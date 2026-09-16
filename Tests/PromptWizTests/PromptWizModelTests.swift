import Darwin
import AppKit
import Foundation
import PromptWizCore

private struct TestFailure: Error, CustomStringConvertible {
    let message: String

    var description: String { message }
}

@main
@MainActor
struct PromptWizModelTests {
    private static var checkCount = 0

    static func main() {
        do {
            try captureCreatesWorkspaceAndPreparesDraftForContinuation()
            try captureFailureKeepsTheModelUsable()
            try sendUsesInjectedAutomationAndPersistsHistory()
            try snippetsAndClipboardUseTheInjectedDependencies()
            try selectedSkillKeepsItsStyleAfterTextSynchronization()
            try selectingSkillPublishesPersistentSelectionRange()
            try cursorNavigationSkipsImageAndSelectedSkillBlocks()
            try shortcutIsRestrictedToTerminalApplication()
            try disablingHideAfterSendKeepsComposerVisible()
            print("PromptWiz seam tests: PASS (\(checkCount) checks)")
        } catch {
            fputs("PromptWiz seam tests: FAIL — \(error)\n", stderr)
            exit(1)
        }
    }

    private static func check(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) throws {
        checkCount += 1
        guard condition() else { throw TestFailure(message: message) }
    }

    private static func captureCreatesWorkspaceAndPreparesDraftForContinuation() throws {
        let session = TerminalSession(
            id: "/dev/ttys001",
            title: "Prompt Wiz — Test",
            processIdentifier: 123,
            tty: "/dev/ttys001"
        )
        let automation = TerminalAutomationFake(
            session: session,
            draft: "Draft from Codex"
        )
        let model = makeModel(automation: automation)
        var openedMainWindow = false
        model.openMainWindowHandler = { openedMainWindow = true }

        model.captureActiveTerminalSession()

        try check(model.workspaces.count == 1, "capture creates one workspace")
        try check(
            model.selectedWorkspace?.terminalSessionID == session.id,
            "workspace keeps the captured terminal session identity"
        )
        try check(
            model.selectedWorkspace?.terminalProcessIdentifier == session.processIdentifier,
            "workspace keeps the captured Terminal process identifier"
        )
        try check(
            model.editorText == "Draft from Codex ",
            "capture prepares the editor draft for continuation"
        )
        try check(
            model.selectedWorkspace?.draft == "Draft from Codex ",
            "capture stores the prepared draft in the workspace"
        )
        try check(openedMainWindow, "capture requests the main window")
    }

    private static func captureFailureKeepsTheModelUsable() throws {
        let automation = TerminalAutomationFake(isTerminalFrontmost: false)
        let model = makeModel(automation: automation)
        var openedMainWindow = false
        model.openMainWindowHandler = { openedMainWindow = true }

        model.captureActiveTerminalSession()

        try check(model.workspaces.isEmpty, "failed capture does not create a workspace")
        try check(model.selectedWorkspace == nil, "failed capture leaves no selected workspace")
        try check(
            model.errorMessage?.contains("Activate the correct Terminal.app tab") == true,
            "failed capture exposes the terminal error"
        )
        try check(openedMainWindow, "failed capture still requests the main window")
        try check(
            automation.activeSessionCallCount == 0,
            "capture stops before querying a non-frontmost Terminal"
        )
    }

    private static func sendUsesInjectedAutomationAndPersistsHistory() throws {
        let automation = TerminalAutomationFake(
            session: TerminalSession(
                id: "/dev/ttys002",
                title: "Prompt Wiz — Send test",
                processIdentifier: 456,
                tty: "/dev/ttys002"
            ),
            draft: "Existing draft"
        )
        let historyPersistence = RecordingPromptHistoryPersistence()
        let model = makeModel(
            automation: automation,
            historyPersistence: historyPersistence
        )
        var minimizedComposer = false
        model.minimizeMainWindowHandler = { minimizedComposer = true }
        model.captureActiveTerminalSession()
        model.updateEditorText("  Enviar isto  ")

        model.send()

        try check(
            automation.sentBuffers == ["  Enviar isto  "],
            "send forwards the current editor buffer to the injected automation"
        )
        try check(
            automation.sentSessions.first?.id == "/dev/ttys002",
            "send forwards the active terminal session to the injected automation"
        )
        try check(
            model.history.first?.prompt == "Enviar isto",
            "send records a trimmed prompt in history"
        )
        try check(minimizedComposer, "successful send minimizes the composer window")
        try check(
            historyPersistence.lastSaved?.first?.prompt == "Enviar isto",
            "send persists the updated history"
        )
        try check(model.editorText.isEmpty, "successful send clears the editor")
    }

    private static func snippetsAndClipboardUseTheInjectedDependencies() throws {
        let snippetPersistence = RecordingSnippetPersistence()
        let clipboard = FixedClipboard(data: Data([1, 2, 3]))
        let model = makeModel(
            snippetPersistence: snippetPersistence,
            clipboard: clipboard
        )

        model.addSnippet(title: "Review", body: "Review this change.", favorite: true)
        guard let snippet = model.snippets.first else {
            throw TestFailure(message: "snippet creation did not publish a snippet")
        }
        model.insert(snippet)
        model.requestImagePaste()

        try check(model.snippets.count == 1, "adding a snippet publishes it through the model")
        try check(
            snippetPersistence.lastSaved?.first?.body == "Review this change.",
            "adding a snippet persists it through the injected persistence"
        )
        try check(
            model.insertionRequest?.text == "Review this change.",
            "inserting a snippet publishes an editor insertion request"
        )
        try check(
            model.imagePastePreview?.data == Data([1, 2, 3]),
            "image paste reads data through the injected clipboard"
        )
    }

    private static func selectedSkillKeepsItsStyleAfterTextSynchronization() throws {
        let textView = NSTextView(frame: .zero)
        textView.string = "$grill $other"
        let skillRange = NSRange(location: 0, length: "$grill".utf16.count)
        textView.textStorage?.addAttribute(
                NSAttributedString.Key("PromptWiz.selectedSkill"),
            value: true,
            range: skillRange
        )

        // AppKit can replace the text storage during SwiftUI synchronization,
        // dropping the temporary selected-skill attribute.
        textView.textStorage?.removeAttribute(
                NSAttributedString.Key("PromptWiz.selectedSkill"),
            range: NSRange(location: 0, length: textView.textStorage?.length ?? 0)
        )
        PromptTextEditor.applyInlineTokenStyles(
            to: textView,
            selectedSkillRanges: [skillRange]
        )

        let color = textView.textStorage?.attribute(
            .foregroundColor,
            at: skillRange.location,
            effectiveRange: nil
        ) as? NSColor
        let otherSkillColor = textView.textStorage?.attribute(
            .foregroundColor,
            at: "$grill ".utf16.count,
            effectiveRange: nil
        ) as? NSColor
        try check(
            color?.isEqual(NSColor.controlAccentColor) == true,
            "a selected skill remains blue after text synchronization"
        )
        try check(
            otherSkillColor?.isEqual(NSColor.controlAccentColor) != true,
            "an unselected skill remains in the normal editor color"
        )
        try check(
            PromptTextEditor.semanticTokenRanges(
                in: textView,
                selectedSkillRanges: [skillRange]
            ) == [skillRange],
            "only the selected skill is treated as an editable token"
        )
        try check(
            PromptEditorTokens.editingRange(
                for: NSRange(location: 2, length: 1),
                in: textView.string,
                restrictedTo: [skillRange]
            ) == skillRange,
            "editing inside a selected skill expands to the whole skill token"
        )
    }

    private static func selectingSkillPublishesPersistentSelectionRange() throws {
        let model = makeModel()
        model.updateEditorText("Use $g")

        let skill = SkillDescriptor(
            id: "grill",
            name: "grill",
            description: "Critically examine a decision.",
            sourcePath: "/tmp/grill/SKILL.md"
        )
        model.selectSkill(skill)

        let expectedRange = NSRange(location: 4, length: "$grill".utf16.count)
        try check(
            model.editorText == "Use $grill ",
            "selecting a skill replaces the active skill query"
        )
        try check(
            model.selectedSkillRanges == [expectedRange],
            "selecting a skill publishes its range for the editor"
        )
    }

    private static func cursorNavigationSkipsImageAndSelectedSkillBlocks() throws {
        let text = "A [Image #1] $grill"
        let tokens = PromptEditorTokens.tokens(in: text)
        guard
            let imageRange = tokens.first(where: { $0.kind == .imageReference })?.range,
            let skillRange = tokens.first(where: { $0.kind == .skillReference })?.range
        else {
            throw TestFailure(message: "cursor navigation test could not find both tokens")
        }

        let blockedRanges = [imageRange, skillRange]
        try check(
            PromptTextEditor.normalizedSelectionRange(
                NSRange(location: imageRange.location + 2, length: 0),
                from: NSRange(location: imageRange.location - 1, length: 0),
                blockedRanges: blockedRanges
            ) == NSRange(location: NSMaxRange(imageRange), length: 0),
            "moving right skips the inside of an image token"
        )
        try check(
            PromptTextEditor.normalizedSelectionRange(
                NSRange(location: skillRange.location + 2, length: 0),
                from: NSRange(location: NSMaxRange(skillRange) + 1, length: 0),
                blockedRanges: blockedRanges
            ) == NSRange(location: skillRange.location, length: 0),
            "moving left skips the inside of a selected skill token"
        )
        try check(
            PromptTextEditor.normalizedSelectionRange(
                NSRange(location: imageRange.location + 2, length: 1),
                from: nil,
                blockedRanges: blockedRanges
            ) == imageRange,
            "selecting inside an image token selects its whole block"
        )
    }

    private static func shortcutIsRestrictedToTerminalApplication() throws {
        try check(
            GlobalShortcut.isAllowed(inBundleIdentifier: "com.apple.Terminal"),
            "the global shortcut is allowed in Terminal.app"
        )
        try check(
            !GlobalShortcut.isAllowed(inBundleIdentifier: "com.apple.finder"),
            "the global shortcut is ignored in Finder"
        )
        try check(
            !GlobalShortcut.isAllowed(inBundleIdentifier: nil),
            "the global shortcut is ignored without a frontmost application"
        )
    }

    private static func disablingHideAfterSendKeepsComposerVisible() throws {
        let automation = TerminalAutomationFake(
            session: TerminalSession(
                id: "/dev/ttys003",
                title: "Prompt Wiz — Hide setting test",
                processIdentifier: 789,
                tty: "/dev/ttys003"
            )
        )
        let model = makeModel(
            automation: automation,
            sendBehaviorPersistence: FixedSendBehaviorPersistence(hideAfterSend: false)
        )
        var minimizedComposer = false
        model.minimizeMainWindowHandler = { minimizedComposer = true }
        model.captureActiveTerminalSession()
        model.updateEditorText("Não esconder")

        model.send()

        try check(!model.hideAfterSend, "the hide-after-send setting loads disabled")
        try check(!minimizedComposer, "disabled hide-after-send keeps the composer visible")
    }

    private static func makeModel(
        automation: TerminalAutomationFake = TerminalAutomationFake(),
        snippetPersistence: any SnippetPersistenceProviding = EmptySnippetPersistence(),
        historyPersistence: any PromptHistoryPersistenceProviding = EmptyPromptHistoryPersistence(),
        clipboard: any ClipboardProviding = EmptyClipboard(),
        sendBehaviorPersistence: any SendBehaviorPersistenceProviding = FixedSendBehaviorPersistence()
    ) -> PromptWizModel {
        PromptWizModel(
            terminalAutomation: automation,
            snippetPersistence: snippetPersistence,
            promptHistoryPersistence: historyPersistence,
            skillCatalog: EmptySkillCatalog(),
            clipboard: clipboard,
            launchAtLogin: DisabledLaunchAtLogin(),
            shortcutPersistence: DefaultShortcutPersistence(),
            sendBehaviorPersistence: sendBehaviorPersistence
        )
    }
}

private final class TerminalAutomationFake: TerminalAutomationProviding, @unchecked Sendable {
    let isTerminalFrontmost: Bool
    private let session: TerminalSession
    private let draft: String
    private(set) var activeSessionCallCount = 0
    private(set) var sentBuffers: [String] = []
    private(set) var sentSessions: [TerminalSession] = []

    init(
        isTerminalFrontmost: Bool = true,
        session: TerminalSession = TerminalSession(
            id: "/dev/ttys001",
            title: "Prompt Wiz — Test",
            processIdentifier: 123,
            tty: "/dev/ttys001"
        ),
        draft: String = "Draft from Codex"
    ) {
        self.isTerminalFrontmost = isTerminalFrontmost
        self.session = session
        self.draft = draft
    }

    func openAccessibilitySettings() {}
    func openAutomationSettings() {}

    func activeSession() throws -> TerminalSession {
        activeSessionCallCount += 1
        return session
    }

    func activeCodexDraft() throws -> String {
        draft
    }

    func liveSessionInventory() -> TerminalSessionInventory? {
        nil
    }

    func sendCodexInputAndReturn(
        _ buffer: String,
        imageAttachments: [PromptImageAttachment],
        to expectedSession: TerminalSession
    ) throws {
        sentBuffers.append(buffer)
        sentSessions.append(expectedSession)
    }

    func requestTabSelection(tty: String) {}
}

private struct EmptySnippetPersistence: SnippetPersistenceProviding {
    func load() -> [Snippet]? { [] }
    func save(_ snippets: [Snippet]) {}
}

private final class RecordingSnippetPersistence: SnippetPersistenceProviding {
    private(set) var lastSaved: [Snippet]?

    func load() -> [Snippet]? { [] }

    func save(_ snippets: [Snippet]) {
        lastSaved = snippets
    }
}

private struct EmptyPromptHistoryPersistence: PromptHistoryPersistenceProviding {
    func load() -> [PromptHistoryEntry] { [] }
    func save(_ entries: [PromptHistoryEntry]) {}
}

private final class RecordingPromptHistoryPersistence: PromptHistoryPersistenceProviding {
    private(set) var lastSaved: [PromptHistoryEntry]?

    func load() -> [PromptHistoryEntry] { [] }

    func save(_ entries: [PromptHistoryEntry]) {
        lastSaved = entries
    }
}

private struct EmptySkillCatalog: SkillCatalogProviding {
    func scan() -> [SkillDescriptor] { [] }
    func search(_ query: String, in skills: [SkillDescriptor]) -> [SkillDescriptor] { skills }
}

private struct EmptyClipboard: ClipboardProviding {
    func pngData() -> Data? { nil }
}

private struct FixedClipboard: ClipboardProviding {
    let data: Data

    func pngData() -> Data? { data }
}

private struct DisabledLaunchAtLogin: LaunchAtLoginProviding {
    let isEnabled = false
    func setEnabled(_ enabled: Bool) throws {}
}

private struct DefaultShortcutPersistence: GlobalShortcutPersistenceProviding {
    func load() -> GlobalShortcut { .defaultShortcut }
    func save(_ shortcut: GlobalShortcut) {}
}

private struct FixedSendBehaviorPersistence: SendBehaviorPersistenceProviding {
    let hideAfterSend: Bool

    init(hideAfterSend: Bool = true) {
        self.hideAfterSend = hideAfterSend
    }

    func loadHideAfterSend() -> Bool { hideAfterSend }
    func saveHideAfterSend(_ enabled: Bool) {}
}
