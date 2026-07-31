//
//  SableLibraryMetadataFoundationTests.swift
//  Sable's LibraryTests
//

import XCTest
@testable import Sable_s_Library

final class SableLibraryMetadataFoundationTests: XCTestCase {
    func testWorkTimingReportsElapsedRateAndRemainingTime() {
        let startedAt = Date(timeIntervalSince1970: 0)
        let now = Date(timeIntervalSince1970: 120)

        let summary = SableLibraryWorkTiming.summary(
            startedAt: startedAt,
            completedCount: 60,
            totalCount: 120,
            unit: "EPUB",
            now: now
        )

        XCTAssertEqual(
            summary,
            "Elapsed 2m 0s; 30.0 EPUB/min; about 2m 0s remaining."
        )
    }

    func testLearningMemoryConservativeMergeDoesNotDoubleCountExistingSignals() {
        let earlier = Date(timeIntervalSince1970: 10)
        let later = Date(timeIntervalSince1970: 20)
        var sharedMemory = SableLibraryLearningMemory()
        sharedMemory.recordMetadataUse(term: "romance", date: earlier)
        sharedMemory.recordMetadataUse(term: "romance", date: earlier)

        var legacyMemory = SableLibraryLearningMemory()
        legacyMemory.recordMetadataUse(term: "romance", date: later)
        legacyMemory.recordMetadataUse(term: "fantasy", date: later)

        let merged = sharedMemory.mergedConservatively(with: legacyMemory)

        XCTAssertEqual(merged.metadataTerms["romance"]?.usedCount, 2)
        XCTAssertEqual(merged.metadataTerms["romance"]?.lastDecisionAt, later)
        XCTAssertEqual(merged.metadataTerms["fantasy"]?.usedCount, 1)
        XCTAssertEqual(merged.metadataTerms["fantasy"]?.lastDecisionAt, later)
    }

    func testSharedContainerUsesMacAppGroupIdentifier() {
        let identifier = SableLibrarySharedContainer.appGroupIdentifier
        XCTAssertTrue(
            identifier == nil
                || identifier?.hasSuffix(".com.annearuki.Sables") == true
        )
    }

    func testFileTypeMatcherSeparatesReadingWatchingAndUnknownFiles() {
        let matcher = SableLibraryFileTypeMatcher(config: .fallback)

        XCTAssertEqual(matcher.mediaDomain(url: URL(fileURLWithPath: "/Library/Book.epub"), isDirectory: false), .reading)
        XCTAssertEqual(matcher.mediaDomain(url: URL(fileURLWithPath: "/Library/Movie.mkv"), isDirectory: false), .watching)
        XCTAssertEqual(matcher.mediaDomain(url: URL(fileURLWithPath: "/Library/Notes.txt"), isDirectory: false), .unknown)
    }

    func testConfidenceEngineAllowsHardEvidenceAndSkipsWeakFuzzyEvidence() {
        let engine = SableLibraryConfidenceEngine()
        let exact = SableLibraryMatchEvidence(
            kind: .exactProviderID,
            provider: .mangabaka,
            value: "1238",
            confidence: 0.99
        )
        let fuzzy = SableLibraryMatchEvidence(
            kind: .titleSimilarity,
            provider: .anilist,
            value: "close title",
            confidence: 0.7
        )

        XCTAssertEqual(engine.decide(evidence: [exact]).outcome, .safeApply)
        XCTAssertEqual(engine.decide(evidence: [fuzzy]).outcome, .leaveUntouched)
    }

    func testConfidenceEngineRoutesCollisionsToAttention() {
        let engine = SableLibraryConfidenceEngine()
        let exact = SableLibraryMatchEvidence(
            kind: .exactISBN,
            provider: .openLibrary,
            value: "9781718372726",
            confidence: 1
        )

        let decision = engine.decide(evidence: [exact], hasCollision: true)

        XCTAssertEqual(decision.outcome, .needsAttention)
    }

    func testSourceIDParserRestoresTrustedReadingIDsFromSableEvidence() {
        let sidecar: [String: Any] = [
            "_sable": [
                "mangabaka": [
                    "manual_series_id": "84345",
                    "matched_id": "84345"
                ],
                "ranobedb": [
                    "series_id": "11430"
                ]
            ],
            "ids": [
                "seriesId": 11431
            ]
        ]

        let ids = SableLibrarySourceIDParser.sourceIDs(from: sidecar) { value in
            switch value {
            case let string as String:
                return string
            case let number as NSNumber:
                return number.stringValue
            default:
                return nil
            }
        }

        XCTAssertTrue(ids.contains(SableLibrarySourceID(provider: .mangabaka, value: "84345")))
        XCTAssertTrue(ids.contains(SableLibrarySourceID(provider: .ranobedb, value: "11430")))
        XCTAssertTrue(ids.contains(SableLibrarySourceID(provider: .ranobedb, value: "11431")))
    }

    func testSourceIDParserAcceptsRanobeDBSeriesIDVariantsAndAmbiguousKeys() {
        let sidecar: [String: Any] = [
            "ids": [
                "series_id": "22111",
                "seriesId": "22112",
                "rdb-id": "22113"
            ],
            "_sable": [
                "ranobedb": [
                    "seriesId": "22114",
                    "ranobedbId": "22115"
                ]
            ]
        ]

        let ids = SableLibrarySourceIDParser.sourceIDs(from: sidecar) { value in
            switch value {
            case let string as String:
                return string
            case let number as NSNumber:
                return number.stringValue
            default:
                return nil
            }
        }

        XCTAssertTrue(ids.contains(SableLibrarySourceID(provider: .ranobedb, value: "22111")))
        XCTAssertTrue(ids.contains(SableLibrarySourceID(provider: .ranobedb, value: "22112")))
        XCTAssertTrue(ids.contains(SableLibrarySourceID(provider: .ranobedb, value: "22113")))
        XCTAssertTrue(
            ids.contains(SableLibrarySourceID(provider: .ranobedb, value: "22114")) ||
            ids.contains(SableLibrarySourceID(provider: .ranobedb, value: "22115"))
        )
    }

    func testLocalLearningRecordsRawReadingLaneSignals() {
        var memory = SableLibraryLearningMemory()

        memory.recordRawReadingLane(
            path: "Solo Leveling Webtoon Vol 01.epub",
            proposedPath: "Manhwa/Solo Leveling Webtoon/Solo Leveling Webtoon - Vol 01.epub",
            readingType: .manhwa
        )
        memory.recordRawReadingLane(
            path: "Solo Leveling Webtoon Vol 02.epub",
            proposedPath: "Manhwa/Solo Leveling Webtoon/Solo Leveling Webtoon - Vol 02.epub",
            readingType: .manhwa
        )

        let signals = memory.rawReadingLaneSignals(
            path: "Solo Leveling Webtoon Vol 03.epub",
            proposedPath: nil
        )

        XCTAssertTrue(signals.contains { signal in
            signal.token == "webtoon" && signal.readingType == .manhwa
        })
        XCTAssertEqual(memory.learnedDecisionCount, 2 * memory.rawReadingLaneTokens(path: "Solo Leveling Webtoon Vol 01.epub", proposedPath: "Manhwa/Solo Leveling Webtoon/Solo Leveling Webtoon - Vol 01.epub").count)
    }

    func testLocalLearningRecordsCleanupKindSignals() {
        var memory = SableLibraryLearningMemory()

        memory.recordCleanupKind(
            path: "Mood Board Asset.nikki",
            proposedPath: "Images/Mood Board Asset.nikki",
            kind: .image
        )
        memory.recordCleanupKind(
            path: "Mood Board Draft.nikki",
            proposedPath: "Images/Mood Board Draft.nikki",
            kind: .image
        )

        let signals = memory.cleanupKindSignals(
            path: "Mood Board Reference.nikki",
            proposedPath: nil
        )

        XCTAssertTrue(signals.contains { signal in
            signal.token == "mood" && signal.kind == .image
        })
        XCTAssertGreaterThan(memory.learnedDecisionCount, 0)
    }

    func testIntelligenceOptionsDecodeSavedLocalLearningChoice() throws {
        let data = Data(#"{"improveSuggestions":false,"useLocalLearning":false}"#.utf8)

        let decoded = try JSONDecoder().decode(SableLibraryIntelligenceOptions.self, from: data)

        XCTAssertFalse(decoded.improveSuggestions)
        XCTAssertFalse(decoded.useLocalLearning)
    }

    func testIntelligenceOptionsDefaultLocalLearningOff() throws {
        XCTAssertFalse(SableLibraryIntelligenceOptions().useLocalLearning)

        let data = Data(#"{"improveSuggestions":true}"#.utf8)
        let decoded = try JSONDecoder().decode(SableLibraryIntelligenceOptions.self, from: data)

        XCTAssertFalse(decoded.useLocalLearning)
    }

    func testLearningMemoryPrunesToLightweightCap() {
        var memory = SableLibraryLearningMemory()
        for index in 0..<12 {
            memory.recordPDFTriage(
                path: "Receipts/Rareterm\(index).pdf",
                proposedPath: "Documents/Receipts/Rareterm\(index).pdf",
                choice: .document,
                date: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }

        memory.pruneForLightweightStorage(maxEntriesPerCategory: 5)

        XCTAssertLessThanOrEqual(memory.pdfTriageTerms.count, 5)
        XCTAssertNotNil(memory.pdfTriageTerms["rareterm11"])
    }

    func testMLTrainingEventUsesStablePrivacyPreservingPathHash() {
        let event = SableLibraryMLTrainingEvent.make(
            kind: .finalSuccessfulPlanRow,
            domain: .reading,
            localPath: "Sample Library/A Livid Lady.epub",
            provider: .local,
            confidenceScore: 0.95,
            now: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(event.localPathHash, "e0b1237ed35e67279143a0094cf4fea2c393404a45b10aac9cbcd2c8647824ae")
        XCTAssertFalse(event.localPathHash.contains("Livid"))
        XCTAssertFalse(event.localPathHash.contains("/"))
    }

    func testProviderPlannerUsesNoKeyReadingProvidersByDefault() throws {
        let planner = SableLibraryProviderGraphPlanner()
        let providers = planner.readingProviders(config: .fallback)

        XCTAssertTrue(providers.contains(.mangabaka))
        XCTAssertTrue(providers.contains(.ranobedb))
        XCTAssertTrue(providers.contains(.openLibrary))
        XCTAssertTrue(providers.contains(.wikidata))
        XCTAssertTrue(providers.contains(.anilist))
        XCTAssertFalse(providers.contains(.myAnimeList))
        XCTAssertNil(planner.searchRequest(provider: .myAnimeList, query: "Frieren", config: .fallback))
        XCTAssertNotNil(planner.searchRequest(provider: .wikidata, query: "The Duke and I", config: .fallback))

        let request = try XCTUnwrap(planner.searchRequest(provider: .ranobedb, query: "Spice and Wolf", config: .fallback))
        XCTAssertFalse(request.requiresAPIKey)
        XCTAssertTrue(request.url.absoluteString.contains("releases"))

        let openLibraryRequest = try XCTUnwrap(planner.searchRequest(provider: .openLibrary, query: "Heated Rivalry Rachel Reid", config: .fallback))
        let openLibraryItems = URLComponents(url: openLibraryRequest.url, resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(openLibraryItems?.first(where: { $0.name == "lang" })?.value, "en")

        let watchingProviders = planner.watchingProviders(config: .fallback)
        XCTAssertTrue(watchingProviders.contains(.tvmaze))
        XCTAssertTrue(watchingProviders.contains(.wikidata))
        XCTAssertFalse(watchingProviders.contains(.myAnimeList))
    }

    func testManualProviderIDParserReadsReadingAndWatchingIDs() throws {
        XCTAssertEqual(
            SableLibraryManualProviderIDParser.sourceID(provider: .openLibrary, from: "https://openlibrary.org/works/OL123W"),
            SableLibrarySourceID(provider: .openLibrary, value: "/works/OL123W")
        )
        XCTAssertEqual(
            SableLibraryManualProviderIDParser.sourceID(provider: .openLibrary, from: "OL987M"),
            SableLibrarySourceID(provider: .openLibrary, value: "/books/OL987M")
        )
        XCTAssertEqual(
            SableLibraryManualProviderIDParser.sourceID(provider: .tmdb, from: "https://www.themoviedb.org/movie/53737-screen"),
            SableLibrarySourceID(provider: .tmdb, value: "53737")
        )
        XCTAssertEqual(
            SableLibraryManualProviderIDParser.sourceID(provider: .imdb, from: "https://www.imdb.com/title/tt1234567/"),
            SableLibrarySourceID(provider: .imdb, value: "tt1234567")
        )
        XCTAssertEqual(
            SableLibraryManualProviderIDParser.sourceID(provider: .wikidata, from: "https://www.wikidata.org/wiki/Q42"),
            SableLibrarySourceID(provider: .wikidata, value: "Q42")
        )
    }

    func testProviderPlannerCleansFreeTextSearchQueries() throws {
        let planner = SableLibraryProviderGraphPlanner()
        let request = try XCTUnwrap(planner.searchRequest(
            provider: .ranobedb,
            query: "Quiet Hero (2018) {mal-1234} - TV",
            config: .fallback
        ))
        let queryItems = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems

        XCTAssertEqual(queryItems?.first(where: { $0.name == "q" })?.value, "Quiet Hero")
    }

    func testProviderCredentialsExposeOnlyKeyedProviders() {
        let credentials = SableLibraryProviderCredentials(
            tmdbAccessToken: "tmdb-token",
            tvdbAccessToken: "tvdb-token"
        )

        XCTAssertNil(credentials.credential(for: .myAnimeList))
        XCTAssertEqual(credentials.credential(for: .tmdb), "tmdb-token")
        XCTAssertEqual(credentials.credential(for: .tvdb), "tvdb-token")
        XCTAssertNil(credentials.credential(for: .ranobedb))
        XCTAssertNil(credentials.credential(for: .openLibrary))
        XCTAssertNil(credentials.credential(for: .anilist))
        XCTAssertNil(credentials.credential(for: .tvmaze))
        XCTAssertNil(credentials.credential(for: .wikidata))
    }

    func testPlexStyleReadingNamesUseYearAndMangaBakaID() {
        let policy = SableLibraryNamingPolicy()
        let sourceID = SableLibrarySourceID(provider: .mangabaka, value: "1238")

        XCTAssertEqual(
            policy.canonicalReadingFolderName(
                preferredTitle: "The Beginning After the End",
                year: 2018,
                sourceID: sourceID,
                mediaType: "oel"
            ),
            "The Beginning After the End (2018) {mb-1238}"
        )
        XCTAssertEqual(
            policy.canonicalReadingSeriesPath(
                preferredTitle: "The Beginning After the End",
                year: 2018,
                sourceID: sourceID,
                mediaType: "oel"
            ),
            "OEL/The Beginning After the End (2018) {mb-1238}"
        )
        XCTAssertEqual(
            policy.canonicalReadingFileName(
                preferredTitle: "The Beginning After the End",
                year: 2018,
                suffix: "Vol 01",
                fileExtension: "epub"
            ),
            "The Beginning After the End (2018) - Vol 01.epub"
        )
        XCTAssertEqual(
            policy.canonicalReadingFileName(
                preferredTitle: "The Saga of Tanya the Evil",
                year: 2017,
                suffix: "Vol 01 - Deus lo Vult",
                fileExtension: "epub"
            ),
            "The Saga of Tanya the Evil (2017) - Vol 01 - Deus lo Vult.epub"
        )
        XCTAssertEqual(
            policy.canonicalReadingFileName(
                preferredTitle: "Quiet Hero",
                year: 2018,
                suffix: "Ch 0001-0005",
                fileExtension: "cbz"
            ),
            "Quiet Hero (2018) - Ch 0001-0005.cbz"
        )
    }

    func testPlexStyleReadingNamesHideOpenLibraryID() {
        let policy = SableLibraryNamingPolicy()
        let sourceID = SableLibrarySourceID(provider: .openLibrary, value: "/works/OL27448W")

        XCTAssertEqual(policy.normalizedMediaType("book"), "Book")
        XCTAssertEqual(
            policy.canonicalReadingFolderName(
                preferredTitle: "The Count of Monte Cristo",
                year: 1844,
                sourceID: sourceID,
                mediaType: "book"
            ),
            "The Count of Monte Cristo (1844)"
        )
        XCTAssertEqual(
            policy.canonicalReadingSeriesPath(
                preferredTitle: "The Count of Monte Cristo",
                year: 1844,
                sourceID: sourceID,
                mediaType: "book"
            ),
            "Books/The Count of Monte Cristo (1844)"
        )
    }

    func testReadingNamesKeepReadingSideAnimeAndNovelIDsWhenSupplied() {
        let policy = SableLibraryNamingPolicy()

        XCTAssertEqual(
            policy.canonicalReadingFolderName(
                preferredTitle: "Ai no Kusabi",
                year: 1990,
                sourceIDs: [
                    SableLibrarySourceID(provider: .ranobedb, value: "1234"),
                    SableLibrarySourceID(provider: .myAnimeList, value: "456"),
                    SableLibrarySourceID(provider: .anilist, value: "789"),
                    SableLibrarySourceID(provider: .openLibrary, value: "/works/OL1W")
                ],
                mediaType: "lightNovel"
            ),
            "Ai no Kusabi (1990) {rdb-1234} {mal-456} {al-789}"
        )
    }

    func testPlexStyleWatchingNamesUseSourceIDAndTypeFolder() {
        let policy = SableLibraryNamingPolicy()
        let sourceID = SableLibrarySourceID(provider: .tmdb, value: "209867")

        XCTAssertEqual(
            policy.canonicalWatchingSeriesPath(
                preferredTitle: "Frieren: Beyond Journey's End",
                year: 2023,
                sourceID: sourceID,
                mediaType: "animeTV"
            ),
            "TV/Frieren Beyond Journey's End (2023) {tmdb-209867}"
        )
        XCTAssertEqual(
            policy.canonicalWatchingSeriesPath(
                preferredTitle: "Frieren: Beyond Journey's End",
                year: 2023,
                sourceID: SableLibrarySourceID(provider: .imdb, value: "tt22248376"),
                mediaType: "animeTV"
            ),
            "TV/Frieren Beyond Journey's End (2023) {imdb-tt22248376}"
        )
        XCTAssertEqual(
            policy.canonicalWatchingSeriesPath(
                preferredTitle: "Frieren: Beyond Journey's End",
                year: 2023,
                sourceID: SableLibrarySourceID(provider: .myAnimeList, value: "52991"),
                mediaType: "animeTV"
            ),
            "TV/Frieren Beyond Journey's End (2023)"
        )
        XCTAssertEqual(
            policy.canonicalWatchingSeriesPath(
                preferredTitle: "Frieren OVA",
                year: 2023,
                sourceID: SableLibrarySourceID(provider: .myAnimeList, value: "52991"),
                mediaType: "ova"
            ),
            "TV/Frieren OVA (2023)"
        )
        XCTAssertEqual(
            policy.canonicalWatchingMovieFileName(
                preferredTitle: "Ghost in the Shell",
                year: 1995,
                sourceID: SableLibrarySourceID(provider: .imdb, value: "tt0113568"),
                fileExtension: "mkv"
            ),
            "Ghost in the Shell (1995) {imdb-tt0113568}.mkv"
        )
        XCTAssertEqual(
            policy.canonicalWatchingMovieFileName(
                preferredTitle: "Ghost in the Shell",
                year: 1995,
                sourceID: SableLibrarySourceID(provider: .myAnimeList, value: "43"),
                fileExtension: "mkv"
            ),
            "Ghost in the Shell (1995).mkv"
        )
        XCTAssertEqual(
            policy.canonicalWatchingMovieFileName(
                preferredTitle: "Ghost in the Shell",
                year: 1995,
                fileExtension: "mkv"
            ),
            "Ghost in the Shell (1995).mkv"
        )
        XCTAssertEqual(
            policy.canonicalWatchingEpisodeFileName(
                preferredTitle: "Frieren: Beyond Journey's End",
                year: 2023,
                season: 1,
                episode: 1,
                episodeTitle: "The Journey's End",
                fileExtension: ".mkv"
            ),
            "Frieren Beyond Journey's End (2023) - S01E01 - The Journey's End.mkv"
        )
        XCTAssertEqual(
            policy.canonicalWatchingEpisodeFileName(
                preferredTitle: "Frieren: Beyond Journey's End",
                year: 2023,
                season: 1,
                episode: 1,
                endSeason: nil,
                endEpisode: 2,
                episodeTitle: "A Long Road",
                fileExtension: ".mkv"
            ),
            "Frieren Beyond Journey's End (2023) - S01E01-E02 - A Long Road.mkv"
        )
    }

    func testProviderParsersNormalizeMangaBakaAndRanobeDBPayloads() throws {
        let mangaBaka = [
            "data": [
                [
                    "id": 1238,
                    "title": "The Beginning After the End",
                    "type": "oel",
                    "year": 2018,
                    "genres": ["legacy fantasy"],
                    "tags": ["legacy adventure"],
                    "tags_v2": [
                        [
                            "id": 1,
                            "name": "Fantasy",
                            "name_path": "Themes > Fantasy",
                            "is_genre": true,
                            "content_rating": "safe"
                        ],
                        [
                            "id": 2,
                            "name": "Magic",
                            "name_path": "Powers > Magic",
                            "is_genre": false,
                            "content_rating": "safe"
                        ],
                        [
                            "id": 3,
                            "name": "Rape",
                            "name_path": "Sexual Content > Sexual Acts > Rape",
                            "is_genre": false,
                            "content_rating": "pornographic"
                        ]
                    ]
                ]
            ]
        ] as [String: Any]
        let ranobeDB = [
            "releases": [
                [
                    "id": 5454,
                    "title": "Spice and Wolf, Vol. 1",
                    "format": "digital",
                    "release_date": 20161213,
                    "isbn13": "9780316318266",
                    "image": [
                        "filename": "spice-cover.jpg"
                    ]
                ]
            ]
        ] as [String: Any]
        let ranobeDBSeriesSearch = [
            "series": [
                [
                    "id": 7222,
                    "title": "By the Grace of the Gods",
                    "c_start_date": 20170922,
                    "book": [
                        "image": [
                            "filename": "lsmfIwUrg2JuQMEq.jpg"
                        ]
                    ]
                ]
            ]
        ] as [String: Any]

        let mangaBakaCandidate = try XCTUnwrap(SableLibraryProviderCandidateParser.mangaBakaCandidates(from: mangaBaka).first)
        let ranobeCandidate = try XCTUnwrap(SableLibraryProviderCandidateParser.ranobeDBCandidates(from: ranobeDB).first)
        let ranobeSeriesCandidate = try XCTUnwrap(SableLibraryProviderCandidateParser.ranobeDBSeriesCandidates(from: ranobeDBSeriesSearch).first)

        XCTAssertEqual(mangaBakaCandidate.sourceIDs.first, SableLibrarySourceID(provider: .mangabaka, value: "1238"))
        XCTAssertEqual(mangaBakaCandidate.mediaType, "oel")
        XCTAssertEqual(mangaBakaCandidate.genres, ["Fantasy", "legacy fantasy"])
        XCTAssertEqual(mangaBakaCandidate.tags, ["Magic", "Rape", "legacy adventure"])
        XCTAssertEqual(mangaBakaCandidate.contentWarnings, ["Rape"])
        XCTAssertEqual(ranobeCandidate.isbn13, ["9780316318266"])
        XCTAssertEqual(ranobeCandidate.year, 2016)
        XCTAssertEqual(ranobeCandidate.coverURL, "https://images.ranobedb.org/spice-cover.jpg")
        XCTAssertEqual(ranobeSeriesCandidate.sourceIDs.first, SableLibrarySourceID(provider: .ranobedb, value: "7222"))
        XCTAssertEqual(ranobeSeriesCandidate.coverURL, "https://images.ranobedb.org/lsmfIwUrg2JuQMEq.jpg")
    }

    func testRanobeDBCandidatesReadSeriesIDAliases() throws {
        let ranobeDBSeriesSearch = [
            "series": [
                [
                    "seriesId": "9001",
                    "title": "The Quintessential Quintuplets",
                    "book": [
                        "image": [
                            "filename": "qeq.jpg"
                        ]
                    ]
                ]
            ]
        ] as [String: Any]

        let candidates = SableLibraryProviderCandidateParser.ranobeDBSeriesCandidates(from: ranobeDBSeriesSearch)
        let candidate = try XCTUnwrap(candidates.first)

        XCTAssertTrue(candidate.sourceIDs.contains(SableLibrarySourceID(provider: .ranobedb, value: "9001")))
    }

    func testRanobeDBSeriesDetailCandidateReadsNestedIDBridges() throws {
        let seriesDetail = [
            "series": [
                "seriesId": 4444,
                "ids": [
                    "al": 12345,
                    "myanimelist": 67890
                ],
                "title": "Spice and Wolf",
                "c_start_date": 20080101,
                "tags": [
                    ["name": "fantasy", "ttype": "genre"]
                ],
                "books": []
            ]
        ] as [String: Any]

        let candidate = try XCTUnwrap(SableLibraryProviderCandidateParser.ranobeDBSeriesDetailCandidate(from: seriesDetail))

        XCTAssertTrue(candidate.sourceIDs.contains(SableLibrarySourceID(provider: .ranobedb, value: "4444")))
        XCTAssertTrue(candidate.sourceIDs.contains(SableLibrarySourceID(provider: .anilist, value: "12345")))
        XCTAssertTrue(candidate.sourceIDs.contains(SableLibrarySourceID(provider: .myAnimeList, value: "67890")))
    }

    func testRanobeDBSeriesDetailMapsVolumeSubtitlesAndBridgeIDs() throws {
        let seriesDetail = [
            "series": [
                "id": 3148,
                "title": "The Saga of Tanya the Evil",
                "title_orig": "Youjo Senki",
                "romaji_orig": "Youjo Senki",
                "anilist_id": 94846,
                "mal_id": 88930,
                "publication_status": "ongoing",
                "lang": "en",
                "olang": "ja",
                "c_start_date": 20131099,
                "book_description": [
                    "description": "A soldier wakes up in another world."
                ],
                "tags": [
                    ["name": "fantasy", "ttype": "genre"],
                    ["name": "military", "ttype": "tag"]
                ],
                "staff": [
                    ["role_type": "author", "name": "カルロ・ゼン", "romaji": "Carlo Zen"],
                    ["role_type": "artist", "name": "篠月しのぶ", "romaji": "Shinobu Shinotsuki"]
                ],
                "publishers": [
                    ["name": "Yen Press"],
                    ["name": "Enterbrain"]
                ],
                "books": [
                    [
                        "id": 11515,
                        "title": "The Saga of Tanya the Evil, Vol. 1: Deus lo Vult",
                        "title_orig": "Youjo Senki 1 Deus lo vult",
                        "sort_order": 1,
                        "c_release_date": 20131099,
                        "book_description": [
                            "description": "A salaryman becomes a young soldier in an alternate war."
                        ],
                        "book_type": "main",
                        "image": [
                            "filename": "tanya-cover.jpg"
                        ]
                    ],
                    [
                        "id": 12701,
                        "title": "The Saga of Tanya the Evil, Vol. 2: Plus Ultra",
                        "sort_order": 2,
                        "c_release_date": 20140599,
                        "book_type": "main"
                    ]
                ]
            ]
        ] as [String: Any]
        let bookDetail = [
            "book": [
                "id": 11515,
                "title": "The Saga of Tanya the Evil, Vol. 1: Deus lo Vult",
                "sort_order": 1,
                "c_release_date": 20131099,
                "description": "Tanya fights through a military campaign after reincarnation.",
                "releases": [
                    [
                        "id": 22676,
                        "lang": "en",
                        "format": "digital",
                        "release_date": 20171219,
                        "isbn13": "9780316512459"
                    ],
                    [
                        "id": 22677,
                        "lang": "en",
                        "format": "print",
                        "release_date": 20171219,
                        "isbn13": "9780316512442",
                        "pages": 344
                    ]
                ]
            ]
        ] as [String: Any]

        let candidate = try XCTUnwrap(SableLibraryProviderCandidateParser.ranobeDBSeriesDetailCandidate(from: seriesDetail))
        let parts = SableLibraryProviderCandidateParser.ranobeDBReadingParts(from: seriesDetail, preferredTitle: candidate.title)
        let detailedPart = try XCTUnwrap(SableLibraryProviderCandidateParser.ranobeDBReadingPartDetail(from: bookDetail, preferredTitle: candidate.title))

        XCTAssertEqual(candidate.sourceIDs, [
            SableLibrarySourceID(provider: .ranobedb, value: "3148"),
            SableLibrarySourceID(provider: .anilist, value: "94846"),
            SableLibrarySourceID(provider: .myAnimeList, value: "88930")
        ])
        XCTAssertEqual(candidate.year, 2013)
        XCTAssertEqual(candidate.description, "A soldier wakes up in another world.")
        XCTAssertEqual(candidate.genres, ["fantasy"])
        XCTAssertEqual(candidate.tags, ["military"])
        XCTAssertEqual(candidate.authors, ["Carlo Zen"])
        XCTAssertEqual(candidate.artists, ["Shinobu Shinotsuki"])
        XCTAssertEqual(candidate.publishers, ["Yen Press", "Enterbrain"])
        XCTAssertEqual(candidate.languages, ["en", "ja"])
        XCTAssertEqual(candidate.status, "ongoing")
        XCTAssertEqual(candidate.coverURL, "https://images.ranobedb.org/tanya-cover.jpg")
        XCTAssertEqual(parts.first?.fileSuffix, "Vol 01 - Deus lo Vult")
        XCTAssertEqual(parts.first?.description, "A salaryman becomes a young soldier in an alternate war.")
        XCTAssertEqual(parts.last?.fileSuffix, "Vol 02 - Plus Ultra")
        XCTAssertEqual(detailedPart.description, "Tanya fights through a military campaign after reincarnation.")
        XCTAssertEqual(detailedPart.isbn13, ["9780316512459", "9780316512442"])
        XCTAssertEqual(detailedPart.releaseIDs, ["22676", "22677"])
        XCTAssertEqual(detailedPart.releaseYear, 2017)
    }

    func testRanobeDBReadingPartsKeepBookSubtitleWhenSeriesTitleLooksLikeFirstBook() throws {
        let seriesDetail = [
            "series": [
                "id": 1523,
                "title": "Sugar Apple Fairy Tale: The Silver Sugar Master and the Obsidian Fairy",
                "books": [
                    [
                        "id": 6211,
                        "title": "Sugar Apple Fairy Tale, Vol. 1: The Silver Sugar Master and the Obsidian Fairy",
                        "sort_order": 1,
                        "book_type": "main"
                    ]
                ]
            ]
        ] as [String: Any]

        let parts = SableLibraryProviderCandidateParser.ranobeDBReadingParts(
            from: seriesDetail,
            preferredTitle: "Sugar Apple Fairy Tale: The Silver Sugar Master and the Obsidian Fairy"
        )
        let part = try XCTUnwrap(parts.first)

        XCTAssertEqual(part.sourceID, SableLibrarySourceID(provider: .ranobedb, value: "6211"))
        XCTAssertEqual(part.subtitle, "The Silver Sugar Master and the Obsidian Fairy")
        XCTAssertEqual(part.fileSuffix, "Vol 01 - The Silver Sugar Master and the Obsidian Fairy")
    }

    func testRanobeDBReadingPartsIgnoreSubBooksWithoutShiftingMainVolumes() {
        let seriesDetail = [
            "series": [
                "books": [
                    [
                        "id": 1,
                        "title": "Example Series, Vol. 1: First",
                        "sort_order": 1,
                        "book_type": "main"
                    ],
                    [
                        "id": 2,
                        "title": "Example Series: Short Story Collection",
                        "sort_order": 2,
                        "book_type": "sub"
                    ],
                    [
                        "id": 3,
                        "title": "Example Series, Vol. 2: Second",
                        "sort_order": 3,
                        "book_type": "main"
                    ]
                ]
            ]
        ] as [String: Any]

        let parts = SableLibraryProviderCandidateParser.ranobeDBReadingParts(
            from: seriesDetail,
            preferredTitle: "Example Series"
        )

        XCTAssertEqual(parts.map(\.number), [1, 2])
        XCTAssertEqual(parts.compactMap { $0.sourceID?.value }, ["1", "3"])
    }

    func testRanobeDBReadingPartsRespectLocalPartScope() {
        let seriesDetail = [
            "series": [
                "books": [
                    [
                        "id": 1,
                        "title": "Example Series Part 1: Volume 1",
                        "sort_order": 1,
                        "book_type": "main"
                    ],
                    [
                        "id": 2,
                        "title": "Example Series Part 5: Volume 1",
                        "sort_order": 22,
                        "book_type": "main"
                    ],
                    [
                        "id": 3,
                        "title": "Example Series Part 5: Volume 2",
                        "sort_order": 23,
                        "book_type": "main"
                    ]
                ]
            ]
        ] as [String: Any]

        let parts = SableLibraryProviderCandidateParser.ranobeDBReadingParts(
            from: seriesDetail,
            preferredTitle: "Example Series Part 5"
        )

        XCTAssertEqual(parts.map(\.number), [1, 2])
        XCTAssertEqual(parts.compactMap { $0.sourceID?.value }, ["2", "3"])
    }

    func testRanobeDBBookDetailTargetsOnlyIncludeRecordsWithoutSavedDetails() {
        let parts = [
            SableLibraryReadingPartMetadata(
                number: 1,
                sourceID: SableLibrarySourceID(provider: .ranobedb, value: "book-1"),
                title: "Example, Vol. 1",
                fileSuffix: "Vol 01"
            ),
            SableLibraryReadingPartMetadata(
                number: 2,
                sourceID: SableLibrarySourceID(provider: .ranobedb, value: "book-2"),
                title: "Example, Vol. 2",
                fileSuffix: "Vol 02"
            ),
            SableLibraryReadingPartMetadata(
                number: 3,
                sourceID: SableLibrarySourceID(provider: .ranobedb, value: "book-3"),
                title: "Example, Vol. 3",
                fileSuffix: "Vol 03"
            )
        ]

        let targets = SableLibraryMetadataLookupService.ranobeDBBookDetailTargets(
            parts: parts,
            detailedBookIDs: ["book-1", "book-2"]
        )

        XCTAssertEqual(targets.map(\.number), [3])
        XCTAssertEqual(targets.compactMap(\.sourceID?.value), ["book-3"])
    }

    func testMangaBakaCoverCandidatesClassifyRegularAndSpecialCovers() throws {
        let payload = [
            "status": 200,
            "data": [
                [
                    "id": 83803,
                    "series_id": 54536,
                    "index": "1",
                    "index_numeric": 1,
                    "type": "volume",
                    "language": "en",
                    "image": [
                        "raw": [
                            "url": "https://images.mangabaka.dev/en-cover",
                            "width": 1591,
                            "height": 2475,
                            "size": 1_314_381
                        ]
                    ]
                ],
                [
                    "id": 83804,
                    "series_id": 54536,
                    "index": "1",
                    "index_numeric": 1,
                    "type": "volume",
                    "language": "ja",
                    "note": "Regular",
                    "image": [
                        "raw": [
                            "url": "https://images.mangabaka.dev/jp-regular",
                            "width": 3023,
                            "height": 4299,
                            "size": 10_007_655
                        ]
                    ]
                ],
                [
                    "id": 83805,
                    "series_id": 54536,
                    "index": "1",
                    "index_numeric": 1,
                    "type": "volume",
                    "language": "ja",
                    "note": "Special",
                    "image": [
                        "raw": [
                            "url": "https://images.mangabaka.dev/jp-special",
                            "width": 3023,
                            "height": 4299,
                            "size": 10_104_702
                        ]
                    ]
                ]
            ]
        ] as [String: Any]

        let candidates = SableLibraryProviderCandidateParser.mangaBakaCoverCandidates(from: payload)
        let english = try XCTUnwrap(candidates.first { $0.language == "en" })
        let japaneseRegular = try XCTUnwrap(candidates.first { $0.language == "ja" && $0.editionNote == "Regular" })
        let japaneseSpecial = try XCTUnwrap(candidates.first { $0.language == "ja" && $0.editionNote == "Special" })

        XCTAssertEqual(candidates.count, 3)
        XCTAssertEqual(english.role, .normal)
        XCTAssertEqual(english.quality, .highResolution)
        XCTAssertTrue(english.canReplaceNormalCover)
        XCTAssertEqual(japaneseRegular.providerSeriesID, "54536")
        XCTAssertEqual(japaneseRegular.providerItemID, "83804")
        XCTAssertEqual(japaneseRegular.volumeNumber, 1)
        XCTAssertEqual(japaneseRegular.role, .normal)
        XCTAssertEqual(japaneseRegular.quality, .highResolution)
        XCTAssertTrue(japaneseRegular.canReplaceNormalCover)
        XCTAssertEqual(japaneseSpecial.role, .specialEdition)
        XCTAssertTrue(japaneseSpecial.shouldSaveAsExtraCover)
        XCTAssertFalse(japaneseSpecial.canReplaceNormalCover)
    }

    func testMangaBakaCoverCandidatesSeparateAlternativeBackAndBonusRows() throws {
        let payload = [
            "status": 200,
            "data": [
                [
                    "id": 1,
                    "index": "1",
                    "index_numeric": 1,
                    "type": "volume",
                    "language": "ja",
                    "note": "1st edition, 2017, tankobon",
                    "image": [
                        "raw": [
                            "url": "https://images.mangabaka.dev/first",
                            "width": 740,
                            "height": 1064,
                            "size": 201_817
                        ]
                    ]
                ],
                [
                    "id": 2,
                    "index": "1.1",
                    "index_numeric": 1.1,
                    "type": "volume",
                    "language": "ja",
                    "note": "2nd edition, 2019 bunkoban",
                    "image": [
                        "raw": [
                            "url": "https://images.mangabaka.dev/second",
                            "width": 1392,
                            "height": 2055,
                            "size": 278_278
                        ]
                    ]
                ],
                [
                    "id": 3,
                    "index": "1.1",
                    "index_numeric": 1.1,
                    "type": "volume_back",
                    "language": "ja",
                    "note": "2nd edition, 2019 bunkoban",
                    "image": [
                        "raw": [
                            "url": "https://images.mangabaka.dev/back",
                            "width": 1018,
                            "height": 1500,
                            "size": 83_613
                        ]
                    ]
                ],
                [
                    "id": 4,
                    "index": "1.1",
                    "index_numeric": 1.1,
                    "type": "other",
                    "language": "ja",
                    "note": "With Obi",
                    "image": [
                        "raw": [
                            "url": "https://images.mangabaka.dev/obi",
                            "width": 740,
                            "height": 1064,
                            "size": 215_959
                        ]
                    ]
                ]
            ]
        ] as [String: Any]

        let candidates = SableLibraryProviderCandidateParser.mangaBakaCoverCandidates(from: payload, seriesID: "83998")
        let firstEdition = try XCTUnwrap(candidates.first { $0.providerItemID == "1" })
        let secondEdition = try XCTUnwrap(candidates.first { $0.providerItemID == "2" })
        let backCover = try XCTUnwrap(candidates.first { $0.providerItemID == "3" })
        let withObi = try XCTUnwrap(candidates.first { $0.providerItemID == "4" })

        XCTAssertEqual(firstEdition.providerSeriesID, "83998")
        XCTAssertEqual(firstEdition.role, .normal)
        XCTAssertEqual(firstEdition.quality, .usable)
        XCTAssertTrue(firstEdition.canReplaceNormalCover)
        XCTAssertEqual(secondEdition.role, .alternativeEdition)
        XCTAssertTrue(secondEdition.shouldSaveAsExtraCover)
        XCTAssertEqual(backCover.role, .backCover)
        XCTAssertFalse(backCover.shouldSaveAsExtraCover)
        XCTAssertEqual(withObi.role, .bonus)
        XCTAssertTrue(withObi.shouldSaveAsExtraCover)
    }

    func testMangaBakaAudiobookCoverIsNotSavedAsAnExtra() throws {
        let payload = [
            "data": [
                [
                    "id": 27737,
                    "index": "1",
                    "index_numeric": 1,
                    "type": "audiobook",
                    "language": "en",
                    "image": [
                        "raw": [
                            "url": "https://images.mangabaka.dev/audiobook",
                            "width": 3_000,
                            "height": 3_000,
                            "size": 1_676_056
                        ]
                    ]
                ]
            ]
        ] as [String: Any]

        let audiobook = try XCTUnwrap(
            SableLibraryProviderCandidateParser
                .mangaBakaCoverCandidates(from: payload)
                .first
        )

        XCTAssertEqual(audiobook.providerType, "audiobook")
        XCTAssertEqual(audiobook.role, .audiobook)
        XCTAssertTrue(audiobook.isAudiobookCover)
        XCTAssertEqual(audiobook.mediaTypeForSeriesIdentity("novel"), "audiobook")
        XCTAssertFalse(audiobook.shouldSaveAsExtraCover)
    }

    func testMangaBakaCoverCandidatesCanReadEmbeddedCoverPagePayload() throws {
        let payload = [
            "status": 200,
            "data": [
                [
                    "id": 83805,
                    "index": "1",
                    "index_numeric": 1,
                    "type": "volume",
                    "language": "ja",
                    "note": "Special",
                    "image": [
                        "raw": [
                            "url": "https://images.mangabaka.dev/jp-special",
                            "width": 3023,
                            "height": 4299,
                            "size": 10_104_702
                        ]
                    ]
                ]
            ]
        ] as [String: Any]
        let payloadData = try JSONSerialization.data(withJSONObject: payload)
        let payloadText = try XCTUnwrap(String(data: payloadData, encoding: .utf8))
        let encodedBodyData = try JSONEncoder().encode(payloadText)
        let encodedBody = try XCTUnwrap(String(data: encodedBodyData, encoding: .utf8))
        let html = #"<script data-sveltekit-fetched>{"body":\#(encodedBody)}</script>"#

        let candidates = SableLibraryProviderCandidateParser.mangaBakaCoverCandidates(fromCoversPageHTML: html, seriesID: "54536")
        let candidate = try XCTUnwrap(candidates.first)

        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidate.providerSeriesID, "54536")
        XCTAssertEqual(candidate.role, .specialEdition)
        XCTAssertEqual(candidate.imageURL, "https://images.mangabaka.dev/jp-special")
    }

    func testMangaBakaCoverPageCarriesTheNextPageURL() throws {
        let data = Data("""
        {
          "status": 200,
          "data": [
            {
              "id": 46537,
              "series_id": 881,
              "index": "1",
              "index_numeric": 1,
              "type": "volume",
              "language": "en",
              "image": {
                "raw": {
                  "url": "https://images.mangabaka.dev/volume-1",
                  "width": 2146,
                  "height": 3056,
                  "size": 1779779
                }
              }
            }
          ],
          "pagination": {
            "next": "https://api.mangabaka.org/v1/series/881/images?page=2"
          }
        }
        """.utf8)

        let page = try SableLibraryProviderCandidateParser.mangaBakaCoverPage(
            from: data,
            seriesID: "881"
        )

        XCTAssertEqual(page.candidates.map(\.providerItemID), ["46537"])
        XCTAssertEqual(
            page.nextPageURL?.absoluteString,
            "https://api.mangabaka.org/v1/series/881/images?page=2"
        )
    }

    func testRanobeDBCoverCandidatesExposeLowResolutionVolumeAndStoreLinks() throws {
        let bookDetail = [
            "book": [
                "id": 32028,
                "title": "Agents of the Four Seasons, Vol. 1: Dance of Spring, Part I",
                "title_orig": "春夏秋冬代行者 春の舞 上",
                "sort_order": 1,
                "lang": "en",
                "image": [
                    "filename": "7aN1QwY1OUisQOKX.jpg",
                    "width": 240,
                    "height": 340
                ],
                "releases": [
                    [
                        "lang": "ja",
                        "format": "digital",
                        "bookwalker": "https://bookwalker.jp/de097ed918-0e96-400d-97b4-19971e9e3f70/"
                    ],
                    [
                        "lang": "ja",
                        "format": "print",
                        "amazon": "https://www.amazon.co.jp/dp/4049135841"
                    ]
                ]
            ]
        ] as [String: Any]

        let candidates = SableLibraryProviderCandidateParser.ranobeDBCoverCandidates(from: bookDetail)
        let candidate = try XCTUnwrap(candidates.first)

        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidate.provider, .ranobedb)
        XCTAssertEqual(candidate.providerItemID, "32028")
        XCTAssertEqual(candidate.volumeNumber, 1)
        XCTAssertEqual(candidate.language, "en")
        XCTAssertEqual(candidate.role, .normal)
        XCTAssertEqual(candidate.quality, .lowResolution)
        XCTAssertFalse(candidate.canReplaceNormalCover)
        XCTAssertEqual(candidate.imageURL, "https://images.ranobedb.org/7aN1QwY1OUisQOKX.jpg")
        XCTAssertEqual(candidate.storeURLs, [
            "https://bookwalker.jp/de097ed918-0e96-400d-97b4-19971e9e3f70/",
            "https://www.amazon.co.jp/dp/4049135841"
        ])
    }

    func testCoverSourcePolicyUsesMangaBakaBaselineThenStoreUpgradesForJapaneseCovers() {
        XCTAssertEqual(
            SableLibraryCoverSourcePolicy.normalCoverDownloadOrder(language: "ja"),
            [.mangaBaka, .bookLiveJP, .bookWalkerJP, .amazonJP]
        )
        XCTAssertEqual(
            SableLibraryCoverSourcePolicy.normalCoverDownloadOrder(language: "jp-JP"),
            [.mangaBaka, .bookLiveJP, .bookWalkerJP, .amazonJP]
        )
        XCTAssertTrue(SableLibraryCoverSourcePolicy.canUseAsNormalCover(.bookLiveJP))
        XCTAssertTrue(SableLibraryCoverSourcePolicy.canUseAsNormalCover(.bookWalkerJP))
        XCTAssertTrue(SableLibraryCoverSourcePolicy.canUseAsNormalCover(.mangaBaka))
        XCTAssertTrue(SableLibraryCoverSourcePolicy.canUseForSpecialOrAlternativeCover(.mangaBaka))
        XCTAssertEqual(
            SableLibraryCoverSourcePolicy.missingCoverReason(language: "ja"),
            "No trusted cover found in MangaBaka, BookLive JP, BookWalker JP, Amazon JP."
        )
    }

    func testCoverSourcePolicyUsesMangaBakaBaselineThenStoreUpgradesForEnglishCovers() {
        XCTAssertEqual(
            SableLibraryCoverSourcePolicy.normalCoverDownloadOrder(language: "en-US"),
            [.mangaBaka, .bookWalkerGlobal, .amazon]
        )
        XCTAssertTrue(SableLibraryCoverSourcePolicy.canUseAsNormalCover(.bookWalkerGlobal))
        XCTAssertTrue(SableLibraryCoverSourcePolicy.canUseAsNormalCover(.mangaBaka))
        XCTAssertFalse(SableLibraryCoverSourcePolicy.canUseAsNormalCover(.ranobeDB))
        XCTAssertFalse(SableLibraryCoverSourcePolicy.canUseForSpecialOrAlternativeCover(.ranobeDB))
        XCTAssertEqual(
            SableLibraryCoverSourcePolicy.missingCoverReason(language: "en"),
            "No trusted cover found in MangaBaka, BookWalker Global, Amazon."
        )
    }

    func testCoverDownloadPassesKeepMangaBakaAndStoreWorkSeparate() {
        let localBooks = [
            SableLibraryCoverDownloadLocalBook(
                fileName: "Series - Vol 01.epub",
                volumeNumber: 1
            )
        ]
        let baselineRequest = SableLibraryCoverDownloadRequest(
            seriesTitle: "Series",
            mediaType: "lightNovel",
            queryTitles: ["Series"],
            mangaBakaSeriesID: "1234",
            localBooks: localBooks,
            downloadPass: .mangaBakaBaseline
        )
        let upgradeRequest = SableLibraryCoverDownloadRequest(
            seriesTitle: "Series",
            mediaType: "lightNovel",
            queryTitles: ["Series"],
            mangaBakaSeriesID: "1234",
            localBooks: localBooks,
            downloadPass: .storeQualityUpgrade
        )

        XCTAssertEqual(
            SableLibraryCoverDownloadPlanner.normalCoverDownloadOrder(
                for: "jp",
                in: baselineRequest
            ),
            [.mangaBaka]
        )
        XCTAssertEqual(
            SableLibraryCoverDownloadPlanner.normalCoverDownloadOrder(
                for: "en",
                in: baselineRequest
            ),
            [.mangaBaka]
        )
        XCTAssertEqual(
            SableLibraryCoverDownloadPlanner.normalCoverDownloadOrder(
                for: "jp",
                in: upgradeRequest
            ),
            [.bookLiveJP, .bookWalkerJP, .amazonJP]
        )
        XCTAssertEqual(
            SableLibraryCoverDownloadPlanner.normalCoverDownloadOrder(
                for: "en",
                in: upgradeRequest
            ),
            [.bookWalkerGlobal, .amazon]
        )
        XCTAssertEqual(
            SableLibraryCoverSourcePolicy.missingCoverReason(
                language: "jp",
                pass: .mangaBakaBaseline
            ),
            "MangaBaka baseline (JP) found no trusted cover in MangaBaka."
        )
        XCTAssertEqual(
            SableLibraryCoverSourcePolicy.missingCoverReason(
                language: "jp",
                pass: .storeQualityUpgrade
            ),
            "Store quality upgrade (JP) found no trusted cover in BookLive JP, BookWalker JP, Amazon JP."
        )
    }

    func testCoverManifestRecordsWhichSearchPassActuallyRan() throws {
        let manifest = SableLibraryDownloadedCoverManifest(
            generatedAt: "2026-07-26T12:00:00Z",
            seriesTitle: "Series",
            mediaType: "lightNovel",
            searchAttempts: [
                SableLibraryCoverSearchAttempt(
                    language: "jp",
                    pass: .mangaBakaBaseline,
                    completedAt: "2026-07-26T11:00:00Z",
                    providers: ["MangaBaka"]
                ),
                SableLibraryCoverSearchAttempt(
                    language: "en",
                    pass: .storeQualityUpgrade,
                    completedAt: "2026-07-26T12:00:00Z",
                    providers: ["BookWalker Global", "Amazon"]
                )
            ],
            entries: [],
            skipped: []
        )

        let data = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(
            SableLibraryDownloadedCoverManifest.self,
            from: data
        )

        XCTAssertEqual(decoded.searchAttempts, manifest.searchAttempts)
    }

    func testStoreCoverMustBeStrictlyBetterThanMangaBakaBaseline() {
        XCTAssertTrue(
            SableLibraryCoverDownloadPlanner.coverDimensionsAreStrictQualityUpgrade(
                width: 800,
                height: 1_100,
                over: 607,
                baselineHeight: 861
            )
        )
        XCTAssertTrue(
            SableLibraryCoverDownloadPlanner.coverDimensionsAreStrictQualityUpgrade(
                width: 1_600,
                height: 2_400,
                over: 1_200,
                baselineHeight: 1_800
            )
        )
        XCTAssertFalse(
            SableLibraryCoverDownloadPlanner.coverDimensionsAreStrictQualityUpgrade(
                width: 1_200,
                height: 1_800,
                over: 1_200,
                baselineHeight: 1_800
            )
        )
        XCTAssertFalse(
            SableLibraryCoverDownloadPlanner.coverDimensionsAreStrictQualityUpgrade(
                width: 1_000,
                height: 1_500,
                over: 1_200,
                baselineHeight: 1_800
            )
        )
    }

    func testAmazonCoverQueriesUseSeriesTitlesBeforeLimitedISBNFallbacks() {
        let amazonQueries = SableLibraryCoverDownloadPlanner.orderedProviderQueries(
            titles: [
                "The Frontier Lord Begins with Zero Subjects",
                "Frontier Lord",
                "辺境領主",
                "An Unnecessary Fourth Alias"
            ],
            isbn13: [
                "978-1-7183-3132-7",
                "978-1-7183-3133-4",
                "978-1-7183-3134-1",
                "not-an-isbn"
            ],
            language: "en",
            provider: .amazon
        )
        let bookWalkerQueries = SableLibraryCoverDownloadPlanner.orderedProviderQueries(
            titles: ["The Frontier Lord Begins with Zero Subjects"],
            isbn13: ["978-1-7183-3132-7"],
            language: "en",
            provider: .bookWalkerGlobal
        )

        XCTAssertEqual(
            amazonQueries,
            [
                .init(value: "The Frontier Lord Begins with Zero Subjects", isExactISBN: false),
                .init(value: "Frontier Lord", isExactISBN: false),
                .init(value: "9781718331327", isExactISBN: true)
            ]
        )
        XCTAssertEqual(
            bookWalkerQueries,
            [
                .init(value: "The Frontier Lord Begins with Zero Subjects", isExactISBN: false)
            ]
        )
    }

    func testCoverRequestKeepsJapaneseAndEnglishISBNsSeparate() {
        let request = SableLibraryCoverDownloadRequest(
            seriesTitle: "Agents of the Four Seasons",
            queryTitles: ["Agents of the Four Seasons", "春夏秋冬代行者"],
            isbn13: ["9781975361792"],
            isbn13ByLanguage: [
                "ja": ["9784049135841"],
                "en": ["9781975361792"]
            ],
            localBooks: [
                .init(fileName: "Agents of the Four Seasons - Vol 01.epub", volumeNumber: 1)
            ]
        )

        XCTAssertEqual(request.isbn13(for: "jp"), ["9784049135841"])
        XCTAssertEqual(request.isbn13(for: "en-US"), ["9781975361792"])
    }

    func testLocalCoverVolumeParsingDoesNotTreatNumericSeriesTitleAsVolume() {
        XCTAssertNil(
            SableLibraryCoverDownloadPlanner.localVolumeNumber(
                fileName: "37°c (2008).epub",
                seriesTitles: ["37°C", "Thirty Seven Degrees Celsius"]
            )
        )
        XCTAssertEqual(
            SableLibraryCoverDownloadPlanner.localVolumeNumber(
                fileName: "Example Series 7.epub",
                seriesTitles: ["Example Series"]
            ),
            7
        )
        XCTAssertEqual(
            SableLibraryCoverDownloadPlanner.localVolumeNumber(
                fileName: "37°C - Vol 02.epub",
                seriesTitles: ["37°C"]
            ),
            2
        )
        XCTAssertEqual(
            SableLibraryCoverDownloadPlanner.localVolumeNumber(
                fileName: "Example Series - Vol 08.5.epub",
                seriesTitles: ["Example Series"]
            ),
            8.5
        )
    }

    func testProviderVisibleTitleVolumeCannotBeMaskedByManifestVolume() {
        XCTAssertFalse(
            SableLibraryCoverDownloadPlanner.providerBookIdentityIsCompatible(
                providerTitle: "Sword Art Online 1: Aincrad (light novel)",
                localBookTitle: "Sword Art Online (2009) - Vol 02.epub",
                localVolume: 2
            )
        )
        XCTAssertTrue(
            SableLibraryCoverDownloadPlanner.providerBookIdentityIsCompatible(
                providerTitle: "Sword Art Online 1: Aincrad (light novel)",
                localBookTitle: "Sword Art Online (2009) - Vol 01.epub",
                localVolume: 1
            )
        )
        XCTAssertNil(
            SableLibraryCoverDownloadPlanner.providerTitleVolumeNumber(
                in: "37°C",
                localBookTitle: "37°C (2008) - Vol 02.epub"
            )
        )
        XCTAssertEqual(
            SableLibraryCoverDownloadPlanner.providerTitleVolumeNumber(
                in: "37°C 2",
                localBookTitle: "37°C (2008) - Vol 02.epub"
            ),
            2
        )
    }

    func testAmazonExactISBNResultPrefersRolerSeriesOverSingleBook() {
        let book = SableLibraryBigBookCoversSeriesCandidate(
            provider: .amazon,
            id: "B0CJF9965P",
            title: "The Frontier Lord Begins with Zero Subjects: Volume 1",
            url: "https://www.amazon.com/dp/B0CJF9965P",
            type: "book",
            bookType: nil,
            thumbnailURL: nil
        )
        let series = SableLibraryBigBookCoversSeriesCandidate(
            provider: .amazon,
            id: "B0CLKWGDS4",
            title: "The Frontier Lord Begins with Zero Subjects",
            url: "https://www.amazon.com/kindle-dbs/product/B0CLKWGDS4",
            type: "series",
            bookType: nil,
            thumbnailURL: nil
        )

        XCTAssertEqual(
            SableLibraryCoverDownloadPlanner.exactIdentifierCandidates([book, series]).map(\.id),
            ["B0CLKWGDS4", "B0CJF9965P"]
        )
    }

    func testComicInfoTypeHardGatesAmazonNovelAndMangaSeries() {
        let novelBooks = [
            SableLibraryBigBookCoversBookCandidate(
                provider: .amazon,
                id: "B0CJF9965P",
                seriesID: "B0CLKWGDS4",
                title: "The Frontier Lord Begins with Zero Subjects: Volume 1",
                url: "https://www.amazon.com/dp/B0CJF9965P",
                coverURL: "https://m.media-amazon.com/images/P/B0CJF9965P.01.MAIN._SCRM_.jpg",
                coverFallbackURLs: [],
                volumeNumber: 1,
                volumeType: "volume",
                sequenceIndex: 1,
                bookType: nil
            )
        ]
        let mangaBooks = [
            SableLibraryBigBookCoversBookCandidate(
                provider: .amazon,
                id: "B0CG3ZQQPH",
                seriesID: "B0CW9R6F3F",
                title: "The Frontier Lord Begins with Zero Subjects (Manga): Volume 1",
                url: "https://www.amazon.com/dp/B0CG3ZQQPH",
                coverURL: "https://m.media-amazon.com/images/P/B0CG3ZQQPH.01.MAIN._SCRM_.jpg",
                coverFallbackURLs: [],
                volumeNumber: 1,
                volumeType: "volume",
                sequenceIndex: 1,
                bookType: nil
            )
        ]
        let service = SableLibraryCoverDownloadService()

        XCTAssertTrue(
            service.providerBooksLookCompatibleWithLocalMedia(
                novelBooks,
                seriesTitle: "The Frontier Lord Begins with Zero Subjects",
                seriesBookType: nil,
                mediaType: "lightNovel"
            )
        )
        XCTAssertTrue(
            service.providerBooksLookCompatibleWithLocalMedia(
                novelBooks,
                seriesTitle: "The Frontier Lord Begins with Zero Subjects",
                seriesBookType: nil,
                mediaType: "novel"
            )
        )
        XCTAssertFalse(
            service.providerBooksLookCompatibleWithLocalMedia(
                mangaBooks,
                seriesTitle: "The Frontier Lord Begins with Zero Subjects (Manga)",
                seriesBookType: nil,
                mediaType: "lightNovel"
            )
        )
        XCTAssertTrue(
            service.providerBooksLookCompatibleWithLocalMedia(
                mangaBooks,
                seriesTitle: "The Frontier Lord Begins with Zero Subjects (Manga)",
                seriesBookType: nil,
                mediaType: "manga"
            )
        )
        XCTAssertFalse(
            service.providerBooksLookCompatibleWithLocalMedia(
                novelBooks,
                seriesTitle: "The Frontier Lord Begins with Zero Subjects",
                seriesBookType: nil,
                mediaType: "manga"
            )
        )
    }

    func testBigBookCoversParsersReadSeriesAndBooksPayloads() throws {
        let searchJSON = Data("""
        {
          "count": 1,
          "data": {
            "bw-g": [
              {
                "id": "CNT_2VJ3FFHAJ0N0",
                "type": "series",
                "title": "Ascendance of a Bookworm",
                "url": "https://bookwalker.com/series/example",
                "bookType": "novel",
                "thumbnail": "https://img.sos-dan.net/thumb.jpg"
              }
            ]
          }
        }
        """.utf8)
        let booksJSON = Data("""
        {
          "count": 2,
          "data": {
            "bw-g": [
              {
                "id": "book-1",
                "title": "Ascendance of a Bookworm: Part 1 Volume 1",
                "url": "https://bookwalker.com/book/1",
                "cover": "https://img.sos-dan.net/original/book-1.jpg",
                "volume": { "number": 1, "seriesId": "CNT_2VJ3FFHAJ0N0" },
                "bookType": "novel"
              },
              {
                "id": "book-1-special",
                "title": "Ascendance of a Bookworm: Part 1 Volume 1 Special Edition",
                "url": "https://bookwalker.com/book/1-special",
                "cover": "https://img.sos-dan.net/original/book-1-special.jpg",
                "volume": { "number": 1, "seriesId": "CNT_2VJ3FFHAJ0N0" },
                "bookType": "novel"
              }
            ]
          }
        }
        """.utf8)

        let series = try SableLibraryBigBookCoversClient.seriesCandidates(fromSearchData: searchJSON, provider: .bookWalkerGlobal)
        let best = try XCTUnwrap(SableLibraryCoverDownloadPlanner.bestSeriesCandidate(
            for: "Ascendance of a Bookworm",
            in: series,
            mediaType: "lightNovel"
        ))
        let books = try SableLibraryBigBookCoversClient.bookCandidates(fromBooksData: booksJSON, provider: .bookWalkerGlobal)
        let covers = SableLibraryProviderCandidateParser.bigBookCoversCandidates(
            from: books,
            source: .bookWalkerGlobal,
            language: "en",
            mediaType: "lightNovel"
        )
        let matched = SableLibraryCoverDownloadPlanner.matchedProviderCovers(
            candidates: covers,
            source: .bookWalkerGlobal,
            language: "en",
            localBooks: [
                SableLibraryCoverDownloadLocalBook(fileName: "Ascendance of a Bookworm - Vol 01.epub", volumeNumber: 1)
            ],
            includeSpecials: true
        )

        XCTAssertEqual(best.id, "CNT_2VJ3FFHAJ0N0")
        XCTAssertEqual(books.count, 2)
        XCTAssertEqual(covers.map(\.role), [.normal, .specialEdition])
        XCTAssertEqual(matched[1]?.map(\.role), [.normal, .specialEdition])
    }

    func testBookLiveBookIDsRestoreMissingBBCVolumeNumbers() throws {
        let booksJSON = Data(
            """
            {
              "count": 3,
              "data": {
                "bl": [
                  {
                    "id": "833218-005",
                    "seriesId": "833218",
                    "title": "Onmyoji Volume Five",
                    "cover": "https://example.com/5.jpg",
                    "volume": { "number": null, "type": "volume" }
                  },
                  {
                    "id": "833218-001",
                    "seriesId": "833218",
                    "title": "Onmyoji Volume One",
                    "cover": "https://example.com/1.jpg",
                    "volume": { "number": null, "type": "volume" }
                  },
                  {
                    "id": "833218-003",
                    "seriesId": "833218",
                    "title": "Onmyoji Volume Three",
                    "cover": "https://example.com/3.jpg",
                    "volume": { "number": null, "type": "volume" }
                  }
                ]
              }
            }
            """.utf8
        )

        let books = try SableLibraryBigBookCoversClient.bookCandidates(
            fromBooksData: booksJSON,
            provider: .bookLiveJP
        )

        XCTAssertEqual(books.map(\.volumeNumber), [5, 1, 3])
        XCTAssertEqual(books.map(\.sequenceIndex), [5, 1, 3])
    }

    func testBigBookCoversRetriesOnlyTemporaryProviderFailures() {
        XCTAssertEqual(
            SableLibraryBigBookCoversClient.providerRetryDelay(
                statusCode: 503,
                retryAfter: nil,
                failedAttempt: 1
            ),
            5
        )
        XCTAssertEqual(
            SableLibraryBigBookCoversClient.providerRetryDelay(
                statusCode: 429,
                retryAfter: "45",
                failedAttempt: 1
            ),
            30
        )
        XCTAssertNil(
            SableLibraryBigBookCoversClient.providerRetryDelay(
                statusCode: 404,
                retryAfter: nil,
                failedAttempt: 1
            )
        )
    }

    func testBigBookCoversRejectsChapterRowsAndKeepsImageFallbacks() throws {
        let booksJSON = Data("""
        {
          "count": 3,
          "data": {
            "amz": [
              {
                "id": "book-1",
                "title": "Series Volume 1",
                "url": "https://www.amazon.com/dp/book-1",
                "cover": "https://img.example/original.jpg",
                "coverFallbacks": ["https://img.example/large.jpg"],
                "volume": { "type": "volume", "number": 1 }
              },
              {
                "id": "chapter-2",
                "title": "Series Chapter 2",
                "url": "https://www.amazon.com/dp/chapter-2",
                "cover": "https://img.example/chapter.jpg",
                "volume": { "type": "chapter", "number": 2 }
              },
              {
                "id": "chapter-disguised-as-volume",
                "title": "佐々木とピーちゃん【分冊版】 3",
                "url": "https://booklive.jp/product/index/title_id/20045013/vol_no/003",
                "cover": "https://img.example/chapter-disguised-as-volume.jpg",
                "volume": { "type": "volume", "number": 3 }
              }
            ]
          }
        }
        """.utf8)

        let books = try SableLibraryBigBookCoversClient.bookCandidates(
            fromBooksData: booksJSON,
            provider: .amazon
        )
        let covers = SableLibraryProviderCandidateParser.bigBookCoversCandidates(
            from: books,
            source: .amazon,
            language: "en",
            mediaType: "lightNovel"
        )

        XCTAssertEqual(covers.count, 1)
        XCTAssertEqual(covers.first?.providerItemID, "book-1")
        XCTAssertEqual(covers.first?.fallbackImageURLs, ["https://img.example/large.jpg"])
    }

    func testJapaneseStoreCandidatesRejectEnglishEditionsAndRepairBadProviderVolumes() {
        let books = [
            SableLibraryBigBookCoversBookCandidate(
                provider: .amazonJP,
                id: "jp-1",
                seriesID: "slime-duke",
                title: "【電子版限定特典付き】スライム大公と没落令嬢のあんがい幸せな婚約1 (ＨＪノベルス)",
                url: nil,
                coverURL: "https://img.example/jp-1.jpg",
                coverFallbackURLs: [],
                volumeNumber: 1,
                volumeType: "volume",
                sequenceIndex: 1,
                bookType: "lightNovel"
            ),
            SableLibraryBigBookCoversBookCandidate(
                provider: .amazonJP,
                id: "jp-2",
                seriesID: "slime-duke",
                title: "【電子版限定特典付き】スライム大公と没落令嬢のあんがい幸せな婚約2 (ＨＪノベルス)",
                url: nil,
                coverURL: "https://img.example/jp-2.jpg",
                coverFallbackURLs: [],
                volumeNumber: 1,
                volumeType: "volume",
                sequenceIndex: 2,
                bookType: "lightNovel"
            ),
            SableLibraryBigBookCoversBookCandidate(
                provider: .amazonJP,
                id: "jp-3",
                seriesID: "slime-duke",
                title: "【電子版限定特典付き】スライム大公と没落令嬢のあんがい幸せな婚約3 (ＨＪノベルス)",
                url: nil,
                coverURL: "https://img.example/jp-3.jpg",
                coverFallbackURLs: [],
                volumeNumber: 1,
                volumeType: "volume",
                sequenceIndex: 3,
                bookType: "lightNovel"
            ),
            SableLibraryBigBookCoversBookCandidate(
                provider: .amazonJP,
                id: "en-1",
                seriesID: "slime-duke-en",
                title: "A Surprisingly Happy Engagement for the Slime Duke: Volume 1 (English Edition)",
                url: nil,
                coverURL: "https://img.example/en-1.jpg",
                coverFallbackURLs: [],
                volumeNumber: 1,
                volumeType: "volume",
                sequenceIndex: 4,
                bookType: "lightNovel"
            )
        ]

        let covers = SableLibraryProviderCandidateParser.bigBookCoversCandidates(
            from: books,
            source: .amazonJP,
            language: "jp",
            mediaType: "lightNovel"
        )

        XCTAssertEqual(covers.map(\.providerItemID), ["jp-1", "jp-2", "jp-3"])
        XCTAssertEqual(covers.map(\.volumeNumber), [1, 2, 3])
        XCTAssertTrue(covers.allSatisfy { $0.role == .normal })
    }

    func testBookLiveURLVolumePreventsRelatedBookFromFallingOntoSearchOrder() {
        let books = [
            SableLibraryBigBookCoversBookCandidate(
                provider: .bookLiveJP,
                id: "side-story",
                seriesID: "524527",
                title: "真の仲間 ～お姫様の幸せな日々～【電子限定版】",
                url: "https://booklive.jp/product/index/title_id/524527/vol_no/011",
                coverURL: "https://res.booklive.jp/524527/011/thumbnail/X.jpg",
                coverFallbackURLs: [],
                volumeNumber: nil,
                volumeType: "volume",
                sequenceIndex: 3,
                bookType: "novel"
            ),
            SableLibraryBigBookCoversBookCandidate(
                provider: .bookLiveJP,
                id: "booklet-six",
                seriesID: "20052553",
                title: "ロンリーガールに逆らえない6巻 特装版小冊子電子版",
                url: "https://booklive.jp/product/index/title_id/20052553/vol_no/001",
                coverURL: "https://res.booklive.jp/20052553/001/thumbnail/X.jpg",
                coverFallbackURLs: [],
                volumeNumber: nil,
                volumeType: "volume",
                sequenceIndex: 1,
                bookType: "manga"
            )
        ]

        let covers = SableLibraryProviderCandidateParser.bigBookCoversCandidates(
            from: books,
            source: .bookLiveJP,
            language: "jp",
            mediaType: "lightNovel"
        )

        XCTAssertEqual(covers.first { $0.providerItemID == "side-story" }?.volumeNumber, 11)
        XCTAssertEqual(covers.first { $0.providerItemID == "booklet-six" }?.volumeNumber, 6)
        XCTAssertFalse(
            SableLibraryCoverDownloadPlanner.providerBookIdentityIsCompatible(
                providerTitle: "背中を預けるには 外伝 この恋の涯てには",
                localBookTitle: "You Can Have My Back - Vol 02.epub",
                localVolume: 2
            )
        )
        XCTAssertFalse(
            SableLibraryCoverDownloadPlanner.providerBookIdentityIsCompatible(
                providerTitle: "転生令嬢と数奇な人生を 短篇集",
                localBookTitle: "The Trials and Tribulations - Vol 01.epub",
                localVolume: 1
            )
        )
        XCTAssertFalse(
            SableLibraryCoverDownloadPlanner.providerBookIdentityIsCompatible(
                providerTitle: "幼女戦記 アニメ完全設定資料集",
                localBookTitle: "The Saga of Tanya the Evil - Vol 01.epub",
                localVolume: 1
            )
        )
        XCTAssertTrue(
            SableLibraryCoverDownloadPlanner.providerBookIdentityIsCompatible(
                providerTitle: "Beckoning Fates: The Beginning After the End, Book 3",
                localBookTitle: "The Beginning After the End - Vol 03.epub",
                localVolume: 3
            )
        )
    }

    func testDirectAmazonFallbackRequiresSeriesAndVolumeIdentity() {
        let beginningTitles = [
            "The Beginning After the End",
            "TBATE"
        ]
        XCTAssertTrue(
            SableLibraryCoverDownloadPlanner.providerDirectBookTitleIsCompatible(
                "New Heights: The Beginning After the End, Book 2",
                requestedSeriesTitles: beginningTitles,
                localBookTitle: "The Beginning After The End (2016) - Vol 02.epub",
                localVolume: 2
            )
        )
        XCTAssertFalse(
            SableLibraryCoverDownloadPlanner.providerDirectBookTitleIsCompatible(
                "Skill Emperor Book 1: An Isekai LitRPG Adventure",
                requestedSeriesTitles: beginningTitles,
                localBookTitle: "The Beginning After The End (2016) - Vol 01.epub",
                localVolume: 1
            )
        )
        XCTAssertFalse(
            SableLibraryCoverDownloadPlanner.providerDirectBookTitleIsCompatible(
                "Secrets of the Silent Witch, Vol. 2",
                requestedSeriesTitles: [
                    "Secrets of the Silent Witch -another-",
                    "Secrets of the Silent Witch: Another—Rise of the Barrier Mage"
                ],
                localBookTitle: "Secrets of the Silent Witch Another—Rise of the Barrier Mage (2023) - Vol 02.epub",
                localVolume: 2
            )
        )
        XCTAssertFalse(
            SableLibraryCoverDownloadPlanner.providerDirectBookTitleIsCompatible(
                "One Scottish Lass - A Regency Time Travel Romance Novella",
                requestedSeriesTitles: [
                    "Raffine’s Plan: Save My Favorite Character"
                ],
                localBookTitle: "Raffine’s Plan Save My Favorite Character (2021) - Vol 01.epub",
                localVolume: 1
            )
        )
        XCTAssertTrue(
            SableLibraryCoverDownloadPlanner.providerDirectBookTitleIsCompatible(
                "The Applause of Marielle Clarac",
                requestedSeriesTitles: ["The Tales of Marielle Clarac"],
                localBookTitle: "The Tales Of Marielle Clarac (2017) - Vol 01.epub",
                localVolume: 1
            )
        )
    }

    func testCoverIdentityIgnoresLocalPublicationYearForSingleWordSeries() {
        XCTAssertTrue(
            SableLibraryCoverDownloadPlanner.providerTitleMatchesLocalSeriesStem(
                "Saiyuki Vol. 1",
                localBookTitle: "Saiyuki (1997) - Vol 01.epub"
            )
        )
        XCTAssertFalse(
            SableLibraryCoverDownloadPlanner.providerTitleMatchesLocalSeriesStem(
                "Tower Vol. 1",
                localBookTitle: "My Very Own Tower Strategy Guide (2020) - Vol 01.epub"
            )
        )
    }

    func testCoverSearchPreservesTheOtherLanguagesFinishedState() {
        let japaneseNote =
            "\(SableLibraryCoverSourcePolicy.missingCoverReason(language: "jp")) "
                + "1 of 1 book slots remain empty."
        let englishNote =
            "\(SableLibraryCoverSourcePolicy.missingCoverReason(language: "en")) "
                + "1 of 1 book slots remain empty."

        XCTAssertEqual(
            SableLibraryCoverDownloadPlanner.preservedMissingCoverSearchNotes(
                [japaneseNote, englishNote],
                requestedLanguages: ["en"]
            ),
            [japaneseNote]
        )
        XCTAssertEqual(
            SableLibraryCoverDownloadPlanner.preservedMissingCoverSearchNotes(
                [japaneseNote, englishNote],
                requestedLanguages: ["jp"]
            ),
            [englishNote]
        )
        XCTAssertTrue(
            SableLibraryCoverDownloadPlanner.preservedMissingCoverSearchNotes(
                [japaneseNote, englishNote],
                requestedLanguages: ["jp", "en"]
            ).isEmpty
        )
    }

    func testProviderPageCategorySeparatesSameTitleMangaAndLightNovel() {
        let mangaHTML = """
        <meta name="keywords" content="作品名,マンガ,女性マンガ,電子書籍">
        <meta name="twitter:data2" content="女性マンガ">
        """
        let novelHTML = """
        <meta name="keywords" content="作品名,書籍,女性向けライトノベル,HJ NOVELS,電子書籍">
        <meta name="twitter:data2" content="女性向けライトノベル">
        """

        XCTAssertEqual(
            SableLibraryCoverDownloadPlanner.providerPageMediaType(from: mangaHTML),
            "manga"
        )
        XCTAssertEqual(
            SableLibraryCoverDownloadPlanner.providerPageMediaType(from: novelHTML),
            "novel"
        )
    }

    func testProviderPageCategoryPrefersBookLiveProductMetadataOverSiteNavigation() {
        let html = """
        <meta name="keywords"
              content="作品名,書籍,男性向けライトノベル,ホビージャパン,電子書籍">
        <meta name="twitter:data2" content="男性向けライトノベル">
        <nav>
          少年マンガ 青年マンガ 少女マンガ 女性マンガ コミック
        </nav>
        """

        XCTAssertEqual(
            SableLibraryCoverDownloadPlanner.providerPageMediaType(from: html),
            "novel"
        )
    }

    func testProviderPageCategoryRecognizesBookLiveBLNovel() {
        let html = """
        <meta name="keywords"
              content="死に戻ったモブはラスボスの最愛でした,BL,BL小説,KADOKAWA,電子書籍">
        <nav>
          少年マンガ 青年マンガ 少女マンガ 女性マンガ BLマンガ コミック
        </nav>
        <section class="product-detail">
          <dt>カテゴリ</dt><dd>BL</dd>
          <dt>ジャンル</dt><dd>BL小説</dd>
          <dt>掲載誌・レーベル</dt><dd>ルビーコレクション</dd>
        </section>
        """

        XCTAssertEqual(
            SableLibraryCoverDownloadPlanner.providerPageMediaType(from: html),
            "novel"
        )
        XCTAssertTrue(
            SableLibraryCoverDownloadPlanner.providerMediaTypeIsCompatible(
                "BL小説",
                isCompatibleWith: "novel"
            )
        )
    }

    func testProviderPageCategoryRecognizesBookLiveDomesticNovelMetadata() {
        let html = """
        <title>ノベル　佐々木と宮野　１年生 - 電子書籍・無料漫画ならブックライブ</title>
        <meta name="keywords"
              content="ノベル　佐々木と宮野　１年生,書籍,小説,国内小説,KADOKAWA,電子書籍">
        <meta name="twitter:data2" content="小説 国内小説">
        <nav>
          少年マンガ 青年マンガ 少女マンガ 女性マンガ コミック
        </nav>
        <section class="product-detail">
          <dt>カテゴリ</dt><dd>小説・文芸</dd>
          <dt>ジャンル</dt><dd>小説 / 国内小説</dd>
          <dt>掲載誌・レーベル</dt><dd>MFC ジーンピクシブシリーズ</dd>
        </section>
        """

        XCTAssertEqual(
            SableLibraryCoverDownloadPlanner.providerPageMediaType(from: html),
            "novel"
        )
    }

    func testProviderPageCategoryRecognizesBookWalkerGANovelImprint() {
        let novelHTML = """
        <title>作品名 - 新文芸・ブックス 著者（ＧＡノベル）：電子書籍</title>
        <meta name="keywords"
              content="作品名,著者,イラストレーター,ＧＡノベル,新文芸,電子書籍">
        <nav>マンガ コミック ライトノベル</nav>
        """
        let mangaHTML = """
        <title>作品名 - マンガ（コミック）</title>
        <meta name="keywords"
              content="作品名,著者,ＧＡコミック,青年マンガ,電子書籍">
        <nav>新文芸 ライトノベル マンガ</nav>
        """

        XCTAssertEqual(
            SableLibraryCoverDownloadPlanner.providerPageMediaType(
                from: novelHTML
            ),
            "novel"
        )
        XCTAssertEqual(
            SableLibraryCoverDownloadPlanner.providerPageMediaType(
                from: mangaHTML
            ),
            "manga"
        )
    }

    func testProviderPageCategoryRecognizesBookLiveKotonohaBunkoImprint() {
        let html = """
        <nav>少年マンガ 青年マンガ 少女マンガ 女性マンガ コミック</nav>
        <section class="product-detail">
          <dt>掲載誌・レーベル</dt><dd>ことのは文庫</dd>
        </section>
        """

        XCTAssertEqual(
            SableLibraryCoverDownloadPlanner.providerPageMediaType(from: html),
            "novel"
        )
    }

    func testMangaBakaSeriesRelationshipsPreferV2AndDeduplicateLegacyValues() throws {
        let data = Data(
            """
            {
              "id": 83318,
              "title": "Familia Chronicle",
              "type": "novel",
              "relationships": {
                "main_story": [83316],
                "adaptation": [25301]
              },
              "relationships_v2": [
                {
                  "to_series_id": 4393,
                  "relation_type": "adaptation"
                },
                {
                  "to_series_id": 83316,
                  "relation_type": "main"
                }
              ]
            }
            """.utf8
        )

        let series = try JSONDecoder().decode(
            SableMangaBakaSeriesSummary.self,
            from: data
        )

        XCTAssertEqual(
            series.relationshipReferences,
            [
                SableMangaBakaSeriesRelationshipReference(
                    seriesID: 4393,
                    relationType: "adaptation"
                ),
                SableMangaBakaSeriesRelationshipReference(
                    seriesID: 83316,
                    relationType: "main"
                ),
                SableMangaBakaSeriesRelationshipReference(
                    seriesID: 25301,
                    relationType: "adaptation"
                )
            ]
        )
    }

    func testExactBookLiveProductCannotBorrowDeclaredNovelTypeFromMangaPage() {
        let incorrectMatch = SableLibraryManualCoverSeriesMatch(
            source: .bookLiveJP,
            providerID: "464058",
            itemType: "series",
            title: "異種族レビュアーズ",
            mediaType: "novel",
            bookType: "novel",
            url: "https://booklive.jp/product/index/title_id/464058/vol_no/002",
            thumbnailURL: nil
        )
        let mangaHTML = """
        <meta name="keywords" content="異種族レビュアーズ,マンガ,少年マンガ,電子書籍">
        <section class="product-detail">
          <dt>カテゴリ</dt><dd>少年・青年マンガ</dd>
          <dt>ジャンル</dt><dd>少年マンガ</dd>
          <dt>掲載誌・レーベル</dt><dd>ドラゴンコミックスエイジ</dd>
        </section>
        """

        XCTAssertFalse(
            SableLibraryCoverDownloadPlanner
                .manualSeriesHasEmbeddedStorefrontTypeProof(incorrectMatch)
        )
        let storeType = SableLibraryCoverDownloadPlanner.providerPageMediaType(
            from: mangaHTML
        )
        XCTAssertEqual(storeType, "manga")
        XCTAssertFalse(
            SableLibraryCoverDownloadPlanner.providerMediaTypeIsCompatible(
                storeType,
                isCompatibleWith: "lightNovel"
            )
        )

        var groupMatch = incorrectMatch
        groupMatch.providerID = "105874"
        groupMatch.itemType = "seriesGroup"
        XCTAssertTrue(
            SableLibraryCoverDownloadPlanner
                .manualSeriesHasEmbeddedStorefrontTypeProof(groupMatch)
        )
    }

    func testStorefrontIdentityRecoversSavedProductIDsAndBookLiveVolume() {
        XCTAssertEqual(
            SableLibraryCoverDownloadPlanner.storefrontIdentity(
                from: "https://booklive.jp/product/index/title_id/759409/vol_no/001",
                source: .bookLiveJP
            ),
            .init(
                providerItemID: "759409-001",
                providerSeriesID: "759409",
                providerVolume: 1
            )
        )
        XCTAssertEqual(
            SableLibraryCoverDownloadPlanner.storefrontIdentity(
                from: "https://bookwalker.com/volume/0ZJGM0JEMXV0",
                source: .bookWalkerGlobal
            ).providerItemID,
            "0ZJGM0JEMXV0"
        )
        XCTAssertEqual(
            SableLibraryCoverDownloadPlanner.storefrontIdentity(
                from: "https://bookwalker.jp/de05b15b1a-3faf-446b-b3f2-44760f748eb9",
                source: .bookWalkerJP
            ).providerItemID,
            "05b15b1a-3faf-446b-b3f2-44760f748eb9"
        )
        XCTAssertEqual(
            SableLibraryCoverDownloadPlanner.storefrontIdentity(
                from: "https://www.amazon.com/gp/product/B0CJF9965P?ref_=dbs",
                source: .amazon
            ).providerItemID,
            "B0CJF9965P"
        )
    }

    func testProviderPageTitleReadsStoreMetadataAndDecodesEntities() {
        let html = """
        <meta property="og:title"
              content="追放者食堂へようこそ！ 第1巻 &amp; 特別編 | 電子書籍 BOOK☆WALKER">
        """

        XCTAssertEqual(
            SableLibraryCoverDownloadPlanner.providerPageTitle(
                from: html,
                source: .bookWalkerJP
            ),
            "追放者食堂へようこそ！ 第1巻 & 特別編"
        )
    }

    func testProviderPageCategoryFindsBookLiveDetailsWithoutScanningLargePageNoise() {
        let pageNoise = String(repeating: "recommendation navigation ", count: 40_000)
        let novelHTML = pageNoise + """
        <section class="product-detail">
          <dt>カテゴリ</dt><dd>ライトノベル</dd>
          <dt>ジャンル</dt><dd>男性向けライトノベル</dd>
          <dt>掲載誌・レーベル</dt><dd>HJノベルス</dd>
        </section>
        """
        let mangaHTML = pageNoise + """
        <section class="product-detail">
          <dt>カテゴリ</dt><dd>少年・青年マンガ</dd>
          <dt>ジャンル</dt><dd>少年マンガ</dd>
          <dt>掲載誌・レーベル</dt><dd>HJコミックス</dd>
        </section>
        """

        XCTAssertEqual(
            SableLibraryCoverDownloadPlanner.providerPageMediaType(from: novelHTML),
            "novel"
        )
        XCTAssertEqual(
            SableLibraryCoverDownloadPlanner.providerPageMediaType(from: mangaHTML),
            "manga"
        )
    }

    func testExactBookLiveGroupKeepsSubtitleFirstVolumeTitles() {
        let match = SableLibraryManualCoverSeriesMatch(
            source: .bookLiveJP,
            providerID: "105874",
            itemType: "seriesGroup",
            title: "シュガーアップル・フェアリーテイル",
            mediaType: "novel",
            bookType: "novel",
            url: "https://booklive.jp/search/keyword/tag_ids/105874",
            thumbnailURL: nil
        )
        let books = [
            SableLibraryBigBookCoversBookCandidate(
                provider: .bookLiveJP,
                id: "365955-001",
                seriesID: "365955",
                title: "銀砂糖師と黒の妖精 ～シュガーアップル・フェアリーテイル～",
                url: "https://booklive.jp/product/index/title_id/365955/vol_no/001",
                coverURL: "https://res.booklive.jp/cover-1.jpg",
                coverFallbackURLs: [],
                volumeNumber: 1,
                volumeType: "normal",
                sequenceIndex: 1,
                bookType: "novel"
            ),
            SableLibraryBigBookCoversBookCandidate(
                provider: .bookLiveJP,
                id: "365955-002",
                seriesID: "365955",
                title: "銀砂糖師と青の公爵",
                url: "https://booklive.jp/product/index/title_id/365955/vol_no/002",
                coverURL: "https://res.booklive.jp/cover-2.jpg",
                coverFallbackURLs: [],
                volumeNumber: 2,
                volumeType: "normal",
                sequenceIndex: 2,
                bookType: "novel"
            )
        ]

        XCTAssertEqual(
            SableLibraryCoverDownloadPlanner.booksFromExactManualSeries(
                books,
                match: match,
                source: .bookLiveJP
            ).map(\.id),
            ["365955-001", "365955-002"]
        )
    }

    func testExactBookLiveGroupFiltersRelatedWorksBeforeRenumberingMainRun() {
        let match = SableLibraryManualCoverSeriesMatch(
            source: .bookLiveJP,
            providerID: "555",
            itemType: "seriesGroup",
            title: "本編シリーズ",
            mediaType: "novel",
            bookType: "novel",
            url: "https://booklive.jp/search/keyword/tag_ids/555",
            thumbnailURL: nil
        )
        let rows = [
            SableLibraryBigBookCoversBookCandidate(
                provider: .bookLiveJP,
                id: "100-001",
                seriesID: "555",
                title: "本編シリーズ はじまりの章",
                url: "https://booklive.jp/product/index/title_id/100/vol_no/001",
                coverURL: "https://res.booklive.jp/100/001/thumbnail/X.jpg",
                coverFallbackURLs: [],
                volumeNumber: 1,
                volumeType: "volume",
                sequenceIndex: 1,
                bookType: "novel"
            ),
            SableLibraryBigBookCoversBookCandidate(
                provider: .bookLiveJP,
                id: "101-001",
                seriesID: "555",
                title: "本編シリーズ 外伝 旅人の日記",
                url: "https://booklive.jp/product/index/title_id/101/vol_no/001",
                coverURL: "https://res.booklive.jp/101/001/thumbnail/X.jpg",
                coverFallbackURLs: [],
                volumeNumber: 2,
                volumeType: "volume",
                sequenceIndex: 2,
                bookType: "novel"
            ),
            SableLibraryBigBookCoversBookCandidate(
                provider: .bookLiveJP,
                id: "102-001",
                seriesID: "555",
                title: "本編シリーズ ふたつめの章",
                url: "https://booklive.jp/product/index/title_id/102/vol_no/001",
                coverURL: "https://res.booklive.jp/102/001/thumbnail/X.jpg",
                coverFallbackURLs: [],
                volumeNumber: 3,
                volumeType: "volume",
                sequenceIndex: 3,
                bookType: "novel"
            )
        ]

        let selected = SableLibraryCoverDownloadPlanner.booksFromExactManualSeries(
            rows,
            match: match,
            source: .bookLiveJP
        )

        XCTAssertEqual(selected.map(\.id), ["100-001", "102-001"])
        XCTAssertEqual(selected.map(\.volumeNumber), [1, 2])
    }

    func testExactManualSeriesRejectsSameLanguageCoverFromAnotherSeriesSource() {
        let match = SableLibraryManualCoverSeriesMatch(
            source: .bookLiveJP,
            providerID: "105874",
            itemType: "seriesGroup",
            title: "シュガーアップル・フェアリーテイル",
            mediaType: "novel",
            bookType: "novel",
            url: "https://booklive.jp/search/keyword/tag_ids/105874",
            thumbnailURL: nil
        )
        let request = SableLibraryCoverDownloadRequest(
            seriesTitle: "Sugar Apple Fairy Tale",
            mediaType: "lightNovel",
            queryTitles: ["Sugar Apple Fairy Tale"],
            manualSeriesMatches: [match],
            localBooks: [
                .init(fileName: "Sugar Apple Fairy Tale - Vol 01.epub", volumeNumber: 1)
            ]
        )
        let authoritative =
            SableLibraryCoverDownloadPlanner.authoritativeManualSeriesMatches(
                for: "jp",
                in: request
            )
        let wrongAmazonCover = SableLibraryDownloadedCoverManifestCover(
            language: "jp",
            source: SableLibraryCoverSource.amazonJP.displayName,
            role: .normal,
            status: "selected_downloaded",
            path: "_covers/jp/wrong.jpg",
            width: 1_059,
            height: 1_500,
            bytes: 100,
            url: "https://example.invalid/wrong.jpg",
            providerURL: "https://amazon.co.jp/dp/example",
            editionNote: nil,
            providerTitle: "シュガーアップル・フェアリーテイル 銀砂糖師と紫紺の楽園",
            providerSeriesID: "amazon-series",
            providerItemID: "amazon-item",
            providerVolume: 1,
            providerMediaType: "novel"
        )
        var exactBookLiveCover = wrongAmazonCover
        exactBookLiveCover.source = SableLibraryCoverSource.bookLiveJP.displayName
        exactBookLiveCover.providerSeriesID = "105874"
        exactBookLiveCover.providerItemID = "181410-001"

        XCTAssertEqual(authoritative, [match])
        XCTAssertFalse(
            SableLibraryCoverDownloadPlanner.manifestCover(
                wrongAmazonCover,
                belongsToAny: authoritative
            )
        )
        XCTAssertTrue(
            SableLibraryCoverDownloadPlanner.manifestCover(
                exactBookLiveCover,
                belongsToAny: authoritative
            )
        )
    }

    func testExactManualSeriesUsesOnlyTheChosenProviderForItsLanguage() {
        let match = SableLibraryManualCoverSeriesMatch(
            source: .bookLiveJP,
            providerID: "241910",
            itemType: "series",
            title: "この素晴らしい世界に祝福を！",
            mediaType: "novel",
            bookType: "novel",
            url: "https://booklive.jp/product/index/title_id/241910/vol_no/001",
            thumbnailURL: nil
        )
        let request = SableLibraryCoverDownloadRequest(
            seriesTitle: "Konosuba God's Blessing on This Wonderful World!",
            mediaType: "lightNovel",
            queryTitles: [
                "Konosuba God's Blessing on This Wonderful World!",
                "この素晴らしい世界に祝福を！"
            ],
            manualSeriesMatches: [match],
            localBooks: [
                .init(
                    fileName: "Konosuba - Vol 17.epub",
                    volumeNumber: 17
                )
            ],
            languages: ["jp"],
            includeSpecials: false
        )

        XCTAssertEqual(
            SableLibraryCoverDownloadPlanner.normalCoverDownloadOrder(
                for: "jp",
                in: request
            ),
            [.bookLiveJP]
        )
        XCTAssertFalse(
            SableLibraryCoverDownloadPlanner.shouldRunAutomaticProviderSearch(
                source: .bookLiveJP,
                provider: .bookLiveJP,
                request: request
            )
        )
        XCTAssertEqual(
            SableLibraryCoverDownloadPlanner.normalCoverDownloadOrder(
                for: "en",
                in: request
            ),
            [.mangaBaka, .bookWalkerGlobal, .amazon]
        )
    }

    func testExactStoreMatchKeepsSavedMangaBakaIdentityBaseline() {
        let match = SableLibraryManualCoverSeriesMatch(
            source: .bookLiveJP,
            providerID: "241910",
            itemType: "series",
            title: "この素晴らしい世界に祝福を！",
            mediaType: "novel",
            bookType: "novel",
            url: "https://booklive.jp/product/index/title_id/241910",
            thumbnailURL: nil
        )
        let request = SableLibraryCoverDownloadRequest(
            seriesTitle: "Konosuba God's Blessing on This Wonderful World!",
            mediaType: "lightNovel",
            queryTitles: [
                "Konosuba God's Blessing on This Wonderful World!",
                "この素晴らしい世界に祝福を！"
            ],
            mangaBakaSeriesID: "83998",
            manualSeriesMatches: [match],
            localBooks: [
                .init(
                    fileName: "Konosuba - Vol 17.epub",
                    volumeNumber: 17
                )
            ],
            languages: ["jp"],
            includeSpecials: false
        )

        XCTAssertEqual(
            SableLibraryCoverDownloadPlanner.normalCoverDownloadOrder(
                for: "jp",
                in: request
            ),
            [.mangaBaka, .bookLiveJP]
        )
    }

    func testExactManualSeriesUsesMainNumberedRunAndIgnoresSpinOffs() {
        let seriesID = "241910"
        let seriesTitle = "この素晴らしい世界に祝福を！"
        let match = SableLibraryManualCoverSeriesMatch(
            source: .bookLiveJP,
            providerID: seriesID,
            itemType: "series",
            title: seriesTitle,
            mediaType: "novel",
            bookType: "novel",
            url: "https://booklive.jp/product/index/title_id/241910",
            thumbnailURL: nil
        )
        let mainBooks = (1...17).map { volume in
            SableLibraryBigBookCoversBookCandidate(
                provider: .bookLiveJP,
                id: "main-\(volume)",
                seriesID: seriesID,
                title: volume == 1
                    ? "\(seriesTitle) あぁ、駄女神さま【電子特別版】"
                    : "\(seriesTitle) \(volume) 本編【電子特別版】",
                url: "https://booklive.jp/product/index/title_id/241910/vol_no/\(volume)",
                coverURL: "https://res.booklive.jp/main-\(volume).jpg",
                coverFallbackURLs: [],
                volumeNumber: Double(volume),
                volumeType: "volume",
                sequenceIndex: volume,
                bookType: "novel"
            )
        }
        let siblingBooks = (1...3).map { volume in
            SableLibraryBigBookCoversBookCandidate(
                provider: .bookLiveJP,
                id: "spin-off-\(volume)",
                seriesID: seriesID,
                title: "この素晴らしい世界に爆焔を！ \(volume) \(seriesTitle)スピンオフ",
                url: "https://booklive.jp/spin-off/\(volume)",
                coverURL: "https://res.booklive.jp/spin-off-\(volume).jpg",
                coverFallbackURLs: [],
                volumeNumber: Double(volume),
                volumeType: "volume",
                sequenceIndex: volume,
                bookType: "novel"
            )
        } + (1...4).map { volume in
            SableLibraryBigBookCoversBookCandidate(
                provider: .bookLiveJP,
                id: "side-story-\(volume)",
                seriesID: seriesID,
                title: "\(seriesTitle) よりみち\(volume)回目！",
                url: "https://booklive.jp/side-story/\(volume)",
                coverURL: "https://res.booklive.jp/side-story-\(volume).jpg",
                coverFallbackURLs: [],
                volumeNumber: Double(volume),
                volumeType: "volume",
                sequenceIndex: volume,
                bookType: "novel"
            )
        }

        let selectedBooks = SableLibraryCoverDownloadPlanner.booksFromExactManualSeries(
            siblingBooks + mainBooks,
            match: match,
            source: .bookLiveJP
        )
        let candidates = SableLibraryProviderCandidateParser.bigBookCoversCandidates(
            from: selectedBooks,
            source: .bookLiveJP,
            language: "jp",
            mediaType: "novel"
        )
        let matched = SableLibraryCoverDownloadPlanner.matchedProviderCovers(
            candidates: candidates,
            source: .bookLiveJP,
            language: "jp",
            localBooks: (1...17).map {
                .init(fileName: "Konosuba - Vol \($0).epub", volumeNumber: Double($0))
            },
            includeSpecials: true
        )

        XCTAssertEqual(selectedBooks.map(\.id), mainBooks.map(\.id))
        XCTAssertTrue(
            SableLibraryCoverDownloadPlanner.booksFromExactManualSeries(
                siblingBooks,
                match: match,
                source: .bookLiveJP
            ).isEmpty
        )
        XCTAssertTrue(candidates.allSatisfy { $0.role == .normal })
        XCTAssertEqual(matched.count, 17)
        for volume in 1...17 {
            XCTAssertEqual(matched[volume]?.first?.providerItemID, "main-\(volume)")
        }

        let wrongSiblingCover = SableLibraryDownloadedCoverManifestCover(
            language: "jp",
            source: SableLibraryCoverSource.bookLiveJP.displayName,
            role: .normal,
            status: "selected_downloaded",
            path: "_covers/jp/wrong-spin-off.jpg",
            width: 1_804,
            height: 2_560,
            bytes: 100,
            url: "https://res.booklive.jp/spin-off-1.jpg",
            providerURL: "https://booklive.jp/spin-off/1",
            editionNote: nil,
            providerTitle: siblingBooks[0].title,
            providerSeriesID: seriesID,
            providerItemID: siblingBooks[0].id,
            providerVolume: 1,
            providerMediaType: "novel"
        )
        var mainCover = wrongSiblingCover
        mainCover.providerTitle = mainBooks[0].title
        mainCover.providerItemID = mainBooks[0].id

        XCTAssertFalse(
            SableLibraryCoverDownloadPlanner.manifestCover(
                wrongSiblingCover,
                belongsToAny: [match]
            )
        )
        XCTAssertTrue(
            SableLibraryCoverDownloadPlanner.manifestCover(
                mainCover,
                belongsToAny: [match]
            )
        )
    }

    func testBookLiveSeriesGroupOrdersNormalNovelsAndKeepsCollectorCoverAsExtra() {
        let html = """
        <li class="item clearfix">
          <a href="/product/index/title_id/20053166/vol_no/001"><img src="https://res.booklive.jp/20053166/001/thumbnail/S.jpg" alt="シュガーアップル・フェアリーテイル Collector&#039;s Edition１"></a>
          <span class="category-label__text">ラノベ</span>
        </li>
        <li class="item clearfix">
          <a href="/product/index/title_id/20045444/vol_no/001"><img src="https://res.booklive.jp/20045444/001/thumbnail/S.jpg" alt="シュガーアップル・フェアリーテイル （１）"></a>
          <span class="category-label__text">少女・女性マンガ</span>
        </li>
        <li class="item clearfix">
          <a href="/product/index/title_id/411181/vol_no/001"><img src="https://res.booklive.jp/411181/001/thumbnail/S.jpg" alt="【合本版】シュガーアップル・フェアリーテイル 全17巻"></a>
          <span class="category-label__text">ラノベ</span>
        </li>
        <li class="item clearfix">
          <a href="/product/index/title_id/181413/vol_no/001"><img src="https://res.booklive.jp/181413/001/thumbnail/S.jpg" alt="シュガーアップル・フェアリーテイル 銀砂糖師と緑の工房"></a>
          <span class="category-label__text">ラノベ</span>
        </li>
        <li class="item clearfix">
          <a href="/product/index/title_id/181410/vol_no/001"><img src="https://res.booklive.jp/181410/001/thumbnail/S.jpg" alt="シュガーアップル・フェアリーテイル 銀砂糖師と黒の妖精"></a>
          <span class="category-label__text">ラノベ</span>
        </li>
        """

        let books = SableLibraryBookLiveSeriesGroupClient.seriesGroupBooks(
            from: html,
            groupID: "105874",
            expectedMediaType: "lightNovel"
        )

        XCTAssertEqual(books.map(\.id), ["181410-001", "181413-001", "20053166-001"])
        XCTAssertEqual(books.map(\.volumeNumber), [1, 2, 1])
        XCTAssertEqual(
            SableLibraryCoverDownloadPlanner.coverRole(from: books[2].title),
            .specialEdition
        )
        XCTAssertTrue(books.allSatisfy { $0.bookType == "novel" })
    }

    func testBookLiveProductFamilyFindsEveryVolumeBehindOneSearchTile() {
        let html = """
        <meta name="twitter:data2" content="男性向けライトノベル">
        <div class="series_list_area">
          <li class="item">
            <a href="/product/index/title_id/1091682/vol_no/001"><img src="https://res.booklive.jp/1091682/001/thumbnail/M.jpg" alt="アラフォーになった最強の英雄たち、再び戦場で無双する！！1"></a>
          </li>
          <li class="item">
            <a href="/product/index/title_id/1091682/vol_no/002"><img src="https://res.booklive.jp/1091682/002/thumbnail/M.jpg" alt="アラフォーになった最強の英雄たち、再び戦場で無双する！！2"></a>
          </li>
          <li class="item">
            <a href="/product/index/title_id/1091682/vol_no/003"><img src="https://res.booklive.jp/1091682/003/thumbnail/M.jpg" alt="アラフォーになった最強の英雄たち、再び戦場で無双する！！3"></a>
          </li>
          <li class="item">
            <a href="/product/index/title_id/1091682/vol_no/004"><img src="https://res.booklive.jp/1091682/004/thumbnail/M.jpg" alt="アラフォーになった最強の英雄たち、再び戦場で無双する！！4"></a>
          </li>
          <a href="/product/index/title_id/1310770/vol_no/001"><img src="https://res.booklive.jp/1310770/001/thumbnail/M.jpg" alt="漫画版"></a>
        </div>
        """

        let books = SableLibraryBookLiveSeriesGroupClient.productFamilyBooks(
            from: html,
            titleID: "1091682",
            bookType: "novel"
        )

        XCTAssertEqual(
            SableLibraryBookLiveSeriesGroupClient.titleID(
                from: "https://booklive.jp/product/index/title_id/1091682/vol_no/001"
            ),
            "1091682"
        )
        XCTAssertEqual(
            books.map(\.id),
            ["1091682-001", "1091682-002", "1091682-003", "1091682-004"]
        )
        XCTAssertEqual(books.map(\.volumeNumber), [1, 2, 3, 4])
        XCTAssertTrue(books.allSatisfy { $0.seriesID == "1091682" })
        XCTAssertTrue(books.allSatisfy { $0.bookType == "novel" })
        XCTAssertTrue(books.allSatisfy {
            $0.coverURL.hasSuffix("/thumbnail/X.jpg")
        })
        XCTAssertTrue(books.allSatisfy {
            $0.coverFallbackURLs == [
                $0.coverURL.replacingOccurrences(
                    of: "/thumbnail/X.jpg",
                    with: "/thumbnail/2L.jpg"
                )
            ]
        })
    }

    func testAutomaticBookLiveSelectionUsesSingleNovelSeriesGroupProof() {
        let rawSearchBook = SableLibraryBigBookCoversBookCandidate(
            provider: .bookLiveJP,
            id: "578597-001",
            seriesID: "578597",
            title: "いや、つれさる相手間違ってるから！",
            url: "https://booklive.jp/product/index/title_id/578597/vol_no/001",
            coverURL: "https://res.booklive.jp/578597/001/thumbnail/X.jpg",
            coverFallbackURLs: [],
            volumeNumber: 1,
            volumeType: "volume",
            sequenceIndex: 1,
            bookType: nil
        )
        let seriesGroupBook = SableLibraryBigBookCoversBookCandidate(
            provider: .bookLiveJP,
            id: "578597-001",
            seriesID: "146397",
            title: "いや、つれさる相手間違ってるから！",
            url: "https://booklive.jp/product/index/title_id/578597/vol_no/001",
            coverURL: "https://res.booklive.jp/578597/001/thumbnail/X.jpg",
            coverFallbackURLs: [],
            volumeNumber: 1,
            volumeType: "volume",
            sequenceIndex: 1,
            bookType: "novel"
        )
        let groupMatch = SableLibraryManualCoverSeriesMatch(
            source: .bookLiveJP,
            providerID: "146397",
            itemType: "seriesGroup",
            title: "いや、つれさる相手間違ってるから！",
            mediaType: "novel",
            bookType: "novel",
            url: "https://booklive.jp/search/keyword/tag_ids/146397",
            thumbnailURL: nil
        )

        let selected = SableLibraryCoverDownloadPlanner
            .preferredAutomaticBookLiveSeriesGroupBooks(
                currentBooks: [rawSearchBook],
                groupBooks: [seriesGroupBook],
                groupMatch: groupMatch
            )

        XCTAssertEqual(selected?.map(\.seriesID), ["146397"])
        XCTAssertEqual(selected?.map(\.bookType), ["novel"])
        XCTAssertTrue(
            SableLibraryCoverDownloadPlanner.providerMediaTypeIsCompatible(
                selected?.first?.bookType,
                isCompatibleWith: "lightNovel"
            )
        )
    }

    func testAutomaticBookLiveSearchInspectsPastMangaAndCollectedEditions() {
        XCTAssertEqual(
            SableLibraryCoverDownloadPlanner.automaticSeriesInspectionLimit(for: .bookLiveJP),
            6
        )
        XCTAssertEqual(
            SableLibraryCoverDownloadPlanner.automaticSeriesInspectionLimit(for: .bookWalkerJP),
            2
        )
        XCTAssertEqual(
            SableLibraryCoverDownloadPlanner.automaticSeriesInspectionLimit(for: .amazonJP),
            2
        )
    }

    func testSingleUnnumberedLocalBookAcceptsVerifiedProviderVolumeOne() {
        let candidate = SableLibraryProviderCoverCandidate(
            provider: .local,
            providerSeriesID: "146397",
            providerItemID: "578597-001",
            title: "いや、つれさる相手間違ってるから！",
            volumeIndex: "1",
            volumeNumber: 1,
            mediaType: "novel",
            language: "jp",
            role: .normal,
            providerType: "novel",
            editionNote: nil,
            imageURL: "https://res.booklive.jp/578597/001/thumbnail/X.jpg",
            width: 1_200,
            height: 1_700,
            byteCount: nil,
            storeURLs: [
                "https://booklive.jp/product/index/title_id/578597/vol_no/001"
            ],
            quality: .usable
        )

        let matched = SableLibraryCoverDownloadPlanner.matchedProviderCovers(
            candidates: [candidate],
            source: .bookLiveJP,
            language: "jp",
            localBooks: [
                SableLibraryCoverDownloadLocalBook(
                    fileName: "Hey! You've Kidnapped the Wrong Royal! (2018).epub",
                    volumeNumber: nil
                )
            ],
            includeSpecials: true
        )

        XCTAssertEqual(matched[1]?.map(\.providerItemID), ["578597-001"])
    }

    func testStorefrontMediaTypeOverridesStaleProviderDeclaration() {
        XCTAssertEqual(
            SableLibraryCoverDownloadPlanner.effectiveProviderMediaType(
                declaredSeriesType: "lightNovel",
                storefrontMediaType: "manga",
                bookTypes: ["lightNovel"]
            ),
            "manga"
        )
        XCTAssertEqual(
            SableLibraryCoverDownloadPlanner.effectiveProviderMediaType(
                declaredSeriesType: "manga",
                storefrontMediaType: "novel",
                bookTypes: ["manga"]
            ),
            "novel"
        )
    }

    func testProviderPageCategoryUsesBookWalkerAndAmazonProductBreadcrumbs() {
        let bookWalkerGlobalHTML = #"""
        <script type="application/ld+json">
        {"@type":"BreadcrumbList","itemListElement":[
          {"@type":"ListItem","position":1,"name":"BookWalker"},
          {"@type":"ListItem","position":2,"name":"Novels"}
        ]}
        </script>
        <section>You may also like MANGA AUDIOBOOK NOVEL MANGA</section>
        """#
        let amazonNovelHTML = """
        <nav>Comics &amp; Manga</nav>
        <ul class="a-unordered-list a-horizontal a-size-small">
          <li><a href="/Kindle-Store/b/ref=dp_bc_1?node=133140011">Kindle Store</a></li>
          <li><a href="/Literature-Fiction/b/ref=dp_bc_3?node=157028011">Literature &amp; Fiction</a></li>
        </ul>
        """
        let amazonMangaHTML = """
        <nav>Literature &amp; Fiction</nav>
        <ul class="a-unordered-list a-horizontal a-size-small">
          <li><a href="/Kindle-Store/b/ref=dp_bc_1?node=133140011">Kindle Store</a></li>
          <li><a href="/Comics-Manga/b/ref=dp_bc_3?node=156104011">Comics, Manga &amp; Graphic Novels</a></li>
        </ul>
        """
        let amazonAudiobookHTML = """
        <title>Amazon.com: New Heights: The Beginning After the End, Book 2
        (Audible Audio Edition)</title>
        <nav>
          <a href="/Literature-Fiction/b/ref=dp_bc_3?node=157028011">
            Literature &amp; Fiction
          </a>
        </nav>
        """
        let amazonKindleNovelHTML = """
        <title>Amazon.com: Beckoning Fates: The Beginning After the End, Book 3
        eBook : TurtleMe: Kindle Store</title>
        <nav>
          <a href="/Kindle-Store/b/ref=dp_bc_1?node=133140011">Kindle Store</a>
          <a href="/Kindle-eBooks/b/ref=dp_bc_2?node=154606011">Kindle eBooks</a>
          <a href="/Fantasy-Gaming/b/ref=dp_bc_3?node=158587011">Mage</a>
        </nav>
        """
        let bookWalkerAudiobookHTML = #"""
        <script type="application/ld+json">
        {"@type":"BreadcrumbList","itemListElement":[
          {"@type":"ListItem","position":1,"name":"BookWalker"},
          {"@type":"ListItem","position":2,"name":"Audiobooks"}
        ]}
        </script>
        <section>You may also like MANGA NOVEL MANGA</section>
        """#
        let bookLiveNovelHTML = #"""
        <meta name="keywords" content="転生令嬢と数奇な人生を,書籍,SF・ファンタジー,早川書房">
        <meta name="twitter:data2" content="SF・ファンタジー">
        """#

        XCTAssertEqual(
            SableLibraryCoverDownloadPlanner.providerPageMediaType(from: bookWalkerGlobalHTML),
            "novel"
        )
        XCTAssertEqual(
            SableLibraryCoverDownloadPlanner.providerPageMediaType(from: amazonNovelHTML),
            "novel"
        )
        XCTAssertEqual(
            SableLibraryCoverDownloadPlanner.providerPageMediaType(from: amazonMangaHTML),
            "manga"
        )
        XCTAssertEqual(
            SableLibraryCoverDownloadPlanner.providerPageMediaType(
                from: amazonAudiobookHTML
            ),
            "audiobook"
        )
        XCTAssertEqual(
            SableLibraryCoverDownloadPlanner.providerPageMediaType(
                from: amazonKindleNovelHTML
            ),
            "novel"
        )
        XCTAssertEqual(
            SableLibraryCoverDownloadPlanner.providerPageMediaType(
                from: bookWalkerAudiobookHTML
            ),
            "audiobook"
        )
        XCTAssertEqual(
            SableLibraryCoverDownloadPlanner.providerPageMediaType(from: bookLiveNovelHTML),
            "novel"
        )
        XCTAssertFalse(
            SableLibraryCoverDownloadPlanner.providerMediaTypeIsCompatible(
                "audiobook",
                isCompatibleWith: "lightNovel"
            )
        )
    }

    func testClinicRejectsSquareAudiobookArtworkAsAutomaticBookCover() {
        XCTAssertFalse(
            SableLibraryAppleBooksCompatibilityRepairer.coverDimensionsHaveBookShape(
                width: 1_500,
                height: 1_500
            )
        )
        XCTAssertTrue(
            SableLibraryAppleBooksCompatibilityRepairer.coverDimensionsHaveBookShape(
                width: 1_600,
                height: 2_560
            )
        )
    }

    func testClinicReadsExplicitVolumeNumbersFromCoverText() {
        XCTAssertEqual(
            SableLibraryAppleBooksCompatibilityRepairer.explicitCoverVolumeNumbers(
                in: "THE BEGINNING AFTER THE END RETRIBUTION VOLUME TEN"
            ),
            [10]
        )
        XCTAssertEqual(
            SableLibraryAppleBooksCompatibilityRepairer.explicitCoverVolumeNumbers(
                in: "RECKONING VOL. 9"
            ),
            [9]
        )
        XCTAssertEqual(
            SableLibraryAppleBooksCompatibilityRepairer.explicitCoverVolumeNumbers(
                in: "第12巻"
            ),
            [12]
        )
    }

    func testCoverCleanupRemovesOnlyGeneratedCollisionSuffixes() {
        XCTAssertEqual(
            SableLibraryCoverDownloadService.coverPathRemovingCollisionSuffix(
                "_covers/en/Series - Vol 01 - Cover EN [Amazon] 02.jpg"
            ),
            "_covers/en/Series - Vol 01 - Cover EN [Amazon].jpg"
        )
        XCTAssertEqual(
            SableLibraryCoverDownloadService.coverPathRemovingCollisionSuffix(
                "_covers/jp/Series - Vol 12 - Cover JP [BookLive JP] 100.jpeg"
            ),
            "_covers/jp/Series - Vol 12 - Cover JP [BookLive JP].jpeg"
        )
        XCTAssertNil(
            SableLibraryCoverDownloadService.coverPathRemovingCollisionSuffix(
                "_covers/jp/Series - Vol 01 - Special 01 JP [BookLive JP].jpg"
            )
        )
    }

    func testElectronicBonusWordingIsNotMistakenForAlternateCover() {
        XCTAssertEqual(
            SableLibraryCoverDownloadPlanner.coverRole(
                from: "【電子版限定特典付き】スライム大公と没落令嬢のあんがい幸せな婚約1"
            ),
            .normal
        )
        XCTAssertEqual(
            SableLibraryCoverDownloadPlanner.coverRole(
                from: "Long Take 小冊子付き特別仕立て"
            ),
            .specialEdition
        )
        XCTAssertEqual(
            SableLibraryCoverDownloadPlanner.coverRole(
                from: "【購入特典】限定書き下ろしショートストーリー"
            ),
            .bonus
        )
        XCTAssertEqual(
            SableLibraryCoverDownloadPlanner.coverRole(
                from: "きみが死ぬまで恋をしたい 1 【期間限定無料】"
            ),
            .normal
        )
    }

    func testExistingStoreCoverLanguageCanBeRevalidatedFromItsSource() {
        XCTAssertFalse(
            SableLibraryCoverDownloadPlanner.providerTitleLanguageIsCompatible(
                "Earl and Fairy: Volume 2 (English Edition)",
                language: "jp",
                source: .amazonJP
            )
        )
        XCTAssertFalse(
            SableLibraryCoverDownloadPlanner.providerTitleLanguageIsCompatible(
                "The White Cat's Revenge as Plotted from the Dragon King's Lap: Volume 7",
                language: "jp",
                source: .amazonJP
            )
        )
        XCTAssertTrue(
            SableLibraryCoverDownloadPlanner.providerTitleLanguageIsCompatible(
                "伯爵と妖精 2",
                language: "jp",
                source: .amazonJP
            )
        )
    }

    func testMangaBakaCoverMatchingNeverRelabelsAnotherLanguage() {
        let candidates = [
            SableLibraryProviderCoverCandidate(
                provider: .mangabaka,
                volumeIndex: "1",
                volumeNumber: 1,
                language: "en",
                role: .normal,
                imageURL: "https://images.mangabaka.dev/en-volume-1",
                storeURLs: [],
                quality: .highResolution
            ),
            SableLibraryProviderCoverCandidate(
                provider: .mangabaka,
                volumeIndex: "1",
                volumeNumber: 1,
                language: "ja",
                role: .normal,
                imageURL: "https://images.mangabaka.dev/jp-volume-1",
                storeURLs: [],
                quality: .highResolution
            ),
            SableLibraryProviderCoverCandidate(
                provider: .mangabaka,
                volumeIndex: "1",
                volumeNumber: 1,
                language: nil,
                role: .normal,
                imageURL: "https://images.mangabaka.dev/unknown-volume-1",
                storeURLs: [],
                quality: .highResolution
            )
        ]
        let localBooks = [
            SableLibraryCoverDownloadLocalBook(fileName: "Series - Vol 01.epub", volumeNumber: 1)
        ]

        let japanese = SableLibraryCoverDownloadPlanner.matchedProviderCovers(
            candidates: candidates,
            source: .mangaBaka,
            language: "jp",
            localBooks: localBooks,
            includeSpecials: true
        )
        let english = SableLibraryCoverDownloadPlanner.matchedProviderCovers(
            candidates: candidates,
            source: .mangaBaka,
            language: "en",
            localBooks: localBooks,
            includeSpecials: true
        )

        XCTAssertEqual(japanese[1]?.map(\.imageURL), ["https://images.mangabaka.dev/jp-volume-1"])
        XCTAssertEqual(english[1]?.map(\.imageURL), ["https://images.mangabaka.dev/en-volume-1"])
    }

    func testCoverArchiveAndClinicQualityFloorsStaySeparate() {
        XCTAssertFalse(SableLibraryCoverDownloadPlanner.coverDimensionsAreArchiveUsable(width: 240, height: 343))
        XCTAssertFalse(SableLibraryCoverDownloadPlanner.coverDimensionsAreArchiveUsable(width: 499, height: 900))
        XCTAssertTrue(SableLibraryCoverDownloadPlanner.coverDimensionsAreArchiveUsable(width: 607, height: 861))
        XCTAssertFalse(SableLibraryCoverDownloadPlanner.coverDimensionsAreUsable(width: 240, height: 343))
        XCTAssertFalse(SableLibraryCoverDownloadPlanner.coverDimensionsAreUsable(width: 607, height: 861))
        XCTAssertFalse(SableLibraryCoverDownloadPlanner.coverDimensionsAreUsable(width: 799, height: 1_600))
        XCTAssertFalse(SableLibraryCoverDownloadPlanner.coverDimensionsAreUsable(width: 1_500, height: 1_500))
        XCTAssertTrue(SableLibraryCoverDownloadPlanner.coverDimensionsAreUsable(width: 800, height: 1_100))
        XCTAssertTrue(SableLibraryCoverDownloadPlanner.coverDimensionsAreUsable(width: 1_400, height: 2_000))
    }

    func testCoverRunDropsUnverifiedAmazonNormalButKeepsLocalOriginal() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("SableRefreshEvidence-\(UUID().uuidString)", isDirectory: true)
        let folder = root.appendingPathComponent("Refresh Evidence", isDirectory: true)
        let localPath = "_covers/en/Refresh Evidence - Vol 01 - Cover EN [Original EPUB].jpg"
        let weakStorePath = "_covers/jp/Refresh Evidence - Vol 01 - Cover JP [Amazon JP].jpg"
        for path in [localPath, weakStorePath] {
            let url = folder.appendingPathComponent(path)
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(path.utf8).write(to: url)
        }
        defer { try? fileManager.removeItem(at: root) }

        let manifest = SableLibraryDownloadedCoverManifest(
            generatedAt: "2026-07-24T00:00:00Z",
            seriesTitle: "Refresh Evidence",
            mediaType: "lightNovel",
            entries: [
                .init(
                    bookFile: "Refresh Evidence - Vol 01.epub",
                    volume: 1,
                    covers: [
                        .init(
                            language: "en",
                            source: "Original EPUB",
                            role: .normal,
                            status: "selected_restored_original",
                            path: localPath,
                            width: 1_200,
                            height: 1_800,
                            bytes: nil,
                            url: nil,
                            providerURL: nil,
                            editionNote: "Authentic cover restored from the local EPUB"
                        ),
                        .init(
                            language: "jp",
                            source: SableLibraryCoverSource.amazonJP.displayName,
                            role: .normal,
                            status: "selected_downloaded",
                            path: weakStorePath,
                            width: 938,
                            height: 1_500,
                            bytes: nil,
                            url: "https://amazon.co.jp/dp/example",
                            providerURL: "https://amazon.co.jp/dp/example",
                            editionNote: nil
                        )
                    ]
                )
            ],
            skipped: []
        )
        let manifestURL = folder.appendingPathComponent("_covers/cover-manifest.json")
        try JSONEncoder().encode(manifest).write(to: manifestURL)
        let request = SableLibraryCoverDownloadRequest(
            seriesTitle: "Refresh Evidence",
            mediaType: "lightNovel",
            queryTitles: ["Refresh Evidence"],
            localBooks: [
                .init(fileName: "Refresh Evidence - Vol 01.epub", volumeNumber: 1)
            ],
            languages: [],
            includeSpecials: false,
            refreshExistingNormalCovers: false
        )

        let result = try await SableLibraryCoverDownloadService().downloadCovers(
            request: request,
            folder: folder,
            root: root
        )

        XCTAssertEqual(result.manifest.entries.first?.covers.map(\.path), [localPath])
        XCTAssertFalse(fileManager.fileExists(atPath: folder.appendingPathComponent(weakStorePath).path))
        let quarantineRoot = root
            .appendingPathComponent("_Sable's Library Reports/Cover Quarantine")
        XCTAssertFalse(fileManager.fileExists(atPath: quarantineRoot.path))
    }

    func testInterruptedCoverCleanupRemovesOnlyUnreferencedCoverImages() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("SableInterruptedCover-\(UUID().uuidString)", isDirectory: true)
        let folder = root.appendingPathComponent("Interrupted Cover", isDirectory: true)
        let referencedPath = "_covers/en/Interrupted Cover - Vol 01 - Cover EN [Amazon].jpg"
        let partialPath = "_covers/en/Interrupted Cover - Vol 01 - Cover EN [Amazon] 02.jpg"
        let bookURL = folder.appendingPathComponent("Interrupted Cover - Vol 01.epub")
        let sidecarURL = folder.appendingPathComponent("ComicInfo.json")
        let bookData = Data("protected book contents".utf8)
        let sidecarData = Data(#"{"title":"Interrupted Cover"}"#.utf8)
        for (path, contents) in [
            (referencedPath, "trusted cover"),
            (partialPath, "partial timed-out cover")
        ] {
            let url = folder.appendingPathComponent(path)
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(contents.utf8).write(to: url)
        }
        try bookData.write(to: bookURL)
        try sidecarData.write(to: sidecarURL)
        defer { try? fileManager.removeItem(at: root) }

        let manifest = SableLibraryDownloadedCoverManifest(
            generatedAt: "2026-07-25T00:00:00Z",
            seriesTitle: "Interrupted Cover",
            mediaType: "lightNovel",
            entries: [
                .init(
                    bookFile: "Interrupted Cover - Vol 01.epub",
                    volume: 1,
                    covers: [
                        .init(
                            language: "en",
                            source: SableLibraryCoverSource.amazon.displayName,
                            role: .normal,
                            status: "selected_reused_store_verified",
                            path: referencedPath,
                            width: 1_050,
                            height: 1_500,
                            bytes: nil,
                            url: "https://example.invalid/cover.jpg",
                            providerURL: "https://amazon.com/dp/example",
                            editionNote: nil
                        )
                    ]
                )
            ],
            skipped: []
        )
        let manifestURL = folder.appendingPathComponent("_covers/cover-manifest.json")
        try JSONEncoder().encode(manifest).write(to: manifestURL)

        let notes = SableLibraryCoverDownloadService().cleanupInterruptedCoverDownload(
            folder: folder,
            root: root
        )

        XCTAssertTrue(
            fileManager.fileExists(atPath: folder.appendingPathComponent(referencedPath).path)
        )
        XCTAssertFalse(
            fileManager.fileExists(atPath: folder.appendingPathComponent(partialPath).path)
        )
        XCTAssertTrue(
            notes.contains { $0.contains("removed 1 stale unreferenced cover") },
            notes.joined(separator: "\n")
        )
        XCTAssertEqual(try Data(contentsOf: bookURL), bookData)
        XCTAssertEqual(try Data(contentsOf: sidecarURL), sidecarData)
        let quarantineRoot = root
            .appendingPathComponent("_Sable's Library Reports/Cover Quarantine")
        XCTAssertFalse(fileManager.fileExists(atPath: quarantineRoot.path))
    }

    func testCoverRetryRemovesWrongSeriesNormalInsteadOfRestoringIt() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("SableWrongSeriesCover-\(UUID().uuidString)", isDirectory: true)
        let folder = root.appendingPathComponent("Hell Mode", isDirectory: true)
        let trustedPath = "_covers/jp/Hell Mode - Vol 03 - Cover JP [BookLive JP].jpg"
        let wrongPath = "_covers/en/Hell Mode - Vol 03 - Cover EN [Amazon].jpg"
        for (path, data) in [
            (trustedPath, Data("trusted-japanese-cover".utf8)),
            (wrongPath, Data("unrelated-retro-horror-cover".utf8))
        ] {
            let url = folder.appendingPathComponent(path)
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url)
        }
        defer { try? fileManager.removeItem(at: root) }

        let manifest = SableLibraryDownloadedCoverManifest(
            generatedAt: "2026-07-24T00:00:00Z",
            seriesTitle: "Hell Mode",
            mediaType: "lightNovel",
            entries: [
                .init(
                    bookFile: "Hell Mode - Vol 03.epub",
                    volume: 3,
                    covers: [
                        .init(
                            language: "jp",
                            source: SableLibraryCoverSource.bookLiveJP.displayName,
                            role: .normal,
                            status: "selected_downloaded",
                            path: trustedPath,
                            width: 1_200,
                            height: 1_800,
                            bytes: nil,
                            url: "https://example.invalid/hell-mode-jp.jpg",
                            providerURL: "https://booklive.jp/hell-mode",
                            editionNote: nil,
                            providerTitle: "ヘルモード",
                            providerSeriesID: "126944",
                            providerItemID: "hell-mode-3",
                            providerVolume: 3,
                            providerMediaType: "novel"
                        ),
                        .init(
                            language: "en",
                            source: SableLibraryCoverSource.amazon.displayName,
                            role: .normal,
                            status: "selected_downloaded",
                            path: wrongPath,
                            width: 1_050,
                            height: 1_500,
                            bytes: nil,
                            url: "https://amazon.com/dp/B07J4M8PVC",
                            providerURL: "https://amazon.com/dp/B07J4M8PVC",
                            editionNote: nil,
                            providerTitle: "Hardcore Gaming 101 Digest Vol. 3: The Guide to Retro Horror",
                            providerSeriesID: nil,
                            providerItemID: "B07J4M8PVC",
                            providerVolume: 3,
                            providerMediaType: "novel"
                        )
                    ]
                )
            ],
            skipped: []
        )
        let manifestURL = folder.appendingPathComponent("_covers/cover-manifest.json")
        try JSONEncoder().encode(manifest).write(to: manifestURL)
        let request = SableLibraryCoverDownloadRequest(
            seriesTitle: "Hell Mode",
            mediaType: "lightNovel",
            queryTitles: [
                "Hell Mode",
                "Hell Mode: The Hardcore Gamer Dominates in Another World with Garbage Balancing",
                "ヘルモード"
            ],
            localBooks: [
                .init(fileName: "Hell Mode - Vol 03.epub", volumeNumber: 3)
            ],
            languages: [],
            includeSpecials: false
        )

        let result = try await SableLibraryCoverDownloadService().downloadCovers(
            request: request,
            folder: folder,
            root: root
        )

        XCTAssertEqual(result.manifest.entries.first?.covers.map(\.path), [trustedPath])
        XCTAssertFalse(fileManager.fileExists(atPath: folder.appendingPathComponent(wrongPath).path))
        XCTAssertTrue(
            result.skipped.contains {
                $0.contains("Local safety pass removed 1")
                    || $0.contains("removed 1 stale unreferenced cover")
            },
            result.skipped.joined(separator: "\n")
        )
        let quarantineRoot = root
            .appendingPathComponent("_Sable's Library Reports/Cover Quarantine")
        XCTAssertFalse(fileManager.fileExists(atPath: quarantineRoot.path))
    }

    func testCoverFallbackOnlyReceivesStillEmptyBookSlots() {
        let covers = [
            1: [
                SableLibraryProviderCoverCandidate(
                    provider: .mangabaka,
                    volumeNumber: 1,
                    language: "en",
                    role: .normal,
                    imageURL: "https://images.mangabaka.dev/volume-1",
                    storeURLs: [],
                    quality: .highResolution
                )
            ],
            2: [
                SableLibraryProviderCoverCandidate(
                    provider: .mangabaka,
                    volumeNumber: 2,
                    language: "en",
                    role: .normal,
                    imageURL: "https://images.mangabaka.dev/volume-2",
                    storeURLs: [],
                    quality: .highResolution
                )
            ]
        ]

        let pending = SableLibraryCoverDownloadPlanner.covers(covers, forBookIndexes: [2])

        XCTAssertEqual(Set(pending.keys), [2])
        XCTAssertEqual(pending[2]?.first?.volumeNumber, 2)
    }

    func testCoverManifestCompletenessRequiresBothLanguages() {
        XCTAssertEqual(
            SableLibraryCoverDownloadPlanner.missingRequiredCoverLanguages(from: ["ja"]),
            ["en"]
        )
        XCTAssertEqual(
            SableLibraryCoverDownloadPlanner.missingRequiredCoverLanguages(from: ["en-US"]),
            ["jp"]
        )
        XCTAssertTrue(
            SableLibraryCoverDownloadPlanner.missingRequiredCoverLanguages(from: ["ja", "en"]).isEmpty
        )
    }

    func testCoverSearchPersistsAnEmptyManifestBeforeReportingNoTrustedResult() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SableCoverNoResult-\(UUID().uuidString)", isDirectory: true)
        let folder = root.appendingPathComponent("No Result Series", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let request = SableLibraryCoverDownloadRequest(
            seriesTitle: "No Result Series",
            mediaType: "lightNovel",
            queryTitles: ["No Result Series"],
            localBooks: [
                SableLibraryCoverDownloadLocalBook(
                    fileName: "No Result Series - Vol 01.epub",
                    volumeNumber: 1
                )
            ],
            languages: []
        )

        do {
            _ = try await SableLibraryCoverDownloadService().downloadCovers(
                request: request,
                folder: folder,
                root: root
            )
            XCTFail("A search with no provider languages should report no trusted covers.")
        } catch let error as SableLibraryCoverDownloadError {
            guard case .noTrustedCovers = error else {
                return XCTFail("Expected noTrustedCovers, got \(error.localizedDescription)")
            }
        }

        let manifestURL = folder.appendingPathComponent("_covers/cover-manifest.json")
        let manifestData = try Data(contentsOf: manifestURL)
        let manifestObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: manifestData) as? [String: Any]
        )
        let entries = try XCTUnwrap(manifestObject["entries"] as? [[String: Any]])

        XCTAssertTrue(entries.isEmpty)
        XCTAssertNotNil(manifestObject["generated_at"] as? String)
    }

    func testCoverGapRetryReusesTrustedManifestCoverWithoutDownloadingOrDuplicating() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("SableCoverReuse-\(UUID().uuidString)", isDirectory: true)
        let folder = root.appendingPathComponent("Trusted Existing Series", isDirectory: true)
        let relativeCoverPath = "_covers/en/Trusted Existing Series - Vol 01 - Cover EN [BookWalker Global].jpg"
        let coverURL = folder.appendingPathComponent(relativeCoverPath)
        try fileManager.createDirectory(
            at: coverURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("existing-cover".utf8).write(to: coverURL)
        defer { try? fileManager.removeItem(at: root) }

        let existingManifest = SableLibraryDownloadedCoverManifest(
            generatedAt: "2026-07-23T00:00:00Z",
            seriesTitle: "Trusted Existing Series",
            mediaType: "lightNovel",
            entries: [
                SableLibraryDownloadedCoverManifestEntry(
                    bookFile: "Trusted Existing Series - Vol 01.epub",
                    volume: 1,
                    covers: [
                        SableLibraryDownloadedCoverManifestCover(
                            language: "en",
                            source: SableLibraryCoverSource.bookWalkerGlobal.displayName,
                            role: .normal,
                            status: "selected_downloaded",
                            path: relativeCoverPath,
                            width: 1_200,
                            height: 1_800,
                            bytes: 14,
                            url: "https://example.invalid/cover.jpg",
                            providerURL: "https://global.bookwalker.jp/example",
                            editionNote: nil,
                            providerTitle: "Trusted Existing Series Volume 1",
                            providerSeriesID: "trusted-series",
                            providerItemID: "trusted-volume-1",
                            providerVolume: 1,
                            providerMediaType: "novel"
                        )
                    ]
                )
            ],
            skipped: []
        )
        let manifestURL = folder.appendingPathComponent("_covers/cover-manifest.json")
        try JSONEncoder().encode(existingManifest).write(to: manifestURL)

        let request = SableLibraryCoverDownloadRequest(
            seriesTitle: "Trusted Existing Series",
            mediaType: "lightNovel",
            queryTitles: ["Trusted Existing Series"],
            localBooks: [
                .init(
                    fileName: "Trusted Existing Series - Vol 01.epub",
                    volumeNumber: 1
                )
            ],
            languages: ["en"],
            includeSpecials: false
        )
        let service = SableLibraryCoverDownloadService()

        let firstResult = try await service.downloadCovers(
            request: request,
            folder: folder,
            root: root
        )
        let secondResult = try await service.downloadCovers(
            request: request,
            folder: folder,
            root: root
        )
        let imageFiles = try fileManager.contentsOfDirectory(
            at: coverURL.deletingLastPathComponent(),
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension.lowercased() == "jpg" }
        let manifestBackups = try fileManager.contentsOfDirectory(
            at: manifestURL.deletingLastPathComponent(),
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix("cover-manifest.backup-") }

        XCTAssertEqual(firstResult.downloadedCount, 0)
        XCTAssertEqual(firstResult.reusedCount, 1)
        XCTAssertEqual(secondResult.downloadedCount, 0)
        XCTAssertEqual(secondResult.reusedCount, 1)
        XCTAssertEqual(imageFiles.map(\.lastPathComponent), [coverURL.lastPathComponent])
        XCTAssertTrue(manifestBackups.isEmpty)
    }

    func testExistingCoverStoreProofRepairDoesNotReplaceImage() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent(
                "SableStoreProofRepair-\(UUID().uuidString)",
                isDirectory: true
            )
        let folder = root.appendingPathComponent(
            "Welcome to the Outcast's Restaurant",
            isDirectory: true
        )
        let relativeCoverPath =
            "_covers/jp/Welcome to the Outcast's Restaurant - Vol 01 - Cover JP [BookLive JP].jpg"
        let coverURL = folder.appendingPathComponent(relativeCoverPath)
        try fileManager.createDirectory(
            at: coverURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let originalImageData = Data("existing-cover-must-not-change".utf8)
        try originalImageData.write(to: coverURL)
        defer { try? fileManager.removeItem(at: root) }

        let manifest = SableLibraryDownloadedCoverManifest(
            generatedAt: "2026-07-20T00:00:00Z",
            seriesTitle: "Welcome to the Outcast's Restaurant",
            mediaType: "lightNovel",
            entries: [
                .init(
                    bookFile: "Welcome to the Outcast's Restaurant - Vol 01.epub",
                    volume: 1,
                    covers: [
                        .init(
                            language: "jp",
                            source: SableLibraryCoverSource.bookLiveJP.displayName,
                            role: .normal,
                            status: "selected_downloaded",
                            path: relativeCoverPath,
                            width: 1_200,
                            height: 1_800,
                            bytes: originalImageData.count,
                            url: "https://res.booklive.jp/759409/001/thumbnail/X.jpg",
                            providerURL: "https://booklive.jp/product/index/title_id/759409/vol_no/001",
                            editionNote: nil,
                            providerTitle: "追放者食堂へようこそ！ 第1巻",
                            providerSeriesID: "759409",
                            providerItemID: "759409-001",
                            providerVolume: 1,
                            providerMediaType: "manga"
                        )
                    ]
                )
            ],
            skipped: []
        )
        let manifestURL = folder.appendingPathComponent(
            "_covers/cover-manifest.json"
        )
        try JSONEncoder().encode(manifest).write(to: manifestURL)

        let storeHTML = """
        <meta property="og:title" content="追放者食堂へようこそ！ 第1巻">
        <section class="product-detail">
          <dt>カテゴリ</dt><dd>ライトノベル</dd>
          <dt>ジャンル</dt><dd>男性向けライトノベル</dd>
        </section>
        """
        let service = SableLibraryCoverDownloadService(
            storefrontHTMLLoader: { _ in storeHTML }
        )
        let result = try await service.downloadCovers(
            request: SableLibraryCoverDownloadRequest(
                seriesTitle: "Welcome to the Outcast's Restaurant",
                mediaType: "lightNovel",
                queryTitles: [
                    "Welcome to the Outcast's Restaurant",
                    "追放者食堂へようこそ！"
                ],
                localBooks: [
                    .init(
                        fileName: "Welcome to the Outcast's Restaurant - Vol 01.epub",
                        volumeNumber: 1
                    )
                ],
                languages: ["jp"],
                includeSpecials: false,
                verifyExistingStoreEvidenceOnly: true
            ),
            folder: folder,
            root: root
        )

        let repairedCover = try XCTUnwrap(
            result.manifest.entries.first?.covers.first
        )
        XCTAssertEqual(result.downloadedCount, 0)
        XCTAssertEqual(try Data(contentsOf: coverURL), originalImageData)
        XCTAssertEqual(repairedCover.path, relativeCoverPath)
        XCTAssertEqual(repairedCover.providerTitle, "追放者食堂へようこそ！ 第1巻")
        XCTAssertEqual(repairedCover.providerSeriesID, "759409")
        XCTAssertEqual(repairedCover.providerItemID, "759409-001")
        XCTAssertEqual(repairedCover.providerVolume, 1)
        XCTAssertEqual(repairedCover.providerMediaType, "novel")
        XCTAssertEqual(repairedCover.status, "selected_reused_store_verified")
        XCTAssertTrue(
            result.manifest.skipped.contains {
                $0 == "Store proof repair JP finished: schema 4; all existing covers now have store evidence."
            }
        )
    }

    func testStoreProofRefreshCorrectsFalseNovelClaimWithoutReplacingImage() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent(
                "SableInterspeciesStoreProof-\(UUID().uuidString)",
                isDirectory: true
            )
        let folder = root.appendingPathComponent(
            "Interspecies Reviewers",
            isDirectory: true
        )
        let relativeCoverPath =
            "_covers/jp/Interspecies Reviewers, Vol. 2 - Cover JP [BookLive JP].jpg"
        let coverURL = folder.appendingPathComponent(relativeCoverPath)
        try fileManager.createDirectory(
            at: coverURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let originalImageData = Data("manga-cover-must-remain-recoverable".utf8)
        try originalImageData.write(to: coverURL)
        defer { try? fileManager.removeItem(at: root) }

        let manifest = SableLibraryDownloadedCoverManifest(
            generatedAt: "2026-07-25T00:00:00Z",
            seriesTitle: "Interspecies Reviewers",
            mediaType: "lightNovel",
            entries: [
                .init(
                    bookFile: "Interspecies Reviewers, Vol. 2- Marionette Crisis.epub",
                    volume: 2,
                    covers: [
                        .init(
                            language: "jp",
                            source: SableLibraryCoverSource.bookLiveJP.displayName,
                            role: .normal,
                            status: "selected_downloaded",
                            path: relativeCoverPath,
                            width: 1_806,
                            height: 2_560,
                            bytes: originalImageData.count,
                            url: "https://res.booklive.jp/464058/002/thumbnail/X.jpg",
                            providerURL: "https://booklive.jp/product/index/title_id/464058/vol_no/002",
                            editionNote: nil,
                            providerTitle: "異種族レビュアーズ　2",
                            providerSeriesID: "464058",
                            providerItemID: "464058-002",
                            providerVolume: 2,
                            providerMediaType: "lightNovel"
                        )
                    ]
                )
            ],
            skipped: []
        )
        let manifestURL = folder.appendingPathComponent("_covers/cover-manifest.json")
        try JSONEncoder().encode(manifest).write(to: manifestURL)

        let mangaHTML = """
        <meta property="og:title" content="異種族レビュアーズ　2">
        <meta name="keywords" content="異種族レビュアーズ,マンガ,少年マンガ,電子書籍">
        <section class="product-detail">
          <dt>カテゴリ</dt><dd>少年・青年マンガ</dd>
          <dt>掲載誌・レーベル</dt><dd>ドラゴンコミックスエイジ</dd>
        </section>
        """
        let result = try await SableLibraryCoverDownloadService(
            storefrontHTMLLoader: { _ in mangaHTML }
        ).downloadCovers(
            request: .init(
                seriesTitle: "Interspecies Reviewers",
                mediaType: "lightNovel",
                queryTitles: ["Interspecies Reviewers", "異種族レビュアーズ"],
                localBooks: [
                    .init(
                        fileName: "Interspecies Reviewers, Vol. 2- Marionette Crisis.epub",
                        volumeNumber: 2
                    )
                ],
                languages: ["jp"],
                includeSpecials: false,
                verifyExistingStoreEvidenceOnly: true
            ),
            folder: folder,
            root: root
        )

        let repairedCover = try XCTUnwrap(result.manifest.entries.first?.covers.first)
        XCTAssertEqual(result.downloadedCount, 0)
        XCTAssertEqual(try Data(contentsOf: coverURL), originalImageData)
        XCTAssertEqual(repairedCover.providerMediaType, "manga")
        XCTAssertEqual(repairedCover.status, "selected_reused_store_verified")
    }

    func testStoreProofRefreshDoesNotVerifyURLIdentityWithoutPageMediaType() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent(
                "SableStoreProofNeedsMediaType-\(UUID().uuidString)",
                isDirectory: true
            )
        let folder = root.appendingPathComponent("Unproven Store Cover", isDirectory: true)
        let relativeCoverPath =
            "_covers/en/Unproven Store Cover - Vol 01 - Cover EN [BookWalker Global].jpg"
        let coverURL = folder.appendingPathComponent(relativeCoverPath)
        try fileManager.createDirectory(
            at: coverURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("existing-unproven-cover".utf8).write(to: coverURL)
        defer { try? fileManager.removeItem(at: root) }

        let manifest = SableLibraryDownloadedCoverManifest(
            generatedAt: "2026-07-25T00:00:00Z",
            seriesTitle: "Unproven Store Cover",
            mediaType: "lightNovel",
            entries: [
                .init(
                    bookFile: "Unproven Store Cover - Vol 01.epub",
                    volume: 1,
                    covers: [
                        .init(
                            language: "en",
                            source: SableLibraryCoverSource.bookWalkerGlobal.displayName,
                            role: .normal,
                            status: "selected_downloaded",
                            path: relativeCoverPath,
                            width: 1_200,
                            height: 1_800,
                            bytes: nil,
                            url: "https://example.invalid/cover.jpg",
                            providerURL: "https://bookwalker.com/volume/ABC123",
                            editionNote: nil,
                            providerTitle: "Unproven Store Cover, Vol. 1",
                            providerSeriesID: nil,
                            providerItemID: nil,
                            providerVolume: 1,
                            providerMediaType: nil
                        )
                    ]
                )
            ],
            skipped: []
        )
        let manifestURL = folder.appendingPathComponent("_covers/cover-manifest.json")
        try JSONEncoder().encode(manifest).write(to: manifestURL)

        let result = try await SableLibraryCoverDownloadService(
            storefrontHTMLLoader: { _ in
                #"<meta property="og:title" content="Unproven Store Cover, Vol. 1">"#
            }
        ).downloadCovers(
            request: .init(
                seriesTitle: "Unproven Store Cover",
                mediaType: "lightNovel",
                queryTitles: ["Unproven Store Cover"],
                localBooks: [
                    .init(
                        fileName: "Unproven Store Cover - Vol 01.epub",
                        volumeNumber: 1
                    )
                ],
                languages: ["en"],
                includeSpecials: false,
                verifyExistingStoreEvidenceOnly: true
            ),
            folder: folder,
            root: root
        )

        let repairedCover = try XCTUnwrap(result.manifest.entries.first?.covers.first)
        XCTAssertEqual(repairedCover.providerItemID, "ABC123")
        XCTAssertNil(repairedCover.providerMediaType)
        XCTAssertFalse(repairedCover.status.contains("store_verified"))
        XCTAssertTrue(repairedCover.status.contains("store_checked_unverified"))
        XCTAssertTrue(
            result.manifest.skipped.contains {
                $0 == "Store proof repair EN finished: schema 4; 1 existing cover still needs a readable product page or exact series choice."
            }
        )
    }

    func testJapaneseManualSeriesAliasPreservesArchivedCoverOnRetry() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("SableJapaneseCoverAlias-\(UUID().uuidString)", isDirectory: true)
        let folder = root.appendingPathComponent("Sugar Apple Fairy Tale", isDirectory: true)
        let relativeCoverPath =
            "_covers/jp/Sugar Apple Fairy Tale - Vol 02 - Cover JP [BookLive JP].jpg"
        let coverURL = folder.appendingPathComponent(relativeCoverPath)
        try fileManager.createDirectory(
            at: coverURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("booklive-japanese-cover".utf8).write(to: coverURL)
        defer { try? fileManager.removeItem(at: root) }

        let japaneseTitle = "シュガーアップル・フェアリーテイル"
        let manualMatch = SableLibraryManualCoverSeriesMatch(
            source: .bookLiveJP,
            providerID: "105874",
            itemType: "seriesGroup",
            title: japaneseTitle,
            mediaType: "novel",
            bookType: "novel",
            url: "https://booklive.jp/search/keyword/tag_ids/105874",
            thumbnailURL: nil
        )
        let manifest = SableLibraryDownloadedCoverManifest(
            generatedAt: "2026-07-24T00:00:00Z",
            seriesTitle: "Sugar Apple Fairy Tale",
            mediaType: "lightNovel",
            manualSeriesMatches: [manualMatch],
            entries: [
                .init(
                    bookFile: "Sugar Apple Fairy Tale - Vol 02.epub",
                    volume: 2,
                    covers: [
                        .init(
                            language: "jp",
                            source: SableLibraryCoverSource.bookLiveJP.displayName,
                            role: .normal,
                            status: "archived_below_clinic_quality",
                            path: relativeCoverPath,
                            width: 607,
                            height: 861,
                            bytes: 23,
                            url: "https://res.booklive.jp/example.jpg",
                            providerURL: "https://booklive.jp/product/index/title_id/181410/vol_no/002",
                            editionNote: nil,
                            providerTitle: "\(japaneseTitle) 2",
                            providerSeriesID: "105874",
                            providerItemID: "181410-002",
                            providerVolume: 2,
                            providerMediaType: "novel"
                        )
                    ]
                )
            ],
            skipped: []
        )
        let manifestURL = folder.appendingPathComponent("_covers/cover-manifest.json")
        try JSONEncoder().encode(manifest).write(to: manifestURL)

        let request = SableLibraryCoverDownloadRequest(
            seriesTitle: "Sugar Apple Fairy Tale",
            mediaType: "lightNovel",
            queryTitles: ["Sugar Apple Fairy Tale", japaneseTitle],
            manualSeriesMatches: [manualMatch],
            localBooks: [
                .init(
                    fileName: "Sugar Apple Fairy Tale - Vol 02.epub",
                    volumeNumber: 2
                )
            ],
            languages: ["jp"],
            includeSpecials: false
        )

        let result = try await SableLibraryCoverDownloadService().downloadCovers(
            request: request,
            folder: folder,
            root: root
        )

        XCTAssertEqual(result.downloadedCount, 0)
        XCTAssertEqual(result.reusedCount, 1)
        XCTAssertEqual(result.manifest.entries.first?.covers.first?.path, relativeCoverPath)
        XCTAssertEqual(
            result.manifest.entries.first?.covers.first?.status,
            "archived_below_clinic_quality"
        )
        XCTAssertTrue(fileManager.fileExists(atPath: coverURL.path))
    }

    func testCoverRerunRemovesByteIdenticalCrossVolumeAssignments() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("SableCrossVolumeCover-\(UUID().uuidString)", isDirectory: true)
        let folder = root.appendingPathComponent("Cross Volume Series", isDirectory: true)
        let firstPath = "_covers/en/Cross Volume Series - Vol 01 - Cover EN [BookWalker Global].jpg"
        let secondPath = "_covers/en/Cross Volume Series - Vol 02 - Cover EN [BookWalker Global].jpg"
        for relativePath in [firstPath, secondPath] {
            let url = folder.appendingPathComponent(relativePath)
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("same-cover-bytes".utf8).write(to: url)
        }
        defer { try? fileManager.removeItem(at: root) }

        let makeCover: (String, String, Int?) -> SableLibraryDownloadedCoverManifestCover = {
            path, itemID, volume in
            SableLibraryDownloadedCoverManifestCover(
                language: "en",
                source: SableLibraryCoverSource.bookWalkerGlobal.displayName,
                role: .normal,
                status: "selected_downloaded",
                path: path,
                width: 1_200,
                height: 1_800,
                bytes: 16,
                url: "https://example.invalid/\(itemID).jpg",
                providerURL: "https://global.bookwalker.jp/\(itemID)",
                editionNote: nil,
                providerTitle: "Cross Volume Series",
                providerSeriesID: "cross-volume-series",
                providerItemID: itemID,
                providerVolume: volume.map(Double.init),
                providerMediaType: "novel"
            )
        }
        let manifest = SableLibraryDownloadedCoverManifest(
            generatedAt: "2026-07-23T00:00:00Z",
            seriesTitle: "Cross Volume Series",
            mediaType: "lightNovel",
            entries: [
                .init(
                    bookFile: "Cross Volume Series - Vol 01.epub",
                    volume: 1,
                    covers: [makeCover(firstPath, "volume-1", 1)]
                ),
                .init(
                    bookFile: "Cross Volume Series - Vol 02.epub",
                    volume: 2,
                    covers: [makeCover(secondPath, "legacy-ambiguous", nil)]
                )
            ],
            skipped: []
        )
        let manifestURL = folder.appendingPathComponent("_covers/cover-manifest.json")
        try JSONEncoder().encode(manifest).write(to: manifestURL)
        let request = SableLibraryCoverDownloadRequest(
            seriesTitle: "Cross Volume Series",
            mediaType: "lightNovel",
            queryTitles: ["Cross Volume Series"],
            localBooks: [
                .init(fileName: "Cross Volume Series - Vol 01.epub", volumeNumber: 1),
                .init(fileName: "Cross Volume Series - Vol 02.epub", volumeNumber: 2)
            ],
            languages: [],
            includeSpecials: false
        )

        let result = try await SableLibraryCoverDownloadService().downloadCovers(
            request: request,
            folder: folder,
            root: root
        )

        XCTAssertEqual(result.manifest.entries.count, 1)
        XCTAssertEqual(result.manifest.entries.first?.bookFile, "Cross Volume Series - Vol 01.epub")
        XCTAssertTrue(result.skipped.contains { $0.contains("visually equivalent") })
        XCTAssertTrue(fileManager.fileExists(atPath: folder.appendingPathComponent(firstPath).path))
        XCTAssertFalse(fileManager.fileExists(atPath: folder.appendingPathComponent(secondPath).path))
        let quarantineRoot = root
            .appendingPathComponent("_Sable's Library Reports/Cover Quarantine")
        XCTAssertFalse(fileManager.fileExists(atPath: quarantineRoot.path))
    }

    func testEnglishCoverRetryDoesNotSanitizeJapaneseAssignments() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("SableLanguageScopedCover-\(UUID().uuidString)", isDirectory: true)
        let folder = root.appendingPathComponent("Language Scoped Series", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        func cover(
            language: String,
            volume: Int,
            path: String
        ) -> SableLibraryDownloadedCoverManifestCover {
            SableLibraryDownloadedCoverManifestCover(
                language: language,
                source: language == "jp"
                    ? SableLibraryCoverSource.bookLiveJP.displayName
                    : SableLibraryCoverSource.amazon.displayName,
                role: .normal,
                status: "selected_downloaded",
                path: path,
                width: 1_000,
                height: 1_500,
                bytes: nil,
                url: "https://example.invalid/\(language)-\(volume).jpg",
                providerURL: "https://example.invalid/\(language)-\(volume)",
                editionNote: nil,
                providerTitle: language == "jp"
                    ? "言語別シリーズ \(volume)"
                    : "Language Scoped Series Volume \(volume)",
                providerSeriesID: "\(language)-series",
                providerItemID: "\(language)-volume-\(volume)",
                providerVolume: Double(volume),
                providerMediaType: "novel"
            )
        }

        var entries: [SableLibraryDownloadedCoverManifestEntry] = []
        for volume in 1...2 {
            let englishPath =
                "_covers/en/Language Scoped Series - Vol 0\(volume) - Cover EN [Amazon].jpg"
            let japanesePath =
                "_covers/jp/Language Scoped Series - Vol 0\(volume) - Cover JP [BookLive JP].jpg"
            for (path, data) in [
                (englishPath, Data("english-\(volume)".utf8)),
                (japanesePath, Data("same-japanese-cover".utf8))
            ] {
                let url = folder.appendingPathComponent(path)
                try fileManager.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: url)
            }
            entries.append(
                .init(
                    bookFile: "Language Scoped Series - Vol 0\(volume).epub",
                    volume: Double(volume),
                    covers: [
                        cover(language: "en", volume: volume, path: englishPath),
                        cover(language: "jp", volume: volume, path: japanesePath)
                    ]
                )
            )
        }

        let manifestURL = folder.appendingPathComponent("_covers/cover-manifest.json")
        let manifest = SableLibraryDownloadedCoverManifest(
            generatedAt: "2026-07-24T00:00:00Z",
            seriesTitle: "Language Scoped Series",
            mediaType: "lightNovel",
            entries: entries,
            skipped: []
        )
        try JSONEncoder().encode(manifest).write(to: manifestURL)
        let request = SableLibraryCoverDownloadRequest(
            seriesTitle: "Language Scoped Series",
            mediaType: "lightNovel",
            queryTitles: ["Language Scoped Series"],
            localBooks: (1...2).map {
                .init(
                    fileName: "Language Scoped Series - Vol 0\($0).epub",
                    volumeNumber: Double($0)
                )
            },
            languages: ["en"],
            includeSpecials: false
        )

        let result = try await SableLibraryCoverDownloadService().downloadCovers(
            request: request,
            folder: folder,
            root: root
        )
        let japaneseCovers = result.manifest.entries.flatMap(\.covers).filter {
            SableLibraryCoverDownloadPlanner.normalizedLanguage($0.language) == "jp"
        }

        XCTAssertEqual(result.reusedCount, 2)
        XCTAssertEqual(japaneseCovers.count, 2)
        XCTAssertFalse(result.skipped.contains { $0.contains("Local safety pass removed") })
    }

    func testCoverRerunKeepsVisuallySimilarCoversWithDistinctStrongVolumeIdentity() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("SableSimilarVolumeCovers-\(UUID().uuidString)", isDirectory: true)
        let folder = root.appendingPathComponent("Similar Numbered Series", isDirectory: true)
        let firstPath = "_covers/en/Similar Numbered Series - Vol 01 - Cover EN [BookWalker Global].png"
        let secondPath = "_covers/en/Similar Numbered Series - Vol 02 - Cover EN [BookWalker Global].png"
        let pixel = try XCTUnwrap(
            Data(
                base64Encoded:
                    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
            )
        )
        for (relativePath, suffix) in [(firstPath, "volume-1"), (secondPath, "volume-2")] {
            let url = folder.appendingPathComponent(relativePath)
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            var data = pixel
            data.append(Data(suffix.utf8))
            try data.write(to: url)
        }
        defer { try? fileManager.removeItem(at: root) }

        let makeCover: (String, Int) -> SableLibraryDownloadedCoverManifestCover = {
            path, volume in
            SableLibraryDownloadedCoverManifestCover(
                language: "en",
                source: SableLibraryCoverSource.bookWalkerGlobal.displayName,
                role: .normal,
                status: "selected_downloaded",
                path: path,
                width: 1_200,
                height: 1_800,
                bytes: nil,
                url: "https://example.invalid/volume-\(volume).png",
                providerURL: "https://global.bookwalker.jp/volume-\(volume)",
                editionNote: nil,
                providerTitle: "Similar Numbered Series Volume \(volume)",
                providerSeriesID: "similar-numbered-series",
                providerItemID: "volume-\(volume)",
                providerVolume: Double(volume),
                providerMediaType: "novel"
            )
        }
        let manifest = SableLibraryDownloadedCoverManifest(
            generatedAt: "2026-07-23T00:00:00Z",
            seriesTitle: "Similar Numbered Series",
            mediaType: "lightNovel",
            entries: [
                .init(
                    bookFile: "Similar Numbered Series - Vol 01.epub",
                    volume: 1,
                    covers: [makeCover(firstPath, 1)]
                ),
                .init(
                    bookFile: "Similar Numbered Series - Vol 02.epub",
                    volume: 2,
                    covers: [makeCover(secondPath, 2)]
                )
            ],
            skipped: []
        )
        let manifestURL = folder.appendingPathComponent("_covers/cover-manifest.json")
        try JSONEncoder().encode(manifest).write(to: manifestURL)
        let request = SableLibraryCoverDownloadRequest(
            seriesTitle: "Similar Numbered Series",
            mediaType: "lightNovel",
            queryTitles: ["Similar Numbered Series"],
            localBooks: [
                .init(fileName: "Similar Numbered Series - Vol 01.epub", volumeNumber: 1),
                .init(fileName: "Similar Numbered Series - Vol 02.epub", volumeNumber: 2)
            ],
            languages: [],
            includeSpecials: false
        )

        let result = try await SableLibraryCoverDownloadService().downloadCovers(
            request: request,
            folder: folder,
            root: root
        )

        XCTAssertEqual(result.manifest.entries.count, 2)
        XCTAssertEqual(
            Set(result.manifest.entries.compactMap(\.volume)),
            Set([1, 2])
        )
        XCTAssertFalse(result.skipped.contains { $0.contains("visually equivalent") })
        XCTAssertTrue(fileManager.fileExists(atPath: folder.appendingPathComponent(firstPath).path))
        XCTAssertTrue(fileManager.fileExists(atPath: folder.appendingPathComponent(secondPath).path))
    }

    func testCoverRerunKeepsOneBestNormalForVisuallyEquivalentProviderImages() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("SableVisualCover-\(UUID().uuidString)", isDirectory: true)
        let folder = root.appendingPathComponent("Visual Cover Series", isDirectory: true)
        let amazonPath = "_covers/en/Visual Cover Series - Vol 01 - Cover EN [Amazon].png"
        let bookWalkerPath = "_covers/en/Visual Cover Series - Vol 01 - Cover EN [BookWalker Global].png"
        let specialPath = "_covers/en/Visual Cover Series - Vol 01 - Special 01 EN [Amazon].png"
        let pixel = try XCTUnwrap(
            Data(
                base64Encoded:
                    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
            )
        )
        for (relativePath, suffix) in [
            (amazonPath, "amazon"),
            (bookWalkerPath, "bookwalker"),
            (specialPath, "special")
        ] {
            let url = folder.appendingPathComponent(relativePath)
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            var data = pixel
            data.append(Data(suffix.utf8))
            try data.write(to: url)
        }
        defer { try? fileManager.removeItem(at: root) }

        let makeCover: (
            String,
            String,
            SableLibraryProviderCoverRole,
            Int,
            Int
        ) -> SableLibraryDownloadedCoverManifestCover = {
            path, source, role, width, height in
            SableLibraryDownloadedCoverManifestCover(
                language: "en",
                source: source,
                role: role,
                status: role == .normal ? "selected_downloaded" : "extra_downloaded",
                path: path,
                width: width,
                height: height,
                bytes: nil,
                url: nil,
                providerURL: nil,
                editionNote: role == .normal ? nil : "Audiobook",
                providerTitle: "Visual Cover Series Volume 1",
                providerSeriesID: "visual-cover-series",
                providerItemID: nil,
                providerVolume: 1,
                providerMediaType: role == .normal ? "novel" : "audiobook"
            )
        }
        let manifest = SableLibraryDownloadedCoverManifest(
            generatedAt: "2026-07-23T00:00:00Z",
            seriesTitle: "Visual Cover Series",
            mediaType: "lightNovel",
            entries: [
                .init(
                    bookFile: "Visual Cover Series - Vol 01.epub",
                    volume: 1,
                    covers: [
                        makeCover(amazonPath, "Amazon", .normal, 1_000, 1_500),
                        makeCover(
                            bookWalkerPath,
                            "BookWalker Global",
                            .normal,
                            1_400,
                            2_100
                        ),
                        makeCover(specialPath, "Amazon", .specialEdition, 2_000, 3_000)
                    ]
                )
            ],
            skipped: []
        )
        let manifestURL = folder.appendingPathComponent("_covers/cover-manifest.json")
        try JSONEncoder().encode(manifest).write(to: manifestURL)
        let request = SableLibraryCoverDownloadRequest(
            seriesTitle: "Visual Cover Series",
            mediaType: "lightNovel",
            queryTitles: ["Visual Cover Series"],
            localBooks: [
                .init(fileName: "Visual Cover Series - Vol 01.epub", volumeNumber: 1)
            ],
            languages: [],
            includeSpecials: true
        )

        let result = try await SableLibraryCoverDownloadService().downloadCovers(
            request: request,
            folder: folder,
            root: root
        )

        let covers = try XCTUnwrap(result.manifest.entries.first?.covers)
        XCTAssertEqual(covers.map(\.path), [bookWalkerPath])
        XCTAssertEqual(covers.first?.role, .normal)
        XCTAssertTrue(result.skipped.contains { $0.contains("Local safety pass removed 2") })
    }

    func testCoverDuplicateAuditPrefersVerifiedEvidenceOverMorePixels() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("SableEvidenceCover-\(UUID().uuidString)", isDirectory: true)
        let folder = root.appendingPathComponent("Evidence First Series", isDirectory: true)
        let amazonPath = "_covers/en/Evidence First Series - Vol 01 - Cover EN [Amazon].jpg"
        let bookWalkerPath =
            "_covers/en/Evidence First Series - Vol 01 - Cover EN [BookWalker Global].jpg"
        for path in [amazonPath, bookWalkerPath] {
            let url = folder.appendingPathComponent(path)
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("same-cover-art".utf8).write(to: url)
        }
        defer { try? fileManager.removeItem(at: root) }

        let verified = SableLibraryDownloadedCoverManifestCover(
            language: "en",
            source: SableLibraryCoverSource.amazon.displayName,
            role: .normal,
            status: "selected_downloaded",
            path: amazonPath,
            width: 1_000,
            height: 1_500,
            bytes: nil,
            url: "https://example.invalid/amazon.jpg",
            providerURL: "https://amazon.com/dp/verified",
            editionNote: nil,
            providerTitle: "Evidence First Series Volume 1",
            providerSeriesID: "verified-series",
            providerItemID: "verified-volume-1",
            providerVolume: 1,
            providerMediaType: "novel"
        )
        let incomplete = SableLibraryDownloadedCoverManifestCover(
            language: "en",
            source: SableLibraryCoverSource.bookWalkerGlobal.displayName,
            role: .normal,
            status: "selected_recovered_best_quality",
            path: bookWalkerPath,
            width: 1_600,
            height: 2_400,
            bytes: nil,
            url: "https://example.invalid/bookwalker.jpg",
            providerURL: nil,
            editionNote: nil,
            providerTitle: "Evidence First Series Volume 1",
            providerSeriesID: nil,
            providerItemID: nil,
            providerVolume: 1,
            providerMediaType: "novel"
        )
        let manifest = SableLibraryDownloadedCoverManifest(
            generatedAt: "2026-07-24T00:00:00Z",
            seriesTitle: "Evidence First Series",
            mediaType: "lightNovel",
            entries: [
                .init(
                    bookFile: "Evidence First Series - Vol 01.epub",
                    volume: 1,
                    covers: [verified, incomplete]
                )
            ],
            skipped: []
        )
        let manifestURL = folder.appendingPathComponent("_covers/cover-manifest.json")
        try JSONEncoder().encode(manifest).write(to: manifestURL)
        let request = SableLibraryCoverDownloadRequest(
            seriesTitle: "Evidence First Series",
            mediaType: "lightNovel",
            queryTitles: ["Evidence First Series"],
            localBooks: [
                .init(fileName: "Evidence First Series - Vol 01.epub", volumeNumber: 1)
            ],
            languages: [],
            includeSpecials: false
        )

        let result = try await SableLibraryCoverDownloadService().downloadCovers(
            request: request,
            folder: folder,
            root: root
        )

        let keptCover = try XCTUnwrap(result.manifest.entries.first?.covers.first)
        XCTAssertEqual(keptCover.path, amazonPath)
        XCTAssertEqual(keptCover.providerItemID, "verified-volume-1")
    }

    func testCoverRetrySanitizesLegacyWrongArcExtrasBeforeProviderLookup() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("SableWrongArcCover-\(UUID().uuidString)", isDirectory: true)
        let folder = root.appendingPathComponent("The Water Magician", isDirectory: true)
        let normalPath = "_covers/en/The Water Magician - Arc 1 Volume 1 - Cover EN [Original EPUB].jpg"
        let wrongPath = "_covers/jp/The Water Magician - Arc 1 Volume 1 - Special 01 JP [BookLive JP].jpg"
        for (path, data) in [
            (normalPath, Data("trusted-normal".utf8)),
            (wrongPath, Data("wrong-later-arc".utf8))
        ] {
            let url = folder.appendingPathComponent(path)
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url)
        }
        defer { try? fileManager.removeItem(at: root) }

        let manifest = SableLibraryDownloadedCoverManifest(
            generatedAt: "2026-07-23T00:00:00Z",
            seriesTitle: "The Water Magician",
            mediaType: "lightNovel",
            entries: [
                .init(
                    bookFile: "The Water Magician - Arc 1 Volume 1.epub",
                    volume: 1,
                    covers: [
                        .init(
                            language: "en",
                            source: "Original EPUB",
                            role: .normal,
                            status: "selected_restored_original",
                            path: normalPath,
                            width: 1_200,
                            height: 1_800,
                            bytes: 14,
                            url: nil,
                            providerURL: nil,
                            editionNote: "Authentic English cover restored from the local EPUB"
                        ),
                        .init(
                            language: "jp",
                            source: SableLibraryCoverSource.bookLiveJP.displayName,
                            role: .specialEdition,
                            status: "extra_downloaded",
                            path: wrongPath,
                            width: 1_200,
                            height: 1_800,
                            bytes: 15,
                            url: "https://example.invalid/wrong.jpg",
                            providerURL: "https://booklive.jp/example",
                            editionNote: "水属性の魔法使い 第三部 東方諸国編1"
                        )
                    ]
                )
            ],
            skipped: []
        )
        let manifestURL = folder.appendingPathComponent("_covers/cover-manifest.json")
        try JSONEncoder().encode(manifest).write(to: manifestURL)
        let request = SableLibraryCoverDownloadRequest(
            seriesTitle: "The Water Magician",
            mediaType: "lightNovel",
            queryTitles: ["The Water Magician"],
            localBooks: [
                .init(
                    fileName: "The Water Magician - Arc 1 Volume 1.epub",
                    volumeNumber: 1
                )
            ],
            languages: [],
            includeSpecials: false,
            refreshExistingNormalCovers: true
        )

        let result = try await SableLibraryCoverDownloadService().downloadCovers(
            request: request,
            folder: folder,
            root: root
        )

        let covers = try XCTUnwrap(result.manifest.entries.first?.covers)
        XCTAssertEqual(covers.map(\.path), [normalPath])
        XCTAssertTrue(result.skipped.contains { $0.contains("Local safety pass removed 1") })
        XCTAssertFalse(fileManager.fileExists(atPath: folder.appendingPathComponent(wrongPath).path))
        let quarantineRoot = root
            .appendingPathComponent("_Sable's Library Reports/Cover Quarantine")
        XCTAssertFalse(fileManager.fileExists(atPath: quarantineRoot.path))
        XCTAssertTrue(
            try fileManager.contentsOfDirectory(
                at: manifestURL.deletingLastPathComponent(),
                includingPropertiesForKeys: nil
            )
            .filter { $0.lastPathComponent.hasPrefix("cover-manifest.backup-") }
            .isEmpty
        )
        let savedManifest = try JSONDecoder().decode(
            SableLibraryDownloadedCoverManifest.self,
            from: Data(contentsOf: manifestURL)
        )
        XCTAssertEqual(savedManifest.entries.first?.covers.map(\.path), [normalPath])
    }

    func testCoverRetryReusesEvidenceBackedPreservedNormalCover() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("SablePreservedCover-\(UUID().uuidString)", isDirectory: true)
        let folder = root.appendingPathComponent("旧版シリーズ", isDirectory: true)
        let coverPath = "_covers/jp/旧版シリーズ - Vol 01 - Cover JP [BookLive JP].jpg"
        let coverURL = folder.appendingPathComponent(coverPath)
        try fileManager.createDirectory(
            at: coverURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("trusted-preserved-cover".utf8).write(to: coverURL)
        defer { try? fileManager.removeItem(at: root) }

        let manifest = SableLibraryDownloadedCoverManifest(
            generatedAt: "2026-07-23T00:00:00Z",
            seriesTitle: "旧版シリーズ",
            mediaType: "lightNovel",
            entries: [
                .init(
                    bookFile: "旧版シリーズ - Vol 01.epub",
                    volume: 1,
                    covers: [
                        .init(
                            language: "jp",
                            source: SableLibraryCoverSource.bookLiveJP.displayName,
                            role: .normal,
                            status: "preserved_previous_normal",
                            path: coverPath,
                            width: 1_200,
                            height: 1_800,
                            bytes: 23,
                            url: "https://example.invalid/cover.jpg",
                            providerURL: "https://booklive.jp/product/index/title_id/123/vol_no/001",
                            editionNote: nil,
                            providerTitle: "旧版シリーズ",
                            providerSeriesID: "123",
                            providerItemID: "1",
                            providerVolume: 1,
                            providerMediaType: "lightNovel"
                        )
                    ]
                )
            ],
            skipped: []
        )
        let manifestURL = folder.appendingPathComponent("_covers/cover-manifest.json")
        try JSONEncoder().encode(manifest).write(to: manifestURL)
        let request = SableLibraryCoverDownloadRequest(
            seriesTitle: "旧版シリーズ",
            mediaType: "lightNovel",
            queryTitles: ["旧版シリーズ"],
            localBooks: [
                .init(fileName: "旧版シリーズ - Vol 01.epub", volumeNumber: 1)
            ],
            languages: ["jp"],
            includeSpecials: false
        )

        let result = try await SableLibraryCoverDownloadService().downloadCovers(
            request: request,
            folder: folder,
            root: root
        )

        XCTAssertEqual(result.downloadedCount, 0)
        XCTAssertEqual(result.reusedCount, 1)
        XCTAssertEqual(result.manifest.entries.first?.covers.map(\.path), [coverPath])
    }

    func testCoverRetryRejectsPreservedBookLiveCoverWithConflictingURLVolume() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("SablePreservedVolume-\(UUID().uuidString)", isDirectory: true)
        let folder = root.appendingPathComponent("旧版シリーズ", isDirectory: true)
        let trustedPath = "_covers/en/旧版シリーズ - Vol 02 - Cover EN [Original EPUB].jpg"
        let wrongPath = "_covers/jp/旧版シリーズ - Vol 02 - Cover JP [BookLive JP].jpg"
        for (relativePath, contents) in [
            (trustedPath, "trusted-original"),
            (wrongPath, "wrong-storefront-volume")
        ] {
            let url = folder.appendingPathComponent(relativePath)
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(contents.utf8).write(to: url)
        }
        defer { try? fileManager.removeItem(at: root) }

        let manifest = SableLibraryDownloadedCoverManifest(
            generatedAt: "2026-07-23T00:00:00Z",
            seriesTitle: "旧版シリーズ",
            mediaType: "lightNovel",
            entries: [
                .init(
                    bookFile: "旧版シリーズ - Vol 02.epub",
                    volume: 2,
                    covers: [
                        .init(
                            language: "en",
                            source: "Original EPUB",
                            role: .normal,
                            status: "selected_restored_original",
                            path: trustedPath,
                            width: 1_200,
                            height: 1_800,
                            bytes: 16,
                            url: nil,
                            providerURL: nil,
                            editionNote: "Authentic cover restored from the local EPUB"
                        ),
                        .init(
                            language: "jp",
                            source: SableLibraryCoverSource.bookLiveJP.displayName,
                            role: .normal,
                            status: "preserved_previous_normal",
                            path: wrongPath,
                            width: 1_200,
                            height: 1_800,
                            bytes: 23,
                            url: "https://example.invalid/wrong.jpg",
                            providerURL: "https://booklive.jp/product/index/title_id/123/vol_no/003",
                            editionNote: nil,
                            providerTitle: "旧版シリーズ",
                            providerSeriesID: "123",
                            providerItemID: "3",
                            providerVolume: 2,
                            providerMediaType: "lightNovel"
                        )
                    ]
                )
            ],
            skipped: []
        )
        let manifestURL = folder.appendingPathComponent("_covers/cover-manifest.json")
        try JSONEncoder().encode(manifest).write(to: manifestURL)
        let request = SableLibraryCoverDownloadRequest(
            seriesTitle: "旧版シリーズ",
            mediaType: "lightNovel",
            queryTitles: ["旧版シリーズ"],
            localBooks: [
                .init(fileName: "旧版シリーズ - Vol 02.epub", volumeNumber: 2)
            ],
            languages: [],
            includeSpecials: false,
            refreshExistingNormalCovers: true
        )

        let result = try await SableLibraryCoverDownloadService().downloadCovers(
            request: request,
            folder: folder,
            root: root
        )

        XCTAssertEqual(result.manifest.entries.first?.covers.map(\.path), [trustedPath])
        XCTAssertTrue(result.skipped.contains { $0.contains("Local safety pass removed 1") })
        XCTAssertFalse(fileManager.fileExists(atPath: folder.appendingPathComponent(wrongPath).path))
        let quarantineRoot = root
            .appendingPathComponent("_Sable's Library Reports/Cover Quarantine")
        XCTAssertFalse(fileManager.fileExists(atPath: quarantineRoot.path))
    }

    func testLiveCoverDownloadSmokeUsesFreshSampleSeriesEvidence() async throws {
        let networkTestMarker = URL(fileURLWithPath: "/tmp/SableRunNetworkCoverTests")
        let markerExists = FileManager.default.fileExists(
            atPath: networkTestMarker.path(percentEncoded: false)
        )
        guard ProcessInfo.processInfo.environment["SABLE_RUN_NETWORK_TESTS"] == "1" || markerExists else {
            throw XCTSkip("Set SABLE_RUN_NETWORK_TESTS=1 or create the temporary SableRunNetworkCoverTests marker to exercise live cover providers.")
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SableCoverNetworkSmoke-\(UUID().uuidString)", isDirectory: true)
        let folder = root.appendingPathComponent("The Frontier Lord Begins With Zero Subjects", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let request = SableLibraryCoverDownloadRequest(
            seriesTitle: "The Frontier Lord Begins With Zero Subjects",
            mediaType: "lightNovel",
            queryTitles: [
                "領民0人スタートの辺境領主様",
                "The Frontier Lord Begins With Zero Subjects"
            ],
            isbn13: ["9781718331327"],
            mangaBakaSeriesID: "85023",
            localBooks: [
                SableLibraryCoverDownloadLocalBook(
                    fileName: "The Frontier Lord Begins With Zero Subjects - Vol 01.epub",
                    volumeNumber: 1
                )
            ],
            languages: ["jp", "en"],
            includeSpecials: false
        )

        let amazonRows = try await SableLibraryBigBookCoversClient().search(
            query: "9781718331327",
            provider: .amazon
        )
        let amazonSeries = try XCTUnwrap(
            amazonRows.first {
                $0.id == "B0CLKWGDS4" && $0.type == "series"
            }
        )
        let amazonBooks = try await SableLibraryBigBookCoversClient().books(
            itemID: amazonSeries.id,
            itemType: amazonSeries.type ?? "series",
            provider: .amazon
        )
        XCTAssertGreaterThanOrEqual(amazonBooks.count, 14)
        XCTAssertEqual(amazonBooks.first?.id, "B0CJF9965P")

        let result = try await SableLibraryCoverDownloadService().downloadCovers(
            request: request,
            folder: folder,
            root: root
        )
        let entry = try XCTUnwrap(result.manifest.entries.first)
        let normalCovers = entry.covers.filter { $0.role == .normal }

        XCTAssertEqual(Set(normalCovers.map(\.language)), Set(["jp", "en"]))
        XCTAssertGreaterThanOrEqual(result.downloadedCount, 2)
        for cover in normalCovers {
            let width = try XCTUnwrap(cover.width)
            let height = try XCTUnwrap(cover.height)
            XCTAssertTrue(
                SableLibraryCoverDownloadPlanner.coverDimensionsAreUsable(width: width, height: height),
                "\(cover.language) cover was only \(width) x \(height)"
            )
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: folder.appendingPathComponent(cover.path).path(percentEncoded: false)
                )
            )
        }
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: folder
                    .appendingPathComponent("_covers/cover-manifest.json")
                    .path(percentEncoded: false)
            )
        )
    }

    func testLiveSlimeDukeCoverSmokeRejectsMangaAndEnglishEditionRows() async throws {
        let networkTestMarker = URL(fileURLWithPath: "/tmp/SableRunNetworkCoverTests")
        let markerExists = FileManager.default.fileExists(
            atPath: networkTestMarker.path(percentEncoded: false)
        )
        guard ProcessInfo.processInfo.environment["SABLE_RUN_NETWORK_TESTS"] == "1" || markerExists else {
            throw XCTSkip("Enable the temporary network-test marker to exercise live cover providers.")
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SableSlimeDukeCoverSmoke-\(UUID().uuidString)", isDirectory: true)
        let folder = root.appendingPathComponent("Slime Duke", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let request = SableLibraryCoverDownloadRequest(
            seriesTitle: "A Surprisingly Happy Engagement for the Slime Duke and the Fallen Noble Lady",
            mediaType: "lightNovel",
            queryTitles: [
                "スライム大公と没落令嬢のあんがい幸せな婚約",
                "A Surprisingly Happy Engagement for the Slime Duke and the Fallen Noble Lady"
            ],
            mangaBakaSeriesID: "85255",
            localBooks: [
                .init(fileName: "Slime Duke - Vol 01.epub", volumeNumber: 1),
                .init(fileName: "Slime Duke - Vol 02.epub", volumeNumber: 2)
            ],
            languages: ["jp"],
            includeSpecials: true
        )

        let result = try await SableLibraryCoverDownloadService().downloadCovers(
            request: request,
            folder: folder,
            root: root
        )
        XCTAssertEqual(result.manifest.entries.count, 2)
        for entry in result.manifest.entries {
            let normal = try XCTUnwrap(entry.covers.first { $0.role == .normal && $0.language == "jp" })
            let providerMediaType = try XCTUnwrap(normal.providerMediaType)
            XCTAssertTrue(
                SableLibraryCoverDownloadPlanner.providerMediaTypeIsCompatible(
                    providerMediaType,
                    isCompatibleWith: "lightNovel"
                ),
                "Storefront classified the selected row as \(providerMediaType)."
            )
            XCTAssertFalse(
                normal.providerTitle?.localizedCaseInsensitiveContains("English Edition") == true,
                normal.providerTitle ?? "missing provider title"
            )
            XCTAssertEqual(normal.providerVolume, entry.volume)
            for cover in entry.covers {
                if let providerVolume = cover.providerVolume,
                   let localVolume = entry.volume {
                    XCTAssertEqual(
                        providerVolume,
                        localVolume,
                        accuracy: 0.001,
                        cover.providerTitle ?? cover.path
                    )
                }
            }
        }
    }

    func testLiveCoverDownloadTenSeriesSample() async throws {
        let networkTestMarker = URL(fileURLWithPath: "/tmp/SableRunNetworkCoverTests")
        guard ProcessInfo.processInfo.environment["SABLE_RUN_NETWORK_TESTS"] == "1"
            || FileManager.default.fileExists(atPath: networkTestMarker.path(percentEncoded: false)) else {
            throw XCTSkip("Create the temporary SableRunNetworkCoverTests marker to exercise the ten-series live sample.")
        }

        struct Sample {
            var title: String
            var nativeTitle: String
            var mangaBakaID: String?
            var fileName: String
            var volume: Int
        }

        let samples = [
            Sample(
                title: "The Frontier Lord Begins With Zero Subjects",
                nativeTitle: "領民0人スタートの辺境領主様",
                mangaBakaID: "85023",
                fileName: "The Frontier Lord Begins With Zero Subjects - Vol 01.epub",
                volume: 1
            ),
            Sample(
                title: "Earl and Fairy",
                nativeTitle: "伯爵と妖精",
                mangaBakaID: "83615",
                fileName: "Earl and Fairy- Volume 1.epub",
                volume: 1
            ),
            Sample(
                title: "Ascendance of a Bookworm Part 5",
                nativeTitle: "本好きの下剋上～司書になるためには手段を選んでいられません～第五部「女神の化身」",
                mangaBakaID: "100543",
                fileName: "Ascendance of a Bookworm- I’ll Do Anything to Become a Librarian! Part 5- Avatar of a Goddess Volume 1.epub",
                volume: 1
            ),
            Sample(
                title: "The Lazy Lord Masters the Sword",
                nativeTitle: "怠惰公子、努力の天才になる",
                mangaBakaID: "85614",
                fileName: "The Lazy Lord Masters The Sword (2020).epub",
                volume: 1
            ),
            Sample(
                title: "Welcome to the Outcast’s Restaurant!",
                nativeTitle: "追放者食堂へようこそ！ ～最強パーティーを追放された料理人（Lv.99）は、田舎で念願の冒険者食堂を開きます！～",
                mangaBakaID: "85882",
                fileName: "Welcome to the Diner of the Exiled! Volume 1.epub",
                volume: 1
            ),
            Sample(
                title: "Imperial Reincarnation: I Came, I Saw, I Survived",
                nativeTitle: "転生したら皇帝でした ～生まれながらの皇帝はこの先生き残れるか～",
                mangaBakaID: "99856",
                fileName: "Imperial Reincarnation- I Came, I Saw, I Survived - Volume 1.epub",
                volume: 1
            ),
            Sample(
                title: "A Kiss and a Pair of Handcuffs",
                nativeTitle: "キスと手錠",
                mangaBakaID: "82744",
                fileName: "A Kiss And A Pair Of Handcuffs (2014).epub",
                volume: 1
            ),
            Sample(
                title: "I Became the Secretary of a Hero!",
                nativeTitle: "勇者様の秘書になりました",
                mangaBakaID: "86206",
                fileName: "I Became the Secretary of a Hero! Volume 1.epub",
                volume: 1
            ),
            Sample(
                title: "Combatants Will Be Dispatched!",
                nativeTitle: "戦闘員、派遣します！",
                mangaBakaID: "85134",
                fileName: "Combatants Will Be Dispatched!, Vol. 1.epub",
                volume: 1
            ),
            Sample(
                title: "Romance Revived: An NPC Was the Final Boss's Love",
                nativeTitle: "死に戻ったモブはラスボスの最愛でした",
                mangaBakaID: "349900",
                fileName: "Romance Revived An Npc Was The Final Boss's Love (2023).epub",
                volume: 1
            )
        ]

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SableCoverTenSeries-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var reportRows: [[String: Any]] = []
        var englishHits = 0
        var japaneseHits = 0
        for (index, sample) in samples.enumerated() {
            let folder = root.appendingPathComponent(
                String(format: "%02d - %@", index + 1, sample.title),
                isDirectory: true
            )
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let request = SableLibraryCoverDownloadRequest(
                seriesTitle: sample.title,
                mediaType: "lightNovel",
                queryTitles: [sample.nativeTitle, sample.title],
                mangaBakaSeriesID: sample.mangaBakaID,
                localBooks: [
                    SableLibraryCoverDownloadLocalBook(
                        fileName: sample.fileName,
                        volumeNumber: Double(sample.volume)
                    )
                ],
                languages: ["jp", "en"],
                includeSpecials: false
            )

            do {
                let result = try await SableLibraryCoverDownloadService().downloadCovers(
                    request: request,
                    folder: folder,
                    root: root
                )
                let covers = result.manifest.entries
                    .flatMap(\.covers)
                    .filter { $0.role == .normal }
                let coverRows = covers.map { cover -> [String: Any] in
                    let width = cover.width ?? 0
                    let height = cover.height ?? 0
                    XCTAssertTrue(
                        SableLibraryCoverDownloadPlanner.coverDimensionsAreUsable(
                            width: width,
                            height: height
                        ),
                        "\(sample.title) \(cover.language) cover was only \(width) x \(height)"
                    )
                    XCTAssertTrue(["en", "jp"].contains(cover.language))
                    return [
                        "language": cover.language,
                        "source": cover.source,
                        "width": width,
                        "height": height,
                        "bytes": cover.bytes ?? 0,
                        "path": cover.path
                    ]
                }
                let languages = Set(covers.map(\.language))
                if let englishCover = covers.first(where: { $0.language == "en" }),
                   let japaneseCover = covers.first(where: { $0.language == "jp" }) {
                    let englishData = try Data(
                        contentsOf: folder.appendingPathComponent(englishCover.path)
                    )
                    let japaneseData = try Data(
                        contentsOf: folder.appendingPathComponent(japaneseCover.path)
                    )
                    XCTAssertNotEqual(
                        englishData,
                        japaneseData,
                        "\(sample.title) reused the same image for English and Japanese."
                    )
                }
                englishHits += languages.contains("en") ? 1 : 0
                japaneseHits += languages.contains("jp") ? 1 : 0
                reportRows.append([
                    "title": sample.title,
                    "native_title": sample.nativeTitle,
                    "covers": coverRows,
                    "skipped": result.skipped
                ])
            } catch {
                reportRows.append([
                    "title": sample.title,
                    "native_title": sample.nativeTitle,
                    "covers": [],
                    "error": error.localizedDescription
                ])
            }
        }

        let report: [String: Any] = [
            "sample_count": samples.count,
            "english_hits": englishHits,
            "japanese_hits": japaneseHits,
            "quality_floor": [
                "minimum_width": 800,
                "minimum_height": 1100,
                "minimum_pixels": 850_000
            ],
            "series": reportRows
        ]
        let reportData = try JSONSerialization.data(
            withJSONObject: report,
            options: [.prettyPrinted, .sortedKeys]
        )
        let attachment = XCTAttachment(
            data: reportData,
            uniformTypeIdentifier: "public.json"
        )
        attachment.name = "Sable Cover Ten Series Live Sample"
        attachment.lifetime = .keepAlways
        add(attachment)

        XCTAssertGreaterThanOrEqual(englishHits, 3, "Too few English covers survived matching and quality checks.")
        XCTAssertGreaterThanOrEqual(japaneseHits, 3, "Too few Japanese covers survived matching and quality checks.")
    }

    func testBookWalkerJPMatchingCanFallBackToProviderOrderWhenVolumeNumbersAreMissing() {
        let candidates = [
            SableLibraryProviderCoverCandidate(
                provider: .local,
                providerSeriesID: "42013",
                providerItemID: "a",
                title: "本好きの下剋上 第一部",
                volumeIndex: "1",
                volumeNumber: nil,
                mediaType: "novel",
                language: "jp",
                role: .normal,
                providerType: "novel",
                editionNote: nil,
                imageURL: "https://img.example/1.jpg",
                width: 1200,
                height: 1700,
                byteCount: nil,
                storeURLs: [],
                quality: .usable
            ),
            SableLibraryProviderCoverCandidate(
                provider: .local,
                providerSeriesID: "42013",
                providerItemID: "b",
                title: "本好きの下剋上 第二部",
                volumeIndex: "2",
                volumeNumber: nil,
                mediaType: "novel",
                language: "jp",
                role: .normal,
                providerType: "novel",
                editionNote: nil,
                imageURL: "https://img.example/2.jpg",
                width: 1200,
                height: 1700,
                byteCount: nil,
                storeURLs: [],
                quality: .usable
            )
        ]

        let matched = SableLibraryCoverDownloadPlanner.matchedProviderCovers(
            candidates: candidates,
            source: .bookWalkerJP,
            language: "jp",
            localBooks: [
                SableLibraryCoverDownloadLocalBook(fileName: "Bookworm - Vol 01.epub", volumeNumber: 1),
                SableLibraryCoverDownloadLocalBook(fileName: "Bookworm - Vol 02.epub", volumeNumber: 2)
            ],
            includeSpecials: false
        )

        XCTAssertEqual(matched[1]?.first?.imageURL, "https://img.example/1.jpg")
        XCTAssertEqual(matched[2]?.first?.imageURL, "https://img.example/2.jpg")
    }

    func testBookWalkerJPDoesNotOverrideExplicitVolumeWithProviderOrder() {
        let candidate = SableLibraryProviderCoverCandidate(
            provider: .local,
            providerSeriesID: "42013",
            providerItemID: "wrong-volume",
            title: "本好きの下剋上",
            volumeIndex: "2",
            volumeNumber: 1,
            mediaType: "novel",
            language: "jp",
            role: .normal,
            providerType: "novel",
            editionNote: nil,
            imageURL: "https://img.example/wrong-volume.jpg",
            width: 1_200,
            height: 1_700,
            byteCount: nil,
            storeURLs: [],
            quality: .usable
        )

        let matched = SableLibraryCoverDownloadPlanner.matchedProviderCovers(
            candidates: [candidate],
            source: .bookWalkerJP,
            language: "jp",
            localBooks: [
                SableLibraryCoverDownloadLocalBook(
                    fileName: "Bookworm - Vol 02.epub",
                    volumeNumber: 2
                )
            ],
            includeSpecials: false
        )

        XCTAssertNil(matched[1])
    }

    func testFractionalProviderVolumeDoesNotRoundIntoNeighboringBook() {
        XCTAssertFalse(
            SableLibraryCoverDownloadPlanner.providerVolume(1.5, matches: 2)
        )
        XCTAssertTrue(
            SableLibraryCoverDownloadPlanner.providerVolume(2, matches: 2)
        )
        XCTAssertTrue(
            SableLibraryCoverDownloadPlanner.providerVolume(
                3.1,
                providerTitle: "Agents of the Four Seasons, Vol. 3",
                matches: 3
            )
        )
        XCTAssertTrue(
            SableLibraryCoverDownloadPlanner.providerVolume(
                3.1,
                providerTitle: "The Trials and Tribulations of My Next Life as a Noblewoman",
                source: .mangaBaka,
                matches: 3
            )
        )
        XCTAssertFalse(
            SableLibraryCoverDownloadPlanner.providerVolume(
                3.1,
                providerTitle: "The Trials and Tribulations of My Next Life as a Noblewoman",
                source: .bookWalkerGlobal,
                matches: 3
            )
        )
        XCTAssertFalse(
            SableLibraryCoverDownloadPlanner.providerVolume(
                7.5,
                providerTitle: "Konosuba, Vol. 7",
                matches: 8
            )
        )
        XCTAssertFalse(
            SableLibraryCoverDownloadPlanner.providerVolume(
                8,
                providerTitle: "The Magical Revolution, Vol. 8",
                matches: 8.5
            )
        )
    }

    func testCoverMatchingRejectsSpecialsFromAnotherArcOrVolume() {
        let candidates = [
            SableLibraryProviderCoverCandidate(
                provider: .local,
                providerSeriesID: "892729",
                providerItemID: "correct",
                title: "水属性の魔法使い 第一部 中央諸国編1",
                volumeIndex: nil,
                volumeNumber: nil,
                mediaType: "novel",
                language: "jp",
                role: .specialEdition,
                providerType: "novel",
                editionNote: nil,
                imageURL: "https://img.example/correct.jpg",
                width: 1_200,
                height: 1_700,
                byteCount: nil,
                storeURLs: [],
                quality: .usable
            ),
            SableLibraryProviderCoverCandidate(
                provider: .local,
                providerSeriesID: "892729",
                providerItemID: "wrong-arc",
                title: "水属性の魔法使い 第三部 東方諸国編1",
                volumeIndex: nil,
                volumeNumber: nil,
                mediaType: "novel",
                language: "jp",
                role: .specialEdition,
                providerType: "novel",
                editionNote: nil,
                imageURL: "https://img.example/wrong-arc.jpg",
                width: 1_200,
                height: 1_700,
                byteCount: nil,
                storeURLs: [],
                quality: .usable
            ),
            SableLibraryProviderCoverCandidate(
                provider: .local,
                providerSeriesID: "892729",
                providerItemID: "wrong-volume",
                title: "水属性の魔法使い 第一部 中央諸国編2",
                volumeIndex: nil,
                volumeNumber: nil,
                mediaType: "novel",
                language: "jp",
                role: .specialEdition,
                providerType: "novel",
                editionNote: nil,
                imageURL: "https://img.example/wrong-volume.jpg",
                width: 1_200,
                height: 1_700,
                byteCount: nil,
                storeURLs: [],
                quality: .usable
            )
        ]

        let matched = SableLibraryCoverDownloadPlanner.matchedProviderCovers(
            candidates: candidates,
            source: .bookLiveJP,
            language: "jp",
            localBooks: [
                SableLibraryCoverDownloadLocalBook(
                    fileName: "The Water Magician - Arc 1 Volume 1.epub",
                    volumeNumber: 1
                )
            ],
            includeSpecials: true
        )

        XCTAssertEqual(matched[1]?.map(\.providerItemID), ["correct"])
    }

    func testCoverMatchingReadsFullWidthVolumeFromJapaneseSpecialEditionNote() {
        let candidate = SableLibraryProviderCoverCandidate(
            provider: .local,
            providerSeriesID: "83946",
            providerItemID: "volume-3-special",
            title: "異世界転生の冒険者",
            volumeIndex: nil,
            volumeNumber: nil,
            mediaType: "novel",
            language: "jp",
            role: .specialEdition,
            providerType: "novel",
            editionNote: "異世界転生の冒険者３【電子版限定書き下ろしSS付】",
            imageURL: "https://img.example/volume-3-special.jpg",
            width: 1_800,
            height: 2_560,
            byteCount: nil,
            storeURLs: [],
            quality: .highResolution
        )

        let matched = SableLibraryCoverDownloadPlanner.matchedProviderCovers(
            candidates: [candidate],
            source: .bookWalkerJP,
            language: "jp",
            localBooks: [
                SableLibraryCoverDownloadLocalBook(
                    fileName: "Isekai Tensei- Recruited to Another World Volume 2.epub",
                    volumeNumber: 2
                ),
                SableLibraryCoverDownloadLocalBook(
                    fileName: "Isekai Tensei- Recruited to Another World Volume 3.epub",
                    volumeNumber: 3
                )
            ],
            includeSpecials: true
        )

        XCTAssertNil(matched[1])
        XCTAssertEqual(matched[2]?.map(\.providerItemID), ["volume-3-special"])
    }

    func testCoverSearchPrefersFullNativeTitlesAndDemotesSpinOffRows() throws {
        let queries = SableLibraryCoverDownloadPlanner.orderedQueries(
            ["転スラ", "転生したらスライムだった件"],
            language: "jp"
        )
        let rows = [
            SableLibraryBigBookCoversSeriesCandidate(
                provider: .bookLiveJP,
                id: "spin-off",
                title: "転スラ日記　転生したらスライムだった件",
                url: nil,
                type: "series",
                bookType: nil,
                thumbnailURL: nil
            ),
            SableLibraryBigBookCoversSeriesCandidate(
                provider: .bookLiveJP,
                id: "normal",
                title: "転生したらスライムだった件",
                url: nil,
                type: "series",
                bookType: nil,
                thumbnailURL: nil
            )
        ]

        let best = try XCTUnwrap(SableLibraryCoverDownloadPlanner.bestSeriesCandidate(
            for: "転生したらスライムだった件",
            in: rows,
            mediaType: "lightNovel"
        ))

        XCTAssertEqual(queries.first, "転生したらスライムだった件")
        XCTAssertEqual(best.id, "normal")
    }

    func testCoverSearchRejectsSiblingEditionsBeforeMatchingVolumes() throws {
        let rows = [
            SableLibraryBigBookCoversSeriesCandidate(
                provider: .bookWalkerGlobal,
                id: "fanbook",
                title: "Ascendance of a Bookworm: Fanbook",
                url: nil,
                type: "series",
                bookType: "novel",
                thumbnailURL: nil
            ),
            SableLibraryBigBookCoversSeriesCandidate(
                provider: .bookWalkerGlobal,
                id: "part-5",
                title: "Ascendance of a Bookworm: Part 5",
                url: nil,
                type: "series",
                bookType: "novel",
                thumbnailURL: nil
            )
        ]

        let best = try XCTUnwrap(SableLibraryCoverDownloadPlanner.bestSeriesCandidate(
            for: "Ascendance of a Bookworm",
            requestedSeriesTitle: "Ascendance of a Bookworm Part 5",
            in: rows,
            mediaType: "lightNovel"
        ))

        XCTAssertEqual(best.id, "part-5")
        XCTAssertFalse(SableLibraryCoverDownloadPlanner.providerTitle(
            "Ascendance of a Bookworm: Fanbook 2",
            belongsTo: "Ascendance of a Bookworm Part 5"
        ))
        XCTAssertTrue(SableLibraryCoverDownloadPlanner.providerTitle(
            "Ascendance of a Bookworm: Part 5: Avatar of a Goddess Volume 2",
            belongsTo: "Ascendance of a Bookworm Part 5"
        ))
        XCTAssertTrue(SableLibraryCoverDownloadPlanner.providerTitle(
            "本好きの下剋上 第五部 女神の化身 2",
            belongsTo: "Ascendance of a Bookworm Part 5"
        ))
        XCTAssertFalse(SableLibraryCoverDownloadPlanner.providerTitle(
            "本好きの下剋上 第二部 2",
            belongsTo: "Ascendance of a Bookworm Part 5"
        ))
    }

    func testCoverSearchDoesNotCollapseSequelsAndSpinoffsIntoParentSeries() {
        XCTAssertFalse(SableLibraryCoverDownloadPlanner.providerTitle(
            "Tower",
            belongsTo: "My Very Own Tower Strategy Guide"
        ))
        XCTAssertFalse(SableLibraryCoverDownloadPlanner.providerTitle(
            "SEX DELIVERY",
            belongsTo: "Delivery Cupid"
        ))
        XCTAssertFalse(SableLibraryCoverDownloadPlanner.providerTitle(
            "Ai No Kusabi Fan Fiction: Journey in the Universe",
            belongsTo: "Ai no Kusabi"
        ))
        XCTAssertFalse(SableLibraryCoverDownloadPlanner.providerTitle(
            "KONOSUBA: God's Blessing on This Wonderful World!",
            belongsTo: "KONOSUBA: God's Blessing on This Wonderful World! Fantastic Days"
        ))
        XCTAssertFalse(SableLibraryCoverDownloadPlanner.providerTitle(
            "Secrets of the Silent Witch",
            belongsTo: "Secrets of the Silent Witch Another: Rise of the Barrier Mage"
        ))
        XCTAssertFalse(SableLibraryCoverDownloadPlanner.providerTitle(
            "Arifureta: From Commonplace to World's Strongest",
            belongsTo: "Arifureta: From Commonplace to World's Strongest Short Stories"
        ))
        XCTAssertFalse(SableLibraryCoverDownloadPlanner.providerTitle(
            "Observation Records of My Fiancee: The Misadventures of a Self-Proclaimed Villainess",
            belongsTo: "Observation Records of My Wife"
        ))
        XCTAssertFalse(SableLibraryCoverDownloadPlanner.providerTitle(
            "I'm the Villainess, So I'm Taming the Final Boss",
            belongsTo: "I'm Not the Final Boss' Lover"
        ))
        XCTAssertFalse(SableLibraryCoverDownloadPlanner.providerSeriesTitle(
            "G-Boys, Be Ambitious 2",
            belongsTo: "Boys, Be Ambitious!"
        ))
        XCTAssertTrue(SableLibraryCoverDownloadPlanner.providerSeriesTitle(
            "The Water Magician",
            belongsTo: "Water Magician"
        ))
    }

    func testCoverIdentityPrefersSameScriptAliasesWhenAvailable() {
        let aliases = [
            "Hell Mode: The Hardcore Gamer Dominates in Another World with Garbage Balancing",
            "Hell Mode: Volume 3",
            "ヘルモード"
        ]

        XCTAssertTrue(SableLibraryCoverDownloadPlanner.providerTitle(
            "Hell Mode: Volume 3",
            belongsToAny: aliases
        ))
        XCTAssertTrue(SableLibraryCoverDownloadPlanner.providerTitle(
            "ヘルモード ～やり込み好きのゲーマーは廃設定の異世界で無双する～３",
            belongsToAny: aliases
        ))
        XCTAssertTrue(SableLibraryCoverDownloadPlanner.providerTitle(
            "【電子版限定特典付き】リピート・ヴァイス1～悪役貴族は死にたくないので四天王になるのをやめました～",
            belongsToAny: [
                "Repeated Vice: I Refuse to Be Important Enough to Die",
                "リピート・ヴァイス ～悪役貴族は死にたくないので四天王になるのをやめました～"
            ]
        ))
        XCTAssertTrue(SableLibraryCoverDownloadPlanner.providerTitle(
            "佐々木とピーちゃん ３ 異世界ファンタジーなら異能バトルも魔法少女もデスゲームも敵ではありません",
            belongsToAny: ["Sasaki and Peeps", "佐々木とピーちゃん"]
        ))
        XCTAssertFalse(SableLibraryCoverDownloadPlanner.providerTitle(
            "Hardcore Gaming 101 Digest Vol. 3: The Guide to Retro Horror",
            belongsToAny: aliases
        ))
        XCTAssertTrue(SableLibraryCoverDownloadPlanner.providerTitleMatchesLocalSeriesStem(
            "Hell Mode: Volume 3",
            localBookTitle: "Hell Mode, Vol. 3- The Hardcore Gamer Dominates in Another World with Garbage Balancing.epub"
        ))
        XCTAssertFalse(SableLibraryCoverDownloadPlanner.providerTitleMatchesLocalSeriesStem(
            "Hardcore Gaming 101 Digest Vol. 3: The Guide to Retro Horror",
            localBookTitle: "Hell Mode, Vol. 3- The Hardcore Gamer Dominates in Another World with Garbage Balancing.epub"
        ))
        XCTAssertTrue(SableLibraryCoverDownloadPlanner.providerTitleMatchesLocalSeriesStem(
            "Arifureta: From Commonplace to World's Strongest Volume 3",
            localBookTitle: "Arifureta Volume 3.epub"
        ))
        XCTAssertTrue(SableLibraryCoverDownloadPlanner.providerTitleMatchesLocalSeriesStem(
            "Ascendance of a Bookworm: Part 2",
            localBookTitle: "Ascendance of a Bookworm- I’ll Do Anything to Become a Librarian! Part 2- Apprentice Shrine Maiden Volume 1.epub"
        ))
        XCTAssertFalse(SableLibraryCoverDownloadPlanner.providerTitleMatchesLocalSeriesStem(
            "Ascendance of a Bookworm: Part 3",
            localBookTitle: "Ascendance of a Bookworm- I’ll Do Anything to Become a Librarian! Part 2- Apprentice Shrine Maiden Volume 1.epub"
        ))
        XCTAssertTrue(SableLibraryCoverDownloadPlanner.providerTitleMatchesLocalSeriesStem(
            "The Water Magician",
            localBookTitle: "The Water Magician- Arc 1 Volume 2.epub"
        ))
        XCTAssertFalse(SableLibraryCoverDownloadPlanner.providerTitle(
            "水属性の魔法使いMAGAZINE",
            belongsTo: "水属性の魔法使い"
        ))
    }

    func testMangaBakaCoverIdentityRequiresExactSeriesAndMediaType() {
        let titles = [
            "Ascendance of a Bookworm: Part 5",
            "本好きの下剋上～司書になるためには手段を選んでいられません～第五部「女神の化身」"
        ]

        XCTAssertTrue(SableLibraryCoverDownloadPlanner.mangaBakaSeriesIdentityIsCompatible(
            titles: titles,
            providerMediaType: "novel",
            requestedSeriesTitle: "Ascendance of a Bookworm Part 5",
            requestedMediaType: "lightNovel"
        ))
        XCTAssertFalse(SableLibraryCoverDownloadPlanner.mangaBakaSeriesIdentityIsCompatible(
            titles: titles,
            providerMediaType: "manga",
            requestedSeriesTitle: "Ascendance of a Bookworm Part 5",
            requestedMediaType: "lightNovel"
        ))
        XCTAssertFalse(SableLibraryCoverDownloadPlanner.mangaBakaSeriesIdentityIsCompatible(
            titles: titles,
            providerMediaType: "novel",
            requestedSeriesTitle: "Ascendance of a Bookworm Part 2",
            requestedMediaType: "lightNovel"
        ))
    }

    func testProviderParsersNormalizeAniListOpenLibraryAndTMDBPayloads() throws {
        let anilist = [
            "id": 154587,
            "idMal": 52991,
            "title": [
                "romaji": "Sousou no Frieren",
                "english": "Frieren: Beyond Journey's End",
                "native": "Sousou no Frieren JP"
            ],
            "format": "TV",
            "seasonYear": 2023,
            "description": "A mage looks back.",
            "genres": ["Adventure", "Fantasy"],
            "tags": [
                ["name": "Time Travel"],
                ["name": "Magic"]
            ],
            "status": "FINISHED",
            "isAdult": false,
            "studios": [
                "nodes": [
                    ["name": "Madhouse"]
                ]
            ]
        ] as [String: Any]
        let openLibrary = [
            "docs": [
                [
                    "key": "/works/OL39406770W",
                    "title": "7th Time Loop Vol. 1",
                    "first_publish_year": 2022,
                    "isbn": ["9781638583936", "0-306-40615-2"],
                    "author_name": ["Touko Amekawa"],
                    "publisher": ["Seven Seas Siren"],
                    "language": ["eng"],
                    "subject": [
                        "genre:fantasy",
                        "genre:romance",
                        "form:light novel",
                        "series:7th Time Loop (light novel)"
                    ]
                ]
            ]
        ] as [String: Any]
        let tmdb = [
            "results": [
                [
                    "id": 209867,
                    "media_type": "tv",
                    "name": "Frieren: Beyond Journey's End",
                    "first_air_date": "2023-09-29"
                ]
            ]
        ] as [String: Any]
        let tvmaze = [
            "id": 69956,
            "name": "Frieren: Beyond Journey's End",
            "premiered": "2023-09-29",
            "type": "Animation",
            "status": "Running",
            "genres": ["Adventure"],
            "externals": [
                "thetvdb": 424536,
                "imdb": "tt22248376"
            ]
        ] as [String: Any]
        let wikidata = [
            "results": [
                "bindings": [
                    [
                        "item": ["value": "http://www.wikidata.org/entity/Q118080048"],
                        "itemLabel": ["value": "Frieren: Beyond Journey's End"],
                        "startYear": ["value": "2023"],
                        "tmdbTV": ["value": "209867"],
                        "tvdb": ["value": "424536"],
                        "imdb": ["value": "tt22248376"],
                        "tvSeriesType": ["value": "tv"]
                    ]
                ]
            ]
        ] as [String: Any]

        let aniListCandidate = try XCTUnwrap(SableLibraryProviderCandidateParser.aniListCandidate(from: anilist))
        let openLibraryCandidate = try XCTUnwrap(SableLibraryProviderCandidateParser.openLibraryCandidates(from: openLibrary).first)
        let tmdbCandidate = try XCTUnwrap(SableLibraryProviderCandidateParser.tmdbCandidates(from: tmdb).first)
        let tvmazeCandidate = try XCTUnwrap(SableLibraryProviderCandidateParser.tvmazeCandidate(from: tvmaze))
        let wikidataIDs = SableLibraryProviderCandidateParser.wikidataSourceIDs(from: wikidata)
        let wikidataCandidate = try XCTUnwrap(SableLibraryProviderCandidateParser.wikidataCandidates(from: wikidata).first)

        XCTAssertEqual(aniListCandidate.sourceIDs, [
            SableLibrarySourceID(provider: .anilist, value: "154587"),
            SableLibrarySourceID(provider: .myAnimeList, value: "52991")
        ])
        XCTAssertEqual(aniListCandidate.genres, ["Adventure", "Fantasy"])
        XCTAssertEqual(aniListCandidate.tags, ["Time Travel", "Magic"])
        XCTAssertEqual(aniListCandidate.status, "FINISHED")
        XCTAssertEqual(aniListCandidate.studios, ["Madhouse"])
        XCTAssertEqual(aniListCandidate.contentWarnings, [])
        XCTAssertNil(aniListCandidate.contentRating)
        XCTAssertEqual(openLibraryCandidate.sourceIDs, [
            SableLibrarySourceID(provider: .openLibrary, value: "/works/OL39406770W")
        ])
        XCTAssertEqual(openLibraryCandidate.isbn13, ["9780306406157", "9781638583936"])
        XCTAssertEqual(openLibraryCandidate.authors, ["Touko Amekawa"])
        XCTAssertEqual(openLibraryCandidate.publishers, ["Seven Seas Siren"])
        XCTAssertEqual(openLibraryCandidate.languages, ["eng"])
        XCTAssertEqual(openLibraryCandidate.genres, ["fantasy", "romance"])
        XCTAssertEqual(openLibraryCandidate.tags, ["light novel"])
        XCTAssertEqual(openLibraryCandidate.aliases, [])
        XCTAssertEqual(tmdbCandidate.sourceIDs.first, SableLibrarySourceID(provider: .tmdb, value: "209867"))
        XCTAssertEqual(tmdbCandidate.mediaType, "tvShow")
        XCTAssertEqual(tvmazeCandidate.sourceIDs, [
            SableLibrarySourceID(provider: .tvmaze, value: "69956"),
            SableLibrarySourceID(provider: .tvdb, value: "424536"),
            SableLibrarySourceID(provider: .imdb, value: "tt22248376")
        ])
        XCTAssertEqual(tvmazeCandidate.year, 2023)
        XCTAssertEqual(tvmazeCandidate.genres, ["Adventure"])
        XCTAssertEqual(tvmazeCandidate.status, "Running")
        XCTAssertTrue(wikidataIDs.contains(SableLibrarySourceID(provider: .wikidata, value: "Q118080048")))
        XCTAssertTrue(wikidataIDs.contains(SableLibrarySourceID(provider: .tmdb, value: "209867")))
        XCTAssertTrue(wikidataIDs.contains(SableLibrarySourceID(provider: .tvdb, value: "424536")))
        XCTAssertTrue(wikidataIDs.contains(SableLibrarySourceID(provider: .imdb, value: "tt22248376")))
        XCTAssertEqual(wikidataCandidate.title, "Frieren: Beyond Journey's End")
        XCTAssertEqual(wikidataCandidate.year, 2023)
        XCTAssertEqual(wikidataCandidate.mediaType, "tv")
        XCTAssertTrue(wikidataCandidate.sourceIDs.contains(SableLibrarySourceID(provider: .imdb, value: "tt22248376")))
    }

    func testWikidataParserKeepsProseBookSeriesHints() throws {
        let wikidata = [
            "results": [
                "bindings": [
                    [
                        "item": ["value": "http://www.wikidata.org/entity/Q101987946"],
                        "itemLabel": ["value": "A Court of Wings and Ruin"],
                        "releaseYear": ["value": "2017"],
                        "bookMediaType": ["value": "book"],
                        "openLibrary": ["value": "OL17823218W"],
                        "isbn13": ["value": "9781619634480"],
                        "authorLabel": ["value": "Sarah J. Maas"],
                        "publisherLabel": ["value": "Bloomsbury Publishing"],
                        "seriesLabel": ["value": "A Court of Thorns and Roses"]
                    ],
                    [
                        "item": ["value": "http://www.wikidata.org/entity/Q101987946"],
                        "itemLabel": ["value": "A Court of Wings and Ruin"],
                        "releaseYear": ["value": "2017"],
                        "bookMediaType": ["value": "book"],
                        "openLibrary": ["value": "OL17823218W"],
                        "authorLabel": ["value": "Sarah J. Maas"],
                        "partOfLabel": ["value": "A Court of Thorns and Roses"]
                    ]
                ]
            ]
        ] as [String: Any]

        let candidate = try XCTUnwrap(SableLibraryProviderCandidateParser.wikidataCandidates(from: wikidata).first)

        XCTAssertEqual(candidate.title, "A Court of Wings and Ruin")
        XCTAssertEqual(candidate.year, 2017)
        XCTAssertEqual(candidate.mediaType, "book")
        XCTAssertEqual(candidate.isbn13, ["9781619634480"])
        XCTAssertEqual(candidate.authors, ["Sarah J. Maas"])
        XCTAssertEqual(candidate.publishers, ["Bloomsbury Publishing"])
        XCTAssertTrue(candidate.tags.contains("series:A Court of Thorns and Roses"))
        XCTAssertTrue(candidate.tags.contains("part of:A Court of Thorns and Roses"))
        XCTAssertTrue(candidate.sourceIDs.contains(SableLibrarySourceID(provider: .wikidata, value: "Q101987946")))
        XCTAssertTrue(candidate.sourceIDs.contains(SableLibrarySourceID(provider: .openLibrary, value: "/works/OL17823218W")))
    }
}
