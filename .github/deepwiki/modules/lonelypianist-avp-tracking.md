# AVP Tracking

## 范围
追踪页覆盖 HandTracking / WorldTracking / PlaneDetection、授权、provider 状态、hand skeleton 关键点采集，以及平面 anchors 的维护。

## 关键对象
| 对象 | 职责 |
| --- | --- |
| `ARTrackingService` | ARKitSession 和 provider 管理 |
| `DataProviderState` | provider 状态表示 |
| `ARGuideViewModel` | 读取追踪数据并驱动校准 / 练习 |

## 行为
- `start()` 会请求必要授权。
- hand / world / plane provider 各自独立记录状态（`providerStateByName["hand"|"world"|"plane"]`）。
- finger tip 更新通过 `AsyncStream` 分发。
- world anchors 会按 id 维护字典。
- plane anchors 会按 id 维护字典（来自 `PlaneDetectionProvider(alignments: [.horizontal])` 的 `anchorUpdates`）。
- 手部关键点在服务层会拆出便于业务使用的属性（例如 `leftIndexFingerTipPosition` / `leftThumbTipPosition` / `rightIndexFingerTipPosition` / `rightThumbTipPosition`），用于 Step 1 校准 reticle 输入与捏合判定。
- 另外会在 `fingerTipPositions` 中补充更稳定的掌心中心点：`left-palmCenter` / `right-palmCenter`（由 `wrist + *Metacarpal + thumbKnuckle` 的 tracked 点位求平均近似）。

## 状态
| 状态 | 含义 |
| --- | --- |
| `idle` | 未启动 |
| `running` | 正在运行 |
| `unsupported` | 设备不支持 |
| `unauthorized` | 未授权 |
| `stopped` | 已停止 |
| `failed` | 启动失败 |

## 调试抓手
- `providerStateByName`
- `authorizationStatusByType`
- `fingerTipPositions`
- `worldAnchorsByID`
- `planeAnchorsByID`


## Coverage Gaps
- 没有设备级自动化验证 hand/world/plane provider 的实际运行差异（尤其是 plane detection 的稳定性和延迟）。

## 更新记录（Update Notes）
- 2026-04-26: 补充左手拇指 tip 追踪点（用于 C8 校准的左手捏合确认），并同步 tracking 页对外暴露点位说明。
- 2026-05-02: 新增 `PlaneDetectionProvider`（horizontal planes）与 `planeAnchorsByID`；在 `fingerTipPositions` 中补充 `*-palmCenter` 用于虚拟钢琴放置确认。
