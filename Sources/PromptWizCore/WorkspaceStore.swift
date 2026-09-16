import Foundation

public final class WorkspaceStore {
    public private(set) var workspaces: [Workspace] = []
    private let now: () -> Date
    private var missingSessionObservations: [String: Int] = [:]

    public init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    @discardableResult
    public func workspace(
        for terminalSessionID: String,
        title: String,
        terminalTTY: String? = nil,
        terminalProcessIdentifier: Int32 = 0
    ) -> Workspace {
        if let index = workspaces.firstIndex(where: { $0.terminalSessionID == terminalSessionID }) {
            workspaces[index].title = title
            if terminalProcessIdentifier != 0 {
                workspaces[index].terminalProcessIdentifier = terminalProcessIdentifier
            }
            if let terminalTTY {
                workspaces[index].terminalTTY = terminalTTY
            }
            return workspaces[index]
        }

        let workspace = Workspace(
            terminalSessionID: terminalSessionID,
            terminalProcessIdentifier: terminalProcessIdentifier,
            terminalTTY: terminalTTY,
            title: title,
            createdAt: now()
        )
        workspaces.append(workspace)
        return workspace
    }

    public func workspace(id: UUID) -> Workspace? {
        workspaces.first(where: { $0.id == id })
    }

    public func updateDraft(
        _ draft: String,
        imageAttachments: [PromptImageAttachment] = [],
        for workspaceID: UUID
    ) {
        guard let index = workspaces.firstIndex(where: { $0.id == workspaceID }) else { return }
        workspaces[index].draft = draft
        workspaces[index].imageAttachments = imageAttachments
        workspaces[index].updatedAt = now()
    }

    public func removeClosedWorkspaces(using inventory: TerminalSessionInventory) {
        // Terminal can briefly expose an empty or partial snapshot while a tab
        // is being selected. Such a snapshot is never evidence of closure.
        guard inventory.isComplete, !inventory.sessionIDs.isEmpty else { return }

        let liveSessionIDs = inventory.sessionIDs
        for workspace in workspaces {
            let sessionID = workspace.terminalSessionID
            if liveSessionIDs.contains(sessionID) {
                missingSessionObservations.removeValue(forKey: sessionID)
            } else {
                missingSessionObservations[sessionID, default: 0] += 1
            }
        }

        let closedSessionIDs = Set(
            missingSessionObservations
                .filter { $0.value >= 2 }
                .map(\.key)
        )
        guard !closedSessionIDs.isEmpty else { return }

        workspaces.removeAll { closedSessionIDs.contains($0.terminalSessionID) }
        for sessionID in closedSessionIDs {
            missingSessionObservations.removeValue(forKey: sessionID)
        }
    }

    public func removeWorkspace(id: UUID) {
        guard let workspace = workspaces.first(where: { $0.id == id }) else { return }
        missingSessionObservations.removeValue(forKey: workspace.terminalSessionID)
        workspaces.removeAll { $0.id == id }
    }
}
