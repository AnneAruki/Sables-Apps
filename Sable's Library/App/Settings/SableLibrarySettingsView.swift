//
//  SableLibrarySettingsView.swift
//  Sable's Library
//

import SwiftUI

private enum SableLibrarySettingsPage: String, CaseIterable, Hashable, Identifiable {
    case general
    case review
    case learning
    case lookups
    case appearance
    case recovery

    var id: String { rawValue }

    func title(for mode: SableLibraryAppMode) -> String {
        switch self {
        case .general: "General"
        case .review: mode == .clinic ? "Repair" : mode == .covers ? "Cover Rules" : "Review"
        case .learning: "Learning"
        case .lookups: "Lookups"
        case .appearance: "Look"
        case .recovery: "Reset"
        }
    }

    func systemImage(for mode: SableLibraryAppMode) -> String {
        switch self {
        case .general: "slider.horizontal.3"
        case .review: mode == .clinic ? "cross.case" : mode == .covers ? "photo.stack" : "checklist"
        case .learning: "brain"
        case .lookups: "key"
        case .appearance: "paintpalette"
        case .recovery: "shield.checkered"
        }
    }

    func isVisible(in mode: SableLibraryAppMode) -> Bool {
        switch (mode, self) {
        case (.clinic, .lookups):
            false
        case (.covers, .learning):
            false
        default:
            true
        }
    }
}

struct SableLibrarySettingsView: View {
    @AppStorage("sableLibrary.appAppearance") private var storedAppearance = SableLibraryAppearance.system.rawValue
    @AppStorage("sableLibrary.appAccent") private var storedAccent = SableLibraryAccentPreset.defaultAccent.rawValue
    @AppStorage("sableLibrary.liquidGlassEnabled") private var liquidGlassEnabled = true
    @AppStorage("sableLibrary.rolerShareConfirmedMatches")
    private var shareConfirmedMatchesWithRoler = true
    @Environment(\.sableLibraryPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @Binding var cleanupOptions: CleanupOptions
    @Binding var pipelineStageOptions: LibraryPipelineStageOptions
    @Binding var intelligenceOptions: SableLibraryIntelligenceOptions
    @Binding var providerCredentials: SableLibraryProviderCredentials
    @State private var showAppearancePreview = false
    @State private var showPersonalModelControls = false
    @State private var showProviderKeys = false
    @State private var showAdvancedSettings = false
    @State private var selectedSettingsPage: SableLibrarySettingsPage = .general
    @State private var pendingDestructiveAction: DestructiveSettingsAction?
    @State private var showPersonalTrainingWarning = false
    @State private var showRolerContributorLogin = false
    @State private var rolerContributorSession:
        SableRolerContributorSession?
    @State private var isCheckingRolerContributorAccess = false
    @State private var rolerContributorAccessError: String?

    private let rolerContributorClient = SableRolerContributorClient()

    let mode: SableLibraryAppMode
    let hasSavedLibrary: Bool
    let learnedDecisionCount: Int?
    let hasLearningMemory: Bool
    let isTrainingPersonalModel: Bool
    let personalTrainingResult: SableLibraryPersonalModelTrainingResult?
    let personalTrainingError: String?
    let personalModelExists: Bool
    let onForgetLibrary: () -> Void
    let onResetOptions: () -> Void
    let onResetLearning: () -> Void
    let onClearProviderCredentials: () -> Void
    let onTrainPersonalModel: () -> Void
    let onRequestLearningStatus: () -> Void
    let onShowOnboarding: () -> Void
    let onClose: (() -> Void)?

    var body: some View {
        settingsTabs
            .onAppear {
                ensureSelectedSettingsPageIsVisible()
                requestStatusForSelectedPage()
            }
            .onChange(of: selectedSettingsPage) { _, _ in
                requestStatusForSelectedPage()
            }
            .onChange(of: intelligenceOptions.useLocalLearning) { _, _ in
                requestStatusForSelectedPage()
            }
            .confirmationDialog(
                pendingDestructiveAction?.title(for: mode) ?? "Confirm Change",
                isPresented: Binding(
                    get: { pendingDestructiveAction != nil },
                    set: { if !$0 { pendingDestructiveAction = nil } }
                ),
                presenting: pendingDestructiveAction
            ) { action in
                Button(action.confirmationTitle(for: mode), role: .destructive) {
                    let confirmedAction = action
                    pendingDestructiveAction = nil
                    perform(confirmedAction)
                }
                Button("Cancel", role: .cancel) {
                    pendingDestructiveAction = nil
                }
            } message: { action in
                Text(action.message(for: mode))
            }
            .confirmationDialog(
                "Retrain from Local Data?",
                isPresented: $showPersonalTrainingWarning
            ) {
                Button("Retrain Local Model") {
                    showPersonalTrainingWarning = false
                    onTrainPersonalModel()
                }
                Button("Cancel", role: .cancel) {
                    showPersonalTrainingWarning = false
                }
            } message: {
                Text("This uses local training material from your saved library reports and Sable learning memory. It can use CPU for a short time, writes a personal model on this Mac, and does not move, rename, upload, or overwrite your files.")
            }
            .sheet(isPresented: $showRolerContributorLogin) {
                SableRolerContributorLoginView(
                    onAuthenticated: completeRolerContributorLogin,
                    onCancel: {
                        showRolerContributorLogin = false
                    }
                )
            }
    }

    private var settingsTabs: some View {
        HStack(spacing: 0) {
            settingsSidebar
                .frame(width: 176)

            Divider()

            selectedSettingsContent
        }
        .frame(minWidth: 760, minHeight: 580)
        .toolbar {
            if let onClose {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onClose)
                }
            }
        }
    }

    private var visibleSettingsPages: [SableLibrarySettingsPage] {
        SableLibrarySettingsPage.allCases.filter { $0.isVisible(in: mode) }
    }

    private func ensureSelectedSettingsPageIsVisible() {
        guard !visibleSettingsPages.contains(selectedSettingsPage),
              let firstPage = visibleSettingsPages.first else {
            return
        }
        selectedSettingsPage = firstPage
    }

    private func requestStatusForSelectedPage() {
        switch selectedSettingsPage {
        case .learning where mode == .library:
            onRequestLearningStatus()
        case .recovery:
            onRequestLearningStatus()
        case .general, .review, .learning, .lookups, .appearance:
            break
        }
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(visibleSettingsPages) { page in
                Button {
                    selectedSettingsPage = page
                } label: {
                    Label(page.title(for: mode), systemImage: page.systemImage(for: mode))
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(selectedSettingsPage == page ? palette.accent : .primary)
                .background(
                    selectedSettingsPage == page ? palette.accent.opacity(0.14) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .accessibilityLabel(page.title(for: mode))
                .accessibilityValue(selectedSettingsPage == page ? "Selected" : "Not selected")
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private var selectedSettingsContent: some View {
        switch selectedSettingsPage {
        case .general:
            settingsPage {
                if mode == .clinic {
                    clinicDefaultsSection
                } else if mode == .covers {
                    coversDefaultsSection
                } else {
                    cleanupSection
                }
            }
        case .review:
            settingsPage {
                if mode == .clinic {
                    clinicRepairSection
                } else if mode == .covers {
                    coversReviewSection
                } else {
                    libraryReviewSection
                    libraryAdvancedSection
                }
            }
        case .learning:
            settingsPage {
                if mode != .library {
                    clinicLearningSection
                } else {
                    learningSection
                }
            }
        case .lookups:
            settingsPage {
                providerAccessSection
            }
        case .appearance:
            settingsPage {
                appearanceSection
            }
        case .recovery:
            settingsPage {
                safetySection
                if mode.showsOnboarding {
                    helpSection
                }
            }
        }
    }

    private func settingsPage<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content()
            }
            .padding(22)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    private var introCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(palette.accent)
                .frame(width: 42, height: 42)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Settings basics")
                    .font(.headline)
                Text("Everyday cleanup choices are first. Optional lookups, personal learning, slower checks, and appearance controls stay lower on the page. Anything that changes files still needs reviewed and checked rows before it runs.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .sableLibraryRaisedPanelSurface()
    }

    private var selectedAppearance: Binding<SableLibraryAppearance> {
        Binding(
            get: { SableLibraryAppearance(rawValue: storedAppearance) ?? .system },
            set: { storedAppearance = $0.rawValue }
        )
    }

    private var selectedAccent: Binding<SableLibraryAccentPreset> {
        Binding(
            get: { SableLibraryAccentPreset.stored(storedAccent) },
            set: { storedAccent = $0.rawValue }
        )
    }

    private var appearanceSection: some View {
        settingsGroup(title: "Appearance", systemImage: "paintpalette", note: "Color and surface preferences.") {
            Picker("Appearance", selection: selectedAppearance) {
                ForEach(SableLibraryAppearance.allCases) { appearance in
                    Text(appearance.label).tag(appearance)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityHint("Chooses whether \(mode.appName) follows the system appearance or stays in light or dark mode.")

            Text(selectedAppearance.wrappedValue.helpText)
                .font(.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Text("Accent")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.textSecondary)
                SableEagerAdaptiveGrid(
                    minimumItemWidth: 108,
                    horizontalSpacing: 8,
                    verticalSpacing: 8
                ) {
                    ForEach(SableLibraryAccentPreset.allCases) { accent in
                        accentButton(accent)
                    }
                }
            }

            Toggle(isOn: $liquidGlassEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Use Liquid Glass when available")
                        .font(.callout.weight(.medium))
                    Text(glassAvailabilityText)
                        .font(.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)
            .accessibilityHint("Turns custom Liquid Glass surfaces on when this Mac and accessibility settings allow them.")

            DisclosureGroup(isExpanded: $showAppearancePreview) {
                VStack(alignment: .leading, spacing: 10) {
                    appearancePreview()

                    SableLibraryInfoBanner(
                        text: "Accessibility settings win: high contrast and reduced transparency use solid surfaces automatically.",
                        role: .running,
                        systemImage: "circle.lefthalf.filled"
                    )
                }
                .padding(.top, 8)
            } label: {
                Text(showAppearancePreview ? "Hide Appearance Preview" : "Show Appearance Preview")
                    .font(.callout.weight(.medium))
            }
            .accessibilityHint("Shows a visual preview of accent, focus, and surface settings.")
        }
    }

    private var glassAvailabilityText: String {
        if reduceTransparency {
            return "Reduce Transparency is on, so \(mode.appName) uses solid surfaces."
        }
        if colorSchemeContrast == .increased {
            return "Increase Contrast is on, so \(mode.appName) uses stronger solid surfaces."
        }
        if #available(macOS 26.0, *) {
            return "Glass appears on supported custom surfaces. Turn this off for a simpler solid look."
        }
        return "This Mac uses the standard solid/material fallback because Liquid Glass requires macOS 26 or later."
    }

    private func accentButton(_ accent: SableLibraryAccentPreset) -> some View {
        let isSelected = selectedAccent.wrappedValue == accent
        let accentColor = accent.color(colorScheme: selectedAppearance.wrappedValue.preferredColorScheme ?? colorScheme, contrast: colorSchemeContrast)

        return Button {
            selectedAccent.wrappedValue = accent
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(accentColor)
                    .frame(width: 18, height: 18)
                    .overlay(Circle().stroke(palette.border))
                    .accessibilityHidden(true)
                Text(accent.label)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: SableLibraryDesign.cornerRadius))
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: SableLibraryDesign.cornerRadius))
        .sableLibraryMenuTriggerSurface(isActive: isSelected)
        .accessibilityLabel("Accent: \(accent.label)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint(accent.helpText)
    }

    private func appearancePreview() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview")
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.textSecondary)

            ZStack {
                glassPreviewBackdrop
                SableEagerAdaptiveGrid(
                    minimumItemWidth: 190,
                    horizontalSpacing: 10,
                    verticalSpacing: 10
                ) {
                    glassPreviewTile("Buttons", detail: "Small secondary controls", systemImage: "button.programmable", intensity: .ultraThin)
                    glassPreviewTile("Action Menus", detail: "Active command triggers", systemImage: "ellipsis.circle", intensity: .thin)
                    glassPreviewTile("Review Panels", detail: "Rows, cards, and summaries", systemImage: "list.bullet.rectangle", intensity: .regular)
                    glassPreviewTile("Window", detail: "Main app surface", systemImage: "macwindow", intensity: .prominent)
                }
                .padding(10)
            }
            .clipShape(RoundedRectangle(cornerRadius: SableLibraryDesign.cornerRadius))
            .accessibilityElement(children: .contain)

            HStack(alignment: .top, spacing: 8) {
                previewGroup(title: "Accent Tint") {
                    HStack(spacing: 6) {
                        accentPreviewBadge("Review", systemImage: "eye")
                        accentPreviewBadge("Safe", systemImage: "checkmark.circle")
                        accentPreviewBadge("Check", systemImage: "questionmark.circle")
                    }
                }

                previewGroup(title: "Focus Ring") {
                    focusPreviewControl()
                }
            }
        }
        .padding(10)
        .sableLibraryRaisedPanelSurface()
    }

    private var glassPreviewBackdrop: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(
                    colors: [
                        palette.background,
                        palette.accent.opacity(0.22),
                        palette.surface
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                ForEach(0..<7, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 999)
                        .fill(index.isMultiple(of: 2) ? palette.accent.opacity(0.18) : palette.textSecondary.opacity(0.10))
                        .frame(width: 120, height: 18)
                        .rotationEffect(.degrees(-18))
                        .offset(
                            x: -geometry.size.width / 2 + CGFloat(index * 74),
                            y: CGFloat(index % 3) * 26 - 28
                        )
                }
            }
        }
        .frame(minHeight: 78)
    }

    private func previewGroup<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(palette.textSecondary)
            content()
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sableLibrarySurface(
            fill: palette.surface,
            border: palette.border,
            glassTint: palette.accent,
            glassProminence: .decorative,
            glassIntensity: .ultraThin
        )
    }

    private func accentPreviewBadge(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(palette.accent)
            .sableLibrarySurface(
                fill: palette.accent.opacity(0.12),
                border: Color.clear,
                cornerRadius: 999,
                glassTint: palette.accent,
                glassProminence: .decorative,
                glassIntensity: .thin
            )
    }

    private func focusPreviewControl() -> some View {
        HStack(spacing: 8) {
            Image(systemName: "keyboard")
                .foregroundStyle(palette.accent)
                .accessibilityHidden(true)
            Text("Focused control")
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .sableLibrarySurface(
            fill: palette.surface,
            border: palette.focusRing.opacity(0.95),
            cornerRadius: 999,
            glassTint: palette.accent,
            glassProminence: .decorative,
            glassIntensity: .thin
        )
        .overlay(
            Capsule()
                .stroke(palette.focusRing.opacity(0.95), lineWidth: colorSchemeContrast == .increased ? 2.5 : 2)
                .padding(-3)
        )
    }

    private func glassPreviewTile(
        _ label: String,
        detail: String,
        systemImage: String,
        intensity: SableLibraryGlassIntensity
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(palette.accent)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
                Text(tintLabel(for: intensity))
                    .font(.caption2)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .sableLibrarySurface(
            fill: palette.surface.opacity(fillPreviewOpacity(for: intensity)),
            border: palette.accent.opacity(borderPreviewOpacity(for: intensity)),
            glassTint: palette.accent,
            glassProminence: .decorative,
            glassIntensity: intensity
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Glass preview: \(label)")
    }

    private func tintLabel(for intensity: SableLibraryGlassIntensity) -> String {
        switch intensity {
        case .ultraThin: "Ultra-thin glass"
        case .thin: "Thin glass"
        case .regular: "Readable glass"
        case .prominent: "Strong glass"
        }
    }

    private func fillPreviewOpacity(for intensity: SableLibraryGlassIntensity) -> Double {
        switch intensity {
        case .ultraThin: 0.10
        case .thin: 0.14
        case .regular: 0.18
        case .prominent: 0.24
        }
    }

    private func borderPreviewOpacity(for intensity: SableLibraryGlassIntensity) -> Double {
        switch intensity {
        case .ultraThin: 0.20
        case .thin: 0.30
        case .regular: 0.42
        case .prominent: 0.58
        }
    }

    private var cleanupSection: some View {
        settingsGroup(title: "Everyday cleanup", systemImage: "folder", note: "Default suggestions for paths and filenames. Nothing changes files until review and apply.") {
            settingToggle("Place loose files", detail: "Prepares folder and filename suggestions for loose books, videos, documents, images, audio, archives, and other root-level files. Apply still needs checked rows.", isOn: $cleanupOptions.organizeLooseBooks)
            settingToggle("Clean book file names", detail: "Prepares shorter filenames by removing obvious source tags, raw volume wording, and overly long provider subtitles before apply.", isOn: $cleanupOptions.renameFiles)
            settingToggle("Sort series folders", detail: "Uses trusted ComicInfo or AnimeInfo sidecars to prepare tidy type-folder moves. Folders with collisions stay out until reviewed.", isOn: $cleanupOptions.renameFolders)
            folderOrganizationDepthPicker
            settingToggle("Treat all PDFs as books", detail: "Use this for a folder that is mostly PDF books or comics. When off, PDFs need book evidence such as ComicInfo, a reading ID, a book/comic sibling, or a Manga/Books folder; other PDFs go to PDF triage before document moves.", isOn: $cleanupOptions.treatPDFsAsBooks)
        }
    }

    private var libraryReviewSection: some View {
        settingsGroup(title: "Review pages", systemImage: "books.vertical", note: "Choose which review pages inspection prepares.") {
            settingToggle("Prepare raw cleanup", detail: "Adds the first review page for root-level loose files, broad type folders, PDF triage, and simple intake placement. EPUB repair stays in Sable's Clinic.", isOn: $pipelineStageOptions.applyCleanup)
            settingToggle("Prepare missing-number review", detail: "Adds a review page for books or chapters that may need volume, part, or chapter attention before naming.", isOn: $pipelineStageOptions.moveMissingNumbers)
            settingToggle("Use sidecar titles", detail: "Lets trusted ComicInfo and AnimeInfo preferred titles shape folder and file suggestions. Turn this off when raw folder names should stay in charge.", isOn: $pipelineStageOptions.useComicInfoTitles)
            preferredTitleStylePicker
            settingToggle("Use MangaBaka for ComicInfo", detail: "Lets checked ComicInfo rows contact MangaBaka during apply. Inspection stays local, fresh unchanged sidecars stay quiet, and weak matches are skipped.", isOn: $pipelineStageOptions.useMangaBaka)
            settingToggle("Use metadata providers", detail: "Lets checked rows contact enabled providers such as RanobeDB, Open Library, AniList, TVmaze, and Wikidata during apply. Inspection still reads local files first.", isOn: $pipelineStageOptions.useMetadataProviders)
            settingToggle("Save receipts", detail: "Writes plain-text receipts and undo notes into the report folder when a step changes files. If this is off or unavailable, the app cannot save the same recovery trail for that run.", isOn: $pipelineStageOptions.exportReports)
            SableLibraryInfoBanner(
                text: "Network boundary: provider switches affect checked apply rows, not the initial folder inspection. Fast everyday pass: raw cleanup plus receipts.",
                role: .info,
                systemImage: "bolt"
            )
        }
    }

    private var coversDefaultsSection: some View {
        settingsGroup(title: "Cover workspace", systemImage: "photo.stack", note: "Defaults for local cover archives and EPUB cover repair. The first inventory remains read-only.") {
            settingToggle("Download series covers", detail: "Enables MangaBaka baseline downloads and optional BookLive, BookWalker, and Amazon quality upgrades in Sable's Covers.", isOn: $pipelineStageOptions.downloadSeriesCovers)
            settingToggle("Write EPUB cover repairs", detail: "Lets checked EPUB Cover rows repair cover markers or use a clearly better language-matched local cover. Other EPUB metadata and content stay untouched.", isOn: $pipelineStageOptions.writeEPUBImportMetadata)
            settingToggle("Save receipts", detail: "Writes local receipts when cover files, manifests, or EPUBs change.", isOn: $pipelineStageOptions.exportReports)
            SableLibraryInfoBanner(
                text: "MangaBaka is the fast baseline. Store providers are a separate quality-upgrade pass. EPUB replacement still requires the higher Clinic quality floor.",
                role: .info,
                systemImage: "checkmark.shield"
            )
        }
    }

    private var coversReviewSection: some View {
        settingsGroup(title: "Cover safety", systemImage: "checkmark.shield", note: "Language, media type, volume, quality, and duplicate checks stay mandatory.") {
            SableLibraryInfoBanner(
                text: "Sable archives correct lower-resolution covers when useful, but only high-quality language-matched normal covers can replace an EPUB cover. Manga, light novel, audiobook, chapter, back, and special covers remain distinct.",
                role: .info,
                systemImage: "photo.badge.checkmark"
            )
            SableLibraryInfoBanner(
                text: "MangaBaka Studio always previews the exact public database change first. Review queue is the default; direct apply requires a separate explicit confirmation.",
                role: .warning,
                systemImage: "person.badge.shield.checkmark"
            )
        }
    }

    private var clinicDefaultsSection: some View {
        settingsGroup(title: "Clinic defaults", systemImage: "cross.case", note: "Defaults for Sable's Clinic repair passes. The first inventory stays read-only; repair rows still need review and apply.") {
            settingToggle("Write EPUB metadata", detail: "Checked repair rows can copy local ComicInfo, RanobeDB, MangaBaka, identifiers, clean tags, series, and book-level facts into EPUB package metadata. A temporary rebuilt EPUB is validated before replacement.", isOn: $pipelineStageOptions.writeEPUBImportMetadata)
            settingToggle("Save receipts", detail: "Writes plain-text receipts and repair notes into the report folder when a checked row changes an EPUB. If this is off or unavailable, the app cannot save the same recovery trail for that run.", isOn: $pipelineStageOptions.exportReports)
            SableLibraryInfoBanner(
                text: "Sable's Clinic owns non-cover EPUB repair. Cover discovery, quality upgrades, cover replacement, and Apple Books cover refresh live in Sable's Covers.",
                role: .info,
                systemImage: "rectangle.2.swap"
            )
        }
    }

    private var clinicRepairSection: some View {
        settingsGroup(title: "Repair depth", systemImage: "wrench.and.screwdriver", note: "Choose how deeply Sable's Clinic opens EPUB internals after the light inventory.") {
            settingToggle("Deep EPUB content checks", detail: "Default for broad Clinic runs. The Clinic page can still run lighter metadata, package, navigation, or content-only passes. Cover work stays in Sable's Covers.", isOn: $pipelineStageOptions.deepEPUBContentChecks)
            settingToggle("Optimize page-image EPUBs (lossy)", detail: "Review-first option for fixed-layout manga or page-image EPUBs. It can downscale oversized pages, never crops, skips covers, and skips pages already near the safe minimum.", isOn: $pipelineStageOptions.optimizePageImageEPUBs)
            SableLibraryInfoBanner(
                text: "Keep deep checks off for fast lists. Turn them on when you are doing a dedicated repair pass and have time for a slower scan.",
                role: .info,
                systemImage: "gauge.with.dots.needle.bottom.50percent"
            )
        }
    }

    private var folderOrganizationDepthPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Reading folder depth")
                .font(.callout.weight(.medium))
            Picker("Reading folder depth", selection: $cleanupOptions.readingFolderOrganizationDepth) {
                ForEach(SableLibraryFolderOrganizationDepth.allCases) { depth in
                    Text(depth.label).tag(depth)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!cleanupOptions.renameFolders)
            .accessibilityHint("Chooses the default folder sorting layout for reading series.")

            Text(cleanupOptions.readingFolderOrganizationDepth.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var preferredTitleStylePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Preferred sidecar name")
                .font(.callout.weight(.medium))
            Picker("Preferred sidecar name", selection: $pipelineStageOptions.preferredTitleStyle) {
                ForEach(SableLibraryPreferredTitleStyle.allCases) { style in
                    Text(style.label).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!pipelineStageOptions.useComicInfoTitles)
            .accessibilityHint("Chooses which trusted sidecar title style Sable uses for folder and file suggestions.")

            Text(pipelineStageOptions.preferredTitleStyle.helpText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var providerAccessSection: some View {
        settingsGroup(title: "Optional providers", systemImage: "key", note: "Local files first. Network providers run only for checked metadata rows.") {
            VStack(alignment: .leading, spacing: 8) {
                providerStatusLine(
                    title: "Works without keys",
                    detail: "MangaBaka, RanobeDB, Open Library, Wikidata, and AniList can run during checked metadata apply rows when their review-tool switches are on. Fresh unchanged sidecars skip repeat calls.",
                    systemImage: "checkmark.circle"
                )
                providerStatusLine(
                    title: "Optional keyed sources",
                    detail: "TMDB and TVDB stay quiet unless a future lookup needs their access key. AniList is the active anime-adjacent bridge for reading metadata.",
                    systemImage: "key.horizontal"
                )
            }

            Divider()

            DisclosureGroup(isExpanded: $showProviderKeys) {
                VStack(alignment: .leading, spacing: 10) {
                    if mode == .covers {
                        providerCredentialField(
                            title: "MangaBaka personal access token",
                            detail: "Used only by MangaBaka Studio to load contributor snapshots, preview cover changes, and submit them. Personal tokens begin with mb-.",
                            text: $providerCredentials.mangaBakaPersonalAccessToken
                        )

                        Divider()

                        rolerContributorAccessControls

                        Divider()
                    }

                    if mode != .covers {
                        providerCredentialField(
                            title: "TMDB token or API key",
                            detail: "Used for movie and TV metadata when TMDB support is enabled.",
                            text: $providerCredentials.tmdbAccessToken
                        )
                        providerCredentialField(
                            title: "TVDB bearer token",
                            detail: "Used for TVDB metadata when TVDB support is enabled.",
                            text: $providerCredentials.tvdbAccessToken
                        )
                    }

                    settingsActionButton(
                        "Clear Provider Keys",
                        systemImage: "xmark.circle",
                        role: .destructive,
                        isDisabled: !providerCredentials.hasAnyCredential,
                        accessibilityHint: "Removes saved provider keys from this Mac."
                    ) {
                        pendingDestructiveAction = .clearProviderCredentials
                    }

                    SableLibraryInfoBanner(
                        text: "Provider keys are stored in the Mac keychain. Sable does not write them into ComicInfo, AnimeInfo, reports, receipts, or local learning files. Clearing keys does not turn off public no-key providers.",
                        role: .info,
                        systemImage: "lock"
                    )
                }
                .padding(.top, 8)
            } label: {
                Text(showProviderKeys ? "Hide Provider Keys" : providerKeysDisclosureTitle)
                    .font(.callout.weight(.medium))
            }
            .accessibilityHint("Shows optional API key fields and the clear keys action.")
        }
    }

    private var rolerContributorAccessControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Roler contributor access")
                        .font(.callout.weight(.medium))

                    if let session = rolerContributorSession {
                        Label(
                            "\(session.accountLabel) · \(session.role.capitalized)",
                            systemImage: "checkmark.shield"
                        )
                        .font(.caption)
                        .foregroundStyle(
                            session.canEdit
                                ? palette.statusSuccess
                                : palette.statusWarning
                        )
                    } else if isCheckingRolerContributorAccess {
                        Label("Checking contributor access…", systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(
                            "Sign in with the MangaBaka account that has your contributor role."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 12)

                if rolerContributorSession == nil {
                    Button {
                        rolerContributorAccessError = nil
                        showRolerContributorLogin = true
                    } label: {
                        Label("Sign In", systemImage: "person.badge.key")
                    }
                    .disabled(isCheckingRolerContributorAccess)
                    .help(
                        "Sign in through MangaBaka OAuth. Sable never receives your MangaBaka password."
                    )
                } else {
                    Button("Sign Out", action: signOutOfRoler)
                        .help(
                            "Remove Roler contributor access from this Mac."
                        )
                }
            }

            Toggle(
                "Share accepted series matches with Roler",
                isOn: $shareConfirmedMatchesWithRoler
            )
            .disabled(rolerContributorSession?.canEdit != true)
            .accessibilityHint(
                "When enabled, a successful direct MangaBaka cover apply shares only its confirmed MangaBaka and store series identifiers. Rejections and library details stay on this Mac."
            )

            Text(
                "Accept Series is only a local approval. After MangaBaka accepts a direct cover update, Sable sends its confirmed MangaBaka ID and store-series IDs through BBC's automatic mapping. Reject Series remains local. Titles, cover images, file paths, and library activity are never included."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            if let rolerContributorAccessError {
                Label(
                    rolerContributorAccessError,
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task {
            await refreshRolerContributorSession()
        }
    }

    private func completeRolerContributorLogin(
        userToken: String,
        sessionID: String
    ) {
        var updatedCredentials = providerCredentials
        updatedCredentials.rolerUserToken = userToken
        updatedCredentials.rolerSessionID = sessionID
        SableLibraryUserSettings().saveProviderCredentials(
            updatedCredentials
        )
        let persistedCredentials =
            SableLibraryUserSettings().loadProviderCredentials()
        let persistedRolerCredentials =
            persistedCredentials.rolerContributorCredentials
        let expectedRolerCredentials =
            updatedCredentials.rolerContributorCredentials
        guard persistedRolerCredentials == expectedRolerCredentials else {
            providerCredentials = persistedCredentials
            rolerContributorSession = nil
            rolerContributorAccessError =
                "Roler sign-in could not be saved securely on this Mac. Rebuild or sign the app with Keychain access, then try again."
            showRolerContributorLogin = false
            return
        }

        providerCredentials = persistedCredentials
        showRolerContributorLogin = false
        Task {
            await refreshRolerContributorSession()
        }
    }

    @MainActor
    private func refreshRolerContributorSession() async {
        let credentials =
            providerCredentials.rolerContributorCredentials
        guard credentials.isAvailable else {
            rolerContributorSession = nil
            rolerContributorAccessError = nil
            isCheckingRolerContributorAccess = false
            return
        }

        isCheckingRolerContributorAccess = true
        rolerContributorAccessError = nil
        defer { isCheckingRolerContributorAccess = false }

        do {
            rolerContributorSession = try await rolerContributorClient
                .contributorSession(credentials: credentials)
        } catch {
            rolerContributorSession = nil
            rolerContributorAccessError = error.localizedDescription
        }
    }

    private func signOutOfRoler() {
        let credentials =
            providerCredentials.rolerContributorCredentials
        providerCredentials.rolerUserToken = ""
        providerCredentials.rolerSessionID = ""
        SableLibraryUserSettings().saveProviderCredentials(
            providerCredentials
        )
        rolerContributorSession = nil
        rolerContributorAccessError = nil
        Task {
            await rolerContributorClient.logout(credentials: credentials)
        }
    }

    private var learningSection: some View {
        settingsGroup(title: "Learning", systemImage: "brain", note: "Local hints from choices you make on this Mac.") {
            settingToggle(
                "Use local learning",
                detail: "Lets remembered choices influence future review suggestions on this Mac. Turn this off when you want only deterministic rules for a pass.",
                isOn: $intelligenceOptions.useLocalLearning
            )
            settingToggle(
                "Improve review notes",
                detail: "Lets available on-device assist features make review notes easier to read. Provider metadata still needs explicit review rows.",
                isOn: $intelligenceOptions.improveSuggestions
            )
            SableLibraryInfoBanner(
                text: "Current memory: \(learningMemorySummary). Teach Sable by choosing Teach Type or Teach Folder, marking PDFs as document/book-like, entering exact provider IDs, and applying rows you trust.",
                role: .info,
                systemImage: "graduationcap"
            )
            DisclosureGroup(isExpanded: $showPersonalModelControls) {
                personalModelTrainingControls
                    .padding(.top, 8)
            } label: {
                Text(showPersonalModelControls ? "Hide Personal Model Training" : personalModelDisclosureTitle)
                    .font(.callout.weight(.medium))
            }
            .accessibilityHint("Shows local personal-model training controls and status.")
        }
    }

    private var clinicLearningSection: some View {
        settingsGroup(title: "Clinic learning", systemImage: "brain", note: "On-device help for clearer EPUB repair review notes.") {
            settingToggle(
                "Improve review notes",
                detail: "Lets available on-device assist features make Clinic repair notes easier to read. EPUB files still need checked rows before repair.",
                isOn: $intelligenceOptions.improveSuggestions
            )
        }
    }

    private var learningMemorySummary: String {
        guard intelligenceOptions.useLocalLearning else {
            return hasLearningMemory
                ? "off; saved choices are kept until you reset them"
                : "off"
        }
        guard let learnedDecisionCount else {
            return "checking remembered choices"
        }
        return "\(learnedDecisionCount) remembered decision\(learnedDecisionCount == 1 ? "" : "s")"
    }

    private var providerKeysDisclosureTitle: String {
        providerCredentials.hasAnyCredential ? "Manage Saved Provider Keys" : "Add Optional Provider Keys"
    }

    private var personalModelDisclosureTitle: String {
        if isTrainingPersonalModel {
            return "Personal Model Training in Progress"
        }
        if personalTrainingError != nil {
            return "Personal Model Needs Attention"
        }
        if personalTrainingResult != nil {
            return "Personal Model Updated"
        }
        if personalModelExists {
            return "Manage Personal Model"
        }
        return "Train Personal Model"
    }

    private var personalModelTrainingControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                settingsActionButton(
                    isTrainingPersonalModel ? "Retraining from Local Data" : "Retrain from Local Data",
                    systemImage: isTrainingPersonalModel ? "hourglass" : "graduationcap",
                    isProminent: true,
                    isDisabled: !hasSavedLibrary || isTrainingPersonalModel,
                    accessibilityHint: "Uses local training material to build a personal cleanup model on this Mac."
                ) {
                    showPersonalTrainingWarning = true
                }

                if isTrainingPersonalModel {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Training in progress")
                }
            }

            Text("Uses your saved library's training notes to build a personal model in Sable's shared local support folder. Sable uses it only on this Mac when local learning is on.")
                .font(.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if !hasSavedLibrary {
                SableLibraryInfoBanner(
                    text: "Choose and save a library folder before training a personal model.",
                    role: .warning,
                    systemImage: "folder.badge.questionmark"
                )
            } else if let personalTrainingResult {
                SableLibraryInfoBanner(
                    text: "\(personalTrainingResult.summary) Sable will use it for local ML hints when local learning is on.",
                    role: .success,
                    systemImage: "checkmark.seal"
                )
            } else if personalModelExists {
                SableLibraryInfoBanner(
                    text: "A personal model is already available on this Mac. Training again replaces that personal copy only.",
                    role: .info,
                    systemImage: "brain"
                )
            }

            if let personalTrainingError {
                SableLibraryInfoBanner(
                    text: personalTrainingError,
                    role: .error,
                    systemImage: "exclamationmark.triangle"
                )
            }

            SableLibraryInfoBanner(
                text: "Local only: retraining reads Sable's local training notes and writes a personal model on this Mac. It never changes files during training.",
                role: .warning,
                systemImage: "lock.shield"
            )
        }
    }

    private func providerStatusLine(title: String, detail: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(palette.accent)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func providerCredentialField(title: String, detail: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.callout.weight(.medium))
            SecureField("Optional", text: text)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(title)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var libraryAdvancedSection: some View {
        settingsGroup(title: "Advanced", systemImage: "slider.horizontal.3", note: "Slower evidence and repair options.") {
            DisclosureGroup(isExpanded: $showAdvancedSettings) {
                VStack(alignment: .leading, spacing: 10) {
                    settingToggle("Check exact duplicates", detail: "Slower but stronger. Files with the same size are fingerprinted before Sable calls them duplicates.", isOn: $cleanupOptions.checkDuplicates)
                    settingToggle(
                        "Prepare saved provider refresh",
                        detail: "Adds one review row per series. Saved provider IDs are refreshed; RanobeDB adds new books and fills only missing book details.",
                        isOn: $pipelineStageOptions.refreshComicInfo
                    )
                    SableLibraryInfoBanner(
                        text: "Safety tip: exact duplicate checks and ComicInfo refreshes can take longer, but they still prepare review rows before changing files.",
                        role: .info,
                        systemImage: "arrow.clockwise"
                    )
                }
                .padding(.top, 8)
            } label: {
                Text(showAdvancedSettings ? "Hide Advanced Choices" : "Show Advanced Choices")
                    .font(.callout.weight(.medium))
            }
            .accessibilityHint("Shows slower checks and richer repair options for advanced cleanup passes.")
        }
    }

    private var safetySection: some View {
        settingsGroup(title: "Recovery", systemImage: "shield.checkered", note: "Reset choices or forget the saved \(mode == .clinic ? "EPUB folder" : "library folder"). These do not delete files.") {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    recoveryButtons
                }

                VStack(alignment: .leading, spacing: 10) {
                    recoveryButtons
                }
            }
        }
    }

    private var helpSection: some View {
        settingsGroup(title: "Guide", systemImage: "questionmark.circle", note: "Open the short welcome guide again.") {
            settingsActionButton(
                "Show Welcome Guide",
                systemImage: "books.vertical",
                accessibilityHint: "Opens the optional onboarding guide.",
                action: onShowOnboarding
            )
        }
    }

    @ViewBuilder
    private var recoveryButtons: some View {
        settingsActionButton(
            "Reset Defaults",
            systemImage: "arrow.counterclockwise",
            role: .destructive,
            accessibilityHint: "Restores \(mode.appName) settings to safe defaults."
        ) {
            pendingDestructiveAction = .resetDefaults
        }

        settingsActionButton(
            "Reset Learning",
            systemImage: "brain.head.profile",
            role: .destructive,
            isDisabled: (learnedDecisionCount ?? 0) == 0 && !hasLearningMemory,
            accessibilityHint: "Forgets remembered review choices. It does not change files."
        ) {
            pendingDestructiveAction = .resetLearning
        }

        settingsActionButton(
            hasSavedLibrary ? "Forget Folder" : "No Saved Folder",
            systemImage: "folder",
            role: .destructive,
            isDisabled: !hasSavedLibrary,
            accessibilityHint: "Removes the remembered \(mode == .clinic ? "EPUB folder" : "library folder"). It does not delete files."
        ) {
            pendingDestructiveAction = .forgetLibrary
        }
    }

    private func settingsActionButton(
        _ title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        isProminent: Bool = false,
        isDisabled: Bool = false,
        accessibilityHint: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Label(title, systemImage: systemImage)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(minWidth: 150, alignment: .center)
        }
        .modifier(SableLibrarySettingsActionButtonStyle(isProminent: isProminent))
        .controlSize(.regular)
        .disabled(isDisabled)
        .accessibilityHint(accessibilityHint)
    }

    private func settingsGroup<Content: View>(title: String, systemImage: String, note: String, @ViewBuilder content: () -> Content) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label(title, systemImage: systemImage)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func settingToggle(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.switch)
        .accessibilityHint(detail)
    }

    private func perform(_ action: DestructiveSettingsAction) {
        switch action {
        case .resetDefaults:
            onResetOptions()
        case .resetLearning:
            onResetLearning()
        case .clearProviderCredentials:
            onClearProviderCredentials()
        case .forgetLibrary:
            onForgetLibrary()
        }
        pendingDestructiveAction = nil
    }
}

private enum DestructiveSettingsAction: Identifiable {
    case resetDefaults
    case resetLearning
    case clearProviderCredentials
    case forgetLibrary

    var id: String {
        switch self {
        case .resetDefaults: "resetDefaults"
        case .resetLearning: "resetLearning"
        case .clearProviderCredentials: "clearProviderCredentials"
        case .forgetLibrary: "forgetLibrary"
        }
    }

    func title(for mode: SableLibraryAppMode) -> String {
        switch self {
        case .resetDefaults: "Reset cleanup defaults?"
        case .resetLearning: "Reset Sable learning?"
        case .clearProviderCredentials: "Clear provider keys?"
        case .forgetLibrary: mode == .clinic ? "Forget saved EPUB folder?" : "Forget saved library folder?"
        }
    }

    func confirmationTitle(for mode: SableLibraryAppMode) -> String {
        switch self {
        case .resetDefaults: "Reset Defaults"
        case .resetLearning: "Reset Learning"
        case .clearProviderCredentials: "Clear Keys"
        case .forgetLibrary: "Forget Folder"
        }
    }

    func message(for mode: SableLibraryAppMode) -> String {
        switch self {
        case .resetDefaults:
            "This restores \(mode.appName) settings to safe defaults. It does not change files, receipts, or the saved folder."
        case .resetLearning:
            "This forgets remembered review choices. It does not change files."
        case .clearProviderCredentials:
            "This removes saved provider keys from this Mac. Public no-key providers still work when their review-tool switches are enabled."
        case .forgetLibrary:
            "This removes the saved folder from app settings. It does not delete or move anything in the folder."
        }
    }
}

private struct SableLibrarySettingsActionButtonStyle: ViewModifier {
    let isProminent: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isProminent {
            content
                .buttonStyle(.borderedProminent)
        } else {
            content
                .buttonStyle(.bordered)
        }
    }
}

private struct SableLibrarySettingsStatus: Sendable {
    let learnedDecisionCount: Int?
    let hasLearningMemory: Bool
    let hasSavedLibrary: Bool
    let personalModelExists: Bool
}

struct SableLibrarySettingsHostView: View {
    let mode: SableLibraryAppMode

    @State private var cleanupOptions: CleanupOptions
    @State private var pipelineStageOptions: LibraryPipelineStageOptions
    @State private var intelligenceOptions: SableLibraryIntelligenceOptions
    @State private var providerCredentials: SableLibraryProviderCredentials
    @State private var learnedDecisionCount: Int?
    @State private var hasLearningMemory: Bool
    @State private var hasSavedLibrary: Bool
    @State private var isLoadingLearningStatus = false
    @State private var isTrainingPersonalModel = false
    @State private var personalTrainingResult: SableLibraryPersonalModelTrainingResult?
    @State private var personalTrainingError: String?
    @State private var personalModelExists: Bool

    private let settings = SableLibraryUserSettings()

    init(mode: SableLibraryAppMode = .library) {
        self.mode = mode
        let settings = SableLibraryUserSettings()
        _cleanupOptions = State(initialValue: settings.loadCleanupOptions())
        _pipelineStageOptions = State(initialValue: settings.loadPipelineStageOptions())
        _intelligenceOptions = State(initialValue: settings.loadIntelligenceOptions())
        _providerCredentials = State(initialValue: settings.loadProviderCredentials())
        _learnedDecisionCount = State(initialValue: nil)
        _hasLearningMemory = State(initialValue: false)
        _hasSavedLibrary = State(initialValue: false)
        _personalModelExists = State(initialValue: FileManager.default.fileExists(atPath: SableLibraryPersonalModelStore.modelURL.path(percentEncoded: false)))
    }

    var body: some View {
        SableLibrarySettingsView(
            cleanupOptions: $cleanupOptions,
            pipelineStageOptions: $pipelineStageOptions,
            intelligenceOptions: $intelligenceOptions,
            providerCredentials: $providerCredentials,
            mode: mode,
            hasSavedLibrary: hasSavedLibrary,
            learnedDecisionCount: learnedDecisionCount,
            hasLearningMemory: hasLearningMemory,
            isTrainingPersonalModel: isTrainingPersonalModel,
            personalTrainingResult: personalTrainingResult,
            personalTrainingError: personalTrainingError,
            personalModelExists: personalModelExists,
            onForgetLibrary: forgetSavedLibraryFolder,
            onResetOptions: resetToolSettings,
            onResetLearning: resetLearningMemory,
            onClearProviderCredentials: clearProviderCredentials,
            onTrainPersonalModel: trainPersonalModel,
            onRequestLearningStatus: refreshLearningStatus,
            onShowOnboarding: showOnboarding,
            onClose: nil
        )
        .onAppear(perform: reloadSavedControls)
        .onChange(of: cleanupOptions) { _, newValue in
            settings.saveCleanupOptions(newValue)
            postSettingsChanged()
        }
        .onChange(of: pipelineStageOptions) { _, newValue in
            settings.savePipelineStageOptions(newValue)
            postSettingsChanged()
        }
        .onChange(of: intelligenceOptions) { _, newValue in
            settings.saveIntelligenceOptions(newValue)
            postSettingsChanged()
        }
        .onChange(of: providerCredentials) { _, newValue in
            settings.saveProviderCredentials(newValue)
            postSettingsChanged()
        }
    }

    private func reloadSavedControls() {
        cleanupOptions = settings.loadCleanupOptions()
        pipelineStageOptions = settings.loadPipelineStageOptions()
        intelligenceOptions = settings.loadIntelligenceOptions()
        providerCredentials = settings.loadProviderCredentials()
        personalModelExists = FileManager.default.fileExists(atPath: SableLibraryPersonalModelStore.modelURL.path(percentEncoded: false))
    }

    private func refreshLearningStatus() {
        guard !isLoadingLearningStatus else { return }
        isLoadingLearningStatus = true
        let shouldLoadLearningCount = mode == .library && intelligenceOptions.useLocalLearning
        Task {
            let status = await Task.detached(priority: .utility) {
                let settings = SableLibraryUserSettings()
                let hasLearningMemory = settings.hasLearningMemory()
                return SableLibrarySettingsStatus(
                    learnedDecisionCount: shouldLoadLearningCount
                        ? settings.loadLearningMemory().learnedDecisionCount
                        : nil,
                    hasLearningMemory: hasLearningMemory,
                    hasSavedLibrary: settings.loadLibraryFolder() != nil,
                    personalModelExists: FileManager.default.fileExists(atPath: SableLibraryPersonalModelStore.modelURL.path(percentEncoded: false))
                )
            }.value

            await MainActor.run {
                learnedDecisionCount = status.learnedDecisionCount
                hasLearningMemory = status.hasLearningMemory
                hasSavedLibrary = status.hasSavedLibrary
                personalModelExists = status.personalModelExists
                isLoadingLearningStatus = false
            }
        }
    }

    private func resetToolSettings() {
        settings.resetToolOptions()
        cleanupOptions = CleanupOptions()
        pipelineStageOptions = LibraryPipelineStageOptions()
        intelligenceOptions = SableLibraryIntelligenceOptions()
        postSettingsChanged()
    }

    private func resetLearningMemory() {
        settings.clearLearningMemory()
        learnedDecisionCount = 0
        hasLearningMemory = false
        postSettingsChanged()
    }

    private func clearProviderCredentials() {
        settings.clearProviderCredentials()
        providerCredentials = SableLibraryProviderCredentials()
        postSettingsChanged()
    }

    private func forgetSavedLibraryFolder() {
        settings.clearLibraryFolder()
        hasSavedLibrary = false
        postSettingsChanged()
    }

    private func showOnboarding() {
        guard mode.showsOnboarding else { return }
        NotificationCenter.default.post(name: .sableLibraryShowOnboarding, object: nil)
    }

    private func trainPersonalModel() {
        guard !isTrainingPersonalModel else { return }
        guard let libraryURL = settings.loadLibraryFolder() else {
            personalTrainingError = SableLibraryPersonalModelTrainingError.missingLibrary.localizedDescription
            return
        }

        isTrainingPersonalModel = true
        personalTrainingError = nil
        personalTrainingResult = nil

        Task {
            let config = SableLibraryService().currentConfig()
            let result: Result<SableLibraryPersonalModelTrainingResult, Error>
            result = await Task.detached(priority: .userInitiated) {
                let memory = SableLibraryUserSettings().loadLearningMemory()
                #if os(macOS)
                let didAccess = libraryURL.startAccessingSecurityScopedResource()
                #else
                let didAccess = false
                #endif
                defer {
                    #if os(macOS)
                    if didAccess {
                        libraryURL.stopAccessingSecurityScopedResource()
                    }
                    #endif
                }
                do {
                    return .success(try SableLibraryPersonalModelTrainer().train(
                        root: libraryURL,
                        config: config,
                        learningMemory: memory
                    ))
                } catch {
                    return .failure(error)
                }
            }.value

            await MainActor.run {
                isTrainingPersonalModel = false
                switch result {
                case .success(let trainingResult):
                    personalTrainingResult = trainingResult
                    personalModelExists = true
                    NotificationCenter.default.post(name: .sableLibraryPersonalModelChanged, object: nil)
                    postSettingsChanged()
                case .failure(let error):
                    personalTrainingError = error.localizedDescription
                }
            }
        }
    }

    private func postSettingsChanged() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .sableLibrarySettingsChanged, object: nil)
        }
    }
}
