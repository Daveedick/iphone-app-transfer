import AppKit

let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()
let surface = NSBezierPath(roundedRect: NSRect(x: 24, y: 24, width: 976, height: 976), xRadius: 214, yRadius: 214)
NSGradient(starting: NSColor(calibratedRed: 0.16, green: 0.19, blue: 0.24, alpha: 1), ending: NSColor(calibratedRed: 0.055, green: 0.07, blue: 0.095, alpha: 1))!.draw(in: surface, angle: -90)
for rect in [NSRect(x: 215, y: 240, width: 250, height: 544), NSRect(x: 560, y: 240, width: 250, height: 544)] {
    let outline = NSBezierPath(roundedRect: rect, xRadius: 47, yRadius: 47)
    outline.lineWidth = 19
    NSColor(calibratedWhite: 0.94, alpha: 0.94).setStroke()
    outline.stroke()
    let home = NSBezierPath(roundedRect: NSRect(x: rect.midX - 41, y: rect.minY + 27, width: 82, height: 9), xRadius: 4.5, yRadius: 4.5)
    NSColor(calibratedWhite: 0.94, alpha: 0.7).setFill(); home.fill()
}
let bridge = NSBezierPath(roundedRect: NSRect(x: 364, y: 415, width: 300, height: 178), xRadius: 48, yRadius: 48)
NSColor(calibratedRed: 0.39, green: 0.57, blue: 0.99, alpha: 1).setFill(); bridge.fill()
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 424, y: 504)); arrow.line(to: NSPoint(x: 602, y: 504))
arrow.move(to: NSPoint(x: 548, y: 557)); arrow.line(to: NSPoint(x: 602, y: 504)); arrow.line(to: NSPoint(x: 548, y: 451))
arrow.lineWidth = 20; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
NSColor.white.setStroke(); arrow.stroke()
image.unlockFocus()
let representation = NSBitmapImageRep(data: image.tiffRepresentation!)!
let png = representation.representation(using: .png, properties: [:])!
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
