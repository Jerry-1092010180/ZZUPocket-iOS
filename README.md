# ZZUPocket iOS

郑州大学非官方校园助手，支持 iOS 17 及以上，包含课表、校园卡与寝室电量查询。

## 我只想安装使用

**没有 Mac、不懂开发，也不需要下载源码或安装 Xcode。**

**[下载 iPhone 安装包（IPA）](https://github.com/Jerry-1092010180/ZZUPocket-iOS/releases/latest/download/ZZUPocket-iOS-unsigned.ipa)** · **[Windows 分步安装教程](docs/Windows安装.md)** · [所有版本](https://github.com/Jerry-1092010180/ZZUPocket-iOS/releases)

请在 Windows 电脑上下载 IPA，用 [Sideloadly](https://sideloadly.io/) 安装到自己的 iPhone。IPA 不能在手机的“文件”中直接点开安装。

| 你有什么设备 | 安装方式 |
| --- | --- |
| iPhone + Windows | 下载 IPA → 拖进 Sideloadly → 按手机提示确认，不需要编译 |
| iPhone + Mac，愿意开发 | [Xcode 开发构建说明](ios/README.md) |
| 只有 iPhone，没有电脑 | TestFlight 尚未开放，当前免费侧载方案仍需要电脑 |

免费 Apple 账号安装的 App **每 7 天需要刷新签名**。可按教程开启自动刷新，但需要电脑开机、刷新服务运行且手机能连接。Apple 账号用于安装；学校账号只在手机 App 里输入，用于查询校园数据。

## 给维护者

在 Actions 中运行 **Publish Windows sideload package**，填写新的版本号（例如 `ios-v0.1.1`），自动生成并发布 IPA、校验文件和 Windows 教程。使用者只需从 Releases 下载，不必运行 Actions。每次使用新的版本号，不覆盖已有版本。

源码：[steady298/ZZUPocket-iOS](https://github.com/steady298/ZZUPocket-iOS)。本仓库以 fork 形式保留来源和提交历史。
