import CryptoKit
import Foundation
import stellarsdk
import Testing
@testable import ChimpDAO

/// Onboarding, étape 1 : briques de `Core/` (autorisations Soroban, `set_owner`, déploiement du Main account,
/// SAC, résolution « qui es-tu ? », preuve de possession, serveur de frais).
/// Valeurs de référence calculées par les fonctions du terminal (`chip-auth.ts` : `authPayloadHash`, `restamp`,
/// `preSignedAuthEntries` ; `provisioning.ts` : `deployAccount`, `predictPocket` ; `sac.ts`), recopiées telles quelles
/// et exécutées avec `@stellar/stellar-sdk` 17.0.1 (version du `bun.lock` du terminal).
struct OnboardingCoreTests {
    private let k1Key = MockChipReader.secp256k1Key
    private let r1Key = MockChipReader.p256Key
    private let config = ChimpNetworkConfig.testnet
    private let passphrase = ChimpNetworkConfig.testnet.passphrase
    private let signature = Data(hex: String(repeating: "11", count: 32) + String(repeating: "22", count: 32))!

    /// Valeurs du terminal.
    private let pocketK1 = "CALWOI2Z6NZ5ULEYRXZZTN7M35CMWMS6YJXTQTVPIOQXKEKWKTVELEMX"
    private let accountK1 = "CDU45A6K2WTMLRDUEQ7SXGOUICJVRWSLZCYPLWB7W6FVQLD7LPNRVVFR"
    private let accountR1 = "CBNQ52VRIYPR5LSFTMVJOIGJYM4DKVUWUJUBNFX74IEZPYOUJFXQ26TA"
    private let positiveNonce: Int64 = 1_234_567_890_123_456_789

    // MARK: Autorisations Soroban (V1 et V2)

    @Test("Entrée set_owner déclarée (V1, signature void) : mêmes octets que preSignedAuthEntries, nonce positif et négatif")
    func declaredEntryBytes() throws {
        #expect(try base64(setOwnerEntry(nonce: positiveNonce))
            == "AAAAAQAAAAEXZyNZ83PaLJiN85m37N9EyzJewm84Tq9DoXURVlTqRREiEPR96YEVAAAD6AAAAAEAAAAAAAAAARdnI1nzc9osmI3zmbfs30TLMl7CbzhOr0OhdRFWVOpFAAAACXNldF9vd25lcgAAAAAAAAEAAAASAAAAAenOg8rVpsXEdCQ/K5nUQJNY2kvIsPXYP7eLWCx/W9saAAAAAA==")
        #expect(try base64(setOwnerEntry(nonce: -42))
            == "AAAAAQAAAAEXZyNZ83PaLJiN85m37N9EyzJewm84Tq9DoXURVlTqRf/////////WAAAD6AAAAAEAAAAAAAAAARdnI1nzc9osmI3zmbfs30TLMl7CbzhOr0OhdRFWVOpFAAAACXNldF9vd25lcgAAAAAAAAEAAAASAAAAAenOg8rVpsXEdCQ/K5nUQJNY2kvIsPXYP7eLWCx/W9saAAAAAA==")
    }

    @Test("Digest V1 (HashIdPreimageSorobanAuthorization) identique à authPayloadHash")
    func payloadHashV1() throws {
        #expect(try SorobanAuth.payloadHash(setOwnerEntry(nonce: positiveNonce), passphrase: passphrase, expirationLedger: 1000).hexString
            == "b0764b7ba9d659562488ee5efcf4c8e55c8c7e1a3cdfa5cb7756f982a2a1ef31")
        #expect(try SorobanAuth.payloadHash(setOwnerEntry(nonce: -42), passphrase: passphrase, expirationLedger: 1000).hexString
            == "9a59a83d900325d9a668f69b211db0b628d067e7477fed92e565958982f9c793")
    }

    @Test("Règle 4 : une entrée V2 (Protocol 28) est hashée en V2 (…WithAddress), jamais convertie")
    func payloadHashV2() throws {
        let v2 = try asV2(setOwnerEntry(nonce: positiveNonce))
        #expect(try base64(v2)
            == "AAAAAgAAAAEXZyNZ83PaLJiN85m37N9EyzJewm84Tq9DoXURVlTqRREiEPR96YEVAAAD6AAAAAEAAAAAAAAAARdnI1nzc9osmI3zmbfs30TLMl7CbzhOr0OhdRFWVOpFAAAACXNldF9vd25lcgAAAAAAAAEAAAASAAAAAenOg8rVpsXEdCQ/K5nUQJNY2kvIsPXYP7eLWCx/W9saAAAAAA==")
        #expect(try SorobanAuth.payloadHash(v2, passphrase: passphrase, expirationLedger: 1000).hexString
            == "bab27f8da1fdaecfcb05db0512c4830108fd91b054006fafbc99b2d3610d9a75")
        #expect(try SorobanAuth.payloadHash(v2, passphrase: passphrase, expirationLedger: 1120).hexString
            == "19886a85ac7fb05678d3034964df0c899cc252a806ca12f0d70e04a3b725740a")
        #expect(try SorobanAuth.payloadHash(asV2(setOwnerEntry(nonce: -42)), passphrase: passphrase, expirationLedger: 1000).hexString
            == "a6455cbf8f12fefe90beecbcd6bc5f7c95419a1676d8fbcec1bc91c8064c307d")
        #expect(try SorobanAuth.payloadHash(asV2(setOwnerEntry(nonce: -42)), passphrase: passphrase, expirationLedger: 1120).hexString
            == "2c8ba05c296496c5999e1a10155d4109f184a90a0a2f8c81db4a0e2d14adbedf")
    }

    @Test("restamp : signature et expiration remplacées dans la variante reçue (V1 reste V1, V2 reste V2)")
    func restampKeepsVariant() throws {
        let auth = try ChipAuthEncoding.chipAuthSecp256k1(signature: signature, recoveryID: 1)
        let v1 = try SorobanAuth.restamped(setOwnerEntry(nonce: positiveNonce), signature: auth)
        #expect(try base64(v1)
            == "AAAAAQAAAAEXZyNZ83PaLJiN85m37N9EyzJewm84Tq9DoXURVlTqRREiEPR96YEVAAAD6AAAABAAAAABAAAAAgAAAA8AAAAJU2VjcDI1NmsxAAAAAAAAEQAAAAEAAAACAAAADwAAAAtyZWNvdmVyeV9pZAAAAAADAAAAAQAAAA8AAAAJc2lnbmF0dXJlAAAAAAAADQAAAEARERERERERERERERERERERERERERERERERERERERERESIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiAAAAAAAAAAEXZyNZ83PaLJiN85m37N9EyzJewm84Tq9DoXURVlTqRQAAAAlzZXRfb3duZXIAAAAAAAABAAAAEgAAAAHpzoPK1abFxHQkPyuZ1ECTWNpLyLD12D+3i1gsf1vbGgAAAAA=")
        let v2 = try SorobanAuth.restamped(asV2(setOwnerEntry(nonce: positiveNonce)), expirationLedger: 1120, signature: auth)
        #expect(SorobanAuth.isAddressV2(v2))
        #expect(try base64(v2)
            == "AAAAAgAAAAEXZyNZ83PaLJiN85m37N9EyzJewm84Tq9DoXURVlTqRREiEPR96YEVAAAEYAAAABAAAAABAAAAAgAAAA8AAAAJU2VjcDI1NmsxAAAAAAAAEQAAAAEAAAACAAAADwAAAAtyZWNvdmVyeV9pZAAAAAADAAAAAQAAAA8AAAAJc2lnbmF0dXJlAAAAAAAADQAAAEARERERERERERERERERERERERERERERERERERERERERESIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiAAAAAAAAAAEXZyNZ83PaLJiN85m37N9EyzJewm84Tq9DoXURVlTqRQAAAAlzZXRfb3duZXIAAAAAAAABAAAAEgAAAAHpzoPK1abFxHQkPyuZ1ECTWNpLyLD12D+3i1gsf1vbGgAAAAA=")
    }

    @Test("Credentials du compte source ou avec délégués : refusés, jamais signés")
    func nonAddressCredentials() throws {
        let entry = try setOwnerEntry(nonce: 1)
        let source = SorobanAuthorizationEntryXDR(credentials: .sourceAccount, rootInvocation: entry.rootInvocation)
        #expect(throws: SorobanAuth.AuthError.notAddressCredentials("source account")) {
            try SorobanAuth.payloadHash(source, passphrase: passphrase, expirationLedger: 1000)
        }
        #expect(throws: SorobanAuth.AuthError.self) { try SorobanAuth.restamped(source, signature: .void) }
    }

    @Test("Déclaration de set_owner : expiration = ledger actuel + 120, digest = celui du terminal, marge de 20 ledgers")
    func declareSetOwner() throws {
        let declared = try PocketClient.declareSetOwner(
            pocket: pocketK1, newOwner: accountK1, passphrase: passphrase, currentLedger: 880, nonce: positiveNonce
        )
        #expect(declared.expirationLedger == 1000)
        #expect(declared.digest.hexString == "b0764b7ba9d659562488ee5efcf4c8e55c8c7e1a3cdfa5cb7756f982a2a1ef31")
        #expect(!declared.needsRefresh(currentLedger: 880))
        #expect(!declared.needsRefresh(currentLedger: 980))
        #expect(declared.needsRefresh(currentLedger: 981))
        #expect(declared.needsRefresh(currentLedger: 1200))
    }

    @Test("Opération set_owner avec l'entrée signée : mêmes octets que invokeContractFunction du terminal")
    func setOwnerOperation() throws {
        let declared = try PocketClient.declareSetOwner(
            pocket: pocketK1, newOwner: accountK1, passphrase: passphrase, currentLedger: 880, nonce: positiveNonce
        )
        let entry = try declared.signed(with: try ChipAuthEncoding.chipAuthSecp256k1(signature: signature, recoveryID: 1))
        let client = SorobanClient(config: config)
        let source = try Account(accountId: config.feePayer, sequenceNumber: 1234)
        let transaction = try PocketClient(client: client).setOwnerTransaction(source: source, pocket: pocketK1, newOwner: accountK1, signedEntry: entry)
        #expect(try base64(transaction.operations[0].toXDR())
            == "AAAAAAAAABgAAAAAAAAAARdnI1nzc9osmI3zmbfs30TLMl7CbzhOr0OhdRFWVOpFAAAACXNldF9vd25lcgAAAAAAAAEAAAASAAAAAenOg8rVpsXEdCQ/K5nUQJNY2kvIsPXYP7eLWCx/W9saAAAAAQAAAAEAAAABF2cjWfNz2iyYjfOZt+zfRMsyXsJvOE6vQ6F1EVZU6kURIhD0femBFQAAA+gAAAAQAAAAAQAAAAIAAAAPAAAACVNlY3AyNTZrMQAAAAAAABEAAAABAAAAAgAAAA8AAAALcmVjb3ZlcnlfaWQAAAAAAwAAAAEAAAAPAAAACXNpZ25hdHVyZQAAAAAAAA0AAABAEREREREREREREREREREREREREREREREREREREREREREiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIgAAAAAAAAABF2cjWfNz2iyYjfOZt+zfRMsyXsJvOE6vQ6F1EVZU6kUAAAAJc2V0X293bmVyAAAAAAAAAQAAABIAAAAB6c6DytWmxcR0JD8rmdRAk1jaS8iw9dg/t4tYLH9b2xoAAAAA")
        #expect(transaction.sourceAccount.keyPair.accountId == config.feePayer)
    }

    @Test("Nonce aléatoire : 8 octets lus comme getBigInt64(0, false)")
    func nonceDecoding() throws {
        #expect(SorobanAuth.int64(bigEndian: [UInt8](Data(hex: "ffffffffffffffff")!)) == -1)
        #expect(SorobanAuth.int64(bigEndian: [UInt8](Data(hex: "0102030405060708")!)) == 72_623_859_790_382_856)
        #expect(SorobanAuth.int64(bigEndian: [UInt8](Data(hex: "8000000000000000")!)) == Int64.min)
        #expect(try SorobanAuth.randomNonce() != SorobanAuth.randomNonce())
    }

    // MARK: Main account

    @Test("Adresse prévue du Main account (déployeur = payeur de frais, sel = sha256(clé)) : identique à deployAccount")
    func predictedAccount() throws {
        #expect(try ChimpAccountClient.predictedAddress(feePayer: config.feePayer, publicKey: k1Key, network: .testnet) == accountK1)
        #expect(try ChimpAccountClient.predictedAddress(feePayer: config.feePayer, publicKey: r1Key, network: .testnet) == accountR1)
        #expect(try PocketFactoryClient.predictedPocket(factory: config.contracts.factory, publicKey: k1Key, network: .testnet) == pocketK1)
    }

    @Test("Opération de déploiement (createCustomContract + constructeur [Vec[CardSigner]]) : identique au terminal, k1 et r1")
    func deployOperation() throws {
        let k1 = try ChimpAccountClient.deployOperation(wasmHash: config.contracts.accountWasmHash, feePayer: config.feePayer, publicKey: k1Key, curve: .secp256k1)
        #expect(try base64(k1.toXDR())
            == "AAAAAAAAABgAAAADAAAAAAAAAAAAAAAA8k/SxnbfL0fRR4u7oSu/7GQQo935iDuASfi5bUPHlrJQkpt0waBJVLeLS2A16XpeB4paDyjsltVHv+6azoA6wAAAAAAEQnWsG+P9UFki+wxWQ3AzF1P+gI4xmQt+dOvzlWFCcQAAAAEAAAAQAAAAAQAAAAEAAAARAAAAAQAAAAIAAAAPAAAABWN1cnZlAAAAAAAAEAAAAAEAAAABAAAADwAAAAlTZWNwMjU2azEAAAAAAAAPAAAAA2tleQAAAAANAAAAQQR5vmZ++dy7rFWgYpXOhwsHApv82y3OKNlZ8oFbFvgXmEg62ncmo8RlXaT7/A4RCKj9F7RIpoVUGZxH0I/7ENS4AAAAAAAAAA==")
        let r1 = try ChimpAccountClient.deployOperation(wasmHash: config.contracts.accountWasmHash, feePayer: config.feePayer, publicKey: r1Key, curve: .p256)
        #expect(try base64(r1.toXDR())
            == "AAAAAAAAABgAAAADAAAAAAAAAAAAAAAA8k/SxnbfL0fRR4u7oSu/7GQQo935iDuASfi5bUPHlrJpi+pj3ESjRGY/8UKa6hCELfJ7a5ke8lhmssbALNzFvgAAAAAEQnWsG+P9UFki+wxWQ3AzF1P+gI4xmQt+dOvzlWFCcQAAAAEAAAAQAAAAAQAAAAEAAAARAAAAAQAAAAIAAAAPAAAABWN1cnZlAAAAAAAAEAAAAAEAAAABAAAADwAAAAlTZWNwMjU2cjEAAAAAAAAPAAAAA2tleQAAAAANAAAAQQRrF9Hy4SxCR/i85uVjpEDydwN9gS3rM6D0oTlF2JjClk/jQuL+Gn+bjufrSnwPnhYrzjNXazFezsu2QGg3v1H1AAAAAAAAAA==")
    }

    // MARK: SAC

    @Test("Adresse des SAC testnet (XLM natif, USDC) : identique à sacForAsset")
    func sacAddresses() throws {
        #expect(try SACClient.contractID(for: Asset(type: AssetType.ASSET_TYPE_NATIVE)!, network: .testnet)
            == "CDLZFC3SYJYDZT7K67VZ75HPJVIEUVNIXF47ZG2FB2RMQQVU2HHGCYSC")
        let usdc = Asset(type: AssetType.ASSET_TYPE_CREDIT_ALPHANUM4, code: "USDC", issuer: try KeyPair(accountId: config.usdcIssuer))!
        #expect(try SACClient.contractID(for: usdc, network: .testnet) == "CBIELTK6YBZJU5UP2WWQEUCYKLPU6AUNZ2BQ4WWFEIE3USCIHMXQDAMA")
    }

    @Test("Solde i128 → montant exact à 7 décimales, sans Double (y compris valeurs négatives et au-delà de 64 bits)")
    func i128Amounts() {
        #expect(SACClient.amount(fromUnits: SACClient.decimal(Int128PartsXDR(hi: 0, lo: 12_345_678))) == Decimal(string: "1.2345678")!)
        #expect(SACClient.amount(fromUnits: SACClient.decimal(Int128PartsXDR(hi: 0, lo: 0))) == 0)
        #expect(SACClient.decimal(Int128PartsXDR(hi: -1, lo: UInt64.max)) == -1)
        #expect(SACClient.decimal(Int128PartsXDR(hi: 1, lo: 0)) == Decimal(string: "18446744073709551616")!)
    }

    // MARK: Résolution (resolve.test.ts)

    private let accountA = "CAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    private let accountB = "CBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB"

    @Test("signIn sur le premier membre confirmé, même si une autre recherche a échoué")
    func resolutionSignIn() {
        let evidence = CardEvidence(tried: [
            .init(account: accountA, source: .hint, member: false),
            .init(account: accountB, source: .pocket, member: true),
        ])
        #expect(evidence.decide() == .signIn(account: accountB, source: .pocket))
        let withFailure = CardEvidence(tried: [.init(account: accountA, source: .hint, member: true)], failed: true)
        #expect(withFailure.decide() == .signIn(account: accountA, source: .hint))
    }

    @Test("Jamais « orphelin » ni « neuve » ni « enregistrée » quand une recherche a échoué : unknown (re-taper)")
    func resolutionNeverOrphansOnFailure() {
        #expect(CardEvidence(tried: [.init(account: accountA, source: .pocket, member: false)], failed: true).decide()
            == .unknown(detail: "Couldn't check this card"))
        #expect(CardEvidence(failed: true).decide() == .unknown(detail: "Couldn't check this card"))
        #expect(CardEvidence(tried: [.init(account: "CPURSE", source: .pocket, member: false)], failed: true, ownPocket: "CPURSE").decide()
            == .unknown(detail: "Couldn't check this card"))
    }

    @Test("orphan seulement si tous les candidats ont refusé proprement ; newCard si rien ne nomme la carte")
    func resolutionOrphanAndNew() {
        #expect(CardEvidence(tried: [.init(account: accountA, source: .pocket, member: false)]).decide() == .orphan(lastKnown: accountA))
        #expect(CardEvidence().decide() == .newCard)
        #expect(CardEvidence(tried: [.init(account: "CPOCKETSELF", source: .pocket, member: false)]).decide() == .orphan(lastKnown: "CPOCKETSELF"))
    }

    @Test("Pocket qui se possède elle-même : enrolled ; carte qui a perdu son compte : orphan")
    func resolutionEnrolled() {
        #expect(CardEvidence(tried: [.init(account: "CPURSE", source: .pocket, member: false)], ownPocket: "CPURSE").decide() == .enrolled)
        #expect(CardEvidence(tried: [.init(account: "COLDACCOUNT", source: .pocket, member: false)], ownPocket: "CPURSE").decide()
            == .orphan(lastKnown: "COLDACCOUNT"))
    }

    // MARK: recovery_id par simulation

    @Test("Anciens et nouveaux contrats : 201/402, 301/502, 200/101 font essayer le recovery_id suivant ; les autres codes non")
    func renumberedRejectionCodes() async throws {
        let code = { (n: Int) in StellarError.simulationFailed("HostError: Error(Contract, #\(n))") as Error }
        for (codes, known) in [(RecoveryIDSearch.RejectionCode.pocket, [201, 402]), (RecoveryIDSearch.RejectionCode.account, [301, 502]), (RecoveryIDSearch.RejectionCode.nfcNft, [200, 101])] {
            for n in known { #expect(RecoveryIDSearch.isRejectedSignature(code(n), contractCodes: codes), "\(n)") }
        }
        #expect(RecoveryIDSearch.isRejectedSignature(StellarError.simulationFailed(#"["failing with contract error", 402]"#), contractCodes: RecoveryIDSearch.RejectionCode.pocket))
        // Autres codes du nouveau contrat : ce n'est pas un mauvais recovery_id.
        #expect(!RecoveryIDSearch.isRejectedSignature(code(401), contractCodes: RecoveryIDSearch.RejectionCode.pocket), "InvalidChip")
        #expect(!RecoveryIDSearch.isRejectedSignature(code(4020), contractCodes: RecoveryIDSearch.RejectionCode.pocket))
        #expect(!RecoveryIDSearch.isRejectedSignature(code(501), contractCodes: RecoveryIDSearch.RejectionCode.account), "UnknownCard")

        // Une Pocket récente refuse le mauvais recovery_id en #402 : la recherche passe au suivant au lieu de s'arrêter.
        let found = try await RecoveryIDSearch.first(rejectionCodes: RecoveryIDSearch.RejectionCode.pocket) { id -> UInt32 in
            guard id == 1 else { throw code(402) }
            return id
        }
        #expect(found.recoveryID == 1)
    }

    @Test("Dernière carte : #303 sur l'ancien compte, #504 LastSigner sur le récent ; un autre code n'est pas ce refus")
    func lastSignerCodes() {
        #expect(CardMembershipClient.isLastCardRefusal(.simulationFailed("HostError: Error(Contract, #303)")))
        #expect(CardMembershipClient.isLastCardRefusal(.simulationFailed("HostError: Error(Contract, #504)")))
        #expect(!CardMembershipClient.isLastCardRefusal(.simulationFailed("HostError: Error(Contract, #503)")))
    }

    @Test("Refus reconnus par contrat : #201 pour la Pocket, #200 pour nfc-nft, jamais l'un pour l'autre ; panne réseau jamais")
    func rejectionCodes() {
        let pocketRefusal = StellarError.simulationFailed("HostError: Error(Auth, InvalidAction) … data:[\"failed account authentication with error\", CA…, Error(Contract, #201)]")
        #expect(RecoveryIDSearch.isRejectedSignature(pocketRefusal, contractCodes: RecoveryIDSearch.RejectionCode.pocket))
        #expect(!RecoveryIDSearch.isRejectedSignature(pocketRefusal, contractCodes: RecoveryIDSearch.RejectionCode.nfcNft))
        #expect(!RecoveryIDSearch.isRejectedSignature(StellarError.simulationFailed("Error(Contract, #2010)"), contractCodes: [201]))
        #expect(RecoveryIDSearch.isRejectedSignature(StellarError.simulationFailed("Error(Crypto, InvalidInput) recover_key_ecdsa"), contractCodes: nil))
        #expect(!RecoveryIDSearch.isRejectedSignature(StellarError.rpc("timeout"), contractCodes: [201]))
        #expect(!RecoveryIDSearch.isRejectedSignature(StellarError.simulationFailed("Error(Contract, #201)"), contractCodes: nil))
    }

    @Test("Recherche du recovery_id : passe au suivant sur un refus, s'arrête sur le premier accepté")
    func recoverySearchFindsFirstAccepted() async throws {
        var attempts: [UInt32] = []
        let found = try await RecoveryIDSearch.first(rejectionCodes: [201]) { id -> String in
            attempts.append(id)
            if id < 2 { throw StellarError.simulationFailed("Error(Contract, #201)") }
            return "assembled"
        }
        #expect(found.result == "assembled")
        #expect(found.recoveryID == 2)
        #expect(attempts == [0, 1, 2])
    }

    @Test("Recherche du recovery_id : une autre erreur remonte aussitôt ; 4 refus = signatureRejected")
    func recoverySearchFailures() async {
        var attempts = 0
        await #expect(throws: StellarError.rpc("down")) {
            try await RecoveryIDSearch.first(rejectionCodes: [201]) { _ -> Int in
                attempts += 1
                throw StellarError.rpc("down")
            }
        }
        #expect(attempts == 1)
        await #expect(throws: StellarError.self) {
            try await RecoveryIDSearch.first(rejectionCodes: [201]) { _ -> Int in throw StellarError.simulationFailed("Error(Contract, #201)") }
        }
        do {
            _ = try await RecoveryIDSearch.first(rejectionCodes: [201]) { _ -> Int in throw StellarError.simulationFailed("Error(Contract, #201)") }
        } catch StellarError.signatureRejected {
        } catch {
            Issue.record("expected signatureRejected, got \(error)")
        }
    }

    // MARK: Preuve de possession (DUOX, locale)

    @Test("Possession DUOX : signature P-256 de sha256(F0F0 ‖ 8000 ‖ RndB ‖ défi[0..16]) acceptée, y compris après low-S")
    func possessionP256Valid() throws {
        let privateKey = P256.Signing.PrivateKey()
        let publicKey = try ChipPublicKey(privateKey.publicKey.x963Representation)
        let challenge = Data((0..<32).map { UInt8($0) })
        let rndB = Data(repeating: 0xAB, count: 16)
        let payload = CardPossession.p256Payload(rndB: rndB, challenge: challenge)
        #expect(payload.hexString == "f0f08000" + String(repeating: "ab", count: 16) + "000102030405060708090a0b0c0d0e0f")
        let raw = try privateKey.signature(for: SHA256.hash(data: payload)).rawRepresentation
        try CardPossession.verifyP256(publicKey: publicKey, challenge: challenge, signature: raw, rndB: rndB)
        try CardPossession.verifyP256(publicKey: publicKey, challenge: challenge, signature: try SignatureEncoding.lowS(raw, curve: .p256), rndB: rndB)
    }

    @Test("Possession DUOX : autre défi, autre RndB, autre carte ou signature abîmée → refus")
    func possessionP256Invalid() throws {
        let privateKey = P256.Signing.PrivateKey()
        let publicKey = try ChipPublicKey(privateKey.publicKey.x963Representation)
        let challenge = Data(repeating: 0x01, count: 32)
        let rndB = Data(repeating: 0xAB, count: 16)
        let raw = try privateKey.signature(for: SHA256.hash(data: CardPossession.p256Payload(rndB: rndB, challenge: challenge))).rawRepresentation
        var otherChallenge = challenge
        otherChallenge[0] = 0x02
        #expect(throws: CardPossession.PossessionError.signatureMismatch) {
            try CardPossession.verifyP256(publicKey: publicKey, challenge: otherChallenge, signature: raw, rndB: rndB)
        }
        #expect(throws: CardPossession.PossessionError.signatureMismatch) {
            try CardPossession.verifyP256(publicKey: publicKey, challenge: challenge, signature: raw, rndB: Data(repeating: 0xAC, count: 16))
        }
        let otherCard = try ChipPublicKey(P256.Signing.PrivateKey().publicKey.x963Representation)
        #expect(throws: CardPossession.PossessionError.signatureMismatch) {
            try CardPossession.verifyP256(publicKey: otherCard, challenge: challenge, signature: raw, rndB: rndB)
        }
        var damaged = raw
        damaged[10] ^= 0xFF
        #expect(throws: CardPossession.PossessionError.signatureMismatch) {
            try CardPossession.verifyP256(publicKey: publicKey, challenge: challenge, signature: damaged, rndB: rndB)
        }
    }

    @Test("Possession : la DUOX ne signe que les 16 premiers octets du défi (troncature documentée, ARCHITECTURE §3.1)")
    func possessionP256Truncation() throws {
        let privateKey = P256.Signing.PrivateKey()
        let publicKey = try ChipPublicKey(privateKey.publicKey.x963Representation)
        let challenge = Data(repeating: 0x01, count: 32)
        let rndB = Data(repeating: 0xAB, count: 16)
        let raw = try privateKey.signature(for: SHA256.hash(data: CardPossession.p256Payload(rndB: rndB, challenge: challenge))).rawRepresentation
        var tail = challenge
        tail[31] = 0x99
        try CardPossession.verifyP256(publicKey: publicKey, challenge: tail, signature: raw, rndB: rndB)
    }

    @Test("Possession Infineon sans campagne connue : refus sans aucune requête ; signature d'une autre courbe : refus")
    func possessionK1WithoutCampaign() async throws {
        let client = SorobanClient(config: config)
        let nfcNft = NfcNftClient(client: client, defaultContract: config.contracts.nfcNft, collection: config.contracts.collection)
        let source = try Account(accountId: config.feePayer, sequenceNumber: 1)
        let card = ChipKeyInfo(kind: .infineon2Go, publicKey: k1Key, pinActive: false)
        await #expect(throws: CardPossession.PossessionError.unknownCard) {
            try await CardPossession.verify(card: card, challenge: Data(count: 32), signed: .secp256k1(signature: signature),
                                            nfcNft: nfcNft, nftContract: nil, source: source)
        }
        await #expect(throws: CardPossession.PossessionError.signatureMismatch) {
            try await CardPossession.verify(card: card, challenge: Data(count: 32), signed: .p256(signature: signature, rndB: Data(count: 16)),
                                            nfcNft: nfcNft, nftContract: config.contracts.nfcNft, source: source)
        }
    }

    // MARK: Serveur de frais

    @Test("Serveur de frais : POST {xdr, network}, enveloppe signée renvoyée")
    func feeSignerRequest() async throws {
        let transaction = try sampleTransaction(sequence: 1234)
        let http = ScriptedHTTP([.init(status: 200, body: ["xdr": try transaction.encodedEnvelope()])])
        let signer = WorkerFeeSigner(url: config.feeSignerURL, transport: http.send, sleep: { _ in })
        let signed = try await signer.signFees(transaction, network: .testnet, passphrase: passphrase)
        #expect(try signed.getTransactionHash(network: .testnet) == transaction.getTransactionHash(network: .testnet))
        let request = try #require(http.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url == config.feeSignerURL)
        let body = try #require(try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: String])
        #expect(body == ["xdr": try transaction.encodedEnvelope(), "network": passphrase])
    }

    @Test("Serveur de frais : 429 attendu une fois (retry-after), puis réussite ; deux 429 = busy")
    func feeSignerRateLimit() async throws {
        let transaction = try sampleTransaction(sequence: 1234)
        let waits = Waits()
        let retried = ScriptedHTTP([
            .init(status: 429, body: [:], retryAfter: "3"),
            .init(status: 200, body: ["xdr": try transaction.encodedEnvelope()]),
        ])
        _ = try await WorkerFeeSigner(url: config.feeSignerURL, transport: retried.send, sleep: waits.record)
            .signFees(transaction, network: .testnet, passphrase: passphrase)
        #expect(retried.requests.count == 2)
        #expect(waits.durations == [.seconds(3)])

        let busy = ScriptedHTTP([.init(status: 429, body: [:]), .init(status: 429, body: [:])])
        await #expect(throws: FeeSignerError.busy) {
            try await WorkerFeeSigner(url: config.feeSignerURL, transport: busy.send, sleep: { _ in })
                .signFees(transaction, network: .testnet, passphrase: passphrase)
        }
        #expect(busy.requests.count == 2)
    }

    @Test("Délai retry-after : > 0 pris (plafonné à 10 s) ; absent, nul ou illisible → 5 s")
    func retryDelay() {
        #expect(WorkerFeeSigner.retryDelay(retryAfter: "3") == .seconds(3))
        #expect(WorkerFeeSigner.retryDelay(retryAfter: "60") == .seconds(10))
        #expect(WorkerFeeSigner.retryDelay(retryAfter: "0.5") == .milliseconds(500))
        #expect(WorkerFeeSigner.retryDelay(retryAfter: nil) == .seconds(5))
        #expect(WorkerFeeSigner.retryDelay(retryAfter: "0") == .seconds(5))
        #expect(WorkerFeeSigner.retryDelay(retryAfter: "soon") == .seconds(5))
    }

    @Test("Serveur de frais : 5xx = indisponible, 403 = refus avec la raison, autre transaction = refusée")
    func feeSignerErrors() async throws {
        let transaction = try sampleTransaction(sequence: 1234)
        let down = ScriptedHTTP([.init(status: 503, body: ["reason": "overloaded"])])
        await #expect(throws: FeeSignerError.unavailable("overloaded")) {
            try await WorkerFeeSigner(url: config.feeSignerURL, transport: down.send, sleep: { _ in })
                .signFees(transaction, network: .testnet, passphrase: passphrase)
        }
        let refused = ScriptedHTTP([.init(status: 403, body: ["error": "refused", "reason": "fee above ceiling"])])
        await #expect(throws: FeeSignerError.refused("fee above ceiling")) {
            try await WorkerFeeSigner(url: config.feeSignerURL, transport: refused.send, sleep: { _ in })
                .signFees(transaction, network: .testnet, passphrase: passphrase)
        }
        let swapped = ScriptedHTTP([.init(status: 200, body: ["xdr": try sampleTransaction(sequence: 9999).encodedEnvelope()])])
        await #expect(throws: FeeSignerError.changedTransaction) {
            try await WorkerFeeSigner(url: config.feeSignerURL, transport: swapped.send, sleep: { _ in })
                .signFees(transaction, network: .testnet, passphrase: passphrase)
        }
    }

    @Test("Empreinte trop petite (« exceeds amount specified ») : reconnue pour la seule nouvelle tentative")
    func staleFootprint() {
        #expect(StellarError.transactionFailed(hash: "h", detail: "operation byte-write resources exceeds amount specified").isStaleFootprint)
        #expect(!StellarError.transactionFailed(hash: "h", detail: "Error(Contract, #201)").isStaleFootprint)
        #expect(!StellarError.notConfirmed(hash: "h").isStaleFootprint)
    }

    // MARK: Aides

    private func setOwnerEntry(nonce: Int64) throws -> SorobanAuthorizationEntryXDR {
        try SorobanAuth.declaredEntry(
            authorizer: pocketK1,
            invocation: try SorobanAuth.contractInvocation(
                contract: pocketK1, function: "set_owner", arguments: try PocketClient.setOwnerArguments(newOwner: accountK1)
            ),
            nonce: nonce,
            expirationLedger: 1000
        )
    }

    /// Même entrée, credentials V2 (ce que renvoie une simulation Protocol 28).
    private func asV2(_ entry: SorobanAuthorizationEntryXDR) throws -> SorobanAuthorizationEntryXDR {
        SorobanAuthorizationEntryXDR(credentials: .addressV2(try SorobanAuth.addressCredentials(entry)), rootInvocation: entry.rootInvocation)
    }

    private func sampleTransaction(sequence: Int64) throws -> Transaction {
        try SorobanClient(config: config).contractCall(
            source: try Account(accountId: config.feePayer, sequenceNumber: sequence),
            contract: pocketK1, function: "owner", arguments: []
        )
    }

    private func base64<T: XDREncodable>(_ value: T) throws -> String {
        Data(try XDREncoder.encode(value)).base64EncodedString()
    }
}

/// Faux serveur HTTP : renvoie les réponses prévues dans l'ordre et garde les requêtes reçues.
private final class ScriptedHTTP: @unchecked Sendable {
    struct Reply {
        let status: Int
        let body: [String: String]
        var retryAfter: String?
    }

    private var replies: [Reply]
    private(set) var requests: [URLRequest] = []

    init(_ replies: [Reply]) { self.replies = replies }

    @Sendable func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let reply = replies.removeFirst()
        var headers = ["content-type": "application/json"]
        if let retryAfter = reply.retryAfter { headers["retry-after"] = retryAfter }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: headers)!
        return (try JSONSerialization.data(withJSONObject: reply.body), response)
    }
}

/// Garde les attentes demandées au lieu de dormir.
private final class Waits: @unchecked Sendable {
    private(set) var durations: [Duration] = []
    @Sendable func record(_ duration: Duration) async throws { durations.append(duration) }
}
