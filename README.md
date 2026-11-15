# QQ Anti Recall iOS

针对 **QQ 9.3.86 / 构建 9.3.86.617** 的 iOS 注入动态库，目标设备为 iPhone 17 Pro Max / iOS 27.0.1。当前版本 **0.2.0-experimental**。

**0.1.0 已由用户实测确认：插件加载、3 个 Hook 安装成功，但单聊撤回后消息仍直接消失。0.2.0 新增入口与诊断，消息保留效果仍待真机复测，不能把编译成功或回调次数视为防撤回成功。**

## 安装与复测

1. 从本仓库 [Actions](https://github.com/zwthys-cyber/qq-anti-recall-ios/actions) 成功的 **Build and test** 运行中下载 `QQAntiRecall-9.3.86.617-arm64-experimental`。
2. 用本次 `QQAntiRecall.dylib` **替换旧版插件**，注入对应 QQ 解密 IPA，再用自己的签名重新安装。不要同时注入两份插件；注入工具必须写入动态库加载项。
3. 打开蓝色「防撤回」面板，核对插件版本 **0.2.0-experimental**。全部接口匹配时共 **11 个 Hook**，其中包括只观察并透传的接口，因此数量不等于拦截成功。
4. 确认已开启，点击「清零并开始测试」。让另一账号发送一条新的单聊文本，确认本机收到后再撤回。记录原消息是否仍显示、退出聊天再进入后是否仍显示，然后导出诊断。
5. 后续分别检查群聊、图片、后台/离线和重启后的情况；关闭插件时应恢复正常撤回行为。

ad-hoc 构建签名不能直接安装到未越狱手机，需要连同宿主 QQ 重新签名。插件不依赖越狱框架。

## 0.2.0 改动

- 新增 Swift `SWIKernelMsgListener` 的撤回回调，以及 `QQMessageRecallNetEngine` / `QQMessageRecallPackageHandler` 的单聊撤回解析入口；开启时阻断这些特定入口，关闭时按原 ABI 透传。
- 保留原 KTI 与 FloatEar 撤回回调；撤回时间和 Codec 写入改为观察后原样透传，不再把时间清零冒充消息保留。
- Swift 普通收消息、列表更新及通用删除只计数并透传；没有按名称批量拦截所有删除方法。
- 新增清零、分入口调用/阻断次数、Hook 是否被后来替换的检查，以及有上限的 QQ 调用位置记录。

每个入口要求匹配真实 IPA 的方法编码；不匹配的入口不安装，并在诊断中记录原因。仅支持上述准确版本/构建和 QQ 可执行文件。原 3 个接口共用预检，新入口独立检查与重试。

## 如何读诊断

`hook_results` 的 **0 表示安装成功，不是调用次数**。1/2/3/4 分别表示缺类、缺方法、ABI 不匹配和参数无效。实际命中看 `incoming_hook_calls`，被阻断的特定撤回入口看 `incoming_suppressed_calls`。`incoming_hook_still_active` 检查 Objective-C 方法表中的替换是否仍存在，不能证明 Swift/C++ 所有调用都会经过方法表。

`positive_recall_time_writes` 仅表示观察到正数时间写入；`prevented_recall_flag_writes` 在 0.2.0 恒为 0。`intercepted_events` 是被阻断的回调总数，同一消息可能对应多个回调。`runtime_qq_verified: false` 保留消息保留效果尚未验证的状态。

`trace_samples` 最多 24 条，每类事件最多 2 条，每条最多 12 个 QQ 镜像内偏移；点击清零会删除旧样本。只包含固定事件名、相对时间和代码位置，不包含消息参数、正文、账号、路径或原始内存地址。

## 验证与限制

GitHub Actions 执行 Mach-O 格式/分类扩展合成测试、Objective-C ABI 与继承隔离测试、新旧适配器测试，以及 iOS arm64 编译、架构/平台/签名检查。新测试覆盖类方法 Hook、指针与整数宽度、关闭透传、普通接收/更新/删除透传、并发诊断清零与隐私边界。

这些测试使用模拟类，没有登录真实 QQ，也不能复现你手机上的消息链路。QQ 内核数据库、离线同步、Swift 直接调用或其他路径仍可能绕过这些入口。没有独立消息备份库，不能恢复安装前已经撤回或本机未收到的消息；跨会话/重启保留尚未验证。

## 静态证据与数据

输入来自用户指定的 [原始导出](https://github.com/zwthys-cyber/ipa-decrypt-lab/actions/runs/43715591869)。初始 [macOS 检查](https://github.com/zwthys-cyber/ipa-decrypt-lab/actions/runs/43718304175) 验证二进制；扩展的 [Linux 元数据检查](https://github.com/zwthys-cyber/ipa-decrypt-lab/actions/runs/43721273602) 绑定同一 QQ 主程序完整 SHA-256，并扫描全局撤回选择子及分类扩展。结果共 1224 条筛选后接口，未从分类扩展中找到新增匹配项。

具体入口、类型编码、哈希与 0.1.0 实测失败记录见 [兼容性证据](Compatibility/qq-9.3.86.617.json)。这些是接口存在的证据，不是完整调用链的运行证明。

元数据读取器依据 Apple [objc4](https://github.com/apple-oss-distributions/objc4/blob/main/runtime/objc-runtime-new.h) 和 [dyld](https://github.com/apple-oss-distributions/dyld/blob/main/include/mach-o/fixup-chains.h)。[QQNoRecall](https://github.com/Qaz9190/QQNoRecall) 仅作调查线索，实现独立编写。

插件不上传数据、不读取消息正文。IPA、交付密钥及签名证书不进入本仓库或公开产物。所有编译、测试与二进制检查只在 GitHub Actions 执行；当前服务器不运行 Git、项目脚本或构建命令。
