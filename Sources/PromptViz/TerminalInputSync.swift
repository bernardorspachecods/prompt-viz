import Foundation
import AppKit

struct TerminalInputSync {
    static let directoryURL = URL(fileURLWithPath: "/tmp/prompt-viz", isDirectory: true)

    static func stateURL(for tty: String) -> URL {
        directoryURL.appendingPathComponent(URL(fileURLWithPath: tty).lastPathComponent + ".state")
    }
}

@MainActor
final class TerminalInputSyncController {
    private let directoryURL: URL
    private var pollTimer: Timer?
    private var selectedTTY: String?
    private var lastBuffer: String?

    var onBufferChanged: ((String) -> Void)?

    init(directoryURL: URL = TerminalInputSync.directoryURL) {
        self.directoryURL = directoryURL
    }

    func start() {
        try? FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.poll()
            }
        }
    }

    func select(tty: String?) {
        selectedTTY = tty
        lastBuffer = nil
        poll()
    }

    private func poll() {
        guard
            let selectedTTY,
            let payload = try? String(contentsOf: TerminalInputSync.stateURL(for: selectedTTY), encoding: .utf8)
        else { return }

        let fields = payload.split(separator: "\n", omittingEmptySubsequences: false).reduce(
            into: [String: String]()
        ) { fields, line in
            guard let separator = line.firstIndex(of: "=") else { return }
            let key = String(line[..<separator])
            let value = String(line.dropFirst(key.count + 1))
            fields[key] = value
        }

        guard
            fields["tty"] == selectedTTY,
            let encodedBuffer = fields["buffer"],
            let bufferData = Data(base64Encoded: encodedBuffer),
            let buffer = String(data: bufferData, encoding: .utf8)
        else { return }

        guard buffer != lastBuffer else { return }
        lastBuffer = buffer
        onBufferChanged?(buffer)
    }
}

struct TerminalKeyEvent: Sendable {
    let keyCode: UInt16
    let characters: String
    let modifierRawValue: UInt
    let pasteboardText: String?
}

@MainActor
final class TerminalKeyMirror {
    private(set) var buffer = ""
    private var cursor = 0
    private var currentTTY: String?
    private var buffersByTTY: [String: String] = [:]
    private var cursorsByTTY: [String: Int] = [:]

    var onBufferChanged: ((String) -> Void)?

    func reset(buffer: String) {
        self.buffer = buffer
        cursor = buffer.count
        persistCurrentBuffer()
    }

    func reset(buffer: String, for tty: String?) {
        currentTTY = tty
        self.buffer = buffer
        cursor = buffer.count
        persistCurrentBuffer()
    }

    func buffer(for tty: String?) -> String? {
        guard let tty else { return nil }
        return buffersByTTY[tty]
    }

    func handle(_ event: TerminalKeyEvent, for tty: String) {
        select(tty: tty)

        let modifiers = NSEvent.ModifierFlags(rawValue: event.modifierRawValue)
        let hasCommand = modifiers.contains(.command)
        let hasControl = modifiers.contains(.control)

        if hasCommand {
            if event.keyCode == 9, let pasteboardText = event.pasteboardText {
                insert(pasteboardText)
            }
            return
        }

        if hasControl {
            switch event.keyCode {
            case 4: // Ctrl-H / backspace
                deleteBackward()
            case 13, 32: // Ctrl-W / Ctrl-U
                if event.keyCode == 13 {
                    deletePreviousWord()
                } else {
                    reset(buffer: "")
                    publish()
                }
            case 0: // Ctrl-A
                cursor = 0
                publish()
            case 14: // Ctrl-E
                cursor = buffer.count
                publish()
            case 8, 2, 7: // Ctrl-C, Ctrl-D, Ctrl-X
                reset(buffer: "")
                publish()
            default:
                break
            }
            return
        }

        switch event.keyCode {
        case 36, 76: // Return / keypad Enter
            reset(buffer: "")
            publish()
        case 51: // Delete backward
            deleteBackward()
        case 117: // Delete forward
            deleteForward()
        case 123: // Left arrow
            cursor = max(0, cursor - 1)
            publish()
        case 124: // Right arrow
            cursor = min(buffer.count, cursor + 1)
            publish()
        case 115: // Home
            cursor = 0
            publish()
        case 119: // End
            cursor = buffer.count
            publish()
        case 53: // Escape
            reset(buffer: "")
            publish()
        default:
            guard !event.characters.isEmpty else { return }
            insert(event.characters)
        }
    }

    private func insert(_ text: String) {
        let insertionIndex = buffer.index(buffer.startIndex, offsetBy: min(cursor, buffer.count))
        buffer.insert(contentsOf: text, at: insertionIndex)
        cursor += text.count
        publish()
    }

    private func deleteBackward() {
        guard cursor > 0 else { return }
        let end = buffer.index(buffer.startIndex, offsetBy: cursor)
        let start = buffer.index(before: end)
        buffer.removeSubrange(start..<end)
        cursor -= 1
        publish()
    }

    private func deleteForward() {
        guard cursor < buffer.count else { return }
        let start = buffer.index(buffer.startIndex, offsetBy: cursor)
        let end = buffer.index(after: start)
        buffer.removeSubrange(start..<end)
        publish()
    }

    private func deletePreviousWord() {
        while cursor > 0 {
            let end = buffer.index(buffer.startIndex, offsetBy: cursor)
            let start = buffer.index(before: end)
            guard buffer[start].isWhitespace else { break }
            buffer.remove(at: start)
            cursor -= 1
        }

        while cursor > 0 {
            let end = buffer.index(buffer.startIndex, offsetBy: cursor)
            let start = buffer.index(before: end)
            guard !buffer[start].isWhitespace else { break }
            buffer.remove(at: start)
            cursor -= 1
        }

        publish()
    }

    private func publish() {
        persistCurrentBuffer()
        onBufferChanged?(buffer)
    }

    private func select(tty: String) {
        currentTTY = tty
        buffer = buffersByTTY[tty] ?? ""
        cursor = cursorsByTTY[tty] ?? buffer.count
    }

    private func persistCurrentBuffer() {
        guard let currentTTY else { return }
        buffersByTTY[currentTTY] = buffer
        cursorsByTTY[currentTTY] = cursor
    }
}
