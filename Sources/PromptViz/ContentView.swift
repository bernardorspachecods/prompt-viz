import AppKit
import PromptVizCore
import SwiftUI
import UniformTypeIdentifiers

enum SnippetEditorPresentation: Identifiable {
    case new
    case edit(Snippet)

    var id: String {
        switch self {
        case .new:
            return "new"
        case .edit(let snippet):
            return snippet.id.uuidString
        }
    }
}

@MainActor
struct ContentView: View {
    @ObservedObject var model: PromptVizModel
    @State private var snippetEditorPresentation: SnippetEditorPresentation?
    @State private var showingSettings = false
    @State private var historySearch = ""
    @State private var showingHistoryClearConfirmation = false

    private var composerTitle: String {
        let title = model.selectedWorkspace?.title ?? "Prompt Viz"
        return String(title.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: true).first ?? Substring(title))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func workspaceDisplayParts(for title: String) -> (repository: String, chat: String?) {
        let withoutSuffix = title
            .components(separatedBy: "|")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? title
        let parts = withoutSuffix.components(separatedBy: " — ")

        guard let repository = parts.first else {
            return (withoutSuffix, nil)
        }

        let chat = parts.dropFirst().joined(separator: " — ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return (
            repository.trimmingCharacters(in: .whitespacesAndNewlines),
            chat.isEmpty ? nil : chat
        )
    }

    var body: some View {
        composer
        .sheet(item: $snippetEditorPresentation) { presentation in
            switch presentation {
            case .new:
                snippetEditorSheet(for: nil)
            case .edit(let snippet):
                snippetEditorSheet(for: snippet)
            }
        }
        .sheet(isPresented: $showingSettings) {
            AppSettingsView(model: model)
        }
        .sheet(item: $model.imagePastePreview) { preview in
            ImagePasteConfirmationView(
                data: preview.data,
                onCancel: { model.cancelImagePaste(preview) },
                onConfirm: { model.confirmImagePaste(preview) }
            )
        }
        .alert("Prompt Viz", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            if model.shouldOfferAutomationSettings {
                    Button("Open Automation") {
                    model.openAutomationSettings()
                    model.errorMessage = nil
                }
            } else if model.shouldOfferAccessibilitySettings {
                    Button("Open Accessibility") {
                    model.openAccessibilitySettings()
                    model.errorMessage = nil
                }
            }
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .onReceive(NotificationCenter.default.publisher(for: .promptVizOpenSettings)) { _ in
            showingSettings = true
        }
    }

    @ViewBuilder
    private func snippetEditorSheet(for snippet: Snippet?) -> some View {
        SnippetEditorSheet(
            snippet: snippet,
            onDelete: snippet.map { snippet in
                { model.removeSnippet(snippet) }
            }
        ) { title, body, favorite in
            if var snippet {
                snippet.title = title
                snippet.body = body
                snippet.isFavorite = favorite
                model.updateSnippet(snippet)
            } else {
                model.addSnippet(
                    title: title,
                    body: body,
                    favorite: favorite
                )
            }
        }
    }

    private var composer: some View {
        HStack(spacing: 0) {
            snippetSidebar

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(composerTitle)
                        .font(.title2.weight(.semibold))

                    Spacer()

                    Button {
                        model.requestImagePaste()
                    } label: {
                        Image(systemName: "photo")
                    }
                    .keyboardShortcut("v", modifiers: [.option])
                    .help("Paste image (⌥V)")

                    Button("Send") {
                        model.send()
                    }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .buttonStyle(.borderedProminent)
                    .disabled(model.editorText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(18)

                Divider()

                PromptEditorArea(model: model)
                .padding(12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var snippetSidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Templates")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button {
                            snippetEditorPresentation = .new
                        } label: {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.borderless)
                        .help("New snippet")
                    }

                    ForEach(Array(model.snippets.prefix(9).enumerated()), id: \.element.id) { index, snippet in
                        shortcutSlot(snippet, shortcutNumber: index + 1)
                    }

                    if !model.favoriteSnippets.isEmpty {
                        Divider()

                        Text("Favorites")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        ForEach(model.favoriteSnippets.prefix(9)) { snippet in
                            Button {
                                model.insert(snippet)
                            } label: {
                                Label(snippet.title, systemImage: "star.fill")
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    Divider()

                    HStack {
                        Text("History")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Spacer()

                        if !model.history.isEmpty {
                            Button {
                                showingHistoryClearConfirmation = true
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Clear history")
                        }
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search history", text: $historySearch)
                            .textFieldStyle(.plain)
                    }
                    .padding(7)
                    .background(.background, in: RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.quaternary)
                    }

                    if visibleHistory.isEmpty {
                        Text(model.history.isEmpty ? "Sent prompts appear here." : "No matching prompts.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(visibleHistory) { entry in
                            historyRow(entry)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)

            HStack {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("Settings")

                Spacer()
            }
        }
        .padding(14)
        .frame(
            minWidth: 250,
            idealWidth: 250,
            maxWidth: 250,
            maxHeight: .infinity,
            alignment: .top
        )
        .background(.quaternary.opacity(0.18))
        .alert("Clear prompt history?", isPresented: $showingHistoryClearConfirmation) {
            Button("Clear", role: .destructive) {
                model.clearHistory()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This cannot be undone.")
        }
    }

    private var visibleHistory: [PromptHistoryEntry] {
        model.searchHistory(historySearch)
    }

    private func historyRow(_ entry: PromptHistoryEntry) -> some View {
        HStack(alignment: .top, spacing: 5) {
            Button {
                model.loadHistoryEntry(entry)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(historyPreview(entry.prompt))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 4) {
                        Text(entry.sessionTitle)
                            .lineLimit(1)
                        Text("·")
                        TimelineView(.periodic(from: Date(), by: 30)) { context in
                            Text(PromptHistoryTime.label(
                                for: entry.sentAt,
                                relativeTo: context.date
                            ))
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Load prompt into editor")

            Button {
                model.removeHistoryEntry(entry)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Delete history entry")
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .background(.background.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
    }

    private func historyPreview(_ prompt: String) -> String {
        prompt
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func shortcutSlot(_ snippet: Snippet, shortcutNumber: Int) -> some View {
        templateSlot(snippet, shortcutNumber: shortcutNumber)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onDrop(of: [UTType.text], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }

            provider.loadDataRepresentation(forTypeIdentifier: UTType.text.identifier) { data, _ in
                guard
                    let data,
                    let string = String(data: data, encoding: .utf8),
                    let snippetID = UUID(uuidString: string)
                else { return }

                Task { @MainActor in
                    model.moveSnippet(id: snippetID, toShortcutNumber: shortcutNumber)
                }
            }
            return true
        }
    }

    private func templateSlot(_ snippet: Snippet, shortcutNumber: Int) -> some View {
        HStack(spacing: 4) {
            Button {
                model.insert(snippet)
            } label: {
                HStack(spacing: 0) {
                    Text("⌘\(shortcutNumber)")
                        .font(.caption.monospaced().weight(.semibold))
                        .frame(width: 34, alignment: .leading)

                    Text(snippet.title)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .keyboardShortcut(
                KeyEquivalent(Character(String(shortcutNumber))),
                modifiers: [.command]
            )

            Button {
                snippetEditorPresentation = .edit(snippet)
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .padding(.vertical, 6)
            .help("Edit snippet")

        }
        .draggable(snippet.id.uuidString)
    }

}
