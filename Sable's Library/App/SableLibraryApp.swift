//
//  SableLibraryApp.swift
//  Sable's Library
//
//  Sable's Library application entry point.
//

import AppKit
import SwiftUI

@main
struct SableLibraryApp: App {
    private let appMode = SableLibraryAppMode.current

    init() {
        // A stale restored SwiftUI window can leave the app running with no visible desk.
        UserDefaults.standard.set(true, forKey: "ApplePersistenceIgnoreState")
    }

    var body: some Scene {
        Window(appMode.appName, id: "main") {
            SableLibraryAppearanceRootView(mode: appMode)
        }
        .defaultSize(
            width: appMode == .covers ? 1320 : 1120,
            height: appMode == .covers ? 840 : 760
        )
        .defaultLaunchBehavior(.presented)
        .restorationBehavior(.disabled)
        .windowResizability(.contentMinSize)
        .commands {
            SidebarCommands()
            SableLibraryCommands(mode: appMode)
        }

        #if os(macOS)
        Settings {
            SableLibraryAppearanceSettingsView(mode: appMode)
        }
        #endif
    }
}

private struct SableLibraryAppearanceRootView: View {
    var mode: SableLibraryAppMode

    @AppStorage("sableLibrary.appAppearance") private var storedAppearance = SableLibraryAppearance.system.rawValue
    @AppStorage("sableLibrary.appAccent") private var storedAccent = SableLibraryAccentPreset.defaultAccent.rawValue
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private var appearance: SableLibraryAppearance {
        SableLibraryAppearance(rawValue: storedAppearance) ?? .system
    }

    private var accent: SableLibraryAccentPreset {
        SableLibraryAccentPreset.stored(storedAccent)
    }

    private var palette: SableLibraryPalette {
        appearance.resolvedPalette(
            colorScheme: appearance.preferredColorScheme ?? colorScheme,
            contrast: colorSchemeContrast,
            accent: accent
        )
    }

    var body: some View {
        Group {
            if mode == .covers {
                SableCoversWorkspaceView()
            } else {
                ContentView(mode: mode)
            }
        }
            .environment(\.sableLibraryPalette, palette)
            .preferredColorScheme(appearance.preferredColorScheme)
            .tint(palette.accent)
            .onAppear(perform: applyAppKitAppearance)
            .onChange(of: storedAppearance) { _, _ in
                applyAppKitAppearance()
            }
    }

    private func applyAppKitAppearance() {
        guard let appearanceName else {
            NSApp.appearance = nil
            return
        }

        NSApp.appearance = NSAppearance(named: appearanceName)
    }

    private var appearanceName: NSAppearance.Name? {
        switch appearance {
        case .system:
            nil
        case .light:
            .aqua
        case .dark:
            .darkAqua
        }
    }
}

#if os(macOS)
private struct SableLibraryAppearanceSettingsView: View {
    var mode: SableLibraryAppMode

    @AppStorage("sableLibrary.appAppearance") private var storedAppearance = SableLibraryAppearance.system.rawValue
    @AppStorage("sableLibrary.appAccent") private var storedAccent = SableLibraryAccentPreset.defaultAccent.rawValue
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private var appearance: SableLibraryAppearance {
        SableLibraryAppearance(rawValue: storedAppearance) ?? .system
    }

    private var accent: SableLibraryAccentPreset {
        SableLibraryAccentPreset.stored(storedAccent)
    }

    private var palette: SableLibraryPalette {
        appearance.resolvedPalette(
            colorScheme: appearance.preferredColorScheme ?? colorScheme,
            contrast: colorSchemeContrast,
            accent: accent
        )
    }

    var body: some View {
        SableLibrarySettingsHostView(mode: mode)
            .environment(\.sableLibraryPalette, palette)
            .preferredColorScheme(appearance.preferredColorScheme)
            .tint(palette.accent)
            .frame(minWidth: 700, minHeight: 680)
    }
}
#endif
