import Foundation
import Testing
@testable import ChimpDAO

/// Configuration par build (décision de Barth du 2026-10-19) : Debug et Testing → testnet, Release → mainnet ; passée
/// partout depuis la session, sans valeur par défaut ; mainnet incomplet → l'app ne démarre pas, jamais de repli.
struct NetworkConfigTests {
    @Test("Les tests tournent en Debug : la configuration de ce build est celle du testnet")
    func thisBuild() throws {
        #expect(try ChimpNetworkConfig.forThisBuild() == .testnet)
    }

    @Test("Mainnet : les contrats ChimpDAO, le serveur de frais et le repère de l'horloge manquent, et c'est dit")
    func mainnetIncomplete() {
        let draft = ChimpNetworkConfig.mainnetDraft
        #expect(draft.network == .mainnet)
        #expect(draft.passphrase == "Public Global Stellar Network ; September 2015")
        #expect(draft.friendbot == nil && draft.usdcFaucet == nil, "Ni friendbot ni robinet sur le mainnet")
        #expect(draft.missing == [
            "contracts.factory", "contracts.collection", "contracts.nfcNft", "contracts.accountWasmHash", "contracts.router",
            "feeSignerURL", "feePayer", "ledgerAnchor",
        ])
        #expect(throws: NetworkConfigError.incomplete(network: .mainnet, missing: draft.missing)) { try draft.complete() }
    }

    /// Le même chemin que le mainnet, rempli avec les valeurs du testnet : il rend exactement `.testnet`.
    private func testnetDraft(factory: String? = ChimpNetworkConfig.testnet.contracts.factory) -> NetworkConfigDraft {
        let t = ChimpNetworkConfig.testnet
        return NetworkConfigDraft(
            network: t.network, passphrase: t.passphrase, rpc: t.endpoints.rpc, horizon: t.endpoints.horizon,
            explorer: t.endpoints.explorer, friendbot: t.endpoints.friendbot, factory: factory,
            collection: t.contracts.collection, nfcNft: t.contracts.nfcNft, accountWasmHash: t.contracts.accountWasmHash,
            router: t.contracts.router, admin: t.contracts.admin, feeSignerURL: t.feeSignerURL, feePayer: t.feePayer,
            usdcIssuer: t.usdcIssuer, usdcFaucet: t.usdcFaucet, ledgerAnchor: t.ledgerAnchor
        )
    }

    @Test("Une configuration complète est acceptée ; une valeur vide (\"\") compte comme absente")
    func complete() throws {
        #expect(try testnetDraft().complete() == .testnet)
        #expect(testnetDraft(factory: "").missing == ["contracts.factory"])
        #expect(throws: NetworkConfigError.self) { try testnetDraft(factory: "").complete() }
    }

    @Test("La session porte la configuration ; son réseau en découle")
    func session() {
        let session = AppSession(store: InMemoryLocalWalletStore(), config: .testnet)
        #expect(session.config == .testnet)
        #expect(session.network == .testnet)
    }

    /// Garde-fou de lecture du code : aucun réseau par défaut dans l'app (hors `Config/` et le mode admin, testnet par
    /// construction). Un paramètre `= .testnet` oublié ferait parler un service au testnet dans un build mainnet.
    @Test("Aucun « = .testnet » ni « ?? .testnet » dans le code de l'app")
    func noDefaultNetwork() throws {
        let patterns = [": ChimpNetworkConfig = ", ": StellarNetwork = ", "?? .testnet", "?? .mainnet"]
        var violations: [String] = []
        for (name, text) in try AsyncAmountRuleTests.sources() where !name.contains("/Config/") && !name.contains("/Admin/") {
            for (index, line) in text.components(separatedBy: "\n").enumerated() where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                for pattern in patterns where line.contains(pattern) {
                    violations.append("\(name):\(index + 1) \(pattern)")
                }
            }
        }
        #expect(violations.isEmpty, "\(violations)")
    }
}
