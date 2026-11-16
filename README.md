# QQ 名片赞领取辅助工具

版本 **1.2.0** · 源码分支 `codex/qq-card-claim-once`

支持每天手动运行多次，每次只处理一个目标、一笔订单。项目本身不限制每天只能运行一次；第三方站点仍决定是否受理。**“可以多次运行”不等于“保证每天多次到账”。**

## 运行入口

默认分支注册的工作流 **Card claim manual**：
[打开 Actions](https://github.com/zwthys-cyber/qq-anti-recall-ios/actions/workflows/card-claim-manual.yml)

1. 确认 Repository Secret `QQ_CARD_CLAIM_TARGET` 已配置为收赞 QQ 号。
2. 打开工作流，点击 **Run workflow**，保持默认分支 `main`。
3. 选择操作：
   - `inspect`：只读取公开商品。
   - `eligibility`：提交号码进行免费价格预览，禁止下单。
   - `submit-once`：同时勾选 `confirm_submit`，才允许尝试一笔免费订单。
4. 查看运行 Summary 和 `card-claim-result` 报告。
5. 需要再次操作时新建一次手动运行。不要使用 **Re-run jobs** 重放提交；提交模式会拒绝第二次运行尝试。

没有定时任务、自动循环、代理切换或额度失败后的自动重试。当前升级不产生订单。

## 额度与结果

| 状态 | 含义 |
| --- | --- |
| `product_visible` | 页面商品存在，未检查目标资格 |
| `free_preview_available` | 预览明确免费，最终下单仍可能被拒绝 |
| `quota_exhausted` | 名额不足、额度限制或 HTTP 429；停止本次操作，等站点恢复 |
| `already_claimed` | 站点提示已领取；不重复提交 |
| `login_required` / `verification_required` | 需要登录或验证，停止 |
| `free_price_not_confirmed` | 价格不明确或非零元，不下单 |
| `preview_timeout_no_order` | 预览超时，未下单 |
| `order_accepted` | 第三方受理订单，尚未核实 QQ 到账 |
| `submission_unknown_do_not_retry` | 已发送但回执不明确；先核对，避免再次运行产生重复订单 |
| `provider_rejected` / `http_error` | 其他拒绝或 HTTP 错误 |
| `stopped_without_order` | 配置、页面或其他前置检查失败，未下单 |

`arrival_verified` 自动报告始终为 false；到账须通过 QQ 页面核对。脚本不把“HTTP 200”“工作流绿色”或“创建订单成功”当成到账。

## 已有验证记录

- 2026-11-16：首次订单受理，用户截图确认总数 28 → 128。
- 同日第二次：价格预览成功，最终下单却返回名额不足。
- 当前没有证据证明站点的限制只针对 IP，也没有每天多次实际到账的验证记录。
- 版本 1.2.0 增加的是手动多次操作入口，不能改变第三方额度。

## 隐私与防重复

QQ 号只从 Secret 读取，仅在资格检查/下单时发送给 `qqqzz.cc`。不需要 QQ 密码或 Cookie。
报告仅保存预定义状态、HTTP 状态、布尔值、时间和版本，不保存 QQ 号、页面正文、原始回包或订单标识。
报告保留 7 天。

提交需显式确认、手动触发、首次运行和明确零元预览。每次最多放行一个来源、方法及目标均匹配的订单请求。
工作流按同一并发组串行运行，但不代表跨新运行的永久订单去重。收到不明确回执时不要重新发起。

## 工程与运行

执行全部位于 GitHub Actions，当前服务器不运行仓库命令、构建或测试。
默认分支的手动入口固定到已验证的源码提交，避免功能分支后续变动悄悄影响提交行为。
更新源码后，须先通过本分支测试，再更新入口固定的提交。

Push 只运行离线测试。合成测试覆盖额度识别、零元判定、精确目标匹配、单次放行、只读拦截、禁止重放和报告脱敏。它们不会访问领取站，也不证明站点有额度。

QQ iOS 插件仍在 `main`，本次只新增独立 Actions 入口，不修改插件源码或版本。

## 来源

参考项目：[GaoZitian/qqqzz-card-claim](https://github.com/GaoZitian/qqqzz-card-claim)；第三方站点 `qqqzz.cc`，商品 83。
参考项目的“每天100个”说明不是持续可用性保证。本工具不修改本机获赞计数，不承诺突破额度。

## 2026-11-16 领取规则调查

通过 GitHub Actions 只读访问商品页面和已加载的公开前端资源，未读取目标 Secret、未下单。

- 页面公告明确写着“本站点依旧可以每天免费领取100个名片赞哦”。
- 商品 83 的公开接口返回 `stock=99999`，因此不能仅凭“名额不足”断言商品页面库存售罄；这个库存字段也不等于免费领取额度。
- `min_order_num=1`、`max_order_num=100` 是订单数量字段，不能据此认定允许每天重复领取 100 次。
- 页面使用服务端价格预览与下单接口，已实测预览成功后下单仍可能拒绝。
- 未获得可以确定计数维度（账号、IP、会话等）或准确重置时间的公开证据。全站配置中的 `nextResetSeconds=0` 不能解释为本商品领取额度已恢复。
- 本轮未验证换 IP 是否有效，也未增加点赞。不得把项目作者的经验描述标成本站实测规则。

证据：[公开页面与接口检查](https://github.com/zwthys-cyber/qq-anti-recall-ios/actions/runs/43806956639)、[商品配置与前端资源检查](https://github.com/zwthys-cyber/qq-anti-recall-ios/actions/runs/43807113074)。
