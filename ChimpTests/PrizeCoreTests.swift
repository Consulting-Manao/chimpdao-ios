import Foundation
import stellarsdk
import Testing
@testable import ChimpDAO

/// Contrat `prize` (carte partenaire, D5) : digest de l'attestation, arguments, autorisation déclarée de la Pocket et
/// signatures enchaînées dans un seul tap.
///
/// Vecteurs du digest : `call_digest` de `reference/chimp-contracts/contracts/chip-auth/src/verify.rs` recalculé par un
/// script Python indépendant (domaine ‖ XDR(adresse) ‖ XDR(symbole) ‖ XDR(vec) ‖ XDR(u32), puis SHA-256), qui redonne
/// d'abord le vecteur Rust figé du terminal (`2b23d024…`, `chip-auth.test.ts`) avant de donner ceux du domaine
/// `chimpdao.prize.v1` (aucun vecteur de ce domaine n'existe dans `reference/`).
struct PrizeCoreTests {
    private let prize = "CDXIJB4UZ6DA7OVFH3HYXUKXB7G6Z2ZD4MG7PTONQ5QELL656KMWCZE4"
    private let pocket = "CC6Z7JDXX2RXULI2TMY7OGJJ57WXTBRCQDRR4W4IFEJZZ7SPGCPYJEJT"
    private let signature = Data(hex: String(repeating: "11", count: 32) + String(repeating: "22", count: 32))!
    private let rndB = Data(repeating: 0xAB, count: 16)

    private func prepared(curve: ChipCurve = .secp256k1, key: ChipPublicKey = MockChipReader.secp256k1Key) -> PreparedPrizeClaim {
        PreparedPrizeClaim(
            prize: prize, pocket: pocket, card: key, curve: curve, amount: TokenAmount(250_000_000),
            token: "CDLZFC3SYJYDZT7K67VZ75HPJVIEUVNIXF47ZG2FB2RMQQVU2HHGCYSC", nfcContract: pocket,
            attestationNonce: 1, pocketNonce: 42, preparedAtLedger: 1_000, expirationLedger: 1_120,
            passphrase: ChimpNetworkConfig.testnet.passphrase
        )
    }

    // MARK: Digest et arguments

    @Test("ChipCallDigest (compilé aussi hors du mode admin) : vecteur Rust figé du terminal")
    func sharedCallDigestRustVector() throws {
        let digest = try ChipCallDigest.callDigest(
            domain: "chimpdao.nfc-nft.v2", contractID: "CDXIJB4UZ6DA7OVFH3HYXUKXB7G6Z2ZD4MG7PTONQ5QELL656KMWCZE4", function: "claim",
            arguments: [.address(try SCAddressXDR(accountId: "GBBD47IF6LWK7P7MDEVSCWR7DPUWV3NY3DTQEVFL4NAT4AQH3ZLLFLA5"))], nonce: 7
        )
        #expect(digest.hexString == "2b23d024c62e7c8d1d37f118e574ef030ffc7b37efc8bb77439c09b93c97ce7c")
    }

    @Test("Attestation de redeem : call_digest(chimpdao.prize.v1, prize, redeem, [redeemer], nonce), vecteurs recalculés")
    func redeemDigestVector() throws {
        #expect(try PrizeContract.redeemDigest(prize: prize, redeemer: pocket, nonce: 1).hexString
            == "6792d636bd26fa7efcdc8b4001e179eb6b225b307e1ee45870c451e4029199b2")
        #expect(try PrizeContract.redeemDigest(prize: prize, redeemer: pocket, nonce: 2).hexString
            == "ffdda74b56b0ca03ae8f875ffd1fb40abf0f64547093a137a414527e3f95ec85")
    }

    @Test("Le domaine du prize n'est pas celui de nfc-nft : une attestation ne passe pas de l'un à l'autre")
    func domainSeparation() throws {
        let other = try ChipCallDigest.callDigest(
            domain: "chimpdao.nfc-nft.v3", contractID: prize, function: "redeem",
            arguments: [try ContractArgument.address(pocket)], nonce: 1
        )
        #expect(other != (try PrizeContract.redeemDigest(prize: prize, redeemer: pocket, nonce: 1)))
    }

    @Test("Arguments : redeem(redeemer, auth, public_key, nonce) et deposit(from, amount i128, token_id u32)")
    func arguments() throws {
        let auth = try ChipAuthEncoding.chipAuthSecp256k1(signature: signature, recoveryID: 1)
        let redeem = try PrizeContract.redeemArguments(redeemer: pocket, attestation: auth, publicKey: MockChipReader.secp256k1Key, nonce: 3)
        #expect(redeem.count == 4)
        #expect(try redeem[0].address?.toStrKey() == pocket)
        #expect(try XDREncoder.encode(redeem[1]) == (try XDREncoder.encode(auth)))
        #expect(redeem[2].bytes == MockChipReader.secp256k1Key.bytes)
        #expect(redeem[3].u32 == 3)

        let admin = ChimpNetworkConfig.testnet.contracts.admin
        let deposit = try PrizeContract.depositArguments(from: admin, amount: TokenAmount(50_0000000), tokenID: 7)
        #expect(try deposit[0].address?.toStrKey() == admin)
        #expect(ContractArgument.int128(deposit[1]) == 50_0000000)
        #expect(deposit[2].u32 == 7)
    }

    @Test("Erreurs du contrat 400 à 403 lues dans une simulation refusée ; autre texte : rien")
    func contractErrors() {
        #expect(PrizeContract.PrizeError.in(StellarError.simulationFailed("HostError: Error(Contract, #400)")) == .nothingReserved)
        #expect(PrizeContract.PrizeError.in(StellarError.simulationFailed("HostError: Error(Contract, #401)")) == .notCardOwner)
        #expect(PrizeContract.PrizeError.in(StellarError.simulationFailed("HostError: Error(Contract, #402)")) == .invalidAttestation)
        #expect(PrizeContract.PrizeError.in(StellarError.simulationFailed("HostError: Error(Contract, #403)")) == .invalidAmount)
        #expect(PrizeContract.PrizeError.in(StellarError.simulationFailed("HostError: Error(Contract, #10)")) == nil)
        #expect(PrizeContract.PrizeError.in(StellarError.rpc("Error(Contract, #400)")) == nil)
    }

    // MARK: Autorisation de la Pocket

    @Test("Arbre déclaré : redeem sur le prize, avec l'attestation dans les arguments, sans sous-appel ; signé par la Pocket")
    func declaredTree() throws {
        let claim = prepared()
        let auth = try PrizeContract.attestation(.secp256k1(signature: signature), recoveryID: 0)
        let declared = try claim.declaredAuthorization(attestation: auth)
        let root = declared.entry.rootInvocation
        guard case .contractFn(let fn) = root.function else { Issue.record("expected a contract call"); return }
        #expect(fn.functionName == "redeem")
        #expect(try fn.contractAddress.toStrKey() == prize)
        #expect(try fn.args.map { try XDREncoder.encode($0) } == (try claim.call(attestation: auth).arguments.map { try XDREncoder.encode($0) }))
        #expect(root.subInvocations.isEmpty)
        let credentials = try SorobanAuth.addressCredentials(declared.entry)
        #expect(credentials.nonce == 42)
        #expect(credentials.signatureExpirationLedger == 1_120)
        #expect(try credentials.address.toStrKey() == pocket)
    }

    @Test("Infineon : deux autorisations de la Pocket (recovery_id 0 et 1 de l'attestation), différentes, dans l'ordre")
    func pocketDigestsK1() throws {
        let claim = prepared()
        let digests = try claim.pocketDigests(after: [.secp256k1(signature: signature)])
        #expect(digests.count == 2)
        #expect(digests[0] != digests[1])
        for (index, recoveryID) in [UInt32(0), 1].enumerated() {
            let auth = try ChipAuthEncoding.chipAuthSecp256k1(signature: signature, recoveryID: recoveryID)
            #expect(digests[index] == (try claim.declaredAuthorization(attestation: auth).digest))
        }
        // Le digest de la Pocket dépend de l'attestation, jamais de l'attestation seule.
        #expect(!digests.contains(try claim.attestationDigest))
    }

    @Test("DUOX : une seule autorisation de la Pocket, avec l'attestation P-256 telle quelle")
    func pocketDigestsP256() throws {
        let claim = prepared(curve: .p256, key: MockChipReader.p256Key)
        let digests = try claim.pocketDigests(after: [.p256(signature: signature, rndB: rndB)])
        let auth = try ChipAuthEncoding.chipAuthSecp256r1(signature: signature, rndB: rndB)
        #expect(digests == [try claim.declaredAuthorization(attestation: auth).digest])
    }

    @Test("Attestation de la mauvaise courbe, absente ou en double : refus, rien de plus n'est signé")
    func pocketDigestsRefused() {
        #expect(throws: ChipError.self) { try prepared().pocketDigests(after: [.p256(signature: signature, rndB: rndB)]) }
        #expect(throws: ChipError.self) { try prepared().pocketDigests(after: []) }
        #expect(throws: ChipError.self) {
            try prepared().pocketDigests(after: [.secp256k1(signature: signature), .secp256k1(signature: signature)])
        }
    }

    @Test("Trace de « Check again » : le transfert du prize vers la Pocket, nonce de l'autorisation de la Pocket")
    func trace() {
        let trace = prepared().trace
        #expect(trace.from == pocket)
        #expect(trace.eventSender == prize)
        #expect(trace.eventRecipient == pocket)
        #expect(trace.nonce == 42)
        #expect(trace.units == 250_000_000)
        #expect(trace.preparedAtLedger == 1_000)
        #expect(trace.expirationLedger == 1_120)
    }

    // MARK: Signatures enchaînées (un seul tap)

    @Test("Un tap : lecture, l'attestation, puis les digests calculés à partir d'elle, chacun SELECT → VERIFY PIN → SIGN")
    func chainedSigning() async throws {
        let card = PrizeInfineon(key: MockChipReader.secp256k1Key)
        let claim = prepared()
        let first = try claim.attestationDigest
        let signed = try await ChipSigning.sign(
            card, digests: [first], followUp: { try claim.pocketDigests(after: $0) },
            acceptedKeys: [MockChipReader.secp256k1Key], pin: "1234"
        )
        #expect(signed.signatures.count == 3)
        let expected = try claim.pocketDigests(after: [signed.signatures[0]])
        #expect(card.signedDigests == [first] + expected)
        #expect(card.sent.filter { $0.prefix(2) == Data([0x00, 0x44]) }.count == 3)
    }

    @Test("Une autre carte : refus après la lecture de sa clé, ni PIN ni signature, followUp jamais appelé")
    func chainedSigningOtherCard() async throws {
        let card = PrizeInfineon(key: MockChipReader.secp256k1Key)
        let other = try ChipPublicKey(Data([0x04]) + Data(repeating: 0x99, count: 64))
        await #expect(throws: ChipError.cardNotAccepted(tapped: MockChipReader.secp256k1Key)) {
            try await ChipSigning.sign(card, digests: [Data(count: 32)], followUp: { _ in
                Issue.record("followUp must not run")
                return []
            }, acceptedKeys: [other], pin: "1234")
        }
        #expect(card.signedDigests.isEmpty)
        #expect(!card.sent.contains { $0.prefix(2) == Data([0x00, 0x44]) })
    }

    @Test("followUp qui échoue : l'erreur remonte, rien n'est renvoyé (donc rien ne peut partir)")
    func chainedSigningFollowUpFails() async throws {
        let card = PrizeInfineon(key: MockChipReader.secp256k1Key)
        await #expect(throws: ChipError.malformedResponse("boom")) {
            try await ChipSigning.sign(card, digests: [Data(count: 32)], followUp: { _ in
                throw ChipError.malformedResponse("boom")
            }, acceptedKeys: [MockChipReader.secp256k1Key], pin: nil)
        }
        #expect(card.signedDigests.count == 1)
    }

    @Test("Le faux signataire enchaîne aussi : une signature par digest, followUp compris")
    func mockChained() async throws {
        let signer = MockChipSigner(delay: .zero)
        let signed = try await signer.sign(
            digests: [Data(count: 32)], followUp: { _ in [Data(count: 32), Data(count: 32)] },
            acceptedKeys: [MockChipReader.secp256k1Key], pin: nil
        )
        #expect(signed.signatures.count == 3)
    }
}

/// Infineon simulée : lit sa clé, vérifie un PIN, signe (DER fixe) et note les digests signés.
private final class PrizeInfineon: APDUTransport, @unchecked Sendable {
    private(set) var sent: [Data] = []
    private(set) var signedDigests: [Data] = []
    let key: ChipPublicKey

    init(key: ChipPublicKey) { self.key = key }

    func send(_ apdu: Data) async throws -> APDUResponse {
        sent.append(apdu)
        let ok = { (data: Data) in APDUResponse(data: data, sw1: 0x90, sw2: 0x00) }
        if apdu == Infineon2Go.selectAPDU { return ok(Data([0x01])) }
        if apdu.prefix(2) == Data([0x00, 0x16]) { return ok(Data(count: 8) + key.bytes) }
        if apdu.prefix(2) == Data([0x00, 0x44]) { return ok(Data()) }
        if apdu.prefix(2) == Data([0x00, 0x18]) {
            signedDigests.append(apdu.dropFirst(5).prefix(32))
            let der = Data(hex: "3044022011111111111111111111111111111111111111111111111111111111111111110220" + String(repeating: "22", count: 32))!
            return ok(Data(count: 8) + der)
        }
        return APDUResponse(data: Data(), sw1: 0x6D, sw2: 0x00)
    }
}
