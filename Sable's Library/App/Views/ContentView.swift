//
//  ContentView.swift
//  Sable's Library
//

import OSLog
import SwiftUI
#if os(macOS)
import AppKit
#endif

private let sableWorkflowLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.annearuki.Sables-Library",
    category: "Workflow"
)

private let sableProgressUIUpdateInterval: TimeInterval = 0.9
private let sableActivityUIUpdateInterval: TimeInterval = 0.9

private struct PendingPipelineQuickCheck {
    var stage: LibraryPipelineStage
    var paths: [String]
}

private enum LibraryFolderSelectionSource {
    case picker
    case drop

    var logLabel: String {
        switch self {
        case .picker:
            "picker"
        case .drop:
            "drop"
        }
    }
}

struct ContentView: View {
    var mode: SableLibraryAppMode = .library

    @Environment(\.sableLibraryPalette) private var palette
    @Environment(\.openSettings) private var openSettings
    @AppStorage("sableLibrary.hasSeenOnboarding") private var hasSeenOnboarding = false

    @State private var libraryURL: URL?
    @State private var scopedLibraryURL: URL?
    @State private var hasLibraryAccess = false
    @State private var status = "Ready"
    @State private var currentActivity: String
    @State private var isRunning = false
    @State private var cleanupOptions = CleanupOptions()
    @State private var pipelineStageOptions = LibraryPipelineStageOptions()
    @State private var intelligenceOptions = SableLibraryIntelligenceOptions()
    @State private var learningMemory = SableLibraryLearningMemory()
    @State private var learnedDecisionCount = 0
    @State private var showOnboarding = false
    @State private var onboardingStep = 0
    @State private var showResetDefaultsConfirmation = false
    @State private var runningTask: Task<Void, Never>?
    @State private var progressPulseTask: Task<Void, Never>?
    @State private var progressSnapshot: SableLibraryProgressSnapshot?
    @State private var lastProgressUIUpdate = Date.distantPast
    @State private var lastActivityUIUpdate = Date.distantPast
    @State private var pipelineRun: LibraryPipelineRun?
    @State private var pipelineApplyResult: LibraryApplyResult?
    @State private var pipelineSummary: LibraryPipelineSummary?
    @State private var pendingPipelineQuickCheck: PendingPipelineQuickCheck?

    @StateObject private var service = SableLibraryService()
    private let settings = SableLibraryUserSettings()

    init(mode: SableLibraryAppMode = .library) {
        self.mode = mode
        _currentActivity = State(initialValue: mode.waitingActivity)
    }

    var body: some View {
        SableLibraryPipelineDashboardView(
            appMode: mode,
            libraryURL: libraryURL,
            run: libraryURL == nil ? nil : pipelineRun,
            isWorking: isRunning,
            statusText: status,
            currentActivity: currentActivity,
            learnedDecisionCount: learnedDecisionCount,
            progressSnapshot: progressSnapshot,
            applyResult: libraryURL == nil ? nil : pipelineApplyResult,
            pipelineSummary: libraryURL == nil ? nil : pipelineSummary,
            canQuickCheck: libraryURL != nil && pendingPipelineQuickCheck != nil,
            folderOrganizationDepth: cleanupOptions.readingFolderOrganizationDepth,
            epubClinicModifiedWindow: pipelineStageOptions.epubClinicModifiedWindow,
            modifiedWindowsByStage: pipelineStageOptions.modifiedWindowsByStage,
            onChooseFolder: chooseLibraryFolder,
            onDropFolder: selectDroppedLibraryFolder,
            onInspect: inspectPipeline,
            onQuickCheck: quickCheckPipeline,
            onOpenReports: openReportFolder,
            onRestoreLastApply: restoreLastApply,
            onDoctorCheck: runDoctorCheck,
            onStop: stopRunningTool,
            onOpenSettings: { openSettings() },
            onDecisionChange: updatePipelineDecision,
            onBulkDecisionChange: updatePipelineDecisions,
            onCorrection: markPipelineCorrection,
            onBulkCorrection: markPipelineCorrections,
            onCorrectionNoteChange: updatePipelineCorrectionNote,
            onMangaBakaIDChange: updatePipelineMangaBakaID,
            onRanobeDBIDChange: updatePipelineRanobeDBID,
            onProviderIDChange: updatePipelineProviderID,
            onProviderCandidates: searchPipelineProviderCandidates,
            onCoverSeriesMatchChange: updatePipelineCoverSeriesMatch,
            onCoverSeriesCandidates: searchPipelineCoverSeriesCandidates,
            onStageDeepInspect: inspectPipelineStage,
            onClinicCheck: inspectEPUBClinic,
            onFolderOrganizationDepthChange: updateFolderOrganizationDepth,
            onEPUBClinicModifiedWindowChange: updateEPUBClinicModifiedWindow,
            onStageModifiedWindowChange: updateStageModifiedWindow,
            onApplyStage: applyPipelineStage,
            onApplyStageItems: applyPipelineStageItems,
            onApplyCovers: applyPipelineCovers,
            onBatchRefreshExactIDs: batchRefreshExactIDs
        )
        .frame(minWidth: 1040, minHeight: 700)
        .sableLibraryAmbientBackground()
        .tint(palette.accent)
        .toolbar {
            macToolbar
        }
        .accessibilityElement(children: .contain)
        .sheet(isPresented: $showOnboarding) {
            SableLibraryOnboardingView(
                hasLibraryFolder: libraryURL != nil,
                onChooseFolder: chooseLibraryFolder,
                onInspect: inspectPipeline,
                onOpenSettings: { openSettings() },
                onFinish: { hasSeenOnboarding = true },
                selectedStep: $onboardingStep
            )
        }
        .confirmationDialog(
            "Reset Sable defaults?",
            isPresented: $showResetDefaultsConfirmation
        ) {
            Button("Reset Defaults", role: .destructive) {
                resetToolSettings()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This restores cleanup, review step, and assist settings to safe defaults. It does not change library files, receipts, or remembered folder access.")
        }
        .onAppear {
            sableWorkflowLogger.info("Main window appeared")
            configureProgressHandler()
            restoreSavedState()
            if mode.showsOnboarding && !hasSeenOnboarding {
                DispatchQueue.main.async {
                    showOnboarding = true
                }
            }
        }
        .onDisappear {
            releaseLibraryAccess()
        }
        .onChange(of: cleanupOptions) { _, newValue in
            settings.saveCleanupOptions(newValue)
        }
        .onChange(of: pipelineStageOptions) { _, newValue in
            settings.savePipelineStageOptions(newValue)
        }
        .onChange(of: intelligenceOptions) { _, newValue in
            settings.saveIntelligenceOptions(newValue)
        }
        .focusedSceneValue(\.sableLibraryCommands, commandActions)
        .task {
            for await _ in NotificationCenter.default.notifications(named: .sableLibrarySettingsChanged) {
                await MainActor.run {
                    reloadSavedPreferences()
                }
            }
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: .sableLibraryShowOnboarding) {
                await MainActor.run {
                    showOnboardingGuide()
                }
            }
        }
    }

    private var commandActions: SableLibraryCommandActions {
        SableLibraryCommandActions(
            chooseFolder: chooseLibraryFolder,
            inspectLibrary: inspectPipeline,
            openReports: openReportFolder,
            openSettings: { openSettings() },
            stop: stopRunningTool,
            resetToolSettings: confirmResetToolSettings,
            showOnboarding: showOnboardingGuide,
            canRun: libraryURL != nil && hasLibraryAccess && !isRunning,
            canOpenReports: libraryURL != nil && hasLibraryAccess,
            isRunning: isRunning
        )
    }

    @ToolbarContentBuilder
    private var macToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button(action: chooseLibraryFolder) {
                Label(libraryURL == nil ? "Choose Folder" : "Change Folder", systemImage: "folder.badge.plus")
            }
            .help(mode == .clinic ? "Choose a different EPUB folder." : "Choose a different library folder.")
            .disabled(isRunning)

            Button(action: inspectPipeline) {
                Label(mode.inspectActionTitle, systemImage: "magnifyingglass")
            }
            .help(mode.inspectActionHelp)
            .disabled(libraryURL == nil || !hasLibraryAccess || isRunning)
            .keyboardShortcut("f", modifiers: [.command, .shift])
        }

        ToolbarSpacer(.fixed, placement: .primaryAction)

        ToolbarItemGroup(placement: .primaryAction) {
            Button(action: openReportFolder) {
                Label("Reports", systemImage: "doc.text.magnifyingglass")
            }
            .help("Open the report folder in Finder.")
            .disabled(libraryURL == nil || !hasLibraryAccess)
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Button {
                openSettings()
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .help("Open app settings.")
            .disabled(isRunning)
        }

        if isRunning {
            ToolbarSpacer(.fixed, placement: .primaryAction)

            ToolbarItem(placement: .primaryAction) {
                Button(role: .cancel, action: stopRunningTool) {
                    Label("Stop", systemImage: "stop.circle")
                }
                .help("Stop after the current file or network request finishes.")
                .keyboardShortcut(".", modifiers: [.command])
            }
        }
    }

    private var pipelineOptions: LibraryPipelineOptions {
        var stageOptions = pipelineStageOptions
        switch mode {
        case .library:
            stageOptions.repairEPUBs = false
            stageOptions.downloadSeriesCovers = false
        case .clinic:
            stageOptions.repairEPUBs = true
            stageOptions.downloadSeriesCovers = false
            stageOptions.applyCleanup = false
            stageOptions.moveMissingNumbers = false
            stageOptions.refreshComicInfo = false
            stageOptions.epubClinicRepairScopes.subtract([.cover, .readerImport])
        case .covers:
            stageOptions.repairEPUBs = true
            stageOptions.downloadSeriesCovers = true
            stageOptions.applyCleanup = false
            stageOptions.moveMissingNumbers = false
            stageOptions.refreshComicInfo = false
            stageOptions.deepEPUBContentChecks = false
            stageOptions.optimizePageImageEPUBs = false
            stageOptions.epubClinicRepairScopes = [.cover]
        }

        var intelligence = intelligenceOptions
        if mode != .library {
            intelligence.useLocalLearning = false
        }

        return LibraryPipelineOptions(
            cleanup: cleanupOptions,
            stages: stageOptions,
            intelligence: intelligence,
            learning: intelligence.useLocalLearning ? learningMemory : SableLibraryLearningMemory()
        )
    }

    private func showOnboardingGuide() {
        sableWorkflowLogger.info("Showing onboarding guide")
        onboardingStep = 0
        showOnboarding = true
    }

    private func confirmResetToolSettings() {
        guard !isRunning else { return }
        showResetDefaultsConfirmation = true
    }

    private func openReportFolder() {
        guard let libraryURL else {
            status = mode.chooseFolderFirstStatus
            return
        }
        guard ensureLibraryAccess(for: libraryURL) else { return }
        let reportURL = libraryURL.appendingPathComponent(SableLibraryConfig.fallback.reportFolderName, isDirectory: true)
        #if os(macOS)
        let reportPath = reportURL.path(percentEncoded: false)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: reportPath, isDirectory: &isDirectory), !isDirectory.boolValue {
            status = "Report folder blocked"
            currentActivity = "A file already exists where the report folder should be: \(reportPath)"
            return
        }

        do {
            if !FileManager.default.fileExists(atPath: reportPath) {
                try FileManager.default.createDirectory(at: reportURL, withIntermediateDirectories: true)
            }
        } catch {
            status = "Could not open reports"
            currentActivity = "The report folder could not be created: \(error.localizedDescription)"
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([reportURL])
        #endif
        addActivity("Opened report folder")
    }

    private func restoreLastApply() {
        configureProgressHandler()
        guard let libraryURL else {
            status = mode.chooseFolderFirstStatus
            return
        }
        guard ensureLibraryAccess(for: libraryURL) else { return }

        isRunning = true
        startProgressPulse()
        status = "Restoring last apply..."
        addActivity("Restoring files from the latest undo plan.")

        let runURL = libraryURL
        let service = service
        runningTask = Task { @MainActor in
            let result = await service.restoreLastApply(root: runURL)
            guard !Task.isCancelled else {
                finishStoppedRun()
                return
            }

            pipelineApplyResult = result
            pendingPipelineQuickCheck = nil
            if let plan = pipelineRun?.context.plan {
                pipelineSummary = SableLibraryPipelineCoordinator(service: service).summarize(plan, lastApplyResult: result)
            } else {
                pipelineSummary = LibraryPipelineSummary(
                    title: result.appliedCount > 0 ? "Restore finished" : "Restore did not change files",
                    message: result.summary.components(separatedBy: .newlines).first ?? result.summary,
                    nextAction: .inspect,
                    plannedCount: 0,
                    unresolvedCount: 0,
                    appliedCount: result.appliedCount
                )
            }
            status = result.appliedCount > 0 ? "Restore finished" : "Nothing restored"
            addActivity(result.summary)
            currentActivity = status
            finishRun()
        }
    }

    private func runDoctorCheck() {
        guard let libraryURL else {
            status = mode.chooseFolderFirstStatus
            return
        }
        guard ensureLibraryAccess(for: libraryURL) else { return }

        let config = service.currentConfig()
        let fileManager = FileManager.default
        let reportFolder = service.reportDirectory(root: libraryURL, config: config)
        let undoPlan = reportFolder.appendingPathComponent(config.reports.undoPlanJSON)
        let duplicateFolder = libraryURL.appendingPathComponent(config.duplicateFolderName, isDirectory: true)
        let missingNumberFolder = libraryURL.appendingPathComponent(config.missingNumberFolderName, isDirectory: true)

        let checks: [(String, Bool, String)] = [
            ("Library folder exists", fileManager.fileExists(atPath: libraryURL.path(percentEncoded: false)), libraryURL.path(percentEncoded: false)),
            ("Library folder is readable", fileManager.isReadableFile(atPath: libraryURL.path(percentEncoded: false)), libraryURL.path(percentEncoded: false)),
            ("Reports folder", fileManager.fileExists(atPath: reportFolder.path(percentEncoded: false)), reportFolder.path(percentEncoded: false)),
            ("Undo plan", fileManager.fileExists(atPath: undoPlan.path(percentEncoded: false)), undoPlan.path(percentEncoded: false)),
            ("Duplicate folder", fileManager.fileExists(atPath: duplicateFolder.path(percentEncoded: false)), duplicateFolder.path(percentEncoded: false)),
            ("Missing-number folder", fileManager.fileExists(atPath: missingNumberFolder.path(percentEncoded: false)), missingNumberFolder.path(percentEncoded: false))
        ]

        var lines = [
            "\(mode.appName) doctor check",
            "===========================",
            "",
            "\(mode == .clinic ? "EPUB folder" : mode == .covers ? "Cover library folder" : "Library folder"): \(libraryURL.path(percentEncoded: false))",
            "Selected folder access: \(hasLibraryAccess ? "yes" : "no")",
            "Current plan rows: \(pipelineRun?.context.plan.activeItems.count ?? 0)",
            "Current unresolved rows: \(pipelineRun?.context.plan.unresolvedItems.count ?? 0)",
            ""
        ]

        for check in checks {
            lines.append("\(check.1 ? "OK" : "Check"): \(check.0)")
            lines.append("  \(check.2)")
        }

        lines.append("")
        lines.append("Safe defaults")
        lines.append("  Duplicate folder: \(config.duplicateFolderName)")
        lines.append("  Missing-number folder: \(config.missingNumberFolderName)")
        lines.append("  Report folder: \(config.reportFolderName)")
        lines.append("  ComicInfo file: \(config.comicInfoFileName)")

        do {
            let reportName = "_sable_doctor.txt"
            let report = lines.joined(separator: "\n")
            try service.writeReport(report, named: reportName, root: libraryURL, config: config)
            let receiptPath = reportFolder.appendingPathComponent(reportName).path(percentEncoded: false)
            pipelineApplyResult = LibraryApplyResult(
                appliedCount: 0,
                skippedCount: 0,
                receiptPath: receiptPath,
                summary: report
            )
            status = "Doctor check finished"
            addActivity("Doctor check written to \(receiptPath).")
        } catch {
            status = "Doctor check failed"
            addActivity("Doctor check could not be written: \(error.localizedDescription)")
        }
    }

    private func resetToolSettings() {
        cleanupOptions = CleanupOptions()
        pipelineStageOptions = LibraryPipelineStageOptions()
        intelligenceOptions = SableLibraryIntelligenceOptions()
        settings.resetToolOptions()
        status = "Defaults reset"
        currentActivity = "The cleanup settings are back to safe defaults"
    }

    private func restoreSavedState() {
        reloadSavedPreferences()
        if let savedURL = settings.loadLibraryFolder() {
            libraryURL = savedURL
            if ensureLibraryAccess(for: savedURL) {
                status = mode == .clinic
                    ? "Selected saved EPUB folder"
                    : mode == .covers
                    ? "Selected saved cover library"
                    : "Selected saved library folder"
                currentActivity = mode == .clinic
                    ? "EPUB folder restored"
                    : mode == .covers
                    ? "Cover library restored"
                    : "Library folder restored"
            }
        } else if libraryURL != nil
            || pipelineRun != nil
            || pipelineApplyResult != nil
            || pipelineSummary != nil
            || pendingPipelineQuickCheck != nil {
            releaseLibraryAccess()
            libraryURL = nil
            clearPipelineDesk()
            status = mode == .clinic
                ? "Saved EPUB folder forgotten"
                : mode == .covers
                ? "Saved cover library forgotten"
                : "Saved library folder forgotten"
            currentActivity = mode.waitingActivity
        }
    }

    private func reloadSavedPreferences() {
        let wasUsingLocalLearning = intelligenceOptions.useLocalLearning
        cleanupOptions = settings.loadCleanupOptions()
        pipelineStageOptions = settings.loadPipelineStageOptions()
        intelligenceOptions = settings.loadIntelligenceOptions()
        if mode != .library {
            intelligenceOptions.useLocalLearning = false
        }

        if intelligenceOptions.useLocalLearning {
            if !wasUsingLocalLearning || learnedDecisionCount == 0 {
                reloadLearningMemory()
            }
        } else {
            learningMemory = SableLibraryLearningMemory()
            learnedDecisionCount = 0
        }
    }

    private func reloadLearningMemory() {
        guard intelligenceOptions.useLocalLearning else {
            learningMemory = SableLibraryLearningMemory()
            learnedDecisionCount = 0
            return
        }
        learningMemory = settings.loadLearningMemory()
        learnedDecisionCount = learningMemory.learnedDecisionCount
    }

    private func saveLightweightLearningMemory() {
        learningMemory.pruneForLightweightStorage()
        settings.saveLearningMemory(learningMemory)
        learnedDecisionCount = learningMemory.learnedDecisionCount
    }

    private func configureProgressHandler() {
        service.progressHandler = { message in
            Task { @MainActor in
                recordActivity(message, throttled: true)
            }
        }
        service.progressSnapshotHandler = { snapshot in
            Task { @MainActor in
                applyProgressSnapshot(snapshot)
            }
        }
    }

    private func addActivity(_ message: String) {
        recordActivity(message)
    }

    @MainActor
    private func applyProgressSnapshot(_ snapshot: SableLibraryProgressSnapshot?) {
        guard let snapshot else {
            if progressSnapshot != nil {
                progressSnapshot = nil
            }
            lastProgressUIUpdate = .distantPast
            return
        }

        let now = Date()
        let previous = progressSnapshot
        let completed = snapshot.clampedTotalUnitCount > 0
            && snapshot.clampedCompletedUnitCount >= snapshot.clampedTotalUnitCount
        let shouldUpdate = previous == nil
            || previous?.title != snapshot.title
            || previous?.totalUnitCount != snapshot.totalUnitCount
            || completed
            || now.timeIntervalSince(lastProgressUIUpdate) >= sableProgressUIUpdateInterval

        guard shouldUpdate else { return }
        progressSnapshot = snapshot
        lastProgressUIUpdate = now
        recordActivity(snapshot.message, throttled: true)
    }

    private func recordActivity(_ message: String, throttled: Bool = false) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != currentActivity else { return }

        if throttled {
            let now = Date()
            guard now.timeIntervalSince(lastActivityUIUpdate) >= sableActivityUIUpdateInterval else { return }
            lastActivityUIUpdate = now
        } else {
            lastActivityUIUpdate = Date()
        }

        currentActivity = trimmed
    }

    private func clearPipelineDesk() {
        pipelineRun = nil
        pipelineApplyResult = nil
        pipelineSummary = nil
        pendingPipelineQuickCheck = nil
    }

    private func stopRunningTool() {
        guard isRunning else { return }
        sableWorkflowLogger.info("Stop requested for active workflow")
        runningTask?.cancel()
        status = "Stopping..."
        currentActivity = "Stopping after the current file or network request finishes."
        addActivity("Stop requested")
    }

    private func startProgressPulse() {
        progressPulseTask?.cancel()
        progressSnapshot = nil
        let startedAt = Date()
        progressPulseTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, isRunning else { break }
                let elapsed = max(5, Int(Date().timeIntervalSince(startedAt)))
                if progressSnapshot == nil {
                    recordActivity("Still working... \(elapsed)s elapsed")
                }
            }
        }
    }

    private func stopProgressPulse() {
        progressPulseTask?.cancel()
        progressPulseTask = nil
        lastProgressUIUpdate = .distantPast
    }

    private func chooseLibraryFolder() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"

        if panel.runModal() == .OK, let url = panel.url {
            selectLibraryFolder(url, source: .picker)
        }
        #endif
    }

    private func selectDroppedLibraryFolder(_ url: URL) {
        selectLibraryFolder(url, source: .drop)
    }

    private func selectLibraryFolder(_ url: URL, source: LibraryFolderSelectionSource) {
        sableWorkflowLogger.info("Selecting folder from \(source.logLabel, privacy: .public)")
        let selectedURL = url.standardizedFileURL
        #if os(macOS)
        var isDirectory: ObjCBool = false
        let selectedPath = selectedURL.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: selectedPath, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            status = "Choose a folder"
            currentActivity = source == .drop
                ? "The dropped item is not a folder. Drop or choose the top folder."
                : "Choose the top folder."
            return
        }
        #endif

        guard ensureLibraryAccess(for: selectedURL) else { return }
        let savedFolderAccess = settings.saveLibraryFolder(selectedURL)
        libraryURL = selectedURL
        sableWorkflowLogger.info("Folder selected and access confirmed")
        if savedFolderAccess {
            status = mode.selectedFolderStatus
            currentActivity = source == .drop ? mode.selectedFromDropActivity : mode.selectedFromPickerActivity
        } else {
            status = "Folder selected for now"
            currentActivity = "The folder is open for this session, but macOS did not save long-term access. Choose it again after restarting if needed."
        }
        clearPipelineDesk()
    }

    private func updateFolderOrganizationDepth(_ depth: SableLibraryFolderOrganizationDepth) {
        guard cleanupOptions.readingFolderOrganizationDepth != depth else { return }
        cleanupOptions.readingFolderOrganizationDepth = depth
        addActivity("Folder sorting depth set to \(depth.label).")
        guard mode == .library, libraryURL != nil, pipelineRun != nil else { return }
        status = "Folder depth updated"
        currentActivity = isRunning
            ? "The new folder depth is saved. Run folder sorting again after the current check finishes."
            : "The new folder depth is saved. Run folder sorting again when you want a fresh preview."
    }

    private func updateEPUBClinicModifiedWindow(_ window: SableEPUBClinicModifiedWindow) {
        guard pipelineStageOptions.epubClinicModifiedWindow != window else { return }
        pipelineStageOptions.epubClinicModifiedWindow = window
        addActivity("Clinic will check \(window.repairScopeDescription).")
    }

    private func updateStageModifiedWindow(
        _ stage: LibraryPipelineStage,
        _ window: SableLibraryModifiedWindow
    ) {
        guard pipelineStageOptions.modifiedWindow(for: stage) != window else { return }
        pipelineStageOptions.setModifiedWindow(window, for: stage)
        addActivity("\(stage.title) will check \(window.libraryScopeDescription).")
    }

    private func inspectPipeline() {
        if mode == .clinic {
            inspectClinicInventory()
            return
        }

        configureProgressHandler()
        guard let libraryURL else {
            status = mode.chooseFolderFirstStatus
            return
        }
        guard ensureLibraryAccess(for: libraryURL) else { return }

        service.clearScanCache()
        isRunning = true
        sableWorkflowLogger.info("Inspection started")
        startProgressPulse()
        status = "Scanning inventory..."
        pipelineApplyResult = nil
        pendingPipelineQuickCheck = nil
        addActivity("Mapping files, folders, sidecars, and quick triage facts. Specialist lanes stay asleep until opened.")

        let runURL = libraryURL
        let options = pipelineOptions
        let service = service
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        runningTask = Task {
            let worker = Task.detached(priority: .userInitiated) {
                await coordinator.inspectInventoryAndBuildPlan(root: runURL, options: options)
            }
            let run = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }

            await MainActor.run {
                guard !Task.isCancelled else {
                    finishStoppedRun()
                    return
                }
                pipelineRun = run
                if finishInspectionFailureIfNeeded(run) {
                    finishRun()
                    return
                }
                pipelineSummary = run.context.inspectMode == .lightInventory
                    ? LibraryPipelineSummary(
                        title: "Inventory & triage ready",
                        message: "Sable mapped the folder lightly. Open a cleanup lane only when you want those specialists to inspect more deeply.",
                        nextAction: .reviewDecisions,
                        plannedCount: 0,
                        unresolvedCount: 0,
                        appliedCount: 0
                    )
                    : coordinator.summarize(run.context.plan)
                status = run.context.inspectMode == .lightInventory
                    ? "Inventory & triage ready"
                    : (run.context.plan.activeItems.isEmpty ? mode.clearStatusTitle : "Review plan ready")
                sableWorkflowLogger.info("Inspection finished with \(run.context.plan.activeItems.count, privacy: .public) active suggestion(s)")
                addActivity(run.context.inspectMode == .lightInventory
                    ? "Inventory triage ready. Open a cleanup lane to wake its specialists."
                    : "Review plan ready with \(run.context.plan.activeItems.count) active suggestion(s).")
                addTimingActivity(for: run)
                currentActivity = status
                finishRun()
            }
        }
    }

    private func inspectClinicInventory() {
        configureProgressHandler()
        guard let libraryURL else {
            status = mode.chooseFolderFirstStatus
            return
        }
        guard ensureLibraryAccess(for: libraryURL) else { return }
        guard !isRunning else { return }

        service.clearScanCache()
        isRunning = true
        sableWorkflowLogger.info("Sable's Clinic inventory started")
        startProgressPulse()
        status = "Scanning EPUB inventory..."
        pipelineApplyResult = nil
        pendingPipelineQuickCheck = nil
        addActivity("Listing EPUB files and checking local sidecars. Deep EPUB checks stay asleep until you open the Clinic step.")

        let runURL = libraryURL
        let options = pipelineOptions
        let service = service
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        runningTask = Task {
            let worker = Task.detached(priority: .userInitiated) {
                await coordinator.inspectEPUBClinicInventoryAndBuildPlan(root: runURL, options: options)
            }
            let run = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }

            await MainActor.run {
                guard !Task.isCancelled else {
                    finishStoppedRun()
                    return
                }
                pipelineRun = run
                if finishInspectionFailureIfNeeded(run) {
                    finishRun()
                    return
                }

                let epubCount = run.context.inspection?.bookFileCount ?? 0
                let comicInfoCount = run.context.inspection?.comicInfoCount ?? 0
                let missingComicInfoCount = run.context.inspection?.missingComicInfoCount ?? 0
                let sidecarSummary = missingComicInfoCount > 0
                    ? "\(comicInfoCount) ComicInfo sidecar group(s) found; \(missingComicInfoCount) EPUB group(s) still need one."
                    : "\(comicInfoCount) ComicInfo sidecar group(s) found."
                pipelineSummary = LibraryPipelineSummary(
                    title: "EPUB inventory ready",
                    message: epubCount == 0
                        ? "No EPUB files were found in this folder."
                        : "Found \(epubCount) EPUB file\(epubCount == 1 ? "" : "s"). \(sidecarSummary) Open the Repair page when you want the deeper checker layers.",
                    nextAction: .reviewDecisions,
                    plannedCount: 0,
                    unresolvedCount: 0,
                    appliedCount: 0
                )
                status = epubCount == 0 ? "No EPUBs found" : "EPUB inventory ready"
                sableWorkflowLogger.info("Sable's Clinic inventory finished with \(epubCount, privacy: .public) EPUB file(s)")
                addActivity(epubCount == 0
                    ? "No EPUB files were found in this folder."
                    : "Found \(epubCount) EPUB file\(epubCount == 1 ? "" : "s") and checked local sidecars. Open the Repair page for checker layers.")
                addTimingActivity(for: run)
                currentActivity = status
                finishRun()
            }
        }
    }

    private func inspectPipelineStage(_ stage: LibraryPipelineStage) {
        inspectPipelineStage(stage, clinicProfile: nil)
    }

    private func inspectEPUBClinic(_ profile: SableClinicCheckProfile) {
        inspectPipelineStage(.epubClinic, clinicProfile: profile)
    }

    private func inspectPipelineStage(_ stage: LibraryPipelineStage, clinicProfile: SableClinicCheckProfile?) {
        configureProgressHandler()
        guard mode.workflowStages.contains(stage) else {
            status = "\(stage.title) belongs in another Sable app"
            currentActivity = stage == .covers
                ? "Open Sable's Covers for cover downloads, verification, and replacement."
                : "Open the matching Sable app for this workflow."
            return
        }
        guard let libraryURL else {
            status = mode.chooseFolderFirstStatus
            return
        }
        guard ensureLibraryAccess(for: libraryURL) else { return }
        guard !isRunning else { return }
        guard stage != .inspect, stage != .reviewApply else { return }

        isRunning = true
        sableWorkflowLogger.info("Specialist check started for \(stage.rawValue, privacy: .public)")
        startProgressPulse()
        let selectedClinicProfile = stage == .epubClinic
            ? clinicProfile ?? SableClinicCheckProfile.matching(
                scopes: pipelineOptions.stages.epubClinicRepairScopes,
                deepContentChecks: pipelineOptions.stages.deepEPUBContentChecks
            )
            : nil
        status = selectedClinicProfile?.workingStatus ?? "Checking \(stage.title)..."
        pipelineApplyResult = nil
        pendingPipelineQuickCheck = nil
        addActivity(selectedClinicProfile?.activityText ?? "Waking the \(stage.title) specialists only.")

        let runURL = libraryURL
        var options = pipelineOptions
        if let selectedClinicProfile {
            options.stages.deepEPUBContentChecks = selectedClinicProfile.runsDeepContentChecks
            options.stages.epubClinicRepairScopes = selectedClinicProfile.repairScopes
            if selectedClinicProfile != .content, selectedClinicProfile != .deep {
                options.stages.optimizePageImageEPUBs = false
            }
        }
        let service = service
        let coordinator = SableLibraryPipelineCoordinator(service: service)
        let priority: TaskPriority = stage == .epubClinic ? .utility : .userInitiated
        let runOptions = options
        runningTask = Task {
            let worker = Task.detached(priority: priority) {
                await coordinator.inspectStageAndBuildPlan(root: runURL, options: runOptions, stage: stage)
            }
            let run = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }

            await MainActor.run {
                guard !Task.isCancelled else {
                    finishStoppedRun()
                    return
                }
                pipelineRun = run
                if finishInspectionFailureIfNeeded(run) {
                    finishRun()
                    return
                }
                finishPipelineStageInspection(run, stage: stage, coordinator: coordinator, root: runURL, options: runOptions)
            }
        }
    }

    @MainActor
    private func finishPipelineStageInspection(
        _ run: LibraryPipelineRun,
        stage: LibraryPipelineStage,
        coordinator: SableLibraryPipelineCoordinator,
        root runURL: URL,
        options: LibraryPipelineOptions
    ) {
        runningTask = Task { @MainActor in
            guard !Task.isCancelled else {
                finishStoppedRun()
                return
            }
            if stage == .comicInfo,
               let refreshedRun = await applyReadyMetadataSidecarChangesIfNeeded(
                    from: run,
                    coordinator: coordinator,
                    root: runURL,
                    options: options
               ) {
                guard !Task.isCancelled else {
                    finishStoppedRun()
                    return
                }
                pipelineRun = refreshedRun
                if finishInspectionFailureIfNeeded(refreshedRun) {
                    finishRun()
                    return
                }
                finishRun()
                return
            }
            let emptyTitle: String
            let emptyMessage: String
            if stage == .epubClinic, mode == .clinic || mode == .covers {
                let profile = SableClinicCheckProfile.matching(
                    scopes: options.stages.epubClinicRepairScopes,
                    deepContentChecks: options.stages.deepEPUBContentChecks
                )
                emptyTitle = profile.emptyTitle
                emptyMessage = profile.emptyMessage
            } else {
                emptyTitle = "\(stage.title) looks clear"
                emptyMessage = "No suggestions are waiting in this lane. Other cleanup lanes can still be checked separately."
            }
            pipelineSummary = run.context.plan.activeItems.isEmpty
                ? LibraryPipelineSummary(
                    title: emptyTitle,
                    message: emptyMessage,
                    nextAction: .reviewDecisions,
                    plannedCount: 0,
                    unresolvedCount: 0,
                    appliedCount: 0
                )
                : coordinator.summarize(run.context.plan)
            status = run.context.plan.activeItems.isEmpty ? emptyTitle : "\(stage.title) review ready"
            sableWorkflowLogger.info("Specialist check finished for \(stage.rawValue, privacy: .public) with \(run.context.plan.activeItems.count, privacy: .public) active suggestion(s)")
            addActivity("\(stage.title) review ready with \(run.context.plan.activeItems.count) active suggestion(s).")
            addTimingActivity(for: run)
            currentActivity = status
            finishRun()
        }
    }

    @MainActor
    private func addTimingActivity(for run: LibraryPipelineRun) {
        guard let timingSummary = run.context.timingSummary else { return }
        addActivity("Timing: \(timingSummary).")
    }

    private func applyReadyMetadataSidecarChangesIfNeeded(
        from run: LibraryPipelineRun,
        coordinator: SableLibraryPipelineCoordinator,
        root runURL: URL,
        options: LibraryPipelineOptions
    ) async -> LibraryPipelineRun? {
        let readyItems = automaticMetadataSidecarItems(in: run.context.plan)
        guard !readyItems.isEmpty else { return nil }

        let itemIDs = readyItems.map(\.id)
        let plan = scopedApplyPlan(
            run.context.plan,
            stage: .comicInfo,
            itemIDs: itemIDs
        )
        let changedPathsBeforeApply = readyItems.compactMap { $0.proposedPath ?? $0.currentPath }

        status = "Running ready sidecar changes..."
        addActivity("Running \(readyItems.count) ready metadata sidecar change\(readyItems.count == 1 ? "" : "s") automatically.")

        let result = await coordinator.applyChecked(plan, stage: .comicInfo, options: options)
        guard !Task.isCancelled else { return nil }

        recordAppliedLearning(from: readyItems, result: result)
        pipelineApplyResult = result
        pipelineSummary = coordinator.summarize(plan, lastApplyResult: result)

        guard result.appliedCount > 0 else {
            status = result.skippedCount > 0 ? "Ready sidecar pass found no writes" : "Nothing applied"
            addActivity(result.summary)
            currentActivity = status
            return nil
        }

        let appliedChangedPaths = result.appliedPaths.compactMap { $0.proposedPath ?? $0.currentPath }
        let changedPaths = appliedChangedPaths.isEmpty ? changedPathsBeforeApply : appliedChangedPaths
        pendingPipelineQuickCheck = nil
        service.clearScanCache()
        status = "Refreshing metadata pass..."
        addActivity("Refreshing after automatic sidecar changes.")

        let refreshedRun = await coordinator.quickVerifyAndBuildPlan(
            root: runURL,
            options: options,
            previousStage: .comicInfo,
            changedPaths: changedPaths
        )
        guard !Task.isCancelled else { return nil }

        pipelineSummary = coordinator.summarize(refreshedRun.context.plan, lastApplyResult: result)
        status = "Sidecar pass finished"
        addActivity("Finished \(result.appliedCount) automatic sidecar change\(result.appliedCount == 1 ? "" : "s"). Anything still uncertain is waiting for review.")
        currentActivity = status
        return refreshedRun
    }

    private func automaticMetadataSidecarItems(in plan: LibraryPlan) -> [LibraryPlanItem] {
        plan.items.filter { item in
            guard item.stage == .comicInfo,
                  item.decision == .checked,
                  item.safety == .reversible,
                  !item.requiresReview,
                  item.isApplyableOperation else {
                return false
            }

            switch item.operation {
            case .createComicInfo, .createAnimeInfo:
                return !item.usedNetworkData || item.confidence != .low
            case .refreshComicInfo, .refreshAnimeInfo:
                return false
            case .inspectOnly, .repairEpubPackage, .repairAppleBooksCompatibility, .cleanRawName, .sortIntoFolder, .renameFolder, .renameFile, .duplicateDecision, .skip:
                return false
            }
        }
    }

    private func finishInspectionFailureIfNeeded(_ run: LibraryPipelineRun) -> Bool {
        guard let inspection = run.context.inspection,
              let failureNote = inspection.failureNote else {
            return false
        }

        pipelineSummary = LibraryPipelineSummary(
            title: inspection.needsFolderAccess ? "Choose folder again" : "Inspection did not finish",
            message: failureNote,
            nextAction: inspection.needsFolderAccess ? .chooseFolder : .inspect,
            plannedCount: 0,
            unresolvedCount: 0,
            appliedCount: pipelineApplyResult?.appliedCount ?? 0
        )
        status = inspection.needsFolderAccess ? "Choose folder again" : "Inspection failed"
        addActivity(failureNote)
        currentActivity = status
        return true
    }

    private func quickCheckPipeline() {
        configureProgressHandler()
        guard let libraryURL else {
            status = mode.chooseFolderFirstStatus
            return
        }
        guard ensureLibraryAccess(for: libraryURL) else { return }
        guard let pendingQuickCheck = pendingPipelineQuickCheck else {
            status = "Apply a checked step before checking again"
            return
        }
        guard mode.workflowStages.contains(pendingQuickCheck.stage) else {
            pendingPipelineQuickCheck = nil
            status = "This check belongs in another Sable app"
            currentActivity = pendingQuickCheck.stage == .covers
                ? "Open Sable's Covers to check cover work."
                : "Open the Sable app that owns this workflow."
            return
        }

        service.clearScanCache()
        isRunning = true
        sableWorkflowLogger.info("Quick check started for \(pendingQuickCheck.stage.rawValue, privacy: .public)")
        startProgressPulse()
        status = "Checking applied work..."
        addActivity("Checking the paths changed by \(pendingQuickCheck.stage.title).")

        let runURL = libraryURL
        let options = pipelineOptions
        let quickCheck = pendingQuickCheck
        let service = service
        runningTask = Task { @MainActor in
            let coordinator = SableLibraryPipelineCoordinator(service: service)
            let run = await coordinator.quickVerifyAndBuildPlan(
                root: runURL,
                options: options,
                previousStage: quickCheck.stage,
                changedPaths: quickCheck.paths
            )
            guard !Task.isCancelled else {
                finishStoppedRun()
                return
            }
            pipelineRun = run
            if finishInspectionFailureIfNeeded(run) {
                pendingPipelineQuickCheck = nil
                finishRun()
                return
            }
            pipelineSummary = coordinator.summarize(run.context.plan, lastApplyResult: pipelineApplyResult)
            pendingPipelineQuickCheck = nil
            status = quickCheck.stage == .epubClinic && run.context.plan.activeItems.isEmpty
                ? "Clinic verification clean"
                : "Quick check finished"
            sableWorkflowLogger.info("Quick check finished")
            addActivity(quickCheck.stage == .epubClinic && run.context.plan.activeItems.isEmpty
                ? "Clinic repairs were rechecked clean."
                : "Quick check finished.")
            currentActivity = status
            finishRun()
        }
    }

    private func applyPipelineStage(_ stage: LibraryPipelineStage, verifyAfterApply: Bool) {
        applyPipelineStage(
            stage,
            itemIDs: nil,
            verifyAfterApply: verifyAfterApply,
            coverDownloadPass: .combined
        )
    }

    private func applyPipelineStageItems(
        _ stage: LibraryPipelineStage,
        itemIDs: [LibraryPlanItem.ID],
        verifyAfterApply: Bool
    ) {
        applyPipelineStage(
            stage,
            itemIDs: itemIDs,
            verifyAfterApply: verifyAfterApply,
            coverDownloadPass: .combined
        )
    }

    private func applyPipelineCovers(
        _ itemIDs: [LibraryPlanItem.ID]?,
        pass: SableLibraryCoverDownloadPass
    ) {
        applyPipelineStage(
            .covers,
            itemIDs: itemIDs,
            verifyAfterApply: false,
            coverDownloadPass: pass
        )
    }

    private func batchRefreshExactIDs(
        _ stage: LibraryPipelineStage,
        itemIDs: [LibraryPlanItem.ID]
    ) {
        configureProgressHandler()
        guard mode.workflowStages.contains(stage) else {
            status = "This step belongs in the other app"
            return
        }
        guard let currentRun = pipelineRun else {
            status = "Inspect the library first"
            return
        }

        let plan = scopedApplyPlan(
            currentRun.context.plan,
            stage: stage,
            itemIDs: itemIDs
        )
        let options = currentRun.context.options
        let runURL = URL(fileURLWithPath: plan.rootPath, isDirectory: true)
        guard ensureLibraryAccess(for: runURL) else { return }

        let batchItems = plan.checkedItems.filter { item in
            item.stage == stage && item.isExactIDBatchRefreshCandidate
        }
        guard !batchItems.isEmpty else {
            status = "No saved-ID refresh rows are ready"
            return
        }

        isRunning = true
        sableWorkflowLogger.info("Exact-ID metadata batch started for \(stage.rawValue, privacy: .public) with \(batchItems.count, privacy: .public) item(s)")
        startProgressPulse()
        status = "Batch refreshing saved IDs by provider..."
        addActivity("Refreshing \(batchItems.count) checked metadata row\(batchItems.count == 1 ? "" : "s") in provider passes from saved IDs.")

        let requestedChangedPaths = batchItems.compactMap { $0.proposedPath ?? $0.currentPath }
        let selectedIDs = Set(itemIDs)
        let service = service
        runningTask = Task { @MainActor in
            let coordinator = SableLibraryPipelineCoordinator(service: service)
            let result = await coordinator.applyExactIDBatch(
                plan,
                stage: stage,
                itemIDs: selectedIDs,
                options: options
            )
            guard !Task.isCancelled else {
                finishStoppedRun()
                return
            }

            recordAppliedLearning(from: batchItems, result: result)
            pipelineApplyResult = result
            pipelineSummary = coordinator.summarize(plan, lastApplyResult: result)
            let appliedChangedPaths = result.appliedPaths.compactMap { $0.proposedPath ?? $0.currentPath }
            let changedPaths = appliedChangedPaths.isEmpty ? requestedChangedPaths : appliedChangedPaths
            pendingPipelineQuickCheck = result.appliedCount > 0 ? PendingPipelineQuickCheck(stage: stage, paths: changedPaths) : nil

            if result.appliedCount > 0 {
                service.clearScanCache()
                let refreshStages = stage.automaticRefreshStages(
                    options: options,
                    focusedMetadataApply: false
                )
                status = "Refreshing metadata, folders, and file names..."
                addActivity("Refreshing saved metadata and rebuilding downstream folder and file-name suggestions.")
                let run = await coordinator.quickVerifyAndBuildPlan(
                    root: runURL,
                    options: options,
                    previousStage: stage,
                    changedPaths: changedPaths,
                    refreshStages: refreshStages
                )
                guard !Task.isCancelled else {
                    finishStoppedRun()
                    return
                }
                pipelineRun = run
                if finishInspectionFailureIfNeeded(run) {
                    pendingPipelineQuickCheck = nil
                    finishRun()
                    return
                }
                let updatedRun = mergingRefreshedStages(
                    refreshStages,
                    from: run,
                    into: currentRun
                )
                pipelineRun = updatedRun
                pipelineSummary = coordinator.summarize(updatedRun.context.plan, lastApplyResult: result)
                pendingPipelineQuickCheck = nil
                status = "Saved IDs and naming refreshed"
                sableWorkflowLogger.info("Exact-ID metadata batch finished for \(stage.rawValue, privacy: .public); applied \(result.appliedCount, privacy: .public) item(s)")
                addActivity("Saved-ID batch finished; provider, folder, and file-name suggestions are current.")
                currentActivity = status
                finishRun()
                return
            }

            status = result.skippedCount > 0 ? "Saved-ID batch found no writes" : "Nothing applied"
            sableWorkflowLogger.info("Exact-ID metadata batch finished for \(stage.rawValue, privacy: .public); applied \(result.appliedCount, privacy: .public) item(s)")
            addActivity(result.summary)
            currentActivity = status
            finishRun()
        }
    }

    private func applyPipelineStage(
        _ stage: LibraryPipelineStage,
        itemIDs: [LibraryPlanItem.ID]?,
        verifyAfterApply: Bool,
        coverDownloadPass: SableLibraryCoverDownloadPass
    ) {
        configureProgressHandler()
        guard mode.workflowStages.contains(stage) else {
            status = "\(stage.title) belongs in another Sable app"
            currentActivity = stage == .covers
                ? "Open Sable's Covers to apply cover work."
                : "Open the Sable app that owns this workflow."
            return
        }
        guard let currentRun = pipelineRun else {
            status = "Inspect the library first"
            return
        }
        let plan = scopedApplyPlan(
            currentRun.context.plan,
            stage: stage,
            itemIDs: itemIDs
        )
        let options = currentRun.context.options
        let runURL = URL(fileURLWithPath: plan.rootPath, isDirectory: true)
        guard ensureLibraryAccess(for: runURL) else { return }

        let checkedItems = plan.checkedItems.filter { item in
            item.stage == stage && item.isApplyableOperation
        }
        guard !checkedItems.isEmpty else {
            status = "Check at least one safe change first"
            return
        }
        let verifiesExistingCoverEvidence = stage == .covers && checkedItems.allSatisfy {
            $0.reviewTags.contains("cover-manifest-unverified")
        }

        isRunning = true
        let scopeText = itemIDs == nil ? "stage" : "checkpoint"
        let checkedPathCount = Set(checkedItems.map(\.currentPath)).count
        let checkedItemText = checkedPathCount == checkedItems.count
            ? "\(checkedItems.count) checked item(s)"
            : "\(checkedItems.count) checked repair row(s) across \(checkedPathCount) file(s)"
        sableWorkflowLogger.info("Apply started for \(stage.rawValue, privacy: .public) \(scopeText, privacy: .public) with \(checkedItemText, privacy: .public)")
        startProgressPulse()
        status = "Applying \(stage.title)..."
        addActivity(
            itemIDs == nil
                ? "Applying \(checkedItemText) from \(stage.title)."
                : "Applying \(checkedItemText) from this \(stage.title) pass."
        )

        let requestedChangedPaths = checkedItems.compactMap { $0.proposedPath ?? $0.currentPath }
        let isRepeatableReaderImportRefresh = stage == .epubClinic
            && checkedItems.allSatisfy(\.isReaderImportRefreshOnly)
        let service = service
        runningTask = Task { @MainActor in
            let coordinator = SableLibraryPipelineCoordinator(service: service)
            let result = await coordinator.applyChecked(
                plan,
                stage: stage,
                options: options,
                coverDownloadPass: coverDownloadPass
            )
            guard !Task.isCancelled else {
                finishStoppedRun()
                return
            }
            recordAppliedLearning(from: checkedItems, result: result)
            pipelineApplyResult = result
            pipelineSummary = coordinator.summarize(plan, lastApplyResult: result)
            let appliedChangedPaths = result.appliedPaths.compactMap { $0.proposedPath ?? $0.currentPath }
            let changedPaths = appliedChangedPaths.isEmpty ? requestedChangedPaths : appliedChangedPaths
            pendingPipelineQuickCheck = result.appliedCount > 0 ? PendingPipelineQuickCheck(stage: stage, paths: changedPaths) : nil
            let isFocusedMetadataApply = itemIDs != nil && stage.isMetadataSidecarStage
            let didAttemptCoverSearch = stage == .covers
                && !checkedItems.isEmpty
                && (result.appliedCount > 0 || result.skippedCount > 0)
            let automaticRefreshStages = stage.automaticRefreshStages(
                options: options,
                focusedMetadataApply: isFocusedMetadataApply
            )
            let refreshStages = automaticRefreshStages.isEmpty && verifyAfterApply
                ? [stage]
                : automaticRefreshStages
            let shouldVerifyAfterApply = !isFocusedMetadataApply
                && !isRepeatableReaderImportRefresh
                && (result.appliedCount > 0 || didAttemptCoverSearch)
                && (verifyAfterApply || !refreshStages.isEmpty)

            if shouldVerifyAfterApply {
                // Cover downloads do not change the library's books or series folders.
                // Reuse the inventory gathered for this review so a small cover refresh
                // does not synchronously walk the entire library again.
                if stage != .covers {
                    service.clearScanCache()
                }
                status = postApplyRefreshStatus(for: stage)
                addActivity(
                    postApplyRefreshActivity(for: stage)
                )
                let run = await coordinator.quickVerifyAndBuildPlan(
                    root: runURL,
                    options: options,
                    previousStage: stage,
                    changedPaths: changedPaths,
                    refreshStages: refreshStages
                )
                guard !Task.isCancelled else {
                    finishStoppedRun()
                    return
                }
                if finishInspectionFailureIfNeeded(run) {
                    pendingPipelineQuickCheck = nil
                    finishRun()
                    return
                }
                var updatedRun = mergingRefreshedStages(
                    refreshStages,
                    from: run,
                    into: currentRun
                )
                if stage == .covers {
                    updatedRun.context.plan.clearCheckedItems(
                        stage: .covers,
                        itemIDs: Set(checkedItems.map(\.id))
                    )
                }
                pipelineRun = updatedRun
                if stage == .covers {
                    let searchedCount = result.appliedCount + result.skippedCount
                    if verifiesExistingCoverEvidence {
                        let checkedProofPaths = Set(
                            checkedItems.map(\.currentPath)
                        )
                        let unresolvedProofPaths = Set(
                            updatedRun.context.plan.items.lazy
                                .filter {
                                    $0.stage == .covers
                                        && checkedProofPaths.contains($0.currentPath)
                                        && (
                                            $0.reviewTags.contains(
                                                "cover-manifest-needs-store-check"
                                            )
                                                || $0.reviewTags.contains(
                                                    "cover-manifest-conflict"
                                                )
                                        )
                                }
                                .map(\.currentPath)
                        )
                        let verifiedProofCount = max(
                            0,
                            checkedProofPaths.count - unresolvedProofPaths.count
                        )
                        let proofOutcome =
                            "\(verifiedProofCount) moved to Complete; "
                            + "\(unresolvedProofPaths.count) could not be confirmed by the saved store pages."
                        pipelineSummary = LibraryPipelineSummary(
                            title: "Store proof check finished",
                            message: "Checked \(searchedCount) series. \(proofOutcome) Existing cover images and EPUBs were untouched. Unconfirmed records and store conflicts are separated below.",
                            nextAction: updatedRun.context.plan.activeItems.isEmpty ? .checkAgain : .reviewDecisions,
                            plannedCount: updatedRun.context.plan.activeItems.count,
                            unresolvedCount: updatedRun.context.plan.unresolvedItems.count,
                            appliedCount: result.appliedCount
                        )
                    } else {
                        let downloadedCoverCount = coverDownloadCount(in: result.summary)
                        let providerWasBusy = result.summary.contains("HTTP 429")
                            || result.summary.localizedCaseInsensitiveContains("temporarily unavailable")
                        let resultText: String
                        if result.skippedCount == 0 {
                            let fileOutcome = downloadedCoverCount == 0
                                ? "No new cover files passed the safety checks; existing trusted covers were retained."
                                : "\(downloadedCoverCount) new cover file\(downloadedCoverCount == 1 ? "" : "s") passed the safety checks."
                            resultText = "All \(result.appliedCount) selected series finished without an operational error. \(fileOutcome) Any remaining language or volume gaps are listed below."
                        } else if result.appliedCount == 0, providerWasBusy {
                            resultText = "The cover service was temporarily busy, so no series was treated as a trustworthy no-cover result. The rows are unchecked and safe to retry later."
                        } else if result.appliedCount == 0 {
                            resultText = "No trusted result was found for the \(result.skippedCount) selected series. They are now unchecked and separated from series that have not been searched."
                        } else if providerWasBusy {
                            resultText = "\(result.appliedCount) series finished. Busy sources were skipped in favor of available backups; \(result.skippedCount) series remain unchecked for review."
                        } else {
                            resultText = "\(result.appliedCount) series finished. \(result.skippedCount) searches finished with no trusted result and are now unchecked for review."
                        }
                        pipelineSummary = LibraryPipelineSummary(
                            title: "Cover search finished",
                            message: "Checked \(searchedCount) series. \(resultText)",
                            nextAction: updatedRun.context.plan.activeItems.isEmpty ? .checkAgain : .reviewDecisions,
                            plannedCount: updatedRun.context.plan.activeItems.count,
                            unresolvedCount: updatedRun.context.plan.unresolvedItems.count,
                            appliedCount: result.appliedCount
                        )
                    }
                } else {
                    pipelineSummary = coordinator.summarize(updatedRun.context.plan, lastApplyResult: result)
                }
                pendingPipelineQuickCheck = nil
                if stage == .covers {
                    status = verifiesExistingCoverEvidence
                        ? "Store proof check finished"
                        : "Cover search finished"
                } else if stage.isMetadataSidecarStage {
                    status = "Metadata and naming refreshed"
                } else if stage == .canonicalFolders {
                    status = "Folders and file names refreshed"
                } else if stage == .canonicalFiles {
                    status = "File names refreshed"
                } else if stage == .epubClinic, updatedRun.context.plan.activeItems.isEmpty {
                    status = "Clinic verification clean"
                } else if stage == .epubClinic {
                    status = "Clinic recheck found rows"
                } else {
                    status = "Apply and check finished"
                }
                sableWorkflowLogger.info("Apply and refresh finished for \(stage.rawValue, privacy: .public); applied \(result.appliedCount, privacy: .public) item(s)")
                if stage == .covers {
                    addActivity(
                        verifiesExistingCoverEvidence
                            ? "Store proof check finished. Existing images were kept; ambiguous and conflicting records are separated for review."
                            : "Cover search finished. Attempted series are unchecked and sorted by outcome."
                    )
                } else if stage.isMetadataSidecarStage {
                    addActivity("Metadata pass finished; provider, folder, and file-name suggestions are current.")
                } else if stage == .canonicalFolders {
                    addActivity("Folder moves finished; Folder Sorting and File Names were rescanned.")
                } else if stage == .canonicalFiles {
                    addActivity("File renames finished and File Names was rescanned.")
                } else if stage == .epubClinic, updatedRun.context.plan.activeItems.isEmpty {
                    addActivity("Clinic repairs were applied and the changed EPUBs rechecked clean.")
                } else if stage == .epubClinic {
                    addActivity("Clinic repairs were applied and the recheck found more rows to review.")
                } else {
                    addActivity("Apply and check finished.")
                }
                currentActivity = status
                finishRun()
                return
            }

            if isFocusedMetadataApply, result.appliedCount > 0 {
                let appliedPathSet = Set(result.appliedPaths.map(\.currentPath))
                let appliedItemIDs = Set(checkedItems.lazy
                    .filter { appliedPathSet.contains($0.currentPath) }
                    .map(\.id))
                var updatedRun = currentRun
                updatedRun.context.plan.groups = updatedRun.context.plan.groups.compactMap { group in
                    guard group.stage == stage else { return group }
                    var updatedGroup = group
                    updatedGroup.items.removeAll { appliedItemIDs.contains($0.id) }
                    return updatedGroup.items.isEmpty ? nil : updatedGroup
                }

                if !refreshStages.isEmpty {
                    service.clearScanCache()
                    status = "Refreshing folder and file suggestions..."
                    addActivity("Provider match saved. Rescanning Folder Sorting and File Names.")
                    let refreshedRun = await coordinator.quickVerifyAndBuildPlan(
                        root: runURL,
                        options: options,
                        previousStage: stage,
                        changedPaths: changedPaths,
                        refreshStages: refreshStages
                    )
                    guard !Task.isCancelled else {
                        finishStoppedRun()
                        return
                    }
                    if finishInspectionFailureIfNeeded(refreshedRun) {
                        pendingPipelineQuickCheck = nil
                        finishRun()
                        return
                    }
                    updatedRun = mergingRefreshedStages(
                        refreshStages,
                        from: refreshedRun,
                        into: updatedRun
                    )
                    pendingPipelineQuickCheck = nil
                }
                pipelineRun = updatedRun

                let savedProviderMatch = checkedItems.count == 1
                    && checkedItems.contains { !$0.manualSourceIDs.isEmpty || $0.reviewTags.contains("manual-provider-match") }
                let remainingCount = updatedRun.context.plan.activeItems.filter { $0.stage == stage }.count
                let remainingMessage = remainingCount == 0
                    ? "This metadata lane is clear."
                    : "The other \(remainingCount) review row\(remainingCount == 1 ? "" : "s") stayed in place."
                status = savedProviderMatch ? "Provider match saved" : "Metadata rows saved"
                pipelineSummary = LibraryPipelineSummary(
                    title: status,
                    message: "Saved \(result.appliedCount) focused metadata row\(result.appliedCount == 1 ? "" : "s"). \(remainingMessage)",
                    nextAction: remainingCount == 0 ? .checkAgain : .reviewDecisions,
                    plannedCount: updatedRun.context.plan.activeItems.count,
                    unresolvedCount: updatedRun.context.plan.unresolvedItems.count,
                    appliedCount: result.appliedCount
                )
                sableWorkflowLogger.info("Focused metadata apply finished for \(stage.rawValue, privacy: .public); kept \(remainingCount, privacy: .public) sibling row(s) open")
                addActivity(
                    refreshStages.isEmpty
                        ? "\(status)."
                        : "\(status). Folder Sorting and File Names are current, and the other provider rows stayed open."
                )
                currentActivity = status
                finishRun()
                return
            }

            if isRepeatableReaderImportRefresh, result.appliedCount > 0 {
                let appliedPathSet = Set(result.appliedPaths.map(\.currentPath))
                let appliedItemIDs = Set(checkedItems.lazy
                    .filter { appliedPathSet.contains($0.currentPath) }
                    .map(\.id))
                var updatedRun = currentRun
                updatedRun.context.plan.groups = updatedRun.context.plan.groups.compactMap { group in
                    var updatedGroup = group
                    updatedGroup.items.removeAll { appliedItemIDs.contains($0.id) }
                    return updatedGroup.items.isEmpty ? nil : updatedGroup
                }
                pipelineRun = updatedRun
                pipelineSummary = LibraryPipelineSummary(
                    title: "Apple Books refresh applied",
                    message: "Sable prepared \(result.appliedCount) EPUB\(result.appliedCount == 1 ? "" : "s") for a fresh Apple Books import. The bulk pass is complete; Recheck Applied remains available when you want to run it again.",
                    nextAction: .checkAgain,
                    plannedCount: updatedRun.context.plan.activeItems.count,
                    unresolvedCount: updatedRun.context.plan.unresolvedItems.count,
                    appliedCount: result.appliedCount
                )
                status = "Apple Books refresh applied"
                sableWorkflowLogger.info("Apple Books refresh finished for \(result.appliedCount, privacy: .public) EPUB(s); repeatable recheck left manual")
                addActivity("Apple Books refresh finished for \(result.appliedCount) EPUB\(result.appliedCount == 1 ? "" : "s").")
                currentActivity = status
                finishRun()
                return
            }

            if stage == .covers, result.appliedCount == 0, result.skippedCount > 0 {
                status = "No trusted covers downloaded"
            } else if stage.isMetadataSidecarStage, result.appliedCount == 0, result.skippedCount > 0 {
                status = "Metadata pass finished with no writes"
            } else {
                status = result.appliedCount > 0 ? "\(stage.title) applied" : "Nothing applied"
            }
            sableWorkflowLogger.info("Apply finished for \(stage.rawValue, privacy: .public); applied \(result.appliedCount, privacy: .public) item(s)")
            addActivity(result.summary)
            currentActivity = status
            finishRun()
        }
    }

    private func postApplyRefreshStatus(for stage: LibraryPipelineStage) -> String {
        switch stage {
        case .covers:
            "Refreshing Covers..."
        case .comicInfo, .providerMatches:
            "Refreshing metadata, folders, and file names..."
        case .canonicalFolders:
            "Refreshing folders and file names..."
        case .canonicalFiles:
            "Refreshing file names..."
        case .epubClinic:
            "Checking applied work..."
        case .inspect, .prepareRawFiles, .duplicateReview, .reviewApply:
            "Checking applied work..."
        }
    }

    private func postApplyRefreshActivity(for stage: LibraryPipelineStage) -> String {
        switch stage {
        case .covers:
            "Refreshing downloaded cover choices."
        case .comicInfo, .providerMatches:
            "Refreshing saved metadata and rebuilding downstream folder and file-name suggestions."
        case .canonicalFolders:
            "Rescanning Folder Sorting and File Names after the folder moves."
        case .canonicalFiles:
            "Rescanning File Names after the renames."
        case .epubClinic:
            "Checking the EPUBs changed by Sable's Clinic."
        case .inspect, .prepareRawFiles, .duplicateReview, .reviewApply:
            "Checking the paths changed by \(stage.title)."
        }
    }

    private func mergingRefreshedStages(
        _ stages: [LibraryPipelineStage],
        from refreshedRun: LibraryPipelineRun,
        into currentRun: LibraryPipelineRun
    ) -> LibraryPipelineRun {
        var updatedRun = currentRun
        updatedRun.context.inspection = refreshedRun.context.inspection
        updatedRun.context.timings.append(contentsOf: refreshedRun.context.timings)
        updatedRun.context.plan.replaceGroups(
            for: Set(stages),
            with: refreshedRun.context.plan
        )
        updatedRun.nextAction = updatedRun.context.plan.activeItems.isEmpty ? .checkAgain : .reviewDecisions
        return updatedRun
    }

    private func scopedApplyPlan(
        _ plan: LibraryPlan,
        stage: LibraryPipelineStage,
        itemIDs: [LibraryPlanItem.ID]?
    ) -> LibraryPlan {
        guard let itemIDs else { return plan }
        let selectedIDs = Set(itemIDs)
        var scopedPlan = plan
        scopedPlan.groups = scopedPlan.groups.map { group in
            guard group.stage == stage else { return group }
            var scopedGroup = group
            scopedGroup.items = scopedGroup.items.map { item in
                if selectedIDs.contains(item.id) {
                    var scopedItem = item
                    scopedItem.decision = .checked
                    return scopedItem
                }
                if item.decision == .checked {
                    var scopedItem = item
                    scopedItem.decision = .unchecked
                    return scopedItem
                }
                return item
            }
            return scopedGroup
        }
        return scopedPlan
    }

    private func recordAppliedLearning(from checkedItems: [LibraryPlanItem], result: LibraryApplyResult) {
        guard result.appliedCount > 0 else { return }

        let appliedCurrentPaths = Set(result.appliedPaths.map(\.currentPath))
        var didUpdateLocalLearning = false
        var eventCount = 0

        for item in checkedItems where appliedCurrentPaths.contains(item.currentPath) {
            if intelligenceOptions.useLocalLearning {
                didUpdateLocalLearning = recordLocalLearningFromAppliedItem(item) || didUpdateLocalLearning
            }
            recordAppliedPlanTrainingEvent(for: item)
            eventCount += 1
        }

        if didUpdateLocalLearning {
            saveLightweightLearningMemory()
        }

        if eventCount > 0 {
            addActivity("Added \(eventCount) applied example\(eventCount == 1 ? "" : "s") to Sable learning.")
        }
    }

    private func recordLocalLearningFromAppliedItem(_ item: LibraryPlanItem) -> Bool {
        var didUpdate = false

        if let readingType = rawReadingType(fromReviewTags: item.reviewTags) {
            learningMemory.recordRawReadingLane(
                path: item.currentPath,
                proposedPath: item.proposedPath,
                readingType: readingType
            )
            didUpdate = true
        }

        if let cleanupKind = cleanupKind(fromReviewTags: item.reviewTags) {
            learningMemory.recordCleanupKind(
                path: item.currentPath,
                proposedPath: item.proposedPath,
                kind: cleanupKind
            )
            didUpdate = true
        }

        if item.reviewTags.contains("pdf-triage"),
           item.proposedPath?.hasPrefix("Documents/") == true {
            learningMemory.recordPDFTriage(
                path: item.currentPath,
                proposedPath: item.proposedPath,
                choice: .document
            )
            didUpdate = true
        }

        if item.stage.isMetadataSidecarStage,
           !item.usedNetworkData,
           item.operation == .createComicInfo || item.operation == .refreshComicInfo {
            learningMemory.recordMangaBakaKeepLocal(seriesKey: item.currentPath)
            didUpdate = true
        }

        if item.stage.isMetadataSidecarStage,
           item.metadataProviders.contains(.mangabaka),
           let manualMangaBakaID = item.manualMangaBakaID {
            learningMemory.recordMangaBakaUse(seriesKey: item.currentPath, candidateID: manualMangaBakaID)
            didUpdate = true
        }

        return didUpdate
    }

    private func recordAppliedPlanTrainingEvent(for item: LibraryPlanItem) {
        guard let libraryURL else { return }
        let event = SableLibraryMLTrainingEvent.make(
            kind: .finalSuccessfulPlanRow,
            domain: trainingDomain(for: item),
            localPath: item.currentPath,
            provider: trainingProvider(for: item),
            confidenceScore: trainingConfidenceScore(for: item.confidence),
            featureSummary: [
                "stage": item.stage.rawValue,
                "operation": item.operation.rawValue,
                "safety": item.safety.rawValue,
                "used_network": String(item.usedNetworkData),
                "destination_root": destinationRoot(in: item.proposedPath),
                "destination_family": destinationFamily(in: item.proposedPath),
                "source_extension": sourceExtension(in: item.currentPath),
                "metadata_providers": item.metadataProviders.map(\.rawValue).joined(separator: ","),
                "requires_review": String(item.requiresReview),
                "review_tags": genericTrainingTags(from: item.reviewTags).joined(separator: ",")
            ]
        )
        service.recordMLTrainingEvent(event, root: libraryURL, config: service.currentConfig())
    }

    private func rawReadingType(fromReviewTags tags: [String]) -> SableLibraryReadingType? {
        for tag in tags where tag.hasPrefix("raw-reading-") {
            let value = String(tag.dropFirst("raw-reading-".count))
            if let type = SableLibraryReadingType(rawValue: value), type != .unknown {
                return type
            }
        }
        return nil
    }

    private func cleanupKind(fromReviewTags tags: [String]) -> SableLibraryCleanupKind? {
        for tag in tags where tag.hasPrefix("cleanup-kind-") {
            let value = String(tag.dropFirst("cleanup-kind-".count))
            if let kind = SableLibraryCleanupKind(rawValue: value) {
                return kind
            }
        }
        return nil
    }

    private func trainingDomain(for item: LibraryPlanItem) -> SableLibraryMediaDomain {
        if item.operation == .createAnimeInfo || item.operation == .refreshAnimeInfo {
            return .watching
        }
        if item.operation == .createComicInfo || item.operation == .refreshComicInfo {
            return .reading
        }
        if rawReadingType(fromReviewTags: item.reviewTags) != nil {
            return .reading
        }
        if let cleanupKind = cleanupKind(fromReviewTags: item.reviewTags) {
            return cleanupKind.mediaDomain
        }
        return .unknown
    }

    private func trainingProvider(for item: LibraryPlanItem) -> SableLibraryMetadataProvider? {
        item.metadataProviders.first ?? (item.usedNetworkData ? nil : .local)
    }

    private func trainingConfidenceScore(for confidence: LibraryPlanConfidence) -> Double {
        switch confidence {
        case .high: 0.95
        case .medium: 0.72
        case .low: 0.4
        case .unknown: 0
        }
    }

    private func destinationRoot(in path: String?) -> String {
        path?
            .split(separator: "/", omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? ""
    }

    private func destinationFamily(in path: String?) -> String {
        let parts = path?.split(separator: "/", omittingEmptySubsequences: true).map(String.init) ?? []
        guard parts.count > 1 else { return "" }
        return parts[1]
    }

    private func sourceExtension(in path: String) -> String {
        (path as NSString).pathExtension.lowercased()
    }

    private func genericTrainingTags(from tags: [String]) -> [String] {
        tags
            .filter { tag in
                tag.hasPrefix("raw-reading-")
                    || tag.hasPrefix("cleanup-kind-")
                    || tag.hasPrefix("pdf-triage")
                    || tag.hasPrefix("likely-")
                    || tag.hasPrefix("epub-")
                    || tag.hasPrefix("ml-training-epub-")
                    || tag.hasPrefix("metadata-")
                    || tag.hasPrefix("naming-")
                    || tag.hasPrefix("provider-route-")
                    || tag.hasPrefix("provider-")
                    || tag == "needs-provider-choice"
                    || tag == "manual-provider-match"
                    || tag == "training-material"
                    || tag == "bulk-raw-review"
            }
            .sorted()
    }

    private func finishRun() {
        isRunning = false
        progressSnapshot = nil
        stopProgressPulse()
        runningTask = nil
    }

    private func finishStoppedRun() {
        sableWorkflowLogger.info("Workflow stopped safely")
        status = "Stopped"
        currentActivity = "Stopped safely. Inspect again or continue reviewing the current plan."
        finishRun()
    }

    private func updatePipelineDecision(_ itemID: LibraryPlanItem.ID, decision: LibraryPlanDecision) {
        guard !isRunning else { return }
        mutatePipelineItem(itemID) { item in
            item.decision = decision
            if decision != .skipped {
                item.rejectionReason = nil
            }
        }
    }

    private func updatePipelineDecisions(_ itemIDs: [LibraryPlanItem.ID], decision: LibraryPlanDecision) {
        guard !isRunning, !itemIDs.isEmpty else { return }
        let ids = Set(itemIDs)
        mutatePipelineItems(matching: ids) { item in
            item.decision = decision
            if decision != .skipped {
                item.rejectionReason = nil
            }
        }

        let action = decision == .checked ? "Checked" : "Cleared"
        addActivity("\(action) \(itemIDs.count) row\(itemIDs.count == 1 ? "" : "s").")
    }

    private func markPipelineCorrection(_ itemID: LibraryPlanItem.ID, option: LibraryPlanCorrectionOption) {
        guard !isRunning else { return }
        var activity = "Skipped one suggestion: \(option.title)"
        mutatePipelineItem(itemID) { item in
            activity = applyCorrection(option, to: &item)
        }
        addActivity(activity)
    }

    private func markPipelineCorrections(_ itemIDs: [LibraryPlanItem.ID], option: LibraryPlanCorrectionOption) {
        guard !isRunning, !itemIDs.isEmpty else { return }
        let ids = Set(itemIDs)
        var updatedCount = 0
        mutatePipelineItems(matching: ids) { item in
            let before = item
            _ = applyCorrection(option, to: &item)
            if item != before {
                updatedCount += 1
            }
        }
        if updatedCount > 0 {
            addActivity("Updated \(updatedCount) row\(updatedCount == 1 ? "" : "s"): \(option.title).")
        }
    }

    private func applyCorrection(_ option: LibraryPlanCorrectionOption, to item: inout LibraryPlanItem) -> String {
        if option == .keepTitle,
           item.stage.isMetadataSidecarStage,
           item.operation == .createComicInfo || item.operation == .refreshComicInfo {
            keepLocalComicInfoTitle(for: &item)
            return "Using the local title for one ComicInfo row."
        }

        if option == .moveExistingAside,
           item.canResolveNameCollision {
            approveNameCollisionResolution(for: &item)
            return "Set one name conflict to move the existing duplicate aside."
        }

        if option == .mergeIntoExisting,
           item.canMergeIntoExistingFolder {
            approveFolderMergeResolution(for: &item)
            return "Set one folder conflict to merge into the existing folder."
        }

        if option == .moveExistingAside,
           item.canResolveDuplicateReview {
            approveDuplicateMoveAside(for: &item)
            return "Set one duplicate copy to move aside."
        }

        if option == .treatAsDocument,
           item.stage == .prepareRawFiles,
           (item.operation == .sortIntoFolder || item.operation == .renameFolder),
           item.correctionOptions.contains(.treatAsDocument),
           item.proposedPath != nil {
            approvePDFDocumentChoice(for: &item)
            return "Set one PDF to move as a document."
        }

        if option == .treatAsBook,
           item.stage == .prepareRawFiles,
           item.correctionOptions.contains(.treatAsBook) {
            approvePDFBookChoice(for: &item)
            return "Kept one PDF out of document cleanup as book-like."
        }

        if let rawReadingType = rawReadingType(for: option),
           canTeachRawReadingLane(item) {
            approveRawReadingLaneChoice(rawReadingType, for: &item)
            return "Marked one raw reading row as \(rawReadingType.folderName)."
        }

        if let cleanupKind = cleanupKind(for: option),
           canTeachCleanupKind(item) {
            approveCleanupKindChoice(cleanupKind, for: &item)
            return "Marked one cleanup row for \(cleanupKind.folderName)."
        }

        if option == .providerNotAvailable,
           item.stage.isMetadataSidecarStage,
           item.reviewTags.contains("metadata-manual-provider-gap") {
            recordProviderGapDismissalTrainingEvent(for: item)
            rememberProviderUnavailableInSidecar(for: item)
            item.decision = .skipped
            clearManualProviderChoices(for: &item)
            item.rejectionReason = LibraryPlanRejectionReason(option: option)
            item.reviewTags = Array(Set(item.reviewTags + ["manual-provider-dismissed", "ml-training-provider-gap-dismissed"])).sorted()
            return "Marked one provider as known missing. Sable will stop asking unless you reset it."
        }

        item.decision = .skipped
        clearManualProviderChoices(for: &item)
        item.rejectionReason = LibraryPlanRejectionReason(option: option)
        return "Skipped one suggestion: \(option.title)"
    }

    private func keepLocalComicInfoTitle(for item: inout LibraryPlanItem) {
        item.reason = item.operation == .refreshComicInfo
            ? "Refresh local ComicInfo.json from the folder title and current files. Provider search will not be used for this row."
            : "Create local ComicInfo.json from the folder title. Provider search will not be used for this row."
        item.confidence = .medium
        item.safety = .reversible
        item.decision = .checked
        item.requiresReview = false
        item.usedNetworkData = false
        item.metadataProviders = []
        clearManualProviderChoices(for: &item)
        item.confidenceExplanation = "Correction chosen: keep the local folder title. The type is inferred from local clues when possible."
        item.rejectionReason = nil
        item.reviewTags = Array(Set(item.reviewTags + ["manual-provider-dismissed", "ml-training-provider-gap-dismissed"])).sorted()
        item.receipt = item.operation == .refreshComicInfo
            ? "Refresh local ComicInfo.json for \(item.currentPath)"
            : "Create local ComicInfo.json for \(item.currentPath)"
    }

    private func approveNameCollisionResolution(for item: inout LibraryPlanItem) {
        guard let proposedPath = item.proposedPath else { return }
        item.reason = PlannedMove.manualNameCollisionReason
        item.confidence = .medium
        item.safety = .collision
        item.decision = .checked
        item.requiresReview = false
        item.usedNetworkData = false
        clearManualProviderChoices(for: &item)
        item.confidenceExplanation = "Collision resolution chosen: apply will move the existing destination into the duplicate folder, then use the proposed name."
        item.rejectionReason = nil
        item.receipt = "Resolve name conflict: \(item.currentPath) -> \(proposedPath)"
    }

    private func approveFolderMergeResolution(for item: inout LibraryPlanItem) {
        guard let proposedPath = item.proposedPath else { return }
        item.reason = PlannedMove.manualFolderMergeReason
        item.confidence = .medium
        item.safety = .collision
        item.decision = .checked
        item.requiresReview = false
        item.usedNetworkData = false
        clearManualProviderChoices(for: &item)
        item.confidenceExplanation = "Merge chosen: apply will move the contents of the current folder into the existing destination folder. Item name conflicts inside that folder get unique names."
        item.rejectionReason = nil
        item.receipt = "Merge folder into existing: \(item.currentPath) -> \(proposedPath)"
    }

    private func approveDuplicateMoveAside(for item: inout LibraryPlanItem) {
        guard let proposedPath = item.proposedPath else { return }
        item.reason = PlannedMove.duplicateReviewReason
        item.confidence = .medium
        item.safety = .reversible
        item.decision = .checked
        item.requiresReview = false
        item.usedNetworkData = false
        clearManualProviderChoices(for: &item)
        item.confidenceExplanation = "Duplicate review chosen: apply will move this extra copy into the duplicate folder. The suggested keeper stays where it is."
        item.rejectionReason = nil
        item.receipt = "Move duplicate aside: \(item.currentPath) -> \(proposedPath)"
    }

    private func approvePDFDocumentChoice(for item: inout LibraryPlanItem) {
        guard let proposedPath = item.proposedPath else { return }
        recordPDFTriageChoice(for: item, choice: .document)
        item.reason = "Marked as a document PDF for this pass. Apply will move it into Documents and leave book/metadata cleanup out."
        item.confidence = .medium
        item.safety = .reversible
        item.decision = .checked
        item.requiresReview = false
        item.usedNetworkData = false
        clearManualProviderChoices(for: &item)
        item.confidenceExplanation = "PDF triage choice: this file is treated as a document, not as a book or ComicInfo candidate."
        item.rejectionReason = nil
        item.receipt = "Treat PDF as document: \(item.currentPath) -> \(proposedPath)"
    }

    private func approvePDFBookChoice(for item: inout LibraryPlanItem) {
        recordPDFTriageChoice(for: item, choice: .book)
        item.reason = "Marked as book-like for this pass. Sable will leave it out of document cleanup."
        item.confidence = .medium
        item.safety = .needsChoice
        item.decision = .skipped
        item.requiresReview = true
        item.usedNetworkData = false
        clearManualProviderChoices(for: &item)
        item.confidenceExplanation = "PDF triage choice: this file or folder should stay out of broad Documents cleanup."
        item.rejectionReason = LibraryPlanRejectionReason(option: .treatAsBook)
        item.receipt = "Keep PDF as book-like: \(item.currentPath)"
    }

    private func recordPDFTriageChoice(for item: LibraryPlanItem, choice: SableLibraryPDFTriageChoice) {
        guard intelligenceOptions.useLocalLearning else { return }
        learningMemory.recordPDFTriage(
            path: item.currentPath,
            proposedPath: item.proposedPath,
            choice: choice
        )
        saveLightweightLearningMemory()
    }

    private func approveRawReadingLaneChoice(_ readingType: SableLibraryReadingType, for item: inout LibraryPlanItem) {
        guard let proposedPath = item.proposedPath,
              let updatedPath = replacingReadingLane(in: proposedPath, with: readingType.folderName) else {
            return
        }

        recordRawReadingLaneChoice(for: item, readingType: readingType)
        item.proposedPath = updatedPath
        item.reason = "Marked as \(readingType.folderName) for this pass. Sable will remember this local reading-lane clue."
        item.confidence = .medium
        item.safety = .reversible
        item.decision = .checked
        item.requiresReview = false
        item.usedNetworkData = false
        clearManualProviderChoices(for: &item)
        item.confidenceExplanation = "Local learning choice: this raw reading item should be grouped under \(readingType.folderName). Future similar raw names can use this clue, but unclear rows still stay reviewable."
        item.rejectionReason = nil
        item.reviewTags = Array(Set(item.reviewTags + ["learned-raw-reading-lane", "raw-reading-\(readingType.rawValue)"])).sorted()
        item.receipt = "Treat raw reading lane as \(readingType.folderName): \(item.currentPath) -> \(updatedPath)"

        if item.reviewTags.contains("raw-name-review") {
            item.reason = "Marked as \(readingType.folderName), but the raw name still needs review before applying."
            item.safety = .needsChoice
            item.decision = .unchecked
            item.requiresReview = true
            item.confidenceExplanation += " The reading lane is taught, but the raw filename still has unclear folder or volume clues."
        }

        if let libraryURL,
           service.fileManager.fileExists(atPath: libraryURL.appendingPathComponent(updatedPath).path(percentEncoded: false)) {
            item.reason = "Marked as \(readingType.folderName), but the chosen destination already exists. Review the duplicate path before applying."
            item.safety = .collision
            item.decision = .unchecked
            item.requiresReview = true
            item.confidenceExplanation += " Destination conflict detected after the lane correction."
        }
    }

    private func recordRawReadingLaneChoice(for item: LibraryPlanItem, readingType: SableLibraryReadingType) {
        guard intelligenceOptions.useLocalLearning else { return }
        learningMemory.recordRawReadingLane(
            path: item.currentPath,
            proposedPath: item.proposedPath,
            readingType: readingType
        )
        saveLightweightLearningMemory()

        if let libraryURL {
            let event = SableLibraryMLTrainingEvent.make(
                kind: .rawReadingLaneCorrection,
                domain: .reading,
                localPath: item.currentPath,
                provider: .local,
                confidenceScore: 0.75,
                featureSummary: [
                    "chosen_lane": readingType.folderName,
                    "operation": item.operation.rawValue,
                    "source": "review_correction"
                ]
            )
            service.recordMLTrainingEvent(event, root: libraryURL, config: service.currentConfig())
        }
    }

    private func approveCleanupKindChoice(_ kind: SableLibraryCleanupKind, for item: inout LibraryPlanItem) {
        guard let proposedPath = item.proposedPath,
              let updatedPath = replacingCleanupKind(in: proposedPath, with: kind.folderName) else {
            return
        }

        recordCleanupKindChoice(for: item, kind: kind)
        item.proposedPath = updatedPath
        item.reason = "Marked for \(kind.folderName) for this pass. Sable will remember this local cleanup-kind clue."
        item.confidence = .medium
        item.safety = .reversible
        item.decision = .checked
        item.requiresReview = false
        item.usedNetworkData = false
        clearManualProviderChoices(for: &item)
        item.confidenceExplanation = "Local learning choice: this raw cleanup item should be grouped under \(kind.folderName). Future similar files and folders can use this clue, but unclear rows still stay reviewable."
        item.rejectionReason = nil
        item.reviewTags = Array(Set(item.reviewTags + ["learned-cleanup-kind", "cleanup-kind-\(kind.rawValue)"])).sorted()
        item.receipt = "Treat cleanup kind as \(kind.folderName): \(item.currentPath) -> \(updatedPath)"

        if let libraryURL,
           service.fileManager.fileExists(atPath: libraryURL.appendingPathComponent(updatedPath).path(percentEncoded: false)) {
            item.reason = "Marked for \(kind.folderName), but the chosen destination already exists. Review the duplicate path before applying."
            item.safety = .collision
            item.decision = .unchecked
            item.requiresReview = true
            item.confidenceExplanation += " Destination conflict detected after the cleanup-kind correction."
        }
    }

    private func recordCleanupKindChoice(for item: LibraryPlanItem, kind: SableLibraryCleanupKind) {
        guard intelligenceOptions.useLocalLearning else { return }
        learningMemory.recordCleanupKind(
            path: item.currentPath,
            proposedPath: item.proposedPath,
            kind: kind
        )
        saveLightweightLearningMemory()

        if let libraryURL {
            let event = SableLibraryMLTrainingEvent.make(
                kind: .cleanupKindCorrection,
                domain: kind.mediaDomain,
                localPath: item.currentPath,
                provider: .local,
                confidenceScore: 0.72,
                featureSummary: [
                    "chosen_kind": kind.folderName,
                    "operation": item.operation.rawValue,
                    "source": "review_correction"
                ]
            )
            service.recordMLTrainingEvent(event, root: libraryURL, config: service.currentConfig())
        }
    }

    private func canTeachRawReadingLane(_ item: LibraryPlanItem) -> Bool {
        item.stage == .prepareRawFiles
            && (item.operation == .sortIntoFolder || item.operation == .renameFolder)
            && item.reviewTags.contains("raw-reading-lane")
            && item.proposedPath != nil
    }

    private func canTeachCleanupKind(_ item: LibraryPlanItem) -> Bool {
        item.stage == .prepareRawFiles
            && (item.operation == .sortIntoFolder || item.operation == .renameFolder)
            && item.reviewTags.contains("cleanup-kind")
            && item.proposedPath != nil
    }

    private func rawReadingType(for option: LibraryPlanCorrectionOption) -> SableLibraryReadingType? {
        switch option {
        case .treatAsManga: .manga
        case .treatAsManhwa: .manhwa
        case .treatAsManhua: .manhua
        case .treatAsLightNovel: .lightNovel
        case .treatAsProseBook: .book
        case .treatAsOEL: .oel
        case .wrongSeries, .wrongType, .badNumber, .treatAsDocument, .treatAsBook, .treatAsReading, .treatAsWatching, .treatAsDocuments, .treatAsImages, .treatAsAudio, .treatAsArchives, .treatAsOtherFiles, .keepTitle, .moveExistingAside, .mergeIntoExisting, .notADuplicate, .providerNotAvailable, .custom:
            nil
        }
    }

    private func cleanupKind(for option: LibraryPlanCorrectionOption) -> SableLibraryCleanupKind? {
        switch option {
        case .treatAsReading: .reading
        case .treatAsWatching: .watching
        case .treatAsDocuments: .document
        case .treatAsImages: .image
        case .treatAsAudio: .audio
        case .treatAsArchives: .archive
        case .treatAsOtherFiles: .other
        case .wrongSeries, .wrongType, .badNumber, .treatAsDocument, .treatAsBook, .treatAsManga, .treatAsManhwa, .treatAsManhua, .treatAsLightNovel, .treatAsProseBook, .treatAsOEL, .keepTitle, .moveExistingAside, .mergeIntoExisting, .notADuplicate, .providerNotAvailable, .custom:
            nil
        }
    }

    private func replacingReadingLane(in path: String, with lane: String) -> String? {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty else { return nil }

        var components = trimmed.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !components.isEmpty else { return nil }

        let knownLanes = Set([
            "books",
            "manga",
            "manhwa",
            "manhua",
            "oel",
            "light novels",
            "comics",
            "other reading"
        ])
        if knownLanes.contains(components[0].lowercased()) {
            components[0] = lane
        } else {
            components.insert(lane, at: 0)
        }
        return components.joined(separator: "/")
    }

    private func replacingCleanupKind(in path: String, with folderName: String) -> String? {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty else { return nil }

        var components = trimmed.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !components.isEmpty else { return nil }

        let knownFolders = Set(SableLibraryCleanupKind.allCases.map { $0.folderName.lowercased() } + [
            "light novels",
            "manga",
            "manhwa",
            "manhua",
            "oel",
            "other reading"
        ])
        if knownFolders.contains(components[0].lowercased()) {
            components[0] = folderName
        } else {
            components.insert(folderName, at: 0)
        }
        return components.joined(separator: "/")
    }

    private func updatePipelineMangaBakaID(_ itemID: LibraryPlanItem.ID, _ input: String) {
        guard !isRunning else { return }
        guard let mangaBakaID = SableLibraryMangaBakaIDParser.id(from: input) else {
            addActivity("Could not read a MangaBaka ID from that value.")
            return
        }

        var updatedItem: LibraryPlanItem?
        mutatePipelineItem(itemID) { item in
            guard item.stage.isMetadataSidecarStage,
                  item.operation == .createComicInfo || item.operation == .refreshComicInfo else { return }

            item.manualMangaBakaID = mangaBakaID
            if !item.metadataProviders.contains(.mangabaka) {
                item.metadataProviders.append(.mangabaka)
            }
            item.usedNetworkData = true
            item.reason = "Apply will fetch MangaBaka ID \(mangaBakaID) directly and write ComicInfo.json from that exact series."
            item.confidence = .medium
            item.safety = .reversible
            item.decision = .checked
            item.requiresReview = false
            item.confidenceExplanation = "Manual MangaBaka match chosen. Broad search is skipped for this row."
            item.rejectionReason = nil
            item.reviewTags = Array(Set(item.reviewTags + [
                "manual-provider-match",
                "provider-mangabaka",
                "metadata-provider-manual-match"
            ])).sorted()
            item.receipt = "Use MangaBaka ID \(mangaBakaID) for \(item.currentPath)"
            updatedItem = item
        }
        if let updatedItem {
            recordManualProviderIDTrainingEvent(for: updatedItem, provider: .mangabaka, identifier: mangaBakaID)
        }
        addActivity("Using MangaBaka ID \(mangaBakaID) for one ComicInfo row.")
    }

    private func updatePipelineRanobeDBID(_ itemID: LibraryPlanItem.ID, _ input: String) {
        guard !isRunning else { return }
        guard let ranobeDBID = SableLibraryRanobeDBIDParser.id(from: input) else {
            addActivity("Could not read a RanobeDB series ID from that value.")
            return
        }

        var updatedItem: LibraryPlanItem?
        mutatePipelineItem(itemID) { item in
            guard item.stage.isMetadataSidecarStage,
                  item.operation == .createComicInfo || item.operation == .refreshComicInfo else { return }

            item.manualRanobeDBID = ranobeDBID
            if !item.metadataProviders.contains(.ranobedb) {
                item.metadataProviders.append(.ranobedb)
            }
            item.usedNetworkData = true
            item.reason = "Apply will use RanobeDB series ID \(ranobeDBID) directly if MangaBaka cannot be matched first."
            item.confidence = .medium
            item.safety = .reversible
            item.decision = .checked
            item.requiresReview = false
            item.confidenceExplanation = "Manual RanobeDB series chosen. RanobeDB title search is skipped for this row; MangaBaka still tries first when enabled."
            item.rejectionReason = nil
            item.reviewTags = Array(Set(item.reviewTags + [
                "manual-provider-match",
                "provider-ranobedb",
                "metadata-provider-manual-match"
            ])).sorted()
            item.receipt = "Use RanobeDB series ID \(ranobeDBID) for \(item.currentPath)"
            updatedItem = item
        }
        if let updatedItem {
            recordManualProviderIDTrainingEvent(for: updatedItem, provider: .ranobedb, identifier: ranobeDBID)
        }
        addActivity("Using RanobeDB series ID \(ranobeDBID) for one metadata sidecar row.")
    }

    private func updatePipelineProviderID(
        _ itemID: LibraryPlanItem.ID,
        provider: SableLibraryMetadataProvider,
        input: String
    ) {
        guard !isRunning else { return }
        guard let sourceID = SableLibraryManualProviderIDParser.sourceID(provider: provider, from: input) else {
            addActivity("Could not read a \(provider.displayName) ID from that value.")
            return
        }

        var updatedItem: LibraryPlanItem?
        mutatePipelineItem(itemID) { item in
            switch item.operation {
            case .createComicInfo, .refreshComicInfo, .createAnimeInfo, .refreshAnimeInfo:
                break
            case .inspectOnly, .cleanRawName, .sortIntoFolder, .renameFolder, .renameFile, .repairEpubPackage, .repairAppleBooksCompatibility, .duplicateDecision, .skip:
                return
            }

            appendManualSourceID(sourceID, to: &item)
            if sourceID.provider == .mangabaka {
                item.manualMangaBakaID = sourceID.value
            }
            if sourceID.provider == .ranobedb {
                item.manualRanobeDBID = sourceID.value
            }
            if !item.metadataProviders.contains(sourceID.provider) {
                item.metadataProviders.append(sourceID.provider)
            }
            item.usedNetworkData = true
            item.reason = "Apply will use the manually chosen \(sourceID.provider.displayName) ID \(sourceID.value) for this metadata row."
            item.confidence = .high
            item.safety = .reversible
            item.decision = .checked
            item.requiresReview = false
            item.confidenceExplanation = "Manual provider match chosen. Broad ambiguous matches stay out of quiet apply."
            item.rejectionReason = nil
            let staleProviderReviewTags: Set<String> = [
                "metadata-provider-no-match-review",
                "provider-ranker-no-match",
                "ml-provider-no-match",
                "metadata-provider-needs-confirmation",
                "metadata-provider-precheck",
                "provider-ranker-precheck",
                "ml-provider-precheck"
            ]
            let keptTags = item.reviewTags.filter { !staleProviderReviewTags.contains($0) }
            item.reviewTags = Array(Set(keptTags + [
                "manual-provider-match",
                "provider-\(sourceID.provider.rawValue)",
                "metadata-provider-manual-match",
                "provider-ranker-manual-match",
                "ml-provider-manual-match"
            ])).sorted()
            item.receipt = "Use \(sourceID.provider.displayName) ID \(sourceID.value) for \(item.currentPath)"
            updatedItem = item
        }
        if let updatedItem {
            recordManualProviderIDTrainingEvent(for: updatedItem, provider: sourceID.provider, identifier: sourceID.value)
        }
        addActivity("Using \(sourceID.provider.displayName) ID \(sourceID.value) for one metadata row.")
    }

    private func searchPipelineProviderCandidates(
        provider: SableLibraryMetadataProvider,
        query: String,
        preferredAniListMediaTypes: [String]
    ) async -> [SableLibraryProviderCandidate] {
        await SableLibraryMetadataLookupService().manualSearchCandidates(
            provider: provider,
            query: query,
            preferredAniListMediaTypes: preferredAniListMediaTypes,
            config: service.currentConfig(),
            service: service
        )
    }

    private func updatePipelineCoverSeriesMatch(
        _ itemID: LibraryPlanItem.ID,
        match: SableLibraryManualCoverSeriesMatch
    ) -> Bool {
        guard !isRunning else { return false }
        var didUpdate = false
        mutatePipelineItem(itemID) { item in
            guard item.canManuallyMatchCoverSeries else { return }
            item.manualCoverSeriesMatches.removeAll { $0.source == match.source }
            item.manualCoverSeriesMatches.append(match)
            item.manualCoverSeriesMatches.sort {
                $0.source.displayName.localizedStandardCompare($1.source.displayName) == .orderedAscending
            }
            if match.source == .mangaBaka {
                item.manualMangaBakaID = match.providerID
                appendManualSourceID(
                    SableLibrarySourceID(provider: .mangabaka, value: match.providerID),
                    to: &item
                )
            }
            item.usedNetworkData = true
            item.decision = .checked
            item.requiresReview = false
            item.safety = .reversible
            item.confidence = .high
            item.rejectionReason = nil
            item.reviewTags = Array(Set(item.reviewTags + [
                "manual-cover-series-match",
                "manual-cover-source-\(match.source.rawValue)"
            ])).sorted()
            item.receipt = "Search \(match.source.displayName) exact series \(match.providerID) for \(item.currentPath)"
            didUpdate = true
        }
        if didUpdate {
            addActivity("Using \(match.source.displayName) series \(match.title) for the next checked cover search.")
        }
        return didUpdate
    }

    private func searchPipelineCoverSeriesCandidates(
        source: SableLibraryCoverSource,
        query: String,
        expectedMediaType: String?
    ) async -> [SableLibraryManualCoverSeriesMatch] {
        if source == .bookLiveJP,
           SableLibraryBookLiveSeriesGroupClient.tagID(from: query) != nil {
            do {
                if let match = try await SableLibraryBookLiveSeriesGroupClient().exactMatch(
                    from: query,
                    expectedMediaType: expectedMediaType
                ) {
                    return [match]
                }
            } catch {
                addActivity("BookLive JP series group could not be read: \(error.localizedDescription)")
                return []
            }
        }

        if source == .mangaBaka {
            let candidates = await searchPipelineProviderCandidates(
                provider: .mangabaka,
                query: query,
                preferredAniListMediaTypes: []
            )
            return candidates.compactMap { candidate in
                guard let sourceID = candidate.sourceIDs.first(where: { $0.provider == .mangabaka }),
                      SableLibraryCoverDownloadPlanner.providerMediaTypeIsCompatible(
                        candidate.mediaType,
                        isCompatibleWith: expectedMediaType
                      ) else {
                    return nil
                }
                return SableLibraryManualCoverSeriesMatch(
                    source: .mangaBaka,
                    providerID: sourceID.value,
                    itemType: "series",
                    title: candidate.title,
                    mediaType: candidate.mediaType,
                    bookType: candidate.mediaType,
                    url: "https://mangabaka.org/\(sourceID.value)/covers",
                    thumbnailURL: candidate.coverURL
                )
            }
        }

        guard let provider = SableLibraryBigBookCoversProvider.provider(for: source) else {
            return []
        }
        do {
            let candidates = try await SableLibraryBigBookCoversClient().search(
                query: query,
                provider: provider
            )
            if source == .bookLiveJP {
                return await SableLibraryBookLiveSeriesGroupClient().manualMatches(
                    from: candidates,
                    expectedMediaType: expectedMediaType
                )
            }
            let seriesFirstCandidates =
                SableLibraryCoverDownloadPlanner.exactIdentifierCandidates(candidates)
            return seriesFirstCandidates.compactMap { candidate in
                let providerMediaType = candidate.bookType
                guard providerMediaType == nil
                    || SableLibraryCoverDownloadPlanner.providerMediaTypeIsCompatible(
                        providerMediaType,
                        isCompatibleWith: expectedMediaType
                    ) else {
                    return nil
                }
                return SableLibraryManualCoverSeriesMatch(
                    source: source,
                    providerID: candidate.id,
                    itemType: candidate.type ?? "series",
                    title: candidate.title,
                    mediaType: candidate.bookType,
                    bookType: candidate.bookType,
                    url: candidate.url,
                    thumbnailURL: candidate.thumbnailURL
                )
            }
        } catch {
            addActivity("\(source.displayName) cover search is temporarily unavailable: \(error.localizedDescription)")
            return []
        }
    }

    private func coverDownloadCount(in summary: String) -> Int {
        guard let regex = try? NSRegularExpression(
            pattern: #"\b(\d+)(?:\s+higher-quality)?\s+cover file"#,
            options: [.caseInsensitive]
        ) else {
            return 0
        }
        let range = NSRange(summary.startIndex..<summary.endIndex, in: summary)
        return regex.matches(in: summary, range: range).reduce(into: 0) { total, match in
            guard match.numberOfRanges > 1,
                  let countRange = Range(match.range(at: 1), in: summary),
                  let count = Int(summary[countRange]) else {
                return
            }
            total += count
        }
    }

    private func appendManualSourceID(_ sourceID: SableLibrarySourceID, to item: inout LibraryPlanItem) {
        guard !item.manualSourceIDs.contains(where: { $0.provider == sourceID.provider && $0.value == sourceID.value }) else {
            return
        }
        item.manualSourceIDs.append(sourceID)
    }

    private func clearManualProviderChoices(for item: inout LibraryPlanItem) {
        item.manualMangaBakaID = nil
        item.manualRanobeDBID = nil
        item.manualSourceIDs = []
    }

    private func recordManualProviderIDTrainingEvent(
        for item: LibraryPlanItem,
        provider: SableLibraryMetadataProvider,
        identifier: String
    ) {
        guard let libraryURL else { return }
        let event = SableLibraryMLTrainingEvent.make(
            kind: .manualIDEntry,
            domain: trainingDomain(for: item),
            localPath: item.currentPath,
            provider: provider,
            confidenceScore: 0.98,
            featureSummary: [
                "provider": provider.rawValue,
                "identifier": identifier,
                "stage": item.stage.rawValue,
                "operation": item.operation.rawValue,
                "source": "manual_id",
                "review_tags": genericTrainingTags(from: item.reviewTags).joined(separator: ",")
            ]
        )
        service.recordMLTrainingEvent(event, root: libraryURL, config: service.currentConfig())
    }

    private func recordProviderGapDismissalTrainingEvent(for item: LibraryPlanItem) {
        guard let libraryURL else { return }
        let provider = item.metadataProviders.first
        let event = SableLibraryMLTrainingEvent.make(
            kind: .skippedAmbiguousMatch,
            domain: trainingDomain(for: item),
            localPath: item.currentPath,
            provider: provider,
            confidenceScore: 0.88,
            featureSummary: [
                "provider": provider?.rawValue ?? "",
                "stage": item.stage.rawValue,
                "operation": item.operation.rawValue,
                "source": "manual_provider_gap_dismissal",
                "metadata_providers": item.metadataProviders.map(\.rawValue).joined(separator: ","),
                "review_tags": genericTrainingTags(from: item.reviewTags).joined(separator: ",")
            ]
        )
        service.recordMLTrainingEvent(event, root: libraryURL, config: service.currentConfig())
    }

    private func rememberProviderUnavailableInSidecar(for item: LibraryPlanItem) {
        guard let libraryURL,
              let provider = item.metadataProviders.first,
              let proposedPath = item.proposedPath else {
            return
        }

        let sidecarURL = libraryURL.appendingPathComponent(proposedPath)
        guard let data = try? Data(contentsOf: sidecarURL),
              var sidecar = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return
        }

        var sable = sidecar["_sable"] as? [String: Any] ?? [:]
        var availability = sable["provider_availability"] as? [String: Any] ?? [:]
        availability[provider.rawValue] = [
            "status": "not_available",
            "provider": provider.rawValue,
            "source": "manual_no_id",
            "updated_at": ISO8601DateFormatter().string(from: Date())
        ]
        sable["provider_availability"] = availability
        sidecar["_sable"] = sable

        guard let output = try? JSONSerialization.data(withJSONObject: sidecar, options: [.prettyPrinted, .sortedKeys]) else {
            return
        }
        try? output.write(to: sidecarURL, options: .atomic)
    }

    private func updatePipelineCorrectionNote(_ itemID: LibraryPlanItem.ID, note: String) {
        guard !isRunning else { return }
        mutatePipelineItem(itemID) { item in
            guard var rejectionReason = item.rejectionReason else { return }
            rejectionReason.note = note
            item.rejectionReason = rejectionReason
        }
    }

    private func mutatePipelineItem(_ itemID: LibraryPlanItem.ID, update: (inout LibraryPlanItem) -> Void) {
        mutatePipelineItems(matching: [itemID], update: update)
    }

    private func mutatePipelineItems(matching itemIDs: Set<LibraryPlanItem.ID>, update: (inout LibraryPlanItem) -> Void) {
        guard var run = pipelineRun else { return }
        var didUpdate = false

        for groupIndex in run.context.plan.groups.indices {
            for itemIndex in run.context.plan.groups[groupIndex].items.indices {
                guard itemIDs.contains(run.context.plan.groups[groupIndex].items[itemIndex].id) else {
                    continue
                }

                update(&run.context.plan.groups[groupIndex].items[itemIndex])
                didUpdate = true
            }
        }

        guard didUpdate else { return }
        pipelineRun = run
        pipelineSummary = SableLibraryPipelineCoordinator(service: service).summarize(
            run.context.plan,
            lastApplyResult: pipelineApplyResult
        )
    }

    @discardableResult
    private func ensureLibraryAccess(for url: URL) -> Bool {
        #if os(macOS)
        let target = url.standardizedFileURL
        if hasLibraryAccess, scopedLibraryURL?.standardizedFileURL == target {
            return true
        }

        releaseLibraryAccess()
        let didStartScope = target.startAccessingSecurityScopedResource()
        let canRead = FileManager.default.isReadableFile(atPath: target.path(percentEncoded: false))
        guard didStartScope || canRead else {
            hasLibraryAccess = false
            status = "Choose folder again"
            currentActivity = "The saved library folder is visible, but macOS did not restore permission to read it."
            return false
        }

        scopedLibraryURL = didStartScope ? target : nil
        hasLibraryAccess = true
        return true
        #else
        hasLibraryAccess = true
        return true
        #endif
    }

    private func releaseLibraryAccess() {
        #if os(macOS)
        scopedLibraryURL?.stopAccessingSecurityScopedResource()
        scopedLibraryURL = nil
        #endif
        hasLibraryAccess = false
    }
}
