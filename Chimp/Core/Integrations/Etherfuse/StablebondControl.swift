import Foundation
import stellarsdk

/// Ce que l'émetteur d'un stablebond peut faire, lu sur la chaîne (drapeaux du compte émetteur, protocole Stellar
/// `AccountFlags`) : `AUTH_REVOCABLE` (2) = il peut geler les jetons d'un détenteur ; `AUTH_CLAWBACK_ENABLED` (8) = il peut
/// les reprendre. Le CETES d'Etherfuse sur testnet a les deux (Horizon, 2026-10-15).
struct IssuerPowers: Equatable, Sendable {
    let canFreeze: Bool
    let canClawBack: Bool

    static let revocableFlag: UInt32 = 0x2
    static let clawbackEnabledFlag: UInt32 = 0x8

    init(canFreeze: Bool, canClawBack: Bool) {
        self.canFreeze = canFreeze
        self.canClawBack = canClawBack
    }

    init(flags: UInt32) {
        canFreeze = flags & Self.revocableFlag != 0
        canClawBack = flags & Self.clawbackEnabledFlag != 0
    }
}

/// Gel et clawback d'un stablebond (tranche 2, D3), lus sur la chaîne, jamais supposés. Absent du terminal : écrit
/// d'après le Stellar Asset Contract (`authorized(id) -> bool`, CAP-46-6) et les drapeaux de compte du protocole.
///
/// Un tiroir dont les jetons sont gelés (`authorized == false`) ne peut ni en envoyer ni en recevoir : l'app le dit au lieu
/// de proposer un swap voué à l'échec.
struct StablebondControl {
    let client: SorobanClient

    /// Drapeaux du compte émetteur (`getLedgerEntries`).
    func issuerPowers(_ issuer: String) async throws -> IssuerPowers {
        let key = LedgerKeyXDR.account(LedgerKeyAccountXDR(accountID: try KeyPair(accountId: issuer).publicKey))
        guard let encoded = key.xdrEncoded else { throw StellarError.invalidResponse("could not encode ledger key") }
        guard let entry = try await client.ledgerEntries([encoded]).first else { throw StellarError.invalidResponse("issuer account not found") }
        guard case .account(let account)? = entry.valueXdr else { throw StellarError.invalidResponse("issuer entry is not an account") }
        return IssuerPowers(flags: account.flags)
    }

    /// Les jetons de ce détenteur sont-ils gelés ? `authorized(holder)` du SAC : `false` = gelés.
    func isFrozen(token: String, holder: String, source: Account) async throws -> Bool {
        !(try await SACClient(client: client).authorized(token: token, holder: holder, source: source))
    }
}

extension SACClient {
    /// `authorized(id) -> bool` du SAC : le détenteur peut-il envoyer et recevoir cet actif ? Une réponse qui n'est pas un
    /// booléen remonte en erreur (jamais « autorisé » par défaut).
    func authorized(token: String, holder: String, source: Account) async throws -> Bool {
        let address = holder.hasPrefix("C") ? try SCAddressXDR(contractId: holder) : try SCAddressXDR(accountId: holder)
        let value = try await client.read(source: source, contract: token, function: "authorized", arguments: [.address(address)])
        guard case .bool(let authorized)? = value else { throw StellarError.invalidResponse("authorized returned \(String(describing: value))") }
        return authorized
    }
}
