//
//  SableLibraryPipelineModels.swift
//  Sable's Library
//

import Foundation

struct LibraryPipelineOptions: Sendable, Equatable {
    var cleanup: CleanupOptions
    var stages: LibraryPipelineStageOptions
    var intelligence: SableLibraryIntelligenceOptions
    var learning: SableLibraryLearningMemory

    init(
        cleanup: CleanupOptions,
        stages: LibraryPipelineStageOptions,
        intelligence: SableLibraryIntelligenceOptions,
        learning: SableLibraryLearningMemory = SableLibraryLearningMemory()
    ) {
        self.cleanup = cleanup
        self.stages = stages
        self.intelligence = intelligence
        self.learning = learning
    }
}

struct LibraryPipelineRun: Identifiable, Sendable {
    let id: UUID
    let root: URL
    var context: LibraryPipelineContext
    var nextAction: LibraryPipelineNextAction

    init(
        id: UUID = UUID(),
        root: URL,
        context: LibraryPipelineContext,
        nextAction: LibraryPipelineNextAction
    ) {
        self.id = id
        self.root = root
        self.context = context
        self.nextAction = nextAction
    }
}

struct LibraryPipelineTiming: Sendable, Equatable {
    var title: String
    var elapsedSeconds: TimeInterval
    var resultCount: Int?

    var summary: String {
        let result = resultCount.map { ", \($0) result(s)" } ?? ""
        return "\(title): \(SableLibraryWorkTiming.duration(elapsedSeconds))\(result)"
    }
}

struct LibraryPipelineContext: Sendable {
    let root: URL
    var options: LibraryPipelineOptions
    var inspectMode: LibraryPipelineInspectMode
    var inspection: LibraryInspection?
    var plan: LibraryPlan
    var timings: [LibraryPipelineTiming]

    init(root: URL, options: LibraryPipelineOptions, inspectMode: LibraryPipelineInspectMode = .full) {
        self.root = root
        self.options = options
        self.inspectMode = inspectMode
        self.inspection = nil
        self.plan = LibraryPlan(root: root, inspectMode: inspectMode)
        self.timings = []
    }

    var timingSummary: String? {
        guard !timings.isEmpty else { return nil }
        return timings.map(\.summary).joined(separator: "; ")
    }
}

enum LibraryPipelineInspectMode: Sendable, Equatable {
    case full
    case lightInventory
    case epubClinicInventory
    case stageDeepDive(LibraryPipelineStage)
    case quickVerify(previousStage: LibraryPipelineStage, changedPaths: [String], focusStage: LibraryPipelineStage?)

    var title: String {
        switch self {
        case .full:
            "Full inspect"
        case .lightInventory:
            "Light inventory"
        case .epubClinicInventory:
            "EPUB inventory"
        case .stageDeepDive(let stage):
            "\(stage.title) deep check"
        case .quickVerify:
            "Quick check"
        }
    }

    var focusStage: LibraryPipelineStage? {
        switch self {
        case .stageDeepDive(let stage):
            stage
        case .quickVerify(_, _, let focusStage):
            focusStage
        case .full, .lightInventory, .epubClinicInventory:
            nil
        }
    }

    var isEPUBClinicVerification: Bool {
        switch self {
        case .quickVerify(let previousStage, _, let focusStage):
            previousStage == .epubClinic || focusStage == .epubClinic
        case .full, .lightInventory, .epubClinicInventory, .stageDeepDive:
            false
        }
    }

    var isEPUBClinicPass: Bool {
        switch self {
        case .epubClinicInventory:
            true
        case .stageDeepDive(let stage):
            stage == .epubClinic
        case .quickVerify(let previousStage, _, let focusStage):
            previousStage == .epubClinic || focusStage == .epubClinic
        case .full, .lightInventory:
            false
        }
    }

    var runsMetadataScan: Bool {
        switch self {
        case .full:
            true
        case .stageDeepDive(let stage), .quickVerify(_, _, let stage?):
            stage.usesComicInfoApplyEngine || stage == .canonicalFolders || stage == .canonicalFiles
        case .lightInventory, .epubClinicInventory, .quickVerify:
            false
        }
    }

    var runsMissingNumberScan: Bool {
        switch self {
        case .full:
            true
        case .stageDeepDive(let stage), .quickVerify(_, _, let stage?):
            stage == .canonicalFiles
        case .lightInventory, .epubClinicInventory, .quickVerify:
            false
        }
    }

    var runsDuplicateScan: Bool {
        switch self {
        case .full:
            true
        case .stageDeepDive(let stage), .quickVerify(_, _, let stage?):
            stage == .duplicateReview
        case .lightInventory, .epubClinicInventory, .quickVerify:
            false
        }
    }

    var wakesEPUBRepairSpecialists: Bool {
        switch self {
        case .full:
            true
        case .stageDeepDive(let stage), .quickVerify(_, _, let stage?):
            stage == .epubClinic
        case .lightInventory, .epubClinicInventory, .quickVerify:
            false
        }
    }

    var usesFocusedEPUBClinicInventory: Bool {
        switch self {
        case .epubClinicInventory:
            true
        case .stageDeepDive(let stage):
            stage == .epubClinic
        case .quickVerify(let previousStage, _, let focusStage):
            previousStage == .epubClinic || focusStage == .epubClinic
        case .full, .lightInventory:
            false
        }
    }

    var quickVerifyChangedPaths: [String]? {
        guard case let .quickVerify(_, changedPaths, _) = self else { return nil }
        return changedPaths
    }
}

struct LibraryInspection: Sendable, Equatable {
    var inspectMode: LibraryPipelineInspectMode
    var rootPath: String
    var fileCount: Int
    var folderCount: Int
    var bookFileCount: Int
    var videoFileCount: Int
    var packageBookCount: Int
    var seriesCount: Int
    var videoSeriesCount: Int
    var looseFileCount: Int
    var comicInfoCount: Int
    var animeInfoCount: Int
    var missingComicInfoCount: Int
    var missingAnimeInfoCount: Int
    var duplicateGroupCount: Int
    var metadataCandidateCount: Int
    var missingNumberCandidateCount: Int
    var sourceMetadataTermKeys: [String]
    var fileTypeCounts: [String: Int]
    var series: [LibrarySeriesSnapshot]
    var books: [LibraryBookSnapshot]
    var videoSeries: [LibraryVideoSeriesSnapshot]
    var videos: [LibraryVideoSnapshot]
    var metadataCandidates: [LibraryInspectionMetadataCandidate]
    var missingNumberCandidates: [LibraryInspectionPathIssue]
    var duplicateCandidates: [LibraryInspectionDuplicateGroup]
    var comicInfoSeriesPaths: [String]
    var missingComicInfoSeriesPaths: [String]
    var animeInfoSeriesPaths: [String]
    var missingAnimeInfoSeriesPaths: [String]
    var notes: [String]
    var verification: LibraryPipelineVerification?

    static func empty(root: URL) -> LibraryInspection {
        LibraryInspection(
            inspectMode: .full,
            rootPath: root.path,
            fileCount: 0,
            folderCount: 0,
            bookFileCount: 0,
            videoFileCount: 0,
            packageBookCount: 0,
            seriesCount: 0,
            videoSeriesCount: 0,
            looseFileCount: 0,
            comicInfoCount: 0,
            animeInfoCount: 0,
            missingComicInfoCount: 0,
            missingAnimeInfoCount: 0,
            duplicateGroupCount: 0,
            metadataCandidateCount: 0,
            missingNumberCandidateCount: 0,
            sourceMetadataTermKeys: [],
            fileTypeCounts: [:],
            series: [],
            books: [],
            videoSeries: [],
            videos: [],
            metadataCandidates: [],
            missingNumberCandidates: [],
            duplicateCandidates: [],
            comicInfoSeriesPaths: [],
            missingComicInfoSeriesPaths: [],
            animeInfoSeriesPaths: [],
            missingAnimeInfoSeriesPaths: [],
            notes: [],
            verification: nil
        )
    }
}

extension LibraryInspection {
    nonisolated func scoped(
        to window: SableLibraryModifiedWindow,
        for stage: LibraryPipelineStage,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> LibraryInspection {
        guard window != .all,
              stage != .inspect,
              stage != .reviewApply,
              stage != .epubClinic else {
            return self
        }

        let scopedBooks = books.filter {
            window.includes(modificationDate: $0.modificationDate, now: now, calendar: calendar)
        }
        let scopedVideos = videos.filter {
            window.includes(modificationDate: $0.modificationDate, now: now, calendar: calendar)
        }
        let scopedBookPaths = Set(scopedBooks.map(\.path))
        let scopedVideoPaths = Set(scopedVideos.map(\.path))

        func containsRecentBook(_ seriesPath: String) -> Bool {
            scopedBooks.contains { snapshot in
                snapshot.seriesID == seriesPath
                    || snapshot.path.hasPrefix(seriesPath + "/")
            }
        }

        func containsRecentVideo(_ seriesPath: String) -> Bool {
            scopedVideos.contains { snapshot in
                snapshot.seriesID == seriesPath
                    || snapshot.path.hasPrefix(seriesPath + "/")
            }
        }

        let scopedSeries = series.filter { containsRecentBook($0.path) }
        let scopedVideoSeries = videoSeries.filter { containsRecentVideo($0.path) }
        let scopedSeriesPaths = Set(scopedSeries.map(\.path))
        let scopedVideoSeriesPaths = Set(scopedVideoSeries.map(\.path))
        let scopedMediaPaths = scopedBookPaths.union(scopedVideoPaths)

        var result = self
        result.books = scopedBooks
        result.videos = scopedVideos

        // Raw intake still needs every established series as a destination index.
        if stage != .prepareRawFiles {
            result.series = scopedSeries
            result.videoSeries = scopedVideoSeries
        }

        result.bookFileCount = scopedBooks.count
        result.videoFileCount = scopedVideos.count
        result.packageBookCount = scopedBooks.filter(\.isPackageBook).count
        result.seriesCount = scopedSeries.count
        result.videoSeriesCount = scopedVideoSeries.count
        result.looseFileCount = scopedBooks.filter { ($0.seriesID ?? "").isEmpty }.count
            + scopedVideos.filter { ($0.seriesID ?? "").isEmpty }.count
        result.comicInfoSeriesPaths = comicInfoSeriesPaths.filter(scopedSeriesPaths.contains)
        result.missingComicInfoSeriesPaths = missingComicInfoSeriesPaths.filter(scopedSeriesPaths.contains)
        result.animeInfoSeriesPaths = animeInfoSeriesPaths.filter(scopedVideoSeriesPaths.contains)
        result.missingAnimeInfoSeriesPaths = missingAnimeInfoSeriesPaths.filter(scopedVideoSeriesPaths.contains)
        result.comicInfoCount = result.comicInfoSeriesPaths.count
        result.missingComicInfoCount = result.missingComicInfoSeriesPaths.count
        result.animeInfoCount = result.animeInfoSeriesPaths.count
        result.missingAnimeInfoCount = result.missingAnimeInfoSeriesPaths.count
        result.missingNumberCandidates = missingNumberCandidates.filter { candidate in
            scopedMediaPaths.contains(candidate.path)
        }
        result.missingNumberCandidateCount = result.missingNumberCandidates.count
        result.duplicateCandidates = duplicateCandidates.filter { candidate in
            candidate.paths.contains(where: scopedMediaPaths.contains)
        }
        result.duplicateGroupCount = result.duplicateCandidates.count
        result.fileTypeCounts = Dictionary(
            grouping: scopedBooks.map(\.fileExtension) + scopedVideos.map(\.fileExtension),
            by: { $0.isEmpty ? "__no_extension__" : $0 }
        ).mapValues(\.count)
        result.notes.append("\(stage.title) is limited to \(window.libraryScopeDescription).")
        return result
    }

    var failureNote: String? {
        notes.first { $0.hasPrefix("Inspection could not finish:") }
    }

    var needsFolderAccess: Bool {
        failureNote?.localizedCaseInsensitiveContains("cannot be read") == true
    }

    var readingTypeCounts: [LibraryInspectionTypeCount] {
        countedTypeRows(
            series.map { Self.readingTypeLabel(for: $0) },
            order: ["Manga", "Manhwa", "Manhua", "Light novels", "OEL", "Other", "Unknown"]
        )
    }

    var watchingTypeCounts: [LibraryInspectionTypeCount] {
        countedTypeRows(
            videoSeries.map { Self.watchingTypeLabel(for: $0) },
            order: ["TV", "Movies", "Other videos", "Unknown"]
        )
    }

    var displayFileTypeCounts: [LibraryInspectionTypeCount] {
        var counts: [String: Int] = [:]
        var otherCount = 0

        for (rawExtension, count) in fileTypeCounts {
            if let label = Self.displayFileTypeLabel(for: rawExtension) {
                counts[label, default: 0] += count
            } else {
                otherCount += count
            }
        }

        if otherCount > 0 {
            counts["Other file types", default: 0] += otherCount
        }

        return counts
            .map { LibraryInspectionTypeCount(label: $0.key, count: $0.value) }
            .sorted { first, second in
                if first.count != second.count {
                    return first.count > second.count
                }
                return first.label < second.label
            }
    }

    static func fileTypeCountKey(for url: URL) -> String {
        let ext = url.pathExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return ext.isEmpty ? noExtensionFileTypeKey : ext
    }

    private static let noExtensionFileTypeKey = "__no_extension__"

    private static let visibleFileTypeExtensions: Set<String> = [
        "7z", "aac", "apk", "app", "ass", "avi", "azw3", "cb7", "cbr", "cbt", "cbz",
        "command", "csv", "djvu", "dmg", "doc", "docx", "epub", "flac", "gif", "gz",
        "heic", "html", "ics", "jpeg", "jpg", "json", "jsonl", "m4a", "m4v", "md",
        "mkv", "mobi", "mov", "mp3", "mp4", "ogg", "overlay", "package", "pages",
        "pdf", "png", "ppt", "pptx", "py", "rar", "rtf", "srt", "svg", "tar", "txt",
        "vtt", "wav", "webm", "webp", "xls", "xlsx", "xml", "zip"
    ]

    private static func displayFileTypeLabel(for rawExtension: String) -> String? {
        let cleaned = rawExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !cleaned.isEmpty else { return "No extension" }
        if cleaned == noExtensionFileTypeKey { return "No extension" }
        guard visibleFileTypeExtensions.contains(cleaned) else { return nil }
        return cleaned.uppercased()
    }

    private func countedTypeRows(_ labels: [String], order: [String]) -> [LibraryInspectionTypeCount] {
        let counts = Dictionary(grouping: labels, by: { $0 }).mapValues(\.count)
        return counts
            .map { LibraryInspectionTypeCount(label: $0.key, count: $0.value) }
            .sorted { first, second in
                let firstIndex = order.firstIndex(of: first.label) ?? order.count
                let secondIndex = order.firstIndex(of: second.label) ?? order.count
                if firstIndex != secondIndex {
                    return firstIndex < secondIndex
                }
                return first.label < second.label
            }
    }

    static func readingTypeLabel(for series: LibrarySeriesSnapshot) -> String {
        let namingPolicy = SableLibraryNamingPolicy()
        let candidates = [
            series.mediaType,
            series.localTitle,
            series.preferredTitle,
            series.displayName,
            series.path
        ].compactMap { $0 }

        for candidate in candidates {
            let normalized = namingPolicy.normalizedMediaType(candidate)
            if normalized != "Unknown" {
                return displayReadingType(normalized)
            }
            if let hinted = namingPolicy.mediaTypeHint(in: candidate) {
                return displayReadingType(hinted)
            }
        }

        let path = series.path.lowercased()
        if path == "light novels" || path.hasPrefix("light novels/") {
            return "Light novels"
        }
        if path == "manga" || path.hasPrefix("manga/") {
            return "Manga"
        }
        if path == "manhwa" || path.hasPrefix("manhwa/") {
            return "Manhwa"
        }
        if path == "manhua" || path.hasPrefix("manhua/") {
            return "Manhua"
        }
        if path == "oel" || path.hasPrefix("oel/") {
            return "OEL"
        }

        return "Unknown"
    }

    static func watchingTypeLabel(for series: LibraryVideoSeriesSnapshot) -> String {
        if let mediaType = series.mediaType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            switch mediaType {
            case "animetv", "anime tv", "ova", "ona", "special", "specials":
                return "TV"
            case "animemovie", "anime movie":
                return "Movies"
            case "tvshow", "tv show", "tv":
                return "TV"
            case "movie":
                return "Movies"
            default:
                break
            }
        }

        let path = series.path.lowercased()
        if path == "tv" || path.hasPrefix("tv/")
            || path == "anime tv" || path.hasPrefix("anime tv/")
            || path == "tv shows" || path.hasPrefix("tv shows/") {
            return "TV"
        }
        if path == "anime movies" || path.hasPrefix("anime movies/") {
            return "Movies"
        }
        if path == "movies" || path.hasPrefix("movies/") {
            return "Movies"
        }
        if path == "other videos" || path.hasPrefix("other videos/") {
            return "Other videos"
        }

        return "Unknown"
    }

    private static func displayReadingType(_ mediaType: String) -> String {
        switch mediaType {
        case "Manga", "Manhwa", "Manhua", "OEL", "Other":
            return mediaType
        case "Novel":
            return "Light novels"
        default:
            return "Unknown"
        }
    }
}

struct LibraryInspectionTypeCount: Identifiable, Sendable, Equatable {
    var id: String { label }
    var label: String
    var count: Int
}

struct LibraryPipelineVerification: Sendable, Equatable {
    var previousStage: LibraryPipelineStage
    var checkedPathCount: Int
    var missingPathCount: Int
    var changedPathCount: Int
    var didCheckEpubPackages: Bool
    var remainingEpubPackageCount: Int
    var message: String

    var needsAttention: Bool {
        missingPathCount > 0 || (didCheckEpubPackages && remainingEpubPackageCount > 0)
    }
}

struct LibrarySeriesSnapshot: Identifiable, Sendable, Equatable {
    let id: String
    var path: String
    var displayName: String
    var localTitle: String?
    var preferredTitle: String?
    var trustedProviderTitles: [String] = []
    var mediaType: String?
    var shelfDescription: String? = nil
    var volumeDescriptions: [String] = []
    var genres: [String] = []
    var themes: [String] = []
    var tags: [String] = []
    var tagRecords: [SableLibraryShelfTagRecord] = []
    var providerNeighborSignals: [String] = []
    var contentWarnings: [String] = []
    var year: Int?
    var primarySourceID: SableLibrarySourceID?
    var identityGraph: SableLibraryIdentityGraph?
    var sourceFreshness: [SableLibraryProviderFreshness] = []
    var localFileSnapshotChanged: Bool = false
    var finalVolume: Int?
    var localBookCount: Int
    var localHighestVolume: Int?
    var comicInfoSource: String?
    var comicInfoLastChecked: String?
    var mangaBakaExpectedType: String?
    var mangaBakaTypeMatched: Bool?
    var missingMangaBakaV2Metadata: Bool = false
    var unavailableMetadataProviders: [SableLibraryMetadataProvider] = []
    var providerCandidateReviews: [SableLibraryProviderCandidateReview] = []
    var hasComicInfo: Bool
}

struct SableLibraryProviderCandidateReview: Sendable, Equatable {
    enum Status: String, Sendable {
        case candidate
        case noMatch = "no_match"
    }

    var provider: SableLibraryMetadataProvider
    var status: Status
    var confidenceScore: Double
    var title: String?
    var year: Int?
    var mediaType: String?
    var sourceID: SableLibrarySourceID?
    var checkedAt: String?
    var schemaVersion: Int = 0
}

struct LibraryBookSnapshot: Identifiable, Sendable, Equatable {
    let id: String
    var path: String
    var fileName: String
    var fileExtension: String
    var seriesID: String?
    var isPackageBook: Bool
    var modificationDate: Date? = nil
}

struct LibraryVideoSeriesSnapshot: Identifiable, Sendable, Equatable {
    let id: String
    var path: String
    var displayName: String
    var localTitle: String?
    var preferredTitle: String?
    var mediaType: String?
    var year: Int?
    var primarySourceID: SableLibrarySourceID?
    var identityGraph: SableLibraryIdentityGraph?
    var sourceFreshness: [SableLibraryProviderFreshness] = []
    var localFileSnapshotChanged: Bool = false
    var localVideoCount: Int
    var animeInfoSource: String?
    var animeInfoLastChecked: String?
    var unavailableMetadataProviders: [SableLibraryMetadataProvider] = []
    var providerCandidateReviews: [SableLibraryProviderCandidateReview] = []
    var hasAnimeInfo: Bool
}

struct LibraryVideoSnapshot: Identifiable, Sendable, Equatable {
    let id: String
    var path: String
    var fileName: String
    var fileExtension: String
    var seriesID: String?
    var modificationDate: Date? = nil
}

struct SableLibraryVolumeConflict: Sendable, Equatable {
    var finalVolume: Int
    var localHighestVolume: Int
}

struct LibraryInspectionMetadataCandidate: Identifiable, Sendable, Equatable {
    var id: String { term }
    var term: String
    var count: Int
    var examples: [String]
}

struct LibraryInspectionPathIssue: Identifiable, Sendable, Equatable {
    var id: String { path }
    var path: String
    var note: String
}

struct LibraryInspectionDuplicateGroup: Identifiable, Sendable, Equatable {
    var id: String { fingerprint }
    var fingerprint: String
    var kind: String
    var paths: [String]
    var suggestedKeeperPath: String?
    var note: String
}

struct LibraryPlan: Identifiable, Sendable, Equatable {
    let id: UUID
    let rootPath: String
    var inspectMode: LibraryPipelineInspectMode
    var groups: [LibraryPlanGroup]

    init(
        id: UUID = UUID(),
        root: URL,
        inspectMode: LibraryPipelineInspectMode = .full,
        groups: [LibraryPlanGroup] = []
    ) {
        self.id = id
        self.rootPath = root.path
        self.inspectMode = inspectMode
        self.groups = groups
    }

    var items: [LibraryPlanItem] {
        groups.flatMap(\.items)
    }

    var activeItems: [LibraryPlanItem] {
        items.filter { !$0.isSkippedForPass }
    }

    var skippedItems: [LibraryPlanItem] {
        items.filter(\.isSkippedForPass)
    }

    var unresolvedItems: [LibraryPlanItem] {
        activeItems.filter(\.needsDecisionReview)
    }

    var checkedItems: [LibraryPlanItem] {
        items.filter { $0.decision == .checked }
    }

    mutating func append(contentsOf newGroups: [LibraryPlanGroup]) {
        guard !newGroups.isEmpty else { return }
        groups.append(contentsOf: newGroups)
    }

    mutating func replaceGroups(
        for refreshedStages: Set<LibraryPipelineStage>,
        with refreshedPlan: LibraryPlan
    ) {
        guard !refreshedStages.isEmpty else { return }

        let existingGroups = groups.filter { refreshedStages.contains($0.stage) }
        let existingGroupIDs = Dictionary(
            existingGroups.map { (Self.groupRefreshKey($0), $0.id) },
            uniquingKeysWith: { first, _ in first }
        )
        let existingItems = Dictionary(
            existingGroups.flatMap(\.items).map { (Self.itemRefreshKey($0), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let refreshedGroups = refreshedPlan.groups
            .filter { refreshedStages.contains($0.stage) }
            .map { group -> LibraryPlanGroup in
                let items = group.items.map { item in
                    guard let existing = existingItems[Self.itemRefreshKey(item)] else {
                        return item
                    }
                    return Self.refreshedItem(item, preservingReviewStateFrom: existing)
                }
                return LibraryPlanGroup(
                    id: existingGroupIDs[Self.groupRefreshKey(group)] ?? group.id,
                    stage: group.stage,
                    title: group.title,
                    summary: group.summary,
                    reviewPrompt: group.reviewPrompt,
                    examples: group.examples,
                    quickVerifyAfterApply: group.quickVerifyAfterApply,
                    items: items
                )
            }

        var groupsByStage = Dictionary(grouping: groups.filter { !refreshedStages.contains($0.stage) }, by: \.stage)
        for group in refreshedGroups {
            groupsByStage[group.stage, default: []].append(group)
        }
        groups = LibraryPipelineStage.allCases.flatMap { groupsByStage[$0] ?? [] }
    }

    mutating func clearCheckedItems(
        stage: LibraryPipelineStage,
        itemIDs: Set<UUID>
    ) {
        guard !itemIDs.isEmpty else { return }
        groups = groups.map { group in
            guard group.stage == stage else { return group }
            var updatedGroup = group
            updatedGroup.items = group.items.map { item in
                guard itemIDs.contains(item.id), item.decision == .checked else {
                    return item
                }
                var updatedItem = item
                updatedItem.decision = .unchecked
                return updatedItem
            }
            return updatedGroup
        }
    }

    private static func groupRefreshKey(_ group: LibraryPlanGroup) -> String {
        "\(group.stage.rawValue)|\(group.title)"
    }

    private static func itemRefreshKey(_ item: LibraryPlanItem) -> String {
        let proposedPath = item.proposedPath ?? ""
        let coverLanguage = item.requestedCoverLanguages.joined(separator: ",")
        return "\(item.stage.rawValue)|\(item.operation.rawValue)|\(item.currentPath)|\(proposedPath)|\(coverLanguage)"
    }

    private static func refreshedItem(
        _ item: LibraryPlanItem,
        preservingReviewStateFrom existing: LibraryPlanItem
    ) -> LibraryPlanItem {
        let refreshedDecision: LibraryPlanDecision
        if item.stage == .covers,
           item.reviewTags.contains("cover-manifest-present")
            || item.reviewTags.contains("cover-manifest-unproven-no-result")
            || item.reviewTags.contains("cover-manifest-below-clinic-quality") {
            refreshedDecision = .unchecked
        } else {
            refreshedDecision = existing.decision
        }

        return LibraryPlanItem(
            id: existing.id,
            stage: item.stage,
            operation: item.operation,
            currentPath: item.currentPath,
            proposedPath: item.proposedPath,
            reason: item.reason,
            confidence: item.confidence,
            safety: item.safety,
            decision: refreshedDecision,
            requiresReview: item.requiresReview,
            usedNetworkData: item.usedNetworkData,
            metadataProviders: item.metadataProviders,
            confidenceExplanation: item.confidenceExplanation,
            correctionOptions: item.correctionOptions,
            manualMangaBakaID: existing.manualMangaBakaID ?? item.manualMangaBakaID,
            manualRanobeDBID: existing.manualRanobeDBID ?? item.manualRanobeDBID,
            manualSourceIDs: existing.manualSourceIDs.isEmpty ? item.manualSourceIDs : existing.manualSourceIDs,
            manualCoverSeriesMatches: existing.manualCoverSeriesMatches.isEmpty
                ? item.manualCoverSeriesMatches
                : existing.manualCoverSeriesMatches,
            coverSearchTitles: item.coverSearchTitles,
            rejectionReason: existing.rejectionReason,
            hasRetriedAfterFeedback: existing.hasRetriedAfterFeedback,
            reviewTags: item.reviewTags,
            receipt: item.receipt
        )
    }
}

struct LibraryPlanGroup: Identifiable, Sendable, Equatable {
    let id: UUID
    var stage: LibraryPipelineStage
    var title: String
    var summary: String
    var reviewPrompt: String
    var examples: [LibraryPlanExample]
    var quickVerifyAfterApply: Bool
    var items: [LibraryPlanItem]

    init(
        id: UUID = UUID(),
        stage: LibraryPipelineStage,
        title: String,
        summary: String,
        reviewPrompt: String = "",
        examples: [LibraryPlanExample] = [],
        quickVerifyAfterApply: Bool = true,
        items: [LibraryPlanItem]
    ) {
        self.id = id
        self.stage = stage
        self.title = title
        self.summary = summary
        self.reviewPrompt = reviewPrompt
        self.examples = examples
        self.quickVerifyAfterApply = quickVerifyAfterApply
        self.items = items
    }
}

struct LibraryPlanExample: Identifiable, Sendable, Equatable {
    let id: UUID
    var title: String
    var before: String
    var after: String?
    var reason: String
    var details: [LibraryPlanExampleDetail]

    init(
        id: UUID = UUID(),
        title: String,
        before: String,
        after: String?,
        reason: String,
        details: [LibraryPlanExampleDetail] = []
    ) {
        self.id = id
        self.title = title
        self.before = before
        self.after = after
        self.reason = reason
        self.details = details
    }
}

struct LibraryPlanExampleDetail: Identifiable, Sendable, Equatable {
    var id: String { label }
    var label: String
    var value: String
    var symbol: String
}

struct LibraryPlanItem: Identifiable, Sendable, Equatable {
    let id: UUID
    var stage: LibraryPipelineStage
    var operation: LibraryPlanOperation
    var currentPath: String
    var proposedPath: String?
    var reason: String
    var confidence: LibraryPlanConfidence
    var safety: LibraryPlanSafety
    var decision: LibraryPlanDecision
    var requiresReview: Bool
    var usedNetworkData: Bool
    var metadataProviders: [SableLibraryMetadataProvider]
    var confidenceExplanation: String
    var correctionOptions: [LibraryPlanCorrectionOption]
    var manualMangaBakaID: String?
    var manualRanobeDBID: String?
    var manualSourceIDs: [SableLibrarySourceID]
    var manualCoverSeriesMatches: [SableLibraryManualCoverSeriesMatch]
    var coverSearchTitles: [String]
    var rejectionReason: LibraryPlanRejectionReason?
    var hasRetriedAfterFeedback: Bool
    var reviewTags: [String]
    var receipt: String

    init(
        id: UUID = UUID(),
        stage: LibraryPipelineStage,
        operation: LibraryPlanOperation,
        currentPath: String,
        proposedPath: String?,
        reason: String,
        confidence: LibraryPlanConfidence,
        safety: LibraryPlanSafety,
        decision: LibraryPlanDecision,
        requiresReview: Bool,
        usedNetworkData: Bool = false,
        metadataProviders: [SableLibraryMetadataProvider] = [],
        confidenceExplanation: String = "",
        correctionOptions: [LibraryPlanCorrectionOption] = [],
        manualMangaBakaID: String? = nil,
        manualRanobeDBID: String? = nil,
        manualSourceIDs: [SableLibrarySourceID] = [],
        manualCoverSeriesMatches: [SableLibraryManualCoverSeriesMatch] = [],
        coverSearchTitles: [String] = [],
        rejectionReason: LibraryPlanRejectionReason? = nil,
        hasRetriedAfterFeedback: Bool = false,
        reviewTags: [String] = [],
        receipt: String = ""
    ) {
        self.id = id
        self.stage = stage
        self.operation = operation
        self.currentPath = currentPath
        self.proposedPath = proposedPath
        self.reason = reason
        self.confidence = confidence
        self.safety = safety
        self.decision = decision
        self.requiresReview = requiresReview
        self.usedNetworkData = usedNetworkData
        self.metadataProviders = metadataProviders
        self.confidenceExplanation = confidenceExplanation
        self.correctionOptions = correctionOptions
        self.manualMangaBakaID = manualMangaBakaID
        self.manualRanobeDBID = manualRanobeDBID
        self.manualSourceIDs = manualSourceIDs
        self.manualCoverSeriesMatches = manualCoverSeriesMatches
        self.coverSearchTitles = coverSearchTitles
        self.rejectionReason = rejectionReason
        self.hasRetriedAfterFeedback = hasRetriedAfterFeedback
        self.reviewTags = reviewTags
        self.receipt = receipt
    }
}

extension LibraryPlanItem {
    var requestedCoverLanguages: [String] {
        let taggedLanguages = [
            reviewTags.contains("cover-language-jp") ? "jp" : nil,
            reviewTags.contains("cover-language-en") ? "en" : nil
        ].compactMap { $0 }
        return taggedLanguages.isEmpty ? ["jp", "en"] : taggedLanguages
    }

    var canManuallyMatchCoverSeries: Bool {
        stage == .covers
            && (
                reviewTags.contains("cover-manifest-incomplete")
                    || reviewTags.contains("cover-manifest-no-result")
                    || reviewTags.contains("cover-manifest-conflict")
                    || reviewTags.contains("cover-manifest-unverified")
                    || reviewTags.contains("cover-manifest-needs-store-check")
                    || reviewTags.contains("cover-manifest-unproven-no-result")
                    || reviewTags.contains("cover-manifest-below-clinic-quality")
            )
    }
}

enum SableLibraryPlanSearch {
    static func matches(_ item: LibraryPlanItem, query: String) -> Bool {
        SableLibrarySearchText.matches([
            item.stage.title,
            item.operation.rawValue,
            item.currentPath,
            item.proposedPath ?? "",
            item.reason,
            item.confidence.rawValue,
            item.safety.rawValue,
            item.decision.rawValue,
            item.metadataProviders.map(\.rawValue).joined(separator: " "),
            item.confidenceExplanation,
            item.manualMangaBakaID ?? "",
            item.manualRanobeDBID ?? "",
            item.manualSourceIDs.map(\.stableKey).joined(separator: " "),
            item.manualCoverSeriesMatches.map { "\($0.source.displayName) \($0.title) \($0.providerID)" }.joined(separator: " "),
            item.coverSearchTitles.joined(separator: " "),
            item.rejectionReason?.option.title ?? "",
            item.rejectionReason?.note ?? "",
            item.reviewTags.joined(separator: " "),
            item.receipt
        ], query: query)
    }
}

enum SableLibraryInspectionSearch {
    static func matches(_ series: LibrarySeriesSnapshot, query: String) -> Bool {
        SableLibrarySearchText.matches([
            series.path,
            series.displayName,
            series.localTitle ?? "",
            series.preferredTitle ?? "",
            series.mediaType ?? "",
            LibraryInspection.readingTypeLabel(for: series),
            series.hasComicInfo ? "has ComicInfo" : "missing ComicInfo",
            series.primarySourceID.map { "\($0.provider.rawValue) \($0.value)" } ?? "",
            series.comicInfoSource ?? ""
        ], query: query)
    }

    static func matches(_ series: LibraryVideoSeriesSnapshot, query: String) -> Bool {
        SableLibrarySearchText.matches([
            series.path,
            series.displayName,
            series.localTitle ?? "",
            series.preferredTitle ?? "",
            series.mediaType ?? "",
            LibraryInspection.watchingTypeLabel(for: series),
            series.hasAnimeInfo ? "has AnimeInfo" : "missing AnimeInfo",
            series.primarySourceID.map { "\($0.provider.rawValue) \($0.value)" } ?? "",
            series.animeInfoSource ?? ""
        ], query: query)
    }
}

enum SableLibrarySearchText {
    static func matches(_ fields: [String], query: String) -> Bool {
        let terms = searchTerms(in: query)
        guard !terms.isEmpty else { return true }

        let haystack = normalized(fields.joined(separator: " "))
        return terms.allSatisfy { haystack.contains($0) }
    }

    private static func searchTerms(in query: String) -> [String] {
        normalized(query)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

enum SableLibraryRanobeDBIDParser {
    nonisolated static func id(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.allSatisfy(\.isNumber) {
            return trimmed
        }

        if let components = URLComponents(string: trimmed) {
            for item in components.queryItems ?? [] {
                let key = item.name.lowercased()
                if ["id", "series_id", "seriesid", "ranobedb_id", "ranobedbid", "rdb"].contains(key),
                   let value = item.value?.trimmingCharacters(in: .whitespacesAndNewlines),
                   value.allSatisfy(\.isNumber),
                   !value.isEmpty {
                    return value
                }
            }

            if let url = components.url {
                let path = url.pathComponents.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
                if let seriesIndex = path.firstIndex(where: { $0.lowercased() == "series" }),
                   path.indices.contains(seriesIndex + 1) {
                    let value = path[seriesIndex + 1]
                    if value.allSatisfy(\.isNumber), !value.isEmpty {
                        return value
                    }
                }

                for component in path.reversed() {
                    if component.allSatisfy(\.isNumber), !component.isEmpty {
                        return component
                    }
                }
            }
        }

        if let labeledRange = trimmed.range(
            of: #"(?i)\b(?:ranobedb|ranobe|rdb\s*)?(?:series\s*)?id\b\D{0,12}\d+"#,
            options: .regularExpression
        ) {
            let labeledText = trimmed[labeledRange]
            if let idRange = labeledText.range(of: #"\d+"#, options: .regularExpression) {
                return String(labeledText[idRange])
            }
        }

        if let rdbToken = trimmed.range(of: #"(?i)\{rdb-(\d+)\}"#, options: .regularExpression) {
            let text = trimmed[rdbToken]
            if let idRange = text.range(of: #"\d+"#, options: .regularExpression) {
                return String(text[idRange])
            }
        }

        return nil
    }
}

enum SableLibraryMangaBakaIDParser {
    nonisolated static func id(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.allSatisfy(\.isNumber) {
            return trimmed
        }

        if let components = URLComponents(string: trimmed) {
            for item in components.queryItems ?? [] {
                let key = item.name.lowercased()
                if ["id", "series_id", "seriesid", "mangabaka_id", "mangabakaid"].contains(key),
                   let value = item.value?.trimmingCharacters(in: .whitespacesAndNewlines),
                   value.allSatisfy(\.isNumber),
                   !value.isEmpty {
                    return value
                }
            }

            if let url = components.url {
                for component in url.pathComponents.reversed() {
                    let clean = component.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    if clean.allSatisfy(\.isNumber), !clean.isEmpty {
                        return clean
                    }
                }
            }
        }

        if let labeledRange = trimmed.range(
            of: #"(?i)\b(?:mangabaka\s*)?(?:series\s*)?id\b\D{0,12}\d+"#,
            options: .regularExpression
        ) {
            let labeledText = trimmed[labeledRange]
            if let idRange = labeledText.range(of: #"\d+"#, options: .regularExpression) {
                return String(labeledText[idRange])
            }
        }
        return nil
    }
}

extension LibraryPlanGroup {
    var activeItems: [LibraryPlanItem] {
        items.filter { !$0.isSkippedForPass }
    }

    var skippedItems: [LibraryPlanItem] {
        items.filter(\.isSkippedForPass)
    }

    var unresolvedItems: [LibraryPlanItem] {
        activeItems.filter(\.needsDecisionReview)
    }

    var isManualProviderGapReviewGroup: Bool {
        if title.hasPrefix("Missing Providers -")
            || title.hasPrefix("Matched Watching Providers -")
            || title.hasPrefix("Saved No ID -")
            || title.hasPrefix("Saved No ID Watching -")
            || title.hasPrefix("Known Missing -")
            || title.hasPrefix("Known Missing Watching -") {
            return true
        }

        let visibleItems = activeItems
        return !visibleItems.isEmpty
            && visibleItems.allSatisfy(\.isManualProviderGapReviewItem)
    }

    var isKnownMissingProviderReviewGroup: Bool {
        if title.hasPrefix("Saved No ID -")
            || title.hasPrefix("Saved No ID Watching -")
            || title.hasPrefix("Known Missing -")
            || title.hasPrefix("Known Missing Watching -") {
            return true
        }

        let visibleItems = activeItems
        return !visibleItems.isEmpty
            && visibleItems.allSatisfy(\.isKnownMissingProviderReviewItem)
    }

    var isMatchedProviderReviewGroup: Bool {
        if title.hasPrefix("Matched Watching Providers -") {
            return true
        }

        let visibleItems = activeItems
        return !visibleItems.isEmpty
            && visibleItems.allSatisfy(\.isMatchedProviderReviewItem)
    }
}

extension LibraryPlanItem {
    var isManualProviderGapReviewItem: Bool {
        reviewTags.contains("metadata-manual-provider-gap")
            || reviewTags.contains("metadata-provider-known-missing")
            || reviewTags.contains("metadata-provider-already-matched")
            || reviewTags.contains("manual-provider-match")
    }

    var isKnownMissingProviderReviewItem: Bool {
        reviewTags.contains("metadata-provider-known-missing")
    }

    var isMatchedProviderReviewItem: Bool {
        reviewTags.contains("metadata-provider-already-matched")
    }
}

enum LibraryPlanCorrectionOption: String, CaseIterable, Sendable {
    case wrongSeries
    case wrongType
    case badNumber
    case treatAsDocument
    case treatAsBook
    case treatAsManga
    case treatAsManhwa
    case treatAsManhua
    case treatAsLightNovel
    case treatAsProseBook
    case treatAsOEL
    case treatAsReading
    case treatAsWatching
    case treatAsDocuments
    case treatAsImages
    case treatAsAudio
    case treatAsArchives
    case treatAsOtherFiles
    case keepTitle
    case moveExistingAside
    case mergeIntoExisting
    case notADuplicate
    case providerNotAvailable
    case custom

    var title: String {
        switch self {
        case .wrongSeries: "Wrong series"
        case .wrongType: "Wrong type"
        case .badNumber: "Bad volume/chapter"
        case .treatAsDocument: "Treat as document"
        case .treatAsBook: "Keep as book"
        case .treatAsManga: "Treat as manga"
        case .treatAsManhwa: "Treat as manhwa"
        case .treatAsManhua: "Treat as manhua"
        case .treatAsLightNovel: "Treat as light novel"
        case .treatAsProseBook: "Treat as prose book"
        case .treatAsOEL: "Treat as OEL"
        case .treatAsReading: "Move to Books"
        case .treatAsWatching: "Move to Videos"
        case .treatAsDocuments: "Move to Documents"
        case .treatAsImages: "Move to Images"
        case .treatAsAudio: "Move to Audio"
        case .treatAsArchives: "Move to Archives"
        case .treatAsOtherFiles: "Move to Other"
        case .keepTitle: "Keep title"
        case .moveExistingAside: "Move existing aside"
        case .mergeIntoExisting: "Merge into existing"
        case .notADuplicate: "Not a duplicate"
        case .providerNotAvailable: "Provider not available"
        case .custom: "Other reason"
        }
    }
}

struct LibraryPlanRejectionReason: Sendable, Equatable {
    var option: LibraryPlanCorrectionOption
    var note: String
    var createdAt: Date

    init(option: LibraryPlanCorrectionOption, note: String = "", createdAt: Date = Date()) {
        self.option = option
        self.note = note
        self.createdAt = createdAt
    }
}

extension LibraryPlanItem {
    var isEmptySortingFolderCleanup: Bool {
        stage == .canonicalFolders
            && operation == .inspectOnly
            && reviewTags.contains("empty-sorting-folder-cleanup")
    }

    var isSkippedForPass: Bool {
        decision == .skipped || rejectionReason != nil
    }

    var needsDecisionReview: Bool {
        guard !isSkippedForPass else { return false }
        if isNameCollisionResolution {
            return decision != .checked
        }
        if isFolderMergeResolution {
            return decision != .checked
        }
        if isDuplicateMoveAside {
            return decision != .checked
        }
        if isManualApprovalFileOperation {
            return decision != .checked
        }
        if isReviewGatedEPUBRepairOperation {
            return decision != .checked
        }

        return decision == .needsChoice || requiresReview || safety == .collision || safety == .network
    }

    var canResolveNameCollision: Bool {
        guard safety == .collision,
              proposedPath != nil,
              currentPath != proposedPath else {
            return false
        }

        switch operation {
        case .cleanRawName, .sortIntoFolder, .renameFolder, .renameFile:
            return true
        case .inspectOnly, .repairEpubPackage, .repairAppleBooksCompatibility, .createComicInfo, .refreshComicInfo, .createAnimeInfo, .refreshAnimeInfo, .duplicateDecision, .skip:
            return false
        }
    }

    var isNameCollisionResolution: Bool {
        canResolveNameCollision
            && !requiresReview
            && reason == PlannedMove.manualNameCollisionReason
    }

    var canMergeIntoExistingFolder: Bool {
        guard safety == .collision,
              operation == .renameFolder,
              proposedPath != nil,
              currentPath != proposedPath else {
            return false
        }
        return true
    }

    var isFolderMergeResolution: Bool {
        canMergeIntoExistingFolder
            && !requiresReview
            && reason == PlannedMove.manualFolderMergeReason
    }

    var canResolveDuplicateReview: Bool {
        stage == .duplicateReview
            && operation == .duplicateDecision
            && proposedPath != nil
            && currentPath != proposedPath
    }

    var isDuplicateMoveAside: Bool {
        canResolveDuplicateReview
            && !requiresReview
            && reason == PlannedMove.duplicateReviewReason
    }

    var isManualApprovalFileOperation: Bool {
        guard requiresReview,
              safety == .needsChoice,
              proposedPath != nil,
              currentPath != proposedPath else {
            return false
        }

        switch operation {
        case .cleanRawName, .sortIntoFolder, .renameFolder, .renameFile:
            break
        case .inspectOnly, .repairEpubPackage, .repairAppleBooksCompatibility, .createComicInfo, .refreshComicInfo, .createAnimeInfo, .refreshAnimeInfo, .duplicateDecision, .skip:
            return false
        }

        let tags = Set(reviewTags)
        return tags.contains("naming-title-change")
            || tags.contains("naming-punctuation-only")
            || tags.contains("naming-provider-token-change")
            || tags.contains("sss-shelf-review")
            || tags.contains("raw-video-numbered-wrapper")
    }

    var isApplyableFileOperation: Bool {
        if isNameCollisionResolution {
            return proposedPath != nil && currentPath != proposedPath
        }
        if isFolderMergeResolution {
            return proposedPath != nil && currentPath != proposedPath
        }
        if isDuplicateMoveAside {
            return proposedPath != nil && currentPath != proposedPath
        }
        if isManualApprovalFileOperation {
            return proposedPath != nil && currentPath != proposedPath
        }

        guard !requiresReview, safety == .reversible else { return false }

        switch operation {
        case .cleanRawName, .sortIntoFolder, .renameFolder, .renameFile:
            return proposedPath != nil && currentPath != proposedPath
        case .inspectOnly, .repairEpubPackage, .repairAppleBooksCompatibility, .createComicInfo, .refreshComicInfo, .createAnimeInfo, .refreshAnimeInfo, .duplicateDecision, .skip:
            return false
        }
    }

    var isApplyableComicInfoOperation: Bool {
        guard stage.usesComicInfoApplyEngine, !requiresReview, safety == .reversible else { return false }

        switch operation {
        case .createComicInfo, .refreshComicInfo, .createAnimeInfo, .refreshAnimeInfo:
            return proposedPath != nil
        case .inspectOnly, .repairEpubPackage, .repairAppleBooksCompatibility, .cleanRawName, .sortIntoFolder, .renameFolder, .renameFile, .duplicateDecision, .skip:
            return false
        }
    }

    var isExactIDBatchRefreshCandidate: Bool {
        guard stage == .comicInfo,
              isApplyableComicInfoOperation,
              usedNetworkData,
              operation == .refreshComicInfo || operation == .refreshAnimeInfo,
              hasExactIDBatchRefreshEvidence else {
            return false
        }

        let excludedTags: Set<String> = [
            "metadata-provider-precheck",
            "metadata-comicinfo-cleaner",
            "metadata-animeinfo-cleaner",
            "metadata-title-cleanup",
            "metadata-manual-provider-gap"
        ]
        return reviewTags.allSatisfy { !excludedTags.contains($0) }
    }

    private var hasExactIDBatchRefreshEvidence: Bool {
        if manualMangaBakaID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return true
        }
        if manualRanobeDBID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return true
        }
        if manualSourceIDs.contains(where: { $0.provider != .local && !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return true
        }
        if reviewTags.contains("metadata-exact-id-refresh") {
            return true
        }

        let folderName = URL(fileURLWithPath: currentPath).lastPathComponent
        return SableLibrarySourceIDParser.folderHints(in: folderName)
            .contains { $0.provider != .local }
    }

    var isApplyablePackageRepairOperation: Bool {
        (stage == .epubClinic || stage == .prepareRawFiles)
            && operation == .repairEpubPackage
            && !requiresReview
            && safety == .reversible
    }

    var isReviewGatedEPUBRepairOperation: Bool {
        guard (stage == .epubClinic || stage == .prepareRawFiles),
              operation == .repairAppleBooksCompatibility,
              requiresReview,
              safety == .needsChoice,
              proposedPath != nil else {
            return false
        }

        let tags = Set(reviewTags)
        guard !tags.contains("epub-protected") else { return false }

        let hasContentRepairScope = tags.contains(SableLibraryEPUBRepairScope.content.reviewTag)
        let hasNavigationRepairScope = tags.contains(SableLibraryEPUBRepairScope.navigation.reviewTag)
        let hasPackageRepairScope = tags.contains(SableLibraryEPUBRepairScope.package.reviewTag)
        let hasCoverRepairScope = tags.contains(SableLibraryEPUBRepairScope.cover.reviewTag)
        let hasReaderImportRepairScope = tags.contains(SableLibraryEPUBRepairScope.readerImport.reviewTag)
        let hasDiagnosticsRepairScope = tags.contains(SableLibraryEPUBRepairScope.diagnostics.reviewTag)
        let hasImplementedReviewedRepair =
            tags.contains("epub-fixed-layout")
                || tags.contains("epub-optimize")
                || (hasContentRepairScope && (
                    tags.contains("epub-xhtml")
                        || tags.contains("epub-duplicate-id")
                        || tags.contains("epub-missing-resource")
                        || tags.contains("epub-css")
                ))
                || (hasNavigationRepairScope && tags.contains("epub-navigation-order"))
                || (hasPackageRepairScope && tags.contains("epub-duplicate-id"))
                || (hasCoverRepairScope && tags.contains("epub-cover"))
                || (hasReaderImportRepairScope && tags.contains("epub-reader-import-refresh"))
                || (hasDiagnosticsRepairScope && (tags.contains("epub-fixed-layout") || tags.contains("epub-optimize")))
        let hasDiagnosticOnlyFinding =
            (tags.contains("epub-missing-resource") && !hasContentRepairScope)
                || (tags.contains("epub-xhtml") && !hasContentRepairScope)
                || (tags.contains("epub-navigation-order") && !hasNavigationRepairScope)
                || (tags.contains("epub-duplicate-id") && !hasContentRepairScope && !hasPackageRepairScope)

        return hasImplementedReviewedRepair && !hasDiagnosticOnlyFinding
    }

    var isApplyableAppleBooksCompatibilityRepairOperation: Bool {
        if isReviewGatedEPUBRepairOperation {
            return true
        }

        return (stage == .epubClinic || stage == .prepareRawFiles)
            && operation == .repairAppleBooksCompatibility
            && !requiresReview
            && safety == .reversible
    }

    var epubRepairScopes: Set<SableLibraryEPUBRepairScope> {
        let taggedScopes = Set(SableLibraryEPUBRepairScope.allCases.filter { scope in
            reviewTags.contains(scope.reviewTag)
        })
        return taggedScopes.isEmpty ? SableLibraryEPUBRepairScope.all : taggedScopes
    }

    var isReaderImportRefreshOnly: Bool {
        isApplyableAppleBooksCompatibilityRepairOperation
            && epubRepairScopes == [.readerImport]
    }

    var isApplyableOperation: Bool {
        isApplyableFileOperation
            || isApplyableComicInfoOperation
            || isApplyablePackageRepairOperation
            || isApplyableAppleBooksCompatibilityRepairOperation
            || isEmptySortingFolderCleanup
    }
}

enum LibraryPipelineStage: String, CaseIterable, Sendable {
    case inspect
    case prepareRawFiles
    case comicInfo
    case providerMatches
    case covers
    case canonicalFolders
    case canonicalFiles
    case epubClinic
    case duplicateReview
    case reviewApply

    var title: String {
        switch self {
        case .inspect: "Inspect library"
        case .prepareRawFiles: "Prepare raw files"
        case .comicInfo: "Metadata Sidecars"
        case .providerMatches: "Provider Matches"
        case .covers: "Covers"
        case .canonicalFolders: "Folder sorting"
        case .canonicalFiles: "File names"
        case .epubClinic: "Sable's Clinic"
        case .duplicateReview: "Duplicates"
        case .reviewApply: "Summary"
        }
    }

    var isMetadataSidecarStage: Bool {
        self == .comicInfo || self == .providerMatches
    }

    var usesComicInfoApplyEngine: Bool {
        isMetadataSidecarStage || self == .covers
    }

    func automaticRefreshStages(
        options: LibraryPipelineOptions,
        focusedMetadataApply: Bool
    ) -> [LibraryPipelineStage] {
        func readingOrganizationStages() -> [LibraryPipelineStage] {
            var stages: [LibraryPipelineStage] = []
            if options.cleanup.renameFolders {
                stages.append(.canonicalFolders)
            }
            if options.cleanup.renameFiles {
                stages.append(.canonicalFiles)
            }
            return stages
        }

        switch self {
        case .comicInfo:
            if focusedMetadataApply {
                return readingOrganizationStages()
            }
            return [.comicInfo, .providerMatches] + readingOrganizationStages()
        case .providerMatches:
            if focusedMetadataApply {
                return readingOrganizationStages()
            }
            return [.providerMatches] + readingOrganizationStages()
        case .canonicalFolders:
            return [.canonicalFolders] + (options.cleanup.renameFiles ? [.canonicalFiles] : [])
        case .canonicalFiles:
            return [.canonicalFiles]
        case .covers:
            return [.covers]
        case .epubClinic:
            return [.epubClinic]
        case .inspect, .prepareRawFiles, .duplicateReview, .reviewApply:
            return []
        }
    }
}

enum LibraryPlanOperation: String, Sendable {
    case inspectOnly
    case repairEpubPackage
    case repairAppleBooksCompatibility
    case cleanRawName
    case sortIntoFolder
    case createComicInfo
    case refreshComicInfo
    case createAnimeInfo
    case refreshAnimeInfo
    case renameFolder
    case renameFile
    case duplicateDecision
    case skip
}

enum LibraryPlanConfidence: String, Sendable {
    case high
    case medium
    case low
    case unknown
}

enum LibraryPlanSafety: String, Sendable {
    case inspectOnly
    case reversible
    case needsChoice
    case collision
    case network
}

enum LibraryPlanDecision: String, Sendable {
    case unchecked
    case checked
    case needsChoice
    case skipped
}

enum LibraryPipelineNextAction: String, Sendable {
    case chooseFolder
    case inspect
    case reviewDecisions
    case applyChecked
    case checkAgain
    case openReceipts
}

struct LibraryApplyResult: Sendable, Equatable {
    var appliedCount: Int
    var skippedCount: Int
    var receiptPath: String?
    var summary: String
    var appliedPaths: [LibraryAppliedPlanPath] = []

    static let empty = LibraryApplyResult(
        appliedCount: 0,
        skippedCount: 0,
        receiptPath: nil,
        summary: "No checked changes were applied."
    )
}

struct LibraryAppliedPlanPath: Sendable, Equatable {
    var currentPath: String
    var proposedPath: String?
    var stage: LibraryPipelineStage
    var operation: LibraryPlanOperation
}

struct LibraryPipelineSummary: Sendable, Equatable {
    var title: String
    var message: String
    var nextAction: LibraryPipelineNextAction
    var plannedCount: Int
    var unresolvedCount: Int
    var appliedCount: Int
}
