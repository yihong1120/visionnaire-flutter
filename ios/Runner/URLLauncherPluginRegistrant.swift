import Flutter
import url_launcher_ios

@objc final class URLLauncherPluginRegistrant: NSObject {
  @objc static func register(with registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "URLLauncherPlugin") else {
      return
    }
    URLLauncherPlugin.register(with: registrar)
  }
}
