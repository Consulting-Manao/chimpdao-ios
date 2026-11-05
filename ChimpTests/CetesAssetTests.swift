import Foundation
import stellarsdk
import Testing
@testable import ChimpDAO

/// Tranche 2, phase 5, étape 1 : CETES d'Etherfuse comme actif de l'app, reconnu **par l'adresse exacte de son contrat**,
/// jamais par son code (il existe au moins quinze autres « CETES » sur testnet, relevés sur Horizon le 2026-10-15).
struct CetesAssetTests {
    /// SAC du CETES d'Etherfuse (émetteur sandbox `GC3CW7…UPS4`).
    static let cetes = "CC72F57YTPX76HAA64JQOEGHQAPSADQWSY5DWVBR66JINPFDLNCQYHIC"
    /// SAC d'un autre « CETES » de testnet (émetteur `GAAV6W…SXUC`), sans rapport avec Etherfuse.
    static let otherCetes = "CD4RNB7OSWXXR6KNIUVWT2YKBMNTR6R4DD4FHZYRMN7ICEI3YOMG2C3H"

    @Test("Liste blanche de l'app : XLM, USDC, CETES à son adresse exacte (le SAC de CETES:GC3CW7…UPS4), puis USDY, SolvBTC, xSolvBTC")
    func whitelist() throws {
        let config = ChimpNetworkConfig.testnet
        let assets = try SACClient.stellarAssets(config: config)
        #expect(assets.map(\.code) == ["XLM", "USDC", "CETES", "USDY", "SolvBTC", "xSolvBTC"])
        #expect(assets.first { $0.code == "CETES" }?.contract == Self.cetes)
        let issuer = try #require(config.integrations?.etherfuse.issuer)
        #expect(issuer == "GC3CW7EDYRTWQ635VDIGY6S4ZUF5L6TQ7AA4MWS7LEQDBLUSZXV7UPS4")
        let asset = try #require(Asset(canonicalForm: "CETES:\(issuer)"))
        #expect(try SACClient.contractID(for: asset, network: .custom(passphrase: config.passphrase)) == Self.cetes)
        #expect(!assets.contains { $0.contract == Self.otherCetes })
    }

    @Test("Activity : un transfert du vrai CETES est une ligne « CETES » ; le même transfert d'un autre « CETES » est ignoré")
    func activityByAddress() throws {
        let map = Dictionary(uniqueKeysWithValues: try SACClient.stellarAssets(config: .testnet).map { ($0.contract, $0.code) })
        func records(_ contract: String) -> [ActivityRecord] {
            ChainActivityHistory.records(
                from: [ActivityHistoryTests.transfer(contract: contract, from: ActivityHistoryTests.adminTopic, to: ActivityHistoryTests.accountTopic)],
                account: ActivityHistoryTests.account, drawers: [ActivityHistoryTests.account], assets: map, known: []
            )
        }
        let row = try #require(records(Self.cetes).first)
        #expect(row.assetCode == "CETES")
        #expect(row.amount == Decimal(string: "2.5"))
        #expect(records(Self.otherCetes).isEmpty, "Un code ne suffit jamais : seule l'adresse du contrat compte")
    }

    @Test("CETES ne s'envoie pas : absent d'Envoyer et de Move, ni « Pay again » ni « Send back » ; présent dans le swap")
    func notSendable() {
        #expect(SendAsset.sendable == [.usdc, .xlm])
        #expect(!SendAsset.cetes.isSendable)
        #expect(SendAsset.swappable == [.xlm, .usdc, .cetes, .usdy, .solvbtc, .xsolvbtc])
        #expect(!SendAsset.usdy.isSendable, "L'USDY d'Ondo non plus : swap seulement")
        let received = ActivityRecord(
            id: "r", event: .transfer, hash: "r", from: ActivityHistoryTests.admin, to: ActivityHistoryTests.account,
            assetCode: "CETES", amount: 10, at: .now, isLocal: false
        )
        #expect(ActivityViewModel.prefill(for: received, kind: .received) == nil)
        let usdc = ActivityRecord(
            id: "u", event: .transfer, hash: "u", from: ActivityHistoryTests.admin, to: ActivityHistoryTests.account,
            assetCode: "USDC", amount: 10, at: .now, isLocal: false
        )
        #expect(ActivityViewModel.prefill(for: usdc, kind: .received)?.asset == .usdc)
    }

    @Test("Saisie et affichage : 7 décimales tapables (Max rend tout le solde), affichage à 2 décimales tronquées")
    func formatting() {
        let locale = Locale(identifier: "en_US")
        #expect(SendAsset.cetes.maxFractionDigits == 7)
        #expect(SendAsset.cetes.formattedWithCode(Decimal(string: "131.3418012")!, locale: locale) == "131.3418012 CETES")
        #expect(SendAsset.cetes.displayedWithCode(Decimal(string: "1820.4099")!, locale: locale) == "1,820.4 CETES")
        #expect(SendAsset(code: "CETES") == .cetes)
    }
}

/// Soroswap : la paire est demandée à la factory d'abord (`pairExists` du terminal).
struct SoroswapPairExistsTests {
    private final class Reader: ContractReading {
        var exists = false
        private(set) var calls: [String] = []
        func readValue(contract: String, function: String, arguments: [SCValXDR]) async throws -> SCValXDR {
            calls.append(function)
            if function == "pair_exists" { return .bool(exists) }
            // Ce que rend vraiment le router pour une paire absente (XLM/CETES, testnet, 2026-10-15).
            throw StellarError.simulationFailed("HostError: Error(Storage, MissingValue) … [\"contract call failed\", get_reserves, []]")
        }
    }

    @Test("Pas de paire XLM/CETES chez Soroswap : pas de route (jamais une panne), le router n'est pas appelé")
    func noPair() async throws {
        let reader = Reader()
        let adapter = SoroswapAdapter(contracts: IntegrationConfig.testnet.soroswap, reader: reader)
        let request = SwapRequest(
            assetIn: IntegrationAsset(code: "XLM", contract: ActivityHistoryTests.xlmSAC),
            assetOut: IntegrationAsset(code: "CETES", contract: CetesAssetTests.cetes), amountIn: 10_000_000
        )
        #expect(try await adapter.quote(request) == nil)
        #expect(reader.calls == ["pair_exists"])
        reader.exists = true
        await #expect(throws: StellarError.self) { try await adapter.quote(request) }
    }
}

/// Swap à trois actifs (feuille E3p) : l'actif de l'autre côté échange les deux, un troisième ne remplace qu'un côté.
struct SwapThreeAssetsTests {
    @Test("Choisir CETES à recevoir ne touche pas au donné ; choisir le reçu comme donné échange les deux")
    func choose() async {
        let service = MockSwapService(delay: .zero)
        let model = SwapFlowModel(service: service, quoteDebounce: .zero)
        await model.loadIfNeeded()
        #expect((model.given, model.received) == (.xlm, .usdc))
        model.choose(.cetes, for: .received)
        #expect((model.given, model.received) == (.xlm, .cetes))
        model.choose(.cetes, for: .given)
        #expect((model.given, model.received) == (.cetes, .xlm))
        model.choose(.usdc, for: .received)
        #expect((model.given, model.received) == (.cetes, .usdc))
        model.choose(.cetes, for: .given)
        #expect((model.given, model.received) == (.cetes, .usdc), "Le même actif : rien ne change")
    }

    @Test("Devis USDC → CETES du service factice : le taux de la maquette (1 USDC ≈ 18,28 CETES)")
    func mockRate() async throws {
        let service = MockSwapService(delay: .zero)
        let quote = try await service.quote(given: .usdc, received: .cetes, amount: 50)
        #expect(quote.expectedOut == Decimal(string: "914"))
    }
}
