import Foundation
import Testing
@testable import ChimpDAO

/// Tranche 2, phase 6 : devis NEAR Intents (N1, D4, voie de repli du grant). Devis **à blanc** seulement ; réponses réelles
/// de l'API 1Click relevées le 2026-10-15.
struct CrossChainQuoteTests {
    private let usdcBase = OneClickToken(assetId: "nep141:base-0x833589fcd6edb6e08f4c7c32d4f71b54bda02913.omft.near", decimals: 6, blockchain: "base", symbol: "USDC")
    private let wnear = OneClickToken(assetId: "nep141:wrap.near", decimals: 24, blockchain: "near", symbol: "wNEAR")

    /// Vraie réponse d'un devis à blanc (10 USDC de Base → wNEAR), 2026-10-15 15:39 UTC.
    static let realQuote = #"""
    {"quote":{"amountIn":"10000000","amountInFormatted":"10.0","amountInUsd":"9.996160000000","minAmountIn":"10000000","amountOut":"1963974524625280388072654","amountOutFormatted":"1.963974524625280388072654","amountOutUsd":"9.918071349358","minAmountOut":"1944334779379027584191927","timeEstimate":35,"refundFee":"0","withdrawFee":"0"},"quoteRequest":{"dry":true,"depositMode":"SIMPLE","swapType":"EXACT_INPUT","slippageTolerance":100},"signature":"ed25519:53sQ","timestamp":"2026-10-15T15:39:40.624Z","correlationId":"9acbc02c"}
    """#

    @Test("Corps du devis : toujours à blanc (dry), remboursement INTENTS, destinataire et montant tels quels")
    func body() {
        let body = OneClickClient.body(
            origin: usdcBase, amountUnits: "10000000", destination: MockOneClick.tokens[5], recipient: "GDZE7UWGO3PS6R6RI6F3XIJLX7WGIEFD3X4YQO4AJH4LS3KDY6LLFXG2",
            refundAccount: "intents.near", deadline: Date(timeIntervalSince1970: 1_792_080_000)
        )
        #expect(body["dry"] as? Bool == true)
        #expect(body["refundType"] as? String == "INTENTS")
        #expect(body["refundTo"] as? String == "intents.near")
        #expect(body["swapType"] as? String == "EXACT_INPUT")
        #expect(body["amount"] as? String == "10000000")
        #expect(body["recipient"] as? String == "GDZE7UWGO3PS6R6RI6F3XIJLX7WGIEFD3X4YQO4AJH4LS3KDY6LLFXG2")
        #expect(body["slippageTolerance"] as? Int == 100)
    }

    @Test("Lecture de la vraie réponse : 10 → 1,9639… ; minimum à 24 décimales, exact ; 35 s")
    func parsesRealQuote() throws {
        let quote = try OneClickClient.quote(from: Data(Self.realQuote.utf8), origin: usdcBase, destination: wnear, at: .now)
        #expect(quote.amountIn == 10)
        #expect(quote.amountOut == Decimal(string: "1.963974524625280388072654"))
        #expect(quote.minimumOut == Decimal(string: "1.944334779379027584191927"))
        #expect(quote.timeEstimate == 35)
    }

    @Test("Une réponse avec une adresse de dépôt n'est jamais lue comme un devis à blanc")
    func refusesDepositAddress() {
        let withDeposit = Self.realQuote.replacingOccurrences(of: #""timeEstimate":35"#, with: #""timeEstimate":35,"depositAddress":"0xabc""#)
        #expect(throws: OneClickError.malformed) {
            try OneClickClient.quote(from: Data(withDeposit.utf8), origin: usdcBase, destination: wnear, at: .now)
        }
    }

    @Test("Refus réels de l'API : paire sans prix, adresse de carte refusée ; le reste dit tel quel")
    func refusals() {
        func check(_ message: String) throws {
            let response = HTTPURLResponse(url: URL(string: "https://1click.chaindefuser.com")!, statusCode: 400, httpVersion: nil, headerFields: nil)!
            try OneClickClient.check(response, data: Data(#"{"message":"\#(message)"}"#.utf8))
        }
        #expect(throws: OneClickError.pairUnavailable) { try check("Quoting for this pair is not available") }
        #expect(throws: OneClickError.recipientRefused) { try check("recipient is not valid") }
        #expect(throws: OneClickError.http(400, "Internal server error")) { try check("Internal server error") }
    }

    @Test("Montant en unités du jeton, exact (6, 8, 18 décimales) ; rien de tapé : pas de devis")
    func units() {
        #expect(CrossChainQuoteModel.units(of: 10, decimals: 6) == "10000000")
        #expect(CrossChainQuoteModel.units(of: Decimal(string: "0.000123")!, decimals: 8) == "12300")
        #expect(CrossChainQuoteModel.units(of: Decimal(string: "1.5")!, decimals: 18) == "1500000000000000000")
        #expect(CrossChainQuoteModel.units(of: 0, decimals: 6) == nil)
    }

    private func model(_ scenario: MockOneClick.Scenario = .normal) async -> (CrossChainQuoteModel, MockOneClick) {
        let client = MockOneClick(scenario: scenario, delay: .zero)
        let model = CrossChainQuoteModel(client: client, recipient: "GDZE7UWGO3PS6R6RI6F3XIJLX7WGIEFD3X4YQO4AJH4LS3KDY6LLFXG2", debounce: .zero)
        await model.load()
        return (model, client)
    }

    @Test("Chaînes : Stellar exclu, les courantes d'abord ; USDC d'abord sur une chaîne ; XLM à l'arrivée par défaut")
    func lists() async {
        let (model, _) = await model()
        #expect(model.chains == ["eth", "base", "sol", "btc"])
        #expect(model.chain == "eth")
        #expect(model.origin?.symbol == "USDC")
        #expect(model.tokens(on: "eth").map(\.symbol) == ["USDC", "ETH"])
        #expect(model.destination == .xlm)
        #expect(model.destinationToken?.blockchain == "stellar")
        #expect(CrossChainQuoteModel.chainName("arb") == "Arbitrum")
        #expect(CrossChainQuoteModel.chainName("zzz") == "ZZZ")
    }

    @Test("Devis : 10 USDC → environ 54,11 XLM ; changer l'arrivée en USDC redemande un devis ; rien de tapé : aucun")
    func quotes() async throws {
        let (model, client) = await model()
        #expect(model.quoteState == .idle)
        model.press(.digit(1)); model.press(.digit(0))
        await model.refreshQuote()
        guard case .quoted(let quote) = model.quoteState else { Issue.record("pas de devis"); return }
        #expect(quote.amountOut == Decimal(string: "54.11"))
        let before = client.quoteCount
        model.selectDestination(.usdc)
        await model.refreshQuote()
        #expect(client.quoteCount > before)
        guard case .quoted(let usdc) = model.quoteState else { Issue.record("pas de devis USDC"); return }
        #expect(usdc.amountOut == Decimal(string: "9.975"))
        model.selectDestination(.cetes)
        #expect(model.destination == .usdc, "Seulement XLM ou USDC à l'arrivée")
    }

    @Test("Pas de prix pour la paire, ou API muette : dit simplement ; chaîne à 8 décimales : saisie limitée à 6")
    func issues() async {
        let (model, _) = await model(.pairUnavailable)
        model.press(.digit(5))
        await model.refreshQuote()
        #expect(model.quoteState == .failed(.pairUnavailable))
        let (offline, _) = await self.model(.offline)
        #expect(offline.phase == .failed)
        let (btc, _) = await self.model()
        btc.selectChain("btc")
        #expect(btc.origin?.symbol == "BTC")
        #expect(btc.fractionDigits == 6)
    }
}
