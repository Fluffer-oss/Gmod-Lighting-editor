local BASE = "lighting_editor/"

if SERVER then
    AddCSLuaFile(BASE .. "sh_config.lua")
    AddCSLuaFile(BASE .. "sh_sections.lua")
    AddCSLuaFile(BASE .. "cl_mapdata.lua")
    AddCSLuaFile(BASE .. "cl_materials.lua")
    AddCSLuaFile(BASE .. "cl_outage.lua")
    AddCSLuaFile(BASE .. "cl_emitters.lua")
end

include(BASE .. "sh_config.lua")
include(BASE .. "sh_sections.lua")

if SERVER then
    include(BASE .. "sv_outage.lua")
    include(BASE .. "sv_maplights.lua")
else
    include(BASE .. "cl_mapdata.lua")
    include(BASE .. "cl_materials.lua")
    include(BASE .. "cl_outage.lua")
    include(BASE .. "cl_emitters.lua")
end
