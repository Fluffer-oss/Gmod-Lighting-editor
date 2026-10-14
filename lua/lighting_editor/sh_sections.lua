local LE = LightingEditor

-- Star Trek Modules' section system: Star_Trek.Sections.Decks[deck].Sections[sectionId]
-- = { RealId = "4A", Name = "...", Areas = { { Min = Vector, Max = Vector }, ... } }.
-- The server builds it from the map's "section<deck>_<id>" triggers and syncs it to
-- every client, so both realms can use it.
function LE.GetDecks()
    local sections = Star_Trek and Star_Trek.Sections
    return sections and istable(sections.Decks) and sections.Decks or nil
end

local function InBox(pos, min, max)
    return pos.x > min.x and pos.x < max.x and pos.y > min.y and pos.y < max.y and pos.z > min.z and pos.z < max.z
end

local function DistanceToBox(area, pos)
    local dx = math.max(area.Min.x - pos.x, 0, pos.x - area.Max.x)
    local dy = math.max(area.Min.y - pos.y, 0, pos.y - area.Max.y)
    local dz = math.max(area.Min.z - pos.z, 0, pos.z - area.Max.z)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- The deck a position is on. Inside a section box, that section's deck.
-- Otherwise (corridors and rooms the sections miss), the deck whose overall
-- extent contains the position, padded by Config.DeckPadding; if several do,
-- the one with a section box nearest to it. nil if it's on no deck.
function LE.FindDeck(pos)
    local decks = LE.GetDecks()
    if not decks then return nil end

    local pad = LE.Config.DeckPadding
    local best, bestDistance
    for deck, deckData in pairs(decks) do
        local min, max, nearest = nil, nil, math.huge
        for _, section in pairs(deckData.Sections or {}) do
            for _, area in ipairs(section.Areas or {}) do
                if InBox(pos, area.Min, area.Max) then return deck end
                nearest = math.min(nearest, DistanceToBox(area, pos))
                min = min and Vector(math.min(min.x, area.Min.x), math.min(min.y, area.Min.y), math.min(min.z, area.Min.z)) or Vector(area.Min)
                max = max and Vector(math.max(max.x, area.Max.x), math.max(max.y, area.Max.y), math.max(max.z, area.Max.z)) or Vector(area.Max)
            end
        end
        if min and InBox(pos, min - Vector(pad, pad, pad), max + Vector(pad, pad, pad))
            and (not bestDistance or nearest < bestDistance) then
            best, bestDistance = deck, nearest
        end
    end
    return best
end
