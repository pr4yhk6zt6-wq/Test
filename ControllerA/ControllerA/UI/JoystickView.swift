import SwiftUI

struct JoystickView: View {
    @Binding var x: Float
    @Binding var y: Float
    var diameter: CGFloat = 120
    var knobDiameter: CGFloat = 60
    var title: String = ""

    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: diameter, height: diameter)
                .overlay(
                    Circle().stroke(Color.white.opacity(0.5), lineWidth: 2)
                )
            Circle()
                .fill(isDragging ? Color.blue.opacity(0.8) : Color.white.opacity(0.7))
                .frame(width: knobDiameter, height: knobDiameter)
                .shadow(radius: 3)
                .offset(dragOffset)
            if !title.isEmpty {
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.white)
                    .offset(y: diameter/2 + 12)
            }
        }
        .frame(width: diameter, height: diameter)
        .gesture(
            DragGesture()
                .onChanged { value in
                    isDragging = true
                    let maxRadius = (diameter - knobDiameter) / 2
                    var newX = value.translation.width
                    var newY = value.translation.height
                    let distance = sqrt(newX*newX + newY*newY)
                    if distance > maxRadius {
                        let angle = atan2(newY, newX)
                        newX = cos(angle) * maxRadius
                        newY = sin(angle) * maxRadius
                    }
                    dragOffset = CGSize(width: newX, height: newY)
                    // Convert to -1..1, Y inverted for game convention (up = positive)
                    x = Float(newX / maxRadius)
                    y = Float(-newY / maxRadius)
                }
                .onEnded { _ in
                    isDragging = false
                    withAnimation(.spring()) {
                        dragOffset = .zero
                    }
                    x = 0
                    y = 0
                }
        )
    }
}

struct DPadView: View {
    @Binding var x: Float
    @Binding var y: Float
    var size: CGFloat = 120

    var body: some View {
        ZStack {
            // Background
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.gray.opacity(0.3))
                .frame(width: size, height: size)

            VStack(spacing: 2) {
                Button(action: {}) {
                    Image(systemName: "chevron.up")
                        .foregroundColor(y > 0.5 ? .blue : .white)
                        .frame(width: size/3, height: size/3)
                        .background(Color.black.opacity(0.2))
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in y = 1 }
                        .onEnded { _ in y = 0 }
                )

                HStack(spacing: 2) {
                    Button(action: {}) {
                        Image(systemName: "chevron.left")
                            .foregroundColor(x < -0.5 ? .blue : .white)
                            .frame(width: size/3, height: size/3)
                            .background(Color.black.opacity(0.2))
                    }
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in x = -1 }
                            .onEnded { _ in x = 0 }
                    )

                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: size/3, height: size/3)

                    Button(action: {}) {
                        Image(systemName: "chevron.right")
                            .foregroundColor(x > 0.5 ? .blue : .white)
                            .frame(width: size/3, height: size/3)
                            .background(Color.black.opacity(0.2))
                    }
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in x = 1 }
                            .onEnded { _ in x = 0 }
                    )
                }

                Button(action: {}) {
                    Image(systemName: "chevron.down")
                        .foregroundColor(y < -0.5 ? .blue : .white)
                        .frame(width: size/3, height: size/3)
                        .background(Color.black.opacity(0.2))
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in y = -1 }
                        .onEnded { _ in y = 0 }
                )
            }
        }
        .frame(width: size, height: size)
    }
}

// Improved DPad with 8-way touch
struct DPad8WayView: View {
    @Binding var x: Float
    @Binding var y: Float
    var size: CGFloat = 140

    @State private var isTouching = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.gray.opacity(0.25))
                .frame(width: size, height: size)

            // Cross
            VStack(spacing: 0) {
                Rectangle().fill(Color.white.opacity(0.15)).frame(width: 40, height: size)
            }
            HStack(spacing: 0) {
                Rectangle().fill(Color.white.opacity(0.15)).frame(width: size, height: 40)
            }

            // Center dot
            Circle()
                .fill(isTouching ? Color.blue : Color.white.opacity(0.6))
                .frame(width: 30, height: 30)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    isTouching = true
                    let location = value.location
                    let center = CGPoint(x: size/2, y: size/2)
                    let dx = location.x - center.x
                    let dy = location.y - center.y
                    let distance = sqrt(dx*dx + dy*dy)
                    let deadzone: CGFloat = 15
                    if distance < deadzone {
                        x = 0; y = 0
                        return
                    }
                    // Normalize to -1..1
                    let maxDist = size/2
                    var nx = Float(dx / maxDist)
                    var ny = Float(-dy / maxDist) // invert Y
                    // Clamp
                    nx = max(-1, min(1, nx))
                    ny = max(-1, min(1, ny))
                    // Quantize to -1,0,1 for DPad but allow analog for flexibility
                    // For DPad we want digital 8-way
                    let threshold: Float = 0.3
                    var qx: Float = 0
                    var qy: Float = 0
                    if abs(nx) > threshold {
                        qx = nx > 0 ? 1 : -1
                    }
                    if abs(ny) > threshold {
                        qy = ny > 0 ? 1 : -1
                    }
                    x = qx
                    y = qy
                }
                .onEnded { _ in
                    isTouching = false
                    x = 0
                    y = 0
                }
        )
    }
}
