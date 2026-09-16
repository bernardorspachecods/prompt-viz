import Foundation
import PromptVizCore

final class LocalSnippetPersistence {
    private let defaults: UserDefaults
    private let key = "prompt-viz.snippets"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [Snippet]? {
        guard let data = defaults.data(forKey: key) else { return nil }
        guard let snippets = try? JSONDecoder().decode([Snippet].self, from: data) else { return nil }
        return snippets.compactMap { snippet in
            guard snippet.title != "Analisa código" else { return nil }

            var snippet = snippet
            switch (snippet.title, snippet.body) {
            case ("Sê honesto", "Sê honesto sobre o que sabes e o que não sabes."):
                snippet.title = "Be honest"
                snippet.body = "Be honest about what you know and what you don't know."
            case ("Sem bias", "Analisa o problema sem bias e explicita os trade-offs."):
                snippet.title = "No bias"
                snippet.body = "Analyze the problem without bias and make the trade-offs explicit."
            case ("Não assumas", "Não assumas informação que não foi fornecida; indica as incertezas."):
                snippet.title = "Don't assume"
                snippet.body = "Don't assume information that wasn't provided; call out uncertainties."
            case ("Explica passo a passo", "Explica o raciocínio passo a passo, de forma clara e concisa."):
                snippet.title = "Explain step by step"
                snippet.body = "Explain the reasoning step by step, clearly and concisely."
            case ("Revisa o resultado", "No final, revê o resultado e aponta possíveis falhas ou casos limite."):
                snippet.title = "Review the result"
                snippet.body = "At the end, review the result and point out possible failures or edge cases."
            default:
                break
            }
            return snippet
        }
    }

    func save(_ snippets: [Snippet]) {
        guard let data = try? JSONEncoder().encode(snippets) else { return }
        defaults.set(data, forKey: key)
    }
}
final class LocalPromptHistoryPersistence {
    private let defaults: UserDefaults
    private let key = "prompt-viz.prompt-history"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [PromptHistoryEntry] {
        guard
            let data = defaults.data(forKey: key),
            let entries = try? JSONDecoder().decode([PromptHistoryEntry].self, from: data)
        else { return [] }

        return entries
    }

    func save(_ entries: [PromptHistoryEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: key)
    }
}
