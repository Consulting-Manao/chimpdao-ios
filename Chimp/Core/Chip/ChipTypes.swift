import Foundation

/// Les deux puces de carte ChimpDAO (ARCHITECTURE §0).
enum ChipKind: String, Equatable, Sendable {
    /// Infineon Blockchain Security 2Go (`infineon2go` dans nfc-bridge).
    case infineon2Go
    /// NXP MIFARE DUOX (`duox` dans nfc-bridge).
    case duox

    var curve: ChipCurve {
        switch self {
        case .infineon2Go: .secp256k1
        case .duox: .p256
        }
    }

    /// Nom technique, non traduit (écrans de développement uniquement).
    var displayName: String {
        switch self {
        case .infineon2Go: "Infineon Blockchain Security 2Go"
        case .duox: "NXP MIFARE DUOX"
        }
    }
}

/// Courbe de la clé de la puce. Les noms sont ceux du terminal (`ChipCurve` dans `chain/types.ts`).
enum ChipCurve: String, Equatable, Sendable {
    case secp256k1 = "secp256k1"
    case p256 = "P-256"
}

/// Clé publique d'une puce : 65 octets SEC1 non compressés (`04 ‖ X ‖ Y`), comme le bridge la renvoie
/// (`pubBytesFromHex` dans `chain/env.ts` refuse toute autre longueur).
struct ChipPublicKey: Equatable, Hashable, Sendable {
    let bytes: Data

    init(_ bytes: Data) throws(ChipError) {
        guard bytes.count == 65, bytes.first == 0x04 else {
            throw .invalidPublicKey(length: bytes.count)
        }
        self.bytes = Data(bytes)
    }

    /// 130 caractères hexadécimaux minuscules, format du bridge (`publicKey` de `read-pubkey`).
    var hex: String { bytes.hexString }
}

/// Ce qu'une lecture de carte rapporte (équivalent de `KeyInfo` du bridge, sans les compteurs).
struct ChipKeyInfo: Equatable, Sendable {
    let kind: ChipKind
    let publicKey: ChipPublicKey
    /// Infineon : octet 0 de la réponse au SELECT = `01`. DUOX : toujours faux (pas de PIN).
    let pinActive: Bool

    var curve: ChipCurve { kind.curve }
}

/// Erreurs de lecture ou de signature d'une puce. Aucune n'est avalée : elles remontent jusqu'à l'écran.
enum ChipError: Error, Equatable, Sendable {
    /// Le téléphone ne sait pas lire le NFC (simulateur, iPhone trop ancien).
    case nfcUnavailable
    /// L'utilisateur a fermé la feuille NFC.
    case cancelled
    /// La limite de 60 s d'Apple est atteinte.
    case timeout
    /// Plusieurs cartes dans le champ.
    case multipleTags
    /// iOS a présenté un tag qu'on ne sait pas interroger par APDU (ni ISO 7816, ni MIFARE DESFire).
    case unsupportedTag(String)
    /// Ni Infineon 2Go ni DUOX (`Unknown chip` dans nfc-bridge).
    case unknownChip
    /// Infineon : la clé n°1 n'existe pas. Une carte sans clé est refusée (règle 6) : on n'en génère jamais.
    case noKey(statusWord: UInt16)
    /// La puce a répondu un statut inattendu à une commande.
    case status(command: String, statusWord: UInt16)
    /// Réponse de la puce illisible ou trop courte.
    case malformedResponse(String)
    /// Clé publique qui n'est pas au format SEC1 non compressé de 65 octets.
    case invalidPublicKey(length: Int)
    /// La liaison radio a échoué (carte retirée trop tôt, session fermée…). Le texte vient d'iOS.
    case transport(String)
    /// La session NFC s'est terminée pour une autre raison. Le texte vient d'iOS.
    case sessionFailed(String)
}

extension ChipError: LocalizedError {
    /// Textes des écrans de développement (mode admin), non traduits.
    var errorDescription: String? {
        switch self {
        case .nfcUnavailable: "This device can't read NFC."
        case .cancelled: "Scan cancelled."
        case .timeout: "The scan timed out (60 s)."
        case .multipleTags: "More than one card in the field. Use only one card."
        case .unsupportedTag(let kind): "This tag can't be read here (\(kind))."
        case .unknownChip: "Unknown chip: not an Infineon 2Go or a MIFARE DUOX."
        case .noKey(let sw): "This card has no key (status \(sw.hexStatus))."
        case .status(let command, let sw): "\(command) failed (status \(sw.hexStatus))."
        case .malformedResponse(let detail): "Unreadable answer from the card: \(detail)"
        case .invalidPublicKey(let length): "The card's public key is not a 65-byte SEC1 key (\(length) bytes)."
        case .transport(let detail): "The connection to the card was lost: \(detail)"
        case .sessionFailed(let detail): "NFC session failed: \(detail)"
        }
    }
}

extension UInt16 {
    /// Statut APDU sur 4 chiffres hexadécimaux (`6A88`).
    var hexStatus: String { String(format: "%04X", self) }
}
