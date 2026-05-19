#!/usr/bin/env swift
import CoreGraphics
import Foundation
import ImageIO

let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/readpic_mem_test.jpg"
let url = URL(fileURLWithPath: path)

let cs = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(
    data: nil, width: 1920, height: 1080,
    bitsPerComponent: 8, bytesPerRow: 1920 * 4,
    space: cs,
    bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
)!
ctx.setFillColor(red: 0.3, green: 0.5, blue: 0.8, alpha: 1)
ctx.fill(CGRect(x: 0, y: 0, width: 1920, height: 1080))
let gradient = CGGradient(
    colorsSpace: cs,
    colors: [CGColor(red: 0.1, green: 0.2, blue: 0.8, alpha: 1),
             CGColor(red: 0.9, green: 0.3, blue: 0.1, alpha: 1)] as CFArray,
    locations: [0, 1.0]
)!
ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 1920, y: 1080), options: [])

let img = ctx.makeImage()!
guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil) else {
    print("ERROR: Cannot create destination")
    exit(1)
}
let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.9]
CGImageDestinationAddImage(dest, img, options as CFDictionary)
guard CGImageDestinationFinalize(dest) else {
    print("ERROR: Failed to write JPEG")
    exit(1)
}
print("OK: \(url.path)  (\(1920)x\(1080))")
