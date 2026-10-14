import Foundation
import stellarsdk
import Testing
@testable import ChimpDAO

/// Tranche 2, phase 1, étape 5 : protocoles d'adaptateur, registre (meilleure route, positions) et adaptateurs factices.
struct IntegrationRegistryTests {
    private let xlm = IntegrationAsset(code: "XLM", contract: "CDLZFC3SYJYDZT7K67VZ75HPJVIEUVNIXF47ZG2FB2RMQQVU2HHGCYSC")
    private let usdc = IntegrationAsset(code: "USDC", contract: "CBIELTK6YBZJU5UP2WWQEUCYKLPU6AUNZ2BQ4WWFEIE3USCIHMXQDAMA")
    private let account = "CCDO6J7WOGPTKZA73FWECCIJ75TTOMHMCWLEGPYWIFCNSINM63UJDDYB"
    private let pocket = "CDGWNZPBHLWML4Z4SFSFLO2NRYV6566CFRM2E5ZRZE74AIXO6FYCS437"
    private let now: UInt64 = 1_791_961_199

    private struct Unavailable: Error {}

    private var request: SwapRequest { SwapRequest(assetIn: xlm, assetOut: usdc, amountIn: 100_000_000) }

    @Test("Meilleure route : la plus grande quantité reçue ; les autres devis sont gardés")
    func bestQuote() async throws {
        let registry = IntegrationRegistry(swapAdapters: [
            MockSwapAdapter(id: "first", name: "First", numerator: 106, denominator: 1000),
            MockSwapAdapter(id: "second", name: "Second", numerator: 446, denominator: 1000),
        ], yieldAdapters: [])
        let comparison = await registry.bestQuote(request)
        #expect(comparison.best?.protocolID == "second")
        #expect(comparison.best?.amountOut == 44_600_000)
        #expect(comparison.quotes.map(\.protocolID) == ["first", "second"])
        #expect(comparison.failures.isEmpty)
    }

    @Test("À égalité, le premier protocole enregistré")
    func tieKeepsFirst() async {
        let registry = IntegrationRegistry(swapAdapters: [
            MockSwapAdapter(id: "first", name: "First", numerator: 1, denominator: 2),
            MockSwapAdapter(id: "second", name: "Second", numerator: 1, denominator: 2),
        ], yieldAdapters: [])
        #expect(await registry.bestQuote(request).best?.protocolID == "first")
    }

    @Test("Protocole indisponible : sa panne est rendue (jamais avalée), l'autre devis reste ; route introuvable : ni devis ni panne")
    func failuresAreKept() async {
        var down = MockSwapAdapter(id: "down", name: "Down", numerator: 9, denominator: 1)
        down.failure = Unavailable()
        var empty = MockSwapAdapter(id: "empty", name: "Empty", numerator: 9, denominator: 1)
        empty.noRoute = true
        let registry = IntegrationRegistry(swapAdapters: [down, empty, MockSwapAdapter(id: "up", name: "Up", numerator: 1, denominator: 10)], yieldAdapters: [])
        let comparison = await registry.bestQuote(request)
        #expect(comparison.best?.protocolID == "up")
        #expect(comparison.failures.map(\.protocolID) == ["down"])
        #expect(comparison.failures.first?.error is Unavailable)
        #expect(comparison.answered == ["empty", "up"])

        let none = await IntegrationRegistry(swapAdapters: [down, empty], yieldAdapters: []).bestQuote(request)
        #expect(none.best == nil)
        #expect(none.failures.count == 1)
    }

    @Test("Devis à 0 ignoré")
    func zeroQuoteIgnored() async {
        let registry = IntegrationRegistry(swapAdapters: [MockSwapAdapter(id: "zero", name: "Zero", numerator: 0, denominator: 1)], yieldAdapters: [])
        #expect(await registry.bestQuote(request).best == nil)
    }

    @Test("Recherche par identifiant")
    func lookup() {
        let registry = IntegrationRegistry(
            swapAdapters: [MockSwapAdapter(id: "a", name: "A", numerator: 1, denominator: 1)],
            yieldAdapters: [MockYieldAdapter(asset: xlm)]
        )
        #expect(registry.swapAdapter(id: "a")?.name == "A")
        #expect(registry.swapAdapter(id: "b") == nil)
        #expect(registry.yieldAdapter(id: "mock-vaults")?.category == "Vaults")
    }

    @Test("Positions : celles de chaque protocole pour ce détenteur, et les protocoles en panne")
    func positions() async {
        var vaults = MockYieldAdapter(asset: xlm)
        vaults.positions = [
            YieldPosition(protocolID: vaults.id, venueID: vaults.vault, holder: account, shares: 599, value: 10_000_000),
            YieldPosition(protocolID: vaults.id, venueID: vaults.vault, holder: pocket, shares: 1, value: 1),
        ]
        var down = MockYieldAdapter(asset: usdc)
        down.failure = Unavailable()
        let discovery = await IntegrationRegistry(swapAdapters: [], yieldAdapters: [vaults, down]).positions(holder: account)
        #expect(discovery.positions.count == 1)
        #expect(discovery.positions.first?.holder == account)
        #expect(discovery.failures.map(\.protocolID) == ["mock-vaults"])
    }

    @Test("Swap factice de bout en bout : devis → appel → bornes = écran → arbre déclaré pour une Pocket")
    func mockSwapEndToEnd() async throws {
        let adapter = MockSwapAdapter(id: "mock", name: "Mock", numerator: 106, denominator: 1000)
        let quote = try #require(try await adapter.quote(request))
        let minimum = Slippage.minimum(of: quote.amountOut, basisPoints: Slippage.defaultBasisPoints)
        let call = try adapter.swapCall(for: quote, minimumOut: minimum, authorizer: pocket, now: now)
        let shown = SignedTerms(
            action: .swap, contract: adapter.router, authorizer: pocket, assetIn: xlm.contract, amountIn: request.amountIn,
            assetOut: usdc.contract, minimumOut: minimum, route: quote.route, deadline: now + 300
        )
        try BoundsCheck.verify(shown: shown, signed: try adapter.terms(of: call), quotedOut: quote.amountOut, now: now)
        let invocation = try IntegrationCallClient.declaredInvocation(call: call, authorizer: .pocket(pocket), shape: adapter.authShape(for: quote))
        #expect(invocation.subInvocations.count == 1)
    }

    @Test("Vault factice : dépôt et retrait au prorata, minimum − 0,5 %, bornes décodées")
    func mockVault() async throws {
        let adapter = MockYieldAdapter(asset: xlm)
        let venue = try #require(adapter.venues().first)
        #expect(venue.underlyingProtocols == ["Blend"])
        let deposit = try await adapter.depositCall(venue: venue, amount: 10_000_000, authorizer: account)
        #expect(try adapter.terms(of: deposit).amountIn == 10_000_000)
        _ = try IntegrationCallClient.declaredInvocation(call: deposit, authorizer: .account(account), shape: adapter.authShape())

        let position = YieldPosition(protocolID: adapter.id, venueID: adapter.vault, holder: account, shares: 600, value: 10_000_000)
        let half = try adapter.terms(of: try await adapter.withdrawCall(position: position, amount: 5_000_000, all: false))
        #expect(half.amountIn == 300)
        #expect(half.minimumOut == 4_975_000)
        let all = try adapter.terms(of: try await adapter.withdrawCall(position: position, amount: 0, all: true))
        #expect(all.amountIn == 600)
        #expect(all.minimumOut == 9_950_000)
    }

    @Test("Adresses factices : des adresses C valides, distinctes, qui ne sont pas celles des vrais protocoles")
    func mockAddresses() throws {
        let router = MockIntegrationAddress.contract("x.router")
        #expect(router.hasPrefix("C"))
        _ = try SCAddressXDR(contractId: router)
        #expect(router != MockIntegrationAddress.contract("x.pair"))
        #expect(router != ChimpNetworkConfig.testnet.contracts.router)
    }
}
