# MouseControl

在 macOS 上管理鼠标设置，分别设置鼠标和触控板的滚动方向。默认简体中文，也可切换英文。

- 雷蛇硬件控制：DPI 档位、按键、回报率、休眠与电量，按型号和连接方式开放。
- 同一鼠标的蓝牙和接收器按已验证序列号共享配置，设备列表显示当前接入方式。
- 普通办公鼠标提供基础配置、系统指针速度入口和独立滚动规则。
- 鼠标与触控板独立方向、水平规则、固定步长、平滑滚动与速度调整。
- 本地配置、按应用切换配置、快捷键宏、低电量提醒和配置导入导出。
- 设备列表可滑动或右键移除，并可恢复；移除保留配置。
- 简洁的系统浅色/深色界面，可切换鼠标或可达鸭应用及菜单栏图标。
- 「设置 → 应用 → 仅后台运行」可隐藏 Dock 图标，保留菜单栏入口。关闭窗口后后台继续工作，从菜单栏打开窗口时也保持隐藏 Dock 图标。

## 下载与运行

从 [GitHub Releases](https://github.com/Avalon0409/mouse-control/releases) 下载 MouseControl ZIP，解压后将应用放入「应用程序」。支持 macOS 14 及以上、Apple Silicon 和 Intel。

首次公开版本使用本地开发证书签名，尚未经过 Apple 公证。macOS 拦截时，在「系统设置 → 隐私与安全性」中选择「仍要打开」。独立滚动需要辅助功能权限，实体 DPI 按钮即时同步需要输入监控权限。先退出 Scroll Reverser，再开启 MouseControl 的独立滚动。

初次启动读取鼠标已有设置；滚动、宏和自动配置切换默认关闭。更新检查关联本仓库的 Release，安装更新时校验签名。每个发布包包含 Git 标签、提交号和 SHA-256 清单。

## 从源码构建

需要 Xcode（Swift 6）及 XcodeGen：

```sh
python3 scripts/bootstrap_dependencies.py
xcodegen generate --spec app/project.yml --project app
python3 scripts/build_local.py --configuration Debug --derived-data build/IntegratedDerivedData
```

依赖按 `docs/upstreams.json` 固定版本获取。已有 `references/` 检出版本不同会报错并保留原目录。公开仓库不包含上游克隆、编译产物、本机配置或诊断数据。

开发证书和专用钥匙串保存在当前用户的 `~/Library/Application Support/MouseControl/DevelopmentSigning`，不进入仓库；持续使用同一证书可保持应用更新后的授权身份。发布签名的私钥另存于 `~/Library/Application Support/MouseControl/UpdateSigning`。

```sh
xcodebuild -project app/MouseControl.xcodeproj -scheme MouseControl -configuration Debug -derivedDataPath build/TestDerivedData CODE_SIGNING_ALLOWED=NO test
```

测试使用独立宿主、配置域及构建目录。发布步骤见 [docs/releasing.md](docs/releasing.md)，验证范围见 [docs/development-plan.md](docs/development-plan.md)。

## 来源

复用 OpenSnek 的 Core、Protocols、Hardware、AppSupport 和鼠标控制界面，以及 Scroll Reverser 的事件来源和滚动规则。保留 Apache 2.0 版权、许可及 NOTICE，详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## Supported Devices

下表记录复用的上游设备配置及其验证等级，硬件控制按连接方式和具体能力开放。


Support is transport-specific. A device may be supported over USB, Bluetooth, or both, depending on what has been captured, tested, and validated in the app.

| Device | USB | Bluetooth | Notes |
|---|---|---|---|
| Basilisk V3 X HyperSpeed | Validated | Validated | |
| Basilisk V3 | Mapped | No | OpenRazer-backed USB profile, sharing the Basilisk V3 USB family configuration with a `26,000` DPI ceiling |
| Basilisk V3 Pro | Validated | Validated | |
| Basilisk V3 35K | Validated | No | Shares the Basilisk V3 USB family configuration |
| Basilisk V3 Pro 35K Phantom Green Edition | Not yet | Contributor validated | Contributor validated Bluetooth DPI stages, battery, two-zone lighting (no logo LED), and button remap. Onboard profile CRUD stays hidden and Bluetooth changes reset on power cycle; use restore-on-connect |
| Orochi V2 | Mapped; telemetry read locally | Contributor validated | MouseControl adds the 2.4 GHz receiver profile (`0x0094`) alongside Bluetooth (`0x0095`), sharing the model/button layout. USB serial, DPI stages, poll rate, sleep and button blocks have been read locally; writes/restoration and matching the Bluetooth serial await hardware validation. Mouse has no RGB lighting. |
| Naga Pro | Contributor validated | Contributor validated | All three side panels (2-button, 6-button, 12-button) press-validated with captured native defaults, and five-slot onboard profile workflows ship. The underside profile button (slot `14`) cycles saved profiles and is remappable, with Default restoring the cycle; OpenSnek provides no scroll-wheel adjustment for this mouse |
| Naga V2 Pro | Contributor validated | Contributor validated | Wired, 2.4 GHz receiver, and Bluetooth share DPI stages, battery, side-panel remapping, and logo + 12-button side-panel lighting. The 6- and 2-button plates have no lighting, and the two top DPI buttons stay preserved read-only. OpenSnek provides no scroll-wheel adjustment (mode / acceleration / smart reel) for this mouse |
| Naga V3 Pro | Contributor validated | Contributor validated | Wired USB `0x00E7`, 2.4 GHz receiver `0x00E8`, and Bluetooth `0x00E9`. DPI up to the published `50,000` ceiling with independent X/Y, three lighting zones, and every body button remappable, including both scroll-wheel buttons. The mouse's adjustable scroll-wheel settings (tactile / free-spin / smart-reel mode and its responsiveness levels) are not something OpenSnek can read or change: the firmware rejects the scroll-mode command pair and has no mode readout. They stay adjustable outside OpenSnek, with the front scroll button or Synapse on Windows; the rear scroll button does nothing by default. Onboard profile CRUD stays hidden because the device rejects metadata reads. Bluetooth includes the same eight lighting effects; poll rate remains USB-only |
| Basilisk (2017) | Contributor validated | No | Contributor validated DPI (scalar, X/Y, live 5-stage table), poll-rate reads, and logo/scroll lighting; button remap not yet mapped |
| Lancehead Tournament Edition | Contributor validated | No | Contributor validated DPI (scalar, X/Y, live 5-stage table), poll-rate reads, and all four lighting zones; button remap not yet mapped |
| Huntsman Mini | Contributor validated | No | Keyboard: contributor validated backlight lighting and brightness. First non-mouse profile; key remap not supported |
| Tartarus Pro | Contributor validated | No | Keypad: contributor validated backlight lighting and brightness. Analog actuation and key remap have no public protocol |
| Mouse Dock | Contributor validated | No | Accessory: one logo LED with static color, brightness, and spectrum/pulse writes. No DPI, buttons, battery, or onboard profiles |
| Mouse Dock Pro | Contributor validated | No | Accessory: one logo LED with brightness, static color, wave, spectrum, and breathing. Answers only transaction ID `0xFF` and reads brightness at a different address than it writes; per-cell custom frames are not mapped yet, so it has no software presets or Battery Meter (unlike the original Mouse Dock) |

