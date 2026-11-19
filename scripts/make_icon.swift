import AppKit

let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

let iconsetURL = URL(fileURLWithPath: "Resources/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconsetURL)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

for (px, filename) in sizes {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: px,
        pixelsHigh: px,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: px, height: px)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let s = CGFloat(px)

    // Rounded squircle background
    let pad = s * 0.08
    let rect = CGRect(x: pad, y: pad, width: s - 2 * pad, height: s - 2 * pad)
    let path = NSBezierPath(roundedRect: rect, xRadius: s * 0.22, yRadius: s * 0.22)
    path.addClip()

    let colors = [
        NSColor(calibratedRed: 0.07, green: 0.16, blue: 0.36, alpha: 1.0).cgColor,
        NSColor(calibratedRed: 0.10, green: 0.44, blue: 0.85, alpha: 1.0).cgColor
    ] as CFArray
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: 0), end: CGPoint(x: s, y: s), options: [])

    // Pulse ECG waveform + subtle Vietnamese V badge
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.95).cgColor)
    ctx.setLineWidth(max(1.5, s * 0.065))
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.beginPath()
    ctx.move(to: CGPoint(x: s * 0.17, y: s * 0.46))
    ctx.addLine(to: CGPoint(x: s * 0.31, y: s * 0.46))
    ctx.addLine(to: CGPoint(x: s * 0.40, y: s * 0.67))
    ctx.addLine(to: CGPoint(x: s * 0.50, y: s * 0.26))
    ctx.addLine(to: CGPoint(x: s * 0.61, y: s * 0.74))
    ctx.addLine(to: CGPoint(x: s * 0.70, y: s * 0.46))
    ctx.addLine(to: CGPoint(x: s * 0.83, y: s * 0.46))
    ctx.strokePath()

    NSGraphicsContext.restoreGraphicsState()
    let data = rep.representation(using: .png, properties: [:])!
    try data.write(to: iconsetURL.appendingPathComponent(filename))
}
print("Generated iconset at \(iconsetURL.path)")
