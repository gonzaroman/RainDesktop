// Genera Resources/AppIcon.icns: lluvia que rebota en el borde de una ventana.
// Uso: swift Tools/make-icon.swift   (desde la raíz del proyecto)
import AppKit

let canvas: CGFloat = 1024
// Cuadrícula de iconos de macOS: placa de 824 pt centrada, esquinas de ~185 pt.
let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
let plateRadius: CGFloat = 185

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// Generador con semilla fija: el icono sale idéntico cada vez.
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

func drawIcon(in ctx: CGContext) {
    let platePath = CGPath(roundedRect: plate, cornerWidth: plateRadius, cornerHeight: plateRadius, transform: nil)

    // Sombra de la placa
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x000000, 0.35))
    ctx.addPath(platePath)
    ctx.setFillColor(color(0x1B1F4A))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(platePath)
    ctx.clip()

    // Cielo de tormenta
    let sky = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                         colors: [color(0x5B5FE0), color(0x2A2C7A), color(0x141638)] as CFArray,
                         locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(sky, start: CGPoint(x: 300, y: 924), end: CGPoint(x: 700, y: 100),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

    // Brillo de relámpago difuso arriba a la derecha
    let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                          colors: [color(0xC9D4FF, 0.35), color(0xC9D4FF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 760, y: 860), startRadius: 0,
                           endCenter: CGPoint(x: 760, y: 860), endRadius: 420, options: [])

    // Ventana
    let win = CGRect(x: 210, y: 170, width: 604, height: 420)
    let winRadius: CGFloat = 44
    let winPath = CGPath(roundedRect: win, cornerWidth: winRadius, cornerHeight: winRadius, transform: nil)

    // Lluvia de fondo (detrás de la ventana)
    var rng = SeededGenerator(state: 2026)
    let slope: CGFloat = 0.28
    ctx.setLineCap(.round)
    for i in 0..<70 {
        let x = CGFloat(i) * 13.7 + CGFloat.random(in: 0...20, using: &rng)
        let y = CGFloat.random(in: 120...980, using: &rng)
        let len = CGFloat.random(in: 50...95, using: &rng)
        let near = i % 3 != 0
        ctx.setStrokeColor(color(0xDCE6FF, near ? 0.55 : 0.28))
        ctx.setLineWidth(near ? 7 : 4)
        ctx.move(to: CGPoint(x: x, y: y))
        ctx.addLine(to: CGPoint(x: x - len * slope, y: y + len))
        ctx.strokePath()
    }

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 30, color: color(0x000000, 0.45))
    ctx.addPath(winPath)
    ctx.setFillColor(color(0xF4F6FF))
    ctx.fillPath()
    ctx.restoreGState()

    // Barra de título y contenido
    ctx.saveGState()
    ctx.addPath(winPath)
    ctx.clip()
    ctx.setFillColor(color(0xE2E6F8))
    ctx.fill(CGRect(x: win.minX, y: win.maxY - 84, width: win.width, height: 84))
    for (i, c) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() {
        ctx.setFillColor(color(UInt32(c)))
        ctx.fillEllipse(in: CGRect(x: win.minX + 40 + CGFloat(i) * 46, y: win.maxY - 58, width: 30, height: 30))
    }
    ctx.setFillColor(color(0xC9CFEA))
    for (i, w) in [380.0, 300.0, 430.0, 250.0].enumerated() {
        let r = CGRect(x: win.minX + 50, y: win.maxY - 150 - CGFloat(i) * 60, width: CGFloat(w), height: 26)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: 13, cornerHeight: 13, transform: nil))
        ctx.fillPath()
    }
    ctx.restoreGState()

    // Gotas que caen justo sobre las salpicaduras
    let water = color(0xEAF0FF, 0.95)
    let splashes: [CGFloat] = [440, 650]
    ctx.setStrokeColor(water)
    ctx.setLineWidth(10)
    for (i, cx) in splashes.enumerated() {
        let head = CGPoint(x: cx - 125 * slope, y: win.maxY + 125 + CGFloat(i) * 40)
        ctx.move(to: head)
        ctx.addLine(to: CGPoint(x: head.x - 110 * slope, y: head.y + 110))
        ctx.strokePath()
    }
    // Salpicaduras: corona de gotitas y anillo sobre el borde
    ctx.setFillColor(water)
    for cx in splashes {
        for (dx, dy, r) in [(-52.0, 26.0, 9.0), (-30.0, 56.0, 8.5), (-4.0, 70.0, 10.0), (24.0, 54.0, 8.5), (48.0, 24.0, 9.0)] {
            ctx.fillEllipse(in: CGRect(x: cx + dx - r, y: win.maxY + dy - r, width: r * 2, height: r * 2))
        }
        ctx.setStrokeColor(color(0xEAF0FF, 0.75))
        ctx.setLineWidth(5)
        ctx.strokeEllipse(in: CGRect(x: cx - 34, y: win.maxY - 2, width: 68, height: 14))
    }
    // Hilo de agua que baja por el lateral derecho
    ctx.setStrokeColor(color(0xEAF0FF, 0.6))
    ctx.setLineWidth(6)
    ctx.move(to: CGPoint(x: win.maxX + 4, y: win.maxY - 60))
    ctx.addLine(to: CGPoint(x: win.maxX + 4, y: win.maxY - 190))
    ctx.strokePath()
    ctx.setFillColor(water)
    ctx.fillEllipse(in: CGRect(x: win.maxX + 4 - 13, y: win.maxY - 225, width: 26, height: 36))

    ctx.restoreGState()

    // Filo de luz en la placa
    ctx.addPath(CGPath(roundedRect: plate.insetBy(dx: 1.5, dy: 1.5), cornerWidth: plateRadius - 1.5,
                       cornerHeight: plateRadius - 1.5, transform: nil))
    ctx.setStrokeColor(color(0xFFFFFF, 0.18))
    ctx.setLineWidth(3)
    ctx.strokePath()
}

func png(size: Int) -> Data {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: CGFloat(size) / canvas, y: CGFloat(size) / canvas)
    drawIcon(in: ctx)
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! png(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! png(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try! png(size: 1024).write(to: URL(fileURLWithPath: "Resources/AppIcon-preview.png"))

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try! task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "✓ Resources/AppIcon.icns" : "iconutil falló")
