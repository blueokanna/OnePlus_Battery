# OnePlus/OPlus 充电兼容修复模块（国行硬件）

## 项目简介
本模块用于修复国行 OPlus 硬件在 OxygenOS/ColorOS 场景下的充电兼容问题，重点解决以下问题：

- 偶发插线无反应、充不进去
- SuperVOOC 协议不触发或被异常降级
- C2C 连接电脑后偶发不充电
- C2C 场景下反复出现 USB 断连/重连提示（反复提示重新拔插）

模块采用 Systemless 方式（不改 system/vendor 分区），通过启动阶段脚本动态注入与纠偏属性。

## 适用范围

### 已重点适配
- OP12（如 CPH2573 / PJD110 / salami）
- OP12R（如 CPH2585 / CPH2609 / aston）
- Ace 系列（部分机型）

### 兼容策略
- 对 OPlus 生态设备（OnePlus/OPPO/realme）启用
- 对未命中机型使用 generic 安全策略，尽量降低副作用

## 核心功能

### 1. 双命名空间属性兼容
同时处理以下属性命名空间，减少 ROM 差异导致的问题：

- persist.vendor.oplus.* 与 persist.vendor.oppo.*
- persist.sys.oplus.* 与 persist.sys.oppo.*

### 2. 机型分档下发（运行时动态）
按机型分档下发关键参数，而不是全机型强推同一组值：

- OP12：偏向高能力快充档位
- OP12R：中间档位
- Ace：更保守档位
- generic：不强推高风险参数

### 3. 温控策略
根据电池温度动态切换策略：

- 高温阈值：43.0°C（battery/temp >= 430）
- 高温时自动进入保守策略（避免继续激进快充协商）

### 4. C2C 电脑连接修复（重点）
在系统运行期间持续监控并动态恢复，不依赖重启：

- 检测 C2C 电脑连接状态（USB online、type、role、电池状态）
- 当出现“在线但不充电”或 Type-C role 异常时自动恢复
- 使用防抖、冷却、会话限流，避免反复触发重连提示

## C2C 强修复开关
模块支持 C2C 修复模式开关（运行时可调）：

- 0：关闭 C2C 修复
- 1：智能防抖修复（默认，推荐）
- 2：强修复模式（更激进，适合顽固场景）

默认情况下，若系统未设置该开关，模块会在 post-fs-data 阶段初始化为 mode=1。

### 设置命令（root 环境）

```bash
# 关闭 C2C 修复
resetprop persist.sys.oplus.c2c.fix.mode 0
resetprop persist.sys.oppo.c2c.fix.mode 0

# 智能模式（默认推荐）
resetprop persist.sys.oplus.c2c.fix.mode 1
resetprop persist.sys.oppo.c2c.fix.mode 1

# 强修复模式
resetprop persist.sys.oplus.c2c.fix.mode 2
resetprop persist.sys.oppo.c2c.fix.mode 2
```

兼容旧字段读取：

- persist.sys.oplus.c2c.force_fix.enable
- persist.sys.oppo.c2c.force_fix.enable

## C2C 防抖与限流机制说明
为降低“反复提示重新拔插”的概率，service 监控采用以下策略：

- 轮询周期：8 秒
- 软修复触发：连续异常达到 3 次
- 软修复冷却：45 秒
- 强修复冷却：180 秒
- 每次插线会话强修复上限：1 次
- 智能模式下强修复阈值：连续异常达到 8 次

### 设计目标
- 避免每次短时抖动都执行强动作
- 避免频繁切换 USB 角色造成系统通知风暴
- 在稳定性与恢复速度之间取得平衡

## 模块工作流程

### post-fs-data 阶段
- 初始化基础安全属性
- 机型识别与分档
- 温度判定并下发首轮策略
- 初始化 C2C 修复模式（若未设置）

### late_start service 阶段
- 二次校验并修复属性
- 输出硬件诊断日志
- 进入 C2C 动态监控循环并按需恢复

## 安装方法

### Magisk / KernelSU 安装
1. 在管理器中选择刷入模块压缩包（如 OnePlus_Battery.zip）
2. 安装完成后重启设备
3. 首次开机后插线测试并查看日志

## 日志与排障

### 日志路径
- /data/local/tmp/op12_chg_postfs.log
- /data/local/tmp/op12_chg_fix.log

### 常用排障命令

```bash
# 查看 post-fs 注入日志
cat /data/local/tmp/op12_chg_postfs.log

# 查看运行期修复日志
cat /data/local/tmp/op12_chg_fix.log

# 过滤 C2C 相关日志
grep -i "C2C" /data/local/tmp/op12_chg_fix.log
```

### 重点观察日志关键字
- C2C会话
- C2C状态
- 软修复已执行
- 强修复已执行
- Type-C role: source -> sink

## 建议的调试顺序
1. 保持默认 mode=1，先验证是否已不再频繁弹出重连提示
2. 若仍偶发不充电，再切 mode=2 观察
3. 若出现不必要干预，可切 mode=0 做 A/B 对比
4. 对比日志中恢复动作触发频率，判断是否需要调整阈值

## 注意事项
- 本模块仅建议用于 OPlus 生态设备
- 高温场景会主动保守，属于保护行为，不是故障
- 不同内核/ROM 对 Type-C 节点权限可能不同，个别机型强修复动作可能受限
- 本模块不替代硬件故障排查（线材、接口、充电头）

## 项目文件说明
- customize.sh：安装界面与设备信息提示
- post-fs-data.sh：早期属性注入与初始化
- service.sh：运行期修复、诊断、C2C 监控
- system.prop：基础静态安全属性
- module.prop：模块元信息

## 更新方向（可选）
- 增加可配置阈值文件（温控阈值、防抖参数）
- 按电脑端 USB 类型（SDP/CDP）进一步细分策略
- 增加更详细的统计日志（会话成功率、恢复耗时）
