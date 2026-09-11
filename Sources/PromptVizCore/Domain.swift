import Foundation

public enum TerminalInputRouting {
    public static func shouldMirror(selectedTTY: String?, observedTTY: String?) -> Bool {
        guard let selectedTTY, let observedTTY else { return false }
        return selectedTTY == observedTTY
    }
}

public struct Workspace: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let terminalSessionID: String
    public var terminalTTY: String?
    public var title: String
    public var draft: String
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        terminalSessionID: String,
        terminalTTY: String? = nil,
        title: String,
        draft: String = "",
        createdAt: Date,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.terminalSessionID = terminalSessionID
        self.terminalTTY = terminalTTY
        self.title = title
        self.draft = draft
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }
}

public struct Snippet: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public var body: String
    public var isFavorite: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        body: String,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.isFavorite = isFavorite
    }
}

public enum TemplateEngine {
    private static let pattern = #"\{\{\s*([^{}]+?)\s*\}\}"#

    public static func fieldNames(in template: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(template.startIndex..<template.endIndex, in: template)
        var names: [String] = []

        expression.enumerateMatches(in: template, range: range) { match, _, _ in
            guard
                let match,
                match.numberOfRanges > 1,
                let nameRange = Range(match.range(at: 1), in: template)
            else { return }

            let name = String(template[nameRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty, !names.contains(name) {
                names.append(name)
            }
        }

        return names
    }

    public static func render(_ template: String, values: [String: String]) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return template }
        let range = NSRange(template.startIndex..<template.endIndex, in: template)
        let rendered = NSMutableString(string: template)
        let matches = expression.matches(in: template, range: range)

        for match in matches.reversed() {
            guard
                match.numberOfRanges > 1,
                let nameRange = Range(match.range(at: 1), in: template),
                let replacementRange = Range(match.range, in: template)
            else { continue }

            let name = String(template[nameRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            rendered.replaceCharacters(
                in: NSRange(replacementRange, in: template),
                with: values[name] ?? ""
            )
        }

        return String(rendered)
    }
}

public final class WorkspaceStore {
    public private(set) var workspaces: [Workspace] = []
    private let now: () -> Date

    public init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    @discardableResult
    public func workspace(
        for terminalSessionID: String,
        title: String,
        terminalTTY: String? = nil
    ) -> Workspace {
        if let index = workspaces.firstIndex(where: { $0.terminalSessionID == terminalSessionID }) {
            workspaces[index].title = title
            if let terminalTTY {
                workspaces[index].terminalTTY = terminalTTY
            }
            return workspaces[index]
        }

        let workspace = Workspace(
            terminalSessionID: terminalSessionID,
            terminalTTY: terminalTTY,
            title: title,
            createdAt: now()
        )
        workspaces.append(workspace)
        return workspace
    }

    public func workspace(id: UUID) -> Workspace? {
        workspaces.first(where: { $0.id == id })
    }

    public func updateDraft(_ draft: String, for workspaceID: UUID) {
        guard let index = workspaces.firstIndex(where: { $0.id == workspaceID }) else { return }
        workspaces[index].draft = draft
        workspaces[index].updatedAt = now()
    }

    public func removeWorkspace(for terminalSessionID: String) {
        workspaces.removeAll { $0.terminalSessionID == terminalSessionID }
    }
}

public final class SnippetLibrary {
    public private(set) var snippets: [Snippet]

    public init(snippets: [Snippet]? = nil) {
        self.snippets = snippets ?? Self.makeDefaults()
    }

    public var favorites: [Snippet] {
        snippets.filter(\.isFavorite)
    }

    public func search(_ query: String) -> [Snippet] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)

        guard !normalized.isEmpty else { return snippets }

        return snippets.filter { snippet in
            let haystack = "\(snippet.title) \(snippet.body)"
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            return haystack.contains(normalized)
        }
    }

    public func add(_ snippet: Snippet) {
        snippets.append(snippet)
    }

    public func update(_ snippet: Snippet) {
        guard let index = snippets.firstIndex(where: { $0.id == snippet.id }) else { return }
        snippets[index] = snippet
    }

    public func remove(id: UUID) {
        snippets.removeAll { $0.id == id }
    }

    private static func makeDefaults() -> [Snippet] {
        [
            Snippet(title: "Sê honesto", body: "Sê honesto sobre o que sabes e o que não sabes.", isFavorite: true),
            Snippet(title: "Sem bias", body: "Analisa o problema sem bias e explicita os trade-offs.", isFavorite: true),
            Snippet(title: "Não assumas", body: "Não assumas informação que não foi fornecida; indica as incertezas."),
            Snippet(title: "Explica passo a passo", body: "Explica o raciocínio passo a passo, de forma clara e concisa."),
            Snippet(title: "Revisa o resultado", body: "No final, revê o resultado e aponta possíveis falhas ou casos limite."),
            Snippet(title: "Analisa código", body: "Analisa este código em {{linguagem}} com foco em {{objetivo}}.")
        ]
    }
}
