import Foundation
import stellarsdk
import Testing
@testable import ChimpDAO

/// Tranche 2, phase 1, étape 4 : préparation de la signature d'un appel d'intégration (portage de `earnSignedCall`).
/// Vecteur : l'entrée déclarée par une Pocket pour un swap Soroswap, construite comme `build` de `preSignedAuthEntries`
/// (`chip-auth.ts`) avec un nonce fixe, et son digest V1 (`authPayloadHash`), avec `@stellar/stellar-sdk` 17.0.1.
/// Principe 9 : refus d'une autorisation expirée ou presque, nonce neuf à chaque préparation.
struct IntegrationSigningTests {
    private let passphrase = ChimpNetworkConfig.testnet.passphrase
    private let account = "CB3NR2OIEHWKYSS2ZBTFDTZVSQCNJQNHOSJMQZU2N5KSWE3TLFWYVLGP"
    private let pocket = "CDGWNZPBHLWML4Z4SFSFLO2NRYV6566CFRM2E5ZRZE74AIXO6FYCS437"
    private let soroswapRouter = "CCJUD55AG6W5HAI5LRVNKAE5WDP5XGZBUDS5WNTIVDU7O264UZZE7BRD"
    private let chimpRouter = "CAOL3K7VQTDZELQMKTAJB3WUQGL5JLXJKZ2Y44F77NH4CZNLW5I755XI"
    private let pair = "CCBX3NZTCQLQFSPG7HBOKL4P2RVPOPVFHDNRTOSCCJWBTPL2GHEH7RQS"
    private let xlm = "CDLZFC3SYJYDZT7K67VZ75HPJVIEUVNIXF47ZG2FB2RMQQVU2HHGCYSC"
    private let usdc = "CBIELTK6YBZJU5UP2WWQEUCYKLPU6AUNZ2BQ4WWFEIE3USCIHMXQDAMA"
    private let vault = "CCLV4H7WTLJQ7ATLHBBQV2WW3OINF3FOY5XZ7VPHZO7NH3D2ZS4GFSF6"
    private let card = MockChipReader.secp256k1Key

    /// Le swap de `auth-tree.test.ts` (1 000 000 de XLM, minimum 1, échéance 0), autorisé par la Pocket.
    private func pocketSwap() throws -> ContractCall {
        try SoroswapCalls.swap(router: soroswapRouter, amountIn: 1_000_000, minimumOut: 1, path: [xlm, usdc], to: pocket, deadline: 0)
    }

    private var shape: SoroswapAuthShape { SoroswapAuthShape(router: soroswapRouter, pair: pair) }

    private func prepared(nonce: Int64 = 1_234_567_890_123_456_789) throws -> PreparedIntegrationCall {
        let call = try pocketSwap()
        let invocation = try IntegrationCallClient.declaredInvocation(call: call, authorizer: .pocket(pocket), shape: shape)
        return try IntegrationCallClient.declaredPocketCall(
            call, pocket: pocket, invocation: invocation, passphrase: passphrase, currentLedger: 1000, nonce: nonce, acceptedKeys: [card]
        )
    }

    @Test("Pocket, swap : entrée déclarée et digest identiques au terminal, expiration = ledger + 120, seule sa carte signe")
    func pocketSwapEntry() throws {
        let prepared = try prepared()
        #expect(try base64(prepared.entry) == "AAAAAQAAAAHNZuXhOuzF8zyRZFW7TY4r7vvCLFmidzHJP8Ai7vFwKREiEPR96YEVAAAEYAAAAAEAAAAAAAAAAZNB96A3rdOBHVxq1QCdsN/bmyGg5ds2aKjp92vcpnJPAAAAHHN3YXBfZXhhY3RfdG9rZW5zX2Zvcl90b2tlbnMAAAAFAAAACgAAAAAAAAAAAAAAAAAPQkAAAAAKAAAAAAAAAAAAAAAAAAAAAQAAABAAAAABAAAAAgAAABIAAAAB15KLcsJwPM/q9+uf9O9NUEpVqLl5/JtFDqLIQrTRzmEAAAASAAAAAVBFzV7Acpp2j9WtAlBYUt9PAo3Ogw5axSIJukhIOy8BAAAAEgAAAAHNZuXhOuzF8zyRZFW7TY4r7vvCLFmidzHJP8Ai7vFwKQAAAAUAAAAAAAAAAAAAAAEAAAAAAAAAAdeSi3LCcDzP6vfrn/TvTVBKVai5efybRQ6iyEK00c5hAAAACHRyYW5zZmVyAAAAAwAAABIAAAABzWbl4TrsxfM8kWRVu02OK+77wixZoncxyT/AIu7xcCkAAAASAAAAAYN9tzMUFwLJ5vnC5S+P1Gr3PqU42xm6QhJsGb16Mch/AAAACgAAAAAAAAAAAAAAAAAPQkAAAAAA")
        #expect(prepared.digest.hexString == "0e3176cd23b3e619a3ad7cd9ed4a2606c832457b68916ede9596443c17a2c89a")
        #expect(prepared.expirationLedger == 1120)
        #expect(prepared.preparedAtLedger == 1000)
        #expect(prepared.acceptedKeys == [card])
        #expect(prepared.nonce == 1_234_567_890_123_456_789)
    }

    @Test("Enveloppe et code de refus : ChipAuth et #201 pour une Pocket, AccountAuth et #301 pour le Main account")
    func envelopes() throws {
        let chipAuth = try ChipAuthEncoding.chipAuthSecp256k1(signature: Data(repeating: 0x11, count: 64), recoveryID: 1)
        let pocketCall = try prepared()
        #expect(try base64(pocketCall.envelope(chipAuth, card: card)) == base64(chipAuth))
        #expect(pocketCall.rejectionCodes == RecoveryIDSearch.RejectionCode.pocket)
        let accountCall = PreparedIntegrationCall(
            authorizer: .account(account), call: pocketCall.call, entry: pocketCall.entry, digest: pocketCall.digest,
            expirationLedger: 1120, preparedAtLedger: 1000, acceptedKeys: [card]
        )
        #expect(try base64(accountCall.envelope(chipAuth, card: card)) == base64(ChipAuthEncoding.accountAuth(publicKey: card, chipAuth: chipAuth)))
        #expect(accountCall.rejectionCodes == RecoveryIDSearch.RejectionCode.account)
    }

    @Test("Nonce neuf à chaque préparation : deux préparations du même swap n'ont ni le même nonce ni le même digest")
    func freshNonce() throws {
        let first = try prepared(nonce: try SorobanAuth.randomNonce())
        let second = try prepared(nonce: try SorobanAuth.randomNonce())
        #expect(first.nonce != second.nonce)
        #expect(first.digest != second.digest)
        // Une signature de la carte vaut pour un seul digest, donc pour un seul nonce : la rejouer sur une autre
        // préparation ne correspond à rien, et rejouer la même entrée est refusé par Stellar (nonce déjà consommé).
        #expect(try prepared(nonce: 7).digest == prepared(nonce: 7).digest)
    }

    @Test("Autorisation expirée ou à moins de 20 ledgers de l'expiration : refusée avant le tap")
    func expiredAuthorization() throws {
        try IntegrationCallClient.checkFresh(expirationLedger: 1120, currentLedger: 1100)
        for current: UInt32 in [1101, 1119, 1120, 1121, 5000] {
            #expect(throws: IntegrationCallClient.SigningError.authorizationExpiring(expirationLedger: 1120, currentLedger: current)) {
                try IntegrationCallClient.checkFresh(expirationLedger: 1120, currentLedger: current)
            }
        }
    }

    @Test("Appel que la forme ne revendique pas : refusé avant tout réseau")
    func undeclaredCallRefused() throws {
        let deposit = try DeFindexCalls.deposit(vault: vault, from: pocket, units: 1)
        #expect(throws: DeclaredInvocations.DeclarationError.self) {
            try IntegrationCallClient.declaredInvocation(call: deposit, authorizer: .pocket(pocket), shape: shape)
        }
        // Le bon appel, mais au nom d'un autre autorisateur : refusé aussi.
        #expect(throws: DeclaredInvocations.DeclarationError.self) {
            try IntegrationCallClient.declaredInvocation(call: try pocketSwap(), authorizer: .account(account), shape: shape)
        }
    }

    @Test("Swap puis dépôt dans un lot du router, un seul autorisateur : un arbre, chaque jambe avec sa prise")
    func swapThenDepositBatch() throws {
        let legs = [
            try SoroswapCalls.swap(router: soroswapRouter, amountIn: 10_000_000, minimumOut: 1_000_000, path: [xlm, usdc], to: pocket, deadline: 0),
            try DeFindexCalls.deposit(vault: vault, from: pocket, units: 5_000_000),
        ]
        let root = try RouterBatch.call(router: chimpRouter, caller: pocket, legs: legs)
        let invocation = try IntegrationCallClient.declaredInvocation(
            call: root, legs: legs, authorizer: .pocket(pocket), shape: ComposedShape(shape, DeFindexAuthShape(underlying: [vault: xlm]))
        )
        #expect(invocation.subInvocations.count == 2)
        #expect(try invocation.subInvocations[0].subInvocations.map { try base64($0) }
                == [try base64(try TokenShape.transfer(token: xlm, from: pocket, to: pair, units: 10_000_000).invocation())])
        #expect(try invocation.subInvocations[1].subInvocations.map { try base64($0) }
                == [try base64(try TokenShape.transfer(token: xlm, from: pocket, to: vault, units: 5_000_000).invocation())])
    }

    private func base64<T: XDREncodable>(_ value: T) throws -> String {
        Data(try XDREncoder.encode(value)).base64EncodedString()
    }
}
