import Foundation
import Testing
@testable import ChimpDAO

/// Tranche 2, phase 5, étape 3 : prix indicatif du CETES par l'API publique d'Etherfuse (sandbox, sans clé). Réponses
/// réelles de `api.sand.etherfuse.com` lues le 2026-10-15 (`/lookup/stablebond/CETES-GC3CW7…UPS4` et
/// `/lookup/tokens/cost/AvvetPGu…?max_age=900`).
struct EtherfusePriceTests {
    static let issuer = "GC3CW7EDYRTWQ635VDIGY6S4ZUF5L6TQ7AA4MWS7LEQDBLUSZXV7UPS4"
    static let mint = "AvvetPGuuB5FD5m86fpw3LtDKyQoUFT1mG9WarNQLW4q"
    static let bond = IntegrationConfig.Stablebond(code: "CETES", contract: CetesAssetTests.cetes)

    static let bondLookup = #"""
    {"name":"Cetes","symbol":"CETES","netAmountDecimal":"722983939.223405","netValueDecimal":"828781223.003139","bondCurrency":"MXN","tokenPriceDecimal":"1.146334","purchaseOrderAmount":"286410.451407","redeemOrderAmount":"0","blockchains":[{"blockchain":"monad","tokenIdentifier":"0x955dBA7d1117B9D9f749957a1fF19DB8D7e7df35","totalSupply":"113673.495833","decimals":6},{"blockchain":"avalanche","tokenIdentifier":"0xdc678b39B316bD7c1D76dcf83E7357ad9B9AC49F","totalSupply":"0.49","decimals":6},{"blockchain":"polygon","tokenIdentifier":"0xBb65ff484548a620910c514154168aBB5d0C2cEC","totalSupply":"1716.02055","decimals":6},{"blockchain":"solana","tokenIdentifier":"AvvetPGuuB5FD5m86fpw3LtDKyQoUFT1mG9WarNQLW4q","totalSupply":"403025557.79144","decimals":6},{"blockchain":"stellar","tokenIdentifier":"CETES-GC3CW7EDYRTWQ635VDIGY6S4ZUF5L6TQ7AA4MWS7LEQDBLUSZXV7UPS4","totalSupply":"319050899.3296408","decimals":7},{"blockchain":"base","tokenIdentifier":"0xcC77c598d42f2f78Beb42C91d12B9d4041a5cE29","totalSupply":"505681.644534","decimals":6}],"solanaMintAddress":"AvvetPGuuB5FD5m86fpw3LtDKyQoUFT1mG9WarNQLW4q"}
    """#

    static let tokenCost = #"""
    {"token_symbol":"CETES","token_mint":"AvvetPGuuB5FD5m86fpw3LtDKyQoUFT1mG9WarNQLW4q","token_kind":"bond","currency":"MXN","token_cost_in_fiat":"1.146334","token_cost_in_usd":"0.062017","fiat_exchange_rate_with_usd":"18.48421","current_basis_points":313,"current_time":"2026-10-15T11:47:15.342297586+00:00","payment_mint":"BXTou3CvPxpFVAJvzvEZcAnRLGCHqT1LHKsFTSQft7s","sources":{"8333dd29-55fc-49c6-94d1-bf97a967654c":{"exchange_rate":"18.48110198974609375","token_cost_in_usd":"0.062027","updated_at":1792064626},"4ac820d6-2b2f-4e52-b62f-c83861d82322":{"exchange_rate":"18.4826430478","token_cost_in_usd":"0.062022","updated_at":1792064616},"c83470e8-282f-41e8-90a5-7eef368311c0":{"exchange_rate":"18.48502","token_cost_in_usd":"0.062014","updated_at":1792064656},"369ed8ed-033a-46e7-84ab-db60002f8d50":{"exchange_rate":"18.484215","token_cost_in_usd":"0.062017","updated_at":1792064606},"7302046e-794e-4c29-b46f-8e6e24ae621f":{"exchange_rate":"18.4874","token_cost_in_usd":"0.062006","updated_at":1792064636}}}
    """#

    /// Une minute après la plus récente des sources.
    static let readAt = Date(timeIntervalSince1970: 1_792_064_716)

    @Test("Le titre qui porte exactement CETES-GC3CW7…UPS4 sur Stellar : son adresse Solana sert d'identifiant")
    func mint() throws {
        #expect(try EtherfusePriceClient.mint(from: Data(Self.bondLookup.utf8), code: "CETES", issuer: Self.issuer) == Self.mint)
    }

    @Test("Un autre émetteur, ou un autre symbole : refusé (jamais le code seul)")
    func notThisBond() {
        let other = "GAAV6W3LFJHBMFV72EZIW5BJCAEGBPAT4TSGIAQC6W6L2UWPYR2MSXUC"
        #expect(throws: EtherfusePriceError.self) { try EtherfusePriceClient.mint(from: Data(Self.bondLookup.utf8), code: "CETES", issuer: other) }
        #expect(throws: EtherfusePriceError.self) { try EtherfusePriceClient.mint(from: Data(Self.bondLookup.utf8), code: "USTRY", issuer: Self.issuer) }
    }

    @Test("Prix : 0,062017 $ et 1,146334 MXN par CETES, daté de la plus ancienne source retenue")
    func price() throws {
        let price = try EtherfusePriceClient.price(from: Data(Self.tokenCost.utf8), code: "CETES", mint: Self.mint, now: Self.readAt)
        #expect(price.usd == Decimal(string: "0.062017"))
        #expect(price.fiat == Decimal(string: "1.146334"))
        #expect(price.currency == "MXN")
        #expect(price.asOf == Date(timeIntervalSince1970: 1_792_064_606))
        #expect(price.source == "Etherfuse")
        #expect(price.value(of: 1000) == Decimal(string: "62.017"))
    }

    @Test("Sources trop anciennes, sources en désaccord (> 1 %), autre jeton : aucun prix plutôt qu'un prix douteux")
    func refusals() {
        let later = Self.readAt.addingTimeInterval(3600)
        #expect(throws: EtherfusePriceError.stale) {
            try EtherfusePriceClient.price(from: Data(Self.tokenCost.utf8), code: "CETES", mint: Self.mint, now: later)
        }
        let disagreeing = Self.tokenCost.replacingOccurrences(of: #""token_cost_in_usd":"0.062006""#, with: #""token_cost_in_usd":"0.070000""#)
        #expect(throws: EtherfusePriceError.sourcesDisagree) {
            try EtherfusePriceClient.price(from: Data(disagreeing.utf8), code: "CETES", mint: Self.mint, now: Self.readAt)
        }
        #expect(throws: EtherfusePriceError.self) {
            try EtherfusePriceClient.price(from: Data(Self.tokenCost.utf8), code: "CETES", mint: "SomethingElse", now: Self.readAt)
        }
    }

    @Test("Client : deux lectures sans clé, puis le prix gardé 5 minutes ; une panne n'est jamais gardée")
    func client() async throws {
        final class Calls: @unchecked Sendable {
            var urls: [URL] = []
            var fail = false
        }
        let calls = Calls()
        let client = EtherfusePriceClient(api: URL(string: "https://api.sand.etherfuse.com")!, issuer: Self.issuer)
        client.now = { Self.readAt }
        client.transport = { request in
            calls.urls.append(request.url!)
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil, "Jamais de clé")
            let body = request.url!.path.contains("stablebond") ? Self.bondLookup : Self.tokenCost
            let status = calls.fail ? 503 : 200
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
        calls.fail = true
        guard case .unavailable = await client.price(of: Self.bond) else { Issue.record("une panne donne un prix"); return }
        calls.fail = false
        let price = try #require(await client.price(of: Self.bond).price)
        #expect(price.usd == Decimal(string: "0.062017"))
        #expect(calls.urls.map(\.absoluteString) == [
            "https://api.sand.etherfuse.com/lookup/stablebond/CETES-\(Self.issuer)",
            "https://api.sand.etherfuse.com/lookup/stablebond/CETES-\(Self.issuer)",
            "https://api.sand.etherfuse.com/lookup/tokens/cost/\(Self.mint)?max_age=900",
        ])
        _ = await client.price(of: Self.bond)
        #expect(calls.urls.count == 3, "Gardé en mémoire")
    }

    @Test("Le total du Wallet ne demande jamais le CETES à Reflector (seule source : Etherfuse)")
    func neverFromReflector() async {
        #expect(PriceOracleConfig.reflector.neverPriced.contains("CETES"))
        let prices = await ReflectorPriceOracle().usdPrices(for: ["CETES", "USDC"])
        #expect(prices == ["USDC": 1])
    }
}
