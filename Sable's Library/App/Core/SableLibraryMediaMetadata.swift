//
//  SableLibraryMediaMetadata.swift
//  Sable's Library
//

import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

indirect enum SableLibraryJSONValue: Sendable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([SableLibraryJSONValue])
    case object([String: SableLibraryJSONValue])

    nonisolated static func from(_ value: Any?) -> SableLibraryJSONValue? {
        guard let value else { return nil }
        if value is NSNull { return .null }
        if let value = value as? Bool { return .bool(value) }
        if let value = value as? Int { return .int(value) }
        if let value = value as? Double { return .double(value) }
        if let value = value as? Float { return .double(Double(value)) }
        if let value = value as? String { return .string(value) }
        if let value = value as? NSNumber {
            if value === kCFBooleanTrue || value === kCFBooleanFalse {
                return .bool(value.boolValue)
            }
            let double = value.doubleValue
            if double.isFinite,
               double.rounded() == double,
               double >= Double(Int.min),
               double <= Double(Int.max) {
                return .int(value.intValue)
            }
            return .double(double)
        }
        if let values = value as? [Any] {
            return .array(values.map { SableLibraryJSONValue.from($0) ?? .null })
        }
        if let object = value as? [String: Any] {
            return .object(
                object.reduce(into: [String: SableLibraryJSONValue]()) { partialResult, item in
                    partialResult[item.key] = SableLibraryJSONValue.from(item.value) ?? .null
                }
            )
        }
        return nil
    }

    nonisolated var foundationValue: Any {
        switch self {
        case .null:
            return NSNull()
        case .bool(let value):
            return value
        case .int(let value):
            return value
        case .double(let value):
            return value
        case .string(let value):
            return value
        case .array(let values):
            return values.map(\.foundationValue)
        case .object(let object):
            return object.mapValues(\.foundationValue)
        }
    }
}

nonisolated enum SableLibraryMediaDomain: String, Codable, Sendable {
    case reading
    case watching
    case unknown
}

enum SableLibraryCleanupKind: String, Codable, Sendable, CaseIterable {
    case reading
    case watching
    case document
    case image
    case audio
    case archive
    case other

    var folderName: String {
        switch self {
        case .reading: "Books"
        case .watching: "Videos"
        case .document: "Documents"
        case .image: "Images"
        case .audio: "Audio"
        case .archive: "Archives"
        case .other: "Other"
        }
    }

    var mediaDomain: SableLibraryMediaDomain {
        switch self {
        case .reading: .reading
        case .watching: .watching
        case .document, .image, .audio, .archive, .other: .unknown
        }
    }
}

enum SableLibraryReadingType: String, Codable, Sendable {
    case manga
    case manhwa
    case manhua
    case oel
    case lightNovel
    case novel
    case book
    case comic
    case unknown

    var folderName: String {
        switch self {
        case .manga: "Manga"
        case .manhwa: "Manhwa"
        case .manhua: "Manhua"
        case .oel: "OEL"
        case .lightNovel: "Light Novels"
        case .novel: "Novels"
        case .book: "Books"
        case .comic: "Comics"
        case .unknown: "Other Reading"
        }
    }
}

enum SableLibraryWatchingType: String, Codable, Sendable {
    case animeTV
    case animeMovie
    case ova
    case ona
    case special
    case movie
    case tvShow
    case unknownVideo

    var folderName: String {
        switch self {
        case .animeTV: "TV"
        case .animeMovie: "Movies"
        case .ova: "TV"
        case .ona: "TV"
        case .special: "TV"
        case .movie: "Movies"
        case .tvShow: "TV"
        case .unknownVideo: "Other Videos"
        }
    }
}

nonisolated enum SableLibraryMetadataProvider: String, Codable, CaseIterable, Sendable {
    case mangabaka
    case ranobedb
    case openLibrary
    case myAnimeList
    case anilist
    case tvmaze
    case wikidata
    case tmdb
    case tvdb
    case imdb
    case local

    var displayName: String {
        switch self {
        case .mangabaka: "MangaBaka"
        case .ranobedb: "RanobeDB"
        case .openLibrary: "Open Library"
        case .myAnimeList: "MyAnimeList"
        case .anilist: "AniList"
        case .tvmaze: "TVmaze"
        case .wikidata: "Wikidata"
        case .tmdb: "TMDB"
        case .tvdb: "TVDB"
        case .imdb: "IMDb"
        case .local: "Local"
        }
    }
}

enum SableLibraryQuietOutcome: String, Codable, Sendable {
    case safeApply
    case leaveUntouched
    case needsAttention
}

enum SableLibraryMatchEvidenceKind: String, Codable, Sendable {
    case exactProviderID
    case exactISBN
    case providerBridge
    case titleSimilarity
    case yearMatch
    case typeMatch
    case volumeOrEpisodeMatch
    case localSidecar
    case userCorrection
}

struct SableLibrarySourceID: Codable, Sendable, Hashable {
    var provider: SableLibraryMetadataProvider
    var value: String

    var stableKey: String {
        "\(provider.rawValue):\(value)"
    }
}

enum SableLibraryManualProviderIDParser {
    nonisolated static func sourceID(provider: SableLibraryMetadataProvider, from input: String) -> SableLibrarySourceID? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let value: String?
        switch provider {
        case .mangabaka:
            value = SableLibraryMangaBakaIDParser.id(from: trimmed)
        case .ranobedb:
            value = SableLibraryRanobeDBIDParser.id(from: trimmed)
        case .openLibrary:
            value = openLibraryID(from: trimmed)
        case .myAnimeList, .anilist, .tmdb, .tvdb, .tvmaze:
            value = firstMatch(in: trimmed, pattern: #"\b\d{2,}\b"#) ?? (trimmed.range(of: #"^\d+$"#, options: .regularExpression) == nil ? nil : trimmed)
        case .wikidata:
            value = firstMatch(in: trimmed, pattern: #"(?i)\bQ\d+\b"#)?.uppercased()
        case .imdb:
            value = firstMatch(in: trimmed, pattern: #"(?i)\btt\d{6,}\b"#)?.lowercased()
        case .local:
            value = nil
        }

        guard let cleanValue = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !cleanValue.isEmpty else {
            return nil
        }
        return SableLibrarySourceID(provider: provider, value: cleanValue)
    }

    nonisolated private static func openLibraryID(from input: String) -> String? {
        if let workOrBook = firstMatch(in: input, pattern: #"(?i)/(?:works|books)/OL\d+[WM]"#) {
            return workOrBook.replacingOccurrences(of: #"(?i)^https?://[^/]+"#, with: "", options: .regularExpression)
        }
        if let olid = firstMatch(in: input, pattern: #"(?i)\bOL\d+[WM]\b"#)?.uppercased() {
            return olid.hasSuffix("W") ? "/works/\(olid)" : "/books/\(olid)"
        }
        return nil
    }

    nonisolated private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
              let range = Range(match.range, in: text) else {
            return nil
        }
        return String(text[range])
    }
}

enum SableLibrarySourceIDParser {
    nonisolated static let legacyTopLevelIDKeys: [(String, SableLibraryMetadataProvider)] = [
        ("mangabaka_id", .mangabaka),
        ("ranobedb_id", .ranobedb),
        ("openlibrary_id", .openLibrary),
        ("open_library_id", .openLibrary),
        ("mal_id", .myAnimeList),
        ("myanimelist_id", .myAnimeList),
        ("my_anime_list_id", .myAnimeList),
        ("anilist_id", .anilist),
        ("tvmaze_id", .tvmaze),
        ("wikidata_id", .wikidata),
        ("tmdb_id", .tmdb),
        ("tvdb_id", .tvdb),
        ("imdb_id", .imdb)
    ]

    nonisolated static func sourceIDs(
        from sidecar: [String: Any],
        extraIDs: [SableLibrarySourceID] = [],
        textValue: (Any?) -> String?
    ) -> [SableLibrarySourceID] {
        var ids: [SableLibrarySourceID] = []

        for (key, provider) in legacyTopLevelIDKeys {
            append(SableLibrarySourceID(provider: provider, value: textValue(sidecar[key]) ?? ""), to: &ids)
        }

        if let rawIDs = sidecar["ids"] as? [String: Any] {
            for (key, value) in rawIDs {
                guard let provider = provider(from: key) ?? provider(fromAmbiguousIDKey: key),
                      let id = textValue(value) else {
                    continue
                }
                append(SableLibrarySourceID(provider: provider, value: id), to: &ids)
            }
        }

        if let sable = sidecar["_sable"] as? [String: Any],
           let ranobe = sable["ranobedb"] as? [String: Any],
            let seriesID = extractProviderID(
                from: ranobe,
                keys: [
                    "id",
                    "series_id",
                    "seriesId",
                    "seriesid",
                    "ranobedb_id",
                    "ranobedbid",
                    "ranobedbId",
                    "rdb"
                ]
            ) {
            append(SableLibrarySourceID(provider: .ranobedb, value: seriesID), to: &ids)
        }
        if let sable = sidecar["_sable"] as? [String: Any],
           let mangaBaka = sable["mangabaka"] as? [String: Any] {
            if let manualID = textValue(mangaBaka["manual_series_id"]) {
                append(SableLibrarySourceID(provider: .mangabaka, value: manualID), to: &ids)
            }
            if let matchedID = textValue(mangaBaka["matched_id"]) {
                append(SableLibrarySourceID(provider: .mangabaka, value: matchedID), to: &ids)
            }
        }

        for extraID in extraIDs {
            append(extraID, to: &ids)
        }

        return ids
    }

    nonisolated static func folderHints(in folderName: String) -> [SableLibrarySourceID] {
        var ids: [SableLibrarySourceID] = []
        var searchStart = folderName.startIndex

        while let openBrace = folderName[searchStart...].firstIndex(of: "{") {
            let contentStart = folderName.index(after: openBrace)
            guard contentStart < folderName.endIndex,
                  let closeBrace = folderName[contentStart...].firstIndex(of: "}") else {
                break
            }

            let content = folderName[contentStart..<closeBrace]
            if let separator = content.firstIndex(of: "-") {
                let providerText = String(content[..<separator])
                let valueStart = content.index(after: separator)
                if valueStart < content.endIndex,
                   isFolderHintProvider(providerText),
                   let provider = provider(from: providerText) {
                    let value = String(content[valueStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    append(SableLibrarySourceID(provider: provider, value: value), to: &ids)
                }
            }

            searchStart = folderName.index(after: closeBrace)
        }

        return ids
    }

    nonisolated static func provider(from key: String) -> SableLibraryMetadataProvider? {
        switch key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "mb", "mangabaka": .mangabaka
        case "rdb", "ranobedb": .ranobedb
        case "ol", "openlibrary", "open_library": .openLibrary
        case "mal", "myanimelist", "my_anime_list": .myAnimeList
        case "anilist", "al": .anilist
        case "tvmaze": .tvmaze
        case "wikidata", "wd": .wikidata
        case "tmdb": .tmdb
        case "tvdb": .tvdb
        case "imdb": .imdb
        case "local": .local
        default: nil
        }
    }

    nonisolated private static func provider(fromAmbiguousIDKey key: String) -> SableLibraryMetadataProvider? {
        let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")

        switch normalized {
        case "seriesid", "rdbid", "ranobedbid", "ranobedb":
            return .ranobedb
        case "mangabakaid", "mbid":
            return .mangabaka
        case "openlibraryid", "olid":
            return .openLibrary
        case "malid", "myanimelistid":
            return .myAnimeList
        case "anilistid", "alid":
            return .anilist
        default:
            return nil
        }
    }

    nonisolated private static func extractProviderID(from object: [String: Any], keys: [String]) -> String? {
        let wanted = Set(keys.map { key in
            key.trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .replacingOccurrences(of: "_", with: "")
                .replacingOccurrences(of: "-", with: "")
        })
        for (key, value) in object {
            let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .replacingOccurrences(of: "_", with: "")
                .replacingOccurrences(of: "-", with: "")

            guard wanted.contains(normalizedKey) else {
                continue
            }
            if let id = value as? String {
                let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            } else if let id = value as? NSNumber {
                return id.stringValue
            }
        }
        return nil
    }

    nonisolated private static func append(_ sourceID: SableLibrarySourceID, to ids: inout [SableLibrarySourceID]) {
        guard !sourceID.value.isEmpty,
              !ids.contains(where: { $0.provider == sourceID.provider && $0.value == sourceID.value }) else {
            return
        }
        ids.append(sourceID)
    }

    nonisolated private static func isFolderHintProvider(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            let code = scalar.value
            return (65...90).contains(code) || (97...122).contains(code) || code == 95
        }
    }
}

enum SableLibraryProviderQueryCleaner {
    nonisolated static func searchTitle(from title: String) -> String? {
        var cleaned = title.replacingOccurrences(of: "_", with: " ")
        var changed = true

        while changed {
            changed = false
            if let next = sourceIDStrippedTitle(from: cleaned) {
                cleaned = next
                changed = true
            }
            if let next = yearStrippedTitle(from: cleaned) {
                cleaned = next
                changed = true
            }
            if let next = volumeStrippedTitle(from: cleaned) {
                cleaned = next
                changed = true
            }
            if let next = typeHintStrippedTitle(from: cleaned) {
                cleaned = next
                changed = true
            }
        }

        cleaned = compactWhitespace(cleaned)
        return cleaned.isEmpty ? nil : cleaned
    }

    nonisolated static func searchTitles(
        from titles: [String],
        limit: Int = 8,
        includeLooseVariants: Bool = false
    ) -> [String] {
        var values: [String] = []
        for title in titles {
            append(searchTitle(from: title), to: &values)
            guard includeLooseVariants else { continue }
            for variant in looseVariants(from: title) {
                append(searchTitle(from: variant), to: &values)
            }
        }
        return Array(values.prefix(max(0, limit)))
    }

    nonisolated private static func looseVariants(from title: String) -> [String] {
        guard let base = searchTitle(from: title) else { return [] }
        var variants: [String] = []

        if base.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
            .range(of: #"^\d{4}$"#, options: .regularExpression) != nil {
            let compact = base.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
            variants.append("\(compact.prefix(2)):\(compact.suffix(2))")
        }

        if base.range(of: #"(?i)\bre\s*:?\s*zero\b"#, options: .regularExpression) != nil {
            variants.append(
                base.replacingOccurrences(
                    of: #"(?i)\bre\s*:?\s*zero\b"#,
                    with: "Re:Zero",
                    options: .regularExpression
                )
            )
        }

        let fanbookReplacements: [(String, String)] = [
            (#"(?i)\bofficial\s+fan\s*book\b"#, "Fanbook"),
            (#"(?i)\bofficial\s+fanbook\b"#, "Fanbook"),
            (#"(?i)\bfanbook\b"#, "Fan Book"),
            (#"(?i)\bfan\s+book\b"#, "Fanbook")
        ]
        for (pattern, replacement) in fanbookReplacements {
            variants.append(base.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression))
        }

        return variants.filter { normalizedKey($0) != normalizedKey(base) }
    }

    nonisolated private static func sourceIDStrippedTitle(from title: String) -> String? {
        stripped(
            title.replacingOccurrences(
                of: #"(?i)\s*\{(?:mb|mangabaka|rdb|ranobedb|ol|openlibrary|open_library|mal|myanimelist|my_anime_list|anilist|al|tvmaze|wikidata|wd|tmdb|tvdb|imdb|local)-[^}]+\}\s*"#,
                with: " ",
                options: .regularExpression
            ),
            original: title
        )
    }

    nonisolated private static func yearStrippedTitle(from title: String) -> String? {
        stripped(
            title.replacingOccurrences(
                of: #"\s*[\(\[]\d{4}[\)\]]\s*$"#,
                with: "",
                options: .regularExpression
            ),
            original: title
        )
    }

    nonisolated private static func volumeStrippedTitle(from title: String) -> String? {
        stripped(
            title.replacingOccurrences(
                of: #"(?i)\s*[-–—:]?\s*(?:vol(?:ume)?|book|part|chapter|ch)\.?\s*0*\d{1,4}(?:\.\d+)?(?:\s*[-–—:]\s*.+)?\s*$"#,
                with: "",
                options: .regularExpression
            ),
            original: title
        )
    }

    nonisolated private static func typeHintStrippedTitle(from title: String) -> String? {
        stripped(
            title.replacingOccurrences(
                of: #"(?i)\s*(?:\(|-|the\s+)?\s*(?:novel|light\s+novel|manga|manhwa|manhua|comic|comics|ebook|epub|oel|anime|anime\s+tv|anime\s+movie|ova|ona|special|movie|movies|tv|tv\s+show)\)?\s*$"#,
                with: "",
                options: .regularExpression
            ),
            original: title
        )
    }

    nonisolated private static func stripped(_ value: String, original: String) -> String? {
        let cleaned = compactWhitespace(value)
        guard !cleaned.isEmpty, cleaned != compactWhitespace(original) else { return nil }
        return cleaned
    }

    nonisolated private static func append(_ value: String?, to values: inout [String]) {
        guard let value else { return }
        let cleaned = compactWhitespace(value)
        guard !cleaned.isEmpty else { return }
        let key = normalizedKey(cleaned)
        guard !values.contains(where: { normalizedKey($0) == key }) else { return }
        values.append(cleaned)
    }

    nonisolated private static func compactWhitespace(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func normalizedKey(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct SableLibraryMatchEvidence: Codable, Sendable, Hashable {
    var kind: SableLibraryMatchEvidenceKind
    var provider: SableLibraryMetadataProvider
    var value: String
    var confidence: Double
}

struct SableLibraryProviderFreshness: Codable, Sendable, Hashable {
    var provider: SableLibraryMetadataProvider
    var fetchedAt: String
    var ttlSeconds: TimeInterval

    func isFresh(now: Date = Date()) -> Bool {
        guard let fetchedDate = ISO8601DateFormatter().date(from: fetchedAt) else { return false }
        return now.timeIntervalSince(fetchedDate) <= ttlSeconds
    }
}

struct SableLibraryReadingPartMetadata: Codable, Sendable, Hashable {
    var number: Int
    var sourceID: SableLibrarySourceID?
    var title: String
    var subtitle: String?
    var fileSuffix: String
    var releaseYear: Int?
    var releaseDate: Int?
    var isbn13: [String]
    var releaseIDs: [String]
    var pages: Int?
    var description: String?

    init(
        number: Int,
        sourceID: SableLibrarySourceID? = nil,
        title: String,
        subtitle: String? = nil,
        fileSuffix: String,
        releaseYear: Int? = nil,
        releaseDate: Int? = nil,
        isbn13: [String] = [],
        releaseIDs: [String] = [],
        pages: Int? = nil,
        description: String? = nil
    ) {
        self.number = number
        self.sourceID = sourceID
        self.title = title
        self.subtitle = subtitle
        self.fileSuffix = fileSuffix
        self.releaseYear = releaseYear
        self.releaseDate = releaseDate
        self.isbn13 = isbn13
        self.releaseIDs = releaseIDs
        self.pages = pages
        self.description = description
    }
}

struct SableLibraryIdentityGraph: Codable, Sendable, Hashable {
    var domain: SableLibraryMediaDomain
    var preferredTitle: String
    var sortTitle: String?
    var year: Int?
    var readingType: SableLibraryReadingType?
    var watchingType: SableLibraryWatchingType?
    var sourceIDs: [SableLibrarySourceID]
    var isbn13: [String]
    var aliases: [String]
    var evidence: [SableLibraryMatchEvidence]
    var freshness: [SableLibraryProviderFreshness]

    init(
        domain: SableLibraryMediaDomain,
        preferredTitle: String,
        sortTitle: String? = nil,
        year: Int? = nil,
        readingType: SableLibraryReadingType? = nil,
        watchingType: SableLibraryWatchingType? = nil,
        sourceIDs: [SableLibrarySourceID] = [],
        isbn13: [String] = [],
        aliases: [String] = [],
        evidence: [SableLibraryMatchEvidence] = [],
        freshness: [SableLibraryProviderFreshness] = []
    ) {
        self.domain = domain
        self.preferredTitle = preferredTitle
        self.sortTitle = sortTitle
        self.year = year
        self.readingType = readingType
        self.watchingType = watchingType
        self.sourceIDs = sourceIDs
        self.isbn13 = isbn13
        self.aliases = aliases
        self.evidence = evidence
        self.freshness = freshness
    }
}

struct SableLibraryQuietDecision: Sendable, Equatable {
    var outcome: SableLibraryQuietOutcome
    var score: Double
    var reason: String
}

struct SableLibraryConfidenceEngine: Sendable {
    var safeApplyThreshold = 0.94
    var needsAttentionThreshold = 0.82

    func decide(evidence: [SableLibraryMatchEvidence], hasCollision: Bool = false, hasMissingRequiredCredential: Bool = false) -> SableLibraryQuietDecision {
        if hasCollision {
            return SableLibraryQuietDecision(outcome: .needsAttention, score: 0, reason: "A destination already exists.")
        }
        if hasMissingRequiredCredential {
            return SableLibraryQuietDecision(outcome: .needsAttention, score: 0, reason: "A required provider key is missing.")
        }

        let score = combinedScore(evidence)
        if score >= safeApplyThreshold {
            return SableLibraryQuietDecision(outcome: .safeApply, score: score, reason: "Strong source evidence is enough for a reversible change.")
        }
        if score >= needsAttentionThreshold, evidence.contains(where: { $0.kind == .titleSimilarity }) {
            return SableLibraryQuietDecision(outcome: .needsAttention, score: score, reason: "The match is close but still depends on fuzzy title evidence.")
        }
        return SableLibraryQuietDecision(outcome: .leaveUntouched, score: score, reason: "Evidence is not strong enough for automatic changes.")
    }

    func combinedScore(_ evidence: [SableLibraryMatchEvidence]) -> Double {
        guard !evidence.isEmpty else { return 0 }
        if evidence.contains(where: { $0.kind == .exactProviderID || $0.kind == .exactISBN }) {
            return min(1, evidence.map(\.confidence).max() ?? 0.98)
        }

        var weighted = 0.0
        var weightTotal = 0.0
        for item in evidence {
            let weight = weight(for: item.kind)
            weighted += item.confidence * weight
            weightTotal += weight
        }
        guard weightTotal > 0 else { return 0 }
        return min(1, weighted / weightTotal)
    }

    func titleSimilarity(_ lhs: String, _ rhs: String) -> Double {
        let normalizedLHS = normalize(lhs)
        let normalizedRHS = normalize(rhs)
        guard !normalizedLHS.isEmpty, !normalizedRHS.isEmpty else { return 0 }
        if normalizedLHS == normalizedRHS { return 1 }
        if normalizedLHS.contains(normalizedRHS) || normalizedRHS.contains(normalizedLHS) {
            return 0.86
        }

        #if canImport(NaturalLanguage)
        if let embedding = NLEmbedding.sentenceEmbedding(for: .english) {
            let distance = embedding.distance(between: normalizedLHS, and: normalizedRHS, distanceType: .cosine)
            if distance.isFinite {
                return min(1, max(tokenSimilarity(normalizedLHS, normalizedRHS), 1 - distance))
            }
        }
        #endif

        return tokenSimilarity(normalizedLHS, normalizedRHS)
    }

    private func weight(for kind: SableLibraryMatchEvidenceKind) -> Double {
        switch kind {
        case .exactProviderID, .exactISBN: 1.0
        case .providerBridge: 0.92
        case .localSidecar, .userCorrection: 0.88
        case .typeMatch: 0.62
        case .yearMatch: 0.56
        case .volumeOrEpisodeMatch: 0.52
        case .titleSimilarity: 0.42
        }
    }

    private func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func tokenSimilarity(_ lhs: String, _ rhs: String) -> Double {
        let lhsTokens = Set(lhs.split(separator: " ").map(String.init))
        let rhsTokens = Set(rhs.split(separator: " ").map(String.init))
        guard !lhsTokens.isEmpty, !rhsTokens.isEmpty else { return 0 }
        let overlap = lhsTokens.intersection(rhsTokens).count
        let union = lhsTokens.union(rhsTokens).count
        return union == 0 ? 0 : Double(overlap) / Double(union)
    }
}

nonisolated enum SableLibraryMLTrainingEventKind: String, Codable, Sendable {
    case acceptedAutomaticMatch
    case cleanupKindCorrection
    case finalSuccessfulPlanRow
    case rawReadingLaneCorrection
    case skippedAmbiguousMatch
    case manualIDEntry
    case restoredRename
    case providerDisagreement
    case finalSuccessfulSidecar
}

nonisolated struct SableLibraryMLTrainingEvent: Codable, Sendable, Hashable {
    var kind: SableLibraryMLTrainingEventKind
    var createdAt: String
    var domain: SableLibraryMediaDomain
    var localPathHash: String
    var provider: SableLibraryMetadataProvider?
    var confidenceScore: Double
    var featureSummary: [String: String]

    static func make(
        kind: SableLibraryMLTrainingEventKind,
        domain: SableLibraryMediaDomain,
        localPath: String,
        provider: SableLibraryMetadataProvider? = nil,
        confidenceScore: Double,
        featureSummary: [String: String] = [:],
        now: Date = Date()
    ) -> SableLibraryMLTrainingEvent {
        SableLibraryMLTrainingEvent(
            kind: kind,
            createdAt: ISO8601DateFormatter().string(from: now),
            domain: domain,
            localPathHash: stableLocalPathHash(localPath),
            provider: provider,
            confidenceScore: confidenceScore,
            featureSummary: featureSummary
        )
    }

    private static func stableLocalPathHash(_ value: String) -> String {
        #if canImport(CryptoKit)
        return SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        #else
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: max(0, 16 - hex.count)) + hex
        #endif
    }
}
