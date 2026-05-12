import SwiftUI
import Observation

@MainActor
@Observable
private final class MessageInputController {
    private let queryManager: QueryManager
    private let completionUseCase: ConversationCompletionUseCase
    private let resolveConversation: @MainActor () throws -> ConversationItem
    private let didSend: ((ConversationItem) -> Void)?

    @ObservationIgnored private var sendTask: Task<Void, Never>?
    let draftStore: ConversationDraftStore

    var message: String = ""
    var isPromptTemplatesPresented: Bool = false
    var isTaskRunning: Bool = false
    var showError: Bool = false
    var errorMessage: String = ""
    var isInputFocused: Bool

    init(
        queryManager: QueryManager,
        completionUseCase: ConversationCompletionUseCase? = nil,
        draftStore: ConversationDraftStore,
        focusOnAppear: Bool,
        resolveConversation: @escaping @MainActor () throws -> ConversationItem,
        didSend: ((ConversationItem) -> Void)? = nil
    ) {
        self.queryManager = queryManager
        self.completionUseCase = completionUseCase ?? .shared
        self.draftStore = draftStore
        self.resolveConversation = resolveConversation
        self.didSend = didSend
        self.isInputFocused = focusOnAppear
    }

    func applyTemplate(_ template: PromptTemplate, conversation: ConversationItem?) {
        message = expandVariables(template.prompt, conversation: conversation)
    }

    func send(autoNameConversations: Bool) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            vxAtelierPro.log.info("Ignoring empty message")
            return
        }

        sendTask?.cancel()
        draftStore.reset()
        isTaskRunning = true
        let textToSend = message

        sendTask = Task { @MainActor in
            do {
                let conversation = try resolveConversation()
                autoNameIfNeeded(conversation: conversation, sourceText: textToSend, autoNameConversations: autoNameConversations)

                let expandedMessage = expandVariables(textToSend, conversation: conversation)
                try await completionUseCase.complete(
                    conversation: conversation,
                    message: expandedMessage,
                    draftStore: draftStore
                )
                try queryManager.saveContext()

                message = ""
                didSend?(conversation)
                vxAtelierPro.log.notice("Message sent and completed successfully")
            } catch {
                if Task.isCancelled { return }
                vxAtelierPro.log.error("Failed to complete message - \(error.localizedDescription)")
                errorMessage = error.localizedDescription
                showError = true
            }
            isTaskRunning = false
            isInputFocused = true
        }
    }

    func cancel() {
        sendTask?.cancel()
        draftStore.reset()
        isTaskRunning = false
    }

    private func autoNameIfNeeded(conversation: ConversationItem, sourceText: String, autoNameConversations: Bool) {
        guard autoNameConversations,
              conversation.turns.isEmpty,
              conversation.title == AppDefaults.newConversationName else { return }

        let separators = CharacterSet(charactersIn: "\n\r.:;")
        var conversationTitle = sourceText.components(separatedBy: separators).first ?? ""

        if conversationTitle.isEmpty {
            conversationTitle = sourceText
        }

        if conversationTitle.lengthOfBytes(using: .utf8) > 64 {
            conversationTitle = conversationTitle.prefix(64) + "..."
        }

        if !conversationTitle.isEmpty {
            vxAtelierPro.log.notice("Auto-named conversation to '\(conversationTitle)'")
            conversation.title = conversationTitle
        }
    }
}

struct MessageInputView: View {
    @FocusState private var isInputFocused: Bool

    @State private var controller: MessageInputController
    private let contextConversation: ConversationItem?

    @AppStorage(AppSettings.Keys.conversationTextEditButtonSize) var buttonSize: Double = AppDefaults
        .conversationTextEditButtonSize
    @AppStorage(AppSettings.Keys.autoNameConversations) private var autoNameConversations: Bool = AppDefaults.autoNameConversations
    @AppStorage(AppSettings.Keys.autoSendConversationTemplates) private var autoSendConversationTemplates: Bool = AppDefaults.autoSendConversationTemplates

    init(
        queryManager: QueryManager,
        completionUseCase: ConversationCompletionUseCase? = nil,
        draftStore: ConversationDraftStore,
        contextConversation: ConversationItem? = nil,
        focusInputOnAppear: Bool = vxAtelierPro.macOS,
        resolveConversation: @escaping @MainActor () throws -> ConversationItem,
        didSend: ((ConversationItem) -> Void)? = nil
    ) {
        self.contextConversation = contextConversation
        _controller = State(
            initialValue: MessageInputController(
                queryManager: queryManager,
                completionUseCase: completionUseCase,
                draftStore: draftStore,
                focusOnAppear: focusInputOnAppear,
                resolveConversation: resolveConversation,
                didSend: didSend
            )
        )
    }

    var body: some View {
        @Bindable var controller = controller

        ZStack {
            VStack {
                TextEditor(text: $controller.message)
                    .padding(AppDefaults.paddingSmall)
                    .frame(minHeight: 32, maxHeight: 48)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .font(.callout)
                    .focused($isInputFocused)
                    #if os(macOS)
                    .onKeyPress(.return) {
                        if NSEvent.modifierFlags.contains(.shift) {
                            return .ignored
                        }
                        controller.send(autoNameConversations: autoNameConversations)
                        return .handled
                    }
                    #endif

                HStack {
                    Button(action: {
                        controller.isPromptTemplatesPresented = true
                    }) {
                        Image(systemName: "hare")
                            .resizable()
                            .scaledToFit()
                            .frame(width: buttonSize, height: buttonSize)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .popover(isPresented: $controller.isPromptTemplatesPresented) {
                        PromptTemplateList(
                            category: PromptTemplate.Category.User,
                            onTemplateActivated: { template in
                                controller.applyTemplate(template, conversation: contextConversation)
                                controller.isPromptTemplatesPresented = false
                                controller.isInputFocused = true

                                if autoSendConversationTemplates {
                                    controller.send(autoNameConversations: autoNameConversations)
                                }
                            })
                        .frame(minWidth: 200, idealWidth: 400, minHeight: 300, idealHeight: 500)
                    }

                    Spacer()

                    Button(action: {
                        controller.send(autoNameConversations: autoNameConversations)
                    }) {
                        Image(systemName: "location")
                            .resizable()
                            .scaledToFit()
                            .frame(width: buttonSize, height: buttonSize)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(AppDefaults.paddingMedium)
            .background(Color.secondary.opacity(0.2))
            .cornerRadius(AppDefaults.cornerRadiusMedium)
            .disabled(controller.isTaskRunning)

            if controller.isTaskRunning {
                ProgressView()
                    .padding(0)
            }
        }
        .padding(AppDefaults.paddingSmall)
        .alert("Error", isPresented: $controller.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(controller.errorMessage)
        }
        .onAppear {
            isInputFocused = controller.isInputFocused
        }
        .onChange(of: controller.isInputFocused) { _, newValue in
            isInputFocused = newValue
        }
        .onChange(of: isInputFocused) { _, newValue in
            controller.isInputFocused = newValue
        }
    }
}
