net.log("WebhookerLoader called")

local socket = require("socket")
local string = require("string")
local ltn12 = require("ltn12")
local tools = require('tools')
local os = require("os")
local U  = require('me_utilities')

local lfs=require('lfs');
package.path = package.path .. [[;]] .. lfs.writedir() .. [[Mods\Services\Webhooker\core\?.lua;]]

require([[Webhooker_logging]])

WebhookerLoader = {}

--------------------------------------------------------------
-- CALLBACKS

WebhookerLoader.onMissionLoadBegin = function()
  net.log("Calling Webhooker")
	Webhooker.safeCall (
    function() 
      local lfs=require('lfs');
      dofile(lfs.writedir()..[[Mods\Services\Webhooker\core\Webhooker_server.lua]]); 
    end
  )
end

--------------------------------------------------------------
DCS.setUserCallbacks(WebhookerLoader)

