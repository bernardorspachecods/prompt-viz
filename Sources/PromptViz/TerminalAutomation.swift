import ApplicationServices
import AppKit
import CoreGraphics
import Foundation
import PromptVizCore

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
