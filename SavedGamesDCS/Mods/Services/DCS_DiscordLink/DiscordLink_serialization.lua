local string = require("string")

if DiscordLink == nil then
    DiscordLink = {}
end
DiscordLink.Serialization = {}


--[[------------------------------------------
		Escape reserved characters within 
        a lua string
--]]------------------------------------------
DiscordLink.Serialization.escapeLuaString = function (str) 
	return 
	string.gsub(string.gsub(string.gsub(string.gsub(str,"\\","\\\\")
														,"\"","\\\"")
														,"\n","\\n")
														, "\r","\\r")
end

--[[------------------------------------------
		Convert lua object to valid lua string
--]]------------------------------------------
DiscordLink.Serialization.obj2str = function(obj, antiCirc,maxdepth)

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
                    msg = msg .. "[" .. DiscordLink.Serialization.obj2str(k,antiCirc,maxdepth -1) ..']=' .. DiscordLink.Serialization.obj2str(v,antiCirc,maxdepth-1) .. ","
                end
            end
		end
		msg = msg..'}'
	elseif t == 'string' then
		msg = msg.."\"".. DiscordLink.Serialization.escapeLuaString(obj) .."\""
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
DiscordLink.Serialization.obj2json = function(obj, antiCirc,maxdepth)

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
						first = false
					end
					msg = msg .. DiscordLink.Serialization.obj2json(v,antiCirc,maxdepth-1)
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
							first = false
						end
						msg = msg .. "\"".. DiscordLink.Serialization.escapeLuaString(k) .."\":" .. DiscordLink.Serialization.obj2json(v,antiCirc,maxdepth-1)
					end
				end
			end					
			msg = msg..'}'
		end

	elseif t == 'string' then
		msg = msg.."\"".. DiscordLink.Serialization.escapeLuaString(obj) .."\""
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