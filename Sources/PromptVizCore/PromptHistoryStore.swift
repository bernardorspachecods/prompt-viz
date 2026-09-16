import Foundation

public final class PromptHistoryStore {
    public private(set) var entries: [PromptHistoryEntry]
    public let limit: Int

    public init(entries: [PromptHistoryEntry] = [], limit: Int = 100) {
        self.limit = max(1, limit)
        self.entries = Self.normalized(entries, limit: self.limit)
    }

    @discardableResult
    public func add(
        prompt: String,
        sessionTitle: String,
        sentAt: Date = Date(),
        imageAttachments: [PromptImageAttachment] = []
    ) -> PromptHistoryEntry {
        let entry = PromptHistoryEntry(
            prompt: prompt,
            sessionTitle: sessionTitle,
            sentAt: sentAt,
            imageAttachments: imageAttachments
        )
        entries = Self.normalized(entries + [entry], limit: limit)
        return entry
    }

    public func search(_ query: String) -> [PromptHistoryEntry] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return entries }

        return entries.filter {
            $0.prompt.localizedCaseInsensitiveContains(normalizedQuery) ||
                $0.sessionTitle.localizedCaseInsensitiveContains(normalizedQuery)
        }
    }

    public func remove(id: UUID) {
        entries.removeAll { $0.id == id }
    }

    public func removeAll() {
        entries.removeAll()
    }

    private static func normalized(
        _ entries: [PromptHistoryEntry],
        limit: Int
    ) -> [PromptHistoryEntry] {
        let indexed = entries.enumerated().sorted { left, right in
            if left.element.sentAt != right.element.sentAt {
                return left.element.sentAt > right.element.sentAt
            }
            return left.offset < right.offset
        }
        return Array(indexed.map(\.element).prefix(limit))
    }
}
