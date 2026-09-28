import UIKit

/// Presse-papiers, derrière un protocole pour que le ViewModel ne dépende pas d'UIKit et reste testable.
protocol AddressClipboard {
    func copy(_ text: String)
}

/// Presse-papiers d'iOS.
struct SystemAddressClipboard: AddressClipboard {
    func copy(_ text: String) {
        UIPasteboard.general.string = text
    }
}
