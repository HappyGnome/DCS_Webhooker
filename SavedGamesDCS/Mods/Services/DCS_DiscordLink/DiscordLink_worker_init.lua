
InLuaWorker.LogInfo("DiscordLink_worker_init.lua Starting.")
--InLuaWorker.LogInfo("scriptRoot set to " .. scriptRoot)

--package.cpath = package.cpath..";"..scriptRoot..[[\https\?.dll;]]
--package.path = package.path..";"..scriptRoot..[[\https\?.lua;]]

InLuaWorker.LogInfo("package.cpath = " .. package.cpath)


local string = require("string")
local ltn12 = require("ltn12")
local os = require("os")
require("url") -- defines socket.url, which socket.http looks for
http = require("http") -- socket.http
local https = require("https")

require("DiscordLink_serialization")

if DiscordLink == nil then
    DiscordLink = {}
end

DiscordLink.Worker = {}
--------------------------------------------------------------
-- Message formatting
--[[------------------------------------------
		Replace placeholders in template
		to generate webhook body
--]]------------------------------------------
DiscordLink.Worker.makeMsgContent = function (rawTemplate,subStrings)

	InLuaWorker.LogInfo("Formatting message " .. DiscordLink.Serialization.obj2str({rawTemplate,subStrings}))

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
--------------------------------------------------------------
-- SENDING METHODS

MessageQueue = {} -- value = {url,body,attempts, lastSent}

DiscordLink.Worker.MakeWebhookCall_ = function (webhookUrl,body)

    InLuaWorker.LogInfo("TrySendToWebhook started: " .. webhookUrl .." " .. body) 

	local source = ltn12.source.string(body)

    local T, code, headers, status =  
    https.request({ url = webhookUrl,
                    method = "POST",
                    headers={["Content-Type"] = "application/json",
                             ["Content-Length"] = string.len(body)},
                    source = source})


    if T == nil or code == nil or code < 200 or code >= 300 then
        if code == nil then code = "??" end
        InLuaWorker.LogInfo("Failed to Call Discord. Http Code: " .. code .. " Status: " .. status)
		return false
    end

	return true
end

DiscordLink.Worker.CallAndRetry = function (msgData)

    local delay  = 1000

    if msgData == nil then
        InLuaWorker.LogError("Missing msgData") 
    end
    
    if msgData.username == nil then
        InLuaWorker.LogError("Missing msgData.username") 
    end
    
    if msgData.webhook == nil then
        InLuaWorker.LogError("Missing msgData.webhook") 
    end
    
    if msgData.templateRaw == nil then
        InLuaWorker.LogError("Missing msgData.templateRaw") 
    end


    local bodyRaw = {
        username = msgData.username,
        content = DiscordLink.Worker.makeMsgContent(templateRaw,templateArgs)
    }

    local body= DiscordLink.Serialization.obj2json(bodyRaw)

    for i = 1,5 do 
        if MakeWebhookCall_(msgData.webhook,body) then break end
        InLuaWorker.YieldFor(delay)
        delay = delay * 2
    end
end

InLuaWorker.LogInfo("DiscordLink_worker_init.lua run.")