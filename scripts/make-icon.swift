#!/usr/bin/env swift
import AppKit
import Foundation

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("usage: make-icon.swift <input.svg> <output.icns>")
    exit(1)
}

let inputURL = URL(fileURLWithPath: args[1])
let outputURL = URL(fileURLWithPath: args[2])

guard let img = NSImage(contentsOf: inputURL) else {
    print("ERROR: cannot load \(inputURL.path)")
    exit(1)
}

let sizes: [(Int, String)] = [
    (16,  "icon_16x16.png"),
    (32,  "icon_16x16@2x.png"),
    (32,  "icon_32x32.png"),
    (64,  "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024,"icon_512x512@2x.png")
]

let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("modulr.iconset")
try? FileManager.default.removeItem(at: tmpDir)
try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

for (size, name) in sizes {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    img.draw(in: rect, from: .zero, operation: .copy, fraction: 1.0)
    NSGraphicsContext.restoreGraphicsState()

    let data = rep.representation(using: .png, properties: [:])!
    let url = tmpDir.appendingPathComponent(name)
    try data.write(to: url)
    print("wrote \(name) (\(size)x\(size))")
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", tmpDir.path, "-o", outputURL.path]
try task.run()
task.waitUntilExit()

if task.terminationStatus == 0 {
    print("created \(outputURL.path)")
} else {
    print("iconutil failed: \(task.terminationStatus)")
    exit(1)
}
