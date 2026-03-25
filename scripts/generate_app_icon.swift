import AppKit
import Foundation

let root = URL(fileURLWithPath: "/Users/manqingguo/Documents/New project/CommodityPulse/Resources/Assets.xcassets/AppIcon.appiconset")
let source = root.appendingPathComponent("Icon-1024.png")

let imageSize = CGSize(width: 1024, height: 1024)
let image = NSImage(size: imageSize)
image.lockFocus()

let rect = NSRect(origin: .zero, size: imageSize)
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.04, green: 0.08, blue: 0.16, alpha: 1),
    NSColor(calibratedRed: 0.13, green: 0.26, blue: 0.44, alpha: 1),
    NSColor(calibratedRed: 0.98, green: 0.73, blue: 0.19, alpha: 1)
])!
gradient.draw(in: NSBezierPath(roundedRect: rect, xRadius: 220, yRadius: 220), angle: -55)

NSColor(calibratedWhite: 1.0, alpha: 0.08).setFill()
NSBezierPath(ovalIn: NSRect(x: 120, y: 590, width: 320, height: 320)).fill()
NSBezierPath(ovalIn: NSRect(x: 630, y: 180, width: 240, height: 240)).fill()

let lineColor = NSColor(calibratedRed: 0.97, green: 0.98, blue: 1.0, alpha: 0.95)
lineColor.setStroke()

let chart = NSBezierPath()
chart.lineWidth = 52
chart.lineCapStyle = .round
chart.lineJoinStyle = .round
chart.move(to: NSPoint(x: 170, y: 280))
chart.line(to: NSPoint(x: 340, y: 420))
chart.line(to: NSPoint(x: 470, y: 380))
chart.line(to: NSPoint(x: 610, y: 560))
chart.line(to: NSPoint(x: 840, y: 700))
chart.stroke()

let arrow = NSBezierPath()
arrow.lineWidth = 52
arrow.lineCapStyle = .round
arrow.move(to: NSPoint(x: 760, y: 700))
arrow.line(to: NSPoint(x: 840, y: 700))
arrow.line(to: NSPoint(x: 840, y: 620))
arrow.stroke()

let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .left
let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 180, weight: .black),
    .foregroundColor: NSColor.white,
    .paragraphStyle: paragraph
]
NSString(string: "CP").draw(in: NSRect(x: 138, y: 82, width: 420, height: 220), withAttributes: attributes)

image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
let pngData = bitmap.representation(using: .png, properties: [:])!
try pngData.write(to: source)
