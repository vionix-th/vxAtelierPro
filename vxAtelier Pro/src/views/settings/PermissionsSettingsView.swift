import SwiftUI

/// System permission and network security settings.
struct PermissionsSettingsView: View {
    @State private var permissionManager = PermissionManager()
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
        SettingsPage(title: "Permissions", maxWidth: 840) {
            SettingsFormSection("Required Permissions") {
                #if os(iOS) || os(macOS)
                permissionRow(.photos, status: permissionManager.photoLibraryStatus)
                #endif
                permissionRow(.camera, status: permissionManager.cameraStatus)
                permissionRow(.microphone, status: permissionManager.microphoneStatus)
                permissionRow(.speech, status: permissionManager.speechRecognitionStatus)
                permissionRow(.contacts, status: permissionManager.contactsStatus)
                permissionRow(.calendars, status: permissionManager.calendarsStatus)
                permissionRow(.location, status: permissionManager.locationStatus)
                permissionRow(.accessibility, status: permissionManager.accessibilityStatus)
            }

            SettingsFormSection("Network Trust") {
                SettingsToggleRow("Allow Self Signed Certificates", isOn: $allowSelfSignedCertificates)
                SelfSignedCertWhitelistView(whitelist: $selfSignedCertWhitelist)
                    .disabled(!allowSelfSignedCertificates)
            }
        }
        .onAppear {
            selfSignedCertWhitelist = decodeWhitelist(from: selfSignedCertWhitelistJSON)
        }
        .onChange(of: selfSignedCertWhitelist) {
            selfSignedCertWhitelistJSON = encodeWhitelist(selfSignedCertWhitelist)
        }
    }

    private func permissionRow(_ type: PermissionType, status: PermissionStatus) -> some View {
        PermissionRowView(
            type: type,
            status: status,
            action: {
                handlePermissionAction(for: type)
            }
        )
    }
} 
