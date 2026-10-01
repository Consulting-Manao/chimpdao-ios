import Foundation
import SwiftUI
import Testing
@testable import ChimpDAO

/// Retours du call avec Pamphile (2026-10-01), thème 3 : sons, textes tirés au hasard, bananes de C9.
struct PersonalityTests {
    @Test("Réglage « Sounds » : activé par défaut, gardé, remis à zéro par « Erase everything »")
    func soundsPreference() {
        let store = InMemoryPreferencesStore()
        let preferences = AppPreferences(store: store)
        #expect(preferences.soundsEnabled)
        preferences.soundsEnabled = false
        #expect(store.values[.sounds] == "off")
        #expect(!AppPreferences(store: store).soundsEnabled, "Relu au prochain lancement")
        preferences.reset()
        #expect(preferences.soundsEnabled)
        #expect(store.values.isEmpty)
    }

    @Test("Sons du parcours Envoyer : la carte signe (tap), l'argent arrive (sent), rien n'est parti ou mauvaise carte (error)")
    func signingSounds() {
        #expect(SigningStage.sending(.checking).sound == .tap)
        #expect(SigningStage.finished(.nothingSent).sound == .error)
        #expect(SigningStage.finished(.waiting(until: .now)).sound == .error)
        #expect(SigningStage.finished(.notConfirmed).sound == nil, "Envoyé, pas encore confirmé : ni victoire ni erreur")
        #expect(SigningStage.idle.sound == nil)
        #expect(SigningStage.enteringPin.sound == nil)
    }

    @Test("Sons de l'ajout de carte : un tap réussi fait avancer, la carte ajoutée, jamais en reculant")
    func addCardSounds() {
        #expect(AddCardFlowView.sound(from: .tapNew, to: .nameCard) == .tap)
        #expect(AddCardFlowView.sound(from: .confirm, to: .unlockCode) == .tap)
        #expect(AddCardFlowView.sound(from: .member, to: .adding) == .tap)
        #expect(AddCardFlowView.sound(from: .adding, to: .done) == .sent)
        #expect(AddCardFlowView.sound(from: .nameCard, to: .tapNew) == nil)
        #expect(AddCardFlowView.sound(from: .nameCard, to: .pin) == nil)
    }

    @Test("Textes au hasard : listes non vides, tirage stable pour une même graine, jamais hors de la liste")
    func randomLines() {
        let lists = [ChimpyLines.sentTitles, ChimpyLines.sentQuips, ChimpyLines.sending, ChimpyLines.loading,
                     ChimpyLines.empty, ChimpyLines.recipientTips]
        for list in lists {
            #expect(!list.isEmpty)
            for seed in [0, 1, 7, 9_999] {
                #expect(ChimpyLines.pick(list, seed: seed).key == ChimpyLines.pick(list, seed: seed).key)
                #expect(list.contains { $0.key == ChimpyLines.pick(list, seed: seed).key })
            }
        }
        #expect(ChimpyLines.recipientTips.contains { $0.key == "I check every address for typos. You check it's the right person." })
        #expect(!ChimpyLines.recipientTips.contains { $0.key.contains("twice") }, "L'app vérifie le format, pas la personne")
    }

    @Test("Bananes de C9 : rien avant le départ ni après la sortie ; elles partent d'en bas et sortent par le haut")
    func flyingBanana() throws {
        let banana = FlyingBanana(startX: 0.2, endX: 0.7, arc: 0.1, side: 40, turns: 1, delay: 0.3)
        let size = CGSize(width: 400, height: 800)
        #expect(banana.frame(at: 0.1, in: size) == nil)
        #expect(banana.frame(at: 0.3 + ChimpMotion.BananaBurst.duration + 0.01, in: size) == nil)
        let first = try #require(banana.frame(at: 0.3, in: size))
        let last = try #require(banana.frame(at: 0.3 + ChimpMotion.BananaBurst.duration, in: size))
        #expect(first.center.y > size.height, "Part sous l'écran")
        #expect(last.center.y < 0, "Sort par le haut")
        #expect(abs(last.angle.degrees) == 360)
        for _ in 0..<50 {
            let random = FlyingBanana.random()
            #expect(random.delay >= 0 && random.delay <= ChimpMotion.BananaBurst.spread)
            #expect(random.side >= 34 && random.side <= 58)
        }
    }
}
