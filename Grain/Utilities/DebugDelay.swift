#if DEBUG
    import Foundation

    /// Artificial per-request latency so loading states can be eyeballed at
    /// something other than fast-wifi speed. DEBUG-only and off unless
    /// `GRAIN_NETWORK_DELAY` is set, either to a preset or to raw seconds:
    ///
    ///     SIMCTL_CHILD_GRAIN_NETWORK_DELAY=3g just sim
    ///     SIMCTL_CHILD_GRAIN_NETWORK_DELAY=0.4 just sim
    ///
    /// or, in Xcode, Scheme → Run → Arguments → Environment Variables.
    ///
    /// Applied inside `XRPCClient`, so every API call pays it independently and
    /// concurrent requests still overlap — unlike a per-screen sleep, which
    /// collapses the staggering that makes a slow connection look the way it
    /// does. Image loads go through Nuke rather than XRPCClient, so thumbnails
    /// stay at full speed.
    enum DebugDelay {
        /// Round-trip times roughly matching Network Link Conditioner's profiles.
        private static let presets: [String: Double] = [
            "wifi": 0.02,
            "lte": 0.065,
            "3g": 0.4,
            "edge": 0.84,
            "slow": 1.5,
        ]

        static let seconds: Double = {
            guard let raw = ProcessInfo.processInfo.environment["GRAIN_NETWORK_DELAY"]?
                .trimmingCharacters(in: .whitespaces).lowercased(), !raw.isEmpty
            else { return 0 }
            if let preset = presets[raw] {
                return preset
            }
            guard let value = Double(raw), value > 0 else { return 0 }
            return value
        }()

        static func wait() async {
            guard seconds > 0 else { return }
            try? await Task.sleep(for: .seconds(seconds))
        }
    }
#endif
