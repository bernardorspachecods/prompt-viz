import Foundation

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
