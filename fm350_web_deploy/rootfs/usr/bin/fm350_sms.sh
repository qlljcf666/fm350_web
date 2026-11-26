#!/bin/sh
# FM350 SMS 短信收发守护 + 工具脚本
# =========================================
# 用法:
#   fm350_sms.sh send <num> <text>         发送短信
#   fm350_sms.sh list [ALL|RECVD|SENT|UNREAD]  列出短信
#   fm350_sms.sh read <index>              读一条
#   fm350_sms.sh delete <index>            删一条
#   fm350_sms.sh delete_all                全删
#   fm350_sms.sh poll                      守护模式: 轮询新消息 + 写入 inbox
#   fm350_sms.sh status                    运行状态

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/at_helper.sh"

INBOX_FILE="/var/run/fm350/sms_inbox.json"
OUTBOX_FILE="/var/run/fm350/sms_outbox.json"
LAST_ID_FILE="/var/run/fm350/sms_last_id"
LOG_FILE="/var/log/fm350_sms.log"
POLL_INTERVAL=5

log() { echo "[$(date '+%F %T')] $*" | tee -a "$LOG_FILE"; }

prepare() {
    mkdir -p /var/run/fm350
    touch "$INBOX_FILE" "$OUTBOX_FILE" "$LOG_FILE"
    [ -f "$LAST_ID_FILE" ] || echo "0" > "$LAST_ID_FILE"
    # 确保文本模式
    at_ok "AT+CMGF=1" 2>/dev/null
    at_cmd "AT+CNMI=2,1,0,0,0" 2>/dev/null   # 新消息通知
}

# ---- 发送短信 ----
sms_send() {
    local num="$1" text="$2"
    [ -z "$num" ] || [ -z "$text" ] && { echo "FAIL: need num & text"; return 1; }
    prepare

    # 确保文本模式
    at_ok "AT+CMGF=1" || { log "set CMGF=1 failed"; return 1; }

    # FM350 发送流程: AT+CMGS=<num> -> 等 > -> 发内容 -> \x1A(CTRL+Z)
    local port=$(at_find_port)
    local tool=$(at_find_tool)
    [ -z "$port" ] && { echo "FAIL: no AT port"; return 1; }

    log "send SMS to $num: ${text:0:40}..."

    case "$tool" in
        fibocom)
            # fibocom_cmd 可能不支持 CMGS 流式, 先试试单条
            # 退化方案: 用 microcom
            if command -v microcom >/dev/null 2>&1; then
                port=$(at_find_port)
                # microcom 支持交互: 先发 CMGS, 等 prompt, 发文本, CTRL+Z
                {
                    echo -ne "AT+CMGF=1\r\n"
                    sleep 0.3
                    echo -ne "AT+CMGS=\"$num\"\r\n"
                    sleep 0.5
                    echo -ne "${text}\x1a"
                    sleep 1
                } | timeout 5 microcom -t 500 "$port" 2>/dev/null | tee -a "$LOG_FILE" | grep -qi "OK" && {
                    echo "OK: sent to $num"; log "SMS sent -> $num"; return 0
                }
            fi
            # 兜底 fibocom_cmd
            fibocom_cmd "" "AT+CMGS=\"$num\",${#text}\r$text" 2>/dev/null | grep -qi "OK" && {
                echo "OK: sent"; return 0
            }
            ;;
        microcom)
            port=$(at_find_port)
            {
                echo -ne "AT+CMGF=1\r\n"
                sleep 0.3
                echo -ne "AT+CMGS=\"$num\"\r\n"
                sleep 0.5
                echo -ne "${text}\x1a"
                sleep 1.5
            } | timeout 6 microcom -t 500 "$port" 2>/dev/null | tee -a "$LOG_FILE" | grep -qi "OK" && {
                echo "OK: sent to $num"; log "SMS sent -> $num"; return 0
            }
            ;;
    esac

    # 失败了
    log "send SMS to $num FAILED"
    echo "FAIL: send failed, check $LOG_FILE"
    return 1
}

# ---- 列出短信 (返回 JSON) ----
sms_list() {
    prepare
    local filter="${1:-ALL}"   # ALL | RECVD | SENT | UNREAD

    # 用 AT+CMGL 列出, FM350 可能不支持 UNREAD 单独过滤, 全列后本地过滤
    local out=$(at_cmd "AT+CMGL=\"$filter\"" 5000)
    [ -z "$out" ] && { echo "[]"; return; }

    # 解析 +CMGL: idx,status,addr,...\r\n 内容\r\n
    # 组装 JSON array
    local first=1
    echo "["
    echo "$out" | awk '
        BEGIN { first=1; }
        /^\+CMGL:/ {
            if (!first) printf ",\n"
            first=0
            # +CMGL: 1,"REC UNREAD","13800138000",,"26/11/26,12:30:00+08"
            rest=$0
            idx=substr(rest, index(rest,":")+1)
            split(idx, a, ",")
            idx_val=a[1]; status=a[2]; addr=a[4]
            # 读下一行是内容
            getline
            text=$0
            # JSON 转义
            gsub(/\\/, "\\\\", addr); gsub(/"/, "\\\"", addr)
            gsub(/\\/, "\\\\", text); gsub(/"/, "\\\"", text)
            gsub(/\\/, "\\\\", status); gsub(/"/, "\\\"", status)
            printf "{\"idx\":%s,\"status\":\"%s\",\"addr\":\"%s\",\"text\":\"%s\"}", idx_val, status, addr, text
        }
    '
    echo "]"
}

# ---- 读单条 ----
sms_read() {
    local idx="$1"
    [ -z "$idx" ] && { echo "FAIL: need index"; return 1; }
    prepare
    at_cmd "AT+CMGR=$idx" 3000 | at_clean
}

# ---- 删除 ----
sms_delete() {
    local idx="$1"
    [ -z "$idx" ] && { echo "FAIL: need index"; return 1; }
    prepare
    at_cmd "AT+CMGD=$idx" 3000 | at_clean
}

sms_delete_all() {
    prepare
    at_cmd "AT+CMGD=0,4" 5000 | at_clean   # 4 = 删全部
}

# ---- 守护: 轮询新消息 ----
sms_daemon() {
    log "fm350_sms daemon start, poll=${POLL_INTERVAL}s"
    while :; do
        prepare
        local last_id=$(cat "$LAST_ID_FILE" 2>/dev/null || echo "0")

        # 列出所有, 取 index 最大的
        local out=$(at_cmd "AT+CMGL=\"ALL\"" 5000)
        local max_id=$(echo "$out" | grep -oE '^\+CMGL: *[0-9]+' | awk -F: '{print $2}' | sort -n | tail -1)
        [ -z "$max_id" ] && max_id=0

        if [ "$max_id" -gt "$last_id" ]; then
            # 有新消息, 拉取 idx > last_id 的
            echo "$out" | awk -v last="$last_id" '
                /^\+CMGL:/ {
                    rest=$0
                    idx=substr(rest, index(rest,":")+1)
                    split(idx, a, ",")
                    i=a[1]+0
                    if (i > last) {
                        getline
                        addr=a[4]; text=$0
                        print i "|" addr "|" text
                    }
                }
            ' | while IFS='|' read -r idx addr text; do
                log "NEW SMS #$idx from $addr: ${text:0:60}"
            done
            echo "$max_id" > "$LAST_ID_FILE"
        fi

        sleep "$POLL_INTERVAL"
    done
}

# 主入口
case "${1:-}" in
    send)        sms_send "$2" "$3" ;;
    list)        sms_list "${2:-ALL}" ;;
    read)        sms_read "$2" ;;
    delete)      sms_delete "$2" ;;
    delete_all)  sms_delete_all ;;
    poll|daemon) sms_daemon ;;
    status)
        echo "=== SMS daemon status ==="
        pgrep -f fm350_sms.sh && echo "running" || echo "not running"
        [ -f "$LAST_ID_FILE" ] && echo "last_id: $(cat $LAST_ID_FILE)"
        echo "=== AT port ==="
        at_find_port
        ;;
    *)
        echo "usage: $0 send <num> <text> | list [ALL|RECVD|SENT|UNREAD] | read <idx> | delete <idx> | delete_all | poll | status"
        exit 1
        ;;
esac
