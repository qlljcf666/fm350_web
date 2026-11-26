fm350web/                               ← Gitee 根
├── fm350_patch_bundle/                 LuCI 补齐包 (503 文件, 7.9 MB)
│   ├── 一键补齐.bat                    ✅ CRLF + UTF-8 BOM + chcp 65001
│   ├── deploy.sh                       bash ADB 部署脚本
│   ├── gen_lmo.py                      .lmo 翻译生成器
│   ├── README.md                       完整部署文档
│   └── rootfs/                         推送目标目录 (原结构)
│       ├── etc/                        init.d + config + firewall.user
│       ├── lib/netifd/proto/
│       ├── sbin/                       fw3 (117 KB) + rpcd
│       ├── usr/bin/                    openssl + ssh-keygen
│       ├── usr/lib/lua/luci/           LuCI 312 Lua 文件 + 53 zh-cn.lmo
│       ├── usr/sbin/                   dnsmasq/dropbear/uhttpd/pppd/...
│       └── www/                        LuCI bootstrap 前端 (131 文件)
│
├── fm350_web_deploy/                   FM350 原生 Web 控制台
│   ├── 350一键部署.bat                 ✅ CRLF + UTF-8 BOM + chcp 65001
│   ├── deploy.sh
│   ├── README.md
│   └── rootfs/
│       ├── etc/gcom/*.gcom + init.d/fm350_web
│       ├── lib/netifd/proto/fm350.sh
│       ├── usr/bin/at_helper.sh + fm350_{dial,sms,lock,reboot}.sh
│       └── www/                        FG360 CBI 风格前端
│           ├── index.html              单页卡片网格布局
│           ├── style.css               LuCI CBI 样式系统
│           ├── app.js                  动态渲染 + 15s 轮询
│           └── cgi-bin/*.sh            8 个 shell CGI
│
├── luci-app-fg360-lock_ipk_1.1.0-1.ipk
├── luci-app-fg360-lock_source_1.1.0-1.zip
├── .gitattributes                      行尾保护 (.sh/.py/.lua=LF, .bat=CRLF)
└── .gitignore