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