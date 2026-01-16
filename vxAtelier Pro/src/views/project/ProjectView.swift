import SwiftUI
import SwiftData
import Foundation
import Observation

// MARK: - Project View
struct ProjectView: View {
    // MARK: - Environment & Properties
    @Environment(QueryManager.self) private var queryManager: QueryManager
    @Environment(ConversationViewModelStore.self) private var conversationStore: ConversationViewModelStore
    
    // Store the project ID directly in the view
    private let projectID: PersistentIdentifier
    
    @Binding private var selectedConversationID: PersistentIdentifier?
    var onActiveConversationChange: (PersistentIdentifier?) -> Void = { _ in }
    var onRequestOptions: (PersistentIdentifier) -> Void = { _ in }
    var onDeleteConversation: (ConversationItem) -> Void
    var onExportProject: (ProjectItem) -> Void

    private enum ProjectRoute: Hashable {
        case conversation(PersistentIdentifier)
    }
    
    // Computed property to resolve project by ID
    private var project: ProjectItem? {
        queryManager.allProjects.first { $0.id == projectID }
    }
    
    // MARK: - State
    @State private var projectOptionsIsPresented: Bool = false
    @State private var isPromptTemplatesPresented: Bool = false
    @State private var systemPromptValue: String = ""
    @State private var path: [ProjectRoute] = []
    
    @AppStorage("NavigationMode") private var navigationMode: NavigationMode = .chats
    @AppStorage("ProjectDialogsSortOrderDescending") private var conversationsSortDescending: Bool =
        AppDefaults.projectDialogsSortDescending
    @AppStorage("ProjectDialogsSortType") private var conversationsSortTypeRaw: String =
        AppDefaults.projectDialogsSortType
    
    private var conversationsSortType: SidebarSortType {
        get { SidebarSortType(rawValue: conversationsSortTypeRaw) ?? .conversationDate }
        set { conversationsSortTypeRaw = newValue.rawValue }
    }
    
    init(
        projectID: PersistentIdentifier,
        selectedConversationID: Binding<PersistentIdentifier?> = .constant(nil),
        onActiveConversationChange: @escaping (PersistentIdentifier?) -> Void = { _ in },
        onRequestOptions: @escaping (PersistentIdentifier) -> Void = { _ in },
        onDeleteConversation: @escaping (ConversationItem) -> Void,
        onExportProject: @escaping (ProjectItem) -> Void
    ) {
        self.projectID = projectID
        self._selectedConversationID = selectedConversationID
        self.onActiveConversationChange = onActiveConversationChange
        self.onRequestOptions = onRequestOptions
        self.onDeleteConversation = onDeleteConversation
        self.onExportProject = onExportProject
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
                    NavigationLink(value: ProjectRoute.conversation(conversation.id)) {
                        NavigationItem(
                            title: Binding(get: { conversation.title} , set: { conversation.title = $0 }),
                            subtitle: conversation.timestamp.formatted(.dateTime.year().month().day().hour().minute()),
                            onDelete: {
                                onDeleteConversation(conversation)
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
                                if let project = self.project {
                                    onExportProject(project)
                                } else {
                                    vxAtelierPro.log.warning(
                                        "ProjectView: Export requested but project not resolved for id \(projectID)."
                                    )
                                }
                            },
                            conversation: conversation
                        )
                    }
                }                
                .onDelete { indexSet in
                    for index in indexSet {
                        if index < filteredConversations.count {
                            let conversation = filteredConversations[index]
                            onDeleteConversation(conversation)
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
        NavigationStack(path: $path) {
            bodyContent
                .navigationDestination(for: ProjectRoute.self) { route in
                    switch route {
                    case .conversation(let id):
                        ConversationView(
                            viewModel: conversationStore.viewModel(for: id),
                            onRequestOptions: onRequestOptions
                        )
                        .id(id)
                    }
                }
        }
        .padding(AppDefaults.paddingSmall)
        .onTapGesture {
            hideKeyboard()
        }
        .onAppear {
            if let initialID = selectedConversationID,
               project?.conversations.contains(where: { $0.id == initialID }) == true {
                path = [.conversation(initialID)]
                selectedConversationID = nil
            }
        }
        .onChange(of: path) { _, newValue in
            if case .conversation(let id) = newValue.last {
                onActiveConversationChange(id)
            } else {
                onActiveConversationChange(nil)
            }
        }
        .onChange(of: selectedConversationID) { _, newValue in
            guard let newValue else { return }
            if project?.conversations.contains(where: { $0.id == newValue }) == true {
                path = [.conversation(newValue)]
            }
            selectedConversationID = nil
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
                    path = [.conversation(conversation.id)]
                    onActiveConversationChange(conversation.id)
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
