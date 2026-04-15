import SwiftUI

struct CustomPromptView: View {
    @State private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                TextEditor(text: $settings.customPromptInstructions)
                    .font(.body)
                    .frame(minHeight: 120)
                    .scrollContentBackground(.hidden)
            } header: {
                Text("Custom Instructions")
            } footer: {
                Text("Guide what the summary focuses on, e.g. \"Focus on bug fixes and who authored them\" or \"Emphasize user-facing changes\".")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
