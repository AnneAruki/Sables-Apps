//
//  SableLibraryIntelligence.swift
//  Sable's Library
//

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

struct SableLibraryIntelligenceAvailability: Sendable, Equatable {
    let isAvailable: Bool
    let title: String
    let detail: String

    static let unavailableInSDK = SableLibraryIntelligenceAvailability(
        isAvailable: false,
        title: "Apple Intelligence unavailable",
        detail: "This build SDK does not include Foundation Models. The app will keep using local learning and deterministic suggestions instead."
    )
}

struct SableLibraryIntelligence: Sendable {
    static var availability: SableLibraryIntelligenceAvailability {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return foundationModelAvailability()
        }
        return SableLibraryIntelligenceAvailability(
            isAvailable: false,
            title: "Apple Intelligence unavailable",
            detail: "Foundation Models require macOS 26 or later. On this macOS version, the app will keep using local learning and deterministic suggestions instead."
        )
        #else
        return .unavailableInSDK
        #endif
    }

    static func cleanupReviewNote(for moves: [PlannedMove], options: SableLibraryIntelligenceOptions) async -> String? {
        guard options.improveSuggestions else { return nil }
        guard !moves.isEmpty else { return nil }

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return await foundationCleanupReviewNote(for: moves)
        }
        #endif

        return nil
    }

    static func tagReviewNote(for candidates: [MetadataCandidate], options: SableLibraryIntelligenceOptions) async -> String? {
        guard options.improveSuggestions else { return nil }
        guard !candidates.isEmpty else { return nil }

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return await foundationTagReviewNote(for: candidates)
        }
        #endif

        return nil
    }

    static func missingNumberReviewNote(for items: [LibraryItem], options: SableLibraryIntelligenceOptions) async -> String? {
        guard options.improveSuggestions else { return nil }
        guard !items.isEmpty else { return nil }

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return await foundationMissingNumberReviewNote(for: items)
        }
        #endif

        return nil
    }

    static func duplicateReviewNote(for groups: [SableLibraryService.DuplicateGroup], options: SableLibraryIntelligenceOptions) async -> String? {
        guard options.improveSuggestions else { return nil }
        guard !groups.isEmpty else { return nil }

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return await foundationDuplicateReviewNote(for: groups)
        }
        #endif

        return nil
    }

    static func unavailableNote(options: SableLibraryIntelligenceOptions) -> String? {
        guard options.improveSuggestions else { return nil }
        let availability = availability
        guard !availability.isAvailable else { return nil }
        return "Apple Intelligence suggestions were requested, but \(availability.detail)"
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private static func foundationModelAvailability() -> SableLibraryIntelligenceAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return SableLibraryIntelligenceAvailability(
                isAvailable: true,
                title: "Apple Intelligence available",
                detail: "On-device Foundation Models can improve review notes without changing files automatically."
            )
        case .unavailable(.deviceNotEligible):
            return SableLibraryIntelligenceAvailability(
                isAvailable: false,
                title: "Apple Intelligence unavailable",
                detail: "This Mac does not support Apple Intelligence. The app will keep using local learning and deterministic suggestions instead."
            )
        case .unavailable(.appleIntelligenceNotEnabled):
            return SableLibraryIntelligenceAvailability(
                isAvailable: false,
                title: "Apple Intelligence off",
                detail: "Apple Intelligence is not enabled in System Settings. The app will keep using local learning and deterministic suggestions instead."
            )
        case .unavailable(.modelNotReady):
            return SableLibraryIntelligenceAvailability(
                isAvailable: false,
                title: "Apple Intelligence preparing",
                detail: "The on-device model is not ready yet. The app will keep using local learning and deterministic suggestions instead."
            )
        case .unavailable(_):
            return SableLibraryIntelligenceAvailability(
                isAvailable: false,
                title: "Apple Intelligence unavailable",
                detail: "The on-device model is not available right now. The app will keep using local learning and deterministic suggestions instead."
            )
        }
    }

    @available(macOS 26.0, *)
    private static func foundationCleanupReviewNote(for moves: [PlannedMove]) async -> String? {
        let sample = moves.prefix(16).map { move in
            "- Reason: \(move.reason)\n  From: \(move.fromPath)\n  To: \(move.toPath)"
        }.joined(separator: "\n")

        let instructions = """
        You review library cleanup suggestions for a macOS app. Be conservative. Do not invent facts. Do not say a move is safe unless the paths make that clear. Return short review notes only.
        """

        let prompt = """
        Review these planned file moves. Give up to five concise bullets that help someone review the suggestions. Mention higher-risk patterns, manual-review cases, or obvious consistency wins. Do not ask the app to move files.

        Planned moves:
        \(sample)
        """

        return await reviewNote(title: "Apple Intelligence review notes", instructions: instructions, prompt: prompt)
    }

    @available(macOS 26.0, *)
    private static func foundationTagReviewNote(for candidates: [MetadataCandidate]) async -> String? {
        let sample = candidates.prefix(20).map { candidate in
            var lines = ["- Term: \(candidate.term)", "  Count: \(candidate.count)"]
            lines.append(contentsOf: candidate.examples.prefix(3).map { "  Example: \($0)" })
            return lines.joined(separator: "\n")
        }.joined(separator: "\n")

        let instructions = """
        You review library metadata candidates for a macOS app. Be conservative. Do not invent title facts. Do not decide for the person. Return short review notes only.
        """

        let prompt = """
        Review these bracket metadata candidates. Give up to five concise bullets that help someone decide which terms are likely source notes versus real title text. Use the examples as evidence. Do not ask the app to change rules automatically.

        Metadata candidates:
        \(sample)
        """

        return await reviewNote(title: "Apple Intelligence metadata notes", instructions: instructions, prompt: prompt)
    }

    @available(macOS 26.0, *)
    private static func foundationMissingNumberReviewNote(for items: [LibraryItem]) async -> String? {
        let sample = items.prefix(20).map { "- \($0.relativePath)" }.joined(separator: "\n")

        let instructions = """
        You review file names that may have missing volume or chapter numbers. Be conservative. Do not infer missing numbers. Return short review notes only.
        """

        let prompt = """
        Review these possible missing volume or chapter numbers. Give up to five concise bullets that help a person spot patterns, false positives, or folders that may need manual attention. Do not suggest exact replacement numbers.

        Possible missing numbers:
        \(sample)
        """

        return await reviewNote(title: "Apple Intelligence missing number notes", instructions: instructions, prompt: prompt)
    }

    @available(macOS 26.0, *)
    private static func foundationDuplicateReviewNote(for groups: [SableLibraryService.DuplicateGroup]) async -> String? {
        let sample = groups.prefix(12).map { group in
            let paths = group.items.prefix(4).map { "  - \($0.relativePath)" }.joined(separator: "\n")
            return "- Fingerprint: \(group.key)\n\(paths)"
        }.joined(separator: "\n")

        let instructions = """
        You review exact duplicate file groups for a macOS app. The duplicate detection is deterministic, but removal choices need user review. Be conservative and brief.
        """

        let prompt = """
        Review these exact duplicate groups. Give up to five concise bullets that help a person decide what to inspect first. Mention folder patterns, naming differences, or cases where keeping multiple copies may make sense. Do not ask the app to delete files.

        Duplicate groups:
        \(sample)
        """

        return await reviewNote(title: "Apple Intelligence duplicate notes", instructions: instructions, prompt: prompt)
    }

    @available(macOS 26.0, *)
    private static func reviewNote(title: String, instructions: String, prompt: String) async -> String? {
        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: prompt)
            guard let content = sanitizedReviewNoteContent(response.content) else { return nil }
            return "\(title):\n\(content)"
        } catch {
            return "Apple Intelligence suggestions were requested, but the on-device model could not complete the review: \(error.localizedDescription)"
        }
    }

    private static func sanitizedReviewNoteContent(_ rawContent: String) -> String? {
        let lines = rawContent
            .split(whereSeparator: \.isNewline)
            .map { line in
                String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
            .prefix(6)
        let content = lines.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return nil }
        guard content.count > 900 else { return content }
        return String(content.prefix(900)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
    #endif
}
