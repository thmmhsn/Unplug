//
//  ContentView.swift
//  Unplug
//
//  Created by Thameem Hassan on 28-6-25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var headphoneDetector = HeadphoneDetector()
    @State private var showingWarning = false
    
    private let warningThreshold: TimeInterval = 60 * 60 // 1 hour
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: headphoneDetector.headphonesConnected ? "headphones" : "speaker.wave.2")
                .imageScale(.large)
                .foregroundStyle(headphoneDetector.headphonesConnected ? .blue : .gray)
                .font(.system(size: 60))
            
            Text(headphoneDetector.headphonesConnected ? "Headphones Connected" : "No Headphones")
                .font(.title2)
                .foregroundColor(headphoneDetector.headphonesConnected ? .blue : .gray)
            
            if headphoneDetector.headphonesConnected {
                VStack {
                    Text("Usage Time")
                        .font(.headline)
                    Text(formatDuration(headphoneDetector.usageDuration))
                        .font(.title)
                        .foregroundColor(headphoneDetector.usageDuration > warningThreshold ? .red : .primary)
                    
                    Button("Reset Timer") {
                        headphoneDetector.resetUsageTracking()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding()
        .onChange(of: headphoneDetector.usageDuration) { _, newValue in
            if newValue > warningThreshold && !showingWarning {
                showingWarning = true
            }
        }
        .alert("Headphone Usage Warning", isPresented: $showingWarning) {
            Button("OK") {
                showingWarning = false
            }
            Button("Reset Timer") {
                headphoneDetector.resetUsageTracking()
                showingWarning = false
            }
        } message: {
            Text("You've been using headphones for over an hour. Consider taking a break to protect your hearing.")
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

#Preview {
    ContentView()
}
