#!/usr/bin/env swift
//
//  MakeIcon.swift
//  Generates the complete AppIcon set from an SF Symbol.
//  Usage:  swift Tools/MakeIcon.swift
//
//  Deliberately a script in the repo: the icon stays reproducible instead
//  of being a binary nobody can regenerate.
//

import AppKit
import Foundation

let symbolName = "clock.arrow.circlepath"
let outputPath = "Resources/Assets.xcassets/AppIcon.appiconset"
let canvas: CGFloat = 1024

// Typical macOS corner radius (squircle approximation).
let cornerRadius = canvas * 0.2237

let topColor = NSColor(srgbRed: 0.04, green: 0.52, blue: 1.00, alpha: 1)     // systemBlue
let bottomColor = NSColor(srgbRed: 0.37, green: 0.36, blue: 0.90, alpha: 1)  // systemIndigo

func makeGlyph(size: CGFloat) -> NSImage? {
    let config = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
    guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
        .withSymbolConfiguration(config) else { return nil }

    // Render the symbol into its own image and tint it white there.
    let glyph = NSImage(size: symbol.size)
    glyph.lockFocus()
    let rect = NSRect(origin: .zero, size: symbol.size)
    symbol.draw(in: rect)
    NSColor.white.set()
    rect.fill(using: .sourceAtop)
    glyph.unlockFocus()
    return glyph
}

func makeIcon() -> NSImage {
    let image = NSImage(size: NSSize(width: canvas, height: canvas))
    image.lockFocus()

    let rect = NSRect(x: 0, y: 0, width: canvas, height: canvas)
    let shape = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
    shape.addClip()

    NSGradient(colors: [topColor, bottomColor])?.draw(in: rect, angle: -90)

    if let glyph = makeGlyph(size: canvas * 0.52) {
        let target = NSRect(
            x: (canvas - glyph.size.width) / 2,
            y: (canvas - glyph.size.height) / 2,
            width: glyph.size.width,
            height: glyph.size.height
        )
        // A subtle shadow gives the glyph depth without shouting.
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
        shadow.shadowBlurRadius = canvas * 0.02
        shadow.shadowOffset = NSSize(width: 0, height: -canvas * 0.008)
        shadow.set()
        glyph.draw(in: target)
        NSGraphicsContext.restoreGraphicsState()
    } else {
        FileHandle.standardError.write("Symbol \(symbolName) unavailable.\n".data(using: .utf8)!)
        exit(1)
    }

    image.unlockFocus()
    return image
}

func write(_ image: NSImage, pixels: Int, to url: URL) {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return }
    rep.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()

    if let data = rep.representation(using: .png, properties: [:]) {
        try? data.write(to: url)
    }
}

// MARK: - Export

let fm = FileManager.default
let outURL = URL(fileURLWithPath: outputPath)
try? fm.createDirectory(at: outURL, withIntermediateDirectories: true)

let icon = makeIcon()
let sizes: [(Int, Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]

var entries: [[String: String]] = []
for (points, scale) in sizes {
    let filename = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    write(icon, pixels: points * scale, to: outURL.appendingPathComponent(filename))
    entries.append([
        "size": "\(points)x\(points)",
        "idiom": "mac",
        "filename": filename,
        "scale": "\(scale)x"
    ])
}

let contents: [String: Any] = ["images": entries, "info": ["version": 1, "author": "xcode"]]
let data = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try data.write(to: outURL.appendingPathComponent("Contents.json"))

let catalogInfo: [String: Any] = ["info": ["version": 1, "author": "xcode"]]
let catalogData = try JSONSerialization.data(withJSONObject: catalogInfo, options: [.prettyPrinted])
try catalogData.write(to: URL(fileURLWithPath: "Resources/Assets.xcassets/Contents.json"))

print("Icon written: \(entries.count) sizes in \(outputPath)")
