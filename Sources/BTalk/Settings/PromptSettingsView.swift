import SwiftUI

struct PromptSettingsView: View {
    @StateObject private var settings = AppSettings.shared
    @State private var customPrompt = ""
    @State private var previewInput = "把 login function 的 return type 改成 Promise<User>，然后加上 error handling"
    @State private var previewOutput = ""
    @State private var isPreviewing = false

    var body: some View {
        Form {
            Section("Template") {
                Picker("Prompt Template", selection: $settings.promptTemplate) {
                    ForEach(PromptTemplate.allCases, id: \.self) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("System Prompt Preview") {
                ScrollView {
                    Text(settings.promptTemplate.systemPrompt)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(height: 120)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            Section("Test") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sample transcript:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("Type a transcript to test...", text: $previewInput, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3)

                    HStack {
                        Button("Preview Result") { runPreview() }
                            .disabled(isPreviewing)
                        if isPreviewing { ProgressView().controlSize(.small) }
                    }

                    if !previewOutput.isEmpty {
                        Text("Output:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(previewOutput)
                            .font(.system(size: 12))
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quaternary)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func runPreview() {
        isPreviewing = true
        previewOutput = ""
        Task {
            if let provider = AppSettings.shared.buildLLMProvider() {
                do {
                    previewOutput = try await provider.structure(transcript: previewInput)
                } catch {
                    previewOutput = "Error: \(error.localizedDescription)"
                }
            } else {
                previewOutput = "No LLM configured. Please set API key in LLM settings."
            }
            isPreviewing = false
        }
    }
}
