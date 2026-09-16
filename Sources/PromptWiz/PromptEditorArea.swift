import AppKit
import PromptWizCore
import SwiftUI

@MainActor
struct PromptEditorArea: View {
    @ObservedObject var model: PromptWizModel
    @State private var text = ""
    @State private var hoveredSkillID: String?
    @State private var selectedSkillIndex = -1

    private var activeSkillQuery: String? {
        guard let range = text.range(
            of: #"\$[A-Za-z0-9_-]*$"#,
            options: .regularExpression
        ) else { return nil }

        return String(text[range].dropFirst())
    }

    private var visibleSkills: [SkillDescriptor] {
        model.searchSkills(activeSkillQuery ?? "")
            .prefix(6)
            .map { $0 }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            PromptTextEditor(
                text: Binding(
                    get: { text },
                    set: {
                        text = $0
                        model.updateEditorText($0)
                    }
                ),
                insertionRequest: $model.insertionRequest,
                cursorLocationRequest: $model.editorCursorLocationRequest,
                focusRequest: $model.editorFocusRequest,
                imagePasteRequest: $model.imagePasteRequest,
                skillHighlightRequest: $model.skillHighlightRequest,
                selectedSkillRanges: $model.selectedSkillRanges,
                onSkillKeyboardAction: handleSkillKeyboardAction,
                onImagePaste: { data, number in
                    model.registerImageAttachment(data, number: number)
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if activeSkillQuery != nil && !visibleSkills.isEmpty {
                skillSuggestions
                    .padding(.top, 58)
                    .padding(.leading, 14)
            }
        }
        .onAppear {
            text = model.editorText
        }
        .onChange(of: model.editorText) { newText in
            if text != newText {
                text = newText
            }
        }
    }

    private var skillSuggestions: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Skills")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(visibleSkills.enumerated()), id: \.element.id) { index, skill in
                    Button {
                        hoveredSkillID = nil
                        selectedSkillIndex = index
                        model.selectSkill(skill)
                    } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "sparkles")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 16)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("$" + skill.name)
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.primary)
                                if !skill.description.isEmpty {
                                    Text(skill.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(
                        hoveredSkillID == skill.id || selectedSkillIndex == index
                            ? Color.accentColor.opacity(0.18)
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                    .onHover { isHovered in
                        hoveredSkillID = isHovered ? skill.id : nil
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: 500, alignment: .leading)
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(.primary.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
    }

    private func handleSkillKeyboardAction(_ action: SkillKeyboardAction) -> Bool {
        guard !visibleSkills.isEmpty, activeSkillQuery != nil else { return false }

        switch action {
        case .moveDown:
            selectedSkillIndex = selectedSkillIndex < 0
                ? 0
                : (selectedSkillIndex + 1) % visibleSkills.count
        case .moveUp:
            selectedSkillIndex = selectedSkillIndex < 0
                ? visibleSkills.count - 1
                : (selectedSkillIndex - 1 + visibleSkills.count) % visibleSkills.count
        case .choose:
            let index = selectedSkillIndex < 0
                ? 0
                : min(selectedSkillIndex, visibleSkills.count - 1)
            model.selectSkill(visibleSkills[index])
            selectedSkillIndex = -1
        }

        return true
    }
}
