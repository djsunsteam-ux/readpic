#!/usr/bin/env swift
import CoreGraphics
import Foundation
import ImageIO

let count = Int(CommandLine.arguments[1]) ?? 1000
let dirPath = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "/tmp/readpic_test_\(count)"
let dirURL = URL(fileURLWithPath: dirPath, isDirectory: true)

try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)

let cs = CGColorSpaceCreateDeviceRGB()
let startTime = CFAbsoluteTimeGetCurrent()

for i in 0..<count {
    let ext = ["jpg", "png"][i % 2]
    let url = dirURL.appendingPathComponent("img_\(i).\(ext)")
    let ctx = CGContext(
        data: nil, width: 1, height: 1,
        bitsPerComponent: 8, bytesPerRow: 4,
        space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
    )!
    ctx.setFillColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
    let img = ctx.makeImage()!

    let utType = ext == "png" ? "public.png" as CFString : "public.jpeg" as CFString
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, utType, 1, nil) else { continue }
    CGImageDestinationAddImage(dest, img, nil)
    CGImageDestinationFinalize(dest)
}

let elapsed = CFAbsoluteTimeGetCurrent() - startTime
print("Created \(count) images in \(dirPath)")
print("Time: \(String(format: "%.1f", elapsed))s")
