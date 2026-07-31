//
//  SableLibraryScannerModels.swift
//  Sable's Library
//

import Foundation

struct BookNameParts: Sendable {
    let seriesTitle: String
    let fileTitle: String
    let needsManualReview: Bool
}

struct SeriesEntry: Codable, Sendable {
    let title: String
    let folderURL: URL
    let relativePath: String
    let formats: [String]
}

struct MetadataCandidate: Identifiable, Hashable, Sendable {
    let term: String
    let count: Int
    let examples: [String]

    var id: String { term.lowercased() }

    nonisolated init(term: String, count: Int, examples: [String] = []) {
        self.term = term
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .lowercased()
        self.count = count
        self.examples = examples
    }
}

struct MetadataScanSummary: Sendable {
    let candidates: [MetadataCandidate]
    let sourceTermKeys: Set<String>
}

struct DuplicateReviewGroup: Identifiable, Hashable, Sendable {
    enum Kind: String, Hashable, Sendable {
        case exactContent
    }

    let fingerprint: String
    let paths: [String]
    let fileSizes: [String: Int64]
    let kind: Kind
    let suggestedKeeperPath: String?
    let note: String

    var id: String { fingerprint + paths.joined(separator: "|") }

    var duplicateCount: Int {
        max(0, paths.count - 1)
    }

    var fileSize: Int64 {
        paths.first.flatMap { fileSizes[$0] } ?? 0
    }
}

struct MangaBakaCandidate: Codable, Sendable, Identifiable, Hashable {
    var mangaBakaID: String
    var preferredTitle: String
    var nativeTitle: String?
    var romanizedTitle: String?
    var aliases: [String]
    var type: String?
    var publisher: String?
    var status: String?
    var finalVolume: String?

    var id: String { mangaBakaID.isEmpty ? preferredTitle : mangaBakaID }

    enum CodingKeys: String, CodingKey {
        case mangaBakaID = "mangabaka_id"
        case preferredTitle = "preferred_title"
        case nativeTitle = "native_title"
        case romanizedTitle = "romanized_title"
        case aliases
        case type
        case publisher
        case status
        case finalVolume = "final_volume"
    }
}
