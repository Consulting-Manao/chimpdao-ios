import SwiftUI

/// Petite pilule d'action (« + Add ») : fond `chimpSurfaceSecondary`, contour de 2 pt.
/// Visuellement d'environ 25 pt de haut ; sa zone tactile est agrandie à 44 pt sans changer la mise en page.
struct ChimpPillButton: View {
    let title: LocalizedStringKey
    let action: () -> Void

    init(_ title: LocalizedStringKey, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .chimpFont(.pill)
                .foregroundStyle(.chimpTextPrimary)
                .padding(.vertical, ChimpSpacing.xxs + ChimpBorder.thin)
                .padding(.horizontal, 11 + ChimpBorder.thin)
                .background(Capsule().fill(Color(.chimpSurfaceSecondary)))
                .overlay(Capsule().strokeBorder(Color(.chimpOutline), lineWidth: ChimpBorder.thin))
                // Zone tactile étendue de 10 pt au-dessus et en dessous (25 + 2 × 10 ≈ 44 pt).
                .contentShape(Rectangle().inset(by: -ChimpSpacing.sm))
        }
        .buttonStyle(ChimpPressableStyle())
    }
}

#Preview {
    HStack(alignment: .firstTextBaseline) {
        Text("My cards").chimpFont(.displayS)
        Spacer()
        ChimpPillButton("+ Add") {}
    }
    .padding(ChimpSpacing.screenMargin)
    .frame(maxHeight: .infinity)
    .background(Color(.chimpBackground))
}
