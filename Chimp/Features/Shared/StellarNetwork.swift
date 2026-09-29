import Foundation

/// Réseau Stellar sur lequel vivent les adresses et les soldes affichés.
/// Au jalon 5, il viendra de `Config/` (Testing → testnet, Release → mainnet, DESIGN_NOTES §12).
enum StellarNetwork: Equatable {
    case testnet
    case mainnet

    /// Nom affiché (glossaire, DESIGN_NOTES §1.2) : nom propre, non traduit.
    var displayName: String {
        switch self {
        case .testnet: "Stellar Testnet"
        case .mainnet: "Stellar"
        }
    }
}
