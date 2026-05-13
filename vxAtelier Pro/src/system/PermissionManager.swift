import SwiftUI
import AVFoundation
import Observation
import Speech
import Photos
import os // For OSLogType
import Contacts
import EventKit
import CoreLocation

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Enum defining the types of permissions the app might require.
enum PermissionType: String, CaseIterable, Identifiable {
    case photos = "Photo Library"
    case microphone = "Microphone"
    case speech = "Speech Recognition"
    case camera = "Camera"
    case contacts = "Contacts"
    case calendars = "Calendars"
    case location = "Location Services"
    case accessibility = "Accessibility"
    
    var id: String { self.rawValue }
    
    /// Provides a description of why the permission is needed.
    var usageDescription: String {
        switch self {
        case .photos:
            return "Used to select avatar images for conversations or the default application avatar."
        case .microphone:
            return "Required for voice input or dictation features (if implemented)."
        case .speech:
            return "Required to transcribe dictated audio into text (if implemented)."
        case .camera:
            return "Required for capturing images or video (if implemented)."
        case .contacts:
            return "Required to access contact information (if implemented)."
        case .calendars:
            return "Required to access calendar events (if implemented)."
        case .location:
            return "Required to access your location (if implemented)."
        case .accessibility:
            return "Required to control other applications or UI elements (e.g., for automation or assistance features)."
        }
    }
    
    /// System image name for the permission icon.
    var systemImageName: String {
         switch self {
         case .photos: return "photo.on.rectangle.angled"
         case .microphone: return "mic.fill"
         case .speech: return "waveform.path.ecg"
         case .camera: return "camera.fill"
         case .contacts: return "person.crop.circle.fill"
         case .calendars: return "calendar"
         case .location: return "location.fill"
         case .accessibility: return "figure.wave.circle.fill"
         }
     }

    #if os(macOS)
    /// Returns the macOS System Settings Privacy pane identifier, if known.
    var macOSPrivacyPaneID: String? {
        switch self {
        case .photos: return "Privacy_Photos"
        case .microphone: return "Privacy_Microphone"
        case .camera: return "Privacy_Camera"
        case .contacts: return "Privacy_Contacts"
        case .calendars: return "Privacy_Calendars"
        case .location: return "Privacy_LocationServices"
        case .accessibility: return "Privacy_Accessibility"
        case .speech: return nil // Managed under Mic/Accessibility
        }
    }
    #endif
}

/// Enum representing the possible authorization statuses for a permission.
enum PermissionStatus: String {
    case notDetermined = "Not Determined"
    case denied = "Denied"
    case authorized = "Authorized"
    case limited = "Limited Access" // Specific to Photos on iOS
    case restricted = "Restricted" // E.g., by parental controls
    
    var description: String {
        self.rawValue
    }
    
    var color: Color {
        switch self {
        case .authorized, .limited: return .green
        case .denied, .restricted: return .red
        case .notDetermined: return .orange
        }
    }
}

/// Manages checking and requesting permissions required by the application.
@MainActor
@Observable
class PermissionManager {
    var photoLibraryStatus: PermissionStatus = .notDetermined
    var microphoneStatus: PermissionStatus = .notDetermined
    var speechRecognitionStatus: PermissionStatus = .notDetermined
    var cameraStatus: PermissionStatus = .notDetermined
    var contactsStatus: PermissionStatus = .notDetermined
    var calendarsStatus: PermissionStatus = .notDetermined
    var locationStatus: PermissionStatus = .notDetermined
    var accessibilityStatus: PermissionStatus = .notDetermined

    // --- REMOVED Manager Instances ---
    // No longer store manager instances here to prevent premature initialization
    // private let locationManager = CLLocationManager() // REMOVED
    // private var locationDelegate: LocationDelegate? // REMOVED
    // No EKEventStore or CNContactStore instances stored here either

    // --- Keep track of ongoing location request ---
    private var locationManager: CLLocationManager?
    private var locationDelegate: LocationDelegate?

    init() {
        // --- REMOVED Manager Initialization ---
        // locationDelegate = LocationDelegate(permissionManager: self) // REMOVED
        // locationManager.delegate = locationDelegate // REMOVED

        // Initial status checks when the manager is created
        // These will now use static methods or create temporary local instances
        checkAllPermissions()
        
        // Add observer for application becoming active to re-check statuses
        #if os(iOS)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        #elseif os(macOS)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive), name: NSApplication.didBecomeActiveNotification, object: nil)
        #endif
    }
    
    deinit {
         // Clean up observer
         NotificationCenter.default.removeObserver(self)
     }

    @objc private func appDidBecomeActive() {
        vxAtelierPro.log.debug("App became active, re-checking permission statuses.")
        checkAllPermissions()
    }
    
    /// Checks the current status of all relevant permissions.
    func checkAllPermissions() {
        checkPhotoLibraryPermission()
        checkMicrophonePermission()
        checkSpeechRecognitionPermission()
        checkCameraPermission()
        checkContactsPermission()
        checkCalendarsPermission()
        checkLocationPermission()
        checkAccessibilityPermission()
    }

    // --- Photo Library ---

    func checkPhotoLibraryPermission() {
        #if os(iOS) || os(macOS) // PHPhotoLibrary available on both, but typically used differently
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        updatePhotoLibraryStatus(from: status)
        #else
        // Photos permission not applicable or handled differently on other platforms
        self.photoLibraryStatus = .notDetermined // Or some other default
        #endif
    }

    func requestPhotoLibraryPermission() {
        #if os(iOS) || os(macOS)
        vxAtelierPro.log.debug("Requesting Photo Library permission...")
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
            DispatchQueue.main.async {
                self?.updatePhotoLibraryStatus(from: status)
                vxAtelierPro.log.info("Photo Library permission status after request: \(status.rawValue)")
            }
        }
        #endif
    }
    
    private func updatePhotoLibraryStatus(from status: PHAuthorizationStatus) {
        switch status {
        case .authorized: self.photoLibraryStatus = .authorized
        case .denied: self.photoLibraryStatus = .denied
        case .notDetermined: self.photoLibraryStatus = .notDetermined
        case .restricted: self.photoLibraryStatus = .restricted
        case .limited: self.photoLibraryStatus = .limited
        @unknown default: self.photoLibraryStatus = .notDetermined
        }
    }

    // --- Microphone ---

    func checkMicrophonePermission() {
        #if os(iOS)
        if #available(iOS 17.0, *) {
            // Use AVCaptureDevice for microphone status in iOS 17+
            let status = AVCaptureDevice.authorizationStatus(for: .audio)
            updateMicrophoneStatus(fromAVCapture: status)
        } else {
            let status = AVAudioSession.sharedInstance().recordPermission
            updateMicrophoneStatus(fromIOS: status)
        }
        #elseif os(macOS)
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        updateMicrophoneStatus(fromAVCapture: status)
        #endif
    }

    func requestMicrophonePermission() {
        #if os(iOS)
        vxAtelierPro.log.debug("Requesting Microphone permission (iOS)...")
        if #available(iOS 17.0, *) {
            // Use AVCaptureDevice for requesting permission in iOS 17+
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    vxAtelierPro.log.info("Microphone permission granted (iOS): \(granted)")
                    self?.checkMicrophonePermission()
                }
            }
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
                DispatchQueue.main.async {
                    vxAtelierPro.log.info("Microphone permission granted (iOS): \(granted)")
                    self?.checkMicrophonePermission()
                }
            }
        }
        #elseif os(macOS)
        vxAtelierPro.log.debug("Requesting Microphone permission (macOS)...")
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            DispatchQueue.main.async {
                vxAtelierPro.log.info("Microphone permission granted (macOS): \(granted)")
                // Re-check status after grant attempt
                 self?.checkMicrophonePermission()
            }
        }
        #endif
    }
    
    #if os(iOS)
     private func updateMicrophoneStatus(fromIOS status: AVAudioSession.RecordPermission) {
         switch status {
         case .granted: self.microphoneStatus = .authorized
         case .denied: self.microphoneStatus = .denied
         case .undetermined: self.microphoneStatus = .notDetermined
         @unknown default: self.microphoneStatus = .notDetermined
         }
     }
     #endif

     #if os(macOS) || os(iOS) // AVCaptureDevice is available on both
     private func updateMicrophoneStatus(fromAVCapture status: AVAuthorizationStatus) {
         switch status {
         case .authorized: self.microphoneStatus = .authorized
         case .denied: self.microphoneStatus = .denied
         case .notDetermined: self.microphoneStatus = .notDetermined
         case .restricted: self.microphoneStatus = .restricted
         @unknown default: self.microphoneStatus = .notDetermined
         }
     }
     #endif


    // --- Speech Recognition ---

    func checkSpeechRecognitionPermission() {
        let status = SFSpeechRecognizer.authorizationStatus()
        updateSpeechStatus(from: status)
    }

    func requestSpeechRecognitionPermission() {
        vxAtelierPro.log.debug("Requesting Speech Recognition permission...")
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                self?.updateSpeechStatus(from: status)
                vxAtelierPro.log.info("Speech Recognition permission status after request: \(status.rawValue)")
            }
        }
    }
    
    private func updateSpeechStatus(from status: SFSpeechRecognizerAuthorizationStatus) {
         switch status {
         case .authorized: self.speechRecognitionStatus = .authorized
         case .denied: self.speechRecognitionStatus = .denied
         case .notDetermined: self.speechRecognitionStatus = .notDetermined
         case .restricted: self.speechRecognitionStatus = .restricted
         @unknown default: self.speechRecognitionStatus = .notDetermined
         }
     }

    // --- Camera ---

    func checkCameraPermission() {
        #if os(iOS) || os(macOS)
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        updateCameraStatus(from: status)
        #endif
    }

    func requestCameraPermission() {
        #if os(iOS) || os(macOS)
        vxAtelierPro.log.debug("Requesting Camera permission...")
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                vxAtelierPro.log.info("Camera permission granted: \(granted)")
                self?.checkCameraPermission() // Re-check status
            }
        }
        #endif
    }
    
    private func updateCameraStatus(from status: AVAuthorizationStatus) {
        switch status {
        case .authorized: self.cameraStatus = .authorized
        case .denied: self.cameraStatus = .denied
        case .notDetermined: self.cameraStatus = .notDetermined
        case .restricted: self.cameraStatus = .restricted
        @unknown default: self.cameraStatus = .notDetermined
        }
    }

    // --- Contacts ---
    
    func checkContactsPermission() {
        // CNContactStore status check is static
        let status = CNContactStore.authorizationStatus(for: .contacts)
        vxAtelierPro.log.debug("Checked Contacts permission: \(status.rawValue)")
        updateContactsStatus(from: status)
    }

    func requestContactsPermission() {
        vxAtelierPro.log.debug("Requesting Contacts permission...")
        // CNContactStore requires an instance for request
        let store = CNContactStore()
        store.requestAccess(for: .contacts) { [weak self] granted, error in
            DispatchQueue.main.async {
                if let error = error {
                     vxAtelierPro.log.error("Error requesting contacts access: \(error.localizedDescription)")
                 } else {
                     vxAtelierPro.log.info("Contacts permission granted: \(granted)")
                 }
                 // Re-check status after grant attempt
                 self?.checkContactsPermission()
            }
        }
    }
    
    private func updateContactsStatus(from status: CNAuthorizationStatus) {
        switch status {
        case .authorized: self.contactsStatus = .authorized
        case .denied: self.contactsStatus = .denied
        case .notDetermined: self.contactsStatus = .notDetermined
        case .restricted: self.contactsStatus = .restricted
        case .limited: self.contactsStatus = .limited
        @unknown default: self.contactsStatus = .notDetermined
        }
    }

    // --- Calendars ---

    func checkCalendarsPermission() {
        // EKEventStore requires an instance for status check, but the instance isn't used after creation.
        // Removed unused 'store' variable.
        let status = EKEventStore.authorizationStatus(for: .event)
        vxAtelierPro.log.debug("Checked Calendars permission: \(status.rawValue)")
        updateCalendarsStatus(from: status)
    }

    func requestCalendarsPermission() {
        vxAtelierPro.log.debug("Requesting Calendars permission...")
        // EKEventStore requires an instance for request
        let store = EKEventStore()
        
        #if swift(>=5.9) && (os(macOS) || os(iOS)) // Using newer async/await API if available
        if #available(macOS 14.0, iOS 17.0, *) {
            Task {
                do {
                    let granted = try await store.requestFullAccessToEvents()
                    DispatchQueue.main.async { [weak self] in
                        vxAtelierPro.log.info("Calendars permission granted (async): \(granted)")
                        self?.checkCalendarsPermission() // Re-check status
                    }
                } catch {
                    vxAtelierPro.log.error("Error requesting full calendar access: \(error)")
                    DispatchQueue.main.async { [weak self] in
                        self?.checkCalendarsPermission() // Re-check status even on error
                    }
                }
            }
        } else {
            // Fallback to older completion handler API
            store.requestAccess(to: .event) { [weak self] granted, error in
                DispatchQueue.main.async {
                    if let error = error {
                        vxAtelierPro.log.error("Error requesting calendar access: \(error.localizedDescription)")
                    } else {
                        vxAtelierPro.log.info("Calendars permission granted through EventKit callback: \(granted)")
                    }
                    self?.checkCalendarsPermission() // Re-check status
                }
            }
        }
        #else
        // Fallback for older Swift versions
        store.requestAccess(to: .event) { [weak self] granted, error in
             DispatchQueue.main.async {
                 if let error = error {
                     vxAtelierPro.log.error("Error requesting calendar access: \(error.localizedDescription)")
                 } else {
                     vxAtelierPro.log.info("Calendars permission granted through EventKit callback: \(granted)")
                 }
                 self?.checkCalendarsPermission() // Re-check status
             }
         }
        #endif
    }
    
    private func updateCalendarsStatus(from status: EKAuthorizationStatus) {
        switch status {
        case .authorized, .fullAccess: // Treat fullAccess same as authorized
            self.calendarsStatus = .authorized
        case .denied: self.calendarsStatus = .denied
        case .notDetermined: self.calendarsStatus = .notDetermined
        case .restricted: self.calendarsStatus = .restricted
        case .writeOnly: self.calendarsStatus = .limited // Or treat differently if needed
        @unknown default: self.calendarsStatus = .notDetermined
        }
    }

    // --- Location Services ---

    func checkLocationPermission() {
        let status: CLAuthorizationStatus

        // Use the modern static method where available
        if #available(iOS 14.0, macOS 11.0, *) {
            status = CLLocationManager().authorizationStatus // Can check status without keeping instance alive
            vxAtelierPro.log.debug("Checked Location permission (static): \(status.rawValue)")
        } else {
            // Fallback for older OS: Requires an instance, but we won't store it
            // Note: This check is less reliable without a delegate on older OS,
            // as status might not be updated immediately after a request.
            // The request flow handles the update more robustly.
            status = CLLocationManager.authorizationStatus()
            vxAtelierPro.log.debug("Checked Location permission (instance fallback): \(status.rawValue)")
        }
        updateLocationStatus(from: status)
    }

    func requestLocationPermission() {
        vxAtelierPro.log.debug("Requesting Location permission...")
        
        // Create manager and delegate locally for the request
        let manager = CLLocationManager()
        let delegate = LocationDelegate { [weak self] status in
             // Completion handler for the delegate
             DispatchQueue.main.async {
                 self?.updateLocationStatus(from: status)
                 // Release manager and delegate once status is updated
                 self?.locationManager = nil
                 self?.locationDelegate = nil
                 vxAtelierPro.log.info("Location permission status after request: \(status.rawValue)")
             }
         }
        
        manager.delegate = delegate
        
        // Keep strong references ONLY during the request lifecycle
        self.locationManager = manager
        self.locationDelegate = delegate
        
        // Make the request
        #if os(iOS)
        // Request "When In Use" - adjust if "Always" is needed
        manager.requestWhenInUseAuthorization()
        #elseif os(macOS)
        // macOS doesn't have a direct equivalent API like iOS for "request"
        // Authorization is implicitly requested when you start using location services.
        // However, checking status and guiding user to settings is the main approach.
        // For macOS 11+, trying to start location updates might trigger the prompt
        // if status is notDetermined. Let's just log for now.
        // manager.startUpdatingLocation() // Example - might trigger prompt
        // manager.stopUpdatingLocation()
        vxAtelierPro.log.debug("Location request on macOS primarily relies on user enabling via System Settings.")
        // We still update status based on the initial check or delegate callback if applicable
        let currentStatus = manager.authorizationStatus
        updateLocationStatus(from: currentStatus) // Update based on current known status
        #endif
    }
    
    // Called by the LocationDelegate
    func updateLocationStatus(from status: CLAuthorizationStatus) {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse: self.locationStatus = .authorized
        case .denied: self.locationStatus = .denied
        case .notDetermined: self.locationStatus = .notDetermined
        case .restricted: self.locationStatus = .restricted
        @unknown default: self.locationStatus = .notDetermined
        }
    }

    // --- Accessibility ---

    func checkAccessibilityPermission() {
        #if os(macOS)
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: false]
        let isTrusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        self.accessibilityStatus = isTrusted ? .authorized : .denied
        vxAtelierPro.log.debug("Accessibility Trusted Status: \(isTrusted)")
        #elseif os(iOS)
        self.accessibilityStatus = .authorized
        vxAtelierPro.log.debug("Accessibility permission is not applicable on iOS, defaulting to authorized.")
        #endif
    }

    func requestAccessibilityPermission() {
        #if os(macOS)
        vxAtelierPro.log.info("Accessibility permission cannot be requested programmatically. Opening System Settings.")
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true]
        if !AXIsProcessTrustedWithOptions(options as CFDictionary) {
            openAppSettings()
        } else {
            self.accessibilityStatus = .authorized
        }
        #elseif os(iOS)
        vxAtelierPro.log.debug("Accessibility permission is not applicable on iOS.")
        #endif
    }

    // --- Open Settings ---
    
    /// Opens the application's settings in the System Settings/Settings app.
    /// On macOS, attempts to open the specific privacy pane if possible.
    func openAppSettings(for type: PermissionType? = nil) { // Add optional type parameter
        vxAtelierPro.log.debug("Attempting to open app settings... (for type: \(type?.rawValue ?? "general"))")

        #if os(iOS)
        // iOS always uses the general app settings URL
        guard let settingsUrl = URL(string: UIApplication.openSettingsURLString) else {
            vxAtelierPro.log.error("Could not create iOS settings URL from string: \(UIApplication.openSettingsURLString)")
            return
        }
        
        // Check if the URL can be opened before attempting
        guard UIApplication.shared.canOpenURL(settingsUrl) else {
            vxAtelierPro.log.warning("Cannot open settings URL: \(settingsUrl)")
            return
        }

        vxAtelierPro.log.debug("Opening iOS settings URL: \(settingsUrl)")
        UIApplication.shared.open(settingsUrl) { success in
            if !success {
                vxAtelierPro.log.error("Failed to open iOS settings URL: \(settingsUrl)")
            }
        }

        #elseif os(macOS)
        var urlToOpen: URL? = nil
        let generalPrivacyURLString = "x-apple.systempreferences:com.apple.preference.security?Privacy"
        
        if let paneID = type?.macOSPrivacyPaneID {
            // Try specific pane first
            let specificURLString = "\(generalPrivacyURLString)_\(paneID)"
            urlToOpen = URL(string: specificURLString)
            vxAtelierPro.log.debug("Attempting to open specific macOS pane: \(specificURLString)")
        }
        
        // Fallback to general Privacy pane if specific URL failed or wasn't found
        if urlToOpen == nil {
            urlToOpen = URL(string: generalPrivacyURLString)
            vxAtelierPro.log.debug("Falling back to general macOS Privacy pane.")
        }
        
        // Safely unwrap the final URL
        guard let finalURL = urlToOpen else {
            vxAtelierPro.log.error("Could not determine a valid URL to open macOS settings.")
            return
        }
                  
        vxAtelierPro.log.debug("Opening final macOS settings URL: \(finalURL)")
        let opened = NSWorkspace.shared.open(finalURL)
        if !opened {
            vxAtelierPro.log.error("NSWorkspace failed to open macOS settings URL: \(finalURL)")
            // Fallback attempt: Open the main System Settings app only if the *specific* URL failed
            if finalURL.absoluteString != generalPrivacyURLString, 
               let generalURL = URL(string: generalPrivacyURLString) { 
                 vxAtelierPro.log.debug("Attempting fallback to open general Privacy pane...")
                 let fallbackOpened = NSWorkspace.shared.open(generalURL)
                 if !fallbackOpened {
                     vxAtelierPro.log.error("NSWorkspace also failed to open general Privacy settings URL: \(generalURL)")
                 }
            } else if finalURL.absoluteString == generalPrivacyURLString {
                // If even the general privacy URL failed, try the absolute base
                if let baseSettingsUrl = URL(string: "x-apple.systempreferences:") {
                     vxAtelierPro.log.debug("Attempting fallback to open base System Settings URL...")
                     let baseOpened = NSWorkspace.shared.open(baseSettingsUrl)
                     if !baseOpened {
                          vxAtelierPro.log.error("NSWorkspace failed to open base System Settings URL.")
                     }
                }
            }
        }
        #endif
    }
}

// MARK: - Location Delegate Helper
// Simple delegate class to handle location authorization changes
// Now takes a completion handler instead of a weak PermissionManager reference
fileprivate class LocationDelegate: NSObject, CLLocationManagerDelegate {
    private var completion: (CLAuthorizationStatus) -> Void

    init(completion: @escaping (CLAuthorizationStatus) -> Void) {
         self.completion = completion
         super.init()
         vxAtelierPro.log.debug("LocationDelegate initialized.")
     }
    
    deinit {
        vxAtelierPro.log.debug("LocationDelegate deinitialized.")
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        vxAtelierPro.log.debug("LocationDelegate: locationManagerDidChangeAuthorization called. Status: \(status.rawValue)")
        completion(status)
    }
    
    // Handle older delegate method if needed (iOS < 14)
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
         vxAtelierPro.log.debug("LocationDelegate: didChangeAuthorization called. Status: \(status.rawValue)")
         // Avoid calling completion twice if both methods are somehow invoked
         // Check if status is not undetermined, as the new method handles all transitions
         if status != .notDetermined {
             completion(status)
         }
     }
}
