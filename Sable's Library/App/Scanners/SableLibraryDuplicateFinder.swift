//
//  SableLibraryDuplicateFinder.swift
//  Sable's Library
//

import Foundation

extension SableLibraryService {
    struct DuplicateGroup: Sendable {
        let key: String
        let items: [LibraryItem]
    }

    func duplicateGroups(root: URL, config: SableLibraryConfig) throws -> [DuplicateGroup] {
        try duplicateGroups(root: root, config: config, cleanupOptions: CleanupOptions(treatPDFsAsBooks: true))
    }

    func duplicateGroups(
        root: URL,
        config: SableLibraryConfig,
        cleanupOptions: CleanupOptions
    ) throws -> [DuplicateGroup] {
        let items = try enumerateItems(root: root, config: config)
        let books = bookItems(in: items, root: root, config: config, cleanupOptions: cleanupOptions)
            .filter { !$0.isDirectory }
        let bySize = Dictionary(grouping: books, by: \.fileSize).filter { $0.key > 0 && $0.value.count > 1 }
        var groups: [DuplicateGroup] = []

        for (_, candidates) in bySize {
            var byFingerprint: [String: [LibraryItem]] = [:]
            for item in candidates {
                try checkForCancellation()
                reportProgress("Reading duplicate fingerprint: \(item.relativePath)")
                let fingerprint = try fileFingerprint(item.url)
                byFingerprint[fingerprint, default: []].append(item)
            }
            for (key, matches) in byFingerprint where matches.count > 1 {
                groups.append(DuplicateGroup(key: key, items: matches.sorted { $0.relativePath < $1.relativePath }))
            }
        }

        return groups.sorted { $0.items[0].relativePath < $1.items[0].relativePath }
    }

    func duplicateReviewGroups(root: URL, config: SableLibraryConfig, exactGroups existingExactGroups: [DuplicateGroup]? = nil) throws -> [DuplicateReviewGroup] {
        let exactSourceGroups = try existingExactGroups ?? duplicateGroups(root: root, config: config)
        return duplicateReviewGroups(from: exactSourceGroups)
    }

    func duplicateReviewGroups(
        root: URL,
        config: SableLibraryConfig,
        cleanupOptions: CleanupOptions,
        exactGroups existingExactGroups: [DuplicateGroup]? = nil
    ) throws -> [DuplicateReviewGroup] {
        let exactSourceGroups = try existingExactGroups ?? duplicateGroups(
            root: root,
            config: config,
            cleanupOptions: cleanupOptions
        )
        return duplicateReviewGroups(from: exactSourceGroups)
    }

    private func duplicateReviewGroups(from exactSourceGroups: [DuplicateGroup]) -> [DuplicateReviewGroup] {
        return exactSourceGroups.map { group in
            reviewGroup(
                key: "exact:\(group.key)",
                items: group.items,
                kind: .exactContent,
                note: "Exact file match. Keeping one copy is usually enough."
            )
        }.sorted {
            ($0.suggestedKeeperPath ?? $0.paths.first ?? "").localizedCaseInsensitiveCompare($1.suggestedKeeperPath ?? $1.paths.first ?? "") == .orderedAscending
        }
    }

    private func reviewGroup(key: String, items: [LibraryItem], kind: DuplicateReviewGroup.Kind, note: String) -> DuplicateReviewGroup {
        let sortedItems = items.sorted { duplicateKeeperSort($0, $1) }
        let sizes = Dictionary(uniqueKeysWithValues: sortedItems.map { ($0.relativePath, $0.fileSize) })
        return DuplicateReviewGroup(
            fingerprint: key,
            paths: sortedItems.map(\.relativePath),
            fileSizes: sizes,
            kind: kind,
            suggestedKeeperPath: sortedItems.first?.relativePath,
            note: duplicateKeeperNote(for: sortedItems.first, fallback: note)
        )
    }

    private func duplicateKeeperSort(_ lhs: LibraryItem, _ rhs: LibraryItem) -> Bool {
        let lhsRank = duplicateKeeperRank(lhs)
        let rhsRank = duplicateKeeperRank(rhs)
        if lhsRank != rhsRank {
            return lhsRank < rhsRank
        }
        if lhs.fileSize != rhs.fileSize {
            return lhs.fileSize > rhs.fileSize
        }
        return lhs.relativePath.localizedCaseInsensitiveCompare(rhs.relativePath) == .orderedAscending
    }

    private func duplicateKeeperRank(_ item: LibraryItem) -> Int {
        let ext = item.url.pathExtension.lowercased()
        if ext == "epub", !looksLikeAppleEPUB(item) { return 0 }
        if ext == "pdf" { return 1 }
        if ext == "epub" { return 2 }
        return 3
    }

    private func looksLikeAppleEPUB(_ item: LibraryItem) -> Bool {
        guard item.url.pathExtension.lowercased() == "epub" else { return false }
        let normalized = normalizeTerm(item.relativePath)
        return normalized.contains("apple epub")
            || normalized.contains("apple books")
            || normalized.contains("ibooks")
            || normalized.contains("itunes")
    }

    private func duplicateKeeperNote(for item: LibraryItem?, fallback: String) -> String {
        guard let item else { return fallback }
        if item.url.pathExtension.lowercased() == "epub", !looksLikeAppleEPUB(item) {
            return fallback
        }
        if item.url.pathExtension.lowercased() == "pdf" {
            return "Suggested keeper: PDF is the strongest available format in this group."
        }
        return fallback
    }

    func fileFingerprint(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hash: UInt64 = 1_469_598_103_934_665_603
        while true {
            try checkForCancellation()
            let data = handle.readData(ofLength: 1024 * 1024)
            guard !data.isEmpty else { break }
            for byte in data {
                hash ^= UInt64(byte)
                hash &*= 1_099_511_628_211
            }
        }

        return String(hash, radix: 16)
    }
}
