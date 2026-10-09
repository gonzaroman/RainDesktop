import Foundation

/// Texto traducido. La clave es el texto en inglés; `Resources/es.lproj/Localizable.strings` tiene el español.
/// La app sale en el idioma del Mac (español o inglés; en cualquier otro idioma, en inglés).
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}
