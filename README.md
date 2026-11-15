# QQ Anti Recall iOS

目标：iPhone 17 Pro Max / iOS 27.0.1，QQ **9.3.86**，通过重签名 QQ 加载插件。

当前处于定向适配中，尚无已验证的防撤回成品。基础 Objective-C Hook 安装器已加入；其自动测试仅证明 ABI 检查、继承隔离和拦截/放行行为，不能证明真实 QQ 防撤回成功。

## 真实输入

- 用户指定导出：[ipa-decrypt-lab run 43715591869](https://github.com/zwthys-cyber/ipa-decrypt-lab/actions/runs/43715591869)。
- 交付文件使用 age 传输加密；通过原仓库的独立诊断分支在 Actions 内解密、校验原始哈希并提取接口元数据。
- App 二进制、密钥和聊天数据不进入本仓库。
- 本地备用路径由用户提供；未在服务器解包或执行。

## 执行约束

所有编译、自动测试、二进制分析和构建验证均在 GitHub Actions 执行。通过 GitHub API 编辑源码，不在服务器运行 Git、构建命令或测试。

## 验证边界

静态方法存在、模拟对象测试和插件编译通过，均不等于 QQ 登录、真实撤回、后台同步或 iOS 27.0.1 真机运行已经验证。未匹配版本或方法 ABI 时不安装对应 Hook。
