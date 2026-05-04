#if os(macOS)

import Cocoa

class HotkeyManager {
    private var hotkeys: [String: (NSEvent) -> Bool] = [:]
    private var monitors: [Any?] = []
    
    func register(key: String, modifierFlags: NSEvent.ModifierFlags, action: @escaping (NSEvent) -> Bool) {
        let keyCombination = generateKeyCombination(key: key, modifierFlags: modifierFlags)
        let displayCombination = formatKeyCombination(key: key, modifierFlags: modifierFlags)
        vxAtelierPro.log.debug("Registering hotkey '\(displayCombination)'")
        hotkeys[keyCombination] = action
    
        self.monitors.append(NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            _ = self?.handleKeyPress(event: event, key: key, modifierFlags: modifierFlags)
        })
        self.monitors.append(NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            return self?.handleKeyPress(event: event, key: key, modifierFlags: modifierFlags)
        })
        
        vxAtelierPro.log.debug("Added event monitors for '\(displayCombination)'")
    }
    
    private func handleKeyPress(event: NSEvent, key: String, modifierFlags: NSEvent.ModifierFlags) -> NSEvent? {
        let pressedKey = event.charactersIgnoringModifiers ?? ""
        let matchModifiers = event.modifierFlags.intersection(modifierFlags) == modifierFlags
        
        if pressedKey == key && matchModifiers {
            let keyCombination = generateKeyCombination(key: key, modifierFlags: modifierFlags)
            let displayCombination = formatKeyCombination(key: key, modifierFlags: modifierFlags)
            vxAtelierPro.log.debug("Hotkey triggered '\(displayCombination)'")
            if let handler = hotkeys[keyCombination] {
                let handled = handler(event)
                vxAtelierPro.log.debug("Hotkey '\(displayCombination)' handled: \(handled)")
                return handled ? nil : event
            }
        }
        
        return event
    }
    
    private func generateKeyCombination(key: String, modifierFlags: NSEvent.ModifierFlags) -> String {
        return "\(modifierFlags.rawValue)-\(key)"
    }

    private func formatKeyCombination(key: String, modifierFlags: NSEvent.ModifierFlags) -> String {
        let modifierSymbols: [(NSEvent.ModifierFlags, String)] = [
            (.control, "^"),
            (.option, "⌥"),
            (.shift, "⇧"),
            (.command, "⌘"),
            (.capsLock, "⇪"),
            (.function, "fn")
        ]

        let prefix = modifierSymbols
            .filter { modifierFlags.contains($0.0) }
            .map { $0.1 }
            .joined()

        let keyLabel = key.count == 1 ? key.uppercased() : key
        return prefix.isEmpty ? keyLabel : "\(prefix)\(keyLabel)"
    }
    
    deinit {
        vxAtelierPro.log.debug("Cleaning up \(self.monitors.count) event monitors")
        for monitor in self.monitors {
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }
}

#endif
