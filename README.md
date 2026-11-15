# QQ Anti Recall iOS

针对 **QQ 9.3.86 / 构建 9.3.86.617** 的实验性 iOS 防撤回动态库，供解密 QQ 注入后重签名安装。目标设备为 iPhone 17 Pro Max / iOS 27.0.1。

**当前属于实验适配。真实 QQ 登录、消息保留和 iOS 27.0.1 真机运行尚未验证。** 编译或合成测试通过不能替代这些验证。

## 下载与安装

1. 打开本仓库 [Actions](https://github.com/zwthys-cyber/qq-anti-recall-ios/actions)，选择成功的 **Build and test** 运行。
2. 下载 `QQAntiRecall-9.3.86.617-arm64-experimental` 产物并解压。
3. 在支持 dylib 注入的 IPA 重签名工具中，选择你的 **QQ 9.3.86.617 解密 IPA**，加入 `QQAntiRecall.dylib`，再使用自己的有效签名安装。工具需同时写入动态库加载项；仅把 dylib 拷入 IPA 不会加载。
4. 启动 QQ 后等待约 3 秒，点击可拖动的蓝色「防撤回」按钮。正常匹配应显示 **已加载接口：3**；可随时关闭拦截或导出诊断。

产物上的 ad-hoc 签名只供构建校验，不能单独用于未越狱 iPhone 安装；重签名工具需要连同宿主 QQ 重新签名。插件不依赖 MobileSubstrate、Theos 或越狱目录。

## 实现范围

从用户指定的真实 IPA 提取并验证以下接口的存在和 ABI：

- `KTIKernelMsgListener -onMsgRecall:peerUid:seq:`
- `_TtC9NTAIOChat20NTAIOFloatEarManager -onRecvRecallMsg:`
- `OCMsgRecord -setRecallTime:`

开启时拦截前两个撤回通知，并把后者收到的正数撤回时间改为 0；关闭时按原类型、原参数调用 QQ 原方法。不会拦截普通消息列表更新、通用删除方法或主动发起撤回的方法。版本/构建/宿主可执行文件不匹配时不初始化；三个接口须全部通过签名检查才安装。

这是一种基于静态接口证据的实验实现，不是完整撤回调用链的运行证明。QQ 内核数据库、离线同步或其他路径仍可能撤回消息；本插件没有独立消息备份库，无法恢复安装前已撤回或本机未收到的内容。跨会话/重启持久保留和所有消息类型均未验证。

## 验证

GitHub Actions 执行：

- Mach-O 大方法、相对方法和 chained pointers 的合成布局测试。
- Objective-C Hook ABI 拒绝、继承隔离、关闭透传测试。
- 适配器版本门禁、完整参数宽度、并发计数和诊断隐私测试。
- iOS arm64 动态库编译、架构/平台/签名检查，输出哈希和源码提交标识。

上述测试在模拟类上执行；并未启动真实 QQ。`build-info.json` 明确保留真实 QQ 和 iOS 27.0.1 运行未验证标记。

真机验证待办：单聊/群聊文本、图片；前台/后台/离线撤回；关闭插件正常撤回；退出聊天再进入、重启 QQ 后是否仍保留。若需验证也完全由 Actions 调度，需要另行提供可连接目标手机的测试环境；普通 GitHub 托管 runner 不含这台手机。

## 来源与数据

原导出：[43715591869](https://github.com/zwthys-cyber/ipa-decrypt-lab/actions/runs/43715591869)。
有效静态接口检查：[43718304175](https://github.com/zwthys-cyber/ipa-decrypt-lab/actions/runs/43718304175)。
输入哈希、方法编码与检查来源见 [兼容性证据](Compatibility/qq-9.3.86.617.json)。

新版本的主逻辑在 QQ 主可执行文件中；旧教程中 QQMessageRecallModule 的 recvC2C/recvGroup 方法不在这份接口清单中，未照搬旧版 Hook。参考项目 [QQNoRecall](https://github.com/Qaz9190/QQNoRecall) 仅用于调查线索，本仓库实现独立编写。元数据读取器依据 Apple [objc4](https://github.com/apple-oss-distributions/objc4/blob/main/runtime/objc-runtime-new.h) 和 [dyld](https://github.com/apple-oss-distributions/dyld/blob/main/include/mach-o/fixup-chains.h) 格式。

插件不上传数据、不读取消息正文；诊断只包含版本、接口匹配结果和计数。QQ IPA、交付密钥和签名证书不进入本仓库或公开产物。所有编译、测试及二进制检查只在 Actions 执行；当前服务器不运行 Git、项目脚本或构建命令。
