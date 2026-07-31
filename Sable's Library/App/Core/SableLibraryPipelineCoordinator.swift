//
//  SableLibraryPipelineCoordinator.swift
//  Sable's Library
//

import Foundation

nonisolated struct SableLibraryPipelineCoordinator: Sendable {
    var service: SableLibraryService
    var inspectStep = SableLibraryStep1InspectLibrary()
    var rawStep = SableLibraryStep2PrepareRawFiles()
    var comicInfoStep = SableLibraryStep3ComicInfo()
    var folderStep = SableLibraryStep4CanonicalFolders()
    var fileStep = SableLibraryStep5CanonicalFiles()
    var duplicateStep = SableLibraryStepDuplicateReview()
    var reviewApplyStep = SableLibraryStep6ReviewApply()

    init(service: SableLibraryService) {
        self.service = service
    }

    func inspectAndBuildPlan(root: URL, options: LibraryPipelineOptions) async -> LibraryPipelineRun {
        await inspectAndBuildPlan(root: root, options: options, mode: .full)
    }

    func inspectInventoryAndBuildPlan(root: URL, options: LibraryPipelineOptions) async -> LibraryPipelineRun {
        await inspectAndBuildPlan(root: root, options: options, mode: .lightInventory)
    }

    func inspectEPUBClinicInventoryAndBuildPlan(root: URL, options: LibraryPipelineOptions) async -> LibraryPipelineRun {
        await inspectAndBuildPlan(root: root, options: options, mode: .epubClinicInventory)
    }

    func inspectStageAndBuildPlan(
        root: URL,
        options: LibraryPipelineOptions,
        stage: LibraryPipelineStage
    ) async -> LibraryPipelineRun {
        await inspectAndBuildPlan(root: root, options: options, mode: .stageDeepDive(stage))
    }

    func quickVerifyAndBuildPlan(
        root: URL,
        options: LibraryPipelineOptions,
        previousStage: LibraryPipelineStage,
        changedPaths: [String]
    ) async -> LibraryPipelineRun {
        await quickVerifyAndBuildPlan(
            root: root,
            options: options,
            previousStage: previousStage,
            changedPaths: changedPaths,
            refreshStages: [previousStage]
        )
    }

    func quickVerifyAndBuildPlan(
        root: URL,
        options: LibraryPipelineOptions,
        previousStage: LibraryPipelineStage,
        changedPaths: [String],
        refreshStages: [LibraryPipelineStage]
    ) async -> LibraryPipelineRun {
        let uniqueRefreshStages = refreshStages.reduce(into: [LibraryPipelineStage]()) { result, stage in
            if !result.contains(stage) {
                result.append(stage)
            }
        }
        let scanFocusStage = uniqueRefreshStages.first(where: { $0 == .canonicalFiles })
            ?? uniqueRefreshStages.first(where: { $0 == .canonicalFolders })
            ?? uniqueRefreshStages.first
            ?? previousStage
        return await inspectAndBuildPlan(
            root: root,
            options: options,
            mode: .quickVerify(
                previousStage: previousStage,
                changedPaths: changedPaths,
                focusStage: scanFocusStage
            ),
            stagesOverride: uniqueRefreshStages
        )
    }

    private func inspectAndBuildPlan(
        root: URL,
        options: LibraryPipelineOptions,
        mode: LibraryPipelineInspectMode,
        stagesOverride: [LibraryPipelineStage]? = nil
    ) async -> LibraryPipelineRun {
        var context = LibraryPipelineContext(root: root, options: options, inspectMode: mode)

        let inspectionStartedAt = Date()
        context.inspection = await inspectStep.inspect(root: root, options: options, mode: mode, service: service)
        let inspectionElapsed = Date().timeIntervalSince(inspectionStartedAt)
        context.timings.append(LibraryPipelineTiming(
            title: mode.title,
            elapsedSeconds: inspectionElapsed,
            resultCount: context.inspection?.fileCount
        ))
        service.reportProgress("\(mode.title) finished in \(SableLibraryWorkTiming.duration(inspectionElapsed))")
        if Task.isCancelled {
            return LibraryPipelineRun(root: root, context: context, nextAction: .checkAgain)
        }
        let stages = stagesOverride ?? stagesToPrepare(for: mode, options: options)
        for (index, stage) in stages.enumerated() {
            if Task.isCancelled {
                return LibraryPipelineRun(root: root, context: context, nextAction: .checkAgain)
            }
            let completedCount = index + 1
            service.reportProgressSnapshot(SableLibraryProgressSnapshot(
                title: "Preparing cleanup steps",
                message: "Preparing \(stage.title) \(completedCount) of \(stages.count).",
                completedUnitCount: index,
                totalUnitCount: stages.count
            ))
            let stageStartedAt = Date()
            let groups = await prepareGroups(for: stage, context: context)
            let stageElapsed = Date().timeIntervalSince(stageStartedAt)
            if Task.isCancelled {
                return LibraryPipelineRun(root: root, context: context, nextAction: .checkAgain)
            }
            context.plan.append(contentsOf: groups)
            context.timings.append(LibraryPipelineTiming(
                title: stage.title,
                elapsedSeconds: stageElapsed,
                resultCount: groups.flatMap(\.items).count
            ))
            service.reportProgressSnapshot(SableLibraryProgressSnapshot(
                title: "Preparing cleanup steps",
                message: "Prepared \(stage.title) \(completedCount) of \(stages.count) in \(SableLibraryWorkTiming.duration(stageElapsed)).",
                completedUnitCount: completedCount,
                totalUnitCount: stages.count
            ))
            if stagesOverride == nil, mode.focusStage != nil, !groups.isEmpty {
                break
            }
        }

        let nextAction: LibraryPipelineNextAction = context.plan.items.isEmpty ? .checkAgain : .reviewDecisions
        return LibraryPipelineRun(root: root, context: context, nextAction: nextAction)
    }

    private func prepareGroups(
        for stage: LibraryPipelineStage,
        context: LibraryPipelineContext
    ) async -> [LibraryPlanGroup] {
        var scopedContext = context
        let modifiedWindow = context.options.stages.modifiedWindow(for: stage)
        scopedContext.inspection = context.inspection?.scoped(
            to: modifiedWindow,
            for: stage
        )

        switch stage {
        case .inspect:
            return []
        case .prepareRawFiles:
            return await rawStep.prepare(context: scopedContext, service: service)
        case .epubClinic:
            return await rawStep.prepareEPUBClinic(context: context, service: service)
        case .comicInfo:
            return await comicInfoStep.prepare(context: scopedContext, service: service)
        case .providerMatches:
            return await comicInfoStep.prepareProviderMatches(context: scopedContext, service: service)
        case .covers:
            return await comicInfoStep.prepareCovers(context: scopedContext, service: service)
        case .canonicalFolders:
            return await folderStep.prepare(context: scopedContext, service: service)
        case .canonicalFiles:
            return await fileStep.prepare(context: scopedContext, service: service)
        case .duplicateReview:
            return await duplicateStep.prepare(context: scopedContext, service: service)
        case .reviewApply:
            return []
        }
    }

    private func stagesToPrepare(
        for mode: LibraryPipelineInspectMode,
        options: LibraryPipelineOptions
    ) -> [LibraryPipelineStage] {
        let actionableStages: [LibraryPipelineStage] = [
            .prepareRawFiles,
            .comicInfo,
            .providerMatches,
            .covers,
            .canonicalFolders,
            .canonicalFiles,
            .epubClinic,
            .duplicateReview
        ].filter { stageIsEnabled($0, options: options) }

        if let focusStage = mode.focusStage {
            if focusStage == .covers {
                return [.covers]
            }
            return actionableStages.contains(focusStage) ? [focusStage] : []
        }

        return (mode == .lightInventory || mode == .epubClinicInventory) ? [] : actionableStages
    }

    private func stageIsEnabled(
        _ stage: LibraryPipelineStage,
        options: LibraryPipelineOptions
    ) -> Bool {
        switch stage {
        case .prepareRawFiles:
            return options.stages.applyCleanup
        case .epubClinic:
            return options.stages.repairEPUBs
        case .canonicalFolders:
            return options.cleanup.renameFolders
        case .canonicalFiles:
            return options.cleanup.renameFiles
        case .covers:
            return options.stages.downloadSeriesCovers
        case .inspect, .comicInfo, .providerMatches, .duplicateReview, .reviewApply:
            return true
        }
    }

    func applyChecked(
        _ plan: LibraryPlan,
        stage: LibraryPipelineStage,
        options: LibraryPipelineOptions? = nil,
        coverDownloadPass: SableLibraryCoverDownloadPass = .combined
    ) async -> LibraryApplyResult {
        await reviewApplyStep.applyChecked(
            plan: plan,
            stage: stage,
            options: options,
            coverDownloadPass: coverDownloadPass,
            service: service
        )
    }

    func applyExactIDBatch(
        _ plan: LibraryPlan,
        stage: LibraryPipelineStage,
        itemIDs: Set<LibraryPlanItem.ID>? = nil,
        options: LibraryPipelineOptions? = nil
    ) async -> LibraryApplyResult {
        await comicInfoStep.applyExactIDBatch(
            plan: plan,
            stage: stage,
            itemIDs: itemIDs,
            options: options,
            service: service
        )
    }

    func summarize(_ plan: LibraryPlan, lastApplyResult: LibraryApplyResult? = nil) -> LibraryPipelineSummary {
        reviewApplyStep.summarize(plan: plan, lastApplyResult: lastApplyResult)
    }
}
