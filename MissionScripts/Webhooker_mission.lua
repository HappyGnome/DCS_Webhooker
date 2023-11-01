if Webhooker == nil then 
    Webhooker = {} 
else 
    return
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
    -- Content injected by server
end

------------------------------------------------------------------
-- Arg constructions

--[[------------------------------------------------------------------------
        Format function for inclusion 
        in send request

        returns: {msgPartLookupKey, {func args...}}
--]]------------------------------------------------------------------------
Webhooker.func = function(funcKey, ...)
    -- Content injected by server
end

--[[------------------------------------------------------------------------
        Format string for inclusion 
        in send request

        returns: {msgPartLookupKey}
--]]------------------------------------------------------------------------
Webhooker.string = function(stringKey)
    -- Content injected by server
end

--[[------------------------------------------------------------------------
        Format player name for inclusion 
        in send request

        returns: {msgPartLookupKey}
--]]------------------------------------------------------------------------
Webhooker.player = function(playerKey)
    -- Content injected by server
end