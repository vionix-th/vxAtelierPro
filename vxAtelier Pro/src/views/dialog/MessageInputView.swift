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
        message = expandVariables(template.prompt, dialog: conversation)
    }

    func send(autoNameDialogs: Bool) {
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
                autoNameIfNeeded(conversation: conversation, sourceText: textToSend, autoNameDialogs: autoNameDialogs)

                let expandedMessage = expandVariables(textToSend, dialog: conversation)
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

    private func autoNameIfNeeded(conversation: ConversationItem, sourceText: String, autoNameDialogs: Bool) {
        guard autoNameDialogs,
              conversation.turns.isEmpty,
              conversation.title == AppDefaults.newDialogName else { return }

        let separators = CharacterSet(charactersIn: "\n\r.:;")
        var dialogTitle = sourceText.components(separatedBy: separators).first ?? ""

        if dialogTitle.isEmpty {
            dialogTitle = sourceText
        }

        if dialogTitle.lengthOfBytes(using: .utf8) > 64 {
            dialogTitle = dialogTitle.prefix(64) + "..."
        }

        if !dialogTitle.isEmpty {
            vxAtelierPro.log.notice("Auto-named dialog to '\(dialogTitle)'")
            conversation.title = dialogTitle
        }
    }
}

struct MessageInputView: View {
    @FocusState private var isInputFocused: Bool

    @StateObject private var viewModel: MessageInputViewModel
    private let contextConversation: ConversationItem?

    @AppStorage(AppSettings.Keys.dialogTextEditButtonSize) var buttonSize: Double = AppDefaults
        .dialogTextEditButtonSize
    @AppStorage(AppSettings.Keys.autoNameDialogs) private var autoNameDialogs: Bool = AppDefaults.autoNameDialogs
    @AppStorage(AppSettings.Keys.autoSendDialogTemplates) private var autoSendDialogTemplates: Bool = AppDefaults.autoSendDialogTemplates

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
                        viewModel.send(autoNameDialogs: autoNameDialogs)
                        return .handled
                    }
                    #endif

                HStack {
                    Button(action: {

                    }) {
                        Image(systemName: "paperclip")
                            .resizable()
                            .scaledToFit()
                            .frame(width: buttonSize, height: buttonSize)
                    }
                    .buttonStyle(PlainButtonStyle())

                    Button(action: {
                        viewModel.isPromptTemplatesPresented = true
                    }) {
                        Image(systemName: "hare")
                            .resizable()
                            .scaledToFit()
                            .frame(width: buttonSize, height: buttonSize)
                    }
                    .padding(.leading, AppDefaults.paddingMedium)
                    .buttonStyle(PlainButtonStyle())
                    .popover(isPresented: $viewModel.isPromptTemplatesPresented) {
                        PromptTemplateList(
                            category: PromptTemplate.Category.User,
                            onTemplateActivated: { template in
                                viewModel.applyTemplate(template, conversation: contextConversation)
                                viewModel.isPromptTemplatesPresented = false
                                viewModel.isInputFocused = true

                                if autoSendDialogTemplates {
                                    viewModel.send(autoNameDialogs: autoNameDialogs)
                                }
                            })
                        .frame(minWidth: 200, idealWidth: 400, minHeight: 300, idealHeight: 500)
                    }

                    Spacer()

                    Button(action: {
                        viewModel.send(autoNameDialogs: autoNameDialogs)
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
