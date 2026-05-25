import SwiftUI
import AppKit

@main
struct ClaudeUsageBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = UsageViewModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Text("✳ \(model.menuBarTitle)")
        }
        .menuBarExtraStyle(.menu)
    }
}

/// Keeps the app in the menu bar only, with no Dock icon or main window.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
