//
//  SableLibraryAppCommands.swift
//  Sable's Library
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

extension Notification.Name {
    static let sableLibrarySettingsChanged = Notification.Name("sableLibrarySettingsChanged")
    static let sableLibraryShowOnboarding = Notification.Name("sableLibraryShowOnboarding")
}

struct SableLibraryCommandActions {
    var chooseFolder: () -> Void
    var inspectLibrary: () -> Void
    var openReports: () -> Void
    var openSettings: () -> Void
    var stop: () -> Void
    var resetToolSettings: () -> Void
    var showOnboarding: () -> Void
    var canRun: Bool
    var canOpenReports: Bool
    var isRunning: Bool
}

extension FocusedValues {
    @Entry var sableLibraryCommands: SableLibraryCommandActions?
}

struct SableLibraryCommands: Commands {
    var mode: SableLibraryAppMode = .library

    @FocusedValue(\.sableLibraryCommands) private var actions

    var body: some Commands {
        CommandGroup(replacing: .sidebar) {
            Button("Show/Hide Sidebar") {
                toggleSidebar()
            }
            .keyboardShortcut("s", modifiers: [.command, .option])
        }

        CommandMenu(mode == .clinic ? "Clinic" : mode == .covers ? "Covers" : "Library") {
            Button(mode == .clinic ? "Choose EPUB Folder..." : mode == .covers ? "Choose Cover Library..." : "Choose Library Folder...") {
                actions?.chooseFolder()
            }
            .keyboardShortcut("o", modifiers: [.command])
            .disabled(actions == nil || actions?.isRunning == true)

            Button(mode.inspectActionTitle) {
                actions?.inspectLibrary()
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .disabled(actions?.canRun != true)

            Button("Open Receipt Folder") {
                actions?.openReports()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(actions?.canOpenReports != true)

            Divider()

            Button(mode == .clinic ? "Stop Current EPUB Check" : mode == .covers ? "Stop Current Cover Check" : "Stop Current Library Check") {
                actions?.stop()
            }
            .keyboardShortcut(".", modifiers: [.command])
            .disabled(actions?.isRunning != true)
        }

        CommandMenu("Sable") {
            Button("Reset Sable Defaults") {
                actions?.resetToolSettings()
            }
            .disabled(actions == nil || actions?.isRunning == true)
        }

        CommandGroup(replacing: .help) {
            Button(mode == .clinic ? "Sable's Clinic Welcome Guide" : mode == .covers ? "Sable's Covers Help" : "Sable's Library Welcome Guide") {
                actions?.showOnboarding()
            }
            .disabled(actions == nil)
        }
    }

    private func toggleSidebar() {
        #if os(macOS)
        NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
        #endif
    }
}
