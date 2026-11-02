# MouseControl 能力清单

日期：2026-11-02。阶段：用户已确认 01～33 全部纳入开发，当前已有可运行开发版。

按已克隆源码的当前界面、模型、通信实现和设备支持矩阵核对。设备能力已复用到独立 app，滚动核心及新增能力已接入；按具体型号开放控制，实机验证状态见 `docs/development-plan.md`。

产品名称已按用户反馈收窄为 MouseControl。下面完整列出候选能力供选择；上游的键盘、键盘辅具和充电底座仅作为参考资料，不进入鼠标产品默认范围。

## 设备与硬件设置：来自 OpenSnek

| 编号 | 能力 | 具体范围 | 条件与运行方式 |
|---|---|---|---|
| 01 | 设备识别与状态 | 识别支持的雷蛇设备、USB/接收器/Bluetooth；显示型号、连接状态、支持程度及可取得的固件/序列号；切换多设备 | 硬件功能按具体型号和连接方式开放 |
| 02 | DPI 与档位 | 设具体 DPI、调整 1～5 个档位、切换当前档位、读取实体 DPI 按钮切换结果 | 范围按设备限制；实时显示需运行 app/service |
| 03 | X/Y 独立 DPI | 水平与垂直轴分别设置 | 仅支持此能力的设备；Orochi V2 当前仅同值 DPI |
| 04 | USB 回报率 | 当前界面提供 125/500/1000 Hz | 按 USB 设备能力开放；当前 BLE 不提供此设置 |
| 05 | 电量与充电状态 | 百分比、图标、充电状态；低电量着色 | 以设备上报为准；干电池不报充电，未提供剩余 mAh |
| 06 | 硬件低电量阈值 | 设置设备的低电量警告阈值，界面约 5～25% | 部分 USB 型号；当前 BLE 隐藏；与 macOS 通知功能分别选择 |
| 07 | 休眠时间 | 当前界面约 1～15 分钟 | 按设备能力开放；Orochi BLE 已映射，型号专属读写仍待验证 |
| 08 | 基础按键改绑 | 左/右/中键、前进/后退、上下左右滚动、恢复默认、禁用按键 | 每个设备的可改槽位与默认恢复能力不同 |
| 09 | 键盘键与快捷键 | 将鼠标按钮绑定到键盘 HID 键及 Command/Option/Control/Shift 组合 | 当前为单键或修饰键组合；复杂动作序列见 32 |
| 10 | Turbo 连发 | 对支持动作持续重复触发并调频率 | 按设备/动作能力开放 |
| 11 | DPI 按键功能 | 绑定 DPI 循环切换、临时 DPI clutch | clutch 只限有已映射能力的型号；按键写入需实机验证 |
| 12 | Mac 本地配置库 | 新建、从当前设备保存、复制、重命名、删除、应用；重连时选择读取鼠标当前设置或恢复最后配置 | 自动重连恢复需要后台运行 |
| 13 | 鼠标板载配置 | 列出、读取、新建、命名、更新、删除/取消分配、激活配置；跟随支持的实体配置切换按钮更新 | 仅特定设备；Orochi 为单槽，无多槽管理 |
| 14 | 硬件滚轮设置 | 有段落/自由滚动、滚轮加速、Smart Reel | 部分 Basilisk USB 能力；每项取决于硬件读回，Orochi 和当前 Naga 型号不提供 |
| 15 | 板载 RGB 灯光 | 亮度、分区/颜色；关闭、静态、光谱、波浪、触发、随机/单色/双色呼吸，及对应方向/速度 | 灯效按设备/传输开放；部分 BLE 仅静态；Orochi 无 RGB |
| 16 | 软件动态灯效 | Flame、Scrolling Rainbow、Comet Chase、Night Rider、Aurora、Jellybeans；调色板与速度、启停 | 部分 USB 灯光设备；依赖常驻逐帧发送 |
| 17 | 用灯光显示电量 | Battery Meter；选电量来源设备、低/中阈值、颜色；低电量闪烁 | 部分有灯设备/Mouse Dock；常驻；与系统电池组件接入分别选择 |

来源：

- `references/OpenSnek/docs/DEVICE_SUPPORT.md`
- `references/OpenSnek/OpenSnek/Sources/OpenSnekCore/{DeviceSupport.swift,Models.swift,ButtonBindingSupport.swift,SoftwareLighting.swift}`
- `references/OpenSnek/OpenSnek/Sources/OpenSnek/UI/{DeviceDetailView.swift,DeviceDetailDpiStagesCard.swift,DeviceDetailSettingsCards.swift,DeviceDetailButtonMappingCard.swift,DeviceDetailLightingCard.swift,LocalProfileLibraryPanel.swift}`

## Mac 滚动行为：来自 Scroll Reverser

| 编号 | 能力 | 具体范围 | 条件与运行方式 |
|---|---|---|---|
| 18 | 鼠标与触控板独立方向 | 每个滚动来源分别保存自然/传统/保持系统方向；全局启停 | 雷蛇以外的鼠标同样可用；需要常驻及辅助功能权限 |
| 19 | 水平方向独立设置 | 水平跟随垂直、反转、保持原方向；覆盖横向滚轮、Shift+滚轮、触控板横滑 | 规则依事件来源生效 |
| 20 | 滚轮步长 | 每格 1～30 行；单独开关；保留连续滚动与惯性语义 | 对离散滚轮事件调整；不增加平滑滚动动画 |
| 21 | 软件生成事件的来源规则 | 给主动生成滚动事件的软件保存反转/不变规则 | 按事件发送进程识别；按当前前台应用切换规则见 29 |
| 22 | Universal Control 来源识别 | 给通用控制的设备/虚拟来源分别保存滚动规则 | 依系统提供的 HID 来源数据，需要场景验证 |
| 23 | 来源列表与管理 | 来源名/自定义名、最近使用、当前滚动高亮、连续/离散类型、删除记录、垂直/水平详情 | 来源识别、方向规则、设置持久化可独立复用 |

滚动只在 Mac 的事件处理链路内生效，不写入鼠标板载设置。移植时覆盖惯性滚动、休眠/唤醒、蓝牙重连、系统自然方向变化，以及与原 Scroll Reverser 同时运行的冲突处理。

来源：`references/Scroll-Reverser/{README.md,MouseTap.m,ScrollSource.m,SourceTable.h,SourceTable.m,SourcesTableController.m}`。

## 两个项目可复用的通用应用能力

| 编号 | 能力 | 具体范围 | 说明 |
|---|---|---|---|
| 24 | 菜单栏快捷入口 | 多设备选择、实时 DPI/电量、DPI 档位和滑杆、打开设置、退出 | OpenSnek 已有 DPI 面板；滚动快捷开关需结合来源规则做 UI |
| 25 | 后台运行与开机启动 | 菜单栏显隐、启动项、服务与窗口协调、断连/休眠/唤醒恢复 | 滚动、自动重连恢复、软件灯效依赖常驻 |
| 26 | 维护与诊断 | 权限状态/入口、日志等级和查看/清理、设备诊断及复制、重置本地数据、更新检查/稳定与 RC 策略；Scroll Reverser 有自动安装/仅通知/关闭更新策略及 AppleScript 启停 | 日志/错误反馈/连接恢复是基础能力；自动更新需我们自己的发布地址及签名；不复制上游反馈/发布入口 |

开发工具可按需复用：OpenSnekProbe 的设备能力目录、只读探测、USB/BLE 报文与配置调查、精确设备范围及原设置恢复记录；Scroll Reverser 的滚动调试窗口及规则单元测试。这些工具先作为研发手段保留，不进入首版普通用户界面。

## 额外候选：需要我们新增或单独验证

| 编号 | 能力 | 当前证据与范围 |
|---|---|---|
| 27 | macOS 原生电池组件接入 | 已明确优先沿标准 BLE → 系统 Accessory PowerSource → BatteryCenter 路线研究；现有 Orochi 已沿该链显示。若 vendor 与标准读数分歧，研究补充/更新系统记录；来源所有权、去重及私有 API 兼容需验证。此项没有现成桥接实现 |
| 28 | 系统低电量通知 | 设备上报降到选定阈值时发 macOS 通知；含去重和权限管理。现有源码的低电量显示/硬件阈值可以提供基础，通知链路需要新增 |
| 29 | 按前台应用切换配置 | 例如工作软件与游戏使用不同 DPI/滚动规则；新增应用匹配及切换策略 |
| 30 | 配置导入导出 | 导入/导出我们自己的配置文件、迁移原 app 配置；需约定版本格式与恢复方式 |
| 31 | 自定义平滑滚动与加速曲线 | 滚轮动画、平滑程度、速度曲线；需要新增事件处理策略。选择此项要与 20 的步长规则一起设计 |
| 32 | 复杂宏及自动化动作 | 多步按键、延时、组合动作、打开 app 等；需要新增 Mac 端执行器及存储 |
| 33 | 支持上游设备范围 | 按用户确认，暂时接入 OpenSnek 已支持的设备，优先 Orochi V2；18～23 的系统滚动功能覆盖其他品牌 |

## 当前可复用的雷蛇设备范围

OpenSnek 的设备矩阵包括：Basilisk V3 X HyperSpeed、Basilisk V3、Basilisk V3 Pro、Basilisk V3 35K、Basilisk V3 Pro 35K Phantom Green、Orochi V2、Naga Pro、Naga V2 Pro、Naga V3 Pro、Basilisk 2017、Lancehead Tournament Edition、Huntsman Mini、Tartarus Pro、Mouse Dock、Mouse Dock Pro。

设备名仅表示存在对应配置；每一项功能及 USB/BLE 支持程度见上游矩阵。Huntsman Mini、Tartarus Pro 和 Dock 目前主要提供灯光控制。

Orochi V2 已补入 2.4 GHz 接收器定义，与 BLE 共用型号和按键布局；USB 序列号、DPI 五档、回报率、休眠及按键块已本机只读验证。BLE DPI 档位和电量沿用上游验证。硬件写入恢复、BLE 序列号匹配与两种连接的配置往返继续实机验证；鼠标无 RGB，仅一个板载配置槽。

## 用户确认与实现状态

用户已确认 01～33 全部开发。33 暂时沿用 OpenSnek 的现有支持范围；Orochi V2 优先。新 app 已接入表内的上游设备控制，并补充后台滚动、平滑/速度加速、宏、前台应用匹配本地配置、配置导入导出、低电量通知和原生电池来源观察/补充。硬件写入、多型号及 Universal Control 的实机验证继续按条件进行，当前证据和发布项见开发记录。

默认中文，可切换英文。外观采用系统浅/深色、中性背景和少量状态色；Orochi 的 DPI 档位按官方手册显示红、绿、蓝、青、黄。图标默认鼠标，可选可达鸭；应用图标和菜单栏同步并记住选择。
