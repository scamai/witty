// Generates Witty's icon artwork: a four-leaf clover whose heart-shaped leaves sit in the
// four quadrants, so the gaps between them read as a 2x2 split of terminal panes, with a
// white ">_" prompt on the top-left leaf, on warm paper.
//
//   swift images/witty-icon-src/draw_clover.swift <output-dir>
//
// Writes:
//   witty-icon-preview.png  1024 px icon with its rounded-square background, the source of
//                           macos/Assets.xcassets/AppIconImage.imageset (in-app image)
//   Clover-leaves.png       the clover's leaves with the prompt cut out, and
//   Clover-prompt.png       the white prompt alone: the two layers of images/Ghostty.icon,
//                           scaled to fill the Icon Composer canvas as the clover fills the preview
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

// 2. Icon Composer layers. The .icon canvas is the rounded square itself (1024 pt), while
//    the preview's square is 824 px, so both layers are scaled by 1024/824 to keep the same
//    proportions. The leaves carry the prompt as a cut-out, and the prompt is its own white
//    layer on top. Default and dark show both, so nothing changes; the monochrome (clear and
//    tinted) appearances hide the prompt layer, and the cut-out reads instead of a white
//    stroke that would vanish against pale glass.
do {
    let leaves = newContext()
    scaleAboutCentre(leaves, size / 824)
    drawClover(leaves)
    leaves.setBlendMode(.clear)
    strokePrompt(leaves, color(0xFFFFFF))
    write(leaves, "\(out)/Clover-leaves.png")

    let prompt = newContext()
    scaleAboutCentre(prompt, size / 824)
    strokePrompt(prompt, color(0xFFFFFF))
    write(prompt, "\(out)/Clover-prompt.png")
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

// ─── 4. Alternate icons ─────────────────────────────────────────────────────────────────
// `macos-icon = blueprint | chalkboard | glass | holographic | microchip | paper | retro |
// xray` picks one of these. Each is a full 1024 px icon in the legacy layout (824 px rounded
// square, 100 px margin), written as <Name>Image.png for
// macos/Assets.xcassets/Alternate Icons/<Name>Image.imageset/macOS-AppIcon-1024px.png.
// They keep upstream's theme names, so the config values and the code are unchanged.

let squircleRect = CGRect(x: 100, y: 100, width: 824, height: 824)
let squircle = CGPath(roundedRect: squircleRect, cornerWidth: 185, cornerHeight: 185, transform: nil)
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func gradient(_ hexes: [UInt32], _ alphas: [CGFloat]? = nil) -> CGGradient {
    let cols = hexes.enumerated().map { color($0.element, alphas?[$0.offset] ?? 1) }
    return CGGradient(colorsSpace: sRGB, colors: cols as CFArray, locations: nil)!
}

func verticalGradient(_ ctx: CGContext, _ g: CGGradient) {
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 924), end: CGPoint(x: 0, y: 100), options: [])
}

/// The icon's outer shadow, then `paint` clipped to the rounded square.
func iconBase(_ ctx: CGContext, _ paint: (CGContext) -> Void) {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x000000, 0.28))
    ctx.addPath(squircle)
    ctx.setFillColor(color(0x808080))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()
    paint(ctx)
    ctx.restoreGState()
}

/// All four leaves as one path.
func cloverPath() -> CGPath {
    let p = CGMutablePath()
    for a in angles { p.addPath(placedLeaf(a)) }
    return p
}

/// A leaf scaled about its own centroid: inner traces and bands.
func insetLeaf(_ angle: Double, _ k: CGFloat) -> CGPath {
    let leaf = placedLeaf(angle)
    let m = centroid(leaf)
    var t = CGAffineTransform(translationX: m.x, y: m.y).scaledBy(x: k, y: k).translatedBy(x: -m.x, y: -m.y)
    return leaf.copy(using: &t)!
}

/// The prompt as a filled outline, for pixel art.
func promptOutline() -> CGPath {
    promptPath().copy(strokingWithWidth: 26, lineCap: .round, lineJoin: .round, miterLimit: 10)
}

/// Deterministic pseudo-random numbers, so every run draws the same texture.
struct Rand {
    var s: UInt64
    mutating func next() -> CGFloat {
        s = s &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat((s >> 33) & 0xFFFFFF) / CGFloat(0xFFFFFF)
    }
}

/// The leaf's axis, pointing outward, and the gradient end points along it.
func leafAxis(_ angle: Double) -> (outer: CGPoint, inner: CGPoint) {
    let rad = CGFloat(angle) * .pi / 180
    let dir = CGPoint(x: -sin(rad), y: cos(rad))
    let outer = gap + 1.6 * leafSize
    return (CGPoint(x: c.x + dir.x * outer, y: c.y + dir.y * outer),
            CGPoint(x: c.x + dir.x * gap, y: c.y + dir.y * gap))
}

/// Blueprint: white line drawing over a technical grid.
func drawBlueprint(_ ctx: CGContext) {
    iconBase(ctx) { ctx in
        verticalGradient(ctx, gradient([0x3A86F0, 0x1F5FD0]))
        for (step, alpha, width) in [(CGFloat(32), CGFloat(0.10), CGFloat(1.5)), (128, 0.22, 2.5)] {
            ctx.setStrokeColor(color(0xFFFFFF, alpha))
            ctx.setLineWidth(width)
            var v: CGFloat = 100
            while v <= 924 {
                ctx.move(to: CGPoint(x: v, y: 100)); ctx.addLine(to: CGPoint(x: v, y: 924))
                ctx.move(to: CGPoint(x: 100, y: v)); ctx.addLine(to: CGPoint(x: 924, y: v))
                v += step
            }
            ctx.strokePath()
        }
        ctx.setStrokeColor(color(0xFFFFFF, 0.28))
        ctx.setLineWidth(3)
        ctx.addEllipse(in: CGRect(x: c.x - 360, y: c.y - 360, width: 720, height: 720))
        ctx.move(to: CGPoint(x: 160, y: 160)); ctx.addLine(to: CGPoint(x: 864, y: 864))
        ctx.move(to: CGPoint(x: 160, y: 864)); ctx.addLine(to: CGPoint(x: 864, y: 160))
        ctx.strokePath()
        ctx.addPath(cloverPath())
        ctx.setFillColor(color(0xFFFFFF, 0.12))
        ctx.fillPath()
        ctx.addPath(cloverPath())
        ctx.setStrokeColor(color(0xFFFFFF))
        ctx.setLineWidth(10)
        ctx.setLineJoin(.round)
        ctx.strokePath()
        strokePrompt(ctx, color(0xFFFFFF))
    }
}

/// Chalkboard: a chalk sketch on slate, in a wooden frame.
func drawChalkboard(_ ctx: CGContext) {
    var r = Rand(s: 7)
    iconBase(ctx) { ctx in
        verticalGradient(ctx, gradient([0xC08A52, 0x8C5A2C]))
        for _ in 0..<60 {
            let y = 100 + r.next() * 824
            ctx.setStrokeColor(color(0x5E3A1A, 0.10 + 0.10 * r.next()))
            ctx.setLineWidth(2 + 3 * r.next())
            ctx.move(to: CGPoint(x: 100, y: y))
            ctx.addCurve(to: CGPoint(x: 924, y: y + (r.next() - 0.5) * 30),
                         control1: CGPoint(x: 380, y: y + (r.next() - 0.5) * 40),
                         control2: CGPoint(x: 650, y: y + (r.next() - 0.5) * 40))
            ctx.strokePath()
        }
        let board = CGPath(roundedRect: squircleRect.insetBy(dx: 58, dy: 58), cornerWidth: 132, cornerHeight: 132, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 10, color: color(0x000000, 0.45))
        ctx.addPath(board)
        ctx.setFillColor(color(0x26302B))
        ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(board)
        ctx.clip()
        verticalGradient(ctx, gradient([0x34413A, 0x222B26]))
        for _ in 0..<1400 {
            let x = 158 + r.next() * 708, y = 158 + r.next() * 708
            ctx.setFillColor(color(0xFFFFFF, 0.02 + 0.04 * r.next()))
            ctx.fillEllipse(in: CGRect(x: x, y: y, width: 2 + 3 * r.next(), height: 2 + 3 * r.next()))
        }
        ctx.saveGState()
        scaleAboutCentre(ctx, 0.86)
        ctx.addPath(cloverPath())
        ctx.setFillColor(color(0xE8F5EC, 0.16))
        ctx.fillPath()
        for pass in 0..<10 {
            var t = CGAffineTransform(translationX: (r.next() - 0.5) * 7, y: (r.next() - 0.5) * 7)
            ctx.addPath(cloverPath().copy(using: &t)!)
            ctx.setStrokeColor(color(pass % 2 == 0 ? 0xF4F7F2 : 0xCDEBD6, 0.30))
            ctx.setLineWidth(10 + 6 * r.next())
            ctx.setLineJoin(.round)
            ctx.strokePath()
        }
        let edge = cloverPath().copy(strokingWithWidth: 26, lineCap: .round, lineJoin: .round, miterLimit: 10)
        for _ in 0..<5000 {
            let pt = CGPoint(x: 186 + r.next() * 652, y: 186 + r.next() * 652)
            if edge.contains(pt) {
                ctx.setFillColor(color(0xFFFFFF, 0.10 + 0.25 * r.next()))
                ctx.fillEllipse(in: CGRect(x: pt.x, y: pt.y, width: 2 + 2 * r.next(), height: 2 + 2 * r.next()))
            }
        }
        for _ in 0..<4 {
            ctx.saveGState()
            ctx.translateBy(x: (r.next() - 0.5) * 4, y: (r.next() - 0.5) * 4)
            strokePrompt(ctx, color(0xF8FBF6, 0.75))
            ctx.restoreGState()
        }
        ctx.restoreGState()
        ctx.restoreGState()
    }
}

/// Glass: frosted leaves over soft colour, in the Liquid Glass manner.
func drawGlass(_ ctx: CGContext) {
    iconBase(ctx) { ctx in
        ctx.drawLinearGradient(gradient([0xDDF5EA, 0xD3E6FB, 0xE6DCF8]),
                               start: CGPoint(x: 100, y: 924), end: CGPoint(x: 924, y: 100), options: [])
        for (x, y, rad, hex) in [(CGFloat(300), CGFloat(700), CGFloat(300), UInt32(0x8FE3B5)),
                                 (720, 330, 340, 0x9CC8FF), (700, 760, 240, 0xF3B8E6)] {
            let g = CGGradient(colorsSpace: sRGB, colors: [color(hex, 0.75), color(hex, 0)] as CFArray, locations: [0, 1])!
            ctx.drawRadialGradient(g, startCenter: CGPoint(x: x, y: y), startRadius: 0,
                                   endCenter: CGPoint(x: x, y: y), endRadius: rad, options: [])
        }
        for a in angles {
            let leaf = placedLeaf(a)
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 26, color: color(0x2A5A7A, 0.18))
            ctx.addPath(leaf)
            ctx.setFillColor(color(0xFFFFFF, 0.34))
            ctx.fillPath()
            ctx.restoreGState()
            ctx.saveGState()
            ctx.addPath(leaf)
            ctx.clip()
            let axis = leafAxis(a)
            ctx.drawLinearGradient(gradient([0xFFFFFF, 0xFFFFFF], [0.55, 0.05]), start: axis.outer, end: axis.inner, options: [])
            ctx.restoreGState()
            ctx.addPath(leaf)
            ctx.setStrokeColor(color(0xFFFFFF, 0.9))
            ctx.setLineWidth(4)
            ctx.strokePath()
        }
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 6, color: color(0xFFFFFF, 0.8))
        strokePrompt(ctx, color(0x3A6F86))
        ctx.restoreGState()
    }
}

/// Holographic: iridescent leaves over a synthwave horizon.
func drawHolographic(_ ctx: CGContext) {
    iconBase(ctx) { ctx in
        verticalGradient(ctx, gradient([0xFF5BD6, 0x9A3BF0, 0x3B1C8C]))
        let horizon: CGFloat = 400
        ctx.setStrokeColor(color(0x7DF9FF, 0.55))
        ctx.setLineWidth(3)
        var y = horizon, step: CGFloat = 18
        while y > 100 {
            ctx.move(to: CGPoint(x: 100, y: y)); ctx.addLine(to: CGPoint(x: 924, y: y))
            y -= step; step *= 1.22
        }
        for i in -8...8 {
            ctx.move(to: CGPoint(x: c.x + CGFloat(i) * 14, y: horizon))
            ctx.addLine(to: CGPoint(x: c.x + CGFloat(i) * 130, y: 100))
        }
        ctx.strokePath()
        let iri: [UInt32] = [0xFFFFFF, 0xB9F6FF, 0xFFB8F0, 0xFFF6B0, 0xC8B8FF]
        for (i, a) in angles.enumerated() {
            let leaf = placedLeaf(a)
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x2B0B5A, 0.45))
            ctx.addPath(leaf)
            ctx.setFillColor(color(0xFFFFFF))
            ctx.fillPath()
            ctx.restoreGState()
            ctx.saveGState()
            ctx.addPath(leaf)
            ctx.clip()
            let rad = (CGFloat(a) + CGFloat(i) * 25) * .pi / 180
            let d = CGPoint(x: cos(rad) * 340, y: sin(rad) * 340)
            ctx.drawLinearGradient(gradient(iri), start: CGPoint(x: c.x - d.x, y: c.y - d.y),
                                   end: CGPoint(x: c.x + d.x, y: c.y + d.y),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            ctx.restoreGState()
            ctx.addPath(leaf)
            ctx.setStrokeColor(color(0xFFFFFF, 0.7))
            ctx.setLineWidth(3)
            ctx.strokePath()
        }
        strokePrompt(ctx, color(0x3B1C8C))
    }
}

/// Microchip: gold leaves on a circuit board, joined by a chip at the crossing.
func drawMicrochip(_ ctx: CGContext) {
    var r = Rand(s: 11)
    iconBase(ctx) { ctx in
        verticalGradient(ctx, gradient([0x157A43, 0x0B4D29]))
        ctx.setLineWidth(7)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        for _ in 0..<26 {
            var p = CGPoint(x: 120 + r.next() * 784, y: 120 + r.next() * 784)
            ctx.setStrokeColor(color(0x3DC97A, 0.45))
            ctx.move(to: p)
            for _ in 0..<3 {
                if r.next() < 0.5 { p.x += (r.next() - 0.5) * 300 } else { p.y += (r.next() - 0.5) * 300 }
                ctx.addLine(to: p)
            }
            ctx.strokePath()
            ctx.setFillColor(color(0x3DC97A, 0.6))
            ctx.fillEllipse(in: CGRect(x: p.x - 9, y: p.y - 9, width: 18, height: 18))
        }
        for a in angles {
            let leaf = placedLeaf(a)
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: color(0x02200F, 0.6))
            ctx.addPath(leaf)
            ctx.setFillColor(color(0xD9A947))
            ctx.fillPath()
            ctx.restoreGState()
            ctx.saveGState()
            ctx.addPath(leaf)
            ctx.clip()
            verticalGradient(ctx, gradient([0xF7D27A, 0xB8862E]))
            ctx.restoreGState()
            ctx.addPath(leaf)
            ctx.setStrokeColor(color(0x8C6420))
            ctx.setLineWidth(5)
            ctx.strokePath()
            ctx.addPath(insetLeaf(a, 0.74))
            ctx.setStrokeColor(color(0xFFE7A6, 0.85))
            ctx.setLineWidth(4)
            ctx.strokePath()
        }
        let chip = CGRect(x: c.x - 44, y: c.y - 44, width: 88, height: 88)
        ctx.setFillColor(color(0xC9A24A))
        for i in 0..<3 {
            let o = CGFloat(i) * 24 - 24
            ctx.fill(CGRect(x: chip.minX - 14, y: c.y + o - 4, width: 14, height: 8))
            ctx.fill(CGRect(x: chip.maxX, y: c.y + o - 4, width: 14, height: 8))
            ctx.fill(CGRect(x: c.x + o - 4, y: chip.minY - 14, width: 8, height: 14))
            ctx.fill(CGRect(x: c.x + o - 4, y: chip.maxY, width: 8, height: 14))
        }
        ctx.addPath(CGPath(roundedRect: chip, cornerWidth: 10, cornerHeight: 10, transform: nil))
        ctx.setFillColor(color(0x1C1F1D))
        ctx.fillPath()
        strokePrompt(ctx, color(0x1C1F1D))
    }
}

/// Paper: a marker drawing on ruled notebook paper.
func drawNotebookPaper(_ ctx: CGContext) {
    iconBase(ctx) { ctx in
        verticalGradient(ctx, gradient([0xFFFFFF, 0xF4EEE2]))
        ctx.setStrokeColor(color(0x9CC3E6, 0.75))
        ctx.setLineWidth(3)
        var y: CGFloat = 860
        while y > 120 {
            ctx.move(to: CGPoint(x: 100, y: y)); ctx.addLine(to: CGPoint(x: 924, y: y))
            y -= 58
        }
        ctx.strokePath()
        ctx.setStrokeColor(color(0xE58C8C, 0.85))
        ctx.move(to: CGPoint(x: 210, y: 100)); ctx.addLine(to: CGPoint(x: 210, y: 924))
        ctx.strokePath()
        for a in angles {
            let leaf = placedLeaf(a)
            ctx.addPath(leaf)
            ctx.setFillColor(color(0x46B06E, 0.92))
            ctx.fillPath()
            ctx.addPath(leaf)
            ctx.setStrokeColor(color(0x2A8A4F))
            ctx.setLineWidth(6)
            ctx.strokePath()
        }
        strokePrompt(ctx, color(0xFFFFFF))
    }
}

/// Retro: a pixel clover glowing on a scanlined CRT, the prompt as dark pixels.
func drawRetro(_ ctx: CGContext) {
    iconBase(ctx) { ctx in
        verticalGradient(ctx, gradient([0x16261C, 0x0A130E]))
        let cell: CGFloat = 24
        let clover = cloverPath(), prompt = promptOutline()
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 22, color: color(0x39FF88, 0.85))
        ctx.setFillColor(color(0x39FF88))
        var y = c.y - 19 * cell
        while y < c.y + 19 * cell {
            var x = c.x - 19 * cell
            while x < c.x + 19 * cell {
                let mid = CGPoint(x: x + cell / 2, y: y + cell / 2)
                if clover.contains(mid) && !prompt.contains(mid) {
                    ctx.fill(CGRect(x: x + 2, y: y + 2, width: cell - 4, height: cell - 4))
                }
                x += cell
            }
            y += cell
        }
        ctx.restoreGState()
        ctx.setFillColor(color(0x000000, 0.28))
        var s: CGFloat = 100
        while s < 924 { ctx.fill(CGRect(x: 100, y: s, width: 824, height: 3)); s += 7 }
        let vignette = CGGradient(colorsSpace: sRGB, colors: [color(0x000000, 0), color(0x000000, 0.55)] as CFArray,
                                  locations: [0.55, 1])!
        ctx.drawRadialGradient(vignette, startCenter: c, startRadius: 0, endCenter: c, endRadius: 600,
                               options: [.drawsAfterEndLocation])
    }
}

/// X-ray: glowing leaf outlines with their veins showing.
func drawXray(_ ctx: CGContext) {
    iconBase(ctx) { ctx in
        verticalGradient(ctx, gradient([0x0C1626, 0x050A12]))
        let glow = CGGradient(colorsSpace: sRGB, colors: [color(0x1D4E66, 0.65), color(0x1D4E66, 0)] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(glow, startCenter: c, startRadius: 0, endCenter: c, endRadius: 460, options: [])
        for a in angles {
            let leaf = placedLeaf(a)
            ctx.addPath(leaf)
            ctx.setFillColor(color(0x7FE7FF, 0.10))
            ctx.fillPath()
            ctx.saveGState()
            ctx.addPath(leaf)
            ctx.clip()
            ctx.translateBy(x: c.x, y: c.y)
            ctx.rotate(by: CGFloat(a) * .pi / 180)
            ctx.translateBy(x: 0, y: gap)
            let L = leafSize, top = CGFloat(2).squareRoot() * L * 0.92
            ctx.setStrokeColor(color(0xA8F2FF, 0.55))
            ctx.setLineWidth(4)
            ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: 0, y: 8)); ctx.addLine(to: CGPoint(x: 0, y: top))
            for k in 1...3 {
                let y0 = top * CGFloat(k) / 4.2, span = L * (0.30 + 0.10 * CGFloat(k))
                ctx.move(to: CGPoint(x: 0, y: y0))
                ctx.addQuadCurve(to: CGPoint(x: -span, y: y0 + span * 0.55), control: CGPoint(x: -span * 0.35, y: y0 + span * 0.10))
                ctx.move(to: CGPoint(x: 0, y: y0))
                ctx.addQuadCurve(to: CGPoint(x: span, y: y0 + span * 0.55), control: CGPoint(x: span * 0.35, y: y0 + span * 0.10))
            }
            ctx.strokePath()
            ctx.restoreGState()
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: 22, color: color(0x7FE7FF, 0.9))
            ctx.addPath(leaf)
            ctx.setStrokeColor(color(0xBFF6FF))
            ctx.setLineWidth(6)
            ctx.strokePath()
            ctx.restoreGState()
        }
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 16, color: color(0x7FE7FF, 0.9))
        strokePrompt(ctx, color(0xFFFFFF))
        ctx.restoreGState()
    }
}

for (name, draw) in [("Blueprint", drawBlueprint), ("Chalkboard", drawChalkboard), ("Glass", drawGlass),
                     ("Holographic", drawHolographic), ("Microchip", drawMicrochip), ("Paper", drawNotebookPaper),
                     ("Retro", drawRetro), ("Xray", drawXray)] as [(String, (CGContext) -> Void)] {
    let ctx = newContext()
    draw(ctx)
    write(ctx, "\(out)/\(name)Image.png")
}
