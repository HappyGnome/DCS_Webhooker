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

Webhooker.Server.addString(", ") -- list sep
Webhooker.Server.addString(" | ") -- table col sep