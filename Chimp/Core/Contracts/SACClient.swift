import CryptoKit
import Foundation
import stellarsdk

/// Stellar Asset Contract : la version « contrat » d'un actif (XLM, USDC). Portage de `sacForAsset`
/// (`reference/terminal/src/chain/sac.ts`) et de `sacBalance` (`chain/stellar.ts`).
struct SACClient {
    let client: SorobanClient

    /// Tous les SAC ont 7 décimales on-chain (`SAC_DECIMALS`).
    static let decimals = 7

    /// Adresse du SAC d'un actif : `Asset(code, émetteur).contractId(passphrase)` (XLM : `Asset.native()`).
    static func contractID(for asset: Asset, network: Network) throws -> String {
        let preimage = HashIDPreimageXDR.contractID(HashIDPreimageContractIDXDR(
            networkID: HashXDR(network.networkId),
            contractIDPreimage: .fromAsset(try asset.toXDR())
        ))
        return try Data(SHA256.hash(data: Data(try XDREncoder.encode(preimage)))).encodeContractId()
    }

    /// Actifs Stellar de l'app, XLM puis USDC (`assetsOf(network, "stellar")` du terminal), avec l'adresse de leur SAC ;
    /// puis les stablebonds d'Etherfuse du réseau (CETES sur testnet, tranche 2), **par l'adresse exacte de `Config/`**
    /// (elle-même vérifiée contre `code:émetteur`, `IntegrationConfig.problems`). C'est la liste blanche de l'app : un
    /// jeton n'est reconnu (soldes, Activity, swap) que par l'adresse de son contrat, jamais par son code.
    static func stellarAssets(config: ChimpNetworkConfig) throws -> [(code: String, contract: String)] {
        let network = Network.custom(passphrase: config.passphrase)
        let usdc = Asset(type: AssetType.ASSET_TYPE_CREDIT_ALPHANUM4, code: "USDC", issuer: try KeyPair(accountId: config.usdcIssuer))!
        let stablebonds = config.etherfuse?.stablebonds.map { ($0.code, $0.contract) } ?? []
        let usdy = config.ondo.map { [($0.usdy.code, $0.usdy.contract)] } ?? []
        return [
            ("XLM", try contractID(for: Asset(type: AssetType.ASSET_TYPE_NATIVE)!, network: network)),
            ("USDC", try contractID(for: usdc, network: network)),
        ] + stablebonds + usdy
    }

    /// `balance(holder)` en unités on-chain (entier, 7 décimales). `nil` si la simulation n'a rendu aucune valeur :
    /// solde inconnu, sur lequel on ne dépense jamais. Les pannes réseau remontent.
    func balance(token: String, holder: String, source: Account) async throws -> Decimal? {
        let holderAddress = holder.hasPrefix("C") ? try SCAddressXDR(contractId: holder) : try SCAddressXDR(accountId: holder)
        guard let value = try await client.read(source: source, contract: token, function: "balance", arguments: [.address(holderAddress)]) else {
            return nil
        }
        guard let parts = value.i128 else { throw StellarError.invalidResponse("balance returned \(value)") }
        return Self.decimal(parts)
    }

    /// `transfer(from, to, amount)` d'un SAC (`new Contract(token).call("transfer", from, to, i128)` du terminal).
    /// `amount` en unités on-chain (stroops pour XLM), entier positif.
    static func transferOperation(token: String, from: String, to: String, units: UInt64) throws -> InvokeHostFunctionOperation {
        try InvokeHostFunctionOperation.forInvokingContract(
            contractId: token,
            functionName: "transfer",
            functionArguments: try transferArguments(from: from, to: to, units: units)
        )
    }

    /// Arguments de `transfer` (`transferArgs` de `payFromChipAccount`) : `Address.fromString(…).toScVal()` pour `from`
    /// et `to` (G, M ou C), puis le montant en `i128`.
    static func transferArguments(from: String, to: String, units: UInt64) throws -> [SCValXDR] {
        [.address(try address(from)), .address(try address(to)), .i128(Int128PartsXDR(hi: 0, lo: units))]
    }

    /// `Address.fromString` : contrat (C), compte (G) ou compte multiplexé (M, memo ID plié dedans, que le SDK
    /// encode en `SC_ADDRESS_TYPE_MUXED_ACCOUNT`).
    static func address(_ strkey: String) throws -> SCAddressXDR {
        strkey.hasPrefix("C") ? try SCAddressXDR(contractId: strkey) : try SCAddressXDR(accountId: strkey)
    }

    // MARK: Paiement depuis une Pocket (ordre 1)

    /// Avant le tap : l'entrée `transfer` que la Pocket autorise (`payFromChipAccount` → `purseSignedCallOn`).
    /// Le SAC est le contrat appelé, la Pocket l'autorisateur (`from`), sans sous-appel : « a SAC transfer is the one
    /// node it authorizes ». Expiration = ledger actuel + 120, nonce aléatoire. Le `digest` est ce que la puce signera.
    static func declareTransfer(
        token: String,
        pocket: String,
        to: String,
        units: UInt64,
        passphrase: String,
        currentLedger: UInt32,
        nonce: Int64
    ) throws -> DeclaredAuthorization {
        try DeclaredAuthorization(
            authorizer: pocket,
            invocation: try SorobanAuth.contractInvocation(
                contract: token, function: "transfer", arguments: try transferArguments(from: pocket, to: to, units: units)
            ),
            passphrase: passphrase,
            expirationLedger: currentLedger + SorobanAuth.expirationLedgers,
            nonce: nonce
        )
    }

    // MARK: Montants

    enum AmountError: Error, Equatable, LocalizedError {
        /// Montant nul ou négatif (`amount must be positive`).
        case notPositive
        /// Plus de décimales que l'actif n'en permet : on refuse au lieu de tronquer, pour que le montant signé
        /// soit exactement celui affiché (règle 8).
        case tooManyDecimals(allowed: Int)
        /// Au-delà de ce qu'un entier de 64 bits peut porter (~1,8 milliard d'unités de l'actif).
        case tooLarge

        var errorDescription: String? {
            switch self {
            case .notPositive: "The amount must be positive."
            case .tooManyDecimals(let allowed): "The amount has more than \(allowed) decimals."
            case .tooLarge: "The amount is too large."
            }
        }
    }

    /// Montant de l'actif → unités on-chain (`toUnits(amount, keypadDecimals, chainDecimals)` de `lib/amount.ts`).
    /// Calcul exact en base 10 (`Decimal`), jamais par un `Double`, indépendant de la langue du téléphone.
    /// Écart volontaire : `toUnits` tronque les décimales en trop ; ici elles sont refusées.
    static func units(of amount: Decimal, keypadDecimals: Int) throws(AmountError) -> UInt64 {
        guard amount > 0 else { throw .notPositive }
        let keypadScaled = amount * pow(Decimal(10), keypadDecimals)
        guard isWhole(keypadScaled) else { throw .tooManyDecimals(allowed: keypadDecimals) }
        let scaled = amount * pow(Decimal(10), decimals)
        guard isWhole(scaled), scaled <= Decimal(UInt64.max) else { throw .tooLarge }
        // `Decimal` → texte (toujours avec « . » et sans séparateur) → entier : aucune perte possible.
        guard let units = UInt64(NSDecimalNumber(decimal: scaled).stringValue) else { throw .tooLarge }
        return units
    }

    private static func isWhole(_ value: Decimal) -> Bool {
        var input = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, 0, .down)
        return rounded == value
    }

    /// `i128` → entier décimal exact (`hi · 2⁶⁴ + lo`), sans passer par un `Double`.
    static func decimal(_ parts: Int128PartsXDR) -> Decimal {
        Decimal(parts.hi) * Decimal(string: "18446744073709551616")! + Decimal(parts.lo)
    }

    /// Unités on-chain → montant de l'actif (division exacte par 10⁷).
    static func amount(fromUnits units: Decimal) -> Decimal {
        units / pow(Decimal(10), decimals)
    }
}
