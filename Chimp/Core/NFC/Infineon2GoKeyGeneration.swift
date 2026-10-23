#if CHIMP_ADMIN
import Foundation

/// Génération de la clé n°1 d'une Infineon 2Go vierge — **mode admin uniquement** (drapeau `CHIMP_ADMIN`,
/// Debug et Testing), jamais dans l'app publiée. Exception à la règle 6 accordée par Pamphile le 2026-09-29 :
/// seulement si le slot 1 est vide (`6A88`), jamais sur une carte qui a déjà une clé.
///
/// Portage de `ensureKey()` (`nfc-bridge/packages/client/src/client.ts`, utilisé par `scripts/test-sign.js`)
/// et de `generateKey()` (`server/chips/infineon2go.js`), avec une garde plus stricte :
/// - le bridge génère dès que la lecture de la clé échoue avec `6A88`, `6A82` ou `6985` (`keyMissing`) ;
///   ici, **seul `6A88`** (« clé absente à cet index ») autorise la génération, et c'est revérifié dans la même
///   session NFC, juste avant, sur la carte réellement présente ;
/// - le bridge accepte l'index de clé renvoyé par la puce ; ici, tout autre index que 1 est une erreur.
///
/// Séquence envoyée (une seule session) :
/// 1. SELECT (détection Infineon) ;
/// 2. SELECT puis GET KEY INFO clé 1 → doit répondre `6A88` ;
/// 3. SELECT puis GENERATE KEY `00 02 00 00 00` → octet 0 de la réponse = index de la clé créée ;
/// 4. SELECT puis GET KEY INFO sur cet index → clé publique (`getPubkey(keyId)` du bridge).
extension Infineon2Go {
    /// Seul statut qui autorise la génération : aucune clé à l'index 1.
    static let emptyKeySlotStatusWord: UInt16 = 0x6A88

    /// GENERATE KEY : `00 02 00 00 00` (`generateKey` du bridge).
    static var generateKeyAPDU: Data { Data([0x00, 0x02, 0x00, 0x00, 0x00]) }

    /// Réponse à GENERATE KEY → index de la clé créée (octet 0, `res[0]` dans le bridge).
    static func parseGenerateKey(_ response: APDUResponse) throws(ChipError) -> UInt8 {
        guard response.statusWord == 0x9000 else {
            throw .status(command: "GENERATE KEY", statusWord: response.statusWord)
        }
        guard let keyID = response.data.first else {
            throw .malformedResponse("GENERATE KEY returned no key index")
        }
        return keyID
    }

    /// Vérifie, sur la carte présente, que le slot 1 est vide. Lève une erreur dans tous les autres cas :
    /// clé déjà présente, autre statut (`6A82`, `6985`…), réponse inattendue.
    static func requireEmptyKeySlot(_ transport: some APDUTransport) async throws {
        _ = try parseSelect(try await transport.send(selectAPDU))
        let response = try await transport.send(getKeyInfoAPDU(keyID: defaultKeyID))
        switch response.statusWord {
        case emptyKeySlotStatusWord:
            return
        case 0x9000:
            throw ChipError.keyAlreadyPresent
        default:
            throw ChipError.status(command: "GET KEY INFO", statusWord: response.statusWord)
        }
    }

    /// Génère la clé n°1 sur une Infineon dont le slot 1 est vide, puis la relit.
    static func generateKeyOnEmptySlot(_ transport: some APDUTransport) async throws -> ChipKeyInfo {
        try await requireEmptyKeySlot(transport)

        _ = try parseSelect(try await transport.send(selectAPDU))
        let keyID = try parseGenerateKey(try await transport.send(generateKeyAPDU))
        guard keyID == defaultKeyID else {
            // La clé existe désormais à cet index et ne peut pas être effacée : on le signale tel quel.
            throw ChipError.unexpectedKeySlot(keyID)
        }

        let pinActive = try parseSelect(try await transport.send(selectAPDU))
        let key = try parseKeyInfo(try await transport.send(getKeyInfoAPDU(keyID: keyID)))
        return ChipKeyInfo(kind: .infineon2Go, publicKey: key, pinActive: pinActive)
    }
}

/// Génération de clé sur une carte déjà connectée : Infineon uniquement (la DUOX a une clé d'usine et ne sait
/// pas en générer, `capabilities.generateKey: false` dans le bridge). Même ordre de détection que la lecture.
enum ChipKeyGeneration {
    static func generateKey(_ transport: some APDUTransport) async throws -> ChipKeyInfo {
        if try await Infineon2Go.detect(transport) != nil {
            return try await Infineon2Go.generateKeyOnEmptySlot(transport)
        }
        if try await Duox.detect(transport) {
            throw ChipError.keyGenerationUnsupported(ChipKind.duox.displayName)
        }
        throw ChipError.unknownChip
    }

    /// « Prepare a card » (Chimp Admin), **dans une seule session NFC** : la clé n°1 est créée seulement si le slot 1 est
    /// vide (`6A88`, même garde que `generateKey`) ; une carte qui a déjà une clé est simplement lue, sans rien générer.
    /// Avant (2026-10-23) : une session de génération qui se terminait en erreur (« already has a key »), puis une
    /// seconde session de lecture ; sur iPhone, la seconde ne s'enchaînait pas et la carte ne pouvait pas être reprise.
    /// Une DUOX (clé d'usine) est lue ; une carte inconnue est refusée.
    static func readOrGenerateKey(_ transport: some APDUTransport) async throws -> ChipKeyInfo {
        if try await Infineon2Go.detect(transport) != nil {
            do {
                return try await Infineon2Go.generateKeyOnEmptySlot(transport)
            } catch ChipError.keyAlreadyPresent {
                return try await ChipDetector.readKey(transport)
            }
        }
        if try await Duox.detect(transport) {
            return try await ChipDetector.readKey(transport)
        }
        throw ChipError.unknownChip
    }
}

/// Génère la clé n°1 d'une carte vierge. Implémenté par `NFCChipKeyGenerator` et `MockChipKeyGenerator`.
protocol ChipKeyGenerator {
    func generateKeyOnEmptySlot() async throws -> ChipKeyInfo
    /// Lit la carte, et crée sa clé n°1 seulement si le slot 1 est vide : une seule session NFC.
    func readOrGenerateKey() async throws -> ChipKeyInfo
}

/// Génération par Core NFC : une feuille NFC, une carte.
struct NFCChipKeyGenerator: ChipKeyGenerator {
    func generateKeyOnEmptySlot() async throws -> ChipKeyInfo {
        try await NFCTagSession.run(
            alertMessage: "Hold the blank card near the top of your iPhone. Don't move it until it's done.",
            successMessage: "Key generated."
        ) { transport in
            try await ChipKeyGeneration.generateKey(transport)
        }
    }

    func readOrGenerateKey() async throws -> ChipKeyInfo {
        try await NFCTagSession.run(
            alertMessage: "Hold the card near the top of your iPhone. Don't move it until it's done.",
            successMessage: "Card ready."
        ) { transport in
            try await ChipKeyGeneration.readOrGenerateKey(transport)
        }
    }
}

/// Faux générateur : réussit seulement si le scénario choisi est une carte sans clé, comme la vraie garde.
struct MockChipKeyGenerator: ChipKeyGenerator {
    var scenario: MockChipReader.Scenario
    var delay: Duration = .milliseconds(900)

    func generateKeyOnEmptySlot() async throws -> ChipKeyInfo {
        try await Task.sleep(for: delay)
        switch scenario {
        case .noKey:
            return ChipKeyInfo(kind: .infineon2Go, publicKey: MockChipReader.secp256k1Key, pinActive: false)
        case .infineon, .infineonWithPIN:
            throw ChipError.keyAlreadyPresent
        case .duox:
            throw ChipError.keyGenerationUnsupported(ChipKind.duox.displayName)
        case .unknownChip, .cardRemoved, .cancelled:
            return try await MockChipReader(scenario: scenario, delay: .zero).readKey()
        }
    }

    func readOrGenerateKey() async throws -> ChipKeyInfo {
        if scenario == .noKey { return try await generateKeyOnEmptySlot() }
        return try await MockChipReader(scenario: scenario, delay: delay).readKey()
    }
}
#endif
