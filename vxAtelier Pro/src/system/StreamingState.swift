import Foundation
import Observation

// MARK: - StreamingState
@Observable public class StreamingState {
    var text: String = ""
    var isActive: Bool = false
    var toolCalls: [GenericToolCall] = []
    var hasToolCallsOnly: Bool = false
    
    // Throttling state
    private var pendingBuffer: String = ""
    private var throttleTimer: DispatchSourceTimer?
    private var isThrottlingEnabled: Bool {
        UserDefaults.standard.bool(forKey: AppSettings.Keys.streamingThrottleEnabled)
    }
    private var throttleIntervalMs: Int {
        let v = UserDefaults.standard.integer(forKey: AppSettings.Keys.streamingThrottleIntervalMs)
        return v > 0 ? v : 50 // default ~20 Hz
    }
    private var streamingDebugEnabled: Bool {
        UserDefaults.standard.bool(forKey: AppSettings.Keys.streamingDebugEnabled)
    }
    
    public init() {}
    
    func reset() {
        // Stop timer and clear buffers
        throttleTimer?.setEventHandler {}
        throttleTimer?.cancel()
        throttleTimer = nil
        pendingBuffer.removeAll(keepingCapacity: false)
        text = ""
        isActive = false
        toolCalls = []
        hasToolCallsOnly = false
    }
    
    func appendContent(_ content: String) {
        if isThrottlingEnabled {
            // Buffer content, start timer if needed
            pendingBuffer += content
            if throttleTimer == nil {
                let timer = DispatchSource.makeTimerSource(queue: .main)
                timer.schedule(deadline: .now(), repeating: .milliseconds(throttleIntervalMs))
                timer.setEventHandler { [weak self] in
                    guard let self = self else { return }
                    if self.pendingBuffer.isEmpty { return }
                    let chunk = self.pendingBuffer
                    self.pendingBuffer.removeAll(keepingCapacity: false)
                    self.text += chunk
                    if self.streamingDebugEnabled {
                        vxAtelierPro.log.debug("StreamingState.flush(len: \(chunk.count)) intervalMs: \(self.throttleIntervalMs)")
                    }
                }
                throttleTimer = timer
                if streamingDebugEnabled { vxAtelierPro.log.debug("StreamingState.throttle(start) intervalMs: \(throttleIntervalMs)") }
                timer.resume()
            }
        } else {
            // Immediate append
            text += content
        }
    }
    
    func updateToolCalls(_ newToolCalls: [GenericToolCall]) {
        // If we're receiving only tool calls with no content, flag it
        if text.isEmpty && !newToolCalls.isEmpty {
            hasToolCallsOnly = true
        }
        
        // Create a dictionary of existing tool calls by ID for easy lookup
        var existingToolCallsDict: [String: GenericToolCall] = [:]
        for toolCall in toolCalls {
            existingToolCallsDict[toolCall.id] = toolCall
        }
        
        // Update existing tool calls or add new ones
        for newToolCall in newToolCalls {
            if let existingToolCall = existingToolCallsDict[newToolCall.id] {
                // If this tool call already exists, append any new arguments
                existingToolCallsDict[newToolCall.id] = GenericToolCall(
                    id: newToolCall.id,
                    name: newToolCall.name.isEmpty ? existingToolCall.name : newToolCall.name,
                    arguments: existingToolCall.arguments + newToolCall.arguments,
                    configuration: newToolCall.configuration ?? existingToolCall.configuration,
                    context: newToolCall.context ?? existingToolCall.context
                )
            } else {
                // Otherwise add the new tool call
                existingToolCallsDict[newToolCall.id] = newToolCall
            }
        }
        
        // Convert back to array and update
        toolCalls = Array(existingToolCallsDict.values)
    }
} 
