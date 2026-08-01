//
//  SableLibraryProviderCandidate.swift
//  Sable's Library
//

import Foundation
import CryptoKit
#if canImport(CoreGraphics)
import CoreGraphics
#endif
#if canImport(ImageIO)
import ImageIO
#endif

struct SableLibraryProviderCandidate: Sendable, Equatable {
    var provider: SableLibraryMetadataProvider
    var title: String
    var year: Int?
    var mediaType: String?
    var sourceIDs: [SableLibrarySourceID]
    var isbn13: [String]
    var aliases: [String]
    var description: String?
    var genres: [String]
    var tags: [String]
    var contentWarnings: [String]
    var studios: [String]
    var authors: [String]
    var artists: [String]
    var publishers: [String]
    var languages: [String]
    var status: String?
    var contentRating: String?
    var coverURL: String?

    init(
        provider: SableLibraryMetadataProvider,
        title: String,
        year: Int? = nil,
        mediaType: String? = nil,
        sourceIDs: [SableLibrarySourceID] = [],
        isbn13: [String] = [],
        aliases: [String] = [],
        description: String? = nil,
        genres: [String] = [],
        tags: [String] = [],
        contentWarnings: [String] = [],
        studios: [String] = [],
        authors: [String] = [],
        artists: [String] = [],
        publishers: [String] = [],
        languages: [String] = [],
        status: String? = nil,
        contentRating: String? = nil,
        coverURL: String? = nil
    ) {
        self.provider = provider
        self.title = title
        self.year = year
        self.mediaType = mediaType
        self.sourceIDs = sourceIDs
        self.isbn13 = isbn13
        self.aliases = aliases
        self.description = description
        self.genres = genres
        self.tags = tags
        self.contentWarnings = contentWarnings
        self.studios = studios
        self.authors = authors
        self.artists = artists
        self.publishers = publishers
        self.languages = languages
        self.status = status
        self.contentRating = contentRating
        self.coverURL = coverURL
    }
}

enum SableLibraryProviderCoverRole: String, Codable, Sendable, Equatable {
    case normal
    case specialEdition
    case alternativeEdition
    case bonus
    case backCover
    case audiobook
    case other
}

enum SableLibraryProviderCoverQuality: String, Codable, Sendable, Equatable {
    case highResolution
    case usable
    case lowResolution
    case unknown
}

enum SableLibraryCoverSource: String, Codable, Sendable, Equatable, CaseIterable {
    case bookLiveJP = "booklive_jp"
    case bookWalkerJP = "bookwalker_jp"
    case bookWalkerGlobal = "bookwalker_global"
    case mangaBaka = "mangabaka"
    case ranobeDB = "ranobedb"
    case amazonJP = "amazon_jp"
    case amazon = "amazon"
    case unknown

    var displayName: String {
        switch self {
        case .bookLiveJP: "BookLive JP"
        case .bookWalkerJP: "BookWalker JP"
        case .bookWalkerGlobal: "BookWalker Global"
        case .mangaBaka: "MangaBaka"
        case .ranobeDB: "RanobeDB"
        case .amazonJP: "Amazon JP"
        case .amazon: "Amazon"
        case .unknown: "Unknown"
        }
    }

    var isStoreSource: Bool {
        switch self {
        case .bookLiveJP, .bookWalkerJP, .bookWalkerGlobal, .amazonJP, .amazon:
            true
        case .mangaBaka, .ranobeDB, .unknown:
            false
        }
    }
}

enum SableLibraryCoverSourcePolicy {
    static let identityBaselineSource = SableLibraryCoverSource.mangaBaka

    static func storeQualityUpgradeOrder(language rawLanguage: String?) -> [SableLibraryCoverSource] {
        switch normalizedLanguage(rawLanguage) {
        case "ja", "jp":
            [.bookLiveJP, .bookWalkerJP, .amazonJP]
        case "en":
            [.bookWalkerGlobal, .amazon]
        default:
            [.bookLiveJP, .bookWalkerGlobal, .bookWalkerJP, .amazonJP, .amazon]
        }
    }

    static func normalCoverDownloadOrder(language rawLanguage: String?) -> [SableLibraryCoverSource] {
        [identityBaselineSource] + storeQualityUpgradeOrder(language: rawLanguage)
    }

    static func canUseAsNormalCover(_ source: SableLibraryCoverSource) -> Bool {
        switch source {
        case .bookLiveJP, .bookWalkerJP, .bookWalkerGlobal, .mangaBaka, .amazonJP, .amazon:
            true
        case .ranobeDB, .unknown:
            false
        }
    }

    static func canUseForSpecialOrAlternativeCover(_ source: SableLibraryCoverSource) -> Bool {
        switch source {
        case .bookLiveJP, .bookWalkerJP, .bookWalkerGlobal, .mangaBaka:
            true
        case .amazonJP, .amazon, .ranobeDB, .unknown:
            false
        }
    }

    static func missingCoverReason(language rawLanguage: String?) -> String {
        let providerNames = normalCoverDownloadOrder(language: rawLanguage).map(\.displayName).joined(separator: ", ")
        return "No trusted cover found in \(providerNames)."
    }

    static func missingCoverReason(
        language rawLanguage: String?,
        pass: SableLibraryCoverDownloadPass
    ) -> String {
        let sources: [SableLibraryCoverSource]
        switch pass {
        case .combined:
            sources = normalCoverDownloadOrder(language: rawLanguage)
        case .mangaBakaBaseline:
            sources = [identityBaselineSource]
        case .storeQualityUpgrade:
            sources = storeQualityUpgradeOrder(language: rawLanguage)
        }
        let providerNames = sources.map(\.displayName).joined(separator: ", ")
        let language = normalizedLanguage(rawLanguage)?.uppercased() ?? "UNKNOWN"
        return "\(pass.displayName) (\(language)) found no trusted cover in \(providerNames)."
    }

    private static func normalizedLanguage(_ rawLanguage: String?) -> String? {
        guard let rawLanguage else { return nil }
        let language = rawLanguage
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if language.hasPrefix("ja") { return "ja" }
        if language.hasPrefix("jp") { return "jp" }
        if language.hasPrefix("en") { return "en" }
        return language.isEmpty ? nil : language
    }
}

enum SableLibraryCoverDownloadPass: String, Codable, Sendable, Equatable, CaseIterable {
    case combined
    case mangaBakaBaseline
    case storeQualityUpgrade

    var displayName: String {
        switch self {
        case .combined:
            "Combined cover search"
        case .mangaBakaBaseline:
            "MangaBaka baseline"
        case .storeQualityUpgrade:
            "Store quality upgrade"
        }
    }
}

enum SableLibraryBigBookCoversProvider: String, Codable, Sendable, Equatable, CaseIterable {
    case bookLiveJP = "bl"
    case bookWalkerJP = "bw"
    case bookWalkerGlobal = "bw-g"
    case amazonJP = "amz-jp"
    case amazon = "amz"
    case amazonUK = "amz-uk"
    case audibleUS = "audible-us"
    case appleBooksUS = "local-apple-books-us"
    case amazonItaly = "amz-it"
    case amazonSpain = "amz-es"
    case amazonGermany = "amz-de"
    case amazonNetherlands = "amz-nl"
    case amazonFrance = "amz-fr"
    case yes24 = "yes24"
    case kyobo = "kyobo"
    case aladin = "aladin"
    case ridibooks = "ridi"
    case shueisha = "shueisha"
    case rakutenKobo = "local-kobo"
    case rakutenKoboNetherlands = "local-kobo-nl"
    case rakutenKoboJapan = "local-kobo-jp"
    case rakutenKoboFrance = "local-kobo-fr"
    case rakutenKoboGermany = "local-kobo-de"
    case rakutenKoboItaly = "local-kobo-it"
    case rakutenKoboSpain = "local-kobo-es"
    case rakutenKoboUK = "local-kobo-uk"
    case barnesNobleUS = "local-bn-us"
    case crunchyrollStore = "local-cr-store"

    var source: SableLibraryCoverSource {
        switch self {
        case .bookLiveJP: .bookLiveJP
        case .bookWalkerJP: .bookWalkerJP
        case .bookWalkerGlobal: .bookWalkerGlobal
        case .amazonJP: .amazonJP
        case .amazon,
             .amazonUK,
             .audibleUS,
             .amazonItaly,
             .amazonSpain,
             .amazonGermany,
             .amazonNetherlands,
             .amazonFrance:
            .amazon
        case .appleBooksUS,
             .yes24,
             .kyobo,
             .aladin,
             .ridibooks,
             .shueisha,
             .rakutenKobo,
             .rakutenKoboNetherlands,
             .rakutenKoboJapan,
             .rakutenKoboFrance,
             .rakutenKoboGermany,
             .rakutenKoboItaly,
             .rakutenKoboSpain,
             .rakutenKoboUK,
             .barnesNobleUS,
             .crunchyrollStore:
            .unknown
        }
    }

    var displayName: String {
        switch self {
        case .bookLiveJP: "BookLive JP"
        case .bookWalkerJP: "BookWalker JP"
        case .bookWalkerGlobal: "BookWalker Global"
        case .amazonJP: "Amazon Japan"
        case .amazon: "Amazon US"
        case .amazonUK: "Amazon UK"
        case .audibleUS: "Audible"
        case .appleBooksUS: "Apple Books"
        case .amazonItaly: "Amazon Italy"
        case .amazonSpain: "Amazon Spain"
        case .amazonGermany: "Amazon Germany"
        case .amazonNetherlands: "Amazon Netherlands"
        case .amazonFrance: "Amazon France"
        case .yes24: "YES24"
        case .kyobo: "Kyobo"
        case .aladin: "Aladin"
        case .ridibooks: "Ridibooks"
        case .shueisha: "Shueisha Official"
        case .rakutenKobo: "Rakuten Kobo"
        case .rakutenKoboNetherlands: "Rakuten Kobo Netherlands"
        case .rakutenKoboJapan: "Rakuten Kobo Japan"
        case .rakutenKoboFrance: "Rakuten Kobo France"
        case .rakutenKoboGermany: "Rakuten Kobo Germany"
        case .rakutenKoboItaly: "Rakuten Kobo Italy"
        case .rakutenKoboSpain: "Rakuten Kobo Spain"
        case .rakutenKoboUK: "Rakuten Kobo UK"
        case .barnesNobleUS: "Barnes & Noble / Nook"
        case .crunchyrollStore: "Crunchyroll Store"
        }
    }

    var languageCode: String {
        switch self {
        case .bookLiveJP,
             .bookWalkerJP,
             .amazonJP,
             .shueisha,
             .rakutenKoboJapan:
            "ja"
        case .bookWalkerGlobal,
             .amazon,
             .amazonUK,
             .audibleUS,
             .appleBooksUS,
             .rakutenKobo,
             .rakutenKoboUK,
             .barnesNobleUS,
             .crunchyrollStore:
            "en"
        case .amazonItaly:
            "it"
        case .amazonSpain:
            "es"
        case .amazonGermany:
            "de"
        case .amazonNetherlands, .rakutenKoboNetherlands:
            "nl"
        case .amazonFrance, .rakutenKoboFrance:
            "fr"
        case .rakutenKoboGermany:
            "de"
        case .rakutenKoboItaly:
            "it"
        case .rakutenKoboSpain:
            "es"
        case .yes24, .kyobo, .aladin, .ridibooks:
            "ko"
        }
    }

    var discoveryPriority: Int {
        switch self {
        case .bookLiveJP, .bookWalkerGlobal: 0
        case .bookWalkerJP: 1
        case .amazonJP, .amazon: 2
        case .amazonUK: 3
        case .shueisha: 4
        case .audibleUS: 5
        case .appleBooksUS: 6
        case .yes24: 7
        case .kyobo: 8
        case .aladin: 9
        case .ridibooks: 10
        case .rakutenKoboJapan: 11
        case .rakutenKobo: 12
        case .rakutenKoboUK: 13
        case .barnesNobleUS: 14
        case .rakutenKoboNetherlands: 15
        case .rakutenKoboFrance: 16
        case .rakutenKoboGermany: 17
        case .rakutenKoboItaly: 18
        case .rakutenKoboSpain: 19
        case .amazonFrance: 20
        case .amazonGermany: 21
        case .amazonItaly: 22
        case .amazonSpain: 23
        case .amazonNetherlands: 24
        case .crunchyrollStore: 25
        }
    }

    var bbcBookProviderIDs: [String] {
        switch self {
        case .bookLiveJP:
            ["bl", "bl-r"]
        case .bookWalkerJP:
            ["bw", "bw-r", "bw-wa", "bw-war"]
        case .bookWalkerGlobal:
            ["bw-g", "bw-gr"]
        default:
            [rawValue]
        }
    }

    var isAmazon: Bool {
        switch self {
        case .amazonJP,
             .amazon,
             .amazonUK,
             .amazonItaly,
             .amazonSpain,
             .amazonGermany,
             .amazonNetherlands,
             .amazonFrance:
            true
        case .bookLiveJP,
             .bookWalkerJP,
             .bookWalkerGlobal,
             .audibleUS,
             .appleBooksUS,
             .yes24,
             .kyobo,
             .aladin,
             .ridibooks,
             .shueisha,
             .rakutenKobo,
             .rakutenKoboNetherlands,
             .rakutenKoboJapan,
             .rakutenKoboFrance,
             .rakutenKoboGermany,
             .rakutenKoboItaly,
             .rakutenKoboSpain,
             .rakutenKoboUK,
             .barnesNobleUS,
             .crunchyrollStore:
            false
        }
    }

    var usesBigBookCoversAPI: Bool {
        switch self {
        case .rakutenKobo,
             .rakutenKoboNetherlands,
             .rakutenKoboJapan,
             .rakutenKoboFrance,
             .rakutenKoboGermany,
             .rakutenKoboItaly,
             .rakutenKoboSpain,
             .rakutenKoboUK,
             .barnesNobleUS,
             .crunchyrollStore:
            false
        default:
            true
        }
    }

    var isRakutenKobo: Bool {
        switch self {
        case .rakutenKobo,
             .rakutenKoboNetherlands,
             .rakutenKoboJapan,
             .rakutenKoboFrance,
             .rakutenKoboGermany,
             .rakutenKoboItaly,
             .rakutenKoboSpain,
             .rakutenKoboUK:
            true
        default:
            false
        }
    }

    var isBarnesNoble: Bool {
        self == .barnesNobleUS
    }

    var isCrunchyrollStore: Bool {
        self == .crunchyrollStore
    }

    static func provider(for source: SableLibraryCoverSource) -> SableLibraryBigBookCoversProvider? {
        switch source {
        case .bookLiveJP: .bookLiveJP
        case .bookWalkerJP: .bookWalkerJP
        case .bookWalkerGlobal: .bookWalkerGlobal
        case .amazonJP: .amazonJP
        case .amazon: .amazon
        case .mangaBaka, .ranobeDB, .unknown: nil
        }
    }
}

struct SableLibraryBigBookCoversSeriesCandidate: Sendable, Equatable {
    var provider: SableLibraryBigBookCoversProvider
    var id: String
    var title: String
    var url: String?
    var type: String?
    var bookType: String?
    var bookTypeWasExplicit: Bool = true
    var thumbnailURL: String?
    var publicationType: String? = nil
}

struct SableLibraryManualCoverSeriesMatch: Codable, Sendable, Equatable, Identifiable {
    var source: SableLibraryCoverSource
    var providerID: String
    var itemType: String
    var title: String
    var mediaType: String?
    var bookType: String?
    var url: String?
    var thumbnailURL: String?

    var id: String {
        "\(source.rawValue):\(providerID)"
    }

    var provider: SableLibraryBigBookCoversProvider? {
        SableLibraryBigBookCoversProvider.provider(for: source)
    }
}

struct SableLibraryBigBookCoversBookCandidate: Sendable, Equatable {
    var provider: SableLibraryBigBookCoversProvider
    var id: String
    var seriesID: String?
    var title: String
    var url: String?
    var coverURL: String
    var coverFallbackURLs: [String]
    var volumeNumber: Double?
    var volumeType: String?
    var sequenceIndex: Int
    var bookType: String?
    var publicationType: String? = nil
}

struct SableLibraryCoverDownloadLocalBook: Sendable, Equatable {
    var fileName: String
    var volumeNumber: Double?
}

struct SableLibraryCoverDownloadRequest: Sendable, Equatable {
    var seriesTitle: String
    var mediaType: String?
    var queryTitles: [String]
    var isbn13: [String]
    var isbn13ByLanguage: [String: [String]]
    var mangaBakaSeriesID: String?
    var mangaBakaSeriesBundle: SableLibraryMangaBakaSeriesBundle?
    var manualSeriesMatches: [SableLibraryManualCoverSeriesMatch]
    var localBooks: [SableLibraryCoverDownloadLocalBook]
    var languages: [String] = ["jp", "en"]
    var includeSpecials: Bool = true
    var refreshExistingNormalCovers: Bool = false
    var verifyExistingStoreEvidenceOnly: Bool = false
    var replaceUnprovenNormalCovers: Bool = false
    var downloadPass: SableLibraryCoverDownloadPass = .combined

    init(
        seriesTitle: String,
        mediaType: String? = nil,
        queryTitles: [String],
        isbn13: [String] = [],
        isbn13ByLanguage: [String: [String]] = [:],
        mangaBakaSeriesID: String? = nil,
        mangaBakaSeriesBundle: SableLibraryMangaBakaSeriesBundle? = nil,
        manualSeriesMatches: [SableLibraryManualCoverSeriesMatch] = [],
        localBooks: [SableLibraryCoverDownloadLocalBook],
        languages: [String] = ["jp", "en"],
        includeSpecials: Bool = true,
        refreshExistingNormalCovers: Bool = false,
        verifyExistingStoreEvidenceOnly: Bool = false,
        replaceUnprovenNormalCovers: Bool = false,
        downloadPass: SableLibraryCoverDownloadPass = .combined
    ) {
        self.seriesTitle = seriesTitle
        self.mediaType = mediaType
        self.queryTitles = SableLibraryCoverDownloadPlanner.uniqueNonEmpty(queryTitles)
        self.isbn13 = SableLibraryCoverDownloadPlanner.normalizedISBNQueries(isbn13)
        var localizedISBNs: [String: [String]] = [:]
        for (key, values) in isbn13ByLanguage {
            let language = SableLibraryCoverDownloadPlanner.normalizedLanguage(key)
            localizedISBNs[language, default: []].append(contentsOf: values)
        }
        self.isbn13ByLanguage = localizedISBNs.mapValues(
            SableLibraryCoverDownloadPlanner.normalizedISBNQueries
        )
        self.mangaBakaSeriesID = mangaBakaSeriesID
        self.mangaBakaSeriesBundle = mangaBakaSeriesBundle
        self.manualSeriesMatches = manualSeriesMatches
        self.localBooks = localBooks
        self.languages = languages
        self.includeSpecials = includeSpecials
        self.refreshExistingNormalCovers = refreshExistingNormalCovers
        self.verifyExistingStoreEvidenceOnly = verifyExistingStoreEvidenceOnly
        self.replaceUnprovenNormalCovers = replaceUnprovenNormalCovers
        self.downloadPass = downloadPass
    }

    func isbn13(for language: String) -> [String] {
        let localized = isbn13ByLanguage[SableLibraryCoverDownloadPlanner.normalizedLanguage(language)] ?? []
        return localized.isEmpty ? isbn13 : localized
    }

    func manualSeriesMatch(for source: SableLibraryCoverSource) -> SableLibraryManualCoverSeriesMatch? {
        manualSeriesMatches.first { $0.source == source }
    }

    var mangaBakaSeriesIDs: [String] {
        if let manualID = manualSeriesMatch(for: .mangaBaka)?.providerID {
            return [manualID]
        }
        if let mangaBakaSeriesBundle,
           !mangaBakaSeriesBundle.members.isEmpty {
            return mangaBakaSeriesBundle.seriesIDs.map(String.init)
        }
        return mangaBakaSeriesID.map { [$0] } ?? []
    }

    func trustsMangaBakaSeriesID(_ seriesID: String) -> Bool {
        mangaBakaSeriesIDs.contains(seriesID)
    }
}

struct SableLibraryDownloadedCoverManifestCover: Codable, Sendable, Equatable {
    var language: String
    var source: String
    var role: SableLibraryProviderCoverRole
    var status: String
    var path: String
    var width: Int?
    var height: Int?
    var bytes: Int?
    var url: String?
    var providerURL: String?
    var editionNote: String?
    var providerTitle: String? = nil
    var providerSeriesID: String? = nil
    var providerItemID: String? = nil
    var providerVolume: Double? = nil
    var providerMediaType: String? = nil

    enum CodingKeys: String, CodingKey {
        case language
        case source
        case role
        case status
        case path
        case width
        case height
        case bytes
        case url
        case providerURL = "provider_url"
        case editionNote = "edition_note"
        case providerTitle = "provider_title"
        case providerSeriesID = "provider_series_id"
        case providerItemID = "provider_item_id"
        case providerVolume = "provider_volume"
        case providerMediaType = "provider_media_type"
    }
}

struct SableLibraryDownloadedCoverManifestEntry: Codable, Sendable, Equatable {
    var bookFile: String
    var volume: Double?
    var covers: [SableLibraryDownloadedCoverManifestCover]

    enum CodingKeys: String, CodingKey {
        case bookFile = "book_file"
        case volume
        case covers
    }
}

struct SableLibraryCoverSearchAttempt: Codable, Sendable, Equatable {
    var schemaVersion: Int = 1
    var language: String
    var pass: SableLibraryCoverDownloadPass
    var completedAt: String
    var providers: [String]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case language
        case pass
        case completedAt = "completed_at"
        case providers
    }
}

struct SableLibraryDownloadedCoverManifest: Codable, Sendable, Equatable {
    var version: Int = 2
    var generatedAt: String
    var generator: String = "Sable's Library"
    var seriesTitle: String? = nil
    var mediaType: String? = nil
    var manualSeriesMatches: [SableLibraryManualCoverSeriesMatch]? = nil
    var searchAttempts: [SableLibraryCoverSearchAttempt]? = nil
    var entries: [SableLibraryDownloadedCoverManifestEntry]
    var skipped: [String]

    enum CodingKeys: String, CodingKey {
        case version
        case generatedAt = "generated_at"
        case generator
        case seriesTitle = "series_title"
        case mediaType = "media_type"
        case manualSeriesMatches = "manual_series_matches"
        case searchAttempts = "search_attempts"
        case entries
        case skipped
    }
}

struct SableLibraryCoverDownloadResult: Sendable, Equatable {
    var manifest: SableLibraryDownloadedCoverManifest
    var downloadedCount: Int
    var reusedCount: Int
    var skipped: [String]
}

enum SableLibraryCoverDownloadError: LocalizedError {
    case noLocalBooks
    case noQueries
    case noTrustedCovers(String)
    case coverBelowMinimum(width: Int, height: Int)
    case invalidProviderResponse(String)
    case unsafeCoverPath(String)

    var errorDescription: String? {
        switch self {
        case .noLocalBooks:
            "No EPUB or book files were found in this series folder."
        case .noQueries:
            "No usable series title was available for cover lookup."
        case .noTrustedCovers(let reason):
            reason
        case .coverBelowMinimum(let width, let height):
            "The best image was only \(width) x \(height). Library cover archives must be at least 500 x 700 and 350,000 pixels."
        case .invalidProviderResponse(let reason):
            "The cover provider response could not be read: \(reason)"
        case .unsafeCoverPath(let path):
            "The cover path is outside the library and was refused: \(path)"
        }
    }
}

struct SableLibraryBigBookCoversClient: Sendable {
    static let maximumConcurrentConnectionsPerHost = 4

    var apiBaseURL = URL(string: "https://c.roler.dev")!
    var dataLoader: (@Sendable (URL) async throws -> Data)? = nil
    private actor ProviderRequestGate {
        private var nextRequestAt = Date.distantPast

        func reserve(minimumSpacing: TimeInterval) -> TimeInterval {
            let now = Date()
            let reservedAt = max(now, nextRequestAt)
            nextRequestAt = reservedAt.addingTimeInterval(minimumSpacing)
            return max(0, reservedAt.timeIntervalSince(now))
        }

        func postpone(by delay: TimeInterval) {
            nextRequestAt = max(nextRequestAt, Date().addingTimeInterval(delay))
        }
    }

    private static let requestGate = ProviderRequestGate()
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpMaximumConnectionsPerHost =
            SableLibraryBigBookCoversClient
                .maximumConcurrentConnectionsPerHost
        return URLSession(configuration: configuration)
    }()

    func search(
        query: String,
        provider: SableLibraryBigBookCoversProvider,
        includeMature: Bool = true
    ) async throws -> [SableLibraryBigBookCoversSeriesCandidate] {
        var components = URLComponents(url: apiBaseURL.appendingPathComponent("search"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "provider", value: provider.rawValue),
            URLQueryItem(name: "include_mature", value: includeMature ? "true" : "false")
        ]
        guard let url = components?.url else { return [] }
        let data = try await providerData(from: url)
        return try Self.seriesCandidates(fromSearchData: data, provider: provider)
    }

    func books(
        itemID: String,
        itemType: String = "series",
        provider: SableLibraryBigBookCoversProvider,
        apiProviderID: String? = nil,
        maximumPages: Int? = nil
    ) async throws -> [SableLibraryBigBookCoversBookCandidate] {
        let responseProviderID = apiProviderID ?? provider.rawValue
        let providerItemType = itemType.lowercased() == "book" ? "book" : "series"
        let shouldPaginate =
            provider.usesBigBookCoversAPI
                && providerItemType == "series"
        let maximumPage = shouldPaginate
            ? maximumPages.map { max($0, 1) }
            : 1
        var books: [SableLibraryBigBookCoversBookCandidate] = []
        var seen = Set<String>()
        var page = 1

        while maximumPage.map({ page <= $0 }) ?? true {
            guard let url = booksURL(
                itemID: itemID,
                itemType: providerItemType,
                apiProviderID: responseProviderID,
                page: page
            ) else {
                break
            }
            let data = try await providerData(from: url)
            let pageBooks = try Self.bookCandidates(
                fromBooksData: data,
                provider: provider,
                responseProviderID: responseProviderID
            )
            let previousSeenCount = seen.count
            for book in pageBooks
            where seen.insert("\(book.provider.rawValue):\(book.id)").inserted {
                books.append(book)
            }
            let addedBookCount = seen.count - previousSeenCount
            if !shouldPaginate
                || pageBooks.count < Self.booksPageSize
                || addedBookCount == 0 {
                break
            }
            page += 1
        }

        return books.enumerated().map { offset, book in
            var orderedBook = book
            if orderedBook.volumeNumber == nil {
                orderedBook.sequenceIndex = offset + 1
            }
            return orderedBook
        }
    }

    func booksWithPreviewAlternatives(
        itemID: String,
        itemType: String = "series",
        provider: SableLibraryBigBookCoversProvider,
        maximumPages: Int? = nil
    ) async throws -> [SableLibraryBigBookCoversBookCandidate] {
        let providerIDs = provider.bbcBookProviderIDs
        guard providerIDs.count > 1 else {
            return try await books(
                itemID: itemID,
                itemType: itemType,
                provider: provider,
                maximumPages: maximumPages
            )
        }

        let providerItemType = itemType.lowercased() == "book"
            ? "book"
            : "series"
        let shouldPaginate = providerItemType == "series"
        let maximumPage = shouldPaginate
            ? maximumPages.map { max($0, 1) }
            : 1
        var booksByProvider = Dictionary(
            uniqueKeysWithValues: providerIDs.map { ($0, []) }
        ) as [String: [SableLibraryBigBookCoversBookCandidate]]
        var seenByProvider = Dictionary(
            uniqueKeysWithValues: providerIDs.map { ($0, Set<String>()) }
        )
        var page = 1

        while maximumPage.map({ page <= $0 }) ?? true {
            guard let url = booksURL(
                itemID: itemID,
                itemType: providerItemType,
                apiProviderIDs: providerIDs,
                page: page
            ) else {
                break
            }
            let data = try await providerData(from: url)
            var pageHasMore = false
            var addedAnyBook = false
            for providerID in providerIDs {
                let pageBooks = try Self.bookCandidates(
                    fromBooksData: data,
                    provider: provider,
                    responseProviderID: providerID
                )
                pageHasMore = pageHasMore
                    || pageBooks.count >= Self.booksPageSize
                for book in pageBooks {
                    guard seenByProvider[providerID, default: []]
                        .insert(book.id).inserted else {
                        continue
                    }
                    booksByProvider[providerID, default: []].append(book)
                    addedAnyBook = true
                }
            }
            if !shouldPaginate || !pageHasMore || !addedAnyBook {
                break
            }
            page += 1
        }

        let orderedBooksByProvider = providerIDs.map {
            Self.booksByAssigningSequenceIndexes(
                booksByProvider[$0] ?? []
            )
        }
        return Self.booksByMergingImageAlternatives(
            primary: orderedBooksByProvider.first ?? [],
            variants: Array(orderedBooksByProvider.dropFirst())
        )
    }

    private static func booksByAssigningSequenceIndexes(
        _ books: [SableLibraryBigBookCoversBookCandidate]
    ) -> [SableLibraryBigBookCoversBookCandidate] {
        books.enumerated().map { offset, book in
            var orderedBook = book
            if orderedBook.volumeNumber == nil {
                orderedBook.sequenceIndex = offset + 1
            }
            return orderedBook
        }
    }

    static func booksByMergingImageAlternatives(
        primary: [SableLibraryBigBookCoversBookCandidate],
        variants: [[SableLibraryBigBookCoversBookCandidate]]
    ) -> [SableLibraryBigBookCoversBookCandidate] {
        var merged = primary
        if merged.isEmpty {
            merged = variants.first(where: { !$0.isEmpty }) ?? []
        }
        var indexByID: [String: Int] = [:]
        for index in merged.indices where indexByID[merged[index].id] == nil {
            indexByID[merged[index].id] = index
        }

        for variantBooks in variants {
            for variant in variantBooks {
                guard let index = indexByID[variant.id] else {
                    if primary.isEmpty {
                        indexByID[variant.id] = merged.count
                        merged.append(variant)
                    }
                    continue
                }
                var alternatives = merged[index].coverFallbackURLs
                alternatives.append(variant.coverURL)
                alternatives.append(contentsOf: variant.coverFallbackURLs)
                let primaryURL = merged[index].coverURL
                var seen = Set([primaryURL])
                merged[index].coverFallbackURLs = alternatives.filter {
                    seen.insert($0).inserted
                }
            }
        }
        return merged
    }

    private static let booksPageSize = 40

    private func booksURL(
        itemID: String,
        itemType: String,
        apiProviderID: String,
        page: Int
    ) -> URL? {
        booksURL(
            itemID: itemID,
            itemType: itemType,
            apiProviderIDs: [apiProviderID],
            page: page
        )
    }

    private func booksURL(
        itemID: String,
        itemType: String,
        apiProviderIDs: [String],
        page: Int
    ) -> URL? {
        var components = URLComponents(
            url: apiBaseURL.appendingPathComponent("books"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "sort", value: "asc"),
            URLQueryItem(name: "page", value: String(page))
        ] + apiProviderIDs.map {
            URLQueryItem(
                name: "\(itemType)(\($0))",
                value: itemID
            )
        }
        return components?.url
    }

    static func seriesCandidates(
        fromSearchData data: Data,
        provider: SableLibraryBigBookCoversProvider
    ) throws -> [SableLibraryBigBookCoversSeriesCandidate] {
        try autoreleasepool {
            let object = try jsonObject(from: data)
            let rows = rowsByProvider(in: object, provider: provider)
            return rows.compactMap { row in
                guard let id = text(row["id"]),
                      let title = text(row["title"]) else { return nil }
                let explicitBookType =
                    text(row["bookType"]) ?? text(row["book_type"])
                return SableLibraryBigBookCoversSeriesCandidate(
                    provider: provider,
                    id: id,
                    title: title,
                    url: text(row["url"]),
                    type: text(row["type"]),
                    bookType: explicitBookType
                        ?? inferredBookType(from: title),
                    bookTypeWasExplicit: explicitBookType != nil,
                    thumbnailURL: text(row["thumbnail"]) ?? text(row["thumbnailUrl"]) ?? text(row["thumbnail_url"]),
                    publicationType: normalizedPublicationType(
                        text(row["publicationType"])
                            ?? text(row["publication_type"])
                    ) ?? inferredAmazonPublicationType(
                        id: id,
                        provider: provider,
                        title: title
                    )
                )
            }
        }
    }

    static func bookCandidates(
        fromBooksData data: Data,
        provider: SableLibraryBigBookCoversProvider,
        responseProviderID: String? = nil
    ) throws -> [SableLibraryBigBookCoversBookCandidate] {
        try autoreleasepool {
            let object = try jsonObject(from: data)
            let rows = rowsByProvider(
                in: object,
                providerID: responseProviderID ?? provider.rawValue
            )
            return rows.enumerated().compactMap { index, row in
                guard let id = text(row["id"]),
                      let title = text(row["title"]),
                      let coverURL = text(row["cover"]) ?? text(row["coverURL"]) ?? text(row["cover_url"]) else { return nil }
                let fallbackURLs = (row["coverFallbacks"] as? [String])
                    ?? (row["cover_fallbacks"] as? [String])
                    ?? []
                let volume = row["volume"] as? [String: Any]
                let volumeType = text(volume?["type"])
                    ?? text(row["volumeType"])
                    ?? text(row["volume_type"])
                let reportedVolumeNumber =
                    double(volume?["number"])
                    ?? double(row["volumeNumber"])
                    ?? double(row["volume_number"])
                    ?? providerItemVolumeNumber(
                        id: id,
                        provider: provider
                    )
                let isChapter = volumeType?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .caseInsensitiveCompare("chapter") == .orderedSame
                let volumeNumber = isChapter
                    ? explicitChapterNumber(in: title)
                        ?? reportedVolumeNumber
                    : explicitVolumeNumber(in: title)
                        ?? reportedVolumeNumber
                let sequenceIndex = volumeNumber.flatMap { number -> Int? in
                    let rounded = number.rounded()
                    guard abs(number - rounded) < 0.000_001,
                          rounded >= 0,
                          rounded <= Double(Int.max) else {
                        return nil
                    }
                    return Int(rounded)
                } ?? (index + 1)
                return SableLibraryBigBookCoversBookCandidate(
                    provider: provider,
                    id: id,
                    seriesID: text(row["seriesId"]) ?? text(row["series_id"]) ?? text(volume?["seriesId"]) ?? text(volume?["series_id"]),
                    title: title,
                    url: text(row["url"]),
                    coverURL: coverURL,
                    coverFallbackURLs: fallbackURLs,
                    volumeNumber: volumeNumber,
                    volumeType: volumeType,
                    sequenceIndex: sequenceIndex,
                    bookType: text(row["bookType"])
                        ?? text(row["book_type"])
                        ?? inferredBookType(from: title),
                    publicationType: normalizedPublicationType(
                        text(row["publicationType"])
                            ?? text(row["publication_type"])
                    ) ?? inferredAmazonPublicationType(
                        id: id,
                        provider: provider,
                        title: title
                    )
                )
            }
        }
    }

    private static func explicitChapterNumber(in title: String) -> Double? {
        let normalized = title.applyingTransform(
            .fullwidthToHalfwidth,
            reverse: false
        ) ?? title
        let patterns = [
            #"(?i)\bchapter\s*(\d+(?:\.\d+)?)\b"#,
            #"第?\s*(\d+(?:\.\d+)?)\s*話"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                continue
            }
            let range = NSRange(
                normalized.startIndex..<normalized.endIndex,
                in: normalized
            )
            guard let match = regex.firstMatch(in: normalized, range: range),
                  match.numberOfRanges > 1,
                  let valueRange = Range(
                    match.range(at: 1),
                    in: normalized
                  ),
                  let number = Double(normalized[valueRange]) else {
                continue
            }
            return number
        }
        return nil
    }

    private static func explicitVolumeNumber(in title: String) -> Double? {
        let normalized = title.applyingTransform(
            .fullwidthToHalfwidth,
            reverse: false
        ) ?? title
        let patterns = [
            #"(?i)\bvol(?:ume)?\.?\s*0*(\d+(?:\.\d+)?)\b"#,
            #"(?i)\btome\s*0*(\d+(?:\.\d+)?)\b"#,
            #"(?i)\bband\s*0*(\d+(?:\.\d+)?)\b"#,
            #"(?i)\btomo\s*0*(\d+(?:\.\d+)?)\b"#,
            #"(?i)\bn[º°o]\.?\s*0*(\d+(?:\.\d+)?)\b"#,
            #"第?\s*0*(\d+(?:\.\d+)?)\s*[巻卷]"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                continue
            }
            let range = NSRange(
                normalized.startIndex..<normalized.endIndex,
                in: normalized
            )
            guard let match = regex.firstMatch(in: normalized, range: range),
                  match.numberOfRanges > 1,
                  let valueRange = Range(
                    match.range(at: 1),
                    in: normalized
                  ),
                  let number = Double(normalized[valueRange]) else {
                continue
            }
            return number
        }
        return nil
    }

    private static func normalizedPublicationType(
        _ value: String?
    ) -> String? {
        guard let value else { return nil }
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if normalized.contains("digital")
            || normalized.contains("kindle")
            || normalized.contains("ebook") {
            return "digital"
        }
        if normalized.contains("physical")
            || normalized.contains("paper")
            || normalized.contains("hardcover")
            || normalized.contains("print") {
            return "physical"
        }
        return normalized.isEmpty ? nil : normalized
    }

    private static func inferredBookType(from title: String) -> String? {
        let normalized = title
            .lowercased()
            .folding(
                options: [.diacriticInsensitive, .widthInsensitive],
                locale: .current
            )
        if normalized.contains("audiobook")
            || normalized.contains("audible audio")
            || normalized.contains("audio edition")
            || normalized.contains("オーディオブック")
            || normalized.contains("オーディオ版")
            || normalized.contains("朗読版") {
            return "audiobook"
        }

        let mangaTitle = normalized
            .replacingOccurrences(of: "light novel", with: "")
        if mangaTitle.contains("(manga)")
            || mangaTitle.contains("[manga]")
            || mangaTitle.contains("graphic novel")
            || mangaTitle.contains("コミックス")
            || mangaTitle.contains("コミック")
            || mangaTitle.contains("マンガ")
            || mangaTitle.contains("漫画")
            || mangaTitle.range(
                of: #"\bmanga\b"#,
                options: .regularExpression
            ) != nil {
            return "manga"
        }
        if normalized.contains("light novel")
            || normalized.contains("(novel)")
            || normalized.contains("[novel]")
            || normalized.contains("ライトノベル")
            || normalized.contains("ラノベ")
            || normalized.contains("ノベル")
            || normalized.contains("文庫")
            || normalized.contains("小説") {
            return "novel"
        }
        return nil
    }

    private static func inferredAmazonPublicationType(
        id: String,
        provider: SableLibraryBigBookCoversProvider,
        title: String
    ) -> String? {
        guard provider.isAmazon else { return nil }
        let normalizedTitle = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if normalizedTitle.contains("kindle")
            || normalizedTitle.contains("ebook")
            || normalizedTitle.contains("digital edition")
            || normalizedTitle.contains("電子書籍") {
            return "digital"
        }
        if normalizedTitle.contains("paperback")
            || normalizedTitle.contains("hardcover")
            || normalizedTitle.contains("comic (paper)")
            || normalizedTitle.contains("コミック (紙)")
            || normalizedTitle.contains("コミック（紙）")
            || normalizedTitle.contains("ペーパーバック")
            || normalizedTitle.contains("単行本") {
            return "physical"
        }
        if id.range(
            of: #"^[0-9]{9}[0-9Xx]$"#,
            options: .regularExpression
        ) != nil {
            return "physical"
        }
        if id.range(
            of: #"^B[0-9A-Z]{9}$"#,
            options: .regularExpression
        ) != nil {
            return "digital"
        }
        return nil
    }

    private static func providerItemVolumeNumber(
        id: String,
        provider: SableLibraryBigBookCoversProvider
    ) -> Double? {
        guard provider == .bookLiveJP,
              let suffix = id.split(separator: "-").last,
              suffix.count == 3,
              let number = Int(suffix),
              number > 0 else {
            return nil
        }
        return Double(number)
    }

    private func providerData(from url: URL) async throws -> Data {
        if let dataLoader {
            return try await dataLoader(url)
        }
        let maximumAttempts = 3
        var failedAttempt = 0

        while true {
            do {
                try Task.checkCancellation()
                let gateDelay = await Self.requestGate.reserve(minimumSpacing: 0.75)
                if gateDelay > 0 {
                    try await Task.sleep(for: .seconds(gateDelay))
                }
                let (data, response) = try await Self.session.data(from: url)
                if let http = response as? HTTPURLResponse,
                   !(200..<300).contains(http.statusCode) {
                    failedAttempt += 1
                    guard failedAttempt < maximumAttempts,
                          let delay = Self.providerRetryDelay(
                            statusCode: http.statusCode,
                            retryAfter: http.value(forHTTPHeaderField: "Retry-After"),
                            failedAttempt: failedAttempt
                          ) else {
                        throw SableLibraryCoverDownloadError.invalidProviderResponse("HTTP \(http.statusCode)")
                    }
                    if http.statusCode == 429 || http.statusCode == 503 {
                        await Self.requestGate.postpone(by: delay)
                    }
                    try await Task.sleep(for: .seconds(delay))
                    continue
                }
                guard data.count <= 8 * 1_024 * 1_024 else {
                    throw SableLibraryCoverDownloadError.invalidProviderResponse(
                        "response is larger than 8 MB"
                    )
                }
                return data
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as URLError {
                failedAttempt += 1
                guard failedAttempt < maximumAttempts,
                      Self.isRetryableProviderNetworkError(error) else {
                    throw error
                }
                let delay = Self.providerRetryDelay(
                    statusCode: nil,
                    retryAfter: nil,
                    failedAttempt: failedAttempt
                ) ?? 5
                try await Task.sleep(for: .seconds(delay))
            }
        }
    }

    static func providerRetryDelay(
        statusCode: Int?,
        retryAfter: String?,
        failedAttempt: Int
    ) -> TimeInterval? {
        if let statusCode,
           ![429, 500, 502, 503, 504].contains(statusCode) {
            return nil
        }
        if let retryAfter,
           let providerDelay = TimeInterval(retryAfter.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return min(30, max(1, providerDelay))
        }
        return failedAttempt <= 1 ? 5 : 15
    }

    private static func isRetryableProviderNetworkError(_ error: URLError) -> Bool {
        switch error.code {
        case .timedOut,
             .cannotConnectToHost,
             .networkConnectionLost,
             .notConnectedToInternet,
             .dnsLookupFailed:
            true
        default:
            false
        }
    }

    private static func jsonObject(from data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SableLibraryCoverDownloadError.invalidProviderResponse("expected a JSON object")
        }
        return object
    }

    private static func rowsByProvider(
        in object: [String: Any],
        provider: SableLibraryBigBookCoversProvider
    ) -> [[String: Any]] {
        rowsByProvider(in: object, providerID: provider.rawValue)
    }

    private static func rowsByProvider(
        in object: [String: Any],
        providerID: String
    ) -> [[String: Any]] {
        let data = object["data"] as? [String: Any] ?? [:]
        return data[providerID] as? [[String: Any]] ?? []
    }

    private static func text(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    private static func double(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        guard let text = text(value) else { return nil }
        return Double(text)
    }

    private static func parsedVolumeNumber(in title: String) -> Double? {
        let patterns = [
            #"(?i)\bvol(?:ume)?\.?\s*(\d+(?:\.\d+)?)"#,
            #"(?i)\bbook\s*(\d+(?:\.\d+)?)"#,
            #"(?i)\bpart\s*(\d+(?:\.\d+)?)"#,
            #"第\s*(\d+(?:\.\d+)?)\s*[巻卷]"#,
            #"(\d+(?:\.\d+)?)\s*[巻卷]"#,
            #"\b(\d+(?:\.\d+)?)\b"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(title.startIndex..<title.endIndex, in: title)
            guard let match = regex.firstMatch(in: title, range: range),
                  match.numberOfRanges > 1,
                  let valueRange = Range(match.range(at: 1), in: title),
                  let value = Double(title[valueRange]) else { continue }
            return value
        }
        return nil
    }
}

struct SableLibraryBookLiveSeriesGroupClient: Sendable {
    private struct ProductInspection: Sendable {
        var mediaType: String?
        var groupID: String?
        var groupTitle: String?
        var groupURL: String?
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: configuration)
    }()

    static func tagID(from value: String) -> String? {
        let patterns = [
            #"(?i)/tag_ids/(\d+)"#,
            #"(?i)\btag(?:_id)?\s*[:=]\s*(\d+)\b"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(value.startIndex..<value.endIndex, in: value)
            guard let match = regex.firstMatch(in: value, range: range),
                  match.numberOfRanges > 1,
                  let idRange = Range(match.range(at: 1), in: value) else {
                continue
            }
            return String(value[idRange])
        }
        return nil
    }

    func exactMatch(
        from value: String,
        expectedMediaType: String?
    ) async throws -> SableLibraryManualCoverSeriesMatch? {
        guard let tagID = Self.tagID(from: value) else { return nil }
        let url = Self.groupURL(tagID: tagID)
        let html = try await html(from: url)
        let title = Self.seriesGroupTitle(from: html) ?? "BookLive series group \(tagID)"
        let bookType = Self.normalizedBookType(expectedMediaType)
        return SableLibraryManualCoverSeriesMatch(
            source: .bookLiveJP,
            providerID: tagID,
            itemType: "seriesGroup",
            title: title,
            mediaType: bookType,
            bookType: bookType,
            url: url.absoluteString,
            thumbnailURL: nil
        )
    }

    func manualMatches(
        from candidates: [SableLibraryBigBookCoversSeriesCandidate],
        expectedMediaType: String?
    ) async -> [SableLibraryManualCoverSeriesMatch] {
        var groupMatches: [SableLibraryManualCoverSeriesMatch] = []
        var productMatches: [SableLibraryManualCoverSeriesMatch] = []
        var seenGroupIDs = Set<String>()

        for candidate in candidates.prefix(6) {
            let inspection = await inspect(candidate)
            let candidateMediaType = inspection?.mediaType ?? candidate.bookType
            if let candidateMediaType,
               !SableLibraryCoverDownloadPlanner.providerMediaTypeIsCompatible(
                candidateMediaType,
                isCompatibleWith: expectedMediaType
               ) {
                continue
            }

            if let groupID = inspection?.groupID,
               seenGroupIDs.insert(groupID).inserted {
                let groupTitle = inspection?.groupTitle ?? candidate.title
                groupMatches.append(
                    SableLibraryManualCoverSeriesMatch(
                        source: .bookLiveJP,
                        providerID: groupID,
                        itemType: "seriesGroup",
                        title: groupTitle,
                        mediaType: candidateMediaType ?? Self.normalizedBookType(expectedMediaType),
                        bookType: candidateMediaType ?? Self.normalizedBookType(expectedMediaType),
                        url: inspection?.groupURL ?? Self.groupURL(tagID: groupID).absoluteString,
                        thumbnailURL: candidate.thumbnailURL
                    )
                )
            }

            productMatches.append(
                SableLibraryManualCoverSeriesMatch(
                    source: .bookLiveJP,
                    providerID: candidate.id,
                    itemType: candidate.type ?? "series",
                    title: candidate.title,
                    mediaType: candidateMediaType,
                    bookType: candidateMediaType,
                    url: candidate.url,
                    thumbnailURL: candidate.thumbnailURL
                )
            )
        }
        return groupMatches + productMatches
    }

    func books(
        groupID: String,
        expectedMediaType: String?
    ) async throws -> [SableLibraryBigBookCoversBookCandidate] {
        let html = try await html(from: Self.groupURL(tagID: groupID, newestFirst: true))
        let books = Self.seriesGroupBooks(
            from: html,
            groupID: groupID,
            expectedMediaType: expectedMediaType
        )
        guard !books.isEmpty else {
            throw SableLibraryCoverDownloadError.invalidProviderResponse(
                "BookLive series group \(groupID) returned no compatible book rows"
            )
        }
        return books
    }

    func books(
        productURL rawURL: String,
        expectedMediaType: String?
    ) async throws -> [SableLibraryBigBookCoversBookCandidate] {
        guard let titleID = Self.titleID(from: rawURL),
              let url = URL(string: rawURL) else {
            throw SableLibraryCoverDownloadError.invalidProviderResponse(
                "BookLive returned an invalid product link"
            )
        }
        let html = try await html(from: url)
        guard let bookType = SableLibraryCoverDownloadPlanner.providerPageMediaType(from: html),
              SableLibraryCoverDownloadPlanner.providerMediaTypeIsCompatible(
                bookType,
                isCompatibleWith: expectedMediaType
              ) else {
            throw SableLibraryCoverDownloadError.invalidProviderResponse(
                "BookLive did not prove the requested media type"
            )
        }
        let books = Self.productFamilyBooks(
            from: html,
            titleID: titleID,
            bookType: bookType
        )
        guard !books.isEmpty else {
            throw SableLibraryCoverDownloadError.invalidProviderResponse(
                "BookLive product \(titleID) returned no compatible volume rows"
            )
        }
        return books
    }

    static func titleID(from value: String) -> String? {
        firstCapture(
            in: value,
            pattern: #"(?i)(?:/|[?&])title_id(?:/|=)(\d+)"#
        )
    }

    static func productFamilyBooks(
        from html: String,
        titleID: String,
        bookType: String
    ) -> [SableLibraryBigBookCoversBookCandidate] {
        let escapedTitleID = NSRegularExpression.escapedPattern(for: titleID)
        let pattern =
            #"(?is)<a[^>]+href=["'](/product/index/title_id/"#
            + escapedTitleID
            + #"/vol_no/(\d+))["'][^>]*>\s*(<img\b[^>]*>)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let htmlRange = NSRange(html.startIndex..<html.endIndex, in: html)
        var seenVolumes = Set<String>()
        var books: [SableLibraryBigBookCoversBookCandidate] = []
        for match in regex.matches(in: html, range: htmlRange) {
            guard match.numberOfRanges > 3,
                  let pathRange = Range(match.range(at: 1), in: html),
                  let volumeRange = Range(match.range(at: 2), in: html),
                  let imageTagRange = Range(match.range(at: 3), in: html) else {
                continue
            }
            let rawVolume = String(html[volumeRange])
            guard seenVolumes.insert(rawVolume).inserted,
                  let volumeNumber = Double(rawVolume) else {
                continue
            }
            let imageTag = String(html[imageTagRange])
            guard let rawCover = htmlAttribute("src", in: imageTag),
                  let rawTitle = htmlAttribute("alt", in: imageTag) else {
                continue
            }
            let path = String(html[pathRange])
            let cover = rawCover.replacingOccurrences(
                of: #"/thumbnail/(?:S|M|L|X|2L)\.jpg"#,
                with: "/thumbnail/X.jpg",
                options: .regularExpression
            )
            let fallbackCover = cover.replacingOccurrences(
                of: "/thumbnail/X.jpg",
                with: "/thumbnail/2L.jpg"
            )
            books.append(
                SableLibraryBigBookCoversBookCandidate(
                    provider: .bookLiveJP,
                    id: "\(titleID)-\(rawVolume)",
                    seriesID: titleID,
                    title: cleanText(rawTitle),
                    url: URL(
                        string: path,
                        relativeTo: URL(string: "https://booklive.jp")
                    )?.absoluteURL.absoluteString ?? path,
                    coverURL: cover,
                    coverFallbackURLs: [fallbackCover],
                    volumeNumber: volumeNumber,
                    volumeType: "volume",
                    sequenceIndex: books.count + 1,
                    bookType: bookType
                )
            )
        }
        return books.sorted {
            if $0.volumeNumber != $1.volumeNumber {
                return ($0.volumeNumber ?? .greatestFiniteMagnitude)
                    < ($1.volumeNumber ?? .greatestFiniteMagnitude)
            }
            return $0.id.localizedStandardCompare($1.id) == .orderedAscending
        }
    }

    static func seriesGroupReference(
        fromProductHTML html: String
    ) -> (id: String, title: String, url: String)? {
        let pattern =
            #"(?is)<dt[^>]*>\s*シリーズ\s*</dt>.{0,500}?<a[^>]+href\s*=\s*["']([^"']*/tag_ids/(\d+)[^"']*)["'][^>]*>(.*?)</a>"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: html,
                range: NSRange(html.startIndex..<html.endIndex, in: html)
              ),
              match.numberOfRanges > 3,
              let pathRange = Range(match.range(at: 1), in: html),
              let idRange = Range(match.range(at: 2), in: html),
              let titleRange = Range(match.range(at: 3), in: html) else {
            return nil
        }
        let id = String(html[idRange])
        let title = cleanText(String(html[titleRange]))
            .replacingOccurrences(of: #"シリーズ$"#, with: "", options: .regularExpression)
        let path = String(html[pathRange])
        let url = URL(string: path, relativeTo: URL(string: "https://booklive.jp"))?
            .absoluteURL.absoluteString
            ?? groupURL(tagID: id).absoluteString
        return (id, title, url)
    }

    static func seriesGroupBooks(
        from html: String,
        groupID: String,
        expectedMediaType: String?
    ) -> [SableLibraryBigBookCoversBookCandidate] {
        let blockPattern = #"(?is)<li\s+class=["']item clearfix["'][^>]*>(.*?)</li>"#
        guard let blockRegex = try? NSRegularExpression(pattern: blockPattern) else {
            return []
        }
        let htmlRange = NSRange(html.startIndex..<html.endIndex, in: html)
        var rows: [(id: String, title: String, url: String, cover: String, bookType: String, role: SableLibraryProviderCoverRole)] = []
        var seenIDs = Set<String>()

        for blockMatch in blockRegex.matches(in: html, range: htmlRange) {
            guard blockMatch.numberOfRanges > 1,
                  let blockRange = Range(blockMatch.range(at: 1), in: html) else {
                continue
            }
            let block = String(html[blockRange])
            guard let product = productReference(fromResultBlock: block),
                  let category = firstCapture(
                    in: block,
                    pattern: #"(?is)category-label__text["'][^>]*>\s*([^<]+)\s*</span>"#
                  ),
                  let bookType = mediaType(forCategory: cleanText(category)),
                  SableLibraryCoverDownloadPlanner.providerMediaTypeIsCompatible(
                    bookType,
                    isCompatibleWith: expectedMediaType
                  ),
                  seenIDs.insert(product.id).inserted else {
                continue
            }
            let title = cleanText(product.title)
            if isBundledEdition(title) || isSplitPublication(title) {
                continue
            }
            rows.append((
                id: product.id,
                title: title,
                url: product.url,
                cover: product.cover,
                bookType: bookType,
                role: SableLibraryCoverDownloadPlanner.coverRole(from: title)
            ))
        }

        let normalRows = rows
            .filter { $0.role == .normal }
            .sorted { lhs, rhs in
                let lhsID = Int(lhs.id) ?? .max
                let rhsID = Int(rhs.id) ?? .max
                if lhsID != rhsID {
                    return lhsID < rhsID
                }
                return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
            }
        var books: [SableLibraryBigBookCoversBookCandidate] = []
        for (offset, row) in normalRows.enumerated() {
            books.append(bookCandidate(
                row: row,
                groupID: groupID,
                volumeNumber: Double(offset + 1),
                sequenceIndex: offset + 1
            ))
        }

        for row in rows where row.role != .normal {
            guard let volume = explicitEditionVolume(in: row.title) else { continue }
            books.append(bookCandidate(
                row: row,
                groupID: groupID,
                volumeNumber: volume,
                sequenceIndex: books.count + 1
            ))
        }
        return books
    }

    static func seriesGroupTitle(from html: String) -> String? {
        guard let title = firstCapture(
            in: html,
            pattern: #"(?is)<h1[^>]*>(.*?)</h1>"#
        ) else {
            return nil
        }
        return cleanText(title)
            .replacingOccurrences(of: #"シリーズ作品一覧$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"作品一覧$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func inspect(
        _ candidate: SableLibraryBigBookCoversSeriesCandidate
    ) async -> ProductInspection? {
        guard let rawURL = candidate.url,
              let url = URL(string: rawURL),
              let html = try? await html(from: url) else {
            return nil
        }
        let group = Self.seriesGroupReference(fromProductHTML: html)
        return ProductInspection(
            mediaType: SableLibraryCoverDownloadPlanner.providerPageMediaType(from: html),
            groupID: group?.id,
            groupTitle: group?.title,
            groupURL: group?.url
        )
    }

    private func html(from url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        let (data, response) = try await Self.session.data(for: request)
        guard data.count <= 8 * 1_024 * 1_024,
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) != false,
              let html = String(data: data, encoding: .utf8) else {
            throw SableLibraryCoverDownloadError.invalidProviderResponse(
                "BookLive returned an unreadable series page"
            )
        }
        return html
    }

    private static func productReference(
        fromResultBlock block: String
    ) -> (id: String, title: String, url: String, cover: String)? {
        let pattern =
            #"(?is)<a[^>]+href=["'](/product/index/title_id/(\d+)/vol_no/(\d+))["'][^>]*>\s*(<img\b[^>]*>)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: block,
                range: NSRange(block.startIndex..<block.endIndex, in: block)
              ),
              match.numberOfRanges > 4,
              let pathRange = Range(match.range(at: 1), in: block),
              let idRange = Range(match.range(at: 2), in: block),
              let imageTagRange = Range(match.range(at: 4), in: block) else {
            return nil
        }
        let path = String(block[pathRange])
        let imageTag = String(block[imageTagRange])
        guard let rawCover = htmlAttribute("src", in: imageTag),
              let rawTitle = htmlAttribute("alt", in: imageTag) else {
            return nil
        }
        let cover = rawCover.replacingOccurrences(
            of: #"/thumbnail/(?:S|M|L|X|2L)\.jpg"#,
            with: "/thumbnail/X.jpg",
            options: .regularExpression
        )
        return (
            String(block[idRange]),
            rawTitle,
            URL(string: path, relativeTo: URL(string: "https://booklive.jp"))?
                .absoluteURL.absoluteString ?? path,
            cover
        )
    }

    private static func htmlAttribute(_ name: String, in tag: String) -> String? {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        let pattern = #"\b"# + escapedName + #"\s*=\s*(?:"([^"]*)"|'([^']*)')"#
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ),
              let match = regex.firstMatch(
                in: tag,
                range: NSRange(tag.startIndex..<tag.endIndex, in: tag)
              ) else {
            return nil
        }
        for captureIndex in 1..<match.numberOfRanges {
            guard match.range(at: captureIndex).location != NSNotFound,
                  let captureRange = Range(match.range(at: captureIndex), in: tag) else {
                continue
            }
            return String(tag[captureRange])
        }
        return nil
    }

    private static func bookCandidate(
        row: (id: String, title: String, url: String, cover: String, bookType: String, role: SableLibraryProviderCoverRole),
        groupID: String,
        volumeNumber: Double,
        sequenceIndex: Int
    ) -> SableLibraryBigBookCoversBookCandidate {
        let previewCover = row.cover.replacingOccurrences(
            of: "/thumbnail/X.jpg",
            with: "/thumbnail/2L.jpg"
        )
        return SableLibraryBigBookCoversBookCandidate(
            provider: .bookLiveJP,
            id: "\(row.id)-001",
            seriesID: groupID,
            title: row.title,
            url: row.url,
            coverURL: row.cover,
            coverFallbackURLs: [previewCover],
            volumeNumber: volumeNumber,
            volumeType: "volume",
            sequenceIndex: sequenceIndex,
            bookType: row.bookType
        )
    }

    private static func groupURL(tagID: String, newestFirst: Bool = false) -> URL {
        let suffix = newestFirst ? "/sort/t2" : ""
        return URL(string: "https://booklive.jp/search/keyword/tag_ids/\(tagID)\(suffix)")!
    }

    private static func mediaType(forCategory category: String) -> String? {
        let normalized = category.lowercased()
        if normalized.contains("ラノベ")
            || normalized.contains("ライトノベル")
            || normalized.contains("小説") {
            return "novel"
        }
        if normalized.contains("マンガ")
            || normalized.contains("漫画")
            || normalized.contains("コミック") {
            return "manga"
        }
        if normalized.contains("オーディオ") {
            return "audiobook"
        }
        return nil
    }

    private static func normalizedBookType(_ mediaType: String?) -> String? {
        let normalized = mediaType?.lowercased() ?? ""
        if normalized.contains("novel") || normalized == "book" {
            return "novel"
        }
        if normalized.contains("manga")
            || normalized.contains("comic")
            || normalized.contains("manhwa")
            || normalized.contains("manhua") {
            return "manga"
        }
        return nil
    }

    private static func isBundledEdition(_ title: String) -> Bool {
        let normalized = title.lowercased()
        return [
            "合本版", "合冊版", "全巻セット", "まとめ買い", "complete bundle"
        ].contains(where: normalized.contains)
    }

    private static func isSplitPublication(_ title: String) -> Bool {
        let normalized = title.lowercased()
        return [
            "分冊版", "分冊", "単話版", "单话版", "単話", "单话", "話売り",
            "chapter edition", "serialized edition"
        ].contains(where: normalized.contains)
    }

    private static func explicitEditionVolume(in title: String) -> Double? {
        let normalized = title.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? title
        let patterns = [
            #"(?i)collector'?s edition\s*(\d+(?:\.\d+)?)"#,
            #"新装版\s*(\d+(?:\.\d+)?)"#,
            #"特装版\s*(\d+(?:\.\d+)?)"#,
            #"限定版\s*(\d+(?:\.\d+)?)"#,
            #"第\s*(\d+(?:\.\d+)?)\s*[巻卷]"#,
            #"(\d+(?:\.\d+)?)\s*[巻卷]"#
        ]
        for pattern in patterns {
            guard let value = firstCapture(in: normalized, pattern: pattern),
                  let volume = Double(value) else {
                continue
            }
            return volume
        }
        return nil
    }

    private static func firstCapture(in value: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: value,
                range: NSRange(value.startIndex..<value.endIndex, in: value)
              ),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: value) else {
            return nil
        }
        return String(value[captureRange])
    }

    private static func cleanText(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

nonisolated enum SableLibraryCoverDownloadPlanner {
    static let storeProofSchemaVersion = 4
    static let unprovenReplacementSchemaVersion = 1

    static func unprovenReplacementReason(language rawLanguage: String?) -> String {
        let language = normalizedLanguage(rawLanguage ?? "unknown").uppercased()
        return "Unproven cover replacement \(language) finished:"
    }

    struct ProviderQuery: Sendable, Equatable {
        var value: String
        var isExactISBN: Bool
    }

    static func uniqueNonEmpty(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let key = normalizedTitle(trimmed)
            return seen.insert(key).inserted ? trimmed : nil
        }
    }

    static func orderedQueries(_ values: [String], language: String) -> [String] {
        let unique = uniqueNonEmpty(values)
        let wantsJapanese = normalizedLanguage(language) == "jp"
        let cjk = unique.filter(containsCJK)
        let latin = unique.filter { !containsCJK($0) }
        if wantsJapanese {
            let hasFullNativeTitle = cjk.contains { cjkComparableLength($0) >= 6 }
            let nativeQueries = hasFullNativeTitle
                ? cjk.filter { cjkComparableLength($0) >= 4 }
                : cjk
            return nativeQueries + latin
        }
        return latin + cjk
    }

    static func orderedProviderQueries(
        titles: [String],
        isbn13: [String],
        language: String,
        provider: SableLibraryBigBookCoversProvider
    ) -> [ProviderQuery] {
        let titleQueries = orderedQueries(titles, language: language)
            .prefix(2)
            .map { ProviderQuery(value: $0, isExactISBN: false) }
        var result = Array(titleQueries)
        if provider.isAmazon {
            result.append(contentsOf: normalizedISBNQueries(isbn13).prefix(1).map {
                ProviderQuery(value: $0, isExactISBN: true)
            })
        }

        var seen = Set<String>()
        return result.filter { query in
            let key = query.isExactISBN
                ? "isbn:\(query.value)"
                : "title:\(normalizedTitle(query.value))"
            return seen.insert(key).inserted
        }
    }

    static func normalizedISBNQueries(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            guard let isbn = normalizedISBN13(value),
                  seen.insert(isbn).inserted else {
                return nil
            }
            return isbn
        }
    }

    static func exactIdentifierCandidates(
        _ candidates: [SableLibraryBigBookCoversSeriesCandidate]
    ) -> [SableLibraryBigBookCoversSeriesCandidate] {
        candidates.sorted { lhs, rhs in
            let lhsIsSeries = lhs.type?.lowercased() == "series"
            let rhsIsSeries = rhs.type?.lowercased() == "series"
            if lhsIsSeries != rhsIsSeries {
                return lhsIsSeries
            }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    static func bestSeriesCandidate(
        for query: String,
        requestedSeriesTitle: String? = nil,
        in candidates: [SableLibraryBigBookCoversSeriesCandidate],
        mediaType: String?
    ) -> SableLibraryBigBookCoversSeriesCandidate? {
        rankedSeriesCandidates(
            for: query,
            requestedSeriesTitle: requestedSeriesTitle,
            in: candidates,
            mediaType: mediaType
        ).first
    }

    static func automaticSeriesInspectionLimit(
        for source: SableLibraryCoverSource
    ) -> Int {
        source == .bookLiveJP ? 6 : 2
    }

    static func rankedSeriesCandidates(
        for query: String,
        requestedSeriesTitle: String? = nil,
        in candidates: [SableLibraryBigBookCoversSeriesCandidate],
        mediaType: String?
    ) -> [SableLibraryBigBookCoversSeriesCandidate] {
        let preferredBookType = preferredProviderBookType(mediaType: mediaType)
        let scored = candidates.compactMap { candidate -> (SableLibraryBigBookCoversSeriesCandidate, Double)? in
            let titleMatch = titleScore(query, candidate.title)
                - providerTitleMismatchPenalty(
                    query: requestedSeriesTitle ?? query,
                    providerTitle: candidate.title,
                    preferredBookType: preferredBookType
                )
            guard titleMatch >= 0.72 else { return nil }
            if let requestedSeriesTitle,
               !providerSeriesTitle(candidate.title, belongsTo: requestedSeriesTitle) {
                return nil
            }

            var score = titleMatch
            if let preferredBookType, let bookType = candidate.bookType?.lowercased() {
                score += bookType == preferredBookType ? 0.2 : -0.35
            }
            if candidate.type?.lowercased() == "series" {
                score += 0.05
            }
            return score >= 0.72 ? (candidate, score) : nil
        }
        return scored
            .sorted {
                if $0.1 != $1.1 {
                    return $0.1 > $1.1
                }
                return $0.0.title.count < $1.0.title.count
            }
            .map(\.0)
    }

    static func providerTitle(
        _ providerTitle: String,
        belongsTo requestedSeriesTitle: String
    ) -> Bool {
        let requestedPart = partScopeNumber(in: requestedSeriesTitle)
        let providerPart = partScopeNumber(in: providerTitle)
        if requestedPart != nil || providerPart != nil {
            guard requestedPart == providerPart else { return false }
        }

        for terms in editionQualifierGroups {
            let requestedHasQualifier = containsAny(requestedSeriesTitle.lowercased(), terms)
            let providerHasQualifier = containsAny(providerTitle.lowercased(), terms)
            if requestedHasQualifier != providerHasQualifier {
                return false
            }
        }

        let bothLatin = containsLatinLetter(requestedSeriesTitle) && containsLatinLetter(providerTitle)
        let bothCJK = containsCJK(requestedSeriesTitle) && containsCJK(providerTitle)
        guard bothLatin || bothCJK else { return true }
        return titleScore(requestedSeriesTitle, providerTitle) >= 0.72
    }

    static func providerTitle(
        _ candidateTitle: String,
        belongsToAny requestedSeriesTitles: [String]
    ) -> Bool {
        let titles = uniqueNonEmpty(requestedSeriesTitles)
        guard !titles.isEmpty else { return false }

        let providerUsesCJK = containsCJK(candidateTitle)
        let sameScriptTitles = titles.filter {
            containsCJK($0) == providerUsesCJK
        }
        let comparableTitles = sameScriptTitles.isEmpty ? titles : sameScriptTitles
        return comparableTitles.contains {
            providerTitle(candidateTitle, belongsTo: $0)
        }
    }

    static func providerTitleMatchesLocalSeriesStem(
        _ providerTitle: String,
        localBookTitle: String
    ) -> Bool {
        let providerUsesCJK = containsCJK(providerTitle)
        guard providerUsesCJK == containsCJK(localBookTitle) else {
            return true
        }

        // Local filenames are normally English even when checking a Japanese
        // cover. The same-script title aliases remain authoritative there.
        guard !providerUsesCJK,
              let stem = localSeriesStem(from: localBookTitle) else {
            return true
        }
        if self.providerTitle(providerTitle, belongsTo: stem) {
            return true
        }

        let localPart = partScopeNumber(in: stem)
        let providerPart = partScopeNumber(in: providerTitle)
        if let localPart, let providerPart {
            guard localPart == providerPart else { return false }
        } else if localPart != nil || providerPart != nil {
            // "Part" identifies a distinct publication series in stores.
            // "Arc" is also used locally to organize consecutive volumes even
            // when the provider keeps one uninterrupted series title.
            let localUsesPart = localBookTitle.range(
                of: #"(?i)\bpart\s*\d+\b"#,
                options: .regularExpression
            ) != nil
            let providerUsesPart = providerTitle.range(
                of: #"(?i)\bpart\s*\d+\b"#,
                options: .regularExpression
            ) != nil
            guard !localUsesPart, !providerUsesPart else { return false }
        }

        // Local filenames often insert a translated subtitle before "Part N"
        // or "Volume N", while stores may put a volume subtitle before the
        // franchise title. This is corroborating evidence only; callers still
        // require the provider title to match a trusted series alias.
        let localTokens = orderedTitleTokens(stem)
        let providerTokens = orderedTitleTokens(providerTitle)
        guard localTokens.count >= 2, providerTokens.count >= 2 else {
            return true
        }
        var sharedPrefixCount = 0
        for (localToken, providerToken) in zip(localTokens, providerTokens) {
            guard localToken == providerToken else { break }
            sharedPrefixCount += 1
        }
        if sharedPrefixCount >= 2 {
            return true
        }

        var longestSharedRun = 0
        for localStart in localTokens.indices {
            for providerStart in providerTokens.indices {
                var run = 0
                while localStart + run < localTokens.count,
                      providerStart + run < providerTokens.count,
                      localTokens[localStart + run] == providerTokens[providerStart + run] {
                    run += 1
                }
                longestSharedRun = max(longestSharedRun, run)
            }
        }
        return longestSharedRun >= 3
    }

    static func providerDirectBookTitleIsCompatible(
        _ providerTitle: String,
        requestedSeriesTitles: [String],
        localBookTitle: String,
        localVolume: Double?
    ) -> Bool {
        self.providerTitle(
            providerTitle,
            belongsToAny: requestedSeriesTitles
        )
            && providerTitleMatchesLocalSeriesStem(
                providerTitle,
                localBookTitle: localBookTitle
            )
            && providerBookIdentityIsCompatible(
                providerTitle: providerTitle,
                localBookTitle: localBookTitle,
                localVolume: localVolume
            )
    }

    static func preservedMissingCoverSearchNotes(
        _ skipped: [String],
        requestedLanguages: [String]
    ) -> [String] {
        let requested = Set(requestedLanguages.map(normalizedLanguage))
        return ["jp", "en"].compactMap { language in
            guard !requested.contains(language) else { return nil }
            let prefixes = [
                SableLibraryCoverSourcePolicy.missingCoverReason(language: language)
            ] + SableLibraryCoverDownloadPass.allCases.map {
                SableLibraryCoverSourcePolicy.missingCoverReason(
                    language: language,
                    pass: $0
                )
            }
            return skipped.last { note in
                prefixes.contains { note.hasPrefix($0) }
            }
        }
    }

    static func providerSeriesTitle(
        _ candidateTitle: String,
        belongsTo requestedSeriesTitle: String
    ) -> Bool {
        guard providerTitle(candidateTitle, belongsTo: requestedSeriesTitle) else {
            return false
        }

        let requested = normalizedTitle(requestedSeriesTitle)
        let provider = normalizedTitle(candidateTitle)
        guard !requested.isEmpty, !provider.isEmpty, provider != requested,
              let range = provider.range(of: requested) else {
            return true
        }

        let prefix = String(provider[..<range.lowerBound])
        let suffix = String(provider[range.upperBound...])
        let safePrefixes = ["", "the", "a", "an", "manga", "novel", "lightnovel"]
        let safeSuffixes = ["", "series", "manga", "novel", "lightnovel"]
        return safePrefixes.contains(prefix) && safeSuffixes.contains(suffix)
    }

    private static func localSeriesStem(from localBookTitle: String) -> String? {
        let withoutExtension = (localBookTitle as NSString).deletingPathExtension
        let range = withoutExtension.range(
            of: #"(?i)(?:^|[\s,;:–—-])(?:vol(?:ume)?|book)\.?\s*\d"#,
            options: .regularExpression
        )
        guard let range else { return nil }

        let stem = String(withoutExtension[..<range.lowerBound])
            .replacingOccurrences(
                of: #"\s*[\(\[]\s*(?:18|19|20)\d{2}\s*[\)\]](?:[\s\p{P}]*)$"#,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard !tokenSet(stem).isEmpty else { return nil }
        return stem
    }

    static func providerTitleVolumeNumber(
        in providerTitle: String,
        localBookTitle: String
    ) -> Double? {
        if let explicitVolume = explicitVolumeNumber(in: providerTitle) {
            return explicitVolume
        }
        guard let stem = localSeriesStem(from: localBookTitle),
              let stemRange = providerTitle.range(
                of: stem,
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
              ) else {
            return nil
        }

        var remainder = providerTitle
        remainder.removeSubrange(stemRange)
        remainder = remainder.replacingOccurrences(
            of: #"(?:\(|\[)\s*(?:18|19|20)\d{2}\s*(?:\)|\])"#,
            with: " ",
            options: .regularExpression
        )
        return firstNumberMatch(
            in: remainder,
            pattern: #"(?:^|[\s,;:：–—-])(\d{1,3}(?:\.\d+)?)(?=$|[\s,;:：()\[\]–—-])"#
        )
    }

    private static func orderedTitleTokens(_ value: String) -> [String] {
        value
            .lowercased()
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .replacingOccurrences(of: #"[\p{P}\p{S}]+"#, with: " ", options: .regularExpression)
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count > 1 }
    }

    static func booksFromExactManualSeries(
        _ books: [SableLibraryBigBookCoversBookCandidate],
        match: SableLibraryManualCoverSeriesMatch,
        source: SableLibraryCoverSource
    ) -> [SableLibraryBigBookCoversBookCandidate] {
        if source == .bookLiveJP,
           match.itemType.caseInsensitiveCompare("seriesGroup") == .orderedSame {
            // A BookLive tag is a related-work shelf, not one series identity.
            // Its rows have already been filtered by visible media type, but
            // spin-offs and side stories still need to be removed before the
            // remaining main run receives sequential volume numbers.
            let compatibleBooks = books.filter {
                SableLibraryCoverDownloadPlanner.providerMediaTypeIsCompatible(
                    $0.bookType,
                    isCompatibleWith: match.bookType ?? match.mediaType
                )
                    && manualSeriesBookTitleIsCompatible(
                        $0.title,
                        with: match.title
                    )
            }
            let normalBooks = compatibleBooks
                .filter { coverRole(from: $0.title) == .normal }
                .sorted { lhs, rhs in
                    if lhs.sequenceIndex != rhs.sequenceIndex {
                        return lhs.sequenceIndex < rhs.sequenceIndex
                    }
                    return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
                }
                .enumerated()
                .map { offset, book in
                    var reindexed = book
                    reindexed.volumeNumber = Double(offset + 1)
                    reindexed.sequenceIndex = offset + 1
                    return reindexed
                }
            let extras = compatibleBooks
                .filter { coverRole(from: $0.title) != .normal }
                .filter { $0.volumeNumber != nil }
            return normalBooks + extras
        }
        let exactSeriesBooks = books.filter { book in
            providerTitle(book.title, belongsTo: match.title)
                || book.seriesID == match.providerID
        }
        let sameWorkFamily = exactSeriesBooks.filter {
            manualSeriesBookTitleIsCompatible(
                $0.title,
                with: match.title
            )
        }
        return sameWorkFamily
    }

    static func preferredAutomaticBookLiveSeriesGroupBooks(
        currentBooks: [SableLibraryBigBookCoversBookCandidate],
        groupBooks: [SableLibraryBigBookCoversBookCandidate],
        groupMatch: SableLibraryManualCoverSeriesMatch
    ) -> [SableLibraryBigBookCoversBookCandidate]? {
        let compatibleGroupBooks = booksFromExactManualSeries(
            groupBooks,
            match: groupMatch,
            source: .bookLiveJP
        )
        guard !compatibleGroupBooks.isEmpty,
              compatibleGroupBooks.count >= currentBooks.count else {
            return nil
        }
        return compatibleGroupBooks
    }

    static func manualSeriesBookTitleIsCompatible(
        _ providerTitle: String,
        with manualSeriesTitle: String
    ) -> Bool {
        let provider = providerTitle.lowercased()
        let series = manualSeriesTitle.lowercased()
        let relatedWorkMarkers = [
            "スピンオフ", "spin-off", "spin off", "spinoff",
            "よりみち", "番外編集", "番外編", "外伝",
            "短篇集", "短編集", "side story", "side stories",
            "short story", "short stories"
        ]
        return !relatedWorkMarkers.contains {
            provider.contains($0) && !series.contains($0)
        }
    }

    static func authoritativeManualSeriesMatches(
        for language: String,
        in request: SableLibraryCoverDownloadRequest
    ) -> [SableLibraryManualCoverSeriesMatch] {
        let allowedSources = Set(
            SableLibraryCoverSourcePolicy.normalCoverDownloadOrder(language: language)
        )
        return request.manualSeriesMatches.filter {
            allowedSources.contains($0.source)
        }
    }

    static func normalCoverDownloadOrder(
        for language: String,
        in request: SableLibraryCoverDownloadRequest
    ) -> [SableLibraryCoverSource] {
        let defaultOrder: [SableLibraryCoverSource]
        switch request.downloadPass {
        case .combined:
            defaultOrder = SableLibraryCoverSourcePolicy.normalCoverDownloadOrder(
                language: language
            )
        case .mangaBakaBaseline:
            defaultOrder = [SableLibraryCoverSourcePolicy.identityBaselineSource]
        case .storeQualityUpgrade:
            defaultOrder = SableLibraryCoverSourcePolicy.storeQualityUpgradeOrder(
                language: language
            )
        }
        let exactSources = Set(
            authoritativeManualSeriesMatches(for: language, in: request).map(\.source)
        ).intersection(defaultOrder)
        guard !exactSources.isEmpty else {
            return defaultOrder
        }
        var allowedSources = exactSources
        if request.downloadPass == .combined,
           request.manualSeriesMatch(for: .mangaBaka) != nil
            || request.mangaBakaSeriesID != nil {
            allowedSources.insert(.mangaBaka)
        }
        return defaultOrder.filter(allowedSources.contains)
    }

    static func shouldRunAutomaticProviderSearch(
        source: SableLibraryCoverSource,
        provider: SableLibraryBigBookCoversProvider,
        request: SableLibraryCoverDownloadRequest
    ) -> Bool {
        request.manualSeriesMatch(for: source)?.provider != provider
    }

    static func manifestCover(
        _ cover: SableLibraryDownloadedCoverManifestCover,
        belongsToAny matches: [SableLibraryManualCoverSeriesMatch]
    ) -> Bool {
        matches.contains { match in
            guard cover.source == match.source.displayName else {
                return false
            }
            if cover.providerSeriesID == match.providerID {
                if match.itemType.caseInsensitiveCompare("seriesGroup") != .orderedSame,
                   let providerTitle = cover.providerTitle {
                    return manualSeriesBookTitleIsCompatible(
                        providerTitle,
                        with: match.title
                    )
                }
                return true
            }
            return match.itemType.caseInsensitiveCompare("book") == .orderedSame
                && cover.providerItemID == match.providerID
        }
    }

    static func matchedProviderCovers(
        candidates: [SableLibraryProviderCoverCandidate],
        source: SableLibraryCoverSource,
        language: String,
        localBooks: [SableLibraryCoverDownloadLocalBook],
        includeSpecials: Bool
    ) -> [Int: [SableLibraryProviderCoverCandidate]] {
        let requestedLanguage = normalizedLanguage(language)
        let languageCandidates = candidates.filter { candidate in
            guard let candidateLanguage = candidate.language else {
                return source != .mangaBaka
            }
            return normalizedLanguage(candidateLanguage) == requestedLanguage
        }
        let sortedBooks = localBooks.enumerated().map { index, book in
            (index: index + 1, book: book)
        }
        let normalCandidates = languageCandidates.filter { $0.role == .normal }
        let extraCandidates = includeSpecials ? languageCandidates.filter { $0.role != .normal } : []
        var result: [Int: [SableLibraryProviderCoverCandidate]] = [:]
        var assignedCandidateImages = Set<String>()

        for local in sortedBooks {
            let volume = local.book.volumeNumber
            let normal = bestCoverCandidate(
                from: normalCandidates,
                source: source,
                localVolume: volume,
                localBookTitle: local.book.fileName,
                sequenceIndex: local.index
            )
            if let normal,
               assignedCandidateImages.insert(candidateImageIdentity(normal)).inserted {
                result[local.index, default: []].append(normal)
            }

            let extras = extraCandidates.filter { candidate in
                coverMatchesLocalBook(
                    candidate,
                    source: source,
                    localVolume: volume,
                    localBookTitle: local.book.fileName,
                    sequenceIndex: local.index
                )
                    && assignedCandidateImages.insert(candidateImageIdentity(candidate)).inserted
            }
            result[local.index, default: []].append(contentsOf: extras)
        }

        return result.mapValues { candidates in
            var seen = Set<String>()
            return candidates.filter { candidate in
                seen.insert("\(candidate.role.rawValue)|\(candidate.imageURL)").inserted
            }
        }
        .filter { !$0.value.isEmpty }
    }

    private static func candidateImageIdentity(
        _ candidate: SableLibraryProviderCoverCandidate
    ) -> String {
        candidate.providerItemID ?? candidate.imageURL
    }

    static func covers(
        _ coversByBookIndex: [Int: [SableLibraryProviderCoverCandidate]],
        forBookIndexes bookIndexes: Set<Int>
    ) -> [Int: [SableLibraryProviderCoverCandidate]] {
        coversByBookIndex.filter { bookIndexes.contains($0.key) }
    }

    static func missingRequiredCoverLanguages(
        from availableLanguages: [String],
        requiredLanguages: [String] = ["jp", "en"]
    ) -> [String] {
        let available = Set(availableLanguages.map(normalizedLanguage))
        return requiredLanguages
            .map(normalizedLanguage)
            .filter { !available.contains($0) }
    }

    static func localVolumeNumber(
        fileName: String,
        seriesTitles: [String]
    ) -> Double? {
        let stem = (fileName as NSString).deletingPathExtension
        let explicitPatterns = [
            #"(?i)\bvol(?:ume)?\.?\s*(\d+(?:\.\d+)?)"#,
            #"(?i)\bv\s*(\d+(?:\.\d+)?)"#,
            #"(?i)\bbook\s*(\d+(?:\.\d+)?)"#,
            #"(?i)\bpart\s*(\d+(?:\.\d+)?)"#,
            #"第\s*(\d+(?:\.\d+)?)\s*[巻卷]"#,
            #"(\d+(?:\.\d+)?)\s*[巻卷]"#
        ]
        for pattern in explicitPatterns {
            if let value = firstNumberMatch(in: stem, pattern: pattern) {
                return value
            }
        }

        var remainder = stem
        for title in uniqueNonEmpty(seriesTitles).sorted(by: { $0.count > $1.count }) {
            let escapedTitle = NSRegularExpression.escapedPattern(for: title)
            guard let regex = try? NSRegularExpression(
                pattern: escapedTitle,
                options: [.caseInsensitive]
            ) else { continue }
            let range = NSRange(remainder.startIndex..<remainder.endIndex, in: remainder)
            remainder = regex.stringByReplacingMatches(
                in: remainder,
                range: range,
                withTemplate: " "
            )
        }

        // Publication years and numeric titles are not volume evidence.
        if let yearRegex = try? NSRegularExpression(
            pattern: #"(?:\(|\[)\s*(?:18|19|20)\d{2}\s*(?:\)|\])"#
        ) {
            let range = NSRange(remainder.startIndex..<remainder.endIndex, in: remainder)
            remainder = yearRegex.stringByReplacingMatches(
                in: remainder,
                range: range,
                withTemplate: " "
            )
        }

        return firstNumberMatch(
            in: remainder,
            pattern: #"(?:^|[\s_-])(\d{1,3}(?:\.\d+)?)(?=$|[\s_-])"#
        )
    }

    static func explicitVolumeNumber(in text: String) -> Double? {
        let patterns = [
            #"(?i)\bvol(?:ume)?\.?\s*(\d+(?:\.\d+)?)"#,
            #"(?i)\bbook\.?\s*(\d+(?:\.\d+)?)"#,
            #"(?i)\bv\s*(\d+(?:\.\d+)?)"#,
            #"第\s*(\d+(?:\.\d+)?)\s*[巻卷]"#,
            #"(\d+(?:\.\d+)?)\s*[巻卷]"#,
            #"[編篇]\s*(\d+(?:\.\d+)?)"#
        ]
        for pattern in patterns {
            if let value = firstNumberMatch(in: text, pattern: pattern) {
                return value
            }
        }
        return nil
    }

    static func explicitVolumeNumber(
        in text: String,
        afterSeriesTitle seriesTitle: String
    ) -> Double? {
        if let explicit = explicitVolumeNumber(in: text) {
            return explicit
        }

        guard let seriesRange = text.range(
            of: seriesTitle,
            options: [
                .caseInsensitive,
                .diacriticInsensitive,
                .widthInsensitive
            ]
        ) else {
            return nil
        }

        var remainder = text
        remainder.removeSubrange(seriesRange)
        if let value = firstNumberMatch(
            in: remainder,
            pattern:
                #"^\s*[・:：\-–—_【\[（(]?\s*(\d{1,3}(?:\.\d+)?)(?=$|[\s　・:：\-–—_】\]）)])"#
        ) {
            return value
        }
        let formalNumerals =
            "〇零一二三四五六七八九十百千壱壹弐貳参參肆伍陸漆捌玖拾"
        let patterns = [
            "第\\s*([\(formalNumerals)]+)\\s*[巻卷]",
            "^\\s*[・:：\\-–—_【\\[（(]?\\s*([\(formalNumerals)]{1,6})"
                + "(?=$|[\\s　・:：\\-–—_】\\]）)])"
        ]
        for pattern in patterns {
            guard let token = firstCapturedText(
                in: remainder,
                pattern: pattern
            ),
            let value = japaneseVolumeNumber(from: token) else {
                continue
            }
            return Double(value)
        }
        return nil
    }

    private static func japaneseVolumeNumber(from text: String) -> Int? {
        let normalized = text
            .replacingOccurrences(of: "〇", with: "零")
            .replacingOccurrences(of: "壱", with: "一")
            .replacingOccurrences(of: "壹", with: "一")
            .replacingOccurrences(of: "弐", with: "二")
            .replacingOccurrences(of: "貳", with: "二")
            .replacingOccurrences(of: "参", with: "三")
            .replacingOccurrences(of: "參", with: "三")
            .replacingOccurrences(of: "肆", with: "四")
            .replacingOccurrences(of: "伍", with: "五")
            .replacingOccurrences(of: "陸", with: "六")
            .replacingOccurrences(of: "漆", with: "七")
            .replacingOccurrences(of: "捌", with: "八")
            .replacingOccurrences(of: "玖", with: "九")
            .replacingOccurrences(of: "拾", with: "十")

        let digits: [Character: Int] = [
            "零": 0,
            "一": 1,
            "二": 2,
            "三": 3,
            "四": 4,
            "五": 5,
            "六": 6,
            "七": 7,
            "八": 8,
            "九": 9
        ]
        let units: [Character: Int] = [
            "十": 10,
            "百": 100,
            "千": 1_000
        ]

        var total = 0
        var pendingDigit: Int?
        var sawNumber = false
        for character in normalized {
            if let digit = digits[character] {
                pendingDigit = digit
                sawNumber = true
                continue
            }
            guard let unit = units[character] else {
                return nil
            }
            total += (pendingDigit ?? 1) * unit
            pendingDigit = nil
            sawNumber = true
        }
        total += pendingDigit ?? 0
        return sawNumber && total > 0 ? total : nil
    }

    private static func explicitEditionVolumeNumber(in text: String) -> Double? {
        explicitVolumeNumber(in: text)
            ?? firstNumberMatch(
                in: text,
                pattern: #"(?:^|[^\d])(\d{1,3}(?:\.\d+)?)(?=\s*(?:[【(\[]|$))"#
            )
    }

    private static func firstNumberMatch(in text: String, pattern: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let searchableText = text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text
        let range = NSRange(searchableText.startIndex..<searchableText.endIndex, in: searchableText)
        guard let match = regex.firstMatch(in: searchableText, range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: searchableText) else {
            return nil
        }
        return Double(searchableText[valueRange])
    }

    static func manifestEntries(
        request: SableLibraryCoverDownloadRequest,
        coversByBookIndex: [Int: [SableLibraryDownloadedCoverManifestCover]]
    ) -> [SableLibraryDownloadedCoverManifestEntry] {
        request.localBooks.enumerated().compactMap { index, book in
            let covers = coversByBookIndex[index + 1] ?? []
            guard !covers.isEmpty else { return nil }
            return SableLibraryDownloadedCoverManifestEntry(
                bookFile: book.fileName,
                volume: book.volumeNumber,
                covers: covers
            )
        }
    }

    static func coverRole(from title: String) -> SableLibraryProviderCoverRole {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let digitalEditionMarkerOnly = containsAny(normalized, [
            "電子特別版",
            "電子版限定特典付き",
            "電子限定特典付き",
            "電子特典付き",
            "digital edition bonus included",
            "digital bonus included"
        ])
        if !digitalEditionMarkerOnly,
           containsAny(normalized, [
            "special edition",
            "limited edition",
            "collector's edition",
            "collectors edition",
            "特別版",
            "特装版",
            "限定版",
            "小冊子付き特別仕立て",
            "小冊子付き"
           ]) {
            return .specialEdition
        }
        if containsAny(normalized, ["alternative", "alternate", "variant", "new edition", "改訂", "新装"]) {
            return .alternativeEdition
        }
        if containsAny(normalized, [
            "bonus", "booklet", "obi", "帯付き",
            "購入特典", "書き下ろしショートストーリー", "特典小冊子"
        ]) {
            return .bonus
        }
        return .normal
    }

    static func preferredProviderBookTypeForDownload(mediaType: String?) -> String? {
        preferredProviderBookType(mediaType: mediaType)
    }

    static func providerMediaTypeIsCompatible(
        _ providerMediaType: String?,
        isCompatibleWith requestedMediaType: String?
    ) -> Bool {
        guard let requested = preferredProviderBookType(mediaType: requestedMediaType) else {
            return true
        }
        guard let provider = preferredProviderBookType(mediaType: providerMediaType) else {
            return false
        }
        return provider == requested
    }

    static func mangaBakaSeriesIdentityIsCompatible(
        titles: [String],
        providerMediaType: String?,
        requestedSeriesTitle: String,
        requestedMediaType: String?
    ) -> Bool {
        guard providerMediaTypeIsCompatible(
            providerMediaType,
            isCompatibleWith: requestedMediaType
        ) else {
            return false
        }
        return uniqueNonEmpty(titles).contains {
            providerTitle($0, belongsTo: requestedSeriesTitle)
        }
    }

    static func coverDimensionsAreUsable(width: Int, height: Int) -> Bool {
        width >= 800
            && height >= 1_100
            && width * height >= 850_000
            && coverDimensionsHaveBookShape(width: width, height: height)
    }

    static func coverDimensionsAreArchiveUsable(width: Int, height: Int) -> Bool {
        width >= 500 && height >= 700 && width * height >= 350_000
    }

    static func coverDimensionsAreStrictQualityUpgrade(
        width: Int,
        height: Int,
        over baselineWidth: Int,
        baselineHeight: Int
    ) -> Bool {
        guard coverDimensionsAreArchiveUsable(width: width, height: height),
              coverDimensionsHaveBookShape(width: width, height: height) else {
            return false
        }
        let reachesClinicQuality = coverDimensionsAreUsable(width: width, height: height)
        let baselineReachesClinicQuality = coverDimensionsAreUsable(
            width: baselineWidth,
            height: baselineHeight
        )
        if reachesClinicQuality != baselineReachesClinicQuality {
            return reachesClinicQuality
        }
        return width * height > baselineWidth * baselineHeight
    }

    static func coverDimensionsHaveBookShape(width: Int, height: Int) -> Bool {
        guard width > 0 else { return false }
        return Double(height) / Double(width) >= 1.18
    }

    static func normalizedLanguage(_ language: String) -> String {
        let normalized = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.hasPrefix("ja") || normalized.hasPrefix("jp") { return "jp" }
        if normalized.hasPrefix("en") { return "en" }
        return normalized
    }

    static func providerTitleLanguageIsCompatible(
        _ title: String,
        language: String,
        source: SableLibraryCoverSource
    ) -> Bool {
        let requestedLanguage = normalizedLanguage(language)
        let normalizedTitle = title.lowercased()

        switch requestedLanguage {
        case "jp":
            if containsAny(normalizedTitle, [
                "english edition",
                "english language edition",
                "英語版",
                "英語 edition"
            ]) {
                return false
            }
            if source == .bookLiveJP || source == .bookWalkerJP || source == .amazonJP {
                return containsCJK(title)
            }
        case "en":
            if containsAny(normalizedTitle, [
                "japanese edition",
                "japanese language edition",
                "日本語版",
                "日本語 edition"
            ]) {
                return false
            }
            if source == .bookWalkerGlobal || source == .amazon {
                return containsLatinLetter(title)
            }
        default:
            break
        }
        return true
    }

    struct StorefrontURLIdentity: Sendable, Equatable {
        var providerItemID: String?
        var providerSeriesID: String?
        var providerVolume: Double?
    }

    static func storefrontIdentity(
        from rawURL: String,
        source: SableLibraryCoverSource
    ) -> StorefrontURLIdentity {
        let decodedURL = rawURL.removingPercentEncoding ?? rawURL

        switch source {
        case .bookLiveJP:
            let titleID = firstCapturedText(
                in: decodedURL,
                pattern: #"(?i)(?:/|[?&])title_id(?:/|=)(\d+)"#
            )
            let volumeText = firstCapturedText(
                in: decodedURL,
                pattern: #"(?i)(?:/|[?&])vol_no(?:/|=)(\d+(?:\.\d+)?)"#
            )
            let itemID: String? = {
                guard let titleID else { return nil }
                return volumeText.map { "\(titleID)-\($0)" } ?? titleID
            }()
            return StorefrontURLIdentity(
                providerItemID: itemID,
                providerSeriesID: titleID,
                providerVolume: volumeText.flatMap(Double.init)
            )

        case .bookWalkerGlobal:
            return StorefrontURLIdentity(
                providerItemID: firstCapturedText(
                    in: decodedURL,
                    pattern: #"(?i)/volume/([^/?#]+)"#
                ),
                providerSeriesID: nil,
                providerVolume: nil
            )

        case .bookWalkerJP:
            let rawID = firstCapturedText(
                in: decodedURL,
                pattern: #"(?i)bookwalker\.jp/de([0-9a-f-]{20,})"#
            )
            return StorefrontURLIdentity(
                providerItemID: rawID,
                providerSeriesID: nil,
                providerVolume: nil
            )

        case .amazon, .amazonJP:
            return StorefrontURLIdentity(
                providerItemID: firstCapturedText(
                    in: decodedURL,
                    pattern: #"(?i)/(?:dp|gp/product|gp/aw/d)/([a-z0-9]{10})(?:[/?#]|$)"#
                )?.uppercased(),
                providerSeriesID: nil,
                providerVolume: nil
            )

        case .mangaBaka, .ranobeDB, .unknown:
            return StorefrontURLIdentity(
                providerItemID: nil,
                providerSeriesID: nil,
                providerVolume: nil
            )
        }
    }

    static func providerPageTitle(
        from html: String,
        source: SableLibraryCoverSource
    ) -> String? {
        let patterns = [
            #"(?is)<meta[^>]+(?:property|name)\s*=\s*["'](?:og:title|twitter:title)["'][^>]+content\s*=\s*["']([^"']+)["']"#,
            #"(?is)<meta[^>]+content\s*=\s*["']([^"']+)["'][^>]+(?:property|name)\s*=\s*["'](?:og:title|twitter:title)["']"#,
            #"(?is)<title[^>]*>(.*?)</title>"#
        ]
        guard let rawTitle = patterns.lazy.compactMap({
            firstCapturedText(in: html, pattern: $0)
        }).first else {
            return nil
        }

        var title = decodedProviderHTMLText(rawTitle)
        let suffixes: [String]
        switch source {
        case .bookLiveJP:
            suffixes = [
                " - 漫画・ラノベ（小説）・無料試し読みなら、電子書籍・コミックストア ブックライブ",
                "【無料試し読みあり】"
            ]
        case .bookWalkerJP:
            suffixes = [" | 電子書籍 BOOK☆WALKER", " - BOOK☆WALKER"]
        case .bookWalkerGlobal:
            suffixes = [" | BOOK☆WALKER Global Store", " - BOOK☆WALKER Global Store"]
        case .amazon, .amazonJP:
            suffixes = [" : Books", ": Books"]
        case .mangaBaka, .ranobeDB, .unknown:
            suffixes = []
        }
        for suffix in suffixes where title.hasSuffix(suffix) {
            title.removeLast(suffix.count)
            title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return title.isEmpty ? nil : title
    }

    private static func decodedProviderHTMLText(_ value: String) -> String {
        var result = value
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")

        guard let numericEntityRegex = try? NSRegularExpression(
            pattern: #"&#(?:x([0-9a-fA-F]+)|([0-9]+));"#
        ) else {
            return result
        }
        while true {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            guard let match = numericEntityRegex.firstMatch(in: result, range: range),
                  let wholeRange = Range(match.range(at: 0), in: result) else {
                break
            }
            let scalarValue: UInt32?
            if match.range(at: 1).location != NSNotFound,
               let hexRange = Range(match.range(at: 1), in: result) {
                scalarValue = UInt32(result[hexRange], radix: 16)
            } else if match.range(at: 2).location != NSNotFound,
                      let decimalRange = Range(match.range(at: 2), in: result) {
                scalarValue = UInt32(result[decimalRange], radix: 10)
            } else {
                scalarValue = nil
            }
            let replacement = scalarValue
                .flatMap(UnicodeScalar.init)
                .map(String.init)
                ?? ""
            result.replaceSubrange(wholeRange, with: replacement)
        }
        return result
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func providerMediaSignalHTML(from html: String) -> String {
        let fullScanLimit = 768 * 1024
        let page = Data(html.utf8)
        guard page.count > fullScanLimit else {
            return html
        }

        let prefixLength = min(128 * 1024, page.count)
        var fragments = [
            String(decoding: page[..<prefixLength], as: UTF8.self)
        ]
        let anchors = [
            "name=\"keywords\"",
            "name='keywords'",
            "twitter:data2",
            "\"BreadcrumbList\"",
            "ref=dp_bc_",
            "/gp/bestsellers/books/",
            "Best Sellers Rank",
            "Product details",
            "カテゴリ",
            "ジャンル",
            "掲載誌・レーベル",
            "audible",
            "Audible"
        ]

        for anchor in anchors {
            let needle = Data(anchor.utf8)
            var searchStart = 0
            var matches = 0
            while matches < 2, searchStart < page.count,
                  let range = page.range(of: needle, in: searchStart..<page.count) {
                let lower = max(0, range.lowerBound - 16 * 1024)
                let upper = min(page.count, range.upperBound + 16 * 1024)
                fragments.append(
                    String(decoding: page[lower..<upper], as: UTF8.self)
                )
                searchStart = range.upperBound
                matches += 1
            }
        }
        return fragments.joined(separator: "\n")
    }

    static func providerPageMediaType(from html: String) -> String? {
        let signalHTML = providerMediaSignalHTML(from: html)
        var normalizedPageTitle = ""
        if let title = firstCapturedText(
            in: signalHTML,
            pattern: #"(?is)<title[^>]*>(.*?)</title>"#
        ) {
            normalizedPageTitle = title
                .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
                .replacingOccurrences(of: "&amp;", with: "&")
                .lowercased()
            if containsAny(normalizedPageTitle, [
                "audible audio edition",
                "audible audiobook",
                "audiobook"
            ]) {
                return "audiobook"
            }
        }

        let patterns = [
            #"(?is)<meta[^>]+name\s*=\s*[\"'](?:keywords|twitter:data2)[\"'][^>]+content\s*=\s*[\"']([^\"']+)[\"']"#,
            #"(?is)<meta[^>]+content\s*=\s*[\"']([^\"']+)[\"'][^>]+name\s*=\s*[\"'](?:keywords|twitter:data2)[\"']"#
        ]
        var productSignals = normalizedPageTitle.isEmpty ? [] : [normalizedPageTitle]
        var metadataSignals: [String] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(signalHTML.startIndex..<signalHTML.endIndex, in: signalHTML)
            for match in regex.matches(in: signalHTML, range: range) where match.numberOfRanges > 1 {
                guard let valueRange = Range(match.range(at: 1), in: signalHTML) else { continue }
                let value = String(signalHTML[valueRange])
                metadataSignals.append(value)
                productSignals.append(value)
            }
        }

        // BookLive puts the actual product category in metadata near the top of
        // the page. Prefer those explicit labels before reading site-wide manga
        // and novel navigation, which otherwise makes a clear result ambiguous.
        let metadataText = metadataSignals
            .joined(separator: " ")
            .lowercased()
            .folding(options: .widthInsensitive, locale: .current)
        if containsAny(metadataText, [
            "audiobook", "audio book", "audible", "オーディオブック", "オーディオ"
        ]) {
            return "audiobook"
        }
        let metadataLooksNovel = containsAny(metadataText, [
            "ライトノベル", "女性向けライトノベル", "ラノベ",
            "bl小説", "tl小説", "小説", "ノベル",
            "小説・文芸", "文芸・小説", "新文芸",
            "light novel",
            "gaノベル", "ga novel", "ga文庫", "ga bunko",
            "ことのは文庫", "kotonoha bunko", "kotoha bunko"
        ])
        let metadataLooksManga = containsAny(metadataText, [
            "少年マンガ", "青年マンガ", "少女マンガ", "女性マンガ",
            "blマンガ", "tlマンガ", "マンガ", "漫画", "コミック", "manga", "comic"
        ])
        if metadataLooksNovel != metadataLooksManga {
            return metadataLooksNovel ? "novel" : "manga"
        }

        // BookWalker Global puts the main format in the second JSON-LD breadcrumb.
        let bookWalkerBreadcrumbPattern =
            #"(?is)\"@type\"\s*:\s*\"BreadcrumbList\".{0,2400}?\"position\"\s*:\s*2\s*,\s*\"name\"\s*:\s*\"([^\"]+)\""#
        if let regex = try? NSRegularExpression(pattern: bookWalkerBreadcrumbPattern) {
            let range = NSRange(signalHTML.startIndex..<signalHTML.endIndex, in: signalHTML)
            for match in regex.matches(in: signalHTML, range: range) where match.numberOfRanges > 1 {
                guard let valueRange = Range(match.range(at: 1), in: signalHTML) else { continue }
                productSignals.append(String(signalHTML[valueRange]))
            }
        }

        // Amazon's global navigation mentions manga on every page. Only its product
        // breadcrumb (dp_bc_*) describes the actual book, so ignore the rest.
        let amazonBreadcrumbPattern =
            #"(?is)<a[^>]+href\s*=\s*[\"'][^\"']*ref=dp_bc_[^\"']*[\"'][^>]*>(.*?)</a>"#
        if let regex = try? NSRegularExpression(pattern: amazonBreadcrumbPattern) {
            let range = NSRange(signalHTML.startIndex..<signalHTML.endIndex, in: signalHTML)
            for match in regex.matches(in: signalHTML, range: range) where match.numberOfRanges > 1 {
                guard let valueRange = Range(match.range(at: 1), in: signalHTML) else { continue }
                let value = String(signalHTML[valueRange])
                    .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
                    .replacingOccurrences(of: "&amp;", with: "&")
                productSignals.append(value)
            }
        }

        // Some Amazon layouts omit dp_bc_* breadcrumbs but still show the
        // product's ranked book categories. Those category links are product
        // evidence, unlike Amazon's global navigation.
        let amazonRankCategoryPattern =
            #"(?is)<a[^>]+href\s*=\s*[\"'][^\"']*(?:/gp/bestsellers/books/|ref=pd_zg|ref=zg_bs_)[^\"']*[\"'][^>]*>(.*?)</a>"#
        if let regex = try? NSRegularExpression(pattern: amazonRankCategoryPattern) {
            let range = NSRange(signalHTML.startIndex..<signalHTML.endIndex, in: signalHTML)
            for match in regex.matches(in: signalHTML, range: range) where match.numberOfRanges > 1 {
                guard let valueRange = Range(match.range(at: 1), in: signalHTML) else { continue }
                let value = String(signalHTML[valueRange])
                    .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
                    .replacingOccurrences(of: "&amp;", with: "&")
                productSignals.append(value)
            }
        }

        // Barnes & Noble product pages expose the useful book format in category
        // links instead of Amazon-style ranked breadcrumbs.
        let barnesNobleCategoryPattern =
            #"(?is)<a[^>]+href\s*=\s*[\"'][^\"']*(?:/b/|/browse/)[^\"']*[\"'][^>]*>(.*?)</a>"#
        if let regex = try? NSRegularExpression(pattern: barnesNobleCategoryPattern) {
            let range = NSRange(signalHTML.startIndex..<signalHTML.endIndex, in: signalHTML)
            for match in regex.matches(in: signalHTML, range: range) where match.numberOfRanges > 1 {
                guard let valueRange = Range(match.range(at: 1), in: signalHTML) else { continue }
                let value = String(signalHTML[valueRange])
                    .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
                    .replacingOccurrences(of: "&amp;", with: "&")
                productSignals.append(value)
            }
        }

        // BookLive exposes the definitive manga/light-novel category in its
        // product-detail rows. Keep only a small window around those labels so
        // unrelated navigation and recommendation copy cannot sway the result.
        let signalPage = signalHTML as NSString
        for marker in ["カテゴリ", "ジャンル", "掲載誌・レーベル"] {
            let markerRange = signalPage.range(of: marker)
            guard markerRange.location != NSNotFound else { continue }
            let upper = min(signalPage.length, NSMaxRange(markerRange) + 4 * 1024)
            productSignals.append(
                signalPage.substring(
                    with: NSRange(
                        location: markerRange.location,
                        length: upper - markerRange.location
                    )
                )
            )
        }

        let text = productSignals.joined(separator: " ").lowercased()
        guard !text.isEmpty else { return nil }

        let novelMarkers = [
            "ライトノベル", "女性向けライトノベル", "ラノベ", "新文芸",
            "bl小説", "tl小説", "小説・文芸", "文芸・小説", "書籍",
            "hj novels", "light novel",
            "ことのは文庫", "kotonoha bunko", "kotoha bunko",
            "novels", "literature & fiction", "teen & young adult",
            "라이트노벨", "라이트 노벨", "장르소설", "웹소설"
        ]
        let mangaMarkers = [
            "少年マンガ", "青年マンガ", "少女マンガ", "女性マンガ",
            "blマンガ", "tlマンガ", "マンガ", "漫画", "コミック", "manga", "comic",
            "만화", "웹툰", "코믹", "그래픽노블", "그래픽 노블"
        ]
        let audiobookMarkers = [
            "audiobook", "audio book", "audible", "オーディオブック", "オーディオ",
            "오디오북", "오디오 북"
        ]
        let novelText = text
            .replacingOccurrences(of: "graphic novels", with: "")
            .replacingOccurrences(of: "電子書籍", with: "")
        if containsAny(text, audiobookMarkers) {
            return "audiobook"
        }
        let looksNovel = containsAny(novelText, novelMarkers)
        let looksManga = containsAny(text, mangaMarkers)
        if looksNovel != looksManga {
            return looksNovel ? "novel" : "manga"
        }
        if !looksManga,
           containsAny(text, ["kindle store", "kindle ebooks", "kindle edition"]) {
            return "novel"
        }
        return nil
    }

    static func effectiveProviderMediaType(
        declaredSeriesType: String?,
        storefrontMediaType: String?,
        bookTypes: [String?]
    ) -> String? {
        storefrontMediaType
            ?? declaredSeriesType
            ?? bookTypes.compactMap { $0 }.first
    }

    static func manualSeriesHasEmbeddedStorefrontTypeProof(
        _ match: SableLibraryManualCoverSeriesMatch
    ) -> Bool {
        match.source == .bookLiveJP
            && match.itemType.caseInsensitiveCompare("seriesGroup") == .orderedSame
    }

    private static func bestCoverCandidate(
        from candidates: [SableLibraryProviderCoverCandidate],
        source: SableLibraryCoverSource,
        localVolume: Double?,
        localBookTitle: String,
        sequenceIndex: Int
    ) -> SableLibraryProviderCoverCandidate? {
        candidates
            .filter {
                coverMatchesLocalBook(
                    $0,
                    source: source,
                    localVolume: localVolume,
                    localBookTitle: localBookTitle,
                    sequenceIndex: sequenceIndex
                )
            }
            .max { lhs, rhs in
                coverCandidateScore(lhs, source: source) < coverCandidateScore(rhs, source: source)
            }
    }

    private static func coverMatchesLocalBook(
        _ candidate: SableLibraryProviderCoverCandidate,
        source: SableLibraryCoverSource,
        localVolume: Double?,
        localBookTitle: String,
        sequenceIndex: Int
    ) -> Bool {
        let editionVolume = candidate.editionNote.flatMap(explicitEditionVolumeNumber(in:))
        guard providerBookIdentityIsCompatible(
            providerTitle: candidate.title,
            localBookTitle: localBookTitle,
            localVolume: localVolume
        ) else {
            return false
        }
        if let editionVolume {
            guard let localVolume,
                  volumeNumbersMatch(editionVolume, localVolume) else {
                return false
            }
        }

        if let candidateVolume = candidate.volumeNumber {
            if let localVolume {
                return providerVolume(
                    candidateVolume,
                    providerTitle: candidate.title ?? candidate.editionNote,
                    localTitle: localBookTitle,
                    source: source,
                    matches: localVolume
                )
            }
            return volumeNumbersMatch(candidateVolume, Double(sequenceIndex))
        }

        guard let indexText = candidate.volumeIndex,
              let index = Double(indexText) else {
            if editionVolume != nil
                || (localVolume != nil
                    && candidate.title.flatMap(explicitVolumeNumber(in:)) != nil) {
                return true
            }
            return localVolume == nil && sequenceIndex == 1
        }
        if let localVolume {
            return volumeNumbersMatch(index, localVolume)
        }
        return volumeNumbersMatch(index, Double(sequenceIndex))
    }

    static func providerVolume(
        _ providerVolume: Double,
        providerTitle: String? = nil,
        localTitle: String? = nil,
        source: SableLibraryCoverSource? = nil,
        matches localVolume: Double
    ) -> Bool {
        guard providerBookIdentityIsCompatible(
            providerTitle: providerTitle,
            localBookTitle: localTitle,
            localVolume: localVolume
        ) else {
            return false
        }
        if volumeNumbersMatch(providerVolume, localVolume) {
            return true
        }

        guard abs(providerVolume - localVolume - 0.1) < 0.001 else {
            return false
        }

        // MangaBaka represents some translated editions as x.1 beside the
        // original-language x entry. Other sources need the visible title to
        // confirm that x.1 is only a storefront sort key.
        if source == .mangaBaka {
            return true
        }
        guard let titleVolume = providerTitle.flatMap(explicitVolumeNumber(in:)) else {
            return false
        }
        return volumeNumbersMatch(titleVolume, localVolume)
    }

    static func providerBookIdentityIsCompatible(
        providerTitle: String?,
        localBookTitle: String?,
        localVolume: Double?
    ) -> Bool {
        if let providerTitle,
           let localBookTitle {
            let provider = providerTitle.lowercased()
            let local = localBookTitle.lowercased()
            let providerIsRelatedWork = containsAny(provider, [
                "番外編集", "番外編", "外伝", "短篇集", "短編集"
            ])
            let localIsRelatedWork = containsAny(local, [
                "side story", "side stories", "gaiden",
                "short story", "short stories",
                "番外編集", "番外編", "外伝", "短篇集", "短編集"
            ])
            if providerIsRelatedWork && !localIsRelatedWork {
                return false
            }
            let providerIsSupplement = containsAny(provider, [
                "設定資料集", "公式設定", "画集", "イラスト集",
                "ファンブック", "公式ガイド", "ガイドブック",
                "art book", "artbook", "fan book", "fanbook",
                "official guide", "setting materials"
            ])
            let localIsSupplement = containsAny(local, [
                "settings book", "setting materials", "art book", "artbook",
                "fan book", "fanbook", "official guide", "guidebook",
                "設定資料集", "公式設定", "画集", "イラスト集",
                "ファンブック", "公式ガイド", "ガイドブック"
            ])
            if providerIsSupplement && !localIsSupplement {
                return false
            }
        }
        if let providerTitle,
           let localBookTitle,
           let localPart = partScopeNumber(in: localBookTitle),
           let providerPart = partScopeNumber(in: providerTitle),
           localPart != providerPart {
            return false
        }
        if let providerTitle,
           let localBookTitle,
           let localVolume,
           let titleVolume = providerTitleVolumeNumber(
                in: providerTitle,
                localBookTitle: localBookTitle
           ),
           !volumeNumbersMatch(titleVolume, localVolume) {
            return false
        }
        return true
    }

    static func volumeNumbersMatch(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) < 0.001
    }

    private static func coverCandidateScore(_ candidate: SableLibraryProviderCoverCandidate, source: SableLibraryCoverSource) -> Int {
        var score = 0
        switch candidate.quality {
        case .highResolution: score += 300
        case .usable: score += 200
        case .unknown: score += 100
        case .lowResolution: score += 0
        }
        if source == .bookLiveJP {
            score += 30
        }
        if candidate.role == .normal {
            score += 50
        }
        score += (candidate.width ?? 0) * (candidate.height ?? 0) / 100_000
        return score
    }

    private static func preferredProviderBookType(mediaType: String?) -> String? {
        let normalized = mediaType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if normalized.contains("audiobook")
            || normalized.contains("audio book")
            || normalized.contains("audible")
            || normalized.contains("オーディオ")
            || normalized.contains("오디오북")
            || normalized.contains("오디오 북") {
            return "audiobook"
        }
        if normalized.contains("novel")
            || normalized == "book"
            || normalized.contains("小説")
            || normalized.contains("ライトノベル")
            || normalized.contains("ラノベ")
            || normalized.contains("라이트노벨")
            || normalized.contains("라이트 노벨")
            || normalized.contains("장르소설")
            || normalized.contains("웹소설") {
            return "novel"
        }
        if normalized.contains("manga")
            || normalized.contains("manhwa")
            || normalized.contains("manhua")
            || normalized.contains("comic")
            || normalized.contains("만화")
            || normalized.contains("웹툰")
            || normalized.contains("코믹")
            || normalized.contains("그래픽노블")
            || normalized.contains("그래픽 노블") {
            return "manga"
        }
        return nil
    }

    private static func providerTitleMismatchPenalty(
        query: String,
        providerTitle: String,
        preferredBookType: String?
    ) -> Double {
        let query = query.lowercased()
        let providerTitle = providerTitle.lowercased()
        var penalty = 0.0

        if partScopeNumber(in: query) != partScopeNumber(in: providerTitle),
           partScopeNumber(in: query) != nil || partScopeNumber(in: providerTitle) != nil {
            penalty += 0.5
        }

        for terms in editionQualifierGroups {
            let queryHasQualifier = containsAny(query, terms)
            let providerHasQualifier = containsAny(providerTitle, terms)
            if queryHasQualifier != providerHasQualifier {
                penalty += 0.28
            }
        }

        if preferredBookType == "novel" {
            let mangaTerms = [
                "コミック", "漫画", "まんが", "マンガ", "4コマ", "４コマ",
                "manga", "comic", "graphic novel"
            ]
            if mangaTerms.contains(where: { providerTitle.contains($0.lowercased()) && !query.contains($0.lowercased()) }) {
                penalty += 0.35
            }
            let audiobookTerms = [
                "audiobook", "audio book", "audible", "オーディオブック"
            ]
            if audiobookTerms.contains(where: {
                providerTitle.contains($0.lowercased())
                    && !query.contains($0.lowercased())
            }) {
                penalty += 0.75
            }
        }

        if preferredBookType == "manga" {
            let novelTerms = ["小説", "ライトノベル", "ノベル", "light novel"]
            if novelTerms.contains(where: { providerTitle.contains($0.lowercased()) && !query.contains($0.lowercased()) }) {
                penalty += 0.25
            }
        }

        return min(penalty, 0.75)
    }

    private static let editionQualifierGroups = [
        ["fan fiction", "fanfiction", "fan-fiction"],
        ["fanbook", "fan book", "ふぁんぶっく", "ファンブック"],
        ["short stories", "short story", "短編集", "短篇集"],
        ["side stories", "side story", "外伝", "番外編", "番外編集"],
        ["fantastic days", "ファンタスティックデイズ"],
        ["another", "アナザー"],
        ["operation records", "作戦記録"],
        ["after story", "after stories", "アフターストーリー"],
        ["4-koma", "4koma", "4コマ", "４コマ"],
        ["anthology", "アンソロジー"],
        ["omnibus", "合本", "合本版", "総集編"],
        ["magazine", "マガジン"]
    ]

    private static func partScopeNumber(in title: String) -> Int? {
        if let number = firstCapturedText(
            in: title,
            pattern: #"(?i)\b(?:part|arc)\s*([0-9]+)\b"#
        ) {
            return Int(number)
        }
        guard let number = firstCapturedText(
            in: title,
            pattern: #"第\s*([0-9一二三四五六七八九十]+)\s*部"#
        ) else {
            return nil
        }
        if let value = Int(number) { return value }
        let japaneseNumbers = [
            "一": 1, "二": 2, "三": 3, "四": 4, "五": 5,
            "六": 6, "七": 7, "八": 8, "九": 9, "十": 10
        ]
        return japaneseNumbers[number]
    }

    private static func firstCapturedText(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: text,
                range: NSRange(text.startIndex..<text.endIndex, in: text)
              ),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }

    private static func containsLatinLetter(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            (0x41...0x5A).contains(Int(scalar.value))
                || (0x61...0x7A).contains(Int(scalar.value))
        }
    }

    private static func titleScore(_ lhs: String, _ rhs: String) -> Double {
        let left = normalizedTitle(lhs)
        let right = normalizedTitle(rhs)
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        if left == right { return 1 }

        let bothCJK = containsCJK(lhs) && containsCJK(rhs)
        if bothCJK {
            if right.contains(left) || left.contains(right) {
                return 0.88
            }
            let leftWithoutStorePrefix = normalizedCJKTitleForPrefixMatch(lhs)
            let rightWithoutStorePrefix = normalizedCJKTitleForPrefixMatch(rhs)
            var sharedPrefix = ""
            for (leftCharacter, rightCharacter) in zip(
                leftWithoutStorePrefix,
                rightWithoutStorePrefix
            ) {
                guard leftCharacter == rightCharacter else { break }
                sharedPrefix.append(leftCharacter)
            }
            if cjkComparableLength(sharedPrefix) >= 6 {
                return 0.82
            }
        }

        let leftTokens = tokenSet(lhs)
        let rightTokens = tokenSet(rhs)
        guard !leftTokens.isEmpty, !rightTokens.isEmpty else { return 0 }
        let overlap = leftTokens.intersection(rightTokens).count
        let denominator = max(leftTokens.count, rightTokens.count)
        if right.contains(left) || left.contains(right) {
            // A generic one-word result such as "Tower" is not enough evidence for
            // "My Very Own Tower Strategy Guide". Exact ISBN lookups bypass title
            // ranking separately, so this only tightens fuzzy title searches.
            if min(leftTokens.count, rightTokens.count) == 1,
               denominator >= 3 {
                return Double(overlap) / Double(denominator)
            }
            return 0.88
        }
        return Double(overlap) / Double(denominator)
    }

    private static func normalizedCJKTitleForPrefixMatch(_ value: String) -> String {
        value
            .replacingOccurrences(
                of: #"^\s*【[^】]{1,48}】\s*"#,
                with: "",
                options: .regularExpression
            )
            .lowercased()
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .replacingOccurrences(of: #"[\p{P}\p{S}\s]+"#, with: "", options: .regularExpression)
    }

    private static func normalizedTitle(_ value: String) -> String {
        value
            .lowercased()
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .replacingOccurrences(of: #"[\p{P}\p{S}\s]+"#, with: "", options: .regularExpression)
    }

    private static func tokenSet(_ value: String) -> Set<String> {
        let normalized = value
            .lowercased()
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .replacingOccurrences(of: #"[\p{P}\p{S}]+"#, with: " ", options: .regularExpression)
        return Set(normalized.split(separator: " ").map(String.init).filter { $0.count > 1 })
    }

    private static func containsCJK(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            (0x3040...0x30FF).contains(Int(scalar.value))
                || (0x3400...0x9FFF).contains(Int(scalar.value))
                || (0xF900...0xFAFF).contains(Int(scalar.value))
        }
    }

    private static func cjkComparableLength(_ value: String) -> Int {
        value.unicodeScalars.filter { scalar in
            (0x3040...0x30FF).contains(Int(scalar.value))
                || (0x3400...0x9FFF).contains(Int(scalar.value))
                || (0xF900...0xFAFF).contains(Int(scalar.value))
        }.count
    }

    private static func containsAny(_ haystack: String, _ needles: [String]) -> Bool {
        needles.contains { haystack.contains($0) }
    }

    private static func normalizedISBN13(_ value: String) -> String? {
        let cleaned = value
            .uppercased()
            .filter { $0.isNumber || $0 == "X" }

        if cleaned.count == 13,
           cleaned.allSatisfy(\.isNumber),
           cleaned.hasPrefix("978") || cleaned.hasPrefix("979") {
            return cleaned
        }

        guard cleaned.count == 10,
              isValidISBN10(cleaned) else {
            return nil
        }

        let prefix = "978" + cleaned.prefix(9)
        let checkSum = prefix.enumerated().reduce(0) { partialResult, element in
            let digit = Int(String(element.element)) ?? 0
            return partialResult + digit * (element.offset.isMultiple(of: 2) ? 1 : 3)
        }
        let checkDigit = (10 - (checkSum % 10)) % 10
        return prefix + "\(checkDigit)"
    }

    private static func isValidISBN10(_ value: String) -> Bool {
        guard value.count == 10 else { return false }

        let weighted = value.enumerated().reduce(0) { partialResult, element in
            let digit: Int
            if element.element == "X", element.offset == 9 {
                digit = 10
            } else if let number = Int(String(element.element)) {
                digit = number
            } else {
                return partialResult + 1_000
            }
            return partialResult + digit * (10 - element.offset)
        }
        return weighted % 11 == 0
    }
}

struct SableLibraryCoverDownloadService: Sendable {
    var bbcClient = SableLibraryBigBookCoversClient()
    var storefrontHTMLLoader: (@Sendable (URL) async throws -> String)? = nil
    private static let storefrontSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldSetCookies = true
        configuration.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: configuration)
    }()
    private static let imageSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 25
        configuration.timeoutIntervalForResource = 45
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: configuration)
    }()

    private struct CoverVisualSignature: Sendable {
        static let width = 32
        static let height = 48
        static let equivalentDistance = 0.02

        var rgba: [UInt8]

        func distance(to other: CoverVisualSignature) -> Double {
            guard rgba.count == other.rgba.count, !rgba.isEmpty else {
                return .infinity
            }
            var squaredDifference = 0.0
            var comparedChannelCount = 0
            for offset in stride(from: 0, to: rgba.count, by: 4) {
                for channel in 0..<3 {
                    let difference = Double(Int(rgba[offset + channel]) - Int(other.rgba[offset + channel])) / 255.0
                    squaredDifference += difference * difference
                    comparedChannelCount += 1
                }
            }
            return sqrt(squaredDifference / Double(max(1, comparedChannelCount)))
        }

        func isEquivalent(to other: CoverVisualSignature) -> Bool {
            distance(to: other) <= Self.equivalentDistance
        }

        static func make(from data: Data) -> CoverVisualSignature? {
            #if canImport(ImageIO) && canImport(CoreGraphics)
            let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
            guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
                return nil
            }
            let thumbnailOptions = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: 128
            ] as CFDictionary
            guard let image = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                thumbnailOptions
            ) else {
                return nil
            }

            var rgba = [UInt8](
                repeating: 0,
                count: width * height * 4
            )
            let rendered = rgba.withUnsafeMutableBytes { bytes -> Bool in
                guard let context = CGContext(
                    data: bytes.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                        | CGBitmapInfo.byteOrder32Big.rawValue
                ) else {
                    return false
                }
                context.interpolationQuality = .high
                context.draw(
                    image,
                    in: CGRect(x: 0, y: 0, width: width, height: height)
                )
                return true
            }
            return rendered ? CoverVisualSignature(rgba: rgba) : nil
            #else
            return nil
            #endif
        }
    }

    private final class CoverFingerprintLedger: @unchecked Sendable {
        struct Assignment {
            var bookIndex: Int
            var language: String
            var role: SableLibraryProviderCoverRole
            var relativePath: String
        }

        private var assignments: [String: Assignment] = [:]
        private var assignmentsByPath: [String: Assignment] = [:]

        func assignment(for fingerprint: String) -> Assignment? {
            assignments[fingerprint]
        }

        func assignment(forAnyPath paths: [String]) -> Assignment? {
            paths.lazy.compactMap { self.assignmentsByPath[$0] }.first
        }

        func record(
            _ fingerprint: String,
            bookIndex: Int,
            language: String,
            role: SableLibraryProviderCoverRole,
            relativePath: String
        ) {
            let assignment = Assignment(
                bookIndex: bookIndex,
                language: language,
                role: role,
                relativePath: relativePath
            )
            assignments[fingerprint] = assignment
            assignmentsByPath[relativePath] = assignment
        }
    }

    private final class CoverFileFingerprintIndex: @unchecked Sendable {
        struct FileInfo {
            var width: Int
            var height: Int
            var bytes: Int

            var pixels: Int {
                width * height
            }
        }

        private var pathsByFingerprint: [String: [String]] = [:]
        private var fingerprintByPath: [String: String] = [:]
        private var visualSignatureByPath: [String: CoverVisualSignature] = [:]
        private var fileInfoByPath: [String: FileInfo] = [:]

        init(folder: URL) {
            let coverFolder = folder.appendingPathComponent("_covers", isDirectory: true)
            let folderPath = folder.standardizedFileURL.path(percentEncoded: false)
            guard let enumerator = FileManager.default.enumerator(
                at: coverFolder,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                return
            }
            let allowedExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "avif"]
            for case let url as URL in enumerator {
                guard allowedExtensions.contains(url.pathExtension.lowercased()),
                      let data = try? Data(contentsOf: url) else {
                    continue
                }
                let path = url.standardizedFileURL.path(percentEncoded: false)
                guard path.hasPrefix(folderPath + "/") else { continue }
                let relativePath = String(path.dropFirst(folderPath.count + 1))
                let fingerprint = SHA256.hash(data: data)
                    .map { String(format: "%02x", $0) }
                    .joined()
                pathsByFingerprint[fingerprint, default: []].append(relativePath)
                fingerprintByPath[relativePath] = fingerprint
                if let visualSignature = CoverVisualSignature.make(from: data) {
                    visualSignatureByPath[relativePath] = visualSignature
                }
                if let dimensions = Self.imageDimensions(in: data) {
                    fileInfoByPath[relativePath] = FileInfo(
                        width: dimensions.width,
                        height: dimensions.height,
                        bytes: data.count
                    )
                }
            }
        }

        func paths(for fingerprint: String) -> [String] {
            pathsByFingerprint[fingerprint] ?? []
        }

        func fingerprint(for relativePath: String) -> String? {
            fingerprintByPath[relativePath]
        }

        func visualSignature(for relativePath: String) -> CoverVisualSignature? {
            visualSignatureByPath[relativePath]
        }

        func visuallyEquivalentPaths(to signature: CoverVisualSignature) -> [String] {
            visualSignatureByPath.compactMap { path, existingSignature in
                signature.isEquivalent(to: existingSignature) ? path : nil
            }
        }

        func fileInfo(for relativePath: String) -> FileInfo? {
            fileInfoByPath[relativePath]
        }

        func record(
            _ fingerprint: String,
            relativePath: String,
            data: Data,
            dimensions: (width: Int, height: Int)
        ) {
            if !pathsByFingerprint[fingerprint, default: []].contains(relativePath) {
                pathsByFingerprint[fingerprint, default: []].append(relativePath)
            }
            fingerprintByPath[relativePath] = fingerprint
            if let signature = CoverVisualSignature.make(from: data) {
                visualSignatureByPath[relativePath] = signature
            }
            fileInfoByPath[relativePath] = FileInfo(
                width: dimensions.width,
                height: dimensions.height,
                bytes: data.count
            )
        }

        private static func imageDimensions(in data: Data) -> (width: Int, height: Int)? {
            #if canImport(ImageIO)
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(
                    source,
                    0,
                    nil
                  ) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
                  let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
                return nil
            }
            return (width.intValue, height.intValue)
            #else
            return nil
            #endif
        }
    }

    private struct ExistingStoreEvidenceRepair {
        var manifest: SableLibraryDownloadedCoverManifest
        var repairedCoverCount: Int
        var repairedFieldCount: Int
        var unresolvedCoverCount: Int
        var notes: [String]
    }

    private struct StorefrontPageEvidence {
        var title: String?
        var mediaType: String?
    }

    private func existingCoverSearchAttempts(
        in manifest: SableLibraryDownloadedCoverManifest?
    ) -> [SableLibraryCoverSearchAttempt] {
        guard let manifest else { return [] }
        var attempts = manifest.searchAttempts ?? []
        let hasMangaBakaTrace = manifest.skipped.contains {
            $0.hasPrefix("\(SableLibraryCoverSource.mangaBaka.displayName):")
        }

        for language in ["jp", "en"] {
            let alreadyProven = attempts.contains {
                SableLibraryCoverDownloadPlanner.normalizedLanguage($0.language) == language
                    && ($0.pass == .mangaBakaBaseline || $0.pass == .combined)
            }
            guard !alreadyProven else { continue }

            let hasSavedMangaBakaCover = manifest.entries.contains { entry in
                entry.covers.contains {
                    SableLibraryCoverDownloadPlanner.normalizedLanguage($0.language) == language
                        && $0.source == SableLibraryCoverSource.mangaBaka.displayName
                }
            }
            let hasLegacyLanguageResult = manifest.skipped.contains { note in
                guard note.hasPrefix("No trusted cover found in") else { return false }
                return language == "jp"
                    ? note.contains(SableLibraryCoverSource.bookLiveJP.displayName)
                    : note.contains(SableLibraryCoverSource.bookWalkerGlobal.displayName)
            }
            guard hasSavedMangaBakaCover || (hasMangaBakaTrace && hasLegacyLanguageResult) else {
                continue
            }
            attempts.append(
                SableLibraryCoverSearchAttempt(
                    language: language,
                    pass: .mangaBakaBaseline,
                    completedAt: manifest.generatedAt,
                    providers: [SableLibraryCoverSource.mangaBaka.displayName]
                )
            )
        }
        return attempts
    }

    private func updatedCoverSearchAttempts(
        existing: [SableLibraryCoverSearchAttempt],
        request: SableLibraryCoverDownloadRequest,
        completedAt: String
    ) -> [SableLibraryCoverSearchAttempt] {
        var attempts = existing
        for language in Set(
            request.languages.map(SableLibraryCoverDownloadPlanner.normalizedLanguage)
        ).sorted() {
            attempts.removeAll {
                SableLibraryCoverDownloadPlanner.normalizedLanguage($0.language) == language
                    && $0.pass == request.downloadPass
            }
            attempts.append(
                SableLibraryCoverSearchAttempt(
                    language: language,
                    pass: request.downloadPass,
                    completedAt: completedAt,
                    providers: SableLibraryCoverDownloadPlanner.normalCoverDownloadOrder(
                        for: language,
                        in: request
                    ).map(\.displayName)
                )
            )
        }
        return attempts.sorted {
            if $0.language != $1.language {
                return $0.language < $1.language
            }
            return $0.pass.rawValue < $1.pass.rawValue
        }
    }

    func downloadCovers(
        request: SableLibraryCoverDownloadRequest,
        folder: URL,
        root: URL
    ) async throws -> SableLibraryCoverDownloadResult {
        guard !request.localBooks.isEmpty else { throw SableLibraryCoverDownloadError.noLocalBooks }
        guard !request.queryTitles.isEmpty || !request.isbn13.isEmpty else {
            throw SableLibraryCoverDownloadError.noQueries
        }

        var coversByBookIndex: [Int: [SableLibraryDownloadedCoverManifestCover]] = [:]
        var skipped: [String] = []
        var downloadedCount = 0
        let fingerprintLedger = CoverFingerprintLedger()
        let fileFingerprintIndex = CoverFileFingerprintIndex(folder: folder)
        let allBookIndexes = Set(1...request.localBooks.count)
        var cachedMangaBakaCandidates: [SableLibraryProviderCoverCandidate]?
        let manifestURL = folder
            .appendingPathComponent("_covers", isDirectory: true)
            .appendingPathComponent("cover-manifest.json")
        let existingManifestBeforeLookup = (try? Data(contentsOf: manifestURL)).flatMap {
            try? JSONDecoder().decode(SableLibraryDownloadedCoverManifest.self, from: $0)
        }
        let existingSearchAttempts = existingCoverSearchAttempts(
            in: existingManifestBeforeLookup
        )
        let evidenceRepair = await repairExistingStoreEvidence(
            manifestURL: manifestURL,
            request: request,
            root: root
        )
        if let existingData = try? Data(contentsOf: manifestURL),
           let existingManifest = try? JSONDecoder().decode(
            SableLibraryDownloadedCoverManifest.self,
            from: existingData
           ) {
            skipped.append(
                contentsOf: SableLibraryCoverDownloadPlanner
                    .preservedMissingCoverSearchNotes(
                        existingManifest.skipped,
                        requestedLanguages: request.languages
                    )
            )
        }
        skipped.append(contentsOf: evidenceRepair?.notes ?? [])

        if request.verifyExistingStoreEvidenceOnly,
           let evidenceRepair {
            let reusedCount = evidenceRepair.manifest.entries.reduce(0) { count, entry in
                count + entry.covers.filter {
                    $0.role == .normal
                        && request.languages.map(
                            SableLibraryCoverDownloadPlanner.normalizedLanguage
                        ).contains(
                            SableLibraryCoverDownloadPlanner.normalizedLanguage($0.language)
                        )
                }.count
            }
            return SableLibraryCoverDownloadResult(
                manifest: evidenceRepair.manifest,
                downloadedCount: 0,
                reusedCount: reusedCount,
                skipped: evidenceRepair.notes
            )
        }

        skipped.append(contentsOf: try sanitizeExistingManifestBeforeLookup(
            manifestURL: manifestURL,
            request: request,
            folder: folder,
            root: root,
            fileFingerprintIndex: fileFingerprintIndex
        ))
        let shouldLoadReusableNormalCovers =
            request.downloadPass == .storeQualityUpgrade
            || !request.refreshExistingNormalCovers
        let reusableCovers = shouldLoadReusableNormalCovers
            ? reusableExistingNormalCovers(
                manifestURL: manifestURL,
                request: request,
                folder: folder,
                root: root
            )
            : [:]
        merge(reusableCovers, into: &coversByBookIndex)
        let reusedCount = reusableCovers.values.reduce(0) { $0 + $1.count }
        if reusedCount > 0 {
            skipped.append(
                "Reused \(reusedCount) existing normal cover\(reusedCount == 1 ? "" : "s"); only missing slots were searched."
            )
            for (bookIndex, covers) in reusableCovers {
                for cover in covers {
                    guard let fingerprint = fileFingerprintIndex.fingerprint(for: cover.path) else {
                        continue
                    }
                    fingerprintLedger.record(
                        fingerprint,
                        bookIndex: bookIndex,
                        language: SableLibraryCoverDownloadPlanner.normalizedLanguage(cover.language),
                        role: cover.role,
                        relativePath: cover.path
                    )
                }
            }
        }

        for language in request.languages.map(SableLibraryCoverDownloadPlanner.normalizedLanguage) {
            let order = SableLibraryCoverDownloadPlanner.normalCoverDownloadOrder(
                for: language,
                in: request
            )
            var searchableBookIndexes = allBookIndexes
            if request.downloadPass != .storeQualityUpgrade {
                for (bookIndex, covers) in reusableCovers {
                    if covers.contains(where: {
                        $0.role == .normal
                            && SableLibraryCoverDownloadPlanner.normalizedLanguage($0.language) == language
                    }) {
                        searchableBookIndexes.remove(bookIndex)
                    }
                }
            }

            for source in order {
                guard SableLibraryCoverSourcePolicy.canUseAsNormalCover(source) else { continue }
                guard !searchableBookIndexes.isEmpty else { break }
                if source == .mangaBaka {
                    guard !request.mangaBakaSeriesIDs.isEmpty else {
                        skipped.append(
                            "\(language): MangaBaka baseline skipped because no MangaBaka series ID is saved."
                        )
                        continue
                    }
                    if cachedMangaBakaCandidates == nil {
                        do {
                            cachedMangaBakaCandidates = try await mangaBakaCoverCandidates(
                                request: request
                            )
                        } catch is CancellationError {
                            throw CancellationError()
                        } catch {
                            cachedMangaBakaCandidates = []
                            skipped.append("MangaBaka: \(error.localizedDescription)")
                        }
                    }
                    let allMatches = SableLibraryCoverDownloadPlanner.matchedProviderCovers(
                        candidates: cachedMangaBakaCandidates ?? [],
                        source: .mangaBaka,
                        language: language,
                        localBooks: request.localBooks,
                        includeSpecials: false
                    )
                    let matched = SableLibraryCoverDownloadPlanner.covers(
                        allMatches,
                        forBookIndexes: searchableBookIndexes
                    )
                    let writeResult = try await writeMatchedCovers(
                        matched,
                        request: request,
                        folder: folder,
                        root: root,
                        language: language,
                        source: .mangaBaka,
                        fingerprintLedger: fingerprintLedger,
                        fileFingerprintIndex: fileFingerprintIndex
                    )
                    mergePreferredCoverSelection(
                        writeResult.coversByBookIndex,
                        into: &coversByBookIndex
                    )
                    skipped.append(contentsOf: writeResult.skipped)
                    downloadedCount += writeResult.downloadedCount
                    continue
                }

                guard let provider = SableLibraryBigBookCoversProvider.provider(for: source) else { continue }
                do {
                    let upgradeBaselines = normalCoverBaselines(
                        in: coversByBookIndex,
                        language: language,
                        bookIndexes: searchableBookIndexes
                    )
                    let providerResult = try await bigBookCovers(
                        request: request,
                        provider: provider,
                        source: source,
                        language: language,
                        neededBookIndexes: searchableBookIndexes,
                        folder: folder,
                        root: root,
                        fingerprintLedger: fingerprintLedger,
                        fileFingerprintIndex: fileFingerprintIndex,
                        normalCoverUpgradeBaselines: upgradeBaselines
                    )
                    mergePreferredCoverSelection(
                        providerResult.coversByBookIndex,
                        into: &coversByBookIndex
                    )
                    skipped.append(contentsOf: providerResult.skipped)
                    downloadedCount += providerResult.downloadedCount
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    skipped.append(
                        "\(source.displayName): temporarily unavailable (\(error.localizedDescription)). Trying the next trusted source."
                    )
                }
            }

            let coveredNormalBookIndexes = normalCoverBookIndexes(
                in: coversByBookIndex,
                language: language
            )
            if request.downloadPass != .storeQualityUpgrade,
               request.includeSpecials,
               !coveredNormalBookIndexes.isEmpty,
               !request.mangaBakaSeriesIDs.isEmpty {
                if cachedMangaBakaCandidates == nil {
                    do {
                        cachedMangaBakaCandidates = try await mangaBakaCoverCandidates(
                            request: request
                        )
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        cachedMangaBakaCandidates = []
                        skipped.append("MangaBaka: \(error.localizedDescription)")
                    }
                }
                let candidates = (cachedMangaBakaCandidates ?? []).filter {
                    $0.shouldSaveAsExtraCover || $0.isAudiobookCover
                }
                let matched = SableLibraryCoverDownloadPlanner.matchedProviderCovers(
                    candidates: candidates,
                    source: .mangaBaka,
                    language: language,
                    localBooks: request.localBooks,
                    includeSpecials: true
                )
                let writeResult = try await writeMatchedCovers(
                    matched,
                    request: request,
                    folder: folder,
                    root: root,
                    language: language,
                    source: .mangaBaka,
                    fingerprintLedger: fingerprintLedger,
                    fileFingerprintIndex: fileFingerprintIndex
                )
                merge(writeResult.coversByBookIndex, into: &coversByBookIndex)
                skipped.append(contentsOf: writeResult.skipped)
                downloadedCount += writeResult.downloadedCount
            }

            let missingCount = allBookIndexes.subtracting(coveredNormalBookIndexes).count
            if missingCount > 0 {
                let missingReason = SableLibraryCoverSourcePolicy.missingCoverReason(
                    language: language,
                    pass: request.downloadPass
                )
                skipped.append(
                    "\(missingReason) \(missingCount) of \(request.localBooks.count) book slots remain empty."
                )
            }
        }

        let freshEntries = SableLibraryCoverDownloadPlanner.manifestEntries(
            request: request,
            coversByBookIndex: coversByBookIndex
        )
        let preservedEntries = preservingExistingManifestEntries(
            freshEntries,
            manifestURL: manifestURL,
            request: request,
            folder: folder,
            root: root,
            excludedMangaBakaItemIDs: Set(
                (cachedMangaBakaCandidates ?? [])
                    .filter(\.isAudiobookCover)
                    .compactMap(\.providerItemID)
            )
        )
        let crossVolumeAudit = removingCrossVolumeDuplicateCoverReferences(
            preservedEntries,
            folder: folder,
            fileFingerprintIndex: fileFingerprintIndex,
            languages: requestedCoverLanguageScope(for: request)
        )
        let entries = crossVolumeAudit.entries
        skipped.append(contentsOf: crossVolumeAudit.skipped)
        for language in Set(
            request.languages.map(SableLibraryCoverDownloadPlanner.normalizedLanguage)
        ) {
            let missingReason = SableLibraryCoverSourcePolicy.missingCoverReason(
                language: language,
                pass: request.downloadPass
            )
            let allMissingReasonPrefixes = [
                SableLibraryCoverSourcePolicy.missingCoverReason(language: language)
            ] + SableLibraryCoverDownloadPass.allCases.map {
                SableLibraryCoverSourcePolicy.missingCoverReason(
                    language: language,
                    pass: $0
                )
            }
            skipped.removeAll { note in
                allMissingReasonPrefixes.contains { note.hasPrefix($0) }
            }
            let missingCount = missingNormalCoverCount(
                in: entries,
                request: request,
                language: language
            )
            if missingCount > 0 {
                skipped.append(
                    "\(missingReason) \(missingCount) of \(request.localBooks.count) book slots remain empty."
                )
            }
        }
        if request.replaceUnprovenNormalCovers {
            for language in Set(
                request.languages.map(SableLibraryCoverDownloadPlanner.normalizedLanguage)
            ).sorted() {
                let prefix = SableLibraryCoverDownloadPlanner.unprovenReplacementReason(
                    language: language
                )
                skipped.removeAll { $0.hasPrefix(prefix) }
                let remaining = entries.reduce(0) { count, entry in
                    count + entry.covers.filter { cover in
                        cover.role == .normal
                            && SableLibraryCoverDownloadPlanner.normalizedLanguage(
                                cover.language
                            ) == language
                            && manifestCoverNeedsTrustedReplacement(
                                cover,
                                entry: entry,
                                request: request
                            )
                    }.count
                }
                let note = remaining == 0
                    ? "\(prefix) schema \(SableLibraryCoverDownloadPlanner.unprovenReplacementSchemaVersion); every unproven normal cover was replaced by a trusted match."
                    : "\(prefix) schema \(SableLibraryCoverDownloadPlanner.unprovenReplacementSchemaVersion); no trusted replacement was found for \(remaining) normal cover"
                        + "\(remaining == 1 ? "" : "s"). Existing image files were kept as fallbacks."
                skipped.append(note)
            }
        }
        let completedAt = ISO8601DateFormatter().string(from: Date())
        let manifest = SableLibraryDownloadedCoverManifest(
            generatedAt: completedAt,
            seriesTitle: request.seriesTitle,
            mediaType: request.mediaType,
            manualSeriesMatches: request.manualSeriesMatches.isEmpty ? nil : request.manualSeriesMatches,
            searchAttempts: updatedCoverSearchAttempts(
                existing: existingSearchAttempts,
                request: request,
                completedAt: completedAt
            ),
            entries: entries,
            skipped: skipped
        )
        let finalized = try finalizeCoverManifest(
            manifest,
            manifestURL: manifestURL,
            folder: folder,
            root: root
        )

        guard !finalized.manifest.entries.isEmpty else {
            throw SableLibraryCoverDownloadError.noTrustedCovers(
                (skipped + finalized.notes).joined(separator: "\n")
            )
        }

        return SableLibraryCoverDownloadResult(
            manifest: finalized.manifest,
            downloadedCount: downloadedCount,
            reusedCount: reusedCount,
            skipped: skipped + finalized.notes
        )
    }

    func cleanupInterruptedCoverDownload(
        folder: URL,
        root: URL
    ) -> [String] {
        let rootPath = canonicalCoverPath(root)
        let folderPath = canonicalCoverPath(folder)
        guard folderPath.hasPrefix(rootPath + "/") else {
            return ["Interrupted cover cleanup skipped an unsafe folder path."]
        }

        let manifestURL = folder
            .appendingPathComponent("_covers", isDirectory: true)
            .appendingPathComponent("cover-manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(
                SableLibraryDownloadedCoverManifest.self,
                from: data
              ) else {
            return []
        }

        do {
            return try finalizeCoverManifest(
                manifest,
                manifestURL: manifestURL,
                folder: folder,
                root: root
            ).notes
        } catch {
            return [
                "Interrupted cover cleanup could not reconcile partial files: "
                    + error.localizedDescription
            ]
        }
    }

    private func repairExistingStoreEvidence(
        manifestURL: URL,
        request: SableLibraryCoverDownloadRequest,
        root: URL
    ) async -> ExistingStoreEvidenceRepair? {
        guard let data = try? Data(contentsOf: manifestURL),
              var manifest = try? JSONDecoder().decode(
                SableLibraryDownloadedCoverManifest.self,
                from: data
              ) else {
            return nil
        }

        let requestedLanguages = Set(
            request.languages.map(SableLibraryCoverDownloadPlanner.normalizedLanguage)
        )
        let manualMatchesChanged =
            !request.manualSeriesMatches.isEmpty
                && (manifest.manualSeriesMatches ?? []) != request.manualSeriesMatches
        var pageEvidenceByURL: [String: StorefrontPageEvidence] = [:]
        var mediaTypeByStoreSeries: [String: String] = [:]
        var repairedCoverCount = 0
        var repairedFieldCount = 0

        for entryIndex in manifest.entries.indices {
            for coverIndex in manifest.entries[entryIndex].covers.indices {
                var cover = manifest.entries[entryIndex].covers[coverIndex]
                let language = SableLibraryCoverDownloadPlanner.normalizedLanguage(
                    cover.language
                )
                guard cover.role == .normal,
                      requestedLanguages.contains(language),
                      let source = SableLibraryCoverSource.allCases.first(where: {
                          $0.displayName == cover.source || $0.rawValue == cover.source
                      }),
                      source.isStoreSource else {
                    continue
                }

                let original = cover
                let manualMatch = request.manualSeriesMatches.first {
                    $0.source == source
                }
                if let manualMatch {
                    if cover.providerSeriesID?.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty != false {
                        cover.providerSeriesID = manualMatch.providerID
                    }
                    if cover.providerTitle?.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty != false {
                        cover.providerTitle = manualMatch.title
                    }
                    if cover.providerMediaType?.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty != false {
                        cover.providerMediaType =
                            manualMatch.bookType ?? manualMatch.mediaType
                    }
                }

                let rawStoreURL = cover.providerURL?.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                let usableStoreURL = rawStoreURL.flatMap { value -> String? in
                    guard !value.isEmpty, let url = URL(string: value),
                          Self.isStorefrontURL(url, for: source) else {
                        return nil
                    }
                    return value
                }
                if let usableStoreURL {
                    let identity = SableLibraryCoverDownloadPlanner.storefrontIdentity(
                        from: usableStoreURL,
                        source: source
                    )
                    if cover.providerItemID?.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty != false {
                        cover.providerItemID = identity.providerItemID
                    }
                    if cover.providerSeriesID?.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty != false {
                        cover.providerSeriesID = identity.providerSeriesID
                    }
                    if cover.providerVolume == nil {
                        cover.providerVolume = identity.providerVolume
                    }
                }

                let seriesKey = [
                    source.rawValue,
                    cover.providerSeriesID
                        ?? manifest.seriesTitle
                        ?? request.seriesTitle
                ].joined(separator: "|")
                let cachedSeriesMediaType = mediaTypeByStoreSeries[seriesKey]
                var storeMediaTypeWasVerified = false
                if source != .amazon,
                   source != .amazonJP,
                   let cachedMediaType = cachedSeriesMediaType,
                   cover.providerMediaType == nil
                    || request.verifyExistingStoreEvidenceOnly {
                    cover.providerMediaType = cachedMediaType
                    storeMediaTypeWasVerified = true
                }

                let localVolume = manifest.entries[entryIndex].volume
                let shouldRefreshStoreMediaType =
                    request.verifyExistingStoreEvidenceOnly
                    && (
                        source == .amazon
                            || source == .amazonJP
                            || cachedSeriesMediaType == nil
                    )
                let needsPageEvidence =
                    cover.providerTitle?.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty != false
                    || cover.providerMediaType?.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty != false
                    || (localVolume != nil && cover.providerVolume == nil)
                    || shouldRefreshStoreMediaType

                if needsPageEvidence,
                   let usableStoreURL,
                   let storefrontURL = URL(string: usableStoreURL) {
                    let pageEvidence: StorefrontPageEvidence?
                    if let cached = pageEvidenceByURL[usableStoreURL] {
                        pageEvidence = cached
                    } else {
                        pageEvidence = await storefrontPageEvidence(
                            at: storefrontURL,
                            source: source
                        )
                        if let pageEvidence {
                            pageEvidenceByURL[usableStoreURL] = pageEvidence
                        }
                    }

                    if let pageEvidence {
                        if cover.providerTitle?.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty != false {
                            cover.providerTitle = pageEvidence.title
                        }
                        if let pageMediaType = pageEvidence.mediaType {
                            cover.providerMediaType = pageMediaType
                            storeMediaTypeWasVerified = true
                            if source != .amazon, source != .amazonJP {
                                mediaTypeByStoreSeries[seriesKey] = pageMediaType
                            }
                        }
                        if cover.providerVolume == nil,
                           let pageTitle = pageEvidence.title,
                           let pageVolume = SableLibraryCoverDownloadPlanner
                            .explicitVolumeNumber(in: pageTitle) {
                            cover.providerVolume = pageVolume
                        }
                    }
                }

                if storeMediaTypeWasVerified {
                    cover.status = "selected_reused_store_verified"
                } else if request.verifyExistingStoreEvidenceOnly {
                    cover.status = Self.storeCheckedUnverifiedStatus(
                        cover.status
                    )
                }
                if cover != original {
                    let changedFieldCount = [
                        original.status != cover.status,
                        original.providerTitle != cover.providerTitle,
                        original.providerSeriesID != cover.providerSeriesID,
                        original.providerItemID != cover.providerItemID,
                        original.providerVolume != cover.providerVolume,
                        original.providerMediaType != cover.providerMediaType
                    ].filter { $0 }.count
                    repairedCoverCount += 1
                    repairedFieldCount += changedFieldCount
                    manifest.entries[entryIndex].covers[coverIndex] = cover
                }
            }
        }

        if !(request.manualSeriesMatches.isEmpty) {
            manifest.manualSeriesMatches = request.manualSeriesMatches
        }
        let unresolvedByLanguage = Dictionary(
            uniqueKeysWithValues: requestedLanguages.sorted().map { language in
                let count = manifest.entries.reduce(0) { partialCount, entry in
                    partialCount + entry.covers.filter { cover in
                        guard cover.role == .normal,
                              SableLibraryCoverDownloadPlanner.normalizedLanguage(
                                cover.language
                              ) == language else {
                            return false
                        }
                        return cover.providerTitle?.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty != false
                            || cover.providerItemID?.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).isEmpty != false
                            || cover.providerMediaType?.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).isEmpty != false
                            || (
                                SableLibraryCoverSource.allCases.first(where: {
                                    $0.displayName == cover.source || $0.rawValue == cover.source
                                })?.isStoreSource == true
                                    && !cover.status.contains("store_verified")
                            )
                            || (entry.volume != nil && cover.providerVolume == nil)
                    }.count
                }
                return (language, count)
            }
        )
        let unresolvedCoverCount = unresolvedByLanguage.values.reduce(0, +)

        var notes: [String] = []
        if repairedCoverCount > 0 {
            let note = "Store proof repair: updated \(repairedCoverCount) existing cover record"
                + "\(repairedCoverCount == 1 ? "" : "s") without replacing image files."
                + " Updated \(repairedFieldCount) evidence field"
                + "\(repairedFieldCount == 1 ? "" : "s"); store-verified status requires a page-proven media type."
            manifest.skipped.removeAll { $0.hasPrefix("Store proof repair:") }
            manifest.skipped.append(note)
            notes.append(note)
        }
        if unresolvedCoverCount > 0 {
            notes.append(
                "Store proof repair: \(unresolvedCoverCount) existing cover"
                    + "\(unresolvedCoverCount == 1 ? "" : "s") still need"
                    + "\(unresolvedCoverCount == 1 ? "s" : "") a readable store page or an exact series choice."
            )
        }

        var proofNotesChanged = false
        if request.verifyExistingStoreEvidenceOnly {
            for language in requestedLanguages.sorted() {
                let prefix = "Store proof repair \(language.uppercased()) finished:"
                let previousNotes = manifest.skipped.filter { $0.hasPrefix(prefix) }
                manifest.skipped.removeAll { $0.hasPrefix(prefix) }
                let unresolved = unresolvedByLanguage[language] ?? 0
                let note = unresolved == 0
                    ? "\(prefix) schema \(SableLibraryCoverDownloadPlanner.storeProofSchemaVersion); all existing covers now have store evidence."
                    : "\(prefix) schema \(SableLibraryCoverDownloadPlanner.storeProofSchemaVersion); \(unresolved) existing cover"
                        + "\(unresolved == 1 ? "" : "s") still need"
                        + "\(unresolved == 1 ? "s" : "") a readable product page or exact series choice."
                manifest.skipped.append(note)
                proofNotesChanged = previousNotes != [note]
                    || proofNotesChanged
            }
        }

        guard repairedCoverCount > 0 || manualMatchesChanged || proofNotesChanged else {
            return ExistingStoreEvidenceRepair(
                manifest: manifest,
                repairedCoverCount: 0,
                repairedFieldCount: 0,
                unresolvedCoverCount: unresolvedCoverCount,
                notes: notes
            )
        }

        manifest.generatedAt = ISO8601DateFormatter().string(from: Date())
        guard let updatedData = try? JSONEncoder.sableCoverManifestEncoder.encode(manifest),
              (try? writeManifestAtomicallyIfChanged(
                  updatedData,
                  to: manifestURL,
                  root: root
              )) != nil else {
            return ExistingStoreEvidenceRepair(
                manifest: manifest,
                repairedCoverCount: repairedCoverCount,
                repairedFieldCount: repairedFieldCount,
                unresolvedCoverCount: unresolvedCoverCount,
                notes: notes + ["Store proof repair could not save the updated manifest."]
            )
        }
        return ExistingStoreEvidenceRepair(
            manifest: manifest,
            repairedCoverCount: repairedCoverCount,
            repairedFieldCount: repairedFieldCount,
            unresolvedCoverCount: unresolvedCoverCount,
            notes: notes
        )
    }

    private static func storeCheckedUnverifiedStatus(_ status: String) -> String {
        let suffix = "_store_checked_unverified"
        let trimmed = status.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains("store_verified"),
              !trimmed.contains("store_checked_unverified") else {
            return trimmed
        }
        return trimmed.isEmpty ? "store_checked_unverified" : trimmed + suffix
    }

    private func storefrontPageEvidence(
        at rawURL: URL,
        source: SableLibraryCoverSource
    ) async -> StorefrontPageEvidence? {
        let url = storefrontVerificationURL(for: rawURL)
        guard let html = try? await loadStorefrontHTML(from: url) else {
            return nil
        }
        return StorefrontPageEvidence(
            title: SableLibraryCoverDownloadPlanner.providerPageTitle(
                from: html,
                source: source
            ),
            mediaType: SableLibraryCoverDownloadPlanner.providerPageMediaType(
                from: html
            )
        )
    }

    private func loadStorefrontHTML(from url: URL) async throws -> String {
        let requestURL = Self.canonicalStorefrontPageURL(url)
        if let storefrontHTMLLoader {
            return try await storefrontHTMLLoader(requestURL)
        }
        var request = URLRequest(url: requestURL)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue(
            "text/html,application/xhtml+xml",
            forHTTPHeaderField: "Accept"
        )
        request.setValue(
            "ja-JP,ja;q=0.9,en-US;q=0.7,en;q=0.5",
            forHTTPHeaderField: "Accept-Language"
        )
        let (data, response) = try await Self.storefrontSession.data(for: request)
        guard data.count <= 8 * 1_024 * 1_024,
              (response as? HTTPURLResponse).map({
                  (200..<300).contains($0.statusCode)
              }) != false,
              let html = String(data: data, encoding: .utf8) else {
            throw SableLibraryCoverDownloadError.invalidProviderResponse(
                "store page could not be read"
            )
        }
        return html
    }

    private static func canonicalStorefrontPageURL(_ url: URL) -> URL {
        guard let host = url.host?.lowercased(),
              host == "bookwalker.jp" || host.hasSuffix(".bookwalker.jp"),
              !url.path.hasSuffix("/"),
              var components = URLComponents(
                url: url,
                resolvingAgainstBaseURL: false
              ) else {
            return url
        }
        components.path += "/"
        return components.url ?? url
    }

    private static func isStorefrontURL(
        _ url: URL,
        for source: SableLibraryCoverSource
    ) -> Bool {
        let host = url.host?.lowercased() ?? ""
        switch source {
        case .bookLiveJP:
            return host == "booklive.jp" || host.hasSuffix(".booklive.jp")
        case .bookWalkerJP:
            return host == "bookwalker.jp" || host.hasSuffix(".bookwalker.jp")
        case .bookWalkerGlobal:
            return host == "bookwalker.com" || host.hasSuffix(".bookwalker.com")
        case .amazonJP:
            return host == "amazon.co.jp" || host.hasSuffix(".amazon.co.jp")
        case .amazon:
            return host.contains("amazon.")
        case .mangaBaka, .ranobeDB, .unknown:
            return false
        }
    }

    private func reusableExistingNormalCovers(
        manifestURL: URL,
        request: SableLibraryCoverDownloadRequest,
        folder: URL,
        root: URL
    ) -> [Int: [SableLibraryDownloadedCoverManifestCover]] {
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(
                SableLibraryDownloadedCoverManifest.self,
                from: data
              ) else {
            return [:]
        }

        let requestedLanguages = Set(
            request.languages.map(SableLibraryCoverDownloadPlanner.normalizedLanguage)
        )
        let rootPath = canonicalCoverPath(root)
        let coverFolderPath = canonicalCoverPath(
            folder.appendingPathComponent("_covers", isDirectory: true)
        )
        let allowedExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "avif"]
        var reusable: [Int: [SableLibraryDownloadedCoverManifestCover]] = [:]

        for (offset, localBook) in request.localBooks.enumerated() {
            let matchingEntry = manifest.entries.first {
                $0.bookFile.caseInsensitiveCompare(localBook.fileName) == .orderedSame
            } ?? manifest.entries.first {
                localBook.volumeNumber != nil && $0.volume == localBook.volumeNumber
            }
            guard let matchingEntry else { continue }

            for language in requestedLanguages {
                let authoritativeMatches =
                    SableLibraryCoverDownloadPlanner.authoritativeManualSeriesMatches(
                        for: language,
                        in: request
                    )
                let candidates = matchingEntry.covers.filter { cover in
                    guard cover.role == .normal,
                          SableLibraryCoverDownloadPlanner.normalizedLanguage(cover.language) == language,
                          let width = cover.width,
                          let height = cover.height,
                          SableLibraryCoverDownloadPlanner.coverDimensionsAreArchiveUsable(
                            width: width,
                            height: height
                          ),
                          let providerTitle = cover.providerTitle else {
                        return false
                    }

                    let hasExactManualSeriesIdentity =
                        SableLibraryCoverDownloadPlanner.manifestCover(
                        cover,
                        belongsToAny: authoritativeMatches
                    )
                    if !authoritativeMatches.isEmpty, !hasExactManualSeriesIdentity {
                        return false
                    }
                    if !hasExactManualSeriesIdentity,
                       (
                        !providerTitleBelongsToRequest(
                            providerTitle,
                            request: request
                        )
                            || !SableLibraryCoverDownloadPlanner.providerTitleMatchesLocalSeriesStem(
                                providerTitle,
                                localBookTitle: localBook.fileName
                            )
                       ) {
                        return false
                    }

                    let source = SableLibraryCoverSource.allCases.first {
                        $0.displayName == cover.source
                    } ?? .unknown
                    guard SableLibraryCoverDownloadPlanner.providerTitleLanguageIsCompatible(
                        providerTitle,
                        language: language,
                        source: source
                    ) else {
                        return false
                    }
                    if request.mediaType != nil {
                        guard let providerMediaType = cover.providerMediaType,
                              SableLibraryCoverDownloadPlanner.providerMediaTypeIsCompatible(
                                providerMediaType,
                                isCompatibleWith: request.mediaType
                              ) else {
                            return false
                        }
                    }
                    if let localVolume = localBook.volumeNumber {
                        guard let providerVolume = cover.providerVolume,
                              SableLibraryCoverDownloadPlanner.providerVolume(
                                providerVolume,
                                providerTitle: cover.providerTitle,
                                localTitle: localBook.fileName,
                                source: source,
                                matches: localVolume
                              ) else {
                            return false
                        }
                    }
                    guard manifestStorefrontVolumeIsCompatible(
                        cover,
                        localBook: localBook
                    ) else {
                        return false
                    }

                    let coverURL = cover.path.hasPrefix("/")
                        ? URL(fileURLWithPath: cover.path)
                        : folder.appendingPathComponent(cover.path)
                    let coverPath = canonicalCoverPath(coverURL)
                    return coverPath.hasPrefix(coverFolderPath + "/")
                        && coverPath.hasPrefix(rootPath + "/")
                        && allowedExtensions.contains(coverURL.pathExtension.lowercased())
                        && FileManager.default.fileExists(atPath: coverPath)
                }

                let sourceOrder = SableLibraryCoverSourcePolicy.normalCoverDownloadOrder(
                    language: language
                )
                let best = candidates.min { lhs, rhs in
                    let lhsSource = SableLibraryCoverSource.allCases.first {
                        $0.displayName == lhs.source
                    } ?? .unknown
                    let rhsSource = SableLibraryCoverSource.allCases.first {
                        $0.displayName == rhs.source
                    } ?? .unknown
                    let lhsPixels = (lhs.width ?? 0) * (lhs.height ?? 0)
                    let rhsPixels = (rhs.width ?? 0) * (rhs.height ?? 0)
                    if lhsPixels != rhsPixels {
                        return lhsPixels > rhsPixels
                    }
                    let lhsRank = sourceOrder.firstIndex(of: lhsSource) ?? Int.max
                    let rhsRank = sourceOrder.firstIndex(of: rhsSource) ?? Int.max
                    return lhsRank < rhsRank
                }
                if let best {
                    reusable[offset + 1, default: []].append(best)
                }
            }
        }
        return reusable
    }

    private func sanitizeExistingManifestBeforeLookup(
        manifestURL: URL,
        request: SableLibraryCoverDownloadRequest,
        folder: URL,
        root: URL,
        fileFingerprintIndex: CoverFileFingerprintIndex
    ) throws -> [String] {
        guard let data = try? Data(contentsOf: manifestURL),
              let existingManifest = try? JSONDecoder().decode(
                SableLibraryDownloadedCoverManifest.self,
                from: data
              ) else {
            return []
        }

        let preservedEntries = preservingExistingManifestEntries(
            [],
            manifestURL: manifestURL,
            request: request,
            folder: folder,
            root: root
        )
        let crossVolumeAudit = removingCrossVolumeDuplicateCoverReferences(
            preservedEntries,
            folder: folder,
            fileFingerprintIndex: fileFingerprintIndex,
            languages: requestedCoverLanguageScope(for: request)
        )
        guard crossVolumeAudit.entries != existingManifest.entries else {
            return []
        }

        let oldCoverCount = existingManifest.entries.reduce(0) { $0 + $1.covers.count }
        let newCoverCount = crossVolumeAudit.entries.reduce(0) { $0 + $1.covers.count }
        let removedCount = max(0, oldCoverCount - newCoverCount)
        let note = removedCount == 1
            ? "Local safety pass removed 1 incompatible or duplicate saved cover assignment before provider lookup."
            : "Local safety pass removed \(removedCount) incompatible or duplicate saved cover assignments before provider lookup."
        let sanitizedManifest = SableLibraryDownloadedCoverManifest(
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            seriesTitle: existingManifest.seriesTitle ?? request.seriesTitle,
            mediaType: existingManifest.mediaType ?? request.mediaType,
            manualSeriesMatches: request.manualSeriesMatches.isEmpty
                ? existingManifest.manualSeriesMatches
                : request.manualSeriesMatches,
            searchAttempts: existingManifest.searchAttempts,
            entries: crossVolumeAudit.entries,
            skipped: existingManifest.skipped + crossVolumeAudit.skipped + [note]
        )
        let sanitizedData = try JSONEncoder.sableCoverManifestEncoder.encode(sanitizedManifest)
        try writeManifestAtomicallyIfChanged(
            sanitizedData,
            to: manifestURL,
            root: root
        )
        return crossVolumeAudit.skipped + [note]
    }

    private func preservingExistingManifestEntries(
        _ freshEntries: [SableLibraryDownloadedCoverManifestEntry],
        manifestURL: URL,
        request: SableLibraryCoverDownloadRequest,
        folder: URL,
        root: URL,
        excludedMangaBakaItemIDs: Set<String> = []
    ) -> [SableLibraryDownloadedCoverManifestEntry] {
        guard let data = try? Data(contentsOf: manifestURL),
              let existingManifest = try? JSONDecoder().decode(
                SableLibraryDownloadedCoverManifest.self,
                from: data
              ) else {
            return freshEntries
        }

        let rootPath = canonicalCoverPath(root)
        let coverFolderPath = canonicalCoverPath(
            folder.appendingPathComponent("_covers", isDirectory: true)
        )
        let freshByFile = Dictionary(uniqueKeysWithValues: freshEntries.map { ($0.bookFile.lowercased(), $0) })

        return request.localBooks.map { localBook in
            let matchingExisting = existingManifest.entries.first {
                $0.bookFile.caseInsensitiveCompare(localBook.fileName) == .orderedSame
            } ?? existingManifest.entries.first {
                localBook.volumeNumber != nil && $0.volume == localBook.volumeNumber
            }
            var result = freshByFile[localBook.fileName.lowercased()]
                ?? SableLibraryDownloadedCoverManifestEntry(
                    bookFile: localBook.fileName,
                    volume: localBook.volumeNumber,
                    covers: []
            )

            for existingCover in matchingExisting?.covers ?? [] {
                if existingCover.role != .audiobook,
                   existingCover.source == SableLibraryCoverSource.mangaBaka.displayName,
                   let providerItemID = existingCover.providerItemID,
                   excludedMangaBakaItemIDs.contains(providerItemID) {
                    continue
                }
                let existingSource = SableLibraryCoverSource.allCases.first {
                    $0.displayName == existingCover.source || $0.rawValue == existingCover.source
                } ?? .unknown
                let requiresVerifiedStoreEvidence = existingCover.role == .normal
                    && (
                        (request.refreshExistingNormalCovers && existingSource.isStoreSource)
                            || existingSource == .amazon
                            || existingSource == .amazonJP
                    )
                if requiresVerifiedStoreEvidence {
                    guard let providerTitle = existingCover.providerTitle?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                          !providerTitle.isEmpty,
                          let providerMediaType = existingCover.providerMediaType,
                          SableLibraryCoverDownloadPlanner.providerMediaTypeIsCompatible(
                            providerMediaType,
                            isCompatibleWith: request.mediaType
                          ) else {
                        continue
                    }
                    if let localVolume = localBook.volumeNumber {
                        guard let providerVolume = existingCover.providerVolume,
                              SableLibraryCoverDownloadPlanner.providerVolume(
                                providerVolume,
                                providerTitle: providerTitle,
                                localTitle: localBook.fileName,
                                source: existingSource,
                                matches: localVolume
                              ) else {
                            continue
                        }
                    }
                }
                if existingCover.role == .normal,
                   let width = existingCover.width,
                   let height = existingCover.height,
                   !SableLibraryCoverDownloadPlanner.coverDimensionsHaveBookShape(
                    width: width,
                    height: height
                   ) {
                    continue
                }
                let existingIdentityTitle = existingCover.providerTitle
                    ?? (existingCover.role == .normal ? nil : existingCover.editionNote)
                let existingLanguage =
                    SableLibraryCoverDownloadPlanner.normalizedLanguage(
                        existingCover.language
                    )
                let authoritativeMatches =
                    SableLibraryCoverDownloadPlanner.authoritativeManualSeriesMatches(
                        for: existingLanguage,
                        in: request
                    )
                let hasExactManualSeriesIdentity = existingCover.role == .normal
                    && SableLibraryCoverDownloadPlanner.manifestCover(
                        existingCover,
                        belongsToAny: authoritativeMatches
                    )
                if existingCover.role == .normal,
                   !authoritativeMatches.isEmpty,
                   !hasExactManualSeriesIdentity {
                    continue
                }
                if let providerTitle = existingCover.providerTitle,
                   !SableLibraryCoverDownloadPlanner.providerTitleLanguageIsCompatible(
                    providerTitle,
                    language: existingCover.language,
                    source: SableLibraryCoverSource.allCases.first {
                        $0.displayName == existingCover.source
                    } ?? .unknown
                   ) {
                    continue
                }
                if let providerTitle = existingCover.providerTitle,
                   !hasExactManualSeriesIdentity,
                   (
                    !providerTitleBelongsToRequest(
                        providerTitle,
                        request: request
                    )
                        || (
                            existingCover.role == .normal
                                && !SableLibraryCoverDownloadPlanner
                                    .providerTitleMatchesLocalSeriesStem(
                                        providerTitle,
                                        localBookTitle: localBook.fileName
                                    )
                        )
                   ) {
                    continue
                }
                if !SableLibraryCoverDownloadPlanner.providerBookIdentityIsCompatible(
                    providerTitle: existingIdentityTitle,
                    localBookTitle: localBook.fileName,
                    localVolume: localBook.volumeNumber
                ) {
                    continue
                }
                if existingCover.role != .audiobook,
                   let providerMediaType = existingCover.providerMediaType,
                   !SableLibraryCoverDownloadPlanner.providerMediaTypeIsCompatible(
                    providerMediaType,
                    isCompatibleWith: request.mediaType
                   ) {
                    continue
                }
                if let providerVolume = existingCover.providerVolume,
                   let localVolume = localBook.volumeNumber,
                   !SableLibraryCoverDownloadPlanner.providerVolume(
                    providerVolume,
                    providerTitle: existingIdentityTitle,
                    localTitle: localBook.fileName,
                    source: SableLibraryCoverSource.allCases.first {
                        $0.displayName == existingCover.source || $0.rawValue == existingCover.source
                    },
                    matches: localVolume
                   ) {
                    continue
                }
                if existingCover.status == "preserved_previous_normal" {
                    guard existingCover.role == .normal,
                          let providerTitle = existingCover.providerTitle,
                          !providerTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                          let width = existingCover.width,
                          let height = existingCover.height,
                          SableLibraryCoverDownloadPlanner.coverDimensionsAreArchiveUsable(
                            width: width,
                            height: height
                          ) else {
                        continue
                    }
                    if request.mediaType != nil {
                        guard let providerMediaType = existingCover.providerMediaType,
                              SableLibraryCoverDownloadPlanner.providerMediaTypeIsCompatible(
                                providerMediaType,
                                isCompatibleWith: request.mediaType
                              ) else {
                            continue
                        }
                    }
                    if localBook.volumeNumber != nil, existingCover.providerVolume == nil {
                        continue
                    }
                }
                guard manifestStorefrontVolumeIsCompatible(
                    existingCover,
                    localBook: localBook
                ) else {
                    continue
                }
                let existingURL = folder.appendingPathComponent(existingCover.path)
                let existingPath = canonicalCoverPath(existingURL)
                guard existingPath.hasPrefix(coverFolderPath + "/"),
                      existingPath.hasPrefix(rootPath + "/"),
                      FileManager.default.fileExists(atPath: existingPath),
                      !result.covers.contains(where: { $0.path == existingCover.path }) else {
                    continue
                }

                let replacementIndex = existingCover.role == .normal
                    ? result.covers.firstIndex {
                        $0.role == .normal
                            && SableLibraryCoverDownloadPlanner.normalizedLanguage($0.language)
                                == SableLibraryCoverDownloadPlanner.normalizedLanguage(existingCover.language)
                    }
                    : nil
                if let replacementIndex {
                    let current = result.covers[replacementIndex]
                    let language =
                        SableLibraryCoverDownloadPlanner.normalizedLanguage(
                            current.language
                        )
                    let authoritativeMatches =
                        SableLibraryCoverDownloadPlanner.authoritativeManualSeriesMatches(
                            for: language,
                            in: request
                        )
                    let existingIsExactManual =
                        SableLibraryCoverDownloadPlanner.manifestCover(
                            existingCover,
                            belongsToAny: authoritativeMatches
                        )
                    let currentIsExactManual =
                        SableLibraryCoverDownloadPlanner.manifestCover(
                            current,
                            belongsToAny: authoritativeMatches
                        )
                    let existingEvidence = manifestCoverEvidencePriority(
                        existingCover,
                        bookFile: localBook.fileName,
                        volume: localBook.volumeNumber
                    )
                    let currentEvidence = manifestCoverEvidencePriority(
                        current,
                        bookFile: localBook.fileName,
                        volume: localBook.volumeNumber
                    )
                    let existingPixels = (existingCover.width ?? 0)
                        * (existingCover.height ?? 0)
                    let currentPixels = (current.width ?? 0) * (current.height ?? 0)
                    let shouldReplace: Bool
                    if request.replaceUnprovenNormalCovers,
                       manifestCoverNeedsTrustedReplacement(
                        existingCover,
                        entry: matchingExisting,
                        request: request
                       ) {
                        shouldReplace = false
                    } else if existingIsExactManual != currentIsExactManual {
                        shouldReplace = existingIsExactManual
                    } else {
                        shouldReplace = existingEvidence > currentEvidence
                            || (
                                existingEvidence == currentEvidence
                                    && (
                                        existingPixels > currentPixels
                                            || (
                                                existingPixels == currentPixels
                                                    && coverProviderPriority(existingCover.source)
                                                        > coverProviderPriority(current.source)
                                            )
                                    )
                            )
                    }
                    if shouldReplace {
                        result.covers[replacementIndex] = existingCover
                    }
                    continue
                }

                let existingData = try? Data(contentsOf: existingURL)
                let duplicatesFreshCover = existingData.map { data in
                    result.covers.contains { freshCover in
                        let freshURL = folder.appendingPathComponent(freshCover.path)
                        return (try? Data(contentsOf: freshURL)) == data
                    }
                } ?? false
                guard !duplicatesFreshCover else { continue }
                result.covers.append(existingCover)
            }
            return result
        }
        .filter { !$0.covers.isEmpty }
    }

    private func manifestCoverNeedsTrustedReplacement(
        _ cover: SableLibraryDownloadedCoverManifestCover,
        entry: SableLibraryDownloadedCoverManifestEntry?,
        request: SableLibraryCoverDownloadRequest
    ) -> Bool {
        guard cover.role == .normal else { return false }
        let source = SableLibraryCoverSource.allCases.first {
            $0.displayName == cover.source || $0.rawValue == cover.source
        } ?? .unknown
        if source.isStoreSource, !cover.status.contains("store_verified") {
            return true
        }
        if cover.providerTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            return true
        }
        if cover.providerItemID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            return true
        }
        if request.mediaType != nil,
           cover.providerMediaType?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            return true
        }
        if entry?.volume != nil, cover.providerVolume == nil {
            return true
        }
        return false
    }

    private struct CrossVolumeCoverAudit {
        var entries: [SableLibraryDownloadedCoverManifestEntry]
        var skipped: [String]
    }

    private struct CoverManifestOccurrence {
        var entryIndex: Int
        var coverIndex: Int
        var fingerprint: String?
        var visualSignature: CoverVisualSignature?
        var language: String
        var identityPriority: Int
        var hasStrongVolumeIdentity: Bool
        var rolePriority: Int
        var pixels: Int
        var providerPriority: Int
        var statusPriority: Int
    }

    private func removingCrossVolumeDuplicateCoverReferences(
        _ entries: [SableLibraryDownloadedCoverManifestEntry],
        folder: URL,
        fileFingerprintIndex: CoverFileFingerprintIndex,
        languages: Set<String>? = nil
    ) -> CrossVolumeCoverAudit {
        var occurrences: [CoverManifestOccurrence] = []

        for (entryIndex, entry) in entries.enumerated() {
            for (coverIndex, cover) in entry.covers.enumerated() {
                let normalizedLanguage =
                    SableLibraryCoverDownloadPlanner.normalizedLanguage(cover.language)
                if let languages, !languages.contains(normalizedLanguage) {
                    continue
                }
                let fingerprint = fileFingerprintIndex.fingerprint(for: cover.path)
                    ?? coverFingerprint(
                        at: folder.appendingPathComponent(cover.path)
                    )
                let visualSignature = fileFingerprintIndex.visualSignature(for: cover.path)
                guard fingerprint != nil || visualSignature != nil else {
                    continue
                }
                let hasStrongVolumeIdentity: Bool
                if let providerVolume = cover.providerVolume,
                   let localVolume = entry.volume {
                    hasStrongVolumeIdentity =
                        SableLibraryCoverDownloadPlanner.providerVolume(
                        providerVolume,
                        providerTitle: cover.providerTitle ?? cover.editionNote,
                        localTitle: entry.bookFile,
                    source: SableLibraryCoverSource.allCases.first {
                        $0.displayName == cover.source || $0.rawValue == cover.source
                    },
                        matches: localVolume
                    )
                } else {
                    hasStrongVolumeIdentity = false
                }
                let actualPixels = fileFingerprintIndex.fileInfo(for: cover.path)?.pixels
                let manifestPixels = (cover.width ?? 0) * (cover.height ?? 0)
                occurrences.append(
                    CoverManifestOccurrence(
                        entryIndex: entryIndex,
                        coverIndex: coverIndex,
                        fingerprint: fingerprint,
                        visualSignature: visualSignature,
                        language: normalizedLanguage,
                        identityPriority: manifestCoverEvidencePriority(
                            cover,
                            bookFile: entry.bookFile,
                            volume: entry.volume
                        ),
                        hasStrongVolumeIdentity: hasStrongVolumeIdentity,
                        rolePriority: cover.role == .normal ? 1 : 0,
                        pixels: max(actualPixels ?? 0, manifestPixels),
                        providerPriority: coverProviderPriority(cover.source),
                        statusPriority: cover.status == "preserved_previous_normal" ? 0 : 1
                    )
                )
            }
        }

        guard occurrences.count > 1 else {
            return CrossVolumeCoverAudit(entries: entries, skipped: [])
        }

        var parents = Array(occurrences.indices)
        func root(of index: Int) -> Int {
            var result = index
            while parents[result] != result {
                result = parents[result]
            }
            return result
        }
        func join(_ lhs: Int, _ rhs: Int) {
            let lhsRoot = root(of: lhs)
            let rhsRoot = root(of: rhs)
            if lhsRoot != rhsRoot {
                parents[rhsRoot] = lhsRoot
            }
        }

        for lhsIndex in 0..<(occurrences.count - 1) {
            for rhsIndex in (lhsIndex + 1)..<occurrences.count {
                let lhs = occurrences[lhsIndex]
                let rhs = occurrences[rhsIndex]
                guard lhs.language == rhs.language else { continue }
                let isByteIdentical = lhs.fingerprint != nil
                    && lhs.fingerprint == rhs.fingerprint
                let isVisuallyEquivalent = if let lhsSignature = lhs.visualSignature,
                                               let rhsSignature = rhs.visualSignature {
                    lhsSignature.isEquivalent(to: rhsSignature)
                } else {
                    false
                }
                let lhsVolume = entries[lhs.entryIndex].volume
                let rhsVolume = entries[rhs.entryIndex].volume
                let hasDistinctStrongVolumeIdentity: Bool
                if lhs.hasStrongVolumeIdentity,
                   rhs.hasStrongVolumeIdentity,
                   let lhsVolume,
                   let rhsVolume {
                    hasDistinctStrongVolumeIdentity =
                        !SableLibraryCoverDownloadPlanner.volumeNumbersMatch(
                            lhsVolume,
                            rhsVolume
                        )
                } else {
                    hasDistinctStrongVolumeIdentity = false
                }
                if isByteIdentical
                    || (isVisuallyEquivalent && !hasDistinctStrongVolumeIdentity) {
                    join(lhsIndex, rhsIndex)
                }
            }
        }

        var occurrenceIndexesByGroup: [Int: [Int]] = [:]
        for index in occurrences.indices {
            occurrenceIndexesByGroup[root(of: index), default: []].append(index)
        }

        var removedReferences = Set<String>()
        var skipped: [String] = []
        for occurrenceIndexes in occurrenceIndexesByGroup.values
        where occurrenceIndexes.count > 1 {
            var winningOccurrenceIndex = occurrenceIndexes[0]
            for candidateIndex in occurrenceIndexes.dropFirst() {
                if occurrence(
                    occurrences[candidateIndex],
                    isPreferredOver: occurrences[winningOccurrenceIndex]
                ) {
                    winningOccurrenceIndex = candidateIndex
                }
            }

            let losingIndexes = occurrenceIndexes.filter {
                $0 != winningOccurrenceIndex
            }
            for losingIndex in losingIndexes {
                let occurrence = occurrences[losingIndex]
                removedReferences.insert("\(occurrence.entryIndex)|\(occurrence.coverIndex)")
            }
            let winnerOccurrence = occurrences[winningOccurrenceIndex]
            let winnerEntry = entries[winnerOccurrence.entryIndex]
            skipped.append(
                "Safety: kept one best-quality \(winnerOccurrence.language.uppercased()) cover "
                    + "with \(winnerEntry.bookFile) and left \(losingIndexes.count) visually "
                    + "equivalent cop\(losingIndexes.count == 1 ? "y" : "ies") unreferenced."
            )
        }

        guard !removedReferences.isEmpty else {
            return CrossVolumeCoverAudit(entries: entries, skipped: [])
        }
        let cleanedEntries = entries.enumerated().compactMap { entryIndex, entry in
            var entry = entry
            entry.covers = entry.covers.enumerated().compactMap { coverIndex, cover in
                removedReferences.contains("\(entryIndex)|\(coverIndex)") ? nil : cover
            }
            return entry.covers.isEmpty ? nil : entry
        }
        return CrossVolumeCoverAudit(entries: cleanedEntries, skipped: skipped)
    }

    private func requestedCoverLanguageScope(
        for request: SableLibraryCoverDownloadRequest
    ) -> Set<String>? {
        let languages = Set(
            request.languages.map(SableLibraryCoverDownloadPlanner.normalizedLanguage)
        )
        return languages.isEmpty ? nil : languages
    }

    private func missingNormalCoverCount(
        in entries: [SableLibraryDownloadedCoverManifestEntry],
        request: SableLibraryCoverDownloadRequest,
        language: String
    ) -> Int {
        let normalizedLanguage = SableLibraryCoverDownloadPlanner.normalizedLanguage(language)
        return request.localBooks.filter { localBook in
            let entry = entries.first {
                $0.bookFile.caseInsensitiveCompare(localBook.fileName) == .orderedSame
            } ?? entries.first {
                localBook.volumeNumber != nil && $0.volume == localBook.volumeNumber
            }
            return entry?.covers.contains {
                $0.role == .normal
                    && SableLibraryCoverDownloadPlanner.normalizedLanguage($0.language)
                        == normalizedLanguage
                    && SableLibraryCoverDownloadPlanner.coverDimensionsAreArchiveUsable(
                        width: $0.width ?? 0,
                        height: $0.height ?? 0
                    )
            } != true
        }.count
    }

    private func manifestCoverEvidencePriority(
        _ cover: SableLibraryDownloadedCoverManifestCover,
        bookFile: String,
        volume: Double?
    ) -> Int {
        var priority = 0
        if cover.providerTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            priority += 1
        }
        if cover.providerSeriesID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            priority += 1
        }
        if cover.providerItemID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            priority += 2
        }
        if cover.providerMediaType?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            priority += 1
        }
        if let providerVolume = cover.providerVolume,
           let volume,
           SableLibraryCoverDownloadPlanner.providerVolume(
            providerVolume,
            providerTitle: cover.providerTitle ?? cover.editionNote,
            localTitle: bookFile,
            source: SableLibraryCoverSource.allCases.first {
                $0.displayName == cover.source || $0.rawValue == cover.source
            },
            matches: volume
           ) {
            priority += 3
        }
        return priority
    }

    private func occurrence(
        _ lhs: CoverManifestOccurrence,
        isPreferredOver rhs: CoverManifestOccurrence
    ) -> Bool {
        let lhsRank = [
            lhs.identityPriority,
            lhs.rolePriority,
            lhs.pixels,
            lhs.providerPriority,
            lhs.statusPriority,
            -lhs.entryIndex,
            -lhs.coverIndex
        ]
        let rhsRank = [
            rhs.identityPriority,
            rhs.rolePriority,
            rhs.pixels,
            rhs.providerPriority,
            rhs.statusPriority,
            -rhs.entryIndex,
            -rhs.coverIndex
        ]
        return rhsRank.lexicographicallyPrecedes(lhsRank)
    }

    private func coverProviderPriority(_ source: String) -> Int {
        switch source.lowercased() {
        case let value where value.contains("booklive") || value.contains("bookwalker"):
            30
        case let value where value.contains("amazon"):
            20
        case let value where value.contains("mangabaka"):
            10
        default:
            0
        }
    }

    private func coverFingerprint(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private struct ProviderWriteResult: Sendable {
        var coversByBookIndex: [Int: [SableLibraryDownloadedCoverManifestCover]]
        var downloadedCount: Int
        var skipped: [String]
        var normalCoverBookIndexes: Set<Int>
    }

    private func bigBookCovers(
        request: SableLibraryCoverDownloadRequest,
        provider: SableLibraryBigBookCoversProvider,
        source: SableLibraryCoverSource,
        language: String,
        neededBookIndexes: Set<Int>,
        folder: URL,
        root: URL,
        fingerprintLedger: CoverFingerprintLedger,
        fileFingerprintIndex: CoverFileFingerprintIndex,
        normalCoverUpgradeBaselines: [Int: SableLibraryDownloadedCoverManifestCover]
    ) async throws -> ProviderWriteResult {
        var skipped: [String] = []
        var coversByBookIndex: [Int: [SableLibraryDownloadedCoverManifestCover]] = [:]
        var downloadedCount = 0
        var normalCoverBookIndexes = Set<Int>()

        if let manualMatch = request.manualSeriesMatch(for: source),
           manualMatch.provider == provider {
            let declaredMediaType = manualMatch.bookType ?? manualMatch.mediaType
            if let declaredMediaType,
               !SableLibraryCoverDownloadPlanner.providerMediaTypeIsCompatible(
                declaredMediaType,
                isCompatibleWith: request.mediaType
               ) {
                skipped.append(
                    "\(source.displayName): the manually chosen series is \(declaredMediaType), not \(request.mediaType ?? "the requested media type")."
                )
            } else {
                let books: [SableLibraryBigBookCoversBookCandidate]
                if source == .bookLiveJP,
                   manualMatch.itemType.caseInsensitiveCompare("seriesGroup") == .orderedSame {
                    books = try await SableLibraryBookLiveSeriesGroupClient().books(
                        groupID: manualMatch.providerID,
                        expectedMediaType: request.mediaType
                    )
                } else {
                    books = try await bbcClient.books(
                        itemID: manualMatch.providerID,
                        itemType: manualMatch.itemType,
                        provider: provider
                    )
                }
                var selectedBooks = SableLibraryCoverDownloadPlanner.booksFromExactManualSeries(
                    books,
                    match: manualMatch,
                    source: source
                )
                if source == .bookLiveJP,
                   manualMatch.itemType.caseInsensitiveCompare("seriesGroup") == .orderedSame {
                    selectedBooks = await expandedBookLiveGroupBooksIfNeeded(
                        selectedBooks,
                        match: manualMatch,
                        request: request
                    )
                    selectedBooks = SableLibraryCoverDownloadPlanner
                        .booksFromExactManualSeries(
                            selectedBooks,
                            match: manualMatch,
                            source: source
                        )
                }
                let storefrontMediaType: String?
                let hasEmbeddedStorefrontTypeProof =
                    SableLibraryCoverDownloadPlanner
                        .manualSeriesHasEmbeddedStorefrontTypeProof(manualMatch)
                if hasEmbeddedStorefrontTypeProof {
                    // The dedicated group parser accepted each row only after
                    // reading BookLive's visible ラノベ/マンガ category.
                    // Opening representative product pages again adds no new
                    // evidence and is especially costly for long series.
                    storefrontMediaType = declaredMediaType
                        ?? selectedBooks.compactMap(\.bookType).first
                } else {
                    storefrontMediaType = await storefrontMediaTypeIfNeeded(
                        declaredSeriesType: manualMatch.bookType ?? manualMatch.mediaType,
                        books: selectedBooks,
                        urls: selectedBooks.map(\.url) + [manualMatch.url],
                        source: source
                    )
                }
                let effectiveProviderMediaType =
                    SableLibraryCoverDownloadPlanner.effectiveProviderMediaType(
                        declaredSeriesType: declaredMediaType,
                        storefrontMediaType: storefrontMediaType,
                        bookTypes: selectedBooks.map(\.bookType)
                    )
                if !selectedBooks.isEmpty,
                   (hasEmbeddedStorefrontTypeProof || storefrontMediaType != nil),
                   providerBooksLookCompatibleWithLocalMedia(
                    selectedBooks,
                    seriesTitle: manualMatch.title,
                    seriesBookType: effectiveProviderMediaType,
                    mediaType: request.mediaType
                   ) {
                    let candidates = SableLibraryProviderCandidateParser.bigBookCoversCandidates(
                        from: selectedBooks,
                        source: source,
                        language: language,
                        mediaType: effectiveProviderMediaType
                    )
                    let allMatches = SableLibraryCoverDownloadPlanner.matchedProviderCovers(
                        candidates: candidates,
                        source: source,
                        language: language,
                        localBooks: request.localBooks,
                        includeSpecials: request.includeSpecials
                    )
                    let matched = SableLibraryCoverDownloadPlanner.covers(
                        allMatches,
                        forBookIndexes: neededBookIndexes
                    )
                    let result = try await writeMatchedCovers(
                        matched,
                        request: request,
                        folder: folder,
                        root: root,
                        language: language,
                        source: source,
                        fingerprintLedger: fingerprintLedger,
                        fileFingerprintIndex: fileFingerprintIndex,
                        normalCoverUpgradeBaselines: normalCoverUpgradeBaselines
                    )
                    merge(result.coversByBookIndex, into: &coversByBookIndex)
                    skipped.append(contentsOf: result.skipped)
                    downloadedCount += result.downloadedCount
                    normalCoverBookIndexes.formUnion(result.normalCoverBookIndexes)
                } else {
                    skipped.append(
                        "\(source.displayName): the manually chosen series \(manualMatch.title) returned no store-verified compatible book rows."
                    )
                }
            }
        }

        guard SableLibraryCoverDownloadPlanner.shouldRunAutomaticProviderSearch(
            source: source,
            provider: provider,
            request: request
        ) else {
            return ProviderWriteResult(
                coversByBookIndex: coversByBookIndex,
                downloadedCount: downloadedCount,
                skipped: skipped,
                normalCoverBookIndexes: normalCoverBookIndexes
            )
        }

        let queries = SableLibraryCoverDownloadPlanner.orderedProviderQueries(
            titles: request.queryTitles,
            isbn13: request.isbn13(for: language),
            language: language,
            provider: provider
        )

        for query in queries {
            let pendingBookIndexes = neededBookIndexes.subtracting(normalCoverBookIndexes)
            guard !pendingBookIndexes.isEmpty else { break }
            let seriesRows: [SableLibraryBigBookCoversSeriesCandidate]
            do {
                seriesRows = try await bbcClient.search(query: query.value, provider: provider)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                skipped.append(
                    "\(source.displayName): \(query.value) could not be checked (\(error.localizedDescription))."
                )
                continue
            }
            let rankedSeries = query.isExactISBN
                ? SableLibraryCoverDownloadPlanner.exactIdentifierCandidates(seriesRows)
                : SableLibraryCoverDownloadPlanner.rankedSeriesCandidates(
                    for: query.value,
                    requestedSeriesTitle: request.seriesTitle,
                    in: seriesRows,
                    mediaType: request.mediaType
                )
            guard !rankedSeries.isEmpty else {
                skipped.append("\(source.displayName): no confident series result for \(query.value).")
                continue
            }

            var selectedBooks: [SableLibraryBigBookCoversBookCandidate] = []
            var selectedSeries: SableLibraryBigBookCoversSeriesCandidate?
            var selectedProviderMediaType: String?
            let inspectionLimit =
                SableLibraryCoverDownloadPlanner.automaticSeriesInspectionLimit(for: source)
            for series in rankedSeries.prefix(inspectionLimit) {
                let books: [SableLibraryBigBookCoversBookCandidate]
                do {
                    books = try await bbcClient.books(
                        itemID: series.id,
                        itemType: series.type ?? "series",
                        provider: provider
                    )
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    skipped.append(
                        "\(source.displayName): \(series.title) could not be opened (\(error.localizedDescription))."
                    )
                    continue
                }
                let seriesBooks = books.filter {
                    let matchesSelectedSeries = SableLibraryCoverDownloadPlanner.providerTitle(
                        $0.title,
                        belongsTo: series.title
                    )
                    let matchesRequest = providerTitleBelongsToRequest(
                        $0.title,
                        request: request
                    )
                    return matchesSelectedSeries && matchesRequest
                }
                var effectiveBooks = seriesBooks
                var effectiveSeriesTitle = series.title
                var effectiveDeclaredMediaType = series.bookType
                var hasBookLiveSeriesGroupTypeProof = false

                if source == .bookLiveJP {
                    let groupMatches = await SableLibraryBookLiveSeriesGroupClient().manualMatches(
                        from: [series],
                        expectedMediaType: request.mediaType
                    )
                    if let group = groupMatches.first(where: {
                        $0.itemType.caseInsensitiveCompare("seriesGroup") == .orderedSame
                    }),
                       let groupBooks = try? await SableLibraryBookLiveSeriesGroupClient().books(
                        groupID: group.providerID,
                        expectedMediaType: request.mediaType
                       ),
                       let preferredGroupBooks = SableLibraryCoverDownloadPlanner
                        .preferredAutomaticBookLiveSeriesGroupBooks(
                            currentBooks: effectiveBooks,
                            groupBooks: groupBooks,
                            groupMatch: group
                        ) {
                        effectiveBooks = preferredGroupBooks
                        effectiveSeriesTitle = group.title
                        effectiveDeclaredMediaType = group.bookType ?? group.mediaType
                        hasBookLiveSeriesGroupTypeProof = true
                        skipped.append(
                            "\(source.displayName): verified \(series.title) through series group \(group.providerID)."
                        )
                    }
                }

                guard !effectiveBooks.isEmpty else {
                    skipped.append(
                        "\(source.displayName): skipped sibling or parent edition \(series.title)."
                    )
                    continue
                }
                let storefrontMediaType: String?
                if hasBookLiveSeriesGroupTypeProof {
                    storefrontMediaType = effectiveDeclaredMediaType
                        ?? effectiveBooks.compactMap(\.bookType).first
                } else {
                    storefrontMediaType = await storefrontMediaTypeIfNeeded(
                        declaredSeriesType: effectiveDeclaredMediaType,
                        books: effectiveBooks,
                        urls: effectiveBooks.map(\.url) + [series.url],
                        source: source
                    )
                }
                guard hasBookLiveSeriesGroupTypeProof || storefrontMediaType != nil else {
                    skipped.append(
                        "\(source.displayName): the store page did not prove whether \(series.title) is manga or a novel."
                    )
                    continue
                }
                let effectiveProviderMediaType =
                    SableLibraryCoverDownloadPlanner.effectiveProviderMediaType(
                    declaredSeriesType: effectiveDeclaredMediaType,
                    storefrontMediaType: storefrontMediaType,
                    bookTypes: effectiveBooks.map(\.bookType)
                    )
                if providerBooksLookCompatibleWithLocalMedia(
                    effectiveBooks,
                    seriesTitle: effectiveSeriesTitle,
                    seriesBookType: effectiveProviderMediaType,
                    mediaType: request.mediaType
                ) {
                    selectedBooks = effectiveBooks
                    selectedSeries = series
                    selectedProviderMediaType = effectiveProviderMediaType
                    break
                }
                skipped.append("\(source.displayName): skipped likely wrong medium for \(series.title).")
            }
            guard selectedSeries != nil, !selectedBooks.isEmpty else {
                skipped.append("\(source.displayName): no compatible book rows found for \(query.value).")
                continue
            }
            let candidates = SableLibraryProviderCandidateParser.bigBookCoversCandidates(
                from: selectedBooks,
                source: source,
                language: language,
                mediaType: selectedProviderMediaType
            )
            let allMatches = SableLibraryCoverDownloadPlanner.matchedProviderCovers(
                candidates: candidates,
                source: source,
                language: language,
                localBooks: request.localBooks,
                includeSpecials: request.includeSpecials
            )
            let matched = SableLibraryCoverDownloadPlanner.covers(
                allMatches,
                forBookIndexes: pendingBookIndexes
            )
            let result = try await writeMatchedCovers(
                matched,
                request: request,
                folder: folder,
                root: root,
                language: language,
                source: source,
                fingerprintLedger: fingerprintLedger,
                fileFingerprintIndex: fileFingerprintIndex,
                normalCoverUpgradeBaselines: normalCoverUpgradeBaselines
            )
            merge(result.coversByBookIndex, into: &coversByBookIndex)
            skipped.append(contentsOf: result.skipped)
            downloadedCount += result.downloadedCount
            normalCoverBookIndexes.formUnion(result.normalCoverBookIndexes)
        }

        if source == .amazon || source == .amazonJP {
            let pendingBookIndexes = neededBookIndexes.subtracting(normalCoverBookIndexes)
            if !pendingBookIndexes.isEmpty {
                let directResult = try await amazonDirectBookCovers(
                    request: request,
                    provider: provider,
                    source: source,
                    language: language,
                    neededBookIndexes: pendingBookIndexes,
                    folder: folder,
                    root: root,
                    fingerprintLedger: fingerprintLedger,
                    fileFingerprintIndex: fileFingerprintIndex,
                    normalCoverUpgradeBaselines: normalCoverUpgradeBaselines
                )
                merge(directResult.coversByBookIndex, into: &coversByBookIndex)
                skipped.append(contentsOf: directResult.skipped)
                downloadedCount += directResult.downloadedCount
                normalCoverBookIndexes.formUnion(directResult.normalCoverBookIndexes)
            }
        }

        return ProviderWriteResult(
            coversByBookIndex: coversByBookIndex,
            downloadedCount: downloadedCount,
            skipped: skipped,
            normalCoverBookIndexes: normalCoverBookIndexes
        )
    }

    private func amazonDirectBookCovers(
        request: SableLibraryCoverDownloadRequest,
        provider: SableLibraryBigBookCoversProvider,
        source: SableLibraryCoverSource,
        language: String,
        neededBookIndexes: Set<Int>,
        folder: URL,
        root: URL,
        fingerprintLedger: CoverFingerprintLedger,
        fileFingerprintIndex: CoverFileFingerprintIndex,
        normalCoverUpgradeBaselines: [Int: SableLibraryDownloadedCoverManifestCover]
    ) async throws -> ProviderWriteResult {
        var result = ProviderWriteResult(
            coversByBookIndex: [:],
            downloadedCount: 0,
            skipped: [],
            normalCoverBookIndexes: []
        )

        for bookIndex in neededBookIndexes.sorted() {
            guard request.localBooks.indices.contains(bookIndex - 1),
                  let localVolume = request.localBooks[bookIndex - 1].volumeNumber else {
                continue
            }
            let volumeText = localVolume.rounded() == localVolume
                ? String(Int(localVolume))
                : String(localVolume)
            let querySuffix = language == "jp"
                ? "第\(volumeText)巻 Kindle"
                : "Book \(volumeText) Kindle"
            let queries = SableLibraryCoverDownloadPlanner.orderedQueries(
                request.queryTitles,
                language: language
            )
            .prefix(2)
            .map { "\($0) \(querySuffix)" }

            var accepted = false
            for query in queries where !accepted {
                let rows: [SableLibraryBigBookCoversSeriesCandidate]
                do {
                    rows = try await bbcClient.search(query: query, provider: provider)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    result.skipped.append(
                        "\(source.displayName): direct Kindle query \(query) failed (\(error.localizedDescription))."
                    )
                    continue
                }
                let localBookTitle = request.localBooks[bookIndex - 1].fileName
                let trustedSeriesTitles = SableLibraryCoverDownloadPlanner.uniqueNonEmpty(
                    [request.seriesTitle]
                        + request.queryTitles
                        + request.manualSeriesMatches.map(\.title)
                )
                let directRows = rows.filter {
                    $0.type?.caseInsensitiveCompare("book") == .orderedSame
                        && SableLibraryCoverDownloadPlanner
                            .providerDirectBookTitleIsCompatible(
                                $0.title,
                                requestedSeriesTitles: trustedSeriesTitles,
                                localBookTitle: localBookTitle,
                                localVolume: localVolume
                            )
                }

                for row in directRows.prefix(8) {
                    let books: [SableLibraryBigBookCoversBookCandidate]
                    do {
                        books = try await bbcClient.books(
                            itemID: row.id,
                            itemType: "book",
                            provider: provider
                        )
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        result.skipped.append(
                            "\(source.displayName): direct Kindle item \(row.id) could not be opened (\(error.localizedDescription))."
                        )
                        continue
                    }
                    let matchingBooks = books.filter {
                        SableLibraryCoverDownloadPlanner
                            .providerDirectBookTitleIsCompatible(
                                $0.title,
                                requestedSeriesTitles: trustedSeriesTitles,
                                localBookTitle: localBookTitle,
                                localVolume: localVolume
                            )
                    }
                    guard !matchingBooks.isEmpty else { continue }

                    let storefrontMediaType = await storefrontMediaTypeIfNeeded(
                        declaredSeriesType: row.bookType,
                        books: matchingBooks,
                        urls: matchingBooks.map(\.url) + [row.url],
                        source: source
                    )
                    guard storefrontMediaType != nil else {
                        result.skipped.append(
                            "\(source.displayName): the store page did not prove whether \(row.title) is manga, a novel, or an audiobook."
                        )
                        continue
                    }
                    let effectiveProviderMediaType =
                        SableLibraryCoverDownloadPlanner.effectiveProviderMediaType(
                            declaredSeriesType: row.bookType,
                            storefrontMediaType: storefrontMediaType,
                            bookTypes: matchingBooks.map(\.bookType)
                        )
                    guard SableLibraryCoverDownloadPlanner.providerMediaTypeIsCompatible(
                        effectiveProviderMediaType,
                        isCompatibleWith: request.mediaType
                    ) else {
                        continue
                    }

                    let candidates = SableLibraryProviderCandidateParser.bigBookCoversCandidates(
                        from: matchingBooks,
                        source: source,
                        language: language,
                        mediaType: effectiveProviderMediaType
                    )
                    let allMatches = SableLibraryCoverDownloadPlanner.matchedProviderCovers(
                        candidates: candidates,
                        source: source,
                        language: language,
                        localBooks: request.localBooks,
                        includeSpecials: request.includeSpecials
                    )
                    let matched = SableLibraryCoverDownloadPlanner.covers(
                        allMatches,
                        forBookIndexes: [bookIndex]
                    )
                    let writeResult = try await writeMatchedCovers(
                        matched,
                        request: request,
                        folder: folder,
                        root: root,
                        language: language,
                        source: source,
                        fingerprintLedger: fingerprintLedger,
                        fileFingerprintIndex: fileFingerprintIndex,
                        normalCoverUpgradeBaselines: normalCoverUpgradeBaselines
                    )
                    merge(writeResult.coversByBookIndex, into: &result.coversByBookIndex)
                    result.skipped.append(contentsOf: writeResult.skipped)
                    result.downloadedCount += writeResult.downloadedCount
                    result.normalCoverBookIndexes.formUnion(writeResult.normalCoverBookIndexes)
                    accepted = writeResult.normalCoverBookIndexes.contains(bookIndex)
                    if accepted {
                        result.skipped.append(
                            "\(source.displayName): used a verified direct Kindle result for volume \(volumeText)."
                        )
                        break
                    }
                }
            }
        }

        return result
    }

    private func mangaBakaCoverCandidates(
        request: SableLibraryCoverDownloadRequest
    ) async throws -> [SableLibraryProviderCoverCandidate] {
        let hasSeriesBundle = request.mangaBakaSeriesBundle?.members.isEmpty == false
        if request.manualSeriesMatch(for: .mangaBaka) != nil
            || !hasSeriesBundle {
            guard let seriesID = request.mangaBakaSeriesIDs.first else { return [] }
            return try await mangaBakaCoverCandidates(
                seriesID: seriesID,
                request: request
            )
        }

        guard let bundle = request.mangaBakaSeriesBundle else { return [] }
        var bundledCandidates: [SableLibraryProviderCoverCandidate] = []
        var failures: [String] = []

        for member in bundle.members {
            try Task.checkCancellation()
            do {
                let candidates = try await mangaBakaCoverCandidates(
                    seriesID: String(member.seriesID),
                    request: request
                )
                bundledCandidates.append(contentsOf: candidates.compactMap {
                    remapMangaBakaCandidate($0, with: member)
                })
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failures.append("MB \(member.seriesID): \(error.localizedDescription)")
            }
        }

        if bundledCandidates.isEmpty, !failures.isEmpty {
            throw SableLibraryCoverDownloadError.noTrustedCovers(
                failures.joined(separator: " / ")
            )
        }
        return bundledCandidates
    }

    private func remapMangaBakaCandidate(
        _ candidate: SableLibraryProviderCoverCandidate,
        with member: SableLibraryMangaBakaSeriesBundleMember
    ) -> SableLibraryProviderCoverCandidate? {
        let sourceVolume = candidate.volumeNumber
            ?? candidate.volumeIndex.flatMap(Double.init)
        guard let sourceVolume,
              let libraryVolume = member.libraryVolume(for: sourceVolume) else {
            return nil
        }

        var candidate = candidate
        candidate.volumeNumber = libraryVolume
        candidate.volumeIndex = libraryVolume.rounded() == libraryVolume
            ? String(Int(libraryVolume))
            : String(libraryVolume)
        candidate.providerSeriesID = String(member.seriesID)
        return candidate
    }

    private func mangaBakaCoverCandidates(
        seriesID: String,
        request: SableLibraryCoverDownloadRequest
    ) async throws -> [SableLibraryProviderCoverCandidate] {
        let identity = try await verifiedMangaBakaSeriesIdentity(
            seriesID: seriesID,
            request: request
        )
        let candidates: [SableLibraryProviderCoverCandidate]
        do {
            let apiCandidates = try await mangaBakaAPICoverCandidates(
                seriesID: seriesID,
                localBookCount: request.localBooks.count
            )
            if !apiCandidates.isEmpty {
                candidates = apiCandidates
                return candidates.map {
                    mangaBakaCandidate($0, identity: identity, seriesID: seriesID)
                }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // The public covers page remains a compatibility fallback if the API is unavailable.
        }

        guard let url = URL(string: "https://mangabaka.org/\(seriesID)/covers") else { return [] }
        let (data, response) = try await Self.storefrontSession.data(from: url)
        if let http = response as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode) {
            return []
        }
        guard data.count <= 8 * 1_024 * 1_024 else {
            throw SableLibraryCoverDownloadError.invalidProviderResponse(
                "MangaBaka cover page is larger than 8 MB"
            )
        }
        guard let html = String(data: data, encoding: .utf8) else { return [] }
        candidates = SableLibraryProviderCandidateParser
            .mangaBakaCoverCandidates(fromCoversPageHTML: html, seriesID: seriesID)
        let identifiedCandidates = candidates.map {
            mangaBakaCandidate($0, identity: identity, seriesID: seriesID)
        }
        guard !identifiedCandidates.isEmpty else {
            let thumbnailDetail: String
            if let width = identity.thumbnailWidth,
               let height = identity.thumbnailHeight {
                if SableLibraryCoverDownloadPlanner.coverDimensionsAreArchiveUsable(
                    width: width,
                    height: height
                ) {
                    thumbnailDetail = "Its only image is a \(width) x \(height) series thumbnail, not a volume cover."
                } else {
                    thumbnailDetail = "Its only image is a \(width) x \(height) series thumbnail, below the 500 x 700 archive floor."
                }
            } else {
                thumbnailDetail = "Its only image is a series thumbnail, not a volume cover."
            }
            throw SableLibraryCoverDownloadError.noTrustedCovers(
                "The exact MangaBaka series \(identity.title) is the correct \(identity.mediaType), "
                    + "but MangaBaka has no volume-cover records. \(thumbnailDetail)"
            )
        }
        return identifiedCandidates
    }

    private struct MangaBakaSeriesIdentity {
        var title: String
        var mediaType: String
        var thumbnailWidth: Int?
        var thumbnailHeight: Int?
    }

    private func verifiedMangaBakaSeriesIdentity(
        seriesID: String,
        request: SableLibraryCoverDownloadRequest
    ) async throws -> MangaBakaSeriesIdentity {
        guard let url = URL(string: "https://api.mangabaka.org/v1/series/\(seriesID)") else {
            throw SableLibraryCoverDownloadError.invalidProviderResponse(
                "MangaBaka series ID is not a valid URL component"
            )
        }
        let (data, response) = try await Self.storefrontSession.data(from: url)
        if let http = response as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode) {
            throw SableLibraryCoverDownloadError.invalidProviderResponse(
                "MangaBaka series returned HTTP \(http.statusCode)"
            )
        }
        guard data.count <= 8 * 1_024 * 1_024 else {
            throw SableLibraryCoverDownloadError.invalidProviderResponse(
                "MangaBaka series response is larger than 8 MB"
            )
        }
        return try mangaBakaSeriesIdentity(
            from: data,
            seriesID: seriesID,
            request: request
        )
    }

    private func mangaBakaSeriesIdentity(
        from data: Data,
        seriesID: String,
        request: SableLibraryCoverDownloadRequest
    ) throws -> MangaBakaSeriesIdentity {
        try autoreleasepool {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let series = object["data"] as? [String: Any],
                  let title = series["title"] as? String,
                  let mediaType = series["type"] as? String else {
                throw SableLibraryCoverDownloadError.invalidProviderResponse(
                    "MangaBaka series identity was incomplete"
                )
            }

            var titles = [title]
            titles.append(contentsOf: ["native_title", "romanized_title"].compactMap {
                series[$0] as? String
            })
            if let localizedTitles = series["titles"] as? [[String: Any]] {
                titles.append(contentsOf: localizedTitles.compactMap { $0["title"] as? String })
            }
            let isManuallyChosen = request.trustsMangaBakaSeriesID(seriesID)
            let isCompatible = if isManuallyChosen {
                SableLibraryCoverDownloadPlanner.providerMediaTypeIsCompatible(
                    mediaType,
                    isCompatibleWith: request.mediaType
                )
            } else {
                SableLibraryCoverDownloadPlanner.mangaBakaSeriesIdentityIsCompatible(
                    titles: titles,
                    providerMediaType: mediaType,
                    requestedSeriesTitle: request.seriesTitle,
                    requestedMediaType: request.mediaType
                )
            }
            guard isCompatible else {
                throw SableLibraryCoverDownloadError.noTrustedCovers(
                    "MangaBaka ID \(seriesID) is \(title) (\(mediaType)), not the requested \(request.seriesTitle) (\(request.mediaType ?? "unknown type"))."
                )
            }
            let rawCover = (series["cover"] as? [String: Any])?["raw"] as? [String: Any]
            return MangaBakaSeriesIdentity(
                title: title,
                mediaType: mediaType,
                thumbnailWidth: (rawCover?["width"] as? NSNumber)?.intValue,
                thumbnailHeight: (rawCover?["height"] as? NSNumber)?.intValue
            )
        }
    }

    private func mangaBakaCandidate(
        _ candidate: SableLibraryProviderCoverCandidate,
        identity: MangaBakaSeriesIdentity,
        seriesID: String
    ) -> SableLibraryProviderCoverCandidate {
        var candidate = candidate
        candidate.title = identity.title
        candidate.mediaType = candidate.mediaTypeForSeriesIdentity(identity.mediaType)
        candidate.providerSeriesID = candidate.providerSeriesID ?? seriesID
        if candidate.storeURLs.isEmpty {
            candidate.storeURLs = ["https://mangabaka.org/\(seriesID)/covers"]
        }
        return candidate
    }

    private func mangaBakaAPICoverCandidates(
        seriesID: String,
        localBookCount: Int
    ) async throws -> [SableLibraryProviderCoverCandidate] {
        guard let firstURL = URL(string: "https://api.mangabaka.org/v1/series/\(seriesID)/images?page=1") else {
            return []
        }

        var nextURL: URL? = firstURL
        var visitedURLs = Set<String>()
        var candidates: [SableLibraryProviderCoverCandidate] = []
        let usefulCandidateTarget = max(24, min(600, max(1, localBookCount) * 4))
        let maximumPages = min(25, max(4, Int(ceil(Double(usefulCandidateTarget) / 24.0)) + 2))

        // The bound prevents a malformed provider response from creating an endless crawl.
        for _ in 0..<maximumPages {
            try Task.checkCancellation()
            guard let pageURL = nextURL,
                  visitedURLs.insert(pageURL.absoluteString).inserted else {
                break
            }
            let (data, response) = try await Self.storefrontSession.data(from: pageURL)
            if let http = response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) {
                throw SableLibraryCoverDownloadError.invalidProviderResponse(
                    "MangaBaka images returned HTTP \(http.statusCode)"
                )
            }
            guard data.count <= 8 * 1_024 * 1_024 else {
                throw SableLibraryCoverDownloadError.invalidProviderResponse(
                    "MangaBaka image page is larger than 8 MB"
                )
            }
            let page = try SableLibraryProviderCandidateParser.mangaBakaCoverPage(
                from: data,
                seriesID: seriesID
            )
            candidates.append(contentsOf: page.candidates)
            nextURL = page.nextPageURL
            if candidates.count >= usefulCandidateTarget {
                break
            }
            if nextURL != nil {
                try await Task.sleep(for: .seconds(1))
            }
        }

        var seen = Set<String>()
        return candidates.filter { candidate in
            let key = candidate.providerItemID ?? [
                candidate.language ?? "",
                candidate.volumeIndex ?? "",
                candidate.role.rawValue,
                candidate.imageURL
            ].joined(separator: "|")
            return seen.insert(key).inserted
        }
    }

    private func writeMatchedCovers(
        _ matched: [Int: [SableLibraryProviderCoverCandidate]],
        request: SableLibraryCoverDownloadRequest,
        folder: URL,
        root: URL,
        language: String,
        source: SableLibraryCoverSource,
        fingerprintLedger: CoverFingerprintLedger,
        fileFingerprintIndex: CoverFileFingerprintIndex,
        normalCoverUpgradeBaselines: [Int: SableLibraryDownloadedCoverManifestCover] = [:]
    ) async throws -> ProviderWriteResult {
        var coversByBookIndex: [Int: [SableLibraryDownloadedCoverManifestCover]] = [:]
        var skipped: [String] = []
        var downloadedCount = 0
        var normalCoverBookIndexes = Set<Int>()
        let rootPath = canonicalCoverPath(root)

        for index in matched.keys.sorted() {
            let candidates = matched[index] ?? []
            var roleCounts: [SableLibraryProviderCoverRole: Int] = [:]
            for candidate in candidates {
                let roleIndex = (roleCounts[candidate.role] ?? 0) + 1
                roleCounts[candidate.role] = roleIndex
                do {
                    let download = try await downloadBestImage(for: candidate, source: source)
                    if candidate.role == .normal,
                       source.isStoreSource,
                       let baseline = normalCoverUpgradeBaselines[index],
                       let baselineWidth = baseline.width,
                       let baselineHeight = baseline.height,
                       !SableLibraryCoverDownloadPlanner.coverDimensionsAreStrictQualityUpgrade(
                        width: download.dimensions.width,
                        height: download.dimensions.height,
                        over: baselineWidth,
                        baselineHeight: baselineHeight
                       ) {
                        skipped.append(
                            "\(source.displayName): kept the MangaBaka or earlier store baseline for "
                                + "\(request.localBooks[index - 1].fileName); "
                                + "\(download.dimensions.width) x \(download.dimensions.height) was not a quality upgrade "
                                + "over \(baselineWidth) x \(baselineHeight)."
                        )
                        continue
                    }
                    let fingerprint = SHA256.hash(data: download.data)
                        .map { String(format: "%02x", $0) }
                        .joined()
                    let visualSignature = CoverVisualSignature.make(from: download.data)
                    let visuallyEquivalentPaths = visualSignature.map {
                        fileFingerprintIndex.visuallyEquivalentPaths(to: $0)
                    } ?? []
                    let existingAssignment = fingerprintLedger.assignment(for: fingerprint)
                        ?? fingerprintLedger.assignment(forAnyPath: visuallyEquivalentPaths)
                    let canReuseAcrossLanguages = existingAssignment.map {
                        $0.bookIndex == index
                            && $0.role == .normal
                            && candidate.role == .normal
                            && $0.language != language
                    } ?? false
                    let replacesSameNormalSlot = existingAssignment.map {
                        $0.bookIndex == index
                            && $0.role == .normal
                            && candidate.role == .normal
                            && $0.language == language
                    } ?? false
                    if let existingAssignment,
                       !canReuseAcrossLanguages,
                       !replacesSameNormalSlot {
                        skipped.append(
                            "\(source.displayName): skipped visually equivalent artwork already assigned to "
                                + "volume slot \(existingAssignment.bookIndex), \(existingAssignment.language), "
                                + "\(existingAssignment.role.rawValue)."
                        )
                        continue
                    }
                    let extensionName = imageExtension(download.contentType, url: download.url)
                    let relativePath = relativeCoverPath(
                        request: request,
                        localBook: request.localBooks[index - 1],
                        language: language,
                        source: source,
                        role: candidate.role,
                        roleIndex: roleIndex,
                        extensionName: extensionName
                    )
                    let existingFingerprintPaths = fileFingerprintIndex.paths(for: fingerprint)
                    let equivalentPaths = Array(
                        Set(existingFingerprintPaths + visuallyEquivalentPaths)
                    )
                    let reusableNormalPath = candidate.role == .normal
                        ? equivalentPaths.filter {
                            $0.hasPrefix(coverSlotPrefix(
                                localBook: request.localBooks[index - 1],
                                language: language
                            )) && $0.contains(" - Cover \(language == "jp" ? "JP" : language.uppercased()) [")
                        }.max {
                            let lhsPixels = fileFingerprintIndex.fileInfo(for: $0)?.pixels ?? 0
                            let rhsPixels = fileFingerprintIndex.fileInfo(for: $1)?.pixels ?? 0
                            return lhsPixels < rhsPixels
                        }.flatMap { path in
                            let existingPixels = fileFingerprintIndex.fileInfo(for: path)?.pixels ?? 0
                            let downloadedPixels = download.dimensions.width * download.dimensions.height
                            return existingPixels >= downloadedPixels ? path : nil
                        }
                        : nil
                    let destination: (relativePath: String, url: URL, shouldWrite: Bool)
                    if let reusableNormalPath {
                        destination = (
                            reusableNormalPath,
                            folder.appendingPathComponent(reusableNormalPath),
                            false
                        )
                    } else {
                        destination = try collisionSafeCoverDestination(
                            folder: folder,
                            rootPath: rootPath,
                            relativePath: relativePath,
                            data: download.data
                        )
                    }
                    var reusedExistingBytes = false
                    if destination.shouldWrite {
                        try FileManager.default.createDirectory(
                            at: destination.url.deletingLastPathComponent(),
                            withIntermediateDirectories: true
                        )
                        if canReuseAcrossLanguages,
                           let existingAssignment {
                            let existingURL = folder.appendingPathComponent(
                                existingAssignment.relativePath
                            )
                            do {
                                try FileManager.default.linkItem(
                                    at: existingURL,
                                    to: destination.url
                                )
                                reusedExistingBytes = true
                            } catch {
                                try download.data.write(to: destination.url, options: .atomic)
                                downloadedCount += 1
                            }
                        } else {
                            try download.data.write(to: destination.url, options: .atomic)
                            downloadedCount += 1
                        }
                    }
                    let storedData = (try? Data(contentsOf: destination.url)) ?? download.data
                    let storedDimensions = imageDimensions(storedData) ?? download.dimensions
                    let storedFingerprint = SHA256.hash(data: storedData)
                        .map { String(format: "%02x", $0) }
                        .joined()
                    fileFingerprintIndex.record(
                        storedFingerprint,
                        relativePath: destination.relativePath,
                        data: storedData,
                        dimensions: storedDimensions
                    )
                    fingerprintLedger.record(
                        storedFingerprint,
                        bookIndex: index,
                        language: language,
                        role: candidate.role,
                        relativePath: destination.relativePath
                    )
                    let isBelowClinicQuality = candidate.role == .normal
                        && !SableLibraryCoverDownloadPlanner.coverDimensionsAreUsable(
                            width: storedDimensions.width,
                            height: storedDimensions.height
                        )
                    let manifestStatus: String
                    if isBelowClinicQuality {
                        manifestStatus = source.isStoreSource
                            ? "archived_below_clinic_quality_store_verified"
                            : "archived_below_clinic_quality"
                        skipped.append(
                            "\(source.displayName): archived \(storedDimensions.width) x \(storedDimensions.height) "
                                + "cover for \(request.localBooks[index - 1].fileName); Clinic will not use it for EPUB replacement."
                        )
                    } else if destination.shouldWrite && !reusedExistingBytes {
                        if candidate.role == .normal, source.isStoreSource {
                            manifestStatus = "selected_downloaded_store_verified"
                        } else {
                            manifestStatus = candidate.role == .normal
                                ? "selected_downloaded"
                                : "extra_downloaded"
                        }
                    } else {
                        manifestStatus = candidate.role == .normal && source.isStoreSource
                            ? "selected_reused_existing_store_verified"
                            : "selected_reused_existing"
                    }
                    let manifestCover = SableLibraryDownloadedCoverManifestCover(
                        language: language,
                        source: source.displayName,
                        role: candidate.role,
                        status: manifestStatus,
                        path: destination.relativePath,
                        width: storedDimensions.width,
                        height: storedDimensions.height,
                        bytes: storedData.count,
                        url: download.url,
                        providerURL: candidate.storeURLs.first,
                        editionNote: candidate.editionNote,
                        providerTitle: candidate.title,
                        providerSeriesID: candidate.providerSeriesID,
                        providerItemID: candidate.providerItemID,
                        providerVolume: candidate.volumeNumber
                            ?? candidate.volumeIndex.flatMap(Double.init),
                        providerMediaType: candidate.mediaType ?? candidate.providerType
                    )
                    coversByBookIndex[index, default: []].append(manifestCover)
                    // Library archives any trustworthy cover that clears the
                    // archive floor. Clinic independently enforces its higher
                    // replacement floor before touching an EPUB.
                    if candidate.role == .normal {
                        normalCoverBookIndexes.insert(index)
                    }
                } catch {
                    skipped.append("\(source.displayName): could not save \(candidate.title ?? candidate.imageURL): \(error.localizedDescription)")
                }
            }
        }

        return ProviderWriteResult(
            coversByBookIndex: coversByBookIndex,
            downloadedCount: downloadedCount,
            skipped: skipped,
            normalCoverBookIndexes: normalCoverBookIndexes
        )
    }

    private func coverSlotPrefix(
        localBook: SableLibraryCoverDownloadLocalBook,
        language: String
    ) -> String {
        let base = sanitizedFileStem((localBook.fileName as NSString).deletingPathExtension)
        return "_covers/\(language)/\(base) - "
    }

    private struct DownloadedCoverImage {
        var data: Data
        var contentType: String?
        var url: String
        var dimensions: (width: Int, height: Int)
    }

    private func downloadBestImage(
        for candidate: SableLibraryProviderCoverCandidate,
        source: SableLibraryCoverSource
    ) async throws -> DownloadedCoverImage {
        var urls: [String] = []
        if source == .amazon || source == .amazonJP {
            for storeURL in candidate.storeURLs {
                urls.append(contentsOf: await amazonHighResolutionImageURLs(from: storeURL))
            }
        }
        urls.append(candidate.imageURL)
        urls.append(contentsOf: candidate.fallbackImageURLs)

        var seen = Set<String>()
        var bestArchiveImage: DownloadedCoverImage?
        var bestSmallDimensions: (width: Int, height: Int)?
        for rawURL in urls where seen.insert(rawURL).inserted {
            do {
                let download = try await downloadImage(from: rawURL)
                guard let dimensions = imageDimensions(download.data) else { continue }
                if SableLibraryCoverDownloadPlanner.coverDimensionsAreUsable(
                    width: dimensions.width,
                    height: dimensions.height
                ) {
                    return DownloadedCoverImage(
                        data: download.data,
                        contentType: download.contentType,
                        url: rawURL,
                        dimensions: dimensions
                    )
                }
                if SableLibraryCoverDownloadPlanner.coverDimensionsAreArchiveUsable(
                    width: dimensions.width,
                    height: dimensions.height
                ) {
                    let archiveImage = DownloadedCoverImage(
                        data: download.data,
                        contentType: download.contentType,
                        url: rawURL,
                        dimensions: dimensions
                    )
                    if let currentBest = bestArchiveImage {
                        if dimensions.width * dimensions.height
                            > currentBest.dimensions.width * currentBest.dimensions.height {
                            bestArchiveImage = archiveImage
                        }
                    } else {
                        bestArchiveImage = archiveImage
                    }
                    continue
                }
                if let currentBest = bestSmallDimensions {
                    if dimensions.width * dimensions.height
                        > currentBest.width * currentBest.height {
                        bestSmallDimensions = dimensions
                    }
                } else {
                    bestSmallDimensions = dimensions
                }
            } catch {
                continue
            }
        }

        if let bestArchiveImage {
            return bestArchiveImage
        }
        if let bestSmallDimensions {
            throw SableLibraryCoverDownloadError.coverBelowMinimum(
                width: bestSmallDimensions.width,
                height: bestSmallDimensions.height
            )
        }
        throw SableLibraryCoverDownloadError.invalidProviderResponse("no usable image data was returned")
    }

    private func downloadImage(from rawURL: String) async throws -> (data: Data, contentType: String?) {
        guard let url = URL(string: rawURL) else {
            throw SableLibraryCoverDownloadError.invalidProviderResponse("bad cover URL")
        }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        let (data, response) = try await Self.imageSession.data(for: request)
        if let http = response as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode) {
            throw SableLibraryCoverDownloadError.invalidProviderResponse("HTTP \(http.statusCode)")
        }
        guard data.count <= 25 * 1024 * 1024 else {
            throw SableLibraryCoverDownloadError.invalidProviderResponse("image is larger than 25 MB")
        }
        return (data, (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type"))
    }

    private func amazonHighResolutionImageURLs(from rawStoreURL: String) async -> [String] {
        guard let url = URL(string: rawStoreURL),
              let host = url.host?.lowercased(),
              host.contains("amazon.") else {
            return []
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await Self.storefrontSession.data(for: request),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) != false,
              let html = String(data: data, encoding: .utf8),
              let regex = try? NSRegularExpression(pattern: #""hiRes"\s*:\s*"(https:[^"]+)""#) else {
            return []
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        var seen = Set<String>()
        return regex.matches(in: html, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let valueRange = Range(match.range(at: 1), in: html) else {
                return nil
            }
            let value = String(html[valueRange])
                .replacingOccurrences(of: #"\/"#, with: "/")
                .replacingOccurrences(of: #"\u0026"#, with: "&")
            return seen.insert(value).inserted ? value : nil
        }
    }

    private func collisionSafeCoverDestination(
        folder: URL,
        rootPath: String,
        relativePath: String,
        data: Data
    ) throws -> (relativePath: String, url: URL, shouldWrite: Bool) {
        let fileManager = FileManager.default
        let pathExtension = (relativePath as NSString).pathExtension
        let base = (relativePath as NSString).deletingPathExtension

        for index in 0..<1_000 {
            let candidateRelativePath: String
            if index == 0 {
                candidateRelativePath = relativePath
            } else if pathExtension.isEmpty {
                candidateRelativePath = "\(base) \(paddedIndex(index + 1))"
            } else {
                candidateRelativePath = "\(base) \(paddedIndex(index + 1)).\(pathExtension)"
            }

            let candidateURL = folder.appendingPathComponent(candidateRelativePath)
            let candidatePath = canonicalCoverPath(candidateURL)
            guard candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/") else {
                throw SableLibraryCoverDownloadError.unsafeCoverPath(candidatePath)
            }
            guard fileManager.fileExists(atPath: candidatePath) else {
                return (candidateRelativePath, candidateURL, true)
            }
            if (try? Data(contentsOf: candidateURL)) == data {
                return (candidateRelativePath, candidateURL, false)
            }
            if index == 0,
               let existingData = try? Data(contentsOf: candidateURL),
               let existingSignature = CoverVisualSignature.make(from: existingData),
               let incomingSignature = CoverVisualSignature.make(from: data),
               existingSignature.isEquivalent(to: incomingSignature) {
                let existingDimensions = imageDimensions(existingData)
                let incomingDimensions = imageDimensions(data)
                let existingPixels = (existingDimensions?.width ?? 0)
                    * (existingDimensions?.height ?? 0)
                let incomingPixels = (incomingDimensions?.width ?? 0)
                    * (incomingDimensions?.height ?? 0)
                return (
                    candidateRelativePath,
                    candidateURL,
                    incomingPixels > existingPixels
                )
            }
        }

        throw SableLibraryCoverDownloadError.invalidProviderResponse("could not choose a unique cover filename")
    }

    private func manifestStorefrontVolumeIsCompatible(
        _ cover: SableLibraryDownloadedCoverManifestCover,
        localBook: SableLibraryCoverDownloadLocalBook
    ) -> Bool {
        guard cover.role == .normal,
              cover.source == SableLibraryCoverSource.bookLiveJP.displayName,
              let localVolume = localBook.volumeNumber,
              let providerURL = cover.providerURL,
              let regex = try? NSRegularExpression(
                pattern: #"(?i)(?:/|[?&])vol_no(?:/|=)(\d+(?:\.\d+)?)"#
              ) else {
            return true
        }
        let range = NSRange(providerURL.startIndex..<providerURL.endIndex, in: providerURL)
        guard let match = regex.firstMatch(in: providerURL, range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: providerURL),
              let storefrontVolume = Double(providerURL[valueRange]) else {
            return true
        }

        if let titleVolume = cover.providerTitle.flatMap(
            SableLibraryCoverDownloadPlanner.explicitVolumeNumber(in:)
        ) {
            return SableLibraryCoverDownloadPlanner.volumeNumbersMatch(
                titleVolume,
                localVolume
            )
        }
        return SableLibraryCoverDownloadPlanner.volumeNumbersMatch(
            storefrontVolume,
            localVolume
        )
    }

    private func writeManifestAtomicallyIfChanged(
        _ data: Data,
        to manifestURL: URL,
        root: URL
    ) throws {
        let fileManager = FileManager.default
        let rootPath = canonicalCoverPath(root)
        let manifestPath = canonicalCoverPath(manifestURL)
        guard manifestPath == rootPath || manifestPath.hasPrefix(rootPath + "/") else {
            throw SableLibraryCoverDownloadError.unsafeCoverPath(manifestPath)
        }
        try fileManager.createDirectory(
            at: manifestURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if fileManager.fileExists(atPath: manifestPath) {
            if (try? Data(contentsOf: manifestURL)) == data {
                return
            }
        }
        try data.write(to: manifestURL, options: .atomic)
    }

    private struct CoverManifestFinalization {
        var manifest: SableLibraryDownloadedCoverManifest
        var notes: [String]
    }

    private func finalizeCoverManifest(
        _ manifest: SableLibraryDownloadedCoverManifest,
        manifestURL: URL,
        folder: URL,
        root: URL
    ) throws -> CoverManifestFinalization {
        var finalized = manifest
        var notes: [String] = []

        let initialData = try JSONEncoder.sableCoverManifestEncoder.encode(finalized)
        try writeManifestAtomicallyIfChanged(initialData, to: manifestURL, root: root)

        notes.append(contentsOf: removeUnreferencedCoverFiles(
            entries: finalized.entries,
            folder: folder,
            root: root
        ))

        let canonicalized = canonicalizingCollisionSuffixes(
            in: finalized.entries,
            folder: folder,
            root: root
        )
        finalized.entries = canonicalized.entries
        if canonicalized.renamedCount > 0 {
            notes.append(
                "Local cleanup normalized \(canonicalized.renamedCount) collision-suffixed "
                    + "cover filename\(canonicalized.renamedCount == 1 ? "" : "s")."
            )
        }
        notes.append(contentsOf: canonicalized.notes)
        finalized.skipped.append(contentsOf: notes)

        let canonicalData = try JSONEncoder.sableCoverManifestEncoder.encode(finalized)
        try writeManifestAtomicallyIfChanged(canonicalData, to: manifestURL, root: root)

        let finalCleanupNotes = removeUnreferencedCoverFiles(
            entries: finalized.entries,
            folder: folder,
            root: root
        )
        if !finalCleanupNotes.isEmpty {
            finalized.skipped.append(contentsOf: finalCleanupNotes)
            notes.append(contentsOf: finalCleanupNotes)
            let cleanedData = try JSONEncoder.sableCoverManifestEncoder.encode(finalized)
            try writeManifestAtomicallyIfChanged(cleanedData, to: manifestURL, root: root)
        }

        return CoverManifestFinalization(manifest: finalized, notes: notes)
    }

    private func removeUnreferencedCoverFiles(
        entries: [SableLibraryDownloadedCoverManifestEntry],
        folder: URL,
        root: URL
    ) -> [String] {
        let fileManager = FileManager.default
        let rootPath = canonicalCoverPath(root)
        let coverFolder = folder.appendingPathComponent("_covers", isDirectory: true)
        let coverFolderPath = canonicalCoverPath(coverFolder)
        guard coverFolderPath.hasPrefix(rootPath + "/"),
              fileManager.fileExists(atPath: coverFolderPath) else {
            return []
        }

        let activePaths = Set(entries.flatMap(\.covers).map {
            canonicalCoverPath(folder.appendingPathComponent($0.path))
        })
        let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "avif"]
        guard let enumerator = fileManager.enumerator(
            at: coverFolder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        let staleFiles = enumerator.compactMap { value -> URL? in
            guard let url = value as? URL,
                  imageExtensions.contains(url.pathExtension.lowercased()),
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                return nil
            }
            let path = canonicalCoverPath(url)
            guard path.hasPrefix(coverFolderPath + "/"),
                  path.hasPrefix(rootPath + "/"),
                  !activePaths.contains(path) else {
                return nil
            }
            return url
        }
        guard !staleFiles.isEmpty else { return [] }

        var removedCount = 0
        var failedCount = 0

        for source in staleFiles {
            let sourcePath = canonicalCoverPath(source)
            guard sourcePath.hasPrefix(coverFolderPath + "/"),
                  sourcePath.hasPrefix(rootPath + "/") else {
                failedCount += 1
                continue
            }
            do {
                try fileManager.removeItem(at: source)
                removedCount += 1
            } catch {
                failedCount += 1
            }
        }

        if removedCount > 0 {
            removeEmptyCoverSubfolders(in: coverFolder, fileManager: fileManager)
        }

        var notes: [String] = []
        if removedCount > 0 {
            notes.append(
                "Local cleanup removed \(removedCount) stale unreferenced cover "
                    + "file\(removedCount == 1 ? "" : "s")."
            )
        }
        if failedCount > 0 {
            notes.append(
                "Local cleanup could not remove \(failedCount) stale cover "
                    + "file\(failedCount == 1 ? "" : "s"); the active manifest remains safe."
            )
        }
        return notes
    }

    private struct CollisionSuffixCanonicalization {
        var entries: [SableLibraryDownloadedCoverManifestEntry]
        var renamedCount: Int
        var notes: [String]
    }

    private func canonicalizingCollisionSuffixes(
        in entries: [SableLibraryDownloadedCoverManifestEntry],
        folder: URL,
        root: URL
    ) -> CollisionSuffixCanonicalization {
        let fileManager = FileManager.default
        let rootPath = canonicalCoverPath(root)
        let coverFolderPath = canonicalCoverPath(
            folder.appendingPathComponent("_covers", isDirectory: true)
        )
        var result = entries
        var referencedPaths = Set(entries.flatMap(\.covers).map(\.path))
        var renamedCount = 0
        var failedCount = 0

        for entryIndex in result.indices {
            for coverIndex in result[entryIndex].covers.indices {
                let oldRelativePath = result[entryIndex].covers[coverIndex].path
                guard let newRelativePath = Self.coverPathRemovingCollisionSuffix(
                    oldRelativePath
                ),
                      !referencedPaths.contains(newRelativePath) else {
                    continue
                }
                let source = folder.appendingPathComponent(oldRelativePath)
                let destination = folder.appendingPathComponent(newRelativePath)
                let sourcePath = canonicalCoverPath(source)
                let destinationPath = canonicalCoverPath(destination)
                guard sourcePath.hasPrefix(coverFolderPath + "/"),
                      sourcePath.hasPrefix(rootPath + "/"),
                      destinationPath.hasPrefix(coverFolderPath + "/"),
                      destinationPath.hasPrefix(rootPath + "/"),
                      fileManager.fileExists(atPath: sourcePath),
                      !fileManager.fileExists(atPath: destinationPath) else {
                    continue
                }

                do {
                    try fileManager.createDirectory(
                        at: destination.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    do {
                        try fileManager.linkItem(at: source, to: destination)
                    } catch {
                        try fileManager.copyItem(at: source, to: destination)
                    }
                    result[entryIndex].covers[coverIndex].path = newRelativePath
                    referencedPaths.remove(oldRelativePath)
                    referencedPaths.insert(newRelativePath)
                    renamedCount += 1
                } catch {
                    failedCount += 1
                }
            }
        }

        let notes = failedCount > 0
            ? [
                "Local cleanup could not normalize \(failedCount) collision-suffixed "
                    + "cover filename\(failedCount == 1 ? "" : "s"); existing files remain active."
            ]
            : []
        return CollisionSuffixCanonicalization(
            entries: result,
            renamedCount: renamedCount,
            notes: notes
        )
    }

    static func coverPathRemovingCollisionSuffix(_ path: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #" [0-9]{2,}(\.(?:jpg|jpeg|png|webp|avif))$"#,
            options: [.caseInsensitive]
        ) else {
            return nil
        }
        let range = NSRange(path.startIndex..<path.endIndex, in: path)
        guard let match = regex.firstMatch(in: path, range: range),
              let matchRange = Range(match.range, in: path),
              let extensionRange = Range(match.range(at: 1), in: path) else {
            return nil
        }
        return String(path[..<matchRange.lowerBound]) + String(path[extensionRange])
    }

    private func removeEmptyCoverSubfolders(
        in coverFolder: URL,
        fileManager: FileManager
    ) {
        guard let enumerator = fileManager.enumerator(
            at: coverFolder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return
        }
        let directories = enumerator.compactMap { value -> URL? in
            guard let url = value as? URL,
                  (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                return nil
            }
            return url
        }
        for directory in directories.sorted(
            by: { $0.pathComponents.count > $1.pathComponents.count }
        ) {
            guard (try? fileManager.contentsOfDirectory(atPath: directory.path)).map(\.isEmpty) == true else {
                continue
            }
            try? fileManager.removeItem(at: directory)
        }
    }

    private func canonicalCoverPath(_ url: URL) -> String {
        var path = url.standardizedFileURL
            .resolvingSymlinksInPath()
            .path(percentEncoded: false)
        while path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }

    private func relativeCoverPath(
        request: SableLibraryCoverDownloadRequest,
        localBook: SableLibraryCoverDownloadLocalBook,
        language: String,
        source: SableLibraryCoverSource,
        role: SableLibraryProviderCoverRole,
        roleIndex: Int,
        extensionName: String
    ) -> String {
        let base = sanitizedFileStem((localBook.fileName as NSString).deletingPathExtension)
        let languageLabel = language == "jp" ? "JP" : language.uppercased()
        let roleLabel: String
        switch role {
        case .normal:
            roleLabel = "Cover \(languageLabel)"
        case .specialEdition:
            roleLabel = "Special \(paddedIndex(roleIndex)) \(languageLabel)"
        case .alternativeEdition:
            roleLabel = "Alternative \(paddedIndex(roleIndex)) \(languageLabel)"
        case .bonus:
            roleLabel = "Bonus \(paddedIndex(roleIndex)) \(languageLabel)"
        case .backCover:
            roleLabel = "Back \(paddedIndex(roleIndex)) \(languageLabel)"
        case .audiobook:
            roleLabel = "Audiobook \(languageLabel)"
        case .other:
            roleLabel = "Extra \(paddedIndex(roleIndex)) \(languageLabel)"
        }
        let category = role == .audiobook
            ? "_covers/audiobook/\(language)"
            : "_covers/\(language)"
        return "\(category)/\(base) - \(roleLabel) [\(source.displayName)].\(extensionName)"
    }

    private func sanitizedFileStem(_ value: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\0")
        let cleaned = value
            .components(separatedBy: forbidden)
            .joined(separator: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Cover" : cleaned
    }

    private func paddedIndex(_ value: Int) -> String {
        String(format: "%02d", value)
    }

    private func imageExtension(_ contentType: String?, url rawURL: String) -> String {
        let contentType = contentType?.lowercased() ?? ""
        if contentType.contains("jpeg") || contentType.contains("jpg") { return "jpg" }
        if contentType.contains("png") { return "png" }
        if contentType.contains("webp") { return "webp" }
        if contentType.contains("avif") { return "avif" }
        let ext = URL(string: rawURL)?.pathExtension.lowercased() ?? ""
        if ["jpg", "jpeg", "png", "webp", "avif"].contains(ext) {
            return ext == "jpeg" ? "jpg" : ext
        }
        return "jpg"
    }

    private func imageDimensions(_ data: Data) -> (width: Int, height: Int)? {
        #if canImport(ImageIO)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
            return nil
        }
        return (width.intValue, height.intValue)
        #else
        return nil
        #endif
    }

    private func merge(
        _ incoming: [Int: [SableLibraryDownloadedCoverManifestCover]],
        into result: inout [Int: [SableLibraryDownloadedCoverManifestCover]]
    ) {
        for (key, covers) in incoming {
            var existing = result[key, default: []]
            var seen = Set(existing.map { cover in
                [cover.language, cover.role.rawValue, cover.path].joined(separator: "|")
            })
            for cover in covers {
                let identity = [cover.language, cover.role.rawValue, cover.path].joined(separator: "|")
                if seen.insert(identity).inserted {
                    existing.append(cover)
                }
            }
            result[key] = existing
        }
    }

    private func mergePreferredCoverSelection(
        _ incoming: [Int: [SableLibraryDownloadedCoverManifestCover]],
        into result: inout [Int: [SableLibraryDownloadedCoverManifestCover]]
    ) {
        for (key, covers) in incoming {
            var existing = result[key, default: []]
            for cover in covers {
                if cover.role == .normal {
                    let language = SableLibraryCoverDownloadPlanner.normalizedLanguage(
                        cover.language
                    )
                    existing.removeAll {
                        $0.role == .normal
                            && SableLibraryCoverDownloadPlanner.normalizedLanguage($0.language)
                                == language
                    }
                }
                let identity = [cover.language, cover.role.rawValue, cover.path]
                    .joined(separator: "|")
                if !existing.contains(where: {
                    [$0.language, $0.role.rawValue, $0.path].joined(separator: "|") == identity
                }) {
                    existing.append(cover)
                }
            }
            result[key] = existing
        }
    }

    private func normalCoverBaselines(
        in coversByBookIndex: [Int: [SableLibraryDownloadedCoverManifestCover]],
        language: String,
        bookIndexes: Set<Int>
    ) -> [Int: SableLibraryDownloadedCoverManifestCover] {
        let normalizedLanguage = SableLibraryCoverDownloadPlanner.normalizedLanguage(language)
        return Dictionary(uniqueKeysWithValues: bookIndexes.compactMap { bookIndex in
            let cover = coversByBookIndex[bookIndex]?.first {
                $0.role == .normal
                    && SableLibraryCoverDownloadPlanner.normalizedLanguage($0.language)
                        == normalizedLanguage
            }
            return cover.map { (bookIndex, $0) }
        })
    }

    private func normalCoverBookIndexes(
        in coversByBookIndex: [Int: [SableLibraryDownloadedCoverManifestCover]],
        language: String
    ) -> Set<Int> {
        let normalizedLanguage = SableLibraryCoverDownloadPlanner.normalizedLanguage(language)
        return Set(coversByBookIndex.compactMap { bookIndex, covers in
            covers.contains {
                $0.role == .normal
                    && SableLibraryCoverDownloadPlanner.normalizedLanguage($0.language)
                        == normalizedLanguage
            } ? bookIndex : nil
        })
    }

    private func expandedBookLiveGroupBooksIfNeeded(
        _ books: [SableLibraryBigBookCoversBookCandidate],
        match: SableLibraryManualCoverSeriesMatch,
        request: SableLibraryCoverDownloadRequest
    ) async -> [SableLibraryBigBookCoversBookCandidate] {
        let normalRows = books.filter {
            SableLibraryCoverDownloadPlanner.coverRole(from: $0.title) == .normal
        }
        guard normalRows.count < request.localBooks.count else {
            return books
        }

        var expandedRows: [SableLibraryBigBookCoversBookCandidate] = []
        for representative in normalRows.prefix(4) {
            let titleID = representative.id.split(separator: "-", maxSplits: 1)
                .first
                .map(String.init)
                ?? representative.id
            guard !titleID.isEmpty else { continue }

            do {
                let providerBooks = try await bbcClient.books(
                    itemID: titleID,
                    itemType: "series",
                    provider: .bookLiveJP
                )
                let compatibleBooks = providerBooks.filter {
                    SableLibraryCoverDownloadPlanner.providerTitle(
                        $0.title,
                        belongsTo: representative.title
                    ) || providerTitleBelongsToRequest($0.title, request: request)
                }
                if compatibleBooks.count > 1 {
                    expandedRows.append(contentsOf: compatibleBooks.map { book in
                        var typedBook = book
                        typedBook.bookType = book.bookType
                            ?? representative.bookType
                            ?? match.bookType
                            ?? match.mediaType
                        return typedBook
                    })
                } else {
                    expandedRows.append(representative)
                }
            } catch is CancellationError {
                return books
            } catch {
                expandedRows.append(representative)
            }

            if expandedRows.count >= request.localBooks.count {
                break
            }
        }

        guard expandedRows.count > normalRows.count else {
            return books
        }

        let extras = books.filter {
            SableLibraryCoverDownloadPlanner.coverRole(from: $0.title) != .normal
        }
        var seenIDs = Set<String>()
        return (expandedRows + extras).filter {
            seenIDs.insert($0.id).inserted
        }
    }

    private func providerTitleBelongsToRequest(
        _ providerTitle: String,
        request: SableLibraryCoverDownloadRequest
    ) -> Bool {
        let knownSeriesTitles = SableLibraryCoverDownloadPlanner.uniqueNonEmpty(
            [request.seriesTitle]
                + request.queryTitles
                + request.manualSeriesMatches.map(\.title)
        )
        return SableLibraryCoverDownloadPlanner.providerTitle(
            providerTitle,
            belongsToAny: knownSeriesTitles
        )
    }

    func providerBooksLookCompatibleWithLocalMedia(
        _ books: [SableLibraryBigBookCoversBookCandidate],
        seriesTitle: String,
        seriesBookType: String?,
        mediaType: String?
    ) -> Bool {
        let preferred = SableLibraryCoverDownloadPlanner.preferredProviderBookTypeForDownload(mediaType: mediaType)
        guard preferred == "novel" || preferred == "manga" else { return true }

        if let seriesBookType = normalizedProviderBookType(seriesBookType) {
            return seriesBookType == preferred
        }

        let rowBookTypes = books.prefix(5).compactMap { normalizedProviderBookType($0.bookType) }
        if !rowBookTypes.isEmpty {
            return rowBookTypes.allSatisfy { $0 == preferred }
        }

        let titles = books.prefix(3).map { $0.title }
        guard !titles.isEmpty else { return true }

        let seriesLooksLikeManga = likelyMangaVolumeTitle(seriesTitle)
        let mangaLikeCount = titles.filter(likelyMangaVolumeTitle).count
        if preferred == "novel" {
            return !seriesLooksLikeManga && mangaLikeCount * 2 < titles.count
        }

        let novelLikeCount = titles.filter(likelyNovelVolumeTitle).count
        if preferred == "manga" {
            if seriesLooksLikeManga || mangaLikeCount * 2 >= titles.count {
                return true
            }
            if novelLikeCount > 0 {
                return false
            }
            // ComicInfo says manga, so an untyped series is too ambiguous to accept.
            return false
        }
        return true
    }

    private func storefrontMediaTypeIfNeeded(
        declaredSeriesType: String?,
        books: [SableLibraryBigBookCoversBookCandidate],
        urls: [String?],
        source: SableLibraryCoverSource
    ) async -> String? {
        guard source == .bookLiveJP
            || source == .bookWalkerJP
            || source == .bookWalkerGlobal
            || source == .amazonJP
            || source == .amazon else {
            return nil
        }

        var visited = Set<String>()
        var detectedMediaTypes = Set<String>()
        let maximumAttempts: Int
        switch source {
        case .bookLiveJP, .bookWalkerJP, .bookWalkerGlobal:
            // These providers group books by one storefront media type. A few
            // representative pages provide the extra proof without parsing an
            // entire long-running series volume by volume.
            maximumAttempts = 3
        default:
            // Amazon series can mix Kindle and audiobook editions, so retain
            // per-item verification there.
            maximumAttempts = .max
        }
        var attempts = 0
        for rawURL in urls.compactMap({ $0 }) where visited.insert(rawURL).inserted {
            guard attempts < maximumAttempts else { break }
            attempts += 1
            guard let rawStorefrontURL = URL(string: rawURL) else { continue }
            let url = storefrontVerificationURL(for: rawStorefrontURL)
            guard let html = try? await loadStorefrontHTML(from: url),
                  let mediaType = SableLibraryCoverDownloadPlanner.providerPageMediaType(from: html) else {
                continue
            }
            detectedMediaTypes.insert(mediaType)
            if mediaType == "audiobook" {
                return mediaType
            }
        }
        return detectedMediaTypes.count == 1 ? detectedMediaTypes.first : nil
    }

    private func storefrontVerificationURL(for url: URL) -> URL {
        guard let host = url.host?.lowercased(),
              host.contains("amazon.") else {
            return url
        }

        let components = url.pathComponents.filter { $0 != "/" }
        let asin: String?
        if let marker = components.firstIndex(where: { $0 == "dp" || $0 == "product" }),
           components.indices.contains(marker + 1) {
            asin = components[marker + 1]
        } else {
            asin = nil
        }
        guard let asin,
              asin.count == 10,
              asin.allSatisfy({ $0.isASCII && $0.isLetter || $0.isNumber }),
              var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        urlComponents.path = "/gp/aw/d/\(asin)"
        urlComponents.query = nil
        urlComponents.fragment = nil
        return urlComponents.url ?? url
    }

    private func normalizedProviderBookType(_ value: String?) -> String? {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if normalized.contains("audiobook")
            || normalized.contains("audio book")
            || normalized.contains("audible")
            || normalized.contains("オーディオ") {
            return "audiobook"
        }
        if normalized.contains("novel") || normalized == "book" {
            return "novel"
        }
        if normalized.contains("manga")
            || normalized.contains("comic")
            || normalized.contains("manhwa")
            || normalized.contains("manhua") {
            return "manga"
        }
        return nil
    }

    private func likelyMangaVolumeTitle(_ title: String) -> Bool {
        let normalized = title.lowercased()
        if normalized.contains("manga")
            || normalized.contains("comic")
            || normalized.contains("graphic novel") {
            return true
        }
        if title.range(of: #"[（(]\d+[）)]"#, options: .regularExpression) != nil {
            return true
        }
        if title.range(of: #"\d+\s*[巻卷]"#, options: .regularExpression) != nil {
            return true
        }
        return title.contains("コミック") || title.contains("漫画") || title.contains("まんが") || title.contains("マンガ")
    }

    private func likelyNovelVolumeTitle(_ title: String) -> Bool {
        let normalized = title.lowercased()
        return normalized.contains("light novel")
            || normalized.contains("novel")
            || title.contains("小説")
            || title.contains("ライトノベル")
    }
}

private extension JSONEncoder {
    static var sableCoverManifestEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

struct SableLibraryProviderCoverCandidate: Codable, Sendable, Equatable {
    var provider: SableLibraryMetadataProvider
    var providerSeriesID: String?
    var providerItemID: String?
    var title: String?
    var volumeIndex: String?
    var volumeNumber: Double?
    var mediaType: String?
    var language: String?
    var role: SableLibraryProviderCoverRole
    var providerType: String?
    var editionNote: String?
    var imageURL: String
    var width: Int?
    var height: Int?
    var byteCount: Int?
    var storeURLs: [String]
    var quality: SableLibraryProviderCoverQuality
    var fallbackImageURLs: [String] = []
    var publicationType: String? = nil

    var canReplaceNormalCover: Bool {
        role == .normal && (quality == .highResolution || quality == .usable)
    }

    var isAudiobookCover: Bool {
        if role == .audiobook {
            return true
        }
        let descriptor = [
            mediaType,
            providerType,
            editionNote,
            title
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")
        return descriptor.contains("audiobook")
            || descriptor.contains("audio book")
            || descriptor.contains("audible")
            || descriptor.contains("オーディオ")
    }

    func mediaTypeForSeriesIdentity(_ seriesMediaType: String) -> String {
        isAudiobookCover ? "audiobook" : seriesMediaType
    }

    var shouldSaveAsExtraCover: Bool {
        guard !isAudiobookCover else { return false }
        return role == .specialEdition || role == .alternativeEdition || role == .bonus
    }
}

enum SableLibraryProviderCandidateParser {
    static func mangaBakaCandidates(from object: [String: Any]) -> [SableLibraryProviderCandidate] {
        let rows = object["data"] as? [[String: Any]] ?? []
        return rows.compactMap { row in
            guard let title = text(row["title"]) else { return nil }
            let id = text(row["id"]).map { SableLibrarySourceID(provider: .mangabaka, value: $0) }
            let aliases = [
                text(row["native_title"]),
                text(row["romanized_title"]),
                text(row["romaji"])
            ].compactMap { $0 }
            let v2TagRows = mangaBakaV2TagRows(from: row)
            let legacyTagRows = mangaBakaLegacyTagRows(from: row)
            let studioRows = row["studios"] as? [[String: Any]] ?? []
            let studioStrings = stringValues(from: row["studio"])
            return SableLibraryProviderCandidate(
                provider: .mangabaka,
                title: title,
                year: int(row["year"]),
                mediaType: text(row["type"]),
                sourceIDs: id.map { [$0] } ?? [],
                aliases: unique(aliases + stringValues(from: row["alias"]).compactMap { $0 }),
                description: text(row["description"]),
                genres: unique(
                    mangaBakaV2Names(from: row["genres_v2"])
                        + mangaBakaV2TagNames(from: v2TagRows, isGenre: true)
                        + taggedValues(from: legacyTagRows, type: "genre")
                        + namedValues(from: row["genres"])
                ),
                tags: unique(
                    mangaBakaV2TagNames(from: v2TagRows, isGenre: false)
                        + taggedValues(from: legacyTagRows, excludingType: "genre")
                        + mangaBakaLegacyNamedValues(from: row["tags"])
                ),
                contentWarnings: unique(
                    mangaBakaV2ContentWarningNames(from: v2TagRows)
                        + namedValues(from: row["warnings"])
                        + namedValues(from: row["content_warnings"])
                ),
                studios: unique(namedValues(from: studioRows) + studioStrings),
                status: text(row["publication_status"]),
                contentRating: bool(row["isAdult"]) == true ? "adult" : nil,
                coverURL: mangaBakaCoverURL(from: row)
            )
        }
    }

    static func ranobeDBCandidates(from object: [String: Any]) -> [SableLibraryProviderCandidate] {
        let rows = object["releases"] as? [[String: Any]] ?? []
        return rows.compactMap { row in
            guard let title = text(row["title"]) else { return nil }
            var ids: [SableLibrarySourceID] = []
            if let id = candidateID(
                from: row,
                keys: ["id", "series_id", "seriesId", "seriesid", "release_id"],
                idsMapKeys: ["id", "series_id", "seriesId", "seriesid", "rdb", "ranobedb"]
            ) {
                ids.append(SableLibrarySourceID(provider: .ranobedb, value: id))
            }
            let isbn = text(row["isbn13"]).map { [$0] } ?? []
            return SableLibraryProviderCandidate(
                provider: .ranobedb,
                title: title,
                year: year(fromPackedDate: int(row["release_date"])),
                mediaType: text(row["format"]),
                sourceIDs: ids,
                isbn13: isbn,
                coverURL: ranobeDBCoverURL(from: row)
            )
        }
    }

    static func ranobeDBSeriesCandidates(from object: [String: Any]) -> [SableLibraryProviderCandidate] {
        let rows = object["series"] as? [[String: Any]] ?? []
        return rows.compactMap { row in
            guard let title = text(row["title"]) else { return nil }
            var ids: [SableLibrarySourceID] = []
            if let id = candidateID(
                from: row,
                keys: ["id", "series_id", "seriesId", "seriesid", "rdb", "ranobedb"],
                idsMapKeys: ["id", "series_id", "seriesId", "seriesid", "ranobedb", "rdb"]
            ) {
                ids.append(SableLibrarySourceID(provider: .ranobedb, value: id))
            }
            return SableLibraryProviderCandidate(
                provider: .ranobedb,
                title: title,
                year: year(fromPackedDate: int(row["c_start_date"]) ?? int(row["start_date"])),
                mediaType: "lightNovel",
                sourceIDs: ids,
                aliases: unique([
                    text(row["title_orig"]),
                    text(row["romaji"]),
                    text(row["romaji_orig"])
                ].compactMap { $0 }),
                coverURL: ranobeDBCoverURL(from: row)
            )
        }
    }

    static func ranobeDBSeriesDetailCandidate(from object: [String: Any]) -> SableLibraryProviderCandidate? {
        guard let series = object["series"] as? [String: Any],
              let title = text(series["title"]) else {
            return nil
        }

        var ids: [SableLibrarySourceID] = []
        if let id = candidateID(
            from: series,
            keys: ["id", "series_id", "seriesId", "seriesid", "ranobedb_id", "ranobedbid", "rdb"],
            idsMapKeys: ["id", "series_id", "seriesId", "seriesid", "ranobedb", "rdb"]
        ) {
            ids.append(SableLibrarySourceID(provider: .ranobedb, value: id))
        }

        let anilistIDKeys = ["anilist_id", "anilistId", "anilistid", "al_id", "alId"]
        if let id = candidateID(from: series, keys: anilistIDKeys) {
            ids.append(SableLibrarySourceID(provider: .anilist, value: id))
        }
        if let anilist = series["anilist"] as? [String: Any],
           let id = candidateID(from: anilist, keys: ["id", "anilist_id", "anilistId", "anilistid", "mal_id", "malId"]) {
            ids.append(SableLibrarySourceID(provider: .anilist, value: id))
        }
        if let idMap = series["ids"] as? [String: Any],
           let id = candidateTextValue(from: idMap, keys: ["anilist", "al", "anilist_id", "al_id"]) {
            ids.append(SableLibrarySourceID(provider: .anilist, value: id))
        }

        if let id = candidateID(from: series, keys: ["mal_id", "malId", "myanimelist_id", "my_anime_list_id", "myAnimeList", "myAnimeListID"]) {
            ids.append(SableLibrarySourceID(provider: .myAnimeList, value: id))
        }
        if let myAnimeList = series["myanimelist"] as? [String: Any],
           let id = candidateID(from: myAnimeList, keys: ["id", "myanimelist_id", "mal_id"]) {
            ids.append(SableLibrarySourceID(provider: .myAnimeList, value: id))
        }
        if let idMap = series["ids"] as? [String: Any],
           let id = candidateTextValue(from: idMap, keys: ["myanimelist", "myanimelist_id", "my_anime_list_id", "mal", "mal_id", "myanimelistid"]) {
            ids.append(SableLibrarySourceID(provider: .myAnimeList, value: id))
        }

        var aliases = [
            text(series["title_orig"]),
            text(series["romaji"]),
            text(series["romaji_orig"])
        ].compactMap { $0 }
        if let titles = series["titles"] as? [[String: Any]] {
            aliases.append(contentsOf: titles.compactMap { text($0["title"]) })
            aliases.append(contentsOf: titles.compactMap { text($0["romaji"]) })
        }
        if let rawAliases = text(series["aliases"]) {
            aliases.append(contentsOf: rawAliases.components(separatedBy: .newlines))
        }

        let tagRows = series["tags"] as? [[String: Any]] ?? []
        let contentWarningRows = series["content_warnings"] as? [[String: Any]] ?? []
        let staffRows = series["staff"] as? [[String: Any]] ?? []
        return SableLibraryProviderCandidate(
            provider: .ranobedb,
            title: title,
            year: year(fromPackedDate: int(series["c_start_date"]) ?? int(series["start_date"])),
            mediaType: "lightNovel",
            sourceIDs: ids,
            aliases: unique(aliases),
            description: text(series["description"]) ?? text((series["book_description"] as? [String: Any])?["description"]),
            genres: taggedValues(from: tagRows, type: "genre"),
            tags: unique(taggedValues(from: tagRows, excludingType: "genre") + taggedValues(from: contentWarningRows, type: "content_warning")),
            contentWarnings: taggedValues(from: contentWarningRows, type: "content_warning"),
            studios: namedValues(from: series["studios"]),
            authors: staffNames(from: staffRows, role: "author"),
            artists: staffNames(from: staffRows, role: "artist"),
            publishers: namedValues(from: series["publishers"]),
            languages: unique([
                text(series["lang"]),
                text(series["olang"])
            ].compactMap { $0 }),
            status: text(series["publication_status"]),
            coverURL: ranobeDBCoverURL(from: series)
        )
    }

    static func ranobeDBReadingParts(from object: [String: Any], preferredTitle: String) -> [SableLibraryReadingPartMetadata] {
        guard let series = object["series"] as? [String: Any],
              let books = series["books"] as? [[String: Any]] else {
            return []
        }

        let scopedBooks = books
            .filter { ranobeDBBook($0, belongsTo: preferredTitle) }
            .sorted {
                (int($0["sort_order"]) ?? Int.max) < (int($1["sort_order"]) ?? Int.max)
            }
        return scopedBooks.enumerated().compactMap { index, book in
            part(
                from: book,
                preferredTitle: preferredTitle,
                fallbackNumber: index + 1
            )
        }
    }

    static func ranobeDBReadingPartDetail(
        from object: [String: Any],
        preferredTitle: String,
        fallback: SableLibraryReadingPartMetadata? = nil
    ) -> SableLibraryReadingPartMetadata? {
        guard let book = object["book"] as? [String: Any] else { return nil }
        guard var part = part(
            from: book,
            preferredTitle: preferredTitle,
            fallbackNumber: fallback?.number
        )
            ?? fallbackPart(from: book, preferredTitle: preferredTitle, fallback: fallback) else {
            return nil
        }

        let releases = book["releases"] as? [[String: Any]] ?? []
        let englishReleases = releases.filter { text($0["lang"]) == "en" }
        let preferredReleases = englishReleases.isEmpty ? releases : englishReleases
        let releaseIDs = preferredReleases.compactMap { text($0["id"]) }
        let isbn = preferredReleases.compactMap { text($0["isbn13"]).flatMap(normalizedISBN13) }
        let pages = preferredReleases.compactMap { int($0["pages"]) }.first
        let releaseDate = preferredReleases.compactMap { int($0["release_date"]) }.first

        part.isbn13 = unique(isbn)
        part.releaseIDs = unique(releaseIDs)
        part.pages = pages
        part.releaseDate = releaseDate ?? part.releaseDate
        part.releaseYear = year(fromPackedDate: releaseDate) ?? part.releaseYear
        return part
    }

    static func mangaBakaCoverCandidates(
        from object: [String: Any],
        seriesID fallbackSeriesID: String? = nil
    ) -> [SableLibraryProviderCoverCandidate] {
        let rows: [[String: Any]]
        if let directRows = object["data"] as? [[String: Any]] {
            rows = directRows
        } else if let directRows = object["covers"] as? [[String: Any]] {
            rows = directRows
        } else {
            rows = []
        }

        return rows.compactMap { row in
            guard let imageURL = providerCoverURL(from: row) else { return nil }
            let width = int(nestedValue(row["image"], "raw", "width")) ?? int(nestedValue(row["image"], "width"))
            let height = int(nestedValue(row["image"], "raw", "height")) ?? int(nestedValue(row["image"], "height"))
            let byteCount = int(nestedValue(row["image"], "raw", "size")) ?? int(row["size"])
            let providerType = text(row["type"])
            let editionNote = text(row["note"])
            return SableLibraryProviderCoverCandidate(
                provider: .mangabaka,
                providerSeriesID: text(row["series_id"]) ?? fallbackSeriesID,
                providerItemID: text(row["id"]),
                title: nil,
                volumeIndex: text(row["index"]),
                volumeNumber: double(row["index_numeric"]),
                mediaType: providerType,
                language: text(row["language"]),
                role: mangaBakaCoverRole(type: providerType, note: editionNote),
                providerType: providerType,
                editionNote: editionNote,
                imageURL: imageURL,
                width: width,
                height: height,
                byteCount: byteCount,
                storeURLs: [],
                quality: coverQuality(width: width, height: height, byteCount: byteCount)
            )
        }
    }

    static func mangaBakaCoverPage(
        from data: Data,
        seriesID: String
    ) throws -> (candidates: [SableLibraryProviderCoverCandidate], nextPageURL: URL?) {
        try autoreleasepool {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw SableLibraryCoverDownloadError.invalidProviderResponse(
                    "MangaBaka images did not return a JSON object"
                )
            }
            let candidates = mangaBakaCoverCandidates(from: object, seriesID: seriesID)
            let pagination = object["pagination"] as? [String: Any]
            let nextPageURL = text(pagination?["next"]).flatMap(URL.init(string:))
            return (candidates, nextPageURL)
        }
    }

    static func mangaBakaCoverCandidates(
        fromCoversPageHTML html: String,
        seriesID fallbackSeriesID: String? = nil
    ) -> [SableLibraryProviderCoverCandidate] {
        for body in embeddedJSONStringValues(named: "body", in: html) {
            let candidates: [SableLibraryProviderCoverCandidate] = autoreleasepool {
                guard let data = body.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return []
                }
                return mangaBakaCoverCandidates(from: object, seriesID: fallbackSeriesID)
            }
            if !candidates.isEmpty {
                return candidates
            }
        }
        return []
    }

    static func ranobeDBCoverCandidates(from object: [String: Any]) -> [SableLibraryProviderCoverCandidate] {
        var candidates: [SableLibraryProviderCoverCandidate] = []

        if let series = object["series"] as? [String: Any] {
            let seriesID = text(series["id"]) ?? text(series["series_id"]) ?? text(series["seriesId"])
            let books = series["books"] as? [[String: Any]] ?? []
            for book in books {
                if let candidate = ranobeDBCoverCandidate(from: book, seriesID: seriesID) {
                    candidates.append(candidate)
                }
            }
            if candidates.isEmpty,
               let candidate = ranobeDBCoverCandidate(from: series, seriesID: seriesID) {
                candidates.append(candidate)
            }
        }

        if let book = object["book"] as? [String: Any],
           let candidate = ranobeDBCoverCandidate(from: book, seriesID: nil) {
            candidates.append(candidate)
        }

        if object["series"] == nil,
           object["book"] == nil,
           let candidate = ranobeDBCoverCandidate(from: object, seriesID: nil) {
            candidates.append(candidate)
        }

        return deduplicatedCoverCandidates(candidates)
    }

    static func bigBookCoversCandidates(
        from books: [SableLibraryBigBookCoversBookCandidate],
        source: SableLibraryCoverSource,
        language: String,
        mediaType: String?
    ) -> [SableLibraryProviderCoverCandidate] {
        let titleVolumes = books.map { bigBookCoversVolumeNumber(in: $0.title) }
        let titleVolumesByProviderVolume = zip(books, titleVolumes).reduce(
            into: [Int: Set<Int>]()
        ) { result, pair in
            guard let providerVolume = pair.0.volumeNumber.map({ Int($0.rounded()) }),
                  let titleVolume = pair.1.map({ Int($0.rounded()) }) else {
                return
            }
            result[providerVolume, default: []].insert(titleVolume)
        }

        return books
            .filter { $0.volumeType?.lowercased() != "chapter" }
            .filter { !storefrontTitleIsChapterSerial($0.title) }
            .filter {
                SableLibraryCoverDownloadPlanner.providerTitleLanguageIsCompatible(
                    $0.title,
                    language: language,
                    source: source
                )
            }
            .map { book in
            let role = SableLibraryCoverDownloadPlanner.coverRole(from: book.title)
            let titleVolume = bigBookCoversVolumeNumber(in: book.title)
            let providerVolume = book.volumeNumber
            let storefrontVolume = storefrontVolumeNumber(
                in: book.url,
                source: source
            )
            let shouldTrustContradictoryTitleVolume: Bool
            if let providerVolume,
               let distinctTitleVolumes = titleVolumesByProviderVolume[Int(providerVolume.rounded())] {
                shouldTrustContradictoryTitleVolume = distinctTitleVolumes.count > 1
            } else {
                shouldTrustContradictoryTitleVolume = providerVolume == nil
            }
            let volumeNumber = shouldTrustContradictoryTitleVolume
                ? titleVolume ?? providerVolume ?? storefrontVolume
                : providerVolume ?? titleVolume ?? storefrontVolume
            let volumeIndex: String
            if let volumeNumber {
                volumeIndex = String(Int(volumeNumber.rounded()))
            } else {
                volumeIndex = String(book.sequenceIndex)
            }
            return SableLibraryProviderCoverCandidate(
                provider: .local,
                providerSeriesID: book.seriesID,
                providerItemID: book.id,
                title: book.title,
                volumeIndex: volumeIndex,
                volumeNumber: volumeNumber,
                mediaType: book.bookType ?? mediaType,
                language: language,
                role: role,
                providerType: book.bookType,
                editionNote: role == .normal ? nil : book.title,
                imageURL: book.coverURL,
                width: nil,
                height: nil,
                byteCount: nil,
                storeURLs: [book.url].compactMap { $0 },
                quality: .unknown,
                fallbackImageURLs: book.coverFallbackURLs,
                publicationType: book.publicationType
            )
        }
    }

    private static func bigBookCoversVolumeNumber(in title: String) -> Double? {
        let normalizedTitle = title.applyingTransform(
            .fullwidthToHalfwidth,
            reverse: false
        ) ?? title
        let patterns = [
            #"(?i)\bvol(?:ume)?\.?\s*(\d+(?:\.\d+)?)"#,
            #"(?i)\bbook\s*(\d+(?:\.\d+)?)"#,
            #"(?i)\bpart\s*(\d+(?:\.\d+)?)"#,
            #"新装版\s*(\d+(?:\.\d+)?)"#,
            #"第\s*(\d+(?:\.\d+)?)\s*[巻卷]"#,
            #"(\d+(?:\.\d+)?)\s*[巻卷]"#,
            #"(\d{1,3})(?=\s*【)"#,
            #"(\d{1,3})(?:\s*[（(][^）)]*[）)])?\s*$"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(
                normalizedTitle.startIndex..<normalizedTitle.endIndex,
                in: normalizedTitle
            )
            guard let match = regex.firstMatch(in: normalizedTitle, range: range),
                  match.numberOfRanges > 1,
                  let valueRange = Range(match.range(at: 1), in: normalizedTitle),
                  let value = Double(normalizedTitle[valueRange]) else { continue }
            return value
        }
        return nil
    }

    static func storefrontTitleIsChapterSerial(_ title: String) -> Bool {
        let normalizedTitle = (
            title.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? title
        ).lowercased()
        let chapterMarkers = [
            "分冊版",
            "分册版",
            "単話版",
            "单话版",
            "単話",
            "单话",
            "マイクロ版",
            "単話売り",
            "話売り",
            "ばら売り",
            "連載版",
            "chapter"
        ]
        if chapterMarkers.contains(where: { marker in
            let normalizedMarker = (
                marker.applyingTransform(
                    .fullwidthToHalfwidth,
                    reverse: false
                ) ?? marker
            ).lowercased()
            return normalizedTitle.contains(normalizedMarker)
        }) {
            return true
        }
        guard let regex = try? NSRegularExpression(
            pattern: #"第?\s*\d+(?:\.\d+)?\s*話"#
        ) else {
            return false
        }
        let range = NSRange(
            normalizedTitle.startIndex..<normalizedTitle.endIndex,
            in: normalizedTitle
        )
        return regex.firstMatch(in: normalizedTitle, range: range) != nil
    }

    private static func storefrontVolumeNumber(
        in url: String?,
        source: SableLibraryCoverSource
    ) -> Double? {
        guard source == .bookLiveJP,
              let url,
              let regex = try? NSRegularExpression(
                pattern: #"(?i)(?:/|[?&])vol_no(?:/|=)(\d+(?:\.\d+)?)"#
              ) else {
            return nil
        }
        let range = NSRange(url.startIndex..<url.endIndex, in: url)
        guard let match = regex.firstMatch(in: url, range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: url) else {
            return nil
        }
        return Double(url[valueRange])
    }

    private static func fallbackPart(
        from row: [String: Any],
        preferredTitle: String,
        fallback: SableLibraryReadingPartMetadata?
    ) -> SableLibraryReadingPartMetadata? {
        guard var part = fallback else { return nil }
        if let title = text(row["title"]) {
            part.title = title
            if let subtitle = subtitle(from: title, preferredTitle: preferredTitle, number: part.number) {
                part.subtitle = subtitle
                part.fileSuffix = "Vol \(paddedVolume(part.number)) - \(subtitle)"
            }
        }
        if let sourceID = text(row["id"]) {
            part.sourceID = SableLibrarySourceID(provider: .ranobedb, value: sourceID)
        }
        if let releaseDate = int(row["c_release_date"]) {
            part.releaseDate = releaseDate
            part.releaseYear = year(fromPackedDate: releaseDate)
        }
        if part.description == nil {
            part.description = bookDescription(from: row)
        }
        return part
    }

    static func openLibraryCandidates(from object: [String: Any]) -> [SableLibraryProviderCandidate] {
        let rows = object["docs"] as? [[String: Any]] ?? []
        return rows.compactMap { row in
            guard let title = text(row["title"]) else { return nil }
            let key = text(row["key"]).map { SableLibrarySourceID(provider: .openLibrary, value: $0) }
            let isbn = (row["isbn"] as? [String] ?? []).filter { normalizedISBN13($0) != nil }.compactMap(normalizedISBN13)
            return SableLibraryProviderCandidate(
                provider: .openLibrary,
                title: title,
                year: int(row["first_publish_year"]),
                sourceIDs: key.map { [$0] } ?? [],
                isbn13: Array(Set(isbn)).sorted(),
                genres: subjectValues(from: row["subject"], prefix: "genre:"),
                tags: subjectValues(from: row["subject"], excludingPrefixes: ["genre:", "series:", "franchise:"]),
                authors: stringValues(from: row["author_name"]),
                publishers: stringValues(from: row["publisher"]),
                languages: unique(stringValues(from: row["language"]) + editionLanguages(from: row["editions"])),
                coverURL: openLibraryCoverURL(from: row, isbn13: isbn)
            )
        }
    }

    private static func editionLanguages(from value: Any?) -> [String] {
        guard let editions = value as? [String: Any],
              let docs = editions["docs"] as? [[String: Any]] else {
            return []
        }
        return docs.flatMap { stringValues(from: $0["language"]) }
    }

    static func aniListCandidate(from media: [String: Any]) -> SableLibraryProviderCandidate? {
        guard let titles = media["title"] as? [String: Any],
              let title = text(titles["english"]) ?? text(titles["romaji"]) ?? text(titles["native"]) else {
            return nil
        }

        var ids: [SableLibrarySourceID] = []
        if let id = candidateTextValue(from: media, keys: ["id"]) {
            ids.append(SableLibrarySourceID(provider: .anilist, value: id))
        }
        if let idMal = candidateTextValue(from: media, keys: ["idMal", "id_mal", "mal_id", "myanimelist_id", "myAnimeListId"]) {
            ids.append(SableLibrarySourceID(provider: .myAnimeList, value: idMal))
        }
        if let idMap = media["ids"] as? [String: Any] {
            if let id = candidateTextValue(from: idMap, keys: ["myanimelist", "mal_id", "malId"]) {
                ids.append(SableLibrarySourceID(provider: .myAnimeList, value: id))
            }
        }

        var aliases = [
            text(titles["romaji"]),
            text(titles["english"]),
            text(titles["native"])
        ].compactMap { $0 }
        aliases.append(contentsOf: media["synonyms"] as? [String] ?? [])

        return SableLibraryProviderCandidate(
            provider: .anilist,
            title: title,
            year: int(media["seasonYear"]) ?? int((media["startDate"] as? [String: Any])?["year"]),
            mediaType: text(media["format"]),
            sourceIDs: ids,
            aliases: Array(Set(aliases)).sorted(),
            description: text(media["description"]),
            genres: stringValues(from: media["genres"]),
            tags: nestedNamedValues(from: media["tags"]),
            contentWarnings: bool(media["isAdult"]) == true ? ["adult"] : [],
            studios: nestedNamedValues(from: media["studios"]),
            status: text(media["status"]),
            contentRating: bool(media["isAdult"]) == true ? "adult" : nil,
            coverURL: aniListCoverURL(from: media)
        )
    }

    static func tmdbCandidates(from object: [String: Any]) -> [SableLibraryProviderCandidate] {
        let rows = object["results"] as? [[String: Any]] ?? []
        return rows.compactMap { row in
            guard let mediaType = text(row["media_type"]),
                  ["movie", "tv"].contains(mediaType),
                  let title = text(row["title"]) ?? text(row["name"]) else {
                return nil
            }
            let id = text(row["id"]).map { SableLibrarySourceID(provider: .tmdb, value: $0) }
            let date = text(row["release_date"]) ?? text(row["first_air_date"])
            return SableLibraryProviderCandidate(
                provider: .tmdb,
                title: title,
                year: date.flatMap { Int($0.prefix(4)) },
                mediaType: mediaType == "tv" ? "tvShow" : "movie",
                sourceIDs: id.map { [$0] } ?? [],
                coverURL: tmdbCoverURL(from: row)
            )
        }
    }

    static func tvmazeCandidate(from object: [String: Any]) -> SableLibraryProviderCandidate? {
        guard let title = text(object["name"]) else { return nil }

        var ids: [SableLibrarySourceID] = []
        if let id = text(object["id"]) {
            ids.append(SableLibrarySourceID(provider: .tvmaze, value: id))
        }
        if let externals = object["externals"] as? [String: Any] {
            if let id = text(externals["thetvdb"]) {
                ids.append(SableLibrarySourceID(provider: .tvdb, value: id))
            }
            if let id = text(externals["imdb"]) {
                ids.append(SableLibrarySourceID(provider: .imdb, value: id))
            }
        }

        return SableLibraryProviderCandidate(
            provider: .tvmaze,
            title: title,
            year: text(object["premiered"]).flatMap { Int($0.prefix(4)) },
            mediaType: "tvShow",
            sourceIDs: ids,
            aliases: text(object["officialSite"]).map { [$0] } ?? [],
            genres: stringValues(from: object["genres"]),
            status: text(object["status"]),
            coverURL: tvmazeCoverURL(from: object)
        )
    }

    static func wikidataSourceIDs(from object: [String: Any]) -> [SableLibrarySourceID] {
        guard let results = object["results"] as? [String: Any],
              let bindings = results["bindings"] as? [[String: Any]] else {
            return []
        }

        var ids: [SableLibrarySourceID] = []
        for binding in bindings {
            if let qid = wikidataEntityID(from: bindingValue("item", in: binding)) {
                ids.append(SableLibrarySourceID(provider: .wikidata, value: qid))
            }
            if let tmdbTV = bindingValue("tmdbTV", in: binding) {
                ids.append(SableLibrarySourceID(provider: .tmdb, value: tmdbTV))
            }
            if let tmdbMovie = bindingValue("tmdbMovie", in: binding) {
                ids.append(SableLibrarySourceID(provider: .tmdb, value: tmdbMovie))
            }
            if let tvdb = bindingValue("tvdb", in: binding) {
                ids.append(SableLibrarySourceID(provider: .tvdb, value: tvdb))
            }
            if let imdb = bindingValue("imdb", in: binding) {
                ids.append(SableLibrarySourceID(provider: .imdb, value: imdb))
            }
        }
        return uniqueSourceIDs(ids)
    }

    static func wikidataCandidates(from object: [String: Any]) -> [SableLibraryProviderCandidate] {
        guard let results = object["results"] as? [String: Any],
              let bindings = results["bindings"] as? [[String: Any]] else {
            return []
        }

        var candidatesByIdentity: [String: SableLibraryProviderCandidate] = [:]
        var identityOrder: [String] = []

        for binding in bindings {
            guard let title = bindingValue("itemLabel", in: binding) ?? bindingValue("label", in: binding) else {
                continue
            }

            var ids: [SableLibrarySourceID] = []
            if let qid = wikidataEntityID(from: bindingValue("item", in: binding)) {
                ids.append(SableLibrarySourceID(provider: .wikidata, value: qid))
            }
            if let tmdbTV = bindingValue("tmdbTV", in: binding) {
                ids.append(SableLibrarySourceID(provider: .tmdb, value: tmdbTV))
            }
            if let tmdbMovie = bindingValue("tmdbMovie", in: binding) {
                ids.append(SableLibrarySourceID(provider: .tmdb, value: tmdbMovie))
            }
            if let tvdb = bindingValue("tvdb", in: binding) {
                ids.append(SableLibrarySourceID(provider: .tvdb, value: tvdb))
            }
            if let imdb = bindingValue("imdb", in: binding) {
                ids.append(SableLibrarySourceID(provider: .imdb, value: imdb))
            }
            if let openLibrary = bindingValue("openLibrary", in: binding),
               let sourceID = openLibrarySourceID(from: openLibrary) {
                ids.append(sourceID)
            }

            let year = int(bindingValue("releaseYear", in: binding))
                ?? int(bindingValue("startYear", in: binding))
                ?? int(bindingValue("year", in: binding))
            let seriesTags = unique([
                bindingValue("seriesLabel", in: binding).map { "series:\($0)" },
                bindingValue("partOfLabel", in: binding).map { "part of:\($0)" },
                bindingValue("volume", in: binding).map { "volume:\($0)" }
            ].compactMap { $0 })
            let candidate = SableLibraryProviderCandidate(
                provider: .wikidata,
                title: title,
                year: year,
                mediaType: wikidataMediaType(in: binding),
                sourceIDs: uniqueSourceIDs(ids),
                isbn13: bindingValue("isbn13", in: binding).flatMap(normalizedISBN13).map { [$0] } ?? [],
                tags: seriesTags,
                authors: bindingValue("authorLabel", in: binding).map { [$0] } ?? [],
                publishers: bindingValue("publisherLabel", in: binding).map { [$0] } ?? []
            )

            let identity = wikidataCandidateIdentity(candidate)
            if candidatesByIdentity[identity] == nil {
                identityOrder.append(identity)
                candidatesByIdentity[identity] = candidate
            } else {
                candidatesByIdentity[identity] = mergedWikidataCandidate(
                    candidatesByIdentity[identity]!,
                    candidate
                )
            }
        }

        return identityOrder.compactMap { candidatesByIdentity[$0] }
    }

    private static func text(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    private static func int(_ value: Any?) -> Int? {
        if let number = value as? NSNumber {
            return number.intValue
        }
        guard let text = text(value) else { return nil }
        return Int(text)
    }

    private static func double(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        guard let text = text(value) else { return nil }
        return Double(text)
    }

    private static func bool(_ value: Any?) -> Bool? {
        if let bool = value as? Bool {
            return bool
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        guard let text = text(value)?.lowercased() else { return nil }
        switch text {
        case "true", "yes", "1":
            return true
        case "false", "no", "0":
            return false
        default:
            return nil
        }
    }

    private static func stringValues(from value: Any?) -> [String] {
        switch value {
        case let strings as [String]:
            unique(strings)
        case let string as String:
            unique(string.components(separatedBy: CharacterSet(charactersIn: ",;")))
        default:
            []
        }
    }

    private static func candidateTextValue(from object: [String: Any], keys: [String]) -> String? {
        let candidates = object.reduce(into: [String: String]()) { result, item in
            let key = normalizedCandidateIDKey(item.key)
            guard result[key] == nil,
                  let textValue = text(item.value) else { return }
            result[key] = textValue
        }
        for key in keys {
            guard let found = candidates[normalizedCandidateIDKey(key)] else { continue }
            if !found.isEmpty {
                return found
            }
        }
        return nil
    }

    private static func candidateID(
        from object: [String: Any],
        keys: [String],
        idsMapKeys: [String] = []
    ) -> String? {
        if let id = candidateTextValue(from: object, keys: keys) {
            return id
        }

        guard
            let idsMap = object["ids"] as? [String: Any],
            !idsMapKeys.isEmpty
        else {
            return nil
        }
        return candidateTextValue(from: idsMap, keys: idsMapKeys)
    }

    private static func normalizedCandidateIDKey(_ key: String) -> String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
    }

    private static func nestedNamedValues(from value: Any?) -> [String] {
        switch value {
        case let rows as [[String: Any]]:
            return namedValues(from: rows)
        case let node as [String: Any]:
            var values: [String] = []
            if let rows = node["nodes"] as? [[String: Any]] {
                values.append(contentsOf: namedValues(from: rows))
            }
            if let edges = node["edges"] as? [[String: Any]] {
                values.append(contentsOf: namedValues(from: edges.compactMap { $0["node"] as? [String: Any] }))
            }
            values.append(contentsOf: namedValues(from: node["node"]))
            return unique(values)
        default:
            return namedValues(from: value)
        }
    }

    private static func namedValues(from value: Any?) -> [String] {
        switch value {
        case let rows as [[String: Any]]:
            unique(rows.compactMap { text($0["name"]) ?? text($0["title"]) ?? text($0["label"]) })
        case let strings as [String]:
            unique(strings)
        case let string as String:
            unique(string.components(separatedBy: CharacterSet(charactersIn: ",;")))
        default:
            []
        }
    }

    private static func mangaBakaV2TagRows(from row: [String: Any]) -> [[String: Any]] {
        if let rows = row["tags_v2"] as? [[String: Any]] {
            return rows
        }
        let rows = row["tags"] as? [[String: Any]] ?? []
        let looksLikeV2 = rows.contains { entry in
            entry["is_genre"] != nil || entry["name_path"] != nil || entry["content_rating"] != nil
        }
        return looksLikeV2 ? rows : []
    }

    private static func mangaBakaLegacyTagRows(from row: [String: Any]) -> [[String: Any]] {
        let rows = row["tags"] as? [[String: Any]] ?? []
        let looksLikeV2 = rows.contains { entry in
            entry["is_genre"] != nil || entry["name_path"] != nil || entry["content_rating"] != nil
        }
        return looksLikeV2 ? [] : rows
    }

    private static func mangaBakaLegacyNamedValues(from value: Any?) -> [String] {
        guard let rows = value as? [[String: Any]] else {
            return namedValues(from: value)
        }
        let looksLikeV2 = rows.contains { row in
            row["is_genre"] != nil || row["name_path"] != nil || row["content_rating"] != nil
        }
        return looksLikeV2 ? [] : namedValues(from: rows)
    }

    private static func mangaBakaV2Names(from value: Any?) -> [String] {
        namedValues(from: value)
    }

    private static func mangaBakaV2TagNames(from rows: [[String: Any]], isGenre: Bool) -> [String] {
        unique(rows.compactMap { row in
            guard bool(row["is_genre"]) == isGenre else { return nil }
            return text(row["name"])
        })
    }

    private static func mangaBakaV2ContentWarningNames(from rows: [[String: Any]]) -> [String] {
        unique(rows.compactMap { row in
            guard let name = text(row["name"]) else { return nil }
            let rating = text(row["content_rating"])?.lowercased() ?? ""
            let path = text(row["name_path"])?.lowercased() ?? ""
            guard rating == "erotica" || rating == "pornographic" || path.contains("sexual content") else {
                return nil
            }
            return name
        })
    }

    private static func taggedValues(from rows: [[String: Any]], type: String) -> [String] {
        unique(rows.compactMap { row in
            guard text(row["ttype"])?.lowercased() == type.lowercased() else { return nil }
            return text(row["name"])
        })
    }

    private static func taggedValues(from rows: [[String: Any]], excludingType type: String) -> [String] {
        unique(rows.compactMap { row in
            guard text(row["ttype"])?.lowercased() != type.lowercased() else { return nil }
            return text(row["name"])
        })
    }

    private static func staffNames(from rows: [[String: Any]], role: String) -> [String] {
        unique(rows.compactMap { row in
            guard text(row["role_type"])?.lowercased() == role.lowercased() else { return nil }
            return text(row["romaji"]) ?? text(row["name"])
        })
    }

    private static func subjectValues(from value: Any?, prefix: String) -> [String] {
        unique(stringValues(from: value).compactMap { rawValue in
            guard rawValue.lowercased().hasPrefix(prefix.lowercased()) else { return nil }
            let cleaned = String(rawValue.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? nil : cleaned
        })
    }

    private static func subjectValues(from value: Any?, excludingPrefixes prefixes: [String]) -> [String] {
        unique(stringValues(from: value).compactMap { rawValue in
            if prefixes.contains(where: { rawValue.lowercased().hasPrefix($0.lowercased()) }) {
                return nil
            }
            return cleanSubject(rawValue)
        })
    }

    private static func cleanSubject(_ rawValue: String) -> String {
        let knownPrefixes = ["form:", "series:", "franchise:", "subject:"]
        for prefix in knownPrefixes where rawValue.lowercased().hasPrefix(prefix.lowercased()) {
            return String(rawValue.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func year(fromPackedDate value: Int?) -> Int? {
        guard let value, value >= 10000 else { return nil }
        return value / 10000
    }

    private static func year(fromDateText value: String?) -> Int? {
        guard let value,
              value.count >= 4,
              let year = Int(value.prefix(4)) else {
            return nil
        }
        return year
    }

    private static func mangaBakaCoverURL(from row: [String: Any]) -> String? {
        nestedText(row["cover"], "raw", "url")
            ?? nestedText(row["cover"], "url")
            ?? normalizedCoverURL(text(row["cover_url"]))
            ?? normalizedCoverURL(text(row["image_url"]))
    }

    private static func ranobeDBCoverURL(from row: [String: Any]) -> String? {
        if let directURL = nestedText(row["cover"], "raw", "url")
            ?? nestedText(row["cover"], "url")
            ?? normalizedCoverURL(text(row["cover_url"]))
            ?? normalizedCoverURL(text(row["image_url"]))
            ?? normalizedCoverURL(text(row["image"])) {
            return directURL
        }

        if let image = row["image"] as? [String: Any],
           let url = ranobeDBCoverURL(fromImage: image) {
            return url
        }

        if let book = row["book"] as? [String: Any],
           let url = ranobeDBCoverURL(from: book) {
            return url
        }

        if let books = row["books"] as? [[String: Any]] {
            for book in books {
                if let url = ranobeDBCoverURL(from: book) {
                    return url
                }
            }
        }

        return nil
    }

    private static func ranobeDBCoverURL(fromImage image: [String: Any]) -> String? {
        if let url = normalizedCoverURL(text(image["url"])) {
            return url
        }
        guard let filename = text(image["filename"]) else {
            return nil
        }
        if filename.hasPrefix("http://") || filename.hasPrefix("https://") || filename.hasPrefix("//") {
            return normalizedCoverURL(filename)
        }
        let trimmed = filename.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty else { return nil }
        return "https://images.ranobedb.org/\(trimmed)"
    }

    private static func providerCoverURL(from row: [String: Any]) -> String? {
        nestedText(row["image"], "raw", "url")
            ?? nestedText(row["image"], "url")
            ?? nestedText(row["cover"], "raw", "url")
            ?? nestedText(row["cover"], "url")
            ?? normalizedCoverURL(text(row["url"]))
            ?? normalizedCoverURL(text(row["cover_url"]))
            ?? normalizedCoverURL(text(row["image_url"]))
    }

    private static func nestedValue(_ value: Any?, _ path: String...) -> Any? {
        var current = value
        for key in path {
            guard let dictionary = current as? [String: Any] else { return nil }
            current = dictionary[key]
        }
        return current
    }

    private static func mangaBakaCoverRole(type: String?, note: String?) -> SableLibraryProviderCoverRole {
        let normalizedType = type?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let normalizedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let combined = [normalizedType, normalizedNote].joined(separator: " ")

        if normalizedType.contains("back") {
            return .backCover
        }
        if containsAny(combined, ["audiobook", "audio book", "audible", "オーディオ"]) {
            return .audiobook
        }
        if containsAny(combined, ["special", "特別", "特装", "限定", "小冊子", "booklet"]) {
            return .specialEdition
        }
        if containsAny(combined, ["bonus", "extra", "obi", "帯付き", "with obi"]) {
            return .bonus
        }
        if normalizedType == "other" {
            return .bonus
        }
        if containsAny(combined, ["alternative", "alternate", "variant", "2nd edition", "second edition", "new edition", "bunkoban", "文庫"]) {
            return .alternativeEdition
        }
        if normalizedType == "volume" || normalizedType.isEmpty {
            return .normal
        }
        return .other
    }

    private static func containsAny(_ haystack: String, _ needles: [String]) -> Bool {
        needles.contains { haystack.contains($0) }
    }

    private static func coverQuality(width: Int?, height: Int?, byteCount: Int?) -> SableLibraryProviderCoverQuality {
        let longestSide = max(width ?? 0, height ?? 0)
        let shortestSide = min(width ?? 0, height ?? 0)
        if longestSide == 0, shortestSide == 0 {
            return .unknown
        }
        if shortestSide < 500 || longestSide < 800 {
            return .lowResolution
        }
        if longestSide >= 1800 || (byteCount ?? 0) >= 1_000_000 {
            return .highResolution
        }
        return .usable
    }

    private static func ranobeDBCoverCandidate(
        from row: [String: Any],
        seriesID: String?
    ) -> SableLibraryProviderCoverCandidate? {
        guard let imageURL = ranobeDBCoverURL(from: row) else { return nil }
        let image = row["image"] as? [String: Any] ?? [:]
        let width = int(image["width"])
        let height = int(image["height"])
        let storeURLs = ranobeDBStoreURLs(from: row)
        let itemID = text(row["id"])
        return SableLibraryProviderCoverCandidate(
            provider: .ranobedb,
            providerSeriesID: seriesID,
            providerItemID: itemID,
            title: text(row["title"]) ?? text(row["title_orig"]),
            volumeIndex: text(row["sort_order"]),
            volumeNumber: double(row["sort_order"]),
            mediaType: "lightNovel",
            language: text(row["lang"]) ?? text(row["olang"]),
            role: .normal,
            providerType: text(row["book_type"]) ?? text(row["format"]),
            editionNote: nil,
            imageURL: imageURL,
            width: width,
            height: height,
            byteCount: nil,
            storeURLs: storeURLs,
            quality: coverQuality(width: width, height: height, byteCount: nil)
        )
    }

    private static func ranobeDBStoreURLs(from row: [String: Any]) -> [String] {
        let releaseRows = row["releases"] as? [[String: Any]] ?? []
        let keys = ["bookwalker", "amazon", "website", "rakuten"]
        return unique(releaseRows.flatMap { release in
            keys.compactMap { key in
                normalizedCoverURL(text(release[key]))
            }
        })
    }

    private static func deduplicatedCoverCandidates(
        _ candidates: [SableLibraryProviderCoverCandidate]
    ) -> [SableLibraryProviderCoverCandidate] {
        var seen = Set<String>()
        var result: [SableLibraryProviderCoverCandidate] = []
        for candidate in candidates {
            let key = [
                candidate.provider.rawValue,
                candidate.providerSeriesID ?? "",
                candidate.providerItemID ?? "",
                candidate.volumeIndex ?? "",
                candidate.language ?? "",
                candidate.role.rawValue,
                candidate.imageURL
            ].joined(separator: "|")
            guard seen.insert(key).inserted else { continue }
            result.append(candidate)
        }
        return result
    }

    private static func embeddedJSONStringValues(named key: String, in html: String) -> [String] {
        let marker = "\"\(key)\":\""
        var values: [String] = []
        var searchStart = html.startIndex

        while let markerRange = html.range(of: marker, range: searchStart..<html.endIndex) {
            var index = markerRange.upperBound
            var encoded = ""
            var trailingBackslashCount = 0

            while index < html.endIndex {
                let character = html[index]
                if character == "\"", trailingBackslashCount.isMultiple(of: 2) {
                    break
                }
                encoded.append(character)
                if character == "\\" {
                    trailingBackslashCount += 1
                } else {
                    trailingBackslashCount = 0
                }
                index = html.index(after: index)
            }

            let literal = "\"\(encoded)\""
            if let data = literal.data(using: .utf8),
               let decoded = try? JSONDecoder().decode(String.self, from: data) {
                values.append(decoded)
            }

            searchStart = index < html.endIndex ? html.index(after: index) : html.endIndex
        }

        return values
    }

    private static func openLibraryCoverURL(from row: [String: Any], isbn13: [String]) -> String? {
        if let coverID = text(row["cover_i"]) {
            return "https://covers.openlibrary.org/b/id/\(coverID)-M.jpg"
        }
        if let isbn = isbn13.first {
            return "https://covers.openlibrary.org/b/isbn/\(isbn)-M.jpg"
        }
        return nil
    }

    private static func aniListCoverURL(from media: [String: Any]) -> String? {
        nestedText(media["coverImage"], "extraLarge")
            ?? nestedText(media["coverImage"], "large")
            ?? nestedText(media["coverImage"], "medium")
    }

    private static func tmdbCoverURL(from row: [String: Any]) -> String? {
        guard let path = text(row["poster_path"]) ?? text(row["backdrop_path"]) else { return nil }
        return "https://image.tmdb.org/t/p/w185\(path)"
    }

    private static func tvmazeCoverURL(from object: [String: Any]) -> String? {
        nestedText(object["image"], "medium")
            ?? nestedText(object["image"], "original")
    }

    private static func nestedText(_ value: Any?, _ path: String...) -> String? {
        var current = value
        for key in path {
            guard let dictionary = current as? [String: Any] else { return nil }
            current = dictionary[key]
        }
        return normalizedCoverURL(text(current))
    }

    private static func normalizedCoverURL(_ value: String?) -> String? {
        guard var value else { return nil }
        if value.hasPrefix("//") {
            value = "https:" + value
        } else if value.hasPrefix("http://") {
            value = "https://" + value.dropFirst("http://".count)
        }
        return value
    }

    private static func part(
        from row: [String: Any],
        preferredTitle: String,
        fallbackNumber: Int? = nil
    ) -> SableLibraryReadingPartMetadata? {
        guard let title = text(row["title"]),
              let number = volumeNumber(in: title, preferredTitle: preferredTitle)
                ?? fallbackNumber
                ?? int(row["sort_order"]) else {
            return nil
        }
        let subtitle = subtitle(from: title, preferredTitle: preferredTitle, number: number)
        let suffix = subtitle.map { "Vol \(paddedVolume(number)) - \($0)" } ?? "Vol \(paddedVolume(number))"
        let sourceID = text(row["id"]).map { SableLibrarySourceID(provider: .ranobedb, value: $0) }
        let releaseDate = int(row["c_release_date"])
        return SableLibraryReadingPartMetadata(
            number: number,
            sourceID: sourceID,
            title: title,
            subtitle: subtitle,
            fileSuffix: suffix,
            releaseYear: year(fromPackedDate: releaseDate),
            releaseDate: releaseDate,
            description: bookDescription(from: row)
        )
    }

    private static func ranobeDBBook(
        _ book: [String: Any],
        belongsTo preferredTitle: String
    ) -> Bool {
        guard let bookTitle = text(book["title"]) else { return false }
        let local = preferredTitle.lowercased()
        let candidate = bookTitle.lowercased()

        if let partNumber = firstCapturedText(
            in: preferredTitle,
            pattern: #"(?i)\bpart\s*(\d+)\b"#
        ) {
            return firstCapturedText(
                in: bookTitle,
                pattern: #"(?i)\bpart\s*("#
                    + NSRegularExpression.escapedPattern(for: partNumber)
                    + #")\b"#
            ) != nil
        }
        if local.contains("short stor") {
            return candidate.contains("short stor")
        }
        if local.contains("fanbook") {
            return candidate.contains("fanbook")
        }
        if local.contains("another") {
            return candidate.contains("another")
        }

        if let bookType = text(book["book_type"])?.lowercased(),
           bookType != "main" {
            return false
        }
        return !containsAny(candidate, [
            "short stor",
            "side stor",
            "operation record",
            " spin-off",
            " spinoff",
            "よりみち",
            "短編集",
            "外伝",
            "番外"
        ])
    }

    private static func firstCapturedText(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: text,
                range: NSRange(text.startIndex..<text.endIndex, in: text)
              ),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }

    private static func bookDescription(from row: [String: Any]) -> String? {
        text(row["description"])
            ?? text((row["book_description"] as? [String: Any])?["description"])
    }

    private static func subtitle(from title: String, preferredTitle: String, number: Int) -> String? {
        let escapedTitle = NSRegularExpression.escapedPattern(for: preferredTitle)
        let patterns = [
            #"(?i)^\s*\#(escapedTitle)\s*,?\s*vol(?:ume)?\.?\s*0*\#(number)\s*[:\-–—]\s*(.+?)\s*$"#,
            #"(?i)^\s*.+?\s*,?\s*vol(?:ume)?\.?\s*0*\#(number)\s*[:\-–—]\s*(.+?)\s*$"#,
            #"(?i)^\s*vol(?:ume)?\.?\s*0*\#(number)\s*[:\-–—]\s*(.+?)\s*$"#,
            #"(?i)^\s*0*\#(number)\s+(.+?)\s*$"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..<title.endIndex, in: title)),
                  let subtitleRange = Range(match.range(at: match.numberOfRanges - 1), in: title) else {
                continue
            }
            let subtitle = sanitizePartTitle(String(title[subtitleRange]))
            if !subtitle.isEmpty {
                return subtitle
            }
        }
        return nil
    }

    private static func volumeNumber(in title: String, preferredTitle: String) -> Int? {
        let escapedTitle = NSRegularExpression.escapedPattern(for: preferredTitle)
        let patterns = [
            #"(?i)^\s*\#(escapedTitle)\s*,?\s*vol(?:ume)?\.?\s*(\d{1,4})"#,
            #"(?i)\bvol(?:ume)?\.?\s*(\d{1,4})\b"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..<title.endIndex, in: title)),
                  let range = Range(match.range(at: 1), in: title),
                  let number = Int(title[range]) else {
                continue
            }
            return number
        }
        return nil
    }

    private static func paddedVolume(_ number: Int) -> String {
        number < 10 ? "0\(number)" : "\(number)"
    }

    private static func sanitizePartTitle(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".-:")))
    }

    nonisolated private static func normalizedISBN13(_ value: String) -> String? {
        let cleaned = value
            .uppercased()
            .filter { $0.isNumber || $0 == "X" }

        if cleaned.count == 13,
           cleaned.allSatisfy(\.isNumber),
           cleaned.hasPrefix("978") || cleaned.hasPrefix("979") {
            return cleaned
        }

        guard cleaned.count == 10,
              isValidISBN10(cleaned) else {
            return nil
        }

        let prefix = "978" + cleaned.prefix(9)
        let checkSum = prefix.enumerated().reduce(0) { partialResult, element in
            let digit = Int(String(element.element)) ?? 0
            return partialResult + digit * (element.offset.isMultiple(of: 2) ? 1 : 3)
        }
        let checkDigit = (10 - (checkSum % 10)) % 10
        return prefix + "\(checkDigit)"
    }

    nonisolated private static func isValidISBN10(_ value: String) -> Bool {
        guard value.count == 10 else { return false }

        let weighted = value.enumerated().reduce(0) { partialResult, element in
            let digit: Int
            if element.element == "X", element.offset == 9 {
                digit = 10
            } else if let number = Int(String(element.element)) {
                digit = number
            } else {
                return partialResult + 1_000
            }
            return partialResult + digit * (10 - element.offset)
        }
        return weighted % 11 == 0
    }

    private static func bindingValue(_ key: String, in binding: [String: Any]) -> String? {
        guard let item = binding[key] as? [String: Any] else { return nil }
        return text(item["value"])
    }

    private static func wikidataEntityID(from value: String?) -> String? {
        guard let value,
              let last = value.split(separator: "/").last,
              last.first == "Q" else {
            return nil
        }
        return String(last)
    }

    private static func openLibrarySourceID(from value: String) -> SableLibrarySourceID? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard trimmed.range(of: #"^OL\d+[WM]$"#, options: .regularExpression) != nil else {
            return nil
        }
        let path = trimmed.hasSuffix("W") ? "/works/\(trimmed)" : "/books/\(trimmed)"
        return SableLibrarySourceID(provider: .openLibrary, value: path)
    }

    private static func wikidataMediaType(in binding: [String: Any]) -> String? {
        if let mediaType = bindingValue("mediaType", in: binding) {
            return mediaType
        }
        if bindingValue("bookMediaType", in: binding) != nil
            || bindingValue("bookType", in: binding) != nil {
            return "book"
        }
        if bindingValue("movieType", in: binding) != nil {
            return "movie"
        }
        if bindingValue("tvSeriesType", in: binding) != nil
            || bindingValue("televisionType", in: binding) != nil
            || bindingValue("animeType", in: binding) != nil {
            return "tv"
        }
        if bindingValue("tmdbMovie", in: binding) != nil,
           bindingValue("tmdbTV", in: binding) == nil,
           bindingValue("tvdb", in: binding) == nil {
            return "movie"
        }
        if bindingValue("tmdbTV", in: binding) != nil || bindingValue("tvdb", in: binding) != nil {
            return "tv"
        }
        return nil
    }

    private static func wikidataCandidateIdentity(_ candidate: SableLibraryProviderCandidate) -> String {
        if let sourceID = candidate.sourceIDs.first(where: { $0.provider == .wikidata }) {
            return sourceID.stableKey
        }
        return "wikidata:\(candidate.title):\(candidate.year.map(String.init) ?? "")"
    }

    private static func mergedWikidataCandidate(
        _ lhs: SableLibraryProviderCandidate,
        _ rhs: SableLibraryProviderCandidate
    ) -> SableLibraryProviderCandidate {
        SableLibraryProviderCandidate(
            provider: .wikidata,
            title: lhs.title,
            year: lhs.year ?? rhs.year,
            mediaType: lhs.mediaType ?? rhs.mediaType,
            sourceIDs: uniqueSourceIDs(lhs.sourceIDs + rhs.sourceIDs),
            isbn13: unique(lhs.isbn13 + rhs.isbn13),
            aliases: unique(lhs.aliases + rhs.aliases),
            description: lhs.description ?? rhs.description,
            genres: unique(lhs.genres + rhs.genres),
            tags: unique(lhs.tags + rhs.tags),
            contentWarnings: unique(lhs.contentWarnings + rhs.contentWarnings),
            studios: unique(lhs.studios + rhs.studios),
            authors: unique(lhs.authors + rhs.authors),
            artists: unique(lhs.artists + rhs.artists),
            publishers: unique(lhs.publishers + rhs.publishers),
            languages: unique(lhs.languages + rhs.languages),
            status: lhs.status ?? rhs.status,
            contentRating: lhs.contentRating ?? rhs.contentRating,
            coverURL: lhs.coverURL ?? rhs.coverURL
        )
    }

    private static func uniqueSourceIDs(_ ids: [SableLibrarySourceID]) -> [SableLibrarySourceID] {
        var seen = Set<String>()
        return ids.filter { id in
            seen.insert(id.stableKey).inserted
        }
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let key = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            return seen.insert(key).inserted ? trimmed : nil
        }
    }
}
