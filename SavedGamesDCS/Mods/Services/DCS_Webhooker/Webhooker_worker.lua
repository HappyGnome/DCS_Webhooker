
InLuaWorker.LogInfo("Webhooker_worker.lua Starting.")
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

require("Webhooker_serialization")

if Webhooker == nil then
    Webhooker = {}
end

Webhooker.Worker = {}
--------------------------------------------------------------
-- Message formatting
--[[------------------------------------------
		Replace placeholders in template
		to generate webhook body
--]]------------------------------------------
Webhooker.Worker.makeMsgContent = function (rawTemplate,subStrings)

	InLuaWorker.LogInfo("Formatting message " .. Webhooker.Serialization.obj2str({rawTemplate,subStrings}))

	local finalText = ""
	
	if rawTemplate == nil then return finalText end

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

			local substring = nil
			if subStrings ~= nil then 
				substring = subStrings[tonumber(tok)]
			end

			if substring == nil then
				substring = ""
				InLuaWorker.LogError("Substring not found for  \"" .. tok .. "\"")
				return nil
			end
			finalText = finalText .. substring 
		end
	end
	return finalText
end
--------------------------------------------------------------
-- SENDING METHODS

Webhooker.Worker.MakeWebhookCall_ = function (webhookUrl,body)

	if body == nil then body = "" end
    InLuaWorker.LogInfo("MakeWebhookCall_ started. Body: " .. body) 

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

Webhooker.Worker.CallAndRetry = function (msgData)

    local delay  = 1000

    if msgData == nil then
        InLuaWorker.LogError("Missing msgData") 
    end
    
    if msgData.webhook == nil or msgData.webhook == "" then
        InLuaWorker.LogError("Missing msgData.webhook") 
    end
    
    if msgData.templateRaw == nil or msgData.templateRaw == "" then
        InLuaWorker.LogError("Missing msgData.templateRaw") 
    end


    local body = Webhooker.Worker.makeMsgContent(msgData.templateRaw,msgData.templateArgs)

	if body == nil then return end

    for i = 1,5 do 
        if Webhooker.Worker.MakeWebhookCall_(msgData.webhook,body) then break end
        InLuaWorker.YieldFor(delay)
        delay = delay * 2
    end
end

InLuaWorker.LogInfo("Webhooker_worker.lua run.")