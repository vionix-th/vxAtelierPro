import SwiftData
import SwiftUI

struct ConversationComposerView: View {
    @FocusState private var isInputFocused: Bool
    @State private var controller: ConversationComposerController

    private let queryManager: QueryManager
    private let contextConversationID: PersistentIdentifier?

    @AppStorage(AppSettings.Keys.conversationTextEditButtonSize) private var buttonSize = AppDefaults.conversationTextEditButtonSize
    @AppStorage(AppSettings.Keys.autoNameConversations) private var autoNameConversations = AppDefaults.autoNameConversations
    @AppStorage(AppSettings.Keys.autoSendConversationTemplates) private var autoSendConversationTemplates = AppDefaults.autoSendConversationTemplates

    init(
        queryManager: QueryManager,
        responseUseCase: ConversationResponseUseCase? = nil,
        draftStore: ConversationDraftStore,
        contextConversationID: PersistentIdentifier? = nil,
        focusInputOnAppear: Bool = {
            #if os(macOS)
                true
            #else
                false
            #endif
        }(),
        resolveConversation: @escaping @MainActor () throws -> ConversationItem,
        didCompleteConversation: ((PersistentIdentifier) -> Void)? = nil
    ) {
        self.queryManager = queryManager
        self.contextConversationID = contextConversationID
        _controller = State(
            initialValue: ConversationComposerController(
                queryManager: queryManager,
                responseUseCase: responseUseCase,
                draftStore: draftStore,
                focusOnAppear: focusInputOnAppear,
                resolveConversation: resolveConversation,
                didCompleteConversation: didCompleteConversation
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
                        if ModifierKeyState.isShiftPressed() {
                            return .ignored
                        }
                        controller.send(autoNameConversations: autoNameConversations)
                        return .handled
                    }
                    #endif

                HStack {
                    Button {
                        controller.isPromptTemplatesPresented = true
                    } label: {
                        Image(systemName: "hare")
                            .resizable()
                            .scaledToFit()
                            .frame(width: buttonSize, height: buttonSize)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $controller.isPromptTemplatesPresented) {
                        PromptTemplateListView(
                            category: PromptTemplate.Category.User,
                            onTemplateActivated: { templateID in
                                controller.applyTemplate(
                                    id: templateID,
                                    conversation: contextConversationID.flatMap {
                                        queryManager.conversation(with: $0)
                                    }
                                )
                                controller.isPromptTemplatesPresented = false
                                controller.isInputFocused = true
                                if autoSendConversationTemplates {
                                    controller.send(
                                        autoNameConversations: autoNameConversations
                                    )
                                }
                            }
                        )
                        .frame(
                            minWidth: 200,
                            idealWidth: 400,
                            minHeight: 300,
                            idealHeight: 500
                        )
                    }

                    Spacer()

                    Button {
                        controller.send(autoNameConversations: autoNameConversations)
                    } label: {
                        Image(systemName: "location")
                            .resizable()
                            .scaledToFit()
                            .frame(width: buttonSize, height: buttonSize)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(AppDefaults.paddingMedium)
            .background(Color.secondary.opacity(0.2))
            .cornerRadius(AppDefaults.cornerRadiusMedium)
            .disabled(controller.isTaskRunning)

            if controller.isTaskRunning {
                ProgressView()
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
