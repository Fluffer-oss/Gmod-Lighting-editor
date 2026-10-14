LightingEditor = LightingEditor or {}
local LE = LightingEditor

LE.Config = {
    -- How much light a section without power loses (0 = none, 1 = pitch black).
    -- Flashlights inside a dark section are dimmed by the same amount.
    DarkLevel = 0.82,

    -- Transitions.
    FlickerOutTime = 1.4,          -- lights stutter before dying
    FadeOutTime = 1.0,
    FlickerInTime = 0.9,           -- lights struggle back on
    FadeInTime = 0.6,

    -- Darkness spreads this far past each section's boxes, fading out, since
    -- the boxes rarely cover a room exactly. More steps = smoother fade.
    BleedDistance = 128,
    BleedSteps = 4,

    BoxPadding = 4,                -- grows each section box so its faces sit behind the walls
    SectionDrawDistance = 8000,    -- dark sections further away than this aren't drawn
    MaxBoxesDrawn = 128,           -- the nearest this many section boxes are drawn

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
