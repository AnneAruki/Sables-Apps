//
//  SableLibraryLearning.swift
//  Sable's Library
//

import Foundation

nonisolated enum SableLibraryPDFTriageChoice: String, Codable, Sendable, Equatable {
    case document
    case book
}

nonisolated struct SableLibraryLearningMemory: Codable, Sendable, Equatable {
    struct CleanupKindTermMemory: Codable, Sendable, Equatable {
        var kindCounts: [String: Int] = [:]
        var lastDecisionAt: Date?
    }

    struct RawReadingLaneTermMemory: Codable, Sendable, Equatable {
        var laneCounts: [String: Int] = [:]
        var lastDecisionAt: Date?
    }

    struct MetadataTermMemory: Codable, Sendable, Equatable {
        var usedCount = 0
        var dismissedCount = 0
        var lastDecisionAt: Date?
    }

    struct MangaBakaSeriesMemory: Codable, Sendable, Equatable {
        var keptLocalCount = 0
        var acceptedCandidateIDs: [String: Int] = [:]
        var lastDecisionAt: Date?
    }

    struct PDFTriageTermMemory: Codable, Sendable, Equatable {
        var documentCount = 0
        var bookCount = 0
        var lastDecisionAt: Date?
    }

    var cleanupKindTerms: [String: CleanupKindTermMemory] = [:]
    var rawReadingLaneTerms: [String: RawReadingLaneTermMemory] = [:]
    var metadataTerms: [String: MetadataTermMemory] = [:]
    var mangaBakaSeries: [String: MangaBakaSeriesMemory] = [:]
    var pdfTriageTerms: [String: PDFTriageTermMemory] = [:]

    enum CodingKeys: String, CodingKey {
        case cleanupKindTerms
        case rawReadingLaneTerms
        case metadataTerms
        case mangaBakaSeries
        case pdfTriageTerms
    }

    init(
        cleanupKindTerms: [String: CleanupKindTermMemory] = [:],
        rawReadingLaneTerms: [String: RawReadingLaneTermMemory] = [:],
        metadataTerms: [String: MetadataTermMemory] = [:],
        mangaBakaSeries: [String: MangaBakaSeriesMemory] = [:],
        pdfTriageTerms: [String: PDFTriageTermMemory] = [:]
    ) {
        self.cleanupKindTerms = cleanupKindTerms
        self.rawReadingLaneTerms = rawReadingLaneTerms
        self.metadataTerms = metadataTerms
        self.mangaBakaSeries = mangaBakaSeries
        self.pdfTriageTerms = pdfTriageTerms
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cleanupKindTerms = try container.decodeIfPresent([String: CleanupKindTermMemory].self, forKey: .cleanupKindTerms) ?? [:]
        rawReadingLaneTerms = try container.decodeIfPresent([String: RawReadingLaneTermMemory].self, forKey: .rawReadingLaneTerms) ?? [:]
        metadataTerms = try container.decodeIfPresent([String: MetadataTermMemory].self, forKey: .metadataTerms) ?? [:]
        mangaBakaSeries = try container.decodeIfPresent([String: MangaBakaSeriesMemory].self, forKey: .mangaBakaSeries) ?? [:]
        pdfTriageTerms = try container.decodeIfPresent([String: PDFTriageTermMemory].self, forKey: .pdfTriageTerms) ?? [:]
    }

    var learnedDecisionCount: Int {
        let cleanupKindCount = cleanupKindTerms.values.reduce(0) { total, memory in
            total + memory.kindCounts.values.reduce(0, +)
        }
        let rawReadingCount = rawReadingLaneTerms.values.reduce(0) { total, memory in
            total + memory.laneCounts.values.reduce(0, +)
        }
        let metadataCount = metadataTerms.values.reduce(0) { total, memory in
            total + memory.usedCount + memory.dismissedCount
        }
        let mangaCount = mangaBakaSeries.values.reduce(0) { total, memory in
            total + memory.keptLocalCount + memory.acceptedCandidateIDs.values.reduce(0, +)
        }
        let pdfCount = pdfTriageTerms.values.reduce(0) { total, memory in
            total + memory.documentCount + memory.bookCount
        }
        return cleanupKindCount + rawReadingCount + metadataCount + mangaCount + pdfCount
    }

    mutating func pruneForLightweightStorage(
        maxEntriesPerCategory: Int = 300,
        maxMangaCandidatesPerSeries: Int = 6
    ) {
        cleanupKindTerms = Self.pruned(
            cleanupKindTerms,
            maxEntries: maxEntriesPerCategory
        ) { memory in
            (memory.lastDecisionAt, memory.kindCounts.values.reduce(0, +))
        }

        rawReadingLaneTerms = Self.pruned(
            rawReadingLaneTerms,
            maxEntries: maxEntriesPerCategory
        ) { memory in
            (memory.lastDecisionAt, memory.laneCounts.values.reduce(0, +))
        }

        metadataTerms = Self.pruned(
            metadataTerms,
            maxEntries: maxEntriesPerCategory
        ) { memory in
            (memory.lastDecisionAt, memory.usedCount + memory.dismissedCount)
        }

        mangaBakaSeries = mangaBakaSeries.mapValues { memory in
            var prunedMemory = memory
            prunedMemory.acceptedCandidateIDs = Self.prunedCounts(
                prunedMemory.acceptedCandidateIDs,
                maxEntries: maxMangaCandidatesPerSeries
            )
            return prunedMemory
        }
        mangaBakaSeries = Self.pruned(
            mangaBakaSeries,
            maxEntries: maxEntriesPerCategory
        ) { memory in
            (
                memory.lastDecisionAt,
                memory.keptLocalCount + memory.acceptedCandidateIDs.values.reduce(0, +)
            )
        }

        pdfTriageTerms = Self.pruned(
            pdfTriageTerms,
            maxEntries: maxEntriesPerCategory
        ) { memory in
            (memory.lastDecisionAt, memory.documentCount + memory.bookCount)
        }
    }

    func prunedForLightweightStorage(
        maxEntriesPerCategory: Int = 300,
        maxMangaCandidatesPerSeries: Int = 6
    ) -> SableLibraryLearningMemory {
        var memory = self
        memory.pruneForLightweightStorage(
            maxEntriesPerCategory: maxEntriesPerCategory,
            maxMangaCandidatesPerSeries: maxMangaCandidatesPerSeries
        )
        return memory
    }

    private static func pruned<Value>(
        _ values: [String: Value],
        maxEntries: Int,
        score: (Value) -> (lastDecisionAt: Date?, decisionCount: Int)
    ) -> [String: Value] {
        guard maxEntries > 0, values.count > maxEntries else { return values }

        let kept = values.sorted { lhs, rhs in
            let lhsScore = score(lhs.value)
            let rhsScore = score(rhs.value)
            switch (lhsScore.lastDecisionAt, rhsScore.lastDecisionAt) {
            case let (.some(lhsDate), .some(rhsDate)) where lhsDate != rhsDate:
                return lhsDate > rhsDate
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            default:
                if lhsScore.decisionCount != rhsScore.decisionCount {
                    return lhsScore.decisionCount > rhsScore.decisionCount
                }
                return lhs.key < rhs.key
            }
        }
        .prefix(maxEntries)

        return Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
    }

    private static func prunedCounts(_ values: [String: Int], maxEntries: Int) -> [String: Int] {
        guard maxEntries > 0, values.count > maxEntries else { return values }
        let kept = values.sorted { lhs, rhs in
            if lhs.value != rhs.value {
                return lhs.value > rhs.value
            }
            return lhs.key < rhs.key
        }
        .prefix(maxEntries)

        return Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
    }

    func mergedConservatively(with other: SableLibraryLearningMemory) -> SableLibraryLearningMemory {
        var result = self
        result.mergeConservatively(other)
        return result
    }

    mutating func mergeConservatively(_ other: SableLibraryLearningMemory) {
        for (key, incoming) in other.cleanupKindTerms {
            var merged = cleanupKindTerms[key, default: CleanupKindTermMemory()]
            for (kind, count) in incoming.kindCounts {
                merged.kindCounts[kind] = max(merged.kindCounts[kind, default: 0], count)
            }
            merged.lastDecisionAt = Self.newerDate(merged.lastDecisionAt, incoming.lastDecisionAt)
            cleanupKindTerms[key] = merged
        }

        for (key, incoming) in other.rawReadingLaneTerms {
            var merged = rawReadingLaneTerms[key, default: RawReadingLaneTermMemory()]
            for (lane, count) in incoming.laneCounts {
                merged.laneCounts[lane] = max(merged.laneCounts[lane, default: 0], count)
            }
            merged.lastDecisionAt = Self.newerDate(merged.lastDecisionAt, incoming.lastDecisionAt)
            rawReadingLaneTerms[key] = merged
        }

        for (key, incoming) in other.metadataTerms {
            var merged = metadataTerms[key, default: MetadataTermMemory()]
            merged.usedCount = max(merged.usedCount, incoming.usedCount)
            merged.dismissedCount = max(merged.dismissedCount, incoming.dismissedCount)
            merged.lastDecisionAt = Self.newerDate(merged.lastDecisionAt, incoming.lastDecisionAt)
            metadataTerms[key] = merged
        }

        for (key, incoming) in other.mangaBakaSeries {
            var merged = mangaBakaSeries[key, default: MangaBakaSeriesMemory()]
            merged.keptLocalCount = max(merged.keptLocalCount, incoming.keptLocalCount)
            for (candidateID, count) in incoming.acceptedCandidateIDs {
                merged.acceptedCandidateIDs[candidateID] = max(merged.acceptedCandidateIDs[candidateID, default: 0], count)
            }
            merged.lastDecisionAt = Self.newerDate(merged.lastDecisionAt, incoming.lastDecisionAt)
            mangaBakaSeries[key] = merged
        }

        for (key, incoming) in other.pdfTriageTerms {
            var merged = pdfTriageTerms[key, default: PDFTriageTermMemory()]
            merged.documentCount = max(merged.documentCount, incoming.documentCount)
            merged.bookCount = max(merged.bookCount, incoming.bookCount)
            merged.lastDecisionAt = Self.newerDate(merged.lastDecisionAt, incoming.lastDecisionAt)
            pdfTriageTerms[key] = merged
        }
    }

    private static func newerDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case (.none, .none):
            nil
        case (.some(let lhs), .none):
            lhs
        case (.none, .some(let rhs)):
            rhs
        case (.some(let lhs), .some(let rhs)):
            max(lhs, rhs)
        }
    }

    mutating func recordCleanupKind(
        path: String,
        proposedPath: String?,
        kind: SableLibraryCleanupKind,
        date: Date = Date()
    ) {
        let tokens = cleanupKindTokens(path: path, proposedPath: proposedPath)
        guard !tokens.isEmpty else { return }

        for token in tokens {
            var memory = cleanupKindTerms[token, default: CleanupKindTermMemory()]
            memory.kindCounts[kind.rawValue, default: 0] += 1
            memory.lastDecisionAt = date
            cleanupKindTerms[token] = memory
        }
    }

    func cleanupKindSignals(path: String, proposedPath: String?) -> [SableLibraryCleanupKindLearnedSignal] {
        cleanupKindTokens(path: path, proposedPath: proposedPath).compactMap { token in
            guard let memory = cleanupKindTerms[token],
                  let best = memory.kindCounts.max(by: { $0.value < $1.value }),
                  let kind = SableLibraryCleanupKind(rawValue: best.key) else {
                return nil
            }

            let total = memory.kindCounts.values.reduce(0, +)
            let competingCount = total - best.value
            guard best.value > competingCount else { return nil }

            return SableLibraryCleanupKindLearnedSignal(
                token: token,
                kind: kind,
                winningCount: best.value,
                competingCount: competingCount,
                confidence: best.value >= 3 ? .high : .medium
            )
        }
    }

    func cleanupKindTokens(path: String, proposedPath: String?) -> [String] {
        let combined = [path, proposedPath ?? ""]
            .joined(separator: " ")
            .lowercased()
            .replacingOccurrences(
                of: #"\.(epub|kepub|mobi|azw3?|ibooks|iba|djvu|cbz|cbr|cb7|pdf|mkv|mp4|m4v|avi|mov|wmv|webm|ts|m2ts|txt|md|rtf|docx?|pages|numbers|key|csv|json|xml|html|pptx?|xlsx?|jpe?g|png|gif|heic|heif|webp|tiff?|bmp|svg|mp3|m4a|aac|flac|wav|aiff|ogg|opus|zip|rar|7z|tar|gz|bz2|xz)\b"#,
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)

        let stopWords: Set<String> = [
            "the", "and", "for", "with", "from", "this", "that", "copy", "version",
            "final", "books", "book", "videos", "video", "documents", "document",
            "images", "image", "audio", "archives", "archive", "other", "files",
            "file", "folder", "library", "sable"
        ]

        let tokens = combined
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { token in
                token.count >= 3
                    && !token.allSatisfy(\.isNumber)
                    && !stopWords.contains(token)
            }

        return Array(Set(tokens)).sorted()
    }

    mutating func recordRawReadingLane(
        path: String,
        proposedPath: String?,
        readingType: SableLibraryReadingType,
        date: Date = Date()
    ) {
        let tokens = rawReadingLaneTokens(path: path, proposedPath: proposedPath)
        guard !tokens.isEmpty else { return }

        for token in tokens {
            var memory = rawReadingLaneTerms[token, default: RawReadingLaneTermMemory()]
            memory.laneCounts[readingType.rawValue, default: 0] += 1
            memory.lastDecisionAt = date
            rawReadingLaneTerms[token] = memory
        }
    }

    func rawReadingLaneSignals(path: String, proposedPath: String?) -> [SableLibraryRawReadingLaneLearnedSignal] {
        rawReadingLaneTokens(path: path, proposedPath: proposedPath).compactMap { token in
            guard let memory = rawReadingLaneTerms[token],
                  let best = memory.laneCounts.max(by: { $0.value < $1.value }),
                  let readingType = SableLibraryReadingType(rawValue: best.key) else {
                return nil
            }

            let total = memory.laneCounts.values.reduce(0, +)
            let competingCount = total - best.value
            guard best.value > competingCount else { return nil }

            let confidence: SableLibraryLearnedSignal.Confidence = best.value >= 3 ? .high : .medium
            return SableLibraryRawReadingLaneLearnedSignal(
                token: token,
                readingType: readingType,
                winningCount: best.value,
                competingCount: competingCount,
                confidence: confidence
            )
        }
    }

    func rawReadingLaneTokens(path: String, proposedPath: String?) -> [String] {
        let combined = [path, proposedPath ?? ""]
            .joined(separator: " ")
            .lowercased()
            .replacingOccurrences(of: #"\.(epub|kepub|mobi|azw3?|ibooks|iba|djvu|cbz|cbr|cb7|pdf)\b"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)

        let stopWords: Set<String> = [
            "the", "and", "for", "with", "from", "this", "that", "copy", "version",
            "final", "books", "book", "manga", "manhwa", "manhua", "light", "novels",
            "novel", "other", "reading"
        ]

        let tokens = combined
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { token in
                token.count >= 3
                    && !token.allSatisfy(\.isNumber)
                    && !stopWords.contains(token)
            }

        return Array(Set(tokens)).sorted()
    }

    mutating func recordMetadataUse(term: String, date: Date = Date()) {
        let key = normalizedKey(term)
        guard !key.isEmpty else { return }
        var memory = metadataTerms[key, default: MetadataTermMemory()]
        memory.usedCount += 1
        memory.lastDecisionAt = date
        metadataTerms[key] = memory
    }

    mutating func recordMetadataDismissal(term: String, date: Date = Date()) {
        let key = normalizedKey(term)
        guard !key.isEmpty else { return }
        var memory = metadataTerms[key, default: MetadataTermMemory()]
        memory.dismissedCount += 1
        memory.lastDecisionAt = date
        metadataTerms[key] = memory
    }

    func metadataSignal(for term: String) -> SableLibraryLearnedSignal? {
        let key = normalizedKey(term)
        guard let memory = metadataTerms[key] else { return nil }
        if memory.usedCount > memory.dismissedCount {
            let confidence: SableLibraryLearnedSignal.Confidence = memory.usedCount >= 3 ? .high : .medium
            return SableLibraryLearnedSignal(
                label: "Learned Use",
                detail: "\(confidence.actionLabel): you used this as a cleanup tag \(memory.usedCount) time\(memory.usedCount == 1 ? "" : "s") before and dismissed it \(memory.dismissedCount) time\(memory.dismissedCount == 1 ? "" : "s").",
                confidence: confidence
            )
        }
        if memory.dismissedCount > memory.usedCount {
            let confidence: SableLibraryLearnedSignal.Confidence = memory.dismissedCount >= 3 ? .high : .medium
            return SableLibraryLearnedSignal(
                label: "Learned Keep",
                detail: "\(confidence.actionLabel): you kept this as title text \(memory.dismissedCount) time\(memory.dismissedCount == 1 ? "" : "s") before and used it \(memory.usedCount) time\(memory.usedCount == 1 ? "" : "s").",
                confidence: confidence
            )
        }
        return SableLibraryLearnedSignal(
            label: "Mixed History",
            detail: "Check examples: you have both used and kept this term before.",
            confidence: .low
        )
    }

    mutating func recordMangaBakaUse(seriesKey: String, candidateID: String, date: Date = Date()) {
        let key = normalizedKey(seriesKey)
        let candidateKey = normalizedKey(candidateID)
        guard !key.isEmpty, !candidateKey.isEmpty else { return }
        var memory = mangaBakaSeries[key, default: MangaBakaSeriesMemory()]
        memory.acceptedCandidateIDs[candidateKey, default: 0] += 1
        memory.lastDecisionAt = date
        mangaBakaSeries[key] = memory
    }

    mutating func recordMangaBakaKeepLocal(seriesKey: String, date: Date = Date()) {
        let key = normalizedKey(seriesKey)
        guard !key.isEmpty else { return }
        var memory = mangaBakaSeries[key, default: MangaBakaSeriesMemory()]
        memory.keptLocalCount += 1
        memory.lastDecisionAt = date
        mangaBakaSeries[key] = memory
    }

    func mangaBakaSignal(seriesKey: String, candidate: MangaBakaCandidate? = nil) -> SableLibraryLearnedSignal? {
        let key = normalizedKey(seriesKey)
        guard let memory = mangaBakaSeries[key] else { return nil }

        if let candidate {
            let candidateKey = normalizedKey(candidate.mangaBakaID.isEmpty ? candidate.preferredTitle : candidate.mangaBakaID)
            let acceptedCount = memory.acceptedCandidateIDs[candidateKey, default: 0]
            guard acceptedCount > 0 else { return nil }
            return SableLibraryLearnedSignal(
                label: "Learned Match",
                detail: "Trust more: you accepted this exact match \(acceptedCount) time\(acceptedCount == 1 ? "" : "s") before.",
                confidence: acceptedCount >= 2 ? .high : .medium
            )
        }

        guard memory.keptLocalCount > 0 else { return nil }
        return SableLibraryLearnedSignal(
            label: "Learned Local",
            detail: "Be careful: you kept the local title \(memory.keptLocalCount) time\(memory.keptLocalCount == 1 ? "" : "s") before.",
            confidence: memory.keptLocalCount >= 2 ? .high : .medium
        )
    }

    mutating func recordPDFTriage(path: String, proposedPath: String?, choice: SableLibraryPDFTriageChoice, date: Date = Date()) {
        let tokens = pdfTriageTokens(path: path, proposedPath: proposedPath)
        guard !tokens.isEmpty else { return }

        for token in tokens {
            var memory = pdfTriageTerms[token, default: PDFTriageTermMemory()]
            switch choice {
            case .document:
                memory.documentCount += 1
            case .book:
                memory.bookCount += 1
            }
            memory.lastDecisionAt = date
            pdfTriageTerms[token] = memory
        }
    }

    func pdfTriageSignals(path: String, proposedPath: String?) -> [SableLibraryPDFTriageLearnedSignal] {
        pdfTriageTokens(path: path, proposedPath: proposedPath).compactMap { token in
            guard let memory = pdfTriageTerms[token] else { return nil }
            let total = memory.documentCount + memory.bookCount
            guard total > 0, memory.documentCount != memory.bookCount else { return nil }

            let choice: SableLibraryPDFTriageChoice = memory.documentCount > memory.bookCount ? .document : .book
            let winningCount = max(memory.documentCount, memory.bookCount)
            let confidence: SableLibraryLearnedSignal.Confidence = winningCount >= 3 ? .high : .medium
            return SableLibraryPDFTriageLearnedSignal(
                token: token,
                choice: choice,
                documentCount: memory.documentCount,
                bookCount: memory.bookCount,
                confidence: confidence
            )
        }
    }

    func pdfTriageTokens(path: String, proposedPath: String?) -> [String] {
        let combined = [path, proposedPath ?? ""]
            .joined(separator: " ")
            .lowercased()
            .replacingOccurrences(of: "documents/", with: " ")
            .replacingOccurrences(of: #"\.pdf\b"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)

        let stopWords: Set<String> = [
            "the", "and", "for", "with", "from", "this", "that", "pdf", "document",
            "copy", "kopie", "version", "versie", "final", "compressed", "compress"
        ]

        let tokens = combined
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { token in
                token.count >= 4
                    && !token.allSatisfy(\.isNumber)
                    && !stopWords.contains(token)
            }

        return Array(Set(tokens)).sorted()
    }

    private func normalizedKey(_ value: String) -> String {
        value
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct SableLibraryCleanupKindLearnedSignal: Sendable, Equatable {
    var token: String
    var kind: SableLibraryCleanupKind
    var winningCount: Int
    var competingCount: Int
    var confidence: SableLibraryLearnedSignal.Confidence

    var detail: String {
        "Learned cleanup clue: \(token) was marked as \(kind.folderName) \(winningCount) time\(winningCount == 1 ? "" : "s") and another kind \(competingCount) time\(competingCount == 1 ? "" : "s")."
    }
}

struct SableLibraryPDFTriageLearnedSignal: Sendable, Equatable {
    var token: String
    var choice: SableLibraryPDFTriageChoice
    var documentCount: Int
    var bookCount: Int
    var confidence: SableLibraryLearnedSignal.Confidence

    var detail: String {
        switch choice {
        case .document:
            "Learned document clue: \(token) was marked as document \(documentCount) time\(documentCount == 1 ? "" : "s") and book \(bookCount) time\(bookCount == 1 ? "" : "s")."
        case .book:
            "Learned book clue: \(token) was marked as book \(bookCount) time\(bookCount == 1 ? "" : "s") and document \(documentCount) time\(documentCount == 1 ? "" : "s")."
        }
    }
}

struct SableLibraryRawReadingLaneLearnedSignal: Sendable, Equatable {
    var token: String
    var readingType: SableLibraryReadingType
    var winningCount: Int
    var competingCount: Int
    var confidence: SableLibraryLearnedSignal.Confidence

    var detail: String {
        "Learned reading lane clue: \(token) was marked as \(readingType.folderName) \(winningCount) time\(winningCount == 1 ? "" : "s") and another lane \(competingCount) time\(competingCount == 1 ? "" : "s")."
    }
}

nonisolated struct SableLibraryLearnedSignal: Sendable, Equatable {
    enum Confidence: Sendable, Equatable {
        case low
        case medium
        case high
    }

    let label: String
    let detail: String
    let confidence: Confidence

    var role: SableLibraryStatusRole {
        switch confidence {
        case .low: .review
        case .medium: .info
        case .high: .success
        }
    }

    var confidenceLabel: String {
        switch confidence {
        case .low: "Needs Review"
        case .medium: "Some History"
        case .high: "Strong History"
        }
    }
}

extension SableLibraryLearnedSignal.Confidence {
    nonisolated var actionLabel: String {
        switch self {
        case .low: "Check"
        case .medium: "Consider"
        case .high: "Likely"
        }
    }
}
