import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: "whatswave/app_settings",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "openAppSettings":
        Self.openThisAppSettings { opened in
          result(opened)
        }
      case "deviceRegionCode":
        if #available(iOS 16, *) {
          result(Locale.current.region?.identifier)
        } else {
          result(Locale.current.regionCode)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// Opens Settings → Whatswave (mic/camera/photos/etc), not the Settings root.
  /// iOS 18+ often sends `openSettingsURLString` to the root unless the app
  /// has a Settings.bundle *and* we try the Apps page URL first.
  private static func openThisAppSettings(completion: @escaping (Bool) -> Void) {
    let bundleId = Bundle.main.bundleIdentifier ?? ""
    if let appsPage = URL(string: "settings-navigation://com.apple.Settings.Apps/\(bundleId)") {
      UIApplication.shared.open(appsPage, options: [:]) { openedAppsPage in
        if openedAppsPage {
          completion(true)
          return
        }
        openOfficialAppSettings(completion: completion)
      }
      return
    }
    openOfficialAppSettings(completion: completion)
  }

  private static func openOfficialAppSettings(completion: @escaping (Bool) -> Void) {
    guard let settingsUrl = URL(string: UIApplication.openSettingsURLString) else {
      completion(false)
      return
    }
    UIApplication.shared.open(settingsUrl, options: [:], completionHandler: completion)
  }
}
