net.log("DCS_Webhooker Hook called")

local string = require("string")
local tools = require('tools')
local os = require("os")
local U  = require('me_utilities')
local lfs=require('lfs');
package.path = package.path .. [[;]] .. lfs.writedir() .. [[Mods\Services\DCS_Webhooker\?.lua;]]

require("Webhooker_serialization")
require("Webhooker_logging")

if Webhooker == nil then
	Webhooker = {}
elseif  Webhooker.Handlers ~= nil then
	for k,v in pairs(Webhooker.Handlers) do -- Set event handlers to nil when re-including
		Webhooker.Handlers[k] = nil
	end
end

Webhooker.Server = {
	config = 
	{
		directory = lfs.writedir()..[[Logs\]],
		channelEnv = "DcsWebhookerWebhooks",
		userFlagRoot = "Webhooker_",
		framesPerPoll = 600,
		maxArgsPerTemplate = 20
	},

	currentLogFile = nil,
	pollFrameTime = 0,
    webhooks = {},
	templates = {}, -- key = template handle, value = {}
	strings = {},
	players = {},
	funcs = {},
	nextMsgPartId = 1,
	nextMsgIndexToCheck = 0,
	popAgainNextFrame = false,
	worker = nil,

	 -- key = msgPartCat. value = {key = handle, value = id}
	msgPartLookup = {template = {}, string = {}, player = {}, func = {}},

	-- key = id, value = {msgPartCat,handle}
	msgPartRevLookup = {}, 
	msgQueue = {},
	msgRateEpoch = nil,
	msgCountSinceEpoch = nil,

	-- Module constants
	msgPartCat = {template = 1, string = 2, player = 3, func = 4},
	scriptRoot = lfs.writedir()..[[Mods\Services\DCS_Webhooker]],
	scrEnvMission = "mission",
	scrEnvServer = "server"
}

 package.cpath = package.cpath..";"..Webhooker.Server.scriptRoot..[[\LuaWorker\?.dll;]]
 local LuaWorker = nil

--------------------------------------------------------------
-- LOAD C Modules

Webhooker.safeCall(
	function()
		LuaWorker = require("LuaWorker")
		net.log("Loaded LuaWorker")
	end)

-----------------------------------------------------------
-- CONFIG & UTILITY

--[[------------------------------------------
		Load config from file
--]]------------------------------------------
function Webhooker.Server.loadConfiguration()
    Webhooker.Logging.log("Config load starting")
	
    local cfg = tools.safeDoFile(lfs.writedir() .. 'Config/Webhooker.lua', false)
	
    if (cfg and cfg.config) then
		for k,v in pairs(Webhooker.Server.config) do
			if cfg.config[k] ~= nil then
				Webhooker.Server.config[k] = cfg.config[k]
			end
		end        
    end
	
	Webhooker.Server.saveConfiguration()
end

--[[------------------------------------------
		Write current config to file
--]]------------------------------------------
function Webhooker.Server.saveConfiguration()
    U.saveInFile(Webhooker.Server.config, 'config', lfs.writedir()..'Config/Webhooker.lua')
end

--------------------------------------------------------------
-- DEFAULT FUNCTIONS

--[[------------------------------------------
		Function to add integer to template
--]]------------------------------------------
Webhooker.Server.formatInteger = function(pack)
	--TODO tidy
	return pack[1]
end

--[[------------------------------------------
		Add default functions that can be
		called to populate message templates
--]]------------------------------------------
Webhooker.Server.addDefaultFuncs = function()
	local lookup = {}

	Webhooker.Server.funcs.integer = Webhooker.Server.formatInteger

	for k,v in pairs(Webhooker.Server.funcs) do

		local revLookupEntry = {Webhooker.Server.msgPartCat.func,k}
		local existingInd = Webhooker.Server.msgPartLookup.func[k]

		if  existingInd == nil then
			Webhooker.Server.msgPartRevLookup[Webhooker.Server.nextMsgPartId] = revLookupEntry
			lookup[k] = Webhooker.Server.nextMsgPartId
			Webhooker.Server.nextMsgPartId = Webhooker.Server.nextMsgPartId + 1
		else
			Webhooker.Server.msgPartRevLookup[existingInd] = revLookupEntry
			lookup[k] = existingInd
		end
	end
	Webhooker.Server.msgPartLookup.func = lookup
end 

--------------------------------------------------------------
-- LOAD TEMPLATES

--[[------------------------------------------
		Call this from messages scripts
		to install templates
--]]------------------------------------------
Webhooker.Server.addTemplate=function(templateKey,webhookKey,bodyTemplate)
	Webhooker.Server.templates[templateKey] = {
		webhookKey = webhookKey,
		bodyRaw = bodyTemplate
	}
end

--[[------------------------------------------
		Run files from the messages subdir
		to install webhook message templates
--]]------------------------------------------
Webhooker.Server.reloadTemplates = function()
	Webhooker.Server.templates = {}
	local messagesDir = Webhooker.Server.scriptRoot..[[\messages]]

	Webhooker.Logging.log(messagesDir)	
	for fpath in lfs.dir(messagesDir) do

		local fullPath = messagesDir .. "\\" .. fpath
		Webhooker.Logging.log("Found "..fpath)
		Webhooker.Logging.log(lfs.attributes(fullPath,"mode"))

		if lfs.attributes(fullPath,"mode") == "file" then
			Webhooker.Logging.log("Loading ".. fpath)	
			Webhooker.safeCall(dofile,fullPath)		
		end
	end

	local templateLookup = {}
	for k,v in pairs(Webhooker.Server.templates) do

		local existingInd = Webhooker.Server.msgPartLookup.template[k]
		local revLookupEntry = {Webhooker.Server.msgPartCat.template, k}

		if  existingInd == nil then
			Webhooker.Server.msgPartRevLookup[Webhooker.Server.nextMsgPartId] = revLookupEntry
			templateLookup[k] = Webhooker.Server.nextMsgPartId
			Webhooker.Server.nextMsgPartId = Webhooker.Server.nextMsgPartId + 1
		else
			Webhooker.Server.msgPartRevLookup[existingInd] = revLookupEntry
			templateLookup[k] = existingInd
		end
	end
	Webhooker.Server.msgPartLookup.template = templateLookup

	Webhooker.Logging.log(Webhooker.Server.templates)
end

--------------------------------------------------------------
-- PUSH TO MISSION ENVIRONMENT ACTIONS

--[[------------------------------------------
		Push entire message part lookup
		to mission environment
--]]------------------------------------------
Webhooker.Server.pushLookup = function()
	local execString = 
	[[
		a_do_script(
		[=[ -- Executed in mission scripting environment
			if Webhooker == nil then Webhooker = {} end 
			Webhooker.msgPartLookup =
	]]

	execString = execString .. Webhooker.Serialization.obj2str(Webhooker.Server.msgPartLookup)

	execString = execString .. [[]=])]]

	Webhooker.Logging.log(execString)
	net.dostring_in(Webhooker.Server.scrEnvMission, execString)
	Webhooker.Logging.log("All lookup pushed")
end

--[[------------------------------------------
		Push single message part category
		to mission environment
--]]------------------------------------------
Webhooker.Server.pushLookupPart = function(msgPartCat)
	local execString = 
	[[
		a_do_script(
		[=[ -- Executed in mission scripting environment
			if Webhooker == nil then Webhooker = {} end 
			Webhooker.msgPartLookup["]] .. msgPartCat .. [["] = 
	]]

	execString = execString .. Webhooker.Serialization.obj2str(Webhooker.Server.msgPartLookup[msgPartCat])

	execString = execString .. [[]=])]]

	Webhooker.Logging.log(execString)
	net.dostring_in(Webhooker.Server.scrEnvMission, execString)
	Webhooker.Logging.log(msgPartCat .. " lookup pushed")
end

--[[------------------------------------------
		Push config to mission environment
--]]------------------------------------------
Webhooker.Server.pushConfig = function()
	local execString = 
	[[
		a_do_script(
		[=[ -- Executed in mission scripting environment
			if Webhooker == nil then Webhooker = {} end 
			Webhooker.config = 
	]]

	execString = execString .. Webhooker.Serialization.obj2str(Webhooker.Server.config)

	execString = execString .. [[]=])]]

	Webhooker.Logging.log(execString)
	net.dostring_in(Webhooker.Server.scrEnvMission, execString)
	Webhooker.Logging.log("Config pushed")
end

--------------------------------------------------------------
-- POP MESSAGES

--[[------------------------------------------
		Pop messages from mission scripting
		environment, and send
--]]------------------------------------------
Webhooker.Server.popMessage = function()

	Webhooker.Server.nextMsgIndexToCheck = Webhooker.Server.nextMsgIndexToCheck + 1

	local ret = nil

	local userFlag = Webhooker.Server.config.userFlagRoot..Webhooker.Server.nextMsgIndexToCheck
	local execString = 
	[[
		-- Executed in server mission scripting environment
		return(trigger.misc.getUserFlag("]]..userFlag..[["))
	]]

	local flagValRaw = net.dostring_in(Webhooker.Server.scrEnvServer, execString)

	local flagVal = tonumber(flagValRaw)

	if flagVal == nil or flagVal == 0 then -- 0 used for boolean false (end of messages)
		Webhooker.Server.nextMsgIndexToCheck = 0
		return
	elseif flagVal ~= 1 then -- 1 used for boolean true (skip message)

		local templateKey = Webhooker.Server.msgPartRevLookup[flagVal]

		if templateKey ~= nil and templateKey[1] == Webhooker.Server.msgPartCat.template then
			ret =	{
				template = templateKey[2], 
				args = Webhooker.Server.popMessageRecurse(userFlag,1)
			}
		else
			Webhooker.Logging.log("Invalid template handle: " .. flagVal)
		end
	
		-- clear flag
		execString = 
		[[
			-- Executed in server mission scripting environment
			trigger.action.setUserFlag("]]..userFlag..[[",true)
		]]
	
		net.dostring_in(Webhooker.Server.scrEnvServer, execString)
	end

	return ret

end

--[[------------------------------------------
		Pop message arguments
--]]------------------------------------------
Webhooker.Server.popMessageRecurse = function(userFlagRoot,recurseLevel)
	local ret = nil
	if recurseLevel > 4 then return ret end

	local i = 1
	while i < Webhooker.Server.config.maxArgsPerTemplate do

		local userFlag = userFlagRoot.."_"..i
		local execString = 
		[[
			-- Executed in server mission scripting environment
			return(trigger.misc.getUserFlag("]]..userFlag..[["))
		]]
	
		local flagRaw = net.dostring_in(Webhooker.Server.scrEnvServer, execString)

		local flagVal = tonumber(flagRaw)
		if flagVal == nil or flagVal == 0  or flagVal == 1 then 
			break 
		elseif flagVal > 0 then
			flagVal = flagVal - 2
		end
		
		if not ret then ret = {} end

		local args = Webhooker.Server.popMessageRecurse(userFlag,recurseLevel+1)
		ret[#ret + 1] = {
			handle = flagVal,
			args = args
		}

		-- clear flag
		execString = 
		[[
			-- Executed in server mission scripting environment
			trigger.action.setUserFlag("]]..userFlag..[[",true)
		]]

		net.dostring_in(Webhooker.Server.scrEnvServer, execString)

		i = i + 1
	end

	return ret
end


--------------------------------------------------------------
-- MAIN LOOP LOGIC

--[[------------------------------------------
		Queue message in worker thread
--]]------------------------------------------
Webhooker.Server.trySendToWebhook = function (webhook,templateRaw, templateArgs)

    if Webhooker.Server.webhooks[webhook] == nil then
        Webhooker.Logging.log("Webhook "..webhook.." not found")
        return false
	elseif templateRaw == nil then
		Webhooker.Logging.log("Missing template for call to webhook "..webhook)
        return false
    end
	Webhooker.Server.ensureLuaWorker()

	Webhooker.Server.worker:DoCoroutine(
		[[Webhooker.Worker.CallAndRetry]], 
		Webhooker.Serialization.obj2str({
			templateRaw = templateRaw,
			templateArgs = templateArgs,
			webhook = Webhooker.Server.webhooks[webhook]
		}))

	return true
end

--[[------------------------------------------
		popAndSendOne
--]]------------------------------------------
Webhooker.Server.popAndSendOne = function ()

    local msgData = Webhooker.Server.popMessage()

	if msgData == nil then return false end

	if Webhooker.Server.nextMsgIndexToCheck > 0 then
		Webhooker.Server.popAgainNextFrame = true
	end

	local template = Webhooker.Server.templates[msgData.template]

	if template == nil then
		Webhooker.Logging.log("Template not found: " .. template)
		return false
	end 

	local templateArgs = {}

	if msgData.args ~= nil then
		for i,arg in ipairs(msgData.args) do
			templateArgs[i] = Webhooker.Server.msgArgToString(arg.handle, arg.args) 
		end
	end

	Webhooker.Server.trySendToWebhook(template.webhookKey,template.bodyRaw, templateArgs)

	
end

--[[------------------------------------------
		Convert message arg pack to 
		replacement string
--]]------------------------------------------
Webhooker.Server.msgArgToString = function (handle, msgArg)

	local handleVal = Webhooker.Server.msgPartRevLookup[handle]

	if handleVal == nil or #handleVal < 2 then
		Webhooker.Logging.log("Unrecognised message part handle: " .. handle)
		return nil
	end

	if handleVal[1] == Webhooker.Server.msgPartCat.string then
		return Webhooker.strings[handleVal[2]]
	elseif handleVal[1] == Webhooker.Server.msgPartCat.player then
		return Webhooker.Server.players[handleVal[2]]
	elseif handleVal[1] == Webhooker.Server.msgPartCat.func then
		return Webhooker.Server.funcs[handleVal[2]](msgArg)
	else
		Webhooker.Logging.log("Unrecognised message part type " .. handleVal[1] .. " for handle "..handle)
		Webhooker.Logging.log({"Webhooker.Server.msgPartRevLookup:", Webhooker.Server.msgPartRevLookup})
		return nil
	end	
end
--------------------------------------------------------------
-- LUA WORKER SETUP

--[[------------------------------------------
		Start lua worker thread if it's 
		not running/starting
--]]------------------------------------------
Webhooker.Server.ensureLuaWorker = function()

	if Webhooker.Server.worker ~= nil then
		local status = Webhooker.Server.worker:Status()

		if status == LuaWorker.WorkerStatus.Starting 
			or status == LuaWorker.WorkerStatus.Processing then
			return
		else
			for i = 1,100 do
				local s = worker:PopLogLine()
				if s == nil then break end
				Webhooker.Logging.log(s)		
			end
		end
	end

	Webhooker.Server.worker = LuaWorker.Create()
	Webhooker.Server.worker:Start()
	Webhooker.Server.worker:DoString("package.cpath = [[" .. package.cpath .. ";"..Webhooker.Server.scriptRoot..[[\https\?.dll;]] .. "]]")
	Webhooker.Server.worker:DoString("package.path = [[" .. package.path .. ";"..Webhooker.Server.scriptRoot..[[\https\?.lua;]] .. "]]")
	--Webhooker.Server.worker:DoString("scriptRoot = [[" .. Webhooker.Server.scriptRoot .. "]]")
	Webhooker.Server.worker:DoFile(Webhooker.Server.scriptRoot .. [[\Webhooker_worker_init.lua]])
end

--------------------------------------------------------------
-- CALLBACKS

Webhooker.Handlers = {}

--[[------------------------------------------
		onMissionLoadBegin
--]]------------------------------------------
Webhooker.Handlers.onMissionLoadBegin = function()
	--if not DCS.isServer() or not DCS.isMultiplayer() then return end --TODO
	Webhooker.safeCall(Webhooker.Handlers.doOnMissionLoadBegin)
end

--[[------------------------------------------
		doOnMissionLoadBegin
--]]------------------------------------------
Webhooker.Handlers.doOnMissionLoadBegin = function()
	Webhooker.Server.loadConfiguration()
	local log_file_name = 'DCS_Webhooker.Logging.log'
	
	local fulldir = Webhooker.Server.config.directory.."\\"
	
	Webhooker.Server.currentLogFile = io.open(fulldir .. log_file_name, "w")
	Webhooker.Logging.log("Mission "..DCS.getMissionName().." loading",Webhooker.Server.currentLogFile)

end

--[[------------------------------------------
		onMissionLoadBegin
--]]------------------------------------------
Webhooker.Handlers.onMissionLoadEnd = function()
	--if not DCS.isServer() or not DCS.isMultiplayer() then return end --TODO
	Webhooker.safeCall(Webhooker.Handlers.doOnMissionLoadEnd)
end

--[[------------------------------------------
		doOnMissionLoadEnd
--]]------------------------------------------
Webhooker.Handlers.doOnMissionLoadEnd = function()
	Webhooker.Logging.log("Mission "..DCS.getMissionName().." loaded",Webhooker.Server.currentLogFile)
	
end

--[[------------------------------------------
		onPlayerConnect
--]]------------------------------------------
Webhooker.Handlers.onPlayerConnect = function(id)
	--if not DCS.isServer() or not DCS.isMultiplayer() then return end
	Webhooker.safeCall(Webhooker.Handlers.doOnPlayerConnect,id)
end

--[[------------------------------------------
		doOnPlayerConnect
--]]------------------------------------------
Webhooker.Handlers.doOnPlayerConnect = function(id)
	local name = Webhooker.Server.getPlayerName(id)
	--local ucid = Webhooker.Server.getPlayerUcid(id)
	
	Webhooker.Server.players[name] = name

	local existingInd = Webhooker.Server.msgPartLookup.player[name]
	local revLookupEntry = {Webhooker.Server.msgPartCat.player, name}

	if  existingInd == nil then
		Webhooker.Server.msgPartRevLookup[Webhooker.Server.nextMsgPartId] = revLookupEntry
		Webhooker.Server.msgPartLookup.player[name] = Webhooker.Server.nextMsgPartId
		Webhooker.Server.nextMsgPartId = Webhooker.Server.nextMsgPartId + 1
	end

	Webhooker.Server.pushLookupPart("player")

	Webhooker.Logging.log("Player ".. name .. " added")
end

--[[------------------------------------------
		onSimulationStop
--]]------------------------------------------
Webhooker.Handlers.onSimulationStop = function()
	--if not DCS.isServer() or not DCS.isMultiplayer() then return end
	Webhooker.safeCall(Webhooker.Handlers.doOnSimulationStop)
end

--[[------------------------------------------
		doOnSimulationStop
--]]------------------------------------------
Webhooker.Handlers.doOnSimulationStop = function()

	if Webhooker.Server.worker ~= nil then
		Webhooker.Server.worker:Stop()	

		for i = 1,100 do
			local s = Webhooker.Server.worker.PopLogLine()
			if s == nil then break end
			Webhooker.Logging.log(s)		
		end
	end
end

--[[------------------------------------------
		onSimulationStart
--]]------------------------------------------
Webhooker.Handlers.onSimulationStart = function()
	--if not DCS.isServer() or not DCS.isMultiplayer() then return end
	Webhooker.safeCall(Webhooker.Handlers.doOnSimulationStart)
end

--[[------------------------------------------
		doOnSimulationStart
--]]------------------------------------------
Webhooker.Handlers.doOnSimulationStart = function()
	Webhooker.Server.reloadTemplates()
	Webhooker.Server.pushLookup()
	Webhooker.Logging.log(net.get_player_list())

	Webhooker.Server.ensureLuaWorker()
end

--[[------------------------------------------
		onSimulationFrame
--]]------------------------------------------
Webhooker.Handlers.onSimulationFrame = function()
	if Webhooker.Server.pollFrameTime > Webhooker.Server.config.framesPerPoll 
		or Webhooker.Server.popAgainNextFrame then
		--if not DCS.isServer() or not DCS.isMultiplayer() then return end -- TODO Test

		if Webhooker.Server.pollFrameTime > Webhooker.Server.config.framesPerPoll then
			Webhooker.Server.pollFrameTime = 0
		end
		
		Webhooker.Server.popAgainNextFrame = false

		Webhooker.safeCall(Webhooker.Server.popAndSendOne)

		return
	elseif Webhooker.Server.pollFrameTime == 111 and Webhooker.Server.worker ~= nil then 
		-- Spread work between frames (avoid round numbers)
		for i = 1,100 do
			local s = Webhooker.Server.worker:PopLogLine() 
			if s == nil then break end
			Webhooker.Logging.log(s)		
		end
	end

	Webhooker.Server.pollFrameTime = Webhooker.Server.pollFrameTime + 1
end

--------------------------------------------------------------
-- INIT METHOD CALLS
--------------------------------------------------------------

--[[-------------------------------------------------
		Get connection strings
--]]-------------------------------------------------
Webhooker.safeCall(
    function()
        local envVar = os.getenv(Webhooker.Server.config.channelEnv)
        if envVar == nil then return end

        for k,v in string.gmatch(envVar,"([^;]+)=([^;]+);?") do
            --Webhooker.Logging.log(k.." "..v)
            Webhooker.Server.webhooks[k] = v
        end
    end)

--[[-------------------------------------------------
		Add default functions to be called
		to populate template
--]]-------------------------------------------------
Webhooker.Server.addDefaultFuncs()

--[[-------------------------------------------------
		Register callbacks
--]]-------------------------------------------------
DCS.setUserCallbacks(Webhooker.Handlers)

Webhooker.Logging.log("TODO In Server")

