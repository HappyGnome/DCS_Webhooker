declare_plugin("Webhooker for DCS by HappyGnome", {
	installed = true,
	dirName = current_mod_path,
	developerName = _("HappyGnome"),
	developerLink = _("https://github.com/HappyGnome/DCS_Webhooker"),
	displayName = _("Webhooker"),
	version = "1.0.0",
	state = "installed",
	info = _(""),
	binaries = {},
    load_immediate = true,
	Options = {
		{ name = "DCS_Webhooker", nameId = "DCS_Webhooker", dir = "options", allow_in_simulation = true; },
	},
	Skins = {
		{ name = "DCS_Webhooker", dir = "theme" },
	},
	creditsFile = "credits.txt";
})

plugin_done()