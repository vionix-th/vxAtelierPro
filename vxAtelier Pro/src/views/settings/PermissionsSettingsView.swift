import SwiftUI

struct PermissionsSettingsView: View {
    @StateObject private var permissionManager = PermissionManager()
    @AppStorage(AppSettings.Keys.allowSelfSignedCertificates) private var allowSelfSignedCertificates: Bool = false
    @AppStorage(AppSettings.Keys.selfSignedCertWhitelist) private var selfSignedCertWhitelistJSON: String = "[]"
    @State private var selfSignedCertWhitelist: [String] = []

    private func decodeWhitelist(from json: String) -> [String] {
        guard let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }
    private func encodeWhitelist(_ whitelist: [String]) -> String {
        if let data = try? JSONEncoder().encode(whitelist), let json = String(data: data, encoding: .utf8) {
            return json
        }
        return "[]"
    }

    private func handlePermissionAction(for type: PermissionType) {
        switch type {
        case .photos:
            switch permissionManager.photoLibraryStatus {
            case .notDetermined:
                permissionManager.requestPhotoLibraryPermission()
            case .denied, .restricted, .authorized, .limited:
                permissionManager.openAppSettings(for: type)
            }
        case .microphone:
            switch permissionManager.microphoneStatus {
            case .notDetermined:
                permissionManager.requestMicrophonePermission()
            case .denied, .restricted, .authorized:
                permissionManager.openAppSettings(for: type)
            case .limited:
                break
            }
        case .speech:
            switch permissionManager.speechRecognitionStatus {
            case .notDetermined:
                permissionManager.requestSpeechRecognitionPermission()
            case .denied, .restricted, .authorized:
                permissionManager.openAppSettings(for: type)
            case .limited:
                break
            }
        case .camera:
            switch permissionManager.cameraStatus {
            case .notDetermined:
                permissionManager.requestCameraPermission()
            case .denied, .restricted, .authorized:
                permissionManager.openAppSettings(for: type)
            case .limited:
                break
            }
        case .contacts:
            switch permissionManager.contactsStatus {
            case .notDetermined:
                permissionManager.requestContactsPermission()
            case .denied, .restricted, .authorized:
                permissionManager.openAppSettings(for: type)
            case .limited:
                break
            }
        case .calendars:
            switch permissionManager.calendarsStatus {
            case .notDetermined:
                permissionManager.requestCalendarsPermission()
            case .denied, .restricted, .authorized, .limited:
                permissionManager.openAppSettings(for: type)
            }
        case .location:
            switch permissionManager.locationStatus {
            case .notDetermined:
                permissionManager.requestLocationPermission()
            case .denied, .restricted, .authorized:
                permissionManager.openAppSettings(for: type)
            case .limited:
                break
            }
        case .accessibility:
            permissionManager.openAppSettings(for: type)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppDefaults.paddingLarge) {
                SettingsSectionView(title: "Required Permissions") {
                    VStack(spacing: AppDefaults.paddingLarge) {
                        #if os(iOS) || os(macOS)
                        PermissionRowView(
                            type: .photos,
                            status: permissionManager.photoLibraryStatus,
                            action: {
                                handlePermissionAction(for: .photos)
                            }
                        )
                        Divider()
                        #endif
                        PermissionRowView(
                            type: .camera,
                            status: permissionManager.cameraStatus,
                            action: {
                                handlePermissionAction(for: .camera)
                            }
                        )
                        Divider()
                        PermissionRowView(
                            type: .microphone,
                            status: permissionManager.microphoneStatus,
                            action: {
                                handlePermissionAction(for: .microphone)
                            }
                        )
                        Divider()
                        PermissionRowView(
                            type: .speech,
                            status: permissionManager.speechRecognitionStatus,
                            action: {
                                handlePermissionAction(for: .speech)
                            }
                        )
                        Divider()
                        PermissionRowView(
                            type: .contacts,
                            status: permissionManager.contactsStatus,
                            action: {
                                handlePermissionAction(for: .contacts)
                            }
                        )
                        Divider()
                        PermissionRowView(
                            type: .calendars,
                            status: permissionManager.calendarsStatus,
                            action: {
                                handlePermissionAction(for: .calendars)
                            }
                        )
                        Divider()
                        PermissionRowView(
                            type: .location,
                            status: permissionManager.locationStatus,
                            action: {
                                handlePermissionAction(for: .location)
                            }
                        )
                        Divider()
                        PermissionRowView(
                            type: .accessibility,
                            status: permissionManager.accessibilityStatus,
                            action: { handlePermissionAction(for: .accessibility) }
                        )
                        Divider()
                        ToggleRow(title: "Allow Self Signed Certificates", isOn: $allowSelfSignedCertificates, titleWidth: 250)
                        SelfSignedCertWhitelistView(whitelist: $selfSignedCertWhitelist)
                            .disabled(!allowSelfSignedCertificates)
                    }
                }
            }
            .padding(.vertical, AppDefaults.paddingLarge)
        }
        .navigationTitle("Permissions")
        .onAppear {
            selfSignedCertWhitelist = decodeWhitelist(from: selfSignedCertWhitelistJSON)
        }
        .onChange(of: selfSignedCertWhitelist) {
            selfSignedCertWhitelistJSON = encodeWhitelist(selfSignedCertWhitelist)
        }
    }
} 
