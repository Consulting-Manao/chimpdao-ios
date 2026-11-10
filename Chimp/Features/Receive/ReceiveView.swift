import SwiftUI

/// Écran Recevoir (D1) : choix du tiroir, QR code de son adresse, pilule « Copy », partage de l'adresse.
/// Uniquement des composants du design system. Recevoir ne demande jamais la carte.
///
/// États : chargement, erreur réseau (« Try again »), Main, wallet d'une carte, un seul tiroir (pas de choix),
/// adresse copiée (« Copied! », retour haptique, annonce VoiceOver).
/// Bulle d'avertissement et bandeau « seule cette carte… » retirés à la demande de Barth (DESIGN_NOTES §12, décisions).
struct ReceiveView: View {
    @Bindable var model: ReceiveViewModel
    /// Bouton retour affiché seulement si une action est fournie.
    var onBack: (() -> Void)?
    /// « Add money from another chain » (D4, sans maquette) : affiché seulement si une action est fournie.
    var onAddMoney: (() -> Void)?

    @Environment(\.chimpScreenInsets) private var screenInsets

    var body: some View {
        VStack(spacing: 0) {
            ChimpHeader(title: "Receive", subtitle: "Anyone can pay you", onBack: onBack)
            switch model.phase {
            case .failed:
                failure
            case .loading, .loaded:
                content
            }
        }
        .background(Color(.chimpBackground))
        .task { await model.loadIfNeeded() }
        .sensoryFeedback(.success, trigger: model.copyCount)
        .onChange(of: model.copyCount) {
            AccessibilityNotification.Announcement(String(localized: "Address copied")).post()
        }
        .chimpSheet(isPresented: $model.isPickerPresented, height: pickerSheetHeight) {
            pickerSheet
        }
    }

    // MARK: Contenu

    /// Comme dans la maquette : le QR et la pilule au centre de l'espace libre, les boutons en bas.
    /// Si la place manque (grandes tailles de texte), tout défile d'un bloc.
    private var content: some View {
        let drawer = model.selectedDrawer
        let isLoading = model.phase == .loading
        return GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    drawerPicker(drawer)
                        .redacted(reason: isLoading ? .placeholder : [])

                    if model.showsTestnetBadge {
                        // Le même avertissement qu'au premier lancement : jamais d'argent réel vers cette adresse.
                        ChimpNoticeBanner(text: TestnetNotice.message, marker: .error)
                            .padding(.top, ChimpSpacing.m)
                    }

                    Spacer(minLength: ChimpSpacing.xl)

                    qrCode(drawer, isLoading: isLoading)

                    ChimpAddressPill(address: drawer?.shortAddress ?? "CAAAAAAA…AAAAAA", isCopied: model.isCopied) {
                        model.copyAddress()
                    }
                    .disabled(isLoading)
                    .redacted(reason: isLoading ? .placeholder : [])
                    .padding(.top, ChimpSpacing.l)

                    Spacer(minLength: ChimpSpacing.xl)

                    bottomActions(drawer, isLoading: isLoading)
                }
                .padding(.horizontal, ChimpSpacing.xxl)
                .padding(.top, ChimpSpacing.l)
                .padding(.bottom, screenInsets.hasHomeIndicator ? ChimpSpacing.bottomBar.bottom : ChimpSpacing.xl)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    @ViewBuilder
    private func drawerPicker(_ drawer: ReceiveViewModel.DrawerContent?) -> some View {
        ChimpDrawerPicker(
            label: "Into",
            icon: drawer?.icon ?? .main,
            title: drawer?.title ?? String(localized: "Main account"),
            action: model.canChooseDrawer ? { model.showPicker() } : nil
        )
    }

    private func qrCode(_ drawer: ReceiveViewModel.DrawerContent?, isLoading: Bool) -> some View {
        ChimpQRCode(message: isLoading ? nil : drawer?.address)
            .accessibilityLabel(Text("QR code of this address"))
            .overlay(alignment: .top) {
                if model.showsTestnetBadge && !isLoading {
                    ChimpTagBadge(text: "Testnet", systemImage: "exclamationmark.triangle.fill")
                        // Taille plafonnée : plus grand, le badge mordrait sur les motifs de repérage du QR
                        // et le code ne se scannerait plus (vérifié en XXXL).
                        .dynamicTypeSize(...DynamicTypeSize.large)
                        // À cheval sur le bord haut de la carte : décalé de la moitié de sa hauteur (≈ 28 pt).
                        // Un décalage ne bouge rien d'autre dans la mise en page (pas de saut sans badge).
                        .offset(y: -ChimpSpacing.ml)
                }
            }
            .frame(maxWidth: .infinity)
    }

    private func bottomActions(_ drawer: ReceiveViewModel.DrawerContent?, isLoading: Bool) -> some View {
        VStack(spacing: 11) {
            ShareLink(item: model.shareText ?? "") {
                Text("Share my address")
            }
            .buttonStyle(ChimpButtonStyle())
            .disabled(isLoading || drawer == nil)

            if let onAddMoney {
                ChimpNavigationRow(title: "Add money from another chain", subtitle: "See a live price from NEAR Intents", action: onAddMoney)
            }
        }
    }

    // MARK: Feuille de choix du tiroir

    private var pickerSheetHeight: CGFloat {
        // Poignée et titre, une ligne par tiroir, bulle de Chimpy (maquette C3 : 3 tiroirs).
        CGFloat(250 + 76 * model.drawers.count)
    }

    private var pickerSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Where should it land?")
                .chimpFont(.sheetTitle)
                .foregroundStyle(.chimpTextPrimary)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: ChimpSpacing.listGap) {
                ForEach(model.drawers) { drawer in
                    ChimpDrawerOptionRow(
                        icon: drawer.icon,
                        title: drawer.title,
                        subtitle: drawer.spendRule,
                        isSelected: drawer.id == model.selectedDrawer?.id
                    ) {
                        model.select(drawerID: drawer.id)
                    }
                }
            }
            .padding(.top, ChimpSpacing.l)

            ChimpySays(
                text: "Main is the easy pick. Money sent to a card's wallet can only be spent with that exact card.",
                pose: .unsure
            )
            .padding(.top, ChimpSpacing.l)
        }
        .padding(.horizontal, ChimpSpacing.xxl)
    }

    // MARK: Erreur

    private var failure: some View {
        ScrollView {
            VStack(spacing: ChimpSpacing.xl) {
                ChimpySays(text: "I can't reach the jungle right now. Check your connection.", pose: .crawl)
                ChimpButton("Try again") {
                    Task { await model.load() }
                }
            }
            .padding(.horizontal, ChimpSpacing.screenMargin)
            .padding(.top, ChimpSpacing.xl)
        }
    }
}

#Preview("Maquette") {
    ReceiveView(model: ReceiveViewModel(dataSource: MockReceiveDataSource()), onBack: {})
}

#Preview("Carte · sombre") {
    ReceiveView(model: ReceiveViewModel(dataSource: MockReceiveDataSource(), initialDrawerID: "0421"), onBack: {})
        .preferredColorScheme(.dark)
}

#Preview("Main seul") {
    ReceiveView(model: ReceiveViewModel(dataSource: MockReceiveDataSource(scenario: .mainOnly)), onBack: {})
}

#Preview("Erreur") {
    ReceiveView(model: ReceiveViewModel(dataSource: MockReceiveDataSource(scenario: .networkError)), onBack: {})
}
