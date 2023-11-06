net.log("DCS_Webhooker Hook called")

local string = require("string")
local tools = require('tools')
local os = require("os")
local U  = require('me_utilities')
local lfs=require('lfs');
package.path = package.path .. [[;]] .. lfs.writedir() .. [[Mods\Services\DCS_Webhooker\core\?.lua;]]

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
		channelEnv = "DcsWebhookerUrls",
		userFlagRoot = "Webhooker",
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
	msgPartLookup = {templates = {}, strings = {}, players = {}, funcs = {}},

	-- key = id, value = {table,handle} --e.g. table = Webhooker.Server.strings
	msgPartRevLookup = {}, 
	msgQueue = {},
	msgRateEpoch = nil,
	msgCountSinceEpoch = nil,

	-- Module constants
	--msgPartCat = {template = 1, string = 2, player = 3, func = 4},
	scriptRoot = lfs.writedir()..[[Mods\Services\DCS_Webhooker]],
	scrEnvMission = "mission",
	scrEnvServer = "server"
}

 package.cpath = package.cpath..";"..Webhooker.Server.scriptRoot..[[\core\LuaWorker\?.dll;]]
 local LuaWorker = nil

--------------------------------------------------------------------------------------
-- LOAD C Modules
--------------------------------------------------------------------------------------

Webhooker.safeCall(
	function()
		LuaWorker = require("LuaWorker")
		net.log("Loaded LuaWorker")
	end)

--------------------------------------------------------------------------------------
-- CONFIG & UTILITY
--------------------------------------------------------------------------------------

--[[----------------------------------------------------------------------------------
		Load config from file
--]]----------------------------------------------------------------------------------
function Webhooker.Server.loadConfiguration()
    Webhooker.Logging.log("Config load starting")
	
    local cfg = tools.safeDoFile(lfs.writedir() .. 'Config/Webhooker.lua', false)
	
    if (cfg and cfg.Webhooker and cfg.Webhooker.config) then
		for k,v in pairs(Webhooker.Server.config) do
			if cfg.Webhooker.config[k] ~= nil then
				Webhooker.Server.config[k] = cfg.Webhooker.config[k]
			end
		end        
    end

	if cfg and cfg.Webhooker then
		if cfg.Webhooker.templates then
			Webhooker.Server.templates = cfg.Webhooker.templates     
		end
		if cfg.Webhooker.webhooks then
			Webhooker.Server.webhooks = cfg.Webhooker.webhooks   
		end
		if cfg.Webhooker.strings then
			Webhooker.Server.strings = cfg.Webhooker.strings   
		end
    end
	
	Webhooker.Server.saveConfiguration()
end

--[[----------------------------------------------------------------------------------
		Write current config to file
--]]----------------------------------------------------------------------------------
function Webhooker.Server.saveConfiguration()
	local toSave = {
		config = Webhooker.Server.config, 
		templates = Webhooker.Server.templates,
		webhooks = Webhooker.Server.webhooks,
		strings = Webhooker.Server.strings,
	}
    U.saveInFile(toSave, 'Webhooker', lfs.writedir()..'Config/Webhooker.lua')
end

--------------------------------------------------------------------------------------
-- TEMPLATES AND EXTENSION API
--------------------------------------------------------------------------------------

--[[----------------------------------------------------------------------------------
		Call this from messages scripts
		to install templates
--]]----------------------------------------------------------------------------------
Webhooker.Server.addTemplate=function(templateKey,webhookKey,bodyTemplate)
	Webhooker.Server.templates[templateKey] = {
		webhookKey = webhookKey,
		bodyRaw = bodyTemplate
	}
end

--[[----------------------------------------------------------------------------------
		Call this from messages scripts
		to install strings
--]]----------------------------------------------------------------------------------
Webhooker.Server.addString=function(stringKey,stringValue)
	
	if stringValue == nil then stringValue = stringKey end

	Webhooker.Server.strings[stringKey] = stringValue
end

--[[----------------------------------------------------------------------------------
		Call this from messages scripts
		to install functions
--]]----------------------------------------------------------------------------------
Webhooker.Server.addFunc=function(funcKey,funcValue)
	Webhooker.Server.funcs[funcKey] = funcValue
end

--[[----------------------------------------------------------------------------------
		Try to convert function or template argument to an integer
		Noo lookups or function calls are performed
--]]----------------------------------------------------------------------------------
Webhooker.Server.argToNum = function (msgArg)

	local handle = nil
	local ret = nil

	if type(msgArg) == 'number' then
		return msgArg
	elseif type(msgArg) == 'table' and type(msgArg[1]) == 'number' then
		return msgArg.handle
	else 
		return nil
	end
end

--[[----------------------------------------------------------------------------------
		Try to convert function or template argument to a string, 
		using lookup tables and calling functions
--]]----------------------------------------------------------------------------------
Webhooker.Server.argToString = function (msgArg)

	local handle = nil
	local innerArgs = nil
	local ret = ""

	if type(msgArg) == 'number' then
		handle = msgArg
	elseif type(msgArg) == 'table' then
		handle = msgArg.handle
		innerArgs = msgArg.args
	else 
		return ret
	end

	local handleVal = Webhooker.Server.msgPartRevLookup[handle]

	if handleVal == nil or #handleVal < 2 or type(handleVal[1]) ~= 'table' then
		Webhooker.Logging.log("Unrecognised message part handle: " .. handle)
		return ret
	end

	if handleVal[1] == Webhooker.Server.funcs then
		if type(innerArgs) == 'table' then
			ret = Webhooker.Server.funcs[handleVal[2]](unpack(innerArgs))
		else 
			ret = Webhooker.Server.funcs[handleVal[2]]()
		end		
	else 
		ret = handleVal[1][handleVal[2]]
	end

	if ret == nil then
		return ""
	else
		return ret
	end
end

--------------------------------------------------------------------------------------
-- LOAD TEMPLATES AND EXTENSIONS
--------------------------------------------------------------------------------------

--[[----------------------------------------------------------------------------------
		Run files from the messages subdir
		to install webhook message templates
--]]----------------------------------------------------------------------------------
Webhooker.Server.reloadTemplates = function()
	Webhooker.Server.templates = {}
	local messagesDir = Webhooker.Server.scriptRoot..[[\messageTemplates]]

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

	-- Rebuild template lookup
	Webhooker.Server.buildLookupSection("templates")

	-- Rebuild string lookup
	Webhooker.Server.buildLookupSection("strings")

	-- Rebuild func lookup
	Webhooker.Server.buildLookupSection("funcs")
end

Webhooker.Server.buildLookupSection = function (sectionName)
	local newLookup = {}

	local section = Webhooker.Server[sectionName]
	local lookupSection = Webhooker.Server.msgPartLookup[sectionName]

	if section == nil or lookupSection == nil then
		Webhooker.Logging.log("Invalid section name: " .. sectionName)
		return
	end

	for k,v in pairs(section) do

		local existingInd = lookupSection[k]
		local revLookupEntry = {section, k}

		if  existingInd == nil then
			Webhooker.Server.msgPartRevLookup[Webhooker.Server.nextMsgPartId] = revLookupEntry
			newLookup[k] = Webhooker.Server.nextMsgPartId
			Webhooker.Server.nextMsgPartId = Webhooker.Server.nextMsgPartId + 1
		else
			Webhooker.Server.msgPartRevLookup[existingInd] = revLookupEntry
			newLookup[k] = existingInd
		end
	end
	Webhooker.Server.msgPartLookup[sectionName] = newLookup --was lookupSection

	Webhooker.Logging.log(sectionName .." section rebuilt: ")
	Webhooker.Logging.log(section)
end

--------------------------------------------------------------------------------------
-- PUSH TO MISSION ENVIRONMENT ACTIONS
--------------------------------------------------------------------------------------

--[[----------------------------------------------------------------------------------
		Push entire message part lookup
		to mission environment
--]]----------------------------------------------------------------------------------
Webhooker.Server.pushLookup = function()
	local execString = 
	[[
		a_do_script(
		[=[ 
			-- Executed in mission scripting environment
			if Webhooker == nil then Webhooker = {} end 
			Webhooker.msgPartLookup =
	]]

	execString = execString .. Webhooker.Serialization.obj2str(Webhooker.Server.msgPartLookup)

	execString = execString .. [[]=])]]

	Webhooker.Logging.log(execString)
	net.dostring_in(Webhooker.Server.scrEnvMission, execString)
	Webhooker.Logging.log("All lookup pushed")
end

--[[----------------------------------------------------------------------------------
		Push single message part category
		to mission environment

		Args: 
		msgPartCat - string, index into Webhooker.Server.msgPartLookup
--]]----------------------------------------------------------------------------------
Webhooker.Server.pushLookupPart = function(msgPartCat)
	local execString = 
	[[
		a_do_script(
		[=[ 
			-- Executed in mission scripting environment

			if Webhooker == nil then Webhooker = {} end
			if Webhooker.msgPartLookup == nil then Webhooker.msgPartLookup = {} end

			Webhooker.msgPartLookup["]] .. msgPartCat .. [["] = 
	]]

	execString = execString .. Webhooker.Serialization.obj2str(Webhooker.Server.msgPartLookup[msgPartCat])

	execString = execString .. [[]=])]]

	net.dostring_in(Webhooker.Server.scrEnvMission, execString)
	Webhooker.Logging.log(msgPartCat .. " lookup pushed")
end

--[[----------------------------------------------------------------------------------
		Push config to mission environment
--]]----------------------------------------------------------------------------------
Webhooker.Server.pushConfig = function()
	local execString = 
	[[
		a_do_script(
		[=[ 
			-- Executed in mission scripting environment
			if Webhooker == nil then Webhooker = {} end 
			Webhooker.config = 
	]]

	execString = execString .. Webhooker.Serialization.obj2str(Webhooker.Server.config)

	execString = execString .. [[]=])]]

	net.dostring_in(Webhooker.Server.scrEnvMission, execString)
	Webhooker.Logging.log("Config pushed")
end

--------------------------------------------------------------------------------------
-- POP MESSAGES
--------------------------------------------------------------------------------------

--[[----------------------------------------------------------------------------------
		Pop messages from mission scripting
		environment, and send
--]]----------------------------------------------------------------------------------
Webhooker.Server.popMessage = function()

	Webhooker.Server.nextMsgIndexToCheck = Webhooker.Server.nextMsgIndexToCheck + 1

	local ret = nil

	local userFlag = Webhooker.Server.config.userFlagRoot .. "_" ..Webhooker.Server.nextMsgIndexToCheck
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

		if flagVal > 0 then
			flagVal = flagVal - 2
		end

		local templateKey = Webhooker.Server.msgPartRevLookup[flagVal]

		if templateKey ~= nil and templateKey[1] == Webhooker.Server.templates then
			ret = {
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

	Webhooker.Logging.log("Popped message flags: ")
	Webhooker.Logging.log(ret)

	return ret

end

--[[----------------------------------------------------------------------------------
		Pop message arguments
--]]----------------------------------------------------------------------------------
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
		local args = nil

		if flagVal == nil or flagVal == 0 then 
			break 
		elseif flagVal == 1  then
			flagVal = nil
		elseif flagVal > 1 then
			flagVal = flagVal - 2
			args = Webhooker.Server.popMessageRecurse(userFlag,recurseLevel+1)
		end
		
		if not ret then ret = {} end 

		if args == nil and flagVal ~= nil then
			ret[#ret + 1] = flagVal
		elseif args == nil then
			ret[#ret + 1] = "NULL"
		else
			ret[#ret + 1] = {
				handle = flagVal,
				args = args
			}
		end

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


--------------------------------------------------------------------------------------
-- MAIN LOOP LOGIC
--------------------------------------------------------------------------------------

--[[----------------------------------------------------------------------------------
		Queue message in worker thread
--]]----------------------------------------------------------------------------------
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

--[[----------------------------------------------------------------------------------
		popAndSendOne
--]]----------------------------------------------------------------------------------
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
			templateArgs[i] = Webhooker.Server.argToString(arg) 
		end
	end

	Webhooker.Server.trySendToWebhook(template.webhookKey,template.bodyRaw, templateArgs)

end
--------------------------------------------------------------
-- LUA WORKER SETUP

--[[----------------------------------------------------------------------------------
		Start lua worker thread if it's 
		not running/starting
--]]----------------------------------------------------------------------------------
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
	Webhooker.Server.worker:DoString("package.cpath = [[" .. package.cpath .. ";"..Webhooker.Server.scriptRoot..[[\core\https\?.dll;]] .. "]]")
	Webhooker.Server.worker:DoString("package.path = [[" .. package.path .. ";"..Webhooker.Server.scriptRoot..[[\core\https\?.lua;]] .. "]]")
	--Webhooker.Server.worker:DoString("scriptRoot = [[" .. Webhooker.Server.scriptRoot .. "]]")
	Webhooker.Server.worker:DoFile(Webhooker.Server.scriptRoot .. [[\core\Webhooker_worker.lua]])
end

--------------------------------------------------------------------------------------
-- CALLBACKS
--------------------------------------------------------------------------------------

Webhooker.Handlers = {}

--[[----------------------------------------------------------------------------------
		onMissionLoadBegin
--]]----------------------------------------------------------------------------------
Webhooker.Handlers.onMissionLoadBegin = function()
	--if not DCS.isServer() or not DCS.isMultiplayer() then return end --TODO
	Webhooker.safeCall(Webhooker.Handlers.doOnMissionLoadBegin)
end

--[[----------------------------------------------------------------------------------
		doOnMissionLoadBegin
--]]----------------------------------------------------------------------------------
Webhooker.Handlers.doOnMissionLoadBegin = function()
	Webhooker.Server.loadConfiguration()
	local log_file_name = 'DCS_Webhooker.Logging.log'
	
	local fulldir = Webhooker.Server.config.directory.."\\"
	
	Webhooker.Server.currentLogFile = io.open(fulldir .. log_file_name, "w")
	Webhooker.Logging.log("Mission "..DCS.getMissionName().." loading",Webhooker.Server.currentLogFile)

end

--[[----------------------------------------------------------------------------------
		onMissionLoadBegin
--]]----------------------------------------------------------------------------------
Webhooker.Handlers.onMissionLoadEnd = function()
	--if not DCS.isServer() or not DCS.isMultiplayer() then return end --TODO
	Webhooker.safeCall(Webhooker.Handlers.doOnMissionLoadEnd)
end

--[[----------------------------------------------------------------------------------
		doOnMissionLoadEnd
--]]----------------------------------------------------------------------------------
Webhooker.Handlers.doOnMissionLoadEnd = function()
	Webhooker.Logging.log("Mission "..DCS.getMissionName().." loaded",Webhooker.Server.currentLogFile)
	
	local file = assert(io.open(Webhooker.Server.scriptRoot .. [[\core\Webhooker_mission_inject.lua]], "r"))
	local injectContent = file:read("*all")
    file:close()

	local execString = 
	[[
		a_do_script("]] .. Webhooker.Serialization.escapeLuaString(injectContent) .. [[")
	]]

	net.dostring_in(Webhooker.Server.scrEnvMission, execString)

	Webhooker.Server.pushConfig()
end

--[[----------------------------------------------------------------------------------
		onPlayerConnect
--]]----------------------------------------------------------------------------------
Webhooker.Handlers.onPlayerConnect = function(id)
	--if not DCS.isServer() or not DCS.isMultiplayer() then return end
	Webhooker.safeCall(Webhooker.Handlers.doOnPlayerConnect,id)
end

--[[----------------------------------------------------------------------------------
		doOnPlayerConnect
--]]----------------------------------------------------------------------------------
Webhooker.Handlers.doOnPlayerConnect = function(id)
	local name = Webhooker.Server.getPlayerName(id)
	--local ucid = Webhooker.Server.getPlayerUcid(id)
	
	Webhooker.Server.players[name] = name

	local existingInd = Webhooker.Server.msgPartLookup.players[name]
	local revLookupEntry = {Webhooker.Server.players, name}

	if  existingInd == nil then
		Webhooker.Server.msgPartRevLookup[Webhooker.Server.nextMsgPartId] = revLookupEntry
		Webhooker.Server.msgPartLookup.players[name] = Webhooker.Server.nextMsgPartId
		Webhooker.Server.nextMsgPartId = Webhooker.Server.nextMsgPartId + 1
	end

	Webhooker.Server.pushLookupPart("player")

	Webhooker.Logging.log("Player ".. name .. " added")
end

--[[----------------------------------------------------------------------------------
		onSimulationStop
--]]----------------------------------------------------------------------------------
Webhooker.Handlers.onSimulationStop = function()
	--if not DCS.isServer() or not DCS.isMultiplayer() then return end
	Webhooker.safeCall(Webhooker.Handlers.doOnSimulationStop)
end

--[[----------------------------------------------------------------------------------
		doOnSimulationStop
--]]----------------------------------------------------------------------------------
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

--[[----------------------------------------------------------------------------------
		onSimulationStart
--]]----------------------------------------------------------------------------------
Webhooker.Handlers.onSimulationStart = function()
	--if not DCS.isServer() or not DCS.isMultiplayer() then return end
	Webhooker.safeCall(Webhooker.Handlers.doOnSimulationStart)
end

--[[----------------------------------------------------------------------------------
		doOnSimulationStart
--]]----------------------------------------------------------------------------------
Webhooker.Handlers.doOnSimulationStart = function()
	Webhooker.Server.reloadTemplates()
	Webhooker.Server.pushLookup()
	Webhooker.Logging.log(net.get_player_list())

	Webhooker.Server.ensureLuaWorker()
end

--[[----------------------------------------------------------------------------------
		onSimulationFrame
--]]----------------------------------------------------------------------------------
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

--------------------------------------------------------------------------------------
-- INIT METHOD CALLS
--------------------------------------------------------------------------------------

--[[----------------------------------------------------------------------------------
		Get connection strings
--]]----------------------------------------------------------------------------------
Webhooker.safeCall(
    function()
        local envVar = os.getenv(Webhooker.Server.config.channelEnv)
        if envVar == nil then return end

        for k,v in string.gmatch(envVar,"([^;]+)=([^;]+);?") do
            --Webhooker.Logging.log(k.." "..v) 
            Webhooker.Server.webhooks[k] = v
        end
    end)

--[[----------------------------------------------------------------------------------
		Register callbacks
--]]----------------------------------------------------------------------------------
DCS.setUserCallbacks(Webhooker.Handlers)

