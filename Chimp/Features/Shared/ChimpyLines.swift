import SwiftUI

/// Textes tirés au hasard, dans le ton de Chimpy (listes validées par Barth le 2026-10-01). Tous dans le String Catalog.
///
/// Jamais pour ce qui touche à la sécurité ou à l'argent : la vérification (C4), le PIN, les erreurs et les montants
/// restent des textes fixes.
enum ChimpyLines {
    /// C9, titre.
    static let sentTitles: [LocalizedStringResource] = ["Swoosh!", "Whoosh!", "Banana express!", "Zip!", "Off it swings!"]

    /// C9, après « Maya has the 5 XLM. ».
    static let sentQuips: [LocalizedStringResource] = [
        "Faster than a monkey on a vine.",
        "Delivered by vine mail.",
        "No banana was harmed.",
        "Chimpy didn't even blink.",
        "Smooth as a ripe banana.",
    ]

    /// Envoi en cours (« Sending… »), sous les étapes.
    static let sending: [LocalizedStringResource] = [
        "Swinging it over…",
        "Hanging on tight…",
        "Climbing the ledger tree…",
        "Almost there, hold the vine…",
    ]

    /// Chargements.
    static let loading: [LocalizedStringResource] = [
        "Counting bananas…",
        "Shaking the tree…",
        "Asking the jungle…",
        "Peeling the latest numbers…",
    ]

    /// États vides (Activity sans mouvement).
    static let empty: [LocalizedStringResource] = [
        "Nothing here yet. The jungle is quiet.",
        "No bananas moved yet.",
        "Empty branch. Your first payment will hang here.",
    ]

    /// Bulle de Chimpy en C1 (« I'll check it twice » et « Monkeys never mix up bananas » remplacés : l'app vérifie le
    /// format d'une adresse, pas la personne).
    static let recipientTips: [LocalizedStringResource] = [
        "No card needed yet. I'll only ask for it at the very end.",
        "I check every address for typos. You check it's the right person.",
        "Tip: Main works with any of your cards.",
    ]
}

extension ChimpyLines {
    /// Une graine à garder dans un `@State` de la vue : le texte est tiré **une fois**, à l'apparition de l'écran, et ne
    /// change pas à chaque rafraîchissement.
    static func seed() -> Int { Int.random(in: 0..<10_000) }

    /// Le texte de la liste pour cette graine.
    static func pick(_ lines: [LocalizedStringResource], seed: Int) -> LocalizedStringResource {
        lines[seed % lines.count]
    }
}
