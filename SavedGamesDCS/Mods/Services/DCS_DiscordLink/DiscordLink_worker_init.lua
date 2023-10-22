
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

--------------------------------------------------------------
-- MAIN LOOP LOGIC

MessageQueue = {} -- value = {url,body,attempts, lastSent}

MakeWebhookCall_ = function (webhookUrl,body)

    --InLuaWorker.LogInfo("TrySendToWebhook started: " .. webhookUrl .." " .. body) 

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

CallAndRetry = function (webhookUrl,body)

    local delay  = 1000

    for i = 1,5 do 
        if MakeWebhookCall_(webhookUrl,body) then break end
        InLuaWorker.YieldFor(delay)
        delay = delay * 2
    end
end

InLuaWorker.LogInfo("DiscordLink_worker_init.lua run.")