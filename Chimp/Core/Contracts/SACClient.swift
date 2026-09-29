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

    /// `i128` → entier décimal exact (`hi · 2⁶⁴ + lo`), sans passer par un `Double`.
    static func decimal(_ parts: Int128PartsXDR) -> Decimal {
        Decimal(parts.hi) * Decimal(string: "18446744073709551616")! + Decimal(parts.lo)
    }

    /// Unités on-chain → montant de l'actif (division exacte par 10⁷).
    static func amount(fromUnits units: Decimal) -> Decimal {
        units / pow(Decimal(10), decimals)
    }
}
