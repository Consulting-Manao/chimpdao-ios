import Foundation
import stellarsdk

/// Les appels du vault xSolvBTC de Solv, construits et relus (décision de Barth du 2026-11-05). **Absent de `reference/`.**
/// Interfaces lues dans les wasm qui tournent sur le mainnet le 2026-11-05 : vault `CATBHFGH…` (`7e2328d8…`), jetons
/// SolvBTC `CBIJBDNZ…` et xSolvBTC `CAUP7NFA…` (`f1107839…`, source `solv-finance/SolvBTC-Stellar-Contract`, vérifiée par
/// stellar.expert), oracle de NAV `CD2KTWZ3…`.
///
/// - `deposit(from, currency, amount: i128) -> i128` : le vault **tire** `amount` de SolvBTC du tiroir avec
///   `transfer_from` (il faut donc d'abord `approve(from, vault, amount, live_until_ledger)` sur SolvBTC), puis frappe au
///   tiroir `amount × 10^nav_decimals / nav` xSolvBTC (mêmes décimales, 8). Les deux appels partent ensemble par le router
///   de ChimpDAO (`batch`) : une seule signature de la carte.
/// - Retrait : `withdraw_request`, puis `withdraw` avec une **signature du serveur de Solv** ; pas dans l'app. On sort par
///   un swap xSolvBTC → SolvBTC.
enum SolvCalls {
    /// `approve(owner, spender, amount, live_until_ledger)` d'un jeton SEP-41.
    static func approve(token: String, owner: String, spender: String, units: Int128, liveUntilLedger: UInt32) throws -> ContractCall {
        guard units > 0 else { throw YieldError.amountTooSmall }
        return ContractCall(contract: token, function: "approve", arguments: [
            try ContractArgument.address(owner), try ContractArgument.address(spender), ContractArgument.i128(units), .u32(liveUntilLedger),
        ])
    }

    static func deposit(vault: String, from: String, currency: String, units: Int128) throws -> ContractCall {
        guard units > 0 else { throw YieldError.amountTooSmall }
        return ContractCall(contract: vault, function: "deposit", arguments: [
            try ContractArgument.address(from), try ContractArgument.address(currency), ContractArgument.i128(units),
        ])
    }

    /// Les deux jambes d'un dépôt, dans l'ordre : l'autorisation exacte de tirer ce montant, puis le dépôt lui-même.
    static func depositLegs(vault: String, from: String, currency: String, units: Int128, liveUntilLedger: UInt32) throws -> [ContractCall] {
        [
            try approve(token: currency, owner: from, spender: vault, units: units, liveUntilLedger: liveUntilLedger),
            try deposit(vault: vault, from: from, currency: currency, units: units),
        ]
    }

    /// Ce que porte un dépôt : le tiroir, l'actif et le montant ; `nil` si l'appel n'a pas exactement cette forme.
    struct Decoded: Equatable {
        let caller: String
        let currency: String
        let units: Int128
    }

    static func decodeDeposit(_ call: ContractCall, vault: String) -> Decoded? {
        guard call.contract == vault, call.function == "deposit", call.arguments.count == 3,
              let caller = call.addressArgument(0), let currency = call.addressArgument(1),
              let units = ContractArgument.int128(call.arguments[2]), units > 0 else { return nil }
        return Decoded(caller: caller, currency: currency, units: units)
    }

    /// Les bornes d'un dépôt, relues dans **les deux** jambes : l'`approve` doit autoriser exactement le vault, pour exactement
    /// le montant déposé, depuis le même tiroir ; sinon rien n'est signé. Dépôt : le SolvBTC part, des xSolvBTC arrivent
    /// (pas de minimum : la NAV du vault fixe la quantité).
    static func terms(of legs: [ContractCall], vault: String, currency: String, shares: String) throws -> SignedTerms {
        guard legs.count == 2, let deposit = decodeDeposit(legs[1], vault: vault), deposit.currency == currency else {
            throw ContractArgument.ArgumentError.malformed("not a Solv deposit")
        }
        let approve = legs[0]
        guard approve.contract == currency, approve.function == "approve", approve.arguments.count == 4,
              approve.addressArgument(0) == deposit.caller, approve.addressArgument(1) == vault,
              ContractArgument.int128(approve.arguments[2]) == deposit.units else {
            throw ContractArgument.ArgumentError.malformed("the approval doesn't match the Solv deposit")
        }
        return SignedTerms(
            action: .deposit, contract: vault, authorizer: deposit.caller, assetIn: currency, amountIn: deposit.units,
            assetOut: shares, minimumOut: nil, route: [], deadline: nil
        )
    }

    /// `calculate_mint_amount` du vault, pour des décimales égales (SolvBTC et xSolvBTC en ont 8) :
    /// `amount × 10^nav_decimals / nav`, arrondi vers zéro. Affichage seulement (« about »).
    static func mintedShares(units: Int128, nav: Int128, navDecimals: Int) -> Int128? {
        guard units > 0, nav > 0, navDecimals >= 0, navDecimals <= 18 else { return nil }
        var scale: Int128 = 1
        for _ in 0..<navDecimals { scale *= 10 }
        let (product, overflow) = units.multipliedReportingOverflow(by: scale)
        guard !overflow else { return nil }
        return product / nav
    }

    /// La valeur de parts, en SolvBTC : `shares × nav / 10^nav_decimals`.
    static func value(shares: Int128, nav: Int128, navDecimals: Int) -> Int128? {
        guard shares >= 0, nav > 0, navDecimals >= 0, navDecimals <= 18 else { return nil }
        var scale: Int128 = 1
        for _ in 0..<navDecimals { scale *= 10 }
        let (product, overflow) = shares.multipliedReportingOverflow(by: nav)
        guard !overflow else { return nil }
        return product / scale
    }

    /// Les codes d'erreur que l'écran sait dire. Solv n'en publie pas la table : seuls ceux du SAC et du jeton sont nommés.
    static func yieldError(for error: Error) -> YieldError? {
        let message: String
        switch error {
        case StellarError.simulationFailed(let text), StellarError.submitFailed(let text): message = text
        case StellarError.transactionFailed(_, let detail): message = detail
        default: return nil
        }
        return message.contains("insufficient balance") || message.contains("InsufficientBalance") ? .insufficientBalance : nil
    }
}

/// Ce qu'un tiroir signe chez Solv : le `deposit` lui-même, rien dessous (le vault tire le SolvBTC par l'`approve`, avec sa
/// propre autorisation de contrat appelant). L'`approve` est un appel de jeton (`TokenShape`).
struct SolvAuthShape: AuthShape {
    let vault: String

    func signer(of call: ContractCall) -> String? {
        SolvCalls.decodeDeposit(call, vault: vault)?.caller
    }

    func pulls(of call: ContractCall, from: String) throws -> [ContractCall] { [] }
}
