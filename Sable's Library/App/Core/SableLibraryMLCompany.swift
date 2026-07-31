//
//  SableLibraryMLCompany.swift
//  Sable's Library
//

import Foundation

nonisolated enum SableLibraryMLCompanyDepartment: String, CaseIterable, Sendable {
    case ceoSable = "ceosable"
    case shelfManager = "shelfmanager"
    case metadataManager = "metadatamanager"
    case clinicManager = "clinicmanager"
    case moveManager = "movemanager"
    case reviewManager = "reviewmanager"
    case intakeDesk = "intakedesk"
    case rawIntake = "rawintake"
    case readingLibrary = "readinglibrary"
    case watchDesk = "watchdesk"
    case sidecarRelations = "sidecarrelations"
    case shelfCatalog = "shelfcatalog"
    case descriptionAboutness = "descriptionaboutness"
    case evidenceQuality = "evidencequality"
    case epubClinic = "epubclinic"
    case namingLogistics = "naminglogistics"
    case duplicateSafety = "duplicatesafety"
    case safetyOffice = "safetyoffice"

    var title: String {
        switch self {
        case .ceoSable: "CEO Sable"
        case .shelfManager: "Shelf Manager"
        case .metadataManager: "Metadata Manager"
        case .clinicManager: "Clinic Manager"
        case .moveManager: "Move Manager"
        case .reviewManager: "Review Manager"
        case .intakeDesk: "Intake Desk"
        case .rawIntake: "Raw Intake"
        case .readingLibrary: "Reading Library"
        case .watchDesk: "Watch Desk"
        case .sidecarRelations: "Sidecar Relations"
        case .shelfCatalog: "Shelf Catalog"
        case .descriptionAboutness: "Description Aboutness"
        case .evidenceQuality: "Evidence Quality"
        case .epubClinic: "Sable's Clinic"
        case .namingLogistics: "Naming Logistics"
        case .duplicateSafety: "Duplicate Safety"
        case .safetyOffice: "Safety Office"
        }
    }

    var featureTokens: [String] {
        switch self {
        case .ceoSable:
            [
                "company.ceosable",
                "communication.singleowner",
                "handoff.sharedevidence",
                "coordination.reviewplan"
            ]
        case .shelfManager:
            [
                "manager.foundation.shelfcatalog",
                "foundation.guidedgeneration",
                "decision.finalsay",
                "classification.aboutnessledger",
                "communication.whyThisShelf",
                "trust.receipts"
            ]
        case .metadataManager:
            [
                "manager.foundation.metadata",
                "foundation.guidedgeneration",
                "decision.finalsay",
                "metadata.diffledger",
                "provider.conflictReview",
                "trust.localSidecarFirst"
            ]
        case .clinicManager:
            [
                "manager.foundation.clinic",
                "foundation.guidedgeneration",
                "decision.finalsay",
                "task.epubrepair",
                "repair.evidencePlan",
                "trust.noSilentRewrite"
            ]
        case .moveManager:
            [
                "manager.foundation.move",
                "foundation.guidedgeneration",
                "decision.finalsay",
                "task.namingmove",
                "safety.dryrun",
                "communication.pathDiff"
            ]
        case .reviewManager:
            [
                "manager.foundation.review",
                "foundation.guidedgeneration",
                "decision.finalsay",
                "review.actionability",
                "communication.plainReason",
                "trust.userCorrectionLoop"
            ]
        case .intakeDesk:
            [
                "department.intakedesk",
                "scope.lightinventory",
                "communication.evidencemap"
            ]
        case .rawIntake:
            [
                "department.rawintake",
                "scope.rootonly",
                "communication.localcleanup"
            ]
        case .readingLibrary:
            [
                "department.readinglibrary",
                "domain.reading",
                "communication.providercontext"
            ]
        case .watchDesk:
            [
                "department.watchdesk",
                "domain.watching",
                "communication.providercontext"
            ]
        case .sidecarRelations:
            [
                "department.sidecarrelations",
                "trust.localsidecar",
                "communication.identitygraph"
            ]
        case .shelfCatalog:
            [
                "department.shelfcatalog",
                "domain.reading",
                "task.sssShelfSuggestion",
                "classification.titleDescriptionGenreTheme",
                "communication.explainableShelfReasoning"
            ]
        case .descriptionAboutness:
            [
                "department.descriptionaboutness",
                "naturalLanguage.descriptionReader",
                "classification.storyEngine",
                "classification.settingFacetSeparation",
                "task.descriptionClarification"
            ]
        case .evidenceQuality:
            [
                "department.evidencequality",
                "classification.evidenceQuality",
                "confidence.crossSourceAgreement",
                "confidence.fallbackWhenThin",
                "review.missingEvidence"
            ]
        case .epubClinic:
            [
                "department.epubclinic",
                "task.epubrepair",
                "scope.deepfilecheck"
            ]
        case .namingLogistics:
            [
                "department.naminglogistics",
                "communication.handoff",
                "task.namingmove"
            ]
        case .duplicateSafety:
            [
                "department.duplicatesafety",
                "escalation.collision",
                "communication.mergechoice"
            ]
        case .safetyOffice:
            [
                "department.safetyoffice",
                "safety.veto",
                "trust.hardguards"
            ]
        }
    }
}

nonisolated enum SableLibraryMLCompany {
    static func departments(for mode: LibraryPipelineInspectMode) -> [SableLibraryMLCompanyDepartment] {
        departments(for: inferredAppMode(for: mode), mode: mode)
    }

    static func departments(
        for appMode: SableLibraryAppMode,
        mode: LibraryPipelineInspectMode
    ) -> [SableLibraryMLCompanyDepartment] {
        switch appMode {
        case .library:
            return libraryDepartments(for: mode)
        case .clinic:
            return clinicDepartments(for: mode)
        case .covers:
            return libraryDepartments(for: mode)
        }
    }

    private static func libraryDepartments(for mode: LibraryPipelineInspectMode) -> [SableLibraryMLCompanyDepartment] {
        switch mode {
        case .full:
            return uniqueDepartments(
                [
                    .ceoSable,
                    .shelfManager,
                    .metadataManager,
                    .moveManager,
                    .reviewManager,
                    .intakeDesk,
                    .rawIntake,
                    .readingLibrary,
                    .watchDesk,
                    .sidecarRelations,
                    .shelfCatalog,
                    .descriptionAboutness,
                    .evidenceQuality,
                    .namingLogistics,
                    .duplicateSafety,
                    .safetyOffice
                ]
            )
        case .lightInventory:
            return [.ceoSable, .reviewManager, .intakeDesk, .evidenceQuality, .safetyOffice]
        case .epubClinicInventory:
            return [.ceoSable, .reviewManager, .intakeDesk, .evidenceQuality, .safetyOffice]
        case .stageDeepDive(let stage):
            return libraryDepartments(for: stage)
        case .quickVerify(_, _, let focusStage):
            return focusStage.map(libraryDepartments(for:)) ?? [.ceoSable, .reviewManager, .intakeDesk, .evidenceQuality, .safetyOffice]
        }
    }

    static func departments(for stage: LibraryPipelineStage) -> [SableLibraryMLCompanyDepartment] {
        departments(for: SableLibraryAppMode.current, stage: stage)
    }

    static func departments(
        for appMode: SableLibraryAppMode,
        stage: LibraryPipelineStage
    ) -> [SableLibraryMLCompanyDepartment] {
        switch appMode {
        case .library:
            return libraryDepartments(for: stage)
        case .clinic:
            return clinicDepartments(for: stage)
        case .covers:
            return stage == .epubClinic ? clinicDepartments(for: stage) : libraryDepartments(for: stage)
        }
    }

    private static func libraryDepartments(for stage: LibraryPipelineStage) -> [SableLibraryMLCompanyDepartment] {
        switch stage {
        case .inspect:
            return [.ceoSable, .reviewManager, .intakeDesk, .evidenceQuality, .safetyOffice]
        case .prepareRawFiles:
            return [.ceoSable, .moveManager, .rawIntake, .readingLibrary, .watchDesk, .namingLogistics, .evidenceQuality, .safetyOffice]
        case .comicInfo:
            return [.ceoSable, .metadataManager, .sidecarRelations, .readingLibrary, .watchDesk, .descriptionAboutness, .evidenceQuality, .safetyOffice]
        case .providerMatches:
            return [.ceoSable, .metadataManager, .sidecarRelations, .readingLibrary, .descriptionAboutness, .evidenceQuality, .safetyOffice]
        case .covers:
            return [.ceoSable, .metadataManager, .sidecarRelations, .readingLibrary, .evidenceQuality, .safetyOffice]
        case .canonicalFolders:
            return [.ceoSable, .shelfManager, .moveManager, .namingLogistics, .readingLibrary, .watchDesk, .sidecarRelations, .descriptionAboutness, .evidenceQuality, .shelfCatalog, .safetyOffice]
        case .canonicalFiles:
            return [.ceoSable, .moveManager, .namingLogistics, .readingLibrary, .evidenceQuality, .safetyOffice]
        case .epubClinic:
            return [.ceoSable, .reviewManager, .evidenceQuality, .safetyOffice]
        case .duplicateReview:
            return [.ceoSable, .reviewManager, .duplicateSafety, .namingLogistics, .evidenceQuality, .safetyOffice]
        case .reviewApply:
            return [.ceoSable, .reviewManager, .evidenceQuality, .safetyOffice]
        }
    }

    private static func clinicDepartments(for mode: LibraryPipelineInspectMode) -> [SableLibraryMLCompanyDepartment] {
        switch mode {
        case .full:
            return uniqueDepartments(
                [
                    .ceoSable,
                    .clinicManager,
                    .metadataManager,
                    .reviewManager,
                    .intakeDesk,
                    .readingLibrary,
                    .sidecarRelations,
                    .descriptionAboutness,
                    .evidenceQuality,
                    .epubClinic,
                    .safetyOffice
                ]
            )
        case .lightInventory, .epubClinicInventory:
            return [.ceoSable, .clinicManager, .intakeDesk, .evidenceQuality, .epubClinic, .safetyOffice]
        case .stageDeepDive(let stage):
            return clinicDepartments(for: stage)
        case .quickVerify(_, _, let focusStage):
            return focusStage.map(clinicDepartments(for:)) ?? [.ceoSable, .clinicManager, .reviewManager, .evidenceQuality, .safetyOffice]
        }
    }

    private static func clinicDepartments(for stage: LibraryPipelineStage) -> [SableLibraryMLCompanyDepartment] {
        switch stage {
        case .inspect:
            return [.ceoSable, .clinicManager, .reviewManager, .intakeDesk, .evidenceQuality, .safetyOffice]
        case .comicInfo, .providerMatches, .covers:
            return [.ceoSable, .metadataManager, .sidecarRelations, .readingLibrary, .descriptionAboutness, .evidenceQuality, .reviewManager, .safetyOffice]
        case .epubClinic:
            return [.ceoSable, .clinicManager, .metadataManager, .epubClinic, .readingLibrary, .sidecarRelations, .descriptionAboutness, .evidenceQuality, .reviewManager, .safetyOffice]
        case .reviewApply, .duplicateReview:
            return [.ceoSable, .clinicManager, .reviewManager, .evidenceQuality, .safetyOffice]
        case .prepareRawFiles, .canonicalFolders, .canonicalFiles:
            return [.ceoSable, .clinicManager, .reviewManager, .evidenceQuality, .safetyOffice]
        }
    }

    static func owner(for item: LibraryPlanItem) -> SableLibraryMLCompanyDepartment {
        switch item.operation {
        case .inspectOnly:
            return .intakeDesk
        case .repairEpubPackage, .repairAppleBooksCompatibility:
            return .epubClinic
        case .cleanRawName, .sortIntoFolder:
            return .rawIntake
        case .createComicInfo, .refreshComicInfo, .createAnimeInfo, .refreshAnimeInfo:
            return .sidecarRelations
        case .renameFolder, .renameFile:
            return .namingLogistics
        case .duplicateDecision:
            return .duplicateSafety
        case .skip:
            return .safetyOffice
        }
    }

    static func finalSayManager(for stage: LibraryPipelineStage) -> SableLibraryMLCompanyDepartment {
        finalSayManager(for: SableLibraryAppMode.current, stage: stage)
    }

    static func finalSayManager(
        for appMode: SableLibraryAppMode,
        stage: LibraryPipelineStage
    ) -> SableLibraryMLCompanyDepartment {
        if appMode == .clinic {
            switch stage {
            case .epubClinic:
                return .clinicManager
            case .comicInfo, .providerMatches, .covers:
                return .metadataManager
            case .inspect, .prepareRawFiles, .canonicalFolders, .canonicalFiles, .duplicateReview, .reviewApply:
                return .reviewManager
            }
        }
        switch stage {
        case .inspect:
            return .reviewManager
        case .prepareRawFiles, .canonicalFiles:
            return .moveManager
        case .comicInfo, .providerMatches, .covers:
            return .metadataManager
        case .canonicalFolders:
            return .shelfManager
        case .epubClinic:
            return .reviewManager
        case .duplicateReview, .reviewApply:
            return .reviewManager
        }
    }

    static func finalSayManager(for item: LibraryPlanItem) -> SableLibraryMLCompanyDepartment {
        finalSayManager(for: inferredAppMode(for: item), item: item)
    }

    static func finalSayManager(
        for appMode: SableLibraryAppMode,
        item: LibraryPlanItem
    ) -> SableLibraryMLCompanyDepartment {
        if appMode == .clinic {
            switch item.operation {
            case .repairEpubPackage, .repairAppleBooksCompatibility:
                return .clinicManager
            case .createComicInfo, .refreshComicInfo, .createAnimeInfo, .refreshAnimeInfo:
                return .metadataManager
            case .inspectOnly, .cleanRawName, .sortIntoFolder, .renameFolder, .renameFile, .duplicateDecision, .skip:
                return .reviewManager
            }
        }
        switch item.operation {
        case .repairEpubPackage, .repairAppleBooksCompatibility:
            return .clinicManager
        case .createComicInfo, .refreshComicInfo, .createAnimeInfo, .refreshAnimeInfo:
            return .metadataManager
        case .renameFolder, .sortIntoFolder:
            if isShelfCatalogItem(item) {
                return .shelfManager
            }
            return .moveManager
        case .renameFile, .cleanRawName:
            return .moveManager
        case .inspectOnly, .duplicateDecision, .skip:
            return .reviewManager
        }
    }

    static func departments(for item: LibraryPlanItem) -> [SableLibraryMLCompanyDepartment] {
        departments(for: inferredAppMode(for: item), item: item)
    }

    static func departments(
        for appMode: SableLibraryAppMode,
        item: LibraryPlanItem
    ) -> [SableLibraryMLCompanyDepartment] {
        var departments: [SableLibraryMLCompanyDepartment] = [
            .ceoSable,
            finalSayManager(for: appMode, item: item),
            owner(for: item)
        ]
        departments.append(contentsOf: Self.departments(for: appMode, stage: item.stage))
        if appMode == .library && isShelfCatalogItem(item) {
            departments.append(contentsOf: [.descriptionAboutness, .evidenceQuality, .shelfCatalog])
        }
        if isMetadataCleanerItem(item) {
            departments.append(contentsOf: [.metadataManager, .sidecarRelations, .evidenceQuality])
        }
        departments.append(.safetyOffice)
        return uniqueDepartments(departments)
    }

    static func featureTokens(for mode: LibraryPipelineInspectMode) -> [String] {
        featureTokens(for: inferredAppMode(for: mode), mode: mode)
    }

    static func featureTokens(
        for appMode: SableLibraryAppMode,
        mode: LibraryPipelineInspectMode
    ) -> [String] {
        var tokens = [
            "app.\(appMode.rawValue)",
            "company.lazycompany",
            "communication.stagedhandoff",
            "trust.privacyfirst"
        ]
        tokens.append(contentsOf: departments(for: appMode, mode: mode).flatMap(\.featureTokens))

        switch mode {
        case .full:
            tokens.append(contentsOf: ["scope.fullinspect", "cpu.heavyoptin"])
        case .lightInventory:
            tokens.append(contentsOf: ["scope.lightinventory", "cpu.balanced"])
        case .epubClinicInventory:
            tokens.append(contentsOf: ["scope.epubinventory", "focus.epubclinic", "cpu.light"])
        case .stageDeepDive(let stage):
            tokens.append(contentsOf: ["scope.deepdive", "focus.\(stage.rawValue.lowercased())"])
        case .quickVerify(let previousStage, let changedPaths, let focusStage):
            tokens.append(contentsOf: [
                "scope.quickverify",
                "previous.\(previousStage.rawValue.lowercased())",
                "changedcount.\(bucket(changedPaths.count))",
                focusStage.map { "focus.\($0.rawValue.lowercased())" } ?? "focus.none"
            ])
        }

        return uniqueStrings(tokens)
    }

    static func featureTokens(for item: LibraryPlanItem) -> [String] {
        featureTokens(for: inferredAppMode(for: item), item: item)
    }

    static func featureTokens(
        for appMode: SableLibraryAppMode,
        item: LibraryPlanItem
    ) -> [String] {
        var tokens = [
            "app.\(appMode.rawValue)",
            "company.lazycompany",
            "communication.stagedhandoff",
            "owner.\(owner(for: item).rawValue)",
            "manager.\(finalSayManager(for: appMode, item: item).rawValue)",
            "foundation.manager.finalsay",
            "trust.mlrecommendsuserdecides"
        ]
        tokens.append(contentsOf: departments(for: appMode, item: item).flatMap(\.featureTokens))

        if item.requiresReview {
            tokens.append("escalation.review")
        }
        switch item.safety {
        case .inspectOnly:
            tokens.append("safety.inspectonly")
        case .reversible:
            tokens.append("safety.reversible")
        case .needsChoice:
            tokens.append(contentsOf: ["safety.needschoice", "escalation.review"])
        case .collision:
            tokens.append(contentsOf: ["safety.collision", "escalation.collision", "communication.mergechoice"])
        case .network:
            tokens.append(contentsOf: ["trust.providerboundary", "escalation.providerreview"])
        }

        if item.usedNetworkData {
            tokens.append("trust.providerboundary")
        }
        if item.currentPath.contains("/") {
            tokens.append("scope.deepevidence")
        } else {
            tokens.append("scope.rootitem")
        }

        let reviewTags = Set(item.reviewTags)
        if reviewTags.contains("metadata-checkpoint-choice") {
            tokens.append(contentsOf: [
                "metadata.choice",
                "communication.providerchoice",
                "escalation.providerreview"
            ])
        }
        if reviewTags.contains("metadata-checkpoint-identity") {
            tokens.append(contentsOf: [
                "metadata.identity",
                "communication.identityfirst"
            ])
        }
        if reviewTags.contains("metadata-checkpoint-detail") {
            tokens.append(contentsOf: [
                "metadata.detail",
                "communication.detailsafteridentity"
            ])
        }
        if reviewTags.contains("metadata-checkpoint-refresh") {
            tokens.append("metadata.refresh")
        }
        if reviewTags.contains("metadata-comicinfo-cleaner") || reviewTags.contains("metadata-provider-data-cleaner") {
            tokens.append(contentsOf: [
                "metadata.sidecarCleaner",
                "metadata.providerEvidenceTidy",
                "communication.dataSummary",
                "trust.localOnly"
            ])
        }
        if reviewTags.contains("metadata-checkpoint-manual") || reviewTags.contains("metadata-manual-provider-gap") {
            tokens.append(contentsOf: [
                "metadata.manualProviderGap",
                "provider.rankerTraining",
                "communication.teachingLoop",
                "review.missingProviderQueue"
            ])
        }
        if reviewTags.contains("metadata-checkpoint-watching") {
            tokens.append(contentsOf: [
                "metadata.watching",
                "provider.watching"
            ])
        }
        if reviewTags.contains("manual-provider-match") {
            tokens.append("provider.matchStrong")
        }
        if reviewTags.contains("naming-title-change") {
            tokens.append(contentsOf: [
                "naming.titleChange",
                "communication.diffFirst",
                "escalation.review"
            ])
        }
        if reviewTags.contains("naming-punctuation-only") {
            tokens.append(contentsOf: [
                "naming.lowVisibilityChange",
                "communication.diffFirst"
            ])
        }
        if reviewTags.contains("naming-provider-token-change") {
            tokens.append(contentsOf: [
                "provider.idChange",
                "trust.providerboundary",
                "escalation.review"
            ])
        }
        if reviewTags.contains("naming-provider-token-preserved") {
            tokens.append("provider.idPreserved")
        }
        if reviewTags.contains("provider-token-ranobedb") {
            tokens.append("provider.ranobedb")
        }
        if reviewTags.contains("provider-token-mangabaka") {
            tokens.append("provider.mangabaka")
        }
        if reviewTags.contains("provider-token-myanimelist") {
            tokens.append("provider.myanimelist")
        }
        if reviewTags.contains("provider-token-anilist") {
            tokens.append("provider.anilist")
        }
        if appMode == .library && isShelfCatalogItem(item) {
            tokens.append(contentsOf: [
                "classification.sssShelf",
                "department.shelfcatalog",
                "department.descriptionaboutness",
                "department.evidencequality",
                "manager.foundation.shelfcatalog",
                "communication.explainableShelfReasoning"
            ])
        }

        return uniqueStrings(tokens)
    }

    static func operatingNote(for mode: LibraryPipelineInspectMode) -> String {
        operatingNote(for: inferredAppMode(for: mode), mode: mode)
    }

    static func operatingNote(
        for appMode: SableLibraryAppMode,
        mode: LibraryPipelineInspectMode
    ) -> String {
        switch mode {
        case .full:
            switch appMode {
            case .library:
                return "CEO Sable is running the Library company: metadata, shelf, move, review, and safety specialists may wake when the shared evidence map is stale."
            case .clinic:
                return "CEO Sable is running the Clinic company: EPUB repair, metadata, reading, evidence, review, and safety specialists may wake for a deliberate health pass."
            case .covers:
                return "CEO Sable is running the Covers company: cover matching, image evidence, EPUB cover repair, review, and safety specialists may wake for a deliberate cover pass."
            }
        case .lightInventory:
            return "CEO Sable is keeping this light: Intake Desk maps evidence, Safety Office marks protected folders, and specialists wait for their lane."
        case .epubClinicInventory:
            return "CEO Sable is keeping this light: Intake Desk lists EPUB files and local sidecars, while Sable's Clinic waits for a deliberate deep check."
        case .stageDeepDive(let stage):
            let titles = departmentTitleList(departments(for: appMode, stage: stage).filter { $0 != .ceoSable })
            return "CEO Sable routed this pass to \(titles); other departments stay quiet."
        case .quickVerify(_, _, let focusStage):
            if let focusStage {
                return "CEO Sable is refreshing changed paths, then handing fresh evidence back to \(stageTitle(focusStage))."
            }
            return "CEO Sable is refreshing changed paths without waking every department."
        }
    }

    static func handoffNote(for item: LibraryPlanItem) -> String {
        handoffNote(for: inferredAppMode(for: item), item: item)
    }

    static func handoffNote(
        for appMode: SableLibraryAppMode,
        item: LibraryPlanItem
    ) -> String {
        let owner = owner(for: item)
        let manager = finalSayManager(for: appMode, item: item)
        let advisors = departments(for: appMode, item: item)
            .filter { $0 != .ceoSable && $0 != owner && $0 != manager }
        let advisorText = departmentTitleList(advisors.prefix(3).map { $0 })
        if advisorText.isEmpty {
            return "Owner: \(owner.title). Foundation manager: \(manager.title) makes the final recommendation; Safety Office keeps apply user-controlled."
        }
        return "Owner: \(owner.title). Foundation manager: \(manager.title) makes the final recommendation. Advisors: \(advisorText). Safety Office keeps apply user-controlled."
    }

    static func safetyNote(for item: LibraryPlanItem) -> String? {
        if item.safety == .collision {
            return "Safety Office flagged a collision; choose merge, move aside, or leave it unchecked."
        }
        if item.safety == .network || item.usedNetworkData {
            return "Provider boundary: network evidence can advise, but weak matches must skip instead of writing guessed data."
        }
        if item.safety == .needsChoice || item.requiresReview {
            return "Review loop: Sable is asking before this department acts."
        }
        if item.safety == .inspectOnly {
            return "Safety Office keeps this inspect-only."
        }
        return nil
    }

    private static func departmentTitleList<S: Sequence>(_ departments: S) -> String where S.Element == SableLibraryMLCompanyDepartment {
        let titles = Array(departments.map(\.title))
        switch titles.count {
        case 0:
            return ""
        case 1:
            return titles[0]
        case 2:
            return "\(titles[0]) and \(titles[1])"
        default:
            return titles.dropLast().joined(separator: ", ") + ", and " + (titles.last ?? "")
        }
    }

    private static func uniqueDepartments(_ departments: [SableLibraryMLCompanyDepartment]) -> [SableLibraryMLCompanyDepartment] {
        var seen = Set<SableLibraryMLCompanyDepartment>()
        return departments.filter { seen.insert($0).inserted }
    }

    private static func uniqueStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private static func isShelfCatalogItem(_ item: LibraryPlanItem) -> Bool {
        guard item.stage == .canonicalFolders else { return false }
        return item.operation == .renameFolder
            || item.operation == .sortIntoFolder
            || item.reviewTags.contains(where: { $0.hasPrefix("shelf-") || $0.hasPrefix("sss-") })
            || item.reviewTags.contains("classification.sssShelf")
    }

    private static func isMetadataCleanerItem(_ item: LibraryPlanItem) -> Bool {
        let reviewTags = Set(item.reviewTags)
        return reviewTags.contains("metadata-comicinfo-cleaner")
            || reviewTags.contains("metadata-provider-data-cleaner")
            || reviewTags.contains("metadata-checkpoint-refresh")
            || reviewTags.contains("metadata-checkpoint-detail")
    }

    private static func stageTitle(_ stage: LibraryPipelineStage) -> String {
        switch stage {
        case .inspect: return "Inspect library"
        case .prepareRawFiles: return "Prepare raw files"
        case .comicInfo: return "Metadata Sidecars"
        case .providerMatches: return "Provider Matches"
        case .covers: return "Covers"
        case .canonicalFolders: return "Folder sorting"
        case .canonicalFiles: return "File names"
        case .epubClinic: return "Sable's Clinic"
        case .duplicateReview: return "Duplicates"
        case .reviewApply: return "Summary"
        }
    }

    private static func bucket(_ value: Int) -> String {
        switch value {
        case 0: "zero"
        case 1: "one"
        case 2...5: "few"
        case 6...20: "some"
        case 21...80: "many"
        default: "large"
        }
    }

    private static func inferredAppMode(for mode: LibraryPipelineInspectMode) -> SableLibraryAppMode {
        switch mode {
        case .epubClinicInventory:
            return .clinic
        case .stageDeepDive(let stage):
            return stage == .epubClinic ? .clinic : SableLibraryAppMode.current
        case .quickVerify(let previousStage, _, let focusStage):
            return previousStage == .epubClinic || focusStage == .epubClinic ? .clinic : SableLibraryAppMode.current
        case .full, .lightInventory:
            return SableLibraryAppMode.current
        }
    }

    private static func inferredAppMode(for item: LibraryPlanItem) -> SableLibraryAppMode {
        switch item.operation {
        case .repairEpubPackage, .repairAppleBooksCompatibility:
            return .clinic
        case .inspectOnly, .cleanRawName, .sortIntoFolder, .createComicInfo, .refreshComicInfo,
             .createAnimeInfo, .refreshAnimeInfo, .renameFolder, .renameFile, .duplicateDecision, .skip:
            return item.stage == .epubClinic ? .clinic : SableLibraryAppMode.current
        }
    }
}
