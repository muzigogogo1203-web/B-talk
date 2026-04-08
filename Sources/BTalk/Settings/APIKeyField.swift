import SwiftUI

/// A secure text field for API keys with reveal toggle and save button.
struct APIKeyField: View {
    let label: String
    @Binding var value: String
    var onSave: () -> Void

    @State private var isRevealed = false

    var body: some View {
        LabeledContent(label) {
            HStack {
                if isRevealed {
                    TextField("Enter API key...", text: $value)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .onSubmit { onSave() }
                } else {
                    SecureField("Enter API key...", text: $value)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .onSubmit { onSave() }
                }

                Button {
                    isRevealed.toggle()
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                Button("Save") {
                    onSave()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(value.isEmpty)
            }
        }
    }
}
