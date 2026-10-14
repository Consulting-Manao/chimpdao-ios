import Foundation

#if DEBUG
/// Réglage caché du catalogue, **en Debug seulement** (demande de Barth du 2026-10-14) : forcer un protocole d'échange.
/// Sur testnet, Aquarius donne toujours le meilleur prix ; un swap Soroswap signé par la carte est pourtant une preuve du
/// livrable D2. Le devis ne vient alors que de ce protocole, et E3 le dit ; tout le reste (bornes, arbre, signature,
/// frais) est inchangé. Absent du Release.
enum SwapProtocolOverride: String, CaseIterable, Identifiable {
    /// Le meilleur des deux (comportement normal).
    case automatic
    case soroswap
    case aquarius

    static let defaultsKey = "chimp.debug.swapProtocol"

    var id: String { rawValue }

    /// L'identifiant de l'adaptateur forcé, `nil` pour le comportement normal.
    var protocolID: String? { self == .automatic ? nil : rawValue }

    var title: String {
        switch self {
        case .automatic: "Best of Soroswap and Aquarius"
        case .soroswap: "Soroswap only"
        case .aquarius: "Aquarius only"
        }
    }

    static var current: SwapProtocolOverride {
        get { UserDefaults.standard.string(forKey: defaultsKey).flatMap(SwapProtocolOverride.init(rawValue:)) ?? .automatic }
        set { UserDefaults.standard.set(newValue == .automatic ? nil : newValue.rawValue, forKey: defaultsKey) }
    }
}
#endif
