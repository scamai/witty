// Generates Witty's icon artwork: a four-leaf clover whose heart-shaped leaves sit in the
// four quadrants, so the gaps between them read as a 2x2 split of terminal panes, with a
// white ">_" prompt on the top-left leaf, on warm paper.
//
//   swift images/witty-icon-src/draw_clover.swift <output-dir>
//
// Writes:
//   witty-icon-preview.png  1024 px icon with its rounded-square background, the source of
//                           macos/Assets.xcassets/AppIconImage.imageset (in-app image)
//   Clover.png              the transparent clover layer for images/Ghostty.icon, scaled so
//                           it fills the Icon Composer canvas the way it fills the preview
//   clover-silhouette.png   white clover on transparent, placed where the ghost used to sit,
//                           for the tintable "custom" Dock icon (CustomIconGhost)
import AppKit

let size: CGFloat = 1024
let c = CGPoint(x: size / 2, y: size / 2)
let leafSize: CGFloat = 206     // L: the side of the diamond each heart leaf is built on
let gap: CGFloat = 24           // how far each leaf's tip sits from the centre

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

/// One heart-shaped leaf with its tip at the origin, growing along +y: a diamond plus two
/// circles, merged into one outline (CGPath.union needs macOS 14).
func leafPath(_ L: CGFloat) -> CGPath {
    let r2 = CGFloat(2).squareRoot()
    let diamond = CGMutablePath()
    diamond.move(to: .zero)
    diamond.addLine(to: CGPoint(x: -L / r2, y: L / r2))
    diamond.addLine(to: CGPoint(x: 0, y: r2 * L))
    diamond.addLine(to: CGPoint(x: L / r2, y: L / r2))
    diamond.closeSubpath()
    let cy = 3 * L / (2 * r2), cx = L / (2 * r2), rad = L / 2
    let left = CGPath(ellipseIn: CGRect(x: -cx - rad, y: cy - rad, width: 2 * rad, height: 2 * rad), transform: nil)
    let right = CGPath(ellipseIn: CGRect(x: cx - rad, y: cy - rad, width: 2 * rad, height: 2 * rad), transform: nil)
    return diamond.union(left).union(right)
}

/// The leaf pointing along `angle` (degrees; 45 is up-left in this y-up space).
func placedLeaf(_ angle: Double) -> CGPath {
    var t = CGAffineTransform(translationX: c.x, y: c.y)
        .rotated(by: CGFloat(angle) * .pi / 180)
        .translatedBy(x: 0, y: gap)
    return leafPath(leafSize).copy(using: &t)!
}

/// Area centroid of a path, by sampling a 2 px grid over its bounding box.
func centroid(_ path: CGPath) -> CGPoint {
    let b = path.boundingBoxOfPath
    var sx: CGFloat = 0, sy: CGFloat = 0, n: CGFloat = 0
    var y = b.minY
    while y <= b.maxY {
        var x = b.minX
        while x <= b.maxX {
            if path.contains(CGPoint(x: x, y: y)) { sx += x; sy += y; n += 1 }
            x += 2
        }
        y += 2
    }
    return CGPoint(x: sx / n, y: sy / n)
}

let angles = [45.0, 135.0, 225.0, 315.0]

/// The ">_" prompt, centred on the top-left leaf's centroid. Before stroking it spans
/// x in [px-44, px+78] and y in [py-38, py+38], so its box centre is (px+17, py).
func promptPath() -> CGPath {
    let centre = centroid(placedLeaf(45))
    let px = centre.x - 17, py = centre.y
    let p = CGMutablePath()
    p.move(to: CGPoint(x: px - 44, y: py + 38))
    p.addLine(to: CGPoint(x: px + 2, y: py))
    p.addLine(to: CGPoint(x: px - 44, y: py - 38))
    p.move(to: CGPoint(x: px + 26, y: py - 38))
    p.addLine(to: CGPoint(x: px + 78, y: py - 38))
    return p
}

func strokePrompt(_ ctx: CGContext, _ fill: CGColor) {
    ctx.saveGState()
    ctx.setStrokeColor(fill)
    ctx.setLineWidth(26)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.addPath(promptPath())
    ctx.strokePath()
    ctx.restoreGState()
}

/// The clover in colour: green gradient leaves, light at the outer edge, and the prompt.
func drawClover(_ ctx: CGContext) {
    let light: [UInt32] = [0x7CDB95, 0x72D68C, 0x6ACF85, 0x75D88F]
    for (i, angle) in angles.enumerated() {
        ctx.saveGState()
        ctx.addPath(placedLeaf(angle))
        ctx.clip()
        let grad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                              colors: [color(light[i]), color(0x2F9F5C)] as CFArray,
                              locations: [0, 1])!
        let rad = CGFloat(angle) * .pi / 180
        let dir = CGPoint(x: -sin(rad), y: cos(rad))   // the leaf's axis, pointing outward
        let outer = gap + 1.6 * leafSize
        ctx.drawLinearGradient(grad,
                               start: CGPoint(x: c.x + dir.x * outer, y: c.y + dir.y * outer),
                               end: CGPoint(x: c.x + dir.x * gap, y: c.y + dir.y * gap), options: [])
        ctx.restoreGState()
    }
    strokePrompt(ctx, color(0xFFFFFF))
}

func newContext() -> CGContext {
    CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpace(name: CGColorSpace.sRGB)!,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func write(_ ctx: CGContext, _ path: String) {
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}

/// Scale everything drawn after this by `k` about the centre.
func scaleAboutCentre(_ ctx: CGContext, _ k: CGFloat) {
    ctx.translateBy(x: c.x, y: c.y)
    ctx.scaleBy(x: k, y: k)
    ctx.translateBy(x: -c.x, y: -c.y)
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

// 1. Preview: macOS rounded square with the standard 100 px margin, warm paper, the clover.
do {
    let ctx = newContext()
    let squircle = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824),
                          cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x000000, 0.28))
    ctx.addPath(squircle)
    ctx.setFillColor(color(0xF3EBDB))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()
    let paper = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                           colors: [color(0xFBF7EE), color(0xEADFC9)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(paper, start: CGPoint(x: 0, y: 924), end: CGPoint(x: 0, y: 100), options: [])
    ctx.restoreGState()
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 22, color: color(0x1E5A35, 0.30))
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    drawClover(ctx)
    ctx.endTransparencyLayer()
    ctx.restoreGState()
    write(ctx, "\(out)/witty-icon-preview.png")
}

// 2. Icon Composer layer. The .icon canvas is the rounded square itself (1024 pt), while
//    the preview's square is 824 px, so scale by 1024/824 to keep the same proportions.
do {
    let ctx = newContext()
    scaleAboutCentre(ctx, size / 824)
    drawClover(ctx)
    write(ctx, "\(out)/Clover.png")
}

// 3. Tintable silhouette for the custom Dock icon: white leaves with the prompt cut out,
//    shrunk and moved to where upstream's ghost sat on the screen (centre ~(352, 378) from
//    the top-left, about 300 px across).
do {
    let ctx = newContext()
    ctx.translateBy(x: 352 - c.x, y: (size - 378) - c.y)
    scaleAboutCentre(ctx, 300 / 652)
    ctx.setFillColor(color(0xFFFFFF))
    for angle in angles {
        ctx.addPath(placedLeaf(angle))
    }
    ctx.fillPath()
    ctx.setBlendMode(.clear)
    strokePrompt(ctx, color(0xFFFFFF))
    write(ctx, "\(out)/clover-silhouette.png")
}
