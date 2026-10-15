import Foundation
import stellarsdk
import Testing
@testable import ChimpDAO

/// Tranche 2, phase 4, étape 1 : l'adaptateur DeFindex réel, avec les réponses du testnet rejouées.
/// Lues le 2026-10-15 (simulations, rien de signé), vault XLM `CCLV4H7W…GFSF6` : actif XLM (SAC `CDLZFC3S…`), une
/// stratégie « XLM Blend Strategy » `CDVLOSPJ…` ; fonds gérés 49 557,2426222 XLM (tout idle, rien d'investi) ;
/// 29,7164659 parts émises ; 1 part = 1 667,6694593 XLM.
struct DeFindexAdapterTests {
    private let account = "CCDO6J7WOGPTKZA73FWECCIJ75TTOMHMCWLEGPYWIFCNSINM63UJDDYB"
    private let pocket = "CCGYGX2HBP464WZWXHHFOMS25CMIBKH3PUKOKRESOM3Z2W4UJRLLJ72Q"
    private let xlm = IntegrationAsset(code: "XLM", contract: "CDLZFC3SYJYDZT7K67VZ75HPJVIEUVNIXF47ZG2FB2RMQQVU2HHGCYSC")
    private let vaultID = "CCLV4H7WTLJQ7ATLHBBQV2WW3OINF3FOY5XZ7VPHZO7NH3D2ZS4GFSF6"
    private var venue: YieldVenue { YieldVenue(id: vaultID, name: "XLM vault", asset: xlm, underlyingProtocols: ["DeFindex", "Blend"]) }

    private static let assets = "AAAAEAAAAAEAAAABAAAAEQAAAAEAAAACAAAADwAAAAdhZGRyZXNzAAAAABIAAAAB15KLcsJwPM/q9+uf9O9NUEpVqLl5/JtFDqLIQrTRzmEAAAAPAAAACnN0cmF0ZWdpZXMAAAAAABAAAAABAAAAAQAAABEAAAABAAAAAwAAAA8AAAAHYWRkcmVzcwAAAAASAAAAAeq3Sel8HTD7IrO7WRpuWZip3kW2J0f3+jTe11r8L/19AAAADwAAAARuYW1lAAAADgAAABJYTE0gQmxlbmQgU3RyYXRlZ3kAAAAAAA8AAAAGcGF1c2VkAAAAAAAAAAAAAA=="
    private static let funds = "AAAAEAAAAAEAAAABAAAAEQAAAAEAAAAFAAAADwAAAAVhc3NldAAAAAAAABIAAAAB15KLcsJwPM/q9+uf9O9NUEpVqLl5/JtFDqLIQrTRzmEAAAAPAAAAC2lkbGVfYW1vdW50AAAAAAoAAAAAAAAAAAAAAHNiax3uAAAADwAAAA9pbnZlc3RlZF9hbW91bnQAAAAACgAAAAAAAAAAAAAAAAAAAAAAAAAPAAAAFHN0cmF0ZWd5X2FsbG9jYXRpb25zAAAAEAAAAAEAAAABAAAAEQAAAAEAAAADAAAADwAAAAZhbW91bnQAAAAAAAoAAAAAAAAAAAAAAAAAAAAAAAAADwAAAAZwYXVzZWQAAAAAAAAAAAAAAAAADwAAABBzdHJhdGVneV9hZGRyZXNzAAAAEgAAAAHqt0npfB0w+yKzu1kablmYqd5FtidH9/o03tda/C/9fQAAAA8AAAAMdG90YWxfYW1vdW50AAAACgAAAAAAAAAAAAAAc2JrHe4="
    private static let supply = "AAAACgAAAAAAAAAAAAAAABG2X3M="
    /// Arbres relevés par simulation : dépôt de 1 XLM depuis le Main, et retrait de 5 000 unités de parts (lot du router
    /// dépôt puis retrait, la jambe `withdraw`).
    private static let depositRoot = "AAAAAAAAAAGXXh/2mtMPgms4Qwrq1tuQ0uyux2+f1efLvtPsesy4YgAAAAdkZXBvc2l0AAAAAAQAAAAQAAAAAQAAAAEAAAAKAAAAAAAAAAAAAAAAAJiWgAAAABAAAAABAAAAAQAAAAoAAAAAAAAAAAAAAAAAmJaAAAAAEgAAAAGG7yf2cZ81ZB/ZbEEJCf9nNzDsFZZDPxZBRNkhrPbokQAAAAAAAAABAAAAAQAAAAAAAAAB15KLcsJwPM/q9+uf9O9NUEpVqLl5/JtFDqLIQrTRzmEAAAAIdHJhbnNmZXIAAAADAAAAEgAAAAGG7yf2cZ81ZB/ZbEEJCf9nNzDsFZZDPxZBRNkhrPbokQAAABIAAAABl14f9prTD4JrOEMK6tbbkNLsrsdvn9Xny77T7HrMuGIAAAAKAAAAAAAAAAAAAAAAAJiWgAAAAAA="
    private static let withdrawLeg = "AAAAAAAAAAGXXh/2mtMPgms4Qwrq1tuQ0uyux2+f1efLvtPsesy4YgAAAAh3aXRoZHJhdwAAAAMAAAAKAAAAAAAAAAAAAAAAAAATiAAAABAAAAABAAAAAQAAAAoAAAAAAAAAAAAAAAAAAAABAAAAEgAAAAGG7yf2cZ81ZB/ZbEEJCf9nNzDsFZZDPxZBRNkhrPbokQAAAAA="

    static let totalManaged: Int128 = 495_572_426_222
    static let totalSupply: Int128 = 297_164_659

    /// Le vault rejoué. `balances` : parts de chaque détenteur ; la valeur des parts suit les fonds (comme le vault).
    private final class VaultReader: ContractReading {
        var balances: [String: Int128] = [:]
        var assets = DeFindexAdapterTests.assets
        /// Remplace la réponse de `get_asset_amounts_per_shares` (valeur corrompue, par exemple).
        var valueOverride: Int128?
        var failure: (String, Error)?
        private(set) var calls: [String] = []

        func readValue(contract: String, function: String, arguments: [SCValXDR]) async throws -> SCValXDR {
            calls.append(function)
            if let failure, failure.0 == function { throw failure.1 }
            switch function {
            case "get_assets": return try SCValXDR(xdr: assets)
            case "fetch_total_managed_funds": return try SCValXDR(xdr: DeFindexAdapterTests.funds)
            case "total_supply": return try SCValXDR(xdr: DeFindexAdapterTests.supply)
            case "balance":
                let holder = try arguments[0].address?.toStrKey() ?? ""
                return ContractArgument.i128(balances[holder] ?? 0)
            case "get_asset_amounts_per_shares":
                let shares = ContractArgument.int128(arguments[0]) ?? 0
                let value = valueOverride ?? shares * DeFindexAdapterTests.totalManaged / DeFindexAdapterTests.totalSupply
                return .vec([ContractArgument.i128(value)])
            default:
                throw StellarError.rpc("no scripted reply for \(function)")
            }
        }
    }

    private func adapter(_ reader: VaultReader) -> DeFindexAdapter {
        DeFindexAdapter(vaults: [venue], reader: reader)
    }

    private func base64(_ invocation: SorobanAuthorizedInvocationXDR) throws -> String {
        Data(try XDREncoder.encode(invocation)).base64EncodedString()
    }

    // MARK: Lecture

    @Test("État du vault : fonds gérés, rien d'investi, parts émises ; 1 part ≈ 1 667,67 XLM ; 1 XLM achète 5 996 unités de parts")
    func vaultState() async throws {
        let state = try await adapter(VaultReader()).state(of: venue)
        #expect(state == DeFindexAdapter.VaultState(totalManaged: 495_572_426_222, invested: 0, totalSupply: 297_164_659))
        #expect(state.shares(for: 10_000_000) == 5_996, "Comme la valeur rendue par la simulation du dépôt (5 996)")
        #expect(state.value(of: 10_000_000) == 16_676_694_593, "Exactement get_asset_amounts_per_shares(1e7) du testnet")
    }

    @Test("Positions : seulement là où il y a des parts ; valeur = get_asset_amounts_per_shares, vérifiée")
    func discover() async throws {
        let reader = VaultReader()
        reader.balances = [account: 300_000]
        let positions = try await adapter(reader).discover(holder: account)
        #expect(positions == [YieldPosition(protocolID: "defindex", venueID: vaultID, holder: account, shares: 300_000, value: 300_000 * Self.totalManaged / Self.totalSupply)])
        #expect(try await adapter(reader).discover(holder: pocket).isEmpty)
    }

    @Test("Valeur invraisemblable (plus que le vault entier, ou loin du prix d'une part) : refusée")
    func implausibleValue() async throws {
        let reader = VaultReader()
        reader.balances = [account: 300_000]
        reader.valueOverride = Self.totalManaged + 1
        await #expect(throws: YieldError.implausibleValue) { _ = try await adapter(reader).discover(holder: account) }
        reader.valueOverride = 300_000 * Self.totalManaged / Self.totalSupply * 2
        await #expect(throws: YieldError.implausibleValue) { _ = try await adapter(reader).discover(holder: account) }
    }

    @Test("Actif du vault vérifié une fois : un autre actif est refusé avant tout appel")
    func assetCheck() async throws {
        let reader = VaultReader()
        _ = try await adapter(reader).depositCall(venue: venue, amount: 10_000_000, authorizer: account)
        let shared = adapter(reader)
        _ = try await shared.depositCall(venue: venue, amount: 1, authorizer: account)
        _ = try await shared.depositCall(venue: venue, amount: 2, authorizer: account)
        #expect(reader.calls.filter { $0 == "get_assets" }.count == 2, "Une fois par adaptateur")

        let foreign = VaultReader()
        foreign.assets = Data(try XDREncoder.encode(SCValXDR.vec([SCValXDR.map([SCMapEntryXDR(
            key: .symbol("address"), val: try ContractArgument.address("CBIELTK6YBZJU5UP2WWQEUCYKLPU6AUNZ2BQ4WWFEIE3USCIHMXQDAMA")
        )])]))).base64EncodedString()
        await #expect(throws: YieldError.wrongAsset) { _ = try await adapter(foreign).depositCall(venue: venue, amount: 1, authorizer: account) }
    }

    // MARK: Arbres confirmés sur testnet

    @Test("Dépôt : deposit → transfer(déposant → vault, montant), octet pour octet comme le testnet (Main)")
    func depositTree() async throws {
        let adapter = adapter(VaultReader())
        let call = try await adapter.depositCall(venue: venue, amount: 10_000_000, authorizer: account)
        let trees = try DeclaredInvocations.build(root: call, authorizers: [.account(account)], shape: adapter.authShape())
        #expect(trees.count == 1)
        #expect(try base64(trees[0].invocation) == Self.depositRoot)
        // Depuis le wallet d'une carte : le même arbre, autorisé par la Pocket.
        let fromPocket = try await adapter.depositCall(venue: venue, amount: 10_000_000, authorizer: pocket)
        let pocketTree = try #require(try DeclaredInvocations.build(root: fromPocket, authorizers: [.pocket(pocket)], shape: adapter.authShape()).first)
        #expect(pocketTree.authorizer == CallAuthorizer.pocket(pocket))
        #expect(pocketTree.invocation.subInvocations.count == 1)
    }

    @Test("Retrait : withdraw seul, sans aucune prise, octet pour octet comme le testnet")
    func withdrawTree() throws {
        let call = try DeFindexCalls.withdraw(vault: vaultID, from: account, shares: 5_000, minimumOut: 1)
        let trees = try DeclaredInvocations.build(root: call, authorizers: [.account(account)], shape: adapter(VaultReader()).authShape())
        #expect(trees.count == 1)
        #expect(try base64(trees[0].invocation) == Self.withdrawLeg)
        #expect(trees[0].invocation.subInvocations.isEmpty)
    }

    // MARK: Retrait

    @Test("Retrait partiel : parts au prorata (vers le bas), minimum = valeur attendue − 0,5 %, bornes relues")
    func partialWithdraw() async throws {
        let reader = VaultReader()
        reader.balances = [account: 300_000]
        let adapter = adapter(reader)
        let position = try #require(try await adapter.discover(holder: account).first)
        let call = try await adapter.withdrawCall(position: position, amount: TokenAmount(position.value / 2), all: false)
        let terms = try adapter.terms(of: call)
        #expect(terms.action == .withdraw)
        #expect(terms.amountIn == 149_999)
        let expected = Int128(149_999) * Self.totalManaged / Self.totalSupply
        #expect(terms.minimumOut == Slippage.minimum(of: expected, basisPoints: 50))
        #expect(terms.authorizer == account)
        #expect(terms.assetOut == xlm.contract)
    }

    @Test("Tout retirer : toutes les parts ; à moins de la marge du total, toutes aussi (pas de poussière)")
    func withdrawAll() async throws {
        let reader = VaultReader()
        reader.balances = [account: 300_000]
        let adapter = adapter(reader)
        let position = try #require(try await adapter.discover(holder: account).first)
        #expect(try adapter.terms(of: try await adapter.withdrawCall(position: position, amount: 0, all: true)).amountIn == 300_000)
        // Le Max affiché (tronqué) : à moins d'un cent-millième de la position.
        let nearlyAll = position.value - position.value / 200_000
        #expect(try adapter.terms(of: try await adapter.withdrawCall(position: position, amount: TokenAmount(nearlyAll), all: false)).amountIn == 300_000)
    }

    @Test("Retrait sans parts : refusé avant de construire l'appel")
    func withdrawNothing() async throws {
        let position = YieldPosition(protocolID: "defindex", venueID: vaultID, holder: account, shares: 1, value: 1)
        await #expect(throws: YieldError.notEnoughShares) {
            _ = try await adapter(VaultReader()).withdrawCall(position: position, amount: 1, all: false)
        }
    }

    @Test("dfAmountFor : les vecteurs de defindex.test.ts du terminal, tels quels")
    func dfAmountFor() {
        // 100 parts qui valent 200 de l'actif : prix de la part 2,0.
        let shares: Int128 = 100_0000000, total: Int128 = 200_0000000
        #expect(DeFindexAdapter.shares(balance: shares, wanted: 50_0000000, total: total, dust: 1) == 25_0000000)
        #expect(DeFindexAdapter.shares(balance: shares, wanted: 1, total: total, dust: 0) == 0)
        #expect(DeFindexAdapter.shares(balance: shares, wanted: 3, total: total, dust: 0) == 1)
        #expect(DeFindexAdapter.shares(balance: shares, wanted: total, total: total, dust: 1) == shares)
        #expect(DeFindexAdapter.shares(balance: shares, wanted: total - 99_999, total: total, dust: 100_000) == shares)
        #expect(DeFindexAdapter.shares(balance: shares, wanted: total - 200_000, total: total, dust: 100_000) == shares * (total - 200_000) / total)
        #expect(DeFindexAdapter.shares(balance: 0, wanted: 50, total: 100, dust: 1) == 0)
        #expect(DeFindexAdapter.shares(balance: 100, wanted: 0, total: 100, dust: 1) == 0)
        #expect(DeFindexAdapter.shares(balance: 100, wanted: 50, total: 0, dust: 1) == 0)
        // Marge : max(un quantum du pavé XLM = 1 unité, total / 100 000).
        #expect(DeFindexAdapter.dust(total: 50) == 1)
        #expect(DeFindexAdapter.dust(total: 500_000_000) == 5_000)
    }

    // MARK: Erreurs

    @Test("Refus traduits : #160 minimum, #111 parts, #117 montant, #10 solde du jeton, #144 stratégie en pause")
    func errors() {
        func error(_ code: Int) -> Error { StellarError.simulationFailed("HostError: Error(Contract, #\(code))") }
        #expect(DeFindexAdapter.yieldError(for: error(160)) == .belowMinimum)
        #expect(DeFindexAdapter.yieldError(for: error(111)) == .notEnoughShares)
        #expect(DeFindexAdapter.yieldError(for: error(117)) == .amountTooSmall)
        #expect(DeFindexAdapter.yieldError(for: error(10)) == .insufficientBalance)
        #expect(DeFindexAdapter.yieldError(for: error(144)) == .vaultUnavailable)
        #expect(DeFindexAdapter.yieldError(for: error(114)) == .notEnoughLiquidity)
        #expect(DeFindexAdapter.yieldError(for: error(999)) == nil)
        #expect(DeFindexAdapter.yieldError(for: StellarError.rpc("timeout")) == nil)
    }

    @Test("Panne réseau : remonte telle quelle (jamais « pas de position »)")
    func network() async throws {
        let reader = VaultReader()
        reader.failure = ("balance", StellarError.rpc("timeout"))
        await #expect(throws: StellarError.rpc("timeout")) { _ = try await adapter(reader).discover(holder: account) }
    }
}
