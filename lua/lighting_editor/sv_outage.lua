local LE = LightingEditor

util.AddNetworkString(LE.NetState)
util.AddNetworkString(LE.NetRequest)

-- deck -> { deck, out = bool, changedAt = CurTime() }. Restored decks stay listed
-- briefly so clients can play the lights-coming-back transition.
LE.Outages = LE.Outages or {}

local function SendState(target)
    local entries = {}
    for _, entry in pairs(LE.Outages) do
        table.insert(entries, entry)
    end

    net.Start(LE.NetState)
    net.WriteUInt(#entries, 8)
    for _, entry in ipairs(entries) do
        net.WriteUInt(entry.deck, 8)
        net.WriteBool(entry.out)
        net.WriteFloat(entry.changedAt)
    end
    if target then net.Send(target) else net.Broadcast() end
end

local function ForgetRestored()
    local cutoff = CurTime() - (LE.Config.FlickerInTime + LE.Config.FadeInTime + 2)
    for deck, entry in pairs(LE.Outages) do
        if not entry.out and entry.changedAt < cutoff then
            LE.Outages[deck] = nil
        end
    end
end

-- Public API: other addons (damage, red alert, engineering consoles) can call this.
-- Returns true if anything changed. Pass noSync when changing many at once, then
-- call LE.SyncPower() once.
function LE.SetDeckPower(deck, powered, noSync)
    deck = tonumber(deck)
    if not deck or deck < 0 or deck > 255 then return false end
    if LE.IsDeckPowered(deck) == powered then return false end

    ForgetRestored()
    LE.Outages[deck] = { deck = deck, out = not powered, changedAt = CurTime() }
    if not noSync then SendState() end
    hook.Run("LightingEditor.DeckPowerChanged", deck, powered)
    return true
end

function LE.SyncPower()
    SendState()
end

function LE.IsDeckPowered(deck)
    local entry = LE.Outages[tonumber(deck)]
    return not (entry and entry.out)
end

-- Resolves a command argument to a list of decks:
--   "here"    the deck the player is on
--   "ship"    every deck
--   "<deck>"  that deck
local function ResolveDecks(ply, where)
    local decks = LE.GetDecks()
    if not decks then
        return nil, "Star Trek Modules' sections aren't loaded on this map."
    end

    where = string.lower(tostring(where or ""))
    if where == "here" then
        if not IsValid(ply) then return nil, "'here' needs a player." end
        -- Body center, not feet: feet on the floor sit right on a section box's bottom edge.
        local deck = LE.FindDeck(ply:WorldSpaceCenter())
        if not deck then return nil, "You're not on any deck." end
        return { deck }
    elseif where == "ship" then
        local list = {}
        for deck in pairs(decks) do table.insert(list, deck) end
        table.sort(list)
        return list
    end

    local deck = tonumber(where)
    if not deck or not decks[deck] then
        return nil, "Usage: here | ship | <deck>   (no deck " .. where .. ")"
    end
    return { deck }
end

function LE.RunPowerCommand(ply, where, powered)
    if not LE.CanControl(ply) then
        return false, "You don't have permission to control ship power."
    end

    local list, err = ResolveDecks(ply, where)
    if not list then return false, err end

    local changed = 0
    for _, deck in ipairs(list) do
        if LE.SetDeckPower(deck, powered, true) then
            changed = changed + 1
        end
    end
    if changed > 0 then SendState() end

    local what = #list == 1 and ("deck " .. list[1]) or (#list .. " decks")
    if changed == 0 then
        return true, string.format("%s already %s.", what, powered and "has power" or "is dark")
    end
    return true, string.format("Power %s: %s.", powered and "restored to" or "cut on", what)
end

local function Reply(ply, message)
    if IsValid(ply) then ply:ChatPrint("[Lighting] " .. message) else print("[Lighting] " .. message) end
end

concommand.Add("lighting_outage", function(ply, _, args)
    local _, message = LE.RunPowerCommand(ply, args[1], false)
    Reply(ply, message)
end)

concommand.Add("lighting_restore", function(ply, _, args)
    local _, message = LE.RunPowerCommand(ply, args[1], true)
    Reply(ply, message)
end)

-- Clients ask once their Lua is ready, so late joiners see decks already dark.
net.Receive(LE.NetRequest, function(_, ply)
    if IsValid(ply) then SendState(ply) end
end)

-- Helix chat commands, when the schema is Helix-based.
hook.Add("InitializedPlugins", "LightingEditor.HelixCommands", function()
    if not (ix and ix.command and ix.command.Add) then return end

    local function Register(name, powered, description)
        ix.command.Add(name, {
            description = description,
            adminOnly = true,
            arguments = ix.type.string,
            OnRun = function(_, client, where)
                local _, message = LE.RunPowerCommand(client, where, powered)
                return message
            end
        })
    end

    Register("PowerOutage", false, "Cut power: here | ship | <deck>")
    Register("PowerRestore", true, "Restore power: here | ship | <deck>")
end)
