import Foundation
import stellarsdk
import Testing
@testable import ChimpDAO

/// Tranche 2, phase 1, étape 1 : arbres d'autorisation déclarés (`AuthShape`), lots du router.
/// Vecteurs calculés par les fonctions du terminal exécutées telles quelles (`auth-tree.ts`, `soroswap/auth.ts` copiés ;
/// `encodeCalls` de `router.ts`, `scMap` de `chip-auth.ts` et `defindexAuthShape` de `defindex/auth.ts` recopiés avec une
/// table vault → SAC fixe), avec `@stellar/stellar-sdk` 17.0.1. Les cas sont ceux de `auth-tree.test.ts`, plus un swap à
/// deux sauts (XLM → USDC → CETES) dont l'arbre a été confirmé par simulation sur testnet le 2026-10-14.
struct AuthShapeTests {
    private let account = "CB3NR2OIEHWKYSS2ZBTFDTZVSQCNJQNHOSJMQZU2N5KSWE3TLFWYVLGP"
    private let pocket = "CDGWNZPBHLWML4Z4SFSFLO2NRYV6566CFRM2E5ZRZE74AIXO6FYCS437"
    private let vault = "CCLV4H7WTLJQ7ATLHBBQV2WW3OINF3FOY5XZ7VPHZO7NH3D2ZS4GFSF6"
    private let chimpRouter = "CAOL3K7VQTDZELQMKTAJB3WUQGL5JLXJKZ2Y44F77NH4CZNLW5I755XI"
    private let xlm = "CDLZFC3SYJYDZT7K67VZ75HPJVIEUVNIXF47ZG2FB2RMQQVU2HHGCYSC"
    private let soroswapRouter = "CCJUD55AG6W5HAI5LRVNKAE5WDP5XGZBUDS5WNTIVDU7O264UZZE7BRD"
    private let pair = "CCBX3NZTCQLQFSPG7HBOKL4P2RVPOPVFHDNRTOSCCJWBTPL2GHEH7RQS"
    private let usdc = "CBIELTK6YBZJU5UP2WWQEUCYKLPU6AUNZ2BQ4WWFEIE3USCIHMXQDAMA"
    private let cetes = "CC72F57YTPX76HAA64JQOEGHQAPSADQWSY5DWVBR66JINPFDLNCQYHIC"

    private var defindex: DeFindexAuthShape { DeFindexAuthShape(underlying: [vault: xlm]) }
    private var soroswap: SoroswapAuthShape { SoroswapAuthShape(router: soroswapRouter, pair: pair) }

    // MARK: Appels de test (mêmes constructeurs que `auth-tree.test.ts`)

    private func deposit(_ from: String, _ units: Int128) throws -> ContractCall {
        ContractCall(contract: vault, function: "deposit", arguments: [
            .vec([ContractArgument.i128(units)]), .vec([ContractArgument.i128(units)]), try ContractArgument.address(from), .bool(true),
        ])
    }

    private func withdraw(_ from: String, _ shares: Int128, _ min: Int128) throws -> ContractCall {
        ContractCall(contract: vault, function: "withdraw", arguments: [
            ContractArgument.i128(shares), .vec([ContractArgument.i128(min)]), try ContractArgument.address(from),
        ])
    }

    private func swap(_ from: String, _ amountIn: Int128, path: [String]? = nil) throws -> ContractCall {
        ContractCall(contract: soroswapRouter, function: "swap_exact_tokens_for_tokens", arguments: [
            ContractArgument.i128(amountIn), ContractArgument.i128(1),
            .vec(try (path ?? [xlm, usdc]).map { try ContractArgument.address($0) }), try ContractArgument.address(from), .u64(0),
        ])
    }

    private func add(_ from: String, _ a: Int128, _ b: Int128) throws -> ContractCall {
        ContractCall(contract: soroswapRouter, function: "add_liquidity", arguments: [
            try ContractArgument.address(xlm), try ContractArgument.address(usdc),
            ContractArgument.i128(a), ContractArgument.i128(b), ContractArgument.i128(a), ContractArgument.i128(b),
            try ContractArgument.address(from), .u64(0),
        ])
    }

    private func remove(_ from: String, _ lp: Int128) throws -> ContractCall {
        ContractCall(contract: soroswapRouter, function: "remove_liquidity", arguments: [
            try ContractArgument.address(xlm), try ContractArgument.address(usdc), ContractArgument.i128(lp),
            ContractArgument.i128(1), ContractArgument.i128(1), try ContractArgument.address(from), .u64(0),
        ])
    }

    // MARK: declaredInvocations

    @Test("Dépôt dans un vault : le déposant signe deposit, avec un seul sous-appel transfer(déposant → vault, montant)")
    func vaultDeposit() throws {
        let declared = try DeclaredInvocations.build(root: try deposit(account, 1_000_000), authorizers: [.account(account)], shape: defindex)
        #expect(declared.count == 1)
        #expect(declared[0].authorizer == .account(account))
        #expect(try base64(declared[0].invocation) == "AAAAAAAAAAGXXh/2mtMPgms4Qwrq1tuQ0uyux2+f1efLvtPsesy4YgAAAAdkZXBvc2l0AAAAAAQAAAAQAAAAAQAAAAEAAAAKAAAAAAAAAAAAAAAAAA9CQAAAABAAAAABAAAAAQAAAAoAAAAAAAAAAAAAAAAAD0JAAAAAEgAAAAF22OnIIeysSlrIZlHPNZQE1MGndJLIZppvVSsTc1ltigAAAAAAAAABAAAAAQAAAAAAAAAB15KLcsJwPM/q9+uf9O9NUEpVqLl5/JtFDqLIQrTRzmEAAAAIdHJhbnNmZXIAAAADAAAAEgAAAAF22OnIIeysSlrIZlHPNZQE1MGndJLIZppvVSsTc1ltigAAABIAAAABl14f9prTD4JrOEMK6tbbkNLsrsdvn9Xny77T7HrMuGIAAAAKAAAAAAAAAAAAAAAAAA9CQAAAAAA=")
    }

    @Test("Retrait d'un vault : rien n'est pris au déposant (aucun sous-appel)")
    func vaultWithdraw() throws {
        let declared = try DeclaredInvocations.build(root: try withdraw(account, 20475, 0), authorizers: [.account(account)], shape: defindex)
        #expect(try base64(declared[0].invocation) == "AAAAAAAAAAGXXh/2mtMPgms4Qwrq1tuQ0uyux2+f1efLvtPsesy4YgAAAAh3aXRoZHJhdwAAAAMAAAAKAAAAAAAAAAAAAAAAAABP+wAAABAAAAABAAAAAQAAAAoAAAAAAAAAAAAAAAAAAAAAAAAAEgAAAAF22OnIIeysSlrIZlHPNZQE1MGndJLIZppvVSsTc1ltigAAAAA=")
        #expect(declared[0].invocation.subInvocations.isEmpty)
    }

    @Test("Lot du router : l'appelant signe batch avec chaque jambe à plat, le cosignataire sa propre jambe avec la prise")
    func vaultMoveBatch() throws {
        let floor: Int128 = 33_804_064
        let legs = [try withdraw(account, 20475, floor), try TokenShape.transfer(token: xlm, from: account, to: pocket, units: floor), try deposit(pocket, floor)]
        #expect(try base64(try RouterBatch.encode(legs)) == "AAAAEAAAAAEAAAADAAAAEQAAAAEAAAADAAAADwAAAARhcmdzAAAAEAAAAAEAAAADAAAACgAAAAAAAAAAAAAAAAAAT/sAAAAQAAAAAQAAAAEAAAAKAAAAAAAAAAAAAAAAAgPPIAAAABIAAAABdtjpyCHsrEpayGZRzzWUBNTBp3SSyGaab1UrE3NZbYoAAAAPAAAACGNvbnRyYWN0AAAAEgAAAAGXXh/2mtMPgms4Qwrq1tuQ0uyux2+f1efLvtPsesy4YgAAAA8AAAAGbWV0aG9kAAAAAAAPAAAACHdpdGhkcmF3AAAAEQAAAAEAAAADAAAADwAAAARhcmdzAAAAEAAAAAEAAAADAAAAEgAAAAF22OnIIeysSlrIZlHPNZQE1MGndJLIZppvVSsTc1ltigAAABIAAAABzWbl4TrsxfM8kWRVu02OK+77wixZoncxyT/AIu7xcCkAAAAKAAAAAAAAAAAAAAAAAgPPIAAAAA8AAAAIY29udHJhY3QAAAASAAAAAdeSi3LCcDzP6vfrn/TvTVBKVai5efybRQ6iyEK00c5hAAAADwAAAAZtZXRob2QAAAAAAA8AAAAIdHJhbnNmZXIAAAARAAAAAQAAAAMAAAAPAAAABGFyZ3MAAAAQAAAAAQAAAAQAAAAQAAAAAQAAAAEAAAAKAAAAAAAAAAAAAAAAAgPPIAAAABAAAAABAAAAAQAAAAoAAAAAAAAAAAAAAAACA88gAAAAEgAAAAHNZuXhOuzF8zyRZFW7TY4r7vvCLFmidzHJP8Ai7vFwKQAAAAAAAAABAAAADwAAAAhjb250cmFjdAAAABIAAAABl14f9prTD4JrOEMK6tbbkNLsrsdvn9Xny77T7HrMuGIAAAAPAAAABm1ldGhvZAAAAAAADwAAAAdkZXBvc2l0AA==")
        let root = try RouterBatch.call(router: chimpRouter, caller: account, legs: legs)
        let declared = try DeclaredInvocations.build(root: root, legs: legs, authorizers: [.account(account), .pocket(pocket)], shape: defindex)
        #expect(declared.map(\.authorizer) == [.account(account), .pocket(pocket)])
        #expect(try declared.map { try base64($0.invocation) } == ["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"])
    }

    @Test("Refus d'inventer un arbre pour un appel qu'aucune forme ne revendique")
    func refusesUnclaimedCall() throws {
        let unknown = ContractCall(contract: chimpRouter, function: "frobnicate", arguments: [try ContractArgument.address(pocket)])
        #expect(throws: DeclaredInvocations.DeclarationError.undeclared(signer: pocket, function: "frobnicate", contract: chimpRouter)) {
            try DeclaredInvocations.build(root: unknown, authorizers: [.pocket(pocket)], shape: defindex)
        }
        let error = DeclaredInvocations.DeclarationError.undeclared(signer: pocket, function: "frobnicate", contract: chimpRouter)
        #expect(error.errorDescription == "Cannot say what CDGWNZPB… signs for in frobnicate on CAOL3K7V… — this protocol has not declared it")
    }

    @Test("Refus d'un cosignataire qui ne signe rien, d'un appel simple à deux autorisateurs, d'un appel sans autorisateur")
    func refusesBadAuthorizers() throws {
        let legs = [try withdraw(account, 1, 0)]
        let root = try RouterBatch.call(router: chimpRouter, caller: account, legs: legs)
        #expect(throws: DeclaredInvocations.DeclarationError.cosignsNothing(pocket)) {
            try DeclaredInvocations.build(root: root, legs: legs, authorizers: [.account(account), .pocket(pocket)], shape: defindex)
        }
        #expect(DeclaredInvocations.DeclarationError.cosignsNothing(pocket).errorDescription == "CDGWNZPB… cosigns nothing in this batch")
        #expect(throws: DeclaredInvocations.DeclarationError.singleCallHasOneAuthorizer) {
            try DeclaredInvocations.build(root: try deposit(account, 1), authorizers: [.account(account), .pocket(pocket)], shape: defindex)
        }
        #expect(throws: DeclaredInvocations.DeclarationError.noAuthorizer) {
            try DeclaredInvocations.build(root: try deposit(account, 1), authorizers: [], shape: defindex)
        }
    }

    @Test("Le signataire déclaré doit être l'autorisateur : un dépôt au nom d'un autre est refusé")
    func refusesForeignSigner() throws {
        #expect(throws: DeclaredInvocations.DeclarationError.self) {
            try DeclaredInvocations.build(root: try deposit(account, 1), authorizers: [.pocket(pocket)], shape: defindex)
        }
    }

    // MARK: TokenShape

    @Test("TokenShape : le premier argument signe toute écriture SEP-41, et rien n'est pris ; balance n'est pas revendiqué")
    func tokenShape() throws {
        let transfer = try TokenShape.transfer(token: xlm, from: pocket, to: account, units: 5)
        #expect(TokenShape().signer(of: transfer) == pocket)
        #expect(try TokenShape().pulls(of: transfer, from: pocket).isEmpty)
        let balance = ContractCall(contract: xlm, function: "balance", arguments: [try ContractArgument.address(pocket)])
        #expect(TokenShape().signer(of: balance) == nil)
    }

    @Test("Composition : derrière la forme du protocole ; une prise n'est jamais pour un autre que le signataire")
    func composedShape() throws {
        let shape = ComposedShape(defindex, TokenShape())
        #expect(shape.signer(of: try deposit(pocket, 1)) == pocket)
        #expect(shape.signer(of: try TokenShape.transfer(token: xlm, from: pocket, to: account, units: 1)) == pocket)
        #expect(try shape.pulls(of: try deposit(pocket, 1), from: account).isEmpty)
    }

    // MARK: Soroswap

    @Test("Soroswap, swap : prend amount_in de path[0] vers la paire (arbre identique au terminal)")
    func soroswapSwap() throws {
        let call = try swap(pocket, 1_000_000)
        #expect(soroswap.signer(of: call) == pocket)
        #expect(try soroswap.pulls(of: call, from: pocket) == [try TokenShape.transfer(token: xlm, from: pocket, to: pair, units: 1_000_000)])
        let declared = try DeclaredInvocations.build(root: call, authorizers: [.pocket(pocket)], shape: soroswap)
        #expect(try base64(declared[0].invocation) == "AAAAAAAAAAGTQfegN63TgR1catUAnbDf25shoOXbNmio6fdr3KZyTwAAABxzd2FwX2V4YWN0X3Rva2Vuc19mb3JfdG9rZW5zAAAABQAAAAoAAAAAAAAAAAAAAAAAD0JAAAAACgAAAAAAAAAAAAAAAAAAAAEAAAAQAAAAAQAAAAIAAAASAAAAAdeSi3LCcDzP6vfrn/TvTVBKVai5efybRQ6iyEK00c5hAAAAEgAAAAFQRc1ewHKado/VrQJQWFLfTwKNzoMOWsUiCbpISDsvAQAAABIAAAABzWbl4TrsxfM8kWRVu02OK+77wixZoncxyT/AIu7xcCkAAAAFAAAAAAAAAAAAAAABAAAAAAAAAAHXkotywnA8z+r365/0701QSlWouXn8m0UOoshCtNHOYQAAAAh0cmFuc2ZlcgAAAAMAAAASAAAAAc1m5eE67MXzPJFkVbtNjivu+8IsWaJ3Mck/wCLu8XApAAAAEgAAAAGDfbczFBcCyeb5wuUvj9Rq9z6lONsZukISbBm9ejHIfwAAAAoAAAAAAAAAAAAAAAAAD0JAAAAAAA==")
    }

    @Test("Soroswap, swap à deux sauts XLM → USDC → CETES : une seule prise, vers la paire du premier saut")
    func soroswapMultiHop() throws {
        let declared = try DeclaredInvocations.build(
            root: try swap(account, 10_000_000, path: [xlm, usdc, cetes]), authorizers: [.account(account)], shape: soroswap
        )
        #expect(try base64(declared[0].invocation) == "AAAAAAAAAAGTQfegN63TgR1catUAnbDf25shoOXbNmio6fdr3KZyTwAAABxzd2FwX2V4YWN0X3Rva2Vuc19mb3JfdG9rZW5zAAAABQAAAAoAAAAAAAAAAAAAAAAAmJaAAAAACgAAAAAAAAAAAAAAAAAAAAEAAAAQAAAAAQAAAAMAAAASAAAAAdeSi3LCcDzP6vfrn/TvTVBKVai5efybRQ6iyEK00c5hAAAAEgAAAAFQRc1ewHKado/VrQJQWFLfTwKNzoMOWsUiCbpISDsvAQAAABIAAAABv6L3+Jvv/xwA9xMHEMeAHyAOFpY6O1Qx95KGvKNbRQwAAAASAAAAAXbY6cgh7KxKWshmUc81lATUwad0kshmmm9VKxNzWW2KAAAABQAAAAAAAAAAAAAAAQAAAAAAAAAB15KLcsJwPM/q9+uf9O9NUEpVqLl5/JtFDqLIQrTRzmEAAAAIdHJhbnNmZXIAAAADAAAAEgAAAAF22OnIIeysSlrIZlHPNZQE1MGndJLIZppvVSsTc1ltigAAABIAAAABg323MxQXAsnm+cLlL4/Uavc+pTjbGbpCEmwZvXoxyH8AAAAKAAAAAAAAAAAAAAAAAJiWgAAAAAA=")
    }

    @Test("Soroswap, ajout de liquidité : les deux jambes aux montants désirés ; retrait : le jeton LP, qui est la paire")
    func soroswapLiquidity() throws {
        #expect(try base64(try DeclaredInvocations.build(root: try add(pocket, 1_000_000, 2_500), authorizers: [.pocket(pocket)], shape: soroswap)[0].invocation) == "AAAAAAAAAAGTQfegN63TgR1catUAnbDf25shoOXbNmio6fdr3KZyTwAAAA1hZGRfbGlxdWlkaXR5AAAAAAAACAAAABIAAAAB15KLcsJwPM/q9+uf9O9NUEpVqLl5/JtFDqLIQrTRzmEAAAASAAAAAVBFzV7Acpp2j9WtAlBYUt9PAo3Ogw5axSIJukhIOy8BAAAACgAAAAAAAAAAAAAAAAAPQkAAAAAKAAAAAAAAAAAAAAAAAAAJxAAAAAoAAAAAAAAAAAAAAAAAD0JAAAAACgAAAAAAAAAAAAAAAAAACcQAAAASAAAAAc1m5eE67MXzPJFkVbtNjivu+8IsWaJ3Mck/wCLu8XApAAAABQAAAAAAAAAAAAAAAgAAAAAAAAAB15KLcsJwPM/q9+uf9O9NUEpVqLl5/JtFDqLIQrTRzmEAAAAIdHJhbnNmZXIAAAADAAAAEgAAAAHNZuXhOuzF8zyRZFW7TY4r7vvCLFmidzHJP8Ai7vFwKQAAABIAAAABg323MxQXAsnm+cLlL4/Uavc+pTjbGbpCEmwZvXoxyH8AAAAKAAAAAAAAAAAAAAAAAA9CQAAAAAAAAAAAAAAAAVBFzV7Acpp2j9WtAlBYUt9PAo3Ogw5axSIJukhIOy8BAAAACHRyYW5zZmVyAAAAAwAAABIAAAABzWbl4TrsxfM8kWRVu02OK+77wixZoncxyT/AIu7xcCkAAAASAAAAAYN9tzMUFwLJ5vnC5S+P1Gr3PqU42xm6QhJsGb16Mch/AAAACgAAAAAAAAAAAAAAAAAACcQAAAAA")
        #expect(try base64(try DeclaredInvocations.build(root: try remove(pocket, 4_242), authorizers: [.pocket(pocket)], shape: soroswap)[0].invocation) == "AAAAAAAAAAGTQfegN63TgR1catUAnbDf25shoOXbNmio6fdr3KZyTwAAABByZW1vdmVfbGlxdWlkaXR5AAAABwAAABIAAAAB15KLcsJwPM/q9+uf9O9NUEpVqLl5/JtFDqLIQrTRzmEAAAASAAAAAVBFzV7Acpp2j9WtAlBYUt9PAo3Ogw5axSIJukhIOy8BAAAACgAAAAAAAAAAAAAAAAAAEJIAAAAKAAAAAAAAAAAAAAAAAAAAAQAAAAoAAAAAAAAAAAAAAAAAAAABAAAAEgAAAAHNZuXhOuzF8zyRZFW7TY4r7vvCLFmidzHJP8Ai7vFwKQAAAAUAAAAAAAAAAAAAAAEAAAAAAAAAAYN9tzMUFwLJ5vnC5S+P1Gr3PqU42xm6QhJsGb16Mch/AAAACHRyYW5zZmVyAAAAAwAAABIAAAABzWbl4TrsxfM8kWRVu02OK+77wixZoncxyT/AIu7xcCkAAAASAAAAAYN9tzMUFwLJ5vnC5S+P1Gr3PqU42xm6QhJsGb16Mch/AAAACgAAAAAAAAAAAAAAAAAAEJIAAAAA")
    }

    @Test("Soroswap : rien n'est revendiqué sur un autre router, rien n'est pris à qui n'est pas `to`")
    func soroswapForeign() throws {
        let other = ContractCall(contract: chimpRouter, function: "swap_exact_tokens_for_tokens", arguments: try swap(pocket, 1).arguments)
        #expect(soroswap.signer(of: other) == nil)
        #expect(try soroswap.pulls(of: try swap(pocket, 1), from: account).isEmpty)
    }

    @Test("Soroswap, déplacement d'une position LP en lot : la source signe le lot (sa prise sous sa jambe), la destination son ajout")
    func soroswapMoveBatch() throws {
        let legs = [
            try remove(pocket, 4_242),
            try TokenShape.transfer(token: xlm, from: pocket, to: account, units: 900),
            try TokenShape.transfer(token: usdc, from: pocket, to: account, units: 3),
            try add(account, 900, 3),
        ]
        let root = try RouterBatch.call(router: chimpRouter, caller: pocket, legs: legs)
        let declared = try DeclaredInvocations.build(root: root, legs: legs, authorizers: [.pocket(pocket), .account(account)], shape: soroswap)
        #expect(declared.map(\.authorizer) == [.pocket(pocket), .account(account)])
        #expect(try declared.map { try base64($0.invocation) } == ["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"])
    }

    @Test("Montant mal formé dans un swap : erreur, jamais un arbre au montant deviné")
    func soroswapMalformed() throws {
        var arguments = try swap(pocket, 1).arguments
        arguments[0] = .u32(1)
        let call = ContractCall(contract: soroswapRouter, function: "swap_exact_tokens_for_tokens", arguments: arguments)
        #expect(throws: ContractArgument.ArgumentError.self) { try soroswap.pulls(of: call, from: pocket) }
    }

    // MARK: Montants

    @Test("i128 : aller-retour exact, y compris au-delà de 64 bits et en négatif")
    func int128RoundTrip() {
        for value: Int128 in [0, 1, 10_000_000, Int128(UInt64.max) + 1, -1, Int128.max, Int128.min] {
            #expect(ContractArgument.int128(ContractArgument.i128(value)) == value)
        }
        for value: UInt128 in [0, 1, UInt128(UInt64.max) + 1, UInt128.max] {
            #expect(ContractArgument.uint128(ContractArgument.u128(value)) == value)
        }
    }

    private func base64<T: XDREncodable>(_ value: T) throws -> String {
        Data(try XDREncoder.encode(value)).base64EncodedString()
    }
}
