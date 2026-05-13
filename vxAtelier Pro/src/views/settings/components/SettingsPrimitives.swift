import SwiftUI

extension ToolbarItemPlacement {
    static var settingsPrimary: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .primaryAction
        #endif
    }

    static var settingsSecondary: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .secondaryAction
        #endif
    }

    static var settingsCancel: ToolbarItemPlacement {
        #if os(iOS)
        .topBarLeading
        #else
        .cancellationAction
        #endif
    }

    static var settingsConfirm: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .confirmationAction
        #endif
    }
}

struct SettingsPage<Content: View>: View {
    let title: String
    var maxWidth: CGFloat = 760
    @ViewBuilder let content: Content

    var body: some View {
        Form {
            content
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .frame(maxWidth: maxWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle(title)
    }
}

struct SettingsListPage<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        content
            .navigationTitle(title)
    }
}

struct SettingsFormSection<Content: View>: View {
    let title: String
    let footer: String?
    @ViewBuilder let content: Content

    init(_ title: String, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        Section {
            content
        } header: {
            Text(title)
        } footer: {
            if let footer {
                Text(footer)
            }
        }
    }
}

struct SettingsToggleRow: View {
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool

    init(_ title: String, subtitle: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        self._isOn = isOn
    }

    var body: some View {
        LabeledContent {
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        } label: {
            SettingsRowLabel(title: title, subtitle: subtitle)
        }
    }
}

struct SettingsPickerRow<Selection: Hashable, Content: View>: View {
    let title: String
    @Binding var selection: Selection
    @ViewBuilder let content: Content

    init(_ title: String, selection: Binding<Selection>, @ViewBuilder content: () -> Content) {
        self.title = title
        self._selection = selection
        self.content = content()
    }

    var body: some View {
        LabeledContent {
            Picker(title, selection: $selection) {
                content
            }
            .labelsHidden()
        } label: {
            Text(title)
        }
    }
}

struct SettingsSliderRow: View {
    let title: String
    let bounds: ClosedRange<Double>
    let step: Double
    @Binding var value: Double

    var body: some View {
        LabeledContent {
            HStack {
                Slider(value: $value, in: bounds, step: step)
                Text(value.formatted(.number.precision(.fractionLength(0))))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 36, alignment: .trailing)
            }
        } label: {
            Text(title)
        }
    }
}

struct SettingsStepperRow: View {
    let title: String
    let bounds: ClosedRange<Int>
    let step: Int
    @Binding var value: Int

    var body: some View {
        LabeledContent {
            Stepper(value: $value, in: bounds, step: step) {
                Text(value.formatted())
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        } label: {
            Text(title)
        }
    }
}

struct SettingsSearchField: View {
    let prompt: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: AppDefaults.paddingMedium) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.roundedBorder)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Clear search")
            }
        }
    }
}

struct SettingsEmptyState: View {
    let title: String
    let systemImage: String
    let description: String

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(description))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SettingsConfirmation: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let confirmTitle: String
    let role: ButtonRole?
    let action: () -> Void

    init(
        title: String,
        message: String,
        confirmTitle: String,
        role: ButtonRole? = .destructive,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.confirmTitle = confirmTitle
        self.role = role
        self.action = action
    }
}

extension View {
    func settingsConfirmationDialog(_ confirmation: Binding<SettingsConfirmation?>) -> some View {
        confirmationDialog(
            confirmation.wrappedValue?.title ?? "",
            isPresented: Binding(
                get: { confirmation.wrappedValue != nil },
                set: { if !$0 { confirmation.wrappedValue = nil } }
            ),
            presenting: confirmation.wrappedValue
        ) { confirmation in
            Button(confirmation.confirmTitle, role: confirmation.role) {
                confirmation.action()
            }
            Button("Cancel", role: .cancel) { }
        } message: { confirmation in
            Text(confirmation.message)
        }
    }
}

struct SettingsEntityAction: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    let role: ButtonRole?
    let handler: () -> Void

    init(
        title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        handler: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.handler = handler
    }
}

struct SettingsEntityList<Item: Identifiable, RowContent: View>: View {
    let items: [Item]
    let emptyTitle: String
    let emptySystemImage: String
    let emptyDescription: String
    let selectionAction: ((Item) -> Void)?
    let rowContent: (Item) -> RowContent
    let actions: (Item) -> [SettingsEntityAction]

    init(
        items: [Item],
        emptyTitle: String,
        emptySystemImage: String,
        emptyDescription: String,
        selectionAction: ((Item) -> Void)? = nil,
        @ViewBuilder rowContent: @escaping (Item) -> RowContent,
        actions: @escaping (Item) -> [SettingsEntityAction] = { _ in [] }
    ) {
        self.items = items
        self.emptyTitle = emptyTitle
        self.emptySystemImage = emptySystemImage
        self.emptyDescription = emptyDescription
        self.selectionAction = selectionAction
        self.rowContent = rowContent
        self.actions = actions
    }

    var body: some View {
        if items.isEmpty {
            SettingsEmptyState(title: emptyTitle, systemImage: emptySystemImage, description: emptyDescription)
        } else {
            List(items) { item in
                let rowActions = actions(item)
                rowContent(item)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectionAction?(item)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        ForEach(rowActions) { action in
                            Button(role: action.role) {
                                action.handler()
                            } label: {
                                Label(action.title, systemImage: action.systemImage)
                            }
                        }
                    }
                    .contextMenu {
                        ForEach(rowActions) { action in
                            Button(role: action.role) {
                                action.handler()
                            } label: {
                                Label(action.title, systemImage: action.systemImage)
                            }
                        }
                    }
            }
        }
    }
}

struct SettingsEntityRows<Item: Identifiable, RowContent: View>: View {
    let items: [Item]
    let emptyTitle: String
    let emptySystemImage: String
    let emptyDescription: String
    let selectionAction: ((Item) -> Void)?
    let rowContent: (Item) -> RowContent
    let actions: (Item) -> [SettingsEntityAction]

    init(
        items: [Item],
        emptyTitle: String,
        emptySystemImage: String,
        emptyDescription: String,
        selectionAction: ((Item) -> Void)? = nil,
        @ViewBuilder rowContent: @escaping (Item) -> RowContent,
        actions: @escaping (Item) -> [SettingsEntityAction] = { _ in [] }
    ) {
        self.items = items
        self.emptyTitle = emptyTitle
        self.emptySystemImage = emptySystemImage
        self.emptyDescription = emptyDescription
        self.selectionAction = selectionAction
        self.rowContent = rowContent
        self.actions = actions
    }

    var body: some View {
        if items.isEmpty {
            LabeledContent {
                VStack(alignment: .leading, spacing: AppDefaults.paddingSmall) {
                    Label(emptyTitle, systemImage: emptySystemImage)
                    Text(emptyDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } label: {
                EmptyView()
            }
        } else {
            ForEach(items) { item in
                let rowActions = actions(item)
                rowContent(item)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectionAction?(item)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        ForEach(rowActions) { action in
                            Button(role: action.role) {
                                action.handler()
                            } label: {
                                Label(action.title, systemImage: action.systemImage)
                            }
                        }
                    }
                    .contextMenu {
                        ForEach(rowActions) { action in
                            Button(role: action.role) {
                                action.handler()
                            } label: {
                                Label(action.title, systemImage: action.systemImage)
                            }
                        }
                    }
            }
        }
    }
}

struct SettingsEntityRow<Accessory: View>: View {
    let title: String
    let subtitle: String?
    let metadata: String?
    let systemImages: [String]
    @ViewBuilder let accessory: Accessory

    init(
        title: String,
        subtitle: String? = nil,
        metadata: String? = nil,
        systemImages: [String] = [],
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.metadata = metadata
        self.systemImages = systemImages
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .center, spacing: AppDefaults.paddingMedium) {
            VStack(alignment: .leading, spacing: AppDefaults.paddingSmall) {
                Text(title)
                    .font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let metadata {
                    Text(metadata)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                accessory
            }
            Spacer(minLength: AppDefaults.paddingMedium)
            ForEach(systemImages, id: \.self) { systemImage in
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, AppDefaults.paddingSmall)
    }
}

private struct SettingsRowLabel: View {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
