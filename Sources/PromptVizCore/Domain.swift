import Foundation

public enum CodexTerminalInputParser {
    private static let statusExpression = try? NSRegularExpression(
        pattern: #"^.+ · .+ · Context [0-9]+% left$"#
    )

    public static func extractDraft(from screen: String) -> String? {
        let lines = screen.components(separatedBy: "\n")
        guard
            let statusIndex = lines.lastIndex(where: isStatusLine),
            let markerIndex = lines[..<statusIndex].lastIndex(where: isPromptMarker)
        else { return nil }

        var renderedLines = Array(lines[markerIndex..<statusIndex])
        while renderedLines.last?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            renderedLines.removeLast()
        }

        guard let firstLine = renderedLines.first,
              let marker = firstLine.firstIndex(of: "›")
        else { return nil }

        var draft = String(firstLine[firstLine.index(after: marker)...])
        if draft.hasPrefix("  ") {
            draft.removeFirst(2)
        } else if draft.first == " " {
            draft.removeFirst()
        }

        for line in renderedLines.dropFirst() {
            if line.hasPrefix("    ") {
                draft.append("\n")
                draft.append(contentsOf: line.dropFirst(4))
            } else if line.hasPrefix("  ") {
                draft.append(contentsOf: line.dropFirst(2))
            } else {
                draft.append("\n")
                draft.append(contentsOf: line)
            }
        }

        return draft
    }

    private static func isPromptMarker(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).first == "›"
    }

    private static func isStatusLine(_ line: String) -> Bool {
        let normalized = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              let statusExpression
        else { return false }

        let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        return statusExpression.firstMatch(in: normalized, range: range) != nil
    }
}

public enum CodexDraftEditor {
    public static func prepareForContinuation(_ draft: String) -> String {
        guard !draft.isEmpty, draft.last?.isWhitespace != true else { return draft }
        return draft + " "
    }
}

public struct SkillDescriptor: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let description: String
    public let sourcePath: String

    public init(id: String, name: String, description: String, sourcePath: String) {
        self.id = id
        self.name = name
        self.description = description
        self.sourcePath = sourcePath
    }
}

public enum SkillManifestParser {
    public static func parse(
        _ content: String,
        fallbackName: String,
        sourcePath: String
    ) -> SkillDescriptor? {
        let lines = content.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) == "---" else {
            return nil
        }

        guard let endIndex = lines.dropFirst().firstIndex(where: {
            $0.trimmingCharacters(in: .whitespacesAndNewlines) == "---"
        }) else {
            return nil
        }

        var name: String?
        var description = ""

        for line in lines[1..<endIndex] {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = line[line.index(after: separator)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)

            switch key {
            case "name":
                name = scalar(value)
            case "description":
                description = scalar(value)
            default:
                continue
            }
        }

        let resolvedName = (name ?? fallbackName).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolvedName.isEmpty else { return nil }

        return SkillDescriptor(
            id: sourcePath,
            name: resolvedName,
            description: description,
            sourcePath: sourcePath
        )
    }

    private static func scalar(_ value: String) -> String {
        guard value.count >= 2 else { return value }
        let first = value.first
        let last = value.last
        guard (first == "\"" && last == "\"") || (first == "'" && last == "'") else {
            return value
        }
        return String(value.dropFirst().dropLast())
    }
}

public struct Workspace: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let terminalSessionID: String
    public var terminalProcessIdentifier: Int32
    public var terminalTTY: String?
    public var title: String
    public var draft: String
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        terminalSessionID: String,
        terminalProcessIdentifier: Int32 = 0,
        terminalTTY: String? = nil,
        title: String,
        draft: String = "",
        createdAt: Date,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.terminalSessionID = terminalSessionID
        self.terminalProcessIdentifier = terminalProcessIdentifier
        self.terminalTTY = terminalTTY
        self.title = title
        self.draft = draft
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }
}

public struct TerminalSessionInventory: Equatable, Sendable {
    public let sessionIDs: Set<String>
    public let isComplete: Bool

    public init(sessionIDs: Set<String>, isComplete: Bool) {
        self.sessionIDs = sessionIDs
        self.isComplete = isComplete
    }

    public init(sessionIDs: Set<String>, tabCount: Int, enumerationSucceeded: Bool) {
        self.sessionIDs = sessionIDs
        self.isComplete = enumerationSucceeded && tabCount >= 0 && sessionIDs.count == tabCount
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
    private var missingSessionObservations: [String: Int] = [:]

    public init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    @discardableResult
    public func workspace(
        for terminalSessionID: String,
        title: String,
        terminalTTY: String? = nil,
        terminalProcessIdentifier: Int32 = 0
    ) -> Workspace {
        if let index = workspaces.firstIndex(where: { $0.terminalSessionID == terminalSessionID }) {
            workspaces[index].title = title
            if terminalProcessIdentifier != 0 {
                workspaces[index].terminalProcessIdentifier = terminalProcessIdentifier
            }
            if let terminalTTY {
                workspaces[index].terminalTTY = terminalTTY
            }
            return workspaces[index]
        }

        let workspace = Workspace(
            terminalSessionID: terminalSessionID,
            terminalProcessIdentifier: terminalProcessIdentifier,
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

    public func removeClosedWorkspaces(using inventory: TerminalSessionInventory) {
        // Terminal can briefly expose an empty or partial snapshot while a tab
        // is being selected. Such a snapshot is never evidence of closure.
        guard inventory.isComplete, !inventory.sessionIDs.isEmpty else { return }

        let liveSessionIDs = inventory.sessionIDs
        for workspace in workspaces {
            let sessionID = workspace.terminalSessionID
            if liveSessionIDs.contains(sessionID) {
                missingSessionObservations.removeValue(forKey: sessionID)
            } else {
                missingSessionObservations[sessionID, default: 0] += 1
            }
        }

        let closedSessionIDs = Set(
            missingSessionObservations
                .filter { $0.value >= 2 }
                .map(\.key)
        )
        guard !closedSessionIDs.isEmpty else { return }

        workspaces.removeAll { closedSessionIDs.contains($0.terminalSessionID) }
        for sessionID in closedSessionIDs {
            missingSessionObservations.removeValue(forKey: sessionID)
        }
    }

    public func removeWorkspace(id: UUID) {
        guard let workspace = workspaces.first(where: { $0.id == id }) else { return }
        missingSessionObservations.removeValue(forKey: workspace.terminalSessionID)
        workspaces.removeAll { $0.id == id }
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
