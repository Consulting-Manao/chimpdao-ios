import Foundation
import Testing
@testable import ChimpDAO

/// Signature par la puce : APDU (comparés à `nfc-bridge/server/chips/infineon2go.js` et `duox.js`),
/// décodage DER et low-S (valeurs calculées par `der.js` et `normalizeSignature` du terminal).
struct ChipSigningTests {
    private let digest = Data((0..<32).map { UInt8($0) })

    // MARK: DER et low-S

    @Test("DER → r ‖ s : 00 de tête retiré, s court complété à 32 octets, s haut normalisé (toRS de der.js)")
    func derToRS() throws {
        let der1 = Data(hex: "3045022100f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f10220fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd036413e")!
        let der2 = Data(hex: "3044022100f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1021f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f")!
        #expect(try SignatureEncoding.lowS(SignatureEncoding.rawSignature(fromDER: der1), curve: .secp256k1).hexString
            == "f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f10000000000000000000000000000000000000000000000000000000000000003")
        #expect(try SignatureEncoding.lowS(SignatureEncoding.rawSignature(fromDER: der2), curve: .secp256k1).hexString
            == "f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1007f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f")
    }

    @Test("DER tronquée ou mal formée : erreur, jamais de plantage")
    func malformedDER() {
        for bad in ["", "3045", "31440220", "3006020101020201", "30450221" + String(repeating: "00", count: 10)] {
            #expect(throws: ChipError.self) { try SignatureEncoding.rawSignature(fromDER: Data(hex: bad) ?? Data()) }
        }
    }

    @Test("Low-S secp256k1 : s = n − 1 → 1 (normalizeSignature du terminal)")
    func lowSK1() throws {
        let high = Data(hex: "1111111111111111111111111111111111111111111111111111111111111111fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364140")!
        #expect(try SignatureEncoding.lowS(high, curve: .secp256k1).hexString
            == "11111111111111111111111111111111111111111111111111111111111111110000000000000000000000000000000000000000000000000000000000000001")
    }

    @Test("Low-S P-256 : s = n − 5 → 5 (toRS de der.js)")
    func lowSR1() throws {
        let high = Data(hex: "2222222222222222222222222222222222222222222222222222222222222222ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc63254c")!
        #expect(try SignatureEncoding.lowS(high, curve: .p256).hexString
            == "22222222222222222222222222222222222222222222222222222222222222220000000000000000000000000000000000000000000000000000000000000005")
    }

    @Test("Low-S : s ≤ n/2 inchangé (bornes comprises), n/2 + 1 normalisé, pour les deux courbes")
    func lowSBoundaries() throws {
        for curve in [ChipCurve.secp256k1, .p256] {
            let r = Data(repeating: 0x33, count: 32)
            let half = Data(SignatureEncoding.halfOrder(of: curve))
            #expect(try SignatureEncoding.lowS(r + half, curve: curve) == r + half)
            #expect(try SignatureEncoding.lowS(r + Data(repeating: 0, count: 31) + [1], curve: curve) == r + Data(repeating: 0, count: 31) + [1])
            var halfPlusOne = [UInt8](half)
            halfPlusOne[31] += 1
            let normalized = try SignatureEncoding.lowS(r + halfPlusOne, curve: curve)
            #expect(SignatureEncoding.compare([UInt8](normalized.suffix(32)), [UInt8](half)) <= 0)
            // n − (n/2 + 1) = n/2 (n est impair).
            #expect(normalized.suffix(32) == half)
        }
    }

    // MARK: Infineon

    @Test("VERIFY PIN : 00 44 00 00 <Lc> <PIN> ; PIN de 4 à 62 octets")
    func verifyPINAPDU() throws {
        #expect(try Infineon2Go.verifyPINAPDU(pin: "1234").hexString == "004400000431323334")
        #expect(throws: ChipError.invalidPINLength) { try Infineon2Go.verifyPINAPDU(pin: "123") }
        #expect(throws: ChipError.invalidPINLength) { try Infineon2Go.verifyPINAPDU(pin: String(repeating: "1", count: 63)) }
    }

    @Test("SIGN : 00 18 01 00 20 <digest> 00")
    func signAPDU() {
        #expect(Infineon2Go.signAPDU(digest: digest).hexString == "0018010020" + digest.hexString + "00")
    }

    @Test("Statuts du PIN (pinError du bridge) : 63Cx, 6983, 6985")
    func pinStatuses() {
        #expect(throws: ChipError.wrongPIN(retriesLeft: 2)) { try Infineon2Go.checkVerifyPIN(APDUResponse(data: Data(), sw1: 0x63, sw2: 0xC2)) }
        #expect(throws: ChipError.pinLocked) { try Infineon2Go.checkVerifyPIN(APDUResponse(data: Data(), sw1: 0x69, sw2: 0x83)) }
        #expect(throws: ChipError.pinRequired) { try Infineon2Go.parseSign(APDUResponse(data: Data(), sw1: 0x69, sw2: 0x85)) }
    }

    @Test("Réponse à SIGN : DER à partir de l'octet 8, mise en r ‖ s low-S")
    func parseSign() throws {
        let der = Data(hex: "3045022100f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f10220fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd036413e")!
        let response = APDUResponse(data: Data([0, 0, 0, 9, 0, 0, 0, 4]) + der, sw1: 0x90, sw2: 0x00)
        #expect(try Infineon2Go.parseSign(response).hexString
            == "f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f10000000000000000000000000000000000000000000000000000000000000003")
    }

    @Test("Signature Infineon : lecture de la clé, même carte vérifiée, SELECT, VERIFY PIN, SIGN")
    func infineonSequence() async throws {
        let card = SigningInfineon(key: MockChipReader.secp256k1Key)
        let signed = try await ChipSigning.sign(card, digest: digest, expectedKey: MockChipReader.secp256k1Key, pin: "1234")
        guard case .secp256k1(let signature) = signed else { Issue.record("expected secp256k1"); return }
        #expect(signature.count == 64)
        #expect(card.sent.suffix(3).map(\.hexString) == [
            Infineon2Go.selectAPDU.hexString, "004400000431323334", "0018010020" + digest.hexString + "00",
        ])
    }

    @Test("Autre carte que celle lue au tap 1 : refus, rien n'est signé")
    func wrongCard() async {
        let card = SigningInfineon(key: MockChipReader.secp256k1Key)
        await #expect(throws: ChipError.wrongCard) {
            try await ChipSigning.sign(card, digest: digest, expectedKey: MockChipReader.p256Key, pin: nil)
        }
        #expect(!card.sent.contains { $0.count > 1 && $0[1] == 0x18 })
    }

    // MARK: DUOX

    @Test("Internal Authenticate : 00 88 00 01 16 80 00 7C 12 81 10 <16 premiers octets du digest> 00")
    func internalAuthenticateAPDU() {
        #expect(Duox.internalAuthenticateAPDU(challenge: digest.prefix(16)).hexString
            == "0088000116" + "8000" + "7c128110" + digest.prefix(16).hexString + "00")
    }

    @Test("Réponse Internal Authenticate : TLV 81 10 RndB et 82 40 r ‖ s")
    func parseInternalAuthenticate() throws {
        let rndB = Data(repeating: 0xAB, count: 16)
        let rs = Data(repeating: 0x22, count: 64)
        let response = APDUResponse(data: Data([0x7C, 0x54, 0x81, 0x10]) + rndB + [0x82, 0x40] + rs, sw1: 0x90, sw2: 0x00)
        let parsed = try Duox.parseInternalAuthenticate(response)
        #expect(parsed.rndB == rndB)
        #expect(parsed.signature == rs)
        #expect(throws: ChipError.self) { try Duox.parseInternalAuthenticate(APDUResponse(data: Data([0x81, 0x10]), sw1: 0x90, sw2: 0x00)) }
        #expect(throws: ChipError.status(command: "Internal Authenticate", statusWord: 0x6982)) {
            try Duox.parseInternalAuthenticate(APDUResponse(data: Data(), sw1: 0x69, sw2: 0x82))
        }
    }
}

/// Infineon simulée qui sait lire sa clé et signer (la signature renvoyée est une DER fixe).
private final class SigningInfineon: APDUTransport {
    private(set) var sent: [Data] = []
    let key: ChipPublicKey

    init(key: ChipPublicKey) { self.key = key }

    func send(_ apdu: Data) async throws -> APDUResponse {
        sent.append(apdu)
        let ok = { (data: Data) in APDUResponse(data: data, sw1: 0x90, sw2: 0x00) }
        if apdu == Infineon2Go.selectAPDU { return ok(Data([0x01])) }
        if apdu.prefix(2) == Data([0x00, 0x16]) { return ok(Data(count: 8) + key.bytes) }
        if apdu.prefix(2) == Data([0x00, 0x44]) { return ok(Data()) }
        if apdu.prefix(2) == Data([0x00, 0x18]) {
            let der = Data(hex: "3044022011111111111111111111111111111111111111111111111111111111111111110220" + String(repeating: "22", count: 32))!
            return ok(Data(count: 8) + der)
        }
        return APDUResponse(data: Data(), sw1: 0x6D, sw2: 0x00)
    }
}
