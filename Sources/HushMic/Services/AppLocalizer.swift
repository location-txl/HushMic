import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
  case automatic
  case zhHans
  case en

  var id: String {
    rawValue
  }

  var lprojName: String? {
    switch self {
    case .automatic:
      return nil
    case .zhHans:
      return "zh-Hans"
    case .en:
      return "en"
    }
  }

  var localeIdentifier: String {
    switch self {
    case .automatic:
      return AppLanguage.resolvedAutomatic.localeIdentifier
    case .zhHans:
      return "zh-Hans"
    case .en:
      return "en"
    }
  }

  static var resolvedAutomatic: AppLanguage {
    let preferred = Bundle.preferredLocalizations(
      from: ["zh-Hans", "en"],
      forPreferences: Locale.preferredLanguages
    )

    return preferred.first == "zh-Hans" ? .zhHans : .en
  }
}

final class AppLocalizer: ObservableObject {
  @Published var language: AppLanguage {
    didSet {
      UserDefaults.standard.set(language.rawValue, forKey: Self.languageDefaultsKey)
    }
  }

  private static let languageDefaultsKey = "appLanguage"

  init() {
    if
      let rawLanguage = UserDefaults.standard.string(forKey: Self.languageDefaultsKey),
      let savedLanguage = AppLanguage(rawValue: rawLanguage)
    {
      language = savedLanguage
    } else {
      language = .automatic
    }
  }

  var resolvedLanguage: AppLanguage {
    switch language {
    case .automatic:
      return AppLanguage.resolvedAutomatic
    case .zhHans, .en:
      return language
    }
  }

  func text(_ key: String, _ arguments: CVarArg...) -> String {
    text(key, arguments: arguments)
  }

  func text(_ key: String, arguments: [CVarArg]) -> String {
    let format = NSLocalizedString(
      key,
      tableName: "Localizable",
      bundle: localizationBundle,
      value: key,
      comment: ""
    )

    guard !arguments.isEmpty else {
      return format
    }

    return String(
      format: format,
      locale: Locale(identifier: resolvedLanguage.localeIdentifier),
      arguments: arguments
    )
  }

  private var localizationBundle: Bundle {
    let language = resolvedLanguage

    guard
      let lprojName = language.lprojName,
      let path = Bundle.main.path(forResource: lprojName, ofType: "lproj"),
      let bundle = Bundle(path: path)
    else {
      return .main
    }

    return bundle
  }
}

indirect enum LocalizedMessage: Equatable {
  case key(String, [LocalizedMessage] = [])
  case coreAudioError(LocalizedMessage, OSStatus)
  case raw(String)

  func resolve(with localizer: AppLocalizer) -> String {
    switch self {
    case .key(let key, let arguments):
      let resolvedArguments: [CVarArg] = arguments.map { $0.resolve(with: localizer) as NSString }
      return localizer.text(key, arguments: resolvedArguments)
    case .coreAudioError(let context, let status):
      return localizer.text(
        "coreaudio.error %@ %lld",
        context.resolve(with: localizer),
        Int64(status)
      )
    case .raw(let text):
      return text
    }
  }
}
