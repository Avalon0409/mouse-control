# 发布

1. 获取固定依赖，生成工程，运行测试。源码必须提交，工作树必须干净。
2. 为正式提交创建 `vMAJOR.MINOR.PATCH` 标签，例如 `v0.1.0`。
3. 使用持久开发签名证书构建通用二进制：

```sh
python3 scripts/build_local.py --configuration Release --derived-data build/ReleaseDerivedData
python3 scripts/package_release.py --app build/ReleaseDerivedData/Build/Products/Release/MouseControl.app --output build/releases/v0.1.0
```

构建脚本从当前标签取得版本，从 Git 提交数量取得递增构建号，并写入提交号、标签和 release 通道。打包脚本确认 Git 标签、应用版本、提交号、双架构和代码签名一致，再生成 ZIP、签名 appcast、SHA-256 及 manifest。

更新私钥保存在当前用户 `~/Library/Application Support/MouseControl/UpdateSigning/private.pem`，必须与 `app/Info.plist` 的 `SUPublicEDKey` 配对。私钥只留在维护者本机，不进入源码、发布包或自动化配置。

GitHub Release 必须使用同一标签并上传四个文件：`MouseControl-VERSION.zip`、`appcast.xml`、`SHA256SUMS.txt`、`release-manifest.json`。发布后下载 ZIP，核对 SHA-256、包内版本及提交号；安装时使用这个下载包，保留现有配置与签名身份，再确认运行路径。

当前发布使用本地开发证书，尚未经过 Apple 公证。签名 feed 用于验证更新包完整性；Developer ID 与 Apple 公证需要另行配置。
