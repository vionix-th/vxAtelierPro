import SwiftUI

/// A reusable hybrid input for numeric values (slider/stepper + text field)
/// Supports both integer and floating-point values via Double binding.
public struct HybridNumericInputView: View {
    public let label: String?
    @Binding public var value: Double
    public let minValue: Double
    public let maxValue: Double
    public let step: Double
    public let isInteger: Bool
    public let useStepper: Bool

    public init(label: String? = nil,
                value: Binding<Double>,
                minValue: Double,
                maxValue: Double,
                step: Double,
                isInteger: Bool = false,
                useStepper: Bool = false) {
        self.label = label
        self._value = value
        self.minValue = minValue
        self.maxValue = maxValue
        self.step = step
        self.isInteger = isInteger
        self.useStepper = useStepper
    }

    public var body: some View {
        HStack(spacing: 12) {
            if let label = label {
                Text(label)
                    .frame(width: 130, alignment: .leading)
            }
            if useStepper {
                Stepper(value: $value, in: minValue...maxValue, step: step) {
                    EmptyView()
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Slider(value: $value, in: minValue...maxValue, step: step)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            TextField("", value: $value, formatter: HybridNumericInputView.numberFormatter(isInteger: isInteger))
                .frame(minWidth: 60, idealWidth: 90, maxWidth: 120)
                .textFieldStyle(.roundedBorder)
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    public static func numberFormatter(isInteger: Bool) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        if isInteger {
            formatter.minimumFractionDigits = 0
            formatter.maximumFractionDigits = 0
        } else {
            formatter.minimumFractionDigits = 0
            formatter.maximumFractionDigits = 3
        }
        return formatter
    }
} 