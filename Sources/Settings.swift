import Foundation

struct RainSettings: Equatable {
    static let streamWidthRange = 0.5...12.0

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
    var sound = true
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
        static let sound = "sound"
        static let volume = "volume"
    }

    static func load() -> RainSettings {
        var s = RainSettings()
        s.raining = defaults.object(forKey: Key.raining) as? Bool ?? s.raining
        s.intensity = clamp(defaults.object(forKey: Key.intensity) as? Double ?? s.intensity, 0, 1)
        s.wind = clamp(defaults.object(forKey: Key.wind) as? Double ?? s.wind, -1, 1)
        s.bounce = clamp(defaults.object(forKey: Key.bounce) as? Double ?? s.bounce, 0, 1)
        s.lightning = defaults.object(forKey: Key.lightning) as? Bool ?? s.lightning
        s.collide = defaults.object(forKey: Key.collide) as? Bool ?? s.collide
        s.sideCollide = defaults.object(forKey: Key.sideCollide) as? Bool ?? s.sideCollide
        s.streamWidth = clamp(defaults.object(forKey: Key.streamWidth) as? Double ?? s.streamWidth,
                              RainSettings.streamWidthRange.lowerBound, RainSettings.streamWidthRange.upperBound)
        s.sound = defaults.object(forKey: Key.sound) as? Bool ?? s.sound
        s.volume = clamp(defaults.object(forKey: Key.volume) as? Double ?? s.volume, 0, 1)
        return s
    }

    static func save(_ s: RainSettings) {
        defaults.set(s.raining, forKey: Key.raining)
        defaults.set(s.intensity, forKey: Key.intensity)
        defaults.set(s.wind, forKey: Key.wind)
        defaults.set(s.bounce, forKey: Key.bounce)
        defaults.set(s.lightning, forKey: Key.lightning)
        defaults.set(s.collide, forKey: Key.collide)
        defaults.set(s.sideCollide, forKey: Key.sideCollide)
        defaults.set(s.streamWidth, forKey: Key.streamWidth)
        defaults.set(s.sound, forKey: Key.sound)
        defaults.set(s.volume, forKey: Key.volume)
    }

    private static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        min(max(v, lo), hi)
    }
}
