#!/usr/bin/env swift
// Renders the QuotaBar app icon (a minimal gauge) into the asset catalog.
// Usage: swift Scripts/generate-icon.swift
import AppKit

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first
    ?? "QuotaBar/Resources/Assets.xcassets/AppIcon.appiconset")

func drawIcon(in context: CGContext, size: CGFloat) {
    let scale = size / 1024
    context.scaleBy(x: scale, y: scale)

    // macOS icon grid: an 824pt rounded square centred on a 1024pt canvas.
    let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
    let platePath = CGPath(roundedRect: plate, cornerWidth: 186, cornerHeight: 186, transform: nil)
    context.saveGState()
    context.addPath(platePath)
    context.clip()
    let colors = [CGColor(red: 0.20, green: 0.21, blue: 0.25, alpha: 1), CGColor(red: 0.08, green: 0.09, blue: 0.11, alpha: 1)]
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    context.restoreGState()

    // Gauge: a 270° arc opening downwards, 68% filled.
    let center = CGPoint(x: 512, y: 470)
    let radius: CGFloat = 250
    let start = CGFloat.pi * 1.25
    let sweep = CGFloat.pi * 1.5
    let fraction: CGFloat = 0.68
    context.setLineCap(.round)
    context.setLineWidth(76)

    context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.16))
    context.addArc(center: center, radius: radius, startAngle: start, endAngle: start - sweep, clockwise: true)
    context.strokePath()

    context.setStrokeColor(CGColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 1))
    context.addArc(center: center, radius: radius, startAngle: start, endAngle: start - sweep * fraction, clockwise: true)
    context.strokePath()

    // Needle pointing at the end of the filled arc.
    let angle = start - sweep * fraction
    let tip = CGPoint(x: center.x + cos(angle) * 150, y: center.y + sin(angle) * 150)
    context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
    context.setLineWidth(40)
    context.move(to: center)
    context.addLine(to: tip)
    context.strokePath()
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
    context.fillEllipse(in: CGRect(x: center.x - 44, y: center.y - 44, width: 88, height: 88))
}

func writeIcon(pixels: Int, name: String) throws {
    let context = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    drawIcon(in: context, size: CGFloat(pixels))
    let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
    let data = bitmap.representation(using: .png, properties: [:])!
    try data.write(to: outputDirectory.appendingPathComponent(name))
}

let variants: [(points: Int, scale: Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
var images: [[String: String]] = []
for variant in variants {
    let name = "icon_\(variant.points)x\(variant.points)\(variant.scale == 2 ? "@2x" : "").png"
    try writeIcon(pixels: variant.points * variant.scale, name: name)
    images.append([
        "filename": name, "idiom": "mac",
        "scale": "\(variant.scale)x", "size": "\(variant.points)x\(variant.points)",
    ])
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: outputDirectory.appendingPathComponent("Contents.json"))
print("Wrote \(variants.count) icons to \(outputDirectory.path)")
