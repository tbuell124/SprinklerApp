import SwiftUI

/// Centralized app colors backed by Apple semantic colors.
extension Color {
    /// Primary window background (adapts to light/dark, vibrancy, etc.)
    static let appBackground = Color(.systemBackground)

    /// Secondary group/card background
    static let appSecondaryBackground = Color(.secondarySystemBackground)

    /// Subtle separator color
    static let appSeparator = Color(.separator)
}
