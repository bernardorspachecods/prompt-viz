import AppKit

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
