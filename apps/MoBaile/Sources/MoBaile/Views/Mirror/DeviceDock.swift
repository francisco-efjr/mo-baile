import SwiftUI

struct DeviceDock: View {
    var body: some View {
        HStack(spacing: 8) {
            FluidPillButton(text: "Voltar", icon: "chevron.left", style: .secondary) {
                // Action
            }
            FluidPillButton(text: "Home", icon: "house", style: .secondary) {
                // Action
            }
            FluidPillButton(text: "Girar", icon: "rotate.right", style: .secondary) {
                // Action
            }
            FluidPillButton(text: "Screenshot", icon: "camera.viewfinder", style: .secondary) {
                // Action
            }
        }
    }
}
