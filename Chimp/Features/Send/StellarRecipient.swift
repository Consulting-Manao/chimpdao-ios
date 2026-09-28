import Foundation
import stellarsdk

/// Destinataire d'un envoi : une adresse Stellar vérifiée (format, version et somme de contrôle).
///
/// Les trois formes acceptées sont celles du terminal (`chain/stellar.ts`, `isAddress`) :
/// - `G…` : compte Stellar classique ;
/// - `M…` : compte classique + un memo ID de 64 bits plié dans l'adresse (SEP-23) ;
/// - `C…` : contrat (un autre wallet ChimpDAO, par exemple).
///
/// La vérification est celle du SDK Stellar (`isValidEd25519PublicKey`, etc.) : longueur, octet de version,
/// somme de contrôle CRC16, et forme canonique du base32. Rien n'est recalculé à la main.
/// Au jalon 5, ce fichier rejoindra `Core/Stellar/` (relecture Pamphile).
struct StellarRecipient: Equatable {
    enum Kind: Equatable {
        case account
        case muxed
        case contract
    }

    /// Adresse exacte qui sera payée (G, M ou C), en majuscules.
    let address: String
    let kind: Kind
    /// Memo ID porté par une adresse M.
    let memoID: UInt64?
}

/// Pourquoi une adresse est refusée. Chaque cas a son message (`SendRecipientView`).
enum RecipientIssue: Error, Equatable {
    /// `S…` : une clé secrète Stellar collée à la place d'une adresse.
    case secretKey
    /// `nom*domaine` : adresse de fédération, hors référence (DESIGN_NOTES §10, point 12).
    case federation
    /// `r…` : adresse XRP Ledger.
    case xrpl
    /// `0x…` : adresse Ethereum (ou compatible).
    case evm
    /// Bonne longueur, bon début, mais la somme de contrôle ne correspond pas : un caractère est faux.
    case typo
    /// Commence comme une adresse Stellar, mais n'a pas la bonne longueur (adresse coupée).
    case wrongLength
    /// Rien de reconnaissable.
    case notStellar
    /// L'adresse d'un de ses propres tiroirs : il faut passer par Move. `name` = nom affiché du tiroir.
    case ownDrawer(name: String, isMain: Bool)
}

/// Pourquoi un memo ID est refusé.
enum MemoIDIssue: Error, Equatable {
    /// Lettres ou symboles : un memo texte ne peut pas partir d'un compte contrat (ARCHITECTURE §3.7).
    case notANumber
    /// Au-delà de 18 446 744 073 709 551 615 (64 bits).
    case tooLarge
}

enum StellarAddressParser {
    /// Longueurs d'une adresse Stellar (SEP-23) : G, C = 56 caractères ; M = 69.
    static let standardLength = 56
    static let muxedLength = 69

    /// Retire les espaces et retours à la ligne, où qu'ils soient (un copier-coller en ajoute souvent).
    static func clean(_ input: String) -> String {
        input.filter { !$0.isWhitespace }
    }

    /// Vérifie une adresse saisie. `nil` si le champ est vide.
    static func parse(_ input: String) -> Result<StellarRecipient, RecipientIssue>? {
        let cleaned = clean(input)
        guard !cleaned.isEmpty else { return nil }

        if cleaned.contains("*") { return .failure(.federation) }
        if cleaned.range(of: #"^0[xX][0-9a-fA-F]{40}$"#, options: .regularExpression) != nil { return .failure(.evm) }
        // Alphabet base58 de l'XRP Ledger, 25 à 35 caractères, commence par « r ».
        if cleaned.range(of: #"^r[1-9A-HJ-NP-Za-km-z]{24,34}$"#, options: .regularExpression) != nil {
            return .failure(.xrpl)
        }

        // Les adresses Stellar sont en majuscules ; une adresse tapée en minuscules désigne le même compte.
        let candidate = cleaned.uppercased()
        if candidate.hasPrefix("S") && candidate.count == standardLength {
            // Clé secrète valide ou presque : dans tous les cas, prévenir.
            return .failure(.secretKey)
        }
        if candidate.isValidEd25519PublicKey() {
            return .success(StellarRecipient(address: candidate, kind: .account, memoID: nil))
        }
        if candidate.isValidMed25519PublicKey() {
            guard let memoID = try? candidate.decodeMuxedAccount().id else { return .failure(.typo) }
            return .success(StellarRecipient(address: candidate, kind: .muxed, memoID: memoID))
        }
        if candidate.isValidContractId() {
            return .success(StellarRecipient(address: candidate, kind: .contract, memoID: nil))
        }

        switch candidate.first {
        case "G", "C":
            return .failure(candidate.count == standardLength ? .typo : .wrongLength)
        case "M":
            return .failure(candidate.count == muxedLength ? .typo : .wrongLength)
        default:
            return .failure(.notStellar)
        }
    }

    /// Vérifie un memo ID saisi (chiffres seulement, 64 bits). `nil` si le champ est vide.
    static func parseMemoID(_ input: String) -> Result<UInt64, MemoIDIssue>? {
        let cleaned = clean(input)
        guard !cleaned.isEmpty else { return nil }
        guard cleaned.allSatisfy({ $0.isASCII && $0.isNumber }) else { return .failure(.notANumber) }
        guard let value = UInt64(cleaned) else { return .failure(.tooLarge) }
        return .success(value)
    }

    /// Plie un memo ID dans l'adresse d'un compte G : l'adresse M obtenue désigne le même compte,
    /// avec l'ID dedans (SEP-23 : clé de 32 octets **puis** ID de 8 octets, encodés par le SDK).
    ///
    /// ⚠️ Écart avec la référence : `withMemoId` du terminal (`chain/address.ts`) place l'ID **avant** la clé,
    /// ce qui désignerait un autre compte. Question posée à Pamphile (DESIGN_NOTES §12).
    static func folding(memoID: UInt64, into recipient: StellarRecipient) -> StellarRecipient? {
        guard recipient.kind == .account,
              let muxed = try? MuxedAccount(accountId: recipient.address, id: memoID).accountId,
              muxed.isValidMed25519PublicKey(),
              // Contrôle : l'adresse M redonne bien le compte G et l'ID de départ.
              let decoded = try? muxed.decodeMuxedAccount(),
              decoded.ed25519AccountId == recipient.address,
              decoded.id == memoID
        else { return nil }
        return StellarRecipient(address: muxed, kind: .muxed, memoID: memoID)
    }

    /// Adresse raccourcie : 4 premiers caractères…4 derniers (« GBM2…4XQA », maquette C1).
    static func short(_ address: String) -> String {
        address.count > 12 ? "\(address.prefix(4))…\(address.suffix(4))" : address
    }
}
