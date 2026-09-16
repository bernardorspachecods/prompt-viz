import AppKit
import Foundation
import PromptWizCore
import SwiftUI

@MainActor
final class PromptWizModel: ObservableObject {
    static let shared = PromptWizModel()

    @Published private(set) var workspaces: [Workspace] = []
    @Published private(set) var snippets: [Snippet] = []
    @Published private(set) var history: [PromptHistoryEntry] = []
    @Published private(set) var skills: [SkillDescriptor] = []
    @Published var selectedWorkspaceID: UUID?
    @Published var editorText = ""
    @Published private(set) var editorImageAttachments: [PromptImageAttachment] = []
    @Published var imagePastePreview: ImagePastePreview?
    @Published var imagePasteRequest: ImagePasteRequest?
    @Published var insertionRequest: TextInsertionRequest?
    @Published var editorCursorLocationRequest: Int?
    @Published var editorFocusRequest: UUID?
    @Published var skillHighlightRequest: SkillHighlightRequest?
    @Published var selectedSkillRanges: [NSRange] = []
    @Published var hideAfterSend: Bool
    @Published private(set) var launchesAtLogin: Bool
    @Published private(set) var openComposerShortcut: GlobalShortcut
    @Published var errorMessage: String?
    @Published var shouldOfferAccessibilitySettings = false
    @Published var shouldOfferAutomationSettings = false
    @Published var isMainWindowVisible = false
    var openMainWindowHandler: (() -> Void)?
    var minimizeMainWindowHandler: (() -> Void)?
    var workspacesDidChangeHandler: (() -> Void)?

    private let workspaceStore: WorkspaceStore
    private let snippetLibrary: SnippetLibrary
    private let promptHistory: PromptHistoryStore
    private let terminalAutomation: any TerminalAutomationProviding
    private let snippetPersistence: any SnippetPersistenceProviding
    private let promptHistoryPersistence: any PromptHistoryPersistenceProviding
    private let skillCatalog: any SkillCatalogProviding
    private let clipboard: any ClipboardProviding
    private let launchAtLogin: any LaunchAtLoginProviding
    private let shortcutPersistence: any GlobalShortcutPersistenceProviding
    private let sendBehaviorPersistence: any SendBehaviorPersistenceProviding
    private var workspaceMonitor: Timer?
    private var skillMonitor: Timer?
    private var editorTextPublicationTimer: Timer?
    private var isPruningWorkspaces = false
    private var isRefreshingSkills = false
    private(set) var isCapturingTerminalSession = false
    private(set) var activeSession: TerminalSession?
    private var latestEditorText = ""

    init(
        workspaceStore: WorkspaceStore = WorkspaceStore(),
        terminalAutomation: any TerminalAutomationProviding = TerminalAutomation(),
        snippetPersistence: any SnippetPersistenceProviding = LocalSnippetPersistence(),
        promptHistoryPersistence: any PromptHistoryPersistenceProviding = LocalPromptHistoryPersistence(),
        skillCatalog: any SkillCatalogProviding = SkillCatalog(),
        clipboard: any ClipboardProviding = SystemClipboard(),
        launchAtLogin: any LaunchAtLoginProviding = SystemLaunchAtLogin(),
        shortcutPersistence: any GlobalShortcutPersistenceProviding = UserDefaultsGlobalShortcutPersistence(),
        sendBehaviorPersistence: any SendBehaviorPersistenceProviding = UserDefaultsSendBehaviorPersistence()
    ) {
        self.workspaceStore = workspaceStore
        self.terminalAutomation = terminalAutomation
        self.snippetPersistence = snippetPersistence
        self.promptHistoryPersistence = promptHistoryPersistence
        self.skillCatalog = skillCatalog
        self.clipboard = clipboard
        self.launchAtLogin = launchAtLogin
        self.shortcutPersistence = shortcutPersistence
        self.sendBehaviorPersistence = sendBehaviorPersistence
        snippetLibrary = SnippetLibrary(snippets: snippetPersistence.load())
        promptHistory = PromptHistoryStore(entries: promptHistoryPersistence.load())
        launchesAtLogin = launchAtLogin.isEnabled
        openComposerShortcut = shortcutPersistence.load()
        hideAfterSend = sendBehaviorPersistence.loadHideAfterSend()
        skills = []
        sync()
        PromptWizLog.info("Application model initialized")
        workspaceMonitor = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pruneClosedWorkspaces()
            }
        }
        skillMonitor = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshSkills()
            }
        }
    }

    var selectedWorkspace: Workspace? {
        guard let selectedWorkspaceID else { return nil }
        return workspaceStore.workspace(id: selectedWorkspaceID)
    }

    var favoriteSnippets: [Snippet] {
        snippets.filter(\.isFavorite)
    }

    func searchHistory(_ query: String) -> [PromptHistoryEntry] {
        promptHistory.search(query)
    }

    func searchSkills(_ query: String) -> [SkillDescriptor] {
        skillCatalog.search(query, in: skills)
    }

    func captureActiveTerminalSession() {
        PromptWizLog.info("Capturing active Terminal session")
        errorMessage = nil
        // Capture can switch to a new workspace, so persist the current editor
        // before changing selectedWorkspaceID or letting the new tab activate.
        saveCurrentDraft()
        isCapturingTerminalSession = true
        shouldOfferAccessibilitySettings = false
        shouldOfferAutomationSettings = false

        guard terminalAutomation.isTerminalFrontmost else {
            isCapturingTerminalSession = false
            let error = TerminalAutomationError.terminalNotActive
            PromptWizLog.error(error, context: "Capture failed")
            errorMessage = error.localizedDescription
            openMainWindow()
            return
        }

        do {
            let session = try terminalAutomation.activeSession()
            let codexDraft = try terminalAutomation.activeCodexDraft()
            activeSession = session
            let workspace = workspaceStore.workspace(
                for: session.id,
                title: session.title,
                terminalTTY: session.tty,
                terminalProcessIdentifier: session.processIdentifier
            )
            let terminalHasDraft = !codexDraft
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
            let editorDraft = terminalHasDraft
                ? CodexDraftEditor.prepareForContinuation(codexDraft)
                : workspace.draft
            let imageAttachments = terminalHasDraft
                ? imageAttachmentsRecovered(from: codexDraft, workspace: workspace)
                : workspace.imageAttachments
            selectedWorkspaceID = workspace.id
            setEditorText(editorDraft)
            editorImageAttachments = imageAttachments
            editorCursorLocationRequest = (editorDraft as NSString).length
            editorFocusRequest = UUID()
            workspaceStore.updateDraft(
                editorDraft,
                imageAttachments: imageAttachments,
                for: workspace.id
            )
            sync()
            openMainWindow()
            PromptWizLog.info("Terminal session captured successfully")
        } catch {
            PromptWizLog.error(error, context: "Capture failed")
            isCapturingTerminalSession = false
            errorMessage = error.localizedDescription
            shouldOfferAccessibilitySettings = (error as? TerminalAutomationError)?.isAccessibilityNotTrusted == true
            shouldOfferAutomationSettings = (error as? TerminalAutomationError)?.isAutomationNotTrusted == true
            openMainWindow()
        }
    }

    func select(_ workspace: Workspace) {
        saveCurrentDraft()
        let workspace = workspaceStore.workspace(id: workspace.id) ?? workspace
        selectedWorkspaceID = workspace.id
        activeSession = TerminalSession(
            id: workspace.terminalSessionID,
            title: workspace.title,
            processIdentifier: pid_t(workspace.terminalProcessIdentifier),
            tty: workspace.terminalTTY
        )
        if let tty = workspace.terminalTTY {
            terminalAutomation.requestTabSelection(tty: tty)
        }
        setEditorText(workspace.draft)
        editorImageAttachments = workspace.imageAttachments
        sync(reconcileWindows: false)
    }

    func selectRelativeWorkspace(by offset: Int) {
        guard !workspaces.isEmpty else { return }

        guard
            let selectedWorkspaceID,
            let currentIndex = workspaces.firstIndex(where: { $0.id == selectedWorkspaceID })
        else {
            select(offset < 0 ? workspaces[workspaces.count - 1] : workspaces[0])
            return
        }

        let nextIndex = (currentIndex + offset + workspaces.count) % workspaces.count
        select(workspaces[nextIndex])
    }

    func closeWorkspace(id: UUID) {
        workspaceStore.removeWorkspace(id: id)

        guard selectedWorkspaceID == id else {
            sync()
            return
        }

        if let nextWorkspace = workspaceStore.workspaces.first {
            selectedWorkspaceID = nextWorkspace.id
            activeSession = TerminalSession(
                id: nextWorkspace.terminalSessionID,
                title: nextWorkspace.title,
                processIdentifier: pid_t(nextWorkspace.terminalProcessIdentifier),
                tty: nextWorkspace.terminalTTY
            )
            setEditorText(nextWorkspace.draft)
            editorImageAttachments = nextWorkspace.imageAttachments
        } else {
            selectedWorkspaceID = nil
            activeSession = nil
            setEditorText("")
            editorImageAttachments = []
        }

        sync()
    }

    func updateEditorText(_ text: String) {
        latestEditorText = text
        saveCurrentDraft()
        scheduleEditorTextPublication()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try launchAtLogin.setEnabled(enabled)
            launchesAtLogin = launchAtLogin.isEnabled
            PromptWizLog.info("Launch at login changed to \(launchesAtLogin)")
        } catch {
            PromptWizLog.error(error, context: "Could not update launch at login")
            launchesAtLogin = launchAtLogin.isEnabled
            errorMessage = "Could not update the launch-at-login setting.\n\n\(error.localizedDescription)"
        }
    }

    func setOpenComposerShortcut(_ shortcut: GlobalShortcut) {
        openComposerShortcut = shortcut
        shortcutPersistence.save(shortcut)
        PromptWizLog.info("Open Composer shortcut changed to \(shortcut.displayName)")
    }

    func setHideAfterSend(_ enabled: Bool) {
        hideAfterSend = enabled
        sendBehaviorPersistence.saveHideAfterSend(enabled)
        PromptWizLog.info("Hide after send changed to \(enabled)")
    }

    func insert(_ snippet: Snippet) {
        insertionRequest = TextInsertionRequest(text: snippet.body)
        PromptWizLog.info("Template inserted")
    }

    func registerImageAttachment(_ data: Data, number: Int) {
        guard !data.isEmpty else { return }
        editorImageAttachments.removeAll { $0.number == number }
        editorImageAttachments.append(PromptImageAttachment(number: number, data: data))
        saveCurrentDraft()
        PromptWizLog.info("Image attachment added")
    }

    func requestImagePaste() {
        guard let data = clipboard.pngData() else {
            PromptWizLog.info("Image preview requested but clipboard has no supported image")
            errorMessage = "No supported image was found in the clipboard."
            return
        }

        imagePastePreview = ImagePastePreview(data: data)
        PromptWizLog.info("Image preview opened from app command")
    }

    func confirmImagePaste(_ preview: ImagePastePreview) {
        guard imagePastePreview?.id == preview.id else { return }
        imagePasteRequest = ImagePasteRequest(data: preview.data)
        imagePastePreview = nil
        editorFocusRequest = UUID()
        PromptWizLog.info("Image paste confirmed from preview")
    }

    func cancelImagePaste(_ preview: ImagePastePreview) {
        guard imagePastePreview?.id == preview.id else { return }
        imagePastePreview = nil
        PromptWizLog.info("Image paste cancelled from preview")
    }

    func pasteToTerminal() {
        shouldOfferAccessibilitySettings = false
        shouldOfferAutomationSettings = false

        guard let activeSession else {
            errorMessage = TerminalAutomationError.terminalNotActive.localizedDescription
            return
        }

        do {
            let textToPaste = latestEditorText
            guard !textToPaste.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            PromptWizLog.info("Pasting prompt with \(editorImageAttachments.count) image attachment(s)")
            try terminalAutomation.pasteCodexInput(
                textToPaste,
                imageAttachments: editorImageAttachments,
                to: activeSession
            )
            PromptWizLog.info("Prompt pasted successfully")
        } catch {
            PromptWizLog.error(error, context: "Could not paste prompt")
            errorMessage = error.localizedDescription
            shouldOfferAccessibilitySettings = (error as? TerminalAutomationError)?.isAccessibilityNotTrusted == true
            shouldOfferAutomationSettings = (error as? TerminalAutomationError)?.isAutomationNotTrusted == true
        }
    }

    func loadHistoryEntry(_ entry: PromptHistoryEntry) {
        saveCurrentDraft()
        setEditorText(entry.prompt)
        editorImageAttachments = entry.imageAttachments
        editorCursorLocationRequest = (entry.prompt as NSString).length
        editorFocusRequest = UUID()
        sync(reconcileWindows: false)
        PromptWizLog.info("Prompt history entry loaded")
    }

    func removeHistoryEntry(_ entry: PromptHistoryEntry) {
        promptHistory.remove(id: entry.id)
        promptHistoryPersistence.save(promptHistory.entries)
        sync(reconcileWindows: false)
        PromptWizLog.info("Prompt history entry deleted")
    }

    func clearHistory() {
        promptHistory.removeAll()
        promptHistoryPersistence.save(promptHistory.entries)
        sync(reconcileWindows: false)
        PromptWizLog.info("Prompt history cleared")
    }

    func selectSkill(_ skill: SkillDescriptor) {
        let invocation = "$" + skill.name + " "
        let expression = #"\$[A-Za-z0-9_-]*$"#
        let currentText = latestEditorText

        if let range = currentText.range(of: expression, options: .regularExpression) {
            let tokenRange = NSRange(range, in: currentText)
            var updatedText = currentText
            updatedText.replaceSubrange(range, with: invocation)
            setEditorText(updatedText)
            selectedSkillRanges = [NSRange(
                location: tokenRange.location,
                length: invocation.dropLast().utf16.count
            )]
            saveCurrentDraft()
            editorCursorLocationRequest = (updatedText as NSString).length
            skillHighlightRequest = SkillHighlightRequest(
                range: NSRange(
                    location: tokenRange.location,
                    length: invocation.dropLast().utf16.count
                )
            )
            sync(reconcileWindows: false)
        } else {
            insertionRequest = TextInsertionRequest(text: invocation)
        }
    }

    func send() {
        shouldOfferAccessibilitySettings = false
        shouldOfferAutomationSettings = false

        guard let activeSession else {
            errorMessage = TerminalAutomationError.terminalNotActive.localizedDescription
            return
        }

        do {
            let textToSend = latestEditorText
            guard !textToSend.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            PromptWizLog.info("Sending prompt with \(editorImageAttachments.count) image attachment(s)")
            try terminalAutomation.sendCodexInputAndReturn(
                textToSend,
                imageAttachments: editorImageAttachments,
                to: activeSession
            )
            promptHistory.add(
                prompt: textToSend.trimmingCharacters(in: .whitespacesAndNewlines),
                sessionTitle: activeSession.title,
                imageAttachments: editorImageAttachments
            )
            promptHistoryPersistence.save(promptHistory.entries)
            setEditorText("")
            editorImageAttachments = []
            saveCurrentDraft()
            sync(reconcileWindows: false)
            if hideAfterSend {
                minimizeMainWindow()
            }
            PromptWizLog.info("Prompt sent successfully")
        } catch {
            PromptWizLog.error(error, context: "Could not send prompt")
            errorMessage = error.localizedDescription
            shouldOfferAccessibilitySettings = (error as? TerminalAutomationError)?.isAccessibilityNotTrusted == true
            shouldOfferAutomationSettings = (error as? TerminalAutomationError)?.isAutomationNotTrusted == true
        }
    }

    func addSnippet(title: String, body: String, favorite: Bool) {
        guard snippetLibrary.add(Snippet(title: title, body: body, isFavorite: favorite)) else {
            PromptWizLog.info("Template creation rejected because the 9-template limit was reached")
            errorMessage = "Prompt Wiz supports up to 9 templates because there are only 9 shortcut slots."
            return
        }
        snippetPersistence.save(snippetLibrary.snippets)
        sync()
        PromptWizLog.info("Template created")
    }

    func updateSnippet(_ snippet: Snippet) {
        snippetLibrary.update(snippet)
        snippetPersistence.save(snippetLibrary.snippets)
        sync()
        PromptWizLog.info("Template updated")
    }

    func removeSnippet(_ snippet: Snippet) {
        snippetLibrary.remove(id: snippet.id)
        snippetPersistence.save(snippetLibrary.snippets)
        sync()
        PromptWizLog.info("Template deleted")
    }

    func moveSnippet(id: UUID, toShortcutNumber shortcutNumber: Int) {
        snippetLibrary.moveSnippet(id, toShortcutNumber: shortcutNumber)
        snippetPersistence.save(snippetLibrary.snippets)
        sync()
        PromptWizLog.info("Template moved to shortcut slot \(shortcutNumber)")
    }

    func openMainWindow() {
        isMainWindowVisible = true
        NSApp?.unhide(nil)
        NSApp?.activate(ignoringOtherApps: true)
        openMainWindowHandler?()
    }

    func minimizeMainWindow() {
        isMainWindowVisible = false
        minimizeMainWindowHandler?()
    }

    func openAccessibilitySettings() {
        terminalAutomation.openAccessibilitySettings()
    }

    func openAutomationSettings() {
        terminalAutomation.openAutomationSettings()
    }

    func finishTerminalSessionCapture() {
        isCapturingTerminalSession = false
    }

    private func saveCurrentDraft() {
        guard let selectedWorkspaceID else { return }
        let referencedNumbers = Set(PromptImageReference.numbers(in: latestEditorText))
        editorImageAttachments = editorImageAttachments.filter {
            referencedNumbers.contains($0.number)
        }
        workspaceStore.updateDraft(
            latestEditorText,
            imageAttachments: editorImageAttachments,
            for: selectedWorkspaceID
        )
    }

    private func imageAttachmentsRecovered(
        from draft: String,
        workspace: Workspace
    ) -> [PromptImageAttachment] {
        let referencedNumbers = PromptImageReference.numbers(in: draft)
        guard !referencedNumbers.isEmpty else { return [] }

        var attachments = workspace.imageAttachments.filter {
            referencedNumbers.contains($0.number)
        }
        let attachedNumbers = Set(attachments.map(\.number))
        let missingNumbers = referencedNumbers.filter { !attachedNumbers.contains($0) }

        if missingNumbers.count == 1,
           let data = clipboard.pngData(),
           !data.isEmpty {
            attachments.append(
                PromptImageAttachment(number: missingNumbers[0], data: data)
            )
            PromptWizLog.info("Recovered one image attachment from the Terminal clipboard")
        }

        let order = Dictionary(uniqueKeysWithValues: referencedNumbers.enumerated().map {
            ($1, $0)
        })
        return attachments.sorted {
            (order[$0.number] ?? Int.max) < (order[$1.number] ?? Int.max)
        }
    }

    private func setEditorText(_ text: String) {
        editorTextPublicationTimer?.invalidate()
        selectedSkillRanges = []
        latestEditorText = text
        editorText = text
    }

    private func scheduleEditorTextPublication() {
        editorTextPublicationTimer?.invalidate()
        editorTextPublicationTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.editorText != self.latestEditorText else { return }
                self.editorText = self.latestEditorText
            }
        }
    }

    private func sync(reconcileWindows: Bool = true) {
        workspaces = workspaceStore.workspaces
        snippets = snippetLibrary.snippets
        history = promptHistory.entries
        if reconcileWindows {
            workspacesDidChangeHandler?()
        }
    }

    private func refreshSkills() {
        guard !isRefreshingSkills else { return }
        isRefreshingSkills = true
        let skillCatalog = skillCatalog

        Task { @MainActor [weak self] in
            let discoveredSkills = await Task.detached(priority: .utility) {
                skillCatalog.scan()
            }.value

            guard let self else { return }
            isRefreshingSkills = false
            skills = discoveredSkills
        }
    }

    private func pruneClosedWorkspaces() {
        guard !isPruningWorkspaces, !workspaceStore.workspaces.isEmpty else { return }
        isPruningWorkspaces = true

        let automation = terminalAutomation
        Task { @MainActor [weak self] in
            let inventory = await Task.detached(priority: .utility) {
                automation.liveSessionInventory()
            }.value

            guard let self else { return }
            isPruningWorkspaces = false
            guard let inventory, inventory.isComplete else { return }

            let workspaceSessionIDs = workspaceStore.workspaces
                .map(\.terminalSessionID)
            let missingSessionIDs = workspaceSessionIDs
                .filter { !inventory.sessionIDs.contains($0) }

            guard !missingSessionIDs.isEmpty else { return }

            workspaceStore.removeClosedWorkspaces(using: inventory)

            if let selectedWorkspaceID,
               workspaceStore.workspace(id: selectedWorkspaceID) == nil {
                self.selectedWorkspaceID = nil
                activeSession = nil
                setEditorText("")
            }

            sync()
        }
    }

}
