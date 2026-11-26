module("luci.controller.admin.telephony", package.seeall)

function index()
  entry({"admin", "telephony"}, firstchild(), "Telephony", 60).dependent=false
  entry({"admin", "telephony", "overview"}, template("admin_telephony/overview"), _("Overview"), 1)
  --entry({"admin", "telephony", "trigger_sim_unlock"}, template("admin_telephony/trigger_sim_unlock"), nil, nil)
  entry({"admin", "telephony", "trigger_sim_unlock"}, call("action_unlock_sim"), nil, nil)
  entry({"admin", "telephony", "trigger_change_nw_radio"}, template("admin_telephony/trigger_change_nw_radio"), nil, nil)
  entry({"admin", "telephony", "trigger_set_nw_rat_2g"}, template("admin_telephony/trigger_set_nw_rat_2g"), nil, nil)
  entry({"admin", "telephony", "trigger_set_nw_rat_3g"}, template("admin_telephony/trigger_set_nw_rat_3g"), nil, nil)
  entry({"admin", "telephony", "trigger_set_nw_rat_4g"}, template("admin_telephony/trigger_set_nw_rat_4g"), nil, nil)
  entry({"admin", "telephony", "trigger_set_nw_rat_5g"}, template("admin_telephony/trigger_set_nw_rat_5g"), nil, nil)
  entry({"admin", "telephony", "trigger_set_nw_rat_45g"}, template("admin_telephony/trigger_set_nw_rat_45g"), nil, nil)
  entry({"admin", "telephony", "trigger_set_nw_rat_345g"}, template("admin_telephony/trigger_set_nw_rat_345g"), nil, nil)
  entry({"admin", "telephony", "trigger_set_nw_rat"}, call("action_set_rat_mode"), nil, nil)
  entry({"admin", "telephony", "trigger_set_radio_on_with_ia"}, call("action_radio_on_with_ia_apn"), nil, nil)
  entry({"admin", "telephony", "trigger_set_radio_on"}, template("admin_telephony/trigger_set_radio_on"), nil, nil)
  entry({"admin", "telephony", "trigger_set_radio_off"}, template("admin_telephony/trigger_set_radio_off"), nil, nil)
  entry({"admin", "telephony", "trigger_set_ims_on_with_apn"}, call("action_ims_on_with_apn"), nil, nil)
  entry({"admin", "telephony", "trigger_set_ims_on"}, template("admin_telephony/trigger_set_ims_on"), nil, nil)
  entry({"admin", "telephony", "trigger_set_ims_off"}, template("admin_telephony/trigger_set_ims_off"), nil, nil)
  entry({"admin", "telephony", "trigger_call_get_call_status"}, template("admin_telephony/trigger_call_get_call_status"), nil, nil)
  --entry({"admin", "telephony", "trigger_call_dial_constant"}, template("admin_telephony/trigger_call_dial_constant"), nil, nil)
  entry({"admin", "telephony", "trigger_call_dial_constant"}, call("action_dial_call"), nil, nil)
  entry({"admin", "telephony", "trigger_call_detect_and_dial"}, template("admin_telephony/trigger_call_detect_and_dial"), nil, nil)
  entry({"admin", "telephony", "trigger_call_dtmf"}, template("admin_telephony/trigger_call_dtmf"), nil, nil)
  entry({"admin", "telephony", "trigger_call_accept_ringing"}, template("admin_telephony/trigger_call_accept_ringing"), nil, nil)
  entry({"admin", "telephony", "trigger_call_accept_waiting"}, template("admin_telephony/trigger_call_accept_waiting"), nil, nil)
  entry({"admin", "telephony", "trigger_call_swap"}, template("admin_telephony/trigger_call_swap"), nil, nil)
  entry({"admin", "telephony", "trigger_call_merge"}, template("admin_telephony/trigger_call_merge"), nil, nil)
  entry({"admin", "telephony", "trigger_call_play_tone"}, template("admin_telephony/trigger_call_play_tone"), nil, nil)
  entry({"admin", "telephony", "trigger_call_mute"}, template("admin_telephony/trigger_call_mute"), nil, nil)
  entry({"admin", "telephony", "trigger_call_unmute"}, template("admin_telephony/trigger_call_unmute"), nil, nil)
  entry({"admin", "telephony", "trigger_call_set_volume"}, call("action_set_volume"), nil, nil)
  entry({"admin", "telephony", "trigger_call_hangup_all"}, template("admin_telephony/trigger_call_hangup_all"), nil, nil)
  entry({"admin", "telephony", "trigger_call_hangup_foreground"}, template("admin_telephony/trigger_call_hangup_foreground"), nil, nil)
  entry({"admin", "telephony", "trigger_call_speech_on"}, template("admin_telephony/trigger_call_speech_on"), nil, nil)
  entry({"admin", "telephony", "trigger_call_speech_off"}, template("admin_telephony/trigger_call_speech_off"), nil, nil)
end

function action_unlock_sim()
	--load htm contect
	luci.template.render("admin_telephony/trigger_sim_unlock", {})
	--Read input SIM pin
	local pin = luci.http.formvalue("pin")
	if pin then
		if luci.http.formvalue("unlock") then
			local command = string.format("mipc_wan_cli --sim_verify_pin \"%s\"", pin)
			luci.sys.exec(command)
		end
	end
end

function action_set_rat_mode()
	--load htm contect
	luci.template.render("admin_telephony/trigger_set_nw_rat", {})
	--Read input SIM pin
	local ratMode = luci.http.formvalue("ratMode")
	if ratMode then
		if luci.http.formvalue("Set") then
			local command = string.format("mipc_wan_cli --nw_set_rat \"%s\"", ratMode)
			luci.sys.exec(command)
		end
	end
end

function action_radio_on_with_ia_apn()
	--load htm contect
	luci.template.render("admin_telephony/trigger_set_radio_on_with_ia", {})
	--Read ia apn
	local ia = luci.http.formvalue("ia")
	if ia then
		if luci.http.formvalue("ia_apn") then
			local command = string.format("mtk_ia \"%s\"", ia)
			luci.sys.exec(command)
		end
	end
end

function action_ims_on_with_apn()
	--load htm contect
	luci.template.render("admin_telephony/trigger_set_ims_on_with_apn", {})
	--Read ia apn
	local ims_apn = luci.http.formvalue("ims_apn")
	if ims_apn then
		if luci.http.formvalue("ims_cfg_on") then
			local command = string.format("mipc_wan_cli --apn_profile_set %s", ims_apn)
            luci.sys.exec(command)
            local command1 = string.format("mipc_wan_cli --nw_radio_state_set 0")
            luci.sys.exec(command1)
            local command2 = string.format("mipc_wan_cli --at_cmd AT+CIREG=2")
            luci.sys.exec(command2)
            local command3 = string.format("mipc_wan_cli --nw_radio_state_set 1")
            luci.sys.exec(command3)
            local command4 = string.format("mipc_wan_cli --ims_set_config 3")
            luci.sys.exec(command4)
		end
	end
end

function action_dial_call()
	--load htm contect
	luci.template.render("admin_telephony/trigger_call_dial_constant", {})
	--Read input number
	local dialNumber = luci.http.formvalue("dialNumber")
	if dialNumber then
		if luci.http.formvalue("Dial") then
			local command = string.format("mipc_wan_cli --dial_request=\"%s\"", dialNumber)
			luci.sys.exec(command)
		end
	end
end

function action_set_volume()
	--load htm contect
	luci.template.render("admin_telephony/trigger_call_set_volume", {})
	--Read input value
	local volume = luci.http.formvalue("volume")
	if volume then
		if luci.http.formvalue("set_volume") then
			local command = string.format("amixer -D mtk_phonecall cset numid=3 %s", volume)
			luci.sys.exec(command)
		end
	end
end
