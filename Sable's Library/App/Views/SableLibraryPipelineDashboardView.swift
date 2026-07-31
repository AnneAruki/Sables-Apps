//
//  SableLibraryPipelineDashboardView.swift
//  Sable's Library
//

import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
import ImageIO
#endif

private struct SableLibraryApplyConfirmation {
    var checkedChangeCount: Int
    var affectedPathCount: Int
    var safeApplyCount: Int
    var leftUntouchedCount: Int
    var needsAttentionCount: Int
    var checkpointSummaries: [SableLibraryApplyCheckpointSummary]
    var receiptPath: String?
    var undoAvailability: String
    var resolvedCollisions: Int
    var mergedFolderItems: Int
    var movedDuplicates: Int
    var conflictsSkipped: Int
    var networkRowsExcluded: Int
    var networkLookupCount: Int
    var hiddenSearchCheckedCount: Int
    var clearedHiddenCategoryCount: Int

    var needsExtraReview: Bool {
        resolvedCollisions > 0
            || mergedFolderItems > 0
            || movedDuplicates > 0
            || networkLookupCount > 0
    }
}

private struct SableLibraryApplyCheckpointSummary: Identifiable {
    var id: String { title }
    var title: String
    var checkedCount: Int
    var networkCount: Int
    var reviewCount: Int
    var isSelected: Bool
}

private enum SableLibraryApplyRequestMode: String {
    case checkedRows
    case mangaBakaCoverBaseline
    case storeCoverQualityUpgrade
    case exactIDBatch
    case singleProviderMatch
}

private enum SableCoversLibraryLane: String, CaseIterable, Identifiable {
    case mangaBakaBaseline
    case qualityUpgrades

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mangaBakaBaseline: "MangaBaka Baseline"
        case .qualityUpgrades: "Quality Upgrades"
        }
    }

    var detail: String {
        switch self {
        case .mangaBakaBaseline:
            "Fill missing or conflicting library cover slots from the matched MangaBaka series."
        case .qualityUpgrades:
            "Keep the MangaBaka baseline, then replace it only when BookLive, BookWalker, or Amazon proves a better image."
        }
    }

    var symbolName: String {
        switch self {
        case .mangaBakaBaseline: "photo.stack"
        case .qualityUpgrades: "sparkles"
        }
    }
}

private struct SableLibraryApplyRequest: Identifiable {
    let mode: SableLibraryApplyRequestMode
    let stage: LibraryPipelineStage
    let itemIDs: [LibraryPlanItem.ID]?
    let scopeTitle: String?
    let summary: SableLibraryApplyConfirmation

    var id: String {
        let scope = scopeTitle ?? "all"
        let ids = itemIDs?.map(\.uuidString).joined(separator: "-") ?? "stage"
        return "\(mode.rawValue)-\(stage.rawValue)-\(scope)-\(ids)"
    }
}

private struct SableLibraryReceiptPreview: Identifiable {
    let id = UUID()
    var title: String
    var result: LibraryApplyResult
}

private struct SableLibraryCoverReviewPreview: Identifiable {
    let id = UUID()
    var title: String
    var items: [LibraryPlanItem]
}

private struct SableLibraryPathChangeSummary {
    var currentValue: String
    var proposedValue: String
    var currentHighlight: String?
    var proposedHighlight: String?
    var symbol: String
    var isReviewSensitive: Bool

    var accessibilityText: String {
        "What changed: \(currentValue) to \(proposedValue)"
    }
}

private enum SableLibraryReviewCategory: String, CaseIterable, Identifiable {
    case books
    case pdfTriage
    case videos
    case metadata
    case repairs
    case shelves
    case folders
    case documents
    case images
    case audio
    case archives
    case duplicates
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .books: "Books"
        case .pdfTriage: "PDF Triage"
        case .videos: "Videos"
        case .metadata: "Metadata"
        case .repairs: "Repairs"
        case .shelves: "Shelves"
        case .folders: "Folders"
        case .documents: "Documents"
        case .images: "Images"
        case .audio: "Audio"
        case .archives: "Archives"
        case .duplicates: "Duplicates"
        case .other: "Other"
        }
    }

    var symbolName: String {
        switch self {
        case .books: "book"
        case .pdfTriage: "doc.text.magnifyingglass"
        case .videos: "play.rectangle"
        case .metadata: "checkmark.seal"
        case .repairs: "wrench.and.screwdriver"
        case .shelves: "books.vertical"
        case .folders: "folder"
        case .documents: "doc.text"
        case .images: "photo"
        case .audio: "waveform"
        case .archives: "archivebox"
        case .duplicates: "square.on.square"
        case .other: "doc"
        }
    }

    static let defaultScope = Set(SableLibraryReviewCategory.allCases)
}

private struct SableLibraryReviewCategoryExpansion: Hashable {
    var groupID: UUID
    var category: SableLibraryReviewCategory
}

private struct SableLibraryStageActionMetrics {
    var hasBulkCheckItems: Bool
    var uncheckedBulkCheckCount: Int
    var uncheckedSafeCount: Int
    var checkedCount: Int
    var applyCount: Int
    var exactIDBatchCount: Int
    var hasNetworkData: Bool
    var hasNetworkSafetyRows: Bool
    var isFiltered: Bool
}

private struct SableLibraryWorkingIndicator: View {
    @Environment(\.sableLibraryPalette) private var palette

    var body: some View {
        Image(systemName: "clock.arrow.circlepath")
            .font(.callout.weight(.semibold))
            .foregroundStyle(palette.accent)
            .frame(width: 18, height: 18)
    }
}

private struct SableLibraryTaskProgressBar: View {
    @Environment(\.sableLibraryPalette) private var palette

    var snapshot: SableLibraryProgressSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ProgressView(
                value: Double(snapshot.clampedCompletedUnitCount),
                total: Double(max(snapshot.clampedTotalUnitCount, 1))
            )
            .progressViewStyle(.linear)
            .tint(palette.accent)

            HStack(spacing: 8) {
                Text(snapshot.countText)
                Spacer(minLength: 8)
                if let percentageText = snapshot.percentageText {
                    Text(percentageText)
                }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
        }
    }
}

private struct SableLibraryGuidanceCue {
    var role: SableLibraryStatusRole
    var title: String
    var message: String
    var recovery: String?

    var needsAttention: Bool {
        role == .warning || role == .error
    }
}

private struct SableLibraryEmptyScanCueModel: Identifiable {
    var id: String { title }
    var title: String
    var detail: String
    var symbol: String
}

private struct SableClinicInventoryOverviewView: View {
    @Environment(\.sableLibraryPalette) private var palette

    var inspection: LibraryInspection?
    var checkProfile: SableClinicCheckProfile?

    private var epubCount: Int {
        inspection?.bookFileCount ?? 0
    }

    private var comicInfoCount: Int {
        inspection?.comicInfoCount ?? 0
    }

    private var missingComicInfoCount: Int {
        inspection?.missingComicInfoCount ?? 0
    }

    private var scanDepth: String {
        guard let inspection else { return "Waiting" }
        if let checkProfile {
            return checkProfile.title
        }
        return inspection.inspectMode == .epubClinicInventory ? "Paths" : "Checker layers"
    }

    private var statusTitle: String {
        guard inspection != nil else { return "No EPUB inventory yet" }
        if let checkProfile {
            return checkProfile.emptyTitle
        }
        return "Inventory only. Not clear yet."
    }

    private var statusMessage: String {
        guard inspection != nil else {
            return "List EPUBs to map files, paths, and local sidecars. The Clinic will wait before opening EPUB internals."
        }
        if let checkProfile {
            return checkProfile.emptyMessage
        }
        return "This pass found EPUB files and checked local ComicInfo and AnimeInfo sidecar coverage. It did not inspect package metadata, navigation, XHTML, CSS, images, covers, or EPUBCheck findings yet."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("EPUB inventory")
                    .font(.headline)
                Text(statusTitle)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(palette.textSecondary)
            }

            SableEagerAdaptiveGrid(
                minimumItemWidth: 145,
                horizontalSpacing: 10,
                verticalSpacing: 10
            ) {
                metricTile("EPUBs", value: "\(epubCount)", symbol: "books.vertical")
                metricTile("ComicInfo", value: "\(comicInfoCount)", symbol: "doc.text.magnifyingglass")
                metricTile("Scan depth", value: scanDepth, symbol: "leaf")
            }

            Text(statusMessage)
                .font(.callout)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if missingComicInfoCount > 0 {
                Label("\(missingComicInfoCount) EPUB group\(missingComicInfoCount == 1 ? "" : "s") still need ComicInfo before metadata cleaning is complete.", systemImage: "doc.badge.plus")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(palette.statusWarning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 2)
        .accessibilityElement(children: .contain)
    }

    private func metricTile(_ title: String, value: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.textSecondary)
                .frame(width: 18)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(palette.textSecondary)
                Text(value)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.38), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}

struct SableLibraryPipelineDashboardView: View {
    @Environment(\.sableLibraryPalette) private var palette
    @Environment(\.openURL) private var openURL

    var appMode: SableLibraryAppMode = .library
    let libraryURL: URL?
    let run: LibraryPipelineRun?
    var isWorking = false
    var statusText = "Ready"
    var currentActivity = ""
    var learnedDecisionCount = 0
    var progressSnapshot: SableLibraryProgressSnapshot?
    var applyResult: LibraryApplyResult?
    var pipelineSummary: LibraryPipelineSummary?
    var canQuickCheck = false
    var folderOrganizationDepth: SableLibraryFolderOrganizationDepth = .form
    var epubClinicModifiedWindow: SableEPUBClinicModifiedWindow = .all
    var modifiedWindowsByStage: [String: SableLibraryModifiedWindow] = [:]
    var onChooseFolder: () -> Void = {}
    var onDropFolder: (URL) -> Void = { _ in }
    var onInspect: () -> Void = {}
    var onQuickCheck: () -> Void = {}
    var onOpenReports: () -> Void = {}
    var onRestoreLastApply: () -> Void = {}
    var onDoctorCheck: () -> Void = {}
    var onStop: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    var onDecisionChange: (LibraryPlanItem.ID, LibraryPlanDecision) -> Void = { _, _ in }
    var onBulkDecisionChange: ([LibraryPlanItem.ID], LibraryPlanDecision) -> Void = { _, _ in }
    var onCorrection: (LibraryPlanItem.ID, LibraryPlanCorrectionOption) -> Void = { _, _ in }
    var onBulkCorrection: ([LibraryPlanItem.ID], LibraryPlanCorrectionOption) -> Void = { _, _ in }
    var onCorrectionNoteChange: (LibraryPlanItem.ID, String) -> Void = { _, _ in }
    var onMangaBakaIDChange: (LibraryPlanItem.ID, String) -> Void = { _, _ in }
    var onRanobeDBIDChange: (LibraryPlanItem.ID, String) -> Void = { _, _ in }
    var onProviderIDChange: (LibraryPlanItem.ID, SableLibraryMetadataProvider, String) -> Void = { _, _, _ in }
    var onProviderCandidates: (SableLibraryMetadataProvider, String, [String]) async -> [SableLibraryProviderCandidate] = { _, _, _ in [] }
    var onCoverSeriesMatchChange: (LibraryPlanItem.ID, SableLibraryManualCoverSeriesMatch) -> Bool = { _, _ in false }
    var onCoverSeriesCandidates: (SableLibraryCoverSource, String, String?) async -> [SableLibraryManualCoverSeriesMatch] = { _, _, _ in [] }
    var onStageDeepInspect: (LibraryPipelineStage) -> Void = { _ in }
    var onClinicCheck: (SableClinicCheckProfile) -> Void = { _ in }
    var onFolderOrganizationDepthChange: (SableLibraryFolderOrganizationDepth) -> Void = { _ in }
    var onEPUBClinicModifiedWindowChange: (SableEPUBClinicModifiedWindow) -> Void = { _ in }
    var onStageModifiedWindowChange: (LibraryPipelineStage, SableLibraryModifiedWindow) -> Void = { _, _ in }
    var onApplyStage: (LibraryPipelineStage, Bool) -> Void = { _, _ in }
    var onApplyStageItems: (LibraryPipelineStage, [LibraryPlanItem.ID], Bool) -> Void = { _, _, _ in }
    var onApplyCovers: ([LibraryPlanItem.ID]?, SableLibraryCoverDownloadPass) -> Void = { _, _ in }
    var onBatchRefreshExactIDs: (LibraryPipelineStage, [LibraryPlanItem.ID]) -> Void = { _, _ in }

    @State private var selectedStage: LibraryPipelineStage = .inspect
    @State private var reviewSearchText = ""
    @State private var reviewCategoryScope = SableLibraryReviewCategory.defaultScope
    @State private var expandedReviewGroups: Set<UUID> = []
    @State private var expandedReviewCategories: Set<SableLibraryReviewCategoryExpansion> = []
    @State private var providerGapVisibleRowLimits: [UUID: Int] = [:]
    @State private var inspectComicInfoSearchText = ""
    @State private var inspectAnimeInfoSearchText = ""
    @State private var pendingApplyRequest: SableLibraryApplyRequest?
    @State private var pendingReceiptPreview: SableLibraryReceiptPreview?
    @State private var selectedWorkflowDetail: SableLibraryWorkflowDetail?
    @State private var pendingMangaBakaIDItem: LibraryPlanItem?
    @State private var pendingRanobeDBIDItem: LibraryPlanItem?
    @State private var pendingProviderSearch: SableLibraryProviderSearchRequest?
    @State private var pendingCoverSearch: SableLibraryCoverSearchRequest?
    @State private var pendingCoverReviewPreview: SableLibraryCoverReviewPreview?
    @State private var coversLibraryLane: SableCoversLibraryLane = .mangaBakaBaseline
    @State private var showRestoreLastApplyConfirmation = false
    @State private var isFolderDropTargeted = false
    @FocusState private var focusedPlanItemID: UUID?

    private let providerGapInitialVisibleRowLimit = 8
    private let providerGapVisibleRowIncrement = 25

    private let reviewRowPreviewLimit = 60
    private let reviewFileTypePreviewLimit = 40

    private var currentStageGroups: [LibraryPlanGroup] {
        guard let run else { return [] }
        return groups(for: selectedStage, in: run)
    }

    private var checkedCount: Int {
        run?.context.plan.checkedItems.count ?? 0
    }

    private var selectedStageApplyCount: Int {
        guard let run else { return 0 }
        return applyCount(for: selectedStage, in: run)
    }

    private var selectedStageExactIDBatchCount: Int {
        guard let run else { return 0 }
        return exactIDBatchItems(for: selectedStage, in: run).count
    }

    private var selectedStageBulkCheckItems: [LibraryPlanItem] {
        currentStageGroups
            .flatMap { bulkDecisionItems(in: $0) }
            .filter(isBulkCheckItem)
    }

    private var selectedStageUncheckedSafeCount: Int {
        currentStageGroups
            .flatMap { bulkDecisionItems(in: $0) }
            .filter(isSafeBulkCheckItem)
            .filter { $0.decision != .checked }
            .count
    }

    private var selectedStageUncheckedBulkCheckCount: Int {
        selectedStageBulkCheckItems.filter { $0.decision != .checked }.count
    }

    private var selectedStageCheckedCount: Int {
        currentStageGroups
            .flatMap { bulkDecisionItems(in: $0) }
            .filter { $0.decision == .checked }
            .count
    }

    private var clinicPlanItems: [LibraryPlanItem] {
        guard appMode == .clinic, let run else { return [] }
        return groups(for: .epubClinic, in: run)
            .flatMap(\.activeItems)
    }

    private var clinicInventoryCount: Int {
        run?.context.inspection?.bookFileCount ?? 0
    }

    private var clinicComicInfoCount: Int {
        run?.context.inspection?.comicInfoCount ?? 0
    }

    private var clinicMissingComicInfoCount: Int {
        run?.context.inspection?.missingComicInfoCount ?? 0
    }

    private var isReviewSearchActive: Bool {
        !reviewSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func isReviewCategoryScopeActive(in group: LibraryPlanGroup) -> Bool {
        group.items.contains { !reviewCategoryScope.contains(reviewCategory(for: $0)) }
    }

    private func isReviewCategoryScopeActive(in groups: [LibraryPlanGroup]) -> Bool {
        groups.contains { isReviewCategoryScopeActive(in: $0) }
    }

    private func isReviewFiltered(in group: LibraryPlanGroup) -> Bool {
        isReviewSearchActive || isReviewCategoryScopeActive(in: group)
    }

    private var sableStatusText: String {
        [
            currentActivity,
            pipelineSummary?.title ?? "",
            pipelineSummary?.message ?? ""
        ]
        .joined(separator: " ")
        .lowercased()
    }

    private var sablePrimaryStatusMessage: String {
        let summaryMessage = pipelineSummary?.message.trimmingCharacters(in: .whitespacesAndNewlines)
        let activity = currentActivity.trimmingCharacters(in: .whitespacesAndNewlines)

        if let summaryMessage, !summaryMessage.isEmpty,
           activity.isEmpty || activity.count < 32 || sableStatusTextContainsProblem {
            return summaryMessage
        }

        return activity.isEmpty ? "Everything is quiet." : activity
    }

    private var sableStatusTextContainsProblem: Bool {
        sableStatusText.contains("failed")
            || sableStatusText.contains("could not")
            || sableStatusText.contains("cannot")
            || sableStatusText.contains("error")
            || sableStatusText.contains("permission")
            || sableStatusText.contains("access")
    }

    private var isShowingCoverSearchOutcome: Bool {
        selectedStage == .covers
            && ["Cover search finished", "Store proof check finished"]
                .contains(pipelineSummary?.title ?? "")
    }

    private func metadataReadyCue(for groups: [LibraryPlanGroup]) -> (title: String, message: String, recovery: String) {
        let checkedItems = groups.flatMap(\.activeItems).filter { $0.decision == .checked }
        let cleanerCount = checkedItems.filter { $0.reviewTags.contains("metadata-comicinfo-cleaner") || $0.reviewTags.contains("metadata-animeinfo-cleaner") }.count
        let bookDetailCount = checkedItems.filter { $0.reviewTags.contains("metadata-ranobedb-book-detail-refresh") }.count
        let createCount = checkedItems.filter { $0.operation == .createComicInfo || $0.operation == .createAnimeInfo }.count

        if cleanerCount > 0, cleanerCount == checkedItems.count {
            return (
                "Sidecar cleanup ready",
                "\(cleanerCount) sidecar cleanup row\(cleanerCount == 1 ? "" : "s") can organize local provider notes.",
                "This cleans saved metadata notes only. It does not move books or invent provider IDs."
            )
        }

        if bookDetailCount > 0, bookDetailCount == checkedItems.count {
            return (
                "Saved provider refresh ready",
                "\(bookDetailCount) series refresh row\(bookDetailCount == 1 ? "" : "s") can update provider data and check RanobeDB for new books.",
                "Saved IDs are used directly. RanobeDB fetches only book details that are not already stored."
            )
        }

        if createCount > 0, createCount == checkedItems.count {
            return (
                "Sidecars ready to create",
                "\(createCount) local sidecar\(createCount == 1 ? "" : "s") can be created for existing media folders.",
                "These metadata notes help later raw-file, folder-name, EPUB, and provider passes."
            )
        }

        return (
            "Metadata rows ready",
            "\(selectedStageApplyCount) checked metadata row\(selectedStageApplyCount == 1 ? "" : "s") can run.",
            "Checked rows run first; questions, conflicts, and unchecked refresh rows stay out."
        )
    }

    private var sableCompanionCue: SableLibraryGuidanceCue? {
        if isShowingCoverSearchOutcome, let pipelineSummary {
            return SableLibraryGuidanceCue(
                role: .success,
                title: pipelineSummary.title,
                message: pipelineSummary.message,
                recovery: pipelineSummary.title == "Store proof check finished"
                    ? "Verified rows move to Complete. Unproven covers move to a real replacement search, and detected conflicts stay available for repair."
                    : "Attempted language rows are unchecked. Partial sets move to that language's Cover Gaps to Retry group, and finished searches with no accepted image move to its No Trusted Match group."
            )
        }

        if sableStatusTextContainsProblem {
            return SableLibraryGuidanceCue(
                role: .error,
                title: "A blocker needs attention",
                message: sablePrimaryStatusMessage,
                recovery: sableRecoverySuggestion(for: sableStatusText)
            )
        }

        if isWorking {
            return SableLibraryGuidanceCue(
                role: .running,
                title: "Checking current step",
                message: currentActivity.isEmpty ? "Working through the current step." : currentActivity,
                recovery: "Let this finish, or stop after the current file if you need to pause."
            )
        }

        if libraryURL == nil {
            return SableLibraryGuidanceCue(
                role: .info,
                title: "Ready when you are",
                message: appMode.chooseFolderCue,
                recovery: appMode == .clinic
                    ? "Pick or drop the folder that holds the EPUBs you want to check."
                    : "Pick or drop the top folder that holds this media library."
            )
        }

        if let run {
            let activeItems = appMode == .clinic ? clinicPlanItems : run.context.plan.activeItems
            let unresolvedItems = appMode == .clinic
                ? activeItems.filter(\.needsDecisionReview)
                : run.context.plan.unresolvedItems
            let blockedRepairCount = appMode == .clinic
                ? unresolvedItems.filter { isManualDiagnosticItem($0) || isCleanSourceNeededEPUBRepairItem($0) }.count
                : 0
            let choiceCount = max(0, unresolvedItems.count - blockedRepairCount)

            if appMode == .clinic, blockedRepairCount > 0, choiceCount == 0 {
                return SableLibraryGuidanceCue(
                    role: .review,
                    title: "Blocked repair findings",
                    message: "\(blockedRepairCount) EPUB finding\(blockedRepairCount == 1 ? " needs" : "s need") a new repair rule or a clean source.",
                    recovery: "Fixable EPUB problems show checked repair rows. Protected or source-quality rows explain why Sable cannot safely rewrite this copy."
                )
            }

            if choiceCount > 0 {
                return SableLibraryGuidanceCue(
                    role: .warning,
                    title: "Review needed",
                    message: "\(choiceCount) suggestion\(choiceCount == 1 ? " needs" : "s need") a decision before this should be applied.",
                    recovery: "Open the item marked for review and choose apply, skip, or a correction."
                )
            }

            if canQuickCheck {
                return SableLibraryGuidanceCue(
                    role: .review,
                    title: "Quick check is ready",
                    message: "The app can verify the last applied step and refresh the next suggestions.",
                    recovery: "Use Check Again before applying more changes."
                )
            }

            if selectedStageApplyCount > 0 {
                if selectedStage == .comicInfo {
                    let metadataCue = metadataReadyCue(for: currentStageGroups)
                    return SableLibraryGuidanceCue(
                        role: .warning,
                        title: metadataCue.title,
                        message: metadataCue.message,
                        recovery: metadataCue.recovery
                    )
                }
                return SableLibraryGuidanceCue(
                    role: .warning,
                    title: "Checked changes are waiting",
                    message: "\(selectedStageApplyCount) checked change\(selectedStageApplyCount == 1 ? "" : "s") in this step can affect files.",
                    recovery: "Review the scope, then apply only when it looks right."
                )
            }

            if activeItems.isEmpty {
                if appMode == .clinic {
                    return SableLibraryGuidanceCue(
                        role: .info,
                        title: "No Clinic rows from this pass",
                        message: "This pass found no repair suggestions. Sable only says clean after repairs are applied and the changed EPUBs recheck with no remaining rows.",
                        recovery: "Run the needed Clinic pass again after adding, changing, or repairing EPUBs."
                    )
                }
                return SableLibraryGuidanceCue(
                    role: .success,
                    title: "Collection looks calm",
                    message: "No cleanup suggestions are waiting right now.",
                    recovery: nil
                )
            }
        } else {
            return SableLibraryGuidanceCue(
                role: .info,
                title: "Ready to inspect",
                message: "Start with a read-only look at this folder.",
                recovery: appMode.runReadyMessage
            )
        }

        if (applyResult?.appliedCount ?? 0) > 0 {
            return SableLibraryGuidanceCue(
                role: .success,
                title: "Changes applied",
                message: "A receipt was saved for the last applied work.",
                recovery: canQuickCheck ? "Use Check Again to verify the result." : nil
            )
        }

        return nil
    }

    private var visibleDashboardCue: SableLibraryGuidanceCue? {
        guard let cue = sableCompanionCue else { return nil }
        if isShowingCoverSearchOutcome {
            return cue
        }
        if cue.needsAttention || cue.role == .running || cue.role == .review {
            return cue
        }
        if canQuickCheck || isWorking {
            return cue
        }
        return nil
    }

    private func sableRecoverySuggestion(for statusText: String) -> String {
        if statusText.contains("permission")
            || statusText.contains("access")
            || statusText.contains("cannot be read")
            || statusText.contains("choose folder again") {
            return "Choose the folder again so macOS can renew access."
        }

        if statusText.contains("report folder")
            || statusText.contains("report path")
            || statusText.contains("already exists") {
            return "Check that path in Finder, then move or rename the blocking file."
        }

        if statusText.contains("network") {
            return "Leave network-only rows out, or enable the matching lookup flow first."
        }

        if statusText.contains("collision")
            || statusText.contains("conflict")
            || statusText.contains("occupied") {
            return "Review the conflicting path and choose a safe skip or move-aside decision."
        }

        if statusText.contains("check at least one") {
            return "Check one safe suggestion before applying this step."
        }

        if statusText.contains("folder") {
            return "Pick or drop the top-level library folder, then inspect again."
        }

        return "Review the message, adjust the item, then try the last action again."
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if let libraryURL, shouldShowDashboardContext {
                    dashboardContextPanel(libraryURL)
                }
                if let visibleDashboardCue {
                    sableCompanionPanel(visibleDashboardCue)
                }
                if appMode == .clinic {
                    clinicRepairDeskPanel
                }
                if appMode == .covers {
                    coversRepairDeskPanel
                }
                if isWorking, appMode != .clinic {
                    workingStatusPanel
                }

                if let run {
                    stepStrip(for: run)
                    if appMode != .clinic, reviewWorkflowStages.contains(selectedStage) {
                        libraryStageScopePanel(for: selectedStage)
                    }
                    focusedStep(for: run)
                        .frame(maxWidth: .infinity, minHeight: 460, alignment: .topLeading)
                } else {
                    emptyState
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 36)
            .padding(.bottom, 20)
            .frame(maxWidth: 1180, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .id("\(run?.id.uuidString ?? "none")-\(isWorking ? "working" : "idle")")
        .onDrop(
            of: [UTType.fileURL.identifier],
            isTargeted: $isFolderDropTargeted,
            perform: handleFolderDrop
        )
        .overlay {
            if isFolderDropTargeted {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(palette.accent, lineWidth: 2)
                    .padding(10)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .onChange(of: run?.id) { _, _ in
            selectedStage = firstReviewStage ?? run?.context.inspectMode.focusStage ?? .inspect
            reviewSearchText = ""
            expandedReviewGroups = []
            expandedReviewCategories = []
            providerGapVisibleRowLimits = [:]
            inspectComicInfoSearchText = ""
            inspectAnimeInfoSearchText = ""
            focusedPlanItemID = nil
        }
        .onChange(of: selectedStage) { _, _ in
            reviewSearchText = ""
            expandedReviewGroups = []
            expandedReviewCategories = []
            providerGapVisibleRowLimits = [:]
            focusedPlanItemID = nil
        }
        .onChange(of: reviewSearchText) { _, _ in
            focusedPlanItemID = nil
        }
        .sheet(item: $pendingApplyRequest) { request in
            applyConfirmationSheet(request)
        }
        .sheet(item: $pendingReceiptPreview) { preview in
            receiptPreviewSheet(preview)
        }
        .sheet(item: $selectedWorkflowDetail) { detail in
            workflowDetailSheet(detail)
        }
        .sheet(item: $pendingMangaBakaIDItem) { item in
            SableLibraryMangaBakaIDSheet(
                item: item,
                onCancel: { pendingMangaBakaIDItem = nil },
                onSave: { input in
                    onMangaBakaIDChange(item.id, input)
                    pendingMangaBakaIDItem = nil
                }
            )
        }
        .sheet(item: $pendingRanobeDBIDItem) { item in
            SableLibraryRanobeDBIDSheet(
                item: item,
                onCancel: { pendingRanobeDBIDItem = nil },
                onSave: { input in
                    onRanobeDBIDChange(item.id, input)
                    pendingRanobeDBIDItem = nil
                }
            )
        }
        .sheet(item: $pendingProviderSearch) { request in
            SableLibraryProviderSearchSheet(
                request: request,
                onCancel: { pendingProviderSearch = nil },
                onUseLocal: {
                    onCorrection(request.item.id, .keepTitle)
                    pendingProviderSearch = nil
                },
                onSave: { provider, input in
                    onProviderIDChange(request.item.id, provider, input)
                    pendingProviderSearch = nil
                },
                onSearch: onProviderCandidates,
                openURL: openURL
            )
        }
        .sheet(item: $pendingCoverSearch) { request in
            SableLibraryCoverSearchSheet(
                request: request,
                onCancel: { pendingCoverSearch = nil },
                onSave: { match in
                    onCoverSeriesMatchChange(request.item.id, match)
                },
                onDownload: {
                    pendingCoverSearch = nil
                    Task { @MainActor in
                        await Task.yield()
                        requestApply(
                            .covers,
                            itemIDs: [request.item.id],
                            scopeTitle: URL(fileURLWithPath: request.item.currentPath)
                                .lastPathComponent
                        )
                    }
                },
                onSearch: onCoverSeriesCandidates,
                openURL: openURL
            )
        }
        .sheet(item: $pendingCoverReviewPreview) { preview in
            coverReviewPreviewSheet(preview)
        }
        .confirmationDialog(
            "Restore Last Apply?",
            isPresented: $showRestoreLastApplyConfirmation,
            titleVisibility: .visible
        ) {
            Button("Restore Last Apply") {
                onRestoreLastApply()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Sable reads the latest undo plan and moves applied files back only when the original path is empty. Missing files or occupied original paths are skipped and listed in the restore receipt.")
        }
    }

    private var firstReviewStage: LibraryPipelineStage? {
        guard let run else { return nil }
        return reviewWorkflowStages.first { stage in
            groups(for: stage, in: run).contains { group in
                !group.activeItems.isEmpty || !group.skippedItems.isEmpty
            }
        }
    }

    private var shouldShowDashboardContext: Bool {
        run != nil || isWorking
    }

    private func handleFolderDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { provider in
            provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }) else {
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let url = Self.droppedFileURL(from: item) else { return }
            Task { @MainActor in
                onDropFolder(url)
            }
        }
        return true
    }

    private static func droppedFileURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return url
        }
        if let url = item as? NSURL {
            return url as URL
        }
        if let data = item as? Data {
            return URL(dataRepresentation: data, relativeTo: nil)
        }
        if let string = item as? String {
            return URL(string: string)
        }
        return nil
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(appMode.dashboardTitle)
                    .font(.title2.bold())
                Text(headerSubtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private func sableCompanionPanel(_ cue: SableLibraryGuidanceCue) -> some View {
        let tint = cue.role.color(in: palette)

        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: cue.role.defaultSymbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(tint.opacity(cue.needsAttention ? 0.16 : 0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(tint.opacity(cue.needsAttention ? 0.34 : 0.20), lineWidth: 1)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(cue.title)
                        .font(.subheadline.weight(.semibold))

                    if let badgeText = sableCueBadgeText(cue) {
                        SableLibraryStatusBadge(
                            text: badgeText,
                            role: cue.role
                        )
                    }
                }

                Text(cue.message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(cue.needsAttention ? 3 : 2)
                    .fixedSize(horizontal: false, vertical: true)

                if let recovery = cue.recovery {
                    Label(recovery, systemImage: cue.needsAttention ? "wrench.and.screwdriver" : "arrow.forward.circle")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(cue.needsAttention ? tint : palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sableLibrarySurface(
            fill: palette.surface,
            border: cue.needsAttention ? tint.opacity(0.42) : palette.border,
            glassTint: cue.needsAttention ? tint : nil,
            glassProminence: cue.needsAttention ? .interactive : .automatic,
            glassIntensity: .thin
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(cue.needsAttention ? "Cleanup warning" : "Cleanup tip")
        .accessibilityValue(
            [cue.title, cue.message, cue.recovery ?? ""]
                .filter { !$0.isEmpty }
                .map(accessibilitySentenceFragment)
                .joined(separator: ". ")
        )
    }

    private func accessibilitySentenceFragment(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!?"))
    }

    private func sableCueBadgeText(_ cue: SableLibraryGuidanceCue) -> String? {
        switch cue.role {
        case .error:
            return "Error"
        case .warning:
            return "Warning"
        case .running:
            return "Update"
        case .success:
            return "OK"
        case .review:
            return "Review"
        case .info, .neutral, .undo:
            return nil
        }
    }

    private var headerSubtitle: String {
        if libraryURL != nil {
            return appMode.headerSubtitleWhenSelected
        }
        return appMode.headerSubtitleWhenEmpty
    }

    private func dashboardContextPanel(_ url: URL) -> some View {
        return HStack(alignment: .center, spacing: 12) {
            Image(systemName: "folder")
                .font(.callout.weight(.semibold))
                .foregroundStyle(palette.accent)
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent.isEmpty ? appMode.selectedFolderTitle : url.lastPathComponent)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)

                Text(dashboardLocationText(for: url))
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                revealAbsolutePathInFinder(url.path(percentEncoded: false))
            }
            .help(url.path(percentEncoded: false))

            if learnedDecisionCount > 0 {
                Text("\(learnedDecisionCount) remembered")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }

            Button(action: onChooseFolder) {
                Label("Change Folder", systemImage: "folder.badge.plus")
            }
            .buttonStyle(.bordered)
            .disabled(isWorking)
            .help("Choose a different library folder.")
            .accessibilityHint("Opens the folder picker.")

            dashboardFolderMenu(url)
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sableLibrarySurface(
            fill: palette.surfaceRaised,
            border: palette.border,
            cornerRadius: 8,
            glassProminence: .none,
            glassIntensity: .thin
        )
        .contextMenu {
            Button("Change Folder...") {
                onChooseFolder()
            }
            .disabled(isWorking)
            Divider()
            Button("Reveal in Finder") {
                revealAbsolutePathInFinder(url.path(percentEncoded: false))
            }
            Button("Copy Path") {
                copyAbsolutePath(url.path(percentEncoded: false))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(appMode == .clinic ? "Selected EPUB collection context" : "Selected library context")
        .accessibilityValue(dashboardContextAccessibilityValue(for: url))
    }

    private func dashboardLocationText(for url: URL) -> String {
        let components = compactDashboardPathComponents(for: url.deletingLastPathComponent())
        guard !components.isEmpty else {
            return url.path(percentEncoded: false)
        }
        return components.joined(separator: " / ")
    }

    private func dashboardPathSummary(_ url: URL) -> some View {
        let components = compactDashboardPathComponents(for: url)

        return Button {
            revealAbsolutePathInFinder(url.path(percentEncoded: false))
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .foregroundStyle(palette.accent)
                    .accessibilityHidden(true)

                ForEach(Array(components.enumerated()), id: \.offset) { index, component in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(palette.textSecondary.opacity(0.72))
                            .accessibilityHidden(true)
                    }

                    Text(component)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(palette.textSecondary)
            .contentShape(Rectangle())
            .frame(height: 22, alignment: .center)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(appMode.selectedFolderTitle)
        .accessibilityValue(url.path(percentEncoded: false))
        .help(url.path(percentEncoded: false))
    }

    private func compactDashboardPathComponents(for url: URL) -> [String] {
        let standardizedURL = url.standardizedFileURL
        var labels: [String] = []

        for component in standardizedURL.pathComponents where component != "/" {
            labels.append(dashboardPathDisplayName(component: component))
        }

        if labels.isEmpty {
            let fallback = standardizedURL.lastPathComponent
            return [fallback.isEmpty ? standardizedURL.path(percentEncoded: false) : fallback]
        }

        return Array(labels.suffix(3))
    }

    private func dashboardPathDisplayName(component: String) -> String {
        if component == "Mobile Documents" {
            return "iCloud Drive"
        }

        return component
    }

    private func dashboardFolderMenu(_ url: URL) -> some View {
        Menu {
            Button("Change Folder...") {
                onChooseFolder()
            }
            .disabled(isWorking)

            Divider()

            Button("Reveal in Finder") {
                revealAbsolutePathInFinder(url.path(percentEncoded: false))
            }
            Button("Copy Path") {
                copyAbsolutePath(url.path(percentEncoded: false))
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.callout.weight(.medium))
        }
        .menuStyle(.borderlessButton)
        .accessibilityHint("Shows folder actions.")
    }

    private var dashboardStatusLabel: some View {
        Label(isWorking ? "Working" : "Saved folder", systemImage: isWorking ? "clock" : "checkmark.seal")
            .font(.caption.weight(.semibold))
            .foregroundStyle(isWorking ? palette.accent : palette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var dashboardMemoryLabel: some View {
        Label(dashboardMemoryText, systemImage: "brain")
            .font(.caption.weight(.medium))
            .foregroundStyle(palette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func dashboardPathControl(_ url: URL) -> some View {
        SableLibraryPathControl(url: url) { selectedURL in
            revealAbsolutePathInFinder(selectedURL.path(percentEncoded: false))
        }
        .frame(height: 24)
        .accessibilityLabel("\(appMode.selectedFolderTitle) path")
        .accessibilityValue(url.path(percentEncoded: false))
    }

    private var dashboardStatusLine: String {
        let trimmedStatus = statusText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedStatus.isEmpty {
            return trimmedStatus
        }
        return isWorking ? "Working" : "Ready"
    }

    private var dashboardMemoryText: String {
        "Local learning: \(learnedDecisionCount) remembered decision\(learnedDecisionCount == 1 ? "" : "s")"
    }

    private func dashboardContextAccessibilityValue(for url: URL) -> String {
        [
            dashboardStatusLine,
            "Folder: \(url.path(percentEncoded: false))",
            learnedDecisionCount > 0 ? dashboardMemoryText : nil
        ]
        .compactMap { $0 }
        .joined(separator: ". ")
    }

    private var workingStatusPanel: some View {
        HStack(alignment: .top, spacing: 12) {
            if progressSnapshot?.clampedTotalUnitCount ?? 0 == 0 {
                SableLibraryWorkingIndicator()
                    .padding(.top, 2)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(progressSnapshot?.title ?? "Working")
                    .font(.subheadline.weight(.semibold))
                Text(progressSnapshot?.message ?? (currentActivity.isEmpty ? "Preparing the next update." : currentActivity))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                if let progressSnapshot, progressSnapshot.clampedTotalUnitCount > 0 {
                    SableLibraryTaskProgressBar(snapshot: progressSnapshot)
                        .accessibilityHidden(true)
                }
            }

            Spacer(minLength: 0)

            Button(role: .cancel, action: onStop) {
                Label("Stop", systemImage: "stop.circle")
            }
            .help("Stop after the current file or network request finishes.")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sableLibrarySurface(
            fill: palette.statusInfo.opacity(0.08),
            border: palette.statusInfo.opacity(0.22),
            glassTint: palette.statusInfo,
            glassProminence: .decorative,
            glassIntensity: .regular
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(progressSnapshot?.title ?? "Work in progress")
        .accessibilityValue(
            progressSnapshot.map(progressAccessibilityValue(for:))
                ?? (currentActivity.isEmpty ? "Preparing the next update." : currentActivity)
        )
    }

    private func progressAccessibilityValue(for snapshot: SableLibraryProgressSnapshot) -> String {
        var details = [snapshot.message]
        if snapshot.clampedTotalUnitCount > 0 {
            details.append(snapshot.countText)
            if let percentageText = snapshot.percentageText {
                details.append(percentageText)
            }
        }
        return details
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    private var clinicRepairDeskPanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.accent)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(palette.accent.opacity(0.14))
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("EPUB Repair Studio")
                        .font(.subheadline.weight(.semibold))
                    Text(clinicDeskSubtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

            if appMode == .clinic, isWorking {
                clinicStopButton
            } else if run != nil || canQuickCheck {
                clinicDeskActions
            }
        }

            if appMode == .clinic, isWorking {
                clinicInlineProgressPanel
            } else {
                clinicPassControlStrip
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sableLibraryPanelSurface()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("EPUB Repair Studio")
        .accessibilityValue(clinicDeskSubtitle)
    }

    private var coversRepairDeskPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "photo.stack")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.accent)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(palette.accent.opacity(0.14))
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Archive Source")
                        .font(.subheadline.weight(.semibold))
                    Text("Fill trusted MangaBaka gaps first, or run the slower storefront quality pass.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                if isWorking {
                    Button(role: .cancel, action: onStop) {
                        Label("Stop", systemImage: "stop.circle")
                    }
                    .buttonStyle(.bordered)
                }
            }

            Picker(
                "Archive source",
                selection: Binding(
                    get: { coversLibraryLane },
                    set: { selectCoversLibraryLane($0) }
                )
            ) {
                ForEach(SableCoversLibraryLane.allCases) { lane in
                    Label(lane.title, systemImage: lane.symbolName)
                        .tag(lane)
                }
            }
            .pickerStyle(.segmented)
            .disabled(isWorking)

            HStack(alignment: .center, spacing: 10) {
                Text(coversLibraryLane.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                Button {
                    prepareSelectedCoverDownloadLane()
                } label: {
                    Label(
                        coversLibraryLane == .mangaBakaBaseline
                            ? "Prepare MangaBaka Pass"
                            : "Prepare Upgrade Pass",
                        systemImage: coversLibraryLane.symbolName
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(libraryURL == nil || isWorking)
            }
            .controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sableLibraryPanelSurface()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Cover Archive Source")
        .accessibilityValue(coversLibraryLane.detail)
    }

    private func selectCoversLibraryLane(_ lane: SableCoversLibraryLane) {
        coversLibraryLane = lane
        selectedStage = .covers
    }

    private func prepareSelectedCoverDownloadLane() {
        selectedStage = .covers
        guard let run else {
            onInspect()
            return
        }
        if shouldDeepInspect(.covers, in: run) {
            onStageDeepInspect(.covers)
        }
    }

    private var clinicDeskSubtitle: String {
        if libraryURL == nil {
            return "Choose a collection, then Clinic lists EPUB files before opening deeper checker layers."
        }
        if isWorking {
            return "Clinic is checking \(epubClinicModifiedWindow.repairScopeDescription) now. Stop will pause after the current file or layer finishes."
        }
        if run?.context.inspectMode == .epubClinicInventory {
            guard clinicInventoryCount > 0 else {
                return "No EPUB files were found in this folder."
            }
            let missingSidecarText = clinicMissingComicInfoCount > 0
                ? "\(clinicMissingComicInfoCount) EPUB group\(clinicMissingComicInfoCount == 1 ? "" : "s") still need ComicInfo."
                : "ComicInfo sidecars are available for mapped EPUB groups."
            return "\(clinicInventoryCount) EPUB file\(clinicInventoryCount == 1 ? "" : "s") mapped; \(clinicComicInfoCount) ComicInfo sidecar group\(clinicComicInfoCount == 1 ? "" : "s") checked. \(missingSidecarText)"
        }
        if clinicPlanItems.isEmpty, run != nil {
            if let clinicEmptyCheckProfile {
                return clinicEmptyCheckProfile.emptyMessage
            }
            return clinicModifiedWindowForCurrentRun == .all
                ? "This pass has no active EPUB repair rows."
                : "This pass has no active EPUB repair rows for \(clinicModifiedWindowForCurrentRun.repairScopeDescription)."
        }
        if !clinicPlanItems.isEmpty {
            return "\(clinicPlanItems.count) EPUB finding\(clinicPlanItems.count == 1 ? "" : "s") sorted into runnable repair rows."
        }
        return "Run a read-only scan to prepare checker layers before anything changes."
    }

    private var clinicModifiedWindowForCurrentRun: SableEPUBClinicModifiedWindow {
        run?.context.options.stages.epubClinicModifiedWindow ?? epubClinicModifiedWindow
    }

    private var clinicEmptyCheckProfile: SableClinicCheckProfile? {
        guard let run, clinicPlanItems.isEmpty else { return nil }
        return clinicEmptyCheckProfile(for: run)
    }

    @ViewBuilder
    private var clinicDeskActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                clinicDeskActionButtons
            }
            VStack(alignment: .trailing, spacing: 8) {
                clinicDeskActionButtons
            }
        }
    }

    @ViewBuilder
    private var clinicDeskActionButtons: some View {
        if libraryURL == nil {
            Button(action: onChooseFolder) {
                Label("Choose Folder", systemImage: "folder.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isWorking)
            .help("Pick the folder that holds the EPUBs to check.")
        } else if canQuickCheck {
            Button(action: onQuickCheck) {
                Label("Recheck Applied", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isWorking)
            .help("Verify the last applied EPUB repairs.")

            Button(action: onInspect) {
                Label(appMode.inspectActionTitle, systemImage: "magnifyingglass")
            }
            .buttonStyle(.bordered)
            .disabled(isWorking)
            .help("Refresh EPUB files, paths, and local sidecar coverage.")
        } else {
            Button(action: onInspect) {
                Label(appMode.inspectActionTitle, systemImage: "magnifyingglass")
            }
            .buttonStyle(.bordered)
            .disabled(isWorking)
            .help("List EPUB files and check local sidecars without opening EPUB internals.")
        }

        Button(action: onOpenReports) {
            Label("Reports", systemImage: "doc.text.magnifyingglass")
        }
        .buttonStyle(.bordered)
        .disabled(libraryURL == nil || isWorking)
        .help("Open Clinic reports and receipts in Finder.")
    }

    private var clinicStopButton: some View {
        Button(role: .cancel, action: onStop) {
            Label("Stop", systemImage: "stop.circle")
        }
        .buttonStyle(.bordered)
        .help("Stop after the current file or repair layer finishes.")
    }

    private var clinicInlineProgressPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if progressSnapshot?.clampedTotalUnitCount ?? 0 == 0 {
                    SableLibraryWorkingIndicator()
                        .accessibilityHidden(true)
                }

                Text(progressSnapshot?.title ?? "Working")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)

                Spacer(minLength: 0)
            }

            Text(progressSnapshot?.message ?? (currentActivity.isEmpty ? "Preparing the next update." : currentActivity))
                .font(.callout)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if let progressSnapshot, progressSnapshot.clampedTotalUnitCount > 0 {
                SableLibraryTaskProgressBar(snapshot: progressSnapshot)
                    .accessibilityHidden(true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sableLibrarySurface(
            fill: palette.statusInfo.opacity(0.08),
            border: palette.statusInfo.opacity(0.22),
            cornerRadius: 8,
            glassTint: palette.statusInfo,
            glassProminence: .decorative,
            glassIntensity: .thin
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(progressSnapshot?.title ?? "Clinic work in progress")
        .accessibilityValue(
            progressSnapshot.map(progressAccessibilityValue(for:))
                ?? (currentActivity.isEmpty ? "Preparing the next update." : currentActivity)
        )
    }

    private var clinicPassControlStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text("Choose a pass")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.textSecondary)

                clinicModifiedWindowMenu

                Spacer(minLength: 0)

                Text("Run one specialist or the complete Clinic")
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)
            }

            SableEagerAdaptiveGrid(
                minimumItemWidth: 112,
                horizontalSpacing: 8,
                verticalSpacing: 8
            ) {
                clinicPassButton(.fast, prominent: true)
                ForEach(SableClinicCheckProfile.repairLaneChoices) { profile in
                    clinicPassButton(profile, prominent: false)
                }
                clinicPassButton(.deep, prominent: false)
            }
        }
        .padding(.top, 2)
    }

    private var clinicModifiedWindowMenu: some View {
        Menu {
            ForEach(SableEPUBClinicModifiedWindow.allCases) { window in
                Button {
                    onEPUBClinicModifiedWindowChange(window)
                } label: {
                    if window == epubClinicModifiedWindow {
                        Label(window.title, systemImage: "checkmark")
                    } else {
                        Text(window.title)
                    }
                }
            }
        } label: {
            Label("EPUBs: \(epubClinicModifiedWindow.shortTitle)", systemImage: "calendar.badge.clock")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(isWorking)
        .help(epubClinicModifiedWindow.helpText)
        .accessibilityLabel("EPUBs to check")
        .accessibilityValue(epubClinicModifiedWindow.title)
        .accessibilityHint(epubClinicModifiedWindow.helpText)
    }

    @ViewBuilder
    private func clinicPassButton(_ profile: SableClinicCheckProfile, prominent: Bool) -> some View {
        if prominent {
            clinicPassButtonBase(profile)
                .buttonStyle(.borderedProminent)
        } else {
            clinicPassButtonBase(profile)
                .buttonStyle(.bordered)
        }
    }

    private func clinicPassButtonBase(_ profile: SableClinicCheckProfile) -> some View {
        Button {
            onClinicCheck(profile)
        } label: {
            Label(profile.title, systemImage: profile.systemImage)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .controlSize(.small)
        .disabled(libraryURL == nil || isWorking)
        .help(profile.detail)
        .accessibilityHint(profile.detail)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "square.grid.2x2")
                    .font(.title3)
                    .foregroundStyle(palette.accent)
                    .frame(width: 28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text(emptyStateTitle)
                        .font(.headline)
                    Text(emptyStateMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    emptyPrimaryActions
                }

                VStack(alignment: .leading, spacing: 10) {
                    emptyPrimaryActions
                }
            }

            Divider()

            emptyScanPreview

            if libraryURL == nil {
                Label(appMode == .clinic
                      ? "No EPUB folder selected yet. Choose Folder opens the macOS folder picker, or drop an EPUB collection folder here."
                      : "No library folder selected yet. Choose Folder opens the macOS folder picker, or drop the top library folder here.",
                  systemImage: "folder.badge.questionmark")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sableLibraryPanelSurface()
    }

    private var emptyScanPreview: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 18) {
                ForEach(emptyScanCues) { cue in
                    emptyScanCue(cue)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(emptyScanCues) { cue in
                    emptyScanCue(cue)
                }
            }
        }
    }

    private var emptyScanCues: [SableLibraryEmptyScanCueModel] {
        var cues: [SableLibraryEmptyScanCueModel]
        if appMode == .clinic {
            cues = [
                SableLibraryEmptyScanCueModel(
                    title: "Scan",
                    detail: "List EPUB files and check local sidecars.",
                    symbol: "magnifyingglass"
                ),
                SableLibraryEmptyScanCueModel(
                    title: "Layers",
                    detail: "Run package, metadata, navigation, and content checks after inventory.",
                    symbol: "square.stack.3d.up"
                ),
                SableLibraryEmptyScanCueModel(
                    title: "Repair",
                    detail: "Only checked safe repairs run after confirmation.",
                    symbol: "checkmark.shield"
                )
            ]
        } else if appMode == .covers {
            cues = [
                SableLibraryEmptyScanCueModel(
                    title: "Inventory",
                    detail: "Map series, EPUBs, and existing cover sets without changing them.",
                    symbol: "magnifyingglass"
                ),
                SableLibraryEmptyScanCueModel(
                    title: "Find Covers",
                    detail: "Fill MangaBaka gaps first, then look for genuine quality upgrades.",
                    symbol: "photo.stack"
                ),
                SableLibraryEmptyScanCueModel(
                    title: "Fix EPUBs",
                    detail: "Use only language-matched covers that pass the Clinic quality floor.",
                    symbol: "book.pages"
                )
            ]
        } else {
            cues = [
                SableLibraryEmptyScanCueModel(
                    title: "Scan",
                    detail: "Read names, folders, and sidecars.",
                    symbol: "magnifyingglass"
                ),
                SableLibraryEmptyScanCueModel(
                    title: "Review",
                    detail: "Show suggestions before anything changes.",
                    symbol: "list.bullet.rectangle"
                ),
                SableLibraryEmptyScanCueModel(
                    title: "Apply",
                    detail: "Only checked rows run after confirmation.",
                    symbol: "checkmark.shield"
                )
            ]
        }

        if learnedDecisionCount > 0 {
            cues.append(SableLibraryEmptyScanCueModel(
                title: "Learning",
                detail: "\(learnedDecisionCount) local choice\(learnedDecisionCount == 1 ? "" : "s") remembered.",
                symbol: "brain"
            ))
        }
        return cues
    }

    private func emptyScanCue(_ cue: SableLibraryEmptyScanCueModel) -> some View {
        emptyScanCue(title: cue.title, detail: cue.detail, symbol: cue.symbol)
    }

    private func emptyScanCue(title: String, detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.accent)
                .frame(width: 18)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(detail)")
    }

    @ViewBuilder
    private var emptyPrimaryActions: some View {
        if libraryURL == nil {
            Button(action: onChooseFolder) {
                Label("Choose Folder", systemImage: "folder.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isWorking)
            .help(appMode == .clinic ? "Pick the folder that holds the EPUBs to check." : "Pick the top folder for this library.")

            Button(action: onInspect) {
                Label(appMode.inspectActionTitle, systemImage: "magnifyingglass")
            }
            .buttonStyle(.bordered)
            .disabled(true)
            .help(appMode == .clinic ? "Choose an EPUB folder before scanning." : "Choose a folder before inspection.")
        } else {
            Button(action: onInspect) {
                Label(appMode.inspectActionTitle, systemImage: "magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isWorking)
            .keyboardShortcut(.return, modifiers: [.command])
            .help(appMode == .clinic ? "List EPUB files and check local sidecars. Open the Repair page for deeper checker layers." : "Run a read-only scan, then review suggestions.")

            Button(action: onChooseFolder) {
                Label("Change Folder", systemImage: "folder.badge.plus")
            }
            .buttonStyle(.bordered)
            .disabled(isWorking)
            .help(appMode == .clinic ? "Replace the current EPUB folder." : "Replace the current library folder.")
        }
    }

    private var emptyStateTitle: String {
        guard let libraryURL else { return appMode.emptyFolderTitle }
        return "\(libraryFolderDisplayName(libraryURL)) is selected"
    }

    private var emptyStateMessage: String {
        if appMode == .clinic {
            if libraryURL == nil {
                return "Clinic starts with an EPUB and sidecar inventory."
            }
            return "Run a light EPUB and sidecar inventory first. Open the Repair page afterward for deeper checker layers."
        }
        if libraryURL == nil { return "Sable will inspect first without changing files." }
        return "Run a read-only scan to prepare the review."
    }

    private func libraryFolderDisplayName(_ url: URL) -> String {
        let fallback = url.lastPathComponent
        return fallback.isEmpty ? "Library folder" : fallback
    }

    private func dashboardAction(
        _ title: String,
        detail: String,
        symbol: String,
        prominent: Bool,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: symbol)
                    .font(.title2)
                    .frame(width: 30)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(prominent ? palette.accentText.opacity(0.82) : palette.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .foregroundStyle(prominent ? palette.accentText : palette.accent)
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .sableLibrarySurface(
                fill: prominent ? palette.accent : palette.surfaceRaised,
                border: prominent ? palette.accent.opacity(0.5) : palette.border,
                glassTint: palette.accent,
                interactive: true,
                glassProminence: prominent ? .interactive : .decorative,
                glassIntensity: prominent ? .prominent : .regular
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(detail)
        .disabled(disabled)
        .opacity(disabled ? 0.55 : 1)
    }

    private func selectedLibraryFolderPanel(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(appMode.selectedFolderTitle, systemImage: "checkmark.seal")
                .font(.subheadline.weight(.semibold))

            SableLibraryPathControl(url: url) { selectedURL in
                revealAbsolutePathInFinder(selectedURL.path(percentEncoded: false))
            }
            .frame(height: 24)
            .accessibilityLabel("\(appMode.selectedFolderTitle) path")
            .accessibilityValue(url.path(percentEncoded: false))

            HStack(spacing: 10) {
                Button {
                    revealAbsolutePathInFinder(url.path(percentEncoded: false))
                } label: {
                    Label("Reveal in Finder", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.borderless)

                Button {
                    copyAbsolutePath(url.path(percentEncoded: false))
                } label: {
                    Label("Copy Path", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderless)

                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sableLibrarySurface(
            fill: palette.surfaceRaised,
            border: palette.border,
            glassProminence: .none,
            glassIntensity: .thin
        )
        .contextMenu {
            Button("Reveal in Finder") {
                revealAbsolutePathInFinder(url.path(percentEncoded: false))
            }
            Button("Copy Path") {
                copyAbsolutePath(url.path(percentEncoded: false))
            }
        }
    }

    private func workflowStep(_ detail: SableLibraryWorkflowDetail) -> some View {
        Button {
            selectedWorkflowDetail = detail
        } label: {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(palette.accent.opacity(0.16))
                    Text("\(detail.number)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(palette.accent)
                }
                .frame(width: 34, height: 34)
                .accessibilityHidden(true)

                Image(systemName: detail.symbol)
                    .font(.title3)
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(detail.title)
                        .font(.subheadline.weight(.semibold))
                    Text(detail.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: "info.circle")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(palette.accent)
                    .accessibilityHidden(true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sableLibrarySurface(
                fill: palette.surfaceRaised,
                border: palette.border,
                glassTint: palette.accent,
                interactive: true,
                glassProminence: .decorative,
                glassIntensity: .thin
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(detail.title). More details.")
        .accessibilityHint("Opens a detailed explanation of this cleanup step.")
    }

    private func workflowDetailSheet(_ detail: SableLibraryWorkflowDetail) -> some View {
        ZStack {
            LinearGradient(
                colors: [
                    palette.background,
                    palette.accent.opacity(detail.patternWash),
                    palette.surface.opacity(0.74)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            SableLibraryWorkflowPattern(style: detail.patternStyle)
                .stroke(
                    palette.accent.opacity(detail.patternOpacity),
                    style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round)
                )
                .ignoresSafeArea()
                .accessibilityHidden(true)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(palette.accent.opacity(0.18))
                            Image(systemName: detail.symbol)
                                .font(.system(size: 30, weight: .semibold))
                                .foregroundStyle(palette.accent)
                        }
                        .frame(width: 64, height: 64)
                        .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 5) {
                            Text(detail.title)
                                .font(.title2.bold())
                            Text(detail.summary)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()

                        Button("Done") {
                            selectedWorkflowDetail = nil
                        }
                        .keyboardShortcut(.defaultAction)
                    }

                    detailCard("What this does", symbol: "gearshape.2", text: detail.what)
                    detailCard("Why it helps", symbol: "questionmark.circle", text: detail.why)
                    detailCard("Safety boundary", symbol: "shield.checkered", text: detail.safety)
                    detailCard("Efficiency tip", symbol: "bolt", text: detail.qualityOfLife)
                    detailCard("How this should feel", symbol: "heart.text.square", text: detail.psychology)
                    detailCard("Shared-library impact", symbol: "person.2", text: detail.sociology)
                    detailCard("Power-user details", symbol: "slider.horizontal.3", text: detail.advanced)
                }
                .padding(24)
                .frame(maxWidth: 820, alignment: .leading)
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
        .frame(minWidth: 720, minHeight: 620)
        .sableLibraryWindowMirrorEffect()
    }

    private func detailCard(_ title: String, symbol: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(palette.accent)
                .frame(width: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(text)
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

    private func receiptPreviewSheet(_ preview: SableLibraryReceiptPreview) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(preview.title)
                        .font(.title3.weight(.semibold))
                    Text("\(preview.result.appliedCount) applied, \(preview.result.skippedCount) skipped")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Done") {
                    pendingReceiptPreview = nil
                }
                .keyboardShortcut(.cancelAction)
            }

            if let receiptPath = preview.result.receiptPath {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Saved receipt")
                        .font(.caption.weight(.semibold))
                    Text(receiptPath)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }

            SableLibrarySelectableTextView(text: preview.result.summary)
                .frame(minHeight: 280)
                .accessibilityLabel("Receipt text")
                .accessibilityValue(preview.result.summary)

            HStack(spacing: 10) {
                Button {
                    copyText(preview.result.summary)
                } label: {
                    Label("Copy Text", systemImage: "doc.on.doc")
                }
                .disabled(preview.result.summary.isEmpty)

                if let receiptPath = preview.result.receiptPath {
                    Button {
                        copyAbsolutePath(receiptPath)
                    } label: {
                        Label("Copy Path", systemImage: "link")
                    }

                    Button {
                        revealAbsolutePathInFinder(receiptPath)
                    } label: {
                        Label("Reveal", systemImage: "folder")
                    }
                }

                Spacer()

                Button(action: onOpenReports) {
                    Label("Reports", systemImage: "folder")
                }
                .disabled(libraryURL == nil)
            }
            .controlSize(.small)
        }
        .padding(22)
        .frame(minWidth: 620, minHeight: 520)
        .sableLibraryWindowMirrorEffect()
    }

    private func stepStrip(for run: LibraryPipelineRun) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(visibleStepStages(for: run), id: \.rawValue) { stage in
                    stageButton(stage, in: run)
                }
            }
            .padding(.vertical, 1)
        }
    }

    @ViewBuilder
    private func focusedStep(for run: LibraryPipelineRun) -> some View {
        if selectedStage == .inspect {
            if appMode == .clinic {
                SableClinicInventoryOverviewView(
                    inspection: run.context.inspection,
                    checkProfile: clinicCheckProfile(for: run)
                )
            } else {
                SableLibraryInspectOverviewView(
                    inspection: run.context.inspection,
                    libraryURL: libraryURL,
                    isWorking: isWorking,
                    comicInfoSearchText: $inspectComicInfoSearchText,
                    animeInfoSearchText: $inspectAnimeInfoSearchText,
                    recommendedStage: recommendedStage(for: run.context.inspection),
                    recommendedSafeRowCount: recommendedStage(for: run.context.inspection).map { safeAutomationCount(for: $0, in: run) } ?? 0,
                    onInspect: onInspect,
                    onRunRecommendedAutomation: { stage in
                        runSafeAutomation(stage, in: run)
                    }
                )
            }
        } else if selectedStage == .reviewApply {
            summaryOnly(for: run)
        } else {
            let groups = groups(for: selectedStage, in: run)
            if groups.isEmpty {
                if appMode == .clinic, selectedStage == .epubClinic {
                    SableClinicInventoryOverviewView(
                        inspection: run.context.inspection,
                        checkProfile: clinicCheckProfile(for: run)
                    )
                } else {
                    summaryOnly(for: run)
                }
            } else {
                stageReviewPage(for: selectedStage, groups: groups)
            }
        }
    }

    private func clinicCheckProfile(for run: LibraryPipelineRun) -> SableClinicCheckProfile? {
        guard run.context.inspectMode.wakesEPUBRepairSpecialists else { return nil }
        return SableClinicCheckProfile.matching(
            scopes: run.context.options.stages.epubClinicRepairScopes,
            deepContentChecks: run.context.options.stages.deepEPUBContentChecks
        )
    }

    private func libraryStageScopePanel(for stage: LibraryPipelineStage) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Label("Items to check", systemImage: "calendar.badge.clock")
                .font(.callout.weight(.semibold))
                .foregroundStyle(palette.textPrimary)

            libraryStageModifiedWindowMenu(for: stage)

            Spacer(minLength: 8)

            Button {
                onStageDeepInspect(stage)
            } label: {
                Label(
                    stage == .covers ? "Quick Audit All Covers" : "Check This Step",
                    systemImage: stage == .covers
                        ? "checkmark.shield"
                        : "arrow.clockwise"
                )
            }
            .buttonStyle(.borderedProminent)
            .disabled(isWorking || libraryURL == nil)
            .help(
                stage == .covers
                    ? "Check every saved cover and manifest locally. This does not contact stores or download images."
                    : "Run only \(applyStageTitle(stage)) for \(libraryModifiedWindow(for: stage).libraryScopeDescription)."
            )
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sableLibraryPanelSurface()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(applyStageTitle(stage)) items to check")
    }

    private func libraryStageModifiedWindowMenu(for stage: LibraryPipelineStage) -> some View {
        let selectedWindow = libraryModifiedWindow(for: stage)

        return Menu {
            ForEach(SableLibraryModifiedWindow.allCases) { window in
                Button {
                    onStageModifiedWindowChange(stage, window)
                } label: {
                    if window == selectedWindow {
                        Label(window.libraryTitle, systemImage: "checkmark")
                    } else {
                        Text(window.libraryTitle)
                    }
                }
            }
        } label: {
            Label(selectedWindow.shortTitle, systemImage: "line.3.horizontal.decrease.circle")
                .font(.callout.weight(.semibold))
                .lineLimit(1)
        }
        .buttonStyle(.bordered)
        .disabled(isWorking)
        .help(selectedWindow.libraryHelpText(for: stage))
        .accessibilityLabel("Date range")
        .accessibilityValue(selectedWindow.libraryTitle)
        .accessibilityHint(selectedWindow.libraryHelpText(for: stage))
    }

    private func libraryModifiedWindow(for stage: LibraryPipelineStage) -> SableLibraryModifiedWindow {
        modifiedWindowsByStage[stage.rawValue] ?? .all
    }

    private func stageReviewPage(
        for stage: LibraryPipelineStage,
        groups: [LibraryPlanGroup]
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            stageReviewHeader(for: stage, groups: groups)
            reviewSearchControls

            VStack(alignment: .leading, spacing: 12) {
                ForEach(groups) { group in
                    reviewGroupSection(group)
                }
            }
        }
        .padding(16)
        .sableLibrarySurface(
            fill: palette.surface,
            border: palette.border,
            glassTint: nil,
            glassProminence: .none,
            glassIntensity: .thin
        )
    }

    private func stageReviewHeader(
        for stage: LibraryPipelineStage,
        groups: [LibraryPlanGroup]
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            stageReviewTitleBlock(for: stage, groups: groups)
            stageReviewToolbar(for: stage, groups: groups)
        }
    }

    private func stageReviewTitleBlock(
        for stage: LibraryPipelineStage,
        groups: [LibraryPlanGroup]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(applyStageTitle(stage))
                    .font(.headline)
                Text(stageSummaryText(for: stage, groups: groups))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            stageStatusRow(for: groups)

            if stage == .canonicalFolders {
                folderOrganizationDepthControl
            }

            if stage == .covers {
                SableLibraryInfoBanner(
                    text: coversLibraryLane.detail,
                    role: .info,
                    systemImage: coversLibraryLane.symbolName
                )
            }

            if let scopeNotice = reviewScopeNotice(for: stage, groups: groups) {
                SableLibraryInfoBanner(
                    text: scopeNotice,
                    role: .info,
                    systemImage: isReviewSearchActive ? "magnifyingglass" : "eye.slash"
                )
            }
        }
    }

    private var folderOrganizationDepthControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Folder depth")
                .font(.caption.weight(.semibold))

            Picker(
                "Folder depth",
                selection: Binding(
                    get: { folderOrganizationDepth },
                    set: { onFolderOrganizationDepthChange($0) }
                )
            ) {
                ForEach(SableLibraryFolderOrganizationDepth.allCases) { depth in
                    Text(depth.label).tag(depth)
                }
            }
            .pickerStyle(.segmented)
            .disabled(isWorking)
            .accessibilityHint("Chooses whether folder sorting previews only form folders, main SSS shelves, or SSS subshelves.")

            Text(folderOrganizationDepth.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 420, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func stageReviewToolbar(
        for stage: LibraryPipelineStage,
        groups: [LibraryPlanGroup]
    ) -> some View {
        stageActionRow(for: stage, groups: groups, metrics: stageActionMetrics(for: stage, groups: groups))
        .controlSize(.small)
    }

    private func stageActionMetrics(
        for stage: LibraryPipelineStage,
        groups: [LibraryPlanGroup]
    ) -> SableLibraryStageActionMetrics {
        let bulkItems = groups.flatMap { bulkDecisionItems(in: $0) }
        let stageItems = groups.flatMap(\.items)
        let categoryScopeActive = groups.contains { group in
            group.items.contains { !reviewCategoryScope.contains(reviewCategory(for: $0)) }
        }
        let isFiltered = isReviewSearchActive || categoryScopeActive

        return SableLibraryStageActionMetrics(
            hasBulkCheckItems: bulkItems.contains(where: isBulkCheckItem),
            uncheckedBulkCheckCount: bulkItems.filter(isBulkCheckItem).filter { $0.decision != .checked }.count,
            uncheckedSafeCount: bulkItems.filter(isSafeBulkCheckItem).filter { $0.decision != .checked }.count,
            checkedCount: bulkItems.filter { $0.decision == .checked }.count,
            applyCount: stageItems.filter { item in
                item.decision == .checked
                    && item.isApplyableOperation
                    && reviewCategoryScope.contains(reviewCategory(for: item))
            }.count,
            exactIDBatchCount: stage == .comicInfo
                ? stageItems.filter(\.isExactIDBatchRefreshCandidate).count
                : 0,
            hasNetworkData: groups.contains { $0.activeItems.contains(where: \.usedNetworkData) },
            hasNetworkSafetyRows: groups.contains { group in
                group.activeItems.contains { $0.safety == .network }
            },
            isFiltered: isFiltered
        )
    }

    @ViewBuilder
    private func stageActionRow(
        for stage: LibraryPipelineStage,
        groups: [LibraryPlanGroup],
        metrics: SableLibraryStageActionMetrics
    ) -> some View {
        if stage == .epubClinic, stageHasOnlyManualDiagnostics(groups) {
            clinicDiagnosticToolbar(groups: groups)
        } else {
            HStack(spacing: 8) {
                Button(action: { checkAllEligible(in: groups) }) {
                    Label(metrics.isFiltered ? "Check Visible" : "Check All", systemImage: "checkmark.square")
                }
                .disabled(isWorking || metrics.uncheckedBulkCheckCount == 0)
                .help(checkAllHelpText(for: stage, metrics: metrics))

                Button(action: { clearChecks(in: groups) }) {
                    Label(metrics.isFiltered ? "Uncheck Visible" : "Uncheck All", systemImage: "square")
                }
                .disabled(isWorking || metrics.checkedCount == 0)
                .help(clearChecksHelpText(metrics: metrics))

                if stage == .covers {
                    if appMode != .covers || coversLibraryLane == .mangaBakaBaseline {
                        let mangaBakaItemIDs = mangaBakaBaselineApplyItemIDs(in: groups)
                        Button(action: {
                            requestApply(
                                stage,
                                itemIDs: mangaBakaItemIDs,
                                mode: .mangaBakaCoverBaseline
                            )
                        }) {
                            Label("Fill MangaBaka Gaps", systemImage: "photo.stack")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isWorking || mangaBakaItemIDs.isEmpty)
                        .help(
                            metrics.applyCount == 0
                                ? "Automatically selects every visible missing or conflicting cover row and runs only MangaBaka. Complete cover sets stay untouched."
                                : "Runs only MangaBaka for the rows you checked. Existing trusted covers are reused and only missing or conflicting slots are filled."
                        )
                        .keyboardShortcut(.return, modifiers: [.command])
                        .accessibilityHint(
                            mangaBakaItemIDs.isEmpty
                                ? "No missing or conflicting MangaBaka cover rows are waiting."
                                : metrics.applyCount == 0
                                ? "Opens a confirmation for every visible MangaBaka cover gap. You do not need to use Check All first."
                                : "Opens a confirmation for the fast MangaBaka baseline pass."
                        )
                    }

                    if appMode != .covers || coversLibraryLane == .qualityUpgrades {
                        Button(action: {
                            requestApply(
                                stage,
                                itemIDs: checkedApplyableItemIDs(in: groups),
                                mode: .storeCoverQualityUpgrade
                            )
                        }) {
                            Label("Find Quality Upgrades", systemImage: "sparkles")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isWorking || metrics.applyCount == 0)
                        .help("Checks BookLive, BookWalker, and Amazon separately. A store cover replaces the current baseline only when it is verified and higher quality.")
                        .accessibilityHint(
                            metrics.applyCount == 0
                                ? "No checked rows are ready."
                                : "Opens a confirmation for the slower store quality-upgrade pass."
                        )
                    }
                } else {
                    Button(action: { requestApply(stage) }) {
                        Label(applyToolbarButtonTitle(for: stage), systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isWorking || metrics.applyCount == 0)
                    .help(applyHelpText(for: stage, metrics: metrics))
                    .keyboardShortcut(.return, modifiers: [.command])
                    .accessibilityHint(metrics.applyCount == 0 ? "No checked rows are ready to apply." : applyAccessibilityHint(for: stage))
                }

                Menu {
                    Button(action: { checkAllSafe(in: groups) }) {
                        Label(metrics.isFiltered ? "Check Visible Safe" : "Check Safe", systemImage: "checkmark.shield")
                    }
                    .disabled(isWorking || metrics.uncheckedSafeCount == 0)

                    if stage == .covers {
                        Button(action: { checkMissingCovers(in: groups) }) {
                            Label("Check Gaps", systemImage: "photo.badge.exclamationmark")
                        }
                        .disabled(isWorking || uncheckedMissingCoverCount(in: groups) == 0)
                        .help("Checks only language rows with no cover manifest or with local books still missing a usable normal cover. Japanese and English can finish independently.")
                    }

                    Divider()

                    if stage == .comicInfo, metrics.exactIDBatchCount > 0 {
                        Button(action: { requestExactIDBatchRefresh(stage) }) {
                            Label("Refresh Saved IDs", systemImage: "bolt.circle")
                        }
                        .disabled(isWorking)
                        .help(exactIDBatchHelpText(count: metrics.exactIDBatchCount))
                        .accessibilityHint("Refreshes only checked metadata rows that already have saved provider IDs.")

                        Divider()
                    }
                    Button {
                        reviewCategoryScope = SableLibraryReviewCategory.defaultScope
                    } label: {
                        Label("Show All Categories", systemImage: "checkmark.square")
                    }
                    .disabled(reviewCategoryScope == SableLibraryReviewCategory.defaultScope)
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .disabled(isWorking)
                .help("More review controls.")
            }
        }
    }

    private func clinicDiagnosticToolbar(groups: [LibraryPlanGroup]) -> some View {
        HStack(spacing: 8) {
            Label("Repair blocked", systemImage: "exclamationmark.triangle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.textSecondary)
                .help("These rows stay visible because Sable cannot safely repair this copy yet. Fixable EPUB problems should show checked repair rows and validate a temporary EPUB before apply.")

            Spacer(minLength: 0)

            Menu {
                Button {
                    reviewCategoryScope = SableLibraryReviewCategory.defaultScope
                } label: {
                    Label("Show All Categories", systemImage: "checkmark.square")
                }
                .disabled(reviewCategoryScope == SableLibraryReviewCategory.defaultScope)
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .disabled(isWorking)
            .help("More review controls.")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("EPUB repair is blocked. Fixable rows show a checkbox.")
    }

    private func reviewGroupSection(_ group: LibraryPlanGroup) -> AnyView {
        let isExpanded = isReviewGroupExpanded(group)

        if usesSettledSimpleGroupRow(group, isExpanded: isExpanded) {
            return AnyView(settledSimpleGroupRow(group))
        }

        return AnyView(VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: groupSymbol(for: group))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(palette.accent)
                    .frame(width: 24)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(group.title)
                        .font(.subheadline.weight(.semibold))
                    Text(groupSummaryText(for: group))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Text("\(group.activeItems.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.quaternary.opacity(group.activeItems.isEmpty ? 0.35 : 0.85), in: Capsule())
                    .accessibilityLabel("\(group.activeItems.count) suggestions")
            }

            stepStatusRow(group)
            groupActionRow(group, isExpanded: isExpanded)

            if isManualProviderGapGroup(group) {
                manualProviderGapReview(for: group, isExpanded: isExpanded)
            } else {
                if !isExpanded {
                    simpleGroupSummary(for: group)
                } else {
                    groupCategoryPreview(for: group)
                }
            }

            if isExpanded && !isManualProviderGapGroup(group) {
                reviewCategoryPanels(for: group, showsHeader: false)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(palette.border, lineWidth: 1)
        )
        .accessibilityElement(children: .contain))
    }

    private func usesSettledSimpleGroupRow(_ group: LibraryPlanGroup, isExpanded: Bool) -> Bool {
        guard !isExpanded, isKnownMissingProviderGroup(group) || isMatchedProviderGroup(group) else {
            return false
        }
        return checkedCount(in: group) == 0
            && group.activeItems.contains(where: \.needsDecisionReview) == false
    }

    private func settledSimpleGroupRow(_ group: LibraryPlanGroup) -> some View {
        let isMatched = isMatchedProviderGroup(group)
        let title = isMatched
            ? "\(group.activeItems.count) saved provider ID\(group.activeItems.count == 1 ? "" : "s"). Nothing needs action unless an ID looks wrong."
            : "\(group.activeItems.count) saved No ID choice\(group.activeItems.count == 1 ? "" : "s"). Use Find Match if this provider has a record now."
        let buttonTitle = isMatched ? "Review IDs" : "Find Match"
        let helpText = isMatched
            ? "Open this saved-ID group if you want to re-check provider coverage."
            : "Open this saved No ID group if you want to search for a provider record again."

        return HStack(alignment: .center, spacing: 12) {
            Image(systemName: "checkmark.seal")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(group.title)
                    .font(.subheadline.weight(.semibold))
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Button {
                toggleReviewGroupExpansion(group)
            } label: {
                Label(buttonTitle, systemImage: "magnifyingglass")
            }
            .controlSize(.small)
            .disabled(group.activeItems.isEmpty)
            .help(helpText)
        }
        .padding(12)
        .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(palette.border.opacity(0.7), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(group.title). \(title)")
    }

    private func groupActionRow(_ group: LibraryPlanGroup, isExpanded: Bool) -> some View {
        HStack(spacing: 8) {
            if isKnownMissingProviderGroup(group) {
                Label("Saved No ID", systemImage: "checkmark.seal")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                    .help("These rows keep a saved No ID choice. Use Find Match on a row if this provider has a record now.")
            } else if isMatchedProviderGroup(group) {
                Label("Already matched", systemImage: "checkmark.seal")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                    .help("These rows already have saved provider IDs. Use Find Match on a row if one looks wrong.")
            } else if isManualProviderGapGroup(group) {
                Button {
                    dismissVisibleProviderGapRows(in: group)
                } label: {
                    Label("Mark Visible No ID", systemImage: "minus.circle")
                }
                .disabled(isWorking || visibleProviderGapItems(in: group).isEmpty)
                .help("Mark the currently visible missing-provider rows as No ID so Sable stops asking for this provider.")
            }

            Spacer(minLength: 0)

            Button {
                toggleReviewGroupExpansion(group)
            } label: {
                Label(
                    isExpanded ? "Hide Rows" : isKnownMissingProviderGroup(group) ? "Find Match" : isManualProviderGapGroup(group) ? "Review Choices" : "Show Rows",
                    systemImage: isExpanded ? "chevron.up" : "chevron.down"
                )
            }
            .disabled(group.activeItems.isEmpty)
            .help(isExpanded ? "Hide rows for this group." : isKnownMissingProviderGroup(group) ? "Show saved No ID rows so you can use Find Match if this provider has a record now." : "Show rows for this group.")

            Menu {
                if group.stage.usesComicInfoApplyEngine {
                    let passItems = applyableItems(in: group)
                    Button {
                        requestApply(
                            group.stage,
                            itemIDs: passItems.map(\.id),
                            scopeTitle: group.title
                        )
                    } label: {
                        Label("Run This Group", systemImage: "play.circle")
                    }
                    .disabled(isWorking || passItems.isEmpty)

                    Divider()
                }

                Button {
                    clearChecks(in: group)
                } label: {
                    Label("Clear This Group", systemImage: "xmark.circle")
                }
                .disabled(isWorking || checkedCount(in: group) == 0)

                if !isKnownMissingProviderGroup(group), !isManualProviderGapGroup(group) {
                    Button {
                        checkAllSafe(in: group)
                    } label: {
                        Label("Check Safe", systemImage: "checkmark.shield")
                    }
                    .disabled(isWorking || uncheckedSafeCount(in: group) == 0)

                    Button {
                        checkAllEligible(in: group)
                    } label: {
                        Label("Check All", systemImage: "checkmark.square")
                    }
                    .disabled(isWorking || uncheckedBulkCheckCount(in: group) == 0)
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .disabled(isWorking)
            .help("More controls for this group.")
        }
        .controlSize(.small)
    }

    @ViewBuilder
    private func manualProviderGapReview(for group: LibraryPlanGroup, isExpanded: Bool) -> some View {
        let rows = visibleProviderGapItems(in: group)

        VStack(alignment: .leading, spacing: 10) {
            Label(
                isMatchedProviderGroup(group)
                    ? "These AnimeInfo files already have saved IDs for this provider. Use Find Match only if one looks wrong."
                    : isKnownMissingProviderGroup(group)
                    ? "Saved No ID rows stay quiet by default. Use Find Match on a row if this provider has a record now."
                    : "90%+ matches with the right media type are already checked. No match rows stay unchecked; use No ID or Find Match.",
                systemImage: "person.text.rectangle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            if isExpanded {
                if rows.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("No visible provider questions", systemImage: "checkmark.seal")
                            .font(.subheadline.weight(.semibold))
                        Text(isReviewSearchActive ? "No rows match this search." : "Everything visible in this provider group has already been handled.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
                } else {
                    let rowLimit = providerGapVisibleRowLimit(for: group, totalCount: rows.count)
                    let previewRows = Array(rows.prefix(rowLimit))
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(previewRows) { item in
                            planItemRow(item)
                        }
                    }

                    if rows.count > previewRows.count {
                        providerGapMoreRowsControl(
                            for: group,
                            visibleCount: previewRows.count,
                            totalCount: rows.count
                        )
                    }
                }
            } else {
                let sampleRows = Array(rows.prefix(3))
                if !sampleRows.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(sampleRows) { item in
                            Text(searchTitle(for: item))
                                .font(.caption)
                                .lineLimit(1)
                                .foregroundStyle(.secondary)
                        }
                        if rows.count > sampleRows.count {
                            Text("\(rows.count - sampleRows.count) more hidden. Use Review Choices to work through this provider.")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.38), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private func providerGapMoreRowsControl(
        for group: LibraryPlanGroup,
        visibleCount: Int,
        totalCount: Int
    ) -> some View {
        let hiddenCount = max(0, totalCount - visibleCount)

        return HStack(alignment: .center, spacing: 8) {
            Label(
                "\(hiddenCount) more row\(hiddenCount == 1 ? "" : "s") hidden.",
                systemImage: "line.3.horizontal.decrease.circle"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Button {
                showMoreProviderGapRows(in: group, totalCount: totalCount)
            } label: {
                Label("Show More Rows", systemImage: "plus.circle")
            }
            .controlSize(.small)
            .disabled(hiddenCount == 0)
            .help("Show the next \(providerGapVisibleRowIncrement) rows in this provider group.")

            Button {
                showAllProviderGapRows(in: group, totalCount: totalCount)
            } label: {
                Label("Show All Rows", systemImage: "list.bullet")
            }
            .controlSize(.small)
            .disabled(hiddenCount == 0)
            .help("Show every row in this provider group.")
        }
        .padding(.top, 2)
    }

    private func groupCategoryPreview(for group: LibraryPlanGroup) -> some View {
        let summaries = reviewCategorySummaries(for: group)
        let diagnosticsOnly = stageHasOnlyManualDiagnostics([group])
        return SableEagerAdaptiveGrid(
            minimumItemWidth: 150,
            horizontalSpacing: 8,
            verticalSpacing: 8
        ) {
            ForEach(summaries) { summary in
                let isSelected = reviewCategoryScope.contains(summary.category)
                HStack(spacing: 8) {
                    Image(systemName: summary.category.symbolName)
                        .foregroundStyle(isSelected ? palette.accent : palette.textSecondary)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(summary.category.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(isSelected ? palette.textPrimary : palette.textSecondary)
                        Text(categoryPreviewText(summary, diagnosticsOnly: diagnosticsOnly))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    if summary.needsReviewCount > 0 {
                        Image(systemName: "questionmark.circle")
                            .foregroundStyle(palette.statusWarning)
                            .accessibilityLabel("\(summary.needsReviewCount) need review")
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.quaternary.opacity(isSelected ? 0.55 : 0.25), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? palette.accent.opacity(0.28) : palette.border.opacity(0.7), lineWidth: 1)
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(summary.category.title), \(summary.count) rows, \(summary.checkedCount) checked")
                .accessibilityValue(isSelected ? "Included" : "Skipped")
            }
        }
    }

    private func simpleGroupSummary(for group: LibraryPlanGroup) -> some View {
        let examples = Array(visibleItems(in: group).prefix(3))
        let checkedCount = checkedCount(in: group)
        let reviewCount = reviewCount(in: group)
        let conflicts = group.activeItems.filter { $0.safety == .collision }.count

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(simpleGroupSummaryTitle(for: group), systemImage: simpleGroupSummarySymbol(for: group))
                    .font(.subheadline.weight(.semibold))

                Spacer(minLength: 0)

                if checkedCount > 0 {
                    Text("\(checkedCount) ready")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(palette.accent.opacity(0.12), in: Capsule())
                }
            }

            Text(simpleGroupSummaryMessage(for: group, checkedCount: checkedCount, reviewCount: reviewCount, conflicts: conflicts))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !examples.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(examples) { item in
                        simpleExampleRow(for: item)
                    }

                    let hiddenCount = max(0, visibleItems(in: group).count - examples.count)
                    if hiddenCount > 0 {
                        Text("\(hiddenCount) more hidden. Use Show Rows or search when you want to inspect more.")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.32), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func simpleGroupSummaryTitle(for group: LibraryPlanGroup) -> String {
        if stageHasOnlyManualDiagnostics([group]) {
            return "Repair blocked"
        }
        let coverStatus = coverStatusProfile(in: group.activeItems)
        if coverStatus.noMatchCount == group.activeItems.count, coverStatus.noMatchCount > 0 {
            return "Search finished"
        }
        if coverStatus.optionalCount == group.activeItems.count, coverStatus.optionalCount > 0 {
            if group.activeItems.allSatisfy({
                $0.reviewTags.contains("cover-manifest-below-clinic-quality")
            }) {
                return "Archive quality"
            }
            return "Optional review"
        }
        if coverStatus.completeCount == group.activeItems.count, coverStatus.completeCount > 0 {
            return "Complete cover sets"
        }
        if reviewCount(in: group) > 0 {
            return "Choices waiting"
        }
        if checkedCount(in: group) > 0 {
            return "Ready batch"
        }
        return "Grouped suggestions"
    }

    private func simpleGroupSummarySymbol(for group: LibraryPlanGroup) -> String {
        if stageHasOnlyManualDiagnostics([group]) {
            return "exclamationmark.triangle"
        }
        let coverStatus = coverStatusProfile(in: group.activeItems)
        if coverStatus.noMatchCount == group.activeItems.count, coverStatus.noMatchCount > 0 {
            return "magnifyingglass.circle"
        }
        if coverStatus.optionalCount == group.activeItems.count, coverStatus.optionalCount > 0 {
            return "questionmark.folder"
        }
        if coverStatus.completeCount == group.activeItems.count, coverStatus.completeCount > 0 {
            return "checkmark.seal"
        }
        if reviewCount(in: group) > 0 {
            return "questionmark.circle"
        }
        if checkedCount(in: group) > 0 {
            return "checkmark.circle"
        }
        return "tray"
    }

    private func simpleGroupSummaryMessage(
        for group: LibraryPlanGroup,
        checkedCount: Int,
        reviewCount: Int,
        conflicts: Int
    ) -> String {
        if stageHasOnlyManualDiagnostics([group]) {
            return "These EPUB findings need a new repair rule or a cleaner source. Fixable rows show a checkbox and validate a temporary EPUB before apply."
        }
        let coverStatus = coverStatusProfile(in: group.activeItems)
        if coverStatus.noMatchCount == group.activeItems.count, coverStatus.noMatchCount > 0 {
            return "These searches have finished. Nothing is stuck or still running. Use Add Match to save an exact store series, then check only the rows you want to retry."
        }
        if coverStatus.optionalCount == group.activeItems.count, coverStatus.optionalCount > 0 {
            if group.activeItems.allSatisfy({
                $0.reviewTags.contains("cover-manifest-below-clinic-quality")
            }) {
                return "These correct covers are saved in the library. They are below Clinic's replacement floor, so no work is still running."
            }
            return "These complete local cover sets are left alone because their older manifests do not contain enough provider evidence for automatic verification."
        }
        if coverStatus.completeCount == group.activeItems.count, coverStatus.completeCount > 0 {
            return "These verified cover sets are complete and left unchecked. Select them only when you deliberately want to refresh good covers."
        }
        if reviewCount > 0 {
            return "\(reviewCount) row\(reviewCount == 1 ? "" : "s") need a real choice. Safe checked rows can wait while you answer those."
        }
        if checkedCount > 0 {
            let conflictText = conflicts == 0 ? "No conflicts are included." : "\(conflicts) conflict\(conflicts == 1 ? "" : "s") stay out until reviewed."
            let rowText = checkedCount == 1 ? "1 reversible row is" : "\(checkedCount) reversible rows are"
            return "\(rowText) already checked. \(conflictText)"
        }
        return "Nothing here is checked yet. Use Check All or open details when you want to inspect the list."
    }

    private func simpleExampleRow(for item: LibraryPlanItem) -> some View {
        let coverOutcome = coverOutcome(for: item)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(
                systemName: item.decision == .checked
                    ? "checkmark.circle.fill"
                    : coverOutcome?.symbol ?? "circle"
            )
                .foregroundStyle(item.decision == .checked ? palette.accent : palette.textSecondary)
                .accessibilityHidden(true)

            Text(simpleExampleTitle(for: item))
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 0)

            Text(
                item.decision == .checked
                    ? "Ready"
                    : coverOutcome?.label
                        ?? (isProtectedEPUBRepairItem(item)
                            ? "Protected"
                            : isManualDiagnosticItem(item)
                                ? "Blocked"
                                : item.needsDecisionReview ? "Needs choice" : "Waiting")
            )
                .font(.caption2.weight(.semibold))
                .foregroundStyle(item.needsDecisionReview ? palette.statusWarning : palette.textSecondary)
        }
    }

    private func simpleExampleTitle(for item: LibraryPlanItem) -> String {
        switch item.operation {
        case .renameFile, .cleanRawName:
            return URL(fileURLWithPath: item.proposedPath ?? item.currentPath).lastPathComponent
        case .renameFolder, .sortIntoFolder:
            return item.proposedPath ?? item.currentPath
        case .createComicInfo, .refreshComicInfo, .createAnimeInfo, .refreshAnimeInfo:
            return searchTitle(for: item)
        case .repairEpubPackage, .repairAppleBooksCompatibility:
            return URL(fileURLWithPath: item.currentPath).lastPathComponent
        case .inspectOnly, .duplicateDecision, .skip:
            return item.currentPath
        }
    }

    private func categoryPreviewText(_ summary: SableLibraryReviewCategorySummary, diagnosticsOnly: Bool) -> String {
        var parts: [String] = []
        if summary.checkedCount > 0 {
            parts.append("\(summary.checkedCount) ready")
        }
        if summary.needsReviewCount > 0 {
            parts.append(diagnosticsOnly
                ? "\(summary.needsReviewCount) blocked"
                : "\(summary.needsReviewCount) need choice")
        }
        if summary.noMatchCount > 0 {
            parts.append("\(summary.noMatchCount) no match")
        }
        if summary.optionalCount > 0 {
            parts.append("\(summary.optionalCount) optional")
        }
        if summary.completeCount > 0 {
            parts.append("\(summary.completeCount) complete")
        }
        let waitingCount = max(
            0,
            summary.count
                - summary.checkedCount
                - summary.needsReviewCount
                - summary.noMatchCount
                - summary.optionalCount
                - summary.completeCount
        )
        if waitingCount > 0 {
            parts.append("\(waitingCount) waiting")
        }
        if summary.visibleCount != summary.count {
            parts.append("\(summary.visibleCount) visible")
        }
        return parts.joined(separator: " · ")
    }

    private func stepStatusRow(_ group: LibraryPlanGroup) -> some View {
        Label(compactStatusText(for: group), systemImage: "list.bullet.rectangle")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func stageStatusRow(for groups: [LibraryPlanGroup]) -> some View {
        Label(compactStatusText(for: groups), systemImage: "list.bullet.rectangle")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func reviewScopeNotice(
        for stage: LibraryPipelineStage,
        groups: [LibraryPlanGroup]
    ) -> String? {
        guard isReviewSearchActive || isReviewCategoryScopeActive(in: groups) else {
            return nil
        }

        var sentences: [String] = []
        if isReviewSearchActive {
            let visibleCount = visibleItems(in: groups).count
            sentences.append("Search is showing \(visibleCount) row\(visibleCount == 1 ? "" : "s") in \(applyStageTitle(stage)). Bulk check and clear buttons affect visible rows only.")
            let hiddenSearchCount = hiddenCheckedBySearchCount(for: stage)
            if hiddenSearchCount > 0 {
                sentences.append("Apply still includes \(hiddenSearchCount) checked row\(hiddenSearchCount == 1 ? "" : "s") hidden by this search.")
            }
        }

        if isReviewCategoryScopeActive(in: groups) {
            sentences.append("Turned-off categories are unchecked before apply. Show All brings them back into view.")
        }

        return sentences.joined(separator: " ")
    }

    private var statusPillColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 112), spacing: 8, alignment: .leading)]
    }

    private func compactStatusText(for group: LibraryPlanGroup) -> String {
        if stageHasOnlyManualDiagnostics([group]) {
            return "\(group.activeItems.count) blocked"
        }
        if group.stage == .covers {
            return compactCoverStatusText(
                items: group.activeItems,
                groupCount: nil,
                skippedCount: group.skippedItems.count,
                visibleCount: isReviewFiltered(in: group) ? visibleItems(in: group).count : nil,
                hiddenCheckedCount: isReviewFiltered(in: group) ? hiddenCheckedCount(in: group) : 0
            )
        }

        return compactStatusText(
            activeCount: group.activeItems.count,
            checkedCount: checkedCount(in: group),
            reviewCount: reviewCount(in: group),
            groupCount: nil,
            skippedCount: group.skippedItems.count,
            visibleCount: isReviewFiltered(in: group) ? visibleItems(in: group).count : nil,
            hiddenCheckedCount: isReviewFiltered(in: group) ? hiddenCheckedCount(in: group) : 0
        )
    }

    private func compactStatusText(for groups: [LibraryPlanGroup]) -> String {
        let activeItems = groups.flatMap(\.activeItems)
        let skippedItems = groups.flatMap(\.skippedItems)
        if stageHasOnlyManualDiagnostics(groups) {
            return "\(activeItems.count) blocked"
        }
        if groups.allSatisfy({ $0.stage == .covers }) {
            return compactCoverStatusText(
                items: activeItems,
                groupCount: groups.count,
                skippedCount: skippedItems.count,
                visibleCount: isReviewFiltered(in: groups) ? visibleItems(in: groups).count : nil,
                hiddenCheckedCount: isReviewFiltered(in: groups) ? hiddenCheckedCount(in: groups) : 0
            )
        }

        return compactStatusText(
            activeCount: activeItems.count,
            checkedCount: checkedCount(in: groups),
            reviewCount: groups.flatMap(\.unresolvedItems).count,
            groupCount: groups.count,
            skippedCount: skippedItems.count,
            visibleCount: isReviewFiltered(in: groups) ? visibleItems(in: groups).count : nil,
            hiddenCheckedCount: isReviewFiltered(in: groups) ? hiddenCheckedCount(in: groups) : 0
        )
    }

    private func compactStatusText(
        activeCount: Int,
        checkedCount: Int,
        reviewCount: Int,
        groupCount: Int?,
        skippedCount: Int,
        visibleCount: Int?,
        hiddenCheckedCount: Int
    ) -> String {
        var parts: [String] = []
        if checkedCount > 0 {
            parts.append("\(checkedCount) ready")
        }
        if reviewCount > 0 {
            parts.append("\(reviewCount) need choice")
        }
        let waitingCount = max(0, activeCount - checkedCount - reviewCount)
        if waitingCount > 0 {
            parts.append("\(waitingCount) waiting")
        }
        if let groupCount, groupCount > 1 {
            parts.append("\(groupCount) groups")
        }
        if let visibleCount {
            parts.append("\(visibleCount) visible")
        }
        if hiddenCheckedCount > 0 {
            parts.append("\(hiddenCheckedCount) ready hidden")
        }
        if skippedCount > 0 {
            parts.append("\(skippedCount) skipped")
        }
        if isWorking {
            parts.append("working")
        }
        return parts.isEmpty ? "Nothing waiting" : parts.joined(separator: " · ")
    }

    private func compactCoverStatusText(
        items: [LibraryPlanItem],
        groupCount: Int?,
        skippedCount: Int,
        visibleCount: Int?,
        hiddenCheckedCount: Int
    ) -> String {
        let profile = coverStatusProfile(in: items)
        var parts: [String] = []
        if profile.checkedCount > 0 {
            parts.append("\(profile.checkedCount) ready")
        }
        if profile.reviewCount > 0 {
            parts.append("\(profile.reviewCount) need choice")
        }
        if profile.waitingCount > 0 {
            parts.append("\(profile.waitingCount) waiting")
        }
        if profile.noMatchCount > 0 {
            parts.append("\(profile.noMatchCount) no match")
        }
        if profile.optionalCount > 0 {
            parts.append("\(profile.optionalCount) optional")
        }
        if profile.completeCount > 0 {
            parts.append("\(profile.completeCount) complete")
        }
        if let groupCount, groupCount > 1 {
            parts.append("\(groupCount) groups")
        }
        if let visibleCount {
            parts.append("\(visibleCount) visible")
        }
        if hiddenCheckedCount > 0 {
            parts.append("\(hiddenCheckedCount) ready hidden")
        }
        if skippedCount > 0 {
            parts.append("\(skippedCount) skipped")
        }
        if isWorking {
            parts.append("working")
        }
        return parts.isEmpty ? "Nothing waiting" : parts.joined(separator: " · ")
    }

    private func stageSummaryText(
        for stage: LibraryPipelineStage,
        groups: [LibraryPlanGroup]
    ) -> String {
        let activeCount = groups.flatMap(\.activeItems).count
        let reviewCount = groups.flatMap(\.unresolvedItems).count
        let checkedCount = checkedCount(in: groups)
        let waitingCount = max(0, activeCount - reviewCount - checkedCount)
        let groupCount = groups.count

        if activeCount == 0 {
            if stage == .epubClinic {
                return "\(applyStageTitle(stage)) has no rows from this pass."
            }
            return "\(applyStageTitle(stage)) is clear."
        }

        if stage == .epubClinic, stageHasOnlyManualDiagnostics(groups) {
            return "\(activeCount) EPUB finding\(activeCount == 1 ? "" : "s") need a new repair rule or a clean source before Sable can change the file."
        }

        if stage == .covers {
            let coverItems = groups.flatMap(\.activeItems)
            let status = compactCoverStatusText(
                items: coverItems,
                groupCount: groups.count,
                skippedCount: groups.flatMap(\.skippedItems).count,
                visibleCount: nil,
                hiddenCheckedCount: 0
            )
            let seriesCount = Set(coverItems.map(\.currentPath)).count
            let totalText: String
            if seriesCount == 1 {
                totalText = activeCount == 1
                    ? "1 language check for 1 series"
                    : "\(activeCount) language checks for 1 series"
            } else {
                totalText = "\(activeCount) language checks across \(seriesCount) series"
            }
            return "\(status). \(totalText)."
        }

        var parts: [String] = []
        if reviewCount > 0 {
            parts.append("\(reviewCount) need choice")
        }
        if checkedCount > 0 {
            parts.append("\(checkedCount) ready")
        }
        if waitingCount > 0 {
            parts.append("\(waitingCount) waiting")
        }

        let groupText = groupCount == 1 ? "1 group" : "\(groupCount) groups"
        let totalText = activeCount == 1 ? "1 suggestion total" : "\(activeCount) suggestions total"
        return "\(parts.joined(separator: " · ")) in \(groupText). \(totalText)."
    }

    private func groupSummaryText(for group: LibraryPlanGroup) -> String {
        guard !group.skippedItems.isEmpty else { return group.summary }

        if group.activeItems.isEmpty {
            return "\(group.skippedItems.count) suggestion(s) skipped for this pass."
        }

        return "\(group.summary) \(group.skippedItems.count) skipped for this pass."
    }

    private func groupSymbol(for group: LibraryPlanGroup) -> String {
        if group.items.contains(where: { $0.operation == .repairEpubPackage || $0.operation == .repairAppleBooksCompatibility }) {
            return "wrench.and.screwdriver"
        }
        if group.items.contains(where: { $0.operation == .createComicInfo || $0.operation == .refreshComicInfo || $0.operation == .createAnimeInfo || $0.operation == .refreshAnimeInfo }) {
            return "doc.badge.gearshape"
        }
        if group.items.contains(where: { $0.operation == .sortIntoFolder }) {
            return "folder.badge.plus"
        }
        if group.items.contains(where: { $0.operation == .renameFile }) {
            return "pencil"
        }
        if group.items.contains(where: { $0.operation == .renameFolder }) {
            return "folder"
        }
        if group.items.contains(where: { $0.operation == .duplicateDecision }) {
            return "square.2.layers.3d"
        }
        return symbol(for: group.stage)
    }

    private func groupContextNote(for group: LibraryPlanGroup) -> String? {
        if group.stage == .covers {
            return "Each row is one language for one reading series. Japanese and English finish independently. Sable uses ComicInfo identity and type to search, rejects weak or undersized images, and keeps normal covers separate from special or alternative editions."
        }
        guard group.stage.isMetadataSidecarStage else {
            let ownerTitles = uniqueOwnerTitles(in: group)
            guard !ownerTitles.isEmpty else { return nil }
            let ownerText = ownerTitles.joined(separator: ownerTitles.count == 2 ? " and " : ", ")
            return "Sable grouped these under \(ownerText). Conflicts, project folders, and unclear moves stay out until you choose them."
        }

        let readingNetworkRows = group.activeItems.filter { item in
            item.usedNetworkData && (item.operation == .createComicInfo || item.operation == .refreshComicInfo)
        }
        let animeNetworkRows = group.activeItems.filter { item in
            item.usedNetworkData && (item.operation == .createAnimeInfo || item.operation == .refreshAnimeInfo)
        }

        if !readingNetworkRows.isEmpty && !animeNetworkRows.isEmpty {
            return "Checked reading and watching metadata rows can use enabled providers during apply. Fresh unchanged sidecars stay quiet."
        }

        if !readingNetworkRows.isEmpty {
            if group.activeItems.allSatisfy(\.requiresReview) {
                return "These provider questions wait for your choice. Use Find Match, paste an exact ID, mark No ID, or leave the row alone."
            }
            return "Checked refresh rows use saved IDs and request current provider data. RanobeDB adds new books and fills only details that are still missing."
        }

        if !animeNetworkRows.isEmpty {
            return "Checked watching metadata rows ask providers only when files changed or freshness expired. Weak matches keep the local sidecar."
        }

        if group.activeItems.contains(where: { $0.safety == .network }) {
            return "Provider-only rows are waiting for a clearer choice. Checked metadata rows in this page can still run."
        }

        if group.activeItems.contains(where: { $0.operation == .createComicInfo }) {
            return "Checked rows create local reading sidecars from folder names. Later rename and sort steps can use those titles safely."
        }

        if group.activeItems.contains(where: { $0.operation == .refreshComicInfo }) {
            return "Checked rows refresh existing reading sidecars. The date choice limits this to series whose local books changed in that period."
        }

        if group.activeItems.contains(where: { $0.operation == .createAnimeInfo }) {
            return "Checked rows create local watching sidecars from folder and video names."
        }

        if group.activeItems.contains(where: { $0.operation == .refreshAnimeInfo }) {
            return "Checked rows refresh existing watching sidecars. Providers run only when matches are strong and the sidecar needs fresh data."
        }

        return nil
    }

    private func uniqueOwnerTitles(in group: LibraryPlanGroup) -> [String] {
        var seen = Set<String>()
        return group.activeItems
            .map { SableLibraryMLCompany.owner(for: $0).title }
            .filter { seen.insert($0).inserted }
            .prefix(2)
            .map { $0 }
    }

    private func checkAllSafe(in group: LibraryPlanGroup) {
        let ids = bulkDecisionItems(in: group)
            .filter(isSafeBulkCheckItem)
            .filter { $0.decision != .checked }
            .map(\.id)
        guard !ids.isEmpty else { return }
        onBulkDecisionChange(ids, .checked)
    }

    private func checkAllSafe(in groups: [LibraryPlanGroup]) {
        let ids = groups
            .flatMap { bulkDecisionItems(in: $0) }
            .filter(isSafeBulkCheckItem)
            .filter { $0.decision != .checked }
            .map(\.id)
        guard !ids.isEmpty else { return }
        onBulkDecisionChange(ids, .checked)
    }

    private func checkAllEligible(in group: LibraryPlanGroup) {
        let ids = bulkDecisionItems(in: group)
            .filter(isBulkCheckItem)
            .filter { $0.decision != .checked }
            .map(\.id)
        guard !ids.isEmpty else { return }
        onBulkDecisionChange(ids, .checked)
    }

    private func checkAllEligible(in groups: [LibraryPlanGroup]) {
        let ids = groups
            .flatMap { bulkDecisionItems(in: $0) }
            .filter(isBulkCheckItem)
            .filter { $0.decision != .checked }
            .map(\.id)
        guard !ids.isEmpty else { return }
        onBulkDecisionChange(ids, .checked)
    }

    private func checkMissingCovers(in groups: [LibraryPlanGroup]) {
        let ids = groups
            .flatMap { bulkDecisionItems(in: $0) }
            .filter(hasCoverManifestGap)
            .filter { $0.decision != .checked }
            .map(\.id)
        guard !ids.isEmpty else { return }
        onBulkDecisionChange(ids, .checked)
    }

    private func uncheckedMissingCoverCount(in groups: [LibraryPlanGroup]) -> Int {
        groups
            .flatMap { bulkDecisionItems(in: $0) }
            .filter(hasCoverManifestGap)
            .filter { $0.decision != .checked }
            .count
    }

    private func hasCoverManifestGap(_ item: LibraryPlanItem) -> Bool {
        item.reviewTags.contains("cover-manifest-missing")
            || item.reviewTags.contains("cover-manifest-incomplete")
            || item.reviewTags.contains("cover-manifest-conflict")
    }

    private func checkAllSafe(in stage: LibraryPipelineStage, run: LibraryPipelineRun) {
        let ids = safeUncheckedItems(for: stage, in: run).map(\.id)
        guard !ids.isEmpty else { return }
        onBulkDecisionChange(ids, .checked)
    }

    private func clearChecks(in group: LibraryPlanGroup) {
        let ids = bulkDecisionItems(in: group)
            .filter { $0.decision == .checked }
            .map(\.id)
        guard !ids.isEmpty else { return }
        onBulkDecisionChange(ids, .unchecked)
    }

    private func uncheckedSafeCount(in group: LibraryPlanGroup) -> Int {
        bulkDecisionItems(in: group)
            .filter(isSafeBulkCheckItem)
            .filter { $0.decision != .checked }
            .count
    }

    private func uncheckedBulkCheckCount(in group: LibraryPlanGroup) -> Int {
        bulkDecisionItems(in: group)
            .filter(isBulkCheckItem)
            .filter { $0.decision != .checked }
            .count
    }

    private func clearChecks(in groups: [LibraryPlanGroup]) {
        let ids = groups
            .flatMap { bulkDecisionItems(in: $0) }
            .filter { $0.decision == .checked }
            .map(\.id)
        guard !ids.isEmpty else { return }
        onBulkDecisionChange(ids, .unchecked)
    }

    private func checkAllSafe(in category: SableLibraryReviewCategory, group: LibraryPlanGroup) {
        let ids = visibleItems(in: group, category: category)
            .filter(isSafeBulkCheckItem)
            .filter { $0.decision != .checked }
            .map(\.id)
        guard !ids.isEmpty else { return }
        changeCategoryDecisions(ids, to: .checked, category: category, group: group)
    }

    private func checkAllEligible(in category: SableLibraryReviewCategory, group: LibraryPlanGroup) {
        let ids = visibleItems(in: group, category: category)
            .filter(isBulkCheckItem)
            .filter { $0.decision != .checked }
            .map(\.id)
        guard !ids.isEmpty else { return }
        changeCategoryDecisions(ids, to: .checked, category: category, group: group)
    }

    private func clearChecks(in category: SableLibraryReviewCategory, group: LibraryPlanGroup) {
        let ids = group.items
            .filter { reviewCategory(for: $0) == category && $0.decision == .checked }
            .map(\.id)
        guard !ids.isEmpty else { return }
        changeCategoryDecisions(ids, to: .unchecked, category: category, group: group)
    }

    private func changeCategoryDecisions(
        _ ids: [LibraryPlanItem.ID],
        to decision: LibraryPlanDecision,
        category: SableLibraryReviewCategory,
        group: LibraryPlanGroup
    ) {
        collapseReviewCategory(category, in: group)
        Task { @MainActor in
            await Task.yield()
            onBulkDecisionChange(ids, decision)
        }
    }

    private func collapseReviewCategory(
        _ category: SableLibraryReviewCategory,
        in group: LibraryPlanGroup
    ) {
        expandedReviewCategories.remove(
            SableLibraryReviewCategoryExpansion(groupID: group.id, category: category)
        )
    }

    private func treatVisiblePDFsAsDocuments(in group: LibraryPlanGroup) {
        let ids = visibleItems(in: group, category: .pdfTriage)
            .filter(canUsePDFDocumentChoice)
            .map(\.id)
        guard !ids.isEmpty else { return }
        onBulkCorrection(ids, .treatAsDocument)
    }

    private func treatLikelyPDFsAsDocuments(in group: LibraryPlanGroup) {
        let ids = visibleItems(in: group, category: .pdfTriage)
            .filter(canUsePDFDocumentChoice)
            .filter(isLikelyDocumentPDFTriageItem)
            .map(\.id)
        guard !ids.isEmpty else { return }
        onBulkCorrection(ids, .treatAsDocument)
    }

    private func keepVisiblePDFsAsBooks(in group: LibraryPlanGroup) {
        let ids = visibleItems(in: group, category: .pdfTriage)
            .filter(canUsePDFBookChoice)
            .map(\.id)
        guard !ids.isEmpty else { return }
        onBulkCorrection(ids, .treatAsBook)
    }

    private func keepLikelyPDFsAsBooks(in group: LibraryPlanGroup) {
        let ids = visibleItems(in: group, category: .pdfTriage)
            .filter(canUsePDFBookChoice)
            .filter(isLikelyBookPDFTriageItem)
            .map(\.id)
        guard !ids.isEmpty else { return }
        onBulkCorrection(ids, .treatAsBook)
    }

    private func likelyPDFDocumentChoiceCount(in group: LibraryPlanGroup) -> Int {
        visibleItems(in: group, category: .pdfTriage)
            .filter(canUsePDFDocumentChoice)
            .filter(isLikelyDocumentPDFTriageItem)
            .count
    }

    private func likelyPDFBookChoiceCount(in group: LibraryPlanGroup) -> Int {
        visibleItems(in: group, category: .pdfTriage)
            .filter(canUsePDFBookChoice)
            .filter(isLikelyBookPDFTriageItem)
            .count
    }

    private func pdfDocumentChoiceCount(in group: LibraryPlanGroup) -> Int {
        visibleItems(in: group, category: .pdfTriage)
            .filter(canUsePDFDocumentChoice)
            .count
    }

    private func pdfBookChoiceCount(in group: LibraryPlanGroup) -> Int {
        visibleItems(in: group, category: .pdfTriage)
            .filter(canUsePDFBookChoice)
            .count
    }

    private func isSafeBulkCheckItem(_ item: LibraryPlanItem) -> Bool {
        item.safety == .reversible
            && !item.requiresReview
            && !item.usedNetworkData
            && !item.isNameCollisionResolution
            && !item.isFolderMergeResolution
            && !item.isDuplicateMoveAside
            && !item.isSkippedForPass
            && canCheck(item)
    }

    private func isSafeAutomationItem(_ item: LibraryPlanItem) -> Bool {
        guard item.safety == .reversible,
              !item.requiresReview,
              !item.isNameCollisionResolution,
              !item.isFolderMergeResolution,
              !item.isDuplicateMoveAside,
              !item.isSkippedForPass,
              canCheck(item) else {
            return false
        }

        if item.usedNetworkData {
            return item.stage.isMetadataSidecarStage && item.confidence != .low
        }

        return true
    }

    private func isBulkCheckItem(_ item: LibraryPlanItem) -> Bool {
        guard !item.isSkippedForPass,
              canCheck(item) else {
            return false
        }

        if item.stage == .covers {
            return item.safety == .reversible && !item.requiresReview
        }

        if item.stage == .providerMatches {
            return isProviderMatchBulkCheckItem(item)
        }

        if item.stage == .comicInfo {
            return isMetadataSidecarBulkCheckItem(item)
        }

        return !item.usedNetworkData
            && item.safety != .collision
    }

    private func isMetadataSidecarBulkCheckItem(_ item: LibraryPlanItem) -> Bool {
        guard item.stage == .comicInfo,
              item.safety == .reversible,
              !item.requiresReview,
              !item.isSkippedForPass,
              canCheck(item) else {
            return false
        }

        if !item.usedNetworkData { return true }
        switch item.operation {
        case .createComicInfo, .refreshComicInfo, .createAnimeInfo, .refreshAnimeInfo:
            return item.confidence != .low
        case .inspectOnly, .repairEpubPackage, .repairAppleBooksCompatibility, .cleanRawName, .sortIntoFolder, .renameFolder, .renameFile, .duplicateDecision, .skip:
            return false
        }
    }

    private func isProviderMatchBulkCheckItem(_ item: LibraryPlanItem) -> Bool {
        guard item.stage == .providerMatches,
              item.safety == .reversible,
              !item.requiresReview,
              !item.isSkippedForPass,
              canCheck(item) else {
            return false
        }

        if !item.usedNetworkData { return true }
        if item.reviewTags.contains("metadata-provider-precheck") { return true }
        if item.reviewTags.contains("manual-provider-match") && explicitProviderID(for: item) != nil { return true }
        if item.reviewTags.contains("metadata-provider-candidate-review") {
            return item.confidence == .high && explicitProviderID(for: item) != nil
        }
        return false
    }

    private func checkSafeHelpText(for group: LibraryPlanGroup) -> String {
        if uncheckedSafeCount(in: group) == 0 {
            return "No safe rows are waiting to be checked in this section."
        }
        return "Check only rows Sable already considers reversible and low-risk in this section. Review rows, conflicts, network-backed rows, and skipped rows stay out."
    }

    private func checkAllHelpText(for stage: LibraryPipelineStage, metrics: SableLibraryStageActionMetrics) -> String {
        if !metrics.hasBulkCheckItems {
            let matching = metrics.isFiltered ? "visible " : ""
            if stage == .covers {
                return "This cover step has no \(matching)series ready to select."
            }
            return stage.isMetadataSidecarStage
                ? "This metadata sidecar step has no \(matching)reversible rows to check."
                : "This review step has no \(matching)rows that can be checked together."
        }

        if metrics.uncheckedBulkCheckCount == 0 {
            return metrics.isFiltered
                ? "All visible checkable rows are already checked."
                : "All checkable rows in this step are already checked."
        }

        let scope = metrics.isFiltered ? "visible rows" : "this step"
        if stage == .covers {
            return "Select every series in \(scope). Nothing is downloaded until you choose Download Covers and confirm the batch."
        }
        if stage == .comicInfo {
            return "Check all visible reversible metadata rows in \(scope), including refresh rows. Refresh starts unchecked until you choose Check All."
        }
        if stage == .providerMatches {
            return "Check provider prechecks, exact ID choices, and 90%+ matches in \(scope). No-match questions stay out."
        }
        if stage.isMetadataSidecarStage {
            return "Check all local reversible metadata rows in \(scope). Provider lookup, manual-choice, conflict, and skipped rows stay out."
        }
        return "Check all rows in \(scope) that can be applied from this review page. Conflicts, network-backed rows, and skipped rows stay out."
    }

    private func checkAllHelpText(for group: LibraryPlanGroup) -> String {
        if uncheckedBulkCheckCount(in: group) == 0 {
            return "No checkable rows are waiting in this section."
        }
        if group.stage == .covers {
            return "Select every series in this section. Nothing is downloaded until you choose Download Covers and confirm the batch."
        }
        if group.stage == .comicInfo {
            return "Check every reversible metadata row in this section, including refresh rows. Refresh starts unchecked until you choose Check All."
        }
        if group.stage == .providerMatches {
            return "Check provider prechecks, exact ID choices, and 90%+ matches in this section. No-match questions stay out."
        }
        if group.stage.isMetadataSidecarStage {
            return "Check every local reversible metadata row in this section. Provider questions still need an ID, No ID, or a row-level choice."
        }
        return "Check every row in this section that can be applied from this page, including review rows. Conflicts, network-backed rows, and skipped rows stay out."
    }

    private func clearChecksHelpText(metrics: SableLibraryStageActionMetrics) -> String {
        if metrics.checkedCount == 0 {
            return metrics.isFiltered
                ? "No visible checked rows in this step."
                : "No checked rows in this step."
        }

        return metrics.isFiltered
            ? "Clear checked rows in the current category and search scope."
            : "Clear every checked row in this step."
    }

    private func applyHelpText(for stage: LibraryPipelineStage, metrics: SableLibraryStageActionMetrics) -> String {
        if metrics.applyCount > 0 {
            if stage == .covers {
                return "Download covers for checked series only. Sable rejects weak, wrong-type, chapter-only, and undersized results."
            }
            if stage == .providerMatches {
                return "Run checked provider teaching rows. Sable saves exact IDs or learned No ID choices, then refreshes the provider queue."
            }
            if stage == .comicInfo {
                return "Run the next metadata refresh pass. Sable saves useful checkpoints, reports weak matches, and refreshes the lane afterward."
            }
            return metrics.hasNetworkData
                ? "Apply checked rows. Metadata lookups run only for checked rows that still need fresh provider data."
                : "Apply only checked local changes in this step."
        }

        if stage.isMetadataSidecarStage, metrics.hasNetworkSafetyRows {
            return "This review step has no checked applyable metadata sidecar rows yet."
        }

        return "Check at least one local reversible change in this step first."
    }

    private func exactIDBatchHelpText(count: Int) -> String {
        "Refresh \(count) checked metadata row\(count == 1 ? "" : "s") that already have saved provider IDs. Rows that need search or review stay untouched."
    }

    private func visibleItems(in group: LibraryPlanGroup) -> [LibraryPlanItem] {
        group.activeItems.filter { item in
            reviewCategoryScope.contains(reviewCategory(for: item))
                && (!isReviewSearchActive || SableLibraryPlanSearch.matches(item, query: reviewSearchText))
        }
    }

    private func visibleItems(in groups: [LibraryPlanGroup]) -> [LibraryPlanItem] {
        groups.flatMap { visibleItems(in: $0) }
    }

    private func visibleItems(
        in group: LibraryPlanGroup,
        category: SableLibraryReviewCategory
    ) -> [LibraryPlanItem] {
        guard reviewCategoryScope.contains(category) else { return [] }
        return group.activeItems.filter { item in
            reviewCategory(for: item) == category
                && (!isReviewSearchActive || SableLibraryPlanSearch.matches(item, query: reviewSearchText))
        }
    }

    private func bulkDecisionItems(in group: LibraryPlanGroup) -> [LibraryPlanItem] {
        visibleItems(in: group)
    }

    private func isManualProviderGapGroup(_ group: LibraryPlanGroup) -> Bool {
        group.isManualProviderGapReviewGroup
    }

    private func isKnownMissingProviderGroup(_ group: LibraryPlanGroup) -> Bool {
        group.isKnownMissingProviderReviewGroup
    }

    private func isMatchedProviderGroup(_ group: LibraryPlanGroup) -> Bool {
        group.isMatchedProviderReviewGroup
    }

    private func isManualProviderGapItem(_ item: LibraryPlanItem) -> Bool {
        item.isManualProviderGapReviewItem
    }

    private func isKnownMissingProviderItem(_ item: LibraryPlanItem) -> Bool {
        item.isKnownMissingProviderReviewItem
    }

    private func isMatchedProviderItem(_ item: LibraryPlanItem) -> Bool {
        item.isMatchedProviderReviewItem
    }

    private func visibleProviderGapItems(in group: LibraryPlanGroup) -> [LibraryPlanItem] {
        visibleItems(in: group)
            .filter(isManualProviderGapItem)
            .sorted { lhs, rhs in
                lhs.currentPath.localizedStandardCompare(rhs.currentPath) == .orderedAscending
            }
    }

    private func providerGapVisibleRowLimit(for group: LibraryPlanGroup, totalCount: Int) -> Int {
        let savedLimit = providerGapVisibleRowLimits[group.id] ?? providerGapInitialVisibleRowLimit
        return min(totalCount, max(providerGapInitialVisibleRowLimit, savedLimit))
    }

    private func showMoreProviderGapRows(in group: LibraryPlanGroup, totalCount: Int) {
        let currentLimit = providerGapVisibleRowLimit(for: group, totalCount: totalCount)
        providerGapVisibleRowLimits[group.id] = min(totalCount, currentLimit + providerGapVisibleRowIncrement)
    }

    private func showAllProviderGapRows(in group: LibraryPlanGroup, totalCount: Int) {
        providerGapVisibleRowLimits[group.id] = totalCount
    }

    private func dismissVisibleProviderGapRows(in group: LibraryPlanGroup) {
        let ids = visibleProviderGapItems(in: group).map(\.id)
        guard !ids.isEmpty else { return }
        onBulkCorrection(ids, .providerNotAvailable)
    }

    private func checkedCount(in groups: [LibraryPlanGroup]) -> Int {
        groups
            .flatMap(\.items)
            .filter { $0.decision == .checked }
            .count
    }

    private func hiddenCheckedCount(in group: LibraryPlanGroup) -> Int {
        guard isReviewFiltered(in: group) else { return 0 }
        let visibleIDs = Set(visibleItems(in: group).map(\.id))
        return group.items.filter { item in
            item.decision == .checked && !visibleIDs.contains(item.id)
        }.count
    }

    private func hiddenCheckedCount(in groups: [LibraryPlanGroup]) -> Int {
        guard isReviewFiltered(in: groups) else { return 0 }
        let visibleIDs = Set(visibleItems(in: groups).map(\.id))
        return groups.flatMap(\.items).filter { item in
            item.decision == .checked && !visibleIDs.contains(item.id)
        }.count
    }

    private func isReviewFiltered(in groups: [LibraryPlanGroup]) -> Bool {
        isReviewSearchActive || isReviewCategoryScopeActive(in: groups)
    }

    private func toggleReviewCategoryExpansion(_ category: SableLibraryReviewCategory, in group: LibraryPlanGroup) {
        if group.stage == .covers, category == .images {
            let rows = visibleItems(in: group, category: category)
            guard !rows.isEmpty else { return }
            pendingCoverReviewPreview = SableLibraryCoverReviewPreview(
                title: group.title,
                items: Array(rows.prefix(reviewRowPreviewLimit))
            )
            return
        }

        let expansion = SableLibraryReviewCategoryExpansion(groupID: group.id, category: category)
        if expandedReviewCategories.contains(expansion) {
            expandedReviewCategories.remove(expansion)
        } else {
            expandedReviewCategories.insert(expansion)
        }
    }

    private func toggleReviewGroupExpansion(_ group: LibraryPlanGroup) {
        if expandedReviewGroups.contains(group.id) {
            expandedReviewGroups.remove(group.id)
        } else {
            expandedReviewGroups.insert(group.id)
        }
    }

    private func isReviewGroupExpanded(_ group: LibraryPlanGroup) -> Bool {
        expandedReviewGroups.contains(group.id)
    }

    private func reviewCategoryPanels(
        for group: LibraryPlanGroup,
        showsHeader: Bool = true
    ) -> some View {
        let summaries = reviewCategorySummaries(for: group)
        return VStack(alignment: .leading, spacing: 10) {
            if showsHeader {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Label("Categories", systemImage: "square.grid.2x2")
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 0)
                    Button {
                        reviewCategoryScope = SableLibraryReviewCategory.defaultScope
                    } label: {
                        Label("Show All", systemImage: "checkmark.square")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .disabled(reviewCategoryScope == SableLibraryReviewCategory.defaultScope)
                    .help("Show every category on this review page.")
                }

                if isReviewCategoryScopeActive(in: group) {
                    Label("Turned-off categories are cleared before apply. Show All brings them back into view.", systemImage: "eye.slash")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if summaries.isEmpty {
                reviewSearchEmptyState
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(summaries) { summary in
                        reviewCategoryPanel(summary, in: group)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func reviewCategoryPanel(_ summary: SableLibraryReviewCategorySummary, in group: LibraryPlanGroup) -> some View {
        let isSelected = reviewCategoryScope.contains(summary.category)
        let isExpanded = expandedReviewCategories.contains(SableLibraryReviewCategoryExpansion(groupID: group.id, category: summary.category))
        let rows = visibleItems(in: group, category: summary.category)
        let hasCheckableRows = rows.contains(where: canCheck)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: summary.category.symbolName)
                    .font(.title3)
                    .foregroundStyle(palette.accent)
                    .frame(width: 28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(summary.category.title)
                        .font(.headline)
                    Text(categorySummaryText(summary, isSelected: isSelected))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Toggle("Include", isOn: Binding(
                    get: { reviewCategoryScope.contains(summary.category) },
                    set: { setReviewCategory(summary.category, enabled: $0, in: group) }
                ))
                .labelsHidden()
                .disabled(isWorking)
                .accessibilityLabel("Include \(summary.category.title)")
            }

            HStack(spacing: 8) {
                if hasCheckableRows {
                    Button {
                        checkAllSafe(in: summary.category, group: group)
                    } label: {
                        Label("Check Safe", systemImage: "checkmark.shield")
                    }
                    .disabled(isWorking || !isSelected || summary.uncheckedSafeCount == 0)
                    .help("Check only already-safe rows in \(summary.category.title). Search still narrows which rows are affected.")

                    Button {
                        checkAllEligible(in: summary.category, group: group)
                    } label: {
                        Label("Check All", systemImage: "checkmark.square")
                    }
                    .disabled(isWorking || !isSelected || summary.uncheckedBulkCheckCount == 0)
                    .help("Check all checkable rows in \(summary.category.title). Search still narrows which rows are affected.")

                    Button {
                        clearChecks(in: summary.category, group: group)
                    } label: {
                        Label("Clear This Type", systemImage: "xmark.circle")
                    }
                    .disabled(isWorking || summary.checkedCount == 0)
                    .help("Clear checked rows in \(summary.category.title) for this step.")
                } else {
                    let isClinicGroup = group.stage == .epubClinic
                    Label(isClinicGroup ? "Blocked repairs" : "Inspect findings", systemImage: isClinicGroup ? "exclamationmark.triangle" : "magnifyingglass.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .help(isClinicGroup
                            ? "These Clinic rows stay visible because Sable needs a new repair rule or a clean source."
                            : "These rows are diagnostic notes that stay visible for review.")
                }

                if summary.category == .pdfTriage {
                    Menu {
                        Button("Treat Likely Documents") {
                            treatLikelyPDFsAsDocuments(in: group)
                        }
                        .disabled(likelyPDFDocumentChoiceCount(in: group) == 0)

                        Button("Keep Likely Books") {
                            keepLikelyPDFsAsBooks(in: group)
                        }
                        .disabled(likelyPDFBookChoiceCount(in: group) == 0)

                        Divider()

                        Button("Treat Visible as Documents") {
                            treatVisiblePDFsAsDocuments(in: group)
                        }
                        .disabled(pdfDocumentChoiceCount(in: group) == 0)

                        Button("Keep Visible as Books") {
                            keepVisiblePDFsAsBooks(in: group)
                        }
                        .disabled(pdfBookChoiceCount(in: group) == 0)
                    } label: {
                        Label("Triage PDFs", systemImage: "wand.and.stars")
                    }
                    .disabled(isWorking || !isSelected || summary.count == 0)
                    .help("Use confidence and search filters to mark PDF rows as documents or keep them out of document cleanup as books.")
                }

                Spacer(minLength: 0)

                Button {
                    toggleReviewCategoryExpansion(summary.category, in: group)
                } label: {
                    Label(isExpanded ? "Hide Rows" : "Show Rows", systemImage: isExpanded ? "chevron.up" : "chevron.down")
                }
                .disabled(!isSelected || summary.count == 0)
                .help(isExpanded ? "Hide rows in this category." : "Show a limited row preview for this category.")
            }
            .controlSize(.small)

            if !isSelected {
                Label("\(summary.category.title) rows are out of this apply.", systemImage: "eye.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if isExpanded {
                if rows.isEmpty {
                    reviewCategoryEmptyState(for: summary.category)
                } else {
                    reviewFileTypeSections(for: rows, category: summary.category)
                }
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? palette.accent.opacity(0.36) : palette.border, lineWidth: 1)
        )
        .accessibilityLabel("\(summary.category.title), \(summary.count) rows, \(summary.checkedCount) checked")
        .accessibilityValue(isSelected ? "Included" : "Skipped")
    }

    private func reviewFileTypeSections(
        for rows: [LibraryPlanItem],
        category: SableLibraryReviewCategory
    ) -> some View {
        let buckets = reviewFileTypeBuckets(for: rows)
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(buckets.prefix(reviewRowPreviewLimit))) { bucket in
                reviewFileTypeSection(bucket, category: category)
            }

            if buckets.count > reviewRowPreviewLimit {
                Label(
                    "Showing the first \(reviewRowPreviewLimit) of \(buckets.count) file types. Search can narrow this category.",
                    systemImage: "line.3.horizontal.decrease.circle"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }
        }
    }

    private func reviewFileTypeSection(
        _ bucket: SableLibraryReviewFileTypeBucket,
        category: SableLibraryReviewCategory
    ) -> some View {
        let rowLimit = 5
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(bucket.title, systemImage: reviewFileTypeSymbol(for: bucket.key, category: category))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("\(bucket.rows.count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary.opacity(0.7), in: Capsule())
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(bucket.rows.prefix(rowLimit))) { item in
                    planItemRow(item)
                }
            }

            if bucket.rows.count > rowLimit {
                Label(
                    "Showing \(rowLimit) examples of \(bucket.rows.count). Search can narrow this list.",
                    systemImage: "line.3.horizontal.decrease.circle"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.38), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
    }

    private func categorySummaryText(
        _ summary: SableLibraryReviewCategorySummary,
        isSelected: Bool
    ) -> String {
        if !isSelected {
            return "Skipped as a category for this apply."
        }
        if isReviewSearchActive && summary.visibleCount == 0 {
            return "No rows match the current search."
        }
        if summary.category == .pdfTriage {
            let leftAloneCount = max(0, summary.count - summary.checkedCount - summary.needsReviewCount)
            if summary.needsReviewCount > 0 {
                return "\(summary.checkedCount) suggested document row(s), \(leftAloneCount) left alone, \(summary.needsReviewCount) blocked."
            }
            if summary.checkedCount > 0 {
                return "\(summary.checkedCount) PDF document row(s) ready for Documents; \(leftAloneCount) left alone unless you choose them."
            }
            if leftAloneCount > 0 {
                return "\(leftAloneCount) PDF row(s) are left alone unless you choose Documents."
            }
            return "PDF rows stay quiet until Sable finds a strong clue or you choose a type."
        }
        if summary.category == .shelves {
            if summary.needsReviewCount > 0 {
                return "\(summary.needsReviewCount) shelf move\(summary.needsReviewCount == 1 ? "" : "s") need approval. Use the shelf buckets below instead of reviewing every series one by one."
            }
            if summary.checkedCount > 0 {
                return "\(summary.checkedCount) shelf move\(summary.checkedCount == 1 ? "" : "s") ready. Rows are grouped by main shelf."
            }
            return "Shelf moves stay unchecked until you approve the suggested shelf."
        }
        if summary.checkedCount == 0 {
            if summary.needsReviewCount == summary.count && summary.uncheckedBulkCheckCount == 0 {
                return "Blocked repair findings. Fixable EPUB problems should appear as checked repair rows; these need a clean source or a new repair rule."
            }
            return "Nothing checked yet. Use Check All to include this type."
        }
        return "\(summary.checkedCount) checked row(s) ready in \(summary.category.title)."
    }

    private func categoryCountChip(_ label: String, value: Int, symbol: String) -> some View {
        Label("\(label) \(value)", systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(value > 0 ? 0.85 : 0.35), in: Capsule())
            .accessibilityLabel("\(label): \(value)")
    }

    private func reviewCategoryEmptyState(for category: SableLibraryReviewCategory) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("No visible \(category.title.lowercased()) rows", systemImage: "magnifyingglass")
                .font(.subheadline.weight(.semibold))
            Text(isReviewSearchActive ? "No rows in this category match the current search." : "This category has no rows to show right now.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }

    private func coverReviewPreviewSheet(_ preview: SableLibraryCoverReviewPreview) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.title2)
                    .foregroundStyle(palette.accent)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(preview.title)
                        .font(.title3.weight(.semibold))
                    Text("\(preview.items.count) cover series")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Button("Done") {
                    pendingCoverReviewPreview = nil
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(preview.items) { item in
                        coverReviewPreviewRow(item)
                    }
                }
                .padding(20)
            }
        }
        .frame(minWidth: 720, idealWidth: 860, minHeight: 480, idealHeight: 660)
    }

    private func coverReviewPreviewRow(_ item: LibraryPlanItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(compactMetadataTitle(for: item))
                    .font(.headline)
                    .lineLimit(2)

                Spacer(minLength: 0)

                if let request = coverSearchRequest(for: item) {
                    Button {
                        pendingCoverReviewPreview = nil
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(200))
                            pendingCoverSearch = request
                        }
                    } label: {
                        Label("Find Cover", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isWorking)
                }

                Button {
                    revealPathInFinder(item.currentPath, revealParent: true)
                } label: {
                    Label("Reveal", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isWorking)
            }

            Text(item.reason)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Label(
                    item.requestedCoverLanguages == ["jp"] ? "Japanese" : "English",
                    systemImage: "character.book.closed"
                )
                Label("Archive 500 x 700", systemImage: "rectangle.inset.filled")
                Label("Clinic 800 x 1100", systemImage: "cross.case")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            Label(compactMetadataLocationText(for: item), systemImage: "folder")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
    }

    private struct SableLibraryCoverOutcome {
        var label: String
        var symbol: String
    }

    private struct SableLibraryCoverStatusProfile {
        var checkedCount: Int
        var reviewCount: Int
        var noMatchCount: Int
        var optionalCount: Int
        var completeCount: Int
        var waitingCount: Int
    }

    private func coverOutcome(for item: LibraryPlanItem) -> SableLibraryCoverOutcome? {
        guard item.stage == .covers, item.decision != .checked else { return nil }
        if item.reviewTags.contains("cover-manifest-no-result") {
            return SableLibraryCoverOutcome(label: "No match", symbol: "magnifyingglass.circle")
        }
        if item.reviewTags.contains("cover-manifest-unproven-no-result") {
            return SableLibraryCoverOutcome(label: "No replacement", symbol: "magnifyingglass.circle")
        }
        if item.reviewTags.contains("cover-manifest-unverified") {
            return SableLibraryCoverOutcome(label: "Ready to verify", symbol: "checkmark.shield")
        }
        if item.reviewTags.contains("cover-manifest-needs-store-check") {
            return SableLibraryCoverOutcome(label: "Ready to replace", symbol: "arrow.triangle.2.circlepath")
        }
        if item.reviewTags.contains("cover-manifest-below-clinic-quality") {
            return SableLibraryCoverOutcome(label: "Archive only", symbol: "archivebox")
        }
        if item.reviewTags.contains("cover-manifest-present") {
            return SableLibraryCoverOutcome(label: "Complete", symbol: "checkmark.seal")
        }
        return nil
    }

    private func coverStatusProfile(in items: [LibraryPlanItem]) -> SableLibraryCoverStatusProfile {
        let checkedCount = items.filter { $0.decision == .checked }.count
        let reviewCount = items.filter(\.needsDecisionReview).count
        let noMatchCount = items.filter {
            $0.decision != .checked
                && (
                    $0.reviewTags.contains("cover-manifest-no-result")
                        || $0.reviewTags.contains("cover-manifest-unproven-no-result")
                )
        }.count
        let optionalCount = items.filter {
            $0.decision != .checked
                && (
                    $0.reviewTags.contains("cover-manifest-unverified")
                        || $0.reviewTags.contains("cover-manifest-below-clinic-quality")
                )
        }.count
        let completeCount = items.filter {
            $0.decision != .checked && $0.reviewTags.contains("cover-manifest-present")
        }.count
        let waitingCount = max(
            0,
            items.count
                - checkedCount
                - reviewCount
                - noMatchCount
                - optionalCount
                - completeCount
        )
        return SableLibraryCoverStatusProfile(
            checkedCount: checkedCount,
            reviewCount: reviewCount,
            noMatchCount: noMatchCount,
            optionalCount: optionalCount,
            completeCount: completeCount,
            waitingCount: waitingCount
        )
    }

    private struct SableLibraryReviewCategorySummary: Identifiable {
        var id: SableLibraryReviewCategory { category }
        var category: SableLibraryReviewCategory
        var count: Int
        var visibleCount: Int
        var checkedCount: Int
        var needsReviewCount: Int
        var noMatchCount: Int
        var optionalCount: Int
        var completeCount: Int
        var uncheckedSafeCount: Int
        var uncheckedBulkCheckCount: Int
    }

    private struct SableLibraryReviewFileTypeBucket: Identifiable {
        var id: String { key }
        var key: String
        var title: String
        var symbolName: String
        var rows: [LibraryPlanItem]
    }

    private func reviewCategorySummaries(for group: LibraryPlanGroup) -> [SableLibraryReviewCategorySummary] {
        SableLibraryReviewCategory.allCases.compactMap { category in
            let items = group.activeItems.filter { reviewCategory(for: $0) == category }
            guard !items.isEmpty else { return nil }
            let visible = visibleItems(in: group, category: category)
            let coverStatus = coverStatusProfile(in: items)
            return SableLibraryReviewCategorySummary(
                category: category,
                count: items.count,
                visibleCount: visible.count,
                checkedCount: items.filter { $0.decision == .checked }.count,
                needsReviewCount: items.filter(\.needsDecisionReview).count,
                noMatchCount: coverStatus.noMatchCount,
                optionalCount: coverStatus.optionalCount,
                completeCount: coverStatus.completeCount,
                uncheckedSafeCount: visible
                    .filter(isSafeBulkCheckItem)
                    .filter { $0.decision != .checked }
                    .count,
                uncheckedBulkCheckCount: visible
                    .filter(isBulkCheckItem)
                    .filter { $0.decision != .checked }
                    .count
            )
        }
    }

    private func reviewFileTypeBuckets(for rows: [LibraryPlanItem]) -> [SableLibraryReviewFileTypeBucket] {
        let grouped = Dictionary(grouping: rows) { item in
            reviewFileTypeKey(for: item)
        }
        return grouped.map { key, bucketRows in
            SableLibraryReviewFileTypeBucket(
                key: key,
                title: reviewFileTypeTitle(for: key),
                symbolName: reviewFileTypeSymbol(for: key),
                rows: bucketRows.sorted { lhs, rhs in
                    lhs.currentPath.localizedStandardCompare(rhs.currentPath) == .orderedAscending
                }
            )
        }
        .sorted { lhs, rhs in
            if lhs.rows.count != rhs.rows.count {
                return lhs.rows.count > rhs.rows.count
            }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    private func reviewFileTypeKey(for item: LibraryPlanItem) -> String {
        if isSSSFolderSortingItem(item) {
            return "sss|\(targetSSSFolderTitle(for: item) ?? "Shelf review")"
        }

        if item.operation == .renameFolder {
            return "folder"
        }

        let currentExtension = (item.currentPath as NSString).pathExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !currentExtension.isEmpty {
            return currentExtension
        }

        if let proposedPath = item.proposedPath {
            let proposedExtension = (proposedPath as NSString).pathExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !proposedExtension.isEmpty {
                return proposedExtension
            }
        }

        return item.proposedPath == nil ? "note" : "unknown"
    }

    private func reviewFileTypeTitle(for key: String) -> String {
        if key.hasPrefix("sss|") {
            return String(key.dropFirst(4))
        }

        switch key {
        case "folder": return "Folders"
        case "note": return "Notes"
        case "unknown": return "Unknown type"
        default: return ".\(key)"
        }
    }

    private func reviewFileTypeSymbol(for key: String) -> String {
        if key.hasPrefix("sss|") {
            return SableLibraryReviewCategory.shelves.symbolName
        }

        switch key {
        case "folder": return "folder"
        case "epub", "kepub", "mobi", "azw", "azw3", "pdf", "cbz", "cbr", "cb7": return "book"
        case "mp4", "mkv", "mov", "avi", "m4v", "webm": return "play.rectangle"
        case "srt", "ass", "vtt", "ssa": return "captions.bubble"
        case "jpg", "jpeg", "png", "gif", "webp", "heic", "tiff": return "photo"
        case "mp3", "m4a", "flac", "wav", "aac", "ogg": return "waveform"
        case "zip", "rar", "7z", "tar", "gz": return "archivebox"
        case "json", "xml", "opf": return "doc.badge.gearshape"
        case "note": return "note.text"
        default: return "doc"
        }
    }

    private func reviewFileTypeSymbol(for key: String, category: SableLibraryReviewCategory) -> String {
        if category == .pdfTriage, key == "pdf" {
            return SableLibraryReviewCategory.pdfTriage.symbolName
        }
        return reviewFileTypeSymbol(for: key)
    }

    private func setReviewCategory(
        _ category: SableLibraryReviewCategory,
        enabled: Bool,
        in group: LibraryPlanGroup
    ) {
        if enabled {
            reviewCategoryScope.insert(category)
            return
        }

        reviewCategoryScope.remove(category)
        let checkedIDs = run?.context.plan.items
            .filter { item in
                item.stage == group.stage
                    && reviewCategory(for: item) == category
                    && item.decision == .checked
            }
            .map(\.id) ?? []
        if !checkedIDs.isEmpty {
            onBulkDecisionChange(checkedIDs, .unchecked)
        }
    }

    @discardableResult
    private func clearHiddenCheckedRows(for stage: LibraryPipelineStage) -> Int {
        let checkedIDs = run?.context.plan.items
            .filter { item in
                item.stage == stage
                    && item.decision == .checked
                    && !reviewCategoryScope.contains(reviewCategory(for: item))
            }
            .map(\.id) ?? []
        if !checkedIDs.isEmpty {
            onBulkDecisionChange(checkedIDs, .unchecked)
        }
        return checkedIDs.count
    }

    private func hiddenCheckedBySearchCount(
        for stage: LibraryPipelineStage,
        limitingTo itemIDs: Set<LibraryPlanItem.ID>? = nil
    ) -> Int {
        guard isReviewSearchActive else { return 0 }
        return run?.context.plan.items
            .filter { item in
                item.stage == stage
                    && item.decision == .checked
                    && item.isApplyableOperation
                    && reviewCategoryScope.contains(reviewCategory(for: item))
                    && (itemIDs?.contains(item.id) ?? true)
                    && !SableLibraryPlanSearch.matches(item, query: reviewSearchText)
            }
            .count ?? 0
    }

    private func reviewCategory(for item: LibraryPlanItem) -> SableLibraryReviewCategory {
        if item.isEmptySortingFolderCleanup {
            return .folders
        }
        if isPDFDocumentTriageItem(item) {
            return .pdfTriage
        }
        if isSSSFolderSortingItem(item) {
            return .shelves
        }
        if item.stage == .covers {
            return .images
        }

        switch item.operation {
        case .repairEpubPackage, .repairAppleBooksCompatibility:
            return .repairs
        case .createComicInfo, .refreshComicInfo, .createAnimeInfo, .refreshAnimeInfo:
            return .metadata
        case .renameFolder:
            return .folders
        case .duplicateDecision:
            return .duplicates
        case .inspectOnly, .skip:
            return .other
        case .cleanRawName, .sortIntoFolder, .renameFile:
            if isPDFPlanItem(item) {
                return .books
            }
            return reviewCategory(forPath: item.proposedPath ?? item.currentPath)
        }
    }

    private func isPDFPlanItem(_ item: LibraryPlanItem) -> Bool {
        isPDFDocumentTriageItem(item)
            || ([item.currentPath] + [item.proposedPath].compactMap { $0 }).contains { path in
            (path as NSString).pathExtension.caseInsensitiveCompare("pdf") == .orderedSame
        }
    }

    private func isPDFDocumentTriageItem(_ item: LibraryPlanItem) -> Bool {
        guard item.stage == .prepareRawFiles,
              item.reviewTags.contains("pdf-triage") || item.correctionOptions.contains(.treatAsDocument),
              let proposedPath = item.proposedPath else {
            return false
        }

        return item.correctionOptions.contains(.treatAsDocument)
            || proposedPath == "Documents/\((item.currentPath as NSString).lastPathComponent)"
            || proposedPath.hasPrefix("Documents/")
    }

    private func isLikelyDocumentPDFTriageItem(_ item: LibraryPlanItem) -> Bool {
        item.reviewTags.contains("likely-document")
    }

    private func isLikelyBookPDFTriageItem(_ item: LibraryPlanItem) -> Bool {
        item.reviewTags.contains("likely-book")
    }

    private func canUsePDFDocumentChoice(_ item: LibraryPlanItem) -> Bool {
        isPDFDocumentTriageItem(item)
            && item.decision != .checked
            && item.proposedPath != nil
            && item.correctionOptions.contains(.treatAsDocument)
    }

    private func canUsePDFBookChoice(_ item: LibraryPlanItem) -> Bool {
        isPDFDocumentTriageItem(item)
            && item.correctionOptions.contains(.treatAsBook)
    }

    private func reviewCategory(forPath path: String) -> SableLibraryReviewCategory {
        let ext = (path as NSString).pathExtension.lowercased()
        if bookReviewExtensions.contains(ext) { return .books }
        if videoReviewExtensions.contains(ext) || subtitleReviewExtensions.contains(ext) { return .videos }
        if documentReviewExtensions.contains(ext) { return .documents }
        if imageReviewExtensions.contains(ext) { return .images }
        if audioReviewExtensions.contains(ext) { return .audio }
        if archiveReviewExtensions.contains(ext) { return .archives }
        return .other
    }

    private var bookReviewExtensions: Set<String> {
        ["epub", "pdf", "kepub", "cbz", "cbr", "cb7", "mobi", "azw", "azw3", "ibooks", "iba", "djvu"]
    }

    private var videoReviewExtensions: Set<String> {
        ["mkv", "mp4", "m4v", "avi", "mov", "wmv", "webm", "ts", "m2ts"]
    }

    private var subtitleReviewExtensions: Set<String> {
        ["srt", "ass", "ssa", "vtt"]
    }

    private var documentReviewExtensions: Set<String> {
        ["txt", "md", "rtf", "doc", "docx", "pages", "numbers", "key", "csv", "json", "xml", "html", "ppt", "pptx", "xls", "xlsx"]
    }

    private var imageReviewExtensions: Set<String> {
        ["jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "tiff", "bmp", "svg"]
    }

    private var audioReviewExtensions: Set<String> {
        ["mp3", "m4a", "aac", "flac", "wav", "aiff", "ogg", "opus"]
    }

    private var archiveReviewExtensions: Set<String> {
        ["zip", "rar", "7z", "tar", "gz", "bz2", "xz"]
    }

    private var reviewSearchControls: some View {
        HStack(spacing: 10) {
            SableLibrarySearchField(
                text: $reviewSearchText,
                placeholder: "Paths, reasons, safety"
            )
            .frame(minWidth: 220, maxWidth: 360)
            .accessibilityLabel("Search review suggestions")
            .accessibilityValue(reviewSearchText)
            .accessibilityHint("Filters the current review step while you type.")

            Spacer(minLength: 0)
        }
    }

    private var reviewSearchEmptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("No matching suggestions", systemImage: "magnifyingglass")
                .font(.subheadline.weight(.semibold))
            Text("No rows match \"\(reviewSearchText)\".")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }

    private func statusPill(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .lineLimit(1)
            .truncationMode(.tail)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: Capsule())
            .accessibilityLabel(text)
    }

    private func planItemRow(_ item: LibraryPlanItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            planItemSelectionControl(item)

            VStack(alignment: .leading, spacing: 7) {
                if item.stage == .covers {
                    compactCoverRowContent(for: item)
                } else if usesCompactMetadataRow(item) {
                    compactMetadataRowContent(for: item)
                } else if usesCompactRenameRow(item) {
                    compactRenameRowContent(for: item)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(reviewRowTitle(for: item))
                            .font(.subheadline.weight(.semibold))
                        confidenceBadge(item)
                        safetyBadge(item)
                        Spacer(minLength: 0)
                        pathActionsMenu(for: item)
                        correctionMenu(for: item)
                    }

                    Text(displayReason(for: item))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let explanation = displayConfidenceExplanation(for: item), !explanation.isEmpty {
                        Text(explanation)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    mangaBakaMatchReview(for: item)

                    pathChange(for: item)
                }

                if let rejection = item.rejectionReason {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Skipped: \(rejection.option.title)", systemImage: "arrow.uturn.backward")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        TextField(
                            "Optional note",
                            text: Binding(
                                get: { rejection.note },
                                set: { onCorrectionNoteChange(item.id, $0) }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .disabled(isWorking)
                    }
                } else if isManualDiagnosticItem(item) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(epubDiagnosticProblemText(for: item), systemImage: "exclamationmark.triangle")
                        Label(epubDiagnosticRepairText(for: item), systemImage: "wrench.adjustable")
                        Label("Use a clean source, or add a real repair rule so this becomes a checked repair row.", systemImage: "checkmark.shield")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                } else if !canCheck(item), let reason = disabledReason(for: item) {
                    Label(reason, systemImage: "lock")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            if focusedPlanItemID == item.id {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(palette.focusRing, lineWidth: 2)
                    .accessibilityHidden(true)
            }
        }
        .focusable(!isWorking)
        .focused($focusedPlanItemID, equals: item.id)
        .onKeyPress(.space) {
            guard togglePlanItemCheck(item) else { return .ignored }
            return .handled
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(planItemAccessibilityLabel(item))
        .accessibilityValue(planItemAccessibilityValue(item))
        .accessibilityHint(planItemAccessibilityHint(item))
        .sableAccessibilityAction(canCheck(item), named: item.decision == .checked ? "Uncheck suggestion" : "Check suggestion") {
            _ = togglePlanItemCheck(item)
        }
        .sableAccessibilityAction(providerSearchRequest(for: item) != nil, named: "Find provider match") {
            if let request = providerSearchRequest(for: item) {
                pendingProviderSearch = request
            }
        }
        .sableAccessibilityAction(coverSearchRequest(for: item) != nil, named: "Find cover series") {
            if let request = coverSearchRequest(for: item) {
                pendingCoverSearch = request
            }
        }
        .sableAccessibilityAction(canUseCollisionResolution(for: item), named: "Move existing aside") {
            onCorrection(item.id, .moveExistingAside)
        }
        .sableAccessibilityAction(canUseFolderMerge(for: item), named: "Merge into existing folder") {
            onCorrection(item.id, .mergeIntoExisting)
        }
        .sableAccessibilityAction(canUseDuplicateMoveAside(for: item), named: "Move duplicate aside") {
            onCorrection(item.id, .moveExistingAside)
        }
        .sableAccessibilityAction(canUseDuplicateMoveAside(for: item), named: "Keep both copies") {
            onCorrection(item.id, .notADuplicate)
        }
        .sableAccessibilityAction(canUsePDFDocumentChoice(item), named: "Treat as document") {
            onCorrection(item.id, .treatAsDocument)
        }
        .sableAccessibilityAction(canUsePDFBookChoice(item), named: "Keep as book") {
            onCorrection(item.id, .treatAsBook)
        }
        .sableAccessibilityAction(canUseLocalTitle(for: item), named: "Use local title") {
            onCorrection(item.id, .keepTitle)
        }
        .sableAccessibilityAction(item.proposedPath != nil, named: "Copy suggested change") {
            copyText(suggestedChangeText(for: item))
        }
        .sableContextMenu(item.stage != .covers) {
            if item.stage != .covers {
                pathActionItems(for: item)
                if canUseLocalTitle(for: item) {
                    Divider()
                    useLocalTitleAction(for: item)
                }
            }
        }
    }

    @ViewBuilder
    private func compactCoverRowContent(for item: LibraryPlanItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(compactMetadataTitle(for: item))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)

            Label(
                item.decision == .checked ? "Selected" : "Cover set",
                systemImage: item.decision == .checked ? "checkmark.circle.fill" : "photo.on.rectangle.angled"
            )
            .font(.caption2.weight(.semibold))
            .foregroundStyle(item.decision == .checked ? palette.accent : .secondary)

            Spacer(minLength: 0)

            if let request = coverSearchRequest(for: item) {
                Button {
                    pendingCoverSearch = request
                } label: {
                    let needsStoreProof =
                        item.reviewTags.contains("cover-manifest-unverified")
                    Label(
                        needsStoreProof
                            ? "Add Store Proof"
                            : (
                                item.manualCoverSeriesMatches.isEmpty
                                    ? "Find Cover"
                                    : "Add Match"
                            ),
                        systemImage: "magnifyingglass"
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isWorking)
                .help(
                    item.reviewTags.contains("cover-manifest-unverified")
                        ? "Choose the exact store series to verify covers that are already downloaded."
                        : "Choose an exact store series after the automatic cover pass left a gap."
                )
            }

            Button {
                revealPathInFinder(item.currentPath, revealParent: true)
            } label: {
                Label("Reveal", systemImage: "folder")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isWorking)
            .help("Reveal this series cover folder in Finder.")
        }

        Text(item.reason)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        SableEagerAdaptiveGrid(
            minimumItemWidth: 150,
            horizontalSpacing: 6,
            verticalSpacing: 6
        ) {
            compactCoverEvidencePill(
                "Language",
                value: item.requestedCoverLanguages == ["jp"]
                    ? "Japanese"
                    : item.requestedCoverLanguages == ["en"] ? "English" : "Japanese + English",
                symbol: "character.book.closed"
            )
            compactCoverEvidencePill("Archive floor", value: "500 x 700", symbol: "rectangle.inset.filled")
            compactCoverEvidencePill("Clinic floor", value: "800 x 1100", symbol: "cross.case")
            compactCoverEvidencePill("Extras", value: "Special + alternative", symbol: "square.stack.3d.up")
        }

        if !item.manualCoverSeriesMatches.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Label("Exact series choices for the next search", systemImage: "checkmark.seal")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(palette.accent)
                ForEach(item.manualCoverSeriesMatches) { match in
                    HStack(spacing: 6) {
                        Text(match.source.displayName)
                            .fontWeight(.semibold)
                        Text(match.title)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 4)
                        Text(match.providerID)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))
                    .accessibilityElement(children: .combine)
                }
            }
        }

        Label(compactMetadataLocationText(for: item), systemImage: "folder")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    private func compactCoverEvidencePill(
        _ label: String,
        value: String,
        symbol: String
    ) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
            Text("\(label):")
                .foregroundStyle(.secondary)
            Text(value)
                .foregroundStyle(palette.textSecondary)
        }
        .font(.caption2.weight(.semibold))
        .lineLimit(1)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.55), in: Capsule())
        .help(value)
    }

    private func usesCompactRenameRow(_ item: LibraryPlanItem) -> Bool {
        switch item.operation {
        case .renameFile, .renameFolder, .cleanRawName:
            return true
        case .inspectOnly, .sortIntoFolder, .createComicInfo, .refreshComicInfo, .createAnimeInfo, .refreshAnimeInfo, .repairEpubPackage, .repairAppleBooksCompatibility, .duplicateDecision, .skip:
            return false
        }
    }

    private func compactRenameRowContent(for item: LibraryPlanItem) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(compactRenameTitle(for: item))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)

                if item.decision == .checked {
                    Label("Ready", systemImage: "checkmark.circle")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(palette.accent)
                } else if item.needsDecisionReview {
                    Label("Needs choice", systemImage: "questionmark.circle")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(palette.statusWarning)
                }

                Spacer(minLength: 0)

                pathActionsMenu(for: item)
                correctionMenu(for: item)
            }

            compactRenameDiff(for: item)

            Text(compactRenameReason(for: item))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if let evidence = compactShelfEvidenceLine(for: item) {
                Text(evidence)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func compactRenameTitle(for item: LibraryPlanItem) -> String {
        switch item.operation {
        case .renameFolder:
            if isSSSFolderSortingItem(item) {
                return compactPathDisplayName(item.currentPath)
            }
            return "Rename folder"
        case .renameFile, .cleanRawName:
            return "Rename file"
        case .inspectOnly, .sortIntoFolder, .createComicInfo, .refreshComicInfo, .createAnimeInfo, .refreshAnimeInfo, .repairEpubPackage, .repairAppleBooksCompatibility, .duplicateDecision, .skip:
            return operationTitle(for: item)
        }
    }

    private func compactRenameDiff(for item: LibraryPlanItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let proposedPath = item.proposedPath,
               let summary = pathChangeSummary(currentPath: item.currentPath, proposedPath: proposedPath) {
                pathChangeSummaryRow(summary, labelWidth: 104)
            } else {
                compactRenameLine("From", value: compactPathDisplayName(item.currentPath), symbol: "doc.text")
                if let proposedPath = item.proposedPath {
                    compactRenameLine("To", value: compactPathDisplayName(proposedPath), symbol: "arrow.turn.down.right")
                }
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
    }

    private func compactRenameLine(_ label: String, value: String, symbol: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Label(label, systemImage: symbol)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .leading)
                .labelStyle(.titleAndIcon)

            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }

    private func compactPathDisplayName(_ path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    private func parentPathDisplay(in path: String) -> String {
        let components = relativePathComponents(in: path)
        guard components.count > 1 else { return "" }
        return components.dropLast().joined(separator: " / ")
    }

    private func relativePathComponents(in path: String) -> [String] {
        path
            .split(separator: "/")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func isSSSFolderSortingItem(_ item: LibraryPlanItem) -> Bool {
        item.stage == .canonicalFolders
            && item.operation == .renameFolder
            && item.reviewTags.contains { tag in
                tag == "sss-shelf-review" || tag.hasPrefix("sss-folder-depth-")
            }
    }

    private func targetSSSFolderTitle(for item: LibraryPlanItem) -> String? {
        let path = item.proposedPath ?? item.currentPath
        return relativePathComponents(in: path).dropLast().reversed().first { component in
            isSSSFolderComponent(component)
        }
    }

    private func isSSSFolderComponent(_ component: String) -> Bool {
        guard let separator = component.range(of: " - ") else { return false }
        let code = component[..<separator.lowerBound]
        guard code.first?.isNumber == true else { return false }
        return code.allSatisfy { $0.isNumber || $0 == "." }
    }

    private func compactShelfEvidenceLine(for item: LibraryPlanItem) -> String? {
        guard isSSSFolderSortingItem(item) else { return nil }
        let explanation = item.confidenceExplanation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !explanation.isEmpty else { return nil }
        if let range = explanation.range(of: "SSS folder depth") {
            return "Why: \(String(explanation[range.lowerBound...]))"
        }
        return "Why: \(explanation)"
    }

    private func compactRenameReason(for item: LibraryPlanItem) -> String {
        if item.isManualApprovalFileOperation
            || item.reviewTags.contains("naming-title-change")
            || item.reviewTags.contains("naming-punctuation-only")
            || item.reviewTags.contains("naming-provider-token-change") {
            return item.reason
        }
        if item.safety == .collision {
            return "Conflict: this destination stays out until you choose what to do."
        }
        if isSSSFolderSortingItem(item) {
            return item.reason
        }
        if item.operation == .renameFolder {
            return "Folder uses the trusted sidecar title and source ID."
        }
        return "File uses the trusted sidecar title while keeping volume or chapter clues."
    }

    private func usesCompactMetadataRow(_ item: LibraryPlanItem) -> Bool {
        guard item.stage.usesComicInfoApplyEngine else { return false }
        switch item.operation {
        case .createComicInfo, .refreshComicInfo, .createAnimeInfo, .refreshAnimeInfo:
            return true
        case .inspectOnly, .cleanRawName, .sortIntoFolder, .renameFolder, .renameFile, .repairEpubPackage, .repairAppleBooksCompatibility, .duplicateDecision, .skip:
            return false
        }
    }

    @ViewBuilder
    private func compactMetadataRowContent(for item: LibraryPlanItem) -> some View {
        let providerMatch = compactProviderMatch(for: item)

        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(compactMetadataTitle(for: item))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)

            compactMetadataBadge(for: item)

            Spacer(minLength: 0)

            compactMetadataActions(for: item)
            compactMetadataMoreMenu(for: item)
        }

        if let providerMatch {
            compactSuggestedProviderMatchCard(providerMatch, for: item)
        } else {
            Text(compactMetadataDecisionText(for: item))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }

        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if providerMatch == nil,
               let idText = compactMetadataIDText(for: item) {
                Label(idText, systemImage: "number.circle")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(palette.accent)
                    .lineLimit(1)
            }

            Label(compactMetadataLocationText(for: item), systemImage: "folder")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func compactMetadataTitle(for item: LibraryPlanItem) -> String {
        let title = searchTitle(for: item)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return title }
        return URL(fileURLWithPath: item.currentPath).lastPathComponent
    }

    private func compactMetadataDecisionText(for item: LibraryPlanItem) -> String {
        if item.reviewTags.contains("manual-provider-match"),
           let sourceID = item.manualSourceIDs.first {
            return "Manual \(sourceID.provider.displayName) ID \(sourceID.value) is ready to apply."
        }
        if isKnownMissingProviderItem(item),
           let provider = item.metadataProviders.first {
            return "\(provider.displayName) has a saved No ID choice for this title. Use Find Match if a record exists now."
        }
        if isMatchedProviderItem(item),
           let provider = item.metadataProviders.first {
            if let sourceID = item.manualSourceIDs.first(where: { $0.provider == provider }) {
                return "\(provider.displayName) ID \(sourceID.value) is already saved. Use Find Match only if it looks wrong."
            }
            return "\(provider.displayName) already has a saved ID. Use Find Match only if it looks wrong."
        }
        if item.reviewTags.contains("metadata-provider-no-match-review"),
           let provider = item.metadataProviders.first {
            return "No \(provider.displayName) result found. Mark No ID to save that choice, or use Find Match to override it."
        }
        if item.reviewTags.contains("metadata-provider-candidate-review"),
           let provider = item.metadataProviders.first {
            let candidate = compactProviderCandidateText(from: item.reason) ?? "a possible match"
            if item.decision == .checked {
                return "\(provider.displayName) found \(candidate). This 90%+ match is already checked; uncheck or Find Match if it looks wrong."
            }
            return "\(provider.displayName) found \(candidate). Check to accept this ID, or use Find Match to replace it."
        }
        if item.reviewTags.contains("metadata-provider-precheck"),
           let provider = item.metadataProviders.first {
            return "Runs one light \(provider.displayName) check. The next refresh becomes a possible-match or No ID question."
        }
        if item.reviewTags.contains("metadata-comicinfo-cleaner") {
            return "Tidies local provider notes. Keeps accepted IDs and V2 details; removes rejected search traces and stale review clutter."
        }
        if isManualProviderGapItem(item),
           let provider = item.metadataProviders.first {
            return "Missing \(provider.displayName) ID. Use Find Match, paste an exact ID, or save No ID."
        }
        if item.operation == .refreshComicInfo || item.operation == .refreshAnimeInfo {
            return "Refreshes saved IDs and confident provider details. Weak results keep the current sidecar."
        }
        return "Creates a sidecar from trusted local/provider evidence. Unclear results stay for review."
    }

    private func compactProviderMatch(for item: LibraryPlanItem) -> CompactSuggestedProviderMatch? {
        compactManualProviderMatch(for: item) ?? compactSuggestedProviderMatch(for: item)
    }

    private func compactManualProviderMatch(for item: LibraryPlanItem) -> CompactSuggestedProviderMatch? {
        guard let sourceID = explicitProviderID(for: item),
              item.reviewTags.contains("manual-provider-match")
                || (!item.reviewTags.contains("metadata-provider-candidate-review")
                    && (item.manualMangaBakaID != nil || item.manualRanobeDBID != nil)) else {
            return nil
        }

        return CompactSuggestedProviderMatch(
            provider: sourceID.provider,
            title: compactMetadataTitle(for: item),
            detail: "Exact ID",
            confidencePercent: nil,
            idText: "\(sourceID.provider.displayName) ID \(sourceID.value)",
            isAlreadyChecked: item.decision == .checked,
            isManual: true
        )
    }

    private func compactSuggestedProviderMatch(for item: LibraryPlanItem) -> CompactSuggestedProviderMatch? {
        guard item.reviewTags.contains("metadata-provider-candidate-review"),
              let provider = item.metadataProviders.first,
              let rawCandidate = compactProviderCandidateText(from: item.reason) else {
            return nil
        }

        let parsedCandidate = splitCompactProviderCandidate(rawCandidate)
        return CompactSuggestedProviderMatch(
            provider: provider,
            title: parsedCandidate.title,
            detail: parsedCandidate.detail,
            confidencePercent: compactProviderCandidatePercent(from: item.reason),
            idText: compactMetadataIDText(for: item),
            isAlreadyChecked: item.decision == .checked,
            isManual: false
        )
    }

    private func splitCompactProviderCandidate(_ rawCandidate: String) -> (title: String, detail: String?) {
        let trimmed = rawCandidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let detailStart = trimmed.range(of: " (", options: .backwards),
              trimmed.hasSuffix(")") else {
            return (trimmed, nil)
        }

        let title = String(trimmed[..<detailStart.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = String(trimmed[detailStart.upperBound..<trimmed.index(before: trimmed.endIndex)])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !detail.isEmpty else {
            return (trimmed, nil)
        }
        return (title, detail)
    }

    private func compactProviderCandidatePercent(from reason: String) -> Int? {
        guard let range = reason.range(of: #" - [0-9]+%"#, options: .regularExpression) else {
            return nil
        }
        let digits = reason[range]
            .filter(\.isNumber)
        return Int(String(digits))
    }

    private func compactSuggestedProviderMatchCard(
        _ match: CompactSuggestedProviderMatch,
        for item: LibraryPlanItem
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            compactSuggestedProviderArtwork(for: match.provider, confirmed: match.isAlreadyChecked)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(match.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if let detail = match.detail {
                        Text(detail)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Text(compactSuggestedProviderActionText(match, for: item))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                compactSuggestedProviderEvidenceGrid(match, for: item)
            }

            Spacer(minLength: 8)

            if match.isAlreadyChecked {
                VStack(alignment: .trailing, spacing: 6) {
                    Label("Ready to Save", systemImage: "checkmark.circle.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(palette.accent)
                        .lineLimit(1)

                    if match.isManual, item.isApplyableOperation {
                        Button {
                            requestApply(
                                item.stage,
                                itemIDs: [item.id],
                                scopeTitle: compactMetadataTitle(for: item),
                                mode: .singleProviderMatch
                            )
                        } label: {
                            Label("Save This Match", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(isWorking)
                        .help("Review and save only this provider match now. Other checked rows stay pending.")
                    }
                }
            } else {
                Button {
                    onDecisionChange(item.id, .checked)
                } label: {
                    Label("Confirm", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isWorking || !canCheck(item))
                .accessibilityHint("Accepts this suggested provider ID for the next apply.")
                .help("Accept this suggested provider match.")
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(match.isAlreadyChecked ? palette.accent.opacity(0.12) : palette.surfaceRaised.opacity(0.82))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(match.isAlreadyChecked ? palette.accent.opacity(0.28) : palette.border, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(compactSuggestedProviderAccessibilityLabel(match))
    }

    private func compactSuggestedProviderActionText(
        _ match: CompactSuggestedProviderMatch,
        for item: LibraryPlanItem
    ) -> String {
        if match.isAlreadyChecked {
            return match.isManual
                ? "This exact provider ID is ready. Save this row now, or keep matching and run the checked batch later."
                : "This provider ID is checked for the next apply."
        }
        if match.isManual {
            return "Confirm to save this exact provider ID on the next apply."
        }
        if item.reviewTags.contains("metadata-provider-confident-candidate") {
            return "Confirm if the provider record matches this series."
        }
        return "Check this row only if this provider record is the right one."
    }

    private func compactSuggestedProviderEvidenceGrid(
        _ match: CompactSuggestedProviderMatch,
        for item: LibraryPlanItem
    ) -> some View {
        let evidence = compactSuggestedProviderEvidence(match, for: item)
        return SableEagerAdaptiveGrid(
            minimumItemWidth: 150,
            horizontalSpacing: 6,
            verticalSpacing: 6
        ) {
            ForEach(Array(evidence.enumerated()), id: \.offset) { _, row in
                compactSuggestedProviderEvidencePill(row.label, value: row.value, symbol: row.symbol)
            }
        }
    }

    private func compactSuggestedProviderEvidence(
        _ match: CompactSuggestedProviderMatch,
        for item: LibraryPlanItem
    ) -> [(label: String, value: String, symbol: String)] {
        var rows: [(label: String, value: String, symbol: String)] = [
            ("Source", match.provider.displayName, "globe")
        ]

        if match.isManual {
            rows.append(("Choice", "Exact ID", "checkmark.seal"))
        } else if let confidencePercent = match.confidencePercent {
            rows.append(("Match", "\(confidencePercent)% sure", "percent"))
        }
        if let idText = match.idText {
            rows.append(("Will save", idText, "number.circle"))
        }
        rows.append(("Local folder", compactMetadataLocationText(for: item), "folder"))
        return rows
    }

    private func compactSuggestedProviderEvidencePill(
        _ label: String,
        value: String,
        symbol: String
    ) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
            Text("\(label):")
                .foregroundStyle(.secondary)
            Text(value)
                .foregroundStyle(label == "Will save" ? palette.accent : palette.textSecondary)
                .truncationMode(.middle)
        }
        .font(.caption2.weight(.semibold))
        .lineLimit(1)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.55), in: Capsule())
        .help(value)
    }

    private func compactSuggestedProviderArtwork(
        for provider: SableLibraryMetadataProvider,
        confirmed: Bool
    ) -> some View {
        Image(systemName: compactSuggestedProviderSymbol(for: provider, confirmed: confirmed))
            .font(.headline.weight(.semibold))
            .foregroundStyle(confirmed ? palette.accent : palette.textSecondary)
            .frame(width: 34, height: 44)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill((confirmed ? palette.accent : palette.textSecondary).opacity(0.12))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke((confirmed ? palette.accent : palette.textSecondary).opacity(0.22), lineWidth: 1)
            }
            .accessibilityHidden(true)
    }

    private func compactSuggestedProviderSymbol(
        for provider: SableLibraryMetadataProvider,
        confirmed: Bool
    ) -> String {
        if confirmed { return "checkmark.seal" }
        switch provider {
        case .openLibrary, .ranobedb:
            return "book.closed"
        case .mangabaka:
            return "books.vertical"
        case .anilist, .myAnimeList:
            return "sparkles"
        case .tmdb, .tvdb, .imdb, .tvmaze:
            return "play.rectangle"
        case .wikidata:
            return "network"
        case .local:
            return "text.badge.checkmark"
        }
    }

    private func compactSuggestedProviderAccessibilityLabel(_ match: CompactSuggestedProviderMatch) -> String {
        var parts = ["Suggested \(match.provider.displayName) match: \(match.title)"]
        if let detail = match.detail {
            parts.append(detail)
        }
        if match.isManual {
            parts.append("Exact ID chosen manually")
        }
        if let confidencePercent = match.confidencePercent {
            parts.append("\(confidencePercent) percent sure")
        }
        if let idText = match.idText {
            parts.append(idText)
        }
        parts.append(match.isAlreadyChecked ? "Confirmed" : "Not confirmed")
        return parts.joined(separator: ", ")
    }

    private func compactProviderCandidateText(from reason: String) -> String? {
        guard let marker = reason.range(of: " match: ") else { return nil }
        let afterMarker = reason[marker.upperBound...]
        if let end = afterMarker.range(of: ". Check this row") {
            return String(afterMarker[..<end.lowerBound])
        }
        if let end = afterMarker.range(of: ". This is checked") {
            return String(afterMarker[..<end.lowerBound])
        }
        return String(afterMarker).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func compactMetadataBadge(for item: LibraryPlanItem) -> some View {
        let badge: (text: String, symbol: String) = {
            if isMatchedProviderItem(item) {
                return ("Saved ID", "checkmark.seal")
            }
            if item.reviewTags.contains("manual-provider-match") || !item.manualSourceIDs.isEmpty {
                return ("Manual ID", "checkmark.seal")
            }
            if item.reviewTags.contains("metadata-provider-no-match-review") {
                return ("No match", "minus.circle")
            }
            if isKnownMissingProviderItem(item) {
                return ("Saved No ID", "checkmark.seal")
            }
            if item.reviewTags.contains("metadata-provider-candidate-review") {
                return ("Possible match", "questionmark.circle")
            }
            if item.reviewTags.contains("metadata-provider-precheck") {
                return ("Precheck", "bolt")
            }
            if item.decision == .checked {
                return ("Ready", "checkmark.circle")
            }
            if item.requiresReview {
                return ("Review", "questionmark.circle")
            }
            return (item.confidence.rawValue.capitalized, "checkmark.seal")
        }()

        return Label(badge.text, systemImage: badge.symbol)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.quaternary, in: Capsule())
            .lineLimit(1)
    }

    @ViewBuilder
    private func compactMetadataActions(for item: LibraryPlanItem) -> some View {
        if let request = providerSearchRequest(for: item) {
            Button {
                pendingProviderSearch = request
            } label: {
                Label("Find Match", systemImage: "text.magnifyingglass")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isWorking)
            .accessibilityLabel("Find provider match")
            .accessibilityHint("Opens focused metadata search for this row.")
            .help("Open the focused metadata search sheet.")

            if isManualProviderGapItem(item), !isKnownMissingProviderItem(item) {
                Button {
                    onCorrection(item.id, .providerNotAvailable)
                } label: {
                    Label("No ID", systemImage: "minus.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isWorking)
                .accessibilityLabel("Save No ID for this provider")
                .accessibilityHint("Saves a No ID choice for this title so Sable stops asking unless you use Find Match later.")
                .help("Save No ID for this provider and title.")
            }
        } else if canUseLocalTitle(for: item) {
            Button {
                onCorrection(item.id, .keepTitle)
            } label: {
                Label("Use Local", systemImage: "text.badge.checkmark")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isWorking)
            .accessibilityLabel("Use local title")
            .accessibilityHint("Accepts the local folder title without a provider ID.")
        }
    }

    @ViewBuilder
    private func compactMetadataMoreMenu(for item: LibraryPlanItem) -> some View {
        Menu {
            pathActionItems(for: item)
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
        .menuStyle(.button)
        .controlSize(.small)
        .disabled(isWorking)
        .accessibilityLabel("More metadata actions")
        .accessibilityHint("Shows path actions and suggested metadata details for this row.")
        .help("Open, reveal, or copy paths and suggested metadata details.")
    }

    private func compactMetadataIDText(for item: LibraryPlanItem) -> String? {
        if let sourceID = explicitProviderID(for: item) {
            return "\(sourceID.provider.displayName) ID \(sourceID.value)"
        }
        return nil
    }

    private func explicitProviderID(for item: LibraryPlanItem) -> SableLibrarySourceID? {
        if let sourceID = item.manualSourceIDs.first(where: {
            $0.provider != .local && !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) {
            return sourceID
        }
        if let manualMangaBakaID = item.manualMangaBakaID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !manualMangaBakaID.isEmpty {
            return SableLibrarySourceID(provider: .mangabaka, value: manualMangaBakaID)
        }
        if let manualRanobeDBID = item.manualRanobeDBID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !manualRanobeDBID.isEmpty {
            return SableLibrarySourceID(provider: .ranobedb, value: manualRanobeDBID)
        }
        return nil
    }

    private func compactMetadataLocationText(for item: LibraryPlanItem) -> String {
        let path = item.currentPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return path.isEmpty ? "Library root" : path
    }

    private func displayReason(for item: LibraryPlanItem) -> String {
        if isPDFDocumentTriageItem(item) {
            return item.reason
        }
        if item.isNameCollisionResolution {
            return item.decision == .checked
                ? "Move the existing destination into \(SableLibraryConfig.fallback.duplicateFolderName), then apply this name."
                : "Move Aside is selected for this conflict. Check the row when you want it included in Apply."
        }
        if item.isFolderMergeResolution {
            return item.decision == .checked
                ? "Move this folder's contents into the existing destination folder."
                : "Merge Into Existing is selected for this conflict. Check the row when you want it included in Apply."
        }
        if item.isDuplicateMoveAside {
            return item.decision == .checked
                ? "Move this extra copy into \(SableLibraryConfig.fallback.duplicateFolderName)."
                : "Move Aside is selected for this duplicate. Check the row when you want it included in Apply."
        }

        guard item.operation == .sortIntoFolder, item.safety != .collision else {
            return item.reason
        }

        if item.requiresReview {
            return "Review the final destination; the raw name has unclear folder or volume clues."
        }

        return "Moves the loose book into the detected series folder and uses the cleaned filename."
    }

    private func displayConfidenceExplanation(for item: LibraryPlanItem) -> String? {
        if isPDFDocumentTriageItem(item) {
            return item.confidenceExplanation
        }
        guard item.operation == .sortIntoFolder, item.safety != .collision else {
            return item.confidenceExplanation
        }

        return "This row shows the final path after folder placement and filename cleanup."
    }

    @ViewBuilder
    private func mangaBakaMatchReview(for item: LibraryPlanItem) -> some View {
        if let request = providerSearchRequest(for: item) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label("Metadata matching", systemImage: "checkmark.seal")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                Button {
                    pendingProviderSearch = request
                } label: {
                    Label("Find Match", systemImage: "text.magnifyingglass")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(isWorking)
                .help("Open one focused metadata sheet for provider search, URL or ID paste, and local-title choices.")
            }
        }
    }

    private func canUseManualProviderSearch(for item: LibraryPlanItem) -> Bool {
        guard item.stage != .covers else { return false }
        switch item.operation {
        case .createComicInfo, .refreshComicInfo, .createAnimeInfo, .refreshAnimeInfo:
            return item.stage.isMetadataSidecarStage
                && (
                    item.usedNetworkData
                        || item.requiresReview
                        || !item.metadataProviders.isEmpty
                        || item.reviewTags.contains("needs-provider-choice")
                        || item.reviewTags.contains("provider-route-needs-choice")
                )
        case .inspectOnly, .cleanRawName, .sortIntoFolder, .renameFolder, .renameFile, .repairEpubPackage, .repairAppleBooksCompatibility, .duplicateDecision, .skip:
            return false
        }
    }

    private func providerSearchRequest(for item: LibraryPlanItem) -> SableLibraryProviderSearchRequest? {
        guard canUseManualProviderSearch(for: item) else { return nil }
        let providers = manualSearchProviders(for: item)
        guard !providers.isEmpty else { return nil }
        return SableLibraryProviderSearchRequest(
            item: item,
            query: searchTitle(for: item),
            providers: providers
        )
    }

    private func coverSearchRequest(for item: LibraryPlanItem) -> SableLibraryCoverSearchRequest? {
        guard item.canManuallyMatchCoverSeries else { return nil }
        return SableLibraryCoverSearchRequest(
            item: item,
            query: searchTitle(for: item)
        )
    }

    private func manualSearchProviders(for item: LibraryPlanItem) -> [SableLibraryMetadataProvider] {
        switch item.operation {
        case .createComicInfo, .refreshComicInfo:
            let readingOrder: [SableLibraryMetadataProvider] = [.ranobedb, .mangabaka, .anilist, .openLibrary]
            let providers = item.metadataProviders.isEmpty
                ? readingOrder
                : item.metadataProviders + readingOrder
            return uniqueManualSearchProviders(providers.filter {
                $0 != .local && $0 != .myAnimeList
            })
        case .createAnimeInfo, .refreshAnimeInfo:
            let watchingOrder: [SableLibraryMetadataProvider] = [.tmdb, .tvdb, .imdb, .tvmaze, .anilist]
            let providers = item.metadataProviders.isEmpty
                ? watchingOrder
                : item.metadataProviders + watchingOrder
            return uniqueManualSearchProviders(providers.filter {
                $0 != .local && $0 != .myAnimeList
            })
        case .inspectOnly, .cleanRawName, .sortIntoFolder, .renameFolder, .renameFile, .repairEpubPackage, .repairAppleBooksCompatibility, .duplicateDecision, .skip:
            return []
        }
    }

    private func uniqueManualSearchProviders(_ providers: [SableLibraryMetadataProvider]) -> [SableLibraryMetadataProvider] {
        var seen = Set<SableLibraryMetadataProvider>()
        return providers.filter { provider in
            seen.insert(provider).inserted
        }
    }

    private func canUseManualRanobeDBID(for item: LibraryPlanItem) -> Bool {
        item.stage.isMetadataSidecarStage
            && (item.operation == .createComicInfo || item.operation == .refreshComicInfo)
            && canUseManualProviderSearch(for: item)
    }

    private func ranobeDBSearchURL(for item: LibraryPlanItem) -> URL? {
        guard canUseManualRanobeDBID(for: item) else { return nil }

        let title = searchTitle(for: item)

        var components = URLComponents(string: "https://ranobedb.org/search")
        components?.queryItems = title.isEmpty ? nil : [URLQueryItem(name: "q", value: title)]
        return components?.url
    }

    private func pathSourceLabel(for item: LibraryPlanItem) -> String {
        if isPDFDocumentTriageItem(item) {
            return item.operation == .renameFolder ? "PDF folder" : "PDF file"
        }

        switch item.operation {
        case .sortIntoFolder:
            return "Loose file"
        case .renameFolder:
            return "Current folder"
        case .createComicInfo, .refreshComicInfo, .createAnimeInfo, .refreshAnimeInfo:
            return "Series folder"
        case .repairEpubPackage:
            return "EPUB package"
        case .repairAppleBooksCompatibility:
            return "EPUB file"
        case .duplicateDecision:
            return "Extra copy"
        case .cleanRawName, .renameFile:
            return "Current file"
        case .inspectOnly, .skip:
            return "Source"
        }
    }

    private func pathDestinationLabel(for item: LibraryPlanItem) -> String {
        if isPDFDocumentTriageItem(item) {
            return "Document path"
        }
        if isManualDiagnosticItem(item) {
            return "Repair note"
        }

        switch item.operation {
        case .sortIntoFolder:
            return "Final path"
        case .renameFolder:
            return "New folder"
        case .createComicInfo, .refreshComicInfo:
            return "ComicInfo"
        case .createAnimeInfo, .refreshAnimeInfo:
            return "AnimeInfo"
        case .cleanRawName, .renameFile:
            return "New file"
        case .repairEpubPackage:
            return "Repaired EPUB"
        case .repairAppleBooksCompatibility:
            return "Fixed EPUB"
        case .duplicateDecision:
            return "Duplicate folder"
        case .inspectOnly, .skip:
            return "Destination"
        }
    }

    private func pathActionsHelpText(for item: LibraryPlanItem) -> String {
        if isManualDiagnosticItem(item) {
            return "Reveal or copy the EPUB path and repair evidence. Sable shows a checkbox only when a safe repair path exists."
        }
        if mangaBakaSearchURL(for: item) != nil {
            return "Open source or destination locations, copy names or paths, copy the suggested change, or search MangaBaka for this title."
        }
        return "Open source or destination locations, copy names or paths, or copy the suggested change."
    }

    private func sourceActionName(for item: LibraryPlanItem) -> String {
        switch item.operation {
        case .sortIntoFolder:
            return "Loose File"
        case .renameFolder:
            return "Current Folder"
        case .createComicInfo, .refreshComicInfo, .createAnimeInfo, .refreshAnimeInfo:
            return "Series Folder"
        case .repairEpubPackage:
            return "EPUB Package"
        case .repairAppleBooksCompatibility:
            return "EPUB File"
        case .duplicateDecision:
            return "Extra Copy"
        case .cleanRawName, .renameFile:
            return "Current File"
        case .inspectOnly, .skip:
            return "Source"
        }
    }

    private func destinationActionName(for item: LibraryPlanItem) -> String {
        if isManualDiagnosticItem(item) {
            return "Repair note"
        }
        switch item.operation {
        case .sortIntoFolder:
            return "Final File"
        case .renameFolder:
            return "New Folder"
        case .createComicInfo, .refreshComicInfo:
            return "ComicInfo"
        case .createAnimeInfo, .refreshAnimeInfo:
            return "AnimeInfo"
        case .cleanRawName, .renameFile:
            return "New File"
        case .repairEpubPackage:
            return "Repaired EPUB"
        case .repairAppleBooksCompatibility:
            return "Fixed EPUB"
        case .duplicateDecision:
            return "Duplicate Folder"
        case .inspectOnly, .skip:
            return "Destination"
        }
    }

    private func pathName(_ path: String) -> String {
        let name = URL(fileURLWithPath: path).lastPathComponent
        return name.isEmpty ? path : name
    }

    private func suggestedChangeText(for item: LibraryPlanItem) -> String {
        if isManualDiagnosticItem(item) {
            return "\(reviewRowTitle(for: item)): \(item.currentPath). \(item.reason)"
        }
        if let proposedPath = item.proposedPath,
           proposedPath != item.currentPath {
            return "\(operationTitle(for: item)): \(item.currentPath) -> \(proposedPath)"
        }
        return "\(operationTitle(for: item)): \(item.currentPath)"
    }

    @ViewBuilder
    private func pathActionsMenu(for item: LibraryPlanItem) -> some View {
        Menu {
            pathActionItems(for: item)
        } label: {
            Label(pathActionsMenuTitle(for: item), systemImage: "ellipsis.circle")
        }
        .menuStyle(.button)
        .controlSize(.small)
        .disabled(isWorking)
        .accessibilityLabel("Path actions")
        .accessibilityHint(pathActionsHelpText(for: item))
        .help(pathActionsHelpText(for: item))
    }

    private func pathActionsMenuTitle(for item: LibraryPlanItem) -> String {
        if item.isReviewGatedEPUBRepairOperation {
            return "Repair / Copy"
        }
        if isManualDiagnosticItem(item) {
            return "Evidence / Copy"
        }
        return "Open / Copy"
    }

    @ViewBuilder
    private func pathActionItems(for item: LibraryPlanItem) -> some View {
        let sourceName = sourceActionName(for: item)
        if item.isReviewGatedEPUBRepairOperation {
            Button(item.decision == .checked ? "Uncheck Repair" : "Check Repair") {
                onDecisionChange(item.id, item.decision == .checked ? .unchecked : .checked)
            }
            Button("Copy Repair Summary") {
                copyText(suggestedChangeText(for: item))
            }
            Divider()
        }

        Button("Reveal \(sourceName) in Finder") {
            revealPathInFinder(item.currentPath)
        }
        Button("Reveal \(sourceName) Folder") {
            revealPathInFinder(item.currentPath, revealParent: true)
        }
        Button("Copy \(sourceName) Path") {
            copyPath(item.currentPath)
        }
        Button("Copy \(sourceName) Name") {
            copyText(pathName(item.currentPath))
        }

        if let proposedPath = item.proposedPath {
            Divider()
            if proposedPath != item.currentPath {
                let destinationName = destinationActionName(for: item)
                Button("Reveal \(destinationName) Folder") {
                    revealPathInFinder(proposedPath, revealParent: true)
                }
                Button("Copy \(destinationName) Path") {
                    copyPath(proposedPath)
                }
                Button("Copy \(destinationName) Name") {
                    copyText(pathName(proposedPath))
                }
            }
            Button("Copy Suggested Change") {
                copyText(suggestedChangeText(for: item))
            }
        }

        if canUseCollisionResolution(for: item) {
            Divider()
            moveExistingAsideAction(for: item)
        }
        if canUsePDFDocumentChoice(item) {
            Divider()
            treatAsDocumentAction(for: item)
            keepAsBookAction(for: item)
        }
        if canUseRawReadingLaneChoice(item) {
            Divider()
            rawReadingLaneMenuActions(for: item)
        }
        if canUseCleanupKindChoice(item) {
            Divider()
            cleanupKindMenuActions(for: item)
        }
        if canUseFolderMerge(for: item) {
            mergeIntoExistingAction(for: item)
        }
        if canUseDuplicateMoveAside(for: item) {
            Divider()
            moveExistingAsideAction(for: item)
            Button("Mark Not a Duplicate") {
                onCorrection(item.id, .notADuplicate)
            }
        }

        if let request = providerSearchRequest(for: item) {
            Divider()
            Button("Find Provider Match...") {
                pendingProviderSearch = request
            }
        }

    }

    @ViewBuilder
    private func correctionMenu(for item: LibraryPlanItem) -> some View {
        if canUseCollisionResolution(for: item) {
            Button {
                onCorrection(item.id, .moveExistingAside)
            } label: {
                Label("Move Aside", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isWorking)
            .help("Move the existing destination into the duplicate folder before applying this rename.")
        }
        if canUseFolderMerge(for: item) {
            Button {
                onCorrection(item.id, .mergeIntoExisting)
            } label: {
                Label("Merge Into Existing", systemImage: "arrow.down.doc")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isWorking)
            .help("Move this folder's contents into the existing destination folder. Item name conflicts get unique names.")
        }
        if canUseDuplicateMoveAside(for: item) {
            Button {
                onCorrection(item.id, .moveExistingAside)
            } label: {
                Label("Move Aside", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isWorking)
            .help("Move this extra copy into the duplicate folder. Suggested keepers stay where they are.")
            Button {
                onCorrection(item.id, .notADuplicate)
            } label: {
                Label("Keep Both", systemImage: "checkmark.seal")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isWorking)
            .help("Mark this duplicate candidate as not a duplicate for this pass.")
        }
        if canUsePDFDocumentChoice(item) {
            Button {
                onCorrection(item.id, .treatAsDocument)
            } label: {
                Label("Treat as Document", systemImage: "doc.text")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isWorking)
            .help("Move this PDF into Documents. Leave it unchecked if it is a book or comic PDF.")
        }
        if canUsePDFBookChoice(item) {
            Button {
                onCorrection(item.id, .treatAsBook)
            } label: {
                Label("Keep as Book", systemImage: "book")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isWorking)
            .help("Leave this PDF out of document cleanup and remember the clue as book-like.")
        }
        if canUseRawReadingLaneChoice(item) {
            Menu {
                rawReadingLaneMenuActions(for: item)
            } label: {
                Label("Teach Type", systemImage: "brain")
            }
            .menuStyle(.button)
            .controlSize(.small)
            .disabled(isWorking)
            .help("Choose the reading lane this row should teach Sable to remember.")
        }
        if canUseCleanupKindChoice(item) {
            Menu {
                cleanupKindMenuActions(for: item)
            } label: {
                Label("Teach Folder", systemImage: "folder.badge.gearshape")
            }
            .menuStyle(.button)
            .controlSize(.small)
            .disabled(isWorking)
            .help("Choose the broad folder this row should teach Sable to remember.")
        }
        if let request = providerSearchRequest(for: item) {
            Button {
                pendingProviderSearch = request
            } label: {
                Label("Find Match", systemImage: "text.magnifyingglass")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isWorking)
            .help("Open one focused metadata sheet for provider search, URL or ID paste, and local-title choices.")
            if isManualProviderGapItem(item), !isKnownMissingProviderItem(item) {
                Button {
                    onCorrection(item.id, .providerNotAvailable)
                } label: {
                    Label("No ID", systemImage: "minus.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isWorking)
                .help("Save No ID for this provider and title.")
            }
        } else if canUseLocalTitle(for: item) {
            Button {
                onCorrection(item.id, .keepTitle)
            } label: {
                Label("Use Local", systemImage: "text.badge.checkmark")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isWorking)
            .help("Create ComicInfo from the local folder title and do not call MangaBaka for this row.")
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private func pathChange(for item: LibraryPlanItem) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if isManualDiagnosticItem(item) {
                pathLine(pathSourceLabel(for: item), path: item.currentPath, symbol: "doc.text")
                Label("Use a clean source, or add a real repair rule so this becomes a checked repair row.", systemImage: "checkmark.shield")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if let proposedPath = item.proposedPath,
               let summary = pathChangeSummary(currentPath: item.currentPath, proposedPath: proposedPath) {
                pathChangeSummaryRow(summary)
            } else {
                pathLine(pathSourceLabel(for: item), path: item.currentPath, symbol: "doc.text")
                if let proposedPath = item.proposedPath {
                    pathLine(pathDestinationLabel(for: item), path: proposedPath, symbol: "arrow.turn.down.right")
                }
            }

            if let manualMangaBakaID = item.manualMangaBakaID {
                Label("MangaBaka ID \(manualMangaBakaID)", systemImage: "number.circle")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(palette.accent)
            }

            if let manualRanobeDBID = item.manualRanobeDBID {
                Label("RanobeDB series ID \(manualRanobeDBID)", systemImage: "number.circle")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(palette.accent)
            }

            if item.isNameCollisionResolution {
                Label(
                    item.decision == .checked
                        ? "Will move the existing destination into \(SableLibraryConfig.fallback.duplicateFolderName), then use this final path."
                        : "Move Aside is ready. Check this row to include it in Apply.",
                    systemImage: "arrow.triangle.2.circlepath"
                )
                    .font(.caption2)
                    .foregroundStyle(palette.statusWarning)
            } else if item.isFolderMergeResolution {
                Label(
                    item.decision == .checked
                        ? "Will move this folder's contents into the existing destination folder."
                        : "Merge Into Existing is ready. Check this row to include it in Apply.",
                    systemImage: "arrow.down.doc"
                )
                    .font(.caption2)
                    .foregroundStyle(palette.statusWarning)
            } else if item.isDuplicateMoveAside {
                Label(
                    item.decision == .checked
                        ? "Will move this extra copy into \(SableLibraryConfig.fallback.duplicateFolderName)."
                        : "Move Aside is ready. Check this row to include it in Apply.",
                    systemImage: "arrow.triangle.2.circlepath"
                )
                    .font(.caption2)
                    .foregroundStyle(palette.statusWarning)
            } else if item.safety == .collision {
                Label("Conflict: destination is excluded until reviewed.", systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundStyle(palette.statusWarning)
            } else if item.safety == .network {
                Label("Network-only row: excluded until it has a specific review flow.", systemImage: "globe")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func pathChangeSummary(
        currentPath: String,
        proposedPath: String
    ) -> SableLibraryPathChangeSummary? {
        guard currentPath != proposedPath else { return nil }

        let currentTitle = folderTitleDisplayName(in: currentPath)
        let proposedTitle = folderTitleDisplayName(in: proposedPath)
        let currentTitleKey = folderTitleSummaryKey(currentTitle)
        let proposedTitleKey = folderTitleSummaryKey(proposedTitle)

        if !currentTitleKey.isEmpty,
           !proposedTitleKey.isEmpty,
           currentTitleKey != proposedTitleKey {
            let highlights = pathChangeHighlights(from: currentTitle, to: proposedTitle)
            return SableLibraryPathChangeSummary(
                currentValue: currentTitle,
                proposedValue: proposedTitle,
                currentHighlight: highlights.current,
                proposedHighlight: highlights.proposed,
                symbol: "textformat",
                isReviewSensitive: true
            )
        }

        if !currentTitle.isEmpty,
           !proposedTitle.isEmpty,
           currentTitle != proposedTitle,
           currentTitleKey == proposedTitleKey {
            let highlights = pathChangeHighlights(from: currentTitle, to: proposedTitle)
            return SableLibraryPathChangeSummary(
                currentValue: currentTitle,
                proposedValue: proposedTitle,
                currentHighlight: highlights.current,
                proposedHighlight: highlights.proposed,
                symbol: "textformat.abc",
                isReviewSensitive: false
            )
        }

        let currentTokens = providerTokenLabels(in: currentPath)
        let proposedTokens = providerTokenLabels(in: proposedPath)
        if currentTokens != proposedTokens {
            let currentValue = providerTokenText(currentTokens)
            let proposedValue = providerTokenText(proposedTokens)
            let highlights = pathChangeHighlights(from: currentValue, to: proposedValue)
            return SableLibraryPathChangeSummary(
                currentValue: currentValue,
                proposedValue: proposedValue,
                currentHighlight: highlights.current,
                proposedHighlight: highlights.proposed,
                symbol: "number.circle",
                isReviewSensitive: true
            )
        }

        let currentParent = parentPathDisplay(in: currentPath)
        let proposedParent = parentPathDisplay(in: proposedPath)
        if !currentParent.isEmpty,
           !proposedParent.isEmpty,
           currentParent != proposedParent {
            return SableLibraryPathChangeSummary(
                currentValue: currentParent,
                proposedValue: proposedParent,
                currentHighlight: currentParent,
                proposedHighlight: proposedParent,
                symbol: "folder.badge.plus",
                isReviewSensitive: false
            )
        }

        let currentRoot = firstPathComponent(in: currentPath)
        let proposedRoot = firstPathComponent(in: proposedPath)
        if let currentRoot, let proposedRoot, currentRoot != proposedRoot {
            return SableLibraryPathChangeSummary(
                currentValue: currentRoot,
                proposedValue: proposedRoot,
                currentHighlight: currentRoot,
                proposedHighlight: proposedRoot,
                symbol: "folder",
                isReviewSensitive: false
            )
        }

        let currentName = (currentPath as NSString).lastPathComponent
        let proposedName = (proposedPath as NSString).lastPathComponent
        if currentName != proposedName {
            let highlights = pathChangeHighlights(from: currentName, to: proposedName)
            return SableLibraryPathChangeSummary(
                currentValue: currentName,
                proposedValue: proposedName,
                currentHighlight: highlights.current,
                proposedHighlight: highlights.proposed,
                symbol: "textformat",
                isReviewSensitive: false
            )
        }

        return nil
    }

    private func pathChangeSummaryRow(
        _ summary: SableLibraryPathChangeSummary,
        labelWidth: CGFloat = 104
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Label("What changed?", systemImage: summary.symbol)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(summary.isReviewSensitive ? palette.statusWarning : palette.textSecondary)
                .frame(width: labelWidth, alignment: .leading)
                .labelStyle(.titleAndIcon)

            pathChangeText(summary)
                .font(.caption2)
                .foregroundStyle(summary.isReviewSensitive ? palette.accent : palette.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary.accessibilityText)
    }

    private func pathChangeText(_ summary: SableLibraryPathChangeSummary) -> Text {
        Text("\(pathChangeValueText(summary.currentValue, highlight: summary.currentHighlight)) -> \(pathChangeValueText(summary.proposedValue, highlight: summary.proposedHighlight))")
    }

    private func pathChangeValueText(_ value: String, highlight: String?) -> Text {
        guard let highlight,
              !highlight.isEmpty,
              let range = value.range(
                of: highlight,
                options: [.caseInsensitive, .diacriticInsensitive]
              ) else {
            return Text(value)
        }

        let before = String(value[..<range.lowerBound])
        let match = String(value[range])
        let after = String(value[range.upperBound...])
        return Text("\(before)\(Text(match).bold().italic())\(after)")
    }

    private func pathChangeHighlights(from current: String, to proposed: String) -> (current: String?, proposed: String?) {
        let currentCharacters = Array(current)
        let proposedCharacters = Array(proposed)
        let sharedCount = min(currentCharacters.count, proposedCharacters.count)
        var prefixCount = 0

        while prefixCount < sharedCount,
              currentCharacters[prefixCount] == proposedCharacters[prefixCount] {
            prefixCount += 1
        }

        var currentEnd = currentCharacters.count
        var proposedEnd = proposedCharacters.count
        while currentEnd > prefixCount,
              proposedEnd > prefixCount,
              currentCharacters[currentEnd - 1] == proposedCharacters[proposedEnd - 1] {
            currentEnd -= 1
            proposedEnd -= 1
        }

        let currentDifference = prefixCount < currentEnd
            ? String(currentCharacters[prefixCount..<currentEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        let proposedDifference = prefixCount < proposedEnd
            ? String(proposedCharacters[prefixCount..<proposedEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
            : ""

        return (
            currentDifference.isEmpty ? nil : currentDifference,
            proposedDifference.isEmpty ? nil : proposedDifference
        )
    }

    private func folderTitleDisplayName(in path: String) -> String {
        let name = (path as NSString).lastPathComponent
        let withoutTokens = name.replacingOccurrences(
            of: #"(?i)\s*\{(?:mb|mangabaka|rdb|ranobedb|ol|openlibrary|open_library|mal|myanimelist|my_anime_list|anilist|al|tvmaze|wikidata|wd|tmdb|tvdb|imdb|local)-[^}]+\}\s*"#,
            with: " ",
            options: .regularExpression
        )
        let withoutYear = withoutTokens.replacingOccurrences(
            of: #"\s*[\(\[]\d{4}[\)\]]\s*$"#,
            with: "",
            options: .regularExpression
        )
        return withoutYear
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "-:")))
    }

    private func folderTitleSummaryKey(_ title: String) -> String {
        title
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "[‘’`´]", with: "'", options: .regularExpression)
            .replacingOccurrences(of: "[“”]", with: "\"", options: .regularExpression)
            .replacingOccurrences(of: "[–—−]", with: "-", options: .regularExpression)
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func providerTokenLabels(in path: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?i)\{(?:mb|mangabaka|rdb|ranobedb|ol|openlibrary|open_library|mal|myanimelist|my_anime_list|anilist|al|tvmaze|wikidata|wd|tmdb|tvdb|imdb|local)-[^}]+\}"#
        ) else {
            return []
        }
        let nsPath = path as NSString
        let fullRange = NSRange(location: 0, length: nsPath.length)
        return regex.matches(in: path, range: fullRange).map { match in
            nsPath.substring(with: match.range)
        }
    }

    private func providerTokenText(_ tokens: [String]) -> String {
        tokens.isEmpty ? "none" : tokens.joined(separator: " ")
    }

    private func firstPathComponent(in path: String) -> String? {
        path.split(separator: "/", omittingEmptySubsequences: true).first.map(String.init)
    }

    private func pathLine(_ label: String, path: String, symbol: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Label(label, systemImage: symbol)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 94, alignment: .leading)
                .labelStyle(.titleAndIcon)

            Text(path)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .accessibilityTextContentType(.fileSystem)
        }
    }

    private func confidenceBadge(_ item: LibraryPlanItem) -> some View {
        Text(item.isReviewGatedEPUBRepairOperation ? "Repair available" : isCleanSourceNeededEPUBRepairItem(item) ? "Clean source" : isManualDiagnosticItem(item) ? "Repair blocked" : confidenceTitle(item.confidence))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(confidenceTint(item.confidence), in: Capsule())
    }

    private func safetyBadge(_ item: LibraryPlanItem) -> some View {
        Text(item.isReviewGatedEPUBRepairOperation ? "Check to apply" : isCleanSourceNeededEPUBRepairItem(item) ? "Clean source needed" : isManualDiagnosticItem(item) ? "Needs rule" : safetyTitle(item.safety))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
    }

    private func summarySection(for run: LibraryPipelineRun) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            summaryOnly(for: run)

            if let verification = run.context.inspection?.verification {
                Label(verification.message, systemImage: verification.needsAttention ? "exclamationmark.triangle" : "checkmark.seal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let applyResult {
                lastApply(applyResult)
            }
        }
        .padding(16)
        .sableLibraryPanelSurface()
    }

    private func summaryOnly(for run: LibraryPipelineRun) -> some View {
        let summary = pipelineSummary ?? fallbackSummary(for: run)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.title)
                        .font(.headline)
                    Text(summary.message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            whatNowPanel(for: run)

            Label(summaryCompactStatusText(summary, run: run), systemImage: summary.unresolvedCount > 0 ? "questionmark.circle" : "checkmark.circle")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func summaryCompactStatusText(
        _ summary: LibraryPipelineSummary,
        run: LibraryPipelineRun
    ) -> String {
        var parts: [String] = []
        if summary.unresolvedCount > 0 {
            parts.append("\(summary.unresolvedCount) need choice")
        }
        if checkedCount > 0 {
            parts.append("\(checkedCount) ready")
        }
        if summary.appliedCount > 0 {
            parts.append("\(summary.appliedCount) applied")
        }
        if !run.context.plan.skippedItems.isEmpty {
            parts.append("\(run.context.plan.skippedItems.count) skipped")
        }
        if parts.isEmpty {
            if let profile = clinicEmptyCheckProfile(for: run) {
                switch profile {
                case .fast:
                    return "Fast EPUB layers clear; deep layers not run."
                case .deep:
                    return "Full Check clear; nothing is waiting."
                default:
                    return "\(profile.title) clear; no repair rows."
                }
            }
            return "Nothing is waiting right now."
        }
        return parts.joined(separator: " · ")
    }

    private func whatNowPanel(for run: LibraryPipelineRun) -> some View {
        let nextApply = nextApplyStage(in: run)
        let safeCheckStage = nextSafeCheckStage(in: run)
        let questionStage = firstQuestionStage(in: run)
        let suggestionStage = firstSuggestionStage(in: run)
        let checkedChanges = nextApply.map { applyCount(for: $0, in: run) } ?? 0
        let safeCheckedChanges = nextApply.map { safeCheckedApplyCount(for: $0, in: run) } ?? 0
        let manualCheckedChanges = max(0, checkedChanges - safeCheckedChanges)
        let safeUncheckedChanges = safeCheckStage.map { safeUncheckedCount(for: $0, in: run) } ?? 0

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(
                    "What now?",
                    systemImage: whatNowSymbol(
                        nextApplyStage: nextApply,
                        safeCheckStage: safeCheckStage,
                        questionStage: questionStage,
                        suggestionStage: suggestionStage
                    )
                )
                .font(.subheadline.weight(.semibold))

                Spacer(minLength: 0)

                EmptyView()
            }

            Text(whatNowMessage(
                run: run,
                nextApplyStage: nextApply,
                safeCheckStage: safeCheckStage,
                questionStage: questionStage,
                suggestionStage: suggestionStage,
                checkedChanges: checkedChanges,
                safeCheckedChanges: safeCheckedChanges,
                manualCheckedChanges: manualCheckedChanges,
                safeUncheckedChanges: safeUncheckedChanges,
                unresolvedCount: run.context.plan.unresolvedItems.count
            ))
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    whatNowActionButtons(
                        run: run,
                        nextApplyStage: nextApply,
                        safeCheckStage: safeCheckStage,
                        questionStage: questionStage,
                        suggestionStage: suggestionStage,
                        checkedChanges: checkedChanges,
                        safeUncheckedChanges: safeUncheckedChanges,
                        manualCheckedChanges: manualCheckedChanges
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    whatNowActionButtons(
                        run: run,
                        nextApplyStage: nextApply,
                        safeCheckStage: safeCheckStage,
                        questionStage: questionStage,
                        suggestionStage: suggestionStage,
                        checkedChanges: checkedChanges,
                        safeUncheckedChanges: safeUncheckedChanges,
                        manualCheckedChanges: manualCheckedChanges
                    )
                }
            }
            .controlSize(.small)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func whatNowActionButtons(
        run: LibraryPipelineRun,
        nextApplyStage: LibraryPipelineStage?,
        safeCheckStage: LibraryPipelineStage?,
        questionStage: LibraryPipelineStage?,
        suggestionStage: LibraryPipelineStage?,
        checkedChanges: Int,
        safeUncheckedChanges: Int,
        manualCheckedChanges: Int
    ) -> some View {
        whatNowPrimaryButton(
            run: run,
            nextApplyStage: nextApplyStage,
            safeCheckStage: safeCheckStage,
            questionStage: questionStage,
            suggestionStage: suggestionStage,
            checkedChanges: checkedChanges,
            safeUncheckedChanges: safeUncheckedChanges,
            manualCheckedChanges: manualCheckedChanges
        )

        if let questionStage, canQuickCheck || nextApplyStage != nil || safeCheckStage != nil {
            Button {
                selectedStage = questionStage
            } label: {
                Label("Question Queue", systemImage: "questionmark.circle")
            }
            .disabled(isWorking)
            .help("Jump to the first row that needs a real choice.")
        }

        Button(action: onOpenReports) {
            Label("Reports", systemImage: "folder")
        }
        .disabled(libraryURL == nil)
        .help("Open receipts and cleanup reports.")

        Menu {
            Button("Restore Last Apply") {
                showRestoreLastApplyConfirmation = true
            }
            .disabled(libraryURL == nil || isWorking)

            Button("Doctor Check") {
                onDoctorCheck()
            }
            .disabled(libraryURL == nil || isWorking)
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
        .disabled(libraryURL == nil)
        .help("Restore the last apply run or write a doctor check report.")
    }

    @ViewBuilder
    private func whatNowPrimaryButton(
        run: LibraryPipelineRun,
        nextApplyStage: LibraryPipelineStage?,
        safeCheckStage: LibraryPipelineStage?,
        questionStage: LibraryPipelineStage?,
        suggestionStage: LibraryPipelineStage?,
        checkedChanges: Int,
        safeUncheckedChanges: Int,
        manualCheckedChanges: Int
    ) -> some View {
        if clinicEmptyCheckProfile(for: run) == .fast {
            Button {
                onClinicCheck(.deep)
            } label: {
                Label("Run Full Check", systemImage: SableClinicCheckProfile.deep.systemImage)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isWorking)
            .help(SableClinicCheckProfile.deep.detail)
        } else if canQuickCheck {
            Button(action: onQuickCheck) {
                Label("Check Again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isWorking)
            .help("Verify the last applied step and refresh the next suggestions.")
        } else if let nextApplyStage {
            Button {
                selectedStage = nextApplyStage
                requestApply(nextApplyStage)
            } label: {
                Label(
                    nextApplyStage == .providerMatches
                        ? "Teach Checked Providers"
                        : nextApplyStage == .comicInfo
                        ? "Run Checked Metadata"
                        : manualCheckedChanges == 0
                        ? "Apply Checked Safe Rows"
                        : "Review & Apply: \(applyStageTitle(nextApplyStage))",
                    systemImage: "checkmark.circle"
                )
            }
            .buttonStyle(.borderedProminent)
            .disabled(isWorking || checkedChanges == 0)
            .help(nextApplyStage.isMetadataSidecarStage ? "Run the next metadata checkpoint and refresh this lane." : manualCheckedChanges == 0 ? "Apply the next checked safe step." : "Open confirmation for the next checked step.")
        } else if let safeCheckStage {
            Button {
                selectedStage = safeCheckStage
                checkAllSafe(in: safeCheckStage, run: run)
            } label: {
                Label("Check Safe", systemImage: "checkmark.shield")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isWorking || safeUncheckedChanges == 0)
            .help("Check all local reversible rows in the next step. Search, conflict, and review rows stay out.")
        } else if let questionStage {
            Button {
                selectedStage = questionStage
            } label: {
                Label("Answer Questions", systemImage: "questionmark.circle")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isWorking)
            .help("Jump to the first row that needs a real choice.")
        } else if let suggestionStage {
            Button {
                selectedStage = suggestionStage
            } label: {
                Label("Open Suggestions", systemImage: "list.bullet.rectangle")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isWorking)
            .help("Open the first cleanup step with suggestions.")
        } else {
            Button(action: onInspect) {
                Label("Inspect Again", systemImage: "magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
            .disabled(libraryURL == nil || isWorking)
            .help("Run a fresh read-only inspection.")
        }
    }

    private func whatNowSymbol(
        nextApplyStage: LibraryPipelineStage?,
        safeCheckStage: LibraryPipelineStage?,
        questionStage: LibraryPipelineStage?,
        suggestionStage: LibraryPipelineStage?
    ) -> String {
        if canQuickCheck {
            return "arrow.clockwise.circle"
        }
        if nextApplyStage != nil {
            return "checkmark.circle"
        }
        if safeCheckStage != nil {
            return "checkmark.square"
        }
        if questionStage != nil {
            return "questionmark.circle"
        }
        if suggestionStage != nil {
            return "list.bullet.rectangle"
        }
        return "checkmark.seal"
    }

    private func whatNowMessage(
        run: LibraryPipelineRun,
        nextApplyStage: LibraryPipelineStage?,
        safeCheckStage: LibraryPipelineStage?,
        questionStage: LibraryPipelineStage?,
        suggestionStage: LibraryPipelineStage?,
        checkedChanges: Int,
        safeCheckedChanges: Int,
        manualCheckedChanges: Int,
        safeUncheckedChanges: Int,
        unresolvedCount: Int
    ) -> String {
        if let profile = clinicEmptyCheckProfile(for: run) {
            if profile == .fast {
                return "Fast Check found no repair rows. Run Full Check when you want Clinic to inspect XHTML, CSS, linked resources, images, and page layout too."
            }
            return profile.emptyMessage
        }

        if canQuickCheck {
            return "A step just changed files. Run Check Again so the next suggestions use the current collection."
        }

        if let nextApplyStage {
            let stageTitle = applyStageTitle(nextApplyStage)
            if nextApplyStage == .providerMatches {
                return "\(checkedChanges) checked provider match row\(checkedChanges == 1 ? "" : "s") waiting in \(stageTitle). Sable will save exact IDs or learned No ID choices, then refresh the queue."
            }
            if nextApplyStage == .comicInfo {
                return "\(checkedChanges) checked metadata row\(checkedChanges == 1 ? "" : "s") waiting in \(stageTitle). Sable will run the next refresh checkpoint and refresh the lane."
            }
            if manualCheckedChanges == 0 {
                return "\(checkedChanges) checked safe change\(checkedChanges == 1 ? "" : "s") waiting in \(stageTitle)."
            }
            return "\(checkedChanges) checked change\(checkedChanges == 1 ? "" : "s") waiting in \(stageTitle): \(safeCheckedChanges) safe, \(manualCheckedChanges) with extra review in the confirmation."
        }

        if let safeCheckStage {
            return "\(safeUncheckedChanges) safe suggestion\(safeUncheckedChanges == 1 ? "" : "s") can be checked automatically in \(applyStageTitle(safeCheckStage)). Search, conflict, and uncertain rows stay for you."
        }

        if let questionStage {
            return "\(unresolvedCount) real question\(unresolvedCount == 1 ? "" : "s") need your choice. Start with \(applyStageTitle(questionStage))."
        }

        if let suggestionStage {
            return "Suggestions are ready in \(applyStageTitle(suggestionStage)). Open that step, check the good rows, then apply."
        }

        if appMode == .clinic {
            return "Nothing is waiting from this Clinic pass. Run the relevant pass again after EPUBs change; only a validation pass can say the EPUBs are clean."
        }
        return "Nothing is waiting right now. The collection looks clear from the latest inspection."
    }

    private func clinicEmptyCheckProfile(for run: LibraryPipelineRun) -> SableClinicCheckProfile? {
        guard appMode == .clinic,
              run.context.inspectMode.wakesEPUBRepairSpecialists,
              run.context.plan.activeItems.isEmpty else {
            return nil
        }
        return clinicCheckProfile(for: run)
    }

    private func lastApply(_ result: LibraryApplyResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Last apply")
                .font(.subheadline.weight(.semibold))
            Text("\(result.appliedCount) applied, \(result.skippedCount) skipped")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                pendingReceiptPreview = SableLibraryReceiptPreview(title: "Last receipt", result: result)
            } label: {
                Label("Preview Receipt", systemImage: "doc.text.magnifyingglass")
            }
            .controlSize(.small)
            .disabled(result.summary.isEmpty)
            .help("Open the latest receipt text in a selectable preview.")

            if let receiptPath = result.receiptPath {
                HStack {
                    Text(receiptPath)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button(action: onOpenReports) {
                        Label("Reports", systemImage: "folder")
                    }
                    .buttonStyle(.borderless)

                    Button {
                        copyAbsolutePath(receiptPath)
                    } label: {
                        Label("Copy Path", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("Copy the receipt path.")
                }
                .contextMenu {
                    Button("Open Report Folder") {
                        onOpenReports()
                    }
                    Button("Reveal Receipt in Finder") {
                        revealAbsolutePathInFinder(receiptPath)
                    }
                    Button("Copy Receipt Path") {
                        copyAbsolutePath(receiptPath)
                    }
                }
            }
        }
    }

    private func fallbackSummary(for run: LibraryPipelineRun) -> LibraryPipelineSummary {
        let plannedCount = run.context.plan.activeItems.count
        let unresolvedCount = run.context.plan.unresolvedItems.count
        let emptyMessage = appMode == .clinic
            ? "No EPUB repair suggestions are waiting from this pass. This is not a full EPUBCheck clean bill unless the validation layer has passed."
            : "No cleanup suggestions are waiting."
        return LibraryPipelineSummary(
            title: plannedCount == 0
                ? (appMode == .clinic ? "No Clinic Rows Waiting" : "Library Looks Clear")
                : "Quiet Plan Ready",
            message: plannedCount == 0 ? emptyMessage : "Safe changes are checked. Uncertain items stay untouched unless they need attention.",
            nextAction: run.nextAction,
            plannedCount: plannedCount,
            unresolvedCount: unresolvedCount,
            appliedCount: applyResult?.appliedCount ?? 0
        )
    }

    private func requestApply(
        _ stage: LibraryPipelineStage,
        itemIDs: [LibraryPlanItem.ID]? = nil,
        scopeTitle: String? = nil,
        mode: SableLibraryApplyRequestMode = .checkedRows
    ) {
        guard !isWorking else { return }
        let clearedHiddenCategoryCount = clearHiddenCheckedRows(for: stage)
        let selectedIDs = itemIDs.map(Set.init)
        let hiddenSearchCheckedCount = hiddenCheckedBySearchCount(for: stage, limitingTo: selectedIDs)
        let count = applyCount(for: stage, limitingTo: selectedIDs)
        guard count > 0 else { return }
        pendingApplyRequest = SableLibraryApplyRequest(
            mode: mode,
            stage: stage,
            itemIDs: itemIDs,
            scopeTitle: scopeTitle,
            summary: applyConfirmationSummary(
                for: stage,
                limitingTo: selectedIDs,
                hiddenSearchCheckedCount: hiddenSearchCheckedCount,
                clearedHiddenCategoryCount: clearedHiddenCategoryCount
            )
        )
    }

    private func requestExactIDBatchRefresh(_ stage: LibraryPipelineStage) {
        guard !isWorking,
              let run else { return }
        let items = exactIDBatchItems(for: stage, in: run)
        guard !items.isEmpty else { return }
        let itemIDs = items.map(\.id)
        pendingApplyRequest = SableLibraryApplyRequest(
            mode: .exactIDBatch,
            stage: stage,
            itemIDs: itemIDs,
            scopeTitle: "Batch Refresh IDs",
            summary: applyConfirmationSummary(
                for: stage,
                limitingTo: Set(itemIDs),
                hiddenSearchCheckedCount: hiddenCheckedBySearchCount(for: stage, limitingTo: Set(itemIDs)),
                clearedHiddenCategoryCount: 0
            )
        )
    }

    private func applyConfirmationTitle(for request: SableLibraryApplyRequest) -> String {
        let stage = request.stage
        let count = request.summary.safeApplyCount
        if request.mode == .exactIDBatch {
            return "Batch refresh saved provider IDs?"
        }
        if request.mode == .singleProviderMatch {
            return "Save this provider match?"
        }
        if stage == .covers {
            if request.mode == .mangaBakaCoverBaseline {
                return "Fill MangaBaka cover gaps for \(count) series?"
            }
            if request.mode == .storeCoverQualityUpgrade {
                return "Check \(count) series for quality upgrades?"
            }
            if coverRequestOnlyVerifiesExisting(request) {
                return "Verify existing covers for \(count) series?"
            }
            return "Download covers for \(count) series?"
        }
        if stage.isMetadataSidecarStage {
            if let scopeTitle = request.scopeTitle {
                return "Run \(scopeTitle)?"
            }
            return stage == .providerMatches
                ? "Run checked provider matches?"
                : "Run next metadata pass in \(applyStageTitle(stage))?"
        }
        return "Apply \(count) safe change\(count == 1 ? "" : "s") in \(applyStageTitle(stage))?"
    }

    private func applyButtonTitle(for request: SableLibraryApplyRequest) -> String {
        let count = request.summary.safeApplyCount
        let stage = request.stage
        if request.mode == .exactIDBatch {
            return "Batch Refresh \(count) ID Row\(count == 1 ? "" : "s")"
        }
        if request.mode == .singleProviderMatch {
            return "Save This Match"
        }
        if stage == .covers {
            if request.mode == .mangaBakaCoverBaseline {
                return "Fill MangaBaka Gaps"
            }
            if request.mode == .storeCoverQualityUpgrade {
                return "Find Quality Upgrades"
            }
            if coverRequestOnlyVerifiesExisting(request) {
                return "Verify Existing Covers"
            }
            return "Download Checked Covers"
        }
        if stage.isMetadataSidecarStage {
            return request.scopeTitle == nil ? "Run Checked Passes" : "Run This Group"
        }
        return "Apply \(count) Safe Change\(count == 1 ? "" : "s")"
    }

    private func applyToolbarButtonTitle(for stage: LibraryPipelineStage) -> String {
        if stage == .covers {
            let checked = run?.context.plan.items.filter {
                $0.stage == .covers
                    && $0.decision == .checked
                    && $0.isApplyableOperation
            } ?? []
            if !checked.isEmpty,
               checked.allSatisfy({
                   $0.reviewTags.contains("cover-manifest-unverified")
               }) {
                return "Verify Existing Covers"
            }
            return "Download Covers"
        }
        return stage.isMetadataSidecarStage ? "Run Ready Changes" : "Apply Ready Changes"
    }

    private func applyAccessibilityHint(for stage: LibraryPipelineStage) -> String {
        if stage == .providerMatches {
            return "Opens a confirmation before saving checked provider matches or learned No ID choices."
        }
        if stage == .comicInfo {
            return "Opens a confirmation before running checked metadata provider lookup."
        }
        if stage == .covers {
            let checked = run?.context.plan.items.filter {
                $0.stage == .covers
                    && $0.decision == .checked
                    && $0.isApplyableOperation
            } ?? []
            if !checked.isEmpty,
               checked.allSatisfy({
                   $0.reviewTags.contains("cover-manifest-unverified")
               }) {
                return "Opens a confirmation before checking saved store evidence and updating only selected cover manifests."
            }
            return "Opens a confirmation before contacting cover providers and writing selected series cover folders."
        }
        return "Opens a confirmation before applying safe changes in this step."
    }

    private func coverRequestOnlyVerifiesExisting(
        _ request: SableLibraryApplyRequest
    ) -> Bool {
        guard request.stage == .covers,
              request.mode == .checkedRows else { return false }
        let requestedIDs = request.itemIDs.map(Set.init)
        let items = run?.context.plan.items.filter {
            $0.stage == .covers
                && $0.decision == .checked
                && $0.isApplyableOperation
                && (requestedIDs?.contains($0.id) ?? true)
        } ?? []
        return !items.isEmpty && items.allSatisfy {
            $0.reviewTags.contains("cover-manifest-unverified")
        }
    }

    private func applyConfirmationSummary(
        for stage: LibraryPipelineStage,
        limitingTo itemIDs: Set<LibraryPlanItem.ID>? = nil,
        hiddenSearchCheckedCount: Int = 0,
        clearedHiddenCategoryCount: Int = 0
    ) -> SableLibraryApplyConfirmation {
        let stageItems = run?.context.plan.items.filter { $0.stage == stage } ?? []
        let checkedItems = stageItems.filter { item in
            item.isApplyableOperation
                && (
                    itemIDs?.contains(item.id)
                        ?? (item.decision == .checked)
                )
        }
        var leftUntouchedCount = 0
        var needsAttentionCount = 0
        var conflictsSkipped = 0
        var networkRowsExcluded = 0
        for item in stageItems {
            let isSelected = itemIDs?.contains(item.id)
                ?? (item.decision == .checked)
            if !isSelected && !item.needsDecisionReview {
                leftUntouchedCount += 1
            }
            if item.needsDecisionReview {
                needsAttentionCount += 1
            }
            if item.safety == .collision && !(item.decision == .checked && (item.isNameCollisionResolution || item.isFolderMergeResolution)) {
                conflictsSkipped += 1
            }
            if item.safety == .network {
                networkRowsExcluded += 1
            }
        }
        let affectedPaths = Set(checkedItems.flatMap { item in
            [item.currentPath, item.proposedPath].compactMap { $0 }
        })
        let applyCount = stage == .covers
            ? Set(checkedItems.map(\.currentPath)).count
            : checkedItems.count
        let receiptURL = reportFolderURL?.appendingPathComponent(SableLibraryConfig.fallback.reports.runSummaryReport)

        return SableLibraryApplyConfirmation(
            checkedChangeCount: checkedItems.count,
            affectedPathCount: affectedPaths.count,
            safeApplyCount: applyCount,
            leftUntouchedCount: leftUntouchedCount,
            needsAttentionCount: needsAttentionCount,
            checkpointSummaries: applyCheckpointSummaries(for: stage, limitingTo: itemIDs),
            receiptPath: receiptURL?.path(percentEncoded: false),
            undoAvailability: undoAvailability(for: stage),
            resolvedCollisions: checkedItems.filter(\.isNameCollisionResolution).count,
            mergedFolderItems: checkedItems.filter(\.isFolderMergeResolution).count,
            movedDuplicates: checkedItems.filter(\.isDuplicateMoveAside).count,
            conflictsSkipped: conflictsSkipped,
            networkRowsExcluded: networkRowsExcluded,
            networkLookupCount: checkedItems.filter(\.usedNetworkData).count,
            hiddenSearchCheckedCount: hiddenSearchCheckedCount,
            clearedHiddenCategoryCount: clearedHiddenCategoryCount
        )
    }

    private func applyCheckpointSummaries(
        for stage: LibraryPipelineStage,
        limitingTo itemIDs: Set<LibraryPlanItem.ID>?
    ) -> [SableLibraryApplyCheckpointSummary] {
        guard stage.usesComicInfoApplyEngine,
              let run else { return [] }

        return groups(for: stage, in: run).compactMap { group in
            let applyable = group.items.filter { item in
                item.isApplyableOperation
                    && reviewCategoryScope.contains(reviewCategory(for: item))
            }
            let selectedApplyable = itemIDs.map { ids in
                applyable.filter { ids.contains($0.id) }
            } ?? applyable.filter { $0.decision == .checked }
            let isSelected = !selectedApplyable.isEmpty

            guard isSelected else { return nil }

            return SableLibraryApplyCheckpointSummary(
                title: group.title,
                checkedCount: selectedApplyable.count,
                networkCount: selectedApplyable.filter(\.usedNetworkData).count,
                reviewCount: group.unresolvedItems.count,
                isSelected: isSelected
            )
        }
    }

    private func applyConfirmationSheet(_ request: SableLibraryApplyRequest) -> some View {
        let summary = request.summary
        let verifiesExistingCovers = coverRequestOnlyVerifiesExisting(request)

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(palette.statusWarning.opacity(0.14))
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(palette.statusWarning)
                }
                .frame(width: 58, height: 58)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text(applyConfirmationTitle(for: request))
                        .font(.title2.bold())
                    Text(applyConfirmationSubtitle(for: request))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    SableEagerAdaptiveGrid(
                        minimumItemWidth: 150,
                        horizontalSpacing: 10,
                        verticalSpacing: 10
                    ) {
                        applyConfirmationMetric(
                            "\(summary.safeApplyCount)",
                            label: applyConfirmationPrimaryMetricLabel(
                                for: request,
                                verifiesExistingCovers: verifiesExistingCovers
                            ),
                            symbol: "checkmark.square"
                        )
                        applyConfirmationMetric(
                            "\(summary.leftUntouchedCount)",
                            label: "will stay untouched",
                            symbol: "lock"
                        )
                        applyConfirmationMetric(
                            "\(summary.needsAttentionCount)",
                            label: "still needs a choice",
                            symbol: "exclamationmark.triangle"
                        )
                    }

                    applyConfirmationScopeSection(for: request)

                    if summary.needsExtraReview {
                        SableLibraryInfoBanner(
                            text: verifiesExistingCovers
                                ? "If the saved store page cannot prove the exact edition, the image is kept and that series moves to Unproven Covers to Replace for a real cover search."
                                : applyConfirmationAttentionText(for: request.stage),
                            role: .warning,
                            systemImage: "exclamationmark.triangle"
                        )
                    }

                    if !summary.checkpointSummaries.isEmpty {
                        applyCheckpointSection(summary.checkpointSummaries)
                    }

                    applyConfirmationRiskSection(summary)
                }
                .padding(20)
            }

            Divider()

            HStack {
                Button("Cancel", role: .cancel) {
                    pendingApplyRequest = nil
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(applyButtonTitle(for: request)) {
                    pendingApplyRequest = nil
                    if request.mode == .exactIDBatch, let itemIDs = request.itemIDs {
                        onBatchRefreshExactIDs(request.stage, itemIDs)
                    } else if request.mode == .mangaBakaCoverBaseline {
                        onApplyCovers(request.itemIDs, .mangaBakaBaseline)
                    } else if request.mode == .storeCoverQualityUpgrade {
                        onApplyCovers(request.itemIDs, .storeQualityUpgrade)
                    } else if let itemIDs = request.itemIDs {
                        onApplyStageItems(request.stage, itemIDs, false)
                    } else {
                        onApplyStage(request.stage, false)
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .accessibilityHint(
                    verifiesExistingCovers
                        ? "Checks saved store evidence and updates only the selected cover manifests. Existing images and EPUBs stay untouched."
                        : request.stage == .covers
                        ? "Downloads covers only for the checked series and refreshes the Covers desk afterward."
                        : request.stage.isMetadataSidecarStage
                        ? "Runs a focused metadata pass and refreshes this lane afterward."
                        : "Applies only the safe changes shown in this confirmation."
                )

                if !request.stage.usesComicInfoApplyEngine {
                    Button {
                        pendingApplyRequest = nil
                        onApplyStage(request.stage, true)
                    } label: {
                        Label("Apply, Then Check Again", systemImage: "arrow.clockwise")
                    }
                    .accessibilityHint("Applies the checked rows, then verifies the changed paths and refreshes suggestions.")
                }
            }
            .padding(16)
        }
        .frame(minWidth: 580, idealWidth: 640, minHeight: 520)
    }

    private func applyConfirmationSubtitle(for request: SableLibraryApplyRequest) -> String {
        let stage = request.stage
        if request.mode == .exactIDBatch {
            return "Sable refreshes only checked sidecars that already have saved provider IDs. Rows that need title search, provider matching, or manual review stay untouched."
        }
        if stage == .providerMatches {
            return "Sable works through checked provider questions, saves exact matches or learned No ID choices, then refreshes this provider queue."
        }
        if stage == .comicInfo {
            return "Sable works through the checked metadata rows, writes useful checkpoints, records weak matches, then refreshes this metadata lane."
        }
        if stage == .covers {
            if request.mode == .mangaBakaCoverBaseline {
                return "Sable uses only the saved MangaBaka series identity, fills missing or conflicting normal-cover slots, and leaves every trusted existing cover alone. This pass can safely run with more series in parallel."
            }
            if request.mode == .storeCoverQualityUpgrade {
                return "Sable checks BookLive, BookWalker, and Amazon after the baseline is present. A store image replaces the current cover only when its series, media type, language, and volume match and its downloaded resolution is genuinely better."
            }
            if coverRequestOnlyVerifiesExisting(request) {
                return "These cover images already exist. Sable checks their saved BookLive, BookWalker, or Amazon pages and updates only cover-manifest.json. Images and EPUBs stay untouched."
            }
            return "Sable searches the approved cover providers for each checked series, rejects weak or undersized matches, and writes only the accepted files into that series _covers folder."
        }
        return "Only checked rows are included. Anything uncertain stays untouched for later review."
    }

    private func applyConfirmationAttentionText(for stage: LibraryPipelineStage) -> String {
        if stage == .covers {
            return "Unchecked series stay untouched. Missing, wrong-type, chapter-only, and undersized results are skipped and explained in the receipt."
        }
        if stage.isMetadataSidecarStage {
            return "Rows that still need a provider choice, known-missing review, or confidence check stay untouched and are listed in the receipt."
        }
        return "Rows that still need a decision are not included unless you explicitly checked a resolved choice."
    }

    private func applyConfirmationPrimaryMetricLabel(
        for request: SableLibraryApplyRequest,
        verifiesExistingCovers: Bool
    ) -> String {
        if request.mode == .mangaBakaCoverBaseline {
            return "series will use MangaBaka"
        }
        if request.mode == .storeCoverQualityUpgrade {
            return "series will check stores"
        }
        if verifiesExistingCovers {
            return "series will verify now"
        }
        if request.stage == .covers {
            return "series will download now"
        }
        return request.stage.isMetadataSidecarStage
            ? "will run now"
            : "will change now"
    }

    private func applyConfirmationMetric(_ value: String, label: String, symbol: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(palette.accent)
                .frame(width: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title2.bold())
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sableLibraryRaisedPanelSurface()
        .accessibilityElement(children: .combine)
    }

    private func applyConfirmationDetail(_ title: String, value: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(palette.accent)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.callout)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func applyConfirmationScopeSection(for request: SableLibraryApplyRequest) -> some View {
        let summary = request.summary
        let verifiesExistingCovers = coverRequestOnlyVerifiesExisting(request)

        return VStack(alignment: .leading, spacing: 10) {
            Label("Before Sable starts", systemImage: "shield.checkered")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            applyConfirmationDetail(
                request.stage.usesComicInfoApplyEngine ? "Will run" : "Will change",
                value: verifiesExistingCovers
                    ? "\(summary.safeApplyCount) series with \(summary.checkedChangeCount) Japanese or English cover record\(summary.checkedChangeCount == 1 ? "" : "s") will be checked. Only missing store identity, title, volume, and media-type evidence may be added to cover-manifest.json."
                    : request.stage == .covers
                    ? "\(summary.safeApplyCount) checked series cover search\(summary.safeApplyCount == 1 ? "" : "es") will run. Accepted images and the local cover manifest are the only files written.\(hiddenSearchApplyNote(summary))"
                    : request.stage.isMetadataSidecarStage
                    ? "\(summary.safeApplyCount) checked metadata row\(summary.safeApplyCount == 1 ? "" : "s") in this step. Provider work uses saved IDs or explicit checked choices.\(hiddenSearchApplyNote(summary))"
                    : "\(summary.safeApplyCount) checked row\(summary.safeApplyCount == 1 ? "" : "s") in this step, affecting \(summary.affectedPathCount) path\(summary.affectedPathCount == 1 ? "" : "s").\(hiddenSearchApplyNote(summary))",
                symbol: "checkmark.circle"
            )

            applyConfirmationDetail(
                "Will not change",
                value: verifiesExistingCovers
                    ? "Existing cover images, EPUBs, filenames, and folders stay exactly where they are. Unchecked and ambiguous records stay untouched."
                    : "Unchecked rows, rows that still need a choice, and blocked conflict rows stay where they are.",
                symbol: "lock"
            )

            applyConfirmationDetail(
                "Receipt",
                value: summary.receiptPath ?? "Created after apply with exact changes and untouched counts.",
                symbol: "doc.text"
            )

            applyConfirmationDetail(
                "Recovery",
                value: summary.undoAvailability,
                symbol: "arrow.uturn.backward.circle"
            )
        }
        .padding(12)
        .sableLibraryRaisedPanelSurface()
    }

    private func applyCheckpointSection(_ checkpoints: [SableLibraryApplyCheckpointSummary]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Metadata checkpoints", systemImage: "list.bullet.rectangle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(checkpoints) { checkpoint in
                    HStack(alignment: .center, spacing: 10) {
                        Image(systemName: checkpoint.isSelected ? "play.circle.fill" : "circle")
                            .foregroundStyle(checkpoint.isSelected ? palette.accent : palette.textSecondary)
                            .frame(width: 22)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(checkpoint.title)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(checkpoint.isSelected ? palette.textPrimary : palette.textSecondary)
                            Text(checkpointSummaryText(checkpoint))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .background(.quaternary.opacity(checkpoint.isSelected ? 0.55 : 0.25), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(checkpoint.isSelected ? palette.accent.opacity(0.3) : palette.border.opacity(0.6), lineWidth: 1)
                    )
                }
            }
        }
        .padding(12)
        .sableLibraryRaisedPanelSurface()
    }

    private func checkpointSummaryText(_ checkpoint: SableLibraryApplyCheckpointSummary) -> String {
        var parts = [
            "\(checkpoint.checkedCount) checked row\(checkpoint.checkedCount == 1 ? "" : "s")"
        ]
        if checkpoint.networkCount > 0 {
            parts.append("\(checkpoint.networkCount) provider lookup\(checkpoint.networkCount == 1 ? "" : "s")")
        }
        if checkpoint.reviewCount > 0 {
            parts.append("\(checkpoint.reviewCount) waiting for review")
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func applyConfirmationRiskSection(_ summary: SableLibraryApplyConfirmation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if summary.hiddenSearchCheckedCount > 0 {
                applyConfirmationDetail(
                    "Checked rows hidden by search",
                    value: "\(summary.hiddenSearchCheckedCount) checked row\(summary.hiddenSearchCheckedCount == 1 ? " is" : "s are") outside the current search results and still included. Cancel and clear the search if you want to review the whole checked set first.",
                    symbol: "magnifyingglass"
                )
            }
            if summary.clearedHiddenCategoryCount > 0 {
                applyConfirmationDetail(
                    "Turned-off categories left out",
                    value: "\(summary.clearedHiddenCategoryCount) checked row\(summary.clearedHiddenCategoryCount == 1 ? "" : "s") from turned-off categories were unchecked before this confirmation and will stay untouched.",
                    symbol: "eye.slash"
                )
            }
            if summary.networkLookupCount > 0 {
                applyConfirmationDetail(
                    "Metadata lookups",
                    value: "\(summary.networkLookupCount) checked row\(summary.networkLookupCount == 1 ? "" : "s") may contact enabled metadata providers during apply. Fresh unchanged sidecars can skip calls; only confident results are written.",
                    symbol: "globe"
                )
            }
            if summary.resolvedCollisions > 0 {
                applyConfirmationDetail(
                    "Name conflicts resolved",
                    value: "\(summary.resolvedCollisions) existing destination item\(summary.resolvedCollisions == 1 ? "" : "s") will move into \(SableLibraryConfig.fallback.duplicateFolderName). Undo covers the applied rename; moved-aside items stay in the duplicate folder.",
                    symbol: "arrow.triangle.2.circlepath"
                )
            }
            if summary.mergedFolderItems > 0 {
                applyConfirmationDetail(
                    "Folder merges",
                    value: "\(summary.mergedFolderItems) folder\(summary.mergedFolderItems == 1 ? "" : "s") will merge into an existing destination. Item name conflicts inside that folder get unique names.",
                    symbol: "arrow.down.doc"
                )
            }
            if summary.movedDuplicates > 0 {
                applyConfirmationDetail(
                    "Duplicate copies moved aside",
                    value: "\(summary.movedDuplicates) checked duplicate cop\(summary.movedDuplicates == 1 ? "y" : "ies") will move into \(SableLibraryConfig.fallback.duplicateFolderName).",
                    symbol: "square.2.layers.3d"
                )
            }
            if summary.conflictsSkipped > 0 {
                applyConfirmationDetail(
                    "Name conflicts left out",
                    value: "\(summary.conflictsSkipped) conflict row\(summary.conflictsSkipped == 1 ? "" : "s") will stay unchanged.",
                    symbol: "lock"
                )
            }
            if summary.networkRowsExcluded > 0 {
                applyConfirmationDetail(
                    "Network-only rows left out",
                    value: "\(summary.networkRowsExcluded) network-only row\(summary.networkRowsExcluded == 1 ? "" : "s") will stay unchanged.",
                    symbol: "wifi.slash"
                )
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sableLibraryPanelSurface()
    }

    private func hiddenSearchApplyNote(_ summary: SableLibraryApplyConfirmation) -> String {
        guard summary.hiddenSearchCheckedCount > 0 else { return "" }
        return " This includes \(summary.hiddenSearchCheckedCount) checked row\(summary.hiddenSearchCheckedCount == 1 ? "" : "s") hidden by the current search."
    }

    private func undoAvailability(for stage: LibraryPipelineStage) -> String {
        if stage == .covers {
            return "Cover files are kept rather than deleted automatically; changed manifests receive a backup."
        }
        if stage.isMetadataSidecarStage {
            return "Receipt only for metadata sidecar writes; no automatic undo plan."
        }
        if stage == .prepareRawFiles {
            return "Undo plan saved for root file and folder moves."
        }
        if stage == .epubClinic {
            return "EPUB repairs are validated in place and listed in the receipt."
        }
        return "Undo plan saved for applied file moves."
    }

    private func applyStageTitle(_ stage: LibraryPipelineStage) -> String {
        switch stage {
        case .inspect: appMode.inspectActionTitle
        case .prepareRawFiles: "Prepare Raw Files"
        case .comicInfo: "Metadata Sidecars"
        case .providerMatches: "Provider Matches"
        case .covers: appMode == .covers ? "Cover Archive" : "Covers"
        case .canonicalFolders: "Folder Names"
        case .canonicalFiles: "File Names"
        case .epubClinic: appMode == .covers ? "Update EPUB Covers" : "Sable's Clinic"
        case .duplicateReview: "Duplicates"
        case .reviewApply: "Summary"
        }
    }

    private func stageTitle(for stage: LibraryPipelineStage) -> String {
        if stage == .inspect {
            return appMode.inspectActionTitle
        }
        if stage == .covers, appMode == .covers {
            return "Cover Archive"
        }
        if stage == .epubClinic, appMode == .covers {
            return "Update EPUB Covers"
        }
        return stage.title
    }

    private var reportFolderURL: URL? {
        let root = run?.root ?? libraryURL
        return root?.appendingPathComponent(SableLibraryConfig.fallback.reportFolderName, isDirectory: true)
    }

    private var reviewWorkflowStages: [LibraryPipelineStage] {
        appMode.workflowStages
    }

    private func visibleStepStages(for _: LibraryPipelineRun) -> [LibraryPipelineStage] {
        [.inspect] + reviewWorkflowStages + [.reviewApply]
    }

    private func uniqueStages(_ stages: [LibraryPipelineStage]) -> [LibraryPipelineStage] {
        var seen = Set<LibraryPipelineStage>()
        return stages.filter { stage in
            seen.insert(stage).inserted
        }
    }

    private func recommendedNavigationStage(in run: LibraryPipelineRun) -> LibraryPipelineStage? {
        nextApplyStage(in: run)
            ?? nextSafeCheckStage(in: run)
            ?? firstQuestionStage(in: run)
            ?? firstSuggestionStage(in: run)
            ?? recommendedStage(for: run.context.inspection)
    }

    private func recommendedStage(for inspection: LibraryInspection?) -> LibraryPipelineStage? {
        guard let inspection else { return nil }

        if inspection.looseFileCount > 0 {
            return .prepareRawFiles
        }
        if inspection.missingComicInfoCount + inspection.missingAnimeInfoCount > 0 {
            return .comicInfo
        }
        if inspection.duplicateGroupCount > 0 {
            return .duplicateReview
        }
        if inspection.metadataCandidateCount > 0 {
            return .providerMatches
        }
        if inspection.missingNumberCandidateCount > 0 {
            return .canonicalFiles
        }
        return nil
    }

    private func nextApplyStage(in run: LibraryPipelineRun) -> LibraryPipelineStage? {
        reviewWorkflowStages.first { applyCount(for: $0, in: run) > 0 }
    }

    private func nextSafeCheckStage(in run: LibraryPipelineRun) -> LibraryPipelineStage? {
        reviewWorkflowStages.first { safeUncheckedCount(for: $0, in: run) > 0 }
    }

    private func firstQuestionStage(in run: LibraryPipelineRun) -> LibraryPipelineStage? {
        reviewWorkflowStages.first { stage in
            groups(for: stage, in: run).flatMap(\.unresolvedItems).isEmpty == false
        }
    }

    private func firstSuggestionStage(in run: LibraryPipelineRun) -> LibraryPipelineStage? {
        reviewWorkflowStages.first { stage in
            groups(for: stage, in: run).flatMap(\.activeItems).isEmpty == false
        }
    }

    private func safeCheckedApplyCount(for stage: LibraryPipelineStage, in run: LibraryPipelineRun) -> Int {
        applyableItems(for: stage, in: run).filter(isSafeBulkCheckItem).count
    }

    private func safeUncheckedCount(for stage: LibraryPipelineStage, in run: LibraryPipelineRun) -> Int {
        safeUncheckedItems(for: stage, in: run).count
    }

    private func safeUncheckedItems(for stage: LibraryPipelineStage, in run: LibraryPipelineRun) -> [LibraryPlanItem] {
        guard isReviewStageVisibleInCurrentApp(stage) else { return [] }
        return run.context.plan.items.filter { item in
            item.stage == stage
                && item.decision != .checked
                && isSafeBulkCheckItem(item)
        }
    }

    private func safeAutomationCount(for stage: LibraryPipelineStage, in run: LibraryPipelineRun) -> Int {
        safeAutomationItems(for: stage, in: run).count
    }

    private func safeAutomationItems(for stage: LibraryPipelineStage, in run: LibraryPipelineRun) -> [LibraryPlanItem] {
        guard isReviewStageVisibleInCurrentApp(stage) else { return [] }
        return run.context.plan.items.filter { item in
            guard item.stage == stage, isSafeAutomationItem(item) else {
                return false
            }

            if stage == .comicInfo {
                return item.operation == .createComicInfo
                    || item.operation == .createAnimeInfo
                    || item.reviewTags.contains("metadata-comicinfo-cleaner")
                    || item.reviewTags.contains("metadata-animeinfo-cleaner")
            }

            return true
        }
    }

    private func applyableItems(for stage: LibraryPipelineStage, in run: LibraryPipelineRun) -> [LibraryPlanItem] {
        guard isReviewStageVisibleInCurrentApp(stage) else { return [] }
        return run.context.plan.items.filter { item in
            item.stage == stage
                && item.decision == .checked
                && item.isApplyableOperation
                && reviewCategoryScope.contains(reviewCategory(for: item))
        }
    }

    private func exactIDBatchItems(for stage: LibraryPipelineStage, in run: LibraryPipelineRun) -> [LibraryPlanItem] {
        guard isReviewStageVisibleInCurrentApp(stage) else { return [] }
        return run.context.plan.items.filter { item in
            item.stage == stage
                && item.isExactIDBatchRefreshCandidate
        }
    }

    private func applyableItems(in group: LibraryPlanGroup) -> [LibraryPlanItem] {
        group.items.filter { item in
            item.decision == .checked
                && item.isApplyableOperation
                && reviewCategoryScope.contains(reviewCategory(for: item))
        }
    }

    private func checkedApplyableItemIDs(
        in groups: [LibraryPlanGroup]
    ) -> [LibraryPlanItem.ID] {
        groups.flatMap { applyableItems(in: $0) }.map(\.id)
    }

    private func mangaBakaBaselineApplyItemIDs(
        in groups: [LibraryPlanGroup]
    ) -> [LibraryPlanItem.ID] {
        let checkedIDs = checkedApplyableItemIDs(in: groups)
        guard checkedIDs.isEmpty else { return checkedIDs }

        return groups
            .flatMap { bulkDecisionItems(in: $0) }
            .filter { item in
                item.isApplyableOperation
                    && (
                        item.reviewTags.contains("cover-manifest-missing")
                            || item.reviewTags.contains("cover-manifest-incomplete")
                            || item.reviewTags.contains("cover-manifest-conflict")
                            || item.reviewTags.contains("cover-manifest-no-result")
                            || item.reviewTags.contains("cover-manifest-needs-store-check")
                            || item.reviewTags.contains("cover-manifest-unproven-no-result")
                    )
            }
            .map(\.id)
    }

    private func applyCount(for stage: LibraryPipelineStage) -> Int {
        guard let run else { return 0 }
        return applyCount(for: stage, in: run)
    }

    private func applyCount(for stage: LibraryPipelineStage, in run: LibraryPipelineRun) -> Int {
        applyableItems(for: stage, in: run).count
    }

    private func applyCount(
        for stage: LibraryPipelineStage,
        limitingTo itemIDs: Set<LibraryPlanItem.ID>?
    ) -> Int {
        guard let run else { return 0 }
        guard let itemIDs else {
            return applyableItems(for: stage, in: run).count
        }
        return run.context.plan.items.filter { item in
            item.stage == stage
                && itemIDs.contains(item.id)
                && item.isApplyableOperation
                && reviewCategoryScope.contains(reviewCategory(for: item))
        }.count
    }

    private func group(for stage: LibraryPipelineStage, in run: LibraryPipelineRun) -> LibraryPlanGroup? {
        guard isStageVisibleInCurrentApp(stage) else { return nil }
        return run.context.plan.groups.first { $0.stage == stage }
    }

    private func groups(for stage: LibraryPipelineStage, in run: LibraryPipelineRun) -> [LibraryPlanGroup] {
        guard isStageVisibleInCurrentApp(stage) else { return [] }
        let groups = run.context.plan.groups.filter { $0.stage == stage }
        guard (appMode == .clinic || appMode == .covers), stage == .epubClinic else { return groups }
        return groups.compactMap { group in
            var runnableGroup = group
            runnableGroup.items = group.items.filter(\.isApplyableOperation)
            return runnableGroup.items.isEmpty ? nil : runnableGroup
        }
    }

    private func runSafeAutomation(_ stage: LibraryPipelineStage, in run: LibraryPipelineRun) {
        guard !isWorking else { return }

        let itemIDs = safeAutomationItems(for: stage, in: run).map(\.id)
        guard !itemIDs.isEmpty else {
            openStage(stage, in: run)
            return
        }

        selectedStage = stage
        onBulkDecisionChange(itemIDs, .checked)
        onApplyStageItems(stage, itemIDs, true)
    }

    private func openStage(_ stage: LibraryPipelineStage, in run: LibraryPipelineRun) {
        guard isStageEnabled(stage, in: run) else { return }

        selectedStage = stage
        if appMode == .clinic, stage == .epubClinic {
            return
        }
        if appMode == .covers, stage == .epubClinic {
            if shouldDeepInspect(stage, in: run) {
                onClinicCheck(.covers)
            }
            return
        }
        if appMode == .library {
            return
        }
        if shouldDeepInspect(stage, in: run) {
            onStageDeepInspect(stage)
        }
    }

    private func isStageEnabled(_ stage: LibraryPipelineStage, in run: LibraryPipelineRun) -> Bool {
        guard isStageVisibleInCurrentApp(stage) else { return false }
        let stageGroups = groups(for: stage, in: run)
        let itemCount = stageGroups.flatMap(\.activeItems).count
        let skippedCount = stageGroups.flatMap(\.skippedItems).count
        return stage == .inspect
            || stage == .reviewApply
            || itemCount > 0
            || skippedCount > 0
            || reviewWorkflowStages.contains(stage)
    }

    private func shouldDeepInspect(_ stage: LibraryPipelineStage, in run: LibraryPipelineRun) -> Bool {
        guard isReviewStageVisibleInCurrentApp(stage) else { return false }
        let stageGroups = groups(for: stage, in: run)
        return reviewWorkflowStages.contains(stage)
            && stageGroups.flatMap(\.activeItems).isEmpty
            && stageGroups.flatMap(\.skippedItems).isEmpty
    }

    private func isStageVisibleInCurrentApp(_ stage: LibraryPipelineStage) -> Bool {
        stage == .inspect || stage == .reviewApply || isReviewStageVisibleInCurrentApp(stage)
    }

    private func isReviewStageVisibleInCurrentApp(_ stage: LibraryPipelineStage) -> Bool {
        reviewWorkflowStages.contains(stage)
    }

    private func stageButton(_ stage: LibraryPipelineStage, in run: LibraryPipelineRun) -> some View {
        let stageGroups = groups(for: stage, in: run)
        let itemCount = stageGroups.flatMap(\.activeItems).count
        let skippedCount = stageGroups.flatMap(\.skippedItems).count
        let reviewCount = stageGroups.flatMap(\.unresolvedItems).count
        let title = stageTitle(for: stage)

        return Button {
            openStage(stage, in: run)
        } label: {
            HStack(alignment: .center, spacing: 6) {
                Label(title, systemImage: symbol(for: stage))
                    .labelStyle(.titleAndIcon)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)

                if let chipText = stageChipText(stage, itemCount: itemCount, reviewCount: reviewCount, skippedCount: skippedCount, run: run) {
                    Text(chipText)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .foregroundStyle(stageChipTint(reviewCount: reviewCount, itemCount: itemCount, skippedCount: skippedCount))
                        .background(stageChipTint(reviewCount: reviewCount, itemCount: itemCount, skippedCount: skippedCount).opacity(0.14), in: Capsule())
                }
            }
            .frame(minWidth: 98, alignment: .center)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(selectedStage == stage ? palette.accent : palette.textSecondary)
        .disabled(!isStageEnabled(stage, in: run))
        .accessibilityLabel(title)
        .accessibilityValue(stageAccessibilityValue(stage, itemCount: itemCount, reviewCount: reviewCount, skippedCount: skippedCount, run: run))
        .accessibilityHint(stepHint(for: stage, in: run))
    }

    private func stageMenuLabel(for stage: LibraryPipelineStage, in run: LibraryPipelineRun) -> String {
        let title = stageTitle(for: stage)
        if recommendedNavigationStage(in: run) == stage {
            return "\(title) - recommended"
        }

        let stageGroups = groups(for: stage, in: run)
        let itemCount = stageGroups.flatMap(\.activeItems).count
        let reviewCount = stageGroups.flatMap(\.unresolvedItems).count
        if reviewCount > 0 {
            return "\(title) - \(reviewCount) need review"
        }
        if itemCount > 0 {
            return "\(title) - \(itemCount) ready"
        }
        return title
    }

    private func stageChipText(
        _ stage: LibraryPipelineStage,
        itemCount: Int,
        reviewCount: Int,
        skippedCount: Int,
        run: LibraryPipelineRun
    ) -> String? {
        switch stage {
        case .inspect:
            guard selectedStage == .inspect, let inspection = run.context.inspection else { return nil }
            let groupCount = inspection.seriesCount + inspection.videoSeriesCount
            return groupCount == 0 ? nil : "\(groupCount)"
        case .reviewApply:
            let activeCount = run.context.plan.activeItems.count
            return activeCount == 0 ? nil : "\(activeCount)"
        case .prepareRawFiles, .comicInfo, .providerMatches, .covers, .canonicalFolders, .canonicalFiles, .epubClinic, .duplicateReview:
            if reviewCount > 0 {
                return "\(reviewCount)!"
            }
            if itemCount > 0 {
                return "\(itemCount)"
            }
            return skippedCount > 0 ? "\(skippedCount)" : nil
        }
    }

    private func stageChipTint(reviewCount: Int, itemCount: Int, skippedCount: Int) -> Color {
        if reviewCount > 0 {
            return palette.statusWarning
        }
        if itemCount > 0 {
            return palette.accent
        }
        if skippedCount > 0 {
            return palette.textSecondary
        }
        return palette.textSecondary
    }

    private func stageAccessibilityValue(_ stage: LibraryPipelineStage, itemCount: Int, reviewCount: Int, skippedCount: Int, run: LibraryPipelineRun) -> String {
        var values: [String] = []
        if selectedStage == stage {
            values.append("Selected")
        }
        switch stage {
        case .inspect:
            if let inspection = run.context.inspection {
                values.append("\(inspection.bookFileCount) book files")
                values.append("\(inspection.videoFileCount) video files")
                values.append("\(inspection.seriesCount) reading series")
                values.append("\(inspection.videoSeriesCount) watching groups")
            } else {
                values.append("Read only")
            }
        case .reviewApply:
            values.append("\(run.context.plan.activeItems.count) planned")
        case .prepareRawFiles, .comicInfo, .providerMatches, .covers, .canonicalFolders, .canonicalFiles, .epubClinic, .duplicateReview:
            values.append(itemCount == 0 ? "Clear" : "\(itemCount) suggestions")
            if reviewCount > 0 {
                values.append("\(reviewCount) need review")
            }
            if skippedCount > 0 {
                values.append("\(skippedCount) skipped")
            }
        }
        return values.joined(separator: ", ")
    }

    private func stageSubtitle(_ stage: LibraryPipelineStage, itemCount: Int, reviewCount: Int, skippedCount: Int, run: LibraryPipelineRun) -> String {
        switch stage {
        case .inspect:
            if let inspection = run.context.inspection {
                let reading = "\(inspection.bookFileCount) book\(inspection.bookFileCount == 1 ? "" : "s")"
                let watching = inspection.videoFileCount > 0 ? ", \(inspection.videoFileCount) video\(inspection.videoFileCount == 1 ? "" : "s")" : ""
                return "\(reading)\(watching), \(inspection.seriesCount + inspection.videoSeriesCount) groups"
            }
            return "Read only"
        case .reviewApply:
            return "\(run.context.plan.activeItems.count) planned"
        case .prepareRawFiles, .comicInfo, .providerMatches, .covers, .canonicalFolders, .canonicalFiles, .epubClinic, .duplicateReview:
            guard itemCount > 0 else {
                return skippedCount > 0 ? "\(skippedCount) skipped" : "Clear"
            }
            return reviewCount > 0 ? "\(itemCount) items, \(reviewCount) review" : "\(itemCount) ready"
        }
    }

    private func checkedCount(in group: LibraryPlanGroup) -> Int {
        group.items.filter { $0.decision == .checked }.count
    }

    private func reviewCount(in group: LibraryPlanGroup) -> Int {
        group.unresolvedItems.count
    }

    private func canCheck(_ item: LibraryPlanItem) -> Bool {
        item.isApplyableOperation
    }

    private func isManualDiagnosticItem(_ item: LibraryPlanItem) -> Bool {
        if isCleanSourceNeededEPUBRepairItem(item) {
            return false
        }
        if item.isReviewGatedEPUBRepairOperation {
            return false
        }
        return item.reviewTags.contains("ml-training-epub-manual-review")
            || (
                item.stage == .epubClinic
                    && item.requiresReview
                    && (item.operation == .repairEpubPackage || item.operation == .repairAppleBooksCompatibility)
            )
    }

    private func isProtectedEPUBRepairItem(_ item: LibraryPlanItem) -> Bool {
        item.reviewTags.contains("epub-protected")
    }

    private func isCleanSourceNeededEPUBRepairItem(_ item: LibraryPlanItem) -> Bool {
        isProtectedEPUBRepairItem(item)
    }

    private func stageHasOnlyManualDiagnostics(_ groups: [LibraryPlanGroup]) -> Bool {
        let activeItems = groups.flatMap(\.activeItems)
        return !activeItems.isEmpty && activeItems.allSatisfy {
            isManualDiagnosticItem($0) || isCleanSourceNeededEPUBRepairItem($0)
        }
    }

    @ViewBuilder
    private func planItemSelectionControl(_ item: LibraryPlanItem) -> some View {
        if canCheck(item) {
            Toggle("", isOn: Binding(
                get: { item.decision == .checked },
                set: { isOn in
                    onDecisionChange(item.id, isOn ? .checked : .unchecked)
                }
            ))
            .labelsHidden()
            .disabled(isWorking)
            .accessibilityLabel(item.decision == .checked ? "Uncheck suggestion" : "Check suggestion")
        } else {
            Image(systemName: isManualDiagnosticItem(item) && !isCleanSourceNeededEPUBRepairItem(item) ? "exclamationmark.triangle" : "lock.circle")
                .font(.title3)
                .foregroundStyle(isManualDiagnosticItem(item) ? palette.statusWarning : .secondary)
                .frame(width: 20, height: 20)
                .accessibilityLabel(isCleanSourceNeededEPUBRepairItem(item) ? "Clean source needed" : isManualDiagnosticItem(item) ? "Repair rule needed" : "Not checkable")
                .help(disabledReason(for: item) ?? "This row is not checkable.")
        }
    }

    private func reviewRowTitle(for item: LibraryPlanItem) -> String {
        isManualDiagnosticItem(item) ? epubDiagnosticTitle(for: item) : operationTitle(for: item)
    }

    private func epubDiagnosticTitle(for item: LibraryPlanItem) -> String {
        let text = epubDiagnosticSearchText(for: item)
        if text.contains("duplicate") && text.contains("manifest") && text.contains("id") {
            return "Duplicate Manifest ID"
        }
        if text.contains("duplicate") && text.contains("id") {
            return "Duplicate XHTML ID"
        }
        if text.contains("missing") && (text.contains("resource") || text.contains("linked")) {
            return "Missing EPUB resource"
        }
        if text.contains("navigation") || text.contains("spine") || text.contains("toc") || text.contains("ncx") {
            return "Navigation order issue"
        }
        if text.contains("xhtml") || text.contains("markup") || text.contains("malformed") {
            return "XHTML markup issue"
        }
        if text.contains("cover") {
            return "Cover marker issue"
        }
        if text.contains("fixed-layout") || text.contains("page box") || text.contains("page-image") || text.contains("lossy") {
            return "Fixed-layout repair issue"
        }
        return "EPUB health finding"
    }

    private func epubDiagnosticProblemText(for item: LibraryPlanItem) -> String {
        let text = epubDiagnosticSearchText(for: item)
        if text.contains("duplicate") && text.contains("manifest") && text.contains("id") {
            return "Problem: the OPF manifest repeats an item id, so package references can become ambiguous."
        }
        if text.contains("duplicate") && text.contains("id") {
            return "Problem: one content file repeats an XHTML id, so links or bookmarks can point to the wrong spot."
        }
        if text.contains("missing") && (text.contains("resource") || text.contains("linked")) {
            return "Problem: a page, stylesheet, nav entry, or package record points to a file that is not inside the EPUB."
        }
        if text.contains("navigation") || text.contains("spine") || text.contains("toc") || text.contains("ncx") {
            return "Problem: the visible table of contents does not match the EPUB reading order."
        }
        if text.contains("xhtml") || text.contains("markup") || text.contains("malformed") {
            return "Problem: a chapter has markup that strict EPUB readers may reject."
        }
        if text.contains("cover") {
            return "Problem: the EPUB cover metadata or cover file marker may be missing or inconsistent."
        }
        if text.contains("fixed-layout") || text.contains("page box") || text.contains("page-image") || text.contains("lossy") {
            return "Problem: fixed-layout or page-image data may not match what Apple Books expects."
        }
        return "Problem: Clinic found an EPUB health warning that needs a repair rule before automatic fixing."
    }

    private func epubDiagnosticRepairText(for item: LibraryPlanItem) -> String {
        let text = epubDiagnosticSearchText(for: item)
        if text.contains("duplicate") && text.contains("manifest") && text.contains("id") {
            return "Fix: rename manifest ids only when spine, guide, nav, and package references can be updated unambiguously."
        }
        if text.contains("duplicate") && text.contains("id") {
            return "Fix: keep the first id stable, rename later duplicates, then validate the temporary EPUB before replacing the original."
        }
        if text.contains("missing") && (text.contains("resource") || text.contains("linked")) {
            return "Fix: retarget the link to the real file, remove a stale reference, or add a proven missing file."
        }
        if text.contains("navigation") || text.contains("spine") || text.contains("toc") || text.contains("ncx") {
            return "Fix: rebuild or reorder nav/NCX entries from the spine after checking the order is not intentional."
        }
        if text.contains("xhtml") || text.contains("markup") || text.contains("malformed") {
            return "Fix: repair the exact broken tag or header, then re-run validation on a temporary copy."
        }
        if text.contains("cover") {
            return "Fix: point the OPF cover metadata to the actual cover image without rewriting unrelated files."
        }
        if text.contains("fixed-layout") || text.contains("page box") || text.contains("page-image") || text.contains("lossy") {
            return "Fix: choose a page-layout repair, run it on a temporary EPUB, and keep the original if validation fails."
        }
        return "Fix: classify the finding, build a narrow safe rule, repair a temporary copy, then recheck."
    }

    private func epubDiagnosticSearchText(for item: LibraryPlanItem) -> String {
        [item.reason, item.confidenceExplanation, item.currentPath, item.proposedPath ?? ""]
            .joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    private func disabledReason(for item: LibraryPlanItem) -> String? {
        switch item.safety {
        case .network:
            return item.stage.isMetadataSidecarStage
                ? "This provider row needs a clear match or No ID choice before it can run."
                : "This network row needs a clearer review choice before it can run."
        case .collision:
            return canUseFolderMerge(for: item)
                ? "Use Merge Into Existing to move this folder's contents into the existing destination, Move Aside if the existing destination is the duplicate, or leave this row unchecked."
                : canUseCollisionResolution(for: item)
                ? "Use Move Aside if the existing destination is the duplicate, or leave this row unchecked."
                : "Name conflicts need manual review before moving files."
        case .inspectOnly:
            if isCleanSourceNeededEPUBRepairItem(item) {
                return "Protected EPUB content cannot be rewritten safely. Use a clean unprotected source, then scan again."
            }
            return "This finding stays visible until Sable has a guarded repair path or a clean source to use."
        case .needsChoice:
            if isCleanSourceNeededEPUBRepairItem(item) {
                return "Use a cleaner EPUB or replacement cover source, then scan again. Sable will not invent missing image detail or rewrite protected book content."
            }
            if item.isReviewGatedEPUBRepairOperation {
                return "Check this repair when the proposed fix fits. Sable tests a temporary EPUB first and keeps the original if validation fails."
            }
            if isManualDiagnosticItem(item) {
                return "This needs a new repair rule or a cleaner source. Sable shows a checkbox only for repairs that can validate a temporary EPUB."
            }
            if item.reviewTags.contains("sss-shelf-review") {
                return "Review the shelf suggestion. Check it if this shelf is right, or leave it unchecked."
            }
            if canUseDuplicateMoveAside(for: item) {
                return "Use Move Aside for an extra copy, Keep Both if both should stay, or leave this row unchecked."
            } else if canUsePDFDocumentChoice(item) {
                return "Use Treat as Document for paperwork, forms, receipts, or non-book files. Use Keep as Book when this is reading material."
            } else if canUseLocalTitle(for: item) || canUseManualProviderSearch(for: item) {
                return "Find the correct provider match, paste a provider URL or ID, use the local title, or leave this row unchecked."
            } else {
                return "Leave unchecked until this row has a real manual fix."
            }
        case .reversible:
            return item.proposedPath == nil ? "No destination is available for this suggestion." : nil
        }
    }

    @ViewBuilder
    private func useLocalTitleAction(for item: LibraryPlanItem) -> some View {
        Button("Use Local Title") {
            onCorrection(item.id, .keepTitle)
        }
    }

    @ViewBuilder
    private func moveExistingAsideAction(for item: LibraryPlanItem) -> some View {
        Button("Move Existing Aside") {
            onCorrection(item.id, .moveExistingAside)
        }
    }

    @ViewBuilder
    private func mergeIntoExistingAction(for item: LibraryPlanItem) -> some View {
        Button("Merge Into Existing") {
            onCorrection(item.id, .mergeIntoExisting)
        }
    }

    @ViewBuilder
    private func treatAsDocumentAction(for item: LibraryPlanItem) -> some View {
        Button("Treat as Document") {
            onCorrection(item.id, .treatAsDocument)
        }
    }

    @ViewBuilder
    private func keepAsBookAction(for item: LibraryPlanItem) -> some View {
        Button("Keep as Book") {
            onCorrection(item.id, .treatAsBook)
        }
    }

    @ViewBuilder
    private func rawReadingLaneMenuActions(for item: LibraryPlanItem) -> some View {
        Button("Treat as Light Novel") {
            onCorrection(item.id, .treatAsLightNovel)
        }
        Button("Treat as Manga") {
            onCorrection(item.id, .treatAsManga)
        }
        Button("Treat as Manhwa") {
            onCorrection(item.id, .treatAsManhwa)
        }
        Button("Treat as Manhua") {
            onCorrection(item.id, .treatAsManhua)
        }
        Button("Treat as Prose Book") {
            onCorrection(item.id, .treatAsProseBook)
        }
        Button("Treat as OEL") {
            onCorrection(item.id, .treatAsOEL)
        }
    }

    @ViewBuilder
    private func cleanupKindMenuActions(for item: LibraryPlanItem) -> some View {
        Button("Move to Books") {
            onCorrection(item.id, .treatAsReading)
        }
        Button("Move to Videos") {
            onCorrection(item.id, .treatAsWatching)
        }
        Button("Move to Documents") {
            onCorrection(item.id, .treatAsDocuments)
        }
        Button("Move to Images") {
            onCorrection(item.id, .treatAsImages)
        }
        Button("Move to Audio") {
            onCorrection(item.id, .treatAsAudio)
        }
        Button("Move to Archives") {
            onCorrection(item.id, .treatAsArchives)
        }
        Button("Move to Other") {
            onCorrection(item.id, .treatAsOtherFiles)
        }
    }

    private func canUseCollisionResolution(for item: LibraryPlanItem) -> Bool {
        item.canResolveNameCollision && !item.isNameCollisionResolution
    }

    private func canUseFolderMerge(for item: LibraryPlanItem) -> Bool {
        item.canMergeIntoExistingFolder && !item.isFolderMergeResolution
    }

    private func canUseDuplicateMoveAside(for item: LibraryPlanItem) -> Bool {
        item.canResolveDuplicateReview && !item.isDuplicateMoveAside
    }

    private func canUseRawReadingLaneChoice(_ item: LibraryPlanItem) -> Bool {
        item.stage == .prepareRawFiles
            && (item.operation == .sortIntoFolder || item.operation == .renameFolder)
            && item.reviewTags.contains("raw-reading-lane")
            && item.correctionOptions.contains(.treatAsLightNovel)
    }

    private func canUseCleanupKindChoice(_ item: LibraryPlanItem) -> Bool {
        item.stage == .prepareRawFiles
            && (item.operation == .sortIntoFolder || item.operation == .renameFolder)
            && item.reviewTags.contains("cleanup-kind")
            && item.correctionOptions.contains(.treatAsDocuments)
    }

    private func canUseManualMangaBakaID(for item: LibraryPlanItem) -> Bool {
        item.stage.isMetadataSidecarStage
            && (item.operation == .createComicInfo || item.operation == .refreshComicInfo)
            && canUseManualProviderSearch(for: item)
    }

    private func canUseLocalTitle(for item: LibraryPlanItem) -> Bool {
        item.stage.isMetadataSidecarStage
            && (item.operation == .createComicInfo || item.operation == .refreshComicInfo)
            && item.correctionOptions.contains(.keepTitle)
    }

    private func mangaBakaSearchURL(for item: LibraryPlanItem) -> URL? {
        guard canUseManualMangaBakaID(for: item) else { return nil }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "mangabaka.org"
        components.path = "/search"
        components.queryItems = [
            URLQueryItem(name: "q", value: searchTitle(for: item))
        ]
        return components.url
    }

    private func searchTitle(for item: LibraryPlanItem) -> String {
        let title = URL(fileURLWithPath: item.currentPath).lastPathComponent
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let cleanTitle = SableLibraryProviderQueryCleaner.searchTitle(from: title) {
            return cleanTitle
        }
        return title.isEmpty ? item.currentPath : title
    }

    private func symbol(for stage: LibraryPipelineStage) -> String {
        switch stage {
        case .inspect: "magnifyingglass"
        case .prepareRawFiles: "tray.and.arrow.down"
        case .comicInfo: "doc.text"
        case .providerMatches: "person.text.rectangle"
        case .covers: "photo.on.rectangle.angled"
        case .canonicalFolders: "folder"
        case .canonicalFiles: "doc.text"
        case .epubClinic: "wrench.and.screwdriver"
        case .duplicateReview: "doc.on.doc"
        case .reviewApply: "checklist.checked"
        }
    }

    private func stepHint(for stage: LibraryPipelineStage, in run: LibraryPipelineRun) -> String {
        if stage == .reviewApply {
            return "Shows the summary and next step."
        }
        return group(for: stage, in: run) == nil ? "No suggestions in this step." : "Open this step for review."
    }

    private func operationTitle(_ operation: LibraryPlanOperation) -> String {
        switch operation {
        case .inspectOnly: "Inspect note"
        case .repairEpubPackage: "Repair EPUB"
        case .repairAppleBooksCompatibility: "Apple Books repair"
        case .cleanRawName: "Clean filename"
        case .sortIntoFolder: "Move and clean"
        case .createComicInfo: "Create ComicInfo"
        case .refreshComicInfo: "Refresh ComicInfo"
        case .createAnimeInfo: "Create AnimeInfo"
        case .refreshAnimeInfo: "Refresh AnimeInfo"
        case .renameFolder: "Rename folder"
        case .renameFile: "Rename file"
        case .duplicateDecision: "Duplicate review"
        case .skip: "Skip"
        }
    }

    private func operationTitle(for item: LibraryPlanItem) -> String {
        if item.isEmptySortingFolderCleanup {
            return "Remove empty folder"
        }
        if item.stage == .covers {
            return "Download covers"
        }
        return isPDFDocumentTriageItem(item) ? "PDF triage" : operationTitle(item.operation)
    }

    private func confidenceTitle(_ confidence: LibraryPlanConfidence) -> String {
        switch confidence {
        case .high: "Likely"
        case .medium: "Check"
        case .low: "Unsure"
        case .unknown: "Unknown"
        }
    }

    private func confidenceTint(_ confidence: LibraryPlanConfidence) -> Color {
        switch confidence {
        case .high: palette.statusSuccess.opacity(0.16)
        case .medium: palette.statusWarning.opacity(0.18)
        case .low, .unknown: palette.statusError.opacity(0.16)
        }
    }

    private func safetyTitle(_ safety: LibraryPlanSafety) -> String {
        switch safety {
        case .inspectOnly: "Read only"
        case .reversible: "Reversible"
        case .needsChoice: "Needs choice"
        case .collision: "Conflict"
        case .network: "Network"
        }
    }

    private func planItemAccessibilityLabel(_ item: LibraryPlanItem) -> String {
        "\(operationTitle(for: item)): \(item.currentPath)"
    }

    private func planItemAccessibilityValue(_ item: LibraryPlanItem) -> String {
        var values = [
            "Decision \(decisionTitle(item.decision))",
            "Confidence \(confidenceTitle(item.confidence))",
            "Safety \(safetyTitle(item.safety))"
        ]
        if let proposedPath = item.proposedPath {
            let destinationName = item.operation == .sortIntoFolder ? "Proposed final path" : "Proposed destination"
            values.append("\(destinationName) \(proposedPath)")
        }
        if item.requiresReview {
            values.append("Needs review")
        }
        return values.joined(separator: ", ")
    }

    private func decisionTitle(_ decision: LibraryPlanDecision) -> String {
        switch decision {
        case .unchecked: "Unchecked"
        case .checked: "Checked"
        case .needsChoice: "Needs a choice"
        case .skipped: "Skipped"
        }
    }

    private func planItemAccessibilityHint(_ item: LibraryPlanItem) -> String {
        if canCheck(item) {
            return "Press Space, use the checkbox, or use row actions to include or exclude this suggestion. Use correction actions if the suggestion is wrong."
        }
        if isManualDiagnosticItem(item) {
            return "This EPUB finding needs a new repair rule or a cleaner source before Sable can run it. Use row actions to inspect or copy the evidence."
        }
        if canUseFolderMerge(for: item) {
            return "Use Merge Into Existing if the current folder's contents belong in the existing destination folder."
        }
        if canUseCollisionResolution(for: item) {
            return "Use Move Aside if the existing destination should be moved into the duplicate folder before this rename applies."
        }
        if canUseDuplicateMoveAside(for: item) {
            return "Use Move Aside if this is an extra copy that should go into the duplicate folder."
        }
        return disabledReason(for: item) ?? "This row is informational."
    }

    @discardableResult
    private func togglePlanItemCheck(_ item: LibraryPlanItem) -> Bool {
        guard canCheck(item), !isWorking else { return false }
        onDecisionChange(item.id, item.decision == .checked ? .unchecked : .checked)
        return true
    }

    private func revealPathInFinder(_ path: String, revealParent: Bool = false) {
        #if os(macOS)
        var url = absoluteURL(for: path)
        if revealParent {
            url.deleteLastPathComponent()
        }
        NSWorkspace.shared.activateFileViewerSelecting([nearestExistingURL(startingAt: url)])
        #endif
    }

    private func revealAbsolutePathInFinder(_ path: String) {
        #if os(macOS)
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([nearestExistingURL(startingAt: url)])
        #endif
    }

    private func copyPath(_ path: String) {
        copyAbsolutePath(absoluteURL(for: path).path(percentEncoded: false))
    }

    private func copyAbsolutePath(_ path: String) {
        copyText(path)
    }

    private func copyText(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    private func absoluteURL(for path: String) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        return (run?.root ?? libraryURL ?? URL(fileURLWithPath: "/")).appendingPathComponent(path)
    }

    private func nearestExistingURL(startingAt url: URL) -> URL {
        var candidate = url
        while candidate.path != "/" && !FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) {
            candidate.deleteLastPathComponent()
        }
        return candidate
    }
}

private struct SableConditionalAccessibilityAction: ViewModifier {
    var condition: Bool
    var name: String
    var action: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if condition {
            content.accessibilityAction(named: Text(name), action)
        } else {
            content
        }
    }
}

private extension View {
    func sableAccessibilityAction(
        _ condition: Bool,
        named name: String,
        _ action: @escaping () -> Void
    ) -> some View {
        modifier(SableConditionalAccessibilityAction(condition: condition, name: name, action: action))
    }

    @ViewBuilder
    func sableContextMenu<MenuItems: View>(
        _ condition: Bool,
        @ViewBuilder menuItems: () -> MenuItems
    ) -> some View {
        if condition {
            contextMenu(menuItems: menuItems)
        } else {
            self
        }
    }
}

private enum SableLibraryWorkflowPatternStyle {
    case folders
    case magnifier
    case checklist
    case receipts
}

private enum SableLibraryWorkflowDetail: String, CaseIterable, Identifiable {
    case chooseFolder
    case inspect
    case reviewNotes
    case applyChecked

    var id: String { rawValue }

    var number: Int {
        switch self {
        case .chooseFolder: 1
        case .inspect: 2
        case .reviewNotes: 3
        case .applyChecked: 4
        }
    }

    var title: String {
        switch self {
        case .chooseFolder: "Choose a library folder"
        case .inspect: "Let Sable inspect"
        case .reviewNotes: "Review final suggestions"
        case .applyChecked: "Apply only checked rows"
        }
    }

    var summary: String {
        switch self {
        case .chooseFolder:
            "Pick the top folder that holds this media library."
        case .inspect:
            "Names, file types, paths, and metadata clues are read locally. Nothing changes yet."
        case .reviewNotes:
            "Rows show proposed final outcomes, grouped by the kind of decision they need."
        case .applyChecked:
            "Checked changes apply, receipts are saved, and Check Again can refresh the next review."
        }
    }

    var symbol: String {
        switch self {
        case .chooseFolder: "folder"
        case .inspect: "magnifyingglass"
        case .reviewNotes: "checklist"
        case .applyChecked: "checkmark.seal"
        }
    }

    var patternStyle: SableLibraryWorkflowPatternStyle {
        switch self {
        case .chooseFolder: .folders
        case .inspect: .magnifier
        case .reviewNotes: .checklist
        case .applyChecked: .receipts
        }
    }

    var patternWash: Double {
        switch self {
        case .chooseFolder: 0.20
        case .inspect: 0.16
        case .reviewNotes: 0.18
        case .applyChecked: 0.22
        }
    }

    var patternOpacity: Double {
        switch self {
        case .chooseFolder: 0.18
        case .inspect: 0.14
        case .reviewNotes: 0.16
        case .applyChecked: 0.20
        }
    }

    var what: String {
        switch self {
        case .chooseFolder:
            "The app asks for one top-level folder and treats it as the boundary for the cleanup session. Every scan, report, undo plan, and review note is framed around what is inside that chosen place."
        case .inspect:
            "Inspection walks the selected folder and builds a read-only picture of the library. It looks at file extensions, folder depth, path names, duplicate clues, missing-number patterns, ComicInfo and AnimeInfo coverage, sidecar freshness, and safe naming hints without moving, deleting, renaming, or contacting network services."
        case .reviewNotes:
            "The findings are grouped into focused review pages so the user is not staring at one giant mixed pile. Each row shows the final proposed outcome for that item, not every small cleanup rule that led there."
        case .applyChecked:
            "Apply uses only the checked rows in the visible step. The app confirms the scope, performs reversible file operations where possible, saves receipts or undo data for file-changing work, and can run an immediate check so the next pass uses fresh paths."
        }
    }

    var why: String {
        switch self {
        case .chooseFolder:
            "A clear folder boundary prevents accidental whole-disk cleanup and makes the app feel accountable. The user knows where Sable is allowed to look, and the app can explain paths, reports, and recovery from that single root."
        case .inspect:
            "Read-only inspection lowers risk and creates trust. People are more willing to let a tool help when the first action is observant rather than corrective, especially when the tool is dealing with personal collections and real files."
        case .reviewNotes:
            "Cleanup decisions are easier when they are sorted by kind of risk. A final path question, a metadata question, and a duplicate question ask different things from the user, so they should not compete for attention in the same mental space."
        case .applyChecked:
            "Checked-only apply keeps control with the user. It makes automation feel like a careful assistant instead of a black box, and it turns each cleanup pass into a small reversible commitment instead of a stressful leap."
        }
    }

    var safety: String {
        switch self {
        case .chooseFolder:
            "The chosen folder is not permission to change everything inside it. It is permission to inspect first. File-changing steps still need explicit review, checked rows, and confirmation before anything is written."
        case .inspect:
            "This step should stay read-only. If a future scan needs network metadata, destructive repair, or generated metadata, that work should be surfaced as a separate review item rather than hidden inside inspection. Freshness checks should read saved sidecar facts before asking providers again."
        case .reviewNotes:
            "Every row should make its evidence visible: current path, final path or target, confidence, safety state, reason, and why a row is checked or blocked. Color can help, but text and icons need to carry the same meaning."
        case .applyChecked:
            "The apply button belongs next to the step it affects. Unchecked, conflicted, network-backed, and unclear rows stay out. If a change cannot be undone automatically, the confirmation should say that before the user commits."
        }
    }

    var qualityOfLife: String {
        switch self {
        case .chooseFolder:
            "Remembering the library folder saves repeated setup, while still letting the user forget or replace it. Showing the full path, the folder name, and a Finder handoff reduces small navigation chores."
        case .inspect:
            "A scan that reports what it is doing makes waiting less frustrating. Plain activity text, determinate counts when available, and a Stop route make long libraries feel manageable instead of stuck."
        case .reviewNotes:
            "Focused review pages let users clean in short sessions. Someone can fix raw files today, ignore sidecar refreshes until later, and still understand what remains when they come back."
        case .applyChecked:
            "After apply, Check Again with fresh paths prevents stale suggestions. It also gives the user a satisfying loop: apply a small batch, verify the collection, continue only when the next review is calm."
        }
    }

    var psychology: String {
        switch self {
        case .chooseFolder:
            "Collections are personal. Asking for one folder respects ownership and reduces the fear that the app will judge or rearrange everything. The language should invite the user to hand over a bounded task."
        case .inspect:
            "Messy libraries can carry guilt. Inspection copy should avoid blame and instead describe what was found. The user should feel accompanied by a careful Sable, not graded by a file-naming machine."
        case .reviewNotes:
            "Review fatigue is real. Short rows, clear defaults, and visible reasons help users make decisions without repeatedly re-parsing the same kind of evidence."
        case .applyChecked:
            "The apply moment is where anxiety peaks. The confirmation should slow the user just enough to verify scope, then give a visible result so the action feels complete and recoverable."
        }
    }

    var sociology: String {
        switch self {
        case .chooseFolder:
            "Libraries reflect many communities and naming traditions: manga volumes, web chapters, novels, one-shots, scan groups, publisher folders, languages, and personal sorting rituals. The folder boundary should not assume one correct culture of organization."
        case .inspect:
            "Metadata can come from people, publishers, tools, archives, and fan communities. The app should treat clues as evidence with context, not as universal truth."
        case .reviewNotes:
            "Good review pages let users teach the app their house style. Corrections should become learning signals without shaming the existing library or forcing everyone into one canonical naming scheme."
        case .applyChecked:
            "Applying changes can affect other readers, sync tools, media servers, backup systems, and future imports. Receipts make the cleanup legible to the household or future self who needs to understand what changed."
        }
    }

    var advanced: String {
        switch self {
        case .chooseFolder:
            "Advanced users benefit from seeing exact root paths, report destinations, saved access state, and whether the folder is local, external, or cloud-backed. Those facts shape performance and recovery expectations."
        case .inspect:
            "The scan can eventually expose more diagnostics: file counts by type, skipped packages, unreadable paths, duplicate fingerprint scope, sidecar parse errors, local snapshot freshness, memory-cache reuse, and whether any metadata source would require network approval."
        case .reviewNotes:
            "Power review tools belong here: filter by safety, sort by confidence, reveal in Finder, copy paths, compare duplicate groups, bulk check safe suggestions, and export the current review page as a receipt preview."
        case .applyChecked:
            "The advanced apply view should show operation counts, source and destination roots, collision handling, receipt path, undo-plan coverage, provider-call scope, and any operation that requires manual recovery."
        }
    }
}

private struct CompactSuggestedProviderMatch {
    var provider: SableLibraryMetadataProvider
    var title: String
    var detail: String?
    var confidencePercent: Int?
    var idText: String?
    var isAlreadyChecked: Bool
    var isManual: Bool
}

private struct SableLibraryCoverSearchRequest: Identifiable {
    var id: UUID { item.id }
    let item: LibraryPlanItem
    let query: String
}

private struct SableLibraryCoverSearchSheet: View {
    @Environment(\.sableLibraryPalette) private var palette
    let request: SableLibraryCoverSearchRequest
    let onCancel: () -> Void
    let onSave: (SableLibraryManualCoverSeriesMatch) -> Bool
    let onDownload: () -> Void
    let onSearch: (SableLibraryCoverSource, String, String?) async -> [SableLibraryManualCoverSeriesMatch]
    let openURL: OpenURLAction

    @State private var selectedSource: SableLibraryCoverSource
    @State private var query: String
    @State private var candidates: [SableLibraryManualCoverSeriesMatch] = []
    @State private var isSearching = false
    @State private var didSearch = false
    @State private var searchTask: Task<Void, Never>?
    @State private var savedMatches: [SableLibraryManualCoverSeriesMatch]
    @State private var saveMessage: String?

    private var sources: [SableLibraryCoverSource] {
        switch request.item.requestedCoverLanguages {
        case ["jp"]:
            [.mangaBaka, .bookLiveJP, .bookWalkerJP, .amazonJP]
        case ["en"]:
            [.mangaBaka, .bookWalkerGlobal, .amazon]
        default:
            [.mangaBaka, .bookLiveJP, .bookWalkerJP, .amazonJP, .bookWalkerGlobal, .amazon]
        }
    }

    init(
        request: SableLibraryCoverSearchRequest,
        onCancel: @escaping () -> Void,
        onSave: @escaping (SableLibraryManualCoverSeriesMatch) -> Bool,
        onDownload: @escaping () -> Void,
        onSearch: @escaping (SableLibraryCoverSource, String, String?) async -> [SableLibraryManualCoverSeriesMatch],
        openURL: OpenURLAction
    ) {
        self.request = request
        self.onCancel = onCancel
        self.onSave = onSave
        self.onDownload = onDownload
        self.onSearch = onSearch
        self.openURL = openURL
        let initialSource = Self.initialSource(for: request.item)
        let initialTitles = request.item.coverSearchTitles + [request.query]
        _selectedSource = State(initialValue: initialSource)
        _query = State(
            initialValue: Self.preferredQuery(
                for: initialSource,
                titles: initialTitles,
                fallback: request.query
            )
        )
        _savedMatches = State(initialValue: request.item.manualCoverSeriesMatches)
    }

    private var cleanQuery: String {
        query
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var itemName: String {
        URL(fileURLWithPath: request.item.currentPath).lastPathComponent
    }

    private var knownTitles: [String] {
        SableLibraryCoverDownloadPlanner.uniqueNonEmpty(
            request.item.coverSearchTitles + [request.query]
        )
    }

    private var expectedMediaType: String? {
        let topFolder = request.item.currentPath
            .split(separator: "/")
            .first
            .map { String($0).lowercased() }
        if topFolder == "light novels" || topFolder == "light novel" {
            return "lightNovel"
        }
        if topFolder.map({ ["manga", "manhwa", "manhua", "oel", "comics", "graphic novels"].contains($0) }) == true {
            return "manga"
        }
        return nil
    }

    private var expectedMediaLabel: String {
        switch expectedMediaType {
        case "lightNovel": "Light novel"
        case "manga": "Manga"
        default: "Reading series"
        }
    }

    private var isStoreProofOnly: Bool {
        request.item.reviewTags.contains("cover-manifest-unverified")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "photo.on.rectangle.angled")
                    .foregroundStyle(palette.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        isStoreProofOnly
                            ? "Verify the existing cover series"
                            : "Find the right cover series"
                    )
                        .font(.headline)
                    Text(itemName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button("Done", action: onCancel)
                    .buttonStyle(.borderless)

                Button {
                    onDownload()
                } label: {
                    Label(
                        isStoreProofOnly
                            ? "Save Store Proof"
                            : "Download This Series",
                        systemImage: isStoreProofOnly
                            ? "checkmark.shield"
                            : "arrow.down.circle"
                    )
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(savedMatches.isEmpty || isSearching)
                .help(
                    savedMatches.isEmpty
                        ? "Choose a store series first."
                        : (
                            isStoreProofOnly
                                ? "Save this store choice in the cover manifest without replacing any images."
                                : "Close this search and confirm a cover download for only this series."
                        )
                )
            }
            .padding(20)

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Picker("Search source", selection: $selectedSource) {
                        ForEach(sources, id: \.self) { source in
                            Text(source.displayName).tag(source)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 190, alignment: .leading)

                    Menu {
                        ForEach(orderedTitleChoices, id: \.self) { title in
                            Button(title) {
                                query = title
                            }
                        }
                    } label: {
                        Image(systemName: "character.book.closed")
                    }
                    .menuStyle(.borderlessButton)
                    .help("Choose a saved Japanese, English, or alternative series title")

                    TextField(
                        selectedSource == .bookLiveJP
                            ? "Series title or BookLive series URL"
                            : "Series title",
                        text: $query
                    )
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(runSearch)

                    Button(action: runSearch) {
                        Label(isSearching ? "Searching" : "Search", systemImage: "magnifyingglass")
                    }
                    .disabled(cleanQuery.isEmpty || isSearching)

                    Button(action: openProviderSearch) {
                        Label("Open Site", systemImage: "arrow.up.forward.square")
                    }
                    .disabled(providerSearchURL == nil)
                }

                HStack(spacing: 12) {
                    Label(expectedMediaLabel, systemImage: expectedMediaType == "manga" ? "books.vertical" : "book.closed")
                    Label(sourceLanguageLabel, systemImage: "character.book.closed")
                    Label("500 x 700 archive minimum", systemImage: "rectangle.inset.filled")
                    Label("800 x 1100 Clinic minimum", systemImage: "cross.case")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.textSecondary)

                Text(
                    isStoreProofOnly
                        ? "Choose the store series that these downloaded covers belong to. Sable saves the series and media-type evidence in cover-manifest.json; it does not download, replace, rename, or remove any cover image in this pass."
                        : "Sable prefers a provider's whole series group when one is available, then filters it to the requested media type. You can also paste a BookLive series/tag URL. Individual books remain visible as fallback choices. Correct covers above the archive minimum are saved, while Clinic only uses the higher-quality ones for EPUB replacement."
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let saveMessage {
                    Label(saveMessage, systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.accent)
                        .accessibilityLabel("Saved cover series. \(saveMessage)")
                }

                if !savedMatches.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Saved series choices")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(savedMatches) { match in
                            Label("\(match.source.displayName): \(match.title)", systemImage: "checkmark.circle")
                                .font(.caption)
                                .lineLimit(1)
                        }
                    }
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        candidateResults
                    }
                    .padding(.vertical, 1)
                }
                .frame(minHeight: 330)
            }
            .padding(20)
        }
        .frame(width: 740, height: 640)
        .task {
            if !didSearch, !cleanQuery.isEmpty {
                runSearch()
            }
        }
        .onChange(of: selectedSource) { _, _ in
            searchTask?.cancel()
            candidates = []
            didSearch = false
            isSearching = false
            query = Self.preferredQuery(
                for: selectedSource,
                titles: knownTitles,
                fallback: query
            )
            runSearch()
        }
        .onDisappear {
            searchTask?.cancel()
        }
    }

    @ViewBuilder
    private var candidateResults: some View {
        if isSearching {
            coverMatchCard {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Checking \(selectedSource.displayName)...")
                        .font(.subheadline.weight(.semibold))
                }
            }
        } else if !candidates.isEmpty {
            ForEach(candidates) { candidate in
                coverCandidateCard(candidate)
            }
        } else if didSearch {
            coverMatchCard {
                VStack(alignment: .leading, spacing: 5) {
                    Label("No series returned", systemImage: "questionmark.circle")
                        .font(.subheadline.weight(.semibold))
                    Text("Try the Japanese title, a shorter series title, another source, or open the provider site. Old and niche series genuinely may have no usable result.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func coverCandidateCard(_ candidate: SableLibraryManualCoverSeriesMatch) -> some View {
        coverMatchCard {
            HStack(alignment: .top, spacing: 12) {
                if let thumbnail = candidate.thumbnailURL.flatMap(URL.init(string:)) {
                    SableLibraryProviderThumbnail(url: thumbnail, placeholderSymbol: "book.closed")
                } else {
                    Image(systemName: "book.closed")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(palette.accent)
                        .frame(width: 42, height: 58)
                        .background(palette.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(candidate.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    Text(candidateDetail(candidate))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Text(candidate.providerID)
                        .font(.caption2.monospaced())
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if let urlText = candidate.url, let url = URL(string: urlText) {
                    Button {
                        openURL(url)
                    } label: {
                        Image(systemName: "arrow.up.forward.square")
                    }
                    .buttonStyle(.borderless)
                    .help("Open this series page")
                }

                Button {
                    guard onSave(candidate) else {
                        saveMessage = "This choice could not be saved. Close this window and run Covers check again."
                        return
                    }
                    savedMatches.removeAll { $0.source == candidate.source }
                    savedMatches.append(candidate)
                    savedMatches.sort {
                        $0.source.displayName.localizedStandardCompare($1.source.displayName) == .orderedAscending
                    }
                    saveMessage = candidate.itemType.caseInsensitiveCompare("seriesGroup") == .orderedSame
                        ? "\(candidate.source.displayName) series group saved. Choose \(isStoreProofOnly ? "Save Store Proof" : "Download This Series") when ready."
                        : "\(candidate.source.displayName) exact series saved. Choose \(isStoreProofOnly ? "Save Store Proof" : "Download This Series") when ready."
                } label: {
                    let isSeriesGroup =
                        candidate.itemType.caseInsensitiveCompare("seriesGroup") == .orderedSame
                    Label(
                        savedMatches.contains(where: { $0.id == candidate.id })
                            ? "Saved"
                            : (isSeriesGroup ? "Use This Series Group" : "Use This Exact Series"),
                        systemImage: savedMatches.contains(where: { $0.id == candidate.id })
                            ? "checkmark.circle.fill"
                            : "checkmark"
                    )
                }
                .controlSize(.small)
                .disabled(savedMatches.contains(where: { $0.id == candidate.id }))
            }
        }
    }

    private func candidateDetail(_ candidate: SableLibraryManualCoverSeriesMatch) -> String {
        let type = candidate.bookType ?? candidate.mediaType ?? "series"
        if candidate.itemType.caseInsensitiveCompare("seriesGroup") == .orderedSame {
            return "\(candidate.source.displayName) · series group · \(type)"
        }
        return "\(candidate.source.displayName) · \(type)"
    }

    private var sourceLanguageLabel: String {
        switch selectedSource {
        case .bookLiveJP, .bookWalkerJP, .amazonJP:
            "Japanese covers"
        case .bookWalkerGlobal, .amazon:
            "English covers"
        case .mangaBaka:
            request.item.requestedCoverLanguages == ["jp"]
                ? "Japanese covers"
                : request.item.requestedCoverLanguages == ["en"]
                ? "English covers"
                : "Japanese or English"
        case .ranobeDB, .unknown:
            "Cover reference"
        }
    }

    private var orderedTitleChoices: [String] {
        switch selectedSource {
        case .bookLiveJP, .bookWalkerJP, .amazonJP:
            SableLibraryCoverDownloadPlanner.orderedQueries(knownTitles, language: "jp")
        case .bookWalkerGlobal, .amazon:
            SableLibraryCoverDownloadPlanner.orderedQueries(knownTitles, language: "en")
        case .mangaBaka, .ranobeDB, .unknown:
            knownTitles
        }
    }

    private func coverMatchCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sableLibrarySurface(
                fill: palette.surfaceRaised,
                border: palette.border,
                cornerRadius: 8,
                glassTint: palette.accent
            )
    }

    private func runSearch() {
        guard !cleanQuery.isEmpty, !isSearching else { return }
        searchTask?.cancel()
        isSearching = true
        didSearch = true
        candidates = []
        let source = selectedSource
        let searchText = cleanQuery
        let mediaType = expectedMediaType

        searchTask = Task {
            let results = await onSearch(source, searchText, mediaType)
            guard !Task.isCancelled,
                  selectedSource == source,
                  cleanQuery == searchText else { return }
            candidates = results
            isSearching = false
        }
    }

    private var providerSearchURL: URL? {
        if selectedSource == .mangaBaka {
            var components = URLComponents(string: "https://mangabaka.org/search")
            components?.queryItems = [URLQueryItem(name: "q", value: cleanQuery)]
            return components?.url
        }
        guard let provider = SableLibraryBigBookCoversProvider.provider(for: selectedSource) else {
            return nil
        }
        var components = URLComponents(string: "https://covers.roler.dev/search")
        components?.queryItems = [
            URLQueryItem(name: "q", value: cleanQuery),
            URLQueryItem(name: "provider", value: provider.rawValue)
        ]
        return components?.url
    }

    private func openProviderSearch() {
        guard let providerSearchURL else { return }
        openURL(providerSearchURL)
    }

    private static func initialSource(for item: LibraryPlanItem) -> SableLibraryCoverSource {
        .mangaBaka
    }

    private static func preferredQuery(
        for source: SableLibraryCoverSource,
        titles: [String],
        fallback: String
    ) -> String {
        let language: String
        switch source {
        case .bookLiveJP, .bookWalkerJP, .amazonJP:
            language = "jp"
        case .bookWalkerGlobal, .amazon:
            language = "en"
        case .mangaBaka, .ranobeDB, .unknown:
            return fallback
        }
        return SableLibraryCoverDownloadPlanner.orderedQueries(titles, language: language).first
            ?? fallback
    }
}

private struct SableLibraryProviderSearchRequest: Identifiable {
    var id: UUID { item.id }
    let item: LibraryPlanItem
    let query: String
    let providers: [SableLibraryMetadataProvider]
}

private struct SableLibraryProviderSearchSheet: View {
    @Environment(\.sableLibraryPalette) private var palette
    let request: SableLibraryProviderSearchRequest
    let onCancel: () -> Void
    let onUseLocal: () -> Void
    let onSave: (SableLibraryMetadataProvider, String) -> Void
    let onSearch: (SableLibraryMetadataProvider, String, [String]) async -> [SableLibraryProviderCandidate]
    let openURL: OpenURLAction

    @State private var selectedProvider: SableLibraryMetadataProvider
    @State private var query: String
    @State private var input = ""
    @State private var candidates: [SableLibraryProviderCandidate] = []
    @State private var isSearching = false
    @State private var didSearch = false
    @State private var searchTask: Task<Void, Never>?

    init(
        request: SableLibraryProviderSearchRequest,
        onCancel: @escaping () -> Void,
        onUseLocal: @escaping () -> Void,
        onSave: @escaping (SableLibraryMetadataProvider, String) -> Void,
        onSearch: @escaping (SableLibraryMetadataProvider, String, [String]) async -> [SableLibraryProviderCandidate],
        openURL: OpenURLAction
    ) {
        self.request = request
        self.onCancel = onCancel
        self.onUseLocal = onUseLocal
        self.onSave = onSave
        self.onSearch = onSearch
        self.openURL = openURL
        _selectedProvider = State(initialValue: request.providers.first ?? .openLibrary)
        _query = State(initialValue: request.query)
    }

    private var parsedSourceID: SableLibrarySourceID? {
        SableLibraryManualProviderIDParser.sourceID(provider: selectedProvider, from: input)
    }

    private var itemName: String {
        URL(fileURLWithPath: request.item.currentPath).lastPathComponent
    }

    private var canUseLocalTitle: Bool {
        request.item.stage.isMetadataSidecarStage
            && (request.item.operation == .createComicInfo || request.item.operation == .refreshComicInfo)
            && request.item.correctionOptions.contains(.keepTitle)
    }

    private var cleanQuery: String {
        query
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var localTitle: String {
        cleanQuery.isEmpty ? itemName : cleanQuery
    }

    private var isReadingMetadataOperation: Bool {
        request.item.operation == .createComicInfo || request.item.operation == .refreshComicInfo
    }

    private var selectedProviderMessage: String {
        switch selectedProvider {
        case .openLibrary:
            "Best for ordinary prose, editions, ISBNs, and English-first book checks."
        case .ranobedb:
            "Best for light novels when the next pass needs series and book details."
        case .mangabaka:
            "Best for manga, manhwa, manhua, comics, and strong reading identity."
        case .anilist:
            "Best for anime-adjacent manga, anime, staff, and format clues."
        case .tmdb:
            "Best for movies, TV, anime shows, and Plex-friendly TMDB IDs."
        case .tvdb:
            "Best for TV and anime series IDs when TMDB is not the right source."
        case .imdb:
            "Best for movie and TV title identity with an IMDb tt ID."
        case .tvmaze:
            "Best for TV episode and show identity when TVmaze has the clean match."
        case .wikidata:
            "Best as a bridge ID when other watching providers are incomplete."
        case .myAnimeList:
            "Legacy MyAnimeList IDs can still be kept in sidecars, but live lookup for this provider is not active."
        case .local:
            "Uses the local folder title without a provider lookup."
        }
    }

    private var selectedProviderSymbol: String {
        switch selectedProvider {
        case .openLibrary, .ranobedb:
            "book.closed"
        case .mangabaka:
            "books.vertical"
        case .anilist, .myAnimeList:
            "sparkles"
        case .tmdb, .tvdb, .imdb, .tvmaze:
            "play.rectangle"
        case .wikidata:
            "network"
        case .local:
            "text.badge.checkmark"
        }
    }

    private var validationMessage: String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Search the provider, then paste the exact URL or ID you want Sable to use."
        }
        if let parsedSourceID {
            return "Will use \(parsedSourceID.provider.displayName) ID \(parsedSourceID.value)."
        }
        return "Could not read an ID for \(selectedProvider.displayName). Paste the provider page URL or exact ID."
    }

    private var validationSymbol: String {
        if parsedSourceID != nil { return "checkmark.circle" }
        return input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "info.circle" : "exclamationmark.triangle"
    }

    private var validationColor: Color {
        if parsedSourceID != nil { return palette.accent }
        return input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? palette.textSecondary : palette.statusWarning
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "text.magnifyingglass")
                    .foregroundStyle(palette.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Manual metadata search")
                        .font(.headline)
                    Text("Find the correct entry for \"\(itemName)\"")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .buttonStyle(.borderless)
                    .controlSize(.small)
            }
            .padding(20)

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                Picker("Source", selection: $selectedProvider) {
                    ForEach(request.providers, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 8) {
                    TextField("Search title...", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(runSearch)

                    Button {
                        runSearch()
                    } label: {
                        Label(isSearching ? "Searching" : "Search", systemImage: "magnifyingglass")
                    }
                    .disabled(cleanQuery.isEmpty || isSearching)

                    Button {
                        openSearch()
                    } label: {
                        Label("Open Site", systemImage: "arrow.up.forward.square")
                    }
                    .disabled(searchURL == nil)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        localMatchCard
                        candidateResults
                        providerSearchCard
                        exactIDCard
                    }
                    .padding(.vertical, 1)
                }
                .frame(minHeight: 280)

                HStack {
                    if canUseLocalTitle {
                        Button {
                            onUseLocal()
                        } label: {
                            Label("Use Local Title", systemImage: "text.badge.checkmark")
                        }
                    }
                    Spacer()
                    Button("Cancel", role: .cancel, action: onCancel)
                    Button("Use Match", action: saveIfReady)
                        .keyboardShortcut(.defaultAction)
                        .disabled(parsedSourceID == nil)
                }
            }
            .padding(20)
        }
        .frame(width: 640, height: 590)
        .task {
            if !didSearch, !cleanQuery.isEmpty {
                runSearch()
            }
        }
        .onChange(of: selectedProvider) { _, _ in
            searchTask?.cancel()
            searchTask = nil
            candidates = []
            didSearch = false
            isSearching = false
            input = ""
            runSearch()
        }
        .onDisappear {
            searchTask?.cancel()
            searchTask = nil
        }
    }

    @ViewBuilder
    private var localMatchCard: some View {
        if canUseLocalTitle {
            matchCard {
                HStack(alignment: .top, spacing: 12) {
                    previewIcon("text.badge.checkmark")
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Partial local match")
                            .font(.subheadline.weight(.semibold))
                        Text(localTitle)
                            .font(.callout.weight(.medium))
                            .lineLimit(2)
                        Text(localMatchExplanation)
                            .font(.caption)
                            .foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Button {
                        onUseLocal()
                    } label: {
                        Label("Correct", systemImage: "checkmark")
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    private var providerSearchCard: some View {
        matchCard {
            HStack(alignment: .top, spacing: 12) {
                previewIcon(selectedProviderSymbol)
                VStack(alignment: .leading, spacing: 5) {
                    Text(selectedProvider.displayName)
                        .font(.subheadline.weight(.semibold))
                    Text(cleanQuery.isEmpty ? itemName : cleanQuery)
                        .font(.callout.weight(.medium))
                        .lineLimit(2)
                    Text(selectedProviderMessage)
                        .font(.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if selectedProvider == .openLibrary {
                        Label("English-first search. Watch for omnibus or broad series records.", systemImage: "globe")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(palette.accent)
                    }
                }
                Spacer(minLength: 8)
                Button {
                    openSearch()
                } label: {
                    Label("Open", systemImage: "arrow.up.forward.square")
                }
                .controlSize(.small)
                .disabled(searchURL == nil)
            }
        }
    }

    @ViewBuilder
    private var candidateResults: some View {
        if isSearching {
            matchCard {
                HStack(spacing: 10) {
                    Image(systemName: "hourglass")
                        .foregroundStyle(palette.accent)
                        .accessibilityHidden(true)
                    Text("Checking \(selectedProvider.displayName)...")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                }
            }
        } else if !rankedCandidates.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Possible matches")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(rankedCandidates.enumerated()), id: \.offset) { _, candidate in
                        candidateCard(candidate)
                    }
                }
            }
        } else if didSearch {
            matchCard {
                HStack(alignment: .top, spacing: 12) {
                    previewIcon("questionmark.circle")
                    VStack(alignment: .leading, spacing: 5) {
                        Text(noResultsTitle)
                            .font(.subheadline.weight(.semibold))
                        Text(noResultsMessage)
                            .font(.caption)
                            .foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func candidateCard(_ candidate: SableLibraryProviderCandidate) -> some View {
        matchCard {
            HStack(alignment: .top, spacing: 12) {
                candidatePreview(for: candidate)
                VStack(alignment: .leading, spacing: 5) {
                    Text(candidateDisplayTitle(candidate))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    Text(candidateSummary(candidate))
                        .font(.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(2)
                    if let sourceID = preferredSourceID(for: candidate) {
                        Label("\(sourceID.provider.displayName) \(sourceID.value)", systemImage: "number.circle")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(palette.accent)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                confidenceBadge(for: candidate)
                Button {
                    chooseCandidate(candidate)
                } label: {
                    Label("Use", systemImage: "checkmark")
                }
                .controlSize(.small)
                .disabled(preferredSourceID(for: candidate) == nil)
            }
        }
    }

    private var rankedCandidates: [SableLibraryProviderCandidate] {
        relevantCandidates.enumerated()
            .sorted { lhs, rhs in
                let leftScore = candidateConfidenceScore(lhs.element)
                let rightScore = candidateConfidenceScore(rhs.element)
                if leftScore == rightScore {
                    return lhs.offset < rhs.offset
                }
                return leftScore > rightScore
            }
            .map(\.element)
    }

    private var relevantCandidates: [SableLibraryProviderCandidate] {
        guard readingCatalogProviderUsesExpectedLane(selectedProvider),
              !expectedCatalogMediaTypes.isEmpty else {
            return candidates
        }
        let preferred = candidates.filter(catalogCandidateMatchesExpectedLane)
        return preferred.isEmpty ? candidates : preferred
    }

    private func confidenceBadge(for candidate: SableLibraryProviderCandidate) -> some View {
        let score = candidateConfidenceScore(candidate)
        let label = score >= 90 ? "Strong" : score >= 75 ? "Likely" : score >= 55 ? "Check" : "Weak"
        return VStack(alignment: .trailing, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
            Text("\(score)%")
                .font(.caption2.monospacedDigit())
        }
        .foregroundStyle(score >= 75 ? palette.accent : palette.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill((score >= 75 ? palette.accent : palette.textSecondary).opacity(0.12))
        )
        .accessibilityLabel("Sable confidence \(label), \(score) percent")
    }

    private var exactIDCard: some View {
        matchCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    previewIcon("number.circle")
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Provider URL or ID")
                            .font(.subheadline.weight(.semibold))
                        Text("Paste the exact \(selectedProvider.displayName) page or ID after you find the right match.")
                            .font(.caption)
                            .foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                TextField(providerInputPlaceholder, text: $input)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(saveIfReady)
                    .accessibilityLabel("\(selectedProvider.displayName) URL or ID")

                Label(validationMessage, systemImage: validationSymbol)
                    .font(.caption)
                    .foregroundStyle(validationColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var localMatchExplanation: String {
        let explanation = request.item.confidenceExplanation.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explanation.isEmpty {
            return explanation
        }
        return "Use this when the folder title is already the right identity and provider lookup would only add noise."
    }

    private var noResultsTitle: String {
        "No clear in-app results"
    }

    private var noResultsMessage: String {
        return "Open the provider site or paste an exact URL/ID if you find the right record."
    }

    @ViewBuilder
    private func candidatePreview(for candidate: SableLibraryProviderCandidate) -> some View {
        if let url = candidateCoverURL(for: candidate) {
            SableLibraryProviderThumbnail(
                url: url,
                placeholderSymbol: symbol(for: candidate)
            )
        } else {
            previewIcon(symbol(for: candidate))
        }
    }

    private func coverPlaceholder(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.title3.weight(.semibold))
            .foregroundStyle(palette.accent)
            .frame(width: 42, height: 58)
            .background(palette.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(palette.accent.opacity(0.24), lineWidth: 1)
            }
    }

    private func candidateCoverURL(for candidate: SableLibraryProviderCandidate) -> URL? {
        guard let coverURL = candidate.coverURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !coverURL.isEmpty else {
            return nil
        }
        return URL(string: coverURL)
    }

    private func previewIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.title3.weight(.semibold))
            .foregroundStyle(palette.accent)
            .frame(width: 42, height: 52)
            .sableLibrarySurface(
                fill: palette.accent.opacity(0.12),
                border: palette.accent.opacity(0.24),
                cornerRadius: 8,
                glassTint: palette.accent
            )
    }

    private func matchCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sableLibrarySurface(
                fill: palette.surfaceRaised,
                border: palette.border,
                cornerRadius: 8,
                glassTint: palette.accent
            )
    }

    private var providerInputPlaceholder: String {
        switch selectedProvider {
        case .openLibrary:
            "Open Library work/book URL or OLID"
        case .mangabaka:
            "MangaBaka series URL or ID"
        case .ranobedb:
            "RanobeDB series URL or ID"
        case .tmdb:
            "TMDB URL or ID"
        case .tvdb:
            "TVDB URL or ID"
        case .imdb:
            "IMDb tt ID or URL"
        case .tvmaze:
            "TVmaze URL or ID"
        case .wikidata:
            "Wikidata Q ID or URL"
        case .myAnimeList:
            "Legacy MyAnimeList/MAL numeric ID"
        case .anilist:
            "AniList URL or ID"
        case .local:
            "Local ID"
        }
    }

    private var searchURL: URL? {
        searchURL(provider: selectedProvider, query: query)
    }

    private func openSearch() {
        guard let searchURL else { return }
        openURL(searchURL)
    }

    private func runSearch() {
        guard !cleanQuery.isEmpty, !isSearching else { return }
        searchTask?.cancel()
        isSearching = true
        didSearch = true
        candidates = []
        let provider = selectedProvider
        let searchText = cleanQuery

        searchTask = Task {
            let results = await onSearch(
                provider,
                searchText,
                provider == .anilist ? preferredCatalogMediaTypesForSearch : []
            )
            guard !Task.isCancelled else { return }
            guard selectedProvider == provider, cleanQuery == searchText else { return }
            candidates = results
            isSearching = false
        }
    }

    private func chooseCandidate(_ candidate: SableLibraryProviderCandidate) {
        guard let sourceID = preferredSourceID(for: candidate) else { return }
        input = sourceID.value
        let provider = sourceID.provider
        onSave(provider, sourceID.value)
    }

    private func preferredSourceID(for candidate: SableLibraryProviderCandidate) -> SableLibrarySourceID? {
        if let exact = candidate.sourceIDs.first(where: { $0.provider == selectedProvider }) {
            return exact
        }
        return candidate.sourceIDs.first
    }

    private func candidateConfidenceScore(_ candidate: SableLibraryProviderCandidate) -> Int {
        let queryKey = normalizedCandidateText(cleanQuery.isEmpty ? itemName : cleanQuery)
        let titleKeys = ([candidateDisplayTitle(candidate), candidate.title] + candidate.aliases)
            .map(normalizedCandidateText)
            .filter { !$0.isEmpty }
        guard !queryKey.isEmpty, !titleKeys.isEmpty else { return 35 }

        let bestTitleScore = titleKeys.map { titleKey in
            if titleKey == queryKey { return 0.96 }
            if titleKey.contains(queryKey) || queryKey.contains(titleKey) { return 0.84 }
            return tokenSimilarityForCandidate(queryKey, titleKey)
        }.max() ?? 0

        var score = Int((45 + bestTitleScore * 48).rounded())
        if let candidateYear = candidate.year,
           let queryYear = yearHintForCandidate(in: cleanQuery + " " + itemName),
           candidateYear == queryYear {
            score += 5
        }
        if candidate.sourceIDs.contains(where: { $0.provider == selectedProvider }) {
            score += 3
        }
        if selectedProvider == .openLibrary,
           candidate.languages.contains(where: isEnglishLanguageCode) {
            score += 3
        }
        if readingCatalogProviderUsesExpectedLane(selectedProvider),
           !expectedCatalogMediaTypes.isEmpty {
            if catalogCandidateMatchesExpectedLane(candidate) {
                score += 6
            } else if catalogCandidateIsReadingSide(candidate) {
                score = min(score, 82)
            } else {
                score = min(score, 62)
            }
        }

        return max(10, min(99, score))
    }

    private var expectedCatalogMediaTypes: Set<String> {
        switch request.item.operation {
        case .createComicInfo, .refreshComicInfo:
            switch expectedReadingCatalogLane {
            case .lightNovel:
                return ["NOVEL"]
            case .manga:
                return ["MANGA"]
            case nil:
                return ["MANGA", "NOVEL"]
            }
        case .createAnimeInfo, .refreshAnimeInfo:
            return ["ANIME"]
        case .inspectOnly, .cleanRawName, .sortIntoFolder, .renameFolder, .renameFile, .repairEpubPackage, .repairAppleBooksCompatibility, .duplicateDecision, .skip:
            return []
        }
    }

    private var preferredCatalogMediaTypesForSearch: [String] {
        Array(expectedCatalogMediaTypes).sorted()
    }

    private func readingCatalogProviderUsesExpectedLane(_ provider: SableLibraryMetadataProvider) -> Bool {
        provider == .anilist
    }

    private func catalogCandidateMatchesExpectedLane(_ candidate: SableLibraryProviderCandidate) -> Bool {
        let expected = expectedCatalogMediaTypes
        guard !expected.isEmpty else { return true }
        let mediaType = normalizedCatalogCandidateMediaType(candidate)
        if expectedReadingCatalogLane == .lightNovel {
            return ["NOVEL", "LIGHT_NOVEL"].contains(mediaType)
        }
        if expectedReadingCatalogLane == .manga {
            return ["MANGA", "ONE_SHOT"].contains(mediaType)
        }
        if expected.contains("MANGA") {
            return ["MANGA", "NOVEL", "ONE_SHOT"].contains(mediaType)
        }
        if expected.contains("ANIME") {
            return ["TV", "TV_SHORT", "MOVIE", "SPECIAL", "OVA", "ONA", "MUSIC"].contains(mediaType)
        }
        return true
    }

    private var expectedReadingCatalogLane: ManualSearchReadingCatalogLane? {
        let pathTop = request.item.currentPath
            .split(separator: "/")
            .first
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        if pathTop == "light novels" || pathTop == "light novel" {
            return .lightNovel
        }
        if pathTop.map({ ["manga", "manhwa", "manhua", "oel", "comics", "comic books", "graphic novels"].contains($0) }) == true {
            return .manga
        }
        return nil
    }

    private func catalogCandidateIsReadingSide(_ candidate: SableLibraryProviderCandidate) -> Bool {
        ["MANGA", "NOVEL", "LIGHT_NOVEL", "ONE_SHOT"].contains(normalizedCatalogCandidateMediaType(candidate))
    }

    private func normalizedCatalogCandidateMediaType(_ candidate: SableLibraryProviderCandidate) -> String {
        candidate.mediaType?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: " ", with: "_") ?? ""
    }

    private func normalizedCandidateText(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\b(?:vol|volume|book|novel|light novel|edition)\b"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func tokenSimilarityForCandidate(_ lhs: String, _ rhs: String) -> Double {
        let left = Set(lhs.split(separator: " ").map(String.init).filter { $0.count > 1 })
        let right = Set(rhs.split(separator: " ").map(String.init).filter { $0.count > 1 })
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        let intersection = left.intersection(right).count
        return Double(intersection * 2) / Double(left.count + right.count)
    }

    private func yearHintForCandidate(in value: String) -> Int? {
        guard let range = value.range(of: #"(?:19|20)\d{2}"#, options: .regularExpression),
              let year = Int(value[range]) else {
            return nil
        }
        return year
    }

    private func isEnglishLanguageCode(_ value: String) -> Bool {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalized == "en" || normalized == "eng" || normalized == "english"
    }

    private func candidateSummary(_ candidate: SableLibraryProviderCandidate) -> String {
        var parts: [String] = [candidate.provider.displayName]
        if let year = candidate.year {
            parts.append("\(year)")
        }
        if let mediaType = candidate.mediaType, !mediaType.isEmpty {
            parts.append(mediaType)
        }
        if !candidate.authors.isEmpty {
            parts.append(candidate.authors.prefix(2).joined(separator: ", "))
        } else if !candidate.studios.isEmpty {
            parts.append(candidate.studios.prefix(2).joined(separator: ", "))
        }
        return parts.joined(separator: " • ")
    }

    private func candidateDisplayTitle(_ candidate: SableLibraryProviderCandidate) -> String {
        candidate.title
    }

    private func symbol(for candidate: SableLibraryProviderCandidate) -> String {
        switch candidate.provider {
        case .openLibrary, .ranobedb:
            "book.closed"
        case .mangabaka:
            "books.vertical"
        case .anilist, .myAnimeList:
            "sparkles"
        case .tmdb, .tvdb, .imdb, .tvmaze:
            "play.rectangle"
        case .wikidata:
            "network"
        case .local:
            "text.badge.checkmark"
        }
    }

    private func saveIfReady() {
        guard let parsedSourceID else { return }
        onSave(parsedSourceID.provider, parsedSourceID.value)
    }

    private func searchURL(provider: SableLibraryMetadataProvider, query: String) -> URL? {
        let cleanQuery = query
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanQuery.isEmpty else { return nil }

        let base: String
        let queryItems: [URLQueryItem]
        switch provider {
        case .mangabaka:
            base = "https://mangabaka.org/search"
            queryItems = [URLQueryItem(name: "q", value: cleanQuery)]
        case .ranobedb:
            base = "https://ranobedb.org/search"
            queryItems = [URLQueryItem(name: "q", value: cleanQuery)]
        case .openLibrary:
            base = "https://openlibrary.org/search"
            queryItems = [
                URLQueryItem(name: "q", value: "\(cleanQuery) language:eng"),
                URLQueryItem(name: "lang", value: "en")
            ]
        case .myAnimeList:
            return nil
        case .anilist:
            base = isReadingMetadataOperation ? "https://anilist.co/search/manga" : "https://anilist.co/search/anime"
            queryItems = [URLQueryItem(name: "search", value: cleanQuery)]
        case .tvmaze:
            base = "https://www.tvmaze.com/search"
            queryItems = [URLQueryItem(name: "q", value: cleanQuery)]
        case .wikidata:
            base = "https://www.wikidata.org/w/index.php"
            queryItems = [URLQueryItem(name: "search", value: cleanQuery)]
        case .tmdb:
            base = "https://www.themoviedb.org/search"
            queryItems = [URLQueryItem(name: "query", value: cleanQuery)]
        case .tvdb:
            base = "https://thetvdb.com/search"
            queryItems = [URLQueryItem(name: "query", value: cleanQuery)]
        case .imdb:
            base = "https://www.imdb.com/find/"
            queryItems = [URLQueryItem(name: "q", value: cleanQuery)]
        case .local:
            return nil
        }

        var components = URLComponents(string: base)
        components?.queryItems = queryItems
        return components?.url
    }
}

#if os(macOS)
private struct SableLibraryProviderThumbnail: View {
    @Environment(\.sableLibraryPalette) private var palette
    let url: URL
    let placeholderSymbol: String

    @State private var thumbnail: CGImage?

    var body: some View {
        Group {
            if let thumbnail {
                Image(decorative: thumbnail, scale: 1, orientation: .up)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: placeholderSymbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(palette.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(palette.accent.opacity(0.12))
                    .redacted(reason: .placeholder)
            }
        }
        .frame(width: 42, height: 58)
        .background(palette.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(palette.border, lineWidth: 1)
        }
        .accessibilityLabel("Provider cover")
        .task(id: url) {
            thumbnail = await Self.loadThumbnail(from: url)
        }
    }

    private nonisolated static func loadThumbnail(from url: URL) async -> CGImage? {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard !Task.isCancelled, data.count <= 12 * 1_024 * 1_024 else {
                return nil
            }
            if let response = response as? HTTPURLResponse,
               !(200..<300).contains(response.statusCode) {
                return nil
            }
            return await Task.detached(priority: .utility) {
                downsampledImage(from: data, maximumPixelSize: 160)
            }.value
        } catch {
            return nil
        }
    }

    private nonisolated static func downsampledImage(
        from data: Data,
        maximumPixelSize: Int
    ) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions)
    }
}
#endif

private enum ManualSearchReadingCatalogLane {
    case lightNovel
    case manga
}

private struct SableLibraryMangaBakaIDSheet: View {
    @Environment(\.sableLibraryPalette) private var palette
    let item: LibraryPlanItem
    let onCancel: () -> Void
    let onSave: (String) -> Void

    @State private var input: String

    init(
        item: LibraryPlanItem,
        onCancel: @escaping () -> Void,
        onSave: @escaping (String) -> Void
    ) {
        self.item = item
        self.onCancel = onCancel
        self.onSave = onSave
        _input = State(initialValue: item.manualMangaBakaID ?? "")
    }

    private var parsedID: String? {
        SableLibraryMangaBakaIDParser.id(from: input)
    }

    private var trimmedInput: String {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var validationMessage: String {
        if trimmedInput.isEmpty {
            return "Paste a MangaBaka series URL or numeric ID."
        }
        if let parsedID {
            return "Will use MangaBaka ID \(parsedID)."
        }
        return "Could not read a MangaBaka series ID. Use a numeric ID, series URL, or text like \"MangaBaka ID 12345\"."
    }

    private var validationSymbol: String {
        if parsedID != nil { return "checkmark.circle" }
        return trimmedInput.isEmpty ? "info.circle" : "exclamationmark.triangle"
    }

    private var validationColor: Color {
        if parsedID != nil { return palette.accent }
        return trimmedInput.isEmpty ? palette.textSecondary : palette.statusWarning
    }

    private var seriesName: String {
        URL(fileURLWithPath: item.currentPath).lastPathComponent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "number.circle")
                    .foregroundStyle(palette.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Give MangaBaka URL/ID")
                        .font(.headline)
                    Text(seriesName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            TextField("MangaBaka ID or URL", text: $input)
                .textFieldStyle(.roundedBorder)
                .onSubmit(saveIfReady)
                .accessibilityLabel("MangaBaka ID or URL")
                .accessibilityHint("Use a numeric MangaBaka series ID or a MangaBaka series URL.")

            Label(
                validationMessage,
                systemImage: validationSymbol
            )
            .font(.caption)
            .foregroundStyle(validationColor)
            .accessibilityLabel("MangaBaka ID validation")
            .accessibilityValue(validationMessage)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                Button("Use URL/ID", action: saveIfReady)
                    .keyboardShortcut(.defaultAction)
                    .disabled(parsedID == nil)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func saveIfReady() {
        guard let parsedID else { return }
        onSave(parsedID)
    }
}

private struct SableLibraryRanobeDBIDSheet: View {
    @Environment(\.sableLibraryPalette) private var palette
    let item: LibraryPlanItem
    let onCancel: () -> Void
    let onSave: (String) -> Void

    @State private var input: String

    init(
        item: LibraryPlanItem,
        onCancel: @escaping () -> Void,
        onSave: @escaping (String) -> Void
    ) {
        self.item = item
        self.onCancel = onCancel
        self.onSave = onSave
        _input = State(initialValue: item.manualRanobeDBID ?? "")
    }

    private var parsedID: String? {
        SableLibraryRanobeDBIDParser.id(from: input)
    }

    private var trimmedInput: String {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var validationMessage: String {
        if trimmedInput.isEmpty {
            return "Paste a RanobeDB series URL or numeric ID."
        }
        if let parsedID {
            return "Will use RanobeDB series ID \(parsedID)."
        }
        return "Could not read a RanobeDB series ID. Use a numeric ID, series URL, or text like \"rdb-6581\"."
    }

    private var validationSymbol: String {
        if parsedID != nil { return "checkmark.circle" }
        return trimmedInput.isEmpty ? "info.circle" : "exclamationmark.triangle"
    }

    private var validationColor: Color {
        if parsedID != nil { return palette.accent }
        return trimmedInput.isEmpty ? palette.textSecondary : palette.statusWarning
    }

    private var seriesName: String {
        URL(fileURLWithPath: item.currentPath).lastPathComponent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "number.circle")
                    .foregroundStyle(palette.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Give RanobeDB URL/ID")
                        .font(.headline)
                    Text(seriesName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            TextField("RanobeDB series ID or URL", text: $input)
                .textFieldStyle(.roundedBorder)
                .onSubmit(saveIfReady)
                .accessibilityLabel("RanobeDB series ID or URL")
                .accessibilityHint("Use a numeric RanobeDB series ID or a RanobeDB series URL.")

            Label(validationMessage, systemImage: validationSymbol)
                .font(.caption)
                .foregroundStyle(validationColor)
                .accessibilityLabel("RanobeDB ID validation")
                .accessibilityValue(validationMessage)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                Button("Use URL/ID", action: saveIfReady)
                    .keyboardShortcut(.defaultAction)
                    .disabled(parsedID == nil)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func saveIfReady() {
        guard let parsedID else { return }
        onSave(parsedID)
    }
}

private struct SableLibraryWorkflowPattern: Shape {
    let style: SableLibraryWorkflowPatternStyle

    func path(in rect: CGRect) -> Path {
        switch style {
        case .folders:
            folders(in: rect)
        case .magnifier:
            magnifiers(in: rect)
        case .checklist:
            checklist(in: rect)
        case .receipts:
            receipts(in: rect)
        }
    }

    private func folders(in rect: CGRect) -> Path {
        var path = Path()
        let rowHeight: CGFloat = 78
        var y = rect.minY + 34
        while y < rect.maxY {
            path.move(to: CGPoint(x: rect.minX - 20, y: y))
            path.addLine(to: CGPoint(x: rect.maxX + 20, y: y - 26))
            var x = rect.minX + 30
            while x < rect.maxX {
                path.move(to: CGPoint(x: x, y: y - 6))
                path.addLine(to: CGPoint(x: x + 18, y: y - 48))
                x += 78
            }
            y += rowHeight
        }
        return path
    }

    private func magnifiers(in rect: CGRect) -> Path {
        var path = Path()
        let spacing: CGFloat = 112
        var y = rect.minY + 22
        while y < rect.maxY + spacing {
            var x = rect.minX + 24
            while x < rect.maxX + spacing {
                let circleRect = CGRect(x: x, y: y, width: 34, height: 34)
                path.addEllipse(in: circleRect)
                path.move(to: CGPoint(x: x + 28, y: y + 28))
                path.addLine(to: CGPoint(x: x + 50, y: y + 50))
                x += spacing
            }
            y += spacing
        }
        return path
    }

    private func checklist(in rect: CGRect) -> Path {
        var path = Path()
        let spacing: CGFloat = 86
        var y = rect.minY + 30
        while y < rect.maxY {
            var x = rect.minX + 24
            while x < rect.maxX {
                path.move(to: CGPoint(x: x, y: y + 8))
                path.addLine(to: CGPoint(x: x + 8, y: y + 16))
                path.addLine(to: CGPoint(x: x + 24, y: y - 4))
                path.move(to: CGPoint(x: x + 38, y: y + 4))
                path.addLine(to: CGPoint(x: x + 94, y: y + 4))
                x += 150
            }
            y += spacing
        }
        return path
    }

    private func receipts(in rect: CGRect) -> Path {
        var path = Path()
        let width: CGFloat = 74
        let height: CGFloat = 92
        var y = rect.minY + 24
        var row = 0
        while y < rect.maxY + height {
            var x = rect.minX + CGFloat(row % 2) * 52
            while x < rect.maxX + width {
                let receipt = CGRect(x: x, y: y, width: width, height: height)
                path.addRoundedRect(in: receipt, cornerSize: CGSize(width: 6, height: 6))
                path.move(to: CGPoint(x: x + 12, y: y + 24))
                path.addLine(to: CGPoint(x: x + 58, y: y + 24))
                path.move(to: CGPoint(x: x + 12, y: y + 44))
                path.addLine(to: CGPoint(x: x + 46, y: y + 44))
                path.move(to: CGPoint(x: x + 12, y: y + 64))
                path.addLine(to: CGPoint(x: x + 54, y: y + 64))
                x += 138
            }
            row += 1
            y += 126
        }
        return path
    }
}
