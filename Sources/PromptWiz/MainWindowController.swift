import AppKit
import Foundation
import PromptWizCore
import SwiftUI

@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    private let model: PromptWizModel
    private var windowsByWorkspaceID: [UUID: NSWindow] = [:]
    private var emptyStateWindow: NSWindow?
    private var isReconciling = false

    init(model: PromptWizModel) {
        self.model = model
        super.init()
    }

    func reconcileWindows() {
        isReconciling = true
        defer { isReconciling = false }

        let workspaceIDs = Set(model.workspaces.map(\.id))

        if workspaceIDs.isEmpty {
            if emptyStateWindow == nil {
                emptyStateWindow = createWindow(title: "Prompt Wiz")
                emptyStateWindow?.center()
            }
            return
        }

        if let emptyStateWindow {
            emptyStateWindow.delegate = nil
            emptyStateWindow.close()
            self.emptyStateWindow = nil
        }

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
        else {
            if emptyStateWindow?.isMiniaturized == true {
                emptyStateWindow?.deminiaturize(nil)
            }
            emptyStateWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            model.finishTerminalSessionCapture()
            return
        }

        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        model.finishTerminalSessionCapture()
    }

    func minimize() {
        NSApp.hide(nil)
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
        guard let window = notification.object as? NSWindow else { return }

        if window === emptyStateWindow {
            emptyStateWindow = nil
            return
        }

        guard let workspaceID = workspaceID(for: window) else { return }

        windowsByWorkspaceID.removeValue(forKey: workspaceID)
        model.closeWorkspace(id: workspaceID)
    }

    private func createWindow(for workspace: Workspace) {
        let window = createWindow(title: tabTitle(for: workspace.title))
        windowsByWorkspaceID[workspace.id] = window

        if let existingWindow = windowsByWorkspaceID.values.first(where: { $0 !== window }) {
            existingWindow.addTabbedWindow(window, ordered: .above)
        } else {
            window.center()
        }
    }

    private func createWindow(title: String) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.tabbingIdentifier = "com.promptwiz.workspace"
        window.tabbingMode = .preferred
        window.minSize = NSSize(width: 760, height: 500)
        window.contentView = NSHostingView(
            rootView: ContentView(model: model)
                .frame(minWidth: 760, minHeight: 500)
        )
        window.delegate = self
        window.isReleasedWhenClosed = false
        return window
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
