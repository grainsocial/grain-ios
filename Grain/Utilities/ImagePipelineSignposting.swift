import Foundation
import Nuke
import os

private let diskCacheSignposter = OSSignposter(subsystem: "social.grain.grain", category: "DiskCache")

/// Emits an os_signpost event every time Nuke is about to write an image to
/// the on-disk `DataCache`. After the "fullsize never disk-cached" refactor,
/// only thumb + avatar URLs should appear in `DiskCacheWrite` events — a
/// fullsize URL showing up means the `.disableDiskCacheWrites` option leaked.
/// `data.count` in the event payload makes thumb (~50–300 KB) vs fullsize
/// (~1–5 MB) vs avatar (~5–50 KB) obvious at a glance.
final class GrainImagePipelineDelegate: ImagePipelineDelegate {
    func willCache(
        data: Data,
        image _: ImageContainer?,
        for request: ImageRequest,
        pipeline _: ImagePipeline,
        completion: @escaping (Data?) -> Void
    ) {
        let name = request.url?.lastPathComponent ?? "nil"
        diskCacheSignposter.emitEvent("DiskCacheWrite", "\(name) bytes=\(data.count)")
        completion(data)
    }
}
