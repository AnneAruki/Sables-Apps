//
//  SableLibraryDesignSystem.swift
//  Sable's Library
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

enum SableLibraryAccentPreset: String, CaseIterable, Identifiable {
    case system = "accent:system"
    case terracotta = "accent:terracotta"
    case pink = "accent:pink"
    case purple = "accent:purple"
    case gold = "accent:gold"
    case green = "accent:green"
    case teal = "accent:teal"
    case blue = "accent:blue"
    case indigo = "accent:indigo"

    var id: String { rawValue }

    static var allCases: [SableLibraryAccentPreset] {
        [.system, .terracotta, .pink, .purple, .gold, .green, .teal, .blue, .indigo]
    }

    static let defaultAccent: SableLibraryAccentPreset = .system

    static func stored(_ rawValue: String) -> SableLibraryAccentPreset {
        let normalized = legacyStorageAliases[rawValue] ?? rawValue
        return SableLibraryAccentPreset(rawValue: normalized) ?? .defaultAccent
    }

    private static let legacyStorageAliases: [String: String] = [
        "moss": SableLibraryAccentPreset.green.rawValue,
        "rose": SableLibraryAccentPreset.pink.rawValue,
        "violet": SableLibraryAccentPreset.purple.rawValue,
        "system:red": SableLibraryAccentPreset.terracotta.rawValue,
        "system:orange": SableLibraryAccentPreset.terracotta.rawValue,
        "system:yellow": SableLibraryAccentPreset.gold.rawValue,
        "system:green": SableLibraryAccentPreset.green.rawValue,
        "system:mint": SableLibraryAccentPreset.teal.rawValue,
        "system:teal": SableLibraryAccentPreset.teal.rawValue,
        "system:cyan": SableLibraryAccentPreset.teal.rawValue,
        "system:blue": SableLibraryAccentPreset.blue.rawValue,
        "system:indigo": SableLibraryAccentPreset.indigo.rawValue,
        "system:purple": SableLibraryAccentPreset.purple.rawValue,
        "system:pink": SableLibraryAccentPreset.pink.rawValue,
        "system:brown": SableLibraryAccentPreset.gold.rawValue,
        "system:gray": SableLibraryAccentPreset.system.rawValue
    ]

    var label: String {
        switch self {
        case .system: "System"
        case .terracotta: "Terracotta"
        case .pink: "Pink"
        case .purple: "Purple"
        case .gold: "Gold"
        case .green: "Green"
        case .teal: "Teal"
        case .blue: "Blue"
        case .indigo: "Indigo"
        }
    }

    var helpText: String {
        switch self {
        case .system:
            "Uses the macOS system accent."
        case .terracotta:
            "Sable terracotta: warm, readable, and a little bolder."
        case .pink:
            "Sable pink: the shared friendly library accent."
        case .purple:
            "Sable purple: saturated but still readable."
        case .gold:
            "Sable gold: warm archive color with a dark glyph."
        case .green:
            "Sable green: the closest match for the original moss accent."
        case .teal:
            "Sable teal: clear and cool without feeling clinical."
        case .blue:
            "Sable blue: familiar, direct, and utility-friendly."
        case .indigo:
            "Sable indigo: deep enough for focus states."
        }
    }

    func color(colorScheme: ColorScheme, contrast: ColorSchemeContrast) -> Color {
        let isDark = colorScheme == .dark
        let highContrast = contrast == .increased

        switch (self, isDark, highContrast) {
        case (.system, _, _): return .systemAccent
        case (.terracotta, false, false): return Color(hex: 0xC96A44)
        case (.terracotta, false, true): return Color(hex: 0xA34D2B)
        case (.terracotta, true, false): return Color(hex: 0xE8875F)
        case (.terracotta, true, true): return Color(hex: 0xF2A07D)
        case (.pink, false, false): return Color(hex: 0xC7366D)
        case (.pink, false, true): return Color(hex: 0xA91455)
        case (.pink, true, false): return Color(hex: 0xFF8EC1)
        case (.pink, true, true): return Color(hex: 0xFFB0D5)
        case (.purple, false, false): return Color(hex: 0x8A3EB3)
        case (.purple, false, true): return Color(hex: 0x6D278F)
        case (.purple, true, false): return Color(hex: 0xD79BFF)
        case (.purple, true, true): return Color(hex: 0xE7BFFF)
        case (.gold, false, false): return Color(hex: 0xB06A00)
        case (.gold, false, true): return Color(hex: 0x7A4500)
        case (.gold, true, false): return Color(hex: 0xE7BC4E)
        case (.gold, true, true): return Color(hex: 0xF6D574)
        case (.green, false, false): return Color(hex: 0x19713C)
        case (.green, false, true): return Color(hex: 0x005626)
        case (.green, true, false): return Color(hex: 0x67C67B)
        case (.green, true, true): return Color(hex: 0x83DB94)
        case (.teal, false, false): return Color(hex: 0x00879A)
        case (.teal, false, true): return Color(hex: 0x006375)
        case (.teal, true, false): return Color(hex: 0x5ED7E5)
        case (.teal, true, true): return Color(hex: 0x8BE7F0)
        case (.blue, false, false): return Color(hex: 0x1F66D1)
        case (.blue, false, true): return Color(hex: 0x174BB2)
        case (.blue, true, false): return Color(hex: 0x76B7FF)
        case (.blue, true, true): return Color(hex: 0x9BCBFF)
        case (.indigo, false, false): return Color(hex: 0x5652C7)
        case (.indigo, false, true): return Color(hex: 0x413EAA)
        case (.indigo, true, false): return Color(hex: 0xA7ABFF)
        case (.indigo, true, true): return Color(hex: 0xC1C4FF)
        }
    }

    func textColor(colorScheme: ColorScheme, contrast: ColorSchemeContrast) -> Color {
        let isDark = colorScheme == .dark
        let highContrast = contrast == .increased

        if self == .system {
            return SableLibraryAccentPreset.bestSystemAccentTextColor()
        }

        if isDark {
            return .black
        }
        if highContrast {
            return .white
        }

        switch self {
        case .terracotta, .gold, .teal:
            return .black
        case .system, .pink, .purple, .green, .blue, .indigo:
            return .white
        }
    }

    private static func bestSystemAccentTextColor() -> Color {
        #if os(macOS)
        guard let accent = NSColor.controlAccentColor.usingColorSpace(.sRGB) else {
            return .white
        }
        let whiteContrast = contrastRatio(
            red: accent.redComponent,
            green: accent.greenComponent,
            blue: accent.blueComponent,
            againstRed: 1,
            green: 1,
            blue: 1
        )
        let blackContrast = contrastRatio(
            red: accent.redComponent,
            green: accent.greenComponent,
            blue: accent.blueComponent,
            againstRed: 0,
            green: 0,
            blue: 0
        )
        return blackContrast >= whiteContrast ? .black : .white
        #else
        return .black
        #endif
    }

    private static func contrastRatio(
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat,
        againstRed backgroundRed: CGFloat,
        green backgroundGreen: CGFloat,
        blue backgroundBlue: CGFloat
    ) -> CGFloat {
        let foreground = relativeLuminance(red: red, green: green, blue: blue)
        let background = relativeLuminance(red: backgroundRed, green: backgroundGreen, blue: backgroundBlue)
        let lighter = max(foreground, background)
        let darker = min(foreground, background)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private static func relativeLuminance(red: CGFloat, green: CGFloat, blue: CGFloat) -> CGFloat {
        func component(_ value: CGFloat) -> CGFloat {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * component(red) + 0.7152 * component(green) + 0.0722 * component(blue)
    }
}

struct SableLibraryPalette: Equatable {
    let background: Color
    let surface: Color
    let surfaceRaised: Color
    let textBackground: Color
    let textPrimary: Color
    let textSecondary: Color
    let textMuted: Color
    let border: Color
    let accent: Color
    let accentText: Color
    let focusRing: Color

    let statusInfo: Color
    let statusSuccess: Color
    let statusWarning: Color
    let statusError: Color
    let statusSpecial: Color
    let statusNeutral: Color

    let badgeInfoFill: Color
    let badgeSuccessFill: Color
    let badgeWarningFill: Color
    let badgeErrorFill: Color
    let badgeSpecialFill: Color
    let badgeTextOnFill: Color
    let badgeErrorTextOnFill: Color
}

extension SableLibraryPalette {
    static let standard = semantic(accent: .defaultAccent, colorScheme: .light, contrast: .standard)

    static func semantic(
        accent: SableLibraryAccentPreset,
        colorScheme: ColorScheme,
        contrast: ColorSchemeContrast
    ) -> SableLibraryPalette {
        let isDark = colorScheme == .dark
        let highContrast = contrast == .increased
        let accentColor = accent.color(colorScheme: colorScheme, contrast: contrast)

        let primaryText = isDark ? Color(hex: 0xF4F4F5) : Color(hex: 0x1F1F23)
        let secondaryText = isDark ? Color(hex: 0xC7C7CF) : Color(hex: 0x51515A)
        let mutedText = isDark ? Color(hex: 0xA2A2AA) : Color(hex: 0x6F6F78)
        let warningColor = isDark ? Color(hex: 0xF4B942) : Color(hex: 0x8A5A00)

        return SableLibraryPalette(
            background: isDark ? Color(hex: 0x101012) : Color(hex: 0xFFFFFF),
            surface: isDark ? Color(hex: 0x1A1A1D) : Color(hex: 0xF6F5F1),
            surfaceRaised: isDark ? Color(hex: 0x242429) : Color(hex: 0xFFFFFF),
            textBackground: Color(nsColor: .textBackgroundColor),
            textPrimary: primaryText,
            textSecondary: secondaryText,
            textMuted: mutedText,
            border: Color(nsColor: .separatorColor).opacity(highContrast ? 0.70 : 0.34),
            accent: accentColor,
            accentText: accent.textColor(colorScheme: colorScheme, contrast: contrast),
            focusRing: highContrast ? Color(hex: 0xFFB000) : (isDark ? Color.white.opacity(0.84) : Color.black.opacity(0.68)),
            statusInfo: accentColor,
            statusSuccess: accentColor,
            statusWarning: warningColor,
            statusError: isDark ? Color(hex: 0xF07171) : Color(hex: 0xC02424),
            statusSpecial: accentColor,
            statusNeutral: Color(nsColor: .secondaryLabelColor),
            badgeInfoFill: accentColor,
            badgeSuccessFill: accentColor,
            badgeWarningFill: accentColor,
            badgeErrorFill: isDark ? Color(hex: 0xF07171) : Color(hex: 0x9B2C2C),
            badgeSpecialFill: accentColor,
            badgeTextOnFill: accent.textColor(colorScheme: colorScheme, contrast: contrast),
            badgeErrorTextOnFill: isDark ? Color.black : Color.white
        )
    }
}

private struct SableLibraryPaletteKey: EnvironmentKey {
    static let defaultValue = SableLibraryPalette.standard
}

extension EnvironmentValues {
    var sableLibraryPalette: SableLibraryPalette {
        get { self[SableLibraryPaletteKey.self] }
        set { self[SableLibraryPaletteKey.self] = newValue }
    }
}

extension Color {
    static var systemAccent: Color {
        #if os(macOS)
        Color(nsColor: NSColor.controlAccentColor)
        #else
        Color.accentColor
        #endif
    }

    init(hex: UInt32, alpha: Double = 1.0) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

enum SableLibraryDesign {
    static let cornerRadius: CGFloat = 8
}

enum SableLibraryGlassTreatment {
    case none
    case materialFallback
    case liquid
}

enum SableLibraryGlassProminence {
    case automatic
    case none
    case decorative
    case interactive
}

enum SableLibraryGlassIntensity {
    case ultraThin
    case thin
    case regular
    case prominent
}

enum SableLibrarySurfaceRole {
    case navigationLayer
    case chrome
    case panel
    case raisedPanel
    case modal
    case menuTrigger(isActive: Bool)

    func fill(in palette: SableLibraryPalette) -> Color {
        switch self {
        case .navigationLayer, .chrome, .panel, .menuTrigger(_):
            palette.surface
        case .raisedPanel, .modal:
            palette.surfaceRaised
        }
    }

    func border(in palette: SableLibraryPalette) -> Color {
        switch self {
        case .navigationLayer:
            palette.accent.opacity(0.12)
        case .menuTrigger(let isActive):
            isActive ? palette.accent.opacity(0.34) : palette.border
        default:
            palette.border
        }
    }

    func glassTint(in palette: SableLibraryPalette) -> Color? {
        switch self {
        case .menuTrigger(let isActive):
            isActive ? palette.accent : nil
        case .navigationLayer, .chrome, .panel, .raisedPanel, .modal:
            palette.accent
        }
    }

    var glassProminence: SableLibraryGlassProminence {
        switch self {
        case .navigationLayer, .chrome, .panel, .raisedPanel, .modal:
            .decorative
        case .menuTrigger(let isActive):
            isActive ? .interactive : .automatic
        }
    }

    var glassIntensity: SableLibraryGlassIntensity {
        switch self {
        case .navigationLayer:
            .prominent
        case .chrome:
            .regular
        case .menuTrigger(let isActive):
            isActive ? .regular : .thin
        case .panel:
            .regular
        case .raisedPanel, .modal:
            .prominent
        }
    }
}

extension View {
    func sableLibraryNavigationLayer(cornerRadius: CGFloat = 0) -> some View {
        modifier(SableLibraryNavigationLayerModifier(cornerRadius: cornerRadius))
    }

    func sableLibraryAmbientBackground() -> some View {
        background(SableLibraryAmbientBackdrop().ignoresSafeArea())
    }

    func sableLibrarySurface(
        fill: Color,
        border: Color,
        cornerRadius: CGFloat = SableLibraryDesign.cornerRadius,
        glassTint: Color? = nil,
        interactive: Bool = false,
        glassProminence: SableLibraryGlassProminence = .automatic,
        glassIntensity: SableLibraryGlassIntensity = .regular
    ) -> some View {
        modifier(SableLibrarySurfaceModifier(
            fill: fill,
            border: border,
            cornerRadius: cornerRadius,
            glassTint: glassTint,
            interactive: interactive,
            glassProminence: glassProminence,
            glassIntensity: glassIntensity
        ))
    }

    func sableLibrarySurface(
        role: SableLibrarySurfaceRole,
        cornerRadius: CGFloat = SableLibraryDesign.cornerRadius
    ) -> some View {
        modifier(SableLibraryRoleSurfaceModifier(role: role, cornerRadius: cornerRadius))
    }

    func sableLibraryChromeSurface(cornerRadius: CGFloat = SableLibraryDesign.cornerRadius) -> some View {
        sableLibrarySurface(role: .chrome, cornerRadius: cornerRadius)
    }

    func sableLibraryPanelSurface(cornerRadius: CGFloat = SableLibraryDesign.cornerRadius) -> some View {
        sableLibrarySurface(role: .panel, cornerRadius: cornerRadius)
    }

    func sableLibraryRaisedPanelSurface(cornerRadius: CGFloat = SableLibraryDesign.cornerRadius) -> some View {
        sableLibrarySurface(role: .raisedPanel, cornerRadius: cornerRadius)
    }

    func sableLibraryModalSurface(cornerRadius: CGFloat = SableLibraryDesign.cornerRadius) -> some View {
        sableLibrarySurface(role: .modal, cornerRadius: cornerRadius)
    }

    func sableLibraryMenuTriggerSurface(
        isActive: Bool = false,
        cornerRadius: CGFloat = SableLibraryDesign.cornerRadius
    ) -> some View {
        modifier(SableLibraryMenuTriggerSurfaceModifier(isActive: isActive, cornerRadius: cornerRadius))
    }

    func sableLibraryWindowMirrorEffect() -> some View {
        modifier(SableLibraryWindowMirrorModifier())
    }
}

private struct SableLibraryWindowMirrorModifier: ViewModifier {
    @AppStorage("sableLibrary.liquidGlassEnabled") private var liquidGlassEnabled = true
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    func body(content: Content) -> some View {
        content
            .backgroundExtensionEffect(isEnabled: canUseMirrorEffect)
    }

    private var canUseMirrorEffect: Bool {
        liquidGlassEnabled
            && !differentiateWithoutColor
            && !reduceTransparency
            && colorSchemeContrast != .increased
    }
}

private struct SableLibraryNavigationLayerModifier: ViewModifier {
    @Environment(\.sableLibraryPalette) private var palette

    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .sableLibrarySurface(role: .navigationLayer, cornerRadius: cornerRadius)
            .sableLibraryWindowMirrorEffect()
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(palette.border)
                    .frame(width: 1)
                    .accessibilityHidden(true)
            }
    }
}

struct SableLibraryAmbientBackdrop: View {
    @Environment(\.sableLibraryPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                palette.background

                if !quietBackdrop {
                    SableLibrarySteppedFacetMosaicBackdrop(size: geometry.size)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private var quietBackdrop: Bool {
        reduceTransparency || differentiateWithoutColor || colorSchemeContrast == .increased
    }
}

private struct SableLibrarySteppedFacetMosaicBackdrop: View {
    @Environment(\.sableLibraryPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme

    let size: CGSize

    var body: some View {
        Canvas { context, canvasSize in
            drawMosaic(in: &context, size: canvasSize)
        }
        .frame(width: size.width, height: size.height)
    }

    private func drawMosaic(in context: inout GraphicsContext, size: CGSize) {
        let cellSize = CGSize(width: 174, height: 132)
        let origin = CGPoint(x: -cellSize.width * 1.2, y: -cellSize.height * 1.2)
        let columns = Int(ceil((size.width - origin.x) / cellSize.width)) + 2
        let rows = Int(ceil((size.height - origin.y) / cellSize.height)) + 2
        let lineOpacity = colorScheme == .dark ? 0.13 : 0.10

        for row in 0..<rows {
            for column in 0..<columns {
                let p00 = mosaicPoint(row: row, column: column, origin: origin, cellSize: cellSize)
                let p10 = mosaicPoint(row: row, column: column + 1, origin: origin, cellSize: cellSize)
                let p01 = mosaicPoint(row: row + 1, column: column, origin: origin, cellSize: cellSize)
                let p11 = mosaicPoint(row: row + 1, column: column + 1, origin: origin, cellSize: cellSize)

                if unit(row: row, column: column, salt: 91) > 0.5 {
                    drawFacet([p00, p10, p11], row: row, column: column, index: 0, in: &context)
                    drawFacet([p00, p11, p01], row: row, column: column, index: 1, in: &context)
                } else {
                    drawFacet([p00, p10, p01], row: row, column: column, index: 0, in: &context)
                    drawFacet([p10, p11, p01], row: row, column: column, index: 1, in: &context)
                }
            }
        }

        for row in 0..<rows {
            for column in 0..<columns {
                let p00 = mosaicPoint(row: row, column: column, origin: origin, cellSize: cellSize)
                let p10 = mosaicPoint(row: row, column: column + 1, origin: origin, cellSize: cellSize)
                let p01 = mosaicPoint(row: row + 1, column: column, origin: origin, cellSize: cellSize)
                let p11 = mosaicPoint(row: row + 1, column: column + 1, origin: origin, cellSize: cellSize)
                let diagonalEndPoints = unit(row: row, column: column, salt: 91) > 0.5
                    ? (p00, p11)
                    : (p10, p01)

                var path = Path()
                path.move(to: p00)
                path.addLine(to: p10)
                path.addLine(to: p11)
                path.addLine(to: p01)
                path.closeSubpath()
                path.move(to: diagonalEndPoints.0)
                path.addLine(to: diagonalEndPoints.1)

                context.stroke(
                    path,
                    with: .color(palette.accent.opacity(lineOpacity)),
                    style: StrokeStyle(lineWidth: 0.9, lineCap: .round, lineJoin: .round)
                )
            }
        }
    }

    private func drawFacet(_ points: [CGPoint], row: Int, column: Int, index: Int, in context: inout GraphicsContext) {
        var path = Path()
        path.addLines(points)
        path.closeSubpath()

        context.fill(path, with: .color(palette.accent.opacity(facetOpacity(row: row, column: column, index: index))))
    }

    private func mosaicPoint(row: Int, column: Int, origin: CGPoint, cellSize: CGSize) -> CGPoint {
        let baseX = origin.x + CGFloat(column) * cellSize.width
        let baseY = origin.y + CGFloat(row) * cellSize.height
        let jitterX = (unit(row: row, column: column, salt: 17) - 0.5) * cellSize.width * 0.34
        let jitterY = (unit(row: row, column: column, salt: 43) - 0.5) * cellSize.height * 0.34

        return CGPoint(x: baseX + jitterX, y: baseY + jitterY)
    }

    private func facetOpacity(row: Int, column: Int, index: Int) -> Double {
        let steps = [0.055, 0.018, 0.075, 0.036, 0.018, 0.055, 0.00, 0.075, 0.036, 0.018, 0.055, 0.075]
        let shuffledIndex = abs(row * 7 + column * 11 + index * 5 + Int(unit(row: row, column: column, salt: 137) * 17)) % steps.count
        return steps[shuffledIndex]
    }

    private func unit(row: Int, column: Int, salt: UInt64) -> CGFloat {
        var value = UInt64(bitPattern: Int64(row + 4096))
        value = value &* 0x9E3779B185EBCA87
        value ^= UInt64(bitPattern: Int64(column + 4096)) &* 0xC2B2AE3D27D4EB4F
        value ^= salt &* 0x165667B19E3779F9
        value ^= value >> 33
        value = value &* 0xff51afd7ed558ccd
        value ^= value >> 33
        value = value &* 0xc4ceb9fe1a85ec53
        value ^= value >> 33

        return CGFloat(Double(value & 0xffff) / 65_535.0)
    }
}

private struct SableLibraryRoleSurfaceModifier: ViewModifier {
    @Environment(\.sableLibraryPalette) private var palette

    let role: SableLibrarySurfaceRole
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content.sableLibrarySurface(
            fill: role.fill(in: palette),
            border: role.border(in: palette),
            cornerRadius: cornerRadius,
            glassTint: role.glassTint(in: palette),
            interactive: false,
            glassProminence: role.glassProminence,
            glassIntensity: role.glassIntensity
        )
    }
}

private struct SableLibraryMenuTriggerSurfaceModifier: ViewModifier {
    @Environment(\.sableLibraryPalette) private var palette

    let isActive: Bool
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .foregroundStyle(isActive ? palette.accent : palette.textSecondary)
            .sableLibrarySurface(role: .menuTrigger(isActive: isActive), cornerRadius: cornerRadius)
    }
}

private struct SableLibrarySurfaceModifier: ViewModifier {
    @AppStorage("sableLibrary.liquidGlassEnabled") private var liquidGlassEnabled = true
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let fill: Color
    let border: Color
    let cornerRadius: CGFloat
    let glassTint: Color?
    let interactive: Bool
    let glassProminence: SableLibraryGlassProminence
    let glassIntensity: SableLibraryGlassIntensity

    private var wantsGlass: Bool {
        switch glassProminence {
        case .automatic:
            interactive || glassTint != nil
        case .none:
            false
        case .decorative, .interactive:
            true
        }
    }

    private var canUseGlassLikeSurface: Bool {
        liquidGlassEnabled && wantsGlass && !differentiateWithoutColor && !reduceTransparency && colorSchemeContrast != .increased
    }

    private var resolvedTreatment: SableLibraryGlassTreatment {
        guard canUseGlassLikeSurface else { return .none }
        if #available(macOS 26.0, *) {
            return .liquid
        }
        return .materialFallback
    }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)

        return Group {
            if #available(macOS 26.0, *), resolvedTreatment == .liquid {
                let glass = resolvedGlass
                content
                    .background(fill.opacity(glassFillOpacity), in: shape)
                    .background((glassTint ?? Color.clear).opacity(glassAccentWashOpacity), in: shape)
                    .glassEffect(interactive ? glass.interactive() : glass, in: shape)
                    .overlay(glassEdgeOverlay(in: shape))
                    .shadow(color: surfaceShadowColor, radius: surfaceShadowRadius, y: surfaceShadowYOffset)
            } else if resolvedTreatment == .materialFallback {
                content
                    .background(.thinMaterial, in: shape)
                    .background(fill.opacity(materialFillOpacity), in: shape)
                    .background((glassTint ?? Color.clear).opacity(materialAccentWashOpacity), in: shape)
                    .overlay(glassEdgeOverlay(in: shape))
                    .shadow(color: surfaceShadowColor, radius: surfaceShadowRadius, y: surfaceShadowYOffset)
            } else {
                content
                    .background(fill, in: shape)
                    .overlay(fallbackEdgeOverlay(in: shape))
                    .shadow(color: surfaceShadowColor, radius: surfaceShadowRadius, y: surfaceShadowYOffset)
            }
        }
    }

    private func fallbackEdgeOverlay(in shape: RoundedRectangle) -> some View {
        ZStack(alignment: .leading) {
            shape.stroke(fallbackBorderColor, lineWidth: colorSchemeContrast == .increased ? 1.5 : 1)

            if let glassTint, wantsGlass {
                RoundedRectangle(cornerRadius: 999)
                    .fill(glassTint)
                    .frame(width: fallbackAccentRuleWidth)
                    .padding(.vertical, fallbackAccentRuleInset)
                    .padding(.leading, 1)
                    .accessibilityHidden(true)
            }
        }
        .clipShape(shape)
    }

    private func glassEdgeOverlay(in shape: RoundedRectangle) -> some View {
        ZStack {
            shape.stroke(leadBorderColor.opacity(leadBorderOpacity), lineWidth: colorSchemeContrast == .increased ? 1.5 : 1)
            shape
                .inset(by: 1)
                .stroke((glassTint ?? border).opacity(innerTintStrokeOpacity), lineWidth: 1)
        }
    }

    @available(macOS 26.0, *)
    private var resolvedGlass: Glass {
        let base: Glass
        switch glassIntensity {
        case .ultraThin, .thin:
            base = .clear
        case .regular, .prominent:
            base = .regular
        }

        guard let glassTint else { return base }
        return base.tint(glassTint.opacity(glassTintOpacity))
    }

    private var isDark: Bool {
        colorScheme == .dark
    }

    private var glassTintOpacity: Double {
        switch (isDark, glassIntensity) {
        case (false, .ultraThin): return 0.026
        case (false, .thin): return 0.044
        case (false, .regular): return 0.074
        case (false, .prominent): return 0.106
        case (true, .ultraThin): return 0.030
        case (true, .thin): return 0.052
        case (true, .regular): return 0.082
        case (true, .prominent): return 0.120
        }
    }

    private var glassFillOpacity: Double {
        switch glassIntensity {
        case .ultraThin: return 0.22
        case .thin: return 0.34
        case .regular: return 0.52
        case .prominent: return 0.66
        }
    }

    private var materialFillOpacity: Double {
        switch glassIntensity {
        case .ultraThin: return 0.34
        case .thin: return 0.46
        case .regular: return 0.62
        case .prominent: return 0.76
        }
    }

    private var glassAccentWashOpacity: Double {
        switch glassIntensity {
        case .ultraThin: return 0.006
        case .thin: return 0.010
        case .regular: return 0.016
        case .prominent: return 0.026
        }
    }

    private var materialAccentWashOpacity: Double {
        switch glassIntensity {
        case .ultraThin: return 0.010
        case .thin: return 0.018
        case .regular: return 0.028
        case .prominent: return 0.044
        }
    }

    private var leadBorderColor: Color {
        isDark ? Color.white : Color.black
    }

    private var leadBorderOpacity: Double {
        switch glassIntensity {
        case .ultraThin: return isDark ? 0.16 : 0.12
        case .thin: return isDark ? 0.20 : 0.16
        case .regular: return isDark ? 0.26 : 0.21
        case .prominent: return isDark ? 0.34 : 0.28
        }
    }

    private var innerTintStrokeOpacity: Double {
        switch glassIntensity {
        case .ultraThin: return 0.14
        case .thin: return 0.20
        case .regular: return 0.28
        case .prominent: return 0.40
        }
    }

    private var fallbackBorderColor: Color {
        guard let glassTint, wantsGlass else { return border }
        return colorSchemeContrast == .increased ? glassTint : border
    }

    private var fallbackAccentRuleWidth: CGFloat {
        switch glassIntensity {
        case .ultraThin: return colorSchemeContrast == .increased ? 3 : 2
        case .thin: return colorSchemeContrast == .increased ? 3 : 2
        case .regular: return colorSchemeContrast == .increased ? 4 : 3
        case .prominent: return colorSchemeContrast == .increased ? 5 : 4
        }
    }

    private var fallbackAccentRuleInset: CGFloat {
        switch glassIntensity {
        case .ultraThin, .thin: return 8
        case .regular: return 7
        case .prominent: return 6
        }
    }

    private var surfaceShadowColor: Color {
        guard colorSchemeContrast != .increased else { return .clear }
        switch glassIntensity {
        case .ultraThin:
            return .clear
        case .thin:
            return Color.black.opacity(isDark ? 0.10 : 0.05)
        case .regular:
            return Color.black.opacity(isDark ? 0.14 : 0.07)
        case .prominent:
            return Color.black.opacity(isDark ? 0.18 : 0.09)
        }
    }

    private var surfaceShadowRadius: CGFloat {
        switch glassIntensity {
        case .ultraThin: return 0
        case .thin: return 8
        case .regular: return 14
        case .prominent: return 20
        }
    }

    private var surfaceShadowYOffset: CGFloat {
        switch glassIntensity {
        case .ultraThin: return 0
        case .thin: return 3
        case .regular: return 6
        case .prominent: return 9
        }
    }
}

enum SableLibraryStatusRole: String, Hashable {
    case success
    case warning
    case error
    case info
    case review
    case running
    case undo
    case neutral

    var color: Color {
        color(in: .standard)
    }

    func color(in palette: SableLibraryPalette) -> Color {
        switch self {
        case .success: palette.accent
        case .warning: palette.accent
        case .error: palette.statusError
        case .info: palette.accent
        case .review: palette.accent
        case .running: palette.accent
        case .undo: palette.accent
        case .neutral: palette.statusNeutral
        }
    }

    var defaultSymbol: String {
        switch self {
        case .success: "checkmark.circle"
        case .warning: "exclamationmark.triangle"
        case .error: "xmark.octagon"
        case .info: "info.circle"
        case .review: "eye"
        case .running: "bolt.fill"
        case .undo: "arrow.uturn.backward.circle"
        case .neutral: "circle"
        }
    }
}

struct SableLibraryStatusBadge: View {
    @Environment(\.sableLibraryPalette) private var palette
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    let text: String
    let role: SableLibraryStatusRole
    var systemImage: String?

    var body: some View {
        Label(text, systemImage: systemImage ?? role.defaultSymbol)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(role.color(in: palette))
            .sableLibrarySurface(
                fill: role.color(in: palette).opacity(differentiateWithoutColor ? 0.18 : 0.12),
                border: differentiateWithoutColor ? role.color(in: palette) : Color.clear,
                cornerRadius: 999,
                glassTint: role.color(in: palette)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(text)")
    }
}

struct SableLibraryInfoBanner: View {
    @Environment(\.sableLibraryPalette) private var palette

    let text: String
    var role: SableLibraryStatusRole = .info
    var systemImage: String? = nil

    var body: some View {
        Label(text, systemImage: systemImage ?? role.defaultSymbol)
            .font(isProminent ? .callout : .caption)
            .foregroundStyle(palette.textSecondary)
            .padding(isProminent ? 12 : 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sableLibrarySurface(
                fill: role.color(in: palette).opacity(isProminent ? 0.09 : 0.06),
                border: role.color(in: palette).opacity(isProminent ? 0.18 : 0.12),
                glassTint: role.color(in: palette)
            )
            .accessibilityElement(children: .combine)
    }

    private var isProminent: Bool {
        role == .warning || role == .error || role == .running
    }
}
