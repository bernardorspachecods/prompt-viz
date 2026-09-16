import SwiftUI

struct AppSettingsView: View {
    @ObservedObject var model: PromptVizModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.title2.weight(.semibold))

            Toggle("Launch Prompt Viz at login", isOn: Binding(
                get: { model.launchesAtLogin },
                set: { model.setLaunchAtLogin($0) }
            ))

            HStack {
                Text("Open Composer shortcut")

                Spacer()

                ShortcutRecorderView(shortcut: Binding(
                    get: { model.openComposerShortcut },
                    set: { model.setOpenComposerShortcut($0) }
                ))

                Button {
                    model.setOpenComposerShortcut(.defaultShortcut)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .help("Reset shortcut")
            }

            Text("Prompt Viz will run in the background and remain available through the \(model.openComposerShortcut.displayName) shortcut.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 430)
    }
}
