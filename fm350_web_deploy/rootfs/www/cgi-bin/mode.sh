#!/bin/sh
# FM350 Web CGI: POST /cgi-bin/mode.sh
# 切换 FM350 USB 工作模式: 40=RNDIS, 41=NCM, 42=ECM
# ================================================

echo "Content-Type: text/plain; charset=utf-8"
echo "Cache-Control: no-store"
echo ""

# 解析 GET 参数 (busybox httpd 把查询串放 QUERY_STRING)
MODE=""
[ -n "$QUERY_STRING" ] && {
    # CGI 环境变量
    eval "$(echo "$QUERY_STRING" | sed 's/&/\n/g' | while read kv; do
        k=$(echo "$kv" | cut -d= -f1)
        v=$(echo "$kv" | cut -d= -f2-)
        [ "$k" = "mode" ] && echo "MODE='$v'"
    done)"
}

# 也尝试 POST body
if [ -z "$MODE" ] && [ "$REQUEST_METHOD" = "POST" ]; then
    read -r MODE 2>/dev/null
    MODE=$(echo "$MODE" | sed 's/mode=//' | cut -d& -f1)
fi

case "$MODE" in
    40|41|42) ;;
    *) echo "FAIL: need mode=40(RNDIS)|41(NCM)|42(ECM), got '$MODE'"; exit 1 ;;
esac

# 自动找 AT 口
AT_PORT=""
if command -v fibocom_cmd >/dev/null 2>&1; then
    # fibocom_cmd 自带端口管理
    AT_PORT="fibocom_cmd"
else
    AT_PORT=$(ls /dev/ttyUSB* 2>/dev/null | head -1)
    [ -z "$AT_PORT" ] && { echo "FAIL: no AT port"; exit 1; }
fi

send_at() {
    if [ "$AT_PORT" = "fibocom_cmd" ]; then
        fibocom_cmd "" "$1" 2>/dev/null
    elif [ -x /bin/microcom ]; then
        echo -ne "${1}\r\n" | timeout 3 microcom -t 500 "$AT_PORT" 2>/dev/null
    elif command -v gcom >/dev/null 2>&1; then
        echo "$1" | gcom -d "$AT_PORT" 2>/dev/null
    fi
}

echo "INFO: switching FM350 mode to $MODE ..."
send_at "AT%MODE=$MODE"
sleep 2

# 验证
ret=$(send_at "AT%MODE?" | tail -1)
echo "INFO: AT%MODE? -> $ret"

# 模式切换后需要让 USB gadget 重新枚举
# FM350 内部处理，外部只需等待网卡重新出现
echo "OK: mode set to $MODE. Device may need ~5s to re-enumerate."
