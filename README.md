# QQ Anti Recall iOS

针对 QQ **9.3.86 / 9.3.86.617**，版本 **0.6.0-experimental**。

0.5.0 用户已确认防撤回成功：编码失败 0、保存 27 次、历史恢复 10 次，未发生字段省略。11 个运行时模型成功编码；重复历史查询的缺失计数不代表新消息全部失败。用户仍未看到标识，头像有调用但 AIOCell 的四个接口调用全为 0，列表行高代理未安装。

0.6.0 增加头像视图挂到窗口/父视图后的延迟刷新，覆盖先绑定消息、后挂入真实聊天列表的路径；测试改用另一种消息行，不依赖旧 AIOCell 的方法命中。标识为浅蓝色圆角“已撤回 · 已保留”，支持深浅色和单元格复用。

新增**打开闪照后保存本机独立图片副本**。点击悬浮“防撤回”按钮 → **查看保留的闪照**，可重复查看已保存图片。QQ 原来的闪照倒计时和原消息入口保持原行为，重复查看从插件面板进入。不处理已经销毁且从未取得图片的闪照。

闪照从已核对的 PhotoBrowserFlashPictureService +decryptImageWithImagePath: 返回结果取得，只接受图片、图片数据或沙盒内的图片文件路径。与 QQ 原资源分开保存，按账号隔离，去重，最多 100 张/128 MiB，单张最多 16 MiB，超限淘汰旧图片。沙盒内使用文件保护和私有权限，排除系统备份；不上传图片，诊断没有图片、路径或账号值。面板提供清除当前账号闪照功能。开启防撤回时启用后续闪照保存，关闭后停止保存，已有副本可手动清除。

普通消息副本仍按账号最多 512 条/16 MiB、单条 256 KiB 保存，关闭不自动删除。普通附件只保留消息模型与路径；闪照的新功能另行保存图片数据。

## 下载和安装

从 [Actions](https://github.com/zwthys-cyber/qq-anti-recall-ios/actions) 下载本版成功构建的 **QQAntiRecall-0.6.0-9.3.86.617-arm64**。用其中 QQAntiRecall.dylib 替换旧插件，注入对应解密 QQ IPA 并与 QQ 一起重签名安装。包中附构建信息、SHA-256 与合成界面截图。动态库的 ad-hoc 签名不能代替设备安装签名。

## 验证边界

编译、二进制检查、测试、签名验证全部在 GitHub Actions，当前服务器不执行仓库或构建命令。UIKit 测试使用 iOS 18.5 模拟器和合成数据，不运行真实 QQ。新增测试检查另一种消息行的窗口挂载、标识布局/复用、独立闪照副本在原文件删除后重复打开、原返回值保持、去重、关闭、账号隔离和清除。

用户确认的是 0.5.0 消息防撤回；0.6.0 提示与闪照功能仍需真机确认。runtime_qq_verified 保留 false，不能用 Hook 安装数代替真机效果。闪照诊断在 flash_retention：decrypt_calls、images_saved、unsupported_results、save_failures 与 hook_active。

[历次接口证据](Compatibility/qq-9.3.86.617.json) · [0.4.0 逐项日志分析](docs/runtime-0.4.0-analysis.md) · [闪照静态接口检查](https://github.com/zwthys-cyber/ipa-decrypt-lab/actions/runs/43775209334)
