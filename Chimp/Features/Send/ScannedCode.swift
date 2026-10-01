import Foundation

/// Pourquoi un code QR scanné en C1 est refusé. Chaque cas a son message (`SendRecipientView`).
enum ScanIssue: Error, Equatable {
    /// L'adresse du code est refusée (clé secrète, caractère faux, XRP…) : même message que pour une adresse collée.
    case address(RecipientIssue)
    /// `web+stellar:tx` : une transaction à signer, pas une adresse.
    case signRequest
    /// Lien de paiement qui veut recevoir la signature sur un site (`callback`) au lieu d'un paiement direct.
    case callback
    /// Lien de paiement pour un autre réseau Stellar (`network_passphrase` ; absent = réseau public, SEP-7).
    case otherNetwork
    /// Memo texte, hash ou retour : impossible depuis un compte contrat (comme dans C1).
    case wordMemo
    /// Un memo dans le lien **et** un autre dans l'adresse M.
    case conflictingMemo
    /// Actif qu'on ne sait pas envoyer (autre code, ou USDC d'un autre émetteur).
    case unsupportedAsset(String)
    /// Ni une adresse Stellar ni un lien de paiement.
    case notAPaymentCode
}

/// Ce qu'on attend d'un lien de paiement sur le réseau de l'app.
struct ScanRules: Equatable {
    let passphrase: String
    /// Réseau public (mainnet) : un lien SEP-7 sans `network_passphrase` le désigne.
    let isPublicNetwork: Bool
    /// Seul émetteur d'USDC accepté (`Config/`).
    let usdcIssuer: String

    init(config: ChimpNetworkConfig) {
        passphrase = config.passphrase
        isPublicNetwork = config.network == .mainnet
        usdcIssuer = config.usdcIssuer
    }
}

/// Lit le contenu d'un code QR scanné en C1 (hors `reference/` : le terminal ne scanne pas ; DESIGN_NOTES §13) :
/// - une adresse seule, G, M ou C, vérifiée comme une adresse collée (`StellarAddressParser`) ;
/// - un lien de paiement SEP-7 `web+stellar:pay?destination=…`, avec `amount`, `asset_code`, `asset_issuer`,
///   `memo` + `memo_type=MEMO_ID` facultatifs.
///
/// On n'affiche jamais `msg` ni `origin_domain` (SEP-7 impose de vérifier `signature` avant de montrer le domaine) :
/// seuls l'adresse, l'actif et le montant sont repris, puis revus en C1, C2 et C4. Le reste est refusé plutôt que
/// deviné.
enum ScannedCodeParser {
    static let scheme = "web+stellar:"

    static func parse(_ payload: String, rules: ScanRules) -> Result<SendPrefill, ScanIssue> {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix(scheme) {
            return parseLink(trimmed, rules: rules)
        }
        switch StellarAddressParser.parse(trimmed) {
        case .success(let recipient)?:
            return .success(SendPrefill(address: recipient.address, origin: .scan))
        case .failure(.notStellar)?, nil:
            return .failure(.notAPaymentCode)
        case .failure(let issue)?:
            return .failure(.address(issue))
        }
    }

    private static func parseLink(_ link: String, rules: ScanRules) -> Result<SendPrefill, ScanIssue> {
        guard let components = URLComponents(string: link) else { return .failure(.notAPaymentCode) }
        switch components.path.lowercased() {
        case "tx": return .failure(.signRequest)
        case "pay": break
        default: return .failure(.notAPaymentCode)
        }
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] where query[item.name] == nil {
            query[item.name] = item.value ?? ""
        }

        let passphrase = query["network_passphrase"]
        if let passphrase, passphrase != rules.passphrase { return .failure(.otherNetwork) }
        if passphrase == nil, !rules.isPublicNetwork { return .failure(.otherNetwork) }
        if let callback = query["callback"], !callback.isEmpty { return .failure(.callback) }

        guard let destination = query["destination"], !destination.isEmpty else { return .failure(.notAPaymentCode) }
        let recipient: StellarRecipient
        switch StellarAddressParser.parse(destination) {
        case .success(let found)?: recipient = found
        case .failure(let issue)?: return .failure(.address(issue))
        case nil: return .failure(.notAPaymentCode)
        }

        // Actif : XLM sans code ni émetteur ; USDC seulement de l'émetteur de `Config/`.
        let code = query["asset_code"].flatMap { $0.isEmpty ? nil : $0 }
        let issuer = query["asset_issuer"].flatMap { $0.isEmpty ? nil : $0 }
        let asset: SendAsset
        switch (code?.uppercased(), issuer) {
        case (nil, nil), ("XLM", nil): asset = .xlm
        case ("USDC", .some(rules.usdcIssuer)): asset = .usdc
        default: return .failure(.unsupportedAsset(code ?? "?"))
        }

        // Memo : seulement un memo ID (64 bits) pour une adresse G ; les autres types ne partent pas d'un compte contrat.
        var memoID: UInt64?
        if let memo = query["memo"], !memo.isEmpty {
            guard query["memo_type"]?.uppercased() == "MEMO_ID" else { return .failure(.wordMemo) }
            guard case .success(let id)? = StellarAddressParser.parseMemoID(memo) else { return .failure(.wordMemo) }
            switch recipient.kind {
            case .account: memoID = id
            case .muxed: if recipient.memoID != id { return .failure(.conflictingMemo) }
            case .contract: return .failure(.wordMemo)
            }
        }

        // Montant : nombre positif écrit avec un point (SEP-7). Illisible : ignoré, on le tapera en C2.
        var amount: Decimal?
        if let text = query["amount"], let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")), value > 0,
           text.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }) {
            amount = value
        }

        return .success(SendPrefill(address: recipient.address, memoID: memoID, asset: asset, amount: amount, origin: .scan))
    }
}
