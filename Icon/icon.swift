import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "AppIcon.iconset")
let sourceURL = URL(fileURLWithPath: "Icon/byte-logo.png")
guard let source = NSImage(contentsOf: sourceURL) else {
    fputs("could not read \(sourceURL.path)\n", stderr)
    exit(1)
}

try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func render(_ pixels: Int) -> NSImage {
    let image = NSImage(size: NSSize(width: pixels, height: pixels))
    image.lockFocus()
    defer { image.unlockFocus() }
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: pixels, height: pixels).fill()
    source.draw(
        in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
        from: NSRect(origin: .zero, size: source.size),
        operation: .copy,
        fraction: 1,
        respectFlipped: true,
        hints: [.interpolation: NSImageInterpolation.high]
    )
    return image
}

func write(_ image: NSImage, to url: URL, pixels: Int) {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: url)
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let suffix = scale == 1 ? "" : "@2x"
        write(render(pixels), to: output.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"), pixels: pixels)
    }
}
print("drew: \(output.path)")
