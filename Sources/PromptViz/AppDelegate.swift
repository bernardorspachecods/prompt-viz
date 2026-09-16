import AppKit
import Foundation

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
