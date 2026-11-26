#!/bin/sh
# FM350 定时重启守护 + CGI
# =================================
# 用法:
#   fm350_reboot.sh status
#   fm350_reboot.sh set    <minute> <hour> <day> <month> <weekday>
#   fm350_reboot.sh unset
#   fm350_reboot.sh do_reboot_now

CRON_FILE="/etc/crontabs/root"
LOG_FILE="/var/log/fm350_reboot.log"

log() { echo "[$(date '+%F %T')] $*" | tee -a "$LOG_FILE"; }

set_schedule() {
    # $1=minute $2=hour $3=day $4=month $5=weekday
    local m="$1" h="$2" d="${3:-*}" mo="${4:-*}" w="${5:-*}"
    [ -z "$m" ] || [ -z "$h" ] && { echo "FAIL: need minute & hour"; return 1; }

    # 去掉旧的 fm350 reboot 条目
    sed -i '/# FM350 AUTO REBOOT/d' "$CRON_FILE" 2>/dev/null || touch "$CRON_FILE"

    echo "$m $h $d $mo $w root /usr/bin/fm350_reboot.sh do_reboot_now # FM350 AUTO REBOOT" >> "$CRON_FILE"
    log "set schedule: $m $h $d $mo $w"

    # 如果 cron 服务没跑, 尝试启动
    pgrep -f crond >/dev/null 2>&1 || {
        /usr/sbin/crond 2>/dev/null || crond 2>/dev/null
        log "crond started"
    }
    echo "OK: schedule set: $m $h $d $mo $w"
}

unset_schedule() {
    sed -i '/# FM350 AUTO REBOOT/d' "$CRON_FILE" 2>/dev/null
    log "schedule cleared"
    echo "OK: schedule cleared"
}

show_status() {
    echo "=== crontab ==="
    grep "FM350" "$CRON_FILE" 2>/dev/null || echo "(no schedule)"
    echo ""
    echo "=== crond ==="
    pgrep -af crond 2>/dev/null || echo "(not running)"
    echo ""
    echo "=== uptime ==="
    uptime
    echo ""
    echo "=== last reboot hint ==="
    last -x reboot 2>/dev/null | head -3 || echo "(no last command)"
}

do_reboot_now() {
    log "AUTO REBOOT triggered"
    echo "[$(date '+%F %T')] FM350 auto-reboot trigger" >> /var/run/fm350/reboot_history
    # 给 10 秒让守护进程 flush
    sync
    sleep 2
    reboot
}

case "${1:-status}" in
    status)          show_status ;;
    set|schedule)    set_schedule "$2" "$3" "$4" "$5" "$6" ;;
    unset|clear)     unset_schedule ;;
    now|reboot)      log "manual reboot"; (sleep 2; reboot) & echo "OK: reboot in 2s" ;;
    do_reboot_now)   do_reboot_now ;;
    *) echo "usage: $0 status | set <m> <h> [d] [mo] [w] | unset | now"; exit 1 ;;
esac
