import SwiftUI

extension View {
    /// Présente une feuille ChimpDAO (feuille système d'iOS habillée comme la maquette) :
    /// hauteur fixe, coins de 34 pt, contour épais, poignée.
    ///
    /// - `isDismissDisabled` : empêche la fermeture par glissement (ex. : pendant l'envoi d'une transaction).
    /// - Aux tailles de texte d'accessibilité, la feuille prend toute la hauteur et son contenu défile.
    /// - Si `height` dépasse l'écran (feuille de scan de 660 pt sur iPhone SE), iOS la ramène
    ///   à la hauteur maximale et son contenu défile (vérifié sur SE le 2026-09-28).
    func chimpSheet<Content: View>(
        isPresented: Binding<Bool>,
        height: CGFloat = ChimpSize.sheetHeight,
        isDismissDisabled: Bool = false,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        sheet(isPresented: isPresented, onDismiss: onDismiss) {
            ChimpSheetContainer(height: height, content: content)
                .interactiveDismissDisabled(isDismissDisabled)
        }
    }
}

/// Habillage d'une feuille : fond, contour, poignée, zone de contenu qui défile si elle déborde.
struct ChimpSheetContainer<Content: View>: View {
    let height: CGFloat
    /// Écart sous la poignée (16 pt dans « Chimp Sign », 14 pt dans la feuille PIN).
    var handleSpacing: CGFloat = ChimpSpacing.l
    @ViewBuilder let content: () -> Content

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.chimpScreenInsets) private var screenInsets

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color(.chimpSurfaceSecondary))
                .frame(width: ChimpSize.sheetHandle.width, height: ChimpSize.sheetHandle.height)
                .padding(.top, ChimpSpacing.lg)
                .padding(.bottom, handleSpacing)
                .accessibilityHidden(true)

            GeometryReader { proxy in
                ScrollView {
                    content()
                        // Dans la maquette, 42 pt sous le contenu incluent la barre d'accueil (34 pt).
                        // Sans barre d'accueil (iPhone SE) : 20 pt, pour ne pas coller au bord de l'écran.
                        .padding(.bottom, screenInsets.hasHomeIndicator ? ChimpSpacing.bottomBar.bottom : ChimpSpacing.xl)
                        .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .top)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .foregroundStyle(.chimpTextPrimary)
        .overlay {
            // Contour de 4 pt en haut et sur les côtés ; le bas passe sous le bord de l'écran.
            UnevenRoundedRectangle(topLeadingRadius: ChimpRadius.sheet, topTrailingRadius: ChimpRadius.sheet)
                .strokeBorder(Color(.chimpOutline), lineWidth: ChimpBorder.thick)
                .padding(.bottom, -ChimpSpacing.xl)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
        }
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(height)])
        .presentationCornerRadius(ChimpRadius.sheet)
        .presentationDragIndicator(.hidden)
        .presentationBackground(Color(.chimpBackground))
    }
}
