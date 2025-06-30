import SwiftUI

struct SettingsView: View {
    @AppStorage("warningThreshold") private var warningThreshold: Double = 3600 // 1 hour in seconds
    @AppStorage("recoveryTime") private var recoveryTime: Double = 600 // 10 minutes in seconds
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Unplug Settings")
                .font(.title2)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 15) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Usage Time Limit")
                        .font(.headline)
                    
                    Text("Time before reaching 100% fatigue")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Text("\(formatTime(warningThreshold))")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Stepper("", value: $warningThreshold, in: 300...7200, step: 300)
                    }
                    
                    Slider(value: $warningThreshold, in: 300...7200, step: 300) {
                        Text("Usage Time")
                    }
                    .accentColor(.blue)
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recovery Time")
                        .font(.headline)
                    
                    Text("Time to fully recover from fatigue")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Text("\(formatTime(recoveryTime))")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Stepper("", value: $recoveryTime, in: 60...1800, step: 60)
                    }
                    
                    Slider(value: $recoveryTime, in: 60...1800, step: 60) {
                        Text("Recovery Time")
                    }
                    .accentColor(.green)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
            
            Spacer()
            
            VStack(spacing: 8) {
                Text("Changes take effect immediately")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Button("Reset to Defaults") {
                    warningThreshold = 3600 // 1 hour
                    recoveryTime = 600 // 10 minutes
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(20)
        .frame(width: 400, height: 500)
        .onChange(of: warningThreshold) { _, newValue in
            NotificationCenter.default.post(name: NSNotification.Name("SettingsChanged"), object: nil)
        }
        .onChange(of: recoveryTime) { _, newValue in
            NotificationCenter.default.post(name: NSNotification.Name("SettingsChanged"), object: nil)
        }
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let remainingSeconds = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%dh %02dm", hours, minutes)
        } else if minutes > 0 {
            return String(format: "%dm %02ds", minutes, remainingSeconds)
        } else {
            return String(format: "%ds", remainingSeconds)
        }
    }
}

#Preview {
    SettingsView()
}