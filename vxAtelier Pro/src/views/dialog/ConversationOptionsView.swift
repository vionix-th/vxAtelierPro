import SwiftData
import SwiftUI

#if os(iOS)
    import UIKit
#elseif os(macOS)
    import AppKit
#endif

// MARK: - Dialog Options View
/// A view for configuring dialog options including model parameters, system prompt, and avatar.
/// Provides a tabbed interface for organizing different settings categories.
struct ConversationOptionsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(QueryManager.self) private var queryManager
    @Binding var options: ConversationOptions

    @Query(sort: [SortDescriptor(\APIConfigurationItem.name)]) private var apiConfigurations: [APIConfigurationItem]
    @Query(sort: [SortDescriptor(\ModelItem.name)]) private var models: [ModelItem]
    
    @State private var isAvatarImageImporting: Bool = false
    @State private var selectedTab = 0

    private var avatarPlaceholder: some View {
        Image(systemName: "person.circle")
            .resizable()
            .scaledToFit()
            .frame(width: AppDefaults.avatarImageSize, height: AppDefaults.avatarImageSize)
            .foregroundColor(.accentColor)
    }

    @ViewBuilder
    private func apiConfigurationPicker() -> some View {
        HStack {
            Text("API Configuration")
                .frame(width: 150, alignment: .leading)
            Picker("", selection: $options.apiConfiguration) {
                ForEach(apiConfigurations) { config in
                    Text(config.name).tag(config as APIConfigurationItem?)
                }
            }
            .pickerStyle(.menu)
            .disabled(apiConfigurations.isEmpty)
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            // MARK: Parameters Tab (Tab 0)
            VStack {
                ScrollView {
                    VStack(spacing: AppDefaults.paddingLarge) {
                        apiConfigurationPicker()
                        
                        // Use SettingsSectionView for parameters
                        SettingsSectionView(title: "Model Parameters") {
                            VStack(spacing: AppDefaults.paddingMedium) {
                                if !options.parameters.isEmpty {
                                    ForEach(
                                        options.parameters.sorted { p1, p2 in
                                            if p1.required != p2.required {
                                                return p1.required
                                            }
                                            if !p1.required && !p2.required && p1.isEnabled != p2.isEnabled {
                                                return p1.isEnabled
                                            }
                                            return p1.displayName.localizedCaseInsensitiveCompare(p2.displayName) == .orderedAscending
                                        }, id: \.id
                                    ) { param in
                                        ParameterControlView(parameter: param, apiConfiguration: options.apiConfiguration)
                                    }
                                } else {
                                    Text("No parameters configured")
                                        .foregroundColor(.gray)
                                        .italic()
                                }
                            }
                        }.disabled(options.apiConfiguration == nil)
                    }
                    .padding(.vertical, AppDefaults.paddingLarge)
                }
            }
            .tabItem {
                Label("Parameters", systemImage: "slider.horizontal.3")
            }
            .tag(0)

            // MARK: Tools Tab (Tab 1)
            VStack {
                ScrollView {
                    VStack(spacing: AppDefaults.paddingLarge) {
                        // Use SettingsSectionView for Tools
                        SettingsSectionView(title: "Available Tools") {
                            // Move Enable/Disable buttons inside
                            HStack {
                                Button("Enable All Tools") {
                                    for tool in AIToolRegistry.shared.getTools() {
                                        options.setToolEnabled(tool.name, enabled: true)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .padding(.horizontal, AppDefaults.paddingSmall)

                                Button("Disable All Tools") {
                                    for tool in AIToolRegistry.shared.getTools() {
                                        options.setToolEnabled(tool.name, enabled: false)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .padding(.horizontal, AppDefaults.paddingSmall)
                            }
                            .padding(.bottom, AppDefaults.paddingMedium) // Add some spacing below buttons

                            // Existing tools list VStack
                            VStack(spacing: 0) {
                                if AIToolRegistry.shared.getTools().isEmpty {
                                    Text("No tools available")
                                        .foregroundColor(.gray)
                                        .italic()
                                        .frame(maxWidth: .infinity, alignment: .center)
                                        .padding()
                                } else {
                                    ForEach(AIToolRegistry.shared.getTools(), id: \.name) { tool in
                                        VStack(spacing: 0) {
                                            HStack {
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(tool.name)
                                                        .font(.headline)
                                                    Text(tool.description)
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                }
                                                Spacer()
                                                Toggle("", isOn: Binding(
                                                    get: { options.isToolEnabled(tool.name) },
                                                    set: { isEnabled in
                                                        options.setToolEnabled(tool.name, enabled: isEnabled)
                                                    }
                                                ))
                                                .labelsHidden()
                                                .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                                            }
                                            .padding(.vertical, 8)
                                            
                                            if options.isToolEnabled(tool.name) {
                                                if let configValues = tool.getDefaultConfiguration(), !configValues.isEmpty {
                                                    ToolConfigurationView(
                                                        tool: tool, 
                                                        configuration: Binding(
                                                            get: { 
                                                                options.getToolConfiguration(tool.name) ?? tool.getDefaultConfiguration() ?? [:] 
                                                            },
                                                            set: { 
                                                                options.setToolConfiguration(tool.name, configuration: $0) 
                                                            }
                                                        )
                                                    )
                                                    .padding(.leading, 34)
                                                    .padding(.bottom, 8)
                                                }
                                            }
                                            
                                            if tool.name != AIToolRegistry.shared.getTools().last?.name {
                                                Divider()
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, AppDefaults.paddingLarge)
                }
            }
            .tabItem {
                Label("Tools", systemImage: "wrench.and.screwdriver")
            }
            .tag(1)

            // MARK: General Tab (Tab 2)
            VStack {
                ScrollView {
                    VStack(spacing: AppDefaults.paddingLarge) {
                        // Use SettingsSectionView for General Options
                        SettingsSectionView(title: "General Options") { 
                            VStack(spacing: AppDefaults.paddingMedium) {
                                // Display Options
                                VStack(alignment: .leading, spacing: AppDefaults.paddingMedium) {
                                    Text("Display")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    
                                    Toggle("Enable Markdown Rendering", isOn: $options.isMarkdownEnabled)
                                        .padding(.vertical, 4)
                                    
                                    Text("When enabled, messages will be rendered with Markdown formatting including code blocks, lists, and formatting.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Divider()
                                    .padding(.vertical, AppDefaults.paddingMedium)
                                
                                // Avatar
                                VStack(alignment: .leading, spacing: AppDefaults.paddingMedium) {
                                    Text("Avatar")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    
                                    HStack {
                                        Spacer()
                                        
                                        // Ensure AvatarView uses the bound options data
                                        AvatarView(
                                            imageData: options.avatarImageData, 
                                            size: AppDefaults.avatarImageSize, 
                                            strokeWidth: AppDefaults.avatarStrokeWidth
                                        )
                                        
                                        Spacer()
                                    }
                                    .padding(.vertical, AppDefaults.paddingSmall)

                                    HStack {
                                        Spacer()
                                        
                                        Button(action: {
                                            vxAtelierPro.log.debug("Avatar image button tapped")
                                            isAvatarImageImporting = true
                                        }) {
                                            Text(options.avatarImageData == nil ? "Add Avatar" : "Change Avatar")
                                        }
                                        .buttonStyle(.bordered)

                                        if options.avatarImageData != nil {
                                            Button(role: .destructive) {
                                                vxAtelierPro.log.debug("Avatar image removed")
                                                // Update bound options data
                                                options.avatarImageData = nil
                                            } label: {
                                                Text("Remove Avatar")
                                            }
                                            .buttonStyle(.bordered)
                                        }
                                        
                                        Spacer()
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, AppDefaults.paddingLarge)
                }
            }
            .tabItem {
                Label("General", systemImage: "gearshape")
            }
            .tag(2)
        }
        .padding(AppDefaults.paddingMedium)
        .onChange(of: options.apiConfiguration) {
            if let config = options.apiConfiguration {
                vxAtelierPro.log.info("API configuration changed, updating parameters")
                options.setupAiRequestArguments(for: config, modelContext: modelContext)
                
                // Set the default model based on the configuration or fallback
                let provider = AIServiceProvider.detectProvider(from: config)
                let defaultModel: String = {
                    if let model = config.defaultModel, !model.isEmpty {
                        return model
                    }
                    switch provider {
                        case .openAI: return AppDefaults.OpenAi.model
                        case .anthropic: return AppDefaults.Anthropic.model
                        case .xAI: return AppDefaults.XAI.model
                        case .deepSeek: return AppDefaults.DeepSeek.model
                    }
                }()
                options.setParameterValue(name: "model", value: defaultModel)
                vxAtelierPro.log.info("Set default model to \(defaultModel) for provider \(provider.rawValue)")
            }
        }
        .toolbar {
            ToolbarItem {
                Button("Close") {
                    vxAtelierPro.log.debug("Close button pressed")
                    dismiss()
                }
            }
        }
        .navigationTitle("Dialog Options")
        #if os(macOS)
            .fileImporter(isPresented: $isAvatarImageImporting, allowedContentTypes: [.image]) { result in
                switch result {
                case .success(let url):
                    vxAtelierPro.log.debug("File importer returned URL: \(url)")
                    do {
                        let imageData = try FileHelper.loadImageData(from: url)
                        if let image: NSImage = NSImage(data: imageData) {
                            vxAtelierPro.log.info("Successfully created NSImage from data")
                            options.avatarImageData = image.tiffRepresentation
                        } else {
                            vxAtelierPro.log.error("Failed to create NSImage from data")
                        }
                    } catch let fileError as FileHelper.FileError {
                        vxAtelierPro.log.error("FileHelper error loading image: \(fileError)")
                        // Handle specific FileHelper errors if needed
                    } catch {
                        vxAtelierPro.log.error("Unexpected error loading image: \(error.localizedDescription)")
                    }
                    
                case .failure(let error):
                    vxAtelierPro.log.error("Failed to import avatar image - \(error.localizedDescription)")
                }
            }
        #elseif os(iOS)
            .sheet(isPresented: $isAvatarImageImporting) {
                ImagePicker(selectedImage: { image in
                    if let imageData = image.jpegData(compressionQuality: 0.8) {
                        vxAtelierPro.log.info("Updated avatar image from image picker")
                        // Update bound options data
                        options.avatarImageData = imageData
                    } else {
                        vxAtelierPro.log.error("Failed to get JPEG data for image from picker")
                    }
                })
            }
        #endif
    }
}

// MARK: - System Prompt Editor
/// A view for editing system prompts with template support.
/// Provides a single-line view with a popover editor and template selection.
private struct SystemPromptEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var promptValue: String
    @State private var isTemplatesPresented: Bool = false
    @State private var isEditorPresented: Bool = false

    var body: some View {
        HStack {
            TextField("System Prompt", text: $promptValue)
                .textFieldStyle(.roundedBorder)
            
            Button {
                isEditorPresented = true
            } label: {
                Image(systemName: "text.quote")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isEditorPresented) {
                VStack(alignment: .leading, spacing: AppDefaults.paddingMedium) {
                    HStack {
                        Text("System Prompt")
                            .font(.headline)
                        
                        Spacer()
                        
                        Button {
                            vxAtelierPro.log.debug("Opening prompt templates")
                            isTemplatesPresented = true
                        } label: {
                            Image(systemName: "hare")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $isTemplatesPresented) {
                            PromptTemplateList(category: PromptTemplate.Category.System) { template in
                                vxAtelierPro.log.info("Applied template: \(template.name)")
                                promptValue = expandVariables(template.prompt)
                                isTemplatesPresented = false
                            }
                            .frame(minWidth: 200, idealWidth: 400, minHeight: 300, idealHeight: 500)
                            .onAppear {
                                vxAtelierPro.log.debug("Templates popover appeared")
                            }
                        }
                    }
                    .padding(.horizontal, AppDefaults.paddingMedium)
                    
                    TextEditor(text: $promptValue)
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 400, height: 200)
                        .cornerRadius(AppDefaults.cornerRadiusMedium)
                        .padding(AppDefaults.paddingSmall)
                }
                .padding()
            }
        }
    }
}

// MARK: - Parameter Control View
/// A view that dynamically renders controls for different parameter types.
/// Supports various input types including text fields, steppers, sliders, toggles, and pickers.
struct ParameterControlView: View {
    @ObservedObject var parameter: AiRequestArgument
    @State private var isModelPickerPresented: Bool = false
    let apiConfiguration: APIConfigurationItem?
    
    init(parameter: AiRequestArgument, apiConfiguration: APIConfigurationItem?) {
        self.parameter = parameter
        self.apiConfiguration = apiConfiguration
    }

    var body: some View {
        let controlType = AiArgumentControlType(rawValue: parameter.controlType) ?? .textField
        let valueType = AiArgumentValueType(rawValue: parameter.valueType) ?? .string

        HStack(spacing: AppDefaults.paddingMedium) {
            Text(parameter.displayName)
                .frame(width: 130, alignment: .leading)
                .help(parameter.paramDescription)
                .foregroundColor(parameter.isEnabled ? .primary : .secondary)

            if parameter.isEnabled {
                switch controlType {
                case .textField:
                    if parameter.name == "system_prompt" {
                        SystemPromptEditor(promptValue: Binding(
                            get: { parameter.stringValue ?? "" },
                            set: { parameter.setValue($0) }
                        ))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        textFieldControl(for: valueType)
                    }
                case .stepper:
                    stepperControl(for: valueType)
                case .slider:
                    sliderControl(for: valueType)
                case .toggle:
                    toggleControl()
                case .picker:
                    pickerControl(for: valueType)
                }
            } else {
                Text("Not used")
                    .foregroundColor(.secondary)
                    .italic()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !parameter.required {
                Toggle("", isOn: Binding(
                    get: { parameter.isEnabled },
                    set: { parameter.isEnabled = $0 }
                ))
                .labelsHidden()
                .toggleStyle(SwitchToggleStyle(tint: .accentColor))
            }
        }
    }

    // MARK: - Control Builders
    
    @ViewBuilder
    private func textFieldControl(for valueType: AiArgumentValueType) -> some View {
        switch valueType {
        case .string:
            if parameter.name == "model" {
                HStack {
                    TextField(parameter.name, text: Binding(
                        get: { parameter.stringValue ?? "" },
                        set: { parameter.setValue($0) }
                    ))
                    .textFieldStyle(.roundedBorder)

                    Button {
                        vxAtelierPro.log.debug("Opening model picker")
                        isModelPickerPresented = true
                    } label: {
                        Image(systemName: "square.grid.2x2")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .sheet(isPresented: $isModelPickerPresented) {
                    if let config = apiConfiguration {
                        ModelSelectionView(
                            selectedModel: parameter.stringValue ?? "",
                            onModelSelected: { modelId in
                                parameter.setValue(modelId)
                            },
                            currentProvider: AIServiceProvider.detectProvider(from: config)
                        )
                    }
                }
            } else {
                TextField(parameter.name, text: Binding(
                    get: { parameter.stringValue ?? "" },
                    set: { parameter.setValue($0) }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .integer:
            TextField(parameter.name, value: Binding(
                get: { parameter.intValue ?? 0 },
                set: { parameter.setValue($0) }
            ), formatter: NumberFormatter())
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: .infinity, alignment: .leading)
        case .float:
            TextField(parameter.name, value: Binding(
                get: { parameter.floatValue ?? 0.0 },
                set: { parameter.setValue($0) }
            ), formatter: NumberFormatter())
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: .infinity, alignment: .leading)
        case .boolean:
            TextField(parameter.name, text: Binding(
                get: { (parameter.boolValue ?? false) ? "true" : "false" },
                set: { parameter.setValue($0.lowercased() == "true") }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func stepperControl(for valueType: AiArgumentValueType) -> some View {
        switch valueType {
        case .integer:
            let minVal = Double(parameter.minValue ?? 0)
            let maxVal = Double(parameter.maxValue ?? 10)
            let stepVal = Double(parameter.step ?? 1)
            HybridNumericInputView(
                label: nil,
                value: Binding(
                    get: { Double(parameter.intValue ?? Int(minVal)) },
                    set: { parameter.setValue(Int($0)) }
                ),
                minValue: minVal,
                maxValue: maxVal,
                step: stepVal,
                isInteger: true,
                useStepper: true
            )
        case .float:
            let minVal = parameter.minValue ?? 0.0
            let maxVal = parameter.maxValue ?? 1.0
            let stepVal = parameter.step ?? 0.1
            HybridNumericInputView(
                label: nil,
                value: Binding(
                    get: { parameter.floatValue ?? minVal },
                    set: { parameter.setValue($0) }
                ),
                minValue: minVal,
                maxValue: maxVal,
                step: stepVal,
                isInteger: false,
                useStepper: true
            )
        default:
            Text("Unsupported type for stepper")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func sliderControl(for valueType: AiArgumentValueType) -> some View {
        switch valueType {
        case .integer:
            let minVal = Double(parameter.minValue ?? 0)
            let maxVal = Double(parameter.maxValue ?? 10)
            let stepVal = Double(parameter.step ?? 1)
            HybridNumericInputView(
                label: nil,
                value: Binding(
                    get: { Double(parameter.intValue ?? Int(minVal)) },
                    set: { parameter.setValue(Int($0)) }
                ),
                minValue: minVal,
                maxValue: maxVal,
                step: stepVal,
                isInteger: true,
                useStepper: false
            )
        case .float:
            let minVal = parameter.minValue ?? 0.0
            let maxVal = parameter.maxValue ?? 1.0
            let stepVal = parameter.step ?? 0.1
            HybridNumericInputView(
                label: nil,
                value: Binding(
                    get: { parameter.floatValue ?? minVal },
                    set: { parameter.setValue($0) }
                ),
                minValue: minVal,
                maxValue: maxVal,
                step: stepVal,
                isInteger: false,
                useStepper: false
            )
        default:
            Text("Unsupported type for slider")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func toggleControl() -> some View {
        Toggle("", isOn: Binding(
            get: { parameter.boolValue ?? false },
            set: { parameter.setValue($0) }
        ))
        .labelsHidden()
        .toggleStyle(SwitchToggleStyle(tint: .accentColor))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func pickerControl(for valueType: AiArgumentValueType) -> some View {
        if let options = parameter.options, !options.isEmpty {
            switch valueType {
            case .string:
                Picker("", selection: Binding(
                    get: { parameter.stringValue ?? options.first ?? "" },
                    set: { parameter.setValue($0) }
                )) {
                    ForEach(options, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            case .integer:
                Picker("", selection: Binding(
                    get: { String(parameter.intValue ?? 0) },
                    set: { parameter.setValue(Int($0) ?? 0) }
                )) {
                    ForEach(options, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            case .float:
                Picker("", selection: Binding(
                    get: { String(parameter.floatValue ?? 0.0) },
                    set: { parameter.setValue(Double($0) ?? 0.0) }
                )) {
                    ForEach(options, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            case .boolean:
                Picker("", selection: Binding(
                    get: { (parameter.boolValue ?? false) ? "true" : "false" },
                    set: { parameter.setValue($0 == "true") }
                )) {
                    Text("True").tag("true")
                    Text("False").tag("false")
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text("No options available")
                .foregroundColor(.gray)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Tool Configuration View
/// A view for configuring tool-specific settings.
private struct ToolConfigurationView: View {
    @State private var isConfigurationPresented: Bool = false
    @State private var configText: String = "{}"
    let tool: AITool
    @Binding var configuration: [String: Any]

    var body: some View {
        HStack {
            Button {
                vxAtelierPro.log.debug("Opening configuration editor")
                // Convert configuration to JSON for editing
                if let jsonData = try? JSONSerialization.data(withJSONObject: configuration, options: .prettyPrinted),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    configText = jsonString
                } else {
                    configText = "{}"
                }
                isConfigurationPresented = true
            } label: {
                HStack {
                    Text("Configure")
                        .font(.subheadline)
                    Image(systemName: "gear")
                }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $isConfigurationPresented) {
            VStack(alignment: .leading, spacing: AppDefaults.paddingMedium) {
                HStack {
                    Text("Tool Configuration: \(tool.name)")
                        .font(.headline)
                    
                    Spacer()
                    
                    Button {
                        vxAtelierPro.log.notice("Reset configuration")
                        if let defaultConfig = tool.getDefaultConfiguration(),
                           let jsonData = try? JSONSerialization.data(withJSONObject: defaultConfig, options: .prettyPrinted),
                           let jsonString = String(data: jsonData, encoding: .utf8) {
                            configText = jsonString
                        } else {
                            configText = "{}"
                        }
                    } label: {
                        Text("Reset to Default")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, AppDefaults.paddingMedium)
                
                ScrollView {
                    TextEditor(text: $configText)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 200)
                        .cornerRadius(AppDefaults.cornerRadiusMedium)
                        .padding(AppDefaults.paddingSmall)
                }
                
                HStack {
                    Spacer()
                    
                    Button("Cancel") {
                        isConfigurationPresented = false
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Save") {
                        // Try to parse the JSON text back to a dictionary
                        if let jsonData = configText.data(using: .utf8),
                           let parsedConfig = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                            configuration = parsedConfig
                            vxAtelierPro.log.notice("Configuration saved")
                        } else {
                            vxAtelierPro.log.error("Invalid JSON configuration")
                        }
                        isConfigurationPresented = false
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
            .padding()
            .frame(minWidth: 500, minHeight: 300)
        }
    }
}
