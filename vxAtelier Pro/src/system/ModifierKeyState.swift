import Foundation

#if os(macOS)
import CoreGraphics
#endif

enum ModifierKeyState {
    #if os(macOS)
    static func isOptionPressed(
        modifierFlags: CGEventFlags = CGEventSource.flagsState(.combinedSessionState)
    ) -> Bool {
        modifierFlags.contains(.maskAlternate)
    }

    static func isShiftPressed(
        modifierFlags: CGEventFlags = CGEventSource.flagsState(.combinedSessionState)
    ) -> Bool {
        modifierFlags.contains(.maskShift)
    }
    #else
    static func isOptionPressed() -> Bool {
        false
    }

    static func isShiftPressed() -> Bool {
        false
    }
    #endif
}
