import Foundation
import stellarsdk
import Testing
@testable import ChimpDAO

/// Tranche 2, phase 1, étape 3 : slippage, impact de prix et bornes signées relues dans l'appel construit.
/// Vecteurs du terminal (`withSlippage` de `lib/amount.ts` ; opérations de `runSwap`, `depositOp`, `withdrawOp`),
/// exécutés avec `@stellar/stellar-sdk` 17.0.1. Réserves de la paire Soroswap XLM/USDC lues sur testnet le 2026-10-14.
struct SignedTermsTests {
    private let account = "CCDO6J7WOGPTKZA73FWECCIJ75TTOMHMCWLEGPYWIFCNSINM63UJDDYB"
    private let pocket = "CDGWNZPBHLWML4Z4SFSFLO2NRYV6566CFRM2E5ZRZE74AIXO6FYCS437"
    private let router = "CCJUD55AG6W5HAI5LRVNKAE5WDP5XGZBUDS5WNTIVDU7O264UZZE7BRD"
    private let xlm = "CDLZFC3SYJYDZT7K67VZ75HPJVIEUVNIXF47ZG2FB2RMQQVU2HHGCYSC"
    private let usdc = "CBIELTK6YBZJU5UP2WWQEUCYKLPU6AUNZ2BQ4WWFEIE3USCIHMXQDAMA"
    private let cetes = "CC72F57YTPX76HAA64JQOEGHQAPSADQWSY5DWVBR66JINPFDLNCQYHIC"
    private let vault = "CCLV4H7WTLJQ7ATLHBBQV2WW3OINF3FOY5XZ7VPHZO7NH3D2ZS4GFSF6"
    private let now: UInt64 = 1_791_961_199

    // MARK: Slippage

    @Test("withSlippage : vecteurs du terminal (arrondi vers le bas, 0 pour un montant nul)")
    func withSlippageVectors() {
        let vectors: [(Int128, Int, Int128)] = [
            (10619368, 50, 10566271),
            (10619368, 300, 10300786),
            (1, 50, 0),
            (0, 50, 0),
            (199, 50, 198),
            (200, 50, 199),
            (12345678901234567890, 300, 11975308534197530853),
        ]
        for (units, bps, expected) in vectors {
            #expect(Slippage.minimum(of: units, basisPoints: bps) == expected)
        }
        #expect(Slippage.minimum(of: -5, basisPoints: 50) == 0)
    }

    @Test("Seuils validés : 0,5 % par défaut, 3 % au maximum (au-delà : refus), avertissement au-delà de 5 % d'impact")
    func thresholds() throws {
        #expect(Slippage.defaultBasisPoints == 50)
        #expect(try Slippage.checked(0) == 0)
        #expect(try Slippage.checked(300) == 300)
        #expect(throws: Slippage.SlippageError.outOfRange(basisPoints: 301)) { try Slippage.checked(301) }
        #expect(throws: Slippage.SlippageError.outOfRange(basisPoints: -1)) { try Slippage.checked(-1) }
        #expect(!Slippage.needsPriceImpactWarning(500))
        #expect(Slippage.needsPriceImpactWarning(501))
    }

    @Test("Impact de prix, réserves réelles de la paire XLM/USDC : 10 XLM → 30 pb (les frais) ; 5 M XLM → 56 %, avertissement")
    func priceImpact() {
        let reserveXLM: Int128 = 39_264_032_674_308, reserveUSDC: Int128 = 4_182_149_447_905
        let small = Slippage.priceImpactBasisPoints(amountIn: 100_000_000, amountOut: 10_619_368, reserveIn: reserveXLM, reserveOut: reserveUSDC)
        #expect(small == 30)
        let large = Slippage.priceImpactBasisPoints(amountIn: 50_000_000_000_000, amountOut: 2_339_476_104_061, reserveIn: reserveXLM, reserveOut: reserveUSDC)
        #expect(large == 5607)
        #expect(Slippage.needsPriceImpactWarning(large!))
        #expect(Slippage.priceImpactBasisPoints(amountIn: 1, amountOut: 1, reserveIn: 0, reserveOut: 1) == nil)
    }

    // MARK: Appels construits = appels du terminal

    @Test("Swap Soroswap : mêmes arguments que runSwap (minimum = devis − 0,5 %)")
    func soroswapSwapBytes() throws {
        let minimum = Slippage.minimum(of: 10_619_368, basisPoints: Slippage.defaultBasisPoints)
        let call = try SoroswapCalls.swap(router: router, amountIn: 10_000_000, minimumOut: minimum, path: [xlm, usdc], to: account, deadline: 1_791_961_499)
        #expect(try call.arguments.map(base64) == ["AAAACgAAAAAAAAAAAAAAAACYloA=", "AAAACgAAAAAAAAAAAAAAAAChOn8=", "AAAAEAAAAAEAAAACAAAAEgAAAAHXkotywnA8z+r365/0701QSlWouXn8m0UOoshCtNHOYQAAABIAAAABUEXNXsBymnaP1a0CUFhS308Cjc6DDlrFIgm6SEg7LwE=", "AAAAEgAAAAGG7yf2cZ81ZB/ZbEEJCf9nNzDsFZZDPxZBRNkhrPbokQ==", "AAAABQAAAABqzymb"])
    }

    @Test("Dépôt et retrait DeFindex : mêmes arguments que depositOp et withdrawOp")
    func defindexBytes() throws {
        #expect(try DeFindexCalls.deposit(vault: vault, from: account, units: 10_000_000).arguments.map(base64) == ["AAAAEAAAAAEAAAABAAAACgAAAAAAAAAAAAAAAACYloA=", "AAAAEAAAAAEAAAABAAAACgAAAAAAAAAAAAAAAACYloA=", "AAAAEgAAAAGG7yf2cZ81ZB/ZbEEJCf9nNzDsFZZDPxZBRNkhrPbokQ==", "AAAAAAAAAAE="])
        let withdraw = try DeFindexCalls.withdraw(vault: vault, from: account, shares: 599, minimumOut: Slippage.minimum(of: 9_990_000, basisPoints: 50))
        #expect(try withdraw.arguments.map(base64) == ["AAAACgAAAAAAAAAAAAAAAAAAAlc=", "AAAAEAAAAAEAAAABAAAACgAAAAAAAAAAAAAAAACXrFI=", "AAAAEgAAAAGG7yf2cZ81ZB/ZbEEJCf9nNzDsFZZDPxZBRNkhrPbokQ=="])
    }

    // MARK: Bornes relues dans l'appel

    private func swapTerms(minimumOut: Int128 = 10_566_271, deadline: UInt64? = nil, path: [String]? = nil) -> SignedTerms {
        let path = path ?? [xlm, usdc]
        return SignedTerms(
            action: .swap, contract: router, authorizer: account, assetIn: path[0], amountIn: 10_000_000,
            assetOut: path[path.count - 1], minimumOut: minimumOut, route: path, deadline: deadline ?? now + 300
        )
    }

    @Test("Les bornes décodées d'un swap sont celles de l'écran ; deux sauts : route complète, actif reçu = dernier")
    func soroswapTermsRoundTrip() throws {
        let call = try SoroswapCalls.swap(router: router, amountIn: 10_000_000, minimumOut: 10_566_271, path: [xlm, usdc], to: account, deadline: now + 300)
        let signed = try SoroswapCalls.terms(of: call, router: router)
        #expect(signed == swapTerms())
        try BoundsCheck.verify(shown: swapTerms(), signed: signed, quotedOut: 10_619_368, now: now)

        let hop = try SoroswapCalls.swap(router: router, amountIn: 10_000_000, minimumOut: 1, path: [xlm, usdc, cetes], to: pocket, deadline: now + 60)
        let hopTerms = try SoroswapCalls.terms(of: hop, router: router)
        #expect(hopTerms.assetOut == cetes)
        #expect(hopTerms.route == [xlm, usdc, cetes])
        #expect(hopTerms.authorizer == pocket)
    }

    @Test("Décodage refusé : autre router, autre fonction, argument mal formé")
    func soroswapTermsRefused() throws {
        let call = try SoroswapCalls.swap(router: router, amountIn: 1, minimumOut: 1, path: [xlm, usdc], to: account, deadline: now)
        #expect(throws: ContractArgument.ArgumentError.self) { try SoroswapCalls.terms(of: call, router: vault) }
        let other = ContractCall(contract: router, function: "swap_tokens_for_exact_tokens", arguments: call.arguments)
        #expect(throws: ContractArgument.ArgumentError.self) { try SoroswapCalls.terms(of: other, router: router) }
        var arguments = call.arguments
        arguments[2] = .vec([try ContractArgument.address(xlm)])
        #expect(throws: ContractArgument.ArgumentError.self) {
            try SoroswapCalls.terms(of: ContractCall(contract: router, function: SoroswapCalls.swapFunction, arguments: arguments), router: router)
        }
    }

    @Test("Écran ≠ appel : chaque borne modifiée est refusée et nommée (montant, actif, destination, contrat, route, minimum, échéance)")
    func shownDiffersFromSigned() throws {
        let shown = swapTerms()
        let cases: [(SignedTerms, String)] = [
            (SignedTerms(action: .swap, contract: router, authorizer: account, assetIn: xlm, amountIn: 20_000_000, assetOut: usdc, minimumOut: 10_566_271, route: [xlm, usdc], deadline: now + 300), "amount given"),
            (SignedTerms(action: .swap, contract: router, authorizer: account, assetIn: usdc, amountIn: 10_000_000, assetOut: usdc, minimumOut: 10_566_271, route: [xlm, usdc], deadline: now + 300), "asset given"),
            (SignedTerms(action: .swap, contract: router, authorizer: pocket, assetIn: xlm, amountIn: 10_000_000, assetOut: usdc, minimumOut: 10_566_271, route: [xlm, usdc], deadline: now + 300), "authorizer"),
            (SignedTerms(action: .swap, contract: vault, authorizer: account, assetIn: xlm, amountIn: 10_000_000, assetOut: usdc, minimumOut: 10_566_271, route: [xlm, usdc], deadline: now + 300), "contract"),
            (swapTerms(path: [xlm, cetes]), "asset received"),
            (SignedTerms(action: .swap, contract: router, authorizer: account, assetIn: xlm, amountIn: 10_000_000, assetOut: usdc, minimumOut: 10_566_271, route: [xlm, cetes, usdc], deadline: now + 300), "route"),
            (swapTerms(minimumOut: 1), "minimum received"),
            (swapTerms(deadline: now + 200), "deadline"),
        ]
        for (signed, field) in cases {
            #expect(throws: BoundsCheck.BoundsError.differs(field: field)) { try BoundsCheck.verify(shown: shown, signed: signed, quotedOut: nil, now: now) }
        }
    }

    @Test("Minimum absent, à 0 ou plus bas que le devis − 3 % : refusé ; exactement − 3 % : accepté")
    func minimumBounds() throws {
        #expect(throws: BoundsCheck.BoundsError.noMinimum) { try BoundsCheck.verify(shown: swapTerms(minimumOut: 0), signed: swapTerms(minimumOut: 0), quotedOut: nil, now: now) }
        let floor = Slippage.minimum(of: 10_619_368, basisPoints: 300)
        #expect(throws: BoundsCheck.BoundsError.slippageAboveMaximum(minimum: floor - 1, floor: floor)) {
            try BoundsCheck.verify(shown: swapTerms(minimumOut: floor - 1), signed: swapTerms(minimumOut: floor - 1), quotedOut: 10_619_368, now: now)
        }
        try BoundsCheck.verify(shown: swapTerms(minimumOut: floor), signed: swapTerms(minimumOut: floor), quotedOut: 10_619_368, now: now)
    }

    @Test("Échéance passée ou à plus de 5 minutes : refusé")
    func deadlineBounds() throws {
        for (deadline, error) in [(now, BoundsCheck.BoundsError.deadlinePassed), (now + 301, .deadlineTooFar)] {
            #expect(throws: error) { try BoundsCheck.verify(shown: swapTerms(deadline: deadline), signed: swapTerms(deadline: deadline), quotedOut: nil, now: now) }
        }
        try BoundsCheck.verify(shown: swapTerms(deadline: now + 1), signed: swapTerms(deadline: now + 1), quotedOut: nil, now: now)
    }

    @Test("Vault : dépôt (l'actif part, les parts arrivent, pas de minimum) et retrait (parts → actif au minimum signé)")
    func defindexTerms() throws {
        let deposit = try DeFindexCalls.terms(of: try DeFindexCalls.deposit(vault: vault, from: account, units: 10_000_000), underlying: xlm)
        #expect(deposit == SignedTerms(action: .deposit, contract: vault, authorizer: account, assetIn: xlm, amountIn: 10_000_000, assetOut: vault, minimumOut: nil, route: [], deadline: nil))
        try BoundsCheck.verify(shown: deposit, signed: deposit, quotedOut: nil, now: now)

        let withdraw = try DeFindexCalls.terms(of: try DeFindexCalls.withdraw(vault: vault, from: pocket, shares: 599, minimumOut: 9_940_050), underlying: xlm)
        #expect(withdraw.assetOut == xlm)
        #expect(withdraw.minimumOut == 9_940_050)
        #expect(withdraw.authorizer == pocket)
        #expect(throws: BoundsCheck.BoundsError.noMinimum) {
            let none = try DeFindexCalls.terms(of: try DeFindexCalls.withdraw(vault: vault, from: pocket, shares: 599, minimumOut: 0), underlying: xlm)
            try BoundsCheck.verify(shown: none, signed: none, quotedOut: nil, now: now)
        }
    }

    @Test("Dépôt dont le minimum diffère du montant désiré : refusé au décodage")
    func defindexDepositMinimumMustMatch() throws {
        let call = ContractCall(contract: vault, function: "deposit", arguments: [
            .vec([ContractArgument.i128(10)]), .vec([ContractArgument.i128(9)]), try ContractArgument.address(account), .bool(true),
        ])
        #expect(throws: ContractArgument.ArgumentError.self) { try DeFindexCalls.terms(of: call, underlying: xlm) }
    }

    private func base64(_ value: SCValXDR) throws -> String {
        Data(try XDREncoder.encode(value)).base64EncodedString()
    }
}
