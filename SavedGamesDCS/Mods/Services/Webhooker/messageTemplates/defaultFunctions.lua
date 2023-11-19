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

Webhooker.Server.addFunc("int",function(rawArg)
	return tostring(Webhooker.Server.argToNum(rawArg))
end)

Webhooker.Server.addFunc("list",function(sepHandle,...)

	local first = true
	local ret = ""

	local sep = Webhooker.Server.argToString(sepHandle)

	if arg == nil or sep ==nil then return ret end

	for i,v in ipairs(arg) do
		if not first then
			ret = ret .. sep
		end
		ret = ret .. Webhooker.Server.argToString(v)
		first = false
	end

	return ret
end)

Webhooker.Server.addFunc("table",function(sepHandle,colsHandle,...)

	local ret = ""

	local sep = Webhooker.Server.argToString(sepHandle)
	local cols = Webhooker.Server.argToNum(colsHandle)

	if arg == nil or sep ==nil or cols == nil then return ret end

	local col = 0
	for i,v in ipairs(arg) do
		if col > 0 then
			ret = ret .. sep
		end
		ret = ret .. Webhooker.Server.argToString(v)

		col = col + 1
		
		if col >= cols then
			ret = ret .. "\\n"
			col = 0
		end		
	end

	-- complete last row
	while col < cols do
		ret = ret .. sep
		col = col + 1

		if col >= cols then
			ret = ret .. "\\n"
		end	
	end	

	return ret
end)

Webhooker.Server.addFunc("datetime",function()
	return os.date("%d/%m/%Y %X")
end)

Webhooker.Server.addFunc("playerCount",function()
	local list = net.get_player_list()
	if not list then
		return 0
	end

	return #list
end)

Webhooker.Server.addFunc("playerList",function()
	local playerIds = net.get_player_list()
	local ret = ""

	if not playerIds then return ret	end

	for i = 1,#playerIds do
		if i == #playerIds and i > 1 then
			ret = ret .. " and "
		elseif i > 1 then
			ret = ret .. ", "
		end
		ret = ret .. net.get_name(playerIds[i])
	end

	return ret
end)

------------------------------------------------------------------------
-- Strings

Webhooker.Server.addString(", ") -- list sep
Webhooker.Server.addString(" | ") -- table col sep