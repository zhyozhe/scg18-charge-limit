#!/system/bin/sh
# バッテリー保護（置き換え版）起動時ワンショット v2 — 遅れて書き直す方式
# 置き場所: /data/adb/service.d/protectcap_boot.sh (Magisk が起動時に1回だけ実行)
#
# v1 の敗因: 起動後15秒で1回だけ書いたが、その後に純正側が protect_battery を
# 1→0 に戻し、BatteryService が 100 を書いて確定した (2026-11-11 実測)。
# v2: 書くタイミングを後ろにずらし、3段 (約60秒 / 約180秒 / 約300秒) で同じ内容を
# 書き直す。毎回ログ (/data/adb/protectcap/boot_apply.log) に
# 「書く前の protect_battery と fullcap / 書いた後の読み戻し」を残す。
# 常駐はしない。3段書いて終わる。表示 (su ダイアログ/トースト) は出ない
# (service.d は Magisk デーモン自身の権限で走るため)。
#
# value ファイル: /data/adb/protectcap/value … 0=オフ / 50,60,80=上限 / 無ければ何もしない

VFILE=/data/adb/protectcap/value
LOG=/data/adb/protectcap/boot_apply.log
[ -f "$VFILE" ] || exit 0
V=$(cat "$VFILE" 2>/dev/null)
case "$V" in
  0|50|60|80) ;;
  *) exit 0 ;;
esac

# sysfs が生えるまで少し待つ
i=0
while [ $i -lt 30 ]; do
  [ -e /sys/class/power_supply/battery/batt_full_capacity ] && break
  sleep 2
  i=$((i+1))
done

apply_once() {
  # $1 = 段のラベル。書く前に状態を記録し、書いた後に読み戻して記録する
  PB_BEFORE=$(settings get global protect_battery 2>/dev/null)
  FC_BEFORE=$(cat /sys/class/power_supply/battery/batt_full_capacity 2>/dev/null)
  if [ "$V" = "0" ]; then
    settings put global battery_protection_threshold 80
    settings put global protect_battery 0
  else
    settings put global battery_protection_threshold "$V"
    settings put global protect_battery 0
    sleep 1
    settings put global protect_battery 1
    sleep 1
    echo "$V OPTION" > /sys/class/power_supply/battery/batt_full_capacity
    echo "$V" > /efs/Battery/batt_full_capacity
    echo 0 > /sys/class/power_supply/battery/batt_soc_rechg
  fi
  sleep 2
  PB_AFTER=$(settings get global protect_battery 2>/dev/null)
  FC_AFTER=$(cat /sys/class/power_supply/battery/batt_full_capacity 2>/dev/null)
  UP=$(cut -d' ' -f1 /proc/uptime)
  echo "stage=$1 up=${UP}s V=$V pb:${PB_BEFORE}->${PB_AFTER} fullcap:${FC_BEFORE}->${FC_AFTER} $(date +%H:%M:%S)" >> "$LOG"
}

# 1段目: 起動から約60秒
sleep 45
apply_once 1
# 2段目: 約180秒
sleep 120
apply_once 2
# 3段目: 約300秒
sleep 120
apply_once 3
exit 0
