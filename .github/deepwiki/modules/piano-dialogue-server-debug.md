# Python Debug Artifacts

## 范围
这页讲调试包和 WS 冒烟测试。

## 产物
| 产物 | 说明 |
| --- | --- |
| `requests/<req_id>/request.json` | 原始请求 |
| `requests/<req_id>/response.json` | 原始响应 |
| `requests/<req_id>/summary.json` | 延迟和统计摘要 |
| `requests/<req_id>/prompt.mid` | prompt MIDI |
| `requests/<req_id>/reply.mid` | reply MIDI |
| `index.jsonl` | 请求索引 |

## 触发条件
- `DIALOGUE_DEBUG=1` 时写盘。
- 写盘失败不会中断主请求。

## 参考脚本
- `server/test_client.py` 会把结果写成 `out/server_reply.mid`。
- `scripts/test_generate.py` / `scripts/test_infilling.py` 可离线生成验证。


## Coverage Gaps
- 调试包没有统一 schema 文档，仍以代码字段为准。

