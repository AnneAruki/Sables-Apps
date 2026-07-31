//
//  SableLibraryStep3ComicInfo.swift
//  Sable's Library
//

import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

nonisolated struct SableLibraryStep3ComicInfo: Sendable {
    private struct IndexedPlanItemResult: Sendable {
        var index: Int
        var path: String
        var item: LibraryPlanItem?
    }

    private enum CoverManifestReadiness {
        case missing
        case incomplete(String)
        case noResult(String)
        case conflict(String)
        case unverified(String)
        case needsStoreCheck(String)
        case replacementNoResult(String)
        case belowClinicQuality(String)
        case complete

        var reviewTag: String {
            switch self {
            case .missing:
                "cover-manifest-missing"
            case .incomplete:
                "cover-manifest-incomplete"
            case .noResult:
                "cover-manifest-no-result"
            case .conflict:
                "cover-manifest-conflict"
            case .unverified:
                "cover-manifest-unverified"
            case .needsStoreCheck:
                "cover-manifest-needs-store-check"
            case .replacementNoResult:
                "cover-manifest-unproven-no-result"
            case .belowClinicQuality:
                "cover-manifest-below-clinic-quality"
            case .complete:
                "cover-manifest-present"
            }
        }
    }

    private let metadataLookupService = SableLibraryMetadataLookupService()
    private let coverDownloadService = SableLibraryCoverDownloadService()
    private let providerGapReviewSchemaVersion = 4
    private let exactIDBatchRefreshTag = "metadata-exact-id-batch"
    private let exactIDRefreshEvidenceTag = "metadata-exact-id-refresh"
    private let ranobeDBSeriesRefreshTag = "metadata-ranobedb-series-refresh"
    private let ranobeDBBookDetailRefreshTag = "metadata-ranobedb-book-detail-refresh"
    private let coverDownloadReviewTag = "metadata-cover-download"
    private var exactIDBatchMaxParallelism: Int {
        SableLibraryAdaptiveWorkBudget.parallelism(minimum: 16, multiplier: 3, cap: 32)
    }
    private func coverDownloadMaxParallelism(
        for pass: SableLibraryCoverDownloadPass
    ) -> Int {
        switch pass {
        case .mangaBakaBaseline:
            SableLibraryAdaptiveWorkBudget.parallelism(
                minimum: 4,
                multiplier: 2,
                cap: 8
            )
        case .combined, .storeQualityUpgrade:
            SableLibraryAdaptiveWorkBudget.parallelism(
                minimum: 1,
                multiplier: 1,
                cap: 2
            )
        }
    }

    private func coverDownloadSeriesTimeout(
        for pass: SableLibraryCoverDownloadPass
    ) -> Duration {
        pass == .mangaBakaBaseline ? .seconds(120) : .seconds(240)
    }

    func prepare(context: LibraryPipelineContext, service: SableLibraryService) async -> [LibraryPlanGroup] {
        service.reportProgress("Preparing ComicInfo and AnimeInfo plan")
        guard let inspection = context.inspection else { return [] }

        let config = service.currentConfig()
        var groups: [LibraryPlanGroup] = []
        let planningPassCount = 7

        let createItems = createComicInfoItems(
            inspection: inspection,
            context: context,
            config: config,
            service: service
        )
        reportMetadataPlanningProgress(
            service: service,
            message: "Prepared reading sidecar creation pass.",
            completed: 1,
            total: planningPassCount
        )
        let choiceItems = createItems.filter(isMetadataChoiceItem)
        let readyCreateItems = createItems.filter { !isMetadataChoiceItem($0) }
        if !choiceItems.isEmpty {
            groups.append(
                LibraryPlanGroup(
                    stage: .comicInfo,
                    title: "Choose Metadata Matches",
                    summary: "\(choiceItems.count) reading group(s) need a provider match, local-title choice, or type correction before Sable spends time searching specialist catalogs.",
                    reviewPrompt: "Use Find Provider Match, give an exact provider URL or ID, choose Use Local, or leave the row unchecked.",
                    examples: examples(from: choiceItems, title: "Needs metadata choice"),
                    items: choiceItems
                )
            )
        }

        if !readyCreateItems.isEmpty {
            let usesMangaBaka = context.options.stages.useMangaBaka
            let usesReadingMetadataProviders = context.options.stages.useMetadataProviders
            groups.append(
                LibraryPlanGroup(
                    stage: .comicInfo,
                    title: usesMangaBaka
                        ? usesReadingMetadataProviders ? "Create Reading ComicInfo - Identity Pass" : "Create Reading ComicInfo from MangaBaka"
                        : usesReadingMetadataProviders ? "Create Reading ComicInfo with Metadata Providers" : "Create Local ComicInfo",
                    summary: usesMangaBaka && usesReadingMetadataProviders
                        ? "\(readyCreateItems.count) series group(s) are missing \(config.comicInfoFileName). Checked rows prefer RanobeDB for light novels, MangaBaka for manga, and Open Library/Wikidata for ordinary prose; the refresh checkpoint can fill book details from saved IDs."
                        : usesMangaBaka
                        ? "\(readyCreateItems.count) series group(s) are missing \(config.comicInfoFileName). Checked rows look up MangaBaka during apply, then write the best match."
                        : usesReadingMetadataProviders
                        ? "\(readyCreateItems.count) series group(s) are missing \(config.comicInfoFileName). Checked rows can add prose or light-novel provider details when confidence is strong."
                        : "\(readyCreateItems.count) series group(s) can get a local \(config.comicInfoFileName) made from the folder name.",
                    reviewPrompt: usesMangaBaka && usesReadingMetadataProviders
                        ? "This checkpoint writes confident sidecars and saves provider identity. Crowded or provider-split matches stay reviewable instead of being accepted quietly."
                        : usesMangaBaka
                        ? "Checked rows may search MangaBaka during apply. Uncheck wrong folders; the receipt will say which matches were written or skipped."
                        : usesReadingMetadataProviders
                        ? "Checked rows may use enabled reading metadata providers during apply only when title evidence is strong enough for quiet enrichment."
                        : "Checked rows write a local sidecar inside each folder without contacting providers.",
                    examples: examples(from: readyCreateItems, title: usesMangaBaka ? "MangaBaka ComicInfo" : usesReadingMetadataProviders ? "Provider ComicInfo" : "Local ComicInfo"),
                    items: readyCreateItems
                )
            )
        }

        let titleCleanupItems = comicInfoTitleCleanupItems(
            inspection: inspection,
            config: config,
            service: service
        )
        reportMetadataPlanningProgress(
            service: service,
            message: "Prepared ComicInfo title cleanup pass.",
            completed: 2,
            total: planningPassCount
        )
        if !titleCleanupItems.isEmpty {
            groups.append(
                LibraryPlanGroup(
                    stage: .comicInfo,
                    title: "Clean ComicInfo Titles",
                    summary: "\(titleCleanupItems.count) sidecar title(s) look like provider book titles instead of series titles.",
                    reviewPrompt: "This is a local-only preflight cleanup. It trims obvious Vol. 1 / Volume 1 suffixes before provider refresh or folder sorting.",
                    examples: examples(from: titleCleanupItems, title: "Sidecar title cleanup"),
                    quickVerifyAfterApply: false,
                    items: titleCleanupItems
                )
            )
        }

        let cleanerItems = await comicInfoCleanerItems(
            inspection: inspection,
            root: context.root,
            config: config,
            service: service
        )
        reportMetadataPlanningProgress(
            service: service,
            message: "Prepared ComicInfo cleaner pass.",
            completed: 3,
            total: planningPassCount
        )
        if !cleanerItems.isEmpty {
            groups.append(
                LibraryPlanGroup(
                    stage: .comicInfo,
                    title: "ComicInfo Cleaner",
                    summary: "\(cleanerItems.count) sidecar file(s) have provider notes or rejected search traces that can be organized locally.",
                    reviewPrompt: "Local-only cleanup. Sable keeps accepted IDs, V2 titles, tags, links, covers, and trusted evidence, then removes stale review clutter and rejected search traces.",
                    examples: examples(from: cleanerItems, title: "Sidecar data cleanup"),
                    quickVerifyAfterApply: false,
                    items: cleanerItems
                )
            )
        }

        let pendingWatchingRawPreparation = hasPendingWatchingRawPreparation(in: context.plan, config: config)
        let animeCleanerItems = pendingWatchingRawPreparation ? [] : animeInfoCleanerItems(
            inspection: inspection,
            root: context.root,
            config: config,
            service: service
        )
        reportMetadataPlanningProgress(
            service: service,
            message: "Prepared AnimeInfo cleaner pass.",
            completed: 4,
            total: planningPassCount
        )
        if !animeCleanerItems.isEmpty {
            groups.append(
                LibraryPlanGroup(
                    stage: .comicInfo,
                    title: "AnimeInfo Cleaner",
                    summary: "\(animeCleanerItems.count) watching sidecar file(s) have provider notes that can be organized locally.",
                    reviewPrompt: "Local-only cleanup. Sable keeps accepted IDs, titles, covers, evidence, Plex hints, and freshness, then removes stale review clutter.",
                    examples: examples(from: animeCleanerItems, title: "Watching sidecar cleanup"),
                    quickVerifyAfterApply: false,
                    items: animeCleanerItems
                )
            )
        }

        let refreshItems = refreshComicInfoItems(
            inspection: inspection,
            context: context,
            config: config,
            service: service
        )
        reportMetadataPlanningProgress(
            service: service,
            message: "Prepared reading sidecar refresh pass.",
            completed: 5,
            total: planningPassCount
        )
        if !refreshItems.isEmpty {
            groups.append(
                LibraryPlanGroup(
                    stage: .comicInfo,
                    title: "Refresh Saved Provider Data",
                    summary: "\(refreshItems.count) existing ComicInfo file(s) can update saved provider data and discover newly released books.",
                    reviewPrompt: context.options.stages.useMetadataProviders || context.options.stages.useMangaBaka
                        ? "Uses saved provider IDs only. MangaBaka and other enabled providers update their current series data; RanobeDB also adds newly listed books and fetches only book details that are still missing. Existing richer data is kept."
                        : "Checked rows refresh local sidecar snapshots without contacting providers.",
                    examples: examples(from: refreshItems, title: "Saved provider refresh"),
                    quickVerifyAfterApply: false,
                    items: refreshItems
                )
            )
        }

        let createAnimeItems = createAnimeInfoItems(
            inspection: inspection,
            context: context,
            config: config,
            service: service
        )
        reportMetadataPlanningProgress(
            service: service,
            message: "Prepared watching sidecar creation pass.",
            completed: 6,
            total: planningPassCount
        )
        if !createAnimeItems.isEmpty {
            groups.append(
                LibraryPlanGroup(
                    stage: .comicInfo,
                    title: "Create Watching AnimeInfo",
                    summary: context.options.stages.useMetadataProviders
                        ? "\(createAnimeItems.count) watching folder(s) can get \(config.animeInfoFileName). Checked rows may contact enabled metadata providers during apply; weak matches still write a local sidecar and leave provider IDs for review."
                        : "\(createAnimeItems.count) watching folder(s) can get a local \(config.animeInfoFileName) made from the folder and video files.",
                    reviewPrompt: context.options.stages.useMetadataProviders
                        ? "Checked rows may contact enabled watching providers during apply. Weak matches write local AnimeInfo without guessed provider IDs."
                        : "Checked rows write local AnimeInfo without contacting outside services.",
                    examples: examples(from: createAnimeItems, title: "AnimeInfo"),
                    items: createAnimeItems
                )
            )
        }

        let refreshAnimeItems = refreshAnimeInfoItems(
            inspection: inspection,
            context: context,
            config: config
        )
        reportMetadataPlanningProgress(
            service: service,
            message: "Prepared watching sidecar refresh pass.",
            completed: 7,
            total: planningPassCount
        )
        if !refreshAnimeItems.isEmpty {
            groups.append(
                LibraryPlanGroup(
                    stage: .comicInfo,
                    title: "Refresh Watching Details",
                    summary: "\(refreshAnimeItems.count) existing AnimeInfo file(s) can refresh from enabled metadata providers during apply.",
                    reviewPrompt: "Checked rows refresh from enabled providers only when evidence is strong. Weak matches keep the existing sidecar unchanged except for the local snapshot.",
                    examples: examples(from: refreshAnimeItems, title: "AnimeInfo refresh"),
                    items: refreshAnimeItems
                )
            )
        }

        return groups
    }

    func prepareCovers(context: LibraryPipelineContext, service: SableLibraryService) async -> [LibraryPlanGroup] {
        service.reportProgress("Preparing series cover download plan")
        guard let inspection = context.inspection else { return [] }

        let config = service.currentConfig()
        let items = coverDownloadItems(
            inspection: inspection,
            context: context,
            config: config,
            service: service
        )
        guard !items.isEmpty else {
            service.reportProgress("Covers: no reading series are ready for cover lookup")
            return []
        }

        service.reportProgress(
            "Covers: audited \(inspection.series.count) series and prepared "
                + "\(items.count) language-specific result(s)"
        )
        let reviewPrompt = "The quick audit is local-only: it checks every saved manifest, file, language, volume, media type, store proof URL, and duplicate image assignment without contacting providers. Fill with MangaBaka is the fast baseline pass for gaps. Find Quality Upgrades is a separate slower store pass. Active cover files are reused; stale generated images are removed after the completed manifest is safely saved. Correct covers at least 500 x 700 are archived. Clinic keeps its stricter 800 x 1100 quality control before replacing an EPUB cover."
        let readinessLanes: [(tag: String, title: String, summary: (String, Int) -> String)] = [
            (
                "cover-manifest-missing",
                "Ready to Find Covers",
                { language, count in "\(count) series have not been searched for \(language.lowercased()) covers yet." }
            ),
            (
                "cover-manifest-incomplete",
                "Cover Gaps to Retry",
                { language, count in "\(count) series already have some \(language.lowercased()) cover data but are still missing a usable volume cover." }
            ),
            (
                "cover-manifest-conflict",
                "Cover Conflicts to Repair",
                { language, count in "\(count) series have a saved \(language.lowercased()) cover whose volume, language, media type, or provider identity conflicts with the local book." }
            ),
            (
                "cover-manifest-no-result",
                "MangaBaka Baseline Finished, Gaps Remain",
                { language, count in "\(count) series completed the MangaBaka baseline for \(language.lowercased()) covers, but MangaBaka could not fill every local volume slot. Nothing is stuck or still running; use the separate store-quality pass when you want to look for replacements or missing editions." }
            ),
            (
                "cover-manifest-unverified",
                "Ready to Verify Existing Covers",
                { language, count in "\(count) series already have complete local \(language.lowercased()) cover files. Sable can repair their older store evidence without replacing or redownloading the images." }
            ),
            (
                "cover-manifest-needs-store-check",
                "Unproven Covers to Replace",
                { language, count in "Store proof found \(count) series with \(language.lowercased()) covers it could not confirm. Checked rows search for trusted replacements while keeping the old images as fallbacks." }
            ),
            (
                "cover-manifest-unproven-no-result",
                "Replacement Search Finished, No Trusted Match",
                { language, count in "\(count) series finished a real \(language.lowercased()) replacement search, but no trusted match was found. Existing images were kept as fallbacks and nothing is still running." }
            ),
            (
                "cover-manifest-below-clinic-quality",
                "Covers Found Below Clinic Quality",
                { language, count in "\(count) series have complete archived \(language.lowercased()) covers, but at least one is below Clinic's 800 x 1100 replacement floor." }
            ),
            (
                "cover-manifest-present",
                "Complete Cover Sets",
                { language, count in "\(count) series already have complete \(language.lowercased()) normal cover sets. Refreshing these is optional." }
            )
        ]

        let languageLanes: [(code: String, tag: String, label: String)] = [
            ("jp", "cover-language-jp", "Japanese"),
            ("en", "cover-language-en", "English")
        ]
        var groups: [LibraryPlanGroup] = []
        for language in languageLanes {
            for lane in readinessLanes {
                let laneItems = items.filter {
                    $0.reviewTags.contains(language.tag)
                        && $0.reviewTags.contains(lane.tag)
                }
                guard !laneItems.isEmpty else { continue }
                let laneReviewPrompt: String
                switch lane.tag {
                case "cover-manifest-present":
                    laneReviewPrompt = "Verified complete \(language.label.lowercased()) cover sets stay unchecked after scans and refreshes. Select them only when you deliberately want the separate store-quality pass to look for better images."
                case "cover-manifest-unverified":
                    laneReviewPrompt = "No cover files are missing here. Checked rows only read their saved store product pages and update cover-manifest.json. Images are never replaced or redownloaded. Anything the store cannot prove moves to Unproven Covers to Replace."
                case "cover-manifest-needs-store-check":
                    laneReviewPrompt = "Store proof already finished. Checked rows now perform a real cover search, not another proof-only pass. A trusted result replaces the unproven manifest assignment; the old image remains untouched unless a safe replacement is accepted."
                case "cover-manifest-unproven-no-result":
                    laneReviewPrompt = "These replacement searches are finished, not waiting. Use Find Cover to choose an exact store series, then check only the rows you deliberately want to retry. Existing fallback images remain untouched."
                case "cover-manifest-below-clinic-quality":
                    laneReviewPrompt = "These are valid archived covers and stay unchecked. Clinic will not use them to replace EPUB covers. Check a row only when you want to look again for a higher-resolution version."
                case "cover-manifest-conflict":
                    laneReviewPrompt = "Checked rows reuse verified covers and search only the conflicting or missing \(language.label.lowercased()) slots. Existing files are preserved until the replacement manifest is safely written."
                case "cover-manifest-no-result":
                    laneReviewPrompt = "MangaBaka was genuinely checked for these \(language.label.lowercased()) gaps. Use Find Quality Upgrades to try BookLive, BookWalker, and Amazon, or Add Match when you know the exact store series. A store-only failure can no longer put a row here."
                default:
                    laneReviewPrompt = reviewPrompt
                }
                let title = "\(language.label) \(lane.title)"
                groups.append(
                    LibraryPlanGroup(
                        stage: .covers,
                        title: title,
                        summary: lane.summary(language.label, laneItems.count),
                        reviewPrompt: laneReviewPrompt,
                        examples: examples(from: laneItems, title: title),
                        quickVerifyAfterApply: false,
                        items: laneItems
                    )
                )
            }
        }
        return groups
    }

    func prepareProviderMatches(context: LibraryPipelineContext, service: SableLibraryService) async -> [LibraryPlanGroup] {
        service.reportProgress("Preparing provider match teaching plan")
        guard let inspection = context.inspection else { return [] }

        let config = service.currentConfig()
        let readingGapGroups = manualReadingProviderGapGroups(
            inspection: inspection,
            context: context,
            config: config
        )
        reportMetadataPlanningProgress(
            service: service,
            title: "Preparing provider matches",
            message: "Prepared reading provider choice pass.",
            completed: 1,
            total: 3
        )
        let matchedWatchingGroups = matchedWatchingProviderGroups(
            inspection: inspection,
            context: context,
            config: config
        )
        reportMetadataPlanningProgress(
            service: service,
            title: "Preparing provider matches",
            message: "Prepared matched watching provider pass.",
            completed: 2,
            total: 3
        )
        let watchingGapGroups = manualWatchingProviderGapGroups(
            inspection: inspection,
            context: context,
            config: config
        )
        reportMetadataPlanningProgress(
            service: service,
            title: "Preparing provider matches",
            message: "Prepared watching provider choice pass.",
            completed: 3,
            total: 3
        )
        return readingGapGroups + matchedWatchingGroups + watchingGapGroups
    }

    private func reportMetadataPlanningProgress(
        service: SableLibraryService,
        title: String = "Preparing metadata sidecars",
        message: String,
        completed: Int,
        total: Int
    ) {
        guard total > 0 else { return }
        service.reportProgressSnapshot(SableLibraryProgressSnapshot(
            title: title,
            message: message,
            completedUnitCount: completed,
            totalUnitCount: total
        ))
    }

    private func comicInfoTitleCleanupItems(
        inspection: LibraryInspection,
        config: SableLibraryConfig,
        service: SableLibraryService
    ) -> [LibraryPlanItem] {
        inspection.series
            .filter(\.hasComicInfo)
            .compactMap { series -> LibraryPlanItem? in
                guard let currentTitle = series.preferredTitle,
                      let repairedTitle = sidecarTitleRepairCandidate(
                        currentTitle: currentTitle,
                        localTitle: series.localTitle ?? organizerTitle(
                            from: URL(fileURLWithPath: series.path).lastPathComponent,
                            service: service
                        ),
                        service: service
                      ) else {
                    return nil
                }

                let comicInfoPath = comicInfoPath(for: series.path, config: config)
                return LibraryPlanItem(
                    stage: .comicInfo,
                    operation: .refreshComicInfo,
                    currentPath: series.path,
                    proposedPath: comicInfoPath,
                    reason: "Local cleanup will change the sidecar title from \(currentTitle) to \(repairedTitle).",
                    confidence: .medium,
                    safety: .reversible,
                    decision: .unchecked,
                    requiresReview: false,
                    usedNetworkData: false,
                    metadataProviders: [],
                    confidenceExplanation: "No provider calls. Sable only trims a clear provider volume marker when the local series title confirms the series name.",
                    correctionOptions: [.keepTitle, .custom],
                    reviewTags: [
                        "company.lazycompany",
                        "department.sidecarrelations",
                        "department.readinglibrary",
                        "metadata-pass",
                        "metadata-preflight-cleanup",
                        "metadata-title-cleanup",
                        "metadata-local-only"
                    ],
                    receipt: "Clean ComicInfo title for \(series.path)"
                )
            }
    }

    private func comicInfoCleanerItems(
        inspection: LibraryInspection,
        root: URL,
        config: SableLibraryConfig,
        service: SableLibraryService
    ) async -> [LibraryPlanItem] {
        let seriesWithSidecars = inspection.series.filter(\.hasComicInfo)
        guard !seriesWithSidecars.isEmpty else { return [] }

        let parallelism = SableLibraryAdaptiveWorkBudget.parallelism(
            minimum: 2,
            multiplier: 1,
            cap: 4,
            itemCount: seriesWithSidecars.count
        )
        return await withTaskGroup(
            of: IndexedPlanItemResult.self,
            returning: [LibraryPlanItem].self
        ) { group in
            let initialCount = min(parallelism, seriesWithSidecars.count)
            for index in 0..<initialCount {
                let series = seriesWithSidecars[index]
                group.addTask {
                    comicInfoCleanerResult(
                        index: index,
                        series: series,
                        root: root,
                        config: config,
                        service: service
                    )
                }
            }

            var nextIndex = initialCount
            var completedCount = 0
            var results: [IndexedPlanItemResult] = []
            results.reserveCapacity(seriesWithSidecars.count)

            while let result = await group.next() {
                if Task.isCancelled {
                    group.cancelAll()
                    break
                }

                results.append(result)
                completedCount += 1
                if completedCount == 1
                    || completedCount.isMultiple(of: 100)
                    || completedCount == seriesWithSidecars.count {
                    reportMetadataPlanningProgress(
                        service: service,
                        message: "Checking ComicInfo cleaner \(completedCount) of \(seriesWithSidecars.count): \(result.path)",
                        completed: completedCount,
                        total: seriesWithSidecars.count
                    )
                }

                if nextIndex < seriesWithSidecars.count {
                    let index = nextIndex
                    let series = seriesWithSidecars[index]
                    nextIndex += 1
                    group.addTask {
                        comicInfoCleanerResult(
                            index: index,
                            series: series,
                            root: root,
                            config: config,
                            service: service
                        )
                    }
                }
            }

            return results
                .sorted { $0.index < $1.index }
                .compactMap(\.item)
        }
    }

    private func comicInfoCleanerResult(
        index: Int,
        series: LibrarySeriesSnapshot,
        root: URL,
        config: SableLibraryConfig,
        service: SableLibraryService
    ) -> IndexedPlanItemResult {
        let comicInfoPath = comicInfoPath(for: series.path, config: config)
        let comicInfoURL = root.appendingPathComponent(comicInfoPath)
        guard let sidecar = readComicInfo(url: comicInfoURL) else {
            return IndexedPlanItemResult(index: index, path: series.path, item: nil)
        }

        let reasons = comicInfoCleanerReasons(in: sidecar, service: service)
        guard !reasons.isEmpty else {
            return IndexedPlanItemResult(index: index, path: series.path, item: nil)
        }

        let reasonText = reasons.prefix(3).joined(separator: "; ")
        let extraCount = reasons.count - min(reasons.count, 3)
        let suffix = extraCount > 0 ? "; \(extraCount) more tidy-up item\(extraCount == 1 ? "" : "s")" : ""
        let item = LibraryPlanItem(
            stage: .comicInfo,
            operation: .refreshComicInfo,
            currentPath: series.path,
            proposedPath: comicInfoPath,
            reason: "Optional ComicInfo cleanup can tidy \(config.comicInfoFileName): \(reasonText)\(suffix).",
            confidence: .high,
            safety: .reversible,
            decision: .unchecked,
            requiresReview: false,
            usedNetworkData: false,
            metadataProviders: [],
            confidenceExplanation: "Local-only ML-assisted data housekeeping. Sable keeps accepted provider IDs, V2 titles, tags, links, cover URLs, and trusted evidence, then removes stale review notes, scratch queries, and rejected provider traces.",
            correctionOptions: [.keepTitle],
            reviewTags: [
                "company.lazycompany",
                "department.sidecarrelations",
                "department.readinglibrary",
                "metadata-pass",
                "metadata-comicinfo-cleaner",
                "metadata-optional-cleaner",
                "metadata-provider-data-cleaner",
                "metadata-cover-prep",
                "metadata-local-only",
                "ml-provider-data-cleaner"
            ],
            receipt: "Clean ComicInfo provider data for \(series.path)"
        )
        return IndexedPlanItemResult(
            index: index,
            path: series.path,
            item: item
        )
    }

    private func animeInfoCleanerItems(
        inspection: LibraryInspection,
        root: URL,
        config: SableLibraryConfig,
        service: SableLibraryService
    ) -> [LibraryPlanItem] {
        let seriesWithSidecars = inspection.videoSeries.filter(\.hasAnimeInfo)
        var items: [LibraryPlanItem] = []
        for (index, series) in seriesWithSidecars.enumerated() {
            guard !Task.isCancelled else { break }
            let completed = index + 1
            if completed == 1 || completed.isMultiple(of: 100) || completed == seriesWithSidecars.count {
                reportMetadataPlanningProgress(
                    service: service,
                    message: "Checking AnimeInfo cleaner \(completed) of \(seriesWithSidecars.count): \(series.path)",
                    completed: completed,
                    total: seriesWithSidecars.count
                )
            }

            let animeInfoPath = animeInfoPath(for: series.path, config: config)
            let animeInfoURL = root.appendingPathComponent(animeInfoPath)
            guard let sidecar = readComicInfo(url: animeInfoURL) else { continue }

            let reasons = animeInfoCleanerReasons(in: sidecar, config: config, service: service)
            guard !reasons.isEmpty else { continue }

            let reasonText = reasons.prefix(3).joined(separator: "; ")
            let extraCount = reasons.count - min(reasons.count, 3)
            let suffix = extraCount > 0 ? "; \(extraCount) more tidy-up item\(extraCount == 1 ? "" : "s")" : ""
            items.append(
                LibraryPlanItem(
                    stage: .comicInfo,
                    operation: .refreshAnimeInfo,
                    currentPath: series.path,
                    proposedPath: animeInfoPath,
                    reason: "Optional AnimeInfo cleanup can organize provider data: \(reasonText)\(suffix).",
                    confidence: .high,
                    safety: .reversible,
                    decision: .unchecked,
                    requiresReview: false,
                    usedNetworkData: false,
                    metadataProviders: [],
                    confidenceExplanation: "No provider calls. Sable rewrites the sidecar into the current schema, keeps trusted watching metadata, and removes stale review notes that no longer need to guide apply.",
                    correctionOptions: [.keepTitle, .custom],
                    reviewTags: [
                        "company.lazycompany",
                        "department.sidecarrelations",
                        "department.watchinglibrary",
                        "metadata-pass",
                        "metadata-animeinfo-cleaner",
                        "metadata-optional-cleaner",
                        "metadata-provider-data-cleaner",
                        "metadata-cover-prep",
                        "metadata-local-only",
                        "ml-provider-data-cleaner"
                    ],
                    receipt: "Clean AnimeInfo provider data for \(series.path)"
                )
            )
        }
        return items
    }

    private func comicInfoCleanerReasons(
        in sidecar: [String: Any],
        service: SableLibraryService
    ) -> [String] {
        var reasons = sidecarProviderCleanerReasons(in: sidecar, service: service)
        if sidecar["classification"] != nil {
            reasons.append("stale SSS shelf classification can move out of ComicInfo cleanup")
        }
        return uniqueStrings(reasons)
    }

    private func jsonObjectsAreEquivalent(_ lhs: [String: Any], _ rhs: [String: Any]) -> Bool {
        if JSONSerialization.isValidJSONObject(lhs),
           JSONSerialization.isValidJSONObject(rhs),
           let lhsData = try? JSONSerialization.data(withJSONObject: lhs, options: [.sortedKeys]),
           let rhsData = try? JSONSerialization.data(withJSONObject: rhs, options: [.sortedKeys]) {
            return lhsData == rhsData
        }

        return NSDictionary(dictionary: lhs).isEqual(to: rhs)
    }

    private func jsonPayloadData(_ object: Any) -> Data? {
        guard JSONSerialization.isValidJSONObject(object) else { return nil }
        return try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private var stableDigestAlgorithm: String {
        #if canImport(CryptoKit)
        "sha256"
        #else
        "fnv1a64"
        #endif
    }

    private func stableDigest(for data: Data) -> String {
        #if canImport(CryptoKit)
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        #else
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: max(0, 16 - hex.count)) + hex
        #endif
    }

    private func sidecarProviderCleanerReasons(
        in sidecar: [String: Any],
        service: SableLibraryService
    ) -> [String] {
        var reasons: [String] = []
        let ids = normalizedIDDictionary(from: sidecar, service: service)

        if let sable = sidecar["_sable"] as? [String: Any] {
            if let reviews = sable["provider_candidate_review"] as? [String: Any] {
                let resolvedProviders = SableLibraryMetadataProvider.allCases.filter { provider in
                    reviews[provider.rawValue] != nil && hasID(idKey(for: provider), in: ids, service: service)
                }
                if !resolvedProviders.isEmpty {
                    reasons.append("resolved provider questions can be removed")
                }

                let rejectedProviders = reviews.contains { rawKey, value in
                    guard let review = value as? [String: Any],
                          isRejectedProviderReview(review, service: service),
                          let provider = metadataProvider(rawKey: rawKey, review: review, service: service),
                          !hasID(idKey(for: provider), in: ids, service: service) else {
                        return false
                    }
                    return true
                }
                if rejectedProviders {
                    reasons.append("rejected provider matches can move into No ID memory")
                }
            }

            if let availability = sable["provider_availability"] as? [String: Any] {
                let resolvedProviders = SableLibraryMetadataProvider.allCases.filter { provider in
                    availability[provider.rawValue] != nil && hasID(idKey(for: provider), in: ids, service: service)
                }
                if !resolvedProviders.isEmpty {
                    reasons.append("old No ID reminders now have accepted IDs")
                }
            }

            if sable["ml"] != nil {
                reasons.append("old ML scratch notes can be dropped")
            }

            if sidecarHasSableSearchHelperQueries(in: sable, service: service) {
                reasons.append("saved search helper queries can be cleared")
            }

            if sidecarHasBookScopedOpenLibrarySeriesID(sidecar, service: service) {
                reasons.append("book-specific Open Library ID can move into No ID memory")
            }

            if ranobeDBAPISummaryNeedsRefresh(in: sidecar, service: service) {
                reasons.append("RanobeDB API payload summary can be refreshed")
            }

            if sidecarHasCompactableRanobeDBRawAPI(sidecar, service: service) {
                reasons.append("bulky RanobeDB raw API payload can be compacted")
            }

            if sidecarHasRejectedProviderPublicTraces(sidecar, service: service) {
                reasons.append("rejected provider traces can be cleaned from public fields")
            }

            if let enrichment = sable["metadata_enrichment"] as? [String: Any],
               isStaleUntouchedProviderNote(enrichment, service: service) {
                reasons.append("stale failed-refresh note can be cleared")
            }

            let skippedProviderNotes = SableLibraryMetadataProvider.allCases.contains { provider in
                guard let providerBlock = sable[provider.rawValue] as? [String: Any] else { return false }
                return isStaleUntouchedProviderNote(providerBlock, service: service)
            }
            if skippedProviderNotes {
                reasons.append("stale skipped-provider notes can be cleared")
            }
        }

        if SableLibrarySourceIDParser.legacyTopLevelIDKeys.contains(where: { sidecar[$0.0] != nil }) {
            reasons.append("legacy ID fields can move into the clean IDs block")
        }

        if sidecarHasDuplicateTitleListValues(sidecar, key: "aliases", service: service) {
            reasons.append("duplicate title aliases can be compacted")
        }

        if sidecarNeedsTitleVariantLabels(sidecar, service: service) {
            reasons.append("native, romanized, and English title labels can be organized")
        }

        if sidecarHasVolumeTitleVariants(sidecar, service: service) {
            reasons.append("volume-level titles can move out of series title variants")
        }

        if localTitleHasVolumeSuffix(sidecar, service: service) {
            reasons.append("local series title can drop volume-only wording")
        }

        if sidecarHasDuplicateTitleListValues(sidecar, key: "volume_titles", service: service) {
            reasons.append("series-title repeats can be removed from volume titles")
        }

        if service.textValue(sidecar["cover_url"]) == nil,
           nestedSidecarCoverURL(in: sidecar, service: service) != nil {
            reasons.append("cover URL can be normalized for EPUB repair")
        }

        return uniqueStrings(reasons)
    }

    private struct RejectedProviderTrace {
        var providers: Set<String> = []
        var titleKeys: Set<String> = []

        var isEmpty: Bool {
            providers.isEmpty && titleKeys.isEmpty
        }
    }

    private func sidecarHasSableSearchHelperQueries(
        in sable: [String: Any],
        service: SableLibraryService
    ) -> Bool {
        SableLibraryMetadataProvider.allCases.contains { provider in
            guard let providerBlock = sable[provider.rawValue] as? [String: Any] else {
                return false
            }
            return service.textValue(providerBlock["query"]) != nil
        }
    }

    private func rejectedProviderTrace(
        in sidecar: [String: Any],
        service: SableLibraryService
    ) -> RejectedProviderTrace? {
        guard let sable = sidecar["_sable"] as? [String: Any],
              let reviews = sable["provider_candidate_review"] as? [String: Any] else {
            return nil
        }

        let ids = normalizedIDDictionary(from: sidecar, service: service)
        var trace = RejectedProviderTrace()
        for (rawKey, rawValue) in reviews {
            guard let review = rawValue as? [String: Any],
                  isRejectedProviderReview(review, service: service) else {
                continue
            }

            let provider = metadataProvider(rawKey: rawKey, review: review, service: service)
            if let provider,
               hasID(idKey(for: provider), in: ids, service: service) {
                continue
            }

            let rawProvider = provider?.rawValue ?? service.textValue(review["provider"]) ?? rawKey
            trace.providers.formUnion(publicProviderKeys(for: rawProvider))

            for key in [
                "rejected_candidate_title",
                "candidate_title",
                "matched_title",
                "provider_title",
                "title"
            ] {
                addRejectedTitle(review[key], to: &trace, service: service)
            }
            for key in [
                "candidate_aliases",
                "aliases",
                "alternate_titles",
                "secondary_titles",
                "titles"
            ] {
                addRejectedTitle(review[key], to: &trace, service: service)
            }
        }

        return trace.isEmpty ? nil : trace
    }

    private func sidecarHasRejectedProviderPublicTraces(
        _ sidecar: [String: Any],
        service: SableLibraryService
    ) -> Bool {
        guard rejectedProviderTrace(in: sidecar, service: service) != nil else {
            return false
        }

        var pruned = sidecar
        pruneRejectedProviderPublicTraces(in: &pruned, service: service)
        return !jsonObjectsAreEquivalent(pruned, sidecar)
    }

    private func sidecarHasBookScopedOpenLibrarySeriesID(
        _ sidecar: [String: Any],
        service: SableLibraryService
    ) -> Bool {
        let ids = normalizedIDDictionary(from: sidecar, service: service)
        guard service.textValue(ids[idKey(for: .openLibrary)]) != nil,
              hasSpecializedReadingIdentity(ids: ids, service: service) else {
            return false
        }
        return sidecarHasOpenLibraryExactISBNEvidence(sidecar, service: service)
    }

    private func ranobeDBAPISummaryNeedsRefresh(
        in sidecar: [String: Any],
        service: SableLibraryService
    ) -> Bool {
        guard let sable = sidecar["_sable"] as? [String: Any],
              let ranobeDB = sable[SableLibraryMetadataProvider.ranobedb.rawValue] as? [String: Any],
              ranobeDB["api"] is [String: Any] else {
            return false
        }
        let current = ranobeDB["api_summary"] as? [String: Any]
        guard let current else { return true }
        return current["raw_payload_digest"] == nil
            || current["raw_payload_bytes"] == nil
            || current["raw_payload_stored_in_sidecar"] == nil
    }

    private func sidecarHasCompactableRanobeDBRawAPI(
        _ sidecar: [String: Any],
        service: SableLibraryService
    ) -> Bool {
        guard let sable = sidecar["_sable"] as? [String: Any],
              let ranobeDB = sable[SableLibraryMetadataProvider.ranobedb.rawValue] as? [String: Any],
              ranobeDB["api"] is [String: Any] else {
            return false
        }
        return ranobeDB["api_compact"] == nil
            || (ranobeDB["api_summary"] as? [String: Any])?["raw_payload_stored_in_sidecar"] as? Bool != false
    }

    private func moveBookScopedOpenLibraryIDToAvailability(
        in sidecar: inout [String: Any],
        service: SableLibraryService
    ) {
        guard sidecarHasBookScopedOpenLibrarySeriesID(sidecar, service: service) else {
            return
        }

        var ids = normalizedIDDictionary(from: sidecar, service: service)
        let openLibraryID = service.textValue(ids[idKey(for: .openLibrary)])
        ids.removeValue(forKey: idKey(for: .openLibrary))
        if ids.isEmpty {
            sidecar.removeValue(forKey: "ids")
        } else {
            sidecar["ids"] = ids
        }

        var sable = sidecar["_sable"] as? [String: Any] ?? [:]
        var availability = sable["provider_availability"] as? [String: Any] ?? [:]
        var note = availability[SableLibraryMetadataProvider.openLibrary.rawValue] as? [String: Any] ?? [:]
        note["status"] = "not_available"
        note["provider"] = SableLibraryMetadataProvider.openLibrary.rawValue
        note["source"] = "series_scope_not_available"
        note["reason"] = "Open Library exact ISBN evidence is book or volume scoped, so it is not kept as the series identity."
        note["updated_at"] = service.isoTimestamp()
        if let openLibraryID {
            note["rejected_candidate_id"] = openLibraryID
        }
        availability[SableLibraryMetadataProvider.openLibrary.rawValue] = note
        sable["provider_availability"] = availability
        sidecar["_sable"] = sable

        let rejectedProviders: Set<SableLibraryMetadataProvider> = [.openLibrary]
        sidecar["source_freshness"] = filteredProviderDictionaries(
            sidecar["source_freshness"] as? [[String: Any]] ?? [],
            removing: rejectedProviders,
            service: service
        )
        sidecar["match_evidence"] = filteredProviderDictionaries(
            sidecar["match_evidence"] as? [[String: Any]] ?? [],
            removing: rejectedProviders,
            service: service
        )
    }

    private func hasSpecializedReadingIdentity(
        ids: [String: Any],
        service: SableLibraryService
    ) -> Bool {
        hasID(idKey(for: .mangabaka), in: ids, service: service)
            || hasID(idKey(for: .ranobedb), in: ids, service: service)
    }

    private func sidecarHasOpenLibraryExactISBNEvidence(
        _ sidecar: [String: Any],
        service: SableLibraryService
    ) -> Bool {
        guard let evidence = sidecar["match_evidence"] as? [[String: Any]] else {
            return false
        }
        return evidence.contains { row in
            normalizedProviderKey(service.textValue(row["provider"]) ?? "") == normalizedProviderKey(SableLibraryMetadataProvider.openLibrary.rawValue)
                && service.textValue(row["kind"])?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "exactisbn"
        }
    }

    private func isRejectedProviderReview(
        _ review: [String: Any],
        service: SableLibraryService
    ) -> Bool {
        let status = service.textValue(review["status"])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        if status == SableLibraryProviderCandidateReview.Status.noMatch.rawValue
            || status == "no-match"
            || status == "rejected"
            || status.contains("reject") {
            return true
        }

        let source = service.textValue(review["source"])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        let reason = service.textValue(review["reason"])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        return source.contains("trusted_title_conflict")
            || source.contains("title_conflict")
            || reason.contains("trusted title conflict")
            || reason.contains("title conflict")
    }

    private func metadataProvider(
        rawKey: String,
        review: [String: Any],
        service: SableLibraryService
    ) -> SableLibraryMetadataProvider? {
        if let provider = SableLibraryMetadataProvider(rawValue: rawKey) {
            return provider
        }
        guard let rawProvider = service.textValue(review["provider"]) else {
            return nil
        }
        return SableLibraryMetadataProvider(rawValue: rawProvider)
    }

    private func addRejectedTitle(
        _ value: Any?,
        to trace: inout RejectedProviderTrace,
        service: SableLibraryService
    ) {
        if let text = service.textValue(value) {
            let key = service.normalizeTerm(text)
            if !key.isEmpty {
                trace.titleKeys.insert(key)
            }
            return
        }

        if let values = value as? [String] {
            for text in values {
                addRejectedTitle(text, to: &trace, service: service)
            }
            return
        }

        if let rows = value as? [[String: Any]] {
            for row in rows {
                addRejectedTitle(row["title"], to: &trace, service: service)
                addRejectedTitle(row["name"], to: &trace, service: service)
                addRejectedTitle(row["value"], to: &trace, service: service)
            }
            return
        }

        if let row = value as? [String: Any] {
            addRejectedTitle(row["title"], to: &trace, service: service)
            addRejectedTitle(row["name"], to: &trace, service: service)
            addRejectedTitle(row["value"], to: &trace, service: service)
        }
    }

    private func publicProviderKeys(for rawProvider: String) -> Set<String> {
        let normalized = normalizedProviderKey(rawProvider)
        var keys = Set([normalized].filter { !$0.isEmpty })

        switch normalizedProviderKey(rawProvider) {
        case "myanimelist", "mal", "jikan":
            keys.formUnion(["myanimelist", "mal", "jikan"])
        case "openlibrary", "ol":
            keys.formUnion(["openlibrary", "open_library", "ol"])
        case "anilist", "al":
            keys.formUnion(["anilist", "al"])
        case "mangabaka", "mb":
            keys.formUnion(["mangabaka", "mb"])
        case "ranobedb", "rdb", "ranobe":
            keys.formUnion(["ranobedb", "rdb", "ranobe"])
        default:
            break
        }

        return keys.map(normalizedProviderKey)
            .reduce(into: Set<String>()) { partialResult, key in
                if !key.isEmpty {
                    partialResult.insert(key)
                }
            }
    }

    private func normalizedProviderKey(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "", options: .regularExpression)
    }

    private func sidecarHasDuplicateTitleListValues(
        _ sidecar: [String: Any],
        key: String,
        service: SableLibraryService
    ) -> Bool {
        let titleKeys = sidecarSeriesTitleKeys(in: sidecar, includeAliases: key != "aliases", service: service)
        return arrayStrings(sidecar[key], service: service).contains { value in
            titleKeys.contains(service.normalizeTerm(value))
        }
    }

    private func createComicInfoItems(
        inspection: LibraryInspection,
        context: LibraryPipelineContext,
        config: SableLibraryConfig,
        service: SableLibraryService
    ) -> [LibraryPlanItem] {
        let seriesByPath = inspection.series.reduce(into: [String: LibrarySeriesSnapshot]()) { partialResult, series in
            partialResult[series.path] = series
        }
        let booksBySeriesID = Dictionary(grouping: inspection.books) { $0.seriesID ?? "" }
        let missingPaths = inspection.missingComicInfoSeriesPaths.sorted()

        return missingPaths.map { path in
            let series = seriesByPath[path]
            let books = booksBySeriesID[path] ?? []
            let title = series?.displayName ?? URL(fileURLWithPath: path).lastPathComponent
            let comicInfoPath = comicInfoPath(for: path, config: config)
            let providerRoute = readingProviderRoute(
                stages: context.options.stages,
                seriesPath: path,
                series: series,
                books: books,
                service: service
            )
            let readingProviders = providerRoute.providers
            let usesMangaBaka = readingProviders.contains(.mangabaka)
            let usesMetadataProviders = readingProviders.contains { $0 != .mangabaka }
            let networkCaution = usesMangaBaka
                ? mangaBakaCreateCaution(title: title, series: series, config: config)
                : nil
            let reason: String

            if providerRoute.requiresReview {
                reason = "First pass found no strong local type/provider route for \(title). Use Find Provider Match, Use Local, or choose the right type before Sable spends time searching broad catalogs."
            } else if usesMangaBaka && usesMetadataProviders {
                reason = networkCaution?.reason
                    ?? "Apply will ask RanobeDB first for light-novel identity, use MangaBaka first for manga/comics, and keep crowded provider results for review."
            } else if usesMangaBaka {
                reason = networkCaution?.reason
                    ?? "Apply will search MangaBaka for \(title) and write \(config.comicInfoFileName) from the best confident match."
            } else if readingProviders == [.openLibrary] {
                reason = "Metadata pass treats \(title) as ordinary prose. Open Library and Wikidata can help when ISBN, author, year, or manual evidence is strong."
            } else if readingProviders == [.ranobedb] {
                reason = "Metadata pass treats \(title) as light-novel-like and checks RanobeDB for series identity first. The refreshed next pass can add matching book details."
            } else if usesMetadataProviders {
                reason = "Metadata pass creates local \(config.comicInfoFileName) for \(title), then asks the best matching reading provider for enrichment only when evidence is strong."
            } else {
                reason = "Create local \(config.comicInfoFileName) for \(title) from the current folder name. Type remains Unknown until reviewed."
            }

            let decision = providerRoute.requiresReview ? LibraryPlanDecision.unchecked : networkCaution?.decision ?? .checked
            let requiresReview = providerRoute.requiresReview || (networkCaution?.requiresReview ?? false)
            let safety = providerRoute.requiresReview
                ? LibraryPlanSafety.needsChoice
                : networkCaution?.safety ?? .reversible
            let confidence = providerRoute.requiresReview
                ? LibraryPlanConfidence.low
                : networkCaution?.confidence ?? (readingProviders.isEmpty ? .high : .medium)

            return LibraryPlanItem(
                stage: .comicInfo,
                operation: .createComicInfo,
                currentPath: path,
                proposedPath: comicInfoPath,
                reason: reason,
                confidence: confidence,
                safety: safety,
                decision: decision,
                requiresReview: requiresReview,
                usedNetworkData: !readingProviders.isEmpty,
                metadataProviders: readingProviders,
                confidenceExplanation: providerRoute.requiresReview
                    ? providerRoute.explanation
                    : networkCaution?.confidenceExplanation ?? confidenceExplanationForReadingProviders(readingProviders),
                correctionOptions: [.wrongSeries, .wrongType, .keepTitle, .custom],
                reviewTags: sidecarPassReviewTags(
                    providerRoute.reviewTags,
                    operation: .createComicInfo,
                    providers: readingProviders,
                    hasRanobeDBID: seriesHasRanobeDBID(series)
                ),
                receipt: "Prepare \(config.comicInfoFileName) for \(path)"
            )
        }
    }

    private func mangaBakaCreateCaution(
        title: String,
        series: LibrarySeriesSnapshot?,
        config: SableLibraryConfig
    ) -> MangaBakaCreateCaution? {
        let namingPolicy = SableLibraryNamingPolicy()
        let localNames = [
            title,
            series?.path,
            series?.localTitle,
            series?.displayName
        ].compactMap { $0 }
        let hasTypeHint = localNames.contains { namingPolicy.mediaTypeHint(in: $0) != nil }
        guard !hasTypeHint else { return nil }

        return MangaBakaCreateCaution(
            reason: "Apply will search MangaBaka for \(title). If the live results are weak or ambiguous, Sable skips this row without writing \(config.comicInfoFileName).",
            confidence: .low,
            safety: .reversible,
            decision: .checked,
            requiresReview: false,
            confidenceExplanation: "No local media-type hint was found. The API is still usable during apply, but broad searches must produce a confident match before anything is written."
        )
    }

    private func coverDownloadItems(
        inspection: LibraryInspection,
        context: LibraryPipelineContext,
        config: SableLibraryConfig,
        service: SableLibraryService
    ) -> [LibraryPlanItem] {
        let root = context.root
        let booksBySeriesID = Dictionary(grouping: inspection.books, by: \.seriesID)
        return inspection.series
            .filter { $0.hasComicInfo && $0.localBookCount > 0 }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
            .flatMap { series -> [LibraryPlanItem] in
                let folder = root.appendingPathComponent(series.path, isDirectory: true)
                let comicInfoURL = folder.appendingPathComponent(config.comicInfoFileName)
                let sidecar = readComicInfo(url: comicInfoURL) ?? [:]
                let localBooks = (booksBySeriesID[Optional(series.id)] ?? [])
                    .filter { ["epub", "kepub", "cbz", "cbr", "cb7", "pdf"].contains($0.fileExtension.lowercased()) }
                    .sorted { $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending }
                guard !localBooks.isEmpty else { return [] }

                let queryTitles = coverDownloadQueryTitles(
                    series: series,
                    sidecar: sidecar,
                    service: service
                )
                guard !queryTitles.isEmpty else { return [] }

                let manifestURL = folder
                    .appendingPathComponent("_covers", isDirectory: true)
                    .appendingPathComponent("cover-manifest.json")
                let savedManualSeriesMatches = savedManualCoverSeriesMatches(
                    at: manifestURL
                )
                return [
                    ("jp", "Japanese", "cover-language-jp"),
                    ("en", "English", "cover-language-en")
                ].map { language, languageLabel, languageTag in
                    let manifestReadiness = coverManifestReadiness(
                        at: manifestURL,
                        seriesFolder: folder,
                        root: root,
                        localBooks: localBooks,
                        seriesTitles: queryTitles,
                        requiredLanguage: language,
                        service: service
                    )
                    let reason: String
                    switch manifestReadiness {
                    case .complete:
                        reason = "Refresh downloaded \(languageLabel.lowercased()) cover choices for \(series.displayName). Existing files are not deleted; the manifest is updated to point at the best current normal covers and any useful extras."
                    case .incomplete(let gap):
                        reason = "Fill gaps in the downloaded \(languageLabel.lowercased()) cover set for \(series.displayName). \(gap)"
                    case .noResult(let detail):
                        reason = "MangaBaka could not fill every \(languageLabel.lowercased()) cover slot for \(series.displayName). \(detail) Use Find Quality Upgrades to try the stores, or retry MangaBaka only when its cover records may have changed."
                    case .conflict(let detail):
                        reason = "Repair a conflicting downloaded \(languageLabel.lowercased()) cover for \(series.displayName). \(detail) Verified covers are reused; only unsafe or missing slots are searched again."
                    case .unverified(let detail):
                        reason = "Verify the complete legacy \(languageLabel.lowercased()) cover set for \(series.displayName). \(detail) Sable will update only its manifest evidence; every existing image stays untouched."
                    case .needsStoreCheck(let detail):
                        reason = "Replace unproven \(languageLabel.lowercased()) covers for \(series.displayName). \(detail) The old images stay as fallbacks until a trusted replacement is accepted."
                    case .replacementNoResult(let detail):
                        reason = "No trusted replacement was found for the unproven \(languageLabel.lowercased()) covers for \(series.displayName). \(detail) Use Find Cover for an exact store series before retrying."
                    case .belowClinicQuality(let detail):
                        reason = "A complete \(languageLabel.lowercased()) cover set is archived for \(series.displayName), but it is not good enough for Clinic replacement. \(detail) Check this row only when you want to search again for a higher-resolution version."
                    case .missing:
                        reason = "Find the \(languageLabel.lowercased()) cover set for \(series.displayName), then save it in _covers with a manifest Clinic can read."
                    }
                    let providerOrder = language == "jp"
                        ? "MangaBaka establishes the Japanese series and volume baseline. BookLive JP, BookWalker JP, and Amazon JP may replace a slot only with a verified higher-quality image."
                        : "MangaBaka establishes the English series and volume baseline. BookWalker Global and Amazon may replace a slot only with a verified higher-quality image."
                    let confidenceExplanation = [
                        "\(languageLabel) order: \(providerOrder)",
                        "Amazon searches validated ComicInfo ISBNs first and localized series titles second. MangaBaka and RanobeDB IDs are never used as Amazon queries.",
                        "ComicInfo type is authoritative: manga rows accept manga series, while novel and lightNovel rows accept light-novel series.",
                        "Chapter rows and images below the 500 x 700 archive floor are rejected. Clinic separately requires 800 x 1100 before EPUB replacement. Special, alternative, bonus, and back covers are saved as extras but Clinic will not use them as the normal EPUB cover."
                    ].joined(separator: " ")
                    let defaultDecision: LibraryPlanDecision
                    switch manifestReadiness {
                    case .missing, .incomplete, .conflict, .needsStoreCheck:
                        defaultDecision = .checked
                    case .unverified:
                        defaultDecision = .checked
                    case .complete, .noResult, .replacementNoResult, .belowClinicQuality:
                        defaultDecision = .unchecked
                    }

                    return LibraryPlanItem(
                        stage: .covers,
                        operation: .refreshComicInfo,
                        currentPath: series.path,
                        proposedPath: "\(series.path)/_covers/cover-manifest.json",
                        reason: reason,
                        confidence: .medium,
                        safety: .reversible,
                        decision: defaultDecision,
                        requiresReview: false,
                        usedNetworkData: true,
                        metadataProviders: [],
                        confidenceExplanation: confidenceExplanation,
                        correctionOptions: [.wrongSeries, .wrongType, .custom],
                        manualMangaBakaID: series.identityGraph?.sourceIDs.first(where: { $0.provider == .mangabaka })?.value,
                        manualSourceIDs: series.identityGraph?.sourceIDs ?? [],
                        manualCoverSeriesMatches: savedManualSeriesMatches,
                        coverSearchTitles: queryTitles,
                        reviewTags: [
                            coverDownloadReviewTag,
                            "cover-download-series",
                            languageTag,
                            manifestReadiness.reviewTag
                        ],
                        receipt: "Download \(languageLabel.lowercased()) cover set for \(series.path)"
                    )
                }
            }
    }

    private func savedManualCoverSeriesMatches(
        at manifestURL: URL
    ) -> [SableLibraryManualCoverSeriesMatch] {
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(
                SableLibraryDownloadedCoverManifest.self,
                from: data
              ) else {
            return []
        }

        var seenSources = Set<SableLibraryCoverSource>()
        let newestMatches: [SableLibraryManualCoverSeriesMatch] =
            (manifest.manualSeriesMatches ?? []).reversed().compactMap { match in
            let providerID = match.providerID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !providerID.isEmpty, seenSources.insert(match.source).inserted else {
                return nil
            }
            var normalized = match
            normalized.providerID = providerID
            return normalized
        }
        return Array(newestMatches.reversed())
    }

    private func coverManifestReadiness(
        at manifestURL: URL,
        seriesFolder: URL,
        root: URL,
        localBooks: [LibraryBookSnapshot],
        seriesTitles: [String],
        requiredLanguage: String,
        service: SableLibraryService
    ) -> CoverManifestReadiness {
        let normalizedRequiredLanguage = SableLibraryCoverDownloadPlanner.normalizedLanguage(
            requiredLanguage
        )
        let languageLabel = normalizedRequiredLanguage == "jp" ? "Japanese" : "English"
        guard service.fileManager.fileExists(atPath: manifestURL.path(percentEncoded: false)) else {
            return .missing
        }
        guard let data = try? Data(contentsOf: manifestURL),
              let object = try? JSONSerialization.jsonObject(with: data),
              let manifest = object as? [String: Any],
              let entries = manifest["entries"] as? [[String: Any]] else {
            return .incomplete("The existing manifest could not be read.")
        }
        let decodedManifest = try? JSONDecoder().decode(
            SableLibraryDownloadedCoverManifest.self,
            from: data
        )
        let manualSeriesMatches = decodedManifest?.manualSeriesMatches ?? []
        let manifestVersion = coverManifestInteger(manifest["version"]) ?? 1
        let manifestSeriesTitle = coverManifestText(manifest["series_title"])
        let manifestMediaType = coverManifestText(manifest["media_type"])
        let skipped = (manifest["skipped"] as? [String]) ?? []
        let structuredBaselineAttempt = decodedManifest?.searchAttempts?
            .filter {
                SableLibraryCoverDownloadPlanner.normalizedLanguage($0.language)
                    == normalizedRequiredLanguage
                    && ($0.pass == .mangaBakaBaseline || $0.pass == .combined)
            }
            .sorted { $0.completedAt < $1.completedAt }
            .last
        let legacyHasMangaBakaCover = entries.contains { entry in
            let covers = entry["covers"] as? [[String: Any]] ?? []
            return covers.contains { cover in
                coverManifestLanguage(cover) == normalizedRequiredLanguage
                    && coverManifestText(cover["source"])
                        == SableLibraryCoverSource.mangaBaka.displayName
            }
        }
        let legacyHasMangaBakaTrace = skipped.contains {
            $0.hasPrefix("\(SableLibraryCoverSource.mangaBaka.displayName):")
        }
        let legacyHasLanguageResult = skipped.contains { note in
            guard note.hasPrefix("No trusted cover found in") else { return false }
            return normalizedRequiredLanguage == "jp"
                ? note.contains(SableLibraryCoverSource.bookLiveJP.displayName)
                : note.contains(SableLibraryCoverSource.bookWalkerGlobal.displayName)
        }
        let mangaBakaBaselineCompletedAt = structuredBaselineAttempt?.completedAt
            ?? (
                legacyHasMangaBakaCover
                    || (legacyHasMangaBakaTrace && legacyHasLanguageResult)
                ? coverManifestText(manifest["generated_at"])
                : nil
            )
        let proofPrefix =
            "Store proof repair \(normalizedRequiredLanguage.uppercased()) finished:"
        let currentProofSchema =
            "schema \(SableLibraryCoverDownloadPlanner.storeProofSchemaVersion)"
        let proofWasChecked = skipped.contains {
            $0.hasPrefix(proofPrefix) && $0.contains(currentProofSchema)
        }
        let replacementPrefix =
            SableLibraryCoverDownloadPlanner.unprovenReplacementReason(
                language: normalizedRequiredLanguage
            )
        let currentReplacementSchema =
            "schema \(SableLibraryCoverDownloadPlanner.unprovenReplacementSchemaVersion)"
        let replacementWasAttempted = skipped.contains {
            $0.hasPrefix(replacementPrefix) && $0.contains(currentReplacementSchema)
        }
        let trustedSeriesTitles = SableLibraryCoverDownloadPlanner.uniqueNonEmpty(
            seriesTitles + [manifestSeriesTitle].compactMap { $0 }
        )

        if entries.isEmpty {
            if let noResultDetail = completedMangaBakaBaselineDetail(
                completedAt: mangaBakaBaselineCompletedAt,
                language: normalizedRequiredLanguage,
                expectedMissingCount: localBooks.count,
                totalBookCount: localBooks.count
            ) {
                return .noResult(noResultDetail)
            }
            return .missing
        }

        let rootURL = root.standardizedFileURL
        let allowedExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "avif"]
        var conflicts: [String] = []
        var incompleteReasons: [String] = []
        var missingEvidence: [String] = []
        var belowClinicQualityReasons: [String] = []
        var evidenceOwners: [String: String] = [:]
        var fingerprintOwners: [String: String] = [:]
        var missingBookCount = 0

        conflicts.append(contentsOf: unreferencedCoverFileDetails(
            entries: entries,
            seriesFolder: seriesFolder,
            root: root,
            language: normalizedRequiredLanguage,
            languageLabel: languageLabel,
            allowedExtensions: allowedExtensions,
            service: service
        ))

        if manifestVersion < 2 {
            missingEvidence.append("the manifest predates provider verification")
        }
        if manifestSeriesTitle == nil {
            missingEvidence.append("the manifest has no series identity")
        }
        if manifestMediaType == nil {
            missingEvidence.append("the manifest has no manga or light-novel type")
        }

        for localBook in localBooks {
            guard let entry = entries.first(where: {
                coverManifestText($0["book_file"])?.caseInsensitiveCompare(localBook.fileName) == .orderedSame
            }) else {
                missingBookCount += 1
                incompleteReasons.append("\(localBook.fileName) is missing from the manifest.")
                continue
            }

            let parsedVolume = SableLibraryCoverDownloadPlanner.localVolumeNumber(
                fileName: localBook.fileName,
                seriesTitles: trustedSeriesTitles
            )
            let recordedVolume = coverManifestDouble(entry["volume"])
            if let parsedVolume, let recordedVolume,
               !SableLibraryCoverDownloadPlanner.volumeNumbersMatch(parsedVolume, recordedVolume) {
                conflicts.append(
                    "\(localBook.fileName) is recorded as volume \(formattedCoverVolume(recordedVolume)) instead of \(formattedCoverVolume(parsedVolume))"
                )
            }
            let localVolume = parsedVolume
                ?? recordedVolume
                ?? (localBooks.count == 1 ? 1 : nil)
            if localVolume == nil {
                missingEvidence.append("\(localBook.fileName) has no unambiguous local volume identity")
            }

            let covers = entry["covers"] as? [[String: Any]] ?? []
            for cover in covers {
                guard coverManifestLanguage(cover) == normalizedRequiredLanguage else {
                    continue
                }
                let role = (coverManifestText(cover["role"]) ?? "normal")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                guard role != "normal",
                      let providerTitle = coverManifestText(cover["provider_title"])
                        ?? coverManifestText(cover["edition_note"]),
                      !SableLibraryCoverDownloadPlanner.providerBookIdentityIsCompatible(
                        providerTitle: providerTitle,
                        localBookTitle: localBook.fileName,
                        localVolume: localVolume
                      ) else {
                    continue
                }
                conflicts.append(
                    "\(localBook.fileName) has an extra cover from another arc or volume: \(providerTitle)"
                )
            }
            let normalCovers = covers.filter { cover in
                let role = (coverManifestText(cover["role"]) ?? "normal")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                let status = (coverManifestText(cover["status"]) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                return role == "normal"
                    && status != "preserved_previous_normal"
                    && coverManifestLanguage(cover) == normalizedRequiredLanguage
            }
            guard !normalCovers.isEmpty else {
                missingBookCount += 1
                incompleteReasons.append(
                    "\(localBook.fileName) is missing a usable \(languageLabel) normal cover."
                )
                continue
            }

            var unusableReasons: [String] = []
            var hasUsableCover = false
            var hasClinicQualityCover = false
            var bestArchiveDimensions: (width: Int, height: Int)?
            for cover in normalCovers {
                var coverHasConflict = false
                var coverMeetsClinicQuality = false
                var measuredDimensions: (width: Int, height: Int)?
                if let width = coverManifestInteger(cover["width"]),
                   let height = coverManifestInteger(cover["height"]) {
                    measuredDimensions = (width, height)
                    if !SableLibraryCoverDownloadPlanner.coverDimensionsAreArchiveUsable(
                        width: width,
                        height: height
                    ) {
                        unusableReasons.append("\(width) x \(height) is below the 500 x 700 archive floor")
                        continue
                    }
                    coverMeetsClinicQuality = SableLibraryCoverDownloadPlanner.coverDimensionsAreUsable(
                        width: width,
                        height: height
                    )
                } else {
                    missingEvidence.append("\(localBook.fileName) has a cover without measured dimensions")
                }

                let rawLanguage = coverManifestText(cover["language"])
                guard let rawLanguage else {
                    unusableReasons.append("a normal cover has no language label")
                    continue
                }
                let language = SableLibraryCoverDownloadPlanner.normalizedLanguage(rawLanguage)
                guard language == normalizedRequiredLanguage else {
                    unusableReasons.append("a normal cover has the unsupported language \(rawLanguage)")
                    continue
                }

                let rawPath = (coverManifestText(cover["path"]) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !rawPath.isEmpty else {
                    unusableReasons.append("a normal cover has no file path")
                    continue
                }
                let coverURL = rawPath.hasPrefix("/")
                    ? URL(fileURLWithPath: rawPath)
                    : seriesFolder.appendingPathComponent(rawPath)
                let standardizedCoverURL = coverURL.standardizedFileURL
                let rootPath = rootURL.path(percentEncoded: false)
                let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
                let coverPath = standardizedCoverURL.path(percentEncoded: false)
                guard coverPath == rootPath || coverPath.hasPrefix(rootPrefix) else {
                    unusableReasons.append("\(rawPath) resolves outside the selected library")
                    continue
                }
                guard allowedExtensions.contains(standardizedCoverURL.pathExtension.lowercased()) else {
                    unusableReasons.append("\(rawPath) is not a supported image file")
                    continue
                }
                guard service.fileManager.fileExists(atPath: coverPath) else {
                    unusableReasons.append("\(rawPath) is missing")
                    continue
                }
                if let fingerprint = coverFileFingerprint(at: standardizedCoverURL) {
                    if let owner = fingerprintOwners[fingerprint],
                       owner.caseInsensitiveCompare(localBook.fileName) != .orderedSame {
                        conflicts.append(
                            "\(localBook.fileName) reuses the same local cover image as \(owner)"
                        )
                        coverHasConflict = true
                    } else {
                        fingerprintOwners[fingerprint] = localBook.fileName
                    }
                }
                let pathComponents = standardizedCoverURL.pathComponents.map {
                    $0.lowercased()
                }
                if let coversIndex = pathComponents.lastIndex(of: "_covers"),
                   pathComponents.indices.contains(coversIndex + 1) {
                    let pathLanguage = SableLibraryCoverDownloadPlanner.normalizedLanguage(
                        pathComponents[coversIndex + 1]
                    )
                    if (pathLanguage == "jp" || pathLanguage == "en"),
                       pathLanguage != language {
                        conflicts.append(
                            "\(localBook.fileName) labels \(rawPath) as \(language.uppercased()) but stores it under \(pathLanguage.uppercased())"
                        )
                        coverHasConflict = true
                    }
                }

                let source = SableLibraryCoverSource.allCases.first {
                    $0.displayName == coverManifestText(cover["source"])
                } ?? .unknown
                let status = (coverManifestText(cover["status"]) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                if source.isStoreSource, !status.contains("store_verified") {
                    let proofResult = status.contains("store_checked_unverified")
                        || proofWasChecked
                        ? "was checked, but its saved store page could not confirm the exact edition"
                        : "has not been checked against its store product page"
                    missingEvidence.append("\(localBook.fileName) \(proofResult)")
                } else if source.isStoreSource, status.contains("store_verified") {
                    let storeURL = coverManifestText(cover["provider_url"])?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if storeURL?.isEmpty != false {
                        missingEvidence.append(
                            "\(localBook.fileName) is marked store-verified but has no saved product-page URL"
                        )
                    } else if !coverStoreProofURL(
                        storeURL ?? "",
                        matches: source
                    ) {
                        conflicts.append(
                            "\(localBook.fileName) has \(source.displayName) proof pointing at another website"
                        )
                        coverHasConflict = true
                    }
                }
                let providerTitle = coverManifestText(cover["provider_title"])
                if let providerTitle {
                    let hasExactManualSeriesIdentity = manualSeriesMatches.contains { match in
                        guard match.source == source else { return false }
                        let providerSeriesID = coverManifestText(cover["provider_series_id"])
                        if providerSeriesID == match.providerID {
                            return true
                        }
                        return match.itemType.caseInsensitiveCompare("book") == .orderedSame
                            && coverManifestText(cover["provider_item_id"]) == match.providerID
                    }
                    if !hasExactManualSeriesIdentity {
                        let matchesTrustedSeries = SableLibraryCoverDownloadPlanner.providerTitle(
                            providerTitle,
                            belongsToAny: trustedSeriesTitles
                        )
                        if !trustedSeriesTitles.isEmpty, !matchesTrustedSeries {
                            conflicts.append(
                                "\(localBook.fileName) uses a provider title from another series: \(providerTitle)"
                            )
                            coverHasConflict = true
                        }
                        if !matchesTrustedSeries,
                           !SableLibraryCoverDownloadPlanner.providerTitleMatchesLocalSeriesStem(
                               providerTitle,
                               localBookTitle: localBook.fileName
                           ) {
                            conflicts.append(
                                "\(localBook.fileName) uses a provider title that does not match its local series name: \(providerTitle)"
                            )
                            coverHasConflict = true
                        }
                    }
                    if !SableLibraryCoverDownloadPlanner.providerTitleLanguageIsCompatible(
                        providerTitle,
                        language: language,
                        source: source
                    ) {
                        conflicts.append(
                            "\(localBook.fileName) has the wrong \(language.uppercased()) edition: \(providerTitle)"
                        )
                        coverHasConflict = true
                    }
                } else {
                    missingEvidence.append("\(localBook.fileName) has a cover without a provider title")
                }

                let providerMediaType = coverManifestText(cover["provider_media_type"])
                if let manifestMediaType {
                    if let providerMediaType {
                        if !SableLibraryCoverDownloadPlanner.providerMediaTypeIsCompatible(
                            providerMediaType,
                            isCompatibleWith: manifestMediaType
                        ) {
                            conflicts.append(
                                "\(localBook.fileName) has a \(providerMediaType) cover in a \(manifestMediaType) series"
                            )
                            coverHasConflict = true
                        }
                    } else {
                        missingEvidence.append("\(localBook.fileName) has a cover without provider media type")
                    }
                }

                let providerVolume = coverManifestDouble(cover["provider_volume"])
                if let localVolume {
                    if let providerVolume {
                        if !SableLibraryCoverDownloadPlanner.providerVolume(
                            providerVolume,
                            providerTitle: providerTitle,
                            localTitle: localBook.fileName,
                            source: source,
                            matches: localVolume
                        ) {
                            let titleEvidence = providerTitle.map {
                                " titled “\($0)”"
                            } ?? ""
                            conflicts.append(
                                "\(localBook.fileName) uses a provider record\(titleEvidence) "
                                    + "saved as volume \(formattedCoverVolume(providerVolume))"
                            )
                            coverHasConflict = true
                        }
                    } else {
                        missingEvidence.append("\(localBook.fileName) has a cover without provider volume")
                    }
                }

                let providerItemID = coverManifestText(cover["provider_item_id"])?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if providerItemID?.isEmpty != false {
                    missingEvidence.append("\(localBook.fileName) has a cover without provider item identity")
                }
                let providerURL = coverManifestText(cover["url"])?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let identities = [
                    providerItemID.map { "item|\(source.rawValue)|\($0)" },
                    providerURL.flatMap { $0.isEmpty ? nil : "url|\($0)" },
                    "path|\(coverPath)"
                ].compactMap { $0 }
                for identity in identities {
                    if let owner = evidenceOwners[identity],
                       owner.caseInsensitiveCompare(localBook.fileName) != .orderedSame {
                        conflicts.append(
                            "\(localBook.fileName) reuses the same provider image as \(owner)"
                        )
                        coverHasConflict = true
                    } else {
                        evidenceOwners[identity] = localBook.fileName
                    }
                }

                if !coverHasConflict {
                    hasUsableCover = true
                    hasClinicQualityCover = hasClinicQualityCover || coverMeetsClinicQuality
                    if !coverMeetsClinicQuality,
                       let measuredDimensions,
                       measuredDimensions.width * measuredDimensions.height
                        > (bestArchiveDimensions.map { $0.width * $0.height } ?? 0) {
                        bestArchiveDimensions = measuredDimensions
                    }
                }
            }
            if !hasUsableCover {
                missingBookCount += 1
                let detail = unusableReasons.first ?? "no usable normal cover was found"
                incompleteReasons.append(
                    "\(localBook.fileName) has no usable \(languageLabel) normal cover because \(detail)."
                )
            } else if !hasClinicQualityCover, let bestArchiveDimensions {
                belowClinicQualityReasons.append(
                    "\(localBook.fileName) has a \(bestArchiveDimensions.width) x \(bestArchiveDimensions.height) "
                        + "\(languageLabel) cover; Clinic requires 800 x 1100 for EPUB replacement."
                )
            }
        }

        if let detail = summarizedCoverReadinessDetails(conflicts) {
            return .conflict(detail)
        }
        if let detail = summarizedCoverReadinessDetails(incompleteReasons) {
            if let noResultDetail = completedMangaBakaBaselineDetail(
                completedAt: mangaBakaBaselineCompletedAt,
                language: normalizedRequiredLanguage,
                expectedMissingCount: missingBookCount,
                totalBookCount: localBooks.count
            ) {
                return .noResult(noResultDetail)
            }
            return .incomplete(detail)
        }
        if let detail = summarizedCoverReadinessDetails(missingEvidence) {
            if proofWasChecked {
                if replacementWasAttempted {
                    return .replacementNoResult(detail)
                }
                return .needsStoreCheck(detail)
            }
            return .unverified(detail)
        }
        if let detail = summarizedCoverReadinessDetails(belowClinicQualityReasons) {
            return .belowClinicQuality(detail)
        }
        return .complete
    }

    private func unreferencedCoverFileDetails(
        entries: [[String: Any]],
        seriesFolder: URL,
        root: URL,
        language: String,
        languageLabel: String,
        allowedExtensions: Set<String>,
        service: SableLibraryService
    ) -> [String] {
        let rootURL = root.standardizedFileURL
        let rootPath = rootURL.path(percentEncoded: false)
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        let languageFolder = seriesFolder
            .appendingPathComponent("_covers", isDirectory: true)
            .appendingPathComponent(language, isDirectory: true)
            .standardizedFileURL
        let languageFolderPath = languageFolder.path(percentEncoded: false)
        guard languageFolderPath.hasPrefix(rootPrefix),
              service.fileManager.fileExists(atPath: languageFolderPath),
              let files = try? service.fileManager.contentsOfDirectory(
                at: languageFolder,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        let activePaths = Set(entries.flatMap { entry -> [String] in
            let covers = entry["covers"] as? [[String: Any]] ?? []
            return covers.compactMap { cover in
                guard let path = coverManifestText(cover["path"])?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                      !path.isEmpty else {
                    return nil
                }
                let coverURL = path.hasPrefix("/")
                    ? URL(fileURLWithPath: path)
                    : seriesFolder.appendingPathComponent(path)
                return coverURL.standardizedFileURL.path(percentEncoded: false)
            }
        })

        return files.compactMap { url -> String? in
            guard allowedExtensions.contains(url.pathExtension.lowercased()),
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                return nil
            }
            let path = url.standardizedFileURL.path(percentEncoded: false)
            guard !activePaths.contains(path) else {
                return nil
            }
            return "\(url.lastPathComponent) is an unreferenced \(languageLabel) cover file and will be removed on repair."
        }
    }

    private func coverManifestLanguage(_ cover: [String: Any]) -> String? {
        guard let language = coverManifestText(cover["language"]) else { return nil }
        return SableLibraryCoverDownloadPlanner.normalizedLanguage(language)
    }

    private func coverFileFingerprint(at url: URL) -> String? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let fileSize = values.fileSize,
              fileSize > 1_024,
              let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
            return nil
        }
        #if canImport(CryptoKit)
        return SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        #else
        return nil
        #endif
    }

    private func coverStoreProofURL(
        _ rawValue: String,
        matches source: SableLibraryCoverSource
    ) -> Bool {
        guard let components = URLComponents(string: rawValue),
              components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased() else {
            return false
        }

        func isHost(_ domain: String) -> Bool {
            host == domain || host.hasSuffix(".\(domain)")
        }

        switch source {
        case .bookLiveJP:
            return isHost("booklive.jp")
        case .bookWalkerJP, .bookWalkerGlobal:
            return isHost("bookwalker.jp") || isHost("bookwalker.com")
        case .amazonJP, .amazon:
            return host == "amazon.com"
                || host.hasPrefix("amazon.")
                || host.contains(".amazon.")
                || host.hasSuffix(".amazon.com")
        case .mangaBaka, .ranobeDB, .unknown:
            return true
        }
    }

    private func completedMangaBakaBaselineDetail(
        completedAt: String?,
        language: String,
        expectedMissingCount: Int,
        totalBookCount: Int
    ) -> String? {
        guard expectedMissingCount > 0, let completedAt else {
            return nil
        }
        let languageLabel = language == "jp" ? "Japanese" : "English"
        return "MangaBaka baseline checked \(languageLabel.lowercased()) covers on "
            + "\(String(completedAt.prefix(10))); "
            + "\(expectedMissingCount) of \(totalBookCount) book slots still have no usable baseline cover."
    }

    private func summarizedCoverReadinessDetails(_ details: [String]) -> String? {
        var seen = Set<String>()
        let unique = details.filter { seen.insert($0).inserted }
        guard !unique.isEmpty else { return nil }
        let summary = unique.prefix(3).joined(separator: " ")
        let remaining = unique.count - min(unique.count, 3)
        return remaining > 0
            ? "\(summary) \(remaining) more issue\(remaining == 1 ? "" : "s") need review."
            : summary
    }

    private func formattedCoverVolume(_ volume: Double) -> String {
        volume.rounded() == volume
            ? String(Int(volume))
            : String(volume)
    }

    private func coverManifestText(_ value: Any?) -> String? {
        if let text = value as? String {
            return text
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    private func coverManifestInteger(_ value: Any?) -> Int? {
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let text = coverManifestText(value) {
            return Int(text)
        }
        return nil
    }

    private func coverManifestDouble(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let text = coverManifestText(value) {
            return Double(text)
        }
        return nil
    }

    private func refreshComicInfoItems(
        inspection: LibraryInspection,
        context: LibraryPipelineContext,
        config: SableLibraryConfig,
        service: SableLibraryService
    ) -> [LibraryPlanItem] {
        guard context.options.stages.refreshComicInfo
            || context.options.stages.useMangaBaka
            || context.options.stages.useMetadataProviders else {
            return []
        }

        let readingProviders = readingMetadataProviders(from: context.options.stages)
        let refreshCandidates = inspection.series
            .compactMap { series -> ComicInfoRefreshCandidate? in
                guard series.hasComicInfo else { return nil }

                let staleReason = staleComicInfo(series)
                let typeMismatch = mismatchedComicInfoType(series)
                let retryReason = readingProviders.isEmpty
                    ? nil
                    : metadataSidecarRetryReason(series: series, root: context.root, config: config, service: service)
                let missingMangaBakaV2Metadata = readingProviders.contains(.mangabaka)
                    && series.missingMangaBakaV2Metadata

                guard context.options.stages.refreshComicInfo || staleReason || typeMismatch || retryReason != nil || missingMangaBakaV2Metadata else {
                    return nil
                }

                return ComicInfoRefreshCandidate(
                    series: series,
                    staleReason: staleReason,
                    typeMismatch: typeMismatch,
                    missingMangaBakaV2Metadata: missingMangaBakaV2Metadata,
                    retryReason: retryReason
                )
            }
            .sorted { $0.series.path < $1.series.path }

        return refreshCandidates.flatMap { candidate -> [LibraryPlanItem] in
            let series = candidate.series
            let comicInfoPath = comicInfoPath(for: series.path, config: config)
            let refreshProviders = readingProviders.filter { !series.unavailableMetadataProviders.contains($0) }
            let usesMangaBaka = refreshProviders.contains(.mangabaka)
            let usesMetadataProviders = refreshProviders.contains { $0 != .mangabaka }
            let exactSourceIDs = exactRefreshSourceIDs(for: series)
            let hasRanobeDBID = seriesHasRanobeDBID(series)
            let reason: String
            if let retryReason = candidate.retryReason {
                reason = retryReason
            } else if usesMangaBaka && usesMetadataProviders {
                reason = candidate.staleReason
                    ? "This \(config.comicInfoFileName) is stale or missing a last-check date. Apply refreshes saved series details: MangaBaka V2, RanobeDB series identity, and AniList support when IDs are present."
                    : candidate.typeMismatch
                    ? "This \(config.comicInfoFileName) may have the wrong reading type. Apply refreshes the specialist provider path and keeps weak results out."
                    : candidate.missingMangaBakaV2Metadata
                    ? "This \(config.comicInfoFileName) has a saved MangaBaka ID but is missing newer title, tag, and link evidence. Apply refreshes those richer provider details without moving files."
                    : "Apply refreshes saved series details from RanobeDB, MangaBaka, and AniList when IDs are present."
            } else if usesMangaBaka {
                reason = candidate.staleReason
                    ? "This \(config.comicInfoFileName) is stale or missing a last-check date. Apply will refresh it from the best confident MangaBaka match."
                    : candidate.typeMismatch
                    ? "This \(config.comicInfoFileName) looks like it matched the wrong MangaBaka format. Apply will refresh it using the folder's type hint."
                    : candidate.missingMangaBakaV2Metadata
                    ? "This \(config.comicInfoFileName) has a saved MangaBaka ID but is missing newer title, tag, and link evidence. Apply refreshes those richer provider details without moving files."
                    : "Apply will search MangaBaka again and update this \(config.comicInfoFileName) from the best confident match."
            } else if usesMetadataProviders {
                reason = candidate.staleReason
                    ? "This \(config.comicInfoFileName) is stale or missing a last-check date. Apply refreshes RanobeDB series identity and AniList support when safe."
                    : "Apply refreshes local snapshot fields and adds RanobeDB series plus AniList details when safe."
            } else {
                reason = "Refresh local \(config.comicInfoFileName) snapshot without contacting MangaBaka."
            }
            let seriesRefreshItem = LibraryPlanItem(
                stage: .comicInfo,
                operation: .refreshComicInfo,
                currentPath: series.path,
                proposedPath: comicInfoPath,
                reason: hasRanobeDBID && refreshProviders.contains(.ranobedb)
                    ? "Updates current data from saved provider IDs. RanobeDB also checks for newly listed books and downloads only book details not already stored."
                    : reason,
                confidence: refreshProviders.isEmpty ? .high : .medium,
                safety: .reversible,
                decision: .unchecked,
                requiresReview: false,
                usedNetworkData: !refreshProviders.isEmpty,
                metadataProviders: refreshProviders,
                confidenceExplanation: candidate.retryReason != nil
                    ? "This sidecar currently has only local fields after a failed provider pass. Retry enabled providers, or use MB URL/ID / RDB URL/ID if search missed the exact series."
                    : candidate.missingMangaBakaV2Metadata
                    ? "Saved MangaBaka IDs let Sable refresh richer V2 title labels, tags, links, and provider evidence without guessing a new match."
                    : refreshProviders.isEmpty ? "Local refresh only updates the app snapshot and keeps existing title fields." : confidenceExplanationForReadingProviders(refreshProviders),
                correctionOptions: [.wrongType, .keepTitle, .custom],
                manualMangaBakaID: exactSourceIDs.first(where: { $0.provider == .mangabaka })?.value,
                manualRanobeDBID: exactSourceIDs.first(where: { $0.provider == .ranobedb })?.value,
                manualSourceIDs: exactSourceIDs,
                reviewTags: sidecarPassReviewTags(
                    (
                        candidate.missingMangaBakaV2Metadata ? ["metadata-mangabaka-v2-refresh"] : []
                    ) + (
                        hasRanobeDBID && refreshProviders.contains(.ranobedb)
                            ? [ranobeDBSeriesRefreshTag, ranobeDBBookDetailRefreshTag]
                            : []
                    ) + (
                        exactSourceIDs.isEmpty ? [] : [exactIDRefreshEvidenceTag]
                    ),
                    operation: .refreshComicInfo,
                    providers: refreshProviders,
                    hasRanobeDBID: hasRanobeDBID,
                    refreshesRanobeDBBooks: hasRanobeDBID && refreshProviders.contains(.ranobedb)
                ),
                receipt: "Refresh \(config.comicInfoFileName) for \(series.path)"
            )

            return [seriesRefreshItem]
        }
    }

    private func manualReadingProviderGapGroups(
        inspection: LibraryInspection,
        context: LibraryPipelineContext,
        config: SableLibraryConfig
    ) -> [LibraryPlanGroup] {
        let providers = manualReadingProviderGapProviders(
            stages: context.options.stages,
            config: config
        )
        guard !providers.isEmpty else { return [] }

        let seriesWithSidecars = inspection.series
            .filter(\.hasComicInfo)
            .filter(isReadingProviderGapEligible)
            .sorted { $0.path < $1.path }
        guard !seriesWithSidecars.isEmpty else { return [] }

        return providers.flatMap { provider -> [LibraryPlanGroup] in
            let missingItems = seriesWithSidecars
                .filter {
                    manualReadingProviderGapApplies(to: $0, provider: provider)
                        && !seriesHasSourceID($0, provider: provider)
                        && !$0.unavailableMetadataProviders.contains(provider)
                }
                .map { series in
                    manualReadingProviderGapItem(
                        series: series,
                        provider: provider,
                        config: config
                    )
                }

            let knownMissingItems = seriesWithSidecars
                .filter {
                    manualReadingProviderGapApplies(to: $0, provider: provider)
                        && !seriesHasSourceID($0, provider: provider)
                        && $0.unavailableMetadataProviders.contains(provider)
                }
                .map { series in
                    manualReadingProviderKnownMissingItem(
                        series: series,
                        provider: provider,
                        config: config
                    )
                }

            var groups: [LibraryPlanGroup] = []
            if !missingItems.isEmpty {
                groups.append(LibraryPlanGroup(
                    stage: .providerMatches,
                    title: "Missing Providers - \(provider.displayName)",
                    summary: "\(missingItems.count) existing \(config.comicInfoFileName) file(s) do not have a \(provider.displayName) ID yet.",
                    reviewPrompt: "Open rows here when you want to teach Sable an exact \(provider.displayName) match. These rows stay out of automatic refresh until you choose a match or use the local title.",
                    examples: examples(from: missingItems, title: "Missing \(provider.displayName)"),
                    quickVerifyAfterApply: false,
                    items: missingItems
                ))
            }
            if !knownMissingItems.isEmpty {
                groups.append(LibraryPlanGroup(
                    stage: .providerMatches,
                    title: "Saved No ID - \(provider.displayName)",
                    summary: "\(knownMissingItems.count) \(config.comicInfoFileName) file(s) remember No ID for \(provider.displayName), but you can search again if the provider has changed.",
                    reviewPrompt: "These rows keep the saved No ID choice by default. Open a row and use Find Match if this provider now has the right record.",
                    examples: examples(from: knownMissingItems, title: "Saved No ID \(provider.displayName)"),
                    quickVerifyAfterApply: false,
                    items: knownMissingItems
                ))
            }
            return groups
        }
    }

    private func manualReadingProviderGapProviders(
        stages: LibraryPipelineStageOptions,
        config: SableLibraryConfig
    ) -> [SableLibraryMetadataProvider] {
        let planner = SableLibraryProviderGraphPlanner()
        var providers: [SableLibraryMetadataProvider] = []

        func providerIsEnabled(_ provider: SableLibraryMetadataProvider) -> Bool {
            planner.providerConfig(for: provider, config: config)?.enabled ?? true
        }

        if stages.useMetadataProviders, providerIsEnabled(.ranobedb) {
            providers.append(.ranobedb)
        }
        if stages.useMangaBaka, providerIsEnabled(.mangabaka) {
            providers.append(.mangabaka)
        }
        if stages.useMetadataProviders, providerIsEnabled(.anilist) {
            providers.append(.anilist)
        }
        if stages.useMetadataProviders, providerIsEnabled(.openLibrary) {
            providers.append(.openLibrary)
        }
        return uniqueProviders(providers)
    }

    private func manualWatchingProviderGapGroups(
        inspection: LibraryInspection,
        context: LibraryPipelineContext,
        config: SableLibraryConfig
    ) -> [LibraryPlanGroup] {
        guard context.options.stages.useMetadataProviders else { return [] }
        let providers = manualWatchingProviderGapProviders(config: config)
        guard !providers.isEmpty else { return [] }

        let seriesWithSidecars = inspection.videoSeries
            .filter(\.hasAnimeInfo)
            .sorted { $0.path < $1.path }
        guard !seriesWithSidecars.isEmpty else { return [] }

        return providers.flatMap { provider -> [LibraryPlanGroup] in
            let missingItems = seriesWithSidecars
                .filter {
                    manualWatchingProviderGapApplies(to: $0, provider: provider)
                        && !videoSeriesHasSourceID($0, provider: provider)
                        && !$0.unavailableMetadataProviders.contains(provider)
                }
                .map { series in
                    manualWatchingProviderGapItem(
                        series: series,
                        provider: provider,
                        config: config
                    )
                }

            let knownMissingItems = seriesWithSidecars
                .filter {
                    manualWatchingProviderGapApplies(to: $0, provider: provider)
                        && !videoSeriesHasSourceID($0, provider: provider)
                        && $0.unavailableMetadataProviders.contains(provider)
                }
                .map { series in
                    manualWatchingProviderKnownMissingItem(
                        series: series,
                        provider: provider,
                        config: config
                    )
                }

            var groups: [LibraryPlanGroup] = []
            if !missingItems.isEmpty {
                groups.append(LibraryPlanGroup(
                    stage: .providerMatches,
                    title: "Missing Watching Providers - \(provider.displayName)",
                    summary: "\(missingItems.count) \(config.animeInfoFileName) file(s) do not have a \(provider.displayName) ID yet.",
                    reviewPrompt: "Open rows here when you want to teach Sable an exact \(provider.displayName) match for movies, TV, or anime. These rows stay out of refresh until you choose a match or mark No ID.",
                    examples: examples(from: missingItems, title: "Missing watching \(provider.displayName)"),
                    quickVerifyAfterApply: false,
                    items: missingItems
                ))
            }
            if !knownMissingItems.isEmpty {
                groups.append(LibraryPlanGroup(
                    stage: .providerMatches,
                    title: "Saved No ID Watching - \(provider.displayName)",
                    summary: "\(knownMissingItems.count) \(config.animeInfoFileName) file(s) remember No ID for \(provider.displayName), but you can search again if the provider has changed.",
                    reviewPrompt: "These rows keep the saved No ID choice by default. Open a row and use Find Match if this provider now has the right record.",
                    examples: examples(from: knownMissingItems, title: "Saved No ID watching \(provider.displayName)"),
                    quickVerifyAfterApply: false,
                    items: knownMissingItems
                ))
            }
            return groups
        }
    }

    private func matchedWatchingProviderGroups(
        inspection: LibraryInspection,
        context: LibraryPipelineContext,
        config: SableLibraryConfig
    ) -> [LibraryPlanGroup] {
        guard context.options.stages.useMetadataProviders else { return [] }

        let seriesWithSidecars = inspection.videoSeries
            .filter(\.hasAnimeInfo)
            .sorted { $0.path < $1.path }
        guard !seriesWithSidecars.isEmpty else { return [] }

        let providerOrder: [SableLibraryMetadataProvider] = [
            .anilist,
            .myAnimeList,
            .tmdb,
            .tvdb,
            .imdb,
            .tvmaze,
            .wikidata
        ]

        return providerOrder.compactMap { provider -> LibraryPlanGroup? in
            let items = seriesWithSidecars.compactMap { series -> LibraryPlanItem? in
                guard manualWatchingProviderGapApplies(to: series, provider: provider),
                      let sourceID = videoSeriesSourceIDs(series).first(where: { $0.provider == provider }) else {
                    return nil
                }
                return matchedWatchingProviderItem(
                    series: series,
                    provider: provider,
                    sourceID: sourceID,
                    config: config
                )
            }
            guard !items.isEmpty else { return nil }

            return LibraryPlanGroup(
                stage: .providerMatches,
                title: "Matched Watching Providers - \(provider.displayName)",
                summary: "\(items.count) \(config.animeInfoFileName) file(s) already have a saved \(provider.displayName) ID.",
                reviewPrompt: "These rows are already covered. Use Find Match only if a saved provider ID looks wrong.",
                examples: examples(from: items, title: "Saved watching \(provider.displayName)"),
                quickVerifyAfterApply: false,
                items: items
            )
        }
    }

    private func manualWatchingProviderGapProviders(config: SableLibraryConfig) -> [SableLibraryMetadataProvider] {
        let planner = SableLibraryProviderGraphPlanner()
        return uniqueProviders(planner.watchingProviders(config: config).filter { provider in
            provider != .myAnimeList && provider != .local
        })
    }

    private func manualWatchingProviderGapApplies(
        to series: LibraryVideoSeriesSnapshot,
        provider: SableLibraryMetadataProvider
    ) -> Bool {
        let type = (series.mediaType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let path = series.path.lowercased()
        let looksAnime = type.contains("anime") || path.contains("anime")
        let looksMovie = type == SableLibraryWatchingType.movie.rawValue.lowercased()
            || type.contains("movie")
            || path.contains("movies/")
            || path.hasPrefix("movies")
        let looksTV = type == SableLibraryWatchingType.tvShow.rawValue.lowercased()
            || type.contains("tv")
            || type.contains("show")
            || path == "tv"
            || path.contains("tv/")
            || path.contains("tv shows")

        switch provider {
        case .anilist, .myAnimeList:
            return looksAnime
        case .tvmaze:
            return looksTV || looksAnime
        case .wikidata:
            return looksAnime || looksMovie || looksTV
        case .tmdb:
            return looksMovie || looksTV
        case .tvdb:
            return looksTV
        case .imdb:
            return looksMovie || looksTV
        case .mangabaka, .ranobedb, .openLibrary, .local:
            return false
        }
    }

    private func videoSeriesHasSourceID(_ series: LibraryVideoSeriesSnapshot, provider: SableLibraryMetadataProvider) -> Bool {
        videoSeriesSourceIDs(series).contains { $0.provider == provider }
    }

    private func videoSeriesSourceIDs(_ series: LibraryVideoSeriesSnapshot) -> [SableLibrarySourceID] {
        uniqueSourceIDs(([series.primarySourceID].compactMap { $0 }) + (series.identityGraph?.sourceIDs ?? []))
    }

    private func manualReadingProviderGapItem(
        series: LibrarySeriesSnapshot,
        provider: SableLibraryMetadataProvider,
        config: SableLibraryConfig
    ) -> LibraryPlanItem {
        if let review = series.providerCandidateReviews.first(where: { $0.provider == provider }) {
            if shouldRefreshProviderCandidateReview(review, provider: provider) {
                return manualReadingProviderPrecheckItem(
                    series: series,
                    provider: provider,
                    config: config
                )
            }
            switch review.status {
            case .candidate:
                return manualReadingProviderCandidateReviewItem(
                    series: series,
                    provider: provider,
                    review: review,
                    config: config
                )
            case .noMatch:
                return manualReadingProviderNoMatchItem(
                    series: series,
                    provider: provider,
                    review: review,
                    config: config
                )
            }
        }

        return manualReadingProviderPrecheckItem(
            series: series,
            provider: provider,
            config: config
        )
    }

    private func shouldRefreshProviderCandidateReview(
        _ review: SableLibraryProviderCandidateReview,
        provider: SableLibraryMetadataProvider
    ) -> Bool {
        switch provider {
        case .anilist:
            return review.schemaVersion < providerGapReviewSchemaVersion
        default:
            return false
        }
    }

    private func manualReadingProviderChoiceItem(
        series: LibrarySeriesSnapshot,
        provider: SableLibraryMetadataProvider,
        config: SableLibraryConfig
    ) -> LibraryPlanItem {
        let comicInfoPath = comicInfoPath(for: series.path, config: config)
        let title = series.preferredTitle ?? series.localTitle ?? series.displayName
        let reason = "Manual provider queue: \(title) does not have a \(provider.displayName) ID yet. Use Find Match to search suggestions, paste an exact URL/ID, or keep the local title."

        return LibraryPlanItem(
            stage: .providerMatches,
            operation: .refreshComicInfo,
            currentPath: series.path,
            proposedPath: comicInfoPath,
            reason: reason,
            confidence: .low,
            safety: .needsChoice,
            decision: .unchecked,
            requiresReview: true,
            usedNetworkData: true,
            metadataProviders: [provider],
            confidenceExplanation: manualReadingProviderGapExplanation(provider: provider),
            correctionOptions: [.keepTitle, .custom],
            reviewTags: [
                "company.lazycompany",
                "department.sidecarrelations",
                "department.readinglibrary",
                "metadata-pass",
                "metadata-checkpoint-manual",
                "metadata-manual-provider-gap",
                "ml-training-provider-gap",
                "provider-ranker-training",
                "metadata-provider-missing-\(provider.rawValue)",
                "needs-provider-choice"
            ],
            receipt: "Manual \(provider.displayName) match for \(series.path)"
        )
    }

    private func manualReadingProviderPrecheckItem(
        series: LibrarySeriesSnapshot,
        provider: SableLibraryMetadataProvider,
        config: SableLibraryConfig
    ) -> LibraryPlanItem {
        let comicInfoPath = comicInfoPath(for: series.path, config: config)
        let title = providerGapTitle(for: series)
        let reason = "Run one light \(provider.displayName) candidate check for \(title). Sable will not write an ID yet; it will return a confidence question or a No ID question for you to confirm."

        return LibraryPlanItem(
            stage: .providerMatches,
            operation: .refreshComicInfo,
            currentPath: series.path,
            proposedPath: comicInfoPath,
            reason: reason,
            confidence: .medium,
            safety: .reversible,
            decision: .checked,
            requiresReview: false,
            usedNetworkData: true,
            metadataProviders: [provider],
            confidenceExplanation: "\(provider.displayName) precheck only. The provider-ranker specialist searches once and caches the best evidence, but it will not save an ID until a later yes/no/manual choice.",
            correctionOptions: [],
            reviewTags: manualProviderGapTags(provider: provider, extra: [
                "metadata-provider-precheck",
                "provider-ranker-precheck",
                "ml-provider-precheck"
            ]),
            receipt: "Precheck \(provider.displayName) match for \(series.path)"
        )
    }

    private func manualReadingProviderKnownMissingItem(
        series: LibrarySeriesSnapshot,
        provider: SableLibraryMetadataProvider,
        config: SableLibraryConfig
    ) -> LibraryPlanItem {
        let comicInfoPath = comicInfoPath(for: series.path, config: config)
        let title = providerGapTitle(for: series)
        return LibraryPlanItem(
            stage: .providerMatches,
            operation: .refreshComicInfo,
            currentPath: series.path,
            proposedPath: comicInfoPath,
            reason: "\(title) is saved as No ID for \(provider.displayName). Leave it alone, or use Find Match if the provider has a record now.",
            confidence: .medium,
            safety: .needsChoice,
            decision: .unchecked,
            requiresReview: false,
            usedNetworkData: true,
            metadataProviders: [provider],
            confidenceExplanation: "Saved No ID provider state from the local sidecar. This row stays out of apply until you pick an exact provider match.",
            correctionOptions: [.custom],
            reviewTags: manualProviderGapTags(provider: provider, extra: [
                "metadata-provider-known-missing",
                "provider-ranker-known-missing",
                "ml-provider-known-missing"
            ]),
            receipt: "Known missing \(provider.displayName) for \(series.path)"
        )
    }

    private func manualReadingProviderCandidateReviewItem(
        series: LibrarySeriesSnapshot,
        provider: SableLibraryMetadataProvider,
        review: SableLibraryProviderCandidateReview,
        config: SableLibraryConfig
    ) -> LibraryPlanItem {
        let comicInfoPath = comicInfoPath(for: series.path, config: config)
        let title = providerGapTitle(for: series)
        let percent = providerCandidateReviewPercent(review)
        let candidate = review.title ?? "untitled candidate"
        let summary = providerCandidateReviewSummary(review)
        let isConfidentMatch = isConfidentReadingProviderCandidate(
            provider: provider,
            percent: percent,
            review: review,
            series: series
        )
        let reason = isConfidentMatch
            ? "\(title) - \(percent)% confident \(provider.displayName) match: \(candidate)\(summary). This is checked because the specialist match is 90%+ and fits the expected media type; uncheck it or open Find Match if it looks wrong."
            : "\(title) - \(percent)% possible \(provider.displayName) match: \(candidate)\(summary). Check this row to use that ID, choose No ID if this provider truly has no record, or open Find Match."
        let sourceIDs = review.sourceID.map { [$0] } ?? []

        return LibraryPlanItem(
            stage: .providerMatches,
            operation: .refreshComicInfo,
            currentPath: series.path,
            proposedPath: comicInfoPath,
            reason: reason,
            confidence: isConfidentMatch ? .high : percent >= 75 ? .medium : .low,
            safety: .reversible,
            decision: isConfidentMatch ? .checked : .unchecked,
            requiresReview: false,
            usedNetworkData: true,
            metadataProviders: [provider],
            confidenceExplanation: isConfidentMatch
                ? "\(provider.displayName) candidate precheck found a \(percent)% specialist match with the expected media type. Sable checks 90%+ matches for apply, but you can still uncheck it before running the pass."
                : "\(provider.displayName) candidate precheck found a possible ID. The row stays unchecked so bulk safe-check will not accept it; checking it is your explicit yes.",
            correctionOptions: [.keepTitle, .custom],
            manualMangaBakaID: provider == .mangabaka ? review.sourceID?.value : nil,
            manualRanobeDBID: provider == .ranobedb ? review.sourceID?.value : nil,
            manualSourceIDs: sourceIDs,
            reviewTags: manualProviderGapTags(provider: provider, extra: [
                "metadata-provider-candidate-review",
                "provider-ranker-candidate",
                "ml-provider-candidate"
            ] + (isConfidentMatch ? [
                "metadata-provider-confident-candidate",
                "provider-ranker-confident",
                "ml-provider-confident"
            ] : [
                "metadata-provider-needs-confirmation"
            ])),
            receipt: "Use suggested \(provider.displayName) ID for \(series.path)"
        )
    }

    private func manualReadingProviderNoMatchItem(
        series: LibrarySeriesSnapshot,
        provider: SableLibraryMetadataProvider,
        review: SableLibraryProviderCandidateReview,
        config: SableLibraryConfig
    ) -> LibraryPlanItem {
        let comicInfoPath = comicInfoPath(for: series.path, config: config)
        let title = providerGapTitle(for: series)
        let reason = "\(title) - 0% \(provider.displayName) match found in the last precheck. Confirm No ID if that is correct, or open Find Match if you know there should be a record."

        return LibraryPlanItem(
            stage: .providerMatches,
            operation: .refreshComicInfo,
            currentPath: series.path,
            proposedPath: comicInfoPath,
            reason: reason,
            confidence: .low,
            safety: .needsChoice,
            decision: .unchecked,
            requiresReview: true,
            usedNetworkData: false,
            metadataProviders: [provider],
            confidenceExplanation: "\(provider.displayName) precheck returned no usable candidate. No ID is a learning signal; Find Match lets you override the specialist if it missed something.",
            correctionOptions: [.keepTitle, .custom],
            reviewTags: manualProviderGapTags(provider: provider, extra: [
                "metadata-provider-no-match-review",
                "provider-ranker-no-match",
                "ml-provider-no-match"
            ]),
            receipt: "Confirm no \(provider.displayName) ID for \(series.path)"
        )
    }

    private func manualWatchingProviderGapItem(
        series: LibraryVideoSeriesSnapshot,
        provider: SableLibraryMetadataProvider,
        config: SableLibraryConfig
    ) -> LibraryPlanItem {
        if let review = series.providerCandidateReviews.first(where: { $0.provider == provider }) {
            if shouldRefreshProviderCandidateReview(review, provider: provider) {
                return manualWatchingProviderPrecheckItem(series: series, provider: provider, config: config)
            }
            switch review.status {
            case .candidate:
                return manualWatchingProviderCandidateReviewItem(
                    series: series,
                    provider: provider,
                    review: review,
                    config: config
                )
            case .noMatch:
                return manualWatchingProviderNoMatchItem(
                    series: series,
                    provider: provider,
                    review: review,
                    config: config
                )
            }
        }

        return manualWatchingProviderPrecheckItem(series: series, provider: provider, config: config)
    }

    private func manualWatchingProviderPrecheckItem(
        series: LibraryVideoSeriesSnapshot,
        provider: SableLibraryMetadataProvider,
        config: SableLibraryConfig
    ) -> LibraryPlanItem {
        let animeInfoPath = animeInfoPath(for: series.path, config: config)
        let title = providerGapTitle(for: series)
        return LibraryPlanItem(
            stage: .providerMatches,
            operation: .refreshAnimeInfo,
            currentPath: series.path,
            proposedPath: animeInfoPath,
            reason: "Run one light \(provider.displayName) candidate check for \(title). Sable will not write an ID yet; it will return a confidence question or a No ID question for you to confirm.",
            confidence: .medium,
            safety: .reversible,
            decision: .checked,
            requiresReview: false,
            usedNetworkData: true,
            metadataProviders: [provider],
            confidenceExplanation: "\(provider.displayName) precheck only. The provider-ranker specialist searches once and caches the best evidence, but it will not save an ID until a later yes/no/manual choice.",
            correctionOptions: [],
            reviewTags: manualProviderGapTags(provider: provider, extra: [
                "metadata-provider-precheck",
                "metadata-provider-watching-gap",
                "provider-ranker-precheck",
                "ml-provider-precheck"
            ]),
            receipt: "Precheck watching \(provider.displayName) match for \(series.path)"
        )
    }

    private func manualWatchingProviderKnownMissingItem(
        series: LibraryVideoSeriesSnapshot,
        provider: SableLibraryMetadataProvider,
        config: SableLibraryConfig
    ) -> LibraryPlanItem {
        let animeInfoPath = animeInfoPath(for: series.path, config: config)
        let title = providerGapTitle(for: series)
        return LibraryPlanItem(
            stage: .providerMatches,
            operation: .refreshAnimeInfo,
            currentPath: series.path,
            proposedPath: animeInfoPath,
            reason: "\(title) is saved as No ID for \(provider.displayName). Leave it alone, or use Find Match if the provider has a record now.",
            confidence: .medium,
            safety: .needsChoice,
            decision: .unchecked,
            requiresReview: false,
            usedNetworkData: true,
            metadataProviders: [provider],
            confidenceExplanation: "Saved No ID provider state from the local AnimeInfo sidecar. This row stays out of apply until you pick an exact provider match.",
            correctionOptions: [.custom],
            reviewTags: manualProviderGapTags(provider: provider, extra: [
                "metadata-provider-known-missing",
                "metadata-provider-watching-gap",
                "provider-ranker-known-missing",
                "ml-provider-known-missing"
            ]),
            receipt: "Known missing watching \(provider.displayName) for \(series.path)"
        )
    }

    private func matchedWatchingProviderItem(
        series: LibraryVideoSeriesSnapshot,
        provider: SableLibraryMetadataProvider,
        sourceID: SableLibrarySourceID,
        config: SableLibraryConfig
    ) -> LibraryPlanItem {
        let animeInfoPath = animeInfoPath(for: series.path, config: config)
        let title = providerGapTitle(for: series)
        return LibraryPlanItem(
            stage: .providerMatches,
            operation: .refreshAnimeInfo,
            currentPath: series.path,
            proposedPath: animeInfoPath,
            reason: "\(title) already has \(provider.displayName) ID \(sourceID.value). This row is visible so provider coverage is auditable; it does not apply unless you use Find Match to replace the ID.",
            confidence: .high,
            safety: .inspectOnly,
            decision: .unchecked,
            requiresReview: false,
            usedNetworkData: false,
            metadataProviders: [provider],
            confidenceExplanation: "Saved provider ID from the local AnimeInfo sidecar. Nothing needs to run for this provider unless you choose a different match.",
            correctionOptions: [.custom],
            manualSourceIDs: [sourceID],
            reviewTags: manualProviderGapTags(provider: provider, extra: [
                "metadata-provider-already-matched",
                "metadata-provider-watching-gap",
                "provider-ranker-covered",
                "ml-provider-covered"
            ]),
            receipt: "Saved watching \(provider.displayName) ID for \(series.path)"
        )
    }

    private func manualWatchingProviderCandidateReviewItem(
        series: LibraryVideoSeriesSnapshot,
        provider: SableLibraryMetadataProvider,
        review: SableLibraryProviderCandidateReview,
        config: SableLibraryConfig
    ) -> LibraryPlanItem {
        let animeInfoPath = animeInfoPath(for: series.path, config: config)
        let title = providerGapTitle(for: series)
        let percent = providerCandidateReviewPercent(review)
        let candidate = review.title ?? "untitled candidate"
        let summary = providerCandidateReviewSummary(review)
        let isConfidentMatch = isConfidentWatchingProviderCandidate(
            provider: provider,
            percent: percent,
            review: review,
            series: series
        )
        let reason = isConfidentMatch
            ? "\(title) - \(percent)% confident \(provider.displayName) match: \(candidate)\(summary). This is checked because the specialist match is 90%+ and fits the expected watching type; uncheck it or open Find Match if it looks wrong."
            : "\(title) - \(percent)% possible \(provider.displayName) match: \(candidate)\(summary). Check this row to use that ID, choose No ID if this provider truly has no record, or open Find Match."

        return LibraryPlanItem(
            stage: .providerMatches,
            operation: .refreshAnimeInfo,
            currentPath: series.path,
            proposedPath: animeInfoPath,
            reason: reason,
            confidence: isConfidentMatch ? .high : percent >= 75 ? .medium : .low,
            safety: .reversible,
            decision: isConfidentMatch ? .checked : .unchecked,
            requiresReview: false,
            usedNetworkData: true,
            metadataProviders: [provider],
            confidenceExplanation: isConfidentMatch
                ? "\(provider.displayName) candidate precheck found a \(percent)% specialist match with the expected watching type. Sable checks 90%+ matches for apply, but you can still uncheck it before running the pass."
                : "\(provider.displayName) candidate precheck found a possible ID. The row stays unchecked so bulk safe-check will not accept it; checking it is your explicit yes.",
            correctionOptions: [.keepTitle, .custom],
            manualSourceIDs: review.sourceID.map { [$0] } ?? [],
            reviewTags: manualProviderGapTags(provider: provider, extra: [
                "metadata-provider-candidate-review",
                "metadata-provider-watching-gap",
                "provider-ranker-candidate",
                "ml-provider-candidate"
            ] + (isConfidentMatch ? [
                "metadata-provider-confident-candidate",
                "provider-ranker-confident",
                "ml-provider-confident"
            ] : [
                "metadata-provider-needs-confirmation"
            ])),
            receipt: "Use suggested watching \(provider.displayName) ID for \(series.path)"
        )
    }

    private func manualWatchingProviderNoMatchItem(
        series: LibraryVideoSeriesSnapshot,
        provider: SableLibraryMetadataProvider,
        review: SableLibraryProviderCandidateReview,
        config: SableLibraryConfig
    ) -> LibraryPlanItem {
        let animeInfoPath = animeInfoPath(for: series.path, config: config)
        let title = providerGapTitle(for: series)
        return LibraryPlanItem(
            stage: .providerMatches,
            operation: .refreshAnimeInfo,
            currentPath: series.path,
            proposedPath: animeInfoPath,
            reason: "\(title) - 0% \(provider.displayName) match found in the last precheck. Confirm No ID if that is correct, or open Find Match if you know there should be a record.",
            confidence: .low,
            safety: .needsChoice,
            decision: .unchecked,
            requiresReview: true,
            usedNetworkData: false,
            metadataProviders: [provider],
            confidenceExplanation: "\(provider.displayName) precheck returned no usable candidate. No ID is a learning signal; Find Match lets you override the specialist if it missed something.",
            correctionOptions: [.keepTitle, .custom],
            reviewTags: manualProviderGapTags(provider: provider, extra: [
                "metadata-provider-no-match-review",
                "metadata-provider-watching-gap",
                "provider-ranker-no-match",
                "ml-provider-no-match"
            ]),
            receipt: "Confirm no watching \(provider.displayName) ID for \(series.path)"
        )
    }

    private func manualProviderGapTags(
        provider: SableLibraryMetadataProvider,
        extra: [String] = []
    ) -> [String] {
        [
            "company.lazycompany",
            "department.sidecarrelations",
            "department.readinglibrary",
            "metadata-pass",
            "metadata-checkpoint-manual",
            "metadata-manual-provider-gap",
            "ml-training-provider-gap",
            "provider-ranker-training",
            "metadata-provider-missing-\(provider.rawValue)",
            "needs-provider-choice"
        ] + extra
    }

    private func providerGapTitle(for series: LibrarySeriesSnapshot) -> String {
        series.preferredTitle ?? series.localTitle ?? series.displayName
    }

    private func providerGapTitle(for series: LibraryVideoSeriesSnapshot) -> String {
        series.preferredTitle ?? series.localTitle ?? series.displayName
    }

    private func providerCandidateReviewPercent(_ review: SableLibraryProviderCandidateReview) -> Int {
        max(0, min(99, Int((review.confidenceScore * 100).rounded())))
    }

    private func isConfidentReadingProviderCandidate(
        provider: SableLibraryMetadataProvider,
        percent: Int,
        review: SableLibraryProviderCandidateReview,
        series: LibrarySeriesSnapshot
    ) -> Bool {
        guard percent >= 90, review.sourceID != nil else { return false }
        switch provider {
        case .ranobedb:
            return review.mediaType?.localizedCaseInsensitiveContains("light") == true
        case .mangabaka:
            guard let mediaType = review.mediaType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                  !mediaType.isEmpty else {
                return true
            }
            return ["manga", "manhwa", "manhua", "comic", "webtoon", "oel"].contains(mediaType)
        case .anilist, .myAnimeList:
            guard let mediaType = review.mediaType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                  !mediaType.isEmpty else {
                return true
            }
            return readingCatalogMediaTypeMatchesExpectedLane(mediaType, series: series)
        default:
            return false
        }
    }

    private func isConfidentWatchingProviderCandidate(
        provider: SableLibraryMetadataProvider,
        percent: Int,
        review: SableLibraryProviderCandidateReview,
        series: LibraryVideoSeriesSnapshot
    ) -> Bool {
        guard percent >= 90, review.sourceID != nil else { return false }
        let mediaType = review.mediaType?.lowercased() ?? ""
        let expectedType = (series.mediaType ?? "").lowercased()
        switch provider {
        case .anilist:
            return mediaType.contains("anime") || mediaType.contains("tv") || mediaType.contains("movie")
        case .tvmaze:
            return !expectedType.contains("movie")
        case .tmdb, .wikidata:
            return true
        case .tvdb:
            return expectedType.contains("tv") || expectedType.contains("show")
        case .imdb:
            return expectedType.contains("movie") || expectedType.contains("tv") || expectedType.contains("show")
        case .mangabaka, .ranobedb, .openLibrary, .myAnimeList, .local:
            return false
        }
    }

    private func readingCatalogMediaTypeMatchesExpectedLane(
        _ mediaType: String,
        series: LibrarySeriesSnapshot
    ) -> Bool {
        let normalizedMediaType = normalizedReadingCatalogMediaType(mediaType)
        if expectedReadingCatalogLane(for: series) == .lightNovel {
            return ["novel", "light_novel"].contains(normalizedMediaType)
        }
        if expectedReadingCatalogLane(for: series) == .manga {
            return ["manga", "one_shot"].contains(normalizedMediaType)
        }
        return ["manga", "one_shot", "novel", "light_novel"].contains(normalizedMediaType)
    }

    private func providerCandidateReviewSummary(_ review: SableLibraryProviderCandidateReview) -> String {
        var parts: [String] = []
        if let mediaType = review.mediaType, !mediaType.isEmpty {
            parts.append(mediaType)
        }
        if let year = review.year {
            parts.append("\(year)")
        }
        return parts.isEmpty ? "" : " (\(parts.joined(separator: ", ")))"
    }

    private func manualReadingProviderGapExplanation(provider: SableLibraryMetadataProvider) -> String {
        switch provider {
        case .ranobedb:
            "RanobeDB is the most precise light-novel source. A manual ID lets the next detail pass fetch series and book data without broad guessing."
        case .mangabaka:
            "MangaBaka is the main manga/manhwa/manhua identity source. Use this when the folder really belongs to a comic-style catalog entry."
        case .anilist:
            "AniList can add anime-adjacent manga identity and bridge IDs after the main reading identity is clear."
        case .myAnimeList:
            "Legacy MAL IDs can still help bridge into AniList, but Sable does not review MAL as an active provider."
        case .openLibrary:
            "Open Library is English-first here and best for prose or ISBN-backed book evidence. Choose exact works/books carefully."
        case .wikidata:
            "Wikidata is useful for prose identity, author/year checks, and series or franchise hints. Use the exact QID only when the item clearly matches this folder."
        default:
            "Use an exact provider match only when the provider result clearly represents this local folder."
        }
    }

    private func isReadingProviderGapEligible(_ series: LibrarySeriesSnapshot) -> Bool {
        let sourceIDs = ([series.primarySourceID].compactMap { $0 }) + (series.identityGraph?.sourceIDs ?? [])
        let hasSpecialistReadingID = sourceIDs.contains { $0.provider == .mangabaka || $0.provider == .ranobedb }
        if hasSpecialistReadingID {
            return true
        }

        let hasBookCatalogOnlyID = !sourceIDs.isEmpty
            && sourceIDs.allSatisfy { $0.provider == .openLibrary || $0.provider == .wikidata }
        let source = series.comicInfoSource?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let sourceLooksBookCatalogOnly = !source.isEmpty
            && !source.contains("mangabaka")
            && !source.contains("ranobedb")
            && (source.contains("openlibrary")
                || source.contains("open library")
                || source.contains("wikidata"))

        if let mediaType = series.mediaType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !mediaType.isEmpty {
            if ["manga", "manhwa", "manhua", "comic", "comics", "webtoon", "oel", "lightnovel", "light novel"].contains(mediaType) {
                return true
            }
            if ["book", "novel", "prose", "general prose"].contains(mediaType) {
                if mediaType == "novel", isLightNovelLane(series.path), !hasBookCatalogOnlyID, !sourceLooksBookCatalogOnly {
                    return true
                }
                return false
            }
        }

        if hasBookCatalogOnlyID || sourceLooksBookCatalogOnly {
            return false
        }

        return isMangaLane(series.path) || isLightNovelLane(series.path)
    }

    private func manualReadingProviderGapApplies(
        to series: LibrarySeriesSnapshot,
        provider: SableLibraryMetadataProvider
    ) -> Bool {
        let rawMediaType = series.mediaType?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let normalizedMediaType = rawMediaType.map { SableLibraryNamingPolicy().normalizedMediaType($0) }
        let rawTypeLooksManga = rawMediaType.map {
            ["manga", "manhwa", "manhua", "comic", "comics", "webtoon", "oel"].contains($0)
        } ?? false
        let rawTypeLooksLightNovel = rawMediaType.map {
            ["lightnovel", "light novel"].contains($0)
        } ?? false
        let looksManga = isMangaLane(series.path)
            || normalizedMediaType.map { ["Manga", "Manhwa", "Manhua", "OEL"].contains($0) } == true
            || rawTypeLooksManga
        let looksLightNovel = isLightNovelLane(series.path)
            || rawTypeLooksLightNovel
            || (normalizedMediaType == "Novel" && !looksManga)

        switch provider {
        case .ranobedb:
            return looksLightNovel
        case .mangabaka:
            return looksManga || looksLightNovel
        case .anilist:
            return looksManga || looksLightNovel
        case .openLibrary, .wikidata:
            return looksManga || looksLightNovel
        default:
            return false
        }
    }

    private func seriesHasSourceID(_ series: LibrarySeriesSnapshot, provider: SableLibraryMetadataProvider) -> Bool {
        let sourceIDs = ([series.primarySourceID].compactMap { $0 }) + (series.identityGraph?.sourceIDs ?? [])
        switch provider {
        case .anilist:
            return sourceIDs.contains { $0.provider == .anilist }
        default:
            return sourceIDs.contains { $0.provider == provider }
        }
    }

    private func metadataSidecarRetryReason(
        series: LibrarySeriesSnapshot,
        root: URL,
        config: SableLibraryConfig,
        service: SableLibraryService
    ) -> String? {
        let comicInfoURL = root.appendingPathComponent(comicInfoPath(for: series.path, config: config))
        guard let sidecar = readComicInfo(url: comicInfoURL) else {
            return nil
        }

        let ids = sourceIDs(from: sidecar, service: service)
        let trustedReadingIDProviders: Set<SableLibraryMetadataProvider> = [
            .mangabaka,
            .ranobedb,
            .openLibrary,
            .wikidata,
        ]

        if ids.contains(where: { trustedReadingIDProviders.contains($0.provider) }) {
            return nil
        }

        let source = service.textValue(sidecar["source"])?.lowercased()
        let sable = sidecar["_sable"] as? [String: Any] ?? [:]
        let failedProviders = [
            "mangabaka",
            "ranobedb",
            "openlibrary",
            "wikidata",
            "anilist"
        ].filter { key in
            guard let providerState = sable[key] as? [String: Any] else { return false }
            return service.textValue(providerState["outcome"]) == SableLibraryQuietOutcome.leaveUntouched.rawValue
        }

        guard source == "local", !failedProviders.isEmpty else {
            return nil
        }
        guard series.localFileSnapshotChanged || staleComicInfo(series) else {
            return nil
        }

        let providerText = failedProviders
            .map { key in
                switch key {
                case "mangabaka": return "MangaBaka"
                case "ranobedb": return "RanobeDB"
                case "openlibrary": return "Open Library"
                case "wikidata": return "Wikidata"
                case "anilist": return "AniList"
                default: return key
                }
            }
            .joined(separator: ", ")

        return "This local \(config.comicInfoFileName) has no trusted provider ID yet. Previous provider pass left \(providerText) untouched, so apply can retry enabled providers or you can give an MB/RDB/OL URL or ID."
    }

    private func createAnimeInfoItems(
        inspection: LibraryInspection,
        context: LibraryPipelineContext,
        config: SableLibraryConfig,
        service: SableLibraryService
    ) -> [LibraryPlanItem] {
        guard !hasPendingWatchingRawPreparation(in: context.plan, config: config) else {
            return []
        }

        let usesMetadataProviders = context.options.stages.useMetadataProviders
        let seriesByPath = inspection.videoSeries.reduce(into: [String: LibraryVideoSeriesSnapshot]()) { partialResult, series in
            partialResult[series.path] = series
        }

        return inspection.missingAnimeInfoSeriesPaths.sorted().compactMap { path in
            let folder = context.root.appendingPathComponent(path, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard service.fileManager.fileExists(atPath: folder.path(percentEncoded: false), isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                return nil
            }

            let series = seriesByPath[path]
            let hasIDHint = hasWatchingSourceIDHint(series) || hasWatchingSourceIDHint(in: path)
            let allowsLocalCheckpoint = canCreateLocalWatchingSidecar(for: series, path: path)
            guard usesMetadataProviders || hasIDHint || allowsLocalCheckpoint else {
                return nil
            }

            let title = series?.displayName ?? URL(fileURLWithPath: path).lastPathComponent
            let animeInfoPath = animeInfoPath(for: path, config: config)
            let localReason = hasIDHint
                ? "Create \(config.animeInfoFileName) for \(title) from existing folder ID hints and local video files."
                : "Create a local \(config.animeInfoFileName) checkpoint for \(title) from the folder and video files. No provider ID is guessed."
            let localConfidence = hasIDHint
                ? "Local apply is allowed because the folder already contains a watching source ID hint; no provider result is guessed."
                : "Local apply is allowed because this folder already has video files. Provider IDs stay blank until a real match is chosen."
            return LibraryPlanItem(
                stage: .comicInfo,
                operation: .createAnimeInfo,
                currentPath: path,
                proposedPath: animeInfoPath,
                reason: usesMetadataProviders
                    ? "Create \(config.animeInfoFileName) for \(title). Apply may contact AniList, TVmaze, and Wikidata; if no confident match is found, Sable writes the local sidecar without provider IDs."
                    : localReason,
                confidence: usesMetadataProviders ? .medium : .high,
                safety: .reversible,
                decision: .checked,
                requiresReview: false,
                usedNetworkData: usesMetadataProviders,
                metadataProviders: usesMetadataProviders ? [.anilist, .tvmaze, .wikidata] : [],
                confidenceExplanation: usesMetadataProviders
                    ? "Network apply: uses no-key anime providers when evidence is strong; otherwise it writes a local AnimeInfo checkpoint and leaves provider IDs blank."
                    : localConfidence,
                correctionOptions: [.keepTitle, .custom],
                reviewTags: watchingSidecarReviewTags(operation: .createAnimeInfo),
                receipt: "Prepare \(config.animeInfoFileName) for \(path)"
            )
        }
    }

    private func canCreateLocalWatchingSidecar(
        for series: LibraryVideoSeriesSnapshot?,
        path: String
    ) -> Bool {
        guard let series,
              series.localVideoCount > 0,
              !path.split(separator: "/").isEmpty else {
            return false
        }
        return true
    }

    private func refreshAnimeInfoItems(
        inspection: LibraryInspection,
        context: LibraryPipelineContext,
        config: SableLibraryConfig
    ) -> [LibraryPlanItem] {
        guard context.options.stages.useMetadataProviders,
              !hasPendingWatchingRawPreparation(in: context.plan, config: config) else { return [] }
        return inspection.videoSeries
            .filter(\.hasAnimeInfo)
            .filter { series in
                staleAnimeInfo(series)
                    || (series.primarySourceID == nil && series.localFileSnapshotChanged)
            }
            .sorted { $0.path < $1.path }
            .map { series in
                let animeInfoPath = animeInfoPath(for: series.path, config: config)
                let exactSourceIDs = exactRefreshSourceIDs(for: series)
                return LibraryPlanItem(
                    stage: .comicInfo,
                    operation: .refreshAnimeInfo,
                    currentPath: series.path,
                    proposedPath: animeInfoPath,
                    reason: "Refresh \(config.animeInfoFileName) from enabled metadata providers when the match is strong.",
                    confidence: .medium,
                    safety: .reversible,
                    decision: .unchecked,
                    requiresReview: false,
                    usedNetworkData: true,
                    metadataProviders: [.anilist, .tvmaze, .wikidata],
                    confidenceExplanation: "Network apply: updates provider IDs only when title plus provider bridge evidence is strong.",
                    correctionOptions: [.keepTitle, .custom],
                    manualSourceIDs: exactSourceIDs,
                    reviewTags: watchingSidecarReviewTags(operation: .refreshAnimeInfo)
                        + (exactSourceIDs.isEmpty ? [] : [exactIDRefreshEvidenceTag]),
                    receipt: "Refresh \(config.animeInfoFileName) for \(series.path)"
                )
            }
    }

    private func hasPendingWatchingRawPreparation(in plan: LibraryPlan, config: SableLibraryConfig) -> Bool {
        let matcher = SableLibraryFileTypeMatcher(config: config)
        return plan.items.contains { item in
            guard item.stage == .prepareRawFiles else {
                return false
            }
            if item.operation == .renameFolder {
                return isWatchingLibraryPath(item.currentPath)
                    || item.proposedPath.map(isWatchingLibraryPath) == true
            }
            guard item.operation == .sortIntoFolder || item.operation == .cleanRawName else {
                return false
            }
            let currentURL = URL(fileURLWithPath: item.currentPath)
            let proposedURL = item.proposedPath.map { URL(fileURLWithPath: $0) }
            return matcher.isVideo(url: currentURL, isDirectory: false)
                || proposedURL.map { matcher.isVideo(url: $0, isDirectory: false) } == true
        }
    }

    private func isWatchingLibraryPath(_ path: String) -> Bool {
        guard let firstComponent = path.split(separator: "/").first else {
            return false
        }
        switch String(firstComponent).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "videos", "tv", "tv shows", "movies", "anime tv", "anime movies", "other videos":
            return true
        default:
            return false
        }
    }

    private func hasWatchingSourceIDHint(_ series: LibraryVideoSeriesSnapshot?) -> Bool {
        series?.identityGraph?.sourceIDs.contains { sourceID in
            switch sourceID.provider {
            case .myAnimeList, .anilist, .tvmaze, .wikidata, .tmdb, .tvdb, .imdb:
                return true
            case .mangabaka, .ranobedb, .openLibrary, .local:
                return false
            }
        } == true
    }

    private func hasWatchingSourceIDHint(in path: String) -> Bool {
        let folderName = URL(fileURLWithPath: path).lastPathComponent
        return sourceIDHints(in: folderName).contains { sourceID in
            switch sourceID.provider {
            case .myAnimeList, .anilist, .tvmaze, .wikidata, .tmdb, .tvdb, .imdb:
                return true
            case .mangabaka, .ranobedb, .openLibrary, .local:
                return false
            }
        }
    }

    private func readingMetadataProviders(from stages: LibraryPipelineStageOptions, seriesPath: String? = nil) -> [SableLibraryMetadataProvider] {
        var providers: [SableLibraryMetadataProvider] = []
        if stages.useMangaBaka {
            providers.append(.mangabaka)
        }
        if stages.useMetadataProviders {
            providers.append(.ranobedb)
            providers.append(.openLibrary)
            providers.append(.wikidata)
            providers.append(.anilist)
        }
        return providers
    }

    private func readingProviderRoute(
        stages: LibraryPipelineStageOptions,
        seriesPath: String,
        series: LibrarySeriesSnapshot?,
        books: [LibraryBookSnapshot],
        service: SableLibraryService
    ) -> ReadingProviderRoute {
        let enabled = readingMetadataProviders(from: stages)
        guard !enabled.isEmpty else {
            return ReadingProviderRoute(
                providers: [],
                requiresReview: false,
                explanation: "Local-only first pass: creates ComicInfo from folder evidence without provider calls.",
                reviewTags: ["provider-route-local"]
            )
        }

        let namingPolicy = SableLibraryNamingPolicy()
        let typeHints = readingRouteTypeHints(
            seriesPath: seriesPath,
            series: series,
            books: books,
            service: service
        )
        let normalizedHints = Set(typeHints.map { namingPolicy.normalizedMediaType($0) })
        let hasComicArchive = books.contains { ["cbz", "cbr", "cb7"].contains($0.fileExtension.lowercased()) }
        let hasMultipleVolumeEPUBs = books.filter { book in
            guard ["epub", "kepub"].contains(book.fileExtension.lowercased()) else { return false }
            let title = (book.fileName as NSString).deletingPathExtension
            return service.volumeOrChapterSuffix(in: title) != nil
        }.count >= 2

        func available(_ providers: [SableLibraryMetadataProvider]) -> [SableLibraryMetadataProvider] {
            providers.filter { enabled.contains($0) }
        }

        if normalizedHints.contains("Book") {
            let providers = available([.openLibrary, .wikidata])
            return ReadingProviderRoute(
                providers: providers,
                requiresReview: providers.isEmpty,
                explanation: providers.isEmpty
                    ? "First pass sees ordinary prose, but book metadata providers are not enabled. Use Local or choose a provider before the next metadata pass."
                    : "First pass sees ordinary prose, so MangaBaka/RanobeDB stay asleep. Open Library and Wikidata are optional enrichment; if no trusted provider match lands, Sable still writes a local book sidecar.",
                reviewTags: ["provider-route-prose"]
            )
        }

        if normalizedHints.contains("Novel") || isLightNovelLane(seriesPath) || hasMultipleVolumeEPUBs {
            let providers = available([.ranobedb, .mangabaka, .anilist])
            let hasRanobeDB = providers.contains(.ranobedb)
            return ReadingProviderRoute(
                providers: providers,
                requiresReview: !hasRanobeDB,
                explanation: hasRanobeDB
                    ? "First pass sees light-novel evidence, so RanobeDB gets first claim on series identity. MangaBaka and AniList can corroborate, but split book-level results stay reviewable."
                    : "First pass sees light-novel evidence, but RanobeDB is not enabled. Use Find Provider Match, Use Local, or choose the missing provider before the next metadata pass.",
                reviewTags: ["provider-route-light-novel"]
            )
        }

        if normalizedHints.contains(where: { ["Manga", "Manhwa", "Manhua", "OEL"].contains($0) }) || hasComicArchive || isMangaLane(seriesPath) {
            let providers = available([.mangabaka, .anilist])
            let hasMangaBaka = providers.contains(.mangabaka)
            return ReadingProviderRoute(
                providers: providers,
                requiresReview: !hasMangaBaka,
                explanation: hasMangaBaka
                    ? "First pass sees manga/comic evidence, so MangaBaka owns identity. AniList can corroborate series identity without moving prose catalogs into this pass."
                    : "First pass sees manga/comic evidence, but MangaBaka is not enabled. Use Find Provider Match, Use Local, or choose a provider before the next metadata pass.",
                reviewTags: ["provider-route-manga"]
            )
        }

        return ReadingProviderRoute(
            providers: [],
            requiresReview: true,
            explanation: "First pass found no strong prose, light-novel, or manga route. Leave this for Find Provider Match, Use Local, or a type correction before running the next metadata pass.",
            reviewTags: ["provider-route-needs-choice", "needs-provider-choice"]
        )
    }

    private func sidecarPassReviewTags(
        _ tags: [String],
        operation: LibraryPlanOperation,
        providers: [SableLibraryMetadataProvider],
        hasRanobeDBID: Bool,
        refreshesRanobeDBBooks: Bool = false
    ) -> [String] {
        var result = tags
        result.append("metadata-pass")
        switch operation {
        case .createComicInfo:
            result.append("metadata-pass-identity")
            result.append("metadata-checkpoint-identity")
        case .refreshComicInfo:
            result.append("metadata-pass-refresh")
            result.append("metadata-checkpoint-refresh")
            if refreshesRanobeDBBooks {
                result.append("metadata-pass-detail")
                result.append("metadata-checkpoint-detail")
            }
        default:
            break
        }

        if result.contains("provider-route-needs-choice") || result.contains("needs-provider-choice") {
            result.append("metadata-checkpoint-choice")
        }

        if providers.contains(.mangabaka) {
            result.append("metadata-provider-identity-mangabaka")
        }
        if providers.contains(.ranobedb) {
            result.append("metadata-provider-ranobedb-series")
            if refreshesRanobeDBBooks {
                result.append("metadata-provider-ranobedb-books")
            }
        }
        if providers.contains(.openLibrary) {
            result.append("metadata-provider-openlibrary")
        }
        if providers.contains(.wikidata) {
            result.append("metadata-provider-wikidata")
        }
        return uniqueStrings(result)
    }

    private func watchingSidecarReviewTags(operation: LibraryPlanOperation) -> [String] {
        var tags = [
            "metadata-pass",
            "metadata-checkpoint-watching",
            "metadata-provider-watching"
        ]
        switch operation {
        case .createAnimeInfo:
            tags.append("metadata-pass-identity")
            tags.append("metadata-checkpoint-identity")
        case .refreshAnimeInfo:
            tags.append("metadata-pass-refresh")
            tags.append("metadata-checkpoint-refresh")
        default:
            break
        }
        return uniqueStrings(tags)
    }

    private func isMetadataChoiceItem(_ item: LibraryPlanItem) -> Bool {
        item.reviewTags.contains("metadata-checkpoint-choice")
            || item.reviewTags.contains("provider-route-needs-choice")
            || item.reviewTags.contains("needs-provider-choice")
    }

    private func seriesHasRanobeDBID(_ series: LibrarySeriesSnapshot?) -> Bool {
        guard let series else { return false }
        if series.primarySourceID?.provider == .ranobedb {
            return true
        }
        return series.identityGraph?.sourceIDs.contains { $0.provider == .ranobedb } == true
    }

    private func readingRouteTypeHints(
        seriesPath: String,
        series: LibrarySeriesSnapshot?,
        books: [LibraryBookSnapshot],
        service: SableLibraryService
    ) -> [String] {
        let namingPolicy = SableLibraryNamingPolicy()
        var hints: [String] = []

        if let mediaType = series?.mediaType {
            hints.append(mediaType)
        }
        if isBooksLane(seriesPath) {
            hints.append(SableLibraryReadingType.book.rawValue)
        }
        for value in [seriesPath, series?.displayName, series?.localTitle, series?.preferredTitle].compactMap({ $0 }) {
            if let hint = namingPolicy.mediaTypeHint(in: value) {
                hints.append(hint)
            }
        }
        for book in books.prefix(8) {
            let raw = (book.fileName as NSString).deletingPathExtension
            if let hint = namingPolicy.mediaTypeHint(in: raw) {
                hints.append(hint)
            }
        }

        return uniqueStrings(hints)
    }

    private func isLightNovelLane(_ path: String) -> Bool {
        path.split(separator: "/")
            .first
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .map { $0 == "light novels" || $0 == "light novel" }
            ?? false
    }

    private func isBooksLane(_ path: String) -> Bool {
        path.split(separator: "/")
            .first
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .map { $0 == "books" || $0 == "book" }
            ?? false
    }

    private func isMangaLane(_ path: String) -> Bool {
        path.split(separator: "/")
            .first
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .map { ["manga", "manhwa", "manhua", "oel", "comics", "comic books", "graphic novels"].contains($0) }
            ?? false
    }

    private func confidenceExplanationForReadingProviders(_ providers: [SableLibraryMetadataProvider]) -> String {
        guard !providers.isEmpty else {
            return "Local-only write: creates ComicInfo.json from the current folder name without network use."
        }
        if providers.contains(.mangabaka), providers.contains(.ranobedb) {
            return "Network apply: uses RanobeDB for light-novel identity, MangaBaka for manga identity, and AniList as a supporting check."
        }
        if providers.contains(.mangabaka) {
            return "Network apply: ranks MangaBaka candidates with title similarity, AniList support, and on-device ML assist, then skips weak matches."
        }
        if (providers.contains(.openLibrary) || providers.contains(.wikidata)), !providers.contains(.ranobedb) {
            return "Network apply: checks English-first Open Library and Wikidata for ordinary book metadata behind strict confidence gates."
        }
        return "Network apply: adds specialist provider enrichment such as RanobeDB light-novel book mapping and AniList bridge IDs only when confidence is strong."
    }

    private func staleComicInfo(_ series: LibrarySeriesSnapshot) -> Bool {
        if !series.sourceFreshness.isEmpty {
            return series.sourceFreshness.contains { !$0.isFresh() }
        }
        guard let lastChecked = series.comicInfoLastChecked,
              let checkedDate = ISO8601DateFormatter().date(from: lastChecked) else {
            return true
        }
        return Date().timeIntervalSince(checkedDate) > 30 * 24 * 60 * 60
    }

    private func staleAnimeInfo(_ series: LibraryVideoSeriesSnapshot) -> Bool {
        if !series.sourceFreshness.isEmpty {
            return series.sourceFreshness.contains { !$0.isFresh() }
        }
        guard let lastChecked = series.animeInfoLastChecked,
              let checkedDate = ISO8601DateFormatter().date(from: lastChecked) else {
            return true
        }
        return Date().timeIntervalSince(checkedDate) > 30 * 24 * 60 * 60
    }

    private func mismatchedComicInfoType(_ series: LibrarySeriesSnapshot) -> Bool {
        let namingPolicy = SableLibraryNamingPolicy()
        let hintedType = [
            series.localTitle,
            series.displayName,
            series.path
        ]
            .compactMap { $0 }
            .compactMap { namingPolicy.mediaTypeHint(in: $0) }
            .first

        if let hintedType,
           let mediaType = series.mediaType,
           namingPolicy.normalizedMediaType(mediaType) != hintedType {
            return true
        }

        if let expectedType = series.mangaBakaExpectedType,
           let mediaType = series.mediaType,
           namingPolicy.normalizedMediaType(mediaType) != namingPolicy.normalizedMediaType(expectedType) {
            return true
        }

        return series.mangaBakaTypeMatched == false && hintedType != nil
    }

    private func comicInfoPath(for seriesPath: String, config: SableLibraryConfig) -> String {
        let folder = seriesPath
            .replacingOccurrences(of: #"/+"#, with: "/", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return folder.isEmpty ? config.comicInfoFileName : "\(folder)/\(config.comicInfoFileName)"
    }

    private func animeInfoPath(for seriesPath: String, config: SableLibraryConfig) -> String {
        let folder = seriesPath
            .replacingOccurrences(of: #"/+"#, with: "/", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return folder.isEmpty ? config.animeInfoFileName : "\(folder)/\(config.animeInfoFileName)"
    }

    private func examples(from items: [LibraryPlanItem], title: String) -> [LibraryPlanExample] {
        items.prefix(3).map { item in
            LibraryPlanExample(
                title: title,
                before: item.currentPath,
                after: item.proposedPath,
                reason: item.reason
            )
        }
    }

    func applyChecked(
        plan: LibraryPlan,
        stage: LibraryPipelineStage = .comicInfo,
        options: LibraryPipelineOptions? = nil,
        coverDownloadPass: SableLibraryCoverDownloadPass = .combined,
        service: SableLibraryService
    ) async -> LibraryApplyResult {
        let checked = plan.checkedItems.filter { $0.stage == stage }
        guard !checked.isEmpty else { return .empty }

        let actionable = checked.filter(\.isApplyableComicInfoOperation)
        guard !actionable.isEmpty else {
            return LibraryApplyResult(
                appliedCount: 0,
                skippedCount: checked.count,
                receiptPath: nil,
                summary: "No checked ComicInfo or AnimeInfo writes were ready. Check a reversible sidecar row first."
            )
        }

        let root = URL(fileURLWithPath: plan.rootPath, isDirectory: true)
        let config = service.currentConfig()
        var applied: [String] = []
        var appliedPaths: [LibraryAppliedPlanPath] = []
        let workBatch = sidecarCompleteWorkBatch(from: actionable, options: options)
        var skipped: [String] = []

        if stage == .covers {
            let coverWorkBatch = mergedCoverDownloadWorkBatch(from: workBatch)
            return await applyCoverDownloadBatch(
                checkedCount: coverWorkBatch.count,
                workBatch: coverWorkBatch,
                root: root,
                config: config,
                downloadPass: coverDownloadPass,
                service: service
            )
        }

        for (index, item) in workBatch.enumerated() {
            let completedCount = index + 1
            do {
                try service.checkForCancellation()
                service.reportProgressSnapshot(SableLibraryProgressSnapshot(
                    title: "Applying metadata sidecars",
                    message: "Writing sidecar \(completedCount) of \(workBatch.count): \(item.currentPath)",
                    completedUnitCount: index,
                    totalUnitCount: workBatch.count
                ))
                defer {
                    service.reportProgressSnapshot(SableLibraryProgressSnapshot(
                        title: "Applying metadata sidecars",
                        message: "Checked sidecar \(completedCount) of \(workBatch.count): \(item.currentPath)",
                        completedUnitCount: completedCount,
                        totalUnitCount: workBatch.count
                    ))
                }
                service.reportProgress("Metadata pass \(index + 1)/\(workBatch.count): \(item.currentPath)")
                switch item.operation {
                case .createComicInfo:
                    let receipt = try await createComicInfo(item: item, root: root, config: config, service: service)
                    applied.append(receipt)
                    appliedPaths.append(appliedPlanPath(for: item))
                case .refreshComicInfo:
                    let receipt = try await refreshComicInfo(item: item, root: root, config: config, service: service)
                    applied.append(receipt)
                    appliedPaths.append(appliedPlanPath(for: item))
                case .createAnimeInfo:
                    let receipt = try await createAnimeInfo(item: item, root: root, config: config, service: service)
                    applied.append(receipt)
                    appliedPaths.append(appliedPlanPath(for: item))
                case .refreshAnimeInfo:
                    let receipt = try await refreshAnimeInfo(item: item, root: root, config: config, service: service)
                    applied.append(receipt)
                    appliedPaths.append(appliedPlanPath(for: item))
                case .inspectOnly, .repairEpubPackage, .repairAppleBooksCompatibility, .cleanRawName, .sortIntoFolder, .renameFolder, .renameFile, .duplicateDecision, .skip:
                    skipped.append("\(item.currentPath): unsupported ComicInfo operation")
                }

                if item.usedNetworkData, index < workBatch.count - 1 {
                    try await delayForMetadataProviders(
                        item: item,
                        nextIndex: index + 2,
                        totalCount: workBatch.count,
                        service: service,
                        config: config
                    )
                }
            } catch {
                skipped.append("\(item.currentPath): \(error.localizedDescription)")
            }
        }

        let report = reportText(applied: applied, skipped: skipped)
        let receiptPath: String?
        do {
            try service.writeReport(report, named: config.reports.metadataReport, root: root, config: config)
            try service.writeReport(report, named: config.reports.runSummaryReport, root: root, config: config)
            receiptPath = service
                .reportDirectory(root: root, config: config)
                .appendingPathComponent(config.reports.metadataReport)
                .path(percentEncoded: false)
        } catch {
            receiptPath = nil
        }

        if !applied.isEmpty {
            service.invalidateScanCache(for: root)
        }

        return LibraryApplyResult(
            appliedCount: applied.count,
            skippedCount: checked.count - applied.count,
            receiptPath: receiptPath,
            summary: report,
            appliedPaths: appliedPaths
        )
    }

    private func mergedCoverDownloadWorkBatch(
        from items: [LibraryPlanItem]
    ) -> [LibraryPlanItem] {
        var mergedItems: [LibraryPlanItem] = []
        var indexByPath: [String: Int] = [:]

        for item in items {
            guard let existingIndex = indexByPath[item.currentPath] else {
                indexByPath[item.currentPath] = mergedItems.count
                mergedItems.append(item)
                continue
            }

            var merged = mergedItems[existingIndex]
            merged.reviewTags = SableLibraryCoverDownloadPlanner.uniqueNonEmpty(
                merged.reviewTags + item.reviewTags
            )
            merged.coverSearchTitles = SableLibraryCoverDownloadPlanner.uniqueNonEmpty(
                merged.coverSearchTitles + item.coverSearchTitles
            )
            var seenMatches = Set(merged.manualCoverSeriesMatches.map(\.id))
            merged.manualCoverSeriesMatches.append(contentsOf: item.manualCoverSeriesMatches.filter {
                seenMatches.insert($0.id).inserted
            })
            merged.manualSourceIDs = Array(
                Dictionary(
                    (merged.manualSourceIDs + item.manualSourceIDs).map { ($0.stableKey, $0) },
                    uniquingKeysWith: { first, _ in first }
                ).values
            )
            mergedItems[existingIndex] = merged
        }

        return mergedItems
    }

    private struct CoverDownloadBatchTaskResult: Sendable {
        let oneBasedIndex: Int
        let receipt: String?
        let appliedPath: LibraryAppliedPlanPath?
        let skippedReason: String?
    }

    private struct CoverDownloadSeriesTimeoutError: LocalizedError, Sendable {
        let minutes: Int

        var errorDescription: String? {
            "Cover lookup exceeded \(minutes) minutes. The series was left unchanged so the rest of the batch could continue."
        }
    }

    private func applyCoverDownloadBatch(
        checkedCount: Int,
        workBatch: [LibraryPlanItem],
        root: URL,
        config: SableLibraryConfig,
        downloadPass: SableLibraryCoverDownloadPass,
        service: SableLibraryService
    ) async -> LibraryApplyResult {
        let startedAt = Date()
        let parallelism = max(
            1,
            min(coverDownloadMaxParallelism(for: downloadPass), workBatch.count)
        )
        let verifiesExistingStoreEvidence = workBatch.allSatisfy {
            $0.reviewTags.contains("cover-manifest-unverified")
        }
        let progressTitle: String
        switch downloadPass {
        case .mangaBakaBaseline:
            progressTitle = "Filling MangaBaka cover gaps"
        case .storeQualityUpgrade:
            progressTitle = "Finding cover quality upgrades"
        case .combined:
            progressTitle = verifiesExistingStoreEvidence
                ? "Verifying existing cover evidence"
                : "Downloading series covers"
        }
        var applied: [String] = []
        var appliedPaths: [LibraryAppliedPlanPath] = []
        var skipped: [String] = []
        var stoppedEarly = false
        var scheduledCount = 0

        service.reportProgressSnapshot(SableLibraryProgressSnapshot(
            title: progressTitle,
            message: coverBatchStartMessage(
                seriesCount: workBatch.count,
                parallelism: parallelism,
                pass: downloadPass,
                verifiesExistingStoreEvidence: verifiesExistingStoreEvidence
            ),
            completedUnitCount: 0,
            totalUnitCount: workBatch.count
        ))

        let results = await withTaskGroup(of: CoverDownloadBatchTaskResult.self) { group in
            let initialCount = min(parallelism, workBatch.count)
            for index in 0..<initialCount {
                let item = workBatch[index]
                let appliedPath = appliedPlanPath(for: item)
                group.addTask {
                    await self.applyCoverDownloadBatchItem(
                        item: item,
                        oneBasedIndex: index + 1,
                        appliedPath: appliedPath,
                        root: root,
                        config: config,
                        downloadPass: downloadPass,
                        service: service
                    )
                }
            }
            scheduledCount = initialCount

            var collected: [CoverDownloadBatchTaskResult] = []
            while let result = await group.next() {
                collected.append(result)
                let completedCount = collected.count
                let timing = coverBatchTiming(
                    startedAt: startedAt,
                    completedCount: completedCount,
                    totalCount: workBatch.count,
                    parallelism: parallelism
                )
                service.reportProgressSnapshot(SableLibraryProgressSnapshot(
                    title: progressTitle,
                    message: "Checked \(completedCount) of \(workBatch.count) series. \(timing)",
                    completedUnitCount: completedCount,
                    totalUnitCount: workBatch.count
                ))
                service.reportProgress(
                    "Covers \(completedCount)/\(workBatch.count): \(timing)"
                )

                guard scheduledCount < workBatch.count else { continue }
                do {
                    try service.checkForCancellation()
                    let item = workBatch[scheduledCount]
                    let oneBasedIndex = scheduledCount + 1
                    let appliedPath = appliedPlanPath(for: item)
                    group.addTask {
                        await self.applyCoverDownloadBatchItem(
                            item: item,
                            oneBasedIndex: oneBasedIndex,
                            appliedPath: appliedPath,
                            root: root,
                            config: config,
                            downloadPass: downloadPass,
                            service: service
                        )
                    }
                    scheduledCount += 1
                } catch {
                    stoppedEarly = true
                    group.cancelAll()
                }
            }
            return collected
        }

        for result in results.sorted(by: { $0.oneBasedIndex < $1.oneBasedIndex }) {
            if let skippedReason = result.skippedReason {
                skipped.append(skippedReason)
            } else {
                if let receipt = result.receipt {
                    applied.append(receipt)
                }
                if let appliedPath = result.appliedPath {
                    appliedPaths.append(appliedPath)
                }
            }
        }
        if stoppedEarly {
            skipped.append(
                "Cover batch stopped after \(results.count) completed series; \(max(0, workBatch.count - scheduledCount)) unscheduled series stayed untouched."
            )
        }

        let timing = coverBatchTiming(
            startedAt: startedAt,
            completedCount: results.count,
            totalCount: workBatch.count,
            parallelism: parallelism
        )
        let report = reportText(applied: applied, skipped: skipped)
            + "\n\nCover batch timing\n\(timing)\n"
        let receiptPath = writeMetadataReport(
            report,
            root: root,
            config: config,
            service: service
        )

        if !applied.isEmpty {
            service.invalidateScanCache(for: root)
        }

        return LibraryApplyResult(
            appliedCount: applied.count,
            skippedCount: max(0, checkedCount - applied.count),
            receiptPath: receiptPath,
            summary: report,
            appliedPaths: appliedPaths
        )
    }

    private func applyCoverDownloadBatchItem(
        item: LibraryPlanItem,
        oneBasedIndex: Int,
        appliedPath: LibraryAppliedPlanPath,
        root: URL,
        config: SableLibraryConfig,
        downloadPass: SableLibraryCoverDownloadPass,
        service: SableLibraryService
    ) async -> CoverDownloadBatchTaskResult {
        do {
            let receipt = try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask {
                    try await self.refreshComicInfo(
                        item: item,
                        root: root,
                        config: config,
                        coverDownloadPass: downloadPass,
                        service: service
                    )
                }
                group.addTask {
                    let timeout = coverDownloadSeriesTimeout(for: downloadPass)
                    try await Task.sleep(for: timeout)
                    throw CoverDownloadSeriesTimeoutError(
                        minutes: downloadPass == .mangaBakaBaseline ? 2 : 4
                    )
                }

                defer { group.cancelAll() }
                guard let first = try await group.next() else {
                    throw CancellationError()
                }
                return first
            }
            return CoverDownloadBatchTaskResult(
                oneBasedIndex: oneBasedIndex,
                receipt: receipt,
                appliedPath: appliedPath,
                skippedReason: nil
            )
        } catch {
            let folder = root.appendingPathComponent(
                item.currentPath,
                isDirectory: true
            )
            let cleanupNotes = coverDownloadService.cleanupInterruptedCoverDownload(
                folder: folder,
                root: root
            )
            let cleanupSummary = cleanupNotes.isEmpty
                ? ""
                : " " + cleanupNotes.joined(separator: " ")
            return CoverDownloadBatchTaskResult(
                oneBasedIndex: oneBasedIndex,
                receipt: nil,
                appliedPath: nil,
                skippedReason: "\(item.currentPath): \(error.localizedDescription)"
                    + cleanupSummary
            )
        }
    }

    private func coverBatchTiming(
        startedAt: Date,
        completedCount: Int,
        totalCount: Int,
        parallelism: Int
    ) -> String {
        let elapsed = max(0, Date().timeIntervalSince(startedAt))
        guard completedCount > 0, elapsed > 0 else {
            return "Elapsed \(coverBatchDuration(elapsed)); using up to \(parallelism) simultaneous searches."
        }

        let ratePerMinute = Double(completedCount) / elapsed * 60
        let remainingCount = max(0, totalCount - completedCount)
        let remainingSeconds = ratePerMinute > 0
            ? Double(remainingCount) / ratePerMinute * 60
            : 0
        let remaining = remainingCount > 0
            ? "; about \(coverBatchDuration(remainingSeconds)) remaining"
            : ""
        return "Elapsed \(coverBatchDuration(elapsed)); \(String(format: "%.1f", ratePerMinute)) series/min\(remaining); up to \(parallelism) simultaneous searches."
    }

    private func coverBatchStartMessage(
        seriesCount: Int,
        parallelism: Int,
        pass: SableLibraryCoverDownloadPass,
        verifiesExistingStoreEvidence: Bool
    ) -> String {
        switch pass {
        case .mangaBakaBaseline:
            return "Starting \(seriesCount) series with up to \(parallelism) simultaneous MangaBaka lookups."
        case .storeQualityUpgrade:
            return "Starting \(seriesCount) series with up to \(parallelism) simultaneous BookLive, BookWalker, or Amazon checks."
        case .combined:
            return verifiesExistingStoreEvidence
                ? "Starting \(seriesCount) series with up to \(parallelism) simultaneous store checks."
                : "Starting \(seriesCount) series with up to \(parallelism) simultaneous searches."
        }
    }

    private func coverBatchDuration(_ seconds: TimeInterval) -> String {
        let rounded = max(0, Int(seconds.rounded()))
        let hours = rounded / 3_600
        let minutes = (rounded % 3_600) / 60
        let remainingSeconds = rounded % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        if minutes > 0 {
            return "\(minutes)m \(remainingSeconds)s"
        }
        return "\(remainingSeconds)s"
    }

    func applyExactIDBatch(
        plan: LibraryPlan,
        stage: LibraryPipelineStage = .comicInfo,
        itemIDs: Set<LibraryPlanItem.ID>? = nil,
        options: LibraryPipelineOptions? = nil,
        service: SableLibraryService
    ) async -> LibraryApplyResult {
        let selectedRows = plan.items.filter { item in
            guard item.stage == stage else { return false }
            if let itemIDs {
                return itemIDs.contains(item.id)
            }
            return item.decision == .checked
        }
        guard !selectedRows.isEmpty else { return .empty }

        let refreshRows = selectedRows.filter(\.isExactIDBatchRefreshCandidate)
        guard !refreshRows.isEmpty else {
            return LibraryApplyResult(
                appliedCount: 0,
                skippedCount: selectedRows.count,
                receiptPath: nil,
                summary: "No exact-ID metadata refresh rows were ready. Rows that need search or manual review stay in the normal refresh route."
            )
        }

        let root = URL(fileURLWithPath: plan.rootPath, isDirectory: true)
        let config = service.currentConfig()
        var skipped: [String] = []
        let nonBatchCount = selectedRows.count - refreshRows.count
        if nonBatchCount > 0 {
            skipped.append("\(nonBatchCount) checked row(s) were not exact-ID refresh rows.")
        }

        let batchRows = refreshRows.compactMap { item in
            exactIDBatchWorkItem(
                from: item,
                root: root,
                config: config,
                service: service,
                skipped: &skipped
            )
        }

        guard !batchRows.isEmpty else {
            let report = exactIDBatchReportText(applied: [], skipped: skipped)
            let receiptPath = writeMetadataReport(report, root: root, config: config, service: service)
            return LibraryApplyResult(
                appliedCount: 0,
                skippedCount: selectedRows.count,
                receiptPath: receiptPath,
                summary: report
            )
        }

        var applied: [String] = []
        var appliedPaths: [LibraryAppliedPlanPath] = []
        let readingBatchRows = batchRows.filter { $0.operation == .refreshComicInfo }
        let rowBatchRows = batchRows.filter { $0.operation != .refreshComicInfo }

        if !readingBatchRows.isEmpty {
            let providerWaveResult = await applyExactIDReadingProviderWaves(
                items: readingBatchRows,
                root: root,
                config: config,
                service: service,
                options: options
            )
            applied.append(contentsOf: providerWaveResult.applied)
            appliedPaths.append(contentsOf: providerWaveResult.appliedPaths)
            skipped.append(contentsOf: providerWaveResult.skipped)
        }

        if !rowBatchRows.isEmpty {
            let rowBatchResult = await applyExactIDRowBatch(
                items: rowBatchRows,
                root: root,
                config: config,
                service: service,
                options: options
            )
            applied.append(contentsOf: rowBatchResult.applied)
            appliedPaths.append(contentsOf: rowBatchResult.appliedPaths)
            skipped.append(contentsOf: rowBatchResult.skipped)
        }

        let report = exactIDBatchReportText(applied: applied, skipped: skipped)
        let receiptPath = writeMetadataReport(report, root: root, config: config, service: service)

        if !applied.isEmpty {
            service.invalidateScanCache(for: root)
        }

        return LibraryApplyResult(
            appliedCount: applied.count,
            skippedCount: max(0, selectedRows.count - applied.count),
            receiptPath: receiptPath,
            summary: report,
            appliedPaths: appliedPaths
        )
    }

    private struct ExactIDBatchApplyOutcome: Sendable {
        let applied: [String]
        let appliedPaths: [LibraryAppliedPlanPath]
        let skipped: [String]
    }

    private struct ExactIDBatchTaskResult: Sendable {
        let oneBasedIndex: Int
        let receipt: String?
        let appliedPath: LibraryAppliedPlanPath?
        let skippedReason: String?
    }

    private struct ExactIDProviderWaveTaskResult: Sendable {
        let oneBasedIndex: Int
        let itemID: UUID
        let provider: SableLibraryMetadataProvider
        let receipt: String?
        let appliedPath: LibraryAppliedPlanPath?
        let skippedReason: String?
    }

    private struct ExactIDProviderWavePreparedWrite: Sendable {
        let oneBasedIndex: Int
        let itemID: UUID
        let provider: SableLibraryMetadataProvider
        let item: LibraryPlanItem
        let sidecarPath: String
        let data: Data
        let receipt: String
        let appliedPath: LibraryAppliedPlanPath
    }

    private struct ExactIDProviderWavePrepareResult: Sendable {
        let oneBasedIndex: Int
        let itemID: UUID
        let provider: SableLibraryMetadataProvider
        let preparedWrite: ExactIDProviderWavePreparedWrite?
        let skippedReason: String?
    }

    private func applyExactIDRowBatch(
        items: [LibraryPlanItem],
        root: URL,
        config: SableLibraryConfig,
        service: SableLibraryService,
        options: LibraryPipelineOptions?
    ) async -> ExactIDBatchApplyOutcome {
        var applied: [String] = []
        var appliedPaths: [LibraryAppliedPlanPath] = []
        var skipped: [String] = []
        let workBatch = sidecarCompleteWorkBatch(from: items, options: options)
        let parallelism = max(1, min(exactIDBatchMaxParallelism, workBatch.count))
        var chunkStart = 0

        while chunkStart < workBatch.count {
            let chunkEnd = min(workBatch.count, chunkStart + parallelism)
            let chunk = Array(workBatch[chunkStart..<chunkEnd])
            let results = await withTaskGroup(of: ExactIDBatchTaskResult.self) { group -> [ExactIDBatchTaskResult] in
                for (index, item) in chunk.enumerated() {
                    let oneBasedIndex = chunkStart + index + 1
                    group.addTask {
                        await self.applyExactIDBatchItem(
                            item: item,
                            oneBasedIndex: oneBasedIndex,
                            totalCount: workBatch.count,
                            root: root,
                            config: config,
                            service: service
                        )
                    }
                }

                var collected: [ExactIDBatchTaskResult] = []
                for await result in group {
                    collected.append(result)
                }
                return collected
            }

            for result in results.sorted(by: { $0.oneBasedIndex < $1.oneBasedIndex }) {
                if let skippedReason = result.skippedReason {
                    skipped.append(skippedReason)
                } else {
                    if let receipt = result.receipt {
                        applied.append(receipt)
                    }
                    if let appliedPath = result.appliedPath {
                        appliedPaths.append(appliedPath)
                    }
                }
            }

            chunkStart += parallelism
        }

        return ExactIDBatchApplyOutcome(applied: applied, appliedPaths: appliedPaths, skipped: skipped)
    }

    private func applyExactIDReadingProviderWaves(
        items: [LibraryPlanItem],
        root: URL,
        config: SableLibraryConfig,
        service: SableLibraryService,
        options: LibraryPipelineOptions?
    ) async -> ExactIDBatchApplyOutcome {
        let workBatch = sidecarCompleteWorkBatch(from: items, options: options)
        let rowOrder = Dictionary(uniqueKeysWithValues: workBatch.enumerated().map { ($0.element.id, $0.offset) })
        let rowsByID = Dictionary(uniqueKeysWithValues: workBatch.map { ($0.id, $0) })
        let localFileSnapshots = exactIDLocalFileSnapshots(
            for: workBatch,
            root: root,
            config: config,
            service: service
        )
        var providersByRow: [UUID: [SableLibraryMetadataProvider]] = [:]
        var receiptsByRow: [UUID: [SableLibraryMetadataProvider: String]] = [:]
        var pathsByRow: [UUID: LibraryAppliedPlanPath] = [:]
        var skipped: [String] = []

        for provider in exactReadingProviderWaveOrder(config: config) {
            let waveItems = workBatch.compactMap { item in
                exactIDProviderWaveWorkItem(
                    from: item,
                    provider: provider,
                    root: root,
                    config: config,
                    service: service
                )
            }
            guard !waveItems.isEmpty else { continue }

            service.reportProgress(exactIDProviderWaveQueueMessage(provider: provider, items: waveItems))
            let results = await applyExactIDProviderWave(
                provider: provider,
                items: waveItems,
                root: root,
                config: config,
                service: service,
                localFileSnapshots: localFileSnapshots
            )

            for result in results.sorted(by: { $0.oneBasedIndex < $1.oneBasedIndex }) {
                if let skippedReason = result.skippedReason {
                    skipped.append(skippedReason)
                } else {
                    providersByRow[result.itemID, default: []].append(result.provider)
                    if let receipt = result.receipt {
                        receiptsByRow[result.itemID, default: [:]][result.provider] = receipt
                    }
                    if let appliedPath = result.appliedPath {
                        pathsByRow[result.itemID] = appliedPath
                    }
                }
            }
        }

        let appliedIDs = providersByRow.keys.sorted {
            (rowOrder[$0] ?? Int.max) < (rowOrder[$1] ?? Int.max)
        }
        let applied = appliedIDs.compactMap { id -> String? in
            guard let item = rowsByID[id] else { return nil }
            let providers = uniqueProviders(providersByRow[id] ?? [])
                .map(\.displayName)
                .joined(separator: " -> ")
            if let ranobeDBReceipt = receiptsByRow[id]?[.ranobedb] {
                return "\(ranobeDBReceipt) [provider order: \(providers)]"
            }
            return "\(item.currentPath): refreshed \(providers)"
        }
        let appliedPaths = appliedIDs.compactMap { pathsByRow[$0] }

        return ExactIDBatchApplyOutcome(applied: applied, appliedPaths: appliedPaths, skipped: skipped)
    }

    private func exactIDLocalFileSnapshots(
        for items: [LibraryPlanItem],
        root: URL,
        config: SableLibraryConfig,
        service: SableLibraryService
    ) -> [UUID: SidecarLocalFileSnapshot] {
        let allBookItems = (try? service.bookItems(root: root, config: config)) ?? []
        return Dictionary(uniqueKeysWithValues: items.map { item in
            let folder = root.appendingPathComponent(item.currentPath, isDirectory: true)
            let folderPath = service.relativePath(for: folder, root: root)
            let nestedPrefix = folderPath.isEmpty ? "" : "\(folderPath)/"
            let bookItems = allBookItems.filter { book in
                folderPath.isEmpty || book.relativePath.hasPrefix(nestedPrefix)
            }
            return (
                item.id,
                SidecarLocalFileSnapshot(bookItems: bookItems, videoItems: [])
            )
        })
    }

    private func applyExactIDProviderWave(
        provider: SableLibraryMetadataProvider,
        items: [LibraryPlanItem],
        root: URL,
        config: SableLibraryConfig,
        service: SableLibraryService,
        localFileSnapshots: [UUID: SidecarLocalFileSnapshot]
    ) async -> [ExactIDProviderWaveTaskResult] {
        if provider == .anilist {
            return await applyExactIDAniListProviderWave(
                items: items,
                root: root,
                config: config,
                service: service,
                localFileSnapshots: localFileSnapshots
            )
        }

        let parallelism = max(1, min(exactIDBatchParallelism(for: provider), items.count))
        var preparedWrites: [ExactIDProviderWavePreparedWrite] = []
        var allResults: [ExactIDProviderWaveTaskResult] = []
        var chunkStart = 0
        var preparedCount = 0
        let fetchTitle = exactIDProviderWaveTitle(provider: provider, items: items)
        let writeTitle = exactIDProviderWaveWriteTitle(provider: provider, items: items)

        service.reportProgressSnapshot(SableLibraryProgressSnapshot(
            title: fetchTitle,
            message: exactIDProviderWaveFetchMessage(provider: provider, items: items),
            completedUnitCount: 0,
            totalUnitCount: items.count
        ))

        while chunkStart < items.count {
            let chunkEnd = min(items.count, chunkStart + parallelism)
            let chunk = Array(items[chunkStart..<chunkEnd])
            let results = await withTaskGroup(of: ExactIDProviderWavePrepareResult.self) { group -> [ExactIDProviderWavePrepareResult] in
                for (index, item) in chunk.enumerated() {
                    let oneBasedIndex = chunkStart + index + 1
                    group.addTask {
                        await self.prepareExactIDProviderWaveItem(
                            item: item,
                            provider: provider,
                            oneBasedIndex: oneBasedIndex,
                            totalCount: items.count,
                            root: root,
                            config: config,
                            service: service,
                            localFiles: localFileSnapshots[item.id]
                        )
                    }
                }

                var collected: [ExactIDProviderWavePrepareResult] = []
                for await result in group {
                    collected.append(result)
                }
                return collected
            }

            for result in results.sorted(by: { $0.oneBasedIndex < $1.oneBasedIndex }) {
                preparedCount += 1
                if let skippedReason = result.skippedReason {
                    allResults.append(ExactIDProviderWaveTaskResult(
                        oneBasedIndex: result.oneBasedIndex,
                        itemID: result.itemID,
                        provider: result.provider,
                        receipt: nil,
                        appliedPath: nil,
                        skippedReason: skippedReason
                    ))
                } else if let preparedWrite = result.preparedWrite {
                    preparedWrites.append(preparedWrite)
                }
                service.reportProgressSnapshot(SableLibraryProgressSnapshot(
                    title: fetchTitle,
                    message: exactIDProviderWaveFetchedMessage(
                        provider: provider,
                        items: items,
                        completed: preparedCount,
                        total: items.count
                    ),
                    completedUnitCount: preparedCount,
                    totalUnitCount: items.count
                ))
            }
            chunkStart += parallelism
        }

        let writes = preparedWrites.sorted { $0.oneBasedIndex < $1.oneBasedIndex }
        guard !writes.isEmpty else {
            return allResults
        }

        service.reportProgressSnapshot(SableLibraryProgressSnapshot(
            title: writeTitle,
            message: exactIDProviderWaveWriteMessage(provider: provider, completed: 0, total: writes.count),
            completedUnitCount: 0,
            totalUnitCount: writes.count
        ))

        var writeStart = 0
        var writtenCount = 0
        while writeStart < writes.count {
            let writeEnd = min(writes.count, writeStart + parallelism)
            let writeChunk = Array(writes[writeStart..<writeEnd])
            let writeResults = await withTaskGroup(of: ExactIDProviderWaveTaskResult.self) { group -> [ExactIDProviderWaveTaskResult] in
                for preparedWrite in writeChunk {
                    group.addTask {
                        self.writeExactIDProviderWaveItem(
                            preparedWrite,
                            root: root,
                            config: config,
                            service: service
                        )
                    }
                }

                var collected: [ExactIDProviderWaveTaskResult] = []
                for await result in group {
                    collected.append(result)
                }
                return collected
            }

            for result in writeResults.sorted(by: { $0.oneBasedIndex < $1.oneBasedIndex }) {
                writtenCount += 1
                allResults.append(result)
                service.reportProgressSnapshot(SableLibraryProgressSnapshot(
                    title: writeTitle,
                    message: exactIDProviderWaveWriteMessage(
                        provider: provider,
                        completed: writtenCount,
                        total: writes.count
                    ),
                    completedUnitCount: writtenCount,
                    totalUnitCount: writes.count
                ))
            }

            writeStart += parallelism
        }

        return allResults
    }

    private func applyExactIDAniListProviderWave(
        items: [LibraryPlanItem],
        root: URL,
        config: SableLibraryConfig,
        service: SableLibraryService,
        localFileSnapshots: [UUID: SidecarLocalFileSnapshot]
    ) async -> [ExactIDProviderWaveTaskResult] {
        let provider = SableLibraryMetadataProvider.anilist
        let parallelism = max(1, min(exactIDBatchParallelism(for: provider), items.count))
        let lookupIDsByItem = Dictionary(uniqueKeysWithValues: items.compactMap { item in
            aniListExactLookupSourceID(for: item).map { (item.id, $0) }
        })
        let lookupIDs = uniqueSourceIDs(Array(lookupIDsByItem.values))
        let fetchTitle = exactIDProviderWaveTitle(provider: provider, items: items)
        let writeTitle = exactIDProviderWaveWriteTitle(provider: provider, items: items)

        service.reportProgressSnapshot(SableLibraryProgressSnapshot(
            title: fetchTitle,
            message: "Fetching AniList support for \(sidecarCountText(items.count)) in grouped GraphQL requests.",
            completedUnitCount: 0,
            totalUnitCount: items.count
        ))

        let candidatesByKey = await metadataLookupService.aniListExactCandidates(
            sourceIDs: lookupIDs,
            mediaType: "MANGA",
            config: config
        )

        var preparedWrites: [ExactIDProviderWavePreparedWrite] = []
        var allResults: [ExactIDProviderWaveTaskResult] = []
        var chunkStart = 0
        var preparedCount = 0

        while chunkStart < items.count {
            let chunkEnd = min(items.count, chunkStart + parallelism)
            let chunk = Array(items[chunkStart..<chunkEnd])
            let results = await withTaskGroup(of: ExactIDProviderWavePrepareResult.self) { group -> [ExactIDProviderWavePrepareResult] in
                for (index, item) in chunk.enumerated() {
                    let oneBasedIndex = chunkStart + index + 1
                    let matchedSourceID = lookupIDsByItem[item.id]
                    let candidate = matchedSourceID.flatMap { candidatesByKey[$0.stableKey] }
                    group.addTask {
                        await self.prepareExactIDAniListProviderWaveItem(
                            item: item,
                            oneBasedIndex: oneBasedIndex,
                            totalCount: items.count,
                            matchedSourceID: matchedSourceID,
                            candidate: candidate,
                            root: root,
                            config: config,
                            service: service,
                            localFiles: localFileSnapshots[item.id]
                        )
                    }
                }

                var collected: [ExactIDProviderWavePrepareResult] = []
                for await result in group {
                    collected.append(result)
                }
                return collected
            }

            for result in results.sorted(by: { $0.oneBasedIndex < $1.oneBasedIndex }) {
                preparedCount += 1
                if let skippedReason = result.skippedReason {
                    allResults.append(ExactIDProviderWaveTaskResult(
                        oneBasedIndex: result.oneBasedIndex,
                        itemID: result.itemID,
                        provider: result.provider,
                        receipt: nil,
                        appliedPath: nil,
                        skippedReason: skippedReason
                    ))
                } else if let preparedWrite = result.preparedWrite {
                    preparedWrites.append(preparedWrite)
                }
                service.reportProgressSnapshot(SableLibraryProgressSnapshot(
                    title: fetchTitle,
                    message: "Prepared \(preparedCount) of \(items.count) AniList sidecar merge\(items.count == 1 ? "" : "s").",
                    completedUnitCount: preparedCount,
                    totalUnitCount: items.count
                ))
            }
            chunkStart += parallelism
        }

        let writes = preparedWrites.sorted { $0.oneBasedIndex < $1.oneBasedIndex }
        guard !writes.isEmpty else {
            return allResults
        }

        service.reportProgressSnapshot(SableLibraryProgressSnapshot(
            title: writeTitle,
            message: exactIDProviderWaveWriteMessage(provider: provider, completed: 0, total: writes.count),
            completedUnitCount: 0,
            totalUnitCount: writes.count
        ))

        var writeStart = 0
        var writtenCount = 0
        while writeStart < writes.count {
            let writeEnd = min(writes.count, writeStart + parallelism)
            let writeChunk = Array(writes[writeStart..<writeEnd])
            let writeResults = await withTaskGroup(of: ExactIDProviderWaveTaskResult.self) { group -> [ExactIDProviderWaveTaskResult] in
                for preparedWrite in writeChunk {
                    group.addTask {
                        self.writeExactIDProviderWaveItem(
                            preparedWrite,
                            root: root,
                            config: config,
                            service: service
                        )
                    }
                }

                var collected: [ExactIDProviderWaveTaskResult] = []
                for await result in group {
                    collected.append(result)
                }
                return collected
            }

            for result in writeResults.sorted(by: { $0.oneBasedIndex < $1.oneBasedIndex }) {
                writtenCount += 1
                allResults.append(result)
                service.reportProgressSnapshot(SableLibraryProgressSnapshot(
                    title: writeTitle,
                    message: exactIDProviderWaveWriteMessage(
                        provider: provider,
                        completed: writtenCount,
                        total: writes.count
                    ),
                    completedUnitCount: writtenCount,
                    totalUnitCount: writes.count
                ))
            }
            writeStart += parallelism
        }

        return allResults
    }

    private func applyExactIDBatchItem(
        item: LibraryPlanItem,
        oneBasedIndex: Int,
        totalCount: Int,
        root: URL,
        config: SableLibraryConfig,
        service: SableLibraryService
    ) async -> ExactIDBatchTaskResult {
        do {
            try service.checkForCancellation()
            service.reportProgress("ID batch refresh \(oneBasedIndex)/\(totalCount): \(item.currentPath)")
            switch item.operation {
            case .refreshComicInfo:
                let receipt = try await refreshComicInfo(item: item, root: root, config: config, service: service)
                return ExactIDBatchTaskResult(
                    oneBasedIndex: oneBasedIndex,
                    receipt: receipt,
                    appliedPath: appliedPlanPath(for: item),
                    skippedReason: nil
                )
            case .refreshAnimeInfo:
                let receipt = try await refreshAnimeInfo(item: item, root: root, config: config, service: service)
                return ExactIDBatchTaskResult(
                    oneBasedIndex: oneBasedIndex,
                    receipt: receipt,
                    appliedPath: appliedPlanPath(for: item),
                    skippedReason: nil
                )
            case .inspectOnly, .repairEpubPackage, .repairAppleBooksCompatibility, .cleanRawName, .sortIntoFolder, .createComicInfo, .createAnimeInfo, .renameFolder, .renameFile, .duplicateDecision, .skip:
                return ExactIDBatchTaskResult(
                    oneBasedIndex: oneBasedIndex,
                    receipt: nil,
                    appliedPath: nil,
                    skippedReason: "\(item.currentPath): unsupported exact-ID batch operation"
                )
            }
        } catch {
            return ExactIDBatchTaskResult(
                oneBasedIndex: oneBasedIndex,
                receipt: nil,
                appliedPath: nil,
                skippedReason: "\(item.currentPath): \(error.localizedDescription)"
            )
        }
    }

    private func prepareExactIDProviderWaveItem(
        item: LibraryPlanItem,
        provider: SableLibraryMetadataProvider,
        oneBasedIndex: Int,
        totalCount: Int,
        root: URL,
        config: SableLibraryConfig,
        service: SableLibraryService,
        localFiles: SidecarLocalFileSnapshot?
    ) async -> ExactIDProviderWavePrepareResult {
        do {
            try service.checkForCancellation()
            service.reportProgress("\(provider.displayName) fetch \(oneBasedIndex)/\(totalCount): \(item.currentPath)")
            let preparedWrite = try await preparedExactIDProviderWaveWrite(
                item: item,
                provider: provider,
                oneBasedIndex: oneBasedIndex,
                root: root,
                config: config,
                service: service,
                cachedLocalFiles: localFiles
            )
            return ExactIDProviderWavePrepareResult(
                oneBasedIndex: oneBasedIndex,
                itemID: item.id,
                provider: provider,
                preparedWrite: preparedWrite,
                skippedReason: nil
            )
        } catch {
            return ExactIDProviderWavePrepareResult(
                oneBasedIndex: oneBasedIndex,
                itemID: item.id,
                provider: provider,
                preparedWrite: nil,
                skippedReason: "\(provider.displayName): \(item.currentPath): \(error.localizedDescription)"
            )
        }
    }

    private func prepareExactIDAniListProviderWaveItem(
        item: LibraryPlanItem,
        oneBasedIndex: Int,
        totalCount: Int,
        matchedSourceID: SableLibrarySourceID?,
        candidate: SableLibraryProviderCandidate?,
        root: URL,
        config: SableLibraryConfig,
        service: SableLibraryService,
        localFiles: SidecarLocalFileSnapshot?
    ) async -> ExactIDProviderWavePrepareResult {
        let provider = SableLibraryMetadataProvider.anilist
        do {
            try service.checkForCancellation()
            service.reportProgress("AniList merge \(oneBasedIndex)/\(totalCount): \(item.currentPath)")
            guard let matchedSourceID else {
                throw CocoaError(.fileNoSuchFile)
            }
            let preparedWrite = try await preparedExactIDAniListProviderWaveWrite(
                item: item,
                oneBasedIndex: oneBasedIndex,
                matchedSourceID: matchedSourceID,
                candidate: candidate,
                root: root,
                config: config,
                service: service,
                cachedLocalFiles: localFiles
            )
            return ExactIDProviderWavePrepareResult(
                oneBasedIndex: oneBasedIndex,
                itemID: item.id,
                provider: provider,
                preparedWrite: preparedWrite,
                skippedReason: nil
            )
        } catch {
            return ExactIDProviderWavePrepareResult(
                oneBasedIndex: oneBasedIndex,
                itemID: item.id,
                provider: provider,
                preparedWrite: nil,
                skippedReason: "AniList: \(item.currentPath): \(error.localizedDescription)"
            )
        }
    }

    private func writeExactIDProviderWaveItem(
        _ preparedWrite: ExactIDProviderWavePreparedWrite,
        root: URL,
        config: SableLibraryConfig,
        service: SableLibraryService
    ) -> ExactIDProviderWaveTaskResult {
        do {
            try service.checkForCancellation()
            let sidecarURL = root.appendingPathComponent(preparedWrite.sidecarPath)
            try service.fileManager.createDirectory(
                at: sidecarURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try preparedWrite.data.write(to: sidecarURL, options: .atomic)
            recordSidecarTrainingEvent(
                item: preparedWrite.item,
                domain: .reading,
                provider: preparedWrite.provider,
                root: root,
                config: config,
                service: service
            )
            return ExactIDProviderWaveTaskResult(
                oneBasedIndex: preparedWrite.oneBasedIndex,
                itemID: preparedWrite.itemID,
                provider: preparedWrite.provider,
                receipt: preparedWrite.receipt,
                appliedPath: preparedWrite.appliedPath,
                skippedReason: nil
            )
        } catch {
            return ExactIDProviderWaveTaskResult(
                oneBasedIndex: preparedWrite.oneBasedIndex,
                itemID: preparedWrite.itemID,
                provider: preparedWrite.provider,
                receipt: nil,
                appliedPath: nil,
                skippedReason: "\(preparedWrite.provider.displayName): \(preparedWrite.item.currentPath): \(error.localizedDescription)"
            )
        }
    }

    private func preparedExactIDAniListProviderWaveWrite(
        item: LibraryPlanItem,
        oneBasedIndex: Int,
        matchedSourceID: SableLibrarySourceID,
        candidate: SableLibraryProviderCandidate?,
        root: URL,
        config: SableLibraryConfig,
        service: SableLibraryService,
        cachedLocalFiles: SidecarLocalFileSnapshot?
    ) async throws -> ExactIDProviderWavePreparedWrite {
        guard let proposedPath = item.proposedPath else {
            throw CocoaError(.fileNoSuchFile)
        }

        let folder = root.appendingPathComponent(item.currentPath, isDirectory: true)
        let comicInfoURL = root.appendingPathComponent(proposedPath)
        let existing = readComicInfo(url: comicInfoURL) ?? [:]
        let localTitle = service.textValue(existing["local_title"])
        let existingPreferredTitle = service.textValue(existing["preferred_title"])
            ?? service.textValue(existing["title"])
        let title = organizerTitle(from: folder.lastPathComponent, service: service)
        let source = service.textValue(existing["source"])?.lowercased()
        let existingTitleQueries = source == "mangabaka" ? [] : [localTitle, existingPreferredTitle].compactMap { $0 }
        let localFiles = cachedLocalFiles
            ?? sidecarLocalFileSnapshot(folder: folder, root: root, config: config, service: service, includeBooks: true)
        let queryPlan = mangaBakaQueryPlan(
            primaryTitle: title,
            extraTitles: existingTitleQueries,
            config: config,
            service: service,
            localFiles: localFiles
        )
        var localOnlyItem = item
        localOnlyItem.usedNetworkData = false
        localOnlyItem.metadataProviders = []
        var comicInfo = try await comicInfoPayload(
            item: localOnlyItem,
            queryPlan: queryPlan,
            folder: folder,
            root: root,
            config: config,
            existing: existing,
            service: service,
            localFiles: localFiles
        )

        let sourceIDs = sourceIDs(
            from: comicInfo,
            extraIDs: item.manualSourceIDs + [matchedSourceID],
            service: service
        )
        if let candidate,
           let enrichment = metadataLookupService.readingCatalogEnrichment(
            aniListCandidate: candidate,
            matchedSourceID: matchedSourceID,
            existingSourceIDs: sourceIDs,
            year: integerValue(comicInfo["year"]),
            config: config
           ) {
            apply(
                readingEnrichment: enrichment,
                to: &comicInfo,
                folder: folder,
                root: root,
                config: config,
                service: service,
                localFiles: localFiles
            )
        } else {
            markComicInfoProviderUntouched(
                &comicInfo,
                provider: .anilist,
                reason: "Saved \(matchedSourceID.provider.displayName) ID \(matchedSourceID.value) did not resolve through AniList.",
                service: service
            )
        }

        let data = try comicInfoSidecarData(
            comicInfo,
            sidecarURL: comicInfoURL,
            service: service,
            mediaDomain: .reading
        )
        return ExactIDProviderWavePreparedWrite(
            oneBasedIndex: oneBasedIndex,
            itemID: item.id,
            provider: .anilist,
            item: item,
            sidecarPath: proposedPath,
            data: data,
            receipt: comicInfoReceipt(action: "Updated", item: item, comicInfo: comicInfo, service: service),
            appliedPath: appliedPlanPath(for: item)
        )
    }

    private func preparedExactIDProviderWaveWrite(
        item: LibraryPlanItem,
        provider: SableLibraryMetadataProvider,
        oneBasedIndex: Int,
        root: URL,
        config: SableLibraryConfig,
        service: SableLibraryService,
        cachedLocalFiles: SidecarLocalFileSnapshot?
    ) async throws -> ExactIDProviderWavePreparedWrite {
        guard let proposedPath = item.proposedPath else {
            throw CocoaError(.fileNoSuchFile)
        }

        let folder = root.appendingPathComponent(item.currentPath, isDirectory: true)
        let comicInfoURL = root.appendingPathComponent(proposedPath)
        let existing = readComicInfo(url: comicInfoURL) ?? [:]
        let localTitle = service.textValue(existing["local_title"])
        let existingPreferredTitle = service.textValue(existing["preferred_title"])
            ?? service.textValue(existing["title"])
        let title = organizerTitle(from: folder.lastPathComponent, service: service)
        let source = service.textValue(existing["source"])?.lowercased()
        let existingTitleQueries = source == "mangabaka" ? [] : [localTitle, existingPreferredTitle].compactMap { $0 }
        let localFiles = cachedLocalFiles
            ?? sidecarLocalFileSnapshot(folder: folder, root: root, config: config, service: service, includeBooks: true)
        let queryPlan = mangaBakaQueryPlan(
            primaryTitle: title,
            extraTitles: existingTitleQueries,
            config: config,
            service: service,
            localFiles: localFiles
        )
        let comicInfo = try await SableLibraryProviderRequestContext.$maximumCacheAge.withValue(30) {
            try await comicInfoPayload(
                item: item,
                queryPlan: queryPlan,
                folder: folder,
                root: root,
                config: config,
                existing: existing,
                service: service,
                localFiles: localFiles
            )
        }
        let data = try comicInfoSidecarData(
            comicInfo,
            sidecarURL: comicInfoURL,
            service: service,
            mediaDomain: .reading
        )
        return ExactIDProviderWavePreparedWrite(
            oneBasedIndex: oneBasedIndex,
            itemID: item.id,
            provider: provider,
            item: item,
            sidecarPath: proposedPath,
            data: data,
            receipt: comicInfoReceipt(action: "Updated", item: item, comicInfo: comicInfo, service: service),
            appliedPath: appliedPlanPath(for: item)
        )
    }

    private func exactIDBatchWorkItem(
        from item: LibraryPlanItem,
        root: URL,
        config: SableLibraryConfig,
        service: SableLibraryService,
        skipped: inout [String]
    ) -> LibraryPlanItem? {
        guard let proposedPath = item.proposedPath else {
            skipped.append("\(item.currentPath): no sidecar path was available.")
            return nil
        }

        let sidecarURL = root.appendingPathComponent(proposedPath)
        guard let existing = readComicInfo(url: sidecarURL) else {
            skipped.append("\(item.currentPath): sidecar could not be read for exact-ID refresh.")
            return nil
        }

        let folderName = URL(fileURLWithPath: item.currentPath).lastPathComponent
        var extraSourceIDs = sourceIDHints(in: folderName)
        appendUniqueSourceIDs(item.manualSourceIDs, to: &extraSourceIDs)
        if let manualMangaBakaID = item.manualMangaBakaID {
            appendUniqueSourceID(SableLibrarySourceID(provider: .mangabaka, value: manualMangaBakaID), to: &extraSourceIDs)
        }
        if let manualRanobeDBID = item.manualRanobeDBID {
            appendUniqueSourceID(SableLibrarySourceID(provider: .ranobedb, value: manualRanobeDBID), to: &extraSourceIDs)
        }

        let sourceIDs = sourceIDs(from: existing, extraIDs: extraSourceIDs, service: service)
        let providers = exactIDBatchProviders(for: item.operation, sourceIDs: sourceIDs, config: config)
        let rowScopedProviders = exactIDProviders(providers, scopedTo: item)
        guard !rowScopedProviders.isEmpty else {
            skipped.append("\(item.currentPath): no enabled saved provider ID was found.")
            return nil
        }

        var batchItem = item
        batchItem.usedNetworkData = true
        batchItem.metadataProviders = rowScopedProviders
        batchItem.manualSourceIDs = sourceIDs
        batchItem.reviewTags = uniqueStrings(batchItem.reviewTags + [exactIDBatchRefreshTag, exactIDRefreshEvidenceTag])
        batchItem.confidenceExplanation = "Exact-ID batch refresh. Sable updates provider data only from saved IDs and does not fall back to title search."
        if batchItem.operation == .refreshComicInfo {
            batchItem.manualMangaBakaID = sourceIDs.first(where: { $0.provider == .mangabaka })?.value
            batchItem.manualRanobeDBID = sourceIDs.first(where: { $0.provider == .ranobedb })?.value
        }
        return batchItem
    }

    private func exactIDProviderWaveWorkItem(
        from item: LibraryPlanItem,
        provider: SableLibraryMetadataProvider,
        root: URL,
        config: SableLibraryConfig,
        service: SableLibraryService
    ) -> LibraryPlanItem? {
        guard item.operation == .refreshComicInfo,
              let proposedPath = item.proposedPath else {
            return nil
        }

        let sidecarURL = root.appendingPathComponent(proposedPath)
        guard let existing = readComicInfo(url: sidecarURL) else {
            return nil
        }

        let folderName = URL(fileURLWithPath: item.currentPath).lastPathComponent
        var extraSourceIDs = sourceIDHints(in: folderName)
        appendUniqueSourceIDs(item.manualSourceIDs, to: &extraSourceIDs)
        if let manualMangaBakaID = item.manualMangaBakaID {
            appendUniqueSourceID(SableLibrarySourceID(provider: .mangabaka, value: manualMangaBakaID), to: &extraSourceIDs)
        }
        if let manualRanobeDBID = item.manualRanobeDBID {
            appendUniqueSourceID(SableLibrarySourceID(provider: .ranobedb, value: manualRanobeDBID), to: &extraSourceIDs)
        }

        let sourceIDs = sourceIDs(from: existing, extraIDs: extraSourceIDs, service: service)
        guard exactIDProviderWaveHasUsableID(provider, sourceIDs: sourceIDs, config: config),
              exactIDProvider(provider, isAllowedBy: item) else {
            return nil
        }

        var waveItem = item
        waveItem.usedNetworkData = true
        waveItem.metadataProviders = [provider]
        waveItem.manualSourceIDs = sourceIDs
        waveItem.reviewTags = uniqueStrings(waveItem.reviewTags + [exactIDBatchRefreshTag, exactIDRefreshEvidenceTag, "metadata-provider-wave"])
        waveItem.confidenceExplanation = "Exact-ID \(provider.displayName) batch refresh. Sable updates this provider from saved IDs and does not fall back to title search."
        waveItem.manualMangaBakaID = sourceIDs.first(where: { $0.provider == .mangabaka })?.value
        waveItem.manualRanobeDBID = sourceIDs.first(where: { $0.provider == .ranobedb })?.value
        return waveItem
    }

    private func exactReadingProviderWaveOrder(config: SableLibraryConfig) -> [SableLibraryMetadataProvider] {
        let enabled = Set(SableLibraryProviderGraphPlanner().readingProviders(config: config))
        return [.mangabaka, .ranobedb, .anilist, .openLibrary, .wikidata].filter { enabled.contains($0) }
    }

    private func exactIDProviderWaveHasUsableID(
        _ provider: SableLibraryMetadataProvider,
        sourceIDs: [SableLibrarySourceID],
        config: SableLibraryConfig
    ) -> Bool {
        let enabled = Set(SableLibraryProviderGraphPlanner().readingProviders(config: config))
        guard enabled.contains(provider) else { return false }

        switch provider {
        case .anilist:
            return sourceIDs.contains { $0.provider == .anilist || $0.provider == .myAnimeList }
        case .mangabaka, .ranobedb, .openLibrary, .wikidata:
            return sourceIDs.contains { $0.provider == provider }
        case .myAnimeList, .tvmaze, .tmdb, .tvdb, .imdb, .local:
            return false
        }
    }

    private func aniListExactLookupSourceID(for item: LibraryPlanItem) -> SableLibrarySourceID? {
        item.manualSourceIDs.first { $0.provider == .anilist }
            ?? item.manualSourceIDs.first { $0.provider == .myAnimeList }
    }

    private func exactIDProviderWaveQueueMessage(
        provider: SableLibraryMetadataProvider,
        items: [LibraryPlanItem]
    ) -> String {
        let count = sidecarCountText(items.count)
        if exactIDProviderWaveIsRanobeDBBookDetail(provider: provider, items: items) {
            return "RanobeDB new-release check: \(count)."
        }
        if provider == .ranobedb {
            return "RanobeDB series batch: \(count)."
        }
        if provider == .anilist {
            return "AniList ID batch: \(count)."
        }
        return "\(provider.displayName) ID batch: \(count)."
    }

    private func exactIDProviderWaveTitle(
        provider: SableLibraryMetadataProvider,
        items: [LibraryPlanItem]
    ) -> String {
        if exactIDProviderWaveIsRanobeDBBookDetail(provider: provider, items: items) {
            return "RanobeDB new releases"
        }
        if provider == .ranobedb {
            return "RanobeDB series refresh"
        }
        if provider == .anilist {
            return "AniList ID refresh"
        }
        return "\(provider.displayName) refresh"
    }

    private func exactIDProviderWaveWriteTitle(
        provider: SableLibraryMetadataProvider,
        items: [LibraryPlanItem]
    ) -> String {
        if exactIDProviderWaveIsRanobeDBBookDetail(provider: provider, items: items) {
            return "RanobeDB metadata writes"
        }
        if provider == .ranobedb {
            return "RanobeDB series writes"
        }
        if provider == .anilist {
            return "AniList ID writes"
        }
        return "\(provider.displayName) writes"
    }

    private func exactIDProviderWaveFetchMessage(
        provider: SableLibraryMetadataProvider,
        items: [LibraryPlanItem]
    ) -> String {
        let sidecars = sidecarCountText(items.count)
        if exactIDProviderWaveIsRanobeDBBookDetail(provider: provider, items: items) {
            return "Checking current RanobeDB series data and fetching only missing book details for \(sidecars)."
        }
        if provider == .ranobedb {
            return "Fetching RanobeDB series identity for \(sidecars) from saved IDs."
        }
        if provider == .anilist {
            return "Fetching AniList support for \(sidecars) from saved AniList or MAL IDs."
        }
        return "Fetching \(provider.displayName) data for \(sidecars) from saved IDs."
    }

    private func exactIDProviderWaveFetchedMessage(
        provider: SableLibraryMetadataProvider,
        items: [LibraryPlanItem],
        completed: Int,
        total: Int
    ) -> String {
        let unit = exactIDProviderWaveIsRanobeDBBookDetail(provider: provider, items: items)
            ? "RanobeDB release-check result"
            : provider == .ranobedb ? "RanobeDB series result" : "\(provider.displayName) result"
        return "Prepared \(completed) of \(total) \(unit)\(total == 1 ? "" : "s")."
    }

    private func exactIDProviderWaveWriteMessage(
        provider: SableLibraryMetadataProvider,
        completed: Int,
        total: Int
    ) -> String {
        let update = "\(provider.displayName) sidecar update\(total == 1 ? "" : "s")"
        if completed == 0 {
            return "Writing \(total) \(update) together."
        }
        return "Wrote \(completed) of \(total) \(update)."
    }

    private func exactIDProviderWaveIsRanobeDBBookDetail(
        provider: SableLibraryMetadataProvider,
        items: [LibraryPlanItem]
    ) -> Bool {
        provider == .ranobedb && !items.isEmpty && items.allSatisfy(shouldRefreshRanobeDBBookDetails(for:))
    }

    private func sidecarCountText(_ count: Int) -> String {
        "\(count) sidecar\(count == 1 ? "" : "s")"
    }

    private func exactIDBatchParallelism(for provider: SableLibraryMetadataProvider) -> Int {
        switch provider {
        case .mangabaka:
            return SableLibraryAdaptiveWorkBudget.parallelism(minimum: 18, multiplier: 3, cap: 34)
        case .ranobedb:
            return SableLibraryAdaptiveWorkBudget.parallelism(minimum: 16, multiplier: 2, cap: 24)
        case .anilist:
            return SableLibraryAdaptiveWorkBudget.parallelism(minimum: 12, multiplier: 2, cap: 18)
        case .openLibrary, .wikidata:
            return SableLibraryAdaptiveWorkBudget.parallelism(minimum: 10, multiplier: 2, cap: 16)
        case .myAnimeList, .tvmaze, .tmdb, .tvdb, .imdb, .local:
            return exactIDBatchMaxParallelism
        }
    }

    private func exactIDBatchProviders(
        for operation: LibraryPlanOperation,
        sourceIDs: [SableLibrarySourceID],
        config: SableLibraryConfig
    ) -> [SableLibraryMetadataProvider] {
        switch operation {
        case .refreshComicInfo:
            return exactReadingIDBatchProviders(sourceIDs: sourceIDs, config: config)
        case .refreshAnimeInfo:
            return exactWatchingIDBatchProviders(sourceIDs: sourceIDs, config: config)
        case .inspectOnly, .repairEpubPackage, .repairAppleBooksCompatibility, .cleanRawName, .sortIntoFolder, .createComicInfo, .createAnimeInfo, .renameFolder, .renameFile, .duplicateDecision, .skip:
            return []
        }
    }

    private func exactReadingIDBatchProviders(
        sourceIDs: [SableLibrarySourceID],
        config: SableLibraryConfig
    ) -> [SableLibraryMetadataProvider] {
        let enabled = Set(SableLibraryProviderGraphPlanner().readingProviders(config: config))
        var providers: [SableLibraryMetadataProvider] = []
        if sourceIDs.contains(where: { $0.provider == .mangabaka }),
           enabled.contains(.mangabaka) {
            providers.append(.mangabaka)
        }
        if sourceIDs.contains(where: { $0.provider == .ranobedb }),
           enabled.contains(.ranobedb) {
            providers.append(.ranobedb)
        }
        if sourceIDs.contains(where: { $0.provider == .myAnimeList || $0.provider == .anilist }),
           enabled.contains(.anilist) {
            providers.append(.anilist)
        }
        if sourceIDs.contains(where: { $0.provider == .openLibrary }),
           enabled.contains(.openLibrary) {
            providers.append(.openLibrary)
        }
        if sourceIDs.contains(where: { $0.provider == .wikidata }),
           enabled.contains(.wikidata) {
            providers.append(.wikidata)
        }
        return uniqueProviders(providers)
    }

    private func exactIDProviders(
        _ providers: [SableLibraryMetadataProvider],
        scopedTo item: LibraryPlanItem
    ) -> [SableLibraryMetadataProvider] {
        guard !item.metadataProviders.isEmpty else {
            return providers
        }
        return providers.filter { exactIDProvider($0, isAllowedBy: item) }
    }

    private func exactIDProvider(
        _ provider: SableLibraryMetadataProvider,
        isAllowedBy item: LibraryPlanItem
    ) -> Bool {
        guard !item.metadataProviders.isEmpty else {
            return true
        }
        return item.metadataProviders.contains(provider)
    }

    private func exactWatchingIDBatchProviders(
        sourceIDs: [SableLibrarySourceID],
        config: SableLibraryConfig
    ) -> [SableLibraryMetadataProvider] {
        let enabled = Set(SableLibraryProviderGraphPlanner().watchingProviders(config: config))
        var providers: [SableLibraryMetadataProvider] = []
        if sourceIDs.contains(where: { $0.provider == .myAnimeList || $0.provider == .anilist }),
           enabled.contains(.anilist) {
            providers.append(.anilist)
        }
        if sourceIDs.contains(where: { $0.provider == .tvmaze || $0.provider == .imdb || $0.provider == .tvdb }),
           enabled.contains(.tvmaze) {
            providers.append(.tvmaze)
        }
        if sourceIDs.contains(where: { $0.provider == .wikidata || $0.provider == .tmdb || $0.provider == .tvdb || $0.provider == .imdb }),
           enabled.contains(.wikidata) {
            providers.append(.wikidata)
        }
        if sourceIDs.contains(where: { $0.provider == .tmdb }),
           enabled.contains(.tmdb) {
            providers.append(.tmdb)
        }
        if sourceIDs.contains(where: { $0.provider == .tvdb }),
           enabled.contains(.tvdb) {
            providers.append(.tvdb)
        }
        if sourceIDs.contains(where: { $0.provider == .imdb }),
           enabled.contains(.imdb) {
            providers.append(.imdb)
        }
        return uniqueProviders(providers)
    }

    private func writeMetadataReport(
        _ report: String,
        root: URL,
        config: SableLibraryConfig,
        service: SableLibraryService
    ) -> String? {
        do {
            try service.writeReport(report, named: config.reports.metadataReport, root: root, config: config)
            try service.writeReport(report, named: config.reports.runSummaryReport, root: root, config: config)
            return service
                .reportDirectory(root: root, config: config)
                .appendingPathComponent(config.reports.metadataReport)
                .path(percentEncoded: false)
        } catch {
            return nil
        }
    }

    private func sidecarCompleteWorkBatch(
        from items: [LibraryPlanItem],
        options: LibraryPipelineOptions?
    ) -> [LibraryPlanItem] {
        let usesLocalLearning = options?.intelligence.useLocalLearning ?? false
        return items.sorted { lhs, rhs in
            let lhsPriority = sidecarApplyPriority(for: lhs, usesLocalLearning: usesLocalLearning)
            let rhsPriority = sidecarApplyPriority(for: rhs, usesLocalLearning: usesLocalLearning)
            if lhsPriority != rhsPriority {
                return lhsPriority > rhsPriority
            }
            return lhs.currentPath.localizedStandardCompare(rhs.currentPath) == .orderedAscending
        }
    }

    private func sidecarApplyPriority(
        for item: LibraryPlanItem,
        usesLocalLearning: Bool
    ) -> Int {
        var score = 0
        if hasExactOrManualProviderChoice(item) {
            score += 120
        }
        if !sidecarUsesProviderWork(item) {
            score += 90
        }
        switch item.confidence {
        case .high:
            score += 40
        case .medium:
            score += 20
        case .low:
            score -= 20
        case .unknown:
            score -= 30
        }
        if item.requiresReview {
            score -= 35
        }
        if item.reviewTags.contains("provider-route-prose")
            || item.reviewTags.contains("provider-route-light-novel")
            || item.reviewTags.contains("provider-route-manga") {
            score += 25
        }
        if item.reviewTags.contains("provider-ambiguous")
            || item.reviewTags.contains("provider-route-needs-choice")
            || item.reviewTags.contains("needs-provider-choice") {
            score -= 60
        }
        if usesLocalLearning {
            let companyTokens = SableLibraryMLCompany.featureTokens(for: item)
            if companyTokens.contains("trust.providerboundary") {
                score += item.requiresReview ? -10 : 10
            }
            if companyTokens.contains("safety.needschoice") {
                score -= 25
            }
        }
        return score
    }

    private func sidecarUsesProviderWork(_ item: LibraryPlanItem) -> Bool {
        item.usedNetworkData || !item.metadataProviders.isEmpty
    }

    private func isExactIDBatchRefresh(_ item: LibraryPlanItem) -> Bool {
        item.reviewTags.contains(exactIDBatchRefreshTag)
    }

    private func shouldRefreshRanobeDBBookDetails(for item: LibraryPlanItem) -> Bool {
        item.reviewTags.contains(ranobeDBBookDetailRefreshTag)
    }

    private func hasExactOrManualProviderChoice(_ item: LibraryPlanItem) -> Bool {
        if item.manualMangaBakaID != nil || item.manualRanobeDBID != nil || !item.manualSourceIDs.isEmpty {
            return true
        }

        let folderName = URL(fileURLWithPath: item.currentPath).lastPathComponent
        return !sourceIDHints(in: folderName).isEmpty
    }

    private func appliedPlanPath(for item: LibraryPlanItem) -> LibraryAppliedPlanPath {
        LibraryAppliedPlanPath(
            currentPath: item.currentPath,
            proposedPath: item.proposedPath,
            stage: item.stage,
            operation: item.operation
        )
    }

    private func createComicInfo(
        item: LibraryPlanItem,
        root: URL,
        config: SableLibraryConfig,
        service: SableLibraryService
    ) async throws -> String {
        guard let proposedPath = item.proposedPath else { return item.receipt }
        let folder = root.appendingPathComponent(item.currentPath, isDirectory: true)
        let comicInfoURL = root.appendingPathComponent(proposedPath)
        guard !service.fileManager.fileExists(atPath: comicInfoURL.path(percentEncoded: false)) else {
            throw CocoaError(.fileWriteFileExists)
        }

        let title = organizerTitle(from: folder.lastPathComponent, service: service)
        let localFiles = sidecarLocalFileSnapshot(folder: folder, root: root, config: config, service: service, includeBooks: true)
        let queryPlan = mangaBakaQueryPlan(
            primaryTitle: title,
            config: config,
            service: service,
            localFiles: localFiles
        )
        let comicInfo = try await comicInfoPayload(
            item: item,
            queryPlan: queryPlan,
            folder: folder,
            root: root,
            config: config,
            existing: [:],
            service: service,
            localFiles: localFiles
        )
        try write(
            comicInfo: comicInfo,
            to: comicInfoURL,
            service: service,
            mediaDomain: .reading
        )
        recordSidecarTrainingEvent(item: item, domain: .reading, provider: trainingProvider(for: item), root: root, config: config, service: service)
        return comicInfoReceipt(action: "Created", item: item, comicInfo: comicInfo, service: service)
    }

    private func refreshComicInfo(
        item: LibraryPlanItem,
        root: URL,
        config: SableLibraryConfig,
        coverDownloadPass: SableLibraryCoverDownloadPass = .combined,
        service: SableLibraryService
    ) async throws -> String {
        let folder = root.appendingPathComponent(item.currentPath, isDirectory: true)
        if item.reviewTags.contains(coverDownloadReviewTag) {
            let comicInfoURL = folder.appendingPathComponent(config.comicInfoFileName)
            let existing = readComicInfo(url: comicInfoURL) ?? [:]
            return try await downloadSeriesCovers(
                item: item,
                folder: folder,
                root: root,
                config: config,
                existing: existing,
                downloadPass: coverDownloadPass,
                service: service
            )
        }
        guard let proposedPath = item.proposedPath else { return item.receipt }
        let comicInfoURL = root.appendingPathComponent(proposedPath)
        let existing = readComicInfo(url: comicInfoURL) ?? [:]
        if item.reviewTags.contains("metadata-provider-precheck") {
            let precheckedComicInfo = await precheckMissingProviderCandidate(
                item: item,
                existing: existing,
                folder: folder,
                config: config,
                service: service
            )
            try write(
                comicInfo: precheckedComicInfo,
                to: comicInfoURL,
                service: service,
                mediaDomain: .reading
            )
            return comicInfoReceipt(action: "Prechecked", item: item, comicInfo: precheckedComicInfo, service: service)
        }
        if item.reviewTags.contains("metadata-title-cleanup") {
            guard let repairedComicInfo = cleanupComicInfoTitleSidecar(
                existing,
                folder: folder,
                root: root,
                config: config,
                service: service
            ) else {
                return "\(item.currentPath): title already looks clean"
            }
            try write(
                comicInfo: repairedComicInfo,
                to: comicInfoURL,
                service: service,
                mediaDomain: .reading
            )
            return comicInfoReceipt(action: "Cleaned title in", item: item, comicInfo: repairedComicInfo, service: service)
        }
        if item.reviewTags.contains("metadata-comicinfo-cleaner") {
            let cleanedComicInfo = cleanupComicInfoProviderDataSidecar(existing, service: service)
            try write(
                comicInfo: cleanedComicInfo,
                to: comicInfoURL,
                service: service,
                mediaDomain: .reading
            )
            recordSidecarCleanerTrainingEvent(
                item: item,
                sidecar: cleanedComicInfo,
                domain: .reading,
                root: root,
                config: config,
                service: service
            )
            return comicInfoReceipt(action: "Cleaned provider data in", item: item, comicInfo: cleanedComicInfo, service: service)
        }

        let localTitle = service.textValue(existing["local_title"])
        let existingPreferredTitle = service.textValue(existing["preferred_title"])
            ?? service.textValue(existing["title"])
        let title = organizerTitle(from: folder.lastPathComponent, service: service)
        let source = service.textValue(existing["source"])?.lowercased()
        let existingTitleQueries = source == "mangabaka" ? [] : [localTitle, existingPreferredTitle].compactMap { $0 }
        let localFiles = sidecarLocalFileSnapshot(folder: folder, root: root, config: config, service: service, includeBooks: true)
        let queryPlan = mangaBakaQueryPlan(
            primaryTitle: title,
            extraTitles: existingTitleQueries,
            config: config,
            service: service,
            localFiles: localFiles
        )
        let comicInfo = try await comicInfoPayload(
            item: item,
            queryPlan: queryPlan,
            folder: folder,
            root: root,
            config: config,
            existing: existing,
            service: service,
            localFiles: localFiles
        )
        try write(
            comicInfo: comicInfo,
            to: comicInfoURL,
            service: service,
            mediaDomain: .reading
        )
        recordSidecarTrainingEvent(item: item, domain: .reading, provider: trainingProvider(for: item), root: root, config: config, service: service)
        return comicInfoReceipt(action: "Updated", item: item, comicInfo: comicInfo, service: service)
    }

    private func createAnimeInfo(
        item: LibraryPlanItem,
        root: URL,
        config: SableLibraryConfig,
        service: SableLibraryService
    ) async throws -> String {
        guard let proposedPath = item.proposedPath else { return item.receipt }
        let folder = root.appendingPathComponent(item.currentPath, isDirectory: true)
        let animeInfoURL = root.appendingPathComponent(proposedPath)
        guard !service.fileManager.fileExists(atPath: animeInfoURL.path(percentEncoded: false)) else {
            throw CocoaError(.fileWriteFileExists)
        }

        let localFiles = sidecarLocalFileSnapshot(folder: folder, root: root, config: config, service: service, includeVideos: true)
        let animeInfo = try await animeInfoPayload(
            item: item,
            folder: folder,
            root: root,
            config: config,
            existing: [:],
            service: service,
            localFiles: localFiles
        )
        try write(
            comicInfo: animeInfo,
            to: animeInfoURL,
            service: service,
            mediaDomain: .watching
        )
        try writePlexMatchIfNeeded(
            animeInfo: animeInfo,
            folder: animeInfoURL.deletingLastPathComponent(),
            service: service
        )
        recordSidecarTrainingEvent(item: item, domain: .watching, provider: trainingProvider(for: item), root: root, config: config, service: service)
        return animeInfoReceipt(action: "Created", item: item, animeInfo: animeInfo, service: service)
    }

    private func refreshAnimeInfo(
        item: LibraryPlanItem,
        root: URL,
        config: SableLibraryConfig,
        service: SableLibraryService
    ) async throws -> String {
        guard let proposedPath = item.proposedPath else { return item.receipt }
        let folder = root.appendingPathComponent(item.currentPath, isDirectory: true)
        let animeInfoURL = root.appendingPathComponent(proposedPath)
        let existing = readComicInfo(url: animeInfoURL) ?? [:]
        if item.reviewTags.contains("metadata-provider-precheck") {
            let precheckedAnimeInfo = await precheckMissingProviderCandidate(
                item: item,
                existing: existing,
                folder: folder,
                config: config,
                service: service
            )
            try write(
                comicInfo: precheckedAnimeInfo,
                to: animeInfoURL,
                service: service,
                mediaDomain: .watching
            )
            return animeInfoReceipt(action: "Prechecked", item: item, animeInfo: precheckedAnimeInfo, service: service)
        }
        if item.reviewTags.contains("metadata-animeinfo-cleaner") {
            let cleanedAnimeInfo = cleanupWatchingSidecarData(
                existing,
                folder: folder,
                config: config,
                service: service
            )
            try write(
                comicInfo: cleanedAnimeInfo,
                to: animeInfoURL,
                service: service,
                mediaDomain: .watching
            )
            try writePlexMatchIfNeeded(
                animeInfo: cleanedAnimeInfo,
                folder: animeInfoURL.deletingLastPathComponent(),
                service: service
            )
            recordSidecarCleanerTrainingEvent(
                item: item,
                sidecar: cleanedAnimeInfo,
                domain: .watching,
                root: root,
                config: config,
                service: service
            )
            return animeInfoReceipt(action: "Cleaned provider data in", item: item, animeInfo: cleanedAnimeInfo, service: service)
        }
        let localFiles = sidecarLocalFileSnapshot(folder: folder, root: root, config: config, service: service, includeVideos: true)
        let animeInfo = try await animeInfoPayload(
            item: item,
            folder: folder,
            root: root,
            config: config,
            existing: existing,
            service: service,
            localFiles: localFiles
        )
        try write(
            comicInfo: animeInfo,
            to: animeInfoURL,
            service: service,
            mediaDomain: .watching
        )
        try writePlexMatchIfNeeded(
            animeInfo: animeInfo,
            folder: animeInfoURL.deletingLastPathComponent(),
            service: service
        )
        recordSidecarTrainingEvent(item: item, domain: .watching, provider: trainingProvider(for: item), root: root, config: config, service: service)
        return animeInfoReceipt(action: "Updated", item: item, animeInfo: animeInfo, service: service)
    }

    private func downloadSeriesCovers(
        item: LibraryPlanItem,
        folder: URL,
        root: URL,
        config: SableLibraryConfig,
        existing: [String: Any],
        downloadPass: SableLibraryCoverDownloadPass,
        service: SableLibraryService
    ) async throws -> String {
        let localItems = (try? service.bookItems(in: folder, libraryRoot: root, config: config)) ?? []
        let queryTitles = coverDownloadQueryTitles(
            seriesPath: item.currentPath,
            sidecar: existing,
            service: service
        )
        let localBooks = localItems
            .filter { !$0.isDirectory }
            .filter { ["epub", "kepub", "cbz", "cbr", "cb7", "pdf"].contains($0.url.pathExtension.lowercased()) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { item in
                SableLibraryCoverDownloadLocalBook(
                    fileName: item.name,
                    volumeNumber: SableLibraryCoverDownloadPlanner.localVolumeNumber(
                        fileName: item.name,
                        seriesTitles: queryTitles
                    )
                )
            }
        let manualMangaBakaID = item.manualCoverSeriesMatches.first(
            where: { $0.source == .mangaBaka }
        )?.providerID
        let savedMangaBakaBundle = SableLibraryMangaBakaSeriesBundleStore.load(
            from: existing
        )
        let mangaBakaBundle = manualMangaBakaID == nil
            ? savedMangaBakaBundle
            : nil
        let mangaBakaID = manualMangaBakaID
            ?? item.manualMangaBakaID
            ?? item.manualSourceIDs.first(where: { $0.provider == .mangabaka })?.value
            ?? sourceIDs(from: existing, service: service).first(where: { $0.provider == .mangabaka })?.value
            ?? mangaBakaBundle?.seriesIDs.first.map(String.init)
        let seriesTitle = coverDisplayTitle(
            for: item.currentPath,
            sidecar: existing,
            service: service
        )
        let verifiesExistingStoreEvidenceOnly =
            downloadPass == .combined
            && item.reviewTags.contains("cover-manifest-unverified")
        let request = SableLibraryCoverDownloadRequest(
            seriesTitle: seriesTitle,
            mediaType: service.textValue(existing["type"]),
            queryTitles: queryTitles,
            isbn13: [],
            isbn13ByLanguage: coverISBN13ByLanguage(
                in: existing,
                seriesTitle: seriesTitle,
                service: service
            ),
            mangaBakaSeriesID: mangaBakaID,
            mangaBakaSeriesBundle: mangaBakaBundle,
            manualSeriesMatches: item.manualCoverSeriesMatches,
            localBooks: localBooks,
            languages: item.requestedCoverLanguages,
            includeSpecials: !item.reviewTags.contains("cover-manifest-incomplete")
                && !item.reviewTags.contains("cover-manifest-conflict")
                && !item.reviewTags.contains("cover-manifest-needs-store-check")
                && !item.reviewTags.contains("cover-manifest-unproven-no-result"),
            refreshExistingNormalCovers: item.reviewTags.contains("cover-manifest-present")
                || item.reviewTags.contains("cover-manifest-below-clinic-quality")
                || item.reviewTags.contains("cover-manifest-needs-store-check")
                || item.reviewTags.contains("cover-manifest-unproven-no-result"),
            verifyExistingStoreEvidenceOnly: verifiesExistingStoreEvidenceOnly,
            replaceUnprovenNormalCovers: item.reviewTags.contains(
                "cover-manifest-needs-store-check"
            ) || item.reviewTags.contains("cover-manifest-unproven-no-result"),
            downloadPass: downloadPass
        )
        let result = try await coverDownloadService.downloadCovers(
            request: request,
            folder: folder,
            root: root
        )
        let entryCount = result.manifest.entries.count
        let skippedNote = result.skipped.isEmpty
            ? ""
            : " Skipped notes: \(result.skipped.prefix(3).joined(separator: " / "))"
        let reusedNote = result.reusedCount == 0
            ? ""
            : " Reused \(result.reusedCount) trusted existing cover\(result.reusedCount == 1 ? "" : "s")."
        if verifiesExistingStoreEvidenceOnly {
            return "\(item.currentPath): checked store proof for \(entryCount) book"
                + "\(entryCount == 1 ? "" : "s") without replacing cover images."
                + "\(skippedNote)"
        }
        if item.reviewTags.contains("cover-manifest-needs-store-check")
            || item.reviewTags.contains("cover-manifest-unproven-no-result") {
            return "\(item.currentPath): searched for trusted replacements for \(entryCount) book"
                + "\(entryCount == 1 ? "" : "s"). Existing images were kept unless a trusted replacement was accepted."
                + "\(reusedNote)\(skippedNote)"
        }
        let action: String
        switch downloadPass {
        case .mangaBakaBaseline:
            action = "filled MangaBaka baseline gaps with"
        case .storeQualityUpgrade:
            action = "accepted"
        case .combined:
            action = "downloaded"
        }
        let suffix = downloadPass == .storeQualityUpgrade
            ? " higher-quality cover file\(result.downloadedCount == 1 ? "" : "s")"
            : " cover file\(result.downloadedCount == 1 ? "" : "s")"
        return "\(item.currentPath): \(action) \(result.downloadedCount)\(suffix) for \(entryCount) book\(entryCount == 1 ? "" : "s").\(reusedNote)\(skippedNote)"
    }

    private func coverISBN13ByLanguage(
        in sidecar: [String: Any],
        seriesTitle: String,
        service: SableLibraryService
    ) -> [String: [String]] {
        var isbnByLanguage: [String: [String]] = [:]

        let partRows = sidecar["parts"] as? [[String: Any]] ?? []
        for part in partRows {
            guard let partTitle = service.textValue(part["title"]),
                  SableLibraryCoverDownloadPlanner.providerTitle(
                    partTitle,
                    belongsTo: seriesTitle
                  ) else {
                continue
            }
            isbnByLanguage["en", default: []].append(
                contentsOf: arrayStrings(part["isbn13"], service: service)
            )
        }

        let sable = sidecar["_sable"] as? [String: Any]
        let ranobeDB = sable?[SableLibraryMetadataProvider.ranobedb.rawValue] as? [String: Any]
        let api = ranobeDB?["api_compact"] as? [String: Any]
            ?? ranobeDB?["api"] as? [String: Any]
            ?? [:]
        let bookRows = api["book_responses"] as? [[String: Any]] ?? []

        for row in bookRows {
            let response = row["response"] as? [String: Any] ?? row
            let book = response["book"] as? [String: Any] ?? response
            guard let bookTitle = service.textValue(book["title"]),
                  SableLibraryCoverDownloadPlanner.providerTitle(
                    bookTitle,
                    belongsTo: seriesTitle
                  ) else {
                continue
            }
            let releases = book["releases"] as? [[String: Any]] ?? []
            for release in releases {
                guard let rawLanguage = service.textValue(release["lang"]),
                      let isbn = service.textValue(release["isbn13"]) else {
                    continue
                }
                let language = SableLibraryCoverDownloadPlanner.normalizedLanguage(rawLanguage)
                guard language == "jp" || language == "en" else { continue }
                isbnByLanguage[language, default: []].append(isbn)
            }
        }

        return isbnByLanguage.mapValues(SableLibraryCoverDownloadPlanner.normalizedISBNQueries)
    }

    private func coverDownloadQueryTitles(
        series: LibrarySeriesSnapshot,
        sidecar: [String: Any],
        service: SableLibraryService
    ) -> [String] {
        coverDownloadQueryTitles(
            seriesPath: series.path,
            sidecar: sidecar,
            service: service,
            extraTitles: [
                series.preferredTitle,
                series.localTitle,
                series.displayName
            ].compactMap { $0 }
        )
    }

    private func coverDownloadQueryTitles(
        seriesPath: String,
        sidecar: [String: Any],
        service: SableLibraryService,
        extraTitles: [String] = []
    ) -> [String] {
        var titles = extraTitles
        let directTitleKeys = [
            "preferred_title",
            "title",
            "local_title",
            "sort_title",
            "native_title",
            "romanized_title",
            "romaji_title",
            "english_title",
            "japanese_title",
            "original_title",
            "title_orig"
        ]
        titles.append(contentsOf: directTitleKeys.compactMap { service.textValue(sidecar[$0]) })
        titles.append(contentsOf: sidecarStringArray(sidecar["aliases"], service: service))
        titles.append(contentsOf: sidecarStringArray(sidecar["alternative_titles"], service: service))
        titles.append(contentsOf: sidecarTitleRows(sidecar["titles"], service: service))

        if let sable = sidecar["_sable"] as? [String: Any] {
            if let mangaBaka = sable["mangabaka"] as? [String: Any] {
                titles.append(contentsOf: sidecarTitleRows(mangaBaka["titles_v2"], service: service))
                titles.append(contentsOf: directTitleKeys.compactMap { service.textValue(mangaBaka[$0]) })
            }
            if let ranobeDB = sable["ranobedb"] as? [String: Any] {
                titles.append(contentsOf: directTitleKeys.compactMap { service.textValue(ranobeDB[$0]) })
                let api = ranobeDB["api_compact"] as? [String: Any]
                    ?? ranobeDB["api"] as? [String: Any]
                if let series = api?["series"] as? [String: Any] {
                    titles.append(contentsOf: directTitleKeys.compactMap { service.textValue(series[$0]) })
                    titles.append(contentsOf: sidecarTitleRows(series["titles"], service: service))
                }
            }
        }

        titles.append(organizerTitle(from: URL(fileURLWithPath: seriesPath).lastPathComponent, service: service))
        return SableLibraryCoverDownloadPlanner.uniqueNonEmpty(titles)
    }

    private func sidecarStringArray(_ value: Any?, service: SableLibraryService) -> [String] {
        if let strings = value as? [String] {
            return strings
        }
        if let rows = value as? [Any] {
            return rows.compactMap { service.textValue($0) }
        }
        return service.textValue(value).map { [$0] } ?? []
    }

    private func sidecarTitleRows(_ value: Any?, service: SableLibraryService) -> [String] {
        guard let rows = value as? [[String: Any]] else {
            return sidecarStringArray(value, service: service)
        }
        let titleKeys = [
            "title",
            "name",
            "label",
            "value",
            "native",
            "native_title",
            "english",
            "romaji",
            "romanized",
            "title_orig"
        ]
        return rows.flatMap { row in
            titleKeys.compactMap { service.textValue(row[$0]) }
        }
    }

    private func coverDisplayTitle(
        for seriesPath: String,
        sidecar: [String: Any],
        service: SableLibraryService
    ) -> String {
        service.textValue(sidecar["preferred_title"])
            ?? service.textValue(sidecar["title"])
            ?? organizerTitle(from: URL(fileURLWithPath: seriesPath).lastPathComponent, service: service)
    }

    private func comicInfoPayload(
        item: LibraryPlanItem,
        queryPlan: MangaBakaQueryPlan,
        folder: URL,
        root: URL,
        config: SableLibraryConfig,
        existing: [String: Any],
        service: SableLibraryService,
        localFiles: SidecarLocalFileSnapshot
    ) async throws -> [String: Any] {
        var comicInfo: [String: Any]

        var manualSourceIDs = sourceIDHints(in: folder.lastPathComponent)
        appendUniqueSourceIDs(item.manualSourceIDs, to: &manualSourceIDs)
        if let manualMangaBakaID = item.manualMangaBakaID {
            appendUniqueSourceID(SableLibrarySourceID(provider: .mangabaka, value: manualMangaBakaID), to: &manualSourceIDs)
        }
        if let manualRanobeDBID = item.manualRanobeDBID,
           !manualSourceIDs.contains(where: { $0.provider == .ranobedb && $0.value == manualRanobeDBID }) {
            appendUniqueSourceID(SableLibrarySourceID(provider: .ranobedb, value: manualRanobeDBID), to: &manualSourceIDs)
        }
        let manualProviders = Set(manualSourceIDs.map(\.provider))
        let persistedConfirmedSourceIDs = confirmedProviderSourceIDs(
            in: existing,
            service: service
        ).filter { !manualProviders.contains($0.provider) }
        let confirmedSourceIDs = uniqueSourceIDs(persistedConfirmedSourceIDs + manualSourceIDs)
        let authoritativeSourceIDs = item.reviewTags.contains("manual-provider-match")
            ? confirmedSourceIDs
            : persistedConfirmedSourceIDs

        let explicitManualMangaBakaID = item.manualMangaBakaID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let knownSourceIDs = sourceIDs(from: existing, extraIDs: confirmedSourceIDs, service: service)
        let knownMangaBakaID = explicitManualMangaBakaID
            ?? knownSourceIDs.first(where: { $0.provider == .mangabaka })?.value
        let hasKnownRanobeDBID = knownSourceIDs.contains(where: { $0.provider == .ranobedb })
        let localHints = localBookMetadataHints(in: localFiles.bookItems, service: service)
        let providerSeed = hydratedReadingMetadataProviders(
            for: item,
            existing: existing,
            knownSourceIDs: knownSourceIDs,
            config: config,
            service: service
        )
        let allowsProviderTitleSearch = !isExactIDBatchRefresh(item)
        let activeProviders = effectiveReadingMetadataProviders(
            for: item,
            providerSeed: providerSeed,
            queryPlan: queryPlan,
            knownSourceIDs: knownSourceIDs,
            knownMangaBakaID: knownMangaBakaID,
            localFiles: localFiles,
            localHints: localHints,
            service: service
        )
        let hasRanobeDBFallback =
            hasKnownRanobeDBID
            || activeProviders.contains(.ranobedb)
            || activeProviders.contains(.openLibrary)
        let shouldUseMangaBaka = shouldUseMangaBakaPrimaryIdentity(
            activeProviders: activeProviders,
            queryPlan: queryPlan,
            explicitManualMangaBakaID: explicitManualMangaBakaID,
            service: service
        )

        var mangaBakaFailureReason: String?

        if shouldUseMangaBaka {
            do {
                let match: MangaBakaMatchAssessment
                if let mangaBakaID = knownMangaBakaID {
                    match = try await mangaBakaMatch(
                        forManualID: mangaBakaID,
                        queryPlan: queryPlan,
                        config: config,
                        service: service
                    )
                } else {
                    match = try await mangaBakaMatch(
                        for: queryPlan,
                        config: config,
                        service: service
                    )
                }

                if explicitManualMangaBakaID == nil,
                   mangaBakaMatchNeedsManualReadingConfirmation(match: match, queryPlan: queryPlan, service: service) {
                    throw MangaBakaLookupError.ambiguousMatch(
                        queryPlan.titles.first ?? match.matchedTitle,
                        max(match.broadTitlePeerCount, match.plausiblePeerCount, 1)
                    )
                }

                comicInfo = mangaBakaComicInfo(
                    match: match,
                    localTitle: localTitleForComicInfo(match: match, existing: existing, folder: folder, service: service),
                    folder: folder,
                    root: root,
                    config: config,
                    existing: existing,
                    service: service,
                    localFiles: localFiles
                )
            } catch {
                mangaBakaFailureReason = error.localizedDescription

                guard hasRanobeDBFallback else {
                    throw error
                }

                let title = queryPlan.titles.first ?? organizerTitle(from: folder.lastPathComponent, service: service)
                comicInfo = localComicInfo(
                    title: title,
                    mediaTypeHint: queryPlan.localMediaTypeHint ?? (queryPlan.usesPreferredTypeFallback ? nil : queryPlan.mediaTypeHint),
                    source: service.textValue(existing["source"]) ?? (hasKnownRanobeDBID ? "ranobedb" : "local"),
                    folder: folder,
                    root: root,
                    config: config,
                    existing: existing,
                    service: service,
                    localFiles: localFiles
                )
            }
        } else {
            let title = queryPlan.titles.first ?? organizerTitle(from: folder.lastPathComponent, service: service)
            comicInfo = localComicInfo(
                title: title,
                mediaTypeHint: queryPlan.localMediaTypeHint ?? (queryPlan.usesPreferredTypeFallback ? nil : queryPlan.mediaTypeHint),
                source: service.textValue(existing["source"]) ?? (hasKnownRanobeDBID ? "ranobedb" : "local"),
                folder: folder,
                root: root,
                config: config,
                existing: existing,
                service: service,
                localFiles: localFiles
            )
        }

        repairRiskyMangaBakaNovelTitleIfNeeded(
            &comicInfo,
            queryPlan: queryPlan,
            folder: folder,
            service: service
        )
        mergeSourceIDs(confirmedSourceIDs, into: &comicInfo, service: service)

        if let mangaBakaFailureReason,
           shouldUseMangaBaka {
            markComicInfoProviderUntouched(
                &comicInfo,
                provider: .mangabaka,
                reason: "MangaBaka did not produce a confident match first; fallback continued with RanobeDB/local metadata. \(mangaBakaFailureReason)",
                service: service
            )
        } else if providerSeed.contains(.mangabaka), !activeProviders.contains(.mangabaka) {
            markComicInfoProviderUntouched(
                &comicInfo,
                provider: .mangabaka,
                reason: providerRouteSkipReason(
                    provider: .mangabaka,
                    activeProviders: activeProviders,
                    queryPlan: queryPlan,
                    localHints: localHints,
                    item: item,
                    service: service
                ),
                service: service
            )
        }
        markSkippedReadingProviders(
            providerSeed,
            activeProviders: activeProviders,
            in: &comicInfo,
            queryPlan: queryPlan,
            localHints: localHints,
            item: item,
            service: service
        )

        if hasReadingSupplementalProviders(activeProviders) {
            await enrichComicInfoFromReadingMetadataProviders(
                &comicInfo,
                providers: activeProviders,
                folder: folder,
                root: root,
                config: config,
                service: service,
                localFiles: localFiles,
                localHints: localHints,
                allowTitleSearch: allowsProviderTitleSearch,
                includeRanobeDBBookDetails: shouldRefreshRanobeDBBookDetails(for: item),
                authoritativeSourceIDs: authoritativeSourceIDs
            )
        }
        rememberMissingProviderGapResultsIfNeeded(
            item: item,
            in: &comicInfo,
            service: service
        )
        if item.reviewTags.contains("manual-provider-match") {
            rememberConfirmedProviderSourceIDs(
                manualSourceIDs,
                in: &comicInfo,
                service: service
            )
        }

        if item.operation == .createComicInfo,
           item.usedNetworkData,
           hasTrustedReadingMetadataProvider(activeProviders),
           !allowsProviderlessProseComicInfoCreate(
                item: item,
                activeProviders: activeProviders,
                queryPlan: queryPlan,
                comicInfo: comicInfo,
                service: service
           ),
           !hasTrustedReadingProviderIdentity(comicInfo, service: service) {
            throw ComicInfoProviderCreateError.noConfidentProviderIdentity(
                queryPlan.titles.first ?? organizerTitle(from: folder.lastPathComponent, service: service)
            )
        }

        return comicInfo
    }

    private func precheckMissingProviderCandidate(
        item: LibraryPlanItem,
        existing: [String: Any],
        folder: URL,
        config: SableLibraryConfig,
        service: SableLibraryService
    ) async -> [String: Any] {
        var comicInfo = existing
        guard let provider = item.metadataProviders.first(where: { $0 != .local }) else {
            return comicInfo
        }

        let query = providerGapPrecheckQuery(item: item, existing: existing, folder: folder, service: service)
        let candidates = await metadataLookupService.manualSearchCandidates(
            provider: provider,
            query: query,
            preferredAniListMediaTypes: providerGapAniListMediaTypes(provider: provider, item: item),
            config: config,
            service: service
        )
        let best = bestProviderGapCandidate(
            provider: provider,
            query: query,
            existing: existing,
            candidates: candidates,
            service: service
        )
        rememberProviderCandidatePrecheck(
            provider: provider,
            query: query,
            best: best,
            in: &comicInfo,
            service: service
        )
        return comicInfo
    }

    private func providerGapPrecheckQuery(
        item: LibraryPlanItem,
        existing: [String: Any],
        folder: URL,
        service: SableLibraryService
    ) -> String {
        [
            service.textValue(existing["preferred_title"]),
            service.textValue(existing["title"]),
            service.textValue(existing["local_title"]),
            organizerTitle(from: folder.lastPathComponent, service: service),
            URL(fileURLWithPath: item.currentPath).lastPathComponent
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { !$0.isEmpty } ?? folder.lastPathComponent
    }

    private func bestProviderGapCandidate(
        provider: SableLibraryMetadataProvider,
        query: String,
        existing: [String: Any],
        candidates: [SableLibraryProviderCandidate],
        service: SableLibraryService
    ) -> (candidate: SableLibraryProviderCandidate, sourceID: SableLibrarySourceID, score: Double)? {
        let scored = candidates
            .compactMap { candidate -> (candidate: SableLibraryProviderCandidate, sourceID: SableLibrarySourceID, score: Double)? in
                guard let sourceID = preferredProviderGapSourceID(candidate, provider: provider) else { return nil }
                let score = providerGapCandidateScore(
                    candidate,
                    provider: provider,
                    query: query,
                    existing: existing,
                    service: service
                )
                return (candidate, sourceID, score)
            }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.candidate.title < rhs.candidate.title
                }
                return lhs.score > rhs.score
            }

        guard var best = scored.first else { return nil }
        let highConfidencePeerCount = scored.filter { $0.score >= 0.90 }.count
        if highConfidencePeerCount >= 5 {
            best.score = min(best.score, 0.89)
        }
        return best
    }

    private func providerGapAniListMediaTypes(
        provider: SableLibraryMetadataProvider,
        item: LibraryPlanItem
    ) -> [String] {
        guard provider == .anilist else { return [] }
        return providerGapReadingCatalogMediaTypes(item: item)
    }

    private func providerGapReadingCatalogMediaTypes(item: LibraryPlanItem) -> [String] {
        switch item.operation {
        case .createComicInfo, .refreshComicInfo:
            switch expectedReadingCatalogLane(mediaType: nil, path: item.currentPath) {
            case .lightNovel:
                return ["MANGA"]
            case .manga:
                return ["MANGA"]
            case nil:
                return ["MANGA"]
            }
        case .createAnimeInfo, .refreshAnimeInfo:
            return ["ANIME"]
        case .inspectOnly, .cleanRawName, .sortIntoFolder, .renameFolder, .renameFile, .repairEpubPackage, .repairAppleBooksCompatibility, .duplicateDecision, .skip:
            return []
        }
    }

    private func preferredProviderGapSourceID(
        _ candidate: SableLibraryProviderCandidate,
        provider: SableLibraryMetadataProvider
    ) -> SableLibrarySourceID? {
        if let exact = candidate.sourceIDs.first(where: { $0.provider == provider }) {
            return exact
        }
        if provider == .anilist,
           let aniList = candidate.sourceIDs.first(where: { $0.provider == .anilist }) {
            return aniList
        }
        return candidate.sourceIDs.first
    }

    private func providerGapCandidateScore(
        _ candidate: SableLibraryProviderCandidate,
        provider: SableLibraryMetadataProvider,
        query: String,
        existing: [String: Any],
        service: SableLibraryService
    ) -> Double {
        let queryKey = normalizedProviderCandidateText(query)
        let titleKeys = ([candidate.title] + candidate.aliases)
            .map(normalizedProviderCandidateText)
            .filter { !$0.isEmpty }
        guard !queryKey.isEmpty, !titleKeys.isEmpty else { return 0.18 }

        let bestTitleScore = titleKeys.map { titleKey in
            if titleKey == queryKey { return 0.96 }
            if titleKey.contains(queryKey) || queryKey.contains(titleKey) { return 0.84 }
            return providerCandidateTokenSimilarity(queryKey, titleKey)
        }.max() ?? 0

        var score: Double
        if bestTitleScore >= 0.92 {
            score = bestTitleScore
        } else {
            score = bestTitleScore <= 0.05 ? 0.08 : max(0.18, bestTitleScore * 0.86)
        }
        if let candidateYear = candidate.year,
           let localYear = integerValue(existing["year"]) ?? providerCandidateYearHint(in: query),
           candidateYear == localYear {
            score += 0.05
        }
        if candidate.sourceIDs.contains(where: { $0.provider == provider }) {
            score += 0.03
        }
        if provider == .openLibrary,
           candidate.languages.contains(where: providerCandidateIsEnglishLanguage) {
            score += 0.03
        }
        if provider == .ranobedb,
           candidate.mediaType?.localizedCaseInsensitiveContains("light") == true {
            score += 0.04
        }
        if provider == .anilist {
            let existingType = service.textValue(existing["type"])
            if readingCatalogCandidateMatchesExpectedLane(candidate, existingType: existingType) {
                score += 0.06
            } else if readingCatalogCandidateIsReadingSide(candidate, existingType: existingType) {
                score = min(score, 0.82)
            } else if existingType.map({ readingCatalogShouldPreferReadingSide($0) }) == true {
                score = min(score, 0.62)
            }
        }

        return max(0.01, min(0.99, score))
    }

    private func readingCatalogCandidateMatchesExpectedLane(
        _ candidate: SableLibraryProviderCandidate,
        existingType: String?
    ) -> Bool {
        guard let mediaType = candidate.mediaType else { return false }
        let lane = expectedReadingCatalogLane(mediaType: existingType, path: nil)
        switch lane {
        case .lightNovel:
            return ["novel", "light_novel"].contains(normalizedReadingCatalogMediaType(mediaType))
        case .manga:
            return ["manga", "one_shot"].contains(normalizedReadingCatalogMediaType(mediaType))
        case nil:
            return readingCatalogCandidateIsReadingSide(candidate, existingType: existingType)
        }
    }

    private func readingCatalogCandidateIsReadingSide(
        _ candidate: SableLibraryProviderCandidate,
        existingType: String?
    ) -> Bool {
        guard existingType.map({ readingCatalogShouldPreferReadingSide($0) }) == true else { return false }
        let normalized = candidate.mediaType?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "_")
            .lowercased() ?? ""
        return [
            "manga",
            "novel",
            "one_shot",
            "one shot",
            "light_novel"
        ].contains(normalized)
    }

    private func expectedReadingCatalogLane(for series: LibrarySeriesSnapshot) -> ReadingCatalogLane? {
        expectedReadingCatalogLane(mediaType: series.mediaType, path: series.path)
    }

    private func expectedReadingCatalogLane(mediaType: String?, path: String?) -> ReadingCatalogLane? {
        let normalizedType = mediaType.map { SableLibraryNamingPolicy().normalizedMediaType($0) }
        if normalizedType.map({ ["Manga", "Manhwa", "Manhua", "OEL"].contains($0) }) == true {
            return .manga
        }
        if normalizedType == "Novel" {
            return .lightNovel
        }

        let pathTop = path?
            .split(separator: "/")
            .first
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        if pathTop == "light novels" || pathTop == "light novel" {
            return .lightNovel
        }
        if pathTop.map({ ["manga", "manhwa", "manhua", "oel", "comics", "comic books", "graphic novels"].contains($0) }) == true {
            return .manga
        }
        return nil
    }

    private func normalizedReadingCatalogMediaType(_ mediaType: String) -> String {
        mediaType
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "_")
            .lowercased()
    }

    private func readingCatalogShouldPreferReadingSide(_ mediaType: String) -> Bool {
        switch SableLibraryNamingPolicy().normalizedMediaType(mediaType) {
        case "Manga", "Manhwa", "Manhua", "Comic", "Novel":
            return true
        default:
            return false
        }
    }

    private func normalizedProviderCandidateText(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\b(?:vol|volume|book|novel|light novel|edition)\b"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func providerCandidateTokenSimilarity(_ lhs: String, _ rhs: String) -> Double {
        let left = Set(lhs.split(separator: " ").map(String.init).filter { $0.count > 1 })
        let right = Set(rhs.split(separator: " ").map(String.init).filter { $0.count > 1 })
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        let intersection = left.intersection(right).count
        return Double(intersection * 2) / Double(left.count + right.count)
    }

    private func providerCandidateYearHint(in value: String) -> Int? {
        guard let range = value.range(of: #"(?:19|20)\d{2}"#, options: .regularExpression),
              let year = Int(value[range]) else {
            return nil
        }
        return year
    }

    private func providerCandidateIsEnglishLanguage(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "en" || normalized == "eng" || normalized == "english"
    }

    private func rememberProviderCandidatePrecheck(
        provider: SableLibraryMetadataProvider,
        query: String,
        best: (candidate: SableLibraryProviderCandidate, sourceID: SableLibrarySourceID, score: Double)?,
        in comicInfo: inout [String: Any],
        service: SableLibraryService
    ) {
        var sable = comicInfo["_sable"] as? [String: Any] ?? [:]
        var reviews = sable["provider_candidate_review"] as? [String: Any] ?? [:]
        let updatedAt = service.isoTimestamp()
        let untouchedReason: String

        if let best {
            var payload: [String: Any] = [
                "status": "candidate",
                "provider": provider.rawValue,
                "source": "provider_gap_precheck",
                "query": query,
                "confidence_score": best.score,
                "confidence_percent": Int((best.score * 100).rounded()),
                "candidate_id": best.sourceID.value,
                "candidate_title": best.candidate.title,
                "schema_version": providerGapReviewSchemaVersion,
                "updated_at": updatedAt
            ]
            if let year = best.candidate.year {
                payload["candidate_year"] = year
            }
            if let mediaType = best.candidate.mediaType {
                payload["candidate_media_type"] = mediaType
            }
            reviews[provider.rawValue] = payload
            untouchedReason = "\(provider.displayName) precheck found a possible \(Int((best.score * 100).rounded()))% match and is waiting for user confirmation."
        } else {
            reviews[provider.rawValue] = [
                "status": "no_match",
                "provider": provider.rawValue,
                "source": "provider_gap_precheck",
                "query": query,
                "confidence_score": 0,
                "confidence_percent": 0,
                "schema_version": providerGapReviewSchemaVersion,
                "updated_at": updatedAt
            ]
            untouchedReason = "\(provider.displayName) precheck found no usable candidate. Awaiting No ID confirmation or manual search."
        }

        sable["provider_candidate_review"] = reviews
        comicInfo["_sable"] = sable
        markComicInfoProviderUntouched(
            &comicInfo,
            provider: provider,
            reason: untouchedReason,
            service: service
        )
    }

    private func effectiveReadingMetadataProviders(
        for item: LibraryPlanItem,
        providerSeed: [SableLibraryMetadataProvider],
        queryPlan: MangaBakaQueryPlan,
        knownSourceIDs: [SableLibrarySourceID],
        knownMangaBakaID: String?,
        localFiles: SidecarLocalFileSnapshot,
        localHints: SidecarBookMetadataHints,
        service: SableLibraryService
    ) -> [SableLibraryMetadataProvider] {
        let providers = uniqueProviders(providerSeed)
        guard !providers.isEmpty else { return [] }

        let knownProviders = Set(knownSourceIDs.map(\.provider))
        let normalizedHints = normalizedReadingHints(queryPlan: queryPlan, service: service)
        let looksComicLike = normalizedHints.contains { ["Manga", "Manhwa", "Manhua", "OEL"].contains($0) }
        let hasComicArchives = localFiles.bookItems.contains { item in
            ["cbz", "cbr", "cb7"].contains(item.url.pathExtension.lowercased())
        }
        let canAskReadingCatalogsForSupport = providers.contains(.ranobedb)
            || knownProviders.contains(.myAnimeList)
            || knownProviders.contains(.anilist)
            || looksComicLike
            || hasComicArchives
        func hasExactBookCatalogID(_ provider: SableLibraryMetadataProvider) -> Bool {
            knownProviders.contains(provider)
        }

        if (knownProviders.contains(.openLibrary) || knownProviders.contains(.wikidata)),
           knownMangaBakaID == nil,
           !knownProviders.contains(.ranobedb) {
            return providers.filter { $0 == .openLibrary || $0 == .wikidata }
        }

        if shouldPreferOpenLibraryForProse(
            item: item,
            availableProviders: providers,
            queryPlan: queryPlan,
            knownMangaBakaID: knownMangaBakaID,
            localHints: localHints,
            service: service
        ) {
            return providers.filter { $0 == .openLibrary || $0 == .wikidata }
        }

        if normalizedHints.contains("Book"),
           providers.contains(where: { $0 == .openLibrary || $0 == .wikidata }),
           knownMangaBakaID == nil,
           !knownProviders.contains(.ranobedb) {
            return providers.filter { $0 == .openLibrary || $0 == .wikidata }
        }

        if normalizedHints.contains("Novel"),
           providers.contains(.ranobedb) {
            return providers.filter { provider in
                provider == .mangabaka
                    || provider == .ranobedb
                    || (provider == .openLibrary && hasExactBookCatalogID(.openLibrary))
                    || (provider == .anilist && canAskReadingCatalogsForSupport)
            }
        }

        if looksComicLike || hasComicArchives {
            if providers.contains(.mangabaka) {
                return providers.filter { provider in
                    provider == .mangabaka
                        || (provider == .openLibrary && hasExactBookCatalogID(.openLibrary))
                        || provider == .anilist
                }
            }
        }

        return providers
    }

    private func hydratedReadingMetadataProviders(
        for item: LibraryPlanItem,
        existing: [String: Any],
        knownSourceIDs: [SableLibrarySourceID],
        config: SableLibraryConfig,
        service: SableLibraryService
    ) -> [SableLibraryMetadataProvider] {
        var providers = uniqueProviders(item.metadataProviders)
        let unavailableProviders = unavailableMetadataProviders(in: existing, service: service)
        providers.removeAll { unavailableProviders.contains($0) }
        if isExactIDBatchRefresh(item) {
            return providers
        }
        guard item.usedNetworkData || !providers.isEmpty else { return providers }

        let enabled = SableLibraryProviderGraphPlanner().readingProviders(config: config)
        func appendIfEnabled(_ provider: SableLibraryMetadataProvider) {
            guard enabled.contains(provider),
                  !providers.contains(provider),
                  !unavailableProviders.contains(provider) else {
                return
            }
            providers.append(provider)
        }

        if item.operation == .refreshComicInfo {
            for provider in enabled {
                appendIfEnabled(provider)
            }
        }

        for sourceID in knownSourceIDs {
            appendIfEnabled(sourceID.provider)
            if sourceID.provider == .myAnimeList {
                appendIfEnabled(.anilist)
            }
        }

        if let ids = existing["ids"] as? [String: Any] {
            for key in ids.keys {
                switch key.lowercased() {
                case "mangabaka", "mb":
                    appendIfEnabled(.mangabaka)
                case "ranobedb", "rdb":
                    appendIfEnabled(.ranobedb)
                case "openlibrary", "open_library", "ol":
                    appendIfEnabled(.openLibrary)
                case "wikidata", "wd":
                    appendIfEnabled(.wikidata)
                case "mal", "myanimelist", "my_anime_list":
                    appendIfEnabled(.anilist)
                case "anilist", "al":
                    appendIfEnabled(.anilist)
                default:
                    break
                }
            }
        }

        return uniqueProviders(providers)
    }

    private func unavailableMetadataProviders(
        in sidecar: [String: Any],
        service: SableLibraryService
    ) -> Set<SableLibraryMetadataProvider> {
        guard let sable = sidecar["_sable"] as? [String: Any],
              let availability = sable["provider_availability"] as? [String: Any] else {
            return []
        }

        return Set(availability.compactMap { key, value in
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
        })
    }

    private func normalizedReadingHints(
        queryPlan: MangaBakaQueryPlan,
        service: SableLibraryService
    ) -> Set<String> {
        let namingPolicy = SableLibraryNamingPolicy()
        return Set(
            [queryPlan.mediaTypeHint, queryPlan.localMediaTypeHint]
                .compactMap { $0 }
                .map { namingPolicy.normalizedMediaType($0) }
        )
    }

    private func shouldUseMangaBakaPrimaryIdentity(
        activeProviders: [SableLibraryMetadataProvider],
        queryPlan: MangaBakaQueryPlan,
        explicitManualMangaBakaID: String?,
        service: SableLibraryService
    ) -> Bool {
        guard activeProviders.contains(.mangabaka) else { return false }
        if explicitManualMangaBakaID?.isEmpty == false {
            return true
        }

        if isMangaBakaLightNovelIdentityRisk(queryPlan: queryPlan, service: service) {
            return false
        }

        let hints = normalizedReadingHints(queryPlan: queryPlan, service: service)
        if hints.contains("Novel"), activeProviders.contains(.ranobedb) {
            return false
        }

        return true
    }

    private func isMangaBakaLightNovelIdentityRisk(
        queryPlan: MangaBakaQueryPlan,
        service: SableLibraryService
    ) -> Bool {
        let hints = normalizedReadingHints(queryPlan: queryPlan, service: service)
        let looksTextNovel = hints.contains("Novel") || hints.contains("Book")
        let hasMultiVolumeLocalEvidence = queryPlan.localBookCount > 1
            || (queryPlan.localHighestVolume ?? 0) > 1
        return looksTextNovel && hasMultiVolumeLocalEvidence
    }

    private func mangaBakaCandidateLooksNovel(
        _ candidate: [String: Any],
        service: SableLibraryService
    ) -> Bool {
        guard let type = service.textValue(candidate["type"]) else { return false }
        return SableLibraryNamingPolicy().normalizedMediaType(type) == "Novel"
    }

    private func mangaBakaMatchNeedsManualReadingConfirmation(
        match: MangaBakaMatchAssessment,
        queryPlan: MangaBakaQueryPlan,
        service: SableLibraryService
    ) -> Bool {
        isMangaBakaLightNovelIdentityRisk(queryPlan: queryPlan, service: service)
            && mangaBakaCandidateLooksNovel(match.candidate, service: service)
    }

    private func markSkippedReadingProviders(
        _ originalProviders: [SableLibraryMetadataProvider],
        activeProviders: [SableLibraryMetadataProvider],
        in comicInfo: inout [String: Any],
        queryPlan: MangaBakaQueryPlan,
        localHints: SidecarBookMetadataHints,
        item: LibraryPlanItem,
        service: SableLibraryService
    ) {
        let active = Set(activeProviders)
        for provider in uniqueProviders(originalProviders) where !active.contains(provider) {
            guard provider != .mangabaka else { continue }
            markComicInfoProviderUntouched(
                &comicInfo,
                provider: provider,
                reason: providerRouteSkipReason(
                    provider: provider,
                    activeProviders: activeProviders,
                    queryPlan: queryPlan,
                    localHints: localHints,
                    item: item,
                    service: service
                ),
                service: service
            )
        }
    }

    private func providerRouteSkipReason(
        provider: SableLibraryMetadataProvider,
        activeProviders: [SableLibraryMetadataProvider],
        queryPlan: MangaBakaQueryPlan,
        localHints: SidecarBookMetadataHints,
        item: LibraryPlanItem,
        service: SableLibraryService
    ) -> String {
        let activeText = activeProviders.map(\.displayName).joined(separator: ", ")
        let route = activeText.isEmpty ? "local sidecar creation" : activeText
        let hints = normalizedReadingHints(queryPlan: queryPlan, service: service)

        if hints.contains("Book") || localHints.hasBookProviderClues || shouldPreferOpenLibraryForProse(
            item: item,
            availableProviders: uniqueProviders(activeProviders + item.metadataProviders),
            queryPlan: queryPlan,
            knownMangaBakaID: nil,
            localHints: localHints,
            service: service
        ) {
            return "Skipped \(provider.displayName) because local EPUB evidence looks like ordinary prose; Sidecar Relations routed this row to \(route)."
        }

        if hints.contains("Novel") {
            return "Skipped \(provider.displayName) because local evidence looks light-novel-like; Sidecar Relations routed this row to \(route)."
        }

        if hints.contains(where: { ["Manga", "Manhwa", "Manhua", "OEL"].contains($0) }) {
            return "Skipped \(provider.displayName) because local evidence looks comic/manga-like; Sidecar Relations routed this row to \(route)."
        }

        return "Skipped \(provider.displayName) because Sidecar Relations routed this row to \(route) for a smaller provider pass."
    }

    private func shouldPreferOpenLibraryForProse(
        item: LibraryPlanItem,
        availableProviders: [SableLibraryMetadataProvider]? = nil,
        queryPlan: MangaBakaQueryPlan,
        knownMangaBakaID: String?,
        localHints: SidecarBookMetadataHints,
        service: SableLibraryService
    ) -> Bool {
        let providers = availableProviders ?? item.metadataProviders
        guard providers.contains(where: { $0 == .openLibrary || $0 == .wikidata }),
              knownMangaBakaID == nil else {
            return false
        }

        if isSpecialistReadingLane(item.currentPath) {
            return false
        }

        let namingPolicy = SableLibraryNamingPolicy()
        let normalizedHints = [queryPlan.mediaTypeHint, queryPlan.localMediaTypeHint]
            .compactMap { $0 }
            .map { namingPolicy.normalizedMediaType($0) }

        if normalizedHints.contains(where: { ["Manga", "Manhwa", "Manhua", "OEL", "Novel"].contains($0) }) {
            return false
        }

        if normalizedHints.contains("Book") {
            return true
        }

        return localHints.hasBookProviderClues
    }

    private func isSpecialistReadingLane(_ path: String) -> Bool {
        guard let firstComponent = path.split(separator: "/").first else {
            return false
        }

        let lane = String(firstComponent)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return [
            "manga",
            "manhwa",
            "manhua",
            "oel",
            "light novel",
            "light novels",
            "comics",
            "comic books",
            "graphic novels"
        ].contains(lane)
    }

    private func hasTrustedReadingMetadataProvider(_ providers: [SableLibraryMetadataProvider]) -> Bool {
        providers.contains(.mangabaka)
            || providers.contains(.ranobedb)
            || providers.contains(.openLibrary)
            || providers.contains(.wikidata)
    }

    private func hasTrustedReadingProviderIdentity(
        _ comicInfo: [String: Any],
        service: SableLibraryService
    ) -> Bool {
        sourceIDs(from: comicInfo, service: service).contains { sourceID in
            switch sourceID.provider {
            case .mangabaka, .ranobedb, .openLibrary, .wikidata:
                return true
            case .anilist, .myAnimeList, .tvmaze, .tmdb, .tvdb, .imdb, .local:
                return false
            }
        }
    }

    private func allowsProviderlessProseComicInfoCreate(
        item: LibraryPlanItem,
        activeProviders: [SableLibraryMetadataProvider],
        queryPlan: MangaBakaQueryPlan,
        comicInfo: [String: Any],
        service: SableLibraryService
    ) -> Bool {
        let providers = Set(activeProviders)
        guard !providers.isEmpty,
              providers.isSubset(of: [.openLibrary, .wikidata]) else {
            return false
        }

        let namingPolicy = SableLibraryNamingPolicy()
        let mediaTypes = [
            service.textValue(comicInfo["type"]),
            queryPlan.localMediaTypeHint,
            queryPlan.mediaTypeHint
        ]
        .compactMap { $0 }
        .map { namingPolicy.normalizedMediaType($0) }

        return mediaTypes.contains("Book") || isBooksLane(item.currentPath)
    }

    private func localTitleForComicInfo(
        match: MangaBakaMatchAssessment,
        existing: [String: Any],
        folder: URL,
        service: SableLibraryService
    ) -> String {
        let namingPolicy = SableLibraryNamingPolicy()
        let folderTitle = organizerTitle(from: folder.lastPathComponent, service: service)
        let matchedType = service.textValue(match.candidate["type"]).map { namingPolicy.normalizedMediaType($0) }
        let expectedType = match.expectedMediaType ?? matchedType

        if let expectedType,
           let existingLocalTitle = service.textValue(existing["local_title"]).map(service.cleanSeriesTitle),
           namingPolicy.mediaTypeHint(in: existingLocalTitle) == expectedType {
            return existingLocalTitle
        }

        return folderTitle
    }

    private func localComicInfo(
        title: String,
        mediaTypeHint: String?,
        source: String,
        folder: URL,
        root: URL,
        config: SableLibraryConfig,
        existing: [String: Any],
        service: SableLibraryService,
        localFiles: SidecarLocalFileSnapshot
    ) -> [String: Any] {
        var comicInfo = existing
        let folderName = folder.lastPathComponent
        let folderYear = yearHint(in: folderName)
        let folderSourceID = sourceIDHint(in: folderName)
        let resolvedMediaType = service.textValue(comicInfo["type"])
            ?? mediaTypeHint
            ?? readingTypeHint(folder: folder, root: root)
            ?? "unknown"
        let ids = normalizedIDDictionary(from: comicInfo, extraIDs: sourceIDHints(in: folderName), service: service)
        let localPartTitles = localReadingPartTitles(in: localFiles.bookItems, config: config, service: service)

        let cleanTitle = organizerTitle(from: title, service: service)
        comicInfo["title"] = service.textValue(comicInfo["title"]) ?? cleanTitle
        comicInfo["local_title"] = service.textValue(comicInfo["local_title"]) ?? cleanTitle
        comicInfo["preferred_title"] = service.textValue(comicInfo["preferred_title"]) ?? cleanTitle
        comicInfo["type"] = resolvedMediaType
        if comicInfo["year"] == nil,
           let folderYear {
            comicInfo["year"] = folderYear
        }
        let resolvedYear = integerValue(comicInfo["year"]) ?? folderYear
        comicInfo["last_checked"] = service.isoTimestamp()
        comicInfo["source"] = source
        comicInfo["ids"] = ids
        if !localPartTitles.isEmpty {
            let existingVolumeTitles = combinedStringList(
                from: comicInfo,
                keys: ["volume_titles", "subtitles"],
                service: service
            )
            comicInfo["volume_titles"] = uniqueStrings(existingVolumeTitles + localPartTitles)
        }
        comicInfo["plex"] = readingOrganizerHints(
            title: service.textValue(comicInfo["preferred_title"]) ?? title,
            year: resolvedYear,
            ids: ids,
            mediaType: resolvedMediaType
        )
        var sable = comicInfo["_sable"] as? [String: Any] ?? [:]
        sable["snapshot_version"] = 1
        sable["refreshed_at"] = service.isoTimestamp()
        sable["book_snapshot"] = bookSnapshot(items: localFiles.bookItems, service: service)
        sable["organizer_source"] = organizerSourceSnapshot(
            folderName: folderName,
            cleanTitle: service.textValue(comicInfo["preferred_title"]) ?? cleanTitle,
            year: resolvedYear,
            sourceID: folderSourceID
        )
        comicInfo["_sable"] = sable
        return comicInfo
    }

    private func repairRiskyMangaBakaNovelTitleIfNeeded(
        _ comicInfo: inout [String: Any],
        queryPlan: MangaBakaQueryPlan,
        folder: URL,
        service: SableLibraryService
    ) {
        guard isMangaBakaLightNovelIdentityRisk(queryPlan: queryPlan, service: service),
              let sable = comicInfo["_sable"] as? [String: Any],
              let titleSource = sable["title_source"] as? [String: Any],
              service.textValue(titleSource["provider"]) == SableLibraryMetadataProvider.mangabaka.rawValue else {
            return
        }

        let fallbackTitle = queryPlan.titles.first ?? organizerTitle(from: folder.lastPathComponent, service: service)
        let localTitle = service.textValue(comicInfo["local_title"]) ?? fallbackTitle
        let cleanLocalTitle = service.cleanSeriesTitle(localTitle)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanLocalTitle.isEmpty else { return }

        let currentTitle = service.textValue(comicInfo["preferred_title"])
            ?? service.textValue(comicInfo["title"])
            ?? ""
        guard service.normalizeTerm(currentTitle) != service.normalizeTerm(cleanLocalTitle) else { return }
        if readingProviderTitleHardConflictsWithLocalSeriesMarker(
            localTitle: cleanLocalTitle,
            providerTitle: currentTitle,
            service: service
        ) {
            return
        }

        comicInfo["title"] = cleanLocalTitle
        comicInfo["preferred_title"] = cleanLocalTitle
        rememberReadingTitleSource(
            provider: .local,
            title: cleanLocalTitle,
            in: &comicInfo,
            service: service
        )

        let ids = normalizedIDDictionary(from: comicInfo, service: service)
        let resolvedYear = integerValue(comicInfo["year"]) ?? yearHint(in: folder.lastPathComponent)
        let resolvedType = service.textValue(comicInfo["type"]) ?? queryPlan.localMediaTypeHint ?? queryPlan.mediaTypeHint ?? "unknown"
        comicInfo["plex"] = readingOrganizerHints(
            title: cleanLocalTitle,
            year: resolvedYear,
            ids: ids,
            mediaType: resolvedType
        )
    }

    private func hasReadingSupplementalProviders(_ providers: [SableLibraryMetadataProvider]) -> Bool {
        providers.contains(.ranobedb)
            || providers.contains(.openLibrary)
            || providers.contains(.wikidata)
            || providers.contains(.anilist)
    }

    private func enrichComicInfoFromReadingMetadataProviders(
        _ comicInfo: inout [String: Any],
        providers: [SableLibraryMetadataProvider],
        folder: URL,
        root: URL,
        config: SableLibraryConfig,
        service: SableLibraryService,
        localFiles: SidecarLocalFileSnapshot,
        localHints: SidecarBookMetadataHints,
        allowTitleSearch: Bool,
        includeRanobeDBBookDetails: Bool,
        authoritativeSourceIDs: [SableLibrarySourceID]
    ) async {
        let shouldAskRanobeFirst = providers.contains(.mangabaka)
            && providers.contains(.ranobedb)

        if shouldAskRanobeFirst, providers.contains(.ranobedb) {
            await enrichComicInfoFromRanobeDB(
                &comicInfo,
                folder: folder,
                root: root,
                config: config,
                service: service,
                localFiles: localFiles,
                allowTitleSearch: allowTitleSearch,
                includeBookDetails: includeRanobeDBBookDetails,
                authoritativeSourceIDs: authoritativeSourceIDs
            )
        }

        if !shouldAskRanobeFirst, providers.contains(.ranobedb) {
            await enrichComicInfoFromRanobeDB(
                &comicInfo,
                folder: folder,
                root: root,
                config: config,
                service: service,
                localFiles: localFiles,
                allowTitleSearch: allowTitleSearch,
                includeBookDetails: includeRanobeDBBookDetails,
                authoritativeSourceIDs: authoritativeSourceIDs
            )
        }

        if providers.contains(.anilist) {
            await enrichComicInfoFromReadingCatalogs(
                &comicInfo,
                providers: providers,
                folder: folder,
                root: root,
                config: config,
                service: service,
                localFiles: localFiles,
                allowTitleSearch: allowTitleSearch,
                authoritativeSourceIDs: authoritativeSourceIDs
            )
        }

        if providers.contains(.openLibrary) {
            await enrichComicInfoFromOpenLibrary(
                &comicInfo,
                folder: folder,
                root: root,
                config: config,
                service: service,
                localFiles: localFiles,
                localHints: localHints,
                authoritativeSourceIDs: authoritativeSourceIDs
            )
        }

        if providers.contains(.wikidata) {
            await enrichComicInfoFromWikidata(
                &comicInfo,
                folder: folder,
                root: root,
                config: config,
                service: service,
                localFiles: localFiles,
                localHints: localHints,
                allowTitleSearch: allowTitleSearch,
                authoritativeSourceIDs: authoritativeSourceIDs
            )
        }
    }

    private func enrichComicInfoFromOpenLibrary(
        _ comicInfo: inout [String: Any],
        folder: URL,
        root: URL,
        config: SableLibraryConfig,
        service: SableLibraryService,
        localFiles: SidecarLocalFileSnapshot,
        localHints: SidecarBookMetadataHints,
        authoritativeSourceIDs: [SableLibrarySourceID]
    ) async {
        let title = service.textValue(comicInfo["preferred_title"])
            ?? service.textValue(comicInfo["title"])
            ?? localHints.titles.first
            ?? service.cleanSeriesTitle(folder.lastPathComponent)
        let ids = uniqueSourceIDs(sourceIDs(from: comicInfo, service: service) + localHints.sourceIDs)
        let year = integerValue(comicInfo["year"]) ?? localHints.year
        let isbn13 = uniqueStrings(arrayStrings(comicInfo["isbn13"], service: service) + localHints.isbn13)
        let authors = uniqueStrings(arrayStrings(comicInfo["authors"], service: service) + localHints.authors)
        let publishers = uniqueStrings(arrayStrings(comicInfo["publishers"], service: service) + localHints.publishers)
        let trustedAliases = uniqueStrings(trustedReadingAliases(from: comicInfo, service: service) + localHints.titles)

        if let enrichment = await metadataLookupService.openLibraryEnrichment(
            title: title,
            sourceIDs: ids,
            isbn13: isbn13,
            trustedAliases: trustedAliases,
            authors: authors,
            publishers: publishers,
            year: year,
            allowTitleSearch: false,
            config: config,
            service: service
        ) {
            apply(
                readingEnrichment: enrichment,
                to: &comicInfo,
                folder: folder,
                root: root,
                config: config,
                service: service,
                localFiles: localFiles,
                authoritativeSourceIDs: authoritativeSourceIDs
            )
        } else {
            markComicInfoProviderUntouched(
                &comicInfo,
                provider: .openLibrary,
                reason: "No Open Library book match met the quiet confidence gate.",
                service: service
            )
        }
    }

    private func enrichComicInfoFromWikidata(
        _ comicInfo: inout [String: Any],
        folder: URL,
        root: URL,
        config: SableLibraryConfig,
        service: SableLibraryService,
        localFiles: SidecarLocalFileSnapshot,
        localHints: SidecarBookMetadataHints,
        allowTitleSearch: Bool,
        authoritativeSourceIDs: [SableLibrarySourceID]
    ) async {
        let title = service.textValue(comicInfo["preferred_title"])
            ?? service.textValue(comicInfo["title"])
            ?? localHints.titles.first
            ?? service.cleanSeriesTitle(folder.lastPathComponent)
        let ids = uniqueSourceIDs(sourceIDs(from: comicInfo, service: service) + localHints.sourceIDs)
        let year = integerValue(comicInfo["year"]) ?? localHints.year
        let authors = uniqueStrings(arrayStrings(comicInfo["authors"], service: service) + localHints.authors)
        let trustedAliases = uniqueStrings(trustedReadingAliases(from: comicInfo, service: service) + localHints.titles)

        if let enrichment = await metadataLookupService.wikidataBookEnrichment(
            title: title,
            sourceIDs: ids,
            trustedAliases: trustedAliases,
            authors: authors,
            year: year,
            allowTitleSearch: allowTitleSearch,
            config: config,
            service: service
        ) {
            apply(
                readingEnrichment: enrichment,
                to: &comicInfo,
                folder: folder,
                root: root,
                config: config,
                service: service,
                localFiles: localFiles,
                authoritativeSourceIDs: authoritativeSourceIDs
            )
        } else {
            markComicInfoProviderUntouched(
                &comicInfo,
                provider: .wikidata,
                reason: "No Wikidata prose match met the quiet confidence gate.",
                service: service
            )
        }
    }

    private func enrichComicInfoFromReadingCatalogs(
        _ comicInfo: inout [String: Any],
        providers: [SableLibraryMetadataProvider],
        folder: URL,
        root: URL,
        config: SableLibraryConfig,
        service: SableLibraryService,
        localFiles: SidecarLocalFileSnapshot,
        allowTitleSearch: Bool,
        authoritativeSourceIDs: [SableLibrarySourceID]
    ) async {
        let title = service.textValue(comicInfo["preferred_title"])
            ?? service.textValue(comicInfo["title"])
            ?? service.cleanSeriesTitle(folder.lastPathComponent)
        let ids = sourceIDs(from: comicInfo, service: service)
        let year = integerValue(comicInfo["year"])
        let allowCatalogTitleSearch = allowTitleSearch
            && shouldUseReadingCatalogTitleSearch(comicInfo: comicInfo, service: service)

        if let enrichment = await metadataLookupService.readingCatalogEnrichment(
            title: title,
            sourceIDs: ids,
            trustedAliases: trustedReadingAliases(from: comicInfo, service: service),
            year: year,
            allowTitleSearch: allowCatalogTitleSearch,
            config: config,
            service: service
        ) {
            apply(
                readingEnrichment: enrichment,
                to: &comicInfo,
                folder: folder,
                root: root,
                config: config,
                service: service,
                localFiles: localFiles,
                authoritativeSourceIDs: authoritativeSourceIDs
            )
        } else {
            if providers.contains(.anilist) {
                markComicInfoProviderUntouched(
                    &comicInfo,
                    provider: .anilist,
                    reason: "No AniList reading bridge met the confidence gate.",
                    service: service
                )
            }
        }
    }

    private func trustedReadingAliases(from comicInfo: [String: Any], service: SableLibraryService) -> [String] {
        var values: [String] = []

        for key in [
            "preferred_title",
            "title",
            "native_title",
            "romanized_title",
            "local_title"
        ] {
            if let value = service.textValue(comicInfo[key]) {
                values.append(value)
            }
        }

        for key in ["aliases", "subtitles"] {
            values.append(contentsOf: combinedStringList(from: comicInfo, keys: [key], service: service))
        }

        return uniqueStrings(values)
    }

    private func localBookMetadataHints(
        in items: [LibraryItem],
        service: SableLibraryService
    ) -> SidecarBookMetadataHints {
        var titles: [String] = []
        var authors: [String] = []
        var publishers: [String] = []
        var isbn13: [String] = []
        var sourceIDs: [SableLibrarySourceID] = []
        var years: [Int] = []

        for item in items.prefix(4) {
            guard ["epub", "kepub"].contains(item.url.pathExtension.lowercased()),
                  let archive = try? SableLibraryAppleBooksCompatibilityRepairer.archiveSnapshot(for: item.url),
                  let opfPath = try? SableLibraryAppleBooksCompatibilityRepairer.opfPath(in: archive),
                  let opfText = try? SableLibraryAppleBooksCompatibilityRepairer.entryText(opfPath, in: archive) else {
                continue
            }

            titles.append(contentsOf: epubDublinCoreValues("title", in: opfText))
            authors.append(contentsOf: epubDublinCoreValues("creator", in: opfText))
            publishers.append(contentsOf: epubDublinCoreValues("publisher", in: opfText))
            let identifiers = epubDublinCoreValues("identifier", in: opfText)
            isbn13.append(contentsOf: identifiers.compactMap(epubISBN13))
            sourceIDs.append(contentsOf: identifiers.compactMap(epubSourceID))
            years.append(contentsOf: epubDublinCoreValues("date", in: opfText).compactMap(epubYear))
        }

        return SidecarBookMetadataHints(
            titles: uniqueStrings(titles),
            authors: uniqueStrings(authors),
            publishers: uniqueStrings(publishers),
            isbn13: uniqueStrings(isbn13),
            sourceIDs: uniqueSourceIDs(sourceIDs),
            year: years.first
        )
    }

    private func epubDublinCoreValues(_ localName: String, in opfText: String) -> [String] {
        let name = NSRegularExpression.escapedPattern(for: localName)
        let pattern = #"<(?:[A-Za-z0-9_]+:)?"# + name + #"\b[^>]*>([\s\S]*?)</(?:[A-Za-z0-9_]+:)?"# + name + #">"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        return regex.matches(in: opfText, range: NSRange(opfText.startIndex..<opfText.endIndex, in: opfText)).compactMap { match in
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: opfText) else {
                return nil
            }
            let raw = opfText[range].replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            let decoded = xmlDecodedMetadataText(String(raw))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return decoded.isEmpty ? nil : decoded
        }
    }

    private func xmlDecodedMetadataText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    private func epubISBN13(_ value: String) -> String? {
        let cleaned = value
            .uppercased()
            .filter { $0.isNumber || $0 == "X" }

        if cleaned.count == 13, cleaned.allSatisfy(\.isNumber) {
            return cleaned
        }

        guard cleaned.count == 10,
              isValidISBN10(cleaned) else {
            return nil
        }

        let prefix = "978" + cleaned.prefix(9)
        let checkSum = prefix.enumerated().reduce(0) { partialResult, element in
            let digit = Int(String(element.element)) ?? 0
            return partialResult + digit * (element.offset.isMultiple(of: 2) ? 1 : 3)
        }
        let checkDigit = (10 - (checkSum % 10)) % 10
        return prefix + "\(checkDigit)"
    }

    private func epubSourceID(_ value: String) -> SableLibrarySourceID? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let openLibraryRange = trimmed.range(
            of: #"(?i)\bOL\d+[WM]\b"#,
            options: .regularExpression
        ) {
            let hasOpenLibraryContext = trimmed.range(
                of: #"(?i)\bopen\s*library\b|openlibrary|openlibrary\.org|/works/|/books/"#,
                options: .regularExpression
            ) != nil
            if hasOpenLibraryContext {
                let id = String(trimmed[openLibraryRange]).uppercased()
                let path = id.hasSuffix("W") ? "/works/\(id)" : "/books/\(id)"
                return SableLibrarySourceID(provider: .openLibrary, value: path)
            }
        }

        if let wikidataRange = trimmed.range(
            of: #"(?i)\bQ\d+\b"#,
            options: .regularExpression
        ) {
            let hasWikidataContext = trimmed.range(
                of: #"(?i)\bwikidata\b|wikidata\.org"#,
                options: .regularExpression
            ) != nil
            if hasWikidataContext {
                return SableLibrarySourceID(
                    provider: .wikidata,
                    value: String(trimmed[wikidataRange]).uppercased()
                )
            }
        }

        return nil
    }

    private func isValidISBN10(_ value: String) -> Bool {
        guard value.count == 10 else { return false }

        let weighted = value.enumerated().reduce(0) { partialResult, element in
            let digit: Int
            if element.element == "X", element.offset == 9 {
                digit = 10
            } else if let number = Int(String(element.element)) {
                digit = number
            } else {
                return partialResult + 1_000
            }
            return partialResult + digit * (10 - element.offset)
        }
        return weighted % 11 == 0
    }

    private func epubYear(_ value: String) -> Int? {
        guard let range = value.range(of: #"\b\d{4}\b"#, options: .regularExpression) else {
            return nil
        }
        return Int(value[range])
    }

    private func shouldUseReadingCatalogTitleSearch(comicInfo: [String: Any], service: SableLibraryService) -> Bool {
        let ids = sourceIDs(from: comicInfo, service: service)
        if ids.contains(where: { $0.provider == .myAnimeList || $0.provider == .anilist }) {
            return true
        }

        let normalizedType = service.textValue(comicInfo["type"])
            .map { SableLibraryNamingPolicy().normalizedMediaType($0) }

        switch normalizedType {
        case "Manga", "Manhwa", "Manhua", "OEL":
            return true
        default:
            return false
        }
    }

    private func enrichComicInfoFromRanobeDB(
        _ comicInfo: inout [String: Any],
        folder: URL,
        root: URL,
        config: SableLibraryConfig,
        service: SableLibraryService,
        localFiles: SidecarLocalFileSnapshot,
        allowTitleSearch: Bool,
        includeBookDetails: Bool,
        authoritativeSourceIDs: [SableLibrarySourceID]
    ) async {
        guard shouldUseRanobeDB(comicInfo: comicInfo, folder: folder, root: root, service: service) else {
            markComicInfoProviderUntouched(
                &comicInfo,
                provider: .ranobedb,
                reason: "RanobeDB enrichment is limited to light-novel-like reading sidecars.",
                service: service
            )
            return
        }

        let title = service.textValue(comicInfo["preferred_title"])
            ?? service.textValue(comicInfo["title"])
            ?? service.cleanSeriesTitle(folder.lastPathComponent)
        let sourceIDs = sourceIDs(from: comicInfo, service: service)
        let hasExistingRanobeDBID = sourceIDs.contains { $0.provider == .ranobedb }
        let knownRanobeDBBookIDs = ranobeDBKnownBookIDs(in: comicInfo, service: service)
        let detailedRanobeDBBookIDs = ranobeDBDetailedBookIDs(in: comicInfo, service: service)

        if let enrichment = await metadataLookupService.readingEnrichment(
            title: title,
            sourceIDs: sourceIDs,
            knownRanobeDBBookIDs: knownRanobeDBBookIDs,
            detailedRanobeDBBookIDs: detailedRanobeDBBookIDs,
            includeBookDetails: includeBookDetails && hasExistingRanobeDBID,
            allowTitleSearch: allowTitleSearch,
            config: config,
            service: service
        ) {
            apply(
                readingEnrichment: enrichment,
                to: &comicInfo,
                folder: folder,
                root: root,
                config: config,
                service: service,
                localFiles: localFiles,
                authoritativeSourceIDs: authoritativeSourceIDs
            )
        } else {
            markComicInfoProviderUntouched(
                &comicInfo,
                provider: .ranobedb,
                reason: "No RanobeDB light-novel match met the quiet confidence gate.",
                service: service
            )
        }
    }

    private func ranobeDBKnownBookIDs(
        in comicInfo: [String: Any],
        service: SableLibraryService
    ) -> Set<String> {
        var result = Set(ranobeDBBookIDsInVolumes(comicInfo["volumes"], service: service))
        guard let sable = comicInfo["_sable"] as? [String: Any],
              let ranobeDB = sable[SableLibraryMetadataProvider.ranobedb.rawValue] as? [String: Any] else {
            return result
        }
        let bookDetail = ranobeDB["book_detail"] as? [String: Any] ?? [:]
        result.formUnion(arrayStrings(bookDetail["known_book_ids"], service: service))
        result.formUnion(arrayStrings(bookDetail["fetched_book_ids"], service: service))
        return result
    }

    private func ranobeDBDetailedBookIDs(
        in comicInfo: [String: Any],
        service: SableLibraryService
    ) -> Set<String> {
        var result = Set<String>()
        let volumes = comicInfo["volumes"] as? [[String: Any]] ?? []
        for volume in volumes where ranobeDBVolumeHasDetailedBookData(volume, service: service) {
            if let bookID = ranobeDBBookID(fromVolume: volume, service: service) {
                result.insert(bookID)
            }
        }

        guard let sable = comicInfo["_sable"] as? [String: Any],
              let ranobeDB = sable[SableLibraryMetadataProvider.ranobedb.rawValue] as? [String: Any] else {
            return result
        }
        let bookDetail = ranobeDB["book_detail"] as? [String: Any] ?? [:]
        result.formUnion(arrayStrings(bookDetail["detailed_book_ids"], service: service))
        for key in ["api", "api_compact"] {
            guard let api = ranobeDB[key] as? [String: Any] else { continue }
            result.formUnion(ranobeDBBookResponseIDs(in: api, service: service))
        }
        return result
    }

    private func ranobeDBBookIDsInVolumes(
        _ value: Any?,
        service: SableLibraryService
    ) -> [String] {
        (value as? [[String: Any]] ?? []).compactMap {
            ranobeDBBookID(fromVolume: $0, service: service)
        }
    }

    private func ranobeDBBookID(
        fromVolume volume: [String: Any],
        service: SableLibraryService
    ) -> String? {
        guard let sourceID = volume["source_id"] as? [String: Any],
              service.textValue(sourceID["provider"])?.lowercased() == SableLibraryMetadataProvider.ranobedb.rawValue else {
            return nil
        }
        return service.textValue(sourceID["value"])
            ?? service.textValue(sourceID["id"])
    }

    private func ranobeDBVolumeHasDetailedBookData(
        _ volume: [String: Any],
        service: SableLibraryService
    ) -> Bool {
        if integerValue(volume["pages"]) != nil
            || service.textValue(volume["description"]) != nil
            || service.textValue(volume["release_date"]) != nil {
            return true
        }
        return !arrayStrings(volume["isbn13"], service: service).isEmpty
            || !arrayStrings(volume["release_ids"], service: service).isEmpty
    }

    private func ranobeDBBookResponseIDs(
        in api: [String: Any],
        service: SableLibraryService
    ) -> [String] {
        (api["book_responses"] as? [[String: Any]] ?? []).compactMap { row in
            let response = row["response"] as? [String: Any] ?? row
            let book = response["book"] as? [String: Any] ?? response
            return service.textValue(book["id"])
        }
    }

    private func shouldUseRanobeDB(
        comicInfo: [String: Any],
        folder: URL,
        root: URL,
        service: SableLibraryService
    ) -> Bool {
        let ids = sourceIDs(from: comicInfo, service: service)
        if ids.contains(where: { $0.provider == .ranobedb }) {
            return true
        }
        if ids.contains(where: { $0.provider == .openLibrary || $0.provider == .wikidata }) {
            return false
        }
        let namingPolicy = SableLibraryNamingPolicy()
        let knownType = service.textValue(comicInfo["type"])
            ?? readingTypeHint(folder: folder, root: root)
        guard let knownType else { return false }
        return namingPolicy.normalizedMediaType(knownType) == "Novel"
    }

    private func apply(
        readingEnrichment enrichment: SableLibraryMetadataEnrichment,
        to comicInfo: inout [String: Any],
        folder: URL,
        root: URL,
        config: SableLibraryConfig,
        service: SableLibraryService,
        localFiles: SidecarLocalFileSnapshot,
        authoritativeSourceIDs: [SableLibrarySourceID] = []
    ) {
        let previousIDs = normalizedIDDictionary(from: comicInfo, service: service)
        let existingRanobeDBKnownBookIDs = ranobeDBKnownBookIDs(in: comicInfo, service: service)
        let existingRanobeDBDetailedBookIDs = ranobeDBDetailedBookIDs(in: comicInfo, service: service)
        let incomingProviders = enrichmentEvidenceProviders(enrichment)
        let usesExactMangaBakaIdentity = incomingProviders.contains(.mangabaka)
            && enrichment.evidence.contains {
                $0.provider == .mangabaka && $0.kind == .exactProviderID
            }
        let authoritativeSourceIDKeys = Set(authoritativeSourceIDs.map(\.stableKey))
        let usesAuthoritativeProviderIdentity = enrichment.sourceIDs.contains { sourceID in
            incomingProviders.contains(sourceID.provider)
                && authoritativeSourceIDKeys.contains(sourceID.stableKey)
        }
        if let localTitle = service.textValue(comicInfo["local_title"]),
           !usesExactMangaBakaIdentity,
           !usesAuthoritativeProviderIdentity,
           readingProviderTitleHardConflictsWithLocalSeriesMarker(
            localTitle: localTitle,
            providerTitle: enrichment.preferredTitle,
            service: service
           ) {
            rejectReadingEnrichmentWithSeriesMarkerConflict(
                enrichment,
                localTitle: localTitle,
                comicInfo: &comicInfo,
                folder: folder,
                service: service,
                reason: "Provider title conflicts with the local series marker.",
                source: "provider_marker_conflict"
            )
            return
        }
        if !usesAuthoritativeProviderIdentity,
           let trustedTitleConflict = readingProviderTitleConflictWithTrustedLocalIdentity(
            enrichment,
            currentComicInfo: comicInfo,
            folder: folder,
            service: service
        ) {
            rejectReadingEnrichmentWithSeriesMarkerConflict(
                enrichment,
                localTitle: trustedTitleConflict.localTitle,
                comicInfo: &comicInfo,
                folder: folder,
                service: service,
                reason: trustedTitleConflict.reason,
                source: "trusted_title_conflict"
            )
            return
        }
        if usesExactMangaBakaIdentity,
           let localTitle = service.textValue(comicInfo["local_title"]),
           readingProviderTitleHardConflictsWithLocalSeriesMarker(
            localTitle: localTitle,
            providerTitle: enrichment.preferredTitle,
            service: service
           ) {
            comicInfo["local_title"] = service.cleanSeriesTitle(enrichment.preferredTitle)
        }

        let hasExistingSpecializedReadingIdentity = previousIDs["mangabaka"] != nil || previousIDs["ranobedb"] != nil
        var ids = previousIDs
        for sourceID in enrichment.sourceIDs {
            if sourceID.provider == .openLibrary, hasExistingSpecializedReadingIdentity {
                continue
            }
            ids[idKey(for: sourceID.provider)] = sourceID.value
        }
        comicInfo["ids"] = ids

        let isBookCatalogMatch = enrichment.providersUsed.allSatisfy { provider in
            provider == .openLibrary || provider == .wikidata
        }
        let hasSpecializedReadingIdentity = ids["mangabaka"] != nil || ids["ranobedb"] != nil
        let shouldUseProviderTitle = shouldUseReadingProviderTitle(
            enrichment.preferredTitle,
            currentComicInfo: comicInfo,
            isBookCatalogMatch: isBookCatalogMatch,
            hasSpecializedReadingIdentity: hasSpecializedReadingIdentity,
            service: service
        )
        let incomingTitleProvider = preferredReadingTitleProvider(from: enrichment)
        let currentTitleProvider = currentReadingTitleProvider(comicInfo: comicInfo, ids: previousIDs, service: service)
        let canPromoteTitle = readingTitlePriority(incomingTitleProvider) >= readingTitlePriority(currentTitleProvider)
            && !(isBookCatalogMatch && hasSpecializedReadingIdentity)
        let repairedSeriesTitle = usesExactMangaBakaIdentity
            ? nil
            : readingSeriesTitleRepairCandidate(
                providerTitle: enrichment.preferredTitle,
                currentComicInfo: comicInfo,
                service: service
            )
        if shouldUseProviderTitle, canPromoteTitle {
            let resolvedTitle = repairedSeriesTitle?.title ?? enrichment.preferredTitle
            let resolvedTitleProvider = repairedSeriesTitle?.provider ?? incomingTitleProvider
            comicInfo["title"] = resolvedTitle
            comicInfo["preferred_title"] = resolvedTitle
            rememberReadingTitleSource(
                provider: resolvedTitleProvider,
                title: resolvedTitle,
                in: &comicInfo,
                service: service
            )
        } else if let repairedSeriesTitle {
            comicInfo["title"] = repairedSeriesTitle.title
            comicInfo["preferred_title"] = repairedSeriesTitle.title
            rememberReadingTitleSource(
                provider: repairedSeriesTitle.provider,
                title: repairedSeriesTitle.title,
                in: &comicInfo,
                service: service
            )
        } else if !shouldUseProviderTitle,
                  let localTitle = service.textValue(comicInfo["local_title"]) {
            comicInfo["title"] = localTitle
            comicInfo["preferred_title"] = localTitle
            rememberReadingTitleSource(
                provider: .local,
                title: localTitle,
                in: &comicInfo,
                service: service
            )
        }
        if let year = enrichment.year,
           comicInfo["year"] == nil || usesAuthoritativeProviderIdentity {
            comicInfo["year"] = year
        }
        let normalizedType = service.textValue(comicInfo["type"]).map { SableLibraryNamingPolicy().normalizedMediaType($0) }
        let localMediaTypeHint = localReadingMediaTypeHint(
            currentComicInfo: comicInfo,
            folder: folder,
            root: root,
            localFiles: localFiles,
            service: service
        )
        let resolvedMediaType = localMediaTypeHint ?? enrichment.mediaType
        if let mediaType = resolvedMediaType,
           shouldApplyReadingMediaType(
            mediaType,
            normalizedCurrentType: normalizedType,
            isBookCatalogMatch: isBookCatalogMatch,
            hasSpecializedReadingIdentity: hasSpecializedReadingIdentity
           ) {
            comicInfo["type"] = mediaType
        }

        let normalizedPreferredTitle = service.normalizeTerm(
            service.textValue(comicInfo["preferred_title"]) ?? enrichment.preferredTitle
        )
        let existingAliases = comicInfo["aliases"] as? [String] ?? []
        let dedupedAliases = ([enrichment.preferredTitle] + enrichment.aliases).filter {
            service.normalizeTerm($0) != normalizedPreferredTitle
        }
        comicInfo["aliases"] = uniqueStrings(existingAliases + dedupedAliases)
        let existingVolumeTitles = combinedStringList(
            from: comicInfo,
            keys: ["volume_titles", "subtitles"],
            service: service
        )
        let partTitles = enrichment.readingParts.compactMap { $0.subtitle }
        let volumeTitles = uniqueStrings(existingVolumeTitles + partTitles)
        if volumeTitles.isEmpty {
            comicInfo.removeValue(forKey: "volume_titles")
        } else {
            comicInfo["volume_titles"] = volumeTitles
        }
        if comicInfo["description"] == nil, let description = enrichment.description {
            comicInfo["description"] = description
        }
        comicInfo["genres"] = uniqueStrings(arrayStrings(comicInfo["genres"], service: service) + enrichment.genres)
        comicInfo["tags"] = uniqueStrings(arrayStrings(comicInfo["tags"], service: service) + enrichment.tags)
        comicInfo["content_warnings"] = uniqueStrings(
            arrayStrings(comicInfo["content_warnings"], service: service) + enrichment.contentWarnings
        )
        if !enrichment.studios.isEmpty {
            comicInfo["studios"] = uniqueStrings(arrayStrings(comicInfo["studios"], service: service) + enrichment.studios)
        }
        comicInfo["authors"] = uniqueStrings(arrayStrings(comicInfo["authors"], service: service) + enrichment.authors)
        comicInfo["artists"] = uniqueStrings(arrayStrings(comicInfo["artists"], service: service) + enrichment.artists)
        comicInfo["publishers"] = uniqueStrings(arrayStrings(comicInfo["publishers"], service: service) + enrichment.publishers)
        comicInfo["languages"] = uniqueStrings(arrayStrings(comicInfo["languages"], service: service) + enrichment.languages)
        if let status = enrichment.status {
            comicInfo["status"] = status
        }
        if let contentRating = enrichment.contentRating {
            comicInfo["content_rating"] = contentRating
        }
        if comicInfo["cover_url"] == nil,
           let coverURL = enrichment.coverURL?.trimmingCharacters(in: .whitespacesAndNewlines),
           !coverURL.isEmpty {
            comicInfo["cover_url"] = coverURL
        }
        let existingISBN = arrayStrings(comicInfo["isbn13"], service: service)
        comicInfo["isbn13"] = uniqueStrings(existingISBN + enrichment.isbn13)
        comicInfo["volumes"] = mergedReadingParts(
            existing: comicInfo["volumes"] as? [[String: Any]] ?? [],
            enriched: enrichment.readingParts,
            service: service
        )

        let existingEvidence = comicInfo["match_evidence"] as? [[String: Any]] ?? []
        comicInfo["match_evidence"] = mergedEvidenceDictionaries(
            existing: existingEvidence,
            refreshed: enrichment.evidence
        )
        let existingFreshness = comicInfo["source_freshness"] as? [[String: Any]] ?? []
        comicInfo["source_freshness"] = mergedFreshnessDictionaries(
            existing: existingFreshness,
            refreshed: enrichment.freshness
        )
        comicInfo["source"] = sourceText(
            existing: service.textValue(comicInfo["source"]),
            providers: enrichment.providersUsed
        )
        comicInfo["last_checked"] = service.isoTimestamp()

        let resolvedTitle = service.textValue(comicInfo["preferred_title"]) ?? enrichment.preferredTitle
        let resolvedYear = integerValue(comicInfo["year"]) ?? enrichment.year ?? yearHint(in: folder.lastPathComponent)
        let resolvedType = service.textValue(comicInfo["type"]) ?? enrichment.mediaType ?? "lightNovel"
        comicInfo["plex"] = readingOrganizerHints(
            title: resolvedTitle,
            year: resolvedYear,
            ids: ids,
            mediaType: resolvedType
        )

        var sable = comicInfo["_sable"] as? [String: Any] ?? [:]
        let localNumbers = localVolumeNumbers(in: localFiles.bookItems, config: config, service: service)
        if enrichment.providersUsed.contains(.ranobedb) {
            let mergedVolumes = comicInfo["volumes"] as? [[String: Any]] ?? []
            let providerVolumeNumbers = mergedVolumes.compactMap { integerValue($0["number"]) }.sorted()
            let providerVolumeNumberSet = Set(providerVolumeNumbers)
            let missingLocalNumbers = localNumbers.filter { !providerVolumeNumberSet.contains($0) }
            let incomingAPIPayload = enrichment.providerPayloads[SableLibraryMetadataProvider.ranobedb.rawValue]?
                .foundationValue as? [String: Any]
            let delta = incomingAPIPayload?["delta"] as? [String: Any] ?? [:]
            let seriesBookIDs = arrayStrings(delta["series_book_ids"], service: service)
            let requestedBookIDs = arrayStrings(delta["requested_book_detail_ids"], service: service)
            let newlyFetchedBookIDs = arrayStrings(delta["fetched_book_detail_ids"], service: service)
            let failedBookIDs = arrayStrings(delta["failed_book_detail_ids"], service: service)
            let newReleaseBookIDs = arrayStrings(delta["new_release_book_ids"], service: service)
            let knownBookIDs = uniqueStrings(
                existingRanobeDBKnownBookIDs.sorted() + seriesBookIDs
            )
            let detailedBookIDs = uniqueStrings(
                existingRanobeDBDetailedBookIDs.sorted() + newlyFetchedBookIDs
            )
            let seriesID = service.textValue(ids["ranobedb"]) ?? ""
            let existingRanobeDBMetadata = sable["ranobedb"] as? [String: Any] ?? [:]
            var ranobeDBMetadata: [String: Any] = [
                "outcome": SableLibraryQuietOutcome.safeApply.rawValue,
                "confidence_score": roundedScore(enrichment.confidenceScore),
                "series_id": seriesID,
                "series_detail": [
                    "fetched": !seriesID.isEmpty,
                    "endpoint": seriesID.isEmpty ? "" : "series/\(seriesID)",
                    "fetch_mode": ranobeDBFetchMode(from: enrichment.evidence),
                    "evidence": ranobeDBEvidenceValues(from: enrichment.evidence)
                ],
                "book_detail": [
                    "local_volume_numbers": localNumbers,
                    "fetched_volume_numbers": providerVolumeNumbers,
                    "missing_local_volume_numbers": missingLocalNumbers,
                    "known_book_ids": knownBookIDs,
                    "known_book_count": knownBookIDs.count,
                    "detailed_book_ids": detailedBookIDs,
                    "fetched_book_ids": detailedBookIDs,
                    "fetched_book_count": detailedBookIDs.count,
                    "new_release_book_ids": newReleaseBookIDs,
                    "new_release_count": newReleaseBookIDs.count,
                    "requested_book_detail_ids": requestedBookIDs,
                    "requested_book_detail_count": requestedBookIDs.count,
                    "newly_fetched_book_ids": newlyFetchedBookIDs,
                    "newly_fetched_book_count": newlyFetchedBookIDs.count,
                    "failed_book_detail_ids": failedBookIDs,
                    "volume_with_isbn_count": mergedVolumes.filter { !arrayStrings($0["isbn13"], service: service).isEmpty }.count,
                    "volume_release_id_count": mergedVolumes.reduce(0) {
                        $0 + arrayStrings($1["release_ids"], service: service).count
                    },
                    "volume_with_pages_count": mergedVolumes.filter { integerValue($0["pages"]) != nil }.count
                ],
                "provider_known_volume_count": providerVolumeNumbers.count,
                "provider_known_highest_volume": providerVolumeNumbers.max() ?? 0,
                "isbn_count": arrayStrings(comicInfo["isbn13"], service: service).count,
                "local_volume_count": localNumbers.count,
                "local_highest_volume": localNumbers.max() ?? 0,
                "updated_at": service.isoTimestamp()
            ]
            if let apiPayload = mergedRanobeDBAPIPayload(
                existingMetadata: existingRanobeDBMetadata,
                incomingPayload: incomingAPIPayload,
                service: service
            ) {
                ranobeDBMetadata["api"] = apiPayload
                ranobeDBMetadata["api_summary"] = ranobeDBAPISummary(from: apiPayload, service: service)
            }
            sable["ranobedb"] = ranobeDBMetadata
        }
        let existingProviders = (sable["metadata_enrichment"] as? [String: Any])?["providers"] as? [String] ?? []
        sable["metadata_enrichment"] = [
            "outcome": SableLibraryQuietOutcome.safeApply.rawValue,
            "confidence_score": roundedScore(enrichment.confidenceScore),
            "providers": uniqueStrings(existingProviders + enrichment.providersUsed.map(\.rawValue)),
            "updated_at": service.isoTimestamp()
        ]
        sable["organizer_source"] = organizerSourceSnapshot(
            folderName: folder.lastPathComponent,
            cleanTitle: resolvedTitle,
            year: resolvedYear,
            sourceID: sourceIDHint(in: folder.lastPathComponent) ?? readingSourceID(from: ids)
        )
        comicInfo["_sable"] = sable
    }

    private func rejectReadingEnrichmentWithSeriesMarkerConflict(
        _ enrichment: SableLibraryMetadataEnrichment,
        localTitle: String,
        comicInfo: inout [String: Any],
        folder: URL,
        service: SableLibraryService,
        reason: String,
        source: String
    ) {
        let cleanLocalTitle = service.cleanSeriesTitle(localTitle)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanLocalTitle.isEmpty else { return }

        let rejectedProviders = enrichmentEvidenceProviders(enrichment)
        var ids = normalizedIDDictionary(from: comicInfo, extraIDs: sourceIDHints(in: folder.lastPathComponent), service: service)
        for provider in rejectedProviders {
            ids.removeValue(forKey: idKey(for: provider))
        }
        comicInfo["ids"] = ids
        comicInfo["title"] = cleanLocalTitle
        comicInfo["preferred_title"] = cleanLocalTitle
        if let existingLocalTitle = service.textValue(comicInfo["local_title"]),
           readingProviderTitleHardConflictsWithLocalSeriesMarker(
            localTitle: existingLocalTitle,
            providerTitle: cleanLocalTitle,
            service: service
           ) {
            comicInfo["local_title"] = cleanLocalTitle
        }
        let existingAliases = arrayStrings(comicInfo["aliases"], service: service)
        comicInfo["aliases"] = uniqueStrings(existingAliases + [enrichment.preferredTitle])
        comicInfo["source_freshness"] = filteredProviderDictionaries(
            comicInfo["source_freshness"] as? [[String: Any]] ?? [],
            removing: Set(rejectedProviders),
            service: service
        )
        comicInfo["match_evidence"] = filteredProviderDictionaries(
            comicInfo["match_evidence"] as? [[String: Any]] ?? [],
            removing: Set(rejectedProviders),
            service: service
        )

        let trustedProviders = sourceIDs(from: ["ids": ids], service: service).map(\.provider)
        comicInfo["source"] = sourceText(existing: nil, providers: trustedProviders)
        comicInfo["last_checked"] = service.isoTimestamp()

        rememberReadingTitleSource(
            provider: .local,
            title: cleanLocalTitle,
            in: &comicInfo,
            service: service
        )

        var sable = comicInfo["_sable"] as? [String: Any] ?? [:]
        for provider in rejectedProviders {
            sable.removeValue(forKey: provider.rawValue)
        }
        var reviews = sable["provider_candidate_review"] as? [String: Any] ?? [:]
        for provider in rejectedProviders {
            let rejectedID = enrichment.sourceIDs.first { $0.provider == provider }?.value
            reviews[provider.rawValue] = [
                "status": SableLibraryProviderCandidateReview.Status.noMatch.rawValue,
                "provider": provider.rawValue,
                "source": source,
                "query": cleanLocalTitle,
                "confidence_score": 0,
                "confidence_percent": 0,
                "rejected_candidate_id": rejectedID ?? "",
                "rejected_candidate_title": enrichment.preferredTitle,
                "reason": reason,
                "updated_at": service.isoTimestamp()
            ]
        }
        sable["provider_candidate_review"] = reviews
        sable["metadata_enrichment"] = [
            "outcome": SableLibraryQuietOutcome.needsAttention.rawValue,
            "confidence_score": 0,
            "providers": rejectedProviders.map(\.rawValue),
            "reason": "Skipped provider enrichment because \(reason.lowercased())",
            "updated_at": service.isoTimestamp()
        ]

        let resolvedYear = integerValue(comicInfo["year"]) ?? enrichment.year ?? yearHint(in: folder.lastPathComponent)
        let resolvedType = service.textValue(comicInfo["type"]) ?? enrichment.mediaType ?? "lightNovel"
        comicInfo["plex"] = readingOrganizerHints(
            title: cleanLocalTitle,
            year: resolvedYear,
            ids: ids,
            mediaType: resolvedType
        )
        sable["organizer_source"] = organizerSourceSnapshot(
            folderName: folder.lastPathComponent,
            cleanTitle: cleanLocalTitle,
            year: resolvedYear,
            sourceID: sourceIDHint(in: folder.lastPathComponent) ?? readingSourceID(from: ids)
        )
        comicInfo["_sable"] = sable
    }

    private func filteredProviderDictionaries(
        _ rows: [[String: Any]],
        removing providers: Set<SableLibraryMetadataProvider>,
        service: SableLibraryService
    ) -> [[String: Any]] {
        rows.filter { row in
            guard let providerText = service.textValue(row["provider"]),
                  let provider = SableLibraryMetadataProvider(rawValue: providerText) else {
                return true
            }
            return !providers.contains(provider)
        }
    }

    private func readingProviderTitleConflictWithTrustedLocalIdentity(
        _ enrichment: SableLibraryMetadataEnrichment,
        currentComicInfo: [String: Any],
        folder: URL,
        service: SableLibraryService
    ) -> (localTitle: String, reason: String)? {
        let incomingProviders = enrichmentEvidenceProviders(enrichment)
        guard incomingProviders.contains(where: { $0 != .local }) else {
            return nil
        }

        let ids = normalizedIDDictionary(from: currentComicInfo, service: service)
        let hasTrustedMangaBakaIdentity = hasID("mangabaka", in: ids, service: service)
        let hasTrustedLocalTitle = service.textValue(currentComicInfo["local_title"]) != nil
        let folderTitle = organizerTitle(from: folder.lastPathComponent, service: service)
        let hasTrustedFolderTitle = !service.normalizeTerm(folderTitle).isEmpty
        guard hasTrustedMangaBakaIdentity || hasTrustedLocalTitle || hasTrustedFolderTitle else {
            return nil
        }

        let trustedTitles = trustedLocalReadingIdentityTitles(
            currentComicInfo: currentComicInfo,
            folderTitle: folderTitle,
            service: service
        )
        guard let fallbackTitle = trustedTitles.first, !trustedTitles.isEmpty else {
            return nil
        }

        let providerTitle = service.cleanSeriesTitle(enrichment.preferredTitle)
        let providerNormalized = service.normalizeTerm(providerTitle)
        guard !providerNormalized.isEmpty else {
            return nil
        }

        if hasTrustedMangaBakaIdentity,
           !incomingProviders.contains(.mangabaka),
           let mangaBakaConflict = trustedReadingSeriesTitleCandidates(
            currentComicInfo: currentComicInfo,
            service: service
           )
            .first(where: { candidate in
                candidate.provider == .mangabaka
                    && readingProviderTitleHardConflictsWithLocalSeriesMarker(
                        localTitle: candidate.title,
                        providerTitle: providerTitle,
                        service: service
                    )
            }) {
            return (
                mangaBakaConflict.title,
                "Provider title \"\(providerTitle)\" conflicts with the trusted MangaBaka title \"\(mangaBakaConflict.title)\"."
            )
        }

        let matchesTrustedTitle = trustedTitles.contains { trustedTitle in
            readingSeriesTitlesMatch(providerTitle, trustedTitle, service: service)
                || providerTitleAddsOnlyVolumeMarker(providerTitle, toCleanSeriesTitle: trustedTitle, service: service)
                || tokenSimilarity(providerNormalized, service.normalizeTerm(trustedTitle)) >= 0.72
        }
        if matchesTrustedTitle {
            return nil
        }

        return (
            fallbackTitle,
            "Provider title \"\(providerTitle)\" does not match the trusted local or MangaBaka title \"\(fallbackTitle)\"."
        )
    }

    private func trustedLocalReadingIdentityTitles(
        currentComicInfo: [String: Any],
        folderTitle: String? = nil,
        service: SableLibraryService
    ) -> [String] {
        var titles: [String] = []
        var seen = Set<String>()

        func append(_ value: String?) {
            guard let value else { return }
            let cleanValue = service.cleanSeriesTitle(value)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedValue = service.normalizeTerm(cleanValue)
            guard !normalizedValue.isEmpty,
                  seen.insert(normalizedValue).inserted else {
                return
            }
            titles.append(cleanValue)
        }

        append(service.textValue(currentComicInfo["local_title"]))
        append(folderTitle)
        if let sable = currentComicInfo["_sable"] as? [String: Any],
           let mangaBaka = sable["mangabaka"] as? [String: Any] {
            append(service.textValue(mangaBaka["matched_title"]))
            append(service.textValue(mangaBaka["matched_alias"]))
            append(service.textValue(mangaBaka["query"]))
            for title in mangaBakaStoredTitles(from: mangaBaka, service: service) {
                append(title)
            }
        }

        return titles
    }

    private func preferredReadingTitleProvider(from enrichment: SableLibraryMetadataEnrichment) -> SableLibraryMetadataProvider {
        let providers = enrichmentEvidenceProviders(enrichment)
        return providers.max { lhs, rhs in
            readingTitlePriority(lhs) < readingTitlePriority(rhs)
        } ?? .local
    }

    private func enrichmentEvidenceProviders(
        _ enrichment: SableLibraryMetadataEnrichment
    ) -> [SableLibraryMetadataProvider] {
        uniqueProviders(enrichment.providersUsed + enrichment.evidence.map(\.provider))
    }

    private func currentReadingTitleProvider(
        comicInfo: [String: Any],
        ids: [String: Any],
        service: SableLibraryService
    ) -> SableLibraryMetadataProvider {
        if let sable = comicInfo["_sable"] as? [String: Any],
           let titleSource = sable["title_source"] as? [String: Any],
           let rawProvider = service.textValue(titleSource["provider"]),
           let provider = SableLibraryMetadataProvider(rawValue: rawProvider) {
            return provider
        }

        if hasID("ranobedb", in: ids, service: service) {
            return .ranobedb
        }
        if hasID("mangabaka", in: ids, service: service) {
            return .mangabaka
        }
        if hasID("anilist", in: ids, service: service)
            || hasID("mal", in: ids, service: service)
            || hasID("myanimelist", in: ids, service: service) {
            return .anilist
        }
        if hasID("openlibrary", in: ids, service: service) {
            return .openLibrary
        }

        return .local
    }

    private func readingSeriesTitleRepairCandidate(
        providerTitle: String,
        currentComicInfo: [String: Any],
        service: SableLibraryService
    ) -> (title: String, provider: SableLibraryMetadataProvider)? {
        if let localTitle = service.textValue(currentComicInfo["local_title"]) {
            let cleanLocalTitle = service.cleanSeriesTitle(localTitle)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanLocalTitle.isEmpty,
               (shouldPreferLocalDisplayTitle(
                localTitle: cleanLocalTitle,
                over: providerTitle,
                service: service
               ) || readingProviderTitleLosesLocalSeriesMarker(
                localTitle: cleanLocalTitle,
                providerTitle: providerTitle,
                service: service
               )) {
                return (cleanLocalTitle, .local)
            }
        }

        for candidate in trustedReadingSeriesTitleCandidates(currentComicInfo: currentComicInfo, service: service) {
            let cleanCandidateTitle = service.cleanSeriesTitle(candidate.title)
            guard providerTitleAddsOnlyVolumeMarker(
                providerTitle,
                toCleanSeriesTitle: cleanCandidateTitle,
                service: service
            ) else {
                continue
            }
            return (cleanCandidateTitle, candidate.provider)
        }

        return nil
    }

    private func cleanupComicInfoTitleSidecar(
        _ comicInfo: [String: Any],
        folder: URL,
        root: URL,
        config: SableLibraryConfig,
        service: SableLibraryService
    ) -> [String: Any]? {
        guard let currentTitle = service.textValue(comicInfo["preferred_title"]) ?? service.textValue(comicInfo["title"]) else {
            return nil
        }

        let localTitle = service.textValue(comicInfo["local_title"])
            ?? organizerTitle(from: folder.lastPathComponent, service: service)
        guard let repairedTitle = sidecarTitleRepairCandidate(
            currentTitle: currentTitle,
            localTitle: localTitle,
            service: service
        ) else {
            return nil
        }

        var repaired = comicInfo
        repaired["title"] = repairedTitle
        repaired["preferred_title"] = repairedTitle
        if let sortTitle = service.textValue(repaired["sort_title"]),
           providerTitleAddsOnlyVolumeMarker(sortTitle, toCleanSeriesTitle: repairedTitle, service: service) {
            repaired["sort_title"] = repairedTitle
        }

        let existingAliases = arrayStrings(repaired["aliases"], service: service)
        repaired["aliases"] = uniqueStrings(existingAliases + [currentTitle])
        let ids = normalizedIDDictionary(from: repaired, service: service)
        let resolvedYear = integerValue(repaired["year"]) ?? yearHint(in: folder.lastPathComponent)
        let resolvedType = service.textValue(repaired["type"]) ?? "unknown"
        repaired["plex"] = readingOrganizerHints(
            title: repairedTitle,
            year: resolvedYear,
            ids: ids,
            mediaType: resolvedType
        )

        rememberReadingTitleSource(provider: .local, title: repairedTitle, in: &repaired, service: service)
        var sable = repaired["_sable"] as? [String: Any] ?? [:]
        sable["title_repair"] = [
            "outcome": SableLibraryQuietOutcome.safeApply.rawValue,
            "reason": "Trimmed provider volume marker before metadata refresh.",
            "previous_title": currentTitle,
            "repaired_title": repairedTitle,
            "updated_at": service.isoTimestamp()
        ]
        sable["organizer_source"] = organizerSourceSnapshot(
            folderName: folder.lastPathComponent,
            cleanTitle: repairedTitle,
            year: resolvedYear,
            sourceID: sourceIDHint(in: folder.lastPathComponent) ?? readingSourceID(from: ids)
        )
        repaired["_sable"] = sable
        return repaired
    }

    private func cleanupComicInfoProviderDataSidecar(
        _ comicInfo: [String: Any],
        service: SableLibraryService
    ) -> [String: Any] {
        var cleaned = cleanupSidecarProviderData(comicInfo, service: service)
        refreshReadingCatalogView(in: &cleaned, service: service)
        return cleaned
    }

    private func cleanupSidecarProviderData(
        _ sidecar: [String: Any],
        service: SableLibraryService
    ) -> [String: Any] {
        var cleaned = sidecar
        moveBookScopedOpenLibraryIDToAvailability(in: &cleaned, service: service)
        pruneRejectedProviderPublicTraces(in: &cleaned, service: service)
        normalizeSidecarCoverURL(in: &cleaned, service: service)
        compactSableMetadata(in: &cleaned, service: service)
        return cleaned
    }

    private func cleanupWatchingSidecarData(
        _ sidecar: [String: Any],
        folder: URL?,
        config: SableLibraryConfig,
        service: SableLibraryService
    ) -> [String: Any] {
        var cleaned = cleanupSidecarProviderData(sidecar, service: service)
        cleanWatchingSourceTitleFields(in: &cleaned, config: config, service: service)
        refreshWatchingPlexHints(in: &cleaned, folder: folder, service: service)
        return cleaned
    }

    private func animeInfoCleanerReasons(
        in sidecar: [String: Any],
        config: SableLibraryConfig,
        service: SableLibraryService
    ) -> [String] {
        var reasons = sidecarProviderCleanerReasons(in: sidecar, service: service)
        if watchingSourceTitleCleanupCandidate(in: sidecar, config: config, service: service) != nil {
            reasons.insert("source tag can be removed from AnimeInfo titles", at: 0)
        }
        return uniqueStrings(reasons)
    }

    private func watchingSourceTitleCleanupCandidate(
        in sidecar: [String: Any],
        config: SableLibraryConfig,
        service: SableLibraryService
    ) -> String? {
        for key in ["preferred_title", "title", "local_title", "sort_title"] {
            guard let value = service.textValue(sidecar[key]),
                  let cleaned = cleanedWatchingTitle(value, config: config, service: service),
                  service.normalizeTerm(cleaned) != service.normalizeTerm(value) else {
                continue
            }
            return cleaned
        }
        return nil
    }

    private func cleanedWatchingTitle(
        _ value: String,
        config: SableLibraryConfig,
        service: SableLibraryService
    ) -> String? {
        let cleaned = service.cleanSeriesTitle(
            service.cleanedTitle(value, config: config)
        )
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              service.normalizeTerm(trimmed) != service.normalizeTerm(value) else {
            return nil
        }
        return trimmed
    }

    private func cleanWatchingSourceTitleFields(
        in sidecar: inout [String: Any],
        config: SableLibraryConfig,
        service: SableLibraryService
    ) {
        for key in ["title", "local_title", "preferred_title", "sort_title"] {
            guard let value = service.textValue(sidecar[key]),
                  let cleaned = cleanedWatchingTitle(value, config: config, service: service) else {
                continue
            }
            sidecar[key] = cleaned
        }
    }

    private func refreshWatchingPlexHints(
        in sidecar: inout [String: Any],
        folder: URL?,
        service: SableLibraryService
    ) {
        guard let title = service.textValue(sidecar["preferred_title"])
            ?? service.textValue(sidecar["title"]) else {
            return
        }

        let year = integerValue(sidecar["year"])
        let ids = normalizedIDDictionary(from: sidecar, service: service)
        let mediaType = service.textValue(sidecar["type"]) ?? SableLibraryWatchingType.unknownVideo.rawValue
        sidecar["plex"] = plexHints(title: title, year: year, ids: ids, mediaType: mediaType)

        var sable = sidecar["_sable"] as? [String: Any] ?? [:]
        var organizer = sable["organizer_source"] as? [String: Any] ?? [:]
        if !organizer.isEmpty || folder != nil {
            let folderName = folder?.lastPathComponent
                ?? service.textValue(organizer["folder_name"])
                ?? title
            organizer["folder_name"] = folderName
            organizer["clean_title"] = title
            organizer["title_with_year"] = year.map { "\(title) (\($0))" } ?? title
            organizer["year_preserved"] = year != nil
            sable["organizer_source"] = organizer
            sidecar["_sable"] = sable
        }
    }

    private func sidecarTitleRepairCandidate(
        currentTitle: String,
        localTitle: String,
        service: SableLibraryService
    ) -> String? {
        let cleanLocalTitle = service.cleanSeriesTitle(localTitle)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanLocalTitle.isEmpty else { return nil }

        if shouldPreferLocalDisplayTitle(
            localTitle: cleanLocalTitle,
            over: currentTitle,
            service: service
        ) {
            return cleanLocalTitle
        }

        if readingProviderTitleLosesLocalSeriesMarker(
            localTitle: cleanLocalTitle,
            providerTitle: currentTitle,
            service: service
        ) {
            return cleanLocalTitle
        }

        guard providerTitleAddsOnlyVolumeMarker(
            currentTitle,
            toCleanSeriesTitle: cleanLocalTitle,
            service: service
        ) else {
            return nil
        }

        return cleanLocalTitle
    }

    private func trustedReadingSeriesTitleCandidates(
        currentComicInfo: [String: Any],
        service: SableLibraryService
    ) -> [(title: String, provider: SableLibraryMetadataProvider)] {
        var candidates: [(title: String, provider: SableLibraryMetadataProvider)] = []
        var seen = Set<String>()

        func append(_ value: String?, provider: SableLibraryMetadataProvider) {
            guard let value else { return }
            let cleanValue = service.cleanSeriesTitle(value)
            let normalizedValue = service.normalizeTerm(cleanValue)
            guard !normalizedValue.isEmpty,
                  seen.insert(normalizedValue).inserted else {
                return
            }
            candidates.append((cleanValue, provider))
        }

        if let sable = currentComicInfo["_sable"] as? [String: Any] {
            if let ranobeDB = sable["ranobedb"] as? [String: Any] {
                append(service.textValue(ranobeDB["matched_title"]), provider: .ranobedb)
                append(service.textValue(ranobeDB["series_title"]), provider: .ranobedb)
                append(service.textValue(ranobeDB["title"]), provider: .ranobedb)
            }
            if let mangaBaka = sable["mangabaka"] as? [String: Any] {
                append(service.textValue(mangaBaka["matched_title"]), provider: .mangabaka)
                append(service.textValue(mangaBaka["matched_alias"]), provider: .mangabaka)
                append(service.textValue(mangaBaka["query"]), provider: .mangabaka)
                for title in mangaBakaStoredTitles(from: mangaBaka, service: service) {
                    append(title, provider: .mangabaka)
                }
            }
            if let aniList = sable["anilist"] as? [String: Any] {
                append(service.textValue(aniList["matched_title"]), provider: .anilist)
                append(service.textValue(aniList["title"]), provider: .anilist)
            }
        }

        append(service.textValue(currentComicInfo["local_title"]), provider: .local)

        return candidates
    }

    private func mangaBakaStoredTitles(
        from metadata: [String: Any],
        service: SableLibraryService
    ) -> [String] {
        var titles: [String] = []
        var seen = Set<String>()

        func append(_ value: String?) {
            guard let value else { return }
            let cleanValue = service.cleanSeriesTitle(value)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedValue = service.normalizeTerm(cleanValue)
            guard !normalizedValue.isEmpty,
                  seen.insert(normalizedValue).inserted else {
                return
            }
            titles.append(cleanValue)
        }

        if let rows = metadata["titles_v2"] as? [[String: Any]] {
            for row in rows {
                append(service.textValue(row["title"]))
            }
        }

        return titles
    }

    private func providerTitleAddsOnlyVolumeMarker(
        _ providerTitle: String,
        toCleanSeriesTitle cleanSeriesTitle: String,
        service: SableLibraryService
    ) -> Bool {
        let normalizedProviderTitle = service.normalizeTerm(service.cleanSeriesTitle(providerTitle))
        let normalizedSeriesTitle = service.normalizeTerm(cleanSeriesTitle)
        guard !normalizedProviderTitle.isEmpty,
              !normalizedSeriesTitle.isEmpty,
              normalizedProviderTitle != normalizedSeriesTitle else {
            return false
        }

        guard let strippedProviderTitle = providerTitleRemovingVolumeSuffix(
            providerTitle,
            service: service
        ) else {
            return false
        }

        return readingSeriesTitlesMatch(
            strippedProviderTitle,
            cleanSeriesTitle,
            service: service
        )
    }

    private func providerTitleRemovingVolumeSuffix(
        _ providerTitle: String,
        service: SableLibraryService
    ) -> String? {
        var strippedTitle = service.cleanSeriesTitle(providerTitle)
        let originalTitle = strippedTitle
        let suffixPatterns = [
            #"\s*\((?:light\s*novel|novel)\)\s*,?\s*vol(?:ume)?\.?\s*0*\d+\s*$"#,
            #"\s*,?\s*vol(?:ume)?\.?\s*0*\d+\s*\((?:light\s*novel|novel)\)\s*$"#,
            #"\s*\((?:vol(?:ume)?\.?|book|novel)\s*0*\d+\)\s*$"#,
            #"\s*,?\s*(?:vol(?:ume)?\.?|book|novel)\s*0*\d+\s*$"#,
            #"\s+0*\d+\s*\((?:light\s*novel|novel)\)\s*$"#
        ]

        var changed = true
        while changed {
            changed = false
            for pattern in suffixPatterns {
                let nextTitle = strippedTitle
                    .replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if nextTitle != strippedTitle {
                    strippedTitle = nextTitle
                    changed = true
                }
            }
        }

        let normalizedOriginalTitle = service.normalizeTerm(originalTitle)
        let normalizedStrippedTitle = service.normalizeTerm(strippedTitle)
        guard !normalizedStrippedTitle.isEmpty,
              normalizedStrippedTitle != normalizedOriginalTitle else {
            return nil
        }

        return strippedTitle
    }

    private func readingSeriesTitlesMatch(
        _ lhs: String,
        _ rhs: String,
        service: SableLibraryService
    ) -> Bool {
        let normalizedLHS = service.normalizeTerm(lhs)
        let normalizedRHS = service.normalizeTerm(rhs)
        guard !normalizedLHS.isEmpty,
              !normalizedRHS.isEmpty else {
            return false
        }
        if normalizedLHS == normalizedRHS {
            return true
        }

        let articlelessLHS = normalizedLHS
            .replacingOccurrences(of: #"^(?:a|an|the)\s+"#, with: "", options: .regularExpression)
        let articlelessRHS = normalizedRHS
            .replacingOccurrences(of: #"^(?:a|an|the)\s+"#, with: "", options: .regularExpression)
        if articlelessLHS == articlelessRHS {
            return true
        }

        return tokenSimilarity(articlelessLHS, articlelessRHS) >= 0.88
    }

    private func hasID(_ key: String, in ids: [String: Any], service: SableLibraryService) -> Bool {
        guard let value = service.textValue(ids[key]) else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func shouldApplyReadingMediaType(
        _ incomingType: String,
        normalizedCurrentType: String?,
        isBookCatalogMatch: Bool,
        hasSpecializedReadingIdentity: Bool
    ) -> Bool {
        let normalizedIncoming = SableLibraryNamingPolicy().normalizedMediaType(incomingType)
        if normalizedIncoming == "Book", hasSpecializedReadingIdentity {
            return false
        }
        if !isBookCatalogMatch {
            return true
        }
        if hasSpecializedReadingIdentity {
            switch normalizedIncoming {
            case "Manga", "Manhwa", "Manhua", "Novel", "OEL":
                return true
            default:
                return false
            }
        }
        guard let normalizedCurrentType else {
            return true
        }
        if normalizedCurrentType == "Novel", !isBookCatalogMatch {
            return true
        }
        if normalizedCurrentType == "Book" {
            return !isBookCatalogMatch || !hasSpecializedReadingIdentity
        }
        return normalizedCurrentType == "Unknown"
    }

    private func readingTitlePriority(_ provider: SableLibraryMetadataProvider) -> Int {
        switch provider {
        case .ranobedb:
            return 60
        case .mangabaka:
            return 50
        case .anilist, .myAnimeList:
            return 40
        case .openLibrary, .wikidata:
            return 20
        case .local:
            return 10
        case .tvmaze, .tmdb, .tvdb, .imdb:
            return 0
        }
    }

    private func rememberReadingTitleSource(
        provider: SableLibraryMetadataProvider,
        title: String,
        in comicInfo: inout [String: Any],
        service: SableLibraryService
    ) {
        var sable = comicInfo["_sable"] as? [String: Any] ?? [:]
        sable["title_source"] = [
            "provider": provider.rawValue,
            "title": title,
            "priority": readingTitlePriority(provider),
            "updated_at": service.isoTimestamp()
        ]
        comicInfo["_sable"] = sable
    }

    private func shouldUseReadingProviderTitle(
        _ providerTitle: String,
        currentComicInfo: [String: Any],
        isBookCatalogMatch: Bool,
        hasSpecializedReadingIdentity: Bool,
        service: SableLibraryService
    ) -> Bool {
        let localTitle = service.textValue(currentComicInfo["local_title"])
        if let localTitle,
           shouldPreferLocalDisplayTitle(
            localTitle: localTitle,
            over: providerTitle,
            service: service
           ) {
            return false
        }

        if let localTitle,
           shouldKeepLocalSubseriesTitle(
            localTitle: localTitle,
            providerTitle: providerTitle,
            service: service
           ) {
            return false
        }

        guard isBookCatalogMatch,
              !hasSpecializedReadingIdentity,
              let localTitle else {
            return true
        }

        let cleanLocalTitle = service.cleanSeriesTitle(localTitle)
        let cleanProviderTitle = service.cleanSeriesTitle(providerTitle)
        let normalizedLocalTitle = service.normalizeTerm(cleanLocalTitle)
        let normalizedProviderTitle = service.normalizeTerm(cleanProviderTitle)
        guard !normalizedLocalTitle.isEmpty,
              !normalizedProviderTitle.isEmpty,
              normalizedLocalTitle != normalizedProviderTitle else {
            return true
        }

        if normalizedLocalTitle.contains(normalizedProviderTitle)
            || normalizedProviderTitle.contains(normalizedLocalTitle) {
            return true
        }

        return tokenSimilarity(normalizedLocalTitle, normalizedProviderTitle) >= 0.62
    }

    private func shouldKeepLocalSubseriesTitle(
        localTitle: String,
        providerTitle: String,
        service: SableLibraryService
    ) -> Bool {
        let normalizedLocalTitle = service.normalizeTerm(service.cleanSeriesTitle(localTitle))
        let normalizedProviderTitle = service.normalizeTerm(service.cleanSeriesTitle(providerTitle))
        guard !normalizedLocalTitle.isEmpty,
              !normalizedProviderTitle.isEmpty,
              normalizedLocalTitle != normalizedProviderTitle else {
            return false
        }

        if readingProviderTitleLosesLocalSeriesMarker(
            localTitle: localTitle,
            providerTitle: providerTitle,
            service: service
        ) {
            return true
        }

        guard normalizedLocalTitle.contains(normalizedProviderTitle) else {
            return false
        }

        let remainder = normalizedLocalTitle
            .replacingOccurrences(of: normalizedProviderTitle, with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return localTitleHasSubseriesMarker(normalizedLocalTitle)
            || localTitleHasSubseriesMarker(remainder)
    }

    private func localTitleHasSubseriesMarker(_ value: String) -> Bool {
        let patterns = [
            #"\bpart\s*\d+\b"#,
            #"\bpart\s+(one|two|three|four|five|six|seven|eight|nine|ten)\b"#,
            #"\bfan\s*book\b"#,
            #"\bofficial\s+fanbook\b"#,
            #"\bshort\s+stor(y|ies)\b"#,
            #"\bside\s+stor(y|ies)\b"#,
            #"\bspin\s*off\b"#
        ]

        return patterns.contains { pattern in
            value.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private struct ReadingSeriesMarkerSet {
        var partNumbers: Set<Int> = []
        var hasFanbook = false
        var hasShortStories = false
        var hasSideStory = false
        var relationshipMarkers: Set<String> = []

        var isEmpty: Bool {
            partNumbers.isEmpty
                && !hasFanbook
                && !hasShortStories
                && !hasSideStory
                && relationshipMarkers.isEmpty
        }

        func isSubset(of other: ReadingSeriesMarkerSet) -> Bool {
            partNumbers.isSubset(of: other.partNumbers)
                && (!hasFanbook || other.hasFanbook)
                && (!hasShortStories || other.hasShortStories)
                && (!hasSideStory || other.hasSideStory)
                && relationshipMarkers.isSubset(of: other.relationshipMarkers)
        }
    }

    private func readingProviderTitleLosesLocalSeriesMarker(
        localTitle: String,
        providerTitle: String,
        service: SableLibraryService
    ) -> Bool {
        let localMarkers = readingSeriesMarkerSet(in: localTitle, service: service)
        guard !localMarkers.isEmpty else { return false }

        let providerMarkers = readingSeriesMarkerSet(in: providerTitle, service: service)
        if readingProviderTitleHardConflictsWithLocalSeriesMarker(
            localTitle: localTitle,
            providerTitle: providerTitle,
            service: service
        ) {
            return true
        }

        return !localMarkers.isSubset(of: providerMarkers)
    }

    private func readingProviderTitleHardConflictsWithLocalSeriesMarker(
        localTitle: String,
        providerTitle: String,
        service: SableLibraryService
    ) -> Bool {
        let localMarkers = readingSeriesMarkerSet(in: localTitle, service: service)
        let providerMarkers = readingSeriesMarkerSet(in: providerTitle, service: service)

        if !localMarkers.partNumbers.isEmpty, providerMarkers.hasFanbook {
            return true
        }
        if localMarkers.hasFanbook, !providerMarkers.partNumbers.isEmpty {
            return true
        }
        if !localMarkers.relationshipMarkers.isEmpty,
           !providerMarkers.relationshipMarkers.isEmpty,
           !localMarkers.relationshipMarkers.isSubset(of: providerMarkers.relationshipMarkers) {
            return true
        }

        return false
    }

    private func readingSeriesMarkerSet(in title: String, service: SableLibraryService) -> ReadingSeriesMarkerSet {
        let normalizedTitle = service.normalizeTerm(service.cleanSeriesTitle(title))
        var markers = ReadingSeriesMarkerSet()

        if normalizedTitle.range(of: #"\bfan\s*book\b|\bfanbook\b"#, options: .regularExpression) != nil {
            markers.hasFanbook = true
        }
        if normalizedTitle.range(of: #"\bshort\s+stor(y|ies)\b"#, options: .regularExpression) != nil {
            markers.hasShortStories = true
        }
        if normalizedTitle.range(of: #"\bside\s+stor(y|ies)\b"#, options: .regularExpression) != nil {
            markers.hasSideStory = true
        }
        markers.relationshipMarkers = readingRelationshipMarkers(in: title)

        guard let regex = try? NSRegularExpression(pattern: #"\bpart\s*([0-9]+)\b"#) else {
            return markers
        }
        let nsTitle = normalizedTitle as NSString
        let fullRange = NSRange(location: 0, length: nsTitle.length)
        for match in regex.matches(in: normalizedTitle, range: fullRange) where match.numberOfRanges > 1 {
            if let part = Int(nsTitle.substring(with: match.range(at: 1))) {
                markers.partNumbers.insert(part)
            }
        }

        return markers
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

    private func localReadingMediaTypeHint(
        currentComicInfo: [String: Any],
        folder: URL,
        root: URL,
        localFiles: SidecarLocalFileSnapshot,
        service: SableLibraryService
    ) -> String? {
        let namingPolicy = SableLibraryNamingPolicy()
        var candidates: [String] = [
            service.textValue(currentComicInfo["local_title"]),
            service.textValue(currentComicInfo["title"]),
            service.textValue(currentComicInfo["preferred_title"]),
            service.textValue(currentComicInfo["sort_title"]),
            service.textValue(currentComicInfo["native_title"]),
            service.textValue(currentComicInfo["romanized_title"]),
            folder.lastPathComponent
        ].compactMap { $0 }

        candidates.append(contentsOf: currentComicInfo["aliases"] as? [String] ?? [])
        candidates.append(contentsOf: localFiles.bookItems.map { item in
            item.url.deletingPathExtension().lastPathComponent
        })

        for candidate in candidates {
            if let hint = namingPolicy.mediaTypeHint(in: candidate) {
                return hint
            }
        }

        return readingTypeHint(folder: folder, root: root)
    }

    private func ranobeDBFetchMode(from evidence: [SableLibraryMatchEvidence]) -> String {
        if evidence.contains(where: { $0.provider == .ranobedb && $0.kind == .exactProviderID }) {
            return "existing_series_id"
        }

        if evidence.contains(where: { $0.provider == .ranobedb && $0.kind == .titleSimilarity }) {
            return "title_search_then_series_id"
        }

        return "unknown"
    }

    private func ranobeDBEvidenceValues(from evidence: [SableLibraryMatchEvidence]) -> [String] {
        uniqueStrings(
            evidence
                .filter { $0.provider == .ranobedb }
                .map { "\($0.kind.rawValue):\($0.value)" }
        )
    }

    private func mergeSourceIDs(
        _ sourceIDs: [SableLibrarySourceID],
        into sidecar: inout [String: Any],
        service: SableLibraryService
    ) {
        guard !sourceIDs.isEmpty else { return }
        sidecar["ids"] = normalizedIDDictionary(from: sidecar, extraIDs: sourceIDs, service: service)
    }

    private func confirmedProviderSourceIDs(
        in sidecar: [String: Any],
        service: SableLibraryService
    ) -> [SableLibrarySourceID] {
        guard let sable = sidecar["_sable"] as? [String: Any],
              let confirmations = sable["provider_identity_confirmations"] as? [String: Any] else {
            return []
        }

        return uniqueSourceIDs(confirmations.compactMap { rawProvider, value in
            guard let provider = SableLibraryMetadataProvider(rawValue: rawProvider),
                  let row = value as? [String: Any],
                  let identifier = service.textValue(row["id"]) else {
                return nil
            }
            return SableLibrarySourceID(provider: provider, value: identifier)
        })
    }

    private func rememberConfirmedProviderSourceIDs(
        _ sourceIDs: [SableLibrarySourceID],
        in sidecar: inout [String: Any],
        service: SableLibraryService
    ) {
        guard !sourceIDs.isEmpty else { return }
        var sable = sidecar["_sable"] as? [String: Any] ?? [:]
        var confirmations = sable["provider_identity_confirmations"] as? [String: Any] ?? [:]
        var availability = sable["provider_availability"] as? [String: Any] ?? [:]
        var reviews = sable["provider_candidate_review"] as? [String: Any] ?? [:]

        for sourceID in sourceIDs {
            confirmations[sourceID.provider.rawValue] = [
                "id": sourceID.value,
                "source": "manual-provider-match",
                "confirmed_at": service.isoTimestamp()
            ]
            availability.removeValue(forKey: sourceID.provider.rawValue)
            reviews.removeValue(forKey: sourceID.provider.rawValue)
        }

        sable["provider_identity_confirmations"] = confirmations
        if availability.isEmpty {
            sable.removeValue(forKey: "provider_availability")
        } else {
            sable["provider_availability"] = availability
        }
        if reviews.isEmpty {
            sable.removeValue(forKey: "provider_candidate_review")
        } else {
            sable["provider_candidate_review"] = reviews
        }
        sidecar["_sable"] = sable
    }

    private func markComicInfoProviderUntouched(
        _ comicInfo: inout [String: Any],
        provider: SableLibraryMetadataProvider,
        reason: String,
        service: SableLibraryService
    ) {
        var sable = comicInfo["_sable"] as? [String: Any] ?? [:]
        sable[provider.rawValue] = [
            "outcome": SableLibraryQuietOutcome.leaveUntouched.rawValue,
            "reason": reason,
            "updated_at": service.isoTimestamp()
        ]
        comicInfo["_sable"] = sable
    }

    private func rememberMissingProviderGapResultsIfNeeded(
        item: LibraryPlanItem,
        in comicInfo: inout [String: Any],
        service: SableLibraryService
    ) {
        guard item.reviewTags.contains("metadata-manual-provider-gap") else { return }
        let knownProviders = Set(sourceIDs(from: comicInfo, service: service).map(\.provider))
        for provider in uniqueProviders(item.metadataProviders) {
            guard provider != .local,
                  !knownProviders.contains(provider) else {
                continue
            }
            rememberUnavailableMetadataProvider(
                provider,
                in: &comicInfo,
                reason: "Missing-provider pass found no confident \(provider.displayName) result for this sidecar.",
                service: service
            )
        }
    }

    private func rememberUnavailableMetadataProvider(
        _ provider: SableLibraryMetadataProvider,
        in comicInfo: inout [String: Any],
        reason: String,
        service: SableLibraryService
    ) {
        var sable = comicInfo["_sable"] as? [String: Any] ?? [:]
        var availability = sable["provider_availability"] as? [String: Any] ?? [:]
        availability[provider.rawValue] = [
            "status": "not_available",
            "provider": provider.rawValue,
            "source": "provider_gap_no_confident_result",
            "reason": reason,
            "updated_at": service.isoTimestamp()
        ]
        sable["provider_availability"] = availability
        comicInfo["_sable"] = sable
        markComicInfoProviderUntouched(&comicInfo, provider: provider, reason: reason, service: service)
    }

    private func bookSnapshot(folder: URL, root: URL, config: SableLibraryConfig, service: SableLibraryService) -> [String: Any] {
        let items = (try? service.bookItems(in: folder, libraryRoot: root, config: config)) ?? []
        return bookSnapshot(items: items, service: service)
    }

    private func bookSnapshot(items: [LibraryItem], service: SableLibraryService) -> [String: Any] {
        return [
            "version": 1,
            "file_count": items.count,
            "book_signature": service.localFileSnapshotSignature(items: items)
        ]
    }

    private func localAnimeInfo(
        folder: URL,
        root: URL,
        config: SableLibraryConfig,
        existing: [String: Any],
        service: SableLibraryService,
        localFiles: SidecarLocalFileSnapshot,
        extraSourceIDs: [SableLibrarySourceID] = []
    ) -> [String: Any] {
        var animeInfo = existing
        let folderName = folder.lastPathComponent
        let folderYear = yearHint(in: folderName)
        let folderSourceID = sourceIDHint(in: folderName)
        let existingTitle = service.textValue(animeInfo["preferred_title"])
            ?? service.textValue(animeInfo["title"])
        let title = existingTitle.flatMap {
            cleanedWatchingTitle($0, config: config, service: service)
                ?? service.cleanSeriesTitle($0)
        }
            ?? organizerTitle(from: folderName, service: service)
        let mediaType = service.textValue(animeInfo["type"])
            ?? watchingTypeHint(folder: folder, root: root)
            ?? inferredWatchingType(
                folder: folder,
                root: root,
                localFiles: localFiles,
                config: config,
                service: service
            )
            ?? SableLibraryWatchingType.unknownVideo.rawValue
        let ids = normalizedIDDictionary(
            from: animeInfo,
            extraIDs: [folderSourceID].compactMap { $0 } + extraSourceIDs,
            service: service
        )
        let localEpisodeTitles = localEpisodeTitles(in: localFiles.videoItems, config: config, service: service)

        animeInfo["title"] = service.textValue(animeInfo["title"]) ?? title
        animeInfo["local_title"] = service.textValue(animeInfo["local_title"]) ?? title
        animeInfo["preferred_title"] = title
        animeInfo["sort_title"] = service.textValue(animeInfo["sort_title"]) ?? title
        animeInfo["type"] = mediaType
        if animeInfo["year"] == nil,
           let folderYear {
            animeInfo["year"] = folderYear
        }
        let resolvedYear = integerValue(animeInfo["year"]) ?? folderYear
        animeInfo["source"] = service.textValue(animeInfo["source"]) ?? "local"
        animeInfo["last_checked"] = service.isoTimestamp()
        animeInfo["ids"] = ids
        if !localEpisodeTitles.isEmpty {
            let existingEpisodeTitles = combinedStringList(
                from: animeInfo,
                keys: ["episode_titles", "subtitles"],
                service: service
            )
            animeInfo["episode_titles"] = uniqueStrings(existingEpisodeTitles + localEpisodeTitles)
        }
        animeInfo["match_evidence"] = animeInfo["match_evidence"] ?? []
        animeInfo["plex"] = plexHints(
            title: title,
            year: resolvedYear,
            ids: ids,
            mediaType: mediaType
        )
        var sable = animeInfo["_sable"] as? [String: Any] ?? [:]
        sable["snapshot_version"] = 1
        sable["sidecar"] = config.animeInfoFileName
        sable["refreshed_at"] = service.isoTimestamp()
        sable["video_snapshot"] = videoSnapshot(items: localFiles.videoItems, service: service)
        sable["organizer_source"] = organizerSourceSnapshot(
            folderName: folderName,
            cleanTitle: title,
            year: resolvedYear,
            sourceID: folderSourceID
        )
        animeInfo["_sable"] = sable
        return animeInfo
    }

    private func animeInfoPayload(
        item: LibraryPlanItem,
        folder: URL,
        root: URL,
        config: SableLibraryConfig,
        existing: [String: Any],
        service: SableLibraryService,
        localFiles: SidecarLocalFileSnapshot
    ) async throws -> [String: Any] {
        var manualSourceIDs = sourceIDHints(in: folder.lastPathComponent)
        appendUniqueSourceIDs(item.manualSourceIDs, to: &manualSourceIDs)
        var animeInfo = localAnimeInfo(
            folder: folder,
            root: root,
            config: config,
            existing: existing,
            service: service,
            localFiles: localFiles,
            extraSourceIDs: manualSourceIDs
        )
        guard item.usedNetworkData else {
            rememberMissingProviderGapResultsIfNeeded(
                item: item,
                in: &animeInfo,
                service: service
            )
            return animeInfo
        }

        let title = service.textValue(animeInfo["preferred_title"])
            ?? service.textValue(animeInfo["title"])
            ?? service.cleanSeriesTitle(folder.lastPathComponent)

        guard !item.metadataProviders.isEmpty else {
            markAnimeInfoProviderUntouched(&animeInfo, service: service)
            rememberMissingProviderGapResultsIfNeeded(
                item: item,
                in: &animeInfo,
                service: service
            )
            return animeInfo
        }

        if let enrichment = await metadataLookupService.watchingEnrichment(
            title: title,
            sourceIDs: sourceIDs(from: animeInfo, extraIDs: manualSourceIDs, service: service),
            allowTitleSearch: !isExactIDBatchRefresh(item),
            config: config,
            service: service
        ) {
            apply(enrichment: enrichment, to: &animeInfo, service: service)
        } else {
            markAnimeInfoProviderUntouched(&animeInfo, service: service)
        }
        rememberMissingProviderGapResultsIfNeeded(
            item: item,
            in: &animeInfo,
            service: service
        )
        return animeInfo
    }

    private func apply(
        enrichment: SableLibraryMetadataEnrichment,
        to animeInfo: inout [String: Any],
        service: SableLibraryService
    ) {
        animeInfo["title"] = enrichment.preferredTitle
        animeInfo["preferred_title"] = enrichment.preferredTitle
        animeInfo["sort_title"] = animeInfo["sort_title"] ?? enrichment.preferredTitle
        if let year = enrichment.year {
            animeInfo["year"] = year
        }
        if let mediaType = enrichment.mediaType {
            animeInfo["type"] = mediaType
        }

        var ids = normalizedIDDictionary(from: animeInfo, service: service)
        for sourceID in enrichment.sourceIDs {
            ids[idKey(for: sourceID.provider)] = sourceID.value
        }
        animeInfo["ids"] = ids

        let existingAliases = animeInfo["aliases"] as? [String] ?? []
        animeInfo["aliases"] = uniqueStrings(existingAliases + enrichment.aliases)
        let existingEpisodeTitles = combinedStringList(
            from: animeInfo,
            keys: ["episode_titles", "subtitles"],
            service: service
        )
        animeInfo["episode_titles"] = existingEpisodeTitles
        animeInfo["content_warnings"] = uniqueStrings(
            arrayStrings(animeInfo["content_warnings"], service: service) + enrichment.contentWarnings
        )
        if !enrichment.studios.isEmpty {
            animeInfo["studios"] = uniqueStrings(arrayStrings(animeInfo["studios"], service: service) + enrichment.studios)
        }
        if animeInfo["description"] == nil, let description = enrichment.description {
            animeInfo["description"] = description
        }
        animeInfo["genres"] = uniqueStrings(arrayStrings(animeInfo["genres"], service: service) + enrichment.genres)
        animeInfo["tags"] = uniqueStrings(arrayStrings(animeInfo["tags"], service: service) + enrichment.tags)
        animeInfo["authors"] = uniqueStrings(arrayStrings(animeInfo["authors"], service: service) + enrichment.authors)
        animeInfo["artists"] = uniqueStrings(arrayStrings(animeInfo["artists"], service: service) + enrichment.artists)
        animeInfo["publishers"] = uniqueStrings(arrayStrings(animeInfo["publishers"], service: service) + enrichment.publishers)
        animeInfo["languages"] = uniqueStrings(arrayStrings(animeInfo["languages"], service: service) + enrichment.languages)
        if let status = enrichment.status {
            animeInfo["status"] = status
        }
        if let contentRating = enrichment.contentRating {
            animeInfo["content_rating"] = contentRating
        }
        if animeInfo["cover_url"] == nil,
           let coverURL = enrichment.coverURL?.trimmingCharacters(in: .whitespacesAndNewlines),
           !coverURL.isEmpty {
            animeInfo["cover_url"] = coverURL
        }
        animeInfo["match_evidence"] = mergedEvidenceDictionaries(
            existing: animeInfo["match_evidence"] as? [[String: Any]] ?? [],
            refreshed: enrichment.evidence
        )
        animeInfo["source_freshness"] = mergedFreshnessDictionaries(
            existing: animeInfo["source_freshness"] as? [[String: Any]] ?? [],
            refreshed: enrichment.freshness
        )
        animeInfo["source"] = sourceText(
            existing: animeInfo["source"] as? String,
            providers: enrichment.providersUsed
        )
        animeInfo["plex"] = plexHints(
            title: enrichment.preferredTitle,
            year: enrichment.year,
            ids: ids,
            mediaType: enrichment.mediaType ?? animeInfo["type"] as? String ?? SableLibraryWatchingType.unknownVideo.rawValue
        )

        var sable = animeInfo["_sable"] as? [String: Any] ?? [:]
        sable["metadata_enrichment"] = [
            "outcome": SableLibraryQuietOutcome.safeApply.rawValue,
            "confidence_score": roundedScore(enrichment.confidenceScore),
            "providers": enrichment.providersUsed.map(\.rawValue),
            "updated_at": ISO8601DateFormatter().string(from: Date())
        ]
        animeInfo["_sable"] = sable
    }

    private func markAnimeInfoProviderUntouched(_ animeInfo: inout [String: Any], service: SableLibraryService) {
        var sable = animeInfo["_sable"] as? [String: Any] ?? [:]
        sable["metadata_enrichment"] = [
            "outcome": SableLibraryQuietOutcome.leaveUntouched.rawValue,
            "reason": "No provider match met the quiet confidence gate.",
            "updated_at": service.isoTimestamp()
        ]
        animeInfo["_sable"] = sable
    }

    private func evidenceDictionary(_ evidence: SableLibraryMatchEvidence) -> [String: Any] {
        [
            "kind": evidence.kind.rawValue,
            "provider": evidence.provider.rawValue,
            "value": evidence.value,
            "confidence": roundedScore(evidence.confidence)
        ]
    }

    private func evidence(from dictionary: [String: Any], service: SableLibraryService) -> SableLibraryMatchEvidence? {
        guard let kindText = service.textValue(dictionary["kind"]),
              let kind = SableLibraryMatchEvidenceKind(rawValue: kindText),
              let providerText = service.textValue(dictionary["provider"]),
              let provider = SableLibraryMetadataProvider(rawValue: providerText),
              let value = service.textValue(dictionary["value"]) else {
            return nil
        }
        return SableLibraryMatchEvidence(
            kind: kind,
            provider: provider,
            value: value,
            confidence: doubleValue(dictionary["confidence"]) ?? 0
        )
    }

    private func freshnessDictionary(_ freshness: SableLibraryProviderFreshness) -> [String: Any] {
        [
            "provider": freshness.provider.rawValue,
            "fetched_at": freshness.fetchedAt,
            "ttl_seconds": freshness.ttlSeconds
        ]
    }

    private func mergedFreshnessDictionaries(
        existing: [[String: Any]],
        refreshed: [SableLibraryProviderFreshness]
    ) -> [[String: Any]] {
        var byProvider = existing.reduce(into: [String: [String: Any]]()) { partialResult, item in
            guard let provider = stringValue(item["provider"]) else { return }
            partialResult[provider] = item
        }
        for freshness in refreshed {
            byProvider[freshness.provider.rawValue] = freshnessDictionary(freshness)
        }
        return byProvider.keys.sorted().compactMap { byProvider[$0] }
    }

    private func mergedEvidenceDictionaries(
        existing: [[String: Any]],
        refreshed: [SableLibraryMatchEvidence]
    ) -> [[String: Any]] {
        var byKey = existing.reduce(into: [String: [String: Any]]()) { partialResult, item in
            guard let kind = stringValue(item["kind"]),
                  let provider = stringValue(item["provider"]),
                  let value = stringValue(item["value"]) else {
                return
            }
            partialResult["\(kind)|\(provider)|\(value)"] = item
        }
        for evidence in refreshed {
            let item = evidenceDictionary(evidence)
            let key = "\(evidence.kind.rawValue)|\(evidence.provider.rawValue)|\(evidence.value)"
            if let existing = byKey[key],
               let existingScore = doubleValue(existing["confidence"]),
               existingScore >= evidence.confidence {
                continue
            }
            byKey[key] = item
        }
        return byKey.keys.sorted().compactMap { byKey[$0] }
    }

    private func idKey(for provider: SableLibraryMetadataProvider) -> String {
        switch provider {
        case .mangabaka: "mangabaka"
        case .ranobedb: "ranobedb"
        case .openLibrary: "openlibrary"
        case .myAnimeList: "mal"
        case .anilist: "anilist"
        case .tvmaze: "tvmaze"
        case .wikidata: "wikidata"
        case .tmdb: "tmdb"
        case .tvdb: "tvdb"
        case .imdb: "imdb"
        case .local: "local"
        }
    }

    private func sourcePrefix(for provider: SableLibraryMetadataProvider) -> String {
        switch provider {
        case .mangabaka: "mb"
        case .ranobedb: "rdb"
        case .openLibrary: "ol"
        case .myAnimeList: "mal"
        case .anilist: "al"
        case .tvmaze: "tvmaze"
        case .wikidata: "wd"
        case .tmdb: "tmdb"
        case .tvdb: "tvdb"
        case .imdb: "imdb"
        case .local: "local"
        }
    }

    private func watchingSourceID(from ids: [String: Any], mediaType: String? = nil) -> SableLibrarySourceID? {
        let providerKeys: [(SableLibraryMetadataProvider, [String])]
        if mediaType.map(isMovieMediaType) == true {
            providerKeys = [
                (.tmdb, ["tmdb"]),
                (.imdb, ["imdb"])
            ]
        } else {
            providerKeys = [
                (.tmdb, ["tmdb"]),
                (.tvdb, ["tvdb"]),
                (.imdb, ["imdb"])
            ]
        }
        return providerKeys.lazy
            .compactMap { provider, keys in
                keys.compactMap { key in
                    stringValue(ids[key]).map { SableLibrarySourceID(provider: provider, value: $0) }
                }.first
            }
            .first
    }

    private func isMovieMediaType(_ mediaType: String) -> Bool {
        switch mediaType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "movie", "animemovie", "anime movie":
            true
        default:
            false
        }
    }

    private func readingSourceID(from ids: [String: Any]) -> SableLibrarySourceID? {
        [
            (.ranobedb, ["ranobedb", "rdb"]),
            (.mangabaka, ["mangabaka", "mb"]),
            (.myAnimeList, ["mal", "myanimelist", "my_anime_list"]),
            (.anilist, ["anilist", "al"]),
            (.openLibrary, ["openlibrary", "open_library", "ol"])
        ]
        .lazy
        .compactMap { provider, keys in
            keys.compactMap { key in
                stringValue(ids[key]).map { SableLibrarySourceID(provider: provider, value: $0) }
            }.first
        }
        .first
    }

    private func sourceIDHints(in folderName: String) -> [SableLibrarySourceID] {
        SableLibrarySourceIDParser.folderHints(in: folderName)
    }

    private func exactRefreshSourceIDs(for series: LibrarySeriesSnapshot) -> [SableLibrarySourceID] {
        var ids = series.identityGraph?.sourceIDs ?? []
        if let primarySourceID = series.primarySourceID {
            appendUniqueSourceID(primarySourceID, to: &ids)
        }
        appendUniqueSourceIDs(sourceIDHints(in: URL(fileURLWithPath: series.path).lastPathComponent), to: &ids)
        return ids
    }

    private func exactRefreshSourceIDs(for series: LibraryVideoSeriesSnapshot) -> [SableLibrarySourceID] {
        var ids = series.identityGraph?.sourceIDs ?? []
        if let primarySourceID = series.primarySourceID {
            appendUniqueSourceID(primarySourceID, to: &ids)
        }
        appendUniqueSourceIDs(sourceIDHints(in: URL(fileURLWithPath: series.path).lastPathComponent), to: &ids)
        return ids
    }

    private func appendUniqueSourceIDs(_ sourceIDs: [SableLibrarySourceID], to ids: inout [SableLibrarySourceID]) {
        for sourceID in sourceIDs {
            appendUniqueSourceID(sourceID, to: &ids)
        }
    }

    private func uniqueSourceIDs(_ sourceIDs: [SableLibrarySourceID]) -> [SableLibrarySourceID] {
        var ids: [SableLibrarySourceID] = []
        appendUniqueSourceIDs(sourceIDs, to: &ids)
        return ids
    }

    private func appendUniqueSourceID(_ sourceID: SableLibrarySourceID, to ids: inout [SableLibrarySourceID]) {
        guard !sourceID.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !ids.contains(where: { $0.provider == sourceID.provider && $0.value == sourceID.value }) else {
            return
        }
        ids.append(sourceID)
    }

    private func sourceIDHint(in folderName: String) -> SableLibrarySourceID? {
        sourceIDHints(in: folderName).first
    }

    private func watchingTypeHint(folder: URL, root: URL) -> String? {
        let relativePath = folder.standardizedFileURL
            .path(percentEncoded: false)
            .replacingOccurrences(of: root.standardizedFileURL.path(percentEncoded: false), with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let firstComponent = relativePath.split(separator: "/").first else { return nil }
        return switch String(firstComponent).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "anime tv": SableLibraryWatchingType.animeTV.rawValue
        case "anime movies": SableLibraryWatchingType.animeMovie.rawValue
        case "movies": SableLibraryWatchingType.movie.rawValue
        case "tv", "tv shows": SableLibraryWatchingType.tvShow.rawValue
        default: nil
        }
    }

    private func inferredWatchingType(
        folder: URL,
        root: URL,
        localFiles: SidecarLocalFileSnapshot,
        config: SableLibraryConfig,
        service: SableLibraryService
    ) -> String? {
        let relativePath = folder.standardizedFileURL
            .path(percentEncoded: false)
            .replacingOccurrences(of: root.standardizedFileURL.path(percentEncoded: false), with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let rootName = relativePath.split(separator: "/").first.map(String.init) ?? ""
        guard service.normalizeTerm(rootName) == "videos" else {
            return nil
        }

        let folderTitle = organizerTitle(from: folder.lastPathComponent, service: service)
        let hasEpisodeNumber = localFiles.videoItems.contains { item in
            localVideoHasEpisodeNumber(
                item.url.deletingPathExtension().lastPathComponent,
                folderTitle: folderTitle,
                config: config,
                service: service
            )
        }
        return hasEpisodeNumber ? SableLibraryWatchingType.tvShow.rawValue : nil
    }

    private func localVideoHasEpisodeNumber(
        _ rawName: String,
        folderTitle: String,
        config: SableLibraryConfig,
        service: SableLibraryService
    ) -> Bool {
        let cleaned = service.cleanedTitle(rawName, config: config)
        if cleaned.range(
            of: #"(?i)\bS(?:eason)?\s*0*\d{1,2}\s*E(?:p(?:isode)?)?\.?\s*0*\d{1,3}\b"#,
            options: .regularExpression
        ) != nil {
            return true
        }

        let titleKey = service.normalizeTerm(folderTitle)
        let cleanedKey = service.normalizeTerm(cleaned)
        guard !titleKey.isEmpty,
              cleanedKey == titleKey || cleanedKey.hasPrefix(titleKey + " ") else {
            return false
        }

        let suffix = String(cleaned.dropFirst(min(cleaned.count, folderTitle.count)))
        let normalizedSuffix = suffix
            .replacingOccurrences(of: #"^[\s._\-–—:]+|[\s._\-–—:]+$"#, with: "", options: .regularExpression)
        return normalizedSuffix.range(of: #"^\d{1,3}(?:\s*[-–—:]\s*.+)?$"#, options: .regularExpression) != nil
    }

    private func readingTypeHint(folder: URL, root: URL) -> String? {
        let relativePath = folder.standardizedFileURL
            .path(percentEncoded: false)
            .replacingOccurrences(of: root.standardizedFileURL.path(percentEncoded: false), with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let firstComponent = relativePath.split(separator: "/").first else { return nil }
        return switch String(firstComponent).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "manga": SableLibraryReadingType.manga.rawValue
        case "manhwa": SableLibraryReadingType.manhwa.rawValue
        case "manhua": SableLibraryReadingType.manhua.rawValue
        case "light novels", "novels": SableLibraryReadingType.lightNovel.rawValue
        case "oel": SableLibraryReadingType.oel.rawValue
        case "books": SableLibraryReadingType.book.rawValue
        default: nil
        }
    }

    private func plexLibraryKind(for mediaType: String) -> String {
        switch mediaType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "movie", "animemovie", "anime movie":
            "movie"
        case "animetv", "anime tv", "tvshow", "tv show", "tv", "ova", "ona", "special", "specials":
            "tv"
        default:
            "video"
        }
    }

    private func integerValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber {
            return number.intValue
        }
        guard let string = stringValue(value) else { return nil }
        return Int(string)
    }

    private func boolValue(_ value: Any?) -> Bool? {
        if let bool = value as? Bool {
            return bool
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        guard let string = stringValue(value)?.lowercased() else { return nil }
        switch string {
        case "true", "yes", "1":
            return true
        case "false", "no", "0":
            return false
        default:
            return nil
        }
    }

    private func doubleValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let double = value as? Double {
            return double
        }
        guard let string = stringValue(value) else { return nil }
        return Double(string)
    }

    private func stringValue(_ value: Any?) -> String? {
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

    private func organizerTitle(from folderName: String, service: SableLibraryService) -> String {
        var title = folderName
            .replacingOccurrences(of: #"\s*\{[A-Za-z_]+-[^}]+\}\s*"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s*\(\d{4}\)\s*$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty {
            title = folderName
        }
        return service.cleanSeriesTitle(title)
    }

    private func organizerSourceSnapshot(
        folderName: String,
        cleanTitle: String,
        year: Int?,
        sourceID: SableLibrarySourceID?
    ) -> [String: Any] {
        var snapshot: [String: Any] = [
            "folder_name": folderName,
            "clean_title": cleanTitle,
            "title_with_year": titleWithYear(cleanTitle, year: year),
            "year_preserved": year != nil
        ]
        if let year {
            snapshot["year"] = year
        }
        if let sourceID {
            snapshot["source_id"] = sourceIDDictionary(sourceID)
        }
        return snapshot
    }

    private func yearHint(in folderName: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: #"\((\d{4})\)\s*(?:\{[^}]+\})?\s*$"#),
              let match = regex.firstMatch(in: folderName, range: NSRange(folderName.startIndex..<folderName.endIndex, in: folderName)),
              let range = Range(match.range(at: 1), in: folderName) else {
            return nil
        }
        return Int(folderName[range])
    }

    private func titleWithYear(_ title: String, year: Int?) -> String {
        let namingPolicy = SableLibraryNamingPolicy()
        let safeTitle = namingPolicy.safePreferredTitle(title)
        guard let year else { return safeTitle }
        return "\(safeTitle) (\(year))"
    }

    private func sourceIDDictionary(_ sourceID: SableLibrarySourceID) -> [String: Any] {
        [
            "provider": sourceID.provider.rawValue,
            "value": sourceID.value,
            "folder_token": "{\(sourcePrefix(for: sourceID.provider))-\(sourceID.value)}"
        ]
    }

    private func sourceIDs(from sidecar: [String: Any], service: SableLibraryService) -> [SableLibrarySourceID] {
        SableLibrarySourceIDParser.sourceIDs(from: sidecar) { service.textValue($0) }
    }

    private func normalizedIDDictionary(
        from sidecar: [String: Any],
        extraIDs: [SableLibrarySourceID] = [],
        service: SableLibraryService
    ) -> [String: Any] {
        var ids: [String: Any] = [:]
        for sourceID in sourceIDs(from: sidecar, extraIDs: extraIDs, service: service) {
            ids[idKey(for: sourceID.provider)] = sourceID.value
        }
        return ids
    }

    private func sourceIDs(
        from sidecar: [String: Any],
        extraIDs: [SableLibrarySourceID],
        service: SableLibraryService
    ) -> [SableLibrarySourceID] {
        SableLibrarySourceIDParser.sourceIDs(from: sidecar, extraIDs: extraIDs) { service.textValue($0) }
    }

    private func sidecarLocalFileSnapshot(
        folder: URL,
        root: URL,
        config: SableLibraryConfig,
        service: SableLibraryService,
        includeBooks: Bool = false,
        includeVideos: Bool = false
    ) -> SidecarLocalFileSnapshot {
        let folderPath = service.relativePath(for: folder, root: root)
        let nestedPrefix = folderPath.isEmpty ? "" : "\(folderPath)/"
        let bookItems: [LibraryItem]
        let videoItems: [LibraryItem]

        if includeBooks {
            bookItems = ((try? service.bookItems(root: root, config: config)) ?? []).filter { item in
                folderPath.isEmpty || item.relativePath.hasPrefix(nestedPrefix)
            }
        } else {
            bookItems = []
        }

        if includeVideos {
            videoItems = ((try? service.videoItems(root: root, config: config)) ?? []).filter { item in
                folderPath.isEmpty || item.relativePath == folderPath || item.relativePath.hasPrefix(nestedPrefix)
            }
        } else {
            videoItems = []
        }

        return SidecarLocalFileSnapshot(bookItems: bookItems, videoItems: videoItems)
    }

    private func localVolumeNumbers(folder: URL, root: URL, config: SableLibraryConfig, service: SableLibraryService) -> [Int] {
        let items = (try? service.bookItems(in: folder, libraryRoot: root, config: config)) ?? []
        return localVolumeNumbers(in: items, config: config, service: service)
    }

    private func localVolumeNumbers(in items: [LibraryItem], config: SableLibraryConfig, service: SableLibraryService) -> [Int] {
        let numbers = items.compactMap { item -> Int? in
            let rawName = item.url.deletingPathExtension().lastPathComponent
            let cleaned = service.cleanedTitle(rawName, config: config)
            guard let suffix = service.volumeOrChapterSuffix(in: cleaned) else { return nil }
            return service.volumeNumber(in: suffix)
        }
        return Array(Set(numbers)).sorted()
    }

    private func localReadingPartTitles(folder: URL, root: URL, config: SableLibraryConfig, service: SableLibraryService) -> [String] {
        let items = (try? service.bookItems(in: folder, libraryRoot: root, config: config)) ?? []
        return localReadingPartTitles(in: items, config: config, service: service)
    }

    private func localReadingPartTitles(in items: [LibraryItem], config: SableLibraryConfig, service: SableLibraryService) -> [String] {
        let titles = items.compactMap { item -> String? in
            let rawName = item.url.deletingPathExtension().lastPathComponent
            let cleaned = service.cleanedTitle(rawName, config: config)
            guard let suffix = service.volumeOrChapterSuffix(in: cleaned) else { return nil }
            return localReadingPartTitle(from: suffix, service: service)
        }
        return uniqueStrings(titles)
    }

    private func localReadingPartTitle(from suffix: String, service: SableLibraryService) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?i)^(?:(?:vol(?:ume)?|v|ch(?:apter)?)\.?\s+\d{1,4})(?:\s*[-–—]\s*\d{1,4})?\s*[-–—:]\s*(.+?)\s*$"#
        ),
              let match = regex.firstMatch(in: suffix, range: NSRange(suffix.startIndex..<suffix.endIndex, in: suffix)),
              let titleRange = Range(match.range(at: 1), in: suffix) else {
            return nil
        }

        let title = String(suffix[titleRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        return service.textValue(title)
    }

    private func localEpisodeTitles(folder: URL, root: URL, config: SableLibraryConfig, service: SableLibraryService) -> [String] {
        let folderPath = service.relativePath(for: folder, root: root)
        let items = (try? service.videoItems(root: root, config: config).filter { item in
            item.relativePath == folderPath || item.relativePath.hasPrefix("\(folderPath)/")
        }) ?? []
        return localEpisodeTitles(in: items, config: config, service: service)
    }

    private func localEpisodeTitles(in items: [LibraryItem], config: SableLibraryConfig, service: SableLibraryService) -> [String] {
        let titles = items.compactMap { item -> String? in
            let rawName = item.url.deletingPathExtension().lastPathComponent
            return localEpisodeTitle(in: rawName, config: config, service: service)
        }
        return uniqueStrings(titles)
    }

    private func localEpisodeTitle(in rawName: String, config: SableLibraryConfig, service: SableLibraryService) -> String? {
        let cleaned = service.cleanedTitle(rawName, config: config)
        guard !cleaned.isEmpty else { return nil }
        let pattern = #"(?i)\bS(?:eason)?\s*0*(\d{1,2})\s*E(?:p(?:isode)?)?\.?\s*0*(\d{1,3})\b(.*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)),
              match.numberOfRanges > 3,
              let tailRange = Range(match.range(at: 3), in: cleaned) else {
            return nil
        }

        let tail = String(cleaned[tailRange])
            .replacingOccurrences(of: #"^[\s._\-–—:]+|[\s._\-–—:]+$"#, with: "", options: .regularExpression)
        guard !tail.isEmpty else { return nil }

        let blocked = Set([
            "1080p",
            "720p",
            "2160p",
            "480p",
            "x264",
            "x265",
            "hevc",
            "aac",
            "bluray",
            "web",
            "dl",
            "webrip",
            "h264",
            "h265"
        ])
        let terms = service.normalizeTerm(tail)
            .split(separator: " ")
            .map(String.init)
        guard !terms.isEmpty, !terms.allSatisfy({ blocked.contains($0) }) else {
            return nil
        }
        return tail
    }

    private func arrayStrings(_ value: Any?, service: SableLibraryService) -> [String] {
        if let values = value as? [String] {
            return values
        }
        if let value = service.textValue(value) {
            return [value]
        }
        return []
    }

    private func mergedReadingParts(
        existing: [[String: Any]],
        enriched: [SableLibraryReadingPartMetadata],
        service: SableLibraryService
    ) -> [[String: Any]] {
        var merged = existing
        for part in enriched {
            let incoming = readingPartDictionary(part)
            let sourceKey = readingPartSourceKey(incoming, service: service)
            let index = merged.firstIndex { current in
                if let sourceKey {
                    return readingPartSourceKey(current, service: service) == sourceKey
                }
                return integerValue(current["number"]) == part.number
            }
            if let index {
                var preserved = merged[index]
                for (key, value) in incoming {
                    preserved[key] = value
                }
                merged[index] = preserved
            } else {
                merged.append(incoming)
            }
        }
        return merged.sorted {
            let lhsNumber = integerValue($0["number"]) ?? Int.max
            let rhsNumber = integerValue($1["number"]) ?? Int.max
            if lhsNumber != rhsNumber { return lhsNumber < rhsNumber }
            return (readingPartSourceKey($0, service: service) ?? "")
                < (readingPartSourceKey($1, service: service) ?? "")
        }
    }

    private func readingPartSourceKey(
        _ part: [String: Any],
        service: SableLibraryService
    ) -> String? {
        guard let sourceID = part["source_id"] as? [String: Any],
              let provider = service.textValue(sourceID["provider"])?.lowercased(),
              let value = service.textValue(sourceID["value"])
                ?? service.textValue(sourceID["id"]) else {
            return nil
        }
        return "\(provider):\(value)"
    }

    private func mergedRanobeDBAPIPayload(
        existingMetadata: [String: Any],
        incomingPayload: [String: Any]?,
        service: SableLibraryService
    ) -> [String: Any]? {
        let existingPayload = existingMetadata["api"] as? [String: Any]
            ?? existingMetadata["api_compact"] as? [String: Any]
        guard existingPayload != nil || incomingPayload != nil else { return nil }

        var result = existingPayload ?? [:]
        for (key, value) in incomingPayload ?? [:] where key != "book_responses" {
            result[key] = value
        }

        let existingRows = existingPayload?["book_responses"] as? [[String: Any]] ?? []
        let incomingRows = incomingPayload?["book_responses"] as? [[String: Any]] ?? []
        var keys: [String] = []
        var rowsByKey: [String: [String: Any]] = [:]
        for (index, row) in (existingRows + incomingRows).enumerated() {
            let key = ranobeDBBookResponseKey(row, service: service) ?? "row:\(index)"
            if rowsByKey[key] == nil {
                keys.append(key)
            }
            rowsByKey[key] = row
        }
        let mergedRows = keys.compactMap { rowsByKey[$0] }
        if mergedRows.isEmpty {
            result.removeValue(forKey: "book_responses")
            result.removeValue(forKey: "book_response_count")
        } else {
            result["book_responses"] = mergedRows
            result["book_response_count"] = mergedRows.count
            result["book_endpoint"] = "GET /book/[id]"
        }
        return result
    }

    private func ranobeDBBookResponseKey(
        _ row: [String: Any],
        service: SableLibraryService
    ) -> String? {
        let response = row["response"] as? [String: Any] ?? row
        let book = response["book"] as? [String: Any] ?? response
        if let bookID = service.textValue(book["id"]) {
            return "book:\(bookID)"
        }
        if let volume = integerValue(row["volume_number"]) ?? integerValue(book["sort_order"]) {
            return "volume:\(volume)"
        }
        return nil
    }

    private func readingPartDictionary(_ part: SableLibraryReadingPartMetadata) -> [String: Any] {
        var item: [String: Any] = [
            "number": part.number,
            "title": part.title,
            "file_suffix": part.fileSuffix
        ]
        if let sourceID = part.sourceID {
            item["source_id"] = sourceIDDictionary(sourceID)
        }
        if let subtitle = part.subtitle {
            item["subtitle"] = subtitle
        }
        if let releaseYear = part.releaseYear {
            item["release_year"] = releaseYear
        }
        if let releaseDate = part.releaseDate {
            item["release_date"] = releaseDate
        }
        if !part.isbn13.isEmpty {
            item["isbn13"] = part.isbn13
        }
        if !part.releaseIDs.isEmpty {
            item["release_ids"] = part.releaseIDs
        }
        if let pages = part.pages {
            item["pages"] = pages
        }
        if let description = part.description?.trimmingCharacters(in: .whitespacesAndNewlines),
           !description.isEmpty {
            item["description"] = description
        }
        return item
    }

    private func sourceText(existing: String?, providers: [SableLibraryMetadataProvider]) -> String {
        let existingSources = existing?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? []
        return uniqueStrings(existingSources + providers.map(\.rawValue)).joined(separator: ", ")
    }

    private func uniqueStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let key = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            return seen.insert(key).inserted ? trimmed : nil
        }
    }

    private func uniqueProviders(_ providers: [SableLibraryMetadataProvider]) -> [SableLibraryMetadataProvider] {
        var seen = Set<SableLibraryMetadataProvider>()
        return providers.filter { provider in
            seen.insert(provider).inserted
        }
    }

    private func videoSnapshot(folder: URL, root: URL, config: SableLibraryConfig, service: SableLibraryService) -> [String: Any] {
        let folderPath = service.relativePath(for: folder, root: root)
        let items = (try? service.videoItems(root: root, config: config).filter { item in
            item.relativePath.hasPrefix(folderPath + "/")
        }) ?? []
        return videoSnapshot(items: items, service: service)
    }

    private func videoSnapshot(items: [LibraryItem], service: SableLibraryService) -> [String: Any] {
        return [
            "version": 1,
            "file_count": items.count,
            "video_signature": service.localFileSnapshotSignature(items: items)
        ]
    }

    private func plexHints(title: String, year: Int?, ids: [String: Any], mediaType: String) -> [String: Any] {
        let namingPolicy = SableLibraryNamingPolicy()
        let safeTitle = namingPolicy.safePreferredTitle(title)
        let baseTitle = titleWithYear(title, year: year)
        let sourceID = watchingSourceID(from: ids, mediaType: mediaType)
        let rootFolder = namingPolicy.watchingRootFolder(for: mediaType)
        let seriesFolderName = namingPolicy.canonicalWatchingFolderName(preferredTitle: title, year: year, sourceID: sourceID)
        let seriesPath = "\(rootFolder)/\(seriesFolderName)"
        let isMovie = isMovieMediaType(mediaType)
        let movieFilePattern = namingPolicy.canonicalWatchingMovieFileName(
            preferredTitle: title,
            year: year,
            sourceID: sourceID,
            fileExtension: "ext"
        )
        let episodePattern = "\(baseTitle) - S01E01 - Episode Title.ext"
        let specialPattern = "\(baseTitle) - S00E01 - Special Title.ext"
        var hints: [String: Any] = [
            "library_kind": plexLibraryKind(for: mediaType),
            "title": safeTitle,
            "title_with_year": baseTitle,
            "root_folder": rootFolder,
            "series_folder_name": seriesFolderName,
            "series_path": seriesPath,
            "season_folder": "Season 01",
            "specials_folder": "Season 00",
            "organizer_targets": [
                "folder": seriesPath,
                "movie_file": "\(seriesPath)/\(movieFilePattern)",
                "episode_file": "\(seriesPath)/Season 01/\(episodePattern)",
                "special_file": "\(seriesPath)/Season 00/\(specialPattern)"
            ],
            "naming": [
                "folder_template": isMovie ? "Title (Year) {tmdb/imdb-id when known}" : "Title (Year) {tmdb/tvdb/imdb-id when known}",
                "source_id_required": false,
                "source_id_note": isMovie
                    ? "Plex IDs improve matching but are optional. Movie names use TMDB or IMDb IDs when already known."
                    : "Plex IDs improve matching but are optional. TV-style folder names and .plexmatch use TMDB, TVDB, or IMDb IDs when already known.",
                "movie_template": sourceID == nil ? "Title (Year).ext" : "Title (Year) {tmdb/imdb-id}.ext",
                "episode_template": "Title (Year) - SXXEXX - Episode Title.ext",
                "specials_season": "Season 00"
            ]
        ]
        if shouldWritePlexMatchFile(for: mediaType) {
            hints["plex_match_file"] = ".plexmatch"
        }
        if let year {
            hints["year"] = year
        }
        if let sourceID {
            hints["source_id"] = sourceIDDictionary(sourceID)
        }
        return hints
    }

    private func readingOrganizerHints(title: String, year: Int?, ids: [String: Any], mediaType: String) -> [String: Any] {
        let namingPolicy = SableLibraryNamingPolicy()
        let safeTitle = namingPolicy.safePreferredTitle(title)
        let baseTitle = titleWithYear(title, year: year)
        let sourceID = readingSourceID(from: ids)
        let rootFolder = namingPolicy.readingRootFolder(for: mediaType)
        let seriesFolderName = namingPolicy.canonicalReadingFolderName(
            preferredTitle: title,
            year: year,
            sourceID: sourceID,
            mediaType: mediaType
        )
        let seriesPath = "\(rootFolder)/\(seriesFolderName)"
        let volumePattern = "\(baseTitle) - Vol 01.ext"
        let volumeTitlePattern = "\(baseTitle) - Vol 01 - Volume Title.ext"
        let chapterPattern = "\(baseTitle) - Ch 0001.ext"
        let chapterRangePattern = "\(baseTitle) - Ch 0001-0005.ext"
        let chapterTitlePattern = "\(baseTitle) - Ch 0001 - Chapter Title.ext"
        var hints: [String: Any] = [
            "library_kind": "reading",
            "title": safeTitle,
            "title_with_year": baseTitle,
            "root_folder": rootFolder,
            "series_folder_name": seriesFolderName,
            "series_path": seriesPath,
            "organizer_targets": [
                "folder": seriesPath,
                "volume_file": "\(seriesPath)/\(volumePattern)",
                "volume_title_file": "\(seriesPath)/\(volumeTitlePattern)",
                "chapter_file": "\(seriesPath)/\(chapterPattern)",
                "chapter_range_file": "\(seriesPath)/\(chapterRangePattern)",
                "chapter_title_file": "\(seriesPath)/\(chapterTitlePattern)"
            ],
            "naming": [
                "folder_template": "Title (Year) {source-id}",
                "volume_template": "Title (Year) - Vol 01.ext",
                "volume_title_template": "Title (Year) - Vol 01 - Volume Title.ext",
                "chapter_template": "Title (Year) - Ch 0001.ext",
                "chapter_range_template": "Title (Year) - Ch 0001-0005.ext",
                "chapter_title_template": "Title (Year) - Ch 0001 - Chapter Title.ext"
            ]
        ]
        if let year {
            hints["year"] = year
        }
        if let sourceID {
            hints["source_id"] = sourceIDDictionary(sourceID)
        }
        return hints
    }

    private func mangaBakaQueryPlan(
        primaryTitle: String,
        extraTitles: [String] = [],
        config: SableLibraryConfig,
        service: SableLibraryService,
        localFiles: SidecarLocalFileSnapshot
    ) -> MangaBakaQueryPlan {
        let namingPolicy = SableLibraryNamingPolicy()
        var queries: [String] = []
        var mediaTypeHint = namingPolicy.mediaTypeHint(in: primaryTitle)
        for queryTitle in preferredMangaBakaSearchTitles(from: primaryTitle, service: service) {
            addMangaBakaQuery(queryTitle, to: &queries, service: service)
        }
        for title in extraTitles {
            let cleanTitle = service.cleanSeriesTitle(title)
            for queryTitle in preferredMangaBakaSearchTitles(from: cleanTitle, service: service) {
                addMangaBakaQuery(queryTitle, to: &queries, service: service)
            }
        }

        let items = localFiles.bookItems
        let localHighestVolume = localHighestVolume(in: items, config: config, service: service)
        let localMediaTypeHint = localMediaTypeHint(in: items)
        for item in items.prefix(5) {
            let fileTitle = item.url.deletingPathExtension().lastPathComponent
            let cleanTitle = service.cleanSeriesTitle(fileTitle)
            if mediaTypeHint == nil {
                mediaTypeHint = namingPolicy.mediaTypeHint(in: cleanTitle)
            }
            for queryTitle in preferredMangaBakaSearchTitles(from: cleanTitle, service: service) {
                addMangaBakaQuery(queryTitle, to: &queries, service: service)
            }
        }

        let normalizedPreferredType = namingPolicy.normalizedMediaType(config.mangaBaka.preferredType)
        let preferredTypeHint = normalizedPreferredType == "Unknown" ? nil : normalizedPreferredType
        let fallbackTitle = mangaBakaCatalogSearchTitle(from: primaryTitle, service: service)
            ?? service.cleanSeriesTitle(primaryTitle)
        let rawTitles = queries.isEmpty ? [fallbackTitle] : queries
        let maxQueryCount = mediaTypeHint == nil && localMediaTypeHint == nil ? 4 : 6
        return MangaBakaQueryPlan(
            titles: Array(rawTitles.prefix(maxQueryCount)),
            mediaTypeHint: mediaTypeHint ?? localMediaTypeHint,
            usesPreferredTypeFallback: mediaTypeHint == nil && localMediaTypeHint == nil && preferredTypeHint != nil,
            localMediaTypeHint: localMediaTypeHint,
            localBookCount: items.count,
            localHighestVolume: localHighestVolume
        )
    }

    private func localHighestVolume(
        in items: [LibraryItem],
        config: SableLibraryConfig,
        service: SableLibraryService
    ) -> Int? {
        items.compactMap { item in
            let rawName = item.url.deletingPathExtension().lastPathComponent
            let cleaned = service.cleanedTitle(rawName, config: config)
            guard let suffix = service.volumeOrChapterSuffix(in: cleaned) else { return nil }
            return service.volumeNumber(in: suffix)
        }.max()
    }

    private func localMediaTypeHint(in items: [LibraryItem]) -> String? {
        let namingPolicy = SableLibraryNamingPolicy()

        // 1. Explicit local naming wins.
        // Examples: "37°C - Thirty Seven Degrees Celsius (Novel)", "Series - Manga".
        for item in items.prefix(8) {
            let rawName = item.url.deletingPathExtension().lastPathComponent
            if let hint = namingPolicy.mediaTypeHint(in: rawName) {
                return hint
            }
        }

        let extensions = Set(items.map { $0.url.pathExtension.lowercased() }.filter { !$0.isEmpty })
        guard !extensions.isEmpty else { return nil }

        let comicFormats: Set<String> = ["cbz", "cbr", "cb7"]
        let ebookFormats: Set<String> = ["epub", "kepub", "mobi", "azw", "azw3", "ibooks", "iba"]

        // 2. Dedicated comic archive formats are strong local manga/comic evidence.
        if !extensions.isDisjoint(with: comicFormats),
           extensions.isDisjoint(with: ebookFormats) {
            return "Manga"
        }

        // 3. EPUB is not automatically Novel anymore.
        // EPUB can be a text novel, scanned-page novel, manga, manhwa, or image-page comic.
        // Use a small content sample only to detect obvious prose or explicit OPF title hints.
        for item in items.prefix(4) {
            guard ["epub", "kepub"].contains(item.url.pathExtension.lowercased()) else { continue }
            if let hint = epubMediaTypeHint(in: item.url) {
                return hint
            }
        }

        // 4. Mixed or image-page EPUB evidence should go to provider/manual review,
        // not silently become Manga or Novel.
        return nil
    }

    private func epubMediaTypeHint(in epubURL: URL) -> String? {
        let namingPolicy = SableLibraryNamingPolicy()

        guard let archive = try? SableLibraryAppleBooksCompatibilityRepairer.archiveSnapshot(for: epubURL) else {
            return nil
        }
        let entries = archive.entries

        // OPF title/type hint first. This catches scanned-page novels whose visible content is image-only.
        if let opfPath = try? SableLibraryAppleBooksCompatibilityRepairer.opfPath(in: archive),
           let opfText = try? SableLibraryAppleBooksCompatibilityRepairer.entryText(opfPath, in: archive) {
            let titleHints = epubTitleLikeStrings(fromOPF: opfText)
            for value in titleHints {
                if let hint = namingPolicy.mediaTypeHint(in: value) {
                    return hint
                }
            }
        }

        let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "gif", "svg", "avif"]
        let textExtensions: Set<String> = ["xhtml", "html", "htm"]
        let imageCount = entries.filter { imageExtensions.contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) }.count
        let textEntries = entries
            .filter { textExtensions.contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) }
            .filter { !epubEntryLooksLikeNavigationOrCover($0) }
            .prefix(6)

        var sampledWords = 0
        var sampledFiles = 0

        for entry in textEntries {
            guard sampledWords < 12_000 else { break }
            guard let raw = try? SableLibraryAppleBooksCompatibilityRepairer.entryText(entry, in: archive) else { continue }
            sampledWords += visibleWordCount(inHTML: raw)
            sampledFiles += 1
        }

        if sampledWords >= 12_000 && sampledFiles >= 2 {
            return "Novel"
        }

        if sampledWords >= 5_000 && imageCount < 80 {
            return "Novel"
        }

        // Important: image-heavy EPUB is not automatically Manga.
        // It may be a scanned-page novel, like 37°C. Let MangaBaka/provider decide.
        return nil
    }

    private func epubTitleLikeStrings(fromOPF opfText: String) -> [String] {
        var values: [String] = []

        values.append(contentsOf: localXMLElementBlocks(named: "dc:title", in: opfText).map(\.body))
        values.append(contentsOf: localXMLElementBlocks(named: "meta", in: opfText).compactMap { block in
            guard localXMLAttribute("property", in: block.openingTag)?.caseInsensitiveCompare("dcterms:title") == .orderedSame else {
                return nil
            }
            return block.body
        })
        values.append(contentsOf: localXMLStartTags(named: "meta", in: opfText).compactMap { tag in
            guard localXMLAttribute("name", in: tag)?.caseInsensitiveCompare("calibre:series") == .orderedSame else {
                return nil
            }
            return localXMLAttribute("content", in: tag)
        })

        return values.compactMap { value in
            let cleaned = value
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .replacingOccurrences(of: "&amp;", with: "&")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? nil : cleaned
        }
    }

    private func epubEntryLooksLikeNavigationOrCover(_ entry: String) -> Bool {
        let name = URL(fileURLWithPath: entry).deletingPathExtension().lastPathComponent.lowercased()
        let blocked = ["nav", "toc", "contents", "cover", "copyright", "title", "colophon"]
        return blocked.contains { name.contains($0) }
    }

    private func visibleWordCount(inHTML html: String) -> Int {
        var text = html
        text = removingLocalXMLElements(named: "script", from: text)
        text = removingLocalXMLElements(named: "style", from: text)
        text = text.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

        guard let regex = try? NSRegularExpression(pattern: #"\b[\p{L}\p{N}’'\-]+\b"#) else {
            return 0
        }
        return regex.numberOfMatches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text))
    }

    private struct LocalXMLElementBlock {
        var range: NSRange
        var openingTag: String
        var body: String
    }

    private func removingLocalXMLElements(named name: String, from text: String) -> String {
        let blocks = localXMLElementBlocks(named: name, in: text)
        guard !blocks.isEmpty else { return text }

        var result = text
        for block in blocks.reversed() {
            guard let range = Range(block.range, in: result) else { continue }
            result.replaceSubrange(range, with: " ")
        }
        return result
    }

    private func localXMLElementBlocks(named name: String, in text: String) -> [LocalXMLElementBlock] {
        localXMLStartTagMatches(named: name, in: text).compactMap { match in
            let trimmedOpening = match.tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedOpening.hasSuffix("/>"),
                  let openingRange = Range(match.range, in: text) else {
                return nil
            }

            let closingPattern = #"</\s*"# + NSRegularExpression.escapedPattern(for: match.tagName) + #"\s*>"#
            guard let closingRegex = try? NSRegularExpression(pattern: closingPattern, options: [.caseInsensitive]) else {
                return nil
            }
            let searchRange = NSRange(openingRange.upperBound..<text.endIndex, in: text)
            guard let closingMatch = closingRegex.firstMatch(in: text, range: searchRange),
                  let closingRange = Range(closingMatch.range, in: text) else {
                return nil
            }

            return LocalXMLElementBlock(
                range: NSRange(openingRange.lowerBound..<closingRange.upperBound, in: text),
                openingTag: match.tag,
                body: String(text[openingRange.upperBound..<closingRange.lowerBound])
            )
        }
    }

    private func localXMLStartTags(named name: String, in text: String) -> [String] {
        localXMLStartTagMatches(named: name, in: text).map(\.tag)
    }

    private func localXMLStartTagMatches(
        named name: String,
        in text: String
    ) -> [(range: NSRange, tag: String, tagName: String)] {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        let pattern = #"<\s*("# + escapedName + #")\b[^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        return regex.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)).compactMap { match in
            guard match.numberOfRanges > 1,
                  let fullRange = Range(match.range, in: text),
                  let nameRange = Range(match.range(at: 1), in: text) else {
                return nil
            }
            return (
                range: match.range,
                tag: String(text[fullRange]),
                tagName: String(text[nameRange])
            )
        }
    }

    private func localXMLAttribute(_ name: String, in tag: String) -> String? {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        let pattern = #"(?:^|\s)"# + escapedName + #"\s*=\s*["']([^"']*)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..<tag.endIndex, in: tag)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: tag) else {
            return nil
        }
        return String(tag[range])
    }

    private func preferredMangaBakaSearchTitles(from title: String, service: SableLibraryService) -> [String] {
        var titles = mangaBakaQueryVariants(from: title, service: service)
        if let cleanTitle = mangaBakaCatalogSearchTitle(from: title, service: service) {
            titles.append(cleanTitle)
        }

        // Final safety pass: never send catalog clutter to MangaBaka.
        // Years, source tokens, and local type suffixes are useful for folders,
        // but bad for provider search strings.
        return uniqueStrings(titles.compactMap { mangaBakaCatalogSearchTitle(from: $0, service: service) })
    }

    private func mangaBakaCatalogSearchTitle(from title: String, service: SableLibraryService) -> String? {
        guard let cleaned = SableLibraryProviderQueryCleaner.searchTitle(from: title) else {
            return nil
        }
        return service.cleanSeriesTitle(cleaned)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func mangaBakaQueryVariants(from title: String, service: SableLibraryService) -> [String] {
        var variants = SableLibraryProviderQueryCleaner.searchTitles(
            from: [title],
            limit: 8,
            includeLooseVariants: true
        )

        if let strippedTitle = service.titleByRemovingTrailingSuffix(from: title) {
            variants.append(contentsOf: SableLibraryProviderQueryCleaner.searchTitles(
                from: [strippedTitle],
                limit: 4,
                includeLooseVariants: true
            ))
        }

        let originalKey = service.normalizeTerm(title)
        return uniqueStrings(variants).filter { service.normalizeTerm($0) != originalKey }
    }

    private func addMangaBakaQuery(_ query: String, to queries: inout [String], service: SableLibraryService) {
        guard let cleanQuery = mangaBakaCatalogSearchTitle(from: query, service: service)?
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines) else {
            return
        }
        guard !cleanQuery.isEmpty else { return }
        let cleanKey = service.normalizeTerm(cleanQuery)
        guard !queries.contains(where: { service.normalizeTerm($0) == cleanKey }) else { return }
        queries.append(cleanQuery)
    }

    private func mangaBakaMatch(
        for queryPlan: MangaBakaQueryPlan,
        config: SableLibraryConfig,
        service: SableLibraryService
    ) async throws -> MangaBakaMatchAssessment {
        var lastError: Error?
        for queryTitle in queryPlan.titles {
            do {
                service.reportProgress("MangaBaka: \(queryTitle)")
                return try await mangaBakaMatch(
                    for: queryTitle,
                    queryPlan: queryPlan,
                    config: config,
                    service: service
                )
            } catch let error as MangaBakaLookupError {
                switch error {
                case .noMatch, .noConfidentMatch, .ambiguousMatch:
                    lastError = error
                    continue
                case .invalidURL, .invalidResponse, .requestFailed:
                    throw error
                }
            } catch {
                throw error
            }
        }

        if let lastError {
            throw lastError
        }
        throw MangaBakaLookupError.noMatch(queryPlan.titles.joined(separator: ", "))
    }

    private func mangaBakaMatch(
        forManualID seriesID: String,
        queryPlan: MangaBakaQueryPlan,
        config: SableLibraryConfig,
        service: SableLibraryService
    ) async throws -> MangaBakaMatchAssessment {
        service.reportProgress("MangaBaka ID: \(seriesID)")
        guard let url = mangaBakaSeriesURL(seriesID: seriesID, config: config) else {
            throw MangaBakaLookupError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = config.mangaBaka.timeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data = try await mangaBakaData(for: request, url: url)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidate = object["data"] as? [String: Any],
              !candidate.isEmpty else {
            throw MangaBakaLookupError.noMatch("MangaBaka ID \(seriesID)")
        }

        var match = mangaBakaMatchAssessment(
            candidate,
            queryTitle: queryPlan.titles.first ?? "MangaBaka ID \(seriesID)",
            queryPlan: queryPlan,
            config: config,
            service: service
        )
        match.manualSeriesID = seriesID
        match.resultCount = 1
        match.plausiblePeerCount = 1
        match.broadTitlePeerCount = 1
        if match.expectedMediaType == nil || match.typeMatched {
            match.confidence = .high
            match.overallScore = max(match.overallScore, 0.98)
        } else {
            match.confidence = .medium
            match.overallScore = min(match.overallScore, 0.89)
        }
        return match
    }

    private func mangaBakaMatch(
        for queryTitle: String,
        queryPlan: MangaBakaQueryPlan,
        config: SableLibraryConfig,
        service: SableLibraryService
    ) async throws -> MangaBakaMatchAssessment {
        guard let url = mangaBakaSearchURL(queryTitle: queryTitle, config: config) else {
            throw MangaBakaLookupError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = config.mangaBaka.timeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data = try await mangaBakaData(for: request, url: url)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = object["data"] as? [[String: Any]],
              !candidates.isEmpty else {
            throw MangaBakaLookupError.noMatch(queryTitle)
        }
        let best = try bestMangaBakaMatch(
            from: candidates,
            queryTitle: queryTitle,
            queryPlan: queryPlan,
            config: config,
            service: service
        )
        return best
    }

    private func mangaBakaData(for request: URLRequest, url: URL) async throws -> Data {
        let cacheKey = SableLibraryProviderResponseCache.key(provider: .mangabaka, url: url)
        if let cachedData = await SableLibraryProviderResponseCache.shared.cachedData(
            for: cacheKey,
            maximumAge: SableLibraryProviderRequestContext.maximumCacheAge
        ) {
            return cachedData
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MangaBakaLookupError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw MangaBakaLookupError.requestFailed(httpResponse.statusCode)
        }

        await SableLibraryProviderResponseCache.shared.store(data, for: cacheKey, ttl: 604_800)
        return data
    }

    private func mangaBakaSeriesURL(seriesID: String, config: SableLibraryConfig) -> URL? {
        var base = config.mangaBaka.apiBaseURL
        if !base.hasSuffix("/") {
            base += "/"
        }
        guard let baseURL = URL(string: base) else { return nil }

        if baseURL.path.split(separator: "/").contains("v1") {
            return baseURL
                .appendingPathComponent("series")
                .appendingPathComponent(seriesID)
        }

        return baseURL
            .appendingPathComponent("v1")
            .appendingPathComponent("series")
            .appendingPathComponent(seriesID)
    }

    private func mangaBakaSearchURL(queryTitle: String, config: SableLibraryConfig) -> URL? {
        var base = config.mangaBaka.apiBaseURL
        if !base.hasSuffix("/") {
            base += "/"
        }
        guard let baseURL = URL(string: base) else { return nil }

        let endpoint: URL
        if baseURL.path.split(separator: "/").contains("v1") {
            endpoint = baseURL
                .appendingPathComponent("series")
                .appendingPathComponent("search")
        } else {
            endpoint = baseURL
                .appendingPathComponent("v1")
                .appendingPathComponent("series")
                .appendingPathComponent("search")
        }

        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "q", value: queryTitle),
            URLQueryItem(name: "limit", value: "\(max(1, min(config.mangaBaka.maxSearchResults, 10)))")
        ]
        return components?.url
    }

    private func bestMangaBakaMatch(
        from candidates: [[String: Any]],
        queryTitle: String,
        queryPlan: MangaBakaQueryPlan,
        config: SableLibraryConfig,
        service: SableLibraryService
    ) throws -> MangaBakaMatchAssessment {
        let assessments = candidates
            .map { candidate in
                mangaBakaMatchAssessment(
                    candidate,
                    queryTitle: queryTitle,
                    queryPlan: queryPlan,
                    config: config,
                    service: service
                )
            }

        let confident = assessments
            .filter(\.isConfidentEnoughToWrite)
            .sorted { lhs, rhs in
                if lhs.typeMatched != rhs.typeMatched {
                    return lhs.typeMatched && !rhs.typeMatched
                }
                return lhs.overallScore > rhs.overallScore
            }
        guard var best = confident.first else {
            throw MangaBakaLookupError.noConfidentMatch(queryTitle)
        }

        let plausiblePeers = plausibleMangaBakaPeers(
            assessments,
            expectedMediaType: best.expectedMediaType
        )
        let broadTitlePeerCount = broadTitlePeerCount(in: assessments)
        best.resultCount = assessments.count
        best.plausiblePeerCount = plausiblePeers.count
        best.broadTitlePeerCount = broadTitlePeerCount
        if plausiblePeers.count > 1 {
            let sortedPeers = plausiblePeers.sorted { $0.overallScore > $1.overallScore }
            best.nearestScoreGap = max(0, best.overallScore - sortedPeers[1].overallScore)
        }

        if mangaBakaResultNeedsManualChoice(
            best: best,
            plausiblePeers: plausiblePeers,
            broadTitlePeerCount: broadTitlePeerCount,
            queryPlan: queryPlan,
            config: config,
            service: service
        ) {
            throw MangaBakaLookupError.ambiguousMatch(
                queryTitle,
                max(broadTitlePeerCount, plausiblePeers.count)
            )
        }

        return best
    }

    private func plausibleMangaBakaPeers(
        _ assessments: [MangaBakaMatchAssessment],
        expectedMediaType: String?
    ) -> [MangaBakaMatchAssessment] {
        assessments.filter { assessment in
            if expectedMediaType != nil, !assessment.typeMatched {
                return false
            }
            return assessment.titleScore >= 0.80 || assessment.overallScore >= 0.78
        }
    }

    private func mangaBakaResultNeedsManualChoice(
        best: MangaBakaMatchAssessment,
        plausiblePeers: [MangaBakaMatchAssessment],
        broadTitlePeerCount: Int,
        queryPlan: MangaBakaQueryPlan,
        config: SableLibraryConfig,
        service: SableLibraryService
    ) -> Bool {
        guard !plausiblePeers.isEmpty else { return false }
        if mangaBakaMatchNeedsManualReadingConfirmation(match: best, queryPlan: queryPlan, service: service) {
            return true
        }

        let highConfidencePeerCount = plausiblePeers.filter { peer in
            peer.confidence == .high || peer.overallScore >= 0.90 || peer.titleScore >= 0.95
        }.count
        if highConfidencePeerCount >= 5 {
            return true
        }

        let bestID = mangaBakaCandidateID(best.candidate, service: service)
        let peers = plausiblePeers.filter { mangaBakaCandidateID($0.candidate, service: service) != bestID }
        guard !peers.isEmpty else { return false }

        if best.expectedMediaType == nil {
            let peerTypes = Set(plausiblePeers.compactMap { service.textValue($0.candidate["type"])?.lowercased() })
            if peerTypes.count > 1 {
                return true
            }
        }

        if let nearestScoreGap = best.nearestScoreGap, nearestScoreGap < 0.08 {
            return true
        }

        let searchLimit = max(1, min(config.mangaBaka.maxSearchResults, 10))
        if queryPlan.usesPreferredTypeFallback,
           broadTitlePeerCount >= 3 {
            return true
        }

        let hasSparseLocalEvidence = (queryPlan.localHighestVolume ?? 0) <= 1 && queryPlan.localBookCount <= 2
        return queryPlan.usesPreferredTypeFallback
            && plausiblePeers.count >= 3
            && best.resultCount >= searchLimit
            && hasSparseLocalEvidence
    }

    private func broadTitlePeerCount(in assessments: [MangaBakaMatchAssessment]) -> Int {
        assessments.filter { assessment in
            assessment.titleScore >= 0.80 || assessment.overallScore >= 0.78
        }.count
    }

    private func mangaBakaCandidateID(_ candidate: [String: Any], service: SableLibraryService) -> String {
        if let id = candidate["id"] {
            return String(describing: id)
        }
        return service.normalizeTerm(service.textValue(candidate["title"]) ?? "")
    }

    private func mangaBakaMatchAssessment(
        _ candidate: [String: Any],
        queryTitle: String,
        queryPlan: MangaBakaQueryPlan,
        config: SableLibraryConfig,
        service: SableLibraryService
    ) -> MangaBakaMatchAssessment {
        let normalizedQuery = service.normalizeTerm(queryTitle)
        let titles = mangaBakaTitles(from: candidate, service: service)
        let titleMatches = titles.map { title in
            (title, mangaBakaTitleScore(title: title, normalizedQuery: normalizedQuery, service: service))
        }
        let bestTitleMatch = titleMatches.max { $0.1 < $1.1 }
        let titleScore = bestTitleMatch?.1 ?? 0
        let semanticScore = mangaBakaSemanticTitleScore(queryTitle: queryTitle, titles: titles, service: service)
        let typeMatched: Bool
        let normalizedDesiredType = queryPlan.mediaTypeHint.map { SableLibraryNamingPolicy().normalizedMediaType($0) }
        let expectedType = normalizedDesiredType == "Unknown" ? nil : normalizedDesiredType
        if let expectedType,
           let type = service.textValue(candidate["type"]) {
            typeMatched = SableLibraryNamingPolicy().normalizedMediaType(type) == expectedType
        } else {
            typeMatched = false
        }

        let combined = mangaBakaCombinedScore(
            titleScore: titleScore,
            semanticScore: semanticScore,
            typeMatched: typeMatched
        )
        let candidateFinalVolume = finalVolume(from: candidate, service: service)
        let hasFinalVolumeConflict = candidateFinalVolume.map { finalVolume in
            queryPlan.localHighestVolume.map { $0 > finalVolume } ?? false
        } ?? false
        let confidence: LibraryPlanConfidence
        if expectedType != nil, !typeMatched {
            confidence = .low
        } else if combined >= 0.90 || titleScore >= 0.95 {
            confidence = .high
        } else if combined >= 0.74 {
            confidence = .medium
        } else if combined > 0 {
            confidence = .low
        } else {
            confidence = .unknown
        }

        return MangaBakaMatchAssessment(
            candidate: candidate,
            queryTitle: queryTitle,
            matchedTitle: bestTitleMatch?.0 ?? service.textValue(candidate["title"]) ?? queryTitle,
            expectedMediaType: expectedType == "Unknown" ? nil : expectedType,
            overallScore: combined,
            titleScore: titleScore,
            semanticScore: semanticScore,
            localHighestVolume: queryPlan.localHighestVolume,
            candidateFinalVolume: candidateFinalVolume,
            hasFinalVolumeConflict: hasFinalVolumeConflict,
            typeMatched: typeMatched,
            confidence: confidence
        )
    }

    private func finalVolume(from candidate: [String: Any], service: SableLibraryService) -> Int? {
        guard let value = service.textValue(candidate["final_volume"]) else { return nil }
        return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func mangaBakaTitleScore(
        title: String,
        normalizedQuery: String,
        service: SableLibraryService
    ) -> Double {
        let normalizedTitle = service.normalizeTerm(title)
        guard !normalizedTitle.isEmpty, !normalizedQuery.isEmpty else { return 0 }
        if normalizedTitle == normalizedQuery {
            return 1.0
        }
        if normalizedTitle.contains(normalizedQuery) || normalizedQuery.contains(normalizedTitle) {
            return 0.82
        }
        return tokenSimilarity(normalizedTitle, normalizedQuery)
    }

    private func tokenSimilarity(_ lhs: String, _ rhs: String) -> Double {
        let lhsTokens = Set(lhs.split(separator: " ").map(String.init))
        let rhsTokens = Set(rhs.split(separator: " ").map(String.init))
        guard !lhsTokens.isEmpty, !rhsTokens.isEmpty else { return 0 }
        let overlap = lhsTokens.intersection(rhsTokens).count
        let union = lhsTokens.union(rhsTokens).count
        guard union > 0 else { return 0 }
        return Double(overlap) / Double(union)
    }

    private func mangaBakaCombinedScore(titleScore: Double, semanticScore: Double?, typeMatched: Bool) -> Double {
        let mlAssistedScore: Double
        if let semanticScore {
            mlAssistedScore = (titleScore * 0.78) + (semanticScore * 0.22)
        } else {
            mlAssistedScore = titleScore
        }

        let typeBoost = typeMatched ? 0.04 : 0
        return min(1.0, max(0.0, mlAssistedScore + typeBoost))
    }

    private func mangaBakaSemanticTitleScore(
        queryTitle: String,
        titles: [String],
        service: SableLibraryService
    ) -> Double? {
        #if canImport(NaturalLanguage)
        let normalizedQuery = service.normalizeTerm(queryTitle)
        guard !normalizedQuery.isEmpty,
              let embedding = NLEmbedding.sentenceEmbedding(for: .english) else {
            return nil
        }

        return titles.compactMap { title -> Double? in
            let normalizedTitle = service.normalizeTerm(title)
            guard !normalizedTitle.isEmpty else { return nil }
            let distance = embedding.distance(between: normalizedQuery, and: normalizedTitle, distanceType: .cosine)
            guard distance.isFinite else { return nil }
            return min(1.0, max(0.0, 1.0 - distance))
        }.max()
        #else
        return nil
        #endif
    }

    private func mangaBakaTitles(from candidate: [String: Any], service: SableLibraryService) -> [String] {
        var titles: [String] = []
        service.addUnique(service.textValue(candidate["title"]), to: &titles)
        service.addUnique(service.textValue(candidate["native_title"]), to: &titles)
        service.addUnique(service.textValue(candidate["romanized_title"]), to: &titles)

        if let titleEntries = candidate["titles"] as? [[String: Any]] {
            for entry in titleEntries {
                service.addUnique(service.textValue(entry["title"]), to: &titles)
            }
        }
        if let secondaryTitles = candidate["secondary_titles"] as? [String: [[String: Any]]] {
            for entries in secondaryTitles.values {
                for entry in entries {
                    service.addUnique(service.textValue(entry["title"]), to: &titles)
                }
            }
        }

        return titles
    }

    private func mangaBakaTitleVariants(from candidate: [String: Any], service: SableLibraryService) -> [String: [String]] {
        var variants: [String: [String]] = [:]

        func append(_ value: String?, to key: String?) {
            guard let key,
                  let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else {
                return
            }
            variants[key, default: []].append(value)
        }

        append(service.textValue(candidate["native_title"]), to: "native")
        append(service.textValue(candidate["romanized_title"]), to: "romanized")

        if let titleEntries = candidate["titles"] as? [[String: Any]] {
            for entry in titleEntries {
                let title = service.textValue(entry["title"])
                let language = service.textValue(entry["language"])
                let traits = arrayStrings(entry["traits"], service: service)
                append(title, to: mangaBakaTitleVariantKey(language: language, traits: traits, title: title))
            }
        }

        return variants.reduce(into: [String: [String]]()) { partialResult, element in
            let values = uniqueTitleVariants(element.value, service: service)
            if !values.isEmpty {
                partialResult[element.key] = values
            }
        }
    }

    private func mangaBakaTitleVariantKey(language: String?, traits: [String], title: String?) -> String? {
        let normalizedLanguage = language?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
        let normalizedTraits = Set(traits.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        })

        if normalizedLanguage?.contains("latn") == true {
            return "romanized"
        }
        if let normalizedLanguage,
           let key = normalizedTitleVariantKey(normalizedLanguage) {
            return key
        }
        if normalizedTraits.contains("native") {
            if let title, isLatinTitle(title) {
                return "romanized"
            }
            return "native"
        }
        return nil
    }

    private func mergeTitleVariants(
        _ incoming: [String: [String]],
        into sidecar: inout [String: Any],
        service: SableLibraryService
    ) {
        guard !incoming.isEmpty else { return }
        var merged = normalizedTitleVariantMap(sidecar["title_variants"], service: service)
        for (key, values) in incoming {
            merged[key, default: []].append(contentsOf: values)
        }
        for key in Array(merged.keys) {
            let values = uniqueTitleVariants(merged[key] ?? [], service: service)
            if values.isEmpty {
                merged.removeValue(forKey: key)
            } else {
                merged[key] = values
            }
        }
        sidecar["title_variants"] = merged
    }

    private func preferredMangaBakaDisplayTitle(
        from candidate: [String: Any],
        localTitle: String,
        service: SableLibraryService
    ) -> String {
        let titles = mangaBakaTitles(from: candidate, service: service)
        let normalizedLocalTitle = service.normalizeTerm(localTitle)
        let providerTitle = service.textValue(candidate["title"]) ?? localTitle
        guard !titles.isEmpty, !normalizedLocalTitle.isEmpty else {
            return providerTitle
        }

        let ranked = titles.map { title -> (title: String, score: Double, rank: Int) in
            let score = mangaBakaTitleScore(
                title: title,
                normalizedQuery: normalizedLocalTitle,
                service: service
            )
            return (title, score, displayTitleLanguageRank(title))
        }
        .sorted { lhs, rhs in
            if abs(lhs.score - rhs.score) > 0.03 {
                return lhs.score > rhs.score
            }
            if lhs.rank != rhs.rank {
                return lhs.rank > rhs.rank
            }
            let normalizedLHS = service.normalizeTerm(lhs.title)
            let normalizedRHS = service.normalizeTerm(rhs.title)
            let lhsContainsRHS = normalizedLHS.contains(normalizedRHS)
            let rhsContainsLHS = normalizedRHS.contains(normalizedLHS)
            if lhsContainsRHS != rhsContainsLHS {
                return lhsContainsRHS
            }
            return lhs.title.count < rhs.title.count
        }

        return ranked.first?.title ?? providerTitle
    }

    private func displayTitleLanguageRank(_ title: String) -> Int {
        if containsCJK(title) {
            return 0
        }
        if likelyRomanizedReadingTitle(title) {
            return 1
        }
        if title.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil {
            return 3
        }
        return 2
    }

    private func containsCJK(_ text: String) -> Bool {
        text.range(of: #"[\p{Han}\p{Hiragana}\p{Katakana}]"#, options: .regularExpression) != nil
    }

    private func likelyRomanizedReadingTitle(_ title: String) -> Bool {
        guard isLatinTitle(title) else { return false }
        let normalized = title
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
        let words = normalized
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        guard words.count >= 3 else { return false }

        let strongMarkers: Set<String> = [
            "akuyaku", "ayumu", "boukensha", "chuu", "chuuni", "douyara", "fuguu",
            "gishi", "hametsu", "himitsu", "isekai", "jibun", "kessha", "kikan",
            "konyakusha", "kuromaku", "mahou", "majutsushi", "monogatari", "nariagari",
            "ore", "ouji", "oidashita", "reijou", "ryuu", "saikyou", "sareta",
            "sareteshimau", "saseteshimau", "shite", "shiou", "suterareta",
            "tame", "tensei", "toshite", "tsuihou", "ubaitotte", "yuusha",
            "youzumi"
        ]
        let particles: Set<String> = ["ga", "ha", "wa", "wo", "o", "ni", "no", "to", "de", "kara"]
        let strongCount = words.filter { strongMarkers.contains($0) }.count
        let particleCount = words.filter { particles.contains($0) }.count
        return strongCount >= 1 || particleCount >= 3
    }

    private func shouldPreferLocalDisplayTitle(
        localTitle: String,
        over providerTitle: String,
        service: SableLibraryService
    ) -> Bool {
        let cleanLocalTitle = service.cleanSeriesTitle(localTitle)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanProviderTitle = service.cleanSeriesTitle(providerTitle)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanLocalTitle.isEmpty,
              !cleanProviderTitle.isEmpty,
              service.normalizeTerm(cleanLocalTitle) != service.normalizeTerm(cleanProviderTitle) else {
            return false
        }
        if containsCJK(cleanProviderTitle), !containsCJK(cleanLocalTitle) {
            return true
        }
        return likelyRomanizedReadingTitle(cleanProviderTitle)
            && isLatinTitle(cleanLocalTitle)
            && !likelyRomanizedReadingTitle(cleanLocalTitle)
    }

    private func mangaBakaComicInfo(
        match: MangaBakaMatchAssessment,
        localTitle: String,
        folder: URL,
        root: URL,
        config: SableLibraryConfig,
        existing: [String: Any],
        service: SableLibraryService,
        localFiles: SidecarLocalFileSnapshot
    ) -> [String: Any] {
        var comicInfo = existing
        let candidate = match.candidate
        let providerTitle = preferredMangaBakaDisplayTitle(
            from: candidate,
            localTitle: localTitle,
            service: service
        )
        let repairedProviderVolumeTitle = providerTitleAddsOnlyVolumeMarker(
            providerTitle,
            toCleanSeriesTitle: localTitle,
            service: service
        )
        let preferredTitle = repairedProviderVolumeTitle
            ? service.cleanSeriesTitle(localTitle)
            : providerTitle
        let titleSourceProvider: SableLibraryMetadataProvider = repairedProviderVolumeTitle ? .local : .mangabaka
        let resolvedLocalTitle: String
        if match.manualSeriesID != nil,
           readingProviderTitleHardConflictsWithLocalSeriesMarker(
            localTitle: localTitle,
            providerTitle: preferredTitle,
            service: service
           ) {
            resolvedLocalTitle = service.cleanSeriesTitle(preferredTitle)
        } else {
            resolvedLocalTitle = localTitle
        }

        comicInfo["title"] = preferredTitle
        comicInfo["local_title"] = resolvedLocalTitle
        comicInfo["preferred_title"] = preferredTitle
        setString("native_title", from: candidate, key: "native_title", in: &comicInfo, service: service)
        setString("romanized_title", from: candidate, key: "romanized_title", in: &comicInfo, service: service)
        setString("description", from: candidate, key: "description", in: &comicInfo, service: service)
        setString("type", from: candidate, key: "type", in: &comicInfo, service: service)
        setString("status", from: candidate, key: "status", in: &comicInfo, service: service)
        setString("content_rating", from: candidate, key: "content_rating", in: &comicInfo, service: service)
        setString("final_volume", from: candidate, key: "final_volume", in: &comicInfo, service: service)
        setString("total_chapters", from: candidate, key: "total_chapters", in: &comicInfo, service: service)
        if let year = candidate["year"] as? Int {
            comicInfo["year"] = year
        }
        let mangaBakaID = candidate["id"].map { String(describing: $0) }
        if let mangaBakaID {
            var ids = comicInfo["ids"] as? [String: Any] ?? [:]
            ids["mangabaka"] = mangaBakaID
            comicInfo["ids"] = ids
        }
        if let url = mangaBakaCanonicalURL(from: candidate, service: service) {
            comicInfo["mangabaka_url"] = url
        }
        if let cover = coverURL(from: candidate, service: service) {
            comicInfo["cover_url"] = cover
        }

        mergeTitleVariants(mangaBakaTitleVariants(from: candidate, service: service), into: &comicInfo, service: service)
        let v2Tags = mangaBakaV2TagSummary(from: candidate, service: service)
        let publishers = publisherNames(from: candidate, service: service)
        if !publishers.isEmpty {
            comicInfo["publishers"] = publishers
        }
        let authors = metadataNames(from: candidate, keys: ["authors", "author"], service: service)
        if !authors.isEmpty {
            comicInfo["authors"] = authors
        }
        let artists = metadataNames(from: candidate, keys: ["artists", "artist"], service: service)
        if !artists.isEmpty {
            comicInfo["artists"] = artists
        }
        let genres = uniqueStrings(
            v2Tags.genres + metadataNames(from: candidate, keys: ["genres_v2", "genres", "genre"], service: service)
        )
        if !genres.isEmpty {
            comicInfo["genres"] = uniqueStrings(arrayStrings(comicInfo["genres"], service: service) + genres)
        }
        let tags = uniqueStrings(
            v2Tags.tags
                + mangaBakaLegacyTagNames(from: candidate, service: service)
                + metadataNames(from: candidate, keys: ["themes", "demographics"], service: service)
        )
        if !tags.isEmpty {
            comicInfo["tags"] = uniqueStrings(arrayStrings(comicInfo["tags"], service: service) + tags)
        }
        let studios = metadataNames(from: candidate, keys: ["studios", "studio"], service: service)
        if !studios.isEmpty {
            comicInfo["studios"] = uniqueStrings(arrayStrings(comicInfo["studios"], service: service) + studios)
        }
        let contentWarnings = uniqueStrings(
            v2Tags.contentWarnings + metadataNames(from: candidate, keys: ["content_warnings", "warnings"], service: service)
        )
        if !contentWarnings.isEmpty {
            comicInfo["content_warnings"] = uniqueStrings(arrayStrings(comicInfo["content_warnings"], service: service) + contentWarnings)
        }
        var mangaBakaMetadata: [String: Any] = [
            "query": match.queryTitle,
            "matched_title": preferredTitle,
            "matched_alias": match.matchedTitle,
            "matched_id": String(describing: candidate["id"] ?? ""),
            "match_source": match.manualSeriesID == nil ? "search" : "manual_id",
            "last_updated_at": service.textValue(candidate["last_updated_at"]) ?? "",
            "confidence": match.confidence.rawValue,
            "confidence_score": roundedScore(match.overallScore),
            "title_score": roundedScore(match.titleScore),
            "type_match": match.typeMatched,
            "confidence_detail": match.explanation
        ]
        if repairedProviderVolumeTitle {
            mangaBakaMetadata["provider_title"] = providerTitle
            mangaBakaMetadata["title_repair"] = "provider_volume_title_trimmed"
        }
        if let expectedMediaType = match.expectedMediaType {
            mangaBakaMetadata["expected_type"] = expectedMediaType
        }
        if let manualSeriesID = match.manualSeriesID {
            mangaBakaMetadata["manual_series_id"] = manualSeriesID
        }
        if let semanticScore = match.semanticScore {
            mangaBakaMetadata["ml_similarity_score"] = roundedScore(semanticScore)
        }
        for (key, value) in mangaBakaV2Metadata(from: candidate, service: service) {
            mangaBakaMetadata[key] = value
        }

        var matchEvidence: [[String: Any]] = [
            evidenceDictionary(
                SableLibraryMatchEvidence(
                    kind: match.manualSeriesID == nil ? .titleSimilarity : .exactProviderID,
                    provider: .mangabaka,
                    value: match.matchedTitle,
                    confidence: match.manualSeriesID == nil ? match.titleScore : 1
                )
            )
        ]
        if match.typeMatched {
            matchEvidence.append(
                evidenceDictionary(
                    SableLibraryMatchEvidence(
                        kind: .typeMatch,
                        provider: .mangabaka,
                        value: service.textValue(candidate["type"]) ?? "",
                        confidence: 0.96
                    )
                )
            )
        }
        comicInfo["match_evidence"] = mergedEvidenceDictionaries(
            existing: comicInfo["match_evidence"] as? [[String: Any]] ?? [],
            refreshed: matchEvidence.compactMap { evidence(from: $0, service: service) }
        )
        comicInfo["source_freshness"] = mergedFreshnessDictionaries(
            existing: comicInfo["source_freshness"] as? [[String: Any]] ?? [],
            refreshed: [
                SableLibraryProviderFreshness(
                    provider: .mangabaka,
                    fetchedAt: service.isoTimestamp(),
                    ttlSeconds: 604800
                )
            ]
        )
        comicInfo["last_checked"] = service.isoTimestamp()
        comicInfo["source"] = "mangabaka"
        let ids = comicInfo["ids"] as? [String: Any] ?? [:]
        let resolvedYear = integerValue(comicInfo["year"]) ?? yearHint(in: folder.lastPathComponent)
        comicInfo["plex"] = readingOrganizerHints(
            title: preferredTitle,
            year: resolvedYear,
            ids: ids,
            mediaType: service.textValue(comicInfo["type"]) ?? service.textValue(candidate["type"]) ?? "unknown"
        )
        var sable = comicInfo["_sable"] as? [String: Any] ?? [:]
        let existingProviders = (sable["metadata_enrichment"] as? [String: Any])?["providers"] as? [String] ?? []
        sable["snapshot_version"] = 1
        sable["refreshed_at"] = service.isoTimestamp()
        sable["book_snapshot"] = bookSnapshot(items: localFiles.bookItems, service: service)
        sable["organizer_source"] = organizerSourceSnapshot(
            folderName: folder.lastPathComponent,
            cleanTitle: preferredTitle,
            year: resolvedYear,
            sourceID: sourceIDHint(in: folder.lastPathComponent) ?? readingSourceID(from: ids)
        )
        sable["mangabaka"] = mangaBakaMetadata
        sable["metadata_enrichment"] = [
            "outcome": SableLibraryQuietOutcome.safeApply.rawValue,
            "confidence_score": roundedScore(match.overallScore),
            "providers": uniqueStrings(existingProviders + [SableLibraryMetadataProvider.mangabaka.rawValue]),
            "updated_at": service.isoTimestamp()
        ]
        sable["title_source"] = [
            "provider": titleSourceProvider.rawValue,
            "title": preferredTitle,
            "priority": readingTitlePriority(titleSourceProvider),
            "updated_at": service.isoTimestamp()
        ]
        comicInfo["_sable"] = sable
        return comicInfo
    }

    private func comicInfoReceipt(
        action: String,
        item: LibraryPlanItem,
        comicInfo: [String: Any],
        service: SableLibraryService
    ) -> String {
        let title = service.textValue(comicInfo["preferred_title"]) ?? service.textValue(comicInfo["title"]) ?? item.currentPath
        let source = service.textValue(comicInfo["source"]) ?? "local"
        if let sableMetadata = comicInfo["_sable"] as? [String: Any],
           let mangaBaka = sableMetadata["mangabaka"] as? [String: Any],
           let confidence = service.textValue(mangaBaka["confidence"]),
           let score = mangaBaka["confidence_score"] {
            let enrichment = sidecarEnrichmentReceiptDetails(from: sableMetadata, service: service)
            let suffix = enrichment.isEmpty ? "" : " [\(enrichment)]"
            return "\(action) \(item.proposedPath ?? item.currentPath) from \(source): \(title) (\(confidence), score \(score))\(suffix)"
        }
        let sableMetadata = comicInfo["_sable"] as? [String: Any] ?? [:]
        let enrichment = sidecarEnrichmentReceiptDetails(from: sableMetadata, service: service)
        let suffix = enrichment.isEmpty ? "" : " [\(enrichment)]"
        return "\(action) \(item.proposedPath ?? item.currentPath) from \(source): \(title)\(suffix)"
    }

    private func animeInfoReceipt(
        action: String,
        item: LibraryPlanItem,
        animeInfo: [String: Any],
        service: SableLibraryService
    ) -> String {
        let title = service.textValue(animeInfo["preferred_title"]) ?? service.textValue(animeInfo["title"]) ?? item.currentPath
        let source = service.textValue(animeInfo["source"]) ?? "local"
        let sableMetadata = animeInfo["_sable"] as? [String: Any] ?? [:]
        let enrichment = sidecarEnrichmentReceiptDetails(from: sableMetadata, service: service)
        let suffix = enrichment.isEmpty ? "" : " [\(enrichment)]"
        return "\(action) \(item.proposedPath ?? item.currentPath) from \(source): \(title)\(suffix)"
    }

    private func sidecarEnrichmentReceiptDetails(
        from sableMetadata: [String: Any],
        service: SableLibraryService
    ) -> String {
        var parts: [String] = []
        if let enrichment = sableMetadata["metadata_enrichment"] as? [String: Any],
           let outcome = service.textValue(enrichment["outcome"]) {
            let providers = (enrichment["providers"] as? [String] ?? [])
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let providerText = providers.isEmpty ? "" : " via \(providers.joined(separator: ", "))"
            let scoreText = service.textValue(enrichment["confidence_score"]).map { ", score \($0)" } ?? ""
            parts.append("\(outcome)\(providerText)\(scoreText)")
        }
        if let ranobeDB = sableMetadata["ranobedb"] as? [String: Any],
           service.textValue(ranobeDB["outcome"]) == SableLibraryQuietOutcome.safeApply.rawValue {
            let bookDetail = ranobeDB["book_detail"] as? [String: Any] ?? [:]
            let volumeCount = service.textValue(ranobeDB["provider_known_volume_count"])
                ?? service.textValue(bookDetail["fetched_book_count"])
                ?? service.textValue(ranobeDB["volume_count"])
                ?? "0"
            let isbnCount = service.textValue(ranobeDB["isbn_count"]) ?? "0"
            let newReleaseCount = service.textValue(bookDetail["new_release_count"]) ?? "0"
            let newDetailCount = service.textValue(bookDetail["newly_fetched_book_count"]) ?? "0"
            parts.append(
                "RanobeDB \(volumeCount) volume(s), \(newReleaseCount) new release(s), \(newDetailCount) new detail record(s), \(isbnCount) ISBN(s)"
            )
        }
        return parts.joined(separator: "; ")
    }

    private func recordSidecarTrainingEvent(
        item: LibraryPlanItem,
        domain: SableLibraryMediaDomain,
        provider: SableLibraryMetadataProvider,
        root: URL,
        config: SableLibraryConfig,
        service: SableLibraryService
    ) {
        let event = SableLibraryMLTrainingEvent.make(
            kind: .finalSuccessfulSidecar,
            domain: domain,
            localPath: item.currentPath,
            provider: provider,
            confidenceScore: confidenceScore(for: item.confidence),
            featureSummary: [
                "stage": item.stage.rawValue,
                "operation": item.operation.rawValue,
                "used_network": String(item.usedNetworkData),
                "safety": item.safety.rawValue,
                "source_extension": (item.currentPath as NSString).pathExtension.lowercased(),
                "metadata_providers": item.metadataProviders.map(\.rawValue).joined(separator: ","),
                "review_tags": item.reviewTags
                    .filter {
                        $0.hasPrefix("likely-")
                            || $0.hasPrefix("provider-")
                            || $0.hasPrefix("metadata-")
                            || $0 == "needs-provider-choice"
                            || $0 == "manual-provider-match"
                    }
                    .sorted()
                    .joined(separator: ",")
            ]
        )
        service.recordMLTrainingEvent(event, root: root, config: config)
    }

    private func recordSidecarCleanerTrainingEvent(
        item: LibraryPlanItem,
        sidecar: [String: Any],
        domain: SableLibraryMediaDomain,
        root: URL,
        config: SableLibraryConfig,
        service: SableLibraryService
    ) {
        let sourceIDs = sourceIDs(from: sidecar, service: service)
        let providerNames = uniqueStrings(sourceIDs.map(\.provider.rawValue)).sorted()
        let ids = normalizedIDDictionary(from: sidecar, service: service)
        let trustedTitleProvider = domain == .reading
            ? currentReadingTitleProvider(comicInfo: sidecar, ids: ids, service: service).rawValue
            : (sourceIDs.first?.provider.rawValue ?? SableLibraryMetadataProvider.local.rawValue)
        let evidenceRows = sidecar["match_evidence"] as? [[String: Any]] ?? []
        let freshnessRows = sidecar["source_freshness"] as? [[String: Any]] ?? []
        let volumes = sidecar["volumes"] as? [[String: Any]] ?? []
        let titleVariants = titleVariantMap(from: sidecar, service: service)
        let event = SableLibraryMLTrainingEvent.make(
            kind: .finalSuccessfulSidecar,
            domain: domain,
            localPath: item.currentPath,
            provider: .local,
            confidenceScore: 0.95,
            featureSummary: [
                "stage": item.stage.rawValue,
                "operation": item.operation.rawValue,
                "used_network": "false",
                "safety": item.safety.rawValue,
                "cleanup_kind": "provider_data_cleaner",
                "provider_data_state": "cleaned",
                "trusted_title_provider": trustedTitleProvider,
                "source_provider_count": metadataCountBucket(providerNames.count),
                "metadata_providers": providerNames.joined(separator: ","),
                "has_cover_url": String(service.textValue(sidecar["cover_url"]) != nil),
                "has_match_evidence": String(!evidenceRows.isEmpty),
                "has_source_freshness": String(!freshnessRows.isEmpty),
                "has_title_variants": String(!titleVariants.isEmpty),
                "has_native_title": String(!(titleVariants["native"] ?? []).isEmpty),
                "has_romanized_title": String(!(titleVariants["romanized"] ?? []).isEmpty),
                "tag_count": metadataCountBucket(arrayStrings(sidecar["tags"], service: service).count),
                "genre_count": metadataCountBucket(arrayStrings(sidecar["genres"], service: service).count),
                "author_count": metadataCountBucket(arrayStrings(sidecar["authors"], service: service).count),
                "publisher_count": metadataCountBucket(arrayStrings(sidecar["publishers"], service: service).count),
                "isbn_count": metadataCountBucket(arrayStrings(sidecar["isbn13"], service: service).count),
                "volume_count": metadataCountBucket(volumes.count),
                "sidecar_source": service.textValue(sidecar["source"]) ?? "",
                "review_tags": item.reviewTags
                    .filter { $0.hasPrefix("metadata-") || $0.hasPrefix("ml-") }
                    .sorted()
                    .joined(separator: ",")
            ]
        )
        service.recordMLTrainingEvent(event, root: root, config: config)
    }

    private func metadataCountBucket(_ count: Int) -> String {
        switch count {
        case 0:
            return "zero"
        case 1:
            return "one"
        case 2...4:
            return "few"
        case 5...12:
            return "some"
        default:
            return "many"
        }
    }

    private func trainingProvider(for item: LibraryPlanItem) -> SableLibraryMetadataProvider {
        if item.metadataProviders.contains(.mangabaka) {
            return .mangabaka
        }
        if item.metadataProviders.contains(.ranobedb) {
            return .ranobedb
        }
        if item.metadataProviders.contains(.openLibrary) {
            return .openLibrary
        }
        if item.metadataProviders.contains(.anilist) {
            return .anilist
        }
        if item.metadataProviders.contains(.tvmaze) {
            return .tvmaze
        }
        if item.metadataProviders.contains(.wikidata) {
            return .wikidata
        }
        return .local
    }

    private func confidenceScore(for confidence: LibraryPlanConfidence) -> Double {
        switch confidence {
        case .high: 0.95
        case .medium: 0.72
        case .low: 0.4
        case .unknown: 0
        }
    }

    private func roundedScore(_ score: Double) -> Double {
        (score * 100).rounded() / 100
    }

    private func setString(
        _ targetKey: String,
        from candidate: [String: Any],
        key sourceKey: String,
        in comicInfo: inout [String: Any],
        service: SableLibraryService
    ) {
        if let value = service.textValue(candidate[sourceKey]) {
            comicInfo[targetKey] = value
        }
    }

    private func coverURL(from candidate: [String: Any], service: SableLibraryService) -> String? {
        guard let cover = candidate["cover"] as? [String: Any],
              let raw = cover["raw"] as? [String: Any] else {
            return nil
        }
        return service.textValue(raw["url"])
    }

    private func mangaBakaCanonicalURL(from candidate: [String: Any], service: SableLibraryService) -> String? {
        if let id = service.textValue(candidate["id"]) {
            return "https://mangabaka.org/\(id)"
        }
        let links = arrayStrings(candidate["links"], service: service)
        return links.first { $0.localizedCaseInsensitiveContains("mangabaka.org") }
            ?? links.first
    }

    private func mangaBakaLegacyTagNames(from candidate: [String: Any], service: SableLibraryService) -> [String] {
        guard let rows = candidate["tags"] as? [[String: Any]] else {
            return metadataNames(from: candidate, keys: ["tags"], service: service)
        }
        let looksLikeV2 = rows.contains { row in
            row["is_genre"] != nil || row["name_path"] != nil || row["content_rating"] != nil
        }
        return looksLikeV2 ? [] : metadataNames(from: candidate, keys: ["tags"], service: service)
    }

    private func mangaBakaV2TagSummary(
        from candidate: [String: Any],
        service: SableLibraryService
    ) -> (genres: [String], tags: [String], contentWarnings: [String]) {
        var genres: [String] = []
        var tags: [String] = []
        var contentWarnings: [String] = []

        for row in mangaBakaV2TagRows(from: candidate) {
            guard let name = service.textValue(row["name"]) else { continue }
            if boolValue(row["is_genre"]) == true {
                genres.append(name)
            } else {
                tags.append(name)
            }

            let rating = service.textValue(row["content_rating"])?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() ?? ""
            let path = service.textValue(row["name_path"])?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() ?? ""
            if rating == "erotica" || rating == "pornographic" || path.contains("sexual content") {
                contentWarnings.append(name)
            }
        }

        return (
            genres: uniqueStrings(genres),
            tags: uniqueStrings(tags),
            contentWarnings: uniqueStrings(contentWarnings)
        )
    }

    private func mangaBakaV2Metadata(from candidate: [String: Any], service: SableLibraryService) -> [String: Any] {
        var result: [String: Any] = [:]

        let titleRows = providerMetadataRows(
            candidate["titles"],
            keeping: ["language", "traits", "title", "note", "is_primary"],
            service: service
        )
        if !titleRows.isEmpty {
            result["titles_v2"] = titleRows
        }

        let linkRows = providerMetadataRows(
            candidate["links_v2"],
            keeping: ["id", "url", "name", "name_display", "type", "language"],
            service: service
        )
        if !linkRows.isEmpty {
            result["links_v2"] = linkRows
        }

        let tagRows = providerMetadataRows(
            mangaBakaV2TagRows(from: candidate),
            keeping: [
                "id", "name", "name_path", "parent_id", "level", "weight",
                "is_genre", "is_spoiler", "is_explicit", "content_rating",
                "description", "series_count", "implied_by_tag_ids"
            ],
            displayMetadataNames: true,
            service: service
        )
        if !tagRows.isEmpty {
            result["tags_v2"] = tagRows
        }

        let genreRows = providerMetadataRows(
            candidate["genres_v2"],
            keeping: [
                "id", "name", "name_path", "parent_id", "level", "weight",
                "is_genre", "is_spoiler", "is_explicit", "content_rating",
                "description", "series_count", "implied_by_tag_ids"
            ],
            displayMetadataNames: true,
            service: service
        )
        if !genreRows.isEmpty {
            result["genres_v2"] = genreRows
        }

        let publisherRows = providerMetadataRows(
            candidate["publishers"],
            keeping: ["name", "type", "note"],
            service: service
        )
        if !publisherRows.isEmpty {
            result["publishers_v2"] = publisherRows
        }

        let relationshipRows = providerMetadataRows(
            candidate["relationships_v2"],
            keeping: [
                "id", "to_series_id", "relation_type", "chronology",
                "published_start_date", "note", "is_manual"
            ],
            service: service
        )
        if !relationshipRows.isEmpty {
            result["relationships_v2"] = relationshipRows
        }

        let recommendationRows = providerMetadataRows(
            mangaBakaRecommendationRows(from: candidate),
            keeping: [
                "id", "series_id", "to_series_id", "mangabaka_id",
                "title", "name", "type", "category", "reason", "reasons",
                "score", "rank", "weight", "similarity", "confidence",
                "genres", "genre", "themes", "theme", "tags", "tag"
            ],
            displayMetadataNames: true,
            service: service
        )
        if !recommendationRows.isEmpty {
            result["recommendation_neighbors"] = recommendationRows
        }

        return result
    }

    private func mangaBakaV2TagRows(from candidate: [String: Any]) -> [[String: Any]] {
        if let rows = candidate["tags_v2"] as? [[String: Any]] {
            return rows
        }
        let rows = candidate["tags"] as? [[String: Any]] ?? []
        let looksLikeV2 = rows.contains { row in
            row["is_genre"] != nil || row["name_path"] != nil || row["content_rating"] != nil
        }
        return looksLikeV2 ? rows : []
    }

    private func mangaBakaRecommendationRows(from candidate: [String: Any]) -> [[String: Any]] {
        var rows: [[String: Any]] = []
        for key in ["recommendation_neighbors", "recommendations_v2", "recommendations", "similar_v2", "similar_series", "similar"] {
            if let value = candidate[key] as? [[String: Any]] {
                rows.append(contentsOf: value)
            }
        }
        return Array(rows.prefix(50))
    }

    private func providerMetadataRows(
        _ value: Any?,
        keeping keys: [String],
        displayMetadataNames: Bool = false,
        service: SableLibraryService
    ) -> [[String: Any]] {
        guard let rows = value as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            var cleaned: [String: Any] = [:]
            for key in keys {
                if let value = providerMetadataValue(row[key], service: service) {
                    cleaned[key] = displayMetadataNames
                        ? displayProviderMetadataValue(value, key: key, service: service)
                        : value
                }
            }
            return cleaned.isEmpty ? nil : cleaned
        }
    }

    private func displayProviderMetadataValue(
        _ value: Any,
        key: String,
        service: SableLibraryService
    ) -> Any {
        switch key {
        case "name":
            guard let text = value as? String else { return value }
            return service.displayMetadataTerm(text)
        case "name_path":
            guard let text = value as? String else { return value }
            return text
                .components(separatedBy: ">")
                .map { service.displayMetadataTerm($0) }
                .joined(separator: " > ")
        default:
            return value
        }
    }

    private func providerMetadataValue(_ value: Any?, service: SableLibraryService) -> Any? {
        switch value {
        case let string as String:
            return service.textValue(string)
        case let bool as Bool:
            return bool
        case let number as NSNumber:
            return number
        case let values as [Any]:
            let cleaned = values.compactMap { providerMetadataValue($0, service: service) }
            return cleaned.isEmpty ? nil : cleaned
        case let dictionary as [String: Any]:
            var cleaned: [String: Any] = [:]
            for (key, value) in dictionary {
                if let value = providerMetadataValue(value, service: service) {
                    cleaned[key] = value
                }
            }
            return cleaned.isEmpty ? nil : cleaned
        default:
            return nil
        }
    }

    private func publisherNames(from candidate: [String: Any], service: SableLibraryService) -> [String] {
        guard let publishers = candidate["publishers"] as? [[String: Any]] else { return [] }

        return publishers.compactMap { publisher in
            service.textValue(publisher["name"])
        }
    }

    private func metadataNames(
        from candidate: [String: Any],
        keys: [String],
        service: SableLibraryService
    ) -> [String] {
        var values: [String] = []
        for key in keys {
            switch candidate[key] {
            case let strings as [String]:
                values.append(contentsOf: strings)
            case let rows as [[String: Any]]:
                values.append(contentsOf: rows.compactMap {
                    service.textValue($0["name"])
                        ?? service.textValue($0["title"])
                        ?? service.textValue($0["label"])
                })
            case let string as String:
                values.append(contentsOf: string.components(separatedBy: CharacterSet(charactersIn: ",;")))
            default:
                continue
            }
        }
        return uniqueStrings(values)
    }

    private func delayForMetadataProviders(
        item: LibraryPlanItem,
        nextIndex: Int,
        totalCount: Int,
        service: SableLibraryService,
        config: SableLibraryConfig
    ) async throws {
        let seconds: Double
        switch item.operation {
        case .createComicInfo, .refreshComicInfo:
            seconds = item.metadataProviders.contains(.mangabaka)
                ? config.mangaBaka.requestDelaySeconds
                : 0
        case .createAnimeInfo, .refreshAnimeInfo:
            let providerDelay = [
                config.metadataProviders.anilist,
                config.metadataProviders.tvmaze,
                config.metadataProviders.wikidata
            ]
                .filter(\.enabled)
                .map(\.requestDelaySeconds)
                .filter { $0 > 0 }
                .min() ?? 0
            seconds = min(providerDelay, 0.35)
        case .inspectOnly, .repairEpubPackage, .repairAppleBooksCompatibility, .cleanRawName, .sortIntoFolder, .renameFolder, .renameFile, .duplicateDecision, .skip:
            seconds = 0
        }

        let delay = max(0, seconds)
        guard delay > 0 else { return }
        service.reportProgress("Provider cooldown before metadata pass \(nextIndex)/\(totalCount)")
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }

    private func readComicInfo(url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return nil
        }
        return dictionary
    }

    private func write(
        comicInfo: [String: Any],
        to url: URL,
        service: SableLibraryService,
        mediaDomain: SableLibraryMediaDomain
    ) throws {
        try service.fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try comicInfoSidecarData(
            comicInfo,
            sidecarURL: url,
            service: service,
            mediaDomain: mediaDomain
        )
        try data.write(to: url, options: .atomic)
    }

    private func comicInfoSidecarData(
        _ comicInfo: [String: Any],
        sidecarURL: URL,
        service: SableLibraryService,
        mediaDomain: SableLibraryMediaDomain
    ) throws -> Data {
        let trustedSourceIDs = sourceIDHints(in: sidecarURL.deletingLastPathComponent().lastPathComponent)
        let compacted = compactedSidecar(
            comicInfo,
            mediaDomain: mediaDomain,
            service: service,
            trustedSourceIDs: trustedSourceIDs
        )
        return try JSONSerialization.data(withJSONObject: compacted, options: [.prettyPrinted, .sortedKeys])
    }

    private func writePlexMatchIfNeeded(
        animeInfo: [String: Any],
        folder: URL,
        service: SableLibraryService
    ) throws {
        guard let content = plexMatchContent(animeInfo: animeInfo, service: service) else {
            return
        }

        try service.fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        try content.write(
            to: folder.appendingPathComponent(".plexmatch"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func plexMatchContent(animeInfo: [String: Any], service: SableLibraryService) -> String? {
        let mediaType = service.textValue(animeInfo["type"]) ?? ""
        guard shouldWritePlexMatchFile(for: mediaType) else {
            return nil
        }

        let title = service.textValue(animeInfo["preferred_title"])
            ?? service.textValue(animeInfo["title"])
        let year = integerValue(animeInfo["year"])
        let ids = animeInfo["ids"] as? [String: Any] ?? [:]

        var lines = [
            "# Generated by Sable's Library from AnimeInfo.json"
        ]
        if let title = title.map(plexMatchLineValue), !title.isEmpty {
            lines.append("title: \(title)")
        }
        if let year {
            lines.append("year: \(year)")
        }
        if let imdb = stringValue(ids["imdb"]) {
            lines.append("imdbid: \(plexMatchLineValue(imdb))")
        } else if let tmdb = stringValue(ids["tmdb"]) {
            lines.append("tmdbid: \(plexMatchLineValue(tmdb))")
        } else if let tvdb = stringValue(ids["tvdb"]) {
            lines.append("tvdbid: \(plexMatchLineValue(tvdb))")
        }

        guard lines.count > 1 else { return nil }
        return lines.joined(separator: "\n") + "\n"
    }

    private func shouldWritePlexMatchFile(for mediaType: String) -> Bool {
        switch mediaType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "animetv", "anime tv", "tv_anime",
             "ova", "ona", "special", "specials",
             "tvshow", "tv show", "tv",
             "animemovie", "anime movie", "movie", "film":
            return true
        default:
            return false
        }
    }

    private func plexMatchLineValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func compactedSidecar(
        _ sidecar: [String: Any],
        mediaDomain: SableLibraryMediaDomain,
        service: SableLibraryService,
        trustedSourceIDs: [SableLibrarySourceID] = []
    ) -> [String: Any] {
        var result = sidecar
        result.removeValue(forKey: "_goblin")
        if mediaDomain == .reading {
            result.removeValue(forKey: "classification")
        }
        moveBookScopedOpenLibraryIDToAvailability(in: &result, service: service)
        pruneRejectedProviderPublicTraces(in: &result, service: service)

        let rejectedSourceIDKeys = rejectedProviderSourceIDKeys(in: result, service: service)
        let trustedSourceIDs = trustedSourceIDs.filter { sourceID in
            !rejectedSourceIDKeys.contains(sourceIDKey(sourceID))
        }
        let ids = normalizedIDDictionary(from: result, extraIDs: trustedSourceIDs, service: service)
        if ids.isEmpty {
            result.removeValue(forKey: "ids")
        } else {
            result["ids"] = ids
        }
        for (key, _) in SableLibrarySourceIDParser.legacyTopLevelIDKeys {
            result.removeValue(forKey: key)
        }

        compactStringList("genres", in: &result, service: service)
        compactStringList("tags", in: &result, service: service)
        compactStringList("studios", in: &result, service: service)
        migrateLegacySubtitleField(in: &result, mediaDomain: mediaDomain, service: service)
        compactStringList("volume_titles", in: &result, service: service)
        compactStringList("episode_titles", in: &result, service: service)
        compactStringList("authors", in: &result, service: service)
        compactStringList("artists", in: &result, service: service)
        compactStringList("publishers", in: &result, service: service)
        compactStringList("languages", in: &result, service: service)
        compactStringList("content_warnings", in: &result, service: service)
        compactStringList("isbn13", in: &result, service: service)
        compactLocalSeriesTitle(in: &result, service: service)
        compactTitleVariants(in: &result, service: service)
        compactAliases(in: &result, service: service)
        compactSeriesAliasDump("volume_titles", in: &result, service: service)
        normalizeSidecarCoverURL(in: &result, service: service)
        compactSableMetadata(in: &result, service: service)

        if let evidence = result["match_evidence"] as? [[String: Any]] {
            result["match_evidence"] = mergedEvidenceDictionaries(existing: evidence, refreshed: [])
        }
        if let freshness = result["source_freshness"] as? [[String: Any]] {
            result["source_freshness"] = mergedFreshnessDictionaries(existing: freshness, refreshed: [])
        }
        if mediaDomain == .reading {
            refreshReadingCatalogView(in: &result, service: service)
        }
        return result
    }

    private var readingCatalogViewKeys: [String] {
        ["schema", "creators", "urls", "source_quality", "organizer", "origin"]
    }

    private func refreshReadingCatalogView(
        in sidecar: inout [String: Any],
        service: SableLibraryService
    ) {
        let fields = readingCatalogViewFields(from: sidecar, service: service)
        for key in readingCatalogViewKeys {
            if let value = fields[key] {
                sidecar[key] = value
            } else {
                sidecar.removeValue(forKey: key)
            }
        }
    }

    private func readingCatalogViewFields(
        from sidecar: [String: Any],
        service: SableLibraryService
    ) -> [String: Any] {
        var fields: [String: Any] = [
            "schema": "ComicInfo.SableClean.v1"
        ]
        if let creators = readingCreatorsView(from: sidecar, service: service) {
            fields["creators"] = creators
        }
        if let urls = readingURLsView(from: sidecar, service: service) {
            fields["urls"] = urls
        }
        if let sourceQuality = readingSourceQualityView(from: sidecar, service: service) {
            fields["source_quality"] = sourceQuality
        }
        if let organizer = readingOrganizerView(from: sidecar, service: service) {
            fields["organizer"] = organizer
        }
        if let origin = readingOriginView(from: sidecar, service: service) {
            fields["origin"] = origin
        }
        return fields
    }

    private func readingCreatorsView(
        from sidecar: [String: Any],
        service: SableLibraryService
    ) -> [String: Any]? {
        var creators: [String: Any] = [:]
        let authors = arrayStrings(sidecar["authors"], service: service)
        let artists = arrayStrings(sidecar["artists"], service: service)
        if !authors.isEmpty {
            creators["authors"] = authors
        }
        if !artists.isEmpty {
            creators["artists"] = artists
        }
        return creators.isEmpty ? nil : creators
    }

    private func readingURLsView(
        from sidecar: [String: Any],
        service: SableLibraryService
    ) -> [String: Any]? {
        var urls: [String: Any] = [:]
        let ids = normalizedIDDictionary(from: sidecar, service: service)

        if let coverURL = service.textValue(sidecar["cover_url"]) {
            urls["cover"] = coverURL
        }
        if let mangaBakaURL = service.textValue(sidecar["mangabaka_url"]) {
            urls["mangabaka"] = mangaBakaURL
        } else if let id = service.textValue(ids[idKey(for: .mangabaka)]) {
            urls["mangabaka"] = "https://mangabaka.org/\(id)"
        }
        if let id = service.textValue(ids[idKey(for: .ranobedb)]) {
            urls["ranobedb"] = "https://ranobedb.org/series/\(id)"
        }
        if let id = service.textValue(ids[idKey(for: .anilist)]) {
            urls["anilist"] = "https://anilist.co/manga/\(id)"
        }
        if let id = service.textValue(ids[idKey(for: .myAnimeList)]) {
            urls["myanimelist"] = "https://myanimelist.net/manga/\(id)"
        }
        if let id = service.textValue(ids[idKey(for: .openLibrary)]) {
            urls["openlibrary"] = id.hasPrefix("/")
                ? "https://openlibrary.org\(id)"
                : "https://openlibrary.org/\(id)"
        }

        let external = readingExternalLinks(from: sidecar, service: service)
        if !external.isEmpty {
            urls["external"] = external
        }

        return urls.isEmpty ? nil : urls
    }

    private func readingExternalLinks(
        from sidecar: [String: Any],
        service: SableLibraryService
    ) -> [[String: Any]] {
        guard let sable = sidecar["_sable"] as? [String: Any],
              let mangaBaka = sable[SableLibraryMetadataProvider.mangabaka.rawValue] as? [String: Any],
              let rows = mangaBaka["links_v2"] as? [[String: Any]] else {
            return []
        }

        var seen = Set<String>()
        return rows.compactMap { row -> [String: Any]? in
            guard let url = service.textValue(row["url"]),
                  seen.insert(url).inserted else {
                return nil
            }
            var link: [String: Any] = ["url": url]
            if let name = service.textValue(row["name_display"]) ?? service.textValue(row["name"]) {
                link["name"] = name
            }
            if let type = service.textValue(row["type"]) {
                link["type"] = type
            }
            if let language = service.textValue(row["language"]) {
                link["language"] = language
            }
            return link
        }
    }

    private func readingSourceQualityView(
        from sidecar: [String: Any],
        service: SableLibraryService
    ) -> [String: Any]? {
        var quality: [String: Any] = [:]
        if let source = service.textValue(sidecar["source"]) {
            quality["source"] = source
        }
        if let lastChecked = service.textValue(sidecar["last_checked"]) {
            quality["last_checked"] = lastChecked
        }

        if let sable = sidecar["_sable"] as? [String: Any] {
            if let enrichment = sable["metadata_enrichment"] as? [String: Any] {
                if let confidenceScore = doubleValue(enrichment["confidence_score"]) {
                    quality["confidence_score"] = roundedScore(confidenceScore)
                }
                if let outcome = service.textValue(enrichment["outcome"]) {
                    quality["outcome"] = outcome
                }
                let providers = arrayStrings(enrichment["providers"], service: service)
                if !providers.isEmpty {
                    quality["providers"] = providers
                }
            }

            if let ranobeDB = sable[SableLibraryMetadataProvider.ranobedb.rawValue] as? [String: Any] {
                if quality["confidence_score"] == nil,
                   let confidenceScore = doubleValue(ranobeDB["confidence_score"]) {
                    quality["confidence_score"] = roundedScore(confidenceScore)
                }
                if quality["outcome"] == nil,
                   let outcome = service.textValue(ranobeDB["outcome"]) {
                    quality["outcome"] = outcome
                }

                var providerDetails: [String: Any] = [:]
                if let apiSummary = ranobeDB["api_summary"] as? [String: Any] {
                    providerDetails["api_summary"] = apiSummary
                }
                if let seriesDetail = ranobeDB["series_detail"] as? [String: Any] {
                    providerDetails["series_detail"] = seriesDetail
                }
                if let bookDetail = ranobeDB["book_detail"] as? [String: Any] {
                    providerDetails["book_detail"] = bookDetail
                }
                if !providerDetails.isEmpty {
                    quality["ranobedb"] = providerDetails
                }
            }

            if let availability = sable["provider_availability"] as? [String: Any],
               !availability.isEmpty {
                quality["provider_availability"] = availability
            }
        }

        let freshness = readingFreshnessView(from: sidecar, service: service)
        if !freshness.isEmpty {
            quality["freshness"] = freshness
        }
        if let evidence = sidecar["match_evidence"] as? [[String: Any]],
           !evidence.isEmpty {
            quality["match_evidence"] = evidence
        }

        return quality.isEmpty ? nil : quality
    }

    private func readingFreshnessView(
        from sidecar: [String: Any],
        service: SableLibraryService
    ) -> [String: Any] {
        let rows = sidecar["source_freshness"] as? [[String: Any]] ?? []
        return rows.reduce(into: [String: Any]()) { partialResult, row in
            guard let provider = service.textValue(row["provider"]) else { return }
            if let fetchedAt = service.textValue(row["fetched_at"]) {
                partialResult[provider] = fetchedAt
            } else {
                partialResult[provider] = row
            }
        }
    }

    private func readingOrganizerView(
        from sidecar: [String: Any],
        service: SableLibraryService
    ) -> [String: Any]? {
        var organizer: [String: Any] = [:]
        if let plex = sidecar["plex"] as? [String: Any] {
            for key in ["root_folder", "series_folder_name", "series_path", "title_with_year", "source_id"] {
                if let value = plex[key] {
                    organizer[key] = value
                }
            }
        }
        if let sable = sidecar["_sable"] as? [String: Any],
           let source = sable["organizer_source"] as? [String: Any] {
            for key in ["folder_name", "clean_title", "title_with_year", "year", "year_preserved", "source_id"] where organizer[key] == nil {
                if let value = source[key] {
                    organizer[key] = value
                }
            }
        }
        return organizer.isEmpty ? nil : organizer
    }

    private func readingOriginView(
        from sidecar: [String: Any],
        service: SableLibraryService
    ) -> [String: Any]? {
        if let origin = service.textValue(sidecar["origin"]) {
            return [
                "name": origin,
                "evidence": "existing metadata"
            ]
        }

        let mediaType = service.textValue(sidecar["type"]) ?? ""
        let normalizedType = SableLibraryNamingPolicy().normalizedMediaType(mediaType)
        switch normalizedType {
        case "Manga":
            return ["name": "Japanese", "evidence": "form"]
        case "Manhwa":
            return ["name": "Korean", "evidence": "form"]
        case "Manhua":
            return ["name": "Chinese", "evidence": "form"]
        case "OEL":
            return ["name": "English-language", "evidence": "form"]
        default:
            break
        }

        guard let language = readingOriginalLanguage(from: sidecar, service: service),
              let origin = originName(forLanguage: language) else {
            return nil
        }
        return [
            "name": origin,
            "language": language,
            "evidence": "provider original language"
        ]
    }

    private func readingOriginalLanguage(
        from sidecar: [String: Any],
        service: SableLibraryService
    ) -> String? {
        guard let sable = sidecar["_sable"] as? [String: Any],
              let ranobeDB = sable[SableLibraryMetadataProvider.ranobedb.rawValue] as? [String: Any] else {
            return nil
        }
        let api = (ranobeDB["api_compact"] as? [String: Any])
            ?? (ranobeDB["api"] as? [String: Any])
        let series = api?["series"] as? [String: Any]
            ?? (api?["series_response"] as? [String: Any])?["series"] as? [String: Any]
        return service.textValue(series?["olang"])
            ?? service.textValue(series?["lang"])
    }

    private func originName(forLanguage language: String) -> String? {
        switch language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "ja", "jp", "jpn", "japanese":
            return "Japanese"
        case "ko", "kor", "korean":
            return "Korean"
        case "zh", "zho", "chi", "cn", "chinese":
            return "Chinese"
        case "en", "eng", "english":
            return "English-language"
        default:
            return nil
        }
    }

    private func compactStringList(_ key: String, in sidecar: inout [String: Any], service: SableLibraryService) {
        let rawValues = arrayStrings(sidecar[key], service: service)
        let values: [String]
        if sidecarDisplayMetadataTermKeys.contains(key) {
            values = uniqueStrings(service.displayMetadataTerms(rawValues))
        } else {
            values = uniqueStrings(rawValues)
        }
        if values.isEmpty {
            sidecar.removeValue(forKey: key)
        } else {
            sidecar[key] = values
        }
    }

    private var sidecarDisplayMetadataTermKeys: Set<String> {
        ["genres", "tags", "content_warnings"]
    }

    private enum LegacySubtitleDestination {
        case volumeTitles
        case episodeTitles
    }

    private func migrateLegacySubtitleField(
        in sidecar: inout [String: Any],
        mediaDomain: SableLibraryMediaDomain,
        service: SableLibraryService
    ) {
        let legacy = combinedStringList(from: sidecar, keys: ["subtitles"], service: service)
        guard !legacy.isEmpty else {
            sidecar.removeValue(forKey: "subtitles")
            return
        }

        let destination = inferredLegacySubtitleDestination(from: sidecar, preferredDomain: mediaDomain, service: service)
        switch destination {
        case .volumeTitles:
            if sidecar["volume_titles"] == nil {
                sidecar["volume_titles"] = legacy
            }
        case .episodeTitles:
            if sidecar["episode_titles"] == nil {
                sidecar["episode_titles"] = legacy
            }
        case nil:
            break
        }
        sidecar.removeValue(forKey: "subtitles")
    }

    private func inferredLegacySubtitleDestination(
        from sidecar: [String: Any],
        preferredDomain: SableLibraryMediaDomain,
        service: SableLibraryService
    ) -> LegacySubtitleDestination? {
        switch preferredDomain {
        case .reading:
            return .volumeTitles
        case .watching:
            return .episodeTitles
        case .unknown:
            break
        }

        if let volumeTitles = sidecar["volume_titles"], !arrayStrings(volumeTitles, service: service).isEmpty {
            return .volumeTitles
        }
        if let episodeTitles = sidecar["episode_titles"], !arrayStrings(episodeTitles, service: service).isEmpty {
            return .episodeTitles
        }

        if let rawType = service.textValue(sidecar["type"])?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            if isWatchingType(rawType) {
                return .episodeTitles
            }
            if isReadingType(rawType) {
                return .volumeTitles
            }
        }

        if let source = service.textValue(sidecar["source"])?.lowercased() {
            if source.contains("anilist") || source.contains("tvmaze") ||
                source.contains("tmdb") || source.contains("tvdb") || source.contains("imdb") ||
                source.contains("wikidata") {
                return .episodeTitles
            }
            if source.contains("mangabaka") || source.contains("ranobedb") || source.contains("openlibrary") {
                return .volumeTitles
            }
        }

        let ids = sourceIDs(from: sidecar, service: service)
        let readingProviderIDs = ids.contains { id in
            id.provider == .mangabaka || id.provider == .ranobedb || id.provider == .openLibrary
        }
        let watchingProviderIDs = ids.contains { id in
            id.provider == .anilist || id.provider == .tvmaze ||
            id.provider == .tvdb || id.provider == .tmdb || id.provider == .imdb || id.provider == .wikidata
        }

        if readingProviderIDs {
            return .volumeTitles
        }
        if watchingProviderIDs {
            return .episodeTitles
        }

        if sidecar["volumes"] != nil {
            return .volumeTitles
        }

        return nil
    }

    private func isWatchingType(_ type: String) -> Bool {
        let normalized = type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return switch normalized {
        case "animetv", "anime tv", "anime movie", "animemovie", "animeova", "ova", "ona", "special", "specials", "movie", "tvshow", "tv show", "tv":
            true
        default:
            false
        }
    }

    private func isReadingType(_ type: String) -> Bool {
        let normalized = type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return switch normalized {
        case "manga", "manhwa", "manhua", "novel", "lightnovel", "light novel", "oel", "book", "comic", "other":
            true
        default:
            false
        }
    }

    private func combinedStringList(
        from sidecar: [String: Any],
        keys: [String],
        service: SableLibraryService
    ) -> [String] {
        uniqueStrings(keys.flatMap { key in
            arrayStrings(sidecar[key], service: service)
        })
    }

    private func pruneRejectedProviderPublicTraces(
        in sidecar: inout [String: Any],
        service: SableLibraryService
    ) {
        guard let trace = rejectedProviderTrace(in: sidecar, service: service) else {
            return
        }

        pruneRejectedTitleVariants(in: &sidecar, trace: trace, service: service)
        pruneRejectedStringList("aliases", in: &sidecar, trace: trace, service: service)
        pruneRejectedProviderRows("match_evidence", in: &sidecar, trace: trace, service: service)
        pruneRejectedProviderRows("source_freshness", in: &sidecar, trace: trace, service: service)
    }

    private func pruneRejectedTitleVariants(
        in sidecar: inout [String: Any],
        trace: RejectedProviderTrace,
        service: SableLibraryService
    ) {
        let trusted = trustedTitleVariantMap(from: sidecar, service: service)
        let trustedValues = trusted.keys.sorted().flatMap { trusted[$0] ?? [] }
        let trustedKeys = Set(trustedValues.map { service.normalizeTerm($0) }.filter { !$0.isEmpty })
        let existing = normalizedTitleVariantMap(sidecar["title_variants"], service: service)
        var result = trusted

        for (key, values) in existing {
            for value in values where shouldKeepExistingTitleVariant(
                value,
                key: key,
                trustedValues: trustedValues,
                trustedKeys: trustedKeys,
                trace: trace,
                service: service
            ) {
                result[key, default: []].append(value)
            }
        }

        for key in Array(result.keys) {
            let values = uniqueTitleVariants(result[key] ?? [], service: service)
            if values.isEmpty {
                result.removeValue(forKey: key)
            } else {
                result[key] = values
            }
        }

        if result.isEmpty {
            sidecar.removeValue(forKey: "title_variants")
        } else {
            sidecar["title_variants"] = result
        }
    }

    private func pruneRejectedStringList(
        _ key: String,
        in sidecar: inout [String: Any],
        trace: RejectedProviderTrace,
        service: SableLibraryService
    ) {
        let trusted = trustedTitleVariantMap(from: sidecar, service: service)
        let trustedValues = trusted.keys.sorted().flatMap { trusted[$0] ?? [] }
        let trustedKeys = Set(trustedValues.map { service.normalizeTerm($0) }.filter { !$0.isEmpty })
        let values = arrayStrings(sidecar[key], service: service).filter { value in
            shouldKeepExistingTitleVariant(
                value,
                key: "english",
                trustedValues: trustedValues,
                trustedKeys: trustedKeys,
                trace: trace,
                service: service
            )
        }

        if values.isEmpty {
            sidecar.removeValue(forKey: key)
        } else {
            sidecar[key] = uniqueStrings(values)
        }
    }

    private func shouldKeepExistingTitleVariant(
        _ value: String,
        key: String,
        trustedValues: [String],
        trustedKeys: Set<String>,
        trace: RejectedProviderTrace,
        service: SableLibraryService
    ) -> Bool {
        let normalized = service.normalizeTerm(value)
        guard !normalized.isEmpty else { return false }
        if trace.titleKeys.contains(normalized) {
            return false
        }
        if trustedKeys.contains(normalized) {
            return true
        }
        if trace.titleKeys.contains(where: { rejectedKey in
            titleKeysAreCloselyRelated(normalized, rejectedKey)
        }) {
            return false
        }

        if !["english", "romanized", "native"].contains(key) {
            return true
        }

        guard !trustedValues.isEmpty else {
            return true
        }

        return trustedValues.contains { trustedValue in
            let trusted = service.normalizeTerm(trustedValue)
            return titleKeysLookLikeSameSeries(normalized, trusted)
        }
    }

    private func titleKeysAreCloselyRelated(_ lhs: String, _ rhs: String) -> Bool {
        guard !lhs.isEmpty, !rhs.isEmpty else { return false }
        return lhs == rhs
            || lhs.contains(rhs)
            || rhs.contains(lhs)
            || tokenSimilarity(lhs, rhs) >= 0.72
    }

    private func titleKeysLookLikeSameSeries(_ lhs: String, _ rhs: String) -> Bool {
        guard !lhs.isEmpty, !rhs.isEmpty else { return false }
        return lhs == rhs
            || lhs.contains(rhs)
            || rhs.contains(lhs)
            || tokenSimilarity(lhs, rhs) >= 0.45
    }

    private func pruneRejectedProviderRows(
        _ key: String,
        in sidecar: inout [String: Any],
        trace: RejectedProviderTrace,
        service: SableLibraryService
    ) {
        guard let rows = sidecar[key] as? [[String: Any]] else {
            return
        }

        let filtered = rows.filter { row in
            !rowMatchesRejectedProviderTrace(row, trace: trace, service: service)
        }
        if filtered.isEmpty {
            sidecar.removeValue(forKey: key)
        } else {
            sidecar[key] = filtered
        }
    }

    private func rowMatchesRejectedProviderTrace(
        _ row: [String: Any],
        trace: RejectedProviderTrace,
        service: SableLibraryService
    ) -> Bool {
        if let provider = service.textValue(row["provider"]),
           trace.providers.contains(normalizedProviderKey(provider)) {
            return true
        }
        guard !trace.titleKeys.isEmpty else {
            return false
        }
        return row.values.contains { value in
            valueMatchesRejectedTitle(value, trace: trace, service: service)
        }
    }

    private func valueMatchesRejectedTitle(
        _ value: Any,
        trace: RejectedProviderTrace,
        service: SableLibraryService
    ) -> Bool {
        if let text = service.textValue(value) {
            let normalized = service.normalizeTerm(text)
            return trace.titleKeys.contains(normalized)
                || trace.titleKeys.contains { rejectedKey in
                    titleKeysAreCloselyRelated(normalized, rejectedKey)
                }
        }
        if let values = value as? [String] {
            return values.contains { valueMatchesRejectedTitle($0, trace: trace, service: service) }
        }
        if let rows = value as? [[String: Any]] {
            return rows.contains { row in
                row.values.contains { valueMatchesRejectedTitle($0, trace: trace, service: service) }
            }
        }
        if let row = value as? [String: Any] {
            return row.values.contains { valueMatchesRejectedTitle($0, trace: trace, service: service) }
        }
        return false
    }

    private func trustedTitleVariantMap(
        from sidecar: [String: Any],
        service: SableLibraryService
    ) -> [String: [String]] {
        var variants: [String: [String]] = [:]

        func append(_ value: String?, to rawKey: String?) {
            guard let rawKey,
                  let key = normalizedTitleVariantKey(rawKey),
                  let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else {
                return
            }
            variants[key, default: []].append(value)
        }

        for key in ["preferred_title", "title", "local_title", "sort_title", "english_title"] {
            if let value = service.textValue(sidecar[key]), isLatinTitle(value) {
                append(value, to: "english")
            }
        }
        append(service.textValue(sidecar["romanized_title"]), to: "romanized")
        append(service.textValue(sidecar["native_title"]), to: "native")

        if let sable = sidecar["_sable"] as? [String: Any],
           let mangaBaka = sable[SableLibraryMetadataProvider.mangabaka.rawValue] as? [String: Any],
           let titleRows = mangaBaka["titles_v2"] as? [[String: Any]] {
            for row in titleRows {
                let title = service.textValue(row["title"])
                let language = service.textValue(row["language"])
                let traits = arrayStrings(row["traits"], service: service)
                append(title, to: mangaBakaTitleVariantKey(language: language, traits: traits, title: title))
            }
        }

        for key in Array(variants.keys) {
            let values = uniqueTitleVariants(variants[key] ?? [], service: service)
            if values.isEmpty {
                variants.removeValue(forKey: key)
            } else {
                variants[key] = values
            }
        }
        return variants
    }

    private func compactAliases(in sidecar: inout [String: Any], service: SableLibraryService) {
        let contributorNames = arrayStrings(sidecar["authors"], service: service)
            + arrayStrings(sidecar["artists"], service: service)
            + arrayStrings(sidecar["publishers"], service: service)
        let contributorKeys = Set(contributorNames.map { service.normalizeTerm($0) })
        let titleKeys = sidecarSeriesTitleKeys(in: sidecar, includeAliases: false, service: service)
        let aliases = uniqueStrings(arrayStrings(sidecar["aliases"], service: service).filter { alias in
            let normalized = service.normalizeTerm(alias)
            return !normalized.isEmpty
                && !contributorKeys.contains(normalized)
                && !titleKeys.contains(normalized)
        })
        if aliases.isEmpty {
            sidecar.removeValue(forKey: "aliases")
        } else {
            sidecar["aliases"] = aliases
        }
    }

    private func compactTitleVariants(in sidecar: inout [String: Any], service: SableLibraryService) {
        let variants = titleVariantMap(from: sidecar, keepExistingVariants: false, service: service)
        if variants.isEmpty {
            sidecar.removeValue(forKey: "title_variants")
        } else {
            sidecar["title_variants"] = variants
        }
    }

    private func compactSeriesAliasDump(_ key: String, in sidecar: inout [String: Any], service: SableLibraryService) {
        let titleKeys = sidecarSeriesTitleKeys(in: sidecar, service: service)
        let values = uniqueStrings(arrayStrings(sidecar[key], service: service).filter { value in
            let normalized = service.normalizeTerm(value)
            return !normalized.isEmpty && !titleKeys.contains(normalized)
        })

        if values.isEmpty {
            sidecar.removeValue(forKey: key)
        } else {
            sidecar[key] = values
        }
    }

    private func sidecarSeriesTitleKeys(in sidecar: [String: Any], service: SableLibraryService) -> Set<String> {
        sidecarSeriesTitleKeys(in: sidecar, includeAliases: true, service: service)
    }

    private func sidecarSeriesTitleKeys(
        in sidecar: [String: Any],
        includeAliases: Bool,
        service: SableLibraryService
    ) -> Set<String> {
        var values: [String] = []
        for key in ["title", "preferred_title", "local_title", "sort_title", "native_title", "romanized_title", "english_title"] {
            if let value = service.textValue(sidecar[key]) {
                values.append(value)
            }
        }
        values.append(contentsOf: titleVariantMap(from: sidecar, service: service).values.flatMap { $0 })
        if includeAliases {
            values.append(contentsOf: arrayStrings(sidecar["aliases"], service: service))
        }
        return Set(values.map { service.normalizeTerm($0) }.filter { !$0.isEmpty })
    }

    private func sidecarNeedsTitleVariantLabels(_ sidecar: [String: Any], service: SableLibraryService) -> Bool {
        let expected = titleVariantMap(from: sidecar, keepExistingVariants: false, service: service)
        guard !expected.isEmpty else { return false }
        let current = normalizedTitleVariantMap(sidecar["title_variants"], service: service)
        return current != expected
    }

    private func sidecarHasVolumeTitleVariants(_ sidecar: [String: Any], service: SableLibraryService) -> Bool {
        guard let rows = sidecar["title_variants"] as? [String: Any] else { return false }
        return rows.values.contains { value in
            arrayStrings(value, service: service).contains { !isSeriesLevelTitleVariant($0, service: service) }
        }
    }

    private func localTitleHasVolumeSuffix(_ sidecar: [String: Any], service: SableLibraryService) -> Bool {
        guard let localTitle = service.textValue(sidecar["local_title"]),
              let cleaned = seriesTitleWithoutVolumeSuffix(localTitle, service: service),
              cleaned != localTitle else {
            return false
        }
        return sidecarTitleMatches(cleaned, sidecar: sidecar, service: service)
    }

    private func titleVariantMap(from sidecar: [String: Any], service: SableLibraryService) -> [String: [String]] {
        titleVariantMap(from: sidecar, keepExistingVariants: true, service: service)
    }

    private func titleVariantMap(
        from sidecar: [String: Any],
        keepExistingVariants: Bool,
        service: SableLibraryService
    ) -> [String: [String]] {
        var english: [String] = []
        var romanized: [String] = []
        var native: [String] = []

        let existing = normalizedTitleVariantMap(sidecar["title_variants"], service: service)
        var localized: [String: [String]] = [:]

        func appendVariant(_ value: String?, to rawKey: String?) {
            guard let rawKey,
                  let key = normalizedTitleVariantKey(rawKey),
                  let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else {
                return
            }
            switch key {
            case "english":
                english.append(value)
            case "romanized":
                romanized.append(value)
            case "native":
                native.append(value)
            default:
                localized[key, default: []].append(value)
            }
        }

        if keepExistingVariants {
            english.append(contentsOf: existing["english"] ?? [])
            romanized.append(contentsOf: existing["romanized"] ?? [])
            native.append(contentsOf: existing["native"] ?? [])
            localized = existing.filter { entry in
                !["english", "romanized", "native"].contains(entry.key)
            }
        }

        for key in ["preferred_title", "title", "local_title", "sort_title", "english_title"] {
            if let value = service.textValue(sidecar[key]), isLatinTitle(value) {
                english.append(value)
            }
        }
        if let value = service.textValue(sidecar["romanized_title"]), isLatinTitle(value) {
            romanized.append(value)
        }
        if let value = service.textValue(sidecar["native_title"]) {
            native.append(value)
        }

        for alias in arrayStrings(sidecar["aliases"], service: service) {
            if containsCJK(alias) {
                native.append(alias)
            } else if likelyRomanizedReadingTitle(alias) {
                romanized.append(alias)
            } else if isLatinTitle(alias) {
                english.append(alias)
            }
        }

        if let sable = sidecar["_sable"] as? [String: Any],
           let mangaBaka = sable[SableLibraryMetadataProvider.mangabaka.rawValue] as? [String: Any],
           let titleRows = mangaBaka["titles_v2"] as? [[String: Any]] {
            for row in titleRows {
                let title = service.textValue(row["title"])
                let language = service.textValue(row["language"])
                let traits = arrayStrings(row["traits"], service: service)
                appendVariant(title, to: mangaBakaTitleVariantKey(language: language, traits: traits, title: title))
            }
        }

        native = uniqueTitleVariants(native, service: service)
        romanized = uniqueTitleVariants(romanized, excluding: native, service: service)
        for key in Array(localized.keys) {
            let values = uniqueTitleVariants(localized[key] ?? [], excluding: native + romanized, service: service)
            if values.isEmpty {
                localized.removeValue(forKey: key)
            } else {
                localized[key] = values
            }
        }
        let localizedValues = localized.keys.sorted().flatMap { localized[$0] ?? [] }
        english = uniqueTitleVariants(english, excluding: native + romanized + localizedValues, service: service)

        guard !native.isEmpty || !romanized.isEmpty || !localized.isEmpty else { return [:] }

        var result: [String: [String]] = [:]
        if !english.isEmpty {
            result["english"] = english
        }
        if !romanized.isEmpty {
            result["romanized"] = romanized
        }
        if !native.isEmpty {
            result["native"] = native
        }
        for key in localized.keys.sorted() {
            if let values = localized[key], !values.isEmpty {
                result[key] = values
            }
        }
        return result
    }

    private func normalizedTitleVariantMap(_ value: Any?, service: SableLibraryService) -> [String: [String]] {
        guard let rows = value as? [String: Any] else { return [:] }
        var result: [String: [String]] = [:]
        for (rawKey, rawValue) in rows {
            guard let key = normalizedTitleVariantKey(rawKey) else { continue }
            result[key, default: []].append(contentsOf: arrayStrings(rawValue, service: service).filter {
                isSeriesLevelTitleVariant($0, service: service)
            })
        }
        for key in Array(result.keys) {
            let values = uniqueTitleVariants(result[key] ?? [], service: service)
            if values.isEmpty {
                result.removeValue(forKey: key)
            } else {
                result[key] = values
            }
        }
        return result
    }

    private func compactLocalSeriesTitle(in sidecar: inout [String: Any], service: SableLibraryService) {
        guard let localTitle = service.textValue(sidecar["local_title"]),
              let cleaned = seriesTitleWithoutVolumeSuffix(localTitle, service: service),
              cleaned != localTitle,
              sidecarTitleMatches(cleaned, sidecar: sidecar, service: service) else {
            return
        }
        sidecar["local_title"] = cleaned
    }

    private func sidecarTitleMatches(_ value: String, sidecar: [String: Any], service: SableLibraryService) -> Bool {
        let normalized = service.normalizeTerm(value)
        guard !normalized.isEmpty else { return false }
        for key in ["preferred_title", "title", "sort_title", "english_title"] {
            if service.textValue(sidecar[key]).map({ service.normalizeTerm($0) == normalized }) == true {
                return true
            }
        }
        return false
    }

    private func seriesTitleWithoutVolumeSuffix(_ value: String, service: SableLibraryService) -> String? {
        let cleaned = value
            .replacingOccurrences(
                of: #"(?i)\s*,?\s*(?:vol(?:ume)?|book|ch(?:apter)?|v)\.?\s*\d{1,4}(?:\.\d+)?(?:\s*[-–—:]\s*.*)?(?:\s*\([^)]*\))?\s*$"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",-–—:")))
        guard !cleaned.isEmpty,
              service.normalizeTerm(cleaned) != service.normalizeTerm(value) else {
            return nil
        }
        return cleaned
    }

    private func normalizedTitleVariantKey(_ key: String) -> String? {
        let normalized = key
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
        switch normalized {
        case "english", "en":
            return "english"
        case "romaji", "romanized", "romanised", "ja-latn", "jp-latn":
            return "romanized"
        case "native",
             "japanese", "ja", "kanji", "kana",
             "korean", "ko", "hangul",
             "chinese", "zh", "zh-cn", "zh-hans", "zh-hant", "zh-hk", "zh-tw", "cn", "hanzi":
            return "native"
        case "arabic", "ar":
            return "arabic"
        case "italian", "it":
            return "italian"
        case "polish", "pl":
            return "polish"
        case "portuguese-brazil", "portuguese-brazilian", "portuguese (brazil)", "pt-br":
            return "portuguese_brazil"
        case "portuguese", "pt":
            return "portuguese"
        case "russian", "ru":
            return "russian"
        case "spanish", "es":
            return "spanish"
        case "french", "fr":
            return "french"
        case "german", "de":
            return "german"
        case "hungarian", "hu":
            return "hungarian"
        case "thai", "th":
            return "thai"
        case "turkish", "tr":
            return "turkish"
        case "ukrainian", "uk", "ua":
            return "ukrainian"
        case "vietnamese", "vi":
            return "vietnamese"
        case "korean-romanized", "ko-latn":
            return "romanized"
        case "chinese-romanized", "zh-latn":
            return "romanized"
        default:
            return nil
        }
    }

    private func uniqueTitleVariants(
        _ values: [String],
        excluding excluded: [String] = [],
        service: SableLibraryService
    ) -> [String] {
        let excludedKeys = Set(excluded.map { service.normalizeTerm($0) }.filter { !$0.isEmpty })
        return uniqueStrings(values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            guard !excludedKeys.contains(service.normalizeTerm(trimmed)) else { return nil }
            guard isSeriesLevelTitleVariant(trimmed, service: service) else { return nil }
            return trimmed
        })
    }

    private func isSeriesLevelTitleVariant(_ value: String, service: SableLibraryService) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.range(
            of: #"(?i)(?:^|[\s,;:–—-])(?:vol(?:ume)?|book|ch(?:apter)?|v)\.?\s*\d{1,4}(?:\.\d+)?(?:\s*[-–—:]\s*.*)?(?:\s*\([^)]*\))?\s*$"#,
            options: .regularExpression
        ) != nil {
            return false
        }
        let normalized = service.normalizeTerm(trimmed)
        if normalized.range(of: #"^(?:vol(?:ume)?|book|ch(?:apter)?|v)\s+\d{1,4}(?:\s+\d+)?$"#, options: .regularExpression) != nil {
            return false
        }
        return true
    }

    private func isLatinTitle(_ value: String) -> Bool {
        value.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil && !containsCJK(value)
    }

    private func normalizeSidecarCoverURL(in sidecar: inout [String: Any], service: SableLibraryService) {
        if let coverURL = service.textValue(sidecar["cover_url"]) ?? service.textValue(sidecar["coverURL"]) {
            sidecar["cover_url"] = coverURL
            sidecar.removeValue(forKey: "coverURL")
            return
        }

        if let coverURL = nestedSidecarCoverURL(in: sidecar, service: service) {
            sidecar["cover_url"] = coverURL
        }
    }

    private func nestedSidecarCoverURL(
        in sidecar: [String: Any],
        service: SableLibraryService
    ) -> String? {
        guard let cover = sidecar["cover"] as? [String: Any] else { return nil }
        if let url = service.textValue(cover["url"]) {
            return url
        }
        if let raw = cover["raw"] as? [String: Any],
           let url = service.textValue(raw["url"]) {
            return url
        }
        return nil
    }

    private func compactSableMetadata(in sidecar: inout [String: Any], service: SableLibraryService) {
        guard var sable = sidecar["_sable"] as? [String: Any] else { return }
        let ids = normalizedIDDictionary(from: sidecar, service: service)

        for provider in SableLibraryMetadataProvider.allCases {
            guard let providerBlock = sable[provider.rawValue] as? [String: Any],
                  isStaleUntouchedProviderNote(providerBlock, service: service) else {
                continue
            }
            sable.removeValue(forKey: provider.rawValue)
        }

        if let enrichment = sable["metadata_enrichment"] as? [String: Any],
           isStaleUntouchedProviderNote(enrichment, service: service) {
            sable.removeValue(forKey: "metadata_enrichment")
        }

        normalizeRanobeDBAPISummary(in: &sable, service: service)
        compactRanobeDBRawAPI(in: &sable, service: service)
        promoteRejectedProviderReviewsToAvailability(in: &sable, ids: ids, service: service)
        removeSableSearchHelperQueries(in: &sable, service: service)

        if var reviews = sable["provider_candidate_review"] as? [String: Any] {
            let availability = sable["provider_availability"] as? [String: Any] ?? [:]
            for provider in SableLibraryMetadataProvider.allCases where hasID(idKey(for: provider), in: ids, service: service) {
                reviews.removeValue(forKey: provider.rawValue)
            }
            for (key, value) in reviews {
                guard let review = value as? [String: Any],
                      isRejectedProviderReview(review, service: service) else {
                    continue
                }
                if let provider = metadataProvider(rawKey: key, review: review, service: service),
                   providerIsMarkedUnavailable(provider, in: availability, service: service) {
                    reviews.removeValue(forKey: key)
                    continue
                }
                guard !reviewHasSpecificRejectedCandidate(review, service: service) else {
                    continue
                }
                reviews.removeValue(forKey: key)
            }
            if reviews.isEmpty {
                sable.removeValue(forKey: "provider_candidate_review")
            } else {
                sable["provider_candidate_review"] = reviews
            }
        }

        if var availability = sable["provider_availability"] as? [String: Any] {
            for provider in SableLibraryMetadataProvider.allCases where hasID(idKey(for: provider), in: ids, service: service) {
                availability.removeValue(forKey: provider.rawValue)
            }
            if availability.isEmpty {
                sable.removeValue(forKey: "provider_availability")
            } else {
                sable["provider_availability"] = availability
            }
        }

        sable.removeValue(forKey: "ml")
        if sable.isEmpty {
            sidecar.removeValue(forKey: "_sable")
        } else {
            sidecar["_sable"] = sable
        }
    }

    private func promoteRejectedProviderReviewsToAvailability(
        in sable: inout [String: Any],
        ids: [String: Any],
        service: SableLibraryService
    ) {
        guard let reviews = sable["provider_candidate_review"] as? [String: Any] else {
            return
        }

        var availability = sable["provider_availability"] as? [String: Any] ?? [:]
        for (rawKey, value) in reviews {
            guard let review = value as? [String: Any],
                  isRejectedProviderReview(review, service: service),
                  let provider = metadataProvider(rawKey: rawKey, review: review, service: service),
                  !hasID(idKey(for: provider), in: ids, service: service) else {
                continue
            }

            let existing = availability[provider.rawValue] as? [String: Any]
            if let existing,
               !providerAvailabilityNoteIsUnavailable(existing, service: service) {
                continue
            }

            availability[provider.rawValue] = providerAvailabilityNote(
                for: provider,
                rejectedReview: review,
                existing: existing,
                service: service
            )
        }

        if !availability.isEmpty {
            sable["provider_availability"] = availability
        }
    }

    private func normalizeRanobeDBAPISummary(
        in sable: inout [String: Any],
        service: SableLibraryService
    ) {
        guard var ranobeDB = sable[SableLibraryMetadataProvider.ranobedb.rawValue] as? [String: Any],
              let api = ranobeDB["api"] as? [String: Any] else {
            return
        }
        ranobeDB["api_summary"] = ranobeDBAPISummary(from: api, service: service)
        sable[SableLibraryMetadataProvider.ranobedb.rawValue] = ranobeDB
    }

    private func compactRanobeDBRawAPI(
        in sable: inout [String: Any],
        service: SableLibraryService
    ) {
        guard var ranobeDB = sable[SableLibraryMetadataProvider.ranobedb.rawValue] as? [String: Any],
              let api = ranobeDB["api"] as? [String: Any] else {
            return
        }
        var summary = ranobeDBAPISummary(from: api, service: service)
        guard let compact = compactRanobeDBAPI(from: api, service: service) else {
            ranobeDB["api_summary"] = summary
            sable[SableLibraryMetadataProvider.ranobedb.rawValue] = ranobeDB
            return
        }

        if let compactData = jsonPayloadData(compact) {
            summary["compact_payload_bytes"] = compactData.count
            summary["compact_payload_digest"] = stableDigest(for: compactData)
            summary["compact_payload_digest_algorithm"] = stableDigestAlgorithm
        }
        summary["raw_payload_stored_in_sidecar"] = false

        ranobeDB["api_summary"] = summary
        ranobeDB["api_compact"] = compact
        ranobeDB.removeValue(forKey: "api")
        sable[SableLibraryMetadataProvider.ranobedb.rawValue] = ranobeDB
    }

    private func compactRanobeDBAPI(
        from api: [String: Any],
        service: SableLibraryService
    ) -> [String: Any]? {
        var compact: [String: Any] = [
            "schema_version": 1,
            "source": "ranobedb-compact"
        ]

        let series = api["series"] as? [String: Any]
            ?? (api["series_response"] as? [String: Any])?["series"] as? [String: Any]
        if let series,
           let compactSeries = compactRanobeDBObject(series, service: service) {
            compact["series"] = compactSeries
        }

        let bookRows = api["book_responses"] as? [[String: Any]] ?? []
        let compactBooks = bookRows.compactMap { row -> [String: Any]? in
            let response = row["response"] as? [String: Any] ?? row
            let book = response["book"] as? [String: Any] ?? response
            guard let compactBook = compactRanobeDBObject(book, service: service) else { return nil }

            var compactRow: [String: Any] = [
                "response": ["book": compactBook]
            ]
            if let number = integerValue(row["volume_number"]) ?? integerValue(book["sort_order"]) {
                compactRow["volume_number"] = number
            }
            return compactRow
        }
        if !compactBooks.isEmpty {
            compact["book_responses"] = compactBooks
            compact["book_response_count"] = compactBooks.count
        }

        return compact.count > 2 ? compact : nil
    }

    private func compactRanobeDBObject(
        _ object: [String: Any],
        service: SableLibraryService
    ) -> [String: Any]? {
        var compact: [String: Any] = [:]

        copyTextKeys(
            [
                "id",
                "title",
                "title_orig",
                "romaji",
                "romaji_orig",
                "description",
                "description_ja",
                "lang",
                "olang",
                "publication_status",
                "web_novel",
                "website",
                "wikidata_id",
                "bookwalker_id",
                "cover_url",
                "image_url"
            ],
            from: object,
            to: &compact,
            service: service
        )
        copyIntegerKeys(
            [
                "sort_order",
                "c_release_date",
                "release_date",
                "pages",
                "anidb_id",
                "anilist_id",
                "mal_id",
                "c_start_date",
                "c_end_date",
                "start_date",
                "end_date"
            ],
            from: object,
            to: &compact
        )

        if let bookDescription = object["book_description"] as? [String: Any] {
            var compactDescription: [String: Any] = [:]
            copyTextKeys(["description", "description_ja"], from: bookDescription, to: &compactDescription, service: service)
            if !compactDescription.isEmpty {
                compact["book_description"] = compactDescription
            }
        }

        if let image = object["image"] as? [String: Any] {
            var compactImage: [String: Any] = [:]
            copyTextKeys(["url", "filename"], from: image, to: &compactImage, service: service)
            if !compactImage.isEmpty {
                compact["image"] = compactImage
            }
        }

        copyStringArrayKeys(["aliases"], from: object, to: &compact, service: service)

        let tags = compactRanobeDBNamedRows(object["tags"] as? [[String: Any]], keys: ["name", "ttype", "type"], service: service)
        if !tags.isEmpty {
            compact["tags"] = tags
        }

        let staff = compactRanobeDBNamedRows(object["staff"] as? [[String: Any]], keys: ["name", "role_type"], service: service)
        if !staff.isEmpty {
            compact["staff"] = staff
        }

        let publishers = compactRanobeDBNamedRows(object["publishers"] as? [[String: Any]], keys: ["name"], service: service)
        if !publishers.isEmpty {
            compact["publishers"] = publishers
        }

        let titles = compactRanobeDBNamedRows(
            object["titles"] as? [[String: Any]],
            keys: ["lang", "title", "romaji"],
            service: service
        )
        if !titles.isEmpty {
            compact["titles"] = titles
        }

        let editions = compactRanobeDBEditions(object["editions"] as? [[String: Any]], service: service)
        if !editions.isEmpty {
            compact["editions"] = editions
        }

        let releases = compactRanobeDBReleases(object["releases"] as? [[String: Any]], service: service)
        if !releases.isEmpty {
            compact["releases"] = releases
        }

        return compact.isEmpty ? nil : compact
    }

    private func compactRanobeDBReleases(
        _ rows: [[String: Any]]?,
        service: SableLibraryService
    ) -> [[String: Any]] {
        (rows ?? []).compactMap { row in
            var compact: [String: Any] = [:]
            copyTextKeys(
                ["id", "lang", "isbn13", "description", "website", "amazon", "bookwalker", "rakuten"],
                from: row,
                to: &compact,
                service: service
            )
            copyIntegerKeys(["release_date", "pages"], from: row, to: &compact)
            return compact.isEmpty ? nil : compact
        }
    }

    private func compactRanobeDBEditions(
        _ rows: [[String: Any]]?,
        service: SableLibraryService
    ) -> [[String: Any]] {
        (rows ?? []).compactMap { row in
            var compact: [String: Any] = [:]
            let staff = compactRanobeDBNamedRows(row["staff"] as? [[String: Any]], keys: ["name", "role_type"], service: service)
            if !staff.isEmpty {
                compact["staff"] = staff
            }
            return compact.isEmpty ? nil : compact
        }
    }

    private func compactRanobeDBNamedRows(
        _ rows: [[String: Any]]?,
        keys: [String],
        service: SableLibraryService
    ) -> [[String: Any]] {
        (rows ?? []).compactMap { row in
            var compact: [String: Any] = [:]
            copyTextKeys(keys, from: row, to: &compact, service: service)
            copyIntegerKeys(
                ["id", "tag_id", "book_id", "series_id", "staff_id", "publisher_id"],
                from: row,
                to: &compact
            )
            copyBoolKeys(["official"], from: row, to: &compact)
            return compact.isEmpty ? nil : compact
        }
    }

    private func copyTextKeys(
        _ keys: [String],
        from source: [String: Any],
        to target: inout [String: Any],
        service: SableLibraryService
    ) {
        for key in keys {
            guard let value = service.textValue(source[key])?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else {
                continue
            }
            target[key] = value
        }
    }

    private func copyIntegerKeys(
        _ keys: [String],
        from source: [String: Any],
        to target: inout [String: Any]
    ) {
        for key in keys {
            if let value = integerValue(source[key]) {
                target[key] = value
            }
        }
    }

    private func copyBoolKeys(
        _ keys: [String],
        from source: [String: Any],
        to target: inout [String: Any]
    ) {
        for key in keys {
            if let value = boolValue(source[key]) {
                target[key] = value
            }
        }
    }

    private func copyStringArrayKeys(
        _ keys: [String],
        from source: [String: Any],
        to target: inout [String: Any],
        service: SableLibraryService
    ) {
        for key in keys {
            let values = arrayStrings(source[key], service: service)
            if !values.isEmpty {
                target[key] = values
            }
        }
    }

    private func ranobeDBAPISummary(
        from api: [String: Any],
        service: SableLibraryService
    ) -> [String: Any] {
        let series = api["series"] as? [String: Any]
            ?? (api["series_response"] as? [String: Any])?["series"] as? [String: Any]
        let bookRows = api["book_responses"] as? [[String: Any]] ?? []
        let bookResponseCount = integerValue(api["book_response_count"]) ?? bookRows.count
        let volumeNumbers = bookRows.compactMap { integerValue($0["volume_number"]) }.sorted()
        let rawPayloadData = jsonPayloadData(api)

        var summary: [String: Any] = [
            "stores_full_series_payload": series != nil,
            "stored_book_payload_count": bookResponseCount,
            "epub_sync_fields": [
                "book descriptions",
                "staff contributors",
                "release links",
                "ISBNs",
                "publishers",
                "languages",
                "release dates",
                "tags"
            ]
        ]
        if let rawPayloadData {
            summary["raw_payload_bytes"] = rawPayloadData.count
            summary["raw_payload_digest"] = stableDigest(for: rawPayloadData)
            summary["raw_payload_digest_algorithm"] = stableDigestAlgorithm
            summary["raw_payload_stored_in_sidecar"] = true
        }
        if let series {
            summary["series_field_count"] = series.count
            if let id = service.textValue(series["id"]) {
                summary["series_id"] = id
            }
        }
        if !volumeNumbers.isEmpty {
            summary["stored_book_volume_numbers"] = volumeNumbers
        }
        return summary
    }

    private func providerIsMarkedUnavailable(
        _ provider: SableLibraryMetadataProvider,
        in availability: [String: Any],
        service: SableLibraryService
    ) -> Bool {
        guard let note = availability[provider.rawValue] as? [String: Any] else {
            return false
        }
        return providerAvailabilityNoteIsUnavailable(note, service: service)
    }

    private func providerAvailabilityNoteIsUnavailable(
        _ note: [String: Any],
        service: SableLibraryService
    ) -> Bool {
        service.textValue(note["status"])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() == "not_available"
    }

    private func providerAvailabilityNote(
        for provider: SableLibraryMetadataProvider,
        rejectedReview review: [String: Any],
        existing: [String: Any]?,
        service: SableLibraryService
    ) -> [String: Any] {
        var note = existing ?? [:]
        note["status"] = "not_available"
        note["provider"] = provider.rawValue
        if service.textValue(note["source"]) == nil {
            note["source"] = "cleaner_rejected_candidate"
        }
        if service.textValue(note["reason"]) == nil {
            note["reason"] = service.textValue(review["reason"])
                ?? "Rejected provider candidate kept out of public metadata."
        }
        note["updated_at"] = service.textValue(review["updated_at"])
            ?? service.textValue(note["updated_at"])
            ?? service.isoTimestamp()

        copyTextValue("query", from: review, to: &note, service: service)
        copyTextValue("rejected_candidate_id", from: review, to: &note, service: service)
        copyTextValue("rejected_candidate_title", from: review, to: &note, service: service)
        copyTextValue("source", from: review, to: &note, as: "rejected_source", service: service)
        copyNumericValue("confidence_score", from: review, to: &note)
        copyNumericValue("confidence_percent", from: review, to: &note)
        return note
    }

    private func copyTextValue(
        _ key: String,
        from source: [String: Any],
        to destination: inout [String: Any],
        as destinationKey: String? = nil,
        service: SableLibraryService
    ) {
        guard let value = service.textValue(source[key]) else {
            return
        }
        destination[destinationKey ?? key] = value
    }

    private func copyNumericValue(
        _ key: String,
        from source: [String: Any],
        to destination: inout [String: Any]
    ) {
        if let value = source[key] as? NSNumber {
            destination[key] = value
        }
    }

    private func rejectedProviderSourceIDKeys(
        in sidecar: [String: Any],
        service: SableLibraryService
    ) -> Set<String> {
        guard let sable = sidecar["_sable"] as? [String: Any],
              let reviews = sable["provider_candidate_review"] as? [String: Any] else {
            return []
        }

        var keys = Set<String>()
        for (rawKey, value) in reviews {
            guard let review = value as? [String: Any],
                  isRejectedProviderReview(review, service: service),
                  let provider = metadataProvider(rawKey: rawKey, review: review, service: service),
                  let rejectedID = specificRejectedCandidateID(in: review, service: service) else {
                continue
            }
            keys.insert(sourceIDKey(SableLibrarySourceID(provider: provider, value: rejectedID)))
        }
        return keys
    }

    private func sourceIDKey(_ sourceID: SableLibrarySourceID) -> String {
        "\(sourceID.provider.rawValue):\(sourceID.value.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    private func reviewHasSpecificRejectedCandidate(
        _ review: [String: Any],
        service: SableLibraryService
    ) -> Bool {
        specificRejectedCandidateID(in: review, service: service) != nil
    }

    private func specificRejectedCandidateID(
        in review: [String: Any],
        service: SableLibraryService
    ) -> String? {
        for key in ["rejected_candidate_id", "candidate_id"] {
            if let value = service.textValue(review[key])?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private func removeSableSearchHelperQueries(
        in sable: inout [String: Any],
        service: SableLibraryService
    ) {
        for provider in SableLibraryMetadataProvider.allCases {
            guard var providerBlock = sable[provider.rawValue] as? [String: Any],
                  service.textValue(providerBlock["query"]) != nil else {
                continue
            }
            providerBlock.removeValue(forKey: "query")
            if providerBlock.isEmpty {
                sable.removeValue(forKey: provider.rawValue)
            } else {
                sable[provider.rawValue] = providerBlock
            }
        }
    }

    private func isStaleUntouchedProviderNote(
        _ note: [String: Any],
        service: SableLibraryService
    ) -> Bool {
        let outcome = service.textValue(note["outcome"])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if outcome == SableLibraryQuietOutcome.leaveUntouched.rawValue.lowercased()
            || outcome == "leave_untouched"
            || outcome == "skipped"
            || outcome == "skip" {
            return true
        }

        let reason = service.textValue(note["reason"])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        return reason.contains("failed refresh") || reason.contains("old skipped")
    }

    private func reportText(applied: [String], skipped: [String]) -> String {
        var lines = [
            "Sable's Library sidecar apply",
            "============================",
            "Applied sidecar writes: \(applied.count)",
            "Skipped: \(skipped.count)"
        ]
        if !applied.isEmpty {
            lines.append("")
            lines.append("Applied:")
            lines.append(contentsOf: applied.map { "- \($0)" })
        }
        if !skipped.isEmpty {
            lines.append("")
            lines.append("Skipped:")
            lines.append(contentsOf: skipped.map { "- \($0)" })
        }
        return lines.joined(separator: "\n")
    }

    private func exactIDBatchReportText(applied: [String], skipped: [String]) -> String {
        var lines = [
            "Sable's Library exact-ID metadata refresh",
            "=========================================",
            "Applied sidecar refreshes: \(applied.count)",
            "Skipped: \(skipped.count)",
            "",
            "Only rows with saved provider IDs are included. Rows that need title search, provider matching, or manual review stay untouched.",
            "Reading rows run in provider passes, so IDs learned from one provider can feed the next provider in the same batch."
        ]
        if !applied.isEmpty {
            lines.append("")
            lines.append("Applied:")
            lines.append(contentsOf: applied.map { "- \($0)" })
        }
        if !skipped.isEmpty {
            lines.append("")
            lines.append("Skipped:")
            lines.append(contentsOf: skipped.map { "- \($0)" })
        }
        return lines.joined(separator: "\n")
    }
}

private struct MangaBakaQueryPlan {
    var titles: [String]
    var mediaTypeHint: String?
    var usesPreferredTypeFallback: Bool
    var localMediaTypeHint: String?
    var localBookCount: Int
    var localHighestVolume: Int?
}

private struct MangaBakaCreateCaution {
    var reason: String
    var confidence: LibraryPlanConfidence
    var safety: LibraryPlanSafety
    var decision: LibraryPlanDecision
    var requiresReview: Bool
    var confidenceExplanation: String
}

private struct ComicInfoRefreshCandidate {
    var series: LibrarySeriesSnapshot
    var staleReason: Bool
    var typeMismatch: Bool
    var missingMangaBakaV2Metadata: Bool
    var retryReason: String?
}

private struct SidecarLocalFileSnapshot: Sendable {
    var bookItems: [LibraryItem] = []
    var videoItems: [LibraryItem] = []
}

private struct SidecarBookMetadataHints: Sendable {
    var titles: [String] = []
    var authors: [String] = []
    var publishers: [String] = []
    var isbn13: [String] = []
    var sourceIDs: [SableLibrarySourceID] = []
    var year: Int?

    var hasBookProviderClues: Bool {
        !authors.isEmpty || !publishers.isEmpty || !isbn13.isEmpty || !sourceIDs.isEmpty || year != nil
    }
}

private struct ReadingProviderRoute {
    var providers: [SableLibraryMetadataProvider]
    var requiresReview: Bool
    var explanation: String
    var reviewTags: [String]
}

private struct MangaBakaMatchAssessment {
    var candidate: [String: Any]
    var queryTitle: String
    var matchedTitle: String
    var expectedMediaType: String?
    var overallScore: Double
    var titleScore: Double
    var semanticScore: Double?
    var localHighestVolume: Int?
    var candidateFinalVolume: Int?
    var hasFinalVolumeConflict: Bool
    var typeMatched: Bool
    var confidence: LibraryPlanConfidence
    var resultCount: Int = 0
    var plausiblePeerCount: Int = 0
    var broadTitlePeerCount: Int = 0
    var nearestScoreGap: Double?
    var manualSeriesID: String?

    var isConfidentEnoughToWrite: Bool {
        guard expectedMediaType == nil || typeMatched else { return false }
        return confidence == .high || confidence == .medium
    }

    var explanation: String {
        var parts = [
            "\(confidenceLabel): title score \(formatted(titleScore))",
            "overall \(formatted(overallScore))"
        ]
        if let manualSeriesID {
            parts.append("manual MangaBaka ID \(manualSeriesID)")
        }
        if let semanticScore {
            parts.append("ML similarity \(formatted(semanticScore))")
        } else {
            parts.append("ML similarity unavailable")
        }
        if let expectedMediaType {
            parts.append(typeMatched ? "type matched \(expectedMediaType)" : "expected \(expectedMediaType) not confirmed")
        } else {
            parts.append("no type hint used")
        }
        if hasFinalVolumeConflict,
           let localHighestVolume,
           let candidateFinalVolume {
            parts.append("local Vol \(localHighestVolume) is ahead of catalog final volume \(candidateFinalVolume)")
        }
        if resultCount > 0 {
            parts.append("\(plausiblePeerCount) plausible match\(plausiblePeerCount == 1 ? "" : "es") among \(resultCount) result\(resultCount == 1 ? "" : "s")")
        }
        if broadTitlePeerCount > plausiblePeerCount {
            parts.append("\(broadTitlePeerCount) broad title match\(broadTitlePeerCount == 1 ? "" : "es") before type checks")
        }
        return parts.joined(separator: "; ")
    }

    private var confidenceLabel: String {
        switch confidence {
        case .high: "Likely"
        case .medium: "Check"
        case .low: "Unsure"
        case .unknown: "Unknown"
        }
    }

    private func formatted(_ score: Double) -> String {
        String(format: "%.2f", score)
    }
}

private enum MangaBakaLookupError: LocalizedError {
    case invalidURL
    case invalidResponse
    case requestFailed(Int)
    case noMatch(String)
    case noConfidentMatch(String)
    case ambiguousMatch(String, Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "MangaBaka search URL could not be built."
        case .invalidResponse:
            "MangaBaka returned an unreadable response."
        case .requestFailed(let status):
            "MangaBaka request failed with status \(status)."
        case .noMatch(let query):
            "No MangaBaka match found for \(query)."
        case .noConfidentMatch(let query):
            "No confident MangaBaka match found for \(query)."
        case .ambiguousMatch(let query, let count):
            count >= 3
                ? "Warning: MangaBaka found \(count) similar possible series for \(query). Skipped without writing ComicInfo.json."
                : "Warning: MangaBaka found several close possible series for \(query). Skipped without writing ComicInfo.json."
        }
    }
}

private enum ComicInfoProviderCreateError: LocalizedError {
    case noConfidentProviderIdentity(String)

    var errorDescription: String? {
        switch self {
        case .noConfidentProviderIdentity(let query):
            "No confident MangaBaka, RanobeDB, or AniList match found for \(query). Skipped without writing ComicInfo.json."
        }
    }
}

private enum ReadingCatalogLane {
    case lightNovel
    case manga
}
