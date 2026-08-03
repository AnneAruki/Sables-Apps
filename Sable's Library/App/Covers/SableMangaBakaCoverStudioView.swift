//
//  SableMangaBakaCoverStudioView.swift
//  Sable's Covers
//

import AppKit
import Combine
import SwiftUI

enum SableMangaBakaStudioSource: String, CaseIterable, Identifiable {
    case manual
    case library
    case browse

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manual: "Search"
        case .library: "Library Gaps"
        case .browse: "Browse"
        }
    }
}

enum SableMangaBakaLibraryAuditFilter: String, CaseIterable, Identifiable {
    case needsAttention
    case missingID
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .needsAttention: "Needs Covers"
        case .missingID: "No MB ID"
        case .all: "All"
        }
    }
}

enum SableMangaBakaBrowseMediaType: String, CaseIterable, Identifiable {
    case all
    case novel
    case manga
    case manhwa

    var id: String { rawValue }
    var apiValue: String? { self == .all ? nil : rawValue }
    var title: String { self == .all ? "All" : rawValue.capitalized }
}

enum SableMangaBakaBrowseLicenseFilter: String, CaseIterable, Identifiable {
    case licensed
    case all
    case unlicensed

    var id: String { rawValue }

    var apiValue: Bool? {
        switch self {
        case .licensed: true
        case .all: nil
        case .unlicensed: false
        }
    }

    var title: String {
        switch self {
        case .licensed: "Licensed"
        case .all: "Any"
        case .unlicensed: "Unlicensed"
        }
    }
}

enum SableMangaBakaBrowseCoverFilter: String, CaseIterable, Identifiable {
    case missingCover
    case incompleteVolumes
    case unchecked
    case all

    var id: String { rawValue }
    var title: String {
        switch self {
        case .missingCover: "No Covers"
        case .incompleteVolumes: "Volume Gaps"
        case .unchecked: "Unproven"
        case .all: "All Series"
        }
    }
}

enum SableMangaBakaBrowseSort: String, CaseIterable, Identifiable {
    case newestPublication
    case recentlyCompleted
    case mostPopular
    case titleAscending
    case titleDescending

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newestPublication: "Newest publication"
        case .recentlyCompleted: "Recently completed"
        case .mostPopular: "Most popular"
        case .titleAscending: "Title A-Z"
        case .titleDescending: "Title Z-A"
        }
    }

    var apiValue: String {
        switch self {
        case .newestPublication: "published_start_date_desc"
        case .recentlyCompleted: "published_end_date_desc"
        case .mostPopular: "popularity_asc"
        case .titleAscending: "name_asc"
        case .titleDescending: "name_desc"
        }
    }
}

enum SableMangaBakaBrowseCoverageLanguage: String, CaseIterable, Identifiable, Sendable {
    case japanese
    case english

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var code: String { self == .japanese ? "ja" : "en" }
}

enum SableMangaBakaStorefrontScanScope: String, CaseIterable, Identifiable {
    case japanese
    case english
    case korean
    case japaneseEnglishKorean
    case french
    case german
    case italian
    case dutch
    case spanish
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .japanese: "Japanese"
        case .english: "English"
        case .korean: "Korean"
        case .japaneseEnglishKorean: "JP + EN + KO"
        case .french: "French"
        case .german: "German"
        case .italian: "Italian"
        case .dutch: "Dutch"
        case .spanish: "Spanish"
        case .all: "All Languages"
        }
    }

    var languageCodes: Set<String>? {
        switch self {
        case .japanese: ["ja"]
        case .english: ["en"]
        case .korean: ["ko"]
        case .japaneseEnglishKorean: ["ja", "en", "ko"]
        case .french: ["fr"]
        case .german: ["de"]
        case .italian: ["it"]
        case .dutch: ["nl"]
        case .spanish: ["es"]
        case .all: nil
        }
    }

    var searchDescription: String {
        switch self {
        case .japaneseEnglishKorean:
            "Japanese, English, and Korean"
        default:
            title
        }
    }
}

private struct SableMangaBakaStorefrontScanProgress: Equatable {
    var providerOrder: [String]
    var providerStates: [String: String]
    var activeProviders: Set<String>
    var completedProviders: Int
    var totalProviders: Int
    var imageCandidates: Int
    var inspectedImages: Int
    var acceptedImages: Int
    var rejectedImages: Int
    var startedAt: Date
    var isActive: Bool
}

private struct SableMangaBakaStorefrontCommentRun {
    var language: String
    var coverType: String
    var provider: SableLibraryBigBookCoversProvider
    var rating: String
    var start: Double
    var end: Double
}

nonisolated struct SableRolerConfirmedStorefrontGroup: Equatable {
    var language: String
    var provider: SableLibraryBigBookCoversProvider
    var coverType: String
    var publicationType: String? = nil
    var providerSeriesIDs: Set<String>
}

nonisolated struct SableMangaBakaCoverSafetyCorrection:
    Equatable, Identifiable, Sendable {
    let id: String
    let originalRating: String
    let proposedRating: String
    let inventoryGroup: SableMangaBakaCoverInventoryGroup
    let language: String

    init(
        cover: SableMangaBakaCoverImage,
        originalRating: String,
        proposedRating: String
    ) {
        id = Self.identity(for: cover)
        self.originalRating = originalRating
        self.proposedRating = proposedRating
        inventoryGroup = cover.inventoryGroup
        language = cover.language
    }

    func matches(_ cover: SableMangaBakaCoverImage) -> Bool {
        id == Self.identity(for: cover)
    }

    private static func identity(
        for cover: SableMangaBakaCoverImage
    ) -> String {
        if let imageID = cover.id {
            return "image:\(imageID)"
        }
        let language = cover.language
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
        let type = cover.type
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return [
            "slot",
            String(cover.seriesID ?? 0),
            language,
            type,
            String(cover.indexNumeric)
        ]
        .joined(separator: "|")
    }
}

private struct SableRolerUploadSyncPlan {
    var mangaBakaSeriesID: Int
    var groups: [SableRolerConfirmedStorefrontGroup]
    var corrections: [String: SableRolerBookVolumeCorrection]
}

@MainActor
final class SableMangaBakaCoverStudioStore: ObservableObject {
    @Published var source: SableMangaBakaStudioSource = .manual
    @Published var query = ""
    @Published var results: [SableMangaBakaSeriesSummary] = []
    @Published var selectedSeries: SableMangaBakaSeriesSummary?
    @Published var relatedSeries: [SableMangaBakaRelatedSeriesSummary] = []
    @Published var isLoadingRelatedSeries = false
    @Published var relatedSeriesMessage: String?
    @Published var draftImages: [SableMangaBakaCoverImage] = []
    @Published var pastedURLs = ""
    @Published var addedLanguage = "ja"
    @Published var addedType = "volume"
    @Published var addedRating = "safe"
    @Published var addedNote = ""
    @Published var startIndex = 1
    @Published var directCoverInspectionsByID:
        [String: SableMangaBakaDirectCoverInspection] = [:]
    @Published var directCoverLinkIDs: Set<String> = []
    @Published var submissionNote = ""
    @Published var preview: SableMangaBakaSubmissionPreview?
    @Published var lastSubmission: SableMangaBakaSubmissionResult?
    @Published var status = "Search MangaBaka or paste a series URL."
    @Published var errorMessage: String?
    @Published var isWorking = false
    @Published private(set) var isCheckingExistingCoverSafety = false
    @Published private(set) var existingCoverSafetyDidComplete = false
    @Published private(set) var existingCoverSafetyCompleted = 0
    @Published private(set) var existingCoverSafetyTotal = 0
    @Published private(set) var existingCoverSafetyProgressLabel =
        "Comparing artwork"
    @Published private(set) var existingCoverSafetyCorrectionCount = 0
    @Published private(set) var existingCoverSafetyReviewedCount = 0
    @Published private(set) var existingCoverSafetyCorrections:
        [SableMangaBakaCoverSafetyCorrection] = []
    @Published private(set) var hasMangaBakaToken = false
    @Published private(set) var mangaBakaAccountRole:
        SableMangaBakaAccountRole?
    @Published private(set) var isCheckingMangaBakaAccount = false
    @Published private(set) var mangaBakaAccountMessage: String?
    @Published var isDownloading = false
    @Published var downloadResult: SableMangaBakaDownloadResult?
    @Published var libraryAuditItems: [SableMangaBakaLibraryCoverAuditItem] = []
    @Published var libraryAuditFilter: SableMangaBakaLibraryAuditFilter = .needsAttention
    @Published var libraryAuditCompleted = 0
    @Published var libraryAuditTotal = 0
    @Published var browseQuery = ""
    @Published var browsePublisher = ""
    @Published var browseMediaType: SableMangaBakaBrowseMediaType = .all
    @Published var browseLicenseFilter: SableMangaBakaBrowseLicenseFilter = .licensed
    @Published var browseCoverFilter: SableMangaBakaBrowseCoverFilter = .missingCover
    @Published var browseSort: SableMangaBakaBrowseSort = .newestPublication
    @Published var browseCoverageLanguage: SableMangaBakaBrowseCoverageLanguage = .japanese
    @Published var browsePage = 1
    @Published var browseTotalCount = 0
    @Published var browseCatalogCountSummary: String?
    @Published var browseHasNextPage = false
    @Published var browseHasPreviousPage = false
    @Published var coverStatsBySeriesID: [Int: SableMangaBakaPublicCoverStats] = [:]
    @Published var browseExpectedVolumeCountsBySeriesID: [Int: Int] = [:]
    @Published var browseCoverStatsFailureIDs: Set<Int> = []
    @Published var storefrontSuggestions: [SableMangaBakaStorefrontCoverSuggestion] = [] {
        didSet { rebuildStorefrontSuggestionCaches() }
    }
    @Published var selectedStorefrontSuggestionIDs: Set<String> = [] {
        didSet { refreshStorefrontCompositeSlots() }
    }
    @Published var excludedStorefrontSuggestionIDs: Set<String> = [] {
        didSet { refreshStorefrontCompositeSlots() }
    }
    @Published var approvedStorefrontReviewGroupIDs: Set<String> = [] {
        didSet { refreshStorefrontCompositeSlots() }
    }
    @Published var rejectedStorefrontReviewGroupIDs: Set<String> = [] {
        didSet { refreshStorefrontCompositeSlots() }
    }
    @Published private(set) var storefrontCompositeSlots:
        [SableMangaBakaStorefrontCompositeSlot] = []
    @Published var rolerMatchShareStatuses:
        [String: SableRolerMatchShareStatus] = [:]
    @Published var rolerBookCorrectionStatuses:
        [String: SableRolerBookCorrectionStatus] = [:]
    @Published var storefrontContentRatingOverrides: [String: String] = [:]
    @Published var storefrontCoverNoteOverrides: [String: String] = [:]
    @Published var storefrontNotes: [String] = []
    @Published var storefrontStageSummary: String?
    @Published var storefrontScanScope: SableMangaBakaStorefrontScanScope = .japanese
    @Published private(set) var disabledStorefrontProviderIDs: Set<String>
    @Published private(set) var storefrontResultsAreLarge = false
    @Published var storeSeriesURLs = ""
    @Published var exactStoreSeriesOutcomes: [String] = []
    @Published fileprivate var storefrontScanProgress: SableMangaBakaStorefrontScanProgress?
    @Published fileprivate var storefrontScanElapsedSeconds = 0
    @Published private(set) var isStoppingStorefrontScan = false
    @Published var mangaBakaVolumeCovers: [SableMangaBakaPublicCoverImage] = []
    @Published var mangaBakaLiveCovers: [SableMangaBakaPublicCoverImage] = []
    @Published var coverInventoryLanguage = "all"
    @Published var libraryBundleTarget: SableMangaBakaLocalLibrarySeries?
    @Published var libraryBundleDraft: SableLibraryMangaBakaSeriesBundle?
    @Published var libraryBundleMessage: String?

    private let client: SableMangaBakaCoverClient
    private let settings = SableLibraryUserSettings()
    private let libraryScanner = SableMangaBakaLibraryScanner()
    private let storefrontDiscovery = SableMangaBakaStorefrontDiscovery()
    private let rolerContributorClient = SableRolerContributorClient()
    private let rolerMappingReceiptStore =
        SableRolerMappingReceiptStore()
    private let storefrontRelationshipApprovalStore:
        SableStorefrontRelationshipApprovalStore
    private var snapshotVersion: Int64?
    private var baselineImages: [SableMangaBakaCoverImage] = []
    private var mangaBakaTokenCache = ""
    private var mangaBakaAccountLookupGeneration = UUID()
    private var storefrontScanClock: Task<Void, Never>?
    private var storefrontScanTask: Task<Void, Never>?
    private var storefrontScanStopFallback: Task<Void, Never>?
    private var existingCoverSafetyTask: Task<Void, Never>?
    private var existingCoverSafetyGeneration = UUID()
    private var storefrontScanGeneration = UUID()
    private var storefrontScanProgressAccumulator:
        SableMangaBakaStorefrontScanProgress?
    private var lastStorefrontScanProgressPublishAt = Date.distantPast
    private var stagedStorefrontMappingSuggestionIDs: Set<String> = []
    private var pendingRolerBookCorrections:
        [String: SableRolerBookVolumeCorrection] = [:]
    private var cachedMangaBakaSubmissionSuggestions:
        [SableMangaBakaStorefrontCoverSuggestion] = []
    private let browseResultPageSize = 25

    init(
        client: SableMangaBakaCoverClient = SableMangaBakaCoverClient(),
        storefrontRelationshipApprovalStore:
            SableStorefrontRelationshipApprovalStore =
                SableStorefrontRelationshipApprovalStore()
    ) {
        self.client = client
        self.storefrontRelationshipApprovalStore =
            storefrontRelationshipApprovalStore
        disabledStorefrontProviderIDs =
            settings.loadDisabledCoverStorefrontProviderIDs()
        let token = settings.loadProviderCredentials()
            .mangaBakaPersonalAccessToken
            .trimmingCharacters(in: .whitespacesAndNewlines)
        mangaBakaTokenCache = token
        hasMangaBakaToken = !token.isEmpty
    }

    var selectedLibraryURL: URL? {
        settings.loadLibraryFolder()
    }

    var canGoBack: Bool {
        selectedSeries != nil
            || libraryBundleTarget != nil
            || !results.isEmpty
            || errorMessage != nil
    }

    var canSaveLibraryBundle: Bool {
        guard libraryBundleTarget?.comicInfoURL != nil,
              let libraryBundleDraft else {
            return false
        }
        return libraryBundleDraft.validationIssues.isEmpty
            && !isWorking
    }

    var selectedSeriesCanJoinLibraryBundle: Bool {
        guard let selectedSeries, let target = libraryBundleTarget else {
            return false
        }
        return mediaTypesMatch(
            local: target.mediaType,
            mangaBaka: selectedSeries.type
        ) && libraryBundleDraft?.members.contains(
            where: { $0.seriesID == selectedSeries.id }
        ) != true
    }

    func goBack() {
        existingCoverSafetyTask?.cancel()
        existingCoverSafetyGeneration = UUID()
        existingCoverSafetyTask = nil
        isCheckingExistingCoverSafety = false
        existingCoverSafetyDidComplete = false
        existingCoverSafetyCompleted = 0
        existingCoverSafetyTotal = 0
        existingCoverSafetyProgressLabel = "Comparing artwork"
        existingCoverSafetyCorrectionCount = 0
        existingCoverSafetyReviewedCount = 0
        existingCoverSafetyCorrections = []
        storefrontScanTask?.cancel()
        storefrontScanClock?.cancel()
        storefrontScanStopFallback?.cancel()
        storefrontScanGeneration = UUID()
        storefrontScanTask = nil
        storefrontScanClock = nil
        storefrontScanStopFallback = nil
        storefrontScanProgress = nil
        storefrontScanElapsedSeconds = 0
        storefrontResultsAreLarge = false
        isStoppingStorefrontScan = false
        isWorking = false

        if selectedSeries != nil {
            selectedSeries = nil
            relatedSeries = []
            isLoadingRelatedSeries = false
            relatedSeriesMessage = nil
            draftImages = []
            directCoverInspectionsByID = [:]
            directCoverLinkIDs = []
            baselineImages = []
            mangaBakaVolumeCovers = []
            mangaBakaLiveCovers = []
            storefrontSuggestions = []
            selectedStorefrontSuggestionIDs = []
            excludedStorefrontSuggestionIDs = []
            approvedStorefrontReviewGroupIDs = []
            rejectedStorefrontReviewGroupIDs = []
            rolerMatchShareStatuses = [:]
            rolerBookCorrectionStatuses = [:]
            pendingRolerBookCorrections = [:]
            storefrontContentRatingOverrides = [:]
            stagedStorefrontMappingSuggestionIDs = []
            preview = nil
            errorMessage = nil
            status = results.isEmpty
                ? "Search MangaBaka or paste a series URL."
                : "\(results.count) MangaBaka series found."
            return
        }

        if libraryBundleTarget != nil {
            source = .library
            libraryBundleTarget = nil
            libraryBundleDraft = nil
            libraryBundleMessage = nil
        }
        results = []
        query = ""
        errorMessage = nil
        status = source == .library
            ? "Choose a library series or scan the library again."
            : "Search MangaBaka or paste a series URL."
    }

    func refreshMangaBakaAccount() {
        let token = settings.loadProviderCredentials()
            .mangaBakaPersonalAccessToken
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let tokenChanged = token != mangaBakaTokenCache
        if tokenChanged {
            mangaBakaTokenCache = token
            mangaBakaAccountRole = nil
            mangaBakaAccountMessage = nil
            mangaBakaAccountLookupGeneration = UUID()
        }
        hasMangaBakaToken = !token.isEmpty
        guard !token.isEmpty else {
            isCheckingMangaBakaAccount = false
            mangaBakaAccountMessage = nil
            return
        }
        guard tokenChanged || mangaBakaAccountRole == nil else { return }
        guard !isCheckingMangaBakaAccount else { return }

        let generation = UUID()
        mangaBakaAccountLookupGeneration = generation
        isCheckingMangaBakaAccount = true
        Task { [weak self] in
            guard let self else { return }
            do {
                let profile = try await client.accountProfile(token: token)
                guard mangaBakaAccountLookupGeneration == generation,
                      mangaBakaTokenCache == token else {
                    return
                }
                mangaBakaAccountRole = profile.role
                mangaBakaAccountMessage = nil
                isCheckingMangaBakaAccount = false
            } catch {
                guard mangaBakaAccountLookupGeneration == generation,
                      mangaBakaTokenCache == token else {
                    return
                }
                mangaBakaAccountRole = nil
                mangaBakaAccountMessage =
                    "Sable could not verify this MangaBaka account yet. Cover changes will use the review queue."
                isCheckingMangaBakaAccount = false
            }
        }
    }

    var preferredSaveMode: SableMangaBakaSaveMode {
        mangaBakaAccountRole?.submissionMode ?? .review
    }

    var canApplyDirectly: Bool {
        preferredSaveMode == .direct
    }

    var filteredLibraryAuditItems: [SableMangaBakaLibraryCoverAuditItem] {
        switch libraryAuditFilter {
        case .needsAttention:
            libraryAuditItems.filter { $0.status.needsCoverAttention }
        case .missingID:
            libraryAuditItems.filter { $0.status == .missingMangaBakaID }
        case .all:
            libraryAuditItems
        }
    }

    var libraryAuditProgressText: String {
        guard libraryAuditTotal > 0 else { return "Not scanned yet" }
        return "\(libraryAuditCompleted) of \(libraryAuditTotal)"
    }

    var validationIssues: [String] {
        guard let selectedSeries, let snapshotVersion else { return [] }
        return SableMangaBakaCoverSnapshot(
            seriesID: selectedSeries.id,
            images: draftImages,
            version: snapshotVersion
        )
        .normalizedForSubmission()
        .validationIssues(
            allowingInheritedDuplicateURLsFrom: baselineImages
        )
    }

    var hasDraftChanges: Bool {
        snapshotVersion != nil && normalizedDraftImages != baselineImages
    }

    var canSubmit: Bool {
        selectedSeries != nil
            && snapshotVersion != nil
            && hasMangaBakaToken
            && !isCheckingMangaBakaAccount
            && validationIssues.isEmpty
            && !isWorking
            && hasDraftChanges
            && !submissionNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var normalizedDraftImages: [SableMangaBakaCoverImage] {
        guard let selectedSeries, let snapshotVersion else { return draftImages }
        return SableMangaBakaCoverSnapshot(
            seriesID: selectedSeries.id,
            images: draftImages,
            version: snapshotVersion
        )
        .normalizedForSubmission()
        .images
    }

    var liveOnlyMangaBakaCovers: [SableMangaBakaPublicCoverImage] {
        let editableIDs = Set(draftImages.compactMap(\.id))
        let editableSlots = Set(draftImages.map {
            coverInventorySlot(
                language: $0.language,
                type: $0.type,
                indexNumeric: $0.indexNumeric
            )
        })
        return mangaBakaLiveCovers.filter {
            !editableIDs.contains($0.id)
                && !editableSlots.contains(
                    coverInventorySlot(
                        language: $0.language,
                        type: $0.type,
                        indexNumeric: $0.indexNumeric
                    )
                )
        }
    }

    var coverInventoryTotalCount: Int {
        draftImages.count + liveOnlyMangaBakaCovers.count
    }

    var coverInventoryLanguageCodes: [String] {
        Set(
            draftImages.map { normalizedStudioLanguage($0.language) }
                + liveOnlyMangaBakaCovers.map { normalizedStudioLanguage($0.language) }
        )
        .sorted {
            let preferredOrder = ["ja", "en", "ko", "zh", "fr", "it", "de", "es", "pt", "nl", "unknown"]
            let lhsRank = preferredOrder.firstIndex(of: $0) ?? preferredOrder.count
            let rhsRank = preferredOrder.firstIndex(of: $1) ?? preferredOrder.count
            return lhsRank == rhsRank ? $0 < $1 : lhsRank < rhsRank
        }
    }

    var coverInventoryFilteredTotalCount: Int {
        draftImages.indices.filter {
            coverInventoryMatches(language: draftImages[$0].language)
        }.count
            + liveOnlyMangaBakaCovers.filter {
                coverInventoryMatches(language: $0.language)
            }.count
    }

    var existingCoverSafetyCorrectionDraftIndices: [Int] {
        guard !existingCoverSafetyCorrections.isEmpty else { return [] }
        return draftImages.indices.filter { index in
            existingCoverSafetyCorrections.contains {
                $0.matches(draftImages[index])
            }
        }
    }

    func existingCoverSafetyCorrection(
        atDraftIndex index: Int
    ) -> SableMangaBakaCoverSafetyCorrection? {
        guard draftImages.indices.contains(index) else { return nil }
        return existingCoverSafetyCorrections.first {
            $0.matches(draftImages[index])
        }
    }

    func existingCoverSafetyCorrectionCount(
        in group: SableMangaBakaCoverInventoryGroup
    ) -> Int {
        existingCoverSafetyCorrections.filter {
            $0.inventoryGroup == group
                && coverInventoryMatches(language: $0.language)
        }.count
    }

    func existingCoverSafetyCorrectionCount(
        in group: SableMangaBakaCoverInventoryGroup,
        language: String
    ) -> Int {
        let normalizedLanguage = normalizedStudioLanguage(language)
        return existingCoverSafetyCorrections.filter {
            $0.inventoryGroup == group
                && normalizedStudioLanguage($0.language)
                    == normalizedLanguage
        }.count
    }

    func draftImageIndices(
        in group: SableMangaBakaCoverInventoryGroup
    ) -> [Int] {
        draftImages.indices.filter {
            draftImages[$0].inventoryGroup == group
                && coverInventoryMatches(language: draftImages[$0].language)
        }
    }

    func liveOnlyCovers(
        in group: SableMangaBakaCoverInventoryGroup
    ) -> [SableMangaBakaPublicCoverImage] {
        liveOnlyMangaBakaCovers.filter {
            $0.inventoryGroup == group
                && coverInventoryMatches(language: $0.language)
        }
    }

    func coverInventoryCount(
        in group: SableMangaBakaCoverInventoryGroup
    ) -> Int {
        draftImageIndices(in: group).count + liveOnlyCovers(in: group).count
    }

    func coverInventoryLanguageCodes(
        in group: SableMangaBakaCoverInventoryGroup
    ) -> [String] {
        coverInventoryLanguageCodes.filter { language in
            (coverInventoryLanguage == "all"
                || coverInventoryLanguage == language)
                && coverInventoryCount(in: group, language: language) > 0
        }
    }

    func draftImageIndices(
        in group: SableMangaBakaCoverInventoryGroup,
        language: String
    ) -> [Int] {
        let normalizedLanguage = normalizedStudioLanguage(language)
        return draftImages.indices.filter {
            draftImages[$0].inventoryGroup == group
                && normalizedStudioLanguage(draftImages[$0].language)
                    == normalizedLanguage
        }
    }

    func liveOnlyCovers(
        in group: SableMangaBakaCoverInventoryGroup,
        language: String
    ) -> [SableMangaBakaPublicCoverImage] {
        let normalizedLanguage = normalizedStudioLanguage(language)
        return liveOnlyMangaBakaCovers.filter {
            $0.inventoryGroup == group
                && normalizedStudioLanguage($0.language)
                    == normalizedLanguage
        }
    }

    func coverInventoryCount(
        in group: SableMangaBakaCoverInventoryGroup,
        language: String
    ) -> Int {
        draftImageIndices(in: group, language: language).count
            + liveOnlyCovers(in: group, language: language).count
    }

    private func coverInventoryMatches(language: String) -> Bool {
        coverInventoryLanguage == "all"
            || normalizedStudioLanguage(language) == coverInventoryLanguage
    }

    private func coverInventorySlot(
        language: String,
        type: String,
        indexNumeric: Double
    ) -> String {
        [
            normalizedStudioLanguage(language),
            type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            String(indexNumeric)
        ]
        .joined(separator: "|")
    }

    func search() {
        guard !isWorking else { return }
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanQuery.isEmpty else {
            errorMessage = "Enter a title, MangaBaka series ID, or series URL."
            return
        }

        isWorking = true
        errorMessage = nil
        preview = nil
        lastSubmission = nil
        status = "Searching MangaBaka..."

        Task {
            do {
                if let id = SableMangaBakaCoverClient.seriesID(from: cleanQuery) {
                    let series = try await client.series(id: id)
                    results = [series]
                    await load(series)
                } else {
                    results = try await client.searchSeries(cleanQuery)
                    status = results.isEmpty
                        ? "No MangaBaka series matched this search."
                        : "\(results.count) MangaBaka series found."
                    isWorking = false
                }
            } catch {
                finish(error)
            }
        }
    }

    func browse(resetPage: Bool = true) {
        guard !isWorking else { return }
        let cleanPublisher = browsePublisher.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanQuery = browseQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if resetPage {
            browsePage = 1
        }

        isWorking = true
        errorMessage = nil
        preview = nil
        lastSubmission = nil
        browseCatalogCountSummary = nil
        status = "Browsing MangaBaka..."

        Task {
            do {
                let page = try await client.browseSeries(
                    query: cleanQuery,
                    publisher: cleanPublisher.nilIfEmpty,
                    mediaType: browseMediaType.apiValue,
                    isLicensed: browseLicenseFilter.apiValue,
                    page: browsePage,
                    limit: browseResultPageSize,
                    sortBy: browseSort.apiValue
                )
                browseTotalCount = page.totalCount
                browseCatalogCountSummary = switch browseLicenseFilter {
                case .licensed:
                    "\(page.totalCount) licensed MangaBaka series match the active title, publisher, and media filters."
                case .all:
                    "\(page.totalCount) MangaBaka series match the active title, publisher, and media filters."
                case .unlicensed:
                    "\(page.totalCount) unlicensed MangaBaka series match the active title, publisher, and media filters."
                }
                browseHasNextPage = page.hasNextPage
                browseHasPreviousPage = page.hasPreviousPage

                let requiresCoverAudit = browseCoverFilter == .missingCover
                    || browseCoverFilter == .incompleteVolumes
                    || browseCoverFilter == .unchecked
                var audited = page.series
                if requiresCoverAudit {
                    for series in page.series {
                        coverStatsBySeriesID.removeValue(forKey: series.id)
                        browseExpectedVolumeCountsBySeriesID.removeValue(forKey: series.id)
                        browseCoverStatsFailureIDs.remove(series.id)
                    }
                    audited = await auditBrowseResults(page.series)
                }

                switch browseCoverFilter {
                case .missingCover:
                    results = audited.filter {
                        coverStatsBySeriesID[$0.id]?.volumeCoverCount == 0
                    }
                case .incompleteVolumes:
                    results = audited.filter { seriesNeedsCovers($0) }
                case .unchecked:
                    results = audited.filter {
                        browseCoverStatsFailureIDs.contains($0.id)
                            || browseCoverage(for: $0)?.isIndeterminate == true
                    }
                case .all:
                    results = page.series
                }

                let uncheckedCount: Int
                if browseCoverFilter == .missingCover
                    || browseCoverFilter == .incompleteVolumes
                    || browseCoverFilter == .unchecked {
                    uncheckedCount = page.series.filter {
                        browseCoverStatsFailureIDs.contains($0.id)
                    }.count
                } else {
                    uncheckedCount = 0
                }
                let uncheckedSuffix = uncheckedCount > 0
                    ? " \(uncheckedCount) cover check\(uncheckedCount == 1 ? "" : "s") failed; use Unproven to retry later."
                    : ""
                let language = browseCoverageLanguage.title
                switch browseCoverFilter {
                case .missingCover:
                    let continuation = page.hasNextPage
                        ? " Continue to catalog page \(page.page + 1) to check more."
                        : ""
                    status = results.isEmpty
                        ? "No empty MangaBaka volume-cover sets were found on catalog page \(page.page).\(uncheckedSuffix)\(continuation)"
                        : "\(results.count) series with no MangaBaka volume covers shown from catalog page \(page.page).\(uncheckedSuffix)\(continuation)"
                case .incompleteVolumes:
                    status = results.isEmpty
                        ? "No confirmed \(language.lowercased()) volume-cover gaps were found on this page.\(uncheckedSuffix)"
                        : "\(results.count) series with \(language.lowercased()) volume-cover gaps shown from \(page.totalCount) catalog matches.\(uncheckedSuffix)"
                case .unchecked:
                    status = results.isEmpty
                        ? "Every \(language.lowercased()) cover set on this page has enough evidence to classify."
                        : "\(results.count) \(language.lowercased()) cover set\(results.count == 1 ? "" : "s") have an unknown release total or could not be checked."
                case .all:
                    status = "\(results.count) shown from \(page.totalCount) matching MangaBaka series."
                }
                isWorking = false
            } catch {
                finish(error)
            }
        }
    }

    func browseNextPage() {
        guard browseHasNextPage else { return }
        browsePage += 1
        browse(resetPage: false)
    }

    func browsePreviousPage() {
        guard browseHasPreviousPage, browsePage > 1 else { return }
        browsePage -= 1
        browse(resetPage: false)
    }

    func usePublisherPreset(_ publisher: String) {
        browsePublisher = publisher
        browsePage = 1
    }

    func scanLibrary() {
        guard !isWorking else { return }
        guard let root = selectedLibraryURL else {
            errorMessage = "Choose your library in My Library first."
            return
        }

        isWorking = true
        errorMessage = nil
        libraryAuditItems = []
        libraryAuditCompleted = 0
        libraryAuditTotal = 0
        status = "Reading local ComicInfo files..."

        Task {
            let didAccess = root.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    root.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let scanner = libraryScanner
                let localSeries = try await Task.detached(priority: .userInitiated) {
                    try scanner.scan(root: root)
                }.value
                libraryAuditTotal = localSeries.count

                let missingIDs = localSeries
                    .filter { !$0.hasMangaBakaIdentity }
                    .map {
                        SableMangaBakaLibraryCoverAuditItem(
                            localSeries: $0,
                            mangaBakaSeries: nil,
                            coverStats: nil,
                            status: .missingMangaBakaID,
                            note: "No MangaBaka ID is saved in ComicInfo or the series folder name."
                        )
                    }
                libraryAuditItems = missingIDs
                libraryAuditCompleted = missingIDs.count

                let matchedSeries = localSeries.filter(\.hasMangaBakaIdentity)
                for batchStart in stride(from: 0, to: matchedSeries.count, by: 2) {
                    let batch = Array(
                        matchedSeries[batchStart..<min(batchStart + 2, matchedSeries.count)]
                    )
                    let checked = await withTaskGroup(
                        of: SableMangaBakaLibraryCoverAuditItem.self
                    ) { group in
                        for local in batch {
                            group.addTask {
                                await self.auditLocalSeries(local)
                            }
                        }
                        var values: [SableMangaBakaLibraryCoverAuditItem] = []
                        for await value in group {
                            values.append(value)
                        }
                        return values
                    }
                    libraryAuditItems.append(contentsOf: checked)
                    libraryAuditItems.sort {
                        $0.localSeries.title.localizedCaseInsensitiveCompare(
                            $1.localSeries.title
                        ) == .orderedAscending
                    }
                    libraryAuditCompleted += checked.count
                    status = "Checked \(libraryAuditCompleted) of \(libraryAuditTotal) local series..."
                }

                let attentionCount = libraryAuditItems.filter {
                    $0.status.needsCoverAttention
                }.count
                status = "Library scan finished: \(attentionCount) series need MangaBaka cover attention."
                isWorking = false
            } catch {
                finish(error)
            }
        }
    }

    func openLibraryAuditItem(_ item: SableMangaBakaLibraryCoverAuditItem) {
        libraryBundleTarget = item.localSeries
        libraryBundleDraft = item.localSeries.mangaBakaSeriesBundle
            ?? SableLibraryMangaBakaSeriesBundle(
                canonicalProvider: item.localSeries.ranobeDBID == nil
                    ? nil
                    : "ranobedb",
                canonicalSeriesID: item.localSeries.ranobeDBID,
                mediaType: item.localSeries.mediaType,
                members: item.localSeries.mangaBakaID.map {
                    [
                        SableLibraryMangaBakaSeriesBundleMember(
                            seriesID: $0,
                            title: item.localSeries.title,
                            mediaType: item.localSeries.mediaType,
                            sourceVolumeStart: 1,
                            sourceVolumeEnd: max(1, item.localSeries.localBookCount),
                            libraryVolumeStart: 1
                        )
                    ]
                } ?? []
            )
        libraryBundleMessage = item.localSeries.mangaBakaSeriesBundle == nil
            ? "Add each matching MangaBaka arc in the same order as the continuous library volumes."
            : "Loaded the saved MangaBaka series bundle."

        if let series = item.mangaBakaSeries {
            results = [series]
            select(series)
            return
        }

        source = .manual
        query = item.localSeries.title
        search()
    }

    func addSelectedSeriesToLibraryBundle() {
        guard let selectedSeries else { return }
        addSeriesToLibraryBundle(selectedSeries)
    }

    func addSeriesToLibraryBundle(_ series: SableMangaBakaSeriesSummary) {
        guard let target = libraryBundleTarget else { return }
        guard mediaTypesMatch(local: target.mediaType, mangaBaka: series.type) else {
            errorMessage =
                "\(series.displayTitle) is \(series.type), but the local series is \(target.mediaType)."
            return
        }

        var bundle = libraryBundleDraft
            ?? SableLibraryMangaBakaSeriesBundle(
                canonicalProvider: target.ranobeDBID == nil ? nil : "ranobedb",
                canonicalSeriesID: target.ranobeDBID,
                mediaType: target.mediaType,
                members: []
            )
        guard !bundle.members.contains(where: { $0.seriesID == series.id }) else {
            libraryBundleMessage = "\(series.displayTitle) is already in this bundle."
            return
        }

        let volumeCount = max(1, expectedVolumeCount(series.finalVolume) ?? 1)
        bundle.members.append(
            SableLibraryMangaBakaSeriesBundleMember(
                seriesID: series.id,
                title: series.nativeTitle ?? series.displayTitle,
                mediaType: series.type,
                sourceVolumeStart: 1,
                sourceVolumeEnd: volumeCount,
                libraryVolumeStart: bundle.nextLibraryVolumeStart
            )
        )
        libraryBundleDraft = bundle.normalized()
        libraryBundleMessage =
            "Added \(series.displayTitle). Check its volume count and order before saving."
        errorMessage = nil
    }

    func removeLibraryBundleMember(seriesID: Int) {
        guard var bundle = libraryBundleDraft else { return }
        bundle.members.removeAll { $0.seriesID == seriesID }
        libraryBundleDraft = bundle.normalized()
        libraryBundleMessage = "Removed MangaBaka \(seriesID) from the draft."
    }

    func moveLibraryBundleMember(seriesID: Int, offset: Int) {
        guard var bundle = libraryBundleDraft,
              let index = bundle.members.firstIndex(where: {
                  $0.seriesID == seriesID
              }) else {
            return
        }
        let destination = index + offset
        guard bundle.members.indices.contains(destination) else { return }
        bundle.members.swapAt(index, destination)
        libraryBundleDraft = bundle.normalized()
        libraryBundleMessage = "Updated the continuous library volume order."
    }

    func setLibraryBundleVolumeCount(seriesID: Int, count: Int) {
        guard var bundle = libraryBundleDraft,
              let index = bundle.members.firstIndex(where: {
                  $0.seriesID == seriesID
              }) else {
            return
        }
        let safeCount = min(200, max(1, count))
        bundle.members[index].sourceVolumeEnd =
            bundle.members[index].sourceVolumeStart + safeCount - 1
        libraryBundleDraft = bundle.normalized()
        libraryBundleMessage = "Updated the volume mapping."
    }

    func saveLibraryBundle() {
        guard let comicInfoURL = libraryBundleTarget?.comicInfoURL,
              let bundle = libraryBundleDraft else {
            errorMessage = "This library series does not have a writable ComicInfo.json."
            return
        }
        do {
            let normalized = bundle.normalized()
            try SableLibraryMangaBakaSeriesBundleStore.save(
                normalized,
                to: comicInfoURL
            )
            libraryBundleDraft = normalized
            if var target = libraryBundleTarget {
                target.mangaBakaSeriesBundle = normalized
                libraryBundleTarget = target
            }
            if let index = libraryAuditItems.firstIndex(where: {
                $0.localSeries.id == libraryBundleTarget?.id
            }) {
                libraryAuditItems[index].localSeries.mangaBakaSeriesBundle = normalized
                libraryAuditItems[index].note =
                    "Saved \(normalized.members.count) MangaBaka series as one continuous library sequence."
            }
            libraryBundleMessage =
                "Saved \(normalized.members.count) MangaBaka series for this one library series. Books and covers were not changed."
            status = "Library series bundle saved."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func load(
        _ series: SableMangaBakaSeriesSummary,
        preservingStorefrontResults: Bool = false
    ) async {
        existingCoverSafetyTask?.cancel()
        existingCoverSafetyGeneration = UUID()
        existingCoverSafetyTask = nil
        isCheckingExistingCoverSafety = false
        existingCoverSafetyDidComplete = false
        existingCoverSafetyCompleted = 0
        existingCoverSafetyTotal = 0
        existingCoverSafetyProgressLabel = "Comparing artwork"
        existingCoverSafetyCorrectionCount = 0
        existingCoverSafetyReviewedCount = 0
        existingCoverSafetyCorrections = []
        storefrontScanClock?.cancel()
        storefrontScanClock = nil
        storefrontScanProgress = nil
        storefrontScanElapsedSeconds = 0
        isWorking = true
        errorMessage = nil
        selectedSeries = series
        preview = nil
        prepareStorefrontStateForSeriesLoad(
            preservingStorefrontResults: preservingStorefrontResults
        )
        if !preservingStorefrontResults {
            relatedSeries = []
            relatedSeriesMessage = nil
            loadRelatedSeries(for: series.id)
        }
        mangaBakaVolumeCovers = []
        mangaBakaLiveCovers = []
        status = "Loading the live MangaBaka cover set..."

        do {
            let inventory = try await client.coverInventory(
                seriesID: series.id,
                token: mangaBakaToken
            )
            let snapshot = inventory.snapshot
            mangaBakaLiveCovers = inventory.liveImages
            mangaBakaVolumeCovers = inventory.liveImages.filter {
                $0.type.caseInsensitiveCompare("volume") == .orderedSame
            }
            snapshotVersion = snapshot.version
            baselineImages = snapshot.normalizedForSubmission().images
            var preparedImages = baselineImages
            var bookLiveUpgradeCount = 0
            for index in preparedImages.indices {
                let preferredURL = preparedImages[index].preferredBookLiveSourceURL
                guard preferredURL != preparedImages[index].url else { continue }
                preparedImages[index].url = preferredURL
                preparedImages[index].previewURL = preferredURL
                bookLiveUpgradeCount += 1
            }
            let preparedPreferredDefault = applyPreferredDefault(
                to: &preparedImages
            )
            draftImages = preparedImages
            if coverInventoryLanguage != "all",
               !coverInventoryLanguageCodes.contains(coverInventoryLanguage) {
                coverInventoryLanguage = "all"
            }
            var preparedNotes: [String] = []
            if bookLiveUpgradeCount > 0 {
                preparedNotes.append(
                    "Upgraded \(bookLiveUpgradeCount) BookLive cover source URL\(bookLiveUpgradeCount == 1 ? "" : "s") from preview thumbnails to the full-resolution X images. Volume, language, media type, and BookLive title IDs are unchanged."
                )
            }
            if preparedPreferredDefault {
                preparedNotes.append(
                    "Updated the default cover using the preferred language and cover-type order."
                )
            }
            submissionNote = preparedNotes.joined(separator: " ")
            startIndex = max(
                1,
                Int((preparedImages.map(\.indexNumeric).max() ?? 0).rounded(.up)) + 1
            )
            if preparedImages.isEmpty {
                status = "This series has no MangaBaka cover images yet."
            } else if bookLiveUpgradeCount > 0 || preparedPreferredDefault {
                let qualityStatus = bookLiveUpgradeCount > 0
                    ? " Prepared \(bookLiveUpgradeCount) safe BookLive quality upgrade\(bookLiveUpgradeCount == 1 ? "" : "s") from preview thumbnails to X images."
                    : ""
                let defaultStatus = preparedPreferredDefault
                    ? " Prepared the preferred default cover."
                    : ""
                status = "Loaded \(preparedImages.count) live MangaBaka covers.\(qualityStatus)\(defaultStatus)"
            } else {
                status = "Loaded \(preparedImages.count) live MangaBaka cover image\(preparedImages.count == 1 ? "" : "s")."
            }
            isWorking = false
            startExistingCoverSafetyAudit()
        } catch {
            draftImages = []
            directCoverInspectionsByID = [:]
            directCoverLinkIDs = []
            baselineImages = []
            mangaBakaVolumeCovers = []
            mangaBakaLiveCovers = []
            snapshotVersion = nil
            finish(error)
        }
    }

    private func startExistingCoverSafetyAudit() {
        guard !draftImages.isEmpty else { return }
        let coversNeedingVision = draftImages.filter {
            humanSafetyRating(for: $0) == nil
        }

        let generation = UUID()
        existingCoverSafetyGeneration = generation
        existingCoverSafetyCompleted = 0
        existingCoverSafetyTotal = coversNeedingVision.count
        existingCoverSafetyProgressLabel = "Comparing artwork"
        existingCoverSafetyCorrectionCount = 0
        existingCoverSafetyReviewedCount = draftImages.count
        existingCoverSafetyCorrections = []
        isCheckingExistingCoverSafety = true
        existingCoverSafetyDidComplete = false

        existingCoverSafetyTask = Task { [weak self] in
            guard let self else { return }
            let inspections = await storefrontDiscovery
                .inspectDirectCoverSafety(
                    coversNeedingVision,
                    progress: { [weak self] completed, total, phase in
                        guard let self,
                              self.existingCoverSafetyGeneration
                                == generation else {
                            return
                        }
                        self.existingCoverSafetyCompleted = completed
                        self.existingCoverSafetyTotal = total
                        self.existingCoverSafetyProgressLabel = switch phase {
                        case .comparingArtwork:
                            "Comparing artwork"
                        case .checkingSafety:
                            "Checking safety"
                        }
                    }
                )
            guard !Task.isCancelled,
                  existingCoverSafetyGeneration == generation else {
                return
            }

            let inspectionsByID = Dictionary(
                uniqueKeysWithValues: inspections.map { ($0.id, $0) }
            )
            var correctedImages = draftImages
            var corrections: [SableMangaBakaCoverSafetyCorrection] = []
            for index in correctedImages.indices {
                if let humanRating = humanSafetyRating(
                    for: correctedImages[index]
                ) {
                    guard SableMangaBakaCoverSafetyAutomation.rank(
                        humanRating
                    ) != SableMangaBakaCoverSafetyAutomation.rank(
                        correctedImages[index].contentRating
                    ) else {
                        continue
                    }
                    corrections.append(
                        SableMangaBakaCoverSafetyCorrection(
                            cover: correctedImages[index],
                            originalRating:
                                correctedImages[index].contentRating,
                            proposedRating: humanRating
                        )
                    )
                    correctedImages[index].contentRating = humanRating
                    continue
                }
                let sourceURL = correctedImages[index].previewURL
                    ?? correctedImages[index].url
                let identity = SableMangaBakaCoverSnapshot
                    .coverURLIdentity(sourceURL)
                guard let inspection = inspectionsByID[identity],
                      let proposedRating =
                        SableMangaBakaCoverSafetyAutomation
                            .proposedReviewRating(
                                currentRating:
                                    correctedImages[index].contentRating,
                                inferredRating: inspection.contentRating,
                                wasInferred:
                                    inspection.contentRatingWasInferred
                            ) else {
                    continue
                }
                corrections.append(
                    SableMangaBakaCoverSafetyCorrection(
                        cover: correctedImages[index],
                        originalRating:
                            correctedImages[index].contentRating,
                        proposedRating: proposedRating
                    )
                )
                correctedImages[index].contentRating = proposedRating
            }

            if !corrections.isEmpty {
                draftImages = correctedImages
            }
            existingCoverSafetyCorrections = corrections
            let correctionCount = corrections.count
            existingCoverSafetyCorrectionCount = correctionCount
            isCheckingExistingCoverSafety = false
            existingCoverSafetyDidComplete = true
            existingCoverSafetyTask = nil
            guard correctionCount > 0 else { return }

            let safetyNote =
                "Prepared \(correctionCount) cover safety correction\(correctionCount == 1 ? "" : "s") after checking the final unique images against human judgments and local vision. Every rating change remains reviewable before it is applied."
            let existingNote = submissionNote.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            submissionNote = existingNote.isEmpty
                ? safetyNote
                : "\(existingNote) \(safetyNote)"
            status =
                "Loaded the MangaBaka cover set and prepared \(correctionCount) safety rating correction\(correctionCount == 1 ? "" : "s") for review."
            invalidatePreview()
        }
    }

    private func humanSafetyRating(
        for cover: SableMangaBakaCoverImage
    ) -> String? {
        guard let seriesID = cover.seriesID ?? selectedSeries?.id else {
            return nil
        }
        if let imageID = cover.id,
           let rating = SableCoverSafetyHumanMemory.shared.rating(
               seriesID: seriesID,
               imageID: imageID
           ) {
            return rating
        }
        if let rating = SableCoverSafetyHumanMemory.shared.rating(
            seriesID: seriesID,
            sourceURL: cover.url
        ) ?? cover.previewURL.flatMap({
            SableCoverSafetyHumanMemory.shared.rating(
                seriesID: seriesID,
                sourceURL: $0
            )
        }) {
            return rating
        }
        return SableCoverSafetyHumanMemory.shared.rating(
            seriesID: seriesID,
            language: cover.language,
            type: cover.type,
            indexNumeric: cover.indexNumeric
        )
    }

    func prepareStorefrontStateForSeriesLoad(
        preservingStorefrontResults: Bool
    ) {
        selectedStorefrontSuggestionIDs = []
        guard !preservingStorefrontResults else { return }

        lastSubmission = nil
        storefrontSuggestions = []
        excludedStorefrontSuggestionIDs = []
        approvedStorefrontReviewGroupIDs = []
        rejectedStorefrontReviewGroupIDs = []
        rolerMatchShareStatuses = [:]
        rolerBookCorrectionStatuses = [:]
        pendingRolerBookCorrections = [:]
        storefrontContentRatingOverrides = [:]
        storefrontCoverNoteOverrides = [:]
        stagedStorefrontMappingSuggestionIDs = []
        storefrontNotes = []
        storefrontStageSummary = nil
        storeSeriesURLs = ""
        exactStoreSeriesOutcomes = []
    }

    func select(_ series: SableMangaBakaSeriesSummary) {
        guard !isWorking else { return }
        Task {
            await load(series)
        }
    }

    private func loadRelatedSeries(for seriesID: Int) {
        isLoadingRelatedSeries = true
        Task { [weak self] in
            guard let self else { return }
            do {
                let loaded = try await client.relatedSeries(seriesID: seriesID)
                guard selectedSeries?.id == seriesID else { return }
                relatedSeries = loaded
                relatedSeriesMessage = loaded.isEmpty
                    ? "No direct MangaBaka relationships."
                    : nil
                isLoadingRelatedSeries = false
            } catch {
                guard selectedSeries?.id == seriesID else { return }
                relatedSeries = []
                relatedSeriesMessage = "Related series could not be loaded."
                isLoadingRelatedSeries = false
            }
        }
    }

    func scanStorefronts() {
        startStorefrontScan(
            providers: recommendedStorefrontProviders,
            includesSecondarySources: false
        )
    }

    func scanMoreStorefronts() {
        startStorefrontScan(
            providers: enabledStorefrontProviders,
            includesSecondarySources: true
        )
    }

    private func startStorefrontScan(
        providers: [SableLibraryBigBookCoversProvider],
        includesSecondarySources: Bool
    ) {
        guard let selectedSeries, !isWorking else { return }
        let scope = storefrontScanScope
        guard !providers.isEmpty else {
            errorMessage = "Choose at least one provider before scanning."
            return
        }
        isWorking = true
        errorMessage = nil
        storefrontStageSummary = nil
        storefrontResultsAreLarge = false
        storefrontSuggestions = []
        storefrontNotes = []
        selectedStorefrontSuggestionIDs = []
        excludedStorefrontSuggestionIDs = []
        approvedStorefrontReviewGroupIDs = []
        rejectedStorefrontReviewGroupIDs = []
        rolerMatchShareStatuses = [:]
        rolerBookCorrectionStatuses = [:]
        pendingRolerBookCorrections = [:]
        storefrontContentRatingOverrides = [:]
        storefrontCoverNoteOverrides = [:]
        stagedStorefrontMappingSuggestionIDs = []
        exactStoreSeriesOutcomes = []
        let scanGeneration = beginStorefrontScan(providers: providers)
        status = scope == .all
            ? "Searching every regional storefront for compatible cover series..."
            : "Searching \(scope.searchDescription.lowercased()) storefronts for compatible cover series..."

        storefrontScanTask = Task { [weak self] in
            guard let self else { return }
            let discovery = await storefrontDiscovery.discover(
                for: selectedSeries,
                languages: scope.languageCodes,
                providers: Set(providers),
                includesSupplementalSources: includesSecondarySources,
                progress: { [weak self] event in
                    await self?.recordStorefrontScan(event)
                }
            )
            guard storefrontScanGeneration == scanGeneration else { return }
            let wasCancelled = Task.isCancelled
            let presentedSuggestions =
                SableMangaBakaStorefrontDiscovery.presentationSuggestions(
                from: discovery.suggestions
            )
            storefrontResultsAreLarge = presentedSuggestions.count > 80
            storefrontSuggestions = presentedSuggestions
            restorePersistedStorefrontRelationshipApprovals()
            storefrontNotes = discovery.notes
            updateStorefrontScanProviderSummaries(
                from: presentedSuggestions
            )

            let availableSuggestionIDs = Set(storefrontSuggestions.map(\.id))
            selectedStorefrontSuggestionIDs.formIntersection(availableSuggestionIDs)
            excludedStorefrontSuggestionIDs.formIntersection(
                availableSuggestionIDs
            )
            storefrontContentRatingOverrides = storefrontContentRatingOverrides
                .filter { availableSuggestionIDs.contains($0.key) }
            selectedStorefrontSuggestionIDs.formUnion(
                bestActionableStorefrontSuggestions(
                    from: storefrontSuggestions
                )
                    .map(\.id)
            )
            let imageIssueCount = discovery.suggestions.filter(
                \.imageNeedsReplacement
            ).count
            let usableImageCount =
                discovery.suggestions.count - imageIssueCount
            let imageIssueSuffix = imageIssueCount > 0
                ? " \(imageIssueCount) matched book record\(imageIssueCount == 1 ? " needs" : "s need") another image and remain unchecked."
                : ""
            let lowerResolutionCount = discovery.suggestions.filter {
                !$0.imageNeedsReplacement && !$0.reachesClinicMinimum
            }.count
            let qualitySuffix = lowerResolutionCount > 0
                ? " \(lowerResolutionCount) lower-resolution result\(lowerResolutionCount == 1 ? " can" : "s can") fill empty MangaBaka slots. Select Best never downgrades an existing cover; you can still choose a replacement manually."
                : ""
            let reviewCount = discovery.suggestions.filter {
                !$0.imageNeedsReplacement
                    && self.storefrontSuggestionNeedsReview($0)
            }.count
            let reviewSuffix = reviewCount > 0
                ? " \(reviewCount) series or numbering result\(reviewCount == 1 ? " needs" : "s need") your review and remain unchecked."
                : ""
            if wasCancelled {
                status = discovery.suggestions.isEmpty
                    ? "Storefront scan stopped before it found a usable cover."
                    : "Storefront scan stopped. Kept \(discovery.suggestions.count) matched cover record\(discovery.suggestions.count == 1 ? "" : "s"), including \(usableImageCount) usable image\(usableImageCount == 1 ? "" : "s").\(imageIssueSuffix)\(qualitySuffix)\(reviewSuffix)"
            } else {
                if discovery.suggestions.isEmpty {
                    status =
                        "The \(scope.searchDescription.lowercased()) scan found no compatible provider series or cover rows."
                } else {
                    status =
                        "Found \(discovery.suggestions.count) matched \(scope.searchDescription.lowercased()) storefront cover record\(discovery.suggestions.count == 1 ? "" : "s"), including \(usableImageCount) usable image\(usableImageCount == 1 ? "" : "s"). The best trusted gaps are checked; uncertain matches wait for you.\(imageIssueSuffix)\(qualitySuffix)\(reviewSuffix)"
                }
            }
            finishStorefrontScan(wasCancelled: wasCancelled)
            storefrontScanStopFallback?.cancel()
            storefrontScanStopFallback = nil
            isStoppingStorefrontScan = false
            isWorking = false
            storefrontScanTask = nil
        }
    }

    var availableStorefrontProviders:
        [SableLibraryBigBookCoversProvider] {
        SableMangaBakaStorefrontDiscovery.selectableProviders(
            for: storefrontScanScope.languageCodes
        )
        .filter { $0 != .amazonNetherlands }
    }

    var enabledStorefrontProviders:
        [SableLibraryBigBookCoversProvider] {
        availableStorefrontProviders.filter {
            !disabledStorefrontProviderIDs.contains($0.rawValue)
        }
    }

    var recommendedStorefrontProviders:
        [SableLibraryBigBookCoversProvider] {
        guard let selectedSeries else { return [] }
        return SableMangaBakaStorefrontDiscovery.recommendedProviders(
            for: storefrontScanScope.languageCodes,
            mediaType: selectedSeries.type
        )
        .filter {
            !disabledStorefrontProviderIDs.contains($0.rawValue)
        }
    }

    fileprivate var storefrontSourceGroups:
        [SableMangaBakaStorefrontSourceGroup] {
        Dictionary(
            grouping: storefrontSuggestions,
            by: storefrontReviewGroupID
        )
        .compactMap { groupID, suggestions in
            guard let suggestion = suggestions.first else { return nil }
            return SableMangaBakaStorefrontSourceGroup(
                id: groupID,
                language: suggestion.language,
                provider: suggestion.provider,
                coverType: suggestion.coverType,
                publicationType: suggestion.normalizedPublicationType,
                suggestions: suggestions.sorted {
                    $0.volumeNumber < $1.volumeNumber
                }
            )
        }
        .sorted {
            let lhsLanguage = normalizedStudioLanguage($0.language)
            let rhsLanguage = normalizedStudioLanguage($1.language)
            if lhsLanguage != rhsLanguage {
                return lhsLanguage < rhsLanguage
            }
            if $0.provider.discoveryPriority != $1.provider.discoveryPriority {
                return $0.provider.discoveryPriority
                    < $1.provider.discoveryPriority
            }
            if $0.coverType != $1.coverType {
                return $0.coverType < $1.coverType
            }
            return ($0.publicationType ?? "") < ($1.publicationType ?? "")
        }
    }

    private func rebuildStorefrontSuggestionCaches() {
        cachedMangaBakaSubmissionSuggestions =
            SableMangaBakaStorefrontDiscovery
            .mangaBakaSubmissionSuggestions(from: storefrontSuggestions)
        refreshStorefrontCompositeSlots()
    }

    private func refreshStorefrontCompositeSlots() {
        storefrontCompositeSlots =
            SableMangaBakaStorefrontDiscovery.compositeSlots(
                fromPreparedSuggestions:
                    cachedMangaBakaSubmissionSuggestions.filter {
                        !storefrontSuggestionIsExcluded($0)
                            && !storefrontRelationshipReviewIsRejected(for: $0)
                            && !$0.imageNeedsReplacement
                    },
                selectedSuggestionIDs: selectedStorefrontSuggestionIDs,
                manualReviewEvaluator: storefrontSuggestionNeedsReview
            )
    }

    var selectedMangaBakaStorefrontSuggestions:
        [SableMangaBakaStorefrontCoverSuggestion] {
        cachedMangaBakaSubmissionSuggestions.filter {
            !storefrontSuggestionIsExcluded($0)
                && !storefrontRelationshipReviewIsRejected(for: $0)
                && !$0.imageNeedsReplacement
                && selectedStorefrontSuggestionIDs.contains($0.id)
        }
    }

    func moveStorefrontCompositeWinner(
        _ slot: SableMangaBakaStorefrontCompositeSlot,
        offset: Int
    ) {
        guard slot.suggestions.count > 1 else { return }
        let nextIndex = (
            slot.winnerIndex + offset + slot.suggestions.count
        ) % slot.suggestions.count
        let suggestion = slot.suggestions[nextIndex]
        selectedStorefrontSuggestionIDs.subtract(
            slot.suggestions.map(\.id)
        )
        setStorefrontSuggestion(suggestion.id, isSelected: true)
        status =
            "Using \(suggestion.provider.displayName) for \(suggestion.numberedKindLabel)."
    }

    func storefrontCoverNote(
        for suggestion: SableMangaBakaStorefrontCoverSuggestion
    ) -> String {
        storefrontCoverNoteOverrides[suggestion.id] ?? ""
    }

    func setStorefrontCoverNote(
        _ note: String,
        for suggestion: SableMangaBakaStorefrontCoverSuggestion
    ) {
        storefrontStageSummary = nil
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            storefrontCoverNoteOverrides.removeValue(forKey: suggestion.id)
        } else {
            storefrontCoverNoteOverrides[suggestion.id] = note
        }
    }

    func setStorefrontProvider(
        _ provider: SableLibraryBigBookCoversProvider,
        isEnabled: Bool
    ) {
        if isEnabled {
            disabledStorefrontProviderIDs.remove(provider.rawValue)
        } else {
            disabledStorefrontProviderIDs.insert(provider.rawValue)
        }
        settings.saveDisabledCoverStorefrontProviderIDs(
            disabledStorefrontProviderIDs
        )
    }

    func setAllStorefrontProviders(isEnabled: Bool) {
        for provider in availableStorefrontProviders {
            if isEnabled {
                disabledStorefrontProviderIDs.remove(provider.rawValue)
            } else {
                disabledStorefrontProviderIDs.insert(provider.rawValue)
            }
        }
        settings.saveDisabledCoverStorefrontProviderIDs(
            disabledStorefrontProviderIDs
        )
    }

    func scanStoreSeriesURLs() {
        guard let selectedSeries, !isWorking else { return }
        let urls = storeSeriesURLs
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let recognizedStoreLinks = urls.compactMap {
            value -> (url: String, reference: SableMangaBakaStorefrontDiscovery.StoreSeriesReference)? in
            guard let reference = SableMangaBakaStorefrontDiscovery
                .storeSeriesReference(from: value) else {
                return nil
            }
            return (value, reference)
        }
        let references = recognizedStoreLinks.map(\.reference)
        let directCoverURLs = urls.compactMap(
            SableMangaBakaStorefrontDiscovery.directCoverURL
        )
        let unrecognizedCount = max(
            0,
            urls.count - references.count - directCoverURLs.count
        )
        guard !references.isEmpty || !directCoverURLs.isEmpty else {
            errorMessage =
                "Paste a supported store page or a direct cover image link."
            return
        }

        let providers = Array(Set(references.map(\.provider))).sorted {
            $0.discoveryPriority < $1.discoveryPriority
        }
        isWorking = true
        errorMessage = nil
        storefrontStageSummary = nil
        exactStoreSeriesOutcomes = []
        let scanGeneration: UUID?
        if references.isEmpty {
            storefrontScanClock?.cancel()
            storefrontScanClock = nil
            storefrontScanProgress = nil
            storefrontScanProgressAccumulator = nil
            scanGeneration = nil
        } else {
            scanGeneration = beginStorefrontScan(providers: providers)
        }
        var workLabels: [String] = []
        if !references.isEmpty {
            workLabels.append(
                "\(references.count) exact store link\(references.count == 1 ? "" : "s")"
            )
        }
        if !directCoverURLs.isEmpty {
            workLabels.append(
                "\(directCoverURLs.count) direct cover link\(directCoverURLs.count == 1 ? "" : "s")"
            )
        }
        status = "Checking \(workLabels.joined(separator: " and "))..."

        storefrontScanTask = Task { [weak self] in
            guard let self else { return }
            let discovery: SableMangaBakaStorefrontDiscoveryResult
            if references.isEmpty {
                discovery = SableMangaBakaStorefrontDiscoveryResult(
                    suggestions: [],
                    notes: []
                )
            } else {
                discovery = await storefrontDiscovery.discover(
                    storeSeriesURLs: recognizedStoreLinks.map(\.url),
                    for: selectedSeries,
                    progress: { [weak self] event in
                        await self?.recordStorefrontScan(event)
                    }
                )
            }
            let directInspections = directCoverURLs.isEmpty
                ? []
                : await storefrontDiscovery.inspectDirectCoverURLs(
                    directCoverURLs
                )
            if let scanGeneration,
               storefrontScanGeneration != scanGeneration {
                return
            }
            let wasCancelled = Task.isCancelled
            let replacedProviders = Set(
                references.filter {
                    $0.itemType != "book"
                        || ($0.provider == .kyobo
                            && $0.publicationTypeOverride == "digital")
                }.map(\.provider)
            )
            let replacedBookKeys = Set(
                references.filter {
                    $0.itemType == "book"
                        && !($0.provider == .kyobo
                            && $0.publicationTypeOverride == "digital")
                }.map {
                    "\($0.provider.rawValue):\($0.itemID.lowercased())"
                }
            )
            let removedSuggestionIDs = Set(
                storefrontSuggestions.filter { suggestion in
                    if replacedProviders.contains(suggestion.provider) {
                        return true
                    }
                    let itemID = suggestion.providerItemID?
                        .lowercased() ?? ""
                    return replacedBookKeys.contains(
                        "\(suggestion.provider.rawValue):\(itemID)"
                    )
                }
                .map(\.id)
            )
            let retained = storefrontSuggestions.filter {
                !removedSuggestionIDs.contains($0.id)
            }
            storefrontSuggestions =
                SableMangaBakaStorefrontDiscovery.presentationSuggestions(
                    from: retained + discovery.suggestions
                )
            restorePersistedStorefrontRelationshipApprovals()
            storefrontResultsAreLarge = storefrontSuggestions.count > 80
            storefrontNotes = Array(
                Set(storefrontNotes + discovery.notes)
            ).sorted()
            updateStorefrontScanProviderSummaries(
                from: storefrontSuggestions
            )
            exactStoreSeriesOutcomes = exactStoreSeriesOutcomeText(
                references: references,
                discovery: discovery,
                unrecognizedCount: unrecognizedCount
            )
            rememberDirectCoverInspections(directInspections)
            let directStage = stageCheckedPastedURLs(
                directCoverURLs,
                selectedSeries: selectedSeries,
                requiresInspection: true,
                updatesStatus: false
            )
            if !directCoverURLs.isEmpty {
                exactStoreSeriesOutcomes.append(
                    "Direct cover links: loaded \(directStage.added) maximum-quality image\(directStage.added == 1 ? "" : "s")\(directStage.unavailable > 0 ? "; \(directStage.unavailable) link\(directStage.unavailable == 1 ? " was" : "s were") not a readable image" : "")\(directStage.skipped > 0 ? "; \(directStage.skipped) duplicate or invalid link\(directStage.skipped == 1 ? " was" : "s were") skipped" : "")."
                )
            }

            let availableSuggestionIDs = Set(storefrontSuggestions.map(\.id))
            selectedStorefrontSuggestionIDs.formIntersection(
                availableSuggestionIDs
            )
            excludedStorefrontSuggestionIDs.formIntersection(
                availableSuggestionIDs
            )
            storefrontContentRatingOverrides = storefrontContentRatingOverrides
                .filter { availableSuggestionIDs.contains($0.key) }
            selectedStorefrontSuggestionIDs.subtract(
                removedSuggestionIDs
            )
            if wasCancelled {
                status = discovery.suggestions.isEmpty && directStage.added == 0
                    ? "Exact store scan stopped. Existing provider results were kept."
                    : "Link scan stopped. Kept \(discovery.suggestions.count + directStage.added) cover result\(discovery.suggestions.count + directStage.added == 1 ? "" : "s") found before stopping."
            } else if discovery.suggestions.isEmpty && directStage.added == 0 {
                status = exactStoreSeriesOutcomes.count == 1
                    ? exactStoreSeriesOutcomes[0]
                    : "The links contained no usable covers. See Exact Link Results for each reason."
            } else {
                var resultLabels: [String] = []
                if !discovery.suggestions.isEmpty {
                    resultLabels.append(
                        "\(discovery.suggestions.count) store cover\(discovery.suggestions.count == 1 ? "" : "s")"
                    )
                }
                if directStage.added > 0 {
                    resultLabels.append(
                        "\(directStage.added) direct cover\(directStage.added == 1 ? "" : "s")"
                    )
                }
                status = "Loaded \(resultLabels.joined(separator: " and ")). Store results are unchecked; direct images are in the proposed cover set. Review the cards before applying anything."
            }
            storeSeriesURLs = ""
            if scanGeneration != nil {
                finishStorefrontScan(wasCancelled: wasCancelled)
            }
            storefrontScanStopFallback?.cancel()
            storefrontScanStopFallback = nil
            isStoppingStorefrontScan = false
            isWorking = false
            storefrontScanTask = nil
        }
    }

    var canStopStorefrontScan: Bool {
        storefrontScanProgress?.isActive == true
            && storefrontScanTask != nil
    }

    func stopStorefrontScan() {
        guard canStopStorefrontScan, !isStoppingStorefrontScan else { return }
        isStoppingStorefrontScan = true
        status = "Stopping storefront scan and keeping the results found so far..."
        storefrontScanTask?.cancel()
        let stoppedGeneration = storefrontScanGeneration

        guard var progress = storefrontScanProgressAccumulator
            ?? storefrontScanProgress else {
            return
        }
        for provider in progress.activeProviders {
            progress.providerStates[provider] = "Stopping after the current request"
        }
        storefrontScanProgressAccumulator = progress
        storefrontScanProgress = progress
        lastStorefrontScanProgressPublishAt = Date()

        storefrontScanStopFallback?.cancel()
        storefrontScanStopFallback = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled,
                  let self,
                  isStoppingStorefrontScan,
                  storefrontScanGeneration == stoppedGeneration else {
                return
            }
            storefrontScanGeneration = UUID()
            finishStorefrontScan(wasCancelled: true)
            isStoppingStorefrontScan = false
            isWorking = false
            storefrontScanTask = nil
            storefrontScanStopFallback = nil
            status =
                "Storefront scan stopped. Unfinished provider requests were discarded."
        }
    }

    func pasteStoreSeriesURLs() {
        guard let value = NSPasteboard.general.string(forType: .string),
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "The clipboard does not contain a link."
            return
        }
        storeSeriesURLs = value
        status =
            "Links pasted. Check them, then choose Scan Links."
    }

    fileprivate var storefrontScanCompactSummary: String? {
        guard let progress = storefrontScanProgress else { return nil }
        var parts = [
            "\(progress.completedProviders) of \(progress.totalProviders) storefronts",
            "\(progress.inspectedImages) of \(progress.imageCandidates) images",
            "\(progress.acceptedImages) usable",
            "elapsed \(durationText(storefrontScanElapsedSeconds))"
        ]
        if let remaining = storefrontScanRemainingSeconds(progress) {
            parts.append("about \(durationText(remaining)) left")
        }
        return parts.joined(separator: " · ")
    }

    fileprivate var storefrontScanProviderRows: [(name: String, state: String)] {
        guard let progress = storefrontScanProgress else { return [] }
        return progress.providerOrder.map {
            ($0, progress.providerStates[$0] ?? "Waiting")
        }
    }

    @discardableResult
    private func beginStorefrontScan(
        providers: [SableLibraryBigBookCoversProvider]
    ) -> UUID {
        storefrontScanTask?.cancel()
        storefrontScanClock?.cancel()
        storefrontScanStopFallback?.cancel()
        storefrontScanStopFallback = nil
        let generation = UUID()
        storefrontScanGeneration = generation
        isStoppingStorefrontScan = false
        storefrontScanElapsedSeconds = 0
        storefrontScanProgress = SableMangaBakaStorefrontScanProgress(
            providerOrder: providers.map(\.displayName),
            providerStates: Dictionary(
                uniqueKeysWithValues: providers.map { ($0.displayName, "Waiting") }
            ),
            activeProviders: [],
            completedProviders: 0,
            totalProviders: providers.count,
            imageCandidates: 0,
            inspectedImages: 0,
            acceptedImages: 0,
            rejectedImages: 0,
            startedAt: Date(),
            isActive: true
        )
        storefrontScanProgressAccumulator = storefrontScanProgress
        lastStorefrontScanProgressPublishAt = Date()
        storefrontScanClock = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled,
                      let self,
                      let progress = self.storefrontScanProgress,
                      progress.isActive else {
                    return
                }
                self.storefrontScanElapsedSeconds = max(
                    0,
                    Int(Date().timeIntervalSince(progress.startedAt))
                )
            }
        }
        return generation
    }

    private func recordStorefrontScan(
        _ event: SableMangaBakaStorefrontDiscovery.ProgressEvent
    ) {
        guard var progress = storefrontScanProgressAccumulator
            ?? storefrontScanProgress else {
            return
        }
        guard progress.isActive else { return }
        let publishesImmediately: Bool
        switch event {
        case let .providerStarted(provider, query):
            progress.activeProviders.insert(provider.displayName)
            progress.totalProviders = max(
                progress.totalProviders,
                progress.completedProviders
                    + progress.activeProviders.count
            )
            progress.providerStates[provider.displayName] = query.map {
                "Searching for “\($0)”"
            } ?? "No suitable title to search"
            publishesImmediately = true

        case let .seriesCandidatesFound(provider, total, compatible):
            progress.providerStates[provider.displayName] =
                "Found \(total) series result\(total == 1 ? "" : "s"); \(compatible) compatible"
            publishesImmediately = true

        case let .coverCandidatesFound(provider, count):
            progress.imageCandidates += count
            progress.providerStates[provider.displayName] =
                "Checking \(count) cover image\(count == 1 ? "" : "s")"
            publishesImmediately = true

        case let .imageInspected(provider, accepted, width, height):
            progress.inspectedImages += 1
            if accepted {
                progress.acceptedImages += 1
            } else {
                progress.rejectedImages += 1
            }
            let dimensions = if let width, let height {
                "\(width) x \(height)"
            } else {
                "image unavailable"
            }
            progress.providerStates[provider.displayName] = accepted
                ? "Accepted \(dimensions)"
                : "Rejected \(dimensions)"
            publishesImmediately = false

        case let .providerFinished(provider, accepted, detail):
            progress.activeProviders.remove(provider.displayName)
            progress.completedProviders += 1
            progress.providerStates[provider.displayName] = accepted > 0
                ? "Done · \(accepted) usable cover\(accepted == 1 ? "" : "s")"
                : "Done · \(detail)"
            publishesImmediately = true
        }
        storefrontScanProgressAccumulator = progress

        let now = Date()
        guard publishesImmediately
            || now.timeIntervalSince(lastStorefrontScanProgressPublishAt) >= 0.25
        else {
            return
        }
        storefrontScanProgress = progress
        lastStorefrontScanProgressPublishAt = now
    }

    private func finishStorefrontScan(wasCancelled: Bool = false) {
        storefrontScanClock?.cancel()
        storefrontScanClock = nil
        guard var progress = storefrontScanProgressAccumulator
            ?? storefrontScanProgress else {
            return
        }
        progress.isActive = false
        if wasCancelled {
            for provider in progress.activeProviders {
                progress.providerStates[provider] = "Stopped"
            }
            for provider in progress.providerOrder
            where progress.providerStates[provider] == "Waiting" {
                progress.providerStates[provider] = "Not checked"
            }
        } else {
            for provider in progress.providerOrder
            where progress.providerStates[provider] == "Waiting" {
                progress.providerStates[provider] =
                    "Done · no matching store series"
            }
        }
        progress.activeProviders.removeAll()
        let terminalProviders = progress.providerOrder.filter {
            let state = progress.providerStates[$0] ?? ""
            return state.hasPrefix("Done")
                || state == "Stopped"
                || state == "Not checked"
        }.count
        progress.completedProviders = min(
            max(progress.completedProviders, terminalProviders),
            max(progress.totalProviders, progress.providerOrder.count)
        )
        progress.totalProviders = max(
            progress.totalProviders,
            progress.providerOrder.count
        )
        storefrontScanElapsedSeconds = max(
            storefrontScanElapsedSeconds,
            Int(Date().timeIntervalSince(progress.startedAt))
        )
        storefrontScanProgressAccumulator = progress
        storefrontScanProgress = progress
        lastStorefrontScanProgressPublishAt = Date()
    }

    private func updateStorefrontScanProviderSummaries(
        from suggestions: [SableMangaBakaStorefrontCoverSuggestion]
    ) {
        guard var progress = storefrontScanProgressAccumulator
            ?? storefrontScanProgress else {
            return
        }
        let grouped = Dictionary(grouping: suggestions, by: \.provider)
        for (provider, providerSuggestions) in grouped {
            var fronts = 0
            var backs = 0
            var digital = 0
            var audiobooks = 0
            var other = 0

            for suggestion in providerSuggestions {
                if suggestion.coverType == "volume_back" {
                    backs += 1
                } else if suggestion.coverType == "audiobook" {
                    audiobooks += 1
                } else if suggestion.normalizedPublicationType == "digital" {
                    digital += 1
                } else if suggestion.coverType == "volume" {
                    fronts += 1
                } else {
                    other += 1
                }
            }

            let details: [(Int, String)] = [
                (fronts, "front"),
                (backs, "back"),
                (digital, "digital"),
                (audiobooks, "audiobook"),
                (other, "other")
            ]
            let summary = details.compactMap { count, label in
                count > 0
                    ? "\(count) \(label)\(count == 1 ? "" : "s")"
                    : nil
            }
            .joined(separator: " · ")

            progress.providerStates[provider.displayName] =
                "Done · \(summary)"
        }
        storefrontScanProgressAccumulator = progress
        storefrontScanProgress = progress
    }

    private func storefrontScanRemainingSeconds(
        _ progress: SableMangaBakaStorefrontScanProgress
    ) -> Int? {
        guard progress.isActive,
              progress.completedProviders >= 4,
              progress.completedProviders < progress.totalProviders else {
            return nil
        }
        let completedBatches = progress.completedProviders / 4
        guard completedBatches > 0 else { return nil }
        let totalBatches = (progress.totalProviders + 3) / 4
        let remainingBatches = max(0, totalBatches - completedBatches)
        return Int(
            (Double(storefrontScanElapsedSeconds) / Double(completedBatches))
                * Double(remainingBatches)
        )
    }

    private func durationText(_ seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds)s"
        }
        let minutes = seconds / 60
        let remainder = seconds % 60
        return remainder == 0 ? "\(minutes)m" : "\(minutes)m \(remainder)s"
    }

    func setStorefrontSuggestion(_ id: String, isSelected: Bool) {
        storefrontStageSummary = nil
        guard let suggestion = storefrontSuggestions.first(where: { $0.id == id }),
              storefrontSuggestionCanBeManuallySelected(suggestion) else {
            selectedStorefrontSuggestionIDs.remove(id)
            return
        }
        if isSelected {
            let preparedSuggestion =
                SableMangaBakaStorefrontDiscovery
                    .mangaBakaSubmissionRepresentative(
                        for: suggestion,
                        among: storefrontSuggestions.filter(
                            storefrontSuggestionCanBeManuallySelected
                        )
                    ) ?? suggestion
            selectedStorefrontSuggestionIDs.remove(id)
            selectedStorefrontSuggestionIDs.insert(preparedSuggestion.id)
        } else {
            selectedStorefrontSuggestionIDs.remove(id)
        }
    }

    private func storefrontSelectionSlotID(
        _ suggestion: SableMangaBakaStorefrontCoverSuggestion
    ) -> String {
        [
            normalizedStudioLanguage(suggestion.language),
            suggestion.coverType,
            String(suggestion.volumeNumber)
        ]
        .joined(separator: ":")
    }

    func storefrontSuggestionCanBeManuallySelected(
        _ suggestion: SableMangaBakaStorefrontCoverSuggestion
    ) -> Bool {
        !storefrontSuggestionIsExcluded(suggestion)
            && !storefrontRelationshipReviewIsRejected(for: suggestion)
            && !suggestion.imageNeedsReplacement
    }

    func storefrontSuggestionIsExcluded(
        _ suggestion: SableMangaBakaStorefrontCoverSuggestion
    ) -> Bool {
        excludedStorefrontSuggestionIDs.contains(suggestion.id)
    }

    func setStorefrontSuggestionExcluded(
        _ suggestion: SableMangaBakaStorefrontCoverSuggestion,
        isExcluded: Bool
    ) {
        storefrontStageSummary = nil
        if isExcluded {
            excludedStorefrontSuggestionIDs.insert(suggestion.id)
            selectedStorefrontSuggestionIDs.remove(suggestion.id)
        } else {
            excludedStorefrontSuggestionIDs.remove(suggestion.id)
        }
    }

    func moveStorefrontSuggestionImage(
        _ suggestion: SableMangaBakaStorefrontCoverSuggestion,
        offset: Int
    ) {
        let choices = suggestion.availableImageChoices
        guard choices.count > 1 else { return }
        let nextIndex = (
            suggestion.activeImageChoiceIndex + offset + choices.count
        ) % choices.count
        setStorefrontSuggestionImage(
            suggestion,
            imageURL: choices[nextIndex].url
        )
    }

    func setStorefrontSuggestionImage(
        _ suggestion: SableMangaBakaStorefrontCoverSuggestion,
        imageURL: String
    ) {
        guard let index = storefrontSuggestions.firstIndex(
            where: { $0.id == suggestion.id }
        ) else {
            return
        }
        let current = storefrontSuggestions[index]
        let selectedIdentity = SableMangaBakaCoverSnapshot.coverURLIdentity(
            imageURL
        )
        guard let choice = current.availableImageChoices.first(where: {
            SableMangaBakaCoverSnapshot.coverURLIdentity($0.url)
                == selectedIdentity
        }) else {
            return
        }
        guard SableMangaBakaCoverSnapshot.coverURLIdentity(current.imageURL)
            != selectedIdentity else {
            return
        }

        var updated = current
        updated.imageURL = choice.url
        updated.imageChoices = current.availableImageChoices
        updated.width = choice.width
        updated.height = choice.height
        storefrontSuggestions[index] = updated
        migrateStorefrontSuggestionState(from: current, to: updated)
        storefrontStageSummary = nil
        errorMessage = nil
        status =
            "Using image \(updated.activeImageChoiceIndex + 1) of \(updated.imageChoiceCount) for \(updated.provider.displayName) \(updated.numberedKindLabel)."
    }

    func setStorefrontSuggestionsAsDigital(
        _ suggestions: [SableMangaBakaStorefrontCoverSuggestion],
        isDigital: Bool
    ) {
        let suggestionIDs = Set(suggestions.map(\.id))
        guard !suggestionIDs.isEmpty else { return }

        storefrontStageSummary = nil
        let groupStates = Dictionary(
            grouping: suggestions,
            by: storefrontReviewGroupID
        )
        .compactMap { oldGroupID, groupedSuggestions -> (
            old: String,
            new: String,
            approved: Bool,
            rejected: Bool,
            shareStatus: SableRolerMatchShareStatus?
        )? in
            guard let suggestion = groupedSuggestions.first else {
                return nil
            }
            return (
                old: oldGroupID,
                new: storefrontReviewGroupID(
                    language: suggestion.language,
                    provider: suggestion.provider,
                    coverType: suggestion.coverType,
                    publicationType: isDigital ? "digital" : nil,
                    providerSeriesID: suggestion.providerSeriesID
                ),
                approved:
                    approvedStorefrontReviewGroupIDs.contains(oldGroupID),
                rejected:
                    rejectedStorefrontReviewGroupIDs.contains(oldGroupID),
                shareStatus: rolerMatchShareStatuses[oldGroupID]
            )
        }

        for index in storefrontSuggestions.indices
        where suggestionIDs.contains(storefrontSuggestions[index].id) {
            let oldID = storefrontSuggestions[index].id
            storefrontSuggestions[index].publicationType =
                isDigital ? "digital" : nil
            let newID = storefrontSuggestions[index].id
            migrateStorefrontSuggestionState(from: oldID, to: newID)
        }

        for state in groupStates {
            approvedStorefrontReviewGroupIDs.remove(state.old)
            rejectedStorefrontReviewGroupIDs.remove(state.old)
            rolerMatchShareStatuses.removeValue(forKey: state.old)
            if state.approved {
                approvedStorefrontReviewGroupIDs.insert(state.new)
            }
            if state.rejected {
                rejectedStorefrontReviewGroupIDs.insert(state.new)
            }
            if let shareStatus = state.shareStatus {
                rolerMatchShareStatuses[state.new] = shareStatus
            }
        }
        selectedStorefrontSuggestionIDs.formIntersection(
            Set(storefrontSuggestions.map(\.id))
        )
        status = isDigital
            ? "Grouped these covers as Digital. They still compete for best quality unless you reject the group."
            : "Returned this cover group to the regular book-cover results."
    }

    func updateStorefrontSuggestionVolume(
        _ suggestion: SableMangaBakaStorefrontCoverSuggestion,
        volumeNumber: Double
    ) {
        guard volumeNumber.isFinite,
              volumeNumber >= 0,
              let index = storefrontSuggestions.firstIndex(
                where: { $0.id == suggestion.id }
              ) else {
            errorMessage = "Enter a valid cover number."
            return
        }
        guard abs(suggestion.volumeNumber - volumeNumber) >= 0.001 else {
            return
        }

        var corrected = suggestion
        corrected.volumeNumber = volumeNumber
        storefrontSuggestions[index] = corrected
        migrateStorefrontSuggestionState(from: suggestion, to: corrected)
        storefrontStageSummary = nil
        errorMessage = nil
        status = "Changed \(suggestion.provider.displayName) \(suggestion.numberedKindLabel) to \(corrected.numberedKindLabel)."
        stageRolerBookVolumeCorrection(corrected)
    }

    private func migrateStorefrontSuggestionState(
        from oldSuggestion: SableMangaBakaStorefrontCoverSuggestion,
        to newSuggestion: SableMangaBakaStorefrontCoverSuggestion
    ) {
        migrateStorefrontSuggestionState(
            from: oldSuggestion.id,
            to: newSuggestion.id
        )
        guard oldSuggestion.sourceIdentity != newSuggestion.sourceIdentity else {
            return
        }
        if let status = rolerBookCorrectionStatuses.removeValue(
            forKey: oldSuggestion.sourceIdentity
        ) {
            rolerBookCorrectionStatuses[newSuggestion.sourceIdentity] = status
        }
        if let correction = pendingRolerBookCorrections.removeValue(
            forKey: oldSuggestion.sourceIdentity
        ) {
            pendingRolerBookCorrections[newSuggestion.sourceIdentity] =
                correction
        }
    }

    private func migrateStorefrontSuggestionState(
        from oldID: String,
        to newID: String
    ) {
        guard oldID != newID else { return }
        if selectedStorefrontSuggestionIDs.remove(oldID) != nil {
            selectedStorefrontSuggestionIDs.insert(newID)
        }
        if excludedStorefrontSuggestionIDs.remove(oldID) != nil {
            excludedStorefrontSuggestionIDs.insert(newID)
        }
        if let rating = storefrontContentRatingOverrides.removeValue(
            forKey: oldID
        ) {
            storefrontContentRatingOverrides[newID] = rating
        }
        if let note = storefrontCoverNoteOverrides.removeValue(
            forKey: oldID
        ) {
            storefrontCoverNoteOverrides[newID] = note
        }
        if stagedStorefrontMappingSuggestionIDs.remove(oldID) != nil {
            stagedStorefrontMappingSuggestionIDs.insert(newID)
        }
    }

    private func stageRolerBookVolumeCorrection(
        _ suggestion: SableMangaBakaStorefrontCoverSuggestion
    ) {
        guard SableRolerContributorSharing.isEnabled else { return }
        let statusID = suggestion.sourceIdentity
        guard let providerID = suggestion.provider.rolerProviderID,
              let bookID = suggestion.providerItemID?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !bookID.isEmpty,
              let seriesID = suggestion.providerSeriesID?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !seriesID.isEmpty else {
            rolerBookCorrectionStatuses[statusID] = .localOnly(
                "The number is corrected here, but this source did not provide the BBC book IDs needed to sync it."
            )
            return
        }
        pendingRolerBookCorrections[statusID] =
            SableRolerBookVolumeCorrection(
            providerId: providerID,
            id: bookID,
            seriesId: seriesID,
            volumeNumber: suggestion.volumeNumber
        )
        rolerBookCorrectionStatuses[statusID] = .localOnly(
            "The corrected number will sync after MangaBaka accepts the cover submission request."
        )
    }

    func storefrontReviewGroupID(
        language: String,
        provider: SableLibraryBigBookCoversProvider,
        coverType: String = "volume",
        publicationType: String? = nil,
        providerSeriesID: String? = nil
    ) -> String {
        let normalizedPublicationType = publicationType?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let publicationGroup = normalizedPublicationType.flatMap {
            $0.isEmpty ? nil : $0
        } ?? "unspecified"
        let seriesGroup = providerSeriesID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let normalizedSeriesGroup = seriesGroup.flatMap {
            $0.isEmpty ? nil : $0
        } ?? "series-unspecified"
        return [
            normalizedStudioLanguage(language),
            provider.rawValue,
            coverType,
            publicationGroup,
            normalizedSeriesGroup
        ]
        .joined(separator: ":")
    }

    func storefrontReviewGroupID(
        for suggestion: SableMangaBakaStorefrontCoverSuggestion
    ) -> String {
        storefrontReviewGroupID(
            language: suggestion.language,
            provider: suggestion.provider,
            coverType: suggestion.coverType,
            publicationType: suggestion.normalizedPublicationType,
            providerSeriesID: suggestion.providerSeriesID
        )
    }

    func storefrontRelationshipReviewIsApproved(
        for suggestion: SableMangaBakaStorefrontCoverSuggestion
    ) -> Bool {
        guard !storefrontRelationshipReviewIsRejected(
            for: suggestion
        ) else {
            return false
        }
        return approvedStorefrontReviewGroupIDs.contains(
                storefrontReviewGroupID(for: suggestion)
            )
            || suggestion.qualifiesForAutomaticAcceptance
    }

    func storefrontRelationshipReviewIsAutomaticallyApproved(
        for suggestion: SableMangaBakaStorefrontCoverSuggestion
    ) -> Bool {
        suggestion.qualifiesForAutomaticAcceptance
            && !storefrontRelationshipReviewIsRejected(for: suggestion)
    }

    func storefrontReviewGroupIsAutomaticallyApproved(
        _ suggestions: [SableMangaBakaStorefrontCoverSuggestion]
    ) -> Bool {
        let relationshipReviews = suggestions.filter(
            \.requiresRelationshipReview
        )
        return !relationshipReviews.isEmpty
            && relationshipReviews.allSatisfy(
                storefrontRelationshipReviewIsAutomaticallyApproved
            )
    }

    func storefrontRelationshipReviewIsRejected(
        for suggestion: SableMangaBakaStorefrontCoverSuggestion
    ) -> Bool {
        rejectedStorefrontReviewGroupIDs.contains(
            storefrontReviewGroupID(for: suggestion)
        )
    }

    func setStorefrontRelationshipReviewApproved(
        language: String,
        provider: SableLibraryBigBookCoversProvider,
        coverType: String = "volume",
        publicationType: String? = nil,
        providerSeriesID: String? = nil,
        isApproved: Bool
    ) {
        storefrontStageSummary = nil
        let matchingSuggestions = storefrontRelationshipSuggestions(
            language: language,
            provider: provider,
            coverType: coverType,
            publicationType: publicationType,
            providerSeriesID: providerSeriesID
        )
        let groupIDs = Set(matchingSuggestions.map(storefrontReviewGroupID))
        let approvalSignatures = storefrontRelationshipApprovalSignatures(
            language: language,
            provider: provider,
            coverType: coverType,
            publicationType: publicationType,
            providerSeriesID: providerSeriesID
        )
        if isApproved {
            approvedStorefrontReviewGroupIDs.formUnion(groupIDs)
            rejectedStorefrontReviewGroupIDs.subtract(groupIDs)
            storefrontRelationshipApprovalStore.record(
                approvalSignatures
            )
            selectBestStorefrontSuggestions(
                from: matchingSuggestions
            )
        } else {
            approvedStorefrontReviewGroupIDs.subtract(groupIDs)
            storefrontRelationshipApprovalStore.remove(
                approvalSignatures
            )
            for groupID in groupIDs {
                rolerMatchShareStatuses.removeValue(forKey: groupID)
            }
            selectedStorefrontSuggestionIDs.subtract(
                matchingSuggestions
                    .filter(\.requiresRelationshipReview)
                    .map(\.id)
            )
        }
    }

    func restorePersistedStorefrontRelationshipApprovals() {
        guard let mangaBakaSeriesID = selectedSeries?.id else { return }
        let grouped = Dictionary(
            grouping: storefrontSuggestions,
            by: storefrontReviewGroupID
        )

        for (groupID, suggestions) in grouped
        where !rejectedStorefrontReviewGroupIDs.contains(groupID) {
            let signatures = Self.storefrontRelationshipApprovalSignatures(
                mangaBakaSeriesID: mangaBakaSeriesID,
                suggestions: suggestions
            )
            if storefrontRelationshipApprovalStore.containsAll(signatures) {
                approvedStorefrontReviewGroupIDs.insert(groupID)
            }
        }
    }

    private func storefrontRelationshipSuggestions(
        language: String,
        provider: SableLibraryBigBookCoversProvider,
        coverType: String,
        publicationType: String?,
        providerSeriesID: String? = nil
    ) -> [SableMangaBakaStorefrontCoverSuggestion] {
        let normalizedLanguage = normalizedStudioLanguage(language)
        let normalizedPublicationType = publicationType?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let normalizedSeriesID = providerSeriesID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return storefrontSuggestions.filter {
            $0.provider == provider
                && normalizedStudioLanguage($0.language)
                    == normalizedLanguage
                && $0.coverType == coverType
                && $0.normalizedPublicationType
                    == normalizedPublicationType
                && (
                    normalizedSeriesID == nil
                        || $0.providerSeriesID?
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .lowercased() == normalizedSeriesID
                )
        }
    }

    private func storefrontRelationshipApprovalSignatures(
        language: String,
        provider: SableLibraryBigBookCoversProvider,
        coverType: String,
        publicationType: String?,
        providerSeriesID: String? = nil
    ) -> Set<String> {
        guard let mangaBakaSeriesID = selectedSeries?.id else { return [] }
        return Self.storefrontRelationshipApprovalSignatures(
            mangaBakaSeriesID: mangaBakaSeriesID,
            suggestions: storefrontRelationshipSuggestions(
                language: language,
                provider: provider,
                coverType: coverType,
                publicationType: publicationType,
                providerSeriesID: providerSeriesID
            )
        )
    }

    static func storefrontRelationshipApprovalSignatures(
        mangaBakaSeriesID: Int,
        suggestions: [SableMangaBakaStorefrontCoverSuggestion]
    ) -> Set<String> {
        Set(
            suggestions.compactMap { suggestion -> String? in
                guard let providerSeriesID = suggestion.providerSeriesID?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                      !providerSeriesID.isEmpty else {
                    return nil
                }
                let components = [
                    String(mangaBakaSeriesID),
                    normalizedStudioLanguage(suggestion.language),
                    suggestion.provider.rawValue,
                    suggestion.coverType.lowercased(),
                    providerSeriesID.lowercased()
                ]
                return components
                    .map {
                        Data($0.utf8).base64EncodedString()
                    }
                    .joined(separator: ".")
            }
        )
    }

    func retryRolerMapping(
        language: String,
        provider: SableLibraryBigBookCoversProvider,
        coverType: String = "volume",
        publicationType: String? = nil
    ) {
        shareAcceptedStorefrontSeries(
            language: language,
            provider: provider,
            coverType: coverType,
            publicationType: publicationType
        )
    }

    private func shareAcceptedStorefrontSeries(
        language: String,
        provider: SableLibraryBigBookCoversProvider,
        coverType: String,
        publicationType: String?,
        confirmedProviderSeriesIDs: Set<String>? = nil
    ) {
        guard SableRolerContributorSharing.isEnabled,
              let selectedSeries,
              let rolerProviderID = provider.rolerProviderID else {
            return
        }
        let groupID = storefrontReviewGroupID(
            language: language,
            provider: provider,
            coverType: coverType,
            publicationType: publicationType
        )
        if rolerMatchShareStatuses[groupID] == .sharing {
            return
        }
        let providerSeriesIDs = confirmedProviderSeriesIDs ?? Set(
            storefrontSuggestions.compactMap { suggestion -> String? in
                guard suggestion.provider == provider,
                      normalizedStudioLanguage(suggestion.language)
                        == normalizedStudioLanguage(language),
                      suggestion.coverType == coverType,
                      suggestion.normalizedPublicationType
                        == publicationType?
                            .trimmingCharacters(
                                in: .whitespacesAndNewlines
                            )
                            .lowercased() else {
                    return nil
                }
                let seriesID = suggestion.providerSeriesID?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return seriesID?.isEmpty == false ? seriesID : nil
            }
        )
        guard !providerSeriesIDs.isEmpty else {
            rolerMatchShareStatuses[groupID] = .failed(
                "This source did not return a store-series ID to share."
            )
            return
        }

        let references =
            [
                SableRolerSeriesReference(
                    providerId: "mb",
                    id: String(selectedSeries.id)
                )
            ]
            + providerSeriesIDs.sorted().map {
                SableRolerSeriesReference(
                    providerId: rolerProviderID,
                    id: $0
                )
            }
        let signature = references
            .map { "\($0.providerId):\($0.id)" }
            .sorted()
            .joined(separator: "|")

        let credentials = settings.loadProviderCredentials()
            .rolerContributorCredentials
        guard credentials.isAvailable else {
            rolerMatchShareStatuses[groupID] = .failed(
                "Sign in to Roler in Settings to share this confirmed match."
            )
            return
        }

        rolerMatchShareStatuses[groupID] = .sharing
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await rolerContributorClient.mapSeries(
                    references,
                    credentials: credentials
                )
                await MainActor.run {
                    self.rolerMappingReceiptStore.record(signature)
                    self.rolerMatchShareStatuses[groupID] = .shared
                }
            } catch {
                await MainActor.run {
                    self.rolerMatchShareStatuses[groupID] = .failed(
                        error.localizedDescription
                    )
                }
            }
        }
    }

    func confirmedStorefrontSuggestionIDsForRoler() -> Set<String> {
        let grouped = Dictionary(
            grouping: storefrontSuggestions
        ) { suggestion in
            storefrontReviewGroupID(for: suggestion)
        }
        var confirmed = stagedStorefrontMappingSuggestionIDs

        for (groupID, suggestions) in grouped {
            if rejectedStorefrontReviewGroupIDs.contains(groupID) {
                confirmed.subtract(suggestions.map(\.id))
                continue
            }
            let explicitlyAccepted =
                approvedStorefrontReviewGroupIDs.contains(groupID)
            let confidentlyAccepted = suggestions.allSatisfy {
                !$0.requiresRelationshipReview
                    || $0.qualifiesForAutomaticAcceptance
            }
            if explicitlyAccepted || confidentlyAccepted {
                confirmed.formUnion(suggestions.map(\.id))
            }
        }

        return confirmed
    }

    func confirmedRolerBookCorrections()
        -> [String: SableRolerBookVolumeCorrection] {
        pendingRolerBookCorrections.filter { sourceID, _ in
            let matchingSuggestions = storefrontSuggestions.filter {
                $0.sourceIdentity == sourceID
            }
            return matchingSuggestions.isEmpty
                || matchingSuggestions.contains {
                    !storefrontRelationshipReviewIsRejected(for: $0)
                }
        }
    }

    static func confirmedStorefrontGroups(
        from suggestions: [SableMangaBakaStorefrontCoverSuggestion],
        selectedIDs: Set<String>
    ) -> [SableRolerConfirmedStorefrontGroup] {
        var groups:
            [String: SableRolerConfirmedStorefrontGroup] = [:]
        for suggestion in suggestions
        where selectedIDs.contains(suggestion.id) {
            guard suggestion.provider.rolerProviderID != nil,
                  let seriesID = suggestion.providerSeriesID?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !seriesID.isEmpty else {
                continue
            }
            let language = suggestion.language.lowercased()
            let key = [
                language,
                suggestion.provider.rawValue,
                suggestion.coverType,
                suggestion.normalizedPublicationType ?? "unspecified"
            ]
            .joined(separator: ":")
            if groups[key] == nil {
                groups[key] = SableRolerConfirmedStorefrontGroup(
                    language: language,
                    provider: suggestion.provider,
                    coverType: suggestion.coverType,
                    publicationType:
                        suggestion.normalizedPublicationType,
                    providerSeriesIDs: []
                )
            }
            groups[key]?.providerSeriesIDs.insert(seriesID)
        }
        return groups.values.sorted {
            (
                $0.language,
                $0.provider.discoveryPriority,
                $0.coverType,
                $0.publicationType ?? ""
            ) < (
                $1.language,
                $1.provider.discoveryPriority,
                $1.coverType,
                $1.publicationType ?? ""
            )
        }
    }

    static func confirmedRolerSeriesReferences(
        mangaBakaSeriesID: Int,
        groups: [SableRolerConfirmedStorefrontGroup]
    ) -> [SableRolerSeriesReference] {
        var references: Set<SableRolerSeriesReference> = [
            SableRolerSeriesReference(
                providerId: "mb",
                id: String(mangaBakaSeriesID)
            )
        ]
        for group in groups {
            guard let providerID = group.provider.rolerProviderID else {
                continue
            }
            for seriesID in group.providerSeriesIDs {
                let normalized = seriesID.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                guard !normalized.isEmpty else { continue }
                references.insert(
                    SableRolerSeriesReference(
                        providerId: providerID,
                        id: normalized
                    )
                )
            }
        }
        return references.sorted {
            ($0.providerId, $0.id) < ($1.providerId, $1.id)
        }
    }

    private static func rolerMappingSignature(
        _ references: [SableRolerSeriesReference]
    ) -> String {
        references
            .map { "\($0.providerId):\($0.id)" }
            .sorted()
            .joined(separator: "|")
    }

    private func rolerUploadSyncPlan() -> SableRolerUploadSyncPlan? {
        guard SableRolerContributorSharing.isEnabled,
              let selectedSeries else {
            return nil
        }
        let confirmedSuggestionIDs =
            confirmedStorefrontSuggestionIDsForRoler()
        let groups = Self.confirmedStorefrontGroups(
            from: storefrontSuggestions,
            selectedIDs: confirmedSuggestionIDs
        )
        let confirmedCorrections = confirmedRolerBookCorrections()
        guard !groups.isEmpty || !confirmedCorrections.isEmpty else {
            return nil
        }
        return SableRolerUploadSyncPlan(
            mangaBakaSeriesID: selectedSeries.id,
            groups: groups,
            corrections: confirmedCorrections
        )
    }

    private func syncRolerAfterSuccessfulSubmission(
        _ plan: SableRolerUploadSyncPlan
    ) async -> String? {
        let groups = plan.groups
        let correctionSourceIDs = Set(plan.corrections.keys)
        let corrections = correctionSourceIDs.compactMap {
            plan.corrections[$0]
        }
        let credentials = settings.loadProviderCredentials()
            .rolerContributorCredentials
        guard credentials.isAvailable else {
            for group in groups {
                rolerMatchShareStatuses[
                    storefrontReviewGroupID(
                        language: group.language,
                        provider: group.provider,
                        coverType: group.coverType,
                        publicationType: group.publicationType
                    )
                ] = .failed(
                    "Sign in to Roler in Settings to share this confirmed match."
                )
            }
            for sourceID in correctionSourceIDs {
                rolerBookCorrectionStatuses[sourceID] = .localOnly(
                    "MangaBaka accepted the cover. Sign in to Roler in Settings to share the corrected number."
                )
            }
            return "Roler was not synced because you are signed out."
        }

        var mappedSeriesCount = 0
        var correctedBookCount = 0
        var failures: [String] = []

        if !groups.isEmpty {
            let references = Self.confirmedRolerSeriesReferences(
                mangaBakaSeriesID: plan.mangaBakaSeriesID,
                groups: groups
            )
            let combinedSignature = Self.rolerMappingSignature(references)
            let groupIDs = groups.map {
                storefrontReviewGroupID(
                    language: $0.language,
                    provider: $0.provider,
                    coverType: $0.coverType,
                    publicationType: $0.publicationType
                )
            }
            for groupID in groupIDs {
                rolerMatchShareStatuses[groupID] = .sharing
            }
            do {
                _ = try await rolerContributorClient.mapSeries(
                    references,
                    credentials: credentials
                )
                rolerMappingReceiptStore.record(combinedSignature)
                for (group, groupID) in zip(groups, groupIDs) {
                    let groupReferences =
                        Self.confirmedRolerSeriesReferences(
                            mangaBakaSeriesID: plan.mangaBakaSeriesID,
                            groups: [group]
                        )
                    rolerMappingReceiptStore.record(
                        Self.rolerMappingSignature(groupReferences)
                    )
                    rolerMatchShareStatuses[groupID] = .shared
                }
                mappedSeriesCount = max(0, references.count - 1)
            } catch {
                for groupID in groupIDs {
                    rolerMatchShareStatuses[groupID] = .failed(
                        error.localizedDescription
                    )
                }
                failures.append(
                    "series mapping failed: \(error.localizedDescription)"
                )
            }
        }

        if !corrections.isEmpty {
            for sourceID in correctionSourceIDs {
                rolerBookCorrectionStatuses[sourceID] = .saving
            }
            do {
                _ = try await rolerContributorClient.editBookVolumes(
                    corrections,
                    credentials: credentials
                )
                for sourceID in correctionSourceIDs {
                    rolerBookCorrectionStatuses[sourceID] = .saved
                    pendingRolerBookCorrections.removeValue(
                        forKey: sourceID
                    )
                }
                correctedBookCount = corrections.count
            } catch {
                for sourceID in correctionSourceIDs {
                    rolerBookCorrectionStatuses[sourceID] = .failed(
                        error.localizedDescription
                    )
                }
                failures.append(
                    "volume corrections failed: \(error.localizedDescription)"
                )
            }
        }

        var completed: [String] = []
        if mappedSeriesCount > 0 {
            completed.append(
                "\(mappedSeriesCount) store series"
            )
        }
        if correctedBookCount > 0 {
            completed.append(
                "\(correctedBookCount) corrected volume number\(correctedBookCount == 1 ? "" : "s")"
            )
        }
        if failures.isEmpty {
            guard !completed.isEmpty else { return nil }
            return "Roler synced \(completed.joined(separator: " and "))."
        }
        let prefix = completed.isEmpty
            ? "Roler sync needs attention"
            : "Roler synced \(completed.joined(separator: " and ")), but"
        return "\(prefix) \(failures.joined(separator: "; "))."
    }

    func setStorefrontRelationshipReviewRejected(
        language: String,
        provider: SableLibraryBigBookCoversProvider,
        coverType: String = "volume",
        publicationType: String? = nil,
        providerSeriesID: String? = nil,
        isRejected: Bool
    ) {
        storefrontStageSummary = nil
        let matchingSuggestions = storefrontRelationshipSuggestions(
            language: language,
            provider: provider,
            coverType: coverType,
            publicationType: publicationType,
            providerSeriesID: providerSeriesID
        )
        let groupIDs = Set(matchingSuggestions.map(storefrontReviewGroupID))
        let approvalSignatures = storefrontRelationshipApprovalSignatures(
            language: language,
            provider: provider,
            coverType: coverType,
            publicationType: publicationType,
            providerSeriesID: providerSeriesID
        )
        if isRejected {
            rejectedStorefrontReviewGroupIDs.formUnion(groupIDs)
            approvedStorefrontReviewGroupIDs.subtract(groupIDs)
            storefrontRelationshipApprovalStore.remove(
                approvalSignatures
            )
            for groupID in groupIDs {
                rolerMatchShareStatuses.removeValue(forKey: groupID)
            }
            selectedStorefrontSuggestionIDs.subtract(
                matchingSuggestions
                    .map(\.id)
            )
        } else {
            rejectedStorefrontReviewGroupIDs.subtract(groupIDs)
        }
    }

    func storefrontSuggestionNeedsReview(
        _ suggestion: SableMangaBakaStorefrontCoverSuggestion
    ) -> Bool {
        suggestion.imageNeedsReplacement
            || suggestion.requiresNumberingReview
            || (
                suggestion.requiresRelationshipReview
                    && !storefrontRelationshipReviewIsApproved(for: suggestion)
            )
    }

    static func automaticallySelectedStorefrontSuggestions(
        from suggestions: [SableMangaBakaStorefrontCoverSuggestion]
    ) -> [SableMangaBakaStorefrontCoverSuggestion] {
        SableMangaBakaStorefrontDiscovery.preferredSuggestions(
            from: suggestions.filter {
                !$0.imageNeedsReplacement
                    && $0.contentRatingWasInferred
                    && !$0.requiresNumberingReview
                    && (
                        !$0.requiresRelationshipReview
                            || $0.qualifiesForAutomaticAcceptance
                    )
            }
        )
    }

    func storefrontContentRating(
        for suggestion: SableMangaBakaStorefrontCoverSuggestion
    ) -> String {
        storefrontContentRatingOverrides[suggestion.id]
            ?? suggestion.contentRating
    }

    func setStorefrontContentRating(
        _ rating: String,
        for suggestion: SableMangaBakaStorefrontCoverSuggestion
    ) {
        guard SableMangaBakaCoverImage.supportedRatings.contains(rating) else {
            return
        }
        storefrontContentRatingOverrides[suggestion.id] = rating
        storefrontStageSummary = nil
    }

    func bestActionableStorefrontSuggestions(
        from suggestions: [SableMangaBakaStorefrontCoverSuggestion]
    ) -> [SableMangaBakaStorefrontCoverSuggestion] {
        SableMangaBakaStorefrontDiscovery.preferredSuggestions(
            from: suggestions.filter {
                !storefrontSuggestionNeedsReview($0)
                    && !storefrontRelationshipReviewIsRejected(for: $0)
                    && storefrontSuggestionIsActionable($0)
            },
            manualReviewEvaluator: {
                self.storefrontSuggestionNeedsReview($0)
            }
        )
            .filter(storefrontSuggestionIsActionable)
    }

    func selectBestStorefrontSuggestions(
        from suggestions: [SableMangaBakaStorefrontCoverSuggestion]
    ) {
        storefrontStageSummary = nil
        replaceStorefrontSelections(
            in: suggestions,
            with: bestActionableStorefrontSuggestions(from: suggestions)
        )
    }

    func selectAllStorefrontSuggestions(
        from suggestions: [SableMangaBakaStorefrontCoverSuggestion]
    ) {
        storefrontStageSummary = nil
        let selectable = suggestions.filter {
            storefrontSuggestionCanBeManuallySelected($0)
                && !$0.imageNeedsReplacement
        }
        replaceStorefrontSelections(
            in: suggestions,
            with: SableMangaBakaStorefrontDiscovery.preferredSuggestions(
                from: selectable
            )
        )
    }

    private func replaceStorefrontSelections(
        in suggestions: [SableMangaBakaStorefrontCoverSuggestion],
        with replacements: [SableMangaBakaStorefrontCoverSuggestion]
    ) {
        let affectedSlots = Set(suggestions.map(storefrontSelectionSlotID))
        selectedStorefrontSuggestionIDs.subtract(
            storefrontSuggestions
                .filter {
                    affectedSlots.contains(storefrontSelectionSlotID($0))
                }
                .map(\.id)
        )
        selectedStorefrontSuggestionIDs.formUnion(replacements.map(\.id))
    }

    func hasAllStorefrontSuggestionSelection(
        in suggestions: [SableMangaBakaStorefrontCoverSuggestion]
    ) -> Bool {
        let preferredIDs = Set(
            SableMangaBakaStorefrontDiscovery.preferredSuggestions(
                from: suggestions.filter {
                    storefrontSuggestionCanBeManuallySelected($0)
                        && !$0.imageNeedsReplacement
                }
            )
            .map(\.id)
        )
        return !preferredIDs.isEmpty
            && preferredIDs.isSubset(of: selectedStorefrontSuggestionIDs)
    }

    func hasBestStorefrontSuggestionSelection(
        in suggestions: [SableMangaBakaStorefrontCoverSuggestion]
    ) -> Bool {
        let suggestionIDs = Set(suggestions.map(\.id))
        let selectedIDs = selectedStorefrontSuggestionIDs.intersection(
            suggestionIDs
        )
        let bestIDs = Set(
            bestActionableStorefrontSuggestions(from: suggestions).map(\.id)
        )
        return selectedIDs == bestIDs
    }

    func storefrontSuggestionIsActionable(
        _ suggestion: SableMangaBakaStorefrontCoverSuggestion
    ) -> Bool {
        guard !storefrontSuggestionIsExcluded(suggestion) else {
            return false
        }
        guard !storefrontRelationshipReviewIsRejected(for: suggestion) else {
            return false
        }
        guard !suggestion.imageNeedsReplacement else {
            return false
        }
        guard localDraftCover(
            language: suggestion.language,
            volumeNumber: suggestion.volumeNumber,
            coverType: suggestion.coverType
        ) != nil else {
            return true
        }
        guard let existing = publicMangaBakaCover(for: suggestion),
              let width = suggestion.width,
              let height = suggestion.height else {
            return false
        }
        if suggestion.coverType == "audiobook" {
            guard suggestion.reachesArchiveMinimum else {
                return false
            }
            let candidateIsPreferred = suggestion.reachesClinicMinimum
            let existingIsPreferred = existing.width >= 800
                && existing.height >= 800
                && existing.width * existing.height >= 850_000
            if candidateIsPreferred != existingIsPreferred {
                return candidateIsPreferred
            }
            return width * height > existing.width * existing.height
        }
        return SableLibraryCoverDownloadPlanner.coverDimensionsAreStrictQualityUpgrade(
            width: width,
            height: height,
            over: existing.width,
            baselineHeight: existing.height
        )
    }

    fileprivate func storefrontSuggestionComparisonKind(
        _ suggestion: SableMangaBakaStorefrontCoverSuggestion
    ) -> SableMangaBakaStorefrontComparisonKind {
        if selectedStorefrontSuggestionIDs.contains(suggestion.id),
           !storefrontSuggestionIsActionable(suggestion) {
            return .chosen
        }
        if storefrontSuggestionNeedsReview(suggestion)
            || storefrontSuggestionIsExcluded(suggestion)
            || storefrontRelationshipReviewIsRejected(for: suggestion)
            || suggestion.imageNeedsReplacement {
            return .review
        }
        guard localDraftCover(
            language: suggestion.language,
            volumeNumber: suggestion.volumeNumber,
            coverType: suggestion.coverType
        ) != nil else {
            return .newSlot
        }
        guard publicMangaBakaCover(for: suggestion) != nil,
              suggestion.width != nil,
              suggestion.height != nil else {
            return .unmeasured
        }
        return storefrontSuggestionIsActionable(suggestion)
            ? .upgrade
            : .current
    }

    func storefrontSuggestionComparisonText(
        _ suggestion: SableMangaBakaStorefrontCoverSuggestion
    ) -> String {
        if storefrontSuggestionIsExcluded(suggestion) {
            return "Excluded from this MangaBaka series"
        }
        if let imageIssueLabel = suggestion.imageIssueLabel {
            return imageIssueLabel
        }
        guard localDraftCover(
            language: suggestion.language,
            volumeNumber: suggestion.volumeNumber,
            coverType: suggestion.coverType
        ) != nil else {
            return "New MangaBaka cover slot"
        }
        let slot = suggestion.numberedKindLabel
        guard let existing = publicMangaBakaCover(for: suggestion) else {
            if selectedStorefrontSuggestionIDs.contains(suggestion.id) {
                return "Will replace existing MangaBaka \(slot) by your choice"
            }
            return "MangaBaka already has \(slot); its quality could not be measured, so it will stay unchanged"
        }
        guard let width = suggestion.width,
              let height = suggestion.height else {
            if selectedStorefrontSuggestionIDs.contains(suggestion.id) {
                return "Will replace existing MangaBaka \(slot) by your choice"
            }
            return "MangaBaka already has \(slot); the provider image could not be measured"
        }
        let isUpgrade: Bool
        if suggestion.coverType == "audiobook" {
            let candidateIsPreferred = suggestion.reachesClinicMinimum
            let existingIsPreferred = existing.width >= 800
                && existing.height >= 800
                && existing.width * existing.height >= 850_000
            isUpgrade = candidateIsPreferred != existingIsPreferred
                ? candidateIsPreferred
                : width * height > existing.width * existing.height
        } else {
            isUpgrade = SableLibraryCoverDownloadPlanner
                .coverDimensionsAreStrictQualityUpgrade(
                    width: width,
                    height: height,
                    over: existing.width,
                    baselineHeight: existing.height
                )
        }
        if isUpgrade {
            return "Upgrade existing MangaBaka \(slot) from \(existing.width) x \(existing.height) to \(width) x \(height)"
        }
        if selectedStorefrontSuggestionIDs.contains(suggestion.id) {
            return "Will replace existing MangaBaka \(slot) by your choice"
        }
        return "MangaBaka already has \(slot) at \(existing.width) x \(existing.height); equal or better"
    }

    @discardableResult
    func stageSelectedStorefrontCovers() -> Int {
        guard let selectedSeries else { return 0 }
        let selectedSuggestions = storefrontSuggestions.filter {
            selectedStorefrontSuggestionIDs.contains($0.id)
        }
        let chosen = selectedMangaBakaStorefrontSuggestions
        let repeatedChapterArtworkCount =
            selectedSuggestions.count - chosen.count
        guard !chosen.isEmpty else {
            errorMessage = "Select at least one provider cover first."
            return 0
        }
        let selectedCountBySlot = Dictionary(
            grouping: chosen,
            by: storefrontSelectionSlotID
        )
        .mapValues(\.count)
        let primarySuggestionIDs = Set(
            SableMangaBakaStorefrontDiscovery.preferredSuggestions(
                from: chosen
            )
            .map(\.id)
        )
        let orderedSuggestions =
            chosen.filter { primarySuggestionIDs.contains($0.id) }
            + chosen.filter { !primarySuggestionIDs.contains($0.id) }

        var added = 0
        var replaced = 0
        var reassigned = 0
        var unchanged = 0
        var changedSuggestions: [SableMangaBakaStorefrontCoverSuggestion] = []
        for suggestion in orderedSuggestions {
            guard storefrontSuggestionCanBeManuallySelected(suggestion) else {
                unchanged += 1
                continue
            }
            let normalizedURL =
                SableMangaBakaCoverSnapshot.coverURLIdentity(
                    suggestion.imageURL
                )
            let slotID = storefrontSelectionSlotID(suggestion)
            let shouldReplaceExistingSlot =
                selectedCountBySlot[slotID, default: 0] == 1
                || primarySuggestionIDs.contains(suggestion.id)

            if shouldReplaceExistingSlot,
               let originalDraftIndex = localDraftCoverIndex(
                language: suggestion.language,
                volumeNumber: suggestion.volumeNumber,
                coverType: suggestion.coverType
            ) {
                let duplicateIndices = draftImages.indices.filter {
                    $0 != originalDraftIndex
                        && SableMangaBakaCoverSnapshot.coverURLIdentity(
                            draftImages[$0].url
                        ) == normalizedURL
                }
                let duplicateWasDefault = duplicateIndices.contains {
                    draftImages[$0].isDefault
                }
                let removedBeforeTarget = duplicateIndices.filter {
                    $0 < originalDraftIndex
                }.count
                for duplicateIndex in duplicateIndices.sorted(by: >) {
                    draftImages.remove(at: duplicateIndex)
                }
                let draftIndex = originalDraftIndex - removedBeforeTarget
                let resolvedRating = resolvedStorefrontContentRating(
                    for: suggestion,
                    preserving: draftImages[draftIndex].contentRating
                )
                let resolvedNote = storefrontCoverNoteOverrides[suggestion.id]
                    ?? draftImages[draftIndex].note
                let changed =
                    SableMangaBakaCoverSnapshot.coverURLIdentity(
                        draftImages[draftIndex].url
                    ) != normalizedURL
                    || draftImages[draftIndex].contentRating != resolvedRating
                    || draftImages[draftIndex].note != resolvedNote
                    || !duplicateIndices.isEmpty
                guard changed else {
                    unchanged += 1
                    continue
                }
                draftImages[draftIndex].url = suggestion.imageURL
                draftImages[draftIndex].previewURL = suggestion.imageURL
                draftImages[draftIndex].contentRating = resolvedRating
                draftImages[draftIndex].note = resolvedNote
                draftImages[draftIndex].isDefault =
                    draftImages[draftIndex].isDefault || duplicateWasDefault
                replaced += 1
                changedSuggestions.append(suggestion)
                continue
            }

            let duplicateIndices = draftImages.indices.filter {
                SableMangaBakaCoverSnapshot.coverURLIdentity(
                    draftImages[$0].url
                ) == normalizedURL
            }
            let duplicateWasDefault = duplicateIndices.contains {
                draftImages[$0].isDefault
            }
            for duplicateIndex in duplicateIndices.sorted(by: >) {
                draftImages.remove(at: duplicateIndex)
            }
            let isFirstCover = draftImages.isEmpty || duplicateWasDefault
            draftImages.append(SableMangaBakaCoverImage(
                seriesID: selectedSeries.id,
                url: suggestion.imageURL,
                index: indexText(suggestion.volumeNumber),
                indexNumeric: suggestion.volumeNumber,
                language: normalizedStudioLanguage(suggestion.language),
                type: suggestion.coverType,
                note: storefrontCoverNoteOverrides[suggestion.id],
                contentRating: resolvedStorefrontContentRating(
                    for: suggestion
                ),
                isDefault: isFirstCover
            ))
            if duplicateIndices.isEmpty {
                added += 1
            } else {
                reassigned += 1
            }
            changedSuggestions.append(suggestion)
        }

        selectedStorefrontSuggestionIDs = []
        let preferredDefaultChanged = applyPreferredDefault(to: &draftImages)
        startIndex = max(
            startIndex,
            Int((draftImages.map(\.indexNumeric).max() ?? 0).rounded(.up)) + 1
        )
        invalidatePreview()
        errorMessage = nil
        let unchangedSummary = unchanged > 0
            ? " \(unchanged) selected cover\(unchanged == 1 ? "" : "s") already exactly matched \(unchanged == 1 ? "its" : "their") target \(unchanged == 1 ? "slot" : "slots")."
            : ""
        let addedSummary = added > 0
            ? "Added \(added) new cover\(added == 1 ? "" : "s"). "
            : ""
        let replacedSummary = replaced > 0
            ? "Replaced \(replaced) existing cover\(replaced == 1 ? "" : "s"). "
            : ""
        let reassignedSummary = reassigned > 0
            ? "Reassigned \(reassigned) existing cover\(reassigned == 1 ? "" : "s") to the selected \(reassigned == 1 ? "slot" : "slots"). "
            : ""
        let repeatedChapterSummary = repeatedChapterArtworkCount > 0
            ? " Kept only the earliest chapter for \(repeatedChapterArtworkCount) repeated chapter artwork entr\(repeatedChapterArtworkCount == 1 ? "y" : "ies")."
            : ""
        let preferredDefaultSummary = preferredDefaultChanged
            ? " Updated the default cover using the preferred language and cover-type order."
            : ""
        let changedCount = added + replaced + reassigned
            + (preferredDefaultChanged ? 1 : 0)
        storefrontStageSummary = changedCount > 0
            ? "\(addedSummary)\(replacedSummary)\(reassignedSummary)\(unchangedSummary)\(repeatedChapterSummary)\(preferredDefaultSummary)"
                .trimmingCharacters(in: .whitespaces)
            : "Every selected cover already exactly matches its target MangaBaka slot.\(repeatedChapterSummary)\(preferredDefaultSummary)"
        if !changedSuggestions.isEmpty {
            stagedStorefrontMappingSuggestionIDs.formUnion(
                changedSuggestions.map(\.id)
            )
            submissionNote = storefrontSubmissionComment(
                changedSuggestions,
                seriesTitle: selectedSeries.displayTitle
            )
        }
        if preferredDefaultChanged {
            submissionNote += submissionNote.isEmpty ? "" : " "
            submissionNote += "Updated the default cover using the preferred language and cover-type order."
        }
        let action = canApplyDirectly ? "direct apply" : "review submission"
        status = "\(storefrontStageSummary ?? "") Confirm the \(action) when you are ready."
        return changedCount
    }

    private func resolvedStorefrontContentRating(
        for suggestion: SableMangaBakaStorefrontCoverSuggestion,
        preserving existingRating: String? = nil
    ) -> String {
        if let override = storefrontContentRatingOverrides[suggestion.id] {
            return override
        }
        let suggested = storefrontContentRating(for: suggestion)
        guard let existingRating else { return suggested }
        let ratings = SableMangaBakaCoverImage.supportedRatings
        let existingRank = ratings.firstIndex(of: existingRating) ?? 0
        let suggestedRank = ratings.firstIndex(of: suggested) ?? 0
        return existingRank >= suggestedRank ? existingRating : suggested
    }

    private func localDraftCover(
        language: String,
        volumeNumber: Double,
        coverType: String
    ) -> SableMangaBakaCoverImage? {
        localDraftCoverIndex(
            language: language,
            volumeNumber: volumeNumber,
            coverType: coverType
        )
        .map { draftImages[$0] }
    }

    private func localDraftCoverIndex(
        language: String,
        volumeNumber: Double,
        coverType: String
    ) -> Int? {
        let normalizedLanguage = normalizedStudioLanguage(language)
        return draftImages.firstIndex {
            $0.type == coverType
                && normalizedStudioLanguage($0.language) == normalizedLanguage
                && abs($0.indexNumeric - volumeNumber) < 0.001
        }
    }

    private func publicMangaBakaCover(
        for suggestion: SableMangaBakaStorefrontCoverSuggestion
    ) -> SableMangaBakaPublicCoverImage? {
        let language = normalizedStudioLanguage(suggestion.language)
        let covers = mangaBakaLiveCovers.isEmpty
            ? mangaBakaVolumeCovers
            : mangaBakaLiveCovers
        return covers
            .filter {
                $0.type == suggestion.coverType
                    && normalizedStudioLanguage($0.language) == language
                    && abs($0.indexNumeric - suggestion.volumeNumber) < 0.001
            }
            .max {
                $0.width * $0.height < $1.width * $1.height
            }
    }

    func prepareStorefrontSubmission() -> Bool {
        if !selectedStorefrontSuggestionIDs.isEmpty {
            _ = stageSelectedStorefrontCovers()
        }
        guard let selectedSeries else {
            errorMessage = "Choose a MangaBaka series first."
            return false
        }
        guard hasDraftChanges else {
            errorMessage = "The proposed cover set does not change MangaBaka."
            return false
        }
        if submissionNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            submissionNote = "Updated the cover set for \(selectedSeries.displayTitle). Checked media type, language, volume order, and source URLs."
        }
        guard hasMangaBakaToken else {
            errorMessage = "Add your MangaBaka personal access token in Settings before submitting covers."
            return false
        }
        guard !isCheckingMangaBakaAccount else {
            errorMessage = "Sable is checking this MangaBaka account's permissions. Try again in a moment."
            return false
        }
        guard validationIssues.isEmpty else {
            errorMessage = "Fix the proposed cover set first: \(validationIssues.joined(separator: " "))"
            return false
        }
        errorMessage = nil
        return canSubmit
    }

    func stagePastedURLs() {
        guard let selectedSeries else { return }
        let urls = pastedURLs
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !urls.isEmpty else {
            errorMessage = "Paste one cover image URL per line."
            return
        }

        isWorking = true
        errorMessage = nil
        status = "Checking \(urls.count) direct cover link\(urls.count == 1 ? "" : "s")..."
        Task { [weak self] in
            guard let self else { return }
            let inspections = await storefrontDiscovery
                .inspectDirectCoverURLs(urls)
            rememberDirectCoverInspections(inspections)
            stageCheckedPastedURLs(
                urls,
                selectedSeries: selectedSeries
            )
            isWorking = false
        }
    }

    private func rememberDirectCoverInspections(
        _ inspections: [SableMangaBakaDirectCoverInspection]
    ) {
        for inspection in inspections {
            directCoverInspectionsByID[inspection.id] = inspection
            let resolvedID = SableMangaBakaCoverSnapshot.coverURLIdentity(
                inspection.url
            )
            directCoverInspectionsByID[resolvedID] = inspection
        }
    }

    @discardableResult
    private func stageCheckedPastedURLs(
        _ urls: [String],
        selectedSeries: SableMangaBakaSeriesSummary,
        requiresInspection: Bool = false,
        updatesStatus: Bool = true
    ) -> (added: Int, skipped: Int, unavailable: Int) {
        var existing = Set(
            draftImages.map {
                SableMangaBakaCoverSnapshot.coverURLIdentity($0.url)
            }
        )
        var nextIndex = Double(startIndex)
        var added = 0
        var skipped = 0
        var unavailable = 0
        for value in urls {
            let sourceIdentity = SableMangaBakaCoverSnapshot
                .coverURLIdentity(value)
            let inspection = directCoverInspectionsByID[sourceIdentity]
            if requiresInspection, inspection == nil {
                unavailable += 1
                continue
            }
            let resolvedURL = inspection?.url ?? value
            let resolvedIdentity = SableMangaBakaCoverSnapshot
                .coverURLIdentity(resolvedURL)
            guard URL(string: resolvedURL)?.host != nil,
                  !existing.contains(resolvedIdentity) else {
                skipped += 1
                continue
            }
            let isFirstCover = draftImages.isEmpty && added == 0
            let resolvedRating = inspection?.contentRatingWasInferred == true
                ? inspection?.contentRating ?? "suggestive"
                : "suggestive"
            draftImages.append(SableMangaBakaCoverImage(
                seriesID: selectedSeries.id,
                url: resolvedURL,
                index: indexText(nextIndex),
                indexNumeric: nextIndex,
                language: addedLanguage,
                type: addedType,
                note: addedNote.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                contentRating: resolvedRating,
                isDefault: isFirstCover
            ))
            existing.insert(resolvedIdentity)
            directCoverLinkIDs.insert(resolvedIdentity)
            nextIndex += 1
            added += 1
        }
        let preferredDefaultChanged = applyPreferredDefault(to: &draftImages)
        startIndex = Int(nextIndex)
        pastedURLs = ""
        invalidatePreview()
        if added > 0 {
            submissionNote = "Added \(added) exact cover URL\(added == 1 ? "" : "s") for \(selectedSeries.displayTitle). Checked language, cover type, volume order, and source URLs."
            if preferredDefaultChanged {
                submissionNote += " Updated the default cover using the preferred language and cover-type order."
            }
        }
        if updatesStatus {
            status = "Added \(added) cover link\(added == 1 ? "" : "s") to the proposed MangaBaka set\(skipped > 0 ? "; \(skipped) duplicate or invalid link\(skipped == 1 ? "" : "s") skipped" : "")\(unavailable > 0 ? "; \(unavailable) unreadable image link\(unavailable == 1 ? "" : "s") skipped" : ""). Review the cards, then confirm the MangaBaka submission when ready."
        }
        return (added, skipped, unavailable)
    }

    func pasteCoverURLs() {
        guard let value = NSPasteboard.general.string(forType: .string),
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "The clipboard does not contain cover image URLs."
            return
        }
        pastedURLs = value
        status = "Cover URLs pasted. Review their language, type, and starting volume before adding them."
    }

    func removeImage(at index: Int) {
        guard draftImages.indices.contains(index) else { return }
        let removedInspectionID = SableMangaBakaCoverSnapshot
            .coverURLIdentity(draftImages[index].url)
        let removedDefault = draftImages[index].isDefault
        draftImages.remove(at: index)
        if !draftImages.contains(where: {
            SableMangaBakaCoverSnapshot.coverURLIdentity($0.url)
                == removedInspectionID
        }) {
            directCoverInspectionsByID.removeValue(
                forKey: removedInspectionID
            )
            directCoverLinkIDs.remove(removedInspectionID)
        }
        if removedDefault, !draftImages.isEmpty {
            if !applyPreferredDefault(to: &draftImages) {
                setDefault(at: draftImages.startIndex)
            } else {
                invalidatePreview()
            }
        } else {
            invalidatePreview()
        }
    }

    func setDefault(at selectedIndex: Int) {
        guard draftImages.indices.contains(selectedIndex) else { return }
        for index in draftImages.indices {
            draftImages[index].isDefault = index == selectedIndex
        }
        invalidatePreview()
    }

    @discardableResult
    private func applyPreferredDefault(
        to images: inout [SableMangaBakaCoverImage]
    ) -> Bool {
        guard let selectedIndex =
            SableMangaBakaCoverSnapshot.preferredDefaultIndex(in: images)
        else {
            return false
        }
        let changed = images.indices.contains {
            images[$0].isDefault != ($0 == selectedIndex)
        }
        guard changed else { return false }
        for index in images.indices {
            images[index].isDefault = index == selectedIndex
        }
        return true
    }

    func imageChanged() {
        invalidatePreview()
    }

    func setDraftImageContentRating(
        at index: Int,
        to rating: String
    ) {
        guard draftImages.indices.contains(index),
              SableMangaBakaCoverImage.supportedRatings.contains(rating)
        else {
            return
        }
        let cover = draftImages[index]
        draftImages[index].contentRating = rating

        if let seriesID = cover.seriesID ?? selectedSeries?.id {
            SableCoverSafetyHumanMemory.shared.record(
                seriesID: seriesID,
                imageID: cover.id,
                sourceURL: cover.url,
                language: cover.language,
                type: cover.type,
                indexNumeric: cover.indexNumeric,
                rating: rating
            )
        }

        let correctionWasResolved = existingCoverSafetyCorrections.contains {
            $0.matches(cover)
        }
        existingCoverSafetyCorrections.removeAll { $0.matches(cover) }
        existingCoverSafetyCorrectionCount =
            existingCoverSafetyCorrections.count
        if correctionWasResolved {
            let remaining = existingCoverSafetyCorrectionCount
            status = remaining == 0
                ? "Recorded the human cover ratings. No safety changes remain to review."
                : "Recorded the human cover rating. \(remaining) safety change\(remaining == 1 ? "" : "s") remain to review."
        }
        imageChanged()
    }

    func setDraftImageNumber(
        at index: Int,
        to volumeNumber: Double
    ) {
        guard draftImages.indices.contains(index),
              volumeNumber.isFinite,
              volumeNumber >= 0 else {
            return
        }
        let label = indexText(volumeNumber)
        guard draftImages[index].indexNumeric != volumeNumber
                || draftImages[index].index != label else {
            return
        }
        draftImages[index].indexNumeric = volumeNumber
        draftImages[index].index = label
        imageChanged()
    }

    func directCoverInspection(
        for image: SableMangaBakaCoverImage
    ) -> SableMangaBakaDirectCoverInspection? {
        directCoverInspectionsByID[
            SableMangaBakaCoverSnapshot.coverURLIdentity(image.url)
        ]
    }

    func directCoverLinkIsImported(
        _ image: SableMangaBakaCoverImage
    ) -> Bool {
        directCoverLinkIDs.contains(
            SableMangaBakaCoverSnapshot.coverURLIdentity(image.url)
        )
    }

    func existingMangaBakaCover(
        for image: SableMangaBakaCoverImage
    ) -> SableMangaBakaPublicCoverImage? {
        let language = normalizedStudioLanguage(image.language)
        let covers = mangaBakaLiveCovers.isEmpty
            ? mangaBakaVolumeCovers
            : mangaBakaLiveCovers
        return covers
            .filter {
                $0.type == image.type
                    && normalizedStudioLanguage($0.language) == language
                    && abs($0.indexNumeric - image.indexNumeric) < 0.001
            }
            .max {
                $0.width * $0.height < $1.width * $1.height
            }
    }

    func submit(mode: SableMangaBakaSaveMode) {
        guard let snapshot = currentSnapshot, canSubmit else { return }
        isWorking = true
        errorMessage = nil
        status = mode == .review
            ? "Sending the cover correction to MangaBaka review..."
            : "Applying the cover correction directly..."
        Task {
            do {
                let result = try await client.submit(
                    snapshot: snapshot,
                    note: submissionNote,
                    mode: mode,
                    token: mangaBakaToken
                )
                let submissionStatus = mode == .review
                    ? "Submission \(result.submissionID) is \(result.status)."
                    : "Direct change \(result.submissionID) is \(result.status)."
                preview = nil
                let rolerPlan = rolerUploadSyncPlan()
                if rolerPlan != nil {
                    stagedStorefrontMappingSuggestionIDs = []
                }
                if let selectedSeries {
                    await load(
                        selectedSeries,
                        preservingStorefrontResults: true
                    )
                }
                lastSubmission = result
                let pendingStatus = rolerPlan == nil
                    ? submissionStatus
                    : "\(submissionStatus) Roler sync is continuing in the background."
                status = pendingStatus
                isWorking = false
                if let rolerPlan {
                    Task { [weak self] in
                        guard let self else { return }
                        let rolerStatus =
                            await self.syncRolerAfterSuccessfulSubmission(
                                rolerPlan
                            )
                        guard self.status == pendingStatus else { return }
                        self.status = [submissionStatus, rolerStatus]
                            .compactMap { $0 }
                            .joined(separator: " ")
                    }
                }
            } catch {
                finish(error)
            }
        }
    }

    func downloadCurrentSet(to destination: URL) {
        guard let selectedSeries, !draftImages.isEmpty, !isDownloading else { return }
        isDownloading = true
        downloadResult = nil
        status = "Downloading \(draftImages.count) MangaBaka cover image\(draftImages.count == 1 ? "" : "s")..."
        let images = draftImages
        Task {
            let result = await client.downloadImages(
                images,
                seriesID: selectedSeries.id,
                destination: destination
            )
            downloadResult = result
            status = "Downloaded \(result.saved.count); skipped \(result.skipped.count); failed \(result.failed.count)."
            isDownloading = false
        }
    }

    private var currentSnapshot: SableMangaBakaCoverSnapshot? {
        guard let selectedSeries, let snapshotVersion else { return nil }
        return SableMangaBakaCoverSnapshot(
            seriesID: selectedSeries.id,
            images: draftImages,
            version: snapshotVersion
        )
        .normalizedForSubmission()
    }

    private var mangaBakaToken: String {
        mangaBakaTokenCache
    }

    private func auditBrowseResults(
        _ series: [SableMangaBakaSeriesSummary]
    ) async -> [SableMangaBakaSeriesSummary] {
        let coverageLanguage = browseCoverageLanguage
        let needsExpectedCount = browseCoverFilter != .missingCover
            && coverageLanguage == .english
        let batchSize = browseCoverFilter == .missingCover ? 1 : 2
        for batchStart in stride(from: 0, to: series.count, by: batchSize) {
            let batch = Array(
                series[batchStart..<min(batchStart + batchSize, series.count)]
            )
            let values = await withTaskGroup(
                of: (Int, SableMangaBakaPublicCoverStats?, Int?).self
            ) { group in
                for item in batch {
                    group.addTask {
                        async let statsRequest = try? self.client.publicVolumeCoverStats(
                            seriesID: item.id
                        )
                        let expectedCount: Int?
                        if needsExpectedCount {
                            expectedCount = try? await self.client.publicExpectedMainVolumeCount(
                                seriesID: item.id,
                                language: coverageLanguage.code
                            )
                        } else {
                            expectedCount = nil
                        }
                        return (item.id, await statsRequest, expectedCount)
                    }
                }
                var results: [(Int, SableMangaBakaPublicCoverStats?, Int?)] = []
                for await result in group {
                    results.append(result)
                }
                return results
            }
            for (seriesID, stats, expectedCount) in values {
                if let stats {
                    coverStatsBySeriesID[seriesID] = stats
                    browseCoverStatsFailureIDs.remove(seriesID)
                } else {
                    browseCoverStatsFailureIDs.insert(seriesID)
                }
                if let expectedCount {
                    browseExpectedVolumeCountsBySeriesID[seriesID] = expectedCount
                }
            }
            if batchStart + batch.count < series.count {
                try? await Task<Never, Never>.sleep(nanoseconds: 200_000_000)
            }
        }
        return series
    }

    private func seriesNeedsCovers(_ series: SableMangaBakaSeriesSummary) -> Bool {
        browseCoverage(for: series)?.hasConfirmedGap == true
    }

    func browseCoverage(
        for series: SableMangaBakaSeriesSummary
    ) -> SableMangaBakaLanguageCoverCoverage? {
        guard let stats = coverStatsBySeriesID[series.id] else { return nil }
        let expectedCount: Int?
        switch browseCoverageLanguage {
        case .japanese:
            expectedCount = expectedVolumeCount(series.finalVolume)
        case .english:
            expectedCount = browseExpectedVolumeCountsBySeriesID[series.id]
        }
        return stats.coverage(
            language: browseCoverageLanguage.code,
            expectedVolumeCount: expectedCount
        )
    }

    func browseCoverageSummary(
        for series: SableMangaBakaSeriesSummary
    ) -> String? {
        guard let coverage = browseCoverage(for: series) else { return nil }
        let language = browseCoverageLanguage.title
        let expectedEvidence: String
        if let expected = coverage.expectedVolumeCount {
            if browseCoverageLanguage == .japanese {
                expectedEvidence = series.hasClosedVolumeCount
                    ? "\(expected) total on MangaBaka"
                    : "\(expected) currently listed on MangaBaka"
            } else {
                expectedEvidence = "\(expected) licensed releases on MangaBaka"
            }
        } else if browseCoverageLanguage == .english {
            expectedEvidence = "licensed total unknown"
        } else {
            expectedEvidence = "series total unknown"
        }

        if coverage.coveredIndices.isEmpty {
            return "\(language): no numbered volume covers · \(expectedEvidence)"
        }
        if !coverage.missingIndices.isEmpty {
            let missing = coverage.missingIndices.prefix(6).map(String.init).joined(
                separator: ", "
            )
            let remainder = coverage.missingIndices.count - min(
                coverage.missingIndices.count,
                6
            )
            let suffix = remainder > 0 ? " +\(remainder) more" : ""
            return "\(language): missing \(missing)\(suffix) · \(expectedEvidence)"
        }
        if coverage.isComplete {
            return "\(language): complete through \(coverage.expectedVolumeCount ?? 0) · \(expectedEvidence)"
        }
        return "\(language): \(coverage.coveredIndices.count) contiguous numbered cover\(coverage.coveredIndices.count == 1 ? "" : "s") · \(expectedEvidence)"
    }

    private func auditLocalSeries(
        _ local: SableMangaBakaLocalLibrarySeries
    ) async -> SableMangaBakaLibraryCoverAuditItem {
        guard !local.mangaBakaSeriesIDs.isEmpty else {
            return SableMangaBakaLibraryCoverAuditItem(
                localSeries: local,
                mangaBakaSeries: nil,
                coverStats: nil,
                status: .missingMangaBakaID,
                note: "No MangaBaka ID is saved."
            )
        }
        do {
            var firstSeries: SableMangaBakaSeriesSummary?
            var combinedCovers: [SableMangaBakaPublicCoverImage] = []
            var availableLanguages = Set<String>()

            for mangaBakaID in local.mangaBakaSeriesIDs {
                async let seriesRequest = client.series(id: mangaBakaID)
                async let statsRequest = client.publicVolumeCoverStats(
                    seriesID: mangaBakaID
                )
                let (series, stats) = try await (seriesRequest, statsRequest)
                firstSeries = firstSeries ?? series

                if !mediaTypesMatch(local: local.mediaType, mangaBaka: series.type) {
                    return SableMangaBakaLibraryCoverAuditItem(
                        localSeries: local,
                        mangaBakaSeries: series,
                        coverStats: stats,
                        status: .mediaTypeConflict,
                        note: "Local type is \(local.mediaType), but MangaBaka \(mangaBakaID) is \(series.type)."
                    )
                }

                availableLanguages.formUnion(stats.availableLanguages)
                let bundleMember = local.mangaBakaSeriesBundle?.members.first {
                    $0.seriesID == mangaBakaID
                }
                combinedCovers.append(contentsOf: stats.volumeCovers.compactMap {
                    cover in
                    guard let bundleMember else { return cover }
                    guard let libraryVolume = bundleMember.libraryVolume(
                        for: cover.indexNumeric
                    ) else {
                        return nil
                    }
                    var cover = cover
                    cover.indexNumeric = libraryVolume
                    return cover
                })
            }

            let coveredVolumes = Set(
                combinedCovers.compactMap { cover -> Int? in
                    let rounded = cover.indexNumeric.rounded()
                    guard rounded >= 1,
                          abs(cover.indexNumeric - rounded) < 0.001 else {
                        return nil
                    }
                    return Int(rounded)
                }
            )
            let stats = SableMangaBakaPublicCoverStats(
                volumeCoverCount: coveredVolumes.count,
                availableLanguages: availableLanguages.sorted(),
                volumeCovers: combinedCovers
            )

            if combinedCovers.isEmpty {
                return SableMangaBakaLibraryCoverAuditItem(
                    localSeries: local,
                    mangaBakaSeries: firstSeries,
                    coverStats: stats,
                    status: .noVolumeCovers,
                    note: "The saved MangaBaka series selection has no normal volume covers."
                )
            }
            if local.localBookCount > 0,
               coveredVolumes.count < local.localBookCount {
                return SableMangaBakaLibraryCoverAuditItem(
                    localSeries: local,
                    mangaBakaSeries: firstSeries,
                    coverStats: stats,
                    status: .fewerCoversThanLocalBooks,
                    note: "The saved MangaBaka series selection covers \(coveredVolumes.count) of \(local.localBookCount) local volumes."
                )
            }
            let localQualityUpgrades = SableMangaBakaLibraryScanner
                .coversThatBeatMangaBaka(
                    localCovers: local.localCovers,
                    mangaBakaCovers: stats.volumeCovers
                )
            if !localQualityUpgrades.isEmpty {
                let examples = localQualityUpgrades.prefix(3).map {
                    "\(normalizedStudioLanguage($0.language).uppercased()) volume \(indexText($0.indexNumeric)) (\($0.width) x \($0.height))"
                }
                return SableMangaBakaLibraryCoverAuditItem(
                    localSeries: local,
                    mangaBakaSeries: firstSeries,
                    coverStats: stats,
                    status: .localCoverQualityUpgrade,
                    note: "\(localQualityUpgrades.count) local cover\(localQualityUpgrades.count == 1 ? " is" : "s are") higher resolution than MangaBaka: \(examples.joined(separator: ", "))."
                )
            }
            return SableMangaBakaLibraryCoverAuditItem(
                localSeries: local,
                mangaBakaSeries: firstSeries,
                coverStats: stats,
                status: .covered,
                note: local.mangaBakaSeriesBundle == nil
                    ? "MangaBaka has \(stats.volumeCoverCount) normal volume covers."
                    : "The MangaBaka bundle covers the continuous local volume sequence."
            )
        } catch {
            return SableMangaBakaLibraryCoverAuditItem(
                localSeries: local,
                mangaBakaSeries: nil,
                coverStats: nil,
                status: .couldNotCheck,
                note: error.localizedDescription
            )
        }
    }

    private func mediaTypesMatch(local: String, mangaBaka: String) -> Bool {
        if local == "novel" {
            return mangaBaka == "novel"
        }
        if local == "manga" {
            return ["manga", "manhwa", "manhua", "oel"].contains(mangaBaka)
        }
        return true
    }

    private func expectedVolumeCount(_ value: String?) -> Int? {
        guard let value else { return nil }
        let digits = value.prefix { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        return Int(digits)
    }

    private func storefrontSubmissionComment(
        _ suggestions: [SableMangaBakaStorefrontCoverSuggestion],
        seriesTitle: String
    ) -> String {
        let sorted = suggestions.sorted {
            let leftLanguage = normalizedStudioLanguage($0.language)
            let rightLanguage = normalizedStudioLanguage($1.language)
            if leftLanguage != rightLanguage {
                return leftLanguage < rightLanguage
            }
            if $0.coverType != $1.coverType {
                return $0.coverType < $1.coverType
            }
            return $0.volumeNumber < $1.volumeNumber
        }
        var runs: [SableMangaBakaStorefrontCommentRun] = []
        for suggestion in sorted {
            let language = normalizedStudioLanguage(suggestion.language)
                .uppercased()
            let rating = storefrontContentRating(for: suggestion)
            if var previous = runs.last,
               previous.language == language,
               previous.coverType == suggestion.coverType,
               previous.provider == suggestion.provider,
               previous.rating == rating,
               previous.end.rounded() == previous.end,
               suggestion.volumeNumber.rounded() == suggestion.volumeNumber,
               suggestion.volumeNumber == previous.end + 1 {
                previous.end = suggestion.volumeNumber
                runs[runs.count - 1] = previous
            } else {
                runs.append(
                    SableMangaBakaStorefrontCommentRun(
                        language: language,
                        coverType: suggestion.coverType,
                        provider: suggestion.provider,
                        rating: rating,
                        start: suggestion.volumeNumber,
                        end: suggestion.volumeNumber
                    )
                )
            }
        }

        let commonRating = Set(runs.map(\.rating)).count == 1
            ? runs.first?.rating
            : nil
        let languages = Array(Set(runs.map(\.language))).sorted()
        let coverSummary = languages.map { language in
            let entries = runs
                .filter { $0.language == language }
                .map { run in
                    var entry = "\(commentIndexText(for: run)) \(run.provider.displayName)"
                    if commonRating == nil {
                        entry += " (\(run.rating))"
                    }
                    return entry
                }
                .joined(separator: ", ")
            return "\(language): \(entries)"
        }
        .joined(separator: "; ")
        let ratingSummary = commonRating.map {
            suggestions.count == 1
                ? " Cover marked \($0)."
                : " All covers marked \($0)."
        } ?? ""
        return "Updated cover\(suggestions.count == 1 ? "" : "s") for \(seriesTitle): \(coverSummary).\(ratingSummary) Checked media type, language, numbering, source URLs, and existing MangaBaka cover quality."
    }

    private func commentIndexText(
        for run: SableMangaBakaStorefrontCommentRun
    ) -> String {
        let prefix = switch run.coverType.lowercased() {
        case "volume": "v"
        case "chapter": "ch"
        case "audiobook": "audio "
        case "volume_back": "back v"
        default: "\(run.coverType) "
        }
        let start = indexText(run.start)
        guard run.end != run.start else {
            return "\(prefix)\(start)"
        }
        return "\(prefix)\(start)-\(indexText(run.end))"
    }

    private func exactStoreSeriesOutcomeText(
        references: [SableMangaBakaStorefrontDiscovery.StoreSeriesReference],
        discovery: SableMangaBakaStorefrontDiscoveryResult,
        unrecognizedCount: Int
    ) -> [String] {
        var seen: Set<String> = []
        var outcomes = references.compactMap { reference -> String? in
            let key = "\(reference.provider.rawValue):\(reference.itemID)"
            guard seen.insert(key).inserted else { return nil }

            let count = discovery.suggestions.filter { suggestion in
                guard suggestion.provider == reference.provider else {
                    return false
                }
                if reference.provider == .kyobo,
                   reference.publicationTypeOverride == "digital" {
                    return true
                }
                return reference.itemType == "book"
                    ? suggestion.providerItemID == reference.itemID
                    : suggestion.providerSeriesID == reference.itemID
            }.count
            if count > 0 {
                return "\(reference.provider.displayName) \(reference.itemID): manual relationship and media type accepted; \(count) usable book, audiobook, or chapter cover\(count == 1 ? "" : "s") shown below for your review."
            }

            let prefix = "\(reference.provider.displayName): "
            let detail = discovery.notes
                .first { $0.hasPrefix(prefix) }
                .map { String($0.dropFirst(prefix.count)) }
                ?? "No compatible book, audiobook, or chapter covers were found."
            return "\(reference.provider.displayName) \(reference.itemID): \(detail)"
        }
        if unrecognizedCount > 0 {
            outcomes.append(
                "\(unrecognizedCount) link\(unrecognizedCount == 1 ? " was" : "s were") not recognized as a BookLive, BookWalker, Amazon, Barnes & Noble, Audible, YES24, or Kyobo store page."
            )
        }
        return outcomes
    }

    private func invalidatePreview() {
        preview = nil
        lastSubmission = nil
    }

    private func finish(_ error: Error) {
        finishStorefrontScan()
        errorMessage = error.localizedDescription
        status = "MangaBaka Studio needs attention."
        isWorking = false
    }

    private func indexText(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(value)
    }

}

private func normalizedStudioLanguage(_ value: String) -> String {
    let normalized = value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
        .replacingOccurrences(of: "_", with: "-")
    let base = normalized.split(separator: "-").first.map(String.init) ?? ""
    switch base {
    case "jp": return "ja"
    case "kr": return "ko"
    case "cn": return "zh"
    case "": return "unknown"
    default: return base
    }
}

private struct SableMangaBakaStorefrontLanguageSection: Identifiable {
    var language: String
    var suggestions: [SableMangaBakaStorefrontCoverSuggestion]

    var id: String { language }

    var providerGroups: [SableMangaBakaStorefrontProviderGroup] {
        Dictionary(grouping: suggestions, by: \.provider)
            .map {
                SableMangaBakaStorefrontProviderGroup(
                    language: language,
                    provider: $0.key,
                    suggestions: $0.value.sorted {
                        if $0.coverType != $1.coverType {
                            return $0.coverType < $1.coverType
                        }
                        return $0.volumeNumber < $1.volumeNumber
                    }
                )
            }
            .sorted {
                $0.provider.discoveryPriority
                    < $1.provider.discoveryPriority
            }
    }
}

private struct SableMangaBakaStorefrontProviderGroup: Identifiable {
    var language: String
    var provider: SableLibraryBigBookCoversProvider
    var suggestions: [SableMangaBakaStorefrontCoverSuggestion]

    var id: String { "\(language):\(provider.rawValue)" }

    var laneSections: [SableMangaBakaStorefrontProviderSection] {
        Dictionary(grouping: suggestions) {
            SableMangaBakaStorefrontLane.classify($0)
        }
        .map {
            SableMangaBakaStorefrontProviderSection(
                language: language,
                lane: $0.key,
                provider: provider,
                suggestions: $0.value
            )
        }
        .sorted { $0.lane.sortOrder < $1.lane.sortOrder }
    }
}

private enum SableMangaBakaStorefrontLane: String, Comparable {
    case books
    case digitalEditions
    case backCovers
    case audiobooks
    case chapters
    case extras

    var title: String {
        switch self {
        case .books: "Book Covers"
        case .digitalEditions: "Digital Editions"
        case .backCovers: "Back Covers"
        case .audiobooks: "Audiobook Covers"
        case .chapters: "Chapter Covers"
        case .extras: "Other Covers"
        }
    }

    var systemImage: String {
        switch self {
        case .books: "books.vertical"
        case .digitalEditions: "ipad.and.iphone"
        case .backCovers: "rectangle.portrait.on.rectangle.portrait"
        case .audiobooks: "headphones"
        case .chapters: "doc.text.image"
        case .extras: "sparkles.rectangle.stack"
        }
    }

    var sortOrder: Int {
        switch self {
        case .books: 0
        case .digitalEditions: 1
        case .backCovers: 2
        case .audiobooks: 3
        case .chapters: 4
        case .extras: 5
        }
    }

    static func classify(
        _ suggestion: SableMangaBakaStorefrontCoverSuggestion
    ) -> Self {
        switch suggestion.coverType {
        case "volume":
            suggestion.isDigitalEdition ? .digitalEditions : .books
        case "volume_back": .backCovers
        case "audiobook": .audiobooks
        case "chapter": .chapters
        default: .extras
        }
    }

    static func < (
        lhs: SableMangaBakaStorefrontLane,
        rhs: SableMangaBakaStorefrontLane
    ) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

private struct SableMangaBakaStorefrontProviderSection: Identifiable {
    var language: String
    var lane: SableMangaBakaStorefrontLane
    var provider: SableLibraryBigBookCoversProvider
    var suggestions: [SableMangaBakaStorefrontCoverSuggestion]

    var id: String { "\(language):\(provider.rawValue):\(lane.rawValue)" }

    var reviewCoverType: String {
        suggestions.first?.coverType ?? "volume"
    }

    var reviewPublicationType: String? {
        suggestions.first?.normalizedPublicationType
    }
}

private struct SableMangaBakaStorefrontSourceGroup: Identifiable {
    var id: String
    var language: String
    var provider: SableLibraryBigBookCoversProvider
    var coverType: String
    var publicationType: String?
    var suggestions: [SableMangaBakaStorefrontCoverSuggestion]

    var representative: SableMangaBakaStorefrontCoverSuggestion? {
        suggestions.min {
            if $0.volumeNumber != $1.volumeNumber {
                return $0.volumeNumber < $1.volumeNumber
            }
            let lhsPixels = ($0.width ?? 0) * ($0.height ?? 0)
            let rhsPixels = ($1.width ?? 0) * ($1.height ?? 0)
            return lhsPixels > rhsPixels
        }
    }

    var releaseKindLabel: String {
        switch coverType {
        case "chapter": "Chapter series"
        case "volume": "Volume series"
        case "audiobook": "Audiobook series"
        case "volume_back": "Back-cover series"
        default: "Other cover series"
        }
    }

    var releaseKindSystemImage: String {
        switch coverType {
        case "chapter": "doc.text.image"
        case "audiobook": "headphones"
        case "volume_back": "rectangle.portrait.on.rectangle.portrait"
        default: "books.vertical"
        }
    }

    var releaseCountLabel: String {
        let noun = switch coverType {
        case "chapter": suggestions.count == 1 ? "chapter" : "chapters"
        case "volume": suggestions.count == 1 ? "volume" : "volumes"
        case "audiobook":
            suggestions.count == 1 ? "audiobook" : "audiobooks"
        case "volume_back":
            suggestions.count == 1 ? "back cover" : "back covers"
        default: suggestions.count == 1 ? "cover" : "covers"
        }
        return "\(suggestions.count) \(noun)"
    }

    var releaseKindHelp: String {
        switch coverType {
        case "chapter":
            "Individual chapter releases. MangaBaka prepares only the first chapter for each distinct cover artwork."
        case "volume":
            "Collected book volumes."
        case "audiobook":
            "Audiobook releases."
        case "volume_back":
            "Back-cover images for collected volumes."
        default:
            "The store did not provide a standard volume, chapter, or audiobook classification."
        }
    }
}

private enum SableMangaBakaCompositeReviewFilter: String, CaseIterable {
    case changes
    case all

    var title: String {
        switch self {
        case .changes: "Changes"
        case .all: "All"
        }
    }
}

private enum SableMangaBakaStorefrontComparisonKind {
    case newSlot
    case upgrade
    case current
    case review
    case unmeasured
    case chosen
}

private struct SableMangaBakaCoverNumberEditor: View {
    var coverType: String
    var value: Double
    var onCommit: (Double) -> Void

    @State private var draft: String
    @FocusState private var isFocused: Bool

    init(
        coverType: String,
        value: Double,
        onCommit: @escaping (Double) -> Void
    ) {
        self.coverType = coverType
        self.value = value
        self.onCommit = onCommit
        _draft = State(initialValue: Self.numberText(value))
    }

    var body: some View {
        HStack(spacing: 5) {
            Text(kindLabel)
                .font(.headline)
            TextField("Number", text: $draft)
                .textFieldStyle(.roundedBorder)
                .frame(width: 58)
                .focused($isFocused)
                .onSubmit(commit)
                .accessibilityLabel("\(kindLabel) number")
                .help("Correct the number before selecting this cover.")

            if hasUncommittedChange {
                Button(action: commit) {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(.borderless)
                .help("Use this \(kindLabel.lowercased()) number")
                .accessibilityLabel(
                    "Use \(kindLabel.lowercased()) number \(draft)"
                )
            }
        }
        .onChange(of: isFocused) { _, focused in
            if !focused {
                commit()
            }
        }
        .onChange(of: value) { _, newValue in
            if !isFocused {
                draft = Self.numberText(newValue)
            }
        }
    }

    private var kindLabel: String {
        switch coverType {
        case "chapter": "Chapter"
        case "audiobook": "Audiobook"
        case "volume_back": "Back Cover"
        case "special": "Special"
        default: "Volume"
        }
    }

    private var parsedValue: Double? {
        Double(
            draft
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: ",", with: ".")
        )
    }

    private var hasUncommittedChange: Bool {
        guard let parsedValue else { return !draft.isEmpty }
        return abs(parsedValue - value) >= 0.001
    }

    private func commit() {
        guard let parsedValue,
              parsedValue.isFinite,
              parsedValue >= 0 else {
            draft = Self.numberText(value)
            return
        }
        guard abs(parsedValue - value) >= 0.001 else {
            draft = Self.numberText(value)
            return
        }
        onCommit(parsedValue)
    }

    private static func numberText(_ value: Double) -> String {
        value.rounded() == value
            ? String(Int(value))
            : String(value)
    }
}

struct SableMangaBakaCoverStudioView: View {
    @Environment(\.sableLibraryPalette) private var palette
    @StateObject private var store = SableMangaBakaCoverStudioStore()
    @State private var showMangaBakaSubmissionConfirmation = false
    @State private var showStoreSeriesURLs = false
    @State private var showManualURLFallback = false
    @State private var showStorefrontNotes = false
    @State private var showStorefrontInspector = false
    @State private var showCurrentCoverSet = false
    @State private var showExistingCoverSafetyCorrections = false
    @State private var showScanDetails = false
    @State private var compositeReviewFilter:
        SableMangaBakaCompositeReviewFilter = .changes
    @State private var compositePage = 1
    @State private var collapsedStorefrontLanguageIDs: Set<String> = []
    @State private var expandedLargeStorefrontLanguageID: String?
    @State private var collapsedStorefrontProviderSectionIDs: Set<String> = []
    @State private var expandedLargeStorefrontProviderSectionIDs: Set<String> = []
    @State private var expandedStorefrontLanguageIDs: Set<String> = []
    @State private var expandedStorefrontProviderIDs: Set<String> = []
    @State private var expandedStorefrontLaneIDs: Set<String> = []
    @State private var expandedStorefrontImageIssueIDs: Set<String> = []
    @State private var expandedCoverInventoryGroupIDs: Set<String> = []
    @State private var expandedCoverInventoryLanguageIDs: Set<String> = []
    @State private var coverInventoryPageByLanguageID: [String: Int] = [:]
    @State private var contentRatingSuggestionID: String?

    private static let coverInventoryPageSize = 48

    var body: some View {
        HSplitView {
            searchSidebar
                .frame(minWidth: 300, idealWidth: 340, maxWidth: 420)

            detail
                .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
        }
        .confirmationDialog(
            store.canApplyDirectly
                ? "Apply directly to MangaBaka?"
                : "Submit these changes for review?",
            isPresented: $showMangaBakaSubmissionConfirmation
        ) {
            if store.canApplyDirectly {
                Button("Apply Directly", role: .destructive) {
                    store.submit(mode: .direct)
                }
            } else {
                Button("Submit for Review") {
                    store.submit(mode: .review)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(mangaBakaSubmissionConfirmationMessage)
        }
        .confirmationDialog(
            "Cover content rating",
            isPresented: Binding(
                get: { contentRatingSuggestionID != nil },
                set: {
                    if !$0 {
                        contentRatingSuggestionID = nil
                    }
                }
            )
        ) {
            if let suggestion = contentRatingSuggestion {
                ForEach(
                    SableMangaBakaCoverImage.supportedRatings,
                    id: \.self
                ) { rating in
                    Button(rating.capitalized) {
                        store.setStorefrontContentRating(
                            rating,
                            for: suggestion
                        )
                        contentRatingSuggestionID = nil
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                contentRatingSuggestionID = nil
            }
        } message: {
            Text(coverRatingHelp)
        }
        .sheet(isPresented: $showScanDetails) {
            storefrontScanDetailsSheet
        }
        .onAppear {
            store.refreshMangaBakaAccount()
        }
        .onChange(of: store.selectedSeries?.id) { _, _ in
            showCurrentCoverSet = false
            showExistingCoverSafetyCorrections = false
            expandedCoverInventoryGroupIDs.removeAll()
            expandedCoverInventoryLanguageIDs.removeAll()
            coverInventoryPageByLanguageID.removeAll()
            collapsedStorefrontLanguageIDs.removeAll()
            expandedLargeStorefrontLanguageID = nil
            collapsedStorefrontProviderSectionIDs.removeAll()
            expandedLargeStorefrontProviderSectionIDs.removeAll()
            expandedStorefrontLanguageIDs.removeAll()
            expandedStorefrontProviderIDs.removeAll()
            expandedStorefrontLaneIDs.removeAll()
            expandedStorefrontImageIssueIDs.removeAll()
            showStorefrontInspector = false
            compositeReviewFilter = .changes
            compositePage = 1
            contentRatingSuggestionID = nil
        }
        .onChange(of: store.isWorking) { _, isWorking in
            if isWorking {
                expandedLargeStorefrontLanguageID = nil
                collapsedStorefrontProviderSectionIDs.removeAll()
                expandedLargeStorefrontProviderSectionIDs.removeAll()
                expandedStorefrontLanguageIDs.removeAll()
                expandedStorefrontProviderIDs.removeAll()
                expandedStorefrontLaneIDs.removeAll()
                expandedStorefrontImageIssueIDs.removeAll()
                showStorefrontInspector = false
                compositePage = 1
            }
        }
        .onChange(of: compositeReviewFilter) { _, _ in
            compositePage = 1
        }
        .onChange(of: store.storefrontCompositeSlots.count) { _, _ in
            compositePage = 1
        }
        .onChange(of: store.coverInventoryLanguage) { _, _ in
            expandedCoverInventoryLanguageIDs.removeAll()
            coverInventoryPageByLanguageID.removeAll()
        }
        .onChange(of: store.existingCoverSafetyCorrectionCount) {
            _, correctionCount in
            if correctionCount == 0 {
                showExistingCoverSafetyCorrections = false
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            store.refreshMangaBakaAccount()
        }
    }

    private var searchSidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                if store.canGoBack {
                    Button {
                        store.goBack()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.borderless)
                    .keyboardShortcut("[", modifiers: .command)
                    .help("Go back")
                    .accessibilityLabel("Go back")
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("MangaBaka Studio")
                        .font(.title2.bold())
                    Text(sidebarSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Picker("Studio source", selection: $store.source) {
                ForEach(SableMangaBakaStudioSource.allCases) { source in
                    Text(source.title).tag(source)
                }
            }
            .pickerStyle(.segmented)
            .disabled(store.isWorking)

            switch store.source {
            case .manual:
                manualSearchControls
            case .library:
                libraryAuditControls
            case .browse:
                browseControls
            }

            Divider()

            if store.selectedSeries != nil {
                seriesFamilyList
            } else if store.source == .library {
                libraryAuditList
            } else {
                sidebarSearchFeedback
                seriesResultsList
            }
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var sidebarSearchFeedback: some View {
        if store.isWorking {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(store.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        } else if let error = store.errorMessage {
            Label {
                Text(error)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle")
            }
            .font(.caption)
            .foregroundStyle(palette.statusError)
        } else if store.status != "Search MangaBaka or paste a series URL." {
            Text(store.status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var sidebarSubtitle: String {
        switch store.source {
        case .manual: "Find one series"
        case .library: "Audit local series"
        case .browse: "Filter MangaBaka"
        }
    }

    private var manualSearchControls: some View {
        HStack(spacing: 8) {
            TextField("Title, series ID, or URL", text: $store.query)
                .textFieldStyle(.roundedBorder)
                .onSubmit(store.search)

            Button(action: store.search) {
                Image(systemName: "magnifyingglass")
            }
            .help("Search MangaBaka")
            .disabled(store.isWorking)
        }
    }

    private var libraryAuditControls: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.selectedLibraryURL?.lastPathComponent ?? "No library selected")
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Text(store.libraryAuditProgressText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button(action: store.scanLibrary) {
                    Label("Scan", systemImage: "books.vertical")
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.selectedLibraryURL == nil || store.isWorking)
            }

            Picker("Library results", selection: $store.libraryAuditFilter) {
                ForEach(SableMangaBakaLibraryAuditFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)

            if store.isWorking, store.libraryAuditTotal > 0 {
                ProgressView(
                    value: Double(store.libraryAuditCompleted),
                    total: Double(store.libraryAuditTotal)
                )
                .progressViewStyle(.linear)
                .accessibilityLabel("Library cover audit progress")
                .accessibilityValue(store.libraryAuditProgressText)
            }
        }
    }

    private var browseControls: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                TextField("Publisher, optional", text: $store.browsePublisher)
                    .textFieldStyle(.roundedBorder)

                Menu {
                    Section("Major English Publishers") {
                        ForEach(
                            [
                                "J-Novel Club",
                                "Yen Press",
                                "Seven Seas Entertainment",
                                "VIZ Media",
                                "Kodansha USA",
                                "Vertical Comics",
                                "SQUARE ENIX Manga",
                                "Cross Infinite World",
                                "One Peace Books",
                                "TOKYOPOP",
                                "Dark Horse Manga",
                                "DENPA",
                                "Titan Manga",
                                "UDON Entertainment",
                                "ABLAZE Manga",
                                "Hanashi Media",
                                "Kaiten Books",
                                "Star Fruit Books"
                            ],
                            id: \.self
                        ) { publisher in
                            Button(publisher) {
                                store.usePublisherPreset(publisher)
                            }
                        }
                    }
                    Section("Major Japanese Publishers") {
                        Button("Shueisha") {
                            store.usePublisherPreset("Shueisha")
                        }
                    }
                    Divider()
                    Button("Any Publisher") {
                        store.usePublisherPreset("")
                    }
                } label: {
                    Image(systemName: "building.2")
                }
                .help("Common publisher filters")
            }

            TextField("Optional title filter", text: $store.browseQuery)
                .textFieldStyle(.roundedBorder)
                .onSubmit { store.browse() }

            HStack(spacing: 8) {
                Label("Sort", systemImage: "arrow.up.arrow.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                Picker("Sort order", selection: $store.browseSort) {
                    ForEach(SableMangaBakaBrowseSort.allCases) { sort in
                        Text(sort.title).tag(sort)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .disabled(store.isWorking)
                .accessibilityLabel("Sort browse results")
                .onChange(of: store.browseSort) { _, _ in
                    guard store.source == .browse,
                          store.browseCatalogCountSummary != nil else {
                        return
                    }
                    store.browse()
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Media type")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Media type", selection: $store.browseMediaType) {
                    ForEach(SableMangaBakaBrowseMediaType.allCases) { type in
                        Text(type.title).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("License")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("License", selection: $store.browseLicenseFilter) {
                    ForEach(SableMangaBakaBrowseLicenseFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text("License status comes from MangaBaka. Publisher is an optional filter, not proof of licensing.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let summary = store.browseCatalogCountSummary {
                    Text(summary)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Cover state")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Cover state", selection: $store.browseCoverFilter) {
                    ForEach(SableMangaBakaBrowseCoverFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if store.browseCoverFilter == .missingCover {
                    Text(
                        "Shows series whose MangaBaka volume-cover result is empty. Checks one catalog page at a time."
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            if store.browseCoverFilter == .incompleteVolumes
                || store.browseCoverFilter == .unchecked {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Cover language")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Cover language", selection: $store.browseCoverageLanguage) {
                        ForEach(SableMangaBakaBrowseCoverageLanguage.allCases) { language in
                            Text(language.title).tag(language)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    Text(
                        store.browseCoverageLanguage == .japanese
                            ? "Compared with MangaBaka's current Japanese volume total."
                            : "Uses licensed English release totals when available; otherwise only visible numbering holes are reported."
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack {
                Button(action: { store.browse() }) {
                    Label("Browse", systemImage: "line.3.horizontal.decrease")
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.isWorking)

                Spacer()

                Button {
                    store.browsePreviousPage()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(store.isWorking || !store.browseHasPreviousPage)
                .help("Previous MangaBaka page")

                Text("\(store.browsePage)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Button {
                    store.browseNextPage()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(store.isWorking || !store.browseHasNextPage)
                .help("Next MangaBaka page")
            }
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private var seriesResultsList: some View {
        if store.results.isEmpty {
            ContentUnavailableView(
                "No Results",
                systemImage: "photo.on.rectangle.angled",
                description: Text(
                    store.source == .browse
                        ? "Choose catalog filters, then browse MangaBaka."
                        : "Search by title or paste a MangaBaka series URL."
                )
            )
        } else {
            List(store.results, selection: Binding(
                get: { store.selectedSeries?.id },
                set: { id in
                    guard let id,
                          let series = store.results.first(where: { $0.id == id }) else {
                        return
                    }
                    store.select(series)
                }
            )) { series in
                seriesResultRow(series)
                    .tag(series.id)
            }
            .listStyle(.sidebar)
        }
    }

    @ViewBuilder
    private var seriesFamilyList: some View {
        if let selectedSeries = store.selectedSeries {
            List {
                Section("Current Series") {
                    seriesFamilyRow(
                        selectedSeries,
                        relationship: nil,
                        isCurrent: true
                    )
                }

                Section {
                    if store.isLoadingRelatedSeries {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Loading MangaBaka relationships...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    } else if let message = store.relatedSeriesMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        ForEach(store.relatedSeries) { related in
                            Button {
                                store.select(related.series)
                            } label: {
                                seriesFamilyRow(
                                    related.series,
                                    relationship: related.relationType,
                                    isCurrent: false
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("Related Series")
                }
            }
            .listStyle(.sidebar)
        }
    }

    private func seriesFamilyRow(
        _ series: SableMangaBakaSeriesSummary,
        relationship: String?,
        isCurrent: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            coverThumbnail(series.coverURL, width: 38, height: 52)

            VStack(alignment: .leading, spacing: 3) {
                Text(series.displayTitle)
                    .font(.callout.weight(isCurrent ? .semibold : .medium))
                    .lineLimit(3)

                if let relationship {
                    Label(
                        relationshipDisplayName(relationship),
                        systemImage: relationshipSymbol(relationship)
                    )
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                }

                Text("\(series.type.capitalized) · MB \(series.id)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func relationshipDisplayName(_ value: String) -> String {
        switch value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_") {
        case "main", "main_story":
            "Main Story"
        case "adaptation":
            "Adaptation"
        case "prequel":
            "Prequel"
        case "sequel":
            "Sequel"
        case "spin_off", "spinoff":
            "Spin-off"
        case "side_story":
            "Side Story"
        case "contains":
            "Contains"
        case "contained_by":
            "Contained By"
        case "alternative", "alternate":
            "Alternative"
        default:
            value
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
        }
    }

    private func relationshipSymbol(_ value: String) -> String {
        switch value.lowercased() {
        case "main", "main_story":
            "arrow.up.left"
        case "adaptation":
            "arrow.triangle.branch"
        case "prequel":
            "backward.end"
        case "sequel":
            "forward.end"
        case "contains", "contained_by":
            "rectangle.on.rectangle"
        default:
            "link"
        }
    }

    @ViewBuilder
    private var libraryAuditList: some View {
        if store.filteredLibraryAuditItems.isEmpty {
            ContentUnavailableView(
                store.libraryAuditItems.isEmpty ? "Library Not Scanned" : "No Matching Gaps",
                systemImage: "books.vertical",
                description: Text(
                    store.libraryAuditItems.isEmpty
                        ? "Scan the selected library to compare local series with MangaBaka volume covers."
                        : "Try another library result filter."
                )
            )
        } else {
            List(store.filteredLibraryAuditItems) { item in
                Button {
                    store.openLibraryAuditItem(item)
                } label: {
                    libraryAuditRow(item)
                }
                .buttonStyle(.plain)
                .help(item.note)
            }
            .listStyle(.sidebar)
        }
    }

    private func seriesResultRow(_ series: SableMangaBakaSeriesSummary) -> some View {
        HStack(spacing: 10) {
            coverThumbnail(series.coverURL, width: 42, height: 58)
            VStack(alignment: .leading, spacing: 3) {
                Text(series.displayTitle)
                    .font(.callout.weight(.medium))
                    .lineLimit(3)
                if let scopeTitle = studioScopeTitle(for: series) {
                    Text(scopeTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Text("\(series.type.capitalized) · MB \(series.id)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if store.source == .browse,
                   let publicationDate = series.publicationDateLabel {
                    Label("Published \(publicationDate)", systemImage: "calendar")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if (store.browseCoverFilter == .incompleteVolumes
                    || store.browseCoverFilter == .unchecked),
                   let summary = store.browseCoverageSummary(for: series) {
                    Text(summary)
                        .font(.caption2)
                        .foregroundStyle(palette.statusWarning)
                        .lineLimit(3)
                } else if store.browseCoverStatsFailureIDs.contains(series.id) {
                    Label("Cover evidence unavailable", systemImage: "questionmark.circle")
                        .font(.caption2)
                        .foregroundStyle(palette.statusWarning)
                }
            }
        }
    }

    private func libraryAuditRow(
        _ item: SableMangaBakaLibraryCoverAuditItem
    ) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: libraryAuditSymbol(item.status))
                .foregroundStyle(
                    item.status == .covered ? palette.statusSuccess : palette.statusWarning
                )
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.localSeries.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(3)
                Text(libraryAuditLabel(item))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private func libraryAuditSymbol(
        _ status: SableMangaBakaLibraryCoverStatus
    ) -> String {
        switch status {
        case .missingMangaBakaID: "link.badge.plus"
        case .noVolumeCovers: "photo.badge.exclamationmark"
        case .fewerCoversThanLocalBooks: "rectangle.stack.badge.minus"
        case .localCoverQualityUpgrade: "arrow.up.right.square"
        case .mediaTypeConflict: "exclamationmark.triangle"
        case .covered: "checkmark.circle"
        case .couldNotCheck: "wifi.exclamationmark"
        }
    }

    private func libraryAuditLabel(
        _ item: SableMangaBakaLibraryCoverAuditItem
    ) -> String {
        switch item.status {
        case .missingMangaBakaID:
            return "\(item.localSeries.mediaType.capitalized) · no MangaBaka ID"
        case .noVolumeCovers:
            return "\(libraryMangaBakaIdentityLabel(item.localSeries)) · no volume covers"
        case .fewerCoversThanLocalBooks:
            return "\(item.coverStats?.volumeCoverCount ?? 0) MB covers · \(item.localSeries.localBookCount) local books"
        case .localCoverQualityUpgrade:
            return item.note
        case .mediaTypeConflict:
            return "\(item.localSeries.mediaType.capitalized) locally · \(item.mangaBakaSeries?.type.capitalized ?? "unknown") on MB"
        case .covered:
            return "\(item.coverStats?.volumeCoverCount ?? 0) volume covers"
        case .couldNotCheck:
            let detail = item.note.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty
                ? "MangaBaka did not return a readable result."
                : "MangaBaka check failed: \(detail)"
        }
    }

    private func libraryMangaBakaIdentityLabel(
        _ series: SableMangaBakaLocalLibrarySeries
    ) -> String {
        let ids = series.mangaBakaSeriesIDs
        if ids.count > 1 {
            return "\(ids.count) linked MB series"
        }
        if let id = ids.first {
            return "MB \(id)"
        }
        return "No MB ID"
    }

    @ViewBuilder
    private var detail: some View {
        if let selectedSeries = store.selectedSeries {
            VStack(spacing: 0) {
                studioHeader(selectedSeries)
                    .frame(maxWidth: 1180, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.bar)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        statusPanel
                        currentImagesPanel(selectedSeries)
                        storefrontDiscoveryPanel
                        storeSeriesURLsPanel
                        addURLsPanel
                    }
                    .padding(20)
                    .padding(.bottom, 20)
                    .frame(maxWidth: 1180, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .scrollIndicators(.visible)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if !store.storefrontSuggestions.isEmpty || store.hasDraftChanges {
                    storefrontPinnedApplyBar
                }
            }
        } else {
            ContentUnavailableView(
                emptyDetailTitle,
                systemImage: "rectangle.stack.badge.plus",
                description: Text(emptyDetailDescription)
            )
        }
    }

    private var emptyDetailTitle: String {
        switch store.source {
        case .manual: "Choose a MangaBaka Series"
        case .library: "Choose a Library Gap"
        case .browse: "Choose a Browse Result"
        }
    }

    private var emptyDetailDescription: String {
        switch store.source {
        case .manual:
            "Search for any MangaBaka series."
        case .library:
            "Scan the selected library, then open a series that needs cover attention."
        case .browse:
            "Filter MangaBaka by publisher and media type, including series outside your library."
        }
    }

    private var storefrontDiscoveryPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Label("Find Best Covers", systemImage: "sparkle.magnifyingglass")
                        .font(.headline)
                    Text("Sable checks the strongest sources for this language, merges matching series, and keeps one best image per cover number.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                HStack(spacing: 8) {
                    Picker("Provider language", selection: $store.storefrontScanScope) {
                        ForEach(
                            SableMangaBakaStorefrontScanScope.allCases.filter {
                                $0 != .dutch
                            }
                        ) { scope in
                            Text(scope.searchDescription).tag(scope)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 210)
                    .help("Choose which language storefronts to search. A new scan replaces the previous provider-result batch.")

                    Menu {
                        Button("Select All") {
                            store.setAllStorefrontProviders(isEnabled: true)
                        }
                        Button("Clear") {
                            store.setAllStorefrontProviders(isEnabled: false)
                        }

                        Divider()

                        ForEach(
                            store.availableStorefrontProviders,
                            id: \.rawValue
                        ) { provider in
                            let isEnabled =
                                !store.disabledStorefrontProviderIDs
                                    .contains(provider.rawValue)
                            Button {
                                store.setStorefrontProvider(
                                    provider,
                                    isEnabled: !isEnabled
                                )
                            } label: {
                                Label(
                                    provider.displayName,
                                    systemImage:
                                        isEnabled
                                            ? "checkmark.circle.fill"
                                            : "circle"
                                )
                            }
                        }
                    } label: {
                        Label(
                            "\(store.enabledStorefrontProviders.count)",
                            systemImage: "checklist"
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .help(
                        "Choose providers for this scan. Disabled providers stay off until you turn them on again."
                    )

                    if store.canStopStorefrontScan {
                        Button(
                            role: .destructive,
                            action: store.stopStorefrontScan
                        ) {
                            Label(
                                store.isStoppingStorefrontScan
                                    ? "Stopping..."
                                    : "Stop Scan",
                                systemImage: "stop.circle.fill"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(store.isStoppingStorefrontScan)
                        .help("Stop checking storefronts and keep every result found so far.")
                    } else {
                        Button(action: store.scanStorefronts) {
                            Label(
                                "Find Best",
                                systemImage: "magnifyingglass"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(
                            store.isWorking
                                || store.recommendedStorefrontProviders.isEmpty
                        )

                        Menu {
                            Button("Search More Sources") {
                                store.scanMoreStorefronts()
                            }
                            .disabled(store.enabledStorefrontProviders.isEmpty)
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .menuStyle(.borderlessButton)
                        .help("Replace this result set with every enabled source for the selected language.")
                    }
                }
            }

            if !store.exactStoreSeriesOutcomes.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 7) {
                    Label("Exact Link Results", systemImage: "link.circle")
                        .font(.callout.weight(.semibold))
                    ForEach(store.exactStoreSeriesOutcomes, id: \.self) { outcome in
                        Label(
                            outcome,
                        systemImage: outcome.contains("accepted;")
                                ? "checkmark.circle"
                                : "info.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if !store.storefrontSuggestions.isEmpty {
                storefrontSourceMatches

                HStack(spacing: 10) {
                    let selectedCount =
                        store.selectedMangaBakaStorefrontSuggestions.count
                    Label(
                        "\(selectedCount) selected",
                        systemImage: "checkmark.circle"
                    )
                    .font(.callout.weight(.medium))
                    .accessibilityLabel(
                        "\(selectedCount) MangaBaka covers selected"
                    )

                    Spacer()

                    Button("Select Missing & Upgrades") {
                        store.selectBestStorefrontSuggestions(
                            from: store.storefrontSuggestions
                        )
                    }
                    .disabled(
                        store.hasBestStorefrontSuggestionSelection(
                            in: store.storefrontSuggestions
                        )
                    )
                    .help("Select one best trusted cover for each language, cover type, and volume. Select Best never downgrades an existing MangaBaka cover; check a specific cover yourself when you intentionally want to replace it.")

                    Button("Clear All") {
                        store.storefrontStageSummary = nil
                        store.selectedStorefrontSuggestionIDs = []
                    }
                    .disabled(store.selectedStorefrontSuggestionIDs.isEmpty)
                    .help("Clear every provider-cover selection.")
                }
                .controlSize(.small)

                storefrontCompositeReview

                Button {
                    showStorefrontInspector.toggle()
                } label: {
                    HStack(spacing: 7) {
                        Image(
                            systemName: showStorefrontInspector
                                ? "chevron.down"
                                : "chevron.right"
                        )
                        .font(.caption.weight(.semibold))
                        .frame(width: 12)
                        Label(
                            "Inspect Sources",
                            systemImage: "wrench.and.screwdriver"
                        )
                        Spacer()
                        Text("\(store.storefrontSuggestions.count) records")
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .font(.callout.weight(.medium))

                if showStorefrontInspector {
                    ForEach(storefrontLanguageSections) { section in
                        storefrontLanguageSection(section)
                    }
                }
            } else if !store.isWorking {
                Text("Find the best covers first. Exact store pages and direct image links remain available below when a match needs help.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if !store.storefrontNotes.isEmpty {
                Button {
                    showStorefrontNotes.toggle()
                } label: {
                    HStack(spacing: 7) {
                        Image(
                            systemName:
                                showStorefrontNotes
                                    ? "chevron.down"
                                    : "chevron.right"
                        )
                        .font(.caption.weight(.semibold))
                        .frame(width: 12)
                        Text("Provider notes (\(store.storefrontNotes.count))")
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .font(.callout)
                .accessibilityLabel(
                    "\(showStorefrontNotes ? "Hide" : "Show") provider notes"
                )

                if showStorefrontNotes {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(store.storefrontNotes, id: \.self) { note in
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.top, 6)
                }
            }
        }
        .padding(16)
        .sableCoverDataSurface(fill: palette.surface, border: palette.border)
    }

    private var storefrontSourceMatches: some View {
        let languageGroups = Dictionary(
            grouping: store.storefrontSourceGroups
        ) {
            normalizedStudioLanguage($0.language)
        }
        .sorted {
            let lhsRank = studioLanguageRank($0.key)
            let rhsRank = studioLanguageRank($1.key)
            return lhsRank == rhsRank ? $0.key < $1.key : lhsRank < rhsRank
        }

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Source Matches", systemImage: "rectangle.stack.badge.checkmark")
                    .font(.headline)
                Spacer()
                Text("\(store.storefrontSourceGroups.count) matched series")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(languageGroups, id: \.key) { language, groups in
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 6) {
                        Text(studioLanguageName(language))
                            .font(.callout.weight(.semibold))
                        Text("\(groups.count)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }

                    SableEagerAdaptiveGrid(
                        minimumItemWidth: 250,
                        maximumItemWidth: 360,
                        horizontalSpacing: 8,
                        verticalSpacing: 8
                    ) {
                        ForEach(groups) { group in
                            storefrontSourceMatchTile(group)
                        }
                    }
                }
            }
        }
    }

    private func storefrontSourceMatchTile(
        _ group: SableMangaBakaStorefrontSourceGroup
    ) -> some View {
        let suggestion = group.representative
        let requiresReview = group.suggestions.contains(
            where: \.requiresRelationshipReview
        )
        let isRejected = suggestion.map {
            store.storefrontRelationshipReviewIsRejected(for: $0)
        } ?? false
        let isApproved = suggestion.map {
            store.storefrontRelationshipReviewIsApproved(for: $0)
        } ?? false

        return HStack(alignment: .top, spacing: 10) {
            coverThumbnail(
                suggestion.flatMap { URL(string: $0.imageURL) },
                width: 52,
                height: 74
            )

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(group.provider.displayName)
                        .font(.callout.weight(.semibold))
                    if let storeURL = suggestion?.storeURL,
                       let url = URL(string: storeURL) {
                        Link(destination: url) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.plain)
                        .help("Open this series at \(group.provider.displayName)")
                        .accessibilityLabel(
                            "Open this series at \(group.provider.displayName)"
                        )
                    }
                }
                Text(suggestion?.title ?? "Matched store series")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Label(
                        studioLanguageName(group.language),
                        systemImage: "character.book.closed"
                    )
                    Text(group.releaseCountLabel)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                Label(
                    group.releaseKindLabel,
                    systemImage: group.releaseKindSystemImage
                )
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .help(group.releaseKindHelp)

                if let suggestion {
                    Label(
                        suggestion.mediaTypeEvidenceLabel,
                        systemImage: suggestion.mediaTypeNeedsAttention
                            ? "exclamationmark.triangle"
                            : "checkmark.circle"
                    )
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(
                        suggestion.mediaTypeNeedsAttention
                            ? palette.statusWarning
                            : .secondary
                    )
                    .lineLimit(2)
                }

                if isRejected {
                    Button("Restore Match") {
                        store.setStorefrontRelationshipReviewRejected(
                            language: group.language,
                            provider: group.provider,
                            coverType: group.coverType,
                            publicationType: group.publicationType,
                            providerSeriesID: suggestion?.providerSeriesID,
                            isRejected: false
                        )
                    }
                    .controlSize(.small)
                } else if requiresReview, !isApproved {
                    HStack(spacing: 6) {
                        Button("Accept") {
                            store.setStorefrontRelationshipReviewApproved(
                                language: group.language,
                                provider: group.provider,
                                coverType: group.coverType,
                                publicationType: group.publicationType,
                                providerSeriesID: suggestion?.providerSeriesID,
                                isApproved: true
                            )
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Reject", role: .destructive) {
                            store.setStorefrontRelationshipReviewRejected(
                                language: group.language,
                                provider: group.provider,
                                coverType: group.coverType,
                                publicationType: group.publicationType,
                                providerSeriesID: suggestion?.providerSeriesID,
                                isRejected: true
                            )
                        }
                    }
                    .controlSize(.small)
                } else {
                    HStack(spacing: 8) {
                        Label(
                            isApproved ? "Accepted match" : "Matched",
                            systemImage: "checkmark.circle.fill"
                        )
                        .font(.caption.weight(.medium))
                        .foregroundStyle(palette.statusSuccess)

                        Button(
                            isApproved && requiresReview
                                ? "Unmatch"
                                : "Reject",
                            role: .destructive
                        ) {
                            store.setStorefrontRelationshipReviewRejected(
                                language: group.language,
                                provider: group.provider,
                                coverType: group.coverType,
                                publicationType: group.publicationType,
                                providerSeriesID: suggestion?.providerSeriesID,
                                isRejected: true
                            )
                        }
                        .controlSize(.small)
                        .help(
                            "Stop using this store series, clear its remembered acceptance, and remove its covers from the current best set. If this match was already synced to BBC, unmerge it on BBC as well."
                        )
                    }
                }
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, minHeight: 102, alignment: .topLeading)
        .sableCoverRowSurface(
            fill: palette.surfaceRaised,
            border: palette.border,
            accent: palette.accent,
            isSelected: isApproved && requiresReview
        )
        .opacity(isRejected ? 0.58 : 1)
    }

    @ViewBuilder
    private var storefrontCompositeReview: some View {
        let allSlots = store.storefrontCompositeSlots
        let filteredSlots = allSlots.filter {
            compositeReviewFilter == .all
                || store.storefrontSuggestionComparisonKind($0.winner)
                    != .current
        }
        let pageSize = 18
        let pageCount = max(
            1,
            Int(ceil(Double(filteredSlots.count) / Double(pageSize)))
        )
        let safePage = min(max(1, compositePage), pageCount)
        let startIndex = min(filteredSlots.count, (safePage - 1) * pageSize)
        let endIndex = min(filteredSlots.count, startIndex + pageSize)
        let pageSlots = Array(filteredSlots[startIndex..<endIndex])

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Label("Best Cover Set", systemImage: "rectangle.stack.fill")
                    .font(.headline)
                Text("\(filteredSlots.count) of \(allSlots.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Show covers", selection: $compositeReviewFilter) {
                    ForEach(
                        SableMangaBakaCompositeReviewFilter.allCases,
                        id: \.rawValue
                    ) {
                        Text($0.title).tag($0)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 150)
            }

            if pageSlots.isEmpty {
                ContentUnavailableView(
                    "No Cover Changes",
                    systemImage: "checkmark.circle",
                    description: Text(
                        "MangaBaka already has covers that are equal or better. Choose All to inspect the complete merged set."
                    )
                )
                .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                SableEagerAdaptiveGrid(
                    minimumItemWidth: 350,
                    maximumItemWidth: 520,
                    horizontalSpacing: 8,
                    verticalSpacing: 8
                ) {
                    ForEach(pageSlots) { slot in
                        storefrontCompositeTile(slot)
                    }
                }
            }

            if pageCount > 1 {
                HStack {
                    Spacer()
                    Button {
                        compositePage = max(1, safePage - 1)
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(safePage == 1)
                    .help("Previous cover page")

                    Text("Page \(safePage) of \(pageCount)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)

                    Button {
                        compositePage = min(pageCount, safePage + 1)
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(safePage == pageCount)
                    .help("Next cover page")
                    Spacer()
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func storefrontCompositeTile(
        _ slot: SableMangaBakaStorefrontCompositeSlot
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            storefrontSuggestionCompactTile(
                slot.winner,
                showsProvider: true
            )

            if slot.suggestions.count > 1 {
                HStack(spacing: 8) {
                    Button {
                        store.moveStorefrontCompositeWinner(slot, offset: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .help("Use the previous provider image for this cover.")

                    Text(
                        "\(slot.winnerIndex + 1) of \(slot.suggestions.count) sources"
                    )
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                    Button {
                        store.moveStorefrontCompositeWinner(slot, offset: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .help("Use the next provider image for this cover.")

                    Spacer()
                    Text(slot.winner.provider.displayName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    Menu {
                        ForEach(
                            slot.suggestions.filter {
                                $0.id != slot.winner.id
                            }
                        ) { suggestion in
                            let isSelected = store
                                .selectedStorefrontSuggestionIDs
                                .contains(suggestion.id)
                            Button {
                                store.setStorefrontSuggestion(
                                    suggestion.id,
                                    isSelected: !isSelected
                                )
                            } label: {
                                Label(
                                    suggestion.provider.displayName,
                                    systemImage: isSelected
                                        ? "checkmark.circle.fill"
                                        : "circle"
                                )
                            }
                            .disabled(
                                !store
                                    .storefrontSuggestionCanBeManuallySelected(
                                        suggestion
                                    )
                            )
                        }
                    } label: {
                        let additionalCount = slot.suggestions.filter {
                            $0.id != slot.winner.id
                                && store.selectedStorefrontSuggestionIDs
                                    .contains($0.id)
                        }.count
                        Label(
                            additionalCount > 0
                                ? "\(additionalCount) extra"
                                : "Editions",
                            systemImage: "square.stack.3d.up"
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help(
                        "Include another edition at the same language, type, and number. It will stay in the same MangaBaka cover slot."
                    )
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 10)
            }
        }
    }

    private func storefrontLanguageSection(
        _ section: SableMangaBakaStorefrontLanguageSection
    ) -> some View {
        let isExpanded = expandedStorefrontLanguageIDs.contains(section.id)
        let selectedCount = section.suggestions.filter {
            store.selectedStorefrontSuggestionIDs.contains($0.id)
        }.count

        return VStack(alignment: .leading, spacing: 10) {
            Button {
                if isExpanded {
                    expandedStorefrontLanguageIDs.remove(section.id)
                    expandedStorefrontProviderIDs = Set(
                        expandedStorefrontProviderIDs.filter {
                            !$0.hasPrefix("\(section.id):")
                        }
                    )
                    expandedStorefrontLaneIDs = Set(
                        expandedStorefrontLaneIDs.filter {
                            !$0.hasPrefix("\(section.id):")
                        }
                    )
                    expandedStorefrontImageIssueIDs = Set(
                        expandedStorefrontImageIssueIDs.filter {
                            !$0.hasPrefix("\(section.id):")
                        }
                    )
                } else {
                    expandedStorefrontLanguageIDs.insert(section.id)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(
                        systemName: isExpanded ? "chevron.down" : "chevron.right"
                    )
                    .font(.caption.weight(.semibold))
                    .frame(width: 12)

                    Text("\(studioLanguageName(section.language)) Covers")
                        .font(.headline)
                    Text(
                        "\(section.suggestions.count) result\(section.suggestions.count == 1 ? "" : "s")"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Text(
                        "\(section.providerGroups.count) provider\(section.providerGroups.count == 1 ? "" : "s")"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if selectedCount > 0 {
                        Label(
                            "\(selectedCount) selected",
                            systemImage: "checkmark.circle.fill"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.statusSuccess)
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                "\(isExpanded ? "Collapse" : "Expand") \(studioLanguageName(section.language)) covers"
            )

            if isExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Spacer()

                        Button("Select Best") {
                            store.selectBestStorefrontSuggestions(
                                from: section.suggestions
                            )
                        }
                        .disabled(
                            store.hasBestStorefrontSuggestionSelection(
                                in: section.suggestions
                            )
                        )
                        .help(
                            "Select one best trusted \(studioLanguageName(section.language).lowercased()) cover for each cover type and volume. Select Best never downgrades an existing MangaBaka cover; check a specific cover yourself when you intentionally want to replace it."
                        )

                        Button("Clear") {
                            store.storefrontStageSummary = nil
                            store.selectedStorefrontSuggestionIDs.subtract(
                                section.suggestions.map(\.id)
                            )
                        }
                        .disabled(!section.suggestions.contains {
                            store.selectedStorefrontSuggestionIDs.contains($0.id)
                        })
                        .help(
                            "Clear the \(studioLanguageName(section.language).lowercased()) selections."
                        )
                    }

                    ForEach(section.providerGroups) { providerGroup in
                        storefrontProviderGroup(providerGroup)
                    }
                }
                .padding(.top, 10)
                .padding(.leading, 22)
            }
        }
    }

    @ViewBuilder
    private func storefrontProviderGroup(
        _ group: SableMangaBakaStorefrontProviderGroup
    ) -> some View {
        let selectedCount = group.suggestions.filter {
            store.selectedStorefrontSuggestionIDs.contains($0.id)
        }.count
        let reviewCount = group.suggestions.filter(
            store.storefrontSuggestionNeedsReview
        ).count
        let isExpanded = expandedStorefrontProviderIDs.contains(group.id)

        VStack(alignment: .leading, spacing: 10) {
            Button {
                if isExpanded {
                    expandedStorefrontProviderIDs.remove(group.id)
                    expandedStorefrontLaneIDs = Set(
                        expandedStorefrontLaneIDs.filter {
                            !$0.hasPrefix("\(group.id):")
                        }
                    )
                    expandedStorefrontImageIssueIDs = Set(
                        expandedStorefrontImageIssueIDs.filter {
                            !$0.hasPrefix("\(group.id):")
                        }
                    )
                } else {
                    expandedStorefrontProviderIDs.insert(group.id)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(
                        systemName: isExpanded ? "chevron.down" : "chevron.right"
                    )
                    .font(.caption.weight(.semibold))
                    .frame(width: 12)

                    Text(group.provider.displayName)
                        .font(.callout.weight(.semibold))
                    Text(
                        "\(group.suggestions.count) cover\(group.suggestions.count == 1 ? "" : "s")"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if reviewCount > 0 {
                        Label(
                            "\(reviewCount) to review",
                            systemImage: "questionmark.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(palette.statusWarning)
                    }

                    if selectedCount > 0 {
                        Label(
                            "\(selectedCount) selected",
                            systemImage: "checkmark.circle.fill"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.statusSuccess)
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                "\(isExpanded ? "Collapse" : "Expand") \(group.provider.displayName)"
            )
            .help(
                "\(isExpanded ? "Hide" : "Load") \(group.provider.displayName) covers"
            )

            if isExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Spacer()

                        Button("Select Best") {
                            store.selectBestStorefrontSuggestions(
                                from: group.suggestions
                            )
                        }
                        .disabled(
                            store.hasBestStorefrontSuggestionSelection(
                                in: group.suggestions
                            )
                        )

                        Button("Clear") {
                            store.storefrontStageSummary = nil
                            store.selectedStorefrontSuggestionIDs.subtract(
                                group.suggestions.map(\.id)
                            )
                        }
                        .disabled(!group.suggestions.contains {
                            store.selectedStorefrontSuggestionIDs.contains($0.id)
                        })
                    }

                    ForEach(group.laneSections) { laneSection in
                        storefrontProviderSection(laneSection)
                    }
                }
                .padding(.leading, 20)
            }
        }
    }

    @ViewBuilder
    private func storefrontProviderSection(
        _ section: SableMangaBakaStorefrontProviderSection
    ) -> some View {
        let readySuggestions = section.suggestions.filter {
            !$0.imageNeedsReplacement
        }
        let imageIssueSuggestions = section.suggestions.filter(
            \.imageNeedsReplacement
        )
        let imageIssueSectionID = "\(section.id):image-issues"
        let reviewCount = readySuggestions.filter(
            store.storefrontSuggestionNeedsReview
        ).count
        let reviewGroupID = store.storefrontReviewGroupID(
            language: section.language,
            provider: section.provider,
            coverType: section.reviewCoverType,
            publicationType: section.reviewPublicationType
        )
        let relationshipReviewSuggestions = readySuggestions.filter(
            \.requiresRelationshipReview
        )
        let isApproved = !relationshipReviewSuggestions.isEmpty
            && relationshipReviewSuggestions.allSatisfy {
                store.approvedStorefrontReviewGroupIDs.contains(
                    store.storefrontReviewGroupID(for: $0)
                )
            }
        let isAutomaticallyApproved =
            store.storefrontReviewGroupIsAutomaticallyApproved(
                section.suggestions
            )
        let isRejected = !section.suggestions.isEmpty
            && section.suggestions.allSatisfy {
                store.storefrontRelationshipReviewIsRejected(for: $0)
            }
        let selectedCount = section.suggestions.filter {
            store.selectedStorefrontSuggestionIDs.contains($0.id)
        }.count
        let isExpanded = expandedStorefrontLaneIDs.contains(section.id)

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    if isExpanded {
                        expandedStorefrontLaneIDs.remove(section.id)
                        expandedStorefrontImageIssueIDs.remove(
                            imageIssueSectionID
                        )
                    } else {
                        expandedStorefrontLaneIDs.insert(section.id)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(
                            systemName: isExpanded
                                ? "chevron.down"
                                : "chevron.right"
                        )
                        .font(.caption.weight(.semibold))
                        .frame(width: 12)

                        Label(
                            section.lane.title,
                            systemImage: section.lane.systemImage
                        )
                        .font(.subheadline.weight(.semibold))

                        Text("\(section.suggestions.count)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    "\(isExpanded ? "Collapse" : "Expand") \(section.provider.displayName) \(section.lane.title)"
                )

                if reviewCount > 0 {
                    Label(
                        "\(reviewCount) to review",
                        systemImage: "questionmark.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(palette.statusWarning)
                }

                if !imageIssueSuggestions.isEmpty {
                    Label(
                        "\(imageIssueSuggestions.count) need image",
                        systemImage: "photo.badge.exclamationmark"
                    )
                    .font(.caption)
                    .foregroundStyle(palette.statusWarning)
                }

                if selectedCount > 0 {
                    Label(
                        "\(selectedCount) selected",
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.statusSuccess)
                }

                if isApproved || isAutomaticallyApproved {
                    Label(
                        isApproved ? "Accepted" : "Auto accepted",
                        systemImage: "checkmark.shield.fill"
                    )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.statusSuccess)
                        .help(
                            isApproved
                                ? "You confirmed this provider series. It will sync to Roler only after a successful MangaBaka apply."
                                : "Strong title and store media-type evidence cleared this provider locally. You can still reject it before applying."
                        )
                }

                rolerMatchShareStatus(
                    groupID: reviewGroupID,
                    language: section.language,
                    provider: section.provider,
                    coverType: section.reviewCoverType,
                    publicationType: section.reviewPublicationType
                )

                if isRejected {
                    Label("Rejected", systemImage: "xmark.octagon.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                }

                Spacer(minLength: 6)

                if section.lane == .books
                    || section.lane == .digitalEditions {
                    Button(
                        section.lane == .digitalEditions
                            ? "Use as Regular"
                            : "Mark Digital"
                    ) {
                        store.setStorefrontSuggestionsAsDigital(
                            section.suggestions,
                            isDigital:
                                section.lane != .digitalEditions
                        )
                    }
                    .controlSize(.small)
                    .help(
                        section.lane == .digitalEditions
                            ? "Return this group to the regular book-cover results. Its images still compete by quality."
                            : "Group these as Digital covers. This is only an organization label; the images still compete by quality unless you reject the group."
                    )
                }

                Button("Select All") {
                    store.selectAllStorefrontSuggestions(
                        from: readySuggestions
                    )
                }
                .controlSize(.small)
                .disabled(
                    readySuggestions.isEmpty
                        || store.hasAllStorefrontSuggestionSelection(
                            in: readySuggestions
                        )
                )
                .help(
                    "Select one best image for every volume in this provider lane. Kindle and print candidates compete for the same normal MangaBaka slot."
                )

                if !isRejected
                    && (
                        isApproved
                            || (
                                reviewCount > 0
                                    && !isAutomaticallyApproved
                            )
                    ) {
                    Button(
                        isApproved
                            ? "Undo Acceptance"
                            : "Accept Series"
                    ) {
                        store.setStorefrontRelationshipReviewApproved(
                            language: section.language,
                            provider: section.provider,
                            coverType: section.reviewCoverType,
                            publicationType:
                                section.reviewPublicationType,
                            isApproved: !isApproved
                        )
                    }
                    .controlSize(.small)
                    .accessibilityLabel(
                        "\(isApproved ? "Undo Acceptance" : "Accept Series") for \(section.provider.displayName) \(section.lane.title)"
                    )
                    .help(
                        isApproved
                            ? "Require relationship and media-type review for this provider lane again."
                            : "Confirm that this provider lane is the correct series and media type. It will sync to Roler only after a successful MangaBaka apply. Numbering warnings still require individual review."
                    )
                }

                Button(
                    isRejected
                        ? "Undo Rejection"
                        : "Reject Series"
                ) {
                    store.setStorefrontRelationshipReviewRejected(
                        language: section.language,
                        provider: section.provider,
                        coverType: section.reviewCoverType,
                        publicationType:
                            section.reviewPublicationType,
                        isRejected: !isRejected
                    )
                }
                .controlSize(.small)
                .accessibilityLabel(
                    "\(isRejected ? "Undo Rejection" : "Reject Series") for \(section.provider.displayName) \(section.lane.title)"
                )
                .foregroundStyle(
                    isRejected
                        ? AnyShapeStyle(.secondary)
                        : AnyShapeStyle(.red)
                )
                .help(
                    isRejected
                        ? "Allow this provider series in the current result batch again."
                        : "Skip this provider series only for the current result batch. Its covers stay visible, Select Best skips them, and no rejection is sent to Roler."
                )
            }

            if isExpanded {
                SableEagerAdaptiveGrid(
                    minimumItemWidth: 320,
                    maximumItemWidth: 460,
                    horizontalSpacing: 8,
                    verticalSpacing: 8
                ) {
                    ForEach(readySuggestions) { suggestion in
                        storefrontSuggestionCompactTile(suggestion)
                    }
                }
                .padding(.leading, 20)

                if !imageIssueSuggestions.isEmpty {
                    storefrontImageIssueSection(
                        imageIssueSuggestions,
                        sectionID: imageIssueSectionID
                    )
                    .padding(.leading, 20)
                }
            } else if reviewCount > 0 || !imageIssueSuggestions.isEmpty {
                Text(
                    imageIssueSuggestions.isEmpty
                        ? "Open this lane to check series, type, and numbering before selecting covers."
                        : "Open this lane to review its usable covers and matched books that need another image."
                )
                    .font(.caption)
                    .foregroundStyle(palette.statusWarning)
                    .padding(.leading, 20)
            }
        }
    }

    @ViewBuilder
    private func storefrontImageIssueSection(
        _ suggestions: [SableMangaBakaStorefrontCoverSuggestion],
        sectionID: String
    ) -> some View {
        let isExpanded = expandedStorefrontImageIssueIDs.contains(sectionID)

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    if isExpanded {
                        expandedStorefrontImageIssueIDs.remove(sectionID)
                    } else {
                        expandedStorefrontImageIssueIDs.insert(sectionID)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(
                            systemName: isExpanded
                                ? "chevron.down"
                                : "chevron.right"
                        )
                        .font(.caption.weight(.semibold))
                        .frame(width: 12)

                        Label(
                            "Needs Another Image",
                            systemImage: "photo.badge.exclamationmark"
                        )
                        .font(.subheadline.weight(.semibold))

                        Text("\(suggestions.count)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    "\(isExpanded ? "Collapse" : "Expand") books that need another image"
                )

                Spacer()

                Button("Use Cover Links") {
                    showManualURLFallback = true
                }
                .controlSize(.small)
                .help(
                    "Open Bulk Cover Links so you can paste working image links from BBC or a storefront."
                )
            }

            Text(
                "The book record matched, but its image is a placeholder or the wrong shape. These rows stay unchecked and cannot be bulk-selected."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            if isExpanded {
                SableEagerAdaptiveGrid(
                    minimumItemWidth: 320,
                    maximumItemWidth: 460,
                    horizontalSpacing: 8,
                    verticalSpacing: 8
                ) {
                    ForEach(suggestions) { suggestion in
                        storefrontSuggestionCompactTile(suggestion)
                    }
                }
            }
        }
        .padding(10)
        .background(
            palette.statusWarning.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(palette.statusWarning.opacity(0.22))
        )
    }

    @ViewBuilder
    private func rolerMatchShareStatus(
        groupID: String,
        language: String,
        provider: SableLibraryBigBookCoversProvider,
        coverType: String,
        publicationType: String?
    ) -> some View {
        switch store.rolerMatchShareStatuses[groupID] {
        case .sharing:
            Label("Sharing", systemImage: "arrow.trianglehead.2.clockwise")
                .font(.caption)
                .foregroundStyle(.secondary)
                .help("Saving this confirmed series match to Roler.")
        case .shared:
            Label("Roler synced", systemImage: "checkmark.icloud")
                .font(.caption)
                .foregroundStyle(palette.statusSuccess)
                .help("Roler saved this confirmed MangaBaka and store-series match.")
        case .failed(let message):
            Label("Not synced", systemImage: "exclamationmark.icloud")
                .font(.caption)
                .foregroundStyle(palette.statusWarning)
                .help(message)
            Button {
                store.retryRolerMapping(
                    language: language,
                    provider: provider,
                    coverType: coverType,
                    publicationType: publicationType
                )
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Try sharing this confirmed match with Roler again. \(message)")
            .accessibilityLabel("Retry Roler sync")
        case nil:
            EmptyView()
        }
    }

    private func storefrontSuggestionCompactTile(
        _ suggestion: SableMangaBakaStorefrontCoverSuggestion,
        showsProvider: Bool = false
    ) -> some View {
        let isExcluded = store.storefrontSuggestionIsExcluded(suggestion)
        let isSelected = store.selectedStorefrontSuggestionIDs.contains(
            suggestion.id
        )
        let canSelect = store.storefrontSuggestionCanBeManuallySelected(
            suggestion
        )

        return HStack(alignment: .top, spacing: 12) {
            storefrontSuggestionImageChooser(
                suggestion,
                width: 70,
                height: 98
            )

            VStack(alignment: .leading, spacing: 8) {
                Button {
                    store.setStorefrontSuggestion(
                        suggestion.id,
                        isSelected: !isSelected
                    )
                } label: {
                    Image(
                        systemName: isSelected
                            ? "checkmark.square.fill"
                            : "square"
                    )
                    .font(.title3)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(
                    isSelected
                        ? AnyShapeStyle(palette.accent)
                        : AnyShapeStyle(.secondary)
                )
                .disabled(!canSelect)
                .accessibilityLabel(
                    "\(isSelected ? "Remove" : "Include") \(suggestion.numberedKindLabel)"
                )
                .accessibilityValue(isSelected ? "Selected" : "Not selected")
                Spacer(minLength: 0)

                Button {
                    store.setStorefrontSuggestionExcluded(
                        suggestion,
                        isExcluded: !isExcluded
                    )
                } label: {
                    Image(
                        systemName: isExcluded
                            ? "arrow.uturn.backward.circle"
                            : "xmark.circle"
                    )
                    .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(
                    isExcluded
                        ? AnyShapeStyle(.secondary)
                        : AnyShapeStyle(.red)
                )
                .help(
                    isExcluded
                        ? "Put this book back in this MangaBaka series."
                        : "Exclude only this book from this MangaBaka series. The rest of the provider series stays available."
                )
                .accessibilityLabel(
                    isExcluded
                        ? "Undo book exclusion"
                        : "Exclude this book"
                )

                if let storeURL = suggestion.storeURL.flatMap(URL.init) {
                    Button {
                        open(storeURL)
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                    }
                    .buttonStyle(.plain)
                    .help("Open the store book")
                }
            }
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                if showsProvider {
                    Label(
                        suggestion.provider.displayName,
                        systemImage: "building.2"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    SableMangaBakaCoverNumberEditor(
                        coverType: suggestion.coverType,
                        value: suggestion.volumeNumber
                    ) {
                        store.updateStorefrontSuggestionVolume(
                            suggestion,
                            volumeNumber: $0
                        )
                    }

                    rolerBookCorrectionStatus(suggestion)
                }
                Text(suggestion.title)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let publicationType = suggestion.publicationTypeLabel {
                    Label(
                        publicationType,
                        systemImage: suggestion.isDigitalEdition
                            ? "ipad.and.iphone"
                            : "book.closed"
                    )
                    .foregroundStyle(.secondary)
                }
                if isExcluded {
                    Label(
                        "Excluded from this MangaBaka series",
                        systemImage: "xmark.circle.fill"
                    )
                    .foregroundStyle(.red)
                }

                if suggestion.requiresRelationshipReview {
                    let isAutomaticallyApproved =
                        store
                            .storefrontRelationshipReviewIsAutomaticallyApproved(
                                for: suggestion
                            )
                    Label(
                        store.storefrontRelationshipReviewIsApproved(
                            for: suggestion
                        )
                            ? (
                                isAutomaticallyApproved
                                    ? "Auto accepted"
                                    : "Series accepted"
                            )
                            : "Needs review",
                        systemImage: store
                            .storefrontRelationshipReviewIsApproved(
                                for: suggestion
                            )
                            ? "checkmark.circle"
                            : "questionmark.circle"
                    )
                    .foregroundStyle(
                        store.storefrontRelationshipReviewIsApproved(
                            for: suggestion
                        )
                            ? palette.statusSuccess
                            : palette.statusWarning
                    )
                } else {
                    Label(
                        suggestion.mediaTypeEvidenceLabel,
                        systemImage: suggestion.mediaTypeNeedsAttention
                            ? "exclamationmark.triangle"
                            : "checkmark.circle"
                    )
                    .foregroundStyle(
                        suggestion.mediaTypeNeedsAttention
                            ? palette.statusWarning
                            : .secondary
                    )
                }

                if let imageIssueLabel = suggestion.imageIssueLabel {
                    Label(
                        imageIssueLabel,
                        systemImage: "photo.badge.exclamationmark"
                    )
                    .foregroundStyle(palette.statusWarning)
                    .fixedSize(horizontal: false, vertical: true)
                }

                if let width = suggestion.width,
                   let height = suggestion.height {
                    Label(
                        "\(width) x \(height)",
                        systemImage: suggestion.reachesClinicMinimum
                            ? "checkmark.seal"
                            : "photo"
                    )
                    .foregroundStyle(
                        suggestion.reachesClinicMinimum
                            ? palette.statusSuccess
                            : palette.statusWarning
                    )
                }

                if let numberingReviewReason =
                    suggestion.numberingReviewReason {
                    Label(
                        numberingReviewReason,
                        systemImage: "number.circle"
                    )
                    .foregroundStyle(palette.statusWarning)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    contentRatingSuggestionID = suggestion.id
                } label: {
                    Label(
                        "Cover: \(store.storefrontContentRating(for: suggestion).capitalized)",
                        systemImage: coverRatingSystemImage(
                            store.storefrontContentRating(for: suggestion)
                        )
                    )
                }
                .buttonStyle(.plain)
                .foregroundStyle(
                    store.storefrontContentRating(for: suggestion) == "safe"
                        ? AnyShapeStyle(.secondary)
                        : AnyShapeStyle(palette.statusWarning)
                )
                .help(coverRatingHelp)

                if isSelected {
                    TextField(
                        "Cover note (optional)",
                        text: Binding(
                            get: {
                                store.storefrontCoverNote(for: suggestion)
                            },
                            set: {
                                store.setStorefrontCoverNote(
                                    $0,
                                    for: suggestion
                                )
                            }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .help(
                        "Saved with this cover, for example Special edition or Alternate cover."
                    )
                }

                if !suggestion.imageNeedsReplacement {
                    Text(store.storefrontSuggestionComparisonText(suggestion))
                        .foregroundStyle(
                            store.selectedStorefrontSuggestionIDs.contains(
                                suggestion.id
                            ) && !store.storefrontSuggestionIsActionable(suggestion)
                                ? AnyShapeStyle(palette.statusWarning)
                                : (
                                    store.storefrontSuggestionIsActionable(
                                        suggestion
                                    )
                                        ? AnyShapeStyle(palette.statusSuccess)
                                        : AnyShapeStyle(.secondary)
                                )
                        )
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(.caption.weight(.medium))
        }
        .padding(10)
        .frame(
            maxWidth: .infinity,
            minHeight: 126,
            alignment: .topLeading
        )
        .sableCoverRowSurface(
            fill: palette.surfaceRaised,
            border: palette.border,
            accent: palette.accent,
            isSelected: isSelected
        )
        .opacity(isExcluded ? 0.62 : 1)
    }

    private func storefrontSuggestionImageChooser(
        _ suggestion: SableMangaBakaStorefrontCoverSuggestion,
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        VStack(spacing: 6) {
            coverThumbnail(
                URL(string: suggestion.imageURL),
                width: width,
                height: height
            )

            if suggestion.imageChoiceCount > 1 {
                HStack(spacing: 3) {
                    Button {
                        store.moveStorefrontSuggestionImage(
                            suggestion,
                            offset: -1
                        )
                    } label: {
                        Image(systemName: "chevron.left")
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .help("Use the previous image from this store page.")
                    .accessibilityLabel(
                        "Previous image for \(suggestion.numberedKindLabel)"
                    )

                    Text(
                        "\(suggestion.activeImageChoiceIndex + 1)/\(suggestion.imageChoiceCount)"
                    )
                    .font(.caption2.monospacedDigit().weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28)

                    Button {
                        store.moveStorefrontSuggestionImage(
                            suggestion,
                            offset: 1
                        )
                    } label: {
                        Image(systemName: "chevron.right")
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .help("Use the next image from this store page.")
                    .accessibilityLabel(
                        "Next image for \(suggestion.numberedKindLabel)"
                    )
                }
                .frame(width: width)
                .padding(.vertical, 2)
                .background(palette.surface.opacity(0.72), in: Capsule())
            }
        }
        .frame(width: width)
    }

    @ViewBuilder
    private func rolerBookCorrectionStatus(
        _ suggestion: SableMangaBakaStorefrontCoverSuggestion
    ) -> some View {
        switch store.rolerBookCorrectionStatuses[suggestion.sourceIdentity] {
        case .saving:
            ProgressView()
                .controlSize(.small)
                .help("Syncing the corrected number to Roler.")
                .accessibilityLabel("Syncing corrected number")
        case .saved:
            Image(systemName: "checkmark.icloud")
                .foregroundStyle(palette.statusSuccess)
                .help("Roler saved this corrected number.")
                .accessibilityLabel("Corrected number synced")
        case .localOnly(let message):
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.secondary)
                .help(message)
                .accessibilityLabel("Corrected number saved here")
        case .failed(let message):
            Image(systemName: "exclamationmark.icloud")
                .foregroundStyle(palette.statusWarning)
                .help(message)
                .accessibilityLabel("Corrected number was not synced")
        case nil:
            EmptyView()
        }
    }

    private var storefrontLanguageSections: [SableMangaBakaStorefrontLanguageSection] {
        Dictionary(grouping: store.storefrontSuggestions) {
            studioLanguageCode($0.language)
        }
        .map {
            SableMangaBakaStorefrontLanguageSection(
                language: $0.key,
                suggestions: $0.value.sorted {
                    if $0.volumeNumber != $1.volumeNumber {
                        return $0.volumeNumber < $1.volumeNumber
                    }
                    return $0.provider.discoveryPriority < $1.provider.discoveryPriority
                }
            )
        }
        .sorted {
            let lhsRank = studioLanguageRank($0.language)
            let rhsRank = studioLanguageRank($1.language)
            return lhsRank == rhsRank ? $0.language < $1.language : lhsRank < rhsRank
        }
    }

    private var usesLargeStorefrontResultHierarchy: Bool {
        store.storefrontSuggestions.count > 80
    }

    private var storeSeriesURLsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                showStoreSeriesURLs.toggle()
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    Image(
                        systemName:
                            showStoreSeriesURLs
                                ? "chevron.down"
                                : "chevron.right"
                    )
                    .font(.caption.weight(.semibold))
                    .frame(width: 12)
                    .padding(.top, 3)

                    VStack(alignment: .leading, spacing: 3) {
                        Label(
                            "Use Store or Cover URLs",
                            systemImage: "link.badge.plus"
                        )
                        .font(.headline)
                        Text(
                            "Use exact store pages or direct cover images when automatic matching needs help."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                "\(showStoreSeriesURLs ? "Hide" : "Show") exact store and cover link tools"
            )

            if showStoreSeriesURLs {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(
                        "Paste BookLive, BookWalker, Amazon, Barnes & Noble, Audible, YES24, or Kyobo store pages, or direct cover image links, one per line. Kyobo ebook pages load the complete embedded series shelf when available."
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 12)

                    Button {
                        openRoler(for: store.selectedSeries, language: "ja")
                    } label: {
                        Label("Search Roler JP", systemImage: "safari")
                    }
                    .controlSize(.small)
                    .disabled(store.selectedSeries == nil)
                    .help(
                        "Open Roler with this series' Japanese title and Japanese storefronts."
                    )

                    Button {
                        openRoler(for: store.selectedSeries, language: "en")
                    } label: {
                        Label("Search Roler EN", systemImage: "safari")
                    }
                    .controlSize(.small)
                    .disabled(store.selectedSeries == nil)
                    .help(
                        "Open Roler with this series' English title and English storefronts."
                    )

                    Menu {
                        Button {
                            openRoler(
                                for: store.selectedSeries,
                                language: "ko"
                            )
                        } label: {
                            Label("Search Roler KR", systemImage: "safari")
                        }

                        Divider()

                        Button {
                            openKoreanStore(
                                for: store.selectedSeries,
                                provider: .yes24
                            )
                        } label: {
                            Label("Search YES24", systemImage: "safari")
                        }

                        Button {
                            openKoreanStore(
                                for: store.selectedSeries,
                                provider: .kyobo
                            )
                        } label: {
                            Label("Search Kyobo", systemImage: "safari")
                        }
                    } label: {
                        Label(
                            "Search Korean Stores",
                            systemImage: "character.book.closed"
                        )
                    }
                    .controlSize(.small)
                    .disabled(store.selectedSeries == nil)
                    .help(
                        "Search Roler, YES24, or Kyobo with this series' Korean title."
                    )

                    Button(action: store.pasteStoreSeriesURLs) {
                        Label("Paste Links", systemImage: "clipboard")
                    }
                    .controlSize(.small)
                }

                TextEditor(text: $store.storeSeriesURLs)
                    .font(.body.monospaced())
                    .frame(minHeight: 76)
                    .padding(6)
                    .background(
                        palette.surfaceRaised,
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(palette.border)
                    )
                    .accessibilityLabel(
                        "Store page or direct cover image URLs, one per line"
                    )

                HStack {
                    Text(
                        "Store results appear in Provider Cover Results above. Direct images are checked at their maximum available size and added to the proposed cover set for review."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 12)

                    Button(action: store.scanStoreSeriesURLs) {
                        Label(
                            "Scan Links",
                            systemImage: "scope"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        store.isWorking
                            || store.storeSeriesURLs
                                .trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                )
                                .isEmpty
                    )
                }
            }
            .padding(.top, 10)
            }
        }
        .padding(16)
        .sableCoverDataSurface(fill: palette.surface, border: palette.border)
    }

    private var storefrontSubmissionControls: some View {
        let selectedCount =
            store.selectedMangaBakaStorefrontSuggestions.count
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 14) {
                storefrontSubmissionSummary(selectedCount: selectedCount)
                Spacer(minLength: 12)
                storefrontSubmissionButton(selectedCount: selectedCount)
            }

            VStack(alignment: .leading, spacing: 10) {
                storefrontSubmissionSummary(selectedCount: selectedCount)
                storefrontSubmissionButton(selectedCount: selectedCount)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(12)
        .background(palette.surfaceRaised, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.border))
    }

    private var storefrontPinnedApplyBar: some View {
        storefrontSubmissionControls
            .frame(maxWidth: 1180)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(.bar)
            .overlay(alignment: .top) {
                Divider()
            }
    }

    private func storefrontSubmissionSummary(selectedCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(
                selectedCount > 0
                    ? "\(selectedCount) cover\(selectedCount == 1 ? "" : "s") ready"
                    : store.hasDraftChanges ? "Prepared cover changes" : "Choose covers to add",
                systemImage: selectedCount > 0 || store.hasDraftChanges
                    ? "checkmark.circle"
                    : "circle.dashed"
            )
            .font(.callout.weight(.semibold))

            Text(mangaBakaSubmissionAccessText)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func storefrontSubmissionButton(selectedCount: Int) -> some View {
        Button {
            if store.prepareStorefrontSubmission() {
                showMangaBakaSubmissionConfirmation = true
            }
        } label: {
            Label(
                mangaBakaSubmissionButtonTitle(selectedCount: selectedCount),
                systemImage: "paperplane.fill"
            )
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(
            store.isWorking
                || store.isCheckingMangaBakaAccount
                || (selectedCount == 0 && !store.hasDraftChanges)
        )
        .help(
            store.canApplyDirectly
                ? "Prepare the selected covers and confirm a direct MangaBaka update."
                : "Prepare the selected covers and send them to MangaBaka for review."
        )
        .accessibilityHint("A confirmation shows Sable's change comment before anything is sent.")
    }

    private var mangaBakaSubmissionAccessText: String {
        guard store.hasMangaBakaToken else {
            return "Add your MangaBaka personal access token in Settings before submitting covers."
        }
        if store.isCheckingMangaBakaAccount {
            return "Checking whether this MangaBaka account can apply directly or needs review."
        }
        if let role = store.mangaBakaAccountRole {
            if role.canApplyDirectly {
                return "\(role.displayName) access: Sable can apply directly after one confirmation."
            }
            return "\(role.displayName) access: Sable will send these changes to MangaBaka for review."
        }
        return store.mangaBakaAccountMessage
            ?? "Sable will use MangaBaka's review queue for this account."
    }

    private var mangaBakaSubmissionConfirmationMessage: String {
        let action = store.canApplyDirectly
            ? "This account can bypass the review queue."
            : "MangaBaka will place these changes in its review queue."
        return "\(action) After MangaBaka receives the request, Sable will also sync confirmed mappings to Roler.\n\nComment:\n\(store.submissionNote)"
    }

    private func mangaBakaSubmissionButtonTitle(
        selectedCount: Int
    ) -> String {
        let subject = selectedCount > 0
            ? "\(selectedCount) Selected"
            : "Prepared Changes"
        return store.canApplyDirectly
            ? "Apply \(subject) Directly..."
            : "Submit \(subject) for Review..."
    }

    private func storefrontSuggestionRow(
        _ suggestion: SableMangaBakaStorefrontCoverSuggestion
    ) -> some View {
        let isSelected = store.selectedStorefrontSuggestionIDs.contains(suggestion.id)
        let isExcluded = store.storefrontSuggestionIsExcluded(suggestion)
        let canSelect = store.storefrontSuggestionCanBeManuallySelected(suggestion)

        return HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 8) {
                Button {
                    store.setStorefrontSuggestion(
                        suggestion.id,
                        isSelected: !isSelected
                    )
                } label: {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .font(.title3)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(
                    isSelected
                        ? AnyShapeStyle(palette.accent)
                        : AnyShapeStyle(.secondary)
                )
                .disabled(!canSelect)
                .accessibilityLabel(
                    "Include \(suggestion.provider.displayName) \(suggestion.language.uppercased()) \(suggestion.coverType) \(suggestion.volumeLabel)"
                )
                .accessibilityValue(isSelected ? "Selected" : "Not selected")
                .accessibilityHint(
                    suggestion.numberingReviewReason
                        ?? (store.storefrontSuggestionNeedsReview(suggestion)
                            ? "The store did not prove the exact series relationship or media type. Review this cover before including it."
                            : store.storefrontSuggestionComparisonText(suggestion))
                )

                Button {
                    store.setStorefrontSuggestionExcluded(
                        suggestion,
                        isExcluded: !isExcluded
                    )
                } label: {
                    Image(
                        systemName: isExcluded
                            ? "arrow.uturn.backward.circle"
                            : "xmark.circle"
                    )
                    .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(
                    isExcluded
                        ? AnyShapeStyle(.secondary)
                        : AnyShapeStyle(.red)
                )
                .help(
                    isExcluded
                        ? "Put this book back in this MangaBaka series."
                        : "Exclude only this book from this MangaBaka series. The rest of the provider series stays available."
                )
                .accessibilityLabel(
                    isExcluded
                        ? "Undo book exclusion"
                        : "Exclude this book"
                )
            }

            coverThumbnail(URL(string: suggestion.imageURL), width: 58, height: 82)

            VStack(alignment: .leading, spacing: 4) {
                Text(suggestion.numberedKindLabel)
                    .font(.callout.weight(.semibold))
                Text(suggestion.provider.displayName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(suggestion.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let publicationType = suggestion.publicationTypeLabel {
                    Text(publicationType)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Label(
                    suggestion.mediaTypeEvidenceLabel,
                    systemImage: suggestion.mediaTypeNeedsAttention
                        ? "exclamationmark.triangle"
                        : "checkmark.circle"
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(
                    suggestion.mediaTypeNeedsAttention
                        ? palette.statusWarning
                        : .secondary
                )
                if suggestion.requiresRelationshipReview {
                    if store.storefrontRelationshipReviewIsRejected(
                        for: suggestion
                    ) {
                        Label(
                            "Series rejected for this provider",
                            systemImage: "xmark.octagon.fill"
                        )
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.red)
                    } else if store.storefrontRelationshipReviewIsApproved(
                        for: suggestion
                    ) {
                        Label(
                            store
                                .storefrontRelationshipReviewIsAutomaticallyApproved(
                                    for: suggestion
                                )
                                ? "Strong title and store type match · auto accepted"
                                : "Series and type accepted for this provider",
                            systemImage: "checkmark.circle"
                        )
                        .font(.caption.weight(.medium))
                        .foregroundStyle(palette.statusSuccess)
                    } else {
                        Label(
                            "Related result · check series and type",
                            systemImage: "questionmark.circle"
                        )
                        .font(.caption.weight(.medium))
                        .foregroundStyle(palette.statusWarning)
                    }
                }
                if let numberingReviewReason =
                    suggestion.numberingReviewReason {
                    Label(
                        numberingReviewReason,
                        systemImage: "number.circle"
                    )
                    .font(.caption.weight(.medium))
                    .foregroundStyle(palette.statusWarning)
                    .fixedSize(horizontal: false, vertical: true)
                }
                if let width = suggestion.width,
                   let height = suggestion.height {
                    Label(
                        "\(width) x \(height) · \(suggestion.reachesClinicMinimum ? "High quality" : "Lower resolution")",
                        systemImage: suggestion.reachesClinicMinimum
                            ? "checkmark.seal"
                            : "photo"
                    )
                    .font(.caption)
                    .foregroundStyle(
                        suggestion.reachesClinicMinimum
                            ? palette.statusSuccess
                        : palette.statusWarning
                    )
                }
                Button {
                    contentRatingSuggestionID = suggestion.id
                } label: {
                    let rating = store.storefrontContentRating(
                        for: suggestion
                    )
                    Label(
                        "Cover: \(rating.capitalized)"
                            + (suggestion.contentRatingWasInferred
                                && store.storefrontContentRatingOverrides[
                                    suggestion.id
                                ] == nil
                                ? " · detected"
                                : ""),
                        systemImage: coverRatingSystemImage(rating)
                    )
                }
                .buttonStyle(.plain)
                .fixedSize()
                .foregroundStyle(
                    store.storefrontContentRating(for: suggestion) == "safe"
                        ? AnyShapeStyle(.secondary)
                        : AnyShapeStyle(palette.statusWarning)
                )
                .help(coverRatingHelp)
                Text(store.storefrontSuggestionComparisonText(suggestion))
                    .font(.caption)
                    .foregroundStyle(
                        store.selectedStorefrontSuggestionIDs.contains(
                            suggestion.id
                        ) && !store.storefrontSuggestionIsActionable(
                            suggestion
                        )
                            ? AnyShapeStyle(palette.statusWarning)
                            : (
                                store.storefrontSuggestionIsActionable(
                                    suggestion
                                )
                                    ? AnyShapeStyle(palette.statusSuccess)
                                    : AnyShapeStyle(.secondary)
                            )
                    )
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            if let storeURL = suggestion.storeURL.flatMap(URL.init(string:)) {
                Button {
                    open(storeURL)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                }
                .buttonStyle(.plain)
                .help("Open the store book")
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sableCoverRowSurface(
            fill: palette.surfaceRaised,
            border: palette.border,
            accent: palette.accent,
            isSelected: isSelected
        )
        .opacity(isExcluded ? 0.62 : 1)
    }

    private var contentRatingSuggestion:
        SableMangaBakaStorefrontCoverSuggestion? {
        guard let contentRatingSuggestionID else { return nil }
        return store.storefrontSuggestions.first {
            $0.id == contentRatingSuggestionID
        }
    }

    private func studioHeader(_ series: SableMangaBakaSeriesSummary) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 4) {
                coverThumbnail(series.coverURL, width: 78, height: 108)
                Text("MB reference")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(series.displayTitle)
                    .font(.title2.bold())
                    .fixedSize(horizontal: false, vertical: true)
                if let scopeTitle = studioScopeTitle(for: series) {
                    Text(scopeTitle)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("\(series.type.capitalized) · MangaBaka \(series.id)")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Button {
                        open(URL(string: "https://mangabaka.org/\(series.id)")!)
                    } label: {
                        Label("MangaBaka", systemImage: "arrow.up.right.square")
                    }

                    Menu {
                        Button {
                            openRoler(for: series, language: "ja")
                        } label: {
                            Label("Search Roler JP", systemImage: "character.book.closed.ja")
                        }

                        Button {
                            openRoler(for: series, language: "en")
                        } label: {
                            Label("Search Roler EN", systemImage: "character.book.closed")
                        }

                        Button {
                            openRoler(for: series, language: "ko")
                        } label: {
                            Label("Search Roler KR", systemImage: "character.book.closed")
                        }

                        Divider()

                        Button {
                            openKoreanStore(
                                for: series,
                                provider: .yes24
                            )
                        } label: {
                            Label("Search YES24", systemImage: "character.book.closed")
                        }

                        Button {
                            openKoreanStore(
                                for: series,
                                provider: .kyobo
                            )
                        } label: {
                            Label("Search Kyobo", systemImage: "character.book.closed")
                        }
                    } label: {
                        Label("Find Sources", systemImage: "photo.badge.magnifyingglass")
                    }
                    .help("Open Roler with the correct Japanese, English, or Korean series title.")

                    Button {
                        chooseDownloadFolder()
                    } label: {
                        Label("Download Set", systemImage: "square.and.arrow.down")
                    }
                    .disabled(store.draftImages.isEmpty || store.isDownloading)
                }
                .controlSize(.small)
            }

            Spacer(minLength: 0)

            if store.isWorking || store.isDownloading {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(store.status)
            }
        }
        .padding(16)
        .sableCoverDataSurface(fill: palette.surface, border: palette.border)
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(store.status, systemImage: store.errorMessage == nil ? "info.circle" : "exclamationmark.triangle")
                .font(.callout.weight(.medium))
                .foregroundStyle(store.errorMessage == nil ? palette.textPrimary : palette.statusError)
                .fixedSize(horizontal: false, vertical: true)

            if let error = store.errorMessage {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let summary = store.storefrontScanCompactSummary {
                HStack(alignment: .center, spacing: 10) {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button("Scan Details...") {
                        showScanDetails = true
                    }
                    .controlSize(.small)
                    .help("Show progress and the result from each storefront.")

                    if store.canStopStorefrontScan {
                        Button(
                            role: .destructive,
                            action: store.stopStorefrontScan
                        ) {
                            Label(
                                store.isStoppingStorefrontScan
                                    ? "Stopping..."
                                    : "Stop Scan",
                                systemImage: "stop.circle.fill"
                            )
                        }
                        .controlSize(.small)
                        .disabled(store.isStoppingStorefrontScan)
                        .help("Stop checking storefronts and keep every result found so far.")
                    }
                }

                if let progress = store.storefrontScanProgress,
                   progress.isActive {
                    ProgressView(
                        value: Double(progress.completedProviders),
                        total: Double(max(progress.totalProviders, 1))
                    )
                    .progressViewStyle(.linear)
                    .accessibilityLabel("Regional storefront scan progress")
                    .accessibilityValue(summary)
                }
            }

            if !store.hasMangaBakaToken {
                SettingsLink {
                    Label("Open MangaBaka Settings", systemImage: "gearshape")
                }
                .controlSize(.small)
                .help("Add the MangaBaka personal access token in Settings. Sable stores it in macOS Keychain.")
            }

            ForEach(store.validationIssues, id: \.self) { issue in
                Label(issue, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(palette.statusWarning)
            }
        }
        .padding(12)
        .sableLibrarySurface(
            fill: palette.surfaceRaised,
            border: store.errorMessage == nil ? palette.border : palette.statusError.opacity(0.7),
            cornerRadius: 8
        )
    }

    private var storefrontScanDetailsSheet: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Storefront Scan Details")
                        .font(.title2.bold())
                    Text(store.storefrontScanCompactSummary ?? "No storefront scan has run yet.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if store.canStopStorefrontScan {
                    Button(
                        role: .destructive,
                        action: store.stopStorefrontScan
                    ) {
                        Label(
                            store.isStoppingStorefrontScan
                                ? "Stopping..."
                                : "Stop Scan",
                            systemImage: "stop.circle.fill"
                        )
                    }
                    .disabled(store.isStoppingStorefrontScan)
                    .help("Stop checking storefronts and keep every result found so far.")
                }
                Button("Done") {
                    showScanDetails = false
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)

            Divider()

            if let progress = store.storefrontScanProgress {
                VStack(alignment: .leading, spacing: 10) {
                    ProgressView(
                        value: Double(progress.completedProviders),
                        total: Double(max(progress.totalProviders, 1))
                    )
                    .progressViewStyle(.linear)

                    HStack(spacing: 16) {
                        Label(
                            "\(progress.acceptedImages) usable",
                            systemImage: "checkmark.circle"
                        )
                        Label(
                            "\(progress.rejectedImages) rejected",
                            systemImage: "xmark.circle"
                        )
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(store.storefrontScanProviderRows, id: \.name) { row in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(row.name)
                                    .font(.callout.weight(.semibold))
                                    .frame(width: 150, alignment: .leading)
                                Text(row.state)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            Divider()
                                .padding(.leading, 20)
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "No Scan Details",
                    systemImage: "magnifyingglass",
                    description: Text("Run a provider scan to see each storefront result.")
                )
            }
        }
        .frame(width: 720, height: 520)
    }

    private func currentImagesPanel(_ series: SableMangaBakaSeriesSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Cover Set", systemImage: "photo.stack")
                    .font(.headline)
                Text(
                    store.coverInventoryLanguage == "all"
                        ? "\(store.coverInventoryTotalCount)"
                        : "\(store.coverInventoryFilteredTotalCount) of \(store.coverInventoryTotalCount)"
                )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    store.select(series)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Reload the live MangaBaka cover set")
                .disabled(store.isWorking)

                Button {
                    showCurrentCoverSet.toggle()
                } label: {
                    Label(
                        showCurrentCoverSet ? "Hide Covers" : "Review Covers",
                        systemImage: showCurrentCoverSet ? "chevron.up" : "chevron.down"
                    )
                }
                .help(
                    showCurrentCoverSet
                        ? "Collapse the current MangaBaka cover set"
                        : "Review and edit the proposed MangaBaka cover set"
                )
            }

            HStack(spacing: 10) {
                Picker("Cover language", selection: $store.coverInventoryLanguage) {
                    Text("All Languages").tag("all")
                    ForEach(store.coverInventoryLanguageCodes, id: \.self) { language in
                        Text(studioLanguageName(language)).tag(language)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 220, alignment: .leading)
                .help("Show one cover language without changing the MangaBaka cover set.")

                if store.coverInventoryLanguage != "all" {
                    Text("\(store.coverInventoryFilteredTotalCount) shown")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if store.isCheckingExistingCoverSafety {
                VStack(alignment: .leading, spacing: 5) {
                    Text(
                        "\(store.existingCoverSafetyProgressLabel) \(store.existingCoverSafetyCompleted) of \(store.existingCoverSafetyTotal) unique cover\(store.existingCoverSafetyTotal == 1 ? "" : "s")"
                    )
                    ProgressView(
                        value: Double(store.existingCoverSafetyCompleted),
                        total: Double(max(store.existingCoverSafetyTotal, 1))
                    )
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 280)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
            } else if store.existingCoverSafetyDidComplete {
                if store.existingCoverSafetyCorrectionCount == 0 {
                    Label(
                        "Checked \(store.existingCoverSafetyReviewedCount) cover\(store.existingCoverSafetyReviewedCount == 1 ? "" : "s"); current ratings agree",
                        systemImage: "checkmark.shield"
                    )
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                } else {
                    Button {
                        showExistingCoverSafetyCorrections.toggle()
                    } label: {
                        HStack(spacing: 8) {
                            Label(
                                "\(store.existingCoverSafetyCorrectionCount) of \(store.existingCoverSafetyReviewedCount) safety ratings differ",
                                systemImage: "exclamationmark.shield"
                            )
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(palette.statusWarning)

                            Spacer()

                            Text(
                                showExistingCoverSafetyCorrections
                                    ? "Hide Changes"
                                    : "Review Changes"
                            )
                            .font(.caption.weight(.semibold))
                            Image(
                                systemName:
                                    showExistingCoverSafetyCorrections
                                        ? "chevron.up"
                                        : "chevron.down"
                            )
                            .font(.caption.weight(.semibold))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(
                        showExistingCoverSafetyCorrections
                            ? "Hide the covers with proposed safety changes"
                            : "Show only the covers with proposed safety changes"
                    )
                }
            }

            if showExistingCoverSafetyCorrections,
               store.existingCoverSafetyCorrectionCount > 0 {
                existingCoverSafetyCorrectionReview()
            }

            SableEagerAdaptiveGrid(
                minimumItemWidth: 125,
                horizontalSpacing: 10,
                verticalSpacing: 6
            ) {
                ForEach(SableMangaBakaCoverInventoryGroup.allCases) { group in
                    let count = store.coverInventoryCount(in: group)
                    Label(
                        "\(count) \(group.summaryTitle(count: count))",
                        systemImage: group.systemImage
                    )
                    .font(.caption.weight(.medium))
                    .foregroundStyle(
                        count == 0
                            ? .tertiary
                            : .secondary
                    )
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("MangaBaka cover type inventory")

            if showCurrentCoverSet {
                if store.coverInventoryTotalCount == 0 {
                    ContentUnavailableView(
                        "No Cover Images",
                        systemImage: "photo.badge.plus",
                        description: Text("Add provider covers or an exact image URL, then confirm the direct update.")
                    )
                    .frame(minHeight: 180)
                } else if store.coverInventoryFilteredTotalCount == 0 {
                    ContentUnavailableView(
                        "No \(studioLanguageName(store.coverInventoryLanguage)) Covers",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("Choose another language or All Languages to review the rest of this cover set.")
                    )
                    .frame(minHeight: 180)
                } else {
                    ForEach(SableMangaBakaCoverInventoryGroup.allCases) { group in
                        coverInventorySection(group)
                    }
                }
            } else {
                Text(
                    store.coverInventoryTotalCount == 0
                        ? "No covers are currently saved on MangaBaka."
                        : "The current cover set is collapsed so the provider results remain easy to browse."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .sableCoverDataSurface(fill: palette.surface, border: palette.border)
    }

    private func existingCoverSafetyCorrectionReview() -> some View {
        let correctionIndices =
            store.existingCoverSafetyCorrectionDraftIndices

        return VStack(alignment: .leading, spacing: 10) {
            Divider()

            HStack(spacing: 8) {
                Label(
                    "Affected Covers",
                    systemImage: "exclamationmark.shield"
                )
                .font(.subheadline.weight(.semibold))
                Text("\(correctionIndices.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            SableEagerAdaptiveGrid(
                minimumItemWidth: 300,
                maximumItemWidth: 440,
                horizontalSpacing: 8,
                verticalSpacing: 8
            ) {
                ForEach(correctionIndices, id: \.self) { index in
                    if store.draftImages.indices.contains(index),
                       let correction =
                        store.existingCoverSafetyCorrection(
                            atDraftIndex: index
                        ) {
                        currentDraftCoverRow(
                            index,
                            fallback: store.draftImages[index],
                            safetyCorrection: correction
                        )
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "\(correctionIndices.count) covers with proposed safety rating changes"
        )
    }

    @ViewBuilder
    private func coverInventorySection(
        _ group: SableMangaBakaCoverInventoryGroup
    ) -> some View {
        let count = store.coverInventoryCount(in: group)
        let safetyChangeCount =
            store.existingCoverSafetyCorrectionCount(in: group)

        if count > 0 {
            VStack(alignment: .leading, spacing: 10) {
                let isExpanded = expandedCoverInventoryGroupIDs
                    .contains(group.id)
                Button {
                    if isExpanded {
                        expandedCoverInventoryGroupIDs.remove(group.id)
                    } else {
                        expandedCoverInventoryGroupIDs.insert(group.id)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(
                            systemName: isExpanded
                                ? "chevron.down"
                                : "chevron.right"
                        )
                        Label(group.title, systemImage: group.systemImage)
                            .font(.subheadline.weight(.semibold))
                        Text("\(count)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        coverSafetyChangeLabel(safetyChangeCount)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(
                    isExpanded
                        ? "Hide these MangaBaka covers"
                        : "Show these MangaBaka covers"
                )

                if isExpanded {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(
                            store.coverInventoryLanguageCodes(in: group),
                            id: \.self
                        ) { language in
                            coverInventoryLanguageSection(
                                group,
                                language: language
                            )
                        }
                    }
                    .padding(.leading, 20)
                }
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func coverInventoryLanguageSection(
        _ group: SableMangaBakaCoverInventoryGroup,
        language: String
    ) -> some View {
        let sectionID = "\(group.id):\(language)"
        let editableIndices = store.draftImageIndices(
            in: group,
            language: language
        )
        let liveOnlyCovers = store.liveOnlyCovers(
            in: group,
            language: language
        )
        let totalCount = editableIndices.count + liveOnlyCovers.count
        let safetyChangeCount =
            store.existingCoverSafetyCorrectionCount(
                in: group,
                language: language
            )
        let pageSize = Self.coverInventoryPageSize
        let pageCount = max(1, (totalCount + pageSize - 1) / pageSize)
        let requestedPage = coverInventoryPageByLanguageID[sectionID] ?? 1
        let page = min(max(requestedPage, 1), pageCount)
        let pageStart = (page - 1) * pageSize
        let editablePage = Array(
            editableIndices.dropFirst(pageStart).prefix(pageSize)
        )
        let liveStart = max(0, pageStart - editableIndices.count)
        let livePage = Array(
            liveOnlyCovers.dropFirst(liveStart)
                .prefix(pageSize - editablePage.count)
        )
        let isExpanded = expandedCoverInventoryLanguageIDs
            .contains(sectionID)

        VStack(alignment: .leading, spacing: 8) {
            Button {
                if isExpanded {
                    expandedCoverInventoryLanguageIDs.remove(sectionID)
                } else {
                    expandedCoverInventoryLanguageIDs.insert(sectionID)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(
                        systemName: isExpanded
                            ? "chevron.down"
                            : "chevron.right"
                    )
                    Label(
                        studioLanguageName(language),
                        systemImage: "character.book.closed"
                    )
                    .font(.callout.weight(.semibold))
                    Text("\(totalCount)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    coverSafetyChangeLabel(safetyChangeCount)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(
                isExpanded
                    ? "Hide these \(studioLanguageName(language)) covers"
                    : "Show these \(studioLanguageName(language)) covers"
            )

            if isExpanded {
                if pageCount > 1 {
                    coverInventoryPager(
                        sectionID: sectionID,
                        page: page,
                        pageCount: pageCount,
                        pageStart: pageStart,
                        totalCount: totalCount
                    )
                }

                SableEagerAdaptiveGrid(
                    minimumItemWidth: 300,
                    maximumItemWidth: 440,
                    horizontalSpacing: 8,
                    verticalSpacing: 8
                ) {
                    ForEach(editablePage, id: \.self) { index in
                        if store.draftImages.indices.contains(index) {
                            currentDraftCoverRow(
                                index,
                                fallback: store.draftImages[index],
                                safetyCorrection:
                                    store.existingCoverSafetyCorrection(
                                        atDraftIndex: index
                                    )
                            )
                        }
                    }
                    ForEach(livePage) { image in
                        currentLiveCoverRow(image)
                    }
                }

                if pageCount > 1 {
                    coverInventoryPager(
                        sectionID: sectionID,
                        page: page,
                        pageCount: pageCount,
                        pageStart: pageStart,
                        totalCount: totalCount
                    )
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func coverSafetyChangeLabel(_ count: Int) -> some View {
        if count > 0 {
            Label(
                "\(count) triggered",
                systemImage: "exclamationmark.shield.fill"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(palette.statusWarning)
            .accessibilityLabel(
                "\(count) safety rating change\(count == 1 ? "" : "s") to review"
            )
        }
    }

    private func coverInventoryPager(
        sectionID: String,
        page: Int,
        pageCount: Int,
        pageStart: Int,
        totalCount: Int
    ) -> some View {
        let visibleUpperBound = min(
            pageStart + Self.coverInventoryPageSize,
            totalCount
        )

        return HStack(spacing: 8) {
            Text(
                "Page \(page) of \(pageCount) · Covers \(pageStart + 1)–\(visibleUpperBound) of \(totalCount)"
            )
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)

            Spacer()

            Button {
                coverInventoryPageByLanguageID[sectionID] = page - 1
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .disabled(page <= 1)
            .help("Previous cover page")

            Button {
                coverInventoryPageByLanguageID[sectionID] = page + 1
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
            .disabled(page >= pageCount)
            .help("Next cover page")
        }
        .accessibilityElement(children: .contain)
    }

    private func currentDraftCoverRow(
        _ index: Int,
        fallback image: SableMangaBakaCoverImage,
        safetyCorrection: SableMangaBakaCoverSafetyCorrection? = nil
    ) -> some View {
        let currentImage = store.draftImages.indices.contains(index)
            ? store.draftImages[index]
            : image
        let isDefault = currentImage.isDefault
        let sizeText = coverSizeText(for: currentImage)

        return HStack(alignment: .top, spacing: 10) {
            coverThumbnail(currentImage.imageURL, width: 56, height: 78)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Label(
                        currentImage.inventoryItemLabel,
                        systemImage: currentImage.inventoryGroup.systemImage
                    )
                    .font(.callout.weight(.semibold))

                    if isDefault {
                        Label("Default", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(palette.statusSuccess)
                    }
                }

                if let safetyCorrection {
                    VStack(alignment: .leading, spacing: 3) {
                        Label(
                            "Safety scan triggered",
                            systemImage: "exclamationmark.shield.fill"
                        )
                        .font(.caption.weight(.semibold))

                        HStack(spacing: 6) {
                            Text(safetyCorrection.originalRating.capitalized)
                            Image(systemName: "arrow.right")
                            Text(safetyCorrection.proposedRating.capitalized)
                                .fontWeight(.semibold)
                        }
                        .font(.callout)
                    }
                    .foregroundStyle(palette.statusWarning)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        palette.statusWarning.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 4)
                    )
                }

                Text(sourceHostText(currentImage.imageURL))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                coverFactGrid {
                    coverFact(studioLanguageName(currentImage.language), systemImage: "character.book.closed")
                    coverFact(coverTypeDisplayName(currentImage.type), systemImage: currentImage.inventoryGroup.systemImage)
                    editableCoverNumberFact(
                        index: index,
                        fallback: currentImage
                    )
                    coverFact(sizeText, systemImage: "photo")
                    coverFact("Cover: \(currentImage.contentRating.capitalized)", systemImage: coverRatingSystemImage(currentImage.contentRating))
                }

                if let note = currentImage.note,
                   !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 8) {
                Menu {
                    ForEach(
                        SableMangaBakaCoverImage.supportedRatings,
                        id: \.self
                    ) { rating in
                        Button {
                            store.setDraftImageContentRating(
                                at: index,
                                to: rating
                            )
                        } label: {
                            if rating == currentImage.contentRating {
                                Label(
                                    rating.capitalized,
                                    systemImage: "checkmark"
                                )
                            } else {
                                Text(rating.capitalized)
                            }
                        }
                    }
                } label: {
                    Image(
                        systemName: coverRatingSystemImage(
                            currentImage.contentRating
                        )
                    )
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .disabled(!store.draftImages.indices.contains(index))
                .help("Change this cover's content rating")
                .accessibilityLabel(
                    "Cover rating: \(currentImage.contentRating.capitalized)"
                )

                Button {
                    store.setDefault(at: index)
                } label: {
                    Image(systemName: isDefault ? "checkmark.circle.fill" : "circle")
                }
                .buttonStyle(.plain)
                .disabled(!store.draftImages.indices.contains(index))
                .help(isDefault ? "This is the default cover" : "Make this the default cover")

                Button(role: .destructive) {
                    store.removeImage(at: index)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .disabled(!store.draftImages.indices.contains(index))
                .help("Remove this cover from the proposed MangaBaka set")
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sableCoverRowSurface(
            fill: palette.surfaceRaised,
            border: palette.border,
            accent: safetyCorrection == nil
                ? palette.accent
                : palette.statusWarning,
            isSelected: isDefault || safetyCorrection != nil
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(studioLanguageName(currentImage.language)) \(currentImage.inventoryItemLabel), \(sizeText), \(currentImage.contentRating) cover\(safetyCorrection.map { ", rating changed from \($0.originalRating)" } ?? "")"
        )
    }

    private func currentLiveCoverRow(
        _ image: SableMangaBakaPublicCoverImage
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            coverThumbnail(URL(string: image.rawURL), width: 56, height: 78)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Label(
                        image.inventoryItemLabel,
                        systemImage: image.inventoryGroup.systemImage
                    )
                    .font(.callout.weight(.semibold))

                    Label("Live only", systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(palette.statusSuccess)
                }

                Text(sourceHostText(URL(string: image.rawURL)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                coverFactGrid {
                    coverFact(studioLanguageName(image.language), systemImage: "character.book.closed")
                    coverFact(coverTypeDisplayName(image.type), systemImage: image.inventoryGroup.systemImage)
                    coverFact("Number \(image.volumeLabel)", systemImage: "number")
                    coverFact("\(image.width) x \(image.height)", systemImage: "photo")
                    coverFact("Cover: \(image.contentRating.capitalized)", systemImage: coverRatingSystemImage(image.contentRating))
                }
            }

            Spacer(minLength: 8)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sableCoverRowSurface(
            fill: palette.surfaceRaised,
            border: palette.border,
            accent: palette.accent
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(studioLanguageName(image.language)) \(image.inventoryItemLabel), live on MangaBaka, \(image.width) by \(image.height) pixels, \(image.contentRating) cover"
        )
    }

    private func liveOnlyCoverCard(
        _ image: SableMangaBakaPublicCoverImage
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label(image.inventoryItemLabel, systemImage: image.inventoryGroup.systemImage)
                    .font(.callout.weight(.semibold))
                Spacer()
                Text(studioLanguageName(image.language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            coverThumbnail(URL(string: image.rawURL), width: 150, height: 210)
                .frame(maxWidth: .infinity)

            Label("Live on MangaBaka", systemImage: "checkmark.seal.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            Text("\(image.width) x \(image.height) pixels")
                .font(.caption)
                .foregroundStyle(.secondary)

            Label(
                "Cover: \(image.contentRating.capitalized)",
                systemImage: coverRatingSystemImage(image.contentRating)
            )
            .font(.caption)
            .foregroundStyle(
                image.contentRating == "safe"
                    ? AnyShapeStyle(.secondary)
                    : AnyShapeStyle(palette.statusWarning)
            )
            .help(coverRatingHelp)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(palette.surfaceRaised, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.border))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(studioLanguageName(image.language)) \(image.inventoryItemLabel), live on MangaBaka, \(image.width) by \(image.height) pixels, \(image.contentRating) cover"
        )
        .help("This cover is live on MangaBaka but was not present in the editable snapshot. It is shown read-only so its source data remains untouched.")
    }

    private func imageEditor(
        _ index: Int,
        fallback image: SableMangaBakaCoverImage
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label(image.inventoryItemLabel, systemImage: image.inventoryGroup.systemImage)
                    .font(.callout.weight(.semibold))
                Spacer()
                Text(studioLanguageName(image.language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ZStack(alignment: .topTrailing) {
                coverThumbnail(image.imageURL, width: 150, height: 210)
                    .frame(maxWidth: .infinity)

                Button(role: .destructive) {
                    store.removeImage(at: index)
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.bordered)
                .help("Remove this cover from the proposed MangaBaka set")
                .padding(6)
            }

            if store.directCoverLinkIsImported(image) {
                directCoverSizeSummary(image)
            }

            TextField("Image URL", text: Binding(
                get: {
                    guard store.draftImages.indices.contains(index) else { return image.url }
                    return store.draftImages[index].url
                },
                set: {
                    guard store.draftImages.indices.contains(index) else { return }
                    store.draftImages[index].url = $0
                    store.imageChanged()
                }
            ))
            .textFieldStyle(.roundedBorder)

            HStack(spacing: 8) {
                TextField("Index", value: Binding(
                    get: {
                        guard store.draftImages.indices.contains(index) else {
                            return image.indexNumeric
                        }
                        return store.draftImages[index].indexNumeric
                    },
                    set: {
                        guard store.draftImages.indices.contains(index) else { return }
                        store.setDraftImageNumber(at: index, to: $0)
                    }
                ), format: .number)
                .frame(width: 68)

                Picker("Language", selection: Binding(
                    get: {
                        guard store.draftImages.indices.contains(index) else {
                            return image.language
                        }
                        return store.draftImages[index].language
                    },
                    set: {
                        guard store.draftImages.indices.contains(index) else { return }
                        store.draftImages[index].language = $0
                        store.imageChanged()
                    }
                )) {
                    ForEach(SableMangaBakaCoverImage.supportedLanguages, id: \.self) {
                        Text(studioLanguageName($0)).tag($0)
                    }
                }
                .labelsHidden()

                Picker("Type", selection: Binding(
                    get: {
                        guard store.draftImages.indices.contains(index) else {
                            return image.type
                        }
                        return store.draftImages[index].type
                    },
                    set: {
                        guard store.draftImages.indices.contains(index) else { return }
                        store.draftImages[index].type = $0
                        store.imageChanged()
                    }
                )) {
                    ForEach(SableMangaBakaCoverImage.supportedTypes, id: \.self) {
                        Text($0.replacingOccurrences(of: "_", with: " ").capitalized).tag($0)
                    }
                }
                .labelsHidden()
            }

            Picker("Cover rating", selection: Binding(
                get: {
                    guard store.draftImages.indices.contains(index) else {
                        return image.contentRating
                    }
                    return store.draftImages[index].contentRating
                },
                set: {
                    store.setDraftImageContentRating(at: index, to: $0)
                }
            )) {
                ForEach(
                    SableMangaBakaCoverImage.supportedRatings,
                    id: \.self
                ) {
                    Text($0.capitalized).tag($0)
                }
            }
            .pickerStyle(.menu)
            .help(coverRatingHelp)

            TextField("Note, such as Special edition", text: Binding(
                get: {
                    guard store.draftImages.indices.contains(index) else {
                        return image.note ?? ""
                    }
                    return store.draftImages[index].note ?? ""
                },
                set: {
                    guard store.draftImages.indices.contains(index) else { return }
                    store.draftImages[index].note = $0.nilIfEmpty
                    store.imageChanged()
                }
            ))
            .textFieldStyle(.roundedBorder)

            HStack {
                Button {
                    store.setDefault(at: index)
                } label: {
                    let isDefault = store.draftImages.indices.contains(index)
                        ? store.draftImages[index].isDefault
                        : image.isDefault
                    Label(
                        isDefault ? "Default" : "Make Default",
                        systemImage: isDefault ? "checkmark.circle.fill" : "circle"
                    )
                }
                .buttonStyle(.plain)

                Spacer()

                Text(image.id == nil ? "New" : "Existing")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(palette.surfaceRaised, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.border))
    }

    private var addURLsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                showManualURLFallback.toggle()
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    Image(
                        systemName:
                            showManualURLFallback
                                ? "chevron.down"
                                : "chevron.right"
                    )
                    .font(.caption.weight(.semibold))
                    .frame(width: 12)
                    .padding(.top, 3)

                    VStack(alignment: .leading, spacing: 3) {
                        Label(
                            "Bulk Cover Links",
                            systemImage: "photo.stack"
                        )
                        .font(.headline)
                        Text(
                            "Paste BBC image links, number them in order, review them against MangaBaka, then apply."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                "\(showManualURLFallback ? "Hide" : "Show") exact cover URL tools"
            )

            if showManualURLFallback {
                VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Paste one direct cover-image URL per line. Links become sequential cover cards starting at the number below.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(action: store.pasteCoverURLs) {
                        Label("Paste URLs", systemImage: "clipboard")
                    }
                    .controlSize(.small)
                    .help("Paste one or more cover image URLs from the clipboard.")
                }

                TextEditor(text: $store.pastedURLs)
                    .font(.body.monospaced())
                    .frame(minHeight: 90)
                    .padding(6)
                    .background(palette.surfaceRaised, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.border))
                    .accessibilityLabel("Cover image URLs, one per line")

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        addURLControls
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        addURLControls
                    }
                }

                HStack {
                    TextField("Optional note", text: $store.addedNote)
                        .textFieldStyle(.roundedBorder)
                    Button("Add and Review Covers") {
                        store.stagePastedURLs()
                        showCurrentCoverSet = true
                    }
                        .buttonStyle(.borderedProminent)
                        .disabled(
                            store.isWorking
                                || store.pastedURLs
                                    .trimmingCharacters(
                                        in: .whitespacesAndNewlines
                                    )
                                    .isEmpty
                        )
                        .help("Check image sizes and add these links to the proposed cover set. Nothing is uploaded until you confirm Apply.")
                }
                }
                .padding(.top, 10)
            }
        }
        .padding(16)
        .sableCoverDataSurface(fill: palette.surface, border: palette.border)
    }

    private var addURLControls: some View {
        Group {
            Picker("Language", selection: $store.addedLanguage) {
                ForEach(SableMangaBakaCoverImage.supportedLanguages, id: \.self) {
                    Text(studioLanguageName($0)).tag($0)
                }
            }
            Picker("Type", selection: $store.addedType) {
                ForEach(SableMangaBakaCoverImage.supportedTypes, id: \.self) {
                    Text($0.replacingOccurrences(of: "_", with: " ").capitalized).tag($0)
                }
            }
            Picker("Rating", selection: $store.addedRating) {
                ForEach(SableMangaBakaCoverImage.supportedRatings, id: \.self) {
                    Text($0.capitalized).tag($0)
                }
            }
            Stepper("Start \(store.startIndex)", value: $store.startIndex, in: 0...10_000)
        }
    }

    @ViewBuilder
    private func directCoverSizeSummary(
        _ image: SableMangaBakaCoverImage
    ) -> some View {
        if let inspection = store.directCoverInspection(for: image) {
            VStack(alignment: .leading, spacing: 4) {
                Label(
                    "\(inspection.width) x \(inspection.height) pixels",
                    systemImage: "photo"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                if let existing = store.existingMangaBakaCover(for: image) {
                    let importedArea = inspection.width * inspection.height
                    let existingArea = existing.width * existing.height
                    Label(
                        importedArea > existingArea
                            ? "Larger than MangaBaka's \(existing.width) x \(existing.height)"
                            : importedArea == existingArea
                                ? "Same size as MangaBaka"
                                : "Smaller than MangaBaka's \(existing.width) x \(existing.height)",
                        systemImage:
                            importedArea > existingArea
                                ? "arrow.up.right"
                                : importedArea == existingArea
                                    ? "equal"
                                    : "arrow.down.right"
                    )
                    .font(.caption)
                    .foregroundStyle(
                        importedArea > existingArea
                            ? AnyShapeStyle(palette.statusSuccess)
                            : importedArea == existingArea
                                ? AnyShapeStyle(.secondary)
                                : AnyShapeStyle(palette.statusWarning)
                    )
                } else {
                    Label(
                        "New MangaBaka cover slot",
                        systemImage: "plus.square"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        } else {
            Label("Image size unavailable", systemImage: "questionmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func studioLanguageCode(_ value: String) -> String {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
        let base = normalized.split(separator: "-").first.map(String.init) ?? ""
        switch base {
        case "jp": return "ja"
        case "kr": return "ko"
        case "cn": return "zh"
        case "": return "unknown"
        default: return base
        }
    }

    private func coverRatingSystemImage(_ rating: String) -> String {
        switch rating {
        case "suggestive":
            return "exclamationmark.shield"
        case "erotica":
            return "eye.trianglebadge.exclamationmark"
        case "pornographic":
            return "hand.raised.fill"
        default:
            return "checkmark.shield"
        }
    }

    private var coverRatingHelp: String {
        "Safe has no sexualized nudity, sexual themes, or suggestive poses. Suggestive includes mild sexual themes, partial or implied nudity, any swimwear, lingerie, or provocative poses. Erotica includes visible nipples or buttocks, erotic near-nudity, sexualized lingerie focus, or bondage and restraint. Pornographic includes visible genitalia, sex acts, sexual fluids, or sex toys, including when censored."
    }

    private func studioLanguageName(_ value: String) -> String {
        let code = studioLanguageCode(value)
        guard code != "unknown" else { return "Other / Unknown" }
        return Locale(identifier: "en").localizedString(forLanguageCode: code)
            ?? code.uppercased()
    }

    private func studioLanguageRank(_ value: String) -> Int {
        let preferredOrder = ["ja", "en", "ko", "zh", "fr", "it", "de", "es", "pt", "nl"]
        return preferredOrder.firstIndex(of: studioLanguageCode(value))
            ?? preferredOrder.count
    }

    private func studioScopeTitle(
        for series: SableMangaBakaSeriesSummary
    ) -> String? {
        [series.nativeTitle, series.title, series.romanizedTitle]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first {
                !$0.isEmpty
                    && $0.caseInsensitiveCompare(series.displayTitle) != .orderedSame
            }
    }

    private func coverThumbnail(_ url: URL?, width: CGFloat, height: CGFloat) -> some View {
        SableMangaBakaRemoteThumbnail(
            url: url,
            width: width,
            height: height
        )
    }

    private func coverFact(
        _ text: String,
        systemImage: String? = nil
    ) -> some View {
        Group {
            if let systemImage {
                Label(text, systemImage: systemImage)
            } else {
                Text(text)
            }
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(palette.surface.opacity(0.82), in: Capsule())
    }

    private func editableCoverNumberFact(
        index: Int,
        fallback image: SableMangaBakaCoverImage
    ) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "number")
            Text("Number")
            TextField(
                "Number",
                value: Binding(
                    get: {
                        guard store.draftImages.indices.contains(index) else {
                            return image.indexNumeric
                        }
                        return store.draftImages[index].indexNumeric
                    },
                    set: {
                        store.setDraftImageNumber(at: index, to: $0)
                    }
                ),
                format: .number
            )
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .frame(width: 48)
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.leading, 6)
        .padding(.trailing, 3)
        .padding(.vertical, 2)
        .background(palette.surface.opacity(0.82), in: Capsule())
        .disabled(!store.draftImages.indices.contains(index))
        .help("Correct this cover's MangaBaka number")
        .accessibilityElement(children: .contain)
    }

    private func coverFactGrid<Content: View>(
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        SableEagerAdaptiveGrid(
            minimumItemWidth: 92,
            horizontalSpacing: 5,
            verticalSpacing: 5
        ) {
            content()
        }
    }

    private func coverSizeText(
        for image: SableMangaBakaCoverImage
    ) -> String {
        let identities = Set([image.previewURL, image.url].compactMap {
            rawValue -> String? in
            guard let rawValue else { return nil }
            let trimmed = rawValue.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !trimmed.isEmpty else { return nil }
            return SableMangaBakaCoverSnapshot.coverURLIdentity(trimmed)
        })

        if let liveImage = store.mangaBakaLiveCovers.first(where: {
            identities.contains(
                SableMangaBakaCoverSnapshot.coverURLIdentity($0.rawURL)
            )
        }) {
            return "\(liveImage.width) x \(liveImage.height)"
        }

        if let suggestion = store.storefrontSuggestions.first(where: {
            identities.contains(
                SableMangaBakaCoverSnapshot.coverURLIdentity($0.imageURL)
            )
        }),
           let width = suggestion.width,
           let height = suggestion.height {
            return "\(width) x \(height)"
        }

        return "Size unknown"
    }

    private func coverTypeDisplayName(_ value: String) -> String {
        switch value {
        case "volume": "Volume"
        case "volume_back": "Back Cover"
        case "audiobook": "Audiobook"
        case "chapter": "Chapter"
        case "season": "Season"
        case "banner": "Banner"
        default:
            value
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
                .capitalized
        }
    }

    private func sourceHostText(_ url: URL?) -> String {
        guard let url else { return "No source URL" }
        if let host = url.host(percentEncoded: false), !host.isEmpty {
            return host
        }
        return url.absoluteString
    }

    private func openRoler(
        for series: SableMangaBakaSeriesSummary?,
        language: String
    ) {
        guard let series,
              let url = SableMangaBakaStorefrontDiscovery.rolerSearchURL(
                for: series,
                language: language
              ) else {
            return
        }
        open(url)
    }

    private func openKoreanStore(
        for series: SableMangaBakaSeriesSummary?,
        provider: SableLibraryBigBookCoversProvider
    ) {
        guard let series,
              let url = SableMangaBakaStorefrontDiscovery
                .koreanStoreSearchURL(
                    for: series,
                    provider: provider
                ) else {
            return
        }
        open(url)
    }

    private func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    private func chooseDownloadFolder() {
        let panel = NSOpenPanel()
        panel.title = "Download MangaBaka Cover Set"
        panel.prompt = "Download Here"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        let access = destination.startAccessingSecurityScopedResource()
        store.downloadCurrentSet(to: destination)
        if access {
            Task {
                while store.isDownloading {
                    try? await Task.sleep(for: .milliseconds(250))
                }
                destination.stopAccessingSecurityScopedResource()
            }
        }
    }
}

private nonisolated extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension View {
    func sableCoverDataSurface(
        fill: Color,
        border: Color,
        cornerRadius: CGFloat = 8
    ) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(border, lineWidth: 1)
            )
    }

    func sableCoverRowSurface(
        fill: Color,
        border: Color,
        accent: Color,
        isSelected: Bool = false,
        cornerRadius: CGFloat = 6
    ) -> some View {
        background(
            isSelected ? accent.opacity(0.10) : fill,
            in: RoundedRectangle(cornerRadius: cornerRadius)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(
                    isSelected ? accent.opacity(0.44) : border,
                    lineWidth: isSelected ? 1.5 : 1
                )
        )
    }
}
