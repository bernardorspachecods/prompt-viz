import ApplicationServices
import AppKit
import CoreGraphics
import OSLog
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers
import PromptVizCore

enum PromptVizBuild {
    static let label = "MVP build 20"
}

enum PromptVizLog {
    private static let logger = Logger(subsystem: "local.prompt-viz.app", category: "runtime")
    private static let lock = NSLock()

    static let fileURL = FileManager.default
        .urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Logs", isDirectory: true)
        .appendingPathComponent("PromptViz.log")

    static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        append(level: "INFO", message: message)
    }

    static func error(_ error: Error, context: String) {
        let message = "\(context): \(error.localizedDescription)"
        logger.error("\(message, privacy: .public)")
        append(level: "ERROR", message: message)
    }

    private static func append(level: String, message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(timestamp) [\(level)] \(message)\n"

        lock.lock()
        defer { lock.unlock() }

        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: fileURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
            try handle.close()
        } catch {
            logger.error("Could not write log file: \(error.localizedDescription, privacy: .public)")
        }
    }
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

private func isImagePasteShortcut(_ event: NSEvent) -> Bool {
    let modifiers = event.modifierFlags
    guard modifiers.contains(.option),
          !modifiers.contains(.command),
          !modifiers.contains(.control)
    else { return false }

    return event.keyCode == 9 ||
        event.charactersIgnoringModifiers?.lowercased() == "v" ||
        event.characters?.lowercased() == "√"
}

struct GlobalShortcut: Codable, Equatable {
    static let defaultShortcut = GlobalShortcut(keyCode: 14, modifierFlags: NSEvent.ModifierFlags.command.rawValue)
    private static let relevantModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    let keyCode: UInt16
    let modifierFlags: UInt

    var displayName: String {
        let modifiers = NSEvent.ModifierFlags(rawValue: modifierFlags)
        var name = ""
        if modifiers.contains(.control) { name += "⌃" }
        if modifiers.contains(.option) { name += "⌥" }
        if modifiers.contains(.shift) { name += "⇧" }
        if modifiers.contains(.command) { name += "⌘" }
        return name + Self.keyName(for: keyCode)
    }

    func matches(_ event: NSEvent) -> Bool {
        let eventModifiers = event.modifierFlags.intersection(Self.relevantModifiers)
        return event.keyCode == keyCode && eventModifiers.rawValue == modifierFlags
    }

    private static func keyName(for keyCode: UInt16) -> String {
        let names: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L",
            38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
            45: "N", 46: "M", 47: ".", 50: "`", 36: "↩", 48: "⇥", 49: "Space",
            51: "⌫", 53: "Esc", 123: "←", 124: "→", 125: "↓", 126: "↑"
        ]
        return names[keyCode] ?? "Key \(keyCode)"
    }
}

enum GlobalShortcutPersistence {
    private static let key = "prompt-viz.open-composer-shortcut"

    static func load(defaults: UserDefaults = .standard) -> GlobalShortcut {
        guard
            let data = defaults.data(forKey: key),
            let shortcut = try? JSONDecoder().decode(GlobalShortcut.self, from: data)
        else { return .defaultShortcut }

        return shortcut
    }

    static func save(_ shortcut: GlobalShortcut, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(shortcut) else { return }
        defaults.set(data, forKey: key)
    }
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
    case codexInputUnavailable
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
            return "macOS has not yet allowed Prompt Viz to send keystrokes to another app. Enable Prompt Viz in Accessibility and try again."
        case .automationNotTrusted:
            return "macOS blocked Prompt Viz from reading the active Terminal.app tab. Allow Prompt Viz to control Terminal.app in Automation settings."
        case .terminalNotActive:
            return "Activate the correct Terminal.app tab before sending."
        case .terminalWindowUnavailable:
            return "Terminal.app is active, but I couldn't identify the current tab. Close and reopen Prompt Viz with that tab selected."
        case .sessionChanged:
            return "The Terminal tab changed. Select it again and try again."
        case .sendFailed:
            return "Could not send the prompt to Terminal.app."
        case .codexInputUnavailable:
            return "I couldn't locate the Codex prompt field in this tab. The text was kept in the app and nothing was sent."
        case .automationFailed(let details):
            return "macOS couldn't send the prompt through Terminal.app.\n\n\(details)"
        }
    }
}

enum LaunchAtLogin {
    static var isEnabled: Bool {
        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval:
            return true
        case .notRegistered, .notFound:
            return false
        @unknown default:
            return false
        }
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

extension Notification.Name {
    static let promptVizOpenAccessibilitySettings = Notification.Name("promptVizOpenAccessibilitySettings")
    static let promptVizOpenSettings = Notification.Name("promptVizOpenSettings")
}

final class TerminalAutomation: @unchecked Sendable {
    private let tabSelectionQueue = DispatchQueue(label: "com.promptviz.terminal-tab-selection")

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

        let title: String
        if result == .success, let focusedWindow {
            let windowElement = unsafeDowncast(focusedWindow, to: AXUIElement.self)
            title = attributeString(windowElement, kAXTitleAttribute as CFString) ?? "Terminal"
        } else {
            title = "Terminal"
        }

        guard let tty = try terminalTTY() else {
            throw TerminalAutomationError.terminalWindowUnavailable
        }

        return TerminalSession(
            id: tty,
            title: title,
            processIdentifier: application.processIdentifier,
            tty: tty
        )
    }

    func activeCodexDraft() throws -> String {
        guard isTerminalFrontmost else {
            throw TerminalAutomationError.terminalNotActive
        }

        let application = NSWorkspace.shared.frontmostApplication
        guard let application, application.bundleIdentifier == "com.apple.Terminal" else {
            throw TerminalAutomationError.terminalNotActive
        }

        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        var focusedWindow: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindow
        ) == .success,
        let focusedWindow
        else {
            throw TerminalAutomationError.codexInputUnavailable
        }

        let windowElement = unsafeDowncast(focusedWindow, to: AXUIElement.self)
        guard let screen = accessibilityTextValue(in: windowElement),
              let draft = CodexTerminalInputParser.extractDraft(from: screen)
        else {
            throw TerminalAutomationError.codexInputUnavailable
        }

        return draft
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

    func liveSessionInventory() -> TerminalSessionInventory? {
        let source = """
        tell application "Terminal"
            set allTTYS to {}
            set inventoryComplete to true
            set tabCount to 0
            repeat with terminalWindow in windows
                repeat with terminalTab in tabs of terminalWindow
                    set tabCount to tabCount + 1
                    set tabTTYText to ""
                    try
                        set tabTTYText to (tty of terminalTab as text)
                        if tabTTYText is "" then
                            set inventoryComplete to false
                        else
                            set end of allTTYS to tabTTYText
                        end if
                    on error
                        set inventoryComplete to false
                    end try
                end repeat
            end repeat
            return {allTTYS, inventoryComplete, tabCount}
        end tell
        """

        guard let script = NSAppleScript(source: source) else { return nil }

        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        guard error == nil else { return nil }

        guard
            result.numberOfItems >= 3,
            let ttyResult = result.atIndex(1),
            let completeResult = result.atIndex(2),
            let tabCountResult = result.atIndex(3)
        else { return nil }

        let tabCount = Int(tabCountResult.int32Value)
        guard tabCount >= 0 else { return nil }

        let indexes = ttyResult.numberOfItems == 0 ? [] : Array(1...ttyResult.numberOfItems)
        let sessionIDs = Set(indexes.compactMap { index in
            ttyResult.atIndex(index)?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty })

        let inventory = TerminalSessionInventory(
            sessionIDs: sessionIDs,
            tabCount: tabCount,
            enumerationSucceeded: completeResult.booleanValue
        )
        return inventory
    }

    func sendCodexInputAndReturn(
        _ buffer: String,
        imageAttachments: [PromptImageAttachment] = [],
        to expectedSession: TerminalSession
    ) throws {
        guard let expectedTTY = expectedSession.tty else {
            throw TerminalAutomationError.sessionChanged
        }

        guard
            let application = NSRunningApplication(processIdentifier: expectedSession.processIdentifier),
            application.activate(options: [.activateIgnoringOtherApps])
        else { throw TerminalAutomationError.sendFailed }

        try selectTab(tty: expectedTTY)
        Thread.sleep(forTimeInterval: 0.15)

        let activeSession = try activeSession()
        guard activeSession.id == expectedSession.id else {
            throw TerminalAutomationError.sessionChanged
        }

        guard AXIsProcessTrusted() else {
            throw TerminalAutomationError.accessibilityNotTrusted
        }

        postKey(virtualKey: 0, flags: .maskControl, to: expectedSession.processIdentifier)
        postKey(virtualKey: 40, flags: .maskControl, to: expectedSession.processIdentifier)
        try pastePrompt(
            buffer,
            imageAttachments: imageAttachments,
            to: expectedSession.processIdentifier
        )
        postKey(virtualKey: 36, flags: [], to: expectedSession.processIdentifier)
    }

    private func pastePrompt(
        _ buffer: String,
        imageAttachments: [PromptImageAttachment],
        to processIdentifier: pid_t
    ) throws {
        let expression = try! NSRegularExpression(pattern: #"\[Image #([0-9]+)\]"#)
        let nsBuffer = buffer as NSString
        let range = NSRange(location: 0, length: nsBuffer.length)
        let attachmentsByNumber = Dictionary(
            uniqueKeysWithValues: imageAttachments.map { ($0.number, $0) }
        )
        var cursor = 0

        for match in expression.matches(in: buffer, range: range) {
            if match.range.location > cursor {
                try pasteText(
                    nsBuffer.substring(with: NSRange(
                        location: cursor,
                        length: match.range.location - cursor
                    )),
                    to: processIdentifier
                )
            }

            let reference = nsBuffer.substring(with: match.range)
            let number = Int(nsBuffer.substring(with: match.range(at: 1)))
            if let number, let attachment = attachmentsByNumber[number] {
                PromptVizLog.info("Sending image attachment #[\(number)] with Ctrl+V")
                try pasteImage(attachment.data, to: processIdentifier)
            } else {
                try pasteText(reference, to: processIdentifier)
            }
            cursor = match.range.location + match.range.length
        }

        if cursor < nsBuffer.length {
            try pasteText(
                nsBuffer.substring(with: NSRange(
                    location: cursor,
                    length: nsBuffer.length - cursor
                )),
                to: processIdentifier
            )
        }
    }

    private func pasteText(_ text: String, to processIdentifier: pid_t) throws {
        guard !text.isEmpty else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            throw TerminalAutomationError.sendFailed
        }

        postKey(virtualKey: 9, flags: .maskCommand, to: processIdentifier)
        Thread.sleep(forTimeInterval: 0.2)
    }

    private func pasteImage(_ data: Data, to processIdentifier: pid_t) throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setData(data, forType: .png) else {
            throw TerminalAutomationError.sendFailed
        }

        // Codex's TUI reserves Ctrl+V for reading an image from the system
        // clipboard. Cmd+V is the terminal's normal text-paste command.
        postKey(virtualKey: 9, flags: .maskControl, to: processIdentifier)
        Thread.sleep(forTimeInterval: 0.2)
        PromptVizLog.info("Image PNG pasted to Codex with Ctrl+V")
    }

    func requestTabSelection(tty: String) {
        tabSelectionQueue.async { [weak self] in
            guard let self else { return }
            try? self.selectTabImmediately(tty: tty)
        }
    }

    func selectTab(tty: String) throws {
        try tabSelectionQueue.sync {
            try selectTabImmediately(tty: tty)
        }
    }

    private func selectTabImmediately(tty: String) throws {
        let escapedTTY = tty
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = """
        tell application "Terminal"
            repeat with terminalWindow in windows
                repeat with terminalTab in tabs of terminalWindow
                    if (tty of terminalTab as text) is "\(escapedTTY)" then
                        set selected of terminalTab to true
                        set index of terminalWindow to 1
                        return true
                    end if
                end repeat
            end repeat
            return false
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

        guard result.booleanValue else {
            throw TerminalAutomationError.sessionChanged
        }
    }

    private func attributeString(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? String
    }

    private func accessibilityTextValue(in element: AXUIElement) -> String? {
        if attributeString(element, kAXRoleAttribute as CFString) == kAXTextAreaRole,
           let value = attributeString(element, kAXValueAttribute as CFString) {
            return value
        }

        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &childrenValue
        ) == .success,
        let childrenValue,
        let children = childrenValue as? [AXUIElement]
        else { return nil }

        for child in children {
            if let value = accessibilityTextValue(in: child) {
                return value
            }
        }

        return nil
    }

    private func postKey(virtualKey: CGKeyCode, flags: CGEventFlags, to processIdentifier: pid_t) {
        guard
            let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: virtualKey, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: virtualKey, keyDown: false)
        else { return }

        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.postToPid(processIdentifier)
        keyUp.postToPid(processIdentifier)
    }

    private func terminalTTY() throws -> String? {
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

@MainActor
final class PromptVizModel: ObservableObject {
    static let shared = PromptVizModel()

    @Published private(set) var workspaces: [Workspace] = []
    @Published private(set) var snippets: [Snippet] = []
    @Published private(set) var history: [PromptHistoryEntry] = []
    @Published private(set) var skills: [SkillDescriptor] = []
    @Published var selectedWorkspaceID: UUID?
    @Published var editorText = ""
    @Published private(set) var editorImageAttachments: [PromptImageAttachment] = []
    @Published var imagePasteRequest: UUID?
    @Published var insertionRequest: TextInsertionRequest?
    @Published var editorCursorLocationRequest: Int?
    @Published var editorFocusRequest: UUID?
    @Published var skillHighlightRequest: SkillHighlightRequest?
    @Published private(set) var launchesAtLogin = LaunchAtLogin.isEnabled
    @Published private(set) var openComposerShortcut = GlobalShortcutPersistence.load()
    @Published var errorMessage: String?
    @Published var shouldOfferAccessibilitySettings = false
    @Published var shouldOfferAutomationSettings = false
    @Published var isMainWindowVisible = false
    var openMainWindowHandler: (() -> Void)?
    var workspacesDidChangeHandler: (() -> Void)?

    let workspaceStore = WorkspaceStore()
    let snippetLibrary: SnippetLibrary
    let promptHistory: PromptHistoryStore
    let terminalAutomation = TerminalAutomation()
    private let snippetPersistence = LocalSnippetPersistence()
    private let promptHistoryPersistence = LocalPromptHistoryPersistence()
    let skillCatalog = SkillCatalog()
    private var workspaceMonitor: Timer?
    private var skillMonitor: Timer?
    private var editorTextPublicationTimer: Timer?
    private var isPruningWorkspaces = false
    private var isRefreshingSkills = false
    private(set) var isCapturingTerminalSession = false
    private(set) var activeSession: TerminalSession?
    private var latestEditorText = ""

    private init() {
        snippetLibrary = SnippetLibrary(snippets: snippetPersistence.load())
        promptHistory = PromptHistoryStore(entries: promptHistoryPersistence.load())
        skills = []
        sync()
        PromptVizLog.info("Application model initialized")
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
        PromptVizLog.info("Capturing active Terminal session")
        // Capture can switch to a new workspace, so persist the current editor
        // before changing selectedWorkspaceID or letting the new tab activate.
        saveCurrentDraft()
        isCapturingTerminalSession = true
        shouldOfferAccessibilitySettings = false
        shouldOfferAutomationSettings = false

        guard terminalAutomation.isTerminalFrontmost else {
            isCapturingTerminalSession = false
            let error = TerminalAutomationError.terminalNotActive
            PromptVizLog.error(error, context: "Capture failed")
            errorMessage = error.localizedDescription
            openMainWindow()
            return
        }

        do {
            let session = try terminalAutomation.activeSession()
            let codexDraft = try terminalAutomation.activeCodexDraft()
            let editorDraft = CodexDraftEditor.prepareForContinuation(codexDraft)
            activeSession = session
            let workspace = workspaceStore.workspace(
                for: session.id,
                title: session.title,
                terminalTTY: session.tty,
                terminalProcessIdentifier: session.processIdentifier
            )
            selectedWorkspaceID = workspace.id
            setEditorText(editorDraft)
            editorImageAttachments = []
            editorCursorLocationRequest = (editorDraft as NSString).length
            editorFocusRequest = UUID()
            workspaceStore.updateDraft(editorDraft, for: workspace.id)
            sync()
            openMainWindow()
            PromptVizLog.info("Terminal session captured successfully")
        } catch {
            PromptVizLog.error(error, context: "Capture failed")
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
            try LaunchAtLogin.setEnabled(enabled)
            launchesAtLogin = LaunchAtLogin.isEnabled
            PromptVizLog.info("Launch at login changed to \(launchesAtLogin)")
        } catch {
            PromptVizLog.error(error, context: "Could not update launch at login")
            launchesAtLogin = LaunchAtLogin.isEnabled
            errorMessage = "Could not update the launch-at-login setting.\n\n\(error.localizedDescription)"
        }
    }

    func setOpenComposerShortcut(_ shortcut: GlobalShortcut) {
        openComposerShortcut = shortcut
        GlobalShortcutPersistence.save(shortcut)
        PromptVizLog.info("Open Composer shortcut changed to \(shortcut.displayName)")
    }

    func insert(_ snippet: Snippet) {
        insertionRequest = TextInsertionRequest(text: snippet.body)
        PromptVizLog.info("Template inserted")
    }

    func registerImageAttachment(_ data: Data, number: Int) {
        guard !data.isEmpty else { return }
        editorImageAttachments.removeAll { $0.number == number }
        editorImageAttachments.append(PromptImageAttachment(number: number, data: data))
        saveCurrentDraft()
        PromptVizLog.info("Image attachment added")
    }

    func requestImagePaste() {
        imagePasteRequest = UUID()
        editorFocusRequest = UUID()
        PromptVizLog.info("Image paste requested from app command")
    }

    func loadHistoryEntry(_ entry: PromptHistoryEntry) {
        saveCurrentDraft()
        setEditorText(entry.prompt)
        editorImageAttachments = entry.imageAttachments
        editorCursorLocationRequest = (entry.prompt as NSString).length
        editorFocusRequest = UUID()
        sync(reconcileWindows: false)
        PromptVizLog.info("Prompt history entry loaded")
    }

    func removeHistoryEntry(_ entry: PromptHistoryEntry) {
        promptHistory.remove(id: entry.id)
        promptHistoryPersistence.save(promptHistory.entries)
        sync(reconcileWindows: false)
        PromptVizLog.info("Prompt history entry deleted")
    }

    func clearHistory() {
        promptHistory.removeAll()
        promptHistoryPersistence.save(promptHistory.entries)
        sync(reconcileWindows: false)
        PromptVizLog.info("Prompt history cleared")
    }

    func selectSkill(_ skill: SkillDescriptor) {
        let invocation = "$" + skill.name + " "
        let expression = #"\$[A-Za-z0-9_-]*$"#

        if let range = editorText.range(of: expression, options: .regularExpression) {
            let tokenRange = NSRange(range, in: editorText)
            var updatedText = latestEditorText
            updatedText.replaceSubrange(range, with: invocation)
            setEditorText(updatedText)
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
            PromptVizLog.info("Sending prompt with \(editorImageAttachments.count) image attachment(s)")
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
            openMainWindow()
            PromptVizLog.info("Prompt sent successfully")
        } catch {
            PromptVizLog.error(error, context: "Could not send prompt")
            errorMessage = error.localizedDescription
            shouldOfferAccessibilitySettings = (error as? TerminalAutomationError)?.isAccessibilityNotTrusted == true
            shouldOfferAutomationSettings = (error as? TerminalAutomationError)?.isAutomationNotTrusted == true
        }
    }

    func addSnippet(title: String, body: String, favorite: Bool) {
        guard snippetLibrary.add(Snippet(title: title, body: body, isFavorite: favorite)) else {
            PromptVizLog.info("Template creation rejected because the 9-template limit was reached")
            errorMessage = "Prompt Viz supports up to 9 templates because there are only 9 shortcut slots."
            return
        }
        snippetPersistence.save(snippetLibrary.snippets)
        sync()
        PromptVizLog.info("Template created")
    }

    func updateSnippet(_ snippet: Snippet) {
        snippetLibrary.update(snippet)
        snippetPersistence.save(snippetLibrary.snippets)
        sync()
        PromptVizLog.info("Template updated")
    }

    func removeSnippet(_ snippet: Snippet) {
        snippetLibrary.remove(id: snippet.id)
        snippetPersistence.save(snippetLibrary.snippets)
        sync()
        PromptVizLog.info("Template deleted")
    }

    func moveSnippet(_ snippet: Snippet, toShortcutNumber shortcutNumber: Int) {
        snippetLibrary.moveSnippet(snippet.id, toShortcutNumber: shortcutNumber)
        snippetPersistence.save(snippetLibrary.snippets)
        sync()
        PromptVizLog.info("Template moved to shortcut slot \(shortcutNumber)")
    }

    func openMainWindow() {
        isMainWindowVisible = true
        NSApp.activate(ignoringOtherApps: true)
        openMainWindowHandler?()
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

    private func setEditorText(_ text: String) {
        editorTextPublicationTimer?.invalidate()
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

        Task { @MainActor [weak self] in
            let discoveredSkills = await Task.detached(priority: .utility) {
                SkillCatalog().scan()
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

@main
struct PromptVizApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = PromptVizModel.shared

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    NotificationCenter.default.post(name: .promptVizOpenSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindowController: MainWindowController?
    private var keyboardMonitor: Any?
    private var workspaceSwitchMonitor: Any?
    private var imagePasteMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        PromptVizLog.info("Application did finish launching")
        let model = PromptVizModel.shared
        mainWindowController = MainWindowController(model: model)
        model.openMainWindowHandler = { [weak self] in
            self?.mainWindowController?.show()
        }
        model.workspacesDidChangeHandler = { [weak self] in
            self?.mainWindowController?.reconcileWindows()
        }

        keyboardMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            guard model.openComposerShortcut.matches(event) else { return }
            PromptVizLog.info("Open Composer shortcut pressed")
            model.captureActiveTerminalSession()
        }

        workspaceSwitchMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags

            if event.keyCode == 43,
               modifiers.contains(.command),
               !modifiers.contains(.option),
               !modifiers.contains(.control),
               !modifiers.contains(.shift) {
                NotificationCenter.default.post(name: .promptVizOpenSettings, object: nil)
                return nil
            }

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

        imagePasteMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.contains(.option) {
                PromptVizLog.info(
                    "Option key event: keyCode=\(event.keyCode), characters=\(event.characters ?? "none"), ignoringModifiers=\(event.charactersIgnoringModifiers ?? "none")"
                )
            }

            guard isImagePasteShortcut(event) else { return event }

            guard let textView = NSApp.keyWindow?.firstResponder as? PromptTextView else {
                PromptVizLog.info("Image shortcut ignored because the editor is not focused")
                return event
            }

            PromptVizLog.info("Image shortcut received by app monitor")
            return textView.onImagePaste?() == true ? nil : event
        }

    }

    func applicationWillTerminate(_ notification: Notification) {
        if let keyboardMonitor {
            NSEvent.removeMonitor(keyboardMonitor)
        }
        if let workspaceSwitchMonitor {
            NSEvent.removeMonitor(workspaceSwitchMonitor)
        }
        if let imagePasteMonitor {
            NSEvent.removeMonitor(imagePasteMonitor)
        }
    }
}

@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    private let model: PromptVizModel
    private var windowsByWorkspaceID: [UUID: NSWindow] = [:]
    private var isReconciling = false

    init(model: PromptVizModel) {
        self.model = model
        super.init()
    }

    func reconcileWindows() {
        isReconciling = true
        defer { isReconciling = false }

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
        model.finishTerminalSessionCapture()
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
            !isReconciling,
            !model.isCapturingTerminalSession,
            let window = notification.object as? NSWindow,
            window.isKeyWindow,
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

enum SnippetEditorPresentation: Identifiable {
    case new
    case edit(Snippet)

    var id: String {
        switch self {
        case .new:
            return "new"
        case .edit(let snippet):
            return snippet.id.uuidString
        }
    }
}

@MainActor
struct ContentView: View {
    @ObservedObject var model: PromptVizModel
    @State private var snippetEditorPresentation: SnippetEditorPresentation?
    @State private var showingSettings = false
    @State private var historySearch = ""
    @State private var showingHistoryClearConfirmation = false

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

    var body: some View {
        composer
        .sheet(item: $snippetEditorPresentation) { presentation in
            switch presentation {
            case .new:
                snippetEditorSheet(for: nil)
            case .edit(let snippet):
                snippetEditorSheet(for: snippet)
            }
        }
        .sheet(isPresented: $showingSettings) {
            AppSettingsView(model: model)
        }
        .alert("Prompt Viz", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            if model.shouldOfferAutomationSettings {
                    Button("Open Automation") {
                    model.terminalAutomation.openAutomationSettings()
                    model.errorMessage = nil
                }
            } else if model.shouldOfferAccessibilitySettings {
                    Button("Open Accessibility") {
                    model.terminalAutomation.openAccessibilitySettings()
                    model.errorMessage = nil
                }
            }
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .onReceive(NotificationCenter.default.publisher(for: .promptVizOpenSettings)) { _ in
            showingSettings = true
        }
    }

    @ViewBuilder
    private func snippetEditorSheet(for snippet: Snippet?) -> some View {
        SnippetEditorSheet(
            snippet: snippet,
            onDelete: snippet.map { snippet in
                { model.removeSnippet(snippet) }
            }
        ) { title, body, favorite in
            if var snippet {
                snippet.title = title
                snippet.body = body
                snippet.isFavorite = favorite
                model.updateSnippet(snippet)
            } else {
                model.addSnippet(
                    title: title,
                    body: body,
                    favorite: favorite
                )
            }
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

                    Button {
                        model.requestImagePaste()
                    } label: {
                        Image(systemName: "photo")
                    }
                    .keyboardShortcut("v", modifiers: [.option])
                    .help("Paste image (⌥V)")

                    Button("Send") {
                        model.send()
                    }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .buttonStyle(.borderedProminent)
                    .disabled(model.editorText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(18)

                Divider()

                PromptEditorArea(model: model)
                .padding(12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var snippetSidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Templates")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button {
                            snippetEditorPresentation = .new
                        } label: {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.borderless)
                        .help("New snippet")
                    }

                    ForEach(Array(model.snippetLibrary.snippets.prefix(9).enumerated()), id: \.element.id) { index, snippet in
                        shortcutSlot(snippet, shortcutNumber: index + 1)
                    }

                    if !model.snippetLibrary.favorites.isEmpty {
                        Divider()

                        Text("Favorites")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        ForEach(model.snippetLibrary.favorites.prefix(9)) { snippet in
                            Button {
                                model.insert(snippet)
                            } label: {
                                Label(snippet.title, systemImage: "star.fill")
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    Divider()

                    HStack {
                        Text("History")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Spacer()

                        if !model.history.isEmpty {
                            Button {
                                showingHistoryClearConfirmation = true
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Clear history")
                        }
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search history", text: $historySearch)
                            .textFieldStyle(.plain)
                    }
                    .padding(7)
                    .background(.background, in: RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.quaternary)
                    }

                    if visibleHistory.isEmpty {
                        Text(model.history.isEmpty ? "Sent prompts appear here." : "No matching prompts.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(visibleHistory) { entry in
                            historyRow(entry)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)

            HStack {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("Settings")

                Spacer()
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
        .alert("Clear prompt history?", isPresented: $showingHistoryClearConfirmation) {
            Button("Clear", role: .destructive) {
                model.clearHistory()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This cannot be undone.")
        }
    }

    private var visibleHistory: [PromptHistoryEntry] {
        model.promptHistory.search(historySearch)
    }

    private func historyRow(_ entry: PromptHistoryEntry) -> some View {
        HStack(alignment: .top, spacing: 5) {
            Button {
                model.loadHistoryEntry(entry)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(historyPreview(entry.prompt))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 4) {
                        Text(entry.sessionTitle)
                            .lineLimit(1)
                        Text("·")
                        TimelineView(.periodic(from: Date(), by: 30)) { context in
                            Text(PromptHistoryTime.label(
                                for: entry.sentAt,
                                relativeTo: context.date
                            ))
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Load prompt into editor")

            Button {
                model.removeHistoryEntry(entry)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Delete history entry")
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .background(.background.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
    }

    private func historyPreview(_ prompt: String) -> String {
        prompt
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func shortcutSlot(_ snippet: Snippet, shortcutNumber: Int) -> some View {
        templateSlot(snippet, shortcutNumber: shortcutNumber)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onDrop(of: [UTType.text], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }

            provider.loadDataRepresentation(forTypeIdentifier: UTType.text.identifier) { data, _ in
                guard
                    let data,
                    let string = String(data: data, encoding: .utf8),
                    let snippetID = UUID(uuidString: string)
                else { return }

                Task { @MainActor in
                    guard let snippet = model.snippetLibrary.snippets.first(where: { $0.id == snippetID }) else {
                        return
                    }
                    model.moveSnippet(snippet, toShortcutNumber: shortcutNumber)
                }
            }
            return true
        }
    }

    private func templateSlot(_ snippet: Snippet, shortcutNumber: Int) -> some View {
        HStack(spacing: 4) {
            Button {
                model.insert(snippet)
            } label: {
                HStack(spacing: 0) {
                    Text("⌘\(shortcutNumber)")
                        .font(.caption.monospaced().weight(.semibold))
                        .frame(width: 34, alignment: .leading)

                    Text(snippet.title)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .keyboardShortcut(
                KeyEquivalent(Character(String(shortcutNumber))),
                modifiers: [.command]
            )

            Button {
                snippetEditorPresentation = .edit(snippet)
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .padding(.vertical, 6)
            .help("Edit snippet")

        }
        .draggable(snippet.id.uuidString)
    }

}

struct AppSettingsView: View {
    @ObservedObject var model: PromptVizModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.title2.weight(.semibold))

            Toggle("Launch Prompt Viz at login", isOn: Binding(
                get: { model.launchesAtLogin },
                set: { model.setLaunchAtLogin($0) }
            ))

            HStack {
                Text("Open Composer shortcut")

                Spacer()

                ShortcutRecorderView(shortcut: Binding(
                    get: { model.openComposerShortcut },
                    set: { model.setOpenComposerShortcut($0) }
                ))

                Button {
                    model.setOpenComposerShortcut(.defaultShortcut)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .help("Reset shortcut")
            }

            Text("Prompt Viz will run in the background and remain available through the \(model.openComposerShortcut.displayName) shortcut.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 430)
    }
}

struct ShortcutRecorderView: NSViewRepresentable {
    @Binding var shortcut: GlobalShortcut

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> ShortcutRecorderNSView {
        let view = ShortcutRecorderNSView(shortcut: shortcut)
        view.onShortcutChanged = { newShortcut in
            context.coordinator.parent.shortcut = newShortcut
        }
        return view
    }

    func updateNSView(_ nsView: ShortcutRecorderNSView, context: Context) {
        nsView.shortcut = shortcut
        nsView.needsDisplay = true
    }

    final class Coordinator {
        var parent: ShortcutRecorderView

        init(_ parent: ShortcutRecorderView) {
            self.parent = parent
        }
    }
}

final class ShortcutRecorderNSView: NSView {
    var shortcut: GlobalShortcut
    var onShortcutChanged: ((GlobalShortcut) -> Void)?
    private var isRecording = false

    init(shortcut: GlobalShortcut) {
        self.shortcut = shortcut
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        isRecording = true
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        needsDisplay = true
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            isRecording = false
            needsDisplay = true
            return
        }

        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !modifiers.isEmpty else {
            NSSound.beep()
            return
        }

        shortcut = GlobalShortcut(keyCode: event.keyCode, modifierFlags: modifiers.rawValue)
        onShortcutChanged?(shortcut)
        isRecording = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let bounds = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6)
        (isRecording ? NSColor.controlAccentColor : NSColor.controlBackgroundColor).setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.stroke()

        let title = isRecording ? "Press shortcut…" : shortcut.displayName
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: isRecording ? NSColor.white : NSColor.labelColor,
            .paragraphStyle: paragraphStyle
        ]
        (title as NSString).draw(
            in: bounds.insetBy(dx: 6, dy: 5),
            withAttributes: attributes
        )
    }
}

@MainActor
struct PromptEditorArea: View {
    @ObservedObject var model: PromptVizModel
    @State private var text = ""
    @State private var hoveredSkillID: String?
    @State private var selectedSkillIndex = -1

    private var activeSkillQuery: String? {
        guard let range = text.range(
            of: #"\$[A-Za-z0-9_-]*$"#,
            options: .regularExpression
        ) else { return nil }

        return String(text[range].dropFirst())
    }

    private var visibleSkills: [SkillDescriptor] {
        model.skillCatalog.search(activeSkillQuery ?? "", in: model.skills)
            .prefix(6)
            .map { $0 }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            PromptTextEditor(
                text: Binding(
                    get: { text },
                    set: {
                        text = $0
                        model.updateEditorText($0)
                    }
                ),
                insertionRequest: $model.insertionRequest,
                cursorLocationRequest: $model.editorCursorLocationRequest,
                focusRequest: $model.editorFocusRequest,
                imagePasteRequest: $model.imagePasteRequest,
                skillHighlightRequest: $model.skillHighlightRequest,
                onSkillKeyboardAction: handleSkillKeyboardAction,
                onImagePaste: { data, number in
                    model.registerImageAttachment(data, number: number)
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if activeSkillQuery != nil && !visibleSkills.isEmpty {
                skillSuggestions
                    .padding(.top, 58)
                    .padding(.leading, 14)
            }
        }
        .onAppear {
            text = model.editorText
        }
        .onChange(of: model.editorText) { newText in
            if text != newText {
                text = newText
            }
        }
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
            model.selectSkill(visibleSkills[index])
            selectedSkillIndex = -1
        }

        return true
    }
}

final class PromptTextView: NSTextView {
    var onImagePaste: (() -> Bool)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isImagePasteShortcut(event) else {
            return super.performKeyEquivalent(with: event)
        }

        PromptVizLog.info("Image shortcut received through key equivalent")
        if onImagePaste?() == true {
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if isImagePasteShortcut(event) {
            PromptVizLog.info("Image shortcut received through key down")
            if onImagePaste?() == true {
                return
            }
        }

        super.keyDown(with: event)
    }
}

struct PromptTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var insertionRequest: TextInsertionRequest?
    @Binding var cursorLocationRequest: Int?
    @Binding var focusRequest: UUID?
    @Binding var imagePasteRequest: UUID?
    @Binding var skillHighlightRequest: SkillHighlightRequest?
    let onSkillKeyboardAction: (SkillKeyboardAction) -> Bool
    let onImagePaste: (Data, Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            onSkillKeyboardAction: onSkillKeyboardAction,
            onImagePaste: onImagePaste
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = PromptTextView()
        textView.delegate = context.coordinator
        textView.onImagePaste = { [weak textView, weak coordinator = context.coordinator] in
            guard let textView else { return false }
            return coordinator?.handleImagePaste(in: textView) ?? false
        }
        textView.isRichText = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.font = .systemFont(ofSize: 15)
        textView.textContainerInset = NSSize(width: 10, height: 12)
        textView.drawsBackground = false
        Self.applyInlineTokenStyles(to: textView)

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
        context.coordinator.onImagePaste = onImagePaste

        if textView.string != text {
            let location = min(textView.selectedRange().location, text.utf16.count)
            context.coordinator.isApplyingModelText = true
            textView.string = text
            textView.setSelectedRange(NSRange(location: location, length: 0))
            context.coordinator.isApplyingModelText = false
        }

        Self.applyInlineTokenStyles(to: textView)

        if let cursorLocationRequest {
            let location = min(max(0, cursorLocationRequest), (textView.string as NSString).length)
            textView.setSelectedRange(NSRange(location: location, length: 0))
            DispatchQueue.main.async {
                guard self.cursorLocationRequest == cursorLocationRequest else { return }
                self.cursorLocationRequest = nil
            }
        }

        if let focusRequest,
           context.coordinator.lastFocusRequestID != focusRequest {
            context.coordinator.lastFocusRequestID = focusRequest
            textView.window?.makeFirstResponder(textView)
            let requestID = focusRequest
            DispatchQueue.main.async {
                guard self.focusRequest == requestID else { return }
                textView.window?.makeFirstResponder(textView)
                self.focusRequest = nil
            }
        }

        if let imagePasteRequest,
           context.coordinator.lastImagePasteRequest != imagePasteRequest {
            context.coordinator.lastImagePasteRequest = imagePasteRequest
            _ = context.coordinator.handleImagePaste(in: textView)
            let requestID = imagePasteRequest
            DispatchQueue.main.async {
                guard self.imagePasteRequest == requestID else { return }
                self.imagePasteRequest = nil
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
        context.coordinator.isApplyingModelText = true
        textView.string = updated
        textView.setSelectedRange(NSRange(location: selection.location + insertionRequest.text.utf16.count, length: 0))
        context.coordinator.isApplyingModelText = false
        Self.applyInlineTokenStyles(to: textView)
        let requestID = insertionRequest.id
        DispatchQueue.main.async {
            guard self.insertionRequest?.id == requestID else { return }
            self.text = updated
            self.insertionRequest = nil
            context.coordinator.lastInsertionID = nil
        }
    }

    static func applyInlineTokenStyles(to textView: NSTextView) {
        guard let textStorage = textView.textStorage else { return }

        let fullRange = NSRange(location: 0, length: textStorage.length)
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15),
            .foregroundColor: NSColor.labelColor
        ]

        textStorage.beginEditing()
        if fullRange.length > 0 {
            textStorage.setAttributes(baseAttributes, range: fullRange)
        }

        let tokenAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: NSColor.controlAccentColor
        ]
        for token in PromptEditorTokens.tokens(in: textView.string) {
            textStorage.addAttributes(tokenAttributes, range: token.range)
        }
        textStorage.endEditing()
        textView.typingAttributes = baseAttributes
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        var lastInsertionID: UUID?
        var lastFocusRequestID: UUID?
        var lastImagePasteRequest: UUID?
        var lastSkillHighlightID: UUID?
        var isApplyingModelText = false
        var onSkillKeyboardAction: (SkillKeyboardAction) -> Bool
        var onImagePaste: (Data, Int) -> Void

        init(
            text: Binding<String>,
            onSkillKeyboardAction: @escaping (SkillKeyboardAction) -> Bool,
            onImagePaste: @escaping (Data, Int) -> Void
        ) {
            _text = text
            self.onSkillKeyboardAction = onSkillKeyboardAction
            self.onImagePaste = onImagePaste
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            guard !isApplyingModelText else { return }
            text = textView.string
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            if let tokenRange = PromptEditorTokens.editingRange(
                for: affectedCharRange,
                in: textView.string
            ), tokenRange != affectedCharRange {
                let replacement = replacementString ?? ""
                isApplyingModelText = true
                textView.textStorage?.replaceCharacters(in: tokenRange, with: replacement)
                textView.setSelectedRange(NSRange(
                    location: tokenRange.location + replacement.utf16.count,
                    length: 0
                ))
                isApplyingModelText = false
                text = textView.string
                PromptTextEditor.applyInlineTokenStyles(to: textView)
                PromptVizLog.info("Inline token edit expanded to the whole block")
                return false
            }

            guard
                replacementString != nil,
                let event = NSApp.currentEvent,
                isImagePasteShortcut(event)
            else { return true }

            PromptVizLog.info("Image shortcut received through text replacement")
            return !handleImagePaste(in: textView, selectedRange: affectedCharRange)
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

        @MainActor
        fileprivate func handleImagePaste(
            in textView: NSTextView,
            selectedRange overrideRange: NSRange? = nil
        ) -> Bool {
            let pasteboard = NSPasteboard.general
            let types = pasteboard.types?.map(\.rawValue).joined(separator: ", ") ?? "none"
            PromptVizLog.info("Image pasteboard types: \(types)")

            let imageData: Data
            if let pngData = pasteboard.data(forType: .png), !pngData.isEmpty {
                imageData = pngData
                PromptVizLog.info("Image paste found PNG data")
            } else if let tiffData = pasteboard.data(forType: .tiff),
                      let image = NSImage(data: tiffData),
                      let convertedData = pngData(from: image) {
                imageData = convertedData
                PromptVizLog.info("Image paste converted TIFF data to PNG")
            } else if let image = NSImage(pasteboard: pasteboard),
                      let convertedData = pngData(from: image) {
                imageData = convertedData
                PromptVizLog.info("Image paste converted NSImage data to PNG")
            } else {
                PromptVizLog.info("Image paste found no supported image data")
                return false
            }

            let number = PromptImageReference.nextNumber(in: textView.string)
            let token = "[Image #\(number)]"
            let currentText = textView.string as NSString
            let currentLength = currentText.length
            let selectedRange = overrideRange ?? textView.selectedRange()
            let location = min(max(0, selectedRange.location), currentLength)
            let length = min(max(0, selectedRange.length), currentLength - location)
            let selection = NSRange(location: location, length: length)
            let updated = currentText.replacingCharacters(in: selection, with: token)

            isApplyingModelText = true
            textView.string = updated
            textView.setSelectedRange(NSRange(
                location: selection.location + token.utf16.count,
                length: 0
            ))
            isApplyingModelText = false
            text = updated
            onImagePaste(imageData, number)
            PromptTextEditor.applyInlineTokenStyles(to: textView)
            PromptVizLog.info("Image placeholder inserted: \(token)")
            return true
        }

        private func pngData(from image: NSImage) -> Data? {
            guard
                let tiffData = image.tiffRepresentation,
                let bitmap = NSBitmapImageRep(data: tiffData)
            else { return nil }

            return bitmap.representation(using: .png, properties: [:])
        }
    }
}

struct SnippetEditorSheet: View {
    let snippet: Snippet?
    let onDelete: (() -> Void)?
    let onSave: (String, String, Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var snippetBody: String
    @State private var favorite: Bool

    init(
        snippet: Snippet?,
        onDelete: (() -> Void)? = nil,
        onSave: @escaping (String, String, Bool) -> Void
    ) {
        self.snippet = snippet
        self.onDelete = onDelete
        self.onSave = onSave
        _title = State(initialValue: snippet?.title ?? "")
        _snippetBody = State(initialValue: snippet?.body ?? "")
        _favorite = State(initialValue: snippet?.isFavorite ?? false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(snippet == nil ? "New snippet" : "Edit snippet")
                .font(.title2.weight(.semibold))
            TextField("Name", text: $title)
                .textFieldStyle(.roundedBorder)
            TextEditor(text: $snippetBody)
                .font(.body.monospaced())
                .frame(height: 130)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            Toggle("Show in favorites", isOn: $favorite)
            HStack {
                if let onDelete {
                    Button("Delete", role: .destructive) {
                        onDelete()
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }

                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
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
