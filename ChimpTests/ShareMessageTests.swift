import Foundation
import Testing
@testable import ChimpDAO

/// Message de « Share » d'un reçu (textes validés par Barth le 2026-10-02).
struct ShareMessageTests {
    static let url = URL(string: "https://stellar.expert/explorer/testnet/tx/abc")!
    static let date = "1 Oct 2026, 14:02"

    @Test("Envoi : montant exact, destinataire court, chute, réseau « play money » sur testnet, preuve en dernier")
    func sent() {
        let text = ShareMessage.text(.sent(to: "GCQF…GXPO"), amount: "25.00 USDC", date: Self.date, network: .testnet, explorerURL: Self.url, hash: "aa")
        let lines = text.components(separatedBy: "\n")
        #expect(lines.count == 4)
        #expect(lines[0] == "🍌 Swoosh! I just sent 25.00 USDC to GCQF…GXPO with ChimpDAO.")
        #expect(ShareMessage.sentPunchlines.contains { String(localized: $0) == lines[1] })
        #expect(lines[2] == "Stellar Testnet (play money) · \(Self.date)")
        #expect(lines[3] == "Proof, straight from the jungle: \(Self.url.absoluteString)")
    }

    @Test("Reçu : l'expéditeur, le tiroir d'arrivée ; sur mainnet, « Stellar » sans « play money »")
    func received() {
        let text = ShareMessage.text(.received(from: "GBTW…FNMB", into: "Main account"), amount: "1,757.5 XLM", date: Self.date, network: .mainnet, explorerURL: Self.url, hash: "bb")
        let lines = text.components(separatedBy: "\n")
        #expect(lines[0] == "🐵 Bananas incoming! GBTW…FNMB sent me 1,757.5 XLM.")
        #expect(ShareMessage.receivedPunchlines.contains { String(localized: $0) == lines[1] })
        #expect(lines[2] == "Landed in my Main account · Stellar · \(Self.date)")
        #expect(!text.contains("play money"))
    }

    @Test("Move et carte ajoutée : pas de lien (rien n'a quitté le compte)")
    func moveAndCard() {
        let move = ShareMessage.text(.moved(from: "Main account", to: "Jungle's wallet"), amount: "50.00 USDC", date: Self.date, network: .testnet, explorerURL: Self.url, hash: "cc")
        #expect(move == "🌴 Moved 50.00 USDC from Main account to Jungle's wallet.\nSame jungle, different branch.\nStellar Testnet (play money) · \(Self.date)")
        let card = ShareMessage.text(.cardAdded(card: "Leaf", approvedBy: "Banana"), amount: nil, date: Self.date, network: .testnet, explorerURL: Self.url, hash: "dd")
        #expect(card.hasPrefix("🃏 Leaf just joined my jungle! Banana said yes.\nThe gang keeps growing."))
        #expect(!card.contains("stellar.expert"))
        let unknown = ShareMessage.text(.cardAdded(card: "Leaf", approvedBy: nil), amount: nil, date: Self.date, network: .testnet, explorerURL: nil, hash: "dd")
        #expect(unknown.hasPrefix("🃏 Leaf just joined my jungle!\n"))
    }

    @Test("Chute : toujours la même pour une transaction, et les trois finissent par sortir")
    func stablePunchline() {
        let hash = String(repeating: "7b3e", count: 16)
        #expect(ShareMessage.pick(ShareMessage.sentPunchlines, hash: hash).key == ShareMessage.pick(ShareMessage.sentPunchlines, hash: hash).key)
        let keys = Set((0..<30).map { ShareMessage.pick(ShareMessage.sentPunchlines, hash: "tx\($0)").key })
        #expect(keys.count == ShareMessage.sentPunchlines.count)
    }
}
