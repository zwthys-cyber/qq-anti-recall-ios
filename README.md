# QQ Anti Recall iOS

针对 QQ **9.3.86 / 9.3.86.617**，版本 **0.7.1-experimental**。

0.5.0 用户已确认防撤回成功：编码失败 0、保存 27 次、历史恢复 10 次，未发生字段省略。11 个运行时模型成功编码；重复历史查询的缺失计数不代表新消息全部失败。用户仍未看到标识，头像有调用但 AIOCell 的四个接口调用全为 0，列表行高代理未安装。

插件入口移入 QQ 设置页底部，保留 QQ 原有页脚，聊天页面不显示悬浮按钮。

0.6.0 增加头像视图挂到窗口/父视图后的延迟刷新，覆盖先绑定消息、后挂入真实聊天列表的路径；测试改用另一种消息行，不依赖旧 AIOCell 的方法命中。标识为浅蓝色圆角“已撤回 · 已保留”，支持深浅色和单元格复用。

新增**聊天消息内重复查看闪照**：在 **QQ 设置 → 防撤回与闪照 · 插件设置** 开启独立的“闪照保留”开关（默认关闭）。正常打开新闪照后，对应消息下方出现“闪照 · 再次查看”，从聊天页面直接打开这一张已保存图片。菜单不提供相册查看入口。不处理已经销毁且从未取得图片的闪照。真实 QQ 的消息路径关联及入口显示仍需实机验证。

闪照从已核对的 PhotoBrowserFlashPictureService +decryptImageWithImagePath: 返回结果取得，只接受图片、图片数据或沙盒内的图片文件路径。与 QQ 原资源分开保存，按账号隔离，去重，最多 100 张/128 MiB，单张最多 16 MiB，超限淘汰旧图片。沙盒内使用文件保护和私有权限，排除系统备份；不上传图片，诊断没有图片、路径或账号值。面板提供清除当前账号闪照功能。闪照保留与防撤回开关独立。关闭闪照开关后停止保存并隐藏聊天重看入口，已有副本可手动清除。消息路径关联仅保存哈希，不写入诊断。

普通消息副本仍按账号最多 512 条/16 MiB、单条 256 KiB 保存，关闭不自动删除。普通附件只保留消息模型与路径；闪照的新功能另行保存图片数据。

## 下载和安装

从 [Actions](https://github.com/zwthys-cyber/qq-anti-recall-ios/actions) 下载本版成功构建的 **QQAntiRecall-0.7.1-9.3.86.617-arm64**。用其中 QQAntiRecall.dylib 替换旧插件，注入对应解密 QQ IPA 并与 QQ 一起重签名安装。包中附构建信息、SHA-256 与合成界面截图。动态库的 ad-hoc 签名不能代替设备安装签名。

## 验证边界

编译、二进制检查、测试、签名验证全部在 GitHub Actions，当前服务器不执行仓库或构建命令。UIKit 测试使用 iOS 18.5 模拟器和合成数据，不运行真实 QQ。新增测试检查另一种消息行的窗口挂载、标识布局/复用、聊天闪照入口、独立开关、消息匹配隔离、独立闪照副本在原文件删除后重复打开、原返回值保持、去重、关闭、账号隔离和清除。

用户确认的是 0.5.0 消息防撤回；用户进一步确认 0.6.0 撤回标识及聊天闪照重看可见、可点击；后续滚动、间距和设备名改动仍需真机验证。runtime_qq_verified 保留 false，不能用 Hook 安装数代替真机效果。闪照诊断在 flash_retention：decrypt_calls、images_saved、unsupported_results、save_failures 与 hook_active。

[历次接口证据](Compatibility/qq-9.3.86.617.json) · [0.4.0 逐项日志分析](docs/runtime-0.4.0-analysis.md) · [闪照静态接口检查](https://github.com/zwthys-cyber/ipa-decrypt-lab/actions/runs/43775209334)

0.6.1 对可识别的消息气泡改为下方 4 点间距，并按实际占用高度预留空间。

0.6.1 同时保留列表底部位置：原本在最新消息处时，增加标识高度后仍保持最新消息在输入栏上方；上翻历史时不强行跳到底部。

0.6.1 修复密集布局时过早消耗标识行高重试次数的问题；QQ 正在批量更新列表时延后处理，测试覆盖 64 次连续布局。

0.6.1 补充设备名页面诊断：除现存脚本标签外，也扫描资源加载记录与同源子页面，支持 .mjs 模块；新增扫描数量和执行错误计数。仍不读取 Cookie、输入内容或请求体，不执行设备名提交。

## 自定义设备名：官方页面保存请求适配（实验）

在插件设置打开“自定义设备名”，输入文字并“保存到插件”，然后进入 QQ 原生的“自定义设备名”页面，等约两秒后点击 QQ 自己的保存按钮。插件仅在官方页面、当前账号、已识别的 SetCustomOnlineStatus JSON 请求中替换 sModelShow，保留设备绑定、版本、登录请求和其余字段。没有匹配的请求会原样放行；没有发送独立的云端改名请求。

页面会在识别到 QQ 返回成功后提示“QQ已接受设备名，请让好友确认显示”。服务端拒绝、未识别响应与成功分开记录。是否允许指定文字、是否需要账号权限由 QQ 服务端决定；本版尚未验证好友实际看到的名称，不把模拟测试或请求已替换当成好友可见成功。关闭自定义覆盖只停止之后的替换，不自动改回已提交的名称；改回原名称需在 QQ 官方页面重新保存。

配置按账号保存在本机。诊断 device_name_integration.submission 仅包含是否配置、请求修改次数和结果计数，不含输入的设备名、账号、Cookie、请求体或设备绑定参数。public_script_assets 的资源诊断仍可用于适配没有匹配的页面版本。

接口线索来自公开源代码中对官方服务的调用：[QQTool 的在线状态功能](https://github.com/netcccyun/toolbox/blob/45ccaee1f4d67ef2abeebb72907e43e10fed4991/app/lib/QQTool.php)。实现采用官方页面实际请求的结构校验，不照搬旧 Android 参数或另取登录凭据。

### 0.7.1 performance and submission correction

Layout callbacks reuse recall/flash state for up to 0.5 seconds, invalidated immediately on store/switch notifications and record rebinding. Unchanged store notifications no longer force whole-table height updates; hook-origin checks run during installation instead of each layout. Experimental device-name submission replaces both `sModel` and `sModelShow`, preserving the official text prefix (`sDesc`). This addresses a possible mismatch in 0.7.0, which only changed `sModelShow`; it does not establish that the backend accepts arbitrary model names. The observed server code -5 is not assigned an undocumented meaning; server acceptance and friend-visible output still require device verification.
