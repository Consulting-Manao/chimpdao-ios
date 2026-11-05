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

extension IntegrationConfig.Xoxno {
    /// « XOXNO USDC », via « XOXNO ».
    var label: ActivityRecord.VaultLabel {
        ActivityRecord.VaultLabel(name: name, protocols: "XOXNO")
    }
}

extension IntegrationConfig.Sentora {
    /// « Sentora USDC », via « Sentora ».
    var label: ActivityRecord.VaultLabel {
        ActivityRecord.VaultLabel(name: name, protocols: "Sentora")
    }
}

extension ChimpNetworkConfig {
    /// Les vaults de ce réseau, par adresse : pour reconnaître un dépôt ou un retrait relu sur la chaîne.
    var vaultLabels: [String: ActivityRecord.VaultLabel] {
        var labels = Dictionary(uniqueKeysWithValues: (integrations?.defindexVaults ?? []).map { ($0.vault, $0.label) })
        // XOXNO : un dépôt envoie l'actif à la réserve commune, un retrait le fait revenir de la réserve.
        if let xoxno = integrations?.xoxno { labels[xoxno.pool] = xoxno.label }
        // Sentora : le vault garde l'actif lui-même.
        if let sentora = integrations?.sentora { labels[sentora.vault] = sentora.label }
        return labels
    }
}
