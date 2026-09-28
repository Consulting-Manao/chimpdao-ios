import SwiftUI

/// Champ de saisie (A4, A5, C1) : fond `chimpSurface`, contour 3, rayon 18.
/// Le champ lui-même (`TextField`) est fourni par l'écran ; un accessoire facultatif se place à droite
/// (ex. : bouton « Paste »).
struct ChimpInputField<Field: View, Accessory: View>: View {
    @ViewBuilder let field: Field
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: ChimpSpacing.m) {
            field
                .frame(maxWidth: .infinity, alignment: .leading)
            accessory
        }
        .foregroundStyle(.chimpTextPrimary)
        .tint(Color(.chimpTextPrimary))
        .padding(.vertical, ChimpSpacing.ml + ChimpBorder.regular)
        .padding(.horizontal, ChimpSpacing.l + ChimpBorder.regular)
        .frame(minHeight: ChimpSize.minimumTouchTarget)
        .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.control), fill: Color(.chimpSurface))
    }
}

extension ChimpInputField where Accessory == EmptyView {
    init(@ViewBuilder field: () -> Field) {
        self.init(field: field) { EmptyView() }
    }
}

/// Nature d'un message sous un champ.
enum ChimpFieldMessageKind {
    /// Saisie refusée : texte `chimpNegative`.
    case error
    /// Précision neutre.
    case info
    /// Saisie reconnue (✓ en `chimpPositive`).
    case success
}

/// Message sous un champ de saisie : icône et texte, sur une ou plusieurs lignes.
struct ChimpFieldMessage: View {
    let text: LocalizedStringKey
    var kind: ChimpFieldMessageKind = .info

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: ChimpSpacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(iconColor)
                .accessibilityHidden(true)
            Text(text)
                .chimpFont(.caption)
                .foregroundStyle(kind == .error ? Color(.chimpNegative) : Color(.chimpTextSecondary))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch kind {
        case .error: "exclamationmark.triangle.fill"
        case .info: "info.circle.fill"
        case .success: "checkmark.circle.fill"
        }
    }

    private var iconColor: Color {
        switch kind {
        case .error: Color(.chimpNegative)
        case .info: Color(.chimpTextSecondary)
        case .success: Color(.chimpPositive)
        }
    }
}

/// Ligne d'un destinataire récent (C1) : pastille de couleur avec l'initiale, nom, adresse raccourcie, chevron.
/// Fond `chimpSurface`, contour 3, rayon 18, ombre `3 3`.
struct ChimpContactRow: View {
    let name: String
    let color: ChimpCardColor
    /// Adresse raccourcie (« GBM2…4XQA »), en Space Mono.
    let detail: String
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ChimpRadius.control)
        Button(action: action) {
            HStack(spacing: 13) {
                RoundedRectangle(cornerRadius: 13)
                    .fill(color.fill)
                    .overlay { RoundedRectangle(cornerRadius: 13).strokeBorder(Color(.chimpOutline), lineWidth: ChimpBorder.regular) }
                    .overlay {
                        Text(verbatim: String(name.prefix(1)).uppercased())
                            .chimpFont(.cardName)
                            .foregroundStyle(color.ink)
                    }
                    .frame(width: 42 + 2 * ChimpBorder.regular, height: 42 + 2 * ChimpBorder.regular)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: name)
                        .chimpFont(.optionTitle)
                        .foregroundStyle(.chimpTextPrimary)
                    Text(verbatim: detail)
                        .chimpFont(.mono)
                        .foregroundStyle(.chimpTextSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(.chimpTextSecondary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, ChimpSpacing.m + ChimpBorder.regular)
            .padding(.horizontal, 15 + ChimpBorder.regular)
        }
        .buttonStyle(ChimpSurfaceButtonStyle(shape: shape, fill: Color(.chimpSurface)))
        .accessibilityElement(children: .combine)
    }
}

private struct ChimpInputFieldPreview: View {
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: ChimpSpacing.m) {
            ChimpInputField {
                TextField("Stellar address", text: $text)
                    .chimpFont(.body)
            } accessory: {
                ChimpPillButton("Paste") {}
            }
            ChimpFieldMessage(text: "One character is off. Copy the address again.", kind: .error)
            ChimpFieldMessage(text: "Includes memo ID 1234567890", kind: .success)
            ChimpContactRow(name: "Maya", color: .pink, detail: "GCQF…GXPO") {}
            ChimpContactRow(name: "Tom", color: .jungle, detail: "GBTW…FNMB") {}
        }
        .padding(ChimpSpacing.screenMargin)
        .frame(maxHeight: .infinity)
        .background(Color(.chimpBackground))
    }
}

#Preview("Light") {
    ChimpInputFieldPreview()
}

#Preview("Dark") {
    ChimpInputFieldPreview()
        .preferredColorScheme(.dark)
}
