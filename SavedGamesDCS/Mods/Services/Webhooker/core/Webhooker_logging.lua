--[[
   Copyright 2023 HappyGnome (https://github.com/HappyGnome)

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
--]]

require("Webhooker_serialization")

local string = require("string")
local os = require("os")
local lfs= require("lfs")

if Webhooker == nil then
    Webhooker = {}
end

Webhooker.Logging =
{
  logFile = io.open(lfs.writedir()..[[Logs\Webhooker.log]], "w")
}

Webhooker.Logging.changeFile = function(newFileName)
  if Webhooker.Logging.logFile then Webhooker.Logging.logFile:close() end
  Webhooker.Logging.logFile = io.open(lfs.writedir()..[[Logs\]]..newFileName, "w")
end

Webhooker.Logging.log = function(str, logFile, prefix)
  if not str and not prefix then 
      return
  end

  if not logFile then
    logFile = Webhooker.Logging.logFile
  end

  if logFile then
  local msg = ''
  if prefix then msg = msg..prefix end
  if str then
    if type(str) == 'table' then
      msg = msg..'{'
      for k,v in pairs(str) do
        local t = type(v)
        msg = msg..k..':'.. Webhooker.Serialization.obj2str(v)..', '
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
Webhooker.Logging.catchError=function(err)
	Webhooker.Logging.log(err)
end 

Webhooker.safeCall = function(func,...)
	local op = func
	if arg then 
		op = function()
			func(unpack(arg))
		end
	end
	
	xpcall(op,Webhooker.Logging.catchError)
end
