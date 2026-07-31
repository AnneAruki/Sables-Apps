//
//  SableLibraryPipelineIntelligence.swift
//  Sable's Library
//

import Foundation
#if canImport(CoreML)
import CoreML
#endif

struct LibraryPipelineIntelligenceNote: Sendable, Equatable {
    var summary: String
    var confidenceNote: String
    var riskNote: String
    var suggestedCorrectionReason: LibraryPlanCorrectionOption?

    static let empty = LibraryPipelineIntelligenceNote(
        summary: "",
        confidenceNote: "",
        riskNote: "",
        suggestedCorrectionReason: nil
    )
}

struct SableLibraryPipelineIntelligence: Sendable {
    func inspectionSummary(for inspection: LibraryInspection, options: SableLibraryIntelligenceOptions) async -> String? {
        guard options.improveSuggestions else { return nil }
        if let hint = localModelHint(for: inspection, options: options) {
            return hint
        }
        return SableLibraryIntelligence.unavailableNote(options: options)
    }

    func inspectionNote(for inspection: LibraryInspection, options: SableLibraryIntelligenceOptions) async -> LibraryPipelineIntelligenceNote? {
        guard options.improveSuggestions else { return nil }
        let missingSidecars = inspection.missingComicInfoCount + inspection.missingAnimeInfoCount
        let watchingText = inspection.videoSeriesCount > 0
            ? ", \(inspection.videoFileCount) video file(s), \(inspection.videoSeriesCount) watching group(s)"
            : ""
        let summary = inspection.verification?.message
            ?? "\(inspection.bookFileCount) book file(s), \(inspection.seriesCount) reading group(s)\(watchingText), \(missingSidecars) missing ComicInfo or AnimeInfo file(s)."
        let risk = inspection.duplicateGroupCount > 0 ? "\(inspection.duplicateGroupCount) duplicate group(s) need review." : ""
        let fallback = SableLibraryIntelligence.unavailableNote(options: options)
        let confidence = [
            inspection.inspectMode.title,
            SableLibraryMLCompany.operatingNote(for: inspection.inspectMode),
            localModelHint(for: inspection, options: options)
        ]
            .compactMap { $0 }
            .joined(separator: " ")
        let riskNote = [risk, fallback]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " ")
        return LibraryPipelineIntelligenceNote(
            summary: summary,
            confidenceNote: confidence,
            riskNote: riskNote,
            suggestedCorrectionReason: nil
        )
    }

    func confidenceNote(for item: LibraryPlanItem, options: SableLibraryIntelligenceOptions) async -> String? {
        guard options.improveSuggestions else { return nil }
        let localHints = localModelHints(for: item, options: options)
        guard item.confidence != .high || !localHints.isEmpty else { return nil }
        return [
            item.confidence == .high ? nil : "Review this because confidence is \(item.confidence.rawValue) and safety is \(item.safety.rawValue).",
            localHints.joined(separator: " ")
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }

    func reviewNote(for item: LibraryPlanItem, options: SableLibraryIntelligenceOptions) async -> LibraryPipelineIntelligenceNote? {
        guard options.improveSuggestions else { return nil }
        let suggestedCorrection: LibraryPlanCorrectionOption?
        switch item.operation {
        case .sortIntoFolder:
            suggestedCorrection = .wrongSeries
        case .renameFile, .cleanRawName:
            suggestedCorrection = .badNumber
        case .createComicInfo, .refreshComicInfo, .createAnimeInfo, .refreshAnimeInfo, .renameFolder:
            suggestedCorrection = .wrongType
        case .inspectOnly, .repairEpubPackage, .repairAppleBooksCompatibility, .duplicateDecision, .skip:
            suggestedCorrection = nil
        }

        let localHints = localModelHints(for: item, options: options)
        let fallback = SableLibraryIntelligence.unavailableNote(options: options)
        let confidenceNote = ([item.confidenceExplanation, SableLibraryMLCompany.handoffNote(for: item)] + localHints)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let riskNote = [
            item.requiresReview ? "Needs review before apply." : "",
            SableLibraryMLCompany.safetyNote(for: item) ?? "",
            fallback ?? ""
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " ")

        return LibraryPipelineIntelligenceNote(
            summary: item.reason,
            confidenceNote: confidenceNote,
            riskNote: riskNote,
            suggestedCorrectionReason: suggestedCorrection
        )
    }

    private func localModelHint(for inspection: LibraryInspection, options: SableLibraryIntelligenceOptions) -> String? {
        guard options.useLocalLearning else { return nil }
        var features = [
            "privacy_anonymized",
            "stage", LibraryPipelineStage.inspect.rawValue,
            "book_count_\(bucket(inspection.bookFileCount))",
            "series_count_\(bucket(inspection.seriesCount))",
            "video_count_\(bucket(inspection.videoFileCount))",
            "watching_series_count_\(bucket(inspection.videoSeriesCount))",
            "missing_sidecar_count_\(bucket(inspection.missingComicInfoCount + inspection.missingAnimeInfoCount))",
            inspection.duplicateGroupCount > 0 ? "has_duplicates" : "no_duplicates",
            inspection.packageBookCount > 0 ? "has_epub_package" : "no_epub_package",
            inspection.missingComicInfoCount > 0 ? "missing_comicinfo" : "has_comicinfo_coverage",
            inspection.missingAnimeInfoCount > 0 ? "missing_animeinfo" : "has_animeinfo_coverage",
            inspectModeToken(inspection.inspectMode)
        ]
        features.append(contentsOf: SableLibraryMLCompany.featureTokens(for: inspection.inspectMode))
        return SableLibraryBundledDecisionModel.shared.hint(for: .inspection, featureText: features.joined(separator: " "))
    }

    private func localModelHints(for item: LibraryPlanItem, options: SableLibraryIntelligenceOptions) -> [String] {
        guard options.useLocalLearning else { return [] }
        var features = [
            "privacy_anonymized",
            "stage", item.stage.rawValue,
            "operation", item.operation.rawValue,
            "safety", item.safety.rawValue,
            "confidence", item.confidence.rawValue,
            "domain", domainToken(for: item),
            "source_extension", extensionToken(in: item.currentPath),
            "destination_root", destinationRoot(in: item.proposedPath),
            "destination_family", destinationFamily(in: item.proposedPath),
            "provider", providerToken(for: item),
            item.usedNetworkData ? "uses_network" : "local_only",
            item.requiresReview ? "requires_review" : "auto_checked",
            item.reviewTags.joined(separator: " ")
        ]
        features.append(contentsOf: SableLibraryMLCompany.featureTokens(for: item))
        let task = modelTask(for: item)
        var hints: [String] = []
        if let hint = SableLibraryBundledDecisionModel.shared.hint(for: task, featureText: features.joined(separator: " ")) {
            hints.append(hint)
        }
        if let taggerTask = nameTaggerTask(for: item),
           let hint = SableLibraryBundledDecisionModel.shared.nameTagHint(
            for: taggerTask,
            text: nameTaggerText(for: item)
           ) {
            hints.append(hint)
        }
        for recommenderTask in recommenderTasks(for: item) {
            if let hint = SableLibraryBundledDecisionModel.shared.recommendationHint(
                for: recommenderTask,
                items: recommenderItems(for: item),
                restrict: recommendationRestrictList(for: recommenderTask)
            ) {
                hints.append(hint)
            }
        }
        return Array(hints.prefix(4))
    }

    private func domainToken(for item: LibraryPlanItem) -> String {
        if item.operation == .createAnimeInfo || item.operation == .refreshAnimeInfo {
            return SableLibraryMediaDomain.watching.rawValue
        }
        if item.operation == .createComicInfo || item.operation == .refreshComicInfo {
            return SableLibraryMediaDomain.reading.rawValue
        }
        if item.reviewTags.contains(where: { $0.hasPrefix("raw-reading-") }) {
            return SableLibraryMediaDomain.reading.rawValue
        }
        if item.reviewTags.contains("cleanup-kind-watching") {
            return SableLibraryMediaDomain.watching.rawValue
        }
        return SableLibraryMediaDomain.unknown.rawValue
    }

    private func extensionToken(in path: String) -> String {
        let ext = (path as NSString).pathExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return ext.isEmpty ? "none" : ext
    }

    private func destinationRoot(in path: String?) -> String {
        path?
            .split(separator: "/", omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? "none"
    }

    private func destinationFamily(in path: String?) -> String {
        let parts = path?.split(separator: "/", omittingEmptySubsequences: true).map(String.init) ?? []
        guard parts.count > 1 else { return "none" }
        return parts[1]
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    private func providerToken(for item: LibraryPlanItem) -> String {
        item.metadataProviders.first?.rawValue ?? (item.usedNetworkData ? "network" : "local")
    }

    private func modelTask(for item: LibraryPlanItem) -> SableLibraryMLHintTask {
        switch item.operation {
        case .repairEpubPackage, .repairAppleBooksCompatibility:
            return .epubRepair
        case .createComicInfo, .refreshComicInfo, .createAnimeInfo, .refreshAnimeInfo:
            if isMetadataCleanerItem(item) {
                return .metadataClean
            }
            return .sidecar
        case .renameFolder:
            if isShelfCatalogItem(item) {
                return .shelfCatalog
            }
            return .namingMove
        case .renameFile, .cleanRawName:
            return .namingMove
        case .duplicateDecision:
            return .reviewManagement
        case .sortIntoFolder:
            if isShelfCatalogItem(item) {
                return .shelfCatalog
            }
            if item.reviewTags.contains(where: { $0.hasPrefix("raw-reading-") }) {
                return .reading
            }
            return .rawCleanup
        case .inspectOnly:
            return .inspection
        case .skip:
            return .reviewManagement
        }
    }

    private func nameTaggerTask(for item: LibraryPlanItem) -> SableLibraryMLNameTaggerTask? {
        switch item.operation {
        case .repairEpubPackage, .repairAppleBooksCompatibility:
            return .reading
        case .createComicInfo, .refreshComicInfo:
            return .reading
        case .createAnimeInfo, .refreshAnimeInfo:
            return .video
        case .renameFile, .cleanRawName, .sortIntoFolder, .renameFolder:
            break
        case .inspectOnly, .duplicateDecision, .skip:
            return nil
        }

        let ext = extensionToken(in: item.currentPath)
        if item.reviewTags.contains(where: { $0.hasPrefix("raw-reading-") })
            || ["epub", "mobi", "azw3", "cbz", "cbr", "cb7", "cbt", "djvu"].contains(ext) {
            return .reading
        }
        if item.reviewTags.contains("cleanup-kind-watching")
            || ["mkv", "mp4", "mov", "avi", "m4v", "webm", "srt", "ass", "vtt"].contains(ext) {
            return .video
        }
        if item.reviewTags.contains("pdf-triage")
            || item.reviewTags.contains("likely-document")
            || item.proposedPath?.hasPrefix("Documents/") == true
            || ["pdf", "doc", "docx", "pages", "rtf", "txt", "md", "xml", "csv", "xlsx", "pptx"].contains(ext) {
            return .document
        }
        return nil
    }

    private func nameTaggerText(for item: LibraryPlanItem) -> String {
        [
            fileName(in: item.currentPath),
            item.proposedPath.flatMap { fileName(in: $0) }
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }

    private func fileName(in path: String) -> String? {
        let name = (path as NSString).lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    private func recommenderTasks(for item: LibraryPlanItem) -> [SableLibraryMLRecommenderTask] {
        var tasks: [SableLibraryMLRecommenderTask] = [.reviewAction]
        let task = modelTask(for: item)
        if task == .provider || task == .sidecar || task == .metadataClean || task == .shelfCatalog || task == .reading || task == .epubRepair || !item.metadataProviders.isEmpty {
            tasks.append(.providerRanking)
        }
        switch item.operation {
        case .sortIntoFolder, .renameFolder, .renameFile, .cleanRawName, .duplicateDecision:
            tasks.append(.folderGrouping)
        case .inspectOnly, .repairEpubPackage, .repairAppleBooksCompatibility, .createComicInfo, .refreshComicInfo, .createAnimeInfo, .refreshAnimeInfo, .skip:
            break
        }
        var seen = Set<SableLibraryMLRecommenderTask>()
        return tasks.filter { seen.insert($0).inserted }
    }

    private func recommenderItems(for item: LibraryPlanItem) -> [String: Double] {
        var items: [String: Double] = [:]

        func add(_ token: String, weight: Double = 3) {
            guard !token.isEmpty else { return }
            let key = "signal.\(token)"
            items[key] = max(items[key] ?? 0, weight)
        }

        add("stage.\(item.stage.rawValue)", weight: 5)
        add("operation.\(item.operation.rawValue)", weight: 3)
        add("safety.\(item.safety.rawValue)", weight: 3)
        add("confidence.\(item.confidence.rawValue)", weight: 2)
        add("domain.\(domainToken(for: item))", weight: 4)
        for token in SableLibraryMLCompany.featureTokens(for: item) {
            add(token, weight: 4)
        }

        if item.confidence == .high { add("strong", weight: 3) }
        if item.safety == .collision { add("collision", weight: 5) }
        if item.safety == .needsChoice { add("review", weight: 3) }
        if item.reviewTags.contains("missing-number") { add("missing.number", weight: 5) }

        for provider in item.metadataProviders {
            add("provider.\(provider.rawValue)", weight: 5)
        }
        if item.usedNetworkData, item.metadataProviders.isEmpty {
            add("provider.network", weight: 2)
        }

        let ext = extensionToken(in: item.currentPath)
        if ext != "none" {
            add("ext.\(ext)", weight: 1)
        }

        for tag in item.reviewTags {
            if let signal = recommenderSignal(forReviewTag: tag) {
                add(signal, weight: 4)
            }
        }

        switch item.operation {
        case .sortIntoFolder:
            add("raw.reading", weight: item.reviewTags.contains("raw-reading-lane") ? 5 : 2)
        case .renameFolder:
            add("task.folderRename", weight: 4)
        case .renameFile, .cleanRawName:
            add("task.fileRename", weight: 4)
        case .repairEpubPackage, .repairAppleBooksCompatibility:
            add("task.epubRepair", weight: 4)
        case .createComicInfo, .refreshComicInfo, .createAnimeInfo, .refreshAnimeInfo:
            add("task.jsonSidecar", weight: 4)
        case .inspectOnly, .duplicateDecision, .skip:
            break
        }

        return items
    }

    private func recommenderSignal(forReviewTag tag: String) -> String? {
        if let value = tag.removingPrefix("raw-reading-") {
            return "reading.\(value)"
        }
        if let value = tag.removingPrefix("cleanup-kind-") {
            return value == "watching" ? "cleanup.video" : "cleanup.\(value)"
        }
        switch tag {
        case "likely-document":
            return "pdf.document"
        case "likely-book":
            return "pdf.book"
        case "pdf-triage":
            return "pdf.document"
        case "epub-repair", "epub-package-repair":
            return "task.epubRepair"
        case "provider-ambiguous":
            return "provider.ambiguous"
        case "metadata-pass":
            return "metadata.pass"
        case "metadata-pass-identity":
            return "metadata.identity"
        case "metadata-pass-detail":
            return "metadata.detail"
        case "metadata-pass-refresh":
            return "metadata.refresh"
        case "metadata-checkpoint-choice":
            return "metadata.choice"
        case "metadata-checkpoint-identity":
            return "metadata.identity"
        case "metadata-checkpoint-detail":
            return "metadata.detail"
        case "metadata-checkpoint-refresh":
            return "metadata.refresh"
        case "metadata-checkpoint-watching":
            return "metadata.watching"
        case "metadata-provider-identity-mangabaka":
            return "provider.mangabaka.identity"
        case "metadata-provider-ranobedb-series":
            return "provider.ranobedb.series"
        case "metadata-provider-ranobedb-books":
            return "provider.ranobedb.books"
        case "metadata-provider-openlibrary":
            return "provider.openLibrary.supporting"
        case "metadata-provider-watching":
            return "provider.watching"
        case "provider-route-needs-choice", "needs-provider-choice":
            return "provider.choiceNeeded"
        case "manual-provider-match":
            return "provider.matchStrong"
        case "training-material":
            return "review.trainingMaterial"
        case "bulk-raw-review":
            return "review.bulkRawReview"
        case "naming-folder-rename":
            return "task.folderRename"
        case "naming-title-change":
            return "review.titleChange"
        case "naming-punctuation-only":
            return "review.lowVisibilityChange"
        case "naming-provider-token-change":
            return "provider.idChange"
        case "naming-provider-token-preserved":
            return "provider.idPreserved"
        case "provider-token-ranobedb":
            return "provider.ranobedb"
        case "provider-token-mangabaka":
            return "provider.mangabaka"
        case "provider-token-myanimelist":
            return "provider.myanimelist"
        case "provider-token-anilist":
            return "provider.anilist"
        default:
            return nil
        }
    }

    private func isShelfCatalogItem(_ item: LibraryPlanItem) -> Bool {
        guard item.stage == .canonicalFolders else { return false }
        return item.operation == .renameFolder
            || item.operation == .sortIntoFolder
            || item.reviewTags.contains(where: { $0.hasPrefix("shelf-") || $0.hasPrefix("sss-") })
            || item.reviewTags.contains("classification.sssShelf")
    }

    private func isMetadataCleanerItem(_ item: LibraryPlanItem) -> Bool {
        let reviewTags = Set(item.reviewTags)
        return reviewTags.contains("metadata-comicinfo-cleaner")
            || reviewTags.contains("metadata-provider-data-cleaner")
            || reviewTags.contains("metadata-checkpoint-refresh")
            || reviewTags.contains("metadata-checkpoint-detail")
    }

    private func recommendationRestrictList(for task: SableLibraryMLRecommenderTask) -> [String] {
        switch task {
        case .reviewAction:
            return [
                "check.sortIntoFolder",
                "protect.skip",
                "treatAsDocument",
                "treatAsBook",
                "review.keepLocal",
                "review.mergeOrMoveAside",
                "review.fixNumber",
                "review.providerChoice",
                "review.sampleFirst",
                "check.renameWhenSafe",
                "check.ifSafe"
            ]
        case .providerRanking:
            return [
                "provider.openLibrary",
                "provider.ranobedb",
                "provider.mangabaka",
                "provider.anilist",
                "provider.tmdb",
                "provider.tvdb",
                "provider.imdb"
            ]
        case .folderGrouping:
            return [
                "group.Books",
                "group.LightNovels",
                "group.Manga",
                "group.Manhwa",
                "group.Manhua",
                "group.Videos",
                "group.Documents",
                "group.Images",
                "group.Audio",
                "group.Archives",
                "group.Protected"
            ]
        }
    }

    private func inspectModeToken(_ mode: LibraryPipelineInspectMode) -> String {
        switch mode {
        case .full:
            return "inspect_full"
        case .lightInventory:
            return "inspect_light_inventory"
        case .epubClinicInventory:
            return "inspect_epub_inventory focus_stage_\(LibraryPipelineStage.epubClinic.rawValue)"
        case .stageDeepDive(let stage):
            return "inspect_stage_deep_dive focus_stage_\(stage.rawValue)"
        case .quickVerify(let previousStage, let changedPaths, let focusStage):
            let focusToken = focusStage.map { "focus_stage_\($0.rawValue)" } ?? "focus_stage_none"
            return "inspect_quick previous_stage_\(previousStage.rawValue) \(focusToken) changed_count_\(bucket(changedPaths.count))"
        }
    }

    private func bucket(_ value: Int) -> String {
        switch value {
        case 0: "zero"
        case 1: "one"
        case 2...5: "few"
        case 6...20: "some"
        case 21...80: "many"
        default: "large"
        }
    }
}

private enum SableLibraryMLHintTask: Sendable {
    case inspection
    case rawCleanup
    case reading
    case provider
    case sidecar
    case metadataClean
    case shelfCatalog
    case epubRepair
    case namingMove
    case reviewManagement
    case general
}

private enum SableLibraryMLNameTaggerTask: Sendable {
    case reading
    case video
    case document
}

private enum SableLibraryMLRecommenderTask: Sendable, Hashable {
    case reviewAction
    case providerRanking
    case folderGrouping
}

private final class SableLibraryBundledDecisionModel: @unchecked Sendable {
    static let shared = SableLibraryBundledDecisionModel()

    #if canImport(CoreML)
    private final class BundleToken: NSObject {}

    private var models: [String: MLModel] = [:]
    private let lock = NSLock()
    #endif

    private init() {
        NotificationCenter.default.addObserver(
            forName: .sableLibraryPersonalModelChanged,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.clearCachedModels()
        }
    }

    func hint(for task: SableLibraryMLHintTask, featureText: String) -> String? {
        #if canImport(CoreML)
        guard let input = try? MLDictionaryFeatureProvider(dictionary: ["text": featureText]) else {
            return nil
        }
        let labels = modelNames(for: task).compactMap { name -> String? in
            guard let model = model(named: name),
                  let output = try? model.prediction(from: input),
                  let label = output.featureValue(for: "label")?.stringValue else {
                return nil
            }
            return displayLabel(label)
        }
        var seen = Set<String>()
        let uniqueLabels = labels.filter { seen.insert($0).inserted }
        guard !uniqueLabels.isEmpty else { return nil }
        if uniqueLabels.count == 1 {
            return "Local ML ensemble hint: \(uniqueLabels[0])."
        }
        return "Local ML ensemble hints: \(uniqueLabels.prefix(3).joined(separator: "; "))."
        #else
        return nil
        #endif
    }

    func nameTagHint(for task: SableLibraryMLNameTaggerTask, text: String) -> String? {
        #if canImport(CoreML)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let model = model(named: nameTaggerModelName(for: task)),
              let input = try? MLDictionaryFeatureProvider(dictionary: ["text": text]),
              let output = try? model.prediction(from: input),
              let tokens = output.featureValue(for: "tokens")?.sequenceValue?.stringValues,
              let labels = output.featureValue(for: "labels")?.sequenceValue?.stringValues else {
            return nil
        }

        let details = zip(tokens, labels)
            .compactMap { token, label in
                displayNameTag(label: label, token: token)
            }
        var seen = Set<String>()
        let uniqueDetails = details.filter { seen.insert($0).inserted }
        guard !uniqueDetails.isEmpty else { return nil }
        return "\(nameTaggerTitle(for: task)) tagger saw \(uniqueDetails.prefix(4).joined(separator: ", "))."
        #else
        return nil
        #endif
    }

    func recommendationHint(
        for task: SableLibraryMLRecommenderTask,
        items: [String: Double],
        restrict: [String]
    ) -> String? {
        #if canImport(CoreML)
        guard !items.isEmpty,
              let model = model(named: recommenderModelName(for: task)) else {
            return nil
        }
        let recommendationCount = max(1, min(3, restrict.isEmpty ? 3 : restrict.count))
        var dictionary: [String: Any] = [
            "items": items,
            "k": recommendationCount
        ]
        if !restrict.isEmpty {
            dictionary["restrict"] = restrict
        }
        guard let input = try? MLDictionaryFeatureProvider(dictionary: dictionary),
              let output = try? model.prediction(from: input),
              let rawRecommendations = output.featureValue(for: "recommendations")?.sequenceValue?.stringValues else {
            return nil
        }
        let recommendations = rawRecommendations
            .filter { !$0.hasPrefix("signal.") }
            .map(displayRecommendation)
        guard !recommendations.isEmpty else { return nil }
        return "\(recommenderTitle(for: task)) recommends \(recommendations.prefix(3).joined(separator: ", "))."
        #else
        return nil
        #endif
    }

    private static let modelNames = [
        "SableLibraryInspectionClassifier",
        "SableLibraryRawCleanupClassifier",
        "SableLibraryReadingClassifier",
        "SableLibraryProviderClassifier",
        "SableLibraryTitleAliasRoleClassifier",
        "SableLibraryMediaTypeClassifier",
        "SableLibraryTagRoleClassifier",
        "SableLibraryDescriptionAboutnessClassifier",
        "SableLibraryWorkFamilyRelationshipClassifier",
        "SableLibrarySidecarClassifier",
        "SableLibraryShelfClassifier",
        "SableLibraryEvidenceMeetingClassifier",
        "SableLibraryEPUBRepairClassifier",
        "SableLibraryNamingMoveClassifier",
        "SableLibraryDecisionClassifier"
    ]

    #if canImport(CoreML)
    private func model(named name: String) -> MLModel? {
        lock.lock()
        if let model = models[name] {
            lock.unlock()
            return model
        }
        lock.unlock()

        guard let loaded = Self.loadModel(named: name) else { return nil }

        lock.lock()
        models[name] = loaded
        lock.unlock()
        return loaded
    }

    private func clearCachedModels() {
        lock.lock()
        models.removeAll()
        lock.unlock()
    }

    private static func loadModel(named name: String) -> MLModel? {
        if name == SableLibraryPersonalModelStore.modelName,
           shouldLoadPersonalModel,
           SableLibraryPersonalModelStore.isPersonalModelFresh() {
            let compiledURL: URL?
            if SableLibraryPersonalModelStore.isCompiledPersonalModelFresh() {
                compiledURL = SableLibraryPersonalModelStore.compiledModelURL
            } else {
                compiledURL = try? SableLibraryPersonalModelStore.prepareCompiledModel()
            }
            if let compiledURL,
               let model = try? MLModel(contentsOf: compiledURL) {
                return model
            }
        }

        for bundle in modelResourceBundles {
            if let compiledURL = bundle.url(forResource: name, withExtension: "mlmodelc"),
               let model = try? MLModel(contentsOf: compiledURL) {
                return model
            }
            if let modelURL = bundle.url(forResource: name, withExtension: "mlmodel"),
               let compiledURL = try? MLModel.compileModel(at: modelURL),
               let model = try? MLModel(contentsOf: compiledURL) {
                return model
            }
        }
        return nil
    }

    private static var shouldLoadPersonalModel: Bool {
        let process = ProcessInfo.processInfo
        return process.environment["XCTestConfigurationFilePath"] == nil
            && !process.processName.lowercased().contains("xctest")
    }

    private static var modelResourceBundles: [Bundle] {
        let candidates = [Bundle.main, Bundle(for: BundleToken.self)] + Bundle.allBundles
        var seen = Set<URL>()
        return candidates.filter {
            seen.insert($0.bundleURL.standardizedFileURL).inserted
        }
    }
    #endif

    private func modelNames(for task: SableLibraryMLHintTask) -> [String] {
        switch task {
        case .inspection:
            return ["SableLibraryInspectionClassifier", "SableLibraryEvidenceMeetingClassifier", "SableLibraryDecisionClassifier"]
        case .rawCleanup:
            return ["SableLibraryRawCleanupClassifier", "SableLibraryMediaTypeClassifier", "SableLibraryNamingMoveClassifier", "SableLibraryDecisionClassifier"]
        case .reading:
            return ["SableLibraryReadingClassifier", "SableLibraryMediaTypeClassifier", "SableLibraryTitleAliasRoleClassifier", "SableLibraryRawCleanupClassifier", "SableLibraryDecisionClassifier"]
        case .provider:
            return ["SableLibraryProviderClassifier", "SableLibraryMediaTypeClassifier", "SableLibraryTitleAliasRoleClassifier", "SableLibraryWorkFamilyRelationshipClassifier", "SableLibrarySidecarClassifier", "SableLibraryDecisionClassifier"]
        case .sidecar:
            return ["SableLibrarySidecarClassifier", "SableLibraryWorkFamilyRelationshipClassifier", "SableLibraryProviderClassifier", "SableLibraryTitleAliasRoleClassifier", "SableLibraryDecisionClassifier"]
        case .metadataClean:
            return ["SableLibrarySidecarClassifier", "SableLibraryWorkFamilyRelationshipClassifier", "SableLibraryProviderClassifier", "SableLibraryTagRoleClassifier", "SableLibraryDescriptionAboutnessClassifier", "SableLibraryEvidenceMeetingClassifier", "SableLibraryDecisionClassifier"]
        case .shelfCatalog:
            return ["SableLibraryShelfClassifier", "SableLibraryDescriptionAboutnessClassifier", "SableLibraryTagRoleClassifier", "SableLibraryMediaTypeClassifier", "SableLibraryWorkFamilyRelationshipClassifier", "SableLibraryEvidenceMeetingClassifier", "SableLibraryReadingClassifier", "SableLibrarySidecarClassifier", "SableLibraryDecisionClassifier"]
        case .epubRepair:
            return ["SableLibraryEPUBRepairClassifier", "SableLibraryReadingClassifier", "SableLibrarySidecarClassifier", "SableLibraryWorkFamilyRelationshipClassifier", "SableLibraryDecisionClassifier"]
        case .namingMove:
            return ["SableLibraryNamingMoveClassifier", "SableLibraryMediaTypeClassifier", "SableLibraryTitleAliasRoleClassifier", "SableLibraryRawCleanupClassifier", "SableLibraryDecisionClassifier"]
        case .reviewManagement:
            return ["SableLibraryEvidenceMeetingClassifier", "SableLibraryDecisionClassifier"]
        case .general:
            return ["SableLibraryDecisionClassifier"]
        }
    }

    private func nameTaggerModelName(for task: SableLibraryMLNameTaggerTask) -> String {
        switch task {
        case .reading:
            return "SableLibraryReadingNameTagger"
        case .video:
            return "SableLibraryVideoNameTagger"
        case .document:
            return "SableLibraryDocumentNameTagger"
        }
    }

    private func nameTaggerTitle(for task: SableLibraryMLNameTaggerTask) -> String {
        switch task {
        case .reading:
            return "Reading name"
        case .video:
            return "Video name"
        case .document:
            return "Document name"
        }
    }

    private func recommenderModelName(for task: SableLibraryMLRecommenderTask) -> String {
        switch task {
        case .reviewAction:
            return "SableLibraryReviewActionRecommender"
        case .providerRanking:
            return "SableLibraryProviderRankingRecommender"
        case .folderGrouping:
            return "SableLibraryFolderGroupingRecommender"
        }
    }

    private func recommenderTitle(for task: SableLibraryMLRecommenderTask) -> String {
        switch task {
        case .reviewAction:
            return "Review action recommender"
        case .providerRanking:
            return "Provider recommender"
        case .folderGrouping:
            return "Folder grouping recommender"
        }
    }

    private func displayNameTag(label: String, token: String) -> String? {
        let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanToken.isEmpty else { return nil }
        switch label {
        case "PROVIDER_NOISE":
            return "provider/source noise '\(cleanToken)'"
        case "YEAR":
            return "year \(cleanToken)"
        case "VOLUME_NUMBER":
            return "volume \(cleanToken)"
        case "CHAPTER_NUMBER":
            return "chapter \(cleanToken)"
        case "ISSUE_NUMBER":
            return "issue \(cleanToken)"
        case "EDITION":
            return "edition clue '\(cleanToken)'"
        case "AUTHOR":
            return "author clue '\(cleanToken)'"
        case "DOCUMENT_TYPE":
            return "document type '\(cleanToken)'"
        case "EPISODE", "EPISODE_NUMBER":
            return "episode \(cleanToken)"
        case "SEASON_NUMBER":
            return "season \(cleanToken)"
        case "RESOLUTION":
            return "resolution \(cleanToken)"
        case "SOURCE":
            return "source \(cleanToken)"
        case "LANGUAGE":
            return "language \(cleanToken)"
        default:
            return nil
        }
    }

    private func displayRecommendation(_ value: String) -> String {
        switch value {
        case "check.sortIntoFolder":
            return "check safe sort"
        case "protect.skip":
            return "protect or skip"
        case "treatAsDocument":
            return "treat as document"
        case "treatAsBook":
            return "treat as book"
        case "review.keepLocal":
            return "review and keep local if unclear"
        case "review.mergeOrMoveAside":
            return "review merge or move-aside"
        case "review.fixNumber":
            return "review/fix number"
        case "review.providerChoice":
            return "review provider choice"
        case "review.sampleFirst":
            return "sample first"
        case "check.renameWhenSafe":
            return "rename when safe"
        case "check.ifSafe":
            return "check if safe"
        case "provider.openLibrary":
            return "Open Library"
        case "provider.ranobedb":
            return "RanobeDB"
        case "provider.mangabaka":
            return "MangaBaka"
        case "provider.anilist":
            return "AniList"
        case "provider.tmdb":
            return "TMDB"
        case "provider.tvdb":
            return "TVDB"
        case "provider.imdb":
            return "IMDb"
        case "group.Books":
            return "Books"
        case "group.LightNovels":
            return "Light Novels"
        case "group.Manga":
            return "Manga"
        case "group.Manhwa":
            return "Manhwa"
        case "group.Manhua":
            return "Manhua"
        case "group.Videos":
            return "Videos"
        case "group.Documents":
            return "Documents"
        case "group.Images":
            return "Images"
        case "group.Audio":
            return "Audio"
        case "group.Archives":
            return "Archives"
        case "group.Protected":
            return "Protected"
        default:
            return displayLabel(value)
        }
    }

    private func displayLabel(_ label: String) -> String {
        if let shelf = label.removingPrefix("description.shelf.") {
            return "description points toward Shelf \(shelf)"
        }
        if let shelf = label.removingPrefix("shelf.") {
            return "Shelf \(shelf)"
        }
        if let value = label.removingPrefix("description.confidence.") {
            return "description confidence: \(prettyLabelSegment(value))"
        }
        if let value = label.removingPrefix("description.") {
            return "description signal: \(prettyLabelSegment(value))"
        }
        if let value = label.removingPrefix("manager.actionability.") {
            return "evidence action: \(prettyLabelSegment(value))"
        }
        if let value = label.removingPrefix("manager.confidence.") {
            return "evidence confidence: \(prettyLabelSegment(value))"
        }
        if let value = label.removingPrefix("manager.") {
            return "evidence manager: \(prettyLabelSegment(value))"
        }
        if let value = label.removingPrefix("tagRole.") {
            return "tag role: \(prettyLabelSegment(value))"
        }
        if let value = label.removingPrefix("mediaType.") {
            return "media type: \(prettyLabelSegment(value))"
        }
        if let value = label.removingPrefix("titleAlias.") {
            return "title alias: \(prettyLabelSegment(value))"
        }
        if let value = label.removingPrefix("workFamily.") {
            return "work family: \(prettyLabelSegment(value))"
        }
        if let value = label.removingPrefix("providerShape.") {
            return "provider shape: \(prettyLabelSegment(value))"
        }
        return label
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "openLibrary", with: "Open Library")
            .replacingOccurrences(of: "ranobedb", with: "RanobeDB")
            .replacingOccurrences(of: "mangabaka", with: "MangaBaka")
            .replacingOccurrences(of: "comicInfo", with: "ComicInfo")
            .replacingOccurrences(of: "animeInfo", with: "AnimeInfo")
            .replacingOccurrences(of: "appleBooks", with: "Apple Books")
    }

    private func prettyLabelSegment(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"([a-z0-9])([A-Z])"#, with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "openLibrary", with: "Open Library")
            .replacingOccurrences(of: "ranobedb", with: "RanobeDB")
            .replacingOccurrences(of: "mangabaka", with: "MangaBaka")
            .replacingOccurrences(of: "comicInfo", with: "ComicInfo")
            .replacingOccurrences(of: "animeInfo", with: "AnimeInfo")
            .replacingOccurrences(of: "appleBooks", with: "Apple Books")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension String {
    func removingPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count))
    }
}
