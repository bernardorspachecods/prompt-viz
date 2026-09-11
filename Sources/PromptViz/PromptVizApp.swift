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

struct TerminalSession: Equatable, Identifiable {
    let id: String
    let title: String
    let processIdentifier: pid_t
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
            return "O macOS bloqueou o Prompt Viz de controlar o Terminal.app. Autoriza o Prompt Viz a controlar o System Events quando aparecer o pedido."
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
            return fallbackSession(for: application)
        }

        let windowElement = unsafeDowncast(focusedWindow, to: AXUIElement.self)
        let title = attributeString(windowElement, kAXTitleAttribute as CFString) ?? "Terminal"
        let windowIdentifier = windowNumber(for: windowElement, title: title, application: application)
            .map { "window-\($0)" }
            ?? attributeString(windowElement, kAXIdentifierAttribute as CFString)
        let sessionID = "\(application.processIdentifier):\(windowIdentifier ?? title)"

        return TerminalSession(
            id: sessionID,
            title: title,
            processIdentifier: application.processIdentifier
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

    private func fallbackSession(for application: NSRunningApplication) -> TerminalSession {
        TerminalSession(
            id: "\(application.processIdentifier):fallback",
            title: "Terminal.app",
            processIdentifier: application.processIdentifier
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
    @Published var selectedWorkspaceID: UUID?
    @Published var editorText = ""
    @Published var insertionRequest: TextInsertionRequest?
    @Published var templateToFill: Snippet?
    @Published var errorMessage: String?
    @Published var shouldOfferAccessibilitySettings = false
    @Published var shouldOfferAutomationSettings = false
    @Published var isMainWindowVisible = false
    var openMainWindowHandler: (() -> Void)?

    let workspaceStore = WorkspaceStore()
    let snippetLibrary: SnippetLibrary
    let terminalAutomation = TerminalAutomation()
    private let snippetPersistence = LocalSnippetPersistence()
    private var workspaceMonitor: Timer?
    private(set) var activeSession: TerminalSession?

    private init() {
        snippetLibrary = SnippetLibrary(snippets: snippetPersistence.load())
        sync()
        workspaceMonitor = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pruneClosedWorkspaces()
            }
        }
    }

    var selectedWorkspace: Workspace? {
        guard let selectedWorkspaceID else { return nil }
        return workspaceStore.workspace(id: selectedWorkspaceID)
    }

    func captureActiveTerminalSession() {
        shouldOfferAccessibilitySettings = false

        guard terminalAutomation.isTerminalFrontmost else {
            errorMessage = TerminalAutomationError.terminalNotActive.localizedDescription
            openMainWindow()
            return
        }

        do {
            let session = try terminalAutomation.activeSession()
            activeSession = session
            let workspace = workspaceStore.workspace(for: session.id, title: session.title)
            selectedWorkspaceID = workspace.id
            editorText = workspace.draft
            sync()
            openMainWindow()
        } catch {
            errorMessage = error.localizedDescription
            shouldOfferAccessibilitySettings = (error as? TerminalAutomationError)?.isAccessibilityNotTrusted == true
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
            processIdentifier: workspace.terminalSessionID.split(separator: ":").first.flatMap { pid_t($0) } ?? 0
        )
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

    private func sync() {
        workspaces = workspaceStore.workspaces
        snippets = snippetLibrary.snippets
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
        }

        sync()
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
            .keyboardShortcut("p", modifiers: [.command, .option])

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
                .keyboardShortcut("p", modifiers: [.command, .option])
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindowController: MainWindowController?
    private var floatingButton: FloatingButtonController?
    private var keyboardMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = PromptVizModel.shared
        mainWindowController = MainWindowController(model: model)
        model.openMainWindowHandler = { [weak self] in
            self?.mainWindowController?.show()
        }
        floatingButton = FloatingButtonController(model: model)
        floatingButton?.start()

        keyboardMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            guard
                event.keyCode == 35,
                event.modifierFlags.contains([.command, .option])
            else { return }
            model.captureActiveTerminalSession()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let keyboardMonitor {
            NSEvent.removeMonitor(keyboardMonitor)
        }
    }
}

@MainActor
final class MainWindowController {
    private let window: NSWindow

    init(model: PromptVizModel) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Prompt Viz · \(PromptVizBuild.label)"
        window.minSize = NSSize(width: 760, height: 500)
        window.contentView = NSHostingView(
            rootView: ContentView(model: model)
                .frame(minWidth: 760, minHeight: 500)
        )
        window.center()
        window.isReleasedWhenClosed = false
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
final class FloatingButtonController {
    private let model: PromptVizModel
    private var panel: NSPanel?
    private var observer: NSObjectProtocol?
    private var refreshTimer: Timer?

    init(model: PromptVizModel) {
        self.model = model
    }

    func start() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
        refresh()
    }

    private func refresh() {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.Terminal" else {
            panel?.orderOut(nil)
            return
        }

        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 44, height: 44),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = .floating
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.contentView = NSHostingView(rootView: FloatingButton(model: model))
            self.panel = panel
        }

        guard let windowFrame = model.terminalAutomation.activeTerminalWindowFrame() else {
            panel?.orderOut(nil)
            return
        }

        let buttonSize: CGFloat = 44
        let horizontalInset: CGFloat = 12
        let verticalInset: CGFloat = 16
        panel?.setFrameOrigin(NSPoint(
            x: windowFrame.maxX - buttonSize - horizontalInset,
            y: windowFrame.minY + verticalInset
        ))
        panel?.orderFrontRegardless()
    }
}

struct FloatingButton: View {
    @ObservedObject var model: PromptVizModel

    var body: some View {
        Button {
            model.captureActiveTerminalSession()
        } label: {
            Image(systemName: "text.bubble.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.blue.gradient, in: Circle())
        }
        .buttonStyle(.plain)
        .help("Abrir Prompt Viz")
    }
}

struct ContentView: View {
    @ObservedObject var model: PromptVizModel
    @State private var snippetSearch = ""
    @State private var showingSnippetEditor = false
    @State private var editingSnippet: Snippet?

    private var visibleSnippets: [Snippet] {
        model.snippetLibrary.search(snippetSearch)
    }

    var body: some View {
        HStack(spacing: 0) {
            workspaceSidebar
            Divider()
            composer
        }
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

    private var workspaceSidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Workspaces", systemImage: "rectangle.split.3x1")
                .font(.headline)
                .padding(.horizontal, 14)

            if model.workspaces.isEmpty {
                Text("Abre um tab do Terminal.app e usa o botão flutuante.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
            } else {
                List(model.workspaces) { workspace in
                    Button {
                        model.select(workspace)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(workspace.title)
                                .lineLimit(1)
                            Text(workspace.draft.isEmpty ? "Sem rascunho" : workspace.draft)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(
                        model.selectedWorkspaceID == workspace.id ? Color.accentColor.opacity(0.14) : .clear
                    )
                }
                .listStyle(.sidebar)
            }

            Spacer()
        }
        .frame(width: 230)
        .padding(.top, 16)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.selectedWorkspace?.title ?? "Prompt Viz")
                        .font(.title2.weight(.semibold))
                    Text(model.selectedWorkspace == nil ? "Nenhum tab selecionado" : "Prompt local")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

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

            PromptTextEditor(text: $model.editorText, insertionRequest: $model.insertionRequest)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(12)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Snippets")
                        .font(.headline)
                    Spacer()
                    Button {
                        editingSnippet = nil
                        showingSnippetEditor = true
                    } label: {
                        Label("Novo", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                }

                HStack {
                    ForEach(Array(model.snippetLibrary.favorites.prefix(9).enumerated()), id: \.element.id) { index, snippet in
                        Button(snippet.title) { model.insert(snippet) }
                            .buttonStyle(.bordered)
                            .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: [.command, .option])
                    }
                    Spacer()
                    TextField("Pesquisar snippets", text: $snippetSearch)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 190)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(visibleSnippets) { snippet in
                            HStack(spacing: 4) {
                                Button(snippet.title) { model.insert(snippet) }
                                    .buttonStyle(.borderless)
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
                            .padding(.vertical, 5)
                            .background(.quaternary, in: Capsule())
                        }
                    }
                }
            }
            .padding(14)
        }
    }
}

struct PromptTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var insertionRequest: TextInsertionRequest?

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
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

        if textView.string != text {
            let location = min(textView.selectedRange().location, text.utf16.count)
            textView.string = text
            textView.setSelectedRange(NSRange(location: location, length: 0))
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

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
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
