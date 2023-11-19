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

            Webhooker.doSendArgs_(userFlag,1,unpack(arg))

            break
        end

        continue = true
        i = i + 1
    end
    
end

-- Returns index under rootFlagName that was set to "end of args"
Webhooker.doSendArgs_ = function(rootFlagName, startIndex,...) 

    if arg == nil or #arg == 0 then 
        trigger.action.setUserFlag(rootFlagName .. "_" .. startIndex,false)
        return startIndex
    end

    local nextIdx = startIndex

    for i,v in ipairs(arg) do

        local userFlag = rootFlagName .. "_" .. nextIdx

        if type(v) =='number' then
            if v >= 0 then v = v + 2 end -- 0 and 1 are reserved boolean values

            trigger.action.setUserFlag(userFlag,v)
        elseif type(v) =='table' and v.unpack then
            nextIdx = Webhooker.doSendArgs_(rootFlagName, nextIdx, unpack(v)) - 1

        elseif type(v) =='table' and #v > 0 then -- function with args to unpack
            local handle = v[1]
            if handle >= 0 then handle = handle + 2 end
            trigger.action.setUserFlag(userFlag,handle)

            if type(v[2]) == 'table' then
                Webhooker.doSendArgs_(userFlag,1, unpack(v[2]))
            else
                Webhooker.doSendArgs_(userFlag,1)
            end
        else 
            trigger.action.setUserFlag(userFlag,true) -- invalid argument, add placeholder to indicate nil
        end

        nextIdx = nextIdx + 1
    end

    trigger.action.setUserFlag(rootFlagName .. "_" .. nextIdx,false) -- end of arguments

    return nextIdx
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

        returns: msgPartLookupKey
--]]------------------------------------------------------------------------
Webhooker.string = function(stringKey)
    return Webhooker.msgPartLookup.strings[stringKey]
end

--[[------------------------------------------------------------------------
        Format player name for inclusion 
        in send request

        returns: msgPartLookupKey
--]]------------------------------------------------------------------------
Webhooker.player = function(playerKey)
    if type(playerKey) == 'table' then
        local ret = {unpack = true}

        for i,v in ipairs(playerKey) do
            ret[i] = Webhooker.msgPartLookup.players[v]
        end

        return ret 
    end
    return Webhooker.msgPartLookup.players[playerKey]
end