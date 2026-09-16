import Foundation
import Darwin
import PromptWizCore

struct ContractFailure: Error, CustomStringConvertible {
    let message: String

    var description: String { message }
}

@main
struct PromptWizContractRunner {
    static func main() {
        do {
            try workspaceContracts()
            try codexTerminalInputContracts()
            try skillManifestContracts()
            try snippetContracts()
            try promptHistoryContracts()
            try promptImageContracts()
            try promptEditorTokenContracts()
            try promptListContinuationContracts()
            print("PromptWiz contracts: PASS (49 checks)")
        } catch {
            fputs("PromptWiz contracts: FAIL — \(error)\n", stderr)
            exit(1)
        }
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw ContractFailure(message: message) }
    }

    private static func workspaceContracts() throws {
        let partialInventory = TerminalSessionInventory(
            sessionIDs: ["/dev/ttys001"],
            tabCount: 2,
            enumerationSucceeded: true
        )
        try check(
            !partialInventory.isComplete,
            "a raw inventory with missing TTYs is incomplete even when AppleScript reports success"
        )

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

        store.removeClosedWorkspaces(using: TerminalSessionInventory(
            sessionIDs: ["/dev/ttys002"],
            isComplete: false
        ))
        try check(
            store.workspaces.count == 2,
            "an incomplete terminal inventory never removes an unfocused workspace"
        )

        store.removeClosedWorkspaces(using: TerminalSessionInventory(
            sessionIDs: [],
            isComplete: true
        ))
        try check(
            store.workspaces.count == 2,
            "an empty terminal inventory never removes workspaces"
        )

        store.removeClosedWorkspaces(using: TerminalSessionInventory(
            sessionIDs: ["/dev/ttys002"],
            isComplete: true
        ))
        try check(
            store.workspace(id: first.id) != nil,
            "a single missing-session observation does not remove a workspace"
        )

        store.removeClosedWorkspaces(using: TerminalSessionInventory(
            sessionIDs: ["/dev/ttys001", "/dev/ttys002"],
            isComplete: true
        ))
        try check(
            store.workspaces.count == 2,
            "a session returning after a transient absence keeps both workspaces"
        )

        store.removeClosedWorkspaces(using: TerminalSessionInventory(
            sessionIDs: ["/dev/ttys002"],
            isComplete: true
        ))
        try check(
            store.workspace(id: first.id) != nil,
            "the first confirmed missing-session observation keeps the workspace"
        )

        store.removeClosedWorkspaces(using: TerminalSessionInventory(
            sessionIDs: ["/dev/ttys002"],
            isComplete: true
        ))
        try check(store.workspace(id: first.id) == nil, "closed terminal session removes workspace")
        try check(store.workspace(id: second.id) != nil, "present terminal session keeps its workspace")
    }

    private static func snippetContracts() throws {
        let library = SnippetLibrary(snippets: [
            Snippet(title: "Sê honesto", body: "Sê honesto.", isFavorite: true),
            Snippet(title: "Sem bias", body: "Analisa sem bias.")
        ])

        try check(library.favorites.map(\.title) == ["Sê honesto"], "favorites are filtered")
        try check(
            library.snippets.compactMap(\.shortcutNumber) == [1, 2],
            "templates occupy consecutive command-number shortcuts"
        )

        library.moveSnippet(library.snippets[0].id, toShortcutNumber: 2)
        try check(
            library.snippets.map(\.title) == ["Sem bias", "Sê honesto"],
            "moving a template to a slot changes template order"
        )
    }

    private static func promptHistoryContracts() throws {
        let history = PromptHistoryStore(limit: 2)
        let first = history.add(
            prompt: "Primeiro prompt",
            sessionTitle: "projeto-a",
            sentAt: Date(timeIntervalSince1970: 100)
        )
        _ = history.add(
            prompt: "Segundo prompt",
            sessionTitle: "projeto-b",
            sentAt: Date(timeIntervalSince1970: 200)
        )
        _ = history.add(
            prompt: "Terceiro prompt",
            sessionTitle: "projeto-a",
            sentAt: Date(timeIntervalSince1970: 300)
        )

        try check(
            history.entries.map(\.prompt) == ["Terceiro prompt", "Segundo prompt"],
            "prompt history keeps newest entries first and respects its limit"
        )
        try check(
            history.search("PROJETO-A").map(\.prompt) == ["Terceiro prompt"],
            "prompt history searches prompt and session title case-insensitively"
        )

        history.remove(id: first.id)
        try check(
            history.entries.map(\.prompt) == ["Terceiro prompt", "Segundo prompt"],
            "removing an entry that was trimmed has no effect"
        )

        history.remove(id: history.entries[0].id)
        try check(
            history.entries.map(\.prompt) == ["Segundo prompt"],
            "prompt history removes an existing entry"
        )
        let imageEntry = history.add(
            prompt: "Prompt with image [Image #1]",
            sessionTitle: "projeto-c",
            sentAt: Date(timeIntervalSince1970: 400),
            imageAttachments: [PromptImageAttachment(number: 1, data: Data([1, 2, 3]))]
        )
        try check(
            imageEntry.imageAttachments.count == 1,
            "prompt history keeps image attachments with the prompt"
        )
        let now = Date(timeIntervalSince1970: 1_000)
        try check(
            PromptHistoryTime.label(
                for: Date(timeIntervalSince1970: 999),
                relativeTo: now
            ) == "now",
            "prompt history uses now during the first minute"
        )
        try check(
            PromptHistoryTime.label(
                for: Date(timeIntervalSince1970: 940),
                relativeTo: now
            ) == "1m",
            "prompt history floors elapsed time to whole minutes"
        )
        try check(
            PromptHistoryTime.label(
                for: Date(timeIntervalSince1970: 880),
                relativeTo: now
            ) == "2m",
            "prompt history increments the minute label only after two minutes"
        )
    }

    private static func promptImageContracts() throws {
        let prompt = "antes [Image #1] e depois [Image #3]"
        try check(
            PromptImageReference.numbers(in: prompt) == [1, 3],
            "prompt image references are read in their display order"
        )
        try check(
            PromptImageReference.nextNumber(in: prompt) == 4,
            "new prompt images receive the next available number"
        )
    }

    private static func promptEditorTokenContracts() throws {
        let prompt = "antes [Image #1] e $grill depois"
        let imageRange = NSRange(prompt.range(of: "[Image #1]", options: .literal)!, in: prompt)
        let skillRange = NSRange(prompt.range(of: "$grill", options: .literal)!, in: prompt)
        let tokens = PromptEditorTokens.tokens(in: prompt)

        try check(
            tokens == [
                PromptEditorToken(kind: .imageReference, range: imageRange),
                PromptEditorToken(kind: .skillReference, range: skillRange)
            ],
            "editor finds image and skill references in their display order"
        )
        try check(
            PromptEditorTokens.editingRange(
                for: NSRange(location: imageRange.location + 2, length: 1),
                in: prompt
            ) == imageRange,
            "editing part of an image reference expands to the whole token"
        )
        try check(
            PromptEditorTokens.editingRange(
                for: NSRange(location: skillRange.location + 2, length: 1),
                in: prompt,
                restrictedTo: [imageRange]
            ) == nil,
            "an unselected skill reference remains normal editable text"
        )
        try check(
            PromptEditorTokens.editingRange(
                for: NSRange(location: skillRange.location + 2, length: 0),
                in: prompt
            ) == skillRange,
            "typing inside a skill reference expands to the whole token"
        )
        try check(
            PromptEditorTokens.editingRange(
                for: NSRange(location: skillRange.upperBound - 1, length: 1),
                in: prompt
            ) == skillRange,
            "backspace at the end of a skill reference removes the whole token"
        )
        let commandDeleteRange = NSRange(location: 0, length: prompt.utf16.count)
        try check(
            PromptEditorTokens.editingRange(for: commandDeleteRange, in: prompt) == commandDeleteRange,
            "a broad command deletion keeps its original range instead of collapsing to a token"
        )
        try check(
            PromptEditorTokens.editingRange(
                for: NSRange(location: imageRange.upperBound, length: 0),
                in: prompt
            ) == nil,
            "typing immediately after a token remains outside the token"
        )
    }

    private static func promptListContinuationContracts() throws {
        let numberedText = "1. primeiro item"
        let numberedEdit = PromptListContinuation.edit(
            in: numberedText,
            selectionRange: NSRange(location: numberedText.utf16.count, length: 0)
        )
        try check(
            numberedEdit == PromptListEdit(
                range: NSRange(location: numberedText.utf16.count, length: 0),
                replacement: "\n2. "
            ),
            "numbered lists continue with the next number"
        )

        let bulletText = "  - primeiro item"
        let bulletEdit = PromptListContinuation.edit(
            in: bulletText,
            selectionRange: NSRange(location: bulletText.utf16.count, length: 0)
        )
        try check(
            bulletEdit == PromptListEdit(
                range: NSRange(location: bulletText.utf16.count, length: 0),
                replacement: "\n  - "
            ),
            "dash lists continue with the same marker and indentation"
        )

        let emptyListText = "1. "
        let emptyListEdit = PromptListContinuation.edit(
            in: emptyListText,
            selectionRange: NSRange(location: emptyListText.utf16.count, length: 0)
        )
        try check(
            emptyListEdit == PromptListEdit(
                range: NSRange(location: 0, length: emptyListText.utf16.count),
                replacement: "\n"
            ),
            "pressing Return on an empty numbered item exits the list"
        )

        try check(
            PromptListContinuation.edit(
                in: "texto normal",
                selectionRange: NSRange(location: 12, length: 0)
            ) == nil,
            "ordinary lines do not receive list continuation"
        )
    }

    private static func codexTerminalInputContracts() throws {
        let screen = """
        output anterior
        ──────────────────────────────────────────────────────────────────────────────

        ›  PROMPT_WIZ_BEGIN
            primeira linha\u{20}
          continua na mesma linha
            terceira linha

          gpt-5.6-luna high · prompt-wiz · Context 70% left

        """

        try check(
            CodexTerminalInputParser.extractDraft(from: screen) ==
                "PROMPT_WIZ_BEGIN\nprimeira linha continua na mesma linha\nterceira linha",
            "Codex input parser preserves real newlines and joins visual wraps"
        )
        try check(
            CodexTerminalInputParser.extractDraft(
                from: "›  \n  gpt-5.6-luna high · prompt-wiz · Context 70% left\n"
            ) == "",
            "Codex input parser recognizes an empty draft"
        )
        try check(
            CodexTerminalInputParser.extractDraft(
                from: "›  Ask Codex to do anything\n  gpt-5.6-luna high · prompt-wiz · Context 70% left\n"
            ) == "",
            "Codex input parser ignores the empty-composer placeholder"
        )
        try check(
            CodexTerminalInputParser.extractDraft(from: "terminal output only") == nil,
            "Codex input parser refuses an unrecognized terminal screen"
        )
        try check(
            CodexTerminalInputParser.extractDraft(
                from: "›  última palavra \n  gpt-5.6-luna high · prompt-wiz · Context 70% left\n"
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
