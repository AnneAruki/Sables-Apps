//
//  SableMangaBakaCoverModels.swift
//  Sable's Covers
//

import Foundation

nonisolated struct SableMangaBakaSeriesTitle: Codable, Sendable, Equatable {
    var language: String
    var traits: [String]
    var title: String
    var isPrimary: Bool?

    enum CodingKeys: String, CodingKey {
        case language
        case traits
        case title
        case isPrimary = "is_primary"
    }
}

nonisolated struct SableMangaBakaSeriesRelationship: Codable, Sendable, Equatable {
    var toSeriesID: Int
    var relationType: String

    enum CodingKeys: String, CodingKey {
        case toSeriesID = "to_series_id"
        case relationType = "relation_type"
    }
}

nonisolated struct SableMangaBakaSeriesRelationshipReference:
    Sendable,
    Equatable
{
    var seriesID: Int
    var relationType: String
}

nonisolated struct SableMangaBakaSeriesSummary: Codable, Sendable, Equatable, Identifiable {
    struct Cover: Codable, Sendable, Equatable {
        struct Raw: Codable, Sendable, Equatable {
            var url: String?
        }

        var raw: Raw?
    }

    struct Publisher: Codable, Sendable, Equatable {
        var name: String
        var type: String?
        var note: String?
    }

    struct Publication: Codable, Sendable, Equatable {
        var startDate: String?
        var endDate: String?

        enum CodingKeys: String, CodingKey {
            case startDate = "start_date"
            case endDate = "end_date"
        }
    }

    var id: Int
    var title: String?
    var nativeTitle: String?
    var romanizedTitle: String?
    var titles: [SableMangaBakaSeriesTitle]?
    var type: String
    var cover: Cover?
    var finalVolume: String?
    var status: String? = nil
    var isLicensed: Bool? = nil
    var publishers: [Publisher]? = nil
    var published: Publication? = nil
    var year: Int? = nil
    var relationships: [String: [Int]]? = nil
    var relationshipsV2: [SableMangaBakaSeriesRelationship]? = nil

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case nativeTitle = "native_title"
        case romanizedTitle = "romanized_title"
        case titles
        case type
        case cover
        case finalVolume = "final_volume"
        case status
        case isLicensed = "is_licensed"
        case publishers
        case published
        case year
        case relationships
        case relationshipsV2 = "relationships_v2"
    }

    var hasClosedVolumeCount: Bool {
        let normalized = status?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            ?? ""
        return [
            "cancelled",
            "canceled",
            "complete",
            "completed",
            "finished"
        ].contains(normalized)
    }

    var displayTitle: String {
        let preferred = titles?.first(where: {
            $0.language == "en" && ($0.isPrimary == true || $0.traits.contains("official"))
        }) ?? titles?.first(where: { $0.language == "en" })
            ?? titles?.first(where: { $0.isPrimary == true })
            ?? titles?.first
        return preferred?.title
            ?? title
            ?? romanizedTitle
            ?? nativeTitle
            ?? "MangaBaka series \(id)"
    }

    var coverURL: URL? {
        guard let value = cover?.raw?.url else { return nil }
        return URL(string: value)
    }

    var hasCoverImage: Bool {
        coverURL != nil
    }

    var publicationDateLabel: String? {
        if let startDate = published?.startDate?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !startDate.isEmpty {
            return startDate
        }
        return year.map(String.init)
    }

    var relationshipReferences: [SableMangaBakaSeriesRelationshipReference] {
        var seenSeriesIDs = Set<Int>()
        var references: [SableMangaBakaSeriesRelationshipReference] = []

        for relationship in relationshipsV2 ?? [] {
            guard relationship.toSeriesID != id,
                  seenSeriesIDs.insert(relationship.toSeriesID).inserted else {
                continue
            }
            references.append(
                SableMangaBakaSeriesRelationshipReference(
                    seriesID: relationship.toSeriesID,
                    relationType: relationship.relationType
                )
            )
        }

        for relationType in (relationships ?? [:]).keys.sorted() {
            for seriesID in relationships?[relationType] ?? [] {
                guard seriesID != id,
                      seenSeriesIDs.insert(seriesID).inserted else {
                    continue
                }
                references.append(
                    SableMangaBakaSeriesRelationshipReference(
                        seriesID: seriesID,
                        relationType: relationType
                    )
                )
            }
        }

        return references
    }
}

nonisolated struct SableMangaBakaRelatedSeriesSummary:
    Sendable,
    Equatable,
    Identifiable
{
    var relationType: String
    var series: SableMangaBakaSeriesSummary

    var id: Int { series.id }
}

nonisolated struct SableMangaBakaSeriesPage: Sendable, Equatable {
    var series: [SableMangaBakaSeriesSummary]
    var totalCount: Int
    var page: Int
    var limit: Int
    var hasNextPage: Bool
    var hasPreviousPage: Bool
}

nonisolated struct SableMangaBakaPublicCoverStats: Sendable, Equatable {
    var volumeCoverCount: Int
    var availableLanguages: [String]
    var volumeCovers: [SableMangaBakaPublicCoverImage] = []

    func coverage(
        language: String,
        expectedVolumeCount: Int?
    ) -> SableMangaBakaLanguageCoverCoverage {
        let normalizedLanguage = language
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let coveredIndices = Set(
            volumeCovers.compactMap { cover -> Int? in
                guard cover.type == "volume",
                      cover.language
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .lowercased() == normalizedLanguage else {
                    return nil
                }
                let rounded = cover.indexNumeric.rounded()
                guard rounded >= 1,
                      abs(cover.indexNumeric - rounded) < 0.001 else {
                    return nil
                }
                return Int(rounded)
            }
        )
        .sorted()
        let usableExpectedCount = expectedVolumeCount.flatMap { $0 > 0 ? $0 : nil }
        let upperBound = usableExpectedCount ?? coveredIndices.last
        let missingIndices: [Int]
        if let upperBound, upperBound > 0 {
            let covered = Set(coveredIndices)
            missingIndices = (1...upperBound).filter { !covered.contains($0) }
        } else {
            missingIndices = []
        }
        return SableMangaBakaLanguageCoverCoverage(
            language: normalizedLanguage,
            coveredIndices: coveredIndices,
            missingIndices: missingIndices,
            expectedVolumeCount: usableExpectedCount
        )
    }
}

nonisolated struct SableMangaBakaPublicCoverImage: Sendable, Equatable, Identifiable {
    var id: Int
    var indexNumeric: Double
    var language: String
    var type: String
    var rawURL: String
    var width: Int
    var height: Int
    var contentRating: String = "safe"
}

nonisolated struct SableMangaBakaLanguageCoverCoverage: Sendable, Equatable {
    var language: String
    var coveredIndices: [Int]
    var missingIndices: [Int]
    var expectedVolumeCount: Int?

    var hasConfirmedGap: Bool {
        coveredIndices.isEmpty || !missingIndices.isEmpty
    }

    var isIndeterminate: Bool {
        expectedVolumeCount == nil
            && !coveredIndices.isEmpty
            && missingIndices.isEmpty
    }

    var isComplete: Bool {
        expectedVolumeCount != nil
            && !coveredIndices.isEmpty
            && missingIndices.isEmpty
    }
}

nonisolated struct SableMangaBakaCoverInventory: Sendable, Equatable {
    var snapshot: SableMangaBakaCoverSnapshot
    var liveImages: [SableMangaBakaPublicCoverImage]
}

nonisolated struct SableMangaBakaLocalCoverImage: Sendable, Equatable {
    var indexNumeric: Double
    var language: String
    var path: String
    var width: Int
    var height: Int
}

nonisolated struct SableMangaBakaStorefrontImageChoice: Sendable, Equatable, Identifiable {
    var url: String
    var width: Int? = nil
    var height: Int? = nil

    var id: String {
        SableMangaBakaCoverSnapshot.coverURLIdentity(url)
    }
}

nonisolated struct SableMangaBakaDirectCoverInspection:
    Sendable,
    Equatable,
    Identifiable
{
    var url: String
    var width: Int
    var height: Int

    var id: String {
        SableMangaBakaCoverSnapshot.coverURLIdentity(url)
    }
}

nonisolated struct SableMangaBakaStorefrontCoverSuggestion: Sendable, Equatable, Identifiable {
    var provider: SableLibraryBigBookCoversProvider
    var providerSeriesID: String?
    var providerItemID: String?
    var title: String
    var imageURL: String
    var imageChoices: [SableMangaBakaStorefrontImageChoice] = []
    var storeURL: String?
    var volumeNumber: Double
    var language: String
    var coverType: String = "volume"
    var requiresRelationshipReview: Bool = false
    var automaticMatchConfidence: Double = 0
    var expectedMediaType: String? = nil
    var detectedMediaType: String? = nil
    var usesManualMediaTypeOverride: Bool = false
    var usesPublisherMediaTypeProof: Bool = false
    var width: Int? = nil
    var height: Int? = nil
    var contentRating: String = "safe"
    var contentRatingWasInferred: Bool = false
    var detectedVolumeNumbers: [Int] = []
    var detectedChapterNumbers: [Int] = []
    var publicationType: String? = nil
    var visualSignature: [UInt8] = []

    var id: String {
        [
            provider.rawValue,
            providerSeriesID ?? "",
            providerItemID ?? "",
            language,
            coverType,
            requiresRelationshipReview ? "review" : "trusted",
            expectedMediaType ?? "",
            detectedMediaType ?? "",
            usesManualMediaTypeOverride ? "manual-type" : "automatic-type",
            usesPublisherMediaTypeProof ? "publisher-type" : "store-type",
            publicationType ?? "",
            String(volumeNumber),
            imageURL
        ]
        .joined(separator: ":")
    }

    var sourceIdentity: String {
        [
            provider.rawValue,
            providerSeriesID ?? "",
            providerItemID ?? "",
            imageURL
        ]
        .joined(separator: ":")
    }

    var availableImageChoices: [SableMangaBakaStorefrontImageChoice] {
        var choices: [SableMangaBakaStorefrontImageChoice] = []
        var seen = Set<String>()

        func append(_ choice: SableMangaBakaStorefrontImageChoice) {
            let identity = SableMangaBakaCoverSnapshot
                .coverURLIdentity(choice.url)
            guard !identity.isEmpty else { return }
            if let existingIndex = choices.firstIndex(where: {
                SableMangaBakaCoverSnapshot.coverURLIdentity($0.url)
                    == identity
            }) {
                if choices[existingIndex].width == nil {
                    choices[existingIndex].width = choice.width
                }
                if choices[existingIndex].height == nil {
                    choices[existingIndex].height = choice.height
                }
                return
            }
            guard seen.insert(identity).inserted else { return }
            choices.append(choice)
        }

        imageChoices.forEach(append)
        append(
            SableMangaBakaStorefrontImageChoice(
                url: imageURL,
                width: width,
                height: height
            )
        )
        return choices
    }

    var activeImageChoiceIndex: Int {
        let activeIdentity = SableMangaBakaCoverSnapshot
            .coverURLIdentity(imageURL)
        return availableImageChoices.firstIndex {
            SableMangaBakaCoverSnapshot.coverURLIdentity($0.url)
                == activeIdentity
        } ?? 0
    }

    var imageChoiceCount: Int {
        availableImageChoices.count
    }

    var volumeLabel: String {
        volumeNumber.rounded() == volumeNumber
            ? String(Int(volumeNumber))
            : String(volumeNumber)
    }

    var numberedKindLabel: String {
        let kind = switch coverType {
        case "audiobook": "Audiobook"
        case "chapter": "Chapter"
        case "volume_back": "Back Cover"
        default: "Volume"
        }
        return "\(kind) \(volumeLabel)"
    }

    var normalizedPublicationType: String? {
        let normalized = publicationType?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalized?.isEmpty == false ? normalized : nil
    }

    var isDigitalEdition: Bool {
        normalizedPublicationType == "digital"
    }

    var publicationTypeLabel: String? {
        switch normalizedPublicationType {
        case "physical":
            return "Print edition"
        case "digital":
            return "Digital edition"
        case let value?:
            return value.capitalized
        case nil:
            return nil
        }
    }

    var contentRatingLabel: String {
        let normalized = contentRating
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return SableMangaBakaCoverImage.supportedRatings.contains(normalized)
            ? normalized.capitalized
            : "Safe"
    }

    var numberingReviewReason: String? {
        guard volumeNumber.rounded() == volumeNumber,
              volumeNumber >= 0 else {
            return nil
        }
        let expected = Int(volumeNumber)
        let volumes = Set(detectedVolumeNumbers)
        let chapters = Set(detectedChapterNumbers)

        if coverType == "chapter" {
            if !chapters.isEmpty, !chapters.contains(expected) {
                return "Cover text shows chapter \(Self.numberList(chapters)), not chapter \(expected)."
            }
            if chapters.isEmpty, !volumes.isEmpty {
                return "Cover text looks like volume \(Self.numberList(volumes)), not a chapter cover."
            }
            return nil
        }

        if !volumes.isEmpty, !volumes.contains(expected) {
            return "Cover text shows volume \(Self.numberList(volumes)), not volume \(expected)."
        }
        if volumes.isEmpty, !chapters.isEmpty {
            return "Cover text looks like chapter \(Self.numberList(chapters)), not a volume cover."
        }
        return nil
    }

    var requiresNumberingReview: Bool {
        numberingReviewReason != nil
    }

    var requiresManualReview: Bool {
        requiresRelationshipReview || requiresNumberingReview
    }

    var qualifiesForAutomaticAcceptance: Bool {
        requiresRelationshipReview
            && automaticMatchConfidence >= 0.90
            && !mediaTypeNeedsAttention
    }

    var mediaTypeEvidenceLabel: String {
        let expected = Self.mediaTypeLabel(expectedMediaType)
        let detected = Self.mediaTypeLabel(detectedMediaType)

        if let expected, let detected, usesPublisherMediaTypeProof {
            return "Expected \(expected) · Publisher says \(detected)"
        }
        if let expected, let detected {
            return "Expected \(expected) · Store says \(detected)"
        }
        if let expected, usesManualMediaTypeOverride {
            return "Expected \(expected) · Manual type override"
        }
        if let expected {
            return "Expected \(expected) · Store type unproven"
        }
        if let detected {
            return "Store says \(detected)"
        }
        return "Store type unproven"
    }

    var mediaTypeNeedsAttention: Bool {
        guard let expectedMediaType else {
            return detectedMediaType == nil
        }
        guard let detectedMediaType else {
            return !usesManualMediaTypeOverride
        }
        return !SableLibraryCoverDownloadPlanner.providerMediaTypeIsCompatible(
            detectedMediaType,
            isCompatibleWith: expectedMediaType
        )
    }

    var reachesArchiveMinimum: Bool {
        guard let width, let height else { return false }
        if coverType == "audiobook" {
            return width >= 500
                && height >= 500
                && width * height >= 350_000
        }
        return SableLibraryCoverDownloadPlanner.coverDimensionsAreArchiveUsable(
            width: width,
            height: height
        )
    }

    var reachesClinicMinimum: Bool {
        guard let width, let height else { return false }
        if coverType == "audiobook" {
            return width >= 800
                && height >= 800
                && width * height >= 850_000
        }
        return SableLibraryCoverDownloadPlanner.coverDimensionsAreUsable(
            width: width,
            height: height
        )
    }

    var imageNeedsReplacement: Bool {
        guard let width, let height else { return false }
        guard width > 1, height > 1 else { return true }

        if coverType == "audiobook" {
            let aspectRatio = Double(height) / Double(max(width, 1))
            return !(0.8...1.25).contains(aspectRatio)
        }

        return !SableLibraryCoverDownloadPlanner.coverDimensionsHaveBookShape(
            width: width,
            height: height
        )
    }

    var imageIssueLabel: String? {
        guard imageNeedsReplacement else { return nil }
        guard let width, let height else { return nil }
        if width <= 1 || height <= 1 {
            return "The provider matched this book, but its cover image is unavailable."
        }
        if coverType == "audiobook" {
            return "This \(width) x \(height) image is not shaped like audiobook artwork."
        }
        if !SableLibraryCoverDownloadPlanner.coverDimensionsHaveBookShape(
            width: width,
            height: height
        ) {
            return "This \(width) x \(height) image looks like audiobook artwork or a placeholder, not a book cover."
        }
        return "The provider matched this book, but this image cannot be used as its cover."
    }

    private static func mediaTypeLabel(_ value: String?) -> String? {
        let clean = value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let clean, !clean.isEmpty else { return nil }

        let normalized = clean
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        if normalized.contains("audio")
            || normalized.contains("오디오") {
            return "Audiobook"
        }
        if normalized.contains("manga")
            || normalized.contains("comic")
            || normalized.contains("graphic novel")
            || normalized.contains("만화")
            || normalized.contains("웹툰")
            || normalized.contains("코믹")
            || normalized.contains("그래픽노블") {
            return "Manga"
        }
        if normalized.contains("novel")
            || normalized == "ranobe"
            || normalized.contains("라이트노벨")
            || normalized.contains("라이트 노벨")
            || normalized.contains("장르소설")
            || normalized.contains("웹소설") {
            return "Light novel"
        }
        if normalized == "book" {
            return "Book"
        }
        return clean.capitalized
    }

    private static func numberList(_ values: Set<Int>) -> String {
        values.sorted().map(String.init).joined(separator: ", ")
    }
}

nonisolated struct SableMangaBakaStorefrontCompositeSlot:
    Sendable,
    Equatable,
    Identifiable
{
    var language: String
    var coverType: String
    var volumeNumber: Double
    var suggestions: [SableMangaBakaStorefrontCoverSuggestion]
    var winner: SableMangaBakaStorefrontCoverSuggestion

    var id: String {
        [
            Self.normalizedLanguage(language),
            coverType,
            String(volumeNumber)
        ]
        .joined(separator: ":")
    }

    var alternativeCount: Int {
        max(0, suggestions.count - 1)
    }

    var winnerIndex: Int {
        suggestions.firstIndex(where: { $0.id == winner.id }) ?? 0
    }

    private static func normalizedLanguage(_ value: String) -> String {
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
}

nonisolated struct SableMangaBakaStorefrontDiscoveryResult: Sendable, Equatable {
    var suggestions: [SableMangaBakaStorefrontCoverSuggestion]
    var notes: [String]
}

nonisolated struct SableMangaBakaLocalLibrarySeries: Sendable, Equatable, Identifiable {
    var id: String { folderURL.path(percentEncoded: false) }
    var title: String
    var mediaType: String
    var mangaBakaID: Int?
    var localBookCount: Int
    var localCovers: [SableMangaBakaLocalCoverImage] = []
    var folderURL: URL
    var comicInfoURL: URL? = nil
    var ranobeDBID: String? = nil
    var mangaBakaSeriesBundle: SableLibraryMangaBakaSeriesBundle? = nil

    var mangaBakaSeriesIDs: [Int] {
        if let mangaBakaSeriesBundle,
           !mangaBakaSeriesBundle.members.isEmpty {
            return mangaBakaSeriesBundle.seriesIDs
        }
        return mangaBakaID.map { [$0] } ?? []
    }

    var hasMangaBakaIdentity: Bool {
        !mangaBakaSeriesIDs.isEmpty
    }
}

nonisolated enum SableMangaBakaLibraryCoverStatus: String, Sendable, Equatable {
    case missingMangaBakaID
    case noVolumeCovers
    case fewerCoversThanLocalBooks
    case localCoverQualityUpgrade
    case mediaTypeConflict
    case covered
    case couldNotCheck

    var needsAttention: Bool {
        self != .covered
    }

    var needsCoverAttention: Bool {
        needsAttention && self != .missingMangaBakaID
    }
}

nonisolated struct SableMangaBakaLibraryCoverAuditItem: Sendable, Equatable, Identifiable {
    var id: String { localSeries.id }
    var localSeries: SableMangaBakaLocalLibrarySeries
    var mangaBakaSeries: SableMangaBakaSeriesSummary?
    var coverStats: SableMangaBakaPublicCoverStats?
    var status: SableMangaBakaLibraryCoverStatus
    var note: String
}

nonisolated struct SableMangaBakaCoverImage: Codable, Sendable, Equatable, Identifiable {
    var id: Int?
    var seriesID: Int?
    var workID: String?
    var url: String
    var index: String?
    var indexNumeric: Double
    var language: String
    var type: String
    var note: String?
    var contentRating: String
    var isDefault: Bool
    var previewURL: String?

    enum CodingKeys: String, CodingKey {
        case id
        case seriesID = "series_id"
        case workID = "work_id"
        case url
        case index
        case indexNumeric = "index_numeric"
        case language
        case type
        case note
        case contentRating = "content_rating"
        case isDefault = "is_default"
    }

    init(
        id: Int? = nil,
        seriesID: Int?,
        workID: String? = nil,
        url: String,
        index: String?,
        indexNumeric: Double,
        language: String,
        type: String = "volume",
        note: String? = nil,
        contentRating: String = "safe",
        isDefault: Bool = false,
        previewURL: String? = nil
    ) {
        self.id = id
        self.seriesID = seriesID
        self.workID = workID
        self.url = url
        self.index = index
        self.indexNumeric = indexNumeric
        self.language = language
        self.type = type
        self.note = note
        self.contentRating = contentRating
        self.isDefault = isDefault
        self.previewURL = previewURL
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(Int.self, forKey: .id)
        seriesID = try container.decodeIfPresent(Int.self, forKey: .seriesID)
        workID = try container.decodeIfPresent(String.self, forKey: .workID)
        url = try container.decode(String.self, forKey: .url)
        index = try container.decodeIfPresent(String.self, forKey: .index)
        indexNumeric = try container.decodeIfPresent(Double.self, forKey: .indexNumeric) ?? 0
        language = try container.decodeIfPresent(String.self, forKey: .language) ?? "unknown"
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? "volume"
        note = try container.decodeIfPresent(String.self, forKey: .note)
        contentRating = try container.decodeIfPresent(String.self, forKey: .contentRating) ?? "safe"
        isDefault = try container.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        previewURL = nil
    }

    var stableID: String {
        id.map(String.init) ?? url
    }

    var imageURL: URL? {
        URL(string: previewURL ?? url)
    }

    var preferredBookLiveSourceURL: String {
        guard URL(string: url)?.host?.lowercased() == "res.booklive.jp" else {
            return url
        }
        return url.replacingOccurrences(
            of: #"/thumbnail/(?:S|M|L|X|2L)\.jpg"#,
            with: "/thumbnail/X.jpg",
            options: .regularExpression
        )
    }

    var volumeLabel: String {
        if let index, !index.isEmpty {
            return index
        }
        if indexNumeric.rounded() == indexNumeric {
            return String(Int(indexNumeric))
        }
        return String(indexNumeric)
    }
}

extension SableMangaBakaCoverImage {
    static let supportedLanguages = [
        "en", "ja", "ko", "zh", "fr", "it", "de", "es", "pt", "nl", "unknown"
    ]
    static let supportedTypes = ["volume", "audiobook", "chapter", "volume_back", "season", "banner", "other"]
    static let supportedRatings = ["safe", "suggestive", "erotica", "pornographic"]

    var inventoryGroup: SableMangaBakaCoverInventoryGroup {
        SableMangaBakaCoverInventoryGroup.classify(type: type, note: note)
    }

    var inventoryItemLabel: String {
        SableMangaBakaCoverInventoryGroup.itemLabel(
            type: type,
            note: note,
            indexLabel: volumeLabel
        )
    }
}

extension SableMangaBakaPublicCoverImage {
    var inventoryGroup: SableMangaBakaCoverInventoryGroup {
        SableMangaBakaCoverInventoryGroup.classify(type: type, note: nil)
    }

    var volumeLabel: String {
        indexNumeric.rounded() == indexNumeric
            ? String(Int(indexNumeric))
            : String(indexNumeric)
    }

    var inventoryItemLabel: String {
        SableMangaBakaCoverInventoryGroup.itemLabel(
            type: type,
            note: nil,
            indexLabel: volumeLabel
        )
    }
}

nonisolated enum SableMangaBakaCoverInventoryGroup: String, CaseIterable, Sendable, Identifiable {
    case standardVolumes
    case backCovers
    case chapterCovers
    case audiobookCovers
    case extras

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standardVolumes: "Standard Volumes"
        case .backCovers: "Back Covers"
        case .chapterCovers: "Chapter Covers"
        case .audiobookCovers: "Audiobooks"
        case .extras: "Specials & Extras"
        }
    }

    var shortTitle: String {
        switch self {
        case .standardVolumes: "Volumes"
        case .backCovers: "Back Covers"
        case .chapterCovers: "Chapters"
        case .audiobookCovers: "Audiobooks"
        case .extras: "Extras"
        }
    }

    func summaryTitle(count: Int) -> String {
        guard count == 1 else { return shortTitle }
        return switch self {
        case .standardVolumes: "Volume"
        case .backCovers: "Back Cover"
        case .chapterCovers: "Chapter"
        case .audiobookCovers: "Audiobook"
        case .extras: "Extra"
        }
    }

    var systemImage: String {
        switch self {
        case .standardVolumes: "books.vertical"
        case .backCovers: "rectangle.portrait.on.rectangle.portrait"
        case .chapterCovers: "doc.text.image"
        case .audiobookCovers: "headphones"
        case .extras: "sparkles.rectangle.stack"
        }
    }

    static func classify(type: String, note: String?) -> Self {
        let normalizedType = type
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let normalizedNote = note?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""

        if normalizedType.contains("audio")
            || normalizedNote.contains("audiobook")
            || normalizedNote.contains("audio book") {
            return .audiobookCovers
        }
        if normalizedType == "chapter" {
            return .chapterCovers
        }
        if normalizedType == "volume_back" {
            return .backCovers
        }
        if normalizedType == "volume",
           !specialEditionTerms.isDisjoint(with: normalizedNoteWords(normalizedNote)) {
            return .extras
        }
        return normalizedType == "volume" ? .standardVolumes : .extras
    }

    static func itemLabel(
        type: String,
        note: String?,
        indexLabel: String
    ) -> String {
        let group = classify(type: type, note: note)
        let cleanType = type
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let kind: String

        switch group {
        case .standardVolumes:
            kind = "Volume"
        case .backCovers:
            kind = "Back Cover"
        case .chapterCovers:
            kind = "Chapter"
        case .audiobookCovers:
            kind = "Audiobook"
        case .extras:
            switch cleanType {
            case "volume":
                kind = "Special / Alternative"
            case "season":
                kind = "Season"
            case "banner":
                kind = "Banner"
            default:
                kind = cleanType
                    .replacingOccurrences(of: "_", with: " ")
                    .capitalized
            }
        }

        guard !indexLabel.isEmpty else { return kind }
        return "\(kind) \(indexLabel)"
    }

    private static let specialEditionTerms: Set<String> = [
        "special", "alternative", "alternate", "variant", "bonus", "booklet",
        "limited", "collector", "anniversary", "digital"
    ]

    private static func normalizedNoteWords(_ note: String) -> Set<String> {
        Set(
            note.components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
        )
    }
}

nonisolated struct SableMangaBakaCoverSnapshot: Sendable, Equatable {
    var seriesID: Int
    var images: [SableMangaBakaCoverImage]
    var version: Int64

    static func preferredDefaultIndex(
        in images: [SableMangaBakaCoverImage]
    ) -> Int? {
        let preferredSlots = [
            (type: "volume", language: "en"),
            (type: "volume", language: "ja"),
            (type: "volume", language: "ko"),
            (type: "chapter", language: "en"),
            (type: "chapter", language: "ja")
        ]

        for slot in preferredSlots {
            let matches = images.indices.filter { index in
                let image = images[index]
                return image.type.lowercased() == slot.type
                    && normalizedDefaultLanguage(image.language) == slot.language
                    && abs(image.indexNumeric - 1) < 0.001
            }
            if let currentDefault = matches.first(where: {
                images[$0].isDefault
            }) {
                return currentDefault
            }
            if let first = matches.first {
                return first
            }
        }
        return nil
    }

    func normalizedForSubmission() -> SableMangaBakaCoverSnapshot {
        var result = self
        let firstDefault = result.images.firstIndex(where: \.isDefault)
        if result.images.isEmpty {
            return result
        }
        let chosenDefault = firstDefault ?? result.images.startIndex
        for index in result.images.indices {
            result.images[index].seriesID = result.seriesID
            result.images[index].isDefault = index == chosenDefault
            if result.images[index].index == nil {
                result.images[index].index = result.images[index].volumeLabel
            }
        }
        return result
    }

    private static func normalizedDefaultLanguage(_ value: String) -> String {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
        let base = normalized.split(separator: "-").first.map(String.init) ?? ""
        return switch base {
        case "jp": "ja"
        case "kr": "ko"
        case "cn": "zh"
        case "": "unknown"
        default: base
        }
    }

    func validationIssues() -> [String] {
        var issues: [String] = []
        var seenURLs = Set<String>()

        for image in images {
            guard let url = URL(string: image.url),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "https" || scheme == "http",
                  url.host != nil else {
                issues.append("Every cover needs a complete http or https URL.")
                continue
            }
            if url.host?.lowercased().contains("imgur") == true {
                issues.append("MangaBaka rejects Imgur cover URLs because of rate limiting.")
            }
            let identity = image.url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !seenURLs.insert(identity).inserted {
                issues.append("The same cover URL appears more than once.")
            }
            if image.indexNumeric < 0 {
                issues.append("Cover indexes cannot be negative.")
            }
            if image.language.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append("Every cover needs a language.")
            }
            if image.contentRating.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append("Every cover needs a content rating.")
            }
        }

        if !images.isEmpty, images.filter(\.isDefault).count != 1 {
            issues.append("A non-empty cover set needs exactly one default cover.")
        }
        return Array(Set(issues)).sorted()
    }

    func validationIssues(
        allowingInheritedDuplicateURLsFrom baselineImages: [SableMangaBakaCoverImage]
    ) -> [String] {
        var issues = validationIssues()
        let duplicateIssue = "The same cover URL appears more than once."
        guard issues.contains(duplicateIssue) else { return issues }

        let baselineCounts = Self.coverURLCounts(in: baselineImages)
        let currentCounts = Self.coverURLCounts(in: images)
        let introducedDuplicate = currentCounts.contains { identity, count in
            count > 1 && count > baselineCounts[identity, default: 0]
        }
        if !introducedDuplicate {
            issues.removeAll { $0 == duplicateIssue }
        }
        return issues
    }

    static func coverURLIdentity(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func coverURLCounts(
        in images: [SableMangaBakaCoverImage]
    ) -> [String: Int] {
        images.reduce(into: [:]) { counts, image in
            let identity = coverURLIdentity(image.url)
            counts[identity, default: 0] += 1
        }
    }
}

nonisolated struct SableMangaBakaSubmissionDiff: Codable, Sendable, Equatable, Identifiable {
    var field: String
    var type: String
    var identity: String?
    var label: String?
    var details: [String: SableMangaBakaDiffValue]?

    var id: String {
        [field, type, identity ?? "", label ?? ""].joined(separator: "|")
    }
}

nonisolated struct SableMangaBakaDiffValue: Codable, Sendable, Equatable {
    var old: SableMangaBakaJSONValue?
    var new: SableMangaBakaJSONValue?
}

nonisolated enum SableMangaBakaJSONValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: SableMangaBakaJSONValue])
    case array([SableMangaBakaJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: SableMangaBakaJSONValue].self) {
            self = .object(value)
        } else {
            self = .array(try container.decode([SableMangaBakaJSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    var shortDescription: String {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            return value.rounded() == value ? String(Int(value)) : String(value)
        case .bool(let value):
            return value ? "true" : "false"
        case .object:
            return "changed values"
        case .array(let values):
            return "\(values.count) values"
        case .null:
            return "none"
        }
    }
}

nonisolated struct SableMangaBakaSubmissionPreview: Sendable, Equatable {
    var hasChanges: Bool
    var changes: [SableMangaBakaSubmissionDiff]
}

nonisolated struct SableMangaBakaSubmissionResult: Sendable, Equatable {
    var submissionID: Int
    var status: String
    var changes: [SableMangaBakaSubmissionDiff]
}

nonisolated enum SableMangaBakaSaveMode: String, Sendable {
    case review
    case direct
}

nonisolated struct SableMangaBakaDownloadResult: Sendable, Equatable {
    var saved: [String]
    var skipped: [String]
    var failed: [String]
}
