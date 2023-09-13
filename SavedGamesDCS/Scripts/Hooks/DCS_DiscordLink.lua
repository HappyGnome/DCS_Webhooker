--Hook to load DCS_DiscordLink
local status, result = pcall(
  function() 
    local lfs=require('lfs');
    dofile(lfs.writedir()..[[Mods\Services\DCS_DiscordLink\init.lua]]); 
  end,nil) 
 
if not status then
  net.log(result)
end