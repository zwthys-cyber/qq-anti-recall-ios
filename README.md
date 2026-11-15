# QQ Anti Recall iOS

针对 **QQ 9.3.86 / 构建 9.3.86.617** 的注入动态库，当前版本 **0.4.0-experimental**。目标设备为 iPhone 17 Pro Max / iOS 27.0.1。

## 本版变化

用户已确认 0.3.0 能保留当前单聊页面的消息，但返回主页再进入时，QQ 会从原生存储加载撤回提示。0.4.0 保留原有更新过滤，并在收到正常消息时保存独立副本；历史查询返回带撤回标记的同一消息时，用本机副本重建消息对象。没有修改 QQ 数据库。

成功保留的消息下方增加浅蓝色圆角标识 **「已撤回 · 已保留」**，带回转箭头图标，支持深浅色模式和辅助功能。标识占用独立行高，复用消息行时清除旧标识。原消息未恢复、账号不匹配或没有安全排版空间时不显示“已保留”。

所有入口要求精确 QQ 版本及 Objective-C 方法签名。消息关联使用当前账号、会话类型、对方标识、频道/群标识和消息 ID；只有同会话序列号唯一匹配时才允许回退。无法确认的记录保持 QQ 原行为。

## 下载和安装

1. 打开 [Actions](https://github.com/zwthys-cyber/qq-anti-recall-ios/actions)，选择本版最新成功的 **Build and test**。
2. 下载 **QQAntiRecall-0.4.0-9.3.86.617-arm64**。内含动态库、构建信息、SHA-256、模拟器测试结果及深浅色标识示意图。
3. 用新版 QQAntiRecall.dylib 替换旧插件，注入对应解密 QQ IPA，连同 QQ 一起重签名安装。不要叠加旧版插件。
4. 面板确认版本 **0.4.0-experimental** 并开启防撤回。全部匹配时为 25 个 Hook；数量本身不代表真机保留成功。

动态库附带 ad-hoc 签名，安装未越狱设备时仍需有效的重签名。插件不依赖越狱框架。

## 本机消息副本

开启后会读取并保存消息内容及渲染元数据，保存在 QQ 沙盒 Application Support/QQAntiRecall/Snapshots-v1，按账号隔离。每个账号最多 512 条、16 MB，有上限的单条副本最多 256 KB；超限淘汰最旧记录。文件使用 iOS 文件保护，排除系统备份，目录/文件权限为 0700/0600。账号和会话索引散列化，消息副本本身不是额外密码加密的保险箱。

插件不上传数据。诊断 JSON 只包含计数、接口状态及受限调用栈偏移，不包含正文、账号、会话标识或消息副本。records_message_contents 在本版准确标为 true，diagnostics_include_message_contents 和 uploads_message_contents 为 false。

面板可关闭后续保留、清零诊断或清除当前账号备份；关闭功能不会自动删除已有副本。普通删除通知会清除对应备份，避免再次恢复。旧版从未保存的内容、本机未收到的内容无法补回。

保存的是已核对模型类的完整字段图，未知对象类型会导致该条副本失败，不能把部分内容冒充完整恢复。附件只保存消息元数据，不额外复制图片/语音/视频文件；附件资源已被 QQ 清理时不保证仍能打开。历史查询没有返回可匹配记录时不会凭空插入消息。

## 云端验证与真机边界

编译、二进制检查、自动测试和签名验证均在 GitHub Actions；当前服务器不执行 Git、项目脚本、构建或测试命令。

回归测试包括：

- 0.2.0 的“更新先于撤回通知”丢消息复现，以及 0.3.0 的混合批次保护。
- 两个独立进程写入/读取，验证磁盘恢复及标识状态持久化；深拷贝、账号/会话隔离、退出账号、缺失副本和普通删除。
- 真实 Hook 入口的首屏/历史查询参数转发，包括错误码、BOOL、64 位状态和无符号查询 ID；不匹配版本与 ABI 拒绝。
- 有限模型解码、未知类型/截断存档拒绝、原始整数宽度、权限与诊断不含正文。
- UIKit 模拟器中的消息下方排版、普通行、复用、从磁盘重载、深浅色渲染、关闭功能与切换账号。
- arm64 iOS 动态库的架构、平台、签名及无越狱框架依赖检查。

界面测试使用稳定的 iOS 18.5 模拟器、自建消息类和合成文本，未登录或运行真实 QQ；iOS 27 云端模拟器曾在启动/安装阶段超时，不计为通过。runtime_qq_verified 保持 false；**0.4.0 在你的 QQ 上的重进聊天恢复及标识效果，尚未获得真机验证。**

安装后应以新收到的消息测试：对方发送 → 本机收到 → 对方撤回 → 原文及标识仍在 → 返回主页再进入 → 结束进程后重新进入。不要使用 0.3.0 已经丢失且从未保存的消息判断新版是否有效。

## 诊断字段

- update_filter：撤回更新过滤数量及读取异常。
- message_store.snapshots_saved / history_records_restored：本次实际写盘及恢复次数，可能包括重复查询。
- message_store.snapshot_encode_failures / snapshot_decode_failures / snapshot_misses / disk_failures：副本缺失或失败原因计数。
- message_store.account_context_available：是否取得经过签名检查的当前账号上下文。
- history_hook_calls / history_hook_still_active：历史回调是否实际触发及 Hook 是否仍有效。
- recall_badge：标识接口状态、创建数及行高刷新数。没有空间时隐藏标识，避免遮挡正文。
- hook_results 中 0 表示安装成功；不是事件次数。

## 接口证据

[原始导出](https://github.com/zwthys-cyber/ipa-decrypt-lab/actions/runs/43715591869)、[主程序检查](https://github.com/zwthys-cyber/ipa-decrypt-lab/actions/runs/43718304175)、[模型/历史接口检查](https://github.com/zwthys-cyber/ipa-decrypt-lab/actions/runs/43763487317) 和 [消息视图检查](https://github.com/zwthys-cyber/ipa-decrypt-lab/actions/runs/43765017161) 绑定同一主程序 SHA-256。方法编码、输入哈希和历次用户反馈见 [兼容性证据](Compatibility/qq-9.3.86.617.json)。

元数据读取器依据 Apple [objc4](https://github.com/apple-oss-distributions/objc4/blob/main/runtime/objc-runtime-new.h) 和 [dyld](https://github.com/apple-oss-distributions/dyld/blob/main/include/mach-o/fixup-chains.h)。仓库与公开产物不包含第三方 IPA、交付密钥、签名证书或真实聊天内容。
