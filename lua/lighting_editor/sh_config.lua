LightingEditor = LightingEditor or {}
local LE = LightingEditor

LE.Config = {
    -- How much light a deck without power loses (0 = none, 1 = pitch black).
    -- Flashlights are unaffected.
    DarkLevel = 0.92,

    -- How a light fixture goes out: "glow" blacks out only its glowing parts
    -- (anything brighter than GlowThreshold, 0-1, and whatever the material
    -- marks as self-illuminated), keeping frames and detail; "black" blacks
    -- out the whole texture.
    GlowOff = "glow",
    GlowThreshold = 0.7,

    -- Light fixtures: these materials go out when the power is out,
    -- wherever they're used. Copies the map compiler made for cubemaps
    -- ("maps/<map>/<name>_x_y_z") count as the same material.
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

    -- Materials never touched: the sky, tool textures, and anything with
    -- these patterns in its name (Lua patterns). Add your hull's exterior
    -- materials here if any of them get darkened.
    KeepMaterials = { "^skybox/", "^tools/", "exterior", "^models/kingpommes/startrek/intrepid/core_effect$" },
    -- Entity classes never touched (STM's own light sources and things drawn separately).
    KeepClasses = {
        force_field = true, player = true, viewmodel = true, gmod_hands = true,
        env_sprite = true, env_lightglow = true, env_glow = true, beam = true, env_beam = true
    },

    -- Surfaces, props and entities this close to a section box count as inside
    -- the ship. Everything further out (the hull's outside, the skybox, STM's
    -- exterior) is left alone. A world material is darkened if at least half its
    -- area is inside.
    InteriorDistance = 96,

    -- Finding everything to darken happens in the background after joining,
    -- this many seconds per frame at most, so it never causes a hitch.
    ScanBudget = 0.002,

    -- Light sources that keep shining in the dark (STM keeps them powered).
    -- Each gives off real dynamic light; the nearest few are lit.
    Emitters = {
        MaxLights = 12,
        Distance = 2000,
        -- In the dark their light is raised to show, up to this many times.
        -- Static props can't receive dynamic light, so much more than this
        -- leaves them as black cutouts against brightly lit walls.
        MaxBoost = 2,
        -- LCARS screens: light the color of what they show, from their face,
        -- sized by the screen.
        LCARS = { Brightness = 0.6, RadiusPerUnit = 3, MinRadius = 48, MaxRadius = 220 },
        -- Force fields: light the color of their texture.
        ForceFields = { Brightness = 1.2, RadiusScale = 1.2, MinRadius = 80, MaxRadius = 300 }
    },

    -- Transitions.
    FlickerOutTime = 1.4,          -- lights stutter before dying
    FadeOutTime = 1.0,
    FlickerInTime = 0.9,           -- lights struggle back on
    FadeInTime = 0.6,
    DeckChangeTime = 0.5,          -- fade when walking (or riding) onto a deck with different power

    -- How far outside a deck's section boxes still counts as that deck
    -- (sections don't always cover every corridor).
    DeckPadding = 64,

    -- The map's own light entities on a deck without power are switched off
    -- (by the server, so everyone sees it): class -> the inputs that switch it
    -- off and on, and how to tell it's on; or "hide" for glows and sprites,
    -- which are hidden instead. Ones that were already off are left alone.
    MapLights = {
        light = { off = "TurnOff", on = "TurnOn", startsOff = 1 },  -- named (switchable) lights
        light_spot = { off = "TurnOff", on = "TurnOn", startsOff = 1 },
        light_dynamic = { off = "TurnOff", on = "TurnOn", state = "m_On" },
        env_projectedtexture = { off = "TurnOff", on = "TurnOn", state = "m_bState" },
        point_spotlight = { off = "LightOff", on = "LightOn", state = "m_bSpotlightOn" },
        env_sprite = "hide",
        env_sprite_oriented = "hide",
        env_lightglow = "hide",
        env_glow = "hide",
        beam = "hide",
        env_beam = "hide"
    },

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
