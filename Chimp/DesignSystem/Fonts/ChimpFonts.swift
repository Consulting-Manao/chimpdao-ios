import CoreText
import Foundation
import OSLog

/// Enregistre les polices embarquées (Resources/Fonts) auprès du système.
///
/// L'Info.plist est verrouillé : on n'utilise pas la clé `UIAppFonts`,
/// on enregistre les fichiers par code au lancement de l'app (`ChimpApp.init`).
/// Les styles de texte appellent aussi `register()` : les `#Preview`
/// ne passent pas par `ChimpApp` et ont besoin des polices.
///
/// Licences (fichiers copiés à côté des polices) :
/// - Luckiest Guy : Apache 2.0 (LICENSE-LuckiestGuy.txt)
/// - Nunito : SIL Open Font License 1.1 (OFL-Nunito.txt)
/// - Space Mono : SIL Open Font License 1.1 (OFL-SpaceMono.txt)
enum ChimpFonts {
    static let files = [
        "LuckiestGuy-Regular",
        "Nunito-Variable",
        "SpaceMono-Regular",
        "SpaceMono-Bold",
    ]

    private static let logger = Logger(subsystem: "com.consulting-manao.chimp", category: "Fonts")

    /// Ne s'exécute qu'une fois, même si `register()` est appelé plusieurs fois.
    private static let registration: Void = {
        for name in files {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else {
                logger.error("Police introuvable dans l'app : \(name).ttf")
                assertionFailure("Police introuvable dans l'app : \(name).ttf")
                continue
            }
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                let cfError = error?.takeRetainedValue()
                // Déjà enregistrée (ex. : aperçus Xcode) : ce n'est pas une erreur.
                if let cfError, CFErrorGetCode(cfError) == CTFontManagerError.alreadyRegistered.rawValue {
                    continue
                }
                logger.error("Échec de l'enregistrement de \(name).ttf : \(String(describing: cfError))")
                assertionFailure("Échec de l'enregistrement de \(name).ttf")
            }
        }
    }()

    static func register() {
        _ = registration
    }
}
