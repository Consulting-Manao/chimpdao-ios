#if CHIMP_ADMIN
import Foundation
import Security
import stellarsdk

/// Clé secrète admin testnet — **exception à la règle 1** (CLAUDE.md) : clé admin testnet, builds Debug/Testing uniquement.
/// Même rôle que la « service key » du terminal (`session/serviceKey.ts`) : saisie à la main par un opérateur,
/// jamais dans le code ni dans git ; vérifiée à la saisie ; jamais relue à l'écran (seule l'adresse G est montrée).
/// Différence voulue avec le terminal : le trousseau d'iOS au lieu de `localStorage`, et seulement une clé `S…`
/// (pas de phrase de récupération, décision de Barth du 2026-09-29).
protocol AdminKeyStore {
    /// Adresse publique (G…) de la clé enregistrée, ou `nil`. Ne renvoie jamais la clé secrète.
    func publicKey() throws -> String?
    /// Vérifie puis enregistre une clé `S…`. Renvoie son adresse G.
    @discardableResult func save(secretSeed: String) throws -> String
    /// Efface la clé.
    func erase() throws
    /// Paire de clés pour signer. Réservé au service d'enregistrement.
    func keyPair() throws -> KeyPair?
}

enum AdminKeyError: Error, Equatable, LocalizedError {
    /// Ce n'est pas une clé secrète Stellar valide (longueur, version, somme de contrôle).
    case invalidSecretSeed
    /// Erreur du trousseau d'iOS (code `OSStatus`).
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidSecretSeed: "That is not a Stellar secret key (S…)."
        case .keychain(let status): "Keychain error \(status)."
        }
    }
}

/// Stockage dans le trousseau d'iOS : cet appareil uniquement (`WhenUnlockedThisDeviceOnly`),
/// jamais synchronisé par iCloud (`kSecAttrSynchronizable = false`). Une clé par réseau.
/// Aucun journal : ni la clé ni ce qui en dérive n'est jamais écrit dans la console.
struct KeychainAdminKeyStore: AdminKeyStore {
    let service: String

    static let accountName = "stellar-admin-secret"

    init(network: StellarNetwork) {
        switch network {
        case .testnet: service = "com.consulting-manao.chimp.admin.testnet"
        case .mainnet: service = "com.consulting-manao.chimp.admin.mainnet"
        }
    }

    /// Pour les tests : un service à part, pour ne jamais toucher à la vraie clé.
    init(service: String) {
        self.service = service
    }

    /// Attributs qui identifient l'élément.
    var baseQuery: [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: Self.accountName,
            kSecAttrSynchronizable: kCFBooleanFalse as Any,
        ]
    }

    /// Attributs à l'enregistrement : cet appareil uniquement, après déverrouillage, sans iCloud.
    var addAttributes: [CFString: Any] {
        baseQuery.merging([kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]) { $1 }
    }

    func publicKey() throws -> String? {
        try keyPair()?.accountId
    }

    func save(secretSeed: String) throws -> String {
        let trimmed = secretSeed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let keyPair = try? KeyPair(secretSeed: trimmed) else { throw AdminKeyError.invalidSecretSeed }
        try erase()
        var attributes = addAttributes
        attributes[kSecValueData] = Data(trimmed.utf8)
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw AdminKeyError.keychain(status) }
        return keyPair.accountId
    }

    func erase() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AdminKeyError.keychain(status) }
    }

    func keyPair() throws -> KeyPair? {
        var query = baseQuery
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw AdminKeyError.keychain(status) }
        guard let data = result as? Data, let seed = String(data: data, encoding: .utf8),
              let keyPair = try? KeyPair(secretSeed: seed) else {
            throw AdminKeyError.invalidSecretSeed
        }
        return keyPair
    }
}

/// Stockage en mémoire, pour les tests et le simulateur.
final class InMemoryAdminKeyStore: AdminKeyStore {
    private var seed: String?

    init(seed: String? = nil) { self.seed = seed }

    func publicKey() throws -> String? { try keyPair()?.accountId }

    func save(secretSeed: String) throws -> String {
        let trimmed = secretSeed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let keyPair = try? KeyPair(secretSeed: trimmed) else { throw AdminKeyError.invalidSecretSeed }
        seed = trimmed
        return keyPair.accountId
    }

    func erase() throws { seed = nil }

    func keyPair() throws -> KeyPair? {
        guard let seed else { return nil }
        return try KeyPair(secretSeed: seed)
    }
}
#endif
