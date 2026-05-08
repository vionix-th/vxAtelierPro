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
        options.systemPrompt = "Test system prompt \(uniqueIdentifier())"
        options.temperature = 0.7
        options.maxOutputTokens = 1000
        options.selectedModelID = "test-model"
        return options
    }

    func create(overrides: (inout ConversationOptions) -> Void) -> ConversationOptions {
        var options = create()
        overrides(&options)
        return options
    }

    func createWithCustomPrompt(_ prompt: String) -> ConversationOptions {
        create { options in
            options.setParameterValue(.systemPrompt, value: .string(prompt))
        }
    }

    func createWithMaxTokens(_ tokens: Int) -> ConversationOptions {
        create { options in
            options.setParameterValue(.maxOutputTokens, value: .integer(tokens))
        }
    }

    func createWithModel(_ model: String) -> ConversationOptions {
        create { options in
            options.setParameterValue(.model, value: .string(model))
        }
    }
}
