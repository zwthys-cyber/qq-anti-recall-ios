# 0.4.0 用户日志逐项分析

本分析针对 QQ 9.3.86.617。用户观察：当前页面能留住消息，返回主页再进入则显示撤回提示；消息下方没有标识。用户补充测试覆盖多种消息。以下把事实、解释和尚未知的部分分开。

## 版本与安装状态

| 字段 | 日志值 | 含义 |
| --- | --- | --- |
| plugin_version | 0.4.0-experimental | 本次失败来自 0.4.0 |
| short_version / build_version | 9.3.86 / 9.3.86.617 | 精确目标版本 |
| supported_version / enabled | true / true | 版本匹配，功能已开启 |
| installed_hooks | 25 | 安装数量，不是成功保留的消息数 |
| hook_results | 全为 0 | 枚举 0 表示安装成功；不是“调用零次” |
| incoming/history/recall_badge hook_still_active | 全为 1 | 导出时对应 IMP 仍是插件安装的实现 |
| runtime_qq_verified | false | 未经完整真机验收的声明，不是禁用开关 |

以上只能证明安装与启用，不能证明正文已保存或标识已显示。

## 接收与实时过滤

| 字段 | 值 | 解释 |
| --- | --- | --- |
| incoming_hook_calls.swi_received | 15 | 接收回调次数；可能包含批次/重复通知 |
| swi_list_update | 18 | 收到 18 次更新回调 |
| swi_recall | 9 | 收到 9 次撤回通知 |
| incoming_suppressed_calls.swi_list_update / swi_recall | 18 / 9 | 18 个更新批次和 9 次通知被拦截 |
| intercepted_events | 27 | 18 + 9；不能解读为 27 条独立消息 |
| swi_delete | 0 | 未观察到普通删除回调 |
| c2c_package_parse / c2c_inout / c2c_net_parse / recall_codec_write | 全为 0 | 这些备用路径没有命中，本次走 SWI 路径 |
| kernel_recall_events / ui_recall_events | 0 / 0 | 旧 KT/UI 路径没命中，不否定已经命中的 SWI |
| positive_recall_time_writes | 84 | 正撤回时间戳写入次数，历史对象重建也会写；不是 84 条撤回 |
| prevented_recall_flag_writes | 0 | 当前版本观察时间戳而不全局清零，以免破坏语义 |

update_filter 的 inspected_update_items、filtered_recall_update_items、filtered_update_batches、dropped_recall_only_batches 全为 18，forwarded_mixed_update_batches 为 0。说明这些批次全部是已识别的撤回对象，被过滤掉。recall_update_filter_ready=true，record_abi_rejections、record_read_failures、unrecognized_update_payloads、unrecognized_update_items 均为 0，未见此路径的类型或读取故障。这解释了当前页面仍能保留消息。

## 历史入口已经触发，缺的是副本

history_hook_calls：history_operate_result=15，history_first_view=3，history_status_result=2；history_list_added、history_query_result、history_guild_first_view、history_multi_result 都是 0。重进/查询入口确实运行过，并非只安装了未调用的历史 Hook。

| message_store 字段 | 值 | 解释 |
| --- | --- | --- |
| snapshot_encode_failures | 27 | **27 次编码尝试失败，是持久化的直接阻断点** |
| snapshots_saved | 0 | **没有正文副本成功写盘** |
| history_records_restored | 0 | **没有历史消息被副本替换** |
| snapshot_misses | 60 | 查询找不到副本；重复查询也会增加，不是 60 条不同消息 |
| snapshot_decode_failures | 0 | 没有可用副本去解码，不能据此宣称解码器正确 |
| marked_recalled_messages | 3 | 标记了 3 个消息身份；标记不等于正文 |
| missing_account_context / account_context_available | 0 / 1 | 账号读取可用，本次不是缺少账号上下文 |
| disk_failures / last_disk_write_succeeded | 0 / true | 元数据/撤回标记可以写盘，**不表示正文副本写入成功** |
| evicted_snapshots | 0 | 没有淘汰副本，本次不是容量不足 |
| maximum_records_per_account | 512 | 条数上限 |
| maximum_snapshot_bytes_per_account | 16777216 | 每账号 16 MiB 上限 |

records_message_contents=true、content_storage=local_app_only 表示功能会在本地保存内容；uploads_message_contents=false、diagnostics_include_message_contents=false 表示不上传、不写入诊断。这些是功能/隐私声明，不能替代 snapshots_saved 的实际结果。

0.4.0 编码器要求整张模型字段图全部可编码；任一附属字段中的未知对象、循环或 ABI 不匹配都可能拒绝整条消息。旧诊断只累计失败，未记录字段路径和原因，因此**不能从这份 JSON 确认具体失败字段**。0.5.0 将非正文可选字段隔离，支持经运行时核对的模型和共享引用；正文元素仍必须完整编码。新增受限的字段路径/类型/原因诊断，不包含值。

## 标识确实没有画出来

recall_badge.installed_hooks=7，hook_results 全 0、hook_still_active 全 1，只证明旧版接口仍安装。

- badges_created=0：没有创建任何标识视图。
- height_refreshes=2：请求过两次行高更新，不能证明实际增加了行高。
- footer_space_unavailable=1：至少一次保留消息检查因没有足够空间而放弃显示。
- text=已撤回 · 已保留：配置文案，不是已经显示的证据。

旧实现只 Hook AIOBaseCellViewModel 的行高方法，测试夹具也恰好从该方法取得行高，未覆盖真实列表采用另一代理的情况。Actions 检查 43771340173 额外确认 AIOChatTableViewDelegate 的同名方法存在，ABI 为 d32@0:8@16@24。0.5.0 改为发现当前聊天表格的实际 delegate 后核对并接入，不猜测 Swift 模型公开属性；通过 QQNTAIOMessageAvatarView.record 取得已核对的记录。新测试让模型没有 record getter、模型行高方法不被调用、bind 返回 false，并验证实际 delegate 留出的空间、复用及重载。

## trace_samples 的时间顺序

| 毫秒 | 事件 | 解释 |
| --- | --- | --- |
| 664 / 666 | swi_received | 先收到消息 |
| 3923 / 3924 | history_operate_result | 历史操作回调已运行 |
| 10197 | positive_recall_time_observed、swi_list_update | 撤回状态先经更新进入 |
| 10201 | recalled_list_items_filtered，并有第二次同类写入/更新/过滤 | 实时过滤生效，通知可能重复 |
| 10202 | swi_recall 两条样本 | 撤回通知晚于更新 |
| 11614 / 23714 | history_first_view | 后续首屏查询到达 |
| 37680 / 37963 | history_status_result | 带状态查询到达 |

qq_image_offsets 是主程序地址偏移的调用栈样本，用于关联路径；不是错误码，也不包含正文。样本数量受限，不等于完整调用次数。没有 history_record_restored 样本，与恢复计数为 0 一致。

## 验收条件

不能再以“Hook 全绿”判成功。安装新版后，使用新收到的消息检查：snapshots_saved 增长；对方撤回后当前页面仍显示原消息和标识；返回再进入及结束进程后重进，history_records_restored 增长并保持原内容。标识应有 badges_created 和 rows_with_footer_reserved，普通消息不带标识，复用不串行。

Actions 验证为合成模型和 UIKit 模拟器测试，并不代替真实 QQ / iOS 27.0.1 验收。图片、语音、视频和文件目前保存消息元数据及路径，未复制 QQ 的附件文件；资源已被 QQ 清理或服务端不再允许下载时，不能保证打开。旧版 snapshots_saved=0 对应的已丢失内容不能凭空补回。
