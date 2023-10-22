net.log("DCS_DiscordLink Hook called")

local socket = require("socket")
local string = require("string")
local ltn12 = require("ltn12")
local tools = require('tools')
local os = require("os")
local U  = require('me_utilities')

if DiscordLink ~= nil and DiscordLink.logFile ~= nil then
	io.close(DiscordLink.logFile)
	for k,v in pairs(DiscordLink) do -- Set event handlers to nil
		DiscordLink[k] = nil
	end
end

DiscordLink = {
	config = 
	{
		directory = lfs.writedir()..[[Logs\]],
		channelEnv = "DcsDiscordLinkWebhooks",
		userFlagRoot = "DiscordLink_",
		retrySendSeconds = 10,
		framesPerPoll = 600,
		maxMessagePopPerFrame = 20,
		maxArgsPerTemplate = 20
	},

	logFile = io.open(lfs.writedir()..[[Logs\DCS_DiscordLink.log]], "w"),
	currentLogFile = nil,
	pollFrameTime = 0,
    webhooks = {},
	templates = {}, -- key = template handle, value = {}
	strings = {},
	players = {},
	funcs = {},
	nextMsgPartId = 1,
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

 package.cpath = package.cpath..";"..DiscordLink.scriptRoot..[[\LuaWorker\?.dll;]]
 local LuaWorker = nil

--------------------------------------------------------------
-- LOAD C Modules

-- DiscordLink.safeCall(
--     function()
--         https = require("https")
--         net.log("Loaded https")
--     end)

DiscordLink.safeCall(
	function()
		LuaWorker = require("LuaWorker")
		net.log("Loaded LuaWorker")
	end)

-----------------------------------------------------------
-- CONFIG & UTILITY

--[[------------------------------------------
		Write log line
--]]------------------------------------------
DiscordLink.log = function(str, logFile, prefix)
    if not str and not prefix then 
        return
    end
	
	if not logFile then
		logFile = DiscordLink.logFile
	end
	
    if logFile then
		local msg = ''
		if prefix then msg = msg..prefix end
		if str then
			if type(str) == 'table' then
				msg = msg..'{'
				for k,v in pairs(str) do
					local t = type(v)
					msg = msg..k..':'..DiscordLink.obj2str(v)..', '
				end
				msg = msg..'}'
			else
				msg = msg..str
			end
		end
		logFile:write("["..os.date("%H:%M:%S").."] "..msg.."\r\n")
		logFile:flush()
    end
end

--[[------------------------------------------
		Convert lua object to string
--]]------------------------------------------

DiscordLink.escapeLuaString = function (str) 
	return 
	string.gsub(string.gsub(string.gsub(string.gsub(str,"\\","\\\\")
														,"\"","\\\"")
														,"\n","\\\n")
														, "\r","\\\r")
end

DiscordLink.obj2str = function(obj, antiCirc,maxdepth)

	if maxdepth == nil then 
		maxdepth = 4 
	end

	if antiCirc == nil then 
		antiCirc = {}
	end

	if maxdepth<=0 then
		return "#"
	end

	if obj == nil then 
		return '??'
	end

	local msg = ''
	local t = type(obj)

	if t == 'table' then
		antiCirc[obj] = true

		msg = msg..'{'
		for k,v in pairs(obj) do
			local t = type(v)
			local dup = false

			dup = antiCirc[v] == true or antiCirc[k] == true

			if dup == false then
				msg = msg .. "[" .. obj2str(k,antiCirc,maxdepth -1)..']='..obj2str(v,antiCirc,maxdepth-1) .. ","
			end
		end
		msg = msg..'}'
	elseif t == 'string' then
		msg = msg.."\"".. DiscordLink.escapeLuaString(obj) .."\""
	elseif t == 'number' then
		msg = msg..obj
	elseif t == 'boolean' then
		if t then
			msg = msg..'true'
		else
			msg = msg..'false'
		end
	end
	return msg
end

-- DiscordLink.obj2strJson = function(obj, antiCirc,maxdepth, dblEscape)

-- 	if maxdepth == nil then 
-- 		maxdepth = 4 
-- 	end

-- 	if antiCirc == nil then 
-- 		antiCirc = {}
-- 	end

-- 	if maxdepth<=0 then
-- 		return "#"
-- 	end

-- 	if obj == nil then 
-- 		return '??'
-- 	end

-- 	local quoteChar = '"'
-- 	if dblEscape then 
-- 		quoteChar = '\\"'
-- 	end

-- 	local msg = ''
-- 	local t = type(obj)

-- 	if t == 'table' then
-- 		antiCirc[obj] = true
-- 		local first = true

-- 		msg = msg..'{'
-- 		for k,v in pairs(obj) do
-- 			local t = type(v)
-- 			local dup = false

-- 			dup = antiCirc[v] == true or antiCirc[k] == true

-- 			if dup == false then
-- 				if first then
-- 					msg = msg..', '
-- 					first  = false
-- 				end
-- 				msg = msg..obj2str(k,antiCirc,maxdepth -1)..':'..obj2str(v,antiCirc,maxdepth-1)
-- 			end
-- 		end
-- 		msg = msg..'}'
-- 	elseif t == 'string' then
-- 		msg = msg.."\"".. string.gsub(string.gsub(obj,"\\","\\\\"),"\"","\\\"") .."\""
-- 	elseif t == 'number' then
-- 		msg = msg..obj
-- 	elseif t == 'boolean' then
-- 		if t then
-- 			msg = msg..'true'
-- 		else
-- 			msg = msg..'false'
-- 		end
-- 	end
-- 	return msg
-- end

--[[------------------------------------------
		Load config from file
--]]------------------------------------------
function DiscordLink.loadConfiguration()
    DiscordLink.log("Config load starting")
	
    local cfg = tools.safeDoFile(lfs.writedir() .. 'Config/DiscordLink.lua', false)
	
    if (cfg and cfg.config) then
		for k,v in pairs(DiscordLink.config) do
			if cfg.config[k] ~= nil then
				DiscordLink.config[k] = cfg.config[k]
			end
		end        
    end
	
	DiscordLink.saveConfiguration()
end

--[[------------------------------------------
		Write current config to file
--]]------------------------------------------
function DiscordLink.saveConfiguration()
    U.saveInFile(DiscordLink.config, 'config', lfs.writedir()..'Config/DiscordLink.lua')
end

--[[------------------------------------------
		Default error handler for module
--]]------------------------------------------
DiscordLink.catchError=function(err)
	DiscordLink.log(err)
end 

--[[------------------------------------------
		Execute func and log on error
--]]------------------------------------------
DiscordLink.safeCall = function(func,...)
	local op = func
	if arg then 
		op = function()
			func(unpack(arg))
		end
	end
	
	xpcall(op,DiscordLink.catchError)
end

--------------------------------------------------------------
-- DEFAULT FUNCTIONS

--[[------------------------------------------
		Function to add integer to template
--]]------------------------------------------
DiscordLink.formatInteger = function(pack)
	--TODO tidy
	return pack[1]
end

--[[------------------------------------------
		Add default functions that can be
		called to populate message templates
--]]------------------------------------------
DiscordLink.addDefaultFuncs = function()
	local lookup = {}

	DiscordLink.funcs.integer = DiscordLink.formatInteger

	for k,v in pairs(DiscordLink.funcs) do

		local revLookupEntry = {DiscordLink.msgPartCat.func,k}
		local existingInd = DiscordLink.msgPartLookup.func[k]

		if  existingInd == nil then
			DiscordLink.msgPartRevLookup[DiscordLink.nextMsgPartId] = revLookupEntry
			lookup[k] = DiscordLink.nextMsgPartId
			DiscordLink.nextMsgPartId = DiscordLink.nextMsgPartId + 1
		else
			DiscordLink.msgPartRevLookup[existingInd] = revLookupEntry
			lookup[k] = existingInd
		end
	end
	DiscordLink.msgPartLookup.func = lookup
end 

--------------------------------------------------------------
-- LOAD TEMPLATES

--[[------------------------------------------
		Call this from messages scripts
		to install templates
--]]------------------------------------------
DiscordLink.addTemplate=function(templateKey,webhookKey,username,content)
	DiscordLink.templates[templateKey] = {
		webhookKey = webhookKey,
		username = username,
		content = content
	}
end

--[[------------------------------------------
		Run files from the messages subdir
		to install webhook message templates
--]]------------------------------------------
DiscordLink.reloadTemplates = function()
	DiscordLink.templates = {}
	local messagesDir = DiscordLink.scriptRoot..[[\messages]]

	DiscordLink.log(messagesDir)	
	for fpath in lfs.dir(messagesDir) do

		local fullPath = messagesDir .. "\\" .. fpath
		DiscordLink.log("Found "..fpath)
		DiscordLink.log(lfs.attributes(fullPath,"mode"))

		if lfs.attributes(fullPath,"mode") == "file" then
			DiscordLink.log("Loading ".. fpath)	
			DiscordLink.safeCall(dofile,fullPath)		
		end
	end

	local templateLookup = {}
	for k,v in pairs(DiscordLink.templates) do

		local existingInd = DiscordLink.msgPartLookup.template[k]
		local revLookupEntry = {DiscordLink.msgPartCat.template, k}

		if  existingInd == nil then
			DiscordLink.msgPartRevLookup[DiscordLink.nextMsgPartId] = revLookupEntry
			templateLookup[k] = DiscordLink.nextMsgPartId
			DiscordLink.nextMsgPartId = DiscordLink.nextMsgPartId + 1
		else
			DiscordLink.msgPartRevLookup[existingInd] = revLookupEntry
			templateLookup[k] = existingInd
		end
	end
	DiscordLink.msgPartLookup.template = templateLookup

	DiscordLink.log(DiscordLink.templates)
end

--------------------------------------------------------------
-- PUSH TO MISSION ENVIRONMENT ACTIONS

--[[------------------------------------------
		Push entire message part lookup
		to mission environment
--]]------------------------------------------
DiscordLink.pushLookup = function()
	local execString = 
	[[
		a_do_script(
		[=[ -- Executed in mission scripting environment
			if DiscordLink == nil then DiscordLink = {} end 
			DiscordLink.msgPartLookup = 
	]]

	execString = execString .. DiscordLink.obj2str(DiscordLink.msgPartLookup)

	execString = execString .. [[]=])]]

	DiscordLink.log(execString)
	net.dostring_in(DiscordLink.scrEnvMission, execString)
	DiscordLink.log("All lookup pushed")
end

--[[------------------------------------------
		Push single message part category
		to mission environment
--]]------------------------------------------
DiscordLink.pushLookupPart = function(msgPartCat)
	local execString = 
	[[
		a_do_script(
		[=[ -- Executed in mission scripting environment
			if DiscordLink == nil then DiscordLink = {} end 
			DiscordLink.msgPartLookup["]] .. msgPartCat .. [["] = 
	]]

	execString = execString .. DiscordLink.obj2str(DiscordLink.msgPartLookup[msgPartCat])

	execString = execString .. [[]=])]]

	DiscordLink.log(execString)
	net.dostring_in(DiscordLink.scrEnvMission, execString)
	DiscordLink.log(msgPartCat .. " lookup pushed")
end

--[[------------------------------------------
		Push config to mission environment
--]]------------------------------------------
DiscordLink.pushConfig = function()
	local execString = 
	[[
		a_do_script(
		[=[ -- Executed in mission scripting environment
			if DiscordLink == nil then DiscordLink = {} end 
			DiscordLink.config = 
	]]

	execString = execString .. DiscordLink.obj2str(DiscordLink.config)

	execString = execString .. [[]=])]]

	DiscordLink.log(execString)
	net.dostring_in(DiscordLink.scrEnvMission, execString)
	DiscordLink.log("Config pushed")
end

--------------------------------------------------------------
-- POP MESSAGES

--[[------------------------------------------
		Pop messages from mission scripting
		environment, and send
--]]------------------------------------------
DiscordLink.popMessages = function()
	local i = 1
	while i < DiscordLink.config.maxMessagePopPerFrame do
		local userFlag = DiscordLink.config.userFlagRoot..i
		local execString = 
		[[
			-- Executed in server mission scripting environment
			return(trigger.misc.getUserFlag("]]..userFlag..[["))
		]]
	
		local flagValRaw = net.dostring_in(DiscordLink.scrEnvServer, execString)
		--DiscordLink.log({result, type(result)})

		local flagVal = tonumber(flagValRaw)
		if flagVal == nil or flagVal == 0 then -- 0 used for boolean false (end of messages)
			break 
		elseif flagVal ~= 1 then -- 1 used for boolean true (skip message)

			local templateKey = DiscordLink.msgPartRevLookup[flagVal]

			if templateKey ~= nil and templateKey[1] == DiscordLink.msgPartCat.template then
				DiscordLink.msgQueue[#DiscordLink.msgQueue + 1] = {
					template = templateKey[2], 
					args = DiscordLink.popMessagesRecurse(userFlag,1),
					sendCount = 0,
					lastSent = nil
				}
			else
				DiscordLink.log("Invalid template handle: " .. flagVal)
			end
		
			-- clear flag
			execString = 
			[[
				-- Executed in server mission scripting environment
				trigger.action.setUserFlag("]]..userFlag..[[",true)
			]]
		
			net.dostring_in(DiscordLink.scrEnvServer, execString)
		end

		i = i + 1
	end
end

--[[------------------------------------------
		Pop message arguments
--]]------------------------------------------
DiscordLink.popMessagesRecurse = function(userFlagRoot,recurseLevel)
	local ret = nil
	if recurseLevel > 4 then return ret end

	local i = 1
	while i < DiscordLink.config.maxArgsPerTemplate do

		local userFlag = userFlagRoot.."_"..i
		local execString = 
		[[
			-- Executed in server mission scripting environment
			return(trigger.misc.getUserFlag("]]..userFlag..[["))
		]]
	
		local flagRaw = net.dostring_in(DiscordLink.scrEnvServer, execString)

		local flagVal = tonumber(flagRaw)
		if flagVal == nil or flagVal == 0  or flagVal == 1 then 
			break 
		elseif flagVal > 0 then
			flagVal = flagVal - 2
		end
		
		if not ret then ret = {} end

		local args = DiscordLink.popMessagesRecurse(userFlag,recurseLevel+1)
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

		net.dostring_in(DiscordLink.scrEnvServer, execString)

		i = i + 1
	end

	return ret
end


--------------------------------------------------------------
-- MAIN LOOP LOGIC

--[[------------------------------------------
		Queue message in worker thread
--]]------------------------------------------
DiscordLink.trySendToWebhook = function (webhook,username,content)

    if DiscordLink.webhooks[webhook] == nil then
        DiscordLink.log("Webhook "..webhook.." not found")
        return false
	elseif username == nil or username == "" then
		DiscordLink.log("Missing username for call to webhook "..webhook)
        return false
	elseif content == nil then
		DiscordLink.log("Missing content for call to webhook "..webhook)
        return false
    end

	local bodyRaw = {
		username = username,
		content = content
	}

	DiscordLink.log("Sending webhook " .. DiscordLink.obj2str(bodyRaw))

    local webhookUrl = DiscordLink.webhookPrefix .. DiscordLink.webhooks[webhook]
    local body = net.lua2json(bodyRaw)

	DiscordLink.EnsureLuaWorker()

	DiscordLink.worker:DoCoroutine([[CallAndRetry]], DiscordLink.escapeLuaString(webhookUrl),DiscordLink.escapeLuaString(body))

	return true
end

--[[------------------------------------------
		TODO: combinme this with the above
--]]------------------------------------------
DiscordLink.sendQueuedMessage = function(queueItem)

	if queueItem.compiledMessage == nil then
		queueItem.compiledMessage = DiscordLink.makeMsgContent(queueItem)
	end

	local template = DiscordLink.templates[queueItem.template]

	if template == nil then
		DiscordLink.log("Template not found: " .. template)
		return false
	end 

	return DiscordLink.trySendToWebhook(template.webhookKey,template.username, queueItem.compiledMessage)
end

--[[------------------------------------------
		TODO: Move retries to worker thread
--]]------------------------------------------
DiscordLink.popAndSendAll = function ()
    DiscordLink.popMessages()

	local retryCuttoff = os.time() - DiscordLink.config.retrySendSeconds

	for k,v in pairs(DiscordLink.msgQueue) do

		if v.lastSent == nil or v.lastSent < retryCuttoff then
			if DiscordLink.sendQueuedMessage(v) then
				-- on success
				DiscordLink.msgQueue[k] = nil 
			else
				-- on failure
				v.lastSent = os.time() -- os.date("%c",os.time())
				v.sendCount = v.sendCount + 1
			end
		end
	end
end

--[[------------------------------------------
		Replace placeholders in template
		to generate webhook body
--]]------------------------------------------
DiscordLink.makeMsgContent = function (msgData)

	if msgData == nil then return nil end

	local template = DiscordLink.templates[msgData.template]

	local rawTemplate = template.content

	local subStrings = {}
	if msgData.args ~= nil then
		for i,v in ipairs(msgData.args) do
			subStrings[i] = DiscordLink.msgArgToString(v.handle, v.args) 
		end
	end

	--DiscordLink.log({"Replacement substrings", subStrings})

	local finalText = ""
	local at = 1
	local atEnd = string.len(rawTemplate)
	while at <= atEnd do
		local found = string.find(rawTemplate,"%%", at) -- "%" (%% in lua regexp) starts replaceable token

		if found == nil then
			finalText = finalText .. string.sub(rawTemplate, at, atEnd)
			break
		elseif  found > at then
			finalText = finalText .. string.sub(rawTemplate, at, found - 1)
		end
		
		if string.sub(rawTemplate,found,found+1) == "%%" then
			finalText = finalText .. "%"
			at = found + 2
		else
			local tok = ""
			local foundEnd = string.find(rawTemplate,"%s", found + 1)
			if foundEnd  == nil then
				tok = string.sub(rawTemplate, found + 1, atEnd)
				at = atEnd + 1
			else
				tok = string.sub(rawTemplate, found + 1, foundEnd - 1)
				at = foundEnd + 1
			end

			local substring = subStrings[tonumber(tok)]
			if substring == nil then
				substring = ""
				-- DiscordLink.log("Substring not found for  \"" .. tok .. "\"")
				return nil
			end
			finalText = finalText .. substring 
		end
	end
	return finalText
end

--[[------------------------------------------
		Convert message arg pack to 
		replacement string
--]]------------------------------------------
DiscordLink.msgArgToString = function (handle, msgArg)

	local handleVal = DiscordLink.msgPartRevLookup[handle]

	if handleVal == nil or #handleVal < 2 then
		DiscordLink.log("Unrecognised message part handle: " .. handle)
		return nil
	end

	if handleVal[1] == DiscordLink.msgPartCat.string then
		return DiscordLink.strings[handleVal[2]]
	elseif handleVal[1] == DiscordLink.msgPartCat.player then
		return DiscordLink.players[handleVal[2]]
	elseif handleVal[1] == DiscordLink.msgPartCat.func then
		return DiscordLink.funcs[handleVal[2]](msgArg)
	else
		DiscordLink.log("Unrecognised message part type " .. handleVal[1] .. " for handle "..handle)
		DiscordLink.log({"DiscordLink.msgPartRevLookup:", DiscordLink.msgPartRevLookup})
		return nil
	end	
end
--------------------------------------------------------------
-- LUA WORKER SETUP

--[[------------------------------------------
		Start lua worker thread if it's 
		not running/starting
--]]------------------------------------------
DiscordLink.EnsureLuaWorker = function()

	if DiscordLink.worker ~= nil then
		local status = DiscordLink.worker:Status()

		if status == LuaWorker.WorkerStatus.Starting 
			or status == LuaWorker.WorkerStatus.Processing then
			return
		else
			for i = 1,100 do
				local s = worker:PopLogLine()
				if s == nil then break end
				DiscordLink.log(s)		
			end
		end
	end

	DiscordLink.worker = LuaWorker.Create()
	DiscordLink.worker:Start()
	DiscordLink.worker:DoString("package.cpath = [[" .. package.cpath .. ";"..DiscordLink.scriptRoot..[[\https\?.dll;]] .. "]]")
	DiscordLink.worker:DoString("package.path = [[" .. package.path .. ";"..DiscordLink.scriptRoot..[[\https\?.lua;]] .. "]]")
	--DiscordLink.worker:DoString("scriptRoot = [[" .. DiscordLink.scriptRoot .. "]]")
	DiscordLink.worker:DoFile(DiscordLink.scriptRoot .. [[\DiscordLink_worker_init.lua]])
end

--------------------------------------------------------------
-- CALLBACKS

--[[------------------------------------------
		onMissionLoadBegin
--]]------------------------------------------
DiscordLink.onMissionLoadBegin = function()
	--if not DCS.isServer() or not DCS.isMultiplayer() then return end --TODO
	DiscordLink.safeCall(DiscordLink.doOnMissionLoadBegin)
end

--[[------------------------------------------
		doOnMissionLoadBegin
--]]------------------------------------------
DiscordLink.doOnMissionLoadBegin = function()
	DiscordLink.loadConfiguration()
	local log_file_name = 'DCS_DiscordLink.log'
	
	local fulldir = DiscordLink.config.directory.."\\"
	
	DiscordLink.currentLogFile = io.open(fulldir .. log_file_name, "w")
	DiscordLink.log("Mission "..DCS.getMissionName().." loading",DiscordLink.currentLogFile)

end

--[[------------------------------------------
		onMissionLoadBegin
--]]------------------------------------------
DiscordLink.onMissionLoadEnd = function()
	--if not DCS.isServer() or not DCS.isMultiplayer() then return end --TODO
	DiscordLink.safeCall(DiscordLink.doOnMissionLoadEnd)
end

--[[------------------------------------------
		doOnMissionLoadEnd
--]]------------------------------------------
DiscordLink.doOnMissionLoadEnd = function()
	DiscordLink.log("Mission "..DCS.getMissionName().." loaded",DiscordLink.currentLogFile)
	
end

--[[------------------------------------------
		onPlayerConnect
--]]------------------------------------------
DiscordLink.onPlayerConnect = function(id)
	--if not DCS.isServer() or not DCS.isMultiplayer() then return end
	DiscordLink.safeCall(DiscordLink.doOnPlayerConnect,{id})
end

--[[------------------------------------------
		doOnPlayerConnect
--]]------------------------------------------
DiscordLink.doOnPlayerConnect = function(id)
	local name = DiscordLink.getPlayerName(id)
	--local ucid = DiscordLink.getPlayerUcid(id)
	
	DiscordLink.players[name] = name

	local existingInd = DiscordLink.msgPartLookup.player[name]
	local revLookupEntry = {DiscordLink.msgPartCat.player, name}

	if  existingInd == nil then
		DiscordLink.msgPartRevLookup[DiscordLink.nextMsgPartId] = revLookupEntry
		DiscordLink.msgPartLookup.player[name] = DiscordLink.nextMsgPartId
		DiscordLink.nextMsgPartId = DiscordLink.nextMsgPartId + 1
	end

	DiscordLink.pushLookupPart("player")

	DiscordLink.log("Player ".. name .. " added")
end

--[[------------------------------------------
		onSimulationStop
--]]------------------------------------------
DiscordLink.onSimulationStop = function()
	--if not DCS.isServer() or not DCS.isMultiplayer() then return end
	DiscordLink.safeCall(DiscordLink.doOnSimulationStop)
end

--[[------------------------------------------
		doOnSimulationStop
--]]------------------------------------------
DiscordLink.doOnSimulationStop = function()

	DiscordLink.worker:Stop()

	for i = 1,100 do
		local s = LuaWorker.PopLogLine()
		if s == nil then break end
		DiscordLink.log(s)		
	end
end

--[[------------------------------------------
		onSimulationStart
--]]------------------------------------------
DiscordLink.onSimulationStart = function()
	--if not DCS.isServer() or not DCS.isMultiplayer() then return end
	DiscordLink.safeCall(DiscordLink.doOnSimulationStart)
end

--[[------------------------------------------
		doOnSimulationStart
--]]------------------------------------------
DiscordLink.doOnSimulationStart = function()
	DiscordLink.reloadTemplates()
	DiscordLink.pushLookup()
	DiscordLink.log(net.get_player_list())

	DiscordLink.EnsureLuaWorker()
end

--[[------------------------------------------
		onSimulationFrame
--]]------------------------------------------
DiscordLink.onSimulationFrame = function()
	if DiscordLink.pollFrameTime > DiscordLink.config.framesPerPoll then
		--if not DCS.isServer() or not DCS.isMultiplayer() then return end -- TODO Test
		DiscordLink.pollFrameTime = 0
		
		DiscordLink.log(DiscordLink.popAndSendAll())

		--DiscordLink.log(DiscordLink.text)
		return
	else if DiscordLink.pollFrameTime == 111 and DiscordLink.worker ~= nil -- Spread work between frames (avoid round numbers)
		for i = 1,100 do
			local s = DiscordLink.worker:PopLogLine()
			if s == nil then break end
			DiscordLink.log(s)		
		end
	end

	DiscordLink.pollFrameTime = DiscordLink.pollFrameTime + 1
end

--------------------------------------------------------------
-- INIT METHOD CALLS
--------------------------------------------------------------

--[[-------------------------------------------------
		Get connection strings
--]]-------------------------------------------------
DiscordLink.safeCall(
    function()
        local envVar = os.getenv(DiscordLink.config.channelEnv)
        if envVar == nil then return end

        for k,v in string.gmatch(envVar,"([^;]+)=([^;]+);?") do
            --DiscordLink.log(k.." "..v)
            DiscordLink.webhooks[k] = v
        end
    end)

--[[-------------------------------------------------
		Add default functions to be called
		to populate template
--]]-------------------------------------------------
DiscordLink.addDefaultFuncs()

--[[-------------------------------------------------
		Register callbacks
--]]-------------------------------------------------
DCS.setUserCallbacks(DiscordLink)

