#if DESIGN_CATALOG
import SwiftUI

/// Tous les boutons, dans leurs quatre états : normal, pressé, désactivé, chargement.
struct CatalogButtonsPage: View {
    let settings: CatalogSettings
    @State private var loadingDemo = false

    var body: some View {
        CatalogPage("Buttons", settings: settings) {
            Text("The first button of each group is live: press it to feel the pressed state (and the light haptic on primary buttons). The others show each state frozen.")
                .chimpFont(.body)
                .foregroundStyle(.chimpTextSecondary)

            VStack(alignment: .leading, spacing: ChimpSpacing.m) {
                CatalogSectionTitle("Loading demo")
                ChimpButton("Tap to load for 2 seconds", isLoading: loadingDemo) {
                    loadingDemo = true
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        loadingDemo = false
                    }
                }
            }

            group("Primary · large", kind: .primary, size: .large, title: "Let's start")
            group("Primary", kind: .primary, size: .regular, title: "Looks good")
            group("Primary · compact", kind: .primary, size: .compact, title: "Send")
            group("Secondary", kind: .secondary, size: .regular, title: "No, stop")
            group("Secondary · raised", kind: .secondary, size: .regular, raised: true, title: "My banana stash")
            group("Secondary · compact", kind: .secondary, size: .compact, title: "Move")
            group("Destructive", kind: .destructive, size: .regular, title: "Disconnect this phone")
            group("Link", kind: .link, size: .regular, title: "Cancel")
            group("On header", kind: .onHeader, size: .regular, title: "Where do I get a real one?", onHeader: true)
            group("Link on header", kind: .linkOnHeader, size: .regular, title: "I don't have a card yet", onHeader: true)
        }
    }

    private func group(
        _ name: LocalizedStringKey,
        kind: ChimpButtonKind,
        size: ChimpButtonSize,
        raised: Bool = false,
        title: LocalizedStringKey,
        onHeader: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: ChimpSpacing.m) {
            CatalogSectionTitle(name)
            VStack(alignment: .leading, spacing: ChimpSpacing.m) {
                state("Normal") {
                    ChimpButton(title, kind: kind, size: size, raised: raised) {}
                }
                state("Pressed") {
                    ChimpButtonFace(kind: kind, size: size, raised: raised, isPressed: true) { Text(title) }
                        .accessibilityHidden(true)
                }
                state("Disabled") {
                    ChimpButton(title, kind: kind, size: size, raised: raised) {}
                        .disabled(true)
                }
                state("Loading") {
                    ChimpButton(title, kind: kind, size: size, raised: raised, isLoading: true) {}
                }
            }
            .padding(onHeader ? ChimpSpacing.l : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if onHeader {
                    Color(.chimpHeader)
                        .overlay { ChimpPattern() }
                        .clipShape(RoundedRectangle(cornerRadius: ChimpRadius.control))
                }
            }
        }
    }

    private func state(_ label: LocalizedStringKey, @ViewBuilder button: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: ChimpSpacing.xs) {
            Text(label).chimpFont(.captionS).foregroundStyle(.chimpTextSecondary)
                .padding(.horizontal, ChimpSpacing.xs)
                .background(Color(.chimpBackground), in: Capsule())
            button()
        }
    }
}

#Preview {
    NavigationStack {
        CatalogButtonsPage(settings: CatalogSettings())
    }
}
#endif
