local LE = LightingEditor
local Config = LE.Config

-- A deck without power goes dark for the players on it: the ship's surfaces,
-- props and entities lose their light and everything that glows goes out
-- (cl_materials.lua), while STM's screens, force fields and alert lights keep
-- shining (cl_emitters.lua). Nothing is rebuilt (lightmaps are never
-- redownloaded), so it never freezes and it fades smoothly frame by frame.
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

local applied

-- darkness: 0 (normal) to Config.DarkLevel (no power).
local function Apply(darkness)
    -- Skip changes too small to see; the end points are always exact.
    if darkness == applied then return end
    if applied and math.abs(darkness - applied) < 1 / 128 and darkness ~= 0 and darkness ~= Config.DarkLevel then return end
    applied = darkness

    local out = Config.DarkLevel > 0 and math.min(1, darkness / Config.DarkLevel) or 0
    LE.SetLighting(1 - darkness, out >= 0.5)
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
    LE.CurrentDarkness = current
end)

-- Players (whose colors come from a material proxy that would undo a material
-- change), your weapon and your hands: dimmed while they're drawn. Color
-- modulation goes through the same gamma-to-linear conversion as $color2.
local function Dim()
    if current <= 0 then return end
    local k = LE.ModelTint(1, LE.LightLeft(1 - current, LE.MaterialKinds.MODEL))
    render.SetColorModulation(k, k, k)
end
local function Undim()
    if current > 0 then render.SetColorModulation(1, 1, 1) end
end
hook.Add("PrePlayerDraw", "LightingEditor.Dim", Dim)
hook.Add("PostPlayerDraw", "LightingEditor.Dim", Undim)
hook.Add("PreDrawViewModel", "LightingEditor.Dim", Dim)
hook.Add("PostDrawViewModel", "LightingEditor.Dim", Undim)
hook.Add("PreDrawPlayerHands", "LightingEditor.Dim", Dim)
hook.Add("PostDrawPlayerHands", "LightingEditor.Dim", Undim)
