import SwiftUI
import UIKit

/// « Technical details » : sous le message de Chimpy, le texte technique d'une erreur, replié par défaut,
/// sélectionnable et copiable pour le support (règle d'affichage des erreurs du 2026-09-29).
/// Texte technique non traduit (message d'origine du réseau ou de la puce).
struct ChimpTechnicalDetails: View {
    let details: String
    /// Sur un écran plein (fond de l'en-tête) : couleurs claires.
    var onDarkBackground = false

    @State private var isExpanded = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: ChimpSpacing.s) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: ChimpSpacing.xs) {
                    Text("Technical details")
                        .chimpFont(.caption)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.heavy))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .foregroundStyle(secondary)
                .frame(minHeight: ChimpSize.minimumTouchTarget)
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded ? Text("Shown") : Text("Hidden"))

            if isExpanded {
                Text(verbatim: details)
                    .chimpFont(.mono)
                    .foregroundStyle(primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    UIPasteboard.general.string = details
                    copied = true
                } label: {
                    Text(copied ? "Copied!" : "Copy for support")
                        .chimpFont(.caption)
                        .foregroundStyle(secondary)
                        .underline()
                        .frame(minHeight: ChimpSize.minimumTouchTarget)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var primary: Color { onDarkBackground ? Color(.chimpOnHeaderPrimary) : Color(.chimpTextPrimary) }
    private var secondary: Color { onDarkBackground ? Color(.chimpOnHeaderSecondary) : Color(.chimpTextSecondary) }
}

#Preview {
    VStack(spacing: 30) {
        ChimpTechnicalDetails(details: "Stellar RPC error: The request timed out.")
            .padding()
            .background(Color(.chimpBackground))
        ChimpTechnicalDetails(details: "The connection to the card was lost: Tag connection lost", onDarkBackground: true)
            .padding()
            .chimpFullScreenBackground()
    }
}
