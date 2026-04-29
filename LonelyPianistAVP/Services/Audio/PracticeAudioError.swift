import Foundation

enum PracticeAudioError: LocalizedError, Equatable {
    case soundFontMissing(resourceName: String)
    case soundFontLoadFailed(resourceName: String, detail: String)

    var errorDescription: String? {
        switch self {
            case let .soundFontMissing(resourceName):
                "未找到音色文件 \(resourceName).sf2。请确认它已被添加到 LonelyPianistAVP 的 App 资源中。"
            case let .soundFontLoadFailed(resourceName, detail):
                "音色文件 \(resourceName).sf2 加载失败：\(detail)"
        }
    }
}
