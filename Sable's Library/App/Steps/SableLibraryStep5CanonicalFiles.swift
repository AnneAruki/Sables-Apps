//
//  SableLibraryStep5CanonicalFiles.swift
//  Sable's Library
//

import Foundation

nonisolated struct SableLibraryStep5CanonicalFiles: Sendable {
    var namingPolicy = SableLibraryNamingPolicy()
    private let maximumFileNameUTF8Bytes = 240

    func prepare(context: LibraryPipelineContext, service: SableLibraryService) async -> [LibraryPlanGroup] {
        service.reportProgress("Preparing file name plan")
        guard context.options.cleanup.renameFiles,
              context.options.stages.useComicInfoTitles,
              let inspection = context.inspection else {
            return []
        }

        let startedAt = Date()
        let config = service.currentConfig()
        let seriesByPath = inspection.series.reduce(into: [String: LibrarySeriesSnapshot]()) { partialResult, series in
            partialResult[series.path] = series
        }
        let videoSeriesByDepth = inspection.videoSeries
            .filter(\.hasAnimeInfo)
            .sorted { lhs, rhs in
                lhs.path.split(separator: "/").count > rhs.path.split(separator: "/").count
            }
        let allItems = (try? service.enumerateItems(root: context.root, config: config)) ?? []
        let subtitlePlanner = SableLibrarySubtitleAttachmentPlanner()
        let hasPendingWatchingPreparation = hasPendingWatchingPreparation(
            in: context.plan,
            config: config,
            videoSeries: inspection.videoSeries
        )
        let totalFileCount = inspection.books.count + (hasPendingWatchingPreparation ? 0 : inspection.videos.count)
        let readingPartNamesBySeriesPath = inspection.series.reduce(into: [String: [Int: ReadingPartNameMetadata]]()) { partialResult, series in
            partialResult[series.path] = readingPartNames(
                for: series,
                root: context.root,
                config: config,
                service: service
            )
        }
        let bookCountBySeries = Dictionary(grouping: inspection.books, by: { $0.seriesID ?? "" }).mapValues(\.count)
        let sourceMetadataTermKeys = inspection.sourceMetadataTermKeys.isEmpty
            ? Set(config.sourceMetadataTerms.map(service.normalizeTerm))
            : Set(inspection.sourceMetadataTermKeys)
        var plannedDestinations = Set<String>()
        var bookItems: [LibraryPlanItem] = []
        var volumeWrapperItems: [LibraryPlanItem] = []
        for (index, book) in inspection.books.enumerated() {
            reportFileNameProgress(
                service: service,
                message: "Checking book filename \(index + 1) of \(inspection.books.count): \(book.fileName)",
                completed: index + 1,
                total: totalFileCount,
                startedAt: startedAt
            )
            if let item = planItem(
                for: book,
                series: seriesByPath[book.seriesID ?? ""],
                knownPartNames: readingPartNamesBySeriesPath[book.seriesID ?? ""] ?? [:],
                bookCountInFolder: bookCountBySeries[book.seriesID ?? ""] ?? 1,
                root: context.root,
                config: config,
                plannedDestinations: &plannedDestinations,
                service: service
            ) {
                bookItems.append(item)
            }
            if let wrapperItem = volumeWrapperFileMoveItem(
                for: book,
                bookCountInFolder: bookCountBySeries[book.seriesID ?? ""] ?? 1,
                root: context.root,
                config: config,
                sourceMetadataTermKeys: sourceMetadataTermKeys,
                plannedDestinations: &plannedDestinations,
                service: service
            ) {
                volumeWrapperItems.append(wrapperItem)
            }
        }
        var videoItems: [LibraryPlanItem] = []
        if !hasPendingWatchingPreparation {
            for (index, video) in inspection.videos.enumerated() {
                let completedCount = inspection.books.count + index + 1
                reportFileNameProgress(
                    service: service,
                    message: "Checking video filename \(index + 1) of \(inspection.videos.count): \(video.fileName)",
                    completed: completedCount,
                    total: totalFileCount,
                    startedAt: startedAt
                )
                guard let item = videoPlanItem(
                    for: video,
                    series: matchingVideoSeries(for: video, seriesByDepth: videoSeriesByDepth),
                    root: context.root,
                    config: config,
                    plannedDestinations: &plannedDestinations,
                    service: service
                ) else {
                    continue
                }
                videoItems.append(item)
                if let proposedPath = item.proposedPath {
                    videoItems.append(contentsOf: subtitlePlanner.planItems(
                        followingVideoMoveFrom: video.path,
                        to: proposedPath,
                        allItems: allItems,
                        stage: .canonicalFiles,
                        operation: .renameFile,
                        requiresReview: item.requiresReview,
                        plannedDestinations: &plannedDestinations,
                        root: context.root,
                        service: service,
                        reason: "Matching subtitle can follow the Plex video rename and keep its language, forced, SDH, or CC tags."
                    ))
                }
            }
        }

        guard !bookItems.isEmpty || !volumeWrapperItems.isEmpty || !videoItems.isEmpty else {
            service.reportProgress("Book file names: no tidy file changes needed")
            return []
        }

        var groups: [LibraryPlanGroup] = []
        if !bookItems.isEmpty {
            service.reportProgress("Book file names: prepared \(bookItems.count) suggestion(s)")
            groups.append(
                LibraryPlanGroup(
                    stage: .canonicalFiles,
                    title: "Book file names",
                    summary: "\(bookItems.count) file(s) can use the ComicInfo title with volume or chapter clues.",
                    reviewPrompt: "Checked rows rename files in place using the sidecar title plus recovered volume or chapter clues.",
                    examples: examples(from: bookItems),
                    items: bookItems
                )
            )
        }

        if !volumeWrapperItems.isEmpty {
            service.reportProgress("Volume wrapper folders: prepared \(volumeWrapperItems.count) suggestion(s)")
            groups.append(
                LibraryPlanGroup(
                    stage: .canonicalFiles,
                    title: "Volume wrapper folders",
                    summary: "\(volumeWrapperItems.count) book file(s) can move out of single-volume folders into shared series folders.",
                    reviewPrompt: "Checked rows repair folders that look like one volume of a larger series, then clean the book filename.",
                    examples: examples(from: volumeWrapperItems),
                    items: volumeWrapperItems
                )
            )
        }

        if !videoItems.isEmpty {
            service.reportProgress("Video file names: prepared \(videoItems.count) suggestion(s)")
            groups.append(
                LibraryPlanGroup(
                    stage: .canonicalFiles,
                    title: "Video file names",
                    summary: "\(videoItems.count) video file(s) can use AnimeInfo titles and Plex season or movie naming.",
                    reviewPrompt: "Checked rows rename videos and matching subtitles in place using the watching sidecar plus clear season, episode, or movie clues.",
                    examples: examples(from: videoItems),
                    items: videoItems
                )
            )
        }
        return groups
    }

    private func reportFileNameProgress(
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
            unit: "file"
        )
        service.reportProgressSnapshot(SableLibraryProgressSnapshot(
            title: "Preparing file names",
            message: "\(message). \(timing)",
            completedUnitCount: completed,
            totalUnitCount: total
        ))
    }

    private func volumeWrapperFileMoveItem(
        for book: LibraryBookSnapshot,
        bookCountInFolder: Int,
        root: URL,
        config: SableLibraryConfig,
        sourceMetadataTermKeys: Set<String>,
        plannedDestinations: inout Set<String>,
        service: SableLibraryService
    ) -> LibraryPlanItem? {
        guard bookCountInFolder == 1,
              let parentPath = book.seriesID,
              volumeWrapperParentCanBeRepaired(parentPath) else {
            return nil
        }

        let folderName = (parentPath as NSString).lastPathComponent
        let cleanedFolderName = service.cleanedTitle(
            folderName,
            config: config,
            sourceMetadataTermKeys: sourceMetadataTermKeys
        )
        guard service.volumeOrChapterSuffix(in: cleanedFolderName) != nil else { return nil }

        let folderParts = service.bookNameParts(
            for: folderName,
            config: config,
            sourceMetadataTermKeys: sourceMetadataTermKeys
        )
        let normalizedFolderName = service.normalizeTerm(folderName)
        let normalizedSeriesTitle = service.normalizeTerm(folderParts.seriesTitle)
        guard !normalizedSeriesTitle.isEmpty,
              normalizedSeriesTitle != normalizedFolderName else {
            return nil
        }

        let rawName = (book.fileName as NSString).deletingPathExtension
        let cleanedRawName = service.cleanedTitle(
            rawName,
            config: config,
            sourceMetadataTermKeys: sourceMetadataTermKeys
        )
        let suffix = service.volumeOrChapterSuffix(in: cleanedRawName)
            ?? service.volumeOrChapterSuffix(in: cleanedFolderName)
        let fileTitle = suffix.map {
            service.bookFileTitle(seriesTitle: folderParts.seriesTitle, suffix: $0)
        } ?? folderParts.fileTitle
        let proposedFileName = service.sanitizeFilename(
            fileTitle + "." + book.fileExtension.lowercased()
        )
        let containerPath = (parentPath as NSString).deletingLastPathComponent
        let proposedSeriesPath = service.joinedRelativePath(containerPath, folderParts.seriesTitle)
        let proposedPath = service.joinedRelativePath(proposedSeriesPath, proposedFileName)

        guard proposedPath != book.path,
              proposedPath.lowercased() != book.path.lowercased() else {
            return nil
        }

        let proposedURL = root.appendingPathComponent(proposedPath)
        let hasCollision = service.fileManager.fileExists(atPath: proposedURL.path(percentEncoded: false))
            || plannedDestinations.contains(proposedPath)
        plannedDestinations.insert(proposedPath)

        return LibraryPlanItem(
            stage: .canonicalFiles,
            operation: .renameFile,
            currentPath: book.path,
            proposedPath: proposedPath,
            reason: "Moves a book out of a folder that looks like one volume and into the shared \(folderParts.seriesTitle) series folder.",
            confidence: hasCollision ? .medium : .high,
            safety: hasCollision ? .collision : .reversible,
            decision: hasCollision ? .unchecked : .checked,
            requiresReview: hasCollision,
            confidenceExplanation: hasCollision
                ? "The parent folder name has a clear volume marker, but the proposed book filename already exists."
                : "The parent folder name has a clear volume marker, and it contains exactly one book file.",
            correctionOptions: [.keepTitle, .custom],
            reviewTags: ["volume-wrapper-folder"],
            receipt: "\(book.path) -> \(proposedPath)"
        )
    }

    private func volumeWrapperParentCanBeRepaired(_ parentPath: String) -> Bool {
        let components = parentPath
            .split(separator: "/")
            .map(String.init)
        guard components.count == 2,
              let root = components.first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return false
        }

        let readingRoots: Set<String> = [
            "books",
            "light novels",
            "manga",
            "manhwa",
            "manhua",
            "oel",
            "comics",
            "comic books",
            "graphic novels",
            "other reading"
        ]
        return readingRoots.contains(root)
    }

    private func planItem(
        for book: LibraryBookSnapshot,
        series: LibrarySeriesSnapshot?,
        knownPartNames: [Int: ReadingPartNameMetadata],
        bookCountInFolder: Int,
        root: URL,
        config: SableLibraryConfig,
        plannedDestinations: inout Set<String>,
        service: SableLibraryService
    ) -> LibraryPlanItem? {
        guard let series,
              series.hasComicInfo,
              let rawPreferredTitle = series.preferredTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawPreferredTitle.isEmpty else {
            return nil
        }
        guard let parentPath = book.seriesID, !parentPath.isEmpty else { return nil }
        let fileSourceIDs = readingFileSourceIDsToPreserve(in: book.fileName)

        let rawName = (book.fileName as NSString).deletingPathExtension
        let cleanedRawName = service.cleanedTitle(rawName, config: config)
        let suffix = service.volumeOrChapterSuffix(in: cleanedRawName)
        let matchedPart = matchedReadingPart(
            for: series,
            suffix: suffix,
            knownPartNames: knownPartNames,
            service: service
        )
        let preferredTitle = effectiveReadingFileTitle(
            for: series,
            preferredTitle: rawPreferredTitle,
            matchedPart: matchedPart,
            suffix: suffix,
            service: service
        )
        let parts = service.preferredBookFileTitle(
            rawName: rawName,
            parentFolderName: preferredTitle,
            requiresTitleMatch: false,
            maximumVolume: nil,
            bookCountInFolder: bookCountInFolder,
            config: config
        )
        var enrichedSuffix = enrichedReadingSuffix(
            suffix,
            matchedPart: matchedPart,
            series: series,
            service: service
        )
        let providerBookFileTitle = ranobeDBBookFileTitle(
            matchedPart: matchedPart,
            series: series,
            suffix: suffix,
            service: service
        )
        var droppedProviderTitleForLength = false
        var usedRanobeDBBookFileTitle = false
        func fallbackFileName(using fallbackSuffix: String?) -> String {
            service.sanitizeFilename(
                namingPolicy.canonicalReadingFileName(
                    preferredTitle: preferredTitle,
                    year: series.year,
                    sourceIDs: fileSourceIDs,
                    suffix: fallbackSuffix,
                    fileExtension: book.fileExtension
                )
            )
        }

        var proposedFileName: String
        if let providerBookFileTitle {
            let ranobeDBFileName = service.sanitizeFilename(
                providerBookFileTitle + "." + book.fileExtension.lowercased()
            )
            if fileNameIsTooLong(ranobeDBFileName) {
                proposedFileName = fallbackFileName(using: enrichedSuffix.suffix)
                droppedProviderTitleForLength = true
            } else {
                proposedFileName = ranobeDBFileName
                usedRanobeDBBookFileTitle = true
            }
        } else {
            proposedFileName = fallbackFileName(using: enrichedSuffix.suffix)
        }
        if enrichedSuffix.usedProviderTitle, fileNameIsTooLong(proposedFileName) {
            enrichedSuffix = (
                suffix: suffix,
                usedProviderTitle: false,
                needsTitleConflictReview: enrichedSuffix.needsTitleConflictReview
            )
            if !usedRanobeDBBookFileTitle {
                proposedFileName = fallbackFileName(using: enrichedSuffix.suffix)
            }
            droppedProviderTitleForLength = true
        }
        if fileNameIsTooLong(proposedFileName) {
            proposedFileName = shortenedFileName(proposedFileName)
        }
        guard proposedFileName != book.fileName else { return nil }
        guard proposedFileName.lowercased() != book.fileName.lowercased() else { return nil }

        let proposedPath = service.joinedRelativePath(parentPath, proposedFileName)
        let proposedURL = root.appendingPathComponent(proposedPath)
        let hasCollision = service.fileManager.fileExists(atPath: proposedURL.path(percentEncoded: false)) || plannedDestinations.contains(proposedPath)
        plannedDestinations.insert(proposedPath)

        let volumeConflict = localVolumeConflict(in: series)
        let fileRenameReview = fileRenameReview(currentPath: book.path, proposedPath: proposedPath)
        let needsReview = hasCollision
            || parts.needsManualReview
            || enrichedSuffix.needsTitleConflictReview
            || fileRenameReview.requiresChoice
        let reason: String
        if hasCollision {
            reason = "Another file already uses this tidy name. Review duplicate handling first."
        } else if parts.needsManualReview {
            reason = "ComicInfo gives the title, but the volume or chapter pattern needs review."
        } else if enrichedSuffix.needsTitleConflictReview {
            reason = "volume or chapter title differs from provider metadata. Keep local title and review before applying."
        } else if usedRanobeDBBookFileTitle {
            reason = "File can use the trusted RanobeDB book title for this exact local volume."
        } else if let reviewReason = fileRenameReview.reason {
            reason = reviewReason
        } else if droppedProviderTitleForLength {
            reason = "The trusted provider book title was too long for a calm filename, so Sable falls back to the ComicInfo title and local volume or chapter."
        } else if enrichedSuffix.usedProviderTitle {
            reason = "File can use ComicInfo preferred title with its trusted volume title."
        } else {
            reason = "File can use ComicInfo preferred title with its existing volume or chapter suffix."
        }
        let baseConfidenceExplanation = confidenceExplanation(
            hasCollision: hasCollision,
            needsManualReview: parts.needsManualReview,
            usedProviderTitle: enrichedSuffix.usedProviderTitle || usedRanobeDBBookFileTitle,
            droppedProviderTitleForLength: droppedProviderTitleForLength,
            needsProviderTitleReview: enrichedSuffix.needsTitleConflictReview,
            volumeConflict: volumeConflict
        )
        let planConfidenceExplanation = fileRenameReview.confidenceNote.map {
            "\(baseConfidenceExplanation) \($0)"
        } ?? baseConfidenceExplanation

        return LibraryPlanItem(
            stage: .canonicalFiles,
            operation: .renameFile,
            currentPath: book.path,
            proposedPath: proposedPath,
            reason: reason,
            confidence: needsReview ? .medium : .high,
            safety: hasCollision ? .collision : (needsReview ? .needsChoice : .reversible),
            decision: needsReview ? .unchecked : .checked,
            requiresReview: needsReview,
            metadataProviders: fileSourceIDs.map(\.provider),
            confidenceExplanation: planConfidenceExplanation,
            correctionOptions: [.badNumber, .keepTitle, .custom],
            reviewTags: fileReviewTags(fileRenameReview.reviewTags, sourceIDs: fileSourceIDs),
            receipt: "\(book.path) -> \(proposedPath)"
        )
    }

    private func effectiveReadingFileTitle(
        for series: LibrarySeriesSnapshot,
        preferredTitle: String,
        matchedPart: ReadingPartNameMetadata?,
        suffix: String?,
        service: SableLibraryService
    ) -> String {
        let baseTitle: String
        if (hasReadingSourceID(.mangabaka, in: series) || hasReadingSourceID(.ranobedb, in: series)),
           let localTitle = series.localTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !localTitle.isEmpty,
           shouldPreserveLocalReadingTitle(localTitle, providerTitle: preferredTitle, service: service) {
            baseTitle = seriesTitleWithoutVolumeSuffix(localTitle)
        } else {
            baseTitle = preferredTitle
        }

        return ranobeDBBookSeriesTitleForFileName(
            preferredTitle: baseTitle,
            matchedPart: matchedPart,
            suffix: suffix,
            service: service
        ) ?? baseTitle
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
        if providerTitleHasConflictingRelationshipMarker(localTitle: localTitle, providerTitle: providerTitle) {
            return true
        }
        if titleConflict(localTitle, providerTitle, service: service) {
            return true
        }
        return providerTitleDropsMeaningfulSubtitle(localTitle: localTitle, providerTitle: providerTitle, service: service)
    }

    private func ranobeDBBookSeriesTitleForFileName(
        preferredTitle: String,
        matchedPart: ReadingPartNameMetadata?,
        suffix: String?,
        service: SableLibraryService
    ) -> String? {
        guard let matchedPart,
              matchedPart.sourceID?.provider == .ranobedb,
              let providerBookTitle = matchedPart.title,
              let providerSeriesTitle = providerSeriesTitle(fromBookTitle: providerBookTitle, service: service) else {
            return nil
        }

        let preferredKey = service.normalizeTerm(preferredTitle)
        let providerSeriesKey = service.normalizeTerm(providerSeriesTitle)
        guard !preferredKey.isEmpty,
              !providerSeriesKey.isEmpty,
              preferredKey != providerSeriesKey,
              preferredKey.contains(providerSeriesKey) else {
            return nil
        }

        let matchedPartTitle = matchedPart.subtitle ?? suffix.flatMap { partTitle(from: $0) }
        if let matchedPartTitle {
            let partTitleKey = service.normalizeTerm(matchedPartTitle)
            guard !partTitleKey.isEmpty,
                  preferredKey.contains(partTitleKey) else {
                return nil
            }
        }

        return providerSeriesTitle
    }

    private func ranobeDBBookFileTitle(
        matchedPart: ReadingPartNameMetadata?,
        series: LibrarySeriesSnapshot,
        suffix: String?,
        service: SableLibraryService
    ) -> String? {
        guard let matchedPart,
              matchedPart.sourceID?.provider == .ranobedb,
              let title = matchedPart.title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty,
              let suffix,
              let localVolumeNumber = service.volumeNumber(in: suffix),
              readingPart(matchedPart, fits: series, localVolumeNumber: localVolumeNumber, service: service),
              let titleSuffix = service.volumeOrChapterSuffix(in: title),
              service.volumeNumber(in: titleSuffix) == localVolumeNumber,
              !readingPartTitleMismatch(
                localSuffix: suffix,
                providerSuffix: titleSuffix,
                service: service
              ) else {
            return nil
        }

        return title
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func providerSeriesTitle(fromBookTitle title: String, service: SableLibraryService) -> String? {
        let seriesTitle = seriesTitleWithoutVolumeSuffix(title)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",:-–—")))
        guard !seriesTitle.isEmpty,
              service.normalizeTerm(seriesTitle) != service.normalizeTerm(title) else {
            return nil
        }
        return seriesTitle
    }

    private func readingFileSourceIDsToPreserve(in fileName: String) -> [SableLibrarySourceID] {
        SableLibrarySourceIDParser.folderHints(in: fileName)
    }

    private func fileReviewTags(_ tags: [String], sourceIDs: [SableLibrarySourceID]) -> [String] {
        var values = tags + ["naming-file-rename"]
        for provider in sourceIDs.map(\.provider) {
            values.append("provider-token-\(provider.rawValue.lowercased())")
        }
        return Array(Set(values)).sorted()
    }

    private func fileRenameReview(currentPath: String, proposedPath: String) -> FileRenameReview {
        let currentFileName = (currentPath as NSString).lastPathComponent
        let proposedFileName = (proposedPath as NSString).lastPathComponent
        let currentTitle = fileTitleForReview(in: currentFileName)
        let proposedTitle = fileTitleForReview(in: proposedFileName)
        let currentTitleKey = fileTitleKey(currentTitle)
        let proposedTitleKey = fileTitleKey(proposedTitle)
        let currentTokens = fileSourceTokenSet(in: currentFileName)
        let proposedTokens = fileSourceTokenSet(in: proposedFileName)
        let tokenChange = currentTokens != proposedTokens
        var tags: [String] = []

        if tokenChange {
            tags.append("naming-provider-token-change")
        } else if !currentTokens.isEmpty {
            tags.append("naming-provider-token-preserved")
        }

        if !currentTitleKey.isEmpty, !proposedTitleKey.isEmpty, currentTitleKey != proposedTitleKey {
            tags.append(contentsOf: ["naming-title-change", "training-material"])
            return FileRenameReview(
                requiresChoice: true,
                reason: "Metadata would change the visible filename title from \(currentTitle) to \(proposedTitle). Confirm before renaming so local file titles stay intentional.",
                confidenceNote: "The file title text changes, so this stays unchecked even when the sidecar has provider IDs.",
                reviewTags: tags
            )
        }

        if tokenChange {
            tags.append("training-material")
            return FileRenameReview(
                requiresChoice: true,
                reason: "Provider ID tokens in the filename would change. Confirm before applying so known IDs like RanobeDB stay attached.",
                confidenceNote: "The title looks stable, but provider tokens change; Sable keeps this as a review choice.",
                reviewTags: tags
            )
        }

        if !currentTitle.isEmpty,
           !proposedTitle.isEmpty,
           currentTitle != proposedTitle,
           currentTitleKey == proposedTitleKey {
            tags.append(contentsOf: ["naming-punctuation-only", "training-material"])
            return FileRenameReview(
                requiresChoice: false,
                reason: "Only punctuation or spacing in the visible filename title would change. Sable checked it because the readable title stays the same.",
                confidenceNote: "This is a low-visibility cleanup, so it remains reversible and can be unchecked before applying.",
                reviewTags: tags
            )
        }

        return FileRenameReview(
            requiresChoice: false,
            reason: nil,
            confidenceNote: nil,
            reviewTags: tags
        )
    }

    private func fileTitleForReview(in fileName: String) -> String {
        let baseName = (fileName as NSString).deletingPathExtension
        let withoutTokens = baseName.replacingOccurrences(
            of: #"(?i)\s*\{(?:mb|mangabaka|rdb|ranobedb|ol|openlibrary|open_library|mal|myanimelist|my_anime_list|anilist|al|tvmaze|wikidata|wd|tmdb|tvdb|imdb|local)-[^}]+\}\s*"#,
            with: " ",
            options: .regularExpression
        )
        let withoutYear = withoutTokens.replacingOccurrences(
            of: #"\s*[\(\[]\d{4}[\)\]]\s*"#,
            with: " ",
            options: .regularExpression
        )
        let withoutSuffix = withoutYear.replacingOccurrences(
            of: #"(?i)\s*(?:[-–—]\s*)?(?:vol(?:ume)?|book|v|ch(?:apter)?)\.?\s*0*\d{1,4}(?:\.\d+)?(?:\s*[-–—]\s*0*\d{1,4})?(?:\s*[-–—:]\s*.+)?\s*$"#,
            with: "",
            options: .regularExpression
        )
        return withoutSuffix
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "-:")))
    }

    private func fileTitleKey(_ title: String) -> String {
        title
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "[‘’`´]", with: "'", options: .regularExpression)
            .replacingOccurrences(of: "[“”]", with: "\"", options: .regularExpression)
            .replacingOccurrences(of: "[–—−]", with: "-", options: .regularExpression)
            .replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func fileSourceTokenSet(in fileName: String) -> Set<String> {
        Set(fileSourceTokenLabels(in: fileName).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        })
    }

    private func fileSourceTokenLabels(in fileName: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?i)\{(?:mb|mangabaka|rdb|ranobedb|ol|openlibrary|open_library|mal|myanimelist|my_anime_list|anilist|al|tvmaze|wikidata|wd|tmdb|tvdb|imdb|local)-[^}]+\}"#
        ) else {
            return []
        }
        let nsFileName = fileName as NSString
        let fullRange = NSRange(location: 0, length: nsFileName.length)
        return regex.matches(in: fileName, range: fullRange).map { match in
            nsFileName.substring(with: match.range)
        }
    }

    private struct FileRenameReview {
        var requiresChoice: Bool
        var reason: String?
        var confidenceNote: String?
        var reviewTags: [String]
    }

    private struct ReadingPartNameMetadata {
        var number: Int
        var sourceID: SableLibrarySourceID?
        var title: String?
        var subtitle: String?
        var fileSuffix: String?

        func bestFileSuffix(localVolumeNumber: Int?, service: SableLibraryService) -> String? {
            let expectedNumber = localVolumeNumber ?? number
            if let titleSuffix = title.flatMap({ service.volumeOrChapterSuffix(in: $0) }) {
                if let titleVolumeNumber = service.volumeNumber(in: titleSuffix),
                   titleVolumeNumber != expectedNumber {
                    return nil
                }
                if !isPlainVolumeSuffix(titleSuffix, number: expectedNumber) {
                    return titleSuffix
                }
            }
            if let subtitle,
               !subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Vol \(Self.paddedVolume(expectedNumber)) - \(subtitle)"
            }
            if let fileSuffix,
               let fileSuffixVolume = service.volumeNumber(in: fileSuffix),
               fileSuffixVolume == expectedNumber,
               !isPlainVolumeSuffix(fileSuffix, number: expectedNumber) {
                return fileSuffix
            }
            return nil
        }

        private func isPlainVolumeSuffix(_ value: String, number: Int) -> Bool {
            let normalized = value
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            return normalized == "vol \(Self.paddedVolume(number))"
                || normalized == "volume \(Self.paddedVolume(number))"
                || normalized == "vol \(number)"
                || normalized == "volume \(number)"
        }

        private static func paddedVolume(_ number: Int) -> String {
            String(format: "%02d", number)
        }
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

    private func providerTitleHasConflictingRelationshipMarker(localTitle: String, providerTitle: String) -> Bool {
        let localMarkers = readingRelationshipMarkers(in: localTitle)
        let providerMarkers = readingRelationshipMarkers(in: providerTitle)
        guard !localMarkers.isEmpty, !providerMarkers.isEmpty else {
            return false
        }
        return !localMarkers.isSubset(of: providerMarkers)
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

    private func tokenSimilarity(_ lhs: String, _ rhs: String) -> Double {
        let lhsTokens = Set(lhs.split(separator: " ").map(String.init))
        let rhsTokens = Set(rhs.split(separator: " ").map(String.init))
        guard !lhsTokens.isEmpty, !rhsTokens.isEmpty else { return 0 }
        let overlap = lhsTokens.intersection(rhsTokens).count
        let union = lhsTokens.union(rhsTokens).count
        return union == 0 ? 0 : Double(overlap) / Double(union)
    }

    private func videoPlanItem(
        for video: LibraryVideoSnapshot,
        series: LibraryVideoSeriesSnapshot?,
        root: URL,
        config: SableLibraryConfig,
        plannedDestinations: inout Set<String>,
        service: SableLibraryService
    ) -> LibraryPlanItem? {
        guard let series,
              series.hasAnimeInfo,
              let preferredTitle = series.preferredTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
              !preferredTitle.isEmpty,
              hasUsableWatchingNamingSource(series, preferredTitle: preferredTitle, service: service),
              let mediaType = effectiveWatchingMediaType(for: series),
              let target = watchingTarget(for: video, series: series, preferredTitle: preferredTitle, mediaType: mediaType, config: config, service: service) else {
            return nil
        }
        guard target.path != video.path else { return nil }
        guard target.path.lowercased() != video.path.lowercased() else { return nil }

        let proposedURL = root.appendingPathComponent(target.path)
        let hasCollision = service.fileManager.fileExists(atPath: proposedURL.path(percentEncoded: false)) || plannedDestinations.contains(target.path)
        plannedDestinations.insert(target.path)

        let reason: String
        if hasCollision {
            reason = "Another file already uses this Plex-style video name. Review duplicate handling first."
        } else if target.kind == .movie {
            reason = "Video can use AnimeInfo movie naming with the trusted title and year."
        } else if target.episodeTitle != nil {
            reason = "Video can use AnimeInfo episode naming and keep the parsed episode title."
        } else {
            reason = "Video can use AnimeInfo episode naming from a clear season and episode code."
        }

        return LibraryPlanItem(
            stage: .canonicalFiles,
            operation: .renameFile,
            currentPath: video.path,
            proposedPath: target.path,
            reason: reason,
            confidence: hasCollision ? .medium : .high,
            safety: hasCollision ? .collision : .reversible,
            decision: hasCollision ? .unchecked : .checked,
            requiresReview: hasCollision,
            confidenceExplanation: hasCollision
                ? "Another file already uses the target video name, so this stays out of quiet apply."
                : target.explanation,
            correctionOptions: [.keepTitle, .custom],
            receipt: "\(video.path) -> \(target.path)"
        )
    }

    private func matchingVideoSeries(
        for video: LibraryVideoSnapshot,
        seriesByDepth: [LibraryVideoSeriesSnapshot]
    ) -> LibraryVideoSeriesSnapshot? {
        seriesByDepth.first { series in
            !series.path.isEmpty && (video.path == series.path || video.path.hasPrefix("\(series.path)/"))
        }
    }

    private func watchingTarget(
        for video: LibraryVideoSnapshot,
        series: LibraryVideoSeriesSnapshot,
        preferredTitle: String,
        mediaType: String,
        config: SableLibraryConfig,
        service: SableLibraryService
    ) -> WatchingFileTarget? {
        if isMovieType(mediaType) {
            let splitSuffix = movieSplitSuffix(from: video.fileName)
            let canonicalMovieName = namingPolicy.canonicalWatchingMovieFileName(
                preferredTitle: preferredTitle,
                year: series.year,
                sourceID: series.primarySourceID,
                fileExtension: video.fileExtension
            )
            let fileName = service.sanitizeFilename(
                movieFileName(canonicalMovieName, splitSuffix: splitSuffix)
            )
            return WatchingFileTarget(
                kind: .movie,
                path: service.joinedRelativePath(series.path, fileName),
                episodeTitle: nil,
                explanation: splitSuffix == nil
                    ? "AnimeInfo marks this as a movie, so Plex expects the file directly inside the movie folder."
                    : "AnimeInfo marks this as a movie, and the split-part marker is kept for Plex."
            )
        }

        guard let parsedEpisode = parsedEpisode(
            from: video,
            series: series,
            preferredTitle: preferredTitle,
            mediaType: mediaType,
            config: config,
            service: service
        ) else {
            return nil
        }
        let episode = plexEpisode(parsedEpisode, mediaType: mediaType)
        let seasonFolder = namingPolicy.plexSeasonFolderName(season: episode.season)
        let fileName = service.sanitizeFilename(
            namingPolicy.canonicalWatchingEpisodeFileName(
                preferredTitle: preferredTitle,
                year: series.year,
                season: episode.season,
                episode: episode.episode,
                endSeason: episode.endSeason,
                endEpisode: episode.endEpisode,
                episodeTitle: episode.title,
                fileExtension: video.fileExtension
            )
        )
        return WatchingFileTarget(
            kind: .episode,
            path: service.joinedRelativePath(series.path, seasonFolder, fileName),
            episodeTitle: episode.title,
            explanation: usesPlexSpecialsSeason(mediaType)
                ? "AnimeInfo marks this as OVA, ONA, or special content, so Plex expects season zero."
                : "AnimeInfo provides the title and the filename has a clear SxxEyy episode code."
        )
    }

    private func isMovieType(_ mediaType: String) -> Bool {
        switch mediaType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "movie", "animemovie", "anime movie":
            true
        default:
            false
        }
    }

    private func plexEpisode(_ episode: ParsedWatchingEpisode, mediaType: String) -> ParsedWatchingEpisode {
        guard usesPlexSpecialsSeason(mediaType), episode.season != 0 else {
            return episode
        }

        return ParsedWatchingEpisode(
            season: 0,
            episode: episode.episode,
            endSeason: episode.endSeason.map { _ in 0 },
            endEpisode: episode.endEpisode,
            title: episode.title
        )
    }

    private func usesPlexSpecialsSeason(_ mediaType: String) -> Bool {
        switch mediaType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "ova", "ona", "special", "specials":
            true
        default:
            false
        }
    }

    private func movieSplitSuffix(from fileName: String) -> String? {
        let rawName = (fileName as NSString).deletingPathExtension
        let pattern = #"(?i)(?:^|[\s._\-–—]+)(cd|disc|disk|dvd|part|pt)\s*0*(\d{1,2})(?:[\s._\-–—]*[A-Za-z0-9][\w\s.\-–—]*)?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: rawName, range: NSRange(rawName.startIndex..<rawName.endIndex, in: rawName)),
              let markerRange = Range(match.range(at: 1), in: rawName),
              let numberRange = Range(match.range(at: 2), in: rawName),
              let number = Int(rawName[numberRange]) else {
            return nil
        }

        let marker = String(rawName[markerRange]).lowercased()
        return "\(marker)\(max(1, number))"
    }

    private func movieFileName(_ fileName: String, splitSuffix: String?) -> String {
        guard let splitSuffix else { return fileName }
        let fileExtension = (fileName as NSString).pathExtension
        let base = (fileName as NSString).deletingPathExtension
        let extensionSuffix = fileExtension.isEmpty ? "" : ".\(fileExtension)"
        return "\(base) - \(splitSuffix)\(extensionSuffix)"
    }

    private func effectiveWatchingMediaType(for series: LibraryVideoSeriesSnapshot) -> String? {
        let rawMediaType = series.mediaType?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if isKnownWatchingMediaType(rawMediaType) {
            return rawMediaType
        }

        return watchingTypeHint(in: series.path)
    }

    private func hasUsableWatchingNamingSource(
        _ series: LibraryVideoSeriesSnapshot,
        preferredTitle: String,
        service: SableLibraryService
    ) -> Bool {
        if hasTrustedWatchingIdentity(series) {
            return true
        }

        let titleKey = service.normalizeTerm(preferredTitle)
        guard !titleKey.isEmpty else { return false }

        let localTitleKey = series.localTitle.map(service.normalizeTerm)
        let displayKey = service.normalizeTerm(series.displayName)
        let folderKey = service.normalizeTerm((series.path as NSString).lastPathComponent)

        return localTitleKey == titleKey
            || displayKey == titleKey
            || folderKey == titleKey
            || folderKey.hasPrefix(titleKey + " ")
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

    private func hasPendingWatchingPreparation(
        in plan: LibraryPlan,
        config: SableLibraryConfig,
        videoSeries: [LibraryVideoSeriesSnapshot]
    ) -> Bool {
        let matcher = SableLibraryFileTypeMatcher(config: config)
        let videoSeriesPaths = Set(videoSeries.map(\.path))
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
            case .renameFolder:
                guard item.stage == .canonicalFolders else { return false }
                return videoSeriesPaths.contains(item.currentPath)
            case .inspectOnly, .repairEpubPackage, .repairAppleBooksCompatibility, .createComicInfo, .refreshComicInfo, .renameFile, .duplicateDecision, .skip:
                return false
            }
        }
    }

    private func parsedEpisode(
        from video: LibraryVideoSnapshot,
        series: LibraryVideoSeriesSnapshot,
        preferredTitle: String,
        mediaType: String,
        config: SableLibraryConfig,
        service: SableLibraryService
    ) -> ParsedWatchingEpisode? {
        let rawName = (video.fileName as NSString).deletingPathExtension
        let pattern = #"(?i)\bS(?:eason)?\s*0*(\d{1,2})\s*E(?:p(?:isode)?)?\.?\s*0*(\d{1,3})(?:\s*[-–—]\s*(?:S(?:eason)?\s*0*(\d{1,2})\s*)?E(?:p(?:isode)?)?\.?\s*0*(\d{1,3}))?\b"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: rawName, range: NSRange(rawName.startIndex..<rawName.endIndex, in: rawName)),
           let season = integerMatch(match, group: 1, in: rawName),
           let episode = integerMatch(match, group: 2, in: rawName) {
            let endSeason = integerMatch(match, group: 3, in: rawName)
            let endEpisode = integerMatch(match, group: 4, in: rawName)

            if let folderSeason = seasonHint(for: video.path, seriesPath: series.path),
               folderSeason != season || (endSeason.map { $0 != folderSeason } ?? false) {
                return nil
            }
            let title = episodeTitle(after: match, in: rawName, config: config, service: service)
            return ParsedWatchingEpisode(
                season: season,
                episode: episode,
                endSeason: endSeason,
                endEpisode: endEpisode,
                title: title
            )
        }

        return looseEpisode(
            from: video,
            rawName: rawName,
            series: series,
            preferredTitle: preferredTitle,
            mediaType: mediaType,
            config: config,
            service: service
        )
    }

    private func integerMatch(_ match: NSTextCheckingResult, group: Int, in text: String) -> Int? {
        guard match.numberOfRanges > group,
              let range = Range(match.range(at: group), in: text) else {
            return nil
        }
        return Int(text[range])
    }

    private func episodeTitle(
        after match: NSTextCheckingResult,
        in rawName: String,
        config: SableLibraryConfig,
        service: SableLibraryService
    ) -> String? {
        guard let fullRange = Range(match.range(at: 0), in: rawName) else { return nil }
        let tail = String(rawName[fullRange.upperBound...])
            .replacingOccurrences(of: #"^[\s._\-–—:]+|[\s._\-–—:]+$"#, with: "", options: .regularExpression)
        guard !tail.isEmpty else { return nil }
        let cleaned = service.cleanedTitle(tail, config: config)
        let blocked = Set(["1080p", "720p", "2160p", "480p", "x264", "x265", "hevc", "aac", "bluray", "web", "dl", "webrip"])
        let terms = service.normalizeTerm(cleaned).split(separator: " ").map(String.init)
        guard !terms.isEmpty,
              !terms.allSatisfy({ blocked.contains($0) }) else {
            return nil
        }
        return cleaned
    }

    private func looseEpisode(
        from video: LibraryVideoSnapshot,
        rawName: String,
        series: LibraryVideoSeriesSnapshot,
        preferredTitle: String,
        mediaType: String,
        config: SableLibraryConfig,
        service: SableLibraryService
    ) -> ParsedWatchingEpisode? {
        if let parsed = looseNumberedEpisode(
            rawName: rawName,
            videoPath: video.path,
            seriesPath: series.path,
            config: config,
            service: service
        ) {
            return parsed
        }

        guard series.localVideoCount == 1,
              !isMovieType(mediaType),
              rawVideoTitleMatchesSeries(rawName, series: series, preferredTitle: preferredTitle, config: config, service: service) else {
            return nil
        }

        return ParsedWatchingEpisode(
            season: seasonHint(for: video.path, seriesPath: series.path) ?? 1,
            episode: 1,
            endSeason: nil,
            endEpisode: nil,
            title: nil
        )
    }

    private func looseNumberedEpisode(
        rawName: String,
        videoPath: String,
        seriesPath: String,
        config: SableLibraryConfig,
        service: SableLibraryService
    ) -> ParsedWatchingEpisode? {
        let pattern = #"(?i)(?:^|[\s._\-–—]+)(?:ep(?:isode)?\.?\s*)?0*(\d{1,3})(?:\s*[-–—]\s*(?:ep(?:isode)?\.?\s*)?0*(\d{1,3}))?(?:\s*[-–—]\s*([^\/]+?))?\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: rawName, range: NSRange(rawName.startIndex..<rawName.endIndex, in: rawName)),
              let episode = integerMatch(match, group: 1, in: rawName),
              (1...199).contains(episode) else {
            return nil
        }
        let endEpisode = integerMatch(match, group: 2, in: rawName)
        if let endEpisode, !(episode...199).contains(endEpisode) {
            return nil
        }

        let season = seasonHint(for: videoPath, seriesPath: seriesPath) ?? 1
        let title = looseEpisodeTitle(match: match, rawName: rawName, config: config, service: service)
        return ParsedWatchingEpisode(
            season: season,
            episode: episode,
            endSeason: nil,
            endEpisode: endEpisode,
            title: title
        )
    }

    private func looseEpisodeTitle(
        match: NSTextCheckingResult,
        rawName: String,
        config: SableLibraryConfig,
        service: SableLibraryService
    ) -> String? {
        guard match.numberOfRanges > 3,
              let range = Range(match.range(at: 3), in: rawName) else {
            return nil
        }
        let rawTitle = String(rawName[range])
            .replacingOccurrences(of: #"^[\s._\-–—:]+|[\s._\-–—:]+$"#, with: "", options: .regularExpression)
        guard !rawTitle.isEmpty else { return nil }

        let cleaned = service.cleanedTitle(rawTitle, config: config)
        let blocked = Set(["1080p", "720p", "2160p", "480p", "x264", "x265", "hevc", "aac", "bluray", "web", "dl", "webrip"])
        let terms = service.normalizeTerm(cleaned).split(separator: " ").map(String.init)
        guard !terms.isEmpty,
              !terms.allSatisfy({ blocked.contains($0) }) else {
            return nil
        }
        return cleaned
    }

    private func rawVideoTitleMatchesSeries(
        _ rawName: String,
        series: LibraryVideoSeriesSnapshot,
        preferredTitle: String,
        config: SableLibraryConfig,
        service: SableLibraryService
    ) -> Bool {
        let rawKey = service.normalizeTerm(service.cleanedTitle(rawName, config: config))
        guard !rawKey.isEmpty else { return false }

        let candidates = [
            preferredTitle,
            series.localTitle,
            series.displayName,
            (series.path as NSString).lastPathComponent
        ].compactMap { $0 }

        return candidates.contains { candidate in
            let cleanedCandidate = service.cleanedTitle(candidate, config: config)
            let key = service.normalizeTerm(cleanedCandidate)
            return !key.isEmpty && (rawKey == key || rawKey.hasPrefix(key + " "))
        }
    }

    private func seasonHint(for path: String, seriesPath: String) -> Int? {
        let relativePath: String
        if path.hasPrefix("\(seriesPath)/") {
            relativePath = String(path.dropFirst(seriesPath.count + 1))
        } else {
            relativePath = path
        }
        for component in relativePath.split(separator: "/").dropLast() {
            let name = String(component)
            if name.range(of: #"(?i)^specials$"#, options: .regularExpression) != nil {
                return 0
            }
            guard let regex = try? NSRegularExpression(pattern: #"(?i)^season\s+0*(\d{1,2})$"#),
                  let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..<name.endIndex, in: name)),
                  let season = integerMatch(match, group: 1, in: name) else {
                continue
            }
            return season
        }
        return nil
    }

    private enum WatchingFileKind {
        case movie
        case episode
    }

    private struct WatchingFileTarget {
        var kind: WatchingFileKind
        var path: String
        var episodeTitle: String?
        var explanation: String
    }

    private struct ParsedWatchingEpisode {
        var season: Int
        var episode: Int
        var endSeason: Int?
        var endEpisode: Int?
        var title: String?
    }

    private func examples(from items: [LibraryPlanItem]) -> [LibraryPlanExample] {
        items.prefix(3).map { item in
            LibraryPlanExample(
                title: "File rename",
                before: item.currentPath,
                after: item.proposedPath,
                reason: item.reason
            )
        }
    }

    private func confidenceExplanation(
        hasCollision: Bool,
        needsManualReview: Bool,
        usedProviderTitle: Bool,
        droppedProviderTitleForLength: Bool,
        needsProviderTitleReview: Bool,
        volumeConflict: SableLibraryVolumeConflict?
    ) -> String {
        let volumeNote = volumeConflict.map { " MangaBaka final volume \($0.finalVolume) may be behind local Vol \($0.localHighestVolume); not used as a blocker." } ?? ""
        if hasCollision {
            return "Another file already uses the target name, so duplicate handling is required.\(volumeNote)"
        }
        if needsProviderTitleReview {
            return "ComicInfo has a provider volume/chapter title for this number, but it does not clearly match the local title.\(volumeNote)"
        }
        if needsManualReview {
            return "ComicInfo provides the title, but the volume/chapter suffix is ambiguous.\(volumeNote)"
        }
        if droppedProviderTitleForLength {
            return "ComicInfo provides a trusted provider volume title, but it is too long for a calm filename. The plan keeps the volume number and drops the oversized subtitle.\(volumeNote)"
        }
        if usedProviderTitle {
            return "ComicInfo title and deterministic volume parsing agree; the sidecar adds a trusted volume title from provider metadata.\(volumeNote)"
        }
        return "ComicInfo title and deterministic volume/chapter parsing agree.\(volumeNote)"
    }

    private func enrichedReadingSuffix(
        _ suffix: String?,
        matchedPart: ReadingPartNameMetadata?,
        series: LibrarySeriesSnapshot,
        service: SableLibraryService
    ) -> (suffix: String?, usedProviderTitle: Bool, needsTitleConflictReview: Bool) {
        guard let suffix,
              let volume = service.volumeNumber(in: suffix),
              let knownPart = matchedPart else {
            return (suffix, false, false)
        }
        let scopedSuffix = scopedReadingSubtitle(
            from: knownPart.title,
            series: series,
            localVolumeNumber: volume,
            service: service
        ).map { "Vol \(paddedVolume(volume)) - \($0)" }
        let knownSuffix = scopedSuffix ?? knownPart.bestFileSuffix(localVolumeNumber: volume, service: service)
        guard let knownSuffix,
              !knownSuffix.isEmpty else {
            return (suffix, false, false)
        }

        guard !suffixContainsPartTitle(suffix) else {
            return (
                suffix,
                false,
                readingPartTitleMismatch(
                    localSuffix: suffix,
                    providerSuffix: knownSuffix,
                    service: service
                )
            )
        }
        let providerSuffix = providerFileNameSuffix(from: knownSuffix, service: service)
        return (providerSuffix, providerSuffix != suffix, false)
    }

    private func paddedVolume(_ number: Int) -> String {
        String(format: "%02d", number)
    }

    private func providerFileNameSuffix(from suffix: String, service: SableLibraryService) -> String {
        let compacted = suffix
            .replacingOccurrences(of: #"\s*~[^~]+~\s*"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s*[-–—:]\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return service.sanitizeFilename(compacted.isEmpty ? suffix : compacted)
    }

    private func fileNameIsTooLong(_ fileName: String) -> Bool {
        fileName.utf8.count > maximumFileNameUTF8Bytes
    }

    private func shortenedFileName(_ fileName: String) -> String {
        guard fileNameIsTooLong(fileName) else { return fileName }
        let nsName = fileName as NSString
        let fileExtension = nsName.pathExtension
        let extensionSuffix = fileExtension.isEmpty ? "" : ".\(fileExtension)"
        let maximumBaseBytes = max(1, maximumFileNameUTF8Bytes - extensionSuffix.utf8.count)
        var baseName = nsName.deletingPathExtension
        while baseName.utf8.count > maximumBaseBytes {
            baseName.removeLast()
        }
        baseName = baseName.trimmingCharacters(
            in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".-"))
        )
        return "\(baseName)\(extensionSuffix)"
    }

    private func suffixContainsPartTitle(_ suffix: String) -> Bool {
        suffix.range(
            of: #"(?i)^(?:vol(?:ume)?|v|ch(?:apter)?)\.?\s+\d{1,4}(?:\s*[-–—]\s*\d{1,4})?\s*[-–—:]\s*\S"#,
            options: .regularExpression
        ) != nil
    }

    private func partTitle(from suffix: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"(?i)^(?:(?:vol(?:ume)?|v|ch(?:apter)?)\.?\s+\d{1,4})(?:\s*[-–—]\s*\d{1,4})?\s*[-–—:]\s*(.+?)\s*$"#),
              let match = regex.firstMatch(in: suffix, range: NSRange(suffix.startIndex..<suffix.endIndex, in: suffix)),
              let titleRange = Range(match.range(at: 1), in: suffix) else {
            return nil
        }
        let title = String(suffix[titleRange])
        return title.isEmpty ? nil : title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func readingPartTitleMismatch(
        localSuffix: String,
        providerSuffix: String,
        service: SableLibraryService
    ) -> Bool {
        guard let localTitle = partTitle(from: localSuffix),
              let providerTitle = partTitle(from: providerSuffix) else {
            return false
        }
        let localKey = service.normalizeTerm(localTitle)
        let providerKey = service.normalizeTerm(providerTitle)
        guard !localKey.isEmpty, !providerKey.isEmpty else { return false }
        if localKey == providerKey {
            return false
        }
        if localKey.contains(providerKey) || providerKey.contains(localKey) {
            return false
        }
        return true
    }

    private func matchedReadingPart(
        for series: LibrarySeriesSnapshot,
        suffix: String?,
        knownPartNames: [Int: ReadingPartNameMetadata],
        service: SableLibraryService
    ) -> ReadingPartNameMetadata? {
        guard let suffix,
              let localVolumeNumber = service.volumeNumber(in: suffix) else {
            return nil
        }

        let directPart = knownPartNames[localVolumeNumber]
        if let directPart,
           readingPart(directPart, fits: series, localVolumeNumber: localVolumeNumber, service: service) {
            return directPart
        }

        let scopedPart = knownPartNames.values
            .sorted { lhs, rhs in
                if lhs.number == rhs.number {
                    return (lhs.title ?? "").localizedStandardCompare(rhs.title ?? "") == .orderedAscending
                }
                return lhs.number < rhs.number
            }
            .first {
                readingPart($0, fits: series, localVolumeNumber: localVolumeNumber, service: service)
            }

        return scopedPart ?? directPart
    }

    private func readingPart(
        _ part: ReadingPartNameMetadata,
        fits series: LibrarySeriesSnapshot,
        localVolumeNumber: Int,
        service: SableLibraryService
    ) -> Bool {
        guard let title = part.title,
              let titleSuffix = service.volumeOrChapterSuffix(in: title),
              service.volumeNumber(in: titleSuffix) == localVolumeNumber else {
            return false
        }

        let scopeMarkers = readingScopeMarkers(for: series, service: service)
        guard !scopeMarkers.isEmpty else { return true }

        let titleKey = service.normalizeTerm(title)
        return scopeMarkers.contains { titleKey.contains($0) }
    }

    private func readingScopeMarkers(
        for series: LibrarySeriesSnapshot,
        service: SableLibraryService
    ) -> Set<String> {
        let values = [
            series.preferredTitle,
            series.localTitle,
            series.displayName,
            (series.path as NSString).lastPathComponent
        ].compactMap { $0 }

        var markers = Set<String>()
        for value in values {
            let normalized = service.normalizeTerm(value)
            markers.formUnion(regexMatches(#"\bpart\s+\d{1,3}\b"#, in: normalized))
            markers.formUnion(regexMatches(#"\bbook\s+\d{1,3}\b"#, in: normalized))
        }
        return markers
    }

    private func regexMatches(_ pattern: String, in value: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.matches(in: value, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: value) else { return nil }
            return String(value[matchRange])
        }
    }

    private func scopedReadingSubtitle(
        from title: String?,
        series: LibrarySeriesSnapshot,
        localVolumeNumber: Int,
        service: SableLibraryService
    ) -> String? {
        guard let title else { return nil }
        let markers = readingScopeMarkers(for: series, service: service)
        guard !markers.isEmpty else { return nil }

        for marker in markers.sorted() {
            let markerPattern = NSRegularExpression.escapedPattern(for: marker)
                .replacingOccurrences(of: #"\ "#, with: #"\s+"#)
            let pattern = #"\b"# + markerPattern + #"\b\s*[:\-–—]\s*(.+?)\s+(?:vol(?:ume)?|v)\.?\s*0*"# + String(localVolumeNumber) + #"\b"#
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let range = NSRange(title.startIndex..<title.endIndex, in: title)
            guard let match = regex.firstMatch(in: title, range: range),
                  let titleRange = Range(match.range(at: 1), in: title) else {
                continue
            }
            let subtitle = service.sanitizeFilename(String(title[titleRange]))
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ":-–—")))
            if !subtitle.isEmpty {
                return subtitle
            }
        }
        return nil
    }

    private func readingPartNames(
        for series: LibrarySeriesSnapshot,
        root: URL,
        config: SableLibraryConfig,
        service: SableLibraryService
    ) -> [Int: ReadingPartNameMetadata] {
        guard series.hasComicInfo else { return [:] }
        let url = root
            .appendingPathComponent(series.path, isDirectory: true)
            .appendingPathComponent(config.comicInfoFileName)
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data),
              let comicInfo = object as? [String: Any],
              let volumes = comicInfo["volumes"] as? [[String: Any]] else {
            return [:]
        }

        return volumes.reduce(into: [Int: ReadingPartNameMetadata]()) { partialResult, volume in
            guard let number = integerValue(volume["number"]) else {
                return
            }
            partialResult[number] = ReadingPartNameMetadata(
                number: number,
                sourceID: sourceID(from: volume["source_id"], service: service),
                title: service.textValue(volume["title"]),
                subtitle: service.textValue(volume["subtitle"]),
                fileSuffix: service.textValue(volume["file_suffix"])
            )
        }
    }

    private func sourceID(from value: Any?, service: SableLibraryService) -> SableLibrarySourceID? {
        guard let dictionary = value as? [String: Any],
              let providerName = service.textValue(dictionary["provider"]),
              let provider = SableLibraryMetadataProvider(rawValue: providerName),
              let idValue = service.textValue(dictionary["value"]),
              !idValue.isEmpty else {
            return nil
        }
        return SableLibrarySourceID(provider: provider, value: idValue)
    }

    private func integerValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let integer = value as? Int {
            return integer
        }
        guard let string = value as? String else { return nil }
        return Int(string.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func localVolumeConflict(in series: LibrarySeriesSnapshot) -> SableLibraryVolumeConflict? {
        guard let finalVolume = series.finalVolume,
              let localHighestVolume = series.localHighestVolume,
              localHighestVolume > finalVolume else {
            return nil
        }
        return SableLibraryVolumeConflict(finalVolume: finalVolume, localHighestVolume: localHighestVolume)
    }

    private func fileExtensionSuffix(_ fileExtension: String) -> String {
        guard !fileExtension.isEmpty else { return "" }
        return fileExtension.hasPrefix(".") ? fileExtension.lowercased() : ".\(fileExtension.lowercased())"
    }
}
