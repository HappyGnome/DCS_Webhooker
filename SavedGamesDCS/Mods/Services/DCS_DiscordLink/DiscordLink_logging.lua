require("DiscordLink_serialization")

local string = require("string")
local os = require("os")
local lfs= require("lfs")

if DiscordLink == nil then
    DiscordLink = {}
end

DiscordLink.Logging =
{
  logFile = io.open(lfs.writedir()..[[Logs\DCS_DiscordLink.log]], "w")
}

DiscordLink.Logging.log = function(str, logFile, prefix)
  if not str and not prefix then 
      return
  end

  if not logFile then
    logFile = DiscordLink.Logging.logFile
  end

  if logFile then
  local msg = ''
  if prefix then msg = msg..prefix end
  if str then
    if type(str) == 'table' then
      msg = msg..'{'
      for k,v in pairs(str) do
        local t = type(v)
        msg = msg..k..':'.. DiscordLink.Serialization.obj2str(v)..', '
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

--error handler for xpcalls
DiscordLink.Logging.catchError=function(err)
	DiscordLink.Logging.log(err)
end 

DiscordLink.safeCall = function(func,...)
	local op = func
	if arg then 
		op = function()
			func(unpack(arg))
		end
	end
	
	xpcall(op,DiscordLink.Logging.catchError)
end
