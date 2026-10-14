local BASE = "lighting_editor/"

if SERVER then
    AddCSLuaFile(BASE .. "sh_config.lua")
    AddCSLuaFile(BASE .. "sh_sections.lua")
    AddCSLuaFile(BASE .. "cl_maplights.lua")
    AddCSLuaFile(BASE .. "cl_outage.lua")
end

include(BASE .. "sh_config.lua")
include(BASE .. "sh_sections.lua")

if SERVER then
    include(BASE .. "sv_outage.lua")
else
    include(BASE .. "cl_maplights.lua")
    include(BASE .. "cl_outage.lua")
end
