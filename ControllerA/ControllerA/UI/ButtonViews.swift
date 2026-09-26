import SwiftUI

struct GameButtonView: View {
    var label: String
    var color: Color
    @Binding var isPressed: Bool
    var size: CGFloat = 60

    var body: some View {
        ZStack {
            Circle()
                .fill(isPressed ? color : color.opacity(0.6))
                .frame(width: size, height: size)
                .shadow(color: isPressed ? color : .clear, radius: isPressed ? 8 : 0)
                .scaleEffect(isPressed ? 0.9 : 1.0)
            Text(label)
                .font(.system(size: size*0.35, weight: .bold))
                .foregroundColor(.white)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        isPressed = true
                        // Haptic
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }
                .onEnded { _ in
                    isPressed = false
                }
        )
    }
}

struct ShoulderButtonView: View {
    var label: String
    @Binding var isPressed: Bool
    var width: CGFloat = 70
    var height: CGFloat = 40

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(isPressed ? Color.orange : Color.orange.opacity(0.6))
                .frame(width: width, height: height)
                .scaleEffect(isPressed ? 0.95 : 1.0)
            Text(label)
                .font(.caption.bold())
                .foregroundColor(.white)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

struct TriggerButtonView: View {
    var label: String
    @Binding var value: Float // 0..1
    var width: CGFloat = 70
    var height: CGFloat = 50

    @State private var isPressing = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.purple.opacity(0.3))
                .frame(width: width, height: height)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.purple.opacity(Double(value)))
                        .frame(width: width, height: CGFloat(value) * height)
                        .animation(.linear(duration: 0.05), value: value),
                    alignment: .bottom
                )
            Text(label)
                .font(.caption2.bold())
                .foregroundColor(.white)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { val in
                    isPressing = true
                    // Calculate vertical press amount
                    let h = height
                    let progress = Float(1.0 - (val.location.y / h))
                    value = max(0, min(1, progress))
                }
                .onEnded { _ in
                    isPressing = false
                    withAnimation {
                        value = 0
                    }
                }
        )
    }
}

struct MenuButtonView: View {
    var label: String
    var systemIcon: String
    @Binding var isPressed: Bool

    var body: some View {
        Button(action: {}) {
            HStack(spacing: 4) {
                Image(systemName: systemIcon)
                    .font(.caption)
                Text(label)
                    .font(.caption2.bold())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isPressed ? Color.white.opacity(0.3) : Color.black.opacity(0.3))
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}
