import ImageIO
import os
import PhotosUI
import SwiftUI
import SwiftyH3

private let logger = Logger(subsystem: "social.grain.grain", category: "Create")

struct CreateGalleryView: View {
    @Environment(AuthManager.self) private var auth
    @State private var title = ""
    @State private var description = ""
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var photoData: [(Data, String)] = [] // (data, mimeType)
    @Environment(\.dismiss) private var dismiss
    @State private var isUploading = false
    @State private var errorMessage: String?
    @State private var resolvedLocation: (h3: String, name: String, address: [String: AnyCodable]?)?
    @State private var locationQuery = ""
    @State private var locationSuggestions: [NominatimResult] = []
    @State private var isSearchingLocation = false
    @State private var locationSearchTask: Task<Void, Never>?

    let client: XRPCClient
    var onCreated: (() -> Void)?

    var body: some View {
        NavigationStack {
            Form {
                Section("Photos") {
                    PhotosPicker(
                        selection: $selectedPhotos,
                        maxSelectionCount: 20,
                        matching: .images
                    ) {
                        Label("Select Photos", systemImage: "photo.on.rectangle.angled")
                    }

                    if !selectedPhotos.isEmpty {
                        Text("\(selectedPhotos.count) photo(s) selected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Details") {
                    TextField("Title", text: $title)
                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Location") {
                    if let loc = resolvedLocation {
                        HStack {
                            Label(loc.name, systemImage: "mappin.and.ellipse")
                                .font(.subheadline)
                                .lineLimit(1)
                            Spacer()
                            Button {
                                resolvedLocation = nil
                                locationQuery = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                            TextField("Search for a location...", text: $locationQuery)
                                .textInputAutocapitalization(.never)
                                .onChange(of: locationQuery) {
                                    locationSearchTask?.cancel()
                                    let query = locationQuery
                                    locationSearchTask = Task {
                                        try? await Task.sleep(for: .milliseconds(300))
                                        guard !Task.isCancelled else { return }
                                        await searchLocation(query: query)
                                    }
                                }
                            if isSearchingLocation {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }

                        ForEach(locationSuggestions, id: \.placeId) { result in
                            Button {
                                selectLocation(result)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.name)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                    if let context = result.context {
                                        Text(context)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .onChange(of: selectedPhotos) {
                Task { await detectLocation() }
            }
            .navigationTitle("New Gallery")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await createGallery() }
                    } label: {
                        if isUploading {
                            ProgressView()
                        } else {
                            Text("Post")
                                .bold()
                        }
                    }
                    .disabled(title.isEmpty || selectedPhotos.isEmpty || isUploading)
                }
            }
        }
    }

    /// Auto-detect location from first photo with GPS when photos are selected.
    private func detectLocation() async {
        resolvedLocation = nil
        locationQuery = ""
        locationSuggestions = []

        for item in selectedPhotos {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let gps = extractGPS(from: data) else { continue }

            if let result = await reverseGeocode(latitude: gps.latitude, longitude: gps.longitude) {
                selectLocation(result)
            }
            break
        }
    }

    /// Forward geocode search via Nominatim.
    private func searchLocation(query: String) async {
        guard query.trimmingCharacters(in: .whitespaces).count >= 2 else {
            locationSuggestions = []
            return
        }
        isSearchingLocation = true
        defer { isSearchingLocation = false }

        var components = URLComponents(string: "https://nominatim.openstreetmap.org/search")!
        components.queryItems = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "q", value: query.trimmingCharacters(in: .whitespaces)),
            URLQueryItem(name: "limit", value: "5"),
            URLQueryItem(name: "addressdetails", value: "1"),
        ]
        guard let url = components.url else { return }

        var request = URLRequest(url: url)
        request.setValue("grain-app/1.0", forHTTPHeaderField: "User-Agent")

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            locationSuggestions = []
            return
        }

        locationSuggestions = json.compactMap { NominatimResult(from: $0) }
    }

    /// Select a location from search results.
    private func selectLocation(_ result: NominatimResult) {
        let h3 = latLonToH3(latitude: result.latitude, longitude: result.longitude)
        resolvedLocation = (h3: h3, name: result.name, address: result.address)
        locationQuery = ""
        locationSuggestions = []
    }

    private func createGallery() async {
        guard let authContext = auth.authContext(), let repo = auth.userDID else { return }
        isUploading = true
        errorMessage = nil

        do {
            // 1. Load, extract EXIF, resize, and upload photos
            struct ProcessedPhoto {
                let blob: BlobRef
                let aspectRatio: AspectRatio
                let exif: [String: AnyCodable]?
            }

            var processed: [ProcessedPhoto] = []
            for item in selectedPhotos {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let original = UIImage(data: data) else { continue }

                let exif = extractExif(from: data)
                let (resized, size) = resizeImage(original, maxDimension: 2000, maxBytes: 900_000)
                logger.warning("Uploading \(resized.count) bytes, \(Int(size.width))x\(Int(size.height))")
                let response = try await client.uploadBlob(data: resized, mimeType: "image/jpeg", auth: authContext)
                processed.append(ProcessedPhoto(
                    blob: response.blob,
                    aspectRatio: AspectRatio(width: Int(size.width), height: Int(size.height)),
                    exif: exif
                ))
            }

            // 2. Create photo records + EXIF records
            let now = ISO8601DateFormatter().string(from: Date())
            var photoUris: [String] = []
            for photo in processed {
                let blobDict: [String: AnyCodable] = [
                    "$type": AnyCodable(photo.blob.type ?? "blob"),
                    "ref": AnyCodable(["$link": AnyCodable(photo.blob.ref?.link ?? "")] as [String: AnyCodable]),
                    "mimeType": AnyCodable(photo.blob.mimeType ?? "image/jpeg"),
                    "size": AnyCodable(photo.blob.size ?? 0)
                ]
                let photoRecord: [String: AnyCodable] = [
                    "photo": AnyCodable(blobDict),
                    "aspectRatio": AnyCodable(["width": AnyCodable(photo.aspectRatio.width), "height": AnyCodable(photo.aspectRatio.height)] as [String: AnyCodable]),
                    "createdAt": AnyCodable(now)
                ]
                let result = try await client.createRecord(
                    collection: "social.grain.photo",
                    repo: repo,
                    record: AnyCodable(photoRecord),
                    auth: authContext
                )
                guard let uri = result.uri else { continue }
                photoUris.append(uri)

                // Create EXIF record if we extracted metadata
                if var exif = photo.exif {
                    exif["photo"] = AnyCodable(uri)
                    exif["createdAt"] = AnyCodable(now)
                    _ = try await client.createRecord(
                        collection: "social.grain.photo.exif",
                        repo: repo,
                        record: AnyCodable(exif),
                        auth: authContext
                    )
                }
            }

            // 3. Create gallery record with pre-resolved location
            var galleryRecord: [String: AnyCodable] = [
                "title": AnyCodable(title),
                "createdAt": AnyCodable(now)
            ]
            if !description.isEmpty { galleryRecord["description"] = AnyCodable(description) }
            if let loc = resolvedLocation {
                galleryRecord["location"] = AnyCodable([
                    "value": AnyCodable(loc.h3),
                    "name": AnyCodable(loc.name)
                ] as [String: AnyCodable])
                if let addr = loc.address {
                    galleryRecord["address"] = AnyCodable(addr)
                }
            }
            let galleryResult = try await client.createRecord(
                collection: "social.grain.gallery",
                repo: repo,
                record: AnyCodable(galleryRecord),
                auth: authContext
            )

            // 4. Create gallery items linking photos to gallery
            if let galleryUri = galleryResult.uri {
                for (index, photoUri) in photoUris.enumerated() {
                    let itemRecord: [String: AnyCodable] = [
                        "gallery": AnyCodable(galleryUri),
                        "item": AnyCodable(photoUri),
                        "position": AnyCodable(index),
                        "createdAt": AnyCodable(now)
                    ]
                    _ = try await client.createRecord(
                        collection: "social.grain.gallery.item",
                        repo: repo,
                        record: AnyCodable(itemRecord),
                        auth: authContext
                    )
                }
            }

            // Done — dismiss and refresh
            onCreated?()
            dismiss()
        } catch let XRPCError.httpError(statusCode, body) {
            let bodyStr = body.flatMap { String(data: $0, encoding: .utf8) } ?? "no body"
            errorMessage = "HTTP \(statusCode): \(bodyStr)"
        } catch {
            errorMessage = error.localizedDescription
        }
        isUploading = false
    }

    // MARK: - Image Processing

    /// Resize image to fit within maxDimension and binary-search JPEG quality to stay under maxBytes.
    private func resizeImage(_ image: UIImage, maxDimension: CGFloat, maxBytes: Int) -> (Data, CGSize) {
        // Use pixel dimensions, not points
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        let scaleFactor = min(maxDimension / pixelWidth, maxDimension / pixelHeight, 1)
        var newSize = CGSize(width: round(pixelWidth * scaleFactor), height: round(pixelHeight * scaleFactor))

        // Render at 1x scale so size = pixels
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        var renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        var scaled = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }

        // Binary search for quality that fits under maxBytes
        var best = scaled.jpegData(compressionQuality: 0.01) ?? Data()
        var lo: CGFloat = 0
        var hi: CGFloat = 1

        for _ in 0..<10 {
            let mid = (lo + hi) / 2
            guard let data = scaled.jpegData(compressionQuality: mid) else { break }
            if data.count <= maxBytes {
                best = data
                lo = mid
            } else {
                hi = mid
            }
        }

        // If even lowest quality is too large, scale down further
        if best.count > maxBytes {
            let downScale = sqrt(Double(maxBytes) / Double(best.count))
            newSize = CGSize(width: round(newSize.width * downScale), height: round(newSize.height * downScale))
            let fmt = UIGraphicsImageRendererFormat()
            fmt.scale = 1
            renderer = UIGraphicsImageRenderer(size: newSize, format: fmt)
            scaled = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
            best = scaled.jpegData(compressionQuality: 0.8) ?? Data()
        }

        return (best, newSize)
    }

    /// Extract EXIF metadata from image data using ImageIO. Returns nil if no useful EXIF found.
    /// Numeric values are scaled by 1_000_000 to match the web app's format.
    private func extractExif(from data: Data) -> [String: AnyCodable]? {
        let scale = 1_000_000

        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            logger.warning("No image properties found")
            return nil
        }

        let exifDict = properties[kCGImagePropertyExifDictionary as String] as? [String: Any]
        let tiffDict = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
        let exifAux = properties[kCGImagePropertyExifAuxDictionary as String] as? [String: Any]
        var result: [String: AnyCodable] = [:]

        // Make & Model (from TIFF)
        if let make = tiffDict?[kCGImagePropertyTIFFMake as String] as? String {
            result["make"] = AnyCodable(make.trimmingCharacters(in: .whitespaces))
        }
        if let model = tiffDict?[kCGImagePropertyTIFFModel as String] as? String {
            result["model"] = AnyCodable(model.trimmingCharacters(in: .whitespaces))
        }

        // Lens — check ExifAux first (where iOS typically puts it), then EXIF dict
        if let lensMake = exifAux?["LensMake"] as? String ?? exifDict?["LensMake"] as? String ?? tiffDict?[kCGImagePropertyTIFFMake as String] as? String {
            result["lensMake"] = AnyCodable(lensMake.trimmingCharacters(in: .whitespaces))
        }
        if let lensModel = exifAux?["LensModel"] as? String ?? exifDict?[kCGImagePropertyExifLensModel as String] as? String {
            result["lensModel"] = AnyCodable(lensModel.trimmingCharacters(in: .whitespaces))
        }

        // Exposure Time (seconds -> scaled int)
        if let exposureTime = exifDict?[kCGImagePropertyExifExposureTime as String] as? Double {
            result["exposureTime"] = AnyCodable(Int(exposureTime * Double(scale)))
        }

        // F-Number
        if let fNumber = exifDict?[kCGImagePropertyExifFNumber as String] as? Double {
            result["fNumber"] = AnyCodable(Int(fNumber * Double(scale)))
        }

        // ISO — can be [Int] or NSArray of NSNumber
        if let isoRaw = exifDict?[kCGImagePropertyExifISOSpeedRatings as String] as? [Any],
           let iso = (isoRaw.first as? NSNumber)?.intValue {
            result["iSO"] = AnyCodable(iso * scale)
        }

        // Focal Length in 35mm
        if let focal35 = exifDict?[kCGImagePropertyExifFocalLenIn35mmFilm as String] as? Int {
            result["focalLengthIn35mmFormat"] = AnyCodable(focal35 * scale)
        } else if let focal35 = exifDict?[kCGImagePropertyExifFocalLenIn35mmFilm as String] as? Double {
            result["focalLengthIn35mmFormat"] = AnyCodable(Int(focal35) * scale)
        }

        // Flash
        if let flash = exifDict?[kCGImagePropertyExifFlash as String] as? Int {
            let flashStr: String
            switch flash {
            case 0: flashStr = "Off, Did not fire"
            case 1: flashStr = "On, Fired"
            case 5: flashStr = "On, Return not detected"
            case 7: flashStr = "On, Return detected"
            case 16: flashStr = "Off, Did not fire"
            case 24: flashStr = "Off, Auto"
            case 25: flashStr = "On, Auto"
            default: flashStr = "Unknown (\(flash))"
            }
            result["flash"] = AnyCodable(flashStr)
        }

        // DateTimeOriginal
        if let dateStr = exifDict?[kCGImagePropertyExifDateTimeOriginal as String] as? String {
            // EXIF format: "2024:01:15 14:30:00" -> ISO 8601
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
            if let date = formatter.date(from: dateStr) {
                result["dateTimeOriginal"] = AnyCodable(ISO8601DateFormatter().string(from: date))
            }
        }

        return result.isEmpty ? nil : result
    }

    // MARK: - GPS & Location

    /// Extract GPS coordinates from image data. Returns (latitude, longitude) or nil.
    private func extractGPS(from data: Data) -> (latitude: Double, longitude: Double)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let gpsDict = properties[kCGImagePropertyGPSDictionary as String] as? [String: Any] else {
            return nil
        }

        guard let latitude = gpsDict[kCGImagePropertyGPSLatitude as String] as? Double,
              let latRef = gpsDict[kCGImagePropertyGPSLatitudeRef as String] as? String,
              let longitude = gpsDict[kCGImagePropertyGPSLongitude as String] as? Double,
              let lonRef = gpsDict[kCGImagePropertyGPSLongitudeRef as String] as? String else {
            return nil
        }

        let lat = latRef == "S" ? -latitude : latitude
        let lon = lonRef == "W" ? -longitude : longitude
        return (lat, lon)
    }

    /// Convert lat/lon to H3 index string at resolution 10.
    private func latLonToH3(latitude: Double, longitude: Double) -> String {
        let latLng = H3LatLng(latitudeDegs: latitude, longitudeDegs: longitude)
        guard let cell = try? latLng.cell(at: .res10) else { return "" }
        return cell.description
    }

    /// Reverse geocode coordinates via Nominatim.
    private func reverseGeocode(latitude: Double, longitude: Double) async -> NominatimResult? {
        var components = URLComponents(string: "https://nominatim.openstreetmap.org/reverse")!
        components.queryItems = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "lat", value: String(latitude)),
            URLQueryItem(name: "lon", value: String(longitude)),
            URLQueryItem(name: "addressdetails", value: "1"),
        ]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue("grain-app/1.0", forHTTPHeaderField: "User-Agent")

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        return NominatimResult(from: json)
    }
}

// MARK: - Nominatim

private struct NominatimResult {
    let placeId: Int
    let latitude: Double
    let longitude: Double
    let name: String
    let context: String?
    let address: [String: AnyCodable]?

    init?(from json: [String: Any]) {
        guard let placeId = json["place_id"] as? Int else { return nil }
        self.placeId = placeId

        // lat/lon can be String or Double from Nominatim
        if let lat = json["lat"] as? String, let lon = json["lon"] as? String,
           let latD = Double(lat), let lonD = Double(lon) {
            self.latitude = latD
            self.longitude = lonD
        } else if let lat = json["lat"] as? Double, let lon = json["lon"] as? Double {
            self.latitude = lat
            self.longitude = lon
        } else {
            return nil
        }

        let addr = json["address"] as? [String: Any]
        let city = addr?["city"] as? String ?? addr?["town"] as? String ?? addr?["village"] as? String

        // Name: place name or city/state/country
        if let placeName = json["name"] as? String, !placeName.isEmpty {
            self.name = placeName
        } else {
            var parts: [String] = []
            if let city { parts.append(city) }
            if let state = addr?["state"] as? String { parts.append(state) }
            if let country = addr?["country"] as? String { parts.append(country) }
            self.name = parts.isEmpty
                ? (json["display_name"] as? String ?? "Unknown").components(separatedBy: ",").first ?? "Unknown"
                : parts.joined(separator: ", ")
        }

        // Context: city, state, country for disambiguation
        var contextParts: [String] = []
        if let city { contextParts.append(city) }
        if let state = addr?["state"] as? String { contextParts.append(state) }
        if let country = addr?["country"] as? String { contextParts.append(country) }
        self.context = contextParts.isEmpty ? nil : contextParts.joined(separator: ", ")

        // Structured address
        if let countryCode = (addr?["country_code"] as? String)?.uppercased() {
            var a: [String: AnyCodable] = ["country": AnyCodable(countryCode)]
            if let city { a["locality"] = AnyCodable(city) }
            if let state = addr?["state"] as? String { a["region"] = AnyCodable(state) }
            if let road = addr?["road"] as? String {
                if let houseNumber = addr?["house_number"] as? String {
                    a["street"] = AnyCodable("\(houseNumber) \(road)")
                } else {
                    a["street"] = AnyCodable(road)
                }
            }
            if let postcode = addr?["postcode"] as? String { a["postalCode"] = AnyCodable(postcode) }
            self.address = a
        } else {
            self.address = nil
        }
    }
}
