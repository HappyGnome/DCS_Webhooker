--Hook to load DCS_Webhooker
local status, result = pcall(
  function() 
    local lfs=require('lfs');
    dofile(lfs.writedir()..[[Mods\Services\DCS_Webhooker\init.lua]]); 
  end,nil) 
 
if not status then
  net.log(result)
end