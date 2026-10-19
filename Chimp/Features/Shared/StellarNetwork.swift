import Foundation

/// Réseau Stellar sur lequel vivent les adresses et les soldes affichés.
/// Celui de la configuration de ce build (`ChimpNetworkConfig.forThisBuild` : Debug et Testing → testnet, Release →
/// mainnet ; décision de Barth du 2026-10-19).
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
