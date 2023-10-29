Webhooker.Server.addTemplate("example","default",[[{"username":"ExampleBot","content":"Hello from template %% %1  %2 "}]])

Webhooker.Server.addFunc("int",function(rawArg)
	return tostring(Webhooker.Server.argToNum(rawArg))
end)

Webhooker.Server.addFunc("list",function(...)

	local first = true
	local ret = ""

	for i,v in arg do
		if not first then
			ret = ret .. ', '
		end
		ret = ret .. Webhooker.Server.argToString(v)
		first = false
	end

	return ret
end)

Webhooker.Server.addFunc("time",function(...)
	return tostring(Webhooker.Server.argToNum(rawArg)) -- TODO
end)

Webhooker.Server.addString("substringTest","substring")