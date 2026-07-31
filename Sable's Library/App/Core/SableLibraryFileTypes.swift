//
//  SableLibraryFileTypes.swift
//  Sable's Library
//

import Foundation
import UniformTypeIdentifiers

struct SableLibraryFileTypeMatcher: Sendable {
    private let bookExtensions: Set<String>
    private let videoExtensions: Set<String>
    private let packageExtensions: Set<String>
    private let bookTypes: Set<UTType>
    private let videoTypes: Set<UTType>
    private let packageTypes: Set<UTType>

    init(config: SableLibraryConfig) {
        self.bookExtensions = Self.normalizedExtensions(config.bookExtensions)
        self.videoExtensions = Self.normalizedExtensions(config.videoExtensions)
        self.packageExtensions = Self.normalizedExtensions(config.packageExtensions)
        self.bookTypes = Self.types(for: bookExtensions)
        self.videoTypes = Self.types(for: videoExtensions)
        self.packageTypes = Self.types(for: packageExtensions)
    }

    func isBook(url: URL, isDirectory: Bool) -> Bool {
        let normalizedExtension = Self.normalizedExtension(url.pathExtension)
        let configuredExtensions = isDirectory ? packageExtensions : bookExtensions
        guard configuredExtensions.contains(normalizedExtension) else { return false }

        let configuredTypes = isDirectory ? packageTypes : bookTypes
        guard let type = UTType(filenameExtension: url.pathExtension), !configuredTypes.isEmpty else {
            return true
        }

        return configuredTypes.contains { type.conforms(to: $0) || $0.conforms(to: type) }
    }

    func isVideo(url: URL, isDirectory: Bool) -> Bool {
        guard !isDirectory else { return false }
        let normalizedExtension = Self.normalizedExtension(url.pathExtension)
        guard videoExtensions.contains(normalizedExtension) else { return false }

        guard let type = UTType(filenameExtension: url.pathExtension), !videoTypes.isEmpty else {
            return true
        }

        return type.conforms(to: .movie)
            || type.conforms(to: .video)
            || videoTypes.contains { type.conforms(to: $0) || $0.conforms(to: type) }
    }

    func mediaDomain(url: URL, isDirectory: Bool) -> SableLibraryMediaDomain {
        if isBook(url: url, isDirectory: isDirectory) {
            return .reading
        }
        if isVideo(url: url, isDirectory: isDirectory) {
            return .watching
        }
        return .unknown
    }

    func displayTypeName(for url: URL) -> String {
        if let type = UTType(filenameExtension: url.pathExtension) {
            return type.localizedDescription ?? type.identifier
        }
        let ext = Self.normalizedExtension(url.pathExtension)
        return ext.isEmpty ? "Unknown file" : ext.uppercased().replacingOccurrences(of: ".", with: "")
    }

    private static func normalizedExtensions(_ extensions: [String]) -> Set<String> {
        Set(extensions.map { Self.normalizedExtension($0) }.filter { !$0.isEmpty })
    }

    private static func normalizedExtension(_ ext: String) -> String {
        let trimmed = ext.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return "" }
        return trimmed.hasPrefix(".") ? trimmed : ".\(trimmed)"
    }

    private static func types(for extensions: Set<String>) -> Set<UTType> {
        Set(extensions.compactMap { ext in
            UTType(filenameExtension: ext.replacingOccurrences(of: ".", with: ""))
        })
    }
}

struct SableLibraryCleanupKindClassification: Sendable, Equatable {
    var kind: SableLibraryCleanupKind
    var folderName: String
    var confidence: LibraryPlanConfidence
    var requiresReview: Bool
    var explanation: String
    var reviewTags: [String]
}

struct SableLibraryCleanupKindClassifier: Sendable {
    private let matcher: SableLibraryFileTypeMatcher
    private let learningMemory: SableLibraryLearningMemory
    private let useLocalLearning: Bool

    init(
        config: SableLibraryConfig,
        learningMemory: SableLibraryLearningMemory = SableLibraryLearningMemory(),
        useLocalLearning: Bool = false
    ) {
        self.matcher = SableLibraryFileTypeMatcher(config: config)
        self.learningMemory = learningMemory
        self.useLocalLearning = useLocalLearning
    }

    func classify(
        item: LibraryItem,
        proposedPath: String? = nil,
        directChildren: [LibraryItem] = []
    ) -> SableLibraryCleanupKindClassification {
        var state = SableLibraryCleanupKindScoringState()
        let ext = item.url.pathExtension.lowercased()
        let text = normalizedText([item.relativePath, item.name, proposedPath ?? ""].joined(separator: " "))

        addExtensionEvidence(
            ext,
            url: item.url,
            isDirectory: item.isDirectory,
            state: &state
        )
        addTextEvidence(text, state: &state)
        addChildEvidence(directChildren, state: &state)
        addLearningEvidence(path: item.relativePath, proposedPath: proposedPath, state: &state)

        return resolvedClassification(from: state, fallback: fallbackKind(for: item))
    }

    private func addExtensionEvidence(
        _ ext: String,
        url: URL,
        isDirectory: Bool,
        state: inout SableLibraryCleanupKindScoringState
    ) {
        guard !isDirectory else { return }

        if matcher.isVideo(url: url, isDirectory: false) {
            state.add(.watching, 4.5, "video extension .\(ext)")
            return
        }

        if readingExtensions.contains(ext) {
            state.add(.reading, ext == "pdf" ? 1.3 : 4.0, ext == "pdf" ? "PDF can be reading or document" : "reading extension .\(ext)")
            return
        }

        if documentExtensions.contains(ext) {
            state.add(.document, 4.0, "document extension .\(ext)")
            return
        }
        if imageExtensions.contains(ext) {
            state.add(.image, 4.0, "image extension .\(ext)")
            return
        }
        if audioExtensions.contains(ext) {
            state.add(.audio, 4.0, "audio extension .\(ext)")
            return
        }
        if archiveExtensions.contains(ext) {
            state.add(.archive, 4.0, "archive extension .\(ext)")
            return
        }

        if let type = UTType(filenameExtension: ext) {
            if type.conforms(to: .movie) || type.conforms(to: .video) {
                state.add(.watching, 3.8, "system video type")
            } else if type.conforms(to: .image) {
                state.add(.image, 3.8, "system image type")
            } else if type.conforms(to: .audio) {
                state.add(.audio, 3.8, "system audio type")
            } else if type.conforms(to: .archive) {
                state.add(.archive, 3.8, "system archive type")
            } else if type.conforms(to: .text) || type.conforms(to: .content) {
                state.add(.document, 2.5, "system document-like type")
            }
        }
    }

    private func addTextEvidence(_ text: String, state: inout SableLibraryCleanupKindScoringState) {
        addTermEvidence(text, terms: readingTerms, kind: .reading, weight: 2.5, label: "reading wording", state: &state)
        addTermEvidence(text, terms: watchingTerms, kind: .watching, weight: 2.7, label: "video wording", state: &state)
        addTermEvidence(text, terms: documentTerms, kind: .document, weight: 2.4, label: "document wording", state: &state)
        addTermEvidence(text, terms: imageTerms, kind: .image, weight: 2.4, label: "image wording", state: &state)
        addTermEvidence(text, terms: audioTerms, kind: .audio, weight: 2.4, label: "audio wording", state: &state)
        addTermEvidence(text, terms: archiveTerms, kind: .archive, weight: 2.2, label: "archive wording", state: &state)

        if text.range(of: #"\bs\d{1,2}e\d{1,3}\b"#, options: .regularExpression) != nil {
            state.add(.watching, 2.4, "episode marker")
        }
        if text.range(of: #"\bvol(?:ume)?\s+\d{1,4}\b"#, options: .regularExpression) != nil {
            state.add(.reading, 1.8, "volume marker")
        }
    }

    private func addChildEvidence(
        _ directChildren: [LibraryItem],
        state: inout SableLibraryCleanupKindScoringState
    ) {
        let children = directChildren.filter { !$0.isDirectory }
        guard !children.isEmpty else { return }

        var counts: [SableLibraryCleanupKind: Int] = [:]
        for child in children {
            let ext = child.url.pathExtension.lowercased()
            if matcher.isVideo(url: child.url, isDirectory: false) {
                counts[.watching, default: 0] += 1
            } else if readingExtensions.contains(ext), ext != "pdf" {
                counts[.reading, default: 0] += 1
            } else if imageExtensions.contains(ext) {
                counts[.image, default: 0] += 1
            } else if audioExtensions.contains(ext) {
                counts[.audio, default: 0] += 1
            } else if archiveExtensions.contains(ext) {
                counts[.archive, default: 0] += 1
            } else if documentExtensions.contains(ext) || ext == "pdf" {
                counts[.document, default: 0] += 1
            }
        }

        guard let best = counts.max(by: { $0.value < $1.value }) else { return }
        let totalKnown = counts.values.reduce(0, +)
        let ratio = Double(best.value) / Double(max(children.count, 1))
        let detail = "\(best.value) of \(children.count) direct file(s) look like \(best.key.folderName)"
        let weight = ratio >= 0.85 ? 4.0 : (ratio >= 0.6 ? 2.4 : 1.0)
        state.add(best.key, weight, detail)

        if counts.count > 1, totalKnown > 0, ratio < 0.75 {
            state.add(.other, 2.0, "mixed direct child file types")
        }
    }

    private func addLearningEvidence(
        path: String,
        proposedPath: String?,
        state: inout SableLibraryCleanupKindScoringState
    ) {
        guard useLocalLearning else { return }
        for signal in learningMemory.cleanupKindSignals(path: path, proposedPath: proposedPath) {
            let weight = signal.confidence == .high ? 2.8 : 1.5
            state.add(signal.kind, weight, signal.detail)
        }
    }

    private func resolvedClassification(
        from state: SableLibraryCleanupKindScoringState,
        fallback: SableLibraryCleanupKind
    ) -> SableLibraryCleanupKindClassification {
        let sorted = state.scores.sorted { lhs, rhs in
            if lhs.value != rhs.value {
                return lhs.value > rhs.value
            }
            return sortIndex(lhs.key) < sortIndex(rhs.key)
        }
        let winner = sorted.first?.key ?? fallback
        let winningScore = sorted.first?.value ?? 0
        let runnerUpScore = sorted.dropFirst().first?.value ?? 0
        let margin = winningScore - runnerUpScore
        let resolved = winningScore > 0 ? winner : fallback
        let requiresReview = resolved == .other || winningScore < 2.2 || margin < 0.65
        let confidence: LibraryPlanConfidence
        if winningScore >= 4.2, margin >= 1.1 {
            confidence = .high
        } else if winningScore >= 2.2, margin >= 0.65 {
            confidence = .medium
        } else {
            confidence = .low
        }

        let evidence = state.evidence[resolved] ?? []
        let evidenceText = evidence.isEmpty ? "fallback cleanup kind" : Array(evidence.prefix(4)).joined(separator: "; ")
        var reviewTags = [
            "cleanup-kind",
            "cleanup-kind-\(resolved.rawValue)",
            requiresReview ? "cleanup-kind-review" : "cleanup-kind-auto"
        ]
        if evidence.contains(where: { $0.contains("Learned cleanup clue") }) {
            reviewTags.append("learned-cleanup-kind")
        }
        return SableLibraryCleanupKindClassification(
            kind: resolved,
            folderName: resolved.folderName,
            confidence: confidence,
            requiresReview: requiresReview,
            explanation: "Cleanup kind: \(resolved.folderName). Evidence: \(evidenceText). Score \(formatted(winningScore)), margin \(formatted(margin)).",
            reviewTags: reviewTags
        )
    }

    private func addTermEvidence(
        _ text: String,
        terms: [String],
        kind: SableLibraryCleanupKind,
        weight: Double,
        label: String,
        state: inout SableLibraryCleanupKindScoringState
    ) {
        let matches = terms.filter { text.contains($0) }
        guard !matches.isEmpty else { return }
        state.add(kind, Double(matches.count) * weight, "\(label): \(matches.prefix(3).joined(separator: ", "))")
    }

    private func fallbackKind(for item: LibraryItem) -> SableLibraryCleanupKind {
        .other
    }

    private func normalizedText(_ value: String) -> String {
        let cleaned = value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: #"[{}\[\]()]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "" : " \(cleaned) "
    }

    private func formatted(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private func sortIndex(_ kind: SableLibraryCleanupKind) -> Int {
        switch kind {
        case .reading: 0
        case .watching: 1
        case .document: 2
        case .image: 3
        case .audio: 4
        case .archive: 5
        case .other: 6
        }
    }

    private var readingExtensions: Set<String> {
        ["epub", "kepub", "mobi", "azw", "azw3", "ibooks", "iba", "djvu", "cbz", "cbr", "cb7", "cbt", "pdf"]
    }

    private var documentExtensions: Set<String> {
        ["txt", "md", "rtf", "doc", "docx", "pages", "numbers", "key", "csv", "json", "xml", "html", "pdf", "ppt", "pptx", "xls", "xlsx"]
    }

    private var imageExtensions: Set<String> {
        ["jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "tiff", "tif", "bmp", "svg"]
    }

    private var audioExtensions: Set<String> {
        ["mp3", "m4a", "aac", "flac", "wav", "aiff", "ogg", "opus"]
    }

    private var archiveExtensions: Set<String> {
        ["zip", "rar", "7z", "tar", "gz", "bz2", "xz"]
    }

    private var readingTerms: [String] {
        [" book ", " books ", " novel ", " manga ", " manhwa ", " manhua ", " comic ", " comics ", " epub ", " chapter ", " volume "]
    }

    private var watchingTerms: [String] {
        [" movie ", " movies ", " video ", " videos ", " episode ", " season ", " anime ", " tv ", " ova ", " ona ", " special "]
    }

    private var documentTerms: [String] {
        [" receipt ", " invoice ", " statement ", " tax ", " loonstrook ", " payslip ", " contract ", " form ", " manual ", " report ", " notes ", " paperwork ", " document "]
    }

    private var imageTerms: [String] {
        [" image ", " images ", " photo ", " photos ", " picture ", " pictures ", " scan ", " scans ", " screenshot ", " screenshots ", " cover ", " artwork ", " portrait ", " wallpaper "]
    }

    private var audioTerms: [String] {
        [" audio ", " music ", " song ", " songs ", " album ", " voice ", " recording ", " podcast ", " audiobook "]
    }

    private var archiveTerms: [String] {
        [" archive ", " backup ", " zip ", " dump ", " export ", " package "]
    }
}

private struct SableLibraryCleanupKindScoringState {
    var scores: [SableLibraryCleanupKind: Double] = [:]
    var evidence: [SableLibraryCleanupKind: [String]] = [:]

    mutating func add(_ kind: SableLibraryCleanupKind, _ score: Double, _ detail: String) {
        scores[kind, default: 0] += score
        evidence[kind, default: []].append(detail)
    }
}
