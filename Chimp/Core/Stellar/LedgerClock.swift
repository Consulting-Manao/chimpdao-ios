import Foundation

/// Un point de repère : tel ledger a été vu fermé à telle heure.
struct LedgerAnchor: Codable, Equatable, Sendable {
    let ledger: UInt32
    let time: Date
}

/// Où l'app garde le dernier ledger vu (le téléphone).
protocol LedgerAnchorStore: AnyObject {
    func load() -> LedgerAnchor?
    func save(_ anchor: LedgerAnchor)
}

enum LedgerClockError: Error, Equatable, LocalizedError {
    /// Le RPC annonce un ledger que l'horloge du téléphone ne permet pas encore.
    case aheadOfClock(ledger: UInt32, maximum: UInt32)

    var errorDescription: String? {
        "Stellar's answer doesn't match your phone's clock, so nothing was signed. Check your phone's date and time, then try again."
    }
}

/// Revue de sécurité F3, partie 1 (2026-10-16) : le numéro de ledger dont dépend l'expiration d'une autorisation vient
/// du RPC. Sans plafond, un RPC menteur pourrait annoncer un ledger lointain et faire signer une autorisation valable des
/// mois. `LedgerClock` le confronte à l'horloge du téléphone : depuis un repère (un ledger vu à une heure donnée), le
/// réseau ne ferme pas plus d'un ledger toutes les `minimumLedgerSeconds`. Le repère est celui de `Config/` et le dernier
/// ledger accepté sur ce téléphone ; le plus serré des deux s'applique. Une marge d'un jour couvre une horloge un peu fausse.
///
/// Ce plafond borne la durée de vie d'une autorisation retenue à environ un jour au pire (au lieu de mois) ; la vraie
/// correction de F3 (réutiliser le nonce pour « Try again ») attend la relecture de Pamphile.
final class LedgerClock {
    /// Stellar ferme un ledger toutes les ~5 à 6 s ; 4 s laisse de la marge.
    static let minimumLedgerSeconds: Double = 4
    /// ~1 jour de ledgers (à 5 s).
    static let marginLedgers: UInt32 = 17_280

    let anchor: LedgerAnchor?
    let store: LedgerAnchorStore
    var now: () -> Date = { .now }

    init(anchor: LedgerAnchor?, store: LedgerAnchorStore) {
        self.anchor = anchor
        self.store = store
    }

    /// Le plus grand ledger crédible maintenant, `nil` sans aucun repère.
    func maximumLedger() -> UInt32? {
        let bounds = [anchor, store.load()].compactMap { $0 }.map { Self.bound(from: $0, now: now()) }
        return bounds.min()
    }

    static func bound(from anchor: LedgerAnchor, now: Date) -> UInt32 {
        let elapsed = max(0, now.timeIntervalSince(anchor.time))
        let ledgers = min(Double(SorobanClient.maximumLedger), (elapsed / minimumLedgerSeconds).rounded(.up))
        let total = UInt64(anchor.ledger) + UInt64(ledgers) + UInt64(marginLedgers)
        return UInt32(min(total, UInt64(SorobanClient.maximumLedger)))
    }

    /// Le ledger annoncé, s'il est crédible au regard de l'horloge du téléphone ; il devient alors le repère du téléphone
    /// (s'il est plus récent que le précédent).
    func checked(_ ledger: UInt32) throws -> UInt32 {
        if let maximum = maximumLedger(), ledger > maximum { throw LedgerClockError.aheadOfClock(ledger: ledger, maximum: maximum) }
        if ledger > store.load()?.ledger ?? 0 { store.save(LedgerAnchor(ledger: ledger, time: now())) }
        return ledger
    }

    /// Une horloge par réseau, partagée par tous les clients (dernier ledger vu gardé sur le téléphone).
    private static var clocks: [String: LedgerClock] = [:]
    private static let lock = NSLock()

    static func shared(for config: ChimpNetworkConfig) -> LedgerClock {
        lock.lock()
        defer { lock.unlock() }
        if let clock = clocks[config.passphrase] { return clock }
        let clock = LedgerClock(anchor: config.ledgerAnchor, store: DefaultsLedgerAnchorStore(key: "ledgerClock.\(config.network)"))
        clocks[config.passphrase] = clock
        return clock
    }

    /// « Erase everything on this phone » : les horloges en mémoire sont oubliées (le dernier ledger vu est effacé des
    /// préférences par `PhoneData.eraseAll`). La suivante repart du repère de `Config/`.
    static func forgetShared() {
        lock.lock()
        defer { lock.unlock() }
        clocks = [:]
    }
}

/// Le dernier ledger accepté, gardé dans les préférences du téléphone (un numéro et une heure, rien de secret).
final class DefaultsLedgerAnchorStore: LedgerAnchorStore {
    let key: String
    init(key: String) { self.key = key }

    func load() -> LedgerAnchor? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(LedgerAnchor.self, from: $0) }
    }

    func save(_ anchor: LedgerAnchor) {
        if let data = try? JSONEncoder().encode(anchor) { UserDefaults.standard.set(data, forKey: key) }
    }
}

final class MemoryLedgerAnchorStore: LedgerAnchorStore {
    private var anchor: LedgerAnchor?
    init(_ anchor: LedgerAnchor? = nil) { self.anchor = anchor }
    func load() -> LedgerAnchor? { anchor }
    func save(_ anchor: LedgerAnchor) { self.anchor = anchor }
}
