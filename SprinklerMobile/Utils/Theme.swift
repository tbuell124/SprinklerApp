import SwiftUI

#if canImport(UIKit)
import UIKit
private typealias PlatformColor = UIColor
#elseif canImport(AppKit)
import AppKit
private typealias PlatformColor = NSColor
#endif

/// Centralised theme utilities that define Sprink's visual language and accessibility behaviour.
/// The palette favours Apple semantic colours, augmenting them with carefully tuned custom
/// accents that meet a minimum 4.5:1 contrast ratio for standard text while responding to the
/// user's increased-contrast accessibility preference.
enum AppTheme {}

// MARK: - Colours

private enum ThemePalette {
    static let primaryBackground = Color.dynamicColor(
        light: ThemeColorProvider.systemBackground,
        dark: Color.makeColor(18, 18, 21),
        highContrastLight: Color.makeColor(242, 242, 247),
        highContrastDark: Color.makeColor(5, 5, 8)
    )

    static let secondaryBackground = Color.dynamicColor(
        light: ThemeColorProvider.secondaryBackground,
        dark: Color.makeColor(30, 31, 38),
        highContrastLight: Color.makeColor(226, 228, 235),
        highContrastDark: Color.makeColor(12, 12, 16)
    )

    static let cardBackground = Color.dynamicColor(
        light: Color.makeColor(250, 250, 252),
        dark: Color.makeColor(28, 29, 36),
        highContrastLight: Color.makeColor(255, 255, 255),
        highContrastDark: Color.makeColor(18, 18, 24)
    )

    static let cardBackgroundElevated = Color.dynamicColor(
        light: Color.makeColor(236, 239, 255),
        dark: Color.makeColor(36, 39, 50),
        highContrastLight: Color.makeColor(224, 229, 255),
        highContrastDark: Color.makeColor(28, 32, 42)
    )

    static let cardStroke = Color.dynamicColor(
        light: Color.makeColor(204, 208, 222),
        dark: Color.makeColor(68, 72, 84),
        highContrastLight: Color.makeColor(116, 120, 134),
        highContrastDark: Color.makeColor(132, 138, 150)
    )

    static let separator = Color.dynamicColor(
        light: ThemeColorProvider.separator,
        dark: Color.makeColor(80, 82, 90),
        highContrastLight: Color.makeColor(86, 88, 96),
        highContrastDark: Color.makeColor(156, 158, 166)
    )

    static let accentPrimary = Color.dynamicColor(
        light: Color.makeColor(0, 98, 204),
        dark: Color.makeColor(93, 182, 255),
        highContrastLight: Color.makeColor(0, 71, 148),
        highContrastDark: Color.makeColor(142, 210, 255)
    )

    static let accentSecondary = Color.dynamicColor(
        light: Color.makeColor(118, 53, 220),
        dark: Color.makeColor(171, 135, 255),
        highContrastLight: Color.makeColor(94, 34, 181),
        highContrastDark: Color.makeColor(195, 164, 255)
    )

    static let success = Color.dynamicColor(
        light: Color.makeColor(12, 140, 64),
        dark: Color.makeColor(84, 217, 130),
        highContrastLight: Color.makeColor(0, 94, 46),
        highContrastDark: Color.makeColor(142, 255, 176)
    )

    static let warning = Color.dynamicColor(
        light: Color.makeColor(206, 129, 18),
        dark: Color.makeColor(250, 189, 92),
        highContrastLight: Color.makeColor(161, 93, 0),
        highContrastDark: Color.makeColor(255, 206, 120)
    )

    static let danger = Color.dynamicColor(
        light: Color.makeColor(204, 43, 62),
        dark: Color.makeColor(255, 114, 136),
        highContrastLight: Color.makeColor(156, 22, 39),
        highContrastDark: Color.makeColor(255, 146, 164)
    )

    static let info = Color.dynamicColor(
        light: Color.makeColor(0, 116, 191),
        dark: Color.makeColor(101, 190, 255),
        highContrastLight: Color.makeColor(0, 82, 134),
        highContrastDark: Color.makeColor(149, 214, 255)
    )

    static let shadow = Color.dynamicColor(
        light: Color.makeColor(15, 18, 31, alpha: 0.35),
        dark: Color.makeColor(0, 0, 0, alpha: 0.7),
        highContrastLight: Color.makeColor(6, 7, 12, alpha: 0.45),
        highContrastDark: Color.makeColor(0, 0, 0, alpha: 0.8)
    )

    static let canvasTop = Color.dynamicColor(
        light: Color.makeColor(245, 247, 255),
        dark: Color.makeColor(18, 19, 24),
        highContrastLight: Color.makeColor(250, 250, 255),
        highContrastDark: Color.makeColor(8, 8, 12)
    )

    static let canvasBottom = Color.dynamicColor(
        light: Color.makeColor(230, 235, 255),
        dark: Color.makeColor(8, 8, 12),
        highContrastLight: Color.makeColor(236, 240, 255),
        highContrastDark: Color.makeColor(2, 2, 6)
    )
}

extension Color {
    /// Primary canvas colour used for top-level backgrounds.
    static var appPrimaryBackground: Color { ThemePalette.primaryBackground }

    /// Secondary surface that provides gentle contrast for grouped content.
    static var appSecondaryBackground: Color { ThemePalette.secondaryBackground }

    /// Elevated background applied to cards.
    static var appCardBackground: Color { ThemePalette.cardBackground }

    /// Highlight colour for elevated card gradients.
    static var appCardBackgroundElevated: Color { ThemePalette.cardBackgroundElevated }

    /// Stroke applied to cards for high-contrast outlines.
    static var appCardStroke: Color { ThemePalette.cardStroke }

    /// Separator colour used for dividers.
    static var appSeparator: Color { ThemePalette.separator }

    /// Primary accent colour with sufficient contrast in light and dark modes.
    static var appAccentPrimary: Color { ThemePalette.accentPrimary }

    /// Secondary accent for complementary highlights.
    static var appAccentSecondary: Color { ThemePalette.accentSecondary }

    /// Success colour for positive states and confirmations.
    static var appSuccess: Color { ThemePalette.success }

    /// Warning colour for cautionary messaging.
    static var appWarning: Color { ThemePalette.warning }

    /// Error colour for critical alerts.
    static var appDanger: Color { ThemePalette.danger }

    /// Informational blue for neutral messaging.
    static var appInfo: Color { ThemePalette.info }

    /// Ambient shadow colour tuned for translucency.
    static var appShadow: Color { ThemePalette.shadow }

    /// Top colour used when constructing canvas gradients.
    static var appCanvasTop: Color { ThemePalette.canvasTop }

    /// Bottom colour used when constructing canvas gradients.
    static var appCanvasBottom: Color { ThemePalette.canvasBottom }

    /// Legacy alias maintained for backwards compatibility while the codebase migrates to the
    /// new naming scheme introduced with the refreshed theme.
    static var appBackground: Color { ThemePalette.primaryBackground }
}

extension LinearGradient {
    /// Convenience gradient representing the app's default background wash.
    static var appCanvas: LinearGradient {
        LinearGradient(colors: [Color.appCanvasTop, Color.appCanvasBottom],
                       startPoint: .top,
                       endPoint: .bottom)
    }
}

// MARK: - Typography

extension Font {
    /// Large display title for hero content.
    static var appLargeTitle: Font {
        .system(.largeTitle, design: .rounded).weight(.bold)
    }

    /// Prominent title used for feature highlights and hero sections.
    static var appTitle: Font {
        .system(.title2, design: .rounded).weight(.bold)
    }

    /// Primary headings for sections.
    static var appHeadline: Font {
        .system(.title3, design: .rounded).weight(.semibold)
    }

    /// Supporting headings within cards.
    static var appSubheadline: Font {
        .system(.subheadline, design: .rounded).weight(.medium)
    }

    /// Standard body copy used across the interface.
    static var appBody: Font {
        .system(.body, design: .rounded)
    }

    /// Monospaced body style for emphasising raw values or codes.
    static var appMonospacedBody: Font {
        .system(.body, design: .monospaced)
    }

    /// Supporting footnote copy.
    static var appFootnote: Font {
        .system(.footnote, design: .rounded)
    }

    /// Caption text for annotations and helper copy.
    static var appCaption: Font {
        .system(.caption, design: .rounded)
    }

    /// Secondary caption for dense metadata.
    static var appCaption2: Font {
        .system(.caption2, design: .rounded)
    }

    /// Button text with increased weight for prominence.
    static var appButton: Font {
        .system(.headline, design: .rounded).weight(.semibold)
    }
}

// MARK: - Card Components

/// Canonical configuration describing how a themed card should be rendered.
struct CardConfiguration {
    struct Stroke {
        let color: Color
        let lineWidth: CGFloat
    }

    struct Shadow {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }

    let padding: CGFloat
    let cornerRadius: CGFloat
    let background: AnyShapeStyle
    let stroke: Stroke?
    let shadow: Shadow?

    /// Default card style used throughout the dashboard and settings surfaces.
    static let standard = CardConfiguration(
        padding: 20,
        cornerRadius: 22,
        background: AnyShapeStyle(LinearGradient(colors: [Color.appCardBackground, Color.appCardBackgroundElevated],
                                                 startPoint: .topLeading,
                                                 endPoint: .bottomTrailing)),
        stroke: Stroke(color: Color.appCardStroke.opacity(0.7), lineWidth: 1),
        shadow: Shadow(color: Color.appShadow.opacity(0.18), radius: 16, x: 0, y: 12)
    )

    /// Prominent card style used for hero content that leans on an accent colour.
    static func hero(accent: Color) -> CardConfiguration {
        CardConfiguration(
            padding: 24,
            cornerRadius: 28,
            background: AnyShapeStyle(LinearGradient(colors: [accent.opacity(0.32), Color.appCardBackgroundElevated],
                                                     startPoint: .topLeading,
                                                     endPoint: .bottomTrailing)),
            stroke: Stroke(color: Color.appCardStroke.opacity(0.5), lineWidth: 1),
            shadow: Shadow(color: Color.appShadow.opacity(0.24), radius: 24, x: 0, y: 16)
        )
    }

    /// Subtle style used for quick actions and smaller informational tiles.
    static let subtle = CardConfiguration(
        padding: 18,
        cornerRadius: 20,
        background: AnyShapeStyle(LinearGradient(colors: [Color.appCardBackground, Color.appCardBackground.opacity(0.92)],
                                                 startPoint: .top,
                                                 endPoint: .bottomTrailing)),
        stroke: Stroke(color: Color.appCardStroke.opacity(0.4), lineWidth: 1),
        shadow: Shadow(color: Color.appShadow.opacity(0.12), radius: 12, x: 0, y: 10)
    )
}

/// Protocol describing a reusable card that automatically adopts the shared styling.
protocol CardView: View {
    associatedtype CardContent: View

    /// Configuration describing the card's visual styling.
    var cardConfiguration: CardConfiguration { get }

    /// Content rendered inside the card.
    @ViewBuilder var cardBody: CardContent { get }
}

extension CardView {
    var cardConfiguration: CardConfiguration { .standard }

    var body: some View {
        CardContainer(configuration: cardConfiguration) {
            cardBody
        }
    }
}

/// Wrapper view that applies padding, rounded corners, gradients, and shadows consistently.
struct CardContainer<Content: View>: View {
    let configuration: CardConfiguration
    let content: Content

    init(configuration: CardConfiguration = .standard, @ViewBuilder content: () -> Content) {
        self.configuration = configuration
        self.content = content()
    }

    var body: some View {
        content
            .padding(configuration.padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: configuration.cornerRadius, style: .continuous)
                    .fill(configuration.background)
                    .overlay {
                        if let stroke = configuration.stroke {
                            RoundedRectangle(cornerRadius: configuration.cornerRadius, style: .continuous)
                                .stroke(stroke.color, lineWidth: stroke.lineWidth)
                        }
                    }
            )
            .shadow(color: configuration.shadow?.color ?? .clear,
                    radius: configuration.shadow?.radius ?? 0,
                    x: configuration.shadow?.x ?? 0,
                    y: configuration.shadow?.y ?? 0)
    }
}

// MARK: - Helpers

private enum ThemeColorProvider {
    #if canImport(UIKit)
    static var systemBackground: PlatformColor { .systemGroupedBackground }
    static var secondaryBackground: PlatformColor { .secondarySystemBackground }
    static var separator: PlatformColor { .separator }
    #elseif canImport(AppKit)
    static var systemBackground: PlatformColor { .windowBackgroundColor }
    static var secondaryBackground: PlatformColor { .underPageBackgroundColor }
    static var separator: PlatformColor { .separatorColor }
    #else
    static var systemBackground: PlatformColor { PlatformColor.white }
    static var secondaryBackground: PlatformColor { PlatformColor.white }
    static var separator: PlatformColor { PlatformColor.gray }
    #endif
}

private extension Color {
    static func makeColor(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, alpha: CGFloat = 1) -> PlatformColor {
        #if canImport(UIKit)
        PlatformColor(red: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
        #elseif canImport(AppKit)
        PlatformColor(calibratedRed: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
        #else
        PlatformColor(red: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
        #endif
    }

    static func dynamicColor(light: PlatformColor,
                             dark: PlatformColor,
                             highContrastLight: PlatformColor? = nil,
                             highContrastDark: PlatformColor? = nil) -> Color {
        #if canImport(UIKit)
        return Color(PlatformColor { traits in
            let usesDarkMode = traits.userInterfaceStyle == .dark
            let prefersHighContrast = traits.accessibilityContrast == .high

            if usesDarkMode {
                if prefersHighContrast, let override = highContrastDark { return override }
                return dark
            } else {
                if prefersHighContrast, let override = highContrastLight { return override }
                return light
            }
        })
        #elseif canImport(AppKit)
        return Color(PlatformColor(name: nil) { appearance in
            let usesDarkMode = appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
            let highContrastAppearances: [NSAppearance.Name] = [
                .accessibilityHighContrastAqua,
                .accessibilityHighContrastDarkAqua,
                .accessibilityHighContrastVibrantLight,
                .accessibilityHighContrastVibrantDark
            ]
            let prefersHighContrast = appearance.bestMatch(from: highContrastAppearances) != nil

            if usesDarkMode {
                if prefersHighContrast, let override = highContrastDark { return override }
                return dark
            } else {
                if prefersHighContrast, let override = highContrastLight { return override }
                return light
            }
        })
        #else
        return Color(light)
        #endif
    }
}
