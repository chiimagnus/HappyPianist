shrink 1 行 `model_forward()` 只转发 `model(idxs)`。把默认 hook 设为可直接调用的 lambda/函数，删掉这层命名包装。 [python_backend/aria/aria/eval/linear_probe.py]
shrink 6 处 `dict.keys()` 只为 membership/len/iteration 服务。直接用 dict：`tag in self.tag_to_id`、`len(tag_to_id)`、`for tag in tag_to_id`。 [python_backend/aria/aria/eval/linear_probe.py]
shrink `write_entries()` 三行只包装一个 for/write。用 `writer.write_all(write_objs)` 或内联写入。 [python_backend/aria/aria/eval/linear_probe.py]
delete `ImprovBackendRegistry.register(_:)` 没有调用方，初始化数组已覆盖当前注册需求。无需替代。 [LonelyPianistAVP/Services/Practice/AI/ImprovBackends/ImprovBackendRegistry.swift]
native `ModelContainerFactory.makeStoreURL()` 手写 Application Support 路径拼接。用 `URL.applicationSupportDirectory.appending(path:)`。 [LonelyPianist/Services/Storage/ModelContainerFactory.swift]
shrink `MIDIPlaybackOutputOption.destinationID(uniqueID:)` 只有一个调用方。直接写 `"destination:\($0.id)"`。 [LonelyPianist/Services/Protocols/RoutableMIDIPlaybackServiceProtocol.swift]

net: 可减 -16 行、-0 个依赖
