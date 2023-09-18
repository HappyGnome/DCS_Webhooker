net.log("DCS_DiscordLink Hook called")

local socket = require("socket")
local string = require("string")
local ltn12 = require("ltn12")
local tools = require('tools')
local os = require("os")
local U  = require('me_utilities')

DiscordLink = {
	config = {directory = lfs.writedir()..[[Logs\]]},
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
	-- 			msg = msg..'}'
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
    channelEnv = "DcsDiscordLinkWebhooks",
	templates = {},
	nextMsgPartId = 1,
	msgPartLookup = {templates = {}, strings={}}, -- key = string/handle, value = id
	msgPartRevLookup = {templates = {}, strings={}}, -- key = id, value = string/handle
	scriptRoot = lfs.writedir()..[[Mods\Services\DCS_DiscordLink]]
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
			msg = msg..k..':'..DiscordLink.obj2str(v)..', '
		end
		msg = msg..'}'
	elseif t == 'number' or t == 'string' or t == 'boolean' then
		msg = msg..obj
	elseif t then
		msg = msg..t
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

--error handler for xpcalls. wraps hitch_trooper.log_e:error
DiscordLink.catchError=function(err)
	DiscordLink.log(err)
end 

DiscordLink.safeCall = function(func,args)
	local op = func
	if args then 
		op = function()
			func(unpack(args))
		end
	end
	
	xpcall(op,DiscordLink.catchError)
end

--------------------------------------------------------------
-- LOAD TEMPLATES

DiscordLink.reloadTemplates = function()
	DiscordLink.templates = {}

	for fpath in lfs.dir(DiscordLink.scriptRoot..[[\messages]]) do
		if lfs.attributes(fpath,"mode") == "file" then
			dofile(fpath)			
		end
	end

	local templateLookup = {}
	local templateRevLookup = {}
	for k,v in pairs(DiscordLink.templates) do
		local existingInd = DiscordLink.msgPartLookup.templates[k]
		if  existingInd == nil then
			templateRevLookup[nextMsgPartId] = k
			templateLookup[k] = nextMsgPartId
			nextMsgPartId = nextMsgPartId + 1
		else
			templateRevLookup[existingInd] = k
			templateLookup[k] = existingInd
		end
	end
	DiscordLink.msgPartLookup.templates = templateLookup
	DiscordLink.msgPartRevLookup.templates = templateRevLookup
end

DiscordLink.pushLookup = function()
	local execString = [[a_do_script(
		[=[ -- Executed in mission scrripting environment
			if DiscordLink == nil then DiscordLink = {} end 
			DiscordLink.msgPartLookup = { ]]

	for k,v in pairs(DiscordLink.msgPartLookup) do
		execString = execString ..[[[']] .. k .. [[']={ ]]
		for l,w in pairs(v) do
			execString = execString .. [[[']] .. l ..[[']=]]..w..[[, ]]
		end
		execString = execString .. [[},]]
	end
		
	execString = execString ..[[}]=])]]

	net.dostring_in("server", execString)
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
        local envVar = os.getenv(DiscordLink.channelEnv)
        if envVar == nil then return end

        for k,v in string.gmatch(envVar,"([^;]+)=([^;]+);?") do
            --DiscordLink.log(k.." "..v)
            DiscordLink.webhooks[k] = v
        end
    end)

--------------------------------------------------------------
-- MAIN LOOP LOGIC

DiscordLink.SanitizeLiteralForJson = function(rawString)
    local ret = string.gsub(rawString,"\\","\\\\")
    ret = string.gsub(ret,"\"","\\\"")
    return ret
end

DiscordLink.TrySendToWebhook = function (webhook,username,content)
    if DiscordLink.webhooks[webhook] == nil then
        DiscordLink.log("Webhook "..webhook.." not found")
        return
    end
    local webhookUrl = "https://discord.com/api/webhooks/".. DiscordLink.webhooks[webhook]
    local body = [[{"content":"]] .. DiscordLink.SanitizeLiteralForJson (content) ..
                [[","username":"]] .. DiscordLink.SanitizeLiteralForJson (username) .. [["}]]

    local T, code, headers, status =  https.request({url = webhookUrl,
        method = "POST",
        headers={["Content-Type"] = "application/json",
                ["Content-Length"] = string.len(body)},
        source = ltn12.source.string(body)})


    if T == nil or code == nil or code < 200 or code >= 300 then
        if code == nil then code = "??" end
        DiscordLink.log("Failed to Call Discord. Http Status: " .. code)
    end
end


--TODO:
-- Queue message
-- Try send from queue
-- Retries and timeout
-- Rate limits
-- Polling mission environment

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

	DiscordLink.reloadTemplates()

	--DiscordLink.SimInit = false -- TODO
end

DiscordLink.onMissionLoadEnd = function()
	--if not DCS.isServer() or not DCS.isMultiplayer() then return end --TODO
	DiscordLink.safeCall(DiscordLink.doOnMissionLoadEnd)
end

DiscordLink.doOnMissionLoadEnd = function()
	DiscordLink.log("Mission "..DCS.getMissionName().." loaded",DiscordLink.currentLogFile)
	-- DiscordLink.log("Mission "..DCS.getMissionFilename().." loaded",DiscordLink.currentLogFile)
end

-- DiscordLink.onPlayerConnect = function(id)
-- 	if not DCS.isServer() or not DCS.isMultiplayer() then return end
-- 	DiscordLink.safeCall(DiscordLink.doOnPlayerConnect,{id})
-- end

-- DiscordLink.doOnPlayerConnect = function(id)
-- 	local name = DiscordLink.getPlayerName(id)
-- 	local ucid = DiscordLink.getPlayerUcid(id)
	
-- 	DiscordLink.log("Player connected: "..name..". Player ID: "..ucid,DiscordLink.currentLogFile)
-- end

-- DiscordLink.onPlayerDisconnect = function(id)
-- 	if not DCS.isServer() or not DCS.isMultiplayer() then return end
-- 	DiscordLink.safeCall(DiscordLink.doOnPlayerDisconnect,{id})
-- end

-- DiscordLink.doOnPlayerDisconnect = function(id)
-- 	local name = DiscordLink.getPlayerName(id)
-- 	local ucid = DiscordLink.getPlayerUcid(id)
	
-- 	local stats = {kills_veh = net.get_stat(id,net.PS_CAR),
-- 				   kills_air = net.get_stat(id,net.PS_PLANE),
-- 				   kills_sea = net.get_stat(id,net.PS_SHIP),
-- 				   landings = net.get_stat(id,net.PS_LAND),
-- 				   ejected = net.get_stat(id,net.PS_EJECT),
-- 				   crashed = net.get_stat(id,net.PS_CRASH)}
	
-- 	DiscordLink.log(stats,DiscordLink.currentLogFile, "Player disconnected: "..name..". Player ID: "..ucid.."\n")
-- end

-- DiscordLink.onPlayerChangeSlot = function(id)
-- 	if not DCS.isServer() or not DCS.isMultiplayer() then return end
-- 	DiscordLink.safeCall(DiscordLink.doOnPlayerChangeSlot,{id})
-- end

-- DiscordLink.doOnPlayerChangeSlot = function(id)
	
-- 	local name = DiscordLink.getPlayerName(id)
-- 	local ucid = DiscordLink.getPlayerUcid(id)
	
-- 	local sideId,slotId =  net.get_slot(id)
-- 	local slotData
-- 	if DiscordLink.slotLookup[sideId] then
-- 		slotData = DiscordLink.slotLookup[sideId][slotId]
-- 	end
-- 	DiscordLink.log(slotData,DiscordLink.currentLogFile, "Player changed slot: "..name..". Player ID: "..ucid..". \n")
-- end

DiscordLink.onSimulationStop = function()
	if not DCS.isServer() or not DCS.isMultiplayer() then return end
	DiscordLink.safeCall(DiscordLink.doOnSimulationStop)
end

DiscordLink.doOnSimulationStop = function()
	DiscordLink.log(net.get_player_list(),DiscordLink.currentLogFile)
end

-- DiscordLink.onSimulationStart = function()
-- 	if not DCS.isServer() or not DCS.isMultiplayer() then return end
-- 	DiscordLink.safeCall(DiscordLink.doOnSimulationStart)
-- end

-- DiscordLink.doOnSimulationStart = function()
-- 	DiscordLink.log(net.get_player_list(),DiscordLink.currentLogFile)
-- end

DiscordLink.onGameEvent = function(event)
	DiscordLink.log(event)
	if(event.id == S_EVENT_MARK_ADDED) then --world.event.
		DiscordLink.text = event.text
	end
end

DiscordLink.onSimulationFrame = function()
	if DiscordLink.pollFrameTime > 599 then
		--if not DCS.isServer() or not DCS.isMultiplayer() then return end -- TODO Test
		DiscordLink.pollFrameTime = 0
		
		--TODO Test
		-- local foo = net.dostring_in("mission", [[return a_do_script("if helms == nil then return \"No HeLMS\" else return \"HeLMS detected\" end")]])
		-- -- local foo = net.dostring_in("server", [[if myvar==true then  return "No HeLMS" else myvar=true return "HeLMS detected" end ]])
		-- --DiscordLink.log(foo)

		-- local foo = net.dostring_in("mission", [[if helms == nil then return "No HeLMS" else return "HeLMS detected" end]])
		-- DiscordLink.log(foo)
		
		foo = net.dostring_in("mission", DiscordLink.config.logString)
		DiscordLink.log(foo)

		foo = net.dostring_in("server", DiscordLink.config.logString)
		DiscordLink.log(foo)

		if not DiscordLink.SimInit then

			local initString = [[		
				DiscordLinkEventHandler  = { 
					onEvent = function(self,event)
						DiscordLinkEventHandler.text = event.text
						if(event.id == world.event.S_EVENT_MARK_CHANGE) then
							DiscordLinkEventHandler.text = event.text
						end
					end
				}
				world.addEventHandler(DiscordLinkEventHandler)
			]]
			local foo = net.dostring_in("server", initString)
			DiscordLink.log(foo)
			local foo = net.dostring_in("mission", initString)
			DiscordLink.log(foo)
			DiscordLink.SimInit= true
		else
			local readString = [[		
				if DiscordLinkEventHandler == nil then 
					return "??1"
				elseif DiscordLinkEventHandler.text == nil then
					return "??2"
				else 
					return DiscordLinkEventHandler.text
				end
			]]
			local foo = net.dostring_in("server", readString)
			DiscordLink.log(foo)
			local foo = net.dostring_in("mission", readString)
			DiscordLink.log(foo)
		end

		DiscordLink.log(DiscordLink.text)
	else	
		DiscordLink.pollFrameTime = DiscordLink.pollFrameTime + 1
	end
end
--------------------------------------------------------------
DCS.setUserCallbacks(DiscordLink)

