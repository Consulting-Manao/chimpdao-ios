import AVFoundation
import SwiftUI

/// Les sons de l'app (retour du call avec Pamphile, 2026-10-01 ; répartition de Barth). Tous de Kenney (CC0), choisis
/// pour ressembler au plus près aux sons Artlist que Barth avait sélectionnés (timbre, attaque, durée, volume).
enum ChimpSound: String, CaseIterable {
    /// Touche du pavé du montant : huit variantes, tirées au hasard, jamais deux fois la même de suite.
    case tap
    /// Ça a marché : la carte a signé ou a été lue, un QR lu, une étape franchie.
    case confirmation
    /// L'argent a bougé : envoi ou Move confirmé (C9).
    case money
    /// Ça fait mal : mauvaise carte, PIN faux.
    case hurt
    /// Un souci technique : réseau, lecture NFC ratée, code refusé, rien n'est parti.
    case error
    /// Pour rire : « Sounds » activé dans les réglages.
    case wood

    /// Fichiers du paquet de l'app (`Resources/Sounds/<nom>.caf`).
    var fileNames: [String] {
        self == .tap ? (1...8).map { "tap\($0)" } : [rawValue]
    }

    /// Absents : pas de son, sans erreur.
    var urls: [URL] {
        fileNames.compactMap { Bundle.main.url(forResource: $0, withExtension: "caf") }
    }
}

/// Joue les sons de l'app. Leurs volumes relatifs sont dans les fichiers (alignés sur les sons de référence de Barth).
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

    private var players: [String: AVAudioPlayer] = [:]
    private var lastTap: String?
    private var isSessionReady = false
    private let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    func play(_ sound: ChimpSound) {
        guard isEnabled(), !isRunningTests else { return }
        prepareSession()
        guard let name = Self.variant(of: sound, after: lastTap), let player = player(named: name) else { return }
        if sound == .tap { lastTap = name }
        player.currentTime = 0
        player.play()
    }

    /// Le fichier à jouer : pour les touches, une variante au hasard, différente de la précédente. Le choix ne dépend
    /// jamais de la touche tapée (aucune information sur ce qui est saisi).
    static func variant(of sound: ChimpSound, after last: String?) -> String? {
        let names = sound.fileNames
        guard names.count > 1 else { return names.first }
        return names.filter { $0 != last }.randomElement()
    }

    private func prepareSession() {
        guard !isSessionReady else { return }
        isSessionReady = true
        // `.ambient` : muet quand l'iPhone est en silencieux ; mélangé à l'audio des autres apps.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
    }

    private func player(named name: String) -> AVAudioPlayer? {
        if let player = players[name] { return player }
        guard let url = Bundle.main.url(forResource: name, withExtension: "caf"),
              let player = try? AVAudioPlayer(contentsOf: url)
        else { return nil }
        // Discrets : sous le volume des autres sons de l'iPhone (l'équilibre entre les sons est dans les fichiers).
        player.volume = 0.7
        player.prepareToPlay()
        players[name] = player
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
