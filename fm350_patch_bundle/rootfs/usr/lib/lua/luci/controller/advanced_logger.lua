module("luci.controller.advanced_logger", package.seeall)

function index()
    entry({"admin", "system", "advanced_logger"}, cbi("advanced_logger"), _("Log Control"), 100)
end