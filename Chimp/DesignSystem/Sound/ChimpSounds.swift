import AVFoundation
import SwiftUI

/// Les trois petits sons de l'app (retour du call avec Pamphile, 2026-10-01).
enum ChimpSound: String, CaseIterable {
    /// Une carte a bien été lue ou a signé (et un code QR lu).
    case tap
    /// Un envoi ou un Move est arrivé (C9).
    case sent
    /// Quelque chose n'a pas marché (PIN faux, carte refusée, envoi raté).
    case error

    /// Fichier du paquet de l'app (`Resources/Sounds/<nom>.caf`). Absent : pas de son, sans erreur.
    var url: URL? { Bundle.main.url(forResource: rawValue, withExtension: "caf") }
}

/// Joue les sons de l'app.
///
/// - **Bouton silencieux de l'iPhone** respecté : catégorie audio `.ambient` (se tait en mode silencieux, ne coupe pas la
///   musique de l'utilisateur, s'y mélange).
/// - **Réglage « Sounds »** (I2) : `isEnabled`, branché sur `AppPreferences.soundsEnabled` au lancement.
/// - Aucun son pendant les tests unitaires (le simulateur joue sur les haut-parleurs du Mac).
@MainActor
final class ChimpSoundPlayer {
    static let shared = ChimpSoundPlayer()

    /// Réglage « Sounds ». Par défaut : activé.
    var isEnabled: () -> Bool = { true }

    private var players: [ChimpSound: AVAudioPlayer] = [:]
    private var isSessionReady = false
    private let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    func play(_ sound: ChimpSound) {
        guard isEnabled(), !isRunningTests else { return }
        prepareSession()
        guard let player = player(for: sound) else { return }
        player.currentTime = 0
        player.play()
    }

    private func prepareSession() {
        guard !isSessionReady else { return }
        isSessionReady = true
        // `.ambient` : muet quand l'iPhone est en silencieux ; mélangé à l'audio des autres apps.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
    }

    private func player(for sound: ChimpSound) -> AVAudioPlayer? {
        if let player = players[sound] { return player }
        guard let url = sound.url, let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        // Discrets : sous le volume des autres sons de l'iPhone.
        player.volume = 0.6
        player.prepareToPlay()
        players[sound] = player
        return player
    }
}

extension View {
    /// Joue `sound` quand `trigger` change et que `condition(ancienne, nouvelle)` est vraie (comme `sensoryFeedback`).
    func chimpSound<Value: Equatable>(
        _ sound: ChimpSound, trigger: Value, condition: @escaping (Value, Value) -> Bool = { _, _ in true }
    ) -> some View {
        onChange(of: trigger) { old, new in
            if condition(old, new) { ChimpSoundPlayer.shared.play(sound) }
        }
    }
}
