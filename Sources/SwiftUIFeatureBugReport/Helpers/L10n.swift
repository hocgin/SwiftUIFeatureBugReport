//
//  L10n.swift
//  SwiftUIFeatureBugReport
//
//  Key-based localisation: every user-facing string is a semantic `feedback.<area>.<name>` key
//  looked up in this package's own bundle, so the board ships translated with no host-app setup.
//
//  Interpolated calls become format keys in the catalogue: `L10n.t("feedback.form.max \(n)")`
//  looks up `"feedback.form.max %lld"`. Integer interpolations pick up plural variations from
//  `Localizable.stringsdict`.
//
//  Push notification keys are the one exception - they resolve against the *host app's* bundle at
//  display time, so they stay as English sentences (see `ActivityKind.localizationKey`).
//

enum L10n {

    /// Resolves a key against this package's `Localizable` table.
    static func t(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .module)
    }
}
