import SwiftData
import SwiftUI

/// Presentation mode that decides whether settings actions live inline or in the navigation toolbar.
enum SettingsPresentationStyle {
    case appNavigation
    case macSettingsScene
}

/// Environment key for the current settings presentation mode.
private struct SettingsPresentationStyleKey: EnvironmentKey {
    static let defaultValue: SettingsPresentationStyle = .appNavigation
}

/// Shared environment accessors for settings presentation policy.
extension EnvironmentValues {
    var settingsPresentationStyle: SettingsPresentationStyle {
        get { self[SettingsPresentationStyleKey.self] }
        set { self[SettingsPresentationStyleKey.self] = newValue }
    }
}

/// Inline action row used when macOS Settings keeps actions inside page content.
struct SettingsInlineActionRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: AppDefaults.paddingMedium) {
            content
            Spacer(minLength: 0)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

/// Page action region that only renders inline controls in the macOS Settings scene.
struct SettingsPageActionRegion<Content: View>: View {
    @Environment(\.settingsPresentationStyle) private var settingsPresentationStyle
    private let padded: Bool
    @ViewBuilder let content: Content

    init(padded: Bool = true, @ViewBuilder content: () -> Content) {
        self.padded = padded
        self.content = content()
    }

    var body: some View {
        if settingsPresentationStyle == .macSettingsScene {
            SettingsInlineActionRow {
                content
            }
            .padding(.horizontal, padded ? nil : 0)
            .padding(.top, padded ? AppDefaults.paddingMedium : 0)
        }
    }
}

/// iOS settings navigation toolbar adapter for trailing and cancellation actions.
private struct SettingsNavigationActionsModifier<Actions: View, CancellationAction: View>: ViewModifier {
    let actions: Actions
    let cancellationAction: CancellationAction

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    actions
                }
                ToolbarItem(placement: .topBarLeading) {
                    cancellationAction
                }
            }
        #else
        content
        #endif
    }
}

/// Settings navigation toolbar helpers.
extension View {
    func settingsNavigationActions<Actions: View>(
        @ViewBuilder _ actions: () -> Actions
    ) -> some View {
        modifier(
            SettingsNavigationActionsModifier(
                actions: actions(),
                cancellationAction: EmptyView()
            )
        )
    }

    func settingsNavigationActions<Actions: View, CancellationAction: View>(
        @ViewBuilder _ actions: () -> Actions,
        @ViewBuilder cancellation: () -> CancellationAction
    ) -> some View {
        modifier(
            SettingsNavigationActionsModifier(
                actions: actions(),
                cancellationAction: cancellation()
            )
        )
    }
}

/// Shared wrapper that constrains settings page width and applies the title.
private struct SettingsPageContainer<Content: View>: View {
    let title: String
    var maxWidth: CGFloat = 760
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .navigationTitle(title)
    }
}

/// Form-based settings page with grouped styling on macOS.
struct SettingsPage<Content: View>: View {
    let title: String
    var maxWidth: CGFloat = 760
    @ViewBuilder let content: Content

    var body: some View {
        SettingsPageContainer(title: title, maxWidth: maxWidth) {
            Form {
                content
            }
            #if os(macOS)
            .formStyle(.grouped)
            #endif
        }
    }
}

/// Settings page wrapper for list-based content.
struct SettingsListPage<Content: View>: View {
    let title: String
    var maxWidth: CGFloat = 760
    @ViewBuilder let content: Content

    var body: some View {
        SettingsPageContainer(title: title, maxWidth: maxWidth) {
            content
        }
    }
}

/// Settings page wrapper that pairs search controls with list content.
struct SettingsSearchListPage<Content: View, SearchContent: View>: View {
    let title: String
    var maxWidth: CGFloat = 760
    @ViewBuilder let searchContent: SearchContent
    @ViewBuilder let content: Content

    var body: some View {
        SettingsPageContainer(title: title, maxWidth: maxWidth) {
            VStack(spacing: 0) {
                searchContent
                    .padding()

                content
            }
        }
    }
}

/// Settings page wrapper for inset-grouped lists on iOS.
struct SettingsInsetGroupedListPage<Content: View>: View {
    let title: String
    var maxWidth: CGFloat = 760
    @ViewBuilder let content: Content

    var body: some View {
        SettingsPageContainer(title: title, maxWidth: maxWidth) {
            content
                #if os(iOS)
                .listStyle(.insetGrouped)
                #endif
                .listSectionSeparator(.hidden)
        }
    }
}

/// Labeled form section with an optional footer.
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

/// Row that pairs a label with a trailing toggle.
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

/// Row that pairs a label with a trailing picker.
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

/// Row that pairs a label with a slider and numeric readout.
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

/// Row that pairs a label with a bounded stepper value.
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

/// Search field with leading icon and clear action.
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

/// Empty-state placeholder for settings collections.
struct SettingsEmptyState: View {
    let title: String
    let systemImage: String
    let description: String

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(description))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Confirmation payload for destructive settings actions.
struct SettingsConfirmation: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let confirmTitle: String
    let role: ButtonRole?
    let itemID: PersistentIdentifier?
    let action: (PersistentIdentifier?) -> Void

    init(
        title: String,
        message: String,
        confirmTitle: String,
        role: ButtonRole? = .destructive,
        itemID: PersistentIdentifier? = nil,
        action: @escaping (PersistentIdentifier?) -> Void
    ) {
        self.title = title
        self.message = message
        self.confirmTitle = confirmTitle
        self.role = role
        self.itemID = itemID
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
                confirmation.action(confirmation.itemID)
            }
            Button("Cancel", role: .cancel) { }
        } message: { confirmation in
            Text(confirmation.message)
        }
    }
}

/// Action payload for settings entity rows.
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

/// List wrapper for settings entities with empty state, swipe actions, and context menus.
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

/// Stack-based row wrapper for settings entities that do not use `List`.
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

/// Compact entity row with title, subtitle, metadata, and trailing status icons.
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

/// Leading label block for toggle and picker rows.
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
