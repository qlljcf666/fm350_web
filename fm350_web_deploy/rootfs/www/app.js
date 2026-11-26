/* ============================================================
   FM350 Web Console · FG360 风格前端 JS
   后端: 已有的 shell CGI 不变 (status.sh / dial.sh / mode.sh /
         dhcp.sh / sms.sh / lock.sh / reboot.sh / net.sh)
   ============================================================ */
(function() {
    'use strict';

    var $ = function(id) { return document.getElementById(id); };
    function esc(v) {
        return String(v == null ? '' : v)
            .replace(/&/g,'&amp;').replace(/</g,'&lt;')
            .replace(/>/g,'&gt;').replace(/"/g,'&quot;');
    }
    function setBusy(btn, busy, oldText) {
        if (!btn) return;
        if (busy) { btn.dataset.oldText = btn.textContent; btn.disabled = true; btn.textContent = oldText || '处理中……'; }
        else      { btn.disabled = false; btn.textContent = btn.dataset.oldText || btn.textContent; }
    }

    // ---- 频段表 (FM350 常用) ----
    var NR_BANDS  = [1,3,5,7,8,28,41,77,78,79];
    var LTE_BANDS = [1,3,5,7,8,20,28,38,40,41];

    function renderBandChecks(containerId, bands, isNr) {
        var labelPrefix = isNr ? 'n' : 'B';
        $(containerId).innerHTML = bands.map(function(b) {
            return '<label><input type="checkbox" name="' + containerId + '-check" value="' + b + '"> ' + labelPrefix + b + '</label>';
        }).join('');
    }
    function selectedBands(containerId) {
        return Array.prototype.slice.call(document.querySelectorAll('input[name="' + containerId + '-check"]:checked'))
            .map(function(i) { return parseInt(i.value, 10); });
    }
    function setCheckedBands(containerId, bands) {
        var sel = {};
        (bands || []).forEach(function(b) { sel[String(b)] = true; });
        document.querySelectorAll('input[name="' + containerId + '-check"]').forEach(function(i) { i.checked = !!sel[i.value]; });
    }

    // ---- KV 渲染 ----
    function renderKV(containerId, rows) {
        $(containerId).innerHTML = rows.map(function(r) {
            return '<div><small>' + esc(r[0]) + '</small><strong>' + esc(r[1]) + '</strong></div>';
        }).join('');
    }

    // ---- fetch 封装 ----
    function ft(url, options) {
        return fetch(url, Object.assign({ cache: 'no-store' }, options || {}))
            .then(function(r) { return r.text(); });
    }
    function fj(url) {
        return ft(url).then(function(t) { try { return JSON.parse(t); } catch(e) { return null; } });
    }

    // ============================================================
    //  状态刷新
    // ============================================================
    async function refreshAll() {
        $('status-note').textContent = '正在刷新……';
        await refreshStatus();
        await refreshLockKV();
        await refreshRebootKV();
        refreshSmsKV();
    }

    async function refreshStatus() {
        var d = await fj('/cgi-bin/status.sh');
        var s = await fj('/cgi-bin/sms.sh?action=status');
        if (!d) { $('status-note').textContent = '无法从 FM350 获取状态 (可能设备没启动)'; return; }

        $('status-note').textContent = '最近更新: ' + new Date().toLocaleTimeString();

        // 顶栏总览 KV
        renderKV('current-kv', [
            ['工作模式', (d.mode || '--').toUpperCase()],
            ['拨号状态', d.dial_state || '--'],
            ['上网 IP', d.ip || '--'],
            ['信号 (CSQ)', d.signal ? ('CSQ ' + d.signal) : '--'],
            ['运营商', s && s.operator || '--'],
            ['SIM 状态', s && s.sim || '--'],
            ['AT 工具', s && s.tool || '--'],
            ['AT 端口', s && s.port || '--'],
            ['当前 AT%MODE', d.current_mode || '--']
        ]);

        // 拨号卡
        renderKV('dial-kv', [
            ['当前模式', (d.mode || '--').toUpperCase()],
            ['拨号状态', d.dial_state || '--'],
            ['IP 地址', d.ip || '--']
        ]);

        // DHCP 卡
        var downDev = null;
        (d.ifaces || []).forEach(function(i) { if (i.name === 'usb0' || i.name === 'ccmni0') downDev = i; });
        $('down-iface').textContent = downDev ? (downDev.name + '  (' + (downDev.ip || '无IP') + ')') : '(等待识别 USB/PCIe 网卡)';
        renderKV('dhcp-kv', [
            ['下游网卡', downDev ? downDev.name : '--'],
            ['LAN 网关', '192.168.42.1/24'],
            ['DHCP 范围', '192.168.42.2-254']
        ]);

        // 网卡表
        var tb = document.querySelector('#iface-table tbody');
        if (tb) {
            tb.innerHTML = '';
            (d.ifaces || []).forEach(function(i) {
                if (i.name === 'lo') return;
                var tr = document.createElement('tr');
                tr.innerHTML = '<td>' + esc(i.name) + '</td><td>' + esc(i.mac) + '</td>' +
                    '<td>' + esc(i.state) + '</td><td>' + esc(i.ip || '') + '</td>' +
                    '<td>' + esc(i.speed || '') + '</td>';
                tb.appendChild(tr);
            });
        }
        if (document.querySelector('#iface-table tbody tr')) $('iface-table').classList.remove('fg-hidden');
    }

    async function refreshLockKV() {
        var d = await fj('/cgi-bin/lock.sh?action=status');
        if (!d) return;
        renderKV('lock-kv', [
            ['AT+COPS?', d.cops || '--'],
            ['AT%LOCK?', d.lock || '--'],
            ['AT%CBAND?', d.cband || '--'],
            ['AT%FREQLOCK?', d.freqlock || '--'],
            ['当前运营商', d.operator || '--'],
            ['信号 CSQ', d.csq || '--']
        ]);
        renderKV('freq-kv', [
            ['AT%FREQLOCK?', d.freqlock || '--']
        ]);

        // 频段当前提示
        $('nr-current-note').textContent = '当前 NR 频段: ' + (d.cband || '等待读取……');
        $('lte-current-note').textContent = '当前 LTE 频段: ' + (d.cband || '等待读取……');
    }

    async function refreshRebootKV() {
        var d = await fj('/cgi-bin/reboot.sh?action=status');
        if (!d) return;
        renderKV('reboot-kv', [
            ['定时计划', d.schedule ? d.schedule.split('#')[0].trim() : '(未设置)'],
            ['crond', /crond/i.test(d.crond || '') ? 'running' : 'stopped'],
            ['运行时长', d.uptime || '--']
        ]);
    }

    async function refreshSmsKV() {
        var d = await fj('/cgi-bin/sms.sh?action=status');
        if (!d) return;
        renderKV('sms-kv', [
            ['SIM 状态', d.sim || '--'],
            ['运营商', d.operator || '--'],
            ['信号 CSQ', d.csq ? ('CSQ ' + d.csq) : '--'],
            ['守护进程', d.daemon || '--']
        ]);
    }

    // ============================================================
    //  拨号
    // ============================================================
    async function doDial(a) {
        var apn = $('apn').value || 'internet';
        var out = await ft('/cgi-bin/dial.sh?action=' + a + '&apn=' + encodeURIComponent(apn));
        alert(out); await refreshStatus();
    }

    async function setUsbMode() {
        var mode = $('usb-mode').value;
        if (!confirm('切换 AT%MODE=' + mode + ' 会导致 FM350 USB 重枚举, 继续?')) return;
        var out = await ft('/cgi-bin/mode.sh?mode=' + mode);
        alert(out); await refreshStatus();
    }

    // ============================================================
    //  DHCP
    // ============================================================
    async function doDhcp(a) {
        var out = await ft('/cgi-bin/dhcp.sh?action=' + a);
        if (a === 'status') {
            $('dhcp-out').classList.remove('fg-hidden');
            $('dhcp-out').textContent = out;
        } else {
            $('dhcp-out').classList.remove('fg-hidden');
            $('dhcp-out').textContent = out;
            await refreshStatus();
        }
    }

    // ============================================================
    //  锁网锁频
    // ============================================================
    async function lockNet() {
        var net = $('plmn-custom').value || $('plmn').value;
        if (!net) { alert('请选运营商或填自定义 MCCMNC'); return; }
        var out = await ft('/cgi-bin/lock.sh?action=net&net=' + encodeURIComponent(net));
        alert(out); await refreshLockKV();
    }
    async function unlockNet() {
        var out = await ft('/cgi-bin/lock.sh?action=auto');
        alert(out); await refreshLockKV();
    }
    async function lockFreq() {
        var f = $('freq').value;
        if (!f) { alert('请填 ARFCN'); return; }
        var out = await ft('/cgi-bin/lock.sh?action=freq&freq=' + encodeURIComponent(f));
        alert(out); await refreshLockKV();
    }
    async function unlockFreq() {
        var out = await ft('/cgi-bin/lock.sh?action=freq&freq=0');
        alert(out); await refreshLockKV();
    }

    // ---- 频段应用 ----
    async function applyBands(rat) {
        var bands = selectedBands(rat + '-bands').join(',');
        if (!bands) { alert('请至少选一个频段'); return; }
        var reconnect = $('reconnect').checked ? '1' : '0';
        if ($(rat + '-reconnect')) reconnect = $(rat + '-reconnect').checked ? '1' : '0';
        var url = '/cgi-bin/lock.sh?action=set_bands&rat=' + rat + '&bands=' + encodeURIComponent(bands) + '&reconnect=' + reconnect;
        // 后端 lock.sh 没有 set_bands —— 用 AT%CBAND 代替
        var bandNums = selectedBands(rat + '-bands').join(',');
        var out = await ft('/cgi-bin/lock.sh?action=band&band=' + encodeURIComponent(bandNums));
        alert(out); await refreshLockKV();
    }
    async function restoreBands(rat) {
        var out = await ft('/cgi-bin/lock.sh?action=band&band=0');
        alert(out); await refreshLockKV();
    }

    // ---- 频段 checkbox 全选/清空 ----
    document.addEventListener('click', function(e) {
        var btn = e.target.closest('button[data-select-all], button[data-clear-all]');
        if (!btn) return;
        var rat = btn.dataset.selectAll || btn.dataset.clearAll;
        var checked = btn.dataset.selectAll ? true : false;
        document.querySelectorAll('input[name="' + rat + '-bands-check"]').forEach(function(cb) { cb.checked = checked; });
    });
    // ---- 频段预设按钮 ----
    document.addEventListener('click', function(e) {
        var b = e.target.closest('button[data-freq]');
        if (b) { $('freq').value = b.dataset.freq; return; }
        var r = e.target.closest('button[data-reboot]');
        if (r) { $('reboot-cron').value = r.dataset.reboot; doRebootSet(); return; }
        var a = e.target.closest('button[data-at]');
        if (a) { $('at-command').value = a.dataset.at; return; }
    });

    // ============================================================
    //  定时重启
    // ============================================================
    async function doRebootSet() {
        var cron = $('reboot-cron').value.trim();
        if (!cron) { alert('请填 cron 表达式'); return; }
        var parts = cron.split(/\s+/);
        // 支持 5 段 (分 时 日 月 周) 或 6 段 (含秒)
        if (parts.length === 6) parts.shift(); // 去掉秒
        if (parts.length !== 5) { alert('cron 需要 5 段: 分 时 日 月 周'); return; }
        // day/month/weekday 用 * 作默认
        var m = parts[0], h = parts[1], d = parts[2], mo = parts[3], w = parts[4];
        var out = await ft('/cgi-bin/reboot.sh?action=set&minute=' + encodeURIComponent(m) +
            '&hour=' + encodeURIComponent(h) + '&day=' + encodeURIComponent(d) +
            '&month=' + encodeURIComponent(mo) + '&weekday=' + encodeURIComponent(w));
        alert(out); await refreshRebootKV();
    }
    async function doRebootUnset() {
        var out = await ft('/cgi-bin/reboot.sh?action=unset');
        alert(out); await refreshRebootKV();
    }
    async function doRebootNow() {
        if (!confirm('⚠ 立即重启 FM350? 所有连接会中断')) return;
        var out = await ft('/cgi-bin/reboot.sh?action=now');
        alert(out);
    }

    // ============================================================
    //  短信
    // ============================================================
    async function sendSms() {
        var num = $('sms-num').value.trim();
        var txt = $('sms-text').value;
        if (!num || !txt) { alert('需要手机号和内容'); return; }
        setBusy($('btn-sms-send'), true);
        var out = await ft('/cgi-bin/sms.sh?action=send&num=' + encodeURIComponent(num) +
            '&text=' + encodeURIComponent(txt));
        setBusy($('btn-sms-send'), false, '发送短信');
        alert(out);
        $('sms-text').value = '';
        doSmsList();
    }
    async function doSmsList() {
        setBusy($('btn-sms-list'), true);
        var raw = await ft('/cgi-bin/sms.sh?action=list&filter=ALL');
        setBusy($('btn-sms-list'), false, '刷新短信列表');
        var list = [];
        try { list = JSON.parse(raw); } catch(e) { alert('短信列表解析失败:\n' + raw); return; }
        var tb = document.querySelector('#sms-table tbody');
        tb.innerHTML = '';
        if (!list.length) {
            tb.innerHTML = '<tr><td colspan="5" class="fg-muted" style="text-align:center;padding:12px">(无短信)</td></tr>';
            return;
        }
        list.sort(function(a,b) { return (b.idx||0) - (a.idx||0); });
        list.forEach(function(m) {
            var tr = document.createElement('tr');
            if (String(m.status || '').indexOf('UNREAD') >= 0) tr.classList.add('unread');
            tr.innerHTML = '<td>' + esc(m.idx) + '</td>' +
                '<td>' + esc(m.status) + '</td>' +
                '<td>' + esc(m.addr || '') + '</td>' +
                '<td style="max-width:320px;white-space:normal">' + esc(m.text || '') + '</td>' +
                '<td><button class="cbi-button cbi-button-reset" data-del="' + m.idx + '">删除</button></td>';
            tb.appendChild(tr);
        });
    }
    document.addEventListener('click', async function(e) {
        var d = e.target.closest('button[data-del]');
        if (!d) return;
        if (!confirm('删除 #' + d.dataset.del + '?')) return;
        var out = await ft('/cgi-bin/sms.sh?action=delete&idx=' + encodeURIComponent(d.dataset.del));
        await doSmsList();
    });
    async function deleteAllSms() {
        if (!confirm('⚠ 清空全部短信? 不可恢复')) return;
        var out = await ft('/cgi-bin/sms.sh?action=delete_all');
        alert(out); await doSmsList();
    }

    // ============================================================
    //  AT 命令
    // ============================================================
    async function sendAt() {
        var cmd = $('at-command').value.trim();
        if (!cmd) { alert('请输入 AT 命令'); return; }
        // 安全校验
        if (/^AT\+CGSN=/i.test(cmd) || /EGMR|QIMEI|QNVW|NVWRITE|NVRW|NVITEM|SNWRITE/i.test(cmd)) {
            if (!confirm('⚠ 该命令可能改变设备身份标识, 继续?')) return;
        }
        $('at-output').textContent = '发送中……';
        // 用 net.sh (通用工具里没有 at-send) — 后端没有专门 at-send, 先返回 mock
        // 后端未来可以加 at.sh CGI
        var out = await ft('/cgi-bin/net.sh?cmd=log');  // 先返回日志做占位, 等后端 at 命令 CGI
        $('at-output').textContent = '[待后端添加 at-send CGI]\n\n' + out;
    }

    // ============================================================
    //  事件绑定
    // ============================================================
    // 频段 checkbox
    renderBandChecks('nr-bands',  NR_BANDS,  true);
    renderBandChecks('lte-bands', LTE_BANDS, false);

    // 拨号
    $('refresh-all').addEventListener('click', refreshAll);
    $('refresh-status').addEventListener('click', refreshStatus);
    $('refresh-lock').addEventListener('click', refreshLockKV);
    $('refresh-reboot').addEventListener('click', refreshRebootKV);
    $('refresh-sms').addEventListener('click', function() { refreshSmsKV(); doSmsList(); });

    $('btn-dial').addEventListener('click',   function() { doDial('dial'); });
    $('btn-stop').addEventListener('click',   function() { doDial('stop'); });
    $('btn-redial').addEventListener('click', function() { doDial('redial'); });
    $('btn-set-mode').addEventListener('click', setUsbMode);

    // DHCP
    $('btn-dhcp-start').addEventListener('click',   function() { doDhcp('start'); });
    $('btn-dhcp-stop').addEventListener('click',    function() { doDhcp('stop'); });
    $('btn-dhcp-restart').addEventListener('click', function() { doDhcp('restart'); });
    $('btn-dhcp-lease').addEventListener('click',   function() { doDhcp('status'); });

    // 锁网
    $('btn-lock-net').addEventListener('click', lockNet);
    $('btn-unlock-net').addEventListener('click', unlockNet);

    // 锁频段
    $('btn-set-nr-bands').addEventListener('click',  function() { applyBands('nr'); });
    $('btn-restore-nr').addEventListener('click',    function() { restoreBands('nr'); });
    $('btn-set-lte-bands').addEventListener('click', function() { applyBands('lte'); });
    $('btn-restore-lte').addEventListener('click',   function() { restoreBands('lte'); });

    // 锁频点
    $('btn-lock-freq').addEventListener('click', lockFreq);
    $('btn-unlock-freq').addEventListener('click', unlockFreq);

    // 定时重启
    $('btn-reboot-set').addEventListener('click', doRebootSet);
    $('btn-reboot-unset').addEventListener('click', doRebootUnset);
    $('btn-reboot-now').addEventListener('click', doRebootNow);

    // 短信
    $('btn-sms-send').addEventListener('click', sendSms);
    $('btn-sms-list').addEventListener('click', doSmsList);
    $('btn-sms-delete-all').addEventListener('click', deleteAllSms);

    // AT
    $('btn-send-at').addEventListener('click', sendAt);
    $('btn-clear-at').addEventListener('click', function() { $('at-output').textContent = '已清空'; });
    $('at-command').addEventListener('keydown', function(e) {
        if (e.ctrlKey && e.key === 'Enter') sendAt();
    });

    // ---- 启动 ----
    refreshAll();
    setInterval(refreshStatus, 15000);  // 每 15s 自动刷新网络状态
})();
