import SwiftUI
import AppKit

@main
struct AudioAssistApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
        .handlesExternalEvents(matching: Set(arrayLiteral: "audioassist"))
    }
}

// AppDelegate ile tek instance garantisi - DÜZELTİLDİ + CRASH PREVENTION
class AppDelegate: NSObject, NSApplicationDelegate {
    private var isInstanceCheckCompleted = false
    private var isAppFullyLoaded = false
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("[AppDelegate] 🚀 Application launching...")
        
        // Crash prevention - NSError handling
        NSSetUncaughtExceptionHandler { exception in
            print("[AppDelegate] 🚨 Uncaught exception: \(exception)")
            print("[AppDelegate] 🚨 Reason: \(exception.reason ?? "Unknown")")
            print("[AppDelegate] 🚨 Call stack: \(exception.callStackSymbols)")
        }
        
        // Güvenli tek instance kontrolü - DELAY ile
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.checkSingleInstance()
        }
        
        // Uygulama tamamen yüklendiğini işaretle
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.isAppFullyLoaded = true
            print("[AppDelegate] 🎯 Application fully loaded")
        }
        
        // Activation policy'yi ayarla
        NSApp.setActivationPolicy(.regular)
        print("[AppDelegate] ✅ Application setup completed")
    }
    
    private func checkSingleInstance() {
        guard !isInstanceCheckCompleted else {
            print("[AppDelegate] ⚠️ Instance check already completed, skipping...")
            return
        }
        
        // Ekstra güvenlik - uygulama tamamen yüklenmeden instance kontrolü yapma
        guard isAppFullyLoaded else {
            print("[AppDelegate] ⏳ App not fully loaded yet, retrying in 0.5 seconds...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.checkSingleInstance()
            }
            return
        }
        
        do {
            let bundleID = Bundle.main.bundleIdentifier ?? "com.dogan.audioassist"
            let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            
            print("[AppDelegate] 🔍 Found \(runningApps.count) running instances")
            
            // Sadece birden fazla instance varsa ve bu instance mevcut değilse sonlandır
            if runningApps.count > 1 {
                let currentApp = NSRunningApplication.current
                let otherApps = runningApps.filter { $0 != currentApp }
                
                if !otherApps.isEmpty {
                    print("[AppDelegate] ⚠️ Multiple instances detected. Terminating other instances...")
                    
                    for app in otherApps {
                        // Ekstra güvenlik kontrolü
                        if app != currentApp && 
                           app.bundleURL != currentApp.bundleURL &&
                           app.processIdentifier != currentApp.processIdentifier {
                            
                            print("[AppDelegate] 🔪 Terminating other instance at: \(app.bundleURL?.path ?? "unknown")")
                            
                            // Güvenli termination - main thread'de
                            DispatchQueue.main.async {
                                // Son bir güvenlik kontrolü
                                if app != NSRunningApplication.current {
                                    app.terminate()
                                } else {
                                    print("[AppDelegate] ⚠️ Attempted to terminate current app, prevented!")
                                }
                            }
                        }
                    }
                }
            }
            
            isInstanceCheckCompleted = true
            print("[AppDelegate] ✅ Single instance check completed")
            
        } catch {
            print("[AppDelegate] ❌ Error during instance check: \(error)")
            isInstanceCheckCompleted = true
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        print("[AppDelegate] 🪟 Last window closed, should terminate: true")
        return true
    }
    
    // Uygulama sonlandırılmadan önce cleanup
    func applicationWillTerminate(_ notification: Notification) {
        print("[AppDelegate] 🛑 Application will terminate")
        
        // Cleanup işlemleri
        isInstanceCheckCompleted = false
        isAppFullyLoaded = false
    }
    
    // Uygulama aktif olmadan önce
    func applicationWillBecomeActive(_ notification: Notification) {
        print("[AppDelegate] 🔄 Application will become active")
    }
    
    // Uygulama aktif olduktan sonra
    func applicationDidBecomeActive(_ notification: Notification) {
        print("[AppDelegate] ✅ Application did become active")
    }
    
    // Uygulama inaktif olmadan önce
    func applicationWillResignActive(_ notification: Notification) {
        print("[AppDelegate] ⏸️ Application will resign active")
    }
    
    // Uygulama inaktif olduktan sonra
    func applicationDidResignActive(_ notification: Notification) {
        print("[AppDelegate] ⏸️ Application did resign active")
    }
    
    // Uygulama kapanmadan önce
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        print("[AppDelegate] 🤔 Application should terminate?")
        return .terminateNow
    }
    

}

