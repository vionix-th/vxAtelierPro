import SwiftUI

@MainActor
final class MessageInputViewModel: ObservableObject {
    private let queryManager: QueryManager
    private let resolveConversation: @MainActor () throws -> ConversationItem
    private var sendTask: Task<Void, Never>?

    let streamingState: StreamingState

    @Published var message: String = ""
    @Published var isPromptTemplatesPresented: Bool = false
    @Published var isTaskRunning: Bool = false
    @Published var showError: Bool = false
    @Published var errorMessage: String = ""
    @Published var isInputFocused: Bool
    var didSend: ((ConversationItem) -> Void)?

    init(
        queryManager: QueryManager,
        streamingState: StreamingState,
        focusOnAppear: Bool,
        resolveConversation: @escaping @MainActor () throws -> ConversationItem,
        didSend: ((ConversationItem) -> Void)? = nil
    ) {
        self.queryManager = queryManager
        self.streamingState = streamingState
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
        streamingState.reset()
        isTaskRunning = true
        let textToSend = message

        sendTask = Task { @MainActor in
            do {
                let conversation = try resolveConversation()
                autoNameIfNeeded(conversation: conversation, sourceText: textToSend, autoNameConversations: autoNameConversations)

                let expandedMessage = expandVariables(textToSend, conversation: conversation)
                try await conversation.complete(expandedMessage, streamingState: streamingState)
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
        streamingState.reset()
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

    @StateObject private var viewModel: MessageInputViewModel
    private let contextConversation: ConversationItem?

    @AppStorage(AppSettings.Keys.conversationTextEditButtonSize) var buttonSize: Double = AppDefaults
        .conversationTextEditButtonSize
    @AppStorage(AppSettings.Keys.autoNameConversations) private var autoNameConversations: Bool = AppDefaults.autoNameConversations
    @AppStorage(AppSettings.Keys.autoSendConversationTemplates) private var autoSendConversationTemplates: Bool = AppDefaults.autoSendConversationTemplates

    init(
        queryManager: QueryManager,
        streamingState: StreamingState,
        contextConversation: ConversationItem? = nil,
        focusInputOnAppear: Bool = vxAtelierPro.macOS,
        resolveConversation: @escaping @MainActor () throws -> ConversationItem,
        didSend: ((ConversationItem) -> Void)? = nil
    ) {
        self.contextConversation = contextConversation
        _viewModel = StateObject(
            wrappedValue: MessageInputViewModel(
                queryManager: queryManager,
                streamingState: streamingState,
                focusOnAppear: focusInputOnAppear,
                resolveConversation: resolveConversation,
                didSend: didSend
            )
        )
    }

    var body: some View {
        ZStack {
            VStack {
                TextEditor(text: $viewModel.message)
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
                        viewModel.send(autoNameConversations: autoNameConversations)
                        return .handled
                    }
                    #endif

                HStack {
                    Button(action: {
                        viewModel.isPromptTemplatesPresented = true
                    }) {
                        Image(systemName: "hare")
                            .resizable()
                            .scaledToFit()
                            .frame(width: buttonSize, height: buttonSize)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .popover(isPresented: $viewModel.isPromptTemplatesPresented) {
                        PromptTemplateList(
                            category: PromptTemplate.Category.User,
                            onTemplateActivated: { template in
                                viewModel.applyTemplate(template, conversation: contextConversation)
                                viewModel.isPromptTemplatesPresented = false
                                viewModel.isInputFocused = true

                                if autoSendConversationTemplates {
                                    viewModel.send(autoNameConversations: autoNameConversations)
                                }
                            })
                        .frame(minWidth: 200, idealWidth: 400, minHeight: 300, idealHeight: 500)
                    }

                    Spacer()

                    Button(action: {
                        viewModel.send(autoNameConversations: autoNameConversations)
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
            .disabled(viewModel.isTaskRunning)

            if viewModel.isTaskRunning {
                ProgressView()
                    .padding(0)
            }
        }
        .padding(AppDefaults.paddingSmall)
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage)
        }
        .onAppear {
            isInputFocused = viewModel.isInputFocused
        }
        .onChange(of: viewModel.isInputFocused) { _, newValue in
            isInputFocused = newValue
        }
        .onChange(of: isInputFocused) { _, newValue in
            viewModel.isInputFocused = newValue
        }
    }
}
