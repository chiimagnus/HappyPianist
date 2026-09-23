import Foundation

enum JevNetworkCompanionDecisionBackendError: Error, Equatable {
    case backendNotResolved
    case discoveryDenied
    case discoveryFailed(message: String)
    case missingModelIdentity
    case missingActionAnswer
    case invalidAction(String)
}

actor JevNetworkCompanionDecisionBackend: CompanionDecisionBackendProtocol {
    nonisolated let kind: CompanionDecisionBackendKind = .networkBonjourJev
    nonisolated let displayName = "Jev 分类器（电脑本地，实验）"

    private static let actionQuestion = JevQuestion.choice(
        instructions: """
        根据当前音乐交互状态，选择 AI 此刻最合适的参与动作。
        只根据给出的状态判断，不假设未提供的信息。
        """,
        criteria: [
            "listen": "继续听。用户仍在主导演奏，或当前停顿不足以证明乐句已经结束。",
            "support": "轻量陪奏。用户仍在演奏，但存在稳定空间让 AI 柔和加入。",
            "sparse": "稀疏陪奏。AI 可以参与，但必须明显降低音符密度，把主导权留给用户。",
            "yield": "让位。AI 正在演奏，而用户重新明显主导，AI 应停止或退出。",
            "respond": "回应。用户已经明显完成乐句，现在适合由 AI 接一句。",
        ]
    )

    private let discoveryService: any BonjourBackendDiscoveryServiceProtocol
    private let client: any JevClassifierClientProtocol
    private let discoveryTimeout: Duration
    private let requestTimeoutSeconds: TimeInterval

    init(
        discoveryService: any BonjourBackendDiscoveryServiceProtocol,
        client: any JevClassifierClientProtocol = JevClassifierClient(),
        discoveryTimeout: Duration = .seconds(1),
        requestTimeoutSeconds: TimeInterval = 1
    ) {
        self.discoveryService = discoveryService
        self.client = client
        self.discoveryTimeout = discoveryTimeout
        self.requestTimeoutSeconds = requestTimeoutSeconds
    }

    func decide(_ input: CompanionDecisionInput) async throws -> CompanionDecision {
        await MainActor.run {
            switch discoveryService.state {
            case .idle, .failed:
                discoveryService.start()
            case .discovering, .resolved, .denied:
                break
            }
        }

        let endpoint = try await waitForResolvedEndpoint()
        let state = formatState(input)
        let response = try await client.classify(
            host: endpoint.host,
            port: endpoint.port,
            model: endpoint.model,
            state: state,
            questions: ["action": Self.actionQuestion],
            timeoutSeconds: requestTimeoutSeconds
        )
        guard let rawAnswer = response.answers["action"] else {
            throw JevNetworkCompanionDecisionBackendError.missingActionAnswer
        }
        guard case let .choice(answer) = rawAnswer else {
            throw JevNetworkCompanionDecisionBackendError.missingActionAnswer
        }
        guard let action = CompanionAction(rawValue: answer.choice) else {
            throw JevNetworkCompanionDecisionBackendError.invalidAction(answer.choice)
        }
        return CompanionDecision(
            action: action,
            confidence: answer.confidence
        )
    }

    private func formatState(_ input: CompanionDecisionInput) -> String {
        let number = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(3))
        func elapsed(since timestamp: TimeInterval?) -> String {
            guard let timestamp else { return "无" }
            return max(0, input.nowTimestampSeconds - timestamp).formatted(number)
        }

        let recentNotes = input.recentNotes.map { note in
            "\(note.midi)(力度=\(note.velocity),距今=\(note.onsetSecondsAgo.formatted(number))秒,时值=\(note.durationSeconds.formatted(number))秒)"
        }.joined(separator: ", " )
        let ioi = input.recentIOIMedianSeconds.map { $0.formatted(number) + "秒" } ?? "无"
        let pitchCenter = input.activePitchCenter.map { $0.formatted(number) } ?? "无"

        return [
            "当前钢琴交互状态：",
            "当前按住音符数=\(input.heldNotesCount)",
            "延音踏板=\(input.sustainValue)（\(input.sustainValue >= 64 ? "按下" : "抬起")）",
            "最近音符间隔中位数=\(ioi)",
            "最近1秒音符密度=\(input.recentNoteDensityPerSecond.formatted(number))音/秒",
            "近期力度趋势=\(input.recentVelocityTrend.formatted(number))",
            "距最后用户事件=\(elapsed(since: input.lastUserEventTimestampSeconds))秒",
            "距最后一次按键=\(elapsed(since: input.lastNoteOnTimestampSeconds))秒",
            "当前音高中心=\(pitchCenter)",
            "AI当前正在演奏=\(input.isAIPlaybackActive ? "是" : "否")",
            "最近音符=\(recentNotes.isEmpty ? "无" : recentNotes)",
        ].joined(separator: "\n")
    }

    private func waitForResolvedEndpoint() async throws -> (
        host: String,
        port: Int,
        model: String
    ) {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: discoveryTimeout)

        while clock.now < deadline, Task.isCancelled == false {
            let state = await MainActor.run { discoveryService.state }
            switch state {
            case let .resolved(host, port, txtRecord):
                guard let model = txtRecord["engine_impl"], model.isEmpty == false else {
                    throw JevNetworkCompanionDecisionBackendError.missingModelIdentity
                }
                return (host, port, model)
            case .denied:
                throw JevNetworkCompanionDecisionBackendError.discoveryDenied
            case let .failed(message):
                throw JevNetworkCompanionDecisionBackendError.discoveryFailed(message: message)
            case .idle, .discovering:
                break
            }
            try await Task.sleep(for: .milliseconds(25))
        }

        throw JevNetworkCompanionDecisionBackendError.backendNotResolved
    }
}
