import Foundation
import stellarsdk

/// « Arrived via ROZO » n'est dit qu'après avoir vu le paiement **sur Stellar** (revue de sécurité F6, 2026-10-16) : l'API
/// de ROZO peut se tromper ou mentir. Le paiement doit être un `transfer` du SAC USDC de `Config/`, depuis un compte payeur
/// de ROZO de `Config/`, vers le tiroir de la commande, du montant exact de la commande, dans la transaction annoncée.
protocol RozoPayoutVerifying: AnyObject {
    func isPaid(_ order: RozoOrder, recipient: String) async throws -> Bool
}

/// Les événements `transfer` d'un SAC, derrière un protocole pour les tests.
protocol RozoTransferEvents {
    func latestLedger() async throws -> UInt32
    func transferEvents(token: String, from: String, to: String, startLedger: UInt32, endLedger: UInt32) async throws -> [SorobanClient.ContractEvent]
}

extension SorobanClient: RozoTransferEvents {
    func transferEvents(token: String, from: String, to: String, startLedger: UInt32, endLedger: UInt32) async throws -> [ContractEvent] {
        let filter = EventFilter(type: "contract", contractIds: [token], topics: [TopicFilter(segmentMatchers: try PaymentClient.transferTopics(from: from, to: to))])
        return try await contractEvents(filters: [filter], startLedger: startLedger, endLedger: endLedger).events
    }
}

final class StellarRozoPayoutVerifier: RozoPayoutVerifying {
    let events: RozoTransferEvents
    /// Le SAC de l'USDC de `Config/` (jamais déduit de la réponse de ROZO).
    let usdc: String
    let payoutAccounts: [String]
    /// Fenêtre relue : ~3 heures de ledgers (le paiement arrive en quelques secondes ; l'écran le cherche aussitôt).
    static let windowLedgers: UInt32 = 2_000

    init(events: RozoTransferEvents, usdc: String, payoutAccounts: [String]) {
        self.events = events
        self.usdc = usdc
        self.payoutAccounts = payoutAccounts
    }

    func isPaid(_ order: RozoOrder, recipient: String) async throws -> Bool {
        guard let hash = order.destinationTxHash, let units = Self.units(order.destinationAmount) else { return false }
        let latest = try await events.latestLedger()
        let start = latest > Self.windowLedgers ? latest - Self.windowLedgers : 1
        for payer in payoutAccounts {
            let found = try await events.transferEvents(token: usdc, from: payer, to: recipient, startLedger: start, endLedger: latest)
            if Self.contains(found, hash: hash, units: units, token: usdc) { return true }
        }
        return false
    }

    /// Le montant de la commande en unités du SAC (7 décimales), `nil` s'il en a davantage.
    static func units(_ amount: Decimal) -> Decimal? {
        guard amount > 0, let units = try? SACClient.units(of: amount, keypadDecimals: 7) else { return nil }
        return Decimal(units)
    }

    /// Un événement de ce SAC, dans cette transaction, d'un montant `i128` égal à `units`. (Les sujets ont déjà été
    /// filtrés par le RPC ; on revérifie le contrat émetteur, que Stellar fixe et qu'aucun autre contrat ne peut imiter.)
    static func contains(_ events: [SorobanClient.ContractEvent], hash: String, units: Decimal, token: String) -> Bool {
        events.contains { event in
            guard event.contractID == token, event.transactionHash == hash,
                  let data = Data(base64Encoded: event.value), let value = try? XDRDecoder.decode(SCValXDR.self, data: data),
                  case .i128(let parts) = value else { return false }
            return SACClient.decimal(parts) == units
        }
    }
}

/// Vérificateur factice : `paid` décide (catalogue, simulateur, tests).
final class MockRozoPayoutVerifier: RozoPayoutVerifying {
    var paid: Bool
    private(set) var checks = 0

    init(paid: Bool = true) {
        self.paid = paid
    }

    func isPaid(_ order: RozoOrder, recipient: String) async throws -> Bool {
        checks += 1
        return paid && order.destinationTxHash != nil
    }
}
