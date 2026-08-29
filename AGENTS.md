# DeskTile 项目协作规则

## 通用要求

- 永远使用中文回答。
- 新文件名尽量使用中文；已有源码命名体系保持一致，不为改名制造无关变更。
- 使用 `5.6-sol` 模型时，禁止调用 `luna` 模型。
- 保留用户已有和与当前任务无关的工作区改动，不得擅自回退或覆盖。

## 版本规则

- 每新增一个独立功能，补丁版本加 1，构建号也加 1。例如 `1.2.2+7` 的下一个功能版本是 `1.2.3+8`。
- 版本号必须同步到 `pubspec.yaml`、Windows 资源、Android/Windows 更新回退常量、Inno Setup 和相关测试、文档。
- Git 标签使用不含构建号的 `vX.Y.Z`，并且必须与 `pubspec.yaml` 中的 `X.Y.Z` 完全一致。

## 新版本自动发布到 GitHub

当用户要求“出新版本”，或一个功能完成并按上述规则递增了版本时，除非用户明确要求只做本地构建或不要发布，否则视为已授权执行完整发布流程，不得停在本地生成安装包：

1. 检查 `git status`，只纳入本版本功能、版本、测试、文档和发布配置；不得提交密钥、`android/key.properties`、keystore、缓存、临时文件或无关用户改动。
2. 运行 `flutter analyze` 和完整 `flutter test`，必须全部通过。
3. 构建并核验 Windows Release、Inno Setup 安装包和 Android Release APK；确认版本号、Android `versionCode`、APK 签名和 SHA-256 均正确。
4. 确认 `origin` 指向 `GodBook/DeskTile`，提交本版本改动，提交信息使用 `release: vX.Y.Z`。
5. 先推送当前发布分支，再创建并推送带注释标签 `vX.Y.Z`。标签已经存在时禁止强制覆盖，必须先核对远端状态并报告。
6. 标签推送后，持续检查 `.github/workflows/android-release.yml` 与 `.github/workflows/windows-release.yml`，直到两个工作流都成功结束；失败时继续诊断并处理，不得把“已推送标签”当作发布完成。
7. 最后通过 GitHub Release/API 核验最新正式版本确为 `vX.Y.Z`，并确认至少包含 Android APK、Android AAB、Windows x64 Setup 及对应 SHA-256 校验文件。

不得强制推送分支或重写已经发布的标签。若认证、网络、GitHub Secrets 或外部服务阻止发布，应保留本地成果并明确说明阻塞点和恢复步骤。
