HARNESS_DIR = arg[0]:match("^(.*/)") or "./"
package.path = HARNESS_DIR .. "?.lua;" .. package.path
local M = require("mock")
local V = M.Vector

local passed, failed = 0, 0
local function check(cond, label)
    if cond then passed = passed + 1 else failed = failed + 1 print("FAIL: " .. label) end
end
local function step(label, fn)
    local ok, err = pcall(fn)
    if not ok then failed = failed + 1 print("ERROR in '" .. label .. "': " .. tostring(err)) end
end
local function near(a, b) return math.abs(a - b) < 1e-6 end
local function vnear(v, x, y, z) return v and near(v.x, x) and near(v.y, y) and near(v.z, z) end

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

-- The map's materials.
local LIGHT_WHITE = "models/kingpommes/startrek/intrepid/light_white"
local CORRIGATED = "kingpommes/startrek/intrepid/wall_corrigated"
M.materials = {
    ["maps/floor"] = { shader = "LightmappedGeneric", params = { ["$color"] = V(1, 1, 1) } },
    ["maps/wall"] = { shader = "WorldVertexTransition", params = { ["$color"] = V(0.5, 0.8, 1) } },
    ["maps/water"] = { shader = "Water", params = { ["$color"] = V(1, 1, 1) } },
    ["maps/door"] = { shader = "LightmappedGeneric", params = { ["$color"] = V(1, 1, 1) } },
    ["lights/white"] = { shader = "UnlitGeneric", params = { ["$color"] = V(1, 1, 1) } },
    [LIGHT_WHITE] = { shader = "VertexLitGeneric", params = { ["$color"] = V(1, 1, 1), ["$color2"] = V(1, 1, 1), ["$selfillumtint"] = V(2, 2, 2) } },
    ["models/shiny"] = { shader = "VertexLitGeneric", params = { ["$color"] = V(1, 1, 1), ["$color2"] = V(1, 1, 1), ["$envmaptint"] = V(0.5, 0.5, 0.5) } },
    [CORRIGATED] = { shader = "LightmappedGeneric", params = { ["$color"] = V(1, 1, 1) } }
}
M.worldMaterials = { "maps/floor", "maps/wall", "maps/water", CORRIGATED, "lights/white" }
M.entities = {
    { GetModel = function() return "*3" end, GetMaterials = function() return { "maps/door" } end },
    { GetModel = function() return "models/props/chair.mdl" end, GetMaterials = function() return { "models/shiny" } end }
}

local admin = M.MakePlayer("admin", true)
local crew = M.MakePlayer("crewman", false)
local server, adminCl, crewCl, clients

local function NewClient(ply)
    local realm = M.NewRealm(false, ply)
    realm.Star_Trek = { Sections = { Decks = MakeDecks() } }
    realm.include("autorun/lighting_editor.lua")
    return realm
end

local function boot()
    M.pooled, M.queueToServer, M.queueToClients = {}, {}, {}
    server = M.NewRealm(true)
    server.Star_Trek = { Sections = { Decks = MakeDecks() } }
    server.include("autorun/lighting_editor.lua")
    adminCl, crewCl = NewClient(admin), NewClient(crew)
    clients = { [admin] = adminCl, [crew] = crewCl }
    adminCl.hook.Run("InitPostEntity")
    crewCl.hook.Run("InitPostEntity")
    M.Pump(server, clients)
end
local function pump() M.Pump(server, clients) end

-- Advances the clock to `t`, running client frames every 0.05s on the way.
local function RunTo(t)
    while M.time < t - 1e-9 do
        M.time = math.min(t, M.time + 0.05)
        for _, realm in pairs(clients) do realm.hook.Run("Think") end
    end
end

local function param(realm, name, p) return realm.materialDefs[name].params[p] end
local function floor(realm) return param(realm, "maps/floor", "$color").x end

-- Whether models are drawn dark in the main view (and back to normal after).
local function ModelsDark(realm)
    realm.hook.Run("PreDrawOpaqueRenderables", false, false, false)
    local dark = realm.modelLighting.suppressed
    realm.hook.Run("PostDrawTranslucentRenderables", false, false, false)
    assert(not realm.modelLighting.suppressed, "engine lighting left suppressed")
    return dark
end

local DECK1, DECK2 = V(256, 128, 0), V(256, 128, 300)
boot()
local Config = server.LightingEditor.Config
local DARK = Config.DarkLevel

step("finding the deck", function()
    local LE = server.LightingEditor
    check(LE.FindDeck(V(100, 100, 50)) == 1, "inside a deck 1 section")
    check(LE.FindDeck(V(600, 100, 50)) == 1, "in a corridor no section covers: still deck 1")
    check(LE.FindDeck(V(100, 100, 300)) == 2, "deck 2")
    check(LE.FindDeck(V(100, 100, 5000)) == nil, "far above the ship: no deck")
end)

step("crew can't cut power", function()
    server.RunCmd(crew, "lighting_outage", { "1" })
    pump()
    check(crew.chat[#crew.chat]:find("permission") ~= nil, "crewman told no permission")
    check(next(server.LightingEditor.Outages) == nil, "nothing changed")
end)

step("with power everywhere, materials are never touched", function()
    crew.pos, admin.pos = DECK1, DECK2
    RunTo(105)
    check(crewCl.materialWrites == 0 and adminCl.materialWrites == 0, "no material writes")
    check(not ModelsDark(crewCl), "models normal")
end)

step("cut power to deck 1", function()
    server.RunCmd(admin, "lighting_outage", { "1" })
    pump()
    check(admin.chat[#admin.chat]:find("Power cut on: deck 1") ~= nil, "admin told: " .. tostring(admin.chat[#admin.chat]))
    check(#crewCl.sounds == 1 and #adminCl.sounds == 0, "sound for the crewman on deck 1 only")

    local seen = {}
    local stop = M.time + Config.FlickerOutTime - 0.05
    while M.time < stop do
        RunTo(M.time + 0.05)
        seen[floor(crewCl) < 0.5 and "dark" or "lit"] = true
    end
    check(seen.dark and seen.lit, "lights flicker before dying")
end)

step("deck 1 without power: the crewman's world goes dark", function()
    RunTo(M.time + 10)
    check(near(floor(crewCl), 1 - DARK), "floor's baked light down to " .. (1 - DARK) .. ": " .. floor(crewCl))
    check(vnear(param(crewCl, "maps/wall", "$color"), 0.5 * (1 - DARK), 0.8 * (1 - DARK), 1 - DARK), "displacement wall scaled from its own color")
    check(near(param(crewCl, "maps/door", "$color").x, 1 - DARK), "brush entities (doors) too")
    check(vnear(param(crewCl, "maps/water", "$color"), 1, 1, 1), "water (not lightmapped) untouched")

    check(vnear(param(crewCl, "lights/white", "$color"), 0, 0, 0), "lights/white black")
    check(vnear(param(crewCl, LIGHT_WHITE, "$color2"), 0, 0, 0) and vnear(param(crewCl, LIGHT_WHITE, "$selfillumtint"), 0, 0, 0), "light_white black, glow off")
    check(vnear(param(crewCl, "models/shiny", "$envmaptint"), 0, 0, 0), "models/shiny reflections off")
    check(vnear(param(crewCl, CORRIGATED, "$color"), 0, 0, 0), "wall_corrigated black (listed light material, even though it's on the world)")
    check(param(crewCl, LIGHT_WHITE, "$envmaptint") == nil, "parameters a material doesn't have are left unset")

    check(ModelsDark(crewCl), "models drawn dark")
    check(near(crewCl.modelLighting.ambient[1], Config.ModelLight) and #crewCl.modelLighting.locals == 0, "with only the configured light")
    crewCl.hook.Run("PreDrawOpaqueRenderables", false, true, false)
    check(not crewCl.modelLighting.suppressed, "the skybox isn't touched")
    crewCl.hook.Run("PostDrawTranslucentRenderables", false, true, false)
end)

step("the admin on deck 2 (with power) sees nothing change", function()
    check(adminCl.materialWrites == 0, "no material writes on the admin's game")
    check(not ModelsDark(adminCl), "models normal")
end)

step("steady darkness costs nothing per frame", function()
    local writes = crewCl.materialWrites
    RunTo(M.time + 2)
    check(crewCl.materialWrites == writes, "no material writes while nothing changes")
end)

step("walking into a corridor the sections don't cover: still dark", function()
    crew.pos = V(640, 128, 0)
    RunTo(M.time + 2)
    check(near(floor(crewCl), 1 - DARK), "still dark")
end)

step("taking the turbolift to deck 2: fades back to normal", function()
    crew.pos = V(1300, 128, 200) -- in a turbolift shaft outside every deck: stays on deck 1
    RunTo(M.time + 1)
    check(near(floor(crewCl), 1 - DARK), "between decks: still dark")
    crew.pos = DECK2
    RunTo(M.time + 0.2 + Config.DeckChangeTime / 2)
    local mid = floor(crewCl)
    check(mid > 1 - DARK + 0.05 and mid < 0.95, "fading, not snapping: " .. mid)
    RunTo(M.time + Config.DeckChangeTime)
    check(near(floor(crewCl), 1), "floor fully lit")
    check(vnear(param(crewCl, "maps/wall", "$color"), 0.5, 0.8, 1), "wall back to its exact original color")
    check(vnear(param(crewCl, LIGHT_WHITE, "$selfillumtint"), 2, 2, 2), "lights back on")
    check(not ModelsDark(crewCl), "models normal")
    local writes = crewCl.materialWrites
    RunTo(M.time + 2)
    check(crewCl.materialWrites == writes, "then left alone")
end)

step("back down to deck 1: dark again", function()
    crew.pos = DECK1
    RunTo(M.time + 1)
    check(near(floor(crewCl), 1 - DARK), "dark")
end)

step("late joiners see the dark deck, with no sound", function()
    local late = M.MakePlayer("late", false)
    late.pos = DECK1
    local lateCl = NewClient(late)
    clients[late] = lateCl
    lateCl.hook.Run("InitPostEntity")
    pump()
    RunTo(M.time + 1)
    check(near(floor(lateCl), 1 - DARK), "dark for the joiner")
    check(#lateCl.sounds == 0, "no sound")
    clients[late] = nil
end)

step("restore power: lights struggle back on, then everything's exactly as it was", function()
    crewCl.sounds = {}
    server.RunCmd(admin, "lighting_restore", { "1" })
    pump()
    check(admin.chat[#admin.chat]:find("restored to: deck 1") ~= nil, "admin told")
    check(#crewCl.sounds == 1, "crewman hears it")
    RunTo(M.time + Config.FlickerInTime / 2)
    check(floor(crewCl) < 1, "not instantly back")
    RunTo(M.time + Config.FlickerInTime + Config.FadeInTime + 0.5)
    for name, def in pairs(M.materials) do
        for p, original in pairs(def.params) do
            check(vnear(param(crewCl, name, p), original.x, original.y, original.z), name .. " " .. p .. " restored exactly")
        end
    end
    check(not ModelsDark(crewCl), "models normal")
end)

step("brush entities created since the last outage are included", function()
    crewCl.materialDefs["maps/hatch"] = { shader = "LightmappedGeneric", params = { ["$color"] = V(1, 1, 1) } }
    table.insert(M.entities, { GetModel = function() return "*9" end, GetMaterials = function() return { "maps/hatch" } end })
    server.RunCmd(admin, "lighting_outage", { "1" })
    pump()
    RunTo(M.time + 5)
    check(near(param(crewCl, "maps/hatch", "$color").x, 1 - DARK), "new hatch dark")
    server.RunCmd(admin, "lighting_restore", { "1" })
    pump()
    RunTo(M.time + 5)
    check(near(param(crewCl, "maps/hatch", "$color").x, 1), "and restored")
    table.remove(M.entities)
end)

step("here, ship, and bad decks", function()
    admin.pos = DECK2
    server.RunCmd(admin, "lighting_outage", { "here" })
    check(admin.chat[#admin.chat]:find("deck 2") ~= nil, "'here' is the admin's deck: " .. admin.chat[#admin.chat])
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
    server.RunCmd(admin, "lighting_outage", { "7" })
    check(admin.chat[#admin.chat]:find("no deck 7") ~= nil, "unknown deck explained")
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
