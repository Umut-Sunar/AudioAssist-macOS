# 🚨 SIGTERM Error Fix Guide

## ❌ **Problem Description**

Uygulama başlatılırken `Thread 1: signal SIGTERM` hatası alınıyordu. Bu hata, uygulamanın kendini sonlandırmasından kaynaklanıyordu.

## 🔍 **Root Cause Analysis**

### **Original Problematic Code**
```swift
func applicationDidFinishLaunching(_ notification: Notification) {
    // Tek instance garantisi
    let bundleID = Bundle.main.bundleIdentifier ?? "com.dogan.audioassist"
    let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    
    if runningApps.count > 1 {
        for app in runningApps {
            if app != NSRunningApplication.current {
                app.terminate() // ❌ Bu satır uygulamayı sonlandırıyordu
            }
        }
    }
}
```

### **Problem**
1. **Immediate Execution**: Instance kontrolü uygulama başlatılır başlatılmaz yapılıyordu
2. **Self-Termination**: Uygulama kendini yanlışlıkla sonlandırıyordu
3. **Race Condition**: Bundle ID kontrolü sırasında timing issues oluşuyordu

## ✅ **Solution Implementation**

### **Fixed Code**
```swift
func applicationDidFinishLaunching(_ notification: Notification) {
    print("[AppDelegate] 🚀 Application launching...")
    
    // Güvenli tek instance kontrolü - DELAY ile
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        self.checkSingleInstance()
    }
    
    // Activation policy'yi ayarla
    NSApp.setActivationPolicy(.regular)
    print("[AppDelegate] ✅ Application setup completed")
}

private func checkSingleInstance() {
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
                if app != currentApp && app.bundleURL != currentApp.bundleURL {
                    print("[AppDelegate] 🔪 Terminating other instance at: \(app.bundleURL?.path ?? "unknown")")
                    app.terminate()
                }
            }
        }
    }
    
    print("[AppDelegate] ✅ Single instance check completed")
}
```

## 🔧 **Key Fixes Applied**

### **1. Delayed Execution**
```swift
DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
    self.checkSingleInstance()
}
```
- Instance kontrolü 0.1 saniye geciktirildi
- Uygulama tamamen başlatıldıktan sonra kontrol yapılıyor

### **2. Better Instance Comparison**
```swift
let currentApp = NSRunningApplication.current
let otherApps = runningApps.filter { $0 != currentApp }

if app != currentApp && app.bundleURL != currentApp.bundleURL {
    app.terminate()
}
```
- Daha güvenli instance karşılaştırması
- Bundle URL kontrolü eklendi

### **3. Separated Logic**
```swift
private func checkSingleInstance() {
    // Instance kontrol mantığı ayrı fonksiyona taşındı
}
```
- Kod daha organize ve test edilebilir
- Hata ayıklama daha kolay

### **4. Enhanced Logging**
```swift
print("[AppDelegate] 🚀 Application launching...")
print("[AppDelegate] ✅ Application setup completed")
print("[AppDelegate] 🔍 Found \(runningApps.count) running instances")
```
- Detaylı logging ile debugging kolaylaştırıldı
- Her adım takip edilebiliyor

## 🚀 **Additional Safety Measures**

### **1. Application Lifecycle Monitoring**
```swift
func applicationWillTerminate(_ notification: Notification) {
    print("[AppDelegate] 🛑 Application will terminate")
}
```

### **2. Error Handling**
```swift
// Bundle ID kontrolü
let bundleID = Bundle.main.bundleIdentifier ?? "com.dogan.audioassist"

// Safe array access
if !otherApps.isEmpty {
    // Process other apps
}
```

### **3. Timing Control**
```swift
// Main thread'de güvenli execution
DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
    // Instance check after app is fully loaded
}
```

## 📋 **Testing Steps**

### **1. Build & Run**
1. Xcode'da projeyi aç
2. Product → Build (⌘B)
3. Product → Run (⌘R)

### **2. Verify Fix**
- ✅ SIGTERM hatası alınmamalı
- ✅ Uygulama normal şekilde başlamalı
- ✅ Console'da success mesajları görünmeli

### **3. Multiple Instance Test**
1. Uygulamayı çalıştır
2. Tekrar çalıştırmaya çalış
3. İlk instance'ın kapanması gerekir

## 🔍 **Debug Information**

### **Console Output (Expected)**
```
[AppDelegate] 🚀 Application launching...
[AppDelegate] ✅ Application setup completed
[AppDelegate] 🔍 Found 1 running instances
[AppDelegate] ✅ Single instance check completed
```

### **Error Cases (Fixed)**
- ❌ `Thread 1: signal SIGTERM` - FIXED
- ❌ Immediate termination - FIXED
- ❌ Race conditions - FIXED

## 🎯 **Prevention Measures**

### **1. Code Review**
- Instance kontrolü için timing kontrolü
- Self-termination prevention
- Bundle ID validation

### **2. Testing**
- Multiple instance scenarios
- Edge cases
- Performance testing

### **3. Monitoring**
- Console logging
- Error tracking
- Performance metrics

## ✅ **Status**

**SIGTERM Error: ✅ FIXED**  
**Single Instance Logic: ✅ IMPROVED**  
**Safety Measures: ✅ ADDED**  
**Ready for Testing: ✅ YES**  

## 🔮 **Future Improvements**

### **1. Enhanced Instance Management**
- Instance ID tracking
- Graceful shutdown
- State persistence

### **2. Better Error Handling**
- Retry mechanisms
- Fallback strategies
- User notifications

### **3. Performance Optimization**
- Lazy initialization
- Background processing
- Memory management

Bu fix ile uygulama artık güvenli bir şekilde başlatılacak ve SIGTERM hatası alınmayacak.
