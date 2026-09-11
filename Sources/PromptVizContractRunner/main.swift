import Foundation
import Darwin
import PromptVizCore

struct ContractFailure: Error, CustomStringConvertible {
    let message: String

    var description: String { message }
}

@main
struct PromptVizContractRunner {
    static func main() {
        do {
            try templateContracts()
            try workspaceContracts()
            try snippetContracts()
            print("PromptViz contracts: PASS (8 checks)")
        } catch {
            fputs("PromptViz contracts: FAIL — \(error)\n", stderr)
            exit(1)
        }
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw ContractFailure(message: message) }
    }

    private static func templateContracts() throws {
        let template = "Analisa este código em {{linguagem}} com foco em {{objetivo}}."
        try check(TemplateEngine.fieldNames(in: template) == ["linguagem", "objetivo"], "template fields preserve order")
        try check(
            TemplateEngine.render(template, values: ["linguagem": "Swift", "objetivo": "segurança"]) ==
                "Analisa este código em Swift com foco em segurança.",
            "template values render"
        )
        try check(
            TemplateEngine.fieldNames(in: "{{nome}} e {{nome}}") == ["nome"],
            "repeated template fields are navigated once"
        )
    }

    private static func workspaceContracts() throws {
        let store = WorkspaceStore(now: { Date(timeIntervalSince1970: 100) })
        let first = store.workspace(for: "terminal-tab-a", title: "Codex A")
        let reused = store.workspace(for: "terminal-tab-a", title: "Codex A atualizado")
        let second = store.workspace(for: "terminal-tab-b", title: "Codex B")

        try check(first.id == reused.id, "same terminal session reuses workspace")
        try check(store.workspace(id: first.id)?.title == "Codex A atualizado", "workspace title follows active session")
        store.updateDraft("Prompt A", for: first.id)
        store.updateDraft("Prompt B", for: second.id)
        try check(store.workspace(id: first.id)?.draft == "Prompt A", "workspace A keeps its draft")
        try check(store.workspace(id: second.id)?.draft == "Prompt B", "workspace B keeps its draft")
        store.removeWorkspace(for: "terminal-tab-a")
        try check(store.workspace(id: first.id) == nil, "closed terminal session removes workspace")
    }

    private static func snippetContracts() throws {
        let library = SnippetLibrary(snippets: [
            Snippet(title: "Sê honesto", body: "Sê honesto.", isFavorite: true),
            Snippet(title: "Sem bias", body: "Analisa sem bias.")
        ])

        try check(library.favorites.map(\.title) == ["Sê honesto"], "favorites are filtered")
        try check(library.search("BIAS").map(\.title) == ["Sem bias"], "snippet search ignores case")
    }
}
