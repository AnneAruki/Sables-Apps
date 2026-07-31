//
//  SableLibraryStep1InspectLibrary.swift
//  Sable's Library
//

import Foundation

nonisolated struct SableLibraryStep1InspectLibrary: Sendable {
    func inspect(
        root: URL,
        options: LibraryPipelineOptions,
        mode: LibraryPipelineInspectMode = .full,
        service: SableLibraryService
    ) async -> LibraryInspection {
        service.reportProgress(progressMessage(for: mode, isFinishing: false))

        do {
            let config = service.currentConfig()
            if mode == .lightInventory {
                let inventory = try service.enumerateLightInventoryItems(root: root, config: config)
                let cachedWarnings = service.cachedScanWarnings(for: service.scanCacheKey(root: root, config: config))
                let scanWarnings = Array(Set(inventory.warnings + cachedWarnings)).sorted()
                service.reportProgress("Light inventory: summarizing files and sidecars without opening every sidecar")
                let inspection = lightInventoryInspection(
                    root: root,
                    mode: mode,
                    items: inventory.items,
                    fileCount: inventory.fileCount,
                    folderCount: inventory.folderCount,
                    scanWarnings: scanWarnings,
                    options: options,
                    config: config,
                    service: service
                )
                return inspectionWithRootCatalog(inspection, root: root, config: config, service: service)
            }

            if mode.usesFocusedEPUBClinicInventory {
                let inventory = try service.enumerateEPUBClinicItems(
                    root: root,
                    config: config,
                    changedPaths: mode.quickVerifyChangedPaths
                )
                return focusedEPUBClinicInspection(
                    root: root,
                    mode: mode,
                    inventory: inventory,
                    service: service
                )
            }

            let items = try service.enumerateItems(root: root, config: config)
            let scanWarnings = service.cachedScanWarnings(for: service.scanCacheKey(root: root, config: config))
            let matcher = SableLibraryFileTypeMatcher(config: config)
            let folders = items.filter(\.isDirectory)
            let files = items.filter { !$0.isDirectory }

            let books = service.bookItems(
                in: items,
                root: root,
                config: config,
                cleanupOptions: options.cleanup
            )
            let videos = items.filter { matcher.isVideo(url: $0.url, isDirectory: $0.isDirectory) }
            let packageBookCount = books.filter(\.isDirectory).count
            let seriesEntries = try service.seriesEntries(root: root, config: config, cleanupOptions: options.cleanup)
            let videoSeriesEntries = try service.videoSeriesEntries(root: root, config: config)
            let comicInfoFolders = try service.comicInfoFolders(root: root, config: config)
            let animeInfoFolders = try service.animeInfoFolders(root: root, config: config)
            let comicInfoFolderPaths = Set(comicInfoFolders.map { $0.standardizedFileURL.path(percentEncoded: false) })
            let animeInfoFolderPaths = Set(animeInfoFolders.map { $0.standardizedFileURL.path(percentEncoded: false) })
            let comicInfoByFolderPath = comicInfoFolders.reduce(into: [String: [String: Any]?]()) { partialResult, folder in
                let folderPath = folder.standardizedFileURL.path(percentEncoded: false)
                partialResult[folderPath] = readComicInfo(folder: folder, config: config, service: service)
            }
            let animeInfoByFolderPath = animeInfoFolders.reduce(into: [String: [String: Any]?]()) { partialResult, folder in
                let folderPath = folder.standardizedFileURL.path(percentEncoded: false)
                partialResult[folderPath] = readAnimeInfo(folder: folder, config: config)
            }
            let comicInfoSeriesPaths = comicInfoFolders.map {
                service.relativePath(for: $0, root: root)
            }.sorted()
            let animeInfoSeriesPaths = animeInfoFolders.map {
                service.relativePath(for: $0, root: root)
            }.sorted()
            let metadataSummary = mode.runsMetadataScan
                ? try service.metadataScanSummary(root: root, config: config, cleanupOptions: options.cleanup)
                : MetadataScanSummary(candidates: [], sourceTermKeys: [])
            let metadataCandidates = metadataSummary.candidates
            let missingNumberItems = mode.runsMissingNumberScan
                ? try service.missingNumberItems(root: root, config: config, cleanupOptions: options.cleanup)
                : []
            let duplicateGroups = mode.runsDuplicateScan
                ? try service.duplicateReviewGroups(root: root, config: config, cleanupOptions: options.cleanup)
                : []
            let booksBySeriesPath = Dictionary(grouping: books) { item in
                service.relativePath(for: item.url.deletingLastPathComponent(), root: root)
            }
            let videosBySeriesPath = Dictionary(grouping: videos) { item in
                service.relativePath(for: item.url.deletingLastPathComponent(), root: root)
            }

            let looseBooks = books.filter { item in
                item.url.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL
            }
            let looseVideos = videos.filter { item in
                item.url.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL
            }
            let missingComicInfoSeriesPaths = seriesEntries.compactMap { entry -> String? in
                let path = entry.folderURL.standardizedFileURL.path(percentEncoded: false)
                return comicInfoFolderPaths.contains(path) ? nil : entry.relativePath
            }
            let missingAnimeInfoSeriesPaths = videoSeriesEntries.compactMap { entry -> String? in
                let path = entry.folderURL.standardizedFileURL.path(percentEncoded: false)
                return animeInfoFolderPaths.contains(path) ? nil : entry.relativePath
            }

            let snapshots = seriesEntries.map { entry in
                let folderPath = entry.folderURL.standardizedFileURL.path(percentEncoded: false)
                let folderSourceIDs = SableLibrarySourceIDParser.folderHints(in: entry.folderURL.lastPathComponent)
                let rawComicInfo = comicInfoByFolderPath[folderPath] ?? nil
                let comicInfo = rawComicInfo.map { sidecarByAddingSourceIDs($0, sourceIDs: folderSourceIDs) }
                let localTitle = comicInfo.flatMap { service.textValue($0["local_title"]) }
                let preferredTitle = comicInfo.flatMap {
                    preferredSidecarTitle(
                        from: $0,
                        preference: options.stages.preferredTitleStyle,
                        service: service
                    )
                }
                let mediaType = comicInfo.flatMap { service.textValue($0["type"]) }
                let sableMetadata = comicInfo?["_sable"] as? [String: Any]
                let mangaBakaMetadata = sableMetadata?["mangabaka"] as? [String: Any]
                let comicInfoLastChecked = comicInfo.flatMap {
                    service.textValue($0["last_checked"]) ?? service.textValue(sableMetadata?["refreshed_at"])
                }
                let freshness = comicInfo.map { sourceFreshness(from: $0, service: service) } ?? []
                let localBooks = booksBySeriesPath[entry.relativePath] ?? []
                let localSnapshotChanged = localFileSnapshotChanged(
                    sidecar: rawComicInfo,
                    snapshotKey: "book_snapshot",
                    signatureKey: "book_signature",
                    localItems: localBooks,
                    service: service
                )
                return LibrarySeriesSnapshot(
                    id: entry.relativePath.isEmpty ? entry.title : entry.relativePath,
                    path: entry.relativePath,
                    displayName: entry.title,
                    localTitle: localTitle,
                    preferredTitle: preferredTitle,
                    trustedProviderTitles: comicInfo.map {
                        trustedProviderTitles(from: $0, service: service)
                    } ?? [],
                    mediaType: mediaType,
                    shelfDescription: comicInfo.flatMap { sidecarShelfDescription(from: $0, service: service) },
                    volumeDescriptions: comicInfo.map { ranobeDBVolumeDescriptions(in: $0, service: service) } ?? [],
                    genres: comicInfo.map {
                        sidecarShelfValues(from: $0, keys: ["genres", "genre"], service: service)
                            + providerV2ShelfNames(in: $0, provider: .mangabaka, keys: ["genres_v2", "tags_v2"], includeGenres: true, service: service)
                            + ranobeDBShelfNames(in: $0, includeGenres: true, service: service)
                    } ?? [],
                    themes: comicInfo.map { sidecarShelfValues(from: $0, keys: ["themes", "theme"], service: service) } ?? [],
                    tags: comicInfo.map {
                        sidecarShelfValues(from: $0, keys: ["tags", "subjects", "subject"], service: service)
                            + providerV2ShelfNames(in: $0, provider: .mangabaka, keys: ["tags_v2"], includeGenres: false, service: service)
                            + ranobeDBShelfNames(in: $0, includeGenres: false, service: service)
                    } ?? [],
                    tagRecords: comicInfo.map {
                        providerV2ShelfTagRecords(in: $0, provider: .mangabaka, service: service)
                            + ranobeDBShelfTagRecords(in: $0, service: service)
                    } ?? [],
                    providerNeighborSignals: comicInfo.map {
                        providerNeighborSignals(in: $0, provider: .mangabaka, service: service)
                    } ?? [],
                    contentWarnings: comicInfo.map { sidecarShelfValues(from: $0, keys: ["content_warnings", "warnings"], service: service) } ?? [],
                    year: comicInfo.flatMap { year(from: $0, service: service) },
                    primarySourceID: comicInfo.flatMap { primarySourceID(from: $0, domain: .reading, extraIDs: folderSourceIDs, service: service) } ?? preferredReadingSourceID(from: folderSourceIDs),
                    identityGraph: comicInfo.map { identityGraph(from: $0, domain: .reading, fallbackTitle: preferredTitle ?? localTitle ?? entry.title, extraIDs: folderSourceIDs, service: service) }
                        ?? folderIdentityGraph(folderName: entry.folderURL.lastPathComponent, domain: .reading, sourceIDs: folderSourceIDs, service: service),
                    sourceFreshness: freshness,
                    localFileSnapshotChanged: localSnapshotChanged,
                    finalVolume: comicInfo.flatMap { finalVolume(from: $0, service: service) },
                    localBookCount: localBooks.count,
                    localHighestVolume: localHighestVolume(in: localBooks, config: config, service: service),
                    comicInfoSource: comicInfo.flatMap { service.textValue($0["source"]) },
                    comicInfoLastChecked: comicInfoLastChecked,
                    mangaBakaExpectedType: service.textValue(mangaBakaMetadata?["expected_type"]),
                    mangaBakaTypeMatched: mangaBakaMetadata?["type_match"] as? Bool,
                    missingMangaBakaV2Metadata: comicInfo.map {
                        missingMangaBakaV2Metadata(in: $0, service: service)
                    } ?? false,
                    unavailableMetadataProviders: rawComicInfo.map {
                        unavailableMetadataProviders(from: $0, service: service)
                    } ?? [],
                    providerCandidateReviews: rawComicInfo.map {
                        providerCandidateReviews(from: $0, service: service)
                    } ?? [],
                    hasComicInfo: rawComicInfo != nil
                )
            }

            let videoSnapshots = videoSeriesEntries.map { entry in
                let folderPath = entry.folderURL.standardizedFileURL.path(percentEncoded: false)
                let folderSourceIDs = SableLibrarySourceIDParser.folderHints(in: entry.folderURL.lastPathComponent)
                let rawAnimeInfo = animeInfoByFolderPath[folderPath] ?? nil
                let animeInfo = rawAnimeInfo.map { sidecarByAddingSourceIDs($0, sourceIDs: folderSourceIDs) }
                let localTitle = animeInfo.flatMap { service.textValue($0["local_title"]) }
                let preferredTitle = animeInfo.flatMap {
                    preferredSidecarTitle(
                        from: $0,
                        preference: options.stages.preferredTitleStyle,
                        service: service
                    )
                }
                let mediaType = animeInfo.flatMap { service.textValue($0["type"]) }
                let sableMetadata = animeInfo?["_sable"] as? [String: Any]
                let animeInfoLastChecked = animeInfo.flatMap {
                    service.textValue($0["last_checked"]) ?? service.textValue(sableMetadata?["refreshed_at"])
                }
                let freshness = animeInfo.map { sourceFreshness(from: $0, service: service) } ?? []
                let localVideos = videosBySeriesPath[entry.relativePath] ?? []
                let localSnapshotChanged = localFileSnapshotChanged(
                    sidecar: rawAnimeInfo,
                    snapshotKey: "video_snapshot",
                    signatureKey: "video_signature",
                    localItems: localVideos,
                    service: service
                )
                return LibraryVideoSeriesSnapshot(
                    id: entry.relativePath.isEmpty ? entry.title : entry.relativePath,
                    path: entry.relativePath,
                    displayName: entry.title,
                    localTitle: localTitle,
                    preferredTitle: preferredTitle,
                    mediaType: mediaType,
                    year: animeInfo.flatMap { year(from: $0, service: service) },
                    primarySourceID: animeInfo.flatMap { primarySourceID(from: $0, domain: .watching, extraIDs: folderSourceIDs, service: service) },
                    identityGraph: animeInfo.flatMap { identityGraph(from: $0, domain: .watching, fallbackTitle: preferredTitle ?? localTitle ?? entry.title, extraIDs: folderSourceIDs, service: service) }
                        ?? folderIdentityGraph(folderName: entry.folderURL.lastPathComponent, domain: .watching, sourceIDs: folderSourceIDs, service: service),
                    sourceFreshness: freshness,
                    localFileSnapshotChanged: localSnapshotChanged,
                    localVideoCount: localVideos.count,
                    animeInfoSource: animeInfo.flatMap { service.textValue($0["source"]) },
                    animeInfoLastChecked: animeInfoLastChecked,
                    unavailableMetadataProviders: rawAnimeInfo.map {
                        unavailableMetadataProviders(from: $0, service: service)
                    } ?? [],
                    providerCandidateReviews: rawAnimeInfo.map {
                        providerCandidateReviews(from: $0, service: service)
                    } ?? [],
                    hasAnimeInfo: rawAnimeInfo != nil
                )
            }

            let bookSnapshots = books.map { item in
                LibraryBookSnapshot(
                    id: item.relativePath,
                    path: item.relativePath,
                    fileName: item.name,
                    fileExtension: item.url.pathExtension.lowercased(),
                    seriesID: service.relativePath(for: item.url.deletingLastPathComponent(), root: root),
                    isPackageBook: item.isDirectory,
                    modificationDate: item.modificationDate
                )
            }

            let videoFileSnapshots = videos.map { item in
                LibraryVideoSnapshot(
                    id: item.relativePath,
                    path: item.relativePath,
                    fileName: item.name,
                    fileExtension: item.url.pathExtension.lowercased(),
                    seriesID: service.relativePath(for: item.url.deletingLastPathComponent(), root: root),
                    modificationDate: item.modificationDate
                )
            }

            let fileTypeCounts = Dictionary(grouping: files) { item in
                LibraryInspection.fileTypeCountKey(for: item.url)
            }.mapValues(\.count)

            var notes: [String] = []
            switch mode {
            case .full:
                notes.append("Full inspect gathered all review clues in one pass.")
            case .lightInventory:
                notes.append("Light inventory gathered folder structure, file types, sidecars, and safety markers without waking every specialist.")
            case .epubClinicInventory:
                notes.append("Sable's Clinic inventory gathered EPUB files, paths, and local sidecars without opening EPUB internals.")
            case .stageDeepDive(let stage):
                notes.append("\(stage.title) specialists are active for this focused review pass.")
            case .quickVerify(_, _, let focusStage):
                if let focusStage {
                    notes.append("Post-apply refresh updated changed paths before waking \(focusStage.title) specialists.")
                } else {
                    notes.append("Post-apply refresh updated changed paths without waking every specialist.")
                }
            }
            notes.append(SableLibraryMLCompany.operatingNote(for: mode))
            notes.append(contentsOf: scanWarnings)
            notes.append("\(books.count) book file(s) found in \(seriesEntries.count) series group(s).")
            if !videos.isEmpty {
                notes.append("\(videos.count) video file(s) found in \(videoSeriesEntries.count) watching group(s).")
            }
            if !looseBooks.isEmpty {
                notes.append("\(looseBooks.count) loose book file(s) are directly inside the library root.")
            }
            if !looseVideos.isEmpty {
                notes.append("\(looseVideos.count) loose video file(s) are directly inside the library root.")
            }
            if packageBookCount > 0 {
                notes.append("\(packageBookCount) expanded EPUB package(s) can be repaired into normal EPUB files.")
            }
            if !missingComicInfoSeriesPaths.isEmpty {
                notes.append("\(missingComicInfoSeriesPaths.count) series group(s) do not have \(config.comicInfoFileName).")
            }
            if !missingAnimeInfoSeriesPaths.isEmpty {
                notes.append("\(missingAnimeInfoSeriesPaths.count) watching group(s) do not have \(config.animeInfoFileName).")
            }
            if !metadataCandidates.isEmpty {
                notes.append("\(metadataCandidates.count) possible source-note/tag term(s) found.")
            }
            if !missingNumberItems.isEmpty {
                notes.append("\(missingNumberItems.count) file(s) have a volume or chapter marker without a number.")
            }
            if !duplicateGroups.isEmpty {
                notes.append("\(duplicateGroups.count) exact duplicate group(s) need review.")
            }

            let verification = verificationResult(for: mode, root: root, packageBookCount: packageBookCount, service: service)
            service.reportProgress(progressMessage(for: mode, isFinishing: true))

            let inspection = LibraryInspection(
                inspectMode: mode,
                rootPath: root.standardizedFileURL.path(percentEncoded: false),
                fileCount: files.count,
                folderCount: folders.count,
                bookFileCount: books.count,
                videoFileCount: videos.count,
                packageBookCount: packageBookCount,
                seriesCount: seriesEntries.count,
                videoSeriesCount: videoSeriesEntries.count,
                looseFileCount: looseBooks.count + looseVideos.count,
                comicInfoCount: comicInfoFolders.count,
                animeInfoCount: animeInfoFolders.count,
                missingComicInfoCount: missingComicInfoSeriesPaths.count,
                missingAnimeInfoCount: missingAnimeInfoSeriesPaths.count,
                duplicateGroupCount: duplicateGroups.count,
                metadataCandidateCount: metadataCandidates.count,
                missingNumberCandidateCount: missingNumberItems.count,
                sourceMetadataTermKeys: metadataSummary.sourceTermKeys.sorted(),
                fileTypeCounts: fileTypeCounts,
                series: snapshots,
                books: bookSnapshots,
                videoSeries: videoSnapshots,
                videos: videoFileSnapshots,
                metadataCandidates: metadataCandidates.map {
                    LibraryInspectionMetadataCandidate(term: $0.term, count: $0.count, examples: $0.examples)
                },
                missingNumberCandidates: missingNumberItems.map {
                    LibraryInspectionPathIssue(path: $0.relativePath, note: "Volume or chapter marker is missing a number.")
                },
                duplicateCandidates: duplicateGroups.map {
                    LibraryInspectionDuplicateGroup(
                        fingerprint: $0.fingerprint,
                        kind: $0.kind.rawValue,
                        paths: $0.paths,
                        suggestedKeeperPath: $0.suggestedKeeperPath,
                        note: $0.note
                    )
                },
                comicInfoSeriesPaths: comicInfoSeriesPaths,
                missingComicInfoSeriesPaths: missingComicInfoSeriesPaths,
                animeInfoSeriesPaths: animeInfoSeriesPaths,
                missingAnimeInfoSeriesPaths: missingAnimeInfoSeriesPaths,
                notes: notes,
                verification: verification
            )
            return inspectionWithRootCatalog(inspection, root: root, config: config, service: service)
        } catch is CancellationError {
            return cancelledInspection(root: root, mode: mode)
        } catch {
            return failedInspection(root: root, mode: mode, error: error)
        }
    }

    private func inspectionWithRootCatalog(
        _ inspection: LibraryInspection,
        root: URL,
        config: SableLibraryConfig,
        service: SableLibraryService
    ) -> LibraryInspection {
        guard inspection.inspectMode == .lightInventory || inspection.inspectMode == .full else {
            return inspection
        }

        var updated = inspection
        do {
            let catalogURL = try service.writeRootLibraryCatalog(inspection: inspection, root: root, config: config)
            updated.notes.append("Root catalog updated: \(catalogURL.lastPathComponent).")
        } catch {
            updated.notes.append("Root catalog could not be updated: \(error.localizedDescription)")
        }
        return updated
    }

    private func lightInventoryInspection(
        root: URL,
        mode: LibraryPipelineInspectMode,
        items: [LibraryItem],
        fileCount: Int,
        folderCount: Int,
        scanWarnings: [String],
        options: LibraryPipelineOptions,
        config: SableLibraryConfig,
        service: SableLibraryService
    ) -> LibraryInspection {
        let matcher = SableLibraryFileTypeMatcher(config: config)
        let files = items.filter { !$0.isDirectory }
        let books = service.bookItems(
            in: items,
            root: root,
            config: config,
            cleanupOptions: options.cleanup
        )
        let videos = items.filter { matcher.isVideo(url: $0.url, isDirectory: $0.isDirectory) }
        let packageBookCount = books.filter(\.isDirectory).count
        let comicInfoFolderPaths = sidecarFolderPaths(
            named: config.comicInfoFileName,
            in: files
        )
        let animeInfoFolderPaths = sidecarFolderPaths(
            named: config.animeInfoFileName,
            in: files
        )
        let readingCoverage = sidecarCoverage(
            for: books,
            sidecarFolderPaths: comicInfoFolderPaths,
            root: root,
            service: service
        )
        let watchingCoverage = sidecarCoverage(
            for: videos,
            sidecarFolderPaths: animeInfoFolderPaths,
            root: root,
            service: service
        )
        let bookSnapshots = books.map { item in
            LibraryBookSnapshot(
                id: item.relativePath,
                path: item.relativePath,
                fileName: item.name,
                fileExtension: item.url.pathExtension.lowercased(),
                seriesID: service.relativePath(for: item.url.deletingLastPathComponent(), root: root),
                isPackageBook: item.isDirectory,
                modificationDate: item.modificationDate
            )
        }
        let videoSnapshots = videos.map { item in
            LibraryVideoSnapshot(
                id: item.relativePath,
                path: item.relativePath,
                fileName: item.name,
                fileExtension: item.url.pathExtension.lowercased(),
                seriesID: service.relativePath(for: item.url.deletingLastPathComponent(), root: root),
                modificationDate: item.modificationDate
            )
        }
        let looseBooks = books.filter { item in
            item.url.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL
        }
        let looseVideos = videos.filter { item in
            item.url.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL
        }
        let fileTypeCounts = Dictionary(grouping: files) { item in
            LibraryInspection.fileTypeCountKey(for: item.url)
        }.mapValues(\.count)

        var notes = [
            "Light inventory gathered counts, file types, sidecar coverage, and safety warnings without opening every ComicInfo file.",
            SableLibraryMLCompany.operatingNote(for: mode),
            "\(books.count) book file(s) found in \(readingCoverage.seriesPaths.count) reading group(s)."
        ]
        if !videos.isEmpty {
            notes.append("\(videos.count) video file(s) found in \(watchingCoverage.seriesPaths.count) watching group(s).")
        }
        if !looseBooks.isEmpty {
            notes.append("\(looseBooks.count) loose book file(s) are directly inside the library root.")
        }
        if !looseVideos.isEmpty {
            notes.append("\(looseVideos.count) loose video file(s) are directly inside the library root.")
        }
        if packageBookCount > 0 {
            notes.append("\(packageBookCount) expanded EPUB package(s) can be checked in Sable's Clinic.")
        }
        if !readingCoverage.missingSidecarSeriesPaths.isEmpty {
            notes.append("\(readingCoverage.missingSidecarSeriesPaths.count) reading group(s) do not have \(config.comicInfoFileName).")
        }
        if !watchingCoverage.missingSidecarSeriesPaths.isEmpty {
            notes.append("\(watchingCoverage.missingSidecarSeriesPaths.count) watching group(s) do not have \(config.animeInfoFileName).")
        }
        notes.append(contentsOf: scanWarnings)

        service.reportProgress(progressMessage(for: mode, isFinishing: true))

        return LibraryInspection(
            inspectMode: mode,
            rootPath: root.standardizedFileURL.path(percentEncoded: false),
            fileCount: fileCount,
            folderCount: folderCount,
            bookFileCount: books.count,
            videoFileCount: videos.count,
            packageBookCount: packageBookCount,
            seriesCount: readingCoverage.seriesPaths.count,
            videoSeriesCount: watchingCoverage.seriesPaths.count,
            looseFileCount: looseBooks.count + looseVideos.count,
            comicInfoCount: comicInfoFolderPaths.count,
            animeInfoCount: animeInfoFolderPaths.count,
            missingComicInfoCount: readingCoverage.missingSidecarSeriesPaths.count,
            missingAnimeInfoCount: watchingCoverage.missingSidecarSeriesPaths.count,
            duplicateGroupCount: 0,
            metadataCandidateCount: 0,
            missingNumberCandidateCount: 0,
            sourceMetadataTermKeys: [],
            fileTypeCounts: fileTypeCounts,
            series: [],
            books: bookSnapshots,
            videoSeries: [],
            videos: videoSnapshots,
            metadataCandidates: [],
            missingNumberCandidates: [],
            duplicateCandidates: [],
            comicInfoSeriesPaths: readingCoverage.sidecarSeriesPaths,
            missingComicInfoSeriesPaths: readingCoverage.missingSidecarSeriesPaths,
            animeInfoSeriesPaths: watchingCoverage.sidecarSeriesPaths,
            missingAnimeInfoSeriesPaths: watchingCoverage.missingSidecarSeriesPaths,
            notes: notes,
            verification: nil
        )
    }

    private func focusedEPUBClinicInspection(
        root: URL,
        mode: LibraryPipelineInspectMode,
        inventory: SableLibraryEPUBClinicInventory,
        service: SableLibraryService
    ) -> LibraryInspection {
        let changedPathKeys = mode.quickVerifyChangedPaths.map {
            Set($0.map(Self.normalizedLibraryPathForComparison))
        }
        let epubItems = inventory.items.filter { item in
            guard let changedPathKeys else { return true }
            return changedPathKeys.contains(Self.normalizedLibraryPathForComparison(item.relativePath))
        }
        let packageBookCount = epubItems.filter(\.isDirectory).count
        let bookSnapshots = epubItems.map { item in
            LibraryBookSnapshot(
                id: item.relativePath,
                path: item.relativePath,
                fileName: item.name,
                fileExtension: item.url.pathExtension.lowercased(),
                seriesID: service.relativePath(for: item.url.deletingLastPathComponent(), root: root),
                isPackageBook: item.isDirectory,
                modificationDate: item.modificationDate
            )
        }
        let fileTypeCounts = epubItems.isEmpty ? [:] : ["epub": epubItems.count]

        var notes = [
            "Sable's Clinic inventory gathered EPUB paths and local sidecar coverage without opening EPUB internals.",
            SableLibraryMLCompany.operatingNote(for: mode)
        ]
        notes.append(contentsOf: inventory.warnings)
        if let changedPathCount = mode.quickVerifyChangedPaths?.count {
            notes.append("Focused quick check limited Sable's Clinic to \(changedPathCount) changed path(s).")
        }
        notes.append("\(bookSnapshots.count) EPUB file(s) queued for Sable's Clinic review.")
        notes.append("\(inventory.comicInfoFolders.count) ComicInfo sidecar folder(s) matched \(inventory.epubCountWithComicInfo) EPUB file(s).")
        if inventory.epubCountWithAnimeInfo > 0 {
            notes.append("\(inventory.animeInfoFolders.count) AnimeInfo sidecar folder(s) matched \(inventory.epubCountWithAnimeInfo) EPUB file(s).")
        }
        if !inventory.missingComicInfoFolders.isEmpty {
            notes.append("\(inventory.missingComicInfoFolders.count) EPUB folder/group(s) need ComicInfo before metadata cleaning can be complete.")
        }
        if !inventory.invalidComicInfoPaths.isEmpty {
            notes.append("\(inventory.invalidComicInfoPaths.count) ComicInfo sidecar(s) could not be read as JSON.")
        }
        if !inventory.invalidAnimeInfoPaths.isEmpty {
            notes.append("\(inventory.invalidAnimeInfoPaths.count) AnimeInfo sidecar(s) could not be read as JSON.")
        }
        if packageBookCount > 0 {
            notes.append("\(packageBookCount) expanded EPUB package(s) can be repaired into normal EPUB files.")
        }

        let verification = verificationResult(
            for: mode,
            root: root,
            packageBookCount: packageBookCount,
            service: service
        )
        service.reportProgress(progressMessage(for: mode, isFinishing: true))

        return LibraryInspection(
            inspectMode: mode,
            rootPath: root.standardizedFileURL.path(percentEncoded: false),
            fileCount: inventory.fileCount,
            folderCount: inventory.folderCount,
            bookFileCount: bookSnapshots.count,
            videoFileCount: 0,
            packageBookCount: packageBookCount,
            seriesCount: Set(inventory.comicInfoFolders + inventory.missingComicInfoFolders).count,
            videoSeriesCount: 0,
            looseFileCount: 0,
            comicInfoCount: inventory.comicInfoFolders.count,
            animeInfoCount: inventory.animeInfoFolders.count,
            missingComicInfoCount: inventory.missingComicInfoFolders.count,
            missingAnimeInfoCount: 0,
            duplicateGroupCount: 0,
            metadataCandidateCount: 0,
            missingNumberCandidateCount: 0,
            sourceMetadataTermKeys: [],
            fileTypeCounts: fileTypeCounts,
            series: [],
            books: bookSnapshots,
            videoSeries: [],
            videos: [],
            metadataCandidates: [],
            missingNumberCandidates: [],
            duplicateCandidates: [],
            comicInfoSeriesPaths: inventory.comicInfoFolders,
            missingComicInfoSeriesPaths: inventory.missingComicInfoFolders,
            animeInfoSeriesPaths: inventory.animeInfoFolders,
            missingAnimeInfoSeriesPaths: [],
            notes: notes,
            verification: verification
        )
    }

    private func sidecarFolderPaths(
        named sidecarName: String,
        in files: [LibraryItem]
    ) -> Set<String> {
        Set(files
            .filter { $0.name == sidecarName }
            .map { $0.url.deletingLastPathComponent().standardizedFileURL.path(percentEncoded: false) })
    }

    private func sidecarCoverage(
        for items: [LibraryItem],
        sidecarFolderPaths: Set<String>,
        root: URL,
        service: SableLibraryService
    ) -> (
        seriesPaths: [String],
        sidecarSeriesPaths: [String],
        missingSidecarSeriesPaths: [String]
    ) {
        var seriesPaths = Set<String>()
        var sidecarSeriesPaths = Set<String>()
        var missingSidecarSeriesPaths = Set<String>()

        for item in items {
            let parent = item.url.deletingLastPathComponent()
            if let sidecarFolderPath = nearestSidecarFolderPath(
                from: parent,
                root: root,
                sidecarFolderPaths: sidecarFolderPaths
            ) {
                let relativePath = service.relativePath(
                    for: URL(fileURLWithPath: sidecarFolderPath, isDirectory: true),
                    root: root
                )
                seriesPaths.insert(relativePath)
                sidecarSeriesPaths.insert(relativePath)
            } else {
                let relativePath = lightInventorySeriesPath(for: item, root: root, service: service)
                seriesPaths.insert(relativePath)
                missingSidecarSeriesPaths.insert(relativePath)
            }
        }

        for sidecarFolderPath in sidecarFolderPaths {
            let relativePath = service.relativePath(
                for: URL(fileURLWithPath: sidecarFolderPath, isDirectory: true),
                root: root
            )
            seriesPaths.insert(relativePath)
            sidecarSeriesPaths.insert(relativePath)
        }

        return (
            seriesPaths: seriesPaths.sorted(),
            sidecarSeriesPaths: sidecarSeriesPaths.sorted(),
            missingSidecarSeriesPaths: missingSidecarSeriesPaths.sorted()
        )
    }

    private func nearestSidecarFolderPath(
        from folder: URL,
        root: URL,
        sidecarFolderPaths: Set<String>
    ) -> String? {
        let rootURL = root.standardizedFileURL
        let rootPath = rootURL.path(percentEncoded: false)
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        var current = folder.standardizedFileURL

        while true {
            let currentPath = current.path(percentEncoded: false)
            guard currentPath == rootPath || currentPath.hasPrefix(rootPrefix) else {
                return nil
            }
            if sidecarFolderPaths.contains(currentPath) {
                return currentPath
            }
            guard currentPath != rootPath else { return nil }
            current = current.deletingLastPathComponent().standardizedFileURL
        }
    }

    private func lightInventorySeriesPath(
        for item: LibraryItem,
        root: URL,
        service: SableLibraryService
    ) -> String {
        let parent = item.url.deletingLastPathComponent().standardizedFileURL
        if parent == root.standardizedFileURL {
            return item.url.deletingPathExtension().lastPathComponent
        }
        return service.relativePath(for: parent, root: root)
    }

    private func cancelledInspection(root: URL, mode: LibraryPipelineInspectMode) -> LibraryInspection {
        var inspection = LibraryInspection.empty(root: root)
        inspection.inspectMode = mode
        inspection.notes = ["Inspection stopped safely before preparing a plan."]
        return inspection
    }

    private func failedInspection(root: URL, mode: LibraryPipelineInspectMode, error: Error) -> LibraryInspection {
        var inspection = LibraryInspection.empty(root: root)
        inspection.inspectMode = mode
        inspection.notes = ["Inspection could not finish: \(error.localizedDescription)"]
        return inspection
    }

    private func progressMessage(for mode: LibraryPipelineInspectMode, isFinishing: Bool) -> String {
        switch (mode, isFinishing) {
        case (.full, false):
            return "Inspect library: reading collection contents"
        case (.full, true):
            return "Inspect library: prepared read-only collection notes"
        case (.lightInventory, false):
            return "Light inventory: mapping folders, sidecars, and file types"
        case (.lightInventory, true):
            return "Light inventory: prepared shared evidence map"
        case (.epubClinicInventory, false):
            return "Sable's Clinic: listing EPUB files and checking sidecars"
        case (.epubClinicInventory, true):
            return "Sable's Clinic: prepared EPUB and sidecar inventory"
        case (.stageDeepDive(let stage), false) where stage == .epubClinic:
            return "Sable's Clinic: mapping EPUB files"
        case (.stageDeepDive(let stage), true) where stage == .epubClinic:
            return "Sable's Clinic: prepared EPUB-only review facts"
        case (.quickVerify(let previousStage, _, let focusStage), false) where previousStage == .epubClinic || focusStage == .epubClinic:
            return "Sable's Clinic: checking changed EPUB files"
        case (.quickVerify(let previousStage, _, let focusStage), true) where previousStage == .epubClinic || focusStage == .epubClinic:
            return "Sable's Clinic: refreshed changed EPUB facts"
        case (.stageDeepDive(let stage), false):
            return "\(stage.title): waking focused specialists"
        case (.stageDeepDive(let stage), true):
            return "\(stage.title): prepared focused review facts"
        case (.quickVerify, false):
            return "Quick check: verifying recent changes"
        case (.quickVerify, true):
            return "Quick check: refreshed affected library facts"
        }
    }

    nonisolated private static func normalizedLibraryPathForComparison(_ path: String) -> String {
        path
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/", omittingEmptySubsequences: true)
            .joined(separator: "/")
    }

    private func verificationResult(
        for mode: LibraryPipelineInspectMode,
        root: URL,
        packageBookCount: Int,
        service: SableLibraryService
    ) -> LibraryPipelineVerification? {
        guard case let .quickVerify(previousStage, changedPaths, _) = mode else { return nil }

        let missing = changedPaths.filter { path in
            let url = root.appendingPathComponent(path)
            return !service.fileManager.fileExists(atPath: url.path(percentEncoded: false))
        }
        let pathMessage: String
        if missing.isEmpty {
            pathMessage = "Checked \(changedPaths.count) changed path(s) from \(previousStage.title)."
        } else {
            pathMessage = "\(missing.count) changed path(s) from \(previousStage.title) need attention."
        }

        let didCheckEpubPackages = !previousStage.usesComicInfoApplyEngine
        let packageMessage: String?
        if didCheckEpubPackages {
            packageMessage = packageBookCount == 0
                ? "No expanded EPUB packages remain."
                : "\(packageBookCount) expanded EPUB package(s) are still waiting to be repackaged."
        } else {
            packageMessage = nil
        }
        let message = [pathMessage, packageMessage].compactMap { $0 }.joined(separator: " ")

        return LibraryPipelineVerification(
            previousStage: previousStage,
            checkedPathCount: changedPaths.count,
            missingPathCount: missing.count,
            changedPathCount: changedPaths.count,
            didCheckEpubPackages: didCheckEpubPackages,
            remainingEpubPackageCount: didCheckEpubPackages ? packageBookCount : 0,
            message: message
        )
    }

    private func readComicInfo(
        folder: URL,
        config: SableLibraryConfig,
        service: SableLibraryService
    ) -> [String: Any]? {
        let url = folder.appendingPathComponent(config.comicInfoFileName)
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return nil
        }
        return dictionary
    }

    private func missingMangaBakaV2Metadata(in sidecar: [String: Any], service: SableLibraryService) -> Bool {
        let ids = SableLibrarySourceIDParser.sourceIDs(from: sidecar) { service.textValue($0) }
        guard ids.contains(where: { $0.provider == .mangabaka }) else {
            return false
        }
        guard let sable = sidecar["_sable"] as? [String: Any],
              let mangaBaka = sable["mangabaka"] as? [String: Any] else {
            return true
        }
        return !["titles_v2", "tags_v2", "links_v2", "publishers_v2", "genres_v2"].contains { key in
            providerMetadataValueIsPresent(mangaBaka[key])
        }
    }

    private func providerMetadataValueIsPresent(_ value: Any?) -> Bool {
        switch value {
        case let rows as [[String: Any]]:
            return !rows.isEmpty
        case let strings as [String]:
            return !strings.isEmpty
        case let string as String:
            return !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default:
            return false
        }
    }

    private func sidecarShelfDescription(
        from sidecar: [String: Any],
        service: SableLibraryService
    ) -> String? {
        let bookDescription = sidecar["book_description"] as? [String: Any]
        let candidates: [Any?] = [
            sidecar["description"],
            sidecar["summary"],
            sidecar["synopsis"],
            bookDescription?["description"]
        ]
        return candidates.compactMap { service.textValue($0) }.first
    }

    private func sidecarShelfValues(
        from sidecar: [String: Any],
        keys: [String],
        service: SableLibraryService
    ) -> [String] {
        var values: [String] = []
        for key in keys {
            for value in sidecarShelfStrings(sidecar[key], service: service) {
                service.addUnique(value, to: &values)
            }
        }
        return values
    }

    private func providerV2ShelfNames(
        in sidecar: [String: Any],
        provider: SableLibraryMetadataProvider,
        keys: [String],
        includeGenres: Bool,
        service: SableLibraryService
    ) -> [String] {
        guard let sable = sidecar["_sable"] as? [String: Any],
              let providerPayload = sable[provider.rawValue] as? [String: Any] else {
            return []
        }

        var values: [String] = []
        for key in keys {
            guard let rows = providerPayload[key] as? [[String: Any]] else { continue }
            let keySuggestsGenres = key.localizedCaseInsensitiveContains("genre")
            for row in rows {
                if (row["is_spoiler"] as? Bool) == true {
                    continue
                }
                let isGenre = row["is_genre"] as? Bool
                if includeGenres {
                    guard keySuggestsGenres || isGenre == true else { continue }
                } else if isGenre == true {
                    continue
                }
                service.addUnique(service.textValue(row["name"]), to: &values)
            }
        }
        return values
    }

    private func providerV2ShelfTagRecords(
        in sidecar: [String: Any],
        provider: SableLibraryMetadataProvider,
        service: SableLibraryService
    ) -> [SableLibraryShelfTagRecord] {
        guard let sable = sidecar["_sable"] as? [String: Any],
              let providerPayload = sable[provider.rawValue] as? [String: Any] else {
            return []
        }

        var records: [SableLibraryShelfTagRecord] = []
        var seen: Set<String> = []
        for key in ["genres_v2", "tags_v2"] {
            guard let rows = providerPayload[key] as? [[String: Any]] else { continue }
            let keySuggestsGenre = key.localizedCaseInsensitiveContains("genre")
            for row in rows {
                guard (row["is_spoiler"] as? Bool) != true,
                      let name = service.textValue(row["name"]) else {
                    continue
                }
                let path = service.textValue(row["name_path"])
                let normalizedKey = [
                    name,
                    path ?? "",
                    provider.rawValue
                ].map {
                    $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                        .lowercased()
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }.joined(separator: "|")
                guard seen.insert(normalizedKey).inserted else { continue }
                records.append(
                    SableLibraryShelfTagRecord(
                        name: name,
                        path: path,
                        providerWeight: service.textValue(row["weight"]),
                        isGenre: (row["is_genre"] as? Bool) ?? keySuggestsGenre,
                        isSpoiler: row["is_spoiler"] as? Bool,
                        isExplicit: row["is_explicit"] as? Bool,
                        contentRating: service.textValue(row["content_rating"]),
                        provider: provider.rawValue
                    )
                )
            }
        }
        return records
    }

    private func providerNeighborSignals(
        in sidecar: [String: Any],
        provider: SableLibraryMetadataProvider,
        service: SableLibraryService
    ) -> [String] {
        guard let sable = sidecar["_sable"] as? [String: Any],
              let providerPayload = sable[provider.rawValue] as? [String: Any] else {
            return []
        }

        var signals: [String] = []
        for key in ["recommendation_neighbors", "recommendations_v2", "recommendations", "similar_v2", "similar_series", "similar"] {
            guard let rows = providerPayload[key] as? [[String: Any]] else { continue }
            for row in rows {
                for field in ["genres", "genre", "themes", "theme", "tags", "tag", "category", "categories", "reason", "reasons"] {
                    for value in providerNeighborSignalValues(row[field], service: service) {
                        service.addUnique(value, to: &signals)
                    }
                }
            }
        }
        return signals
    }

    private func providerNeighborSignalValues(_ value: Any?, service: SableLibraryService) -> [String] {
        if let text = service.textValue(value) {
            return [text]
        }

        if let row = value as? [String: Any] {
            var values: [String] = []
            for key in ["name", "name_path", "genre", "theme", "tag", "category", "reason"] {
                for value in providerNeighborSignalValues(row[key], service: service) {
                    service.addUnique(value, to: &values)
                }
            }
            return values
        }

        if let values = value as? [Any] {
            var result: [String] = []
            for value in values {
                for signal in providerNeighborSignalValues(value, service: service) {
                    service.addUnique(signal, to: &result)
                }
            }
            return result
        }

        return []
    }

    private func ranobeDBShelfNames(
        in sidecar: [String: Any],
        includeGenres: Bool,
        service: SableLibraryService
    ) -> [String] {
        var values: [String] = []
        for row in ranobeDBSeriesTags(in: sidecar) {
            let type = service.textValue(row["ttype"])?.lowercased() ?? ""
            let isGenre = type == "genre"
            guard includeGenres == isGenre else { continue }
            service.addUnique(service.textValue(row["name"]), to: &values)
        }
        return values
    }

    private func ranobeDBShelfTagRecords(
        in sidecar: [String: Any],
        service: SableLibraryService
    ) -> [SableLibraryShelfTagRecord] {
        var records: [SableLibraryShelfTagRecord] = []
        var seen: Set<String> = []
        for row in ranobeDBSeriesTags(in: sidecar) {
            guard let name = service.textValue(row["name"]) else { continue }
            let type = service.textValue(row["ttype"])?.lowercased() ?? "tag"
            let normalizedKey = "\(name.lowercased())|\(type)"
            guard seen.insert(normalizedKey).inserted else { continue }
            let weight: String
            switch type {
            case "genre":
                weight = "core"
            case "tag":
                weight = "recurrent"
            default:
                weight = "incidental"
            }
            records.append(
                SableLibraryShelfTagRecord(
                    name: name,
                    path: type,
                    providerWeight: weight,
                    isGenre: type == "genre",
                    provider: SableLibraryMetadataProvider.ranobedb.rawValue
                )
            )
        }
        return records
    }

    private func ranobeDBSeriesTags(in sidecar: [String: Any]) -> [[String: Any]] {
        guard let sable = sidecar["_sable"] as? [String: Any],
              let ranobeDB = sable[SableLibraryMetadataProvider.ranobedb.rawValue] as? [String: Any],
              let compact = ranobeDB["api_compact"] as? [String: Any],
              let series = compact["series"] as? [String: Any],
              let tags = series["tags"] as? [[String: Any]] else {
            return []
        }
        return tags
    }

    private func ranobeDBVolumeDescriptions(
        in sidecar: [String: Any],
        service: SableLibraryService
    ) -> [String] {
        guard let sable = sidecar["_sable"] as? [String: Any],
              let ranobeDB = sable[SableLibraryMetadataProvider.ranobedb.rawValue] as? [String: Any],
              let compact = ranobeDB["api_compact"] as? [String: Any],
              let bookResponses = compact["book_responses"] as? [[String: Any]] else {
            return []
        }
        var descriptions: [String] = []
        for response in bookResponses {
            let payload = response["response"] as? [String: Any]
            let book = payload?["book"] as? [String: Any]
            service.addUnique(service.textValue(book?["description"]), to: &descriptions)
        }
        return descriptions
    }

    private func trustedProviderTitles(
        from sidecar: [String: Any],
        service: SableLibraryService
    ) -> [String] {
        var titles: [String] = []

        func add(_ value: Any?) {
            service.addUnique(service.textValue(value), to: &titles)
        }

        func addRows(_ value: Any?) {
            guard let rows = value as? [[String: Any]] else { return }
            for row in rows {
                for key in ["title", "name", "english", "romaji", "romanized", "native"] {
                    add(row[key])
                }
            }
        }

        guard let sable = sidecar["_sable"] as? [String: Any] else {
            return []
        }

        if let titleSource = sable["title_source"] as? [String: Any],
           service.textValue(titleSource["provider"]) != nil {
            add(titleSource["title"])
        }

        if let mangaBaka = sable[SableLibraryMetadataProvider.mangabaka.rawValue] as? [String: Any] {
            addRows(mangaBaka["titles_v2"])
        }

        if let ranobeDB = sable[SableLibraryMetadataProvider.ranobedb.rawValue] as? [String: Any],
           let compact = ranobeDB["api_compact"] as? [String: Any] ?? ranobeDB["api"] as? [String: Any],
           let series = compact["series"] as? [String: Any] {
            add(series["title"])
            for alias in series["aliases"] as? [Any] ?? [] {
                add(alias)
            }
            addRows(series["titles"])
        }

        return titles
    }

    private func sidecarShelfStrings(_ value: Any?, service: SableLibraryService) -> [String] {
        if let value = service.textValue(value) {
            return [value]
        }
        if let values = value as? [Any] {
            return values.flatMap { sidecarShelfStrings($0, service: service) }
        }
        if let dictionary = value as? [String: Any] {
            return ["name", "title", "label", "value"]
                .compactMap { service.textValue(dictionary[$0]) }
        }
        return []
    }

    private func readAnimeInfo(
        folder: URL,
        config: SableLibraryConfig
    ) -> [String: Any]? {
        let url = folder.appendingPathComponent(config.animeInfoFileName)
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return nil
        }
        return dictionary
    }

    private func year(from sidecar: [String: Any], service: SableLibraryService) -> Int? {
        if let year = sidecar["year"] as? Int {
            return year
        }
        guard let value = service.textValue(sidecar["year"]) else { return nil }
        return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func preferredSidecarTitle(
        from sidecar: [String: Any],
        preference: SableLibraryPreferredTitleStyle,
        service: SableLibraryService
    ) -> String? {
        let titles = sidecarTitleBuckets(from: sidecar, service: service)
        let fallbackTitle = service.textValue(sidecar["preferred_title"])
            ?? service.textValue(sidecar["title"])
            ?? service.textValue(sidecar["local_title"])

        let preferredOrder: [SableLibraryPreferredTitleStyle]
        switch preference {
        case .english:
            preferredOrder = [.english, .romaji, .native]
        case .romaji:
            preferredOrder = [.romaji, .english, .native]
        case .native:
            preferredOrder = [.native, .romaji, .english]
        }

        for style in preferredOrder {
            if let title = titles[style]?.first {
                return title
            }
        }
        return fallbackTitle
    }

    private func sidecarTitleBuckets(
        from sidecar: [String: Any],
        service: SableLibraryService
    ) -> [SableLibraryPreferredTitleStyle: [String]] {
        var result: [SableLibraryPreferredTitleStyle: [String]] = [:]

        func add(_ value: String?, to style: SableLibraryPreferredTitleStyle) {
            guard let value else { return }
            var bucket = result[style] ?? []
            service.addUnique(value, to: &bucket)
            result[style] = bucket
        }

        func addValues(_ values: [String], to style: SableLibraryPreferredTitleStyle) {
            for value in values {
                add(value, to: style)
            }
        }

        for key in ["english_title", "english"] {
            add(service.textValue(sidecar[key]), to: .english)
        }
        for key in ["romanized_title", "romaji_title", "romanized", "romaji"] {
            add(service.textValue(sidecar[key]), to: .romaji)
        }
        for key in ["native_title", "native", "japanese_title", "korean_title", "chinese_title"] {
            add(service.textValue(sidecar[key]), to: .native)
        }

        for key in ["preferred_title", "title", "local_title", "sort_title"] {
            guard let value = service.textValue(sidecar[key]) else { continue }
            add(value, to: containsNativeEastAsianScript(value) ? .native : .english)
        }

        if let variants = sidecar["title_variants"] as? [String: Any] {
            for (key, value) in variants {
                guard let style = normalizedTitleStyleKey(key) else { continue }
                addValues(titleVariantStrings(value, service: service), to: style)
            }
        }

        return result
    }

    private func normalizedTitleStyleKey(_ key: String) -> SableLibraryPreferredTitleStyle? {
        switch key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "english", "en":
            return .english
        case "romaji", "romanized", "romanised":
            return .romaji
        case "native",
             "japanese", "ja", "kanji", "kana",
             "korean", "ko", "hangul",
             "chinese", "zh", "zh-cn", "zh-hans", "zh-hant", "cn", "hanzi":
            return .native
        default:
            return nil
        }
    }

    private func titleVariantStrings(_ value: Any?, service: SableLibraryService) -> [String] {
        if let value = service.textValue(value) {
            return isSeriesLevelTitleVariant(value) ? [value] : []
        }
        if let values = value as? [Any] {
            return values.compactMap { value in
                guard let title = service.textValue(value),
                      isSeriesLevelTitleVariant(title) else {
                    return nil
                }
                return title
            }
        }
        return []
    }

    private func isSeriesLevelTitleVariant(_ value: String) -> Bool {
        value.range(
            of: #"(?i)(?:^|[\s,;:–—-])(?:vol(?:ume)?|book|ch(?:apter)?|v)\.?\s*\d{1,4}(?:\.\d+)?(?:\s*[-–—:]\s*.*)?(?:\s*\([^)]*\))?\s*$"#,
            options: .regularExpression
        ) == nil
    }

    private func containsNativeEastAsianScript(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3040...0x30FF,
                 0x3400...0x9FFF,
                 0xF900...0xFAFF,
                 0xAC00...0xD7AF:
                return true
            default:
                return false
            }
        }
    }

    private func primarySourceID(
        from sidecar: [String: Any],
        domain: SableLibraryMediaDomain,
        extraIDs: [SableLibrarySourceID] = [],
        service: SableLibraryService
    ) -> SableLibrarySourceID? {
        if domain == .reading,
           let value = service.textValue(sidecar["mangabaka_id"]) {
            return SableLibrarySourceID(provider: .mangabaka, value: value)
        }

        let preferredProviderOrder: [SableLibraryMetadataProvider] = domain == .watching
            ? [.tmdb, .tvdb, .imdb]
            : [.ranobedb, .mangabaka, .anilist, .openLibrary]

        let ids = SableLibrarySourceIDParser.sourceIDs(from: sidecar, extraIDs: extraIDs) { service.textValue($0) }
        let preferredID = preferredProviderOrder.compactMap { provider in
            ids.first { $0.provider == provider }
        }.first
        return domain == .watching ? preferredID : preferredID ?? ids.first
    }

    private func identityGraph(
        from sidecar: [String: Any],
        domain: SableLibraryMediaDomain,
        fallbackTitle: String,
        extraIDs: [SableLibrarySourceID] = [],
        service: SableLibraryService
    ) -> SableLibraryIdentityGraph {
        let preferredTitle = service.textValue(sidecar["preferred_title"])
            ?? service.textValue(sidecar["title"])
            ?? fallbackTitle
        var aliases = sidecar["aliases"] as? [String] ?? []
        for title in sidecarTitleBuckets(from: sidecar, service: service).values.flatMap({ $0 })
        where isSeriesLevelTitleVariant(title) {
            service.addUnique(title, to: &aliases)
        }
        let sourceIDs = SableLibrarySourceIDParser.sourceIDs(from: sidecar, extraIDs: extraIDs) { service.textValue($0) }
        let isbn13 = (sidecar["isbn13"] as? [String]) ?? service.textValue(sidecar["isbn13"]).map { [$0] } ?? []
        let readingType = domain == .reading
            ? readingType(from: service.textValue(sidecar["type"]))
            : nil
        let watchingType = domain == .watching
            ? watchingType(from: service.textValue(sidecar["type"]))
            : nil
        let freshness = sourceFreshness(from: sidecar, service: service)

        return SableLibraryIdentityGraph(
            domain: domain,
            preferredTitle: preferredTitle,
            sortTitle: service.textValue(sidecar["sort_title"]),
            year: year(from: sidecar, service: service),
            readingType: readingType,
            watchingType: watchingType,
            sourceIDs: sourceIDs,
            isbn13: isbn13,
            aliases: aliases,
            evidence: [],
            freshness: freshness
        )
    }

    private func sourceFreshness(from sidecar: [String: Any], service: SableLibraryService) -> [SableLibraryProviderFreshness] {
        guard let rows = sidecar["source_freshness"] as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            guard let providerName = service.textValue(row["provider"]),
                  let provider = SableLibrarySourceIDParser.provider(from: providerName),
                  let fetchedAt = service.textValue(row["fetched_at"]),
                  let ttlSeconds = timeIntervalValue(row["ttl_seconds"], service: service) else {
                return nil
            }
            return SableLibraryProviderFreshness(
                provider: provider,
                fetchedAt: fetchedAt,
                ttlSeconds: ttlSeconds
            )
        }
    }

    private func localFileSnapshotChanged(
        sidecar: [String: Any]?,
        snapshotKey: String,
        signatureKey: String,
        localItems: [LibraryItem],
        service: SableLibraryService
    ) -> Bool {
        guard let sidecar,
              let sable = sidecar["_sable"] as? [String: Any],
              let snapshot = sable[snapshotKey] as? [String: Any] else {
            return !localItems.isEmpty
        }

        let storedCount = integerValue(snapshot["file_count"], service: service)
        let storedSignature = service.textValue(snapshot[signatureKey])
        let currentSignature = service.localFileSnapshotSignature(items: localItems)
        return storedCount != localItems.count || storedSignature != currentSignature
    }

    private func integerValue(_ value: Any?, service: SableLibraryService) -> Int? {
        if let integer = value as? Int {
            return integer
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        guard let text = service.textValue(value) else { return nil }
        return Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func timeIntervalValue(_ value: Any?, service: SableLibraryService) -> TimeInterval? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let double = value as? Double {
            return double
        }
        guard let string = service.textValue(value) else { return nil }
        return TimeInterval(string.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func preferredReadingSourceID(from ids: [SableLibrarySourceID]) -> SableLibrarySourceID? {
        let order: [SableLibraryMetadataProvider] = [.ranobedb, .mangabaka, .anilist, .openLibrary]
        return order.compactMap { provider in
            ids.first { $0.provider == provider }
        }.first ?? ids.first
    }

    private func folderIdentityGraph(
        folderName: String,
        domain: SableLibraryMediaDomain,
        sourceIDs: [SableLibrarySourceID],
        service: SableLibraryService
    ) -> SableLibraryIdentityGraph? {
        guard !sourceIDs.isEmpty else { return nil }

        let title = folderTitleForIdentity(folderName, service: service)
        return SableLibraryIdentityGraph(
            domain: domain,
            preferredTitle: title,
            sortTitle: nil,
            year: folderYearHint(in: folderName),
            readingType: domain == .reading ? .unknown : nil,
            watchingType: domain == .watching ? .unknownVideo : nil,
            sourceIDs: sourceIDs,
            isbn13: [],
            aliases: [],
            evidence: [],
            freshness: []
        )
    }

    private func folderTitleForIdentity(_ folderName: String, service: SableLibraryService) -> String {
        let stripped = folderName
            .replacingOccurrences(of: #"\s*\{[A-Za-z_]+-[^}]+\}\s*"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s*\(\d{4}\)\s*$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return service.cleanSeriesTitle(stripped.isEmpty ? folderName : stripped)
    }

    private func folderYearHint(in folderName: String) -> Int? {
        var scanEnd = folderName.endIndex
        while let tokenRange = trailingCurlyTokenRange(in: folderName, before: scanEnd) {
            scanEnd = tokenRange.lowerBound
        }

        var contentEnd = scanEnd
        while contentEnd > folderName.startIndex {
            let previous = folderName.index(before: contentEnd)
            guard folderName[previous].isWhitespace else { break }
            contentEnd = previous
        }
        guard contentEnd > folderName.startIndex else { return nil }

        let closeIndex = folderName.index(before: contentEnd)
        guard folderName[closeIndex] == ")",
              let openIndex = folderName[..<closeIndex].lastIndex(of: "(") else {
            return nil
        }

        let yearStart = folderName.index(after: openIndex)
        let yearText = folderName[yearStart..<closeIndex]
        guard yearText.count == 4,
              yearText.allSatisfy(\.isNumber) else {
            return nil
        }
        return Int(yearText)
    }

    private func trailingCurlyTokenRange(
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
        guard value[closeIndex] == "}",
              let openIndex = value[..<closeIndex].lastIndex(of: "{"),
              !value[value.index(after: openIndex)..<closeIndex].isEmpty else {
            return nil
        }

        var fullStart = openIndex
        while fullStart > value.startIndex {
            let previous = value.index(before: fullStart)
            guard value[previous].isWhitespace else { break }
            fullStart = previous
        }
        return fullStart..<end
    }

    private func sidecarFromFolderSourceIDs(
        folderName: String,
        sourceIDs: [SableLibrarySourceID],
        service: SableLibraryService
    ) -> [String: Any] {
        var sidecar: [String: Any] = [
            "title": folderTitleWithoutSourceTokens(folderName, service: service),
            "preferred_title": folderTitleWithoutSourceTokens(folderName, service: service),
            "ids": [:]
        ]
        sidecar = sidecarByAddingSourceIDs(sidecar, sourceIDs: sourceIDs)
        return sidecar
    }

    private func sidecarByAddingSourceIDs(
        _ sidecar: [String: Any],
        sourceIDs: [SableLibrarySourceID]
    ) -> [String: Any] {
        guard !sourceIDs.isEmpty else { return sidecar }

        var sidecar = sidecar
        var ids = sidecar["ids"] as? [String: Any] ?? [:]

        for sourceID in sourceIDs {
            ids[idKey(for: sourceID.provider)] = sourceID.value
        }

        sidecar["ids"] = ids
        return sidecar
    }

    private func unavailableMetadataProviders(
        from sidecar: [String: Any],
        service: SableLibraryService
    ) -> [SableLibraryMetadataProvider] {
        guard let sable = sidecar["_sable"] as? [String: Any],
              let availability = sable["provider_availability"] as? [String: Any] else {
            return []
        }

        return availability.compactMap { key, value in
            guard let provider = SableLibraryMetadataProvider(rawValue: key) else {
                return nil
            }

            let status: String?
            if let dictionary = value as? [String: Any] {
                status = service.textValue(dictionary["status"])
            } else {
                status = service.textValue(value)
            }

            return status == "not_available" ? provider : nil
        }
    }

    private func providerCandidateReviews(
        from sidecar: [String: Any],
        service: SableLibraryService
    ) -> [SableLibraryProviderCandidateReview] {
        guard let sable = sidecar["_sable"] as? [String: Any],
              let reviews = sable["provider_candidate_review"] as? [String: Any] else {
            return []
        }

        return reviews.compactMap { key, value in
            guard let provider = SableLibraryMetadataProvider(rawValue: key),
                  let dictionary = value as? [String: Any],
                  let rawStatus = service.textValue(dictionary["status"]),
                  let status = SableLibraryProviderCandidateReview.Status(rawValue: rawStatus) else {
                return nil
            }

            let sourceID = (
                service.textValue(dictionary["candidate_id"])
                    ?? service.textValue(dictionary["rejected_candidate_id"])
            ).map {
                SableLibrarySourceID(provider: provider, value: $0)
            }
            return SableLibraryProviderCandidateReview(
                provider: provider,
                status: status,
                confidenceScore: doubleValue(dictionary["confidence_score"]) ?? 0,
                title: service.textValue(dictionary["candidate_title"])
                    ?? service.textValue(dictionary["rejected_candidate_title"]),
                year: intValue(dictionary["candidate_year"]),
                mediaType: service.textValue(dictionary["candidate_media_type"]),
                sourceID: sourceID,
                checkedAt: service.textValue(dictionary["updated_at"]),
                schemaVersion: intValue(dictionary["schema_version"]) ?? 0
            )
        }
    }

    private func intValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber {
            return number.intValue
        }
        guard let text = serviceTextValue(value) else { return nil }
        return Int(text)
    }

    private func doubleValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        guard let text = serviceTextValue(value) else { return nil }
        return Double(text)
    }

    private func serviceTextValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    private func folderTitleWithoutSourceTokens(_ folderName: String, service: SableLibraryService) -> String {
        let stripped = folderName
            .replacingOccurrences(of: #"\s*\{[A-Za-z_]+-[^}]+\}\s*"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s*\(\d{4}\)\s*$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return service.cleanSeriesTitle(stripped.isEmpty ? folderName : stripped)
    }

    private func idKey(for provider: SableLibraryMetadataProvider) -> String {
        switch provider {
        case .mangabaka:
            "mangabaka"
        case .ranobedb:
            "ranobedb"
        case .openLibrary:
            "openlibrary"
        case .myAnimeList:
            "mal"
        case .anilist:
            "anilist"
        case .tvmaze:
            "tvmaze"
        case .wikidata:
            "wikidata"
        case .tmdb:
            "tmdb"
        case .tvdb:
            "tvdb"
        case .imdb:
            "imdb"
        case .local:
            "local"
        }
    }

    private func readingType(from rawValue: String?) -> SableLibraryReadingType {
        switch rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "manga": .manga
        case "manhwa": .manhwa
        case "manhua": .manhua
        case "oel", "original english language": .oel
        case "light novel", "lightnovel": .lightNovel
        case "novel": .novel
        case "book": .book
        case "comic", "comics": .comic
        default: .unknown
        }
    }

    private func watchingType(from rawValue: String?) -> SableLibraryWatchingType {
        switch rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "anime tv", "animetv", "tv_anime": .animeTV
        case "anime movie", "animemovie": .animeMovie
        case "ova": .ova
        case "ona": .ona
        case "special", "specials": .special
        case "movie": .movie
        case "tv", "tv show", "tvshow": .tvShow
        default: .unknownVideo
        }
    }

    private func finalVolume(from comicInfo: [String: Any], service: SableLibraryService) -> Int? {
        guard let value = service.textValue(comicInfo["final_volume"]) else { return nil }
        return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func localHighestVolume(
        in books: [LibraryItem],
        config: SableLibraryConfig,
        service: SableLibraryService
    ) -> Int? {
        books.compactMap { item in
            let rawName = item.url.deletingPathExtension().lastPathComponent
            let cleaned = service.cleanedTitle(rawName, config: config)
            guard let suffix = service.volumeOrChapterSuffix(in: cleaned) else { return nil }
            return service.volumeNumber(in: suffix)
        }.max()
    }
}
