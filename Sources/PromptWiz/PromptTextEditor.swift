import AppKit
import PromptWizCore
import SwiftUI

struct PromptTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var insertionRequest: TextInsertionRequest?
    @Binding var cursorLocationRequest: Int?
    @Binding var focusRequest: UUID?
    @Binding var imagePasteRequest: ImagePasteRequest?
    @Binding var skillHighlightRequest: SkillHighlightRequest?
    @Binding var selectedSkillRanges: [NSRange]
    let onSkillKeyboardAction: (SkillKeyboardAction) -> Bool
    let onImagePaste: (Data, Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            selectedSkillRanges: $selectedSkillRanges,
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
        Self.applyInlineTokenStyles(to: textView, selectedSkillRanges: selectedSkillRanges)

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

        if !textView.hasMarkedText(), textView.string != text {
            let location = min(textView.selectedRange().location, text.utf16.count)
            context.coordinator.isApplyingModelText = true
            textView.string = text
            textView.setSelectedRange(NSRange(location: location, length: 0))
            context.coordinator.isApplyingModelText = false
        }

        if !textView.hasMarkedText() {
            Self.applyInlineTokenStyles(to: textView, selectedSkillRanges: selectedSkillRanges)
        }

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
           context.coordinator.lastImagePasteRequest != imagePasteRequest.id {
            context.coordinator.lastImagePasteRequest = imagePasteRequest.id
            _ = context.coordinator.handleImagePaste(imagePasteRequest.data, in: textView)
            let requestID = imagePasteRequest.id
            DispatchQueue.main.async {
                guard self.imagePasteRequest?.id == requestID else { return }
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

            let highlightRange = NSRange(location: location, length: length)
            let highlightedText = (textView.string as NSString).substring(with: highlightRange)
            let requestIsReady = length == skillHighlightRequest.range.length &&
                highlightedText.hasPrefix("$")

            if requestIsReady {
                let selectedRange = NSRange(location: location, length: length)
                if !selectedSkillRanges.contains(where: { NSEqualRanges($0, selectedRange) }) {
                    selectedSkillRanges.append(selectedRange)
                }
                Self.applyInlineTokenStyles(to: textView, selectedSkillRanges: selectedSkillRanges)
                context.coordinator.lastSkillHighlightID = skillHighlightRequest.id
                let requestID = skillHighlightRequest.id
                DispatchQueue.main.async {
                    guard self.skillHighlightRequest?.id == requestID else { return }
                    self.skillHighlightRequest = nil
                }
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
        context.coordinator.selectedSkillRanges = context.coordinator.adjustedSelectedSkillRanges(
            afterReplacing: selection,
            withUTF16Length: insertionRequest.text.utf16.count
        )
        context.coordinator.isApplyingModelText = true
        textView.string = updated
        textView.setSelectedRange(NSRange(location: selection.location + insertionRequest.text.utf16.count, length: 0))
        context.coordinator.isApplyingModelText = false
        Self.applyInlineTokenStyles(to: textView, selectedSkillRanges: selectedSkillRanges)
        let requestID = insertionRequest.id
        DispatchQueue.main.async {
            guard self.insertionRequest?.id == requestID else { return }
            self.text = updated
            self.insertionRequest = nil
            context.coordinator.lastInsertionID = nil
        }
    }

    static func applyInlineTokenStyles(
        to textView: NSTextView,
        selectedSkillRanges: [NSRange]
    ) {
        guard !textView.hasMarkedText() else { return }
        guard let textStorage = textView.textStorage else { return }

        let fullRange = NSRange(location: 0, length: textStorage.length)
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15),
            .foregroundColor: NSColor.labelColor
        ]

        textStorage.beginEditing()
        if fullRange.length > 0 {
            textStorage.addAttributes(baseAttributes, range: fullRange)
        }

        let tokenAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: NSColor.controlAccentColor
        ]
        for token in PromptEditorTokens.tokens(in: textView.string) {
            let isImage = token.kind == .imageReference
            let isSelectedSkill = token.kind == .skillReference &&
                selectedSkillRanges.contains(where: { NSEqualRanges($0, token.range) })

            if isImage || isSelectedSkill {
                textStorage.addAttributes(tokenAttributes, range: token.range)
            }
        }
        textStorage.endEditing()
        textView.typingAttributes = baseAttributes
    }

    static func semanticTokenRanges(
        in textView: NSTextView,
        selectedSkillRanges: [NSRange]
    ) -> [NSRange] {
        return PromptEditorTokens.tokens(in: textView.string).compactMap { token in
            if token.kind == .imageReference {
                return token.range
            }

            return selectedSkillRanges.contains(where: { NSEqualRanges($0, token.range) })
                ? token.range
                : nil
        }
    }

    static func normalizedSelectionRange(
        _ proposedRange: NSRange,
        from previousRange: NSRange?,
        blockedRanges: [NSRange]
    ) -> NSRange {
        guard proposedRange.location >= 0, proposedRange.length >= 0 else {
            return proposedRange
        }

        var normalizedRange = proposedRange
        for blockedRange in blockedRanges {
            let blockedStart = blockedRange.location
            let blockedEnd = NSMaxRange(blockedRange)

            if normalizedRange.length == 0 {
                guard normalizedRange.location > blockedStart,
                      normalizedRange.location < blockedEnd
                else { continue }

                if let previousLocation = previousRange?.location,
                   previousLocation <= blockedStart,
                   normalizedRange.location > previousLocation {
                    normalizedRange.location = blockedEnd
                } else if let previousLocation = previousRange?.location,
                          previousLocation >= blockedEnd,
                          normalizedRange.location < previousLocation {
                    normalizedRange.location = blockedStart
                } else {
                    let distanceToStart = normalizedRange.location - blockedStart
                    let distanceToEnd = blockedEnd - normalizedRange.location
                    normalizedRange.location = distanceToStart < distanceToEnd
                        ? blockedStart
                        : blockedEnd
                }
            } else if NSIntersectionRange(normalizedRange, blockedRange).length > 0 {
                normalizedRange = NSUnionRange(normalizedRange, blockedRange)
            }
        }

        return normalizedRange
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        @Binding var selectedSkillRanges: [NSRange]
        var lastInsertionID: UUID?
        var lastFocusRequestID: UUID?
        var lastImagePasteRequest: UUID?
        var lastSkillHighlightID: UUID?
        var isApplyingModelText = false
        var onSkillKeyboardAction: (SkillKeyboardAction) -> Bool
        var onImagePaste: (Data, Int) -> Void

        init(
            text: Binding<String>,
            selectedSkillRanges: Binding<[NSRange]>,
            onSkillKeyboardAction: @escaping (SkillKeyboardAction) -> Bool,
            onImagePaste: @escaping (Data, Int) -> Void
        ) {
            _text = text
            _selectedSkillRanges = selectedSkillRanges
            self.onSkillKeyboardAction = onSkillKeyboardAction
            self.onImagePaste = onImagePaste
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            guard !isApplyingModelText else { return }
            text = textView.string
            guard !textView.hasMarkedText() else { return }
            PromptTextEditor.applyInlineTokenStyles(
                to: textView,
                selectedSkillRanges: selectedSkillRanges
            )
        }

        func textView(
            _ textView: NSTextView,
            willChangeSelectionFromCharacterRanges oldSelectedCharRanges: [NSValue],
            toCharacterRanges newSelectedCharRanges: [NSValue]
        ) -> [NSValue] {
            guard !textView.hasMarkedText() else { return newSelectedCharRanges }

            let blockedRanges = PromptTextEditor.semanticTokenRanges(
                in: textView,
                selectedSkillRanges: selectedSkillRanges
            )
            let previousRange = oldSelectedCharRanges.first?.rangeValue

            return newSelectedCharRanges.map { value in
                NSValue(
                    range: PromptTextEditor.normalizedSelectionRange(
                        value.rangeValue,
                        from: previousRange,
                        blockedRanges: blockedRanges
                    )
                )
            }
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            guard !textView.hasMarkedText() else { return true }

            if let tokenRange = PromptEditorTokens.editingRange(
                for: affectedCharRange,
                in: textView.string,
                restrictedTo: PromptTextEditor.semanticTokenRanges(
                    in: textView,
                    selectedSkillRanges: selectedSkillRanges
                )
            ), tokenRange != affectedCharRange {
                let replacement = replacementString ?? ""
                selectedSkillRanges = adjustedSelectedSkillRanges(
                    afterReplacing: tokenRange,
                    withUTF16Length: replacement.utf16.count
                )
                isApplyingModelText = true
                textView.textStorage?.replaceCharacters(in: tokenRange, with: replacement)
                textView.setSelectedRange(NSRange(
                    location: tokenRange.location + replacement.utf16.count,
                    length: 0
                ))
                isApplyingModelText = false
                text = textView.string
                PromptTextEditor.applyInlineTokenStyles(
                    to: textView,
                    selectedSkillRanges: selectedSkillRanges
                )
                PromptWizLog.info("Inline token edit expanded to the whole block")
                return false
            }

            guard
                replacementString != nil,
                let event = NSApp.currentEvent,
                isImagePasteShortcut(event)
            else {
                selectedSkillRanges = adjustedSelectedSkillRanges(
                    afterReplacing: affectedCharRange,
                    withUTF16Length: replacementString?.utf16.count ?? 0
                )
                return true
            }

                PromptWizLog.info("Image shortcut received through text replacement")
            return !handleImagePaste(in: textView, selectedRange: affectedCharRange)
        }

        fileprivate func adjustedSelectedSkillRanges(
            afterReplacing affectedRange: NSRange,
            withUTF16Length replacementLength: Int
        ) -> [NSRange] {
            let editStart = affectedRange.location
            let editEnd = affectedRange.location + affectedRange.length
            let delta = replacementLength - affectedRange.length

            return selectedSkillRanges.compactMap { range in
                let tokenStart = range.location
                let tokenEnd = range.location + range.length
                let overlaps = affectedRange.length == 0
                    ? editStart > tokenStart && editStart < tokenEnd
                    : editStart < tokenEnd && editEnd > tokenStart

                if overlaps {
                    return nil
                }

                if editEnd <= tokenStart {
                    return NSRange(
                        location: tokenStart + delta,
                        length: range.length
                    )
                }

                return range
            }
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
            _ confirmedImageData: Data? = nil,
            in textView: NSTextView,
            selectedRange overrideRange: NSRange? = nil
        ) -> Bool {
            let imageData: Data
            if let confirmedImageData {
                guard !confirmedImageData.isEmpty else { return false }
                imageData = confirmedImageData
                PromptWizLog.info("Image paste using confirmed preview data")
            } else {
                let pasteboard = NSPasteboard.general
                let types = pasteboard.types?.map(\.rawValue).joined(separator: ", ") ?? "none"
                PromptWizLog.info("Image pasteboard types: \(types)")

                if let pngData = pasteboard.data(forType: .png), !pngData.isEmpty {
                    imageData = pngData
                    PromptWizLog.info("Image paste found PNG data")
                } else if let tiffData = pasteboard.data(forType: .tiff),
                          let image = NSImage(data: tiffData),
                          let convertedData = pngData(from: image) {
                    imageData = convertedData
                    PromptWizLog.info("Image paste converted TIFF data to PNG")
                } else if let image = NSImage(pasteboard: pasteboard),
                          let convertedData = pngData(from: image) {
                    imageData = convertedData
                    PromptWizLog.info("Image paste converted NSImage data to PNG")
                } else {
                    PromptWizLog.info("Image paste found no supported image data")
                    return false
                }
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
            selectedSkillRanges = adjustedSelectedSkillRanges(
                afterReplacing: selection,
                withUTF16Length: token.utf16.count
            )

            isApplyingModelText = true
            textView.string = updated
            textView.setSelectedRange(NSRange(
                location: selection.location + token.utf16.count,
                length: 0
            ))
            isApplyingModelText = false
            text = updated
            onImagePaste(imageData, number)
            PromptTextEditor.applyInlineTokenStyles(
                to: textView,
                selectedSkillRanges: selectedSkillRanges
            )
            PromptWizLog.info("Image placeholder inserted: \(token)")
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
