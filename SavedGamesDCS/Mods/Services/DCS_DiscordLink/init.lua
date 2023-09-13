
local socket = require("socket")
local ltn12 = require("ltn12")
local os = require("os")
--local debug= require('debug')

package.cpath = package.cpath..";"..lfs.writedir()..[[Mods\Services\DCS_DiscordLink\https\?.dll;]]
package.path = package.path..";"..lfs.writedir()..[[Mods\Services\DCS_DiscordLink\https\?.lua;]]
local https = nil

local _status, _result = pcall(function()
    https = require("https")
    net.log("Loaded https")
end)

if not https then
    net.log("Couldn't load https")
end

_status, _result = 
pcall( function()
        local ipLookupUrl = "https://discord.com/api/webhooks/1150508545293439027/2b9WEv_MC8Pz-ribq5bhC8QA3sg9NGUksJSvslriuS46SwQSFxabCBHtwgn72kMtU9H8"
local body= [[{"content":"Hello Discord4","username":"WebhookMessage"}]]

net.log("DiscordLoggerTest Called")
        local T, code, headers, status =  https.request({url = ipLookupUrl,
    method = "POST",
    headers={["Content-Type"] = "application/json",
            ["Content-Length"] = string.len(body)},
    source = ltn12.source.string(body)})


        if T == nil or code == nil or code < 200 or code >= 300 then
            if code == nil then code = "??" end
            net.log("Failed to Call Discord from "..ipLookupUrl..". Http Status: " .. code)
        end

if not T == nil  then
    net.log(T)
end
end)