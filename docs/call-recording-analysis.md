# QQ 9.3.86.617 通话录制通知接口

输入为现有导出运行 [44887720434](https://github.com/zwthys-cyber/ipa-decrypt-lab/actions/runs/44887720434) 的固定摘要加密产物。仅在 GitHub Actions 临时目录解密，没有重新请求 Apple、导出密钥或发布 IPA。主程序 SHA-256 与已有兼容记录一致：`60402733db43cb8b61ea818bd7dd98d2a3d7cf4d84236f3555ee9ab37c4495b0`。

最终静态检查运行：[44890526592](https://github.com/zwthys-cyber/ipa-decrypt-lab/actions/runs/44890526592)。检查解析 Objective-C 元数据，并跟随 ARM64 分支跳板解析方法调用；较早未解析跳板的检查不作为调用关系的最终依据。

## 接口与调用关系

| 方法 | ABI | 静态观察 |
| --- | --- | --- |
| `QQRTCP2PRecordPart -onRecordStart` | `B16@0:8` | 启动本机录制器、更新本机状态后，调用 `notifyPeerRecordState:`，参数为 1 |
| `-notifyPeerRecordEnd` | `v16@0:8` | 调用 `notifyPeerRecordState:`，参数为 8 |
| `-notifyPeerRecordState:` | `v20@0:8i16` | 先调用专用发送方法；状态 1、3、5 随后加入本机 ACK 跟踪 |
| `-sendRecordState:` | `v20@0:8i16` | 格式化状态，取得 `c2cChatEngine`，调用消息种类 8 的发送函数 |
| `-checkRecordAck` | `v16@0:8` | 重发仍调用 `sendRecordState:`；不重新启动录制器 |

只 Hook `-sendRecordState:`（地址 `0x1106a1738`）。开启时跳过所有传入的录制状态，覆盖开始、结束和重发；关闭时按原 ABI 将有符号 32 位参数完整转发一次。本机状态更新、录制开始返回值、通知后的 ACK 跟踪及对方通知接收方法保持原实现。

安装前要求精确 QQ 版本、构建号、可执行文件名及 Objective-C ABI。类尚未加载时允许稍后重试；没有匹配接口时不安装。

## 证据边界

静态调用关系证明了适配依据，合成测试验证拦截和转发逻辑，不等于真实 QQ 通话成功。尚需双端验证一对一语音／视频的录制开始、停止、保存、播放，以及好友端是否还出现提醒。群通话、系统录制提示、外部应用录制不在该接口证据范围内。

诊断仅记录开关、Hook 状态与调用计数，不记录通话内容、参与者、文件或原始状态参数。
