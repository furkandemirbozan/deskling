import Foundation

/// Masaüstündeki içeceğin teması.
enum DrinkKind: String, CaseIterable, Identifiable, Codable {
    case tea, turkishCoffee, mug, beer
    var id: String { rawValue }

    var title: String {
        switch self {
        case .tea: return "İnce Belli Çay"
        case .turkishCoffee: return "Türk Kahvesi"
        case .mug: return "Kahve"
        case .beer: return "Bira"
        }
    }

    var shortTitle: String {
        switch self {
        case .tea: return "Çay"
        case .turkishCoffee: return "Türk Kahvesi"
        case .mug: return "Kahve"
        case .beer: return "Bira"
        }
    }

    /// Odak bitince çalan, temaya yakışan yumuşak ses.
    var focusEndSound: String {
        switch self {
        case .tea: return "Tink"            // kaşık şıngırtısı
        case .turkishCoffee: return "Purr"
        case .mug: return "Pop"
        case .beer: return "Bottle"
        }
    }

    var breakEndSound: String { "Glass" }
}

enum DrinkSize: String, CaseIterable, Identifiable {
    case small, medium, large
    var id: String { rawValue }
    var title: String { self == .small ? "Küçük" : self == .medium ? "Orta" : "Büyük" }
    var scale: Double { self == .small ? 0.75 : self == .medium ? 1.0 : 1.35 }

    /// Ölçeğe en yakın hazır boyut (sağ tık menüsündeki işaret için).
    static func nearest(_ s: Double) -> DrinkSize {
        allCases.min(by: { abs($0.scale - s) < abs($1.scale - s) })!
    }
}

/// Animasyon yoğunluğu: düşükte kare hızı ve partikül sayısı azalır.
enum DrinkEffects: String, CaseIterable, Identifiable {
    case low, high
    var id: String { rawValue }
    var title: String { self == .low ? "Düşük (tasarruflu)" : "Yüksek" }
    /// Sakinken kare hızı.
    var fps: Int { self == .low ? 20 : 30 }
    /// Sürükleme, dolum ve titreme sırasında kare hızı.
    var activeFps: Int { self == .low ? 30 : 60 }
    var particleFactor: Double { self == .low ? 0.4 : 1 }
}

/// Ayar sınırları ve varsayılanlar tek yerde.
enum PomoLimits {
    static let focus = 5...90
    static let shortBreak = 1...30
    static let longBreak = 5...60
    static let cycle = 2...8
    static let scale = 0.6...1.6

    static let defaults: [String: Any] = [
        "pomoEnabled": true, "pomoShowDrink": true, "pomoDrink": DrinkKind.tea.rawValue,
        "pomoFocus": 25, "pomoShort": 5, "pomoLong": 15, "pomoCycle": 4,
        "pomoScale": 1.0, "pomoMenuTimer": true, "pomoEffects": DrinkEffects.high.rawValue,
        "pomoSound": true, "pomoNotify": true, "pomoKeepAwake": false,
        "pomoQuietFocus": false, "pomoCleanOnBreak": false,
    ]

    static func clamp(_ v: Int, _ r: ClosedRange<Int>) -> Int { min(r.upperBound, max(r.lowerBound, v)) }
}
