import AppKit

/// Ventana transparente que cubre una pantalla, justo por encima de las ventanas normales y por debajo
/// de la barra de menús, el Dock y los menús. No recibe clics.
final class RainWindow: NSWindow {
    /// Nivel normal: justo encima de las ventanas, por debajo del Dock, la barra de menús y los menús.
    static let rainLevel = NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue + 1)
    /// Durante la inundación: por encima del Dock y de la barra de menús, aún por debajo de los menús.
    static let floodLevel = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue - 1)

    /// Marco de la pantalla al crearla. `window.screen` es `nil` mientras la ventana está oculta.
    let screenFrame: CGRect
    let rainView: RainView

    init(screen: NSScreen) {
        screenFrame = screen.frame
        rainView = RainView(frame: NSRect(origin: .zero, size: screen.frame.size))
        // La barra de menús es translúcida: la lluvia no debe verse a través de ella.
        rainView.menuBarHeight = max(0, screen.frame.maxY - screen.visibleFrame.maxY)
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = Self.rainLevel
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        animationBehavior = .none
        isExcludedFromWindowsMenu = true
        isReleasedWhenClosed = false
        contentView = rainView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
