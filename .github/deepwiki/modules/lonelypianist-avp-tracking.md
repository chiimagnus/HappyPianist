# AVP Tracking

## 范围
追踪页覆盖 HandTracking / WorldTracking、授权、provider 状态和 finger tip 采集。

## 关键对象
| 对象 | 职责 |
| --- | --- |
| `ARTrackingService` | ARKitSession 和 provider 管理 |
| `DataProviderState` | provider 状态表示 |
| `ARGuideViewModel` | 读取追踪数据并驱动校准 / 练习 |

## 行为
- `start()` 会请求必要授权。
- hand / world provider 各自独立记录状态。
- finger tip 更新通过 `AsyncStream` 分发。
- world anchors 会按 id 维护字典。

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


## Coverage Gaps
- 没有设备级自动化验证 hand/world provider 的实际运行差异。

