//
//  OtterApp.swift
//  Otter
//
//  Created by Tim Mahoney on 12/16/23.
//

import SwiftUI
import UniformTypeIdentifiers

@main
struct OtterApp : App {
    
    @Environment(\.openWindow) var openWindow
    @AppStorage("OTDebug") var showDebugMenu = false
    
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    /// We need some sort of @State to put in the "Slow Loading" menu toggle.
    /// The actual data is stored in `Database`
    @State var slowLoading = Database.slowLoading
    
    let savedQueries = SavedQueries()
    
    static let aboutWindowID = "about"

    var body: some Scene {
        
        DocumentGroup(viewing: Database.self) { documentConfiguration in
            let database = documentConfiguration.document
            ContentView(database: database)
        }
        .defaultSize(width: 1234, height: 789)
        .windowToolbarStyle(.unifiedCompact)
        .environment(self.savedQueries)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Otter") {
                    do {
                        try Self.showAboutWindow()
                    } catch {
                        Logger.ui.fault("Failed to show about window...weird... \(error)")
                    }
                }
            }
            
            CommandGroup(before: .newItem) {
                Button("New Window") {
                    // NSDocument `makeWindowControllers` and adds a new controller to `windowControllers`.
                    // Get that new window controller and show it.
                    if let currentDocument = NSDocumentController.shared.currentDocument {
                        let before = Set(currentDocument.windowControllers)
                        currentDocument.makeWindowControllers()
                        let after = Set(currentDocument.windowControllers)
                        let controllersToShow = after.subtracting(before)
                        for windowController in controllersToShow {
                            windowController.showWindow(nil)
                        }
                        
                        Analytics.track("New Window")
                    }
                }
                .keyboardShortcut("N")
            }
            
            // I can't seem to find a way to automatically show a "Find" menu bar item for our table view.
            // So, instead of doing things the "right" way, let's just get this shit done.
            CommandGroup(before: .textEditing) {
                Button("Find…") {
                    Analytics.track("Show Find Interface")
                    self.sendFindAction(.showFindInterface)
                }
                .keyboardShortcut("F")
                
                Button("Find Next") {
                    Analytics.track("Find Next")
                    self.sendFindAction(.nextMatch)
                }
                .keyboardShortcut("G")
                
                Button("Find Previous") {
                    Analytics.track("Find Previous")
                    self.sendFindAction(.previousMatch)
                }
                .keyboardShortcut("G", modifiers: [.command, .shift])
            }
            
            if self.showDebugMenu {
                CommandMenu("Debug") {
                    Toggle(isOn: self.$slowLoading) {
                        Text("Slow Loading")
                    }
                    .onChange(of: self.slowLoading) { oldValue, newValue in
                        Database.slowLoading = newValue
                    }
                    
                    Button("Reset Saved Filters") {
                        let count = self.savedQueries.savedQueries.count
                        Analytics.track("Reset Saved Filters", [
                            .analytics_savedFilterCount: count,
                        ])
                        self.savedQueries.reset()
                    }
                    
                    Button("Reset Tutorial") {
                        AppDelegate.didShowTutorial = false
                    }
                }
            }
        }
        
        Window("Otter", id: Self.aboutWindowID) {
            AboutView()
        }
        .windowResizability(.contentSize)
        .handlesExternalEvents(matching: [Self.aboutWindowID])
    }
    
    func sendFindAction(_ action: NSTextFinder.Action) {
        NSApplication.shared.sendAction(
            #selector(NSResponder.performTextFinderAction(_:)),
            to: nil,
            from: TextFinderAction(action)
        )
    }
    
    static func showAboutWindow() throws {
        var urlComponents = URLComponents()
        urlComponents.scheme = "otter"
        urlComponents.path = Self.aboutWindowID
        if let url = urlComponents.url {
            NSWorkspace.shared.open(url)
        } else {
            Logger.ui.error("Unable to create URL from components: \(urlComponents)")
            throw CocoaError(.fileNoSuchFile)
        }
    }
}

class AppDelegate : NSObject, NSApplicationDelegate {
    
    @AppStorage("OTDidShowTutorial") static var didShowTutorial = false
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        if !Self.didShowTutorial {
            Logger.ui.log("Haven't shown tutorial yet")
            
            do {
                try OtterApp.showAboutWindow()
                Self.didShowTutorial = true
            } catch {
                Logger.ui.fault("Failed to show tutorial: \(error)")
            }
        }
    }
}
