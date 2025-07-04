import SwiftUI

struct LoadingView: View {
    let message: String
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 20) {
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(Color.blue, lineWidth: 4)
                .frame(width: 50, height: 50)
                .rotationEffect(Angle(degrees: isAnimating ? 360 : 0))
                .animation(
                    Animation.linear(duration: 1.0).repeatForever(autoreverses: false),
                    value: isAnimating
                )
            
            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
        }
        .onAppear {
            isAnimating = true
        }
    }
}
