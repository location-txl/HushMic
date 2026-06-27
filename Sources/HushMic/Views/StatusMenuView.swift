import SwiftUI

struct StatusMenuView: View {
  @ObservedObject var appModel: AppModel
  @ObservedObject var localizer: AppLocalizer

  var body: some View {
    Text(appModel.statusTitle(localizer: localizer))
    Text(appModel.deviceTitle(localizer: localizer))
    Text(appModel.permissionTitle(localizer: localizer))
    Text(appModel.lastActionTitle(localizer: localizer))

    Divider()

    Toggle(localizer.text("menu.auto_control"), isOn: $appModel.autoControlEnabled)
    Toggle(localizer.text("menu.launch_at_login"), isOn: $appModel.launchAtLoginEnabled)

    Divider()

    Menu(localizer.text("menu.language")) {
      ForEach(AppLanguage.allCases) { language in
        Button {
          localizer.language = language
        } label: {
          if localizer.language == language {
            Label(languageTitle(language), systemImage: "checkmark")
          } else {
            Text(languageTitle(language))
          }
        }
      }
    }

    Divider()

    Button(localizer.text("menu.refresh")) {
      appModel.refresh()
    }

    Button(localizer.text("menu.authorize_accessibility")) {
      appModel.requestPermissionAuthorizationFlow()
    }

    Button(localizer.text("menu.test_media_key")) {
      appModel.testPlayPause()
    }

    Divider()

    Text(versionTitle())

    Button(localizer.text("menu.quit")) {
      NSApplication.shared.terminate(nil)
    }
  }

  private func languageTitle(_ language: AppLanguage) -> String {
    switch language {
    case .automatic:
      return localizer.text("language.automatic")
    case .zhHans:
      return localizer.text("language.zh_hans")
    case .en:
      return localizer.text("language.english")
    }
  }

  private func versionTitle() -> String {
    let rawVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    let version = rawVersion?.trimmingCharacters(in: .whitespacesAndNewlines)

    if let version, !version.isEmpty {
      return localizer.text("menu.version %@", version)
    }

    return localizer.text("menu.version %@", "dev")
  }
}
