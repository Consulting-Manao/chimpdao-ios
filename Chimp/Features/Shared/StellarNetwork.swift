import Foundation

/// Réseau Stellar sur lequel vivent les adresses et les soldes affichés.
/// Au jalon 5, il viendra de `Config/` (Testing → testnet, Release → mainnet, DESIGN_NOTES §12).
enum StellarNetwork: String, Equatable, Sendable {
    case testnet
    case mainnet

    /// Nom affiché (glossaire, DESIGN_NOTES §1.2) : nom propre, non traduit.
    var displayName: String {
        switch self {
        case .testnet: "Stellar Testnet"
        case .mainnet: "Stellar"
        }
    }

    /// Libellé court du sélecteur « Network » des réglages (I2, maquette : « Mainnet », « Testnet »).
    var shortName: String {
        switch self {
        case .testnet: "Testnet"
        case .mainnet: "Mainnet"
        }
    }
}
