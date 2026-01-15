import SwiftUI
import Observation

@MainActor
@Observable
final class ViewOptionsStore {
    enum NavigationMode: String {
        case chats, archive, trash
    }
    
    private(set) var navigationMode: NavigationMode {
        didSet {
            defaults.set(navigationMode.rawValue, forKey: Keys.navigationMode)
            defaults.set(showArchived, forKey: Keys.showArchived)
            defaults.set(showTrashed, forKey: Keys.showTrashed)
        }
    }
    
    var showEmptySections: Bool {
        didSet { defaults.set(showEmptySections, forKey: Keys.showEmptySections) }
    }

    var showUserDialogsOnly: Bool {
        didSet { defaults.set(showUserDialogsOnly, forKey: Keys.showUserDialogsOnly) }
    }
    
    var statusBarVisible: Bool {
        didSet { defaults.set(statusBarVisible, forKey: Keys.statusBarVisible) }
    }
    
    var sidebarDialogsSortDescending: Bool {
        didSet { defaults.set(sidebarDialogsSortDescending, forKey: Keys.sidebarDialogsSortDescending) }
    }
    
    var sidebarDialogsSortTypeRaw: String {
        didSet { defaults.set(sidebarDialogsSortTypeRaw, forKey: Keys.sidebarDialogsSortTypeRaw) }
    }
    
    var sidebarProjectsSortDescending: Bool {
        didSet { defaults.set(sidebarProjectsSortDescending, forKey: Keys.sidebarProjectsSortDescending) }
    }
    
    var sidebarProjectsSortTypeRaw: String {
        didSet { defaults.set(sidebarProjectsSortTypeRaw, forKey: Keys.sidebarProjectsSortTypeRaw) }
    }
    
    var showArchived: Bool { navigationMode == .archive }
    var showTrashed: Bool { navigationMode == .trash }
    
    private let defaults: UserDefaults
    private let navigationAnimation: Animation = .easeInOut(duration: 0.3)
    @ObservationIgnored private var defaultsObserver: NSObjectProtocol?
    
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        
        let storedMode = NavigationMode(rawValue: defaults.string(forKey: Keys.navigationMode) ?? "")
        let legacyArchive = defaults.bool(forKey: Keys.showArchived)
        let legacyTrash = defaults.bool(forKey: Keys.showTrashed)
        if let mode = storedMode {
            navigationMode = mode
        } else if legacyArchive {
            navigationMode = .archive
        } else if legacyTrash {
            navigationMode = .trash
        } else {
            navigationMode = .chats
        }
        
        showEmptySections = defaults.object(forKey: Keys.showEmptySections) as? Bool
            ?? AppDefaults.showEmptySections
        showUserDialogsOnly = defaults.object(forKey: Keys.showUserDialogsOnly) as? Bool
            ?? AppDefaults.showUserDialogsOnly
        statusBarVisible = defaults.object(forKey: Keys.statusBarVisible) as? Bool
            ?? AppDefaults.statusBarVisible
        sidebarDialogsSortDescending =
            defaults.object(forKey: Keys.sidebarDialogsSortDescending) as? Bool ?? true
        sidebarDialogsSortTypeRaw =
            defaults.string(forKey: Keys.sidebarDialogsSortTypeRaw)
                ?? SidebarSortType.conversationDate.rawValue
        sidebarProjectsSortDescending =
            defaults.object(forKey: Keys.sidebarProjectsSortDescending) as? Bool ?? false
        sidebarProjectsSortTypeRaw =
            defaults.string(forKey: Keys.sidebarProjectsSortTypeRaw)
                ?? SidebarSortType.alphabetically.rawValue
        
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: defaults,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.syncFromDefaults()
            }
        }
    }
    
    deinit {
        if let observer = defaultsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    func setNavigationMode(_ mode: NavigationMode, animated: Bool = true) {
        guard navigationMode != mode else { return }
        if animated {
            withAnimation(navigationAnimation) {
                navigationMode = mode
            }
        } else {
            navigationMode = mode
        }
    }
    
    private func syncFromDefaults() {
        let archived = defaults.bool(forKey: Keys.showArchived)
        let trashed = defaults.bool(forKey: Keys.showTrashed)
        let derived: NavigationMode = trashed ? .trash : (archived ? .archive : .chats)
        if derived != navigationMode {
            navigationMode = derived
        }
        
        let emptySections = defaults.object(forKey: Keys.showEmptySections) as? Bool
            ?? showEmptySections
        if emptySections != showEmptySections {
            showEmptySections = emptySections
        }

        let userDialogsOnly = defaults.object(forKey: Keys.showUserDialogsOnly) as? Bool
            ?? showUserDialogsOnly
        if userDialogsOnly != showUserDialogsOnly {
            showUserDialogsOnly = userDialogsOnly
        }
        
        let statusVisible = defaults.object(forKey: Keys.statusBarVisible) as? Bool
            ?? statusBarVisible
        if statusVisible != statusBarVisible {
            statusBarVisible = statusVisible
        }
        
        let dialogDescending = defaults.object(forKey: Keys.sidebarDialogsSortDescending) as? Bool
            ?? sidebarDialogsSortDescending
        if dialogDescending != sidebarDialogsSortDescending {
            sidebarDialogsSortDescending = dialogDescending
        }
        
        let dialogSortType = defaults.string(forKey: Keys.sidebarDialogsSortTypeRaw)
            ?? sidebarDialogsSortTypeRaw
        if dialogSortType != sidebarDialogsSortTypeRaw {
            sidebarDialogsSortTypeRaw = dialogSortType
        }
        
        let projectDescending = defaults.object(forKey: Keys.sidebarProjectsSortDescending) as? Bool
            ?? sidebarProjectsSortDescending
        if projectDescending != sidebarProjectsSortDescending {
            sidebarProjectsSortDescending = projectDescending
        }
        
        let projectSortType = defaults.string(forKey: Keys.sidebarProjectsSortTypeRaw)
            ?? sidebarProjectsSortTypeRaw
        if projectSortType != sidebarProjectsSortTypeRaw {
            sidebarProjectsSortTypeRaw = projectSortType
        }
    }
    
    // MARK: - Keys
    private enum Keys {
        static let navigationMode = "NavigationMode"
        static let showEmptySections = "ShowEmptySections"
        static let showUserDialogsOnly = "ShowUserDialogsOnly"
        static let showArchived = "ShowArchived"
        static let showTrashed = "ShowTrashed"
        static let statusBarVisible = "statusBarVisible"
        static let sidebarDialogsSortDescending = "SidebarDialogsSortOrderDescending"
        static let sidebarDialogsSortTypeRaw = "SidebarDialogsSortType"
        static let sidebarProjectsSortDescending = "SidebarProjectsSortOrderDescending"
        static let sidebarProjectsSortTypeRaw = "SidebarProjectsSortType"
    }
}
