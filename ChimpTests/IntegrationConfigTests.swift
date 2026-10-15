import Foundation
import Testing
@testable import ChimpDAO

/// Tranche 2, phase 1, étape 6 : adresses des intégrations dans `Config/` (portage de `contractsProblems`).
struct IntegrationConfigTests {
    private let config = ChimpNetworkConfig.testnet

    private var knownAssetCodes: Set<String> {
        Set(((try? SACClient.stellarAssets(config: config)) ?? []).map(\.code))
    }

    private var reserved: [String] {
        [config.contracts.factory, config.contracts.collection, config.contracts.nfcNft, config.contracts.router]
    }

    @Test("Table testnet cohérente : adresses valides, aucune répétée ni prise à ChimpDAO, actifs connus, SAC du CETES calculé")
    func testnetTableHasNoProblems() throws {
        let integrations = try #require(config.integrations)
        #expect(integrations.problems(passphrase: config.passphrase, knownAssetCodes: knownAssetCodes, reserved: reserved).isEmpty)
    }

    @Test("Décisions du 2026-10-14 : vault XLM seulement (USDC exclu), Blend affiché comme sous-jacent, CETES, pas de prize")
    func decisions() throws {
        let integrations = try #require(config.integrations)
        #expect(integrations.defindexVaults.map(\.assetCode) == ["XLM"])
        #expect(!integrations.defindexVaults.contains { $0.vault == "CBMVK2JK6NTOT2O4HNQAIQFJY232BHKGLIMXDVQVHIIZKDACXDFZDWHN" })
        #expect(integrations.defindexVaults[0].underlyingProtocols.contains("Blend"))
        #expect(integrations.etherfuse.stablebonds.map(\.code) == ["CETES"])
        #expect(integrations.etherfuse.priceAPI.host == "api.sand.etherfuse.com")
    }

    @Test("Aucune intégration sur mainnet")
    func mainnetHasNone() {
        #expect(IntegrationConfig.for(.mainnet) == nil)
    }

    @Test("Problèmes détectés : adresse mal formée, adresse répétée ou de ChimpDAO, actif inconnu, SAC qui ne correspond pas")
    func problemsAreReported() {
        let base = IntegrationConfig.testnet
        let broken = IntegrationConfig(
            soroswap: .init(router: "not-an-address", factory: config.contracts.router),
            aquarius: .init(router: config.contracts.nfcNft),
            defindexVaults: [.init(vault: base.defindexVaults[0].vault, assetCode: "EURC", name: "EURC vault", underlyingProtocols: [])],
            etherfuse: .init(
                issuer: base.etherfuse.issuer,
                stablebonds: [.init(code: "CETES", contract: base.defindexVaults[0].vault)],
                priceAPI: URL(string: "http://api.etherfuse.com/")!
            )
        )
        let problems = broken.problems(passphrase: config.passphrase, knownAssetCodes: knownAssetCodes, reserved: reserved)
        #expect(problems.contains { $0.hasPrefix("soroswap.router is not a C-address") })
        #expect(problems.contains("soroswap.factory repeats an address used elsewhere"))
        #expect(problems.contains("aquarius.router repeats an address used elsewhere"))
        #expect(problems.contains("defindexVaults[EURC vault] names unknown asset \"EURC\""))
        #expect(problems.contains("defindexVaults[EURC vault] names no underlying protocol"))
        #expect(problems.contains("etherfuse.CETES repeats an address used elsewhere"))
        #expect(problems.contains { $0.hasPrefix("etherfuse.CETES is not the SAC of CETES:") })
        #expect(problems.contains("etherfuse.priceAPI is not https"))
    }
}
