// Estudio de capturas de RainDesktop.
//
// Monta un escritorio ficticio en inglés por encima del real (fondo, carpetas, widget del tiempo de
// Nueva York, barra de menús, Dock y tres ventanas de ejemplo) para hacer las capturas del README sin
// que se vea nada del usuario. Nada de lo que se dibuja sale de su Mac.
//
// Uso:
//   swiftc -O Tools/Studio/main.swift -o build/Studio && build/Studio &
//   open RainDesktop.app --args --studio-pid <pid del estudio> -AppleLanguages '(en)' -intensity 0.7 …
// Se cierra con `pkill -x Studio`.
import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Fondo de pantalla

/// Fondo propio (no el del usuario): noche azul con ondas suaves.
struct Wallpaper: View {
    /// Rectángulo de la pantalla y de la ventana que lo dibuja, para que el fondo encaje entre ventanas.
    let screen: CGRect
    let window: CGRect

    var body: some View {
        Canvas { ctx, size in
            ctx.translateBy(x: screen.minX - window.minX, y: window.maxY - screen.maxY)
            let full = CGRect(origin: .zero, size: screen.size)
            ctx.fill(Path(full), with: .linearGradient(
                Gradient(colors: [Color(red: 0.09, green: 0.07, blue: 0.27), Color(red: 0.18, green: 0.12, blue: 0.45),
                                  Color(red: 0.10, green: 0.16, blue: 0.42)]),
                startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: full.width, y: full.height)))
            ctx.fill(Path(ellipseIn: CGRect(x: -250, y: full.height * 0.45, width: 900, height: 700)),
                     with: .radialGradient(Gradient(colors: [Color(red: 0.45, green: 0.32, blue: 0.95).opacity(0.55), .clear]),
                                           center: CGPoint(x: 200, y: full.height * 0.8), startRadius: 0, endRadius: 450))
            for i in 0..<4 {
                let t = CGFloat(i)
                var p = Path()
                let base = full.height * (0.52 + 0.1 * t)
                p.move(to: CGPoint(x: 0, y: base))
                p.addCurve(to: CGPoint(x: full.width, y: base - 120 + 40 * t),
                           control1: CGPoint(x: full.width * 0.35, y: base - 220),
                           control2: CGPoint(x: full.width * 0.65, y: base + 140 - 30 * t))
                p.addLine(to: CGPoint(x: full.width, y: full.height))
                p.addLine(to: CGPoint(x: 0, y: full.height))
                p.closeSubpath()
                ctx.fill(p, with: .linearGradient(
                    Gradient(colors: [Color(red: 0.35 + 0.08 * t, green: 0.30, blue: 0.95).opacity(0.22), .clear]),
                    startPoint: CGPoint(x: 0, y: base - 120), endPoint: CGPoint(x: 0, y: base + 260)))
            }
        }
    }
}

// MARK: - Escritorio

struct DesktopItem: Identifiable {
    let id = UUID()
    let name: String
    let type: UTType
}

struct DesktopIcon: View {
    let item: DesktopItem
    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: NSWorkspace.shared.icon(for: item.type))
                .resizable()
                .frame(width: 64, height: 64)
            Text(item.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(width: 96)
                .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
        }
        .frame(width: 100, height: 104, alignment: .top)
    }
}

struct WeatherWidget: View {
    let hours: [(String, String, Int)] = [("10AM", "cloud.rain.fill", 61), ("11AM", "cloud.heavyrain.fill", 62),
                                          ("12PM", "cloud.heavyrain.fill", 63), ("1PM", "cloud.rain.fill", 63),
                                          ("2PM", "cloud.drizzle.fill", 62), ("3PM", "cloud.fill", 60)]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 4) {
                        Text("New York").font(.system(size: 15, weight: .semibold))
                        Image(systemName: "location.fill").font(.system(size: 10))
                    }
                    Text("61°").font(.system(size: 42, weight: .light))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Image(systemName: "cloud.rain.fill").symbolRenderingMode(.multicolor).font(.system(size: 20))
                    Text("Rain").font(.system(size: 13, weight: .semibold))
                    Text("H:64° L:55°").font(.system(size: 13, weight: .semibold))
                }
            }
            HStack {
                ForEach(hours, id: \.0) { hour in
                    VStack(spacing: 5) {
                        Text(hour.0).font(.system(size: 11, weight: .semibold)).opacity(0.8)
                        Image(systemName: hour.1).symbolRenderingMode(.multicolor).font(.system(size: 15))
                        Text("\(hour.2)°").font(.system(size: 13, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(width: 338, height: 158)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.22, green: 0.27, blue: 0.40), Color(red: 0.13, green: 0.16, blue: 0.27)],
                                     startPoint: .top, endPoint: .bottom))
        )
    }
}

struct Backdrop: View {
    let screen: CGRect
    let menuBarHeight: CGFloat
    let items: [DesktopItem] = [
        .init(name: "Projects", type: .folder), .init(name: "Design Assets", type: .folder),
        .init(name: "Photos", type: .folder), .init(name: "Rainy Day Playlist", type: .folder),
        .init(name: "Trip to New York.pdf", type: .pdf), .init(name: "Moodboard.png", type: .png),
        .init(name: "Ideas.txt", type: .plainText), .init(name: "Invoices", type: .folder),
    ]

    var body: some View {
        ZStack(alignment: .topLeading) {
            Wallpaper(screen: screen, window: screen)
            WeatherWidget()
                .padding(.leading, 22)
                .padding(.top, menuBarHeight + 20)
            HStack(alignment: .top, spacing: 4) {
                Spacer()
                VStack(spacing: 8) { ForEach(items.suffix(4)) { DesktopIcon(item: $0) } }
                VStack(spacing: 8) { ForEach(items.prefix(4)) { DesktopIcon(item: $0) } }
            }
            .padding(.top, menuBarHeight + 14)
            .padding(.trailing, 14)
        }
        .frame(width: screen.width, height: screen.height)
    }
}

// MARK: - Barra de menús y Dock

final class StatusItemLocator: ObservableObject {
    /// Posición x (en la pantalla) del icono real de RainDesktop, para dibujar el falso en el mismo sitio.
    /// RainDesktop la anuncia en modo estudio con una notificación distribuida.
    @Published var x: CGFloat?

    init() {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.gonzalo.raindesktop.studio.statusItem"), object: nil, queue: .main
        ) { [weak self] note in
            if let text = note.object as? String, let value = Double(text) { self?.x = CGFloat(value) }
        }
    }
}

struct MenuBar: View {
    let screen: CGRect
    let height: CGFloat
    @ObservedObject var locator: StatusItemLocator

    var body: some View {
        ZStack(alignment: .leading) {
            Wallpaper(screen: screen, window: CGRect(x: screen.minX, y: screen.maxY - height, width: screen.width, height: height))
            Color.black.opacity(0.12)
            HStack(spacing: 18) {
                Image(systemName: "apple.logo").font(.system(size: 15))
                Text("Finder").fontWeight(.bold)
                ForEach(["File", "Edit", "View", "Go", "Window", "Help"], id: \.self) { Text($0) }
                Spacer()
                ForEach(["wifi", "battery.75percent", "magnifyingglass", "switch.2"], id: \.self) {
                    Image(systemName: $0).font(.system(size: 14))
                }
                Text("Fri Oct 9  9:41 AM")
            }
            .font(.system(size: 13.5, weight: .medium))
            .padding(.horizontal, 22)
            // El icono de RainDesktop, justo donde está el real (el panel se abre desde ahí).
            if let x = locator.x {
                Image(systemName: "cloud.rain.fill")
                    .font(.system(size: 14))
                    .position(x: x - screen.minX, y: height / 2)
            }
        }
        .foregroundStyle(.white)
        .frame(width: screen.width, height: height)
    }
}

struct Dock: View {
    let screen: CGRect
    let height: CGFloat
    let apps = ["/System/Library/CoreServices/Finder.app", "/System/Cryptexes/App/System/Applications/Safari.app", "/System/Applications/Messages.app",
                "/System/Applications/Mail.app", "/System/Applications/Maps.app", "/System/Applications/Photos.app",
                "/System/Applications/Notes.app", "/System/Applications/Music.app", "/System/Applications/Calendar.app",
                "/System/Applications/System Settings.app"]

    var body: some View {
        ZStack {
            Wallpaper(screen: screen, window: CGRect(x: screen.minX, y: screen.minY, width: screen.width, height: height))
            HStack(spacing: 6) {
                ForEach(apps.filter { FileManager.default.fileExists(atPath: $0) }, id: \.self) { path in
                    Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 54, height: 54)
                }
                Rectangle().fill(.white.opacity(0.3)).frame(width: 1, height: 44).padding(.horizontal, 4)
                Image(nsImage: NSWorkspace.shared.icon(for: .folder)).resizable().frame(width: 54, height: 54)
                Image(nsImage: NSImage(named: NSImage.trashEmptyName) ?? NSImage()).resizable().frame(width: 54, height: 54)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.white.opacity(0.16))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.28), lineWidth: 1))
            )
            .padding(.bottom, 4)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(width: screen.width, height: height)
    }
}

// MARK: - Ventanas de ejemplo

struct ProjectsWindow: View {
    let rows: [(String, UTType, String, String)] = [
        ("Website Redesign", .folder, "Today, 9:12 AM", "--"),
        ("Brand Guidelines.pdf", .pdf, "Yesterday, 6:40 PM", "4.2 MB"),
        ("NYC Trip", .folder, "Oct 3, 2026", "--"),
        ("Podcast Episode 12.mp3", .mp3, "Oct 1, 2026", "38.5 MB"),
        ("Moodboard.png", .png, "Sep 28, 2026", "2.1 MB"),
        ("Q4 Roadmap.txt", .plainText, "Sep 24, 2026", "12 KB"),
        ("Rain Recordings", .folder, "Sep 20, 2026", "--"),
    ]
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Name").frame(maxWidth: .infinity, alignment: .leading)
                Text("Date Modified").frame(width: 170, alignment: .leading)
                Text("Size").frame(width: 70, alignment: .trailing)
            }
            .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            .padding(.horizontal, 18).padding(.vertical, 8)
            Divider()
            ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                HStack(spacing: 8) {
                    Image(nsImage: NSWorkspace.shared.icon(for: row.1)).resizable().frame(width: 20, height: 20)
                    Text(row.0).frame(maxWidth: .infinity, alignment: .leading)
                    Text(row.2).foregroundStyle(.secondary).frame(width: 170, alignment: .leading)
                    Text(row.3).foregroundStyle(.secondary).frame(width: 70, alignment: .trailing)
                }
                .font(.system(size: 13))
                .padding(.horizontal, 18).padding(.vertical, 7)
                .background(i % 2 == 1 ? Color.primary.opacity(0.04) : .clear)
            }
            Spacer()
        }
    }
}

struct IdeasWindow: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Rainy Day Ideas").font(.system(size: 22, weight: .bold))
            Text("Friday, October 9").font(.system(size: 12)).foregroundStyle(.secondary)
            ForEach(["☕️  Make hot chocolate", "📚  Finish my book", "🎧  Lo-fi playlist + rain sounds",
                     "🧩  Start the 1,000-piece puzzle", "🪟  Watch the rain on the windows"], id: \.self) {
                Text($0).font(.system(size: 15))
            }
            Spacer()
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct NowPlayingWindow: View {
    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 10)
                .fill(LinearGradient(colors: [Color(red: 0.25, green: 0.35, blue: 0.75), Color(red: 0.1, green: 0.12, blue: 0.35)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(Image(systemName: "cloud.rain.fill").font(.system(size: 30)).foregroundStyle(.white))
                .frame(width: 76, height: 76)
            VStack(alignment: .leading, spacing: 6) {
                Text("Rain on the Window").font(.system(size: 14, weight: .semibold))
                Text("Ambient Sounds").font(.system(size: 12)).foregroundStyle(.secondary)
                ProgressView(value: 0.42).controlSize(.small)
                HStack(spacing: 22) {
                    Image(systemName: "backward.fill")
                    Image(systemName: "pause.fill").font(.system(size: 18))
                    Image(systemName: "forward.fill")
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
    }
}

// MARK: - Montaje

func makeWindow(_ frame: CGRect, level: NSWindow.Level, borderless: Bool, title: String = "",
                content: some View) -> NSWindow {
    let style: NSWindow.StyleMask = borderless ? [.borderless] : [.titled, .closable, .miniaturizable, .resizable]
    let window = NSWindow(contentRect: frame, styleMask: style, backing: .buffered, defer: false)
    window.title = title
    window.level = level
    window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(rootView: content)
    window.setFrame(borderless ? frame : window.frameRect(forContentRect: frame), display: true)
    if borderless {
        window.hasShadow = false
        window.ignoresMouseEvents = true
    }
    window.collectionBehavior = [.fullScreenAuxiliary]
    return window
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
// Que macOS no agrupe las ventanas de ejemplo en pestañas.
NSWindow.allowsAutomaticWindowTabbing = false

let screen = NSScreen.screens[0]
let s = screen.frame
let menuBarHeight = max(24, s.maxY - screen.visibleFrame.maxY)
let dockHeight = max(76, screen.visibleFrame.minY - s.minY + 6)
let locator = StatusItemLocator()

var windows: [NSWindow] = []
windows.append(makeWindow(s, level: .normal, borderless: true, content: Backdrop(screen: s, menuBarHeight: menuBarHeight)))
windows.append(makeWindow(CGRect(x: s.minX, y: s.maxY - menuBarHeight, width: s.width, height: menuBarHeight),
                          level: NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2), borderless: true,
                          content: MenuBar(screen: s, height: menuBarHeight, locator: locator)))
windows.append(makeWindow(CGRect(x: s.minX, y: s.minY, width: s.width, height: dockHeight),
                          level: NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1), borderless: true,
                          content: Dock(screen: s, height: dockHeight)))
// Ventanas de ejemplo (contenido, en puntos desde abajo a la izquierda), colocadas para que se vean
// bordes superiores y laterales libres.
windows.append(makeWindow(CGRect(x: s.minX + 130, y: s.minY + 250, width: 640, height: 340), level: .normal,
                          borderless: false, title: "Projects", content: ProjectsWindow()))
windows.append(makeWindow(CGRect(x: s.minX + 710, y: s.minY + 330, width: 420, height: 290), level: .normal,
                          borderless: false, title: "Rainy Day Ideas", content: IdeasWindow()))
windows.append(makeWindow(CGRect(x: s.minX + 880, y: s.minY + 130, width: 380, height: 108), level: .normal,
                          borderless: false, title: "Now Playing", content: NowPlayingWindow()))

for w in windows { w.orderFrontRegardless() }
app.activate(ignoringOtherApps: true)
windows.last?.makeKeyAndOrderFront(nil)
app.run()
