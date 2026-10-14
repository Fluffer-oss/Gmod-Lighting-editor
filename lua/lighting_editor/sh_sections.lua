local LE = LightingEditor

-- Star Trek Modules' section system: Star_Trek.Sections.Decks[deck].Sections[sectionId]
-- = { RealId = "4A", Name = "...", Areas = { { Min = Vector, Max = Vector }, ... } }.
-- The server builds it from the map's "section<deck>_<id>" triggers and syncs it to
-- every client, so both realms can use it.
function LE.GetDecks()
    local sections = Star_Trek and Star_Trek.Sections
    return sections and istable(sections.Decks) and sections.Decks or nil
end

-- Same numbering Star Trek Modules uses: "4" -> 400, "4A" -> 401, "4B" -> 402.
function LE.ParseSectionId(text)
    text = string.upper(string.Trim(tostring(text or "")))
    local plain = tonumber(text)
    if plain then
        return plain >= 100 and plain or plain * 100
    end

    local number, letter = string.match(text, "^(%d+)(%a)$")
    if not number then return nil end
    return tonumber(number) * 100 + (string.byte(letter) - 64)
end

function LE.SectionKey(deck, sectionId)
    return tostring(deck) .. ":" .. tostring(sectionId)
end

function LE.GetSection(deck, sectionId)
    local decks = LE.GetDecks()
    local deckData = decks and decks[deck]
    return deckData and deckData.Sections and deckData.Sections[sectionId] or nil
end

function LE.SectionName(deck, sectionId)
    local section = LE.GetSection(deck, sectionId)
    if not section then return string.format("deck %s section %s", deck, sectionId) end
    return string.format("deck %d section %s (%s)", deck, tostring(section.RealId), tostring(section.Name))
end

local function InBox(pos, min, max)
    return pos.x > min.x and pos.x < max.x and pos.y > min.y and pos.y < max.y and pos.z > min.z and pos.z < max.z
end
LE.InBox = InBox

function LE.FindSection(pos)
    local decks = LE.GetDecks()
    if not decks then return nil end

    for deck, deckData in pairs(decks) do
        for sectionId, section in pairs(deckData.Sections or {}) do
            for _, area in ipairs(section.Areas or {}) do
                if InBox(pos, area.Min, area.Max) then
                    return deck, sectionId
                end
            end
        end
    end
end

-- Distance from a point to the nearest of a section's boxes (0 if inside one).
function LE.DistanceToBox(area, pos)
    local dx = math.max(area.Min.x - pos.x, 0, pos.x - area.Max.x)
    local dy = math.max(area.Min.y - pos.y, 0, pos.y - area.Max.y)
    local dz = math.max(area.Min.z - pos.z, 0, pos.z - area.Max.z)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function LE.DistanceToSection(section, pos)
    local best = math.huge
    for _, area in ipairs(section.Areas or {}) do
        best = math.min(best, LE.DistanceToBox(area, pos))
    end
    return best
end
