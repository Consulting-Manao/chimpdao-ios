import SwiftUI

/// Grande carte-choix avec un titre et une explication (« choix radio en cartes », A3, F5, H1).
/// Le choix mis en avant est jaune ; un choix pas encore disponible est grisé avec un badge « Coming soon ».
struct ChimpChoiceCard: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    var isHighlighted = false
    /// `false` : grisé, non touchable, avec le badge « Coming soon ».
    var isAvailable = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: ChimpSpacing.xxs) {
                HStack(alignment: .firstTextBaseline, spacing: ChimpSpacing.s) {
                    Text(title)
                        .chimpFont(.displayS)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if !isAvailable {
                        Text("Coming soon")
                            .chimpFont(.labelS)
                            .textCase(.uppercase)
                            .padding(.horizontal, ChimpSpacing.s)
                            .padding(.vertical, ChimpSpacing.xxs)
                            .background(Capsule().fill(Color(.chimpSurfaceSecondary)))
                            .overlay(Capsule().strokeBorder(Color(.chimpOutline), lineWidth: ChimpBorder.thin))
                    }
                }
                Text(detail)
                    .chimpFont(.bodyM)
                    .lineSpacing(3)
                    .foregroundStyle(isHighlighted ? Color(.chimpOnAccent) : Color(.chimpTextSecondary))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(isHighlighted ? Color(.chimpOnAccent) : Color(.chimpTextPrimary))
            .padding(ChimpSpacing.l + ChimpBorder.regular)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(ChimpSurfaceButtonStyle(
            shape: RoundedRectangle(cornerRadius: ChimpRadius.chimpCard),
            fill: isHighlighted ? Color(.chimpAccent) : Color(.chimpSurface),
            shadow: .card
        ))
        .disabled(!isAvailable)
        .accessibilityHint(isAvailable ? Text(verbatim: "") : Text("Coming soon"))
    }
}

#Preview {
    VStack(spacing: ChimpSpacing.blockGap) {
        ChimpChoiceCard(title: "Start a new account", detail: "This card becomes the first key of a brand-new account.", isHighlighted: true) {}
        ChimpChoiceCard(title: "Join an account I already have", detail: "You'll tap one of that account's cards next, to let this one in.", isAvailable: false) {}
    }
    .padding(ChimpSpacing.screenMargin)
    .background(Color(.chimpBackground))
}
