# Piano Highlight Regression Checklist (AVP 2D/3D)

Scope: `LonelyPianistAVP` 的练习引导（practice guide）键盘高亮，要求 2D（`PianoKeyboard88View`）与 3D（RealityKit decals）行为一致。

## Truth Source (Must Not Drift)

- Shared style: `PianoGuideHighlightStyle.resolve(hand:phase:keyKind:)`
- Shared highlight token: `PianoGuideKeyHighlightResolver.resolveHighlights(guide:)`

Current constants (lock via unit tests):
- White keys: triggered `0.75`; active right `0.48`; active left `0.55`
- Black keys: triggered `0.95`; active right `0.95`; active left `0.92`
- Tint tokens:
  - Right hand white: `.yellow`
  - Right hand black: `.orange`
  - Left hand: `.cyan`

## Automated Verification

- Run: `rtk xcodebuild build -scheme LonelyPianistAVP`
- Run: `rtk xcodebuild test -scheme LonelyPianistAVP -destination 'id=86364D5F-BCCF-48C5-AF79-8154E5689FA3'`

Sanity (manual grep):
- Run: `rtk rg -n "PianoGuideHighlightStyle\\.resolve\\(" LonelyPianistAVP | head -n 80`
- Expected: 2D（`PracticeStepView` / `PianoKeyboard88View`）与 3D（`PianoGuideOverlayController`）都在使用共享样式。

## Manual Visual Checks (2D vs 3D Must Match)

Preconditions:
- 进入任意带有左右手音符的练习曲目（同一小节内最好同时有白键与黑键）。
- 打开 immersive（3D）同时保持 2D 键盘可见（practice step UI）。

Checklist:
1) Same MIDI notes highlighted
   - 2D 与 3D 同一时刻高亮的键集合一致（包含 step advance 的瞬间）。
2) Tint mapping
   - 右手：白键黄、黑键橙；左手：青色（白/黑都为 cyan）。
3) Triggered vs Active intensity (white keys)
   - 同一键在 triggered（瞬时）与 active（持续）两种 phase 下，2D 与 3D 的明暗变化方向一致。
   - White: triggered 明显更亮；active 左手比 active 右手略亮。
4) Triggered vs Active intensity (black keys)
   - Black: triggered 与 active 右手强度相同；active 左手略暗于右手。
5) Step advance transitions
   - 手动下一步（manual advance）多次快速点击，确认不会出现 2D/3D 高亮错位（例如 2D 已进入下一步但 3D 仍停留上一组键）。
6) Autoplay on/off
   - 打开与关闭 autoplay 各复验一次 1)~5)。

## Known Non-goals (Do Not Misinterpret)

- 3D decal 仍可能有“软边”观感（来自 `KeyDecalSoftRect` 纹理的 alpha 分布）；本清单关注的是：同一键的颜色语义与强度（opacity）是否一致。

