//
//  SableLibrarySidebarView.swift
//  Sable's Library
//

import SwiftUI

struct SableLibrarySidebarView: View {
    @Environment(\.sableLibraryPalette) private var palette

    let libraryURL: URL?
    let status: String
    let isRunning: Bool
    let learnedDecisionCount: Int
    @State private var selectedDetail: SableLibrarySidebarDetail?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                libraryFolderSection
                workflowSection
                safetySection
                privacySection
                assistSection
                statusSection
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .sableLibraryNavigationLayer()
        .navigationSplitViewColumnWidth(min: 340, ideal: 390, max: 470)
        .sheet(item: $selectedDetail) { detail in
            sidebarDetailSheet(detail)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(palette.accent)
                .frame(width: 56, height: 56, alignment: .leading)
                .accessibilityHidden(true)

            Text("Sable's Library")
                .font(.largeTitle.bold())
                .lineLimit(2)

            Text(status)
                .font(.title3.weight(.semibold))
                .foregroundStyle(isRunning ? palette.accent : palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if libraryURL == nil {
                Text("Step 1: choose the top folder for your library. The first pass only inspects.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sable's Library")
        .accessibilityValue(status)
    }

    private var libraryFolderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Current Library Folder", systemImage: "folder")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text(libraryURL?.lastPathComponent ?? "No library folder selected")
                    .font(.title3.bold())
                    .foregroundStyle(libraryURL == nil ? palette.textSecondary : palette.textPrimary)
                    .lineLimit(2)

                Text(libraryURL?.path(percentEncoded: false) ?? "Choose a folder to give the app a bounded collection to inspect.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(6)
                    .textSelection(.enabled)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sableLibrarySurface(
                fill: palette.surfaceRaised,
                border: palette.border,
                glassProminence: .none,
                glassIntensity: .thin
            )

            Label(libraryURL == nil ? "Waiting for a library folder" : "Ready for read-only inspect", systemImage: libraryURL == nil ? "folder.badge.questionmark" : "checkmark.seal")
                .font(.callout.weight(.medium))
                .foregroundStyle(libraryURL == nil ? palette.textSecondary : palette.accent)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .sableLibrarySurface(
            fill: palette.surface,
            border: palette.border,
            glassTint: palette.accent,
            glassProminence: .decorative,
            glassIntensity: .regular
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Current library folder")
        .accessibilityValue(libraryURL?.path(percentEncoded: false) ?? "No folder selected")
    }

    private var workflowSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("How Sable Works", systemImage: "books.vertical")
                .font(.headline)

            sidebarNumberedNote(1, detail: .chooseFolder)
            sidebarNumberedNote(2, detail: .inspectLocally)
            sidebarNumberedNote(3, detail: .cleanSidecars)
            sidebarNumberedNote(4, detail: .teachProviders)
            sidebarNumberedNote(5, detail: .renameAndSort)
            sidebarNumberedNote(6, detail: .repairAndReceipts)
        }
        .padding(14)
        .sableLibraryPanelSurface()
    }

    private var safetySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Careful by Default", systemImage: "shield.checkered")
                .font(.headline)

            sidebarNote(.inspectSafety)
            sidebarNote(.conflictsStayOut)
            sidebarNote(.receiptsMatter)
        }
        .padding(14)
        .sableLibraryPanelSurface()
    }

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Privacy", systemImage: "lock.shield")
                .font(.headline)

            sidebarNote(.libraryFilesLocal)
            sidebarNote(.mangaBakaOptional)
            sidebarNote(.receiptsStayLocal)
        }
        .padding(14)
        .sableLibraryPanelSurface()
    }

    private var assistSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Assist", systemImage: "sparkles")
                .font(.headline)

            sidebarNote(.appleIntelligenceAssist)
            sidebarNote(.localLearningAssist)
            sidebarNote(.trainingMaterial)
        }
        .padding(14)
        .sableLibraryPanelSurface()
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(isRunning ? "At Work" : "Desk Status", systemImage: isRunning ? "clock" : "sparkles.rectangle.stack")
                .font(.headline)

            Text(isRunning ? "The app is working through one visible stage. Stop waits for the current file or network request to settle." : "Choose a library folder, inspect, then handle one stage at a time.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .sableLibraryPanelSurface()
    }

    private func sidebarNote(_ detail: SableLibrarySidebarDetail) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: detail.symbol)
                .foregroundStyle(palette.accent)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(detail.title)
                    .font(.callout.weight(.medium))
                Text(summary(for: detail))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            detailButton(detail)
        }
        .accessibilityElement(children: .contain)
    }

    private func sidebarNumberedNote(_ number: Int, detail: SableLibrarySidebarDetail) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(palette.accent.opacity(0.16))
                Text("\(number)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(palette.accent)
            }
            .frame(width: 28, height: 28)
            .accessibilityHidden(true)

            Image(systemName: detail.symbol)
                .foregroundStyle(palette.accent)
                .frame(width: 22)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(detail.title)
                    .font(.callout.weight(.medium))
                Text(summary(for: detail))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            detailButton(detail)
        }
        .accessibilityElement(children: .contain)
    }

    private func detailButton(_ detail: SableLibrarySidebarDetail) -> some View {
        Button {
            selectedDetail = detail
        } label: {
            Image(systemName: "info.circle")
                .font(.callout.weight(.semibold))
                .foregroundStyle(palette.accent)
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Open a clearer explanation about \(detail.title).")
        .accessibilityLabel("Open a clearer explanation about \(detail.title)")
    }

    private func sidebarDetailSheet(_ detail: SableLibrarySidebarDetail) -> some View {
        ZStack {
            SableLibraryAmbientBackdrop()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 14) {
                        sidebarLectureSableMark

                        VStack(alignment: .leading, spacing: 5) {
                            Text("How this works")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(palette.accent)
                            Text(detail.title)
                                .font(.title2.bold())
                            Text(summary(for: detail))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()

                        Button("Done") {
                            selectedDetail = nil
                        }
                        .keyboardShortcut(.defaultAction)
                    }

                    ForEach(detail.sections(learnedDecisionCount: learnedDecisionCount, availability: intelligenceAvailability)) { section in
                        sidebarDetailCard(section)
                    }
                }
                .padding(24)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .sableLibrarySurface(
                fill: palette.surface,
                border: palette.accent.opacity(0.30),
                glassTint: palette.accent,
                glassProminence: .decorative,
                glassIntensity: .prominent
            )
            .padding(24)
        }
        .frame(minWidth: 680, minHeight: 540)
        .sableLibraryWindowMirrorEffect()
    }

    private var sidebarLectureSableMark: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 52, weight: .semibold))
                .foregroundStyle(palette.accent)
                .frame(width: 88, height: 112)

            Image(systemName: "doc.richtext")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(palette.accent)
                .padding(6)
                .sableLibrarySurface(
                    fill: palette.surfaceRaised,
                    border: palette.border,
                    cornerRadius: 6,
                    glassTint: palette.accent,
                    glassProminence: .decorative,
                    glassIntensity: .ultraThin
                )
        }
        .frame(width: 104, height: 118, alignment: .center)
        .accessibilityHidden(true)
    }

    private func sidebarDetailCard(_ section: SableLibrarySidebarDetailSection) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: section.symbol)
                .font(.headline)
                .foregroundStyle(palette.accent)
                .frame(width: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(section.title)
                    .font(.headline)
                Text(section.text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sableLibraryRaisedPanelSurface()
        .accessibilityElement(children: .combine)
    }

    private var intelligenceAvailability: SableLibraryIntelligenceAvailability {
        SableLibraryIntelligence.availability
    }

    private func summary(for detail: SableLibrarySidebarDetail) -> String {
        detail.summary(learnedDecisionCount: learnedDecisionCount, availability: intelligenceAvailability)
    }

}

private struct SableLibrarySidebarDetailSection: Identifiable {
    let id = UUID()
    var title: String
    var symbol: String
    var text: String
}

private enum SableLibrarySidebarDetail: String, Identifiable {
    case chooseFolder
    case inspectLocally
    case cleanSidecars
    case teachProviders
    case renameAndSort
    case repairAndReceipts
    case reviewNotes
    case applyCheckedRows
    case inspectSafety
    case conflictsStayOut
    case receiptsMatter
    case libraryFilesLocal
    case mangaBakaOptional
    case receiptsStayLocal
    case appleIntelligenceAssist
    case localLearningAssist
    case trainingMaterial

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chooseFolder: "Choose a library folder"
        case .inspectLocally: "Inspect locally"
        case .cleanSidecars: "Clean sidecars"
        case .teachProviders: "Teach providers"
        case .renameAndSort: "Rename and sort"
        case .repairAndReceipts: "Repair EPUBs and save receipts"
        case .reviewNotes: "Review cleanup suggestions"
        case .applyCheckedRows: "Apply checked rows"
        case .inspectSafety: "Nothing moves during inspect"
        case .conflictsStayOut: "Conflicts stay out"
        case .receiptsMatter: "Receipts matter"
        case .libraryFilesLocal: "Library files stay local"
        case .mangaBakaOptional: "Providers are optional"
        case .receiptsStayLocal: "Receipts stay with the collection"
        case .appleIntelligenceAssist: "Apple Intelligence"
        case .localLearningAssist: "Local learning"
        case .trainingMaterial: "Training material"
        }
    }

    func summary(learnedDecisionCount: Int, availability: SableLibraryIntelligenceAvailability) -> String {
        switch self {
        case .chooseFolder:
            "Pick the top folder that holds this media library."
        case .inspectLocally:
            "Names, file types, paths, and metadata clues are read before anything changes."
        case .cleanSidecars:
            "ComicInfo and AnimeInfo cleanup tidies local metadata notes without moving files."
        case .teachProviders:
            "Provider Matches saves exact IDs or learned No ID choices separately from refresh."
        case .renameAndSort:
            "Folder and filename changes stay in their own review pages with final paths."
        case .repairAndReceipts:
            "EPUB repair writes temporary files first, then receipts explain what changed."
        case .reviewNotes:
            "Rows show proposed outcomes with reasons, safety labels, and check or skip controls."
        case .applyCheckedRows:
            "Only checked safe changes apply. Check Again can verify fresh paths afterward."
        case .inspectSafety:
            "The first pass reads and explains. It should not move or rename files."
        case .conflictsStayOut:
            "Collision and network-backed rows stay excluded until reviewed."
        case .receiptsMatter:
            "File-changing work is paired with receipts or undo notes when possible."
        case .libraryFilesLocal:
            "Library checks read the selected folder on this Mac."
        case .mangaBakaOptional:
            "Checked metadata rows can use providers during apply; fresh unchanged sidecars stay quiet."
        case .receiptsStayLocal:
            "Reports and undo notes are saved inside the selected library folder."
        case .appleIntelligenceAssist:
            "\(availability.title). Review notes only; file changes still need approval."
        case .localLearningAssist:
            "Local learning has \(learnedDecisionCount) remembered decision\(learnedDecisionCount == 1 ? "" : "s"), stored on this Mac."
        case .trainingMaterial:
            "Corrections, checked safe applies, and skipped weak matches become lessons for future review."
        }
    }

    var symbol: String {
        switch self {
        case .chooseFolder: "folder"
        case .inspectLocally: "magnifyingglass"
        case .cleanSidecars: "doc.text.magnifyingglass"
        case .teachProviders: "person.text.rectangle"
        case .renameAndSort: "folder.badge.gearshape"
        case .repairAndReceipts: "wrench.and.screwdriver"
        case .reviewNotes: "list.bullet.rectangle"
        case .applyCheckedRows: "checkmark.seal"
        case .inspectSafety: "eye"
        case .conflictsStayOut: "exclamationmark.triangle"
        case .receiptsMatter: "doc.text"
        case .libraryFilesLocal: "externaldrive"
        case .mangaBakaOptional: "network"
        case .receiptsStayLocal: "doc.text.magnifyingglass"
        case .appleIntelligenceAssist: "sparkles"
        case .localLearningAssist: "brain"
        case .trainingMaterial: "graduationcap"
        }
    }

    func sections(
        learnedDecisionCount: Int,
        availability: SableLibraryIntelligenceAvailability
    ) -> [SableLibrarySidebarDetailSection] {
        switch self {
        case .chooseFolder:
            [
                .init(title: "What this means", symbol: "folder", text: "The selected library folder is the one top-level folder that bounds the cleanup session. Every scan, receipt, undo plan, and review note is framed around that selected root instead of the whole Mac."),
                .init(title: "Why it matters", symbol: "shield.checkered", text: "A clear folder boundary prevents accidental whole-disk cleanup and makes the app accountable. The user can always see where Sable is allowed to look."),
                .init(title: "Setting to know", symbol: "gearshape", text: "The saved library folder can be forgotten from Settings. Forgetting it removes the app's remembered folder access; it does not delete, move, rename, or inspect anything."),
                .init(title: "Finder handoff", symbol: "arrow.up.right.square", text: "Advanced users need exact paths, not just friendly folder names. Reveal in Finder and Copy Path belong wherever the selected root, report folder, current path, or final path is shown."),
                .init(title: "Safety boundary", symbol: "lock", text: "Choosing a library folder grants a place to inspect first. File-changing work still needs review rows, checked decisions, and an apply confirmation before anything is written."),
                .init(title: "Power-user details", symbol: "slider.horizontal.3", text: "Useful diagnostics include exact root path, report destination, saved access state, whether the folder is local, external, or cloud-backed, and whether unavailable files may affect scan speed.")
            ]
        case .inspectLocally:
            [
                .init(title: "What this means", symbol: "magnifyingglass", text: "Inspection walks the selected library folder and builds a read-only picture of file types, folder depth, path names, duplicate clues, missing-number patterns, ComicInfo and AnimeInfo coverage, and safe naming hints."),
                .init(title: "Local privacy", symbol: "externaldrive", text: "The inspection pass reads the selected folder on this Mac. Local ComicInfo and AnimeInfo parsing, filename checks, duplicate clues, and folder-name suggestions should not contact outside services."),
                .init(title: "Assist context", symbol: "sparkles", text: "Apple Intelligence, when available, can help write clearer review notes. Local learning can remember repeated decisions. Neither should apply file changes or override deterministic safety checks."),
                .init(title: "Network boundary", symbol: "network", text: "MangaBaka and other network-backed work belongs in visible review rows. Inspection should not quietly fetch outside metadata just because a folder was selected."),
                .init(title: "Safety boundary", symbol: "eye", text: "Inspect stays observational: no moves, renames, deletes, repairs, metadata writes, or generated metadata commits. Anything stronger becomes a separate review item."),
                .init(title: "Power-user details", symbol: "slider.horizontal.3", text: "Useful diagnostics include file counts by type, skipped packages, unreadable paths, duplicate fingerprint scope, sidecar parse errors, cloud placeholders, and any metadata source that would need network approval.")
            ]
        case .cleanSidecars:
            [
                .init(title: "What this means", symbol: "doc.text.magnifyingglass", text: "Sidecar cleanup focuses on ComicInfo and AnimeInfo quality: title fields, aliases, accepted IDs, stale provider notes, cover URLs, descriptions, tags, freshness, and local model training clues."),
                .init(title: "What it does not do", symbol: "folder", text: "This stage should not rename folders, rename files, merge series, repair EPUB packages, or decide that a prose book belongs in the reading-provider workflow."),
                .init(title: "Why it matters", symbol: "checkmark.seal", text: "Clean sidecars give later stages a trusted local source of truth. Folder sorting and EPUB repair should read that source rather than fighting the refresh pass."),
                .init(title: "Safety boundary", symbol: "lock", text: "Cleaner rows write metadata sidecars only after they are checked. They should keep accepted provider data and remove stale scratch data without inventing new identity."),
                .init(title: "Power-user details", symbol: "slider.horizontal.3", text: "Useful cleaner details include before and after sidecar fields, removed stale keys, kept IDs, title language labels, cover source, freshness state, and training events written.")
            ]
        case .teachProviders:
            [
                .init(title: "What this means", symbol: "person.text.rectangle", text: "Provider Matches is a teaching lane. It asks whether a specific provider has the right ID for a title, or whether Sable should remember that the provider has no useful ID."),
                .init(title: "What it does not do", symbol: "arrow.triangle.branch", text: "Teaching a provider is not a folder rename and not a broad metadata refresh. It saves exact IDs or learned No ID choices so the next refresh can be lighter and more precise."),
                .init(title: "Provider treaty", symbol: "list.bullet.clipboard", text: "Reading cleanup should prefer RanobeDB for light novels, MangaBaka for manga, Open Library/Wikidata for ordinary prose, and AniList as support."),
                .init(title: "Safety boundary", symbol: "xmark.octagon", text: "High confidence still needs the expected media type and no confusing duplicate cluster. Ambiguous matches stay reviewable instead of being accepted in bulk."),
                .init(title: "Power-user details", symbol: "slider.horizontal.3", text: "Provider rows should show candidate ID, title, media type, year, cover when available, confidence reason, known missing state, and reset options.")
            ]
        case .renameAndSort:
            [
                .init(title: "What this means", symbol: "folder.badge.gearshape", text: "Folder and filename stages use trusted sidecars and local clues to propose final paths. They are where file movement and naming decisions belong."),
                .init(title: "What it does not do", symbol: "network", text: "Rename and sort should not quietly call providers or rewrite ComicInfo. If metadata is weak, the row should defer back to sidecar cleanup or provider teaching."),
                .init(title: "Why it matters", symbol: "arrow.left.arrow.right", text: "Keeping paths separate from metadata prevents refresh from fighting cleanup. The user can review path changes as path changes, with current and proposed destinations visible."),
                .init(title: "Safety boundary", symbol: "exclamationmark.triangle", text: "Collisions, case-only conflicts, merge choices, and unclear type folders stay out until the user reviews them explicitly."),
                .init(title: "Power-user details", symbol: "slider.horizontal.3", text: "Good path rows show current path, final path, source title, sidecar authority, collision state, undo coverage, and why a row is checked or left for review.")
            ]
        case .repairAndReceipts:
            [
                .init(title: "What this means", symbol: "wrench.and.screwdriver", text: "EPUB repair is a later file-changing stage. It can refresh import metadata, fix package cover metadata, use trusted sidecar covers, validate the result, and replace the original only after the temporary file passes checks."),
                .init(title: "What it does not do", symbol: "sparkles", text: "Repair should not guess series identity, fetch broad provider data, or clean raw filenames. It consumes trusted sidecar metadata that earlier stages prepared."),
                .init(title: "Receipts", symbol: "doc.text", text: "Receipts explain applied metadata writes, file moves, EPUB repairs, skipped rows, and recovery notes. They should stay near the selected collection."),
                .init(title: "Safety boundary", symbol: "lock", text: "File-changing work needs checked rows, confirmation, validation where possible, and clear undo or manual recovery notes."),
                .init(title: "Power-user details", symbol: "slider.horizontal.3", text: "Repair details should include temporary file path, validation result, cover source, import metadata written, backup or undo coverage, and skipped failures.")
            ]
        case .reviewNotes:
            [
                .init(title: "What this means", symbol: "list.bullet.rectangle", text: "Review rows are grouped into focused pages of proposed final outcomes: raw cleanup, missing numbers, ComicInfo and AnimeInfo, folder names, book filenames, duplicates, unresolved cases, and apply summaries."),
                .init(title: "Why it matters", symbol: "questionmark.circle", text: "A rename question, metadata question, duplicate question, and missing-number question ask different things from the user. Separate pages keep decisions scannable and reduce review fatigue."),
                .init(title: "Setting to know", symbol: "slider.horizontal.3", text: "Review tool settings decide which pages are prepared during inspection. Turning a tool off should prevent new suggestions for that area; it should not apply, revert, or hide already written files."),
                .init(title: "Evidence contract", symbol: "text.magnifyingglass", text: "Rows should show the current path, final path or metadata target, confidence, safety state, collision state, reason, and why a row is checked, unchecked, or blocked."),
                .init(title: "Learning context", symbol: "brain", text: "Remembered decisions can make future notes clearer, but they should remain explainable and resettable. Learning should help prioritize review, not silently change files."),
                .init(title: "Power-user details", symbol: "slider.horizontal.3", text: "Power review tools belong here: filter by safety, sort by confidence, reveal in Finder, copy paths, compare duplicate groups, bulk-check safe suggestions, and export the current review page as a receipt preview.")
            ]
        case .applyCheckedRows:
            [
                .init(title: "What this means", symbol: "checkmark.seal", text: "Apply uses only checked rows in the visible step. It confirms the scope, performs supported local changes, saves receipts or undo data where possible, and can verify fresh paths afterward with Check Again."),
                .init(title: "Concrete confirmation", symbol: "checklist", text: "The confirmation should name the step and scope: safe changes, files affected, receipt path, undo availability, skipped conflicts, and any metadata lookups."),
                .init(title: "What stays out", symbol: "exclamationmark.triangle", text: "Unchecked rows, conflicted destinations, unclear metadata, and unsupported operations stay excluded unless the user gets a more specific review path."),
                .init(title: "Receipts and undo", symbol: "doc.text", text: "File-changing runs should save readable receipts. Supported moves should save undo data; if automatic undo is unavailable, the confirmation should say that before the user commits."),
                .init(title: "Safety boundary", symbol: "lock", text: "Apply belongs next to the plan it affects, not in global chrome. The user should be able to verify exactly which checked rows will change files before committing."),
                .init(title: "Power-user details", symbol: "slider.horizontal.3", text: "The advanced apply view should show operation counts, source and destination roots, collision handling, receipt path, undo-plan coverage, skipped rows, and any operation that requires manual recovery.")
            ]
        case .inspectSafety:
            [
                .init(title: "What this means", symbol: "eye", text: "Careful by default means the first pass reads and explains. It should make the collection legible before asking the user to accept any cleanup work."),
                .init(title: "What does not happen", symbol: "lock", text: "Inspect should not move, rename, delete, repair, write ComicInfo or AnimeInfo, create reports that imply apply happened, or contact network services as a hidden side effect."),
                .init(title: "Setting to know", symbol: "gearshape", text: "Settings can prepare more review suggestions, but preparation is not application. Slow or advanced checks still need to surface their results before files change."),
                .init(title: "Assist boundary", symbol: "sparkles", text: "Apple Intelligence and local learning can help summarize findings. They should not invent metadata, rename files by themselves, or turn an unchecked row into an applied change."),
                .init(title: "Power-user details", symbol: "slider.horizontal.3", text: "The app should eventually expose enough scan diagnostics for power users to tell the difference between skipped, unreadable, cloud-placeholder, network-deferred, and intentionally excluded work.")
            ]
        case .conflictsStayOut:
            [
                .init(title: "What this means", symbol: "exclamationmark.triangle", text: "A conflict is any row where applying could overwrite, collide, or change a path that is not clearly safe."),
                .init(title: "Why it matters", symbol: "arrow.triangle.branch", text: "Conflicts are where automation can surprise people. Keeping them out by default protects existing files and avoids mixing uncertain decisions into a safe cleanup pass."),
                .init(title: "Network context", symbol: "network", text: "MangaBaka-backed ComicInfo rows are checked work when the user chooses to apply that review page. The confirmation should show that network lookups will happen."),
                .init(title: "Evidence contract", symbol: "text.magnifyingglass", text: "A conflict row needs the current path, final path, collision state, confidence, reason, and correction controls before it can become applyable."),
                .init(title: "Safety boundary", symbol: "xmark.octagon", text: "The app should skip conflicts during apply and say how many were skipped. Skipping is a safety feature, not a failure."),
                .init(title: "Power-user details", symbol: "slider.horizontal.3", text: "Future inspector details should distinguish name collisions, same-file no-ops, cross-volume moves, cloud-provider uncertainty, permission failures, and network-deferred metadata.")
            ]
        case .receiptsMatter:
            [
                .init(title: "What this means", symbol: "doc.text", text: "Receipts are readable reports for file-changing runs and serious review work. They record what the app proposed or changed so the cleanup can be traced later."),
                .init(title: "Why it matters", symbol: "clock.arrow.circlepath", text: "Receipts make cleanup legible to a future self, a household, backup tools, or anyone trying to understand why paths changed."),
                .init(title: "Setting to know", symbol: "gearshape", text: "The Save Receipts setting controls report writing. If receipts are off or unavailable, apply confirmations should be extra explicit about what recovery information will not be saved."),
                .init(title: "Undo coverage", symbol: "arrow.uturn.backward.circle", text: "Supported moves should keep undo data. Rename, move, metadata, or network-related work that cannot be undone automatically needs clear warning copy before apply."),
                .init(title: "Path actions", symbol: "folder", text: "Receipt paths should be visible, selectable, and easy to hand to Finder. Open Report Folder, Reveal in Finder, and Copy Path are part of the recovery story."),
                .init(title: "Power-user details", symbol: "slider.horizontal.3", text: "Receipt details should include operation counts, affected files, skipped conflicts, excluded network rows, undo-plan coverage, source and destination roots, and any manual recovery instructions.")
            ]
        case .libraryFilesLocal:
            [
                .init(title: "What this means", symbol: "externaldrive", text: "Library files stay local means the library check reads the selected folder on this Mac. The app should treat local file paths, local metadata, and local reports as the normal path."),
                .init(title: "What stays local", symbol: "folder", text: "Folder walking, filename checks, extension checks, ComicInfo and AnimeInfo parsing, duplicate clues, learned choices, reports, undo plans, and sidecar file snapshots should stay on this Mac unless a visible network-backed row says otherwise."),
                .init(title: "What can leave", symbol: "network", text: "Network-backed metadata work is a separate subject. If the app needs outside data, the row should say what service is involved and why the user is being asked to review it. Repeated no-key provider responses can be reused in memory during the same app session."),
                .init(title: "Safety boundary", symbol: "lock", text: "Do not make broad privacy promises unless the code enforces them. The UI should describe specific behaviors: read locally, write receipts locally, review network rows explicitly."),
                .init(title: "Power-user details", symbol: "slider.horizontal.3", text: "Future diagnostics should show whether the selected library folder is local, external, iCloud-backed, another cloud provider, read-only, unavailable, or missing security-scoped access.")
            ]
        case .mangaBakaOptional:
            [
                .init(title: "What this means", symbol: "network", text: "MangaBaka and the reading providers are optional outside metadata sources for ComicInfo rows. Their work should be visible and clearly separated from local inspection."),
                .init(title: "Setting to know", symbol: "gearshape", text: "Use MangaBaka for ComicInfo and Use metadata providers let checked sidecar rows search provider APIs during apply. They should not make the read-only inspection pass quietly fetch outside metadata."),
                .init(title: "Refresh gate", symbol: "clock.badge.checkmark", text: "ComicInfo and AnimeInfo refresh rows compare provider freshness with the local file snapshot saved in the sidecar. If nothing changed and the provider data is still fresh, the row should stay quiet instead of calling the provider again."),
                .init(title: "Safety boundary", symbol: "xmark.octagon", text: "Provider lookup happens only when the user applies checked metadata rows. Rows without a confident match should be skipped instead of inventing metadata."),
                .init(title: "Power-user details", symbol: "slider.horizontal.3", text: "Provider diagnostics should show request source, matching confidence, source title, local title, memory-cache reuse, freshness state, and whether a retry or manual correction is available.")
            ]
        case .receiptsStayLocal:
            [
                .init(title: "What this means", symbol: "doc.text.magnifyingglass", text: "Receipts and undo notes are part of the selected collection's recovery story. They should be easy to find from the app and Finder."),
                .init(title: "Where they live", symbol: "folder", text: "Reports are saved into the selected library folder's report folder when receipt export is enabled. This keeps cleanup notes near the files they describe."),
                .init(title: "Setting to know", symbol: "gearshape", text: "Save Receipts controls report writing. If receipts are disabled or unavailable, apply confirmations should say what recovery information will not be saved."),
                .init(title: "Path actions", symbol: "arrow.up.right.square", text: "Open Receipts, Reveal in Finder, and Copy Path are privacy and recovery actions, not decoration. They help the user inspect what changed without digging through hidden folders."),
                .init(title: "Power-user details", symbol: "slider.horizontal.3", text: "Receipt previews should eventually show report path, undo-plan path, applied operation counts, skipped rows, excluded network rows, and manual recovery notes.")
            ]
        case .appleIntelligenceAssist:
            [
                .init(title: "Current availability", symbol: "sparkles", text: "\(availability.title). \(availability.detail)"),
                .init(title: "What it can do", symbol: "text.magnifyingglass", text: "Apple Intelligence can help turn deterministic findings into clearer review notes, summaries, confidence explanations, and comparison hints when the on-device model is available."),
                .init(title: "What it cannot do", symbol: "lock", text: "It must not invent metadata, silently rename files, delete files, override safety checks, or turn an unchecked suggestion into an applied operation."),
                .init(title: "Setting to know", symbol: "gearshape", text: "Assist settings are reset with cleanup defaults. The app should continue to work with deterministic suggestions when Apple Intelligence is unavailable, off, or still preparing."),
                .init(title: "Power-user details", symbol: "slider.horizontal.3", text: "Advanced diagnostics should show whether a note came from deterministic rules, local learning, Apple Intelligence, or a fallback because the model was unavailable.")
            ]
        case .localLearningAssist:
            [
                .init(title: "Current memory", symbol: "brain", text: "Local learning has \(learnedDecisionCount) remembered decision\(learnedDecisionCount == 1 ? "" : "s"). These choices are stored in Sable's shared local support folder on this Mac."),
                .init(title: "What it can do", symbol: "text.magnifyingglass", text: "Learning can remember repeated review choices, manual provider IDs, and rows that applied successfully. That helps explain why a term looks safe or risky and reduces repeated decisions for the same collection style."),
                .init(title: "What it cannot do", symbol: "lock", text: "Learning should not silently apply file changes, override conflict checks, or shame an existing naming style. It is a review aid, not a hidden automation rule."),
                .init(title: "Setting to know", symbol: "gearshape", text: "Reset Sable Learning in Settings forgets remembered review choices. It does not change library files, saved reports, or the selected library folder."),
                .init(title: "Power-user details", symbol: "slider.horizontal.3", text: "Future inspector details should show which remembered example affected a suggestion, how often it was accepted or dismissed, and how to correct the learning signal.")
            ]
        case .trainingMaterial:
            [
                .init(title: "What teaches Sable", symbol: "checklist", text: "Good lessons come from corrections, Treat As choices, manual provider IDs, checked safe applies, and weak matches you leave unchecked or skip."),
                .init(title: "How to train calmly", symbol: "target", text: "For a huge raw batch, review a small sample first. Fix the wrong type, destination, volume number, provider, or merge choice before checking the whole group."),
                .init(title: "What not to teach", symbol: "lock", text: "Do not apply a giant batch just to see what happens. Leave uncertain rows unchecked; uncertainty is useful safety signal for the next model."),
                .init(title: "Privacy boundary", symbol: "lock.shield", text: "Project training uses anonymous features instead of private titles and paths. Personal training receipts can include local names, so keep those in your library reports folder."),
                .init(title: "Best cadence", symbol: "arrow.clockwise", text: "Inspect, open one lane, correct a few rows, apply only safe rows, Check Again, then retrain the anonymous model after the batch looks trustworthy.")
            ]
        }
    }
}
