import SwiftUI

/// Reçu imprimé (maquette I1.1d) : papier clair dans les deux thèmes, légèrement penché, ombre douce ; en-tête
/// (date et « N° »), titre entre pointillés, lignes, double trait, TOTAL, grand tampon, lien vers l'explorateur,
/// code-barres, « THANKS FOR MONKEYING AROUND », encoches sur les côtés et bord déchiré en dents de scie.
struct ChimpReceiptSlip<Lines: View>: View {
    let header: String
    var number: String?
    let title: String
    var total: String?
    var totalColor: Color = Color(.chimpTicketInk)
    let stamp: LocalizedStringKey
    let stampColor: Color
    var onExplorer: (() -> Void)?
    @ViewBuilder let lines: Lines

    var body: some View {
        VStack(spacing: 0) {
            paper
            ChimpTornEdge()
                .fill(Color(.chimpTicketPaper))
                .frame(height: 12)
                .padding(.horizontal, ChimpBorder.regular)
                .accessibilityHidden(true)
        }
        .compositingGroup()
        .shadow(color: Color(.chimpTicketShadow), radius: 0, x: 4, y: 5)
        .rotationEffect(.degrees(-0.6))
    }

    private var paper: some View {
        VStack(alignment: .leading, spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    Text(header).fixedSize()
                    Spacer(minLength: ChimpSpacing.s)
                    if let number { Text(number).foregroundStyle(Color(.chimpTicketMuted)).fixedSize() }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(header)
                    if let number { Text(number).foregroundStyle(Color(.chimpTicketMuted)) }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .textCase(.uppercase)
            .chimpFont(.label)
            .accessibilityElement(children: .combine)

            ChimpDashedRule().padding(.top, 9).padding(.bottom, 8)
            Text(title)
                .chimpFont(.optionTitle)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            ChimpDashedRule().padding(.top, 9).padding(.bottom, 4)

            lines

            if let total {
                VStack(spacing: 2) {
                    Rectangle().frame(height: 2)
                    Rectangle().frame(height: 2)
                }
                .foregroundStyle(Color(.chimpTicketInk))
                .padding(.top, 6)
                .accessibilityHidden(true)
                HStack(alignment: .lastTextBaseline) {
                    Text("Total").textCase(.uppercase).chimpFont(.label)
                    Spacer(minLength: ChimpSpacing.s)
                    Text(total)
                        .chimpFont(.receiptTotal)
                        .foregroundStyle(totalColor)
                        .multilineTextAlignment(.trailing)
                }
                .padding(.top, 6)
                .accessibilityElement(children: .combine)
            }

            Text(stamp)
                .chimpFont(.stampL)
                .textCase(.uppercase)
                .foregroundStyle(stampColor)
                .tracking(1.5)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 20)
                .padding(.top, 7)
                .padding(.bottom, 3)
                .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(stampColor, lineWidth: 4) }
                .rotationEffect(.degrees(-3))
                .frame(maxWidth: .infinity)
                .padding(.top, ChimpSpacing.xxs)

            if let onExplorer {
                Button(action: onExplorer) {
                    // Flèche en symbole : le caractère « ↗ » s'affiche en émoji.
                    HStack(spacing: 3) {
                        Text(verbatim: "Stellar Expert").underline()
                        Image(systemName: "arrow.up.right").fontWeight(.black).imageScale(.small)
                    }
                    .chimpFont(.receiptLink)
                    .frame(minHeight: ChimpSize.minimumTouchTarget)
                }
                .buttonStyle(ChimpPressableStyle())
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityLabel(Text("View on Stellar Expert"))
            }

            ChimpBarcode()
                .fill(Color(.chimpTicketInk))
                .frame(height: 34)
                .padding(.top, onExplorer == nil ? ChimpSpacing.s : 0)
                .accessibilityHidden(true)
            Text("Thanks for monkeying around")
                .textCase(.uppercase)
                .chimpFont(.labelS)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, ChimpSpacing.xs)
                .accessibilityHidden(true)
        }
        .foregroundStyle(Color(.chimpTicketInk))
        .padding(.horizontal, ChimpSpacing.l)
        .padding(.vertical, ChimpSpacing.m)
        .background(Color(.chimpTicketPaper), in: UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6))
        .overlay {
            ChimpOpenBottomOutline(radius: 6)
                .stroke(Color(.chimpOutline), lineWidth: ChimpBorder.regular)
        }
        .overlay(alignment: .topLeading) { punchHole(leading: true) }
        .overlay(alignment: .topTrailing) { punchHole(leading: false) }
    }

    /// Encoche : un demi-cercle de la couleur du fond, cerclé, dans le bord du papier.
    private func punchHole(leading: Bool) -> some View {
        Circle()
            .fill(Color(.chimpBackground))
            .overlay { Circle().strokeBorder(Color(.chimpOutline), lineWidth: ChimpBorder.regular) }
            // Maquette : cercle de 24 pt (18 + contour), centré sur le bord intérieur du papier, 43 pt sous le haut.
            .frame(width: 24, height: 24)
            .mask(alignment: leading ? .trailing : .leading) { Rectangle().frame(width: 12) }
            .offset(x: leading ? -9 : 9, y: 43)
            .accessibilityHidden(true)
    }
}

/// Une ligne du reçu imprimé : libellé (« TO ») à gauche, valeur à droite, accessoire éventuel (« Copy »).
/// Aux grandes tailles de texte, la valeur passe sous le libellé.
struct ChimpReceiptLine<Value: View, Accessory: View>: View {
    let label: LocalizedStringKey
    @ViewBuilder let value: Value
    @ViewBuilder let accessory: Accessory

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    labelText
                    HStack(spacing: ChimpSpacing.s) { valueText; accessory }
                }
            } else {
                HStack(spacing: ChimpSpacing.s) {
                    labelText.frame(width: 92, alignment: .leading)
                    valueText.frame(maxWidth: .infinity, alignment: .trailing)
                    accessory
                }
            }
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }

    private var labelText: some View {
        Text(label)
            .textCase(.uppercase)
            .chimpFont(.receiptLabel)
            .foregroundStyle(Color(.chimpTicketMuted))
    }

    private var valueText: some View {
        value
            .chimpFont(.receiptValue)
            .multilineTextAlignment(.trailing)
            .fixedSize(horizontal: false, vertical: true)
    }
}

extension ChimpReceiptLine where Accessory == EmptyView {
    init(label: LocalizedStringKey, @ViewBuilder value: () -> Value) {
        self.init(label: label, value: value, accessory: { EmptyView() })
    }
}

/// Petite pastille de couleur d'un tiroir ou d'une carte (ligne FROM du reçu).
struct ChimpReceiptSwatch: View {
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(color)
            .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(Color(.chimpOutline), lineWidth: ChimpBorder.thin) }
            .frame(width: 20, height: 13)
            .accessibilityHidden(true)
    }
}

/// Contour du papier : les côtés et le haut arrondi, sans le bas (le bord déchiré prend le relais).
struct ChimpOpenBottomOutline: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let inset = ChimpBorder.regular / 2
        let r = rect.insetBy(dx: inset, dy: inset)
        var path = Path()
        path.move(to: CGPoint(x: r.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: r.minX, y: r.minY + radius))
        path.addArc(center: CGPoint(x: r.minX + radius, y: r.minY + radius), radius: radius, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.addLine(to: CGPoint(x: r.maxX - radius, y: r.minY))
        path.addArc(center: CGPoint(x: r.maxX - radius, y: r.minY + radius), radius: radius, startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: r.maxX, y: rect.maxY))
        return path
    }
}

/// Bord déchiré : dents de scie de 14 pt pointant vers le bas.
struct ChimpTornEdge: Shape {
    var tooth: CGFloat = 14

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        var x = rect.minX
        while x < rect.maxX {
            let next = min(x + tooth, rect.maxX)
            path.addLine(to: CGPoint(x: (x + next) / 2, y: rect.maxY))
            path.addLine(to: CGPoint(x: next, y: rect.minY))
            x = next
        }
        path.closeSubpath()
        return path
    }
}

/// Code-barres décoratif (motif de la maquette : barres de 2, 3 et 1 pt sur une période de 13 pt).
struct ChimpBarcode: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let bars: [(start: CGFloat, width: CGFloat)] = [(0, 2), (4, 3), (9, 1)]
        var origin = rect.minX
        while origin < rect.maxX {
            for bar in bars where origin + bar.start < rect.maxX {
                path.addRect(CGRect(x: origin + bar.start, y: rect.minY, width: min(bar.width, rect.maxX - origin - bar.start), height: rect.height))
            }
            origin += 13
        }
        return path
    }
}

#Preview {
    ScrollView {
        ChimpReceiptSlip(
            header: "Tue 30 Sep · 14:02", number: "N° 4935984", title: "You paid GCQF…GXPO", total: "−$25.00",
            stamp: "Paid", stampColor: Color(.chimpStampPaid), onExplorer: {}
        ) {
            ChimpReceiptLine(label: "To") { Text(verbatim: "GCQF…GXPO") }
            ChimpReceiptLine(label: "From") {
                HStack(spacing: 6) { ChimpReceiptSwatch(color: ChimpCardColor.jungle.fill); Text(verbatim: "Jungle's wallet") }
            }
            ChimpReceiptLine(label: "Amount") { Text(verbatim: "25.00 USDC") }
        }
        .padding(22)
    }
    .background(Color(.chimpBackground))
}
