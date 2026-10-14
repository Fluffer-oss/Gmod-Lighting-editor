local LE = LightingEditor

util.AddNetworkString(LE.NetState)
util.AddNetworkString(LE.NetRequest)

-- key -> { deck, sectionId, out = bool, changedAt = CurTime() }. Restored sections
-- stay listed briefly so clients can play the lights-coming-back transition.
LE.Outages = LE.Outages or {}

local function WriteState()
    local entries = {}
    for _, entry in pairs(LE.Outages) do
        table.insert(entries, entry)
    end

    net.WriteUInt(#entries, 12)
    for _, entry in ipairs(entries) do
        net.WriteUInt(entry.deck, 8)
        net.WriteUInt(entry.sectionId, 16)
        net.WriteBool(entry.out)
        net.WriteFloat(entry.changedAt)
    end
end

local function SendState(target)
    net.Start(LE.NetState)
    WriteState()
    if target then net.Send(target) else net.Broadcast() end
end

local function ForgetRestored()
    local cutoff = CurTime() - (LE.Config.FlickerInTime + LE.Config.FadeInTime + 2)
    for key, entry in pairs(LE.Outages) do
        if not entry.out and entry.changedAt < cutoff then
            LE.Outages[key] = nil
        end
    end
end

-- Public API: other addons (damage, red alert, engineering consoles) can call this.
-- Returns true if anything changed. Pass noSync when changing many at once, then
-- call LE.SyncPower() once.
function LE.SetSectionPower(deck, sectionId, powered, noSync)
    deck, sectionId = tonumber(deck), tonumber(sectionId)
    if not deck or not sectionId then return false end

    local key = LE.SectionKey(deck, sectionId)
    local entry = LE.Outages[key]
    local isOut = entry and entry.out or false
    if isOut == not powered then return false end

    ForgetRestored()
    LE.Outages[key] = { deck = deck, sectionId = sectionId, out = not powered, changedAt = CurTime() }
    if not noSync then SendState() end
    hook.Run("LightingEditor.SectionPowerChanged", deck, sectionId, powered)
    return true
end

function LE.SyncPower()
    SendState()
end

function LE.IsSectionPowered(deck, sectionId)
    local entry = LE.Outages[LE.SectionKey(deck, sectionId)]
    return not (entry and entry.out)
end

-- Resolves command arguments to a list of { deck, sectionId }:
--   "here"        the section the player is standing in
--   "ship"        every section on every deck
--   "<deck>"      every section on that deck
--   "<deck> <id>" one section; id as the map names it, e.g. 4 or 4A
local function ResolveTargets(ply, args)
    local decks = LE.GetDecks()
    if not decks then
        return nil, "Star Trek Modules' sections aren't loaded on this map."
    end

    local first = string.lower(tostring(args[1] or ""))
    local targets = {}

    if first == "here" then
        if not IsValid(ply) then return nil, "'here' needs a player." end
        -- Body center, not feet: feet on the floor sit right on a section box's bottom edge.
        local deck, sectionId = LE.FindSection(ply:WorldSpaceCenter())
        if not deck then return nil, "You're not inside any section." end
        table.insert(targets, { deck, sectionId })
    elseif first == "ship" then
        for deck, deckData in pairs(decks) do
            for sectionId in pairs(deckData.Sections or {}) do
                table.insert(targets, { deck, sectionId })
            end
        end
    else
        local deck = tonumber(args[1])
        if not deck or not decks[deck] then
            return nil, "Usage: here | ship | <deck> [section]   (no deck " .. tostring(args[1]) .. ")"
        end
        if args[2] then
            local sectionId = LE.ParseSectionId(args[2])
            if not sectionId or not decks[deck].Sections[sectionId] then
                return nil, string.format("Deck %d has no section %s.", deck, tostring(args[2]))
            end
            table.insert(targets, { deck, sectionId })
        else
            for sectionId in pairs(decks[deck].Sections or {}) do
                table.insert(targets, { deck, sectionId })
            end
        end
    end

    return targets
end

function LE.RunPowerCommand(ply, args, powered)
    if not LE.CanControl(ply) then
        return false, "You don't have permission to control ship power."
    end

    local targets, err = ResolveTargets(ply, args)
    if not targets then return false, err end

    local changed = 0
    for _, target in ipairs(targets) do
        if LE.SetSectionPower(target[1], target[2], powered, true) then
            changed = changed + 1
        end
    end
    if changed > 0 then SendState() end

    local what = #targets == 1 and LE.SectionName(targets[1][1], targets[1][2]) or (#targets .. " sections")
    if changed == 0 then
        return true, string.format("%s already %s.", what, powered and "has power" or "is dark")
    end
    return true, string.format("Power %s: %s.", powered and "restored to" or "cut in", what)
end

local function Reply(ply, message)
    if IsValid(ply) then ply:ChatPrint("[Lighting] " .. message) else print("[Lighting] " .. message) end
end

concommand.Add("lighting_outage", function(ply, _, args)
    local _, message = LE.RunPowerCommand(ply, args, false)
    Reply(ply, message)
end)

concommand.Add("lighting_restore", function(ply, _, args)
    local _, message = LE.RunPowerCommand(ply, args, true)
    Reply(ply, message)
end)

-- Clients ask once their Lua is ready, so late joiners see sections already dark.
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
            arguments = { ix.type.string, bit.bor(ix.type.string, ix.type.optional) },
            OnRun = function(_, client, where, section)
                local _, message = LE.RunPowerCommand(client, { where, section }, powered)
                return message
            end
        })
    end

    Register("PowerOutage", false, "Cut power: here | ship | <deck> [section]")
    Register("PowerRestore", true, "Restore power: here | ship | <deck> [section]")
end)
