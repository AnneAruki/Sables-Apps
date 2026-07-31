//
//  SableLibraryTagReviewner.swift
//  Sable's Library
//

import Foundation

extension SableLibraryService {
    func metadataCandidates(root: URL, config: SableLibraryConfig) throws -> [String] {
        try metadataCandidateEntries(root: root, config: config).map { "\($0.term) (\($0.count))" }
    }

    func sourceMetadataTermKeys(root: URL, config: SableLibraryConfig) throws -> Set<String> {
        try metadataScanSummary(root: root, config: config).sourceTermKeys
    }

    func metadataCandidateEntries(root: URL, config: SableLibraryConfig) throws -> [MetadataCandidate] {
        try metadataScanSummary(root: root, config: config).candidates
    }

    func metadataScanSummary(root: URL, config: SableLibraryConfig) throws -> MetadataScanSummary {
        try metadataScanSummary(root: root, config: config, cleanupOptions: CleanupOptions(treatPDFsAsBooks: true))
    }

    func metadataScanSummary(
        root: URL,
        config: SableLibraryConfig,
        cleanupOptions: CleanupOptions
    ) throws -> MetadataScanSummary {
        let items = try enumerateItems(root: root, config: config)
        let readingPaths = Set(bookItems(in: items, root: root, config: config, cleanupOptions: cleanupOptions).map(\.relativePath))
        let observations = metadataTagObservations(in: items, readingPaths: readingPaths)
        let sourceTermKeys = inferredSourceMetadataTermKeys(from: observations, config: config)
        var counts: [String: Int] = [:]
        var examples: [String: [String]] = [:]

        for observation in observations {
            try checkForCancellation()
            reportProgress("Reading metadata clues: \(observation.relativePath)")
            guard !sourceTermKeys.contains(observation.key) else { continue }

            let normalizedCandidate = metadataCandidateKey(observation.term)
            guard !normalizedCandidate.isEmpty else { continue }
            counts[normalizedCandidate, default: 0] += 1
            if examples[normalizedCandidate, default: []].count < 4 {
                examples[normalizedCandidate, default: []].append(observation.relativePath)
            }
        }

        let candidates = counts.sorted { lhs, rhs in
            if lhs.value == rhs.value {
                return lhs.key.localizedStandardCompare(rhs.key) == .orderedAscending
            }
            return lhs.value > rhs.value
        }.map { MetadataCandidate(term: $0.key, count: $0.value, examples: examples[$0.key] ?? []) }

        return MetadataScanSummary(candidates: candidates, sourceTermKeys: sourceTermKeys)
    }

    private func metadataCandidateKey(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .lowercased()
    }

    private struct MetadataTagObservation {
        var term: String
        var key: String
        var relativePath: String
        var isTrailingSourceStack: Bool
        var trailingStackCount: Int
    }

    private func metadataTagObservations(
        in items: [LibraryItem],
        readingPaths: Set<String>
    ) -> [MetadataTagObservation] {
        let tagRegex = try? NSRegularExpression(pattern: #"\[([^\]]{2,80})\]"#)
        guard let tagRegex else { return [] }

        var observations: [MetadataTagObservation] = []
        for item in items where readingPaths.contains(item.relativePath) || item.isDirectory {
            let name = item.url.deletingPathExtension().lastPathComponent
            let fullRange = NSRange(name.startIndex..<name.endIndex, in: name)
            let tagMatches = tagRegex.matches(in: name, range: fullRange)
            guard !tagMatches.isEmpty else { continue }

            let trailingRange = trailingSquareBracketStackRange(in: name).map { NSRange($0, in: name) }
            let trailingStackCount = trailingRange.map { stackRange in
                tagMatches.filter { NSIntersectionRange($0.range(at: 0), stackRange).length == $0.range(at: 0).length }.count
            } ?? 0

            for match in tagMatches {
                guard let termRange = Range(match.range(at: 1), in: name) else { continue }
                let term = String(name[termRange])
                let key = normalizeTerm(term)
                guard !key.isEmpty else { continue }

                let isTrailing = trailingRange.map {
                    NSIntersectionRange(match.range(at: 0), $0).length == match.range(at: 0).length
                } ?? false
                observations.append(MetadataTagObservation(
                    term: term,
                    key: key,
                    relativePath: item.relativePath,
                    isTrailingSourceStack: isTrailing,
                    trailingStackCount: trailingStackCount
                ))
            }
        }
        return observations
    }

    private func trailingSquareBracketStackRange(in value: String) -> Range<String.Index>? {
        var scanEnd = value.endIndex
        var stackStart: String.Index?

        while let noteRange = trailingSquareBracketNoteRange(in: value, before: scanEnd) {
            stackStart = noteRange.lowerBound
            scanEnd = noteRange.lowerBound
        }

        guard let stackStart else { return nil }
        return stackStart..<value.endIndex
    }

    private func trailingSquareBracketNoteRange(
        in value: String,
        before end: String.Index
    ) -> Range<String.Index>? {
        var contentEnd = end
        while contentEnd > value.startIndex {
            let previous = value.index(before: contentEnd)
            guard value[previous].isWhitespace else { break }
            contentEnd = previous
        }
        guard contentEnd > value.startIndex else { return nil }

        let closeIndex = value.index(before: contentEnd)
        guard value[closeIndex] == "]",
              let openIndex = value[..<closeIndex].lastIndex(of: "[") else {
            return nil
        }

        let contentStart = value.index(after: openIndex)
        let contentLength = value[contentStart..<closeIndex].count
        guard (2...80).contains(contentLength) else { return nil }

        var fullStart = openIndex
        while fullStart > value.startIndex {
            let previous = value.index(before: fullStart)
            guard value[previous].isWhitespace else { break }
            fullStart = previous
        }
        return fullStart..<end
    }

    private func inferredSourceMetadataTermKeys(
        from observations: [MetadataTagObservation],
        config: SableLibraryConfig
    ) -> Set<String> {
        var keys = Set(config.sourceMetadataTerms.map(normalizeTerm))
        let grouped = Dictionary(grouping: observations, by: \.key)

        for (key, values) in grouped {
            let trailingCount = values.filter(\.isTrailingSourceStack).count
            let appearsInStack = values.contains { $0.isTrailingSourceStack && $0.trailingStackCount >= 2 }
            if trailingCount >= 2 || appearsInStack || values.contains(where: isPublisherLikeSourceTag) {
                keys.insert(key)
            }
        }

        return keys
    }

    private func isPublisherLikeSourceTag(_ observation: MetadataTagObservation) -> Bool {
        guard observation.isTrailingSourceStack else { return false }
        let key = observation.key
        let sourceWords = [
            "club", "premium", "kobo", "kindle", "digital", "media", "press",
            "publisher", "scan", "scans", "play", "edition", "seas", "tokyopop",
            "books", "manga"
        ]
        return sourceWords.contains { key.contains($0) }
    }
}
