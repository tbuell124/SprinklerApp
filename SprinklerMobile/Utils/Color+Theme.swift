import SwiftUI

/// Provides ShapeStyle accessors for theme colour tokens so that `.foregroundStyle(.token)`
/// and similar APIs compile across the codebase. The computed properties simply forward to
/// the canonical definitions declared in `Theme.swift`.
extension ShapeStyle {
    /// Primary canvas colour used for top-level backgrounds.
    static var appPrimaryBackground: Color { Color.appPrimaryBackground }

    /// Secondary surface colour for grouped content.
    static var appSecondaryBackground: Color { Color.appSecondaryBackground }

    /// Elevated background applied to cards.
    static var appCardBackground: Color { Color.appCardBackground }

    /// Highlight colour used for card gradients.
    static var appCardBackgroundElevated: Color { Color.appCardBackgroundElevated }

    /// High-contrast stroke colour for cards.
    static var appCardStroke: Color { Color.appCardStroke }

    /// Divider colour for separators.
    static var appSeparator: Color { Color.appSeparator }

    /// Primary accent colour.
    static var appAccentPrimary: Color { Color.appAccentPrimary }

    /// Secondary accent colour.
    static var appAccentSecondary: Color { Color.appAccentSecondary }

    /// Success state colour.
    static var appSuccess: Color { Color.appSuccess }

    /// Warning state colour.
    static var appWarning: Color { Color.appWarning }

    /// Danger state colour.
    static var appDanger: Color { Color.appDanger }

    /// Informational blue used for neutral messaging.
    static var appInfo: Color { Color.appInfo }

    /// Ambient shadow colour tuned for translucency.
    static var appShadow: Color { Color.appShadow }

    /// Top gradient colour for canvas backgrounds.
    static var appCanvasTop: Color { Color.appCanvasTop }

    /// Bottom gradient colour for canvas backgrounds.
    static var appCanvasBottom: Color { Color.appCanvasBottom }

    /// Legacy alias maintained for backwards compatibility while the codebase migrates to
    /// the refreshed theme.
    static var appBackground: Color { Color.appBackground }
}
