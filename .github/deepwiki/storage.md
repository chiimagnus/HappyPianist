# 存储

## 存储拓扑

| 存储层 | 位置 | 数据类型 | 读写方 |
| --- | --- | --- | --- |
| SwiftData `MappingProfileEntity` | `Models/Storage/MappingProfileEntity.swift` | Profile 元数据 + payloadData | `SwiftDataMappingProfileRepository` |
| SwiftData `RecordingTakeEntity` | `Models/Storage/RecordingTakeEntity.swift` | Take 元数据与时长 | `SwiftDataRecordingTakeRepository` |
| SwiftData `RecordedNoteEntity` | `Models/Storage/RecordedNoteEntity.swift` | 单音符事件 | `SwiftDataRecordingTakeRepository` |
| UserDefaults | `AppIconDisplayMode` | 图标显示模式 | `AppIconDisplayViewModel` |

## 数据结构矩阵

| 结构 | 关键字段 | 约束 | 备注 |
| --- | --- | --- | --- |
| `MappingProfileEntity` | `id`, `name`, `isActive`, `payloadData` | `id` unique | payload 使用 JSON 编码外部存储 |
| `RecordingTakeEntity` | `id`, `name`, `durationSec`, `notes` | `id` unique | notes 级联删除 |
| `RecordedNoteEntity` | `note`, `velocity`, `startOffsetSec`, `durationSec` | `id` unique | 关联到 take |

## 读写流程

1. 启动时 `ensureSeedProfilesIfNeeded()` 保证默认 profile 存在。
2. 编辑 profile 时 `saveProfile()` 更新实体并保存。
3. 录制 stop 时生成 `RecordingTake` 并 `saveTake()`。
4. take 重命名/删除后立即刷新列表与选中态。

## 排序与选择策略

| 数据 | 排序规则 | 选择策略 |
| --- | --- | --- |
| Profiles | active 优先，其次 `updatedAt` 降序 | `activeProfileID` 优先，缺失回退首项 |
| Takes | `updatedAt` 降序，再 `createdAt` 降序 | 保留旧选中，失效时选首项 |
| Notes | `startOffsetSec` 升序，再 note 升序 | 回放事件按时间重建 |

## 一致性与错误处理

- Profile 删除后若删的是 active，仓储自动激活最近更新的 profile。
- 保存 take 时会先清理旧 note entity 再重建，避免残留脏数据。
- 仓储错误透传给 ViewModel 并写入状态消息。

## 迁移与演进注意事项

- `payloadData` 是 JSON 编码 blob，字段变更需保证解码兼容。
- SwiftData schema 增改字段时需规划迁移策略（仓库当前未显式提供）。

## 示例片段

```swift
// SwiftDataMappingProfileRepository.swift
if let existing = try fetchEntity(id: profile.id) {
    existing.payloadData = try encoder.encode(profile.payload)
} else {
    context.insert(try makeEntity(from: profile))
}
```

```swift
// SwiftDataRecordingTakeRepository.swift
for noteEntity in existing.notes {
    context.delete(noteEntity)
}
existing.notes.removeAll(keepingCapacity: false)
```

## Coverage Gaps（如有）

- 缺少版本化迁移文档与回滚策略。

## 来源引用（Source References）

- `PianoKey/Models/Storage/MappingProfileEntity.swift`
- `PianoKey/Models/Storage/RecordingTakeEntity.swift`
- `PianoKey/Models/Storage/RecordedNoteEntity.swift`
- `PianoKey/Services/Storage/SwiftDataMappingProfileRepository.swift`
- `PianoKey/Services/Storage/SwiftDataRecordingTakeRepository.swift`
- `PianoKey/Models/Mapping/MappingProfile.swift`
- `PianoKey/Models/Recording/RecordingTake.swift`
- `Packages/MenuBarDockKit/Sources/MenuBarDockKit/AppIconDisplayMode.swift`
