import Foundation
import stellarsdk
import Testing
@testable import ChimpDAO

// Mode admin (CHIMP_ADMIN) : absent de la Release, donc du schéma « Chimp Release Tests ».
#if CHIMP_ADMIN

// Code du mode admin : ces tests tournent avec l'action Test du schéma (configuration Debug, drapeau `CHIMP_ADMIN`).

/// Étape B : attestation, encodages, signature de la puce, transaction `mint`, garde-fous.
/// Valeurs de référence calculées par les fonctions du terminal (`chip-auth.ts`, `provisioning.ts`) et du bridge
/// (`der.js`), recopiées telles quelles et exécutées avec `@stellar/stellar-sdk` 17.0.1 (version du `bun.lock`
/// du terminal, empreinte vérifiée). Le script retrouve le vecteur Rust figé dans `chip-auth.test.ts`.
struct EnrolmentTests {
    private let k1Key = MockChipReader.secp256k1Key
    private let r1Key = MockChipReader.p256Key
    /// **L'adresse avec laquelle les vecteurs ci-dessous ont été calculés** (campagne `chi4`), et non la campagne par
    /// défaut de `Config/` : le digest et l'enveloppe du `mint` portent l'adresse du contrat appelé, donc changer de
    /// campagne changerait les valeurs attendues et ces tests ne prouveraient plus le **format**. La campagne par
    /// défaut est vérifiée à part (`testnetAddresses`).
    private let nfcNft = "CC6Z7JDXX2RXULI2TMY7OGJJ57WXTBRCQDRR4W4IFEJZZ7SPGCPYJEJT"
    private let factory = ChimpNetworkConfig.testnet.contracts.factory
    private let admin = ChimpNetworkConfig.testnet.contracts.admin
    private let signature = Data(hex: String(repeating: "11", count: 32) + String(repeating: "22", count: 32))!
    private let rndB = Data(repeating: 0xAB, count: 16)

    // MARK: Attestation (modèle B)

    @Test("callDigest : vecteur Rust figé du terminal (chimpdao_chip_auth::call_digest)")
    func callDigestRustVector() throws {
        let digest = try NfcNftAttestation.callDigest(
            domain: "chimpdao.nfc-nft.v2",
            contractID: "CDXIJB4UZ6DA7OVFH3HYXUKXB7G6Z2ZD4MG7PTONQ5QELL656KMWCZE4",
            function: "claim",
            arguments: [.address(try SCAddressXDR(accountId: "GBBD47IF6LWK7P7MDEVSCWR7DPUWV3NY3DTQEVFL4NAT4AQH3ZLLFLA5"))],
            nonce: 7
        )
        #expect(digest.hexString == "2b23d024c62e7c8d1d37f118e574ef030ffc7b37efc8bb77439c09b93c97ce7c")
    }

    /// Contrat nfc-nft de testnet mis à jour (`reference/chimp-contracts` e9e6c84) : `uri: Option<String>` est attesté
    /// après la politique. Vecteurs : `callDigest`, `scCurve`, `scUpgradePolicy` du terminal recopiés tels quels, liste
    /// d'arguments du `mint_digest` des tests du contrat, `uri` = `None` (`ScVal::Void`). Le même script redonne les
    /// anciens vecteurs à 3 arguments (f8a98f…, 1986079…), qui ne sont plus acceptés par le contrat.
    @Test("Digest de mint (v3, [clé, courbe, Managed, uri None], nonce 7) : contrat à jour, Infineon et DUOX")
    func mintDigest() throws {
        #expect(NfcNftAttestation.domain == "chimpdao.nfc-nft.v3")
        #expect(try NfcNftAttestation.mintDigest(nfcNft: nfcNft, publicKey: k1Key, curve: .secp256k1, managed: true, nonce: 7).hexString
            == "99fd618f3126b96165bbc3b75b9ee9fa80d467564ccbe72e1a30ccc570b70f1d")
        #expect(try NfcNftAttestation.mintDigest(nfcNft: nfcNft, publicKey: r1Key, curve: .p256, managed: true, nonce: 7).hexString
            == "f85088d7846cedf56f535d471e1a48a04aba30cae3a1c1179172bda0c88b6012")
        let arguments = NfcNftAttestation.mintArguments(auth: .void, publicKey: k1Key, curve: .secp256k1, managed: true, nonce: 7)
        #expect(arguments.count == 6, "mint(auth, public_key, curve, upgrade_policy, uri, nonce)")
        #expect(try xdr(arguments[4]) == "AAAAAQ==", "uri = None")
    }

    // MARK: Encodages ScVal

    @Test("Curve et UpgradePolicy : mêmes octets XDR que scCurve / scUpgradePolicy")
    func unitEnums() throws {
        #expect(try xdr(ChipAuthEncoding.curve(.secp256k1)) == "AAAAEAAAAAEAAAABAAAADwAAAAlTZWNwMjU2azEAAAA=")
        #expect(try xdr(ChipAuthEncoding.curve(.p256)) == "AAAAEAAAAAEAAAABAAAADwAAAAlTZWNwMjU2cjEAAAA=")
        #expect(try xdr(ChipAuthEncoding.upgradePolicy(managed: true)) == "AAAAEAAAAAEAAAABAAAADwAAAAdNYW5hZ2VkAA==")
    }

    @Test("ChipAuth Secp256k1 et Secp256r1 : clés de map triées, mêmes octets que le terminal")
    func chipAuth() throws {
        #expect(try xdr(ChipAuthEncoding.chipAuthSecp256k1(signature: signature, recoveryID: 1))
            == "AAAAEAAAAAEAAAACAAAADwAAAAlTZWNwMjU2azEAAAAAAAARAAAAAQAAAAIAAAAPAAAAC3JlY292ZXJ5X2lkAAAAAAMAAAABAAAADwAAAAlzaWduYXR1cmUAAAAAAAANAAAAQBERERERERERERERERERERERERERERERERERERERERERIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiI=")
        #expect(try xdr(ChipAuthEncoding.chipAuthSecp256r1(signature: signature, rndB: rndB))
            == "AAAAEAAAAAEAAAACAAAADwAAAAlTZWNwMjU2cjEAAAAAAAARAAAAAQAAAAIAAAAPAAAABXJuZF9iAAAAAAAADQAAABCrq6urq6urq6urq6urq6urAAAADwAAAAlzaWduYXR1cmUAAAAAAAANAAAAQBERERERERERERERERERERERERERERERERERERERERERIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiI=")
        #expect(throws: ChipError.self) { try ChipAuthEncoding.chipAuthSecp256r1(signature: signature, rndB: Data(count: 8)) }
        #expect(throws: ChipError.self) { try ChipAuthEncoding.chipAuthSecp256k1(signature: Data(count: 63), recoveryID: 0) }
    }

    // MARK: Transaction mint

    @Test("Transaction mint complète (Infineon) : enveloppe du terminal, avec uri = None avant le nonce (compte et bornes fixes)")
    func mintEnvelopeK1() throws {
        let auth = try ChipAuthEncoding.chipAuthSecp256k1(signature: signature, recoveryID: 1)
        #expect(try mintEnvelope(card: k1Key, kind: .infineon2Go, auth: auth)
            == "AAAAAgAAAABXZ5r1Pz+DMcNFD5T8pJxRItNzD9JgDnFDKb85dk/fggAAAGQAAAAASZYC0wAAAAEAAAAAAAAAAAAAAABrSdIAAAAAAAAAAAEAAAAAAAAAGAAAAAAAAAABvZ+kd76jei0amzH3GSnv7XmGIoDjHluIKROc/k8wn4QAAAAEbWludAAAAAYAAAAQAAAAAQAAAAIAAAAPAAAACVNlY3AyNTZrMQAAAAAAABEAAAABAAAAAgAAAA8AAAALcmVjb3ZlcnlfaWQAAAAAAwAAAAEAAAAPAAAACXNpZ25hdHVyZQAAAAAAAA0AAABAEREREREREREREREREREREREREREREREREREREREREREiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIgAAAA0AAABBBHm+Zn753LusVaBilc6HCwcCm/zbLc4o2VnygVsW+BeYSDradyajxGVdpPv8DhEIqP0XtEimhVQZnEfQj/sQ1LgAAAAAAAAQAAAAAQAAAAEAAAAPAAAACVNlY3AyNTZrMQAAAAAAABAAAAABAAAAAQAAAA8AAAAHTWFuYWdlZAAAAAABAAAAAwAAAAcAAAAAAAAAAAAAAAA=")
    }

    @Test("Transaction mint complète (DUOX) : enveloppe du terminal, avec uri = None avant le nonce")
    func mintEnvelopeR1() throws {
        let auth = try ChipAuthEncoding.chipAuthSecp256r1(signature: signature, rndB: rndB)
        #expect(try mintEnvelope(card: r1Key, kind: .duox, auth: auth)
            == "AAAAAgAAAABXZ5r1Pz+DMcNFD5T8pJxRItNzD9JgDnFDKb85dk/fggAAAGQAAAAASZYC0wAAAAEAAAAAAAAAAAAAAABrSdIAAAAAAAAAAAEAAAAAAAAAGAAAAAAAAAABvZ+kd76jei0amzH3GSnv7XmGIoDjHluIKROc/k8wn4QAAAAEbWludAAAAAYAAAAQAAAAAQAAAAIAAAAPAAAACVNlY3AyNTZyMQAAAAAAABEAAAABAAAAAgAAAA8AAAAFcm5kX2IAAAAAAAANAAAAEKurq6urq6urq6urq6urq6sAAAAPAAAACXNpZ25hdHVyZQAAAAAAAA0AAABAEREREREREREREREREREREREREREREREREREREREREREiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIgAAAA0AAABBBGsX0fLhLEJH+Lzm5WOkQPJ3A32BLeszoPShOUXYmMKWT+NC4v4af5uO5+tKfA+eFivOM1drMV7Oy7ZAaDe/UfUAAAAAAAAQAAAAAQAAAAEAAAAPAAAACVNlY3AyNTZyMQAAAAAAABAAAAABAAAAAQAAAA8AAAAHTWFuYWdlZAAAAAABAAAAAwAAAAcAAAAAAAAAAAAAAAA=")
    }

    @Test("Adresse de la Pocket calculée hors ligne : identique à predictPocket")
    func predictPocket() throws {
        #expect(try CardEnrolment.predictPocket(factory: factory, publicKey: k1Key, network: .testnet) == "CALWOI2Z6NZ5ULEYRXZZTN7M35CMWMS6YJXTQTVPIOQXKEKWKTVELEMX")
        #expect(try CardEnrolment.predictPocket(factory: factory, publicKey: r1Key, network: .testnet) == "CBO25SL7BJJT5J3LPAHTOKKVZJTBOBJQG227TE2JSETD7DZHF6BBOGMO")
    }

    // MARK: Recovery id (méthode de l'ancienne app)

    @Test("Signature refusée → recovery_id suivant ; toute autre erreur → on s'arrête")
    func rejectedSignaturePatterns() {
        let rejected = [
            "HostError: Error(Contract, #200)",
            "Error(Contract, 200)",
            #"["failing with contract error", 200]"#,
            "HostError: Error(Crypto, InvalidInput)",
            "secp256k1 recovery failed",
            "recover_key_ecdsa",
        ]
        for message in rejected {
            #expect(CardEnrolment.isRejectedSignature(StellarError.simulationFailed(message)), "\(message)")
        }
        let other: [Error] = [
            StellarError.simulationFailed("HostError: Error(Contract, #210)"), // TokenAlreadyMinted
            StellarError.simulationFailed("HostError: Error(Contract, #2001)"),
            StellarError.simulationFailed("ledger 200"),
            StellarError.rpc("The request timed out."),
            ChipError.cancelled,
        ]
        for error in other {
            #expect(!CardEnrolment.isRejectedSignature(error), "\(error)")
        }
    }

    @Test("Refus du contrat (trap) distingué d'une panne réseau (isContractTrap)")
    func contractTrap() {
        #expect(StellarError.simulationFailed("HostError: Error(Contract, #201)").isContractTrap)
        #expect(StellarError.simulationFailed("host invocation failed: UnreachableCodeReached").isContractTrap)
        #expect(!StellarError.simulationFailed("network down").isContractTrap)
        #expect(!StellarError.rpc("Error(Contract, #201)").isContractTrap)
    }

    // MARK: Garde-fou testnet

    @Test("Le mode admin refuse tout autre réseau que testnet")
    func testnetOnly() throws {
        try CardEnrolment.requireTestnet(.testnet)
        let testnet = ChimpNetworkConfig.testnet
        let mainnetPassphrase = ChimpNetworkConfig(
            network: .testnet, passphrase: "Public Global Stellar Network ; September 2015",
            endpoints: testnet.endpoints, contracts: testnet.contracts, feeSignerURL: testnet.feeSignerURL,
            feePayer: testnet.feePayer, usdcIssuer: testnet.usdcIssuer, usdcFaucet: nil, features: .none
        )
        let mainnetNetwork = ChimpNetworkConfig(
            network: .mainnet, passphrase: testnet.passphrase,
            endpoints: testnet.endpoints, contracts: testnet.contracts, feeSignerURL: testnet.feeSignerURL,
            feePayer: testnet.feePayer, usdcIssuer: testnet.usdcIssuer, usdcFaucet: nil, features: .none
        )
        let otherRPC = ChimpNetworkConfig(
            network: .testnet, passphrase: testnet.passphrase,
            endpoints: .init(rpc: URL(string: "https://rpc.lightsail.network")!, horizon: testnet.endpoints.horizon,
                             explorer: testnet.endpoints.explorer, friendbot: nil),
            contracts: testnet.contracts, feeSignerURL: testnet.feeSignerURL,
            feePayer: testnet.feePayer, usdcIssuer: testnet.usdcIssuer, usdcFaucet: nil, features: .none
        )
        for config in [mainnetPassphrase, mainnetNetwork, otherRPC] {
            #expect(throws: CardEnrolmentError.notTestnet) { try CardEnrolment.requireTestnet(config) }
            #expect(throws: CardEnrolmentError.notTestnet) { try CardEnrolment(config: config, keyStore: InMemoryAdminKeyStore()) }
        }
    }

    @Test("Config testnet : valeurs transmises par Pamphile")
    func testnetConfig() {
        let config = ChimpNetworkConfig.testnet
        // Campagne `og` (« Chimp OG ») depuis le 2026-11-16 : c'est là que le terminal enregistre aussi.
        #expect(config.contracts.nfcNft == "CAHOJMBLANFG7YQGCY4BRWSQ5N5Q5FVM5D3WA4S5ZON3QSNP2OJDRJPT")
        #expect(config.contracts.factory == "CDWPHF7DRJ37GLFZGQDSO6RTX4QR75WTNKJUMFJRETQLIOAHFBU6RGYR")
        #expect(config.contracts.collection == "CDGFNWFN7ZKU4XDPNXOGDQ4JZ7SZCMXLL3PYFESOCCA2L5DM3ZBCPEKC")
        #expect(config.contracts.router == "CAOL3K7VQTDZELQMKTAJB3WUQGL5JLXJKZ2Y44F77NH4CZNLW5I755XI")
        #expect(config.contracts.accountWasmHash == "044275ac1be3fd505922fb0c564370331753fe808e31990b7e74ebf395614271")
        #expect(config.explorerURL(transactionHash: "abc").absoluteString == "https://stellar.expert/explorer/testnet/tx/abc")
        #expect(config.feeSignerURL.absoluteString == "https://chimpdao-signer.tansu-964.workers.dev/")
    }

    // MARK: Clé admin

    @Test("Trousseau : cet appareil uniquement, sans synchronisation iCloud")
    func keychainAttributes() {
        let store = KeychainAdminKeyStore(network: .testnet)
        #expect(store.service == "com.consulting-manao.chimp.admin.testnet")
        #expect(store.addAttributes[kSecAttrAccessible] as? String == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        #expect(store.addAttributes[kSecAttrSynchronizable] as? Bool == false)
        #expect(store.baseQuery[kSecAttrSynchronizable] as? Bool == false)
    }

    @Test("Trousseau : enregistrer, relire l'adresse G, effacer (service de test, jamais la vraie clé)")
    func keychainRoundTrip() throws {
        let store = KeychainAdminKeyStore(service: "com.consulting-manao.chimp.admin.unit-tests")
        try store.erase()
        let keyPair = try KeyPair.generateRandomKeyPair()
        let saved = try store.save(secretSeed: "  \(keyPair.secretSeed!)\n")
        #expect(saved == keyPair.accountId)
        #expect(try store.publicKey() == keyPair.accountId)
        #expect(try store.keyPair()?.accountId == keyPair.accountId)
        try store.erase()
        #expect(try store.publicKey() == nil)
        #expect(throws: AdminKeyError.invalidSecretSeed) { try store.save(secretSeed: keyPair.accountId) }
        #expect(try store.publicKey() == nil)
    }

    @Test("Modèle de la clé : seule l'adresse G est exposée, avertissement si ce n'est pas l'admin connu")
    func keyModel() throws {
        let model = AdminKeyModel(store: InMemoryAdminKeyStore())
        #expect(!model.hasKey)
        model.save("SNOTAKEY")
        #expect(!model.hasKey)
        #expect(model.errorMessage != nil)
        let keyPair = try KeyPair.generateRandomKeyPair()
        model.save(keyPair.secretSeed!)
        #expect(model.publicKey == keyPair.accountId)
        #expect(model.isUnexpectedAdmin)
        model.erase()
        #expect(!model.hasKey)
    }

    // MARK: Parcours (services factices)

    @Test("Parcours : vérification → ce que la carte signe → tap 2 → enregistrée ; annulation = retour à la vérification")
    func enrolFlow() async throws {
        let card = ChipKeyInfo(kind: .infineon2Go, publicKey: k1Key, pinActive: false)
        let model = AdminEnrolModel(
            makeService: { MockCardEnrolmentService(delay: .zero) },
            signer: MockChipSigner(delay: .zero)
        )
        await model.check(card)
        guard case .ready(let plan) = model.state else { Issue.record("expected ready, got \(model.state)"); return }
        #expect(plan.managed)
        #expect(plan.digest.count == 32)
        await model.enrol(pin: nil)
        guard case .enrolled(let result) = model.state else { Issue.record("expected enrolled, got \(model.state)"); return }
        #expect(result.explorerURL.absoluteString.hasPrefix("https://stellar.expert/explorer/testnet/tx/"))

        let cancelling = AdminEnrolModel(
            makeService: { MockCardEnrolmentService(delay: .zero) },
            signer: MockChipSigner(outcome: .failure(.cancelled), delay: .zero)
        )
        await cancelling.check(card)
        await cancelling.enrol(pin: nil)
        #expect(cancelling.state == .ready(plan))

        let wrongCard = AdminEnrolModel(
            makeService: { MockCardEnrolmentService(delay: .zero) },
            signer: MockChipSigner(outcome: .failure(.wrongCard), delay: .zero)
        )
        await wrongCard.check(card)
        await wrongCard.enrol(pin: nil)
        #expect(wrongCard.state == .failed(ChipError.wrongCard.errorDescription!))
    }

    @Test("Carte déjà enregistrée : rien à écrire")
    func alreadyEnrolled() async {
        let model = AdminEnrolModel(makeService: { MockCardEnrolmentService(alreadyEnrolled: true, delay: .zero) }, signer: MockChipSigner(delay: .zero))
        await model.check(ChipKeyInfo(kind: .infineon2Go, publicKey: k1Key, pinActive: false))
        guard case .alreadyEnrolled = model.state else { Issue.record("expected alreadyEnrolled"); return }
    }

    // MARK: Aides

    private func xdr(_ value: SCValXDR) throws -> String {
        Data(try XDREncoder.encode(value)).base64EncodedString()
    }

    private func mintEnvelope(card: ChipPublicKey, kind: ChipKind, auth: SCValXDR) throws -> String {
        let plan = EnrolmentPlan(
            card: ChipKeyInfo(kind: kind, publicKey: card, pinActive: false), nfcNft: nfcNft, admin: admin,
            nonce: 7, managed: true, digest: Data(count: 32), predictedPocket: ""
        )
        let source = try Account(accountId: admin, sequenceNumber: 1_234_567_890)
        return try CardEnrolment.mintTransaction(source: source, plan: plan, auth: auth, maxTime: 1_800_000_000).encodedEnvelope()
    }
}
#endif
