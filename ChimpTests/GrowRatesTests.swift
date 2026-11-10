import Foundation
import Testing
@testable import ChimpDAO

/// Taux du moment dans Grow (demande de Barth, 2026-11-10). Réponse réduite de `testnet-api.xoxno.com` relevée ce jour-là.
struct GrowRatesTests {
    private let usdc = "CBIELTK6YBZJU5UP2WWQEUCYKLPU6AUNZ2BQ4WWFEIE3USCIHMXQDAMA"
    private let us = Locale(identifier: "en_US")
    private let fr = Locale(identifier: "fr_FR")

    private func json(_ hub: Int = 1, sac: String? = nil, apy: String = "0.011484654408456559", status: String = "ready") -> Data {
        Data("""
        [{"symbol":"USDC","hubId":\(hub),"sac":"\(sac ?? usdc)","supplyApy":\(apy),"dataStatus":"\(status)","spokes":[]},
         {"symbol":"XLM","hubId":1,"sac":"CDLZFC3SYJYDZT7K67VZ75HPJVIEUVNIXF47ZG2FB2RMQQVU2HHGCYSC","supplyApy":0.64,"dataStatus":"ready"},
         {"symbol":"USDC/XLM LP","hubId":3,"sac":null,"supplyApy":null,"dataStatus":"ready"}]
        """.utf8)
    }

    @Test("Le taux du marché de l'app : même hub, même actif, données à jour")
    func marketRate() throws {
        let rate = try #require(XoxnoRateClient.rate(from: json(), hubID: 1, asset: usdc))
        #expect(rate > Decimal(string: "0.0114")! && rate < Decimal(string: "0.0115")!)
    }

    @Test("Refusé plutôt que deviné : autre hub, autre actif, données pas prêtes, taux absurde ou absent, réponse illisible")
    func refused() {
        #expect(XoxnoRateClient.rate(from: json(2), hubID: 1, asset: usdc) == nil)
        #expect(XoxnoRateClient.rate(from: json(sac: "CAAA"), hubID: 1, asset: usdc) == nil)
        #expect(XoxnoRateClient.rate(from: json(status: "syncing"), hubID: 1, asset: usdc) == nil)
        #expect(XoxnoRateClient.rate(from: json(apy: "-0.01"), hubID: 1, asset: usdc) == nil)
        #expect(XoxnoRateClient.rate(from: json(apy: "11"), hubID: 1, asset: usdc) == nil)
        #expect(XoxnoRateClient.rate(from: json(apy: "null"), hubID: 1, asset: usdc) == nil)
        #expect(XoxnoRateClient.rate(from: Data("oops".utf8), hubID: 1, asset: usdc) == nil)
    }

    @Test("Le client lit l'API configurée ; une panne ne donne simplement aucun taux")
    func client() async throws {
        var ok = XoxnoRateClient(api: URL(string: "https://example.test")!, hubID: 1, asset: usdc)
        let data = json()
        ok.transport = { request in
            #expect(request.url?.absoluteString == "https://example.test/stellar-lending/v1/assets")
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        #expect(await ok.rates()[.xoxno] != nil)
        var down = ok
        down.transport = { _ in throw URLError(.timedOut) }
        #expect(await down.rates().isEmpty)
        #expect(XoxnoRateClient(config: .testnet) != nil, "Testnet : le taux de XOXNO est branché")
    }

    @Test("Affichage : une décimale au plus, dans la langue du téléphone, et rien sans taux")
    func text() {
        #expect(GrowView.rateText(Decimal(string: "0.011484")!, locale: us) == "~1.1% a year")
        #expect(GrowView.rateText(Decimal(string: "0.011484")!, locale: fr).contains("1,1"))
        #expect(GrowView.rateText(0, locale: us) == "~0% a year")
        #expect(GrowView.withRate("Grows USDC", rate: Decimal(string: "0.02")!, locale: us) == "Grows USDC · ~2% a year")
        #expect(GrowView.withRate("Grows USDC", rate: nil, locale: us) == "Grows USDC")
    }

    @Test("Modèle : le taux lu arrive ; un vault qui n'investit rien affiche 0 % ; sans source, rien")
    func model() async {
        let model = GrowModel(service: MockVaultService(delay: .zero), rateReader: MockGrowRates(values: [.xoxno: Decimal(string: "0.02")!]))
        await model.refresh()
        #expect(model.rates[.xoxno] == Decimal(string: "0.02"))
        #expect(model.rates[.sentora] == nil)
        #expect((model.rates[.defindex] != nil) == (model.context?.vault.invested == 0))
        #expect(GrowModel(service: MockVaultService(delay: .zero)).rates.isEmpty)
    }
}
