local LE = LightingEditor
local Config = LE.Config

-- The map's own light entities on a dark deck: dynamic lights, projected
-- textures, spotlights, named lights, and the sprites and glows that make light
-- fixtures look lit. Switched off here on the server, so everyone sees them off.
-- Only what this addon switched off is switched back on.

LE.SwitchedOff = LE.SwitchedOff or {} -- entity -> how it was switched off

-- STM dims the bridge by switching these lights off during some alerts;
-- they mustn't be switched back on while that alert is still active.
local function HeldOffByAlert(ent)
    local alert = Star_Trek and Star_Trek.Alert
    if not (alert and alert.ActiveAlert and alert.BridgeDimName) then return false end
    local alertType = alert.AlertTypes and alert.AlertTypes[alert.ActiveAlert]
    return alertType and alertType.BridgeDim and ent:GetName() == alert.BridgeDimName or false
end

-- Whether a light is on now. A light's TurnOff sets its "starts off" spawn
-- flag; the others keep their state in a variable.
local function IsOn(ent, how)
    if how.startsOff then return not ent:HasSpawnFlags(how.startsOff) end
    if how.state then
        local state = ent:GetInternalVariable(how.state)
        return state ~= false and state ~= 0
    end
    return true
end

local function SwitchOff(ent, how)
    if LE.SwitchedOff[ent] then return end
    if how == "hide" then
        if ent:GetNoDraw() then return end -- already hidden by something else
        ent:SetNoDraw(true)
    else
        if not IsOn(ent, how) then return end
        ent:Fire(how.off)
    end
    LE.SwitchedOff[ent] = how
end

local function SwitchOn(ent, how)
    LE.SwitchedOff[ent] = nil
    if how == "hide" then
        ent:SetNoDraw(false)
    elseif not HeldOffByAlert(ent) then
        ent:Fire(how.on)
    end
end

-- Brings every map light in line with deck power.
function LE.UpdateMapLights()
    for ent, how in pairs(LE.SwitchedOff) do
        if not IsValid(ent) then
            LE.SwitchedOff[ent] = nil
        else
            local deck = LE.FindDeck(ent:GetPos())
            if not deck or LE.IsDeckPowered(deck) then SwitchOn(ent, how) end
        end
    end

    if next(LE.Outages) == nil then return end
    for class, how in pairs(Config.MapLights) do
        for _, ent in ipairs(ents.FindByClass(class)) do
            local deck = LE.FindDeck(ent:GetPos())
            if deck and not LE.IsDeckPowered(deck) then SwitchOff(ent, how) end
        end
    end
end

hook.Add("LightingEditor.DeckPowerChanged", "LightingEditor.MapLights", function()
    LE.UpdateMapLights()
end)

-- A map cleanup recreates the map's entities with their lights on.
hook.Add("PostCleanupMap", "LightingEditor.MapLights", function()
    LE.SwitchedOff = {}
    timer.Simple(0, LE.UpdateMapLights)
end)

-- STM's alerts switch the bridge lights back on when they end; keep them off
-- if the bridge's deck has no power.
local function WrapAlert()
    local alert = Star_Trek and Star_Trek.Alert
    if not alert or alert.LightingEditorWrapped then return end
    alert.LightingEditorWrapped = true
    for _, name in ipairs({ "Enable", "Disable" }) do
        local original = alert[name]
        if isfunction(original) then
            alert[name] = function(...)
                local results = { original(...) }
                for ent in pairs(LE.SwitchedOff) do
                    if IsValid(ent) and LE.SwitchedOff[ent] ~= "hide" and ent:GetName() == alert.BridgeDimName then
                        ent:Fire(LE.SwitchedOff[ent].off)
                    end
                end
                LE.UpdateMapLights()
                return unpack(results)
            end
        end
    end
end
hook.Add("InitPostEntity", "LightingEditor.WrapAlert", WrapAlert)
hook.Add("Star_Trek.ModulesLoaded", "LightingEditor.WrapAlert", WrapAlert)
WrapAlert()
