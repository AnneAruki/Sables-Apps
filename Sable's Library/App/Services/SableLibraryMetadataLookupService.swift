//
//  SableLibraryMetadataLookupService.swift
//  Sable's Library
//

import Foundation

struct SableLibraryMetadataEnrichment: Sendable, Equatable {
    var preferredTitle: String
    var year: Int?
    var mediaType: String?
    var sourceIDs: [SableLibrarySourceID]
    var aliases: [String]
    var description: String?
    var genres: [String] = []
    var tags: [String] = []
    var contentWarnings: [String] = []
    var studios: [String] = []
    var authors: [String] = []
    var artists: [String] = []
    var publishers: [String] = []
    var languages: [String] = []
    var status: String?
    var contentRating: String?
    var coverURL: String?
    var isbn13: [String]
    var readingParts: [SableLibraryReadingPartMetadata]
    var evidence: [SableLibraryMatchEvidence]
    var freshness: [SableLibraryProviderFreshness]
    var confidenceScore: Double
    var providersUsed: [SableLibraryMetadataProvider]
    var providerPayloads: [String: SableLibraryJSONValue] = [:]
}

private struct RanobeDBBookDetailEnrichment: Sendable {
    var parts: [SableLibraryReadingPartMetadata]
    var apiBookResponses: [SableLibraryJSONValue]
    var requestedBookIDs: [String]
    var fetchedBookIDs: [String]
    var failedBookIDs: [String]
}

struct SableLibraryMetadataLookupService: Sendable {
    private let planner = SableLibraryProviderGraphPlanner()
    private let confidenceEngine = SableLibraryConfidenceEngine()

    func manualSearchCandidates(
        provider: SableLibraryMetadataProvider,
        query rawQuery: String,
        preferredAniListMediaTypes: [String] = [],
        config: SableLibraryConfig,
        service: SableLibraryService
    ) async -> [SableLibraryProviderCandidate] {
        let queries = providerSearchTitles(rawQuery, service: service, limit: 4)
        guard !queries.isEmpty else { return [] }

        var candidates: [SableLibraryProviderCandidate] = []

        switch provider {
        case .mangabaka:
            for query in queries {
                if let request = planner.searchRequest(provider: .mangabaka, query: query, config: config),
                   let object = try? await jsonObject(for: request) {
                    candidates.append(contentsOf: SableLibraryProviderCandidateParser.mangaBakaCandidates(from: object))
                }
                if candidates.count >= 10 { break }
            }
        case .ranobedb:
            if let providerConfig = planner.providerConfig(for: .ranobedb, config: config) {
                for query in queries {
                    if let request = ranobeDBSeriesSearchRequest(query: query, providerConfig: providerConfig),
                       let object = try? await jsonObject(for: request) {
                        candidates.append(contentsOf: SableLibraryProviderCandidateParser.ranobeDBSeriesCandidates(from: object))
                    }
                    if candidates.count >= 10 { break }
                }
                candidates = await ranobeDBManualCandidatesWithCovers(candidates, providerConfig: providerConfig)
            }
        case .openLibrary:
            if let providerConfig = planner.providerConfig(for: .openLibrary, config: config) {
                for query in queries.prefix(3) {
                    for request in openLibraryTitleRequests(title: query, authors: [], providerConfig: providerConfig).prefix(1) {
                        guard let object = try? await jsonObject(for: request) else { continue }
                        candidates.append(contentsOf: SableLibraryProviderCandidateParser.openLibraryCandidates(from: object))
                    }
                    if candidates.count >= 10 { break }
                }
            }
        case .myAnimeList:
            candidates = []
        case .anilist:
            let mediaTypes = normalizedCatalogMediaTypes(preferredAniListMediaTypes)
            for query in queries {
                for mediaType in mediaTypes.isEmpty ? ["MANGA", "ANIME"] : mediaTypes {
                    if let matches = try? await aniListCandidates(title: query, mediaType: mediaType, config: config) {
                        candidates.append(contentsOf: matches)
                    }
                }
                if candidates.count >= 10 { break }
            }
        case .tvmaze:
            let query = queries[0]
            if let request = planner.searchRequest(provider: .tvmaze, query: query, config: config),
               let object = try? await jsonObject(for: request),
               let candidate = SableLibraryProviderCandidateParser.tvmazeCandidate(from: object) {
                candidates.append(candidate)
            }
        case .wikidata:
            let query = queries[0]
            if let match = await wikidataTitleMatch(title: query, year: nil, mediaType: nil, config: config) {
                candidates.append(match.candidate)
            }
        case .tmdb:
            let query = queries[0]
            if let request = planner.searchRequest(provider: .tmdb, query: query, config: config),
               let object = try? await jsonObject(for: request) {
                candidates.append(contentsOf: SableLibraryProviderCandidateParser.tmdbCandidates(from: object))
            }
        case .tvdb, .imdb, .local:
            candidates = []
        }

        return Array(deduplicatedManualCandidates(candidates).prefix(10))
    }

    private func ranobeDBManualCandidatesWithCovers(
        _ candidates: [SableLibraryProviderCandidate],
        providerConfig: SableLibraryConfig.MetadataProvider
    ) async -> [SableLibraryProviderCandidate] {
        guard candidates.contains(where: { !manualCandidateHasCover($0) }) else {
            return candidates
        }

        var enriched: [SableLibraryProviderCandidate] = []
        for candidate in candidates.prefix(10) {
            guard !manualCandidateHasCover(candidate),
                  let ranobeDBID = candidate.sourceIDs.first(where: { $0.provider == .ranobedb })?.value,
                  let request = ranobeDBDetailRequest(path: ["series", ranobeDBID], providerConfig: providerConfig),
                  let object = try? await jsonObject(for: request),
                  let detail = SableLibraryProviderCandidateParser.ranobeDBSeriesDetailCandidate(from: object) else {
                enriched.append(candidate)
                continue
            }

            var merged = detail
            if merged.sourceIDs.isEmpty {
                merged.sourceIDs = candidate.sourceIDs
            }
            if merged.aliases.isEmpty {
                merged.aliases = candidate.aliases
            }
            if merged.mediaType == nil {
                merged.mediaType = candidate.mediaType
            }
            if merged.year == nil {
                merged.year = candidate.year
            }
            enriched.append(merged)
        }

        if candidates.count > enriched.count {
            enriched.append(contentsOf: candidates.dropFirst(enriched.count))
        }
        return enriched
    }

    private func manualCandidateHasCover(_ candidate: SableLibraryProviderCandidate) -> Bool {
        candidate.coverURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private func mergedCandidate(
        _ candidate: SableLibraryProviderCandidate,
        fallback: SableLibraryProviderCandidate
    ) -> SableLibraryProviderCandidate {
        var merged = candidate
        if merged.sourceIDs.isEmpty {
            merged.sourceIDs = fallback.sourceIDs
        }
        merged.aliases = uniqueStrings(merged.aliases + fallback.aliases + [fallback.title])
        if merged.year == nil {
            merged.year = fallback.year
        }
        if merged.mediaType == nil {
            merged.mediaType = fallback.mediaType
        }
        if merged.coverURL == nil {
            merged.coverURL = fallback.coverURL
        }
        return merged
    }

    private func normalizedCatalogMediaTypes(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let normalized = value
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: " ", with: "_")
                .uppercased()
            let apiType: String?
            switch normalized {
            case "MANGA", "NOVEL", "LIGHT_NOVEL", "LIGHTNOVEL", "ONE_SHOT", "ONESHOT":
                apiType = "MANGA"
            case "ANIME", "TV", "MOVIE", "OVA", "ONA", "SPECIAL":
                apiType = "ANIME"
            default:
                apiType = nil
            }
            guard let apiType,
                  seen.insert(apiType).inserted else {
                return nil
            }
            return apiType
        }
    }

    func watchingEnrichment(
        title rawTitle: String,
        sourceIDs existingSourceIDs: [SableLibrarySourceID] = [],
        allowTitleSearch: Bool = true,
        config: SableLibraryConfig,
        service: SableLibraryService
    ) async -> SableLibraryMetadataEnrichment? {
        let title = providerSearchTitle(rawTitle, service: service)

        let primaryMatch: (candidate: SableLibraryProviderCandidate, score: Double, matchedTitle: String)
        let malID: String?
        let existingMALID = existingSourceIDs.first(where: { $0.provider == .myAnimeList })?.value
        var usedExistingMALID: String?
        var usedExistingExternalID: SableLibrarySourceID?
        var seededAniListCandidate: SableLibraryProviderCandidate?

        if let existingMALID,
           let aniListCandidate = try? await aniListCandidate(malID: existingMALID, config: config) {
            primaryMatch = (candidate: aniListCandidate, score: 1, matchedTitle: aniListCandidate.title)
            malID = existingMALID
            usedExistingMALID = existingMALID
            seededAniListCandidate = aniListCandidate
        } else if let externalMatch = await externalWatchingIDMatch(sourceIDs: existingSourceIDs, config: config) {
            primaryMatch = externalMatch.match
            malID = nil
            usedExistingExternalID = externalMatch.sourceID
        } else {
            guard allowTitleSearch else { return nil }
            if let aniListMatch = await aniListTitleMatch(title: title, config: config) {
                primaryMatch = aniListMatch
                malID = aniListMatch.candidate.sourceIDs.first(where: { $0.provider == .myAnimeList })?.value
                usedExistingMALID = nil
                seededAniListCandidate = aniListMatch.candidate
            } else if let wikidataMatch = await wikidataTitleMatch(title: title, year: nil, mediaType: nil, config: config) {
                primaryMatch = wikidataMatch
                malID = nil
                usedExistingMALID = nil
            } else {
                return nil
            }
        }

        let secondaryAniListCandidate: SableLibraryProviderCandidate?
        if primaryMatch.candidate.provider == .anilist {
            secondaryAniListCandidate = nil
        } else if let seededAniListCandidate {
            secondaryAniListCandidate = seededAniListCandidate
        } else if let malID {
            secondaryAniListCandidate = try? await aniListCandidate(malID: malID, config: config)
        } else {
            secondaryAniListCandidate = nil
        }
        var candidates = [primaryMatch.candidate, secondaryAniListCandidate].compactMap { $0 }
        let preferred = primaryMatch.candidate
        var ids = uniqueSourceIDs(existingSourceIDs + candidates.flatMap(\.sourceIDs))
        var aliases = uniqueStrings(candidates.flatMap(\.aliases) + candidates.map(\.title))
        var genres = uniqueStrings(candidates.flatMap(\.genres))
        var tags = uniqueStrings(candidates.flatMap(\.tags))
        var contentWarnings = uniqueStrings(candidates.flatMap(\.contentWarnings))
        var studios = uniqueStrings(candidates.flatMap(\.studios))
        var authors = uniqueStrings(candidates.flatMap(\.authors))
        var artists = uniqueStrings(candidates.flatMap(\.artists))
        var publishers = uniqueStrings(candidates.flatMap(\.publishers))
        var languages = uniqueStrings(candidates.flatMap(\.languages))
        var description = candidates.compactMap(\.description).first
        var status = candidates.compactMap(\.status).first
        var contentRating = candidates.compactMap(\.contentRating).first
        var providersUsed = uniqueProviders(candidates.map(\.provider))
        let now = ISO8601DateFormatter().string(from: Date())

        var evidence: [SableLibraryMatchEvidence] = []
        if let usedExistingMALID {
            evidence.append(
                SableLibraryMatchEvidence(
                    kind: .exactProviderID,
                    provider: .myAnimeList,
                    value: "mal:\(usedExistingMALID)",
                    confidence: 1
                )
            )
        } else if let usedExistingExternalID {
            evidence.append(
                SableLibraryMatchEvidence(
                    kind: .exactProviderID,
                    provider: usedExistingExternalID.provider,
                    value: usedExistingExternalID.stableKey,
                    confidence: 1
                )
            )
        } else {
            evidence.append(
                SableLibraryMatchEvidence(
                    kind: .titleSimilarity,
                    provider: primaryMatch.candidate.provider,
                    value: primaryMatch.matchedTitle,
                    confidence: primaryMatch.score
                )
            )
        }
        if let malID,
           primaryMatch.candidate.provider != .anilist,
           secondaryAniListCandidate?.sourceIDs.contains(where: { $0.provider == .myAnimeList && $0.value == malID }) == true {
            evidence.append(
                SableLibraryMatchEvidence(
                    kind: .providerBridge,
                    provider: .anilist,
                    value: "mal:\(malID)",
                    confidence: 0.98
                )
            )
        }
        if usedExistingExternalID == nil,
           primaryMatch.candidate.provider == .wikidata,
           wikidataCandidateHasUsefulExternalID(primaryMatch.candidate) {
            evidence.append(
                SableLibraryMatchEvidence(
                    kind: .providerBridge,
                    provider: .wikidata,
                    value: wikidataBridgeEvidenceValue(from: primaryMatch.candidate.sourceIDs),
                    confidence: 0.97
                )
            )
        }
        var preferredYear = preferred.year
        var preferredMediaType = preferred.mediaType
        if allowTitleSearch,
           primaryMatch.candidate.provider != .wikidata,
           let wikidataMatch = await wikidataTitleMatch(
            title: preferred.title,
            year: preferredYear,
            mediaType: preferred.mediaType,
            config: config
           ) {
            let newWikidataIDs = wikidataMatch.candidate.sourceIDs.filter { wikidataID in
                !ids.contains { $0.provider == wikidataID.provider && $0.value == wikidataID.value }
            }
            if !newWikidataIDs.isEmpty {
                candidates.append(wikidataMatch.candidate)
                ids = uniqueSourceIDs(ids + newWikidataIDs)
                aliases = uniqueStrings(aliases + wikidataMatch.candidate.aliases + [wikidataMatch.candidate.title])
                preferredYear = preferredYear ?? wikidataMatch.candidate.year
                preferredMediaType = preferredMediaType ?? wikidataMatch.candidate.mediaType
                providersUsed = uniqueProviders(providersUsed + [.wikidata])
                evidence.append(
                    SableLibraryMatchEvidence(
                        kind: .titleSimilarity,
                        provider: .wikidata,
                        value: wikidataMatch.matchedTitle,
                        confidence: wikidataMatch.score
                    )
                )
                if let candidateYear = wikidataMatch.candidate.year,
                   candidateYear == preferredYear {
                    evidence.append(
                        SableLibraryMatchEvidence(
                            kind: .yearMatch,
                            provider: .wikidata,
                            value: "\(candidateYear)",
                            confidence: 0.96
                        )
                    )
                }
                if wikidataMatch.candidate.sourceIDs.contains(where: { $0.provider == .tmdb || $0.provider == .tvdb || $0.provider == .imdb }) {
                    evidence.append(
                        SableLibraryMatchEvidence(
                            kind: .providerBridge,
                            provider: .wikidata,
                            value: wikidataBridgeEvidenceValue(from: wikidataMatch.candidate.sourceIDs),
                            confidence: 0.97
                        )
                    )
                }
            }
        }
        if let tvmazeMatch = await tvmazeMatch(title: preferred.title, year: preferredYear, sourceIDs: ids, allowTitleSearch: allowTitleSearch, config: config) {
            candidates.append(tvmazeMatch.candidate)
            ids = uniqueSourceIDs(ids + tvmazeMatch.candidate.sourceIDs)
            aliases = uniqueStrings(aliases + tvmazeMatch.candidate.aliases + [tvmazeMatch.candidate.title])
            genres = uniqueStrings(genres + tvmazeMatch.candidate.genres)
            tags = uniqueStrings(tags + tvmazeMatch.candidate.tags)
            contentWarnings = uniqueStrings(contentWarnings + tvmazeMatch.candidate.contentWarnings)
            studios = uniqueStrings(studios + tvmazeMatch.candidate.studios)
            authors = uniqueStrings(authors + tvmazeMatch.candidate.authors)
            artists = uniqueStrings(artists + tvmazeMatch.candidate.artists)
            publishers = uniqueStrings(publishers + tvmazeMatch.candidate.publishers)
            languages = uniqueStrings(languages + tvmazeMatch.candidate.languages)
            description = description ?? tvmazeMatch.candidate.description
            status = status ?? tvmazeMatch.candidate.status
            contentRating = contentRating ?? tvmazeMatch.candidate.contentRating
            preferredYear = preferredYear ?? tvmazeMatch.candidate.year
            preferredMediaType = preferredMediaType ?? tvmazeMatch.candidate.mediaType
            providersUsed = uniqueProviders(providersUsed + [.tvmaze])
            let exactTVMazeSourceID = matchingSourceID(
                in: tvmazeMatch.candidate.sourceIDs,
                from: existingSourceIDs
            )
            evidence.append(
                SableLibraryMatchEvidence(
                    kind: exactTVMazeSourceID == nil ? .titleSimilarity : .exactProviderID,
                    provider: exactTVMazeSourceID?.provider ?? .tvmaze,
                    value: exactTVMazeSourceID?.stableKey ?? tvmazeMatch.matchedTitle,
                    confidence: exactTVMazeSourceID == nil ? tvmazeMatch.score : 1
                )
            )
            if let candidateYear = tvmazeMatch.candidate.year,
               candidateYear == preferredYear {
                evidence.append(
                    SableLibraryMatchEvidence(
                        kind: .yearMatch,
                        provider: .tvmaze,
                        value: "\(candidateYear)",
                        confidence: 0.96
                    )
                )
            }
            if tvmazeMatch.candidate.sourceIDs.contains(where: { $0.provider == .tvdb || $0.provider == .imdb }) {
                evidence.append(
                    SableLibraryMatchEvidence(
                        kind: .providerBridge,
                        provider: .tvmaze,
                        value: "externals",
                        confidence: 0.97
                    )
                )
            }
        }

        let wikidataIDs = await wikidataBridgeIDs(for: ids, config: config)
        let newWikidataIDs = wikidataIDs.filter { wikidataID in
            !ids.contains { $0.provider == wikidataID.provider && $0.value == wikidataID.value }
        }
        if !newWikidataIDs.isEmpty {
            ids = uniqueSourceIDs(ids + newWikidataIDs)
            providersUsed = uniqueProviders(providersUsed + [.wikidata])
            evidence.append(
                SableLibraryMatchEvidence(
                    kind: .providerBridge,
                    provider: .wikidata,
                    value: wikidataBridgeEvidenceValue(from: ids),
                    confidence: 0.98
                )
            )
        }

        let confidence = confidenceEngine.combinedScore(evidence)
        guard confidence >= 0.94 else { return nil }

        return SableLibraryMetadataEnrichment(
            preferredTitle: preferred.title,
            year: preferredYear,
            mediaType: watchingType(from: preferredMediaType).rawValue,
            sourceIDs: ids,
            aliases: aliases,
            description: description,
            genres: genres,
            tags: tags,
            contentWarnings: contentWarnings,
            studios: studios,
            authors: authors,
            artists: artists,
            publishers: publishers,
            languages: languages,
            status: status,
            contentRating: contentRating,
            coverURL: preferred.coverURL,
            isbn13: [],
            readingParts: [],
            evidence: evidence,
            freshness: providersUsed.map {
                SableLibraryProviderFreshness(provider: $0, fetchedAt: now, ttlSeconds: ttlSeconds(for: $0, config: config))
            },
            confidenceScore: confidence,
            providersUsed: providersUsed
        )
    }

    func readingEnrichment(
        title rawTitle: String,
        sourceIDs existingSourceIDs: [SableLibrarySourceID] = [],
        knownRanobeDBBookIDs: Set<String> = [],
        detailedRanobeDBBookIDs: Set<String> = [],
        includeBookDetails: Bool = true,
        allowTitleSearch: Bool = true,
        config: SableLibraryConfig,
        service: SableLibraryService
    ) async -> SableLibraryMetadataEnrichment? {
        let title = providerSearchTitle(rawTitle, service: service)
        guard let providerConfig = planner.providerConfig(for: .ranobedb, config: config),
              providerConfig.enabled else {
            return nil
        }

        let detailObject: [String: Any]
        var matchedCandidate: SableLibraryProviderCandidate?
        var evidence: [SableLibraryMatchEvidence] = []

        if let ranobeDBID = existingSourceIDs.first(where: { $0.provider == .ranobedb })?.value,
           let request = ranobeDBDetailRequest(path: ["series", ranobeDBID], providerConfig: providerConfig),
           let object = try? await jsonObject(for: request) {
            detailObject = object
            evidence.append(
                SableLibraryMatchEvidence(
                    kind: .exactProviderID,
                    provider: .ranobedb,
                    value: ranobeDBID,
                    confidence: 1
                )
            )
        } else {
            guard allowTitleSearch,
                  let match = await bestRanobeDBSeriesMatch(
                    title: title,
                    providerConfig: providerConfig
                  ),
                  let ranobeDBID = match.candidate.sourceIDs.first(where: { $0.provider == .ranobedb })?.value,
                  let detailRequest = ranobeDBDetailRequest(path: ["series", ranobeDBID], providerConfig: providerConfig),
                  let object = try? await jsonObject(for: detailRequest) else {
                return nil
            }
            detailObject = object
            matchedCandidate = match.candidate
            evidence.append(
                SableLibraryMatchEvidence(
                    kind: .titleSimilarity,
                    provider: .ranobedb,
                    value: match.matchedTitle,
                    confidence: match.score
                )
            )
        }

        guard let detailCandidate = SableLibraryProviderCandidateParser.ranobeDBSeriesDetailCandidate(from: detailObject) ?? matchedCandidate else {
            return nil
        }

        var sourceIDs = uniqueSourceIDs(existingSourceIDs + detailCandidate.sourceIDs)
        var parts = SableLibraryProviderCandidateParser.ranobeDBReadingParts(
            from: detailObject,
            preferredTitle: title
        )
        var ranobeDBBookResponses: [SableLibraryJSONValue] = []
        var requestedBookIDs: [String] = []
        var fetchedBookIDs: [String] = []
        var failedBookIDs: [String] = []
        if includeBookDetails {
            let bookDetails = await enrichedRanobeDBBookDetails(
                parts: parts,
                detailedBookIDs: detailedRanobeDBBookIDs,
                providerConfig: providerConfig,
                preferredTitle: title
            )
            parts = bookDetails.parts
            ranobeDBBookResponses = bookDetails.apiBookResponses
            requestedBookIDs = bookDetails.requestedBookIDs
            fetchedBookIDs = bookDetails.fetchedBookIDs
            failedBookIDs = bookDetails.failedBookIDs
        }
        let isbn = uniqueStrings(parts.flatMap(\.isbn13))
        let openLibraryCandidates = await openLibraryCandidates(for: isbn, config: config)
        var providersUsed: [SableLibraryMetadataProvider] = [.ranobedb]

        if !openLibraryCandidates.isEmpty {
            providersUsed.append(.openLibrary)
            sourceIDs = uniqueSourceIDs(sourceIDs + openLibraryCandidates.flatMap(\.sourceIDs))
            for candidate in openLibraryCandidates {
                if let matchedISBN = candidate.isbn13.first(where: { isbn.contains($0) }) {
                    evidence.append(
                        SableLibraryMatchEvidence(
                            kind: .exactISBN,
                            provider: .openLibrary,
                            value: matchedISBN,
                            confidence: 1
                        )
                    )
                }
            }
        }

        let bridgeIDs = detailCandidate.sourceIDs.filter { $0.provider == .myAnimeList || $0.provider == .anilist }
        for id in bridgeIDs {
            evidence.append(
                SableLibraryMatchEvidence(
                    kind: .providerBridge,
                    provider: id.provider,
                    value: "ranobedb:\(id.value)",
                    confidence: 0.95
                )
            )
        }
        if detailCandidate.mediaType == "lightNovel" {
            evidence.append(
                SableLibraryMatchEvidence(
                    kind: .typeMatch,
                    provider: .ranobedb,
                    value: "lightNovel",
                    confidence: 0.96
                )
            )
        }

        let confidence = confidenceEngine.combinedScore(evidence)
        guard confidence >= 0.94 else { return nil }

        let now = ISO8601DateFormatter().string(from: Date())
        let aliases = uniqueStrings(
            detailCandidate.aliases
                + openLibraryCandidates.flatMap(\.aliases)
                + [matchedCandidate?.title, detailCandidate.title].compactMap { $0 }
        )
        let genres = uniqueStrings([detailCandidate, matchedCandidate].compactMap { $0 }.flatMap(\.genres))
        let tags = uniqueStrings([detailCandidate, matchedCandidate].compactMap { $0 }.flatMap(\.tags))
        let contentWarnings = uniqueStrings([detailCandidate, matchedCandidate].compactMap { $0 }.flatMap(\.contentWarnings))
        let studios = uniqueStrings([detailCandidate, matchedCandidate].compactMap { $0 }.flatMap(\.studios))
        let enrichmentCandidates = [detailCandidate, matchedCandidate].compactMap { $0 } + openLibraryCandidates
        let authors = uniqueStrings(enrichmentCandidates.flatMap(\.authors))
        let artists = uniqueStrings(enrichmentCandidates.flatMap(\.artists))
        let publishers = uniqueStrings(enrichmentCandidates.flatMap(\.publishers))
        let languages = uniqueStrings(enrichmentCandidates.flatMap(\.languages))
        let coverURL = enrichmentCandidates.compactMap(\.coverURL).first
        sourceIDs = uniqueSourceIDs(sourceIDs)
        let seriesBookIDs = uniqueStrings(parts.compactMap { part in
            guard part.sourceID?.provider == .ranobedb else { return nil }
            return part.sourceID?.value
        })
        let newReleaseBookIDs = seriesBookIDs.filter { !knownRanobeDBBookIDs.contains($0) }
        let providerPayloads = ranobeDBProviderPayloads(
            seriesResponse: detailObject,
            bookResponses: ranobeDBBookResponses,
            seriesBookIDs: seriesBookIDs,
            knownBookIDsBeforeRefresh: knownRanobeDBBookIDs.sorted(),
            detailedBookIDsBeforeRefresh: detailedRanobeDBBookIDs.sorted(),
            newReleaseBookIDs: newReleaseBookIDs,
            requestedBookIDs: requestedBookIDs,
            fetchedBookIDs: fetchedBookIDs,
            failedBookIDs: failedBookIDs,
            fetchedAt: now
        )
        return SableLibraryMetadataEnrichment(
            preferredTitle: detailCandidate.title,
            year: detailCandidate.year,
            mediaType: detailCandidate.mediaType,
            sourceIDs: sourceIDs,
            aliases: aliases,
            description: detailCandidate.description ?? matchedCandidate?.description,
            genres: genres,
            tags: tags,
            contentWarnings: contentWarnings,
            studios: studios,
            authors: authors,
            artists: artists,
            publishers: publishers,
            languages: languages,
            status: detailCandidate.status ?? matchedCandidate?.status,
            contentRating: detailCandidate.contentRating ?? matchedCandidate?.contentRating,
            coverURL: coverURL,
            isbn13: isbn,
            readingParts: parts,
            evidence: evidence,
            freshness: providersUsed.map {
                SableLibraryProviderFreshness(
                    provider: $0,
                    fetchedAt: now,
                    ttlSeconds: ttlSeconds(for: $0, config: config)
                )
            },
            confidenceScore: confidence,
            providersUsed: providersUsed,
            providerPayloads: providerPayloads
        )
    }

    func openLibraryEnrichment(
        title rawTitle: String,
        sourceIDs existingSourceIDs: [SableLibrarySourceID] = [],
        isbn13 existingISBN13: [String] = [],
        trustedAliases: [String] = [],
        authors existingAuthors: [String] = [],
        publishers existingPublishers: [String] = [],
        year existingYear: Int? = nil,
        allowTitleSearch: Bool = false,
        config: SableLibraryConfig,
        service: SableLibraryService
    ) async -> SableLibraryMetadataEnrichment? {
        let title = providerSearchTitle(rawTitle, service: service)
        let isbn13 = uniqueStrings(existingISBN13)
        let openLibrarySourceIDs = existingSourceIDs.filter { $0.provider == .openLibrary }
        var candidates = await openLibraryCandidates(for: openLibrarySourceIDs, config: config)
        var evidence: [SableLibraryMatchEvidence] = []

        for sourceID in openLibrarySourceIDs where matchingSourceID(in: candidates.flatMap(\.sourceIDs), from: [sourceID]) != nil {
            evidence.append(
                SableLibraryMatchEvidence(
                    kind: .exactProviderID,
                    provider: .openLibrary,
                    value: sourceID.stableKey,
                    confidence: 1
                )
            )
        }

        if candidates.isEmpty {
            candidates = await openLibraryCandidates(for: isbn13, config: config)
        }

        for candidate in candidates {
            if let matchedISBN = candidate.isbn13.first(where: { isbn13.contains($0) }) {
                evidence.append(
                    SableLibraryMatchEvidence(
                        kind: .exactISBN,
                        provider: .openLibrary,
                        value: matchedISBN,
                        confidence: 1
                    )
                )
            }
        }

        if candidates.isEmpty,
           allowTitleSearch,
           let match = await bestOpenLibraryBookMatch(
            title: title,
            trustedAliases: trustedAliases,
            year: existingYear,
            authors: existingAuthors,
            publishers: existingPublishers,
            config: config
           ) {
            candidates = [match.candidate]
            evidence = match.evidence
        }

        guard let preferred = candidates.first else { return nil }

        let confidence = confidenceEngine.combinedScore(evidence)
        guard confidence >= 0.94 else { return nil }

        let enrichmentCandidates = candidates
        let now = ISO8601DateFormatter().string(from: Date())
        let aliases = uniqueStrings(
            trustedAliases
                + enrichmentCandidates.flatMap(\.aliases)
                + enrichmentCandidates.map(\.title)
        )
        let sourceIDs = uniqueSourceIDs(existingSourceIDs + enrichmentCandidates.flatMap(\.sourceIDs))
        let authors = uniqueStrings(existingAuthors + enrichmentCandidates.flatMap(\.authors))
        let publishers = uniqueStrings(existingPublishers + enrichmentCandidates.flatMap(\.publishers))

        return SableLibraryMetadataEnrichment(
            preferredTitle: preferred.title,
            year: preferred.year ?? existingYear,
            mediaType: SableLibraryReadingType.book.rawValue,
            sourceIDs: sourceIDs,
            aliases: aliases,
            description: preferred.description,
            genres: uniqueStrings(enrichmentCandidates.flatMap(\.genres)),
            tags: uniqueStrings(enrichmentCandidates.flatMap(\.tags)),
            contentWarnings: uniqueStrings(enrichmentCandidates.flatMap(\.contentWarnings)),
            studios: uniqueStrings(enrichmentCandidates.flatMap(\.studios)),
            authors: authors,
            artists: uniqueStrings(enrichmentCandidates.flatMap(\.artists)),
            publishers: publishers,
            languages: uniqueStrings(enrichmentCandidates.flatMap(\.languages)),
            status: preferred.status,
            contentRating: preferred.contentRating,
            coverURL: preferred.coverURL,
            isbn13: uniqueStrings(isbn13 + enrichmentCandidates.flatMap(\.isbn13)),
            readingParts: [],
            evidence: evidence,
            freshness: [
                SableLibraryProviderFreshness(
                    provider: .openLibrary,
                    fetchedAt: now,
                    ttlSeconds: ttlSeconds(for: .openLibrary, config: config)
                )
            ],
            confidenceScore: confidence,
            providersUsed: [.openLibrary]
        )
    }

    func wikidataBookEnrichment(
        title rawTitle: String,
        sourceIDs existingSourceIDs: [SableLibrarySourceID] = [],
        trustedAliases: [String] = [],
        authors existingAuthors: [String] = [],
        year existingYear: Int? = nil,
        allowTitleSearch: Bool = false,
        config: SableLibraryConfig,
        service: SableLibraryService
    ) async -> SableLibraryMetadataEnrichment? {
        let title = providerSearchTitle(rawTitle, service: service)
        let match: (candidate: SableLibraryProviderCandidate, evidence: [SableLibraryMatchEvidence], score: Double)?

        if let exactMatch = await wikidataBookIDMatch(sourceIDs: existingSourceIDs, config: config) {
            match = exactMatch
        } else if allowTitleSearch {
            match = await bestWikidataBookMatch(
                title: title,
                trustedAliases: trustedAliases,
                year: existingYear,
                authors: existingAuthors,
                config: config
            )
        } else {
            match = nil
        }

        guard let match else { return nil }

        let confidence = confidenceEngine.combinedScore(match.evidence)
        guard confidence >= 0.94 else { return nil }

        let preferred = match.candidate
        let now = ISO8601DateFormatter().string(from: Date())
        let aliases = uniqueStrings(
            trustedAliases
                + preferred.aliases
                + [preferred.title]
        )
        let sourceIDs = uniqueSourceIDs(existingSourceIDs + preferred.sourceIDs)
        let authors = uniqueStrings(existingAuthors + preferred.authors)

        return SableLibraryMetadataEnrichment(
            preferredTitle: preferred.title,
            year: preferred.year ?? existingYear,
            mediaType: SableLibraryReadingType.book.rawValue,
            sourceIDs: sourceIDs,
            aliases: aliases,
            description: preferred.description,
            genres: uniqueStrings(preferred.genres),
            tags: uniqueStrings(preferred.tags),
            contentWarnings: uniqueStrings(preferred.contentWarnings),
            studios: uniqueStrings(preferred.studios),
            authors: authors,
            artists: uniqueStrings(preferred.artists),
            publishers: uniqueStrings(preferred.publishers),
            languages: uniqueStrings(preferred.languages),
            status: preferred.status,
            contentRating: preferred.contentRating,
            coverURL: preferred.coverURL,
            isbn13: uniqueStrings(preferred.isbn13),
            readingParts: [],
            evidence: match.evidence,
            freshness: [
                SableLibraryProviderFreshness(
                    provider: .wikidata,
                    fetchedAt: now,
                    ttlSeconds: ttlSeconds(for: .wikidata, config: config)
                )
            ],
            confidenceScore: confidence,
            providersUsed: [.wikidata]
        )
    }

    func readingCatalogEnrichment(
        title rawTitle: String,
        sourceIDs existingSourceIDs: [SableLibrarySourceID] = [],
        trustedAliases: [String] = [],
        year: Int? = nil,
        allowTitleSearch: Bool = false,
        config: SableLibraryConfig,
        service: SableLibraryService
    ) async -> SableLibraryMetadataEnrichment? {
        let title = providerSearchTitle(rawTitle, service: service)
        let now = ISO8601DateFormatter().string(from: Date())

        var candidates: [SableLibraryProviderCandidate] = []
        var evidence: [SableLibraryMatchEvidence] = []
        var providersUsed: [SableLibraryMetadataProvider] = []

        let existingMALID = existingSourceIDs.first(where: { $0.provider == .myAnimeList })?.value

        if let malID = existingMALID,
           let aniListCandidate = try? await aniListCandidate(malID: malID, mediaType: "MANGA", config: config) {
            candidates.append(aniListCandidate)
            providersUsed.append(.anilist)
            evidence.append(
                SableLibraryMatchEvidence(
                    kind: .providerBridge,
                    provider: .anilist,
                    value: "mal:\(malID)",
                    confidence: 0.98
                )
            )
        } else if let anilistID = existingSourceIDs.first(where: { $0.provider == .anilist })?.value,
                  let aniListCandidate = try? await aniListCandidate(id: anilistID, mediaType: "MANGA", config: config) {
            candidates.append(aniListCandidate)
            providersUsed.append(.anilist)
            evidence.append(
                SableLibraryMatchEvidence(
                    kind: .exactProviderID,
                    provider: .anilist,
                    value: anilistID,
                    confidence: 1
                )
            )
        } else if allowTitleSearch,
                  let aniListMatch = await aniListTitleMatch(title: title, mediaType: "MANGA", config: config) {
            candidates.append(aniListMatch.candidate)
            providersUsed.append(.anilist)
            evidence.append(
                SableLibraryMatchEvidence(
                    kind: .titleSimilarity,
                    provider: .anilist,
                    value: aniListMatch.matchedTitle,
                    confidence: aniListMatch.score
                )
            )
        }

        guard !candidates.isEmpty else { return nil }

        let preferred = candidates.first ?? SableLibraryProviderCandidate(provider: .local, title: title)
        let sourceIDs = uniqueSourceIDs(existingSourceIDs + candidates.flatMap(\.sourceIDs))
        let aliases = uniqueStrings(candidates.flatMap(\.aliases) + candidates.map(\.title))
        let genres = uniqueStrings(candidates.flatMap(\.genres))
        let tags = uniqueStrings(candidates.flatMap(\.tags))
        let contentWarnings = uniqueStrings(candidates.flatMap(\.contentWarnings))
        let studios = uniqueStrings(candidates.flatMap(\.studios))
        let authors = uniqueStrings(candidates.flatMap(\.authors))
        let artists = uniqueStrings(candidates.flatMap(\.artists))
        let publishers = uniqueStrings(candidates.flatMap(\.publishers))
        let languages = uniqueStrings(candidates.flatMap(\.languages))
        let description = candidates.compactMap(\.description).first
        let status = candidates.compactMap(\.status).first
        let contentRating = candidates.compactMap(\.contentRating).first
        let coverURL = candidates.compactMap(\.coverURL).first

        let confidence = confidenceEngine.combinedScore(evidence)
        guard confidence >= 0.94 else { return nil }

        return SableLibraryMetadataEnrichment(
            preferredTitle: preferred.title,
            year: preferred.year ?? year,
            mediaType: preferred.mediaType,
            sourceIDs: sourceIDs,
            aliases: aliases,
            description: description,
            genres: genres,
            tags: tags,
            contentWarnings: contentWarnings,
            studios: studios,
            authors: authors,
            artists: artists,
            publishers: publishers,
            languages: languages,
            status: status,
            contentRating: contentRating,
            coverURL: coverURL,
            isbn13: [],
            readingParts: [],
            evidence: evidence,
            freshness: uniqueProviders(providersUsed).map {
                SableLibraryProviderFreshness(provider: $0, fetchedAt: now, ttlSeconds: ttlSeconds(for: $0, config: config))
            },
            confidenceScore: confidence,
            providersUsed: uniqueProviders(providersUsed)
        )
    }

    private func bestCandidateWithTrustedAliases(
        queryTitle: String,
        trustedAliases: [String],
        candidates: [SableLibraryProviderCandidate]
    ) -> (candidate: SableLibraryProviderCandidate, score: Double, matchedTitle: String)? {
        let trustedPool = uniqueStrings([queryTitle] + trustedAliases)
        let scored = candidates.map { candidate in
            let candidateTitles = uniqueStrings([candidate.title] + candidate.aliases)
            var bestScore = 0.0
            var bestTitle = candidate.title

            for trusted in trustedPool {
                for candidateTitle in candidateTitles {
                    let score = confidenceEngine.titleSimilarity(trusted, candidateTitle)
                    if score > bestScore {
                        bestScore = score
                        bestTitle = candidateTitle
                    }
                }
            }

            return (candidate: candidate, score: bestScore, matchedTitle: bestTitle)
        }
        .sorted { $0.score > $1.score }

        guard let best = scored.first,
              best.score >= 0.94 else {
            return nil
        }

        if scored.count > 1, scored[1].score >= 0.92, best.score - scored[1].score < 0.05 {
            return nil
        }

        return best
    }

    private func providerSearchTitle(_ rawTitle: String, service: SableLibraryService) -> String {
        let filesystemTitle = service.cleanSeriesTitle(rawTitle)
        return SableLibraryProviderQueryCleaner.searchTitle(from: filesystemTitle) ?? filesystemTitle
    }

    private func providerSearchTitles(_ rawTitle: String, service: SableLibraryService, limit: Int = 4) -> [String] {
        let filesystemTitle = service.cleanSeriesTitle(rawTitle)
        var titles = SableLibraryProviderQueryCleaner.searchTitles(
            from: [filesystemTitle, rawTitle],
            limit: limit,
            includeLooseVariants: true
        )
        if titles.isEmpty {
            let fallback = filesystemTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if !fallback.isEmpty {
                titles.append(fallback)
            }
        }
        return Array(titles.prefix(max(0, limit)))
    }

    private func trustedReadingQueryTitles(title: String, aliases: [String]) -> [String] {
        SableLibraryProviderQueryCleaner.searchTitles(
            from: [title] + aliases,
            limit: 8,
            includeLooseVariants: true
        )
    }

    private func jsonObject(for requestPlan: SableLibraryProviderRequest) async throws -> [String: Any] {
        let request = try authorizedRequest(for: requestPlan)
        let cacheKey = request.url.map {
            SableLibraryProviderResponseCache.key(provider: requestPlan.provider, url: $0)
        }
        let isCacheable = requestPlan.cacheTTLSeconds > 0
            && !requestPlan.requiresAPIKey
            && (request.httpMethod == nil || request.httpMethod == "GET")

        if isCacheable,
           let cacheKey,
           let cachedData = await SableLibraryProviderResponseCache.shared.cachedData(
            for: cacheKey,
            maximumAge: SableLibraryProviderRequestContext.maximumCacheAge
           ),
           let cachedObject = try JSONSerialization.jsonObject(with: cachedData) as? [String: Any] {
            return cachedObject
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLError(.badServerResponse)
        }
        if isCacheable, let cacheKey {
            await SableLibraryProviderResponseCache.shared.store(data, for: cacheKey, ttl: requestPlan.cacheTTLSeconds)
        }
        return object
    }

    private func authorizedRequest(for requestPlan: SableLibraryProviderRequest) throws -> URLRequest {
        let credentials = SableLibraryUserSettings().loadProviderCredentials()
        let credential = credentials.credential(for: requestPlan.provider)
        if requestPlan.requiresAPIKey, credential == nil {
            throw URLError(.userAuthenticationRequired)
        }

        var requestURL = requestPlan.url
        if requestPlan.provider == .tmdb,
           let credential,
           isTMDBV3APIKey(credential),
           var components = URLComponents(url: requestURL, resolvingAgainstBaseURL: false) {
            var queryItems = components.queryItems ?? []
            if !queryItems.contains(where: { $0.name == "api_key" }) {
                queryItems.append(URLQueryItem(name: "api_key", value: credential))
            }
            components.queryItems = queryItems
            if let url = components.url {
                requestURL = url
            }
        }

        var request = URLRequest(url: requestURL)
        request.timeoutInterval = requestPlan.timeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if requestPlan.provider == .wikidata {
            request.setValue("Sable's Library/1.0 local metadata organizer", forHTTPHeaderField: "User-Agent")
        }
        if let credential {
            applyCredential(credential, provider: requestPlan.provider, to: &request)
        }
        return request
    }

    private func applyCredential(_ credential: String, provider: SableLibraryMetadataProvider, to request: inout URLRequest) {
        switch provider {
        case .tmdb:
            if !isTMDBV3APIKey(credential) {
                request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
            }
        case .tvdb:
            request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
        case .mangabaka, .ranobedb, .openLibrary, .myAnimeList, .anilist, .tvmaze, .wikidata, .imdb, .local:
            break
        }
    }

    private func isTMDBV3APIKey(_ credential: String) -> Bool {
        credential.count <= 64 && credential.range(of: #"^[A-Fa-f0-9]+$"#, options: .regularExpression) != nil
    }

    func aniListExactCandidates(
        sourceIDs: [SableLibrarySourceID],
        mediaType: String = "MANGA",
        config: SableLibraryConfig
    ) async -> [String: SableLibraryProviderCandidate] {
        guard let providerConfig = planner.providerConfig(for: .anilist, config: config),
              providerConfig.enabled,
              let url = URL(string: providerConfig.apiBaseURL) else {
            return [:]
        }

        var candidatesByKey: [String: SableLibraryProviderCandidate] = [:]
        let lookups = uniqueSourceIDs(sourceIDs).compactMap(AniListExactLookup.init(sourceID:))
        let batchSize = 10

        for kind in AniListExactLookup.Kind.allCases {
            let ids = lookups
                .filter { $0.kind == kind }
                .map(\.id)
            var chunkStart = 0
            while chunkStart < ids.count {
                let chunkEnd = min(ids.count, chunkStart + batchSize)
                let chunk = Array(ids[chunkStart..<chunkEnd])
                let batch = await aniListExactCandidateBatch(
                    ids: chunk,
                    kind: kind,
                    mediaType: mediaType,
                    url: url,
                    providerConfig: providerConfig
                )
                candidatesByKey.merge(batch, uniquingKeysWith: { current, _ in current })
                chunkStart += batchSize
            }
        }

        return candidatesByKey
    }

    func readingCatalogEnrichment(
        aniListCandidate candidate: SableLibraryProviderCandidate,
        matchedSourceID: SableLibrarySourceID,
        existingSourceIDs: [SableLibrarySourceID] = [],
        year: Int? = nil,
        config: SableLibraryConfig
    ) -> SableLibraryMetadataEnrichment? {
        let now = ISO8601DateFormatter().string(from: Date())
        let evidence: [SableLibraryMatchEvidence]
        switch matchedSourceID.provider {
        case .myAnimeList:
            evidence = [
                SableLibraryMatchEvidence(
                    kind: .providerBridge,
                    provider: .anilist,
                    value: "mal:\(matchedSourceID.value)",
                    confidence: 0.98
                )
            ]
        default:
            evidence = [
                SableLibraryMatchEvidence(
                    kind: .exactProviderID,
                    provider: .anilist,
                    value: matchedSourceID.value,
                    confidence: 1
                )
            ]
        }

        let confidence = confidenceEngine.combinedScore(evidence)
        guard confidence >= 0.94 else { return nil }

        return SableLibraryMetadataEnrichment(
            preferredTitle: candidate.title,
            year: candidate.year ?? year,
            mediaType: candidate.mediaType,
            sourceIDs: uniqueSourceIDs(existingSourceIDs + candidate.sourceIDs + [matchedSourceID]),
            aliases: uniqueStrings(candidate.aliases + [candidate.title]),
            description: candidate.description,
            genres: uniqueStrings(candidate.genres),
            tags: uniqueStrings(candidate.tags),
            contentWarnings: uniqueStrings(candidate.contentWarnings),
            studios: uniqueStrings(candidate.studios),
            authors: uniqueStrings(candidate.authors),
            artists: uniqueStrings(candidate.artists),
            publishers: uniqueStrings(candidate.publishers),
            languages: uniqueStrings(candidate.languages),
            status: candidate.status,
            contentRating: candidate.contentRating,
            coverURL: candidate.coverURL,
            isbn13: [],
            readingParts: [],
            evidence: evidence,
            freshness: [
                SableLibraryProviderFreshness(
                    provider: .anilist,
                    fetchedAt: now,
                    ttlSeconds: ttlSeconds(for: .anilist, config: config)
                )
            ],
            confidenceScore: confidence,
            providersUsed: [.anilist]
        )
    }

    private struct AniListExactLookup: Hashable, Sendable {
        enum Kind: CaseIterable, Sendable {
            case aniList
            case myAnimeList

            var filterArgument: String {
                switch self {
                case .aniList:
                    "id_in"
                case .myAnimeList:
                    "idMal_in"
                }
            }
        }

        var kind: Kind
        var id: Int

        init?(sourceID: SableLibrarySourceID) {
            guard let id = Int(sourceID.value) else { return nil }
            switch sourceID.provider {
            case .anilist:
                self.kind = .aniList
            case .myAnimeList:
                self.kind = .myAnimeList
            case .mangabaka, .ranobedb, .openLibrary, .tvmaze, .wikidata, .tmdb, .tvdb, .imdb, .local:
                return nil
            }
            self.id = id
        }
    }

    private func aniListExactCandidateBatch(
        ids: [Int],
        kind: AniListExactLookup.Kind,
        mediaType: String,
        url: URL,
        providerConfig: SableLibraryConfig.MetadataProvider
    ) async -> [String: SableLibraryProviderCandidate] {
        guard !ids.isEmpty else { return [:] }
        do {
            return try await aniListExactCandidateBatchRequest(
                ids: ids,
                kind: kind,
                mediaType: mediaType,
                url: url,
                providerConfig: providerConfig
            )
        } catch {
            guard ids.count > 1 else { return [:] }
            let midpoint = ids.count / 2
            let left = await aniListExactCandidateBatch(
                ids: Array(ids[..<midpoint]),
                kind: kind,
                mediaType: mediaType,
                url: url,
                providerConfig: providerConfig
            )
            let right = await aniListExactCandidateBatch(
                ids: Array(ids[midpoint...]),
                kind: kind,
                mediaType: mediaType,
                url: url,
                providerConfig: providerConfig
            )
            return left.merging(right, uniquingKeysWith: { current, _ in current })
        }
    }

    private func aniListExactCandidateBatchRequest(
        ids: [Int],
        kind: AniListExactLookup.Kind,
        mediaType: String,
        url: URL,
        providerConfig: SableLibraryConfig.MetadataProvider
    ) async throws -> [String: SableLibraryProviderCandidate] {
        let pageSize = max(1, ids.count)
        let query = """
        query ($ids: [Int], $perPage: Int) {
          Page(page: 1, perPage: $perPage) {
            media(\(kind.filterArgument): $ids, type: \(mediaType)) {
              id
              idMal
              title { romaji english native }
              format
              seasonYear
              startDate { year month day }
              synonyms
              description
              coverImage { extraLarge large medium }
              genres
              tags { name }
              status
              isAdult
              studios {
                edges {
                  node {
                    name
                  }
                }
              }
            }
          }
        }
        """
        let body: [String: Any] = [
            "query": query,
            "variables": [
                "ids": ids,
                "perPage": pageSize
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = providerConfig.timeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Sable's Library/1.0 local metadata organizer", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObject = object["data"] as? [String: Any],
              let page = dataObject["Page"] as? [String: Any],
              let mediaRows = page["media"] as? [[String: Any]] else {
            throw URLError(.badServerResponse)
        }

        var candidatesByKey: [String: SableLibraryProviderCandidate] = [:]
        for candidate in mediaRows.compactMap(SableLibraryProviderCandidateParser.aniListCandidate(from:)) {
            for sourceID in candidate.sourceIDs {
                switch sourceID.provider {
                case .anilist, .myAnimeList:
                    candidatesByKey[sourceID.stableKey] = candidate
                case .mangabaka, .ranobedb, .openLibrary, .tvmaze, .wikidata, .tmdb, .tvdb, .imdb, .local:
                    continue
                }
            }
        }
        return candidatesByKey
    }

    private func aniListCandidate(malID: String, mediaType: String = "ANIME", config: SableLibraryConfig) async throws -> SableLibraryProviderCandidate? {
        guard let providerConfig = planner.providerConfig(for: .anilist, config: config),
              providerConfig.enabled,
              let malInt = Int(malID),
              let url = URL(string: providerConfig.apiBaseURL) else {
            return nil
        }

        let query = """
        query ($idMal: Int) {
          Media(idMal: $idMal, type: \(mediaType)) {
            id
            idMal
            title { romaji english native }
            format
            seasonYear
            startDate { year month day }
            synonyms
            description
            coverImage { extraLarge large medium }
            genres
            tags { name }
            status
            isAdult
            studios {
              edges {
                node {
                  name
                }
              }
            }
          }
        }
        """
        let body: [String: Any] = [
            "query": query,
            "variables": ["idMal": malInt]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = providerConfig.timeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Sable's Library/1.0 local metadata organizer", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObject = object["data"] as? [String: Any],
              let media = dataObject["Media"] as? [String: Any] else {
            return nil
        }
        return SableLibraryProviderCandidateParser.aniListCandidate(from: media)
    }

    private func aniListCandidate(id: String, mediaType: String = "ANIME", config: SableLibraryConfig) async throws -> SableLibraryProviderCandidate? {
        guard let providerConfig = planner.providerConfig(for: .anilist, config: config),
              providerConfig.enabled,
              let aniListInt = Int(id),
              let url = URL(string: providerConfig.apiBaseURL) else {
            return nil
        }

        let query = """
        query ($id: Int) {
          Media(id: $id, type: \(mediaType)) {
            id
            idMal
            title { romaji english native }
            format
            seasonYear
            startDate { year month day }
            synonyms
            description
            coverImage { extraLarge large medium }
            genres
            tags { name }
            status
            isAdult
            studios {
              edges {
                node {
                  name
                }
              }
            }
          }
        }
        """
        let body: [String: Any] = [
            "query": query,
            "variables": ["id": aniListInt]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = providerConfig.timeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Sable's Library/1.0 local metadata organizer", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObject = object["data"] as? [String: Any],
              let media = dataObject["Media"] as? [String: Any] else {
            return nil
        }
        return SableLibraryProviderCandidateParser.aniListCandidate(from: media)
    }

    private func aniListTitleMatch(
        title: String,
        mediaType: String = "ANIME",
        config: SableLibraryConfig
    ) async -> (candidate: SableLibraryProviderCandidate, score: Double, matchedTitle: String)? {
        guard let candidates = try? await aniListCandidates(title: title, mediaType: mediaType, config: config),
              !candidates.isEmpty else {
            return nil
        }
        return bestCandidate(queryTitle: title, candidates: candidates, requiredMinimumScore: 0.96)
    }

    private func aniListCandidate(title: String, mediaType: String = "ANIME", config: SableLibraryConfig) async throws -> SableLibraryProviderCandidate? {
        try await aniListCandidates(title: title, mediaType: mediaType, perPage: 1, config: config).first
    }

    private func aniListCandidates(
        title: String,
        mediaType: String = "ANIME",
        perPage: Int = 10,
        config: SableLibraryConfig
    ) async throws -> [SableLibraryProviderCandidate] {
        guard let providerConfig = planner.providerConfig(for: .anilist, config: config),
              providerConfig.enabled,
              let url = URL(string: providerConfig.apiBaseURL) else {
            return []
        }

        let pageSize = max(1, min(perPage, 25))
        let query = """
        query ($search: String, $page: Int, $perPage: Int) {
          Page(page: $page, perPage: $perPage) {
            pageInfo {
              total
              currentPage
              lastPage
              hasNextPage
            }
            media(search: $search, type: \(mediaType)) {
              id
              idMal
              title { romaji english native }
              format
              seasonYear
              startDate { year month day }
              synonyms
              description
              coverImage { extraLarge large medium }
              genres
              tags { name }
              status
              isAdult
              studios {
                edges {
                  node {
                    name
                  }
                }
              }
            }
          }
        }
        """
        let body: [String: Any] = [
            "query": query,
            "variables": [
                "search": title,
                "page": 1,
                "perPage": pageSize
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = providerConfig.timeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Sable's Library/1.0 local metadata organizer", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObject = object["data"] as? [String: Any],
              let page = dataObject["Page"] as? [String: Any],
              let mediaRows = page["media"] as? [[String: Any]] else {
            return []
        }
        return mediaRows.compactMap(SableLibraryProviderCandidateParser.aniListCandidate(from:))
    }

    private func tvmazeMatch(
        title: String,
        year: Int?,
        sourceIDs: [SableLibrarySourceID],
        allowTitleSearch: Bool,
        config: SableLibraryConfig
    ) async -> (candidate: SableLibraryProviderCandidate, score: Double, matchedTitle: String)? {
        if let exactMatch = await tvmazeExternalMatch(sourceIDs: sourceIDs, config: config) {
            return exactMatch
        }

        guard allowTitleSearch else { return nil }

        let queryTitle = SableLibraryProviderQueryCleaner.searchTitle(from: title) ?? title
        guard let request = planner.searchRequest(provider: .tvmaze, query: queryTitle, config: config),
              let object = try? await jsonObject(for: request),
              let candidate = SableLibraryProviderCandidateParser.tvmazeCandidate(from: object),
              yearIsCompatible(reference: year, candidate: candidate.year) else {
            return nil
        }
        return bestCandidate(queryTitle: queryTitle, candidates: [candidate], requiredMinimumScore: 0.94)
    }

    private func tvmazeExternalMatch(
        sourceIDs: [SableLibrarySourceID],
        config: SableLibraryConfig
    ) async -> (candidate: SableLibraryProviderCandidate, score: Double, matchedTitle: String)? {
        guard let providerConfig = planner.providerConfig(for: .tvmaze, config: config),
              providerConfig.enabled else {
            return nil
        }

        let request: SableLibraryProviderRequest?
        let matchedTitle: String
        if let tvmazeID = sourceIDs.first(where: { $0.provider == .tvmaze })?.value {
            request = tvmazeRequest(
                path: ["shows", tvmazeID],
                queryItems: [],
                providerConfig: providerConfig
            )
            matchedTitle = "tvmaze:\(tvmazeID)"
        } else if let imdbID = sourceIDs.first(where: { $0.provider == .imdb })?.value {
            request = tvmazeRequest(
                path: ["lookup", "shows"],
                queryItems: [URLQueryItem(name: "imdb", value: imdbID)],
                providerConfig: providerConfig
            )
            matchedTitle = "imdb:\(imdbID)"
        } else if let tvdbID = sourceIDs.first(where: { $0.provider == .tvdb })?.value {
            request = tvmazeRequest(
                path: ["lookup", "shows"],
                queryItems: [URLQueryItem(name: "thetvdb", value: tvdbID)],
                providerConfig: providerConfig
            )
            matchedTitle = "tvdb:\(tvdbID)"
        } else {
            request = nil
            matchedTitle = ""
        }

        guard let request,
              let object = try? await jsonObject(for: request),
              let candidate = SableLibraryProviderCandidateParser.tvmazeCandidate(from: object) else {
            return nil
        }
        return (candidate: candidate, score: 1, matchedTitle: matchedTitle)
    }

    private func tvmazeRequest(
        path: [String],
        queryItems: [URLQueryItem],
        providerConfig: SableLibraryConfig.MetadataProvider
    ) -> SableLibraryProviderRequest? {
        var base = providerConfig.apiBaseURL
        if !base.hasSuffix("/") {
            base += "/"
        }
        guard let baseURL = URL(string: base) else { return nil }
        var url = path.reduce(baseURL) { partialURL, component in
            partialURL.appendingPathComponent(component)
        }
        if !queryItems.isEmpty {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.queryItems = queryItems
            guard let componentURL = components?.url else { return nil }
            url = componentURL
        }
        return SableLibraryProviderRequest(
            provider: .tvmaze,
            url: url,
            requiresAPIKey: providerConfig.requiresAPIKey,
            timeoutSeconds: providerConfig.timeoutSeconds,
            cacheTTLSeconds: providerConfig.cacheTTLSeconds
        )
    }

    private func externalWatchingIDMatch(
        sourceIDs: [SableLibrarySourceID],
        config: SableLibraryConfig
    ) async -> (match: (candidate: SableLibraryProviderCandidate, score: Double, matchedTitle: String), sourceID: SableLibrarySourceID)? {
        guard let sourceID = preferredExternalWatchingSourceID(from: sourceIDs) else {
            return nil
        }

        if let tvmazeMatch = await tvmazeExternalMatch(sourceIDs: sourceIDs, config: config) {
            return (match: tvmazeMatch, sourceID: sourceID)
        }

        if let wikidataCandidate = await wikidataIDMatch(sourceIDs: sourceIDs, config: config) {
            return (
                match: (candidate: wikidataCandidate, score: 1, matchedTitle: sourceID.stableKey),
                sourceID: sourceID
            )
        }

        return nil
    }

    private func preferredExternalWatchingSourceID(from sourceIDs: [SableLibrarySourceID]) -> SableLibrarySourceID? {
        sourceIDs.first { $0.provider == .imdb }
            ?? sourceIDs.first { $0.provider == .tmdb }
            ?? sourceIDs.first { $0.provider == .tvdb }
            ?? sourceIDs.first { $0.provider == .tvmaze }
            ?? sourceIDs.first { $0.provider == .wikidata }
    }

    private func wikidataBridgeIDs(
        for sourceIDs: [SableLibrarySourceID],
        config: SableLibraryConfig
    ) async -> [SableLibrarySourceID] {
        guard let providerConfig = planner.providerConfig(for: .wikidata, config: config),
              providerConfig.enabled else {
            return []
        }

        let imdbIDs = sourceIDs
            .filter { $0.provider == .imdb }
            .map(\.value)
            .filter { $0.range(of: #"^tt\d+$"#, options: .regularExpression) != nil }
        let tvdbIDs = sourceIDs
            .filter { $0.provider == .tvdb }
            .map(\.value)
            .filter { $0.range(of: #"^\d+$"#, options: .regularExpression) != nil }

        let query: String?
        if !imdbIDs.isEmpty {
            query = wikidataQuery(property: "P345", variable: "imdb", values: imdbIDs)
        } else if !tvdbIDs.isEmpty {
            query = wikidataQuery(property: "P4835", variable: "tvdb", values: tvdbIDs)
        } else {
            query = nil
        }

        guard let query,
              let request = wikidataRequest(query: query, providerConfig: providerConfig),
              let object = try? await jsonObject(for: request) else {
            return []
        }
        return SableLibraryProviderCandidateParser.wikidataSourceIDs(from: object)
    }

    private func wikidataIDMatch(
        sourceIDs: [SableLibrarySourceID],
        config: SableLibraryConfig
    ) async -> SableLibraryProviderCandidate? {
        guard let providerConfig = planner.providerConfig(for: .wikidata, config: config),
              providerConfig.enabled else {
            return nil
        }

        for sourceID in sourceIDs {
            guard let query = wikidataExactIDQuery(for: sourceID),
                  let request = wikidataRequest(query: query, providerConfig: providerConfig),
                  let object = try? await jsonObject(for: request),
                  let candidate = SableLibraryProviderCandidateParser.wikidataCandidates(from: object).first else {
                continue
            }
            return candidate
        }

        return nil
    }

    private func wikidataBookIDMatch(
        sourceIDs: [SableLibrarySourceID],
        config: SableLibraryConfig
    ) async -> (candidate: SableLibraryProviderCandidate, evidence: [SableLibraryMatchEvidence], score: Double)? {
        guard let providerConfig = planner.providerConfig(for: .wikidata, config: config),
              providerConfig.enabled else {
            return nil
        }

        for sourceID in sourceIDs {
            guard let query = wikidataBookExactIDQuery(for: sourceID),
                  let request = wikidataRequest(query: query, providerConfig: providerConfig),
                  let object = try? await jsonObject(for: request),
                  let candidate = SableLibraryProviderCandidateParser.wikidataCandidates(from: object)
                    .first(where: wikidataBookCandidateIsUseful) else {
                continue
            }

            let evidence = [
                SableLibraryMatchEvidence(
                    kind: sourceID.provider == .wikidata ? .exactProviderID : .providerBridge,
                    provider: sourceID.provider == .wikidata ? .wikidata : sourceID.provider,
                    value: sourceID.stableKey,
                    confidence: sourceID.provider == .wikidata ? 1 : 0.98
                ),
                SableLibraryMatchEvidence(
                    kind: .typeMatch,
                    provider: .wikidata,
                    value: "book",
                    confidence: 0.96
                )
            ]
            let score = confidenceEngine.combinedScore(evidence)
            return (candidate: candidate, evidence: evidence, score: score)
        }

        return nil
    }

    private func bestWikidataBookMatch(
        title: String,
        trustedAliases: [String],
        year: Int?,
        authors: [String],
        config: SableLibraryConfig
    ) async -> (candidate: SableLibraryProviderCandidate, evidence: [SableLibraryMatchEvidence], score: Double)? {
        guard let providerConfig = planner.providerConfig(for: .wikidata, config: config),
              providerConfig.enabled else {
            return nil
        }

        let queryTitles = SableLibraryProviderQueryCleaner.searchTitles(
            from: [title] + trustedAliases,
            limit: 5,
            includeLooseVariants: true
        )
        var scored: [(candidate: SableLibraryProviderCandidate, evidence: [SableLibraryMatchEvidence], score: Double)] = []

        for queryTitle in queryTitles {
            guard let query = wikidataBookTitleQuery(title: queryTitle),
                  let request = wikidataRequest(query: query, providerConfig: providerConfig),
                  let object = try? await jsonObject(for: request) else {
                continue
            }

            let candidates = SableLibraryProviderCandidateParser.wikidataCandidates(from: object)
                .filter(wikidataBookCandidateIsUseful)
            for candidate in candidates {
                if let assessment = wikidataBookMatchAssessment(
                    candidate,
                    queryTitle: queryTitle,
                    trustedTitle: title,
                    aliases: trustedAliases,
                    year: year,
                    authors: authors
                ) {
                    scored.append(assessment)
                }
            }

            if !scored.isEmpty {
                break
            }

            await sleepForProviderDelay(providerConfig)
        }

        let sorted = scored.sorted { $0.score > $1.score }
        guard let best = sorted.first else { return nil }
        if sorted.count > 1,
           sorted[1].score >= 0.94,
           best.score - sorted[1].score < 0.04,
           bookCatalogCandidateIdentity(best.candidate) != bookCatalogCandidateIdentity(sorted[1].candidate) {
            return nil
        }
        return best
    }

    private func wikidataBookMatchAssessment(
        _ candidate: SableLibraryProviderCandidate,
        queryTitle: String,
        trustedTitle: String,
        aliases: [String],
        year: Int?,
        authors: [String]
    ) -> (candidate: SableLibraryProviderCandidate, evidence: [SableLibraryMatchEvidence], score: Double)? {
        let titlePool = SableLibraryProviderQueryCleaner.searchTitles(
            from: [trustedTitle, queryTitle] + aliases,
            limit: 12,
            includeLooseVariants: true
        )
        let candidateTitles = uniqueStrings([candidate.title] + candidate.aliases)
        let titleScore = titlePool
            .flatMap { localTitle in
                candidateTitles.map { providerTitle in
                    confidenceEngine.titleSimilarity(localTitle, providerTitle)
                }
            }
            .max() ?? 0

        let yearMatch: Bool
        if let year, let candidateYear = candidate.year {
            yearMatch = abs(year - candidateYear) <= 1
        } else {
            yearMatch = false
        }
        let authorMatch = hasStringOverlap(authors, candidate.authors)
            || queryMentionsAny(candidate.authors, in: titlePool + [queryTitle])
        let hasCatalogBridge = candidate.sourceIDs.contains { $0.provider == .openLibrary }

        let trusted =
            titleScore >= 0.99
            || (titleScore >= 0.96 && (authorMatch || yearMatch || hasCatalogBridge))
            || (titleScore >= 0.94 && authorMatch && (yearMatch || hasCatalogBridge))
        guard trusted else { return nil }

        var evidence = [
            SableLibraryMatchEvidence(
                kind: .titleSimilarity,
                provider: .wikidata,
                value: candidate.title,
                confidence: titleScore
            ),
            SableLibraryMatchEvidence(
                kind: .typeMatch,
                provider: .wikidata,
                value: "book",
                confidence: 0.96
            )
        ]
        if authorMatch {
            evidence.append(
                SableLibraryMatchEvidence(
                    kind: .localSidecar,
                    provider: .wikidata,
                    value: "author:\(candidate.authors.first ?? authors.first ?? "")",
                    confidence: 0.96
                )
            )
        }
        if yearMatch, let candidateYear = candidate.year {
            evidence.append(
                SableLibraryMatchEvidence(
                    kind: .yearMatch,
                    provider: .wikidata,
                    value: "\(candidateYear)",
                    confidence: 0.96
                )
            )
        }
        if hasCatalogBridge {
            evidence.append(
                SableLibraryMatchEvidence(
                    kind: .providerBridge,
                    provider: .openLibrary,
                    value: candidate.sourceIDs.first(where: { $0.provider == .openLibrary })?.stableKey ?? "openlibrary",
                    confidence: 0.94
                )
            )
        }

        let score = confidenceEngine.combinedScore(evidence)
        guard score >= 0.94 else { return nil }
        return (candidate: candidate, evidence: evidence, score: score)
    }

    private func wikidataBookCandidateIsUseful(_ candidate: SableLibraryProviderCandidate) -> Bool {
        candidate.sourceIDs.contains { $0.provider == .wikidata }
            && SableLibraryNamingPolicy().normalizedMediaType(candidate.mediaType ?? "") == "Book"
    }

    private func wikidataTitleMatch(
        title: String,
        year: Int?,
        mediaType: String?,
        config: SableLibraryConfig
    ) async -> (candidate: SableLibraryProviderCandidate, score: Double, matchedTitle: String)? {
        guard let providerConfig = planner.providerConfig(for: .wikidata, config: config),
              providerConfig.enabled,
              let query = wikidataTitleQuery(title: title),
              let request = wikidataRequest(query: query, providerConfig: providerConfig),
              let object = try? await jsonObject(for: request) else {
            return nil
        }

        let candidates = SableLibraryProviderCandidateParser.wikidataCandidates(from: object)
            .filter { wikidataCandidateHasUsefulExternalID($0) }
            .filter { wikidataCandidateIsCompatible($0, year: year, mediaType: mediaType) }

        return bestCandidate(
            queryTitle: title,
            candidates: candidates,
            requiredMinimumScore: year == nil ? 0.98 : 0.96
        )
    }

    private func wikidataRequest(
        query: String,
        providerConfig: SableLibraryConfig.MetadataProvider
    ) -> SableLibraryProviderRequest? {
        guard let baseURL = URL(string: providerConfig.apiBaseURL) else { return nil }
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "query", value: query)
        ]
        guard let url = components?.url else { return nil }
        return SableLibraryProviderRequest(
            provider: .wikidata,
            url: url,
            requiresAPIKey: false,
            timeoutSeconds: providerConfig.timeoutSeconds,
            cacheTTLSeconds: providerConfig.cacheTTLSeconds
        )
    }

    private func wikidataQuery(property: String, variable: String, values: [String]) -> String {
        let sparqlValues = values.map(sparqlStringLiteral).joined(separator: " ")
        return """
        SELECT ?item ?tmdbTV ?tmdbMovie ?tvdb ?imdb WHERE {
          VALUES ?\(variable) { \(sparqlValues) }
          ?item wdt:\(property) ?\(variable).
          OPTIONAL { ?item wdt:P4983 ?tmdbTV. }
          OPTIONAL { ?item wdt:P4947 ?tmdbMovie. }
          OPTIONAL { ?item wdt:P4835 ?tvdb. }
          OPTIONAL { ?item wdt:P345 ?imdb. }
        }
        LIMIT 3
        """
    }

    private func wikidataExactIDQuery(for sourceID: SableLibrarySourceID) -> String? {
        let value = sourceID.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        let whereClause: String
        switch sourceID.provider {
        case .imdb:
            guard value.range(of: #"^tt\d+$"#, options: .regularExpression) != nil else { return nil }
            whereClause = """
              VALUES ?imdb { \(sparqlStringLiteral(value)) }
              ?item wdt:P345 ?imdb.
            """
        case .tmdb:
            guard value.range(of: #"^\d+$"#, options: .regularExpression) != nil else { return nil }
            whereClause = """
              {
                VALUES ?tmdbTV { \(sparqlStringLiteral(value)) }
                ?item wdt:P4983 ?tmdbTV.
              }
              UNION
              {
                VALUES ?tmdbMovie { \(sparqlStringLiteral(value)) }
                ?item wdt:P4947 ?tmdbMovie.
              }
            """
        case .tvdb:
            guard value.range(of: #"^\d+$"#, options: .regularExpression) != nil else { return nil }
            whereClause = """
              VALUES ?tvdb { \(sparqlStringLiteral(value)) }
              ?item wdt:P4835 ?tvdb.
            """
        case .wikidata:
            guard value.range(of: #"^Q\d+$"#, options: .regularExpression) != nil else { return nil }
            whereClause = """
              VALUES ?item { wd:\(value) }
            """
        case .tvmaze, .mangabaka, .ranobedb, .openLibrary, .myAnimeList, .anilist, .local:
            return nil
        }

        return wikidataCandidateQuery(whereClause: whereClause, limit: 5)
    }

    private func wikidataBookExactIDQuery(for sourceID: SableLibrarySourceID) -> String? {
        let value = sourceID.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        let whereClause: String
        switch sourceID.provider {
        case .wikidata:
            guard value.range(of: #"^Q\d+$"#, options: .regularExpression) != nil else { return nil }
            whereClause = """
              VALUES ?item { wd:\(value) }
              ?item wdt:P31/wdt:P279* ?bookType.
              VALUES ?allowedBookType { wd:Q571 wd:Q8261 wd:Q7725634 wd:Q47461344 wd:Q3331189 }
              FILTER(?bookType = ?allowedBookType)
            """
        case .openLibrary:
            guard let olid = openLibrarySPARQLID(from: value) else { return nil }
            whereClause = """
              VALUES ?openLibrary { \(sparqlStringLiteral(olid)) }
              ?item wdt:P648 ?openLibrary.
              ?item wdt:P31/wdt:P279* ?bookType.
              VALUES ?allowedBookType { wd:Q571 wd:Q8261 wd:Q7725634 wd:Q47461344 wd:Q3331189 }
              FILTER(?bookType = ?allowedBookType)
            """
        case .mangabaka, .ranobedb, .myAnimeList, .anilist, .tvmaze, .tmdb, .tvdb, .imdb, .local:
            return nil
        }

        return wikidataCandidateQuery(whereClause: whereClause, limit: 5)
    }

    private func wikidataTitleQuery(title: String) -> String? {
        let queryTitle = SableLibraryProviderQueryCleaner.searchTitle(from: title) ?? title
        let trimmed = queryTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let whereClause = """
          SERVICE wikibase:mwapi {
            bd:serviceParam wikibase:endpoint "www.wikidata.org";
                            wikibase:api "EntitySearch";
                            mwapi:search \(sparqlStringLiteral(trimmed));
                            mwapi:language "en".
            ?item wikibase:apiOutputItem mwapi:item.
          }
          OPTIONAL { ?item wdt:P345 ?imdb. }
          OPTIONAL { ?item wdt:P4983 ?tmdbTV. }
          OPTIONAL { ?item wdt:P4947 ?tmdbMovie. }
          OPTIONAL { ?item wdt:P4835 ?tvdb. }
          FILTER(BOUND(?imdb) || BOUND(?tmdbTV) || BOUND(?tmdbMovie) || BOUND(?tvdb))
        """

        return wikidataCandidateQuery(whereClause: whereClause, limit: 10)
    }

    private func wikidataBookTitleQuery(title: String) -> String? {
        let queryTitle = SableLibraryProviderQueryCleaner.searchTitle(from: title) ?? title
        let trimmed = queryTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let whereClause = """
          SERVICE wikibase:mwapi {
            bd:serviceParam wikibase:endpoint "www.wikidata.org";
                            wikibase:api "EntitySearch";
                            mwapi:search \(sparqlStringLiteral(trimmed));
                            mwapi:language "en".
            ?item wikibase:apiOutputItem mwapi:item.
          }
          ?item wdt:P31/wdt:P279* ?bookType.
          VALUES ?allowedBookType { wd:Q571 wd:Q8261 wd:Q7725634 wd:Q47461344 wd:Q3331189 }
          FILTER(?bookType = ?allowedBookType)
        """

        return wikidataCandidateQuery(whereClause: whereClause, limit: 10)
    }

    private func wikidataCandidateQuery(whereClause: String, limit: Int) -> String {
        """
        SELECT ?item ?itemLabel ?releaseYear ?startYear ?tmdbTV ?tmdbMovie ?tvdb ?imdb ?movieType ?tvSeriesType ?televisionType ?animeType ?bookMediaType ?openLibrary ?isbn13 ?authorLabel ?publisherLabel ?seriesLabel ?partOfLabel ?volume WHERE {
          \(whereClause)
          OPTIONAL { ?item wdt:P31/wdt:P279* wd:Q11424. BIND("movie" AS ?movieType) }
          OPTIONAL { ?item wdt:P31/wdt:P279* wd:Q5398426. BIND("tv" AS ?tvSeriesType) }
          OPTIONAL { ?item wdt:P31/wdt:P279* wd:Q15416. BIND("tv" AS ?televisionType) }
          OPTIONAL { ?item wdt:P31/wdt:P279* wd:Q1107. BIND("tv" AS ?animeType) }
          OPTIONAL {
            ?item wdt:P31/wdt:P279* ?bookMediaClass.
            VALUES ?bookMediaClass { wd:Q571 wd:Q8261 wd:Q7725634 wd:Q47461344 wd:Q3331189 }
            BIND("book" AS ?bookMediaType)
          }
          OPTIONAL { ?item wdt:P577 ?releaseDate. BIND(YEAR(?releaseDate) AS ?releaseYear) }
          OPTIONAL { ?item wdt:P580 ?startDate. BIND(YEAR(?startDate) AS ?startYear) }
          OPTIONAL { ?item wdt:P648 ?openLibrary. }
          OPTIONAL { ?item wdt:P212 ?isbn13. }
          OPTIONAL { ?item wdt:P50 ?author. }
          OPTIONAL { ?item wdt:P123 ?publisher. }
          OPTIONAL { ?item wdt:P179 ?series. }
          OPTIONAL { ?item wdt:P361 ?partOf. }
          OPTIONAL { ?item wdt:P478 ?volume. }
          SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
        }
        LIMIT \(max(1, limit))
        """
    }

    private func openLibrarySPARQLID(from value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if let range = trimmed.range(of: #"OL\d+[WM]"#, options: .regularExpression) {
            return String(trimmed[range])
        }
        return nil
    }

    private func sparqlStringLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: #"\"#, with: #"\\\\"#)
            .replacingOccurrences(of: #"""#, with: #"\""#)
        return "\"\(escaped)\""
    }

    private func wikidataCandidateHasUsefulExternalID(_ candidate: SableLibraryProviderCandidate) -> Bool {
        candidate.sourceIDs.contains { sourceID in
            sourceID.provider == .imdb || sourceID.provider == .tmdb || sourceID.provider == .tvdb
        }
    }

    private func wikidataCandidateIsCompatible(
        _ candidate: SableLibraryProviderCandidate,
        year: Int?,
        mediaType: String?
    ) -> Bool {
        if let year,
           let candidateYear = candidate.year,
           abs(year - candidateYear) > 1 {
            return false
        }

        guard let mediaType,
              let candidateMediaType = candidate.mediaType else {
            return true
        }

        return isMovieMediaType(mediaType) == isMovieMediaType(candidateMediaType)
    }

    private func wikidataBridgeEvidenceValue(from sourceIDs: [SableLibrarySourceID]) -> String {
        if let imdbID = sourceIDs.first(where: { $0.provider == .imdb })?.value {
            return "imdb:\(imdbID)"
        }
        if let tvdbID = sourceIDs.first(where: { $0.provider == .tvdb })?.value {
            return "tvdb:\(tvdbID)"
        }
        return "external-id"
    }

    private func bestRanobeDBSeriesMatch(
        title: String,
        providerConfig: SableLibraryConfig.MetadataProvider
    ) async -> (candidate: SableLibraryProviderCandidate, score: Double, matchedTitle: String)? {
        let queryTitles = ranobeDBSeriesQueryTitles(for: title)

        for queryTitle in queryTitles {
            guard let request = ranobeDBSeriesSearchRequest(query: queryTitle, providerConfig: providerConfig),
                  let searchObject = try? await jsonObject(for: request) else {
                continue
            }

            let candidates = SableLibraryProviderCandidateParser.ranobeDBSeriesCandidates(from: searchObject)

            if let strictMatch = bestCandidate(
                queryTitle: queryTitle,
                candidates: candidates,
                requiredMinimumScore: 0.96
            ) {
                return strictMatch
            }

            if let supportedMatch = bestCandidateWithTrustedAliases(
                queryTitle: queryTitle,
                trustedAliases: queryTitles,
                candidates: candidates
            ) {
                return supportedMatch
            }

            let delay = max(0, providerConfig.requestDelaySeconds)
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }

        return nil
    }

    private func ranobeDBSeriesQueryTitles(for title: String) -> [String] {
        SableLibraryProviderQueryCleaner.searchTitles(
            from: [title],
            limit: 10,
            includeLooseVariants: true
        )
    }

    private func ranobeDBSeriesSearchRequest(
        query: String,
        providerConfig: SableLibraryConfig.MetadataProvider
    ) -> SableLibraryProviderRequest? {
        guard let url = ranobeDBURL(path: ["series"], queryItems: [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "rl", value: "en"),
            URLQueryItem(name: "rll", value: "or"),
            URLQueryItem(name: "limit", value: "10")
        ], providerConfig: providerConfig) else {
            return nil
        }
        return SableLibraryProviderRequest(
            provider: .ranobedb,
            url: url,
            requiresAPIKey: providerConfig.requiresAPIKey,
            timeoutSeconds: providerConfig.timeoutSeconds,
            cacheTTLSeconds: providerConfig.cacheTTLSeconds
        )
    }

    private func ranobeDBDetailRequest(
        path: [String],
        providerConfig: SableLibraryConfig.MetadataProvider
    ) -> SableLibraryProviderRequest? {
        guard let url = ranobeDBURL(path: path, queryItems: [], providerConfig: providerConfig) else {
            return nil
        }
        return SableLibraryProviderRequest(
            provider: .ranobedb,
            url: url,
            requiresAPIKey: providerConfig.requiresAPIKey,
            timeoutSeconds: providerConfig.timeoutSeconds,
            cacheTTLSeconds: providerConfig.cacheTTLSeconds
        )
    }

    private func ranobeDBURL(
        path: [String],
        queryItems: [URLQueryItem],
        providerConfig: SableLibraryConfig.MetadataProvider
    ) -> URL? {
        var base = providerConfig.apiBaseURL
        if !base.hasSuffix("/") {
            base += "/"
        }
        guard let baseURL = URL(string: base) else { return nil }
        let endpoint = path.reduce(baseURL) { partialURL, component in
            partialURL.appendingPathComponent(component)
        }
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems.isEmpty ? nil : queryItems
        return components?.url
    }

    private func enrichedRanobeDBBookDetails(
        parts: [SableLibraryReadingPartMetadata],
        detailedBookIDs: Set<String>,
        providerConfig: SableLibraryConfig.MetadataProvider,
        preferredTitle: String
    ) async -> RanobeDBBookDetailEnrichment {
        var enriched = parts
        let targets = Self.ranobeDBBookDetailTargets(
            parts: parts,
            detailedBookIDs: detailedBookIDs
        )
        let requestedBookIDs = targets.compactMap(\.sourceID?.value)

        let parallelism = max(1, min(
            SableLibraryAdaptiveWorkBudget.parallelism(minimum: 8, multiplier: 2, cap: 16),
            targets.count
        ))
        var detailsByNumber: [Int: SableLibraryReadingPartMetadata] = [:]
        var responsesByNumber: [Int: SableLibraryJSONValue] = [:]
        var fetchedBookIDsByNumber: [Int: String] = [:]
        var chunkStart = 0

        while chunkStart < targets.count {
            let chunkEnd = min(targets.count, chunkStart + parallelism)
            let chunk = Array(targets[chunkStart..<chunkEnd])
            let results = await withTaskGroup(of: (Int, String, SableLibraryReadingPartMetadata, SableLibraryJSONValue?)?.self) { group -> [(Int, String, SableLibraryReadingPartMetadata, SableLibraryJSONValue?)] in
                for target in chunk {
                    group.addTask {
                        guard let bookID = target.sourceID?.value,
                              let request = ranobeDBDetailRequest(path: ["book", bookID], providerConfig: providerConfig),
                              let object = try? await jsonObject(for: request) else {
                            return nil
                        }
                        let response = SableLibraryJSONValue.from(object)
                        let detailed = SableLibraryProviderCandidateParser.ranobeDBReadingPartDetail(
                                from: object,
                                preferredTitle: preferredTitle,
                                fallback: target
                              ) ?? target
                        return (target.number, bookID, detailed, response)
                    }
                }

                var collected: [(Int, String, SableLibraryReadingPartMetadata, SableLibraryJSONValue?)] = []
                for await result in group {
                    if let result {
                        collected.append(result)
                    }
                }
                return collected
            }

            for (number, bookID, detail, response) in results {
                detailsByNumber[number] = detail
                responsesByNumber[number] = response
                fetchedBookIDsByNumber[number] = bookID
            }
            chunkStart += parallelism
        }

        for index in enriched.indices {
            let number = enriched[index].number
            if let detail = detailsByNumber[number] {
                enriched[index] = mergedRanobeDBBookDetail(base: enriched[index], detail: detail)
            }
        }

        let apiBookResponses = responsesByNumber.keys.sorted().compactMap { number -> SableLibraryJSONValue? in
            guard let response = responsesByNumber[number] else { return nil }
            return .object([
                "volume_number": .int(number),
                "response": response
            ])
        }
        let fetchedBookIDs = fetchedBookIDsByNumber.keys.sorted().compactMap { fetchedBookIDsByNumber[$0] }
        let fetchedBookIDSet = Set(fetchedBookIDs)
        return RanobeDBBookDetailEnrichment(
            parts: enriched,
            apiBookResponses: apiBookResponses,
            requestedBookIDs: requestedBookIDs,
            fetchedBookIDs: fetchedBookIDs,
            failedBookIDs: requestedBookIDs.filter { !fetchedBookIDSet.contains($0) }
        )
    }

    nonisolated static func ranobeDBBookDetailTargets(
        parts: [SableLibraryReadingPartMetadata],
        detailedBookIDs: Set<String>
    ) -> [SableLibraryReadingPartMetadata] {
        parts
            .filter { part in
                guard let sourceID = part.sourceID,
                      sourceID.provider == .ranobedb else {
                    return false
                }
                return !detailedBookIDs.contains(sourceID.value)
            }
            .sorted { lhs, rhs in
                if lhs.number != rhs.number { return lhs.number < rhs.number }
                return (lhs.sourceID?.value ?? "") < (rhs.sourceID?.value ?? "")
            }
    }

    private func ranobeDBProviderPayloads(
        seriesResponse: [String: Any],
        bookResponses: [SableLibraryJSONValue],
        seriesBookIDs: [String],
        knownBookIDsBeforeRefresh: [String],
        detailedBookIDsBeforeRefresh: [String],
        newReleaseBookIDs: [String],
        requestedBookIDs: [String],
        fetchedBookIDs: [String],
        failedBookIDs: [String],
        fetchedAt: String
    ) -> [String: SableLibraryJSONValue] {
        var payload: [String: SableLibraryJSONValue] = [
            "schema_version": .int(1),
            "fetched_at": .string(fetchedAt),
            "series_endpoint": .string("GET /series/[id]"),
            "delta": .object([
                "series_book_ids": .array(seriesBookIDs.map(SableLibraryJSONValue.string)),
                "known_book_ids_before_refresh": .array(knownBookIDsBeforeRefresh.map(SableLibraryJSONValue.string)),
                "detailed_book_ids_before_refresh": .array(detailedBookIDsBeforeRefresh.map(SableLibraryJSONValue.string)),
                "new_release_book_ids": .array(newReleaseBookIDs.map(SableLibraryJSONValue.string)),
                "requested_book_detail_ids": .array(requestedBookIDs.map(SableLibraryJSONValue.string)),
                "fetched_book_detail_ids": .array(fetchedBookIDs.map(SableLibraryJSONValue.string)),
                "failed_book_detail_ids": .array(failedBookIDs.map(SableLibraryJSONValue.string))
            ])
        ]
        if let series = seriesResponse["series"] as? [String: Any],
           let seriesID = providerPayloadText(series["id"]) {
            payload["series_id"] = .string(seriesID)
        }
        if let series = SableLibraryJSONValue.from(seriesResponse["series"]) {
            payload["series"] = series
        }
        if let response = SableLibraryJSONValue.from(seriesResponse) {
            payload["series_response"] = response
        }
        if !bookResponses.isEmpty {
            payload["book_endpoint"] = .string("GET /book/[id]")
            payload["book_responses"] = .array(bookResponses)
            payload["book_response_count"] = .int(bookResponses.count)
        }
        return [SableLibraryMetadataProvider.ranobedb.rawValue: .object(payload)]
    }

    private func providerPayloadText(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let value = value as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let value = value as? Int {
            return String(value)
        }
        if let value = value as? NSNumber {
            return String(describing: value)
        }
        return nil
    }

    private func mergedRanobeDBBookDetail(
        base: SableLibraryReadingPartMetadata,
        detail: SableLibraryReadingPartMetadata
    ) -> SableLibraryReadingPartMetadata {
        var result = detail
        if result.sourceID == nil {
            result.sourceID = base.sourceID
        }
        if result.subtitle == nil {
            result.subtitle = base.subtitle
        }
        if isPlainVolumeSuffix(result.fileSuffix, number: result.number),
           !isPlainVolumeSuffix(base.fileSuffix, number: base.number) {
            result.fileSuffix = base.fileSuffix
        }
        if result.releaseYear == nil {
            result.releaseYear = base.releaseYear
        }
        if result.releaseDate == nil {
            result.releaseDate = base.releaseDate
        }
        if result.description == nil {
            result.description = base.description
        }
        return result
    }

    private func isPlainVolumeSuffix(_ suffix: String, number: Int) -> Bool {
        let paddedNumber = String(format: "%02d", number)
        let normalized = suffix
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return normalized == "vol \(paddedNumber)"
            || normalized == "volume \(paddedNumber)"
            || normalized == "vol \(number)"
            || normalized == "volume \(number)"
    }

    private func openLibraryTitleCandidates(
        trustedTitle: String,
        aliases: [String],
        year: Int?,
        authors: [String],
        publishers: [String],
        config: SableLibraryConfig
    ) async -> [SableLibraryProviderCandidate] {
        guard let providerConfig = planner.providerConfig(for: .openLibrary, config: config),
              providerConfig.enabled else {
            return []
        }

        let queryTitles = SableLibraryProviderQueryCleaner.searchTitles(
            from: [trustedTitle] + aliases,
            limit: 4,
            includeLooseVariants: true
        )

        var accepted: [SableLibraryProviderCandidate] = []

        for queryTitle in queryTitles {
            for request in openLibraryTitleRequests(
                title: queryTitle,
                authors: authors,
                providerConfig: providerConfig
            ) {
                guard let object = try? await jsonObject(for: request) else {
                    continue
                }

                let candidates = SableLibraryProviderCandidateParser.openLibraryCandidates(from: object)
                for candidate in candidates {
                    if openLibraryTitleCandidateIsTrusted(
                        candidate,
                        trustedTitle: trustedTitle,
                        aliases: aliases,
                        year: year,
                        authors: authors,
                        publishers: publishers
                    ) {
                        accepted.append(candidate)
                    }
                }

                if !accepted.isEmpty {
                    break
                }

                await sleepForOpenLibraryDelay(providerConfig)
            }

            if !accepted.isEmpty {
                break
            }
        }

        return accepted
    }

    private func bestOpenLibraryBookMatch(
        title: String,
        trustedAliases: [String],
        year: Int?,
        authors: [String],
        publishers: [String],
        config: SableLibraryConfig
    ) async -> (candidate: SableLibraryProviderCandidate, evidence: [SableLibraryMatchEvidence], score: Double)? {
        guard let providerConfig = planner.providerConfig(for: .openLibrary, config: config),
              providerConfig.enabled else {
            return nil
        }

        let queryTitles = SableLibraryProviderQueryCleaner.searchTitles(
            from: [title] + trustedAliases,
            limit: 5,
            includeLooseVariants: true
        )
        var scored: [(candidate: SableLibraryProviderCandidate, evidence: [SableLibraryMatchEvidence], score: Double)] = []

        for queryTitle in queryTitles {
            for request in openLibraryTitleRequests(
                title: queryTitle,
                authors: authors,
                providerConfig: providerConfig
            ) {
                guard let object = try? await jsonObject(for: request) else {
                    continue
                }

                let candidates = SableLibraryProviderCandidateParser.openLibraryCandidates(from: object)
                for candidate in candidates {
                    if let assessment = openLibraryBookMatchAssessment(
                        candidate,
                        queryTitle: queryTitle,
                        trustedTitle: title,
                        aliases: trustedAliases,
                        year: year,
                        authors: authors,
                        publishers: publishers
                    ) {
                        scored.append(assessment)
                    }
                }

                if !scored.isEmpty {
                    break
                }

                await sleepForOpenLibraryDelay(providerConfig)
            }

            if !scored.isEmpty {
                break
            }
        }

        let sorted = scored.sorted { $0.score > $1.score }
        guard let best = sorted.first else { return nil }
        if sorted.count > 1,
           sorted[1].score >= 0.94,
           best.score - sorted[1].score < 0.04,
           openLibraryCandidateIdentity(best.candidate) != openLibraryCandidateIdentity(sorted[1].candidate) {
            return nil
        }
        return best
    }

    private func openLibraryBookMatchAssessment(
        _ candidate: SableLibraryProviderCandidate,
        queryTitle: String,
        trustedTitle: String,
        aliases: [String],
        year: Int?,
        authors: [String],
        publishers: [String]
    ) -> (candidate: SableLibraryProviderCandidate, evidence: [SableLibraryMatchEvidence], score: Double)? {
        guard openLibraryCandidateIsEnglishCompatible(candidate) else { return nil }

        let titlePool = SableLibraryProviderQueryCleaner.searchTitles(
            from: [trustedTitle, queryTitle] + aliases,
            limit: 12,
            includeLooseVariants: true
        )
        let candidateTitles = uniqueStrings([candidate.title] + candidate.aliases)
        let plainTitleScore = titlePool
            .flatMap { localTitle in
                candidateTitles.map { providerTitle in
                    confidenceEngine.titleSimilarity(localTitle, providerTitle)
                }
            }
            .max() ?? 0

        let localTitleAuthorPairs = titlePool.flatMap { localTitle in
            authors.map { "\(localTitle) \($0)" }
        }
        let providerTitleAuthorPairs = candidateTitles.flatMap { candidateTitle in
            candidate.authors.map { "\(candidateTitle) \($0)" }
        }
        let titleAuthorScore = localTitleAuthorPairs
            .flatMap { localPair in
                providerTitleAuthorPairs.map { providerPair in
                    confidenceEngine.titleSimilarity(localPair, providerPair)
                }
            }
            .max() ?? 0

        let yearMatch: Bool
        if let year, let candidateYear = candidate.year {
            yearMatch = abs(year - candidateYear) <= 1
        } else {
            yearMatch = false
        }
        let authorMatch = hasStringOverlap(authors, candidate.authors)
            || queryMentionsAny(candidate.authors, in: titlePool + [queryTitle])
        let publisherMatch = hasStringOverlap(publishers, candidate.publishers)

        let bestTitleScore = max(plainTitleScore, titleAuthorScore)
        let trusted =
            titleAuthorScore >= 0.97
            || (plainTitleScore >= 0.98 && (authorMatch || publisherMatch || yearMatch))
            || (plainTitleScore >= 0.94 && (authorMatch || publisherMatch))
            || (plainTitleScore >= 0.94 && yearMatch && !candidate.authors.isEmpty)
        guard trusted else { return nil }

        var evidence = [
            SableLibraryMatchEvidence(
                kind: .titleSimilarity,
                provider: .openLibrary,
                value: candidate.title,
                confidence: bestTitleScore
            )
        ]
        if authorMatch {
            evidence.append(
                SableLibraryMatchEvidence(
                    kind: .localSidecar,
                    provider: .openLibrary,
                    value: "author:\(candidate.authors.first ?? authors.first ?? "")",
                    confidence: 0.96
                )
            )
        }
        if publisherMatch {
            evidence.append(
                SableLibraryMatchEvidence(
                    kind: .localSidecar,
                    provider: .openLibrary,
                    value: "publisher:\(candidate.publishers.first ?? publishers.first ?? "")",
                    confidence: 0.94
                )
            )
        }
        if yearMatch, let candidateYear = candidate.year {
            evidence.append(
                SableLibraryMatchEvidence(
                    kind: .yearMatch,
                    provider: .openLibrary,
                    value: "\(candidateYear)",
                    confidence: 0.96
                )
            )
        }

        let score = confidenceEngine.combinedScore(evidence)
        guard score >= 0.94 else { return nil }
        return (candidate: candidate, evidence: evidence, score: score)
    }

    private func openLibraryTitleCandidateIsTrusted(
        _ candidate: SableLibraryProviderCandidate,
        trustedTitle: String,
        aliases: [String],
        year: Int?,
        authors: [String],
        publishers: [String]
    ) -> Bool {
        guard openLibraryCandidateIsEnglishCompatible(candidate) else { return false }

        let titlePool = SableLibraryProviderQueryCleaner.searchTitles(
            from: [trustedTitle] + aliases,
            limit: 12,
            includeLooseVariants: true
        )
        let bestTitleScore = titlePool
            .map { confidenceEngine.titleSimilarity($0, candidate.title) }
            .max() ?? 0

        let yearMatch: Bool
        if let year, let candidateYear = candidate.year {
            yearMatch = abs(year - candidateYear) <= 1
        } else {
            yearMatch = false
        }

        let authorMatch = hasStringOverlap(authors, candidate.authors)
        let publisherMatch = hasStringOverlap(publishers, candidate.publishers)

        if bestTitleScore >= 0.98 {
            return true
        }

        if bestTitleScore >= 0.94, yearMatch {
            return true
        }

        if bestTitleScore >= 0.92, authorMatch || publisherMatch {
            return true
        }

        return false
    }

    private func openLibraryCandidateIsEnglishCompatible(_ candidate: SableLibraryProviderCandidate) -> Bool {
        bookCatalogCandidateIsEnglishCompatible(candidate)
    }

    private func bookCatalogCandidateIsEnglishCompatible(_ candidate: SableLibraryProviderCandidate) -> Bool {
        let languages = candidate.languages
            .map { normalizedLooseKey($0) }
            .filter { !$0.isEmpty }
        guard !languages.isEmpty else { return true }

        return languages.contains { language in
            language == "eng"
                || language == "en"
                || language == "english"
                || language.contains(" english ")
        }
    }

    private func queryMentionsAny(_ candidates: [String], in queries: [String]) -> Bool {
        let queryKeys = queries.map(normalizedLooseKey).filter { !$0.isEmpty }
        let candidateKeys = candidates.map(normalizedLooseKey).filter { !$0.isEmpty }
        guard !queryKeys.isEmpty, !candidateKeys.isEmpty else { return false }

        return candidateKeys.contains { candidate in
            queryKeys.contains { query in
                query.contains(candidate) || candidate.contains(query)
            }
        }
    }

    private func openLibraryCandidateIdentity(_ candidate: SableLibraryProviderCandidate) -> String {
        if let sourceID = candidate.sourceIDs.first(where: { $0.provider == .openLibrary }) {
            return sourceID.stableKey
        }
        return normalizedLooseKey(([candidate.title] + candidate.authors).joined(separator: " "))
    }

    private func bookCatalogCandidateIdentity(_ candidate: SableLibraryProviderCandidate) -> String {
        if let sourceID = candidate.sourceIDs.first {
            return sourceID.stableKey
        }
        return normalizedLooseKey(([candidate.title] + candidate.authors).joined(separator: " "))
    }

    private func hasStringOverlap(_ lhs: [String], _ rhs: [String]) -> Bool {
        let left = Set(lhs.map(normalizedLooseKey).filter { !$0.isEmpty })
        let right = Set(rhs.map(normalizedLooseKey).filter { !$0.isEmpty })
        guard !left.isEmpty, !right.isEmpty else { return false }

        return !left.isDisjoint(with: right)
    }

    private func normalizedLooseKey(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func openLibraryTitleRequests(
        title: String,
        authors: [String],
        providerConfig: SableLibraryConfig.MetadataProvider
    ) -> [SableLibraryProviderRequest] {
        var requests: [SableLibraryProviderRequest] = []

        if let author = uniqueStrings(authors).first,
           let request = openLibraryTitleRequest(
            title: title,
            author: author,
            englishOnly: true,
            providerConfig: providerConfig
           ) {
            requests.append(request)
        }

        if let request = openLibraryTitleRequest(
            title: title,
            author: nil,
            englishOnly: true,
            providerConfig: providerConfig
        ) {
            requests.append(request)
        }

        return requests
    }

    private func openLibraryTitleRequest(
        title: String,
        author: String?,
        englishOnly: Bool,
        providerConfig: SableLibraryConfig.MetadataProvider
    ) -> SableLibraryProviderRequest? {
        var base = providerConfig.apiBaseURL
        if !base.hasSuffix("/") {
            base += "/"
        }
        guard let baseURL = URL(string: base) else { return nil }

        let endpoint = baseURL.appendingPathComponent("search.json")
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)

        var queryItems: [URLQueryItem]
        if englishOnly {
            queryItems = [
                URLQueryItem(name: "q", value: #"title:"\#(openLibraryEscapedQueryTitle(title))" language:eng"#),
                URLQueryItem(name: "lang", value: "en")
            ]
        } else {
            queryItems = [
                URLQueryItem(name: "title", value: title),
                URLQueryItem(name: "lang", value: "en")
            ]
        }
        if let author = author?.trimmingCharacters(in: .whitespacesAndNewlines),
           !author.isEmpty {
            queryItems.append(URLQueryItem(name: "author", value: author))
        }
        queryItems.append(contentsOf: [
            URLQueryItem(name: "fields", value: "key,title,author_name,first_publish_year,isbn,edition_key,publisher,subject,language,editions,editions.key,editions.title,editions.language"),
            URLQueryItem(name: "limit", value: "10")
        ])
        components?.queryItems = queryItems

        guard let url = components?.url else { return nil }
        return SableLibraryProviderRequest(
            provider: .openLibrary,
            url: url,
            requiresAPIKey: providerConfig.requiresAPIKey,
            timeoutSeconds: providerConfig.timeoutSeconds,
            cacheTTLSeconds: providerConfig.cacheTTLSeconds
        )
    }

    private func openLibraryEscapedQueryTitle(_ title: String) -> String {
        title
            .replacingOccurrences(of: #"["\\]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sleepForOpenLibraryDelay(_ providerConfig: SableLibraryConfig.MetadataProvider) async {
        await sleepForProviderDelay(providerConfig)
    }

    private func sleepForProviderDelay(_ providerConfig: SableLibraryConfig.MetadataProvider) async {
        let delay = max(0, providerConfig.requestDelaySeconds)
        if delay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    }

    private func openLibraryCandidates(
        for sourceIDs: [SableLibrarySourceID],
        config: SableLibraryConfig
    ) async -> [SableLibraryProviderCandidate] {
        guard !sourceIDs.isEmpty,
              let providerConfig = planner.providerConfig(for: .openLibrary, config: config),
              providerConfig.enabled else {
            return []
        }

        var candidates: [SableLibraryProviderCandidate] = []
        for sourceID in sourceIDs.prefix(3) {
            guard let request = openLibraryExactIDRequest(sourceID: sourceID, providerConfig: providerConfig),
                  let object = try? await jsonObject(for: request) else {
                continue
            }
            let matches = SableLibraryProviderCandidateParser.openLibraryCandidates(from: object)
                .map { openLibraryCandidate($0, adding: sourceID) }
            candidates.append(contentsOf: matches)
            let delay = max(0, providerConfig.requestDelaySeconds)
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        return candidates
    }

    private func openLibraryCandidates(
        for isbn13: [String],
        config: SableLibraryConfig
    ) async -> [SableLibraryProviderCandidate] {
        guard !isbn13.isEmpty,
              let providerConfig = planner.providerConfig(for: .openLibrary, config: config),
              providerConfig.enabled else {
            return []
        }

        var candidates: [SableLibraryProviderCandidate] = []
        for isbn in isbn13.prefix(3) {
            guard let request = openLibraryISBNRequest(isbn: isbn, providerConfig: providerConfig),
                  let object = try? await jsonObject(for: request) else {
                continue
            }
            let matches = SableLibraryProviderCandidateParser.openLibraryCandidates(from: object)
                .filter { $0.isbn13.contains(isbn) }
            candidates.append(contentsOf: matches)
            let delay = max(0, providerConfig.requestDelaySeconds)
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        return candidates
    }

    private func openLibraryExactIDRequest(
        sourceID: SableLibrarySourceID,
        providerConfig: SableLibraryConfig.MetadataProvider
    ) -> SableLibraryProviderRequest? {
        guard sourceID.provider == .openLibrary,
              let query = openLibraryExactIDQuery(sourceID.value) else {
            return nil
        }

        var base = providerConfig.apiBaseURL
        if !base.hasSuffix("/") {
            base += "/"
        }
        guard let baseURL = URL(string: base) else { return nil }
        let endpoint = baseURL.appendingPathComponent("search.json")
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "lang", value: "en"),
            URLQueryItem(name: "fields", value: "key,title,author_name,first_publish_year,isbn,edition_key,publisher,subject,language,editions,editions.key,editions.title,editions.language"),
            URLQueryItem(name: "limit", value: "3")
        ]
        guard let url = components?.url else { return nil }
        return SableLibraryProviderRequest(
            provider: .openLibrary,
            url: url,
            requiresAPIKey: providerConfig.requiresAPIKey,
            timeoutSeconds: providerConfig.timeoutSeconds,
            cacheTTLSeconds: providerConfig.cacheTTLSeconds
        )
    }

    private func openLibraryExactIDQuery(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard let range = trimmed.range(of: #"OL\d+[WM]"#, options: .regularExpression) else {
            return nil
        }
        let id = String(trimmed[range])
        if id.hasSuffix("W") {
            return "key:/works/\(id)"
        }
        return "edition_key:\(id)"
    }

    private func openLibraryISBNRequest(
        isbn: String,
        providerConfig: SableLibraryConfig.MetadataProvider
    ) -> SableLibraryProviderRequest? {
        var base = providerConfig.apiBaseURL
        if !base.hasSuffix("/") {
            base += "/"
        }
        guard let baseURL = URL(string: base) else { return nil }
        let endpoint = baseURL.appendingPathComponent("search.json")
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "isbn", value: isbn),
            URLQueryItem(name: "lang", value: "en"),
            URLQueryItem(name: "fields", value: "key,title,author_name,first_publish_year,isbn,edition_key,publisher,subject,language,editions,editions.key,editions.title,editions.language"),
            URLQueryItem(name: "limit", value: "3")
        ]
        guard let url = components?.url else { return nil }
        return SableLibraryProviderRequest(
            provider: .openLibrary,
            url: url,
            requiresAPIKey: providerConfig.requiresAPIKey,
            timeoutSeconds: providerConfig.timeoutSeconds,
            cacheTTLSeconds: providerConfig.cacheTTLSeconds
        )
    }

    private func openLibraryCandidate(
        _ candidate: SableLibraryProviderCandidate,
        adding sourceID: SableLibrarySourceID
    ) -> SableLibraryProviderCandidate {
        var candidate = candidate
        candidate.sourceIDs = uniqueSourceIDs(candidate.sourceIDs + [sourceID])
        return candidate
    }

    private func bestCandidate(
        queryTitle: String,
        candidates: [SableLibraryProviderCandidate],
        requiredMinimumScore: Double
    ) -> (candidate: SableLibraryProviderCandidate, score: Double, matchedTitle: String)? {
        let scored = candidates.map { candidate in
            let titles = [candidate.title] + candidate.aliases
            let best = titles
                .map { ($0, confidenceEngine.titleSimilarity(queryTitle, $0)) }
                .max { $0.1 < $1.1 } ?? (candidate.title, 0)
            return (candidate: candidate, score: best.1, matchedTitle: best.0)
        }
        .sorted { lhs, rhs in
            lhs.score > rhs.score
        }

        guard let best = scored.first,
              best.score >= requiredMinimumScore else {
            return nil
        }
        if scored.count > 1, scored[1].score >= 0.94, best.score - scored[1].score < 0.04 {
            return nil
        }
        return best
    }

    private func watchingType(from rawValue: String?) -> SableLibraryWatchingType {
        switch rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "movie", "animemovie", "anime movie":
            return .animeMovie
        case "tv", "tvshow", "tv show", "series", "animetv", "anime tv":
            return .animeTV
        case "ova":
            return .ova
        case "ona":
            return .ona
        case "special", "specials":
            return .special
        default:
            return .unknownVideo
        }
    }

    private func isMovieMediaType(_ mediaType: String) -> Bool {
        switch mediaType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "movie", "animemovie", "anime movie":
            return true
        default:
            return false
        }
    }

    private func yearIsCompatible(reference: Int?, candidate: Int?) -> Bool {
        guard let reference, let candidate else { return true }
        return abs(reference - candidate) <= 1
    }

    private func ttlSeconds(for provider: SableLibraryMetadataProvider, config: SableLibraryConfig) -> TimeInterval {
        planner.providerConfig(for: provider, config: config)?.cacheTTLSeconds ?? 604800
    }

    private func deduplicatedManualCandidates(_ candidates: [SableLibraryProviderCandidate]) -> [SableLibraryProviderCandidate] {
        var seen = Set<String>()
        return candidates.filter { candidate in
            let identity = candidate.sourceIDs.first?.stableKey
                ?? "\(candidate.provider.rawValue):\(manualCandidateKey(candidate.title)):\(candidate.year.map(String.init) ?? "")"
            return seen.insert(identity).inserted
        }
    }

    private func manualCandidateKey(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func uniqueSourceIDs(_ ids: [SableLibrarySourceID]) -> [SableLibrarySourceID] {
        var seen = Set<String>()
        return ids.filter { id in
            seen.insert(id.stableKey).inserted
        }
    }

    private func matchingSourceID(
        in candidateIDs: [SableLibrarySourceID],
        from existingIDs: [SableLibrarySourceID]
    ) -> SableLibrarySourceID? {
        candidateIDs.first { candidateID in
            existingIDs.contains { existingID in
                candidateID.provider == existingID.provider && candidateID.value == existingID.value
            }
        }
    }

    private func uniqueStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let key = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            return seen.insert(key).inserted ? trimmed : nil
        }
    }

    private func uniqueProviders(_ providers: [SableLibraryMetadataProvider]) -> [SableLibraryMetadataProvider] {
        var seen = Set<SableLibraryMetadataProvider>()
        return providers.filter { provider in
            seen.insert(provider).inserted
        }
    }
}
