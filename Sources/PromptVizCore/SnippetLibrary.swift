import Foundation

public final class SnippetLibrary {
    public private(set) var snippets: [Snippet]

    public init(snippets: [Snippet]? = nil) {
        var normalizedSnippets = (snippets ?? Self.makeDefaults())
            .enumerated()
            .sorted {
                switch ($0.element.shortcutNumber, $1.element.shortcutNumber) {
                case let (left?, right?):
                    return left < right
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return $0.offset < $1.offset
                }
            }
            .map(\.element)
        Self.compactShortcuts(in: &normalizedSnippets)

        self.snippets = normalizedSnippets
    }

    public var favorites: [Snippet] {
        snippets.filter(\.isFavorite)
    }

    @discardableResult
    public func add(_ snippet: Snippet) -> Bool {
        guard snippets.count < 9 else { return false }
        snippets.append(snippet)
        compactShortcuts()
        return true
    }

    public func update(_ snippet: Snippet) {
        guard let index = snippets.firstIndex(where: { $0.id == snippet.id }) else { return }
        snippets[index] = snippet
    }

    public func remove(id: UUID) {
        snippets.removeAll { $0.id == id }
        compactShortcuts()
    }

    public func moveSnippet(_ snippetID: UUID, toShortcutNumber shortcutNumber: Int) {
        guard (1...9).contains(shortcutNumber),
              let currentIndex = snippets.firstIndex(where: { $0.id == snippetID }),
              !snippets.isEmpty
        else { return }

        let targetIndex = min(shortcutNumber - 1, snippets.count - 1)
        guard currentIndex != targetIndex else { return }

        let snippet = snippets.remove(at: currentIndex)
        snippets.insert(snippet, at: targetIndex)
        compactShortcuts()
    }

    private func compactShortcuts() {
        Self.compactShortcuts(in: &snippets)
    }

    private static func compactShortcuts(in snippets: inout [Snippet]) {
        for index in snippets.indices {
            snippets[index].shortcutNumber = index < 9 ? index + 1 : nil
        }
    }

    private static func makeDefaults() -> [Snippet] {
        [
            Snippet(title: "Be honest", body: "Be honest about what you know and what you don't know.", isFavorite: true),
            Snippet(title: "No bias", body: "Analyze the problem without bias and make the trade-offs explicit.", isFavorite: true),
            Snippet(title: "Don't assume", body: "Don't assume information that wasn't provided; call out uncertainties."),
            Snippet(title: "Explain step by step", body: "Explain the reasoning step by step, clearly and concisely."),
            Snippet(title: "Review the result", body: "At the end, review the result and point out possible failures or edge cases.")
        ]
    }
}
