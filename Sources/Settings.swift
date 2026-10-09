import Foundation

struct RainSettings: Equatable {
    static let streamWidthRange = 0.5...12.0
    static let floodMinutesRange = 0.25...5.0

    var raining = false
    /// De 0 a 1.
    var intensity = 0.6
    /// De -1 (hacia la izquierda) a 1 (hacia la derecha).
    var wind = 0.25
    /// De 0 (suave) a 1 (fuerte).
    var bounce = 0.5
    var lightning = true
    var collide = true
    /// Rebotar también en los laterales (se nota con viento).
    var sideCollide = true
    /// Grosor en puntos de un hilo lateral con el caudal máximo.
    var streamWidth = 1.0
    /// Si no se usa el Mac, el agua va subiendo hasta llenar la pantalla.
    var flood = false
    /// Minutos que tarda en llenarse la pantalla.
    var floodMinutes = 1.0
    var sound = true
    /// Comprobar una vez al día si hay una versión nueva en GitHub.
    var checkUpdates = true
    /// De 0 a 1.
    var volume = 0.5
}

/// Guarda los ajustes en `UserDefaults` (dentro del contenedor del sandbox).
enum SettingsStore {
    private static let defaults = UserDefaults.standard

    private enum Key {
        static let raining = "raining"
        static let intensity = "intensity"
        static let wind = "wind"
        static let bounce = "bounce"
        static let lightning = "lightning"
        static let collide = "collide"
        static let sideCollide = "sideCollide"
        static let streamWidth = "streamWidth"
        static let flood = "flood"
        static let floodMinutes = "floodMinutes"
        static let sound = "sound"
        static let checkUpdates = "checkUpdates"
        static let volume = "volume"
    }

    static func load() -> RainSettings {
        var s = RainSettings()
        s.raining = bool(Key.raining, s.raining)
        s.intensity = double(Key.intensity, s.intensity, 0...1)
        s.wind = double(Key.wind, s.wind, -1...1)
        s.bounce = double(Key.bounce, s.bounce, 0...1)
        s.lightning = bool(Key.lightning, s.lightning)
        s.collide = bool(Key.collide, s.collide)
        s.sideCollide = bool(Key.sideCollide, s.sideCollide)
        s.streamWidth = double(Key.streamWidth, s.streamWidth, RainSettings.streamWidthRange)
        s.flood = bool(Key.flood, s.flood)
        s.floodMinutes = double(Key.floodMinutes, s.floodMinutes, RainSettings.floodMinutesRange)
        s.sound = bool(Key.sound, s.sound)
        s.checkUpdates = bool(Key.checkUpdates, s.checkUpdates)
        s.volume = double(Key.volume, s.volume, 0...1)
        return s
    }

    // `bool(forKey:)` y `double(forKey:)` también leen los argumentos de lanzamiento (`-intensity 0.7`),
    // que llegan como texto.
    private static func bool(_ key: String, _ fallback: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
    }

    private static func double(_ key: String, _ fallback: Double, _ range: ClosedRange<Double>) -> Double {
        let value = defaults.object(forKey: key) == nil ? fallback : defaults.double(forKey: key)
        return min(max(value, range.lowerBound), range.upperBound)
    }

    static func save(_ s: RainSettings) {
        // En el estudio de capturas no se toca nada de lo que el usuario tiene guardado.
        guard !StudioMode.isActive else { return }
        defaults.set(s.raining, forKey: Key.raining)
        defaults.set(s.intensity, forKey: Key.intensity)
        defaults.set(s.wind, forKey: Key.wind)
        defaults.set(s.bounce, forKey: Key.bounce)
        defaults.set(s.lightning, forKey: Key.lightning)
        defaults.set(s.collide, forKey: Key.collide)
        defaults.set(s.sideCollide, forKey: Key.sideCollide)
        defaults.set(s.streamWidth, forKey: Key.streamWidth)
        defaults.set(s.flood, forKey: Key.flood)
        defaults.set(s.floodMinutes, forKey: Key.floodMinutes)
        defaults.set(s.sound, forKey: Key.sound)
        defaults.set(s.checkUpdates, forKey: Key.checkUpdates)
        defaults.set(s.volume, forKey: Key.volume)
    }
}
