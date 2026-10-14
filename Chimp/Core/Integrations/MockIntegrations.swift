import CryptoKit
import Foundation
import stellarsdk

/// Adaptateurs factices pour le simulateur, les aperçus et les tests : l'UI des intégrations tourne sans réseau ni carte
/// (CLAUDE.md : tout service de `Core/` a une implémentation Mock). Leurs contrats sont des adresses inventées, dérivées
/// d'un libellé : aucune ne correspond à un vrai protocole, rien de ce qu'ils construisent n'est jamais envoyé.
enum MockIntegrationAddress {
    /// Une adresse C valide, dérivée de `label` (`sha256`), qui n'existe sur aucun réseau.
    static func contract(_ label: String) -> String {
        (try? Data(SHA256.hash(data: Data("chimpdao.mock.\(label)".utf8))).encodeContractId()) ?? ""
    }
}

/// Un protocole d'échange factice : prix fixe, mêmes appels et même forme d'autorisation que Soroswap.
struct MockSwapAdapter: SwapAdapter {
    let id: String
    let name: String
    /// Prix fixe : `amountOut = amountIn × numerator / denominator`.
    let numerator: Int128
    let denominator: Int128
    /// Panne à rendre au lieu d'un devis (protocole indisponible).
    var failure: Error?
    /// Aucune route (route introuvable).
    var noRoute = false

    var router: String { MockIntegrationAddress.contract("\(id).router") }
    var pair: String { MockIntegrationAddress.contract("\(id).pair") }

    func quote(_ request: SwapRequest) async throws -> SwapQuote? {
        if let failure { throw failure }
        guard !noRoute, request.amountIn > 0, denominator > 0 else { return nil }
        return SwapQuote(
            protocolID: id, request: request, route: [request.assetIn.contract, request.assetOut.contract],
            amountOut: request.amountIn * numerator / denominator, priceImpactBasisPoints: 30, firstHopVenue: pair
        )
    }

    func swapCall(for quote: SwapQuote, minimumOut: Int128, authorizer: String, now: UInt64) throws -> ContractCall {
        try SoroswapCalls.swap(
            router: router, amountIn: quote.request.amountIn, minimumOut: minimumOut, path: quote.route,
            to: authorizer, deadline: now + SoroswapCalls.deadlineSeconds
        )
    }

    func authShape(for quote: SwapQuote) -> any AuthShape {
        SoroswapAuthShape(router: router, pair: quote.firstHopVenue)
    }

    func terms(of call: ContractCall) throws -> SignedTerms {
        try SoroswapCalls.terms(of: call, router: router)
    }

    var deadlineSeconds: UInt64? { SoroswapCalls.deadlineSeconds }

    func swapError(for error: Error) -> SwapError? { SoroswapAdapter.swapError(for: error) }

    func receivedUnits(_ returnValue: SCValXDR) -> Int128? { (try? SoroswapAdapter.amounts(returnValue))?.last }
}

/// Un protocole de rendement factice : un seul vault, positions tenues en mémoire, mêmes appels et même forme
/// d'autorisation que DeFindex.
struct MockYieldAdapter: YieldAdapter {
    let asset: IntegrationAsset
    /// Positions « lues sur la chaîne ».
    var positions: [YieldPosition] = []
    var failure: Error?

    let id = "mock-vaults"
    let name = "Mock vaults"
    let category = "Vaults"
    let openActions = [YieldAction(id: "deposit", label: "Deposit", maxFrom: .balance)]
    let manageActions = [
        YieldAction(id: "deposit", label: "Deposit", maxFrom: .balance),
        YieldAction(id: "withdraw", label: "Withdraw", maxFrom: .position),
    ]

    var vault: String { MockIntegrationAddress.contract("\(id).\(asset.code).vault") }

    func venues() -> [YieldVenue] {
        [YieldVenue(id: vault, name: "\(asset.code) vault", asset: asset, underlyingProtocols: ["Blend"])]
    }

    func discover(holder: String) async throws -> [YieldPosition] {
        if let failure { throw failure }
        return positions.filter { $0.holder == holder }
    }

    func depositCall(venue: YieldVenue, amount: Int128, authorizer: String) async throws -> ContractCall {
        try DeFindexCalls.deposit(vault: venue.id, from: authorizer, units: amount)
    }

    /// Parts au prorata de la valeur (`dfAmountFor` sans la marge de poussière), minimum = valeur − 0,5 %.
    func withdrawCall(position: YieldPosition, amount: Int128, all: Bool) async throws -> ContractCall {
        let shares = all || position.value <= 0 ? position.shares : position.shares * amount / position.value
        let expected = all ? position.value : amount
        return try DeFindexCalls.withdraw(
            vault: position.venueID, from: position.holder, shares: shares,
            minimumOut: Slippage.minimum(of: expected, basisPoints: Slippage.defaultBasisPoints)
        )
    }

    func authShape() -> any AuthShape {
        DeFindexAuthShape(underlying: [vault: asset.contract])
    }

    func terms(of call: ContractCall) throws -> SignedTerms {
        try DeFindexCalls.terms(of: call, underlying: asset.contract)
    }
}
