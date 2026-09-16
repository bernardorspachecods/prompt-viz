import AppKit
import Foundation
import OSLog

import ApplicationServices
import AppKit
import CoreGraphics
import OSLog
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers
import PromptWizCore

enum PromptWizBuild {
    static let label = "MVP build 22"
}
enum PromptWizLog {
    private static let logger = Logger(subsystem: "local.prompt-wiz.app", category: "runtime")
    private static let lock = NSLock()

    static let fileURL = FileManager.default
        .urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Logs", isDirectory: true)
        .appendingPathComponent("PromptWiz.log")

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

struct ImagePastePreview: Identifiable {
    let id = UUID()
    let data: Data
}

struct ImagePasteRequest: Equatable, Identifiable {
    let id = UUID()
    let data: Data
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

func isImagePasteShortcut(_ event: NSEvent) -> Bool {
    let modifiers = event.modifierFlags
    guard modifiers.contains(.option),
          !modifiers.contains(.command),
          !modifiers.contains(.control)
    else { return false }

    return event.keyCode == 9 ||
        event.charactersIgnoringModifiers?.lowercased() == "v" ||
        event.characters?.lowercased() == "√"
}

enum ClipboardImageReader {
    static func pngData(from pasteboard: NSPasteboard) -> Data? {
        if let pngData = pasteboard.data(forType: .png), !pngData.isEmpty {
            return pngData
        }

        if let tiffData = pasteboard.data(forType: .tiff),
           let image = NSImage(data: tiffData),
           let pngData = pngData(from: image) {
            return pngData
        }

        guard let image = NSImage(pasteboard: pasteboard) else { return nil }
        return pngData(from: image)
    }

    private static func pngData(from image: NSImage) -> Data? {
        guard
            let tiffData = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData)
        else { return nil }

        return bitmap.representation(using: .png, properties: [:])
    }
}
