import SwiftUI
import AppKit

public class SplashWindow: NSWindow {
    public init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 720),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        self.center()
        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .floating // Keep it on top initially
        
        let contentView = NSHostingView(rootView: SplashView { [weak self] in
            self?.close()
        })
        
        self.contentView = contentView
    }
    
    public override var canBecomeKey: Bool {
        return true
    }
}

struct SplashView: View {
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    let onClose: () -> Void
    
    @State private var phase = 0 // Controls timeline
    @State private var bootLabel = "iniciando ADB server"
    
    private let labels = [
        "iniciando ADB server",
        "conectando WebDriverAgent · 8100",
        "iniciando Proxy MITM · 8082",
        "pronto!"
    ]
    
    var body: some View {
        ZStack {
            // Background gradient
            RadialGradient(
                gradient: Gradient(colors: [
                    Color(hex: "B4E4F6"),
                    Color(hex: "97D5EF"),
                    Color(hex: "7FC7E6")
                ]),
                center: .center,
                startRadius: 100,
                endRadius: 600
            )
            
            VStack {
                HStack(spacing: 40) {
                    // Mascot
                    if let img = NSImage(named: "mascot") {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 580, height: 540)
                            .offset(
                                x: reduceMotion ? 0 : (phase >= 1 ? 0 : -180),
                                y: reduceMotion ? 0 : (phase >= 2 ? (sin(Date().timeIntervalSince1970 * 2) * 11) : (phase >= 1 ? 0 : 26))
                            )
                            .scaleEffect(phase >= 1 ? 1 : 0.94)
                    } else {
                        // Fallback shape
                        Circle().fill(Color.white.opacity(0.5)).frame(width: 300, height: 300)
                    }
                    
                    // Texts
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Mo baile")
                            .font(.system(size: 96, weight: .bold))
                            .tracking(-0.045 * 96)
                            .opacity(phase >= 2 ? 1 : 0)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("ELEMENT RECORDER")
                                .font(.system(size: 13, weight: .semibold))
                                .tracking(0.08 * 13)
                            
                            Rectangle()
                                .fill(Color(hex: "E88BA5"))
                                .frame(height: 2)
                                .frame(width: 160)
                        }
                        .opacity(phase >= 2 ? 1 : 0)
                        
                        Spacer().frame(height: 40)
                        
                        // Progress
                        VStack(alignment: .leading, spacing: 8) {
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(Color.white.opacity(0.3))
                                    .frame(width: 300, height: 4)
                                    .cornerRadius(2)
                                
                                LinearGradient(
                                    gradient: Gradient(colors: [Color(hex: "E88BA5"), Color(hex: "6BBF6A")]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                .frame(width: phase >= 3 ? 300 : 0, height: 4)
                                .cornerRadius(2)
                                .animation(.linear(duration: 1.24), value: phase)
                            }
                            
                            Text(bootLabel)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(bootLabel == "pronto!" ? Color(hex: "6BBF6A") : Color.black.opacity(0.7))
                        }
                        .opacity(phase >= 2 ? 1 : 0)
                    }
                }
            }
            .scaleEffect(phase >= 5 ? 1.035 : (phase >= 1 ? 1 : 1.04))
            .opacity(phase >= 5 ? 0 : (phase >= 1 ? 1 : 0))
            
            // Sparkles (simplified)
            Circle()
                .fill(Color.white)
                .frame(width: 4, height: 4)
                .offset(x: 100, y: -100)
                .opacity(phase >= 2 ? (sin(Date().timeIntervalSince1970 * 5) > 0 ? 1 : 0) : 0)
        }
        .frame(width: 1280, height: 720)
        .onAppear {
            runAnimation()
        }
        // Dismiss on interact
        .onTapGesture { onClose() }
    }
    
    private func runAnimation() {
        if reduceMotion {
            phase = 4
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { onClose() }
            return
        }
        
        // 0-380ms: stage fade + scale
        withAnimation(.easeOut(duration: 0.38)) { phase = 1 }
        
        // 80-900ms: mascot drift
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.8)) { phase = 2 }
        }
        
        // Boot labels rotation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.92) {
            bootLabel = labels[1]
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            bootLabel = labels[2]
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.9) {
            bootLabel = labels[3]
        }
        
        // 900-2140ms: progress fill
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            phase = 3
        }
        
        // 2220-2560ms: fade out
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.22) {
            withAnimation(.easeIn(duration: 0.34)) { phase = 5 }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.56) {
            onClose()
        }
    }
}

