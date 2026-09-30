import SwiftUI

extension View {
    /// Présente une feuille ChimpDAO (feuille système d'iOS habillée comme la maquette) :
    /// hauteur fixe, coins de 34 pt, contour épais, poignée.
    ///
    /// - `isDismissDisabled` : empêche la fermeture par glissement (ex. : pendant l'envoi d'une transaction).
    /// - Aux tailles de texte d'accessibilité, la feuille prend toute la hauteur et son contenu défile.
    /// - Si `height` dépasse l'écran (feuille de scan de 660 pt sur iPhone SE), iOS la ramène
    ///   à la hauteur maximale et son contenu défile (vérifié sur SE le 2026-09-28).
    /// - `fitsContent` : la feuille prend la hauteur de son contenu (mesurée), sans espace vide dessous ; `height` ne sert
    ///   qu'avant la première mesure.
    func chimpSheet<Content: View>(
        isPresented: Binding<Bool>,
        height: CGFloat = ChimpSize.sheetHeight,
        fitsContent: Bool = false,
        isDismissDisabled: Bool = false,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        sheet(isPresented: isPresented, onDismiss: onDismiss) {
            ChimpSheetContainer(height: height, fitsContent: fitsContent, content: content)
                .interactiveDismissDisabled(isDismissDisabled)
        }
    }
}

/// Habillage d'une feuille : fond, contour, poignée, zone de contenu qui défile si elle déborde.
struct ChimpSheetContainer<Content: View>: View {
    /// Poignée et son écart, au-dessus du contenu.
    private var handleArea: CGFloat { ChimpSpacing.lg + ChimpSize.sheetHandle.height + handleSpacing }

    /// Hauteur demandée à iOS : le contenu mesuré (marge du bas comprise) plus la poignée. iOS ajoute lui-même la zone de
    /// la barre d'accueil (vérifié sur simulateur), et ramène la feuille à la hauteur de l'écran si elle dépasse ; le
    /// contenu défile alors.
    private var detentHeight: CGFloat {
        guard fitsContent, let contentHeight else { return height }
        return handleArea + contentHeight
    }

    let height: CGFloat
    /// Écart sous la poignée (16 pt dans « Chimp Sign », 14 pt dans la feuille PIN).
    var handleSpacing: CGFloat = ChimpSpacing.l
    /// Hauteur de la feuille = hauteur du contenu (voir `chimpSheet`).
    var fitsContent = false
    @ViewBuilder let content: () -> Content

    /// Hauteur mesurée du contenu (marge du bas comprise), pour `fitsContent`.
    @State private var contentHeight: CGFloat?

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
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
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
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(detentHeight)])
        .presentationCornerRadius(ChimpRadius.sheet)
        .presentationDragIndicator(.hidden)
        .presentationBackground(Color(.chimpBackground))
    }
}
