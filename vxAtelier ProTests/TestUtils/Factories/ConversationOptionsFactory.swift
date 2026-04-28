import Foundation
#if canImport(vxAtelier_Pro_debug)
@testable import vxAtelier_Pro_debug
#else
@testable import vxAtelier_Pro
#endif

final class ConversationOptionsFactory: BaseTestFactory<ConversationOptions>, TestDataFactory {
    typealias Model = ConversationOptions
    
    func create() -> ConversationOptions {
        let options = ConversationOptions()
        
        // Create and add default parameters
        let systemPrompt = AiRequestArgument(
            name: "system_prompt",
            displayName: "System Prompt",
            description: "Instructions for the AI assistant",
            required: true,
            valueType: .string,
            controlType: .textField
        )
        systemPrompt.setValue("Test system prompt \(uniqueIdentifier())")
        
        let temperature = AiRequestArgument(
            name: "temperature",
            displayName: "Temperature",
            description: "Controls randomness in responses",
            required: true,
            valueType: .float,
            controlType: .slider,
            minValue: 0.0,
            maxValue: 2.0,
            step: 0.1,
            defaultValue: 0.7
        )
        
        let maxTokens = AiRequestArgument(
            name: "max_tokens",
            displayName: "Max Tokens",
            description: "Maximum tokens in response",
            required: true,
            valueType: .integer,
            controlType: .stepper,
            minValue: 100,
            maxValue: 4000,
            step: 100,
            defaultValue: 1000
        )
        
        let model = AiRequestArgument(
            name: "model",
            displayName: "Model",
            description: "AI model to use",
            required: true,
            valueType: .string,
            controlType: .picker,
            options: ["test-model"],
            defaultValue: "test-model"
        )
        
        options.parameters = [systemPrompt, temperature, maxTokens, model]
        return options
    }
    
    func create(overrides: (inout ConversationOptions) -> Void) -> ConversationOptions {
        var options = create()
        overrides(&options)
        return options
    }
    
    // Helper methods for common test scenarios
    
    func createWithCustomPrompt(_ prompt: String) -> ConversationOptions {
        create { options in
            options.setParameterValue(name: "system_prompt", value: prompt)
        }
    }
    
    func createWithMaxTokens(_ tokens: Int) -> ConversationOptions {
        create { options in
            options.setParameterValue(name: "max_tokens", value: tokens)
        }
    }
    
    func createWithModel(_ model: String) -> ConversationOptions {
        create { options in
            options.setParameterValue(name: "model", value: model)
        }
    }
}
