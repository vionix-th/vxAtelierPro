import SwiftUI
import SwiftData

// MARK: - Model Editor View
struct ModelEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(QueryManager.self) private var queryManager
    
    let model: ModelItem
    @State private var name: String
    @State private var provider: String
    @State private var contextSize: Int
    @State private var capabilities: [ModelCapability]
    
    init(model: ModelItem) {
        self.model = model
        _name = State(initialValue: model.name)
        _provider = State(initialValue: model.provider)
        _contextSize = State(initialValue: model.contextSize)
        _capabilities = State(initialValue: model.capabilities)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Model Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .rounded))
                    
                    Picker("Provider", selection: $provider) {
                        ForEach([
                            ModelProviderUtils.Provider.openAI.rawValue,
                            ModelProviderUtils.Provider.anthropic.rawValue,
                            ModelProviderUtils.Provider.google.rawValue,
                            ModelProviderUtils.Provider.meta.rawValue,
                            ModelProviderUtils.Provider.mistral.rawValue,
                            ModelProviderUtils.Provider.xAI.rawValue,
                            ModelProviderUtils.Provider.deepSeek.rawValue,
                            ModelProviderUtils.Provider.custom.rawValue
                        ], id: \.self) { provider in
                            Text(provider)
                                .font(.system(.body, design: .rounded))
                                .tag(provider)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("Model Information")
                        .font(.system(.headline, design: .rounded))
                        .foregroundColor(.primary)
                        .textCase(nil)
                }
                
                Section {
                    VStack(alignment: .leading, spacing: AppDefaults.paddingMedium) {
                        HStack(spacing: AppDefaults.paddingLarge) {
                            TextField("", value: $contextSize, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 120)
                                .monospacedDigit()
                            
                            Text("tokens")
                                .foregroundColor(.secondary)
                                .font(.system(.body, design: .rounded))
                            
                            Spacer()
                            
                            Menu {
                                Group {
                                    Button("4K (4,096)") { contextSize = 4_096 }
                                    Button("8K (8,192)") { contextSize = 8_192 }
                                    Button("16K (16,384)") { contextSize = 16_384 }
                                }
                                Divider()
                                Group {
                                    Button("32K (32,768)") { contextSize = 32_768 }
                                    Button("128K (131,072)") { contextSize = 131_072 }
                                }
                            } label: {
                                Label("Presets", systemImage: "slider.horizontal.3")
                                    .font(.system(.body, design: .rounded))
                            }
                            .menuStyle(.borderlessButton)
                        }
                        .padding(.vertical, AppDefaults.paddingSmall)
                        
                        Text("Maximum number of tokens the model can process in a single request")
                            .font(.system(.caption, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Context Size")
                        .font(.system(.headline, design: .rounded))
                        .foregroundColor(.primary)
                        .textCase(nil)
                }
                
                Section {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppDefaults.paddingLarge) {
                        ForEach(ModelCapability.allCases.sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { capability in
                            Toggle(isOn: Binding(
                                get: { capabilities.contains(capability) },
                                set: { isEnabled in
                                    if isEnabled {
                                        capabilities.append(capability)
                                    } else {
                                        capabilities.removeAll { $0 == capability }
                                    }
                                }
                            )) {
                                Label {
                                    Text(capability.rawValue)
                                        .font(.system(.body, design: .rounded))
                                } icon: {
                                    Image(systemName: capability.systemName)
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .toggleStyle(.switch)
                            .padding(.vertical, AppDefaults.paddingSmall)
                        }
                    }
                } header: {
                    Text("Capabilities")
                        .font(.system(.headline, design: .rounded))
                        .foregroundColor(.primary)
                        .textCase(nil)
                }
                
                if model.modelContext != nil {
                    Section {
                        Button(role: .destructive) {
                            deleteModel()
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                Text("Delete Model")
                            }
                            .frame(maxWidth: .infinity)
                            .font(.system(.body, design: .rounded))
                        }
                        .buttonStyle(.bordered)
                        .padding(.vertical, AppDefaults.paddingSmall)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(model.modelContext == nil ? "Add Model" : "Edit Model")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(.system(.body, design: .rounded))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .font(.system(.body, design: .rounded))
                        .disabled(name.isEmpty)
                }
            }
        }
    }
    
    private func save() {
        model.name = name
        model.provider = provider
        model.contextSize = contextSize
        model.capabilities = capabilities
        
        do {
            if model.modelContext == nil {
                try queryManager.insert(model)
            } else {
                // If the model already exists, just save the context
                // The insert method already calls saveContext
                try queryManager.saveContext()
            }
            // queryManager.refresh() // Refresh QueryManager after save (already done by insert/saveContext)
            dismiss()
        } catch {
            vxAtelierPro.log.error("Failed to save model \(name): \(error.localizedDescription)")
            // Optionally show an alert to the user here
        }
    }
    
    private func deleteModel() {
        do {
            try queryManager.delete(model)
            // queryManager.refresh() // Refresh QueryManager after delete (already done by delete)
            dismiss()
        } catch {
            vxAtelierPro.log.error("Failed to delete model \(model.name): \(error.localizedDescription)")
            // Optionally show an alert to the user here
        }
    }
} 