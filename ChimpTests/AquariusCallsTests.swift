import Foundation
import stellarsdk
import Testing
@testable import ChimpDAO

/// Tranche 2, phase 3, étape 1 : appels Aquarius et leur forme d'autorisation (`AquariusCalls`, `AquariusAuthShape`).
/// Aquarius n'est pas dans `reference/` : les arbres attendus sont ceux que le testnet a rendus le 2026-10-14 par
/// simulation « recording » (rien de signé), pour le Main account `CCDO6J…DDYB`, router `CBCFTQSP…`, pool XLM/USDC à
/// 0,3 % `CAYBMZYJ…` (`pool_index` `9ac7a9cd…`), pool USDC/CETES `CBJPT2SC…`.
struct AquariusCallsTests {
    private let router = IntegrationConfig.testnet.aquarius.router
    private let account = "CCDO6J7WOGPTKZA73FWECCIJ75TTOMHMCWLEGPYWIFCNSINM63UJDDYB"
    private let pocket = "CCGYGX2HBP464WZWXHHFOMS25CMIBKH3PUKOKRESOM3Z2W4UJRLLJ72Q"
    private let xlm = "CDLZFC3SYJYDZT7K67VZ75HPJVIEUVNIXF47ZG2FB2RMQQVU2HHGCYSC"
    private let usdc = "CBIELTK6YBZJU5UP2WWQEUCYKLPU6AUNZ2BQ4WWFEIE3USCIHMXQDAMA"
    private let cetes = "CC72F57YTPX76HAA64JQOEGHQAPSADQWSY5DWVBR66JINPFDLNCQYHIC"
    private let xlmUsdcPool = "CAYBMZYJCOMMOHOGOGBK7ANIKF3JPZAL4D7SWAPVPHC4WBMOUT5DJN5B"
    private let usdcCetesPool = "CBJPT2SCZSUJQGBZHHCHLZJX3GVYLOPVUKF53ESH4NFQZMC2UFPDWHRI"
    /// Même `pool_index` pour les deux pools : il dépend du type et des frais (produit constant, 0,3 %), pas des jetons.
    private let hash = Data(hex: "9ac7a9cde23ac2ada11105eeaa42e43c2ea8332ca0aa8f41f58d7160274d718e")!

    private var xlmToUsdc: AquariusCalls.Hop { .init(tokens: [usdc, xlm], poolHash: hash, pool: xlmUsdcPool, tokenOut: usdc) }
    private var usdcToCetes: AquariusCalls.Hop { .init(tokens: [usdc, cetes], poolHash: hash, pool: usdcCetesPool, tokenOut: cetes) }
    private var directShape: AquariusAuthShape { AquariusAuthShape(router: router, pool: xlmUsdcPool, poolTokens: [usdc, xlm]) }
    private var chainShape: AquariusAuthShape { AquariusAuthShape(router: router, pool: "", poolTokens: []) }

    private func base64(_ invocation: SorobanAuthorizedInvocationXDR) throws -> String {
        Data(try XDREncoder.encode(invocation)).base64EncodedString()
    }

    private func declared(_ call: ContractCall, by authorizer: CallAuthorizer, shape: AquariusAuthShape) throws -> String {
        let trees = try DeclaredInvocations.build(root: call, authorizers: [authorizer], shape: shape)
        #expect(trees.count == 1)
        return try base64(trees[0].invocation)
    }

    // MARK: Tri des jetons

    @Test("Tri des jetons par les octets du contrat, pas par le texte de l'adresse")
    func tokenOrder() throws {
        #expect(try AquariusCalls.sortedTokens(xlm, usdc) == [usdc, xlm])
        #expect(try AquariusCalls.sortedTokens(usdc, xlm) == [usdc, xlm])
        #expect(try AquariusCalls.sortedTokens(cetes, usdc) == [usdc, cetes])
        // 0x04… avant 0x3e… alors que « CA7 » précède « CAC » en texte.
        let low = "CACAIBAEAQCAIBAEAQCAIBAEAQCAIBAEAQCAIBAEAQCAIBAEAQCAINCW"
        let high = "CA7D4PR6HY7D4PR6HY7D4PR6HY7D4PR6HY7D4PR6HY7D4PR6HY7D5IR2"
        #expect([low, high].sorted() == [high, low])
        #expect(try AquariusCalls.sortedTokens(high, low) == [low, high])
        #expect(throws: (any Error).self) { try AquariusCalls.sortedTokens("GABC", usdc) }
    }

    // MARK: Arbres confirmés sur testnet

    @Test("swap direct : router → pool.swap(user, 1, 0, …) → transfer(user → pool), octet pour octet comme le testnet")
    func directSwapTree() throws {
        let call = try AquariusCalls.swap(router: router, user: account, hop: xlmToUsdc, amountIn: 10_000_000, minimumOut: 4_400_000)
        #expect(try declared(call, by: .account(account), shape: directShape) == "AAAAAAAAAAFEWcJPGECM+j56YKlCymqsfUEV2jif6kewUK2AcYgZ0AAAAARzd2FwAAAABwAAABIAAAABhu8n9nGfNWQf2WxBCQn/Zzcw7BWWQz8WQUTZIaz26JEAAAAQAAAAAQAAAAIAAAASAAAAAVBFzV7Acpp2j9WtAlBYUt9PAo3Ogw5axSIJukhIOy8BAAAAEgAAAAHXkotywnA8z+r365/0701QSlWouXn8m0UOoshCtNHOYQAAABIAAAAB15KLcsJwPM/q9+uf9O9NUEpVqLl5/JtFDqLIQrTRzmEAAAASAAAAAVBFzV7Acpp2j9WtAlBYUt9PAo3Ogw5axSIJukhIOy8BAAAADQAAACCax6nN4jrCraERBe6qQuQ8LqgzLKCqj0H1jXFgJ01xjgAAAAkAAAAAAAAAAAAAAAAAmJaAAAAACQAAAAAAAAAAAAAAAABDI4AAAAABAAAAAAAAAAEwFmcJE5jHHcZxgq+BqFF2l+QL4P8rAfV5xcsFjqT6NAAAAARzd2FwAAAABQAAABIAAAABhu8n9nGfNWQf2WxBCQn/Zzcw7BWWQz8WQUTZIaz26JEAAAADAAAAAQAAAAMAAAAAAAAACQAAAAAAAAAAAAAAAACYloAAAAAJAAAAAAAAAAAAAAAAAEMjgAAAAAEAAAAAAAAAAdeSi3LCcDzP6vfrn/TvTVBKVai5efybRQ6iyEK00c5hAAAACHRyYW5zZmVyAAAAAwAAABIAAAABhu8n9nGfNWQf2WxBCQn/Zzcw7BWWQz8WQUTZIaz26JEAAAASAAAAATAWZwkTmMcdxnGCr4GoUXaX5Avg/ysB9XnFywWOpPo0AAAACgAAAAAAAAAAAAAAAACYloAAAAAA")
    }

    @Test("swap_chained à un saut : router → transfer(user → router), comme le testnet")
    func chainedOneHopTree() throws {
        let call = try AquariusCalls.chained(router: router, user: account, tokenIn: xlm, hops: [xlmToUsdc], amountIn: 10_000_000, minimumOut: 4_400_000)
        #expect(try declared(call, by: .account(account), shape: chainShape) == "AAAAAAAAAAFEWcJPGECM+j56YKlCymqsfUEV2jif6kewUK2AcYgZ0AAAAAxzd2FwX2NoYWluZWQAAAAFAAAAEgAAAAGG7yf2cZ81ZB/ZbEEJCf9nNzDsFZZDPxZBRNkhrPbokQAAABAAAAABAAAAAQAAABAAAAABAAAAAwAAABAAAAABAAAAAgAAABIAAAABUEXNXsBymnaP1a0CUFhS308Cjc6DDlrFIgm6SEg7LwEAAAASAAAAAdeSi3LCcDzP6vfrn/TvTVBKVai5efybRQ6iyEK00c5hAAAADQAAACCax6nN4jrCraERBe6qQuQ8LqgzLKCqj0H1jXFgJ01xjgAAABIAAAABUEXNXsBymnaP1a0CUFhS308Cjc6DDlrFIgm6SEg7LwEAAAASAAAAAdeSi3LCcDzP6vfrn/TvTVBKVai5efybRQ6iyEK00c5hAAAACQAAAAAAAAAAAAAAAACYloAAAAAJAAAAAAAAAAAAAAAAAEMjgAAAAAEAAAAAAAAAAdeSi3LCcDzP6vfrn/TvTVBKVai5efybRQ6iyEK00c5hAAAACHRyYW5zZmVyAAAAAwAAABIAAAABhu8n9nGfNWQf2WxBCQn/Zzcw7BWWQz8WQUTZIaz26JEAAAASAAAAAURZwk8YQIz6PnpgqULKaqx9QRXaOJ/qR7BQrYBxiBnQAAAACgAAAAAAAAAAAAAAAACYloAAAAAA")
    }

    @Test("swap_chained à deux sauts XLM → USDC → CETES : une seule prise, vers le router, comme le testnet")
    func chainedTwoHopsTree() throws {
        let call = try AquariusCalls.chained(router: router, user: account, tokenIn: xlm, hops: [xlmToUsdc, usdcToCetes], amountIn: 10_000_000, minimumOut: 1)
        #expect(try declared(call, by: .account(account), shape: chainShape) == "AAAAAAAAAAFEWcJPGECM+j56YKlCymqsfUEV2jif6kewUK2AcYgZ0AAAAAxzd2FwX2NoYWluZWQAAAAFAAAAEgAAAAGG7yf2cZ81ZB/ZbEEJCf9nNzDsFZZDPxZBRNkhrPbokQAAABAAAAABAAAAAgAAABAAAAABAAAAAwAAABAAAAABAAAAAgAAABIAAAABUEXNXsBymnaP1a0CUFhS308Cjc6DDlrFIgm6SEg7LwEAAAASAAAAAdeSi3LCcDzP6vfrn/TvTVBKVai5efybRQ6iyEK00c5hAAAADQAAACCax6nN4jrCraERBe6qQuQ8LqgzLKCqj0H1jXFgJ01xjgAAABIAAAABUEXNXsBymnaP1a0CUFhS308Cjc6DDlrFIgm6SEg7LwEAAAAQAAAAAQAAAAMAAAAQAAAAAQAAAAIAAAASAAAAAVBFzV7Acpp2j9WtAlBYUt9PAo3Ogw5axSIJukhIOy8BAAAAEgAAAAG/ovf4m+//HAD3EwcQx4AfIA4Wljo7VDH3koa8o1tFDAAAAA0AAAAgmsepzeI6wq2hEQXuqkLkPC6oMyygqo9B9Y1xYCdNcY4AAAASAAAAAb+i9/ib7/8cAPcTBxDHgB8gDhaWOjtUMfeShryjW0UMAAAAEgAAAAHXkotywnA8z+r365/0701QSlWouXn8m0UOoshCtNHOYQAAAAkAAAAAAAAAAAAAAAAAmJaAAAAACQAAAAAAAAAAAAAAAAAAAAEAAAABAAAAAAAAAAHXkotywnA8z+r365/0701QSlWouXn8m0UOoshCtNHOYQAAAAh0cmFuc2ZlcgAAAAMAAAASAAAAAYbvJ/ZxnzVkH9lsQQkJ/2c3MOwVlkM/FkFE2SGs9uiRAAAAEgAAAAFEWcJPGECM+j56YKlCymqsfUEV2jif6kewUK2AcYgZ0AAAAAoAAAAAAAAAAAAAAAAAmJaAAAAAAA==")
    }

    @Test("Depuis le wallet d'une carte : le même arbre, autorisé et payé par la Pocket ; USDC → XLM prend l'USDC (indices 0 → 1)")
    func pocketAndReverse() throws {
        let reverse = AquariusCalls.Hop(tokens: [usdc, xlm], poolHash: hash, pool: xlmUsdcPool, tokenOut: xlm)
        let call = try AquariusCalls.swap(router: router, user: pocket, hop: reverse, amountIn: 2_500_000, minimumOut: 5_000_000)
        let tree = try #require(try DeclaredInvocations.build(root: call, authorizers: [.pocket(pocket)], shape: directShape).first)
        #expect(tree.authorizer == CallAuthorizer.pocket(pocket))
        let poolSwap = try #require(tree.invocation.subInvocations.first)
        guard case .contractFn(let poolArgs) = poolSwap.function, case .contractFn(let transferArgs) = try #require(poolSwap.subInvocations.first).function else {
            Issue.record("not a contract call"); return
        }
        #expect(try poolArgs.contractAddress.toStrKey() == xlmUsdcPool)
        #expect(poolArgs.args[1].u32 == 0)
        #expect(poolArgs.args[2].u32 == 1)
        #expect(try transferArgs.contractAddress.toStrKey() == usdc)
        #expect(try transferArgs.args[0].address?.toStrKey() == pocket)
        #expect(try transferArgs.args[1].address?.toStrKey() == xlmUsdcPool)
        #expect(ContractArgument.int128(transferArgs.args[2]) == 2_500_000)
    }

    // MARK: Bornes relues

    @Test("Bornes d'un swap direct et d'un swap à deux sauts, sans échéance")
    func terms() throws {
        let direct = try AquariusCalls.terms(
            of: try AquariusCalls.swap(router: router, user: account, hop: xlmToUsdc, amountIn: 10_000_000, minimumOut: 4_400_000),
            router: router
        )
        #expect(direct == SignedTerms(
            action: .swap, contract: router, authorizer: account, assetIn: xlm, amountIn: 10_000_000,
            assetOut: usdc, minimumOut: 4_400_000, route: [xlm, usdc], deadline: nil
        ))
        let chained = try AquariusCalls.terms(
            of: try AquariusCalls.chained(router: router, user: pocket, tokenIn: xlm, hops: [xlmToUsdc, usdcToCetes], amountIn: 10_000_000, minimumOut: 7),
            router: router
        )
        #expect(chained.route == [xlm, usdc, cetes])
        #expect(chained.assetOut == cetes)
        #expect(chained.minimumOut == 7)
        #expect(chained.authorizer == pocket)
        #expect(chained.deadline == nil)
    }

    @Test("Bornes refusées : autre router, jetons non triés, maillons qui ne se suivent pas, autre fonction")
    func termsRefused() throws {
        let good = try AquariusCalls.swap(router: router, user: account, hop: xlmToUsdc, amountIn: 1, minimumOut: 1)
        #expect(throws: ContractArgument.ArgumentError.self) { try AquariusCalls.terms(of: good, router: IntegrationConfig.testnet.soroswap.router) }

        var unsorted = good.arguments
        unsorted[1] = .vec([try ContractArgument.address(xlm), try ContractArgument.address(usdc)])
        #expect(throws: ContractArgument.ArgumentError.self) {
            try AquariusCalls.terms(of: ContractCall(contract: router, function: "swap", arguments: unsorted), router: router)
        }

        let broken = try AquariusCalls.chained(router: router, user: account, tokenIn: xlm, hops: [usdcToCetes], amountIn: 1, minimumOut: 1)
        #expect(throws: ContractArgument.ArgumentError.self) { try AquariusCalls.terms(of: broken, router: router) }

        let deposit = ContractCall(contract: router, function: "deposit", arguments: good.arguments)
        #expect(throws: ContractArgument.ArgumentError.self) { try AquariusCalls.terms(of: deposit, router: router) }
    }

    @Test("Montants en u128 : négatif refusé à l'encodage, valeur au-delà d'un i128 refusée à la lecture")
    func u128Amounts() throws {
        #expect(throws: ContractArgument.ArgumentError.self) {
            try AquariusCalls.swap(router: router, user: account, hop: xlmToUsdc, amountIn: -1, minimumOut: 1)
        }
        #expect(AquariusCalls.int128(ContractArgument.u128(42)) == 42)
        #expect(AquariusCalls.int128(ContractArgument.u128(UInt128.max)) == nil)
        #expect(AquariusCalls.int128(ContractArgument.i128(42)) == nil)
    }

    @Test("Forme : rien sur un autre router, rien pour qui n'est pas user, pool qui ne correspond pas refusé")
    func shapeRefusals() throws {
        let call = try AquariusCalls.swap(router: router, user: account, hop: xlmToUsdc, amountIn: 1, minimumOut: 1)
        #expect(try directShape.pulls(of: call, from: pocket).isEmpty)
        let elsewhere = ContractCall(contract: IntegrationConfig.testnet.soroswap.router, function: "swap", arguments: call.arguments)
        #expect(directShape.signer(of: elsewhere) == nil)
        let otherPool = AquariusAuthShape(router: router, pool: usdcCetesPool, poolTokens: [usdc, cetes])
        #expect(throws: ContractArgument.ArgumentError.self) { try otherPool.pulls(of: call, from: account) }
    }
}
