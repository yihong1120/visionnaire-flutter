import Flutter
import FirebaseCore
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private static var didConfigureFirebase = false

  private static func configureFirebaseIfNeeded() {
    guard !didConfigureFirebase else { return }
    FirebaseApp.configure()
    didConfigureFirebase = true
  }

  override init() {
    AppDelegate.configureFirebaseIfNeeded()
    super.init()
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    AppDelegate.configureFirebaseIfNeeded()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "NativeHlsPlayerView"
    ) {
      registrar.register(
        NativeHlsPlayerViewFactory(),
        withId: "visionnaire/native_hls_player"
      )
    }
  }
}
