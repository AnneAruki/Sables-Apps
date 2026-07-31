//
//  SableLibraryStep4CanonicalFolders.swift
//  Sable's Library
//

import Foundation

nonisolated private struct SableLibraryFolderShelfWorkItem: Sendable {
    var seriesPath: String
    var input: SableLibraryShelfCatalogInput
}

nonisolated private struct SableLibraryFolderShelfEvaluation: Sendable {
    var suggestion: SableLibraryShelfSuggestion
    var ledger: SableLibraryShelfDecisionLedger
}

nonisolated private struct SableLibraryFolderShelfResult: Sendable {
    var seriesPath: String
    var evaluation: SableLibraryFolderShelfEvaluation
}

nonisolated struct SableLibraryStep4CanonicalFolders: Sendable {
    var namingPolicy = SableLibraryNamingPolicy()

    func prepare(context: LibraryPipelineContext, service: SableLibraryService) async -> [LibraryPlanGroup] {
        service.reportProgress("Preparing folder sorting plan")
        guard context.options.cleanup.renameFolders,
              context.options.stages.useComicInfoTitles,
              let inspection = context.inspection else {
            return []
        }

        let startedAt = Date()
        let includesWatching = !hasPendingWatchingPreparation(in: context.plan, config: service.currentConfig())
        let totalSeriesCount = inspection.series.count + (includesWatching ? inspection.videoSeries.count : 0)
        let shelfEvaluations = await readingShelfEvaluations(
            for: inspection.series,
            root: context.root,
            organizationDepth: context.options.cleanup.readingFolderOrganizationDepth,
            service: service,
            startedAt: startedAt
        )
        var plannedDestinations: [String: String] = [:]
        var items: [LibraryPlanItem] = []
        for (index, series) in inspection.series.enumerated() {
            reportSortingProgress(
                service: service,
                message: "Checking reading folder \(index + 1) of \(inspection.series.count): \(series.path)",
                completed: index + 1,
                total: totalSeriesCount,
                startedAt: startedAt
            )
            if let item = planItem(
                for: series,
                root: context.root,
                folderOrganizationDepth: context.options.cleanup.readingFolderOrganizationDepth,
                plannedDestinations: &plannedDestinations,
                shelfEvaluation: shelfEvaluations[series.path],
                service: service
            ) {
                items.append(item)
            }
        }
        if includesWatching {
            for (index, series) in inspection.videoSeries.enumerated() {
                let completedCount = inspection.series.count + index + 1
                reportSortingProgress(
                    service: service,
                    message: "Checking watching folder \(index + 1) of \(inspection.videoSeries.count): \(series.path)",
                    completed: completedCount,
                    total: totalSeriesCount,
                    startedAt: startedAt
                )
                if let item = videoPlanItem(
                    for: series,
                    root: context.root,
                    plannedDestinations: &plannedDestinations,
                    service: service
                ) {
                    items.append(item)
                }
            }
        }

        let emptySortingFolderItems = context.options.stages.modifiedWindow(for: .canonicalFolders) == .all
            ? emptySortingFolderCleanupItems(
                inspection: inspection,
                root: context.root,
                organizationDepth: context.options.cleanup.readingFolderOrganizationDepth,
                service: service
            )
            : []

        guard !items.isEmpty || !emptySortingFolderItems.isEmpty else {
            service.reportProgress("Folder sorting: no tidy folder changes needed")
            return []
        }

        service.reportProgress("Folder sorting: prepared \(items.count + emptySortingFolderItems.count) suggestion(s)")
        var groups: [LibraryPlanGroup] = []
        if !items.isEmpty {
            groups.append(LibraryPlanGroup(
                stage: .canonicalFolders,
                title: "Folder sorting",
                summary: "\(items.count) folder(s) can line up with trusted sidecar titles, \(context.options.cleanup.readingFolderOrganizationDepth.label.lowercased()) organization, and optional source IDs.",
                reviewPrompt: "Checked folder moves use trusted sidecars. After a successful move, abandoned empty shelf and subshelf folders are removed and listed in the receipt; collection roots and folders containing real files stay untouched. Collisions, unclear paths, and merge choices stay out until you review them.",
                examples: examples(from: items),
                items: items
            ))
        }
        if !emptySortingFolderItems.isEmpty {
            groups.append(LibraryPlanGroup(
                stage: .canonicalFolders,
                title: "Empty Sorting Folders",
                summary: "\(emptySortingFolderItems.count) empty SSS shelf or subshelf folder(s) remain from an older folder depth.",
                reviewPrompt: "These rows start unchecked. Checked folders are removed only if they still contain nothing except optional Finder metadata at apply time. Collection roots and folders that gain real content are always preserved.",
                examples: emptySortingFolderItems.prefix(3).map { item in
                    LibraryPlanExample(
                        title: "Remove empty folder",
                        before: item.currentPath,
                        after: nil,
                        reason: item.reason
                    )
                },
                items: emptySortingFolderItems
            ))
        }
        return groups
    }

    private func readingShelfEvaluations(
        for seriesRows: [LibrarySeriesSnapshot],
        root: URL,
        organizationDepth: SableLibraryFolderOrganizationDepth,
        service: SableLibraryService,
        startedAt: Date
    ) async -> [String: SableLibraryFolderShelfEvaluation] {
        guard organizationDepth.includesShelf else { return [:] }

        let workItems = seriesRows.compactMap { series -> SableLibraryFolderShelfWorkItem? in
            guard series.hasComicInfo,
                  !series.path.isEmpty,
                  let rawPreferredTitle = series.preferredTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !rawPreferredTitle.isEmpty else {
                return nil
            }

            let preferredTitle = effectiveReadingFolderTitle(
                for: series,
                preferredTitle: rawPreferredTitle,
                service: service
            )
            let explicitMediaType = series.mediaType?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let mediaType = explicitMediaType.isEmpty
                ? inferredReadingMediaType(for: series, root: root) ?? explicitMediaType
                : explicitMediaType
            return SableLibraryFolderShelfWorkItem(
                seriesPath: series.path,
                input: readingShelfInput(
                    for: series,
                    preferredTitle: preferredTitle,
                    mediaType: mediaType
                )
            )
        }
        guard !workItems.isEmpty else { return [:] }

        // Shelf matching is CPU-heavy but independent. A small cap keeps memory calm
        // while preserving sequential filesystem and collision planning below.
        let parallelism = SableLibraryAdaptiveWorkBudget.parallelism(
            minimum: 2,
            multiplier: 1,
            cap: 3,
            itemCount: workItems.count
        )
        var evaluations: [String: SableLibraryFolderShelfEvaluation] = [:]
        evaluations.reserveCapacity(workItems.count)
        var chunkStart = 0

        while chunkStart < workItems.count {
            if Task.isCancelled { return [:] }
            let chunkEnd = min(workItems.count, chunkStart + parallelism)
            let chunk = Array(workItems[chunkStart..<chunkEnd])
            let results = await withTaskGroup(
                of: SableLibraryFolderShelfResult.self
            ) { group -> [SableLibraryFolderShelfResult] in
                for workItem in chunk {
                    group.addTask {
                        let suggestion = SableLibraryShelfCatalog.suggestShelf(for: workItem.input)
                        return SableLibraryFolderShelfResult(
                            seriesPath: workItem.seriesPath,
                            evaluation: SableLibraryFolderShelfEvaluation(
                                suggestion: suggestion,
                                ledger: SableLibraryShelfCatalog.decisionLedger(
                                    for: workItem.input,
                                    suggestion: suggestion
                                )
                            )
                        )
                    }
                }

                var collected: [SableLibraryFolderShelfResult] = []
                collected.reserveCapacity(chunk.count)
                for await result in group {
                    collected.append(result)
                }
                return collected
            }
            for result in results {
                evaluations[result.seriesPath] = result.evaluation
            }
            chunkStart = chunkEnd

            let timing = SableLibraryWorkTiming.summary(
                startedAt: startedAt,
                completedCount: chunkEnd,
                totalCount: workItems.count,
                unit: "shelf"
            )
            service.reportProgressSnapshot(SableLibraryProgressSnapshot(
                title: "Classifying reading shelves",
                message: "Checked \(chunkEnd) of \(workItems.count) reading shelves. \(timing)",
                completedUnitCount: chunkEnd,
                totalUnitCount: workItems.count
            ))
            await Task.yield()
        }

        return evaluations
    }

    private func emptySortingFolderCleanupItems(
        inspection: LibraryInspection,
        root: URL,
        organizationDepth: SableLibraryFolderOrganizationDepth,
        service: SableLibraryService
    ) -> [LibraryPlanItem] {
        let readingRoots = Set(inspection.series.compactMap { series in
            series.path.split(separator: "/").first.map(String.init)
        })
        var candidates: [String] = []

        for readingRoot in readingRoots.sorted() {
            let formURL = root.appendingPathComponent(readingRoot, isDirectory: true)
            for shelfURL in directoryChildren(of: formURL, service: service) where isSSSShelfName(shelfURL.lastPathComponent) {
                let shelfPath = "\(readingRoot)/\(shelfURL.lastPathComponent)"
                if organizationDepth == .form, isEffectivelyEmptyDirectory(shelfURL, service: service) {
                    candidates.append(shelfPath)
                }

                for subShelfURL in directoryChildren(of: shelfURL, service: service)
                    where isSSSSubShelfName(subShelfURL.lastPathComponent)
                {
                    if isEffectivelyEmptyDirectory(subShelfURL, service: service) {
                        candidates.append("\(shelfPath)/\(subShelfURL.lastPathComponent)")
                    }
                }
            }
        }

        return Array(Set(candidates))
            .sorted { lhs, rhs in
                let lhsDepth = lhs.split(separator: "/").count
                let rhsDepth = rhs.split(separator: "/").count
                if lhsDepth != rhsDepth { return lhsDepth > rhsDepth }
                return lhs.localizedStandardCompare(rhs) == .orderedAscending
            }
            .map { path in
                LibraryPlanItem(
                    stage: .canonicalFolders,
                    operation: .inspectOnly,
                    currentPath: path,
                    proposedPath: nil,
                    reason: "This empty SSS sorting folder is left from an older folder depth and can be removed.",
                    confidence: .high,
                    safety: .reversible,
                    decision: .unchecked,
                    requiresReview: false,
                    usedNetworkData: false,
                    metadataProviders: [],
                    confidenceExplanation: "Sable found no real files or folders inside. Apply checks again immediately before removal and skips the row if anything has appeared.",
                    correctionOptions: [],
                    reviewTags: ["empty-sorting-folder-cleanup", "sss-empty-container"],
                    receipt: "Remove empty sorting folder \(path)"
                )
            }
    }

    private func directoryChildren(
        of folder: URL,
        service: SableLibraryService
    ) -> [URL] {
        (try? service.fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ))?.filter { url in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            return values?.isDirectory == true && values?.isSymbolicLink != true
        } ?? []
    }

    private func isEffectivelyEmptyDirectory(
        _ folder: URL,
        service: SableLibraryService
    ) -> Bool {
        guard let children = try? service.fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        ) else {
            return false
        }

        return children.allSatisfy { child in
            if child.lastPathComponent == ".DS_Store" { return true }
            let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values?.isDirectory == true, values?.isSymbolicLink != true else {
                return false
            }
            return isEffectivelyEmptyDirectory(child, service: service)
        }
    }

    private func isSSSShelfName(_ name: String) -> Bool {
        sssCodeParts(in: name).count == 1
    }

    private func isSSSSubShelfName(_ name: String) -> Bool {
        sssCodeParts(in: name).count == 2
    }

    private func sssCodeParts(in name: String) -> [String] {
        guard name.contains(" - ") else { return [] }
        let parts = name
            .components(separatedBy: " - ")[0]
            .split(separator: ".")
            .map(String.init)
        guard parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else {
            return []
        }
        return parts
    }

    private func reportSortingProgress(
        service: SableLibraryService,
        message: String,
        completed: Int,
        total: Int,
        startedAt: Date
    ) {
        guard total > 0 else { return }
        guard completed == 1 || completed.isMultiple(of: 50) || completed == total else { return }
        let timing = SableLibraryWorkTiming.summary(
            startedAt: startedAt,
            completedCount: completed,
            totalCount: total,
            unit: "folder"
        )
        service.reportProgressSnapshot(SableLibraryProgressSnapshot(
            title: "Preparing folder sorting",
            message: "\(message). \(timing)",
            completedUnitCount: completed,
            totalUnitCount: total
        ))
    }

    private func planItem(
        for series: LibrarySeriesSnapshot,
        root: URL,
        folderOrganizationDepth: SableLibraryFolderOrganizationDepth,
        plannedDestinations: inout [String: String],
        shelfEvaluation: SableLibraryFolderShelfEvaluation?,
        service: SableLibraryService
    ) -> LibraryPlanItem? {
        guard series.hasComicInfo else { return nil }
        guard !series.path.isEmpty else { return nil }
        guard let rawPreferredTitle = series.preferredTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawPreferredTitle.isEmpty else {
            return nil
        }
        let preferredTitle = effectiveReadingFolderTitle(
            for: series,
            preferredTitle: rawPreferredTitle,
            service: service
        )

        let explicitMediaType = series.mediaType?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let inferredMediaType = explicitMediaType.isEmpty ? inferredReadingMediaType(for: series, root: root) : nil
        let mediaType = inferredMediaType ?? explicitMediaType
        let sourceIDs = readingSourceIDs(for: series)
        let canonicalSeriesFolderName = namingPolicy.canonicalReadingFolderName(
            preferredTitle: preferredTitle,
            year: series.year,
            sourceIDs: sourceIDs,
            mediaType: mediaType
        )
        let shelfSuggestion: SableLibraryShelfSuggestion?
        let shelfLedger: SableLibraryShelfDecisionLedger?
        if let shelfEvaluation, folderOrganizationDepth.includesShelf {
            shelfSuggestion = shelfEvaluation.suggestion
            shelfLedger = shelfEvaluation.ledger
        } else {
            let shelfInput = folderOrganizationDepth.includesShelf
                ? readingShelfInput(for: series, preferredTitle: preferredTitle, mediaType: mediaType)
                : nil
            shelfSuggestion = shelfInput.map { SableLibraryShelfCatalog.suggestShelf(for: $0) }
            shelfLedger = shelfInput.flatMap { input in
                shelfSuggestion.map { SableLibraryShelfCatalog.decisionLedger(for: input, suggestion: $0) }
            }
        }
        let canonicalFolderName = canonicalReadingSeriesPath(
            seriesFolderName: canonicalSeriesFolderName,
            mediaType: mediaType,
            organizationDepth: folderOrganizationDepth,
            shelfSuggestion: shelfSuggestion
        )
        guard canonicalFolderName != series.path else { return nil }
        guard canonicalFolderName.lowercased() != series.path.lowercased() else { return nil }

        let sourceURL = root.appendingPathComponent(series.path, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard service.fileManager.fileExists(atPath: sourceURL.path(percentEncoded: false), isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }

        let proposedPath = canonicalFolderName
        let proposedURL = root.appendingPathComponent(proposedPath, isDirectory: true)
        let destinationExists = service.fileManager.fileExists(atPath: proposedURL.path(percentEncoded: false))
        let plannedCollisionSource = plannedDestinations[proposedPath]
        let hasCollision = destinationExists || plannedCollisionSource != nil
        plannedDestinations[proposedPath] = series.path

        let normalizedMediaType = namingPolicy.normalizedMediaType(mediaType)
        let typeWasInferred = inferredMediaType != nil
        let currentTypeHint = namingPolicy.mediaTypeHint(in: series.path)
        let hasKnownType = normalizedMediaType != "Unknown"
        let hasTypeMismatch = currentTypeHint != nil && hasKnownType && currentTypeHint != normalizedMediaType
        let volumeConflict = localVolumeConflict(in: series)
        let trustedAliasUpgrade = trustedProviderAliasMatch(
            for: series,
            currentTitle: folderTitleForReview(in: series.path),
            preferredTitle: preferredTitle
        )
        let folderRenameReview = folderRenameReview(
            currentPath: series.path,
            proposedPath: proposedPath,
            trustedAliasUpgrade: trustedAliasUpgrade
        )
        let collisionDetail = collisionExplanation(
            proposedPath: proposedPath,
            destinationExists: destinationExists,
            plannedCollisionSource: plannedCollisionSource
        )
        let needsShelfReview = needsShelfClassificationReview(shelfSuggestion)
        let needsReview = hasCollision
            || !hasKnownType
            || hasTypeMismatch
            || folderRenameReview.requiresChoice
            || needsShelfReview
        let reason: String
        if hasTypeMismatch, let currentTypeHint {
            if let collisionDetail {
                reason = "Folder name says \(currentTypeHint), but ComicInfo says \(normalizedMediaType). \(collisionDetail)"
            } else {
                reason = "Folder name says \(currentTypeHint), but ComicInfo says \(normalizedMediaType). Check the MangaBaka match or choose the right type."
            }
        } else if hasCollision {
            reason = collisionDetail ?? "Another folder already uses this tidy name. Review before moving anything."
        } else if !hasKnownType {
            reason = "ComicInfo has a preferred title, but the media type is missing or unclear. Confirm before using an Unknown type folder."
        } else if let reviewReason = folderRenameReview.reason {
            reason = reviewReason
        } else if needsShelfReview, let shelfSuggestion {
            reason = shelfSortingReviewReason(shelfSuggestion, ledger: shelfLedger)
        } else if let shelfSuggestion, folderOrganizationDepth.includesShelf {
            reason = "SSS suggests \(shelfSuggestion.subShelf.displayName). The move adds the shelf path; the series title and source IDs stay the same."
        } else if typeWasInferred {
            reason = "Folder is already in the ordinary Books area, so Sable can clean up the title and year as a book."
        } else {
            reason = "Folder can move into the ComicInfo type folder with its preferred title and source ID."
        }
        let confidenceText = confidenceExplanation(
            hasCollision: hasCollision,
            hasKnownType: hasKnownType,
            currentTypeHint: currentTypeHint,
            normalizedMediaType: normalizedMediaType,
            typeWasInferred: typeWasInferred,
            volumeConflict: volumeConflict,
            collisionDetail: collisionDetail,
            shelfSortingNote: shelfSortingConfidenceNote(shelfSuggestion, ledger: shelfLedger, depth: folderOrganizationDepth)
        )
        let confidenceExplanation = folderRenameReview.confidenceNote.map {
            "\(confidenceText) \($0)"
        } ?? confidenceText
        let reviewTags = folderReviewTags(
            folderRenameReview.reviewTags + shelfSortingReviewTags(shelfSuggestion, depth: folderOrganizationDepth),
            sourceIDs: sourceIDs
        )

        return LibraryPlanItem(
            stage: .canonicalFolders,
            operation: .renameFolder,
            currentPath: series.path,
            proposedPath: proposedPath,
            reason: reason,
            confidence: needsReview ? .medium : .high,
            safety: hasCollision ? .collision : (needsReview ? .needsChoice : .reversible),
            decision: needsReview ? .unchecked : .checked,
            requiresReview: needsReview,
            metadataProviders: sourceIDs.map(\.provider),
            confidenceExplanation: confidenceExplanation,
            correctionOptions: [.wrongType, .keepTitle, .custom],
            reviewTags: reviewTags,
            receipt: "\(series.path) -> \(proposedPath)"
        )
    }

    private func canonicalReadingSeriesPath(
        seriesFolderName: String,
        mediaType: String,
        organizationDepth: SableLibraryFolderOrganizationDepth,
        shelfSuggestion: SableLibraryShelfSuggestion?
    ) -> String {
        var components = [namingPolicy.readingRootFolder(for: mediaType)]
        if organizationDepth.includesShelf, let shelfSuggestion {
            components.append(shelfFolderComponent(shelfSuggestion.shelf.displayName))
            if organizationDepth.includesSubShelf {
                components.append(shelfFolderComponent(shelfSuggestion.subShelf.displayName))
            }
        }
        components.append(seriesFolderName)
        return components.joined(separator: "/")
    }

    private func shelfFolderComponent(_ value: String) -> String {
        namingPolicy.safePreferredTitle(value)
    }

    private func readingShelfInput(
        for series: LibrarySeriesSnapshot,
        preferredTitle: String,
        mediaType: String
    ) -> SableLibraryShelfCatalogInput {
        SableLibraryShelfCatalogInput(
            title: preferredTitle,
            description: series.shelfDescription,
            volumeDescriptions: series.volumeDescriptions,
            genres: series.genres,
            themes: series.themes,
            tags: series.tags,
            tagRecords: series.tagRecords,
            providerNeighborSignals: series.providerNeighborSignals,
            contentWarnings: series.contentWarnings,
            mediaType: mediaType
        )
    }

    private func needsShelfClassificationReview(_ suggestion: SableLibraryShelfSuggestion?) -> Bool {
        guard let suggestion else { return false }
        return suggestion.shelf.code == "00"
            || suggestion.confidenceLevel == .low
            || suggestion.confidenceLevel == .needsReview
    }

    private func shelfSortingReviewReason(
        _ suggestion: SableLibraryShelfSuggestion,
        ledger: SableLibraryShelfDecisionLedger?
    ) -> String {
        let lead = "SSS suggests \(suggestion.subShelf.displayName) with \(suggestion.confidenceLevel.displayName.lowercased()) confidence."
        if let ledger {
            let needed = ledger.neededEvidence.isEmpty
                ? ""
                : " Better evidence: \(ledger.neededEvidence.prefix(2).joined(separator: ", "))."
            return "\(lead) \(ledger.actionability.displayName).\(needed) Check this shelf, then tick it if it fits or leave it unchecked."
        }
        let warning = shelfSortingPrimaryWarning(suggestion.warnings)
            .map { " \($0)" }
            ?? " The evidence is thin or close to another shelf."
        return "\(lead)\(warning) Check this shelf, then tick it if it fits or leave it unchecked."
    }

    private func shelfSortingConfidenceNote(
        _ suggestion: SableLibraryShelfSuggestion?,
        ledger: SableLibraryShelfDecisionLedger?,
        depth: SableLibraryFolderOrganizationDepth
    ) -> String? {
        guard depth.includesShelf, let suggestion else { return nil }
        let evidenceCount = suggestion.evidence.count
        let evidenceText = evidenceCount == 1 ? "1 evidence point" : "\(evidenceCount) evidence points"
        let percent = Int((suggestion.confidence * 100).rounded())
        let sourceSummary = shelfSortingSourceSummary(suggestion.evidence)
        let evidenceSummary = shelfSortingEvidenceSummary(suggestion.evidence)
        let warningSummary = shelfSortingWarningSummary(suggestion.warnings)
        let ledgerSummary = shelfSortingLedgerSummary(ledger)
        return "SSS folder depth is \(depth.label); suggested \(suggestion.displayPath) with \(suggestion.confidenceLevel.displayName.lowercased()) confidence (\(percent)%) from \(evidenceText).\(sourceSummary)\(evidenceSummary)\(ledgerSummary)\(warningSummary)"
    }

    private func shelfSortingSourceSummary(_ evidence: [SableLibraryShelfEvidencePoint]) -> String {
        let sources = evidence
            .map(\.source)
            .filter { $0 != .safety }
            .reduce(into: [SableLibraryShelfEvidenceSource]()) { result, source in
                if !result.contains(source) {
                    result.append(source)
                }
            }
            .map(\.displayName)
        guard !sources.isEmpty else { return "" }
        return " Sources: \(sources.joined(separator: ", "))."
    }

    private func shelfSortingEvidenceSummary(_ evidence: [SableLibraryShelfEvidencePoint]) -> String {
        let snippets = evidence.prefix(3).map { point in
            let terms = point.matchedTerms.prefix(3).joined(separator: ", ")
            if terms.isEmpty {
                return point.source.displayName
            }
            return "\(point.source.displayName): \(terms)"
        }
        guard !snippets.isEmpty else { return "" }
        return " Evidence: \(snippets.joined(separator: "; "))."
    }

    private func shelfSortingWarningSummary(_ warnings: [String]) -> String {
        guard let warning = shelfSortingPrimaryWarning(warnings) else { return "" }
        return " Note: \(warning)"
    }

    private func shelfSortingLedgerSummary(_ ledger: SableLibraryShelfDecisionLedger?) -> String {
        guard let ledger else { return "" }
        var parts = ["Actionability: \(ledger.actionability.displayName)."]
        if let reason = ledger.whyNotCompeting.first {
            parts.append("Nearest shelf check: \(reason)")
        }
        if !ledger.neededEvidence.isEmpty {
            parts.append("To improve confidence: \(ledger.neededEvidence.prefix(2).joined(separator: ", ")).")
        }
        return " \(parts.joined(separator: " "))"
    }

    private func shelfSortingPrimaryWarning(_ warnings: [String]) -> String? {
        warnings.first { warning in
            let lowercased = warning.lowercased()
            return !lowercased.contains("content")
                && !lowercased.contains("access")
                && !lowercased.contains("user-controlled")
        } ?? warnings.first
    }

    private func shelfSortingReviewTags(
        _ suggestion: SableLibraryShelfSuggestion?,
        depth: SableLibraryFolderOrganizationDepth
    ) -> [String] {
        guard depth.includesShelf, let suggestion else { return ["sss-folder-depth-\(depth.rawValue)"] }
        var tags = [
            "sss-folder-depth-\(depth.rawValue)",
            "sss-\(suggestion.shelf.code)",
            "sss-\(suggestion.subShelf.code)"
        ]
        if needsShelfClassificationReview(suggestion) {
            tags.append("sss-shelf-review")
        }
        return tags
    }

    private func inferredReadingMediaType(for series: LibrarySeriesSnapshot, root: URL) -> String? {
        if isOrdinaryBooksLane(path: series.path, root: root) {
            return SableLibraryReadingType.book.rawValue
        }

        return nil
    }

    private func isOrdinaryBooksLane(path: String, root: URL) -> Bool {
        let components = path
            .split(separator: "/")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        let knownReadingRoots: Set<String> = [
            "manga",
            "manhwa",
            "manhua",
            "oel",
            "light novels",
            "comics",
            "comic books",
            "graphic novels",
            "other reading"
        ]

        if let first = components.first {
            if first == "books" {
                return true
            }
            if knownReadingRoots.contains(first) {
                return false
            }
        }

        return root.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "books"
    }

    private func effectiveReadingFolderTitle(
        for series: LibrarySeriesSnapshot,
        preferredTitle: String,
        service: SableLibraryService
    ) -> String {
        if let localTitle = bestLocalReadingTitle(for: series),
           trustedProviderAliasMatch(
               for: series,
               currentTitle: localTitle,
               preferredTitle: preferredTitle
           ) {
            return preferredTitle
        }

        if let localTitle = bestLocalReadingTitle(for: series),
           hasReadingSourceID(.mangabaka, in: series),
           localReadingTitleIsProtectable(for: series),
           shouldPreserveLocalReadingTitle(localTitle, providerTitle: preferredTitle, service: service) {
            return localTitle
        }

        if let localTitle = bestLocalReadingTitle(for: series),
           localReadingTitleIsProtectable(for: series),
           shouldPreserveLocalReadingTitle(localTitle, providerTitle: preferredTitle, service: service) {
            return localTitle
        }

        guard containsCJK(preferredTitle) else {
            return preferredTitle
        }

        if let localTitle = bestLocalReadingTitle(for: series),
           !containsCJK(localTitle) {
            return localTitle
        }

        return preferredTitle
    }

    private func localReadingTitleIsProtectable(for series: LibrarySeriesSnapshot) -> Bool {
        if series.localTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return true
        }

        guard let firstComponent = series.path.split(separator: "/").first else {
            return false
        }
        let root = String(firstComponent)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let knownReadingRoots: Set<String> = [
            "books",
            "light novels",
            "novels",
            "manga",
            "manhwa",
            "manhua",
            "oel",
            "comics",
            "comic books",
            "graphic novels",
            "other reading"
        ]
        return knownReadingRoots.contains(root)
    }

    private func hasReadingSourceID(_ provider: SableLibraryMetadataProvider, in series: LibrarySeriesSnapshot) -> Bool {
        let ids = (series.identityGraph?.sourceIDs ?? []) + [series.primarySourceID].compactMap { $0 }
        return ids.contains { $0.provider == provider }
    }

    private func shouldPreserveLocalReadingTitle(
        _ localTitle: String,
        providerTitle: String,
        service: SableLibraryService
    ) -> Bool {
        if providerTitleHasConflictingSeriesMarker(localTitle: localTitle, providerTitle: providerTitle) {
            return true
        }
        if titleConflict(localTitle, providerTitle, service: service) {
            return true
        }
        if providerTitleLosesLocalSeriesMarker(localTitle: localTitle, providerTitle: providerTitle) {
            return true
        }
        return providerTitleDropsMeaningfulSubtitle(localTitle: localTitle, providerTitle: providerTitle, service: service)
    }

    private func titleConflict(_ lhs: String, _ rhs: String, service: SableLibraryService) -> Bool {
        let lhsKey = service.normalizeTerm(lhs)
        let rhsKey = service.normalizeTerm(rhs)
        guard !lhsKey.isEmpty, !rhsKey.isEmpty, lhsKey != rhsKey else {
            return false
        }
        if lhsKey.contains(rhsKey) || rhsKey.contains(lhsKey) {
            return false
        }
        return tokenSimilarity(lhsKey, rhsKey) < 0.72
    }

    private func providerTitleDropsMeaningfulSubtitle(
        localTitle: String,
        providerTitle: String,
        service: SableLibraryService
    ) -> Bool {
        let localKey = service.normalizeTerm(seriesTitleWithoutVolumeSuffix(localTitle))
        let providerKey = service.normalizeTerm(seriesTitleWithoutVolumeSuffix(providerTitle))
        guard !localKey.isEmpty,
              !providerKey.isEmpty,
              localKey != providerKey,
              localKey.contains(providerKey),
              !providerKey.contains(localKey) else {
            return false
        }

        let remainder = localKey
            .replacingOccurrences(of: providerKey, with: " ")
            .replacingOccurrences(of: #"\b(?:the|a|an|and|or|of|to|in|with|for|from|by|as|is|was|were|i|my|this)\b"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = remainder.split(separator: " ").filter { $0.count > 2 }
        return tokens.count >= 2
    }

    private func tokenSimilarity(_ lhs: String, _ rhs: String) -> Double {
        let lhsTokens = Set(lhs.split(separator: " ").map(String.init))
        let rhsTokens = Set(rhs.split(separator: " ").map(String.init))
        guard !lhsTokens.isEmpty, !rhsTokens.isEmpty else { return 0 }
        let overlap = lhsTokens.intersection(rhsTokens).count
        let union = lhsTokens.union(rhsTokens).count
        return union == 0 ? 0 : Double(overlap) / Double(union)
    }

    private func bestLocalReadingTitle(for series: LibrarySeriesSnapshot) -> String? {
        for candidate in [series.localTitle, series.displayName] {
            guard let candidate else { continue }
            let clean = seriesTitleWithoutVolumeSuffix(candidate)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty {
                return clean
            }
        }
        return nil
    }

    private func seriesTitleWithoutVolumeSuffix(_ value: String) -> String {
        let cleaned = value
            .replacingOccurrences(
                of: #"(?i)\s*,?\s*(?:vol(?:ume)?|book|ch(?:apter)?|v)\.?\s*\d{1,4}(?:\.\d+)?(?:\s*[-–—:]\s*.*)?(?:\s*\([^)]*\))?\s*$"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",-–—:")))
        return cleaned.isEmpty ? value : cleaned
    }

    private func containsCJK(_ text: String) -> Bool {
        text.range(of: #"[\p{Han}\p{Hiragana}\p{Katakana}]"#, options: .regularExpression) != nil
    }

    private func readingSourceIDs(for series: LibrarySeriesSnapshot) -> [SableLibrarySourceID] {
        var selected: [SableLibrarySourceID] = []
        var seen = Set<String>()

        func append(_ sourceID: SableLibrarySourceID?) {
            guard let sourceID else { return }
            let key = "\(sourceID.provider.rawValue):\(sourceID.value)"
            guard seen.insert(key).inserted else { return }
            selected.append(sourceID)
        }

        let folderIDs = SableLibrarySourceIDParser.folderHints(in: series.path)
        let unavailableProviders = Set(series.unavailableMetadataProviders)
        let rejectedSourceIDs = rejectedProviderSourceIDs(for: series)
        let all = (series.identityGraph?.sourceIDs ?? [])
            + [series.primarySourceID].compactMap { $0 }
            + folderIDs
        let available = all.filter {
            !unavailableProviders.contains($0.provider)
                && !rejectedSourceIDs.contains(sourceIDKey($0))
        }

        // Preserve MB + RDB together when known.
        append(available.first { $0.provider == .mangabaka })
        append(available.first { $0.provider == .ranobedb })
        append(folderIDs.first { $0.provider == .myAnimeList })
        append(folderIDs.first { $0.provider == .anilist })

        // Fallback if the sidecar has only another stable catalog ID.
        // Open Library IDs are helpful evidence but too broad for folder identity;
        // prose works, editions, series, and omnibuses can share confusing book-catalog anchors.
        if selected.isEmpty {
            append(available.first { $0.provider != .openLibrary })
        }

        return selected
    }

    private func rejectedProviderSourceIDs(for series: LibrarySeriesSnapshot) -> Set<String> {
        Set(series.providerCandidateReviews.compactMap { review in
            guard review.status == .noMatch,
                  let sourceID = review.sourceID else {
                return nil
            }
            return sourceIDKey(sourceID)
        })
    }

    private func sourceIDKey(_ sourceID: SableLibrarySourceID) -> String {
        "\(sourceID.provider.rawValue):\(sourceID.value)"
    }

    private func folderReviewTags(_ tags: [String], sourceIDs: [SableLibrarySourceID]) -> [String] {
        var values = tags + ["naming-folder-rename"]
        for provider in sourceIDs.map(\.provider) {
            values.append("provider-token-\(provider.rawValue.lowercased())")
        }
        return Array(Set(values)).sorted()
    }

    private func folderRenameReview(
        currentPath: String,
        proposedPath: String,
        trustedAliasUpgrade: Bool = false
    ) -> FolderRenameReview {
        let currentTitle = folderTitleForReview(in: currentPath)
        let proposedTitle = folderTitleForReview(in: proposedPath)
        let currentTitleKey = folderTitleKey(currentTitle)
        let proposedTitleKey = folderTitleKey(proposedTitle)
        let currentTokens = folderSourceTokenSet(in: currentPath)
        let proposedTokens = folderSourceTokenSet(in: proposedPath)
        let tokenChange = currentTokens != proposedTokens
        var tags: [String] = []

        if tokenChange {
            tags.append("naming-provider-token-change")
        } else if !currentTokens.isEmpty {
            tags.append("naming-provider-token-preserved")
        }

        if !currentTitleKey.isEmpty, !proposedTitleKey.isEmpty, currentTitleKey != proposedTitleKey {
            tags.append(contentsOf: ["naming-title-change", "training-material"])
            if trustedAliasUpgrade, !tokenChange {
                tags.append("naming-provider-alias-upgrade")
                return FolderRenameReview(
                    requiresChoice: false,
                    reason: "The current folder title is a saved provider alias for this exact series. Sable checked the canonical provider title as a reversible rename.",
                    confidenceNote: "The provider IDs stay attached and the old title is present in provider metadata, so this alias upgrade is high confidence.",
                    reviewTags: tags
                )
            }
            return FolderRenameReview(
                requiresChoice: true,
                reason: "Metadata would change the visible folder title from \(currentTitle) to \(proposedTitle). Confirm before renaming so local titles stay intentional.",
                confidenceNote: "The title text changes, so this stays unchecked even when the sidecar has provider IDs.",
                reviewTags: tags
            )
        }

        if tokenChange {
            tags.append("training-material")
            return FolderRenameReview(
                requiresChoice: true,
                reason: "Provider ID tokens in the folder name would change. Confirm before applying so known IDs like RanobeDB stay attached.",
                confidenceNote: "The title looks stable, but provider tokens change; Sable keeps this as a review choice.",
                reviewTags: tags
            )
        }

        if !currentTitle.isEmpty,
           !proposedTitle.isEmpty,
           currentTitle != proposedTitle,
           currentTitleKey == proposedTitleKey {
            tags.append(contentsOf: ["naming-punctuation-only", "training-material"])
            return FolderRenameReview(
                requiresChoice: false,
                reason: "Only punctuation or spacing in the visible title would change. Sable checked it because the readable title stays the same.",
                confidenceNote: "This is a low-visibility cleanup, so it remains reversible and can be unchecked before applying.",
                reviewTags: tags
            )
        }

        return FolderRenameReview(
            requiresChoice: false,
            reason: nil,
            confidenceNote: nil,
            reviewTags: tags
        )
    }

    private func trustedProviderAliasMatch(
        for series: LibrarySeriesSnapshot,
        currentTitle: String,
        preferredTitle: String
    ) -> Bool {
        let sourceIDs = readingSourceIDs(for: series)
        guard sourceIDs.contains(where: {
            $0.provider == .ranobedb || $0.provider == .mangabaka
        }) else {
            return false
        }

        let currentKey = providerAliasTitleKey(currentTitle)
        let preferredKey = providerAliasTitleKey(preferredTitle)
        guard !currentKey.isEmpty,
              !preferredKey.isEmpty,
              currentKey != preferredKey else {
            return false
        }

        return series.trustedProviderTitles.contains { title in
            let aliasKey = providerAliasTitleKey(title)
            return aliasKey == currentKey && aliasKey != preferredKey
        }
    }

    private func providerAliasTitleKey(_ title: String) -> String {
        title
            .replacingOccurrences(
                of: #"(?i)\s*(?:[-–—:]\s*)?(?:light\s*novel|novel|manga|manhwa|manhua|oel|comic)\s*$"#,
                with: "",
                options: .regularExpression
            )
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: "", options: .regularExpression)
    }

    private func folderTitleForReview(in path: String) -> String {
        let name = (path as NSString).lastPathComponent
        let withoutTokens = name.replacingOccurrences(
            of: #"(?i)\s*\{(?:mb|mangabaka|rdb|ranobedb|ol|openlibrary|open_library|mal|myanimelist|my_anime_list|anilist|al|tvmaze|wikidata|wd|tmdb|tvdb|imdb|local)-[^}]+\}\s*"#,
            with: " ",
            options: .regularExpression
        )
        let withoutYear = withoutTokens.replacingOccurrences(
            of: #"\s*[\(\[]\d{4}[\)\]]\s*$"#,
            with: "",
            options: .regularExpression
        )
        return withoutYear
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "-:")))
    }

    private func folderTitleKey(_ title: String) -> String {
        title
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "[‘’`´]", with: "'", options: .regularExpression)
            .replacingOccurrences(of: "[“”]", with: "\"", options: .regularExpression)
            .replacingOccurrences(of: "[–—−]", with: "-", options: .regularExpression)
            .replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func folderSourceTokenSet(in path: String) -> Set<String> {
        Set(folderSourceTokenLabels(in: path).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        })
    }

    private func folderSourceTokenLabels(in path: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?i)\{(?:mb|mangabaka|rdb|ranobedb|ol|openlibrary|open_library|mal|myanimelist|my_anime_list|anilist|al|tvmaze|wikidata|wd|tmdb|tvdb|imdb|local)-[^}]+\}"#
        ) else {
            return []
        }
        let nsPath = path as NSString
        let fullRange = NSRange(location: 0, length: nsPath.length)
        return regex.matches(in: path, range: fullRange).map { match in
            nsPath.substring(with: match.range)
        }
    }

    private struct FolderRenameReview {
        var requiresChoice: Bool
        var reason: String?
        var confidenceNote: String?
        var reviewTags: [String]
    }

    private enum ReadingSeriesMarker: Hashable {
        case part(Int)
        case fanbook
        case shortStories
        case sideStory
        case relationship(String)
    }

    private func providerTitleLosesLocalSeriesMarker(localTitle: String, providerTitle: String) -> Bool {
        let localMarkers = readingSeriesMarkers(in: localTitle)
        guard !localMarkers.isEmpty else { return false }

        let providerMarkers = readingSeriesMarkers(in: providerTitle)
        if providerTitleHasConflictingSeriesMarker(localTitle: localTitle, providerTitle: providerTitle) {
            return true
        }

        return !localMarkers.isSubset(of: providerMarkers)
    }

    private func providerTitleHasConflictingSeriesMarker(localTitle: String, providerTitle: String) -> Bool {
        let localMarkers = readingSeriesMarkers(in: localTitle)
        let providerMarkers = readingSeriesMarkers(in: providerTitle)

        if localMarkers.contains(where: isPartMarker), providerMarkers.contains(.fanbook) {
            return true
        }
        if localMarkers.contains(.fanbook), providerMarkers.contains(where: isPartMarker) {
            return true
        }
        let localRelationships = relationshipMarkers(in: localMarkers)
        let providerRelationships = relationshipMarkers(in: providerMarkers)
        if !localRelationships.isEmpty,
           !providerRelationships.isEmpty,
           !localRelationships.isSubset(of: providerRelationships) {
            return true
        }

        return false
    }

    private func isPartMarker(_ marker: ReadingSeriesMarker) -> Bool {
        if case .part = marker {
            return true
        }
        return false
    }

    private func readingSeriesMarkers(in title: String) -> Set<ReadingSeriesMarker> {
        var markers = Set<ReadingSeriesMarker>()
        let normalized = title
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()

        if normalized.range(of: #"\bfan\s*book\b|\bfanbook\b"#, options: .regularExpression) != nil {
            markers.insert(.fanbook)
        }
        if normalized.range(of: #"\bshort\s+stor(y|ies)\b"#, options: .regularExpression) != nil {
            markers.insert(.shortStories)
        }
        if normalized.range(of: #"\bside\s+stor(y|ies)\b"#, options: .regularExpression) != nil {
            markers.insert(.sideStory)
        }
        for relationship in readingRelationshipMarkers(in: title) {
            markers.insert(.relationship(relationship))
        }

        for partNumber in readingPartNumbers(in: normalized) {
            markers.insert(.part(partNumber))
        }

        return markers
    }

    private func relationshipMarkers(in markers: Set<ReadingSeriesMarker>) -> Set<String> {
        Set(markers.compactMap { marker in
            if case .relationship(let value) = marker {
                return value
            }
            return nil
        })
    }

    private func readingRelationshipMarkers(in title: String) -> Set<String> {
        let foldedTitle = title
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var markers = Set<String>()
        if foldedTitle.range(of: #"\bfiancee?\b|\bkon\s*yakusha\b|\bkonyakusha\b"#, options: .regularExpression) != nil {
            markers.insert("fiancee")
        }
        if foldedTitle.range(of: #"\bwife\b|\bwives\b|\btsuma\b"#, options: .regularExpression) != nil {
            markers.insert("wife")
        }
        return markers
    }

    private func readingPartNumbers(in normalizedTitle: String) -> [Int] {
        guard let regex = try? NSRegularExpression(pattern: #"\bpart\s*([0-9]+)\b"#) else {
            return []
        }
        let nsTitle = normalizedTitle as NSString
        let fullRange = NSRange(location: 0, length: nsTitle.length)
        return regex.matches(in: normalizedTitle, range: fullRange).compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            return Int(nsTitle.substring(with: match.range(at: 1)))
        }
    }

    private func videoPlanItem(
        for series: LibraryVideoSeriesSnapshot,
        root: URL,
        plannedDestinations: inout [String: String],
        service: SableLibraryService
    ) -> LibraryPlanItem? {
        guard series.hasAnimeInfo else { return nil }
        guard !series.path.isEmpty else { return nil }
        guard hasTrustedWatchingIdentity(series) else { return nil }
        guard let preferredTitle = series.preferredTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
              !preferredTitle.isEmpty else {
            return nil
        }

        guard let mediaType = effectiveWatchingMediaType(for: series) else {
            return nil
        }
        let canonicalPath = namingPolicy.canonicalWatchingSeriesPath(
            preferredTitle: preferredTitle,
            year: series.year,
            sourceID: series.primarySourceID,
            mediaType: mediaType
        )
        guard canonicalPath != series.path else { return nil }
        guard canonicalPath.lowercased() != series.path.lowercased() else { return nil }

        let sourceURL = root.appendingPathComponent(series.path, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard service.fileManager.fileExists(atPath: sourceURL.path(percentEncoded: false), isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }

        let proposedURL = root.appendingPathComponent(canonicalPath, isDirectory: true)
        let destinationExists = service.fileManager.fileExists(atPath: proposedURL.path(percentEncoded: false))
        let plannedCollisionSource = plannedDestinations[canonicalPath]
        let hasCollision = destinationExists || plannedCollisionSource != nil
        plannedDestinations[canonicalPath] = series.path

        return LibraryPlanItem(
            stage: .canonicalFolders,
            operation: .renameFolder,
            currentPath: series.path,
            proposedPath: canonicalPath,
            reason: hasCollision
                ? collisionExplanation(proposedPath: canonicalPath, destinationExists: destinationExists, plannedCollisionSource: plannedCollisionSource) ?? "Another folder already uses this watching name."
                : "Folder can move into the AnimeInfo watching type folder with its preferred title, year, and any Plex-supported ID already known.",
            confidence: hasCollision ? .medium : .high,
            safety: hasCollision ? .collision : .reversible,
            decision: hasCollision ? .unchecked : .checked,
            requiresReview: hasCollision,
            confidenceExplanation: hasCollision
                ? "Another folder already uses the target name, so this stays out of quiet apply."
                : "AnimeInfo provides a trusted title and a known watching type. TMDB, TVDB, or IMDb is added only when already known.",
            correctionOptions: [.wrongType, .keepTitle, .custom],
            receipt: "\(series.path) -> \(canonicalPath)"
        )
    }

    private func effectiveWatchingMediaType(for series: LibraryVideoSeriesSnapshot) -> String? {
        let rawMediaType = series.mediaType?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if isKnownWatchingMediaType(rawMediaType) {
            return rawMediaType
        }

        return watchingTypeHint(in: series.path)
    }

    private func hasTrustedWatchingIdentity(_ series: LibraryVideoSeriesSnapshot) -> Bool {
        if series.primarySourceID != nil {
            return true
        }

        if let source = series.animeInfoSource?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !source.isEmpty,
           source != "local" {
            return true
        }

        return series.identityGraph?.sourceIDs.contains { sourceID in
            switch sourceID.provider {
            case .myAnimeList, .anilist, .tvmaze, .wikidata, .tmdb, .tvdb, .imdb:
                return true
            case .mangabaka, .ranobedb, .openLibrary, .local:
                return false
            }
        } == true
    }

    private func isKnownWatchingMediaType(_ mediaType: String) -> Bool {
        switch mediaType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "animemovie", "anime movie",
             "animetv", "anime tv", "tv_anime",
             "ova", "ona", "special", "specials",
             "movie",
             "tvshow", "tv show", "tv":
            return true
        default:
            return false
        }
    }

    private func watchingTypeHint(in path: String) -> String? {
        guard let firstComponent = path.split(separator: "/").first else { return nil }
        switch String(firstComponent).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "anime tv":
            return SableLibraryWatchingType.animeTV.rawValue
        case "anime movies":
            return SableLibraryWatchingType.animeMovie.rawValue
        case "movies":
            return SableLibraryWatchingType.movie.rawValue
        case "tv", "tv shows":
            return SableLibraryWatchingType.tvShow.rawValue
        default:
            return nil
        }
    }

    private func hasPendingWatchingPreparation(in plan: LibraryPlan, config: SableLibraryConfig) -> Bool {
        let matcher = SableLibraryFileTypeMatcher(config: config)
        return plan.items.contains { item in
            switch item.operation {
            case .createAnimeInfo, .refreshAnimeInfo:
                return item.stage.isMetadataSidecarStage
            case .sortIntoFolder, .cleanRawName:
                guard item.stage == .prepareRawFiles else { return false }
                let currentURL = URL(fileURLWithPath: item.currentPath)
                let proposedURL = item.proposedPath.map { URL(fileURLWithPath: $0) }
                return matcher.isVideo(url: currentURL, isDirectory: false)
                    || proposedURL.map { matcher.isVideo(url: $0, isDirectory: false) } == true
            case .inspectOnly, .repairEpubPackage, .repairAppleBooksCompatibility, .createComicInfo, .refreshComicInfo, .renameFolder, .renameFile, .duplicateDecision, .skip:
                return false
            }
        }
    }

    private func collisionExplanation(
        proposedPath: String,
        destinationExists: Bool,
        plannedCollisionSource: String?
    ) -> String? {
        if destinationExists {
            return "Destination already exists: \(proposedPath). Review it as a possible duplicate or wrong media type before moving anything."
        }
        if let plannedCollisionSource {
            return "Another suggestion is already targeting \(proposedPath) from \(plannedCollisionSource). Review these together."
        }
        return nil
    }

    private func examples(from items: [LibraryPlanItem]) -> [LibraryPlanExample] {
        items.prefix(3).map { item in
            LibraryPlanExample(
                title: "Folder rename",
                before: item.currentPath,
                after: item.proposedPath,
                reason: item.reason
            )
        }
    }

    private func confidenceExplanation(
        hasCollision: Bool,
        hasKnownType: Bool,
        currentTypeHint: String?,
        normalizedMediaType: String,
        typeWasInferred: Bool,
        volumeConflict: SableLibraryVolumeConflict?,
        collisionDetail: String?,
        shelfSortingNote: String?
    ) -> String {
        let volumeNote = volumeConflict.map { " MangaBaka final volume \($0.finalVolume) may be behind local Vol \($0.localHighestVolume); not used as a blocker." } ?? ""
        let shelfNote = shelfSortingNote.map { " \($0)" } ?? ""
        if let currentTypeHint, hasKnownType, currentTypeHint != normalizedMediaType {
            let detail = "Folder type hint \(currentTypeHint) does not match ComicInfo type \(normalizedMediaType)."
            if let collisionDetail {
                return "\(detail) \(collisionDetail)\(volumeNote)\(shelfNote)"
            }
            return "\(detail)\(volumeNote)\(shelfNote)"
        }
        if hasCollision {
            return "\(collisionDetail ?? "Another folder already uses the target name, so this needs duplicate/collision review.")\(volumeNote)\(shelfNote)"
        }
        if !hasKnownType {
            return "ComicInfo title exists, but media type is unknown.\(volumeNote)\(shelfNote)"
        }
        if typeWasInferred {
            return "ComicInfo has no type, but this folder is in the ordinary Books area, so Sable treats it as Book for folder sorting.\(volumeNote)\(shelfNote)"
        }
        return "ComicInfo provides a preferred title and known type.\(volumeNote)\(shelfNote)"
    }

    private func localVolumeConflict(in series: LibrarySeriesSnapshot) -> SableLibraryVolumeConflict? {
        guard let finalVolume = series.finalVolume,
              let localHighestVolume = series.localHighestVolume,
              localHighestVolume > finalVolume else {
            return nil
        }
        return SableLibraryVolumeConflict(finalVolume: finalVolume, localHighestVolume: localHighestVolume)
    }
}
