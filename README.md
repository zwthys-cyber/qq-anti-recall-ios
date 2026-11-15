# QQ Anti Recall iOS

针对 **QQ 9.3.86 / 构建 9.3.86.617** 的 iOS 注入动态库。当前版本 **0.3.0-experimental**，目标设备为 iPhone 17 Pro Max / iOS 27.0.1。

## 0.3.0 修正

用户的 0.2.0 真机日志显示：收到消息后，QQ 先写入正数 recallTime 并调用 SWI 的 onMsgInfoListUpdate:，约 1 ms 后才调用 onMsgRecall:peerUid:seq:。0.2.0 原样放行了前面的更新，所以即使拦截了后面 5 次撤回通知，消息仍会消失。

0.3.0 在调用 QQ 原始列表更新方法之前逐条检查记录：只过滤类型及 getter ABI 均已核对的 OCMsgRecord，且要求 recallTime > 0。整批都是撤回项时不调用原更新方法；混合批次只移除撤回项，保留普通项的顺序和对象身份。真实空列表、未知载荷、未知记录类型、类型不匹配或读取失败均保留原行为。关闭插件时原参数直接透传。

不重写撤回时间，不拦截普通用户删除，不读取正文，也不修改输入记录。原有撤回通知拦截继续保留，防止更新之后的通知再次删除可见消息。

**本次针对已抓到的“先更新、后通知”路径修正。自动回归测试不等于目标手机验证；真实 QQ 的修正效果仍需安装新版确认。**

## 下载和安装

1. 打开 [Actions](https://github.com/zwthys-cyber/qq-anti-recall-ios/actions)，选择包含本次源码且成功的 Build and test。
2. 下载 **QQAntiRecall-0.3.0-9.3.86.617-arm64**。解压后核对 build-info.json 的 plugin_version 为 0.3.0-experimental。
3. 用新的 QQAntiRecall.dylib 替换旧插件，注入对应 QQ 解密 IPA，然后用自己的有效签名重签名安装。不要叠加注入旧版。注入工具须写入动态库加载项。
4. 面板确认插件版本 0.3.0-experimental，并开启防撤回。全部原有接口匹配时仍为 11 个 Hook；这次修改已有更新 Hook 的行为，不靠增加 Hook 数量实现修正。

构建产物的 ad-hoc 签名不能直接用于未越狱手机安装，重签名工具需要连同 QQ 重新签名。插件不依赖越狱框架。

## 验证

所有编译和自动测试都由 GitHub Actions 完成。新增回归用例先复现 0.2.0：消息已显示 → 原样执行带撤回标记的更新 → 拦截后续通知，结果消息仍丢失；再通过真实的插件 Hook 执行同样顺序，验证显示层原对象及内容保留。

还覆盖混合批次中的正常编辑、记录顺序和身份、输入不被修改、普通用户删除、禁用透传、零值/负值/64 位边界、未知类型、子类 ABI 不匹配、getter 异常、并发计数及诊断不含正文。保留已有 Mach-O、Hook、新旧适配器及 iOS 架构/平台/签名验证。

这些测试使用模拟 QQ 类及显示模型，没有在 runner 上登录真正的 QQ。手机验证应使用安装后的新消息：另一账号发送 → 本机收到 → 另一账号撤回，观察气泡是否保留；随后分别验证退出聊天再进入、重启、群聊、图片和后台场景。

## 诊断

点击「清零并开始测试」可以隔离一次新测试，然后「导出诊断」。0.3.0 的 update_filter 中：

- recall_update_filter_ready：OCMsgRecord 的撤回时间 getter 是否符合预期 ABI。
- filtered_recall_update_items：实际从列表更新中移除的撤回项数量，可能包含同一消息的重复分发。
- dropped_recall_only_batches：整批撤回更新被阻断的次数。
- forwarded_mixed_update_batches：过滤后仍向 QQ 传递普通更新的批次数。
- unrecognized_update_payloads / unrecognized_update_items / record_abi_rejections / record_read_failures：未识别或未能安全读取时的透传计数。

incoming_suppressed_calls.swi_list_update 只统计整批被阻断的回调；混合批次由 update_filter 记录。hook_results 中 0 是安装成功，实际调用次数在 incoming_hook_calls。11 个 Hook 或 intercepted_events > 0 都不能单独证明消息被保留。

trace_samples 最多 24 条，每种固定事件名最多 2 条、每条最多 12 个 QQ 镜像内偏移。诊断不包含消息参数、正文、账号、路径或原始内存地址。

## 范围与数据

本次保护的是已收到消息的更新通知路径，没有修改 QQ 原生数据库，也没有独立消息备份库。无法恢复本机未收到或安装前已撤回的内容；离线同步、退出会话或重启后的持久保留未获验证。runtime_qq_verified 仍为 false，避免将模拟测试当作真机成功。

输入为用户指定的 [原始导出](https://github.com/zwthys-cyber/ipa-decrypt-lab/actions/runs/43715591869)。[初始二进制检查](https://github.com/zwthys-cyber/ipa-decrypt-lab/actions/runs/43718304175) 与 [扩展元数据检查](https://github.com/zwthys-cyber/ipa-decrypt-lab/actions/runs/43721273602) 绑定同一 QQ 主程序 SHA-256；方法编码、输入哈希和旧版失败记录见 [兼容性证据](Compatibility/qq-9.3.86.617.json)。

元数据读取器依据 Apple [objc4](https://github.com/apple-oss-distributions/objc4/blob/main/runtime/objc-runtime-new.h) 和 [dyld](https://github.com/apple-oss-distributions/dyld/blob/main/include/mach-o/fixup-chains.h)。[QQNoRecall](https://github.com/Qaz9190/QQNoRecall) 仅作调查线索，实现独立编写。

插件不上传数据、不读取或另行保存消息正文。IPA、交付密钥及签名证书不进入此仓库或公开产物。当前服务器不执行 Git、项目脚本、编译或测试命令。
