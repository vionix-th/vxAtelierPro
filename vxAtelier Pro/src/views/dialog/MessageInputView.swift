import Observation
import SwiftUI

struct MessageInputView: View {
    var dialog: ConversationItem? = nil
    var streamingState: StreamingState

    var focusInputOnAppear: Bool = vxAtelierPro.macOS

    @FocusState private var isInputFocused: Bool

    @State private var message: String = ""
    @State private var isPromptTemplatesPresented: Bool = false
    @State private var isTaskRunning: Bool = false
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""

    @AppStorage("DialogTextEdit.buttonSize") var buttonSize: Double = AppDefaults
        .dialogTextEditButtonSize
    @AppStorage("AutoNameDialogs") private var autoNameDialogs: Bool = AppDefaults.autoNameDialogs
    @AppStorage("AutoSendDialogTemplates") private var autoSendDialogTemplates: Bool = AppDefaults.autoSendDialogTemplates

    var didSend: ((ConversationItem) -> Void)?

    private func sendMessage(to: ConversationItem) {
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            vxAtelierPro.log.info("Ignoring empty message")
            return
        }

        if to.turns.isEmpty && to.title == AppDefaults.newDialogName && autoNameDialogs {
            vxAtelierPro.log.notice("Auto-naming new dialog")

            let separators = CharacterSet(charactersIn: "\n\r.:;")
            var dialogTitle = message.components(separatedBy: separators).first ?? ""

            if dialogTitle.isEmpty {
                dialogTitle = message
            }

            if dialogTitle.lengthOfBytes(using: .utf8) > 64 {
                dialogTitle = dialogTitle.prefix(64) + "..."
            }

            if !dialogTitle.isEmpty {
                vxAtelierPro.log.notice("Auto-named dialog to '\(dialogTitle)'")
                to.title = dialogTitle
            }
        }

        let currentMessage = message
        isTaskRunning = true

        Task {
            do {
                let expandedMessage = expandVariables(currentMessage, dialog: self.dialog)

                // Use the new unified complete method, which handles streaming and non-streaming
                try await to.complete(expandedMessage, streamingState: streamingState)

                message = ""  // Only clear input after successful completion
                didSend?(to)
                vxAtelierPro.log.notice("Message sent and completed successfully")
            } catch {
                vxAtelierPro.log.error("Failed to complete message - \(error.localizedDescription)")
                errorMessage = error.localizedDescription
                showError = true
                
                let allMessages: [MessageItem] = to.turns.flatMap { turn in [turn.userMessage] + turn.events.map { $0.message } }
                if let lastMessage = allMessages.last, lastMessage.role == "user", lastMessage.content.text == currentMessage {
                    // Optionally implement removal logic if needed
                    vxAtelierPro.log.notice("Would remove user message due to completion error (turn-based model).")
                }
            }
            isTaskRunning = false
            isInputFocused = true
        }
    }

    var body: some View {
        ZStack {
            VStack {
                TextEditor(text: $message)
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
                        if let dialog = self.dialog {
                            sendMessage(to: dialog)
                        }
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
                        isPromptTemplatesPresented = true
                    }) {
                        Image(systemName: "hare")
                            .resizable()
                            .scaledToFit()
                            .frame(width: buttonSize, height: buttonSize)
                    }
                    .padding(.leading, AppDefaults.paddingMedium)
                    .buttonStyle(PlainButtonStyle())
                    .popover(isPresented: $isPromptTemplatesPresented) {
                        PromptTemplateList(
                            category: PromptTemplate.Category.User,
                            onTemplateActivated: { template in
                                message = expandVariables(template.prompt, dialog: self.dialog)
                                isPromptTemplatesPresented = false
                                isInputFocused = true

                                if autoSendDialogTemplates, let dialog = self.dialog {
                                    sendMessage(to: dialog)
                                }
                            })
                        .frame(minWidth: 200, idealWidth: 400, minHeight: 300, idealHeight: 500)
                    }

                    Spacer()

                    Button(action: {
                        if let dialog = self.dialog {
                            sendMessage(to: dialog)
                        } else {
                            vxAtelierPro.log.error("Cannot send message - no dialog available")
                            errorMessage = "No dialog to send to"
                            showError = true
                        }
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
            .disabled(isTaskRunning)

            if isTaskRunning {
                ProgressView()
                    .padding(0)
            }
        }
        .padding(AppDefaults.paddingSmall)
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .onAppear {            
            isInputFocused = self.focusInputOnAppear
        }
    }
}
