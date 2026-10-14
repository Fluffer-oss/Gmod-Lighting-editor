local LE = LightingEditor
local Config = LE.Config

-- A deck without power goes dark for the players on it, by turning down the
-- map's real baked light rather than dimming the screen:
--  * World brushes: their material's $color scales only the light that comes
--    from the lightmap (LightmappedGeneric multiplies it into the lightmap
--    lighting), so walls and floors lose their baked light while flashlights
--    still work. Nothing is rebuilt: lightmaps are never redownloaded, so it
--    never freezes, and it can fade smoothly frame by frame.
--  * Light fixtures (Config.LightMaterials) go fully black.
--  * Models (players, props) get almost no light (Config.ModelLight).
-- It applies to everything a player on a dark deck sees, so it doesn't matter
-- whether STM's sections cover every corridor; it ends when they leave the deck.

LE.ClientOutages = LE.ClientOutages or {}

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local function RequestState()
    net.Start(LE.NetRequest)
    net.SendToServer()
end

LE.CurrentDeck = LE.CurrentDeck or nil

net.Receive(LE.NetState, function()
    local incoming = {}
    for _ = 1, net.ReadUInt(8) do
        local entry = { deck = net.ReadUInt(8), out = net.ReadBool(), changedAt = net.ReadFloat() }
        incoming[entry.deck] = entry
    end

    for deck, entry in pairs(incoming) do
        local previous = LE.ClientOutages[deck]
        local isNewChange = not previous or previous.out ~= entry.out
        -- Only for changes happening now (not a joiner's catch-up), on our deck.
        local sound = entry.out and Config.Sounds.Out or Config.Sounds.Restore
        if isNewChange and CurTime() - entry.changedAt < 1 and deck == LE.CurrentDeck and sound and sound ~= "" then
            surface.PlaySound(sound)
        end
    end

    LE.ClientOutages = incoming
end)

hook.Add("InitPostEntity", "LightingEditor.RequestState", RequestState)
if IsValid(LocalPlayer()) then RequestState() end

--------------------------------------------------------------------------------
-- How dark a deck is right now (0 = normal, Config.DarkLevel = no power)
--------------------------------------------------------------------------------

-- A fixed stutter pattern, like a light style ("m" = on, "a" = off).
local FLICKER = "mmamammmmammamamaaamammmaaaam"

local function Flicker(t, seed)
    local index = (math.floor(t * 18) + seed) % #FLICKER + 1
    return FLICKER:sub(index, index) == "a"
end

function LE.DeckDarkness(entry, now)
    local t = now - entry.changedAt
    local seed = entry.deck % 7
    local dark = Config.DarkLevel

    if entry.out then
        if t < Config.FlickerOutTime then
            return Flicker(t, seed) and dark or 0
        end
        return dark * math.min(1, (t - Config.FlickerOutTime) / Config.FadeOutTime + 0.6)
    end

    if t < Config.FlickerInTime then
        return Flicker(t, seed) and dark or dark * 0.4
    end
    return dark * 0.4 * math.max(0, 1 - (t - Config.FlickerInTime) / Config.FadeInTime)
end

--------------------------------------------------------------------------------
-- Materials
--------------------------------------------------------------------------------

-- Original values of every parameter we change, so restoring is exact.
-- material name -> { mat = IMaterial, params = { [param] = Vector } }
LE.Originals = LE.Originals or {}

local function Track(name, params)
    local tracked = LE.Originals[name]
    if tracked then return tracked end

    local mat = Material(name)
    if not mat or mat:IsError() then return nil end
    tracked = { mat = mat, params = {} }
    for param, required in pairs(params) do
        local value = mat:GetVector(param)
        if value then
            tracked.params[param] = Vector(value)
        elseif required then
            tracked.params[param] = Vector(1, 1, 1)
        end
    end
    LE.Originals[name] = tracked
    return tracked
end

local function Scale(tracked, factor)
    for param, original in pairs(tracked.params) do
        tracked.mat:SetVector(param, original * factor)
    end
end

-- Lightmapped world materials (the world and brush entities like doors),
-- found when a deck first goes dark for us.
local worldMaterials, lightMaterials

local function IsLightmapped(mat)
    local shader = string.lower(mat:GetShader() or "")
    return shader:find("lightmapped", 1, true) or shader:find("worldvertextransition", 1, true)
end

local function CollectMaterials()
    lightMaterials = {}
    local isLight = {}
    for _, name in ipairs(Config.LightMaterials) do
        isLight[string.lower(name)] = true
        local tracked = Track(name, { ["$color"] = true, ["$color2"] = true, ["$selfillumtint"] = false, ["$envmaptint"] = false })
        if tracked then table.insert(lightMaterials, tracked) end
    end

    worldMaterials = {}
    local seen = {}
    local function Add(names)
        for _, name in ipairs(names or {}) do
            local key = string.lower(name)
            if not seen[key] and not isLight[key] then
                seen[key] = true
                local mat = Material(name)
                if mat and not mat:IsError() and IsLightmapped(mat) then
                    table.insert(worldMaterials, Track(name, { ["$color"] = true }))
                end
            end
        end
    end
    Add(game.GetWorld():GetMaterials())
    for _, ent in ipairs(ents.GetAll()) do
        local model = ent:GetModel()
        if model and model:sub(1, 1) == "*" then Add(ent:GetMaterials()) end
    end
end

local applied = 0

-- darkness: 0 (normal) to Config.DarkLevel (no power).
local function Apply(darkness)
    -- Skip changes too small to see; the end points are always exact.
    if darkness == applied then return end
    if math.abs(darkness - applied) < 1 / 256 and darkness ~= 0 and darkness ~= Config.DarkLevel then return end
    if not worldMaterials then CollectMaterials() end

    local out = Config.DarkLevel > 0 and math.min(1, darkness / Config.DarkLevel) or 0
    for _, tracked in ipairs(worldMaterials) do Scale(tracked, 1 - darkness) end
    for _, tracked in ipairs(lightMaterials) do Scale(tracked, 1 - out) end
    applied = darkness

    if darkness == 0 then
        -- Fully back to normal: pick up any new brush entities next time.
        worldMaterials, lightMaterials = nil, nil
    end
end

--------------------------------------------------------------------------------
-- Frame
--------------------------------------------------------------------------------

local nextDeckCheck, deckChangedAt, levelAtDeckChange = 0, -math.huge, 0
local current = 0

local function TargetDarkness(now)
    local entry = LE.CurrentDeck and LE.ClientOutages[LE.CurrentDeck]
    return entry and LE.DeckDarkness(entry, now) or 0
end

hook.Add("Think", "LightingEditor.Outages", function()
    local now = CurTime()
    local ply = LocalPlayer()

    if now >= nextDeckCheck and IsValid(ply) then
        nextDeckCheck = now + 0.2
        -- Between decks (turbolift shafts, gaps), stay on the last one.
        local deck = LE.FindDeck(ply:WorldSpaceCenter())
        if deck and deck ~= LE.CurrentDeck then
            levelAtDeckChange = current
            deckChangedAt = now
            LE.CurrentDeck = deck
        end
    end

    local target = TargetDarkness(now)
    local blend = (now - deckChangedAt) / Config.DeckChangeTime
    if blend < 1 then
        current = levelAtDeckChange + (target - levelAtDeckChange) * blend
    else
        current = target
    end

    Apply(current)
end)

-- Models: the engine lights them from the map's baked lighting, which the
-- materials above don't reach, so while the lights are out they're drawn with
-- only a little flat light instead.
local modelsDark = false

hook.Add("PreDrawOpaqueRenderables", "LightingEditor.Models", function(drawingDepth, drawingSkybox, drawing3DSkybox)
    modelsDark = false
    if not Config.DarkenModels or drawingDepth or drawingSkybox or drawing3DSkybox then return end
    if Config.DarkLevel <= 0 or current < Config.DarkLevel * 0.5 then return end

    local light = Config.ModelLight
    render.SuppressEngineLighting(true)
    render.ResetModelLighting(light, light, light)
    render.SetLocalModelLights({})
    modelsDark = true
end)

hook.Add("PostDrawTranslucentRenderables", "LightingEditor.Models", function()
    if modelsDark then
        render.SuppressEngineLighting(false)
        modelsDark = false
    end
end)
