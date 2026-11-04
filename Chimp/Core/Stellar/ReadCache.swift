import Foundation

/// Mémoire courte des lectures sur la chaîne (soldes, positions, cartes d'un compte), pour que passer du Wallet à Envoyer,
/// Swap ou Grow ne refasse pas les mêmes simulations. Portage de `reference/terminal/src/chain/read-cache.ts` :
///
/// - Toute écriture réussie vide tout (`invalidate`, appelé par `SorobanClient.submitAndWait`, le seul passage de tous les
///   envois) : l'app ne montre jamais les chiffres d'avant une opération.
/// - Une durée bornée (60 s) limite le retard de toute façon : de l'argent peut bouger en dehors de l'app.
/// - Pendant les 20 s qui suivent une écriture, une lecture ne vaut que 1,5 s : le RPC peut encore rendre l'état d'avant.
/// - En mémoire seulement, jamais enregistré ; une lecture ratée n'est jamais gardée. Deux lectures identiques lancées en
///   même temps n'en font qu'une.
final class ReadCache {
    static let shared = ReadCache()

    /// Bien plus long qu'un passage d'écran, assez court pour qu'un mouvement venu d'ailleurs se voie en une minute.
    static let readTTL: Duration = .seconds(60)
    static let settlingTTL: Duration = .milliseconds(1_500)
    static let settlingWindow: Duration = .seconds(20)

    private struct Entry {
        let at: ContinuousClock.Instant
        /// `nil` : sans limite de durée.
        let ttl: Duration?
        /// `Task<T, Error>` de la lecture, retrouvé par sa clé (une clé = un seul type).
        let task: Any
        let id: UUID
    }

    private var store: [String: Entry] = [:]
    /// Jusqu'à quand une lecture peut encore rendre l'état d'avant la dernière écriture.
    private var settlingUntil: ContinuousClock.Instant?
    private let now: () -> ContinuousClock.Instant

    init(now: @escaping () -> ContinuousClock.Instant = { .now }) {
        self.now = now
    }

    /// La valeur gardée pour `key` si elle est encore valable, sinon `read()` (gardée si elle réussit). `ttl` : `nil` pour
    /// une réponse qui ne change jamais (la Pocket d'une carte), vidée seulement par une écriture.
    func read<T>(_ key: String, ttl: Duration? = ReadCache.readTTL, _ read: @escaping () async throws -> T) async throws -> T {
        let instant = now()
        if let hit = store[key], hit.ttl.map({ instant - hit.at < $0 }) ?? true, let task = hit.task as? Task<T, Error> {
            return try await task.value
        }
        let task = Task { try await read() }
        let id = UUID()
        let settling = settlingUntil.map { instant < $0 } ?? false
        store[key] = Entry(at: instant, ttl: settling ? Self.settlingTTL : ttl, task: task, id: id)
        do {
            return try await task.value
        } catch {
            // Une lecture ratée ne doit pas servir : la suivante réessaie.
            if store[key]?.id == id { store[key] = nil }
            throw error
        }
    }

    /// De l'argent vient de bouger : tout ce qui est gardé est l'état d'avant, et ce qui sera lu dans les secondes qui
    /// suivent peut l'être aussi.
    func invalidate() {
        store.removeAll()
        settlingUntil = now() + Self.settlingWindow
    }

    /// « Tirer pour rafraîchir » : tout relire, sans la fenêtre d'après une écriture.
    func clear() {
        store.removeAll()
    }
}
