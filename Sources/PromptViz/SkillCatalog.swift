import Foundation
import PromptVizCore

final class SkillCatalog {
    private let fileManager: FileManager
    private let roots: [URL]

    init(fileManager: FileManager = .default, roots: [URL]? = nil) {
        self.fileManager = fileManager
        self.roots = roots ?? Self.defaultRoots(fileManager: fileManager)
    }

    func scan() -> [SkillDescriptor] {
        var discovered: [String: SkillDescriptor] = [:]

        for root in roots {
            guard fileManager.fileExists(atPath: root.path) else { continue }
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: []
            ) else { continue }

            for case let url as URL in enumerator where url.lastPathComponent == "SKILL.md" {
                guard
                    let content = try? String(contentsOf: url, encoding: .utf8),
                    let skill = SkillManifestParser.parse(
                        content,
                        fallbackName: url.deletingLastPathComponent().lastPathComponent,
                        sourcePath: url.path
                    )
                else { continue }

                let key = skill.name.folding(
                    options: [.caseInsensitive, .diacriticInsensitive],
                    locale: .current
                )
                if discovered[key] == nil {
                    discovered[key] = skill
                }
            }
        }

        return discovered.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func search(_ query: String, in skills: [SkillDescriptor]) -> [SkillDescriptor] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)

        guard !normalized.isEmpty else { return skills }

        return skills.filter { skill in
            let haystack = "\(skill.name) \(skill.description)"
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            return haystack.contains(normalized)
        }
    }

    private static func defaultRoots(fileManager: FileManager) -> [URL] {
        let home = fileManager.homeDirectoryForCurrentUser
        let project = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)

        return [
            home.appendingPathComponent(".codex/skills", isDirectory: true),
            home.appendingPathComponent(".codex/plugins/cache", isDirectory: true),
            home.appendingPathComponent("LLM/agent-skills/skills", isDirectory: true),
            project.appendingPathComponent(".agents/skills", isDirectory: true),
            project.appendingPathComponent(".codex/skills", isDirectory: true)
        ]
    }
}
