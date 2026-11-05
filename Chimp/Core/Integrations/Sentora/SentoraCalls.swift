import Foundation
import stellarsdk

/// Les appels d'un vault Sentora, construits et relus (décision de Barth du 2026-11-05). **Absent de `reference/`.**
/// Interface lue dans le wasm qui tourne sur le mainnet (`ca6b85a1…`, vault USDC `CAHEWHOP…`, le 2026-11-05) ; code source
/// `Into-The-Block-Corp/StellarVaults` (commit `c29a8bf9`, vérifié par stellar.expert contre ce wasm).
///
/// - `deposit(from, amount: u128, referral_id: Option<String>) -> u64` : prend `amount` au tiroir (`transfer` vers le
///   vault) et l'ajoute à **son** dépôt. `referral_id = None`.
/// - `withdraw(from, amount: u128) -> Result<(), Error>` : rend `amount` du dépôt au tiroir (jamais plus que le dépôt).
/// - Position : aucune fonction de lecture ; la donnée persistante `Deposit(Address)` porte `DepositRecord { amount, owner }`.
///
/// Les récompenses ne passent pas par le vault : Sentora les publie en fin de période dans un escrow, et chacun les
/// réclame avec une preuve fournie par son serveur. Retirer avant la fin fait perdre celles de la période.
enum SentoraCalls {
    static func deposit(vault: String, from: String, units: Int128) throws -> ContractCall {
        guard units > 0, let amount = UInt128(exactly: units) else { throw YieldError.amountTooSmall }
        return ContractCall(contract: vault, function: "deposit", arguments: [
            try ContractArgument.address(from), ContractArgument.u128(amount), .void,
        ])
    }

    static func withdraw(vault: String, from: String, units: Int128) throws -> ContractCall {
        guard units > 0, let amount = UInt128(exactly: units) else { throw YieldError.amountTooSmall }
        return ContractCall(contract: vault, function: "withdraw", arguments: [
            try ContractArgument.address(from), ContractArgument.u128(amount),
        ])
    }

    /// Ce que porte un appel : la fonction, le tiroir et le montant ; `nil` si l'appel n'a pas exactement cette forme (un
    /// dépôt sans parrainage, un montant positif).
    struct Decoded: Equatable {
        let function: String
        let caller: String
        let units: Int128
    }

    static func decode(_ call: ContractCall, vault: String) -> Decoded? {
        guard call.contract == vault, let caller = call.addressArgument(0),
              call.arguments.count >= 2, let amount = ContractArgument.uint128(call.arguments[1]), amount > 0,
              let units = Int128(exactly: amount) else { return nil }
        switch call.function {
        case "deposit":
            guard call.arguments.count == 3, case .void = call.arguments[2] else { return nil }
        case "withdraw":
            guard call.arguments.count == 2 else { return nil }
        default:
            return nil
        }
        return Decoded(function: call.function, caller: caller, units: units)
    }

    /// Les bornes d'un appel. Dépôt : l'actif part (montant exact), le vault le garde (pas de minimum). Retrait : le montant
    /// exact revient au tiroir (le vault rend exactement ce qui est demandé, ou refuse).
    static func terms(of call: ContractCall, vault: String, asset: String) throws -> SignedTerms {
        guard let decoded = decode(call, vault: vault) else { throw ContractArgument.ArgumentError.malformed("not a Sentora \(call.function)") }
        switch decoded.function {
        case "deposit":
            return SignedTerms(
                action: .deposit, contract: vault, authorizer: decoded.caller, assetIn: asset, amountIn: decoded.units,
                assetOut: vault, minimumOut: nil, route: [], deadline: nil
            )
        default:
            return SignedTerms(
                action: .withdraw, contract: vault, authorizer: decoded.caller, assetIn: vault, amountIn: decoded.units,
                assetOut: asset, minimumOut: decoded.units, route: [], deadline: nil
            )
        }
    }

    /// Clé (base64) de la donnée persistante du dépôt d'un tiroir : `DepositStorageKey::Deposit(holder)`.
    static func depositKey(vault: String, holder: String) throws -> String {
        let key = LedgerKeyXDR.contractData(LedgerKeyContractDataXDR(
            contract: try SCAddressXDR(contractId: vault), key: .vec([.symbol("Deposit"), try ContractArgument.address(holder)]),
            durability: .persistent
        ))
        guard let encoded = key.xdrEncoded else { throw StellarError.invalidResponse("could not encode ledger key") }
        return encoded
    }

    /// Clé (base64) de l'instance du vault : son stockage porte `Paused` et `TotalPrincipal`.
    static func instanceKey(vault: String) throws -> String {
        let key = LedgerKeyXDR.contractData(LedgerKeyContractDataXDR(
            contract: try SCAddressXDR(contractId: vault), key: .ledgerKeyContractInstance, durability: .persistent
        ))
        guard let encoded = key.xdrEncoded else { throw StellarError.invalidResponse("could not encode ledger key") }
        return encoded
    }

    /// L'état du vault, lu dans le stockage de son instance (`CoreStorageKeys::Paused`, `DepositStorageKey::TotalPrincipal`).
    struct VaultState: Equatable {
        let paused: Bool
        let totalPrincipal: Int128
    }

    static func state(instance value: SCValXDR?) throws -> VaultState {
        guard let storage = value?.contractInstance?.storage else { throw StellarError.invalidResponse("Sentora vault has no instance storage") }
        func entry(_ name: String) -> SCValXDR? {
            storage.first { entry in
                if case .vec(let items?) = entry.key, items.count == 1, case .symbol(name) = items[0] { return true }
                return false
            }?.val
        }
        let paused: Bool = if case .bool(let flag)? = entry("Paused") { flag } else { false }
        let total = entry("TotalPrincipal").flatMap(ContractArgument.uint128).flatMap { Int128(exactly: $0) } ?? 0
        return VaultState(paused: paused, totalPrincipal: total)
    }

    /// `DepositRecord { amount: u128, owner: Address }` → le montant déposé, seulement si l'entrée est bien celle de ce
    /// tiroir ; `nil` pour une forme inattendue.
    static func principal(_ value: SCValXDR, holder: String) -> Int128? {
        guard case .map(let entries?) = value,
              let amount = entries.first(where: { $0.key.symbol == "amount" }).flatMap({ ContractArgument.uint128($0.val) }),
              let owner = entries.first(where: { $0.key.symbol == "owner" })?.val.address.flatMap({ try? $0.toStrKey() }),
              owner == holder else { return nil }
        return Int128(exactly: amount)
    }

    /// Les codes d'erreur du vault (`ContractErrors`, source `c29a8bf9`) qu'un écran sait dire : 100 `VaultPaused`,
    /// 101 `NotEnoughDeposit`, 104 `ZeroAmountDeposit` ; 10 vient du SAC (solde insuffisant).
    static func yieldError(for error: Error) -> YieldError? {
        let message: String
        switch error {
        case StellarError.simulationFailed(let text), StellarError.submitFailed(let text): message = text
        case StellarError.transactionFailed(_, let detail): message = detail
        default: return nil
        }
        let codes: [(Int, YieldError)] = [(100, .vaultUnavailable), (101, .notEnoughShares), (104, .amountTooSmall), (10, .insufficientBalance)]
        return codes.first { message.contains("Error(Contract, #\($0.0))") }?.1
    }
}

/// Ce qu'un tiroir signe chez Sentora : un dépôt prend le montant (`transfer` du tiroir vers le vault) ; un retrait ne
/// prend rien.
struct SentoraAuthShape: AuthShape {
    let vault: String
    let asset: String

    func signer(of call: ContractCall) -> String? {
        SentoraCalls.decode(call, vault: vault)?.caller
    }

    func pulls(of call: ContractCall, from: String) throws -> [ContractCall] {
        guard let decoded = SentoraCalls.decode(call, vault: vault), decoded.caller == from, decoded.function == "deposit" else { return [] }
        return [try TokenShape.transfer(token: asset, from: from, to: vault, units: decoded.units)]
    }
}
