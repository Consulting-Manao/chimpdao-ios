import Foundation

/// Les actifs qui ne s'échangent qu'avec quelques autres sur un réseau : choisir l'un d'eux d'un côté du swap met
/// automatiquement en face un partenaire qui a une route (retour de Barth, 2026-11-05). Un actif absent s'échange
/// avec tout.
///
/// Testnet : relevé le 2026-11-05 en demandant un devis pour chaque paire à Soroswap et Aquarius (les copies de
/// `tools/grow-testnet` n'ont de pool qu'avec l'USDC, et xSolvBTC seulement avec SolvBTC). Mainnet : rien de restreint
/// tant que ses routes ne sont pas relevées de la même façon.
enum SwapPairs {
    /// Code de l'actif → ses partenaires, le préféré d'abord.
    static func restricted(on network: StellarNetwork) -> [String: [String]] {
        switch network {
        case .testnet:
            [
                "CETES": ["USDC", "XLM"],
                "USDY": ["USDC"],
                "SolvBTC": ["USDC", "xSolvBTC"],
                "xSolvBTC": ["SolvBTC"],
            ]
        case .mainnet:
            [:]
        }
    }

    /// Les deux actifs ont-ils une route l'un vers l'autre (dans les deux sens) ?
    static func canSwap(_ first: String, _ second: String, on network: StellarNetwork) -> Bool {
        let table = restricted(on: network)
        return (table[first]?.contains(second) ?? true) && (table[second]?.contains(first) ?? true)
    }

    /// Ce qu'on met en face de `chosen` quand l'actif actuel n'a pas de route : l'USDC si possible, sinon son partenaire
    /// préféré ; `nil` si aucun changement n'est nécessaire.
    static func partner(for chosen: String, replacing current: String, on network: StellarNetwork) -> String? {
        guard !canSwap(chosen, current, on: network) else { return nil }
        if canSwap(chosen, "USDC", on: network) { return "USDC" }
        return restricted(on: network)[chosen]?.first
    }
}
