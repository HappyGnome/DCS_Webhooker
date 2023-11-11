--Hook to load Webhooker
local status, result = pcall(
  function() 
    local lfs=require('lfs');
    dofile(lfs.writedir()..[[Mods\Services\Webhooker\init.lua]]); 
  end,nil) 
 
if not status then
  net.log(result)
end