import Foundation
import Observation

@MainActor
@Observable
final class HomeViewModel {
    private let appModel: AppModel

    var isImporterPresented = false

    init(appModel: AppModel) {
        self.appModel = appModel
    }

    var immersiveSpaceState: AppModel.ImmersiveSpaceState {
        appModel.immersiveSpaceState
    }

    var calibrationStatusText: String {
        appModel.calibration == nil ? "未设置" : "已加载"
    }

    var scoreStatusText: String {
        appModel.importedFile?.fileName ?? "未导入"
    }

    var stepCountText: String? {
        guard appModel.importedSteps.isEmpty == false else { return nil }
        return "\(appModel.importedSteps.count)"
    }

    var nextActionHint: String {
        if appModel.calibration == nil {
            return "下一步：进入 Step 1 完成校准（设置 A0 / C8 后保存）。"
        }
        if appModel.importedSteps.isEmpty {
            return "下一步：返回主窗口并用右上角 toolbar 导入 MusicXML（.musicxml 或 .xml）。"
        }
        return "下一步：进入 Step 2 开始练习。"
    }

    var importErrorMessage: String? {
        appModel.importErrorMessage
    }

    var calibrationStatusMessage: String? {
        appModel.calibrationStatusMessage
    }

    func clearImportError() {
        appModel.importErrorMessage = nil
    }

    var canImportScore: Bool {
        immersiveSpaceState == .closed
    }

    var canEnterPractice: Bool {
        appModel.calibration != nil && appModel.importedSteps.isEmpty == false
    }

    func handleImportResult(_ result: Result<[URL], Error>) {
        do {
            guard let selectedURL = try result.get().first else { return }
            appModel.importMusicXML(from: selectedURL)
        } catch {
            appModel.importErrorMessage = "导入失败：\(error.localizedDescription)"
        }
    }

}
