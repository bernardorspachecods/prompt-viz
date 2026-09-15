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
            try codexTerminalInputContracts()
            try skillManifestContracts()
            try snippetContracts()
            print("PromptViz contracts: PASS (21 checks)")
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
        let first = store.workspace(
            for: "/dev/ttys001",
            title: "Codex A",
            terminalTTY: "/dev/ttys001",
            terminalProcessIdentifier: 101
        )
        let reused = store.workspace(
            for: "/dev/ttys001",
            title: "Codex A atualizado",
            terminalTTY: "/dev/ttys001",
            terminalProcessIdentifier: 101
        )
        let second = store.workspace(
            for: "/dev/ttys002",
            title: "Codex B",
            terminalTTY: "/dev/ttys002",
            terminalProcessIdentifier: 101
        )

        try check(first.id == reused.id, "same terminal session reuses workspace")
        try check(store.workspace(id: first.id)?.title == "Codex A atualizado", "workspace title follows active session")
        try check(store.workspaces.count == 2, "different tabs in one Terminal window keep separate workspaces")
        try check(
            store.workspace(id: first.id)?.terminalProcessIdentifier == 101,
            "workspace keeps the Terminal process identifier separately from the tab identity"
        )
        store.updateDraft("Prompt A", for: first.id)
        store.updateDraft("Prompt B", for: second.id)
        try check(store.workspace(id: first.id)?.draft == "Prompt A", "workspace A keeps its draft")
        try check(store.workspace(id: second.id)?.draft == "Prompt B", "workspace B keeps its draft")
        store.removeWorkspace(for: "/dev/ttys001")
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

    private static func codexTerminalInputContracts() throws {
        let screen = """
        output anterior
        ──────────────────────────────────────────────────────────────────────────────

        ›  PROMPT_VIZ_BEGIN
            primeira linha\u{20}
          continua na mesma linha
            terceira linha

          gpt-5.6-luna high · prompt-viz · Context 70% left

        """

        try check(
            CodexTerminalInputParser.extractDraft(from: screen) ==
                "PROMPT_VIZ_BEGIN\nprimeira linha continua na mesma linha\nterceira linha",
            "Codex input parser preserves real newlines and joins visual wraps"
        )
        try check(
            CodexTerminalInputParser.extractDraft(
                from: "›  \n  gpt-5.6-luna high · prompt-viz · Context 70% left\n"
            ) == "",
            "Codex input parser recognizes an empty draft"
        )
        try check(
            CodexTerminalInputParser.extractDraft(from: "terminal output only") == nil,
            "Codex input parser refuses an unrecognized terminal screen"
        )
        try check(
            CodexTerminalInputParser.extractDraft(
                from: "›  última palavra \n  gpt-5.6-luna high · prompt-viz · Context 70% left\n"
            ) == "última palavra ",
            "Codex input parser preserves a trailing space"
        )
        try check(
            CodexDraftEditor.prepareForContinuation("última palavra") == "última palavra ",
            "captured drafts receive a continuation space"
        )
        try check(
            CodexDraftEditor.prepareForContinuation("última palavra ") == "última palavra ",
            "existing trailing spaces are not duplicated"
        )
    }

    private static func skillManifestContracts() throws {
        let manifest = """
        ---
        name: "example-skill"
        description: "A skill for testing discovery."
        ---
        # Example
        """
        let skill = SkillManifestParser.parse(
            manifest,
            fallbackName: "fallback",
            sourcePath: "/tmp/example/SKILL.md"
        )

        try check(skill?.name == "example-skill", "skill name is read from frontmatter")
        try check(skill?.description == "A skill for testing discovery.", "skill description is read from frontmatter")
        try check(
            SkillManifestParser.parse("# Not a skill", fallbackName: "fallback", sourcePath: "/tmp/nope") == nil,
            "files without frontmatter are ignored"
        )
    }
}
