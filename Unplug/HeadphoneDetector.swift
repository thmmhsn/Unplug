import Foundation
import CoreAudio
import AudioToolbox

class HeadphoneDetector: ObservableObject {
    @Published var headphonesConnected = false
    @Published var usageStartTime: Date?
    @Published var usageDuration: TimeInterval = 0
    
    private var timer: Timer?
    private var deviceListenerProc: AudioObjectPropertyListenerProc?
    
    init() {
        checkInitialHeadphoneStatus()
        startMonitoring()
    }
    
    deinit {
        stopMonitoring()
    }
    
    private func checkInitialHeadphoneStatus() {
        headphonesConnected = isHeadphonesConnected()
        
        if headphonesConnected {
            startUsageTracking()
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
                    } else {
                        detector.stopUsageTracking()
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
                    self.usageDuration = Date().timeIntervalSince(startTime)
                }
            }
        }
    }
    
    private func stopUsageTracking() {
        timer?.invalidate()
        timer = nil
        usageStartTime = nil
        usageDuration = 0
    }
    
    func resetUsageTracking() {
        if headphonesConnected {
            startUsageTracking()
        } else {
            usageDuration = 0
        }
    }
}