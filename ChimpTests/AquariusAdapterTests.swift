import Foundation
import stellarsdk
import Testing
@testable import ChimpDAO

/// Tranche 2, phase 3, étape 2 : l'adaptateur Aquarius réel, avec les réponses du RPC rejouées.
/// Réponses lues sur testnet le 2026-10-14 (simulations, rien de signé), router `CBCFTQSP…` :
/// - pools XLM/USDC : `37b955f3…` → `CDVB6O3W…` (1 %), `9ac7a9cd…` → `CAYBMZYJ…` (0,3 %), `b2e02fcf…` → `CCGFVAHV…` (0,1 %) ;
/// - 10 XLM → 4,3383109 / 4,4560433 / 4,3609693 USDC ; 10 USDC → 22,5739461 / 22,3067657 / 22,8837825 XLM ;
/// - pool USDC/CETES `CBJPT2SC…` (0,3 %) : 4,4560433 USDC → 5 016,059078 CETES ; aucun pool XLM/CETES.
struct AquariusAdapterTests {
    private let contracts = IntegrationConfig.testnet.aquarius
    private let xlm = IntegrationAsset(code: "XLM", contract: "CDLZFC3SYJYDZT7K67VZ75HPJVIEUVNIXF47ZG2FB2RMQQVU2HHGCYSC")
    private let usdc = IntegrationAsset(code: "USDC", contract: "CBIELTK6YBZJU5UP2WWQEUCYKLPU6AUNZ2BQ4WWFEIE3USCIHMXQDAMA")
    private let cetes = IntegrationAsset(code: "CETES", contract: "CC72F57YTPX76HAA64JQOEGHQAPSADQWSY5DWVBR66JINPFDLNCQYHIC")
    private let account = "CCDO6J7WOGPTKZA73FWECCIJ75TTOMHMCWLEGPYWIFCNSINM63UJDDYB"

    private static let poolsXLMUSDC = "AAAAEQAAAAEAAAADAAAADQAAACA3uVXzcI2udIytRlRB/K1wsm/+JyOFInpKc3I0rkKb3wAAABIAAAAB6h87dr64AGf/lCLe6AGnCCD7zd+KboS1fOveDebdfMcAAAANAAAAIJrHqc3iOsKtoREF7qpC5DwuqDMsoKqPQfWNcWAnTXGOAAAAEgAAAAEwFmcJE5jHHcZxgq+BqFF2l+QL4P8rAfV5xcsFjqT6NAAAAA0AAAAgsuAvz8pslvitXL2E53hKd3s22clqJFlALE9FhGKqt/AAAAASAAAAAYxagPVvLmxqSrNEsLEJ8R89lItbEBgysxaG2t9neEGt"
    private static let poolsUSDCCETES = "AAAAEQAAAAEAAAABAAAADQAAACCax6nN4jrCraERBe6qQuQ8LqgzLKCqj0H1jXFgJ01xjgAAABIAAAABUvnqQsyomBg5OcR15TfZq4W59aKL3ZJH40sMsFqhXjs="
    private static let noPools = "AAAAEQAAAAEAAAAA"
    private static let constantProduct = "AAAAEQAAAAEAAAACAAAADwAAAANmZWUAAAAAAwAAAB4AAAAPAAAACXBvb2xfdHlwZQAAAAAAAA8AAAAQY29uc3RhbnRfcHJvZHVjdA=="

    /// Par pool (`pool_index` en hex, 8 premiers caractères) : devis de 10 XLM → USDC, de 10 USDC → XLM, réserves.
    private static let xlmUSDC: [String: (xlmToUSDC: String, usdcToXLM: String, reserves: String)] = [
        "37b955f3": ("AAAACQAAAAAAAAAAAAAAAAKV+UU=", "AAAACQAAAAAAAAAAAAAAAA10gsU=", "AAAAEAAAAAEAAAACAAAACQAAAAAAAAAAAAAAKhAx4ZwAAAAJAAAAAAAAAAAAAABf9w5kZg=="),
        "9ac7a9cd": ("AAAACQAAAAAAAAAAAAAAAAKn8DE=", "AAAACQAAAAAAAAAAAAAAAA1Lvgk=", "AAAAEAAAAAEAAAACAAAACQAAAAAAAAAAAAANQOlTCYoAAAAJAAAAAAAAAAAAAB2nUFKohA=="),
        "b2e02fcf": ("AAAACQAAAAAAAAAAAAAAAAKZbl0=", "AAAACQAAAAAAAAAAAAAAAA2jycE=", "AAAAEAAAAAEAAAACAAAACQAAAAAAAAAAAAAC0PgvEjsAAAAJAAAAAAAAAAAAAAZzjj4dgw=="),
    ]
    private static let usdcCETESReserves = "AAAAEAAAAAEAAAACAAAACQAAAAAAAAAAAAAAABInDJ4AAAAJAAAAAAAAAAAAAAAJLIQGGA=="
    private static let usdcToCETES = "AAAACQAAAAAAAAAAAAAAASr6/MY="

    /// Le RPC rejoué : chaque lecture est décidée par `reply` et notée.
    private final class ScriptedReader: ContractReading {
        var reply: (String, [SCValXDR]) throws -> SCValXDR
        private(set) var calls: [String] = []

        init(reply: @escaping (String, [SCValXDR]) throws -> SCValXDR) {
            self.reply = reply
        }

        func readValue(contract: String, function: String, arguments: [SCValXDR]) async throws -> SCValXDR {
            calls.append(function)
            return try reply(function, arguments)
        }
    }

    private static func value(_ base64: String) throws -> SCValXDR {
        try SCValXDR(xdr: base64)
    }

    private static func hashKey(_ value: SCValXDR) -> String {
        (value.bytes ?? Data()).prefix(4).map { String(format: "%02x", $0) }.joined()
    }

    /// Le testnet du 2026-10-14 ; `failingPool` (8 caractères hex) répond `error` au devis.
    private func testnetReader(failingPool: String? = nil, error: Error? = nil) -> ScriptedReader {
        let xlmContract = xlm.contract, usdcContract = usdc.contract, cetesContract = cetes.contract
        return ScriptedReader { function, arguments in
            let tokens = ContractArgument.addresses(arguments.first ?? .void) ?? []
            switch function {
            case "get_pools":
                if Set(tokens) == [xlmContract, usdcContract] { return try Self.value(Self.poolsXLMUSDC) }
                if Set(tokens) == [usdcContract, cetesContract] { return try Self.value(Self.poolsUSDCCETES) }
                return try Self.value(Self.noPools)
            case "get_info":
                return try Self.value(Self.constantProduct)
            case "estimate_swap":
                let pool = Self.hashKey(arguments[3])
                if pool == failingPool, let error { throw error }
                let tokenIn = try arguments[1].address?.toStrKey()
                if Set(tokens) == [usdcContract, cetesContract] { return try Self.value(Self.usdcToCETES) }
                guard let replies = Self.xlmUSDC[pool] else { throw StellarError.simulationFailed("HostError: Error(Contract, #404)") }
                return try Self.value(tokenIn == xlmContract ? replies.xlmToUSDC : replies.usdcToXLM)
            case "get_reserves":
                if Set(tokens) == [usdcContract, cetesContract] { return try Self.value(Self.usdcCETESReserves) }
                return try Self.value(Self.xlmUSDC[Self.hashKey(arguments[1])]!.reserves)
            default:
                throw StellarError.rpc("no scripted reply for \(function)")
            }
        }
    }

    private func adapter(_ reader: ScriptedReader, hub: String? = nil) -> AquariusAdapter {
        AquariusAdapter(contracts: contracts, hub: hub ?? usdc.contract, reader: reader)
    }

    // MARK: Devis

    @Test("10 XLM → USDC : le meilleur des trois pools (0,3 %, 4,4560433 USDC), impact 30 pb, swap direct sur ce pool")
    func bestDirectPool() async throws {
        let quote = try #require(try await adapter(testnetReader()).quote(SwapRequest(assetIn: xlm, assetOut: usdc, amountIn: 100_000_000)))
        #expect(quote.protocolID == "aquarius")
        #expect(quote.amountOut == 44_560_433)
        #expect(quote.route == [xlm.contract, usdc.contract])
        #expect(quote.firstHopVenue == "CAYBMZYJCOMMOHOGOGBK7ANIKF3JPZAL4D7SWAPVPHC4WBMOUT5DJN5B")
        #expect(quote.priceImpactBasisPoints == 30)
        #expect(quote.hops.count == 1)
        #expect(quote.hops[0].tokens == [usdc.contract, xlm.contract])
        #expect(quote.hops[0].poolHash.prefix(4) == Data([0x9a, 0xc7, 0xa9, 0xcd]))
    }

    @Test("10 USDC → XLM : un autre pool gagne (0,1 %, 22,8837825 XLM) ; réserves lues dans le bon sens")
    func reverseDirection() async throws {
        let quote = try #require(try await adapter(testnetReader()).quote(SwapRequest(assetIn: usdc, assetOut: xlm, amountIn: 100_000_000)))
        #expect(quote.amountOut == 228_837_825)
        #expect(quote.firstHopVenue == "CCGFVAHVN4XGY2SKWNCLBMIJ6EPT3FELLMIBQMVTC2DNVX3HPBA23OMU")
        #expect(quote.priceImpactBasisPoints == 10)
    }

    @Test("XLM → CETES sans pool direct : un saut via l'USDC, swap_chained vers le router, impacts composés (30 et 1 299 pb)")
    func oneHopViaUSDC() async throws {
        let quote = try #require(try await adapter(testnetReader()).quote(SwapRequest(assetIn: xlm, assetOut: cetes, amountIn: 100_000_000)))
        #expect(quote.route == [xlm.contract, usdc.contract, cetes.contract])
        #expect(quote.amountOut == 5_016_059_078)
        #expect(quote.hops.map(\.pool) == ["CAYBMZYJCOMMOHOGOGBK7ANIKF3JPZAL4D7SWAPVPHC4WBMOUT5DJN5B", "CBJPT2SCZSUJQGBZHHCHLZJX3GVYLOPVUKF53ESH4NFQZMC2UFPDWHRI"])
        #expect(quote.firstHopVenue == contracts.router)
        #expect(quote.priceImpactBasisPoints == 1_326)

        let adapter = adapter(testnetReader())
        let call = try adapter.swapCall(for: quote, minimumOut: 4_990_000_000, authorizer: account, now: 0)
        #expect(call.function == "swap_chained")
        let terms = try adapter.terms(of: call)
        #expect(terms.route == quote.route)
        #expect(terms.minimumOut == 4_990_000_000)
        #expect(terms.deadline == nil)
        #expect(adapter.deadlineSeconds == nil)
    }

    @Test("Sans actif pivot, pas de saut : XLM → CETES n'a pas de route")
    func noHubNoHop() async throws {
        let quote = try await AquariusAdapter(contracts: contracts, hub: nil, reader: testnetReader())
            .quote(SwapRequest(assetIn: xlm, assetOut: cetes, amountIn: 100_000_000))
        #expect(quote == nil)
    }

    @Test("Pools lus une fois, type lu une fois par pool ; trois devis par demande")
    func memoized() async throws {
        let reader = testnetReader()
        let adapter = adapter(reader)
        _ = try await adapter.quote(SwapRequest(assetIn: xlm, assetOut: usdc, amountIn: 100_000_000))
        _ = try await adapter.quote(SwapRequest(assetIn: xlm, assetOut: usdc, amountIn: 100_000_000))
        #expect(reader.calls.filter { $0 == "get_pools" }.count == 1)
        #expect(reader.calls.filter { $0 == "get_info" }.count == 1)
        #expect(reader.calls.filter { $0 == "estimate_swap" }.count == 6)
    }

    @Test("Un pool qui refuse (en pause, vide) est écarté ; une panne réseau remonte")
    func failingPool() async throws {
        for code in [206, 2010] {
            let reader = testnetReader(failingPool: "9ac7a9cd", error: StellarError.simulationFailed("HostError: Error(Contract, #\(code))"))
            let quote = try #require(try await adapter(reader).quote(SwapRequest(assetIn: xlm, assetOut: usdc, amountIn: 100_000_000)))
            #expect(quote.amountOut == 43_609_693) // le pool à 0,1 %
        }
        let reader = testnetReader(failingPool: "9ac7a9cd", error: StellarError.rpc("timeout"))
        await #expect(throws: StellarError.rpc("timeout")) {
            _ = try await adapter(reader).quote(SwapRequest(assetIn: xlm, assetOut: usdc, amountIn: 100_000_000))
        }
    }

    @Test("Montant nul, mêmes actifs ou aucun pool : pas de devis")
    func noQuote() async throws {
        let reader = testnetReader()
        let adapter = adapter(reader)
        #expect(try await adapter.quote(SwapRequest(assetIn: xlm, assetOut: usdc, amountIn: 0)) == nil)
        #expect(try await adapter.quote(SwapRequest(assetIn: xlm, assetOut: xlm, amountIn: 1)) == nil)
        #expect(reader.calls.isEmpty)
        let lonely = IntegrationAsset(code: "AAA", contract: "CACAIBAEAQCAIBAEAQCAIBAEAQCAIBAEAQCAIBAEAQCAIBAEAQCAINCW")
        #expect(try await AquariusAdapter(contracts: contracts, hub: nil, reader: reader).quote(SwapRequest(assetIn: lonely, assetOut: usdc, amountIn: 1)) == nil)
    }

    @Test("Pool non constant : impact mesuré contre un montant mille fois plus petit")
    func otherCurve() async throws {
        let reader = testnetReader()
        let stable = try SCValXDR.map([SCMapEntryXDR(key: .symbol("pool_type"), val: .symbol("stable"))])
        let base = reader.reply
        reader.reply = { function, arguments in
            if function == "get_info" { return stable }
            if function == "estimate_swap", let units = AquariusCalls.int128(arguments[4]), units == 100_000 {
                return ContractArgument.u128(50_000) // prix « spot » : 0,5 USDC par XLM
            }
            return try base(function, arguments)
        }
        let quote = try #require(try await adapter(reader).quote(SwapRequest(assetIn: xlm, assetOut: usdc, amountIn: 100_000_000)))
        // spot : 50 000 000 ; rendu : 44 560 433 → 10,87 %
        #expect(quote.priceImpactBasisPoints == 1_087)
        #expect(reader.calls.contains("get_reserves"), "Réserves lues pour toute courbe : un devis ne doit jamais les dépasser")
    }

    @Test("Montants envoyés au RPC exacts, à chaque saut (garde-fou : Swift 6.3 corrompt un Int128 passé à une fonction async)")
    func amountsSentAreExact() async throws {
        let reader = testnetReader()
        var sent: [Int128?] = []
        let base = reader.reply
        reader.reply = { function, arguments in
            if function == "estimate_swap" { sent.append(AquariusCalls.int128(arguments[4])) }
            return try base(function, arguments)
        }
        _ = try await adapter(reader).quote(SwapRequest(assetIn: xlm, assetOut: cetes, amountIn: 100_000_000))
        // XLM → USDC sur les trois pools, puis USDC → CETES avec ce que rend le meilleur pool.
        #expect(sent == [100_000_000, 100_000_000, 100_000_000, 44_560_433])

        sent = []
        _ = try await adapter(reader).quote(SwapRequest(assetIn: usdc, assetOut: xlm, amountIn: 123_456_789_012))
        #expect(sent == [123_456_789_012, 123_456_789_012, 123_456_789_012])
    }

    // MARK: Vraisemblance

    @Test("Rejeu du devis corrompu (Swift 6.3, Debug) : 14,57 millions d'USDC pour 10 XLM, refusé avant l'écran")
    func corruptedQuoteBlocked() async throws {
        let reader = testnetReader()
        let base = reader.reply
        // Ce que le pool avait estimé pour le montant géant : presque toute sa réserve d'USDC (relevé sur testnet).
        reader.reply = { function, arguments in
            function == "estimate_swap" ? ContractArgument.u128(14_571_967_060_779) : try base(function, arguments)
        }
        await #expect(throws: SwapError.implausibleQuote) {
            _ = try await adapter(reader).quote(SwapRequest(assetIn: xlm, assetOut: usdc, amountIn: 100_000_000))
        }
    }

    @Test("Vraisemblance : un devis égal ou supérieur à la réserve du pool, ou meilleur que le prix spot, est refusé")
    func plausibility() async throws {
        // Réserves du pool à 0,3 % (USDC, XLM) : 14 572 443,601290 USDC et 3 260 444,4338308 XLM.
        let reserveUSDC: Int128 = 14_572_443_601_290, reserveXLM: Int128 = 32_604_444_338_308
        let spot = 100_000_000 * reserveUSDC / reserveXLM // 10 XLM au prix des réserves
        #expect(Slippage.isPlausible(amountIn: 100_000_000, amountOut: 44_560_433, reserveOut: reserveUSDC, spotIn: reserveXLM, spotOut: reserveUSDC))
        #expect(Slippage.isPlausible(amountIn: 100_000_000, amountOut: spot, reserveOut: reserveUSDC, spotIn: reserveXLM, spotOut: reserveUSDC), "Au prix spot exact : accepté")
        #expect(!Slippage.isPlausible(amountIn: 100_000_000, amountOut: spot + spot / 1_000, reserveOut: reserveUSDC, spotIn: reserveXLM, spotOut: reserveUSDC), "0,1 % au-dessus du spot")
        #expect(!Slippage.isPlausible(amountIn: 100_000_000, amountOut: reserveUSDC, reserveOut: reserveUSDC, spotIn: reserveXLM, spotOut: reserveUSDC), "Toute la réserve")
        #expect(!Slippage.isPlausible(amountIn: 100_000_000, amountOut: 0, reserveOut: reserveUSDC, spotIn: reserveXLM, spotOut: reserveUSDC))

        // Plus que la réserve, quelle que soit la courbe.
        let reader = testnetReader()
        let base = reader.reply
        reader.reply = { function, arguments in
            function == "estimate_swap" ? ContractArgument.u128(UInt128(reserveUSDC + 1)) : try base(function, arguments)
        }
        await #expect(throws: SwapError.implausibleQuote) {
            _ = try await adapter(reader).quote(SwapRequest(assetIn: xlm, assetOut: usdc, amountIn: 100_000_000))
        }
    }

    // MARK: Erreurs

    @Test("Refus Aquarius traduits : #2006 prix, #404 / #301 / #206 pas de route, #2010 liquidité ; #10 du jeton non traduit")
    func errors() {
        func error(_ code: Int) -> Error { StellarError.simulationFailed("HostError: Error(Contract, #\(code))\n…") }
        #expect(AquariusAdapter.swapError(for: error(2006)) == .slippageExceeded)
        #expect(AquariusAdapter.swapError(for: StellarError.transactionFailed(hash: "x", detail: "Error(Contract, #2006)")) == .slippageExceeded)
        for code in [404, 301, 307, 2007, 206] { #expect(AquariusAdapter.swapError(for: error(code)) == .noRoute) }
        for code in [2010, 324, 2018] { #expect(AquariusAdapter.swapError(for: error(code)) == .insufficientLiquidity) }
        #expect(AquariusAdapter.swapError(for: error(10)) == nil)
        #expect(AquariusAdapter.swapError(for: error(507)) == nil)
        #expect(AquariusAdapter.swapError(for: StellarError.rpc("timeout")) == nil)
    }

    @Test("Montant reçu lu dans la valeur rendue (u128) : 0,4456055 USDC pour 1 XLM sur testnet")
    func receivedUnits() throws {
        let adapter = adapter(testnetReader())
        #expect(adapter.receivedUnits(try SCValXDR(xdr: "AAAACQAAAAAAAAAAAAAAAABD/nc=")) == 4_456_055)
        #expect(adapter.receivedUnits(ContractArgument.i128(1)) == nil)
    }

    @Test("Composition des impacts : 1 − ∏(1 − impact), inconnue si un saut l'est")
    func compounded() {
        #expect(AquariusAdapter.compounded([30]) == 30)
        #expect(AquariusAdapter.compounded([30, 1_299]) == 1_326)
        #expect(AquariusAdapter.compounded([30, nil]) == nil)
        #expect(AquariusAdapter.compounded([]) == 0)
    }
}
