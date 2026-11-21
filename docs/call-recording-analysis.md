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

只 Hook `-sendRecordState:`（地址 `0x1106a1738`）。0.9.1 开启时只跳过本机开始／结束状态（1、3、8），包括它们的重发；保留中止对方录制指令（5）、确认和未知状态；关闭时按原 ABI 将有符号 32 位参数完整转发一次。本机状态更新、录制开始返回值、通知后的 ACK 跟踪及对方通知接收方法保持原实现。

安装前要求精确 QQ 版本、构建号、可执行文件名及 Objective-C ABI。类尚未加载时允许稍后重试；没有匹配接口时不安装。

## 证据边界

静态调用关系证明了适配依据，合成测试验证拦截和转发逻辑，不等于真实 QQ 通话成功。尚需双端验证一对一语音／视频的录制开始、停止、保存、播放，以及好友端是否还出现提醒。群通话、系统录制提示、外部应用录制不在该接口证据范围内。

诊断仅记录开关、Hook 状态与调用计数，不记录通话内容、参与者、文件或原始状态参数。

## 接收端界面与中止控制（0.9.1 补充）

进一步检查运行：[44891268449](https://github.com/zwthys-cyber/ipa-decrypt-lab/actions/runs/44891268449)，复用同一份固定摘要 IPA。结果为静态元数据、ARM64 反汇编与编译期字符串，不是实际运行截图。

### 对方会看到什么

接收状态 1 时，`QQRTCP2PRecordPart -handlePeerRecord:` 的跳转表进入 `0x1106a0e80`，设置对方录制状态为 4，并在前台调用 `playPeerRecordAudio`，随后调用 `recordPart onPeerRecordBarShow:YES`；后台场景设置待提示标志。

`QQRTCShowPanelRecordPart -onPeerRecordBarShow:`（`0x1106c9314`）更新视图模型的 `isPeerVideoRecording`，创建并显示 `peerRecordBar`。创建方法 `-initPeerRecordBarIfNeeded`（`0x1106c741c`）对这个栏设置 style=0，并将 delegate 设为当前面板。

`QQAVRecordBar -initWithFrame:`（`0x1105a8fbc`）设置“对方正在录制视频”文字；`-setStyle:`（`0x1105a93d0`）在 style=0 分支创建停止按钮，将点击事件绑定到 `onCancelBtn`。style=1 为另一种紧凑显示，使用红点与“对方正在录制”文字；具体布局随面板状态而变。

因此原版 QQ 的接收端存在录制提示、语音提示以及可中止录制的 UI 控件，并非只有消息文字。

### 中止按钮的完整路径

1. `QQAVRecordBar -onCancelBtn`（`0x1105aa0bc`）转发给 delegate。
2. `QQRTCShowPanelRecordPart -onCancelBtn`（`0x1106c9720`）设置 peerState=8，调用 `p2pRecordPart notifyPeerRecordState:5`，隐藏对方录制栏并显示“你中止了对方录制，录制内容将不会被存储。”。
3. 录制方的 `handlePeerRecord:` 收到状态 5，跳转表进入 `0x1106a0c30`，发出 6／7 确认，并调用 `onRecordStopReason:2`。
4. 停止流程进入本机录制器停止和 UI 收尾；相应完成块含“对方中止了你的录制”提示。

提示文案表达 QQ 的预期行为；没有通过真实录制文件验证其“不会被存储”效果。

### 状态边界与修复

| 状态 | 静态用途 | 0.9.1 开启后的处理 |
| --- | --- | --- |
| 1 | 本机开始录制；接收方显示录制栏 | 屏蔽及阻止重发 |
| 3 | 本机结束流程 | 屏蔽及阻止重发 |
| 8 | 本机取消／结束路径，包含延迟发送 | 屏蔽及阻止重发 |
| 5 | 请求中止对方录制 | 原样转发 |
| 2、4、6、7、9 | 状态确认 | 原样转发 |
| 其他值 | 未证实含义 | 原样转发 |

0.9.0 在发送方法上屏蔽所有状态，范围过宽，可能破坏使用者中止对方录制及确认消息。0.9.1 改为精确屏蔽 1／3／8；原有接收端中止处理保持不变。

**关于隐藏的结论：** 在已追踪的这条接收路径中，录制栏由收到开始状态 1 触发；录制前开启插件可阻止本机发送这个触发条件。因此预期不会通过该路径弹出状态栏及其按钮。这是静态因果推断，不是所有 QQ 平台和后台恢复路径都已完成实机验证。已经发送的开始状态或对方已显示的状态栏不能靠后续拦截撤回。

## 本机录制完成提示音（0.9.2 补充）

静态检查运行：[44893558085](https://github.com/zwthys-cyber/ipa-decrypt-lab/actions/runs/44893558085)。复用同一份加密包，重新核对下列元数据和有界 ARM64 调用关系。

| 接口／常量 | 已核对依据 |
| --- | --- |
| `QQRTCP2PRecordPart -recordAVTinyVideoFinished:RecordStopResult:` | ABI `v32@0:8Q16Q24`，IMP `0x1106a2cbc`；完成处理内调用音效辅助函数，再安排后续异步 UI／保存结果处理 |
| 音效辅助函数 `0x1106a30b4` | 将字符串 `recordDing` 置于参数 x2，循环数 w3=0，调用 `playAudio:andLoopTime:` |
| `AVRingPlayer -playAudio:andLoopTime:` | ABI `v28@0:8@16i24`，IMP `0x1104f7094`；原方法转发至带音量参数的播放接口 |

`recordDing` 也出现在对方录制提示等路径中，不能只凭资源名全局静音。本版用线程局部的嵌套计数限定原始完成回调执行期间；开关开启、资源名精确匹配 `recordDing` 且循环数为 0 时才跳过这次播放。计数在 `@finally` 中恢复，原始完成回调、保存与 UI 工作仍完整执行，异常保持原样抛出。

播放和完成两个方法均通过精确 ABI 预检后才安装，任一不匹配时保留原实现。开关关闭、其他资源、其他循环数、非字符串参数、回调外和其他线程的音效请求均原样转发。没有修改音频会话、系统音量、通话媒体或录像文件。

`call_recording.completion_tone_hook_active` 表示这两个 Hook 均仍生效；`completion_tones_muted` 只记录被跳过的匹配播放次数。两项不代表真机声音验证，也不记录通话内容或请求资源参数。需在目标设备确认停止录制无提示音且仍能正常保存／播放录制文件。
