import SwiftUI

/// Shown in place of the whole app when this build is older than the server
/// supports. There is nothing to dismiss: the only way on is the App Store.
struct UpdateRequiredView: View {
    let storeURL: URL

    @Environment(\.openURL) private var openURL

    var body: some View {
        GeometryReader { geo in
            let fullHeight = geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom
            ZStack {
                Image("login-bg")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: fullHeight)
                    .clipped()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                VStack(spacing: 0) {
                    Spacer()

                    Text("grain")
                        .font(.custom("Syne", size: 44).weight(.heavy))
                        .foregroundStyle(.white)
                        .padding(.bottom, 60)
                        .accessibilityHidden(true)

                    Text("Update Grain")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 8)
                        .accessibilityAddTraits(.isHeader)

                    Text("This version of Grain is no longer supported. Update to keep using it.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 24)

                    Button {
                        openURL(storeURL)
                    } label: {
                        Text("Update")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .background(.white, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.black)

                    Spacer()
                }
                .padding(24)
                .frame(maxWidth: 440)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea(.keyboard)
        .interactiveDismissDisabled()
    }
}

#Preview {
    UpdateRequiredView(storeURL: AppVersionPolicy.fallbackStoreURL)
}
