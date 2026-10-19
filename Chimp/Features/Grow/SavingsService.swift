import Foundation
import stellarsdk

/// Les CETES d'un tiroir (F9, F10, tuile de B2/B3) : une ligne par tiroir, jamais fusionnées (décision de Barth du
/// 2026-10-15).
struct SavingsHolding: Equatable, Identifiable {
    var id: String { drawerID }
    let drawerID: String
    let drawerAddress: String
    let amount: Decimal
    /// Gelés par l'émetteur (`authorized == false`, lu sur la chaîne) : bandeau rouge, aucun swap.
    let frozen: Bool
    /// Le prix auquel on les a obtenus, noté sur ce téléphone ; `nil` → la valeur seule.
    let basis: SavingsBasis?

    /// Évolution du prix depuis l'obtention (« Price +0.62% »), si la base et le prix du moment sont connus.
    func priceChange(_ price: StablebondPrice?) -> Decimal? {
        guard let basis, let price else { return nil }
        return basis.priceChange(now: price.usd)
    }
}

/// Tout ce que montrent F9 et F10 pour un stablebond.
struct SavingsContext: Equatable {
    let network: StellarNetwork
    let asset: SendAsset
    let drawers: [SendDrawer]
    /// Les tiroirs qui détiennent des CETES, ou dont les CETES sont gelés.
    let holdings: [SavingsHolding]
    /// Prix indicatif d'Etherfuse ; indisponible → la quantité seule.
    let price: StablebondPriceResult
    /// Pouvoirs de l'émetteur, lus sur la chaîne (`nil` si la lecture a échoué).
    let issuerPowers: IssuerPowers?

    func holding(drawerAddress: String) -> SavingsHolding? {
        holdings.first { $0.drawerAddress == drawerAddress }
    }

    func drawer(address: String) -> SendDrawer? {
        drawers.first { $0.address == address }
    }
}

protocol SavingsService: AnyObject {
    func fetchSavings() async throws -> SavingsContext
}

/// Le vrai service, sur le réseau de l'app (testnet) : soldes des tiroirs (comme Envoyer), gel de chaque tiroir et pouvoirs
/// de l'émetteur (sur la chaîne), prix indicatif (Etherfuse), base tirée de l'historique du téléphone.
final class ChainSavingsService: SavingsService {
    private let session: AppSession
    private let config: ChimpNetworkConfig
    private let drawers: ChainSendService
    private let pricing: StablebondPricing?

    init(session: AppSession, pricing: StablebondPricing? = nil) {
        self.session = session
        config = session.config
        drawers = ChainSendService(session: session)
        self.pricing = pricing ?? EtherfusePriceClient.shared(for: config)
    }

    func fetchSavings() async throws -> SavingsContext {
        guard let etherfuse = config.integrations?.etherfuse, let bond = etherfuse.stablebonds.first,
              let asset = SendAsset(code: bond.code) else { throw SwapServiceError.unknownDrawer("stablebond") }
        let context = try await drawers.fetchContext()
        let client = SorobanClient(config: config)
        let control = StablebondControl(client: client)
        let source = try Account(accountId: config.feePayer, sequenceNumber: 0)
        let records = session.wallet.account.map { session.activity.activity(of: $0.address).records } ?? []

        // Réseau en parallèle : le prix, les pouvoirs de l'émetteur, le gel de chaque tiroir.
        async let price = pricing?.price(of: bond) ?? .unavailable("no price source")
        async let powers = try? control.issuerPowers(etherfuse.issuer)
        let frozen: Set<String> = await withTaskGroup(of: String?.self) { group in
            for drawer in context.drawers {
                group.addTask {
                    // Une lecture ratée n'invente pas un gel : seul `authorized == false` en est un.
                    (try? await control.isFrozen(token: bond.contract, holder: drawer.address, source: source)) == true ? drawer.id : nil
                }
            }
            var result: Set<String> = []
            for await id in group { if let id { result.insert(id) } }
            return result
        }
        let holdings = context.drawers.compactMap { drawer -> SavingsHolding? in
            let amount = drawer.balance(of: asset)
            guard amount > 0 || frozen.contains(drawer.id) else { return nil }
            return SavingsHolding(
                drawerID: drawer.id, drawerAddress: drawer.address, amount: amount, frozen: frozen.contains(drawer.id),
                basis: SavingsBasis.from(records: records, drawer: drawer.address, code: asset.code, balance: amount)
            )
        }
        return SavingsContext(
            network: context.network, asset: asset, drawers: context.drawers, holdings: holdings,
            price: await price, issuerPowers: await powers
        )
    }
}

/// Économies factices (catalogue, simulateur, tests) : les tiroirs d'Envoyer ; 1 820,40 CETES dans le Main, obtenus à
/// 0,05435 $ (prix du moment 0,05469 $ : +0,62 %, maquette F9).
final class MockSavingsService: SavingsService {
    enum Scenario: String, CaseIterable, Identifiable {
        /// Des CETES dans le Main, prix disponible, base connue (F9, F10).
        case normal
        /// Prix d'Etherfuse indisponible (F9a, F10a) : la quantité seule.
        case priceUnavailable
        /// Aucun CETES (F9b, F10b).
        case none
        /// Des CETES dans le Main et dans Banana (une ligne par tiroir).
        case twoDrawers
        /// Les CETES du Main sont gelés par Etherfuse.
        case frozen
        /// Base inconnue (obtenus sur un autre téléphone) : la valeur seule, sans évolution.
        case unknownBasis

        var id: String { rawValue }
    }

    let send: MockSendService
    var scenario: Scenario
    var delay: Duration

    static let price = StablebondPrice(code: "CETES", usd: Decimal(string: "0.05469")!, currency: "MXN", fiat: 1, asOf: .now.addingTimeInterval(-120))
    static let basisPrice = Decimal(string: "0.05435")!

    init(scenario: Scenario = .normal, delay: Duration = .milliseconds(500)) {
        send = MockSendService(dataScenario: .standard, delay: delay, nfcDelay: delay)
        self.scenario = scenario
        self.delay = delay
    }

    func fetchSavings() async throws -> SavingsContext {
        try await Task.sleep(for: delay)
        let context = try await send.fetchContext()
        var holdings: [SavingsHolding] = []
        let basis = scenario == .unknownBasis ? nil : SavingsBasis(unitPriceUSD: Self.basisPrice, since: MockVaultService.depositDate)
        if scenario != .none, let main = context.drawers.first(where: { $0.kind == .main }) {
            holdings.append(SavingsHolding(
                drawerID: main.id, drawerAddress: main.address, amount: Decimal(string: "1820.4")!, frozen: scenario == .frozen, basis: basis
            ))
        }
        if scenario == .twoDrawers, let card = context.drawers.first(where: { $0.kind != .main }) {
            holdings.append(SavingsHolding(drawerID: card.id, drawerAddress: card.address, amount: 500, frozen: false, basis: nil))
        }
        return SavingsContext(
            network: context.network, asset: .cetes, drawers: context.drawers, holdings: holdings,
            price: scenario == .priceUnavailable ? .unavailable("mock") : .price(Self.price),
            issuerPowers: IssuerPowers(canFreeze: true, canClawBack: true)
        )
    }
}
