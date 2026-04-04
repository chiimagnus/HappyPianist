# LonelyPianist

用 MIDI 键盘控制 Mac 输入的菜单栏应用。单个音符映射文本，和弦触发组合键，旋律触发快捷指令，力度区分输出，多套 Profile 随时切换。

## 快速上手

1. 启动 LonelyPianist → 菜单栏打开面板
2. 点击 `Grant Accessibility Permission` 授予辅助功能权限（首次必做）
3. 点击 `Start Listening` 开始监听 MIDI
4. 点击 `Open LonelyPianist` 打开主窗口，在 `Mappings` 页面设置映射规则并弹琴验证

> ⚠️ 必须授予 **辅助功能权限** 才能跨应用注入按键。路径：`系统设置 > 隐私与安全性 > 辅助功能` → 勾选 LonelyPianist。

## 没有实体琴？

用 [MidiKeys](https://github.com/flit/MidiKeys)（开源免费）当虚拟键盘。打开后在 LonelyPianist 点 `Refresh MIDI Sources` 即可识别。

> 不要用库乐队测试——它的 MIDI 事件不会广播给外部应用。
