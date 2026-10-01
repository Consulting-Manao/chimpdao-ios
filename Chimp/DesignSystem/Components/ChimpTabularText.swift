import SwiftUI
import UIKit

/// Chiffres de même largeur pour une police qui n'a pas de chiffres « tabulaires » (Luckiest Guy : le « 1 » est bien
/// plus étroit que le « 0 »). Sans ça, le montant saisi en C2 bouge à chaque touche.
///
/// Chaque chiffre reçoit, après lui, l'espace qui lui manque pour égaler le plus large des dix. Un seul `Text` : la
/// réduction automatique (`minimumScaleFactor`) et l'animation des chiffres (`numericText`) marchent comme avant.
/// Nunito et Space Mono ont déjà des chiffres de même largeur (mesuré le 2026-10-01) : inutile pour elles.
enum ChimpTabularText {
    /// Le texte, avec l'espace qui égalise les chiffres, pour un style ChimpDAO à la taille de texte donnée.
    static func text(_ string: String, style: ChimpTextStyle, dynamicTypeSize: DynamicTypeSize) -> Text {
        let font = style.family.uiFont(size: style.pointSize(for: dynamicTypeSize))
        return Text(attributed(string, font: font))
    }

    /// Chaîne avec l'espace ajouté après chaque chiffre (fonction pure, testée).
    static func attributed(_ string: String, font: UIFont) -> AttributedString {
        let widths = digitWidths(font)
        let widest = widths.values.max() ?? 0
        var result = AttributedString()
        for character in string {
            var piece = AttributedString(String(character))
            if let width = widths[character], width < widest {
                piece.kern = widest - width
            }
            result += piece
        }
        return result
    }

    /// Largeur de chaque chiffre de 0 à 9 dans cette police.
    static func digitWidths(_ font: UIFont) -> [Character: CGFloat] {
        var widths: [Character: CGFloat] = [:]
        for character in "0123456789" {
            widths[character] = (String(character) as NSString).size(withAttributes: [.font: font]).width
        }
        return widths
    }
}
