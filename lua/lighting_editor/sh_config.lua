LightingEditor = LightingEditor or {}
local LE = LightingEditor

LE.Config = {
    -- How much of the map's baked light is lost on a deck without power
    -- (0 = none, 1 = pitch black). Flashlights are unaffected.
    DarkLevel = 0.92,

    -- Light fixtures: these materials go fully black when the power is out.
    LightMaterials = {
        "models/kingpommes/startrek/intrepid/light_white",
        "models/kingpommes/startrek/intrepid/bridge_pillar_glow",
        "models/kingpommes/startrek/intrepid/light_engineering",
        "models/kingpommes/startrek/intrepid/sickbay_wall_light",
        "models/kingpommes/startrek/intrepid/transporter_wall_light",
        "models/kingpommes/startrek/intrepid/light_bridge_ceiling",
        "kingpommes/startrek/intrepid/eng_floorlight",
        "models/shiny",
        "lights/white",
        "kingpommes/startrek/intrepid/floormap/light_ceiling_01",
        "kingpommes/startrek/intrepid/floormap/light_ceiling_02",
        "kingpommes/startrek/intrepid/light_white",
        "kingpommes/startrek/intrepid/wall_corrigated"
    },

    -- Players, props and other models on a dark deck are lit by only this much
    -- ambient light (0-1). Set DarkenModels = false to leave them alone.
    DarkenModels = true,
    ModelLight = 0.04,

    -- Transitions.
    FlickerOutTime = 1.4,          -- lights stutter before dying
    FadeOutTime = 1.0,
    FlickerInTime = 0.9,           -- lights struggle back on
    FadeInTime = 0.6,
    DeckChangeTime = 0.5,          -- fade when walking (or riding) onto a deck with different power

    -- How far outside a deck's section boxes still counts as that deck
    -- (sections don't always cover every corridor).
    DeckPadding = 64,

    Sounds = {
        Out = "ambient/energy/spark6.wav",
        Restore = "buttons/button1.wav"
    }
}

LE.NetState = "LightingEditor.Outages"
LE.NetRequest = "LightingEditor.Request"

-- Admins and superadmins; also LeopardRP's "administrator" rank when that schema is loaded.
function LE.CanControl(ply)
    if not IsValid(ply) then return true end -- server console
    if ply:IsAdmin() then return true end

    local admin = LeopardRP and LeopardRP.Administration
    if admin and admin.GetPermissionRank and admin.HasRankAtLeast then
        local ok, allowed = pcall(function()
            return admin.HasRankAtLeast(admin.GetPermissionRank(ply:SteamID64()), "administrator")
        end)
        return ok and allowed == true
    end

    return false
end
