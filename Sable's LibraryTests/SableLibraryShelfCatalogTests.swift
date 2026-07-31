//
//  SableLibraryShelfCatalogTests.swift
//  Sable's LibraryTests
//

import XCTest
@testable import Sable_s_Library

final class SableLibraryShelfCatalogTests: XCTestCase {
    func testApothecaryDiariesUsesDescriptionOverLooseRomanceTags() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "The Apothecary Diaries",
                description: "Maomao is sold into the rear palace, where her knowledge of medicine and poison pulls her into consort mysteries and court work.",
                genres: ["Historical", "Mystery", "Romance"],
                themes: ["Medicine", "Investigation", "Court", "Working"],
                tags: ["Romantic Subplot", "LGBTQ+", "Female Lead"]
            )
        )

        XCTAssertEqual(suggestion.subShelf.code, "70.8")
        XCTAssertGreaterThanOrEqual(suggestion.confidence, 0.62)
    }

    func testSpiderUsesDungeonMonsterIsekaiInsteadOfIncidentalYuriFacet() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "So I'm a Spider, So What?",
                description: "A schoolgirl wakes up reborn as a tiny spider and has to survive in a deadly dungeon.",
                genres: ["Fantasy", "Adventure", "Action"],
                themes: ["Isekai", "Dungeon", "Game Elements", "Non-Human Protagonist"],
                tags: ["Yuri", "Anime Tie-In", "Manga Tie-In"]
            )
        )

        XCTAssertEqual(suggestion.subShelf.code, "21.5")
        XCTAssertTrue(suggestion.facets.contains("yuri"))
    }

    func testWrongRoyalUsesComedyFantasyOverRoyaltySetting() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "Hey! You've Kidnapped the Wrong Royal!",
                description: "A demon lord kidnaps the wrong royal in a gag-filled fantasy adventure.",
                genres: ["Fantasy", "Action", "Adventure", "Comedy"],
                themes: ["Comedy", "Adventure"],
                tags: ["Princess", "Demon Lord"]
            )
        )

        XCTAssertEqual(suggestion.subShelf.code, "20.7")
    }

    func testSilentWitchUsesMagicOverCourtPoliticsFacet() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "Secrets of the Silent Witch",
                description: "The Silent Witch is the only practitioner of Voiceless Magic and is sent to guard a prince while hiding her fear of public speaking.",
                genres: ["Fantasy", "School_life", "Comedy", "Drama"],
                themes: ["Magic", "Witch", "Boarding School"],
                tags: ["Royalty", "Politics", "Female Lead"]
            )
        )

        XCTAssertEqual(suggestion.subShelf.code, "20.1")
    }

    func testTagOnlyShelfSignalStaysLowConfidence() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "Untitled Folder",
                tags: ["Isekai"]
            )
        )

        XCTAssertLessThan(suggestion.confidence, 0.62)
        XCTAssertTrue([.low, .needsReview].contains(suggestion.confidenceLevel))
    }

    func testProviderGenreThemeAgreementCanStayReviewableWithoutDescription() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "Arifureta From Commonplace to World's Strongest",
                genres: ["Fantasy", "Adventure"],
                themes: ["Isekai", "Dungeon", "Game Elements"],
                tags: ["Anime Tie-In", "Manga Tie-In"]
            )
        )

        XCTAssertEqual(suggestion.subShelf.code, "21.6")
        XCTAssertTrue([.needsReview, .low, .medium].contains(suggestion.confidenceLevel))
        XCTAssertFalse(suggestion.warnings.contains { $0.localizedCaseInsensitiveContains("Only tag evidence") })
    }

    func testProviderNeighborsBoostOnlyExistingShelfEvidence() {
        let base = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "A Kiss and a Pair of Handcuffs",
                description: "A tense drama about a personal bond tested by danger and trust.",
                genres: ["Boys Love", "Drama", "Romance", "Yaoi"],
                tags: ["Yaoi", "BL"]
            )
        )
        let withNeighbors = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "A Kiss and a Pair of Handcuffs",
                description: "A tense drama about a personal bond tested by danger and trust.",
                genres: ["Boys Love", "Drama", "Romance", "Yaoi"],
                tags: ["Yaoi", "BL"],
                providerNeighborSignals: ["Boys Love", "Yaoi", "Mature Romance"]
            )
        )

        XCTAssertEqual(base.subShelf.code, "34.1")
        XCTAssertEqual(withNeighbors.subShelf.code, "34.1")
        XCTAssertGreaterThan(withNeighbors.confidence, base.confidence)
        XCTAssertTrue(withNeighbors.evidence.contains { $0.source == .providerNeighbor })
    }

    func testProviderNeighborsDoNotCreateShelfByThemselves() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "Untitled Folder",
                providerNeighborSignals: ["Boys Love", "Yaoi", "Mature Romance"]
            )
        )

        XCTAssertEqual(suggestion.shelf.code, "00")
        XCTAssertFalse(suggestion.evidence.contains { $0.source == .providerNeighbor })
    }

    func testGenericRomanceDoesNotBecomeFantasyRomanceWithoutFantasyAboutness() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "All My Loving",
                description: "A story about love, longing, and finding the courage to choose romance.",
                genres: ["Romance"],
                tags: ["Romance"]
            )
        )

        XCTAssertEqual(suggestion.subShelf.code, "30.1")
        XCTAssertEqual(suggestion.confidenceLevel, .medium)
        XCTAssertFalse(suggestion.evidence.contains { $0.source == .specificSignal })
    }

    func testSpecificFantasyRomanceSignalsCanReachHighConfidence() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "The Witch and the Cursed Duke",
                description: "A witch enters a magical engagement with a cursed duke and slowly turns an arranged marriage into love.",
                genres: ["Romance", "Fantasy"],
                themes: ["Fantasy Romance", "Marriage"],
                tags: ["Romance"]
            )
        )

        XCTAssertEqual(suggestion.subShelf.code, "30.3")
        XCTAssertEqual(suggestion.confidenceLevel, .high)
        XCTAssertTrue(suggestion.evidence.contains { point in
            point.source == .specificSignal
                && point.matchedTerms.contains { ["fantasy romance", "arranged marriage", "engagement", "marriage"].contains($0) }
        })
    }

    func testGenericIsekaiTitleBeatsLooseFantasyRomanceTags() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "Isekai Tensei: Recruited to Another World",
                description: "A summoned protagonist starts over in another world, learning magic and surviving a new adventure.",
                genres: ["Fantasy", "Romance"],
                tags: ["Reincarnation", "Romance"]
            )
        )

        XCTAssertEqual(suggestion.subShelf.code, "21.1")
    }

    func testDomesticIsekaiDoesNotBecomeFantasyRomanceFromLooseGenre() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "In Another World with Household Spells",
                description: "A reincarnated protagonist uses household spells and domestic magic to build a gentle daily life in another world.",
                genres: ["Fantasy", "Romance"],
                tags: ["Magic", "Slow Life"]
            )
        )

        XCTAssertEqual(suggestion.subShelf.code, "21.8")
    }

    func testFullSeriesHaremIsekaiUsesHouseholdPolygamyShelf() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "Mushoku Tensei: Jobless Reincarnation",
                description: "Kicked out by his family, he awakens reborn as an infant in a world of swords and sorcery. Across the full series, married life, multiple wives, children, and household drama become major long-running structures.",
                genres: ["Adventure", "Fantasy", "Harem"],
                themes: ["Isekai", "Magic", "Reincarnation", "Family", "Married Life"],
                tags: ["Harem", "Anime Tie-In", "Manga Tie-In", "Based on a Web Novel", "Reincarnation", "Multiple Wives"]
            )
        )

        XCTAssertEqual(suggestion.subShelf.code, "21.10")
        XCTAssertTrue([.medium, .high].contains(suggestion.confidenceLevel))
        XCTAssertFalse(suggestion.facets.contains("anime tie-in"))
        XCTAssertFalse(suggestion.facets.contains("manga tie-in"))
    }

    func testQueerRelationshipEngineBeatsVillainessIsekaiSetting() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "I'm in Love with the Villainess",
                description: "After waking inside an otome game, Rei pursues the villainess Claire in a girls love romance where the relationship is the core engine.",
                genres: ["Girls Love", "Fantasy", "Romance"],
                themes: ["Girls Love", "Yuri", "Isekai", "Villainess", "Otome Game"],
                tags: ["Villainess", "Reincarnation", "Nobility"]
            )
        )

        XCTAssertEqual(suggestion.subShelf.code, "34.2")
    }

    func testComedyParodyCanOverrideIsekaiSetting() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "KonoSuba: God's Blessing on This Wonderful World!",
                description: "A parody isekai comedy about ridiculous fantasy misadventures after a boy is sent to another world.",
                genres: ["Comedy", "Fantasy", "Adventure"],
                themes: ["Isekai", "Parody", "Gag", "Comedy"],
                tags: ["Adventurer", "Demon Lord", "Anime Tie-In"]
            )
        )

        XCTAssertEqual(suggestion.subShelf.code, "20.7")
    }

    func testSeriesWideVolumeDescriptionsSupportButDoNotOverwhelmMainEngine() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "Re:ZERO -Starting Life in Another World-",
                description: "A boy is suddenly summoned to another world and faces impossible danger.",
                volumeDescriptions: [
                    "After death, he returns to an earlier moment and tries to survive.",
                    "The time loop tightens around the mansion as repeated deaths reveal new clues.",
                    "Survival depends on understanding Return by Death without breaking under the pressure."
                ],
                genres: ["Fantasy", "Adventure"],
                themes: ["Isekai", "Time Loop", "Survival"],
                tags: ["Anime Tie-In", "Manga Tie-In"]
            )
        )

        XCTAssertEqual(suggestion.subShelf.code, "21.7")
        XCTAssertTrue(suggestion.evidence.contains { $0.source == .volumeDescription })
        XCTAssertTrue([.medium, .high].contains(suggestion.confidenceLevel))
    }

    func testVillainessIsekaiUsesContextBeforeRomanceOrCourtSignals() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "Villainess: Reborn to Rewrite Her Bad Ending",
                description: "After reincarnation she awakens as a villainess in a royal court and has to navigate engagement politics and survival in a fantasy world.",
                genres: ["Fantasy", "Romance", "Adventure"],
                themes: ["Isekai", "Villainess", "Court", "Reincarnation", "Royalty"],
                tags: ["Villainess", "Reincarnated as a Villainess", "Nobility", "Engagement"]
            )
        )

        XCTAssertEqual(suggestion.subShelf.code, "21.3")
    }

    func testOmegaverseNeedsPublicIdentitySignals() {
        let tagOnlySuggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "Untitled Folder",
                tags: ["Omegaverse", "Harem", "Dom/Sub"]
            )
        )

        XCTAssertEqual(tagOnlySuggestion.shelf.code, "00")
        XCTAssertTrue([.low, .needsReview].contains(tagOnlySuggestion.confidenceLevel))

        let identitySuggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "My Neighbour Is an Omega",
                description: "A tense omegaverse story about alpha, omega, and mating instinct in a modern household setup.",
                genres: ["Fantasy"],
                themes: ["Omegaverse", "Alpha", "Omega"],
                tags: ["Omegaverse", "Dom/Sub"]
            )
        )

        XCTAssertEqual(identitySuggestion.subShelf.code, "34.3")
    }

    func testOmegaTitleBeatsPlainBLWhenOmegaverseIsCentral() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "How to Deal When Your Intimidating Neighbor is Actually an Omega",
                description: "A college alpha discovers that his intimidating neighbor is actually an omega in an omegaverse romance.",
                genres: ["Boys Love", "Romance", "Yaoi"],
                tags: ["Omegaverse", "Alpha", "Omega", "Neighbors"]
            )
        )

        XCTAssertEqual(suggestion.subShelf.code, "34.3")
    }

    func testNonIsekaiSchoolHaremTagDoesNotBeatSchoolRomanceAboutness() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "Kusunoki's Flunking Her High School Glow-Up",
                description: "Two former outcasts try to survive high school popularity, awkward crushes, and social anxiety.",
                genres: ["Comedy", "Drama", "Romance", "Harem", "School_life"],
                tags: ["High School", "School Life", "Harem", "Heterosexual"]
            )
        )

        XCTAssertEqual(suggestion.subShelf.code, "30.1")
    }

    func testNonIsekaiHaremEngineUsesRomanticChaosShelf() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "The Prince's Reverse Harem",
                description: "A romance-first comedy where multiple love interests, competing suitors, and romantic chaos drive the plot.",
                genres: ["Romance", "Harem", "Comedy"],
                themes: ["Reverse Harem", "Romantic Rivalry"],
                tags: ["Harem", "Reverse Harem", "Multiple Love Interests"]
            )
        )

        XCTAssertEqual(suggestion.subShelf.code, "30.7")
    }

    func testWorkplaceSatireDoesNotUseCozyIsekaiShelf() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "Life Lessons with Uramichi Oniisan",
                description: "A dark comedy workplace satire about a miserable children's TV host and the showbiz adults around him.",
                genres: ["Comedy", "Psychological", "Slice of Life"],
                tags: ["Working", "Showbiz", "Gag Humor", "Satire", "Dark Comedy"]
            )
        )

        XCTAssertEqual(suggestion.subShelf.code, "40.9")
    }

    func testReverseIsekaiFoodSliceOfLifeBeatsGenericFantasyRomance() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "Welcome to Japan, Ms. Elf!",
                description: "A man travels to a fantasy world in his dreams and brings an elf back to Japan, where food and gentle daily life become a major focus.",
                genres: ["Fantasy", "Adventure", "Comedy", "Romance", "Slice of Life"],
                tags: ["Isekai", "Reverse Isekai", "Transported to Another World", "Cooking", "Food", "Gourmet", "Romantic Subplot"]
            )
        )

        XCTAssertEqual(suggestion.subShelf.code, "21.8")
    }

    func testSummonedAnimalTransformationIsekaiBeatsGenericFantasyRomance() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "The White Cat's Revenge as Plotted from the Dragon King's Lap",
                description: "A young woman is stranded in another world, abandoned in a forest, and becomes tied to cats, dragons, magic, and revenge.",
                genres: ["Fantasy", "Action", "Adventure", "Comedy", "Drama", "Romance", "Slice of Life"],
                tags: ["Isekai", "Summoned into Another World", "Animal Transformation", "Shapeshifting", "Cats", "Dragons", "Magic"]
            )
        )

        XCTAssertEqual(suggestion.subShelf.code, "21.5")
    }

    func testBLAndYuriNeedMainlineNarrativeSupportNotSingleTagNoise() {
        let blByTagOnly = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "Untitled Folder",
                tags: ["Boys Love", "Yaoi", "Dom/Sub"]
            )
        )

        XCTAssertNotEqual(blByTagOnly.shelf.code, "34")
        XCTAssertTrue(blByTagOnly.confidence < 0.62)

        let blMainline = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "Given",
                description: "A boys' love story about music and heartbreak.",
                genres: ["Boys Love", "Drama", "Music"],
                themes: ["Boys Love", "Male x Male"]
            )
        )

        XCTAssertEqual(blMainline.subShelf.code, "34.1")
    }

    func testPublicBLGenreCanBeHighConfidenceWithoutDescriptionRepeatingIdentity() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "A Kiss and a Pair of Handcuffs",
                description: "A tense drama about a personal bond tested by danger and trust.",
                genres: ["Boys Love", "Drama", "Romance", "Yaoi"],
                tags: ["Yaoi", "BL"],
                contentWarnings: ["Yaoi"]
            )
        )

        XCTAssertEqual(suggestion.subShelf.code, "34.1")
        XCTAssertEqual(suggestion.confidenceLevel, .high)
        XCTAssertFalse(suggestion.warnings.contains { $0.localizedCaseInsensitiveContains("content") })
    }

    func testExplicitBLGenreBeatsGenericFantasyRomanceSignals() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "The Husky and His White Cat Shizun",
                description: "A reborn cultivator returns to a violent fantasy world shaped by magic, supernatural conflict, and a complicated bond with his shizun.",
                genres: ["Fantasy", "Supernatural", "Boys Love", "Drama", "Romance", "Yaoi"],
                tags: ["Magic", "Romance", "Cultivation"],
                contentWarnings: ["Sexual Assault"]
            )
        )

        XCTAssertEqual(suggestion.subShelf.code, "34.1")
        XCTAssertTrue([.medium, .high].contains(suggestion.confidenceLevel))
        XCTAssertTrue(suggestion.warnings.contains { $0.localizedCaseInsensitiveContains("content") })
    }

    func testNonBLXianxiaUsesCultivationFantasyShelf() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "Sword Sect Records",
                description: "A young cultivator enters a mountain sect and trains with qi, sword cultivation, and immortal masters.",
                genres: ["Fantasy", "Action", "Adventure"],
                tags: ["Cultivation", "Xianxia", "Sects", "Martial Arts"]
            )
        )

        XCTAssertEqual(suggestion.subShelf.code, "20.6")
    }

    func testBLGenreStillBeatsCultivationFantasyWhenPublicGenreIsCentral() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "The Husky and His White Cat Shizun",
                description: "A boys love danmei story about a reborn cultivator, his shizun, and a complicated relationship in a xianxia world.",
                genres: ["Fantasy", "Boys Love", "Romance", "Yaoi"],
                themes: ["Boys Love", "Danmei"],
                tags: ["Cultivation", "Xianxia", "Shizun"]
            )
        )

        XCTAssertEqual(suggestion.subShelf.code, "34.1")
    }

    func testShounenAiGenreStaysOnBLShelf() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "Sasaki and Miyano",
                description: "A school life romance about two boys gradually understanding their feelings.",
                genres: ["Boys Love", "Comedy", "Romance", "Slice of Life", "School_life", "Shounen_ai"],
                tags: ["Boys Love", "Shounen AI", "BL", "Romance"]
            )
        )

        XCTAssertEqual(suggestion.subShelf.code, "34.1")
        XCTAssertTrue([.medium, .high].contains(suggestion.confidenceLevel))
    }

    func testFunctionalDerivativeTagsDoNotCreateShelfEvidence() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "Untitled Folder",
                tags: ["Anime Tie-In", "Manga Tie-In", "Adapted to Anime", "Adapted to Manga", "Based on a Web Novel", "Light Novel"]
            )
        )

        XCTAssertEqual(suggestion.subShelf.code, "00.1")
        XCTAssertEqual(suggestion.confidenceLevel, .needsReview)
    }

    func testLibrarianTagRolesSeparateAboutnessFromBibliographicRelationships() {
        let records = [
            SableLibraryShelfTagRecord(
                name: "Adapted to Anime",
                path: "Derivative Work > Adaptations > Adapted to Anime",
                providerWeight: "unweighted"
            ),
            SableLibraryShelfTagRecord(
                name: "Time Loop",
                path: "Narrative Tropes > Plot Structure > Time Manipulation > Time Loop",
                providerWeight: "core"
            ),
            SableLibraryShelfTagRecord(
                name: "Fantasy",
                path: "Settings > Fantasy",
                providerWeight: "defining",
                isGenre: true
            ),
            SableLibraryShelfTagRecord(
                name: "Yuri",
                path: "Themes > Girls Love > Yuri",
                providerWeight: "recurrent",
                isSpoiler: true
            ),
            SableLibraryShelfTagRecord(
                name: "Light Novel",
                providerWeight: "unweighted"
            )
        ]

        let classifications = Dictionary(
            uniqueKeysWithValues: SableLibraryShelfTagClassifier.classify(records).map { ($0.record.name, $0) }
        )

        XCTAssertEqual(classifications["Adapted to Anime"]?.role, .bibliographicRelationship)
        XCTAssertEqual(classifications["Adapted to Anime"]?.use, .bibliographicRelationship)
        XCTAssertEqual(classifications["Time Loop"]?.role, .narrativeEngine)
        XCTAssertEqual(classifications["Time Loop"]?.use, .subShelfEvidence)
        XCTAssertEqual(classifications["Fantasy"]?.role, .contentGenre)
        XCTAssertEqual(classifications["Fantasy"]?.use, .mainShelfEvidence)
        XCTAssertEqual(classifications["Yuri"]?.role, .relationship)
        XCTAssertEqual(classifications["Yuri"]?.use, .facet)
        XCTAssertEqual(classifications["Light Novel"]?.role, .formOrCarrier)

        let shelfEvidence = SableLibraryShelfTagClassifier.shelfEvidenceNames(from: records)
        XCTAssertTrue(shelfEvidence.contains("Time Loop"))
        XCTAssertTrue(shelfEvidence.contains("Fantasy"))
        XCTAssertFalse(shelfEvidence.contains("Adapted to Anime"))
        XCTAssertFalse(shelfEvidence.contains("Yuri"))
        XCTAssertFalse(shelfEvidence.contains("Light Novel"))
    }

    func testRichProviderTagRecordsSupportShelfWithoutFunctionalNoise() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "Return Again in Another World",
                description: "A summoned boy keeps dying in another world and has to survive repeated resets.",
                genres: ["Fantasy"],
                tagRecords: [
                    SableLibraryShelfTagRecord(
                        name: "Time Loop",
                        path: "Narrative Tropes > Plot Structure > Time Manipulation > Time Loop",
                        providerWeight: "core"
                    ),
                    SableLibraryShelfTagRecord(
                        name: "Adapted to Anime",
                        path: "Derivative Work > Adaptations > Adapted to Anime",
                        providerWeight: "unweighted"
                    ),
                    SableLibraryShelfTagRecord(
                        name: "Seinen",
                        path: "Audience Demographics > Male Oriented > Seinen",
                        providerWeight: "defining"
                    ),
                    SableLibraryShelfTagRecord(
                        name: "Rape",
                        path: "Sexual Content > Sexual Acts > Rape",
                        providerWeight: "recurrent",
                        contentRating: "safe"
                    )
                ]
            )
        )

        XCTAssertEqual(suggestion.subShelf.code, "21.7")
        XCTAssertTrue(suggestion.evidence.contains { point in
            point.source == .theme && point.matchedTerms.contains("time loop")
        })
        XCTAssertFalse(suggestion.facets.contains("adapted to anime"))
        XCTAssertFalse(suggestion.evidence.contains { point in
            point.matchedTerms.contains("seinen")
        })
        XCTAssertTrue(suggestion.warnings.contains { $0.localizedCaseInsensitiveContains("content") })
    }

    func testMangaBakaSexualAndDemographicTagsDoNotBecomeShelfEvidence() {
        let records = [
            SableLibraryShelfTagRecord(
                name: "Ecchi",
                path: "Sexual Content > Ecchi",
                providerWeight: "defining",
                contentRating: "safe"
            ),
            SableLibraryShelfTagRecord(
                name: "Josei",
                path: "Audience Demographics > Female Oriented > Josei",
                providerWeight: "defining"
            ),
            SableLibraryShelfTagRecord(
                name: "Cooking",
                path: "Activities > Cooking",
                providerWeight: "core"
            )
        ]

        let classifications = Dictionary(
            uniqueKeysWithValues: SableLibraryShelfTagClassifier.classify(records).map { ($0.record.name, $0) }
        )

        XCTAssertEqual(classifications["Ecchi"]?.role, .contentAdvisory)
        XCTAssertEqual(classifications["Ecchi"]?.use, .reviewOnly)
        XCTAssertEqual(classifications["Josei"]?.role, .audienceDemographic)
        XCTAssertEqual(classifications["Josei"]?.use, .facet)
        XCTAssertEqual(classifications["Cooking"]?.role, .subjectTheme)
        XCTAssertEqual(classifications["Cooking"]?.use, .subShelfEvidence)
    }

    func testMilitarySciFiBeatsGenericRomanceForEightySix() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "86--EIGHTY-SIX",
                description: "A republic claims its unmanned drones fight a bloodless war, but soldiers in the Eighty-Sixth Sector are forced onto the battlefield.",
                genres: ["Action", "Drama", "Romance", "Sci-Fi", "Mecha"],
                tags: ["Military", "War", "Robots", "Artificial Intelligence", "Dystopian", "Romantic Subplot"]
            )
        )

        XCTAssertEqual(suggestion.subShelf.code, "60.2")
    }

    func testParodyIsekaiBeatsCozyFoodFromIncidentalFood() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "Konosuba: God's Blessing on This Wonderful World!",
                description: "A parody isekai comedy about ridiculous fantasy misadventures after a boy is reborn in a parallel world and just wants enough money and food to survive.",
                genres: ["Comedy", "Fantasy", "Adventure", "Romance", "Harem"],
                themes: ["Isekai", "Parody", "Satire", "Slapstick"],
                tags: ["Transported to Another World", "Parody", "Satire", "Slapstick", "Useless Power", "Misfortune"]
            )
        )

        XCTAssertEqual(suggestion.subShelf.code, "20.7")
    }

    func testKonosubaMainSeriesStaysComedyFirstDespiteHaremFacet() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "Konosuba: God's Blessing on This Wonderful World!",
                description: "Kazuma is reborn in a parallel world with Aqua and begins ridiculous fantasy misadventures.",
                volumeDescriptions: [
                    "Kazuma, Aqua, Megumin, and Darkness create more chaotic fantasy comedy."
                ],
                genres: ["Fantasy", "Adventure", "Comedy", "Romance", "Harem"],
                themes: ["Isekai", "Comedy"],
                tags: ["Travel", "Harem", "Misfortune", "Useless Power"]
            )
        )

        XCTAssertEqual(suggestion.subShelf.code, "20.7")
    }

    func testCraftingIsekaiBeatsPlainCraftFantasy() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "Survival in Another World with My Mistress!",
                description: "A man wakes in another world and uses video game crafting powers to harvest resources, build whatever he imagines, and survive.",
                genres: ["Fantasy", "Adventure", "Harem"],
                themes: ["Isekai", "Crafting"],
                tags: ["Crafting", "Survival", "Isekai", "Harem"]
            )
        )

        XCTAssertEqual(suggestion.subShelf.code, "21.2")
    }

    func testDeathGameThrillerBeatsGenericAdventureFantasy() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "Playing Death Games to Put Food on the Table",
                description: "A girl wakes in a locked house and survives deadly games full of traps, weapons, and battle royale rules.",
                genres: ["Action", "Drama", "Mystery", "Suspense"],
                tags: ["Death Game", "Play or Die", "High Stakes Games", "Battle Royale", "Survival"]
            )
        )

        XCTAssertEqual(suggestion.subShelf.code, "50.5")
    }

    func testVRMMOWithoutWorldTransferUsesSciFiGameShelf() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "Sword Art Online",
                description: "Players are trapped in a virtual reality online game where dying in the game means dying outside it too.",
                genres: ["Sci-Fi", "Fantasy", "Adventure"],
                tags: ["Virtual Reality", "VRMMO", "Online Game", "Death Game"]
            )
        )

        XCTAssertEqual(suggestion.subShelf.code, "60.4")
    }

    func testScienceMagicPowersBeatGenericFantasyRomance() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "A Certain Magical Index",
                description: "Academy City is a scientific marvel where superhuman abilities are ranked, while magic, anti-magic, and sorcerers collide with science.",
                genres: ["Action", "Comedy", "Fantasy", "Romance", "Sci-Fi", "Supernatural"],
                tags: ["ESP", "Super Powers", "Special Abilities", "Anti-Magic", "Futuristic City", "Magic"]
            )
        )

        XCTAssertEqual(suggestion.subShelf.code, "60.7")
    }

    func testFolkloreMysteryUsesSupernaturalMysteryOverGenericFolklore() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "Associate Professor Akira Takatsuki's Conjecture",
                description: "A folklore studies professor investigates urban legends, haunted objects, curses, spirits, and strange festivals.",
                genres: ["Mystery", "Supernatural", "Psychological"],
                tags: ["Folklore", "Urban Legend", "Spirits", "Investigation"]
            )
        )

        XCTAssertEqual(suggestion.subShelf.code, "50.4")
    }

    func testOtomeIsekaiBeatsIncidentalMechaTags() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "Trapped in a Dating Sim: The World of Otome Games is Tough for Mobs",
                description: "A worker is reincarnated into an otome game world and has to survive the social rules of the dating sim.",
                genres: ["Fantasy", "Romance", "Sci-Fi", "Mecha"],
                themes: ["Isekai", "Otome Game", "Dating Sim"],
                tags: ["Mecha", "Artificial Intelligence", "Reincarnation", "Otome Game"]
            )
        )

        XCTAssertEqual(suggestion.subShelf.code, "21.3")
    }

    func testVillainessRegressionWorldUsesBroaderVillainessShelf() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "The Villainess Is Dead! Long Live the Empress!",
                description: "After a poisonous bad ending, she gets a second chance through regression and fights the death flag of her villainess role.",
                genres: ["Fantasy", "Romance"],
                tags: ["Villainess", "Regression", "Death Flag", "Canon Fodder"]
            )
        )

        XCTAssertEqual(suggestion.subShelf.code, "21.3")
    }

    func testGameWorldIsekaiDoesNotBecomePlainMilitaryFromSingleBattlefieldClue() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "Overlord",
                description: "A player remains inside a game world as the overlord of a guild base and begins exploring the changed fantasy world.",
                genres: ["Fantasy", "Adventure", "Action"],
                themes: ["Isekai", "Game World", "Guilds"],
                tags: ["MMORPG", "Game Elements", "Transported to Another World", "Guilds"]
            )
        )

        XCTAssertEqual(suggestion.subShelf.code, "21.6")
    }

    func testGenericReincarnationDoesNotCreateVillainessRegressionShelf() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "I've Been Killing Slimes for 300 Years and Maxed Out My Level",
                description: "After dying from overwork, she is reincarnated as an immortal witch and spends centuries living a relaxed fantasy life.",
                genres: ["Fantasy", "Slice of Life"],
                tags: ["Isekai", "Reincarnation", "Witch", "Slow Life"]
            )
        )

        XCTAssertNotEqual(suggestion.subShelf.code, "21.3")
        XCTAssertEqual(suggestion.subShelf.code, "21.8")
    }

    func testHeroPartyQuietLifeUsesSlowLifeShelf() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "Banished from the Hero's Party, I Decided to Live a Quiet Life in the Countryside",
                description: "After leaving the hero's party, Red opens an apothecary on the frontier and tries to live an easy quiet life in the countryside.",
                genres: ["Fantasy", "Slice of Life", "Romance"],
                tags: ["Countryside", "Slow Life", "Cooking", "Agriculture"]
            )
        )

        XCTAssertEqual(suggestion.subShelf.code, "40.6")
    }

    func testFluffyParadiseUsesCozyIsekaiOverCourtSignals() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "Fluffy Paradise",
                description: "A woman is reincarnated into another world with the ability to be adored by all creatures, spending her days cuddling fantasy animals.",
                genres: ["Fantasy", "Adventure", "Slice of Life"],
                themes: ["Isekai", "Slow Life"],
                tags: ["Reincarnation", "Isekai", "Animals", "Pets", "Slow Life", "Nobility"]
            )
        )

        XCTAssertEqual(suggestion.subShelf.code, "21.8")
    }

    func testWeakestTamerUsesCozyIsekaiInsteadOfSurvivalThriller() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "The Weakest Tamer Began a Journey to Pick Up Trash",
                description: "Ivy has memories of a past life, learns to travel on her own, tames a slime companion, and slowly finds a chosen family.",
                genres: ["Fantasy", "Adventure", "Slice of Life"],
                themes: ["Isekai", "Travel", "Found Family"],
                tags: ["Reincarnation", "Isekai", "Survival", "Slimes", "Travel", "Found Family"]
            )
        )

        XCTAssertEqual(suggestion.subShelf.code, "21.8")
    }

    func testPublicBLGenreBeatsGenericFantasyRomance() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "You Can Have My Back",
                description: "Leorino remembers a previous romance between two men and is drawn back toward the prince connected to that love story.",
                genres: ["Fantasy", "Boys Love", "Romance", "Yaoi"],
                themes: ["Boys Love"],
                tags: ["Boys Love", "Yaoi", "BL", "Reincarnation", "Nobility"]
            )
        )

        XCTAssertEqual(suggestion.subShelf.code, "34.1")
    }

    func testKnownRomanceCoreTitleCanReachHighConfidence() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "The Tales of Marielle Clarac",
                description: "A noble's daughter receives a marriage proposal and her romance with Simeon becomes the core of the story.",
                genres: ["Fantasy", "Romance", "Historical"],
                tags: ["Marriage", "Engagement", "Romance"]
            )
        )

        XCTAssertEqual(suggestion.subShelf.code, "30.3")
        XCTAssertEqual(suggestion.confidenceLevel, .high)
    }

    func testHeatAloneDoesNotCreateOmegaverseShelf() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "The White Cat's Revenge as Plotted from the Dragon King's Lap",
                description: "A fantasy romance about a cat transformation, a dragon king, and tension in the heat of danger.",
                genres: ["Fantasy", "Romance"],
                tags: ["Shapeshifting", "Animal Transformation", "Dragon", "Isekai"]
            )
        )

        XCTAssertNotEqual(suggestion.subShelf.code, "34.3")
    }

    func testSpyVocabularyUsesEspionageShelf() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "Spy Classroom",
                description: "A spy team from an intelligence agency trains for an impossible covert mission involving infiltration, sabotage, deception, and undercover work.",
                genres: ["Action", "Mystery", "Suspense"],
                tags: ["Spies", "Espionage", "Secret Mission", "Undercover"]
            )
        )

        XCTAssertEqual(suggestion.subShelf.code, "50.8")
    }

    func testComedyParodyCanBeatDemonFantasyWhenTitleAndDescriptionSupportIt() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "Combatants Will Be Dispatched!",
                description: "A combat agent from an evil organization is sent into a fantasy world for absurd misadventures and villain organization parody.",
                genres: ["Comedy", "Fantasy", "Adventure"],
                themes: ["Parody", "Satire", "Comedy"],
                tags: ["Demon Lord", "Parody", "Misfortune"]
            )
        )

        XCTAssertEqual(suggestion.subShelf.code, "20.7")
    }

    func testProductionMagicVillageDefenseUsesCraftKnowledgeIsekai() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "Easygoing Territory Defense by the Optimistic Lord: Production Magic Turns a Nameless Village into the Strongest Fortified City",
                description: "A reincarnated nobleman with production magic uses past-life knowledge, construction, ballistae, and fortifications to transform a nameless village into a prosperous fortified city.",
                volumeDescriptions: [
                    "Van builds fortifications and develops the village with production magic.",
                    "Past-life knowledge helps him construct defenses and improve trade routes."
                ],
                genres: ["Fantasy", "Isekai"],
                themes: ["Isekai", "Production Magic", "Territory Development"],
                tags: ["Crafting", "Production Magic", "Reincarnation"]
            )
        )

        XCTAssertEqual(suggestion.subShelf.code, "21.2")
        XCTAssertEqual(suggestion.confidenceLevel, .high)
    }

    func testMonsterSceneryDoesNotCreateAlteredBodyIsekaiShelf() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "Taking My Reincarnation One Step at a Time: No One Told Me There Would Be Monsters!",
                description: "Sarasa is thrust into a fantasy world as a ten-year-old girl in a strange land filled with flying beasts and oversized wolves. A monster hunter takes her in, and she slowly learns magic and builds a new life.",
                genres: ["Fantasy", "Adventure"],
                themes: ["Isekai", "Reincarnation", "Found Family"],
                tags: ["Magic", "Found Family", "Dungeon"]
            )
        )

        XCTAssertNotEqual(suggestion.subShelf.code, "21.5")
    }

    func testAdultFantasyServiceReviewComedyDoesNotBecomeRomance() {
        let input = SableLibraryShelfCatalogInput(
            title: "Interspecies Reviewers: Ecstasy Days",
            description: "An adult fantasy comedy where adventurers visit sexy shops and succubus establishments, then review and grade the services.",
            genres: ["Fantasy", "Comedy", "Erotica"],
            tags: ["Smut", "Succubus", "Comedy"],
            contentWarnings: ["Smut"]
        )
        let suggestion = SableLibraryShelfCatalog.suggestShelf(for: input)
        let ledger = SableLibraryShelfCatalog.decisionLedger(for: input, suggestion: suggestion)

        XCTAssertEqual(suggestion.subShelf.code, "20.7")
        XCTAssertNotEqual(suggestion.subShelf.code, "30.3")
        XCTAssertNotEqual(ledger.actionability, .manualPreference)
    }

    func testAdultContentFacetDoesNotForceManualPreferenceWhenShelfEvidenceIsClear() {
        let input = SableLibraryShelfCatalogInput(
            title: "Survival in Another World with My Mistress!",
            description: "A man wakes in another world and survives with video game crafting powers, harvesting resources and building whatever he can imagine.",
            genres: ["Fantasy", "Adventure", "Adult"],
            themes: ["Isekai", "Crafting"],
            tags: ["Crafting", "Harem", "Ecchi"],
            contentWarnings: ["Adult"]
        )
        let suggestion = SableLibraryShelfCatalog.suggestShelf(for: input)
        let ledger = SableLibraryShelfCatalog.decisionLedger(for: input, suggestion: suggestion)

        XCTAssertEqual(suggestion.subShelf.code, "21.2")
        XCTAssertEqual(ledger.actionability, .goodEvidence)
        XCTAssertTrue(suggestion.warnings.contains { $0.localizedCaseInsensitiveContains("Adult-content metadata") })
    }

    func testScienceFictionShelfIsBroaderThanSpace() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "Beacon of Light in the Dark Sea",
                description: "Inside the 3000m underwater station, an international group of scientists and engineers research possible settlement of the human race before the station becomes a survival stage of cult madness and chaos.",
                genres: ["Fantasy", "Action", "Drama"],
                tags: ["Web Novel", "Korean Novels"]
            )
        )

        XCTAssertEqual(suggestion.subShelf.code, "60.1")
        XCTAssertEqual(suggestion.subShelf.displayName, "60.1 - Science Fiction & Speculative Worlds")
    }

    func testGenericReincarnationDoesNotCreateStrategyIsekaiForMasterSwordsman() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "The World's Least Interesting Master Swordsman",
                description: "After being reincarnated into a fantasy world, Sansui spends five hundred years swinging his sword before raising a child and heading out into the world.",
                genres: ["Fantasy", "Action", "Adventure", "Martial Arts", "Harem"],
                tags: ["Swordplay", "Swordsman", "Reincarnation", "Isekai", "Reincarnated in Another World", "Harem"]
            )
        )

        XCTAssertEqual(suggestion.subShelf.code, "21.1")
        XCTAssertNotEqual(suggestion.subShelf.code, "21.9")
    }

    func testSlowLifeEvidenceCanBeatSwordsmanAdventureFallback() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "A Reincarnated Swordsman's Quiet Life",
                description: "After reincarnating in another world, a swordsman chooses a slow life, raises a child, and enjoys quiet daily life between small journeys.",
                genres: ["Fantasy", "Slice of Life"],
                themes: ["Isekai", "Slow Life"],
                tags: ["Isekai", "Swordsman", "Slow Life", "Found Family"]
            )
        )

        XCTAssertEqual(suggestion.subShelf.code, "21.8")
    }

    func testHardModeStatsUsesGameSystemsStatsIsekai() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "Starting on Hard Mode: God Levels, Got Problems",
                description: "Merlin awakens in a strange new world with god-tier stats, ridiculous powers, and chaotic companions.",
                genres: ["Fantasy", "Action", "Adventure", "Comedy"],
                tags: ["Reincarnation", "Isekai", "Game Elements", "Harem", "Magic"]
            )
        )

        XCTAssertEqual(suggestion.subShelf.code, "21.6")
        XCTAssertEqual(suggestion.subShelf.displayName, "21.6 - Game Systems, Stats & VRMMO Isekai")
    }

    func testMafiaStoryUsesCrimeShelf() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "Sister Mafioso",
                description: "A nun-in-training with amnesia is pulled back toward the don's mafia family and the organized crime world she escaped.",
                genres: ["Fantasy", "Mystery", "Romance", "Adventure", "Thriller"],
                tags: ["Female Lead"]
            )
        )

        XCTAssertEqual(suggestion.subShelf.code, "50.8")
        XCTAssertEqual(suggestion.subShelf.displayName, "50.8 - Crime, Heists & Espionage")
    }

    func testDisownedMagicToolsUsesCraftKnowledgeIsekai() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "Disowned but Not Disheartened! Life Is Good with Overpowered Magic",
                description: "A girl with memories of her previous life invents magic tools, studies overpowered magic, and grows into a new life after being disowned.",
                genres: ["Fantasy", "Comedy"],
                tags: ["Reincarnation", "Isekai", "Invention", "Magic Academy", "Magic"]
            )
        )

        XCTAssertEqual(suggestion.subShelf.code, "21.2")
    }

    func testCorpseKingComedyUsesParodyFantasy() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "The Return of the Corpse King",
                description: "A former summoned hero returns to stop the Secret Society Helheim, then has to face the cringey secret that he founded the organization himself.",
                genres: ["Fantasy", "Action", "Adventure", "Comedy", "Harem"],
                tags: ["Harem"]
            )
        )

        XCTAssertEqual(suggestion.subShelf.code, "20.7")
    }

    func testPuppositesUsesContemporaryRomance() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "Pupposites Attract",
                description: "A fluffy, feel-good romance manga for dog lovers where two mismatched pairs meet at the park and an unlikely friendship may become something more.",
                genres: ["Comedy", "Romance", "Slice of Life", "Shoujo"],
                tags: ["Josei", "Animals", "Dogs", "Pets", "Mature Romance"]
            )
        )

        XCTAssertEqual(suggestion.subShelf.code, "30.1")
    }

    func testEarthChosenSaviorUsesPsychologicalSurvivalShelf() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "The Earth's Chosen Savior",
                description: "The universe decides to destroy Earth in forty-two days, and monsters invade through gateways from an alien world while a chosen savior obsesses over saving Earth.",
                genres: ["Fantasy", "Action", "Psychological"],
                tags: ["Game Elements", "Web Novel"]
            )
        )

        XCTAssertEqual(suggestion.subShelf.code, "50.5")
    }

    func testAgeRegressionAloneDoesNotCreateVillainessRegressionWorld() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "Nia Liston: The Merciless Maiden",
                description: "A great hero wakes in the body of a sickly young girl and starts training until she is in fighting form again.",
                genres: ["Fantasy", "Action", "Adventure", "Comedy"],
                tags: ["Age Regression", "Reincarnation", "Isekai", "Cultivation", "Martial Arts"]
            )
        )

        XCTAssertNotEqual(suggestion.subShelf.code, "21.3")
    }

    func testSpiderAlteredBodyIsekaiBeatsLooseSciFiGenre() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "So I'm a Spider, So What?",
                description: "A high school girl wakes up in another world and is reborn as a spider in the worst dungeon ever.",
                genres: ["Fantasy", "Sci-Fi", "Adventure", "Psychological"],
                tags: ["Isekai", "Non-Human Protagonist", "Dungeon", "Sci-Fi"]
            )
        )

        XCTAssertEqual(suggestion.subShelf.code, "21.5")
    }

    func testWhiteCatTransformationIsekaiBeatsConspiracyVocabulary() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "The White Cat's Revenge as Plotted from the Dragon King's Lap",
                description: "Ruri is summoned to another world, gets caught in a conspiracy, and transforms into a white cat with a mystical bracelet.",
                genres: ["Fantasy", "Adventure", "Romance", "Slice of Life"],
                tags: ["Isekai", "Animal Transformation", "Shapeshifting", "Cats", "Conspiracy"]
            )
        )

        XCTAssertEqual(suggestion.subShelf.code, "21.5")
        XCTAssertNotEqual(suggestion.subShelf.code, "50.8")
    }

    func testGenericFutureLanguageDoesNotCreateScienceFictionShelf() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "A Fantasy of the Future",
                description: "The future is not what he saw, so he sets out on a journey to avoid the fate waiting for him.",
                genres: ["Fantasy", "Adventure"],
                tags: ["Time Travel"]
            )
        )

        XCTAssertNotEqual(suggestion.subShelf.code, "60.1")
    }

    func testCultistMobDoesNotMeanCrimeMob() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "I Got Reincarnated as a Cultist Mob in an Eroge Full of Maniacs with Death Wishes",
                description: "A reincarnated minor character tries to escape a dangerous cult in another world.",
                genres: ["Fantasy", "Action", "Comedy", "Romance"],
                tags: ["Isekai", "Reincarnation", "Harem", "Gore"]
            )
        )

        XCTAssertNotEqual(suggestion.subShelf.code, "50.8")
    }

    func testDungeonTrapsDoNotOverrideDungeonAdventureShelf() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "BLADE & BASTARD",
                description: "An amnesiac adventurer explores an unexplored dungeon full of traps and retrieves fallen adventurers.",
                genres: ["Fantasy", "Action", "Adventure", "Horror"],
                tags: ["Dungeon", "Adventurers", "Dark Fantasy"]
            )
        )

        XCTAssertEqual(suggestion.subShelf.code, "20.4")
        XCTAssertNotEqual(suggestion.subShelf.code, "50.5")
    }

    func testBladeAndBastardReincarnationNoiseDoesNotCreateIsekaiShelf() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "BLADE & BASTARD",
                description: "Deep in the unexplored reaches of the dungeon, a corpse is discovered. After Iarumas is resurrected, his memories of life before death are gone, and he delves into the dungeon to retrieve dead adventurers.",
                volumeDescriptions: [
                    "A resurrected adventurer gulps the fresh air of her second chance at life.",
                    "Strange parasitic beasts invade the upper levels of the dungeon after rising from the lower levels."
                ],
                genres: ["Fantasy", "Action", "Adventure", "Horror"],
                themes: ["Dungeon", "Guild", "Adventurer"],
                tags: ["Dungeon", "Adventurers", "Dark Fantasy", "Fantasy World", "RPG", "Reincarnation"]
            )
        )

        XCTAssertEqual(suggestion.subShelf.code, "20.4")
        XCTAssertNotEqual(suggestion.shelf.code, "21")
    }

    func testBeginningAfterTheEndUsesReincarnationFantasyOverSchoolLifeTag() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "The Beginning After the End",
                description: "A king is reincarnated into a new magical fantasy world, grows into a young adventurer, and learns magic while larger conflicts gather around him.",
                genres: ["Fantasy", "Action", "Adventure", "School_life"],
                themes: ["Reincarnation", "Magic", "Adventure"],
                tags: ["School Life", "Reincarnation", "Magic", "Fantasy"]
            )
        )

        XCTAssertEqual(suggestion.subShelf.code, "21.1")
        XCTAssertNotEqual(suggestion.subShelf.code, "40.2")
    }

    func testRearguardUsesAdventureIsekaiWithHaremAsFacet() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "The World's Strongest Rearguard: Labyrinth Country's Novice Seeker",
                description: "Reborn into a fantasy world, Arihito becomes an adventurer called a Seeker with the job class called rearguard, providing party support in Labyrinth Country.",
                genres: ["Fantasy", "Action", "Adventure", "Romance", "Harem"],
                tags: ["Isekai", "Reincarnation", "Dungeon", "Guilds", "Harem", "Game Elements"]
            )
        )

        XCTAssertEqual(suggestion.subShelf.code, "21.1")
        XCTAssertNotEqual(suggestion.subShelf.code, "21.5")
    }

    func testQuietAdventureIsekaiBeatsLaterWarVolumeNoise() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "The Water Magician",
                description: "Ryo is reincarnated into the fantastical world of Phi, hoping for a quiet life learning water magic. Taking it easy becomes difficult when deadly monsters force him to fight for his life.",
                volumeDescriptions: [
                    "Later volumes mention a kingdom, war, and empire, but the series remains rooted in his new world adventure and second life."
                ],
                genres: ["Fantasy", "Action", "Adventure", "Comedy"],
                tags: ["Reincarnation", "Isekai", "Dungeon", "Mages", "Slow Romance"]
            )
        )

        XCTAssertEqual(suggestion.subShelf.code, "21.1")
        XCTAssertEqual(suggestion.confidenceLevel, .high)
    }

    func testTakingMyReincarnationUsesCozyFoundFamilyIsekai() {
        let suggestion = SableLibraryShelfCatalog.suggestShelf(
            for: SableLibraryShelfCatalogInput(
                title: "Taking My Reincarnation One Step at a Time: No One Told Me There Would Be Monsters!",
                description: "A woman with a mana deficit is reborn as a child in another world, where a monster hunter takes her in and she builds a new life with found family.",
                genres: ["Fantasy", "Adventure"],
                tags: ["Isekai", "Reincarnation", "Found Family", "Slow Life", "Magic"]
            )
        )

        XCTAssertEqual(suggestion.subShelf.code, "21.8")
        XCTAssertNotEqual(suggestion.subShelf.code, "21.5")
    }

    func testSideStoryLedgerRequestsParentSeriesInheritance() {
        let input = SableLibraryShelfCatalogInput(
            title: "Mushoku Tensei: Redundant Reincarnation",
            description: "A side story collection about weddings, married life, and later family moments.",
            genres: ["Fantasy", "Romance"],
            tags: ["Side Story", "Marriage", "Wedding"]
        )

        let ledger = SableLibraryShelfCatalog.decisionLedger(for: input)

        XCTAssertEqual(ledger.actionability, .parentInheritanceCandidate)
        XCTAssertFalse(ledger.ruleChangeNeeded)
        XCTAssertTrue(ledger.neededEvidence.contains("parent-series shelf or prior decision"))
    }

    func testDecisionLedgerExplainsHighConfidenceSpecificShelf() {
        let input = SableLibraryShelfCatalogInput(
            title: "Re:ZERO -Starting Life in Another World-",
            description: "A boy is summoned to another world and survives through Return by Death, repeated resets, and psychological horror.",
            volumeDescriptions: [
                "Repeated deaths force him to understand each time loop.",
                "Survival depends on carrying memories through each reset."
            ],
            genres: ["Fantasy", "Thriller", "Psychological"],
            themes: ["Isekai", "Time Loop", "Survival", "Psychological Horror"],
            tagRecords: [
                SableLibraryShelfTagRecord(
                    name: "Time Loop",
                    path: "Narrative Tropes > Plot Structure > Time Manipulation > Time Loop",
                    providerWeight: "core"
                )
            ]
        )

        let suggestion = SableLibraryShelfCatalog.suggestShelf(for: input)
        let ledger = SableLibraryShelfCatalog.decisionLedger(for: input, suggestion: suggestion)

        XCTAssertEqual(suggestion.subShelf.code, "21.7")
        XCTAssertEqual(ledger.actionability, .goodEvidence)
        XCTAssertFalse(ledger.ruleChangeNeeded)
        XCTAssertTrue(ledger.mainEvidence.contains { $0.contains("Description") })
        XCTAssertFalse(ledger.whyNotCompeting.isEmpty)
    }

    func testDecisionLedgerMarksThinMetadataAsEvidenceProblem() {
        let input = SableLibraryShelfCatalogInput(
            title: "Untitled Folder",
            tags: ["Isekai"]
        )

        let ledger = SableLibraryShelfCatalog.decisionLedger(for: input)

        XCTAssertEqual(ledger.actionability, .evidenceProblem)
        XCTAssertFalse(ledger.ruleChangeNeeded)
        XCTAssertTrue(ledger.neededEvidence.contains("series or volume description"))
        XCTAssertTrue(ledger.neededEvidence.contains("provider tag paths and weights"))
    }

    func testDecisionLedgerKeepsSensitiveMetadataUserControlled() {
        let input = SableLibraryShelfCatalogInput(
            title: "The Husky and His White Cat Shizun",
            description: "A boys love danmei story about a reborn cultivator, his shizun, and a complicated relationship in a xianxia world.",
            genres: ["Fantasy", "Boys Love", "Romance", "Yaoi"],
            themes: ["Boys Love", "Danmei"],
            tags: ["Cultivation", "Xianxia", "Shizun"],
            contentWarnings: ["Sexual Assault"]
        )

        let suggestion = SableLibraryShelfCatalog.suggestShelf(for: input)
        let ledger = SableLibraryShelfCatalog.decisionLedger(for: input, suggestion: suggestion)

        XCTAssertEqual(suggestion.subShelf.code, "34.1")
        XCTAssertEqual(ledger.actionability, .manualPreference)
        XCTAssertTrue(ledger.neededEvidence.contains("manual check for sensitive or user-controlled metadata"))
    }

    func testDecisionLedgerSeparatesEngineFromIsekaiAndHaremFacets() {
        let input = SableLibraryShelfCatalogInput(
            title: "The Eminence in Shadow",
            description: "A parody fantasy about a boy acting out his secret organization delusions in another world.",
            genres: ["Action", "Comedy", "Fantasy", "Adventure", "Harem"],
            themes: ["Isekai", "Parody", "Satire"],
            tags: ["Isekai", "Harem", "Adapted to Anime", "Male Protagonist"]
        )

        let suggestion = SableLibraryShelfCatalog.suggestShelf(for: input)
        let ledger = SableLibraryShelfCatalog.decisionLedger(for: input, suggestion: suggestion)

        XCTAssertEqual(suggestion.subShelf.code, "20.7")
        XCTAssertTrue(ledger.evidenceRoles.engine.contains("parody"))
        XCTAssertTrue(ledger.evidenceRoles.publicGenre.contains("Comedy"))
        XCTAssertTrue(ledger.evidenceRoles.facet.contains("Harem"))
        XCTAssertTrue(ledger.evidenceRoles.ignoredForShelf.contains("Adapted to Anime"))
        XCTAssertFalse(ledger.mainEvidence.contains { $0.localizedCaseInsensitiveContains("adapted to anime") })
    }

    func testSupportOnlyEvidenceCannotBecomeHighConfidence() {
        let input = SableLibraryShelfCatalogInput(
            title: "Untitled School Folder",
            tagRecords: [
                SableLibraryShelfTagRecord(
                    name: "School",
                    path: "Settings > School",
                    providerWeight: "defining"
                ),
                SableLibraryShelfTagRecord(
                    name: "Female Lead",
                    path: "Character Types > Female Lead",
                    providerWeight: "defining"
                ),
                SableLibraryShelfTagRecord(
                    name: "Adapted to Anime",
                    path: "Derivative Work > Adapted to Anime",
                    providerWeight: "unweighted"
                )
            ]
        )

        let suggestion = SableLibraryShelfCatalog.suggestShelf(for: input)
        let ledger = SableLibraryShelfCatalog.decisionLedger(for: input, suggestion: suggestion)

        XCTAssertNotEqual(suggestion.confidenceLevel, .high)
        XCTAssertEqual(ledger.actionability, .evidenceProblem)
        XCTAssertTrue(ledger.evidenceRoles.setting.contains { $0.localizedCaseInsensitiveContains("school") })
        XCTAssertTrue(ledger.evidenceRoles.facet.contains("Female Lead"))
        XCTAssertTrue(ledger.evidenceRoles.ignoredForShelf.contains("Adapted to Anime"))
        XCTAssertTrue(suggestion.warnings.contains { $0.localizedCaseInsensitiveContains("support a shelf") })
    }

    func testDecisionLedgerShowsMixedEngineSettingForKokoroConnectLikeCase() {
        let input = SableLibraryShelfCatalogInput(
            title: "Kokoro Connect",
            description: "A school club friendship drama where students are forced through body swapping and psychological pressure.",
            genres: ["Comedy", "Drama", "Slice of Life"],
            tagRecords: [
                SableLibraryShelfTagRecord(
                    name: "Body Swapping",
                    path: "Narrative Tropes > Body Swapping",
                    providerWeight: "core"
                ),
                SableLibraryShelfTagRecord(
                    name: "School Club",
                    path: "Settings > School Clubs",
                    providerWeight: "core"
                ),
                SableLibraryShelfTagRecord(
                    name: "Love Triangle",
                    path: "Relationship Dynamics > Love Triangle",
                    providerWeight: "recurrent"
                )
            ]
        )

        let ledger = SableLibraryShelfCatalog.decisionLedger(for: input)

        XCTAssertTrue(ledger.evidenceRoles.engine.contains { $0.localizedCaseInsensitiveContains("body") })
        XCTAssertTrue(ledger.evidenceRoles.setting.contains("School Club"))
        XCTAssertTrue(ledger.evidenceRoles.facet.contains("Love Triangle"))
        XCTAssertTrue([.legitimateAmbiguity, .goodEvidence, .evidenceProblem].contains(ledger.actionability))
    }

}
