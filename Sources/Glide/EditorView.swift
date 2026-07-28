import SwiftUI

struct EditorView: View {
    @Binding var script: Script

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Title", text: $script.title)
                .textFieldStyle(.plain)
                .font(.title2.weight(.semibold))
                .padding(.horizontal, 20)
                .padding(.vertical, 16)

            Divider()

            TextEditor(text: $script.body)
                .font(.system(size: 15))
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Text("Edited \(script.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
