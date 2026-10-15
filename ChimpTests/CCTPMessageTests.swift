import Foundation
import stellarsdk
import Testing
@testable import ChimpDAO

/// Tranche 2, phase 6, étape 1 : messages Circle CCTP (D4). **Garde-fou** (décision de Barth du 2026-10-15 : une erreur
/// d'encodage perd l'argent) : cinq vrais transferts Ethereum Sepolia → Stellar, finalisés sur testnet par
/// `CctpForwarder.mint_and_forward` (relus le 2026-10-15 sur le RPC, messages confirmés « complete » par l'API Iris de
/// Circle) ; notre encodage de `mintRecipient`, `destinationCaller` et `hookData` doit en redonner **exactement** les octets.
/// Le premier vient de la transaction Sepolia `0x57a30e5b…ccb5` (bloc 11 875 025), où l'on retrouve ce même hook data.
struct CCTPMessageTests {
    struct Vector {
        let stellarTx: String
        let at: String
        let message: String
    }

    static let vectors: [Vector] = [
        Vector(stellarTx: "3a58f9adb094e3e6a6f11a8280196cdfd31566a6d60b7a21dee3388df265e01d", at: "2026-10-09T04:56:32Z", message: "00000001000000000000001b8abfa825982d14be2b97d8b74be95744fa2691e01e7d1b8ac777008245e998050000000000000000000000008fe6b999dc680ccfdd5bf7eb0974218be2542daada6f9ee0786c812344d82817ef19b648b4af120f8bd10bf658e6b99eacff24b83de86ac50b47eaf2840fe23e48179551660fd1072fba6f445d4a6bd7af4ab93e000007d0000007d0000000010000000000000000000000001c7d4b196cb0c7b01d743fbc6116a902379c72383de86ac50b47eaf2840fe23e48179551660fd1072fba6f445d4a6bd7af4ab93e00000000000000000000000000000000000000000000000000000000001e8480000000000000000000000000222650f98a19d45b1275842786d4319f5d39d55c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000038474243514154485647454d515749503348414e414d58494346445a52414241494a54474b4c4c4a324658344c375648364158564456354b4b"),
        Vector(stellarTx: "59fba037af9013ad49399b32bd39b1776f52d8eb69aac5950ccbad15d4d579cb", at: "2026-10-09T06:00:17Z", message: "00000001000000000000001b9ee98dcde611e011e8b011f800be7a1693aef3d6cb3f54baefc0fb8b00b172bd0000000000000000000000008fe6b999dc680ccfdd5bf7eb0974218be2542daada6f9ee0786c812344d82817ef19b648b4af120f8bd10bf658e6b99eacff24b83de86ac50b47eaf2840fe23e48179551660fd1072fba6f445d4a6bd7af4ab93e000007d0000007d0000000010000000000000000000000001c7d4b196cb0c7b01d743fbc6116a902379c72383de86ac50b47eaf2840fe23e48179551660fd1072fba6f445d4a6bd7af4ab93e00000000000000000000000000000000000000000000000000000000001e8480000000000000000000000000222650f98a19d45b1275842786d4319f5d39d55c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000038474243514154485647454d515749503348414e414d58494346445a52414241494a54474b4c4c4a324658344c375648364158564456354b4b"),
        Vector(stellarTx: "7e3d6cb84a3d0083c4314cb5f0387bed02e4da783dd62059ec18a4d3679f75ed", at: "2026-10-09T11:39:52Z", message: "00000001000000000000001b9fa803225cf418f9d6fbacadd8f6cff72825d84ffb1f4139bbe87460a255bcad0000000000000000000000008fe6b999dc680ccfdd5bf7eb0974218be2542daada6f9ee0786c812344d82817ef19b648b4af120f8bd10bf658e6b99eacff24b83de86ac50b47eaf2840fe23e48179551660fd1072fba6f445d4a6bd7af4ab93e000007d0000007d0000000010000000000000000000000001c7d4b196cb0c7b01d743fbc6116a902379c72383de86ac50b47eaf2840fe23e48179551660fd1072fba6f445d4a6bd7af4ab93e00000000000000000000000000000000000000000000000000000000001e8480000000000000000000000000e109f20f54055cbc0efa607229b74fdd15e16de70000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000038474243514154485647454d515749503348414e414d58494346445a52414241494a54474b4c4c4a324658344c375648364158564456354b4b"),
        Vector(stellarTx: "8804f39a62c0d5ab28631428bb2e5d20e72599363575fc12d9c123ade44e1681", at: "2026-10-09T10:35:42Z", message: "00000001000000000000001bbb68e384e56275c329b9baab9f27b0e4aa2199db47aeebb95a649e77b31ef9650000000000000000000000008fe6b999dc680ccfdd5bf7eb0974218be2542daada6f9ee0786c812344d82817ef19b648b4af120f8bd10bf658e6b99eacff24b83de86ac50b47eaf2840fe23e48179551660fd1072fba6f445d4a6bd7af4ab93e000007d0000007d0000000010000000000000000000000001c7d4b196cb0c7b01d743fbc6116a902379c72383de86ac50b47eaf2840fe23e48179551660fd1072fba6f445d4a6bd7af4ab93e00000000000000000000000000000000000000000000000000000000001e8480000000000000000000000000e109f20f54055cbc0efa607229b74fdd15e16de70000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000038474243514154485647454d515749503348414e414d58494346445a52414241494a54474b4c4c4a324658344c375648364158564456354b4b"),
        Vector(stellarTx: "bd6e3591a251c848fb218dd423d2cc23af5d253a15db6e877aca538c079a693c", at: "2026-10-09T05:22:17Z", message: "00000001000000000000001b62dceab24f3216eff8695d7c6cc794f8b0c7d75f2b9478f3a3c90868411a34d40000000000000000000000008fe6b999dc680ccfdd5bf7eb0974218be2542daada6f9ee0786c812344d82817ef19b648b4af120f8bd10bf658e6b99eacff24b83de86ac50b47eaf2840fe23e48179551660fd1072fba6f445d4a6bd7af4ab93e000007d0000007d0000000010000000000000000000000001c7d4b196cb0c7b01d743fbc6116a902379c72383de86ac50b47eaf2840fe23e48179551660fd1072fba6f445d4a6bd7af4ab93e0000000000000000000000000000000000000000000000000000000000a7d8c0000000000000000000000000826abf3b74c59b6aec8a0d4af07fe5fc81a0fe0f0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000038474232513659365158573255484e444b37475741374c46495a5a324c54585059323650564454475259424b41445944444936414d524e414d"),
    ]

    static let forwarder = "CA66Q2WFBND6V4UEB7RD4SAXSVIWMD6RA4X3U32ELVFGXV5PJK4T4VSZ"
    static let tokenMessengerMinter = "CDNG7HXAPBWICI2E3AUBP3YZWZELJLYSB6F5CC7WLDTLTHVM74SLRTHP"

    static func message(_ index: Int) throws -> CCTPMessage {
        try CCTPMessage(try #require(Data(hex: vectors[index].message)))
    }

    @Test("Décodage : Sepolia (0) → Stellar (27), 2 USDC (6 décimales), finalité Standard, USDC de Sepolia, TokenMessengerV2")
    func decodes() throws {
        let message = try Self.message(0)
        #expect(message.version == 1)
        #expect(message.sourceDomain == 0)
        #expect(message.destinationDomain == 27)
        #expect(CCTPMessage.evmAddress(message.sender) == "0x8fe6b999dc680ccfdd5bf7eb0974218be2542daa")
        #expect(message.recipient == (try CCTPMessage.bytes32(contract: Self.tokenMessengerMinter)))
        #expect(message.minFinalityThreshold == 2000 && message.finalityThresholdExecuted == 2000)
        #expect(CCTPMessage.evmAddress(message.burn.burnToken) == "0x1c7d4b196cb0c7b01d743fbc6116a902379c7238")
        #expect(message.burn.amount == 2_000_000)
        #expect(message.burn.feeExecuted == 0)
        #expect(CCTPMessage.evmAddress(message.burn.messageSender) == "0x222650f98a19d45b1275842786d4319f5d39d55c")
        #expect(CCTPMessage.stellarAmount(message.burn.amount) == 2)
        #expect(try CCTPMessage.forwardRecipient(in: message.burn.hookData) == "GBCQATHVGEMQWIP3HANAMXICFDZRABAIJTGKLLJ2FX4L7VH6AXVDV5KK")
    }

    @Test("GARDE-FOU : notre encodage du forwarder et du hook data redonne exactement les octets des cinq transferts réels")
    func encodingMatchesRealTransfers() throws {
        let forwarder = try CCTPMessage.bytes32(contract: Self.forwarder)
        for index in Self.vectors.indices {
            let message = try Self.message(index)
            #expect(message.destinationCaller == forwarder, "destinationCaller du transfert \(Self.vectors[index].stellarTx)")
            #expect(message.burn.mintRecipient == forwarder, "mintRecipient du transfert \(Self.vectors[index].stellarTx)")
            let recipient = try CCTPMessage.forwardRecipient(in: message.burn.hookData)
            #expect(try CCTPMessage.hookData(forwardRecipient: recipient) == message.burn.hookData, "hookData du transfert \(Self.vectors[index].stellarTx)")
        }
    }

    @Test("Adresse C d'une carte (notre cas) : 56 caractères, aller-retour exact ; octets réservés nuls, version 0")
    func contractRecipient() throws {
        let main = "CCDO6J7WOGPTKZA73FWECCIJ75TTOMHMCWLEGPYWIFCNSINM63UJDDYB"
        let hook = try CCTPMessage.hookData(forwardRecipient: main)
        #expect(hook.count == 32 + 56)
        #expect(hook.prefix(24) == Data(count: 24))
        #expect([UInt8](hook[24..<32]) == [0, 0, 0, 0, 0, 0, 0, 56])
        #expect(try CCTPMessage.forwardRecipient(in: hook) == main)
    }

    @Test("Refusé avant toute signature : somme de contrôle fausse, adresse tronquée, autre chose qu'une adresse Stellar")
    func refusals() {
        let main = "CCDO6J7WOGPTKZA73FWECCIJ75TTOMHMCWLEGPYWIFCNSINM63UJDDYB"
        let wrongChecksum = String(main.dropLast()) + "A"
        for bad in [wrongChecksum, String(main.dropLast()), "0x222650f98a19d45b1275842786d4319f5d39d55c", "", "GBCQATHVGEMQWIP3HANAMXICFDZRABAIJTGKLLJ2FX4L7VH6AXVDV5KA"] {
            #expect(throws: CCTPMessage.DecodeError.self) { try CCTPMessage.hookData(forwardRecipient: bad) }
        }
        #expect(throws: CCTPMessage.DecodeError.self) { try CCTPMessage.bytes32(contract: "GBCQATHVGEMQWIP3HANAMXICFDZRABAIJTGKLLJ2FX4L7VH6AXVDV5KK") }
        // Hook data abîmé : octets réservés non nuls, version inconnue, longueur trop grande.
        var hook = (try? CCTPMessage.hookData(forwardRecipient: main)) ?? Data()
        hook[0] = 1
        #expect(throws: CCTPMessage.DecodeError.self) { try CCTPMessage.forwardRecipient(in: hook) }
        hook[0] = 0; hook[27] = 1
        #expect(throws: CCTPMessage.DecodeError.self) { try CCTPMessage.forwardRecipient(in: hook) }
        hook[27] = 0; hook[31] = 200
        #expect(throws: CCTPMessage.DecodeError.self) { try CCTPMessage.forwardRecipient(in: hook) }
        #expect(throws: CCTPMessage.DecodeError.self) { try CCTPMessage(Data(count: 100)) }
    }
}
