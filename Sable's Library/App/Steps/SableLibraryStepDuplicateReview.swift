//
//  SableLibraryStepDuplicateReview.swift
//  Sable's Library
//

import Foundation

nonisolated struct SableLibraryStepDuplicateReview: Sendable {
    func prepare(context: LibraryPipelineContext, service: SableLibraryService) async -> [LibraryPlanGroup] {
        guard let inspection = context.inspection,
              !inspection.duplicateCandidates.isEmpty else {
            return []
        }

        let config = service.currentConfig()
        let exactDuplicateCandidates = inspection.duplicateCandidates.filter { $0.kind == DuplicateReviewGroup.Kind.exactContent.rawValue }
        var items: [LibraryPlanItem] = []
        var examples: [LibraryPlanExample] = []

        for (index, group) in exactDuplicateCandidates.enumerated() {
            reportDuplicateProgress(
                service: service,
                message: "Checking duplicate group \(index + 1) of \(exactDuplicateCandidates.count).",
                completed: index + 1,
                total: exactDuplicateCandidates.count
            )
            let keeperPath = group.suggestedKeeperPath ?? group.paths.first
            let extraPaths = group.paths.filter { $0 != keeperPath }
            guard !extraPaths.isEmpty else { continue }

            if examples.count < 3 {
                examples.append(example(for: group, keeperPath: keeperPath))
            }

            for path in extraPaths {
                let targetPath = duplicateTargetPath(for: path, config: config, service: service)
                items.append(LibraryPlanItem(
                    stage: .duplicateReview,
                    operation: .duplicateDecision,
                    currentPath: path,
                    proposedPath: targetPath,
                    reason: duplicateReason(for: group, keeperPath: keeperPath),
                    confidence: confidence(for: group),
                    safety: .needsChoice,
                    decision: .needsChoice,
                    requiresReview: true,
                    confidenceExplanation: duplicateExplanation(for: group, keeperPath: keeperPath),
                    correctionOptions: [.moveExistingAside, .notADuplicate],
                    receipt: "Duplicate review: move \(path) to \(targetPath)"
                ))
            }
        }

        guard !items.isEmpty else { return [] }

        return [
            LibraryPlanGroup(
                stage: .duplicateReview,
                title: "Duplicate review",
                summary: "\(exactDuplicateCandidates.count) exact duplicate group(s), \(items.count) extra copy candidate(s).",
                reviewPrompt: "Check Move Aside only for extra copies you are comfortable moving into \(config.duplicateFolderName). Suggested keepers stay where they are.",
                examples: examples,
                items: items
            )
        ]
    }

    private func reportDuplicateProgress(
        service: SableLibraryService,
        message: String,
        completed: Int,
        total: Int
    ) {
        guard total > 0 else { return }
        guard completed == 1 || completed.isMultiple(of: 50) || completed == total else { return }
        service.reportProgressSnapshot(SableLibraryProgressSnapshot(
            title: "Preparing duplicate review",
            message: message,
            completedUnitCount: completed,
            totalUnitCount: total
        ))
    }

    private func duplicateTargetPath(for path: String, config: SableLibraryConfig, service: SableLibraryService) -> String {
        let fileName = URL(fileURLWithPath: path).lastPathComponent
        return service.joinedRelativePath(config.duplicateFolderName, fileName)
    }

    private func duplicateReason(for group: LibraryInspectionDuplicateGroup, keeperPath: String?) -> String {
        let kind = kindTitle(group.kind)
        if let keeperPath {
            return "\(kind). Suggested keeper: \(keeperPath). \(group.note)"
        }
        return "\(kind). \(group.note)"
    }

    private func duplicateExplanation(for group: LibraryInspectionDuplicateGroup, keeperPath: String?) -> String {
        let pathCount = group.paths.count
        let keeper = keeperPath.map { " Suggested keeper: \($0)." } ?? ""
        return "\(pathCount) exact matching file\(pathCount == 1 ? "" : "s") were found in this group.\(keeper) Move Aside sends only this extra copy to the duplicate folder."
    }

    private func example(for group: LibraryInspectionDuplicateGroup, keeperPath: String?) -> LibraryPlanExample {
        LibraryPlanExample(
            title: kindTitle(group.kind),
            before: group.paths.joined(separator: "\n"),
            after: keeperPath,
            reason: group.note,
            details: [
                LibraryPlanExampleDetail(label: "Keeper", value: keeperPath ?? "Review needed", symbol: "checkmark.seal"),
                LibraryPlanExampleDetail(label: "Copies", value: "\(max(0, group.paths.count - 1))", symbol: "doc.on.doc")
            ]
        )
    }

    private func confidence(for group: LibraryInspectionDuplicateGroup) -> LibraryPlanConfidence {
        group.kind == DuplicateReviewGroup.Kind.exactContent.rawValue ? .high : .unknown
    }

    private func kindTitle(_ kind: String) -> String {
        switch kind {
        case DuplicateReviewGroup.Kind.exactContent.rawValue:
            return "Exact duplicate"
        default:
            return "Duplicate candidate"
        }
    }
}
