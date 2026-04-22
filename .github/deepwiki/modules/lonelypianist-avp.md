# 模块：LonelyPianistAVP（visionOS）

## 职责与边界
- **负责**：
  - Step 1：世界锚点校准（A0/C8）；
  - Step 2：曲库导入、索引管理、音频绑定与试听；
  - Step 3：沉浸空间定位、手部追踪按键检测、步骤高亮推进。
- **不负责**：
  - MIDI 映射与对话推理（由 macOS / Python 负责）；
  - PDF/图片转谱（只消费外部 MusicXML）。

## 目录范围
| 路径 | 角色 | 说明 |
| --- | --- | --- |
| `LonelyPianistAVP/LonelyPianistAVPApp.swift` | App 入口 | 组装 `AppModel` 与 3 个 ViewModel |
| `LonelyPianistAVP/AppModel.swift` | 全局状态中枢 | 汇聚导入、校准、定位与练习会话 |
| `LonelyPianistAVP/Views/ContentView.swift` | 三步流程入口 | `NavigationStack` 路由 Step 1/2/3 |
| `LonelyPianistAVP/Views/CalibrationStepView.swift` | Step 1 | 校准捕获与保存 |
| `LonelyPianistAVP/Views/Library/SongLibraryView.swift` | Step 2 | 曲库导入、删除、绑定音频、进入练习 |
| `LonelyPianistAVP/Views/PracticeStepView.swift` | Step 3 | 练习状态、定位状态、手动推进按钮 |
| `LonelyPianistAVP/ViewModels/ARGuideViewModel.swift` | 定位与练习编排 | provider/anchor 状态机 |
| `LonelyPianistAVP/ViewModels/Library/SongLibraryViewModel.swift` | 曲库编排 | 索引、文件、试听状态一致性维护 |
| `LonelyPianistAVP/Services/Library/SongAudioPlayer.swift` | 试听播放器 | `AVAudioPlayer` 封装与播放态回调 |
| `LonelyPianistAVP/Services/Tracking/ARTrackingService.swift` | AR provider 接线 | 指尖/锚点/授权/状态 |
| `LonelyPianistAVP/Services/Library/*` | 曲库存储服务层 | index、score、audio、seed、playback |

## 入口点与生命周期
| 入口 / 事件 | 文件 | 触发时机 | 行为 |
| --- | --- | --- | --- |
| App 初始化 | `LonelyPianistAVPApp.swift` | 启动时 | 加载校准、seed 曲库（MusicXML + 音频）、初始化 ViewModels |
| 打开沉浸空间 | `ARGuideViewModel.openImmersiveForStep` | Step 1 / Step 3 进入时 | 管理 `.closed/.inTransition/.open` 状态 |
| 手部与世界追踪启动 | `ARTrackingService.start()` | 沉浸空间 onAppear 后 | 请求授权并启动 providers |
| 曲库导入 | `SongLibraryViewModel.importMusicXML` | Step 2 导入动作 | 文件复制 + 索引更新 |
| 练习准备 | `SongLibraryViewModel.preparePractice` | Step 2 点击“开始练习” | 解析 score、构建步骤、注入 AppModel |

## 上下游依赖
| 方向 | 对象 | 关系 | 风险 |
| --- | --- | --- | --- |
| 上游 | 外部 MusicXML / 音频文件 | fileImporter 输入 | 文件格式与可读性 |
| 上游 | ARKit Hand/World Tracking | 持续 anchor 与手指更新 | 权限、支持度、环境变化 |
| 下游 | RealityKit overlay controllers | 可视化键位、指尖、reticle | 状态不同步会出现误导 |
| 下游 | SongLibrary 文件系统 | 曲库索引与资源持久化 | 索引-文件漂移 |

## 对外接口与契约
| 契约 | 位置 | 调用方 | 含义 |
| --- | --- | --- | --- |
| `SongLibraryIndexStoreProtocol` | `Services/Library/SongLibraryIndexStore.swift` | SongLibraryViewModel | 索引 load/save |
| `SongFileStoreProtocol` | `Services/Library/SongFileStore.swift` | SongLibraryViewModel | 曲谱与音频文件读写 |
| `AudioImportServiceProtocol` | `Services/Library/AudioImportService.swift` | SongLibraryViewModel | 音频导入与去重 |
| `ARTrackingServiceProtocol` | `Services/Tracking/ARTrackingService.swift` | ARGuideViewModel | provider 状态与 tracking 数据 |
| `WorldAnchorCalibrationStoreProtocol` | `Services/WorldAnchorCalibrationStore.swift` | AppModel | 校准持久化 |

## 数据契约、状态与存储
- 关键模型：
  - `StoredWorldAnchorCalibration`（持久化 anchor ID）；
  - `SongLibraryIndex / SongLibraryEntry`（曲库元数据）；
  - `PracticeStep`（练习步进）；
  - `DataProviderState`（provider 状态）。
- 关键状态：
  - `ImmersiveSpaceState`：`closed / inTransition / open`；
  - `PracticeLocalizationState`：`idle / blocked / opening / waiting / locating / failed / ready`；
  - `PracticeState`：`idle / ready / guiding / completed`。
- 试听状态：
  - `SongLibraryViewModel` 以 `currentListeningEntryID` / `isCurrentListeningPlaying` 驱动曲库页的“聆听/暂停”按钮；
  - `SongAudioPlaybackStateController` 与 `SongAudioPlayer` 负责播放态切换、暂停、恢复与完成回调。
- 关键存储：
  - `Documents/piano-worldanchor-calibration.json`
  - `Documents/SongLibrary/index.json`
  - `Documents/SongLibrary/scores/*`
  - `Documents/SongLibrary/audio/*`

## 正常路径与边界情况
| 场景 | 正常路径 | 边界处理 |
| --- | --- | --- |
| Step 1 校准 | 捕获 A0/C8 -> 保存 | 不完整校准返回“校准信息不完整” |
| Step 2 选曲 | 导入 MusicXML -> 更新索引 | 索引写入失败会回滚已复制文件 |
| Step 2 绑定音频 | 导入 mp3/m4a -> 更新条目 | 非 mp3/m4a 直接报错 |
| Step 2 试听 | 点击“聆听/暂停” -> 切换当前播放条目 | 音频丢失或播放器创建失败会提示错误 |
| Step 3 定位练习 | provider 运行 -> 锚点恢复 -> ready | 失败时关闭沉浸空间并提示重试/回校准 |

## 扩展点与修改热点
- 扩展点：
  - 曲库标签、分组与排序；
  - 练习匹配策略（节奏容差、手别策略）；
  - 多点/自动校准算法。
- 高风险热点：
  - `ARGuideViewModel.runPracticeLocalization`；
  - `SongLibraryViewModel` 的导入与删除事务顺序；
  - `ARTrackingService.start` 的授权与 provider 协调；
  - `ImmersiveView` update 闭包中的 overlay 同步。

## 测试与调试抓手
| 类别 | 位置 | 关注点 |
| --- | --- | --- |
| 定位策略测试 | `PracticeLocalizationPolicyTests.swift` | block/fail/timeout 分支 |
| 曲库存储测试 | `SongLibraryIndexStoreTests.swift`、`SongFileStoreTests.swift` | 索引与文件一致性 |
| 校准存储测试 | `WorldAnchorCalibrationStoreTests.swift` | 读写稳定性 |
| 播放状态测试 | `SongAudioPlayerStateTests.swift` | 聆听状态迁移 |
| 试听按钮状态测试 | `SongLibraryViewModelListeningStateTests.swift` | 聆听/暂停按钮与播放态同步 |
| 解析/步骤测试 | `MusicXMLParserTests.swift`、`PracticeStepBuilderTests.swift` | 练习输入正确性 |

## 示例片段
```swift
switch appModel.resolveRuntimeCalibrationFromTrackedAnchors() {
case .resolved:
    practiceLocalizationState = .ready
    practiceSessionViewModel.startGuidingIfReady()
default:
    break
}
```

```swift
let imported = try fileStore.importMusicXML(from: url)
var nextIndex = updatedIndex
nextIndex.entries.append(entry)
try indexStore.save(nextIndex)
```

## Coverage Gaps
- 目前仍缺 Immersive UI 自动化测试（依赖手工体验验证）。
- 曲库长期运行的自动清理策略尚未内置（可能累积历史文件）。
- `SongLibrarySeeder` 的 seed / backfill 逻辑依赖 bundled `Resources/SeedScores`，缺失资源会直接退化为无种子状态。
