//
//  SableLibraryAppearance.swift
//  Sable's Library
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

enum SableLibraryAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var helpText: String {
        switch self {
        case .system:
            "Follows your macOS appearance. This is the calm default."
        case .light:
            "Keeps the app in light mode with the selected accent."
        case .dark:
            "Keeps the app in dark mode with the selected accent."
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var palette: SableLibraryPalette {
        resolvedPalette(colorScheme: .light, contrast: .standard, accent: .defaultAccent)
    }

    func resolvedPalette(
        colorScheme: ColorScheme,
        contrast: ColorSchemeContrast,
        accent: SableLibraryAccentPreset = .defaultAccent
    ) -> SableLibraryPalette {
        SableLibraryPalette.semantic(
            accent: accent,
            colorScheme: colorScheme,
            contrast: contrast
        )
    }
}

struct SableLibraryPaletteAudit {
    struct Finding: Sendable, Equatable {
        let appearance: String
        let pair: String
        let ratio: Double
        let minimum: Double

        var passed: Bool {
            ratio >= minimum
        }

        var line: String {
            let formattedRatio = String(format: "%.2f", ratio)
            let formattedMinimum = String(format: "%.1f", minimum)
            return "\(passed ? "PASS" : "WARN") - \(appearance): \(pair) contrast \(formattedRatio):1, target \(formattedMinimum):1"
        }
    }

    static func findings() -> [Finding] {
        SableLibraryAppearance.allCases.flatMap { appearance in
            SableLibraryAccentPreset.allCases.flatMap { accent in
                findings(for: appearance, accent: accent)
            }
        }
    }

    static func summaryLines() -> [String] {
        let allFindings = findings()
        let warnings = allFindings.filter { !$0.passed }
        var lines = [
            "Palette accessibility audit",
            "---------------------------"
        ]
        lines.append(contentsOf: allFindings.map(\.line))
        lines.append("")
        lines.append(warnings.isEmpty ? "Palette audit passed." : "Palette audit found \(warnings.count) contrast warning(s).")
        return lines
    }

    private static func findings(for appearance: SableLibraryAppearance, accent: SableLibraryAccentPreset) -> [Finding] {
        let scheme = appearance.preferredColorScheme ?? .light
        let palette = appearance.resolvedPalette(colorScheme: scheme, contrast: .standard, accent: accent)
        let label = "\(appearance.label) / \(accent.label)"
        return [
            finding(appearance: label, pair: "primary text on background", foreground: palette.textPrimary, background: palette.background, minimum: 4.5),
            finding(appearance: label, pair: "primary text on surface", foreground: palette.textPrimary, background: palette.surface, minimum: 4.5),
            finding(appearance: label, pair: "secondary text on surface", foreground: palette.textSecondary, background: palette.surface, minimum: 3.0),
            finding(appearance: label, pair: "muted text on surface", foreground: palette.textMuted, background: palette.surface, minimum: 3.0),
            finding(appearance: label, pair: "accent text on accent", foreground: palette.accentText, background: palette.accent, minimum: 4.5),
            finding(appearance: label, pair: "badge text on info badge", foreground: palette.badgeTextOnFill, background: palette.badgeInfoFill, minimum: 4.5),
            finding(appearance: label, pair: "badge text on warning badge", foreground: palette.badgeTextOnFill, background: palette.badgeWarningFill, minimum: 4.5),
            finding(appearance: label, pair: "badge text on error badge", foreground: palette.badgeErrorTextOnFill, background: palette.badgeErrorFill, minimum: 4.5)
        ]
    }

    private static func finding(appearance: String, pair: String, foreground: Color, background: Color, minimum: Double) -> Finding {
        Finding(
            appearance: appearance,
            pair: pair,
            ratio: contrastRatio(foreground: foreground, background: background),
            minimum: minimum
        )
    }

    private static func contrastRatio(foreground: Color, background: Color) -> Double {
        guard let foregroundRGB = foreground.rgbComponents, let backgroundRGB = background.rgbComponents else {
            return 0
        }
        let lighter = max(foregroundRGB.relativeLuminance, backgroundRGB.relativeLuminance)
        let darker = min(foregroundRGB.relativeLuminance, backgroundRGB.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }
}

private struct SableLibraryRGB {
    let red: Double
    let green: Double
    let blue: Double

    var relativeLuminance: Double {
        0.2126 * adjusted(red) + 0.7152 * adjusted(green) + 0.0722 * adjusted(blue)
    }

    private func adjusted(_ component: Double) -> Double {
        component <= 0.03928
            ? component / 12.92
            : pow((component + 0.055) / 1.055, 2.4)
    }
}

private extension Color {
    var rgbComponents: SableLibraryRGB? {
        #if os(macOS)
        guard let color = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        return SableLibraryRGB(red: color.redComponent, green: color.greenComponent, blue: color.blueComponent)
        #else
        return nil
        #endif
    }
}
