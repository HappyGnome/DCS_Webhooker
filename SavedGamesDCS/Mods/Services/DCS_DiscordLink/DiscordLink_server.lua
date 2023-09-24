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
		framesPerPoll = 600
	},
	-- logString = [[			
	-- 	obj2str = function(obj, antiCirc,maxdepth)
	-- 		if maxdepth<=0 then
	-- 			return "#"
	-- 		end
	-- 		if obj == nil then 
	-- 			return '??'
	-- 		end
	-- 		if antiCirc == nil then 
	-- 			antiCirc = {}
	-- 		end
	-- 		local msg = ''
	-- 		local t = type(obj)
	-- 		if t == 'table' then
	-- 			antiCirc[#antiCirc+1] = obj
	-- 			msg = msg..'{'
	-- 			for k,v in pairs(obj) do
	-- 				local t = type(v)
	-- 				local dup = false

	-- 				for _,prevObj in ipairs(antiCirc) do
	-- 					if prevObj == v then
	-- 						dup = true
	-- 						break
	-- 					end
	-- 				end
	-- 				if dup == false then
	-- 					msg = msg..obj2str(k,antiCirc,maxdepth -1)..':'..obj2str(v,antiCirc,maxdepth-1)..', '
	-- 				end
	-- 			end
	-- 			msg = msg..'}'pushLookup
	-- 		elseif t == 'number' or t == 'string' then
	-- 			msg = msg..obj
	-- 		elseif t == 'boolean' then
	-- 			if t then
	-- 				msg = msg..'true'
	-- 			else
	-- 				msg = msg..'false'
	-- 			end
	-- 		elseif t then
	-- 			msg = msg..t
	-- 		end
	-- 		return msg
	-- 	end

	-- 	return obj2str(_G,nil,2)]]},

	logFile = io.open(lfs.writedir()..[[Logs\DCS_DiscordLink.log]], "w"),
	currentLogFile = nil,
	pollFrameTime = 0,
    webhooks = {},
	templates = {}, -- key = template handle, value = {}
	strings = {},
	players = {},
	funcs = {},
	nextMsgPartId = 1,

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

package.cpath = package.cpath..";"..DiscordLink.scriptRoot..[[\https\?.dll;]]
package.path = package.path..";"..DiscordLink.scriptRoot..[[\https\?.lua;]]
local https = nil

-----------------------------------------------------------
-- CONFIG & UTILITY

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

DiscordLink.obj2str = function(obj)
    if obj == nil then 
        return '??'
    end
	local msg = ''
	local t = type(obj)
	if t == 'table' then
		msg = msg..'{'
		for k,v in pairs(obj) do
			local t = type(v)
			if type(k) == "string" then k = '"' .. k .. '"' end
			msg = msg.. '[' .. k..'] = '..DiscordLink.obj2str(v)..', '
		end
		msg = msg ..'}'
	elseif t == 'string' then
		msg = msg .. '"' .. obj .. '"'
	elseif t == 'number' then
		msg = msg .. obj
	elseif t == 'boolean' then
		if obj then
			msg = msg .. "true"
		else
			msg = msg .. "false"
		end
	elseif t then
		msg = msg .. t
	end
	return msg
end

function DiscordLink.loadConfiguration()
    DiscordLink.log("Config load starting")
	
    local cfg = tools.safeDoFile(lfs.writedir()..'Config/DiscordLink.lua', false)
	
    if (cfg and cfg.config) then
		for k,v in pairs(DiscordLink.config) do
			if cfg.config[k] ~= nil then
				DiscordLink.config[k] = cfg.config[k]
			end
		end        
    end
	
	DiscordLink.saveConfiguration()
end

function DiscordLink.saveConfiguration()
    U.saveInFile(DiscordLink.config, 'config', lfs.writedir()..'Config/DiscordLink.lua')
end

--error handler for xpcalls
DiscordLink.catchError=function(err)
	DiscordLink.log(err)
end 

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

DiscordLink.formatInteger = function(pack)
	--TODO tidy
	return pack[1]
end

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
DiscordLink.addDefaultFuncs()

--------------------------------------------------------------
-- LOAD TEMPLATES

-- Server-side API
DiscordLink.addTemplate=function(templateKey,webhookKey,username,content)
	DiscordLink.templates[templateKey] = {
		webhookKey = webhookKey,
		username = username,
		content = content
	}
end

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

DiscordLink.pushLookupPart = function(msgPartCat)
	local execString = 
	[[
		a_do_script(
		[=[ -- Executed in mission scripting environment
			if DiscordLink == nil then DiscordLink = {} end 
			DiscordLink.msgPartLookup["]] .. msgPartCat .. [["] = ]]

	execString = execString .. DiscordLink.obj2str(DiscordLink.msgPartLookup[msgPartCat])

	execString = execString .. [[]=])]]

	DiscordLink.log(execString)
	net.dostring_in(DiscordLink.scrEnvMission, execString)
	DiscordLink.log(msgPartCat .. " lookup pushed")
end

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

DiscordLink.popMessages = function()
	local i = 1
	while i < 200 do
		local userFlag = DiscordLink.config.userFlagRoot..i
		local execString = 
		[[
			-- Executed server mission scripting environment
			return(trigger.misc.getUserFlag("]]..userFlag..[["))
		]]
	
		local resultRaw = net.dostring_in(DiscordLink.scrEnvServer, execString)
		DiscordLink.log({result, type(result)})

		local result = tonumber(resultRaw)
		if result == nil or result == 0 then -- 0 used for boolean false (end of messages)
			break 
		elseif result ~= 1 then -- 1 used for boolean true (skip message)
			local templateKey = DiscordLink.msgPartRevLookup[result]
			if templateKey ~= nil and templateKey[1] == DiscordLink.msgPartCat.template then
				DiscordLink.msgQueue[#DiscordLink.msgQueue + 1] = {
					template = templateKey[2], 
					args = DiscordLink.popMessagesRecurse(userFlag,1),
					sendCount = 0,
					lastSent = nil
				}
			else
				DiscordLink.log("Invalid template handle: " .. result)
			end
		end

		-- clear flag
		execString = 
		[[
			-- Executed server mission scripting environment
			trigger.action.setUserFlag("]]..userFlag..[[",true)
		]]
	
		net.dostring_in(DiscordLink.scrEnvServer, execString)

		i = i + 1
	end
end

DiscordLink.popMessagesRecurse = function(userFlagRoot,recurseLevel)
	local ret = nil
	if recurseLevel > 4 then return ret end

	local i = 1
	while i < 200 do
		local userFlag = userFlagRoot.."_"..i
		local execString = 
		[[
			-- Executed server mission scripting environment
			return(trigger.misc.getUserFlag("]]..userFlag..[["))
		]]
	
		local resultRaw = net.dostring_in(DiscordLink.scrEnvServer, execString)
		DiscordLink.log({result, type(result)})

		local result = tonumber(resultRaw)
		if result == nil or result == 0  or result == 1 then 
			break 
		elseif result > 0 then
			result = result - 2
		end
		
		if not ret then ret = {} end

		local args = DiscordLink.popMessagesRecurse(userFlag,recurseLevel+1)
		ret[#ret + 1] = {
			handle = result,
			args = args
		}

		-- clear flag
		execString = 
		[[
			-- Executed server mission scripting environment
			trigger.action.setUserFlag("]]..userFlag..[[",true)
		]]

		net.dostring_in(DiscordLink.scrEnvServer, execString)

		i = i + 1
	end

	return ret
end

--------------------------------------------------------------
-- LOAD HTTPS

DiscordLink.safeCall(
    function()
        https = require("https")
        net.log("Loaded https")
    end)

--------------------------------------------------------------
-- GET CONNECTION STRINGS

DiscordLink.safeCall(
    function()
        local envVar = os.getenv(DiscordLink.config.channelEnv)
        if envVar == nil then return end

        for k,v in string.gmatch(envVar,"([^;]+)=([^;]+);?") do
            --DiscordLink.log(k.." "..v)
            DiscordLink.webhooks[k] = v
        end
    end)

--------------------------------------------------------------
-- MAIN LOOP LOGIC

DiscordLink.TrySendToWebhook = function (webhook,username,content)
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

	DiscordLink.log("Body" .. body)
	local source = ltn12.source.string(body)

	DiscordLink.log("SourceCreated")

    local T, code, headers, status =  https.request({url = webhookUrl,
        method = "POST",
        headers={["Content-Type"] = "application/json",
                ["Content-Length"] = string.len(body)},
		source = source})


    if T == nil or code == nil or code < 200 or code >= 300 then
        if code == nil then code = "??" end
        DiscordLink.log("Failed to Call Discord. Http Status: " .. code)
		return false
    end

	return true
end

DiscordLink.SendQueuedMessage = function(queueItem)

	if queueItem.compiledMessage == nil then
		queueItem.compiledMessage = DiscordLink.MakeMsgContent(queueItem)
	end

	local template = DiscordLink.templates[queueItem.template]

	if template == nil then
		DiscordLink.log("Template not found: " .. template)
		return false
	end 

	return DiscordLink.TrySendToWebhook(template.webhookKey,template.username, queueItem.compiledMessage)
end

DiscordLink.PopAndSendAll = function ()
    DiscordLink.popMessages()

	local retryCuttoff = os.time() - DiscordLink.config.retrySendSeconds

	for k,v in pairs(DiscordLink.msgQueue) do

		if v.lastSent == nil or v.lastSent < retryCuttoff then
			if DiscordLink.SendQueuedMessage(v) then
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

DiscordLink.MakeMsgContent = function (msgData)

	if msgData == nil then return nil end

	local template = DiscordLink.templates[msgData.template]

	local rawTemplate = template.content

	local subStrings = {}
	if msgData.args ~= nil then
		for i,v in ipairs(msgData.args) do
			subStrings[i] = DiscordLink.msgArgToString(v.handle, v.args) 
		end
	end

	DiscordLink.log({"Replacement substrings", subStrings})

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
				DiscordLink.log("Substring not found for  \"" .. tok .. "\"")
				return nil
			end
			finalText = finalText .. substring 
		end
	end
	return finalText
end

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
-- CALLBACKS

DiscordLink.onMissionLoadBegin = function()
	--if not DCS.isServer() or not DCS.isMultiplayer() then return end --TODO
	DiscordLink.safeCall(DiscordLink.doOnMissionLoadBegin)
end

DiscordLink.doOnMissionLoadBegin = function()
	DiscordLink.loadConfiguration()
	local log_file_name = 'DCS_DiscordLink.log'
	
	local fulldir = DiscordLink.config.directory.."\\"
	
	DiscordLink.currentLogFile = io.open(fulldir .. log_file_name, "w")
	DiscordLink.log("Mission "..DCS.getMissionName().." loading",DiscordLink.currentLogFile)

end

DiscordLink.onMissionLoadEnd = function()
	--if not DCS.isServer() or not DCS.isMultiplayer() then return end --TODO
	DiscordLink.safeCall(DiscordLink.doOnMissionLoadEnd)
end

DiscordLink.doOnMissionLoadEnd = function()
	DiscordLink.log("Mission "..DCS.getMissionName().." loaded",DiscordLink.currentLogFile)
	
end

DiscordLink.onPlayerConnect = function(id)
	--if not DCS.isServer() or not DCS.isMultiplayer() then return end
	DiscordLink.safeCall(DiscordLink.doOnPlayerConnect,{id})
end

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

DiscordLink.onSimulationStop = function()
	if not DCS.isServer() or not DCS.isMultiplayer() then return end
	DiscordLink.safeCall(DiscordLink.doOnSimulationStop)
end

DiscordLink.doOnSimulationStop = function()
	DiscordLink.log(net.get_player_list())
end

DiscordLink.onSimulationStart = function()
	--if not DCS.isServer() or not DCS.isMultiplayer() then return end
	DiscordLink.safeCall(DiscordLink.doOnSimulationStart)
end

DiscordLink.doOnSimulationStart = function()
	DiscordLink.reloadTemplates()
	DiscordLink.pushLookup()
	DiscordLink.log(net.get_player_list())
end

DiscordLink.onGameEvent = function(event)
	-- DiscordLink.log(event)
	-- if(event.id == S_EVENT_MARK_ADDED) then --world.event.
	-- 	DiscordLink.text = event.text
	-- end
end

DiscordLink.onSimulationFrame = function()
	if DiscordLink.pollFrameTime > DiscordLink.config.framesPerPoll then
		--if not DCS.isServer() or not DCS.isMultiplayer() then return end -- TODO Test
		DiscordLink.pollFrameTime = 0
		
		DiscordLink.log(DiscordLink.PopAndSendAll())
			

		--DiscordLink.log(DiscordLink.text)
	else	
		DiscordLink.pollFrameTime = DiscordLink.pollFrameTime + 1
	end
end
--------------------------------------------------------------
DCS.setUserCallbacks(DiscordLink)

