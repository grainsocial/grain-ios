@testable import Grain
import PhotosUI
import SwiftUI
import Testing

/// Rendering each face of the story composer. The camera never reaches ready
/// in the simulator, so these cover the placeholder states of the viewfinder
/// and drive the review stage directly with a photo.
@MainActor
struct StoryComposerRenderTests {
    private let photo = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 160)).image { context in
        UIColor.systemTeal.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 120, height: 160))
    }

    // MARK: - Capture stage

    @Test func rendersTheViewfinderWhileCameraAccessIsDenied() async {
        let camera = StoryCamera(requestAccess: { false })
        await camera.start()

        ViewRender.render(captureStage(camera: camera))
    }

    @Test func rendersTheViewfinderWhenThereIsNoCamera() async {
        let camera = StoryCamera(requestAccess: { true })
        await camera.start()

        ViewRender.render(captureStage(camera: camera))
    }

    @Test func rendersTheViewfinderWhileStartingAndWithAnError() {
        ViewRender.render(captureStage(camera: StoryCamera(requestAccess: { true }), error: "Couldn't take the photo. Try again."))
    }

    private func captureStage(camera: StoryCamera, error: String? = nil) -> some View {
        StoryCaptureStage(
            camera: camera,
            selectedPhoto: .constant(nil),
            errorMessage: error,
            onCapture: { _ in },
            onCaptureFailed: {},
            onCancel: {}
        )
        .background(Color.black)
    }

    // MARK: - Review stage

    @Test func rendersTheReviewStageWithNothingSet() {
        ViewRender.render(reviewStage())
    }

    @Test func rendersTheReviewStageWithEveryDetailSet() {
        ViewRender.render(reviewStage(
            location: "Golden Gate Park",
            labels: "Nudity, Sexual",
            postToBluesky: true
        ))
    }

    @Test func rendersTheReviewStageWhilePostingAndAfterAFailure() {
        ViewRender.render(reviewStage(isUploading: true))
        ViewRender.render(reviewStage(error: "HTTP 413: PayloadTooLarge"))
    }

    private func reviewStage(
        location: String? = nil,
        labels: String? = nil,
        postToBluesky: Bool = false,
        error: String? = nil,
        isUploading: Bool = false
    ) -> some View {
        StoryReviewStage(
            image: photo,
            locationName: location,
            labelSummary: labels,
            postToBluesky: .constant(postToBluesky),
            errorMessage: error,
            isUploading: isUploading,
            onRetake: {},
            onEditLocation: {},
            onClearLocation: {},
            onEditLabels: {},
            onClearLabels: {},
            onPost: {}
        )
        .background(Color.black)
    }

    // MARK: - Detail sheets

    @Test func rendersTheLocationSheetBeforeAndAfterAPick() {
        let env = TestEnvironment()
        ViewRender.render(
            StoryLocationSheet(resolvedLocation: .constant(nil), photoLocationResult: nil) { _ in }
                .withTestEnvironment(env)
        )
        ViewRender.render(
            StoryLocationSheet(
                resolvedLocation: .constant((h3: "8a2a1072b59ffff", name: "Lisboa", address: nil)),
                photoLocationResult: nil
            ) { _ in }
                .withTestEnvironment(env)
        )
    }

    @Test func rendersTheContentLabelSheetExpanded() {
        let env = TestEnvironment()
        ViewRender.render(
            StoryContentLabelSheet(selectedLabels: .constant(["nudity"]))
                .withTestEnvironment(env)
        )
    }

    // MARK: - The whole composer

    @Test func rendersTheComposerWithADeniedCamera() async {
        await withGrainEnvironment {
            MockURLProtocol.respondByPath(Fixtures.routes)
            defer { MockURLProtocol.handler = nil }
            let env = TestEnvironment()

            ViewRender.render(
                StoryCreateView(client: env.client, camera: StoryCamera(requestAccess: { false }))
                    .withTestEnvironment(env),
                settle: 0.3
            )
        }
    }
}
