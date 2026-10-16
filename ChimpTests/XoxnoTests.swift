import Foundation
import stellarsdk
import Testing
@testable import ChimpDAO

/// Phase 7 : XOXNO, dépôt et retrait d'USDC (décisions de Barth du 2026-10-16). Vecteurs relevés sur testnet le 2026-10-16
/// par simulation (rien de signé) : l'arbre d'un dépôt de 1 USDC depuis le Main `CASBWZTE…D3RP`, celui d'un retrait de
/// 0,1 USDC de la position n°26 (compte `CC2F5OMM…VUIN`), et l'état du marché USDC (réserve et profil de risque 1).
struct XoxnoTests {
    private let market = IntegrationConfig.testnet.xoxno
    private let usdc = "CBIELTK6YBZJU5UP2WWQEUCYKLPU6AUNZ2BQ4WWFEIE3USCIHMXQDAMA"
    private let main = "CASBWZTE3GU4VVBC2Q3V6VXCHTG7VLHG45AJXEJ64IVNQSDLEDRBD3RP"
    private let owner26 = "CC2F5OMM2QV2FMR6BF3PBCXHHR4Q3IOSKT7XYPKR4XXEJW6VWWLNVUIN"

    static let supplyAuth = "AAAAAgAAAAEkG2Zk2anK1CLUN19W4jzN+qzm50CbkT7iKthIayDiEXYJA+IWhNY7AAAAAAAAAAEAAAAAAAAAAa8bJ9JFNWeUhllMmqJvX38AYQxDvOAzTQmaOEpCVopaAAAABnN1cHBseQAAAAAABAAAABIAAAABJBtmZNmpytQi1DdfVuI8zfqs5udAm5E+4irYSGsg4hEAAAAFAAAAAAAAAAAAAAADAAAAAQAAABAAAAABAAAAAQAAABAAAAABAAAAAgAAABEAAAABAAAAAgAAAA8AAAAFYXNzZXQAAAAAAAASAAAAAVBFzV7Acpp2j9WtAlBYUt9PAo3Ogw5axSIJukhIOy8BAAAADwAAAAZodWJfaWQAAAAAAAMAAAABAAAACgAAAAAAAAAAAAAAAACYloAAAAABAAAAAAAAAAFQRc1ewHKado/VrQJQWFLfTwKNzoMOWsUiCbpISDsvAQAAAAh0cmFuc2ZlcgAAAAMAAAASAAAAASQbZmTZqcrUItQ3X1biPM36rObnQJuRPuIq2EhrIOIRAAAAEgAAAAFkYvoOgBjyhJWWHkgeWYoOn0RGo8URspffhkVGxQO0/AAAAAoAAAAAAAAAAAAAAAAAmJaAAAAAAA=="
    static let withdrawAuth = "AAAAAgAAAAG0XrmM1Cuisj4JdvCK5zx5DaHSVP98PVHl7kTb1bWW2mgvE8VhC5vSAAAAAAAAAAEAAAAAAAAAAa8bJ9JFNWeUhllMmqJvX38AYQxDvOAzTQmaOEpCVopaAAAACHdpdGhkcmF3AAAABAAAABIAAAABtF65jNQrorI+CXbwiuc8eQ2h0lT/fD1R5e5E29W1ltoAAAAFAAAAAAAAABoAAAAQAAAAAQAAAAEAAAAQAAAAAQAAAAIAAAARAAAAAQAAAAIAAAAPAAAABWFzc2V0AAAAAAAAEgAAAAFQRc1ewHKado/VrQJQWFLfTwKNzoMOWsUiCbpISDsvAQAAAA8AAAAGaHViX2lkAAAAAAADAAAAAQAAAAoAAAAAAAAAAAAAAAAAD0JAAAAAAQAAAAA="
    static let syncData = "AAAAEQAAAAEAAAACAAAADwAAAAZwYXJhbXMAAAAAABEAAAABAAAADQAAAA8AAAAOYXNzZXRfZGVjaW1hbHMAAAAAAAMAAAAHAAAADwAAAAhhc3NldF9pZAAAABIAAAABUEXNXsBymnaP1a0CUFhS308Cjc6DDlrFIgm6SEg7LwEAAAAPAAAAEGJhc2VfYm9ycm93X3JhdGUAAAAKAAAAAAAIRZUWFAFISgAAAAAAAA8AAAANZmxhc2hsb2FuX2ZlZQAAAAAAAAMAAAAJAAAADwAAABBpc19mbGFzaGxvYW5hYmxlAAAAAAAAAAEAAAAPAAAAD21heF9ib3Jyb3dfcmF0ZQAAAAAKAAAAAAZ2XHk/oQB50AAAAAAAAA8AAAAPbWF4X3V0aWxpemF0aW9uAAAAAAoAAAAAAxHSUzFsedN2AAAAAAAADwAAAA9taWRfdXRpbGl6YXRpb24AAAAACgAAAAABnZceT+hAHnQAAAAAAAAPAAAAE29wdGltYWxfdXRpbGl6YXRpb24AAAAACgAAAAAC4DDUrPRyIboAAAAAAAAPAAAADnJlc2VydmVfZmFjdG9yAAAAAAADAAAD6AAAAA8AAAAGc2xvcGUxAAAAAAAKAAAAAAAhFlRYUAUhKAAAAAAAAA8AAAAGc2xvcGUyAAAAAAAKAAAAAABSt9LcyAzS5AAAAAAAAA8AAAAGc2xvcGUzAAAAAAAKAAAAAATYxVrvuMBbXAAAAAAAAA8AAAAFc3RhdGUAAAAAAAARAAAAAQAAAAcAAAAPAAAADGJvcnJvd19pbmRleAAAAAoAAAAAAz4dfV5BsIPvHTXEAAAADwAAAAhib3Jyb3dlZAAAAAoAAAAKpI9Njte1UbslfV3AAAAADwAAAARjYXNoAAAACgAAAAAAAAAAAAAAA8yQcxEAAAAPAAAADmxhc3RfdGltZXN0YW1wAAAAAAAFAAABoTxicZgAAAAPAAAAB3JldmVudWUAAAAACgAAAAAAtgYwMKnOJgnjk9AAAAAPAAAACHN1cHBsaWVkAAAACgAAAB8/7Ck1D/5EK5GKlbIAAAAPAAAADHN1cHBseV9pbmRleAAAAAoAAAAAAzvch87Q7FXMGm+N"
    static let spokeAsset = "AAAAEQAAAAEAAAALAAAADwAAAApib3Jyb3dfY2FwAAAAAAAKAAAAAAAAAAAAAAAXSHboAAAAAA8AAAAGZnJvemVuAAAAAAAAAAAAAAAAAA8AAAANaXNfYm9ycm93YWJsZQAAAAAAAAAAAAABAAAADwAAABNpc19jb2xsYXRlcmFsaXphYmxlAAAAAAAAAAABAAAADwAAABFsaXF1aWRhdGlvbl9ib251cwAAAAAAAAMAAADIAAAADwAAABBsaXF1aWRhdGlvbl9mZWVzAAAAAwAAAGQAAAAPAAAAFWxpcXVpZGF0aW9uX3RocmVzaG9sZAAAAAAAAAMAACZIAAAADwAAAA1sb2FuX3RvX3ZhbHVlAAAAAAAAAwAAJeUAAAAPAAAACG5vX3NlaXplAAAAAAAAAAAAAAAPAAAABnBhdXNlZAAAAAAAAAAAAAAAAAAPAAAACnN1cHBseV9jYXAAAAAAAAoAAAAAAAAAAAAAABdIdugA"
    static let spokeUsage = "AAAAEQAAAAEAAAACAAAADwAAABNib3Jyb3dlZF9zY2FsZWRfcmF5AAAAAAoAAAAKFoWqag8g0U0qD3hVAAAADwAAABNzdXBwbGllZF9zY2FsZWRfcmF5AAAAAAoAAAAcaGBjTfZ6BmRRYzUE"

    private func scVal(_ base64: String) throws -> SCValXDR {
        try XDRDecoder.decode(SCValXDR.self, data: try #require(Data(base64Encoded: base64)))
    }

    private func root(_ base64: String) throws -> SorobanAuthorizedInvocationXDR {
        try XDRDecoder.decode(SorobanAuthorizationEntryXDR.self, data: try #require(Data(base64Encoded: base64))).rootInvocation
    }

    private func adapter(reader: ContractReading = FakeReader(), ledger: XoxnoLedgerReading = FakeLedger()) -> XoxnoAdapter {
        XoxnoAdapter(market: market, asset: IntegrationAsset(code: "USDC", contract: usdc), reader: reader, ledger: ledger)
    }

    // MARK: Autorisations

    @Test("Dépôt : l'arbre déclaré est exactement celui de la simulation (supply, puis transfer du tiroir vers la réserve)")
    func supplyTree() throws {
        let call = try adapter().supplyCall(from: main, units: TokenAmount(10_000_000))
        let expected = try DeclaredInvocations.invocation(of: call, from: main, shape: XoxnoAuthShape(market: market, asset: usdc))
        #expect(AuthTreeCheck.mismatch(try root(Self.supplyAuth), expected: expected) == nil)
        // Un autre montant ou un autre tiroir : refusé.
        let other = try adapter().supplyCall(from: main, units: TokenAmount(10_000_001))
        let wrong = try DeclaredInvocations.invocation(of: other, from: main, shape: XoxnoAuthShape(market: market, asset: usdc))
        #expect(AuthTreeCheck.mismatch(try root(Self.supplyAuth), expected: wrong) != nil)
    }

    @Test("Retrait : l'arbre déclaré est exactement celui de la simulation (withdraw seul, rien n'est pris au tiroir)")
    func withdrawTree() throws {
        let position = XoxnoPosition(accountID: 26, holder: owner26, status: .live(value: 200_169_269, spokeID: 3, hasDebt: false))
        let call = try adapter().withdrawCall(position: position, units: TokenAmount(1_000_000), all: false)
        let expected = try DeclaredInvocations.invocation(of: call, from: owner26, shape: XoxnoAuthShape(market: market, asset: usdc))
        #expect(expected.subInvocations.isEmpty)
        #expect(AuthTreeCheck.mismatch(try root(Self.withdrawAuth), expected: expected) == nil)
    }

    @Test("F4 : un dépôt ne va jamais dans une position existante, même annoncée « à soi » par le RPC (account_id = 0)")
    func depositAlwaysOpensANewPosition() throws {
        // Le RPC annonce la position n°26 (celle d'un autre) comme une position du Main, vivante, sans dette.
        let announced = XoxnoPosition(accountID: 26, holder: main, status: .live(value: 1, spokeID: 1, hasDebt: false))
        _ = announced  // l'adaptateur ne prend plus aucun numéro de position pour un dépôt
        let call = try adapter().supplyCall(from: main, units: TokenAmount(10_000_000))
        #expect(XoxnoCalls.decode(call, market: market, asset: usdc)?.accountID == 0)
    }

    @Test("Une position avec dette ou à renouveler ne se retire pas")
    func noMoveWithDebtOrExpired() {
        for status in [XoxnoPosition.Status.live(value: 10, spokeID: 1, hasDebt: true), .needsRenewal] {
            let position = XoxnoPosition(accountID: 54, holder: main, status: status)
            #expect(throws: YieldError.self) { try adapter().withdrawCall(position: position, units: TokenAmount(1), all: false) }
        }
    }

    // MARK: Bornes

    @Test("Bornes : dépôt exact ; retrait exact ; « tout » avec la valeur relue comme minimum affiché")
    func terms() throws {
        let deposit = try adapter().terms(of: try adapter().supplyCall(from: main, units: TokenAmount(10_000_000)))
        #expect(deposit.action == .deposit && deposit.amountIn == 10_000_000 && deposit.assetIn == usdc && deposit.minimumOut == nil)
        let position = XoxnoPosition(accountID: 54, holder: main, status: .live(value: 30_000_000, spokeID: 1, hasDebt: false))
        let partial = try adapter().terms(of: try adapter().withdrawCall(position: position, units: TokenAmount(1_000_000), all: false))
        #expect(partial.action == .withdraw && partial.amountIn == 1_000_000 && partial.minimumOut == 1_000_000 && partial.assetOut == usdc)
        let all = try adapter().withdrawCall(position: position, units: TokenAmount(0), all: true)
        #expect(try adapter().terms(of: all, allValue: TokenAmount(30_000_000)).minimumOut == 30_000_000)
        #expect(try adapter().terms(of: all).minimumOut == nil)
    }

    @Test("Appels refusés : autre actif, autre hub, deux actifs, retrait vers un autre destinataire, autre contrat")
    func decodeRefusals() throws {
        let good = try XoxnoCalls.withdraw(market: market, asset: usdc, from: main, accountID: 54, units: 5)
        #expect(XoxnoCalls.decode(good, market: market, asset: usdc) != nil)
        let otherAsset = try XoxnoCalls.withdraw(market: market, asset: "CDLZFC3SYJYDZT7K67VZ75HPJVIEUVNIXF47ZG2FB2RMQQVU2HHGCYSC", from: main, accountID: 54, units: 5)
        #expect(XoxnoCalls.decode(otherAsset, market: market, asset: usdc) == nil)
        let otherHub = IntegrationConfig.Xoxno(controller: market.controller, pool: market.pool, positionNFT: market.positionNFT, assetCode: "USDC", hubID: 2, spokeID: 1, name: "x")
        #expect(XoxnoCalls.decode(try XoxnoCalls.withdraw(market: otherHub, asset: usdc, from: main, accountID: 54, units: 5), market: market, asset: usdc) == nil)
        var arguments = good.arguments
        arguments[3] = try ContractArgument.address(owner26)
        #expect(XoxnoCalls.decode(ContractCall(contract: market.controller, function: "withdraw", arguments: arguments), market: market, asset: usdc) == nil)
        arguments = good.arguments
        let key = try XoxnoCalls.hubAssetKey(asset: usdc, hubID: 1)
        arguments[2] = .vec([.vec([key, ContractArgument.i128(1)]), .vec([key, ContractArgument.i128(1)])])
        #expect(XoxnoCalls.decode(ContractCall(contract: market.controller, function: "withdraw", arguments: arguments), market: market, asset: usdc) == nil)
        #expect(XoxnoCalls.decode(ContractCall(contract: market.pool, function: "withdraw", arguments: good.arguments), market: market, asset: usdc) == nil)
    }

    // MARK: Marché

    @Test("État du marché USDC relevé le 2026-10-16 : déposé et prêté égaux aux vues de la réserve, retirable sous la limite de 95 %")
    func marketState() throws {
        let state = try XoxnoAdapter.state(sync: try scVal(Self.syncData), spokeAsset: try scVal(Self.spokeAsset), spokeUsage: try scVal(Self.spokeUsage), asset: usdc)
        // `get_supplied_amount` = 24 778 939 190, `get_borrowed_amount` = 8 462 018 598 (même moment).
        #expect(abs(state.supplied - 24_778_939_190) <= 1)
        #expect(abs(state.borrowed - 8_462_018_598) <= 1)
        #expect(state.cash == 16_316_920_593)
        #expect(state.maxUtilization == 950_000_000_000_000_000_000_000_000)
        #expect(!state.paused && !state.frozen)
        #expect(state.supplyCap == 100_000_000_000)
        #expect(state.remainingCap > 70_000_000_000 && state.remainingCap < 80_000_000_000)
        // Déposé − prêté ÷ 0,95 ≈ 1 587,15 USDC, moins la marge (1 % du prêté ≈ 8,46 USDC) ; l'argent disponible est plus grand.
        #expect(state.marketWithdrawable > 15_786_000_000 && state.marketWithdrawable < 15_787_000_000)
        #expect(state.withdrawable(position: 10_000_000) == 10_000_000)
        #expect(state.withdrawable(position: 50_000_000_000) == state.marketWithdrawable)
        #expect(throws: (any Error).self) { try XoxnoAdapter.state(sync: try scVal(Self.syncData), spokeAsset: try scVal(Self.spokeAsset), spokeUsage: try scVal(Self.spokeUsage), asset: "CDLZFC3SYJYDZT7K67VZ75HPJVIEUVNIXF47ZG2FB2RMQQVU2HHGCYSC") }
    }

    @Test("Retirable : limité par l'argent disponible, par la limite d'utilisation, jamais négatif")
    func withdrawable() {
        func state(supplied: Int128, borrowed: Int128, cash: Int128) -> XoxnoMarketState {
            XoxnoMarketState(supplied: supplied, borrowed: borrowed, cash: cash, maxUtilization: 950_000_000_000_000_000_000_000_000,
                             paused: false, frozen: false, supplyCap: 0, suppliedInSpoke: 0)
        }
        // Rien de prêté : tout l'argent, moins 1 unité de marge.
        #expect(state(supplied: 1_000, borrowed: 0, cash: 1_000).marketWithdrawable == 999)
        // 950 prêtés sur 1 000 : la limite est atteinte, rien ne sort.
        #expect(state(supplied: 1_000, borrowed: 950, cash: 50).marketWithdrawable == 0)
        // Prêté 100 : 1 000 − ⌈100 / 0,95⌉ = 894, l'argent (900) est plus grand ; marge 2.
        #expect(state(supplied: 1_000, borrowed: 100, cash: 900).marketWithdrawable == 892)
        // L'argent disponible plus petit que la limite.
        #expect(state(supplied: 1_000, borrowed: 100, cash: 300).marketWithdrawable == 298)
    }

    @Test("a × b ÷ c sur 256 bits : grands nombres, arrondi, dépassement")
    func mulDiv() {
        let ray: Int128 = 1_000_000_000_000_000_000_000_000_000
        #expect(XoxnoMath.mulDiv(2_475_856_094_650_223_924_285_383_808_434, 1_000_823_078_660_650_620_428_119_949, ray, roundUp: false) == 2_477_893_918_968_572_306_313_949_277_259)
        #expect(XoxnoMath.mulDiv(10, 1, 3, roundUp: false) == 3)
        #expect(XoxnoMath.mulDiv(10, 1, 3, roundUp: true) == 4)
        #expect(XoxnoMath.mulDiv(Int128.max, Int128.max, 1, roundUp: false) == nil)
        #expect(XoxnoMath.mulDiv(-1, 1, 1, roundUp: false) == nil)
    }

    // MARK: Positions

    @Test("Données vivantes, expirées ou absentes")
    func liveness() {
        #expect(XoxnoAdapter.isLive(meta: 200, supply: 200, latest: 100))
        #expect(XoxnoAdapter.isLive(meta: 200, supply: nil, latest: 100))
        #expect(!XoxnoAdapter.isLive(meta: 99, supply: 200, latest: 100))
        #expect(!XoxnoAdapter.isLive(meta: 200, supply: 99, latest: 100))
        #expect(!XoxnoAdapter.isLive(meta: nil, supply: nil, latest: 100))
    }

    @Test("Positions retrouvées par le jeton : une lue, une à renouveler (jamais à zéro, jamais disparue)")
    func positions() async throws {
        let reader = FakeReader()
        reader.answers = [
            "balance": .u32(2),
            "get_owner_token_id:0": .u32(26),
            "get_owner_token_id:1": .u32(5),
            "get_account_attributes": .map([SCMapEntryXDR(key: .symbol("mode"), val: .u32(0)), SCMapEntryXDR(key: .symbol("spoke_id"), val: .u32(1))]),
            "get_collateral_amount": ContractArgument.i128(200_169_269),
            "get_total_borrow_usd": ContractArgument.i128(0),
        ]
        let ledger = FakeLedger()
        ledger.latest = 5_223_000
        ledger.lives = [
            try XoxnoAdapter.entryKey("AccountMeta", id: 26, controller: market.controller): 6_846_705,
            try XoxnoAdapter.entryKey("SupplyPositions", id: 26, controller: market.controller): 6_846_705,
            try XoxnoAdapter.entryKey("AccountMeta", id: 5, controller: market.controller): 5_000_000,
            try XoxnoAdapter.entryKey("SupplyPositions", id: 5, controller: market.controller): 5_000_000,
        ]
        let positions = try await adapter(reader: reader, ledger: ledger).positions(holder: main)
        #expect(positions == [
            XoxnoPosition(accountID: 26, holder: main, status: .live(value: 200_169_269, spokeID: 1, hasDebt: false)),
            XoxnoPosition(accountID: 5, holder: main, status: .needsRenewal),
        ])
        #expect(!reader.calls.contains("get_collateral_amount:5"))
    }

    @Test("Aucun jeton : aucune position, sans autre lecture")
    func noPosition() async throws {
        let reader = FakeReader()
        reader.answers = ["balance": .u32(0)]
        #expect(try await adapter(reader: reader).positions(holder: main).isEmpty)
        #expect(reader.calls == ["balance"])
    }

    @Test("Refus traduits : liquidité, utilisation, pause, gel, plafond")
    func errors() {
        func error(_ code: Int) -> YieldError? {
            XoxnoAdapter.yieldError(for: StellarError.simulationFailed("HostError: Error(Contract, #\(code))"))
        }
        #expect(error(112) == .notEnoughLiquidity)
        #expect(error(127) == .notEnoughLiquidity)
        #expect(error(315) == .vaultUnavailable)
        #expect(error(316) == .vaultUnavailable)
        #expect(error(311) == .capReached)
        #expect(error(10) == .insufficientBalance)
        #expect(error(999) == nil)
    }
}

private final class FakeReader: ContractReading {
    var answers: [String: SCValXDR] = [:]
    private(set) var calls: [String] = []

    func readValue(contract: String, function: String, arguments: [SCValXDR]) async throws -> SCValXDR {
        var name = function
        if function == "get_owner_token_id", case .u32(let index) = arguments.last { name += ":\(index)" }
        if function == "get_collateral_amount", case .u64(let id) = arguments.first { name += ":\(id)" }
        calls.append(name)
        if let answer = answers[name] ?? answers[function] { return answer }
        throw StellarError.rpc("no answer for \(name)")
    }
}

private final class FakeLedger: XoxnoLedgerReading {
    var latest: UInt32 = 0
    var lives: [String: UInt32] = [:]

    func latestLedger() async throws -> UInt32 { latest }

    func liveUntil(_ base64Keys: [String]) async throws -> [String: UInt32] {
        lives.filter { base64Keys.contains($0.key) }
    }
}
