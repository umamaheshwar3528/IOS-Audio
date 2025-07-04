import SwiftUI

struct AudioLevelMeterView: View {
    @ObservedObject private var recordingManager = AudioRecordingManager.shared
    
    private let numberOfBars = 20
    private let barSpacing: CGFloat = 2
    private let minBarHeight: CGFloat = 4
    private let maxBarHeight: CGFloat = 40
    
    var body: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<numberOfBars, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(barColor(for: index))
                    .frame(width: 3, height: barHeight(for: index))
                    .animation(.easeInOut(duration: 0.1), value: recordingManager.audioLevel)
            }
        }
        .frame(height: maxBarHeight)
    }
    
    private func barHeight(for index: Int) -> CGFloat {
        let normalizedLevel = normalizeAudioLevel(recordingManager.audioLevel)
        let barThreshold = Float(index) / Float(numberOfBars)
        
        if normalizedLevel > barThreshold {
            return minBarHeight + (maxBarHeight - minBarHeight) * CGFloat(normalizedLevel - barThreshold) * CGFloat(numberOfBars)
        } else {
            return minBarHeight
        }
    }
    
    private func barColor(for index: Int) -> Color {
        let normalizedLevel = normalizeAudioLevel(recordingManager.audioLevel)
        let barThreshold = Float(index) / Float(numberOfBars)
        
        if normalizedLevel > barThreshold {
            if index < numberOfBars * 2 / 3 {
                return .green
            } else if index < numberOfBars * 9 / 10 {
                return .yellow
            } else {
                return .red
            }
        } else {
            return .gray.opacity(0.3)
        }
    }
    
    private func normalizeAudioLevel(_ level: Float) -> Float {
        // Convert dB to 0-1 range
        let minDB: Float = -60.0
        let maxDB: Float = 0.0
        let clampedLevel = max(minDB, min(maxDB, level))
        return (clampedLevel - minDB) / (maxDB - minDB)
    }
}
