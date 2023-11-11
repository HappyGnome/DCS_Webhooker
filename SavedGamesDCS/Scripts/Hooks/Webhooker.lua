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

--Hook to load Webhooker
local status, result = pcall(
  function() 
    local lfs=require('lfs');
    dofile(lfs.writedir()..[[Mods\Services\Webhooker\init.lua]]); 
  end,nil) 
 
if not status then
  net.log(result)
end