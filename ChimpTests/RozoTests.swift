import Foundation
import stellarsdk
import Testing
@testable import ChimpDAO

/// Tranche 2, phase 6 (suite) : ROZO, intermédiaire de confiance (décision de Barth du 2026-10-16). Vecteurs : de vraies
/// réponses de l'API testnet relevées le 2026-10-16 (devis à blanc et commande non payée vers le Main de la carte n°7).
struct RozoTests {
    private let config = IntegrationConfig.testnet.rozo
    private let main = "CASBWZTE3GU4VVBC2Q3V6VXCHTG7VLHG45AJXEJ64IVNQSDLEDRBD3RP"

    /// `POST /payments` (commande de 0,01 USDC, jamais payée) : montants en nombres.
    static let createdOrder = #"""
    {"id":"pay_7xGFFCtr1koYAmkGp1DNu9DL","appId":"rozoDemo","orderId":"chimpdao-probe-1792135192","status":"payment_unpaid","type":"exactIn","createdAt":"2026-10-16T07:19:55.079139+00:00","updatedAt":"2026-10-16T07:19:55.079139+00:00","expiresAt":"2026-10-16T07:29:54.93+00:00","display":{"title":"ChimpDAO probe (unpaid)","currency":"USD"},"source":{"chainId":"84532","tokenSymbol":"USDC","tokenAddress":"0x036cbd53842c5426634e7929541ec2318f3dcf7e","amount":0.01,"receiverAddress":"0x4843B70de3Aa77CFbfDA0BAf468e3C4f32B1FA34","fee":0},"destination":{"chainId":"1500","receiverAddress":"CASBWZTE3GU4VVBC2Q3V6VXCHTG7VLHG45AJXEJ64IVNQSDLEDRBD3RP","tokenSymbol":"USDC","tokenAddress":"USDC:GBBD47IF6LWK7P7MDEVSCWR7DPUWV3NY3DTQEVFL4NAT4AQH3ZLLFLA5","amount":0.01}}
    """#

    /// `POST /payments?dryrun=true` (0,10 USDC) : montants en texte.
    static let dryRun = #"""
    {"fee":"0","type":"exactIn","source":{"chainId":"84532","tokenSymbol":"USDC","tokenAddress":"0x036cbd53842c5426634e7929541ec2318f3dcf7e","amount":"0.10","fee":"0"},"destination":{"chainId":"1500","receiverAddress":"CASBWZTE3GU4VVBC2Q3V6VXCHTG7VLHG45AJXEJ64IVNQSDLEDRBD3RP","tokenSymbol":"USDC","tokenAddress":"USDC:GBBD47IF6LWK7P7MDEVSCWR7DPUWV3NY3DTQEVFL4NAT4AQH3ZLLFLA5","amount":"0.10"}}
    """#

    private func response(_ status: Int, _ body: String) -> RozoClient.HTTPTransport {
        { request in
            (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
    }

    // MARK: Lecture

    @Test("Une vraie commande se lit : identifiant, état, expiration, montants en nombres, adresse de dépôt")
    func readsRealOrder() throws {
        let order = try RozoClient.order(from: Data(Self.createdOrder.utf8))
        #expect(order.id == "pay_7xGFFCtr1koYAmkGp1DNu9DL")
        #expect(order.status == .unpaid)
        #expect(order.sourceAmount == Decimal(string: "0.01"))
        #expect(order.destinationAmount == Decimal(string: "0.01"))
        #expect(order.depositAddress == "0x4843B70de3Aa77CFbfDA0BAf468e3C4f32B1FA34")
        #expect(order.destinationAddress == main)
        let expires = try #require(order.expiresAt)
        #expect(abs(expires.timeIntervalSince1970 - 1_792_135_794.93) < 0.001)
        #expect(order.problems(recipient: main, requested: Decimal(string: "0.01")!, config: config).isEmpty)
    }

    @Test("États lus : ceux de la documentation, et « payment_payout_started » vu au premier test réel")
    func statuses() {
        #expect(RozoOrder.Status("payment_unpaid") == .unpaid)
        #expect(RozoOrder.Status("payment_payin_completed") == .payinCompleted)
        #expect(RozoOrder.Status("payment_payout_started") == .payoutStarted)
        #expect(RozoOrder.Status("payment_completed") == .completed)
        #expect(RozoOrder.Status("payment_bounced").isFinal)
        #expect(!RozoOrder.Status("payment_payout_started").isFinal)
        #expect(RozoOrder.Status("payment_refunded") == .other("payment_refunded"))
    }

    @Test("Dates : fractions de seconde de 2 ou 6 chiffres, ou aucune")
    func dates() throws {
        let short = try #require(RozoClient.date("2026-10-16T07:29:54.93+00:00"))
        let long = try #require(RozoClient.date("2026-10-16T07:19:55.079139+00:00"))
        let none = try #require(RozoClient.date("2026-10-16T07:29:54+00:00"))
        #expect(abs(short.timeIntervalSince(none) - 0.93) < 0.001)
        #expect(abs(long.timeIntervalSince1970 - 1_792_135_195.079139) < 0.001)
        #expect(RozoClient.date("hier") == nil)
    }

    @Test("Le devis à blanc se lit (montants en texte)")
    func readsDryRun() async throws {
        let client = RozoClient(config: config)
        client.transport = response(200, Self.dryRun)
        let quote = try await client.quote(amount: Decimal(string: "0.1")!, recipient: main)
        #expect(quote == RozoQuote(sourceAmount: Decimal(string: "0.10")!, destinationAmount: Decimal(string: "0.10")!, fee: 0))
    }

    @Test("Montant envoyé : toujours deux décimales, jamais arrondi vers le haut")
    func amountText() {
        #expect(RozoClient.amountText(Decimal(string: "0.1")!) == "0.10")
        #expect(RozoClient.amountText(1) == "1.00")
        #expect(RozoClient.amountText(Decimal(string: "0.109")!) == "0.10")
        #expect(RozoClient.amountText(Decimal(string: "0.05")!) == "0.05")
    }

    @Test("Corps d'une commande : démo testnet, exactIn, Base Sepolia → Stellar, USDC, destinataire en clair")
    func body() throws {
        let client = RozoClient(config: config)
        client.orderReference = { "chimpdao-test" }
        let body = client.body(amount: Decimal(string: "0.1")!, recipient: main)
        let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        #expect(String(decoding: data, as: UTF8.self) == #"{"appId":"rozoDemo","destination":{"chainId":"1500","receiverAddress":"CASBWZTE3GU4VVBC2Q3V6VXCHTG7VLHG45AJXEJ64IVNQSDLEDRBD3RP","tokenSymbol":"USDC"},"display":{"currency":"USD","title":"ChimpDAO"},"orderId":"chimpdao-test","source":{"amount":"0.10","chainId":"84532","tokenSymbol":"USDC"},"type":"exactIn"}"#)
    }

    @Test("Refus de l'API nommés : adresse, montant trop haut ou trop bas ; le reste garde son code")
    func refusals() async {
        let client = RozoClient(config: config)
        client.transport = response(400, #"{"error":{"code":"invalidAddress","message":"destination.receiverAddress invalid for chain"},"requestId":"x"}"#)
        await #expect(throws: RozoError.invalidAddress) { try await client.quote(amount: 1, recipient: main) }
        client.transport = response(400, #"{"error":{"code":"amountTooHigh","message":"amount must be ≤ 1"}}"#)
        await #expect(throws: RozoError.amountTooHigh) { try await client.quote(amount: 2, recipient: main) }
        client.transport = response(400, #"{"error":{"code":"display required","message":"x"}}"#)
        await #expect(throws: RozoError.http(400, "display required: x")) { try await client.quote(amount: 1, recipient: main) }
    }

    // MARK: Contrôle de la commande

    @Test("Une commande qui ne correspond pas à la demande est refusée, champ par champ")
    func mismatches() throws {
        let good = try RozoClient.order(from: Data(Self.createdOrder.utf8))
        func with(_ change: (inout [String: Any]) -> Void) throws -> RozoOrder {
            var object = try #require(try JSONSerialization.jsonObject(with: Data(Self.createdOrder.utf8)) as? [String: Any])
            change(&object)
            return try RozoClient.order(from: JSONSerialization.data(withJSONObject: object))
        }
        func set(_ side: String, _ key: String, _ value: Any) throws -> RozoOrder {
            try with { object in
                var part = object[side] as! [String: Any]
                part[key] = value
                object[side] = part
            }
        }
        let requested = Decimal(string: "0.01")!
        #expect(good.problems(recipient: main, requested: requested, config: config).isEmpty)
        #expect(!good.problems(recipient: "CCDO6J7WOGPTKZA73FWECCIJ75TTOMHMCWLEGPYWIFCNSINM63UJDDYB", requested: requested, config: config).isEmpty)
        let refused = [
            try set("destination", "chainId", "8453"),
            try set("destination", "tokenAddress", "USDC:GA5ZSEJYB37JRC5AVCIA5MOP4RHTM335X2KGX3IHOJAPP5RE34K4KZVN"),
            try set("source", "chainId", "8453"),
            try set("source", "tokenAddress", "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"),
            try set("source", "receiverAddress", "0x1234"),
            try set("source", "amount", 0.07),
            try set("destination", "amount", 0.5),
        ]
        for order in refused {
            #expect(!order.problems(recipient: main, requested: requested, config: config).isEmpty)
        }
        // Un centime ajouté par ROZO pour distinguer deux commandes : accepté.
        #expect(try set("source", "amount", 0.02).problems(recipient: main, requested: requested, config: config).isEmpty)
    }

    @Test("createOrder refuse une commande vers un autre destinataire : rien n'est montré")
    func createRefusesMismatch() async {
        let client = RozoClient(config: config)
        client.transport = response(200, Self.createdOrder)
        await #expect(throws: RozoError.self) {
            try await client.createOrder(amount: Decimal(string: "0.01")!, recipient: "CCDO6J7WOGPTKZA73FWECCIJ75TTOMHMCWLEGPYWIFCNSINM63UJDDYB")
        }
        let order = try? await client.createOrder(amount: Decimal(string: "0.01")!, recipient: main)
        #expect(order?.id == "pay_7xGFFCtr1koYAmkGp1DNu9DL")
    }

    // MARK: Écran N2

    private func model(_ scenario: MockRozo.Scenario = .normal, paidOnStellar: Bool = true) -> (RozoTransferModel, MockRozo) {
        let mock = MockRozo(scenario: scenario, delay: .zero)
        let verifier = MockRozoPayoutVerifier(paid: paidOnStellar)
        return (RozoTransferModel(client: mock, verifier: verifier, config: config, recipient: main, debounce: .zero, pollInterval: .zero), mock)
    }

    private func type(_ text: String, into model: RozoTransferModel) {
        for character in text {
            model.press(character == "." ? .decimal : .digit(Int(String(character))!))
        }
    }

    @Test("Montant hors des bornes : dit tout de suite, pas de devis, pas de commande")
    func bounds() {
        let (model, _) = model()
        type("2", into: model)
        #expect(model.quoteState == .failed(.tooHigh))
        #expect(!model.canCreateOrder)
    }

    @Test("Devis, commande vérifiée, puis suivi jusqu'à l'arrivée")
    func happyPath() async throws {
        let (model, _) = model()
        type("0.1", into: model)
        await model.refreshQuote()
        #expect(model.quoteState == .quoted(RozoQuote(sourceAmount: Decimal(string: "0.1")!, destinationAmount: Decimal(string: "0.1")!, fee: 0)))
        #expect(model.canCreateOrder)
        await model.createOrder()
        let order = try #require(model.order)
        #expect(order.status == .unpaid)
        #expect(order.sourceAmount == Decimal(string: "0.11"))
        await model.track()
        #expect(model.order?.status == .completed)
        #expect(model.order?.destinationTxHash != nil)
        #expect(model.isArrivalVerified)
    }

    @Test("Commande renvoyée ou expirée : l'issue est dite, on peut recommencer")
    func badEndings() async {
        for scenario in [MockRozo.Scenario.bounced, .expired] {
            let (model, _) = model(scenario)
            type("0.5", into: model)
            await model.refreshQuote()
            await model.createOrder()
            await model.track()
            #expect(model.order?.status == (scenario == .bounced ? .bounced : .expired))
            model.startOver()
            #expect(model.phase == .entry)
        }
    }

    @Test("Commande qui ne correspond pas : l'écran le dit, sans adresse de dépôt")
    func mismatchScreen() async {
        let (model, _) = model(.mismatch)
        type("0.5", into: model)
        await model.refreshQuote()
        await model.createOrder()
        #expect(model.phase == .failed(.mismatch))
        #expect(model.order == nil)
    }

    @Test("Compte à rebours : « 9:05 », jamais négatif")
    func countdown() {
        let now = Date(timeIntervalSince1970: 1_000)
        #expect(RozoTransferModel.countdown(545.7) == "9:05")
        #expect(RozoTransferModel.remaining(until: now.addingTimeInterval(-5), now: now) == 0)
        #expect(RozoTransferModel.remaining(until: nil, now: now) == nil)
    }

    @Test("F6 : l'API ROZO dit « payé » mais aucun paiement n'existe sur Stellar → jamais « Arrived »")
    func lyingRozoIsNotEnough() async throws {
        let (model, _) = model(paidOnStellar: false)
        type("0.1", into: model)
        await model.refreshQuote()
        await model.createOrder()
        await model.track()
        // MockRozo annonce `payment_completed` avec un hash qui ne correspond à aucun paiement vérifié sur Stellar.
        #expect(model.order?.status == .completed)
        #expect(!model.isArrivalVerified)
        #expect(model.arrivalCheck == .notFound, "Dit « introuvable » après les essais, jamais « Arrived »")
    }

    // MARK: Vérification sur Stellar (F6)

    private static let payer = "GABWCTTOFK3TBVDLMVZER6JBXLOOCZ6PFDIUSYYU5GTJXP2CPMUYCQ37"
    private static let usdcSAC = "CBIELTK6YBZJU5UP2WWQEUCYKLPU6AUNZ2BQ4WWFEIE3USCIHMXQDAMA"

    private static func event(contract: String = usdcSAC, hash: String, units: Int128) -> ChimpDAO.SorobanClient.ContractEvent {
        let value = Data(try! XDREncoder.encode(ContractArgument.i128(units))).base64EncodedString()
        return ChimpDAO.SorobanClient.ContractEvent(id: "1", contractID: contract, ledger: 5_222_790, ledgerClosedAt: "2026-10-16T07:58:57Z", transactionHash: hash, topics: [], value: value)
    }

    private final class FakeEvents: RozoTransferEvents {
        var events: [ChimpDAO.SorobanClient.ContractEvent] = []
        private(set) var asked: [(String, String, String)] = []
        func latestLedger() async throws -> UInt32 { 5_223_000 }
        func transferEvents(token: String, from: String, to: String, startLedger: UInt32, endLedger: UInt32) async throws -> [ChimpDAO.SorobanClient.ContractEvent] {
            asked.append((token, from, to))
            return events
        }
    }

    @Test("F6 : le vrai paiement de ROZO du 2026-10-16 (0,1 USDC, e7f98fad…) est reconnu ; autre transaction, autre montant, autre contrat : non")
    func stellarVerification() async throws {
        let hash = "e7f98fad7c045eabaf0d036d4ef5defef29798be51d14f383dd959838cb10151"
        let order = MockRozo.order(status: .completed, amount: Decimal(string: "0.1")!, recipient: main, expiresAt: nil)
        let paid = RozoOrder(
            id: order.id, status: .completed, expiresAt: nil, sourceChainId: order.sourceChainId, sourceToken: order.sourceToken,
            sourceAmount: order.sourceAmount, depositAddress: order.depositAddress, destinationChainId: order.destinationChainId,
            destinationAddress: main, destinationToken: order.destinationToken, destinationAmount: Decimal(string: "0.1")!,
            destinationTxHash: hash, errorMessage: nil
        )
        let events = FakeEvents()
        let verifier = StellarRozoPayoutVerifier(events: events, usdc: Self.usdcSAC, payoutAccounts: [Self.payer])
        events.events = [Self.event(hash: hash, units: 1_000_000)]
        #expect(try await verifier.isPaid(paid, recipient: main))
        #expect(events.asked.first?.0 == Self.usdcSAC && events.asked.first?.1 == Self.payer && events.asked.first?.2 == main)
        events.events = [Self.event(hash: "autre", units: 1_000_000)]
        #expect(try await !verifier.isPaid(paid, recipient: main))
        events.events = [Self.event(hash: hash, units: 999_999)]
        #expect(try await !verifier.isPaid(paid, recipient: main))
        events.events = [Self.event(contract: "CDLZFC3SYJYDZT7K67VZ75HPJVIEUVNIXF47ZG2FB2RMQQVU2HHGCYSC", hash: hash, units: 1_000_000)]
        #expect(try await !verifier.isPaid(paid, recipient: main))
    }
}
