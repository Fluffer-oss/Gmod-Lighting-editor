local LE = LightingEditor
local Config = LE.Config

-- With the power out, a light fixture's texture is swapped for a copy whose
-- glowing parts are black, while the rest of it (frames, colored markings,
-- detail) stays. The glowing parts are the bright parts (the lit panel, the
-- white strip), and the parts the material itself marks as emissive: its
-- self-illumination mask, either the texture's alpha or a $selfillummask.
-- Each copy is made once, on the graphics card, in a few draws into render
-- targets, one texture per frame:
--   1. bright = the texture's brightness (gray), minus Config.GlowThreshold
--   2. emissive = the self-illumination mask, if it has one
--   3. mask = bright stretched so anything clearly bright becomes 1, or emissive, whichever is more
--   4. copy = the texture (alpha and all), times (1 - mask)

local MAX_SIZE = 1024

local function Target(name, w, h)
    return GetRenderTargetEx(name, w, h, RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_NONE, 0, 0, IMAGE_FORMAT_RGBA8888)
end

-- One material per step: changing a material's texture between draws in the
-- same frame isn't safe with queued rendering, and one texture is done per frame.
local grayMat = CreateMaterial("lightingeditor_gray", "g_colourmodify", {
    ["$fbtexture"] = "vgui/white", ["$ignorez"] = 1,
    ["$pp_colour_addr"] = 0, ["$pp_colour_addg"] = 0, ["$pp_colour_addb"] = 0,
    ["$pp_colour_brightness"] = 0, ["$pp_colour_contrast"] = 1, ["$pp_colour_colour"] = 0,
    ["$pp_colour_mulr"] = 0, ["$pp_colour_mulg"] = 0, ["$pp_colour_mulb"] = 0
})
local maskMat = CreateMaterial("lightingeditor_mask", "UnlitGeneric", { ["$basetexture"] = "vgui/white", ["$ignorez"] = 1 })
local alphaMat = CreateMaterial("lightingeditor_alpha", "UnlitGeneric", { ["$basetexture"] = "vgui/white", ["$ignorez"] = 1, ["$translucent"] = 1 })
local grayMaskMat = CreateMaterial("lightingeditor_graymask", "g_colourmodify", {
    ["$fbtexture"] = "vgui/white", ["$ignorez"] = 1,
    ["$pp_colour_addr"] = 0, ["$pp_colour_addg"] = 0, ["$pp_colour_addb"] = 0,
    ["$pp_colour_brightness"] = 0, ["$pp_colour_contrast"] = 1, ["$pp_colour_colour"] = 0,
    ["$pp_colour_mulr"] = 0, ["$pp_colour_mulg"] = 0, ["$pp_colour_mulb"] = 0
})
local emissiveMat = CreateMaterial("lightingeditor_emissive", "UnlitGeneric", { ["$basetexture"] = "vgui/white", ["$ignorez"] = 1 })
-- Translucent, so it outputs the texture's own alpha (an opaque material's
-- alpha can't be relied on: Source may write depth into it).
local sourceMat = CreateMaterial("lightingeditor_source", "UnlitGeneric", { ["$basetexture"] = "vgui/white", ["$ignorez"] = 1, ["$translucent"] = 1 })
local stretchedMat = CreateMaterial("lightingeditor_stretched", "UnlitGeneric", { ["$basetexture"] = "vgui/white", ["$ignorez"] = 1 })

local function Draw(mat, w, h)
    surface.SetDrawColor(255, 255, 255, 255)
    surface.SetMaterial(mat)
    surface.DrawTexturedRect(0, 0, w, h)
end

local function Into(target, fn)
    render.PushRenderTarget(target)
    cam.Start2D()
    fn()
    cam.End2D()
    render.OverrideBlend(false)
    render.PopRenderTarget()
end

local count = 0
-- emissive: nil, "alpha" (the texture's alpha marks what glows) or a mask texture.
-- bright: whether its bright parts count as glowing too.
local function Build(texture, emissive, bright)
    local w, h = texture:Width(), texture:Height()
    if not w or not h or w <= 0 or h <= 0 then return false end
    local scale = math.min(1, MAX_SIZE / math.max(w, h))
    w, h = math.max(1, math.floor(w * scale)), math.max(1, math.floor(h * scale))

    count = count + 1
    local result = Target("lightingeditor_glow_" .. count, w, h)
    local mask = Target("lightingeditor_mask_" .. w .. "x" .. h, w, h)
    local stretched = Target("lightingeditor_stretched_" .. w .. "x" .. h, w, h)
    local threshold = math.Clamp(Config.GlowThreshold, 0, 0.99)

    -- 1. Brightness, minus the threshold (the target can't go below 0).
    if bright then Into(mask, function()
        render.Clear(0, 0, 0, 255)
        grayMat:SetTexture("$fbtexture", texture)
        render.OverrideBlend(true, BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD)
        Draw(grayMat, w, h)
        render.OverrideBlend(true, BLEND_ONE, BLEND_ONE, BLENDFUNC_REVERSE_SUBTRACT)
        local t = math.floor(threshold * 255 + 0.5)
        surface.SetDrawColor(t, t, t, 255)
        surface.DrawRect(0, 0, w, h)
    end) end

    -- 2. What the material marks as emissive, as gray.
    local emissiveTarget
    if emissive then
        emissiveTarget = Target("lightingeditor_emissive_" .. w .. "x" .. h, w, h)
        Into(emissiveTarget, function()
            if emissive == "alpha" then
                -- White, times the texture's alpha.
                render.Clear(255, 255, 255, 255)
                alphaMat:SetTexture("$basetexture", texture)
                render.OverrideBlend(true, BLEND_ZERO, BLEND_SRC_ALPHA, BLENDFUNC_ADD)
                Draw(alphaMat, w, h)
            else
                render.Clear(0, 0, 0, 255)
                grayMaskMat:SetTexture("$fbtexture", emissive)
                render.OverrideBlend(true, BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD)
                Draw(grayMaskMat, w, h)
            end
        end)
    end

    -- 3. Bright parts stretched so the brightest reach 1 (the target can't go
    -- above 1), or the emissive parts, whichever is more.
    Into(stretched, function()
        render.Clear(0, 0, 0, 255)
        maskMat:SetTexture("$basetexture", mask)
        render.OverrideBlend(true, BLEND_ONE, BLEND_ONE, BLENDFUNC_ADD)
        if bright then
            for _ = 1, math.ceil(1 / (1 - threshold)) do Draw(maskMat, w, h) end
        end
        if emissiveTarget then
            emissiveMat:SetTexture("$basetexture", emissiveTarget)
            render.OverrideBlend(true, BLEND_ONE, BLEND_ONE, BLENDFUNC_MAX)
            Draw(emissiveMat, w, h)
        end
    end)

    -- 4. The texture, alpha and all, with its bright parts multiplied away.
    Into(result, function()
        render.Clear(0, 0, 0, 0)
        sourceMat:SetTexture("$basetexture", texture)
        render.OverrideBlend(true, BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD, BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD)
        Draw(sourceMat, w, h)
        stretchedMat:SetTexture("$basetexture", stretched)
        render.OverrideBlend(true, BLEND_ZERO, BLEND_ONE_MINUS_SRC_COLOR, BLENDFUNC_ADD, BLEND_ZERO, BLEND_ONE, BLENDFUNC_ADD)
        Draw(stretchedMat, w, h)
    end)

    return result
end

-- key -> result texture, or false if it couldn't be made
local results, queue, waiting = {}, {}, {}

-- Calls done(texture) with the copy of `texture` with its glowing parts dark,
-- or with nil if it can't be made (the caller falls back to plain black).
-- emissive: nil, "alpha" or a self-illumination mask texture; bright: whether
-- its bright parts count as glowing too.
function LE.RequestDarkGlow(texture, emissive, bright, done)
    local key = texture:GetName() .. "|" .. (emissive == "alpha" and "alpha" or emissive and emissive:GetName() or "") .. "|" .. tostring(bright)
    if results[key] ~= nil then
        done(results[key] or nil)
        return
    end
    if not waiting[key] then
        waiting[key] = {}
        table.insert(queue, { key = key, texture = texture, emissive = emissive, bright = bright })
    end
    table.insert(waiting[key], done)
end

hook.Add("PreRender", "LightingEditor.GlowTextures", function()
    local job = table.remove(queue, 1)
    if not job then return end

    local name, texture = job.key, job.texture
    local ok, result = pcall(Build, texture, job.emissive, job.bright)
    if not ok then
        ErrorNoHalt("[Lighting] Couldn't darken " .. tostring(name) .. ": " .. tostring(result) .. "\n")
        result = false
    end
    results[name] = result or false
    for _, done in ipairs(waiting[name] or {}) do done(result or nil) end
    waiting[name] = nil
end)
