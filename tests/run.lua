HARNESS_DIR = arg[0]:match("^(.*/)") or "./"
package.path = HARNESS_DIR .. "?.lua;" .. package.path
local M = require("mock")
local F = require("files")
local V, Color = M.Vector, M.Color

local passed, failed = 0, 0
local function check(cond, label)
    if cond then passed = passed + 1 else failed = failed + 1 print("FAIL: " .. label) end
end
local function step(label, fn)
    local ok, err = pcall(fn)
    if not ok then failed = failed + 1 print("ERROR in '" .. label .. "': " .. tostring(err)) end
end
local function near(a, b) return a and b and math.abs(a - b) < 1e-4 end
local function vnear(v, x, y, z) return v and near(v.x, x) and near(v.y, y) and near(v.z, z) end

--------------------------------------------------------------------------------
-- The ship
--------------------------------------------------------------------------------

-- Star Trek Modules' section data, as synced to both realms.
-- Deck 1 (z 0..128): two sections with an uncovered corridor (x 512..768) between them.
-- Deck 2 (z 256..384): one section over the whole deck.
local function area(x1, y1, z1, x2, y2, z2) return { Min = V(x1, y1, z1), Max = V(x2, y2, z2) } end
local function MakeDecks()
    return {
        [1] = { Sections = {
            [100] = { RealId = "1", Name = "Bridge", Areas = { area(0, 0, 0, 512, 256, 128) } },
            [500] = { RealId = "5", Name = "Engineering", Areas = { area(768, 0, 0, 1024, 256, 128) } }
        } },
        [2] = { Sections = {
            [100] = { RealId = "1", Name = "Quarters", Areas = { area(0, 0, 256, 1024, 256, 384) } }
        } }
    }
end

local function quad(x, y, z, size) -- a floor tile centered on x, y
    local h = size / 2
    return { { x - h, y - h, z }, { x + h, y - h, z }, { x + h, y + h, z }, { x - h, y + h, z } }
end

local ALARM = "models/kingpommes/startrek/intrepid/light_alarm"
local BRIDGE_LIGHT = "models/kingpommes/startrek/intrepid/light_bridge_ceiling"
local CORRIGATED = "kingpommes/startrek/intrepid/wall_corrigated"
local SELFILLUM, ADDITIVE = 64, 128
local function tex(name, pixels, w) return M.Texture(name, w or (pixels and #pixels) or 0, pixels and 1 or 0, pixels) end
local WHITE, NAVY, GREY, YELLOW = { 1, 1, 1, 1 }, { 0.1, 0.2, 0.5, 1 }, { 0.5, 0.5, 0.5, 1 }, { 1, 0.9, 0.2, 0.5 }

-- The map's world faces: inside the ship (near a section), on the hull's
-- outside, and in the sky.
M.files["maps/rp_test.bsp"] = F.Map({
    { material = "maps/floor", verts = quad(100, 100, 0, 64), area = 4096 },
    { material = "maps/floor", verts = quad(600, 100, 0, 64), area = 4096 },     -- uncovered corridor: still inside
    { material = "maps/hull", verts = quad(500, -2000, 64, 64), area = 4096 },   -- outside the ship
    { material = "maps/mixed", verts = quad(200, 100, 128, 64), area = 3000 },   -- mostly inside: darkened
    { material = "maps/mixed", verts = quad(200, -3000, 0, 64), area = 1000 },
    { material = "maps/hullmostly", verts = quad(200, 100, 0, 64), area = 1000 }, -- mostly outside: left alone
    { material = "maps/hullmostly", verts = quad(200, -3000, 0, 64), area = 3000 },
    { material = "maps/glowstrip", verts = quad(300, 50, 128, 32) },
    { material = "maps/cubemapped", verts = quad(400, 200, 0, 32) },
    { material = "maps/water", verts = quad(450, 200, 0, 32) },
    { material = "maps/skyface", verts = quad(100, 100, 128, 32), flags = 0x4 }, -- sky: never drawn lit
    { material = "maps/nodraw", verts = quad(100, 100, 120, 32), flags = 0x80 },
    { material = CORRIGATED, verts = quad(800, 100, 128, 32) },
    -- A listed light fixture as the map compiler copies it for a cubemap.
    { material = "maps/rp_test/kingpommes/startrek/intrepid/eng_floorlight_120_-40_8", verts = quad(120, 60, 0, 32) },
    { material = "maps/rp_test/maps/hull_500_-2000_64", verts = quad(500, -2000, 64, 64) }, -- copy on the outside
    -- A listed fixture in a room far from any section box: goes out anyway.
    { material = "maps/rp_test/lights/white_2000_2000_64", verts = quad(2000, 2000, 64, 32) },
    { material = "maps/stairs", verts = { { 0, 0, 300 }, { 90, 0, 300 }, { 0, 90, 300 } } }
}, {
    { model = "models/props/console.mdl", pos = { 100, 100, 10 } },
    { model = "models/props/asteroid.mdl", pos = { 0, 0, -9000 } },              -- 3D skybox
    { model = "models/kingpommes/startrek/intrepid/alarm.mdl", pos = { 300, 100, 100 } },
    { model = "models/kingpommes/startrek/intrepid/alarm.mdl", pos = { 300, 900, 300 } } -- outside: no alarm here
})
M.files["models/props/console.mdl"] = F.Model({ "console", "console_screen" }, { "models\\props_old\\", "models\\props\\" })
M.files["models/props/asteroid.mdl"] = F.Model({ "asteroid" }, { "models/props/" })
M.files["models/kingpommes/startrek/intrepid/alarm.mdl"] = F.Model({ "light_alarm", "alarm_frame" }, { "models/kingpommes/startrek/intrepid/" })
M.files["materials/stm/forcefield.vtf"] = F.Texture(0.1, 0.3, 0.6)

M.materials = {
    ["maps/floor"] = { shader = "LightmappedGeneric", params = { ["$color"] = V(1, 1, 1), ["$basetexture"] = tex("maps/floor") } },
    ["maps/hull"] = { shader = "LightmappedGeneric", params = { ["$color"] = V(1, 1, 1) } },
    ["maps/mixed"] = { shader = "WorldVertexTransition", params = { ["$color"] = V(0.5, 0.8, 1) } },
    ["maps/hullmostly"] = { shader = "LightmappedGeneric", params = { ["$color"] = V(1, 1, 1) } },
    -- A wall with a glowing strip: the strip is marked in the texture's alpha.
    ["maps/glowstrip"] = { shader = "LightmappedGeneric", params = { ["$flags"] = SELFILLUM, ["$color"] = V(1, 1, 1),
        ["$basetexture"] = tex("maps/glowstrip", { { 1, 1, 0.8, 1 }, { 0.4, 0.4, 0.4, 0 }, { 1, 1, 1, 0 } }), ["$selfillumtint"] = V(1, 1, 1) } },
    ["maps/cubemapped"] = { shader = "LightmappedGeneric", params = { ["$envmap"] = "env_cubemap", ["$envmaptint"] = V(0.6, 0.6, 0.6) } },
    ["maps/water"] = { shader = "Water", params = { ["$color"] = V(1, 1, 1) } },
    ["maps/skyface"] = { shader = "LightmappedGeneric", params = {} },
    ["maps/nodraw"] = { shader = "LightmappedGeneric", params = {} },
    ["maps/stairs"] = { shader = "LightmappedGeneric", params = {} },
    ["maps/door"] = { shader = "LightmappedGeneric", params = { ["$color"] = V(1, 1, 1) } },
    -- Listed: its bright parts go black, the rest stays (and darkens like any wall).
    [CORRIGATED] = { shader = "LightmappedGeneric", params = { ["$color"] = V(1, 1, 1), ["$basetexture"] = tex(CORRIGATED, { WHITE, NAVY, GREY, YELLOW }) } },
    ["models/kingpommes/startrek/intrepid/core_effect"] = { shader = "UnlitGeneric", params = { ["$flags"] = ADDITIVE, ["$basetexture"] = tex("core_effect") } },
    ["models/props/door_label"] = { shader = "UnlitGeneric", params = { ["$flags"] = 2097152, ["$basetexture"] = tex("models/props/door_label") } },
    ["maps/rp_test/kingpommes/startrek/intrepid/eng_floorlight_120_-40_8"] = { shader = "LightmappedGeneric", params = { ["$basetexture"] = tex("kingpommes/startrek/intrepid/eng_floorlight"), ["$envmap"] = "maps/rp_test/c120_-40_8" } },
    ["maps/rp_test/lights/white_2000_2000_64"] = { shader = "UnlitGeneric", params = { ["$basetexture"] = tex("lights/white") } },
    ["maps/rp_test/maps/hull_500_-2000_64"] = { shader = "LightmappedGeneric", params = { ["$color"] = V(1, 1, 1) } },
    -- Listed, but on nothing the scan finds (a model only a map entity uses, say).
    ["models/kingpommes/startrek/intrepid/light_white"] = { shader = "VertexLitGeneric", params = { ["$basetexture"] = tex("models/kingpommes/startrek/intrepid/light_white") } },
    ["models/props/console"] = { shader = "VertexLitGeneric", params = { ["$phong"] = 1, ["$phongboost"] = 2, ["$envmap"] = "env_cubemap" } },
    ["models/props/console_screen"] = { shader = "VertexLitGeneric", params = { ["$flags"] = SELFILLUM, ["$basetexture"] = tex("models/props/console_screen") } },
    ["models/props/asteroid"] = { shader = "VertexLitGeneric", params = { ["$color2"] = V(1, 1, 1) } },
    ["models/props/door_metal"] = { shader = "VertexLitGeneric", params = { ["$color2"] = V(0.9, 0.9, 0.9) } },
    ["models/props/beam_cone"] = { shader = "VertexLitGeneric", params = { ["$flags"] = ADDITIVE, ["$basetexture"] = tex("models/props/beam_cone") } },
    ["models/planets/earth"] = { shader = "VertexLitGeneric", params = { ["$color2"] = V(1, 1, 1) } },
    ["models/stm/forcefield"] = { shader = "UnlitGeneric", params = { ["$basetexture"] = "stm/forcefield", ["$color"] = V(1, 1, 1) } },
    [ALARM] = { shader = "VertexLitGeneric", params = { ["$alarmcolor"] = V(0, 0, 0), ["$basetexture"] = tex(ALARM) } },
    ["models/kingpommes/startrek/intrepid/alarm_frame"] = { shader = "VertexLitGeneric", params = {} },
    -- Listed, with a separate self-illumination mask: masked or bright parts go black.
    [BRIDGE_LIGHT] = { shader = "VertexLitGeneric", params = { ["$flags"] = SELFILLUM, ["$brightness"] = 1, ["$color2"] = V(1, 1, 1),
        ["$basetexture"] = tex(BRIDGE_LIGHT, { { 0.3, 0.3, 0.3, 1 }, { 1, 1, 1, 1 }, { 0.3, 0.3, 0.3, 1 } }),
        ["$selfillummask"] = tex("lightmask", { { 1, 1, 1, 1 }, { 0, 0, 0, 1 }, { 0, 0, 0, 1 } }) } },
    ["lights/white"] = { shader = "UnlitGeneric", params = { ["$color"] = V(1, 1, 1) } } -- no texture
}
M.worldMaterials = { "maps/floor", "maps/hull", "lights/white" }

-- Client-side entities.
local function Ent(class, model, pos, materials, extra)
    local e = { __valid = true, class = class, model = model, pos = pos, materials = materials or {}, color = Color(255, 255, 255, 255) }
    function e:GetClass() return self.class end
    function e:GetModel() return self.model end
    function e:GetPos() return self.pos end
    function e:WorldSpaceCenter() return self.pos end
    function e:GetMaterials() return self.materials end
    function e:GetMaterial() return self.override or "" end
    function e:IsPlayer() return false end
    function e:GetNoDraw() return self.noDraw == true end
    function e:GetColor() return self.color end
    function e:OBBMins() return V(-64, -2, -64) end
    function e:OBBMaxs() return V(64, 2, 64) end
    for k, v in pairs(extra or {}) do e[k] = v end
    return e
end
local door = Ent("prop_dynamic", "models/props/door.mdl", V(256, 0, 64), { "models/props/door_metal", "models/props/door_label" })
local brushDoor = Ent("func_door", "*3", V(700, 128, 64), { "maps/door" })
local beam = Ent("prop_dynamic", "models/props/beam.mdl", V(200, 200, 100), {}, { override = "models/props/beam_cone" })
local field = Ent("force_field", "models/stm/forcefield.mdl", V(640, 128, 64), { "models/stm/forcefield" })
local planet = Ent("prop_dynamic", "models/planets/earth.mdl", V(0, 0, -20000), { "models/planets/earth" })
local lamp = Ent("prop_dynamic", "models/props/lamp.mdl", V(150, 150, 120), { BRIDGE_LIGHT, "lights/white" })
local core = Ent("prop_dynamic", "models/props/warpcore.mdl", V(900, 128, 64), { "models/kingpommes/startrek/intrepid/core_effect" })
M.entities = { door, brushDoor, beam, field, planet, lamp, core }

-- Server-side map light entities.
local function MapLight(class, name, pos, extra)
    local e = { __valid = true, class = class, name = name, pos = pos, fired = {}, flags = 0, vars = {} }
    function e:GetPos() return self.pos end
    function e:GetName() return self.name end
    function e:Fire(input) table.insert(self.fired, input) end
    function e:GetNoDraw() return self.noDraw == true end
    function e:SetNoDraw(v) self.noDraw = v end
    function e:HasSpawnFlags(f) return math.floor(self.flags / f) % 2 == 1 end
    function e:GetInternalVariable(k) return self.vars[k] end
    for k, v in pairs(extra or {}) do e[k] = v end
    return e
end
local bridgeLight = MapLight("light", "bridgeLights", V(100, 100, 120))
local darkLight = MapLight("light", "storeroom", V(800, 100, 120), { flags = 1 })        -- already off
local dynLight = MapLight("light_dynamic", "", V(200, 100, 120), { vars = { m_On = true } })
local deck2Lamp = MapLight("env_projectedtexture", "", V(100, 100, 350), { vars = { m_bState = true } })
local sprite = MapLight("env_sprite", "", V(300, 100, 120))
local hiddenSprite = MapLight("env_sprite", "", V(310, 100, 120), { noDraw = true })    -- hidden by the map
local spot = MapLight("point_spotlight", "", V(400, 100, 120), { vars = { m_bSpotlightOn = true } })
M.serverEntities = { bridgeLight, darkLight, dynLight, deck2Lamp, sprite, hiddenSprite, spot }

--------------------------------------------------------------------------------
-- Realms
--------------------------------------------------------------------------------

local admin = M.MakePlayer("admin", true)
local crew = M.MakePlayer("crewman", false)
local server, adminCl, crewCl, clients

local function STM(realm)
    realm.Star_Trek = {
        Sections = { Decks = MakeDecks() },
        Alert = {
            AlertMaterial = ALARM, BridgeDimName = "bridgeLights",
            AlertTypes = { red = { BridgeDim = true }, yellow = { BridgeDim = false } }
        },
        LCARS = {
            ColorOrange = Color(202, 151, 50), ColorRed = Color(197, 52, 54),
            ActiveInterfaces = {}
        }
    }
end

local function NewClient(ply)
    local realm = M.NewRealm(false, ply)
    STM(realm)
    realm.include("autorun/lighting_editor.lua")
    return realm
end

local function boot()
    M.pooled, M.queueToServer, M.queueToClients = {}, {}, {}
    server = M.NewRealm(true)
    STM(server)
    -- STM's server alert functions, switching the bridge lights like STM does.
    local alert = server.Star_Trek.Alert
    function alert:Enable(type)
        self.ActiveAlert = type
        bridgeLight:Fire(self.AlertTypes[type].BridgeDim and "turnOff" or "turnOn")
        return true
    end
    function alert:Disable()
        self.ActiveAlert = nil
        bridgeLight:Fire("turnOn")
        return true
    end
    server.include("autorun/lighting_editor.lua")
    adminCl, crewCl = NewClient(admin), NewClient(crew)
    clients = { [admin] = adminCl, [crew] = crewCl }
    adminCl.hook.Run("InitPostEntity")
    crewCl.hook.Run("InitPostEntity")
    M.Pump(server, clients)
end
local function pump() M.Pump(server, clients) end

local frames = 0
local function Frame()
    frames = frames + 1
    for _, realm in pairs(clients) do
        realm.hook.Run("PreRender")
        realm.hook.Run("Think")
    end
end
-- Advances the clock to `t`, running client frames every 0.05s on the way.
local function RunTo(t)
    while M.time < t - 1e-9 do
        M.time = math.min(t, M.time + 0.05)
        Frame()
    end
end

local function P(realm, name, p) return realm.materialDefs[name].params[p] end
local function floor(realm) return P(realm, "maps/floor", "$color").x end
local function isBlack(realm, name) local t = P(realm, name, "$basetexture") return type(t) == "table" and t.textureName == "lightingeditor_black" end
-- Switched to a copy with its glowing parts black.
local function isCopy(realm, name) local t = P(realm, name, "$basetexture") return type(t) == "table" and t.textureName:find("^lightingeditor_glow_") ~= nil end
local function isOff(realm, name) return isBlack(realm, name) or isCopy(realm, name) end
local function pix(p, r, g, b, a) return near(p[1], r) and near(p[2], g) and near(p[3], b) and near(p[4], a) end
local function liveLights(realm)
    local list = {}
    for _, l in pairs(realm.dlights) do if l.dietime and l.dietime > M.time then table.insert(list, l) end end
    return list
end

local DECK1, DECK2 = V(256, 128, 0), V(256, 128, 300)
boot()
local Config = server.LightingEditor.Config
local DARK = Config.DarkLevel
-- Light left on a dead deck: walls lose DarkLevel, but never go below MinLight;
-- props lose only PropDarkScale of what the walls lose.
local K = math.max(1 - DARK, Config.MinLight)
local KM = math.max(1 - DARK * Config.PropDarkScale, Config.MinLight)
-- What a model's $color2 must be for the shader (which converts it from gamma
-- to linear, x^2.2) to scale its light by KM.
local function MK(original) return ((original ^ 2.2) * KM) ^ (1 / 2.2) end

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

step("finding the deck", function()
    local LE = server.LightingEditor
    check(LE.FindDeck(V(100, 100, 50)) == 1, "inside a deck 1 section")
    check(LE.FindDeck(V(600, 100, 50)) == 1, "in a corridor no section covers: still deck 1")
    check(LE.FindDeck(V(100, 100, 300)) == 2, "deck 2")
    check(LE.FindDeck(V(100, 100, 5000)) == nil, "far above the ship: no deck")
    check(LE.NearSection(V(600, 100, 0), 96) and not LE.NearSection(V(500, -2000, 64), 96), "inside vs the hull's outside")
end)

step("reading the map's files", function()
    local LE = crewCl.LightingEditor
    local faces, props = {}, {}
    local ok = LE.ScanMap(function(name, center, faceArea) table.insert(faces, { name, center, faceArea }) end,
        function(model, pos) table.insert(props, { model, pos }) end, function() end)
    check(ok, "map read")
    check(#faces == 15, "15 drawn faces, sky and nodraw skipped: " .. #faces)
    check(faces[1][1] == "maps/floor" and vnear(faces[1][2], 100, 100, 0) and near(faces[1][3], 4096), "face material, center and area")
    check(vnear(faces[#faces][2], 30, 30, 300), "a triangle's center (edges stored both ways round)")
    check(#props == 4 and props[1][1] == "models/props/console.mdl" and vnear(props[1][2], 100, 100, 10), "static props and positions")
    local candidates = LE.ModelMaterialCandidates("models/props/console.mdl")
    check(#candidates == 2 and candidates[1][2] == "models/props/console" and candidates[2][1] == "models/props_old/console_screen", "model materials under each folder")
    check(vnear(LE.TextureColor("stm/forcefield"), 0.1, 0.3, 0.6), "texture average color")
    check(LE.TextureColor("missing/texture") == nil, "missing texture: no color")
end)

step("finding what to darken happens over several frames", function()
    local step = M.sysTimeStep
    M.sysTimeStep = 0.001 -- a slow computer: the time budget runs out quickly
    local before = frames
    for _ = 1, 200 do
        Frame()
        if crewCl.LightingEditor.WorldScanned then break end
    end
    check(crewCl.LightingEditor.WorldScanned, "scan finished")
    check(frames - before > 1, "spread over " .. (frames - before) .. " frames")
    M.sysTimeStep = step
end)

step("with power everywhere, nothing is touched", function()
    crew.pos, admin.pos = DECK1, DECK2
    RunTo(105)
    check(crewCl.materialWrites == 0 and adminCl.materialWrites == 0, "no material writes")
    check(#M.errors == 0, "no errors: " .. tostring(M.errors[1]))
end)

step("crew can't cut power", function()
    server.RunCmd(crew, "lighting_outage", { "1" })
    pump()
    check(crew.chat[#crew.chat]:find("permission") ~= nil, "crewman told no permission")
    check(next(server.LightingEditor.Outages) == nil, "nothing changed")
end)

step("cut power to deck 1: flicker, then dark", function()
    server.RunCmd(admin, "lighting_outage", { "1" })
    pump()
    check(admin.chat[#admin.chat]:find("Power cut on: deck 1") ~= nil, "admin told: " .. tostring(admin.chat[#admin.chat]))
    check(#crewCl.sounds == 1 and #adminCl.sounds == 0, "sound for the crewman on deck 1 only")
    local seen = {}
    local stop = M.time + Config.FlickerOutTime - 0.05
    while M.time < stop do
        RunTo(M.time + 0.05)
        seen[floor(crewCl) < 0.5 and "dark" or "lit"] = true
        seen[isOff(crewCl, CORRIGATED) and "off" or "on"] = true
    end
    check(seen.dark and seen.lit and seen.off and seen.on, "lights flicker before dying")
    RunTo(M.time + 10)
end)

step("deck 1 without power: surfaces", function()
    local c = crewCl
    check(near(floor(c), K), "floor's baked light down to " .. K .. ": " .. floor(c))
    check(vnear(P(c, "maps/mixed", "$color"), 0.5 * K, 0.8 * K, K), "displacement, mostly inside, scaled from its own color")
    check(vnear(P(c, "maps/cubemapped", "$envmaptint"), 0.6 * K, 0.6 * K, 0.6 * K), "cubemap reflections dimmed")
    check(near(P(c, "maps/door", "$color").x, K), "brush door dark")
    check(vnear(P(c, "maps/hull", "$color"), 1, 1, 1), "the hull's outside untouched")
    check(vnear(P(c, "maps/hullmostly", "$color"), 1, 1, 1), "a material mostly on the outside untouched")
    check(vnear(P(c, "maps/water", "$color"), 1, 1, 1), "water untouched")
    check(P(c, "maps/skyface", "$color") == nil and P(c, "maps/nodraw", "$color") == nil, "sky and nodraw faces ignored")
end)

step("deck 1 without power: props, entities and glow", function()
    local c = crewCl
    check(vnear(P(c, "models/props/console", "$color2"), MK(1), MK(1), MK(1)), "static prop exactly as dark as the walls once the shader converts it")
    check(near(P(c, "models/props/console", "$color2").x ^ 2.2, KM), "(linear: " .. KM .. ")")
    check(near(P(c, "models/props/console", "$phongboost"), 2 * KM), "and its highlights")
    check(KM > K + 0.2, "props keep more light than the walls (" .. KM .. " vs " .. K .. ")")
    check(vnear(P(c, "models/props/console", "$envmaptint"), MK(1), MK(1), MK(1)), "and its reflections")
    check(isBlack(c, "models/props/console_screen") == false and P(c, "models/props/console_screen", "$basetexture").textureName == "models/props/console_screen",
        "static prop's screen, self-illuminated but with no glow marked in its (empty) texture, kept")
    check(P(c, "models/props/asteroid", "$color2").x == 1, "3D skybox prop untouched")
    check(vnear(P(c, "models/props/door_metal", "$color2"), MK(0.9), MK(0.9), MK(0.9)), "door (entity) dark, from its own color")
    local LE = c.LightingEditor
    check(near(LE.ModelTint(2, 0.75), 1.5) and near(LE.ModelTint(2, 0.25) ^ 2.2, 0.5), "overbright tints (above 1, which the shader leaves linear)")
    check(isBlack(c, "models/props/beam_cone"), "additive light cone (material override) out entirely")
    local black = c.renderTargets.lightingeditor_black
    check(black.cleared[4] == 0, "with transparent black, so nothing shows where it was see-through")
    check(P(c, "models/props/door_label", "$basetexture").textureName == "models/props/door_label", "door label (plain unlit) untouched")
    check(P(c, "models/kingpommes/startrek/intrepid/core_effect", "$basetexture").textureName == "core_effect", "core_effect excluded")
    check(P(c, "models/planets/earth", "$color2").x == 1, "STM exterior (planet far outside) untouched")
    check(P(c, "models/stm/forcefield", "$basetexture") == "stm/forcefield" and P(c, "models/stm/forcefield", "$color").x == 1, "force field untouched")
    -- The wall with a glowing strip: darkened like a wall, and only the strip goes black.
    check(near(P(c, "maps/glowstrip", "$color").x, K), "self-illuminated wall darkened like any wall")
    check(isCopy(c, "maps/glowstrip"), "and its texture swapped for the copy")
    local strip = P(c, "maps/glowstrip", "$basetexture").pixels
    check(pix(strip[1], 0, 0, 0, 1), "the part marked as glowing is black")
    check(pix(strip[2], 0.4, 0.4, 0.4, 0), "the rest is exactly as it was, alpha too")
    check(pix(strip[3], 1, 1, 1, 0), "even white parts it doesn't mark as glowing (white paint isn't a light)")

    -- wall_corrigated (listed): darkened like a wall, and its bright parts black.
    check(near(P(c, CORRIGATED, "$color").x, K), "wall_corrigated darkened like any wall, not all black")
    check(isCopy(c, CORRIGATED), "with its glowing parts blacked out")
    local wall = P(c, CORRIGATED, "$basetexture").pixels
    local t = 179 / 255 -- GlowThreshold 0.7, as the 0-255 color it's drawn with
    local function kept(p) local l = 0.299 * p[1] + 0.587 * p[2] + 0.114 * p[3] return 1 - math.min(1, math.max(0, l - t) * 4) end
    check(pix(wall[1], 0, 0, 0, 1), "white: black")
    check(pix(wall[2], 0.1, 0.2, 0.5, 1), "dark blue: kept")
    check(pix(wall[3], 0.5, 0.5, 0.5, 1), "mid gray: kept")
    check(pix(wall[4], 1 * kept(YELLOW), 0.9 * kept(YELLOW), 0.2 * kept(YELLOW), 0.5) and kept(YELLOW) > 0.3 and kept(YELLOW) < 0.5,
        "bright yellow: mostly dark, and its alpha kept")
    check(isOff(c, "maps/rp_test/kingpommes/startrek/intrepid/eng_floorlight_120_-40_8"), "eng_floorlight (listed) out in its cubemap copy")
    check(isOff(c, "models/kingpommes/startrek/intrepid/light_white"), "light_white (listed) out though nothing found uses it")
    check(P(c, "maps/rp_test/maps/hull_500_-2000_64", "$color").x == 1, "cubemap copy on the outside untouched")
    check(isOff(c, "maps/rp_test/lights/white_2000_2000_64"), "listed fixture far from any section still goes out")
    check(isCopy(c, BRIDGE_LIGHT), "bridge light off by texture, so STM's brightness proxy can't undo it")
    local bridge = P(c, BRIDGE_LIGHT, "$basetexture").pixels
    check(pix(bridge[1], 0, 0, 0, 1) and pix(bridge[2], 0, 0, 0, 1), "its masked part and its bright part black")
    check(pix(bridge[3], 0.3, 0.3, 0.3, 1), "the rest kept")
    check(vnear(P(c, BRIDGE_LIGHT, "$color2"), MK(1), MK(1), MK(1)), "and the fixture itself darkened like any prop")
    check(vnear(P(c, "lights/white", "$color"), 0, 0, 0), "lights/white (no texture) black by color")
    check(P(c, ALARM, "$basetexture").textureName == ALARM and P(c, ALARM, "$color2") == nil, "STM alert material untouched")
    check(crewCl.LightingEditor.BaseMaterialName("maps/rp_test/foo/bar_-1_2_-30") == "foo/bar" and crewCl.LightingEditor.BaseMaterialName("foo/bar_1_2_3") == "foo/bar_1_2_3", "cubemap copy names")
end)

step("players, weapons and hands are dimmed while drawn", function()
    for _, pair in ipairs({ { "PrePlayerDraw", "PostPlayerDraw" }, { "PreDrawViewModel", "PostDrawViewModel" }, { "PreDrawPlayerHands", "PostDrawPlayerHands" } }) do
        crewCl.hook.Run(pair[1])
        check(near(crewCl.modulation[1], MK(1)), pair[1] .. " dims, like the props")
        crewCl.hook.Run(pair[2])
        check(crewCl.modulation[1] == 1, pair[2] .. " restores")
    end
end)

step("the admin on deck 2 (with power) sees nothing change", function()
    check(adminCl.materialWrites == 0, "no material writes on the admin's game")
    adminCl.hook.Run("PrePlayerDraw")
    check(adminCl.modulation[1] == 1, "players normal")
end)

step("steady darkness costs nothing per frame", function()
    local writes = crewCl.materialWrites
    RunTo(M.time + 2)
    check(crewCl.materialWrites == writes, "no material writes while nothing changes")
end)

step("new props are picked up while dark", function()
    crewCl.materialDefs["models/props/mug"] = { shader = "VertexLitGeneric", params = { ["$color2"] = V(1, 1, 1) } }
    local mug = Ent("prop_physics", "models/props/mug.mdl", V(120, 120, 40), { "models/props/mug" })
    table.insert(M.entities, mug)
    RunTo(M.time + 1.5)
    check(near(P(crewCl, "models/props/mug", "$color2").x, MK(1)), "spawned mug dark")
    table.remove(M.entities)
end)

step("LCARS screens and force fields keep shining, as real light", function()
    local lcars = crewCl.Star_Trek.LCARS
    local console = Ent("prop_dynamic", "models/props/console.mdl", V(100, 0, 64), {})
    lcars.ActiveInterfaces[5] = { Ent = console, AnimPos = 1, Windows = {
        { WPosG = V(100, 0, 64), WAngG = { Up = function() return V(0, 1, 0) end }, WScale = 20, WWidth = 400, WHeight = 200,
          Elements = { { Color = Color(202, 151, 50) }, { Color = Color(53, 164, 192) } } }
    } }
    crewCl.Star_Trek.Alert.CurrentAlert = "red"
    crewCl.materialDefs[ALARM].params["$alarmcolor"] = V(255 / 256, 0, 0)
    RunTo(M.time + 0.5)
    check(#liveLights(crewCl) == 2, "screen and force field only, no alert lights: " .. #liveLights(crewCl))

    local byPos, screen = {}, nil
    for _, l in ipairs(liveLights(crewCl)) do
        byPos[string.format("%d %d %d", l.pos.x, l.pos.y, l.pos.z)] = l
        if l.dir then screen = l end
    end

    check(screen ~= nil, "the LCARS screen gives off light")
    if screen then
        check(screen.pos.y > 0 and vnear(screen.dir, 0, 1, 0), "from its face, towards the front")
        check(screen.r == math.floor((202 + 53) / 2 + 0.5) and screen.b == math.floor((50 + 192) / 2 + 0.5), "the average color of what it shows")
        local size = math.sqrt((400 / 20) * (200 / 20))
        check(near(screen.size, math.max(size * Config.Emitters.LCARS.RadiusPerUnit, Config.Emitters.LCARS.MinRadius)), "sized by the screen")
        check(near(screen.brightness, Config.Emitters.LCARS.Brightness * Config.Emitters.MaxBoost), "raised in the dark, but only up to MaxBoost")
    end

    local fieldLight = byPos["640 128 64"]
    check(fieldLight ~= nil, "the force field gives off light")
    if fieldLight then
        check(fieldLight.b == 255 and math.abs(fieldLight.g - 255 / 2) <= 1 and math.abs(fieldLight.r - 255 / 6) <= 1,
            string.format("the color of its texture: %d %d %d", fieldLight.r, fieldLight.g, fieldLight.b))
    end

    check(byPos["300 100 100"] == nil, "alert fixtures give off no light")

    -- Red alert: screens switch to STM's red palette.
    lcars.ActiveInterfaces[5].Windows[1].CurrentStyle = "LCARS_RED"
    RunTo(M.time + 0.5)
    for _, l in ipairs(liveLights(crewCl)) do
        if l.dir then check(l.r == 197 and l.g == 52 and l.b == 54, "red alert screens light red") end
    end

    crewCl.Star_Trek.Alert.CurrentAlert = nil
    lcars.ActiveInterfaces[5] = nil
    RunTo(M.time + 1)
    check(#liveLights(crewCl) == 1, "screen closed: only the force field still lights (" .. #liveLights(crewCl) .. ")")
    crewCl.materialDefs[ALARM].params["$alarmcolor"] = V(0, 0, 0)
end)

step("at most Config.Emitters.MaxLights lights, nearest first", function()
    for i = 20, 1, -1 do -- furthest first
        table.insert(M.entities, Ent("force_field", "models/stm/forcefield.mdl", V(300 + i * 40, 128, 64), { "models/stm/forcefield" }))
    end
    crewCl.dlights = {}
    RunTo(M.time + 0.5)
    local lights, furthest = liveLights(crewCl), 0
    for _, l in ipairs(lights) do furthest = math.max(furthest, l.pos.x) end
    check(#lights == Config.Emitters.MaxLights, "capped at " .. Config.Emitters.MaxLights .. ": " .. #lights)
    check(furthest < 300 + 20 * 40, "the furthest left out")
    for _ = 1, 20 do table.remove(M.entities) end
end)

step("the server switches deck 1's map lights off", function()
    check(bridgeLight.fired[#bridgeLight.fired] == "TurnOff", "named light off")
    check(#darkLight.fired == 0, "a light that was already off is left alone")
    check(dynLight.fired[#dynLight.fired] == "TurnOff", "dynamic light off")
    check(spot.fired[#spot.fired] == "LightOff", "spotlight off")
    check(sprite.noDraw == true, "glow sprite hidden")
    check(#deck2Lamp.fired == 0, "deck 2's lamp untouched")
end)

step("STM's alerts can't switch the bridge lights back on during an outage", function()
    server.Star_Trek.Alert:Enable("yellow") -- STM turns the bridge lights on for yellow alert
    check(bridgeLight.fired[#bridgeLight.fired] == "TurnOff", "switched back off")
    server.Star_Trek.Alert:Enable("red")
end)

step("walking into a corridor the sections don't cover: still dark", function()
    crew.pos = V(640, 128, 0)
    RunTo(M.time + 2)
    check(near(floor(crewCl), K), "still dark")
end)

step("taking the turbolift to deck 2: fades back to normal", function()
    crew.pos = V(1300, 128, 200) -- in a turbolift shaft outside every deck: stays on deck 1
    RunTo(M.time + 1)
    check(near(floor(crewCl), K), "between decks: still dark")
    crew.pos = DECK2
    RunTo(M.time + 0.2 + Config.DeckChangeTime / 2)
    local mid = floor(crewCl)
    check(mid > K + 0.05 and mid < 0.95, "fading, not snapping: " .. mid)
    RunTo(M.time + Config.DeckChangeTime)
    check(near(floor(crewCl), 1), "floor fully lit")
    check(not isOff(crewCl, BRIDGE_LIGHT), "lights back on")
    local writes = crewCl.materialWrites
    RunTo(M.time + 2)
    check(crewCl.materialWrites == writes, "then left alone")
    crew.pos = DECK1
    RunTo(M.time + 1)
    check(near(floor(crewCl), K), "back on deck 1: dark")
end)

step("late joiners see the dark deck, with no sound", function()
    local late = M.MakePlayer("late", false)
    late.pos = DECK1
    local lateCl = NewClient(late)
    clients[late] = lateCl
    lateCl.hook.Run("InitPostEntity")
    pump()
    RunTo(M.time + 3)
    check(near(floor(lateCl), K), "dark for the joiner")
    check(isOff(lateCl, CORRIGATED), "lights off for the joiner")
    check(#lateCl.sounds == 0, "no sound")
    clients[late] = nil
end)

step("restore power: everything's exactly as it was", function()
    crewCl.sounds = {}
    server.Star_Trek.Alert:Disable()
    server.RunCmd(admin, "lighting_restore", { "1" })
    pump()
    check(admin.chat[#admin.chat]:find("restored to: deck 1") ~= nil, "admin told")
    check(#crewCl.sounds == 1, "crewman hears it")
    RunTo(M.time + Config.FlickerInTime / 2)
    check(floor(crewCl) < 1, "not instantly back")
    RunTo(M.time + Config.FlickerInTime + Config.FadeInTime + 0.5)
    for name, def in pairs(M.materials) do
        for p, original in pairs(def.params) do
            local now = P(crewCl, name, p)
            local same
            if type(original) == "table" and original.textureName then same = type(now) == "table" and now.textureName == original.textureName
            elseif type(original) == "table" then same = vnear(now, original.x, original.y, original.z)
            else same = now == original end
            check(same, name .. " " .. p .. " restored exactly")
        end
    end
    crewCl.hook.Run("PrePlayerDraw")
    check(crewCl.modulation[1] == 1, "players normal")

    check(bridgeLight.fired[#bridgeLight.fired] == "TurnOn" and dynLight.fired[#dynLight.fired] == "TurnOn" and spot.fired[#spot.fired] == "LightOn", "map lights back on")
    check(#darkLight.fired == 0, "the one that was off stays off")
    check(sprite.noDraw == false and hiddenSprite.noDraw == true, "sprites as they were")
end)

step("red alert holds the bridge lights off after power returns", function()
    local alert = server.Star_Trek.Alert
    alert:Enable("red")
    server.RunCmd(admin, "lighting_outage", { "1" })
    local count = #bridgeLight.fired
    server.RunCmd(admin, "lighting_restore", { "1" })
    check(#bridgeLight.fired == count, "not switched on while STM has them dimmed")
    alert:Disable()
    pump()
end)

step("a map that can't be read falls back to the world's materials", function()
    local saved = M.files["maps/rp_test.bsp"]
    M.files["maps/rp_test.bsp"] = nil
    local other = M.MakePlayer("other", false)
    other.pos = DECK1
    local otherCl = NewClient(other)
    clients[other] = otherCl
    otherCl.hook.Run("InitPostEntity")
    pump()
    for _ = 1, 50 do Frame() end
    check(otherCl.LightingEditor.WorldScanned, "finished anyway")
    server.RunCmd(admin, "lighting_outage", { "1" })
    pump()
    RunTo(M.time + 5)
    check(near(floor(otherCl), K), "world materials still darkened")
    server.RunCmd(admin, "lighting_restore", { "1" })
    pump()
    RunTo(M.time + 5)
    clients[other] = nil
    M.files["maps/rp_test.bsp"] = saved
end)

step("here, ship, and bad decks", function()
    admin.pos = DECK2
    server.RunCmd(admin, "lighting_outage", { "here" })
    check(admin.chat[#admin.chat]:find("deck 2") ~= nil, "'here' is the admin's deck: " .. admin.chat[#admin.chat])
    check(deck2Lamp.fired[#deck2Lamp.fired] == "TurnOff", "deck 2's lamp off")
    admin.pos = V(0, 0, 5000)
    server.RunCmd(admin, "lighting_outage", { "here" })
    check(admin.chat[#admin.chat]:find("not on any deck") ~= nil, "'here' off the ship explained")
    server.RunCmd(admin, "lighting_outage", { "ship" })
    check(admin.chat[#admin.chat]:find("2 decks") ~= nil, "ship covers both decks")
    local sends = #M.queueToClients
    server.RunCmd(admin, "lighting_restore", { "ship" })
    check(#M.queueToClients - sends == 1, "one network update for the whole ship")
    pump()
    check(server.LightingEditor.IsDeckPowered(1) and server.LightingEditor.IsDeckPowered(2), "all powered")
    check(deck2Lamp.fired[#deck2Lamp.fired] == "TurnOn", "deck 2's lamp back on")
    server.RunCmd(admin, "lighting_outage", { "7" })
    check(admin.chat[#admin.chat]:find("no deck 7") ~= nil, "unknown deck explained")
end)

step("minimum light, and props darkened less", function()
    local LE = crewCl.LightingEditor
    local Config = LE.Config -- the client's own copy
    local MODEL, WORLD = LE.MaterialKinds.MODEL, LE.MaterialKinds.WORLD
    check(near(LE.LightLeft(1, WORLD), 1) and near(LE.LightLeft(1, MODEL), 1), "full power: everything at full light")
    check(near(LE.LightLeft(0.08, WORLD), Config.MinLight), "walls never below MinLight")
    check(near(LE.LightLeft(0.5, WORLD), 0.5), "above it, walls follow the deck's light")
    check(near(LE.LightLeft(0.5, MODEL), 1 - 0.5 * Config.PropDarkScale), "props lose PropDarkScale of what the walls lose")
    local saved = Config.MinLight
    Config.MinLight = 0.7
    check(near(LE.LightLeft(0.08, MODEL), 0.7), "props never below MinLight either")
    Config.MinLight = saved

    check(Config.BarelyDarkenProps == false, "BarelyDarkenProps is off by default")
    Config.BarelyDarkenProps = true
    check(near(LE.LightLeft(0.08, MODEL), 1 - 0.92 * 0.25), "with BarelyDarkenProps, props only dim a little")
    check(near(LE.LightLeft(0.08, WORLD), Config.MinLight), "walls unchanged")
    Config.BarelyDarkenProps = false
end)

step("Helix chat commands", function()
    local registered = {}
    server.ix = { command = { Add = function(name, def) registered[name] = def end }, type = { string = 1, optional = 64 } }
    server.hook.Run("InitializedPlugins")
    check(registered.PowerOutage and registered.PowerRestore, "PowerOutage and PowerRestore registered")
    check(registered.PowerOutage.adminOnly, "admin only")
    local reply = registered.PowerOutage.OnRun(nil, admin, "2")
    check(reply and reply:find("cut on: deck 2") ~= nil, "PowerOutage works: " .. tostring(reply))
end)

for _, e in ipairs(M.errors) do print("logged: " .. e) end
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
