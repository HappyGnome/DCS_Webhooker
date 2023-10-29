Webhooker.Server.addTemplate("example","default",[[{"username":"ExampleBot %3 ","content":"Hello from template  \nPercent: %% \n string: %1 \n int: %2 \n list: %4 "}]])

Webhooker.Server.addFunc("int",function(rawArg)
	return tostring(Webhooker.Server.argToNum(rawArg))
end)

Webhooker.Server.addFunc("list",function(sepHandle,...)

	local first = true
	local ret = ""

	local sep = Webhooker.Server.argToString(sepHandle)

	if arg == nil then return ret end

	for i,v in ipairs(arg) do
		if not first then
			ret = ret .. sep
		end
		ret = ret .. Webhooker.Server.argToString(v)
		first = false
	end

	return ret
end)

Webhooker.Server.addFunc("datetime",function()
	return os.date("%d/%m/%Y %X")
end)

Webhooker.Server.addString("substringTest","substring")
Webhooker.Server.addString(", ")