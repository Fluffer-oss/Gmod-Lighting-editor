LightingEditor = LightingEditor or {}
local LE = LightingEditor

LE.Config = {
    -- How much light a section without power loses (0 = none, 1 = pitch black).
    -- Flashlights inside a dark section are dimmed by the same amount.
    DarkLevel = 0.82,

    -- Emergency lighting: a slow red pulse over the whole section, plus red
    -- glows on the room's real light fixtures (read from the map file).
    EmergencyColor = Color(255, 24, 12),
    EmergencyTint = 0.10,          -- strength of the red wash at the top of a pulse
    PulsePeriod = 2.4,             -- seconds per pulse
    FixtureGlowSize = 22,
    MaxFixtureGlows = 64,
    MaxEmergencyLights = 6,        -- real dynamic lights at the nearest fixtures
    EmergencyLightSize = 220,

    -- Transitions.
    FlickerOutTime = 1.4,          -- lights stutter before dying
    FadeOutTime = 1.0,
    FlickerInTime = 0.9,           -- lights struggle back on
    FadeInTime = 0.6,

    -- Only the nearest few dark sections are drawn, as cheap as that is.
    MaxSectionsDrawn = 6,
    SectionDrawDistance = 3000,
    BoxPadding = 4,                -- grows each section box so its faces sit behind the walls

    Sounds = {
        Out = "ambient/energy/spark6.wav",
        Restore = "buttons/button1.wav"
    },
    SoundDistance = 1200
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
