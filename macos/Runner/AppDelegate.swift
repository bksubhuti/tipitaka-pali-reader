import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {


// Add this method to handle Universal Links (e.g. from WhatsApp)
  override func application(_ application: NSApplication,
                            continue userActivity: NSUserActivity,
                            restorationHandler: @escaping ([NSUserActivityRestoring]) -> Void) -> Bool {
      
      // 1. Check if this is a web browsing activity (HTTPS link)
      if userActivity.activityType == NSUserActivityTypeBrowsingWeb,
          let incomingURL = userActivity.webpageURL {
          
          // 2. Convert "https://" to "tpr.pali.tools://"
          //    This forces the app to treat it exactly like the Chrome redirect!
          var components = URLComponents(url: incomingURL, resolvingAgainstBaseURL: true)
          components?.scheme = "tpr.pali.tools" // <--- The Magic Switch
          
          if let customSchemeURL = components?.url {
              // 3. Re-open the URL using the custom scheme
              NSWorkspace.shared.open(customSchemeURL)
              return true
          }
      }
      
      return super.application(application, continue: userActivity, restorationHandler: restorationHandler)
  }
  
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
