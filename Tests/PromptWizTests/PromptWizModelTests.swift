import Darwin
import AppKit
import Foundation
import SwiftUI
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
            try captureRecoversImageAttachmentFromTerminalClipboard()
            try captureKeepsExistingWorkspaceDraftWhenTerminalIsEmpty()
            try captureFailureKeepsTheModelUsable()
            try sendUsesInjectedAutomationAndPersistsHistory()
            try pasteToTerminalDoesNotSendOrClearThePrompt()
            try snippetsAndClipboardUseTheInjectedDependencies()
            try snippetsMigrateFromThePreviousAppKey()
            try inlineStylingDoesNotCancelMarkedTextComposition()
            try selectedSkillKeepsItsStyleAfterTextSynchronization()
            try selectingSkillPublishesPersistentSelectionRange()
            try cursorNavigationSkipsImageAndSelectedSkillBlocks()
            try imagePasteShortcutAcceptsOptionAndControlV()
            try editorCoordinatorContinuesNumberedListsOnReturn()
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

    private static func captureRecoversImageAttachmentFromTerminalClipboard() throws {
        let imageData = Data([9, 8, 7])
        let automation = TerminalAutomationFake(
            session: TerminalSession(
                id: "/dev/ttys006",
                title: "Prompt Wiz — Terminal image test",
                processIdentifier: 303,
                tty: "/dev/ttys006"
            ),
            draft: "Analisa esta imagem [Image #1]"
        )
        let model = makeModel(
            automation: automation,
            clipboard: FixedClipboard(data: imageData)
        )

        model.captureActiveTerminalSession()
        try check(
            model.editorImageAttachments.count == 1 &&
                model.editorImageAttachments[0].number == 1 &&
                model.editorImageAttachments[0].data == imageData,
            "capture associates the clipboard image with the Terminal image reference"
        )
        model.send()

        try check(
            automation.sentImageAttachments.count == 1 &&
                automation.sentImageAttachments[0].count == 1 &&
                automation.sentImageAttachments[0][0].number == 1 &&
                automation.sentImageAttachments[0][0].data == imageData,
            "an image already pasted in Terminal is sent as its PNG attachment"
        )
    }

    private static func captureKeepsExistingWorkspaceDraftWhenTerminalIsEmpty() throws {
        let automation = TerminalAutomationFake(
            session: TerminalSession(
                id: "/dev/ttys005",
                title: "Prompt Wiz — Existing draft test",
                processIdentifier: 202,
                tty: "/dev/ttys005"
            ),
            draft: "Draft initially visible in Terminal"
        )
        let model = makeModel(automation: automation)

        model.captureActiveTerminalSession()
        model.updateEditorText("Texto guardado na app")
        automation.draft = "   \n"

        model.captureActiveTerminalSession()

        try check(
            model.editorText == "Texto guardado na app",
            "an empty Terminal keeps the existing app draft when reopening its workspace"
        )
        try check(
            model.selectedWorkspace?.draft == "Texto guardado na app",
            "an empty Terminal does not overwrite the existing workspace draft"
        )
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

    private static func pasteToTerminalDoesNotSendOrClearThePrompt() throws {
        let automation = TerminalAutomationFake(
            session: TerminalSession(
                id: "/dev/ttys004",
                title: "Prompt Wiz — Paste test",
                processIdentifier: 101,
                tty: "/dev/ttys004"
            )
        )
        let model = makeModel(automation: automation)
        var minimizedComposer = false
        model.minimizeMainWindowHandler = { minimizedComposer = true }
        model.captureActiveTerminalSession()
        model.updateEditorText("  Colar isto  ")

        model.pasteToTerminal()

        try check(
            automation.pastedBuffers == ["  Colar isto  "],
            "paste forwards the current editor buffer to Terminal.app"
        )
        try check(automation.sentBuffers.isEmpty, "paste does not submit the prompt")
        try check(model.history.isEmpty, "paste does not add a history entry")
        try check(
            model.selectedWorkspace?.draft == "  Colar isto  ",
            "paste keeps the prompt in the composer"
        )
        try check(!minimizedComposer, "paste keeps the composer visible")
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

    private static func snippetsMigrateFromThePreviousAppKey() throws {
        let suiteName = "PromptWizSnippetMigrationTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestFailure(message: "could not create isolated defaults for snippet migration")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let oldSnippet = Snippet(
            title: "My saved snippet",
            body: "This content must survive an app rename.",
            isFavorite: true,
            shortcutNumber: 1
        )
        let oldData = try JSONEncoder().encode([oldSnippet])
        defaults.set(oldData, forKey: "prompt-viz.snippets")

        let loadedSnippets = LocalSnippetPersistence(defaults: defaults).load()

        try check(
            loadedSnippets == [oldSnippet],
            "snippets saved by the previous app version are loaded after the rename"
        )
        try check(
            defaults.data(forKey: "prompt-wiz.snippets") == oldData,
            "legacy snippets are copied to the current persistence key"
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

    private static func inlineStylingDoesNotCancelMarkedTextComposition() throws {
        let textView = NSTextView(frame: .zero)
        textView.string = "a"
        textView.setSelectedRange(NSRange(location: 1, length: 0))
        textView.setMarkedText(
            "´",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: 1, length: 0)
        )

        try check(textView.hasMarkedText(), "the editor exposes the pending accent composition")

        let marker = NSAttributedString.Key("PromptWiz.testTypingAttribute")
        textView.typingAttributes = [marker: "preserve"]
        PromptTextEditor.applyInlineTokenStyles(to: textView, selectedSkillRanges: [])

        try check(
            textView.hasMarkedText(),
            "inline styling keeps the pending accent composition alive"
        )
        try check(
            textView.typingAttributes[marker] as? String == "preserve",
            "inline styling does not replace typing attributes during composition"
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

    private static func imagePasteShortcutAcceptsOptionAndControlV() throws {
        let optionV = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.option],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "v",
            charactersIgnoringModifiers: "v",
            isARepeat: false,
            keyCode: 9
        )
        let controlV = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.control],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "v",
            charactersIgnoringModifiers: "v",
            isARepeat: false,
            keyCode: 9
        )
        let commandV = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "v",
            charactersIgnoringModifiers: "v",
            isARepeat: false,
            keyCode: 9
        )

        try check(
            optionV.map(isImagePasteShortcut) == true,
            "Option+V remains an image paste shortcut"
        )
        try check(
            controlV.map(isImagePasteShortcut) == true,
            "Control+V is accepted as an image paste shortcut"
        )
        try check(
            commandV.map(isImagePasteShortcut) == false,
            "Command+V remains normal text paste"
        )
    }

    private static func editorCoordinatorContinuesNumberedListsOnReturn() throws {
        var text = "1. primeiro item"
        var selectedSkillRanges: [NSRange] = []
        let coordinator = PromptTextEditor.Coordinator(
            text: Binding(
                get: { text },
                set: { text = $0 }
            ),
            selectedSkillRanges: Binding(
                get: { selectedSkillRanges },
                set: { selectedSkillRanges = $0 }
            ),
            onSkillKeyboardAction: { _ in false },
            onImagePaste: { _, _ in }
        )
        let textView = NSTextView(frame: .zero)
        textView.string = text
        textView.setSelectedRange(NSRange(location: text.utf16.count, length: 0))

        let handled = coordinator.textView(
            textView,
            doCommandBy: #selector(NSResponder.insertNewline(_:))
        )

        try check(handled, "the editor handles Return for numbered list continuation")
        try check(
            textView.string == "1. primeiro item\n2. ",
            "Return inserts the next numbered list item in the editor"
        )
        try check(
            text == textView.string,
            "numbered list continuation synchronizes the editor binding"
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
    var draft: String
    private(set) var activeSessionCallCount = 0
    private(set) var sentBuffers: [String] = []
    private(set) var sentSessions: [TerminalSession] = []
    private(set) var sentImageAttachments: [[PromptImageAttachment]] = []
    private(set) var pastedBuffers: [String] = []
    private(set) var pastedSessions: [TerminalSession] = []

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
        sentImageAttachments.append(imageAttachments)
    }

    func pasteCodexInput(
        _ buffer: String,
        imageAttachments: [PromptImageAttachment],
        to expectedSession: TerminalSession
    ) throws {
        pastedBuffers.append(buffer)
        pastedSessions.append(expectedSession)
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
