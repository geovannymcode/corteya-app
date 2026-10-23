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
    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ShopPreferences")!
    let channel = FlutterMethodChannel(name: "com.geovannycode.corteya/preferences", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "readSlug": result(UserDefaults.standard.string(forKey: "barbershop.slug"))
      case "writeSlug":
        if let slug = call.arguments as? String { UserDefaults.standard.set(slug, forKey: "barbershop.slug") }
        else { UserDefaults.standard.removeObject(forKey: "barbershop.slug") }
        result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
    // TODO despliegue: Associated Domains y apple-app-site-association para APP_LINK_HOST.
  }
}
