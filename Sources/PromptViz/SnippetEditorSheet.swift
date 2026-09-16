import PromptVizCore
import SwiftUI

struct SnippetEditorSheet: View {
    let snippet: Snippet?
    let onDelete: (() -> Void)?
    let onSave: (String, String, Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var snippetBody: String
    @State private var favorite: Bool

    init(
        snippet: Snippet?,
        onDelete: (() -> Void)? = nil,
        onSave: @escaping (String, String, Bool) -> Void
    ) {
        self.snippet = snippet
        self.onDelete = onDelete
        self.onSave = onSave
        _title = State(initialValue: snippet?.title ?? "")
        _snippetBody = State(initialValue: snippet?.body ?? "")
        _favorite = State(initialValue: snippet?.isFavorite ?? false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(snippet == nil ? "New snippet" : "Edit snippet")
                .font(.title2.weight(.semibold))
            TextField("Name", text: $title)
                .textFieldStyle(.roundedBorder)
            TextEditor(text: $snippetBody)
                .font(.body.monospaced())
                .frame(height: 130)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            Toggle("Show in favorites", isOn: $favorite)
            HStack {
                if let onDelete {
                    Button("Delete", role: .destructive) {
                        onDelete()
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }

                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    onSave(title, snippetBody, favorite)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || snippetBody.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 500)
    }
}
