if Webhooker == nil then Webhooker = {} end

if Webhooker.msgPartLookup == nil then
    Webhooker.msgPartLookup = {templates = {}, strings = {}, players = {}, funcs = {} } -- Populated by Webhooker_server
end 

if Webhooker.config  == nil then
    Webhooker.config = 
	{
		userFlagRoot = "Webhooker"
	}
end

--[[------------------------------------------------------------------------
        Queue a formatted template webhook request to be sent

        args: 
            templateKey -   Template configured on the server to format 
                            and send
            args        -   Positional arguments to substitute in the 
                            template. 
                            Each has the format {msgPartLookupKey, {...}} 
                            where optional ... contains message parts
                            of the same format, or raw integers
--]]------------------------------------------------------------------------
Webhooker.send = function(templateKey, ...) 

    local i = 1
    local continue = true

    if Webhooker.msgPartLookup.templates == nil then return end

    local templateId = Webhooker.msgPartLookup.templates[templateKey]
    if templateId == nil then return end

    if templateId >= 0 then templateId = templateId + 2 end

    while continue do
        continue = false

        local userFlag = Webhooker.config.userFlagRoot .. "_" .. i

        local currentFlag = trigger.misc.getUserFlag(userFlag)

        if currentFlag == nil or currentFlag == 0 or currentFlag == 1 then -- boolean and unused flags are all available

            trigger.action.setUserFlag(userFlag,templateId)

            Webhooker.doSendArgs_(userFlag,unpack(arg))

            break
        end

        continue = true
        i = i + 1
    end
    
end

Webhooker.doSendArgs_ = function(rootFlagName, ...) 

    if arg == nil or #arg == 0 then 
        trigger.action.setUserFlag(rootFlagName .. "_1",false)
        return 
    end

    for i,v in ipairs(arg) do

        local userFlag = rootFlagName .. "_" .. i

        if type(v) =='number' then
            if v >= 0 then v = v + 2 end -- 0 and 1 are reserved boolean values

            trigger.action.setUserFlag(userFlag,v)
        elseif type(v) =='table' and #v > 0 then
            local handle = v[1]
            if handle >= 0 then handle = handle + 2 end
            trigger.action.setUserFlag(userFlag,handle)

            if type(v[2]) == 'table' then
                Webhooker.doSendArgs_(userFlag, unpack(v[2]))
            else
                Webhooker.doSendArgs_(userFlag)
            end
        else 
            trigger.action.setUserFlag(userFlag,true) -- invalid argument, add placeholder to indicate nil
        end
    end

    trigger.action.setUserFlag(rootFlagName .. "_" .. (#arg + 1),false) -- end of arguments
end

------------------------------------------------------------------
-- Arg constructions

--[[------------------------------------------------------------------------
        Format function for inclusion 
        in send request

        returns: {msgPartLookupKey, {func args...}}
--]]------------------------------------------------------------------------
Webhooker.func = function(funcKey, ...)
    local argPack = nil

    if arg ~= nil and #arg > 0 then
        argPack = arg
    end

    return {Webhooker.msgPartLookup.funcs[funcKey],argPack}
end

--[[------------------------------------------------------------------------
        Format string for inclusion 
        in send request

        returns: {msgPartLookupKey}
--]]------------------------------------------------------------------------
Webhooker.string = function(stringKey)
    return Webhooker.msgPartLookup.strings[stringKey]
end

--[[------------------------------------------------------------------------
        Format player name for inclusion 
        in send request

        returns: {msgPartLookupKey}
--]]------------------------------------------------------------------------
Webhooker.player = function(playerKey)
    return Webhooker.msgPartLookup.players[playerKey]
end