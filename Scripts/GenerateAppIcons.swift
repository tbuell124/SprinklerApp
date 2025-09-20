#!/usr/bin/env swift
//
//  GenerateAppIcons.swift
//  SprinklerApp
//
//  This script procedurally generates the AppIcon PNG variants used by the
//  SprinklerMobile target. It intentionally lives outside of the Xcode build
//  products so the repository can avoid committing large binary assets while
//  still producing deterministic icon artwork at build time.
//

import Foundation
import AppKit

/// Configuration that describes an icon PNG that must be produced.
private struct IconSpecification {
    let filename: String
    let pointSize: CGFloat
    let scale: CGFloat

    var pixelSize: CGFloat { pointSize * scale }
}

/// The list of icons required by the AppIcon asset catalog.
/// The sizes mirror the filenames included in the asset's Contents.json file.
private let specifications: [IconSpecification] = [
    IconSpecification(filename: "AppIcon-20@2x.png", pointSize: 20, scale: 2),
    IconSpecification(filename: "AppIcon-20@3x.png", pointSize: 20, scale: 3),
    IconSpecification(filename: "AppIcon-29@2x.png", pointSize: 29, scale: 2),
    IconSpecification(filename: "AppIcon-29@3x.png", pointSize: 29, scale: 3),
    IconSpecification(filename: "AppIcon-40@2x.png", pointSize: 40, scale: 2),
    IconSpecification(filename: "AppIcon-40@3x.png", pointSize: 40, scale: 3),
    IconSpecification(filename: "AppIcon-60@2x.png", pointSize: 60, scale: 2),
    IconSpecification(filename: "AppIcon-60@3x.png", pointSize: 60, scale: 3),
    IconSpecification(filename: "AppIcon-76@2x.png", pointSize: 76, scale: 2),
    IconSpecification(filename: "AppIcon-83.5@2x.png", pointSize: 83.5, scale: 2),
    IconSpecification(filename: "AppIcon-1024.png", pointSize: 1024, scale: 1)
]

/// Colors used to build the icon's gradient background.
private let gradientColors: [NSColor] = [
    NSColor(calibratedRed: 0.09, green: 0.53, blue: 0.95, alpha: 1.0),
    NSColor(calibratedRed: 0.35, green: 0.82, blue: 0.58, alpha: 1.0)
]

/// The foreground color used to draw the stylized "S" glyph.
private let glyphColor = NSColor(calibratedWhite: 1.0, alpha: 0.9)

/// Entry point that validates arguments and orchestrates icon generation.
@main
enum GenerateAppIcons {
    static func main() {
        do {
            let destinationPath = try resolveDestinationPath()
            try FileManager.default.createDirectory(at: destinationPath, withIntermediateDirectories: true)
            try specifications.forEach { specification in
                try renderIcon(specification: specification, destinationDirectory: destinationPath)
            }
            fputs("App icons generated at \(destinationPath.path)\n", stdout)
        } catch {
            fputs("\(error.localizedDescription)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }

    /// Resolves the destination directory supplied by the caller.
    private static func resolveDestinationPath() throws -> URL {
        guard CommandLine.arguments.count >= 2 else {
            throw NSError(domain: "GenerateAppIcons", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Missing output directory argument"
            ])
        }

        let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        return destination
    }

    /// Renders a single icon to disk based on the supplied specification.
    private static func renderIcon(specification: IconSpecification, destinationDirectory: URL) throws {
        let size = NSSize(width: specification.pixelSize, height: specification.pixelSize)
        let image = NSImage(size: size)

        image.lockFocus()
        defer { image.unlockFocus() }

        let rect = NSRect(origin: .zero, size: size)

        // Draw a simple vertical gradient to create visual depth.
        if let gradient = NSGradient(colors: gradientColors) {
            gradient.draw(in: rect, angle: 90)
        } else {
            gradientColors.first?.setFill()
            rect.fill()
        }

        // Draw a rounded rectangle stroke to soften the corners slightly.
        let cornerRadius = size.width * 0.18
        let roundedPath = NSBezierPath(roundedRect: rect.insetBy(dx: size.width * 0.05, dy: size.height * 0.05), xRadius: cornerRadius, yRadius: cornerRadius)
        glyphColor.withAlphaComponent(0.2).setStroke()
        roundedPath.lineWidth = size.width * 0.04
        roundedPath.stroke()

        // Draw the centered "S" glyph representing "Sprinkler".
        let glyph = "S" as NSString
        let fontSize = size.width * 0.55
        let font = NSFont.systemFont(ofSize: fontSize, weight: .heavy)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: glyphColor,
            .paragraphStyle: paragraphStyle
        ]

        let glyphRect = rect.insetBy(dx: size.width * 0.18, dy: size.height * 0.18)
        glyph.draw(in: glyphRect, withAttributes: attributes)

        try write(image: image, to: destinationDirectory.appendingPathComponent(specification.filename))
    }

    /// Writes the generated NSImage to disk as a PNG file.
    private static func write(image: NSImage, to url: URL) throws {
        guard let tiffRepresentation = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiffRepresentation) else {
            throw NSError(domain: "GenerateAppIcons", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Failed to capture bitmap representation"
            ])
        }

        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "GenerateAppIcons", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Failed to encode PNG data"
            ])
        }

        try pngData.write(to: url, options: .atomic)
    }
}
