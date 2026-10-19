import SwiftUI

/// Le reçu ne peut pas être montré ici (l'historique de l'app manque) : dit clairement, jamais remplacé par un faux.
/// L'opération, elle, est faite : son reçu est dans l'onglet Activity.
struct ReceiptUnavailableNote: View {
    var body: some View {
        ChimpNoticeBanner(text: "The receipt can't be shown here. You'll find it in Activity.", marker: .error)
            .padding(ChimpSpacing.xxl)
    }
}
