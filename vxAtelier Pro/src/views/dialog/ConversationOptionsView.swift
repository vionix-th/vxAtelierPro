import SwiftData
import SwiftUI

#if os(iOS)
    import UIKit
#elseif os(macOS)
    import AppKit
#endif

// MARK: - Conversation Options View
/// A view for configuring conversation options including model parameters, system prompt, and avatar.
/// Provides a tabbed interface for organizing different settings categories.
struct ConversationOptionsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Binding var options: ConversationOptions

    @Query(sort: [SortDescriptor(\APIConfigurationItem.name)]) private var apiConfigurations: [APIConfigurationItem]
    
    @State private var isAvatarImageImporting: Bool = false
    @State private var selectedTab = 0

    private var avatarPlaceholder: some View {
        Image(systemName: "person.circle")
            .resizable()
            .scaledToFit()
            .frame(width: AppDefaults.avatarImageSize, height: AppDefaults.avatarImageSize)
            .foregroundColor(.accentColor)
    }

    private var parameterControls: [ConversationParameterControl] {
        ConversationParameterProjection.controls(
            for: options,
            apiConfiguration: options.apiConfiguration
        )
    }

    @ViewBuilder
    private func apiConfigurationPicker() -> some View {
        LabeledContent("API Configuration") {
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
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            selectedPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack {
                Spacer()
                Button("Done") {
                    vxAtelierPro.log.debug("Done button pressed")
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        #if os(macOS)
            .presentationSizing(.page)
        #endif
        .onChange(of: options.apiConfiguration) {
            if let config = options.apiConfiguration {
                vxAtelierPro.log.info("API configuration changed, updating defaults")
                let provider = config.providerIDEnum
                options.applyAPIConfigurationDefaults(replaceSelectedModel: true)
                let defaultModel = options.selectedModelID ?? ""
                vxAtelierPro.log.info("Set default model to \(defaultModel) for provider \(provider.displayName)")
            }
        }
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Conversation Options")
                .font(.title2)
                .fontWeight(.semibold)

            Picker("Options Section", selection: $selectedTab) {
                Label("Parameters", systemImage: "slider.horizontal.3").tag(0)
                Label("Tools", systemImage: "wrench.and.screwdriver").tag(1)
                Label("General", systemImage: "gearshape").tag(2)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var selectedPane: some View {
        switch selectedTab {
        case 0:
            parametersPane
        case 1:
            toolsPane
        default:
            generalPane
        }
    }

    private var parametersPane: some View {
        Form {
            apiConfigurationPicker()

            Section("Model Parameters") {
                let controls = parameterControls
                if !controls.isEmpty {
                    ForEach(controls) { control in
                        ParameterControlView(
                            control: control,
                            apiConfiguration: options.apiConfiguration,
                            onValueChanged: { value in
                                options.setParameterValue(control.parameterID, value: value)
                            },
                            onEnabledChanged: { isEnabled in
                                options.setParameterEnabled(control.parameterID, enabled: isEnabled)
                            }
                        )
                    }
                } else {
                    Text("No parameters configured")
                        .foregroundColor(.gray)
                        .italic()
                }
            }
            .disabled(options.apiConfiguration == nil)
        }
        .formStyle(.grouped)
    }

    private var toolsPane: some View {
        Form {
            Section("Available Tools") {
                HStack {
                    Button("Enable All Tools") {
                        for tool in LLMToolRegistry.shared.getTools() {
                            options.setToolEnabled(tool.name, enabled: true)
                        }
                    }
                    .buttonStyle(.bordered)

                    Button("Disable All Tools") {
                        for tool in LLMToolRegistry.shared.getTools() {
                            options.setToolEnabled(tool.name, enabled: false)
                        }
                    }
                    .buttonStyle(.bordered)
                }

                if LLMToolRegistry.shared.getTools().isEmpty {
                    Text("No tools available")
                        .foregroundColor(.gray)
                        .italic()
                } else {
                    ForEach(LLMToolRegistry.shared.getTools(), id: \.name) { tool in
                        LabeledContent {
                            Toggle("", isOn: Binding(
                                get: { options.isToolEnabled(tool.name) },
                                set: { isEnabled in
                                    options.setToolEnabled(tool.name, enabled: isEnabled)
                                }
                            ))
                            .labelsHidden()
                            .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(tool.name)
                                Text(tool.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        if options.isToolEnabled(tool.name),
                           let configurableTool = tool as? any ConfigurableLLMTool {
                            LabeledContent {
                                ToolConfigurationView(
                                    tool: configurableTool,
                                    configuration: Binding(
                                        get: {
                                            options.getToolConfiguration(tool.name) ?? configurableTool.defaultConfiguration()
                                        },
                                        set: {
                                            options.setToolConfiguration(tool.name, configuration: $0)
                                        }
                                    )
                                )
                            } label: {
                                Text("\(tool.name) Configuration")
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var generalPane: some View {
        Form {
            Section("Display") {
                Toggle("Enable Markdown Rendering", isOn: $options.isMarkdownEnabled)

                Text("When enabled, messages will be rendered with Markdown formatting including code blocks, lists, and formatting.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Avatar") {
                LabeledContent("Current Avatar") {
                    AvatarView(
                        imageData: options.avatarImageData,
                        size: AppDefaults.avatarImageSize,
                        strokeWidth: AppDefaults.avatarStrokeWidth
                    )
                }

                LabeledContent("Avatar Image") {
                    HStack {
                        Button(action: {
                            vxAtelierPro.log.debug("Avatar image button tapped")
                            isAvatarImageImporting = true
                        }) {
                            Text(options.avatarImageData == nil ? "Add" : "Change")
                        }
                        .buttonStyle(.bordered)

                        if options.avatarImageData != nil {
                            Button(role: .destructive) {
                                vxAtelierPro.log.debug("Avatar image removed")
                                options.avatarImageData = nil
                            } label: {
                                Text("Remove")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
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
            TextField("", text: $promptValue)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("System Prompt")
            
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
                            PromptTemplateListView(category: PromptTemplate.Category.System) { template in
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
struct ParameterControlView: View {
    let control: ConversationParameterControl
    let apiConfiguration: APIConfigurationItem?
    let onValueChanged: (JSONValue?) -> Void
    let onEnabledChanged: (Bool) -> Void
    @State private var isModelPickerPresented: Bool = false

    var body: some View {
        LabeledContent {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: AppDefaults.paddingMedium) {
                    parameterValueControl
                        .layoutPriority(1)
                    enabledToggle
                }

                VStack(alignment: .trailing, spacing: AppDefaults.paddingSmall) {
                    parameterValueControl
                    enabledToggle
                }
            }
            .disabled(!control.isValueEditable)
            .opacity(control.isValueEditable ? 1 : 0.55)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(control.displayName)
                    .font(.body)
                    .help(control.description)
                    .foregroundColor(control.isValueEditable ? .primary : .secondary)
                parameterStateBadges
            }
        }
    }

    private var enabledToggle: some View {
        Toggle("", isOn: Binding(
            get: { control.isEnabled },
            set: onEnabledChanged
        ))
        .labelsHidden()
        .toggleStyle(SwitchToggleStyle(tint: .accentColor))
        .disabled(!control.canToggleEnabled)
        .help(enabledToggleHelp)
    }

    @ViewBuilder
    private var parameterValueControl: some View {
        switch control.controlType {
        case .textField:
            if control.parameterID == .systemPrompt {
                SystemPromptEditor(promptValue: stringBinding)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                textFieldControl(for: control.valueType)
            }
        case .stepper:
            stepperControl(for: control.valueType)
        case .slider:
            sliderControl(for: control.valueType)
        case .toggle:
            toggleControl()
        case .picker:
            pickerControl(for: control.valueType)
        }
    }

    @ViewBuilder
    private var parameterStateBadges: some View {
        HStack(spacing: 6) {
            if control.required {
                Text("Required")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Text(control.isAvailable ? "Available" : "Unavailable")
                .font(.caption2)
                .foregroundColor(control.isAvailable ? .secondary : .red)
            if !control.isMapped {
                Text("Unmapped")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
        }
    }

    private var enabledToggleHelp: String {
        if control.required {
            return "Required parameters are always enabled."
        }
        if !control.isAvailable {
            return "Unavailable parameters cannot be sent."
        }
        if !control.isMapped {
            return "Unmapped parameters cannot be sent."
        }
        return "Controls whether this parameter is sent with requests."
    }

    private var stringBinding: Binding<String> {
        Binding(
            get: { control.value?.stringValue ?? "" },
            set: { onValueChanged(.string($0)) }
        )
    }

    private var intBinding: Binding<Double> {
        Binding(
            get: { Double(control.value?.integerValue ?? Int(control.minValue ?? 0)) },
            set: { onValueChanged(.integer(Int($0))) }
        )
    }

    private var doubleBinding: Binding<Double> {
        Binding(
            get: { control.value?.doubleValue ?? control.minValue ?? 0 },
            set: { onValueChanged(.number($0)) }
        )
    }

    @ViewBuilder
    private func textFieldControl(for valueType: LLMParameterValueType) -> some View {
        switch valueType {
        case .string:
            if control.parameterID == .model {
                HStack {
                    TextField("", text: Binding(
                        get: { control.value?.stringValue ?? "" },
                        set: { onValueChanged(.string($0)) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(control.displayName)

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
                            selectedModel: control.value?.stringValue ?? "",
                            onModelSelected: { modelID in
                                onValueChanged(.string(modelID))
                            },
                            apiConfiguration: config
                        )
                    }
                }
            } else {
                TextField("", text: stringBinding)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(control.displayName)
            }
        case .integer:
            TextField("", value: Binding(
                get: { control.value?.integerValue ?? 0 },
                set: { onValueChanged(.integer($0)) }
            ), formatter: NumberFormatter())
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(control.displayName)
        case .float:
            TextField("", value: Binding(
                get: { control.value?.doubleValue ?? 0 },
                set: { onValueChanged(.number($0)) }
            ), formatter: NumberFormatter())
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(control.displayName)
        case .boolean:
            TextField("", text: Binding(
                get: { (control.value?.boolValue ?? false) ? "true" : "false" },
                set: { onValueChanged(.boolean($0.lowercased() == "true")) }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(control.displayName)
        }
    }

    @ViewBuilder
    private func stepperControl(for valueType: LLMParameterValueType) -> some View {
        numericControl(for: valueType, useStepper: true)
    }

    @ViewBuilder
    private func sliderControl(for valueType: LLMParameterValueType) -> some View {
        numericControl(for: valueType, useStepper: false)
    }

    @ViewBuilder
    private func numericControl(for valueType: LLMParameterValueType, useStepper: Bool) -> some View {
        switch valueType {
        case .integer:
            numericInput(
                value: intBinding,
                minValue: control.minValue ?? 0,
                maxValue: control.maxValue ?? 10,
                step: control.step ?? 1,
                isInteger: true,
                useStepper: useStepper
            )
        case .float:
            numericInput(
                value: doubleBinding,
                minValue: control.minValue ?? 0,
                maxValue: control.maxValue ?? 1,
                step: control.step ?? 0.1,
                isInteger: false,
                useStepper: useStepper
            )
        default:
            Text("Unsupported numeric parameter")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func numericInput(
        value: Binding<Double>,
        minValue: Double,
        maxValue: Double,
        step: Double,
        isInteger: Bool,
        useStepper: Bool
    ) -> some View {
        HStack(spacing: AppDefaults.paddingMedium) {
            if useStepper {
                Stepper(value: value, in: minValue...maxValue, step: step) {
                    TextField("", value: value, formatter: HybridNumericInputView.numberFormatter(isInteger: isInteger))
                        .textFieldStyle(.roundedBorder)
                }
            } else {
                Slider(value: value, in: minValue...maxValue, step: step)
                    .frame(maxWidth: .infinity)

                TextField("", value: value, formatter: HybridNumericInputView.numberFormatter(isInteger: isInteger))
                    .textFieldStyle(.roundedBorder)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func toggleControl() -> some View {
        Toggle("", isOn: Binding(
            get: { control.value?.boolValue ?? false },
            set: { onValueChanged(.boolean($0)) }
        ))
        .labelsHidden()
        .toggleStyle(SwitchToggleStyle(tint: .accentColor))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func pickerControl(for valueType: LLMParameterValueType) -> some View {
        if let options = control.options, !options.isEmpty {
            Picker("", selection: Binding(
                get: { control.value?.stringValue ?? options.first ?? "" },
                set: { onValueChanged(.string($0)) }
            )) {
                ForEach(options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
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
    let tool: any ConfigurableLLMTool
    @Binding var configuration: [String: JSONValue]

    var body: some View {
        HStack {
            Button {
                vxAtelierPro.log.debug("Opening configuration editor")
                // Convert configuration to JSON for editing
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                if let jsonData = try? encoder.encode(JSONValue.object(configuration)),
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
                        let encoder = JSONEncoder()
                        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                        if let jsonData = try? encoder.encode(JSONValue.object(tool.defaultConfiguration())),
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
                           let parsedConfig = try? JSONDecoder().decode(JSONValue.self, from: jsonData).objectValue {
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
