import AVFoundation
import SwiftUI

/// Les sons de l'app (répartition de Barth, 2026-10-01 et 2026-10-02). Thème bois et jungle : taps en bois (Kenney, CC0),
/// sons synthétisés pour ChimpDAO, et vrais enregistrements de jungle (feuillages, oiseaux, ruisseau : voir Licenses).
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
    /// Froissement de feuillage en naviguant (nouvel écran, retour, onglet, feuille) : quinze variantes.
    case leaves
    /// Un oiseau au loin, à la place d'un froissement de temps en temps : quatre variantes.
    case bird
    /// Branche qu'on secoue : « tirer pour rafraîchir ».
    case branch

    /// Fichiers du paquet de l'app (`Resources/Sounds/<nom>.caf`).
    var fileNames: [String] {
        switch self {
        case .tap: (1...8).map { "tap\($0)" }
        case .leaves: (1...15).map { "leaves\($0)" }
        case .bird: (1...4).map { "bird\($0)" }
        default: [rawValue]
        }
    }

    /// Son d'ambiance (feuillages, oiseaux, branche) : il ne couvre jamais un son utile.
    var isAmbient: Bool {
        self == .leaves || self == .bird || self == .branch
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
    /// Dernière variante jouée, par son : jamais deux fois la même de suite.
    private var lastVariant: [ChimpSound: String] = [:]
    /// Dernier son utile (tap, confirmation, money…) et dernier froissement : les froissements s'effacent devant eux.
    private var lastUsefulSound = Date.distantPast
    private var lastRustle = Date.distantPast
    private var isSessionReady = false
    let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    var canPlay: Bool { isEnabled() && !isRunningTests }

    func play(_ sound: ChimpSound) {
        guard canPlay else { return }
        if !sound.isAmbient { lastUsefulSound = .now }
        prepareSession()
        guard let name = Self.variant(of: sound, after: lastVariant[sound]), let player = player(named: name) else { return }
        lastVariant[sound] = name
        player.currentTime = 0
        player.play()
    }

    /// Froissement de feuillage en naviguant (retour de Barth du 2026-10-02 : « l'impression de naviguer dans la
    /// jungle ») ; une fois sur 25, un oiseau au loin à la place. Au plus un toutes les 0,4 s, et jamais dans les 0,8 s qui
    /// suivent un son utile : la jungle reste en fond.
    func rustle(now: Date = .now) {
        guard Self.allowsRustle(now: now, lastRustle: lastRustle, lastUseful: lastUsefulSound) else { return }
        lastRustle = now
        play(Self.rustleSound(roll: Int.random(in: 0..<Self.birdOdds)))
    }

    /// Un oiseau une fois sur 25.
    static let birdOdds = 25

    static func rustleSound(roll: Int) -> ChimpSound {
        roll == 0 ? .bird : .leaves
    }

    static func allowsRustle(now: Date, lastRustle: Date, lastUseful: Date) -> Bool {
        now.timeIntervalSince(lastRustle) >= 0.4 && now.timeIntervalSince(lastUseful) >= 0.8
    }

    /// Le fichier à jouer : une variante au hasard, différente de la précédente. Pour les touches, le choix ne dépend
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

/// Easter egg (demande de Barth du 2026-10-02) : un petit ruisseau qui coule en boucle sur la page Licenses, où personne ne
/// va. Il arrive en fondu et repart en fondu ; même règles que les autres sons (réglage « Sounds », bouton silencieux).
@MainActor
final class ChimpAmbience {
    static let shared = ChimpAmbience()

    private var player: AVAudioPlayer?
    private var stopTask: Task<Void, Never>?

    func startStream() {
        guard ChimpSoundPlayer.shared.canPlay else { return }
        stopTask?.cancel()
        if player == nil {
            guard let url = Bundle.main.url(forResource: "stream", withExtension: "caf"),
                  let looping = try? AVAudioPlayer(contentsOf: url)
            else { return }
            looping.numberOfLoops = -1
            looping.volume = 0
            player = looping
        }
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
        player?.play()
        // Discret (retour de Barth du 2026-10-02) : environ 3 dB sous la première version.
        player?.setVolume(0.42, fadeDuration: 1.5)
    }

    /// Arrêt en fondu, un peu différé : passer de la liste des licences à un texte de licence (puis revenir) ne coupe
    /// pas le ruisseau, `startStream` annule l'arrêt.
    func stopStream() {
        guard player != nil else { return }
        stopTask?.cancel()
        stopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.3))
            guard !Task.isCancelled else { return }
            self?.player?.setVolume(0, fadeDuration: 1)
            try? await Task.sleep(for: .seconds(1.1))
            guard !Task.isCancelled else { return }
            self?.player?.stop()
            self?.player = nil
        }
    }
}
