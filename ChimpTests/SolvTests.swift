import Foundation
import stellarsdk
import Testing
@testable import ChimpDAO

/// Solv (xSolvBTC) et les jetons à 8 décimales. Vecteurs : la copie de test du 2026-11-05 (`tools/grow-testnet`), NAV du
/// mainnet relevée le même jour (1,00000000, 8 décimales), formule `calculate_mint_amount` du vault
/// (`solv-finance/SolvBTC-Stellar-Contract`, `vault/src/vault.rs`).
struct SolvTests {
    static let vault = "CAFSPVWXSAVR3DKCJXFHMD4RPYUDL6UW6X5HC6FJV5PU4BPOFC757CXW"
    static let solvBTC = "CBEBG4NVDGZ2UZXXEYZATVF77SFCLG2U2ISOLKJI7RF2TZWBQCAWJ7MU"
    static let xSolvBTC = "CBO6MQP2L2GITZXPU7H7HZJU7JRH7VBBGXOQRU6NVAKXIL35AOWVOCEC"
    static let main = "CASBWZTE3GU4VVBC2Q3V6VXCHTG7VLHG45AJXEJ64IVNQSDLEDRBD3RP"
    static let router = "CAOL3K7VQTDZELQMKTAJB3WUQGL5JLXJKZ2Y44F77NH4CZNLW5I755XI"

    @Test("8 décimales : 0,00123456 SolvBTC = 123 456 unités, et retour ; jamais 10 fois trop ni trop peu")
    func eightDecimals() throws {
        #expect(SendAsset.solvbtc.decimals == 8 && SendAsset.xsolvbtc.decimals == 8 && SendAsset.usdc.decimals == 7)
        #expect(try SwapUnits.units(of: Decimal(string: "0.00123456")!, asset: .solvbtc) == 123_456)
        #expect(try SwapUnits.units(of: 1, asset: .xlm) == 10_000_000)
        #expect(SwapUnits.amount(fromUnits: 123_456, asset: .solvbtc) == Decimal(string: "0.00123456"))
        #expect(SACClient.amount(fromUnits: 247_700, chainDecimals: SendAsset.decimals(code: "SolvBTC")) == Decimal(string: "0.002477"))
        #expect(SendAsset.decimals(code: "USDC") == 7 && SendAsset.decimals(code: "EURC") == 7)
        #expect(throws: SACClient.AmountError.self) { try SACClient.units(of: Decimal(string: "0.000000001")!, keypadDecimals: 8, chainDecimals: 8) }
    }

    @Test("Un devis vers SolvBTC se lit avec ses 8 décimales (quantité attendue et minimum signé)")
    func quoteDecimals() {
        let quote = SwapQuoteSummary(
            protocolID: "soroswap", protocolName: "Soroswap", given: .usdc, received: .solvbtc, amountIn: 10,
            expectedOutUnits: 12_345, route: [.usdc, .solvbtc], routeContracts: [], priceImpactBasisPoints: nil
        )
        #expect(quote.expectedOut == Decimal(string: "0.00012345"))
    }

    @Test("Affichage : un solde de bitcoin garde 6 décimales (0,002477 SolvBTC, pas « < 0.01 »)")
    func display() {
        let locale = Locale(identifier: "en_US")
        #expect(SendAsset.solvbtc.displayed(Decimal(string: "0.0024771")!, locale: locale) == "0.002477")
        #expect(SendAsset.xsolvbtc.displayedWithCode(Decimal(string: "0.0000001")!, locale: locale) == "< 0.000001 xSolvBTC")
        #expect(SendAsset.usdc.displayed(Decimal(string: "62.5")!, locale: locale) == "62.50", "Les autres actifs ne changent pas")
    }

    @Test("Les jetons de Solv sont des actifs du réseau, swappables, jamais envoyables, prix par RedStone seulement")
    func assets() throws {
        let config = ChimpNetworkConfig.testnet
        let assets = try SACClient.stellarAssets(config: config)
        #expect(assets.contains { $0.code == "SolvBTC" && $0.contract == Self.solvBTC })
        #expect(assets.contains { $0.code == "xSolvBTC" && $0.contract == Self.xSolvBTC })
        #expect(SendAsset.swappable.contains(.solvbtc) && SendAsset.swappable.contains(.xsolvbtc))
        #expect(!SendAsset.solvbtc.isSendable && !SendAsset.xsolvbtc.isSendable)
        #expect(PriceOracleConfig.reflector.neverPriced.isSuperset(of: ["SOLVBTC", "XSOLVBTC"]))
        #expect(StablebondWalletPrices(config: config)?.entries.map(\.bond.code) == ["CETES", "USDY", "SolvBTC", "xSolvBTC"])
    }

    @Test("Prix du Wallet rangés en majuscules, comme Reflector : le total trouve « SOLVBTC »")
    func walletPriceKeys() async {
        let price = StablebondPrice(code: "SolvBTC", usd: 80_000, currency: "USD", fiat: 80_000, asOf: .now, source: "RedStone")
        let prices = StablebondWalletPrices(entries: [(bond: .init(code: "SolvBTC", contract: Self.solvBTC), pricing: MockStablebondPricing(result: .price(price)))])
        let usd = await prices.usdPrices(for: ["SolvBTC"])
        #expect(usd == ["SOLVBTC": 80_000])
        #expect(NetWorth.usd([("SolvBTC", Decimal(string: "0.001")!)], prices: usd) == 80)
    }

    @Test("Dépôt : `approve(tiroir, vault, montant, échéance)` puis `deposit(tiroir, SolvBTC, montant)`, bornes relues dans les deux")
    func depositLegs() throws {
        let legs = try SolvCalls.depositLegs(vault: Self.vault, from: Self.main, currency: Self.solvBTC, units: 50_000, liveUntilLedger: 5_600_000)
        #expect(legs.map(\.function) == ["approve", "deposit"])
        #expect(legs[0].contract == Self.solvBTC && legs[0].addressArgument(0) == Self.main && legs[0].addressArgument(1) == Self.vault)
        #expect(ContractArgument.int128(legs[0].arguments[2]) == 50_000)
        #expect(legs[1].contract == Self.vault && ContractArgument.int128(legs[1].arguments[2]) == 50_000)
        let terms = try SolvCalls.terms(of: legs, vault: Self.vault, currency: Self.solvBTC, shares: Self.xSolvBTC)
        #expect(terms.action == .deposit && terms.authorizer == Self.main && terms.amountIn == 50_000 && terms.assetOut == Self.xSolvBTC)

        // Un `approve` qui ne correspond pas au dépôt (autre montant, autre bénéficiaire) : rien n'est signé.
        let tooMuch = try SolvCalls.approve(token: Self.solvBTC, owner: Self.main, spender: Self.vault, units: 60_000, liveUntilLedger: 5_600_000)
        #expect(throws: ContractArgument.ArgumentError.self) { try SolvCalls.terms(of: [tooMuch, legs[1]], vault: Self.vault, currency: Self.solvBTC, shares: Self.xSolvBTC) }
        let elsewhere = try SolvCalls.approve(token: Self.solvBTC, owner: Self.main, spender: Self.router, units: 50_000, liveUntilLedger: 5_600_000)
        #expect(throws: ContractArgument.ArgumentError.self) { try SolvCalls.terms(of: [elsewhere, legs[1]], vault: Self.vault, currency: Self.solvBTC, shares: Self.xSolvBTC) }
    }

    @Test("Arbre déclaré : le Main autorise `batch` du router, avec `approve` et `deposit` dessous, rien d'autre")
    func declaredTree() throws {
        let legs = try SolvCalls.depositLegs(vault: Self.vault, from: Self.main, currency: Self.solvBTC, units: 50_000, liveUntilLedger: 5_600_000)
        let root = try RouterBatch.call(router: Self.router, caller: Self.main, legs: legs)
        let declared = try DeclaredInvocations.build(root: root, legs: legs, authorizers: [.account(Self.main)], shape: SolvAuthShape(vault: Self.vault))
        #expect(declared.count == 1)
        let tree = try #require(declared.first).invocation
        #expect(tree.subInvocations.count == 2)
        #expect(tree.subInvocations.allSatisfy { $0.subInvocations.isEmpty }, "Le vault tire le SolvBTC lui-même (transfer_from)")
        #expect(SolvAuthShape(vault: Self.vault).signer(of: legs[1]) == Self.main)
        #expect(SolvAuthShape(vault: Self.vault).signer(of: legs[0]) == nil, "L'approve est un appel de jeton")
    }

    @Test("Formules du vault : parts frappées = montant × 10^8 / NAV ; valeur = parts × NAV / 10^8 (vers zéro)")
    func formulas() {
        #expect(SolvCalls.mintedShares(units: 100_000, nav: 100_000_000, navDecimals: 8) == 100_000)
        #expect(SolvCalls.mintedShares(units: 100_000, nav: 105_000_000, navDecimals: 8) == 95_238)
        #expect(SolvCalls.value(shares: 95_238, nav: 105_000_000, navDecimals: 8) == 99_999)
        #expect(SolvCalls.mintedShares(units: 0, nav: 100_000_000, navDecimals: 8) == nil)
        #expect(SolvCalls.mintedShares(units: 1, nav: 0, navDecimals: 8) == nil)
        var quote = VaultQuote(action: .deposit, amount: Decimal(string: "0.001")!, shares: TokenAmount(95_238), expectedOut: nil, minimumOut: nil, all: false)
        quote.decimals = 8
        #expect(quote.sharesAmount == Decimal(string: "0.00095238"))
    }

    @Test("Le pot Solv : la valeur en SolvBTC, ce qui a vraiment poussé (NAV), le total en dollars au prix de RedStone")
    func pot() throws {
        let drawer = SendDrawer(id: "main", kind: .main, address: Self.main, balances: [:], usesPin: true)
        let context = VaultContext(
            network: .testnet, drawers: [drawer], vault: ChainSolvService.info(ChimpNetworkConfig.testnet.integrations!.solv),
            holdings: [VaultHolding(drawerID: "main", drawerAddress: Self.main, shares: Decimal(string: "0.001")!, value: Decimal(string: "0.00105")!,
                                    basis: VaultBasis(putIn: Decimal(string: "0.001")!, since: .now), readAt: .now)]
        )
        #expect(context.vault.mark == .solv && context.vault.asset == .solvbtc && context.vault.withdrawalsBlocked)
        let pot = try #require(GrowPots.build(vault: nil, lending: nil, savings: [], solv: context).first)
        #expect(pot.mark == .solv && pot.growth == Decimal(string: "0.00005"))
        #expect(GrowPots.totalUSD([pot], xlmUSD: nil, btcUSD: 80_000) == 4)
        #expect(GrowPots.totalUSD([pot], xlmUSD: nil, btcUSD: nil) == nil, "Jamais de total partiel")
        #expect(MainTabView.addRoute(.solv, drawerID: "main") == .solvDeposit(drawerID: "main"))
        #expect(GrowView.plantRoute(.solv, drawer: nil, fallbackAddress: nil) == .solvDeposit(drawerID: nil))
    }
}
