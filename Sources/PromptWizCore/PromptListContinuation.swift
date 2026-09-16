import Foundation

public struct PromptListEdit: Equatable, Sendable {
    public let range: NSRange
    public let replacement: String

    public init(range: NSRange, replacement: String) {
        self.range = range
        self.replacement = replacement
    }
}

public enum PromptListContinuation {
    private static let markerExpression = try! NSRegularExpression(
        pattern: #"^([ \t]*)(?:(\d+)\.|-)(.*)$"#
    )

    public static func edit(
        in text: String,
        selectionRange: NSRange
    ) -> PromptListEdit? {
        let nsText = text as NSString
        let textLength = nsText.length
        let cursor = selectionRange.location

        guard selectionRange.length == 0,
              cursor >= 0,
              cursor <= textLength
        else { return nil }

        let lineStart = lineStart(in: nsText, before: cursor)
        let lineEnd = lineEnd(in: nsText, from: cursor)
        let lineRange = NSRange(location: lineStart, length: lineEnd - lineStart)
        let line = nsText.substring(with: lineRange)
        let lineRangeInLine = NSRange(location: 0, length: (line as NSString).length)

        guard let match = markerExpression.firstMatch(in: line, range: lineRangeInLine),
              match.range.location == 0
        else { return nil }

        let indent = (line as NSString).substring(with: match.range(at: 1))
        let numberRange = match.range(at: 2)
        let numberText = numberRange.location == NSNotFound
            ? ""
            : (line as NSString).substring(with: numberRange)
        let suffix = (line as NSString).substring(with: match.range(at: 3))
        guard suffix.isEmpty || suffix.first == " " || suffix.first == "\t" else {
            return nil
        }

        let content = suffix.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasNumberedMarker = match.range(at: 2).location != NSNotFound
        let nextMarker: String

        if hasNumberedMarker {
            guard let number = Int(numberText), number < Int.max else { return nil }
            nextMarker = "\(number + 1)."
        } else {
            nextMarker = "-"
        }

        if content.isEmpty, cursor == lineEnd, !suffix.isEmpty {
            return PromptListEdit(
                range: lineRange,
                replacement: "\n"
            )
        }

        return PromptListEdit(
            range: selectionRange,
            replacement: "\n\(indent)\(nextMarker) "
        )
    }

    private static func lineStart(in text: NSString, before location: Int) -> Int {
        guard location > 0 else { return 0 }

        let searchRange = NSRange(location: 0, length: location)
        let newline = text.range(of: "\n", options: .backwards, range: searchRange)
        return newline.location == NSNotFound ? 0 : NSMaxRange(newline)
    }

    private static func lineEnd(in text: NSString, from location: Int) -> Int {
        let searchRange = NSRange(location: location, length: text.length - location)
        let newline = text.range(of: "\n", options: [], range: searchRange)
        return newline.location == NSNotFound ? text.length : newline.location
    }
}
