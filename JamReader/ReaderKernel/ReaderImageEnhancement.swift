import Foundation

nonisolated enum ReaderImageEnhancementLevel: String, CaseIterable, Identifiable, Sendable {
    case off
    case clean
    case crisp
    case hd

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off:
            return "Off"
        case .clean:
            return "Clean"
        case .crisp:
            return "Crisp"
        case .hd:
            return "HD"
        }
    }

    var systemImage: String {
        switch self {
        case .off:
            return "nosign"
        case .clean:
            return "wand.and.sparkles"
        case .crisp:
            return "sparkles"
        case .hd:
            return "square.stack.3d.up"
        }
    }

    var isEnabled: Bool {
        self != .off
    }
}

nonisolated enum ReaderImageModelScale: String, CaseIterable, Identifiable, Sendable {
    case off
    case low
    case medium
    case high
    case ultraHigh

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off:
            return "Off"
        case .low:
            return "Efficiency"
        case .medium:
            return "Normal"
        case .high:
            return "Quality"
        case .ultraHigh:
            return "Extreme"
        }
    }

    var systemImage: String {
        switch self {
        case .off:
            return "cpu"
        case .low, .medium, .high, .ultraHigh:
            return "sparkles"
        }
    }

    var isEnabled: Bool {
        self != .off
    }
}

nonisolated enum ReaderImageModelBackend: String, CaseIterable, Identifiable, Sendable {
    case realCUGAN

    var id: String { rawValue }

    var title: String {
        switch self {
        case .realCUGAN:
            return "Real-CUGAN"
        }
    }

    var systemImage: String {
        switch self {
        case .realCUGAN:
            return "sparkles"
        }
    }
}

nonisolated struct ReaderImageEnhancementSettings: Equatable, Sendable {
    var level: ReaderImageEnhancementLevel
    var modelBackend: ReaderImageModelBackend
    var modelScale: ReaderImageModelScale
    var appliesPerspectiveCorrection: Bool

    static let `default` = ReaderImageEnhancementSettings(
        level: .off,
        modelBackend: .realCUGAN,
        modelScale: .off,
        appliesPerspectiveCorrection: false
    )

    var isEnabled: Bool {
        level.isEnabled || modelScale.isEnabled || appliesPerspectiveCorrection
    }

    var systemImage: String {
        if modelScale.isEnabled {
            return modelBackend.systemImage
        }

        if level.isEnabled {
            return level.systemImage
        }

        if appliesPerspectiveCorrection {
            return "crop.rotate"
        }

        return level.systemImage
    }

    var storageKey: String {
        "\(level.rawValue)-backend-\(modelBackend.rawValue)-model-\(modelScale.rawValue)-perspective-\(appliesPerspectiveCorrection)"
    }

    var preferredDecodeMaxPixelSize: Int? {
        switch modelBackend {
        case .realCUGAN:
            return ReaderRealCUGANCoreMLBackend.preferredDecodeMaxPixelSize(for: modelScale)
        }
    }

    var persistentRenderingSettings: ReaderImageEnhancementSettings {
        self
    }

    var cacheKey: String {
        "v23-realcugan2x-pro-conservative-tile432-copyopt-\(storageKey)"
    }
}

final class ReaderImageEnhancementPreferencesStore {
    private let userDefaults: UserDefaults
    private let levelKey = "reader.imageEnhancement.level"
    private let modelBackendKey = "reader.imageEnhancement.modelBackend"
    private let modelScaleKey = "reader.imageEnhancement.modelScale"
    private let perspectiveKey = "reader.imageEnhancement.perspectiveCorrection"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func loadSettings() -> ReaderImageEnhancementSettings {
        let level = userDefaults.string(forKey: levelKey)
            .flatMap(ReaderImageEnhancementLevel.init(rawValue:))
            ?? ReaderImageEnhancementSettings.default.level
        let modelBackend = userDefaults.string(forKey: modelBackendKey)
            .flatMap(ReaderImageModelBackend.init(rawValue:))
            ?? ReaderImageEnhancementSettings.default.modelBackend
        let modelScale = userDefaults.string(forKey: modelScaleKey)
            .flatMap { storedValue in
                ReaderImageModelScale(rawValue: storedValue)
                    ?? (storedValue == "x2" ? .ultraHigh : nil)
            }
            ?? ReaderImageEnhancementSettings.default.modelScale

        let appliesPerspectiveCorrection = userDefaults.object(forKey: perspectiveKey) == nil
            ? ReaderImageEnhancementSettings.default.appliesPerspectiveCorrection
            : userDefaults.bool(forKey: perspectiveKey)

        return ReaderImageEnhancementSettings(
            level: level,
            modelBackend: modelBackend,
            modelScale: modelScale,
            appliesPerspectiveCorrection: appliesPerspectiveCorrection
        )
    }

    func saveSettings(_ settings: ReaderImageEnhancementSettings) {
        userDefaults.set(settings.level.rawValue, forKey: levelKey)
        userDefaults.set(settings.modelBackend.rawValue, forKey: modelBackendKey)
        userDefaults.set(settings.modelScale.rawValue, forKey: modelScaleKey)
        userDefaults.set(settings.appliesPerspectiveCorrection, forKey: perspectiveKey)
    }
}

nonisolated enum ReaderImageEnhancementNamespace {
    nonisolated static func namespace(
        documentURL: URL,
        settings: ReaderImageEnhancementSettings
    ) -> String {
        let baseNamespace = ReaderPageCache.namespace(for: documentURL)
        guard settings.isEnabled else {
            return baseNamespace
        }

        return "enhanced-\(settings.cacheKey)-\(baseNamespace)"
    }
}
