import AppKit
import Foundation
import PromptWizCore

protocol TerminalAutomationProviding: AnyObject, Sendable {
    var isTerminalFrontmost: Bool { get }

    func openAccessibilitySettings()
    func openAutomationSettings()
    func activeSession() throws -> TerminalSession
    func activeCodexDraft() throws -> String
    func liveSessionInventory() -> TerminalSessionInventory?
    func pasteCodexInput(
        _ buffer: String,
        imageAttachments: [PromptImageAttachment],
        to expectedSession: TerminalSession
    ) throws
    func sendCodexInputAndReturn(
        _ buffer: String,
        imageAttachments: [PromptImageAttachment],
        to expectedSession: TerminalSession
    ) throws
    func requestTabSelection(tty: String)
}

extension TerminalAutomation: TerminalAutomationProviding { }

protocol SnippetPersistenceProviding {
    func load() -> [Snippet]?
    func save(_ snippets: [Snippet])
}

extension LocalSnippetPersistence: SnippetPersistenceProviding { }

protocol PromptHistoryPersistenceProviding {
    func load() -> [PromptHistoryEntry]
    func save(_ entries: [PromptHistoryEntry])
}

extension LocalPromptHistoryPersistence: PromptHistoryPersistenceProviding { }

protocol SkillCatalogProviding: Sendable {
    func scan() -> [SkillDescriptor]
    func search(_ query: String, in skills: [SkillDescriptor]) -> [SkillDescriptor]
}

extension SkillCatalog: @unchecked Sendable, SkillCatalogProviding { }

protocol ClipboardProviding {
    func pngData() -> Data?
}

struct SystemClipboard: ClipboardProviding {
    func pngData() -> Data? {
        ClipboardImageReader.pngData(from: .general)
    }
}

protocol LaunchAtLoginProviding {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

struct SystemLaunchAtLogin: LaunchAtLoginProviding {
    var isEnabled: Bool { LaunchAtLogin.isEnabled }

    func setEnabled(_ enabled: Bool) throws {
        try LaunchAtLogin.setEnabled(enabled)
    }
}

protocol GlobalShortcutPersistenceProviding {
    func load() -> GlobalShortcut
    func save(_ shortcut: GlobalShortcut)
}

struct UserDefaultsGlobalShortcutPersistence: GlobalShortcutPersistenceProviding {
    func load() -> GlobalShortcut {
        GlobalShortcutPersistence.load()
    }

    func save(_ shortcut: GlobalShortcut) {
        GlobalShortcutPersistence.save(shortcut)
    }
}

protocol SendBehaviorPersistenceProviding {
    func loadHideAfterSend() -> Bool
    func saveHideAfterSend(_ enabled: Bool)
}

extension UserDefaultsSendBehaviorPersistence: SendBehaviorPersistenceProviding { }
