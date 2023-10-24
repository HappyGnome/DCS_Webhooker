net.log("DCS_DiscordLinkLoader called")

local socket = require("socket")
local string = require("string")
local ltn12 = require("ltn12")
local tools = require('tools')
local os = require("os")
local U  = require('me_utilities')

local lfs=require('lfs');
package.path = package.path .. [[;]] .. lfs.writedir() .. [[Mods\Services\DCS_DiscordLink\?.lua;]]

require([[DiscordLink_logging]])

DiscordLinkLoader = {}

--------------------------------------------------------------
-- CALLBACKS

DiscordLinkLoader.onMissionLoadBegin = function()
  net.log("Calling DiscordLink")
  DiscordLink.Logging.log("TODO Test")
	DiscordLink.safeCall (
    function() 
      local lfs=require('lfs');
      dofile(lfs.writedir()..[[Mods\Services\DCS_DiscordLink\DiscordLink_server.lua]]); 
    end
  )
end

--------------------------------------------------------------
DCS.setUserCallbacks(DiscordLinkLoader)

