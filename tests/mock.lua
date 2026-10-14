-- Minimal Garry's Mod environment for running the addon in plain Lua 5.1.
-- Materials are simulated as parameter tables, so tests can check exactly what
-- the addon does to each one.

local M = {}
local ADDON_LUA = os.getenv("ADDON_LUA") or (HARNESS_DIR .. "../lua/")

---------------------------------------------------------------- GMod extensions
function math.Clamp(v, lo, hi) return math.min(math.max(v, lo), hi) end
function string.Trim(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end

local VEC = {}
VEC.__index = VEC
local function Vector(x, y, z)
    if type(x) == "table" then return setmetatable({ x = x.x, y = x.y, z = x.z }, VEC) end
    return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, VEC)
end
VEC.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
VEC.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
VEC.__mul = function(a, b) if type(a) == "number" then a, b = b, a end return Vector(a.x * b, a.y * b, a.z * b) end
function VEC:Dot(o) return self.x * o.x + self.y * o.y + self.z * o.z end
function VEC:Cross(o) return Vector(self.y * o.z - self.z * o.y, self.z * o.x - self.x * o.z, self.x * o.y - self.y * o.x) end
function VEC:Length() return math.sqrt(self:Dot(self)) end
function VEC:DistToSqr(o) local d = self - o return d:Dot(d) end
function VEC:GetNormalized() local l = self:Length() return Vector(self.x / l, self.y / l, self.z / l) end
M.Vector = Vector

local COLOR = {}
local function Color(r, g, b, a) return setmetatable({ r = r, g = g, b = b, a = a or 255 }, COLOR) end

---------------------------------------------------------------- shared world
M.queueToServer, M.queueToClients, M.pooled = {}, {}, {}
M.time = 100
M.errors = {}
M.materials, M.worldMaterials, M.entities = {}, {}, {}

function M.MakePlayer(name, admin)
    local p = { __valid = true, name = name, admin = admin, pos = Vector(0, 0, 0), chat = {} }
    function p:IsAdmin() return self.admin end
    function p:GetPos() return self.pos end
    function p:EyePos() return self.pos + Vector(0, 0, 64) end
    function p:WorldSpaceCenter() return self.pos + Vector(0, 0, 36) end
    function p:SteamID64() return "7656119" .. #name end
    function p:ChatPrint(m) table.insert(self.chat, m) end
    return p
end

function M.NewRealm(isServer, localPlayer)
    local env = setmetatable({}, { __index = _G })
    env._G = env
    env.SERVER, env.CLIENT = isServer, not isServer
    env.Vector, env.Color = Vector, Color
    env.color_white = Color(255, 255, 255)
    env.istable = function(v) return type(v) == "table" end
    env.isvector = function(v) return getmetatable(v) == VEC end
    env.IsValid = function(v) return type(v) == "table" and rawget(v, "__valid") == true end
    env.CurTime = function() return M.time end
    env.ErrorNoHalt = function(m) table.insert(M.errors, m) end
    env.AddCSLuaFile = function() end
    env.game = { GetMap = function() return "rp_test" end }
    env.include = function(path)
        local chunk = assert(loadfile(ADDON_LUA .. path))
        setfenv(chunk, env)
        return chunk()
    end
    env.util = { AddNetworkString = function(n) assert(isServer) M.pooled[n] = true end }
    env.print = function(...) env.printed = table.concat({ ... }, " ") end

    local hooks = {}
    env.hook = {
        Add = function(e, n, f) hooks[e] = hooks[e] or {} hooks[e][n] = f end,
        Run = function(e, ...)
            local names = {}
            for n in pairs(hooks[e] or {}) do table.insert(names, n) end
            table.sort(names)
            for _, n in ipairs(names) do
                local a, b = hooks[e][n](...)
                if a ~= nil then return a, b end
            end
        end
    }
    local commands = {}
    env.concommand = { Add = function(n, f) commands[n] = f end }
    env.RunCmd = function(ply, name, args) assert(commands[name], name)(ply, name, args or {}) end

    -- net with read/write type checking
    local receivers, out, inc = {}, nil, nil
    env.net = {
        Receive = function(n, f) receivers[n] = f end,
        Start = function(n) assert(M.pooled[n], "unpooled " .. n) out = { name = n, fields = {} } end,
        WriteUInt = function(v, bits) assert(v >= 0 and v < 2 ^ bits, "WriteUInt overflow") table.insert(out.fields, { "uint" .. bits, v }) end,
        WriteBool = function(v) assert(type(v) == "boolean") table.insert(out.fields, { "bool", v }) end,
        WriteFloat = function(v) assert(type(v) == "number") table.insert(out.fields, { "float", v }) end,
        Send = function(t) table.insert(M.queueToClients, { msg = out, target = t }) end,
        Broadcast = function() table.insert(M.queueToClients, { msg = out }) end,
        SendToServer = function() table.insert(M.queueToServer, { msg = out, sender = localPlayer }) end
    }
    local function reader(kind)
        return function(bits)
            local f = table.remove(inc.fields, 1)
            assert(f, "read past end of " .. inc.name)
            local want = kind == "uint" and ("uint" .. bits) or kind
            assert(f[1] == want, "net type mismatch: wrote " .. f[1] .. ", read " .. want)
            return f[2]
        end
    end
    env.net.ReadUInt, env.net.ReadBool, env.net.ReadFloat = reader("uint"), reader("bool"), reader("float")
    env.__deliver = function(msg, sender)
        inc = { name = msg.name, fields = { unpack(msg.fields) } }
        assert(receivers[msg.name], "no receiver " .. msg.name)(0, sender)
        assert(#inc.fields == 0, "unread fields left in " .. msg.name)
    end

    if not isServer then
        env.LocalPlayer = function() return localPlayer end
        env.sounds = {}
        env.surface = { PlaySound = function(snd) table.insert(env.sounds, snd) end }

        -- Materials: M.materials[name] = { shader = "...", params = { ["$color"] = Vector } }.
        -- Each client has its own copy of the materials, like separate games.
        env.materialDefs = {}
        for name, def in pairs(M.materials) do
            local params = {}
            for k, v in pairs(def.params) do params[k] = Vector(v) end
            env.materialDefs[name] = { shader = def.shader, params = params }
        end
        env.materialWrites = 0
        env.Material = function(name)
            local def = env.materialDefs[string.lower(name)]
            local mat = {}
            function mat:IsError() return def == nil end
            function mat:GetShader() return def and def.shader end
            function mat:GetVector(param) local v = def and def.params[param] return v and Vector(v) or nil end
            function mat:SetVector(param, v)
                assert(def, "SetVector on a missing material")
                def.params[param] = Vector(v)
                env.materialWrites = env.materialWrites + 1
            end
            return mat
        end
        env.game.GetWorld = function() return { GetMaterials = function() return M.worldMaterials end } end
        env.ents = { GetAll = function() return M.entities end }

        local lighting = { suppressed = false }
        env.modelLighting = lighting
        env.render = {
            SuppressEngineLighting = function(v) lighting.suppressed = v end,
            ResetModelLighting = function(r, g, b) lighting.ambient = { r, g, b } end,
            SetLocalModelLights = function(t) lighting.locals = t end,
            RedownloadAllLightmaps = function() error("lightmaps must never be redownloaded") end
        }
        env.engine = { LightStyle = function() error("light styles must never be changed") end }
    end

    return env
end

function M.Pump(server, clients)
    for _ = 1, 100 do
        local s = table.remove(M.queueToServer, 1)
        if s then server.__deliver(s.msg, s.sender) end
        local c = table.remove(M.queueToClients, 1)
        if c then
            for ply, realm in pairs(clients) do
                if not c.target or c.target == ply then realm.__deliver(c.msg) end
            end
        end
        if not s and not c then return end
    end
    error("message loop")
end

return M
