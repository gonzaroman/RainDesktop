import AppKit
import CoreGraphics

/// Obtiene los rects de las ventanas visibles para que la lluvia choque con ellas.
/// Usa CGWindowList (origen arriba-izq) y los convierte a coords Cocoa globales (origen abajo-izq).
class WindowListProvider {
    var onUpdate: (([CGRect]) -> Void)?
    private var timer: Timer?
    private var lastSignature = ""

    private let skipOwners = ["Dock", "SystemUIServer", "NotificationCenter", "ControlCenter", "WindowManager", "loginwindow"]

    func start() {
        stop()
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            self?.poll()
        }
        if let t = timer {
            RunLoop.current.add(t, forMode: .common)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        guard let rawList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return
        }
        // Quartz origen arriba-izq de la pantalla principal -> Cocoa global origen abajo-izq.
        // Usar la pantalla principal (no screens.first) para multimonitor.
        let primary = NSScreen.main ?? NSScreen.screens.first
        let primaryTop = (primary?.frame.origin.y ?? 0) + (primary?.frame.height ?? 900)

        var rects: [CGRect] = []
        for info in rawList {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let alpha = info[kCGWindowAlpha as String] as? Double, alpha > 0.1 else { continue }
            let owner = info[kCGWindowOwnerName as String] as? String ?? ""
            if owner == "RainDesktop" { continue }
            if skipOwners.contains(owner) { continue }
            if owner == "Finder" {
                // El escritorio del Finder ocupa toda la pantalla: ignorarlo
                if let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                   let w = boundsDict["Width"] as? CGFloat, w > 1000 {
                    continue
                }
            }
            guard let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let x = boundsDict["X"] as? CGFloat,
                  let yQuartz = boundsDict["Y"] as? CGFloat,
                  let w = boundsDict["Width"] as? CGFloat,
                  let h = boundsDict["Height"] as? CGFloat else { continue }
            if w < 60 || h < 40 { continue }

            // Quartz (arriba-izq) -> Cocoa global (abajo-izq)
            let yCocoa = primaryTop - yQuartz - h
            var rect = CGRect(x: x, y: yCocoa, width: w, height: h)

            // Quita sombra aproximada
            rect = rect.insetBy(dx: 10, dy: 8)
            if rect.width < 40 || rect.height < 25 { continue }

            // Ignora rects del tamaño de una pantalla completa (fondos)
            var isFullscreen = false
            for screen in NSScreen.screens {
                if abs(rect.width - screen.frame.width) < 30 && abs(rect.height - screen.frame.height) < 30 {
                    isFullscreen = true
                    break
                }
            }
            if isFullscreen { continue }

            rects.append(rect)
            if rects.count >= 20 { break }
        }

        // Evita spamear updates idénticos
        let sig = rects.map { "\($0.minX.rounded())-($0.minY.rounded())-\($0.width.rounded())-\($0.height.rounded())" }.joined(separator: "|")
        if sig != lastSignature {
            lastSignature = sig
            DispatchQueue.main.async { [rects] in
                self.onUpdate?(rects)
            }
        }
    }
}
