import Foundation

/// Normalises the list of pins reported by the controller with the client's existing
/// snapshot so the dashboard always reflects the authoritative order and available zones.
///
/// The controller response is treated as the source of truth: whenever it returns pins we
/// preserve their ordering and omit any placeholders that previously mirrored the static
/// wiring catalogue. This ensures the iOS app only exposes zones that are actually
/// configured on the Raspberry Pi, preventing mismatched GPIO assignments and broken
/// toggles on the dashboard.
struct PinCatalogMerger {
    /// Produces the collection of pins that should be rendered after considering both the
    /// controller response and any locally cached state.
    ///
    /// - Parameters:
    ///   - current: The pins currently stored on the device (for example from the cache or
    ///              previous refresh).
    ///   - remote:  The pins returned by the controller in the latest `/status` payload.
    /// - Returns:  The pins that should be displayed to the user.
    static func merge(current: [PinDTO], remote: [PinDTO]?) -> [PinDTO] {
        guard let remote, !remote.isEmpty else {
            // No controller data available yet – keep whatever the client already has or
            // fall back to the static wiring catalogue so the UI can still render a
            // realistic preview while waiting for the first refresh.
            return current.isEmpty ? PinDTO.makeDefaultSprinklerPins() : current
        }

        let existingByPin = Dictionary(uniqueKeysWithValues: current.map { ($0.pin, $0) })
        let defaultCatalog = PinDTO.makeDefaultSprinklerPins()
        let defaultByPin = Dictionary(uniqueKeysWithValues: defaultCatalog.map { ($0.pin, $0) })

        let mergedRemotePins = remote.map { remotePin -> PinDTO in
            var merged = remotePin

            // Preserve the latest customised label the user may have applied.
            if merged.name == nil, let existingName = existingByPin[remotePin.pin]?.name {
                merged.name = existingName
            }

            // Maintain the toggle state the user saw previously if the controller omitted it.
            if merged.isEnabled == nil, let existingEnabled = existingByPin[remotePin.pin]?.isEnabled {
                merged.isEnabled = existingEnabled
            }

            // Carry forward any in-progress watering state we were already displaying.
            if merged.isActive == nil, let existingActive = existingByPin[remotePin.pin]?.isActive {
                merged.isActive = existingActive
            }

            return merged
        }

        let remotePins = Set(mergedRemotePins.map(\.pin))

        let placeholderPins: [PinDTO] = defaultCatalog
            .filter { !remotePins.contains($0.pin) }
            .map { defaultPin in
                var placeholder = existingByPin[defaultPin.pin] ?? defaultPin

                // Ensure the UI always renders a friendly label, falling back to the
                // wiring catalogue name when a custom value is unavailable.
                if let defaultName = defaultByPin[defaultPin.pin]?.name, (placeholder.name ?? "").isEmpty {
                    placeholder.name = defaultName
                }

                // Missing pins should be treated as hidden/inactive so the counters
                // accurately reflect how many zones are actually enabled.
                placeholder.isEnabled = false
                placeholder.isActive = false

                return placeholder
            }

        return mergedRemotePins + placeholderPins
    }
}
