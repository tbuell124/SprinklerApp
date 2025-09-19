import SwiftUI

/// Shared color palette used throughout the Sprink app.
extension Color {
    /// Normalised background color that respects the active platform's default surfaces.
    static var appBackground: Color {
        #if os(iOS)
        Color(UIColor.systemBackground)
        #elseif canImport(AppKit)
        Color(NSColor.windowBackgroundColor)
        #else
        Color.white
        #endif
    }

    /// Secondary background used for subtle contrast between cards and the canvas.
    static var appSecondaryBackground: Color {
        #if os(iOS)
        Color(UIColor.secondarySystemBackground)
        #elseif canImport(AppKit)
        Color(NSColor.controlBackgroundColor)
        #else
        Color(white: 0.94)
        #endif
    }

    /// Provides a sensible separator colour across platforms for card dividers.
    static var appSeparator: Color {
        #if os(iOS)
        Color(UIColor.separator)
        #elseif canImport(AppKit)
        Color(NSColor.separatorColor)
        #else
        Color.gray.opacity(0.3)
        #endif
    }
}
