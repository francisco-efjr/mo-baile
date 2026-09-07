import SwiftUI

struct DeviceBezel: View {
    @Environment(ThemeManager.self) private var themeManager
    var isCompact: Bool = false
    
    var body: some View {
        let theme = themeManager.current
        
        let width: CGFloat = isCompact ? 186 : 258
        let height: CGFloat = isCompact ? 390 : 540
        let radiusOuter: CGFloat = isCompact ? 30 : 40
        let radiusInner: CGFloat = isCompact ? 25 : 33
        let padding: CGFloat = isCompact ? 6 : 7
        let notchWidth: CGFloat = isCompact ? 54 : 76
        let notchHeight: CGFloat = isCompact ? 14 : 20
        
        ZStack {
            // Outer Frame
            RoundedRectangle(cornerRadius: radiusOuter, style: .continuous)
                .fill(theme.deviceBezel)
                .shadow(color: .black.opacity(0.45), radius: 15, x: 0, y: 12)
            
            // Inner Screen Area
            RoundedRectangle(cornerRadius: radiusInner, style: .continuous)
                .fill(theme.bgDeviceScreen)
                .padding(padding)
                .overlay {
                    ScreenCanvas()
                        .clipShape(RoundedRectangle(cornerRadius: radiusInner, style: .continuous))
                        .padding(padding)
                }
            
            // Notch
            VStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(theme.deviceBezel)
                    .frame(width: notchWidth, height: notchHeight)
                    .padding(.top, padding)
                Spacer()
            }
            
            // Home Indicator
            VStack {
                Spacer()
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(Color(red: 69/255, green: 71/255, blue: 90/255)) // #45475A borderStrong
                    .frame(width: isCompact ? 28 : 38, height: 5)
                    .padding(.bottom, padding + (isCompact ? 4 : 8))
            }
        }
        .frame(width: width, height: height)
    }
}
