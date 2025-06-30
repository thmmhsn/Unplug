import Foundation
import CoreAudio
import AudioToolbox
import AVFoundation

class HeadphoneDetector: ObservableObject {
    @Published var headphonesConnected = false
    @Published var usageStartTime: Date?
    @Published var usageDuration: TimeInterval = 0
    @Published var fatigueLevel: Double = 0.0 // 0.0 to 1.0, where 1.0 = warning threshold
    
    private var timer: Timer?
    private var fatigueTimer: Timer?
    private var deviceListenerProc: AudioObjectPropertyListenerProc?
    private var disconnectedTime: Date?
    private var hasSoundedFatigueWarning = false
    
    private var warningThreshold: TimeInterval = 30 // 1 hour
    private var recoveryTime: TimeInterval = 10 // 10 minutes
    
    init() {
        loadSettings()
        checkInitialHeadphoneStatus()
        startMonitoring()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsChanged),
            name: NSNotification.Name("SettingsChanged"),
            object: nil
        )
    }
    
    deinit {
        stopMonitoring()
        fatigueTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
    
    private func loadSettings() {
        warningThreshold = UserDefaults.standard.double(forKey: "warningThreshold")
        recoveryTime = UserDefaults.standard.double(forKey: "recoveryTime")
        
        // Set defaults if not previously saved
        if warningThreshold == 0 {
            warningThreshold = 3600 // 1 hour
        }
        if recoveryTime == 0 {
            recoveryTime = 600 // 10 minutes
        }
    }
    
    @objc private func settingsChanged() {
        loadSettings()
    }
    
    private func checkInitialHeadphoneStatus() {
        headphonesConnected = isHeadphonesConnected()
        
        if headphonesConnected {
            startUsageTracking()
            startFatigueTracking()
        }
    }
    
    private func startMonitoring() {
        deviceListenerProc = { (objectID, numAddresses, addresses, clientData) -> OSStatus in
            guard let detector = Unmanaged<HeadphoneDetector>.fromOpaque(clientData!).takeUnretainedValue() as HeadphoneDetector? else {
                return noErr
            }
            
            DispatchQueue.main.async {
                let newStatus = detector.isHeadphonesConnected()
                if detector.headphonesConnected != newStatus {
                    detector.headphonesConnected = newStatus
                    
                    if newStatus {
                        detector.startUsageTracking()
                        detector.startFatigueTracking()
                    } else {
                        detector.stopUsageTracking()
                        detector.startFatigueRecovery()
                    }
                }
            }
            
            return noErr
        }
        
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        AudioObjectAddPropertyListener(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, deviceListenerProc!, selfPtr)
    }
    
    private func stopMonitoring() {
        if let listener = deviceListenerProc {
            var propertyAddress = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDevices,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            
            let selfPtr = Unmanaged.passUnretained(self).toOpaque()
            AudioObjectRemovePropertyListener(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, listener, selfPtr)
        }
        timer?.invalidate()
        fatigueTimer?.invalidate()
    }
    
    private func isHeadphonesConnected() -> Bool {
        var deviceCount: UInt32 = 0
        var propertySize = UInt32(MemoryLayout<UInt32>.size)
        
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &propertySize)
        guard status == noErr else { return false }
        
        deviceCount = propertySize / UInt32(MemoryLayout<AudioDeviceID>.size)
        let devices = UnsafeMutablePointer<AudioDeviceID>.allocate(capacity: Int(deviceCount))
        defer { devices.deallocate() }
        
        status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &propertySize, devices)
        guard status == noErr else { return false }
        
        for i in 0..<Int(deviceCount) {
            let deviceID = devices[i]
            
            if isOutputDevice(deviceID) {
                let deviceName = getDeviceName(deviceID)
                let transportType = getTransportType(deviceID)
                
                if isHeadphoneDevice(name: deviceName, transportType: transportType) {
                    return true
                }
            }
        }
        
        return false
    }
    
    private func isOutputDevice(_ deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var propertySize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &propertySize)
        
        return status == noErr && propertySize > 0
    }
    
    private func getDeviceName(_ deviceID: AudioDeviceID) -> String {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var propertySize = UInt32(MemoryLayout<CFString>.size)
        var deviceName: CFString = "" as CFString
        
        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &propertySize, &deviceName)
        guard status == noErr else { return "" }
        
        return deviceName as String
    }
    
    private func getTransportType(_ deviceID: AudioDeviceID) -> UInt32 {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var propertySize = UInt32(MemoryLayout<UInt32>.size)
        var transportType: UInt32 = 0
        
        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &propertySize, &transportType)
        guard status == noErr else { return 0 }
        
        return transportType
    }
    
    private func isHeadphoneDevice(name: String, transportType: UInt32) -> Bool {
        let lowercaseName = name.lowercased()
        
        let headphoneKeywords = ["headphone", "headset", "airpods", "earbud", "earphone"]
        for keyword in headphoneKeywords {
            if lowercaseName.contains(keyword) {
                return true
            }
        }
        
        return transportType == kAudioDeviceTransportTypeBluetooth && 
               (lowercaseName.contains("audio") || lowercaseName.contains("wireless"))
    }
    
    private func startUsageTracking() {
        usageStartTime = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            DispatchQueue.main.async {
                if let startTime = self.usageStartTime {
                    let previousDuration = self.usageDuration
                    self.usageDuration = Date().timeIntervalSince(startTime)
                    
                    NotificationCenter.default.post(name: NSNotification.Name("UsageTimeChanged"), object: nil)
                    
                    if previousDuration < self.warningThreshold && self.usageDuration >= self.warningThreshold {
                        self.showWarningNotification()
                    }
                }
            }
        }
        NotificationCenter.default.post(name: NSNotification.Name("HeadphoneStatusChanged"), object: nil)
    }
    
    private func stopUsageTracking() {
        timer?.invalidate()
        timer = nil
        usageStartTime = nil
        usageDuration = 0
        NotificationCenter.default.post(name: NSNotification.Name("HeadphoneStatusChanged"), object: nil)
    }
    
    private func startFatigueTracking() {
        fatigueTimer?.invalidate()
        hasSoundedFatigueWarning = false
        
        // Store the baseline fatigue level when starting tracking
        let baselineFatigue = fatigueLevel
        
        fatigueTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            DispatchQueue.main.async {
                if self.headphonesConnected {
                    let previousFatigue = self.fatigueLevel
                    // Calculate additional fatigue from current usage session
                    let additionalFatigue = self.usageDuration / self.warningThreshold
                    // Add to baseline fatigue level
                    self.fatigueLevel = min(1.0, baselineFatigue + additionalFatigue)
                    
                    // Play warning sound when fatigue reaches 100% for the first time
                    if previousFatigue < 1.0 && self.fatigueLevel >= 1.0 && !self.hasSoundedFatigueWarning {
                        self.playFatigueWarningSound()
                        self.hasSoundedFatigueWarning = true
                    }
                    
                    NotificationCenter.default.post(name: NSNotification.Name("FatigueChanged"), object: nil)
                }
            }
        }
    }
    
    private func startFatigueRecovery() {
        disconnectedTime = Date()
        fatigueTimer?.invalidate()
        fatigueTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            DispatchQueue.main.async {
                if let disconnectedAt = self.disconnectedTime {
                    let recoveryDuration = Date().timeIntervalSince(disconnectedAt)
                    let recoveryProgress = recoveryDuration / self.recoveryTime
                    
                    // Decrease fatigue level over recovery time
                    let previousFatigue = self.fatigueLevel
                    self.fatigueLevel = max(0.0, previousFatigue * (1.0 - recoveryProgress))
                    
                    NotificationCenter.default.post(name: NSNotification.Name("FatigueChanged"), object: nil)
                    
                    // Stop recovery timer when fully recovered
                    if self.fatigueLevel <= 0.0 {
                        self.fatigueLevel = 0.0
                        self.fatigueTimer?.invalidate()
                        self.fatigueTimer = nil
                        self.disconnectedTime = nil
                    }
                }
            }
        }
    }
    
    private func showWarningNotification() {
        let notification = NSUserNotification()
        notification.title = "Headphone Usage Warning"
        notification.informativeText = "You've been using headphones for over an hour. Consider taking a break to protect your hearing."
        notification.soundName = NSUserNotificationDefaultSoundName
        
        NSUserNotificationCenter.default.deliver(notification)
    }
    
    private func playFatigueWarningSound() {
        // Play system alert sound
        AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_UserPreferredAlert))
        
        // Also show enhanced notification
        let notification = NSUserNotification()
        notification.title = "Maximum Fatigue Reached!"
        notification.informativeText = "You've reached 100% fatigue. Consider taking a break to protect your hearing and reduce ear fatigue."
        notification.soundName = NSUserNotificationDefaultSoundName
        
        NSUserNotificationCenter.default.deliver(notification)
    }
    
    func resetUsageTracking() {
        if headphonesConnected {
            startUsageTracking()
            fatigueLevel = 0.0
            hasSoundedFatigueWarning = false
            startFatigueTracking()
        } else {
            usageDuration = 0
            fatigueLevel = 0.0
            hasSoundedFatigueWarning = false
        }
        NotificationCenter.default.post(name: NSNotification.Name("UsageTimeChanged"), object: nil)
        NotificationCenter.default.post(name: NSNotification.Name("FatigueChanged"), object: nil)
    }
}
