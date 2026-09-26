import SwiftUI

struct ControllerView: View {
    @ObservedObject var input: InputState
    @State private var aPressed = false
    @State private var bPressed = false
    @State private var xPressed = false
    @State private var yPressed = false
    @State private var l1Pressed = false
    @State private var r1Pressed = false
    @State private var l3Pressed = false
    @State private var r3Pressed = false
    @State private var menuPressed = false
    @State private var viewPressed = false

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height
            ZStack {
                // Background
                LinearGradient(colors: [Color.black, Color.gray.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                if isLandscape {
                    landscapeLayout
                } else {
                    portraitLayout
                }

                // Top bar
                VStack {
                    HStack {
                        Spacer()
                        MenuButtonView(label: "VIEW", systemIcon: "rectangle.grid.1x2", isPressed: $viewPressed)
                            .onChange(of: viewPressed) { pressed in
                                if pressed { input.buttons.insert(.view) } else { input.buttons.remove(.view) }
                            }
                        MenuButtonView(label: "MENU", systemIcon: "line.3.horizontal", isPressed: $menuPressed)
                            .onChange(of: menuPressed) { pressed in
                                if pressed { input.buttons.insert(.menu) } else { input.buttons.remove(.menu) }
                            }
                        Spacer()
                    }
                    .padding(.top, 8)
                    Spacer()
                }
            }
        }
        .onChange(of: aPressed) { pressed in
            if pressed { input.buttons.insert(.a) } else { input.buttons.remove(.a) }
        }
        .onChange(of: bPressed) { pressed in
            if pressed { input.buttons.insert(.b) } else { input.buttons.remove(.b) }
        }
        .onChange(of: xPressed) { pressed in
            if pressed { input.buttons.insert(.x) } else { input.buttons.remove(.x) }
        }
        .onChange(of: yPressed) { pressed in
            if pressed { input.buttons.insert(.y) } else { input.buttons.remove(.y) }
        }
        .onChange(of: l1Pressed) { pressed in
            if pressed { input.buttons.insert(.l1) } else { input.buttons.remove(.l1) }
        }
        .onChange(of: r1Pressed) { pressed in
            if pressed { input.buttons.insert(.r1) } else { input.buttons.remove(.r1) }
        }
        .onChange(of: l3Pressed) { pressed in
            if pressed { input.buttons.insert(.l3) } else { input.buttons.remove(.l3) }
        }
        .onChange(of: r3Pressed) { pressed in
            if pressed { input.buttons.insert(.r3) } else { input.buttons.remove(.r3) }
        }
    }

    var portraitLayout: some View {
        VStack(spacing: 16) {
            // Top: L1 R1 L2 R2
            HStack(spacing: 20) {
                ShoulderButtonView(label: "L1", isPressed: $l1Pressed)
                TriggerButtonView(label: "L2", value: $input.leftTrigger)
                Spacer()
                TriggerButtonView(label: "R2", value: $input.rightTrigger)
                ShoulderButtonView(label: "R1", isPressed: $r1Pressed)
            }
            .padding(.horizontal)
            .padding(.top, 40)

            Spacer()

            // Middle: DPad + ABXY
            HStack {
                VStack {
                    DPad8WayView(x: $input.dpadX, y: $input.dpadY, size: 140)
                    Text("D-PAD")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))
                }
                Spacer()
                VStack(spacing: 8) {
                    GameButtonView(label: "Y", color: .yellow, isPressed: $yPressed, size: 55)
                    HStack(spacing: 12) {
                        GameButtonView(label: "X", color: .blue, isPressed: $xPressed, size: 55)
                        GameButtonView(label: "B", color: .red, isPressed: $bPressed, size: 55)
                    }
                    GameButtonView(label: "A", color: .green, isPressed: $aPressed, size: 55)
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            // Bottom: Sticks
            HStack {
                VStack {
                    JoystickView(x: $input.leftStickX, y: $input.leftStickY, diameter: 110, knobDiameter: 55, title: "L")
                    ShoulderButtonView(label: "L3", isPressed: $l3Pressed, width: 50, height: 28)
                }
                Spacer()
                VStack {
                    JoystickView(x: $input.rightStickX, y: $input.rightStickY, diameter: 110, knobDiameter: 55, title: "R")
                    ShoulderButtonView(label: "R3", isPressed: $r3Pressed, width: 50, height: 28)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 30)
        }
    }

    var landscapeLayout: some View {
        HStack(spacing: 0) {
            // Left side: L1 L2, DPad, Left Stick
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    ShoulderButtonView(label: "L1", isPressed: $l1Pressed, width: 60, height: 32)
                    TriggerButtonView(label: "L2", value: $input.leftTrigger, width: 60, height: 40)
                }
                DPad8WayView(x: $input.dpadX, y: $input.dpadY, size: 120)
                JoystickView(x: $input.leftStickX, y: $input.leftStickY, diameter: 100, knobDiameter: 50, title: "L")
                ShoulderButtonView(label: "L3", isPressed: $l3Pressed, width: 45, height: 24)
            }
            .frame(maxWidth: .infinity)

            Spacer()

            // Right side: R1 R2, ABXY, Right Stick
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    TriggerButtonView(label: "R2", value: $input.rightTrigger, width: 60, height: 40)
                    ShoulderButtonView(label: "R1", isPressed: $r1Pressed, width: 60, height: 32)
                }
                VStack(spacing: 6) {
                    GameButtonView(label: "Y", color: .yellow, isPressed: $yPressed, size: 48)
                    HStack(spacing: 8) {
                        GameButtonView(label: "X", color: .blue, isPressed: $xPressed, size: 48)
                        GameButtonView(label: "B", color: .red, isPressed: $bPressed, size: 48)
                    }
                    GameButtonView(label: "A", color: .green, isPressed: $aPressed, size: 48)
                }
                JoystickView(x: $input.rightStickX, y: $input.rightStickY, diameter: 100, knobDiameter: 50, title: "R")
                ShoulderButtonView(label: "R3", isPressed: $r3Pressed, width: 45, height: 24)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 40)
    }
}
