# OnePlus/OPlus 充电兼容修复模块（国行硬件）

## 1. 模块说明

这是一个面向 OPlus 生态机型的 Systemless 充电兼容修复模块，主要用于修复以下问题。

- 偶发插线无反应、无法充电
- SuperVOOC 协议不触发或被异常降级
- C2C 连接电脑时偶发不充电
- 锁屏/灭屏时 C2C 连接反复跳连、反复提示重新连接

模块不修改 system/vendor 分区，依赖启动阶段脚本动态注入与运行期纠偏。

## 2. 当前版本

- 版本：v1.1
- versionCode：11
- 模块 ID：op12_charging_fix

## 3. 适用机型与策略

### 3.1 已重点适配

- OP12（如 CPH2573 / PJD110 / salami）
- OP12R（如 CPH2585 / CPH2609 / aston）
- Ace 系列（部分机型）

### 3.2 机型分档

- op12：高能力快充档位
- op12r：中间档位
- ace：保守档位
- generic：不强推高风险参数，优先稳定

## 4. 功能总览

### 4.1 双命名空间兼容

同时处理以下属性空间。

- `persist.vendor.oplus.*` 与 `persist.vendor.oppo.*`
- `persist.sys.oplus.*` 与 `persist.sys.oppo.*`

### 4.2 温控动态策略

- 高温阈值：`battery/temp >= 430`（43.0°C）
- 高温时自动转保守策略，减少异常协商和掉速风险

### 4.3 C2C 运行期动态修复

- 持续监控 USB 在线状态、类型、角色、充电状态
- 出现异常时触发软修复/强修复（受防抖和限流控制）

### 4.4 锁屏/灭屏守护（v1.7 重点）

- 锁屏场景默认启用守护，减少误触发强动作导致的跳连
- 使用 `current_now` 绝对值兜底，避免仅靠 `battery/status` 误判
- 屏幕状态变化时自动清空异常连击计数，避免亮灭屏切换造成误触发

### 4.5 电脑端口类型自动策略（v1.8 重点）

- 自动识别端口类型：`SDP`、`CDP`、`unknown_pc`
- `SDP` 走更保守策略：提高触发阈值、延长冷却、默认禁用强动作
- `CDP` 走平衡策略：允许软修复，必要时有限强修复
- `unknown_pc` 走最保守策略：优先避免误触发导致跳连

### 4.6 黑屏反复连接防抖保护态（v1.9 重点）

- 识别黑屏下短时间多次断连/重连（session churn）
- 自动进入稳定保护态，期间仅低频软修复，禁止频繁强动作
- 保护态结束后自动返回常规策略
- 新增 USB 输入电流判定（`usb/current_now`）以降低黑屏误判

## 5. 开关与参数

### 5.1 C2C 修复模式开关

- `persist.sys.oplus.c2c.fix.mode`
- `persist.sys.oppo.c2c.fix.mode`

取值如下。

- `0`：关闭 C2C 修复
- `1`：智能防抖修复（默认，推荐）
- `2`：强修复模式（更激进）

兼容读取旧字段。

- `persist.sys.oplus.c2c.force_fix.enable`
- `persist.sys.oppo.c2c.force_fix.enable`

### 5.2 锁屏守护开关

- `persist.sys.oplus.c2c.screenoff.guard`
- `persist.sys.oppo.c2c.screenoff.guard`

取值如下。

- `0`：关闭锁屏守护
- `1`：开启锁屏守护（默认）

### 5.3 端口策略开关

- `persist.sys.oplus.c2c.port.policy.enable`
- `persist.sys.oppo.c2c.port.policy.enable`

取值如下。

- `0`：关闭端口自适应（兼容旧行为）
- `1`：开启端口自适应（默认）

### 5.4 黑屏防抖守护开关

- `persist.sys.oplus.c2c.flap.guard.enable`
- `persist.sys.oppo.c2c.flap.guard.enable`

取值如下。

- `0`：关闭黑屏防抖守护
- `1`：开启黑屏防抖守护（默认）

### 5.5 默认初始化逻辑

如果系统没有设置相关值，模块在 post-fs-data 阶段自动初始化。

- `c2c.fix.mode = 1`
- `c2c.screenoff.guard = 1`
- `c2c.port.policy.enable = 1`
- `c2c.flap.guard.enable = 1`

## 6. 推荐配置（直接可用）

### 6.1 日常推荐（优先稳定）

- `c2c.fix.mode = 1`
- `c2c.screenoff.guard = 1`
- `c2c.port.policy.enable = 1`
- `c2c.flap.guard.enable = 1`

### 6.2 锁屏仍偶发不充（加强恢复）

- `c2c.fix.mode = 2`
- `c2c.screenoff.guard = 1`
- `c2c.port.policy.enable = 1`
- `c2c.flap.guard.enable = 1`

### 6.3 A/B 排障（对照测试）

- `c2c.fix.mode = 0`
- `c2c.screenoff.guard = 1`
- `c2c.port.policy.enable = 1`
- `c2c.flap.guard.enable = 1`

## 7. 设置命令（root）

```bash
# 智能模式（推荐）
resetprop persist.sys.oplus.c2c.fix.mode 1
resetprop persist.sys.oppo.c2c.fix.mode 1

# 强修复模式
resetprop persist.sys.oplus.c2c.fix.mode 2
resetprop persist.sys.oppo.c2c.fix.mode 2

# 关闭 C2C 修复
resetprop persist.sys.oplus.c2c.fix.mode 0
resetprop persist.sys.oppo.c2c.fix.mode 0

# 锁屏守护开/关
resetprop persist.sys.oplus.c2c.screenoff.guard 1
resetprop persist.sys.oppo.c2c.screenoff.guard 1
resetprop persist.sys.oplus.c2c.screenoff.guard 0
resetprop persist.sys.oppo.c2c.screenoff.guard 0

# 端口类型自动策略开/关
resetprop persist.sys.oplus.c2c.port.policy.enable 1
resetprop persist.sys.oppo.c2c.port.policy.enable 1
resetprop persist.sys.oplus.c2c.port.policy.enable 0
resetprop persist.sys.oppo.c2c.port.policy.enable 0

# 黑屏防抖守护开/关
resetprop persist.sys.oplus.c2c.flap.guard.enable 1
resetprop persist.sys.oppo.c2c.flap.guard.enable 1
resetprop persist.sys.oplus.c2c.flap.guard.enable 0
resetprop persist.sys.oppo.c2c.flap.guard.enable 0
```

建议设置后重启一次，确保所有组件读取到同一状态。

## 8. 防抖与限流机制（service）

当前脚本参数如下。

- 轮询周期：8s
- 软修复触发：连续异常 3 次
- 软修复冷却：45s
- 强修复冷却：180s
- 每次插线会话强修复上限：1 次
- 智能模式强修复阈值：连续异常 8 次

端口自适应策略（`port.policy.enable=1`）下，会按 USB 类型自动调整阈值与强动作权限。

- `SDP`：提高触发门槛并延长冷却，默认不执行强动作
- `CDP`：中等门槛，亮屏下允许受限强动作
- `unknown_pc`：最高保守级别，优先避免反复跳连

锁屏守护额外参数如下。

- 锁屏软修复触发：连续异常 6 次
- 锁屏软修复冷却：180s
- 锁屏下默认避免频繁强动作（仅 mode=2 且满足条件时允许一次）

黑屏防抖保护态参数如下。

- 短时重连窗口：180s
- 触发阈值：窗口内 4 次会话抖动
- 保护态持续：300s
- 保护态软修复冷却：300s

## 9. 安装方法

1. 在 Magisk/KernelSU 中选择模块压缩包安装。
2. 安装完成后重启。
3. 首次启动后连接充电器、C2C 连接电脑做验证。

## 10. 日志与排障

### 10.1 日志路径

- `/data/local/tmp/op12_chg_postfs.log`
- `/data/local/tmp/op12_chg_fix.log`

### 10.2 常用命令

```bash
cat /data/local/tmp/op12_chg_postfs.log
cat /data/local/tmp/op12_chg_fix.log
grep -i "C2C\|屏幕状态\|锁屏守护" /data/local/tmp/op12_chg_fix.log
grep -i "防抖统计\|防抖统计汇总" /data/local/tmp/op12_chg_fix.log
```

防抖统计日志用于快速判断哪类电脑端口最容易触发黑屏跳连：

- `trigger#`：黑屏保护态累计触发次数
- `class`：本次触发对应端口类型（`sdp`/`cdp`/`unknown_pc` 等）
- `top`：当前触发最多的端口类型与次数
- `sdp/cdp/unknown_pc/...`：各类型累计触发计数

### 10.3 重点观察关键字

- C2C会话
- C2C状态
- 软修复已执行
- 强修复已执行
- 锁屏守护
- 防抖守护
- 防抖统计
- 防抖统计汇总
- 屏幕状态
- Type-C role: source -> sink

## 11. 锁屏跳连专项排障流程

1. 先使用默认推荐：`mode=1 + screenoff.guard=1`。
2. 锁屏连接电脑并观察 3-5 分钟日志是否频繁进入恢复模式。
3. 若仍有锁屏不充，切 `mode=2` 再测试。
4. 若恢复动作过多，保持 `mode=1` 并确认线材、电脑口、Hub 是否稳定。
5. 对比亮屏与灭屏日志差异，重点关注 `current_now` 和 `screen` 字段。
6. 若日志频繁出现“防抖守护”，说明已进入黑屏稳定保护态，可先维持默认配置继续观察。

## 12. 注意事项

- 本模块仅建议在 OPlus 生态设备使用。
- 不同内核的电流方向定义可能不同，本模块已按绝对值做兜底。
- 不同 ROM 对 Type-C 节点权限限制不同，个别机型强修复可能受限。
- 软件修复不替代硬件排查（线材、接口、主板、充电头）。

## 13. 项目文件说明

- customize.sh：安装界面与设备识别提示
- post-fs-data.sh：早期属性注入与默认开关初始化
- service.sh：运行期修复、诊断、C2C 动态监控
- system.prop：基础静态安全属性
- module.prop：模块元信息
