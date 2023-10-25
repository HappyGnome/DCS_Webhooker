net.log("DCS_DiscordLink Hook called")

local string = require("string")
local tools = require('tools')
local os = require("os")
local U  = require('me_utilities')
local lfs=require('lfs');
package.path = package.path .. [[;]] .. lfs.writedir() .. [[Mods\Services\DCS_DiscordLink\?.lua;]]

require("DiscordLink_serialization")
require("DiscordLink_logging")

if DiscordLink == nil then
	DiscordLink = {}
elseif  DiscordLink.Handlers ~= nil then
	for k,v in pairs(DiscordLink.Handlers) do -- Set event handlers to nil when re-including
		DiscordLink.Handlers[k] = nil
	end
end

DiscordLink.Server = {
	config = 
	{
		directory = lfs.writedir()..[[Logs\]],
		channelEnv = "DcsDiscordLinkWebhooks",
		userFlagRoot = "DiscordLink_",
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
	scriptRoot = lfs.writedir()..[[Mods\Services\DCS_DiscordLink]],
	webhookPrefix = "https://discord.com/api/webhooks/",
	scrEnvMission = "mission",
	scrEnvServer = "server"
}

 package.cpath = package.cpath..";"..DiscordLink.Server.scriptRoot..[[\LuaWorker\?.dll;]]
 local LuaWorker = nil

--------------------------------------------------------------
-- LOAD C Modules

DiscordLink.safeCall(
	function()
		LuaWorker = require("LuaWorker")
		net.log("Loaded LuaWorker")
	end)

-----------------------------------------------------------
-- CONFIG & UTILITY

--[[------------------------------------------
		Load config from file
--]]------------------------------------------
function DiscordLink.Server.loadConfiguration()
    DiscordLink.Logging.log("Config load starting")
	
    local cfg = tools.safeDoFile(lfs.writedir() .. 'Config/DiscordLink.lua', false)
	
    if (cfg and cfg.config) then
		for k,v in pairs(DiscordLink.Server.config) do
			if cfg.config[k] ~= nil then
				DiscordLink.Server.config[k] = cfg.config[k]
			end
		end        
    end
	
	DiscordLink.Server.saveConfiguration()
end

--[[------------------------------------------
		Write current config to file
--]]------------------------------------------
function DiscordLink.Server.saveConfiguration()
    U.saveInFile(DiscordLink.Server.config, 'config', lfs.writedir()..'Config/DiscordLink.lua')
end

--------------------------------------------------------------
-- DEFAULT FUNCTIONS

--[[------------------------------------------
		Function to add integer to template
--]]------------------------------------------
DiscordLink.Server.formatInteger = function(pack)
	--TODO tidy
	return pack[1]
end

--[[------------------------------------------
		Add default functions that can be
		called to populate message templates
--]]------------------------------------------
DiscordLink.Server.addDefaultFuncs = function()
	local lookup = {}

	DiscordLink.Server.funcs.integer = DiscordLink.Server.formatInteger

	for k,v in pairs(DiscordLink.Server.funcs) do

		local revLookupEntry = {DiscordLink.Server.msgPartCat.func,k}
		local existingInd = DiscordLink.Server.msgPartLookup.func[k]

		if  existingInd == nil then
			DiscordLink.Server.msgPartRevLookup[DiscordLink.Server.nextMsgPartId] = revLookupEntry
			lookup[k] = DiscordLink.Server.nextMsgPartId
			DiscordLink.Server.nextMsgPartId = DiscordLink.Server.nextMsgPartId + 1
		else
			DiscordLink.Server.msgPartRevLookup[existingInd] = revLookupEntry
			lookup[k] = existingInd
		end
	end
	DiscordLink.Server.msgPartLookup.func = lookup
end 

--------------------------------------------------------------
-- LOAD TEMPLATES

--[[------------------------------------------
		Call this from messages scripts
		to install templates
--]]------------------------------------------
DiscordLink.Server.addTemplate=function(templateKey,webhookKey,username,content)
	DiscordLink.Server.templates[templateKey] = {
		webhookKey = webhookKey,
		username = username,
		content = content
	}
end

--[[------------------------------------------
		Run files from the messages subdir
		to install webhook message templates
--]]------------------------------------------
DiscordLink.Server.reloadTemplates = function()
	DiscordLink.Server.templates = {}
	local messagesDir = DiscordLink.Server.scriptRoot..[[\messages]]

	DiscordLink.Logging.log(messagesDir)	
	for fpath in lfs.dir(messagesDir) do

		local fullPath = messagesDir .. "\\" .. fpath
		DiscordLink.Logging.log("Found "..fpath)
		DiscordLink.Logging.log(lfs.attributes(fullPath,"mode"))

		if lfs.attributes(fullPath,"mode") == "file" then
			DiscordLink.Logging.log("Loading ".. fpath)	
			DiscordLink.safeCall(dofile,fullPath)		
		end
	end

	local templateLookup = {}
	for k,v in pairs(DiscordLink.Server.templates) do

		local existingInd = DiscordLink.Server.msgPartLookup.template[k]
		local revLookupEntry = {DiscordLink.Server.msgPartCat.template, k}

		if  existingInd == nil then
			DiscordLink.Server.msgPartRevLookup[DiscordLink.Server.nextMsgPartId] = revLookupEntry
			templateLookup[k] = DiscordLink.Server.nextMsgPartId
			DiscordLink.Server.nextMsgPartId = DiscordLink.Server.nextMsgPartId + 1
		else
			DiscordLink.Server.msgPartRevLookup[existingInd] = revLookupEntry
			templateLookup[k] = existingInd
		end
	end
	DiscordLink.Server.msgPartLookup.template = templateLookup

	DiscordLink.Logging.log(DiscordLink.Server.templates)
end

--------------------------------------------------------------
-- PUSH TO MISSION ENVIRONMENT ACTIONS

--[[------------------------------------------
		Push entire message part lookup
		to mission environment
--]]------------------------------------------
DiscordLink.Server.pushLookup = function()
	local execString = 
	[[
		a_do_script(
		[=[ -- Executed in mission scripting environment
			if DiscordLink == nil then DiscordLink = {} end 
			DiscordLink.msgPartLookup =
	]]

	execString = execString .. DiscordLink.Serialization.obj2str(DiscordLink.Server.msgPartLookup)

	execString = execString .. [[]=])]]

	DiscordLink.Logging.log(execString)
	net.dostring_in(DiscordLink.Server.scrEnvMission, execString)
	DiscordLink.Logging.log("All lookup pushed")
end

--[[------------------------------------------
		Push single message part category
		to mission environment
--]]------------------------------------------
DiscordLink.Server.pushLookupPart = function(msgPartCat)
	local execString = 
	[[
		a_do_script(
		[=[ -- Executed in mission scripting environment
			if DiscordLink == nil then DiscordLink = {} end 
			DiscordLink.msgPartLookup["]] .. msgPartCat .. [["] = 
	]]

	execString = execString .. DiscordLink.Serialization.obj2str(DiscordLink.Server.msgPartLookup[msgPartCat])

	execString = execString .. [[]=])]]

	DiscordLink.Logging.log(execString)
	net.dostring_in(DiscordLink.Server.scrEnvMission, execString)
	DiscordLink.Logging.log(msgPartCat .. " lookup pushed")
end

--[[------------------------------------------
		Push config to mission environment
--]]------------------------------------------
DiscordLink.Server.pushConfig = function()
	local execString = 
	[[
		a_do_script(
		[=[ -- Executed in mission scripting environment
			if DiscordLink == nil then DiscordLink = {} end 
			DiscordLink.config = 
	]]

	execString = execString .. DiscordLink.Serialization.obj2str(DiscordLink.Server.config)

	execString = execString .. [[]=])]]

	DiscordLink.Logging.log(execString)
	net.dostring_in(DiscordLink.Server.scrEnvMission, execString)
	DiscordLink.Logging.log("Config pushed")
end

--------------------------------------------------------------
-- POP MESSAGES

--[[------------------------------------------
		Pop messages from mission scripting
		environment, and send
--]]------------------------------------------
DiscordLink.Server.popMessage = function()

	DiscordLink.Server.nextMsgIndexToCheck = DiscordLink.Server.nextMsgIndexToCheck + 1

	local userFlag = DiscordLink.Server.config.userFlagRoot..DiscordLink.Server.nextMsgIndexToCheck
	local execString = 
	[[
		-- Executed in server mission scripting environment
		return(trigger.misc.getUserFlag("]]..userFlag..[["))
	]]

	DiscordLink.Logging.log("TODO pop message: " .. userFlag)

	local flagValRaw = net.dostring_in(DiscordLink.Server.scrEnvServer, execString)

	local flagVal = tonumber(flagValRaw)

	DiscordLink.Logging.log("exec Done" .. flagValRaw) -- TODO

	if flagVal == nil or flagVal == 0 then -- 0 used for boolean false (end of messages)
		DiscordLink.Server.nextMsgIndexToCheck = 0
		return
	elseif flagVal ~= 1 then -- 1 used for boolean true (skip message)

		local templateKey = DiscordLink.Server.msgPartRevLookup[flagVal]

		if templateKey ~= nil and templateKey[1] == DiscordLink.Server.msgPartCat.template then
			return	{
				template = templateKey[2], 
				args = DiscordLink.Server.popMessageRecurse(userFlag,1)
			}
		else
			DiscordLink.Logging.log("Invalid template handle: " .. flagVal)
		end
	
		-- clear flag
		execString = 
		[[
			-- Executed in server mission scripting environment
			trigger.action.setUserFlag("]]..userFlag..[[",true)
		]]
	
		net.dostring_in(DiscordLink.Server.scrEnvServer, execString)
	end

end

--[[------------------------------------------
		Pop message arguments
--]]------------------------------------------
DiscordLink.Server.popMessageRecurse = function(userFlagRoot,recurseLevel)
	local ret = nil
	if recurseLevel > 4 then return ret end

	local i = 1
	while i < DiscordLink.Server.config.maxArgsPerTemplate do

		local userFlag = userFlagRoot.."_"..i
		local execString = 
		[[
			-- Executed in server mission scripting environment
			return(trigger.misc.getUserFlag("]]..userFlag..[["))
		]]
	
		local flagRaw = net.dostring_in(DiscordLink.Server.scrEnvServer, execString)

		local flagVal = tonumber(flagRaw)
		if flagVal == nil or flagVal == 0  or flagVal == 1 then 
			break 
		elseif flagVal > 0 then
			flagVal = flagVal - 2
		end
		
		if not ret then ret = {} end

		local args = DiscordLink.Server.popMessageRecurse(userFlag,recurseLevel+1)
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

		net.dostring_in(DiscordLink.Server.scrEnvServer, execString)

		i = i + 1
	end

	return ret
end


--------------------------------------------------------------
-- MAIN LOOP LOGIC

--[[------------------------------------------
		Queue message in worker thread
--]]------------------------------------------
DiscordLink.Server.trySendToWebhook = function (webhook,username,templateRaw, templateArgs)

    if DiscordLink.Server.webhooks[webhook] == nil then
        DiscordLink.Logging.log("Webhook "..webhook.." not found")
        return false
	elseif username == nil or username == "" then
		DiscordLink.Logging.log("Missing username for call to webhook "..webhook)
        return false
	elseif templateRaw == nil then
		DiscordLink.Logging.log("Missing template for call to webhook "..webhook)
        return false
    end
	DiscordLink.Server.ensureLuaWorker()

	DiscordLink.Server.worker:DoCoroutine(
		[[DiscordLink.Worker.CallAndRetry]], 
		DiscordLink.Serialization.obj2str({
			username = username,
			templateRaw = templateRaw,
			templateArgs = templateArgs,
			webhook = DiscordLink.Server.webhookPrefix .. DiscordLink.Server.webhooks[webhook]
		}))

	return true
end

--[[------------------------------------------
		popAndSendOne
--]]------------------------------------------
DiscordLink.Server.popAndSendOne = function ()

    local msgData = DiscordLink.Server.popMessage()

	if msgData == nil then return false end

	if DiscordLink.Server.nextMsgIndexToCheck > 0 then
		DiscordLink.Server.popAgainNextFrame = true
	end

	local template = DiscordLink.Server.templates[msgData.template]

	if template == nil then
		DiscordLink.Logging.log("Template not found: " .. template)
		return false
	end 

	local templateArgs = {}

	if msgData.args ~= nil then
		for i,arg in ipairs(msgData.args) do
			templateArgs[i] = DiscordLink.Server.msgArgToString(arg.handle, arg.args) 
		end
	end

	DiscordLink.Server.trySendToWebhook(template.webhookKey,template.username, template.content, templateArgs)

	
end

--[[------------------------------------------
		Convert message arg pack to 
		replacement string
--]]------------------------------------------
DiscordLink.Server.msgArgToString = function (handle, msgArg)

	local handleVal = DiscordLink.Server.msgPartRevLookup[handle]

	if handleVal == nil or #handleVal < 2 then
		DiscordLink.Logging.log("Unrecognised message part handle: " .. handle)
		return nil
	end

	if handleVal[1] == DiscordLink.Server.msgPartCat.string then
		return DiscordLink.strings[handleVal[2]]
	elseif handleVal[1] == DiscordLink.Server.msgPartCat.player then
		return DiscordLink.Server.players[handleVal[2]]
	elseif handleVal[1] == DiscordLink.Server.msgPartCat.func then
		return DiscordLink.Server.funcs[handleVal[2]](msgArg)
	else
		DiscordLink.Logging.log("Unrecognised message part type " .. handleVal[1] .. " for handle "..handle)
		DiscordLink.Logging.log({"DiscordLink.Server.msgPartRevLookup:", DiscordLink.Server.msgPartRevLookup})
		return nil
	end	
end
--------------------------------------------------------------
-- LUA WORKER SETUP

--[[------------------------------------------
		Start lua worker thread if it's 
		not running/starting
--]]------------------------------------------
DiscordLink.Server.ensureLuaWorker = function()

	if DiscordLink.Server.worker ~= nil then
		local status = DiscordLink.Server.worker:Status()

		if status == LuaWorker.WorkerStatus.Starting 
			or status == LuaWorker.WorkerStatus.Processing then
			return
		else
			for i = 1,100 do
				local s = worker:PopLogLine()
				if s == nil then break end
				DiscordLink.Logging.log(s)		
			end
		end
	end

	DiscordLink.Server.worker = LuaWorker.Create()
	DiscordLink.Server.worker:Start()
	DiscordLink.Server.worker:DoString("package.cpath = [[" .. package.cpath .. ";"..DiscordLink.Server.scriptRoot..[[\https\?.dll;]] .. "]]")
	DiscordLink.Server.worker:DoString("package.path = [[" .. package.path .. ";"..DiscordLink.Server.scriptRoot..[[\https\?.lua;]] .. "]]")
	--DiscordLink.Server.worker:DoString("scriptRoot = [[" .. DiscordLink.Server.scriptRoot .. "]]")
	DiscordLink.Server.worker:DoFile(DiscordLink.Server.scriptRoot .. [[\DiscordLink_worker_init.lua]])
end

--------------------------------------------------------------
-- CALLBACKS

DiscordLink.Handlers = {}

--[[------------------------------------------
		onMissionLoadBegin
--]]------------------------------------------
DiscordLink.Handlers.onMissionLoadBegin = function()
	--if not DCS.isServer() or not DCS.isMultiplayer() then return end --TODO
	DiscordLink.safeCall(DiscordLink.Handlers.doOnMissionLoadBegin)
end

--[[------------------------------------------
		doOnMissionLoadBegin
--]]------------------------------------------
DiscordLink.Handlers.doOnMissionLoadBegin = function()
	DiscordLink.Server.loadConfiguration()
	local log_file_name = 'DCS_DiscordLink.Logging.log'
	
	local fulldir = DiscordLink.Server.config.directory.."\\"
	
	DiscordLink.Server.currentLogFile = io.open(fulldir .. log_file_name, "w")
	DiscordLink.Logging.log("Mission "..DCS.getMissionName().." loading",DiscordLink.Server.currentLogFile)

end

--[[------------------------------------------
		onMissionLoadBegin
--]]------------------------------------------
DiscordLink.Handlers.onMissionLoadEnd = function()
	--if not DCS.isServer() or not DCS.isMultiplayer() then return end --TODO
	DiscordLink.safeCall(DiscordLink.Handlers.doOnMissionLoadEnd)
end

--[[------------------------------------------
		doOnMissionLoadEnd
--]]------------------------------------------
DiscordLink.Handlers.doOnMissionLoadEnd = function()
	DiscordLink.Logging.log("Mission "..DCS.getMissionName().." loaded",DiscordLink.Server.currentLogFile)
	
end

--[[------------------------------------------
		onPlayerConnect
--]]------------------------------------------
DiscordLink.Handlers.onPlayerConnect = function(id)
	--if not DCS.isServer() or not DCS.isMultiplayer() then return end
	DiscordLink.safeCall(DiscordLink.Handlers.doOnPlayerConnect,id)
end

--[[------------------------------------------
		doOnPlayerConnect
--]]------------------------------------------
DiscordLink.Handlers.doOnPlayerConnect = function(id)
	local name = DiscordLink.Server.getPlayerName(id)
	--local ucid = DiscordLink.Server.getPlayerUcid(id)
	
	DiscordLink.Server.players[name] = name

	local existingInd = DiscordLink.Server.msgPartLookup.player[name]
	local revLookupEntry = {DiscordLink.Server.msgPartCat.player, name}

	if  existingInd == nil then
		DiscordLink.Server.msgPartRevLookup[DiscordLink.Server.nextMsgPartId] = revLookupEntry
		DiscordLink.Server.msgPartLookup.player[name] = DiscordLink.Server.nextMsgPartId
		DiscordLink.Server.nextMsgPartId = DiscordLink.Server.nextMsgPartId + 1
	end

	DiscordLink.Server.pushLookupPart("player")

	DiscordLink.Logging.log("Player ".. name .. " added")
end

--[[------------------------------------------
		onSimulationStop
--]]------------------------------------------
DiscordLink.Handlers.onSimulationStop = function()
	--if not DCS.isServer() or not DCS.isMultiplayer() then return end
	DiscordLink.safeCall(DiscordLink.Handlers.doOnSimulationStop)
end

--[[------------------------------------------
		doOnSimulationStop
--]]------------------------------------------
DiscordLink.Handlers.doOnSimulationStop = function()

	if DiscordLink.Server.worker ~= nil then
		DiscordLink.Server.worker:Stop()	

		for i = 1,100 do
			local s = DiscordLink.Server.worker.PopLogLine()
			if s == nil then break end
			DiscordLink.Logging.log(s)		
		end
	end
end

--[[------------------------------------------
		onSimulationStart
--]]------------------------------------------
DiscordLink.Handlers.onSimulationStart = function()
	--if not DCS.isServer() or not DCS.isMultiplayer() then return end
	DiscordLink.safeCall(DiscordLink.Handlers.doOnSimulationStart)
end

--[[------------------------------------------
		doOnSimulationStart
--]]------------------------------------------
DiscordLink.Handlers.doOnSimulationStart = function()
	DiscordLink.Server.reloadTemplates()
	DiscordLink.Server.pushLookup()
	DiscordLink.Logging.log(net.get_player_list())

	DiscordLink.Server.ensureLuaWorker()
end

--[[------------------------------------------
		onSimulationFrame
--]]------------------------------------------
DiscordLink.Handlers.onSimulationFrame = function()
	if DiscordLink.Server.pollFrameTime > DiscordLink.Server.config.framesPerPoll 
		or DiscordLink.Server.popAgainNextFrame then
		--if not DCS.isServer() or not DCS.isMultiplayer() then return end -- TODO Test

		if DiscordLink.Server.pollFrameTime > DiscordLink.Server.config.framesPerPoll then
			DiscordLink.Server.pollFrameTime = 0
		end
		
		DiscordLink.Server.popAgainNextFrame = false

		DiscordLink.safeCall(DiscordLink.Server.popAndSendOne)

		return
	elseif DiscordLink.Server.pollFrameTime == 111 and DiscordLink.Server.worker ~= nil then 
		-- Spread work between frames (avoid round numbers)
		for i = 1,100 do
			local s = DiscordLink.Server.worker:PopLogLine() 
			if s == nil then break end
			DiscordLink.Logging.log(s)		
		end
	end

	DiscordLink.Server.pollFrameTime = DiscordLink.Server.pollFrameTime + 1
end

--------------------------------------------------------------
-- INIT METHOD CALLS
--------------------------------------------------------------

--[[-------------------------------------------------
		Get connection strings
--]]-------------------------------------------------
DiscordLink.safeCall(
    function()
        local envVar = os.getenv(DiscordLink.Server.config.channelEnv)
        if envVar == nil then return end

        for k,v in string.gmatch(envVar,"([^;]+)=([^;]+);?") do
            --DiscordLink.Logging.log(k.." "..v)
            DiscordLink.Server.webhooks[k] = v
        end
    end)

--[[-------------------------------------------------
		Add default functions to be called
		to populate template
--]]-------------------------------------------------
DiscordLink.Server.addDefaultFuncs()

--[[-------------------------------------------------
		Register callbacks
--]]-------------------------------------------------
DCS.setUserCallbacks(DiscordLink.Handlers)

DiscordLink.Logging.log("TODO In Server")

