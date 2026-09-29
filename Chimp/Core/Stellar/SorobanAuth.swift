import CryptoKit
import Foundation
import Security
import stellarsdk

/// Entrées d'autorisation Soroban signées par une puce (modèle A, ARCHITECTURE §3.2 et §3.3).
/// Portage de `reference/terminal/src/chain/chip-auth.ts` : `addressCreds`, `credsKind`, `restamp`,
/// `authPayloadHash`, `preSignedAuthEntries` / `preSignedAuthEntry`.
///
/// La puce signe toujours le même objet : `sha256(HashIdPreimage…)`, qui couvre le réseau, le nonce,
/// l'expiration et l'appel (contrat, fonction, arguments, sous-appels). Ni les frais ni l'empreinte n'y sont :
/// c'est pour cela qu'on peut recalculer les frais après la signature sans refaire signer la carte.
enum SorobanAuth {
    /// `AUTH_EXPIRATION_LEDGERS` (`chain/env.ts`) : environ 10 minutes.
    static let expirationLedgers: UInt32 = 120
    /// `EXPIRATION_MARGIN_LEDGERS` : en dessous de 20 ledgers restants (~2 min), on reconstruit l'entrée avant le tap.
    static let expirationMarginLedgers: UInt32 = 20

    enum AuthError: Error, Equatable, LocalizedError {
        /// L'entrée ne porte pas de credentials d'adresse (V1 ou V2) : erreur de l'appelant, jamais un cas à signer.
        case notAddressCredentials(String)
        /// Le générateur aléatoire du système a échoué.
        case randomUnavailable

        var errorDescription: String? {
            switch self {
            case .notAddressCredentials(let kind): "Expected address credentials, got \(kind)."
            case .randomUnavailable: "The system random generator failed."
            }
        }
    }

    // MARK: Credentials (V1 et V2)

    /// `addressCreds` : la partie « adresse » des credentials, pour les deux variantes du Protocol 28.
    static func addressCredentials(_ entry: SorobanAuthorizationEntryXDR) throws(AuthError) -> SorobanAddressCredentialsXDR {
        switch entry.credentials {
        case .address(let credentials), .addressV2(let credentials): return credentials
        case .sourceAccount: throw .notAddressCredentials("source account")
        case .addressWithDelegates: throw .notAddressCredentials("address with delegates")
        }
    }

    /// `credsKind == "sorobanCredentialsAddressV2"`.
    static func isAddressV2(_ entry: SorobanAuthorizationEntryXDR) -> Bool {
        if case .addressV2 = entry.credentials { return true }
        return false
    }

    /// `restamp` : copie de l'entrée avec une expiration ou une signature remplacée, **dans la variante reçue**
    /// (règle 4 : V1 et V2 ne signent pas le même préimage, on ne convertit jamais).
    static func restamped(
        _ entry: SorobanAuthorizationEntryXDR,
        expirationLedger: UInt32? = nil,
        signature: SCValXDR? = nil
    ) throws(AuthError) -> SorobanAuthorizationEntryXDR {
        var credentials = try addressCredentials(entry)
        if let expirationLedger { credentials.signatureExpirationLedger = expirationLedger }
        if let signature { credentials.signature = signature }
        return SorobanAuthorizationEntryXDR(
            credentials: isAddressV2(entry) ? .addressV2(credentials) : .address(credentials),
            rootInvocation: entry.rootInvocation
        )
    }

    // MARK: Digest

    /// `authPayloadHash` : ce que la puce signe pour une entrée, à l'expiration choisie.
    /// V2 hashe `HashIdPreimageSorobanAuthorizationWithAddress` (mêmes champs + l'adresse), V1 `HashIdPreimageSorobanAuthorization`.
    static func payloadHash(
        _ entry: SorobanAuthorizationEntryXDR,
        passphrase: String,
        expirationLedger: UInt32
    ) throws -> Data {
        let credentials = try addressCredentials(entry)
        let networkID = HashXDR(Data(SHA256.hash(data: Data(passphrase.utf8))))
        let preimage: HashIDPreimageXDR = isAddressV2(entry)
            ? .sorobanAuthorizationWithAddress(HashIDPreimageSorobanAuthorizationWithAddressXDR(
                networkID: networkID,
                nonce: credentials.nonce,
                signatureExpirationLedger: expirationLedger,
                address: credentials.address,
                invocation: entry.rootInvocation
            ))
            : .sorobanAuthorization(HashIDPreimageSorobanAuthorizationXDR(
                networkID: networkID,
                nonce: credentials.nonce,
                signatureExpirationLedger: expirationLedger,
                invocation: entry.rootInvocation
            ))
        return Data(SHA256.hash(data: Data(try XDREncoder.encode(preimage))))
    }

    // MARK: Ordre 1 : déclarer, signer, puis simuler

    /// Appel d'une fonction de contrat, tel qu'il figure dans une entrée d'autorisation (`SorobanAuthorizedInvocation`).
    static func contractInvocation(
        contract: String,
        function: String,
        arguments: [SCValXDR],
        subInvocations: [SorobanAuthorizedInvocationXDR] = []
    ) throws -> SorobanAuthorizedInvocationXDR {
        SorobanAuthorizedInvocationXDR(
            function: .contractFn(InvokeContractArgsXDR(
                contractAddress: try SCAddressXDR(contractId: contract),
                functionName: function,
                args: arguments
            )),
            subInvocations: subInvocations
        )
    }

    /// Entrée déclarée sans signature (`build` de `preSignedAuthEntries`) : credentials **V1**, signature `void`.
    /// Le terminal construit ses propres entrées en V1 (« elles passent très bien ») ; seules les entrées reçues
    /// d'une simulation peuvent être en V2.
    static func declaredEntry(
        authorizer: String,
        invocation: SorobanAuthorizedInvocationXDR,
        nonce: Int64,
        expirationLedger: UInt32
    ) throws -> SorobanAuthorizationEntryXDR {
        SorobanAuthorizationEntryXDR(
            credentials: .address(SorobanAddressCredentialsXDR(
                address: try SCAddressXDR(contractId: authorizer),
                nonce: nonce,
                signatureExpirationLedger: expirationLedger,
                signature: .void
            )),
            rootInvocation: invocation
        )
    }

    /// Nonce aléatoire sur 8 octets lus en grand-boutiste signé (`getBigInt64(0, false)` du terminal).
    /// L'hôte exige seulement qu'un nonce n'ait jamais servi pour cette adresse.
    static func randomNonce() throws(AuthError) -> Int64 {
        int64(bigEndian: [UInt8](try randomBytes(count: 8)))
    }

    /// 8 octets lus en entier signé grand-boutiste (complément à deux).
    static func int64(bigEndian bytes: [UInt8]) -> Int64 {
        Int64(bitPattern: bytes.prefix(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) })
    }

    /// 32 octets aléatoires (défi de la preuve de possession).
    static func randomBytes(count: Int) throws(AuthError) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw .randomUnavailable }
        return Data(bytes)
    }
}

/// Une entrée d'autorisation de l'ordre 1, prête avant le tap : ce que la puce signera (`digest`)
/// et l'entrée à compléter avec sa signature. Rien de secret : l'appel est public, le nonce n'est qu'un anti-rejeu.
struct DeclaredAuthorization {
    /// Entrée sans signature (V1).
    let entry: SorobanAuthorizationEntryXDR
    let expirationLedger: UInt32
    /// `sha256` du préimage : les 32 octets que la puce signe.
    let digest: Data

    /// `preSignedAuthEntry` sans la signature : l'appel, qui l'autorise, et l'expiration (ledger actuel + 120).
    init(
        authorizer: String,
        invocation: SorobanAuthorizedInvocationXDR,
        passphrase: String,
        expirationLedger: UInt32,
        nonce: Int64
    ) throws {
        entry = try SorobanAuth.declaredEntry(authorizer: authorizer, invocation: invocation, nonce: nonce, expirationLedger: expirationLedger)
        self.expirationLedger = expirationLedger
        digest = try SorobanAuth.payloadHash(entry, passphrase: passphrase, expirationLedger: expirationLedger)
    }

    /// `true` s'il reste moins de 20 ledgers avant l'expiration : il faut reconstruire (nouveau digest) avant le tap.
    func needsRefresh(currentLedger: UInt32) -> Bool {
        expirationLedger < currentLedger || expirationLedger - currentLedger < SorobanAuth.expirationMarginLedgers
    }

    /// L'entrée avec la signature de la puce (`ChipAuth` pour une Pocket, `AccountAuth` pour un compte).
    func signed(with signature: SCValXDR) throws -> SorobanAuthorizationEntryXDR {
        try SorobanAuth.restamped(entry, signature: signature)
    }
}
