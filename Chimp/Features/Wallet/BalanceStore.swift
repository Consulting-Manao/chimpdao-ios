import Foundation

/// Derniers soldes lus de chaque compte, pour que le Wallet s'affiche tout de suite au lancement, puis se relise sur la
/// chaîne (demande de Barth du 2026-11-04). **Affichage seulement** : aucun envoi ne s'en sert, chacun relit la chaîne
/// avant de signer. Des montants, aucun secret ; protégés comme l'historique (`completeFileProtection`), effacés par
/// « Erase everything on this phone ». Écart avec le terminal, qui ne garde rien d'un lancement à l'autre (DESIGN_NOTES §13).
protocol BalanceStore: AnyObject {
    /// Les derniers soldes lus de ce compte, `nil` s'il n'y en a pas (ou si le fichier est illisible).
    func snapshot(of account: String) -> WalletSnapshot?
    /// Garder ces soldes. Un échec d'écriture n'est pas grave : le Wallet se relira au prochain lancement.
    func save(_ snapshot: WalletSnapshot, of account: String)
    func erase() throws
}

/// Le fichier, à côté de celui de l'historique.
struct StoredBalances: Codable, Equatable {
    static let currentVersion = 1

    var version = StoredBalances.currentVersion
    var accounts: [String: WalletSnapshot] = [:]
}

final class FileBalanceStore: BalanceStore {
    let fileURL: URL

    init(network: StellarNetwork, directory: URL? = nil) throws {
        let base = try directory ?? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let folder = base.appending(path: "ChimpDAO", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appending(path: "balances-\(network.rawValue).json")
    }

    private func load() -> StoredBalances {
        guard let data = try? Data(contentsOf: fileURL),
              let stored = try? FileLocalWalletStore.decoder.decode(StoredBalances.self, from: data),
              stored.version == StoredBalances.currentVersion else { return StoredBalances() }
        return stored
    }

    func snapshot(of account: String) -> WalletSnapshot? {
        load().accounts[account]
    }

    func save(_ snapshot: WalletSnapshot, of account: String) {
        var stored = load()
        stored.accounts[account] = snapshot
        try? FileLocalWalletStore.encoder.encode(stored).write(to: fileURL, options: FileLocalWalletStore.writingOptions)
    }

    func erase() throws {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }
}

/// En mémoire, pour les tests, le catalogue et le simulateur.
final class InMemoryBalanceStore: BalanceStore {
    private(set) var stored = StoredBalances()

    func snapshot(of account: String) -> WalletSnapshot? { stored.accounts[account] }

    func save(_ snapshot: WalletSnapshot, of account: String) { stored.accounts[account] = snapshot }

    func erase() throws { stored = StoredBalances() }
}

// Pour écrire les soldes : la puce et la couleur d'une carte, par leur nom (`rawValue`), comme dans le fichier du wallet.
extension ChipKind: Codable {}
extension ChimpCardColor: Codable {}
