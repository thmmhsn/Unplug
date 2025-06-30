import SwiftUI

struct FatigueProgressBar: View {
    let progress: Double
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 6)
                
                RoundedRectangle(cornerRadius: 3)
                    .fill(progressColor)
                    .frame(width: geometry.size.width * progress, height: 6)
                    .animation(.easeInOut(duration: 0.3), value: progress)
            }
        }
        .frame(height: 6)
    }
    
    private var progressColor: Color {
        switch progress {
        case 0.0..<0.5:
            return .green
        case 0.5..<0.8:
            return .yellow
        default:
            return .red
        }
    }
}

struct MenuRowView: View {
    @ObservedObject var headphoneDetector: HeadphoneDetector
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: headphoneDetector.headphonesConnected ? "headphones" : "speaker.wave.2")
                .foregroundColor(.primary)
                .frame(width: 16, height: 16)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(headphoneDetector.headphonesConnected ? "Headphones Connected" : "No Headphones")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                
                if headphoneDetector.headphonesConnected {
                    HStack(spacing: 4) {
                        Text("Usage: \(formatDuration(headphoneDetector.usageDuration))")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        if headphoneDetector.usageDuration > 3600 {
                            Text("⚠️")
                                .font(.system(size: 10))
                        }
                    }
                    
                    // Fatigue progress bar
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Fatigue")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(Int(headphoneDetector.fatigueLevel * 100))%")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        FatigueProgressBar(progress: headphoneDetector.fatigueLevel)
                    }
                } else if headphoneDetector.fatigueLevel > 0 {
                    // Show fatigue level when disconnected (recovering)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Fatigue")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(Int(headphoneDetector.fatigueLevel * 100))%")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        FatigueProgressBar(progress: headphoneDetector.fatigueLevel)
                    }
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(height: calculateHeight())
    }
    
    private func calculateHeight() -> CGFloat {
        if headphoneDetector.headphonesConnected {
            return 70 // Connected with usage time and fatigue bar
        } else if headphoneDetector.fatigueLevel > 0 {
            return 50 // Disconnected but showing recovery
        } else {
            return 28 // Just status text
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) % 3600 / 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}
