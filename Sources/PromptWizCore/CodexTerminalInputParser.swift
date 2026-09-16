import Foundation

import Foundation

public enum CodexTerminalInputParser {
    private static let emptyComposerPlaceholder = "Ask Codex to do anything"
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

        return draft == emptyComposerPlaceholder ? "" : draft
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
