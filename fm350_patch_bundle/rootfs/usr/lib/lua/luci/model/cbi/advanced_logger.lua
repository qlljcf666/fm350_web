local sys   = require "luci.sys"
local zones = require "luci.sys.zoneinfo"
local fs    = require "nixio.fs"
local conf  = require "luci.config"

local m, s, o

m = Map("system", translate("Log Control"), translate("Here you can configure the log properties e.g. maximum record file number, log start/stop control ...etc ."))
m:chain("luci")


s = m:section(TypedSection, "system", translate("Advanced System Properties"))
s.anonymous = true
s.addremove = false

--
-- Advanced System Properties
--

o = s:option(ListValue, "ap_start", translate("Start or Stop AP log"))
o:value(0, translate("stop"))
o:value(1, translate("start"))

o = s:option(ListValue, "gps_start", translate("Start or Stop GPS log"))
o:value(0, translate("stop"))
o:value(1, translate("start"))

o = s:option(ListValue, "net_start", translate("Start or Stop tcpdump"))
o:value(0, translate("stop"))
o:value(1, translate("start"))

o = s:option(ListValue, "md_start", translate("Start or Stop MD log"))
o:value(0, translate("stop"))
o:value(1, translate("start"))

o = s:option(Value, "log_store_path", translate("Log store path"))
o.placeholder = "/data/debuglog"

o = s:option(ListValue, "enable_sensitive_log", translate("Enable sensitive log in AP and MD side"))
o:value(0, translate("disable"))
o:value(1, translate("enable"))

o = s:option(ListValue, "ap_auto_logging", translate("Auto start logging or not"))
o:value(0, translate("stop"))
o:value(1, translate("start"))

o = s:option(ListValue, "ap_save_mode", translate("AP log saving mode"))
o:value(0, translate("overwrite"))
o:value(1, translate("create new file"))

o = s:option(Value, "ap_max_files", translate("AP log maximum saving files per time"),"maximum file count must be larger than 2")
o.placeholder = 16

o = s:option(Value, "ap_max_bootlog_folders", translate("AP boot log maximum keeping numbers"),"maximum numbers count must be larger than 5")
o.placeholder = 16

o = s:option(ListValue, "md_save_mode", translate("MD log saving mode"))
o:value(0, translate("do nothing"))
o:value(1, translate("USB"))
o:value(2, translate("internal storage"))
o:value(3, translate("PLS (MD ring buffer)"))
o:value(4, translate("Over Ethernet"))

o = s:option(ListValue, "md_gps_location_log_enable", translate("Enable Location log in MD"))
o:value(0, translate("disable"))
o:value(1, translate("enable"))

o = s:option(ListValue, "md_dumpback_mode", translate("MD dumpback mode"))
o:value(0, translate("normal dump"))
o:value(1, translate("subsystem dump"))
o:value(2, translate("mini dump"))
o:value(1, translate("selected dump"))

o = s:option(ListValue, "md_level", translate("MD log level"))
o:value(8, translate("Debug"))
o:value(7, translate("Info"))
o:value(6, translate("Notice"))
o:value(5, translate("Warning"))
o:value(4, translate("Error"))
o:value(3, translate("Critical"))
o:value(2, translate("Alert"))
o:value(1, translate("Emergency"))

o = s:option(Value, "md_log_size", translate("MD log file size"),"unit:MB and file size should larger than 20MB")
o.placeholder = 16

o = s:option(Value, "md_cyclic_size", translate("The maximum MD log size"),"It will replace oldest log when reaching maximum size")
o.placeholder = 16

o = s:option(Value, "md_memdump_wait_time", translate("MD memory dump wait time"),"If you save & apply new value, then a reboot will be required")
o.placeholder = 16

o = s:option(Value, "md_log_ip", translate("MD Log IP Address"),"Specify MD Log IP address")
o.datatype = "ip4addr"
o.placeholder = "0.0.0.0"
o.default = "0.0.0.0"

o = s:option(Value, "md_log_port", translate("MD Log Port"),"Specify MD Log Port")
o.datatype = "portrange"
o.placeholder = "0-65535"
o.default = 10001

o = s:option(Value, "snaplen", translate("tcpdump snaplen"), translate("Specify the number of bytes to be captured by tcpdump"))
o.datatype = "and(uinteger, min(16), max(9000))"
o.placeholder = "16-9000"
o.default = 128
o.addremove = false
o.optional = false

local apply = luci.http.formvalue("cbi.apply")
if apply then
    io.popen("/etc/init.d/log_controld reload")
end

return m
