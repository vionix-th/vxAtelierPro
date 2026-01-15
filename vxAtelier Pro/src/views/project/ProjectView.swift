import SwiftUI
import SwiftData
import Foundation
import Observation

// MARK: - Project View
struct ProjectView: View {
    // MARK: - Environment & Properties
    @Environment(\.modelContext) private var modelContext: ModelContext   
    @Environment(QueryManager.self) private var queryManager: QueryManager
    @Environment(TTSQueue.self) private var ttsQueue: TTSQueue    
    @Environment(ConversationViewModelStore.self) private var conversationStore: ConversationViewModelStore
    
    // Store the project ID directly in the view
    private let projectID: PersistentIdentifier
    
    var onConversationViewAppear: (ConversationItem) -> Void = { _ in }
    var onRequestOptions: (PersistentIdentifier) -> Void = { _ in }
    
    // Computed property to resolve project by ID
    private var project: ProjectItem? {
        queryManager.allProjects.first { $0.id == projectID }
    }
    
    // MARK: - State
    @State private var projectOptionsIsPresented: Bool = false
    @State private var isPromptTemplatesPresented: Bool = false
    @State private var systemPromptValue: String = ""
    
    @AppStorage("DialogTextEdit.buttonSize") var buttonSize: Double = AppDefaults.dialogTextEditButtonSize
    
    @AppStorage("NavigationMode") private var navigationMode: NavigationMode = .chats
    @AppStorage("SidebarDialogsSortOrderDescending") private var conversationsSortDescending: Bool = true
    @AppStorage("SidebarDialogsSortType") private var conversationsSortTypeRaw: String =
        SidebarSortType.conversationDate.rawValue
    
    private var conversationsSortType: SidebarSortType {
        get { SidebarSortType(rawValue: conversationsSortTypeRaw) ?? .conversationDate }
        set { conversationsSortTypeRaw = newValue.rawValue }
    }
    
    init(projectID: PersistentIdentifier, onConversationViewAppear: @escaping (ConversationItem) -> Void = { _ in }, onRequestOptions: @escaping (PersistentIdentifier) -> Void = { _ in }) {
        self.projectID = projectID
        self.onConversationViewAppear = onConversationViewAppear
        self.onRequestOptions = onRequestOptions
    }
    
    // Backward compatibility initializer
    init(project: ProjectItem, onConversationViewAppear: @escaping (ConversationItem) -> Void = { _ in }, onRequestOptions: @escaping (PersistentIdentifier) -> Void = { _ in }) {
        self.init(projectID: project.id, onConversationViewAppear: onConversationViewAppear, onRequestOptions: onRequestOptions)
    }
    
    // MARK: - Computed Properties
    var filteredConversations: [ConversationItem] {
        guard let project = self.project else { return [] }
        
        let filtered = project.conversations.filter { conversation in
            switch conversation.status {
            case .active:
                return true
            case .archived:
                return navigationMode == .archive
            case .trashed:
                return navigationMode == .trash
            }
        }
        // Sort by selected type and order
        return ConversationSorter.sort(
            filtered,
            descending: conversationsSortDescending,
            sortType: conversationsSortType
        )
    }
    
    // MARK: - View Components

    // Helper function to get system prompt editor
    func systemPromptEditor() -> some View {
        TextEditor(text: $systemPromptValue)
        .onChange(of: project?.defaultOptions) { oldValue, newValue in
            // Update local state when options change
            systemPromptValue = project?.defaultOptions.parameters.first(where: { $0.name == "system_prompt" })?.stringValue ?? ""
        }
        .frame(minHeight: 100)
        .font(.system(.body, design: .monospaced))
        .scrollDisabled(true)
    }

    // System prompt template button
    func promptTemplateButton() -> some View {
        Button {
            vxAtelierPro.log.debug("Opening prompt templates")
            isPromptTemplatesPresented = true
        } label: {
            Image(systemName: "hare")
                .resizable()
                .scaledToFit()
                .frame(minWidth: 20, maxWidth: 20)
        }
        .padding(.trailing, 12)
        .buttonStyle(PlainButtonStyle())
        .popover(isPresented: $isPromptTemplatesPresented) {
            PromptTemplateList(category: PromptTemplate.Category.System, onTemplateActivated: { template in
                vxAtelierPro.log.debug("Applied system prompt template: \(template.name)")
                systemPromptValue = expandVariables(template.prompt)                
                isPromptTemplatesPresented = false
            })
            .frame(minWidth: 200, idealWidth: 400, minHeight: 300, idealHeight: 500)
            .onAppear {
                vxAtelierPro.log.debug("Prompt templates popover appeared")
            }
        }
    }

    // MARK: - View Sections
    
    var sectionSystemPrompt: some View {
        VStack(alignment: .leading, spacing: AppDefaults.paddingMedium) {
            Text("System Prompt")
                .font(.headline)
                .foregroundColor(AppDefaults.sectionHeaderColor)
                .padding(.horizontal, AppDefaults.paddingLarge)
            
            VStack(spacing: AppDefaults.paddingMedium) {
                VStack {
                    ScrollView {
                        systemPromptEditor()
                    }
                    .padding(AppDefaults.paddingSmall)
                    .frame(maxHeight: 100)
                        
                    HStack {
                        promptTemplateButton()
                        Spacer()
                    }
                }
            }
            .padding(AppDefaults.paddingLarge)
            .background(Color.secondary.opacity(AppDefaults.sectionBackgroundOpacity))
            .clipShape(RoundedRectangle(cornerRadius: AppDefaults.cornerRadiusMedium))
            .padding(.horizontal, AppDefaults.paddingLarge)
        }
    }
    
    var sectionDialogs: some View {
        VStack(alignment: .leading, spacing: AppDefaults.paddingMedium) {
            HStack {
                Text("Conversations")
                    .font(.headline)
                    .foregroundColor(AppDefaults.sectionHeaderColor)
                Spacer()
                SidebarSortButton(
                    sortDescending: $conversationsSortDescending,
                    sortTypeRaw: $conversationsSortTypeRaw,
                    allowedTypes: SidebarSortType.allCases
                )
            }
            .padding(.horizontal, AppDefaults.paddingLarge)
            
            // Extract the inner content to reduce complexity
            sectionDialogsContent
            .padding(AppDefaults.paddingLarge)
            .background(Color.secondary.opacity(AppDefaults.sectionBackgroundOpacity))
            .clipShape(RoundedRectangle(cornerRadius: AppDefaults.cornerRadiusMedium))
            .padding(.horizontal, AppDefaults.paddingLarge)
        }
    }
    
    var sectionDialogsContent: some View {
        VStack(spacing: AppDefaults.paddingMedium) {
            VStack {
                ForEach(filteredConversations) { conversation in
                    NavigationLink {
                        ConversationView(
                            viewModel: conversationStore.viewModel(for: conversation.id),
                            onRequestOptions: onRequestOptions
                        )
                            .onAppear() {
                                onConversationViewAppear(conversation)
                            }
                    } label: {
                        NavigationItem(
                            title: Binding(get: { conversation.title} , set: { conversation.title = $0 }),
                            subtitle: conversation.timestamp.formatted(.dateTime.year().month().day().hour().minute()),
                            onDelete: {
                                // Use QueryManager to move to trash (or delete if bookmark)
                                do {
                                    try queryManager.moveItemToTrash(conversation)
                                    vxAtelierPro.log.debug("ProjectView: Moved conversation '\(conversation.title)' to trash via context menu.")
                                } catch {
                                    vxAtelierPro.log.error("ProjectView: Failed to move conversation '\(conversation.title)' to trash via context menu: \(error.localizedDescription)")
                                    // Consider showing an error alert
                                }
                            },
                            onRename: { conversation.title = $0 },
                            imageName: "document",
                            onProjectAssign: { targetProject in
                                vxAtelierPro.log.debug("Assigning conversation '\(conversation.title)' to project '\(targetProject?.name ?? "<nil>")'")
                                conversation.project = targetProject
                                do {
                                    try queryManager.saveContext()
                                } catch {
                                    vxAtelierPro.log.error("ProjectView: Failed to save context after assigning conversation to project: \(error.localizedDescription)")
                                }
                            },
                            onExport: {
                                Task {
                                    do {
                                        vxAtelierPro.log.debug("Exporting project '\(self.project?.name ?? "Unknown")'")
                                        try await DataManager.shared.exportProject(self.project!)
                                    } catch {
                                        vxAtelierPro.log.error("Failed to export project - \(error.localizedDescription)")
                                    }
                                }
                            },
                            conversation: conversation
                        )
                    }
                }                
                .onDelete { indexSet in
                    // Use QueryManager to move to trash (or delete if bookmark)
                    for index in indexSet {
                        // Ensure index is valid before accessing
                        if index < filteredConversations.count {
                            let conversation = filteredConversations[index]
                            do {
                                try queryManager.moveItemToTrash(conversation)
                                vxAtelierPro.log.debug("ProjectView: Moved conversation '\(conversation.title)' to trash via swipe delete.")
                            } catch {
                                vxAtelierPro.log.error("ProjectView: Failed to move conversation '\(conversation.title)' to trash via swipe delete: \(error.localizedDescription)")
                                // Consider showing an error alert
                            }
                        } else {
                            vxAtelierPro.log.warning("ProjectView: Invalid index \(index) encountered in sectionDialogs.onDelete for filteredConversations count \(filteredConversations.count).")
                        }
                    }
                }
            }
            .cornerRadius(AppDefaults.cornerRadiusMedium)
            .padding(AppDefaults.paddingSmall)
        }
    }
    
    // MARK: - View Body
    var body: some View {
        // Extract the main content to reduce complexity
        bodyContent
        .padding(AppDefaults.paddingSmall)
        .onTapGesture {
            hideKeyboard()
        }
    }
    
    var bodyContent: some View {
        VStack{
            ScrollView {
                VStack(spacing: AppDefaults.paddingLarge) {
                    sectionSystemPrompt
                                                     
                    if(filteredConversations.isEmpty) {
                        Spacer()
                        
                        Text("Start a new Conversation by entering your message in the text field below.")
                            .padding(AppDefaults.paddingLarge)
                            .font(.title2)
                    } else {
                        sectionDialogs
                    }
                }
                .padding(.vertical, AppDefaults.paddingLarge)
                
                Spacer()
            }
            
            Divider()
            
            if let project = self.project {
                MessageInputView(dialog: ConversationItem(AppDefaults.newDialogName, options: project.defaultOptions.copy()), streamingState: StreamingState(), didSend: { conversation in
                    vxAtelierPro.log.debug("Created new conversation '\(conversation.title)' in project '\(project.name)'")
                    conversation.project = project
                    do {
                        try queryManager.saveContext()
                    } catch {
                        vxAtelierPro.log.error("ProjectView: Failed to save context after setting project for new conversation: \(error.localizedDescription)")
                    }
                    onConversationViewAppear(conversation)
                }).padding(AppDefaults.paddingSmall)
            }
            
        }
        .navigationTitle(Binding(get: { project?.name ?? "" }, set: { newValue in
            if let project = self.project {
                project.name = newValue
            }
        }))
        .sheet(isPresented: $projectOptionsIsPresented) {
            if let project = self.project {
                ConversationOptionsView(options: Binding(get: { project.defaultOptions }, set: { project.defaultOptions = $0 }))
                    .onDisappear {
                        do {
                            try queryManager.saveContext()
                            vxAtelierPro.log.debug("ProjectView: Saved context after ConversationOptionsView dismissed for project '\(project.name)'.") 
                        } catch {
                            vxAtelierPro.log.error("ProjectView: Failed to save context after ConversationOptionsView dismissed: \(error.localizedDescription)")
                        }
                    }
            }
        }
        .toolbar() {
            Menu {
                // Project Settings
                Button {
                    vxAtelierPro.log.debug("Opening project options for '\(project?.name ?? "Unknown")'")
                    projectOptionsIsPresented = true
                } label: {
                    MenuItemStyle.label("Project Options", systemImage: "slider.horizontal.3")
                }
                .help("Configure project-wide settings and defaults")
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundColor(.gray)
                    .font(.title2)
            }
            .help("Project Actions")
        }
        .onAppear() {
            if let project = self.project {
                systemPromptValue = project.defaultOptions.getParameterValue(name: "system_prompt", defaultValue: "")
            }
        }
        .onChange(of: systemPromptValue) {
            if let project = self.project {
                project.defaultOptions.setParameterValue(name: "system_prompt", value: systemPromptValue)
                do {
                    try queryManager.saveContext()
                } catch {
                    vxAtelierPro.log.error("ProjectView: Failed to save context after changing system prompt: \(error.localizedDescription)")
                }
            }
        }
    }
}
