//
//  SableLibraryAppMode.swift
//  Sable's Library
//

import Foundation

enum SableLibraryAppMode: String, Sendable {
    case library
    case clinic
    case covers

    nonisolated static var current: SableLibraryAppMode {
        #if SABLE_COVERS
        .covers
        #elseif SABLE_CLINIC
        .clinic
        #else
        .library
        #endif
    }

    var appName: String {
        switch self {
        case .library: "Sable's Library"
        case .clinic: "Sable's Clinic"
        case .covers: "Sable's Covers"
        }
    }

    var dashboardTitle: String {
        switch self {
        case .library: "Sable's Library"
        case .clinic: "Sable's Clinic"
        case .covers: "Sable's Covers"
        }
    }

    var selectedFolderTitle: String {
        switch self {
        case .library: "Selected library"
        case .clinic: "Selected collection"
        case .covers: "Selected cover library"
        }
    }

    var waitingActivity: String {
        switch self {
        case .library: "Sable is waiting for a library folder"
        case .clinic: "Sable's Clinic is waiting for a folder of EPUBs"
        case .covers: "Sable's Covers is waiting for a library folder"
        }
    }

    var chooseFolderFirstStatus: String {
        switch self {
        case .library: "Choose a library folder first"
        case .clinic: "Choose a folder of EPUBs first"
        case .covers: "Choose a cover library folder first"
        }
    }

    var clearStatusTitle: String {
        switch self {
        case .library: "Library looks clear"
        case .clinic: "No Clinic rows from this pass"
        case .covers: "Cover library looks clear"
        }
    }

    var inspectActionTitle: String {
        switch self {
        case .library: "Scan Inventory"
        case .clinic: "Scan EPUBs"
        case .covers: "Scan Cover Library"
        }
    }

    var inspectActionHelp: String {
        switch self {
        case .library: "Map files, folders, sidecars, and quick triage facts without waking every specialist."
        case .clinic: "List EPUB files and check local sidecars without opening EPUB internals."
        case .covers: "Map series, EPUBs, ComicInfo, and local cover sets without downloading or replacing anything."
        }
    }

    var runReadyMessage: String {
        switch self {
        case .library: "Run Scan Inventory when you are ready."
        case .clinic: "Run List EPUBs when you are ready."
        case .covers: "Run Scan Cover Library when you are ready."
        }
    }

    var emptyFolderTitle: String {
        switch self {
        case .library: "Choose a library folder"
        case .clinic: "Choose an EPUB folder"
        case .covers: "Choose a cover library folder"
        }
    }

    var selectedFolderStatus: String {
        switch self {
        case .library: "Selected library folder"
        case .clinic: "Selected EPUB folder"
        case .covers: "Selected cover library folder"
        }
    }

    var selectedFromDropActivity: String {
        switch self {
        case .library: "Library folder selected from drop"
        case .clinic: "EPUB folder selected from drop"
        case .covers: "Cover library folder selected from drop"
        }
    }

    var selectedFromPickerActivity: String {
        switch self {
        case .library: "Library folder selected"
        case .clinic: "EPUB folder selected"
        case .covers: "Cover library folder selected"
        }
    }

    var chooseFolderCue: String {
        switch self {
        case .library:
            "Choose one library folder. Inspection is read-only until you apply checked changes."
        case .clinic:
            "Choose a folder that contains EPUBs. The first pass lists files and checks local sidecars."
        case .covers:
            "Choose one library folder. The first pass only inventories series, EPUBs, and existing cover sets."
        }
    }

    var headerSubtitleWhenSelected: String {
        switch self {
        case .library:
            "Sable can handle safe cleanup and pause for the choices that matter."
        case .clinic:
            "Sable can inspect EPUB health, repair safe issues, and guide risky fixes safely."
        case .covers:
            "Download, verify, repair, and contribute covers from one focused workspace."
        }
    }

    var headerSubtitleWhenEmpty: String {
        switch self {
        case .library:
            "Choose a library folder, then let Sable inspect before anything changes."
        case .clinic:
            "Choose an EPUB folder, then list EPUB files and local sidecars before running deeper checker layers."
        case .covers:
            "Choose a library folder for local cover work, or open MangaBaka Studio for any series."
        }
    }

    var workflowStages: [LibraryPipelineStage] {
        switch self {
        case .library:
            [.prepareRawFiles, .comicInfo, .providerMatches, .canonicalFolders, .canonicalFiles, .duplicateReview]
        case .clinic:
            [.epubClinic]
        case .covers:
            [.covers, .epubClinic]
        }
    }

    var showsOnboarding: Bool {
        self == .library
    }
}
