import Foundation

public struct PromptImageAttachment: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let number: Int
    public let data: Data

    public init(id: UUID = UUID(), number: Int, data: Data) {
        self.id = id
        self.number = number
        self.data = data
    }
}

public enum PromptEditorTokenKind: Equatable, Sendable {
    case imageReference
    case skillReference
}

public struct PromptEditorToken: Equatable, Sendable {
    public let kind: PromptEditorTokenKind
    public let range: NSRange

    public init(kind: PromptEditorTokenKind, range: NSRange) {
        self.kind = kind
        self.range = range
    }
}

public enum PromptEditorTokens {
    private static let imageExpression = try! NSRegularExpression(
        pattern: #"\[Image #[0-9]+\]"#
    )
    private static let skillExpression = try! NSRegularExpression(
        pattern: #"\$[A-Za-z0-9_-]+"#
    )

    public static func tokens(in text: String) -> [PromptEditorToken] {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let imageTokens = imageExpression.matches(in: text, range: fullRange).map {
            PromptEditorToken(kind: .imageReference, range: $0.range)
        }
        let skillTokens = skillExpression.matches(in: text, range: fullRange).map {
            PromptEditorToken(kind: .skillReference, range: $0.range)
        }

        return (imageTokens + skillTokens).sorted {
            if $0.range.location != $1.range.location {
                return $0.range.location < $1.range.location
            }
            return $0.range.length < $1.range.length
        }
    }

    public static func editingRange(
        for affectedRange: NSRange,
        in text: String
    ) -> NSRange? {
        editingRange(
            for: affectedRange,
            tokenRanges: tokens(in: text).map(\.range)
        )
    }

    public static func editingRange(
        for affectedRange: NSRange,
        in text: String,
        restrictedTo tokenRanges: [NSRange]
    ) -> NSRange? {
        editingRange(for: affectedRange, tokenRanges: tokenRanges)
    }

    private static func editingRange(
        for affectedRange: NSRange,
        tokenRanges: [NSRange]
    ) -> NSRange? {
        guard affectedRange.location >= 0, affectedRange.length >= 0 else { return nil }

        let editStart = affectedRange.location
        let editEnd = affectedRange.location + affectedRange.length

        var expandedRange: NSRange?
        for tokenRange in tokenRanges {
            let tokenStart = tokenRange.location
            let tokenEnd = tokenRange.location + tokenRange.length

            if affectedRange.length == 0 {
                if editStart > tokenStart && editStart < tokenEnd {
                    return tokenRange
                }
                continue
            }

            guard editStart < tokenEnd && editEnd > tokenStart else { continue }
            expandedRange = expandedRange.map {
                NSUnionRange($0, tokenRange)
            } ?? NSUnionRange(affectedRange, tokenRange)
        }

        return expandedRange
    }
}
