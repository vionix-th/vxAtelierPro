#if os(macOS)

import SwiftUI
import SwiftData
import AppKit

class GlobalUtilityPanel {
    private var dialogWindow: NSWindow? = nil
    
    @MainActor
    func show(modelContext: ModelContext, conversationID: PersistentIdentifier, queryManager: QueryManager, didSend: @escaping (PersistentIdentifier) -> Void) {
        var window = self.dialogWindow
        
        if window == nil {
            vxAtelierPro.log.debug("Creating new utility panel window")
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 350, height: 100),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false)
            
            if let window = window {
                window.center()
                window.isReleasedWhenClosed = false
                window.setFrameAutosaveName("com.cutecube.software.vxAtelier.DialogTextEditDialogWindow")
                vxAtelierPro.log.debug("Window configuration completed")
            }
            
            self.dialogWindow = window
        }
        
        if let window = window {
            // Resolve the conversation on-demand from the QueryManager
            guard let conversation = queryManager.conversation(with: conversationID) else {
                vxAtelierPro.log.error("Failed to find conversation with ID: \(conversationID)")
                return
            }
            
            vxAtelierPro.log.notice("Showing dialog '\(conversation.title)'")
            window.title = conversation.title
            window.contentViewController = NSHostingController(
                rootView:
                    MessageInputView(
                        queryManager: queryManager,
                        streamingState: StreamingState(),
                        contextConversation: conversation,
                        resolveConversation: {
                            if let resolved = queryManager.conversation(with: conversationID) {
                                return resolved
                            }
                            throw AppError.invalidOperation("Conversation not found")
                        },
                        didSend: { _ in
                            vxAtelierPro.log.debug("Dialog completed, closing window")
                            didSend(conversationID)
                            self.dialogWindow?.close()
                        })
                    .frame(minWidth: 350, maxWidth: .infinity, maxHeight: .infinity)
                    .environment(\.modelContext, modelContext)
                    .id(conversationID)
            )
            window.makeKeyAndOrderFront(nil)
        } else {
            vxAtelierPro.log.error("Failed to create or show window")
        }
    }
    
}

#endif
