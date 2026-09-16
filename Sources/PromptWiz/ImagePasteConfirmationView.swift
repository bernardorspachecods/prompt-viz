import AppKit
import SwiftUI

struct ImagePasteConfirmationView: View {
    let data: Data
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Preview image")
                .font(.headline)

            Group {
                if let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Text("The image could not be previewed.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 560, maxHeight: 420)

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Paste image", action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 520, minHeight: 380)
    }
}
