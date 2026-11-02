# MouseControl

- 产品聚焦 macOS 鼠标设置与鼠标/触控板滚动，最低支持 macOS 14。
- 自有代码位于 `app/`，使用 SwiftUI/AppKit，默认中文并支持英文。
- 复用 OpenSnek 的 Core、Protocols、Hardware、AppSupport，以及 Scroll Reverser 的事件来源与规则；保留版权、许可及 NOTICE。
- `references/` 是固定版本的上游资料，保持只读；来源记录在 `docs/upstreams.json`。
- 同一物理鼠标按有效序列号共享配置，不按型号名合并；不同鼠标独立保存。普通 HID 鼠标只用基础控制，不发送雷蛇私有命令。
- 修改硬件前先确认设备身份并记录当前值，写入后读回并验证恢复。蓝牙读取与写入按设备串行执行。
- 日志、配置、缓存与签名材料使用当前用户的系统目录；不硬编码开发者路径，不提交本机数据。
- 本地运行使用 `scripts/build_local.py` 保持固定签名身份；测试使用独立 DerivedData，不能覆盖已授权应用。
- 不提交、导出或重新生成既有开发签名钥匙串和更新私钥，不改变系统信任。
- 发布构建必须从干净的正式 Git 标签生成，包内提交号和版本必须与标签一致。发布步骤见 `docs/releasing.md`。
- 干电池保留设备上报的百分比，不推算不存在的剩余 mAh。已有系统电池来源优先复用。
