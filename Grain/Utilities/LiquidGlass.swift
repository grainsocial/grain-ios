import SwiftUI

extension View {
    /// Applies iOS 26 Liquid Glass effect.
    func liquidGlass() -> some View {
        self.glassEffect(.regular.interactive())
    }

    /// Applies iOS 26 Liquid Glass effect in a circular shape.
    func liquidGlassCircle() -> some View {
        self.clipShape(Circle())
            .glassEffect(.regular.interactive())
    }
}
