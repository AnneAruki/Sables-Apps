//
//  SableLibraryShelfCatalog.swift
//  Sable's Library
//

import Foundation

nonisolated struct SableLibraryShelfCatalogInput: Sendable, Equatable {
    var title: String
    var description: String?
    var volumeDescriptions: [String]
    var genres: [String]
    var themes: [String]
    var tags: [String]
    var tagRecords: [SableLibraryShelfTagRecord]
    var providerNeighborSignals: [String]
    var contentWarnings: [String]
    var mediaType: String?

    init(
        title: String,
        description: String? = nil,
        volumeDescriptions: [String] = [],
        genres: [String] = [],
        themes: [String] = [],
        tags: [String] = [],
        tagRecords: [SableLibraryShelfTagRecord] = [],
        providerNeighborSignals: [String] = [],
        contentWarnings: [String] = [],
        mediaType: String? = nil
    ) {
        self.title = title
        self.description = description
        self.volumeDescriptions = volumeDescriptions
        self.genres = genres
        self.themes = themes
        self.tags = tags
        self.tagRecords = tagRecords
        self.providerNeighborSignals = providerNeighborSignals
        self.contentWarnings = contentWarnings
        self.mediaType = mediaType
    }
}

nonisolated struct SableLibraryShelfDefinition: Identifiable, Sendable, Equatable {
    var code: String
    var title: String
    var subShelves: [SableLibrarySubShelfDefinition]

    var id: String { code }
    var displayName: String { "\(code) - \(title)" }
}

nonisolated struct SableLibrarySubShelfDefinition: Identifiable, Sendable, Equatable {
    var code: String
    var title: String

    var id: String { code }
    var displayName: String { "\(code) - \(title)" }
}

nonisolated enum SableLibraryShelfEvidenceSource: String, Codable, CaseIterable, Sendable {
    case title
    case description
    case volumeDescription
    case genre
    case theme
    case tag
    case specificSignal
    case providerNeighbor
    case safety

    var displayName: String {
        switch self {
        case .title: "Title"
        case .description: "Description"
        case .volumeDescription: "Volume descriptions"
        case .genre: "Genre"
        case .theme: "Theme"
        case .tag: "Tag"
        case .specificSignal: "Specific shelf clues"
        case .providerNeighbor: "Provider neighbors"
        case .safety: "Safety"
        }
    }
}

nonisolated enum SableLibraryShelfConfidenceLevel: String, Codable, Sendable {
    case high
    case medium
    case low
    case needsReview

    var displayName: String {
        switch self {
        case .high: "High"
        case .medium: "Medium"
        case .low: "Low"
        case .needsReview: "Needs review"
        }
    }
}

nonisolated struct SableLibraryShelfEvidencePoint: Sendable, Equatable {
    var source: SableLibraryShelfEvidenceSource
    var matchedTerms: [String]
    var score: Double
    var note: String
}

nonisolated enum SableLibraryShelfEvidenceRole: String, Codable, CaseIterable, Sendable {
    case engine
    case publicGenre
    case setting
    case facet
    case formatFunction
    case sensitiveReview
    case userPreference
    case ignoredForShelf

    var displayName: String {
        switch self {
        case .engine: "Engine"
        case .publicGenre: "Public genre"
        case .setting: "Setting"
        case .facet: "Facet"
        case .formatFunction: "Format/function"
        case .sensitiveReview: "Sensitive/review"
        case .userPreference: "Preference"
        case .ignoredForShelf: "Ignored for shelf"
        }
    }
}

nonisolated struct SableLibraryShelfEvidenceRoleLedger: Codable, Sendable, Equatable {
    var engine: [String] = []
    var publicGenre: [String] = []
    var setting: [String] = []
    var facet: [String] = []
    var formatFunction: [String] = []
    var sensitiveReview: [String] = []
    var userPreference: [String] = []
    var ignoredForShelf: [String] = []

    func values(for role: SableLibraryShelfEvidenceRole) -> [String] {
        switch role {
        case .engine: engine
        case .publicGenre: publicGenre
        case .setting: setting
        case .facet: facet
        case .formatFunction: formatFunction
        case .sensitiveReview: sensitiveReview
        case .userPreference: userPreference
        case .ignoredForShelf: ignoredForShelf
        }
    }

    var engineEvidence: [String] {
        uniqueEvidenceRoleValues(engine + publicGenre)
    }

    var supportOnlyEvidence: [String] {
        uniqueEvidenceRoleValues(setting + facet + formatFunction + sensitiveReview + userPreference + ignoredForShelf)
    }
}

nonisolated struct SableLibraryShelfAlternative: Sendable, Equatable {
    var shelf: SableLibraryShelfDefinition
    var subShelf: SableLibrarySubShelfDefinition
    var score: Double
}

nonisolated struct SableLibraryShelfSuggestion: Sendable, Equatable {
    var shelf: SableLibraryShelfDefinition
    var subShelf: SableLibrarySubShelfDefinition
    var confidence: Double
    var confidenceLevel: SableLibraryShelfConfidenceLevel
    var evidence: [SableLibraryShelfEvidencePoint]
    var alternatives: [SableLibraryShelfAlternative]
    var facets: [String]
    var evidenceRoles: SableLibraryShelfEvidenceRoleLedger
    var warnings: [String]

    var displayPath: String {
        "\(shelf.displayName) / \(subShelf.displayName)"
    }
}

nonisolated enum SableLibraryShelfDecisionActionability: String, Codable, CaseIterable, Hashable, Sendable {
    case goodEvidence
    case evidenceProblem
    case legitimateAmbiguity
    case possibleRuleProblem
    case manualPreference
    case parentInheritanceCandidate

    var displayName: String {
        switch self {
        case .goodEvidence: "Good evidence"
        case .evidenceProblem: "Evidence problem"
        case .legitimateAmbiguity: "Legitimate ambiguity"
        case .possibleRuleProblem: "Possible rule problem"
        case .manualPreference: "Manual preference / user-controlled"
        case .parentInheritanceCandidate: "Parent-series inheritance candidate"
        }
    }
}

nonisolated struct SableLibraryShelfDecisionLedger: Codable, Sendable, Equatable {
    var suggestedShelf: String
    var suggestedPath: String
    var shelfCode: String
    var subShelfCode: String
    var confidence: SableLibraryShelfConfidenceLevel
    var confidenceScore: Double
    var mainEvidence: [String]
    var evidenceRoles: SableLibraryShelfEvidenceRoleLedger
    var competingShelves: [String]
    var whyNotCompeting: [String]
    var neededEvidence: [String]
    var userCorrection: String?
    var actionability: SableLibraryShelfDecisionActionability
    var ruleChangeNeeded: Bool
}

nonisolated enum SableLibraryShelfCatalog {
    static let shelves: [SableLibraryShelfDefinition] = [
        shelf("00", "Review & Exceptions", [
            sub("00.1", "Needs Metadata"),
            sub("00.2", "Mixed Genre or Low Confidence"),
            sub("00.3", "Identity-Sensitive Review"),
            sub("00.4", "Duplicate or Edition Review"),
            sub("00.5", "Provider Conflict"),
            sub("00.6", "Restricted Review"),
            sub("00.7", "Shelf Rule Conflict"),
            sub("00.8", "Manual Override or Personal Preference")
        ]),
        shelf("10", "Action & Adventure", [
            sub("10.1", "Combat & Martial Arts"),
            sub("10.2", "Quests & Journeys"),
            sub("10.3", "Survival & Wilderness"),
            sub("10.4", "Military & War"),
            sub("10.5", "Revenge & Rivalry"),
            sub("10.8", "Tournaments & Competition")
        ]),
        shelf("20", "Fantasy & Supernatural", [
            sub("20.1", "Magic & Sorcery"),
            sub("20.2", "Myth, Folklore & Spirits"),
            sub("20.3", "Paranormal Life & Supernatural Beings"),
            sub("20.4", "Dungeons, Guilds & Adventurers"),
            sub("20.5", "Demons, Monsters & Non-Human Fantasy"),
            sub("20.6", "Cultivation, Xianxia & Wuxia"),
            sub("20.7", "Comic & Parody Fantasy"),
            sub("20.8", "Craft, Trade & Knowledge Fantasy"),
            sub("20.9", "Dark, Urban & Paranormal Fantasy")
        ]),
        shelf("21", "Isekai & Other Worlds", [
            sub("21.1", "Adventure & Quest Isekai"),
            sub("21.2", "Craft, Trade & Knowledge Isekai"),
            sub("21.3", "Villainess, Otome & Regression Worlds"),
            sub("21.4", "Court, Nobility & Royal Isekai"),
            sub("21.5", "Altered-Body & Monster Isekai"),
            sub("21.6", "Game Systems, Stats & VRMMO Isekai"),
            sub("21.7", "Survival, Horror & Time Loop Isekai"),
            sub("21.8", "Cozy, Food & Healing Isekai"),
            sub("21.9", "Kingdom, War & Strategy Isekai"),
            sub("21.10", "Harem, Household & Polygamy Isekai")
        ]),
        shelf("30", "Romance", [
            sub("30.1", "Contemporary Romance"),
            sub("30.2", "Historical Romance"),
            sub("30.3", "Fantasy Romance"),
            sub("30.4", "Slow Burn & First Love"),
            sub("30.5", "Marriage, Engagement & Contracts"),
            sub("30.6", "Love Triangles & Rivalry"),
            sub("30.7", "Harem, Reverse Harem & Romantic Chaos"),
            sub("30.8", "Family & Domestic Romance"),
            sub("30.9", "Sports & Competition Romance")
        ]),
        shelf("34", "BL, GL & Queer Relationship Fiction", [
            sub("34.1", "BL & Yaoi"),
            sub("34.2", "GL & Yuri"),
            sub("34.3", "Omegaverse & Secondary Gender"),
            sub("34.4", "Dom/Sub, Guideverse, Cakeverse & Nameverse"),
            sub("34.5", "Queer School & Coming-of-Age"),
            sub("34.6", "Queer Contemporary & Adult Life"),
            sub("34.7", "Poly, Harem & Complex Queer Relationships"),
            sub("34.8", "Relationship Dynamics, Power & Toxicity"),
            sub("34.9", "Queer Fantasy, Royalty & Supernatural Romance")
        ]),
        shelf("40", "Slice of Life, Work & School", [
            sub("40.1", "Daily Life & Iyashikei"),
            sub("40.2", "School Life"),
            sub("40.3", "Workplace & Careers"),
            sub("40.4", "Food, Cooking & Gourmet"),
            sub("40.6", "Healing, Slow Life & Rural Life"),
            sub("40.9", "Comedy & Gag")
        ]),
        shelf("50", "Mystery, Horror & Thriller", [
            sub("50.1", "Detective & Investigation"),
            sub("50.4", "Supernatural Mystery"),
            sub("50.5", "Psychological Thriller"),
            sub("50.6", "Horror, Monsters & Body Horror"),
            sub("50.8", "Crime, Heists & Espionage")
        ]),
        shelf("60", "Sci-Fi, Games & Technology", [
            sub("60.1", "Science Fiction & Speculative Worlds"),
            sub("60.2", "Mecha & Military Tech"),
            sub("60.4", "VRMMO & Game Worlds"),
            sub("60.5", "Game Systems & Leveling"),
            sub("60.6", "Time Travel & Time Loops"),
            sub("60.7", "ESP, Powers & Science Magic")
        ]),
        shelf("70", "Historical, Court & Society", [
            sub("70.2", "Court, Nobility & Royal Houses"),
            sub("70.4", "Politics, Succession & Power"),
            sub("70.6", "War, Diplomacy & Kingdoms"),
            sub("70.8", "Court Work, Medicine & Trade")
        ]),
        shelf("80", "Literary, Adaptations & Media", [
            sub("80.1", "Literary Fiction & Classics"),
            sub("80.4", "Adaptations & Franchise Works"),
            sub("80.5", "Fanbooks, Side Stories & Extras"),
            sub("80.9", "Books, Libraries & Publishing")
        ]),
        shelf("90", "Nonfiction, Essays & Reference", [
            sub("90.1", "Essays, Commentary & Criticism"),
            sub("90.2", "History, Biography & Memoir"),
            sub("90.3", "Culture, Society & Politics"),
            sub("90.4", "Psychology, Self-Help & Communication"),
            sub("90.5", "Identity, Gender & Queer Nonfiction"),
            sub("90.6", "Art, Writing, Media & Creative Process"),
            sub("90.7", "Food, Home & Practical Skills"),
            sub("90.8", "Education, Science & Knowledge"),
            sub("90.9", "Reference, Guides & Data Books")
        ])
    ]

    static func suggestShelf(for input: SableLibraryShelfCatalogInput) -> SableLibraryShelfSuggestion {
        let text = EvidenceText(input: input)
        var candidates = rules.compactMap { rule -> CandidateScore? in
            var candidate = CandidateScore(rule: rule)
            candidate.add(source: .title, terms: rule.titleTerms, text: text.title, weight: 5, cap: 8)
            candidate.add(source: .description, terms: rule.descriptionTerms, text: text.description, weight: 4, cap: 8)
            candidate.add(source: .volumeDescription, terms: rule.descriptionTerms, text: text.volumeDescriptions, weight: 1.75, cap: 5)
            candidate.add(source: .genre, terms: rule.genreTerms, text: text.genres, weight: 3.5, cap: 7)
            candidate.add(source: .theme, terms: rule.themeTerms, text: text.themes, weight: 3, cap: 7)
            if !rule.requiresPublicIdentity {
                candidate.add(source: .tag, terms: rule.tagTerms, text: text.tags, weight: 1, cap: 2.5)
            }
            candidate.add(source: .specificSignal, terms: rule.specificTerms, text: text.specificSignals, weight: 2.25, cap: 6)
            if !candidate.points.isEmpty {
                candidate.add(
                    source: .providerNeighbor,
                    terms: rule.genreTerms + rule.themeTerms + rule.tagTerms + rule.specificTerms,
                    text: text.providerNeighbors,
                    weight: 0.75,
                    cap: 1.5
                )
            }
            if rule.requiresIsekaiContext, !text.hasIsekaiContext {
                return nil
            }
            if rule.requiresRomanceEngineWhenIsekai,
               text.hasIsekaiContext,
               !text.hasRomanceEngineContext {
                return nil
            }
            if rule.excludesIsekaiContext, text.hasIsekaiContext {
                return nil
            }
            return candidate.totalScore > 0 ? candidate : nil
        }

        if candidates.isEmpty {
            candidates = [CandidateScore(reviewRule: reviewRule, note: "No title, description, genre, or theme signal was strong enough.")]
        }

        candidates.sort { $0.totalScore > $1.totalScore }
        promotePublicIdentityCandidateIfNeeded(in: &candidates)
        var top = candidates[0]
        let runnerUp = candidates.dropFirst().first
        var warnings = reviewWarnings(for: input, text: text)
        let preliminaryEvidenceRoles = evidenceRoleLedger(for: input, suggestionEvidence: top.points)
        let confidence = confidenceScore(
            for: top,
            runnerUp: runnerUp,
            evidenceRoles: preliminaryEvidenceRoles,
            warnings: &warnings
        )

        if confidence.level == .needsReview, top.rule.subCode != "00.1" {
            top.points.append(
                SableLibraryShelfEvidencePoint(
                    source: .safety,
                    matchedTerms: [],
                    score: 0,
                    note: "Shelf evidence is too weak or too close to a competing shelf, so this should stay reviewable."
                )
            )
        }

        let evidenceRoles = evidenceRoleLedger(for: input, suggestionEvidence: top.points)
        let selectedShelf = shelf(for: top.rule.shelfCode)
        let selectedSubShelf = subShelf(for: top.rule.subCode)
        return SableLibraryShelfSuggestion(
            shelf: selectedShelf,
            subShelf: selectedSubShelf,
            confidence: confidence.value,
            confidenceLevel: confidence.level,
            evidence: top.points.sorted { $0.score > $1.score },
            alternatives: candidates.dropFirst().prefix(3).map {
                SableLibraryShelfAlternative(
                    shelf: shelf(for: $0.rule.shelfCode),
                    subShelf: subShelf(for: $0.rule.subCode),
                    score: $0.totalScore
                )
            },
            facets: facets(for: input, text: text),
            evidenceRoles: evidenceRoles,
            warnings: warnings
        )
    }

    static func decisionLedger(for input: SableLibraryShelfCatalogInput) -> SableLibraryShelfDecisionLedger {
        let suggestion = suggestShelf(for: input)
        return decisionLedger(for: input, suggestion: suggestion)
    }

    static func decisionLedger(
        for input: SableLibraryShelfCatalogInput,
        suggestion: SableLibraryShelfSuggestion
    ) -> SableLibraryShelfDecisionLedger {
        let actionability = decisionActionability(for: input, suggestion: suggestion)
        return SableLibraryShelfDecisionLedger(
            suggestedShelf: suggestion.subShelf.displayName,
            suggestedPath: suggestion.displayPath,
            shelfCode: suggestion.shelf.code,
            subShelfCode: suggestion.subShelf.code,
            confidence: suggestion.confidenceLevel,
            confidenceScore: suggestion.confidence,
            mainEvidence: ledgerEvidence(from: suggestion),
            evidenceRoles: suggestion.evidenceRoles,
            competingShelves: suggestion.alternatives.prefix(3).map(\.subShelf.displayName),
            whyNotCompeting: ledgerCompetitionReasons(for: suggestion),
            neededEvidence: ledgerNeededEvidence(for: input, suggestion: suggestion, actionability: actionability),
            userCorrection: nil,
            actionability: actionability,
            ruleChangeNeeded: actionability == .possibleRuleProblem
        )
    }

    static func shelf(for code: String) -> SableLibraryShelfDefinition {
        shelves.first { $0.code == code } ?? shelves[0]
    }

    static func subShelf(for code: String) -> SableLibrarySubShelfDefinition {
        shelves.flatMap(\.subShelves).first { $0.code == code } ?? shelves[0].subShelves[0]
    }

    private static func evidenceRoleLedger(
        for input: SableLibraryShelfCatalogInput,
        suggestionEvidence: [SableLibraryShelfEvidencePoint]
    ) -> SableLibraryShelfEvidenceRoleLedger {
        var ledger = SableLibraryShelfEvidenceRoleLedger()

        appendEvidencePoints(suggestionEvidence, to: &ledger)
        ledger.publicGenre.append(contentsOf: input.genres)
        for theme in input.themes {
            appendRoleValue(theme, defaultRole: .engine, to: &ledger)
        }
        ledger.sensitiveReview.append(contentsOf: input.contentWarnings)

        let tagClassifications = SableLibraryShelfTagClassifier.classify(
            uniqueTagRecords(input.tagRecords + input.tags.map { SableLibraryShelfTagRecord(name: $0) })
        )
        for classification in tagClassifications {
            let name = classification.record.name
            switch classification.role {
            case .contentGenre:
                ledger.publicGenre.append(name)
            case .narrativeEngine, .subjectTheme:
                ledger.engine.append(name)
            case .settingFrame:
                ledger.setting.append(name)
            case .relationship, .characterOrSpecies, .audienceDemographic, .unknown:
                ledger.facet.append(name)
            case .bibliographicRelationship, .formOrCarrier, .productionStatus:
                ledger.formatFunction.append(name)
                ledger.ignoredForShelf.append(name)
            case .contentAdvisory:
                ledger.sensitiveReview.append(name)
            }
        }

        if input.mediaType?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
           let mediaType = input.mediaType {
            ledger.formatFunction.append(mediaType)
        }

        return normalizedRoleLedger(ledger)
    }

    private static func appendEvidencePoints(
        _ evidence: [SableLibraryShelfEvidencePoint],
        to ledger: inout SableLibraryShelfEvidenceRoleLedger
    ) {
        for point in evidence {
            let terms = point.matchedTerms
            switch point.source {
            case .title, .description, .volumeDescription, .specificSignal, .providerNeighbor:
                for term in terms {
                    appendRoleValue(term, defaultRole: .engine, to: &ledger)
                }
            case .genre:
                ledger.publicGenre.append(contentsOf: terms)
            case .theme, .tag:
                for term in terms {
                    appendRoleValue(term, defaultRole: .engine, to: &ledger)
                }
            case .safety:
                ledger.sensitiveReview.append(contentsOf: terms.isEmpty ? [point.note] : terms)
            }
        }
    }

    private static func appendRoleValue(
        _ value: String,
        defaultRole: SableLibraryShelfEvidenceRole,
        to ledger: inout SableLibraryShelfEvidenceRoleLedger
    ) {
        if evidenceEngineOverrideTerms.contains(where: { contains(value, term: $0) }) {
            ledger.engine.append(value)
            return
        }

        let classification = SableLibraryShelfTagClassifier.classify(
            SableLibraryShelfTagRecord(name: value)
        )
        switch classification.role {
        case .contentGenre:
            ledger.publicGenre.append(value)
        case .narrativeEngine, .subjectTheme:
            ledger.engine.append(value)
        case .settingFrame:
            ledger.setting.append(value)
        case .relationship, .characterOrSpecies, .audienceDemographic, .unknown:
            append(value, defaultRole: defaultRole, to: &ledger)
        case .bibliographicRelationship, .formOrCarrier, .productionStatus:
            ledger.formatFunction.append(value)
            ledger.ignoredForShelf.append(value)
        case .contentAdvisory:
            ledger.sensitiveReview.append(value)
        }
    }

    private static func append(
        _ value: String,
        defaultRole: SableLibraryShelfEvidenceRole,
        to ledger: inout SableLibraryShelfEvidenceRoleLedger
    ) {
        switch defaultRole {
        case .engine:
            ledger.engine.append(value)
        case .publicGenre:
            ledger.publicGenre.append(value)
        case .setting:
            ledger.setting.append(value)
        case .facet:
            ledger.facet.append(value)
        case .formatFunction:
            ledger.formatFunction.append(value)
        case .sensitiveReview:
            ledger.sensitiveReview.append(value)
        case .userPreference:
            ledger.userPreference.append(value)
        case .ignoredForShelf:
            ledger.ignoredForShelf.append(value)
        }
    }

    private static let evidenceEngineOverrideTerms = [
        "parody", "satire", "death game", "time loop", "time travel",
        "body swap", "body swapping", "battle royale", "survival",
        "psychological horror", "kingdom building", "crafting",
        "alchemy", "healing", "slow life"
    ]

    private static func normalizedRoleLedger(_ ledger: SableLibraryShelfEvidenceRoleLedger) -> SableLibraryShelfEvidenceRoleLedger {
        SableLibraryShelfEvidenceRoleLedger(
            engine: uniqueEvidenceRoleValues(ledger.engine),
            publicGenre: uniqueEvidenceRoleValues(ledger.publicGenre),
            setting: uniqueEvidenceRoleValues(ledger.setting),
            facet: uniqueEvidenceRoleValues(ledger.facet),
            formatFunction: uniqueEvidenceRoleValues(ledger.formatFunction),
            sensitiveReview: uniqueEvidenceRoleValues(ledger.sensitiveReview),
            userPreference: uniqueEvidenceRoleValues(ledger.userPreference),
            ignoredForShelf: uniqueEvidenceRoleValues(ledger.ignoredForShelf)
        )
    }

    private static let reviewRule = Rule(
        shelfCode: "00",
        subCode: "00.1",
        titleTerms: [],
        descriptionTerms: [],
        genreTerms: [],
        themeTerms: [],
        tagTerms: []
    )

    private static let rules: [Rule] = [
        Rule("21", "21.7",
             title: ["re:zero", "re zero"],
             description: ["return by death", "time loop", "die and try again", "repeated deaths", "repeated resets", "survival", "psychological horror", "psychological pressure"],
             genres: ["thriller", "psychological", "horror"],
             themes: ["isekai", "time loop", "time manipulation", "survival", "horror", "psychological horror"],
             tags: ["reincarnation", "summoned into another world"],
             specific: ["return by death", "time loop", "repeated deaths", "repeated resets", "psychological horror", "survival"],
             requiresIsekaiContext: true),
        Rule("21", "21.3",
             title: ["villainess", "otome", "dating sim", "world of otome games", "trapped in a dating sim", "canon fodder", "reincarnated mastermind", "regression", "regressor", "death flag", "doom flag", "bad ending"],
             description: ["villainess", "villainess noblewoman", "villainess daughter", "bad ending", "death flag", "doom flag", "condemned role", "canon fodder", "mob character", "extra in a novel", "extra in a game", "side character in a novel", "side character in a game", "inside a novel", "inside the novel", "inside a story", "inside the story", "inside a game", "inside the game", "game's world", "game world", "story world", "became the antagonist", "antagonist role", "shadowy antagonist", "story's shadowy antagonist", "mastermind behind", "canon role", "fated role", "time regression", "life regression", "regressor", "redo", "returned to the past", "return to the past", "second chance timeline", "back in time", "otome game", "dating sim", "game heroine", "capture target", "capture targets", "world of otome games", "engage in engagement"],
             genres: [],
             themes: ["villainess", "otome game", "dating sim", "fated engagement", "time regression", "life regression", "death flag", "doom flag", "canon fodder"],
             tags: ["villainess", "reincarnated as a villainess", "villainess arc", "time regression", "life regression", "otome game", "dating sim", "canon fodder", "death flag", "doom flag", "mob character", "capture targets"],
             specific: ["villainess", "villainess noblewoman", "villainess daughter", "otome game", "dating sim", "world of otome games", "game heroine", "capture target", "capture targets", "canon fodder", "mob character", "extra in a novel", "extra in a game", "bad ending", "death flag", "doom flag", "condemned role", "inside a novel", "inside the novel", "inside a story", "inside the story", "inside a game", "inside the game", "game's world", "game world", "story world", "became the antagonist", "antagonist role", "shadowy antagonist", "story's shadowy antagonist", "mastermind behind", "canon role", "fated role", "time regression", "life regression", "regressor", "redo", "returned to the past", "return to the past", "second chance timeline", "back in time", "reincarnated as a villainess"]),
        Rule("21", "21.5",
             title: ["spider", "so i'm a spider", "so i'm a spider so what", "so i'm a spider so what ex", "slime", "white cat's revenge", "dragon king's lap"],
             description: ["monster protagonist", "reincarnated as a monster", "non-human protagonist", "reborn as a spider", "reincarnated as a spider", "reincarnated as a slime", "reincarnated as a sword", "reincarnated as a dragon", "reincarnated as a cat", "transform into a white cat", "transforms into a white cat", "animal transformation", "cat transformation", "shapeshifting"],
             genres: [],
             themes: ["isekai", "monster pov", "monster protagonist", "non-human protagonist", "beast protagonist", "object protagonist", "animal transformation", "shapeshifting"],
             tags: ["reincarnated as a monster", "monster protagonist", "non-human protagonist", "object protagonist", "animal transformation", "shapeshifting"],
             specific: ["spider", "so i'm a spider", "so i'm a spider so what", "so i'm a spider so what ex", "slime", "monster protagonist", "non-human protagonist", "object protagonist", "animal transformation", "cat transformation", "shapeshifting", "reborn as a spider", "reincarnated as a spider", "reincarnated as a monster", "reincarnated as a slime", "reincarnated as a sword", "reincarnated as a dragon", "reincarnated as a cat", "transform into a white cat", "transforms into a white cat", "white cat", "dragon king's lap"],
             requiresIsekaiContext: true),
        Rule("21", "21.6",
             title: ["overlord", "no game no life", "vrmmo", "game", "starting on hard mode", "god levels got problems"],
             description: ["game system", "game world", "world of games", "decided by games", "virtual reality", "vrmmo", "mmo", "stats", "status screen", "skill tree", "god-tier stats", "god tier stats", "level up", "leveling", "level 2", "level 99", "ridiculous powers"],
             genres: [],
             themes: ["isekai", "vrmmo", "game world", "game system", "game elements", "stats", "leveling"],
             tags: ["game elements", "games", "stats", "leveling"],
             specific: ["game system", "game world", "world of games", "game elements", "stats", "status screen", "skill tree", "god-tier stats", "god tier stats", "level up", "leveling", "level 2", "level 99", "decided by games", "ridiculous powers"],
             requiresIsekaiContext: true),
        Rule("21", "21.2",
             title: ["bookworm", "dahlia", "crafting", "alchemist", "economics", "survival in another world", "easygoing territory defense", "production magic", "fortified city", "disowned but not disheartened"],
             description: ["books", "library", "writing", "invention", "invent magic tools", "magic tools", "craft", "crafting", "video game crafting", "commerce", "trade", "rebuilding civilization", "literacy", "printing", "world building", "worldbuilding", "character building", "base building", "settlement building", "village building", "territory defense", "territory development", "production magic", "prosperous city", "fortified city", "fortifications", "construction", "ballistae", "past-life knowledge", "past life knowledge", "memories of her previous life", "memories of his previous life", "minecraft", "harvest resources", "build whatever"],
             genres: [],
             themes: ["invention", "crafting", "economics", "knowledge", "working", "worldbuilding", "base building", "territory development", "production magic"],
             tags: ["merchant", "alchemy", "production magic", "crafting", "territory development", "invention", "magic tools"],
             specific: ["books", "library", "printing", "invention", "invent magic tools", "magic tools", "crafting", "video game crafting", "economics", "trade", "worldbuilding", "base building", "settlement building", "village building", "territory defense", "territory development", "production magic", "prosperous city", "fortified city", "fortifications", "construction", "ballistae", "past-life knowledge", "past life knowledge", "memories of her previous life", "memories of his previous life", "minecraft", "harvest resources", "build whatever"],
             requiresIsekaiContext: true),
        Rule("21", "21.8",
             title: ["campfire cooking", "cooking", "fluffy", "fluffy paradise", "weakest tamer", "killing slimes", "maxed out my level", "taking my reincarnation one step at a time", "no one told me there would be monsters", "maid", "all-works maid", "housekeeping", "household spells", "slow life", "restaurant", "diner", "cafe", "pizza parlor", "gourmet", "delicacies"],
             description: ["cooking", "cook", "food", "gourmet", "gourmet food", "order gourmet food", "delicacies", "restaurant", "diner", "cafe", "pizza parlor", "slow life", "heartwarming", "housekeeping", "household spells", "household magic", "domestic magic", "daily life", "relaxed life", "relaxed fantasy life", "leisurely", "easygoing life", "live leisurely", "low key life", "stress free", "pleasantly as possible", "world's most wonderful maid", "all-purpose maid", "cleaning", "serving", "diy", "level 99 cooking", "cuddle", "cuddling", "adored by all creatures", "all creatures", "fantasy animal", "animal cuddling", "pets", "animals", "tame", "tamer", "slime companion", "found family", "father figure", "mana deficit", "perpetual lack of energy", "monster hunter takes her in", "builds a new life"],
             genres: ["gourmet"],
             themes: ["isekai", "cooking", "food", "gourmet", "healing", "slow life", "domestic life", "domestic work", "maid", "found family"],
             tags: ["fluffy", "iyashikei", "found family", "slow life", "cooking", "food", "food and beverage", "gourmet", "maid", "maids", "restaurant", "animals", "pets"],
             specific: ["cooking", "cook", "food", "food and beverage", "gourmet", "gourmet food", "delicacies", "restaurant", "diner", "pizza parlor", "housekeeping", "household spells", "household magic", "daily life", "slow life", "healing", "cafe", "iyashikei", "relaxed life", "relaxed fantasy life", "leisurely", "easygoing life", "low key life", "stress free", "maid", "maids", "all-purpose maid", "cleaning", "serving", "diy", "fluffy", "fluffy paradise", "cuddle", "cuddling", "adored by all creatures", "fantasy animal", "animals", "pets", "tamer", "found family", "father figure", "slime companion", "mana deficit", "perpetual lack of energy", "monster hunter takes her in", "builds a new life"],
             requiresIsekaiContext: true),
        Rule("21", "21.4",
             title: ["royal", "noble", "duke", "duchess", "prince", "princess"],
             description: ["court", "nobility", "royalty", "duke", "duchess", "prince", "princess", "aristocracy"],
             genres: [],
             themes: ["nobility", "royalty", "court politics"],
             tags: ["engagement", "noblewoman"],
             specific: ["court", "nobility", "royalty", "duke", "duchess", "prince", "princess", "aristocracy", "palace"],
             requiresIsekaiContext: true),
        Rule("21", "21.9",
             title: ["tanya", "kingdom", "empire", "war"],
             description: ["kingdom", "war", "military", "strategy", "army", "empire"],
             genres: [],
             themes: ["isekai", "war", "military", "kingdom building", "strategy"],
             tags: ["war", "military", "kingdom building", "strategy", "army", "empire"],
             specific: ["kingdom building", "war", "military", "strategy", "army", "empire"],
             requiresIsekaiContext: true),
        Rule("21", "21.10",
             title: ["mushoku tensei", "jobless reincarnation", "in another world with my smartphone", "smartphone"],
             description: ["harem", "multiple wives", "polygamy", "wives", "fiancees", "fiancées", "married life", "wife-collection", "romantic accumulation"],
             genres: ["harem"],
             themes: ["isekai", "harem", "polygamy", "married life"],
             tags: ["harem", "polygamy", "multiple wives", "wife", "wives", "fiancees", "fiancées"],
             specific: ["harem", "multiple wives", "polygamy", "married life", "wife-collection", "romantic accumulation"],
             requiresIsekaiContext: true),
        Rule("21", "21.1",
             title: ["isekai", "isekai tensei", "recruited to another world", "summoned", "transported", "adventure", "hero", "demon lord", "world's least interesting master swordsman", "least interesting master swordsman", "world's strongest rearguard", "labyrinth country's novice seeker", "beginning after the end"],
             description: ["summoned into another world", "summoned to another world", "transported to another world", "reincarnated in another world", "reincarnated into another world", "reincarnated into a new world", "reincarnated into a fantasy world", "reborn into another world", "reborn in another world", "reborn into a fantasy world", "recruited to another world", "another world", "other world", "new world", "parallel world", "second life in another world", "second lifetime in another world", "quiet life learning", "quiet life", "go with the flow", "taking it easy", "deadly monsters", "fighting for his life", "monster fighting", "learn magic", "water magic", "quest", "journey", "adventure", "swords and sorcery", "swinging his sword", "sword training", "swordsmanship", "fighting style", "adventurer called a seeker", "job class called rearguard", "party support", "labyrinth country"],
             genres: ["adventure", "action", "fantasy"],
             themes: ["isekai", "reincarnation", "transmigration", "summoned into another world", "transported to another world", "travel", "quest", "hero", "magic", "quiet life", "martial arts"],
             tags: ["isekai", "reincarnation", "transmigration", "summoned into another world", "transported to another world", "adventurer", "questing", "martial arts", "swordplay", "swordsman"],
             specific: ["recruited to another world", "summoned into another world", "summoned to another world", "transported to another world", "reincarnated in another world", "quiet life learning", "go with the flow", "taking it easy", "deadly monsters", "fighting for his life", "monster fighting", "water magic", "quest", "journey", "adventure", "swords and sorcery", "demon lord", "adventurer", "seeker", "rearguard", "job class", "party support", "labyrinth country", "martial arts", "swordplay", "swordsman", "swinging his sword", "sword training", "swordsmanship", "fighting style"],
             requiresIsekaiContext: true,
             scoreMultiplier: 0.45),
        Rule("20", "20.7",
             title: ["wrong royal", "gag", "parody", "konosuba", "god's blessing on this wonderful world", "combatants will be dispatched", "eminence in shadow", "interspecies reviewers", "return of the corpse king"],
             description: ["gag-filled", "gag filled", "parody", "satire", "absurd", "ridiculous", "comedy-first", "comedy first", "chaotic comedy", "over-the-top", "over the top", "comic fantasy", "fantasy comedy", "fantasy sex comedy", "adult fantasy comedy", "sextravaganza", "sex shop", "sex shops", "sexy shops", "service review", "service reviews", "grade the services", "succubus establishments", "succubus joints", "comedic isekai", "parody isekai", "isekai parody", "hero parody", "villain organization parody", "evil organization", "combat agent", "misadventures", "craziness", "cringey secret", "cringe secret", "secret society", "founded helheim", "kazuma", "aqua", "megumin"],
             genres: [],
             themes: ["comedy", "gag", "parody", "satire"],
             tags: ["parody", "satire", "slapstick", "misfortune", "useless power"],
             specific: ["gag", "parody", "satire", "absurd", "ridiculous", "slapstick", "comedy-first", "comedy first", "chaotic comedy", "over-the-top", "over the top", "comic fantasy", "fantasy comedy", "fantasy sex comedy", "adult fantasy comedy", "sextravaganza", "sex shop", "sex shops", "sexy shops", "service review", "service reviews", "grade the services", "succubus establishments", "succubus joints", "interspecies reviewers", "comedic isekai", "parody isekai", "isekai parody", "hero parody", "villain organization parody", "evil organization", "combat agent", "combatants will be dispatched", "konosuba", "god's blessing on this wonderful world", "cringey secret", "cringe secret", "secret society", "founded helheim", "misadventures", "craziness", "kazuma", "aqua", "megumin", "misfortune", "useless power"]),
        Rule("20", "20.8",
             title: ["bladesmith", "blacksmith", "craft", "merchant", "healer", "apothecary"],
             description: ["blacksmith", "bladesmith", "smith", "forged", "forge", "weapon", "weapons", "enchanter", "enchanting", "craft", "crafting", "trade", "merchant", "business", "healer", "healing", "medicine", "clinic", "workshop", "artisan"],
             genres: [],
             themes: ["crafting", "trade", "working", "business", "alchemy", "healing", "medicine", "knowledge"],
             tags: ["blacksmiths", "magical weapons", "craft", "crafting", "merchant", "doctor", "healer", "healing", "medicine", "medical"],
             specific: ["blacksmith", "bladesmith", "smith", "forged", "forge", "magical weapons", "weapon master", "enchanter", "enchanting", "craft", "crafting", "trade", "merchant", "business", "healer", "healing", "medicine", "clinic", "workshop", "artisan"],
             excludesIsekaiContext: true),
        Rule("10", "10.1",
             title: ["martial arts", "swordplay", "swordsman", "sword master", "blade master"],
             description: ["martial arts", "swordplay", "swordsman", "sword master", "sword training", "swordsmanship", "duel", "duels", "fighting style", "combat training"],
             genres: ["martial arts"],
             themes: ["martial arts", "combat"],
             tags: ["martial arts", "swordplay", "swordsman", "duels", "combat"],
             specific: ["martial arts", "swordplay", "swordsman", "sword master", "sword training", "swordsmanship", "duel", "duels", "fighting style", "combat training"],
             excludesIsekaiContext: true),
        Rule("10", "10.2",
             title: ["kino's journey", "beautiful world", "journey", "traveler", "traveller"],
             description: ["journey", "journeys", "travel", "travels", "traveler", "traveller", "quest", "adventure", "wilderness"],
             genres: ["adventure"],
             themes: ["travel", "journey", "quest", "adventure"],
             tags: ["travel", "journey", "quest", "adventure"],
             specific: ["journey", "journeys", "travel", "travels", "traveler", "traveller", "quest", "adventure", "wilderness"],
             excludesIsekaiContext: true),
        Rule("10", "10.4",
             title: ["sentenced to be a hero", "penal hero", "eighty-six", "eighty six"],
             description: ["war", "bloodless war", "army", "soldiers", "front lines", "front line", "penal hero unit", "military unit"],
             genres: [],
             themes: ["war", "military"],
             tags: ["war", "wars", "military", "soldiers", "army", "prison", "anti-hero"],
             specific: ["war", "bloodless war", "army", "soldiers", "front lines", "front line", "penal hero unit", "military unit", "prison records"]),
        Rule("60", "60.1",
             title: ["science fiction", "sci-fi", "sci fi", "speculative world", "beacon of light in the dark sea"],
             description: ["science fiction", "sci-fi", "sci fi", "futuristic", "near future", "cyber", "android", "artificial intelligence", "outer space", "space station", "space travel", "spaceship", "alien planet", "technology", "underwater station", "undersea station", "research station", "scientists and engineers", "scientists", "engineers", "deep sea", "possible settlement", "human race"],
             genres: ["sci-fi", "sci fi", "science fiction"],
             themes: ["futuristic", "artificial intelligence", "technology", "research station", "undersea"],
             tags: ["sci-fi", "sci fi", "science fiction", "artificial intelligence", "androids", "technology", "scientists", "engineers"],
             specific: ["science fiction", "sci-fi", "sci fi", "futuristic", "near future", "cyber", "android", "artificial intelligence", "outer space", "space station", "space travel", "spaceship", "alien planet", "technology", "underwater station", "undersea station", "research station", "scientists and engineers", "deep sea", "possible settlement", "human race"]),
        Rule("60", "60.2",
             title: ["86", "86--eighty-six", "86-eighty-six", "eighty-six", "eighty six"],
             description: ["unmanned drones", "autonomous drones", "drones", "mecha", "robots", "military", "war", "army", "soldiers", "futuristic", "dystopian"],
             genres: ["mecha"],
             themes: ["military", "war", "mecha", "robots", "artificial intelligence", "dystopian"],
             tags: ["military", "war", "wars", "robots", "mecha", "artificial intelligence", "soldiers", "dystopian", "guns", "sci fi"],
             specific: ["unmanned drones", "autonomous drones", "drones", "mecha", "robots", "military", "war", "soldiers", "artificial intelligence", "dystopian"]),
        Rule("60", "60.4",
             title: ["sword art online", "vrmmo"],
             description: ["virtual reality", "vrmmo", "mmo", "online game", "trapped in a game", "death game"],
             genres: ["sci-fi", "sci fi"],
             themes: ["vrmmo", "game world", "virtual reality"],
             tags: ["vrmmo", "virtual reality", "game world", "online game"],
             specific: ["sword art online", "virtual reality", "vrmmo", "online game", "trapped in a game", "death game"]),
        Rule("60", "60.7",
             title: ["a certain magical index", "magical index"],
             description: ["academy city", "scientific marvel", "superhuman abilities", "paranormal talent", "level zero", "anti-magic", "sorcerers", "futuristic city"],
             genres: ["sci-fi", "sci fi", "supernatural"],
             themes: ["esp", "super powers", "special abilities", "magic", "science"],
             tags: ["esp", "super powers", "superpowers", "special abilities", "anti-magic", "scientists", "experiments", "futuristic city", "clones"],
             specific: ["academy city", "scientific marvel", "superhuman abilities", "paranormal talent", "level zero", "anti-magic", "sorcerers", "futuristic city", "esp"]),
        Rule("20", "20.4",
             title: ["adventurer", "guild", "dungeon", "bladesmith", "weapon master", "blade & bastard", "blade and bastard"],
             description: ["adventurer", "guild", "dungeon", "quest", "journey", "blacksmith", "bladesmith", "weapon master"],
             genres: [],
             themes: ["dungeon", "guild", "adventurer"],
             tags: ["adventurer", "guilds", "dungeon diving", "blacksmiths", "magical weapons", "zero to hero"],
             specific: ["adventurer", "guild", "guilds", "dungeon", "dungeon diving", "blacksmith", "bladesmith", "magical weapons", "weapon master"],
             excludesIsekaiContext: true),
        Rule("20", "20.1",
             title: ["silent witch", "witch", "sorcerer", "mage", "attack magic"],
             description: ["magic", "witch", "mage", "sorcery", "spell", "magic training", "voiceless magic", "academy of magic", "magic academy", "attack magic", "mana"],
             genres: [],
             themes: ["magic", "witch", "magic school"],
             tags: ["academy"],
             specific: ["magic", "witch", "mage", "sorcery", "spell", "magic school", "academy of magic", "magic academy", "voiceless magic", "attack magic", "mana"],
             excludesIsekaiContext: true),
        Rule("20", "20.2",
             title: ["folklore", "spirit", "spirits", "yokai", "youkai", "shrine", "god", "gods", "deity"],
             description: ["folklore", "folklore studies", "myth", "mythology", "legend", "urban legend", "spirits", "spirit realm", "yokai", "youkai", "shrine", "god", "gods", "goddess", "deity", "guardian spirit", "kami", "kokkuri"],
             genres: ["supernatural"],
             themes: ["folklore", "mythology", "spirits", "youkai", "yokai", "gods"],
             tags: ["japanese folklore", "folklore", "youkai", "yokai", "spirits", "guardian spirits", "gods", "goddess"],
             specific: ["folklore", "folklore studies", "myth", "mythology", "urban legend", "spirit realm", "yokai", "youkai", "guardian spirit", "kami", "kokkuri"],
             excludesIsekaiContext: true),
        Rule("20", "20.3",
             title: ["ghost", "specter", "spectre", "vampire", "supernatural"],
             description: ["ghost", "specter", "spectre", "vampire", "supernatural being", "paranormal life", "haunted", "spirit roommate", "exorcist", "exorcism", "curse", "curses"],
             genres: ["supernatural"],
             themes: ["supernatural", "paranormal", "ghost", "vampire"],
             tags: ["ghosts", "spirits", "vampires", "paranormal", "supernatural", "exorcists"],
             specific: ["ghost", "specter", "spectre", "vampire", "supernatural being", "paranormal life", "haunted", "spirit roommate", "exorcist", "exorcism"],
             excludesIsekaiContext: true),
        Rule("20", "20.5",
             title: ["demon lord", "demon king", "demon", "orc", "monster"],
             description: ["demon lord", "demon king", "demon", "monster", "non-human race", "nonhuman race", "orc", "beastman", "beastmen"],
             genres: [],
             themes: ["demons", "monsters", "non-human"],
             tags: ["demons", "demon lord", "demon king", "monsters", "orcs", "beastmen", "non-human"],
             specific: ["demon lord", "demon king", "demon", "monster", "non-human race", "nonhuman race", "orc", "beastman", "beastmen"],
             excludesIsekaiContext: true),
        Rule("20", "20.6",
             title: ["cultivation", "xianxia", "wuxia", "murim"],
             description: ["cultivation", "cultivator", "xianxia", "wuxia", "murim", "martial immortal", "sect", "jianghu", "qi", "dao", "sword cultivation", "martial arts world", "immortal master"],
             genres: [],
             themes: ["cultivation", "xianxia", "wuxia", "martial arts"],
             tags: ["cultivation", "cultivators", "xianxia", "wuxia", "murim", "sects", "martial arts", "qi", "dao"],
             specific: ["cultivation", "cultivator", "xianxia", "wuxia", "murim", "martial immortal", "sect", "jianghu", "sword cultivation", "immortal master"]),
        Rule("20", "20.9",
             title: ["urban fantasy", "paranormal"],
             description: ["urban fantasy", "paranormal", "supernatural", "youkai", "exorcism", "spirits", "vampire"],
             genres: ["supernatural"],
             themes: ["urban fantasy", "paranormal", "vampire", "youkai", "spirits"],
             tags: ["urban fantasy", "paranormal", "youkai", "exorcists", "spirits", "vampires"],
             specific: ["urban fantasy", "paranormal", "youkai", "exorcism", "spirits", "vampire"]),
        Rule("30", "30.7",
             title: ["harem", "reverse harem"],
             description: ["harem", "reverse harem", "romantic chaos", "multiple love interests", "many suitors", "many admirers", "competing suitors"],
             genres: ["harem"],
             themes: ["harem", "reverse harem", "romantic rivalry"],
             tags: ["harem", "reverse harem", "multiple love interests", "love rivals"],
             specific: ["harem", "reverse harem", "romantic chaos", "multiple love interests", "many suitors", "competing suitors"],
             excludesIsekaiContext: true),
        Rule("30", "30.1",
             title: ["high school", "college", "neighbor", "neighbour", "glow up", "glow-up", "pupposites attract"],
             description: ["modern", "contemporary", "high school", "college", "classmate", "neighbor", "neighbour", "first love", "romance", "crush", "crushes", "dating", "dog lovers", "chance meetings", "unlikely friendship", "feel-good romance", "park"],
             genres: ["romance"],
             themes: ["contemporary romance", "school romance", "school life"],
             tags: ["school life", "high school", "college", "classmates", "neighbors", "neighbours", "modern day", "heterosexual"],
             specific: ["modern", "contemporary", "school romance", "school life", "high school", "college", "classmates", "neighbors", "neighbours", "crush", "crushes", "dating", "dog lovers", "chance meetings", "unlikely friendship", "feel-good romance", "park"],
             excludesIsekaiContext: true),
        Rule("40", "40.2",
             title: ["high school", "academy"],
             description: ["school life", "high school", "classmates", "student", "students"],
             genres: ["school_life", "slice of life"],
             themes: ["school life"],
             tags: ["high school", "school life", "high school students", "classmates", "college"],
             specific: ["high school", "school life", "students", "classmates", "college"],
             excludesIsekaiContext: true,
             scoreMultiplier: 0.7),
        Rule("40", "40.1",
             title: ["daily life", "everyday", "ordinary days", "dragon daddy diaries"],
             description: ["daily life", "everyday life", "ordinary days", "quiet life", "slice of life", "healing", "childcare", "parenthood", "family life", "found family", "heartwarming"],
             genres: ["slice of life"],
             themes: ["daily life", "slice of life", "iyashikei", "healing", "found family"],
             tags: ["daily life", "slice of life", "iyashikei", "healing", "found family"],
             specific: ["daily life", "everyday life", "ordinary days", "quiet life", "slice of life", "healing", "childcare", "parenthood", "family life", "found family", "heartwarming", "dragon daddy"],
             excludesIsekaiContext: true),
        Rule("40", "40.4",
             title: ["cooking", "restaurant", "diner", "cafe", "gourmet"],
             description: ["cooking", "cook", "food", "gourmet", "restaurant", "diner", "cafe", "food and beverage", "delicacies", "level 99 cooking"],
             genres: ["gourmet"],
             themes: ["cooking", "food", "gourmet"],
             tags: ["cooking", "food", "food and beverage", "gourmet", "restaurant", "diner", "cafe"],
             specific: ["cooking", "cook", "food", "food and beverage", "gourmet", "restaurant", "diner", "cafe", "delicacies", "level 99 cooking"],
             excludesIsekaiContext: true),
        Rule("40", "40.6",
             title: ["slow life", "rural life", "living in the mountains", "countryside", "hero's party", "quiet life in the countryside"],
             description: ["slow life", "rural life", "countryside", "frontier", "mountain", "mountains", "quiet life", "easy life", "simple life", "recluse", "burnout", "healing", "heartwarming", "leisurely", "opening a pharmacy", "open an apothecary"],
             genres: ["slice of life"],
             themes: ["slow life", "rural life", "healing", "iyashikei"],
             tags: ["slow life", "countryside", "rural", "healing", "iyashikei", "lighthearted"],
             specific: ["slow life", "rural life", "countryside", "frontier", "mountain", "mountains", "quiet life", "easy life", "simple life", "recluse", "burnout", "healing", "heartwarming", "leisurely", "opening a pharmacy", "open an apothecary"],
             excludesIsekaiContext: true),
        Rule("40", "40.3",
             title: ["workplace", "office", "yakuza", "idol"],
             description: ["work", "workplace", "career", "office", "showbiz", "idol", "entertainment industry", "yakuza"],
             genres: ["slice of life"],
             themes: ["working", "workplace", "idols", "fandom", "organized crime"],
             tags: ["working", "work", "showbiz", "idol", "idols", "entertainment industry", "yakuza", "kpop", "fans", "otaku culture"],
             specific: ["work", "workplace", "career", "showbiz", "idol", "idols", "entertainment industry", "yakuza", "kpop", "fans"],
             excludesIsekaiContext: true),
        Rule("40", "40.9",
             title: ["life lessons", "gag", "parody"],
             description: ["gag", "satire", "black humor", "black comedy", "dark comedy", "comedy"],
             genres: ["comedy", "slice of life"],
             themes: ["comedy", "gag", "satire"],
             tags: ["gag humor", "satire", "black humor", "dark comedy", "parody"],
             specific: ["gag", "gag humor", "satire", "black humor", "black comedy", "dark comedy", "parody"],
             excludesIsekaiContext: true),
        Rule("70", "70.8",
             title: ["apothecary", "pharmacist", "herbalist"],
             description: ["rear palace", "medicine", "apothecary", "pharmacist", "herbalist", "consort", "emperor", "court work"],
             genres: ["historical", "mystery"],
             themes: ["medicine", "investigation", "court", "working"],
             tags: ["doctor", "herbalist", "palace"],
             specific: ["rear palace", "medicine", "apothecary", "pharmacist", "herbalist", "consort", "court work"]),
        Rule("80", "80.4",
             title: ["stranger things", "a whole new world", "as old as time", "conceal, don't feel", "mirror, mirror", "unbirthday"],
             description: ["official script", "retelling", "adaptation", "franchise"],
             genres: [],
             themes: ["adaptation", "scripts"],
             tags: ["franchise"],
             specific: ["official script", "retelling", "adaptation", "franchise"]),
        Rule("80", "80.1",
             title: ["jane eyre", "pride and prejudice", "wuthering heights", "dracula", "crime and punishment", "great gatsby"],
             description: ["classic"],
             genres: ["classic", "literary fiction"],
             themes: ["classic"],
             tags: [],
             specific: ["classic", "literary fiction"]),
        Rule("34", "34.3",
             title: ["omegaverse", "my neighbour is an omega", "my neighbor is an omega", "omega", "alpha omega"],
             description: ["omegaverse", "omega", "alpha", "mate bond", "rut", "dominance", "submission", "dom/sub", "nameverse", "guideverse"],
             genres: ["omegaverse"],
             themes: ["omegaverse", "omega", "alpha", "dom/sub"],
             tags: [],
             specific: ["omegaverse", "omega", "alpha", "mate bond", "rut", "dom/sub", "nameverse", "guideverse"],
             requiresPublicIdentity: true),
        Rule("34", "34.2",
             title: ["yuri", "girls love", "shoujo ai", "shoujo-ai", "lesbian romance", "i'm in love with the villainess", "im in love with the villainess"],
             description: ["girls love", "yuri", "sapphic romance", "lesbian romance", "queer girls' love", "in love with the villainess", "pursues the villainess", "falls for the villainess"],
             genres: ["girls love", "yuri", "shoujo ai", "gl"],
             themes: ["girls love", "yuri", "queer", "shoujo ai", "sapphic romance", "lesbian romance", "gl"],
             tags: [],
             specific: ["girls love", "yuri", "shoujo ai", "sapphic romance", "lesbian romance", "queer girls love", "pursues the villainess", "gl"],
             requiresPublicIdentity: true),
        Rule("34", "34.1",
             title: ["boys love", "yaoi", "shounen ai", "shounen-ai", "hitorijime", "given", "you can have my back"],
             description: ["boys love", "yaoi", "m/m romance", "gay romance", "shounen ai", "male x male", "danmei", "feelings begin to bloom", "draw them closer", "bond grows", "their bond grows", "love story"],
             genres: ["boys love", "yaoi", "shounen ai", "danmei", "bl"],
             themes: ["boys love", "yaoi", "gay romance", "m/m romance", "shounen ai", "danmei", "bl"],
             tags: [],
             specific: ["boys love", "yaoi", "m/m romance", "gay romance", "shounen ai", "male x male", "danmei", "bl"],
             requiresPublicIdentity: true),
        Rule("30", "30.9",
             title: ["hockey"],
             description: ["hockey", "sports romance"],
             genres: ["sports romance"],
             themes: ["sports romance"],
             tags: ["sports"],
             specific: ["hockey", "sports romance", "sports"]),
        Rule("30", "30.2",
             title: ["bridgerton", "regency", "loyal soldier lustful beast"],
             description: ["regency", "historical romance", "england", "soldier", "knight", "historical romance"],
             genres: ["historical romance"],
             themes: ["historical romance"],
             tags: ["regency"],
             specific: ["regency", "historical romance", "england", "soldier", "knight"]),
        Rule("30", "30.3",
             title: ["bride", "groom", "fiance", "fiancee", "fiancée", "betrothed", "marielle clarac", "safe & sound in the arms of an elite knight", "villainess for the tyrant"],
             description: ["love story", "falls in love", "falling in love", "in love", "romance", "romantic", "marriage", "marriage proposal", "arranged marriage", "contract marriage", "engagement", "betrothed", "bride", "groom", "fiance", "fiancee", "fiancée", "fiancé", "wedding", "courtship", "lovey-dovey", "romance novelist", "whisks her away", "sanctuary", "dashing knight", "elite knight", "tyrant"],
             genres: ["fantasy romance"],
             themes: ["fantasy romance", "marriage", "engagement"],
             tags: ["fantasy romance"],
             specific: ["fantasy romance", "love story", "falls in love", "falling in love", "arranged marriage", "contract marriage", "engagement", "marriage", "marriage proposal", "bride", "groom", "betrothed", "fiance", "fiancee", "fiancée", "fiancé", "wedding", "courtship", "lovey-dovey", "romance novelist", "whisks her away", "sanctuary", "dashing knight", "elite knight", "tyrant"],
             requiresRomanceEngineWhenIsekai: true),
        Rule("50", "50.1",
             title: ["detective", "investigation"],
             description: ["detective", "investigation", "mystery", "poison"],
             genres: ["mystery"],
             themes: ["investigation", "medical mystery"],
             tags: ["detective"],
             specific: ["detective", "investigation", "mystery", "poison", "medical mystery"]),
        Rule("50", "50.4",
             title: ["rascal does not dream", "conjecture", "case files"],
             description: ["mysterious maladies", "supernatural in origin", "case files", "mystery", "vampire", "monster", "no one else can see", "investigation", "folklore studies", "urban legend", "haunted", "curse", "spirit realm", "strange festival"],
             genres: ["mystery", "supernatural", "psychological"],
             themes: ["vampire", "school", "supernatural", "folklore", "urban legend"],
             tags: ["mysterious elements", "urban fantasy", "vampires", "time manipulation", "psychological", "folklore"],
             specific: ["mysterious maladies", "supernatural in origin", "case files", "folklore studies", "urban legend", "haunted", "curse", "spirit realm", "strange festival", "mysterious elements", "urban fantasy"]),
        Rule("50", "50.5",
             title: ["death game", "death games", "playing death games", "earth's chosen savior"],
             description: ["death game", "death games", "play or die", "high stakes games", "locked rooms", "weapons", "battle royale", "destroy earth", "saving earth", "monsters invading through gateways", "gateway invasion", "alien world", "survival stage", "cult madness", "chaos"],
             genres: ["thriller", "suspense", "mystery"],
             themes: ["death game", "apocalypse", "survival"],
             tags: ["death game", "death games", "play or die", "high stakes games", "high stakes game", "battle royale"],
             specific: ["death game", "death games", "play or die", "high stakes games", "high stakes game", "locked rooms", "battle royale", "destroy earth", "saving earth", "monsters invading through gateways", "gateway invasion", "alien world", "survival stage", "cult madness", "chaos"]),
        Rule("50", "50.6",
             title: ["vampire", "horror"],
             description: ["vampire", "horror", "monster", "body horror"],
             genres: ["horror"],
             themes: ["vampire", "monster"],
             tags: ["body horror"],
             specific: ["vampire", "horror", "monster", "body horror"]),
        Rule("50", "50.8",
             title: ["spy", "spies", "spy classroom", "agent", "undercover", "sister mafioso", "mafioso"],
             description: ["spy", "spies", "espionage", "intelligence agency", "covert mission", "secret mission", "infiltration", "sabotage", "counterintelligence", "deception", "undercover", "handler", "secret agent", "intelligence agent", "spy school", "spy team", "heist", "heists", "con", "cons", "mafia", "mafioso", "crime family", "organized crime", "don", "mobster"],
             genres: [],
             themes: ["espionage", "spy", "spies", "heist", "organized crime"],
             tags: ["spy", "spies", "espionage", "covert mission", "secret mission", "infiltration", "sabotage", "undercover", "agents", "heist", "heists", "cons", "organized crime", "mafia"],
             specific: ["spy", "spies", "espionage", "intelligence agency", "covert mission", "secret mission", "infiltration", "sabotage", "counterintelligence", "deception", "undercover", "handler", "secret agent", "intelligence agent", "spy school", "spy team", "heist", "heists", "con", "cons", "mafia", "mafioso", "crime family", "organized crime", "don", "mobster"]),
        Rule("90", "90.9",
             title: ["surrounded by idiots", "surrounded by narcissists", "how to piss off men"],
             description: ["self-help", "psychology", "society"],
             genres: ["nonfiction"],
             themes: ["psychology", "society"],
             tags: ["self-help"],
             specific: ["self-help", "psychology", "society", "narcissists"])
    ]

    private static func promotePublicIdentityCandidateIfNeeded(in candidates: inout [CandidateScore]) {
        guard let currentTop = candidates.first,
              currentTop.rule.shelfCode != "34",
              let identityIndex = candidates.firstIndex(where: { candidate in
                  candidate.rule.shelfCode == "34"
                      && (candidate.hasPublicIdentityCatalogSupport || candidate.hasPublicIdentityNarrativeSupport)
              }) else {
            return
        }

        let identityCandidate = candidates[identityIndex]
        guard identityCandidate.totalScore >= max(10, currentTop.totalScore * 0.62) else {
            return
        }

        candidates.remove(at: identityIndex)
        candidates.insert(identityCandidate, at: 0)
    }

    private static func decisionActionability(
        for input: SableLibraryShelfCatalogInput,
        suggestion: SableLibraryShelfSuggestion
    ) -> SableLibraryShelfDecisionActionability {
        let sources = Set(suggestion.evidence.map(\.source))
        let hasNoDescription = inputHasNoDescription(input)
        let hasOnlyGenericTaxonomy = !sources.isEmpty && sources.isSubset(of: [.genre, .tag, .safety])
        let hasEngineOrPublicGenreRole = !suggestion.evidenceRoles.engineEvidence.isEmpty
        let hasOnlySupportRole = suggestion.evidenceRoles.engineEvidence.isEmpty
            && !suggestion.evidenceRoles.supportOnlyEvidence.isEmpty
        let hasNarrativeEvidence = !sources.isDisjoint(with: [.title, .description, .volumeDescription])
        let hasCatalogEvidence = !sources.isDisjoint(with: [.genre, .theme, .tag])
        let hasSpecificEvidence = sources.contains(.specificSignal)
        let isReviewRow = [.low, .needsReview].contains(suggestion.confidenceLevel)

        if isParentInheritanceCandidate(input) {
            return .parentInheritanceCandidate
        }
        if suggestion.shelf.code == "00" || hasNoDescription || hasOnlyGenericTaxonomy || hasOnlySupportRole {
            return .evidenceProblem
        }
        if suggestion.warnings.contains(where: isHighSensitivityWarning) {
            return .manualPreference
        }
        if suggestion.warnings.contains(where: isCloseShelfWarning) {
            return .legitimateAmbiguity
        }
        if isReviewRow,
           hasEngineOrPublicGenreRole,
           hasNarrativeEvidence,
           hasCatalogEvidence,
           hasSpecificEvidence {
            return .possibleRuleProblem
        }
        if isReviewRow {
            return .evidenceProblem
        }
        return .goodEvidence
    }

    private static func ledgerEvidence(from suggestion: SableLibraryShelfSuggestion) -> [String] {
        let evidence = suggestion.evidence
            .filter { $0.source != .safety }
            .prefix(5)
            .map { point in
                let terms = point.matchedTerms.prefix(5).joined(separator: ", ")
                if terms.isEmpty {
                    return point.source.displayName
                }
                return "\(point.source.displayName): \(terms)"
            }
        if !evidence.isEmpty {
            return Array(evidence)
        }
        return ["No reliable aboutness evidence was strong enough."]
    }

    private static func ledgerCompetitionReasons(for suggestion: SableLibraryShelfSuggestion) -> [String] {
        guard !suggestion.alternatives.isEmpty else {
            return ["No stronger competing shelf appeared."]
        }
        let specificEvidence = suggestion.evidence
            .first { $0.source == .specificSignal }?
            .matchedTerms
            .prefix(3)
            .joined(separator: ", ")

        return suggestion.alternatives.prefix(3).map { alternative in
            if suggestion.shelf.code == "21", alternative.shelf.code != "21" {
                return "Isekai context keeps this near \(suggestion.subShelf.displayName) unless \(alternative.subShelf.displayName) has the stronger story engine."
            }
            if suggestion.shelf.code == "34", alternative.shelf.code != "34" {
                return "Public BL/GL/queer relationship evidence outranks \(alternative.subShelf.displayName) when the relationship is the story engine."
            }
            if broadFallbackSubShelfCodes.contains(alternative.subShelf.code),
               !broadFallbackSubShelfCodes.contains(suggestion.subShelf.code) {
                return "Specific shelf evidence beats the broader fallback \(alternative.subShelf.displayName)."
            }
            if let specificEvidence, !specificEvidence.isEmpty {
                return "\(suggestion.subShelf.displayName) has specific clues (\(specificEvidence)); \(alternative.subShelf.displayName) stays as an alternative."
            }
            return "\(alternative.subShelf.displayName) scored lower than the selected shelf and stays available for review."
        }
    }

    private static func ledgerNeededEvidence(
        for input: SableLibraryShelfCatalogInput,
        suggestion: SableLibraryShelfSuggestion,
        actionability: SableLibraryShelfDecisionActionability
    ) -> [String] {
        var needed: [String] = []
        if inputHasNoDescription(input) {
            needed.append("series or volume description")
        }
        if suggestion.confidenceLevel != .high {
            if suggestion.evidenceRoles.engine.isEmpty {
                needed.append("clear story-engine evidence")
            }
            if input.volumeDescriptions.isEmpty {
                needed.append("series-wide volume descriptions")
            }
            if input.tagRecords.isEmpty {
                needed.append("provider tag paths and weights")
            }
            if input.genres.isEmpty || input.themes.isEmpty {
                needed.append("provider genres and themes")
            } else {
                needed.append("cross-provider genre/theme agreement")
            }
        }
        if suggestion.warnings.contains(where: isCloseShelfWarning),
           let alternative = suggestion.alternatives.first {
            needed.append("clearer evidence separating \(suggestion.subShelf.displayName) from \(alternative.subShelf.displayName)")
        }
        if actionability == .manualPreference {
            needed.append("manual check for sensitive or user-controlled metadata")
        }
        if actionability == .parentInheritanceCandidate {
            needed.append("parent-series shelf or prior decision")
        }
        if actionability == .possibleRuleProblem {
            needed.append("human case review before changing shelf rules")
        }
        return uniqueLedgerStrings(needed)
    }

    private static func inputHasNoDescription(_ input: SableLibraryShelfCatalogInput) -> Bool {
        (input.description?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            && input.volumeDescriptions.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private static func isParentInheritanceCandidate(_ input: SableLibraryShelfCatalogInput) -> Bool {
        let text = normalize(
            [
                input.title,
                input.description ?? "",
                input.genres.joined(separator: " "),
                input.themes.joined(separator: " "),
                input.tags.joined(separator: " ")
            ].joined(separator: " ")
        )
        guard !text.isEmpty else { return false }
        return parentInheritanceTerms.contains { containsNormalized(text, term: normalize($0)) }
    }

    private static func isCloseShelfWarning(_ warning: String) -> Bool {
        warning.localizedCaseInsensitiveContains("Two shelves are close")
    }

    private static func isHighSensitivityWarning(_ warning: String) -> Bool {
        warning.localizedCaseInsensitiveContains("Content-sensitive metadata")
    }

    private static let broadFallbackSubShelfCodes: Set<String> = [
        "21.1", "20.1", "10.2", "30.1", "60.1"
    ]

    private static let parentInheritanceTerms = [
        "side story", "side stories", "short story", "short stories",
        "short story collection", "after story", "after stories",
        "spin off", "spin-off", "spinoff", "redundant", "recollection",
        "recollections", "bonus story", "bonus stories", "extra edition",
        "extras", "gaiden"
    ]

    private static func uniqueLedgerStrings(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values {
            let key = normalize(value)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            result.append(value)
        }
        return result
    }

    private static func uniqueTagRecords(_ records: [SableLibraryShelfTagRecord]) -> [SableLibraryShelfTagRecord] {
        var seen: Set<String> = []
        var result: [SableLibraryShelfTagRecord] = []
        for record in records {
            let key = [
                normalize(record.name),
                normalize(record.path ?? "")
            ].joined(separator: "|")
            guard !key.trimmingCharacters(in: CharacterSet(charactersIn: "|")).isEmpty,
                  seen.insert(key).inserted else {
                continue
            }
            result.append(record)
        }
        return result
    }

    private static func facets(for input: SableLibraryShelfCatalogInput, text: EvidenceText) -> [String] {
        let facetTerms = [
            "male protagonist", "female protagonist", "strong female lead",
            "reincarnation", "summoned", "transmigration", "romance subplot",
            "lgbtq+", "yuri", "boys love", "harem", "polygamy", "multiple wives", "content warning"
        ]
        let allText = ShelfSearchText([
            text.title.normalized,
            text.description.normalized,
            text.volumeDescriptions.normalized,
            text.genres.normalized,
            text.themes.normalized,
            text.facetTags.normalized,
            text.reviewTags.normalized,
            text.contentWarnings.normalized
        ].joined(separator: " "))
        return facetTerms.filter { term in
            guard let shelfTerm = ShelfTerm(term) else { return false }
            return allText.contains(shelfTerm)
        }
    }

    private static func reviewWarnings(for input: SableLibraryShelfCatalogInput, text: EvidenceText) -> [String] {
        var warnings: [String] = []
        if (input.description?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            && input.volumeDescriptions.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            warnings.append("No description was available, so title and provider tags may be overrepresented.")
        }
        let advisoryValues = input.contentWarnings + [text.contentWarnings.normalized, text.reviewTags.normalized]
        if hasHighSensitivityReviewWarning(in: advisoryValues) {
            warnings.append("Content-sensitive metadata should stay reviewable and user-controlled.")
        } else if hasContentAdvisoryWarning(in: advisoryValues) {
            warnings.append("Adult-content metadata stays visible as a facet and does not decide the shelf by itself.")
        }
        if !text.reviewTags.normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            warnings.append("Provider adult/content-review tags stay visible as facets.")
        }
        return warnings
    }

    private static func confidenceScore(
        for top: CandidateScore,
        runnerUp: CandidateScore?,
        evidenceRoles: SableLibraryShelfEvidenceRoleLedger,
        warnings: inout [String]
    ) -> (value: Double, level: SableLibraryShelfConfidenceLevel) {
        let aboutnessSources = top.sources.subtracting([.safety])
        let independentSources = aboutnessSources.subtracting([.specificSignal])
        let sourceCount = Double(independentSources.count)
        let evidenceStrength = min(top.totalScore / 18, 1)
        let sourceAgreement = min(sourceCount / 3, 1)
        let runnerScore = runnerUp?.totalScore ?? 0
        let margin = top.totalScore > 0 ? max(0, (top.totalScore - runnerScore) / top.totalScore) : 0
        let hasNarrativeTextSupport = !independentSources.isDisjoint(with: [.title, .description, .volumeDescription])
        let hasCatalogingSupport = !independentSources.isDisjoint(with: [.genre, .theme])
        let hasProviderTaxonomyAgreement = independentSources.contains(.genre) && independentSources.contains(.theme)
        let hasSpecificSignal = aboutnessSources.contains(.specificSignal)
        let hasPublicIdentityCatalogSupport = top.hasPublicIdentityCatalogSupport
        let hasPublicIdentityNarrativeSupport = top.hasPublicIdentityNarrativeSupport
        let hasEngineOrPublicGenreRole = !evidenceRoles.engineEvidence.isEmpty
        let hasSupportOnlyRole = evidenceRoles.engineEvidence.isEmpty
            && !evidenceRoles.supportOnlyEvidence.isEmpty
        var value = (0.50 * evidenceStrength) + (0.30 * sourceAgreement) + (0.20 * margin)

        if hasNarrativeTextSupport && hasCatalogingSupport {
            value += 0.08
        } else if hasProviderTaxonomyAgreement {
            value += 0.06
        } else if sourceCount >= 3 {
            value += 0.04
        }
        if hasSpecificSignal {
            value += hasNarrativeTextSupport && hasCatalogingSupport ? 0.10 : 0.07
        }
        if hasPublicIdentityCatalogSupport {
            value += hasNarrativeTextSupport ? 0.08 : 0.06
        } else if hasPublicIdentityNarrativeSupport {
            value += 0.05
        }

        if aboutnessSources == [.tag] {
            value = min(value, 0.42)
            warnings.append("Only tag evidence matched; tags alone are not enough for confident shelving.")
        }
        if hasSupportOnlyRole {
            value = min(value, 0.56)
            warnings.append("Only setting, facet, format, or review clues were available; these can support a shelf but should not decide it alone.")
        }
        if !hasEngineOrPublicGenreRole {
            value = min(value, 0.68)
        }
        if top.rule.requiresPublicIdentity,
           aboutnessSources.isDisjoint(with: [.title, .description, .volumeDescription, .genre, .theme]) {
            value = min(value, 0.5)
            warnings.append("Relationship or identity terms need public genre/theme support before becoming a shelf.")
        }
        let closeShelfShouldLowerConfidence = !(top.rule.requiresPublicIdentity && hasPublicIdentityCatalogSupport)
        if runnerScore > 0, margin < 0.18, closeShelfShouldLowerConfidence {
            value = max(0, value - 0.12)
            warnings.append("Two shelves are close; keep this reviewable or show alternatives.")
        }
        let highConfidenceEligible = hasSpecificSignal
            || hasPublicIdentityCatalogSupport
            || hasPublicIdentityNarrativeSupport
            || (hasNarrativeTextSupport && hasCatalogingSupport && sourceCount >= 4)
        if !highConfidenceEligible {
            value = min(value, 0.81)
        }

        let level: SableLibraryShelfConfidenceLevel
        switch value {
        case 0.82...:
            level = .high
        case 0.58..<0.82:
            level = .medium
        case 0.38..<0.58:
            level = .low
        default:
            level = .needsReview
        }
        return (min(max(value, 0), 0.96), level)
    }

    private static func shelf(_ code: String, _ title: String, _ subShelves: [SableLibrarySubShelfDefinition]) -> SableLibraryShelfDefinition {
        SableLibraryShelfDefinition(code: code, title: title, subShelves: subShelves)
    }

    private static func sub(_ code: String, _ title: String) -> SableLibrarySubShelfDefinition {
        SableLibrarySubShelfDefinition(code: code, title: title)
    }

    private static func hasContentAdvisoryWarning(in values: [String]) -> Bool {
        let text = normalize(values.joined(separator: " | "))
        guard !text.isEmpty else { return false }
        return contentAdvisoryWarningTerms.contains { containsNormalized(text, term: normalize($0)) }
    }

    private static func hasHighSensitivityReviewWarning(in values: [String]) -> Bool {
        let text = normalize(values.joined(separator: " | "))
        guard !text.isEmpty else { return false }
        return highSensitivityReviewTerms.contains { containsNormalized(text, term: normalize($0)) }
    }

    private static let contentAdvisoryWarningTerms = [
        "adult", "mature", "explicit", "hentai", "erotica", "ecchi", "smut",
        "sex shop", "sex shops", "sexy shops", "sexual services", "sex work",
        "sexual violence", "sexual assault", "sexual content", "sexual coercion",
        "rape", "attempted rape", "dubious consent", "non consensual", "non-consensual",
        "incest", "abuse", "harassment", "sexual harassment", "gore", "torture",
        "suicide", "self harm", "self-harm", "nudity", "partial nudity"
    ]

    private static let highSensitivityReviewTerms = [
        "sexual violence", "sexual assault", "sexual coercion",
        "rape", "attempted rape", "dubious consent", "non consensual", "non-consensual",
        "incest", "abuse", "harassment", "sexual harassment", "gore", "torture",
        "suicide", "self harm", "self-harm"
    ]
}

nonisolated private func uniqueEvidenceRoleValues(_ values: [String]) -> [String] {
    var seen: Set<String> = []
    var result: [String] = []
    for value in values {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = normalize(trimmed)
        guard !key.isEmpty, seen.insert(key).inserted else { continue }
        result.append(trimmed)
    }
    return result
}

nonisolated private struct EvidenceText {
    var title: ShelfSearchText
    var description: ShelfSearchText
    var volumeDescriptions: ShelfSearchText
    var genres: ShelfSearchText
    var themes: ShelfSearchText
    var tags: ShelfSearchText
    var specificSignals: ShelfSearchText
    var providerNeighbors: ShelfSearchText
    var facetTags: ShelfSearchText
    var reviewTags: ShelfSearchText
    var contentWarnings: ShelfSearchText
    var hasIsekaiContext: Bool
    var hasRomanceEngineContext: Bool

    init(input: SableLibraryShelfCatalogInput) {
        let tagClassifications = SableLibraryShelfTagClassifier.classify(
            Self.uniqueRecords(input.tagRecords + input.tags.map { SableLibraryShelfTagRecord(name: $0) })
        )
        let strongShelfClassifications = tagClassifications.filter { classification in
            classification.isShelfEvidence && classification.evidenceMultiplier >= 0.45
        }
        let genreTagNames = strongShelfClassifications
            .filter { $0.role == .contentGenre }
            .map(\.record.name)
        let themeTagNames = strongShelfClassifications
            .filter { classification in
                [.narrativeEngine, .settingFrame, .subjectTheme].contains(classification.role)
            }
            .map(\.record.name)

        let normalizedTitle = Self.joinNormalized([input.title])
        let normalizedDescription = Self.joinNormalized([input.description].compactMap { $0 })
        let normalizedVolumeDescriptions = Self.joinNormalized(input.volumeDescriptions)
        let normalizedGenres = Self.joinNormalized(input.genres + genreTagNames)
        let normalizedThemes = Self.joinNormalized(input.themes + themeTagNames)
        let normalizedTags = Self.joinNormalized(tagClassifications.filter(\.isShelfEvidence).map(\.record.name))
        let normalizedProviderNeighbors = Self.joinNormalized(input.providerNeighborSignals)
        let normalizedSpecificSignals = [
            normalizedTitle,
            normalizedDescription,
            normalizedVolumeDescriptions,
            normalizedGenres,
            normalizedThemes,
            normalizedTags
        ].joined(separator: " | ")
        let normalizedFacetTags = Self.joinNormalized(tagClassifications.filter { classification in
            classification.use == .facet || classification.use == .reviewOnly
        }.map(\.record.name))
        let normalizedReviewTags = Self.joinNormalized(tagClassifications.filter { classification in
            classification.use == .reviewOnly
        }.map(\.record.name))
        let normalizedContentWarnings = Self.joinNormalized(input.contentWarnings)
        title = ShelfSearchText(normalizedTitle)
        description = ShelfSearchText(normalizedDescription)
        volumeDescriptions = ShelfSearchText(normalizedVolumeDescriptions)
        genres = ShelfSearchText(normalizedGenres)
        themes = ShelfSearchText(normalizedThemes)
        tags = ShelfSearchText(normalizedTags)
        specificSignals = ShelfSearchText(normalizedSpecificSignals)
        providerNeighbors = ShelfSearchText(normalizedProviderNeighbors)
        facetTags = ShelfSearchText(normalizedFacetTags)
        reviewTags = ShelfSearchText(normalizedReviewTags)
        contentWarnings = ShelfSearchText(normalizedContentWarnings)
        let allText = [
            normalizedTitle,
            normalizedDescription,
            normalizedVolumeDescriptions,
            normalizedGenres,
            normalizedThemes,
            normalizedTags,
            normalizedFacetTags
        ].joined(separator: " | ")
        hasIsekaiContext = Self.isIsekaiContext(ShelfSearchText(allText))
        hasRomanceEngineContext = Self.isRomanceEngineContext(
            ShelfSearchText([
                normalizedTitle,
                normalizedDescription,
                normalizedVolumeDescriptions,
                normalizedThemes
            ].joined(separator: " | "))
        )
    }

    private static func joinNormalized(_ values: [String]) -> String {
        normalize(values.joined(separator: " | "))
    }

    private static func isIsekaiContext(_ text: ShelfSearchText) -> Bool {
        isekaiContextTerms.compactMap(ShelfTerm.init).contains { text.contains($0) }
    }

    private static func isRomanceEngineContext(_ text: ShelfSearchText) -> Bool {
        romanceEngineTerms.compactMap(ShelfTerm.init).contains { text.contains($0) }
    }

    private static let isekaiContextTerms = [
        "isekai", "reverse isekai", "another world", "other world",
        "strange world", "person in a strange world", "summoned into another world",
        "summoned to another world", "transported to another world",
        "transmigrated into another world", "reincarnated in another world",
        "reincarnated into another world", "reincarnated into a new world",
        "reincarnated into a fantasy world", "reborn into another world",
        "reborn in another world", "reborn into a fantasy world",
        "second life in another world", "second lifetime in another world",
        "former japanese in another world", "from earth to another world",
        "memories from a previous life in another world",
        "otome game", "return by death", "bookworm", "honzuki", "re:zero",
        "re zero", "mushoku tensei", "jobless reincarnation", "konosuba",
        "so i'm a spider", "so i'm a spider so what", "beginning after the end",
        "regression", "regressor", "redo", "second chance timeline", "back in time",
        "inside a novel", "inside the novel", "inside a story", "inside the story",
        "story world", "canon fodder", "death flag"
    ]

    private static let romanceEngineTerms = [
        "love story", "romance", "romantic", "falls in love", "falling in love",
        "in love", "marriage", "arranged marriage", "contract marriage",
        "engagement", "betrothed", "bride", "groom", "fiance", "fiancee",
        "fiancée", "fiancees", "fiancées", "wedding", "courtship",
        "dating", "relationship", "lovers", "couple", "first love",
        "slow burn", "confession", "suitor"
    ]

    private static func uniqueRecords(_ records: [SableLibraryShelfTagRecord]) -> [SableLibraryShelfTagRecord] {
        var seen: Set<String> = []
        var result: [SableLibraryShelfTagRecord] = []
        for record in records {
            let key = [
                normalize(record.name),
                normalize(record.path ?? "")
            ].joined(separator: "|")
            guard !key.trimmingCharacters(in: CharacterSet(charactersIn: "|")).isEmpty,
                  seen.insert(key).inserted else {
                continue
            }
            result.append(record)
        }
        return result
    }
}

nonisolated private struct Rule {
    var shelfCode: String
    var subCode: String
    var titleTerms: [ShelfTerm]
    var descriptionTerms: [ShelfTerm]
    var genreTerms: [ShelfTerm]
    var themeTerms: [ShelfTerm]
    var tagTerms: [ShelfTerm]
    var specificTerms: [ShelfTerm]
    var requiresPublicIdentity: Bool
    var requiresIsekaiContext: Bool
    var requiresRomanceEngineWhenIsekai: Bool
    var excludesIsekaiContext: Bool
    var scoreMultiplier: Double

    init(
        _ shelfCode: String,
        _ subCode: String,
        title: [String],
        description: [String],
        genres: [String],
        themes: [String],
        tags: [String],
        specific: [String] = [],
        requiresPublicIdentity: Bool = false,
        requiresIsekaiContext: Bool = false,
        requiresRomanceEngineWhenIsekai: Bool = false,
        excludesIsekaiContext: Bool = false,
        scoreMultiplier: Double = 1
    ) {
        self.shelfCode = shelfCode
        self.subCode = subCode
        self.titleTerms = Self.terms(title)
        self.descriptionTerms = Self.terms(description)
        self.genreTerms = Self.terms(genres)
        self.themeTerms = Self.terms(themes)
        self.tagTerms = Self.terms(tags)
        self.specificTerms = Self.terms(specific)
        self.requiresPublicIdentity = requiresPublicIdentity
        self.requiresIsekaiContext = requiresIsekaiContext
        self.requiresRomanceEngineWhenIsekai = requiresRomanceEngineWhenIsekai
        self.excludesIsekaiContext = excludesIsekaiContext
        self.scoreMultiplier = scoreMultiplier
    }

    init(
        shelfCode: String,
        subCode: String,
        titleTerms: [String],
        descriptionTerms: [String],
        genreTerms: [String],
        themeTerms: [String],
        tagTerms: [String],
        specificTerms: [String] = [],
        requiresPublicIdentity: Bool = false,
        requiresIsekaiContext: Bool = false,
        requiresRomanceEngineWhenIsekai: Bool = false,
        excludesIsekaiContext: Bool = false,
        scoreMultiplier: Double = 1
    ) {
        self.shelfCode = shelfCode
        self.subCode = subCode
        self.titleTerms = Self.terms(titleTerms)
        self.descriptionTerms = Self.terms(descriptionTerms)
        self.genreTerms = Self.terms(genreTerms)
        self.themeTerms = Self.terms(themeTerms)
        self.tagTerms = Self.terms(tagTerms)
        self.specificTerms = Self.terms(specificTerms)
        self.requiresPublicIdentity = requiresPublicIdentity
        self.requiresIsekaiContext = requiresIsekaiContext
        self.requiresRomanceEngineWhenIsekai = requiresRomanceEngineWhenIsekai
        self.excludesIsekaiContext = excludesIsekaiContext
        self.scoreMultiplier = scoreMultiplier
    }

    private static func terms(_ values: [String]) -> [ShelfTerm] {
        values.compactMap(ShelfTerm.init)
    }
}

nonisolated private struct ShelfSearchText: Sendable, Equatable {
    private static let indexedPhraseWordLimit = 10

    var normalized: String
    private var paddedBoundaryText: String
    private var boundaryTokens: Set<String>
    private var boundaryPhrases: Set<String>

    init(_ normalized: String) {
        self.normalized = normalized
        let boundaryText = boundaryNormalize(normalized)
        paddedBoundaryText = " \(boundaryText) "
        let tokens = boundaryText.split(separator: " ").map(String.init)
        boundaryTokens = Set(tokens)

        var phrases = Set<String>()
        if tokens.count > 1 {
            phrases.reserveCapacity(tokens.count * min(Self.indexedPhraseWordLimit, tokens.count))
            for start in tokens.indices {
                var phrase = tokens[start]
                let upperBound = min(tokens.count, start + Self.indexedPhraseWordLimit)
                guard start + 1 < upperBound else { continue }
                for index in (start + 1)..<upperBound {
                    phrase += " " + tokens[index]
                    phrases.insert(phrase)
                }
            }
        }
        boundaryPhrases = phrases
    }

    func contains(_ term: ShelfTerm) -> Bool {
        guard !normalized.isEmpty else { return false }
        if term.boundaryWordCount == 1 {
            return boundaryTokens.contains(term.boundaryNormalized)
        }
        if term.boundaryWordCount <= Self.indexedPhraseWordLimit {
            return boundaryPhrases.contains(term.boundaryNormalized)
        }
        return paddedBoundaryText.contains(" \(term.boundaryNormalized) ")
    }
}

nonisolated private struct ShelfTerm: Sendable, Equatable {
    var raw: String
    var normalized: String
    var boundaryNormalized: String
    var boundaryWordCount: Int

    init?(_ raw: String) {
        let normalized = normalize(raw)
        guard !normalized.isEmpty else { return nil }
        let boundaryNormalized = boundaryNormalize(normalized)
        self.raw = raw
        self.normalized = normalized
        self.boundaryNormalized = boundaryNormalized
        self.boundaryWordCount = boundaryNormalized.split(separator: " ").count
    }
}

nonisolated private struct CandidateScore {
    var rule: Rule
    var points: [SableLibraryShelfEvidencePoint] = []

    var sources: Set<SableLibraryShelfEvidenceSource> {
        Set(points.map(\.source))
    }

    var hasPublicIdentityCatalogSupport: Bool {
        rule.requiresPublicIdentity
            && sources.contains(.specificSignal)
            && !sources.isDisjoint(with: [.genre, .theme])
    }

    var hasPublicIdentityNarrativeSupport: Bool {
        rule.requiresPublicIdentity
            && sources.contains(.specificSignal)
            && !sources.isDisjoint(with: [.title, .description, .volumeDescription])
    }

    var totalScore: Double {
        let base = points.reduce(0) { $0 + $1.score }
        let independentSources = sources.subtracting([.specificSignal, .providerNeighbor])
        let agreementBonus = max(0, min(Double(independentSources.count - 1) * 2, 6))
        let identityCentralityBonus: Double
        if rule.requiresPublicIdentity,
           !sources.isDisjoint(with: [.title, .description, .volumeDescription]),
           !sources.isDisjoint(with: [.genre, .theme]) {
            identityCentralityBonus = 12
        } else if hasPublicIdentityCatalogSupport {
            identityCentralityBonus = 10
        } else if hasPublicIdentityNarrativeSupport {
            identityCentralityBonus = 8
        } else {
            identityCentralityBonus = 0
        }
        return (base + agreementBonus + identityCentralityBonus) * rule.scoreMultiplier
    }

    init(rule: Rule) {
        self.rule = rule
    }

    init(reviewRule: Rule, note: String) {
        self.rule = reviewRule
        self.points = [
            SableLibraryShelfEvidencePoint(
                source: .safety,
                matchedTerms: [],
                score: 0.1,
                note: note
            )
        ]
    }

    mutating func add(
        source: SableLibraryShelfEvidenceSource,
        terms: [ShelfTerm],
        text: ShelfSearchText,
        weight: Double,
        cap: Double
    ) {
        let matched = terms.filter { text.contains($0) }.map(\.raw)
        guard !matched.isEmpty else { return }
        let score = min(Double(matched.count) * weight, cap)
        points.append(
            SableLibraryShelfEvidencePoint(
                source: source,
                matchedTerms: matched,
                score: score,
                note: "\(source.displayName) matched \(matched.prefix(3).joined(separator: ", "))."
            )
        )
    }
}

nonisolated private func contains(_ text: String, term: String) -> Bool {
    containsNormalized(normalize(text), term: normalize(term))
}

nonisolated private func containsNormalized(_ normalizedText: String, term normalizedTerm: String) -> Bool {
    guard !normalizedText.isEmpty, !normalizedTerm.isEmpty else { return false }

    var searchRange = normalizedText.startIndex..<normalizedText.endIndex
    while let range = normalizedText.range(of: normalizedTerm, range: searchRange) {
        let startsAtBoundary = range.lowerBound == normalizedText.startIndex
            || !isShelfAlphaNumeric(normalizedText[normalizedText.index(before: range.lowerBound)])
        let endsAtBoundary = range.upperBound == normalizedText.endIndex
            || !isShelfAlphaNumeric(normalizedText[range.upperBound])
        if startsAtBoundary && endsAtBoundary {
            return true
        }

        guard range.upperBound < normalizedText.endIndex else { break }
        searchRange = range.upperBound..<normalizedText.endIndex
    }
    return false
}

nonisolated private func normalize(_ value: String) -> String {
    let folded = value
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        .lowercased()
    var result = String.UnicodeScalarView()
    var lastWasSpace = true
    let space = UnicodeScalar(32)!

    for scalar in folded.unicodeScalars {
        if isAllowedShelfScalar(scalar) {
            result.append(scalar)
            lastWasSpace = false
        } else if !lastWasSpace {
            result.append(space)
            lastWasSpace = true
        }
    }

    return String(result).trimmingCharacters(in: .whitespacesAndNewlines)
}

nonisolated private func boundaryNormalize(_ value: String) -> String {
    var result = String.UnicodeScalarView()
    var lastWasSpace = true
    let space = UnicodeScalar(32)!

    for scalar in value.unicodeScalars {
        if isShelfAlphaNumeric(scalar) {
            result.append(scalar)
            lastWasSpace = false
        } else if !lastWasSpace {
            result.append(space)
            lastWasSpace = true
        }
    }

    return String(result).trimmingCharacters(in: .whitespacesAndNewlines)
}

nonisolated private func isAllowedShelfScalar(_ scalar: UnicodeScalar) -> Bool {
    switch scalar.value {
    case 48...57, 97...122, 35, 43, 47:
        return true
    default:
        return false
    }
}

nonisolated private func isShelfAlphaNumeric(_ scalar: UnicodeScalar) -> Bool {
    switch scalar.value {
    case 48...57, 97...122:
        return true
    default:
        return false
    }
}

nonisolated private func isShelfAlphaNumeric(_ character: Character) -> Bool {
    guard character.unicodeScalars.count == 1,
          let scalar = character.unicodeScalars.first else {
        return false
    }
    return isShelfAlphaNumeric(scalar)
}
