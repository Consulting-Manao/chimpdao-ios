import Foundation

extension IntegrationConfig.DeFindexVault {
    /// « DeFindex XLM » (maquette I1g.1 : VAULT), et la chaîne des protocoles « DeFindex → Blend » (PROTOCOLS).
    var label: ActivityRecord.VaultLabel {
        ActivityRecord.VaultLabel(
            name: "\(underlyingProtocols.first ?? "DeFindex") \(assetCode)",
            protocols: underlyingProtocols.joined(separator: " → ")
        )
    }
}

extension ChimpNetworkConfig {
    /// Les vaults de ce réseau, par adresse : pour reconnaître un dépôt ou un retrait relu sur la chaîne.
    var vaultLabels: [String: ActivityRecord.VaultLabel] {
        Dictionary(uniqueKeysWithValues: (integrations?.defindexVaults ?? []).map { ($0.vault, $0.label) })
    }
}
