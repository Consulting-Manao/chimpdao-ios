import SwiftUI

/// En-tête d'un écran racine d'onglet (Activity, I1) : fond `chimpHeader` + motif, titre en Luckiest Guy 28 et, dessous,
/// une rangée de contenu (les pastilles de filtre). Passe sous la barre d'état comme `ChimpHeader`.
struct ChimpTabHeader<Accessory: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let accessory: Accessory

    @Environment(\.chimpScreenInsets) private var screenInsets

    var body: some View {
        VStack(alignment: .leading, spacing: ChimpSpacing.m) {
            Text(title)
                .chimpFont(.tabTitle)
                .foregroundStyle(.chimpOnHeaderPrimary)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, ChimpSpacing.xl)
            accessory
        }
        .padding(.top, ChimpSpacing.header(for: screenInsets).top)
        .padding(.bottom, ChimpSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            Color(.chimpHeader)
                .overlay { ChimpPattern() }
                .ignoresSafeArea(edges: .top)
        }
    }
}

/// Pastille de filtre sur l'en-tête (« All drawers », « Main », « Jungle ») : jaune avec contour sombre quand elle est
/// choisie, sinon voile sombre et contour clair (maquette I1).
struct ChimpFilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .chimpFont(.tile)
                .lineLimit(1)
                .foregroundStyle(isSelected ? Color(.chimpOnAccent) : Color(.chimpOnHeaderPrimary))
                .padding(.horizontal, 13)
                .padding(.vertical, 6)
                .background(isSelected ? Color(.chimpAccent) : Color(.chimpHeaderShade), in: Capsule())
                .overlay {
                    Capsule().strokeBorder(
                        isSelected ? Color(.chimpOutline) : Color.white.opacity(0.45), lineWidth: ChimpBorder.regular
                    )
                }
                .frame(minHeight: ChimpSize.minimumTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(ChimpPressableStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Tampon d'une ligne du ticket : texte en capitales, encadré de sa couleur, légèrement penché.
struct ChimpStamp: View {
    let text: LocalizedStringKey
    let color: Color
    var tilt: Double = -3

    var body: some View {
        Text(text)
            .chimpFont(.stamp)
            .textCase(.uppercase)
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.top, 4)
            .padding(.bottom, 2)
            .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(color, lineWidth: 2.5) }
            .rotationEffect(.degrees(tilt))
    }
}

/// Ticket de caisse d'une journée (maquette I1) : papier clair dans les deux thèmes, contour, ombre douce, légèrement
/// penché ; en-tête « TODAY · SEP 30 », pointillés, lignes, pointillés, sceau « CHIMPY-CERTIFIED » et total du jour.
struct ChimpTicket<Rows: View>: View {
    let title: String
    let date: String
    var net: String?
    var netColor: Color = Color(.chimpTicketInk)
    var showsSeal = true
    var tilt: Double = 0
    @ViewBuilder let rows: Rows

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Le jour et la date sur une ligne ; aux grandes tailles de texte, l'un sous l'autre (jamais un mot coupé).
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).textCase(.uppercase).fixedSize()
                    Spacer(minLength: ChimpSpacing.s)
                    Text(date).textCase(.uppercase).foregroundStyle(Color(.chimpTicketMuted)).fixedSize()
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).textCase(.uppercase)
                    Text(date).textCase(.uppercase).foregroundStyle(Color(.chimpTicketMuted))
                }
            }
            .chimpFont(.label)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            ChimpDashedRule().padding(.top, 9).padding(.bottom, 4)
            rows
            if showsSeal || net != nil {
                ChimpDashedRule().padding(.top, 6)
                HStack(alignment: .center) {
                    if showsSeal { seal }
                    Spacer(minLength: ChimpSpacing.s)
                    if let net {
                        Text(net)
                            .chimpFont(.greeting)
                            .foregroundStyle(netColor)
                            .multilineTextAlignment(.trailing)
                            .accessibilityLabel(Text("Day total: \(net)"))
                    }
                }
                .padding(.top, ChimpSpacing.s)
            }
        }
        .foregroundStyle(Color(.chimpTicketInk))
        .padding(.vertical, ChimpSpacing.m)
        .padding(.horizontal, ChimpSpacing.l)
        .background(Color(.chimpTicketPaper), in: RoundedRectangle(cornerRadius: 6))
        .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(Color(.chimpOutline), lineWidth: ChimpBorder.regular) }
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(.chimpTicketShadow))
                .offset(x: 4, y: 5)
        }
        .rotationEffect(.degrees(tilt))
    }

    /// Tête de Chimpy en sépia dans un cercle, et « CHIMPY-CERTIFIED » : décoratif.
    private var seal: some View {
        HStack(spacing: 7) {
            Image(.tileHead)
                .resizable()
                .scaledToFit()
                .frame(width: 26)
                .grayscale(1)
                .colorMultiply(Color(.chimpTicketRule))
                .opacity(0.8)
                .frame(width: 30, height: 30)
                .overlay { Circle().strokeBorder(Color(.chimpTicketMuted), lineWidth: 2.5) }
                .clipShape(Circle())
            Text("Chimpy-certified")
                .chimpFont(.seal)
                .textCase(.uppercase)
                .foregroundStyle(Color(.chimpTicketMuted))
        }
        .rotationEffect(.degrees(-4))
        .accessibilityHidden(true)
    }
}

/// Une ligne du ticket : titre et « heure · tiroir », tampon, montant.
/// Aux grandes tailles de texte, le tampon et le montant passent sous le titre.
struct ChimpTicketRow: View {
    let title: String
    let meta: String
    let stamp: LocalizedStringKey
    let stampColor: Color
    var stampTilt: Double = -3
    var amount: String?
    var amountColor: Color = Color(.chimpTicketInk)
    /// Second montant, sous le premier (swap, maquette I1s : « −400 XLM » puis « +99.71 USDC »).
    var secondaryAmount: String?
    var secondaryAmountColor: Color = Color(.chimpStampReceived)
    /// Fond de la ligne (swap : `chimpActivitySwap`), sinon le papier du ticket.
    var background: Color?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: ChimpSpacing.xs) {
                    labels
                    HStack {
                        ChimpStamp(text: stamp, color: stampColor, tilt: stampTilt)
                        Spacer(minLength: ChimpSpacing.s)
                        amountText
                    }
                }
            } else {
                HStack(alignment: .center, spacing: ChimpSpacing.sm) {
                    labels.frame(maxWidth: .infinity, alignment: .leading)
                    ChimpStamp(text: stamp, color: stampColor, tilt: stampTilt)
                    amountText.frame(minWidth: 62, alignment: .trailing)
                }
            }
        }
        .padding(.vertical, background == nil ? ChimpSpacing.xs : ChimpSpacing.s)
        .padding(.horizontal, background == nil ? 0 : 10)
        .background {
            if let background { RoundedRectangle(cornerRadius: 8).fill(background) }
        }
        .contentShape(Rectangle())
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .chimpFont(.ticketTitle)
                .foregroundStyle(Color(.chimpTicketInk))
            Text(meta)
                .chimpFont(.ticketMeta)
                .foregroundStyle(Color(.chimpTicketMuted))
        }
        // Toujours à la ligne, jamais tronqué.
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var amountText: some View {
        if let amount {
            VStack(alignment: .trailing, spacing: 1) {
                Text(amount)
                    .foregroundStyle(amountColor)
                if let secondaryAmount {
                    Text(secondaryAmount)
                        .foregroundStyle(secondaryAmountColor)
                }
            }
            .chimpFont(.ticketAmount)
            .multilineTextAlignment(.trailing)
        }
    }
}

/// Pointillés du ticket.
struct ChimpDashedRule: View {
    var body: some View {
        Line()
            .stroke(Color(.chimpTicketRule), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
            .frame(height: 2)
            .padding(.horizontal, -4)
            .accessibilityHidden(true)
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return path
        }
    }
}

#Preview {
    VStack {
        ChimpTicket(title: "Today", date: "Sep 30", net: "−$12.88", netColor: Color(.chimpStampPaid), tilt: -0.6) {
            ChimpTicketRow(title: "You paid GCQF…GXPO", meta: "14:02 · from Jungle", stamp: "Paid", stampColor: Color(.chimpStampPaid), amount: "−$25.00")
            ChimpTicketRow(title: "Moved to Jungle's wallet", meta: "11:20 · Main → Jungle", stamp: "Moved", stampColor: Color(.chimpTicketMuted), stampTilt: 2, amount: "$50.00")
            ChimpTicketRow(title: "GBTW…FNMB paid you", meta: "09:00 · into Main", stamp: "Got it", stampColor: Color(.chimpStampReceived), amount: "+$0.12", amountColor: Color(.chimpStampReceived))
        }
    }
    .padding(26)
    .background(Color(.chimpBackground))
}
