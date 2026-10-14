import Foundation
import stellarsdk
import Testing
@testable import ChimpDAO

/// Tranche 2, phase 1, étape 2 : l'arbre rendu par la simulation (ordre 2, Main account) doit être exactement l'arbre
/// déclaré par l'adaptateur, sinon rien n'est signé (principe 3, DESIGN_NOTES §13 du 2026-10-14).
/// Entrées enregistrées sur testnet le 2026-10-14 (ledger 5187971) : simulation « recording » d'un swap Soroswap
/// 1 XLM → USDC et d'un dépôt de 1 XLM dans le vault DeFindex XLM, au nom du Main account de Barth. Rien n'a été signé.
struct AuthTreeCheckTests {
    private let passphrase = ChimpNetworkConfig.testnet.passphrase
    private let account = "CCDO6J7WOGPTKZA73FWECCIJ75TTOMHMCWLEGPYWIFCNSINM63UJDDYB"
    private let other = "CB3NR2OIEHWKYSS2ZBTFDTZVSQCNJQNHOSJMQZU2N5KSWE3TLFWYVLGP"
    private let router = "CCJUD55AG6W5HAI5LRVNKAE5WDP5XGZBUDS5WNTIVDU7O264UZZE7BRD"
    private let chimpRouter = "CAOL3K7VQTDZELQMKTAJB3WUQGL5JLXJKZ2Y44F77NH4CZNLW5I755XI"
    private let pair = "CCBX3NZTCQLQFSPG7HBOKL4P2RVPOPVFHDNRTOSCCJWBTPL2GHEH7RQS"
    private let xlm = "CDLZFC3SYJYDZT7K67VZ75HPJVIEUVNIXF47ZG2FB2RMQQVU2HHGCYSC"
    private let usdc = "CBIELTK6YBZJU5UP2WWQEUCYKLPU6AUNZ2BQ4WWFEIE3USCIHMXQDAMA"
    private let cetes = "CC72F57YTPX76HAA64JQOEGHQAPSADQWSY5DWVBR66JINPFDLNCQYHIC"
    private let vault = "CCLV4H7WTLJQ7ATLHBBQV2WW3OINF3FOY5XZ7VPHZO7NH3D2ZS4GFSF6"

    static let recordedSwap = "AAAAAgAAAAGG7yf2cZ81ZB/ZbEEJCf9nNzDsFZZDPxZBRNkhrPbokX0F9MqkqhQyAAAAAAAAAAEAAAAAAAAAAZNB96A3rdOBHVxq1QCdsN/bmyGg5ds2aKjp92vcpnJPAAAAHHN3YXBfZXhhY3RfdG9rZW5zX2Zvcl90b2tlbnMAAAAFAAAACgAAAAAAAAAAAAAAAACYloAAAAAKAAAAAAAAAAAAAAAAAA9CQAAAABAAAAABAAAAAgAAABIAAAAB15KLcsJwPM/q9+uf9O9NUEpVqLl5/JtFDqLIQrTRzmEAAAASAAAAAVBFzV7Acpp2j9WtAlBYUt9PAo3Ogw5axSIJukhIOy8BAAAAEgAAAAGG7yf2cZ81ZB/ZbEEJCf9nNzDsFZZDPxZBRNkhrPbokQAAAAUAAAAA9IZXAAAAAAEAAAAAAAAAAdeSi3LCcDzP6vfrn/TvTVBKVai5efybRQ6iyEK00c5hAAAACHRyYW5zZmVyAAAAAwAAABIAAAABhu8n9nGfNWQf2WxBCQn/Zzcw7BWWQz8WQUTZIaz26JEAAAASAAAAAYN9tzMUFwLJ5vnC5S+P1Gr3PqU42xm6QhJsGb16Mch/AAAACgAAAAAAAAAAAAAAAACYloAAAAAA"
    static let recordedDeposit = "AAAAAgAAAAGG7yf2cZ81ZB/ZbEEJCf9nNzDsFZZDPxZBRNkhrPbokUZKHUlqAKcyAAAAAAAAAAEAAAAAAAAAAZdeH/aa0w+CazhDCurW25DS7K7Hb5/V58u+0+x6zLhiAAAAB2RlcG9zaXQAAAAABAAAABAAAAABAAAAAQAAAAoAAAAAAAAAAAAAAAAAmJaAAAAAEAAAAAEAAAABAAAACgAAAAAAAAAAAAAAAACYloAAAAASAAAAAYbvJ/ZxnzVkH9lsQQkJ/2c3MOwVlkM/FkFE2SGs9uiRAAAAAAAAAAEAAAABAAAAAAAAAAHXkotywnA8z+r365/0701QSlWouXn8m0UOoshCtNHOYQAAAAh0cmFuc2ZlcgAAAAMAAAASAAAAAYbvJ/ZxnzVkH9lsQQkJ/2c3MOwVlkM/FkFE2SGs9uiRAAAAEgAAAAGXXh/2mtMPgms4Qwrq1tuQ0uyux2+f1efLvtPsesy4YgAAAAoAAAAAAAAAAAAAAAAAmJaAAAAAAA=="

    private var shape: SoroswapAuthShape { SoroswapAuthShape(router: router, pair: pair) }

    private func swap(
        amountIn: Int128 = 10_000_000, minOut: Int128 = 1_000_000, path: [String]? = nil, to: String? = nil, contract: String? = nil,
        function: String = "swap_exact_tokens_for_tokens"
    ) throws -> ContractCall {
        ContractCall(contract: contract ?? router, function: function, arguments: [
            ContractArgument.i128(amountIn), ContractArgument.i128(minOut), .vec(try (path ?? [xlm, usdc]).map { try ContractArgument.address($0) }),
            try ContractArgument.address(to ?? account), .u64(4_102_444_800),
        ])
    }

    /// L'arbre que l'adaptateur Soroswap déclare pour le swap enregistré.
    private func declaredSwap() throws -> SorobanAuthorizedInvocationXDR {
        try DeclaredInvocations.build(root: try swap(), authorizers: [.account(account)], shape: shape)[0].invocation
    }

    /// Une entrée « simulée » portant `invocation`, avec les credentials (V2) de l'entrée enregistrée.
    private func simulated(_ invocation: SorobanAuthorizedInvocationXDR, address: String? = nil) throws -> SorobanAuthorizationEntryXDR {
        let recorded = try SorobanAuthorizationEntryXDR(fromBase64: Self.recordedSwap)
        var credentials = try SorobanAuth.addressCredentials(recorded)
        if let address { credentials.address = try SCAddressXDR(contractId: address) }
        return SorobanAuthorizationEntryXDR(credentials: .addressV2(credentials), rootInvocation: invocation)
    }

    private func check(_ entries: [SorobanAuthorizationEntryXDR], expected: SorobanAuthorizedInvocationXDR) throws -> SorobanAuth.PendingEntry {
        try AuthorizedCall.checkedAccountEntry(entries, account: account, expected: expected, passphrase: passphrase, expirationLedger: 5_188_091)
    }

    private func expectMismatch(_ invocation: SorobanAuthorizedInvocationXDR, _ mismatch: AuthTreeCheck.Mismatch) throws {
        #expect(throws: AuthorizedCall.CallError.treeMismatch(mismatch)) { try check([try simulated(invocation)], expected: try declaredSwap()) }
    }

    // MARK: Accepté

    @Test("Swap Soroswap : l'arbre simulé sur testnet est exactement l'arbre déclaré ; entrée V2 gardée, expiration posée")
    func recordedSwapAccepted() throws {
        let recorded = try SorobanAuthorizationEntryXDR(fromBase64: Self.recordedSwap)
        let pending = try check([recorded], expected: try declaredSwap())
        #expect(SorobanAuth.isAddressV2(pending.entry))
        #expect(try SorobanAuth.addressCredentials(pending.entry).signatureExpirationLedger == 5_188_091)
        #expect(pending.digest == (try SorobanAuth.payloadHash(pending.entry, passphrase: passphrase, expirationLedger: 5_188_091)))
    }

    @Test("Dépôt DeFindex : l'arbre simulé sur testnet est exactement l'arbre déclaré")
    func recordedDepositAccepted() throws {
        let deposit = ContractCall(contract: vault, function: "deposit", arguments: [
            .vec([ContractArgument.i128(10_000_000)]), .vec([ContractArgument.i128(10_000_000)]), try ContractArgument.address(account), .bool(true),
        ])
        let declared = try DeclaredInvocations.build(root: deposit, authorizers: [.account(account)], shape: DeFindexAuthShape(underlying: [vault: xlm]))
        let recorded = try SorobanAuthorizationEntryXDR(fromBase64: Self.recordedDeposit)
        _ = try check([recorded], expected: declared[0].invocation)
    }

    // MARK: Refus (principe 9 : montant, actif, destination, contrat, route modifiés)

    @Test("Montant donné modifié : refusé (argument 0 de l'appel racine)")
    func amountChanged() throws {
        try expectMismatch(try DeclaredInvocations.build(root: try swap(amountIn: 20_000_000), authorizers: [.account(account)], shape: shape)[0].invocation,
                           .argument(path: "root", index: 0))
    }

    @Test("Minimum reçu modifié : refusé (argument 1)")
    func minimumChanged() throws {
        try expectMismatch(try DeclaredInvocations.build(root: try swap(minOut: 1), authorizers: [.account(account)], shape: shape)[0].invocation,
                           .argument(path: "root", index: 1))
    }

    @Test("Route ou actif reçu modifiés : refusé (argument 2, le chemin)")
    func routeChanged() throws {
        try expectMismatch(try DeclaredInvocations.build(root: try swap(path: [xlm, usdc, cetes]), authorizers: [.account(account)], shape: shape)[0].invocation,
                           .argument(path: "root", index: 2))
        try expectMismatch(try DeclaredInvocations.build(root: try swap(path: [xlm, cetes]), authorizers: [.account(account)], shape: shape)[0].invocation,
                           .argument(path: "root", index: 2))
    }

    @Test("Destination modifiée : refusé (argument 3, `to`)")
    func destinationChanged() throws {
        let tampered = try swap(to: other).invocation(subInvocations: [
            try TokenShape.transfer(token: xlm, from: account, to: pair, units: 10_000_000).invocation(),
        ])
        try expectMismatch(tampered, .argument(path: "root", index: 3))
    }

    @Test("Contrat ou fonction modifiés : refusé")
    func contractChanged() throws {
        let sub = [try TokenShape.transfer(token: xlm, from: account, to: pair, units: 10_000_000).invocation()]
        try expectMismatch(try swap(contract: chimpRouter).invocation(subInvocations: sub), .contract(path: "root", expected: router, got: chimpRouter))
        try expectMismatch(try swap(function: "swap_tokens_for_exact_tokens").invocation(subInvocations: sub),
                           .function(path: "root", expected: "swap_exact_tokens_for_tokens", got: "swap_tokens_for_exact_tokens"))
    }

    @Test("Prise modifiée sous un appel racine identique : actif, destination ou montant du transfer → refusé")
    func pullChanged() throws {
        let transfer = { (token: String, to: String, units: Int128) in
            try self.swap().invocation(subInvocations: [try TokenShape.transfer(token: token, from: self.account, to: to, units: units).invocation()])
        }
        try expectMismatch(try transfer(usdc, pair, 10_000_000), .contract(path: "root.0", expected: xlm, got: usdc))
        try expectMismatch(try transfer(xlm, other, 10_000_000), .argument(path: "root.0", index: 1))
        try expectMismatch(try transfer(xlm, pair, 10_000_001), .argument(path: "root.0", index: 2))
    }

    @Test("Sous-appel en trop ou manquant : refusé")
    func subInvocationCount() throws {
        let pull = try TokenShape.transfer(token: xlm, from: account, to: pair, units: 10_000_000).invocation()
        let extra = try TokenShape.transfer(token: usdc, from: account, to: other, units: 1).invocation()
        try expectMismatch(try swap().invocation(subInvocations: [pull, extra]), .subInvocationCount(path: "root", expected: 1, got: 2))
        try expectMismatch(try swap().invocation(), .subInvocationCount(path: "root", expected: 1, got: 0))
    }

    @Test("Deux entrées pour le compte, ou une entrée pour une autre adresse : refusé avant toute signature")
    func entriesRefused() throws {
        let recorded = try SorobanAuthorizationEntryXDR(fromBase64: Self.recordedSwap)
        #expect(throws: AuthorizedCall.CallError.unexpectedAuthorization("2 entries to sign")) {
            try check([recorded, recorded], expected: try declaredSwap())
        }
        #expect(throws: SorobanAuth.AuthError.unexpectedSigner(other)) {
            try check([recorded, try simulated(try declaredSwap(), address: other)], expected: try declaredSwap())
        }
        let delegated = SorobanAuthorizationEntryXDR(
            credentials: .addressWithDelegates(SorobanAddressCredentialsWithDelegatesXDR(
                addressCredentials: try SorobanAuth.addressCredentials(recorded), delegates: []
            )),
            rootInvocation: recorded.rootInvocation
        )
        #expect(throws: SorobanAuth.AuthError.notAddressCredentials("address with delegates")) {
            try check([delegated], expected: try declaredSwap())
        }
    }

    @Test("Arbre attendu par défaut (paiement) : l'appel sans sous-appel ; un swap avec sa prise y est refusé")
    func defaultExpectationUnchanged() throws {
        let bare = try swap().invocation()
        let recorded = try SorobanAuthorizationEntryXDR(fromBase64: Self.recordedSwap)
        #expect(throws: AuthorizedCall.CallError.treeMismatch(.subInvocationCount(path: "root", expected: 0, got: 1))) {
            try check([recorded], expected: bare)
        }
    }

    @Test("La différence est nommée dans le message d'erreur")
    func messages() {
        #expect(AuthorizedCall.CallError.treeMismatch(.argument(path: "root.0", index: 2)).errorDescription
                == "Unexpected authorization from the simulation: argument 2 of root.0 differs")
        #expect(AuthTreeCheck.Mismatch.subInvocationCount(path: "root", expected: 1, got: 2).description == "root authorizes 2 sub-calls instead of 1")
    }
}
