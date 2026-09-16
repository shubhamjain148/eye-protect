// Generates Resources/AppIcon.icns: an eye glyph on a calm teal gradient.
// Run: swift scripts/make-icon.swift   (re-run only when changing the icon)
import AppKit

func render(size: Int) -> NSImage {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()
    let inset = s * 0.05                                  // macOS icons leave a margin
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let path = NSBezierPath(roundedRect: rect, xRadius: s * 0.22, yRadius: s * 0.22)
    NSGradient(starting: NSColor(calibratedRed: 0.09, green: 0.55, blue: 0.55, alpha: 1),
               ending:   NSColor(calibratedRed: 0.03, green: 0.25, blue: 0.32, alpha: 1))!
        .draw(in: path, angle: -70)
    let config = NSImage.SymbolConfiguration(pointSize: s * 0.5, weight: .medium)
    if let glyph = NSImage(systemSymbolName: "eye.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let tinted = NSImage(size: glyph.size, flipped: false) { r in
            glyph.draw(in: r); NSColor.white.set(); r.fill(using: .sourceAtop); return true
        }
        let g = tinted.size
        tinted.draw(in: NSRect(x: (s - g.width) / 2, y: (s - g.height) / 2, width: g.width, height: g.height))
    }
    image.unlockFocus()
    return image
}

let out = "Resources/AppIcon.iconset"
try? FileManager.default.removeItem(atPath: out)
try! FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for (name, px) in [("16x16",16),("16x16@2x",32),("32x32",32),("32x32@2x",64),("128x128",128),
                   ("128x128@2x",256),("256x256",256),("256x256@2x",512),("512x512",512),("512x512@2x",1024)] {
    let img = render(size: px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    img.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
}
let task = Process()
task.launchPath = "/usr/bin/iconutil"
task.arguments = ["-c", "icns", out, "-o", "Resources/AppIcon.icns"]
task.launch(); task.waitUntilExit()
try? FileManager.default.removeItem(atPath: out)
print(task.terminationStatus == 0 ? "wrote Resources/AppIcon.icns" : "iconutil failed")
