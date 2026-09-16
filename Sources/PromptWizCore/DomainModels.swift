import Foundation

public struct Workspace: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let terminalSessionID: String
    public var terminalProcessIdentifier: Int32
    public var terminalTTY: String?
    public var title: String
    public var draft: String
    public var imageAttachments: [PromptImageAttachment]
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        terminalSessionID: String,
        terminalProcessIdentifier: Int32 = 0,
        terminalTTY: String? = nil,
        title: String,
        draft: String = "",
        imageAttachments: [PromptImageAttachment] = [],
        createdAt: Date,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.terminalSessionID = terminalSessionID
        self.terminalProcessIdentifier = terminalProcessIdentifier
        self.terminalTTY = terminalTTY
        self.title = title
        self.draft = draft
        self.imageAttachments = imageAttachments
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
    public var shortcutNumber: Int?

    public init(
        id: UUID = UUID(),
        title: String,
        body: String,
        isFavorite: Bool = false,
        shortcutNumber: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.isFavorite = isFavorite
        self.shortcutNumber = shortcutNumber
    }
}

public struct PromptHistoryEntry: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let prompt: String
    public let sessionTitle: String
    public let sentAt: Date
    public let imageAttachments: [PromptImageAttachment]

    public init(
        id: UUID = UUID(),
        prompt: String,
        sessionTitle: String,
        sentAt: Date,
        imageAttachments: [PromptImageAttachment] = []
    ) {
        self.id = id
        self.prompt = prompt
        self.sessionTitle = sessionTitle
        self.sentAt = sentAt
        self.imageAttachments = imageAttachments
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case prompt
        case sessionTitle
        case sentAt
        case imageAttachments
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.prompt = try container.decode(String.self, forKey: .prompt)
        self.sessionTitle = try container.decode(String.self, forKey: .sessionTitle)
        self.sentAt = try container.decode(Date.self, forKey: .sentAt)
        self.imageAttachments = try container.decodeIfPresent(
            [PromptImageAttachment].self,
            forKey: .imageAttachments
        ) ?? []
    }
}

public enum PromptHistoryTime {
    public static func label(
        for date: Date,
        relativeTo now: Date = Date()
    ) -> String {
        let elapsed = max(0, now.timeIntervalSince(date))
        let minutes = Int(elapsed / 60)
        return minutes == 0 ? "now" : "\(minutes)m"
    }
}

public enum PromptImageReference {
    private static let expression = try! NSRegularExpression(
        pattern: #"\[Image #([0-9]+)\]"#
    )

    public static func numbers(in text: String) -> [Int] {
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        var seen = Set<Int>()

        return expression.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            let number = Int(nsText.substring(with: match.range(at: 1)))
            guard let number, seen.insert(number).inserted else { return nil }
            return number
        }
    }

    public static func nextNumber(in text: String) -> Int {
        (numbers(in: text).max() ?? 0) + 1
    }
}
