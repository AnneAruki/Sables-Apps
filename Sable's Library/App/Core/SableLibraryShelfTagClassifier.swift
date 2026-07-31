 //
//  SableLibraryShelfTagClassifier.swift
//  Sable's Library
//

import Foundation

nonisolated enum SableLibraryShelfTagRole: String, Codable, Sendable {
    case contentGenre
    case settingFrame
    case narrativeEngine
    case subjectTheme
    case characterOrSpecies
    case relationship
    case audienceDemographic
    case bibliographicRelationship
    case formOrCarrier
    case productionStatus
    case contentAdvisory
    case unknown

    var displayName: String {
        switch self {
        case .contentGenre: "Content genre"
        case .settingFrame: "Setting or frame"
        case .narrativeEngine: "Narrative engine"
        case .subjectTheme: "Subject or theme"
        case .characterOrSpecies: "Character or species"
        case .relationship: "Relationship"
        case .audienceDemographic: "Audience demographic"
        case .bibliographicRelationship: "Bibliographic relationship"
        case .formOrCarrier: "Form or carrier"
        case .productionStatus: "Production status"
        case .contentAdvisory: "Content advisory"
        case .unknown: "Unsorted tag"
        }
    }
}

nonisolated enum SableLibraryShelfTagUse: String, Codable, Sendable {
    case mainShelfEvidence
    case subShelfEvidence
    case facet
    case bibliographicRelationship
    case reviewOnly
    case ignore

    var isShelfEvidence: Bool {
        self == .mainShelfEvidence || self == .subShelfEvidence
    }

    var displayName: String {
        switch self {
        case .mainShelfEvidence: "Use for main shelf"
        case .subShelfEvidence: "Use for sub-shelf"
        case .facet: "Keep as facet"
        case .bibliographicRelationship: "Keep as relationship metadata"
        case .reviewOnly: "Use for review warning"
        case .ignore: "Ignore for SSS"
        }
    }
}

nonisolated struct SableLibraryShelfTagRecord: Sendable, Equatable {
    var name: String
    var path: String?
    var providerWeight: String?
    var isGenre: Bool?
    var isSpoiler: Bool?
    var isExplicit: Bool?
    var contentRating: String?
    var provider: String?

    init(
        name: String,
        path: String? = nil,
        providerWeight: String? = nil,
        isGenre: Bool? = nil,
        isSpoiler: Bool? = nil,
        isExplicit: Bool? = nil,
        contentRating: String? = nil,
        provider: String? = nil
    ) {
        self.name = name
        self.path = path
        self.providerWeight = providerWeight
        self.isGenre = isGenre
        self.isSpoiler = isSpoiler
        self.isExplicit = isExplicit
        self.contentRating = contentRating
        self.provider = provider
    }
}

nonisolated struct SableLibraryShelfTagClassification: Sendable, Equatable {
    var record: SableLibraryShelfTagRecord
    var role: SableLibraryShelfTagRole
    var use: SableLibraryShelfTagUse
    var evidenceMultiplier: Double
    var note: String

    var isShelfEvidence: Bool {
        use.isShelfEvidence
    }
}

nonisolated enum SableLibraryShelfTagClassifier {
    static func classify(names: [String]) -> [SableLibraryShelfTagClassification] {
        classify(names.map { SableLibraryShelfTagRecord(name: $0) })
    }

    static func classify(_ records: [SableLibraryShelfTagRecord]) -> [SableLibraryShelfTagClassification] {
        records.map(classify)
    }

    static func classify(_ record: SableLibraryShelfTagRecord) -> SableLibraryShelfTagClassification {
        let name = normalizedShelfTagText(record.name)
        let path = normalizedShelfTagText(record.path ?? "")
        let combined = [name, path].filter { !$0.isEmpty }.joined(separator: " ")

        if isContentAdvisory(record: record, combined: combined) {
            return result(record, .contentAdvisory, .reviewOnly, 0, "Content and access-sensitive tags stay reviewable.")
        }
        if isBibliographicRelationship(combined) {
            return result(record, .bibliographicRelationship, .bibliographicRelationship, 0, "This describes adaptation, source, or media lineage, not story aboutness.")
        }
        if isFormOrCarrier(combined) {
            return result(record, .formOrCarrier, .facet, 0.05, "This belongs to the Form/Origin layer rather than the shelf layer.")
        }
        if isProductionStatus(combined) {
            return result(record, .productionStatus, .facet, 0.05, "This helps collection management, not subject shelving.")
        }
        if isCoreRelationshipIdentity(combined) {
            return result(record, .relationship, .facet, min(facetMultiplier(for: record) * 1.1, 0.55), "Core queer/BL-GL identity terms stay as high-priority facets and need title/theme/genre support to become a public shelf.")
        }
        if isRelationship(combined) {
            return result(record, .relationship, .facet, facetMultiplier(for: record), "Relationship tags are facets unless genre/theme evidence makes them the public shelf.")
        }
        if record.isGenre == true || isContentGenre(combined) {
            return result(record, .contentGenre, .mainShelfEvidence, weightedMultiplier(for: record, base: 1), "Genre terms can support the main shelf.")
        }
        if isNarrativeEngine(combined) {
            return result(record, .narrativeEngine, .subShelfEvidence, weightedMultiplier(for: record, base: 0.9), "Narrative engine terms help decide the sub-shelf.")
        }
        if isSettingFrame(combined) {
            return result(record, .settingFrame, .subShelfEvidence, weightedMultiplier(for: record, base: 0.8), "Setting and frame terms help decide the shelf neighborhood.")
        }
        if isCharacterOrSpecies(combined) {
            return result(record, .characterOrSpecies, .facet, facetMultiplier(for: record), "Character and species terms are usually facets unless several sources agree.")
        }
        if isAudienceDemographic(combined) {
            return result(record, .audienceDemographic, .facet, 0.1, "Audience demographic is useful browsing metadata, not story aboutness.")
        }
        if isSubjectTheme(combined) {
            return result(record, .subjectTheme, .subShelfEvidence, weightedMultiplier(for: record, base: 0.75), "Subject/theme terms can support a sub-shelf.")
        }

        return result(record, .unknown, .facet, 0.1, "Keep the tag visible, but do not let it steer shelving until it is classified.")
    }

    static func shelfEvidenceNames(from names: [String]) -> [String] {
        shelfEvidenceNames(from: names.map { SableLibraryShelfTagRecord(name: $0) })
    }

    static func shelfEvidenceNames(from records: [SableLibraryShelfTagRecord]) -> [String] {
        uniqueShelfTagNames(classify(records).filter(\.isShelfEvidence).map(\.record.name))
    }

    static func facetNames(from names: [String]) -> [String] {
        facetNames(from: names.map { SableLibraryShelfTagRecord(name: $0) })
    }

    static func facetNames(from records: [SableLibraryShelfTagRecord]) -> [String] {
        uniqueShelfTagNames(classify(records).filter { classification in
            classification.use == .facet || classification.use == .reviewOnly
        }.map(\.record.name))
    }

    private static func result(
        _ record: SableLibraryShelfTagRecord,
        _ role: SableLibraryShelfTagRole,
        _ use: SableLibraryShelfTagUse,
        _ multiplier: Double,
        _ note: String
    ) -> SableLibraryShelfTagClassification {
        SableLibraryShelfTagClassification(
            record: record,
            role: role,
            use: use,
            evidenceMultiplier: min(max(multiplier, 0), 1),
            note: note
        )
    }

    private static let bibliographicRelationshipTerms = shelfTagTerms([
            "derivative work", "adapted to", "adaptation", "anime tie in", "manga tie in",
            "based on", "based on a web novel", "based on a light novel", "based on a novel",
            "based on literature", "based on game", "based on a game", "based on visual novel",
            "based on manga", "based on anime", "adapted to game", "adapted to manga",
            "adapted to anime", "drama cd", "audio drama", "spin off", "spin-off",
            "side story", "sequel", "prequel", "serialization", "franchise"
    ])

    private static let formOrCarrierTerms = shelfTagTerms([
            "light novel", "light novels", "web novel", "web novels", "novel", "manga",
            "manhwa", "manhua", "anime", "one shot", "ebook", "paperback"
    ])

    private static let productionStatusTerms = shelfTagTerms([
            "licensed", "completed", "ongoing", "hiatus", "releasing", "publication status",
            "has anime", "anime announced", "award winning", "award-winning"
    ])

    private static let contentAdvisoryTerms = shelfTagTerms([
        "content warning", "content warnings", "gore", "torture", "suicide",
        "sexual violence", "sexual content", "sexual acts", "sexual coercion",
        "rape", "attempted rape", "incest", "adult", "hentai", "erotica",
        "ecchi", "smut", "mature", "nudity", "partial nudity", "lust", "group intercourse",
        "threesome", "virginity", "stolen kiss", "sex shop", "sex shops", "sexy shops",
        "sexual services", "sex work", "harassment", "sexual harassment"
    ])

    private static let relationshipTerms = shelfTagTerms([
        "romance subplot", "harem", "poly", "love triangle", "master servant relationship",
        "heterosexual", "relationship dynamics", "polyamory", "polygamy", "multiple wives",
        "multiple partners", "dominance", "submissive", "age gap", "older male younger male",
        "finding love again", "unrequited love", "first love", "marriage", "engagement",
        "reverse harem", "multiple love interests", "love rivals"
    ])

    private static let coreRelationshipIdentityTerms = shelfTagTerms([
        "boys love", "girls love", "yaoi", "yuri", "shounen ai", "shoujo ai",
        "omegaverse", "male x male", "m/m romance", "gay romance", "sapphic romance",
        "lesbian romance", "dom/sub", "alpha", "omega", "queer", "bl", "gl",
        "secondary gender", "guideverse", "cakeverse", "nameverse", "lgbtq"
    ])

    private static let contentGenreTerms = shelfTagTerms([
        "action", "adventure", "comedy", "drama", "fantasy", "horror",
        "mystery", "romance", "sci fi", "science fiction", "slice of life",
        "supernatural", "thriller", "suspense", "tragedy", "historical",
        "literary fiction", "classic", "sports romance", "gourmet",
        "school life", "dark comedy", "black comedy", "gag humor", "satire",
        "parody", "slapstick", "mecha", "martial arts"
    ])

    private static let narrativeEngineTerms = shelfTagTerms([
        "time loop", "time rewind", "time travel", "time manipulation",
        "reincarnation", "transmigration", "summoned into another world",
        "transported to another world", "reincarnated in another world",
        "weak to strong", "game elements", "leveling", "rpg", "skills", "stats",
        "otome game", "villainess", "kingdom building", "crafting", "invention",
        "economics", "survival", "revenge", "quest", "travel", "death game",
        "death games", "high stakes game", "high stakes games", "play or die", "kill or be killed", "dungeon survival", "non human protagonist",
        "non-human protagonist", "monster protagonist", "body swap", "body swapping", "body swaps", "gender bender",
        "age regression", "loop", "redo", "regression", "regressor", "second chance",
        "back in time", "inside a novel", "inside the novel", "inside a story",
        "inside the story", "story world", "canon fodder", "death flag",
        "animal transformation", "shapeshifting", "beast protagonist", "object protagonist",
        "cultivation", "cultivator", "xianxia", "wuxia", "murim"
    ])

    private static let settingFrameTerms = shelfTagTerms([
        "isekai", "fantasy world", "alternate universe", "dungeon", "labyrinth",
        "court", "nobility", "royalty", "kingdom", "empire", "school",
        "academy", "workplace", "restaurant", "cafe", "medieval", "war",
        "military", "vrmmo", "game world", "other world", "virtual reality",
        "guilds", "palace", "rear palace", "boarding school", "college",
        "high school", "middle school", "rural", "countryside", "urban",
        "dystopian", "apocalypse", "school life", "modern day", "showbiz",
        "entertainment industry", "urban fantasy", "futuristic city", "story world",
        "spirit realm", "folklore", "mythology", "cultivation sect", "sect", "jianghu"
    ])

    private static let characterOrSpeciesTerms = shelfTagTerms([
        "female lead", "male lead", "female protagonist", "male protagonist",
        "non human protagonist", "nonhuman protagonist", "monster pov", "slime",
        "spider", "witch", "mage", "demon lord", "demon king", "dragon",
        "elf", "vampire", "monster girls", "monster boys", "strong female lead",
        "villainess", "anti hero", "anti-hero", "hero", "demon", "gods",
        "monks", "priests", "idol", "idols", "yakuza", "otaku", "hikikomori",
        "youkai", "yokai", "guardian spirit", "goddess"
    ])

    private static let audienceDemographicTerms = shelfTagTerms([
        "shounen", "shojo", "shoujo", "seinen", "josei", "demographic",
        "male demographic", "female demographic"
    ])

    private static let subjectThemeTerms = shelfTagTerms([
        "medicine", "investigation", "cooking", "food", "gourmet", "library",
        "books", "writing", "working", "business", "trade", "merchant",
        "alchemy", "production magic", "healing", "slow life", "family",
        "found family", "politics", "religion", "social class", "poverty",
        "knowledge", "modern knowledge", "magic", "music", "performing arts",
        "singing", "idols", "fandom", "organized crime", "medicine",
        "apothecary", "poison", "chef", "agriculture", "guilds", "craft",
        "work", "school clubs", "maid", "maids", "domestic work", "housekeeping",
        "restaurant", "diner", "food and beverage", "blacksmith", "blacksmiths",
        "bladesmith", "magical weapons", "weapon master", "workshop", "artisan",
        "idol", "fans", "otaku culture", "showbiz", "mafia", "mafioso",
        "crime family", "mobster",
        "entertainment industry", "kpop", "yakuza", "battle royale", "mecha",
        "robots", "artificial intelligence", "esp", "super powers", "superpowers",
        "special abilities", "anti magic", "anti-magic", "paranormal", "folklore",
        "japanese folklore", "myth", "mythology", "urban legend", "spirits",
        "spirit realm", "youkai", "yokai", "guardian spirits", "gods", "goddess",
        "cultivation", "cultivator", "xianxia", "wuxia", "murim", "martial arts",
        "sect", "qi", "dao"
    ])

    private static func isBibliographicRelationship(_ text: String) -> Bool {
        containsAnyShelfTagTerm(text, bibliographicRelationshipTerms)
    }

    private static func isFormOrCarrier(_ text: String) -> Bool {
        containsAnyShelfTagTerm(text, formOrCarrierTerms)
    }

    private static func isProductionStatus(_ text: String) -> Bool {
        containsAnyShelfTagTerm(text, productionStatusTerms)
    }

    private static func isContentAdvisory(record: SableLibraryShelfTagRecord, combined: String) -> Bool {
        ["adult", "erotica", "pornographic", "mature", "hentai", "smut"].contains(normalizedShelfTagText(record.contentRating ?? ""))
            || containsAnyShelfTagTerm(combined, contentAdvisoryTerms)
    }

    private static func isRelationship(_ text: String) -> Bool {
        containsAnyShelfTagTerm(text, relationshipTerms)
    }

    private static func isCoreRelationshipIdentity(_ text: String) -> Bool {
        containsAnyShelfTagTerm(text, coreRelationshipIdentityTerms)
    }

    private static func isContentGenre(_ text: String) -> Bool {
        containsAnyShelfTagTerm(text, contentGenreTerms)
    }

    private static func isNarrativeEngine(_ text: String) -> Bool {
        containsAnyShelfTagTerm(text, narrativeEngineTerms)
    }

    private static func isSettingFrame(_ text: String) -> Bool {
        containsAnyShelfTagTerm(text, settingFrameTerms)
    }

    private static func isCharacterOrSpecies(_ text: String) -> Bool {
        containsAnyShelfTagTerm(text, characterOrSpeciesTerms)
    }

    private static func isAudienceDemographic(_ text: String) -> Bool {
        containsAnyShelfTagTerm(text, audienceDemographicTerms)
    }

    private static func isSubjectTheme(_ text: String) -> Bool {
        containsAnyShelfTagTerm(text, subjectThemeTerms)
    }

    private static func weightedMultiplier(for record: SableLibraryShelfTagRecord, base: Double) -> Double {
        if record.isGenre == true, providerWeightIsMissingOrUnweighted(record.providerWeight) {
            return base * 0.75
        }
        return base * providerWeightMultiplier(record.providerWeight)
    }

    private static func facetMultiplier(for record: SableLibraryShelfTagRecord) -> Double {
        min(0.45, 0.35 * providerWeightMultiplier(record.providerWeight))
    }

    private static func providerWeightMultiplier(_ value: String?) -> Double {
        switch normalizedShelfTagText(value ?? "") {
        case "defining": 1
        case "core": 0.9
        case "recurrent": 0.55
        case "incidental": 0.25
        case "unweighted", "": 0.15
        default: 0.4
        }
    }

    private static func providerWeightIsMissingOrUnweighted(_ value: String?) -> Bool {
        let normalized = normalizedShelfTagText(value ?? "")
        return normalized.isEmpty || normalized == "unweighted"
    }
}

nonisolated private func uniqueShelfTagNames(_ values: [String]) -> [String] {
    var seen: Set<String> = []
    var result: [String] = []
    for value in values {
        let key = normalizedShelfTagText(value)
        guard !key.isEmpty, !seen.contains(key) else { continue }
        seen.insert(key)
        result.append(value)
    }
    return result
}

nonisolated private struct ShelfTagTerm: Sendable, Equatable {
    var raw: String
    var normalized: String

    init?(_ raw: String) {
        let normalized = normalizedShelfTagText(raw)
        guard !normalized.isEmpty else { return nil }
        self.raw = raw
        self.normalized = normalized
    }
}

nonisolated private func shelfTagTerms(_ values: [String]) -> [ShelfTagTerm] {
    values.compactMap(ShelfTagTerm.init)
}

nonisolated private func containsAnyShelfTagTerm(_ normalizedText: String, _ terms: [ShelfTagTerm]) -> Bool {
    terms.contains { containsShelfTagTerm(normalizedText, term: $0) }
}

nonisolated private func containsShelfTagTerm(_ normalizedText: String, term: ShelfTagTerm) -> Bool {
    guard !normalizedText.isEmpty, !term.normalized.isEmpty else { return false }

    var searchRange = normalizedText.startIndex..<normalizedText.endIndex
    while let range = normalizedText.range(of: term.normalized, range: searchRange) {
        let startsAtBoundary = range.lowerBound == normalizedText.startIndex
            || !isShelfTagAlphaNumeric(normalizedText[normalizedText.index(before: range.lowerBound)])
        let endsAtBoundary = range.upperBound == normalizedText.endIndex
            || !isShelfTagAlphaNumeric(normalizedText[range.upperBound])
        if startsAtBoundary && endsAtBoundary {
            return true
        }

        guard range.upperBound < normalizedText.endIndex else { break }
        searchRange = range.upperBound..<normalizedText.endIndex
    }
    return false
}

nonisolated private func normalizedShelfTagText(_ value: String) -> String {
    let folded = value
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        .lowercased()
    var result = String.UnicodeScalarView()
    var lastWasSpace = true
    let space = UnicodeScalar(32)!

    for scalar in folded.unicodeScalars {
        if isAllowedShelfTagScalar(scalar) {
            result.append(scalar)
            lastWasSpace = false
        } else if !lastWasSpace {
            result.append(space)
            lastWasSpace = true
        }
    }

    return String(result).trimmingCharacters(in: .whitespacesAndNewlines)
}

nonisolated private func isAllowedShelfTagScalar(_ scalar: UnicodeScalar) -> Bool {
    switch scalar.value {
    case 48...57, 97...122, 35, 43, 47:
        return true
    default:
        return false
    }
}

nonisolated private func isShelfTagAlphaNumeric(_ character: Character) -> Bool {
    guard character.unicodeScalars.count == 1,
          let scalar = character.unicodeScalars.first else {
        return false
    }
    switch scalar.value {
    case 48...57, 97...122:
        return true
    default:
        return false
    }
}
