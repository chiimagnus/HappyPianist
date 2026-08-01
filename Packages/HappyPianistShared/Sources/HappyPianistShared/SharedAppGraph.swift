import Foundation

/// Resources supplied by the App target that embeds the shared feature set.
///
/// A Swift package's resource bundle is deliberately not used for app-owned models,
/// soundfonts, or seed scores. Each host retains ownership of those assets.
public struct SharedAppResources {
    private let hostBundle: Bundle

    public init(hostBundle: Bundle) {
        self.hostBundle = hostBundle
    }

    public func url(forResource name: String, withExtension ext: String?) -> URL? {
        hostBundle.url(forResource: name, withExtension: ext)
    }
}

/// The non-spatial practice inputs available to every host.
public enum SharedPracticeInputMode: String, CaseIterable, Sendable {
    case bluetoothMIDI
    case targetAudio
}

/// Entry point for common composition that is independent of spatial UI.
public enum SharedAppGraph {
    // ponytail: this starts as a resource boundary; services move here only once both hosts consume them.
    public static func resources(hostBundle: Bundle) -> SharedAppResources {
        SharedAppResources(hostBundle: hostBundle)
    }
}
