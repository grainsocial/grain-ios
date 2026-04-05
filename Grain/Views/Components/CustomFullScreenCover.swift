import SwiftUI

extension View {
    func customFullScreenCover(
        isPresented: Binding<Bool>,
        transition: AnyTransition = .scale(scale: 0.9).combined(with: .opacity),
        animation: Animation = .easeInOut(duration: 0.25),
        @ViewBuilder content: @escaping () -> some View
    ) -> some View {
        modifier(
            CustomFullScreenCoverModifier(
                isPresented: isPresented,
                transition: transition,
                animation: animation,
                presentedView: content
            )
        )
    }
}

private struct CustomFullScreenCoverModifier<PresentedView: View>: ViewModifier {
    @Binding var isPresented: Bool
    let transition: AnyTransition
    let animation: Animation
    @ViewBuilder let presentedView: () -> PresentedView

    @State private var isPresentedInternal = false
    @State private var isShowContent = false

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $isPresentedInternal) {
                ZStack {
                    if isShowContent {
                        presentedView()
                            .transition(transition)
                    }
                }
                .onAppear {
                    withAnimation(animation) {
                        isShowContent = true
                    }
                }
                .presentationBackground(.clear)
            }
            .onChange(of: isPresented) { _, newValue in
                if newValue {
                    isShowContent = false
                    isPresentedInternal = true
                } else {
                    withAnimation(animation) {
                        isShowContent = false
                    } completion: {
                        isPresentedInternal = false
                    }
                }
            }
    }
}
