import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    FolderAccess.register(with: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}

/// Keeps the sandboxed app's access to a folder the reader picked once
/// (~/TPR, where Claude reads TPR's books), across restarts, with a
/// security-scoped bookmark.
enum FolderAccess {
  static let key = "folderAccessBookmarks"
  static var open: [String: URL] = [:]

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "tpr/folder_access", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      let args = call.arguments as? [String: Any]
      let name = args?["name"] as? String ?? ""
      switch call.method {
      case "pick":
        // macOS's folder picker with our own button and message; the
        // sandbox may then write in the chosen folder.
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        if let dir = args?["directory"] as? String {
          panel.directoryURL = URL(fileURLWithPath: dir, isDirectory: true)
        }
        panel.prompt = args?["button"] as? String ?? "Choose"
        panel.message = args?["message"] as? String ?? ""
        result(panel.runModal() == .OK ? panel.url?.path : nil)
      case "remember":
        guard let path = args?["path"] as? String else { return result(false) }
        do {
          let data = try URL(fileURLWithPath: path, isDirectory: true)
            .bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
          var all = UserDefaults.standard.dictionary(forKey: key) ?? [:]
          all[name] = data
          UserDefaults.standard.set(all, forKey: key)
          result(true)
        } catch {
          result(FlutterError(code: "bookmark", message: error.localizedDescription, details: nil))
        }
      case "start":
        // The folder's path, now readable and writable, or nil if never
        // picked or no longer there.
        guard let data = (UserDefaults.standard.dictionary(forKey: key) ?? [:])[name] as? Data else {
          return result(nil)
        }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope,
                                 relativeTo: nil, bookmarkDataIsStale: &stale),
              url.startAccessingSecurityScopedResource() else {
          return result(nil)
        }
        if stale, let fresh = try? url.bookmarkData(options: .withSecurityScope,
                                                     includingResourceValuesForKeys: nil, relativeTo: nil) {
          var all = UserDefaults.standard.dictionary(forKey: key) ?? [:]
          all[name] = fresh
          UserDefaults.standard.set(all, forKey: key)
        }
        open[name]?.stopAccessingSecurityScopedResource()
        open[name] = url
        result(url.path)
      case "stop":
        open.removeValue(forKey: name)?.stopAccessingSecurityScopedResource()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
