import Foundation
import stellarsdk

/// Les appels du contrôleur XOXNO, construits et relus (phase 7, décisions de Barth du 2026-10-16 : dépôt et retrait
/// seulement, jamais d'emprunt). Signatures lues dans la spécification du contrat déployé sur testnet (code `52ed959d…`) et
/// dans `XOXNO/rs-lending-xlm` (`interfaces/controller`). **Absent de `reference/`.**
///
/// - `supply(caller, account_id, spoke_id, [(HubAssetKey, montant)]) -> u64` : `account_id = 0` crée la position (et son
///   jeton) ; sinon on ajoute à la position existante du tiroir.
/// - `withdraw(caller, account_id, [(HubAssetKey, montant)], to) -> [(HubAssetKey, montant)]` : `to = None`, l'actif revient
///   au tiroir qui signe. Un montant au-delà de la position est ramené à la position par le contrat.
///
/// Une `HubAssetKey` est la structure `{ asset: Address, hub_id: u32 }` (une table aux clés triées).
enum XoxnoCalls {
    static func hubAssetKey(asset: String, hubID: UInt32) throws -> SCValXDR {
        .map([
            SCMapEntryXDR(key: .symbol("asset"), val: try ContractArgument.address(asset)),
            SCMapEntryXDR(key: .symbol("hub_id"), val: .u32(hubID)),
        ])
    }

    private static func entries(asset: String, hubID: UInt32, units: Int128) throws -> SCValXDR {
        .vec([.vec([try hubAssetKey(asset: asset, hubID: hubID), ContractArgument.i128(units)])])
    }

    static func supply(market: IntegrationConfig.Xoxno, asset: String, from: String, accountID: UInt64, units: Int128) throws -> ContractCall {
        ContractCall(contract: market.controller, function: "supply", arguments: [
            try ContractArgument.address(from),
            .u64(accountID),
            .u32(market.spokeID),
            try entries(asset: asset, hubID: market.hubID, units: units),
        ])
    }

    static func withdraw(market: IntegrationConfig.Xoxno, asset: String, from: String, accountID: UInt64, units: Int128) throws -> ContractCall {
        ContractCall(contract: market.controller, function: "withdraw", arguments: [
            try ContractArgument.address(from),
            .u64(accountID),
            try entries(asset: asset, hubID: market.hubID, units: units),
            .void,
        ])
    }

    /// Ce que porte un appel : le tiroir, le numéro de position, et l'unique `(actif, montant)` ; `nil` si l'appel n'a pas
    /// exactement cette forme (un seul actif, celui du marché ; un retrait sans autre destinataire que le tiroir).
    struct Decoded: Equatable {
        let function: String
        let caller: String
        let accountID: UInt64
        let spokeID: UInt32?
        let units: Int128
    }

    static func decode(_ call: ContractCall, market: IntegrationConfig.Xoxno, asset: String) -> Decoded? {
        guard call.contract == market.controller, let caller = call.addressArgument(0),
              case .u64(let accountID) = call.arguments[safe: 1] ?? .void else { return nil }
        let list: SCValXDR?
        var spoke: UInt32?
        switch call.function {
        case "supply":
            guard call.arguments.count == 4, case .u32(let spokeID) = call.arguments[2] else { return nil }
            spoke = spokeID
            list = call.arguments[3]
        case "withdraw":
            guard call.arguments.count == 4, case .void = call.arguments[3] else { return nil }
            list = call.arguments[2]
        default:
            return nil
        }
        guard let rows = list?.vec, rows.count == 1, let pair = rows[0].vec, pair.count == 2,
              let key = pair[0].map, key.count == 2,
              key.first(where: { $0.key.symbol == "asset" })?.val.address.flatMap({ try? $0.toStrKey() }) == asset,
              case .u32(let hub) = key.first(where: { $0.key.symbol == "hub_id" })?.val ?? .void, hub == market.hubID,
              let units = ContractArgument.int128(pair[1]) else { return nil }
        return Decoded(function: call.function, caller: caller, accountID: accountID, spokeID: spoke, units: units)
    }

    /// Les bornes d'un appel. Dépôt : l'actif part (montant exact), la position le reçoit (pas de minimum). Retrait :
    /// `units` sort de la position et revient au tiroir ; « tout » (`units = 0`) n'a pas de montant dans l'appel : le
    /// minimum affiché est alors la valeur relue juste avant (`allValue`), la position ne pouvant que croître sans dette.
    static func terms(of call: ContractCall, market: IntegrationConfig.Xoxno, asset: String, allValue: Int128? = nil) throws -> SignedTerms {
        guard let decoded = decode(call, market: market, asset: asset), decoded.units >= 0 else {
            throw ContractArgument.ArgumentError.malformed("not an XOXNO \(call.function)")
        }
        switch decoded.function {
        case "supply":
            guard decoded.units > 0 else { throw ContractArgument.ArgumentError.malformed("XOXNO supply of nothing") }
            return SignedTerms(
                action: .deposit, contract: market.controller, authorizer: decoded.caller, assetIn: asset, amountIn: decoded.units,
                assetOut: market.controller, minimumOut: nil, route: [], deadline: nil
            )
        default:
            return SignedTerms(
                action: .withdraw, contract: market.controller, authorizer: decoded.caller, assetIn: market.controller,
                amountIn: decoded.units, assetOut: asset, minimumOut: decoded.units > 0 ? decoded.units : allValue, route: [], deadline: nil
            )
        }
    }
}

/// Ce que le contrôleur XOXNO fait signer à son déposant (vérifié par simulation sur testnet le 2026-10-16, Main
/// `CASBWZTE…D3RP` pour le dépôt, position n°26 d'un autre compte C pour le retrait) : `supply` prend le montant au
/// tiroir **vers la réserve** (un seul sous-appel, `transfer(tiroir → réserve, montant)`) ; `withdraw` ne prend rien.
struct XoxnoAuthShape: AuthShape {
    let market: IntegrationConfig.Xoxno
    let asset: String

    func signer(of call: ContractCall) -> String? {
        XoxnoCalls.decode(call, market: market, asset: asset)?.caller
    }

    func pulls(of call: ContractCall, from: String) throws -> [ContractCall] {
        guard let decoded = XoxnoCalls.decode(call, market: market, asset: asset), decoded.caller == from,
              decoded.function == "supply" else { return [] }
        return [try TokenShape.transfer(token: asset, from: from, to: market.pool, units: decoded.units)]
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
