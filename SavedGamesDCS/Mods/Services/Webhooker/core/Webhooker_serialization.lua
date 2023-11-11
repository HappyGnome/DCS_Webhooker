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

local string = require("string")

if Webhooker == nil then
    Webhooker = {}
end
Webhooker.Serialization = {}


--[[------------------------------------------
		Escape reserved characters within 
        a lua string
--]]------------------------------------------
Webhooker.Serialization.escapeLuaString = function (str) 
	return 
	string.gsub(string.gsub(string.gsub(string.gsub(str,"\\","\\\\")
														,"\"","\\\"")
														,"\n","\\n")
														, "\r","\\r")
end

--[[------------------------------------------
		Convert lua object to valid lua string
--]]------------------------------------------
Webhooker.Serialization.obj2str = function(obj, antiCirc,maxdepth)

	if maxdepth == nil then 
		maxdepth = 4 
	end

	if antiCirc == nil then 
		antiCirc = {}
	end

	if maxdepth<=0 then
		return "#"
	end

	if obj == nil then 
		return '??'
	end

	local msg = ''
	local t = type(obj)

	if t == 'table' then
		antiCirc[obj] = true

		msg = msg..'{'
		for k,v in pairs(obj) do
			local t = type(v)

            local keyType = type(k)
            if keyType == 'string' or keyType == 'number' then
                if not antiCirc[v] then
                    msg = msg .. "[" .. Webhooker.Serialization.obj2str(k,antiCirc,maxdepth -1) ..']=' .. Webhooker.Serialization.obj2str(v,antiCirc,maxdepth-1) .. ","
                end
            end
		end
		msg = msg..'}'
	elseif t == 'string' then
		msg = msg.."\"".. Webhooker.Serialization.escapeLuaString(obj) .."\""
	elseif t == 'number' then
		msg = msg..obj
	elseif t == 'boolean' then
		if t then
			msg = msg..'true'
		else
			msg = msg..'false'
		end
	end
	return msg
end

--[[------------------------------------------
		Convert lua object to valid json
--]]------------------------------------------
Webhooker.Serialization.obj2json = function(obj, antiCirc,maxdepth)

	if maxdepth == nil then 
		maxdepth = 4 
	end

	if antiCirc == nil then 
		antiCirc = {}
	end

	if maxdepth<=0 then
		return "#"
	end

	if obj == nil then 
		return '??'
	end

	local msg = ''
	local t = type(obj)

	if t == 'table' then
		antiCirc[obj] = true
		local first = true

		if #obj > 0 then -- Array or object
			msg = msg..'['
			for k,v in ipairs(obj) do
				local t = type(v)
				if not antiCirc[v] then
					if not first then 
						msg = msg .. ","
					end
					msg = msg .. Webhooker.Serialization.obj2json(v,antiCirc,maxdepth-1)
					first = false
				end
			end					
			msg = msg..']'
		else
			msg = msg..'{'
			for k,v in pairs(obj) do
				local t = type(v)

				local keyType = type(k)
				if keyType == 'string'  then
					if not antiCirc[v] then
						if not first then 
							msg = msg .. ","
						end
						msg = msg .. "\"".. Webhooker.Serialization.escapeLuaString(k) .."\":" .. Webhooker.Serialization.obj2json(v,antiCirc,maxdepth-1)
						first = false						
					end
				end
			end					
			msg = msg..'}'
		end

	elseif t == 'string' then
		msg = msg.."\"".. Webhooker.Serialization.escapeLuaString(obj) .."\""
	elseif t == 'number' then
		msg = msg..obj
	elseif t == 'boolean' then
		if t then
			msg = msg..'true'
		else
			msg = msg..'false'
		end
	end
	return msg
end