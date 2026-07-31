//
//  SableLibraryStep6ReviewApply.swift
//  Sable's Library
//

import Foundation

nonisolated struct SableLibraryStep6ReviewApply: Sendable {
    private let comicInfoStep = SableLibraryStep3ComicInfo()

    func applyChecked(
        plan: LibraryPlan,
        stage: LibraryPipelineStage,
        options: LibraryPipelineOptions?,
        coverDownloadPass: SableLibraryCoverDownloadPass = .combined,
        service: SableLibraryService
    ) async -> LibraryApplyResult {
        if stage.usesComicInfoApplyEngine {
            return await comicInfoStep.applyChecked(
                plan: plan,
                stage: stage,
                options: options,
                coverDownloadPass: coverDownloadPass,
                service: service
            )
        }

        let checked = plan.checkedItems.filter { $0.stage == stage }
        guard !checked.isEmpty else { return .empty }

        let root = URL(fileURLWithPath: plan.rootPath, isDirectory: true)
        let config = service.currentConfig()
        let repairItems = checked.filter(\.isApplyablePackageRepairOperation)
        let appleBooksRepairItems = checked.filter(\.isApplyableAppleBooksCompatibilityRepairOperation)
        let emptySortingFolderItems = checked.filter(\.isEmptySortingFolderCleanup)
        let moveItems = checked.filter { isMoveOperation($0) && !$0.isEmptySortingFolderCleanup }
        let moves = moveItems.compactMap(move)
        guard !moves.isEmpty
                || !repairItems.isEmpty
                || !appleBooksRepairItems.isEmpty
                || !emptySortingFolderItems.isEmpty else {
            return LibraryApplyResult(
                appliedCount: 0,
                skippedCount: checked.count,
                receiptPath: nil,
                summary: "No checked final path changes were ready to apply. Sidecar and network-backed rows still need their own review page."
            )
        }

        var reportSections: [String] = []
        var appliedCount = 0
        var skippedCount = 0
        var appliedPaths: [LibraryAppliedPlanPath] = []
        let reportAppName = reportOwnerName(for: stage)

        if !repairItems.isEmpty {
            let repairResult = await service.applyEpubPackageRepairs(
                root: root,
                paths: repairItems.map(\.currentPath),
                reportTitle: "\(reportAppName) EPUB package repair apply",
                reportName: config.reports.runSummaryReport
            )
            appliedCount += repairResult.applied.count
            skippedCount += repairResult.skipped.count
            appliedPaths.append(contentsOf: repairResult.applied.map { path in
                LibraryAppliedPlanPath(
                    currentPath: path,
                    proposedPath: nil,
                    stage: stage,
                    operation: .repairEpubPackage
                )
            })
            reportSections.append(repairResult.report)
        }

        if !appleBooksRepairItems.isEmpty {
            let shouldWriteImportMetadata =
                options?.stages.writeEPUBImportMetadata == true
                || appleBooksRepairItems.contains { $0.reviewTags.contains("epub-import-metadata") }
            let uniqueAppleBooksPaths = Array(Set(appleBooksRepairItems.map(\.currentPath))).sorted()
            let sidecarMetadataByPath = uniqueAppleBooksPaths.reduce(into: [String: SableLibraryEPUBImportMetadata]()) { partialResult, path in
                let url = root.appendingPathComponent(path)
                guard let metadata = service.epubImportMetadataCandidate(for: url, root: root, config: config) else {
                    return
                }
                partialResult[path] = metadata
            }
            let importMetadataByPath: [String: SableLibraryEPUBImportMetadata]
            if shouldWriteImportMetadata {
                importMetadataByPath = sidecarMetadataByPath
            } else {
                importMetadataByPath = [:]
            }
            let trustedCoverURLByPath: [String: String] = Dictionary(
                uniqueKeysWithValues: sidecarMetadataByPath.compactMap { entry in
                    guard let coverURL = entry.value.coverURL else { return nil }
                    return (entry.key, coverURL)
                }
            )
            let localCoverCandidatesByPath: [String: [SableLibraryEPUBImportCoverCandidate]] = sidecarMetadataByPath
                .filter { !$0.value.localCoverCandidates.isEmpty }
                .mapValues(\.localCoverCandidates)
            let repairScopesByPath = appleBooksRepairItems.reduce(into: [String: Set<SableLibraryEPUBRepairScope>]()) { partialResult, item in
                partialResult[item.currentPath, default: []].formUnion(item.epubRepairScopes)
            }
            let appleBooksRepairResult = await service.applyAppleBooksCompatibilityRepairs(
                root: root,
                paths: uniqueAppleBooksPaths,
                reportTitle: "\(reportAppName) Apple Books compatibility repair apply",
                reportName: config.reports.runSummaryReport,
                optimizePageImageEPUBs: options?.stages.optimizePageImageEPUBs ?? false,
                importMetadataByPath: importMetadataByPath,
                trustedCoverURLByPath: trustedCoverURLByPath,
                localCoverCandidatesByPath: localCoverCandidatesByPath,
                repairScopesByPath: repairScopesByPath
            )
            let appliedAppleBooksPaths = appleBooksRepairResult.applied.map {
                $0.replacingOccurrences(of: " repaired in place", with: "")
            }
            let appliedAppleBooksPathSet = Set(appliedAppleBooksPaths)
            let skippedAppleBooksPathSet = skippedAppleBooksPaths(
                from: appleBooksRepairResult,
                selectedPaths: uniqueAppleBooksPaths
            ).subtracting(appliedAppleBooksPathSet)
            let appliedAppleBooksRowCount = appleBooksRepairItems.filter {
                appliedAppleBooksPathSet.contains($0.currentPath)
            }.count
            let skippedAppleBooksRowCount = appleBooksRepairItems.filter {
                skippedAppleBooksPathSet.contains($0.currentPath)
            }.count
            appliedCount += appliedAppleBooksRowCount
            skippedCount += skippedAppleBooksRowCount
            appliedPaths.append(contentsOf: appliedAppleBooksPaths.map { path in
                LibraryAppliedPlanPath(
                    currentPath: path,
                    proposedPath: nil,
                    stage: stage,
                    operation: .repairAppleBooksCompatibility
                )
            })
            let rowSummary = appleBooksRepairRowSummary(
                selectedRows: appleBooksRepairItems.count,
                selectedFiles: uniqueAppleBooksPaths.count,
                appliedRows: appliedAppleBooksRowCount,
                appliedFiles: appliedAppleBooksPaths.count,
                skippedRows: skippedAppleBooksRowCount,
                skippedFiles: skippedAppleBooksPathSet.count
            )
            reportSections.append([rowSummary, appleBooksRepairResult.report].joined(separator: "\n\n"))
        }

        if !moves.isEmpty {
            let result = await service.applyPlannedMovesWithApplied(
                root: root,
                moves: moves,
                reportTitle: "\(reportAppName) \(stage.title.lowercased()) apply",
                reportName: config.reports.runSummaryReport,
                cleanupEmptySourceFolders: stage == .canonicalFolders
            )
            appliedCount += result.applied.count
            skippedCount += result.skipped.count
            appliedPaths.append(contentsOf: appliedPlanPaths(
                from: result.applied,
                checkedItems: moveItems,
                stage: stage
            ))
            reportSections.append(result.report)
        }

        if !emptySortingFolderItems.isEmpty {
            let result = await service.removeCheckedEmptySortingFolders(
                root: root,
                relativePaths: emptySortingFolderItems.map(\.currentPath),
                reportTitle: "\(reportAppName) empty sorting folder cleanup",
                reportName: config.reports.runSummaryReport
            )
            appliedCount += result.removed.count
            skippedCount += result.skipped.count
            appliedPaths.append(contentsOf: result.removed.map { path in
                LibraryAppliedPlanPath(
                    currentPath: path,
                    proposedPath: nil,
                    stage: stage,
                    operation: .inspectOnly
                )
            })
            reportSections.append(result.report)
        }

        var combinedReport = reportSections.joined(separator: "\n\n")
        let receiptPath: String?
        if combinedReport.isEmpty {
            receiptPath = nil
        } else {
            do {
                try service.writeReport(combinedReport, named: config.reports.runSummaryReport, root: root, config: config)
                receiptPath = service
                    .reportDirectory(root: root, config: config)
                    .appendingPathComponent(config.reports.runSummaryReport)
                    .path(percentEncoded: false)
            } catch {
                if !combinedReport.contains("Receipt warning:") {
                    let changeSummary = appliedCount == 0
                        ? "No files were changed"
                        : "\(appliedCount) change\(appliedCount == 1 ? "" : "s") \(appliedCount == 1 ? "was" : "were") applied"
                    combinedReport += "\n\nReceipt warning: \(changeSummary), but Sable could not save the final receipt: \(error.localizedDescription)"
                }
                receiptPath = nil
            }
        }

        return LibraryApplyResult(
            appliedCount: appliedCount,
            skippedCount: skippedCount,
            receiptPath: receiptPath,
            summary: combinedReport.isEmpty ? "No checked changes were applied." : combinedReport,
            appliedPaths: appliedPaths
        )
    }

    func summarize(plan: LibraryPlan, lastApplyResult: LibraryApplyResult?) -> LibraryPipelineSummary {
        let plannedCount = plan.activeItems.count
        let unresolvedCount = plan.unresolvedItems.count
        let appliedCount = lastApplyResult?.appliedCount ?? 0

        if appliedCount > 0, plannedCount == 0, plan.inspectMode.isEPUBClinicVerification {
            return LibraryPipelineSummary(
                title: "Clinic verification clean",
                message: "\(appliedCount) repair row\(appliedCount == 1 ? "" : "s") applied, then Sable rechecked the changed EPUBs and found no remaining Clinic rows.",
                nextAction: .checkAgain,
                plannedCount: plannedCount,
                unresolvedCount: unresolvedCount,
                appliedCount: appliedCount
            )
        }

        if appliedCount > 0 {
            return LibraryPipelineSummary(
                title: "Inspect again",
                message: "\(appliedCount) change(s) were applied. Let Sable refresh the changed paths before more cleanup.",
                nextAction: .checkAgain,
                plannedCount: plannedCount,
                unresolvedCount: unresolvedCount,
                appliedCount: appliedCount
            )
        }

        if plannedCount == 0 {
            return LibraryPipelineSummary(
                title: summaryClearTitle(for: plan),
                message: summaryClearMessage(for: plan),
                nextAction: .checkAgain,
                plannedCount: plannedCount,
                unresolvedCount: unresolvedCount,
                appliedCount: appliedCount
            )
        }

        if unresolvedCount > 0 {
            return LibraryPipelineSummary(
                title: "Review still needed",
                message: "\(unresolvedCount) item(s) still need your choice before the collection can be considered tidy.",
                nextAction: .reviewDecisions,
                plannedCount: plannedCount,
                unresolvedCount: unresolvedCount,
                appliedCount: appliedCount
            )
        }

        return LibraryPipelineSummary(
            title: "Ready to apply",
            message: "Checked changes are ready on their individual review pages.",
            nextAction: .applyChecked,
            plannedCount: plannedCount,
            unresolvedCount: unresolvedCount,
            appliedCount: appliedCount
        )
    }

    private func reportOwnerName(for stage: LibraryPipelineStage) -> String {
        stage == .epubClinic ? "Sable's Clinic" : "Sable's Library"
    }

    private func summaryClearTitle(for plan: LibraryPlan) -> String {
        isClinicPlan(plan) ? "No Clinic rows from this pass" : "Library looks clear"
    }

    private func summaryClearMessage(for plan: LibraryPlan) -> String {
        if isClinicPlan(plan) {
            return "No EPUB repair rows were found in this pass. Sable only says clean after repairs are applied and the changed EPUBs recheck with no remaining rows."
        }
        return "No cleanup suggestions are waiting. Run inspect again after adding new books."
    }

    private func isClinicPlan(_ plan: LibraryPlan) -> Bool {
        plan.inspectMode.isEPUBClinicPass || plan.groups.contains { $0.stage == .epubClinic }
    }

    private func isMoveOperation(_ item: LibraryPlanItem) -> Bool {
        item.isApplyableFileOperation
    }

    private func move(from item: LibraryPlanItem) -> PlannedMove? {
        guard let proposedPath = item.proposedPath,
              item.currentPath != proposedPath else {
            return nil
        }

        return PlannedMove(
            reason: reason(for: item),
            fromPath: item.currentPath,
            toPath: proposedPath
        )
    }

    private func appliedPlanPaths(
        from appliedMoves: [PlannedMove],
        checkedItems: [LibraryPlanItem],
        stage: LibraryPipelineStage
    ) -> [LibraryAppliedPlanPath] {
        let itemsByCurrentPath = Dictionary(grouping: checkedItems, by: \.currentPath)
        return appliedMoves.map { move in
            let item = itemsByCurrentPath[move.fromPath]?.first
            return LibraryAppliedPlanPath(
                currentPath: move.fromPath,
                proposedPath: move.toPath,
                stage: stage,
                operation: item?.operation ?? .sortIntoFolder
            )
        }
    }

    private func reason(for item: LibraryPlanItem) -> String {
        if item.isNameCollisionResolution {
            return PlannedMove.manualNameCollisionReason
        }
        if item.isFolderMergeResolution {
            return PlannedMove.manualFolderMergeReason
        }
        if item.isDuplicateMoveAside {
            return PlannedMove.duplicateReviewReason
        }
        if item.reviewTags.contains("pdf-triage") {
            return "cleanup review: PDF document triage"
        }
        if item.reviewTags.contains("volume-wrapper-folder")
            || item.reviewTags.contains("video-wrapper-folder") {
            return PlannedMove.volumeWrapperFolderReason
        }
        if item.reviewTags.contains("raw-video-numbered-wrapper") {
            return PlannedMove.rawVideoNumberedWrapperReason
        }
        if item.reviewTags.contains("raw-existing-series-update") {
            return PlannedMove.rawUpdateFolderReason
        }

        return switch item.operation {
        case .repairEpubPackage:
            "cleanup review: repair expanded EPUB package"
        case .repairAppleBooksCompatibility:
            "cleanup review: repair Apple Books EPUB in place"
        case .sortIntoFolder:
            "cleanup review: move and clean loose book"
        case .cleanRawName:
            "cleanup review: clean raw filename"
        case .renameFolder:
            "cleanup review: tidy folder name"
        case .renameFile:
            "cleanup review: tidy file name"
        case .inspectOnly, .createComicInfo, .refreshComicInfo, .createAnimeInfo, .refreshAnimeInfo, .duplicateDecision, .skip:
            "cleanup review: skipped"
        }
    }

    private func skippedAppleBooksPaths(
        from result: LibraryAppleBooksCompatibilityRepairApplyResult,
        selectedPaths: [String]
    ) -> Set<String> {
        var skipped = Set(result.failed.keys)
        for line in result.skipped {
            if let path = selectedPaths.first(where: { line == $0 || line.hasPrefix("\($0):") }) {
                skipped.insert(path)
            }
        }
        return skipped
    }

    private func appleBooksRepairRowSummary(
        selectedRows: Int,
        selectedFiles: Int,
        appliedRows: Int,
        appliedFiles: Int,
        skippedRows: Int,
        skippedFiles: Int
    ) -> String {
        [
            "Selected Sable's Clinic repair rows: \(selectedRows)",
            "Unique EPUB files touched: \(appliedFiles) of \(selectedFiles)",
            "Completed repair rows: \(appliedRows)",
            "Skipped repair rows: \(skippedRows) across \(skippedFiles) file(s)",
            "Sable rewrites each EPUB at most once per apply, while applying all selected repair layers for that file together."
        ].joined(separator: "\n")
    }
}
