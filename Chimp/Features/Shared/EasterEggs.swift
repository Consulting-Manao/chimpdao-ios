import Foundation

/// Easter eggs J1 à J3 (maquette « Chimp App Final », section J ; règles validées le 2026-09-30, construits le
/// 2026-11-10). Rares, plein écran, ils ne bloquent jamais rien : un tap et on revient où on était. J4 n'existe pas
/// (décision de Barth du 2026-09-30 : au 3ᵉ PIN faux, une Infineon se bloque pour de bon).
enum ChimpEasterEgg: String, Identifiable, Equatable {
    /// J1 · 7 taps en moins de 3 s sur la banane du pied des réglages.
    case bananaMode
    /// J2 · l'app ouverte entre 3 h 00 et 3 h 59, une fois par nuit, sur le Wallet seulement.
    case nightOwl
    /// J3 · le total du Wallet passe de moins de 1 000 $ à 1 000 $ ou plus, une fois par compte.
    case thousandaire

    var id: String { rawValue }
}

/// Les règles des déclencheurs, sans écran (testées à part).
enum EasterEggRules {
    static let bananaTaps = 7
    static let bananaWindow: TimeInterval = 3
    static let thousand: Decimal = 1_000

    /// J1 : les 7 derniers taps tiennent en 3 s.
    static func isBananaMode(_ taps: [Date]) -> Bool {
        guard taps.count >= bananaTaps, let first = taps.suffix(bananaTaps).first, let last = taps.last else { return false }
        return last.timeIntervalSince(first) < bananaWindow
    }

    /// J2 : entre 3 h 00 et 3 h 59, à l'heure du téléphone.
    static func isNightOwlHour(_ date: Date, calendar: Calendar = .current) -> Bool {
        calendar.component(.hour, from: date) == 3
    }

    /// J2 : la nuit, notée pour ne pas revenir avant la suivante (« 2026-11-12 »).
    static func night(of date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// J3 : le total en **dollars**, quelle que soit la devise affichée (sinon « $1,000 » ne voudrait rien dire) ; `nil`
    /// quand un avoir n'a pas de prix (pas de total partiel).
    static func usdTotal(_ snapshot: WalletSnapshot) -> Decimal? {
        DisplayMoney(currency: .usd, usdPrices: snapshot.usdPrices).value(snapshot.allAssets).map { $0 + (snapshot.main.growing ?? 0) }
    }

    /// J3 : passage de moins de 1 000 $ à 1 000 $ ou plus entre deux lectures réussies du même compte.
    static func crossesThousand(from previous: Decimal?, to current: Decimal?) -> Bool {
        guard let previous, let current else { return false }
        return previous < thousand && current >= thousand
    }
}

#if DESIGN_CATALOG
import SwiftUI

/// Lancement direct d'un easter egg (Debug et Testing), sans attendre 3 h du matin ni 1 000 $ :
/// `xcrun simctl launch <appareil> com.consulting-manao.chimp -easterEggDemo bananaMode` (`nightOwl`, `thousandaire`).
struct EasterEggDemoLaunch: ViewModifier {
    @State private var egg = UserDefaults.standard.string(forKey: "easterEggDemo").flatMap(ChimpEasterEgg.init(rawValue:))

    func body(content: Content) -> some View {
        content.overlay {
            if let egg {
                ChimpEasterEggView(egg: egg) { self.egg = nil }
            }
        }
    }
}
#endif
