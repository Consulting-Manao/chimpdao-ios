#if DESIGN_CATALOG
import SwiftUI

/// Composants ajoutés pour Envoyer (C1 à C3) : champ de saisie, messages, destinataires récents,
/// sélecteur « From » avec solde, montant saisi, actif, pastilles rapides, lignes de choix.
struct CatalogSendPartsPage: View {
    let settings: CatalogSettings
    @State private var text = ""
    @State private var chip = 25
    @State private var assetSelection = "usdc"

    var body: some View {
        CatalogPage("Send parts", settings: settings) {
            section("Input field and messages") {
                ChimpInputField {
                    TextField("Stellar address (G…, C… or M…)", text: $text)
                        .chimpFont(.monoValue)
                } accessory: {
                    ChimpPillButton("Paste") {}
                }
                ChimpFieldMessage(text: "Paste it from the app or exchange you're paying.")
                ChimpFieldMessage(text: "One character is off in this address. Copy it again from where you found it.", kind: .error)
                ChimpFieldMessage(text: "Valid Stellar address. Includes memo ID 1234567890", kind: .success)
            }

            section("Recent contacts") {
                ChimpContactRow(name: "Maya", color: .pink, detail: "GCQF…GXPO") {}
                ChimpContactRow(name: "Tom", color: .jungle, detail: "GBTW…FNMB") {}
            }

            section("From picker with balance") {
                ChimpDrawerPicker(label: "From", icon: .main, title: "Main account", balance: "720", balanceAfter: "695 USDC") {}
                ChimpDrawerPicker(label: "From", icon: .card(.jungle), title: "Jungle's wallet", balance: "62.50 USDC") {}
                Text("Long balance: it moves under the name.")
                    .chimpFont(.caption)
                    .foregroundStyle(.chimpTextSecondary)
                ChimpDrawerPicker(label: "From", icon: .card(.banana), title: "Banana's wallet", balance: "1,250.1234567", balanceAfter: "1,000.1234567 XLM") {}
            }

            section("Amount, asset, quick amounts") {
                VStack(spacing: ChimpSpacing.m) {
                    Text(verbatim: "25").chimpFont(.amountEntry)
                    ChimpAssetPill(glyph: .usdc, title: "USDC") {}
                    HStack(spacing: ChimpSpacing.s) {
                        ForEach([10, 25, 50], id: \.self) { value in
                            ChimpChoiceChip(verbatim: "\(value)", isSelected: chip == value) { chip = value }
                        }
                        ChimpChoiceChip("Max", isSelected: false) {}
                    }
                    HStack(spacing: ChimpSpacing.s) {
                        ChimpChoiceChip(verbatim: "250", isSelected: false) {}
                            .disabled(true)
                        Text("Disabled: more than the balance.")
                            .chimpFont(.caption)
                            .foregroundStyle(.chimpTextSecondary)
                    }
                }
                .frame(maxWidth: .infinity)
            }

            section("Option rows (asset sheet)") {
                ChimpOptionRow(title: "USDC", subtitle: "720 USDC in Main account", isSelected: assetSelection == "usdc") {
                    assetSelection = "usdc"
                } icon: {
                    ChimpAssetIcon(glyph: .usdc, size: 38)
                }
                ChimpOptionRow(title: "XLM", subtitle: "400 XLM in Main account", isSelected: assetSelection == "xlm") {
                    assetSelection = "xlm"
                } icon: {
                    ChimpAssetIcon(glyph: .xlm, size: 38)
                }
            }
        }
    }

    private func section(_ title: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: ChimpSpacing.m) {
            CatalogSectionTitle(title)
            content()
        }
    }
}
#endif
