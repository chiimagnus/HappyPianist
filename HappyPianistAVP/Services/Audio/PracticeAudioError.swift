import Foundation

enum PracticeAudioError: LocalizedError, Equatable, Sendable {
    case soundFontMissing(resourceName: String)
    case operationFailed(
        operation: PianoPerformanceAudioOperation,
        recovery: PianoPerformanceAudioRecovery,
        detail: String
    )

    var operation: PianoPerformanceAudioOperation {
        switch self {
        case .soundFontMissing:
            .soundFontLoad
        case let .operationFailed(operation, _, _):
            operation
        }
    }

    var recovery: PianoPerformanceAudioRecovery {
        switch self {
        case .soundFontMissing:
            .unrecoverable
        case let .operationFailed(_, recovery, _):
            recovery
        }
    }

    var errorDescription: String? {
        switch self {
        case let .soundFontMissing(resourceName):
            "未找到音色文件 \(resourceName).sf2。请确认它已被添加到 HappyPianistAVP 的 App 资源中。"
        case let .operationFailed(operation, _, detail):
            "\(operation.userFacingName)失败：\(detail)"
        }
    }
}

enum PracticeAudioPlaybackState: Equatable, Sendable {
    case idle
    case ready
    case failed(PracticeAudioError)
}

private extension PianoPerformanceAudioOperation {
    var userFacingName: String {
        switch self {
        case .audioSessionConfiguration:
            "音频会话配置"
        case .soundFontLoad:
            "音色加载"
        case .engineStart:
            "音频引擎启动"
        case .sequenceLoad:
            "演奏序列加载"
        case .sequenceStart:
            "演奏序列启动"
        case .commandRender:
            "音频指令渲染"
        case .interruption:
            "音频中断处理"
        case .routeChange:
            "音频路由切换"
        case .mediaServicesReset:
            "音频服务重置"
        case .transportReset:
            "音频停止复位"
        }
    }
}
