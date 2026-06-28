#!/usr/bin/env swift

import AppKit
import Foundation

let outputURL: URL
if CommandLine.arguments.count > 1 {
    outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
} else {
    outputURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Resources/AppIcon.icon/Assets/icon-source.png")
}

try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)

let canvas = CGFloat(1024)
let image = NSImage(size: NSSize(width: canvas, height: canvas))
let zcodeSourceURL = outputURL.deletingLastPathComponent().appendingPathComponent("zcode-source.png")
guard let zcodeIcon = NSImage(contentsOf: zcodeSourceURL) else {
    throw NSError(domain: "AppIconGenerator", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing ZCode source icon at \(zcodeSourceURL.path)."])
}

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(displayP3Red: r, green: g, blue: b, alpha: a)
}

func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
    CGPoint(x: x, y: y)
}

func roundedPolygon(_ points: [CGPoint], radius: CGFloat) -> NSBezierPath {
    precondition(points.count >= 3)

    func normalize(_ vector: CGVector) -> CGVector {
        let length = sqrt(vector.dx * vector.dx + vector.dy * vector.dy)
        guard length > 0 else { return .zero }
        return CGVector(dx: vector.dx / length, dy: vector.dy / length)
    }

    func insetPoint(at index: Int, toward neighbor: CGPoint) -> CGPoint {
        let current = points[index]
        let direction = normalize(CGVector(dx: neighbor.x - current.x, dy: neighbor.y - current.y))
        return CGPoint(x: current.x + direction.dx * radius, y: current.y + direction.dy * radius)
    }

    let path = NSBezierPath()
    let last = points.count - 1
    path.move(to: insetPoint(at: 0, toward: points[last]))

    for index in points.indices {
        let previous = index == 0 ? last : index - 1
        let next = index == last ? 0 : index + 1
        let start = insetPoint(at: index, toward: points[previous])
        let end = insetPoint(at: index, toward: points[next])
        path.line(to: start)
        path.curve(to: end, controlPoint1: points[index], controlPoint2: points[index])
    }

    path.close()
    return path
}

func drawPath(
    _ path: NSBezierPath,
    gradient: NSGradient,
    angle: CGFloat,
    stroke: NSColor,
    lineWidth: CGFloat,
    shadow: NSShadow? = nil
) {
    NSGraphicsContext.saveGraphicsState()
    shadow?.set()
    gradient.draw(in: path, angle: angle)
    NSGraphicsContext.restoreGraphicsState()

    stroke.setStroke()
    path.lineWidth = lineWidth
    path.stroke()
}

func drawCircularArrow(center: CGPoint, radius: CGFloat, clockwise: Bool) {
    let badgeRect = NSRect(
        x: center.x - radius,
        y: center.y - radius,
        width: radius * 2,
        height: radius * 2
    )

    let badgeShadow = NSShadow()
    badgeShadow.shadowOffset = NSSize(width: 0, height: -8)
    badgeShadow.shadowBlurRadius = 18
    badgeShadow.shadowColor = color(0, 0, 0, 0.26)

    let badgePath = NSBezierPath(ovalIn: badgeRect)
    NSGraphicsContext.saveGraphicsState()
    badgeShadow.set()
    NSGradient(colors: [
        color(0.42, 0.70, 1, 0.90),
        color(0.18, 0.43, 0.92, 0.90)
    ])!.draw(in: badgePath, angle: clockwise ? 28 : -28)
    NSGraphicsContext.restoreGraphicsState()

    color(1, 1, 1, 0.55).setStroke()
    badgePath.lineWidth = 2
    badgePath.stroke()

    let arrowPath = NSBezierPath()
    arrowPath.lineWidth = 12
    arrowPath.lineCapStyle = .round
    arrowPath.lineJoinStyle = .round
    let arcRadius = radius * 0.48
    if clockwise {
        arrowPath.appendArc(
            withCenter: center,
            radius: arcRadius,
            startAngle: 138,
            endAngle: -142,
            clockwise: true
        )
    } else {
        arrowPath.appendArc(
            withCenter: center,
            radius: arcRadius,
            startAngle: 42,
            endAngle: 322,
            clockwise: false
        )
    }

    color(1, 1, 1, 0.94).setStroke()
    arrowPath.stroke()

    let head: [CGPoint]
    if clockwise {
        head = [
            point(center.x - arcRadius * 0.92, center.y + arcRadius * 0.22),
            point(center.x - arcRadius * 1.34, center.y + arcRadius * 0.18),
            point(center.x - arcRadius * 1.04, center.y - arcRadius * 0.14)
        ]
    } else {
        head = [
            point(center.x + arcRadius * 0.92, center.y + arcRadius * 0.22),
            point(center.x + arcRadius * 1.34, center.y + arcRadius * 0.18),
            point(center.x + arcRadius * 1.04, center.y - arcRadius * 0.14)
        ]
    }
    let headPath = roundedPolygon(head, radius: 4)
    color(1, 1, 1, 0.96).setFill()
    headPath.fill()
}

image.lockFocus()
NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: canvas, height: canvas).fill()
NSGraphicsContext.current?.imageInterpolation = .high
NSGraphicsContext.current?.shouldAntialias = true

let iconShadow = NSShadow()
iconShadow.shadowOffset = NSSize(width: 0, height: -22)
iconShadow.shadowBlurRadius = 42
iconShadow.shadowColor = color(0, 0, 0, 0.36)

let iconSize = CGFloat(456)
let iconRect = NSRect(
    x: (canvas - iconSize) / 2,
    y: (canvas - iconSize) / 2 + 6,
    width: iconSize,
    height: iconSize
)
NSGraphicsContext.saveGraphicsState()
iconShadow.set()
zcodeIcon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1)
NSGraphicsContext.restoreGraphicsState()

let glassRing = NSBezierPath(roundedRect: iconRect.insetBy(dx: 3, dy: 3), xRadius: 96, yRadius: 96)
color(1, 1, 1, 0.12).setStroke()
glassRing.lineWidth = 3
glassRing.stroke()

drawCircularArrow(center: point(376, 512), radius: 48, clockwise: false)
drawCircularArrow(center: point(648, 512), radius: 48, clockwise: true)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:])
else {
    throw NSError(domain: "AppIconGenerator", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not render app icon PNG."])
}

try png.write(to: outputURL, options: .atomic)
