net.log("DCS_DiscordLinkLoader called")

local socket = require("socket")
local string = require("string")
local ltn12 = require("ltn12")
local tools = require('tools')
local os = require("os")
local U  = require('me_utilities')

DiscordLinkLoader ={
  logFile = io.open(lfs.writedir()..[[Logs\DCS_DiscordLinkLoader.log]], "w")
}

DiscordLinkLoader.log = function(str, logFile, prefix)
  if not str and not prefix then 
      return
  end

if not logFile then
  logFile = DiscordLinkLoader.logFile
end

  if logFile then
  local msg = ''
  if prefix then msg = msg..prefix end
  if str then
    if type(str) == 'table' then
      msg = msg..'{'
      for k,v in pairs(str) do
        local t = type(v)
        msg = msg..k..':'.. DiscordLinkLoader.obj2str(v)..', '
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

DiscordLinkLoader.obj2str = function(obj)
  if obj == nil then 
      return '??'
  end
local msg = ''
local t = type(obj)
if t == 'table' then
  msg = msg..'{'
  for k,v in pairs(obj) do
    local t = type(v)
    msg = msg..k..':'..DiscordLinkLoader.obj2str(v)..', '
  end
  msg = msg..'}'
elseif t == 'number' or t == 'string' or t == 'boolean' then
  msg = msg..obj
elseif t then
  msg = msg..t
end
return msg
end

--error handler for xpcalls
DiscordLinkLoader.catchError=function(err)
	DiscordLinkLoader.log(err)
end 

DiscordLinkLoader.safeCall = function(func,...)
	local op = func
	if arg then 
		op = function()
			func(unpack(arg))
		end
	end
	
	xpcall(op,DiscordLinkLoader.catchError)
end
--------------------------------------------------------------
-- CALLBACKS

DiscordLinkLoader.onMissionLoadBegin = function()
  net.log("Calling DiscordLink")
	DiscordLinkLoader.safeCall(
  function() 
    local lfs=require('lfs');
    dofile(lfs.writedir()..[[Mods\Services\DCS_DiscordLink\DiscordLink_server.lua]]); 
  end)
end

--------------------------------------------------------------
DCS.setUserCallbacks(DiscordLinkLoader)

