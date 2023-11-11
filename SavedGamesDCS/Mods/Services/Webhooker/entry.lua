--[[
   Copyright 2023 HappyGnome (https://github.com/HappyGnome)

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
--]]

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
		{ name = "Webhooker", nameId = "Webhooker", dir = "options", allow_in_simulation = true; },
	},
	Skins = {
		{ name = "Webhooker", dir = "theme" },
	},
	creditsFile = "credits.txt";
})

plugin_done()