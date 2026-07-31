//
//  SableLibrarySettingsModels.swift
//  Sable's Library
//

import Foundation

nonisolated enum SableLibraryFolderOrganizationDepth: String, Codable, CaseIterable, Identifiable, Sendable {
    case form
    case shelf
    case subShelf

    var id: String { rawValue }

    var label: String {
        switch self {
        case .form: "Form"
        case .shelf: "Shelf"
        case .subShelf: "Subshelf"
        }
    }

    var detail: String {
        switch self {
        case .form:
            "Keeps the current layout: Form / Series."
        case .shelf:
            "Adds the main SSS shelf between form and series."
        case .subShelf:
            "Adds the main SSS shelf and detailed subshelf before the series."
        }
    }

    var includesShelf: Bool {
        self == .shelf || self == .subShelf
    }

    var includesSubShelf: Bool {
        self == .subShelf
    }
}

nonisolated struct CleanupOptions: Codable, Sendable, Equatable {
    var organizeLooseBooks = true
    var renameFiles = true
    var renameFolders = true
    var readingFolderOrganizationDepth = SableLibraryFolderOrganizationDepth.form
    var checkDuplicates = true
    var treatPDFsAsBooks = false

    enum CodingKeys: String, CodingKey {
        case organizeLooseBooks
        case renameFiles
        case renameFolders
        case readingFolderOrganizationDepth
        case checkDuplicates
        case treatPDFsAsBooks
    }

    nonisolated init(
        organizeLooseBooks: Bool = true,
        renameFiles: Bool = true,
        renameFolders: Bool = true,
        readingFolderOrganizationDepth: SableLibraryFolderOrganizationDepth = .form,
        checkDuplicates: Bool = true,
        treatPDFsAsBooks: Bool = false
    ) {
        self.organizeLooseBooks = organizeLooseBooks
        self.renameFiles = renameFiles
        self.renameFolders = renameFolders
        self.readingFolderOrganizationDepth = readingFolderOrganizationDepth
        self.checkDuplicates = checkDuplicates
        self.treatPDFsAsBooks = treatPDFsAsBooks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        organizeLooseBooks = try container.decodeIfPresent(Bool.self, forKey: .organizeLooseBooks) ?? true
        renameFiles = try container.decodeIfPresent(Bool.self, forKey: .renameFiles) ?? true
        renameFolders = try container.decodeIfPresent(Bool.self, forKey: .renameFolders) ?? true
        readingFolderOrganizationDepth = try container.decodeIfPresent(SableLibraryFolderOrganizationDepth.self, forKey: .readingFolderOrganizationDepth) ?? .form
        checkDuplicates = try container.decodeIfPresent(Bool.self, forKey: .checkDuplicates) ?? true
        treatPDFsAsBooks = try container.decodeIfPresent(Bool.self, forKey: .treatPDFsAsBooks) ?? false
    }
}

nonisolated struct LibraryPipelineStageOptions: Codable, Sendable, Equatable {
    var applyCleanup = true
    var moveMissingNumbers = true
    var useComicInfoTitles = true
    var preferredTitleStyle = SableLibraryPreferredTitleStyle.english
    var useMangaBaka = false
    var useMetadataProviders = false
    var downloadSeriesCovers = false
    var refreshComicInfo = false
    var repairEPUBs = true
    var deepEPUBContentChecks = true
    var epubClinicRepairScopes = SableLibraryEPUBRepairScope.all
    var epubClinicModifiedWindow = SableEPUBClinicModifiedWindow.all
    var modifiedWindowsByStage: [String: SableLibraryModifiedWindow] = [:]
    var optimizePageImageEPUBs = false
    var writeEPUBImportMetadata = true
    var exportReports = true

    enum CodingKeys: String, CodingKey {
        case applyCleanup
        case moveMissingNumbers
        case useComicInfoTitles
        case preferredTitleStyle
        case useMangaBaka
        case useMetadataProviders
        case downloadSeriesCovers
        case refreshComicInfo
        case repairEPUBs
        case deepEPUBContentChecks
        case epubClinicRepairScopes
        case epubClinicModifiedWindow
        case modifiedWindowsByStage
        case optimizePageImageEPUBs
        case writeEPUBImportMetadata
        case exportReports
    }

    nonisolated init(
        applyCleanup: Bool = true,
        moveMissingNumbers: Bool = true,
        useComicInfoTitles: Bool = true,
        preferredTitleStyle: SableLibraryPreferredTitleStyle = .english,
        useMangaBaka: Bool = false,
        useMetadataProviders: Bool = false,
        downloadSeriesCovers: Bool = false,
        refreshComicInfo: Bool = false,
        repairEPUBs: Bool = true,
        deepEPUBContentChecks: Bool = true,
        epubClinicRepairScopes: Set<SableLibraryEPUBRepairScope> = SableLibraryEPUBRepairScope.all,
        epubClinicModifiedWindow: SableEPUBClinicModifiedWindow = .all,
        modifiedWindowsByStage: [String: SableLibraryModifiedWindow] = [:],
        optimizePageImageEPUBs: Bool = false,
        writeEPUBImportMetadata: Bool = true,
        exportReports: Bool = true
    ) {
        self.applyCleanup = applyCleanup
        self.moveMissingNumbers = moveMissingNumbers
        self.useComicInfoTitles = useComicInfoTitles
        self.preferredTitleStyle = preferredTitleStyle
        self.useMangaBaka = useMangaBaka
        self.useMetadataProviders = useMetadataProviders
        self.downloadSeriesCovers = downloadSeriesCovers
        self.refreshComicInfo = refreshComicInfo
        self.repairEPUBs = repairEPUBs
        self.deepEPUBContentChecks = deepEPUBContentChecks
        self.epubClinicRepairScopes = epubClinicRepairScopes
        self.epubClinicModifiedWindow = epubClinicModifiedWindow
        self.modifiedWindowsByStage = modifiedWindowsByStage
        self.optimizePageImageEPUBs = optimizePageImageEPUBs
        self.writeEPUBImportMetadata = writeEPUBImportMetadata
        self.exportReports = exportReports
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        applyCleanup = try container.decodeIfPresent(Bool.self, forKey: .applyCleanup) ?? true
        moveMissingNumbers = try container.decodeIfPresent(Bool.self, forKey: .moveMissingNumbers) ?? true
        useComicInfoTitles = try container.decodeIfPresent(Bool.self, forKey: .useComicInfoTitles) ?? true
        preferredTitleStyle = try container.decodeIfPresent(SableLibraryPreferredTitleStyle.self, forKey: .preferredTitleStyle) ?? .english
        useMangaBaka = try container.decodeIfPresent(Bool.self, forKey: .useMangaBaka) ?? false
        useMetadataProviders = try container.decodeIfPresent(Bool.self, forKey: .useMetadataProviders) ?? false
        downloadSeriesCovers = try container.decodeIfPresent(Bool.self, forKey: .downloadSeriesCovers) ?? false
        refreshComicInfo = try container.decodeIfPresent(Bool.self, forKey: .refreshComicInfo) ?? false
        repairEPUBs = try container.decodeIfPresent(Bool.self, forKey: .repairEPUBs) ?? true
        deepEPUBContentChecks = try container.decodeIfPresent(Bool.self, forKey: .deepEPUBContentChecks) ?? true
        epubClinicRepairScopes = try container.decodeIfPresent(Set<SableLibraryEPUBRepairScope>.self, forKey: .epubClinicRepairScopes) ?? SableLibraryEPUBRepairScope.all
        epubClinicModifiedWindow = try container.decodeIfPresent(SableEPUBClinicModifiedWindow.self, forKey: .epubClinicModifiedWindow) ?? .all
        modifiedWindowsByStage = try container.decodeIfPresent([String: SableLibraryModifiedWindow].self, forKey: .modifiedWindowsByStage) ?? [:]
        optimizePageImageEPUBs = try container.decodeIfPresent(Bool.self, forKey: .optimizePageImageEPUBs) ?? false
        writeEPUBImportMetadata = try container.decodeIfPresent(Bool.self, forKey: .writeEPUBImportMetadata) ?? true
        exportReports = try container.decodeIfPresent(Bool.self, forKey: .exportReports) ?? true
    }

    nonisolated func modifiedWindow(for stage: LibraryPipelineStage) -> SableLibraryModifiedWindow {
        if let savedWindow = modifiedWindowsByStage[stage.rawValue] {
            return savedWindow
        }
        return stage == .epubClinic ? epubClinicModifiedWindow : .all
    }

    nonisolated mutating func setModifiedWindow(
        _ window: SableLibraryModifiedWindow,
        for stage: LibraryPipelineStage
    ) {
        modifiedWindowsByStage[stage.rawValue] = window
        if stage == .epubClinic {
            epubClinicModifiedWindow = window
        }
    }
}

enum SableLibraryModifiedWindow: String, Codable, CaseIterable, Identifiable, Sendable {
    case all
    case today
    case last7Days
    case last30Days

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All EPUBs"
        case .today: "Today"
        case .last7Days: "Last 7 days"
        case .last30Days: "Last 30 days"
        }
    }

    var shortTitle: String {
        switch self {
        case .all: "All"
        case .today: "Today"
        case .last7Days: "7 days"
        case .last30Days: "30 days"
        }
    }

    var libraryTitle: String {
        switch self {
        case .all: "All items"
        case .today: "Today"
        case .last7Days: "Last 7 days"
        case .last30Days: "Last 30 days"
        }
    }

    var repairScopeDescription: String {
        switch self {
        case .all: "all EPUBs"
        case .today: "EPUBs changed today"
        case .last7Days: "EPUBs changed in the last 7 days"
        case .last30Days: "EPUBs changed in the last 30 days"
        }
    }

    var libraryScopeDescription: String {
        switch self {
        case .all: "all library items"
        case .today: "items changed today"
        case .last7Days: "items changed in the last 7 days"
        case .last30Days: "items changed in the last 30 days"
        }
    }

    nonisolated func libraryHelpText(for stage: LibraryPipelineStage) -> String {
        switch self {
        case .all:
            "\(stage.title) checks every matching item in the library."
        case .today:
            "\(stage.title) checks only books and videos whose file date changed today."
        case .last7Days:
            "\(stage.title) checks only books and videos whose file date changed in the last 7 days."
        case .last30Days:
            "\(stage.title) checks only books and videos whose file date changed in the last 30 days."
        }
    }

    var helpText: String {
        switch self {
        case .all:
            "Clinic checks every EPUB found by the inventory."
        case .today:
            "Clinic checks only EPUB files whose file date changed today."
        case .last7Days:
            "Clinic checks only EPUB files whose file date changed in the last 7 days."
        case .last30Days:
            "Clinic checks only EPUB files whose file date changed in the last 30 days."
        }
    }

    nonisolated func includes(
        modificationDate: Date?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard let modificationDate else {
            return self == .all
        }

        switch self {
        case .all:
            return true
        case .today:
            return calendar.isDate(modificationDate, inSameDayAs: now)
        case .last7Days:
            return modificationDate >= now.addingTimeInterval(-7 * 24 * 60 * 60)
        case .last30Days:
            return modificationDate >= now.addingTimeInterval(-30 * 24 * 60 * 60)
        }
    }
}

typealias SableEPUBClinicModifiedWindow = SableLibraryModifiedWindow

enum SableLibraryPreferredTitleStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case english
    case romaji
    case native

    var id: String { rawValue }

    var label: String {
        switch self {
        case .english: "English"
        case .romaji: "Romaji"
        case .native: "Native"
        }
    }

    var helpText: String {
        switch self {
        case .english:
            "Use English titles when sidecars have them, with romaji or native titles as fallback."
        case .romaji:
            "Use romanized titles when available, then fall back to English or native titles."
        case .native:
            "Use Japanese, Korean, or Chinese titles when available, then fall back to romaji or English."
        }
    }
}

nonisolated struct SableLibraryIntelligenceOptions: Codable, Sendable, Equatable {
    var improveSuggestions = true
    var useLocalLearning = false

    enum CodingKeys: String, CodingKey {
        case improveSuggestions
        case useLocalLearning
    }

    nonisolated init(improveSuggestions: Bool = true, useLocalLearning: Bool = false) {
        self.improveSuggestions = improveSuggestions
        self.useLocalLearning = useLocalLearning
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        improveSuggestions = try container.decodeIfPresent(Bool.self, forKey: .improveSuggestions) ?? true
        useLocalLearning = try container.decodeIfPresent(Bool.self, forKey: .useLocalLearning) ?? false
    }
}

nonisolated struct SableLibraryProviderCredentials: Codable, Sendable, Equatable {
    var tmdbAccessToken = ""
    var tvdbAccessToken = ""
    var mangaBakaPersonalAccessToken = ""
    var rolerUserToken = ""
    var rolerSessionID = ""

    private enum CodingKeys: String, CodingKey {
        case tmdbAccessToken
        case tvdbAccessToken
        case mangaBakaPersonalAccessToken
    }

    init(
        tmdbAccessToken: String = "",
        tvdbAccessToken: String = "",
        mangaBakaPersonalAccessToken: String = "",
        rolerUserToken: String = "",
        rolerSessionID: String = ""
    ) {
        self.tmdbAccessToken = tmdbAccessToken
        self.tvdbAccessToken = tvdbAccessToken
        self.mangaBakaPersonalAccessToken = mangaBakaPersonalAccessToken
        self.rolerUserToken = rolerUserToken
        self.rolerSessionID = rolerSessionID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tmdbAccessToken = try container.decodeIfPresent(String.self, forKey: .tmdbAccessToken) ?? ""
        tvdbAccessToken = try container.decodeIfPresent(String.self, forKey: .tvdbAccessToken) ?? ""
        mangaBakaPersonalAccessToken = try container.decodeIfPresent(
            String.self,
            forKey: .mangaBakaPersonalAccessToken
        ) ?? ""
        rolerUserToken = ""
        rolerSessionID = ""
    }

    var hasAnyCredential: Bool {
        !tmdbAccessToken.trimmedForCredential.isEmpty
            || !tvdbAccessToken.trimmedForCredential.isEmpty
            || !mangaBakaPersonalAccessToken.trimmedForCredential.isEmpty
            || !rolerUserToken.trimmedForCredential.isEmpty
            || !rolerSessionID.trimmedForCredential.isEmpty
    }

    func credential(for provider: SableLibraryMetadataProvider) -> String? {
        let value: String
        switch provider {
        case .tmdb:
            value = tmdbAccessToken
        case .tvdb:
            value = tvdbAccessToken
        case .mangabaka:
            value = mangaBakaPersonalAccessToken
        case .ranobedb, .openLibrary, .myAnimeList, .anilist, .tvmaze, .wikidata, .imdb, .local:
            return nil
        }
        let trimmed = value.trimmedForCredential
        return trimmed.isEmpty ? nil : trimmed
    }
}

private nonisolated extension String {
    var trimmedForCredential: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
