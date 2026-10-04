import AppKit

class RainWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        setFrame(screen.frame, display: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false

        let rainView = RainView(frame: NSRect(x: 0, y: 0, width: screen.frame.width, height: screen.frame.height))
        rainView.autoresizingMask = [.width, .height]
        contentView = rainView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
