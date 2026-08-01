//
//  SableMangaBakaCoverStudioTests.swift
//  Sable's LibraryTests
//

import Foundation
import XCTest
@testable import Sable_s_Library

final class SableMangaBakaCoverStudioTests: XCTestCase {
    override func tearDown() {
        SableMangaBakaURLProtocol.handler = nil
        super.tearDown()
    }

    func testSeriesIDParserAcceptsIDsAndMangaBakaURLs() {
        XCTAssertEqual(SableMangaBakaCoverClient.seriesID(from: "54536"), 54536)
        XCTAssertEqual(
            SableMangaBakaCoverClient.seriesID(
                from: "https://mangabaka.org/data/submissions/series/54536/edit"
            ),
            54536
        )
        XCTAssertNil(SableMangaBakaCoverClient.seriesID(from: "Sugar Apple Fairy Tale"))
    }

    func testSnapshotNormalizationKeepsExactlyOneDefaultAndOwningSeries() {
        let snapshot = SableMangaBakaCoverSnapshot(
            seriesID: 54536,
            images: [
                cover(url: "https://example.com/1.jpg", index: 1, isDefault: true),
                cover(url: "https://example.com/2.jpg", index: 2, isDefault: true)
            ],
            version: 100
        )

        let normalized = snapshot.normalizedForSubmission()

        XCTAssertEqual(normalized.images.filter(\.isDefault).count, 1)
        XCTAssertTrue(normalized.images[0].isDefault)
        XCTAssertFalse(normalized.images[1].isDefault)
        XCTAssertEqual(normalized.images.map(\.seriesID), [54536, 54536])
    }

    @MainActor
    func testExistingMangaBakaCoverNumberCanBeCorrectedInDraft() {
        let store = SableMangaBakaCoverStudioStore()
        store.draftImages = [
            cover(
                url: "https://example.com/wrong-number.jpg",
                index: 4,
                isDefault: true
            )
        ]

        store.setDraftImageNumber(at: 0, to: 1.5)

        XCTAssertEqual(store.draftImages[0].indexNumeric, 1.5)
        XCTAssertEqual(store.draftImages[0].index, "1.5")

        store.setDraftImageNumber(at: 0, to: -1)
        XCTAssertEqual(store.draftImages[0].indexNumeric, 1.5)
    }

    func testPreferredDefaultUsesAvailableLanguageAndCoverTypeOrder() {
        let images = [
            cover(
                url: "https://example.com/chapter-ja.jpg",
                index: 1,
                isDefault: true,
                language: "ja",
                type: "chapter"
            ),
            cover(
                url: "https://example.com/volume-ko.jpg",
                index: 1,
                isDefault: false,
                language: "ko",
                type: "volume"
            ),
            cover(
                url: "https://example.com/volume-ja.jpg",
                index: 1,
                isDefault: false,
                language: "ja",
                type: "volume"
            ),
            cover(
                url: "https://example.com/volume-en.jpg",
                index: 2,
                isDefault: false,
                language: "en",
                type: "volume"
            )
        ]

        XCTAssertEqual(
            SableMangaBakaCoverSnapshot.preferredDefaultIndex(in: images),
            2
        )
    }

    func testPreferredDefaultFallsBackToEnglishChapterOne() {
        let images = [
            cover(
                url: "https://example.com/chapter-ja.jpg",
                index: 1,
                isDefault: true,
                language: "ja",
                type: "chapter"
            ),
            cover(
                url: "https://example.com/chapter-en.jpg",
                index: 1,
                isDefault: false,
                language: "en",
                type: "chapter"
            ),
            cover(
                url: "https://example.com/volume-en-2.jpg",
                index: 2,
                isDefault: false,
                language: "en",
                type: "volume"
            )
        ]

        XCTAssertEqual(
            SableMangaBakaCoverSnapshot.preferredDefaultIndex(in: images),
            1
        )
    }

    func testSnapshotValidationRejectsDuplicateAndImgurURLs() {
        let image = cover(url: "https://imgur.com/example.jpg", index: 1, isDefault: true)
        let snapshot = SableMangaBakaCoverSnapshot(
            seriesID: 54536,
            images: [image, image],
            version: 100
        )

        let issues = snapshot.validationIssues()

        XCTAssertTrue(issues.contains("MangaBaka rejects Imgur cover URLs because of rate limiting."))
        XCTAssertTrue(issues.contains("The same cover URL appears more than once."))
        XCTAssertTrue(issues.contains("A non-empty cover set needs exactly one default cover."))
    }

    func testSnapshotValidationAllowsOnlyInheritedDuplicateURLs() {
        let inherited = [
            cover(
                url: "https://example.com/inherited.jpg",
                index: 1,
                isDefault: true
            ),
            cover(
                url: " https://example.com/inherited.jpg ",
                index: 2,
                isDefault: false
            )
        ]
        let unchangedDuplicate = SableMangaBakaCoverSnapshot(
            seriesID: 54536,
            images: inherited + [
                cover(
                    url: "https://example.com/new.jpg",
                    index: 3,
                    isDefault: false
                )
            ],
            version: 100
        )
        let newlyDuplicated = SableMangaBakaCoverSnapshot(
            seriesID: 54536,
            images: inherited + [
                cover(
                    url: "https://example.com/inherited.jpg",
                    index: 3,
                    isDefault: false
                )
            ],
            version: 100
        )

        XCTAssertFalse(
            unchangedDuplicate
                .validationIssues(
                    allowingInheritedDuplicateURLsFrom: inherited
                )
                .contains("The same cover URL appears more than once.")
        )
        XCTAssertTrue(
            newlyDuplicated
                .validationIssues(
                    allowingInheritedDuplicateURLsFrom: inherited
                )
                .contains("The same cover URL appears more than once.")
        )
    }

    func testCoverInventorySeparatesVolumesChaptersAudiobooksAndSpecials() {
        let volume = SableMangaBakaCoverImage(
            seriesID: 64_161,
            url: "https://example.com/volume.jpg",
            index: "1",
            indexNumeric: 1,
            language: "ja",
            type: "volume"
        )
        let chapter = SableMangaBakaCoverImage(
            seriesID: 64_161,
            url: "https://example.com/chapter.jpg",
            index: "0",
            indexNumeric: 0,
            language: "en",
            type: "chapter"
        )
        let audiobook = SableMangaBakaCoverImage(
            seriesID: 64_161,
            url: "https://example.com/audio.jpg",
            index: "1",
            indexNumeric: 1,
            language: "en",
            type: "audiobook"
        )
        let backCover = SableMangaBakaCoverImage(
            seriesID: 64_161,
            url: "https://example.com/back.jpg",
            index: "1",
            indexNumeric: 1,
            language: "ja",
            type: "volume_back"
        )
        let special = SableMangaBakaCoverImage(
            seriesID: 64_161,
            url: "https://example.com/special.jpg",
            index: "2",
            indexNumeric: 2,
            language: "ja",
            type: "volume",
            note: "Special edition"
        )

        XCTAssertEqual(volume.inventoryGroup, .standardVolumes)
        XCTAssertEqual(backCover.inventoryGroup, .backCovers)
        XCTAssertEqual(chapter.inventoryGroup, .chapterCovers)
        XCTAssertEqual(audiobook.inventoryGroup, .audiobookCovers)
        XCTAssertEqual(special.inventoryGroup, .extras)
        XCTAssertEqual(chapter.inventoryItemLabel, "Chapter 0")
        XCTAssertEqual(audiobook.inventoryItemLabel, "Audiobook 1")
        XCTAssertEqual(backCover.inventoryItemLabel, "Back Cover 1")
        XCTAssertEqual(special.inventoryItemLabel, "Special / Alternative 2")
    }

    @MainActor
    func testLiveOnlyChapterRemainsVisibleWithoutJoiningEditableDraft() {
        let store = SableMangaBakaCoverStudioStore()
        store.draftImages = [
            cover(
                url: "https://example.com/volume-1.jpg",
                index: 1,
                isDefault: true
            )
        ]
        store.mangaBakaLiveCovers = [
            SableMangaBakaPublicCoverImage(
                id: 10,
                indexNumeric: 1,
                language: "ja",
                type: "volume",
                rawURL: "https://images.example.com/volume-1.jpg",
                width: 1_800,
                height: 2_560
            ),
            SableMangaBakaPublicCoverImage(
                id: 11,
                indexNumeric: 0,
                language: "en",
                type: "chapter",
                rawURL: "https://images.example.com/chapter-0.jpg",
                width: 1_200,
                height: 1_800
            )
        ]

        XCTAssertEqual(store.draftImages.count, 1)
        XCTAssertEqual(store.liveOnlyMangaBakaCovers.map(\.id), [11])
        XCTAssertEqual(store.coverInventoryTotalCount, 2)
        XCTAssertEqual(store.coverInventoryCount(in: .standardVolumes), 1)
        XCTAssertEqual(store.coverInventoryCount(in: .chapterCovers), 1)
        XCTAssertEqual(store.coverInventoryCount(in: .audiobookCovers), 0)
        XCTAssertEqual(store.coverInventoryCount(in: .extras), 0)

        XCTAssertEqual(store.coverInventoryLanguageCodes, ["ja", "en"])
        store.coverInventoryLanguage = "en"
        XCTAssertEqual(store.coverInventoryFilteredTotalCount, 1)
        XCTAssertEqual(store.coverInventoryCount(in: .standardVolumes), 0)
        XCTAssertEqual(store.coverInventoryCount(in: .chapterCovers), 1)
        XCTAssertEqual(store.draftImages.count, 1)

        store.coverInventoryLanguage = "ja"
        XCTAssertEqual(store.coverInventoryFilteredTotalCount, 1)
        XCTAssertEqual(store.coverInventoryCount(in: .standardVolumes), 1)
        XCTAssertEqual(store.coverInventoryCount(in: .chapterCovers), 0)
    }

    @MainActor
    func testSuccessfulApplyRefreshKeepsProviderResultsAndClearsSelection() {
        let suggestion = storefrontSuggestion(
            provider: .bookLiveJP,
            language: "ja"
        )
        let store = SableMangaBakaCoverStudioStore()
        store.storefrontSuggestions = [suggestion]
        store.selectedStorefrontSuggestionIDs = [suggestion.id]
        store.approvedStorefrontReviewGroupIDs = ["booklive-review"]
        store.rolerMatchShareStatuses = ["booklive-review": .shared]
        store.storefrontNotes = ["BookLive JP: 8 fronts"]

        store.prepareStorefrontStateForSeriesLoad(
            preservingStorefrontResults: true
        )

        XCTAssertEqual(store.storefrontSuggestions, [suggestion])
        XCTAssertTrue(store.selectedStorefrontSuggestionIDs.isEmpty)
        XCTAssertEqual(
            store.approvedStorefrontReviewGroupIDs,
            ["booklive-review"]
        )
        XCTAssertEqual(
            store.rolerMatchShareStatuses["booklive-review"],
            .shared
        )
        XCTAssertEqual(store.storefrontNotes, ["BookLive JP: 8 fronts"])
    }

    func testAmazonProductCategoryProvesLightNovel() {
        let html = """
        <html><head><title>Re:Zero, Vol. 1: Books</title></head><body>
        <a href="/gp/bestsellers/books/11764665011/ref=pd_zg_hrsr_books">
        Teen &amp; Young Adult Light Novels
        </a>
        </body></html>
        """

        XCTAssertEqual(
            SableMangaBakaStorefrontDiscovery.storefrontMediaTypeProof(
                title: "Re:Zero, Vol. 1",
                html: html
            ),
            "novel"
        )
    }

    func testAmazonProductCategoryProvesManga() {
        let html = """
        <html><head><title>Example, Vol. 1: Books</title></head><body>
        <a href="/gp/bestsellers/books/4367/ref=pd_zg_hrsr_books">
        Comics, Manga &amp; Graphic Novels
        </a>
        </body></html>
        """

        XCTAssertEqual(
            SableMangaBakaStorefrontDiscovery.storefrontMediaTypeProof(
                title: "Example, Vol. 1",
                html: html
            ),
            "manga"
        )
    }

    func testAmazonProductPagePrefersHighResolutionCoverImages() {
        let html = #"""
        <script>
        var gallery = [
          {"large":"https:\/\/images.example\/volume-1-large.jpg",
           "hiRes":"https:\/\/images.example\/volume-1-hires.jpg"}
        ];
        </script>
        <img
          data-old-hires="https://images.example/volume-1-old-hires.jpg"
          src="https://images.example/series-thumbnail.jpg"
        >
        """#

        XCTAssertEqual(
            SableMangaBakaStorefrontDiscovery
                .amazonHighResolutionImageURLs(in: html),
            [
                "https://images.example/volume-1-hires.jpg",
                "https://images.example/volume-1-large.jpg",
                "https://images.example/volume-1-old-hires.jpg"
            ]
        )
    }

    func testAmazonGermanyProductPagePrefersSecondFrontGalleryImage() {
        let html = #"""
        <script>
        var gallery = [
          {"large":"https:\/\/images.example\/volume-1-preview-large.jpg",
           "hiRes":"https:\/\/images.example\/volume-1-preview-hires.jpg"},
          {"large":"https:\/\/images.example\/volume-1-cover-large.jpg",
           "hiRes":"https:\/\/images.example\/volume-1-cover-hires.jpg"}
        ];
        </script>
        """#

        XCTAssertEqual(
            SableMangaBakaStorefrontDiscovery
                .amazonPreferredFrontImageURLs(
                    in: html,
                    host: "www.amazon.de"
                ),
            [
                "https://images.example/volume-1-cover-hires.jpg",
                "https://images.example/volume-1-cover-large.jpg",
                "https://images.example/volume-1-preview-hires.jpg",
                "https://images.example/volume-1-preview-large.jpg"
            ]
        )
        XCTAssertEqual(
            SableMangaBakaStorefrontDiscovery
                .amazonPreferredFrontImageURLs(
                    in: html,
                    host: "www.amazon.com"
                ),
            [
                "https://images.example/volume-1-preview-hires.jpg",
                "https://images.example/volume-1-cover-hires.jpg",
                "https://images.example/volume-1-preview-large.jpg",
                "https://images.example/volume-1-cover-large.jpg"
            ]
        )
    }

    func testAmazonProductGalleryDoesNotBorrowAudibleCompanionArtwork() {
        let html = #"""
        <script>
        var audibleCompanion = {
          'asin': 'B0AUDIBLE1',
          'colorImages': { 'initial': [
            {"large":"https:\/\/images.example\/audible-volume-1-large.jpg",
             "hiRes":"https:\/\/images.example\/audible-volume-1-square.jpg",
             "variant":"MAIN"}
          ]}
        };
        var kindleImageBlock = {
          'asin': 'B0G34PSB1C',
          'colorImages': { 'initial': [
            {"large":"https:\/\/images.example\/kindle-volume-1-large.jpg",
             "hiRes":"https:\/\/images.example\/kindle-volume-1-hires.jpg",
             "variant":"MAIN"}
          ]},
          'colorToAsin': {}
        };
        </script>
        """#

        XCTAssertEqual(
            SableMangaBakaStorefrontDiscovery
                .amazonPreferredFrontImageURLs(
                    in: html,
                    host: "www.amazon.com",
                    expectedItemID: "B0G34PSB1C"
                ),
            [
                "https://images.example/kindle-volume-1-hires.jpg",
                "https://images.example/kindle-volume-1-large.jpg"
            ]
        )
    }

    func testEveryAmazonStorePageUsesItsProductGallery() {
        XCTAssertTrue(
            SableMangaBakaStorefrontDiscovery
                .amazonStoreURLSupportsPageGallery(
                    "https://www.amazon.com/dp/B0DH5CX7XM"
                )
        )
        XCTAssertTrue(
            SableMangaBakaStorefrontDiscovery
                .amazonStoreURLSupportsPageGallery(
                    "https://www.amazon.co.uk/dp/B0DH5LFGQL"
                )
        )
        XCTAssertTrue(
            SableMangaBakaStorefrontDiscovery
                .amazonStoreURLSupportsPageGallery(
                    "https://www.amazon.de/dp/2889510182"
                )
        )
        XCTAssertFalse(
            SableMangaBakaStorefrontDiscovery
                .amazonStoreURLSupportsPageGallery(
                    "https://m.media-amazon.com/images/I/cover.jpg"
                )
        )
    }

    func testAmazonProductPageSeparatesBackCoverFromFrontImages() {
        let html = #"""
        <script>
        var gallery = [
          {"large":"https:\/\/images.example\/volume-33-front-large.jpg",
           "hiRes":"https:\/\/images.example\/volume-33-front.jpg"}
        ];
        </script>
        <li class="image item maintain-height variant-BACK">
          <div
            data-a-image-name="mbAltImage"
            data-old-hires="https://images.example/volume-33-back.jpg"
          ></div>
        </li>
        """#

        XCTAssertEqual(
            SableMangaBakaStorefrontDiscovery
                .amazonHighResolutionImageURLs(in: html),
            [
                "https://images.example/volume-33-front.jpg",
                "https://images.example/volume-33-front-large.jpg"
            ]
        )
        XCTAssertEqual(
            SableMangaBakaStorefrontDiscovery
                .amazonBackCoverImageURLs(in: html),
            ["https://images.example/volume-33-back.jpg"]
        )
    }

    func testAmazonAudiobookTitleCannotMasqueradeAsNovel() {
        XCTAssertEqual(
            SableMangaBakaStorefrontDiscovery.storefrontMediaTypeProof(
                title: "Example, Vol. 1: Audible Audio Edition",
                html: "<a href=\"/gp/bestsellers/books/11764665011\">Light Novels</a>"
            ),
            "audiobook"
        )
    }

    func testAmazonJapaneseMangaImprintProvesManga() {
        XCTAssertEqual(
            SableMangaBakaStorefrontDiscovery.storefrontMediaTypeProof(
                title: "戦闘員、派遣します！ 5 (MFコミックス アライブシリーズ)",
                html: nil
            ),
            "manga"
        )
    }

    func testAmazonJapaneseLightNovelImprintProvesNovel() {
        XCTAssertEqual(
            SableMangaBakaStorefrontDiscovery.storefrontMediaTypeProof(
                title: "戦闘員、派遣します！ (角川スニーカー文庫)",
                html: nil
            ),
            "novel"
        )
    }

    func testAutomaticAmazonResultsRejectProvenWrongMediaType() {
        XCTAssertEqual(
            SableMangaBakaStorefrontDiscovery
                .automaticMediaTypeDisposition(
                    detectedMediaType: "manga",
                    expectedMediaType: "light_novel"
                ),
            .rejected
        )
        XCTAssertEqual(
            SableMangaBakaStorefrontDiscovery
                .automaticMediaTypeDisposition(
                    detectedMediaType: nil,
                    expectedMediaType: "light_novel"
                ),
            .needsReview
        )
        XCTAssertEqual(
            SableMangaBakaStorefrontDiscovery
                .automaticMediaTypeDisposition(
                    detectedMediaType: "novel",
                    expectedMediaType: "light_novel"
                ),
            .accepted
        )
    }

    func testLocalMediaMismatchNeverHidesBBCVolumeRows() {
        func candidate(
            _ id: String,
            mediaType: String?
        ) -> SableLibraryProviderCoverCandidate {
            SableLibraryProviderCoverCandidate(
                provider: .local,
                providerSeriesID: "amazon-series",
                providerItemID: id,
                title: "7th Time Loop \(id)",
                volumeIndex: "1",
                volumeNumber: 1,
                mediaType: mediaType,
                language: "en",
                role: .normal,
                providerType: nil,
                editionNote: nil,
                imageURL: "https://example.com/\(id).jpg",
                width: 1_500,
                height: 2_138,
                byteCount: nil,
                storeURLs: [],
                quality: .highResolution
            )
        }

        var requiresRelationshipReview = false
        let filtered = SableMangaBakaStorefrontDiscovery
            .volumeCandidatesForMediaReview(
                from: [
                    candidate("light-novel", mediaType: "novel"),
                    candidate("unknown", mediaType: nil),
                    candidate("manga-sibling", mediaType: "manga")
                ],
                targetMediaType: "light_novel",
                trustsSelectedSeriesIdentity: false,
                offersMediaTypeMismatchForReview: false,
                requiresRelationshipReview: &requiresRelationshipReview
            )

        XCTAssertEqual(
            filtered.compactMap(\.providerItemID),
            ["light-novel", "unknown", "manga-sibling"]
        )
        XCTAssertFalse(requiresRelationshipReview)
    }

    func testAmazonExactTitleRemainsReviewableWhenStoreTypeConflicts() {
        let series = SableMangaBakaSeriesSummary(
            id: 725,
            title: "ONE-PUNCH MAN",
            nativeTitle: "ワンパンマン",
            romanizedTitle: "One-Punch Man",
            titles: [
                SableMangaBakaSeriesTitle(
                    language: "ja",
                    traits: ["native"],
                    title: "ワンパンマン",
                    isPrimary: true
                )
            ],
            type: "manga",
            cover: nil,
            finalVolume: nil
        )

        XCTAssertTrue(
            SableMangaBakaStorefrontDiscovery
                .shouldOfferMediaTypeMismatchForManualReview(
                    providerTitles: [
                        "ワンパンマン 2 (ジャンプコミックス)"
                    ],
                    series: series,
                    language: "ja"
                )
        )
        XCTAssertFalse(
            SableMangaBakaStorefrontDiscovery
                .shouldOfferMediaTypeMismatchForManualReview(
                    providerTitles: [
                        "ONE PIECE モノクロ版 2 (ジャンプコミックス)"
                    ],
                    series: series,
                    language: "ja"
                )
        )
        XCTAssertEqual(
            SableMangaBakaStorefrontDiscovery.automaticMatchConfidence(
                providerTitles: ["ワンパンマン 2"],
                series: series,
                language: "ja",
                detectedMediaType: "novel",
                expectedMediaType: "manga"
            ),
            0
        )
    }

    @MainActor
    func testSelectedStorefrontCoverIsAddedToTheDraftWithoutUploading() {
        let store = SableMangaBakaCoverStudioStore()
        let suggestion = SableMangaBakaStorefrontCoverSuggestion(
            provider: .amazon,
            providerSeriesID: "agents",
            providerItemID: "volume-8",
            title: "Agents of the Four Seasons, Volume 8",
            imageURL: "https://images.example.com/agents-ko-8.jpg",
            storeURL: "https://example.com/agents/8",
            volumeNumber: 8,
            language: "ko"
        )
        store.selectedSeries = SableMangaBakaSeriesSummary(
            id: 188_016,
            title: "Agents of the Four Seasons",
            nativeTitle: nil,
            romanizedTitle: nil,
            titles: nil,
            type: "novel",
            cover: nil,
            finalVolume: nil
        )
        store.storefrontSuggestions = [suggestion]
        store.selectedStorefrontSuggestionIDs = [suggestion.id]

        let added = store.stageSelectedStorefrontCovers()

        XCTAssertEqual(added, 1)
        XCTAssertEqual(store.draftImages.count, 1)
        XCTAssertEqual(store.draftImages.first?.language, "ko")
        XCTAssertEqual(store.draftImages.first?.indexNumeric, 8)
        XCTAssertTrue(store.selectedStorefrontSuggestionIDs.isEmpty)
        XCTAssertNil(store.preview)
        XCTAssertTrue(store.storefrontStageSummary?.contains("Added 1 new cover") == true)
        XCTAssertTrue(store.submissionNote.contains("KO: v8 Amazon US"))
        XCTAssertTrue(store.submissionNote.contains("Cover marked safe."))
        XCTAssertTrue(store.submissionNote.contains("Checked media type"))
        XCTAssertTrue(store.submissionNote.contains("existing MangaBaka cover quality"))
        XCTAssertFalse(store.submissionNote.contains("Sable"))
    }

    @MainActor
    func testStorefrontImageChooserStagesTheChosenImageURL() {
        let store = SableMangaBakaCoverStudioStore()
        let previewURL = "https://images.example.com/agents-de-1-preview.jpg"
        let coverURL = "https://images.example.com/agents-de-1-cover.jpg"
        let suggestion = SableMangaBakaStorefrontCoverSuggestion(
            provider: .amazonGermany,
            providerSeriesID: "agents",
            providerItemID: "volume-1",
            title: "Agents of the Four Seasons, Band 1",
            imageURL: previewURL,
            imageChoices: [
                SableMangaBakaStorefrontImageChoice(
                    url: previewURL,
                    width: 900,
                    height: 1400
                ),
                SableMangaBakaStorefrontImageChoice(
                    url: coverURL,
                    width: 1218,
                    height: 2149
                )
            ],
            storeURL: "https://www.amazon.de/dp/example",
            volumeNumber: 1,
            language: "de"
        )
        store.selectedSeries = SableMangaBakaSeriesSummary(
            id: 188_016,
            title: "Agents of the Four Seasons",
            nativeTitle: nil,
            romanizedTitle: nil,
            titles: nil,
            type: "novel",
            cover: nil,
            finalVolume: nil
        )
        store.storefrontSuggestions = [suggestion]
        store.selectedStorefrontSuggestionIDs = [suggestion.id]

        store.setStorefrontSuggestionImage(suggestion, imageURL: coverURL)

        guard let updated = store.storefrontSuggestions.first else {
            XCTFail("Expected an updated suggestion")
            return
        }
        XCTAssertEqual(updated.imageURL, coverURL)
        XCTAssertEqual(updated.width, 1218)
        XCTAssertEqual(updated.height, 2149)
        XCTAssertTrue(store.selectedStorefrontSuggestionIDs.contains(updated.id))
        XCTAssertFalse(store.selectedStorefrontSuggestionIDs.contains(suggestion.id))

        XCTAssertEqual(store.stageSelectedStorefrontCovers(), 1)
        XCTAssertEqual(store.draftImages.first?.url, coverURL)
    }

    @MainActor
    func testManualSelectionReassignsWhitespaceVariantOfExistingURL() {
        let store = SableMangaBakaCoverStudioStore()
        store.selectedSeries = SableMangaBakaSeriesSummary(
            id: 725,
            title: "ONE-PUNCH MAN",
            nativeTitle: nil,
            romanizedTitle: nil,
            titles: nil,
            type: "manga",
            cover: nil,
            finalVolume: nil
        )
        store.draftImages = [
            cover(
                url: " https://example.com/volume-1.jpg ",
                index: 1,
                isDefault: true
            )
        ]
        let suggestion = SableMangaBakaStorefrontCoverSuggestion(
            provider: .amazon,
            providerSeriesID: "one-punch-man",
            providerItemID: "volume-2",
            title: "One-Punch Man, Vol. 2",
            imageURL: "https://example.com/volume-1.jpg",
            storeURL: "https://example.com/one-punch-man/2",
            volumeNumber: 2,
            language: "ja"
        )
        store.storefrontSuggestions = [suggestion]
        store.selectedStorefrontSuggestionIDs = [suggestion.id]

        XCTAssertEqual(store.stageSelectedStorefrontCovers(), 1)
        XCTAssertEqual(store.draftImages.count, 1)
        XCTAssertEqual(store.draftImages.first?.indexNumeric, 2)
        XCTAssertEqual(
            store.draftImages.first?.url,
            "https://example.com/volume-1.jpg"
        )
        XCTAssertTrue(
            store.storefrontStageSummary?.contains(
                "Reassigned 1 existing cover"
            ) == true
        )
        XCTAssertTrue(store.selectedStorefrontSuggestionIDs.isEmpty)
    }

    @MainActor
    func testStoreFormatDoesNotCreateAnEditionNoteOrDuplicateSlot() {
        let store = SableMangaBakaCoverStudioStore()
        store.selectedSeries = SableMangaBakaSeriesSummary(
            id: 725,
            title: "ONE-PUNCH MAN",
            nativeTitle: "ワンパンマン",
            romanizedTitle: nil,
            type: "manga"
        )
        store.draftImages = [
            cover(
                url: "https://example.com/print-1.jpg",
                index: 1,
                isDefault: true
            )
        ]
        var paperback = storefrontSuggestion(
            provider: .amazonJP,
            language: "ja",
            publicationType: "physical"
        )
        paperback.imageURL = "https://example.com/print-1.jpg"
        store.storefrontSuggestions = [paperback]
        store.setStorefrontSuggestion(paperback.id, isSelected: true)

        XCTAssertEqual(store.stageSelectedStorefrontCovers(), 0)
        XCTAssertEqual(store.draftImages.count, 1)
        XCTAssertEqual(store.draftImages.first?.url, paperback.imageURL)
        XCTAssertNil(store.draftImages.first?.note)
        XCTAssertEqual(
            store.storefrontStageSummary,
            "Every selected cover already exactly matches its target MangaBaka slot."
        )
    }

    @MainActor
    func testExactExistingEditionCanStillBecomeThePreferredDefault() {
        let store = SableMangaBakaCoverStudioStore()
        store.selectedSeries = SableMangaBakaSeriesSummary(
            id: 725,
            title: "ONE-PUNCH MAN",
            nativeTitle: "ワンパンマン",
            romanizedTitle: nil,
            type: "manga"
        )
        var digital = storefrontSuggestion(
            provider: .bookLiveJP,
            language: "ja",
            publicationType: "digital"
        )
        digital.imageURL = "https://example.com/digital-1.jpg"
        store.draftImages = [
            SableMangaBakaCoverImage(
                seriesID: 725,
                url: digital.imageURL,
                index: "1",
                indexNumeric: 1,
                language: "ja",
                note: "Digital edition",
                contentRating: "safe",
                isDefault: false
            )
        ]
        store.storefrontSuggestions = [digital]
        store.setStorefrontSuggestion(digital.id, isSelected: true)

        XCTAssertEqual(store.stageSelectedStorefrontCovers(), 1)
        XCTAssertEqual(store.draftImages.count, 1)
        XCTAssertTrue(store.draftImages[0].isDefault)
        XCTAssertEqual(
            store.storefrontStageSummary,
            "1 selected cover already exactly matched its target slot. Updated the default cover using the preferred language and cover-type order."
        )
        XCTAssertFalse(
            store.status.lowercased().contains("equal or better")
        )
    }

    @MainActor
    func testStorefrontCommentCompactsConsecutiveSourceRanges() {
        let store = SableMangaBakaCoverStudioStore()
        store.selectedSeries = SableMangaBakaSeriesSummary(
            id: 83_317,
            title: "Sword Oratoria",
            nativeTitle: nil,
            romanizedTitle: nil,
            titles: nil,
            type: "novel",
            cover: nil,
            finalVolume: nil
        )
        let suggestions = [
            storefrontSuggestion(
                provider: .amazon,
                language: "en",
                volumeNumber: 1
            ),
            storefrontSuggestion(
                provider: .amazon,
                language: "en",
                volumeNumber: 2
            ),
            storefrontSuggestion(
                provider: .bookLiveJP,
                language: "ja",
                volumeNumber: 1
            ),
            storefrontSuggestion(
                provider: .bookLiveJP,
                language: "ja",
                volumeNumber: 2
            ),
            storefrontSuggestion(
                provider: .bookWalkerJP,
                language: "ja",
                volumeNumber: 3
            )
        ]
        store.storefrontSuggestions = suggestions
        store.selectedStorefrontSuggestionIDs = Set(suggestions.map(\.id))

        XCTAssertEqual(store.stageSelectedStorefrontCovers(), 5)
        XCTAssertTrue(
            store.submissionNote.contains(
                "EN: v1-2 Amazon US; JA: v1-2 BookLive JP, v3 BookWalker JP"
            )
        )
        XCTAssertTrue(store.submissionNote.contains("All covers marked safe."))
        XCTAssertFalse(store.submissionNote.contains("(safe cover)"))
    }

    @MainActor
    func testSelectedManualChapterCoverKeepsItsChapterType() {
        let store = SableMangaBakaCoverStudioStore()
        let suggestion = SableMangaBakaStorefrontCoverSuggestion(
            provider: .bookWalkerGlobal,
            providerSeriesID: "CNT_1TZHZ2EGA8T0",
            providerItemID: "chapter-3",
            title: "Chapter 3",
            imageURL: "https://images.example.com/chapter-3.jpg",
            storeURL: "https://bookwalker.com/de123",
            volumeNumber: 3,
            language: "en",
            coverType: "chapter"
        )
        store.selectedSeries = SableMangaBakaSeriesSummary(
            id: 64_161,
            title: "Agents of the Four Seasons",
            nativeTitle: "春夏秋冬代行者 百歌百葉",
            romanizedTitle: nil,
            titles: nil,
            type: "manga",
            cover: nil,
            finalVolume: nil
        )
        store.storefrontSuggestions = [suggestion]
        store.selectedStorefrontSuggestionIDs = [suggestion.id]

        XCTAssertEqual(store.stageSelectedStorefrontCovers(), 1)
        XCTAssertEqual(store.draftImages.count, 1)
        XCTAssertEqual(store.draftImages.first?.type, "chapter")
        XCTAssertEqual(store.draftImages.first?.indexNumeric, 3)
        XCTAssertTrue(
            store.submissionNote.contains(
                "EN: ch3 BookWalker Global"
            )
        )
        XCTAssertFalse(store.submissionNote.contains("Sable"))
    }

    @MainActor
    func testHigherQualityStorefrontCoverReplacesSameMangaBakaSlot() {
        let store = SableMangaBakaCoverStudioStore()
        store.selectedSeries = SableMangaBakaSeriesSummary(
            id: 99_032,
            title: "Back to the Battlefield",
            nativeTitle: nil,
            romanizedTitle: nil,
            titles: nil,
            type: "novel",
            cover: nil,
            finalVolume: "4"
        )
        store.draftImages = [
            cover(
                url: "https://example.com/old.jpg",
                index: 1,
                isDefault: true
            )
        ]
        store.mangaBakaVolumeCovers = [
            SableMangaBakaPublicCoverImage(
                id: 10,
                indexNumeric: 1,
                language: "ja",
                type: "volume",
                rawURL: "https://example.com/old.jpg",
                width: 500,
                height: 700
            )
        ]
        let upgrade = storefrontSuggestion(
            provider: .bookWalkerJP,
            language: "ja",
            width: 1_500,
            height: 2_250
        )
        store.storefrontSuggestions = [upgrade]
        store.setStorefrontSuggestion(upgrade.id, isSelected: true)

        XCTAssertEqual(store.stageSelectedStorefrontCovers(), 1)
        XCTAssertEqual(store.draftImages.count, 1)
        XCTAssertEqual(store.draftImages[0].url, upgrade.imageURL)
        XCTAssertTrue(
            store.storefrontStageSummary?.contains("Replaced 1 existing cover") == true
        )
    }

    @MainActor
    func testManuallySelectedCoverCanReplaceAnEqualOrBetterMangaBakaSlot() {
        let store = SableMangaBakaCoverStudioStore()
        store.selectedSeries = SableMangaBakaSeriesSummary(
            id: 99_032,
            title: "Back to the Battlefield",
            nativeTitle: nil,
            romanizedTitle: nil,
            titles: nil,
            type: "novel",
            cover: nil,
            finalVolume: "4"
        )
        store.draftImages = [
            cover(
                url: "https://example.com/good.jpg",
                index: 1,
                isDefault: true
            )
        ]
        store.mangaBakaVolumeCovers = [
            SableMangaBakaPublicCoverImage(
                id: 10,
                indexNumeric: 1,
                language: "ja",
                type: "volume",
                rawURL: "https://example.com/good.jpg",
                width: 1_500,
                height: 2_250
            )
        ]
        let worse = storefrontSuggestion(
            provider: .amazonJP,
            language: "ja",
            width: 800,
            height: 1_100
        )
        store.storefrontSuggestions = [worse]
        store.setStorefrontSuggestion(worse.id, isSelected: true)

        XCTAssertTrue(store.selectedStorefrontSuggestionIDs.contains(worse.id))
        XCTAssertFalse(store.storefrontSuggestionIsActionable(worse))
        XCTAssertEqual(
            store.storefrontSuggestionComparisonText(worse),
            "Will replace existing MangaBaka Volume 1 by your choice"
        )
        XCTAssertEqual(store.stageSelectedStorefrontCovers(), 1)
        XCTAssertEqual(store.draftImages.first?.url, worse.imageURL)
        XCTAssertTrue(
            store.storefrontStageSummary?.contains("Replaced 1 existing cover") == true
        )
    }

    @MainActor
    func testSelectAllChoosesOneBestFormatForEveryAvailableVolume() {
        let paperback = storefrontSuggestion(
            provider: .bookLiveJP,
            language: "ja",
            volumeNumber: 1,
            width: 1_000,
            height: 1_500,
            publicationType: "physical"
        )
        let kindle = storefrontSuggestion(
            provider: .bookLiveJP,
            language: "ja",
            volumeNumber: 1,
            width: 2_000,
            height: 3_000,
            publicationType: "digital"
        )
        let second = storefrontSuggestion(
            provider: .bookLiveJP,
            language: "ja",
            volumeNumber: 2
        )
        let excluded = storefrontSuggestion(
            provider: .bookLiveJP,
            language: "ja",
            volumeNumber: 3
        )
        let store = SableMangaBakaCoverStudioStore()
        store.storefrontSuggestions = [paperback, kindle, second, excluded]
        store.excludedStorefrontSuggestionIDs = [excluded.id]

        store.selectAllStorefrontSuggestions(
            from: store.storefrontSuggestions
        )

        XCTAssertEqual(
            store.selectedStorefrontSuggestionIDs,
            Set([kindle.id, second.id])
        )
    }

    func testCommonMangaBakaCoverLanguagesRemainAvailableForManualFallbacks() {
        XCTAssertTrue(
            Set(["en", "ja", "ko", "zh", "fr", "it"])
                .isSubset(of: Set(SableMangaBakaCoverImage.supportedLanguages))
        )
    }

    func testOnlyContributorModeratorAndAdminCanApplyDirectly() {
        XCTAssertFalse(SableMangaBakaAccountRole.user.canApplyDirectly)
        XCTAssertFalse(SableMangaBakaAccountRole.developer.canApplyDirectly)
        XCTAssertTrue(SableMangaBakaAccountRole.contributor.canApplyDirectly)
        XCTAssertTrue(SableMangaBakaAccountRole.moderator.canApplyDirectly)
        XCTAssertTrue(SableMangaBakaAccountRole.admin.canApplyDirectly)

        XCTAssertEqual(SableMangaBakaAccountRole.user.submissionMode, .review)
        XCTAssertEqual(
            SableMangaBakaAccountRole.developer.submissionMode,
            .review
        )
        XCTAssertEqual(
            SableMangaBakaAccountRole.contributor.submissionMode,
            .direct
        )
        XCTAssertEqual(
            SableMangaBakaAccountRole.moderator.submissionMode,
            .direct
        )
        XCTAssertEqual(SableMangaBakaAccountRole.admin.submissionMode, .direct)
    }

    func testAccountProfileChoosesReviewForUserAndDirectForContributor()
        async throws
    {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SableMangaBakaURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        var returnedRole = SableMangaBakaAccountRole.user
        SableMangaBakaURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/v1/my/profile")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "x-api-key"),
                "mb-test-token"
            )

            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
            )
            let data = Data(
                """
                {"status":200,"data":{"id":"account-1","preferred_username":"Sable","updated_at":null,"role":"\(returnedRole.rawValue)","auth_type":"pat","scopes":[]}}
                """.utf8
            )
            return (response, data)
        }

        let client = SableMangaBakaCoverClient(session: session)
        let userProfile = try await client
            .accountProfile(token: "mb-test-token")

        XCTAssertEqual(userProfile.id, "account-1")
        XCTAssertEqual(userProfile.preferredUsername, "Sable")
        XCTAssertEqual(userProfile.role, .user)
        XCTAssertEqual(userProfile.role.submissionMode, .review)

        returnedRole = .contributor
        let contributorProfile = try await client
            .accountProfile(token: "mb-test-token")

        XCTAssertEqual(contributorProfile.role, .contributor)
        XCTAssertEqual(contributorProfile.role.submissionMode, .direct)
    }

    func testSubmitExplicitlyUsesReviewQueueAndPersonalAccessToken() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SableMangaBakaURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        SableMangaBakaURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/v0/my/submissions/series-images/54536")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "mb-test-token")

            let body = try requestBodyData(request)
            let json = try XCTUnwrap(
                JSONSerialization.jsonObject(with: body) as? [String: Any]
            )
            XCTAssertEqual(json["save_mode"] as? String, "review")
            XCTAssertEqual(json["user_note"] as? String, "Add the missing Japanese cover.")

            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
            )
            let data = Data(
                #"{"status":200,"data":{"submission_id":123,"status":"pending","changes":[]}}"#
                    .utf8
            )
            return (response, data)
        }

        let client = SableMangaBakaCoverClient(session: session)
        let snapshot = SableMangaBakaCoverSnapshot(
            seriesID: 54536,
            images: [
                cover(
                    url: "https://images.example.com/jp-1.jpg",
                    index: 1,
                    isDefault: true
                )
            ],
            version: 1_785_000_000_000
        )

        let result = try await client.submit(
            snapshot: snapshot,
            note: "Add the missing Japanese cover.",
            mode: .review,
            token: "mb-test-token"
        )

        XCTAssertEqual(result.submissionID, 123)
        XCTAssertEqual(result.status, "pending")
    }

    func testDirectSubmitPreservesChapterTypeInMangaBakaPayload() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SableMangaBakaURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        SableMangaBakaURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/v0/my/submissions/series-images/64161")

            let body = try requestBodyData(request)
            let json = try XCTUnwrap(
                JSONSerialization.jsonObject(with: body) as? [String: Any]
            )
            let data = try XCTUnwrap(json["data"] as? [String: Any])
            let images = try XCTUnwrap(data["images"] as? [[String: Any]])
            let image = try XCTUnwrap(images.first)

            XCTAssertEqual(image["type"] as? String, "chapter")
            XCTAssertEqual(image["index_numeric"] as? Double, 3)
            XCTAssertEqual(image["index"] as? String, "3")
            XCTAssertEqual(json["save_mode"] as? String, "direct")

            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
            )
            let responseData = Data(
                #"{"status":200,"data":{"submission_id":321,"status":"accepted","changes":[]}}"#
                    .utf8
            )
            return (response, responseData)
        }

        let client = SableMangaBakaCoverClient(session: session)
        let snapshot = SableMangaBakaCoverSnapshot(
            seriesID: 64161,
            images: [
                SableMangaBakaCoverImage(
                    seriesID: 64161,
                    url: "https://images.example.com/chapter-3.jpg",
                    index: "3",
                    indexNumeric: 3,
                    language: "en",
                    type: "chapter",
                    isDefault: true
                )
            ],
            version: 1_785_000_000_000
        )

        let result = try await client.submit(
            snapshot: snapshot,
            note: "Added EN chapter 3 from BookWalker Global.",
            mode: .direct,
            token: "mb-test-token"
        )

        XCTAssertEqual(result.submissionID, 321)
        XCTAssertEqual(result.status, "accepted")
    }

    func testDirectSubmitRejectsAnEmptyChangeCommentBeforeSending() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SableMangaBakaURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        SableMangaBakaURLProtocol.handler = { request in
            XCTFail("An empty change comment must be rejected before a request is sent.")
            throw URLError(.badServerResponse)
        }

        let client = SableMangaBakaCoverClient(session: session)
        let snapshot = SableMangaBakaCoverSnapshot(
            seriesID: 54536,
            images: [
                cover(
                    url: "https://images.example.com/jp-1.jpg",
                    index: 1,
                    isDefault: true
                )
            ],
            version: 1_785_000_000_000
        )

        do {
            _ = try await client.submit(
                snapshot: snapshot,
                note: "   ",
                mode: .direct,
                token: "mb-test-token"
            )
            XCTFail("Expected an empty change comment to be rejected.")
        } catch {
            XCTAssertTrue(
                error.localizedDescription.contains(
                    "Describe what the cover correction changes."
                )
            )
        }
    }

    func testPreviewUsesABoundedRequestAndDoesNotSubmitChanges() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SableMangaBakaURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        SableMangaBakaURLProtocol.handler = { request in
            XCTAssertEqual(
                request.url?.path,
                "/v0/my/submissions/series-images/54536/preview"
            )
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.timeoutInterval, 30, accuracy: 0.1)

            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
            )
            let data = Data(
                #"{"status":200,"data":{"has_changes":true,"changes":[]}}"#.utf8
            )
            return (response, data)
        }

        let snapshot = SableMangaBakaCoverSnapshot(
            seriesID: 54536,
            images: [
                cover(
                    url: "https://images.example.com/jp-1.jpg",
                    index: 1,
                    isDefault: true
                )
            ],
            version: 1_785_000_000_000
        )

        let result = try await SableMangaBakaCoverClient(session: session)
            .preview(snapshot: snapshot, token: "mb-test-token")

        XCTAssertTrue(result.hasChanges)
    }

    func testBrowseUsesPublisherAndMediaTypeFilters() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SableMangaBakaURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        SableMangaBakaURLProtocol.handler = { request in
            let components = try XCTUnwrap(
                URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
            )
            let values = Dictionary(
                uniqueKeysWithValues: (components.queryItems ?? []).map {
                    ($0.name, $0.value ?? "")
                }
            )
            XCTAssertEqual(request.url?.path, "/v1/series/search")
            XCTAssertEqual(values["publisher"], "J-Novel Club")
            XCTAssertEqual(values["type"], "novel")
            XCTAssertEqual(values["is_licensed"], "true")
            XCTAssertEqual(values["page"], "2")
            XCTAssertEqual(values["limit"], "25")
            XCTAssertEqual(values["sort_by"], "name_asc")

            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
            )
            let data = Data(
                """
                {
                  "status": 200,
                  "pagination": {
                    "count": 216,
                    "page": 2,
                    "limit": 25,
                    "next": "https://api.mangabaka.org/v1/series/search?page=3",
                    "previous": "https://api.mangabaka.org/v1/series/search?page=1"
                  },
                  "data": [{
                    "id": 85341,
                    "title": "Sugar Apple Fairy Tale",
                    "type": "novel",
                    "final_volume": "20",
                    "year": 2010,
                    "published": {
                      "start_date": "2010-11-30",
                      "end_date": null
                    },
                    "is_licensed": true,
                    "publishers": [{
                      "name": "J-Novel Club",
                      "type": "English",
                      "note": "20 digital volumes"
                    }]
                  }]
                }
                """.utf8
            )
            return (response, data)
        }

        let client = SableMangaBakaCoverClient(session: session)
        let page = try await client.browseSeries(
            query: "",
            publisher: "J-Novel Club",
            mediaType: "novel",
            isLicensed: true,
            page: 2
        )

        XCTAssertEqual(page.totalCount, 216)
        XCTAssertTrue(page.hasNextPage)
        XCTAssertTrue(page.hasPreviousPage)
        XCTAssertEqual(page.series.first?.finalVolume, "20")
        XCTAssertEqual(page.series.first?.published?.startDate, "2010-11-30")
        XCTAssertEqual(page.series.first?.publicationDateLabel, "2010-11-30")
        XCTAssertEqual(page.series.first?.isLicensed, true)
        XCTAssertEqual(page.series.first?.publishers?.first?.name, "J-Novel Club")
    }

    func testBrowseSortOptionsUseSupportedMangaBakaSortValues() {
        XCTAssertEqual(
            SableMangaBakaBrowseSort.newestPublication.apiValue,
            "published_start_date_desc"
        )
        XCTAssertEqual(
            SableMangaBakaBrowseSort.recentlyCompleted.apiValue,
            "published_end_date_desc"
        )
        XCTAssertEqual(
            SableMangaBakaBrowseSort.mostPopular.apiValue,
            "popularity_asc"
        )
        XCTAssertEqual(
            SableMangaBakaBrowseSort.titleAscending.apiValue,
            "name_asc"
        )
        XCTAssertEqual(
            SableMangaBakaBrowseSort.titleDescending.apiValue,
            "name_desc"
        )
    }

    func testSeriesWithoutCoverCanBeFilteredFromSearchResponse() throws {
        let data = Data(
            """
            {
              "id": 85341,
              "title": "Sugar Apple Fairy Tale",
              "type": "novel",
              "cover": null,
              "is_licensed": true
            }
            """.utf8
        )

        let series = try JSONDecoder().decode(
            SableMangaBakaSeriesSummary.self,
            from: data
        )

        XCTAssertFalse(series.hasCoverImage)
        XCTAssertEqual(series.isLicensed, true)
    }

    @MainActor
    func testNoCoverBrowseUsesEmptyPublicVolumeInventory() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SableMangaBakaURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var requestedImageSeriesIDs = Set<Int>()

        SableMangaBakaURLProtocol.handler = { request in
            let url = try XCTUnwrap(request.url)
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
            )
            if url.path.hasSuffix("/images") {
                let seriesID = try XCTUnwrap(
                    url.path
                        .split(separator: "/")
                        .dropLast()
                        .last
                        .flatMap { Int($0) }
                )
                requestedImageSeriesIDs.insert(seriesID)
                let count = seriesID == 1 ? 1 : 0
                let body = """
                    {
                      "status": 200,
                      "data": [],
                      "pagination": {
                        "count": \(count),
                        "page": 1,
                        "limit": 50,
                        "next": null,
                        "previous": null
                      },
                      "available_languages": [],
                      "available_types": ["volume"]
                    }
                    """
                return (response, Data(body.utf8))
            }

            let components = try XCTUnwrap(
                URLComponents(
                    url: url,
                    resolvingAgainstBaseURL: false
                )
            )
            let query = Dictionary(
                uniqueKeysWithValues: (components.queryItems ?? []).map {
                    ($0.name, $0.value ?? "")
                }
            )
            XCTAssertEqual(query["sort_by"], "published_start_date_desc")
            XCTAssertEqual(query["limit"], "25")
            let body = """
                  {
                    "status": 200,
                    "pagination": {
                      "count": 2,
                      "page": 1,
                      "limit": 25,
                      "next": null,
                      "previous": null
                    },
                    "data": [
                      {
                        "id": 1,
                        "title": "Has a Volume Cover",
                        "type": "manga",
                        "cover": {"raw": {"url": "https://example.com/one.jpg"}}
                      },
                      {
                        "id": 2,
                        "title": "Has No Volume Covers",
                        "type": "manhwa",
                        "cover": {"raw": {"url": "https://example.com/two.jpg"}}
                      }
                    ]
                  }
                  """
            return (response, Data(body.utf8))
        }

        let store = SableMangaBakaCoverStudioStore(
            client: SableMangaBakaCoverClient(session: session)
        )
        store.browseLicenseFilter = .all
        store.browseCoverFilter = .missingCover
        store.browse()

        for _ in 0..<200 where store.isWorking {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertFalse(store.isWorking)
        XCTAssertEqual(requestedImageSeriesIDs, Set([1, 2]))
        XCTAssertEqual(store.results.map(\.id), [2])
        XCTAssertTrue(store.status.contains("1 series with no MangaBaka volume covers"))
        XCTAssertFalse(store.browseHasNextPage)
        XCTAssertEqual(SableMangaBakaBrowseMediaType.manhwa.apiValue, "manhwa")
    }

    func testPublicCoverStatsRequestsOnlyNormalVolumeCovers() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SableMangaBakaURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        SableMangaBakaURLProtocol.handler = { request in
            let components = try XCTUnwrap(
                URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
            )
            let values = Dictionary(
                uniqueKeysWithValues: (components.queryItems ?? []).map {
                    ($0.name, $0.value ?? "")
                }
            )
            XCTAssertEqual(request.url?.path, "/v1/series/85341/images")
            XCTAssertEqual(values["type"], "volume")
            XCTAssertEqual(values["limit"], "50")
            XCTAssertEqual(values["page"], "1")

            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
            )
            let data = Data(
                """
                {
                  "status": 200,
                  "data": [],
                  "pagination": {
                    "count": 7,
                    "page": 1,
                    "limit": 50,
                    "next": null,
                    "previous": null
                  },
                  "available_languages": ["ja", "en"],
                  "available_types": ["volume"]
                }
                """.utf8
            )
            return (response, data)
        }

        let client = SableMangaBakaCoverClient(session: session)
        let stats = try await client.publicVolumeCoverStats(seriesID: 85341)

        XCTAssertEqual(stats.volumeCoverCount, 7)
        XCTAssertEqual(stats.availableLanguages, ["en", "ja"])
    }

    func testLanguageCoverageUsesUniqueNumberedSlotsWithoutMixingLanguages() {
        let stats = SableMangaBakaPublicCoverStats(
            volumeCoverCount: 6,
            availableLanguages: ["en", "ja"],
            volumeCovers: [
                publicCover(id: 1, index: 1, language: "en"),
                publicCover(id: 2, index: 1, language: "en"),
                publicCover(id: 3, index: 3, language: "en"),
                publicCover(id: 4, index: 2, language: "ja"),
                publicCover(id: 5, index: 2, language: "en", type: "chapter"),
                publicCover(id: 6, index: 2.5, language: "en")
            ]
        )

        let english = stats.coverage(language: "en", expectedVolumeCount: 4)
        let japanese = stats.coverage(language: "ja", expectedVolumeCount: 3)

        XCTAssertEqual(english.coveredIndices, [1, 3])
        XCTAssertEqual(english.missingIndices, [2, 4])
        XCTAssertTrue(english.hasConfirmedGap)
        XCTAssertEqual(japanese.coveredIndices, [2])
        XCTAssertEqual(japanese.missingIndices, [1, 3])
    }

    func testUnknownEnglishTotalOnlyReportsVisibleNumberingHoles() {
        let statsWithHole = SableMangaBakaPublicCoverStats(
            volumeCoverCount: 2,
            availableLanguages: ["en"],
            volumeCovers: [
                publicCover(id: 1, index: 1, language: "en"),
                publicCover(id: 2, index: 3, language: "en")
            ]
        )
        let statsWithoutHole = SableMangaBakaPublicCoverStats(
            volumeCoverCount: 2,
            availableLanguages: ["en"],
            volumeCovers: [
                publicCover(id: 3, index: 1, language: "en"),
                publicCover(id: 4, index: 2, language: "en")
            ]
        )

        let gap = statsWithHole.coverage(language: "en", expectedVolumeCount: nil)
        let unknown = statsWithoutHole.coverage(language: "en", expectedVolumeCount: nil)

        XCTAssertEqual(gap.missingIndices, [2])
        XCTAssertTrue(gap.hasConfirmedGap)
        XCTAssertTrue(unknown.missingIndices.isEmpty)
        XCTAssertFalse(unknown.hasConfirmedGap)
        XCTAssertTrue(unknown.isIndeterminate)
        XCTAssertFalse(unknown.isComplete)
    }

    func testLicensedEnglishWorkCountProvidesExpectedVolumeTotal() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SableMangaBakaURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        SableMangaBakaURLProtocol.handler = { request in
            let components = try XCTUnwrap(
                URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
            )
            let values = Dictionary(
                uniqueKeysWithValues: (components.queryItems ?? []).map {
                    ($0.name, $0.value ?? "")
                }
            )
            XCTAssertEqual(request.url?.path, "/v1/series/84926/works")
            XCTAssertEqual(values["page"], "1")
            XCTAssertEqual(values["limit"], "50")

            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
            )
            let data = Data(
                """
                {
                  "status": 200,
                  "data": [{
                    "count_type": "main",
                    "sequence_numeric": 1,
                    "collections": [{
                      "language": {"iso": "ja"},
                      "licensed": false,
                      "count_main": 41
                    }, {
                      "language": {"iso": "en"},
                      "licensed": true,
                      "count_main": 29
                    }]
                  }],
                  "pagination": {
                    "count": 58,
                    "page": 1,
                    "limit": 50,
                    "next": "https://api.mangabaka.org/v1/series/84926/works?page=2",
                    "previous": null
                  }
                }
                """.utf8
            )
            return (response, data)
        }

        let count = try await SableMangaBakaCoverClient(session: session)
            .publicExpectedMainVolumeCount(seriesID: 84926, language: "en")

        XCTAssertEqual(count, 29)
    }

    func testCoverSnapshotUsesLivePublicPreviewWithoutChangingSubmissionSource() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SableMangaBakaURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let retiredSource = "https://images.mangabaka.dev/dropbox/retired.jpg"
        let liveImage = "https://images.mangabaka.dev/3/2/7/c/current"
        SableMangaBakaURLProtocol.handler = { request in
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
            )
            if request.url?.path == "/v0/my/submissions/series-images/85230" {
                return (
                    response,
                    Data(
                        """
                        {
                          "status": 200,
                          "data": {
                            "version": 42,
                            "data": {
                              "images": [{
                                "id": 123261,
                                "series_id": 85230,
                                "url": "\(retiredSource)",
                                "index": "1",
                                "index_numeric": 1,
                                "language": "ja",
                                "type": "volume",
                                "content_rating": "safe",
                                "is_default": true
                              }]
                            }
                          }
                        }
                        """.utf8
                    )
                )
            }

            XCTAssertEqual(request.url?.path, "/v1/series/85230/images")
            let components = try XCTUnwrap(
                URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
            )
            let values = Dictionary(
                uniqueKeysWithValues: (components.queryItems ?? []).map {
                    ($0.name, $0.value ?? "")
                }
            )
            XCTAssertEqual(values["limit"], "50")
            return (
                response,
                Data(
                    """
                    {
                      "status": 200,
                      "data": [{
                        "id": 123261,
                        "index_numeric": 1,
                        "language": "ja",
                        "type": "volume",
                        "image": {
                          "raw": {
                            "url": "\(liveImage)",
                            "width": 1804,
                            "height": 2560
                          }
                        }
                      }],
                      "pagination": {
                        "count": 1,
                        "page": 1,
                        "limit": 100,
                        "next": null,
                        "previous": null
                      },
                      "available_languages": ["ja"]
                    }
                    """.utf8
                )
            )
        }

        let snapshot = try await SableMangaBakaCoverClient(session: session)
            .coverSnapshot(seriesID: 85230, token: "mb-test-token")

        XCTAssertEqual(snapshot.images.first?.url, retiredSource)
        XCTAssertEqual(snapshot.images.first?.previewURL, liveImage)
        XCTAssertEqual(snapshot.images.first?.imageURL?.absoluteString, liveImage)
    }

    func testCoverSnapshotToleratesDuplicatePublicImageIDs() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SableMangaBakaURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let retiredSource = "https://images.mangabaka.dev/dropbox/retired.jpg"
        let liveImage = "https://images.mangabaka.dev/3/2/7/c/current"
        let duplicateLiveImage = "https://images.mangabaka.dev/3/2/7/c/duplicate"
        SableMangaBakaURLProtocol.handler = { request in
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
            )
            if request.url?.path == "/v0/my/submissions/series-images/85231" {
                return (
                    response,
                    Data(
                        """
                        {
                          "status": 200,
                          "data": {
                            "version": 42,
                            "data": {
                              "images": [{
                                "id": 123261,
                                "series_id": 85231,
                                "url": "\(retiredSource)",
                                "index": "1",
                                "index_numeric": 1,
                                "language": "ja",
                                "type": "volume",
                                "content_rating": "safe",
                                "is_default": true
                              }]
                            }
                          }
                        }
                        """.utf8
                    )
                )
            }

            XCTAssertEqual(request.url?.path, "/v1/series/85231/images")
            return (
                response,
                Data(
                    """
                    {
                      "status": 200,
                      "data": [{
                        "id": 123261,
                        "index_numeric": 1,
                        "language": "ja",
                        "type": "volume",
                        "image": {
                          "raw": {
                            "url": "\(liveImage)",
                            "width": 1804,
                            "height": 2560
                          }
                        }
                      }, {
                        "id": 123261,
                        "index_numeric": 1,
                        "language": "ja",
                        "type": "volume",
                        "image": {
                          "raw": {
                            "url": "\(duplicateLiveImage)",
                            "width": 1804,
                            "height": 2560
                          }
                        }
                      }],
                      "pagination": {
                        "count": 2,
                        "page": 1,
                        "limit": 50,
                        "next": null,
                        "previous": null
                      },
                      "available_languages": ["ja"]
                    }
                    """.utf8
                )
            )
        }

        let snapshot = try await SableMangaBakaCoverClient(session: session)
            .coverSnapshot(seriesID: 85231, token: "mb-test-token")

        XCTAssertEqual(snapshot.images.first?.url, retiredSource)
        XCTAssertEqual(snapshot.images.first?.previewURL, liveImage)
        XCTAssertNotEqual(
            snapshot.images.first?.previewURL,
            duplicateLiveImage
        )
    }

    func testCoverInventoryKeepsPublicOnlyChapterOutsideEditableSnapshot() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SableMangaBakaURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        SableMangaBakaURLProtocol.handler = { request in
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
            )

            if request.url?.path == "/v0/my/submissions/series-images/64161" {
                return (
                    response,
                    Data(
                        """
                        {
                          "status": 200,
                          "data": {
                            "version": 9,
                            "data": {
                              "images": [{
                                "id": 133020,
                                "series_id": 64161,
                                "url": "https://res.booklive.jp/20069630/001/thumbnail/X.jpg",
                                "index": "1",
                                "index_numeric": 1,
                                "language": "ja",
                                "type": "volume",
                                "content_rating": "safe",
                                "is_default": true
                              }]
                            }
                          }
                        }
                        """.utf8
                    )
                )
            }

            XCTAssertEqual(request.url?.path, "/v1/series/64161/images")
            return (
                response,
                Data(
                    """
                    {
                      "status": 200,
                      "data": [{
                        "id": 133020,
                        "index_numeric": 1,
                        "language": "ja",
                        "type": "volume",
                        "image": {
                          "raw": {
                            "url": "https://images.mangabaka.dev/volume-1",
                            "width": 1800,
                            "height": 2560
                          }
                        }
                      }, {
                        "id": 133067,
                        "index_numeric": 0,
                        "language": "en",
                        "type": "chapter",
                        "image": {
                          "raw": {
                            "url": "https://images.mangabaka.dev/chapter-0",
                            "width": 1200,
                            "height": 1800
                          }
                        }
                      }],
                      "pagination": {
                        "count": 2,
                        "page": 1,
                        "limit": 50,
                        "next": null,
                        "previous": null
                      },
                      "available_languages": ["ja", "en"]
                    }
                    """.utf8
                )
            )
        }

        let inventory = try await SableMangaBakaCoverClient(session: session)
            .coverInventory(seriesID: 64_161, token: "mb-test-token")

        XCTAssertEqual(inventory.snapshot.images.map(\.id), [133020])
        XCTAssertEqual(inventory.liveImages.map(\.id), [133020, 133067])
        XCTAssertEqual(
            inventory.liveImages.first(where: { $0.id == 133067 })?.inventoryGroup,
            .chapterCovers
        )
    }

    func testPublicCoverStatsRetriesA429Response() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SableMangaBakaURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var requestCount = 0

        SableMangaBakaURLProtocol.handler = { request in
            requestCount += 1
            let statusCode = requestCount == 1 ? 429 : 200
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: statusCode,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
            )
            let data = statusCode == 429
                ? Data(#"{"status":429,"message":"Too many requests"}"#.utf8)
                : Data(
                    """
                    {
                      "status": 200,
                      "data": [],
                      "pagination": {
                        "count": 3,
                        "page": 1,
                        "limit": 50,
                        "next": null,
                        "previous": null
                      },
                      "available_languages": ["ja"],
                      "available_types": ["volume"]
                    }
                    """.utf8
                )
            return (response, data)
        }

        let stats = try await SableMangaBakaCoverClient(session: session)
            .publicVolumeCoverStats(seriesID: 85341)

        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(stats.volumeCoverCount, 3)
    }

    func testSeriesDetailsRetryA429Response() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SableMangaBakaURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var requestCount = 0

        SableMangaBakaURLProtocol.handler = { request in
            requestCount += 1
            let statusCode = requestCount == 1 ? 429 : 200
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: statusCode,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
            )
            let data = statusCode == 429
                ? Data(#"{"status":429,"message":"Too many requests"}"#.utf8)
                : Data(
                    """
                    {
                      "status": 200,
                      "data": {
                        "id": 86007,
                        "title": "As The Villainess, I Reject These Happy-Bad Endings!",
                        "type": "novel",
                        "final_volume": "2"
                      }
                    }
                    """.utf8
                )
            return (response, data)
        }

        let series = try await SableMangaBakaCoverClient(session: session)
            .series(id: 86007)

        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(series.id, 86007)
        XCTAssertEqual(series.type, "novel")
    }

    func testStorefrontDiscoveryUsesJapaneseTitlesForJapaneseStores() {
        let series = SableMangaBakaSeriesSummary(
            id: 86007,
            title: "As The Villainess, I Reject These Happy-Bad Endings!",
            nativeTitle: "私が聖女？いいえ、悪役令嬢です！",
            romanizedTitle: "Watashi ga Seijo",
            titles: [
                SableMangaBakaSeriesTitle(
                    language: "en",
                    traits: ["official"],
                    title: "As The Villainess, I Reject These Happy-Bad Endings!",
                    isPrimary: true
                ),
                SableMangaBakaSeriesTitle(
                    language: "ja",
                    traits: ["native"],
                    title: "私が聖女？いいえ、悪役令嬢です！",
                    isPrimary: true
                ),
                SableMangaBakaSeriesTitle(
                    language: "fr",
                    traits: ["official"],
                    title: "Moi, une sainte ? Non, une méchante !",
                    isPrimary: true
                ),
                SableMangaBakaSeriesTitle(
                    language: "ko",
                    traits: ["official"],
                    title: "내가 성녀라고요? 아니요, 악역 영애입니다!",
                    isPrimary: true
                )
            ],
            type: "novel",
            cover: nil,
            finalVolume: "2"
        )

        XCTAssertEqual(
            SableMangaBakaStorefrontDiscovery.preferredQuery(
                for: .bookLiveJP,
                series: series
            ),
            "私が聖女？いいえ、悪役令嬢です！"
        )
        XCTAssertEqual(
            SableMangaBakaStorefrontDiscovery.preferredQuery(
                for: .bookWalkerGlobal,
                series: series
            ),
            "As The Villainess, I Reject These Happy-Bad Endings!"
        )
        XCTAssertEqual(
            SableMangaBakaStorefrontDiscovery.preferredQuery(
                for: .amazonFrance,
                series: series
            ),
            "Moi, une sainte ? Non, une méchante !"
        )
        XCTAssertEqual(
            SableMangaBakaStorefrontDiscovery.preferredQuery(
                for: .aladin,
                series: series
            ),
            "내가 성녀라고요? 아니요, 악역 영애입니다!"
        )
    }

    func testJapaneseStorefrontPrefersKanaAlternativeOverLatinPrimary() {
        let series = SableMangaBakaSeriesSummary(
            id: 725,
            title: "ONE-PUNCH MAN",
            nativeTitle: "ONE PUNCH-MAN",
            romanizedTitle: "Wanpanman",
            titles: [
                SableMangaBakaSeriesTitle(
                    language: "ja",
                    traits: ["native"],
                    title: "ONE PUNCH-MAN",
                    isPrimary: true
                ),
                SableMangaBakaSeriesTitle(
                    language: "ja",
                    traits: ["alternative"],
                    title: "ワンパンマン",
                    isPrimary: false
                )
            ],
            type: "manga",
            cover: nil
        )

        XCTAssertEqual(
            SableMangaBakaStorefrontDiscovery.preferredQuery(
                for: .bookLiveJP,
                series: series
            ),
            "ワンパンマン"
        )
    }

    func testJapaneseStorefrontPrefersCleanNativeTitleOverLongAlias() throws {
        let cleanTitle =
            "ループ7回目の悪役令嬢は、元敵国で自由気ままな花嫁生活を満喫する"
        let longAlias =
            "ループ7回目の悪役令嬢は、元敵国で自由気ままな花嫁（人質）生活を満喫する"
        let series = SableMangaBakaSeriesSummary(
            id: 369,
            title: "7th Time Loop: The Villainess Enjoys a Carefree Life",
            nativeTitle: cleanTitle,
            romanizedTitle: nil,
            titles: [
                SableMangaBakaSeriesTitle(
                    language: "ja",
                    traits: ["official"],
                    title: longAlias,
                    isPrimary: true
                )
            ],
            type: "manga",
            cover: nil
        )

        XCTAssertEqual(
            SableMangaBakaStorefrontDiscovery.preferredQuery(
                for: .bookLiveJP,
                series: series
            ),
            cleanTitle
        )

        let rolerURL = try XCTUnwrap(
            SableMangaBakaStorefrontDiscovery.rolerSearchURL(
                for: series,
                language: "ja"
            )
        )
        let components = try XCTUnwrap(
            URLComponents(url: rolerURL, resolvingAgainstBaseURL: false)
        )
        XCTAssertEqual(
            components.queryItems?.first(where: { $0.name == "q" })?.value,
            cleanTitle
        )
    }

    func testEnglishProviderSearchAddsOneConciseBBCFallback() {
        let reZero = SableMangaBakaSeriesSummary(
            id: 84_926,
            title: "Re:Zero -Starting Life in Another World-",
            nativeTitle: "Re:ゼロから始める異世界生活",
            romanizedTitle: nil,
            titles: [
                SableMangaBakaSeriesTitle(
                    language: "en",
                    traits: ["official"],
                    title: "Re:Zero -Starting Life in Another World-",
                    isPrimary: true
                )
            ],
            type: "novel",
            cover: nil
        )
        let seventhLoop = SableMangaBakaSeriesSummary(
            id: 84_345,
            title:
                "7th Time Loop: The Villainess Enjoys a Carefree Life Married to Her Worst Enemy!",
            nativeTitle: nil,
            romanizedTitle: nil,
            type: "novel"
        )

        XCTAssertEqual(
            SableMangaBakaStorefrontDiscovery.providerSearchQueries(
                for: .bookWalkerGlobal,
                series: reZero
            ),
            [
                "Re:Zero -Starting Life in Another World-",
                "Re:Zero"
            ]
        )
        XCTAssertEqual(
            SableMangaBakaStorefrontDiscovery.providerSearchQueries(
                for: .amazon,
                series: seventhLoop
            ),
            [
                "7th Time Loop: The Villainess Enjoys a Carefree Life Married to Her Worst Enemy!",
                "7th Time Loop"
            ]
        )
        XCTAssertEqual(
            SableMangaBakaStorefrontDiscovery.providerSearchQueries(
                for: .bookLiveJP,
                series: reZero
            ),
            ["Re:ゼロから始める異世界生活"]
        )
    }

    func testConciseBBCFallbackOutranksNoisyLongTitleResults() {
        let irrelevant = SableLibraryBigBookCoversSeriesCandidate(
            provider: .bookWalkerGlobal,
            id: "unrelated",
            title: "My Quiet Blacksmith Life in Another World",
            url: "https://bookwalker.com/series/unrelated",
            type: "series",
            bookType: "novel",
            thumbnailURL: nil
        )
        let reZero = SableLibraryBigBookCoversSeriesCandidate(
            provider: .bookWalkerGlobal,
            id: "CNT_3Y7A6PRYA270",
            title: "Re:ZERO -Starting Life in Another World-",
            url: "https://bookwalker.com/series/3Y7A6PRYA270",
            type: "series",
            bookType: "novel",
            thumbnailURL: nil
        )

        let ranked = SableLibraryCoverDownloadPlanner
            .rankedSeriesCandidates(
                for: "Re:Zero -Starting Life in Another World-",
                in: [irrelevant, reZero],
                mediaType: "novel"
            )

        XCTAssertEqual(ranked.first?.id, reZero.id)
    }

    func testRolerSearchURLsUseLanguageSpecificTitlesAndProviders() throws {
        let series = SableMangaBakaSeriesSummary(
            id: 188_016,
            title: "Agents of the Four Seasons",
            nativeTitle: "春夏秋冬代行者 百歌百葉",
            romanizedTitle: "Shunkashuutou Daikousha",
            titles: [
                SableMangaBakaSeriesTitle(
                    language: "en",
                    traits: ["official"],
                    title: "Agents of the Four Seasons",
                    isPrimary: true
                ),
                SableMangaBakaSeriesTitle(
                    language: "ja",
                    traits: ["official"],
                    title: "春夏秋冬代行者 百歌百葉",
                    isPrimary: true
                ),
                SableMangaBakaSeriesTitle(
                    language: "ko",
                    traits: ["official"],
                    title: "봄과 여름과 가을과 겨울의 대리인",
                    isPrimary: true
                )
            ],
            type: "manga",
            cover: nil,
            finalVolume: nil
        )

        let japaneseURL = try XCTUnwrap(
            SableMangaBakaStorefrontDiscovery.rolerSearchURL(
                for: series,
                language: "ja"
            )
        )
        let japaneseComponents = try XCTUnwrap(
            URLComponents(url: japaneseURL, resolvingAgainstBaseURL: false)
        )
        XCTAssertEqual(
            japaneseComponents.queryItems?.first(where: { $0.name == "q" })?.value,
            "春夏秋冬代行者 百歌百葉"
        )
        XCTAssertEqual(
            japaneseComponents.queryItems?
                .first(where: { $0.name == "providerLocale" })?.value,
            "ja"
        )
        let japaneseProviders = japaneseComponents.queryItems?
            .filter { $0.name == "provider" }
            .compactMap(\.value)
        XCTAssertEqual(
            japaneseProviders,
            ["bl", "bw", "bl-r", "bw-r", "bw-wa", "bw-war", "amz-jp", "ebj", "cmoa"]
        )

        let englishURL = try XCTUnwrap(
            SableMangaBakaStorefrontDiscovery.rolerSearchURL(
                for: series,
                language: "en"
            )
        )
        let englishComponents = try XCTUnwrap(
            URLComponents(url: englishURL, resolvingAgainstBaseURL: false)
        )
        XCTAssertEqual(
            englishComponents.queryItems?.first(where: { $0.name == "q" })?.value,
            "Agents of the Four Seasons"
        )
        XCTAssertEqual(
            englishComponents.queryItems?
                .first(where: { $0.name == "providerLocale" })?.value,
            "en"
        )
        XCTAssertEqual(
            englishComponents.queryItems?
                .filter { $0.name == "provider" }
                .compactMap(\.value),
            ["bw-g", "bw-gr", "amz", "amz-uk"]
        )
        let koreanURL = try XCTUnwrap(
            SableMangaBakaStorefrontDiscovery.rolerSearchURL(
                for: series,
                language: "ko"
            )
        )
        let koreanComponents = try XCTUnwrap(
            URLComponents(url: koreanURL, resolvingAgainstBaseURL: false)
        )
        XCTAssertEqual(
            koreanComponents.queryItems?.first(where: { $0.name == "q" })?.value,
            "봄과 여름과 가을과 겨울의 대리인"
        )
        XCTAssertEqual(
            koreanComponents.queryItems?
                .first(where: { $0.name == "providerLocale" })?.value,
            "ko"
        )
        XCTAssertEqual(
            koreanComponents.queryItems?
                .filter { $0.name == "provider" }
                .compactMap(\.value),
            ["aladin", "ridi"]
        )

        let yes24URL = try XCTUnwrap(
            SableMangaBakaStorefrontDiscovery.koreanStoreSearchURL(
                for: series,
                provider: .yes24
            )
        )
        let yes24Components = try XCTUnwrap(
            URLComponents(url: yes24URL, resolvingAgainstBaseURL: false)
        )
        XCTAssertEqual(yes24Components.host, "www.yes24.com")
        XCTAssertEqual(
            yes24Components.queryItems?
                .first(where: { $0.name == "query" })?.value,
            "봄과 여름과 가을과 겨울의 대리인"
        )

        let kyoboURL = try XCTUnwrap(
            SableMangaBakaStorefrontDiscovery.koreanStoreSearchURL(
                for: series,
                provider: .kyobo
            )
        )
        let kyoboComponents = try XCTUnwrap(
            URLComponents(url: kyoboURL, resolvingAgainstBaseURL: false)
        )
        XCTAssertEqual(kyoboComponents.host, "search.kyobobook.co.kr")
        XCTAssertEqual(
            kyoboComponents.queryItems?
                .first(where: { $0.name == "keyword" })?.value,
            "봄과 여름과 가을과 겨울의 대리인"
        )
    }

    func testStorefrontGroupKeepsSiblingArcsOutOfScopedMangaBakaSeries() {
        let series = SableMangaBakaSeriesSummary(
            id: 188_016,
            title: "Shunkashuutou Daikousha: Tasogare no Shashu",
            nativeTitle: "春夏秋冬代行者 黄昏の射手",
            romanizedTitle: "Shunkashuutou Daikousha",
            titles: [
                SableMangaBakaSeriesTitle(
                    language: "en",
                    traits: ["official"],
                    title: "Agents of the Four Seasons",
                    isPrimary: true
                ),
                SableMangaBakaSeriesTitle(
                    language: "ja",
                    traits: [],
                    title: "春夏秋冬代行者",
                    isPrimary: false
                ),
                SableMangaBakaSeriesTitle(
                    language: "ja",
                    traits: ["native"],
                    title: "春夏秋冬代行者 黄昏の射手",
                    isPrimary: true
                )
            ],
            type: "novel",
            cover: nil,
            finalVolume: "1"
        )
        let japaneseBooks = [
            storefrontBook(
                id: "spring",
                title: "春夏秋冬代行者 春の舞 上",
                sequence: 1
            ),
            storefrontBook(
                id: "twilight",
                title: "春夏秋冬代行者 黄昏の射手",
                sequence: 8
            ),
            storefrontBook(
                id: "summer",
                title: "春夏秋冬代行者 夏の舞 下",
                sequence: 4
            )
        ]

        let japanese = SableMangaBakaStorefrontDiscovery.booksScopedToSelectedSeries(
            japaneseBooks,
            series: series,
            language: "ja"
        )
        let english = SableMangaBakaStorefrontDiscovery.booksScopedToSelectedSeries(
            [
                storefrontBook(
                    id: "en-1",
                    title: "Agents of the Four Seasons, Volume 1",
                    sequence: 1
                ),
                storefrontBook(
                    id: "en-2",
                    title: "Agents of the Four Seasons, Volume 2",
                    sequence: 2
                )
            ],
            series: series,
            language: "en"
        )
        let wrongSingle = SableMangaBakaStorefrontDiscovery.booksScopedToSelectedSeries(
            [
                storefrontBook(
                    id: "wrong-single",
                    title: "春夏秋冬代行者 春の舞 上",
                    sequence: 1
                )
            ],
            series: series,
            language: "ja"
        )

        XCTAssertEqual(japanese.map(\.id), ["twilight"])
        XCTAssertEqual(japanese.map(\.volumeNumber), [1])
        XCTAssertTrue(english.isEmpty)
        XCTAssertTrue(wrongSingle.isEmpty)
    }

    func testTransliteratedLongTitleDoesNotTurnOneSeriesIntoSiblingArcs() {
        let series = SableMangaBakaSeriesSummary(
            id: 82_822,
            title: "If the Villainess and Villain Met and Fell in Love",
            nativeTitle:
                "悪役令嬢と悪役令息が、出逢って恋に落ちたなら　～名無しの精霊と契約して追い出された令嬢は、今日も令息と競い合っているようです～",
            romanizedTitle:
                "Akuyaku Reijou to Akuyaku Reisoku ga, Deatte Koi ni Ochitanara",
            titles: [
                SableMangaBakaSeriesTitle(
                    language: "ja-Latn",
                    traits: [],
                    title:
                        "Akuyaku Reijou to Akuyaku Reisoku ga, Deatte Koi ni Ochitanara",
                    isPrimary: false
                ),
                SableMangaBakaSeriesTitle(
                    language: "ja-Latn",
                    traits: ["native"],
                    title:
                        "Akuyaku Reijou to Akuyaku Reisoku ga, Deatte Koi ni Ochita Nara: Nanashi no Seirei to Keiyakushite Oidasareta Reijou wa, Kyou mo Reisoku to Kisoiatteiru Youdesu",
                    isPrimary: true
                ),
                SableMangaBakaSeriesTitle(
                    language: "en",
                    traits: [],
                    title:
                        "If the Villainess and the Villain Were to Meet and Fall in Love",
                    isPrimary: false
                ),
                SableMangaBakaSeriesTitle(
                    language: "en",
                    traits: ["official"],
                    title: "If the Villainess and Villain Met and Fell in Love",
                    isPrimary: true
                ),
                SableMangaBakaSeriesTitle(
                    language: "ja",
                    traits: ["native"],
                    title:
                        "悪役令嬢と悪役令息が、出逢って恋に落ちたなら　～名無しの精霊と契約して追い出された令嬢は、今日も令息と競い合っているようです～",
                    isPrimary: true
                )
            ],
            type: "novel",
            cover: nil,
            finalVolume: "6",
            status: "completed"
        )
        let japaneseBooks = (1...6).map { volume in
            storefrontBook(
                id: "booklive-\(volume)",
                title:
                    "悪役令嬢と悪役令息が、出逢って恋に落ちたなら\(volume == 1 ? "" : String(volume))　～名無しの精霊と契約して追い出された令嬢は、今日も令息と競い合っているようです～",
                sequence: volume
            )
        }
        let englishBooks = (1...5).map { volume in
            storefrontBook(
                id: "bookwalker-global-\(volume)",
                title: "If the Villainess and Villain Met and Fell in Love, Volume \(volume)",
                sequence: volume
            )
        }

        let japanese = SableMangaBakaStorefrontDiscovery.providerBooksForReview(
            japaneseBooks,
            series: series,
            language: "ja",
            trustsSelectedSeriesIdentity: false
        )
        let english = SableMangaBakaStorefrontDiscovery.providerBooksForReview(
            englishBooks,
            series: series,
            language: "en",
            trustsSelectedSeriesIdentity: false
        )

        XCTAssertEqual(japanese.books.map(\.id), (1...6).map { "booklive-\($0)" })
        XCTAssertEqual(japanese.books.map(\.volumeNumber), [1, 2, 3, 4, 5, 6])
        XCTAssertFalse(japanese.requiresRelationshipReview)
        XCTAssertEqual(
            english.books.map(\.id),
            (1...5).map { "bookwalker-global-\($0)" }
        )
        XCTAssertEqual(english.books.map(\.volumeNumber), [1, 2, 3, 4, 5])
        XCTAssertFalse(english.requiresRelationshipReview)
    }

    func testReleasingSeriesDoesNotUseStaleFinalVolumeAsHardLimit() {
        let series = SableMangaBakaSeriesSummary(
            id: 64_161,
            title: "Agents of the Four Seasons",
            nativeTitle: "春夏秋冬代行者 百歌百葉",
            romanizedTitle: "Shunkashuutou Daikousha: Hyakka Hyakuyou",
            titles: [
                SableMangaBakaSeriesTitle(
                    language: "ja",
                    traits: ["native"],
                    title: "春夏秋冬代行者 百歌百葉",
                    isPrimary: true
                )
            ],
            type: "manga",
            cover: nil,
            finalVolume: "2",
            status: "releasing"
        )
        let books = (1...3).map {
            storefrontBook(
                id: "booklive-\($0)",
                title: "春夏秋冬代行者 百歌百葉\($0)",
                sequence: $0
            )
        }

        let scoped = SableMangaBakaStorefrontDiscovery
            .booksScopedToSelectedSeries(
                books,
                series: series,
                language: "ja"
            )

        XCTAssertEqual(
            scoped.map(\.id),
            ["booklive-1", "booklive-2", "booklive-3"]
        )
        XCTAssertEqual(scoped.map(\.volumeNumber), [1, 2, 3])
    }

    func testScopedSeriesKeepsExplicitStoreVolumeNumbersInsteadOfRowPositions() {
        let series = SableMangaBakaSeriesSummary(
            id: 59_029,
            title: "Agents of the Four Seasons",
            nativeTitle: "春夏秋冬代行者 春の舞",
            romanizedTitle: nil,
            titles: [
                SableMangaBakaSeriesTitle(
                    language: "ja",
                    traits: ["native"],
                    title: "春夏秋冬代行者 春の舞",
                    isPrimary: true
                )
            ],
            type: "manga",
            cover: nil,
            finalVolume: nil,
            status: "releasing"
        )
        let books = [
            storefrontBook(
                id: "bookwalker-5",
                title: "春夏秋冬代行者　春の舞　5巻",
                sequence: 6
            ),
            storefrontBook(
                id: "bookwalker-8",
                title: "春夏秋冬代行者  春の舞  8巻",
                sequence: 9
            )
        ]

        let scoped = SableMangaBakaStorefrontDiscovery
            .booksScopedToSelectedSeries(
                books,
                series: series,
                language: "ja"
            )

        XCTAssertEqual(scoped.map(\.id), ["bookwalker-5", "bookwalker-8"])
        XCTAssertEqual(scoped.map(\.volumeNumber), [5, 8])
    }

    func testScopedSeriesReadsFormalJapaneseVolumeNumbersInsteadOfRowPositions() {
        let series = SableMangaBakaSeriesSummary(
            id: 83_982,
            title: "Hell Is Dark with No Flowers",
            nativeTitle: "地獄くらやみ花もなき",
            romanizedTitle: nil,
            titles: [
                SableMangaBakaSeriesTitle(
                    language: "ja",
                    traits: ["native"],
                    title: "地獄くらやみ花もなき",
                    isPrimary: true
                )
            ],
            type: "novel",
            cover: nil,
            finalVolume: "8",
            status: "complete"
        )
        let titles = [
            "地獄くらやみ花もなき",
            "地獄くらやみ花もなき　伍　雨の金魚、昏い隠れ鬼",
            "地獄くらやみ花もなき　参　蛇喰らう宿",
            "地獄くらやみ花もなき　弐　生き人形の島",
            "地獄くらやみ花もなき　捌　冥がりの呪花、雨の夜語り",
            "地獄くらやみ花もなき　漆　闇夜に吠える犬",
            "地獄くらやみ花もなき　肆　百鬼疾る夜行列車",
            "地獄くらやみ花もなき　陸　黒猫の鳴く獄舎"
        ]
        let books = titles.enumerated().map { offset, title in
            storefrontBook(
                id: "bookwalker-\(offset + 1)",
                title: title,
                sequence: offset + 1
            )
        }

        let scoped = SableMangaBakaStorefrontDiscovery
            .booksScopedToSelectedSeries(
                books,
                series: series,
                language: "ja"
            )

        XCTAssertEqual(
            scoped.map(\.volumeNumber),
            [1, 5, 3, 2, 8, 7, 4, 6]
        )
    }

    func testExactStoreSeriesReadsFormalJapaneseVolumeNumbers() {
        let series = SableMangaBakaSeriesSummary(
            id: 83_982,
            title: "Hell Is Dark with No Flowers",
            nativeTitle: "地獄くらやみ花もなき",
            romanizedTitle: nil,
            titles: nil,
            type: "novel",
            cover: nil,
            finalVolume: "8"
        )
        let books = [
            storefrontBook(
                id: "bookwalker-five",
                title: "地獄くらやみ花もなき　伍　雨の金魚、昏い隠れ鬼",
                sequence: 2
            ),
            storefrontBook(
                id: "bookwalker-two",
                title: "地獄くらやみ花もなき　弐　生き人形の島",
                sequence: 4
            )
        ]

        let scoped = SableMangaBakaStorefrontDiscovery
            .booksScopedToExactStoreSeries(
                books,
                series: series,
                language: "ja"
            )

        XCTAssertEqual(scoped.map(\.volumeNumber), [5, 2])
    }

    func testFormalJapaneseVolumeParserDoesNotTreatSeriesTitleAsVolume() {
        XCTAssertEqual(
            SableLibraryCoverDownloadPlanner.explicitVolumeNumber(
                in: "地獄くらやみ花もなき　捌　冥がりの呪花、雨の夜語り",
                afterSeriesTitle: "地獄くらやみ花もなき"
            ),
            8
        )
        XCTAssertNil(
            SableLibraryCoverDownloadPlanner.explicitVolumeNumber(
                in: "八男って、それはないでしょう！",
                afterSeriesTitle: "八男って、それはないでしょう！"
            )
        )
    }

    func testBookWalkerBunkoPageProvesNovel() {
        let html = """
        <html><head><title>地獄くらやみ花もなき | BOOK☆WALKER</title></head>
        <body>
        <div>カテゴリ：文芸・小説</div>
        <div>レーベル：角川文庫</div>
        </body></html>
        """

        XCTAssertEqual(
            SableMangaBakaStorefrontDiscovery.storefrontMediaTypeProof(
                title: "地獄くらやみ花もなき",
                html: html
            ),
            "novel"
        )
    }

    func testCompletedSeriesStillUsesFinalVolumeAsHardLimit() {
        let series = SableMangaBakaSeriesSummary(
            id: 64_161,
            title: "Agents of the Four Seasons",
            nativeTitle: "春夏秋冬代行者 百歌百葉",
            romanizedTitle: nil,
            titles: [
                SableMangaBakaSeriesTitle(
                    language: "ja",
                    traits: ["native"],
                    title: "春夏秋冬代行者 百歌百葉",
                    isPrimary: true
                )
            ],
            type: "manga",
            cover: nil,
            finalVolume: "2",
            status: "completed"
        )
        let books = (1...3).map {
            storefrontBook(
                id: "booklive-\($0)",
                title: "春夏秋冬代行者 百歌百葉\($0)",
                sequence: $0
            )
        }

        let scoped = SableMangaBakaStorefrontDiscovery
            .booksScopedToSelectedSeries(
                books,
                series: series,
                language: "ja"
            )

        XCTAssertEqual(scoped.map(\.id), ["booklive-1", "booklive-2"])
    }

    func testBookLiveProductFamilyParserKeepsEveryVisibleVolume() {
        let html = """
        <div class="picture"><a href="/product/index/title_id/1053549/vol_no/001"><img src="https://res.booklive.jp/1053549/001/thumbnail/M.jpg" alt="悪役令嬢と悪役令息が、出逢って恋に落ちたなら"></a></div>
        <div class="picture"><a href="/product/index/title_id/1053549/vol_no/002"><img src="https://res.booklive.jp/1053549/002/thumbnail/M.jpg" alt="悪役令嬢と悪役令息が、出逢って恋に落ちたなら２"></a></div>
        <div class="picture"><a href="/product/index/title_id/1053549/vol_no/003"><img src="https://res.booklive.jp/1053549/003/thumbnail/M.jpg" alt="悪役令嬢と悪役令息が、出逢って恋に落ちたなら３"></a></div>
        <div class="picture"><a href="/product/index/title_id/1053549/vol_no/004"><img src="https://res.booklive.jp/1053549/004/thumbnail/M.jpg" alt="悪役令嬢と悪役令息が、出逢って恋に落ちたなら４"></a></div>
        <div class="picture"><a href="/product/index/title_id/1053549/vol_no/005"><img src="https://res.booklive.jp/1053549/005/thumbnail/M.jpg" alt="悪役令嬢と悪役令息が、出逢って恋に落ちたなら５"></a></div>
        <div class="picture"><a href="/product/index/title_id/1053549/vol_no/006"><img src="https://res.booklive.jp/1053549/006/thumbnail/M.jpg" alt="悪役令嬢と悪役令息が、出逢って恋に落ちたなら６"></a></div>
        """

        let books = SableLibraryBookLiveSeriesGroupClient.productFamilyBooks(
            from: html,
            titleID: "1053549",
            bookType: "novel"
        )

        XCTAssertEqual(books.map(\.volumeNumber), [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(
            books.last?.coverURL,
            "https://res.booklive.jp/1053549/006/thumbnail/X.jpg"
        )
    }

    func testBookLiveProductFamilyMergeKeepsStorefrontSiblingsAndBBCAlternatives() {
        let storefrontBooks = (1...9).map { volume in
            SableLibraryBigBookCoversBookCandidate(
                provider: .bookLiveJP,
                id: "456224-\(String(format: "%03d", volume))",
                seriesID: "456224",
                title: "BookLive item \(volume)",
                url:
                    "https://booklive.jp/product/index/title_id/456224/vol_no/\(String(format: "%03d", volume))",
                coverURL:
                    "https://res.booklive.jp/456224/\(String(format: "%03d", volume))/thumbnail/X.jpg",
                coverFallbackURLs: [],
                volumeNumber: Double(volume),
                volumeType: "volume",
                sequenceIndex: volume,
                bookType: "manga"
            )
        }
        let bbcBooks = [1, 2, 5].map { volume in
            SableLibraryBigBookCoversBookCandidate(
                provider: .bookLiveJP,
                id: "456224-\(String(format: "%03d", volume))",
                seriesID: "456224",
                title: "BBC item \(volume)",
                url:
                    "https://booklive.jp/product/index/title_id/456224/vol_no/\(String(format: "%03d", volume))",
                coverURL: "https://c.roler.dev/bl/456224-\(String(format: "%03d", volume))/0",
                coverFallbackURLs: [],
                volumeNumber: Double(volume),
                volumeType: "volume",
                sequenceIndex: volume,
                bookType: "manga"
            )
        }

        let merged = SableMangaBakaStorefrontDiscovery
            .mergedBookLiveProductFamilyBooks(
                storefrontBooks: storefrontBooks,
                bbcBooks: bbcBooks,
                fallbackMediaType: "manga"
            )

        XCTAssertEqual(merged.count, 9)
        XCTAssertEqual(merged.map(\.volumeNumber), (1...9).map(Double.init))
        XCTAssertEqual(
            merged[4].coverFallbackURLs,
            ["https://c.roler.dev/bl/456224-005/0"]
        )
    }

    func testExactStoreSeriesURLsRecognizeSupportedProductAndSeriesLinks() {
        let bookLive = SableMangaBakaStorefrontDiscovery.storeSeriesReference(
            from:
                "https://booklive.jp/product/index/title_id/20069630/vol_no/001"
        )
        let bookWalker =
            SableMangaBakaStorefrontDiscovery.storeSeriesReference(
                from:
                    "https://bookwalker.com/series/1TZHZ2EGA8T0/agents-of-the-four-seasons-one-hundred-songs-and-one-hundred-pages"
            )
        let amazonSeries =
            SableMangaBakaStorefrontDiscovery.storeSeriesReference(
                from:
                    "https://www.amazon.com/dp/B0D83KNC25?binding=kindle_edition"
            )
        let amazonBook =
            SableMangaBakaStorefrontDiscovery.storeSeriesReference(
                from:
                    "https://www.amazon.com/Agents-Four-Seasons-Dance-Spring-ebook/dp/B0D8138N51/ref=sr_1_5"
            )
        let barnesNoble =
            SableMangaBakaStorefrontDiscovery.storeSeriesReference(
                from:
                    "https://www.barnesandnoble.com/w/one-punch-man-vol-2-one/1122136149?ean=9781421577418"
            )
        let barnesNobleSeries =
            SableMangaBakaStorefrontDiscovery.storeSeriesReference(
                from:
                    "https://www.barnesandnoble.com/series/one-punch-man-series"
            )
        let yes24 = SableMangaBakaStorefrontDiscovery.storeSeriesReference(
            from: "https://www.yes24.com/product/goods/176008933"
        )
        let kyobo = SableMangaBakaStorefrontDiscovery.storeSeriesReference(
            from:
                "https://ebook-product.kyobobook.co.kr/dig/epd/ebook/E000002950013"
        )
        let kyoboPrint =
            SableMangaBakaStorefrontDiscovery.storeSeriesReference(
                from:
                    "https://product.kyobobook.co.kr/detail/S000214458961"
            )

        XCTAssertEqual(bookLive?.provider, .bookLiveJP)
        XCTAssertEqual(bookLive?.itemID, "20069630")
        XCTAssertEqual(bookLive?.itemType, "productFamily")
        XCTAssertEqual(bookWalker?.provider, .bookWalkerGlobal)
        XCTAssertEqual(bookWalker?.itemID, "CNT_1TZHZ2EGA8T0")
        XCTAssertEqual(bookWalker?.itemType, "series")
        XCTAssertEqual(amazonSeries?.provider, .amazon)
        XCTAssertEqual(amazonSeries?.itemID, "B0D83KNC25")
        XCTAssertEqual(amazonSeries?.itemType, "series")
        XCTAssertEqual(amazonBook?.provider, .amazon)
        XCTAssertEqual(amazonBook?.itemID, "B0D8138N51")
        XCTAssertEqual(amazonBook?.itemType, "book")
        XCTAssertEqual(barnesNoble?.provider, .barnesNobleUS)
        XCTAssertEqual(barnesNoble?.itemID, "9781421577418")
        XCTAssertEqual(barnesNoble?.itemType, "book")
        XCTAssertEqual(barnesNobleSeries?.provider, .barnesNobleUS)
        XCTAssertEqual(barnesNobleSeries?.itemID, "one-punch-man-series")
        XCTAssertEqual(barnesNobleSeries?.itemType, "series")
        XCTAssertEqual(yes24?.provider, .yes24)
        XCTAssertEqual(yes24?.itemID, "176008933")
        XCTAssertEqual(yes24?.itemType, "book")
        XCTAssertEqual(yes24?.languageOverride, "ko")
        XCTAssertEqual(kyobo?.provider, .kyobo)
        XCTAssertEqual(kyobo?.itemID, "E000002950013")
        XCTAssertEqual(kyobo?.itemType, "book")
        XCTAssertEqual(kyobo?.languageOverride, "ko")
        XCTAssertEqual(kyobo?.publicationTypeOverride, "digital")
        XCTAssertEqual(kyoboPrint?.provider, .kyobo)
        XCTAssertEqual(kyoboPrint?.itemID, "S000214458961")
        XCTAssertEqual(kyoboPrint?.itemType, "book")
        XCTAssertEqual(kyoboPrint?.languageOverride, "ko")
        XCTAssertNil(kyoboPrint?.publicationTypeOverride)
    }

    func testExactAmazonStoreURLsPreserveRegionalProvider() {
        let japan = SableMangaBakaStorefrontDiscovery.storeSeriesReference(
            from: "https://www.amazon.co.jp/gp/product/B0CJF9965P"
        )
        let unitedKingdom =
            SableMangaBakaStorefrontDiscovery.storeSeriesReference(
                from:
                    "https://www.amazon.co.uk/kindle-dbs/product/B0D83KNC25"
            )
        let germany = SableMangaBakaStorefrontDiscovery.storeSeriesReference(
            from: "https://www.amazon.de/dp/B0D83KNC25?binding=kindle_edition"
        )

        XCTAssertEqual(japan?.provider, .amazonJP)
        XCTAssertEqual(japan?.itemID, "B0CJF9965P")
        XCTAssertEqual(japan?.itemType, "book")
        XCTAssertEqual(unitedKingdom?.provider, .amazonUK)
        XCTAssertEqual(unitedKingdom?.itemType, "series")
        XCTAssertEqual(germany?.provider, .amazonGermany)
        XCTAssertEqual(germany?.itemType, "series")
    }

    func testExactAmazonProductAndSeriesURLsPreserveTheUserChosenScope() {
        let product = SableMangaBakaStorefrontDiscovery.storeSeriesReference(
            from:
                "https://www.amazon.co.uk/gp/product/B0G34PSB1C?storeType=ebooks"
        )
        let series = SableMangaBakaStorefrontDiscovery.storeSeriesReference(
            from:
                "https://www.amazon.com/dp/B0G4S8K7LN?binding=kindle_edition"
        )

        XCTAssertEqual(product?.provider, .amazonUK)
        XCTAssertEqual(product?.itemID, "B0G34PSB1C")
        XCTAssertEqual(product?.itemType, "book")
        XCTAssertEqual(product?.publicationTypeOverride, "digital")
        XCTAssertEqual(series?.provider, .amazon)
        XCTAssertEqual(series?.itemID, "B0G4S8K7LN")
        XCTAssertEqual(series?.itemType, "series")
        XCTAssertEqual(series?.publicationTypeOverride, "digital")
    }

    func testExactAmazonBookKeepsOnlyThePastedASINAndURL() throws {
        let reference = try XCTUnwrap(
            SableMangaBakaStorefrontDiscovery.storeSeriesReference(
                from:
                    "https://www.amazon.com/gp/product/B0G34PSB1C?storeType=ebooks"
            )
        )
        let rows = [
            SableLibraryBigBookCoversBookCandidate(
                provider: .amazon,
                id: "B0G34PSB1C",
                seriesID: nil,
                title:
                    "Early Years: The Beginning After the End: (Remastered Edition)",
                url: "https://www.amazon.com/dp/B0G34PSB1C",
                coverURL: "https://images.example/ebook.jpg",
                coverFallbackURLs: [],
                volumeNumber: nil,
                volumeType: "volume",
                sequenceIndex: 1,
                bookType: nil,
                publicationType: nil
            ),
            SableLibraryBigBookCoversBookCandidate(
                provider: .amazon,
                id: "B0DH5Y8HSF",
                seriesID: "B0AUDIBLE1",
                title: "Early Years: Audible Audio Edition",
                url: "https://www.amazon.com/dp/B0DH5Y8HSF",
                coverURL: "https://images.example/audiobook.jpg",
                coverFallbackURLs: [],
                volumeNumber: 1,
                volumeType: "volume",
                sequenceIndex: 2,
                bookType: "audiobook",
                publicationType: "digital"
            )
        ]

        let scoped = SableMangaBakaStorefrontDiscovery
            .booksScopedToExactStoreReference(
                rows,
                reference: reference
            )

        XCTAssertEqual(scoped.map(\.id), ["B0G34PSB1C"])
        XCTAssertEqual(scoped.first?.url, reference.url)
        XCTAssertEqual(scoped.first?.publicationType, "digital")
    }

    func testCrossInfiniteWorldCatalogFindsExactSeriesPage() throws {
        let series = SableMangaBakaSeriesSummary(
            id: 84_747,
            title: "Onmyoji and Tengu Eyes",
            nativeTitle: "陰陽師と天狗眼",
            romanizedTitle: nil,
            titles: [
                SableMangaBakaSeriesTitle(
                    language: "en",
                    traits: ["official"],
                    title: "Onmyoji and Tengu Eyes",
                    isPrimary: true
                )
            ],
            type: "novel",
            cover: nil,
            finalVolume: "5"
        )
        let html = """
        <a href="Another-Series.html">
          <img alt="Another Series Cover" src="another.jpg">
        </a>
        <a href="Onmyoji-and-Tengu-Eyes.html">
          <img alt="Onmyoji and Tengu Eyes Cover" src="onmyoji.jpg">
        </a>
        """

        let url = try XCTUnwrap(
            SableMangaBakaStorefrontDiscovery
                .crossInfiniteWorldSeriesPageURL(
                    in: html,
                    series: series
                )
        )

        XCTAssertEqual(
            url.absoluteString,
            "https://www.crossinfworld.com/Onmyoji-and-Tengu-Eyes.html"
        )
    }

    func testCrossInfiniteWorldCatalogAllowsOneUnambiguousOfficialTypo()
        throws {
        let series = SableMangaBakaSeriesSummary(
            id: 111_892,
            title:
                "How I Swapped Places with the Villainess, Beat Up Her Fiance, and Found True Love",
            nativeTitle: nil,
            romanizedTitle: nil,
            titles: nil,
            type: "novel",
            cover: nil,
            finalVolume: "1"
        )
        let html = """
        <a href="How-I-Swapped-Places-with-the-Villainess.html">
          <img alt="How I Swapped Place with the Villainess Cover" src="swap.jpg">
        </a>
        <a href="Another-Villainess.html">
          <img alt="Another Villainess Cover" src="other.jpg">
        </a>
        """

        let url = try XCTUnwrap(
            SableMangaBakaStorefrontDiscovery
                .crossInfiniteWorldSeriesPageURL(
                    in: html,
                    series: series
                )
        )

        XCTAssertEqual(
            url.absoluteString,
            "https://www.crossinfworld.com/How-I-Swapped-Places-with-the-Villainess.html"
        )
    }

    func testCrossInfiniteWorldAmazonLinksKeepEnglishLanguageAndPreferDigital() {
        let html = """
        <div class="col-sm-3">
          <div class="panel-heading">
            <strong>Onmyoji and Tengu Eyes</strong>
          </div>
          <p><strong>Print Releases</strong></p>
          <a href="https://www.amazon.com/dp/B0PRINT001">Amazon US</a>
          <a href="https://www.amazon.de/dp/B0PRINT001">Amazon DE</a>
          <p><strong>Digital Releases</strong></p>
          <a href="https://www.amazon.com/dp/B0DIGIT001">Amazon US</a>
        </div>
        <div class="col-sm-3">
          <div class="panel-heading">
            <strong>Onmyoji and Tengu Eyes Volume 2</strong>
          </div>
          <a href="https://www.amazon.co.uk/dp/B0DIGIT002">Amazon UK</a>
          <!-- <a href="https://www.amazon.fr/dp/B0STALE999">stale</a> -->
        </div>
        <div class="clearfix"></div>
        """

        let references = SableMangaBakaStorefrontDiscovery
            .crossInfiniteWorldAmazonReferences(in: html)

        XCTAssertEqual(references.count, 3)
        XCTAssertEqual(
            references.first(where: { $0.provider == .amazon })?.itemID,
            "B0DIGIT001"
        )
        XCTAssertEqual(
            references.first(where: { $0.provider == .amazonGermany })?
                .volumeNumberOverride,
            1
        )
        XCTAssertEqual(
            references.first(where: { $0.provider == .amazonUK })?
                .volumeNumberOverride,
            2
        )
        XCTAssertTrue(
            references.allSatisfy { $0.languageOverride == "en" }
        )
        XCTAssertTrue(
            references.allSatisfy {
                $0.publisherProvenMediaType == "novel"
            }
        )
    }

    func testSevenSeasSearchSelectsExactSeriesAndMediaType() throws {
        let series = SableMangaBakaSeriesSummary(
            id: 123,
            title: "I Want to Escape from Princess Lessons",
            nativeTitle: nil,
            romanizedTitle: nil,
            titles: [
                SableMangaBakaSeriesTitle(
                    language: "en",
                    traits: ["official"],
                    title: "I Want to Escape from Princess Lessons",
                    isPrimary: true
                )
            ],
            type: "manga",
            cover: nil,
            finalVolume: "6"
        )
        let json = """
        [
          {
            "title": "I Want to Escape from Princess Lessons (Light Novel)",
            "url": "https://sevenseasentertainment.com/series/i-want-to-escape-from-princess-lessons-light-novel/"
          },
          {
            "title": "I Want to Escape From Princess Lessons (Manga)",
            "url": "https://sevenseasentertainment.com/series/i-want-to-escape-from-princess-lessons-manga/"
          }
        ]
        """

        let url = try XCTUnwrap(
            SableMangaBakaStorefrontDiscovery
                .sevenSeasSeriesPageURL(
                    in: json,
                    series: series
                )
        )

        XCTAssertEqual(
            url.absoluteString,
            "https://sevenseasentertainment.com/series/i-want-to-escape-from-princess-lessons-manga/"
        )
    }

    func testSevenSeasSearchLetsExactUntypedSeriesReachBookTypeCheck()
        throws {
        let series = SableMangaBakaSeriesSummary(
            id: 124,
            title: "Skip and Loafer",
            nativeTitle: nil,
            romanizedTitle: nil,
            titles: nil,
            type: "manga",
            cover: nil,
            finalVolume: "12"
        )
        let json = """
        [
          {
            "title": "Skip and Loafer",
            "url": "https://sevenseasentertainment.com/series/skip-and-loafer/"
          },
          {
            "title": "Skip and Loafer (Light Novel)",
            "url": "https://sevenseasentertainment.com/series/skip-and-loafer-light-novel/"
          }
        ]
        """

        let url = try XCTUnwrap(
            SableMangaBakaStorefrontDiscovery
                .sevenSeasSeriesPageURL(in: json, series: series)
        )

        XCTAssertEqual(
            url.absoluteString,
            "https://sevenseasentertainment.com/series/skip-and-loafer/"
        )
    }

    func testSevenSeasSearchAllowsOneUnambiguousDanmeiSubtitle() throws {
        let series = SableMangaBakaSeriesSummary(
            id: 85_593,
            title: "The Husky and His White Cat Shizun",
            nativeTitle: nil,
            romanizedTitle: nil,
            titles: nil,
            type: "novel",
            cover: nil,
            finalVolume: "11"
        )
        let json = """
        [
          {
            "title": "The Husky and His White Cat Shizun: Erha He Ta De Bai Mao Shizun (Novel)",
            "url": "https://sevenseasentertainment.com/series/the-husky-and-his-white-cat-shizun-erha-he-ta-de-bai-mao-shizun-novel/"
          },
          {
            "title": "The Husky and His White Cat Shizun Art Book (Manga)",
            "url": "https://sevenseasentertainment.com/series/the-husky-and-his-white-cat-shizun-art-book/"
          }
        ]
        """

        let url = try XCTUnwrap(
            SableMangaBakaStorefrontDiscovery
                .sevenSeasSeriesPageURL(in: json, series: series)
        )

        XCTAssertEqual(
            url.absoluteString,
            "https://sevenseasentertainment.com/series/the-husky-and-his-white-cat-shizun-erha-he-ta-de-bai-mao-shizun-novel/"
        )
    }

    func testSevenSeasSeriesPageKeepsVolumesAndMatchingSirenAudiobooks() {
        let series = SableMangaBakaSeriesSummary(
            id: 456,
            title:
                "7th Time Loop: The Villainess Enjoys a Carefree Life Married to Her Worst Enemy!",
            nativeTitle: nil,
            romanizedTitle: nil,
            titles: [
                SableMangaBakaSeriesTitle(
                    language: "en",
                    traits: ["official"],
                    title:
                        "7th Time Loop: The Villainess Enjoys a Carefree Life Married to Her Worst Enemy!",
                    isPrimary: true
                )
            ],
            type: "novel",
            cover: nil,
            finalVolume: "7"
        )
        let html = """
        <h2 class="topper">Series<span>:</span> 7th Time Loop: The Villainess Enjoys a Carefree Life Married to Her Worst Enemy!</h2>
        <a class="series-volume" href="https://sevenseasentertainment.com/books/7th-time-loop-light-novel-vol-1/">
          7th Time Loop: The Villainess Enjoys a Carefree Life Married to Her Worst Enemy! (Light Novel) Vol. 1
          Release Date: Jul 19, 2022 Format: Light Novel
        </a>
        <a class="series-volume" href="https://sevenseasentertainment.com/audio_books/7th-time-loop-audiobook-vol-1/">
          7th Time Loop: The Villainess Enjoys a Carefree Life Married to Her Worst Enemy! (Audiobook) Vol. 1
          Release Date: Dec 11, 2025
        </a>
        <a class="series-volume" href="https://sevenseasentertainment.com/books/7th-time-loop-manga-vol-1/">
          7th Time Loop: The Villainess Enjoys a Carefree Life Married to Her Worst Enemy! (Manga) Vol. 1
          Release Date: Sep 01, 2022 Format: Manga
        </a>
        <a class="series-volume" href="https://sevenseasentertainment.com/audio_books/kuma-kuma-kuma-bear-audiobook-vol-11-5/">
          Kuma Kuma Kuma Bear (Audiobook) Vol. 11.5
        </a>
        """

        let urls = SableMangaBakaStorefrontDiscovery
            .sevenSeasVolumePageURLs(
                in: html,
                series: series
            )

        XCTAssertEqual(urls.count, 2)
        XCTAssertTrue(
            urls.contains {
                $0.absoluteString.contains(
                    "/books/7th-time-loop-light-novel-vol-1/"
                )
            }
        )
        XCTAssertTrue(
            urls.contains {
                $0.absoluteString.contains(
                    "/audio_books/7th-time-loop-audiobook-vol-1/"
                )
            }
        )
    }

    func testSevenSeasSeriesPageKeepsUntypedExactVolumeLinks() {
        let series = SableMangaBakaSeriesSummary(
            id: 457,
            title: "Parallel Paradise",
            nativeTitle: nil,
            romanizedTitle: nil,
            titles: nil,
            type: "manga",
            cover: nil,
            finalVolume: "17"
        )
        let html = """
        <h2 class="topper">Series<span>:</span> Parallel Paradise</h2>
        <a class="series-volume" href="https://sevenseasentertainment.com/books/parallel-paradise-vol-1/">
          Parallel Paradise Vol. 1 Release Date: Mar 31, 2020
        </a>
        <a class="series-volume" href="https://sevenseasentertainment.com/books/parallel-paradise-light-novel-vol-1/">
          Parallel Paradise (Light Novel) Vol. 1
        </a>
        <a class="series-volume" href="https://sevenseasentertainment.com/books/unrelated-vol-1/">
          Unrelated Vol. 1
        </a>
        """

        let urls = SableMangaBakaStorefrontDiscovery
            .sevenSeasVolumePageURLs(in: html, series: series)

        XCTAssertEqual(
            urls.map(\.absoluteString),
            [
                "https://sevenseasentertainment.com/books/parallel-paradise-vol-1/"
            ]
        )
    }

    func testSevenSeasOfficialHeadingConnectsSubtitleAndManhwaVolumes() {
        let series = SableMangaBakaSeriesSummary(
            id: 458,
            title: "Killing Stalking",
            nativeTitle: nil,
            romanizedTitle: nil,
            titles: nil,
            type: "manga",
            cover: nil,
            finalVolume: "8"
        )
        let html = """
        <h2 class="topper">Series<span>:</span> Killing Stalking</h2>
        <a class="series-volume" href="https://sevenseasentertainment.com/books/killing-stalking-deluxe-edition-vol-1/">
          Killing Stalking: Deluxe Edition Vol. 1
          Release Date: Jul 19, 2022 Format: Manhwa
        </a>
        <a href="https://sevenseasentertainment.com/books/killing-stalking-lookalike-vol-1/">
          Killing Stalking Lookalike Vol. 1
        </a>
        """

        let urls = SableMangaBakaStorefrontDiscovery
            .sevenSeasVolumePageURLs(in: html, series: series)

        XCTAssertEqual(
            urls.map(\.absoluteString),
            [
                "https://sevenseasentertainment.com/books/killing-stalking-deluxe-edition-vol-1/"
            ]
        )
    }

    func testSevenSeasManhwaFormatIsManga() throws {
        let pageURL = try XCTUnwrap(
            URL(
                string:
                    "https://sevenseasentertainment.com/books/killing-stalking-deluxe-edition-vol-1/"
            )
        )
        let html = """
        <h2 class="topper">Book<span>:</span> Killing Stalking: Deluxe Edition Vol. 1</h2>
        <div class="age-rating" id="webtoons-block">Webtoons</div>
        <div id="volume-cover">
          <img src="https://sevenseasentertainment.com/covers/killing-stalking-1.jpg">
        </div>
        <p><b>Format:</b> Manhwa</p>
        <a href="https://www.amazon.com/s?field-keywords=killing+stalking">
          <img alt="Amazon (US)">
        </a>
        """

        let references = SableMangaBakaStorefrontDiscovery
            .sevenSeasPublisherReferences(
                in: html,
                pageURL: pageURL
            )

        XCTAssertEqual(references.first?.mediaType, "manga")
        XCTAssertEqual(references.first?.imprint, "Webtoons")
    }

    func testSevenSeasBookPageUsesOfficialCoverAndDigitalRetailers() throws {
        let pageURL = try XCTUnwrap(
            URL(
                string:
                    "https://sevenseasentertainment.com/books/i-want-to-escape-from-princess-lessons-manga-vol-5/"
            )
        )
        let html = """
        <h2 class="topper">Book<span>:</span> I Want to Escape from Princess Lessons (Manga) Vol. 5</h2>
        <div id="volume-cover">
          <img src="https://sevenseasentertainment.com/covers/princess-5.jpg">
        </div>
        <p><b>Format:</b> Manga</p>
        <a href="https://www.amazon.com/s?k=print">
          <img alt="Amazon">
        </a>
        <a href="https://www.amazon.com/s?field-keywords=digital">
          <img alt="Amazon (US)">
        </a>
        <a href="https://global.bookwalker.jp/search/?word=Princess+Lessons+Vol+5">
          <img alt="Book Walker">
        </a>
        <a href="https://www.kobo.com/search?query=Princess">
          <img alt="Kobo">
        </a>
        """

        let references = SableMangaBakaStorefrontDiscovery
            .sevenSeasPublisherReferences(
                in: html,
                pageURL: pageURL
            )

        XCTAssertEqual(
            Set(references.map(\.provider)),
            [.amazon, .bookWalkerGlobal, .rakutenKobo]
        )
        XCTAssertTrue(
            references.allSatisfy {
                $0.imageURL
                    == "https://sevenseasentertainment.com/covers/princess-5.jpg"
            }
        )
        XCTAssertTrue(
            references.allSatisfy {
                $0.volumeNumber == 5
                    && $0.coverType == "volume"
                    && $0.mediaType == "manga"
            }
        )
        XCTAssertEqual(
            references.first(where: { $0.provider == .amazon })?
                .storeURL,
            "https://www.amazon.com/s?field-keywords=digital"
        )
        XCTAssertEqual(
            references.first(where: { $0.provider == .rakutenKobo })?
                .publicationType,
            "digital"
        )
    }

    func testKoboRetailerLinksKeepTheirStorefrontLocale() throws {
        let pageURL = try XCTUnwrap(
            URL(
                string:
                    "https://sevenseasentertainment.com/books/example-vol-1/"
            )
        )
        let html = """
        <h2 class="topper">Book: Example (Manga) Vol. 1</h2>
        <div id="volume-cover">
          <img src="https://sevenseasentertainment.com/covers/example-1.jpg">
        </div>
        <p><b>Format:</b> Manga</p>
        <a href="https://www.kobo.com/nl/nl/ebook/example">
          Kobo Netherlands
        </a>
        <a href="https://www.kobo.com/fr/fr/ebook/example">
          Kobo France
        </a>
        """

        let references = SableMangaBakaStorefrontDiscovery
            .sevenSeasPublisherReferences(
                in: html,
                pageURL: pageURL
            )

        XCTAssertEqual(
            Set(references.map(\.provider)),
            [.rakutenKoboNetherlands, .rakutenKoboFrance]
        )
        XCTAssertTrue(
            references.allSatisfy {
                $0.publicationType == "digital"
                    && $0.language == "en"
            }
        )
    }

    func testSevenSeasSirenPageCreatesFocusedAudiobookRetailerLanes()
        throws {
        let pageURL = try XCTUnwrap(
            URL(
                string:
                    "https://sevenseasentertainment.com/audio_books/7th-time-loop-audiobook-vol-1/"
            )
        )
        let html = """
        <h2 class="topper">Book<span>:</span> 7th Time Loop (Audiobook) Vol. 1</h2>
        <div id="siren-block" class="age-rating">Siren</div>
        <div id="volume-cover">
          <img src="https://sevenseasentertainment.com/covers/loop-audio-1.jpg">
        </div>
        <a href="https://www.audible.com/pd/Example/B0G59S5G5W">
          <img alt="audible">
        </a>
        <a href="https://global.bookwalker.jp/deb5c5a446-e26d-4422-8e49-f3a67d012206/">
          <img alt="bookwalker">
        </a>
        <a href="https://www.kobo.com/us/en/audiobook/example">
          <img alt="kobo">
        </a>
        <a href="https://www.barnesandnoble.com/w/example/1">
          <img alt="nook">
        </a>
        <a href="https://open.spotify.com/show/example">
          <img alt="spotify">
        </a>
        """

        let references = SableMangaBakaStorefrontDiscovery
            .sevenSeasPublisherReferences(
                in: html,
                pageURL: pageURL
            )

        XCTAssertEqual(
            Set(references.map(\.provider)),
            [
                .audibleUS,
                .barnesNobleUS,
                .bookWalkerGlobal,
                .rakutenKobo
            ]
        )
        XCTAssertEqual(
            references.first { $0.provider == .rakutenKobo }?
                .publicationType,
            "digital"
        )
        XCTAssertTrue(
            references.allSatisfy {
                $0.volumeNumber == 1
                    && $0.coverType == "audiobook"
                    && $0.mediaType == "audiobook"
                    && $0.imprint == "Siren"
            }
        )
    }

    func testSevenSeasPublisherBadgesPreserveSharedCatalogImprints() {
        let html = """
        <div id="AS-block" class="age-rating">
          <a href="https://airshipnovels.com/">Airship</a>
        </div>
        <div id="danmei-block" class="age-rating">Danmei</div>
        <div id="GS-block" class="age-rating">
          <a href="https://ghostshipmanga.com/">Ghost Ship</a>
        </div>
        <div id="siren-block" class="age-rating">Siren</div>
        <div id="SS-block" class="age-rating">Steamship</div>
        <div class="age-rating" id="webtoons-block">Webtoons</div>
        <div id="SSBL-block" class="age-rating">boys' love</div>
        <div class="age-rating" id="mature"></div>
        """

        XCTAssertEqual(
            SableMangaBakaStorefrontDiscovery.sevenSeasImprints(
                in: html
            ),
            [
                "Airship",
                "Danmei",
                "Ghost Ship",
                "Siren",
                "Steamship",
                "Webtoons"
            ]
        )
    }

    func testBookWalkerExactVolumeLinksBecomeBookReferences() throws {
        let global = try XCTUnwrap(
            SableMangaBakaStorefrontDiscovery.storeSeriesReference(
                from:
                    "https://bookwalker.com/volume/15GWQ9JC7NH0/7th-time-loop-vol-1"
            )
        )
        XCTAssertEqual(global.provider, .bookWalkerGlobal)
        XCTAssertEqual(global.itemID, "15GWQ9JC7NH0")
        XCTAssertEqual(global.itemType, "book")

        let japanese = try XCTUnwrap(
            SableMangaBakaStorefrontDiscovery.storeSeriesReference(
                from:
                    "https://bookwalker.jp/de92479a-4c8c-8044-ad10-8be37a2e44e4/"
            )
        )
        XCTAssertEqual(japanese.provider, .bookWalkerJP)
        XCTAssertEqual(
            japanese.itemID,
            "de92479a-4c8c-8044-ad10-8be37a2e44e4"
        )
        XCTAssertEqual(japanese.itemType, "book")
    }

    func testOfficialPublisherVolumeAttachesBBCSeriesAndBookIdentity() {
        let reference =
            SableMangaBakaStorefrontDiscovery.OfficialPublisherReference(
                provider: .bookWalkerJP,
                title: "Example Story (Light Novel) Vol. 5",
                imageURL: "https://publisher.example/volume-5.jpg",
                storeURL:
                    "https://bookwalker.jp/de92479a-4c8c-8044-ad10-8be37a2e44e4/",
                volumeNumber: 5,
                coverType: "volume",
                mediaType: "novel",
                pageURL: "https://publisher.example/volume-5"
            )
        var book = storefrontBook(
            id: "de92479a-4c8c-8044-ad10-8be37a2e44e4",
            title: "Example Story Vol. 5",
            sequence: 1,
            volumeNumber: 1
        )
        book.seriesID = "bbc-example-story"

        let resolved = SableMangaBakaStorefrontDiscovery
            .applyingOfficialPublisherIdentity(
                to: [reference],
                providerSeriesID: "fallback-series",
                books: [book]
            )

        XCTAssertEqual(
            resolved.first?.providerSeriesID,
            "bbc-example-story"
        )
        XCTAssertEqual(
            resolved.first?.providerItemID,
            "de92479a-4c8c-8044-ad10-8be37a2e44e4"
        )
        XCTAssertEqual(resolved.first?.volumeNumber, 5)
    }

    func testShueishaSearchCreatesOfficialFrontAndBackCoverLanes()
        throws {
        let html = """
        <script>
        var ssd = {
          "datas": [{
            "series_id": 36591,
            "series_name": "ワンパンマン",
            "label_name": "ジャンプコミックス",
            "genre_datas": ["少年コミックス"],
            "item_datas": [{
              "isbn": "978-4-08-870701-3",
              "item_name": "ワンパンマン 1",
              "view_volume_number": "1",
              "image_url": "https://dosbg3xlm0x1t.cloudfront.net/images/items/9784088707013/240/9784088707013.jpg"
            }]
          }]
        };
        var order = 1;
        </script>
        """
        let searchURL = try XCTUnwrap(
            URL(
                string:
                    "https://www.shueisha.co.jp/books/search/search.html?titleauthor=%E3%83%AF%E3%83%B3%E3%83%91%E3%83%B3%E3%83%9E%E3%83%B3"
            )
        )
        let payload = try XCTUnwrap(
            SableMangaBakaStorefrontDiscovery.shueishaSearchPayload(
                in: html
            )
        )
        let references = SableMangaBakaStorefrontDiscovery
            .shueishaPublisherReferences(
                from: try XCTUnwrap(payload.datas.first),
                searchURL: searchURL,
                requiresRelationshipReview: true
            )

        XCTAssertEqual(references.count, 2)
        XCTAssertEqual(
            Set(references.map(\.coverType)),
            ["volume", "volume_back"]
        )
        XCTAssertTrue(
            references.allSatisfy {
                $0.provider == .shueisha
                    && $0.language == "ja"
                    && $0.publicationType == "physical"
                    && $0.providerSeriesID == nil
                    && $0.providerItemID == nil
                    && $0.requiresRelationshipReview
            }
        )
        XCTAssertTrue(
            references.contains {
                $0.imageURL.hasSuffix(
                    "/1200/9784088707013_130.jpg"
                )
            }
        )
        XCTAssertTrue(
            SableMangaBakaStorefrontDiscovery
                .bbcAnchoredOfficialPublisherReferences(references)
                .isEmpty
        )

        let bbcAnchored = references.map { reference in
            var reference = reference
            reference.providerSeriesID = "148407"
            reference.providerItemID = "9784088707013"
            return reference
        }
        XCTAssertEqual(
            SableMangaBakaStorefrontDiscovery
                .bbcAnchoredOfficialPublisherReferences(bbcAnchored)
                .count,
            2
        )
    }

    func testShueishaFullSeriesReadsPastFortyItems() throws {
        let items: [[String: Any]] = (1...41).map { volume in
            [
                "isbn": "978-4-08-000\(String(format: "%04d", volume))",
                "item_name": "ONE PIECE \(volume)",
                "view_volume_number": String(volume),
                "image_url":
                    "https://dosbg3xlm0x1t.cloudfront.net/images/items/\(volume)/240/\(volume).jpg"
            ]
        }
        let payload: [String: Any] = [
            "count": 1,
            "data": [
                "series_data": [
                    "series_id": 35169,
                    "series_name": "ONE PIECE",
                    "main_label_name": "ジャンプコミックス",
                    "genre_datas": ["コミックス", "ジャンプコミックス"]
                ],
                "item_datas": items
            ]
        ]
        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        let json = try XCTUnwrap(String(data: jsonData, encoding: .utf8))
        let html = "<script>var ssd = \(json); var order = 1;</script>"

        let series = try XCTUnwrap(
            SableMangaBakaStorefrontDiscovery.shueishaFullSeries(
                in: html
            )
        )

        XCTAssertEqual(series.seriesId, 35169)
        XCTAssertEqual(series.itemDatas.count, 41)
        XCTAssertEqual(series.itemDatas.last?.viewVolumeNumber, "41")
    }

    func testKodanshaCatalogKeepsExactMangaVolumesAndDigitalRetailers()
        throws {
        let series = SableMangaBakaSeriesSummary(
            id: 101,
            title: "Suzume",
            nativeTitle: nil,
            romanizedTitle: nil,
            titles: nil,
            type: "manga",
            cover: nil,
            finalVolume: "3"
        )
        let seriesHTML = """
        <title>Suzume | Digital manga series | Kodansha</title>
        <h1 class="series__single__title">Suzume</h1>
        <a href="https://kodansha.us/series/suzume/volume-2/">
          Volume 2
        </a>
        <a href="https://kodansha.us/series/suzume/volume-1/">
          Volume 1
        </a>
        """

        let pages = SableMangaBakaStorefrontDiscovery
            .kodanshaVolumePageURLs(
                in: seriesHTML,
                series: series
            )
        XCTAssertEqual(
            pages.map(\.path),
            [
                "/series/suzume/volume-1",
                "/series/suzume/volume-2"
            ]
        )

        let pageURL = try XCTUnwrap(pages.first)
        let volumeHTML = """
        <meta property="og:title" content="Suzume Volume 1 | Kodansha">
        <meta property="og:image" content="https://production.image.azuki.co/suzume/800.webp">
        <span>Print Retailers</span>
        <a href="https://www.amazon.com/dp/1647294045">Amazon</a>
        <span>Digital Retailers</span>
        <a href="https://www.amazon.com/dp/B0DDCV11H6">Amazon</a>
        <a href="https://bookwalker.com/by/isbn/9798894781327">
          Bookwalker
        </a>
        <a href="https://www.kobo.com/us/en/ebook/suzume">Kobo</a>
        """
        let references = SableMangaBakaStorefrontDiscovery
            .kodanshaPublisherReferences(
                in: volumeHTML,
                pageURL: pageURL
            )

        XCTAssertEqual(
            Set(references.map(\.provider)),
            [.amazon, .bookWalkerGlobal, .rakutenKobo]
        )
        XCTAssertEqual(
            references.first { $0.provider == .amazon }?.storeURL,
            "https://www.amazon.com/dp/B0DDCV11H6"
        )
        XCTAssertTrue(
            references.allSatisfy {
                $0.publisherFamily == "Kodansha"
                    && $0.mediaType == "manga"
                    && $0.volumeNumber == 1
            }
        )
    }

    func testVIZCatalogKeepsExactMangaProductsAndRegionalAmazonLinks()
        throws {
        let series = SableMangaBakaSeriesSummary(
            id: 102,
            title: "One-Punch Man",
            nativeTitle: nil,
            romanizedTitle: nil,
            titles: nil,
            type: "manga",
            cover: nil,
            finalVolume: nil
        )
        let searchHTML = """
        <a href="/manga-books/manga/other-volume-1/product/1">
          Other, Vol. 1
        </a>
        <a href="/manga-books/manga/one-punch-man-volume-2/product/2">
          One-Punch Man, Vol. 2
        </a>
        <a href="/manga-books/manga/one-punch-man-volume-1/product/1">
          One-Punch Man, Vol. 1
        </a>
        """
        let pages = SableMangaBakaStorefrontDiscovery
            .vizVolumePageURLs(in: searchHTML, series: series)
        XCTAssertEqual(
            pages.map(\.path),
            [
                "/manga-books/manga/one-punch-man-volume-1/product/1",
                "/manga-books/manga/one-punch-man-volume-2/product/2"
            ]
        )
        XCTAssertEqual(
            SableMangaBakaStorefrontDiscovery
                .officialPublisherAnchorPageURLs(
                    from: [
                        pages[0],
                        pages[1],
                        try XCTUnwrap(
                            URL(
                                string:
                                    "https://www.viz.com/manga-books/manga/one-punch-man-volume-3/product/3"
                            )
                        ),
                        try XCTUnwrap(
                            URL(
                                string:
                                    "https://www.viz.com/manga-books/manga/one-punch-man-volume-4/product/4"
                            )
                        )
                    ]
                ),
            [
                pages[0],
                pages[1],
                try XCTUnwrap(
                    URL(
                        string:
                            "https://www.viz.com/manga-books/manga/one-punch-man-volume-4/product/4"
                    )
                )
            ]
        )
        XCTAssertEqual(
            SableMangaBakaStorefrontDiscovery
                .vizRetailerPageURLs(from: pages)
                .map(\.path),
            [
                "/manga-books/manga/one-punch-man-volume-1/product/1/paperback",
                "/manga-books/manga/one-punch-man-volume-1/product/1/digital",
                "/manga-books/manga/one-punch-man-volume-2/product/2/paperback",
                "/manga-books/manga/one-punch-man-volume-2/product/2/digital"
            ]
        )

        let pageURL = try XCTUnwrap(pages.first)
        let pageHTML = """
        <meta property="og:title" content="VIZ: Read a Free Preview of One-Punch Man, Vol. 1">
        <meta property="og:image" content="https://viz.example/one-punch-man-1.jpg">
        <a href="https://www.amazon.com/dp/1421585642">Amazon</a>
        <a href="https://www.amazon.co.uk/dp/1421585642">Amazon</a>
        <a href="https://www.barnesandnoble.com/w/9781421585642">
          Barnes &amp; Noble
        </a>
        <a href="https://www.kobobooks.com/search/search.html?q=9781421585642">
          Kobo
        </a>
        """
        let references = SableMangaBakaStorefrontDiscovery
            .vizPublisherReferences(in: pageHTML, pageURL: pageURL)

        XCTAssertEqual(
            Set(references.map(\.provider)),
            [.amazon, .amazonUK, .barnesNobleUS, .rakutenKobo]
        )
        XCTAssertTrue(
            references.allSatisfy {
                $0.publisherFamily == "VIZ Media"
                    && $0.title == "One-Punch Man, Vol. 1"
                    && $0.volumeNumber == 1
            }
        )

        let expanded = SableMangaBakaStorefrontDiscovery
            .expandedOfficialPublisherReferences(
                anchor: try XCTUnwrap(
                    references.first { $0.provider == .amazon }
                ),
                providerSeriesID: "amazon-series",
                books: [
                    SableLibraryBigBookCoversBookCandidate(
                        provider: .amazon,
                        id: "1421585642",
                        seriesID: "amazon-series",
                        title: "One-Punch Man, Vol. 1",
                        url:
                            "https://www.amazon.com/dp/1421585642",
                        coverURL:
                            "https://amazon.example/one-punch-man-1.jpg",
                        coverFallbackURLs: [],
                        volumeNumber: 1,
                        volumeType: "volume",
                        sequenceIndex: 1,
                        bookType: "manga"
                    ),
                    SableLibraryBigBookCoversBookCandidate(
                        provider: .amazon,
                        id: "1421585650",
                        seriesID: "amazon-series",
                        title: "One-Punch Man, Vol. 2",
                        url:
                            "https://www.amazon.com/dp/1421585650",
                        coverURL:
                            "https://amazon.example/one-punch-man-2.jpg",
                        coverFallbackURLs: [],
                        volumeNumber: 2,
                        volumeType: "volume",
                        sequenceIndex: 2,
                        bookType: "manga"
                    )
                ]
            )
        XCTAssertEqual(expanded.map(\.volumeNumber), [1, 2])
        XCTAssertEqual(
            expanded.map(\.providerItemID),
            ["1421585642", "1421585650"]
        )
        XCTAssertTrue(
            expanded.allSatisfy {
                $0.publisherFamily == "VIZ Media"
                    && $0.providerSeriesID == "amazon-series"
            }
        )
        XCTAssertTrue(
            SableMangaBakaStorefrontDiscovery
                .officialPublisherCandidateTitle(
                    "Teil von: One-Punch Man",
                    matches: "One-Punch Man"
                )
        )
        XCTAssertFalse(
            SableMangaBakaStorefrontDiscovery
                .officialPublisherCandidateTitle(
                    "Teil von: One-Punch Man",
                    matches: "One-Punch Man (light novel)"
                )
        )
    }

    func testDarkHorseCatalogRequiresExplicitMangaGenre()
        throws {
        let series = SableMangaBakaSeriesSummary(
            id: 103,
            title: "Keep Your Hands Off Eizouken!",
            nativeTitle: nil,
            romanizedTitle: nil,
            titles: nil,
            type: "manga",
            cover: nil,
            finalVolume: nil
        )
        let searchHTML = """
        <a href="/books/3004-947/eizouken-volume-2-tpb/">
          Keep Your Hands Off Eizouken! Volume 2 TPB
        </a>
        <a href="/books/3004-946/eizouken-volume-1-tpb/">
          Keep Your Hands Off Eizouken! Volume 1 TPB
        </a>
        """
        let pages = SableMangaBakaStorefrontDiscovery
            .darkHorseVolumePageURLs(
                in: searchHTML,
                series: series
            )
        XCTAssertEqual(
            pages.map(\.path),
            [
                "/books/3004-946/eizouken-volume-1-tpb",
                "/books/3004-947/eizouken-volume-2-tpb"
            ]
        )

        let pageURL = try XCTUnwrap(pages.first)
        let baseHTML = """
        <meta property="og:title" content="Keep Your Hands Off Eizouken! Volume 1 :: Profile :: Dark Horse Comics">
        <meta property="og:image" content="https://images.darkhorse.com/covers/400/eizouken-1.jpg">
        <a href="https://www.amazon.com/gp/product/1506718979">
          Buy on Amazon
        </a>
        """
        XCTAssertTrue(
            SableMangaBakaStorefrontDiscovery
                .darkHorsePublisherReferences(
                    in: baseHTML,
                    pageURL: pageURL
                )
                .isEmpty
        )

        let references = SableMangaBakaStorefrontDiscovery
            .darkHorsePublisherReferences(
                in:
                    baseHTML
                    + #"<a href="/search/genre:manga/">Manga</a>"#,
                pageURL: pageURL
            )
        XCTAssertEqual(references.map(\.provider), [.amazon])
        XCTAssertEqual(references.first?.publisherFamily, "Dark Horse Manga")
        XCTAssertEqual(references.first?.volumeNumber, 1)
    }

    func testSquareEnixCatalogUsesSeriesAndISBNRetailerBridges()
        throws {
        let series = SableMangaBakaSeriesSummary(
            id: 104,
            title: "The God-Slaying Demon King",
            nativeTitle: nil,
            romanizedTitle: nil,
            titles: nil,
            type: "manga",
            cover: nil,
            finalVolume: nil
        )
        let indexHTML = """
        <a href="/en-us/series/the-god-slaying-demon-king">
          <img alt="The God-Slaying Demon King"
               src="https://square.example/series.jpg">
        </a>
        <a href="/en-us/series/the-apothecary-diaries-light-novel">
          <img alt="The Apothecary Diaries (Light Novel)"
               src="https://square.example/novel.jpg">
        </a>
        """
        let seriesPages = SableMangaBakaStorefrontDiscovery
            .squareEnixSeriesPageURLs(in: indexHTML, series: series)
        XCTAssertEqual(
            seriesPages.map(\.path),
            ["/en-us/series/the-god-slaying-demon-king"]
        )

        let seriesHTML = """
        <a href="/en-us/product/9781646093618">
          <img alt="The God-Slaying Demon King, Volume 1"
               src="https://square.example/1.jpg">
        </a>
        <a href="/en-us/product/9781646093625">
          <img alt="The God-Slaying Demon King, Volume 2"
               src="https://square.example/2.jpg">
        </a>
        """
        let productPages = SableMangaBakaStorefrontDiscovery
            .squareEnixVolumePageURLs(in: seriesHTML, series: series)
        XCTAssertEqual(
            productPages.map(\.path),
            [
                "/en-us/product/9781646093618",
                "/en-us/product/9781646093625"
            ]
        )

        let productHTML = """
        <meta property="og:title"
              content="The God-Slaying Demon King, Volume 1">
        <img alt="The God-Slaying Demon King, Volume 1"
             class="w-full"
             src="https://fyre.cdn.sewest.net/manga/cover.jpg?width=768">
        <span>category:</span><span>Manga</span>
        <a href="https://www.amazon.com/gp/product/1646093615">
          Amazon
        </a>
        <a href="https://www.barnesandnoble.com/w/?ean=9781646093618">
          Barnes &amp; Noble
        </a>
        <a href="https://store.crunchyroll.com/products/9781646093618.html">
          Crunchyroll Store
        </a>
        """
        let productURL = try XCTUnwrap(productPages.first)
        let references = SableMangaBakaStorefrontDiscovery
            .squareEnixPublisherReferences(
                in: productHTML,
                pageURL: productURL
            )
        XCTAssertEqual(
            Set(references.map(\.provider)),
            [.amazon, .barnesNobleUS, .crunchyrollStore]
        )
        XCTAssertTrue(
            references.allSatisfy {
                $0.publisherFamily == "Square Enix Manga & Books"
                    && $0.mediaType == "manga"
                    && $0.volumeNumber == 1
                    && $0.imageURL.contains("width=1600")
            }
        )
        XCTAssertEqual(
            references.first(where: {
                $0.provider == .barnesNobleUS
            })?.providerItemID,
            "9781646093618"
        )
    }

    func testCrunchyrollExactProductGalleryAddsReviewableBackCover()
        throws {
        let pageHTML = #"""
        <script>
        {"images":[
          {"disBaseLink":"https://store.crunchyroll.com/images/book_1.jpg"},
          {"disBaseLink":"https://store.crunchyroll.com/images/book_2.jpg"},
          {"disBaseLink":"https://store.crunchyroll.com/images/book_3.jpg"}
        ]}
        </script>
        """#
        let reference =
            SableMangaBakaStorefrontDiscovery.OfficialPublisherReference(
                provider: .crunchyrollStore,
                title: "Witch Hat Atelier Manga Volume 1",
                imageURL: "https://publisher.example/cover.jpg",
                storeURL:
                    "https://store.crunchyroll.com/products/witch-hat-atelier-9798888776407.html",
                volumeNumber: 1,
                coverType: "volume",
                mediaType: "manga",
                pageURL: "https://publisher.example/witch-hat-atelier",
                publisherFamily: "Kodansha"
            )

        let references = SableMangaBakaStorefrontDiscovery
            .crunchyrollProductReferences(
                in: pageHTML,
                reference: reference
            )

        XCTAssertEqual(references.map(\.coverType), ["volume", "volume_back"])
        XCTAssertEqual(
            references.map(\.imageURL),
            [
                "https://store.crunchyroll.com/images/book_1.jpg",
                "https://store.crunchyroll.com/images/book_2.jpg"
            ]
        )
        let front = try XCTUnwrap(references.first)
        let back = try XCTUnwrap(references.dropFirst().first)
        XCTAssertFalse(front.requiresRelationshipReview)
        XCTAssertTrue(back.requiresRelationshipReview)
        XCTAssertEqual(front.providerItemID, "9798888776407")
    }

    func testExactBookWalkerGroupTrustsTheManuallyChosenSeriesIdentity() {
        let books = (1...3).map { volume in
            storefrontBook(
                id: "bw-global-\(volume)",
                title:
                    "Agents of the Four Seasons: One Hundred Songs and One Hundred Pages, Volume \(volume)",
                sequence: volume
            )
        }

        let scoped = SableMangaBakaStorefrontDiscovery
            .booksScopedToExactStoreSeries(books)

        XCTAssertEqual(
            scoped.map(\.id),
            ["bw-global-1", "bw-global-2", "bw-global-3"]
        )
        XCTAssertEqual(scoped.map(\.volumeNumber), [1, 2, 3])
    }

    func testExactBBCSeriesUsesUnusedVolumeSlotForMissingNumber() {
        let books = [
            SableLibraryBigBookCoversBookCandidate(
                provider: .amazon,
                id: "early-years",
                seriesID: "B0G4S8K7LN",
                title:
                    "Early Years: The Beginning After the End: (Remastered Edition)",
                url: "https://www.amazon.com/dp/early-years",
                coverURL: "https://example.com/early-years.jpg",
                coverFallbackURLs: [],
                volumeNumber: nil,
                volumeType: "volume",
                sequenceIndex: 6,
                bookType: nil
            )
        ] + (2...12).map { volume in
            SableLibraryBigBookCoversBookCandidate(
                provider: .amazon,
                id: "book-\(volume)",
                seriesID: "B0G4S8K7LN",
                title: "The Beginning After the End, Book \(volume)",
                url: "https://www.amazon.com/dp/book-\(volume)",
                coverURL: "https://example.com/book-\(volume).jpg",
                coverFallbackURLs: [],
                volumeNumber: nil,
                volumeType: "volume",
                sequenceIndex: volume,
                bookType: nil
            )
        }
        let series = SableMangaBakaSeriesSummary(
            id: 186_987,
            title: "The Beginning After the End",
            nativeTitle: nil,
            romanizedTitle: nil,
            type: "novel"
        )

        let scoped = SableMangaBakaStorefrontDiscovery
            .booksScopedToExactStoreSeries(
                books,
                series: series,
                language: "en"
            )

        XCTAssertEqual(
            scoped.first(where: { $0.id == "early-years" })?.volumeNumber,
            1
        )
        XCTAssertEqual(Set(scoped.compactMap(\.volumeNumber)).count, 12)
    }

    func testExactStoreLinkKeepsUnusualBBCEditionForUserReview() {
        let book = SableLibraryBigBookCoversBookCandidate(
            provider: .amazonUK,
            id: "B0G34PSB1C",
            seriesID: "B0G34PSB1C",
            title:
                "Early Years: The Beginning After the End (Collector's Edition)",
            url: "https://www.amazon.co.uk/dp/B0G34PSB1C",
            coverURL: "https://example.com/early-years.jpg",
            coverFallbackURLs: [],
            volumeNumber: 1,
            volumeType: "volume",
            sequenceIndex: 1,
            bookType: nil
        )

        let candidates = SableMangaBakaStorefrontDiscovery
            .exactStoreVolumeCandidates(
                from: [book],
                language: "en"
            )

        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.providerItemID, "B0G34PSB1C")
        XCTAssertEqual(candidates.first?.volumeNumber, 1)
        XCTAssertNil(candidates.first?.mediaType)
        XCTAssertEqual(candidates.first?.role, .normal)
    }

    func testChapterOnlyBookWalkerGroupBecomesTypedChapterCoversForManualURL() {
        let chapters = (0...3).map { chapter in
            SableLibraryBigBookCoversBookCandidate(
                provider: .bookWalkerGlobal,
                id: "chapter-\(chapter)",
                seriesID: "CNT_1TZHZ2EGA8T0",
                title: "Chapter \(chapter)",
                url: nil,
                coverURL: "https://example.com/chapter-\(chapter).jpg",
                coverFallbackURLs: [],
                volumeNumber: Double(chapter),
                volumeType: "chapter",
                sequenceIndex: chapter,
                bookType: nil
            )
        }

        XCTAssertEqual(
            SableMangaBakaStorefrontDiscovery.inferredSeriesMediaType(
                from: chapters
            ),
            "manga"
        )
        XCTAssertTrue(
            SableLibraryProviderCandidateParser.bigBookCoversCandidates(
                from: chapters,
                source: .bookWalkerGlobal,
                language: "en",
                mediaType: "manga"
            ).isEmpty
        )
        let manualChapterCandidates = SableMangaBakaStorefrontDiscovery
            .exactStoreChapterCandidates(
                from: chapters,
                source: .bookWalkerGlobal,
                language: "en"
            )
        XCTAssertEqual(manualChapterCandidates.count, 4)
        XCTAssertEqual(
            manualChapterCandidates.compactMap(\.volumeNumber),
            [0, 1, 2, 3]
        )
        XCTAssertTrue(
            manualChapterCandidates.allSatisfy {
                $0.providerType == "chapter"
            }
        )
        XCTAssertEqual(
            SableMangaBakaStorefrontDiscovery.exactStoreSeriesNoVolumeCoverNote(
                provider: .bookWalkerGlobal,
                books: chapters,
                language: "en"
            ),
            "BookWalker Global: manual relationship and media type accepted. This store page contains 4 chapter editions, but none exposed a usable chapter-cover image."
        )
    }

    func testJapaneseChapterSerialKeywordsStayOutOfVolumeCovers() {
        let markers = [
            "分冊版",
            "単話版",
            "マイクロ版",
            "単話売り",
            "ばら売り",
            "連載版"
        ]
        let books = markers.enumerated().map { index, marker in
            SableLibraryBigBookCoversBookCandidate(
                provider: .bookLiveJP,
                id: "chapter-serial-\(index + 1)",
                seriesID: "chapter-serial",
                title: "サンプル作品 \(marker) \(index + 1)",
                url: nil,
                coverURL:
                    "https://example.com/chapter-serial-\(index + 1).jpg",
                coverFallbackURLs: [],
                volumeNumber: Double(index + 1),
                volumeType: "volume",
                sequenceIndex: index + 1,
                bookType: "manga"
            )
        }

        XCTAssertTrue(
            SableLibraryProviderCandidateParser.bigBookCoversCandidates(
                from: books,
                source: .bookLiveJP,
                language: "ja",
                mediaType: "manga"
            ).isEmpty
        )

        let chapterCandidates = SableMangaBakaStorefrontDiscovery
            .exactStoreChapterCandidates(
                from: books,
                source: .bookLiveJP,
                language: "ja"
            )
        XCTAssertEqual(chapterCandidates.count, markers.count)
        XCTAssertEqual(
            chapterCandidates.compactMap(\.volumeNumber),
            [1, 2, 3, 4, 5, 6]
        )
        XCTAssertTrue(
            chapterCandidates.allSatisfy {
                $0.providerType == "chapter"
            }
        )
    }

    func testBareJapaneseSingleEpisodeMarkerOverridesBBCVolumeClassification() {
        let book = SableLibraryBigBookCoversBookCandidate(
            provider: .bookLiveJP,
            id: "1720842-013",
            seriesID: "1720842",
            title:
                "魔王軍四天王の最弱令嬢は自由に生きたい！【単話】 13",
            url:
                "https://booklive.jp/product/index/title_id/1720842/vol_no/013",
            coverURL: "https://example.com/chapter-13.jpg",
            coverFallbackURLs: [],
            volumeNumber: 13,
            volumeType: "volume",
            sequenceIndex: 13,
            bookType: "manga"
        )

        XCTAssertTrue(
            SableLibraryProviderCandidateParser
                .storefrontTitleIsChapterSerial(book.title)
        )
        XCTAssertTrue(
            SableMangaBakaStorefrontDiscovery.exactStoreVolumeCandidates(
                from: [book],
                language: "ja"
            ).isEmpty
        )

        let chapters = SableMangaBakaStorefrontDiscovery
            .exactStoreChapterCandidates(
                from: [book],
                source: .bookLiveJP,
                language: "ja"
            )

        XCTAssertEqual(chapters.count, 1)
        XCTAssertEqual(chapters.first?.volumeNumber, 13)
        XCTAssertEqual(chapters.first?.providerType, "chapter")
    }

    func testUnprovenChapterSerialDoesNotInheritExpectedSeriesMediaType() {
        let book = SableLibraryBigBookCoversBookCandidate(
            provider: .bookLiveJP,
            id: "20104192-001",
            seriesID: "20104192",
            title:
                "Re:ゼロから始める異世界生活 第五章 水の都と英雄の詩【分冊版】 1",
            url: nil,
            coverURL: "https://example.com/re-zero-chapter-1.jpg",
            coverFallbackURLs: [],
            volumeNumber: 1,
            volumeType: "volume",
            sequenceIndex: 1,
            bookType: nil
        )

        let candidates = SableMangaBakaStorefrontDiscovery
            .exactStoreChapterCandidates(
                from: [book],
                source: .bookLiveJP,
                language: "ja"
            )

        XCTAssertEqual(candidates.count, 1)
        XCTAssertNil(candidates[0].mediaType)
        XCTAssertEqual(
            SableMangaBakaStorefrontDiscovery.automaticMediaTypeDisposition(
                detectedMediaType: candidates[0].mediaType,
                expectedMediaType: "novel"
            ),
            .needsReview
        )
    }

    func testAutomaticSeriesCandidatesRouteChapterSerialsIntoTheirOwnLane() {
        let regular = SableLibraryBigBookCoversSeriesCandidate(
            provider: .bookLiveJP,
            id: "20144150",
            title:
                "リピート・ヴァイス ～悪役貴族は死にたくないので四天王になるのをやめました～",
            url:
                "https://booklive.jp/product/index/title_id/20144150/vol_no/001",
            type: "series",
            bookType: "manga",
            thumbnailURL: nil
        )
        let markers = [
            "分冊版",
            "単話版",
            "マイクロ版",
            "単話売り",
            "ばら売り",
            "連載版"
        ]
        let chapterSerials = markers.enumerated().map { index, marker in
            SableLibraryBigBookCoversSeriesCandidate(
                provider: .bookLiveJP,
                id: "chapter-\(index + 1)",
                title: "\(regular.title)【\(marker)】",
                url:
                    "https://booklive.jp/product/index/title_id/\(20_137_716 + index)/vol_no/001",
                type: "series",
                bookType: "manga",
                thumbnailURL: nil
            )
        }
        let audiobook = SableLibraryBigBookCoversSeriesCandidate(
            provider: .bookWalkerGlobal,
            id: "CNT_1QXEJ8JQDP0G",
            title: "Is It Wrong to Try to Pick Up Girls in a Dungeon?",
            url:
                "https://bookwalker.com/series/1QXEJ8JQDP0G/is-it-wrong-to-try-to-pick-up-girls-in-a-dungeon",
            type: "series",
            bookType: "audiobook",
            bookTypeWasExplicit: true,
            thumbnailURL: nil
        )

        let ranked = SableLibraryCoverDownloadPlanner
            .rankedSeriesCandidates(
                for: regular.title,
                in: [regular] + chapterSerials,
                mediaType: "manga"
            )
        let lanes = SableMangaBakaStorefrontDiscovery
            .automaticSeriesCandidateLanes(ranked + [audiobook])

        XCTAssertEqual(lanes.volumes.map(\.id), ["20144150"])
        XCTAssertEqual(
            Set(lanes.chapters.map(\.id)),
            Set(chapterSerials.map(\.id))
        )
        XCTAssertEqual(lanes.audiobooks.map(\.id), ["CNT_1QXEJ8JQDP0G"])
    }

    func testCompatibleBBCTypeCannotAutoOpenAnUnrelatedSeriesTitle() {
        let unrelated = SableLibraryBigBookCoversSeriesCandidate(
            provider: .bookWalkerGlobal,
            id: "unrelated-novel",
            title: "The Lawyer in Shizuku-ishi Sleeps with a Wolf",
            url: "https://global.bookwalker.jp/series/unrelated-novel",
            type: "series",
            bookType: "novel",
            thumbnailURL: "https://images.example/unrelated.jpg"
        )
        let expected = SableLibraryBigBookCoversSeriesCandidate(
            provider: .bookWalkerGlobal,
            id: "expected-novel",
            title: "The Beginning After the End",
            url: "https://global.bookwalker.jp/series/expected-novel",
            type: "series",
            bookType: "novel",
            thumbnailURL: "https://images.example/expected.jpg"
        )
        let candidates = [unrelated, expected]

        let ranked = SableLibraryCoverDownloadPlanner
            .rankedSeriesCandidates(
                for: "The Beginning After the End",
                in: candidates,
                mediaType: "novel"
            )
        let automatic = SableMangaBakaStorefrontDiscovery
            .automaticSeriesCandidateLanes(ranked)

        XCTAssertEqual(automatic.volumes.map(\.id), ["expected-novel"])
    }

    func testLibraryNeedsCoversExcludesSeriesWithoutMangaBakaIdentity() {
        XCTAssertFalse(
            SableMangaBakaLibraryCoverStatus
                .missingMangaBakaID
                .needsCoverAttention
        )
        XCTAssertTrue(
            SableMangaBakaLibraryCoverStatus
                .noVolumeCovers
                .needsCoverAttention
        )
        XCTAssertTrue(
            SableMangaBakaLibraryCoverStatus
                .fewerCoversThanLocalBooks
                .needsCoverAttention
        )
    }

    func testParentheticalContributorAliasDoesNotRejectExactJapaneseSeries() {
        let series = SableMangaBakaSeriesSummary(
            id: 20_254,
            title: "Boys, Be Ambitious!",
            nativeTitle: "少年よ、大志とか色々抱け",
            romanizedTitle: "Shounen yo, Taishi toka Iroiro Idake",
            titles: [
                SableMangaBakaSeriesTitle(
                    language: "en",
                    traits: ["official"],
                    title: "Boys, Be Ambitious!",
                    isPrimary: true
                ),
                SableMangaBakaSeriesTitle(
                    language: "en",
                    traits: [],
                    title: "Boys, Be Ambitious! (NAGAI Saburou)",
                    isPrimary: false
                ),
                SableMangaBakaSeriesTitle(
                    language: "ja",
                    traits: ["native"],
                    title: "少年よ、大志とか色々抱け",
                    isPrimary: true
                )
            ],
            type: "manga",
            cover: nil,
            finalVolume: "1"
        )
        let books = [
            storefrontBook(
                id: "booklive-273261",
                title: "少年よ、大志とか色々抱け",
                sequence: 1
            )
        ]

        let scoped = SableMangaBakaStorefrontDiscovery.booksScopedToSelectedSeries(
            books,
            series: series,
            language: "ja"
        )

        XCTAssertEqual(scoped.map(\.id), ["booklive-273261"])
        XCTAssertEqual(scoped.map(\.volumeNumber), [1])
    }

    func testScopedSeriesPreservesProviderVolumeNumbersWhenResponseOrderDiffers() {
        let series = SableMangaBakaSeriesSummary(
            id: 84_747,
            title: "Onmyoji and Tengu Eyes",
            nativeTitle: "陰陽師と天狗眼",
            romanizedTitle: nil,
            titles: [],
            type: "novel",
            cover: nil,
            finalVolume: nil
        )
        let books = [
            storefrontBook(
                id: "833218-005",
                title: "陰陽師と天狗眼",
                sequence: 0,
                volumeNumber: 5
            ),
            storefrontBook(
                id: "833218-001",
                title: "陰陽師と天狗眼",
                sequence: 1,
                volumeNumber: 1
            ),
            storefrontBook(
                id: "833218-003",
                title: "陰陽師と天狗眼",
                sequence: 2,
                volumeNumber: 3
            )
        ]

        let scoped = SableMangaBakaStorefrontDiscovery.booksScopedToSelectedSeries(
            books,
            series: series,
            language: "ja"
        )

        XCTAssertEqual(scoped.map(\.id), ["833218-005", "833218-001", "833218-003"])
        XCTAssertEqual(scoped.compactMap(\.volumeNumber), [5, 1, 3])
    }

    func testStorefrontDiscoveryKeepsOnePreferredProviderPerLanguageAndVolume() {
        let suggestions = [
            storefrontSuggestion(provider: .shueisha, language: "ja"),
            storefrontSuggestion(provider: .amazonJP, language: "ja"),
            storefrontSuggestion(provider: .bookWalkerJP, language: "ja"),
            storefrontSuggestion(provider: .bookLiveJP, language: "ja"),
            storefrontSuggestion(provider: .amazon, language: "en"),
            storefrontSuggestion(provider: .amazonUK, language: "en"),
            storefrontSuggestion(provider: .bookWalkerGlobal, language: "en")
        ]

        let preferred = SableMangaBakaStorefrontDiscovery.preferredSuggestions(
            from: suggestions
        )

        XCTAssertEqual(preferred.count, 2)
        XCTAssertEqual(
            preferred.first(where: { $0.language == "ja" })?.provider,
            .bookLiveJP
        )
        XCTAssertEqual(
            preferred.first(where: { $0.language == "en" })?.provider,
            .bookWalkerGlobal
        )
    }

    func testAmazonSeriesBooksContinuePastFirstFortyFormatRows() async throws {
        func pageData(start: Int, count: Int) throws -> Data {
            let rows = (start..<(start + count)).map { index in
                [
                    "id": String(format: "B%09d", index),
                    "title": "One-Punch Man, Vol. \(index)",
                    "url": "https://www.amazon.com/dp/\(index)",
                    "cover":
                        "https://m.media-amazon.com/images/P/\(index).jpg",
                    "volume": [
                        "type": "volume",
                        "number": String(index)
                    ]
                ] as [String: Any]
            }
            return try JSONSerialization.data(
                withJSONObject: ["data": ["amz": rows]]
            )
        }

        let pages = [
            1: try pageData(start: 1, count: 40),
            2: try pageData(start: 41, count: 2)
        ]
        let client = SableLibraryBigBookCoversClient(
            apiBaseURL: URL(string: "https://example.com")!,
            dataLoader: { url in
                let components = URLComponents(
                    url: url,
                    resolvingAgainstBaseURL: false
                )
                let page = components?.queryItems?
                    .first(where: { $0.name == "page" })?
                    .value
                    .flatMap(Int.init) ?? 1
                return pages[page] ?? Data(#"{"data":{"amz":[]}}"#.utf8)
            }
        )

        let books = try await client.books(
            itemID: "B07JK95JJH",
            provider: .amazon
        )

        XCTAssertEqual(books.count, 42)
        XCTAssertEqual(books.last?.volumeNumber, 42)
    }

    func testAmazonSeriesBooksRespectExplicitFourPageBudget() async throws {
        let client = SableLibraryBigBookCoversClient(
            apiBaseURL: URL(string: "https://example.com")!,
            dataLoader: { url in
                let components = URLComponents(
                    url: url,
                    resolvingAgainstBaseURL: false
                )
                let page = components?.queryItems?
                    .first(where: { $0.name == "page" })?
                    .value
                    .flatMap(Int.init) ?? 1
                guard page <= 4 else {
                    throw URLError(.resourceUnavailable)
                }
                let start = ((page - 1) * 40) + 1
                let rows = (start..<(start + 40)).map { index in
                    [
                        "id": String(format: "B%09d", index),
                        "title": "Example, Vol. \(index)",
                        "cover": "https://example.com/\(index).jpg",
                        "volume": [
                            "type": "volume",
                            "number": String(index)
                        ]
                    ] as [String: Any]
                }
                return try JSONSerialization.data(
                    withJSONObject: ["data": ["amz": rows]]
                )
            }
        )

        let books = try await client.books(
            itemID: "B07JK95JJH",
            provider: .amazon,
            maximumPages: 4
        )

        XCTAssertEqual(books.count, 160)
        XCTAssertEqual(books.last?.volumeNumber, 160)
    }

    func testBBCSeriesBooksContinuePastFirstFortyForShueisha() async throws {
        func pageData(start: Int, count: Int) throws -> Data {
            let rows = (start..<(start + count)).map { index in
                [
                    "id": "978408\(String(format: "%07d", index))",
                    "title": "ONE PIECE \(index)",
                    "cover": "https://example.com/\(index).jpg",
                    "volume": [
                        "type": "volume",
                        "number": String(index)
                    ]
                ] as [String: Any]
            }
            return try JSONSerialization.data(
                withJSONObject: ["data": ["shueisha": rows]]
            )
        }

        let pages = [
            1: try pageData(start: 1, count: 40),
            2: try pageData(start: 41, count: 40),
            3: try pageData(start: 81, count: 35)
        ]
        let client = SableLibraryBigBookCoversClient(
            apiBaseURL: URL(string: "https://example.com")!,
            dataLoader: { url in
                let page = URLComponents(
                    url: url,
                    resolvingAgainstBaseURL: false
                )?.queryItems?
                    .first(where: { $0.name == "page" })?
                    .value
                    .flatMap(Int.init) ?? 1
                return pages[page]
                    ?? Data(#"{"data":{"shueisha":[]}}"#.utf8)
            }
        )

        let books = try await client.books(
            itemID: "35169",
            provider: .shueisha
        )

        XCTAssertEqual(books.count, 115)
        XCTAssertEqual(books.last?.volumeNumber, 115)
    }

    func testAmazonSeriesBooksRespectExplicitTwoPageBudget() async throws {
        let client = SableLibraryBigBookCoversClient(
            apiBaseURL: URL(string: "https://example.com")!,
            dataLoader: { url in
                let components = URLComponents(
                    url: url,
                    resolvingAgainstBaseURL: false
                )
                let page = components?.queryItems?
                    .first(where: { $0.name == "page" })?
                    .value
                    .flatMap(Int.init) ?? 1
                guard page <= 2 else {
                    throw URLError(.resourceUnavailable)
                }
                let start = ((page - 1) * 40) + 1
                let rows = (start..<(start + 40)).map { index in
                    [
                        "id": String(format: "B%09d", index),
                        "title": "Example, Vol. \(index)",
                        "cover": "https://example.com/\(index).jpg",
                        "volume": [
                            "type": "volume",
                            "number": String(index)
                        ]
                    ] as [String: Any]
                }
                return try JSONSerialization.data(
                    withJSONObject: ["data": ["amz": rows]]
                )
            }
        )

        let books = try await client.books(
            itemID: "B07JK95JJH",
            provider: .amazon,
            maximumPages: 2
        )

        XCTAssertEqual(books.count, 80)
        XCTAssertEqual(books.last?.volumeNumber, 80)
    }

    func testBBCBookLivePreviewBecomesASelectableImageAlternative() async throws {
        let client = SableLibraryBigBookCoversClient(
            apiBaseURL: URL(string: "https://example.com")!,
            dataLoader: { url in
                let providerIDs = try XCTUnwrap(
                    URLComponents(
                        url: url,
                        resolvingAgainstBaseURL: false
                    )?
                    .queryItems?
                    .filter { $0.name.hasPrefix("series(") }
                    .compactMap {
                        $0.name
                            .split(separator: "(")
                            .last?
                            .dropLast()
                    }
                )
                var data: [String: Any] = [:]
                for providerID in providerIDs {
                    let cover = providerID == "bl-r"
                        ? "https://c.roler.dev/bl/206718-001/0"
                        : "https://res.booklive.jp/206718/001/thumbnail/X.jpg"
                    data[String(providerID)] = [
                        [
                            "id": "206718-001",
                            "providerId": String(providerID),
                            "url":
                                "https://booklive.jp/product/index/title_id/206718/vol_no/001",
                            "title": "王様のベッド",
                            "cover": cover,
                            "seriesId": "206718",
                            "volume": [
                                "type": "volume",
                                "number": NSNull()
                            ]
                        ]
                    ]
                }
                return try JSONSerialization.data(
                    withJSONObject: ["data": data]
                )
            }
        )

        let books = try await client.booksWithPreviewAlternatives(
            itemID: "206718",
            provider: .bookLiveJP
        )

        XCTAssertEqual(books.count, 1)
        XCTAssertEqual(books.first?.volumeNumber, 1)
        XCTAssertEqual(
            books.first?.coverURL,
            "https://res.booklive.jp/206718/001/thumbnail/X.jpg"
        )
        XCTAssertEqual(
            books.first?.coverFallbackURLs,
            ["https://c.roler.dev/bl/206718-001/0"]
        )
    }

    func testBBCPreviewProvidersContinuePastFirstFortyRows() async throws {
        let client = SableLibraryBigBookCoversClient(
            apiBaseURL: URL(string: "https://example.com")!,
            dataLoader: { url in
                let components = URLComponents(
                    url: url,
                    resolvingAgainstBaseURL: false
                )
                let page = components?.queryItems?
                    .first(where: { $0.name == "page" })?
                    .value
                    .flatMap(Int.init) ?? 1
                let providerIDs = components?.queryItems?
                    .filter { $0.name.hasPrefix("series(") }
                    .compactMap {
                        $0.name.split(separator: "(").last?.dropLast()
                    } ?? []
                let range = page == 1 ? 1...40 : 41...42
                var response: [String: Any] = [:]
                for providerID in providerIDs {
                    response[String(providerID)] = range.map { index in
                        [
                            "id": "volume-\(index)",
                            "providerId": String(providerID),
                            "title": "Volume \(index)",
                            "cover":
                                "https://example.com/\(providerID)/\(index).jpg",
                            "volume": [
                                "type": "volume",
                                "number": String(index)
                            ]
                        ] as [String: Any]
                    }
                }
                return try JSONSerialization.data(
                    withJSONObject: ["data": response]
                )
            }
        )

        let books = try await client.booksWithPreviewAlternatives(
            itemID: "series-example",
            provider: .bookWalkerGlobal
        )

        XCTAssertEqual(books.count, 42)
        XCTAssertEqual(books.last?.volumeNumber, 42)
        XCTAssertEqual(books.last?.coverFallbackURLs.count, 1)
    }

    func testBBCBookWalkerPreviewCannotReplacePrimaryVolumeMetadata() async throws {
        let client = SableLibraryBigBookCoversClient(
            apiBaseURL: URL(string: "https://example.com")!,
            dataLoader: { url in
                let providerIDs = try XCTUnwrap(
                    URLComponents(
                        url: url,
                        resolvingAgainstBaseURL: false
                    )?
                    .queryItems?
                    .filter { $0.name.hasPrefix("series(") }
                    .compactMap {
                        $0.name
                            .split(separator: "(")
                            .last?
                            .dropLast()
                    }
                )
                var data: [String: Any] = [:]
                for providerID in providerIDs {
                    let isReader = providerID == "bw-r"
                        || providerID == "bw-war"
                    let cover = isReader
                        ? "https://c.roler.dev/bw/example/0"
                        : "https://c.bookwalker.jp/coverImage_123.jpg"
                    let volumeType = providerID == "bw-wa"
                        || providerID == "bw-war"
                        ? "chapter"
                        : "volume"
                    data[String(providerID)] = [
                        [
                            "id": "example",
                            "providerId": String(providerID),
                            "url": "https://bookwalker.jp/de-example",
                            "title": "Example 1",
                            "cover": cover,
                            "seriesId": "series-example",
                            "bookType": "manga",
                            "volume": [
                                "type": volumeType,
                                "number": "1"
                            ]
                        ]
                    ]
                }
                return try JSONSerialization.data(
                    withJSONObject: ["data": data]
                )
            }
        )

        let books = try await client.booksWithPreviewAlternatives(
            itemID: "series-example",
            provider: .bookWalkerJP
        )

        XCTAssertEqual(books.count, 1)
        XCTAssertEqual(books.first?.volumeType, "volume")
        XCTAssertEqual(books.first?.volumeNumber, 1)
        XCTAssertEqual(
            books.first?.coverURL,
            "https://c.bookwalker.jp/coverImage_123.jpg"
        )
        XCTAssertEqual(
            books.first?.coverFallbackURLs,
            ["https://c.roler.dev/bw/example/0"]
        )
    }

    func testAmazonBookRowsInferKindleAndPaperbackFormats() throws {
        let payload = Data(
            """
            {
              "data": {
                "amz": [
                  {
                    "id": "B00I9IO7FE",
                    "title": "One-Punch Man, Vol. 1",
                    "cover": "https://example.com/kindle.jpg",
                    "volume": {"type": "volume", "number": "1"}
                  },
                  {
                    "id": "1421585642",
                    "title": "One-Punch Man, Vol. 1",
                    "cover": "https://example.com/paper.jpg",
                    "volume": {"type": "volume", "number": "1"}
                  }
                ]
              }
            }
            """.utf8
        )

        let books = try SableLibraryBigBookCoversClient.bookCandidates(
            fromBooksData: payload,
            provider: .amazon
        )

        XCTAssertEqual(books.map(\.publicationType), ["digital", "physical"])
    }

    func testBookWalkerChapterTitlesOverrideIncorrectBBCNumbers() throws {
        let payload = Data(
            """
            {
              "data": {
                "bw-wa": [
                  {
                    "id": "6db99b37-632e-4a0e-92cb-256627002453",
                    "title": "第6話　“１人目”",
                    "cover": "https://c.bookwalker.jp/chapter-6.jpg",
                    "volume": {"type": "chapter", "number": "1"}
                  },
                  {
                    "id": "4101f778-ad1f-4155-9333-8a7075920ef7",
                    "title": "第28話　“三日月”",
                    "cover": "https://c.bookwalker.jp/chapter-28.jpg",
                    "volume": {"type": "chapter", "number": "3"}
                  },
                  {
                    "id": "chapter-37",
                    "title": "第37話　海賊“百計のクロ”",
                    "cover": "https://c.bookwalker.jp/chapter-37.jpg",
                    "volume": {"type": "chapter", "number": "100"}
                  }
                ]
              }
            }
            """.utf8
        )

        let books = try SableLibraryBigBookCoversClient.bookCandidates(
            fromBooksData: payload,
            provider: .bookWalkerJP,
            responseProviderID: "bw-wa"
        )

        XCTAssertEqual(books.count, 3)
        XCTAssertTrue(books.allSatisfy { $0.volumeType == "chapter" })
        XCTAssertEqual(books.map(\.volumeNumber), [6, 28, 37])
        XCTAssertEqual(books.map(\.sequenceIndex), [6, 28, 37])

        let candidates = SableMangaBakaStorefrontDiscovery
            .exactStoreChapterCandidates(
                from: books,
                source: .bookWalkerJP,
                language: "ja"
            )
        XCTAssertTrue(candidates.allSatisfy { $0.providerType == "chapter" })
        XCTAssertEqual(candidates.map(\.volumeNumber), [6, 28, 37])
    }

    func testBookLiveBBCRowsKeepDistinctVolumeSlots() throws {
        let rows = (1...8).map { volume in
            """
            {
              "id": "965497-\(String(format: "%03d", volume))",
              "providerId": "bl",
              "url": "https://booklive.jp/product/index/title_id/965497/vol_no/\(String(format: "%03d", volume))",
              "title": "ループ7回目の悪役令嬢は、元敵国で自由気ままな花嫁生活を満喫する \(volume)",
              "cover": "https://res.booklive.jp/965497/\(String(format: "%03d", volume))/thumbnail/X.jpg",
              "seriesId": "965497",
              "volume": {"type": "volume", "number": "\(volume)"}
            }
            """
        }
        .joined(separator: ",")
        let payload = Data(
            """
            {
              "data": {
                "bl": [
                  \(rows)
                ]
              }
            }
            """.utf8
        )

        var books = try SableLibraryBigBookCoversClient.bookCandidates(
            fromBooksData: payload,
            provider: .bookLiveJP
        )
        books = books.map { book in
            var typedBook = book
            typedBook.bookType = "manga"
            return typedBook
        }
        let candidates = SableLibraryProviderCandidateParser
            .bigBookCoversCandidates(
                from: books,
                source: .bookLiveJP,
                language: "ja",
                mediaType: "manga"
            )
        let suggestions = candidates.map {
            SableMangaBakaStorefrontCoverSuggestion(
                provider: .bookLiveJP,
                providerSeriesID: $0.providerSeriesID,
                providerItemID: $0.providerItemID,
                title: $0.title ?? "",
                imageURL: $0.imageURL,
                volumeNumber: $0.volumeNumber ?? 0,
                language: "ja",
                coverType: "volume",
                expectedMediaType: "manga",
                detectedMediaType: $0.mediaType,
                width: 1_440,
                height: 2_048,
                contentRating: "safe"
            )
        }

        XCTAssertEqual(books.map(\.volumeNumber), (1...8).map(Double.init))
        XCTAssertEqual(candidates.map(\.volumeNumber), (1...8).map(Double.init))
        XCTAssertEqual(
            SableMangaBakaStorefrontDiscovery
                .presentationSuggestions(from: suggestions)
                .map(\.volumeNumber),
            (1...8).map(Double.init)
        )
    }

    func testBookLiveScopingKeepsPrimaryJapaneseTitleVolumes() throws {
        let rows = (1...8).map { volume in
            """
            {
              "id": "965497-\(String(format: "%03d", volume))",
              "providerId": "bl",
              "url": "https://booklive.jp/product/index/title_id/965497/vol_no/\(String(format: "%03d", volume))",
              "title": "ループ7回目の悪役令嬢は、元敵国で自由気ままな花嫁生活を満喫する \(volume)",
              "cover": "https://res.booklive.jp/965497/\(String(format: "%03d", volume))/thumbnail/X.jpg",
              "seriesId": "965497",
              "volume": {"type": "volume", "number": "\(volume)"}
            }
            """
        }
        .joined(separator: ",")
        let payload = Data(
            """
            {
              "data": {
                "bl": [
                  \(rows)
                ]
              }
            }
            """.utf8
        )
        let books = try SableLibraryBigBookCoversClient.bookCandidates(
            fromBooksData: payload,
            provider: .bookLiveJP
        )
        let series = SableMangaBakaSeriesSummary(
            id: 369,
            title:
                "7th Time Loop: The Villainess Enjoys a Carefree Life Married to Her Worst Enemy!",
            nativeTitle:
                "ループ7回目の悪役令嬢は、元敵国で自由気ままな花嫁生活を満喫する",
            romanizedTitle: nil,
            titles: [
                SableMangaBakaSeriesTitle(
                    language: "en",
                    traits: ["official"],
                    title: "7th Time Loop: The Villainess Enjoys a Carefree Life",
                    isPrimary: false
                ),
                SableMangaBakaSeriesTitle(
                    language: "en",
                    traits: ["official"],
                    title:
                        "7th Time Loop: The Villainess Enjoys a Carefree Life Married to Her Worst Enemy!",
                    isPrimary: true
                ),
                SableMangaBakaSeriesTitle(
                    language: "ja",
                    traits: ["native"],
                    title:
                        "ループ7回目の悪役令嬢は、元敵国で自由気ままな花嫁（人質）生活を満喫する",
                    isPrimary: false
                ),
                SableMangaBakaSeriesTitle(
                    language: "ja",
                    traits: ["native"],
                    title:
                        "ループ7回目の悪役令嬢は、元敵国で自由気ままな花嫁生活を満喫する",
                    isPrimary: true
                )
            ],
            type: "manga",
            cover: nil,
            finalVolume: nil
        )

        let scoped = SableMangaBakaStorefrontDiscovery
            .booksScopedToSelectedSeries(books, series: series, language: "ja")

        XCTAssertEqual(scoped.count, 8)
        XCTAssertEqual(scoped.map(\.volumeNumber), (1...8).map(Double.init))
    }

    func testAmazonBookRowsInferJapaneseMangaFromComicLabel() throws {
        let payload = Data(
            """
            {
              "data": {
                "amz-jp": [
                  {
                    "id": "408870701X",
                    "title": "ワンパンマン 1 (ジャンプコミックス)",
                    "cover": "https://example.com/paper.jpg",
                    "volume": {"type": "volume", "number": "1"}
                  },
                  {
                    "id": "B01FU3MY2S",
                    "title": "ワンパンマン 1 (ジャンプコミックスDIGITAL)",
                    "cover": "https://example.com/digital.jpg",
                    "volume": {"type": "volume", "number": "1"}
                  }
                ]
              }
            }
            """.utf8
        )

        let books = try SableLibraryBigBookCoversClient.bookCandidates(
            fromBooksData: payload,
            provider: .amazonJP
        )

        XCTAssertEqual(books.map(\.bookType), ["manga", "manga"])
        XCTAssertEqual(books.map(\.publicationType), ["physical", "digital"])
    }

    func testAmazonBookRowsTreatKindleAsDigitalEvidence() throws {
        let payload = Data(
            """
            {
              "data": {
                "amz": [
                  {
                    "id": "123456789X",
                    "title": "Example, Vol. 1 (Kindle Edition)",
                    "cover": "https://example.com/kindle.jpg",
                    "volume": {"type": "volume", "number": "1"}
                  }
                ]
              }
            }
            """.utf8
        )

        let books = try SableLibraryBigBookCoversClient.bookCandidates(
            fromBooksData: payload,
            provider: .amazon
        )

        XCTAssertEqual(books.first?.publicationType, "digital")
    }

    func testAmazonSearchRowsInferJapanesePaperbackFormat() throws {
        let payload = Data(
            """
            {
              "data": {
                "amz-jp": [
                  {
                    "id": "4088707028",
                    "title": "ワンパンマン 2 (ジャンプコミックス)",
                    "type": "book",
                    "thumbnail": "https://example.com/paper.jpg"
                  }
                ]
              }
            }
            """.utf8
        )

        let candidates = try SableLibraryBigBookCoversClient.seriesCandidates(
            fromSearchData: payload,
            provider: .amazonJP
        )

        XCTAssertEqual(candidates.first?.publicationType, "physical")
    }

    func testAmazonNovelSeriesSelectionKeepsTheWholeBBCSeries() throws {
        let searchPayload = Data(
            """
            {
              "data": {
                "amz": [
                  {
                    "id": "B0B3JHX9D2",
                    "type": "series",
                    "title": "The Beginning After the End (comic)",
                    "bookType": "manga"
                  },
                  {
                    "id": "B0G4S8K7LN",
                    "type": "series",
                    "title": "The Beginning after the End",
                    "bookType": null
                  },
                  {
                    "id": "B0G34PSB1C",
                    "type": "book",
                    "title": "Early Years: The Beginning After the End: (Remastered Edition)",
                    "bookType": null
                  }
                ]
              }
            }
            """.utf8
        )
        let candidates = try SableLibraryBigBookCoversClient.seriesCandidates(
            fromSearchData: searchPayload,
            provider: .amazon
        )
        let ranked = SableLibraryCoverDownloadPlanner
            .rankedSeriesCandidates(
                for: "The Beginning After the End",
                in: candidates,
                mediaType: "novel"
            )

        XCTAssertEqual(ranked.first?.id, "B0G4S8K7LN")
        XCTAssertEqual(ranked.first?.type, "series")
        XCTAssertFalse(ranked.first?.bookTypeWasExplicit ?? true)

        let rows: [[String: Any]] = (1...12).map { volume in
            [
                "id": "BOOK-\(volume)",
                "title": "The Beginning After the End, Book \(volume)",
                "cover": "https://images.example/\(volume).jpg",
                "seriesId": "B0G4S8K7LN",
                "volume": [
                    "type": "volume",
                    "number": String(volume)
                ]
            ]
        }
        let booksPayload = try JSONSerialization.data(
            withJSONObject: ["data": ["amz": rows]]
        )
        let books = try SableLibraryBigBookCoversClient.bookCandidates(
            fromBooksData: booksPayload,
            provider: .amazon
        )

        XCTAssertEqual(books.count, 12)
        XCTAssertEqual(Set(books.compactMap(\.seriesID)), ["B0G4S8K7LN"])
        XCTAssertEqual(
            books.compactMap(\.volumeNumber),
            (1...12).map(Double.init)
        )
    }

    func testAmazonSeriesBooksUseUnscaledBBCSearchImagesAsFallbacks() {
        let series = SableMangaBakaSeriesSummary(
            id: 186_987,
            title: "The Beginning After the End",
            nativeTitle: nil,
            romanizedTitle: nil,
            titles: nil,
            type: "novel",
            cover: nil,
            finalVolume: nil
        )
        let books = [
            SableLibraryBigBookCoversBookCandidate(
                provider: .amazon,
                id: "B0DH5TJ9F3",
                seriesID: "B0G4S8K7LN",
                title: "New Heights: The Beginning After the End, Book 2",
                url: "https://www.amazon.com/dp/B0DH5TJ9F3",
                coverURL:
                    "https://m.media-amazon.com/images/P/B0DH5TJ9F3.01.MAIN._SCRM_.jpg",
                coverFallbackURLs: [
                    "https://m.media-amazon.com/images/P/B0DH5TJ9F3.01.MAIN.L.jpg"
                ],
                volumeNumber: 2,
                volumeType: "volume",
                sequenceIndex: 2,
                bookType: nil,
                publicationType: "digital"
            )
        ]
        let candidates = [
            SableLibraryBigBookCoversSeriesCandidate(
                provider: .amazon,
                id: "B0DH5TJ9F3",
                title: "New Heights: The Beginning After the End, Book 2",
                url: "https://www.amazon.com/dp/B0DH5TJ9F3",
                type: "book",
                bookType: nil,
                thumbnailURL:
                    "https://m.media-amazon.com/images/I/81wxb5p3YxL._AC_UL320_.jpg",
                publicationType: "digital"
            )
        ]

        let enriched = SableMangaBakaStorefrontDiscovery
            .amazonBooksByAddingDirectResults(
                books,
                from: candidates,
                selectedSeriesID: "B0G4S8K7LN",
                series: series,
                language: "en"
            )

        XCTAssertEqual(enriched.count, 1)
        XCTAssertEqual(
            enriched[0].coverFallbackURLs,
            [
                "https://m.media-amazon.com/images/P/B0DH5TJ9F3.01.MAIN.L.jpg",
                "https://m.media-amazon.com/images/I/81wxb5p3YxL.jpg",
                "https://m.media-amazon.com/images/I/81wxb5p3YxL._AC_UL320_.jpg"
            ]
        )
    }

    func testAmazonSearchImageCanRescueSameTitleWithChangedASIN() {
        let series = SableMangaBakaSeriesSummary(
            id: 186_987,
            title: "The Beginning After the End",
            nativeTitle: nil,
            romanizedTitle: nil,
            titles: nil,
            type: "novel",
            cover: nil,
            finalVolume: nil
        )
        let books = [
            SableLibraryBigBookCoversBookCandidate(
                provider: .amazon,
                id: "B0DH5CX7XM",
                seriesID: "B0G4S8K7LN",
                title: "Beckoning Fates: The Beginning After the End, Book 3",
                url: "https://www.amazon.com/dp/B0DH5CX7XM",
                coverURL:
                    "https://m.media-amazon.com/images/P/B0DH5CX7XM.01.MAIN._SCRM_.jpg",
                coverFallbackURLs: [],
                volumeNumber: 3,
                volumeType: "volume",
                sequenceIndex: 3,
                bookType: nil,
                publicationType: "digital"
            )
        ]
        let candidates = [
            SableLibraryBigBookCoversSeriesCandidate(
                provider: .amazon,
                id: "B0G4S4676K",
                title: "Beckoning Fates: The Beginning After the End, Book 3",
                url: "https://www.amazon.com/dp/B0G4S4676K",
                type: "book",
                bookType: nil,
                thumbnailURL:
                    "https://m.media-amazon.com/images/I/813HUQwmEnL._AC_UL320_.jpg",
                publicationType: "digital"
            )
        ]

        let enriched = SableMangaBakaStorefrontDiscovery
            .amazonBooksByAddingDirectResults(
                books,
                from: candidates,
                selectedSeriesID: "B0G4S8K7LN",
                series: series,
                language: "en"
            )

        XCTAssertEqual(enriched.count, 1)
        XCTAssertEqual(
            enriched[0].coverFallbackURLs.first,
            "https://m.media-amazon.com/images/I/813HUQwmEnL.jpg"
        )
    }

    func testAmazonJapanesePaperFormatSwitcherFindsPhysicalASIN() {
        let html = """
        <div id="tmmSwatches">
          <div id="tmm-grid-swatch-KINDLE" role="listitem">
            <a href="/dp/B01FU3MY46/ref=tmm_kin_swatch_0">
              Kindle Edition
            </a>
          </div>
          <div id="tmm-grid-swatch-OTHER" role="listitem">
            <a href="/-/en/One-Punch-Man/dp/4088707028/ref=tmm_other_meta_binding_swatch_0">
              <span class="slot-title">
                <span aria-label="Comics (Paper) Format:">Comics (Paper)</span>
              </span>
            </a>
            <a href="/gp/offer-listing/4088707028">Other offers</a>
          </div>
        </div>
        """

        XCTAssertEqual(
            SableMangaBakaStorefrontDiscovery
                .amazonPhysicalFormatIdentifier(in: html),
            "4088707028"
        )
    }

    func testAmazonJapaneseKindleMetadataFindsPrintEditionISBN() {
        let html = """
        <span
          data-a-popover="{
            &quot;inlineContent&quot;:
            &quot;Based on the print edition (ISBN 408870701X).&quot;
          }"
        >
          200 pages
        </span>
        """

        XCTAssertEqual(
            SableMangaBakaStorefrontDiscovery
                .amazonPhysicalFormatIdentifier(in: html),
            "408870701X"
        )
    }

    func testAmazonJapaneseFormatSwitcherIgnoresDigitalOnlySwatch() {
        let html = """
        <div id="tmm-grid-swatch-KINDLE" role="listitem">
          <a href="/dp/B01FU3MY2S/ref=tmm_kin_swatch_0">
            Kindle Edition
          </a>
        </div>
        """

        XCTAssertNil(
            SableMangaBakaStorefrontDiscovery
                .amazonPhysicalFormatIdentifier(in: html)
        )
    }

    func testAmazonDirectResultsAddLateVolumesButIgnoreCollections() {
        let series = SableMangaBakaSeriesSummary(
            id: 725,
            title: "ONE-PUNCH MAN",
            nativeTitle: "ONE PUNCH-MAN",
            romanizedTitle: nil,
            type: "manga"
        )
        let existing = [
            SableLibraryBigBookCoversBookCandidate(
                provider: .amazonUK,
                id: "1974755398",
                seriesID: "B07JK95JJH",
                title: "One-Punch Man, Vol. 31",
                url: "https://www.amazon.co.uk/dp/1974755398",
                coverURL: "https://example.com/31.jpg",
                coverFallbackURLs: [],
                volumeNumber: 31,
                volumeType: "volume",
                sequenceIndex: 31,
                bookType: "manga",
                publicationType: "physical"
            )
        ]
        let candidates = [
            SableLibraryBigBookCoversSeriesCandidate(
                provider: .amazonUK,
                id: "1974771539",
                title: "One-Punch Man, Vol. 36: Volume 36",
                url: "https://www.amazon.co.uk/dp/1974771539",
                type: "book",
                bookType: "manga",
                thumbnailURL: "https://example.com/36.jpg",
                publicationType: "physical"
            ),
            SableLibraryBigBookCoversSeriesCandidate(
                provider: .amazonUK,
                id: "B01N2GGCFC",
                title: "One-Punch Man Volume 6-10 Collection 5 Books Set",
                url: "https://www.amazon.co.uk/dp/B01N2GGCFC",
                type: "book",
                bookType: "manga",
                thumbnailURL: "https://example.com/set.jpg",
                publicationType: "physical"
            )
        ]

        let merged = SableMangaBakaStorefrontDiscovery
            .amazonBooksByAddingDirectResults(
                existing,
                from: candidates,
                selectedSeriesID: "B07JK95JJH",
                series: series,
                language: "en"
            )

        XCTAssertEqual(merged.compactMap(\.volumeNumber), [31, 36])
    }

    func testAmazonJapanesePaperbackDirectResultKeepsMangaProof() {
        let series = SableMangaBakaSeriesSummary(
            id: 725,
            title: "ONE-PUNCH MAN",
            nativeTitle: "ワンパンマン",
            romanizedTitle: nil,
            type: "manga"
        )
        let paperback = SableLibraryBigBookCoversSeriesCandidate(
            provider: .amazonJP,
            id: "4088707028",
            title: "ワンパンマン 2 (ジャンプコミックス)",
            url: "https://www.amazon.co.jp/dp/4088707028",
            type: "book",
            bookType: nil,
            thumbnailURL: "https://example.com/paper.jpg",
            publicationType: nil
        )

        let merged = SableMangaBakaStorefrontDiscovery
            .amazonBooksByAddingDirectResults(
                [],
                from: [paperback],
                selectedSeriesID: "B074CGZDXX",
                series: series,
                language: "ja"
            )

        XCTAssertEqual(merged.first?.publicationType, "physical")
        XCTAssertEqual(merged.first?.bookType, "manga")
        XCTAssertEqual(merged.first?.volumeNumber, 2)
    }

    func testSelectBestUsesQualityAcrossPrintAndDigitalFormats() {
        let print = storefrontSuggestion(
            provider: .amazon,
            language: "en",
            width: 1_600,
            height: 2_400,
            publicationType: "physical"
        )
        let digital = storefrontSuggestion(
            provider: .amazon,
            language: "en",
            width: 2_000,
            height: 3_000,
            publicationType: "digital"
        )

        let preferred = SableMangaBakaStorefrontDiscovery
            .preferredSuggestions(from: [digital, print])

        XCTAssertEqual(preferred.count, 1)
        XCTAssertEqual(preferred.first?.publicationType, "digital")
        XCTAssertEqual(preferred.first?.imageURL, digital.imageURL)
    }

    func testPresentationKeepsDistinctPrintAndDigitalEditions() {
        let print = storefrontSuggestion(
            provider: .amazonJP,
            language: "ja",
            publicationType: "physical"
        )
        let digital = storefrontSuggestion(
            provider: .amazonJP,
            language: "ja",
            publicationType: "digital"
        )

        let presented = SableMangaBakaStorefrontDiscovery
            .presentationSuggestions(from: [print, digital])

        XCTAssertEqual(presented.count, 2)
    }

    @MainActor
    func testPrintAndDigitalLanesHaveIndependentAcceptance() {
        var print = storefrontSuggestion(
            provider: .amazonJP,
            language: "ja",
            publicationType: "physical"
        )
        print.requiresRelationshipReview = true
        var digital = storefrontSuggestion(
            provider: .amazonJP,
            language: "ja",
            publicationType: "digital"
        )
        digital.requiresRelationshipReview = true

        let store = SableMangaBakaCoverStudioStore()
        store.storefrontSuggestions = [print, digital]
        store.setStorefrontRelationshipReviewApproved(
            language: "ja",
            provider: .amazonJP,
            publicationType: "physical",
            isApproved: true
        )

        XCTAssertTrue(
            store.storefrontRelationshipReviewIsApproved(for: print)
        )
        XCTAssertFalse(
            store.storefrontRelationshipReviewIsApproved(for: digital)
        )
    }

    @MainActor
    func testDigitalLabelStillCompetesUntilItsGroupIsRejected() {
        let print = storefrontSuggestion(
            provider: .amazonJP,
            language: "ja",
            width: 1_600,
            height: 2_400,
            publicationType: "physical"
        )
        var digital = storefrontSuggestion(
            provider: .amazonJP,
            language: "ja",
            width: 2_000,
            height: 3_000,
            publicationType: "digital"
        )
        digital.providerItemID = "digital"
        digital.imageURL = "https://example.com/digital.jpg"

        let store = SableMangaBakaCoverStudioStore()
        store.storefrontSuggestions = [print, digital]

        XCTAssertEqual(
            store.bestActionableStorefrontSuggestions(
                from: store.storefrontSuggestions
            ).first?.imageURL,
            digital.imageURL
        )

        store.setStorefrontRelationshipReviewRejected(
            language: "ja",
            provider: .amazonJP,
            publicationType: "digital",
            isRejected: true
        )

        XCTAssertEqual(
            store.bestActionableStorefrontSuggestions(
                from: store.storefrontSuggestions
            ).first?.imageURL,
            print.imageURL
        )
    }

    @MainActor
    func testChangingDigitalLabelKeepsTheUsersSeriesDecision() throws {
        var suggestion = storefrontSuggestion(
            provider: .amazonJP,
            language: "ja",
            publicationType: nil
        )
        suggestion.requiresRelationshipReview = true
        let store = SableMangaBakaCoverStudioStore()
        store.storefrontSuggestions = [suggestion]
        store.setStorefrontRelationshipReviewApproved(
            language: "ja",
            provider: .amazonJP,
            publicationType: nil,
            isApproved: true
        )

        store.setStorefrontSuggestionsAsDigital(
            [suggestion],
            isDigital: true
        )

        let relabeled = try XCTUnwrap(store.storefrontSuggestions.first)
        XCTAssertTrue(relabeled.isDigitalEdition)
        XCTAssertTrue(
            store.storefrontRelationshipReviewIsApproved(
                for: relabeled
            )
        )
    }

    func testSelectBestKeepsDigitalSlotWhenOnlyDigitalResultsAreVisible() {
        let lowerQuality = storefrontSuggestion(
            provider: .amazon,
            language: "en",
            width: 1_000,
            height: 1_500,
            publicationType: "digital"
        )
        var higherQuality = lowerQuality
        higherQuality.providerItemID = "higher-quality"
        higherQuality.imageURL = "https://example.com/higher-quality.jpg"
        higherQuality.width = 2_000
        higherQuality.height = 3_000

        let preferred = SableMangaBakaStorefrontDiscovery
            .preferredSuggestions(from: [lowerQuality, higherQuality])

        XCTAssertEqual(preferred.count, 1)
        XCTAssertEqual(preferred.first?.imageURL, higherQuality.imageURL)
        XCTAssertEqual(preferred.first?.publicationType, "digital")
    }

    func testProviderPresentationKeepsAlternativesFromEachStorefront() {
        let suggestions = [
            storefrontSuggestion(provider: .bookLiveJP, language: "ja"),
            storefrontSuggestion(provider: .bookWalkerJP, language: "ja"),
            storefrontSuggestion(provider: .amazonJP, language: "ja")
        ]

        let presented =
            SableMangaBakaStorefrontDiscovery.presentationSuggestions(
                from: suggestions
            )

        XCTAssertEqual(presented.count, 3)
        XCTAssertEqual(
            presented.map(\.provider),
            [.bookLiveJP, .bookWalkerJP, .amazonJP]
        )
    }

    func testUnscopedStoreBooksRemainVisibleButRequireReview() {
        let series = SableMangaBakaSeriesSummary(
            id: 59_029,
            title: "Agents of the Four Seasons",
            nativeTitle: "春夏秋冬代行者 春の舞",
            romanizedTitle: nil,
            titles: [
                SableMangaBakaSeriesTitle(
                    language: "ja",
                    traits: ["native"],
                    title: "春夏秋冬代行者 春の舞",
                    isPrimary: true
                ),
                SableMangaBakaSeriesTitle(
                    language: "ja",
                    traits: [],
                    title: "春夏秋冬代行者",
                    isPrimary: false
                )
            ],
            type: "manga",
            cover: nil,
            finalVolume: nil
        )
        let siblingBooks = [
            storefrontBook(
                id: "bookwalker-sibling",
                title: "春夏秋冬代行者 百歌百葉 1巻",
                sequence: 1
            )
        ]

        let result = SableMangaBakaStorefrontDiscovery.providerBooksForReview(
            siblingBooks,
            series: series,
            language: "ja",
            trustsSelectedSeriesIdentity: false
        )

        XCTAssertEqual(result.books.map(\.id), ["bookwalker-sibling"])
        XCTAssertTrue(result.requiresRelationshipReview)
    }

    func testAutomaticMatchConfidenceRequiresStoreTypeAndSpecificTitle() {
        let series = SableMangaBakaSeriesSummary(
            id: 59_029,
            title: "Agents of the Four Seasons",
            nativeTitle: "春夏秋冬代行者 春の舞",
            romanizedTitle: nil,
            titles: [
                SableMangaBakaSeriesTitle(
                    language: "ja",
                    traits: ["native"],
                    title: "春夏秋冬代行者 春の舞",
                    isPrimary: true
                ),
                SableMangaBakaSeriesTitle(
                    language: "ja",
                    traits: [],
                    title: "春夏秋冬代行者",
                    isPrimary: false
                )
            ],
            type: "manga",
            cover: nil,
            finalVolume: nil
        )

        let exact = SableMangaBakaStorefrontDiscovery
            .automaticMatchConfidence(
                providerTitles: ["春夏秋冬代行者 春の舞 2"],
                series: series,
                language: "ja",
                detectedMediaType: "manga",
                expectedMediaType: "manga"
            )
        let sibling = SableMangaBakaStorefrontDiscovery
            .automaticMatchConfidence(
                providerTitles: ["春夏秋冬代行者 百歌百葉 2"],
                series: series,
                language: "ja",
                detectedMediaType: "manga",
                expectedMediaType: "manga"
            )
        let unprovenType = SableMangaBakaStorefrontDiscovery
            .automaticMatchConfidence(
                providerTitles: ["春夏秋冬代行者 春の舞 2"],
                series: series,
                language: "ja",
                detectedMediaType: nil,
                expectedMediaType: "manga"
            )

        XCTAssertGreaterThanOrEqual(exact, 0.90)
        XCTAssertLessThan(sibling, 0.90)
        XCTAssertEqual(unprovenType, 0)
    }

    func testManualStoreLinkTrustsTheUserChosenRelationship() {
        let series = SableMangaBakaSeriesSummary(
            id: 64_161,
            title: "Agents of the Four Seasons",
            nativeTitle: "春夏秋冬代行者 百歌百葉",
            romanizedTitle: nil,
            titles: nil,
            type: "manga",
            cover: nil,
            finalVolume: nil
        )
        let manuallyChosenBooks = [
            storefrontBook(
                id: "bookwalker-manual",
                title: "Agents of the Four Seasons, Chapter 3",
                sequence: 3
            )
        ]

        let result = SableMangaBakaStorefrontDiscovery.providerBooksForReview(
            manuallyChosenBooks,
            series: series,
            language: "en",
            trustsSelectedSeriesIdentity: true
        )

        XCTAssertEqual(result.books.map(\.id), ["bookwalker-manual"])
        XCTAssertFalse(result.requiresRelationshipReview)
    }

    func testTrustedResultWinsAutomaticSlotOverRelatedAlternative() {
        let trusted = storefrontSuggestion(
            provider: .bookLiveJP,
            language: "ja",
            width: 900,
            height: 1_280
        )
        let related = storefrontSuggestion(
            provider: .bookWalkerJP,
            language: "ja",
            width: 1_800,
            height: 2_560,
            requiresRelationshipReview: true
        )

        let preferred = SableMangaBakaStorefrontDiscovery.preferredSuggestions(
            from: [related, trusted]
        )

        XCTAssertEqual(preferred, [trusted])
    }

    @MainActor
    func testRelatedResultsStartUncheckedDuringAutomaticSelection() {
        let related = storefrontSuggestion(
            provider: .bookWalkerJP,
            language: "ja",
            width: 1_800,
            height: 2_560,
            requiresRelationshipReview: true
        )
        let trusted = storefrontSuggestion(
            provider: .bookLiveJP,
            language: "ja",
            width: 1_200,
            height: 1_800
        )

        XCTAssertEqual(
            SableMangaBakaCoverStudioStore
                .automaticallySelectedStorefrontSuggestions(
                    from: [related, trusted]
                ),
            [trusted]
        )
    }

    @MainActor
    func testStrongStoreEvidenceProvisionallyAcceptsRelatedResults() {
        let confident = storefrontSuggestion(
            provider: .bookWalkerGlobal,
            language: "en",
            width: 1_733,
            height: 2_600,
            requiresRelationshipReview: true,
            automaticMatchConfidence: 0.96,
            expectedMediaType: "novel",
            detectedMediaType: "novel"
        )
        let store = SableMangaBakaCoverStudioStore()
        store.storefrontSuggestions = [confident]

        store.selectBestStorefrontSuggestions(from: [confident])

        XCTAssertTrue(
            store.storefrontRelationshipReviewIsAutomaticallyApproved(
                for: confident
            )
        )
        XCTAssertFalse(store.storefrontSuggestionNeedsReview(confident))
        XCTAssertEqual(
            store.selectedStorefrontSuggestionIDs,
            Set([confident.id])
        )
        XCTAssertTrue(store.approvedStorefrontReviewGroupIDs.isEmpty)
    }

    @MainActor
    func testUnprovenStoreTypeStillRequiresManualReview() {
        let unproven = storefrontSuggestion(
            provider: .bookWalkerGlobal,
            language: "en",
            width: 1_733,
            height: 2_600,
            requiresRelationshipReview: true,
            automaticMatchConfidence: 0.96,
            expectedMediaType: "novel",
            detectedMediaType: nil
        )
        let store = SableMangaBakaCoverStudioStore()
        store.storefrontSuggestions = [unproven]

        store.selectBestStorefrontSuggestions(from: [unproven])

        XCTAssertFalse(
            store.storefrontRelationshipReviewIsAutomaticallyApproved(
                for: unproven
            )
        )
        XCTAssertTrue(store.storefrontSuggestionNeedsReview(unproven))
        XCTAssertTrue(store.selectedStorefrontSuggestionIDs.isEmpty)
    }

    @MainActor
    func testRejectingAConfidentMatchOverridesAutomaticAcceptance() {
        let confident = storefrontSuggestion(
            provider: .bookWalkerGlobal,
            language: "en",
            width: 1_733,
            height: 2_600,
            requiresRelationshipReview: true,
            automaticMatchConfidence: 0.96,
            expectedMediaType: "novel",
            detectedMediaType: "novel"
        )
        let store = SableMangaBakaCoverStudioStore()
        store.storefrontSuggestions = [confident]

        store.setStorefrontRelationshipReviewRejected(
            language: "en",
            provider: .bookWalkerGlobal,
            isRejected: true
        )
        store.selectBestStorefrontSuggestions(from: [confident])

        XCTAssertFalse(
            store.storefrontRelationshipReviewIsAutomaticallyApproved(
                for: confident
            )
        )
        XCTAssertTrue(store.storefrontSuggestionNeedsReview(confident))
        XCTAssertTrue(store.selectedStorefrontSuggestionIDs.isEmpty)
    }

    @MainActor
    func testAcceptingProviderSeriesLetsSelectBestUseReviewedResults() {
        let related = storefrontSuggestion(
            provider: .ridibooks,
            language: "ko",
            width: 960,
            height: 1_440,
            requiresRelationshipReview: true
        )
        let store = SableMangaBakaCoverStudioStore()
        store.storefrontSuggestions = [related]

        store.selectBestStorefrontSuggestions(from: [related])
        XCTAssertTrue(store.selectedStorefrontSuggestionIDs.isEmpty)
        XCTAssertTrue(store.storefrontSuggestionNeedsReview(related))

        store.setStorefrontRelationshipReviewApproved(
            language: "ko",
            provider: .ridibooks,
            isApproved: true
        )
        store.selectBestStorefrontSuggestions(from: [related])

        XCTAssertFalse(store.storefrontSuggestionNeedsReview(related))
        XCTAssertEqual(
            store.selectedStorefrontSuggestionIDs,
            Set([related.id])
        )

        store.setStorefrontRelationshipReviewApproved(
            language: "ko",
            provider: .ridibooks,
            isApproved: false
        )
        XCTAssertTrue(store.selectedStorefrontSuggestionIDs.isEmpty)
        XCTAssertTrue(store.storefrontSuggestionNeedsReview(related))
    }

    @MainActor
    func testSelectBestPrefersAcceptedHigherResolutionSourceOverTrustedAmazon() {
        let bookWalker = storefrontSuggestion(
            provider: .bookWalkerGlobal,
            language: "en",
            width: 1_733,
            height: 2_600,
            requiresRelationshipReview: true
        )
        let amazon = storefrontSuggestion(
            provider: .amazon,
            language: "en",
            width: 1_706,
            height: 2_560
        )
        let store = SableMangaBakaCoverStudioStore()
        store.storefrontSuggestions = [amazon, bookWalker]

        store.selectBestStorefrontSuggestions(from: store.storefrontSuggestions)
        XCTAssertEqual(
            store.selectedStorefrontSuggestionIDs,
            Set([amazon.id])
        )

        store.setStorefrontRelationshipReviewApproved(
            language: "en",
            provider: .bookWalkerGlobal,
            isApproved: true
        )
        store.selectBestStorefrontSuggestions(from: store.storefrontSuggestions)

        XCTAssertEqual(
            store.selectedStorefrontSuggestionIDs,
            Set([bookWalker.id])
        )
    }

    @MainActor
    func testRejectingProviderSeriesClearsAndExcludesItsCovers() {
        let rejected = storefrontSuggestion(
            provider: .bookWalkerGlobal,
            language: "en",
            width: 1_733,
            height: 2_600
        )
        let fallback = storefrontSuggestion(
            provider: .amazon,
            language: "en",
            width: 1_706,
            height: 2_560
        )
        let store = SableMangaBakaCoverStudioStore()
        store.storefrontSuggestions = [rejected, fallback]
        store.selectBestStorefrontSuggestions(from: store.storefrontSuggestions)
        XCTAssertEqual(
            store.selectedStorefrontSuggestionIDs,
            Set([rejected.id])
        )

        store.setStorefrontRelationshipReviewRejected(
            language: "en",
            provider: .bookWalkerGlobal,
            isRejected: true
        )
        store.selectBestStorefrontSuggestions(from: store.storefrontSuggestions)

        XCTAssertTrue(
            store.storefrontRelationshipReviewIsRejected(for: rejected)
        )
        XCTAssertFalse(store.storefrontSuggestionIsActionable(rejected))
        XCTAssertEqual(
            store.selectedStorefrontSuggestionIDs,
            Set([fallback.id])
        )

        store.setStorefrontRelationshipReviewRejected(
            language: "en",
            provider: .bookWalkerGlobal,
            isRejected: false
        )
        store.selectBestStorefrontSuggestions(from: store.storefrontSuggestions)
        XCTAssertEqual(
            store.selectedStorefrontSuggestionIDs,
            Set([rejected.id])
        )
    }

    @MainActor
    func testExcludingOneBookKeepsTheProviderSeriesAndSelectBestUsesTheFallback() {
        let wrongBook = storefrontSuggestion(
            provider: .bookLiveJP,
            language: "ja",
            volumeNumber: 1,
            width: 1_800,
            height: 2_560
        )
        var wantedBook = storefrontSuggestion(
            provider: .bookLiveJP,
            language: "ja",
            volumeNumber: 1,
            width: 1_400,
            height: 1_990
        )
        wantedBook.providerItemID = "wanted-volume-1"
        wantedBook.imageURL = "https://example.com/wanted-volume-1.jpg"
        let store = SableMangaBakaCoverStudioStore()
        store.storefrontSuggestions = [wrongBook, wantedBook]

        store.setStorefrontSuggestionExcluded(
            wrongBook,
            isExcluded: true
        )
        store.selectBestStorefrontSuggestions(
            from: store.storefrontSuggestions
        )

        XCTAssertTrue(store.storefrontSuggestionIsExcluded(wrongBook))
        XCTAssertFalse(store.storefrontSuggestionIsActionable(wrongBook))
        XCTAssertEqual(
            store.selectedStorefrontSuggestionIDs,
            Set([wantedBook.id])
        )
        XCTAssertTrue(store.rejectedStorefrontReviewGroupIDs.isEmpty)
    }

    @MainActor
    func testCorrectingOneBookNumberPreservesItsLocalState() {
        let original = storefrontSuggestion(
            provider: .yes24,
            language: "ko",
            volumeNumber: 5,
            width: 1_000,
            height: 1_500
        )
        let store = SableMangaBakaCoverStudioStore()
        store.storefrontSuggestions = [original]
        store.selectedStorefrontSuggestionIDs = [original.id]
        store.excludedStorefrontSuggestionIDs = [original.id]
        store.storefrontContentRatingOverrides[original.id] = "suggestive"

        store.updateStorefrontSuggestionVolume(
            original,
            volumeNumber: 1
        )

        let corrected = try? XCTUnwrap(store.storefrontSuggestions.first)
        XCTAssertEqual(corrected?.volumeNumber, 1)
        XCTAssertFalse(store.selectedStorefrontSuggestionIDs.contains(original.id))
        XCTAssertTrue(
            corrected.map {
                store.excludedStorefrontSuggestionIDs.contains($0.id)
            } == true
        )
        XCTAssertEqual(
            corrected.flatMap {
                store.storefrontContentRatingOverrides[$0.id]
            },
            "suggestive"
        )
    }

    @MainActor
    func testManualFormatChoiceKeepsMultipleVersionsInOneVolumeSlot() {
        var print = storefrontSuggestion(
            provider: .amazonJP,
            language: "ja",
            width: 1_600,
            height: 2_400,
            publicationType: "physical"
        )
        print.providerItemID = "408870701X"
        print.imageURL = "https://example.com/print-1.jpg"
        var kindle = storefrontSuggestion(
            provider: .amazonJP,
            language: "ja",
            width: 2_000,
            height: 3_000,
            publicationType: "digital"
        )
        kindle.providerItemID = "B074CGZDXX"
        kindle.imageURL = "https://example.com/kindle-1.jpg"

        let store = SableMangaBakaCoverStudioStore()
        store.selectedSeries = SableMangaBakaSeriesSummary(
            id: 725,
            title: "ONE-PUNCH MAN",
            nativeTitle: "ワンパンマン",
            romanizedTitle: nil,
            type: "manga"
        )
        store.draftImages = [
            cover(
                url: "https://example.com/old-volume-1.jpg",
                index: 1,
                isDefault: true
            )
        ]
        store.storefrontSuggestions = [kindle, print]

        store.setStorefrontSuggestion(kindle.id, isSelected: true)
        store.setStorefrontSuggestion(print.id, isSelected: true)

        XCTAssertEqual(
            store.selectedStorefrontSuggestionIDs,
            Set([kindle.id, print.id])
        )
        XCTAssertEqual(store.stageSelectedStorefrontCovers(), 2)
        XCTAssertEqual(store.draftImages.count, 2)
        XCTAssertEqual(
            Set(store.draftImages.map(\.url)),
            Set([kindle.imageURL, print.imageURL])
        )
        XCTAssertFalse(
            store.draftImages.contains {
                $0.url == "https://example.com/old-volume-1.jpg"
            }
        )
        XCTAssertTrue(store.draftImages.allSatisfy { $0.index == "1" })
        XCTAssertTrue(store.draftImages.allSatisfy { $0.type == "volume" })
        XCTAssertTrue(store.draftImages.allSatisfy { $0.note == nil })
    }

    @MainActor
    func testMultipleVersionsInOneSlotKeepTheirOwnCoverNotes() {
        var regular = storefrontSuggestion(
            provider: .bookLiveJP,
            language: "ja",
            publicationType: "digital"
        )
        regular.imageURL = "https://example.com/regular-volume-1.jpg"
        var special = storefrontSuggestion(
            provider: .bookWalkerJP,
            language: "ja",
            publicationType: "digital"
        )
        special.imageURL = "https://example.com/special-volume-1.jpg"

        let store = SableMangaBakaCoverStudioStore()
        store.selectedSeries = SableMangaBakaSeriesSummary(
            id: 725,
            title: "Example Series",
            nativeTitle: nil,
            romanizedTitle: nil,
            type: "manga"
        )
        store.storefrontSuggestions = [regular, special]
        store.setStorefrontSuggestion(regular.id, isSelected: true)
        store.setStorefrontSuggestion(special.id, isSelected: true)
        store.setStorefrontCoverNote(
            "Regular edition",
            for: regular
        )
        store.setStorefrontCoverNote(
            "Special edition",
            for: special
        )

        XCTAssertEqual(store.stageSelectedStorefrontCovers(), 2)
        XCTAssertEqual(store.draftImages.count, 2)
        XCTAssertEqual(
            Dictionary(
                uniqueKeysWithValues: store.draftImages.map {
                    ($0.url, $0.note)
                }
            )[regular.imageURL]!,
            "Regular edition"
        )
        XCTAssertEqual(
            Dictionary(
                uniqueKeysWithValues: store.draftImages.map {
                    ($0.url, $0.note)
                }
            )[special.imageURL]!,
            "Special edition"
        )
        XCTAssertTrue(store.draftImages.allSatisfy { $0.index == "1" })
    }

    @MainActor
    func testCoverNoteCanBeUpdatedWithoutReplacingTheImage() {
        let suggestion = storefrontSuggestion(
            provider: .bookLiveJP,
            language: "ja"
        )
        let store = SableMangaBakaCoverStudioStore()
        store.selectedSeries = SableMangaBakaSeriesSummary(
            id: 725,
            title: "Example Series",
            nativeTitle: nil,
            romanizedTitle: nil,
            type: "manga"
        )
        store.storefrontSuggestions = [suggestion]
        store.draftImages = [
            cover(
                url: suggestion.imageURL,
                index: 1,
                isDefault: true
            )
        ]
        store.setStorefrontSuggestion(suggestion.id, isSelected: true)
        store.setStorefrontCoverNote(
            "Alternate cover",
            for: suggestion
        )

        XCTAssertEqual(store.stageSelectedStorefrontCovers(), 1)
        XCTAssertEqual(store.draftImages.first?.note, "Alternate cover")
    }

    @MainActor
    func testManualChapterChoiceKeepsMultipleArtVersionsForOneChapter() {
        var bookLive = storefrontSuggestion(
            provider: .bookLiveJP,
            language: "ja",
            volumeNumber: 1,
            coverType: "chapter",
            width: 1_350,
            height: 1_920
        )
        bookLive.imageURL = "https://example.com/chapter-1-booklive.jpg"
        var amazon = storefrontSuggestion(
            provider: .amazonJP,
            language: "ja",
            volumeNumber: 1,
            coverType: "chapter",
            width: 1_600,
            height: 2_400
        )
        amazon.imageURL = "https://example.com/chapter-1-amazon.jpg"

        let store = SableMangaBakaCoverStudioStore()
        store.selectedSeries = SableMangaBakaSeriesSummary(
            id: 523_141,
            title: "Repeated Vice",
            nativeTitle: nil,
            romanizedTitle: nil,
            type: "manga"
        )
        store.storefrontSuggestions = [bookLive, amazon]

        store.setStorefrontSuggestion(bookLive.id, isSelected: true)
        store.setStorefrontSuggestion(amazon.id, isSelected: true)

        XCTAssertEqual(
            store.selectedStorefrontSuggestionIDs,
            Set([bookLive.id, amazon.id])
        )
        XCTAssertEqual(store.stageSelectedStorefrontCovers(), 2)
        XCTAssertEqual(store.draftImages.count, 2)
        XCTAssertEqual(
            Set(store.draftImages.map(\.url)),
            Set([bookLive.imageURL, amazon.imageURL])
        )
        XCTAssertTrue(
            store.draftImages.allSatisfy {
                $0.type == "chapter"
                    && abs($0.indexNumeric - 1) < 0.001
            }
        )
    }

    @MainActor
    func testSuccessfulUploadMappingUsesOnlySelectedSupportedStoreSeries() {
        let selectedBookLive = storefrontSuggestion(
            provider: .bookLiveJP,
            language: "ja",
            volumeNumber: 1
        )
        var anotherBookLive = storefrontSuggestion(
            provider: .bookLiveJP,
            language: "ja",
            volumeNumber: 2
        )
        anotherBookLive.providerSeriesID = "second-series"
        let unselectedAmazon = storefrontSuggestion(
            provider: .amazon,
            language: "en",
            volumeNumber: 1
        )
        let unsupported = storefrontSuggestion(
            provider: .yes24,
            language: "ko",
            volumeNumber: 1
        )

        let groups = SableMangaBakaCoverStudioStore
            .confirmedStorefrontGroups(
                from: [
                    selectedBookLive,
                    anotherBookLive,
                    unselectedAmazon,
                    unsupported
                ],
                selectedIDs: [
                    selectedBookLive.id,
                    anotherBookLive.id,
                    unsupported.id
                ]
            )

        XCTAssertEqual(
            groups,
            [
                SableRolerConfirmedStorefrontGroup(
                    language: "ja",
                    provider: .bookLiveJP,
                    coverType: "volume",
                    providerSeriesIDs: ["series", "second-series"]
                )
            ]
        )

        XCTAssertEqual(
            SableMangaBakaCoverStudioStore
                .confirmedRolerSeriesReferences(
                    mangaBakaSeriesID: 104_661,
                    groups: groups
                ),
            [
                SableRolerSeriesReference(
                    providerId: "bl",
                    id: "second-series"
                ),
                SableRolerSeriesReference(
                    providerId: "bl",
                    id: "series"
                ),
                SableRolerSeriesReference(
                    providerId: "mb",
                    id: "104661"
                )
            ]
        )
    }

    @MainActor
    func testRolerGroupsDoNotMergePrintAndDigitalSeriesAcceptance() {
        var print = storefrontSuggestion(
            provider: .amazonJP,
            language: "ja",
            publicationType: "physical"
        )
        print.providerSeriesID = "paperback-series"
        var digital = storefrontSuggestion(
            provider: .amazonJP,
            language: "ja",
            publicationType: "digital"
        )
        digital.providerSeriesID = "kindle-series"

        let groups = SableMangaBakaCoverStudioStore
            .confirmedStorefrontGroups(
                from: [print, digital],
                selectedIDs: [print.id]
            )

        XCTAssertEqual(
            groups,
            [
                SableRolerConfirmedStorefrontGroup(
                    language: "ja",
                    provider: .amazonJP,
                    coverType: "volume",
                    publicationType: "physical",
                    providerSeriesIDs: ["paperback-series"]
                )
            ]
        )
    }

    @MainActor
    func testRolerApplyIncludesAcceptedAndTrustedLanesButSkipsUnreviewedAndRejected() {
        let trustedBookLive = storefrontSuggestion(
            provider: .bookLiveJP,
            language: "ja"
        )
        let acceptedAmazon = storefrontSuggestion(
            provider: .amazonUK,
            language: "en",
            requiresRelationshipReview: true,
            automaticMatchConfidence: 0.50
        )
        let awaitingAmazon = storefrontSuggestion(
            provider: .amazonFrance,
            language: "fr",
            requiresRelationshipReview: true,
            automaticMatchConfidence: 0.50
        )
        let rejectedAmazon = storefrontSuggestion(
            provider: .amazonGermany,
            language: "de"
        )
        let store = SableMangaBakaCoverStudioStore()
        store.storefrontSuggestions = [
            trustedBookLive,
            acceptedAmazon,
            awaitingAmazon,
            rejectedAmazon
        ]
        store.approvedStorefrontReviewGroupIDs = [
            store.storefrontReviewGroupID(for: acceptedAmazon)
        ]
        store.rejectedStorefrontReviewGroupIDs = [
            store.storefrontReviewGroupID(for: rejectedAmazon)
        ]

        let confirmed =
            store.confirmedStorefrontSuggestionIDsForRoler()

        XCTAssertTrue(confirmed.contains(trustedBookLive.id))
        XCTAssertTrue(confirmed.contains(acceptedAmazon.id))
        XCTAssertFalse(confirmed.contains(awaitingAmazon.id))
        XCTAssertFalse(confirmed.contains(rejectedAmazon.id))
    }

    @MainActor
    func testAcceptingPrintAndDigitalGroupsSeparatelyCanApproveBoth() {
        let paperback = storefrontSuggestion(
            provider: .amazonJP,
            language: "ja",
            requiresRelationshipReview: true,
            automaticMatchConfidence: 0.50,
            publicationType: "physical"
        )
        let digital = storefrontSuggestion(
            provider: .amazonJP,
            language: "ja",
            volumeNumber: 2,
            requiresRelationshipReview: true,
            automaticMatchConfidence: 0.50,
            publicationType: "digital"
        )
        let store = SableMangaBakaCoverStudioStore()
        store.storefrontSuggestions = [paperback, digital]

        store.setStorefrontRelationshipReviewApproved(
            language: "ja",
            provider: .amazonJP,
            publicationType: "physical",
            isApproved: true
        )

        XCTAssertTrue(
            store.storefrontRelationshipReviewIsApproved(for: paperback)
        )
        XCTAssertFalse(
            store.storefrontRelationshipReviewIsApproved(for: digital)
        )

        store.setStorefrontRelationshipReviewApproved(
            language: "ja",
            provider: .amazonJP,
            publicationType: "digital",
            isApproved: true
        )

        XCTAssertTrue(
            store.storefrontRelationshipReviewIsApproved(for: paperback)
        )
        XCTAssertTrue(
            store.storefrontRelationshipReviewIsApproved(for: digital)
        )
    }

    @MainActor
    func testRolerApplyIncludesUnselectedNumberCorrectionUnlessLaneWasRejected() {
        let original = storefrontSuggestion(
            provider: .bookLiveJP,
            language: "ja",
            volumeNumber: 5
        )
        let store = SableMangaBakaCoverStudioStore()
        store.storefrontSuggestions = [original]

        store.updateStorefrontSuggestionVolume(
            original,
            volumeNumber: 1
        )

        let corrected = try? XCTUnwrap(store.storefrontSuggestions.first)
        XCTAssertEqual(
            store.confirmedRolerBookCorrections().values.first?.volumeNumber,
            1
        )

        if let corrected {
            store.setStorefrontRelationshipReviewRejected(
                language: corrected.language,
                provider: corrected.provider,
                isRejected: true
            )
        }

        XCTAssertTrue(store.confirmedRolerBookCorrections().isEmpty)
    }

    @MainActor
    func testAutomaticSelectionKeepsOneBestTrustedCoverPerVolume() {
        let smallerVolumeOne = storefrontSuggestion(
            provider: .bookLiveJP,
            language: "ja",
            volumeNumber: 1,
            width: 900,
            height: 1_280
        )
        let betterVolumeOne = storefrontSuggestion(
            provider: .bookWalkerJP,
            language: "ja",
            volumeNumber: 1,
            width: 1_800,
            height: 2_560
        )
        let onlyVolumeTwo = storefrontSuggestion(
            provider: .amazonJP,
            language: "ja",
            volumeNumber: 2,
            width: 600,
            height: 900
        )

        let selected = SableMangaBakaCoverStudioStore
            .automaticallySelectedStorefrontSuggestions(
                from: [smallerVolumeOne, onlyVolumeTwo, betterVolumeOne]
            )

        XCTAssertEqual(selected.count, 2)
        XCTAssertEqual(
            selected.first(where: { $0.volumeNumber == 1 })?.provider,
            .bookWalkerJP
        )
        XCTAssertEqual(
            selected.first(where: { $0.volumeNumber == 2 })?.provider,
            .amazonJP
        )
    }

    @MainActor
    func testAutomaticSelectionAllowsLowerResolutionCoverForEmptySlot() {
        let lowerResolution = storefrontSuggestion(
            provider: .amazonFrance,
            language: "fr",
            width: 400,
            height: 600
        )

        XCTAssertFalse(lowerResolution.reachesClinicMinimum)
        XCTAssertEqual(
            SableMangaBakaCoverStudioStore
                .automaticallySelectedStorefrontSuggestions(
                    from: [lowerResolution]
                ),
            [lowerResolution]
        )
    }

    @MainActor
    func testSelectBestFillsEmptySlotWithoutDowngradingExistingCover() {
        let store = SableMangaBakaCoverStudioStore()
        store.draftImages = [
            cover(
                url: "https://example.com/existing.jpg",
                index: 1,
                isDefault: true
            )
        ]
        store.mangaBakaVolumeCovers = [
            SableMangaBakaPublicCoverImage(
                id: 10,
                indexNumeric: 1,
                language: "ja",
                type: "volume",
                rawURL: "https://example.com/existing.jpg",
                width: 1_800,
                height: 2_560
            )
        ]
        let downgrade = storefrontSuggestion(
            provider: .bookLiveJP,
            language: "ja",
            volumeNumber: 1,
            width: 900,
            height: 1_280
        )
        let emptySlot = storefrontSuggestion(
            provider: .amazonJP,
            language: "ja",
            volumeNumber: 2,
            width: 400,
            height: 600
        )

        store.selectBestStorefrontSuggestions(
            from: [downgrade, emptySlot]
        )

        XCTAssertEqual(
            store.selectedStorefrontSuggestionIDs,
            Set([emptySlot.id])
        )
        XCTAssertFalse(store.storefrontSuggestionIsActionable(downgrade))
        XCTAssertTrue(store.storefrontSuggestionIsActionable(emptySlot))
    }

    @MainActor
    func testAutomaticSelectionKeepsVolumeAndChapterSlotsSeparate() {
        let volume = storefrontSuggestion(
            provider: .bookLiveJP,
            language: "ja",
            volumeNumber: 3,
            coverType: "volume",
            width: 1_800,
            height: 2_560
        )
        let chapter = storefrontSuggestion(
            provider: .bookWalkerJP,
            language: "ja",
            volumeNumber: 3,
            coverType: "chapter",
            width: 1_200,
            height: 1_800
        )

        let selected = SableMangaBakaCoverStudioStore
            .automaticallySelectedStorefrontSuggestions(
                from: [chapter, volume]
            )

        XCTAssertEqual(selected.count, 2)
        XCTAssertEqual(
            Set(selected.map(\.coverType)),
            Set(["volume", "chapter"])
        )
    }

    func testAudiobookCompanionDiscoveryOnlyRunsForNovelSeries() {
        let novel = SableMangaBakaSeriesSummary(
            id: 1,
            title: "Kuma Kuma Kuma Bear",
            nativeTitle: nil,
            romanizedTitle: nil,
            titles: nil,
            type: "novel",
            cover: nil,
            finalVolume: nil
        )
        let manga = SableMangaBakaSeriesSummary(
            id: 2,
            title: "Kuma Kuma Kuma Bear",
            nativeTitle: nil,
            romanizedTitle: nil,
            titles: nil,
            type: "manga",
            cover: nil,
            finalVolume: nil
        )

        XCTAssertTrue(
            SableMangaBakaStorefrontDiscovery
                .shouldDiscoverEnglishAudiobooks(
                    for: novel,
                    provider: .audibleUS
                )
        )
        XCTAssertFalse(
            SableMangaBakaStorefrontDiscovery
                .shouldDiscoverEnglishAudiobooks(
                    for: novel,
                    provider: .amazon
                )
        )
        XCTAssertTrue(
            SableMangaBakaStorefrontDiscovery
                .shouldDiscoverEnglishAudiobooks(
                    for: novel,
                    provider: .bookWalkerGlobal
                )
        )
        XCTAssertTrue(
            SableMangaBakaStorefrontDiscovery
                .shouldDiscoverEnglishAudiobooks(
                    for: novel,
                    provider: .appleBooksUS
                )
        )
        XCTAssertFalse(
            SableMangaBakaStorefrontDiscovery
                .shouldDiscoverEnglishAudiobooks(
                    for: manga,
                    provider: .audibleUS
                )
        )
        XCTAssertFalse(
            SableMangaBakaStorefrontDiscovery
                .shouldDiscoverEnglishAudiobooks(
                    for: manga,
                    provider: .appleBooksUS
                )
        )
    }

    func testAudibleCatalogParsesSeriesSequenceAndSquareArtwork() throws {
        let data = Data(
            """
            {
              "products": [
                {
                  "asin": "B0F7SC7WVW",
                  "title": "Kuma Kuma Kuma Bear (Light Novel) Vol. 1",
                  "language": "english",
                  "product_images": {
                    "500": "https://example.com/500.jpg",
                    "1024": "https://example.com/1024.jpg",
                    "1600": "https://example.com/1600.jpg",
                    "2400": "https://example.com/2400.jpg",
                    "3000": "https://example.com/3000.jpg"
                  },
                  "series": [
                    {
                      "asin": "B0F7Z67917",
                      "sequence": "1",
                      "title": "Kuma Kuma Kuma Bear Light Novel",
                      "url": "https://www.audible.com/series/B0F7Z67917"
                    }
                  ]
                }
              ]
            }
            """.utf8
        )

        let products = try SableAudibleCatalogClient.products(from: data)

        XCTAssertEqual(products.count, 1)
        XCTAssertEqual(
            products.first?.preferredCoverURL,
            "https://example.com/3000.jpg"
        )
        XCTAssertEqual(
            products.first?.fallbackCoverURLs,
            [
                "https://example.com/2400.jpg",
                "https://example.com/1600.jpg",
                "https://example.com/1024.jpg",
                "https://example.com/500.jpg"
            ]
        )
        XCTAssertEqual(products.first?.series?.first?.sequence, "1")
        XCTAssertEqual(products.first?.series?.first?.asin, "B0F7Z67917")
    }

    func testAppleBooksCatalogUsesLargeJPEGArtworkOnly() throws {
        let data = Data(
            """
            {
              "resultCount": 1,
              "results": [
                {
                  "wrapperType": "audiobook",
                  "collectionId": 1697529670,
                  "artistName": "Fujino Omori",
                  "collectionName": "Is It Wrong to Try to Pick Up Girls in a Dungeon?, Vol. 1",
                  "collectionViewUrl": "https://books.apple.com/us/audiobook/id1697529670",
                  "artworkUrl100": "https://is1-ssl.mzstatic.com/image/thumb/Music126/v4/example/9781975388171.jpg/100x100bb.jpg"
                }
              ]
            }
            """.utf8
        )

        let products = try SableAppleBooksCatalogClient.products(from: data)
        let product = try XCTUnwrap(products.first)

        XCTAssertEqual(product.collectionID, 1_697_529_670)
        XCTAssertEqual(
            product.preferredCoverURL,
            "https://is1-ssl.mzstatic.com/image/thumb/Music126/v4/example/9781975388171.jpg/10000x0w-999.jpg"
        )
        XCTAssertEqual(
            product.fallbackCoverURLs,
            [
                "https://is1-ssl.mzstatic.com/image/thumb/Music126/v4/example/9781975388171.jpg/100x100bb.jpg"
            ]
        )
        XCTAssertFalse(
            ([product.preferredCoverURL] + product.fallbackCoverURLs)
                .compactMap { $0 }
                .contains { $0.lowercased().hasSuffix(".png") }
        )
    }

    func testAudibleProductURLParsesAsExactBookReference() {
        let reference = SableMangaBakaStorefrontDiscovery
            .storeSeriesReference(
                from:
                    "https://www.audible.com/pd/7th-Time-Loop-Vol-3-Audiobook/B0GVZKWGPY?ref=test"
            )

        XCTAssertEqual(reference?.provider, .audibleUS)
        XCTAssertEqual(reference?.itemID, "B0GVZKWGPY")
        XCTAssertEqual(reference?.itemType, "book")
        XCTAssertEqual(reference?.languageOverride, "en")
        XCTAssertEqual(reference?.publisherProvenMediaType, "audiobook")
    }

    func testAppleBooksAudiobookURLsParseAsExactReferences() {
        let canonical = SableMangaBakaStorefrontDiscovery
            .storeSeriesReference(
                from:
                    "https://books.apple.com/us/audiobook/is-it-wrong-to-try-to-pick-up-girls/id1697529670"
            )
        let legacyISBN = SableMangaBakaStorefrontDiscovery
            .storeSeriesReference(
                from:
                    "https://books.apple.com/us/audiobook/Is It Wrong to Try to Pick Up Girls in a Dungeon?, Vol. 1/9781975388171"
            )

        XCTAssertEqual(canonical?.provider, .appleBooksUS)
        XCTAssertEqual(canonical?.itemID, "1697529670")
        XCTAssertEqual(canonical?.publisherProvenMediaType, "audiobook")
        XCTAssertEqual(legacyISBN?.provider, .appleBooksUS)
        XCTAssertEqual(legacyISBN?.itemID, "9781975388171")
        XCTAssertEqual(legacyISBN?.publisherProvenMediaType, "audiobook")
    }

    func testAudibleSelectionKeepsTitleMatchedProductWithoutSeriesMetadata() {
        let title =
            "7th Time Loop: The Villainess Enjoys a Carefree Life Married to Her Worst Enemy!"
        let series = SableMangaBakaSeriesSummary(
            id: 84_345,
            title: title,
            nativeTitle: nil,
            romanizedTitle: nil,
            type: "novel"
        )
        let audibleSeries = SableAudibleCatalogClient.SeriesEntry(
            asin: "B0GMKW2X8C",
            sequence: "1",
            title: title,
            url: nil
        )
        let products = [
            SableAudibleCatalogClient.Product(
                asin: "B0H46N5CYN",
                title: "\(title), Vol. 4",
                language: "english",
                productImages: ["3000": "https://example.com/4.jpg"],
                series: [
                    SableAudibleCatalogClient.SeriesEntry(
                        asin: audibleSeries.asin,
                        sequence: "4",
                        title: audibleSeries.title,
                        url: nil
                    )
                ]
            ),
            SableAudibleCatalogClient.Product(
                asin: "B0GVZKWGPY",
                title: "\(title), Vol. 3",
                language: "english",
                productImages: ["3000": "https://example.com/3.jpg"],
                series: []
            ),
            SableAudibleCatalogClient.Product(
                asin: "B0G59S5G5W",
                title: "\(title), Vol. 1",
                language: "english",
                productImages: ["3000": "https://example.com/1.jpg"],
                series: [audibleSeries]
            )
        ]

        let selection = SableMangaBakaStorefrontDiscovery
            .audibleSeriesSelection(
                from: products,
                requestedTitles: [title],
                series: series,
                query: title
            )

        XCTAssertEqual(selection?.providerSeriesID, "B0GMKW2X8C")
        XCTAssertEqual(
            selection?.books.map(\.id),
            ["B0G59S5G5W", "B0GVZKWGPY", "B0H46N5CYN"]
        )
        XCTAssertEqual(selection?.books.map(\.volumeNumber), [1, 3, 4])
        XCTAssertEqual(selection?.books.map(\.bookType), [
            "audiobook",
            "audiobook",
            "audiobook"
        ])
    }

    func testExactAudibleLinkKeepsUserChosenProductWhenTitleMatchingFails() {
        let series = SableMangaBakaSeriesSummary(
            id: 84_345,
            title: "7th Time Loop",
            nativeTitle: nil,
            romanizedTitle: nil,
            type: "novel"
        )
        let product = SableAudibleCatalogClient.Product(
            asin: "B0GVZKWGPY",
            title: "Store title with an unexpected subtitle",
            language: nil,
            productImages: [
                "3000": "https://example.com/exact-audiobook.jpg"
            ],
            series: []
        )

        let selection = SableMangaBakaStorefrontDiscovery
            .audibleExactSelection(
                from: [product],
                series: series,
                fallbackProviderSeriesID: product.asin
            )

        XCTAssertEqual(selection?.providerSeriesID, product.asin)
        XCTAssertEqual(selection?.books.map(\.id), [product.asin])
        XCTAssertEqual(selection?.books.map(\.volumeNumber), [1])
        XCTAssertEqual(selection?.books.map(\.bookType), ["audiobook"])
    }

    @MainActor
    func testAutomaticSelectionKeepsBookAndAudiobookSlotsSeparate() {
        let book = storefrontSuggestion(
            provider: .amazon,
            language: "en",
            volumeNumber: 4,
            coverType: "volume",
            width: 1_700,
            height: 2_560
        )
        let audiobook = storefrontSuggestion(
            provider: .amazonUK,
            language: "en",
            volumeNumber: 4,
            coverType: "audiobook",
            width: 1_600,
            height: 1_600
        )

        let selected = SableMangaBakaCoverStudioStore
            .automaticallySelectedStorefrontSuggestions(
                from: [audiobook, book]
            )

        XCTAssertEqual(selected.count, 2)
        XCTAssertEqual(
            Set(selected.map(\.coverType)),
            Set(["volume", "audiobook"])
        )
    }

    func testAudiobookQualityUsesSquareArtworkThresholds() {
        let archiveOnly = storefrontSuggestion(
            provider: .amazon,
            language: "en",
            coverType: "audiobook",
            width: 600,
            height: 600
        )
        let highQuality = storefrontSuggestion(
            provider: .amazon,
            language: "en",
            coverType: "audiobook",
            width: 1_200,
            height: 1_200
        )

        XCTAssertTrue(archiveOnly.reachesArchiveMinimum)
        XCTAssertFalse(archiveOnly.reachesClinicMinimum)
        XCTAssertTrue(highQuality.reachesArchiveMinimum)
        XCTAssertTrue(highQuality.reachesClinicMinimum)
        XCTAssertEqual(highQuality.numberedKindLabel, "Audiobook 1")
    }

    func testImageIssueClassificationSeparatesBookAndAudiobookShapes() {
        let squareVolume = storefrontSuggestion(
            provider: .amazon,
            language: "en",
            coverType: "volume",
            width: 2_400,
            height: 2_400
        )
        let squareAudiobook = storefrontSuggestion(
            provider: .audibleUS,
            language: "en",
            coverType: "audiobook",
            width: 2_400,
            height: 2_400
        )
        let archiveBook = storefrontSuggestion(
            provider: .bookLiveJP,
            language: "ja",
            coverType: "volume",
            width: 703,
            height: 1_000
        )

        XCTAssertTrue(squareVolume.imageNeedsReplacement)
        XCTAssertTrue(
            squareVolume.imageIssueLabel?
                .contains("not a book cover") == true
        )
        XCTAssertFalse(squareAudiobook.imageNeedsReplacement)
        XCTAssertFalse(archiveBook.imageNeedsReplacement)
        XCTAssertTrue(archiveBook.reachesArchiveMinimum)
        XCTAssertFalse(archiveBook.reachesClinicMinimum)
    }

    @MainActor
    func testAutomaticAndManualSelectionSkipVolumeArtworkWithWrongShape() {
        let wrongShape = storefrontSuggestion(
            provider: .amazon,
            language: "en",
            volumeNumber: 1,
            coverType: "volume",
            width: 2_400,
            height: 2_400
        )
        let usableCover = storefrontSuggestion(
            provider: .bookWalkerGlobal,
            language: "en",
            volumeNumber: 2,
            coverType: "volume",
            width: 1_600,
            height: 2_560
        )
        let store = SableMangaBakaCoverStudioStore()

        let automatic = SableMangaBakaCoverStudioStore
            .automaticallySelectedStorefrontSuggestions(
                from: [wrongShape, usableCover]
            )

        XCTAssertEqual(automatic, [usableCover])
        XCTAssertFalse(
            store.storefrontSuggestionCanBeManuallySelected(wrongShape)
        )
        XCTAssertTrue(
            store.storefrontSuggestionCanBeManuallySelected(usableCover)
        )
    }

    func testExactStoreLinkKeepsSquareBBCArtworkForReview() {
        XCTAssertFalse(
            SableMangaBakaStorefrontDiscovery
                .storefrontImageShapeIsAccepted(
                    width: 1_500,
                    height: 1_500,
                    acceptsSquareArtwork: false,
                    acceptsAnyArtworkShape: false
                )
        )
        XCTAssertTrue(
            SableMangaBakaStorefrontDiscovery
                .storefrontImageShapeIsAccepted(
                    width: 1_500,
                    height: 1_500,
                    acceptsSquareArtwork: false,
                    acceptsAnyArtworkShape: true
                )
        )
        XCTAssertFalse(
            SableMangaBakaStorefrontDiscovery
                .storefrontImageShapeIsAccepted(
                    width: 1,
                    height: 1,
                    acceptsSquareArtwork: false,
                    acceptsAnyArtworkShape: true
                )
        )
    }

    func testManualImageChoicesOmitConfirmedTrackingPixels() {
        let trackingURL = "https://images.example/tracking.jpg"
        let coverURL = "https://images.example/cover.jpg"
        let unverifiedFallbackURL = "https://images.example/fallback.jpg"

        let choices = SableMangaBakaStorefrontDiscovery
            .storefrontImageChoices(
                from: [
                    trackingURL,
                    coverURL,
                    unverifiedFallbackURL
                ],
                validatedDimensions: [
                    trackingURL: (width: 1, height: 1),
                    coverURL: (width: 1_500, height: 2_400)
                ]
            )

        XCTAssertEqual(
            choices.map(\.url),
            [coverURL, unverifiedFallbackURL]
        )
    }

    @MainActor
    func testProviderAcceptanceStaysSeparateForBooksAndAudiobooks() {
        let book = storefrontSuggestion(
            provider: .amazon,
            language: "en",
            coverType: "volume",
            width: 1_700,
            height: 2_560,
            requiresRelationshipReview: true
        )
        let audiobook = storefrontSuggestion(
            provider: .amazon,
            language: "en",
            coverType: "audiobook",
            width: 1_600,
            height: 1_600,
            requiresRelationshipReview: true
        )
        let store = SableMangaBakaCoverStudioStore()
        store.storefrontSuggestions = [book, audiobook]

        store.setStorefrontRelationshipReviewApproved(
            language: "en",
            provider: .amazon,
            coverType: "volume",
            isApproved: true
        )

        XCTAssertFalse(store.storefrontSuggestionNeedsReview(book))
        XCTAssertTrue(store.storefrontSuggestionNeedsReview(audiobook))

        store.selectBestStorefrontSuggestions(
            from: store.storefrontSuggestions
        )
        XCTAssertEqual(
            store.selectedStorefrontSuggestionIDs,
            Set([book.id])
        )
    }

    @MainActor
    func testNumberMismatchStaysVisibleButIsNotAutomaticallySelected() {
        let mismatch = storefrontSuggestion(
            provider: .bookWalkerJP,
            language: "ja",
            volumeNumber: 6,
            width: 1_800,
            height: 2_560,
            detectedVolumeNumbers: [5]
        )

        XCTAssertEqual(
            mismatch.numberingReviewReason,
            "Cover text shows volume 5, not volume 6."
        )
        XCTAssertTrue(mismatch.requiresManualReview)
        XCTAssertTrue(
            SableMangaBakaCoverStudioStore
                .automaticallySelectedStorefrontSuggestions(
                    from: [mismatch]
                )
                .isEmpty
        )
    }

    func testChapterAndVolumeTextChecksStaySeparate() {
        let chapter = storefrontSuggestion(
            provider: .bookLiveJP,
            language: "ja",
            volumeNumber: 12,
            coverType: "chapter",
            detectedChapterNumbers: [12]
        )
        let mislabeledVolume = storefrontSuggestion(
            provider: .bookLiveJP,
            language: "ja",
            volumeNumber: 12,
            coverType: "volume",
            detectedChapterNumbers: [12]
        )

        XCTAssertNil(chapter.numberingReviewReason)
        XCTAssertEqual(
            mislabeledVolume.numberingReviewReason,
            "Cover text looks like chapter 12, not a volume cover."
        )
        XCTAssertEqual(
            SableMangaBakaStorefrontDiscovery.explicitChapterNumbers(
                in: "Chapter 12 第12話 12화"
            ),
            Set([12])
        )
    }

    func testContentRatingInferenceUsesMangaBakaCoverRules() {
        XCTAssertEqual(
            SableMangaBakaStorefrontDiscovery
                .inferredCoverContentRating(
                    from: ["lingerie", "illustration"]
                ),
            "suggestive"
        )
        XCTAssertEqual(
            SableMangaBakaStorefrontDiscovery
                .inferredCoverContentRating(
                    from: ["nudity", "illustration"]
                ),
            "erotica"
        )
        XCTAssertEqual(
            SableMangaBakaStorefrontDiscovery
                .inferredCoverContentRating(
                    from: ["sexual activity"]
                ),
            "pornographic"
        )
    }

    @MainActor
    func testProviderReplacementPreservesStricterExistingRatingUnlessOverridden() {
        let store = SableMangaBakaCoverStudioStore()
        store.selectedSeries = SableMangaBakaSeriesSummary(
            id: 130_883,
            title: "I Could Never Be a Succubus!",
            nativeTitle: nil,
            romanizedTitle: nil,
            titles: nil,
            type: "novel",
            cover: nil,
            finalVolume: nil
        )
        store.draftImages = [
            cover(
                url: "https://example.com/existing.jpg",
                index: 1,
                isDefault: true
            )
        ]
        store.draftImages[0].contentRating = "erotica"
        store.mangaBakaVolumeCovers = [
            SableMangaBakaPublicCoverImage(
                id: 1,
                indexNumeric: 1,
                language: "ja",
                type: "volume",
                rawURL: "https://example.com/existing.jpg",
                width: 800,
                height: 1_200,
                contentRating: "erotica"
            )
        ]
        let upgrade = storefrontSuggestion(
            provider: .bookLiveJP,
            language: "ja",
            width: 1_800,
            height: 2_560,
            contentRating: "safe"
        )
        store.storefrontSuggestions = [upgrade]
        store.setStorefrontSuggestion(upgrade.id, isSelected: true)

        XCTAssertEqual(store.stageSelectedStorefrontCovers(), 1)
        XCTAssertEqual(store.draftImages[0].contentRating, "erotica")

        store.draftImages[0].url = "https://example.com/existing.jpg"
        store.storefrontSuggestions = [upgrade]
        store.setStorefrontContentRating("suggestive", for: upgrade)
        store.setStorefrontSuggestion(upgrade.id, isSelected: true)
        XCTAssertEqual(store.stageSelectedStorefrontCovers(), 1)
        XCTAssertEqual(store.draftImages[0].contentRating, "suggestive")
    }

    func testStorefrontTypeEvidenceExplainsMangaNovelMismatch() {
        let suggestion = storefrontSuggestion(
            provider: .amazon,
            language: "en",
            expectedMediaType: "manga",
            detectedMediaType: "novel"
        )

        XCTAssertEqual(
            suggestion.mediaTypeEvidenceLabel,
            "Expected Manga · Store says Light novel"
        )
        XCTAssertTrue(suggestion.mediaTypeNeedsAttention)
    }

    func testStorefrontTypeEvidenceExplainsUnprovenManualOverride() {
        let suggestion = storefrontSuggestion(
            provider: .bookWalkerGlobal,
            language: "en",
            expectedMediaType: "manga",
            detectedMediaType: nil,
            usesManualMediaTypeOverride: true
        )

        XCTAssertEqual(
            suggestion.mediaTypeEvidenceLabel,
            "Expected Manga · Manual type override"
        )
        XCTAssertFalse(suggestion.mediaTypeNeedsAttention)
    }

    func testStorefrontTypeEvidenceConfirmsCompatibleStoreType() {
        let suggestion = storefrontSuggestion(
            provider: .bookLiveJP,
            language: "ja",
            expectedMediaType: "novel",
            detectedMediaType: "light_novel"
        )

        XCTAssertEqual(
            suggestion.mediaTypeEvidenceLabel,
            "Expected Light novel · Store says Light novel"
        )
        XCTAssertFalse(suggestion.mediaTypeNeedsAttention)
    }

    func testStorefrontTypeEvidenceUsesOfficialPublisherProof() {
        let suggestion = storefrontSuggestion(
            provider: .amazon,
            language: "en",
            expectedMediaType: "novel",
            detectedMediaType: "novel",
            usesPublisherMediaTypeProof: true
        )

        XCTAssertEqual(
            suggestion.mediaTypeEvidenceLabel,
            "Expected Light novel · Publisher says Light novel"
        )
        XCTAssertFalse(suggestion.mediaTypeNeedsAttention)
    }

    func testStorefrontDiscoveryPrefersMeasuredQualityBeforeProviderOrder() {
        let lowerResolutionBookLive = storefrontSuggestion(
            provider: .bookLiveJP,
            language: "ja",
            width: 960,
            height: 1_280
        )
        let fullResolutionBookWalker = storefrontSuggestion(
            provider: .bookWalkerJP,
            language: "ja",
            width: 1_837,
            height: 2_700
        )

        let preferred = SableMangaBakaStorefrontDiscovery.preferredSuggestions(
            from: [lowerResolutionBookLive, fullResolutionBookWalker]
        )

        XCTAssertEqual(preferred.count, 1)
        XCTAssertEqual(preferred.first?.provider, .bookWalkerJP)
        XCTAssertTrue(preferred.first?.reachesClinicMinimum == true)
    }

    func testCompositeSlotsMergeProvidersAndChooseBestMeasuredCover() throws {
        let bookLive = storefrontSuggestion(
            provider: .bookLiveJP,
            language: "ja",
            volumeNumber: 3,
            width: 1_440,
            height: 2_048
        )
        let bookWalker = storefrontSuggestion(
            provider: .bookWalkerJP,
            language: "ja",
            volumeNumber: 3,
            width: 1_800,
            height: 2_700
        )
        let amazon = storefrontSuggestion(
            provider: .amazonJP,
            language: "ja",
            volumeNumber: 3,
            width: 1_600,
            height: 2_560
        )

        let slot = try XCTUnwrap(
            SableMangaBakaStorefrontDiscovery.compositeSlots(
                from: [bookLive, bookWalker, amazon]
            ).first
        )

        XCTAssertEqual(slot.volumeNumber, 3)
        XCTAssertEqual(slot.suggestions.count, 3)
        XCTAssertEqual(slot.alternativeCount, 2)
        XCTAssertEqual(slot.winner.provider, .bookWalkerJP)
    }

    func testCompositeSlotPrefersBookLiveWhenMeasuredQualityTies() throws {
        let bookLive = storefrontSuggestion(
            provider: .bookLiveJP,
            language: "ja",
            width: 1_440,
            height: 2_048
        )
        let bookWalker = storefrontSuggestion(
            provider: .bookWalkerJP,
            language: "ja",
            width: 1_440,
            height: 2_048
        )
        let amazon = storefrontSuggestion(
            provider: .amazonJP,
            language: "ja",
            width: 1_440,
            height: 2_048
        )

        let slot = try XCTUnwrap(
            SableMangaBakaStorefrontDiscovery.compositeSlots(
                from: [amazon, bookWalker, bookLive]
            ).first
        )

        XCTAssertEqual(slot.winner.provider, .bookLiveJP)
    }

    func testCompositeSlotRespectsManuallyChosenProviderAlternative() throws {
        let bookLive = storefrontSuggestion(
            provider: .bookLiveJP,
            language: "ja",
            width: 1_440,
            height: 2_048
        )
        let bookWalker = storefrontSuggestion(
            provider: .bookWalkerJP,
            language: "ja",
            width: 1_800,
            height: 2_700
        )

        let slot = try XCTUnwrap(
            SableMangaBakaStorefrontDiscovery.compositeSlots(
                from: [bookLive, bookWalker],
                selectedSuggestionIDs: [bookLive.id]
            ).first
        )

        XCTAssertEqual(slot.winner.id, bookLive.id)
        XCTAssertEqual(slot.winner.provider, .bookLiveJP)
    }

    @MainActor
    func testMovingCompositeWinnerReplacesThePrimarySelection() throws {
        let bookLive = storefrontSuggestion(
            provider: .bookLiveJP,
            language: "ja",
            width: 1_440,
            height: 2_048
        )
        let bookWalker = storefrontSuggestion(
            provider: .bookWalkerJP,
            language: "ja",
            width: 1_800,
            height: 2_700
        )
        let store = SableMangaBakaCoverStudioStore()
        store.storefrontSuggestions = [bookLive, bookWalker]
        store.selectedStorefrontSuggestionIDs = [bookWalker.id]
        let slot = try XCTUnwrap(store.storefrontCompositeSlots.first)

        store.moveStorefrontCompositeWinner(slot, offset: 1)

        XCTAssertEqual(store.selectedStorefrontSuggestionIDs.count, 1)
        XCTAssertNotEqual(
            store.selectedStorefrontSuggestionIDs.first,
            bookWalker.id
        )
    }

    func testCompositeSlotsKeepBookChapterAndAudiobookLanesSeparate() {
        let book = storefrontSuggestion(
            provider: .bookWalkerGlobal,
            language: "en",
            volumeNumber: 2,
            coverType: "volume"
        )
        let chapter = storefrontSuggestion(
            provider: .bookLiveJP,
            language: "en",
            volumeNumber: 2,
            coverType: "chapter"
        )
        let audiobook = storefrontSuggestion(
            provider: .audibleUS,
            language: "en",
            volumeNumber: 2,
            coverType: "audiobook"
        )

        let slots = SableMangaBakaStorefrontDiscovery.compositeSlots(
            from: [book, chapter, audiobook]
        )

        XCTAssertEqual(slots.count, 3)
        XCTAssertEqual(Set(slots.map(\.coverType)), ["volume", "chapter", "audiobook"])
    }

    func testMangaBakaSubmissionKeepsOnlyEarliestChapterForRepeatedArtwork() {
        let repeatedArtwork = [
            UInt8(20), 40, 60, 255,
            80, 100, 120, 255
        ]
        let differentArtwork = [
            UInt8(220), 200, 180, 255,
            160, 140, 120, 255
        ]
        let firstChapter = storefrontSuggestion(
            provider: .bookLiveJP,
            language: "ja",
            volumeNumber: 1,
            coverType: "chapter",
            visualSignature: repeatedArtwork
        )
        let repeatedChapter = storefrontSuggestion(
            provider: .bookLiveJP,
            language: "ja",
            volumeNumber: 15,
            coverType: "chapter",
            visualSignature: repeatedArtwork
        )
        let changedArtworkChapter = storefrontSuggestion(
            provider: .bookLiveJP,
            language: "ja",
            volumeNumber: 16,
            coverType: "chapter",
            visualSignature: differentArtwork
        )

        let prepared =
            SableMangaBakaStorefrontDiscovery.mangaBakaSubmissionSuggestions(
                from: [
                    repeatedChapter,
                    changedArtworkChapter,
                    firstChapter
                ]
            )

        XCTAssertEqual(
            prepared.map(\.volumeNumber).sorted(),
            [1, 16]
        )
    }

    func testMangaBakaChapterArtworkRuleDoesNotCollapseVolumes() {
        let repeatedArtwork = [
            UInt8(20), 40, 60, 255,
            80, 100, 120, 255
        ]
        let firstVolume = storefrontSuggestion(
            provider: .bookLiveJP,
            language: "ja",
            volumeNumber: 1,
            visualSignature: repeatedArtwork
        )
        let secondVolume = storefrontSuggestion(
            provider: .bookLiveJP,
            language: "ja",
            volumeNumber: 2,
            visualSignature: repeatedArtwork
        )

        let prepared =
            SableMangaBakaStorefrontDiscovery.mangaBakaSubmissionSuggestions(
                from: [firstVolume, secondVolume]
            )

        XCTAssertEqual(prepared.count, 2)
    }

    func testMangaBakaSubmissionRepresentativeRedirectsRepeatedChapter() {
        let repeatedArtwork = [
            UInt8(20), 40, 60, 255,
            80, 100, 120, 255
        ]
        let firstChapter = storefrontSuggestion(
            provider: .bookLiveJP,
            language: "ja",
            volumeNumber: 1,
            coverType: "chapter",
            visualSignature: repeatedArtwork
        )
        let repeatedChapter = storefrontSuggestion(
            provider: .bookLiveJP,
            language: "ja",
            volumeNumber: 15,
            coverType: "chapter",
            visualSignature: repeatedArtwork
        )

        let representative =
            SableMangaBakaStorefrontDiscovery
                .mangaBakaSubmissionRepresentative(
                    for: repeatedChapter,
                    among: [repeatedChapter, firstChapter]
                )

        XCTAssertEqual(representative?.id, firstChapter.id)
    }

    @MainActor
    func testSelectingRepeatedChapterSelectsVisibleMangaBakaRepresentative() {
        let repeatedArtwork = [
            UInt8(20), 40, 60, 255,
            80, 100, 120, 255
        ]
        let firstChapter = storefrontSuggestion(
            provider: .bookLiveJP,
            language: "ja",
            volumeNumber: 1,
            coverType: "chapter",
            visualSignature: repeatedArtwork
        )
        let repeatedChapter = storefrontSuggestion(
            provider: .bookLiveJP,
            language: "ja",
            volumeNumber: 15,
            coverType: "chapter",
            visualSignature: repeatedArtwork
        )
        let store = SableMangaBakaCoverStudioStore()
        store.storefrontSuggestions = [repeatedChapter, firstChapter]

        store.setStorefrontSuggestion(
            repeatedChapter.id,
            isSelected: true
        )

        XCTAssertEqual(
            store.selectedStorefrontSuggestionIDs,
            Set([firstChapter.id])
        )
        XCTAssertEqual(
            store.selectedMangaBakaStorefrontSuggestions.map(\.id),
            [firstChapter.id]
        )
    }

    @MainActor
    func testAcceptingOneProviderSeriesDoesNotApproveItsSiblingCandidate() {
        var novel = storefrontSuggestion(
            provider: .bookWalkerGlobal,
            language: "en",
            requiresRelationshipReview: true
        )
        novel.providerSeriesID = "novel-series"
        var manga = storefrontSuggestion(
            provider: .bookWalkerGlobal,
            language: "en",
            requiresRelationshipReview: true
        )
        manga.providerSeriesID = "manga-series"

        let store = SableMangaBakaCoverStudioStore()
        store.selectedSeries = SableMangaBakaSeriesSummary(
            id: 1,
            title: "Example",
            nativeTitle: nil,
            romanizedTitle: nil,
            type: "novel"
        )
        store.storefrontSuggestions = [novel, manga]

        store.setStorefrontRelationshipReviewApproved(
            language: novel.language,
            provider: novel.provider,
            coverType: novel.coverType,
            publicationType: novel.normalizedPublicationType,
            providerSeriesID: novel.providerSeriesID,
            isApproved: true
        )

        XCTAssertTrue(
            store.storefrontRelationshipReviewIsApproved(for: novel)
        )
        XCTAssertFalse(
            store.storefrontRelationshipReviewIsApproved(for: manga)
        )
    }

    func testRecommendedProvidersUseTheFocusedLanguageBundles() {
        XCTAssertEqual(
            SableMangaBakaStorefrontDiscovery.recommendedProviders(
                for: ["ja"],
                mediaType: "manga"
            ),
            [.bookLiveJP, .bookWalkerJP, .amazonJP, .shueisha]
        )
        XCTAssertEqual(
            SableMangaBakaStorefrontDiscovery.recommendedProviders(
                for: ["en"],
                mediaType: "novel"
            ),
            [
                .bookWalkerGlobal,
                .amazon,
                .amazonUK,
                .audibleUS,
                .appleBooksUS
            ]
        )
        XCTAssertEqual(
            SableMangaBakaStorefrontDiscovery.recommendedProviders(
                for: ["ko"],
                mediaType: "manga"
            ),
            [.yes24, .kyobo, .aladin, .ridibooks]
        )
        XCTAssertFalse(
            SableMangaBakaStorefrontDiscovery.recommendedProviders(
                for: nil,
                mediaType: "novel"
            ).contains(.amazonNetherlands)
        )
    }

    func testFastJapaneseScanKeepsTheOfficialShueishaLane() {
        XCTAssertTrue(
            SableMangaBakaStorefrontDiscovery
                .includesShueishaPublisherSource(
                    includesSupplementalSources: false,
                    selectedProviders: [.bookLiveJP, .shueisha]
                )
        )
        XCTAssertFalse(
            SableMangaBakaStorefrontDiscovery
                .includesShueishaPublisherSource(
                    includesSupplementalSources: false,
                    selectedProviders: [.bookLiveJP]
                )
        )
        XCTAssertTrue(
            SableMangaBakaStorefrontDiscovery
                .includesShueishaPublisherSource(
                    includesSupplementalSources: true,
                    selectedProviders: nil
                )
        )
    }

    func testBookLivePreviewSourceNormalizesToFullResolutionXImage() {
        let preview = cover(
            url: "https://res.booklive.jp/1091682/001/thumbnail/2L.jpg",
            index: 1,
            isDefault: true
        )

        XCTAssertEqual(
            preview.preferredBookLiveSourceURL,
            "https://res.booklive.jp/1091682/001/thumbnail/X.jpg"
        )
    }

    func testStorefrontLanguageScopesOnlyUseMatchingProviders() {
        XCTAssertEqual(
            SableMangaBakaStorefrontDiscovery.providers(for: ["ja"]),
            [.bookLiveJP, .bookWalkerJP, .amazonJP, .shueisha]
        )
        XCTAssertEqual(
            SableMangaBakaStorefrontDiscovery.providers(for: ["en"]),
            [
                .bookWalkerGlobal,
                .amazon,
                .amazonUK,
                .audibleUS,
                .appleBooksUS
            ]
        )
        XCTAssertEqual(
            SableMangaBakaStorefrontDiscovery.providers(for: ["ko"]),
            [.yes24, .kyobo, .aladin, .ridibooks]
        )
        XCTAssertEqual(
            SableMangaBakaStorefrontDiscovery.providers(
                for: SableMangaBakaStorefrontScanScope
                    .japaneseEnglishKorean
                    .languageCodes
            ),
            [
                .bookLiveJP,
                .bookWalkerGlobal,
                .bookWalkerJP,
                .amazonJP,
                .amazon,
                .amazonUK,
                .shueisha,
                .audibleUS,
                .appleBooksUS,
                .yes24,
                .kyobo,
                .aladin,
                .ridibooks
            ]
        )
        XCTAssertEqual(
            SableMangaBakaStorefrontDiscovery.providers(for: ["fr"]),
            [.amazonFrance]
        )
        XCTAssertEqual(
            SableMangaBakaStorefrontDiscovery.providers(for: ["nl"]),
            [.amazonNetherlands]
        )
        XCTAssertEqual(
            SableMangaBakaStorefrontDiscovery.providers(for: nil).count,
            SableLibraryBigBookCoversProvider.allCases
                .filter(\.usesBigBookCoversAPI)
                .count
        )
    }

    func testStorefrontExecutionLanesBoundAmazonRegionsSeparately() {
        let providers = SableMangaBakaStorefrontDiscovery.providers(for: nil)
        let lanes = SableMangaBakaStorefrontDiscovery.providerExecutionLanes(
            for: providers
        )

        XCTAssertFalse(lanes.regular.isEmpty)
        XCTAssertFalse(lanes.amazon.isEmpty)
        XCTAssertTrue(lanes.regular.allSatisfy { !$0.isAmazon })
        XCTAssertTrue(lanes.amazon.allSatisfy(\.isAmazon))
        XCTAssertEqual(lanes.regular.count + lanes.amazon.count, providers.count)
        XCTAssertEqual(
            SableMangaBakaStorefrontDiscovery.amazonProviderConcurrencyLimit,
            4
        )
        XCTAssertEqual(
            SableLibraryBigBookCoversClient
                .maximumConcurrentConnectionsPerHost,
            4
        )
    }

    func testFocusedMultilanguageScanCanRunAllAmazonRegionsTogether() {
        let providers = SableMangaBakaStorefrontDiscovery.providers(
            for: ["ja", "en", "ko"]
        )
        let lanes = SableMangaBakaStorefrontDiscovery.providerExecutionLanes(
            for: providers
        )

        XCTAssertEqual(lanes.amazon, [.amazonJP, .amazon, .amazonUK])
        XCTAssertLessThanOrEqual(
            lanes.amazon.count,
            SableMangaBakaStorefrontDiscovery.amazonProviderConcurrencyLimit
        )
    }

    func testSelectableStorefrontProvidersExcludeLowValueAutomaticSources() {
        XCTAssertEqual(
            SableMangaBakaStorefrontDiscovery.selectableProviders(for: ["ja"]),
            [
                .bookLiveJP,
                .bookWalkerJP,
                .amazonJP,
                .shueisha
            ]
        )
        XCTAssertEqual(
            SableMangaBakaStorefrontDiscovery.selectableProviders(for: ["en"]),
            [
                .bookWalkerGlobal,
                .amazon,
                .amazonUK,
                .audibleUS,
                .appleBooksUS,
                .barnesNobleUS
            ]
        )
        XCTAssertEqual(
            SableMangaBakaStorefrontDiscovery.selectableProviders(for: ["nl"]),
            [.amazonNetherlands]
        )
        XCTAssertFalse(
            SableMangaBakaStorefrontDiscovery.providerIsEnabled(
                .rakutenKobo,
                selectedProviders: [.rakutenKobo]
            )
        )
    }

    @MainActor
    func testAcceptedStorefrontSeriesPersistsButDifferentSeriesNeedsReview()
        throws {
        let suiteName = "SableStorefrontApprovalTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let approvalStore = SableStorefrontRelationshipApprovalStore(
            defaults: defaults
        )
        let series = SableMangaBakaSeriesSummary(
            id: 84_345,
            title: "7th Time Loop",
            nativeTitle: nil,
            romanizedTitle: nil,
            titles: nil,
            type: "novel",
            cover: nil,
            finalVolume: nil
        )
        var accepted = storefrontSuggestion(
            provider: .bookWalkerGlobal,
            language: "en",
            requiresRelationshipReview: true
        )
        accepted.providerSeriesID = "seven-loop-novel"

        let firstStore = SableMangaBakaCoverStudioStore(
            storefrontRelationshipApprovalStore: approvalStore
        )
        firstStore.selectedSeries = series
        firstStore.storefrontSuggestions = [accepted]
        firstStore.setStorefrontRelationshipReviewApproved(
            language: "en",
            provider: .bookWalkerGlobal,
            isApproved: true
        )

        let nextScanStore = SableMangaBakaCoverStudioStore(
            storefrontRelationshipApprovalStore: approvalStore
        )
        nextScanStore.selectedSeries = series
        nextScanStore.storefrontSuggestions = [accepted]
        nextScanStore.restorePersistedStorefrontRelationshipApprovals()
        XCTAssertTrue(
            nextScanStore.storefrontRelationshipReviewIsApproved(
                for: accepted
            )
        )

        var differentStoreSeries = accepted
        differentStoreSeries.providerSeriesID = "seven-loop-manga"
        let changedStore = SableMangaBakaCoverStudioStore(
            storefrontRelationshipApprovalStore: approvalStore
        )
        changedStore.selectedSeries = series
        changedStore.storefrontSuggestions = [differentStoreSeries]
        changedStore.restorePersistedStorefrontRelationshipApprovals()
        XCTAssertFalse(
            changedStore.storefrontRelationshipReviewIsApproved(
                for: differentStoreSeries
            )
        )
    }

    @MainActor
    func testUnmatchingAcceptedStorefrontSeriesClearsRememberedApproval()
        throws {
        let suiteName = "SableStorefrontUnmatchTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let approvalStore = SableStorefrontRelationshipApprovalStore(
            defaults: defaults
        )
        let series = SableMangaBakaSeriesSummary(
            id: 84_345,
            title: "7th Time Loop",
            nativeTitle: nil,
            romanizedTitle: nil,
            titles: nil,
            type: "novel",
            cover: nil,
            finalVolume: nil
        )
        var accepted = storefrontSuggestion(
            provider: .bookWalkerGlobal,
            language: "en",
            requiresRelationshipReview: true
        )
        accepted.providerSeriesID = "wrong-series"

        let store = SableMangaBakaCoverStudioStore(
            storefrontRelationshipApprovalStore: approvalStore
        )
        store.selectedSeries = series
        store.storefrontSuggestions = [accepted]
        store.setStorefrontRelationshipReviewApproved(
            language: "en",
            provider: .bookWalkerGlobal,
            providerSeriesID: accepted.providerSeriesID,
            isApproved: true
        )
        store.setStorefrontRelationshipReviewApproved(
            language: "en",
            provider: .bookWalkerGlobal,
            providerSeriesID: accepted.providerSeriesID,
            isApproved: false
        )

        XCTAssertFalse(
            store.storefrontRelationshipReviewIsApproved(for: accepted)
        )
        XCTAssertTrue(store.selectedStorefrontSuggestionIDs.isEmpty)

        let nextScanStore = SableMangaBakaCoverStudioStore(
            storefrontRelationshipApprovalStore: approvalStore
        )
        nextScanStore.selectedSeries = series
        nextScanStore.storefrontSuggestions = [accepted]
        nextScanStore.restorePersistedStorefrontRelationshipApprovals()

        XCTAssertFalse(
            nextScanStore.storefrontRelationshipReviewIsApproved(
                for: accepted
            )
        )
    }

    @MainActor
    func testRejectingAcceptedStorefrontSeriesClearsRememberedApproval()
        throws {
        let suiteName = "SableStorefrontRejectTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let approvalStore = SableStorefrontRelationshipApprovalStore(
            defaults: defaults
        )
        let series = SableMangaBakaSeriesSummary(
            id: 84_345,
            title: "7th Time Loop",
            nativeTitle: nil,
            romanizedTitle: nil,
            titles: nil,
            type: "novel",
            cover: nil,
            finalVolume: nil
        )
        var accepted = storefrontSuggestion(
            provider: .amazonJP,
            language: "ja",
            requiresRelationshipReview: true
        )
        accepted.providerSeriesID = "wrong-series"

        let store = SableMangaBakaCoverStudioStore(
            storefrontRelationshipApprovalStore: approvalStore
        )
        store.selectedSeries = series
        store.storefrontSuggestions = [accepted]
        store.setStorefrontRelationshipReviewApproved(
            language: "ja",
            provider: .amazonJP,
            providerSeriesID: accepted.providerSeriesID,
            isApproved: true
        )
        store.setStorefrontRelationshipReviewRejected(
            language: "ja",
            provider: .amazonJP,
            providerSeriesID: accepted.providerSeriesID,
            isRejected: true
        )

        XCTAssertTrue(
            store.storefrontRelationshipReviewIsRejected(for: accepted)
        )
        XCTAssertFalse(
            store.storefrontRelationshipReviewIsApproved(for: accepted)
        )
        XCTAssertTrue(store.selectedStorefrontSuggestionIDs.isEmpty)

        let nextScanStore = SableMangaBakaCoverStudioStore(
            storefrontRelationshipApprovalStore: approvalStore
        )
        nextScanStore.selectedSeries = series
        nextScanStore.storefrontSuggestions = [accepted]
        nextScanStore.restorePersistedStorefrontRelationshipApprovals()

        XCTAssertFalse(
            nextScanStore.storefrontRelationshipReviewIsApproved(
                for: accepted
            )
        )
    }

    func testYES24SearchParserReadsNovelCoverAndVolume() {
        let html = """
        <input id="ordOpt_14680895"
               value="{&quot;goods_name&quot;:&quot;Re : 제로부터 시작하는 이세계 생활 3&quot;,&quot;goodsSortNm&quot;:&quot;라이트노벨&quot;}">
        """

        let products = SableMangaBakaStorefrontDiscovery.yes24Products(
            from: html,
            query: "Re : 제로부터 시작하는 이세계 생활"
        )

        XCTAssertEqual(products.count, 1)
        XCTAssertEqual(products.first?.id, "14680895")
        XCTAssertEqual(products.first?.volumeNumber, 3)
        XCTAssertEqual(products.first?.mediaType, "novel")
        XCTAssertEqual(
            products.first?.imageURL,
            "https://image.yes24.com/goods/14680895/XL"
        )
    }

    func testYES24ExactProductParserReadsSasakiAndMiyanoNovel() {
        let html = """
        <meta name="title" content="소설 사사키와 미야노 2학년">
        <meta property="og:image"
              content="https://image.yes24.com/goods/180386493/xl">
        <script type="application/ld+json">
        {
          "genre": ["만화/라이트노벨", "BL(보이즈러브)"],
          "isPartOf": {
            "name": "소설 사사키와 미야노",
            "url": "https://www.yes24.com/product/category/series/001?SeriesNumber=374485"
          }
        }
        </script>
        """

        let product = SableMangaBakaStorefrontDiscovery.yes24Product(
            from: html,
            goodsID: "180386493",
            storeURL: "https://www.yes24.com/product/goods/180386493"
        )

        XCTAssertEqual(product?.id, "180386493")
        XCTAssertEqual(product?.title, "소설 사사키와 미야노 2학년")
        XCTAssertEqual(product?.volumeNumber, 2)
        XCTAssertEqual(product?.mediaType, "novel")
        XCTAssertEqual(product?.seriesID, "374485")
        XCTAssertEqual(
            product?.imageURL,
            "https://image.yes24.com/goods/180386493/xl"
        )
    }

    func testYES24ExactStandaloneProductDefaultsToVolumeOne() {
        let html = """
        <meta name="title"
              content="던전에서 만남을 추구하면 안 되는 걸까 외전 파밀리아 크로니클 episode 프레이야">
        <meta property="og:image"
              content="https://image.yes24.com/goods/92134965/xl">
        <script>
        {"genre": ["만화/라이트노벨", "라이트노벨", "판타지"]}
        </script>
        """

        let product = SableMangaBakaStorefrontDiscovery.yes24Product(
            from: html,
            goodsID: "92134965",
            storeURL: "https://www.yes24.com/product/goods/92134965"
        )

        XCTAssertEqual(product?.volumeNumber, 1)
        XCTAssertEqual(product?.mediaType, "novel")
    }

    func testRakutenBooksParserReadsPrintAndDigitalVolumes() {
        let html = """
        <div class="rbcomp__item-list__item">
          <div class="rbcomp__item-list__item__image">
            <a href="https://books.rakuten.co.jp/rk/digital-1/?l-id=test">
              <img src="https://example.com/digital.jpg?downsize=130:*">
            </a>
          </div>
          <span class="rbcomp__category e-book">電子</span>
          <span class="rbcomp__item-list__item__title">ワンパンマン 1 （ジャンプコミックスDIGITAL）[電子書籍版]</span>
          <p class="rbcomp__item-list__item__subtext">シリーズ名：<a href="https://books.rakuten.co.jp/search?series=ワンパンマン">ワンパンマン</a></p>
          <p>漫画（コミック）</p>
        </div>
        <div class="rbcomp__item-list__item">
          <div class="rbcomp__item-list__item__image">
            <a href="https://books.rakuten.co.jp/rb/12345/?l-id=test">
              <img src="https://example.com/print.jpg?downsize=130:*">
            </a>
          </div>
          <span class="rbcomp__category book">本</span>
          <span class="rbcomp__item-list__item__title">ワンパンマン 1 （ジャンプコミックス）</span>
          <p class="rbcomp__item-list__item__subtext">シリーズ名：<a href="https://books.rakuten.co.jp/series/BW0016N7V0/">ワンパンマン</a></p>
          <p>コミック</p>
        </div>
        <div class="rbcomp__item-list__item">
          <div class="rbcomp__item-list__item__image">
            <a href="https://books.rakuten.co.jp/rb/blu-ray-1/?l-id=test">
              <img src="https://example.com/blu-ray.jpg?downsize=130:*">
            </a>
          </div>
          <span class="rbcomp__category dvd">DVD</span>
          <span class="rbcomp__item-list__item__title">ワンパンマン SEASON 2 第1巻(特装限定版)【Blu-ray】</span>
          <p class="rbcomp__item-list__item__subtext">シリーズ名：<a href="https://books.rakuten.co.jp/search?series=ワンパンマン">ワンパンマン</a></p>
          <p>関連する漫画（コミック）も販売中</p>
        </div>
        """

        let products = SableMangaBakaStorefrontDiscovery
            .rakutenBooksProducts(from: html, query: "ワンパンマン")

        XCTAssertEqual(products.count, 2)
        XCTAssertEqual(products.map(\.volumeNumber), [1, 1])
        XCTAssertEqual(products.map(\.mediaType), ["manga", "manga"])
        XCTAssertEqual(
            Set(products.map(\.publicationType)),
            Set(["digital", "physical"])
        )
        XCTAssertEqual(
            products.first?.imageURL,
            "https://example.com/digital.jpg"
        )
        XCTAssertEqual(
            products.last?.storeURL,
            "https://books.rakuten.co.jp/rb/12345/"
        )
    }

    func testBarnesNobleSearchParserReadsProductURLs() {
        let html = #"""
        <script>
        window.__reactRouterContext.streamController.enqueue(
          "P1:[\"https:\/\/www.barnesandnoble.com\/w\/One-Punch-Man-Vol-2-ONE\/1122136149?ean=9781421577418\", \"\/w\/9781421585277\/9781421585277\"]"
        )
        </script>
        """#

        let urls = SableMangaBakaStorefrontDiscovery
            .barnesNobleProductURLs(from: html)

        XCTAssertEqual(
            urls,
            [
                "https://www.barnesandnoble.com/w/One-Punch-Man-Vol-2-ONE/1122136149?ean=9781421577418",
                "https://www.barnesandnoble.com/w/9781421585277/9781421585277"
            ]
        )
    }

    func testBarnesNobleSearchParserPrioritizesResultISBNLinksOverPageNoise() {
        let html = #"""
        <script>
        window.__reactRouterContext.streamController.enqueue(
          "P1:[\"https:\/\/www.barnesandnoble.com\/w\/the-school-for-thieves-peter-burns\/1146889548?ean=9781665982283\", \"https:\/\/www.barnesandnoble.com\/w\/seek-immediate-shelter-vincent-yu\/1148026418?ean=9781250410122\", \"\/w\/9781974766529\/9781974766529\", \"\/w\/9781421585642\/9781421585642\"]"
        )
        </script>
        """#

        let urls = SableMangaBakaStorefrontDiscovery
            .barnesNobleProductURLs(from: html, query: "one punch man")

        XCTAssertEqual(
            Array(urls.prefix(2)),
            [
                "https://www.barnesandnoble.com/w/9781974766529/9781974766529",
                "https://www.barnesandnoble.com/w/9781421585642/9781421585642"
            ]
        )
        XCTAssertTrue(
            urls.dropFirst(2).contains(
                "https://www.barnesandnoble.com/w/the-school-for-thieves-peter-burns/1146889548?ean=9781665982283"
            )
        )
    }

    func testBarnesNobleProductGridParserReadsLooseVolumes() {
        let html = #"""
        <html>
          <head>
            <meta property="og:title" content="One-Punch Man Manga">
          </head>
          <body>
            <script>
            window.__reactRouterContext.streamController.enqueue(
              "P1:[\"https:\/\/www.barnesandnoble.com\/w\/the-school-for-thieves-peter-burns\/1146889548?ean=9781665982283\", \"https:\/\/cdn.shopify.com\/s\/files\/1\/0674\/5433\/7265\/files\/9781665982283_p0.jpg?v=1765183313\", \"One-Punch Man, Vol. 34\", \"\/w\/9781974766529\/9781974766529\", \"https:\/\/cdn.shopify.com\/s\/files\/1\/0674\/5433\/7265\/files\/9781974766529_p0.jpg?v=1779072144\", \"One-Punch Man, Vol. 35\", \"\/w\/9781974768493\/9781974768493\", \"One-Punch Man, Vol. 4\", \"\/w\/9781421569208\/9781421569208\", \"https:\/\/cdn.shopify.com\/s\/files\/1\/0674\/5433\/7265\/files\/9781421569208_p0.jpg?v=1765323591\"]"
            )
            </script>
          </body>
        </html>
        """#

        let products = SableMangaBakaStorefrontDiscovery.barnesNobleProducts(
            from: html,
            pageURL:
                "https://www.barnesandnoble.com/series/one-punch-man-series",
            query: "One-Punch Man"
        )

        XCTAssertEqual(products.map(\.volumeNumber), [4, 34])
        XCTAssertEqual(products.map(\.id), ["9781421569208", "9781974766529"])
        XCTAssertEqual(products.map(\.mediaType), ["manga", "manga"])
        XCTAssertEqual(
            products.map(\.publicationType),
            ["physical", "physical"]
        )
        XCTAssertEqual(
            products.first?.imageURL,
            "https://cdn.shopify.com/s/files/1/0674/5433/7265/files/9781421569208_p0.jpg?v=1765323591"
        )
    }

    func testBarnesNobleSearchGridKeepsPerProductMediaTypesSeparate() {
        let html = #"""
        <html>
          <head>
            <meta property="og:title" content="Search | Barnes &amp; Noble">
          </head>
          <body>
            <script>
            window.__reactRouterContext.streamController.enqueue(
              "P1:[\"7th Time Loop: The Villainess Enjoys a Carefree Life Married to Her Worst Enemy! (Light Novel) Vol. 1\", \"\/w\/9781638583936\/9781638583936\", \"https:\/\/cdn.shopify.com\/s\/files\/1\/0674\/5433\/7265\/files\/9781638583936_p0.jpg\", \"7th Time Loop: The Villainess Enjoys a Carefree Life Vol. 1 (Manga)\", \"\/w\/9781685793241\/9781685793241\", \"https:\/\/cdn.shopify.com\/s\/files\/1\/0674\/5433\/7265\/files\/9781685793241_p0.jpg\"]"
            )
            </script>
          </body>
        </html>
        """#

        let products = SableMangaBakaStorefrontDiscovery.barnesNobleProducts(
            from: html,
            pageURL:
                "https://www.barnesandnoble.com/search?q=7th%20time%20loop",
            query: "7th Time Loop"
        )

        XCTAssertEqual(products.count, 2)
        XCTAssertEqual(
            Dictionary(
                uniqueKeysWithValues: products.map {
                    ($0.id, $0.mediaType)
                }
            ),
            [
                "9781638583936": "novel",
                "9781685793241": "manga"
            ]
        )
    }

    func testBarnesNobleLightNovelTitleMatchesItsSeries() {
        XCTAssertTrue(
            SableLibraryCoverDownloadPlanner.providerTitle(
                "7th Time Loop: The Villainess Enjoys a Carefree Life Married to Her Worst Enemy! (Light Novel) Vol. 4",
                belongsTo:
                    "7th Time Loop: The Villainess Enjoys a Carefree Life Married to Her Worst Enemy!"
            )
        )
    }

    func testBarnesNobleProductPageParserReadsCoverVolumeAndFormat() {
        let html = #"""
        <html>
          <head>
            <meta property="og:title" content="One-Punch Man, Vol. 2">
            <meta property="og:image" content="https://cdn.shopify.com/s/files/1/0674/5433/7265/files/9781421577418_p0.jpg?v=1765331193">
          </head>
          <body>
            <button role="radio" aria-checked="true" type="button">
              Paperback
              <div>$11.99</div>
            </button>
            <a href="/b/books/comics-manga-graphic-novels/_/N-29Z8q8Zucc">
              Comics, Manga &amp; Graphic Novels
            </a>
          </body>
        </html>
        """#

        let product = SableMangaBakaStorefrontDiscovery.barnesNobleProduct(
            from: html,
            storeURL:
                "https://www.barnesandnoble.com/w/one-punch-man-vol-2-one/1122136149?ean=9781421577418",
            query: "One-Punch Man"
        )

        XCTAssertEqual(product?.id, "9781421577418")
        XCTAssertEqual(product?.title, "One-Punch Man, Vol. 2")
        XCTAssertEqual(product?.volumeNumber, 2)
        XCTAssertEqual(
            product?.imageURL,
            "https://cdn.shopify.com/s/files/1/0674/5433/7265/files/9781421577418_p0.jpg?v=1765331193"
        )
        XCTAssertEqual(
            product?.storeURL,
            "https://www.barnesandnoble.com/w/one-punch-man-vol-2-one/1122136149?ean=9781421577418"
        )
        XCTAssertEqual(product?.publicationType, "physical")
        XCTAssertEqual(product?.mediaType, "manga")
    }

    func testBarnesNobleProductPageParserRejectsVideoPages() {
        let html = #"""
        <html>
          <head>
            <meta property="og:title" content="One-Punch Man: Season 2 [Blu-ray]">
            <meta property="og:image" content="https://cdn.shopify.com/s/files/1/0674/5433/7265/files/0782009246695_p0.jpg">
          </head>
          <body>
            <button role="radio" aria-checked="true" type="button">
              Blu-ray
              <div>$69.99</div>
            </button>
          </body>
        </html>
        """#

        let product = SableMangaBakaStorefrontDiscovery.barnesNobleProduct(
            from: html,
            storeURL:
                "https://www.barnesandnoble.com/w/one-punch-man-season-2/1137065687?ean=0782009246695",
            query: "One-Punch Man"
        )

        XCTAssertNil(product)
    }

    func testKoboCDNURLRequestsTheUnconstrainedArtwork() {
        let source =
            "https://cdn.kobo.com/book-images/"
            + "014a0a77-326d-4ba1-9860-12ae3d6f0d03/"
            + "353/569/90/False/example-volume-1.jpg"

        let upgraded = SableMangaBakaStorefrontDiscovery
            .archivalStorefrontImageURL(from: source)

        XCTAssertEqual(
            upgraded,
            "https://cdn.kobo.com/book-images/"
                + "014a0a77-326d-4ba1-9860-12ae3d6f0d03/"
                + "example-volume-1.jpg"
        )
    }

    func testMaximumImageCandidatesUseLocalSourcesWithoutChangingBBCImages() {
        let bbcBookLive = "https://c.roler.dev/bl/965497-001/0"
        let bbcBookWalker = "https://c.roler.dev/bw/303953-1/0"
        let bbcAmazon = "https://c.roler.dev/amz/B09RN5QP4G/0"
        let amazon =
            "https://m.media-amazon.com/images/I/81example._SL500_.jpg"
        let apple =
            "https://is1-ssl.mzstatic.com/image/thumb/Music126/v4/example/9781975388171.jpg/100x100bb.jpg"

        XCTAssertFalse(
            SableMangaBakaStorefrontDiscovery
                .usesLocalMaximumImageResolution(for: bbcBookLive)
        )
        XCTAssertFalse(
            SableMangaBakaStorefrontDiscovery
                .usesLocalMaximumImageResolution(for: bbcBookWalker)
        )
        XCTAssertFalse(
            SableMangaBakaStorefrontDiscovery
                .usesLocalMaximumImageResolution(for: bbcAmazon)
        )
        XCTAssertTrue(
            SableMangaBakaStorefrontDiscovery
                .usesLocalMaximumImageResolution(for: amazon)
        )
        XCTAssertTrue(
            SableMangaBakaStorefrontDiscovery
                .usesLocalMaximumImageResolution(for: apple)
        )

        let appleCandidates = SableMangaBakaStorefrontDiscovery
            .maximumImageURLCandidates(from: apple)
        XCTAssertEqual(
            appleCandidates.first,
            "https://is1-ssl.mzstatic.com/image/thumb/Music126/v4/example/9781975388171.jpg/10000x0w-999.jpg"
        )
        XCTAssertEqual(appleCandidates.last, apple)
        XCTAssertFalse(
            appleCandidates.contains { $0.lowercased().hasSuffix(".png") }
        )

        let amazonCandidates = SableMangaBakaStorefrontDiscovery
            .maximumImageURLCandidates(from: amazon)
        XCTAssertEqual(
            amazonCandidates.first,
            "https://m.media-amazon.com/images/I/81example.jpg"
        )
        XCTAssertEqual(amazonCandidates.last, amazon)
    }

    func testMaximumImageCandidatesCoverLocalStorefrontRules() {
        let yes24 = SableMangaBakaStorefrontDiscovery
            .maximumImageURLCandidates(
                from: "https://image.yes24.com/goods/180386493/L"
            )
        let kyobo = SableMangaBakaStorefrontDiscovery
            .maximumImageURLCandidates(
                from:
                    "https://contents.kyobobook.co.kr/sih/fit-in/3000x0/pdt/9791172884338.jpg"
            )
        let ridi = SableMangaBakaStorefrontDiscovery
            .maximumImageURLCandidates(
                from: "https://img.ridicdn.net/cover/2066007610/xlarge"
            )
        let aladin = SableMangaBakaStorefrontDiscovery
            .maximumImageURLCandidates(
                from:
                    "https://image.aladin.co.kr/product/123/45/coversum/example.jpg?RS=384"
            )
        let shueisha = SableMangaBakaStorefrontDiscovery
            .maximumImageURLCandidates(
                from:
                    "https://assets.shueisha.online/image/upload/600/example.jpg"
            )

        XCTAssertTrue(yes24.contains("https://image.yes24.com/goods/180386493/XL"))
        XCTAssertTrue(kyobo.contains("https://contents.kyobobook.co.kr/pdt/9791172884338.jpg"))
        XCTAssertTrue(
            ridi.contains(
                "https://img.ridicdn.net/cover/2066007610/xxlarge?dpi=xxxhdpi&format=png"
            )
        )
        XCTAssertTrue(
            aladin.contains(
                "https://image.aladin.co.kr/product/123/45/cover500/example.jpg"
            )
        )
        XCTAssertTrue(
            shueisha.contains(
                "https://assets.shueisha.online/image/-/upload/0/example.jpg"
            )
        )
    }

    func testKyoboSearchParserBuildsFullResolutionCoverURL() {
        let html = """
        <input data-pid="S000220341645"
               data-bid="9791172884338"
               data-name="Re: 제로부터 시작하는 이세계 생활 42"
               data-code="KOR">
        """

        let products = SableMangaBakaStorefrontDiscovery.kyoboProducts(
            from: html,
            query: "Re: 제로부터 시작하는 이세계 생활"
        )

        XCTAssertEqual(products.count, 1)
        XCTAssertEqual(products.first?.id, "S000220341645")
        XCTAssertEqual(products.first?.volumeNumber, 42)
        XCTAssertEqual(
            products.first?.imageURL,
            "https://contents.kyobobook.co.kr/sih/fit-in/3000x0/pdt/9791172884338.jpg"
        )
    }

    func testKyoboSearchParserRejectsSiblingGuidebook() {
        let html = """
        <input data-pid="S000001"
               data-bid="9791172884338"
               data-name="Re:제로부터 시작하는 이세계 생활 Re:zeropedia 2"
               data-code="KOR">
        """

        let products = SableMangaBakaStorefrontDiscovery.kyoboProducts(
            from: html,
            query: "Re:제로부터 시작하는 이세계 생활"
        )

        XCTAssertTrue(products.isEmpty)
    }

    func testKyoboProductClassificationSeparatesNovelAndManga() {
        XCTAssertEqual(
            SableMangaBakaStorefrontDiscovery.kyoboMediaType(
                from: #""saleCmdtClstCode":"010508""#
            ),
            "novel"
        )
        XCTAssertEqual(
            SableMangaBakaStorefrontDiscovery.kyoboMediaType(
                from: #"saleCmdtClstCode\":\"4717\"#
            ),
            "manga"
        )
    }

    func testKyoboExactEbookParserReadsFullSizeStandaloneNovel() {
        let html = """
        <meta name="title" content="파밀리아 크로니클 에피소드(Episode): 프레이야
            | 오모리 후지노 | 소미미디어- 교보ebook">
        <meta property="og:image"
              content="https://contents.kyobobook.co.kr/sih/fit-in/380x590/pdt/9791165073121.jpg">
        <ol>
          <li class="depth_item active">
            <a>라이트노벨</a>
          </li>
        </ol>
        """

        let product = SableMangaBakaStorefrontDiscovery.kyoboProduct(
            from: html,
            productID: "E000002950013",
            storeURL:
                "https://ebook-product.kyobobook.co.kr/dig/epd/ebook/E000002950013"
        )

        XCTAssertEqual(
            product?.title,
            "파밀리아 크로니클 에피소드(Episode): 프레이야"
        )
        XCTAssertEqual(product?.volumeNumber, 1)
        XCTAssertEqual(product?.mediaType, "novel")
        XCTAssertEqual(
            product?.imageURL,
            "https://contents.kyobobook.co.kr/sih/fit-in/3000x0/pdt/9791165073121.jpg"
        )
    }

    func testKyoboExactPrintSearchParserReadsSuppliedMangaVolumes() {
        let html = """
        <input class="result_checkbox"
               data-pid="S000214458961"
               data-bid="9791138484398"
               data-name="파밀리아 크로니클 episode 프레이야 1"
               data-code="KOR">
        <input class="result_checkbox"
               data-pid="S000214965332"
               data-bid="9791138485081"
               data-name="파밀리아 크로니클 episode 프레이야 2"
               data-code="KOR">
        <input class="result_checkbox"
               data-pid="S000219545215"
               data-bid="9791138489812"
               data-name="파밀리아 크로니클 episode 프레이야 3"
               data-code="KOR">
        <script>
        [{"sale_CMDT_CLST_CODE3":"4717",
          "dq_ID":"S000214458961",
          "cmdt_NAME":"파밀리아 크로니클 episode 프레이야 1"},
         {"sale_CMDT_CLST_CODE3":"4717",
          "dq_ID":"S000214965332",
          "cmdt_NAME":"파밀리아 크로니클 episode 프레이야 2"},
         {"sale_CMDT_CLST_CODE3":"4718",
          "dq_ID":"S000219545215",
          "cmdt_NAME":"파밀리아 크로니클 episode 프레이야 3"}]
        </script>
        """

        let productIDs = [
            "S000214458961",
            "S000214965332",
            "S000219545215"
        ]
        let products = productIDs.compactMap { productID in
            SableMangaBakaStorefrontDiscovery.kyoboPrintProduct(
                fromSearchHTML: html,
                productID: productID,
                storeURL:
                    "https://product.kyobobook.co.kr/detail/\(productID)"
            )
        }

        XCTAssertEqual(products.count, 3)
        XCTAssertEqual(
            products.map(\.title),
            [
                "파밀리아 크로니클 episode 프레이야 1",
                "파밀리아 크로니클 episode 프레이야 2",
                "파밀리아 크로니클 episode 프레이야 3"
            ]
        )
        XCTAssertEqual(products.map(\.volumeNumber), [1, 2, 3])
        XCTAssertEqual(products.map(\.mediaType), ["manga", "manga", "manga"])
        XCTAssertEqual(
            products.map(\.imageURL),
            [
                "https://contents.kyobobook.co.kr/sih/fit-in/3000x0/pdt/9791138484398.jpg",
                "https://contents.kyobobook.co.kr/sih/fit-in/3000x0/pdt/9791138485081.jpg",
                "https://contents.kyobobook.co.kr/sih/fit-in/3000x0/pdt/9791138489812.jpg"
            ]
        )
        XCTAssertEqual(
            products.map(\.storeURL),
            productIDs.map {
                "https://product.kyobobook.co.kr/detail/\($0)"
            }
        )
    }

    func testKoreanStoreLabelsProveNovelMangaAndAudiobookTypes() {
        XCTAssertTrue(
            SableLibraryCoverDownloadPlanner.providerMediaTypeIsCompatible(
                "라이트노벨",
                isCompatibleWith: "novel"
            )
        )
        XCTAssertTrue(
            SableLibraryCoverDownloadPlanner.providerMediaTypeIsCompatible(
                "웹툰",
                isCompatibleWith: "manga"
            )
        )
        XCTAssertFalse(
            SableLibraryCoverDownloadPlanner.providerMediaTypeIsCompatible(
                "오디오북",
                isCompatibleWith: "novel"
            )
        )

        let manga = storefrontSuggestion(
            provider: .ridibooks,
            language: "ko",
            expectedMediaType: "manga",
            detectedMediaType: "만화"
        )
        XCTAssertEqual(
            manga.mediaTypeEvidenceLabel,
            "Expected Manga · Store says Manga"
        )
        XCTAssertFalse(manga.mediaTypeNeedsAttention)
    }

    func testKyoboMetadataCanProveTypeWhenClassificationCodeIsMissing() {
        XCTAssertEqual(
            SableMangaBakaStorefrontDiscovery.kyoboMediaType(
                from: #"<meta name="keywords" content="국내도서, 라이트노벨, 판타지">"#
            ),
            "novel"
        )
        XCTAssertEqual(
            SableMangaBakaStorefrontDiscovery.kyoboMediaType(
                from: #"<meta name="keywords" content="국내도서, 웹툰, 만화">"#
            ),
            "manga"
        )
    }

    func testLocalCoverQualityAuditOnlyFlagsStrictUpgradesForSameSlot() {
        let local = [
            SableMangaBakaLocalCoverImage(
                indexNumeric: 1,
                language: "jp",
                path: "_covers/jp/volume-1.jpg",
                width: 1_800,
                height: 2_600
            ),
            SableMangaBakaLocalCoverImage(
                indexNumeric: 2,
                language: "en",
                path: "_covers/en/volume-2.jpg",
                width: 600,
                height: 900
            )
        ]
        let mangaBaka = [
            SableMangaBakaPublicCoverImage(
                id: 1,
                indexNumeric: 1,
                language: "ja",
                type: "volume",
                rawURL: "https://example.com/ja-1.jpg",
                width: 1_000,
                height: 1_500
            ),
            SableMangaBakaPublicCoverImage(
                id: 2,
                indexNumeric: 2,
                language: "en",
                type: "volume",
                rawURL: "https://example.com/en-2.jpg",
                width: 1_000,
                height: 1_500
            )
        ]

        let upgrades = SableMangaBakaLibraryScanner.coversThatBeatMangaBaka(
            localCovers: local,
            mangaBakaCovers: mangaBaka
        )

        XCTAssertEqual(upgrades.map(\.path), ["_covers/jp/volume-1.jpg"])
    }

    func testLibraryScannerReadsComicInfoIDTypeAndDistinctVolumes() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let series = root
            .appendingPathComponent("Light Novels", isDirectory: true)
            .appendingPathComponent("Example Series (2020) {mb-54536}", isDirectory: true)
        try FileManager.default.createDirectory(
            at: series,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let sidecar = Data(
            #"{"title":"Example Series","type":"novel","ids":{"mangabaka":"54536"}}"#
                .utf8
        )
        try sidecar.write(to: series.appendingPathComponent("ComicInfo.json"))
        try Data("one".utf8).write(
            to: series.appendingPathComponent("Example Series - Volume 1.epub")
        )
        try Data("duplicate format".utf8).write(
            to: series.appendingPathComponent("Example Series - Vol 1.pdf")
        )
        try Data("two".utf8).write(
            to: series.appendingPathComponent("Example Series - Volume 2.epub")
        )

        let scanned = try SableMangaBakaLibraryScanner().scan(root: root)

        XCTAssertEqual(scanned.count, 1)
        XCTAssertEqual(scanned[0].title, "Example Series")
        XCTAssertEqual(scanned[0].mediaType, "novel")
        XCTAssertEqual(scanned[0].mangaBakaID, 54536)
        XCTAssertEqual(scanned[0].localBookCount, 2)
    }

    func testMangaBakaSeriesBundleMapsSplitArcsIntoContinuousVolumes() {
        let bundle = SableLibraryMangaBakaSeriesBundle(
            canonicalProvider: "ranobedb",
            canonicalSeriesID: "12081",
            mediaType: "novel",
            members: [
                SableLibraryMangaBakaSeriesBundleMember(
                    seriesID: 85_230,
                    title: "Dance of Spring",
                    mediaType: "novel",
                    sourceVolumeStart: 1,
                    sourceVolumeEnd: 2,
                    libraryVolumeStart: 1
                ),
                SableLibraryMangaBakaSeriesBundleMember(
                    seriesID: 105_091,
                    title: "Dance of Summer",
                    mediaType: "novel",
                    sourceVolumeStart: 1,
                    sourceVolumeEnd: 2,
                    libraryVolumeStart: 3
                ),
                SableLibraryMangaBakaSeriesBundleMember(
                    seriesID: 105_092,
                    title: "Archer of Dawn",
                    mediaType: "novel",
                    sourceVolumeStart: 1,
                    sourceVolumeEnd: 1,
                    libraryVolumeStart: 5
                ),
                SableLibraryMangaBakaSeriesBundleMember(
                    seriesID: 105_119,
                    title: "Dance of Autumn",
                    mediaType: "novel",
                    sourceVolumeStart: 1,
                    sourceVolumeEnd: 2,
                    libraryVolumeStart: 6
                ),
                SableLibraryMangaBakaSeriesBundleMember(
                    seriesID: 188_016,
                    title: "Twilight Archer",
                    mediaType: "novel",
                    sourceVolumeStart: 1,
                    sourceVolumeEnd: 1,
                    libraryVolumeStart: 8
                )
            ]
        )

        let spring = bundle.members[0]
        let summer = bundle.members[1]
        XCTAssertEqual(spring.libraryVolume(for: 1), 1)
        XCTAssertEqual(spring.libraryVolume(for: 2), 2)
        XCTAssertNil(spring.libraryVolume(for: 3))
        XCTAssertEqual(summer.libraryVolume(for: 1), 3)
        XCTAssertEqual(summer.libraryVolume(for: 2), 4)
        XCTAssertEqual(bundle.members[2].libraryVolume(for: 1), 5)
        XCTAssertEqual(bundle.members[3].libraryVolume(for: 1), 6)
        XCTAssertEqual(bundle.members[3].libraryVolume(for: 2), 7)
        XCTAssertEqual(bundle.members[4].libraryVolume(for: 1), 8)
        XCTAssertEqual(bundle.seriesIDs, [85_230, 105_091, 105_092, 105_119, 188_016])
        XCTAssertTrue(bundle.validationIssues.isEmpty)
    }

    func testMangaBakaSeriesBundleStorePreservesExistingComicInfo() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let comicInfoURL = root.appendingPathComponent("ComicInfo.json")
        try Data(
            #"{"title":"Agents Of The Four Seasons","type":"lightNovel","ids":{"ranobedb":"12081"},"_sable":{"keep_me":"yes"}}"#.utf8
        ).write(to: comicInfoURL)
        let bundle = SableLibraryMangaBakaSeriesBundle(
            canonicalProvider: "ranobedb",
            canonicalSeriesID: "12081",
            mediaType: "novel",
            members: [
                SableLibraryMangaBakaSeriesBundleMember(
                    seriesID: 85_230,
                    title: "Dance of Spring",
                    mediaType: "novel",
                    sourceVolumeStart: 1,
                    sourceVolumeEnd: 2,
                    libraryVolumeStart: 1
                ),
                SableLibraryMangaBakaSeriesBundleMember(
                    seriesID: 105_091,
                    title: "Dance of Summer",
                    mediaType: "novel",
                    sourceVolumeStart: 1,
                    sourceVolumeEnd: 2,
                    libraryVolumeStart: 3
                )
            ]
        )

        try SableLibraryMangaBakaSeriesBundleStore.save(
            bundle,
            to: comicInfoURL
        )

        let data = try Data(contentsOf: comicInfoURL)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(object["title"] as? String, "Agents Of The Four Seasons")
        let sable = try XCTUnwrap(object["_sable"] as? [String: Any])
        XCTAssertEqual(sable["keep_me"] as? String, "yes")
        XCTAssertEqual(
            SableLibraryMangaBakaSeriesBundleStore.load(from: object),
            bundle
        )
    }

    func testLibraryScannerRecognizesSavedMangaBakaSeriesBundle() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let series = root
            .appendingPathComponent("Light Novels", isDirectory: true)
            .appendingPathComponent("Agents Of The Four Seasons", isDirectory: true)
        try FileManager.default.createDirectory(
            at: series,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let sidecar = Data(
            """
            {
              "title": "Agents Of The Four Seasons",
              "type": "lightNovel",
              "ids": {"ranobedb": "12081"},
              "_sable": {
                "cover_series_bundle": {
                  "schema_version": 1,
                  "canonical_provider": "ranobedb",
                  "canonical_series_id": "12081",
                  "media_type": "novel",
                  "members": [
                    {
                      "series_id": 85230,
                      "title": "Dance of Spring",
                      "media_type": "novel",
                      "source_volume_start": 1,
                      "source_volume_end": 2,
                      "library_volume_start": 1
                    },
                    {
                      "series_id": 105091,
                      "title": "Dance of Summer",
                      "media_type": "novel",
                      "source_volume_start": 1,
                      "source_volume_end": 2,
                      "library_volume_start": 3
                    }
                  ]
                }
              }
            }
            """.utf8
        )
        try sidecar.write(to: series.appendingPathComponent("ComicInfo.json"))

        let scanned = try SableMangaBakaLibraryScanner().scan(root: root)

        XCTAssertEqual(scanned.count, 1)
        XCTAssertEqual(scanned[0].ranobeDBID, "12081")
        XCTAssertEqual(scanned[0].mangaBakaSeriesIDs, [85_230, 105_091])
        XCTAssertTrue(scanned[0].hasMangaBakaIdentity)
        XCTAssertEqual(
            scanned[0].mangaBakaSeriesBundle?.members[1].libraryVolumeStart,
            3
        )
    }

    func testCoverRequestUsesBundleIDsUnlessManualIDOverridesThem() {
        let bundle = SableLibraryMangaBakaSeriesBundle(
            canonicalProvider: "ranobedb",
            canonicalSeriesID: "12081",
            mediaType: "novel",
            members: [
                SableLibraryMangaBakaSeriesBundleMember(
                    seriesID: 85_230,
                    title: "Dance of Spring",
                    mediaType: "novel",
                    sourceVolumeStart: 1,
                    sourceVolumeEnd: 2,
                    libraryVolumeStart: 1
                ),
                SableLibraryMangaBakaSeriesBundleMember(
                    seriesID: 105_091,
                    title: "Dance of Summer",
                    mediaType: "novel",
                    sourceVolumeStart: 1,
                    sourceVolumeEnd: 2,
                    libraryVolumeStart: 3
                )
            ]
        )
        var request = SableLibraryCoverDownloadRequest(
            seriesTitle: "Agents Of The Four Seasons",
            mediaType: "lightNovel",
            queryTitles: ["Agents Of The Four Seasons"],
            mangaBakaSeriesBundle: bundle,
            localBooks: []
        )

        XCTAssertEqual(request.mangaBakaSeriesIDs, ["85230", "105091"])
        XCTAssertTrue(request.trustsMangaBakaSeriesID("105091"))

        request.manualSeriesMatches = [
            SableLibraryManualCoverSeriesMatch(
                source: .mangaBaka,
                providerID: "999",
                itemType: "series",
                title: "Manual",
                mediaType: "novel",
                bookType: nil,
                url: nil,
                thumbnailURL: nil
            )
        ]
        XCTAssertEqual(request.mangaBakaSeriesIDs, ["999"])
    }

    func testRolerContributorSessionUsesReturnedOAuthCredentials() async throws {
        let client = rolerClient { request in
            XCTAssertEqual(request.url?.path, "/user/me")
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "X-User-Token"),
                "user-secret"
            )
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "X-Session-Id"),
                "session-secret"
            )
            return (
                try XCTUnwrap(
                    HTTPURLResponse(
                        url: try XCTUnwrap(request.url),
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: nil
                    )
                ),
                Data(
                    """
                    {"data":{"role":"contributor","username":"Sample User","userId":"42"}}
                    """.utf8
                )
            )
        }

        let session = try await client.contributorSession(
            credentials: rolerCredentials
        )

        XCTAssertTrue(session.canEdit)
        XCTAssertEqual(session.accountLabel, "Sample User")
        XCTAssertEqual(session.userID, "42")
    }

    func testRolerConfirmedMappingUsesAutomaticIDAndRateLimitHeaders() async throws {
        let client = rolerClient { request in
            XCTAssertEqual(request.url?.path, "/map")
            XCTAssertEqual(request.httpMethod, "PATCH")
            let body = try JSONSerialization.jsonObject(
                with: requestBodyData(request)
            ) as? [String: Any]
            XCTAssertNil(body?["mappedId"])
            let series = try XCTUnwrap(
                body?["series"] as? [[String: String]]
            )
            XCTAssertEqual(
                Set(series.map { "\($0["providerId"] ?? ""):\($0["id"] ?? "")" }),
                ["mb:83317", "bw-g:series-123"]
            )
            return (
                try XCTUnwrap(
                    HTTPURLResponse(
                        url: try XCTUnwrap(request.url),
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: [
                            "RateLimit-Limit": "100",
                            "RateLimit-Remaining": "97",
                            "RateLimit-Reset": "45"
                        ]
                    )
                ),
                Data(#"{"data":{"failed":[]}}"#.utf8)
            )
        }

        let result = try await client.mapSeries(
            [
                SableRolerSeriesReference(providerId: "mb", id: "83317"),
                SableRolerSeriesReference(
                    providerId: "bw-g",
                    id: "series-123"
                )
            ],
            credentials: rolerCredentials
        )

        XCTAssertEqual(result.rateLimit.limit, 100)
        XCTAssertEqual(result.rateLimit.remaining, 97)
        XCTAssertEqual(result.rateLimit.resetSeconds, 45)
    }

    func testRolerVolumeCorrectionSendsOnlyConfirmedNumber() async throws {
        let client = rolerClient { request in
            XCTAssertEqual(request.url?.path, "/edit/books")
            XCTAssertEqual(request.httpMethod, "PATCH")
            let body = try JSONSerialization.jsonObject(
                with: requestBodyData(request)
            ) as? [String: Any]
            let books = try XCTUnwrap(
                body?["books"] as? [[String: Any]]
            )
            let book = try XCTUnwrap(books.first)
            XCTAssertEqual(book["providerId"] as? String, "bl")
            XCTAssertEqual(book["id"] as? String, "book-5")
            XCTAssertEqual(book["seriesId"] as? String, "series-1")
            XCTAssertEqual(
                (book["volume"] as? [String: String])?["number"],
                "5"
            )
            XCTAssertNil(book["type"])
            return (
                try XCTUnwrap(
                    HTTPURLResponse(
                        url: try XCTUnwrap(request.url),
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: nil
                    )
                ),
                Data(#"{"data":{"failed":[]}}"#.utf8)
            )
        }

        _ = try await client.editBookVolumes(
            [
                SableRolerBookVolumeCorrection(
                    providerId: "bl",
                    id: "book-5",
                    seriesId: "series-1",
                    volumeNumber: 5
                )
            ],
            credentials: rolerCredentials
        )
    }

    func testRolerRecognizesFlatMutationFailures() async throws {
        let client = rolerClient { request in
            (
                try XCTUnwrap(
                    HTTPURLResponse(
                        url: try XCTUnwrap(request.url),
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: nil
                    )
                ),
                Data(
                    """
                    {
                      "mapping_error": null,
                      "mapping_failed": [
                        {
                          "providerId": "bl",
                          "id": "series-1",
                          "message": "Series could not be mapped"
                        }
                      ]
                    }
                    """.utf8
                )
            )
        }

        do {
            _ = try await client.mapSeries(
                [
                    SableRolerSeriesReference(
                        providerId: "mb",
                        id: "104661"
                    ),
                    SableRolerSeriesReference(
                        providerId: "bl",
                        id: "series-1"
                    )
                ],
                credentials: rolerCredentials
            )
            XCTFail("Expected Roler's flat failure response to throw.")
        } catch let error as SableRolerContributorError {
            XCTAssertEqual(
                error,
                .rejected(
                    "bl/series-1: Series could not be mapped"
                )
            )
        }
    }

    func testRolerRateLimitBecomesCalmRetryError() async throws {
        let client = rolerClient { request in
            (
                try XCTUnwrap(
                    HTTPURLResponse(
                        url: try XCTUnwrap(request.url),
                        statusCode: 429,
                        httpVersion: nil,
                        headerFields: ["RateLimit-Reset": "120"]
                    )
                ),
                Data()
            )
        }

        do {
            _ = try await client.mapSeries(
                [
                    SableRolerSeriesReference(
                        providerId: "mb",
                        id: "83317"
                    ),
                    SableRolerSeriesReference(
                        providerId: "bw-g",
                        id: "series-123"
                    )
                ],
                credentials: rolerCredentials
            )
            XCTFail("Expected the request to be rate-limited.")
        } catch let error as SableRolerContributorError {
            XCTAssertEqual(error, .rateLimited(resetSeconds: 120))
        }
    }

    func testOnlyBBCProvidersProduceRolerMappingIDs() {
        XCTAssertEqual(
            SableLibraryBigBookCoversProvider.bookLiveJP.rolerProviderID,
            "bl"
        )
        XCTAssertEqual(
            SableLibraryBigBookCoversProvider.amazon.rolerProviderID,
            "amz"
        )
        XCTAssertNil(
            SableLibraryBigBookCoversProvider.yes24.rolerProviderID
        )
        XCTAssertNil(
            SableLibraryBigBookCoversProvider.kyobo.rolerProviderID
        )
        XCTAssertNil(
            SableLibraryBigBookCoversProvider.audibleUS.rolerProviderID
        )
        XCTAssertNil(
            SableLibraryBigBookCoversProvider.appleBooksUS.rolerProviderID
        )
        XCTAssertEqual(
            SableLibraryBigBookCoversProvider.shueisha.rolerProviderID,
            "shueisha"
        )
        XCTAssertNil(
            SableLibraryBigBookCoversProvider
                .rakutenKoboNetherlands
                .rolerProviderID
        )
    }

    private var rolerCredentials: SableRolerContributorCredentials {
        SableRolerContributorCredentials(
            userToken: "user-secret",
            sessionID: "session-secret"
        )
    }

    private func rolerClient(
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> SableRolerContributorClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SableMangaBakaURLProtocol.self]
        SableMangaBakaURLProtocol.handler = handler
        return SableRolerContributorClient(
            session: URLSession(configuration: configuration),
            baseURL: URL(string: "https://c.roler.dev")!
        )
    }

    private func cover(
        url: String,
        index: Double,
        isDefault: Bool,
        language: String = "ja",
        type: String = "volume"
    ) -> SableMangaBakaCoverImage {
        SableMangaBakaCoverImage(
            seriesID: nil,
            url: url,
            index: String(Int(index)),
            indexNumeric: index,
            language: language,
            type: type,
            isDefault: isDefault
        )
    }

    private func publicCover(
        id: Int,
        index: Double,
        language: String,
        type: String = "volume"
    ) -> SableMangaBakaPublicCoverImage {
        SableMangaBakaPublicCoverImage(
            id: id,
            indexNumeric: index,
            language: language,
            type: type,
            rawURL: "https://example.com/\(id).jpg",
            width: 1_000,
            height: 1_500
        )
    }

    private func storefrontSuggestion(
        provider: SableLibraryBigBookCoversProvider,
        language: String,
        volumeNumber: Double = 1,
        coverType: String = "volume",
        width: Int? = nil,
        height: Int? = nil,
        requiresRelationshipReview: Bool = false,
        automaticMatchConfidence: Double = 0,
        expectedMediaType: String? = nil,
        detectedMediaType: String? = nil,
        usesManualMediaTypeOverride: Bool = false,
        usesPublisherMediaTypeProof: Bool = false,
        contentRating: String = "safe",
        contentRatingWasInferred: Bool = false,
        detectedVolumeNumbers: [Int] = [],
        detectedChapterNumbers: [Int] = [],
        publicationType: String? = nil,
        visualSignature: [UInt8] = []
    ) -> SableMangaBakaStorefrontCoverSuggestion {
        SableMangaBakaStorefrontCoverSuggestion(
            provider: provider,
            providerSeriesID: "series",
            providerItemID:
                "\(provider.rawValue)-\(coverType)-\(volumeNumber)",
            title: "Example Volume 1",
            imageURL:
                "https://example.com/\(provider.rawValue)-\(coverType)-\(volumeNumber).jpg",
            storeURL: nil,
            volumeNumber: volumeNumber,
            language: language,
            coverType: coverType,
            requiresRelationshipReview: requiresRelationshipReview,
            automaticMatchConfidence: automaticMatchConfidence,
            expectedMediaType: expectedMediaType,
            detectedMediaType: detectedMediaType,
            usesManualMediaTypeOverride: usesManualMediaTypeOverride,
            usesPublisherMediaTypeProof: usesPublisherMediaTypeProof,
            width: width,
            height: height,
            contentRating: contentRating,
            contentRatingWasInferred: contentRatingWasInferred,
            detectedVolumeNumbers: detectedVolumeNumbers,
            detectedChapterNumbers: detectedChapterNumbers,
            publicationType: publicationType,
            visualSignature: visualSignature
        )
    }

    private func storefrontBook(
        id: String,
        title: String,
        sequence: Int,
        volumeNumber: Double? = nil
    ) -> SableLibraryBigBookCoversBookCandidate {
        SableLibraryBigBookCoversBookCandidate(
            provider: .bookWalkerJP,
            id: id,
            seriesID: "agents",
            title: title,
            url: nil,
            coverURL: "https://example.com/\(id).jpg",
            coverFallbackURLs: [],
            volumeNumber: volumeNumber ?? Double(sequence),
            volumeType: "volume",
            sequenceIndex: sequence,
            bookType: "novel"
        )
    }
}

private final class SableMangaBakaURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(
                self,
                didFailWithError: NSError(
                    domain: "SableMangaBakaURLProtocol",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Missing request handler"]
                )
            )
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func requestBodyData(_ request: URLRequest) throws -> Data {
    if let body = request.httpBody {
        return body
    }
    let stream = try XCTUnwrap(request.httpBodyStream)
    stream.open()
    defer { stream.close() }

    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4_096)
    while true {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count < 0 {
            throw stream.streamError ?? NSError(
                domain: "SableMangaBakaURLProtocol",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Could not read the request body"]
            )
        }
        if count == 0 {
            return data
        }
        data.append(buffer, count: count)
    }
}
