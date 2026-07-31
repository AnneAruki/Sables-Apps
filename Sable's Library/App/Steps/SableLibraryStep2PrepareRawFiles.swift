//
//  SableLibraryStep2PrepareRawFiles.swift
//  Sable's Library
//

import Foundation
import UniformTypeIdentifiers

nonisolated struct SableLibraryStep2PrepareRawFiles: Sendable {
    private struct EPUBClinicBookResult: Sendable {
        var index: Int
        var fileName: String
        var repairItems: [LibraryPlanItem]
    }

    private enum EPUBCheckerLayer: String, CaseIterable {
        case sidecarMetadata
        case sidecarTags
        case container
        case packageManifest
        case metadataIdentifiers
        case navigation
        case contentDocuments
        case coversImages
        case readerImport
        case structure
        case standardsProfile
        case manualDiagnostics
        case fixedLayoutDiagnostics
        case protectionDiagnostics

        var reviewTag: String {
            "epub-layer-\(rawValue)"
        }
    }

    func prepareEPUBClinic(context: LibraryPipelineContext, service: SableLibraryService) async -> [LibraryPlanGroup] {
        service.reportProgress("Sable's Clinic: checking light repair and import metadata work")

        guard context.options.stages.repairEPUBs,
              context.inspectMode.wakesEPUBRepairSpecialists,
              let inspection = context.inspection else {
            return []
        }

        let config = service.currentConfig()
        let candidateBooks = epubClinicCandidateBooks(from: inspection.books, mode: context.inspectMode)
        let modifiedWindow = context.options.stages.epubClinicModifiedWindow
        let books = candidateBooks.filter {
            modifiedWindow.includes(modificationDate: $0.modificationDate)
        }
        let runsDeepContentChecks = context.options.stages.deepEPUBContentChecks
        let repairScopes = context.options.stages.epubClinicRepairScopes.isEmpty
            ? SableLibraryEPUBRepairScope.all
            : context.options.stages.epubClinicRepairScopes
        let checkProfile = SableClinicCheckProfile.matching(
            scopes: repairScopes,
            deepContentChecks: runsDeepContentChecks
        )
        guard !books.isEmpty else {
            let scope = modifiedWindow.repairScopeDescription
            service.reportProgress("Sable's Clinic: no \(scope) need this repair pass")
            return []
        }

        service.reportProgress("Sable's Clinic: running \(checkProfile.title.lowercased()) for \(modifiedWindow.repairScopeDescription)")
        let startedAt = Date()
        let parallelism = SableLibraryAdaptiveWorkBudget.parallelism(
            minimum: 1,
            multiplier: 1,
            cap: 2,
            itemCount: books.count
        )
        service.reportProgress("Sable's Clinic: using \(parallelism) careful background worker(s)")
        let repairResults = await withTaskGroup(
            of: EPUBClinicBookResult.self,
            returning: [EPUBClinicBookResult].self
        ) { group in
            let initialCount = min(parallelism, books.count)
            for index in 0..<initialCount {
                let book = books[index]
                group.addTask {
                    epubClinicBookResult(
                        index: index,
                        book: book,
                        root: context.root,
                        config: config,
                        deepContentChecks: runsDeepContentChecks,
                        repairScopes: repairScopes,
                        optimizePageImageEPUBs: context.options.stages.optimizePageImageEPUBs,
                        writeEPUBImportMetadata: context.options.stages.writeEPUBImportMetadata,
                        service: service
                    )
                }
            }

            var nextIndex = initialCount
            var completedCount = 0
            var results: [EPUBClinicBookResult] = []
            results.reserveCapacity(books.count)

            while let result = await group.next() {
                if Task.isCancelled {
                    group.cancelAll()
                    break
                }

                results.append(result)
                completedCount += 1
                if completedCount == 1 || completedCount.isMultiple(of: 10) || completedCount == books.count {
                    let timing = SableLibraryWorkTiming.summary(
                        startedAt: startedAt,
                        completedCount: completedCount,
                        totalCount: books.count,
                        unit: "EPUB"
                    )
                    service.reportProgressSnapshot(SableLibraryProgressSnapshot(
                        title: "Sable's Clinic",
                        message: "\(checkProfile.title) checked \(completedCount) of \(books.count) EPUB file(s). \(timing) Current: \(epubClinicProgressFileName(result.fileName))",
                        completedUnitCount: completedCount,
                        totalUnitCount: books.count
                    ))
                    service.reportProgress("Sable's Clinic \(completedCount)/\(books.count): \(timing)")
                }

                if nextIndex < books.count {
                    let index = nextIndex
                    let book = books[index]
                    nextIndex += 1
                    group.addTask {
                        epubClinicBookResult(
                            index: index,
                            book: book,
                            root: context.root,
                            config: config,
                            deepContentChecks: runsDeepContentChecks,
                            repairScopes: repairScopes,
                            optimizePageImageEPUBs: context.options.stages.optimizePageImageEPUBs,
                            writeEPUBImportMetadata: context.options.stages.writeEPUBImportMetadata,
                            service: service
                        )
                    }
                }
            }
            return results.sorted { $0.index < $1.index }
        }
        service.reportProgressSnapshot(nil)
        guard !Task.isCancelled else { return [] }

        var packageRepairItems: [LibraryPlanItem] = []
        var appleBooksRepairItems: [LibraryPlanItem] = []
        for result in repairResults {
            for repairItem in result.repairItems {
                switch repairItem.operation {
                case .repairEpubPackage:
                    packageRepairItems.append(repairItem)
                case .repairAppleBooksCompatibility:
                    appleBooksRepairItems.append(repairItem)
                case .inspectOnly, .cleanRawName, .sortIntoFolder, .createComicInfo, .refreshComicInfo, .createAnimeInfo, .refreshAnimeInfo, .renameFolder, .renameFile, .duplicateDecision, .skip:
                    break
                }
            }
        }

        let blockedOrSourceNeededRepairCount =
            packageRepairItems.filter { !$0.isApplyableOperation }.count
            + appleBooksRepairItems.filter { !$0.isApplyableOperation }.count
        let runnablePackageRepairItems = packageRepairItems.filter(\.isApplyableOperation)

        var groups: [LibraryPlanGroup] = []
        if !runnablePackageRepairItems.isEmpty {
            groups.append(LibraryPlanGroup(
                stage: .epubClinic,
                title: "Repair EPUB packages",
                summary: "\(runnablePackageRepairItems.count) expanded EPUB package(s) can be rebuilt as normal EPUB files.",
                reviewPrompt: "Checked rows rebuild expanded packages into normal EPUB files, validate before and after, and keep the visible book path the same.",
                examples: packageRepairExamples(from: runnablePackageRepairItems),
                items: runnablePackageRepairItems
            ))
        }
        if !appleBooksRepairItems.isEmpty {
            let metadataCopy = context.options.stages.writeEPUBImportMetadata
                ? " Local ComicInfo, provider IDs, series, clean tags, and book-level facts can be mirrored into EPUB metadata."
                : ""
            let imageOptimization = context.options.stages.optimizePageImageEPUBs
                ? " Page-image optimization stays review-first because it is lossy."
                : ""
            groups.append(contentsOf: appleBooksRepairGroups(
                for: appleBooksRepairItems,
                metadataCopy: metadataCopy,
                imageOptimization: imageOptimization
            ))
        }

        let emptyRepairMessage = modifiedWindow == .all
            ? "Sable's Clinic: no repair work needed"
            : "Sable's Clinic: no repair work needed for \(modifiedWindow.repairScopeDescription)"
        let runnableRepairCount = groups.flatMap(\.items).filter(\.isApplyableOperation).count
        let repairMessage: String
        if runnableRepairCount == 0, blockedOrSourceNeededRepairCount > 0 {
            repairMessage = "Sable's Clinic: prepared \(blockedOrSourceNeededRepairCount) blocked or source-needed EPUB finding(s)"
        } else if runnableRepairCount > 0, blockedOrSourceNeededRepairCount > 0 {
            repairMessage = "Sable's Clinic: prepared \(runnableRepairCount) runnable repair suggestion(s); \(blockedOrSourceNeededRepairCount) blocked or source-needed finding(s) stay visible"
        } else {
            repairMessage = groups.isEmpty ? emptyRepairMessage : "Sable's Clinic: prepared \(runnableRepairCount) repair suggestion(s)"
        }
        service.reportProgress(repairMessage)
        return groups
    }

    private func epubClinicBookResult(
        index: Int,
        book: LibraryBookSnapshot,
        root: URL,
        config: SableLibraryConfig,
        deepContentChecks: Bool,
        repairScopes: Set<SableLibraryEPUBRepairScope>,
        optimizePageImageEPUBs: Bool,
        writeEPUBImportMetadata: Bool,
        service: SableLibraryService
    ) -> EPUBClinicBookResult {
        autoreleasepool {
            EPUBClinicBookResult(
                index: index,
                fileName: book.fileName,
                repairItems: epubRepairItems(
                    for: book,
                    stage: .epubClinic,
                    root: root,
                    config: config,
                    deepContentChecks: deepContentChecks,
                    repairScopes: repairScopes,
                    optimizePageImageEPUBs: optimizePageImageEPUBs,
                    writeEPUBImportMetadata: writeEPUBImportMetadata,
                    service: service
                )
            )
        }
    }

    private func epubClinicCandidateBooks(
        from books: [LibraryBookSnapshot],
        mode: LibraryPipelineInspectMode
    ) -> [LibraryBookSnapshot] {
        guard case let .quickVerify(previousStage, changedPaths, focusStage) = mode,
              previousStage == .epubClinic || focusStage == .epubClinic else {
            return books
        }

        let changedPathKeys = Set(changedPaths.map(Self.normalizedLibraryPathForComparison))
        guard !changedPathKeys.isEmpty else { return [] }

        return books.filter { book in
            changedPathKeys.contains(Self.normalizedLibraryPathForComparison(book.path))
        }
    }

    private func epubClinicProgressFileName(_ fileName: String) -> String {
        let limit = 86
        guard fileName.count > limit else { return fileName }
        return "\(fileName.prefix(limit - 3))..."
    }

    nonisolated private static func normalizedLibraryPathForComparison(_ path: String) -> String {
        path
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/", omittingEmptySubsequences: true)
            .joined(separator: "/")
    }

    private func appleBooksRepairGroups(
        for items: [LibraryPlanItem],
        metadataCopy: String,
        imageOptimization: String
    ) -> [LibraryPlanGroup] {
        guard !items.isEmpty else { return [] }

        let buckets = Dictionary(grouping: items) { item in
            epubCheckerLayer(for: item)
        }

        return EPUBCheckerLayer.allCases.compactMap { layer in
            appleBooksRepairGroup(
                layer: layer,
                items: buckets[layer] ?? [],
                reviewPrompt: epubRepairGroupPrompt(
                    layer,
                    metadataCopy: metadataCopy,
                    imageOptimization: imageOptimization
                )
            )
        }
    }

    private func appleBooksRepairGroup(
        layer: EPUBCheckerLayer,
        items: [LibraryPlanItem],
        reviewPrompt: String
    ) -> LibraryPlanGroup? {
        guard !items.isEmpty else { return nil }

        let sortedItems = items.sorted {
            $0.currentPath.localizedStandardCompare($1.currentPath) == .orderedAscending
        }

        return LibraryPlanGroup(
            stage: .epubClinic,
            title: epubRepairGroupTitle(layer),
            summary: epubRepairGroupSummary(layer, count: sortedItems.count),
            reviewPrompt: reviewPrompt,
            examples: appleBooksRepairExamples(from: sortedItems),
            items: sortedItems
        )
    }

    private func epubCheckerLayer(for item: LibraryPlanItem) -> EPUBCheckerLayer {
        EPUBCheckerLayer.allCases.first { layer in
            item.reviewTags.contains(layer.reviewTag)
        } ?? epubCheckerLayer(from: [item.reason])
    }

    private func epubCheckerLayer(from reasons: [String]) -> EPUBCheckerLayer {
        let normalized = reasons.joined(separator: " ").lowercased()
        if normalized.contains("description and subject")
            || normalized.contains("subject tag")
            || normalized.contains("subject tags") {
            return .sidecarTags
        }
        if normalized.contains("comicinfo")
            || normalized.contains("series and volume")
            || normalized.contains("title sorting")
            || normalized.contains("isbn/provider")
            || normalized.contains("creator, contributor") {
            return .sidecarMetadata
        }
        if normalized.contains("protected")
            || normalized.contains("encrypted")
            || normalized.contains("drm") {
            return .protectionDiagnostics
        }
        if normalized.contains("malformed xhtml") && !normalized.contains("guarded xhtml parser repair") {
            return .manualDiagnostics
        }
        if normalized.contains("fixed-layout")
            || normalized.contains("page box")
            || normalized.contains("optimization")
            || normalized.contains("optimize")
            || normalized.contains("lossy") {
            return .fixedLayoutDiagnostics
        }
        if normalized.contains("apple books cover import") {
            return .readerImport
        }
        if normalized.contains("cover") {
            return .coversImages
        }
        if normalized.contains("semantic heading")
            || normalized.contains("semantic chapter heading")
            || normalized.contains("chapter headings from existing ncx")
            || normalized.contains("ncx-backed") {
            return .structure
        }
        if normalized.contains("navigation")
            || normalized.contains("toc")
            || normalized.contains("ncx table of contents identifier")
            || normalized.contains("ncx table of contents target")
            || normalized.contains("ncx table of contents playorder")
            || normalized.contains("table of contents playorder")
            || normalized.contains("ncx pagelist")
            || normalized.contains("table of contents") {
            return .navigation
        }
        if normalized.contains("epub content-type")
            || normalized.contains("epub content document")
            || normalized.contains("duplicate epub content")
            || normalized.contains("orphan xhtml inline closing")
            || normalized.contains("missing local epub script")
            || normalized.contains("guarded xhtml parser repair")
            || normalized.contains("xhtml named")
            || normalized.contains("bare xhtml ampersand")
            || normalized.contains("xhtml void element")
            || normalized.contains("invalid xhtml control")
            || normalized.contains("retarget")
            || normalized.contains("missing epub linked resource")
            || normalized.contains("http-equiv")
            || normalized.contains("epub doctype")
            || normalized.contains("xhtml doctype")
            || normalized.contains("image dimension")
            || normalized.contains("non-breaking space")
            || normalized.contains("custom data")
            || normalized.contains("guarded epub css")
            || normalized.contains("simple epub css") {
            return .contentDocuments
        }
        if normalized.contains("metadata refinement")
            || normalized.contains("legacy epub metadata")
            || normalized.contains("opf package identifier") {
            return .metadataIdentifiers
        }
        if normalized.contains("package version")
            || normalized.contains("epub 3.4-compatible")
            || normalized.contains("3.3/3.4") {
            return .standardsProfile
        }
        if normalized.contains("mimetype")
            || normalized.contains("itunesmetadata")
            || normalized.contains("itunes metadata") {
            return .container
        }
        if normalized.contains("manifest")
            || normalized.contains("epub guide")
            || normalized.contains("svg")
            || normalized.contains("scripted")
            || normalized.contains("dead epub spine") {
            return .packageManifest
        }
        return .metadataIdentifiers
    }

    private func epubRepairGroupTitle(_ layer: EPUBCheckerLayer) -> String {
        switch layer {
        case .sidecarMetadata:
            return "EPUB metadata sync"
        case .sidecarTags:
            return "EPUB tag sync"
        case .container:
            return "EPUB container layer"
        case .packageManifest:
            return "EPUB package layer"
        case .metadataIdentifiers:
            return "EPUB metadata identifiers"
        case .navigation:
            return "EPUB navigation layer"
        case .contentDocuments:
            return "EPUB content layer"
        case .coversImages:
            return "EPUB cover/image layer"
        case .readerImport:
            return "Apple Books import refresh"
        case .structure:
            return "EPUB structure layer"
        case .standardsProfile:
            return "EPUB standards profile"
        case .manualDiagnostics:
            return "EPUB blocked repair findings"
        case .fixedLayoutDiagnostics:
            return "EPUB fixed-layout repairs"
        case .protectionDiagnostics:
            return "Protected EPUBs"
        }
    }

    private func epubRepairGroupSummary(
        _ layer: EPUBCheckerLayer,
        count: Int
    ) -> String {
        switch layer {
        case .sidecarMetadata:
            return "\(count) EPUB file(s) can sync identity, series, creators, identifiers, dates, pages, and reader import metadata from local sidecars."
        case .sidecarTags:
            return "\(count) EPUB file(s) can sync cleaned descriptions and display tags into standard EPUB metadata."
        case .container:
            return "\(count) EPUB file(s) can repair OCF/container-level packaging issues such as the mimetype entry or stale reader import files."
        case .packageManifest:
            return "\(count) EPUB file(s) can repair package manifest, guide, SVG, or scripted-resource declarations."
        case .metadataIdentifiers:
            return "\(count) EPUB file(s) can repair package identifier and metadata-refinement wiring."
        case .navigation:
            return "\(count) EPUB file(s) can repair EPUB navigation, NCX identifiers/targets, or create a TOC from existing structure."
        case .contentDocuments:
            return "\(count) EPUB file(s) can repair safe XHTML/content-document declarations, broken resource links, duplicate content IDs, and stale local script tags without rewriting book prose."
        case .coversImages:
            return "\(count) EPUB file(s) can repair cover markers or use a trusted language-matched library cover when it is clearly better."
        case .readerImport:
            return "\(count) EPUB file(s) can receive a fresh, validated import identity after Apple Books cached a stale or placeholder cover."
        case .structure:
            return "\(count) EPUB file(s) have NCX-backed chapter labels that can become semantic H1 headings after review."
        case .standardsProfile:
            return "\(count) EPUB file(s) can align EPUB 3.3/3.4-compatible package metadata with EPUB 3 version signaling."
        case .manualDiagnostics:
            return "\(count) EPUB file(s) need a new repair rule or a cleaner source before Sable can change the file."
        case .fixedLayoutDiagnostics:
            return "\(count) EPUB file(s) can repair fixed-layout, page-box, or page-image issues on a temporary EPUB first."
        case .protectionDiagnostics:
            return "\(count) EPUB file(s) look protected or encrypted and need an unlocked clean source."
        }
    }

    private func epubRepairGroupPrompt(
        _ layer: EPUBCheckerLayer,
        metadataCopy: String,
        imageOptimization: String
    ) -> String {
        switch layer {
        case .sidecarMetadata:
            return "Checked rows sync identity, series, volume, creator, publisher, language, dates, pages, and identifiers from local sidecars into EPUB package metadata. Book text and styling stay untouched.\(metadataCopy)"
        case .sidecarTags:
            return "Checked rows sync cleaned descriptions and display tags into EPUB subject and description fields. This helps readers and catalog tools without changing book text or styling."
        case .container:
            return "Checked rows repair container-level EPUB packaging only after building and validating a temporary EPUB. Sable does not delete the source unless the repaired copy validates."
        case .packageManifest:
            return "Checked rows repair manifest and guide declarations for resources that already exist in the EPUB. Sable does not invent missing chapters or convert the book."
        case .metadataIdentifiers:
            return "Checked rows repair package identifier wiring and metadata refinements so EPUBCheck, Apple Books, and catalog tools can read the same identity cleanly."
        case .navigation:
            return "Checked rows repair EPUB 3 navigation declarations, NCX identifiers, and TOC targets only from existing spine order, real chapter headings, document titles, or older NCX data. Sable does not rename headings, rewrite chapter HTML, or add page breaks."
        case .contentDocuments:
            return "Checked rows repair safe XHTML header and content-document declarations, duplicate content IDs, orphan inline closing tags, missing local script tags, and broken resource links with one clear target. Book text, reading order, and styling intent stay intact."
        case .coversImages:
            return "Checked rows repair EPUB cover markers and may use a trusted language-matched cover from the series _covers folder or local sidecar. Sable replaces an embedded image only when the candidate is clearly better, keeps dimension findings review-first, and validates a temporary EPUB before replacing the original."
        case .readerImport:
            return "These rows start unchecked. Applying one refreshes the EPUB import identity and cover markers, uses a clearly better language-matched cover when available, and validates the rebuilt EPUB. Remove the stale copy from Apple Books before importing the repaired EPUB so Apple Books does not keep both entries."
        case .structure:
            return "These rows start unchecked. When checked, Sable promotes only exact NCX-linked paragraph or div chapter labels into H1 headings. It keeps the text, anchors, classes, and book order, then validates a temporary EPUB before replacing the original."
        case .standardsProfile:
            return "Checked rows keep EPUB 3.3/3.4-compatible publications signaled as EPUB 3 using version 3.0, matching the current EPUB specification. Sable does not write a fake 3.4 package version."
        case .manualDiagnostics:
            return "Rows here stay visible because Sable does not have a safe local repair rule yet. Fixable EPUB problems should appear as checked repair rows; these need a cleaner source or a new repair rule."
        case .fixedLayoutDiagnostics:
            return "Checked rows repair fixed-layout page boxes and selected page-image work on a temporary EPUB, validate it, and keep the original if validation fails.\(imageOptimization)"
        case .protectionDiagnostics:
            return "Protected or encrypted book content cannot be safely rewritten by Sable. Replace these with an unlocked clean source, then run the Clinic again."
        }
    }

    func prepare(context: LibraryPipelineContext, service: SableLibraryService) async -> [LibraryPlanGroup] {
        service.reportProgress("Prepare raw files: checking loose and not-yet-cataloged files")

        guard let inspection = context.inspection else { return [] }
        let config = service.currentConfig()
        let modifiedWindow = context.options.stages.modifiedWindow(for: .prepareRawFiles)
        let sourceMetadataTermKeys = inspection.sourceMetadataTermKeys.isEmpty
            ? Set(config.sourceMetadataTerms.map(service.normalizeTerm))
            : Set(inspection.sourceMetadataTermKeys)
        let seriesByPath = inspection.series.reduce(into: [String: LibrarySeriesSnapshot]()) { partialResult, series in
            partialResult[series.path] = series
        }
        let scannedItems = (try? service.enumerateItems(root: context.root, config: config)) ?? []
        let protectedScope = SableLibraryProtectedFolderPolicy.scope(
            in: scannedItems,
            config: config,
            fileManager: service.fileManager
        )
        let allItems = protectedScope.allowingOnlyMutableItems(scannedItems)
        let candidateItems = modifiedWindow == .all
            ? allItems
            : allItems.filter {
                modifiedWindow.includes(modificationDate: $0.modificationDate)
            }
        let protectedRawFolderPaths = protectedRawFolderPaths(
            in: scannedItems,
            config: config,
            fileManager: service.fileManager
        ).union(protectedScope.paths)
        let scopedReadingSeriesPaths = Set(inspection.books.compactMap(\.seriesID))
        let scopedVideoSeriesPaths = Set(inspection.videos.compactMap(\.seriesID))
        let readingFolderCandidates = broadMediaFolderCandidates(
            paths: inspection.series.map(\.path),
            destinationRoot: "Books",
            root: context.root,
            service: service
        ).filter {
            !protectedRawFolderPaths.contains($0.key)
                && (modifiedWindow == .all || scopedReadingSeriesPaths.contains($0.key))
        }
        let videoFolderCandidates = broadMediaFolderCandidates(
            paths: inspection.videoSeries.map(\.path),
            destinationRoot: "Videos",
            root: context.root,
            service: service
        ).filter {
            !protectedRawFolderPaths.contains($0.key)
                && (modifiedWindow == .all || scopedVideoSeriesPaths.contains($0.key))
        }
        let handledTopLevelMediaPaths = Set(readingFolderCandidates.keys).union(videoFolderCandidates.keys)
        let readingFolderPathByName = folderPathByNormalizedName(readingFolderCandidates, service: service)
        let videoFolderPathByName = folderPathByNormalizedName(videoFolderCandidates, service: service)
        let existingReadingSeriesIndex = existingReadingSeriesFolderIndex(
            series: inspection.series,
            service: service
        )
        let readingClassifier = RawReadingLaneClassifier(
            root: context.root,
            service: service,
            learningMemory: context.options.learning,
            useLocalLearning: context.options.intelligence.useLocalLearning
        )
        let booksBySeriesPath = Dictionary(grouping: inspection.books.compactMap { book -> (String, LibraryBookSnapshot)? in
            guard let seriesID = book.seriesID, !seriesID.isEmpty else { return nil }
            return (seriesID, book)
        }, by: { $0.0 }).mapValues { rows in rows.map(\.1) }
        let looseVideoBareEpisodeSeriesTitleKeys = looseVideoBareEpisodeSeriesTitleKeys(
            videos: inspection.videos,
            config: config,
            sourceMetadataTermKeys: sourceMetadataTermKeys,
            service: service
        )
        let subtitlePlanner = SableLibrarySubtitleAttachmentPlanner()
        var plannedDestinations = Set<String>()
        var looseItems: [LibraryPlanItem] = []
        var pdfTriageItems: [LibraryPlanItem] = []
        var typeFolderItems: [LibraryPlanItem] = []
        if modifiedWindow == .all {
            looseItems.append(contentsOf: legacyWatchingRootItems(
                root: context.root,
                plannedDestinations: &plannedDestinations,
                service: service
            ))
        }

        for (index, book) in inspection.books.enumerated() {
            reportPreparationProgress(
                service: service,
                title: "Preparing raw files",
                message: "Checking loose book \(index + 1) of \(inspection.books.count): \(book.fileName)",
                completed: index + 1,
                total: inspection.books.count
            )
            let parentRelativePath = book.seriesID ?? ""
            let isLoose = parentRelativePath.isEmpty

            guard isLoose else { continue }

            let rawName = (book.fileName as NSString).deletingPathExtension
            let parsed = service.bookNameParts(for: rawName, config: config, sourceMetadataTermKeys: sourceMetadataTermKeys)
            let cleanFileName = cleanedFileName(from: parsed.fileTitle, originalFileName: book.fileName, service: service)

            guard context.options.cleanup.organizeLooseBooks else { continue }
            let folderName = service.sanitizeFilename(parsed.seriesTitle)
            let lane = readingClassifier.classifyLooseBook(
                for: book,
                parsed: parsed
            )
            let folderNameKeys = normalizedSeriesTitleMatchKeys(folderName, service: service)
            let existingSidecarFolder = existingReadingSeriesIndex.folderPath(
                forTitleKeys: folderNameKeys,
                preferredRoot: lane.folderName
            )
            let existingSeriesFolder = existingSidecarFolder ?? readingFolderPathByName[service.normalizeTerm(folderName)]
            let proposedPath = existingSeriesFolder.map { service.joinedRelativePath($0, cleanFileName) }
                ?? service.joinedRelativePath(lane.folderName, folderName, cleanFileName)
            let reason = existingSidecarFolder != nil
                ? "Moves the loose reading file into the existing series folder that already has ComicInfo, so new volumes do not need fresh metadata setup."
                : existingSeriesFolder == nil
                ? "Moves the loose reading file into \(lane.folderName), keeps the detected series folder, and uses the cleaned filename."
                : "Moves the loose reading file into its existing series folder first; the checked folder row can then place the whole series under its detected reading type."
            var item = planItem(
                operation: .sortIntoFolder,
                currentPath: book.path,
                proposedPath: proposedPath,
                reason: parsed.needsManualReview || lane.requiresReview ? "Review the final destination; the raw name has unclear folder, type, or volume clues." : reason,
                requiresReview: parsed.needsManualReview || lane.requiresReview,
                plannedDestinations: &plannedDestinations,
                root: context.root,
                service: service
            )
            if parsed.needsManualReview {
                item.reviewTags = Array(Set(item.reviewTags + ["raw-name-review"])).sorted()
            }
            applyRawReadingLane(lane, to: &item)
            if existingSidecarFolder != nil {
                item.reviewTags = Array(Set(item.reviewTags + ["raw-existing-series-update", "raw-reading-existing-series"])).sorted()
            }
            looseItems.append(item)
        }

        for (index, video) in inspection.videos.enumerated() {
            reportPreparationProgress(
                service: service,
                title: "Preparing raw files",
                message: "Checking loose video \(index + 1) of \(inspection.videos.count): \(video.fileName)",
                completed: index + 1,
                total: inspection.videos.count
            )
            let parentRelativePath = video.seriesID ?? ""
            let isLoose = parentRelativePath.isEmpty

            guard isLoose else { continue }

            let rawName = (video.fileName as NSString).deletingPathExtension
            let parsed = videoNameParts(
                for: rawName,
                parentFolderName: nil,
                requiresTitleMatch: false,
                config: config,
                sourceMetadataTermKeys: sourceMetadataTermKeys,
                bareEpisodeSeriesTitleKeys: looseVideoBareEpisodeSeriesTitleKeys,
                service: service
            )
            let cleanFileName = cleanedFileName(from: parsed.fileTitle, originalFileName: video.fileName, service: service)

            guard context.options.cleanup.organizeLooseBooks else { continue }
            let folderName = service.sanitizeFilename(parsed.seriesTitle)
            let existingSeriesFolder = videoFolderPathByName[service.normalizeTerm(folderName)]
            let proposedPath = existingSeriesFolder.map { service.joinedRelativePath($0, cleanFileName) }
                ?? service.joinedRelativePath("Videos", folderName, cleanFileName)
            let reason = existingSeriesFolder == nil
                ? "Moves the loose video into Videos, keeps the detected watching folder, and uses the cleaned filename."
                : "Moves the loose video into its existing watching folder first; the checked folder row can then place the whole series under Videos."
            let item = planItem(
                operation: .sortIntoFolder,
                currentPath: video.path,
                proposedPath: proposedPath,
                reason: parsed.needsManualReview ? "Review the final destination; the raw video name has unclear series or episode clues." : reason,
                requiresReview: parsed.needsManualReview,
                plannedDestinations: &plannedDestinations,
                root: context.root,
                service: service
            )
            looseItems.append(item)
            looseItems.append(contentsOf: subtitlePlanner.planItems(
                followingVideoMoveFrom: video.path,
                to: proposedPath,
                allItems: allItems,
                stage: .prepareRawFiles,
                operation: .sortIntoFolder,
                requiresReview: item.requiresReview,
                plannedDestinations: &plannedDestinations,
                root: context.root,
                service: service,
                reason: "Matching subtitle can move with the loose video and keep its Plex language, forced, SDH, or CC tags."
            ))
        }

        if context.options.cleanup.organizeLooseBooks {
            for updateFolder in rawReadingUpdateFolderMatches(
                series: inspection.series,
                existingIndex: existingReadingSeriesIndex,
                service: service
            ) {
                let sourceBooks = booksBySeriesPath[updateFolder.sourcePath] ?? []
                for book in sourceBooks {
                    let rawName = (book.fileName as NSString).deletingPathExtension
                    let parsed = service.bookNameParts(for: rawName, config: config, sourceMetadataTermKeys: sourceMetadataTermKeys)
                    let cleanFileName = cleanedFileName(from: parsed.fileTitle, originalFileName: book.fileName, service: service)
                    let proposedPath = service.joinedRelativePath(updateFolder.targetPath, cleanFileName)
                    var item = planItem(
                        operation: .sortIntoFolder,
                        currentPath: book.path,
                        proposedPath: proposedPath,
                        reason: parsed.needsManualReview
                            ? "Review the filename before moving it into the existing metadata folder."
                            : "This plain folder matches an existing series folder with ComicInfo. Move the new file there so metadata stays attached to the series.",
                        requiresReview: parsed.needsManualReview,
                        plannedDestinations: &plannedDestinations,
                        root: context.root,
                        service: service
                    )
                    item.reviewTags = Array(Set(item.reviewTags + [
                        "raw-existing-series-update",
                        "raw-reading-existing-series"
                    ])).sorted()
                    if parsed.needsManualReview {
                        item.reviewTags = Array(Set(item.reviewTags + ["raw-name-review"])).sorted()
                    }
                    looseItems.append(item)
                }
            }

            for (currentPath, folderName) in readingFolderCandidates.sorted(by: { $0.key < $1.key }) {
                let series = seriesByPath[currentPath]
                let lane = readingClassifier.classifySeriesFolder(
                    path: currentPath,
                    displayName: folderName,
                    series: series,
                    books: booksBySeriesPath[currentPath] ?? []
                )
                looseItems.append(topLevelMediaFolderItem(
                    currentPath: currentPath,
                    proposedPath: service.joinedRelativePath(lane.folderName, folderName),
                    reason: lane.requiresReview
                        ? "Review this folder's reading type before moving it into \(lane.folderName)."
                        : "Moves this existing series folder under \(lane.folderName) based on local reading-type clues.",
                    requiresReview: lane.requiresReview,
                    lane: lane,
                    plannedDestinations: &plannedDestinations,
                    root: context.root,
                    service: service
                ))
            }

            for (currentPath, folderName) in videoFolderCandidates.sorted(by: { $0.key < $1.key }) {
                looseItems.append(topLevelMediaFolderItem(
                    currentPath: currentPath,
                    proposedPath: service.joinedRelativePath("Videos", folderName),
                    reason: "Moves this existing watching folder under Videos. Later metadata cleanup can still refine it into Movies, TV, or other video folders.",
                    plannedDestinations: &plannedDestinations,
                    root: context.root,
                    service: service
                ))
            }
        }

        if context.options.cleanup.organizeLooseBooks {
            let matcher = SableLibraryFileTypeMatcher(config: config)
            let cleanupKindClassifier = SableLibraryCleanupKindClassifier(
                config: config,
                learningMemory: context.options.learning,
                useLocalLearning: context.options.intelligence.useLocalLearning
            )
            let pdfClassifier = SableLibraryPDFTriageClassifier(
                learningMemory: context.options.learning,
                useLocalLearning: context.options.intelligence.useLocalLearning
            )
            let readingItemPaths = Set(service.bookItems(
                in: allItems,
                root: context.root,
                config: config,
                cleanupOptions: context.options.cleanup
            ).map(\.relativePath))

            for (index, item) in candidateItems.enumerated() {
                reportPreparationProgress(
                    service: service,
                    title: "Preparing raw files",
                    message: "Checking root item \(index + 1) of \(candidateItems.count): \(item.name)",
                    completed: index + 1,
                    total: candidateItems.count
                )
                guard let planItem = genericTypeFolderItem(
                    for: item,
                    readingItemPaths: readingItemPaths,
                    matcher: matcher,
                    cleanupKindClassifier: cleanupKindClassifier,
                    pdfClassifier: pdfClassifier,
                    plannedDestinations: &plannedDestinations,
                    root: context.root,
                    service: service
                ) else {
                    continue
                }

                if planItem.correctionOptions.contains(.treatAsDocument) {
                    pdfTriageItems.append(planItem)
                } else {
                    typeFolderItems.append(planItem)
                }
            }

            let directChildrenByParent = Dictionary(grouping: allItems) { item in
                normalizedFolderPath(from: item.relativePath)
            }
            let videoWrapperBareEpisodeSeriesTitleKeys = videoWrapperBareEpisodeSeriesTitleKeys(
                items: allItems,
                directChildrenByParent: directChildrenByParent,
                matcher: matcher,
                config: config,
                sourceMetadataTermKeys: sourceMetadataTermKeys,
                service: service
            )
            let folderItems = candidateItems.filter(\.isDirectory)
            for (index, folder) in folderItems.enumerated() {
                reportPreparationProgress(
                    service: service,
                    title: "Preparing raw files",
                    message: "Checking wrapper folder \(index + 1) of \(folderItems.count): \(folder.name)",
                    completed: index + 1,
                    total: folderItems.count
                )
                guard !protectedRawFolderPaths.contains(folder.relativePath) else { continue }
                guard let planItem = videoWrapperFolderItem(
                    for: folder,
                    directChildrenByParent: directChildrenByParent,
                    matcher: matcher,
                    config: config,
                    sourceMetadataTermKeys: sourceMetadataTermKeys,
                    bareEpisodeSeriesTitleKeys: videoWrapperBareEpisodeSeriesTitleKeys,
                    plannedDestinations: &plannedDestinations,
                    root: context.root,
                    service: service
                ) else {
                    continue
                }
                looseItems.append(planItem)
            }

            for (index, folder) in folderItems.enumerated() {
                reportPreparationProgress(
                    service: service,
                    title: "Preparing raw files",
                    message: "Checking source-tagged folder \(index + 1) of \(folderItems.count): \(folder.name)",
                    completed: index + 1,
                    total: folderItems.count
                )
                guard !protectedRawFolderPaths.contains(folder.relativePath) else { continue }
                guard let planItem = sourceTaggedVideoSeriesFolderItem(
                    for: folder,
                    directChildrenByParent: directChildrenByParent,
                    matcher: matcher,
                    config: config,
                    sourceMetadataTermKeys: sourceMetadataTermKeys,
                    plannedDestinations: &plannedDestinations,
                    root: context.root,
                    service: service
                ) else {
                    continue
                }
                looseItems.append(planItem)
            }

            for (index, folder) in folderItems.enumerated() {
                reportPreparationProgress(
                    service: service,
                    title: "Preparing raw files",
                    message: "Checking numbered video folder \(index + 1) of \(folderItems.count): \(folder.name)",
                    completed: index + 1,
                    total: folderItems.count
                )
                guard !protectedRawFolderPaths.contains(folder.relativePath) else { continue }
                guard let planItem = numberedVideoWrapperFolderItem(
                    for: folder,
                    videoSeries: inspection.videoSeries,
                    directChildrenByParent: directChildrenByParent,
                    matcher: matcher,
                    config: config,
                    sourceMetadataTermKeys: sourceMetadataTermKeys,
                    plannedDestinations: &plannedDestinations,
                    root: context.root,
                    service: service
                ) else {
                    continue
                }
                looseItems.append(planItem)
            }

            for (index, folder) in folderItems.enumerated() {
                reportPreparationProgress(
                    service: service,
                    title: "Preparing raw files",
                    message: "Checking PDF wrapper folder \(index + 1) of \(folderItems.count): \(folder.name)",
                    completed: index + 1,
                    total: folderItems.count
                )
                guard !protectedRawFolderPaths.contains(folder.relativePath) else { continue }
                guard let planItem = pdfWrapperFolderTriageItem(
                    for: folder,
                    directChildrenByParent: directChildrenByParent,
                    readingItemPaths: readingItemPaths,
                    pdfClassifier: pdfClassifier,
                    plannedDestinations: &plannedDestinations,
                    root: context.root,
                    service: service
                ) else {
                    continue
                }
                pdfTriageItems.append(planItem)
            }

            for (index, folder) in folderItems.enumerated() {
                reportPreparationProgress(
                    service: service,
                    title: "Preparing raw files",
                    message: "Checking cleanup folder \(index + 1) of \(folderItems.count): \(folder.name)",
                    completed: index + 1,
                    total: folderItems.count
                )
                guard !protectedRawFolderPaths.contains(folder.relativePath) else { continue }
                guard let planItem = genericCleanupFolderItem(
                    for: folder,
                    directChildrenByParent: directChildrenByParent,
                    handledTopLevelMediaPaths: handledTopLevelMediaPaths,
                    readingItemPaths: readingItemPaths,
                    cleanupKindClassifier: cleanupKindClassifier,
                    plannedDestinations: &plannedDestinations,
                    root: context.root,
                    service: service
                ) else {
                    continue
                }
                typeFolderItems.append(planItem)
            }
        }

        var groups: [LibraryPlanGroup] = []
        let preparedLooseItems = trainingGatedRawItems(
            looseItems,
            threshold: 250,
            note: "Large raw placement batch: review a sample, correct anything weird, then use Check Safe when the pattern looks right."
        )
        let preparedTypeFolderItems = trainingGatedRawItems(
            typeFolderItems,
            threshold: 120,
            note: "Large type-folder batch: review a sample before checking the full group."
        )

        if !preparedLooseItems.isEmpty {
            let checkedCount = preparedLooseItems.filter { $0.decision == .checked }.count
            let gatedPrompt = checkedCount == 0
                ? "This is training material first: review a sample of the detected placements, correct anything odd, then use Check Safe when the group pattern looks right."
                : "Checked reading files are grouped by series and routed into Books, Light Novels, Manga, Manhwa, Manhua, OEL, or Other Reading when local clues are strong. Unclear rows stay unchecked."
            groups.append(LibraryPlanGroup(
                stage: .prepareRawFiles,
                title: "Place raw media",
                summary: "\(preparedLooseItems.count) loose book, video, or top-level media suggestion(s) can move into the right series home.",
                reviewPrompt: gatedPrompt,
                examples: examples(from: preparedLooseItems, title: "Final placement"),
                items: preparedLooseItems
            ))
        }
        if !pdfTriageItems.isEmpty {
            let unresolvedPDFCount = pdfTriageItems.filter(\.needsDecisionReview).count
            let checkedPDFCount = pdfTriageItems.filter { $0.decision == .checked }.count
            let leftAlonePDFCount = max(0, pdfTriageItems.count - unresolvedPDFCount - checkedPDFCount)
            groups.append(LibraryPlanGroup(
                stage: .prepareRawFiles,
                title: "PDF triage",
                summary: "\(pdfTriageItems.count) PDF file or wrapper-folder suggestion(s): \(checkedPDFCount) suggested document, \(leftAlonePDFCount) left alone, \(unresolvedPDFCount) blocked.",
                reviewPrompt: "Sable pre-fills strong document clues and leaves book-like or unsure rows alone. You can still choose Documents or keep book-like for any row.",
                examples: examples(from: pdfTriageItems, title: "PDF document choice"),
                items: pdfTriageItems
            ))
        }
        if !preparedTypeFolderItems.isEmpty {
            let checkedCount = preparedTypeFolderItems.filter { $0.decision == .checked }.count
            let gatedPrompt = checkedCount == 0
                ? "This is training material first: review a sample of the broad file-type sorting, correct anything odd, then use Check Safe when the group pattern looks right."
                : "Checked rows use local file, folder, and learned cleanup clues to move root-level items into broad folders like Documents, Images, Audio, Archives, Videos, Books, and Other."
            groups.append(LibraryPlanGroup(
                stage: .prepareRawFiles,
                title: "Sort other root files",
                summary: "\(preparedTypeFolderItems.count) loose non-sidecar file or simple top-level folder suggestion(s) can move into broad type folders.",
                reviewPrompt: gatedPrompt,
                examples: examples(from: preparedTypeFolderItems, title: "Type folder"),
                items: preparedTypeFolderItems
            ))
        }
        service.reportProgress(groups.isEmpty ? "Prepare raw files: nothing obvious to prepare" : "Prepare raw files: prepared \(groups.flatMap(\.items).count) final suggestion(s)")
        return groups
    }

    private func reportPreparationProgress(
        service: SableLibraryService,
        title: String,
        message: String,
        completed: Int,
        total: Int
    ) {
        guard total > 0 else { return }
        guard completed == 1 || completed.isMultiple(of: 50) || completed == total else { return }
        service.reportProgressSnapshot(SableLibraryProgressSnapshot(
            title: title,
            message: message,
            completedUnitCount: completed,
            totalUnitCount: total
        ))
    }

    private func trainingGatedRawItems(
        _ items: [LibraryPlanItem],
        threshold: Int,
        note: String
    ) -> [LibraryPlanItem] {
        let autoCheckedCount = items.filter { $0.decision == .checked && $0.safety == .reversible }.count
        guard autoCheckedCount > threshold else { return items }

        return items.map { item in
            guard item.decision == .checked,
                  item.safety == .reversible,
                  !item.requiresReview else {
                return item
            }

            var gatedItem = item
            gatedItem.decision = .unchecked
            gatedItem.confidence = .medium
            gatedItem.confidenceExplanation = note
            gatedItem.reviewTags = Array(Set(item.reviewTags + ["training-material", "bulk-raw-review"])).sorted()
            return gatedItem
        }
    }

    private func protectedRawFolderPaths(
        in items: [LibraryItem],
        config: SableLibraryConfig,
        fileManager: FileManager
    ) -> Set<String> {
        Set(items.compactMap { item in
            guard item.isDirectory else { return nil }
            guard Self.rawFolderCleanupProtectionReason(
                folderName: item.name,
                folderURL: item.url,
                config: config,
                fileManager: fileManager
            ) != nil else {
                return nil
            }
            return item.relativePath
        })
    }

    static func rawFolderCleanupProtectionReason(
        folderName: String,
        folderURL: URL,
        config: SableLibraryConfig,
        fileManager: FileManager
    ) -> String? {
        SableLibraryProtectedFolderPolicy.protectionReason(
            folderName: folderName,
            folderURL: folderURL,
            config: config,
            fileManager: fileManager
        )
    }

    private func cleanedFileName(from fileTitle: String, originalFileName: String, service: SableLibraryService) -> String {
        let ext = (originalFileName as NSString).pathExtension.lowercased()
        let suffix = ext.isEmpty ? "" : ".\(ext)"
        return service.sanitizeFilename(fileTitle + suffix)
    }

    private func genericTypeFolderItem(
        for item: LibraryItem,
        readingItemPaths: Set<String>,
        matcher: SableLibraryFileTypeMatcher,
        cleanupKindClassifier: SableLibraryCleanupKindClassifier,
        pdfClassifier: SableLibraryPDFTriageClassifier,
        plannedDestinations: inout Set<String>,
        root: URL,
        service: SableLibraryService
    ) -> LibraryPlanItem? {
        guard !item.isDirectory else { return nil }
        guard isLoose(item.relativePath) else { return nil }
        guard !isProtectedMetadataSidecar(item.name) else { return nil }
        guard !readingItemPaths.contains(item.relativePath),
              !matcher.isVideo(url: item.url, isDirectory: item.isDirectory),
              !isSubtitle(url: item.url) else {
            return nil
        }

        let isPDF = item.url.pathExtension.caseInsensitiveCompare("pdf") == .orderedSame
        let classification = isPDF ? nil : cleanupKindClassifier.classify(item: item)
        let folderName = genericTypeFolderName(for: item.url, cleanupKind: classification?.kind)
        let cleanFileName = service.sanitizeFilename(item.name)
        let proposedPath = service.joinedRelativePath(folderName, cleanFileName)
        let reason = isPDF
            ? "PDFs can be books or everyday documents. Treat this as a document only if it belongs in Documents; leave it unchecked if it is a book or comic PDF."
            : "Moves this loose file into the \(folderName) folder using local file-type and cleanup-kind clues. The filename is preserved except for filesystem-safe cleanup."

        var plannedItem = planItem(
            operation: .sortIntoFolder,
            currentPath: item.relativePath,
            proposedPath: proposedPath,
            reason: reason,
            requiresReview: isPDF || classification?.requiresReview == true,
            plannedDestinations: &plannedDestinations,
            root: root,
            service: service
        )

        if isPDF, plannedItem.safety == .needsChoice {
            let classification = pdfClassifier.classify(
                path: item.relativePath,
                proposedPath: proposedPath,
                isWrapperFolder: false
            )
            applyPDFTriageClassification(
                classification,
                to: &plannedItem,
                documentReceipt: "PDF document triage: \(item.relativePath) -> \(proposedPath)"
            )
        } else if let classification {
            applyCleanupKindClassification(classification, to: &plannedItem)
        }

        return plannedItem
    }

    private func genericCleanupFolderItem(
        for folder: LibraryItem,
        directChildrenByParent: [String: [LibraryItem]],
        handledTopLevelMediaPaths: Set<String>,
        readingItemPaths: Set<String>,
        cleanupKindClassifier: SableLibraryCleanupKindClassifier,
        plannedDestinations: inout Set<String>,
        root: URL,
        service: SableLibraryService
    ) -> LibraryPlanItem? {
        guard folder.isDirectory else { return nil }
        guard isTopLevelMediaFolderCandidate(folder.relativePath) else { return nil }
        guard !handledTopLevelMediaPaths.contains(folder.relativePath) else { return nil }
        guard !readingItemPaths.contains(folder.relativePath) else { return nil }

        let children = directChildrenByParent[folder.relativePath] ?? []
        let protectedChildren = children.filter { isProtectedMetadataSidecar($0.name) }
        guard !children.isEmpty, protectedChildren.isEmpty else { return nil }

        let pdfChildren = children.filter { child in
            !child.isDirectory && child.url.pathExtension.caseInsensitiveCompare("pdf") == .orderedSame
        }
        guard !(pdfChildren.count == 1 && children.count == pdfChildren.count) else {
            return nil
        }

        let classification = cleanupKindClassifier.classify(
            item: folder,
            directChildren: children
        )
        guard classification.kind != .other else { return nil }

        let folderName = service.sanitizeFilename(folder.name)
        guard !folderName.isEmpty else { return nil }
        let destinationFolder = genericTypeFolderName(for: children, cleanupKind: classification.kind)

        var plannedItem = planItem(
            operation: .renameFolder,
            currentPath: folder.relativePath,
            proposedPath: service.joinedRelativePath(destinationFolder, folderName),
            reason: classification.requiresReview
                ? "Review this folder's broad cleanup type before moving it into \(destinationFolder)."
                : "Moves this top-level folder into \(destinationFolder) using local child-file and cleanup-kind clues.",
            requiresReview: classification.requiresReview,
            plannedDestinations: &plannedDestinations,
            root: root,
            service: service
        )
        applyCleanupKindClassification(classification, to: &plannedItem)
        return plannedItem
    }

    private func pdfWrapperFolderTriageItem(
        for folder: LibraryItem,
        directChildrenByParent: [String: [LibraryItem]],
        readingItemPaths: Set<String>,
        pdfClassifier: SableLibraryPDFTriageClassifier,
        plannedDestinations: inout Set<String>,
        root: URL,
        service: SableLibraryService
    ) -> LibraryPlanItem? {
        guard folder.isDirectory else { return nil }
        guard folder.name.caseInsensitiveCompare("Documents") != .orderedSame else { return nil }
        guard !folder.relativePath.hasPrefix("Documents/") else { return nil }
        guard !readingItemPaths.contains(folder.relativePath) else { return nil }

        let children = directChildrenByParent[folder.relativePath] ?? []
        let pdfChildren = children.filter { child in
            !child.isDirectory && child.url.pathExtension.caseInsensitiveCompare("pdf") == .orderedSame
        }
        let protectedChildren = children.filter { isProtectedMetadataSidecar($0.name) }
        guard protectedChildren.isEmpty else { return nil }
        guard pdfChildren.count == 1, children.count == pdfChildren.count else {
            return nil
        }
        guard !readingItemPaths.contains(pdfChildren[0].relativePath) else { return nil }

        let folderName = service.sanitizeFilename(folder.name)
        let proposedPath = service.joinedRelativePath(documentTypeFolderName(for: pdfChildren[0].url), folderName)
        var plannedItem = planItem(
            operation: .renameFolder,
            currentPath: folder.relativePath,
            proposedPath: proposedPath,
            reason: "This folder looks like a single-PDF wrapper. Treat it as a document folder only if the PDF inside is paperwork, a form, a receipt, a manual, or another non-book file.",
            requiresReview: true,
            plannedDestinations: &plannedDestinations,
            root: root,
            service: service
        )

        if plannedItem.safety == .needsChoice {
            let classification = pdfClassifier.classify(
                path: pdfChildren[0].relativePath,
                proposedPath: proposedPath,
                isWrapperFolder: true
            )
            applyPDFTriageClassification(
                classification,
                to: &plannedItem,
                documentReceipt: "PDF folder triage: \(folder.relativePath) -> \(proposedPath)"
            )
        }

        return plannedItem
    }

    private func sourceTaggedVideoSeriesFolderItem(
        for folder: LibraryItem,
        directChildrenByParent: [String: [LibraryItem]],
        matcher: SableLibraryFileTypeMatcher,
        config: SableLibraryConfig,
        sourceMetadataTermKeys: Set<String>,
        plannedDestinations: inout Set<String>,
        root: URL,
        service: SableLibraryService
    ) -> LibraryPlanItem? {
        guard folder.isDirectory,
              let videoRoot = canonicalVideoRoot(in: folder.relativePath, service: service),
              folder.relativePath != videoRoot,
              isDirectChildPath(folder.relativePath, of: videoRoot) else {
            return nil
        }

        let children = directChildrenByParent[folder.relativePath] ?? []
        let hasSidecar = children.contains { isProtectedMetadataSidecar($0.name) }
        let hasNestedFolder = children.contains { $0.isDirectory }
        guard hasSidecar || hasNestedFolder else { return nil }

        let sourceCleaned = service.cleanedTitle(
            folder.name,
            config: config,
            sourceMetadataTermKeys: sourceMetadataTermKeys
        )
        let cleanFolderName = service.sanitizeFilename(
            cleanedVideoTitle(
                sourceCleaned,
                sourceMetadataTermKeys: sourceMetadataTermKeys,
                service: service
            )
        )
        guard !cleanFolderName.isEmpty,
              service.normalizeTerm(cleanFolderName) != service.normalizeTerm(folder.name),
              videoFolderContainsVideo(folder.url, matcher: matcher, service: service) else {
            return nil
        }

        var plannedItem = planItem(
            operation: .renameFolder,
            currentPath: folder.relativePath,
            proposedPath: service.joinedRelativePath(videoRoot, cleanFolderName),
            reason: "Removes a configured source tag from this watching folder while keeping its videos, AnimeInfo, Plex match file, and season folders together.",
            requiresReview: false,
            plannedDestinations: &plannedDestinations,
            root: root,
            service: service
        )
        plannedItem.reviewTags = Array(Set(plannedItem.reviewTags + [
            "cleanup-kind",
            "cleanup-kind-watching",
            "raw-video-source-folder",
            "metadata-source-term-cleanup"
        ])).sorted()
        return plannedItem
    }

    private func isDirectChildPath(_ path: String, of parent: String) -> Bool {
        let childComponents = path.split(separator: "/")
        let parentComponents = parent.split(separator: "/")
        return childComponents.count == parentComponents.count + 1
            && childComponents.prefix(parentComponents.count).elementsEqual(parentComponents)
    }

    private func videoFolderContainsVideo(
        _ folderURL: URL,
        matcher: SableLibraryFileTypeMatcher,
        service: SableLibraryService
    ) -> Bool {
        guard let enumerator = service.fileManager.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }

        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey]),
                  values.isDirectory != true,
                  matcher.isVideo(url: url, isDirectory: false) else {
                continue
            }
            return true
        }
        return false
    }

    private func numberedVideoWrapperFolderItem(
        for folder: LibraryItem,
        videoSeries: [LibraryVideoSeriesSnapshot],
        directChildrenByParent: [String: [LibraryItem]],
        matcher: SableLibraryFileTypeMatcher,
        config: SableLibraryConfig,
        sourceMetadataTermKeys: Set<String>,
        plannedDestinations: inout Set<String>,
        root: URL,
        service: SableLibraryService
    ) -> LibraryPlanItem? {
        guard folder.isDirectory,
              let videoRoot = canonicalVideoRoot(in: folder.relativePath, service: service),
              folder.relativePath != videoRoot,
              isDirectChildPath(folder.relativePath, of: videoRoot) else {
            return nil
        }

        let children = directChildrenByParent[folder.relativePath] ?? []
        let videoChildren = children.filter { child in
            !child.isDirectory && matcher.isVideo(url: child.url, isDirectory: child.isDirectory)
        }
        guard videoChildren.count == 1,
              let video = videoChildren.first else {
            return nil
        }

        let animeInfoChild = children.first {
            $0.name.caseInsensitiveCompare(config.animeInfoFileName) == .orderedSame
        }
        guard let animeInfoChild,
              generatedLocalWrapperAnimeInfoCanBeRetired(animeInfoChild.url) else {
            return nil
        }
        guard children.allSatisfy({ child in
            child.relativePath == video.relativePath
                || child.relativePath == animeInfoChild.relativePath
        }) else {
            return nil
        }

        guard let parts = numberedWrapperEpisodeParts(
            folder: folder,
            video: video,
            config: config,
            sourceMetadataTermKeys: sourceMetadataTermKeys,
            service: service
        ),
              let episode = Int(parts.episodeText),
              let targetSeries = numberedVideoWrapperTarget(
                for: parts,
                sourceFolderPath: folder.relativePath,
                videoSeries: videoSeries,
                config: config,
                sourceMetadataTermKeys: sourceMetadataTermKeys,
                service: service
              ),
              let season = numberedVideoWrapperSeason(for: targetSeries.mediaType) else {
            return nil
        }

        let title = numberedVideoWrapperTargetTitle(
            for: targetSeries,
            config: config,
            sourceMetadataTermKeys: sourceMetadataTermKeys,
            service: service
        )
        let episodeFileName = SableLibraryNamingPolicy().canonicalWatchingEpisodeFileName(
            preferredTitle: title,
            year: targetSeries.year,
            season: season,
            episode: episode,
            episodeTitle: nil,
            fileExtension: video.url.pathExtension
        )
        let proposedPath = service.joinedRelativePath(
            targetSeries.path,
            SableLibraryNamingPolicy().plexSeasonFolderName(season: season),
            episodeFileName
        )
        guard proposedPath != video.relativePath,
              !proposedPath.hasPrefix(folder.relativePath + "/") else {
            return nil
        }

        var plannedItem = planItem(
            operation: .sortIntoFolder,
            currentPath: video.relativePath,
            proposedPath: proposedPath,
            reason: "Moves this numbered raw episode into the matching watching series and retires its generated placeholder AnimeInfo after review.",
            requiresReview: true,
            plannedDestinations: &plannedDestinations,
            root: root,
            service: service
        )
        plannedItem.reviewTags = Array(Set(plannedItem.reviewTags + [
            "cleanup-kind",
            "cleanup-kind-watching",
            "metadata-local-sidecar-retire",
            "raw-video-numbered-wrapper",
            "raw-video-wrapper-folder"
        ])).sorted()
        return plannedItem
    }

    private func numberedWrapperEpisodeParts(
        folder: LibraryItem,
        video: LibraryItem,
        config: SableLibraryConfig,
        sourceMetadataTermKeys: Set<String>,
        service: SableLibraryService
    ) -> BareVideoEpisodeParts? {
        [
            (video.name as NSString).deletingPathExtension,
            folder.name
        ].compactMap { rawName -> BareVideoEpisodeParts? in
            let cleaned = cleanedVideoTitle(
                service.cleanedTitle(rawName, config: config, sourceMetadataTermKeys: sourceMetadataTermKeys),
                sourceMetadataTermKeys: sourceMetadataTermKeys,
                service: service
            )
            return bareVideoEpisodeParts(from: cleaned, service: service)
        }.first
    }

    private func numberedVideoWrapperTarget(
        for parts: BareVideoEpisodeParts,
        sourceFolderPath: String,
        videoSeries: [LibraryVideoSeriesSnapshot],
        config: SableLibraryConfig,
        sourceMetadataTermKeys: Set<String>,
        service: SableLibraryService
    ) -> LibraryVideoSeriesSnapshot? {
        let sourceKeys = watchingTitleMatchKeys(
            for: [parts.seriesTitle],
            config: config,
            sourceMetadataTermKeys: sourceMetadataTermKeys,
            service: service
        )
        let matches = videoSeries.compactMap { series -> (series: LibraryVideoSeriesSnapshot, score: Int)? in
            guard series.path != sourceFolderPath,
                  !series.path.hasPrefix(sourceFolderPath + "/"),
                  (series.hasAnimeInfo || series.localVideoCount > 0),
                  numberedVideoWrapperSeason(for: series.mediaType) != nil,
                  !videoSeriesFolderNeedsSourceCleanup(
                    series,
                    config: config,
                    sourceMetadataTermKeys: sourceMetadataTermKeys,
                    service: service
                  ) else {
                return nil
            }

            let targetKeys = watchingTitleMatchKeys(
                for: watchingTitleCandidates(for: series),
                config: config,
                sourceMetadataTermKeys: sourceMetadataTermKeys,
                service: service
            )
            if !sourceKeys.normalized.isDisjoint(with: targetKeys.normalized) {
                return (series, 0)
            }
            if !sourceKeys.compact.isDisjoint(with: targetKeys.compact) {
                return (series, 1)
            }
            return nil
        }.sorted {
            if $0.score != $1.score {
                return $0.score < $1.score
            }
            return $0.series.path.localizedStandardCompare($1.series.path) == .orderedAscending
        }

        guard let best = matches.first else { return nil }
        if matches.dropFirst().contains(where: { $0.score == best.score }) {
            return nil
        }
        return best.series
    }

    private func videoSeriesFolderNeedsSourceCleanup(
        _ series: LibraryVideoSeriesSnapshot,
        config: SableLibraryConfig,
        sourceMetadataTermKeys: Set<String>,
        service: SableLibraryService
    ) -> Bool {
        guard let videoRoot = canonicalVideoRoot(in: series.path, service: service),
              isDirectChildPath(series.path, of: videoRoot) else {
            return false
        }

        let folderName = (series.path as NSString).lastPathComponent
        let cleanFolderName = service.sanitizeFilename(
            cleanedVideoTitle(
                service.cleanedTitle(folderName, config: config, sourceMetadataTermKeys: sourceMetadataTermKeys),
                sourceMetadataTermKeys: sourceMetadataTermKeys,
                service: service
            )
        )
        return !cleanFolderName.isEmpty
            && service.normalizeTerm(cleanFolderName) != service.normalizeTerm(folderName)
    }

    private func watchingTitleCandidates(for series: LibraryVideoSeriesSnapshot) -> [String] {
        [
            series.preferredTitle,
            series.localTitle,
            series.displayName,
            (series.path as NSString).lastPathComponent
        ].compactMap { $0 }
    }

    private func watchingTitleMatchKeys(
        for titles: [String],
        config: SableLibraryConfig,
        sourceMetadataTermKeys: Set<String>,
        service: SableLibraryService
    ) -> WatchingTitleMatchKeys {
        titles.reduce(into: WatchingTitleMatchKeys()) { keys, title in
            let sourceCleaned = service.cleanedTitle(
                title,
                config: config,
                sourceMetadataTermKeys: sourceMetadataTermKeys
            )
            let cleaned = cleanedVideoTitle(
                sourceCleaned,
                sourceMetadataTermKeys: sourceMetadataTermKeys,
                service: service
            )
            let titleValues = [
                title,
                sourceCleaned,
                cleaned,
                service.cleanSeriesTitle(cleaned),
                SableLibraryProviderQueryCleaner.searchTitle(from: cleaned)
            ].compactMap { $0 }

            for value in titleValues {
                let normalized = service.normalizeTerm(value)
                guard !normalized.isEmpty else { continue }
                keys.normalized.insert(normalized)
                keys.compact.insert(compactWatchingTitleKey(normalized))
            }
        }
    }

    private func numberedVideoWrapperTargetTitle(
        for series: LibraryVideoSeriesSnapshot,
        config: SableLibraryConfig,
        sourceMetadataTermKeys: Set<String>,
        service: SableLibraryService
    ) -> String {
        for candidate in watchingTitleCandidates(for: series) {
            let sourceCleaned = service.cleanedTitle(
                candidate,
                config: config,
                sourceMetadataTermKeys: sourceMetadataTermKeys
            )
            let cleaned = cleanedVideoTitle(
                sourceCleaned,
                sourceMetadataTermKeys: sourceMetadataTermKeys,
                service: service
            )
            let title = service.cleanSeriesTitle(
                SableLibraryProviderQueryCleaner.searchTitle(from: cleaned) ?? cleaned
            )
            if !title.isEmpty {
                return title
            }
        }
        return series.displayName
    }

    private func compactWatchingTitleKey(_ normalized: String) -> String {
        normalized.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
    }

    private func numberedVideoWrapperSeason(for mediaType: String?) -> Int? {
        switch mediaType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "movie", "animemovie", "anime movie", "unknownvideo", "unknown video":
            return nil
        case "ova", "ona", "special", "specials":
            return 0
        default:
            return 1
        }
    }

    private func generatedLocalWrapperAnimeInfoCanBeRetired(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data),
              let sidecar = object as? [String: Any] else {
            return false
        }

        let source = (sidecar["source"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let mediaType = (sidecar["type"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let ids = sidecar["ids"] as? [String: Any] ?? [:]
        let sable = sidecar["_sable"] as? [String: Any] ?? [:]
        let sidecarName = (sable["sidecar"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return source == "local"
            && (mediaType == nil || mediaType == "unknownvideo" || mediaType == "unknown video")
            && ids.isEmpty
            && (sidecarName == nil || sidecarName == url.lastPathComponent)
    }

    private func videoWrapperFolderItem(
        for folder: LibraryItem,
        directChildrenByParent: [String: [LibraryItem]],
        matcher: SableLibraryFileTypeMatcher,
        config: SableLibraryConfig,
        sourceMetadataTermKeys: Set<String>,
        bareEpisodeSeriesTitleKeys: Set<String>,
        plannedDestinations: inout Set<String>,
        root: URL,
        service: SableLibraryService
    ) -> LibraryPlanItem? {
        guard folder.isDirectory,
              let videoRoot = canonicalVideoRoot(in: folder.relativePath, service: service),
              folder.relativePath != videoRoot else {
            return nil
        }

        let children = directChildrenByParent[folder.relativePath] ?? []
        let videoChildren = children.filter { child in
            !child.isDirectory && matcher.isVideo(url: child.url, isDirectory: child.isDirectory)
        }
        let protectedChildren = children.filter { isProtectedMetadataSidecar($0.name) }
        guard protectedChildren.isEmpty,
              videoChildren.count == 1,
              children.count == videoChildren.count,
              let video = videoChildren.first else {
            return nil
        }

        let rawName = (video.name as NSString).deletingPathExtension
        let sourceCleanedRawTitle = service.cleanedTitle(rawName, config: config, sourceMetadataTermKeys: sourceMetadataTermKeys)
        let cleanedWithoutSourceRemoval = cleanedVideoTitleWithoutSourceRemoval(sourceCleanedRawTitle, service: service)
        let cleanedWithSourceRemoval = cleanedVideoTitle(
            sourceCleanedRawTitle,
            sourceMetadataTermKeys: sourceMetadataTermKeys,
            service: service
        )
        let removedSourceNote = service.normalizeTerm(cleanedWithoutSourceRemoval) != service.normalizeTerm(cleanedWithSourceRemoval)
        let usesBareEpisodeNumber = bareVideoEpisodeParts(from: cleanedWithSourceRemoval, service: service).map {
            shouldUseBareVideoEpisodeParts($0, bareEpisodeSeriesTitleKeys: bareEpisodeSeriesTitleKeys, service: service)
        } ?? false
        guard removedSourceNote || usesBareEpisodeNumber else { return nil }

        let parsed = videoNameParts(
            for: rawName,
            parentFolderName: nil,
            requiresTitleMatch: false,
            config: config,
            sourceMetadataTermKeys: sourceMetadataTermKeys,
            bareEpisodeSeriesTitleKeys: bareEpisodeSeriesTitleKeys,
            service: service
        )
        let folderName = service.sanitizeFilename(parsed.seriesTitle)
        let cleanFileName = cleanedFileName(from: parsed.fileTitle, originalFileName: video.name, service: service)
        let proposedPath = service.joinedRelativePath(videoRoot, folderName, cleanFileName)
        guard proposedPath != video.relativePath else { return nil }

        var plannedItem = planItem(
            operation: .sortIntoFolder,
            currentPath: video.relativePath,
            proposedPath: proposedPath,
            reason: parsed.needsManualReview
                ? "Review this one-video wrapper before merging it into a shared video series folder."
                : "This looks like a one-video wrapper. Move the video into the shared series folder and remove the empty wrapper after apply.",
            requiresReview: parsed.needsManualReview,
            plannedDestinations: &plannedDestinations,
            root: root,
            service: service
        )
        plannedItem.reviewTags = Array(Set(plannedItem.reviewTags + [
            "cleanup-kind",
            "cleanup-kind-watching",
            "video-wrapper-folder",
            "raw-video-wrapper-folder"
        ])).sorted()
        return plannedItem
    }

    private func broadMediaFolderCandidates(
        paths: [String],
        destinationRoot: String,
        root: URL,
        service: SableLibraryService
    ) -> [String: String] {
        paths.reduce(into: [String: String]()) { partialResult, path in
            guard isTopLevelMediaFolderCandidate(path) else { return }
            let folderURL = root.appendingPathComponent(path, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard service.fileManager.fileExists(atPath: folderURL.path(percentEncoded: false), isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                return
            }

            let folderName = service.sanitizeFilename((path as NSString).lastPathComponent)
            guard !folderName.isEmpty,
                  service.normalizeTerm(folderName) != service.normalizeTerm(destinationRoot) else {
                return
            }
            partialResult[path] = folderName
        }
    }

    private func folderPathByNormalizedName(
        _ candidates: [String: String],
        service: SableLibraryService
    ) -> [String: String] {
        candidates.reduce(into: [String: String]()) { partialResult, row in
            let key = service.normalizeTerm(row.value)
            if partialResult[key] == nil {
                partialResult[key] = row.key
            }
        }
    }

    private func looseVideoBareEpisodeSeriesTitleKeys(
        videos: [LibraryVideoSnapshot],
        config: SableLibraryConfig,
        sourceMetadataTermKeys: Set<String>,
        service: SableLibraryService
    ) -> Set<String> {
        let parts = videos.compactMap { video -> BareVideoEpisodeParts? in
            guard (video.seriesID ?? "").isEmpty else { return nil }
            let rawName = (video.fileName as NSString).deletingPathExtension
            let cleaned = cleanedVideoTitle(
                service.cleanedTitle(rawName, config: config, sourceMetadataTermKeys: sourceMetadataTermKeys),
                sourceMetadataTermKeys: sourceMetadataTermKeys,
                service: service
            )
            return bareVideoEpisodeParts(from: cleaned, service: service)
        }
        return repeatedBareEpisodeSeriesTitleKeys(from: parts, service: service)
    }

    private func videoWrapperBareEpisodeSeriesTitleKeys(
        items: [LibraryItem],
        directChildrenByParent: [String: [LibraryItem]],
        matcher: SableLibraryFileTypeMatcher,
        config: SableLibraryConfig,
        sourceMetadataTermKeys: Set<String>,
        service: SableLibraryService
    ) -> Set<String> {
        let parts = items.compactMap { folder -> BareVideoEpisodeParts? in
            guard folder.isDirectory,
                  canonicalVideoRoot(in: folder.relativePath, service: service) != nil else {
                return nil
            }

            let children = directChildrenByParent[folder.relativePath] ?? []
            let videoChildren = children.filter { child in
                !child.isDirectory && matcher.isVideo(url: child.url, isDirectory: child.isDirectory)
            }
            guard videoChildren.count == 1,
                  children.count == videoChildren.count,
                  let video = videoChildren.first else {
                return nil
            }

            let rawName = (video.name as NSString).deletingPathExtension
            let cleaned = cleanedVideoTitle(
                service.cleanedTitle(rawName, config: config, sourceMetadataTermKeys: sourceMetadataTermKeys),
                sourceMetadataTermKeys: sourceMetadataTermKeys,
                service: service
            )
            return bareVideoEpisodeParts(from: cleaned, service: service)
        }
        return repeatedBareEpisodeSeriesTitleKeys(from: parts, service: service)
    }

    private func repeatedBareEpisodeSeriesTitleKeys(
        from parts: [BareVideoEpisodeParts],
        service: SableLibraryService
    ) -> Set<String> {
        let counts = parts.reduce(into: [String: Int]()) { partialResult, part in
            guard !part.hasLeadingZero else { return }
            let key = service.normalizeTerm(part.seriesTitle)
            guard !key.isEmpty else { return }
            partialResult[key, default: 0] += 1
        }
        return Set(counts.compactMap { key, count in count > 1 ? key : nil })
    }

    private func isTopLevelMediaFolderCandidate(_ path: String) -> Bool {
        let normalized = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !normalized.isEmpty, !normalized.contains("/") else { return false }
        return !broadOrCanonicalRootFolderNames.contains(normalized.lowercased())
    }

    private var broadOrCanonicalRootFolderNames: Set<String> {
        [
            "books",
            "videos",
            "documents",
            "pdfs",
            "text",
            "word",
            "spreadsheets",
            "presentations",
            "json",
            "xml",
            "web",
            "mixed documents",
            "other documents",
            "images",
            "audio",
            "archives",
            "other",
            "epubs",
            "comic archives",
            "pdf books",
            "djvu",
            "mkv",
            "mp4",
            "mov",
            "avi",
            "wmv",
            "webm",
            "transport streams",
            "jpeg",
            "png",
            "webp",
            "gif",
            "heic",
            "svg",
            "tiff",
            "bmp",
            "mp3",
            "aac",
            "flac",
            "wav",
            "ogg opus",
            "zip",
            "rar",
            "7z",
            "tar gz",
            "manga",
            "manhwa",
            "manhua",
            "light novels",
            "oel",
            "anime movies",
            "anime tv",
            "movies",
            "tv",
            "tv shows",
            "other videos",
            "_possible duplicates",
            "_sable's library reports",
            "_do not touch"
        ]
    }

    private func canonicalVideoRoot(in path: String, service: SableLibraryService) -> String? {
        guard let rootName = pathComponents(in: path).first else { return nil }
        return canonicalVideoRootNames.contains(service.normalizeTerm(rootName)) ? rootName : nil
    }

    private var canonicalVideoRootNames: Set<String> {
        [
            "videos",
            "tv",
            "anime tv",
            "anime movies",
            "movies",
            "tv shows",
            "other videos"
        ]
    }

    private func topLevelMediaFolderItem(
        currentPath: String,
        proposedPath: String,
        reason: String,
        requiresReview: Bool = false,
        lane: RawReadingLaneClassification? = nil,
        plannedDestinations: inout Set<String>,
        root: URL,
        service: SableLibraryService
    ) -> LibraryPlanItem {
        var item = planItem(
            operation: .renameFolder,
            currentPath: currentPath,
            proposedPath: proposedPath,
            reason: reason,
            requiresReview: requiresReview,
            plannedDestinations: &plannedDestinations,
            root: root,
            service: service
        )
        if let lane {
            applyRawReadingLane(lane, to: &item)
        }
        return item
    }

    private func legacyWatchingRootItems(
        root: URL,
        plannedDestinations: inout Set<String>,
        service: SableLibraryService
    ) -> [LibraryPlanItem] {
        [
            ("Anime TV", "TV"),
            ("TV Shows", "TV"),
            ("Anime Movies", "Movies")
        ].compactMap { legacyRoot, modernRoot in
            let source = root.appendingPathComponent(legacyRoot, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard service.fileManager.fileExists(atPath: source.path(percentEncoded: false), isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                return nil
            }

            let target = root.appendingPathComponent(modernRoot, isDirectory: true)
            let targetExists = service.fileManager.fileExists(atPath: target.path(percentEncoded: false))
                || plannedDestinations.contains(modernRoot)
            plannedDestinations.insert(modernRoot)

            if targetExists {
                return LibraryPlanItem(
                    stage: .prepareRawFiles,
                    operation: .renameFolder,
                    currentPath: legacyRoot,
                    proposedPath: modernRoot,
                    reason: PlannedMove.manualFolderMergeReason,
                    confidence: .medium,
                    safety: .collision,
                    decision: .unchecked,
                    requiresReview: false,
                    confidenceExplanation: "The modern \(modernRoot) folder already exists. Check this only when you want Sable to merge the legacy \(legacyRoot) contents into it.",
                    correctionOptions: [.mergeIntoExisting, .keepTitle],
                    reviewTags: ["legacy-watching-root"],
                    receipt: "\(legacyRoot) -> \(modernRoot)"
                )
            }

            return LibraryPlanItem(
                stage: .prepareRawFiles,
                operation: .renameFolder,
                currentPath: legacyRoot,
                proposedPath: modernRoot,
                reason: "Renames the legacy \(legacyRoot) watching home to \(modernRoot) so video libraries use neutral Plex-style folders.",
                confidence: .high,
                safety: .reversible,
                decision: .checked,
                requiresReview: false,
                confidenceExplanation: "The old root can be renamed directly because the modern \(modernRoot) folder does not exist yet.",
                correctionOptions: [.keepTitle],
                reviewTags: ["legacy-watching-root"],
                receipt: "\(legacyRoot) -> \(modernRoot)"
            )
        }
    }

    private func applyRawReadingLane(_ lane: RawReadingLaneClassification, to item: inout LibraryPlanItem) {
        item.confidenceExplanation = lane.explanation
        item.reviewTags = Array(Set(item.reviewTags + lane.reviewTags)).sorted()
        item.correctionOptions = Array(Set(
            item.correctionOptions + [
                .treatAsManga,
                .treatAsManhwa,
                .treatAsManhua,
                .treatAsLightNovel,
                .treatAsProseBook,
                .treatAsOEL,
                .wrongType
            ]
        )).sorted { $0.title < $1.title }

        guard item.safety != .collision else { return }

        item.confidence = lane.confidence
        if lane.requiresReview {
            item.safety = .needsChoice
            item.decision = .unchecked
            item.requiresReview = true
        }
    }

    private func applyCleanupKindClassification(
        _ classification: SableLibraryCleanupKindClassification,
        to item: inout LibraryPlanItem
    ) {
        item.confidenceExplanation = classification.explanation
        item.reviewTags = Array(Set(item.reviewTags + classification.reviewTags)).sorted()
        item.correctionOptions = Array(Set(
            item.correctionOptions + [
                .treatAsReading,
                .treatAsWatching,
                .treatAsDocuments,
                .treatAsImages,
                .treatAsAudio,
                .treatAsArchives,
                .treatAsOtherFiles,
                .wrongType
            ]
        )).sorted { $0.title < $1.title }

        guard item.safety != .collision else { return }

        item.confidence = classification.confidence
        if classification.requiresReview {
            item.safety = .needsChoice
            item.decision = .unchecked
            item.requiresReview = true
        }
    }

    private func applyPDFTriageClassification(
        _ classification: SableLibraryPDFTriageClassification,
        to item: inout LibraryPlanItem,
        documentReceipt: String
    ) {
        item.confidence = classification.confidence
        item.confidenceExplanation = classification.explanation
        item.correctionOptions = [.treatAsDocument, .treatAsBook, .keepTitle, .custom]
        item.reviewTags = classification.reviewTags
        item.receipt = documentReceipt

        switch classification.choice {
        case .document:
            item.decision = .checked
            item.safety = .reversible
            item.requiresReview = false
            item.reason = "Sable thinks this PDF is a document. It is checked for Documents, but you can still keep it as book-like before applying."
        case .book:
            item.decision = .unchecked
            item.safety = .needsChoice
            item.requiresReview = false
            item.reason = "Sable thinks this PDF is book-like. It is left out of document cleanup unless you choose Treat as Document."
        case nil:
            item.decision = .unchecked
            item.safety = .needsChoice
            item.requiresReview = false
            item.reason = "Sable is unsure whether this PDF is a document or book. It is left alone unless you choose Treat as Document."
        }
    }

    private func isLoose(_ relativePath: String) -> Bool {
        let parent = (relativePath as NSString).deletingLastPathComponent
        return parent.isEmpty || parent == "."
    }

    private func isProtectedMetadataSidecar(_ fileName: String) -> Bool {
        let baseName = (fileName as NSString).deletingPathExtension
        return baseName.caseInsensitiveCompare("ComicInfo") == .orderedSame
            || baseName.caseInsensitiveCompare("AnimeInfo") == .orderedSame
    }

    private func isSubtitle(url: URL) -> Bool {
        ["srt", "ass", "ssa", "vtt"].contains(url.pathExtension.lowercased())
    }

    private func genericTypeFolderName(for url: URL, cleanupKind: SableLibraryCleanupKind? = nil) -> String {
        if let cleanupKind, cleanupKind != .other {
            switch cleanupKind {
            case .document:
                return documentTypeFolderName(for: url)
            case .image:
                return imageTypeFolderName(for: url)
            case .audio:
                return audioTypeFolderName(for: url)
            case .archive:
                return archiveTypeFolderName(for: url)
            case .reading:
                return readingTypeFolderName(for: url)
            case .watching:
                return videoTypeFolderName(for: url)
            case .other:
                break
            }
        }

        let ext = url.pathExtension.lowercased()
        if readingExtensions.contains(ext), ext != "pdf" { return readingTypeFolderName(for: url) }
        if videoExtensions.contains(ext) { return videoTypeFolderName(for: url) }
        if documentExtensions.contains(ext) { return documentTypeFolderName(for: url) }
        if imageExtensions.contains(ext) { return imageTypeFolderName(for: url) }
        if audioExtensions.contains(ext) { return audioTypeFolderName(for: url) }
        if archiveExtensions.contains(ext) { return archiveTypeFolderName(for: url) }

        if let type = UTType(filenameExtension: ext) {
            if type.conforms(to: .movie) || type.conforms(to: .video) { return videoTypeFolderName(for: url) }
            if type.conforms(to: .image) { return imageTypeFolderName(for: url) }
            if type.conforms(to: .audio) { return audioTypeFolderName(for: url) }
            if type.conforms(to: .archive) { return archiveTypeFolderName(for: url) }
            if type.conforms(to: .text) || type.conforms(to: .content) { return documentTypeFolderName(for: url) }
        }
        return "Other"
    }

    private func genericTypeFolderName(for children: [LibraryItem], cleanupKind: SableLibraryCleanupKind) -> String {
        let fileChildren = children.filter { !$0.isDirectory }
        guard !fileChildren.isEmpty else { return cleanupKind.folderName }

        let counts = fileChildren.reduce(into: [String: Int]()) { partialResult, child in
            let folderName = genericTypeFolderName(for: child.url, cleanupKind: cleanupKind)
            guard folderName.hasPrefix(cleanupKind.folderName + "/") else { return }
            partialResult[folderName, default: 0] += 1
        }
        guard let best = counts.max(by: { $0.value < $1.value }) else {
            return cleanupKind.folderName
        }
        guard best.value == fileChildren.count else {
            return mixedTypeFolderName(for: cleanupKind)
        }
        return best.key
    }

    private func mixedTypeFolderName(for cleanupKind: SableLibraryCleanupKind) -> String {
        switch cleanupKind {
        case .reading:
            return "Books/Mixed Reading"
        case .watching:
            return "Videos/Mixed Videos"
        case .document:
            return "Documents/Mixed Documents"
        case .image:
            return "Images/Mixed Images"
        case .audio:
            return "Audio/Mixed Audio"
        case .archive:
            return "Archives/Mixed Archives"
        case .other:
            return "Other"
        }
    }

    private func readingTypeFolderName(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "epub", "kepub", "mobi", "azw", "azw3", "ibooks", "iba":
            return "Books/EPUBs"
        case "cbz", "cbr", "cb7", "cbt":
            return "Books/Comic Archives"
        case "pdf":
            return "Books/PDFs"
        case "djvu":
            return "Books/DJVU"
        default:
            return "Books/Other Reading Files"
        }
    }

    private func videoTypeFolderName(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "mkv":
            return "Videos/MKV"
        case "mp4", "m4v":
            return "Videos/MP4"
        case "mov":
            return "Videos/MOV"
        case "avi":
            return "Videos/AVI"
        case "wmv":
            return "Videos/WMV"
        case "webm":
            return "Videos/WebM"
        case "ts", "m2ts":
            return "Videos/Transport Streams"
        default:
            return "Videos/Other Video Files"
        }
    }

    private func documentTypeFolderName(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "pdf":
            return "Documents/PDFs"
        case "txt", "md", "markdown":
            return "Documents/Text"
        case "rtf", "doc", "docx", "pages":
            return "Documents/Word"
        case "numbers", "csv", "tsv", "xls", "xlsx":
            return "Documents/Spreadsheets"
        case "key", "ppt", "pptx":
            return "Documents/Presentations"
        case "json":
            return "Documents/JSON"
        case "xml":
            return "Documents/XML"
        case "html", "htm", "css":
            return "Documents/Web"
        default:
            return "Documents/Other Documents"
        }
    }

    private func imageTypeFolderName(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg":
            return "Images/JPEG"
        case "png":
            return "Images/PNG"
        case "webp":
            return "Images/WebP"
        case "gif":
            return "Images/GIF"
        case "heic", "heif":
            return "Images/HEIC"
        case "svg":
            return "Images/SVG"
        case "tiff", "tif":
            return "Images/TIFF"
        case "bmp":
            return "Images/BMP"
        default:
            return "Images/Other Images"
        }
    }

    private func audioTypeFolderName(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "mp3":
            return "Audio/MP3"
        case "m4a", "aac":
            return "Audio/AAC"
        case "flac":
            return "Audio/FLAC"
        case "wav", "aiff":
            return "Audio/WAV"
        case "ogg", "opus":
            return "Audio/OGG Opus"
        default:
            return "Audio/Other Audio"
        }
    }

    private func archiveTypeFolderName(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "zip":
            return "Archives/ZIP"
        case "rar":
            return "Archives/RAR"
        case "7z":
            return "Archives/7z"
        case "tar", "gz", "bz2", "xz":
            return "Archives/TAR GZ"
        default:
            return "Archives/Other Archives"
        }
    }

    private var readingExtensions: Set<String> {
        ["epub", "kepub", "mobi", "azw", "azw3", "ibooks", "iba", "djvu", "cbz", "cbr", "cb7", "cbt", "pdf"]
    }

    private var videoExtensions: Set<String> {
        ["mkv", "mp4", "m4v", "avi", "mov", "wmv", "webm", "ts", "m2ts"]
    }

    private var documentExtensions: Set<String> {
        ["txt", "md", "markdown", "rtf", "doc", "docx", "pages", "numbers", "key", "csv", "tsv", "json", "xml", "html", "htm", "css", "pdf", "ppt", "pptx", "xls", "xlsx"]
    }

    private var imageExtensions: Set<String> {
        ["jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "tiff", "bmp", "svg"]
    }

    private var audioExtensions: Set<String> {
        ["mp3", "m4a", "aac", "flac", "wav", "aiff", "ogg", "opus"]
    }

    private var archiveExtensions: Set<String> {
        ["zip", "rar", "7z", "tar", "gz", "bz2", "xz"]
    }

    private func videoNameParts(
        for rawName: String,
        parentFolderName: String?,
        requiresTitleMatch: Bool,
        config: SableLibraryConfig,
        sourceMetadataTermKeys: Set<String>,
        bareEpisodeSeriesTitleKeys: Set<String>,
        service: SableLibraryService
    ) -> VideoNameParts {
        let cleaned = cleanedVideoTitle(
            service.cleanedTitle(rawName, config: config, sourceMetadataTermKeys: sourceMetadataTermKeys),
            sourceMetadataTermKeys: sourceMetadataTermKeys,
            service: service
        )
        guard let parentFolderName else {
            let seriesTitle = videoSeriesTitle(
                from: cleaned,
                bareEpisodeSeriesTitleKeys: bareEpisodeSeriesTitleKeys,
                service: service
            ) ?? cleaned
            let fileTitle = videoFileTitle(
                from: cleaned,
                seriesTitle: seriesTitle,
                bareEpisodeSeriesTitleKeys: bareEpisodeSeriesTitleKeys,
                service: service
            )
            return VideoNameParts(
                seriesTitle: service.cleanSeriesTitle(seriesTitle),
                fileTitle: fileTitle,
                needsManualReview: seriesTitleNeedsReview(seriesTitle, service: service)
            )
        }

        let folderTitle = service.cleanSeriesTitle(parentFolderName)
        let preferredSeriesTitle = SableLibraryProviderQueryCleaner.searchTitle(from: folderTitle) ?? folderTitle
        let detectedSeriesTitle = videoSeriesTitle(
            from: cleaned,
            bareEpisodeSeriesTitleKeys: bareEpisodeSeriesTitleKeys,
            service: service
        )
        let normalizedPreferred = service.normalizeTerm(preferredSeriesTitle)
        let normalizedDetected = detectedSeriesTitle.map(service.normalizeTerm)
        let fileTitle: String

        if let detectedSeriesTitle,
           !requiresTitleMatch || normalizedDetected == normalizedPreferred || normalizedPreferred.hasPrefix(normalizedDetected ?? "") || (normalizedDetected?.hasPrefix(normalizedPreferred) ?? false) {
            fileTitle = cleaned.replacingOccurrences(
                of: detectedSeriesTitle,
                with: preferredSeriesTitle,
                options: [.anchored, .caseInsensitive]
            )
        } else {
            fileTitle = cleaned
        }

        return VideoNameParts(
            seriesTitle: preferredSeriesTitle,
            fileTitle: fileTitle,
            needsManualReview: detectedSeriesTitle.map { seriesTitleNeedsReview($0, service: service) } ?? false
        )
    }

    private func cleanedVideoTitle(
        _ value: String,
        sourceMetadataTermKeys: Set<String>,
        service: SableLibraryService
    ) -> String {
        let withoutSourceNotes = removingLeadingVideoSourceNotes(
            from: value,
            sourceMetadataTermKeys: sourceMetadataTermKeys,
            service: service
        )
        let spaced = withoutSourceNotes
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return service.sanitizeFilename(spaced.isEmpty ? withoutSourceNotes : spaced)
    }

    private func cleanedVideoTitleWithoutSourceRemoval(_ value: String, service: SableLibraryService) -> String {
        let spaced = value
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return service.sanitizeFilename(spaced.isEmpty ? value : spaced)
    }

    private func videoSeriesTitle(
        from cleanedTitle: String,
        bareEpisodeSeriesTitleKeys: Set<String>,
        service: SableLibraryService
    ) -> String? {
        let patterns = [
            #"(?i)^(.+?)(?:\s*[-–—]\s*|\s+)S(?:eason)?\s*0*\d{1,2}\s*E(?:p(?:isode)?)?\.?\s*0*\d{1,3}\b"#,
            #"(?i)^(.+?)(?:\s*[-–—]\s*|\s+)Episode\s*0*\d{1,3}\b"#,
            #"(?i)^(.+?)\s*[-–—]\s*0*\d{1,3}\b"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: cleanedTitle, range: NSRange(cleanedTitle.startIndex..<cleanedTitle.endIndex, in: cleanedTitle)),
                  let range = Range(match.range(at: 1), in: cleanedTitle) else {
                continue
            }
            let title = service.sanitizeFilename(String(cleanedTitle[range]))
            if !title.isEmpty {
                return title
            }
        }

        if let parts = bareVideoEpisodeParts(from: cleanedTitle, service: service),
           shouldUseBareVideoEpisodeParts(parts, bareEpisodeSeriesTitleKeys: bareEpisodeSeriesTitleKeys, service: service) {
            return parts.seriesTitle
        }

        return nil
    }

    private func videoFileTitle(
        from cleanedTitle: String,
        seriesTitle: String,
        bareEpisodeSeriesTitleKeys: Set<String>,
        service: SableLibraryService
    ) -> String {
        guard let parts = bareVideoEpisodeParts(from: cleanedTitle, service: service),
              shouldUseBareVideoEpisodeParts(parts, bareEpisodeSeriesTitleKeys: bareEpisodeSeriesTitleKeys, service: service),
              service.normalizeTerm(parts.seriesTitle) == service.normalizeTerm(seriesTitle) else {
            return cleanedTitle
        }
        return service.sanitizeFilename("\(parts.seriesTitle) - \(parts.episodeText)")
    }

    private func bareVideoEpisodeParts(from cleanedTitle: String, service: SableLibraryService) -> BareVideoEpisodeParts? {
        let pattern = #"(?i)^(.+?)\s+(\d{1,3})(?:\s*(?:v\d+))?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: cleanedTitle, range: NSRange(cleanedTitle.startIndex..<cleanedTitle.endIndex, in: cleanedTitle)),
              let seriesRange = Range(match.range(at: 1), in: cleanedTitle),
              let episodeRange = Range(match.range(at: 2), in: cleanedTitle) else {
            return nil
        }

        let rawSeriesTitle = String(cleanedTitle[seriesRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        let rawEpisode = String(cleanedTitle[episodeRange])
        guard let episodeNumber = Int(rawEpisode),
              episodeNumber > 0,
              episodeNumber < 200 else {
            return nil
        }

        let seriesTitle = service.sanitizeFilename(rawSeriesTitle)
        guard !seriesTitle.isEmpty else { return nil }

        let hasLeadingZero = rawEpisode.count > 1 && rawEpisode.hasPrefix("0")
        let episodeText = hasLeadingZero || rawEpisode.count > 1
            ? rawEpisode
            : String(format: "%02d", episodeNumber)
        return BareVideoEpisodeParts(
            seriesTitle: seriesTitle,
            episodeText: episodeText,
            hasLeadingZero: hasLeadingZero
        )
    }

    private func shouldUseBareVideoEpisodeParts(
        _ parts: BareVideoEpisodeParts,
        bareEpisodeSeriesTitleKeys: Set<String>,
        service: SableLibraryService
    ) -> Bool {
        parts.hasLeadingZero || bareEpisodeSeriesTitleKeys.contains(service.normalizeTerm(parts.seriesTitle))
    }

    private func removingLeadingVideoSourceNotes(
        from value: String,
        sourceMetadataTermKeys: Set<String>,
        service: SableLibraryService
    ) -> String {
        var current = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^\s*(?:\[([^\]]+)\]|\(([^)]+)\))\s*(.+)$"#

        while let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: current, range: NSRange(current.startIndex..<current.endIndex, in: current)) {
            let sourceRange = match.range(at: 1).location != NSNotFound ? match.range(at: 1) : match.range(at: 2)
            guard let noteRange = Range(sourceRange, in: current),
                  let remainderRange = Range(match.range(at: 3), in: current) else {
                break
            }

            let note = String(current[noteRange])
            let remainder = String(current[remainderRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard shouldRemoveLeadingVideoSourceNote(
                note,
                remainder: remainder,
                sourceMetadataTermKeys: sourceMetadataTermKeys,
                service: service
            ) else {
                break
            }
            current = remainder
        }

        return current
    }

    private func shouldRemoveLeadingVideoSourceNote(
        _ note: String,
        remainder: String,
        sourceMetadataTermKeys: Set<String>,
        service: SableLibraryService
    ) -> Bool {
        guard !remainder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }

        let normalizedNote = service.normalizeTerm(note)
        if sourceMetadataTermKeys.contains(normalizedNote) {
            return true
        }

        let tokens = Set(normalizedNote.split(separator: " ").map(String.init))
        let domainTokens: Set<String> = [
            "com",
            "net",
            "org",
            "tv",
            "site",
            "io",
            "cc",
            "club",
            "online",
            "xyz",
            "app"
        ]
        if !tokens.isDisjoint(with: domainTokens) {
            return true
        }

        return note.range(
            of: #"(?:^|[.\s_-])(?:com|net|org|tv|site|io|cc|club|online|xyz|app)$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private func seriesTitleNeedsReview(_ title: String, service: SableLibraryService) -> Bool {
        service.compactTitleNeedsManualReview(raw: title, spaced: service.spacedSeriesName(title))
    }

    private func epubRepairItems(
        for book: LibraryBookSnapshot,
        stage: LibraryPipelineStage,
        root: URL,
        config: SableLibraryConfig,
        deepContentChecks: Bool,
        repairScopes: Set<SableLibraryEPUBRepairScope>,
        optimizePageImageEPUBs: Bool,
        writeEPUBImportMetadata: Bool,
        service: SableLibraryService
    ) -> [LibraryPlanItem] {
        guard book.fileExtension == "epub" else { return [] }

        if book.isPackageBook {
            guard repairScopes.contains(.package) || repairScopes.contains(.compatibility) else {
                return []
            }
            return [packageRepairItem(for: book, stage: stage)]
        }

        let epubURL = root.appendingPathComponent(book.path)
        let sidecarMetadata = service.epubImportMetadataCandidate(for: epubURL, root: root, config: config)
        let importMetadata = writeEPUBImportMetadata ? sidecarMetadata : nil
        guard let analysis = service.appleBooksCompatibilityRepairAnalysis(
            for: epubURL,
            relativePath: book.path,
            root: root,
            config: config,
            deepContentChecks: deepContentChecks,
            optimizePageImageEPUBs: optimizePageImageEPUBs,
            importMetadata: importMetadata,
            trustedCoverURLString: sidecarMetadata?.coverURL,
            localCoverCandidates: sidecarMetadata?.localCoverCandidates ?? [],
            coverProvider: sidecarMetadata?.coverProvider,
            repairScopes: repairScopes
        ) else {
            return []
        }

        return appleBooksCompatibilityRepairItems(
            for: book,
            stage: stage,
            analysis: analysis,
            repairScopes: repairScopes
        )
    }

    private func packageRepairItem(
        for book: LibraryBookSnapshot,
        stage: LibraryPipelineStage
    ) -> LibraryPlanItem {
        LibraryPlanItem(
            stage: stage,
            operation: .repairEpubPackage,
            currentPath: book.path,
            proposedPath: book.path,
            reason: "Expanded EPUB package can be rebuilt into a normal EPUB file at the same path.",
            confidence: .high,
            safety: .reversible,
            decision: .checked,
            requiresReview: false,
            confidenceExplanation: "The repair verifies EPUB anchors first, writes a standards-shaped EPUB, then validates the final archive before removing the temporary package backup.",
            correctionOptions: [.keepTitle, .custom],
            reviewTags: ["epub-package-repair", "epub-repair"],
            receipt: "repair EPUB package: \(book.path)"
        )
    }

    private func appleBooksCompatibilityRepairItems(
        for book: LibraryBookSnapshot,
        stage: LibraryPipelineStage,
        analysis: LibraryAppleBooksCompatibilityRepairAnalysis,
        repairScopes: Set<SableLibraryEPUBRepairScope>
    ) -> [LibraryPlanItem] {
        let metadataProviders = analysis.coverProvider.map { [$0] } ?? []
        let isProtected = analysis.protection.isProtected
        let protectedReason = analysis.protection.reason ?? "EPUB contains encrypted content resources."
        if isProtected {
            return [
                appleBooksCompatibilityRepairItem(
                    for: book,
                    stage: stage,
                    analysis: analysis,
                    scope: .diagnostics,
                    reasons: [protectedReason],
                    title: "protected EPUB",
                    metadataProviders: metadataProviders,
                    safety: .inspectOnly,
                    decision: .unchecked,
                    requiresReview: true,
                    confidence: .medium,
                    confidenceExplanation: "Sable found encrypted non-font content or a DRM marker. The row stays visible because the file needs an outside clean source; Sable will not rewrite protected book content."
                )
            ]
        }

        let scopedReasons = epubRepairScopedReasons(from: analysis.reasons)
        let effectiveScopes = repairScopes.isEmpty ? SableLibraryEPUBRepairScope.all : repairScopes
        return orderedEPUBRepairScopes.filter { effectiveScopes.contains($0) }.compactMap { scope in
            guard let reasons = scopedReasons[scope], !reasons.isEmpty else {
                return nil
            }
            let needsReview = epubRepairNeedsReview(reasons: reasons, isProtected: false)
            return appleBooksCompatibilityRepairItem(
                for: book,
                stage: stage,
                analysis: analysis,
                scope: scope,
                reasons: reasons,
                title: epubRepairScopeTitle(scope),
                metadataProviders: metadataProviders,
                safety: needsReview ? .needsChoice : .reversible,
                decision: needsReview ? .unchecked : .checked,
                requiresReview: needsReview,
                confidence: needsReview ? .medium : .high,
                confidenceExplanation: epubRepairScopeExplanation(
                    scope,
                    needsReview: needsReview,
                    reasons: reasons
                )
            )
        }
    }

    private func appleBooksCompatibilityRepairItem(
        for book: LibraryBookSnapshot,
        stage: LibraryPipelineStage,
        analysis: LibraryAppleBooksCompatibilityRepairAnalysis,
        scope: SableLibraryEPUBRepairScope,
        reasons: [String],
        title: String,
        metadataProviders: [SableLibraryMetadataProvider],
        safety: LibraryPlanSafety,
        decision: LibraryPlanDecision,
        requiresReview: Bool,
        confidence: LibraryPlanConfidence,
        confidenceExplanation: String
    ) -> LibraryPlanItem {
        LibraryPlanItem(
            stage: stage,
            operation: .repairAppleBooksCompatibility,
            currentPath: book.path,
            proposedPath: analysis.outputRelativePath,
            reason: "Sable's Clinic \(title): \(reasons.joined(separator: "; ")).",
            confidence: confidence,
            safety: safety,
            decision: decision,
            requiresReview: requiresReview,
            usedNetworkData: scope == .cover && analysis.downloadsTrustedCover,
            metadataProviders: metadataProviders,
            confidenceExplanation: confidenceExplanation,
            correctionOptions: [.keepTitle, .custom],
            reviewTags: epubRepairReviewTags(from: reasons, isProtected: safety == .inspectOnly, scope: scope),
            receipt: "Sable's Clinic \(title): \(book.path)"
        )
    }

    private var orderedEPUBRepairScopes: [SableLibraryEPUBRepairScope] {
        [.metadata, .tags, .cover, .readerImport, .navigation, .structure, .package, .content, .compatibility, .diagnostics]
    }

    private func epubRepairScopedReasons(from reasons: [String]) -> [SableLibraryEPUBRepairScope: [String]] {
        let joinedReasons = reasons.map { $0.lowercased() }.joined(separator: " ")
        let hasNCXIdentifierRepair = joinedReasons.contains("ncx table of contents identifier")
        return reasons.reduce(into: [SableLibraryEPUBRepairScope: [String]]()) { partialResult, reason in
            let normalized = reason.lowercased()
            let scope: SableLibraryEPUBRepairScope
            if normalized.contains("epubcheck-style health scan") {
                scope = .diagnostics
            } else if normalized.contains("apple books cover import") {
                scope = .readerImport
            } else if normalized.contains("description and subject")
                || normalized.contains("subject tag")
                || normalized.contains("subject tags") {
                scope = .tags
            } else if normalized.contains("cover") {
                scope = .cover
            } else if normalized.contains("semantic heading")
                || normalized.contains("semantic chapter heading")
                || normalized.contains("chapter headings from existing ncx")
                || normalized.contains("ncx-backed") {
                scope = .structure
            } else if normalized.contains("navigation")
                || normalized.contains("toc")
                || normalized.contains("navigation order")
                || normalized.contains("ncx table of contents playorder")
                || normalized.contains("ncx table of contents identifier")
                || normalized.contains("ncx table of contents target")
                || normalized.contains("ncx pagelist")
                || normalized.contains("table of contents") {
                scope = .navigation
            } else if hasNCXIdentifierRepair,
                      normalized.contains("metadata refinement")
                        || normalized.contains("legacy epub metadata")
                        || normalized.contains("opf package identifier") {
                scope = .navigation
            } else if normalized.contains("fixed-layout")
                || normalized.contains("page box")
                || normalized.contains("optimization")
                || normalized.contains("optimize")
                || normalized.contains("lossy") {
                scope = .diagnostics
            } else if normalized.contains("manifest")
                || normalized.contains("epub guide")
                || normalized.contains("spine page-map")
                || normalized.contains("epub tours")
                || normalized.contains("scripted")
                || normalized.contains("svg")
                || normalized.contains("font")
                || normalized.contains("dead epub spine") {
                scope = .package
            } else if normalized.contains("epub content-type")
                || normalized.contains("epub content document")
                || normalized.contains("duplicate epub content")
                || normalized.contains("orphan xhtml inline closing")
                || normalized.contains("missing local epub script")
                || normalized.contains("guarded xhtml parser repair")
                || normalized.contains("malformed xhtml")
                || normalized.contains("xhtml named")
                || normalized.contains("bare xhtml ampersand")
                || normalized.contains("xhtml void element")
                || normalized.contains("invalid xhtml control")
                || normalized.contains("retarget")
                || normalized.contains("missing epub linked resource")
                || normalized.contains("http-equiv")
                || normalized.contains("epub doctype")
                || normalized.contains("xhtml doctype")
                || normalized.contains("non-breaking space")
                || normalized.contains("custom data")
                || normalized.contains("image dimension")
                || normalized.contains("guarded epub css")
                || normalized.contains("simple epub css") {
                scope = .content
            } else if normalized.contains("mimetype")
                || normalized.contains("package version")
                || normalized.contains("epub 3.4-compatible")
                || normalized.contains("3.3/3.4")
                || normalized.contains("metadata refinement")
                || normalized.contains("legacy epub metadata")
                || normalized.contains("non-namespaced epub metadata")
                || normalized.contains("opf package identifier")
                || normalized.contains("itunesmetadata")
                || normalized.contains("itunes metadata") {
                scope = .compatibility
            } else {
                scope = .metadata
            }
            partialResult[scope, default: []].append(reason)
        }
    }

    private func epubRepairScopeTitle(_ scope: SableLibraryEPUBRepairScope) -> String {
        switch scope {
        case .metadata:
            return "metadata"
        case .tags:
            return "tags and descriptions"
        case .cover:
            return "covers"
        case .readerImport:
            return "Apple Books import refresh"
        case .navigation:
            return "navigation"
        case .structure:
            return "structure"
        case .package:
            return "package"
        case .content:
            return "content documents"
        case .compatibility:
            return "compatibility cleanup"
        case .diagnostics:
            return "layout and page-image repairs"
        }
    }

    private func epubRepairScopeExplanation(
        _ scope: SableLibraryEPUBRepairScope,
        needsReview: Bool,
        reasons: [String]
    ) -> String {
        if needsReview {
            if scope == .cover {
                if let volumeMismatch = reasons.first(where: {
                    $0.localizedCaseInsensitiveContains("embedded cover prints Volume")
                }) {
                    return "\(volumeMismatch) The row stays unchecked until you review it; Sable validates a temporary EPUB before replacing the original."
                }
                return "The language-matched library cover is clearly larger than the embedded cover. Because this is a visible edition-sensitive change, the row stays unchecked until you review it; Sable validates a temporary EPUB before replacing the original."
            }
            return "This finding cannot be repaired from the current EPUB alone. Sable keeps it visible so it can be replaced with a cleaner source instead of pretending it was fixed."
        }

        switch scope {
        case .metadata:
            return "Sable writes identity, series, creator, publisher, language, date, page, identifier, and reader import fields from trusted local sidecars, then validates a temporary EPUB before replacing the original."
        case .tags:
            return "Sable writes cleaned description and subject tags from trusted local sidecars. Book text and styling stay untouched."
        case .cover:
            return "Sable repairs EPUB cover markers, fills missing covers from local cover files or trusted sidecar URLs, and can replace an embedded cover only when a local language-matched cover is clearly better. The rebuilt EPUB is validated before it replaces the original."
        case .readerImport:
            return "Sable refreshes the package identity and cover markers on a validated temporary EPUB. The row starts unchecked because you must remove the stale Apple Books entry before importing the repaired file to avoid a duplicate."
        case .navigation:
            return "Sable repairs EPUB 3 navigation markers and can create or rebuild a standards-shaped TOC from existing spine order, real document headings, document titles, or an older NCX table of contents. It does not rewrite chapter prose."
        case .structure:
            return "Sable promotes exact NCX-linked paragraph or div labels into semantic H1-H6 headings, keeps text and anchors, and validates the rebuilt EPUB. It does not guess from styling."
        case .package:
            return "Sable repairs OPF manifest, guide, SVG/scripted, and font declarations for resources already inside the EPUB, then validates the temporary EPUB."
        case .content:
            return "Sable repairs safe XHTML document details such as legacy headers, content-type declarations, named entities, custom data attributes, image dimension attributes, duplicate IDs, orphan inline closing tags, missing local script tags, and broken links that have exactly one real target."
        case .compatibility:
            return "Sable removes stale reader import files, refreshes safe package identifiers, and patches OPF/NCX metadata wiring. Content-document repairs stay in the Content lane so package cleanup cannot unexpectedly rewrite chapter files."
        case .diagnostics:
            return "Sable repairs fixed-layout and page-image issues only on a temporary EPUB, validates the rebuilt file, and leaves the original alone if validation fails."
        }
    }

    private func epubRepairReviewTags(
        from reasons: [String],
        isProtected: Bool = false,
        scope: SableLibraryEPUBRepairScope? = nil
    ) -> [String] {
        var tags = ["epub-repair", "epub-apple-books", "epub-health-scan"]
        if let scope {
            tags.append(scope.reviewTag)
        }
        tags.append(epubCheckerLayer(from: reasons).reviewTag)
        if isProtected {
            tags.append("epub-protected")
        }
        let normalizedReasons = reasons.map { $0.lowercased() }.joined(separator: " ")
        if normalizedReasons.contains("cover") {
            tags.append("epub-cover")
        }
        if normalizedReasons.contains("apple books cover import") {
            tags.append("epub-reader-import-refresh")
        }
        if normalizedReasons.contains("subject tag") || normalizedReasons.contains("subject tags") {
            tags.append("epub-tags")
        }
        if normalizedReasons.contains("manifest") {
            tags.append("epub-manifest")
        }
        if normalizedReasons.contains("missing epub manifest resource") {
            tags.append("epub-resource-manifest")
            tags.append("ml-training-epub-package")
        }
        if normalizedReasons.contains("dead epub spine") {
            tags.append("epub-spine")
            tags.append("ml-training-epub-package")
        }
        if normalizedReasons.contains("epub guide") {
            tags.append("epub-manifest")
            tags.append("epub-guide")
        }
        if normalizedReasons.contains("epub content-type")
            || normalizedReasons.contains("epub content document")
            || normalizedReasons.contains("http-equiv")
            || normalizedReasons.contains("epub doctype")
            || normalizedReasons.contains("xhtml doctype")
            || normalizedReasons.contains("orphan xhtml inline closing")
            || normalizedReasons.contains("missing local epub script")
            || normalizedReasons.contains("guarded xhtml parser repair")
            || normalizedReasons.contains("xhtml named")
            || normalizedReasons.contains("bare xhtml ampersand")
            || normalizedReasons.contains("xhtml void element")
            || normalizedReasons.contains("invalid xhtml control")
            || normalizedReasons.contains("non-breaking space")
            || normalizedReasons.contains("custom data")
            || normalizedReasons.contains("image dimension")
            || normalizedReasons.contains("guarded epub css")
            || normalizedReasons.contains("simple epub css")
        {
            tags.append("epub-content")
        }
        if normalizedReasons.contains("css") {
            tags.append("epub-css")
            tags.append("ml-training-epub-content")
        }
        if normalizedReasons.contains("missing epub linked resource") {
            tags.append("epub-missing-resource")
            tags.append("epub-content")
            tags.append("ml-training-epub-content")
        }
        if normalizedReasons.contains("duplicate epub manifest") {
            tags.append("epub-duplicate-id")
            tags.append("epub-manifest")
            tags.append("ml-training-epub-package")
        }
        if normalizedReasons.contains("duplicate epub content") {
            tags.append("epub-duplicate-id")
            tags.append("epub-content")
        }
        if normalizedReasons.contains("orphan xhtml inline closing")
            || normalizedReasons.contains("guarded xhtml parser repair")
            || normalizedReasons.contains("malformed xhtml")
            || normalizedReasons.contains("xhtml named")
            || normalizedReasons.contains("bare xhtml ampersand")
            || normalizedReasons.contains("xhtml void element")
            || normalizedReasons.contains("invalid xhtml control") {
            tags.append("epub-xhtml")
            tags.append("ml-training-epub-content")
        }
        if normalizedReasons.contains("missing local epub script") {
            tags.append("epub-scripted")
            tags.append("ml-training-epub-content")
        }
        if normalizedReasons.contains("navigation order") {
            tags.append("epub-navigation-order")
            tags.append("ml-training-epub-navigation")
            if !normalizedReasons.contains("rebuild epub navigation order") {
                tags.append("ml-training-epub-manual-review")
            }
        }
        if normalizedReasons.contains("metadata refinement")
            || normalizedReasons.contains("legacy epub metadata")
            || normalizedReasons.contains("non-namespaced epub metadata")
            || normalizedReasons.contains("opf package identifier")
        {
            tags.append("epub-metadata")
            tags.append(SableLibraryEPUBRepairScope.compatibility.reviewTag)
        }
        if normalizedReasons.contains("navigation")
            || normalizedReasons.contains("toc")
            || normalizedReasons.contains("ncx table of contents playorder")
            || normalizedReasons.contains("ncx pagelist")
            || normalizedReasons.contains("table of contents") {
            tags.append("epub-navigation")
        }
        if normalizedReasons.contains("non-breaking space") {
            tags.append("epub-content-entity")
            tags.append("ml-training-epub-content")
        }
        if normalizedReasons.contains("custom data") {
            tags.append("epub-content-attributes")
            tags.append("ml-training-epub-content")
        }
        if normalizedReasons.contains("scripted") {
            tags.append("epub-scripted")
            tags.append("ml-training-epub-package")
        }
        if normalizedReasons.contains("font manifest") {
            tags.append("epub-fonts")
            tags.append("ml-training-epub-package")
        }
        if normalizedReasons.contains("semantic heading") || normalizedReasons.contains("ncx-backed") {
            tags.append("epub-structure")
            tags.append("epub-navigation-source-ncx")
            tags.append("ml-training-epub-structure")
        }
        if normalizedReasons.contains("h1") {
            tags.append("epub-structure-h1")
        }
        if normalizedReasons.contains("h2")
            || normalizedReasons.contains("h3")
            || normalizedReasons.contains("h4")
            || normalizedReasons.contains("h5")
            || normalizedReasons.contains("h6")
        {
            tags.append("epub-structure-lower-headings")
        }
        if normalizedReasons.contains("ncx") {
            tags.append("epub-navigation-source-ncx")
        }
        if normalizedReasons.contains("spine")
            || normalizedReasons.contains("heading")
            || normalizedReasons.contains("document title")
        {
            tags.append("epub-navigation-source-document-structure")
        }
        if normalizedReasons.contains("comicinfo")
            || normalizedReasons.contains("series and volume")
            || normalizedReasons.contains("title sorting")
            || normalizedReasons.contains("isbn/provider")
            || normalizedReasons.contains("creator, contributor")
            || normalizedReasons.contains("description and subject")
        {
            tags.append("epub-import-metadata")
        }
        if normalizedReasons.contains("fixed-layout") || normalizedReasons.contains("page box") {
            tags.append("epub-fixed-layout")
        }
        if normalizedReasons.contains("optimization") || normalizedReasons.contains("optimize") {
            tags.append("epub-optimize")
        }
        return tags.sorted()
    }

    private func epubRepairNeedsReview(reasons: [String], isProtected: Bool) -> Bool {
        guard !isProtected else { return false }
        let normalizedReasons = reasons.map { $0.lowercased() }.joined(separator: " ")
        return normalizedReasons.contains("cover replacement")
            || normalizedReasons.contains("apple books cover import")
    }

    private func planItem(
        operation: LibraryPlanOperation,
        currentPath: String,
        proposedPath: String,
        reason: String,
        requiresReview: Bool,
        plannedDestinations: inout Set<String>,
        root: URL,
        service: SableLibraryService
    ) -> LibraryPlanItem {
        let proposedURL = root.appendingPathComponent(proposedPath)
        let hasCollision = service.fileManager.fileExists(atPath: proposedURL.path(percentEncoded: false)) || plannedDestinations.contains(proposedPath)
        plannedDestinations.insert(proposedPath)

        let safety: LibraryPlanSafety = hasCollision ? .collision : (requiresReview ? .needsChoice : .reversible)
        return LibraryPlanItem(
            stage: .prepareRawFiles,
            operation: operation,
            currentPath: currentPath,
            proposedPath: proposedPath,
            reason: hasCollision ? "Final path already exists or another suggestion wants the same name. Review duplicate handling first." : reason,
            confidence: requiresReview || hasCollision ? .medium : .high,
            safety: safety,
            decision: requiresReview || hasCollision ? .unchecked : .checked,
            requiresReview: requiresReview || hasCollision,
            confidenceExplanation: confidenceExplanation(
                hasCollision: hasCollision,
                requiresReview: requiresReview,
                operation: operation
            ),
            correctionOptions: correctionOptions(for: operation),
            receipt: "\(currentPath) -> \(proposedPath)"
        )
    }

    private func examples(from items: [LibraryPlanItem], title: String) -> [LibraryPlanExample] {
        items.prefix(3).map { item in
            if item.operation == .sortIntoFolder {
                return looseFileSortExample(from: item, title: title)
            }

            return LibraryPlanExample(
                title: title,
                before: item.currentPath,
                after: item.proposedPath,
                reason: item.reason
            )
        }
    }

    private func looseFileSortExample(from item: LibraryPlanItem, title: String) -> LibraryPlanExample {
        let destination = item.proposedPath ?? ""
        let destinationFolder = normalizedFolderPath(from: destination)
        let destinationFile = (destination as NSString).lastPathComponent
        var details = [
            LibraryPlanExampleDetail(label: "Loose file", value: item.currentPath, symbol: "doc.text")
        ]

        if !destinationFolder.isEmpty {
            details.append(LibraryPlanExampleDetail(label: "Final folder", value: destinationFolder, symbol: "folder"))
        }

        if !destinationFile.isEmpty {
            details.append(LibraryPlanExampleDetail(label: "Final file", value: destinationFile, symbol: "doc"))
        }

        return LibraryPlanExample(
            title: title,
            before: item.currentPath,
            after: item.proposedPath,
            reason: item.reason,
            details: details
        )
    }

    private func packageRepairExamples(from items: [LibraryPlanItem]) -> [LibraryPlanExample] {
        items.prefix(3).map { item in
            LibraryPlanExample(
                title: "EPUB package repair",
                before: item.currentPath,
                after: item.proposedPath,
                reason: item.reason,
                details: [
                    LibraryPlanExampleDetail(label: "Before", value: "Folder package ending in .epub", symbol: "folder"),
                    LibraryPlanExampleDetail(label: "After", value: "Normal EPUB file at the same path", symbol: "doc.zipper"),
                    LibraryPlanExampleDetail(label: "Checks", value: "Preflight, temporary EPUB validation, final EPUB validation", symbol: "checkmark.seal")
                ]
            )
        }
    }

    private func appleBooksRepairExamples(from items: [LibraryPlanItem]) -> [LibraryPlanExample] {
        items.prefix(3).map { item in
            LibraryPlanExample(
                title: "Sable's Clinic cleanup",
                before: item.currentPath,
                after: item.proposedPath,
                reason: item.reason,
                details: [
                    LibraryPlanExampleDetail(label: "Original", value: "Replaced only after validation", symbol: "lock"),
                    LibraryPlanExampleDetail(label: "Cleaned EPUB", value: item.currentPath, symbol: "doc.badge.gearshape"),
                    LibraryPlanExampleDetail(label: "Checks", value: "Metadata, cover markers, package sanity, EPUB validation", symbol: "checkmark.seal")
                ]
            )
        }
    }

    private func normalizedFolderPath(from path: String) -> String {
        let folder = (path as NSString).deletingLastPathComponent
        return folder == "." ? "" : folder
    }

    private func confidenceExplanation(
        hasCollision: Bool,
        requiresReview: Bool,
        operation: LibraryPlanOperation
    ) -> String {
        if hasCollision {
            return "Final path conflict; keep unchecked until duplicate handling is reviewed."
        }
        if requiresReview {
            return "The parser found an ambiguous raw name, so this starts unchecked."
        }
        switch operation {
        case .repairEpubPackage:
            return "The expanded EPUB package will be rebuilt as a normal EPUB file at the same visible path."
        case .repairAppleBooksCompatibility:
            return "A repaired Apple Books-friendly EPUB will replace the original only after the temporary repaired file validates."
        case .sortIntoFolder:
            return "This row shows the final path after folder placement and filename cleanup."
        case .cleanRawName:
            return "The raw filename can be normalized without trusted metadata yet."
        case .inspectOnly, .createComicInfo, .refreshComicInfo, .createAnimeInfo, .refreshAnimeInfo, .renameFolder, .renameFile, .duplicateDecision, .skip:
            return "Prepared by deterministic cleanup rules."
        }
    }

    private func correctionOptions(for operation: LibraryPlanOperation) -> [LibraryPlanCorrectionOption] {
        switch operation {
        case .repairEpubPackage:
            return [.keepTitle, .custom]
        case .repairAppleBooksCompatibility:
            return [.keepTitle, .custom]
        case .sortIntoFolder:
            return [.wrongSeries, .badNumber, .keepTitle, .custom]
        case .cleanRawName:
            return [.badNumber, .keepTitle, .custom]
        case .inspectOnly, .createComicInfo, .refreshComicInfo, .createAnimeInfo, .refreshAnimeInfo, .renameFolder, .renameFile, .duplicateDecision, .skip:
            return [.custom]
        }
    }

    private func existingReadingSeriesFolderIndex(
        series: [LibrarySeriesSnapshot],
        service: SableLibraryService
    ) -> ExistingReadingSeriesFolderIndex {
        var titleBuckets: [String: Set<ExistingReadingSeriesFolder>] = [:]
        var rootTitleBuckets: [String: Set<ExistingReadingSeriesFolder>] = [:]
        var candidates = Set<ExistingReadingSeriesTitleCandidate>()

        for row in series where row.hasComicInfo {
            guard let rootKey = canonicalReadingRootKey(in: row.path, service: service) else { continue }
            let folder = ExistingReadingSeriesFolder(path: row.path, rootKey: rootKey)
            for titleKey in normalizedSeriesTitleKeys(for: row, service: service) {
                titleBuckets[titleKey, default: []].insert(folder)
                rootTitleBuckets[ExistingReadingSeriesFolderIndex.compoundKey(rootKey: rootKey, titleKey: titleKey), default: []].insert(folder)
                candidates.insert(ExistingReadingSeriesTitleCandidate(titleKey: titleKey, folder: folder))
            }
        }

        return ExistingReadingSeriesFolderIndex(
            byTitle: uniqueExistingReadingFolders(in: titleBuckets),
            byRootAndTitle: uniqueExistingReadingFolders(in: rootTitleBuckets),
            candidates: candidates.sorted {
                if $0.titleKey == $1.titleKey {
                    return $0.folder.path.localizedStandardCompare($1.folder.path) == .orderedAscending
                }
                return $0.titleKey.localizedStandardCompare($1.titleKey) == .orderedAscending
            }
        )
    }

    private func rawReadingUpdateFolderMatches(
        series: [LibrarySeriesSnapshot],
        existingIndex: ExistingReadingSeriesFolderIndex,
        service: SableLibraryService
    ) -> [RawReadingUpdateFolderMatch] {
        series.compactMap { row in
            guard !row.hasComicInfo,
                  row.localBookCount > 0,
                  isDirectCanonicalReadingSeriesPath(row.path, service: service),
                  let rootKey = canonicalReadingRootKey(in: row.path, service: service) else {
                return nil
            }

            guard let target = existingIndex.folder(
                forTitleKeys: Array(normalizedSeriesTitleKeys(for: row, service: service)),
                preferredRootKey: rootKey
            ),
                  target.path != row.path else {
                return nil
            }

            return RawReadingUpdateFolderMatch(sourcePath: row.path, targetPath: target.path)
        }
        .sorted { lhs, rhs in
            lhs.sourcePath.localizedStandardCompare(rhs.sourcePath) == .orderedAscending
        }
    }

    private func uniqueExistingReadingFolders(
        in buckets: [String: Set<ExistingReadingSeriesFolder>]
    ) -> [String: ExistingReadingSeriesFolder] {
        buckets.reduce(into: [String: ExistingReadingSeriesFolder]()) { partialResult, row in
            guard row.value.count == 1,
                  let folder = row.value.first else {
                return
            }
            partialResult[row.key] = folder
        }
    }

    private func normalizedSeriesTitleKeys(
        for series: LibrarySeriesSnapshot,
        service: SableLibraryService
    ) -> Set<String> {
        var values = [
            series.localTitle,
            series.preferredTitle,
            series.identityGraph?.preferredTitle,
            series.displayName,
            (series.path as NSString).lastPathComponent
        ]
        values.append(series.primarySourceID.map { "\($0.provider.rawValue)-\($0.value)" })
        values.append(contentsOf: series.identityGraph?.aliases ?? [])

        return Set(values.compactMap { $0 }.flatMap {
            normalizedSeriesTitleMatchKeys($0, service: service)
        })
    }

    private func normalizedSeriesTitleMatchKeys(_ value: String, service: SableLibraryService) -> [String] {
        let stripped = value
            .replacingOccurrences(of: #"\s*\{[A-Za-z]+-[^}]+\}"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*\(\d{4}\)\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let key = service.normalizeTerm(stripped)
        guard !key.isEmpty else { return [] }

        var keys = [key]
        let compactKey = key.replacingOccurrences(of: " ", with: "")
        if compactKey != key, compactKey.count >= 8 {
            keys.append(compactKey)
        }
        return keys
    }

    private func isDirectCanonicalReadingSeriesPath(_ path: String, service: SableLibraryService) -> Bool {
        let components = pathComponents(in: path)
        guard components.count == 2 else { return false }
        return canonicalReadingRootNames.contains(service.normalizeTerm(components[0]))
    }

    private func canonicalReadingRootKey(in path: String, service: SableLibraryService) -> String? {
        guard let root = pathComponents(in: path).first else { return nil }
        let key = service.normalizeTerm(root)
        return canonicalReadingRootNames.contains(key) ? key : nil
    }

    private func pathComponents(in path: String) -> [String] {
        path
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private var canonicalReadingRootNames: Set<String> {
        [
            "books",
            "manga",
            "manhwa",
            "manhua",
            "light novels",
            "oel",
            "other reading"
        ]
    }
}

private struct ExistingReadingSeriesFolder: Hashable, Sendable {
    var path: String
    var rootKey: String
}

private struct ExistingReadingSeriesTitleCandidate: Hashable, Sendable {
    var titleKey: String
    var folder: ExistingReadingSeriesFolder
}

private struct ExistingReadingSeriesFolderIndex: Sendable {
    var byTitle: [String: ExistingReadingSeriesFolder]
    var byRootAndTitle: [String: ExistingReadingSeriesFolder]
    var candidates: [ExistingReadingSeriesTitleCandidate]

    func folder(forTitleKey titleKey: String, preferredRootKey: String?) -> ExistingReadingSeriesFolder? {
        folder(forTitleKeys: [titleKey], preferredRootKey: preferredRootKey)
    }

    func folder(forTitleKeys titleKeys: [String], preferredRootKey: String?) -> ExistingReadingSeriesFolder? {
        let keys = Set(titleKeys.filter { !$0.isEmpty })
        guard !keys.isEmpty else { return nil }

        let exactRootMatches = Set(keys.compactMap { titleKey in
            preferredRootKey.flatMap {
                byRootAndTitle[Self.compoundKey(rootKey: $0, titleKey: titleKey)]
            }
        })
        if exactRootMatches.count == 1 {
            return exactRootMatches.first
        }
        guard exactRootMatches.isEmpty else { return nil }

        let exactMatches = Set(keys.compactMap { byTitle[$0] })
        if exactMatches.count == 1 {
            return exactMatches.first
        }
        guard exactMatches.isEmpty else { return nil }

        let preferredCandidates = preferredRootKey.map { rootKey in
            candidates.filter { $0.folder.rootKey == rootKey }
        } ?? candidates
        let strongMatches = Set(preferredCandidates.compactMap { candidate in
            keys.contains(where: { Self.stronglyMatches($0, candidate.titleKey) })
                ? candidate.folder
                : nil
        })
        return strongMatches.count == 1 ? strongMatches.first : nil
    }

    private static func stronglyMatches(_ lhs: String, _ rhs: String) -> Bool {
        guard lhs != rhs else { return true }
        let lhsWords = lhs.split(separator: " ").map(String.init)
        let rhsWords = rhs.split(separator: " ").map(String.init)
        let shorterWordCount = min(lhsWords.count, rhsWords.count)
        let shorterCharacterCount = min(lhs.count, rhs.count)

        if shorterWordCount >= 3,
           shorterCharacterCount >= 12,
           (lhs.hasPrefix(rhs + " ") || rhs.hasPrefix(lhs + " ")) {
            return true
        }

        guard shorterWordCount >= 5 else { return false }
        let lhsSet = Set(lhsWords)
        let rhsSet = Set(rhsWords)
        let sharedCount = lhsSet.intersection(rhsSet).count
        let denominator = lhsSet.count + rhsSet.count
        guard denominator > 0 else { return false }
        let diceSimilarity = (2.0 * Double(sharedCount)) / Double(denominator)
        return diceSimilarity >= 0.90
    }

    func folderPath(forTitleKey titleKey: String, preferredRoot: String?) -> String? {
        let preferredRootKey = preferredRoot.map { normalizedKey($0) }
        return folder(forTitleKey: titleKey, preferredRootKey: preferredRootKey)?.path
    }

    func folderPath(forTitleKeys titleKeys: [String], preferredRoot: String?) -> String? {
        let preferredRootKey = preferredRoot.map { normalizedKey($0) }
        return folder(forTitleKeys: titleKeys, preferredRootKey: preferredRootKey)?.path
    }

    static func compoundKey(rootKey: String, titleKey: String) -> String {
        "\(rootKey)|\(titleKey)"
    }

    private func normalizedKey(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct RawReadingUpdateFolderMatch: Sendable, Equatable {
    var sourcePath: String
    var targetPath: String
}

private struct VideoNameParts {
    var seriesTitle: String
    var fileTitle: String
    var needsManualReview: Bool
}

private struct BareVideoEpisodeParts {
    var seriesTitle: String
    var episodeText: String
    var hasLeadingZero: Bool
}

private struct WatchingTitleMatchKeys {
    var normalized: Set<String> = []
    var compact: Set<String> = []
}

private struct RawReadingLaneClassification: Sendable, Equatable {
    var readingType: SableLibraryReadingType
    var folderName: String
    var confidence: LibraryPlanConfidence
    var requiresReview: Bool
    var explanation: String
    var reviewTags: [String]
}

private struct RawReadingLaneClassifier: Sendable {
    private let root: URL
    private let service: SableLibraryService
    private let learningMemory: SableLibraryLearningMemory
    private let useLocalLearning: Bool
    private let rootFolders: Set<String>

    init(
        root: URL,
        service: SableLibraryService,
        learningMemory: SableLibraryLearningMemory = SableLibraryLearningMemory(),
        useLocalLearning: Bool = false
    ) {
        self.root = root
        self.service = service
        self.learningMemory = learningMemory
        self.useLocalLearning = useLocalLearning
        self.rootFolders = Self.rootFolders(in: root, service: service)
    }

    func classifyLooseBook(
        for book: LibraryBookSnapshot,
        parsed: BookNameParts
    ) -> RawReadingLaneClassification {
        var state = RawReadingLaneScoringState()
        let ext = book.fileExtension.lowercased()
        let text = normalizedText([
            book.path,
            book.fileName,
            parsed.seriesTitle,
            parsed.fileTitle
        ].joined(separator: " "))

        addExtensionEvidence(ext, parsed: parsed, text: text, state: &state)
        addTextEvidence(text, state: &state)
        addExistingLaneEvidence(state: &state)
        addLearningEvidence(path: book.path, proposedPath: nil, state: &state)

        return resolvedClassification(from: state, fallback: fallbackType(for: ext))
    }

    func classifySeriesFolder(
        path: String,
        displayName: String,
        series: LibrarySeriesSnapshot?,
        books: [LibraryBookSnapshot]
    ) -> RawReadingLaneClassification {
        var state = RawReadingLaneScoringState()
        let text = normalizedText([
            path,
            displayName,
            series?.displayName ?? "",
            series?.localTitle ?? "",
            series?.preferredTitle ?? "",
            series?.mediaType ?? "",
            books.map(\.fileName).joined(separator: " ")
        ].joined(separator: " "))

        if let mediaType = series?.mediaType,
           let type = readingType(from: mediaType) {
            state.add(type, 5.0, "trusted sidecar type: \(mediaType)")
        }

        let extensions = books.map { $0.fileExtension.lowercased() }
        let archiveCount = extensions.filter { comicArchiveExtensions.contains($0) }.count
        let epubCount = extensions.filter { proseEbookExtensions.contains($0) }.count
        let volumeCount = books.filter { book in
            service.volumeOrChapterSuffix(in: (book.fileName as NSString).deletingPathExtension) != nil
        }.count
        let chapterCount = books.filter { book in
            service.volumeOrChapterSuffix(in: (book.fileName as NSString).deletingPathExtension)?.hasPrefix("Ch ") == true
        }.count

        if archiveCount > 0 {
            state.add(.manga, archiveCount >= epubCount ? 3.4 : 1.8, "\(archiveCount) comic archive file(s)")
        }
        if epubCount > 0, volumeCount > 0 {
            state.add(.lightNovel, epubCount >= archiveCount ? 3.3 : 1.7, "\(volumeCount) volume EPUB clue(s)")
        }
        if chapterCount > 0 {
            state.add(.manga, 2.8, "\(chapterCount) chapter clue(s)")
        }
        if epubCount > 0, volumeCount == 0, archiveCount == 0 {
            state.add(.book, 2.5, "\(epubCount) prose ebook file(s) without volume markers")
        }

        if archiveCount > 0, epubCount > 0, abs(archiveCount - epubCount) <= 1 {
            state.add(.unknown, 3.0, "mixed ebook and comic archive folder")
        }

        addTextEvidence(text, state: &state)
        addExistingLaneEvidence(state: &state)
        addLearningEvidence(path: path, proposedPath: nil, state: &state)

        return resolvedClassification(from: state, fallback: .unknown)
    }

    private func addExtensionEvidence(
        _ ext: String,
        parsed: BookNameParts,
        text: String,
        state: inout RawReadingLaneScoringState
    ) {
        if comicArchiveExtensions.contains(ext) {
            state.add(.manga, 3.5, "comic archive extension .\(ext)")
        } else if proseEbookExtensions.contains(ext) {
            if parsed.fileTitle.range(of: #"(?i)\bvol\s+\d{1,4}\b"#, options: .regularExpression) != nil {
                state.add(.lightNovel, 3.4, "volume-numbered ebook")
            } else {
                state.add(.book, 2.5, "standalone prose ebook")
            }
        } else if ext == "pdf" {
            if containsVolumeOrChapterCue(text) {
                state.add(.manga, 1.6, "PDF has volume/chapter wording")
            } else {
                state.add(.unknown, 1.6, "PDF needs document/book triage")
            }
        }
    }

    private func addTextEvidence(_ text: String, state: inout RawReadingLaneScoringState) {
        addTermEvidence(text, terms: manhwaTerms, type: .manhwa, weight: 6.0, label: "manhwa wording", state: &state)
        addTermEvidence(text, terms: manhuaTerms, type: .manhua, weight: 6.0, label: "manhua wording", state: &state)
        addTermEvidence(text, terms: mangaTerms, type: .manga, weight: 2.8, label: "manga wording", state: &state)
        addTermEvidence(text, terms: lightNovelTerms, type: .lightNovel, weight: 2.2, label: "light novel wording", state: &state)
        addTermEvidence(text, terms: oelTerms, type: .oel, weight: 3.0, label: "OEL wording", state: &state)
        addTermEvidence(text, terms: proseBookTerms, type: .book, weight: 1.5, label: "prose wording", state: &state)

        if containsChapterCue(text) {
            state.add(.manga, 2.2, "chapter marker")
        }
        if containsVolumeCue(text) {
            state.add(.lightNovel, 1.8, "volume marker")
        }
    }

    private func addExistingLaneEvidence(state: inout RawReadingLaneScoringState) {
        for type in [SableLibraryReadingType.manga, .manhwa, .manhua, .oel, .lightNovel, .book] {
            if rootFolders.contains(type.folderName.lowercased()) {
                state.add(type, 0.35, "\(type.folderName) lane exists")
            }
        }
    }

    private func addLearningEvidence(path: String, proposedPath: String?, state: inout RawReadingLaneScoringState) {
        guard useLocalLearning else { return }
        for signal in learningMemory.rawReadingLaneSignals(path: path, proposedPath: proposedPath) {
            let weight = signal.confidence == .high ? 2.8 : 1.5
            state.add(signal.readingType, weight, signal.detail)
        }
    }

    private func resolvedClassification(
        from state: RawReadingLaneScoringState,
        fallback: SableLibraryReadingType
    ) -> RawReadingLaneClassification {
        let sorted = state.scores.sorted { lhs, rhs in
            if lhs.value != rhs.value {
                return lhs.value > rhs.value
            }
            return laneSortIndex(lhs.key) < laneSortIndex(rhs.key)
        }
        let winner = sorted.first?.key ?? fallback
        let winningScore = sorted.first?.value ?? 0
        let runnerUpScore = sorted.dropFirst().first?.value ?? 0
        let margin = winningScore - runnerUpScore
        let resolved = winningScore > 0 ? winner : fallback
        let requiresReview = resolved == .unknown || winningScore < 2.2 || margin < 0.65
        let confidence: LibraryPlanConfidence
        if winningScore >= 4.2, margin >= 1.1 {
            confidence = .high
        } else if winningScore >= 2.2, margin >= 0.65 {
            confidence = .medium
        } else {
            confidence = .low
        }
        let evidence = state.evidence[resolved] ?? []
        let evidenceText = evidence.isEmpty ? "fallback reading lane" : Array(evidence.prefix(4)).joined(separator: "; ")
        let scoreText = String(format: "%.1f", winningScore)
        let marginText = String(format: "%.1f", margin)
        let folderName = resolved.folderName

        return RawReadingLaneClassification(
            readingType: resolved,
            folderName: folderName,
            confidence: confidence,
            requiresReview: requiresReview,
            explanation: "Raw reading type: \(folderName). Evidence: \(evidenceText). Score \(scoreText), margin \(marginText).",
            reviewTags: [
                "raw-reading-lane",
                "raw-reading-\(resolved.rawValue)",
                requiresReview ? "raw-reading-review" : "raw-reading-auto"
            ]
        )
    }

    private func addTermEvidence(
        _ text: String,
        terms: [String],
        type: SableLibraryReadingType,
        weight: Double,
        label: String,
        state: inout RawReadingLaneScoringState
    ) {
        let matches = terms.filter { text.contains($0) }
        guard !matches.isEmpty else { return }
        state.add(type, Double(matches.count) * weight, "\(label): \(matches.prefix(3).joined(separator: ", "))")
    }

    private func fallbackType(for ext: String) -> SableLibraryReadingType {
        if comicArchiveExtensions.contains(ext) { return .manga }
        if proseEbookExtensions.contains(ext) { return .book }
        return .unknown
    }

    private func readingType(from mediaType: String) -> SableLibraryReadingType? {
        switch SableLibraryNamingPolicy().normalizedMediaType(mediaType) {
        case "Manga": .manga
        case "Manhwa": .manhwa
        case "Manhua": .manhua
        case "OEL": .oel
        case "Novel": .lightNovel
        case "Book": .book
        case "Other": .unknown
        default: nil
        }
    }

    private func containsVolumeOrChapterCue(_ text: String) -> Bool {
        containsVolumeCue(text) || containsChapterCue(text)
    }

    private func containsVolumeCue(_ text: String) -> Bool {
        text.range(of: #"\bvol(?:ume)?\s+\d{1,4}\b"#, options: .regularExpression) != nil
    }

    private func containsChapterCue(_ text: String) -> Bool {
        text.range(of: #"\b(?:chapter|ch)\s+\d{1,4}\b"#, options: .regularExpression) != nil
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

    private func laneSortIndex(_ type: SableLibraryReadingType) -> Int {
        switch type {
        case .manhwa: 0
        case .manhua: 1
        case .manga: 2
        case .lightNovel: 3
        case .oel: 4
        case .book: 5
        case .comic: 6
        case .novel: 7
        case .unknown: 8
        }
    }

    private var comicArchiveExtensions: Set<String> {
        ["cbz", "cbr", "cb7", "cbt"]
    }

    private var proseEbookExtensions: Set<String> {
        ["epub", "kepub", "mobi", "azw", "azw3", "ibooks", "iba", "djvu"]
    }

    private var mangaTerms: [String] {
        [" manga ", " tankobon ", " tankoubon ", " doujin ", " oneshot ", " one shot "]
    }

    private var manhwaTerms: [String] {
        [" manhwa ", " webtoon ", " tapas ", " tappytoon ", " lezhin ", " kakaopage ", " kakao "]
    }

    private var manhuaTerms: [String] {
        [" manhua ", " bilibili ", " kuaikan ", " acqq ", " qq "]
    }

    private var lightNovelTerms: [String] {
        [
            " light novel ", " ranobe ", " j novel ", " jnovel ", " yen on ",
            " seven seas ", " airship ", " tentai ", " cross infinite world ",
            " reincarnated ", " reincarnation ", " isekai ", " villainess ",
            " adventurer ", " demon lord ", " magic academy "
        ]
    }

    private var oelTerms: [String] {
        [" oel ", " original english ", " english language manga ", " webcomic "]
    }

    private var proseBookTerms: [String] {
        [" novel ", " memoir ", " poems ", " essays ", " complete scripts ", " screenplay "]
    }

    private static func rootFolders(in root: URL, service: SableLibraryService) -> Set<String> {
        guard let children = try? service.fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return Set(children.compactMap { url in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                return nil
            }
            return url.lastPathComponent.lowercased()
        })
    }
}

private struct RawReadingLaneScoringState {
    var scores: [SableLibraryReadingType: Double] = [:]
    var evidence: [SableLibraryReadingType: [String]] = [:]

    mutating func add(_ type: SableLibraryReadingType, _ score: Double, _ detail: String) {
        scores[type, default: 0] += score
        evidence[type, default: []].append(detail)
    }
}
