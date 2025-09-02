import SwiftUI

// MARK: - Reusable Settings Row Components

// Simple Text Row (e.g., for Appearance)
struct TextRow: View {
    let title: String
    @Binding var value: String
    var titleWidth: CGFloat = 150 // Default width

    var body: some View {
        HStack {
            Text(title)
                .frame(width: titleWidth, alignment: .leading)
            Picker(title, selection: $value) {
                // Assuming appearanceStyle is the main use case
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
            .labelsHidden()
            Spacer()
        }
    }
}

// Simple Toggle Row
struct ToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    var titleWidth: CGFloat? = 200 // Default width, optional

    var body: some View {
        HStack {
            // Display Text once, apply frame conditionally
            if let titleWidth = titleWidth {
                Text(title)
                    .frame(width: titleWidth, alignment: .leading)
            } else {
                Text(title)
            }
            Spacer()
            Toggle(title, isOn: $isOn)
                .labelsHidden()
        }
    }
}

// Simple Slider Row
struct SliderRow: View {
    let title: String
    let bounds: ClosedRange<Double>
    let step: Double
    @Binding var value: Double
    var titleWidth: CGFloat = 150 // Default width

    var body: some View {
        HStack {
            Text(title)
                .frame(width: titleWidth, alignment: .leading)
            Slider(value: $value, in: bounds, step: step) {
                 // Accessibility label if needed
            }
            Text("\(Int(value))") // Display current value
                .frame(width: 40, alignment: .trailing)
                .monospacedDigit()
        }
    }
}

// Simple Stepper Row
struct StepperRow: View {
    let title: String
    let bounds: ClosedRange<Int>
    let step: Int
    @Binding var value: Int
    var titleWidth: CGFloat = 150 // Default width

    var body: some View {
        HStack {
            Text(title)
                .frame(width: titleWidth, alignment: .leading)
            Stepper("", value: $value, in: bounds, step: step)
            Spacer()
            Text("\(value)") // Display current value
                .frame(width: 40, alignment: .trailing)
                .monospacedDigit()
        }
    }
} 