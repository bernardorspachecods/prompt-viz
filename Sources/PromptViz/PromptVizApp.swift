import ApplicationServices
import AppKit
import CoreGraphics
import SwiftUI
import PromptVizCore

enum PromptVizBuild {
    static let label = "MVP build 15"
}

struct TextInsertionRequest: Equatable, Identifiable {
    let id = UUID()
    let text: String
}

struct SkillHighlightRequest: Equatable, Identifiable {
    let id = UUID()
    let range: NSRange
}

enum SkillKeyboardAction {
    case moveUp
    case moveDown
    case choose
}

struct TerminalSession: Equatable, Identifiable {
    let id: String
    let title: String
    let processIdentifier: pid_t
    let tty: String?
}

enum TerminalAutomationError: LocalizedError {
    case accessibilityNotTrusted
    case automationNotTrusted
    case terminalNotActive
    case terminalWindowUnavailable
    case sessionChanged
    case sendFailed
    case automationFailed(String)

    var isAccessibilityNotTrusted: Bool {
        if case .accessibilityNotTrusted = self { return true }
        return false
    }

    var isAutomationNotTrusted: Bool {
        if case .automationNotTrusted = self { return true }
        return false
    }

    var errorDescription: String? {
        switch self {
        case .accessibilityNotTrusted:
            return "O macOS ainda não permitiu ao Prompt Viz enviar teclas para outra app. Ativa o Prompt Viz em Acessibilidade e tenta novamente."
        case .automationNotTrusted:
            return "O macOS bloqueou o Prompt Viz de ler o tab ativo do Terminal.app. Autoriza o Prompt Viz a controlar o Terminal.app nas definições de Automação."
        case .terminalNotActive:
            return "Ativa o tab correto do Terminal.app antes de enviar."
        case .terminalWindowUnavailable:
            return "O Terminal.app está ativo, mas não consegui identificar o tab atual. Fecha e reabre o Prompt Viz com esse tab selecionado."
        case .sessionChanged:
            return "O tab do Terminal mudou. Volta a selecioná-lo e tenta novamente."
        case .sendFailed:
            return "Não foi possível enviar a prompt para o Terminal.app."
        case .automationFailed(let details):
            return "O macOS não conseguiu enviar a prompt através do Terminal.app.\n\n\(details)"
        }
    }
}

extension Notification.Name {
    static let promptVizOpenAccessibilitySettings = Notification.Name("promptVizOpenAccessibilitySettings")
}

final class TerminalAutomation {
    var isTerminalFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.Terminal"
    }

    func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    func openAutomationSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
    }

    func activeSession() throws -> TerminalSession {
        guard
            let application = NSWorkspace.shared.frontmostApplication,
            application.bundleIdentifier == "com.apple.Terminal"
        else { throw TerminalAutomationError.terminalNotActive }

        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        var focusedWindow: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindow
        )

        guard result == .success, let focusedWindow else {
            return try fallbackSession(for: application)
        }

        let windowElement = unsafeDowncast(focusedWindow, to: AXUIElement.self)
        let title = attributeString(windowElement, kAXTitleAttribute as CFString) ?? "Terminal"
        let windowIdentifier = windowNumber(for: windowElement, title: title, application: application)
            .map { "window-\($0)" }
            ?? attributeString(windowElement, kAXIdentifierAttribute as CFString)
        let sessionID = "\(application.processIdentifier):\(windowIdentifier ?? title)"
        let tty = try terminalTTY(for: application)

        return TerminalSession(
            id: sessionID,
            title: title,
            processIdentifier: application.processIdentifier,
            tty: tty
        )
    }

    func activeTerminalWindowFrame() -> CGRect? {
        guard
            let application = NSWorkspace.shared.frontmostApplication,
            application.bundleIdentifier == "com.apple.Terminal"
        else { return nil }

        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        var focusedWindow: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindow
        )

        if result == .success, let focusedWindow {
            let windowElement = unsafeDowncast(focusedWindow, to: AXUIElement.self)
            if let frame = accessibilityFrame(of: windowElement) {
                return frame
            }
        }

        return frontmostWindowFrame(for: application)
    }

    func liveSessionIDs() -> Set<String>? {
        let terminalApplications = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.Terminal"
        )
        let terminalPIDs = Set(terminalApplications.map(\.processIdentifier))

        guard
            let windowInfo = CGWindowListCopyWindowInfo(
                .optionAll,
                kCGNullWindowID
            ) as? [[String: Any]]
        else { return nil }

        return Set(windowInfo.compactMap { info in
            guard
                let ownerPID = info[kCGWindowOwnerPID as String] as? NSNumber,
                terminalPIDs.contains(ownerPID.int32Value),
                let number = info[kCGWindowNumber as String] as? NSNumber
            else { return nil }

            return "\(ownerPID.int32Value):window-\(number.uint32Value)"
        })
    }

    private func fallbackSession(for application: NSRunningApplication) throws -> TerminalSession {
        TerminalSession(
            id: "\(application.processIdentifier):fallback",
            title: "Terminal.app",
            processIdentifier: application.processIdentifier,
            tty: try terminalTTY(for: application)
        )
    }

    func send(_ text: String, to expectedSession: TerminalSession) throws {
        guard !text.isEmpty else { return }

        guard
            let application = NSRunningApplication(processIdentifier: expectedSession.processIdentifier),
            application.activate(options: [.activateIgnoringOtherApps])
        else { throw TerminalAutomationError.sendFailed }

        let activeSession = try activeSession()
        guard activeSession.id == expectedSession.id else {
            throw TerminalAutomationError.sessionChanged
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            throw TerminalAutomationError.sendFailed
        }

        try sendPasteAndReturn(to: expectedSession.processIdentifier)
    }

    private func sendPasteAndReturn(to processIdentifier: pid_t) throws {
        guard AXIsProcessTrusted() else {
            throw TerminalAutomationError.accessibilityNotTrusted
        }

        // Give Terminal time to become frontmost after activate().
        Thread.sleep(forTimeInterval: 0.15)

        guard
            let pasteDown = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true),
            let pasteUp = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false),
            let returnDown = CGEvent(keyboardEventSource: nil, virtualKey: 36, keyDown: true),
            let returnUp = CGEvent(keyboardEventSource: nil, virtualKey: 36, keyDown: false)
        else {
            throw TerminalAutomationError.sendFailed
        }

        pasteDown.flags = .maskCommand
        pasteUp.flags = .maskCommand
        pasteDown.postToPid(processIdentifier)
        pasteUp.postToPid(processIdentifier)
        Thread.sleep(forTimeInterval: 0.05)
        returnDown.postToPid(processIdentifier)
        returnUp.postToPid(processIdentifier)
    }

    private func attributeString(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? String
    }

    private func terminalTTY(for application: NSRunningApplication) throws -> String? {
        let source = """
        tell application "Terminal"
            if (count of windows) is 0 then return ""
            return tty of selected tab of front window
        end tell
        """

        guard let script = NSAppleScript(source: source) else {
            throw TerminalAutomationError.automationNotTrusted
        }

        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        guard error == nil else {
            throw TerminalAutomationError.automationNotTrusted
        }

        let tty = result.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return tty.isEmpty ? nil : tty
    }

    private func windowNumber(
        for element: AXUIElement,
        title: String,
        application: NSRunningApplication
    ) -> CGWindowID? {
        guard
            let frame = accessibilityFrame(of: element),
            let windowInfo = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
            ) as? [[String: Any]]
        else { return nil }

        let candidates: [(windowNumber: CGWindowID, score: CGFloat)] = windowInfo.compactMap {
            (info) -> (windowNumber: CGWindowID, score: CGFloat)? in
            guard
                let ownerPID = info[kCGWindowOwnerPID as String] as? NSNumber,
                ownerPID.intValue == Int(application.processIdentifier),
                let number = info[kCGWindowNumber as String] as? NSNumber,
                let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                let candidateFrame = CGRect(dictionaryRepresentation: bounds)
            else { return nil }

            let titlePenalty: CGFloat = (info[kCGWindowName as String] as? String) == title ? 0 : 10_000
            let distance = abs(candidateFrame.minX - frame.minX)
                + abs(candidateFrame.minY - frame.minY)
                + abs(candidateFrame.width - frame.width)
                + abs(candidateFrame.height - frame.height)

            return (number.uint32Value, titlePenalty + distance)
        }

        return candidates.min(by: { $0.score < $1.score })?.windowNumber
    }

    private func accessibilityFrame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
            AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
            let positionValue,
            let sizeValue
        else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard
            AXValueGetValue(unsafeDowncast(positionValue, to: AXValue.self), .cgPoint, &position),
            AXValueGetValue(unsafeDowncast(sizeValue, to: AXValue.self), .cgSize, &size)
        else { return nil }

        return CGRect(origin: position, size: size)
    }

    private func frontmostWindowFrame(for application: NSRunningApplication) -> CGRect? {
        guard
            let windowInfo = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
            ) as? [[String: Any]]
        else { return nil }

        let frames: [CGRect] = windowInfo.compactMap { info in
            guard
                let ownerPID = info[kCGWindowOwnerPID as String] as? NSNumber,
                ownerPID.intValue == Int(application.processIdentifier),
                let layer = info[kCGWindowLayer as String] as? NSNumber,
                layer.intValue == 0,
                let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                let frame = CGRect(dictionaryRepresentation: bounds)
            else { return nil }

            return frame
        }

        return frames.first
    }
}

final class LocalSnippetPersistence {
    private let defaults: UserDefaults
    private let key = "prompt-viz.snippets"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [Snippet]? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode([Snippet].self, from: data)
    }

    func save(_ snippets: [Snippet]) {
        guard let data = try? JSONEncoder().encode(snippets) else { return }
        defaults.set(data, forKey: key)
    }
}

@MainActor
final class PromptVizModel: ObservableObject {
    static let shared = PromptVizModel()

    @Published private(set) var workspaces: [Workspace] = []
    @Published private(set) var snippets: [Snippet] = []
    @Published private(set) var skills: [SkillDescriptor] = []
    @Published var selectedWorkspaceID: UUID?
    @Published var editorText = ""
    @Published var insertionRequest: TextInsertionRequest?
    @Published var editorCursorLocationRequest: Int?
    @Published var skillHighlightRequest: SkillHighlightRequest?
    @Published var templateToFill: Snippet?
    @Published var errorMessage: String?
    @Published var shouldOfferAccessibilitySettings = false
    @Published var shouldOfferAutomationSettings = false
    @Published var isMainWindowVisible = false
    var openMainWindowHandler: (() -> Void)?
    var workspacesDidChangeHandler: (() -> Void)?

    let workspaceStore = WorkspaceStore()
    let snippetLibrary: SnippetLibrary
    let terminalAutomation = TerminalAutomation()
    private let snippetPersistence = LocalSnippetPersistence()
    let skillCatalog = SkillCatalog()
    private let terminalInputSync = TerminalInputSyncController()
    private let terminalKeyMirror = TerminalKeyMirror()
    private var workspaceMonitor: Timer?
    private var skillMonitor: Timer?
    private(set) var activeSession: TerminalSession?

    private init() {
        snippetLibrary = SnippetLibrary(snippets: snippetPersistence.load())
        skills = skillCatalog.scan()
        terminalInputSync.onBufferChanged = { [weak self] buffer in
            self?.applyTerminalInput(buffer)
        }
        terminalKeyMirror.onBufferChanged = { [weak self] buffer in
            self?.applyTerminalInput(buffer)
        }
        terminalInputSync.start()
        sync()
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

    func captureActiveTerminalSession() {
        shouldOfferAccessibilitySettings = false
        shouldOfferAutomationSettings = false

        guard terminalAutomation.isTerminalFrontmost else {
            errorMessage = TerminalAutomationError.terminalNotActive.localizedDescription
            openMainWindow()
            return
        }

        do {
            let session = try terminalAutomation.activeSession()
            activeSession = session
            let workspace = workspaceStore.workspace(
                for: session.id,
                title: session.title,
                terminalTTY: session.tty
            )
            selectedWorkspaceID = workspace.id
            editorText = terminalKeyMirror.buffer(for: session.tty) ?? workspace.draft
            terminalKeyMirror.reset(buffer: editorText, for: session.tty)
            terminalInputSync.select(tty: session.tty)
            sync()
            openMainWindow()
        } catch {
            errorMessage = error.localizedDescription
            shouldOfferAccessibilitySettings = (error as? TerminalAutomationError)?.isAccessibilityNotTrusted == true
            shouldOfferAutomationSettings = (error as? TerminalAutomationError)?.isAutomationNotTrusted == true
            openMainWindow()
        }
    }

    func select(_ workspace: Workspace) {
        saveCurrentDraft()
        selectedWorkspaceID = workspace.id
        editorText = workspace.draft
        activeSession = TerminalSession(
            id: workspace.terminalSessionID,
            title: workspace.title,
            processIdentifier: workspace.terminalSessionID.split(separator: ":").first.flatMap { pid_t($0) } ?? 0,
            tty: workspace.terminalTTY
        )
        terminalKeyMirror.reset(buffer: editorText, for: workspace.terminalTTY)
        terminalInputSync.select(tty: workspace.terminalTTY)
        sync()
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
            editorText = nextWorkspace.draft
            activeSession = TerminalSession(
                id: nextWorkspace.terminalSessionID,
                title: nextWorkspace.title,
                processIdentifier: nextWorkspace.terminalSessionID.split(separator: ":").first.flatMap { pid_t($0) } ?? 0,
                tty: nextWorkspace.terminalTTY
            )
            terminalKeyMirror.reset(buffer: editorText, for: nextWorkspace.terminalTTY)
            terminalInputSync.select(tty: nextWorkspace.terminalTTY)
        } else {
            selectedWorkspaceID = nil
            activeSession = nil
            editorText = ""
            terminalKeyMirror.reset(buffer: "")
            terminalInputSync.select(tty: nil)
        }

        sync()
    }

    func updateEditorText(_ text: String) {
        editorText = text
        saveCurrentDraft()
        sync()
    }

    func insert(_ snippet: Snippet) {
        if TemplateEngine.fieldNames(in: snippet.body).isEmpty {
            insertionRequest = TextInsertionRequest(text: snippet.body)
        } else {
            templateToFill = snippet
        }
    }

    func selectSkill(_ skill: SkillDescriptor) {
        let invocation = "$" + skill.name + " "
        let expression = #"\$[A-Za-z0-9_-]*$"#

        if let range = editorText.range(of: expression, options: .regularExpression) {
            let tokenRange = NSRange(range, in: editorText)
            editorText.replaceSubrange(range, with: invocation)
            editorCursorLocationRequest = (editorText as NSString).length
            skillHighlightRequest = SkillHighlightRequest(
                range: NSRange(
                    location: tokenRange.location,
                    length: invocation.dropLast().utf16.count
                )
            )
            saveCurrentDraft()
            sync()
        } else {
            insertionRequest = TextInsertionRequest(text: invocation)
        }
    }

    func applyTemplate(_ snippet: Snippet, values: [String: String]) {
        insertionRequest = TextInsertionRequest(text: TemplateEngine.render(snippet.body, values: values))
        templateToFill = nil
    }

    func send() {
        shouldOfferAccessibilitySettings = false
        shouldOfferAutomationSettings = false

        guard let activeSession else {
            errorMessage = TerminalAutomationError.terminalNotActive.localizedDescription
            return
        }

        do {
            try terminalAutomation.send(editorText, to: activeSession)
            updateEditorText("")
            terminalKeyMirror.reset(buffer: "", for: activeSession.tty)
            openMainWindow()
        } catch {
            errorMessage = error.localizedDescription
            shouldOfferAccessibilitySettings = (error as? TerminalAutomationError)?.isAccessibilityNotTrusted == true
            shouldOfferAutomationSettings = (error as? TerminalAutomationError)?.isAutomationNotTrusted == true
        }
    }

    func addSnippet(title: String, body: String, favorite: Bool) {
        snippetLibrary.add(Snippet(title: title, body: body, isFavorite: favorite))
        snippetPersistence.save(snippetLibrary.snippets)
        sync()
    }

    func updateSnippet(_ snippet: Snippet) {
        snippetLibrary.update(snippet)
        snippetPersistence.save(snippetLibrary.snippets)
        sync()
    }

    func removeSnippet(_ snippet: Snippet) {
        snippetLibrary.remove(id: snippet.id)
        snippetPersistence.save(snippetLibrary.snippets)
        sync()
    }

    func openMainWindow() {
        isMainWindowVisible = true
        NSApp.activate(ignoringOtherApps: true)
        openMainWindowHandler?()
    }

    private func saveCurrentDraft() {
        guard let selectedWorkspaceID else { return }
        workspaceStore.updateDraft(editorText, for: selectedWorkspaceID)
    }

    private func applyTerminalInput(_ text: String) {
        guard let tty = activeSession?.tty else { return }
        terminalKeyMirror.reset(buffer: text, for: tty)
        editorText = text
        saveCurrentDraft()
        sync()
    }

    private func sync() {
        workspaces = workspaceStore.workspaces
        snippets = snippetLibrary.snippets
        workspacesDidChangeHandler?()
    }

    private func refreshSkills() {
        skills = skillCatalog.scan()
    }

    private func pruneClosedWorkspaces() {
        guard let liveSessionIDs = terminalAutomation.liveSessionIDs() else { return }

        let closedSessionIDs = workspaceStore.workspaces
            .map(\.terminalSessionID)
            .filter { $0.contains(":window-") && !liveSessionIDs.contains($0) }

        guard !closedSessionIDs.isEmpty else { return }

        for sessionID in closedSessionIDs {
            workspaceStore.removeWorkspace(for: sessionID)
        }

        if let selectedWorkspaceID,
           workspaceStore.workspace(id: selectedWorkspaceID) == nil {
            self.selectedWorkspaceID = nil
            activeSession = nil
            editorText = ""
            terminalKeyMirror.reset(buffer: "")
            terminalInputSync.select(tty: nil)
        }

        sync()
    }

    func handleTerminalKeyEvent(_ event: TerminalKeyEvent) {
        guard
            terminalAutomation.isTerminalFrontmost,
            let observedSession = try? terminalAutomation.activeSession(),
            let observedTTY = observedSession.tty
        else { return }

        terminalKeyMirror.handle(event, for: observedTTY)

        guard
            let selectedTTY = activeSession?.tty,
            TerminalInputRouting.shouldMirror(
                selectedTTY: selectedTTY,
                observedTTY: observedTTY
            )
        else { return }

        applyTerminalInput(terminalKeyMirror.buffer(for: observedTTY) ?? "")
    }
}

@main
struct PromptVizApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = PromptVizModel.shared

    var body: some Scene {
        MenuBarExtra("Prompt Viz · \(PromptVizBuild.label)", systemImage: "text.bubble") {
            Button("Abrir compositor") {
                model.captureActiveTerminalSession()
            }
            .keyboardShortcut("e", modifiers: [.command])

            Divider()

            Button("Sair") {
                NSApplication.shared.terminate(nil)
            }
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Abrir compositor") {
                    model.captureActiveTerminalSession()
                }
                .keyboardShortcut("e", modifiers: [.command])
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindowController: MainWindowController?
    private var keyboardMonitor: Any?
    private var workspaceSwitchMonitor: Any?
    private var terminalInputMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = PromptVizModel.shared
        mainWindowController = MainWindowController(model: model)
        model.openMainWindowHandler = { [weak self] in
            self?.mainWindowController?.show()
        }
        model.workspacesDidChangeHandler = { [weak self] in
            self?.mainWindowController?.reconcileWindows()
        }

        keyboardMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            guard
                event.keyCode == 14,
                event.modifierFlags.contains(.command),
                !event.modifierFlags.contains(.option),
                !event.modifierFlags.contains(.control),
                !event.modifierFlags.contains(.shift)
            else { return }
            model.captureActiveTerminalSession()
        }

        workspaceSwitchMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags
            guard
                event.keyCode == 48,
                modifiers.contains(.control),
                !modifiers.contains(.command),
                !modifiers.contains(.option)
            else { return event }

            guard !model.workspaces.isEmpty else { return event }
            let offset = modifiers.contains(.shift) ? -1 : 1
            Task { @MainActor [weak self] in
                self?.mainWindowController?.selectRelativeTab(by: offset)
            }
            return nil
        }

        terminalInputMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.Terminal" else {
                return
            }

            let isPaste = event.modifierFlags.contains(.command) && event.keyCode == 9
            let terminalEvent = TerminalKeyEvent(
                keyCode: event.keyCode,
                characters: event.characters ?? "",
                modifierRawValue: event.modifierFlags.rawValue,
                pasteboardText: isPaste ? NSPasteboard.general.string(forType: .string) : nil
            )

            Task { @MainActor [weak model] in
                model?.handleTerminalKeyEvent(terminalEvent)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let keyboardMonitor {
            NSEvent.removeMonitor(keyboardMonitor)
        }
        if let workspaceSwitchMonitor {
            NSEvent.removeMonitor(workspaceSwitchMonitor)
        }
        if let terminalInputMonitor {
            NSEvent.removeMonitor(terminalInputMonitor)
        }
    }
}

@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    private let model: PromptVizModel
    private var windowsByWorkspaceID: [UUID: NSWindow] = [:]

    init(model: PromptVizModel) {
        self.model = model
        super.init()
    }

    func reconcileWindows() {
        let workspaceIDs = Set(model.workspaces.map(\.id))

        for (workspaceID, window) in windowsByWorkspaceID where !workspaceIDs.contains(workspaceID) {
            windowsByWorkspaceID.removeValue(forKey: workspaceID)
            window.delegate = nil
            window.close()
        }

        for workspace in model.workspaces where windowsByWorkspaceID[workspace.id] == nil {
            createWindow(for: workspace)
        }
    }

    func show() {
        reconcileWindows()

        guard
            let selectedWorkspaceID = model.selectedWorkspaceID,
            let window = windowsByWorkspaceID[selectedWorkspaceID]
        else { return }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func selectRelativeTab(by offset: Int) {
        guard
            let window = NSApp.keyWindow,
            let tabGroup = window.tabGroup,
            tabGroup.windows.count > 1
        else { return }

        if offset < 0 {
            window.selectPreviousTab(nil)
        } else {
            window.selectNextTab(nil)
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        activateWorkspace(for: notification)
    }

    func windowDidBecomeMain(_ notification: Notification) {
        activateWorkspace(for: notification)
    }

    func windowWillClose(_ notification: Notification) {
        guard
            let window = notification.object as? NSWindow,
            let workspaceID = workspaceID(for: window)
        else { return }

        windowsByWorkspaceID.removeValue(forKey: workspaceID)
        model.closeWorkspace(id: workspaceID)
    }

    private func createWindow(for workspace: Workspace) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = tabTitle(for: workspace.title)
        window.tabbingIdentifier = "com.promptviz.workspace"
        window.tabbingMode = .preferred
        window.minSize = NSSize(width: 760, height: 500)
        window.contentView = NSHostingView(
            rootView: ContentView(model: model)
                .frame(minWidth: 760, minHeight: 500)
        )
        window.delegate = self
        window.isReleasedWhenClosed = false

        if let existingWindow = windowsByWorkspaceID.values.first {
            existingWindow.addTabbedWindow(window, ordered: .above)
        } else {
            window.center()
        }

        windowsByWorkspaceID[workspace.id] = window
    }

    private func activateWorkspace(for notification: Notification) {
        guard
            let window = notification.object as? NSWindow,
            let workspaceID = workspaceID(for: window),
            let workspace = model.workspaces.first(where: { $0.id == workspaceID }),
            model.selectedWorkspaceID != workspaceID
        else { return }

        model.select(workspace)
    }

    private func workspaceID(for window: NSWindow) -> UUID? {
        windowsByWorkspaceID.first { $0.value === window }?.key
    }

    private func tabTitle(for title: String) -> String {
        String(title.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: true).first ?? Substring(title))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@MainActor
struct ContentView: View {
    @ObservedObject var model: PromptVizModel
    @State private var snippetSearch = ""
    @State private var showingSnippetEditor = false
    @State private var editingSnippet: Snippet?
    @State private var hoveredSkillID: String?
    @State private var selectedSkillIndex = -1

    private var composerTitle: String {
        let title = model.selectedWorkspace?.title ?? "Prompt Viz"
        return String(title.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: true).first ?? Substring(title))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func workspaceDisplayParts(for title: String) -> (repository: String, chat: String?) {
        let withoutSuffix = title
            .components(separatedBy: "|")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? title
        let parts = withoutSuffix.components(separatedBy: " — ")

        guard let repository = parts.first else {
            return (withoutSuffix, nil)
        }

        let chat = parts.dropFirst().joined(separator: " — ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return (
            repository.trimmingCharacters(in: .whitespacesAndNewlines),
            chat.isEmpty ? nil : chat
        )
    }

    private var visibleSnippets: [Snippet] {
        model.snippetLibrary.search(snippetSearch)
    }

    private var activeSkillQuery: String? {
        guard let range = model.editorText.range(
            of: #"\$[A-Za-z0-9_-]*$"#,
            options: .regularExpression
        ) else { return nil }

        return String(model.editorText[range].dropFirst())
    }

    private var visibleSkills: [SkillDescriptor] {
        model.skillCatalog.search(activeSkillQuery ?? "", in: model.skills)
            .prefix(6)
            .map { $0 }
    }

    var body: some View {
        composer
        .sheet(item: $model.templateToFill) { snippet in
            TemplateFillSheet(snippet: snippet) { values in
                model.applyTemplate(snippet, values: values)
            }
        }
        .sheet(isPresented: $showingSnippetEditor) {
            SnippetEditorSheet(snippet: editingSnippet) { title, body, favorite in
                if var editingSnippet {
                    editingSnippet.title = title
                    editingSnippet.body = body
                    editingSnippet.isFavorite = favorite
                    model.updateSnippet(editingSnippet)
                } else {
                    model.addSnippet(title: title, body: body, favorite: favorite)
                }
            }
        }
        .alert("Prompt Viz", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            if model.shouldOfferAutomationSettings {
                Button("Abrir Automação") {
                    model.terminalAutomation.openAutomationSettings()
                    model.errorMessage = nil
                }
            } else if model.shouldOfferAccessibilitySettings {
                Button("Abrir Acessibilidade") {
                    model.terminalAutomation.openAccessibilitySettings()
                    model.errorMessage = nil
                }
            }
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var composer: some View {
        HStack(spacing: 0) {
            snippetSidebar

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(composerTitle)
                        .font(.title2.weight(.semibold))

                    Spacer()

                    Button("Enviar") {
                        model.send()
                    }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .buttonStyle(.borderedProminent)
                    .disabled(model.editorText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(18)

                Divider()

                ZStack(alignment: .topLeading) {
                    PromptTextEditor(
                        text: $model.editorText,
                        insertionRequest: $model.insertionRequest,
                        cursorLocationRequest: $model.editorCursorLocationRequest,
                        skillHighlightRequest: $model.skillHighlightRequest,
                        onSkillKeyboardAction: handleSkillKeyboardAction
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if activeSkillQuery != nil && !visibleSkills.isEmpty {
                        skillSuggestions
                            .padding(.top, 58)
                            .padding(.leading, 14)
                    }
                }
                .padding(12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var snippetSidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Snippets", systemImage: "text.quote")
                    .font(.headline)

                Spacer()

                Button {
                    editingSnippet = nil
                    showingSnippetEditor = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Novo snippet")
            }

            TextField("Pesquisar", text: $snippetSearch)
                .textFieldStyle(.roundedBorder)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 10) {
                    if !model.snippetLibrary.favorites.isEmpty {
                        Text("Favoritos")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        ForEach(Array(model.snippetLibrary.favorites.prefix(9).enumerated()), id: \.element.id) { index, snippet in
                            Button {
                                model.insert(snippet)
                            } label: {
                                Label(snippet.title, systemImage: "star.fill")
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.bordered)
                            .keyboardShortcut(
                                KeyEquivalent(Character(String(index + 1))),
                                modifiers: [.command, .option]
                            )
                        }
                    }

                    if !visibleSnippets.isEmpty {
                        Divider()

                        Text("Todos")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        ForEach(visibleSnippets) { snippet in
                            snippetRow(snippet)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(
            minWidth: 250,
            idealWidth: 250,
            maxWidth: 250,
            maxHeight: .infinity,
            alignment: .top
        )
        .background(.quaternary.opacity(0.18))
    }

    private func snippetRow(_ snippet: Snippet) -> some View {
        HStack(spacing: 4) {
            Button {
                model.insert(snippet)
            } label: {
                Text(snippet.title)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button {
                editingSnippet = snippet
                showingSnippetEditor = true
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help("Editar snippet")

            Button {
                model.removeSnippet(snippet)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Apagar snippet")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
    }

    private var skillSuggestions: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("Skills", systemImage: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(visibleSkills.enumerated()), id: \.element.id) { index, skill in
                        Button {
                            hoveredSkillID = nil
                            selectedSkillIndex = index
                            model.selectSkill(skill)
                        } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "sparkles")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 16)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("$" + skill.name)
                                        .font(.callout.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    if !skill.description.isEmpty {
                                        Text(skill.description)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(
                            hoveredSkillID == skill.id || selectedSkillIndex == index
                                ? Color.accentColor.opacity(0.18)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                        .onHover { isHovered in
                            hoveredSkillID = isHovered ? skill.id : nil
                        }
                    }
                }
            }
            .frame(maxHeight: 220)
        }
        .frame(maxWidth: 500, alignment: .leading)
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(.primary.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
    }

    private func handleSkillKeyboardAction(_ action: SkillKeyboardAction) -> Bool {
        guard !visibleSkills.isEmpty, activeSkillQuery != nil else { return false }

        switch action {
        case .moveDown:
            selectedSkillIndex = selectedSkillIndex < 0
                ? 0
                : (selectedSkillIndex + 1) % visibleSkills.count
        case .moveUp:
            selectedSkillIndex = selectedSkillIndex < 0
                ? visibleSkills.count - 1
                : (selectedSkillIndex - 1 + visibleSkills.count) % visibleSkills.count
        case .choose:
            let index = selectedSkillIndex < 0
                ? 0
                : min(selectedSkillIndex, visibleSkills.count - 1)
            let skill = visibleSkills[index]
            model.selectSkill(skill)
            selectedSkillIndex = -1
        }

        return true
    }
}

struct PromptTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var insertionRequest: TextInsertionRequest?
    @Binding var cursorLocationRequest: Int?
    @Binding var skillHighlightRequest: SkillHighlightRequest?
    let onSkillKeyboardAction: (SkillKeyboardAction) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSkillKeyboardAction: onSkillKeyboardAction)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.font = .systemFont(ofSize: 15)
        textView.textContainerInset = NSSize(width: 10, height: 12)
        textView.drawsBackground = false

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.onSkillKeyboardAction = onSkillKeyboardAction

        if textView.string != text {
            let location = min(textView.selectedRange().location, text.utf16.count)
            textView.string = text
            textView.setSelectedRange(NSRange(location: location, length: 0))
        }

        if let cursorLocationRequest {
            let location = min(max(0, cursorLocationRequest), (textView.string as NSString).length)
            textView.setSelectedRange(NSRange(location: location, length: 0))
            DispatchQueue.main.async {
                guard self.cursorLocationRequest == cursorLocationRequest else { return }
                self.cursorLocationRequest = nil
            }
        }

        if let skillHighlightRequest,
           context.coordinator.lastSkillHighlightID != skillHighlightRequest.id {
            let textLength = (textView.string as NSString).length
            let location = min(max(0, skillHighlightRequest.range.location), textLength)
            let length = min(
                max(0, skillHighlightRequest.range.length),
                textLength - location
            )

            if length > 0 {
                textView.textStorage?.addAttributes([
                    .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
                    .foregroundColor: NSColor.controlAccentColor
                ], range: NSRange(location: location, length: length))
                textView.typingAttributes = [
                    .font: NSFont.systemFont(ofSize: 15),
                    .foregroundColor: NSColor.labelColor
                ]
            }

            context.coordinator.lastSkillHighlightID = skillHighlightRequest.id
            let requestID = skillHighlightRequest.id
            DispatchQueue.main.async {
                guard self.skillHighlightRequest?.id == requestID else { return }
                self.skillHighlightRequest = nil
            }
        }

        guard
            let insertionRequest,
            context.coordinator.lastInsertionID != insertionRequest.id
        else { return }

        context.coordinator.lastInsertionID = insertionRequest.id
        let currentLength = (textView.string as NSString).length
        let selectedRange = textView.selectedRange()
        let location = min(max(0, selectedRange.location), currentLength)
        let length = min(max(0, selectedRange.length), currentLength - location)
        let selection = NSRange(location: location, length: length)
        let updated = (textView.string as NSString).replacingCharacters(in: selection, with: insertionRequest.text)
        textView.string = updated
        textView.setSelectedRange(NSRange(location: selection.location + insertionRequest.text.utf16.count, length: 0))
        let requestID = insertionRequest.id
        DispatchQueue.main.async {
            guard self.insertionRequest?.id == requestID else { return }
            self.text = updated
            self.insertionRequest = nil
            context.coordinator.lastInsertionID = nil
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        var lastInsertionID: UUID?
        var lastSkillHighlightID: UUID?
        var onSkillKeyboardAction: (SkillKeyboardAction) -> Bool

        init(
            text: Binding<String>,
            onSkillKeyboardAction: @escaping (SkillKeyboardAction) -> Bool
        ) {
            _text = text
            self.onSkillKeyboardAction = onSkillKeyboardAction
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch NSStringFromSelector(commandSelector) {
            case "moveDown:":
                return onSkillKeyboardAction(.moveDown)
            case "moveUp:":
                return onSkillKeyboardAction(.moveUp)
            case "insertNewline:":
                if NSApp.currentEvent?.modifierFlags.contains(.command) == true {
                    return false
                }
                return onSkillKeyboardAction(.choose)
            default:
                return false
            }
        }
    }
}

struct TemplateFillSheet: View {
    let snippet: Snippet
    let onInsert: ([String: String]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var values: [String: String]
    @FocusState private var focusedField: String?

    init(snippet: Snippet, onInsert: @escaping ([String: String]) -> Void) {
        self.snippet = snippet
        self.onInsert = onInsert
        _values = State(initialValue: Dictionary(
            uniqueKeysWithValues: TemplateEngine.fieldNames(in: snippet.body).map { ($0, "") }
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(snippet.title)
                .font(.title2.weight(.semibold))
            Text(snippet.body)
                .font(.callout)
                .foregroundStyle(.secondary)

            ForEach(TemplateEngine.fieldNames(in: snippet.body), id: \.self) { field in
                TextField(field, text: Binding(
                    get: { values[field, default: ""] },
                    set: { values[field] = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: field)
            }

            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }
                Button("Inserir") {
                    onInsert(values)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
            }
        }
        .padding(24)
        .frame(width: 430)
        .onAppear {
            focusedField = TemplateEngine.fieldNames(in: snippet.body).first
        }
    }
}

struct SnippetEditorSheet: View {
    let snippet: Snippet?
    let onSave: (String, String, Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var snippetBody: String
    @State private var favorite: Bool

    init(snippet: Snippet?, onSave: @escaping (String, String, Bool) -> Void) {
        self.snippet = snippet
        self.onSave = onSave
        _title = State(initialValue: snippet?.title ?? "")
        _snippetBody = State(initialValue: snippet?.body ?? "")
        _favorite = State(initialValue: snippet?.isFavorite ?? false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(snippet == nil ? "Novo snippet" : "Editar snippet")
                .font(.title2.weight(.semibold))
            TextField("Nome", text: $title)
                .textFieldStyle(.roundedBorder)
            TextEditor(text: $snippetBody)
                .font(.body.monospaced())
                .frame(height: 130)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            Toggle("Mostrar nos favoritos", isOn: $favorite)
            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }
                Button("Guardar") {
                    onSave(title, snippetBody, favorite)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || snippetBody.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 500)
    }
}
