ui_print " "
ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ui_print "   OnePlus 电池充电兼容模块 v1.3"
ui_print "   国行硬件 x OOS/ColorOS 兼容优化"
ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ui_print " "

MODEL=$(getprop ro.product.model)
DEVICE=$(getprop ro.product.device)
BUILD=$(getprop ro.build.display.id)
BRAND=$(getprop ro.product.brand)
MANUFACTURER=$(getprop ro.product.manufacturer)
REGION=$(getprop ro.oplus.regionmark)
[ -z "$REGION" ] && REGION=$(getprop ro.vendor.oplus.regionmark)
[ -z "$REGION" ] && REGION=$(getprop ro.boot.hwc)

ui_print "  设备: $MODEL ($DEVICE)"
ui_print "  系统: $BUILD"
ui_print "  厂商: $BRAND/$MANUFACTURER"
ui_print "  区域: ${REGION:-unknown}"
ui_print " "

# 设备识别（优先识别 OP12 国行/国际硬件）
if echo "$MODEL $DEVICE" | grep -qiE "OnePlus 12|CPH2573|PJD110|salami"; then
    ui_print "  ✓ 已识别为 OnePlus 12 系列硬件"
elif echo "$MODEL $DEVICE" | grep -qiE "OnePlus|OPPO|PJD|CPH"; then
    ui_print "  ✓ 已识别为 OPlus 系硬件（兼容模式）"
else
    ui_print "  ⚠ 未识别为目标机型，将按通用安全模式安装"
fi

# 系统识别
FLAVOR=$(getprop ro.build.flavor)
if echo "$FLAVOR $BUILD" | grep -qiE "OOS|OxygenOS|oxygen|global"; then
    ui_print "  ✓ 已检测到 OxygenOS"
elif echo "$FLAVOR $BUILD" | grep -qiE "ColorOS|color"; then
    ui_print "  ✓ 已检测到 ColorOS"
else
    ui_print "  ⚠ 系统标识不明确，将启用双命名空间兼容策略"
fi

if echo "$REGION" | grep -qiE "CN|China|CHN|PRC"; then
    ui_print "  ✓ 国行区域标识已检测到"
elif [ -n "$REGION" ]; then
    ui_print "  ℹ 区域标识为 $REGION（仍会启用兼容注入）"
fi

ui_print " "
ui_print "  正在配置文件权限..."
chmod 0755 "$MODPATH/service.sh"
chmod 0755 "$MODPATH/post-fs-data.sh"
rm -f /data/local/tmp/op12_chg_fix.log 2>/dev/null
rm -f /data/local/tmp/op12_chg_postfs.log 2>/dev/null
ui_print "  ✓ 安装完成"

ui_print " "
ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ui_print "  重启后生效"
ui_print " "
ui_print "  修复内容："
ui_print "  • 偶发性充不进 / 插上无反应"
ui_print "  • SuperVOOC 100W 协议不触发"
ui_print "  • 充电速率被异常降级"
ui_print "  • OPlus/OPPO 属性命名差异导致的兼容问题"
ui_print " "
ui_print "  诊断日志："
ui_print "  /data/local/tmp/op12_chg_fix.log"
ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ui_print " "
