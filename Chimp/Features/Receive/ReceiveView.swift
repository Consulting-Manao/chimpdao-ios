import SwiftUI

/// Écran Recevoir (D1) : choix du tiroir, QR code de son adresse, pilule « Copy », avertissement de Chimpy,
/// partage de l'adresse. Uniquement des composants du design system. Recevoir ne demande jamais la carte.
///
/// États : chargement, erreur réseau (« Try again »), Main, wallet d'une carte (bandeau « seule cette carte… »),
/// un seul tiroir (pas de choix), adresse copiée (« Copied! », retour haptique, annonce VoiceOver).
struct ReceiveView: View {
    @Bindable var model: ReceiveViewModel
    /// Bouton retour affiché seulement si une action est fournie.
    var onBack: (() -> Void)?

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

    private var content: some View {
        let drawer = model.selectedDrawer
        let isLoading = model.phase == .loading
        return GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    drawerPicker(drawer)
                        .redacted(reason: isLoading ? .placeholder : [])

                    if let name = drawer?.cardName, let color = drawer?.cardColor, !isLoading {
                        ChimpNoticeBanner(
                            text: "Only your \(name) card can spend money sent here. Lose the card, lose the money.",
                            marker: .card(color)
                        )
                        .padding(.top, ChimpSpacing.sm)
                    }

                    Spacer(minLength: ChimpSpacing.xxxl)

                    qrCode(drawer, isLoading: isLoading)

                    ChimpAddressPill(address: drawer?.shortAddress ?? "CAAAAAAA…AAAAAA", isCopied: model.isCopied) {
                        model.copyAddress()
                    }
                    .disabled(isLoading)
                    .redacted(reason: isLoading ? .placeholder : [])
                    .padding(.top, ChimpSpacing.l)

                    Spacer(minLength: ChimpSpacing.xl)

                    if !isLoading {
                        // Le réseau d'abord : c'est l'erreur la plus coûteuse (DESIGN_NOTES §12, décisions).
                        ChimpySays(
                            text: "\(model.networkName) only! Money sent from any other network is lost for good. Some apps and exchanges can't send here yet.",
                            pose: .stand
                        )
                    }
                }
                .padding(.horizontal, ChimpSpacing.xxl)
                .padding(.top, ChimpSpacing.l)
                .padding(.bottom, ChimpSpacing.l)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomBar(drawer, isLoading: isLoading)
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
                        .alignmentGuide(.top) { $0.height / 2 }
                }
            }
            .frame(maxWidth: .infinity)
    }

    private func bottomBar(_ drawer: ReceiveViewModel.DrawerContent?, isLoading: Bool) -> some View {
        VStack(spacing: 11) {
            ShareLink(item: drawer?.address ?? "") {
                Text("Share my address")
            }
            .buttonStyle(ChimpButtonStyle())
            .disabled(isLoading || drawer == nil)

            ChimpNavigationRow(title: "Take a payment in person", subtitle: "They tap their Chimp card on your phone") {
                model.takePaymentInPerson()
            }
        }
        .padding(.top, ChimpSpacing.bottomBar.top)
        .padding(.horizontal, ChimpSpacing.bottomBar.leading)
        .padding(.bottom, screenInsets.hasHomeIndicator ? ChimpSpacing.bottomBar.bottom : ChimpSpacing.xl)
        .background(Color(.chimpBackground))
    }

    // MARK: Feuille de choix du tiroir

    private var pickerSheetHeight: CGFloat {
        // Titre, une ligne par tiroir, bulle de Chimpy (maquette C3 : 3 tiroirs).
        CGFloat(300 + 80 * model.drawers.count)
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
                pose: .crawl
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
