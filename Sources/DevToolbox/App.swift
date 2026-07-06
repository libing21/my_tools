import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Regular activation policy so the window and Dock icon behave normally.
        NSApp.setActivationPolicy(.regular)

        // A bare NSApplication has no menu, which means the standard Edit menu
        // items (Cut/Copy/Paste/Select All) are never installed — and those are
        // what wire ⌘C/⌘V/⌘X/⌘A into the responder chain. Build the menu so
        // copy/paste works in every text field.
        NSApp.mainMenu = Self.makeMainMenu()

        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let initialWidth = min(max(visibleFrame.width * 0.82, 1180), 1500)
        let initialHeight = min(max(visibleFrame.height * 0.82, 760), 980)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: initialWidth, height: initialHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "DevToolbox"
        window.minSize = NSSize(width: 1100, height: 720)
        window.center()
        window.titlebarAppearsTransparent = false
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ContentView())
        self.window = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        HotKeyManager.shared.register { [weak self] in
            self?.toggleWindow()
        }
    }

    /// Cmd+Shift+Space behavior: if the app is frontmost and visible, hide it;
    /// otherwise bring the window to front and focus it.
    private func toggleWindow() {
        guard let window = window else { return }
        if NSApp.isActive && window.isVisible {
            NSApp.hide(nil)
        } else {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    /// Standard macOS main menu. The App menu provides Hide/Quit; the Edit menu
    /// provides Undo/Redo/Cut/Copy/Paste/Select All. AppKit routes these to the
    /// first responder, so they work in any focused text field.
    static func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        let appName = "DevToolbox"
        appMenu.addItem(withTitle: "隐藏 \(appName)",
                        action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "隐藏其他",
                        action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 \(appName)",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // Edit menu
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "编辑")
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        return mainMenu
    }
}

@main
struct DevToolboxApp {
    static func main() {
        // Headless self-test path: exercises core tool logic without launching
        // the GUI. Used for CI / verification on machines without a display.
        if CommandLine.arguments.contains("--selftest") {
            SelfTest.run()
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
