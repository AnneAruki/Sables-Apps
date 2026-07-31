//
//  SableLibraryOnboardingView.swift
//  Sable's Library
//

import SwiftUI

struct SableLibraryOnboardingView: View {
    @Environment(\.sableLibraryPalette) private var palette
    @Environment(\.dismiss) private var dismiss

    let hasLibraryFolder: Bool
    let onChooseFolder: () -> Void
    let onInspect: () -> Void
    let onOpenSettings: () -> Void
    let onFinish: () -> Void

    @Binding var selectedStep: Int

    private let steps: [SableLibraryOnboardingStep] = [
        SableLibraryOnboardingStep(
            title: "Choose one library folder",
            detail: "Choose the top folder that holds your books or comics. The app remembers that library folder, then only reads it until you approve a file-changing task.",
            systemImage: "folder",
            actionTitle: "Choose Folder"
        ),
        SableLibraryOnboardingStep(
            title: "Scan before changing",
            detail: "Scan Inventory maps book files, local sidecars, messy edges, duplicates, missing numbers, and catalog clues before anything moves or renames.",
            systemImage: "magnifyingglass",
            actionTitle: "Scan Inventory"
        ),
        SableLibraryOnboardingStep(
            title: "Keep the receipts",
            detail: "Every serious run writes readable reports. File-changing moves keep an undo plan, so the app can retrace the last applied route.",
            systemImage: "doc.text",
            actionTitle: nil
        ),
        SableLibraryOnboardingStep(
            title: "Quiet magic, local first",
            detail: "Local learning stays on this Mac. Apple Intelligence may help write clearer review notes. Provider calls happen only for checked rows that need fresh data, and same-session cache stays in memory.",
            systemImage: "lock",
            actionTitle: "Review Settings"
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            header

            softDivider

            HStack(alignment: .top, spacing: 18) {
                stepRail
                    .frame(width: 230)

                stepCard(steps[selectedStep])
                    .frame(maxWidth: .infinity, minHeight: 310, alignment: .topLeading)
            }
            .padding(22)

            softDivider

            footer
        }
        .frame(minWidth: 700, minHeight: 500)
        .sableLibraryAmbientBackground()
        .sableLibraryWindowMirrorEffect()
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(palette.accent)
                .frame(width: 48, height: 48)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Welcome to Sable's Library")
                    .font(.title2.bold())
                Text("This quick guide stays practical, skippable, and available from Settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(22)
    }

    private var softDivider: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.clear,
                        palette.border,
                        palette.accent.opacity(0.18),
                        palette.border,
                        Color.clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 1)
            .accessibilityHidden(true)
    }

    private var stepRail: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                Button {
                    selectedStep = index
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: step.systemImage)
                            .frame(width: 20)
                            .accessibilityHidden(true)
                        Text(step.title)
                            .font(.callout.weight(.medium))
                            .lineLimit(2)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity)
                    .contentShape(RoundedRectangle(cornerRadius: SableLibraryDesign.cornerRadius))
                }
                .buttonStyle(.plain)
                .foregroundStyle(index == selectedStep ? palette.accent : palette.textSecondary)
                .sableLibraryMenuTriggerSurface(isActive: index == selectedStep)
                .accessibilityLabel(step.title)
                .accessibilityValue(index == selectedStep ? "Selected" : "Not selected")
            }

            Spacer(minLength: 0)
        }
    }

    private func stepCard(_ step: SableLibraryOnboardingStep) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ZStack {
                Image(systemName: step.systemImage)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(palette.accent)
            }
            .frame(width: 78, height: 78)
            .sableLibrarySurface(
                fill: palette.accent.opacity(0.11),
                border: Color.clear,
                glassTint: palette.accent,
                glassProminence: .decorative,
                glassIntensity: .thin
            )
            .accessibilityHidden(true)

            Text(step.title)
                .font(.title.bold())
            Text(step.detail)
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if step.title == "Choose one library folder", hasLibraryFolder {
                Label("Folder selected. You can continue the tour.", systemImage: "checkmark.circle")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(palette.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .sableLibrarySurface(
                        fill: palette.accent.opacity(0.11),
                        border: Color.clear,
                        cornerRadius: 999,
                        glassTint: palette.accent,
                        glassProminence: .decorative,
                        glassIntensity: .thin
                    )
            }

            if step.title == "Scan before changing", !hasLibraryFolder {
                Label("Choose a folder first. Inventory stays read-only.", systemImage: "folder.badge.questionmark")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if let actionTitle = actionTitle(for: step) {
                Button(actionTitle) {
                    performStepAction(step)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityHint(actionHint(for: step))
            }
        }
        .padding(22)
        .sableLibrarySurface(
            fill: palette.surface,
            border: palette.accent.opacity(0.30),
            glassTint: palette.accent,
            glassProminence: .decorative,
            glassIntensity: .prominent
        )
    }

    private var footer: some View {
        HStack {
            Button("Skip") {
                finish()
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            Button("Back") {
                selectedStep = max(0, selectedStep - 1)
            }
            .disabled(selectedStep == 0)

            Button(selectedStep == steps.count - 1 ? "Done" : "Next") {
                if selectedStep == steps.count - 1 {
                    finish()
                } else {
                    selectedStep += 1
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }

    private func actionTitle(for step: SableLibraryOnboardingStep) -> String? {
        if step.title == "Scan before changing", !hasLibraryFolder {
            return "Choose Folder First"
        }
        return step.actionTitle
    }

    private func actionHint(for step: SableLibraryOnboardingStep) -> String {
        switch step.title {
        case "Choose one library folder":
            return "Opens the macOS folder picker."
        case "Scan before changing":
            return hasLibraryFolder
                ? "Starts a read-only inventory scan of the selected folder."
                : "Opens the folder picker before inventory scanning is available."
        case "Quiet magic, local first":
            return "Opens Settings so you can review privacy and assist options."
        default:
            return ""
        }
    }

    private func performStepAction(_ step: SableLibraryOnboardingStep) {
        switch step.title {
        case "Choose one library folder":
            onChooseFolder()
        case "Scan before changing":
            if hasLibraryFolder {
                onInspect()
            } else {
                onChooseFolder()
            }
        case "Quiet magic, local first":
            onOpenSettings()
        default:
            break
        }
    }

    private func finish() {
        onFinish()
        dismiss()
    }
}

private struct SableLibraryOnboardingStep: Hashable {
    let title: String
    let detail: String
    let systemImage: String
    let actionTitle: String?
}
