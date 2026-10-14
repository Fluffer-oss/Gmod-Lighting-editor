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
function VEC:Distance(o) return (self - o):Length() end
function VEC:GetNormalized() local l = self:Length() return Vector(self.x / l, self.y / l, self.z / l) end
M.Vector = Vector

local COLOR = {}
local function Color(r, g, b, a) return setmetatable({ r = r, g = g, b = b, a = a or 255 }, COLOR) end
M.Color = function(...) return Color(...) end

---------------------------------------------------------------- shared world
M.queueToServer, M.queueToClients, M.pooled = {}, {}, {}
M.time = 100
M.errors = {}
M.materials, M.worldMaterials, M.entities, M.serverEntities, M.files = {}, {}, {}, {}, {}
M.sysTime, M.sysTimeStep = 0, 0.00005

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

    env.isstring = function(v) return type(v) == "string" end
    env.isfunction = function(v) return type(v) == "function" end
    env.timer = { Simple = function(_, f) f() end }

    -- Read-only game files: M.files[path] = bytes.
    env.file = { Open = function(path, mode, where)
        assert(mode == "rb" and where == "GAME", "files are only read")
        local data = M.files[path]
        if not data then return nil end
        local pos = 0
        return {
            Read = function(_, n) local chunk = data:sub(pos + 1, pos + n) pos = pos + #chunk return chunk end,
            Seek = function(_, p) pos = p end,
            Size = function() return #data end,
            Close = function() end
        }
    end }

    if isServer then
        env.ents = { FindByClass = function(class)
            local found = {}
            for _, ent in ipairs(M.serverEntities) do if ent.class == class then table.insert(found, ent) end end
            return found
        end }
    else
        env.LocalPlayer = function() return localPlayer end
        env.EyePos = function() return localPlayer:EyePos() end
        env.SysTime = function() M.sysTime = M.sysTime + M.sysTimeStep return M.sysTime end
        env.sounds = {}
        env.surface = { PlaySound = function(snd) table.insert(env.sounds, snd) end }

        -- Materials, simulated: M.materials[name] = { shader, params = { [param] = value } }.
        -- Each client has its own copy, like separate games.
        env.materialDefs = {}
        for name, def in pairs(M.materials) do
            local params = {}
            for k, v in pairs(def.params) do params[k] = getmetatable(v) == VEC and Vector(v) or v end
            env.materialDefs[name] = { shader = def.shader, params = params }
        end
        env.materialWrites = 0
        env.Material = function(name)
            local def = env.materialDefs[string.lower(name)]
            local mat = {}
            local function get(param, kind)
                local v = def and def.params[param]
                if v == nil then return nil end
                if kind == "vector" then assert(getmetatable(v) == VEC, param .. " isn't a vector") return Vector(v) end
                if kind == "number" then assert(type(v) == "number", param .. " isn't a number") return v end
                if kind == "string" then return type(v) == "table" and v.textureName or tostring(v) end
                return v
            end
            local function set(param, v)
                assert(def, "writing to a missing material")
                def.params[param] = v
                env.materialWrites = env.materialWrites + 1
            end
            function mat:IsError() return def == nil end
            function mat:GetShader() return def and def.shader end
            function mat:GetVector(param) return get(param, "vector") end
            function mat:GetInt(param) local v = get(param, "number") return v and math.floor(v) end
            function mat:GetFloat(param) return get(param, "number") end
            function mat:GetString(param) return get(param, "string") end
            function mat:GetTexture(param) return get(param) end
            function mat:SetVector(param, v) assert(getmetatable(v) == VEC) set(param, Vector(v)) end
            function mat:SetFloat(param, v) assert(type(v) == "number") set(param, v) end
            function mat:SetTexture(param, t) assert(type(t) == "table" and t.textureName, "SetTexture needs a texture") set(param, t) end
            return mat
        end
        env.renderTargets = {}
        env.GetRenderTarget = function(name)
            env.renderTargets[name] = env.renderTargets[name] or { textureName = name, cleared = nil }
            return env.renderTargets[name]
        end
        env.game.GetWorld = function() return { GetMaterials = function() return M.worldMaterials end } end
        local function clientEnts() local t = {} for _, e in ipairs(M.entities) do if e.__valid then table.insert(t, e) end end return t end
        env.ents = {
            GetAll = clientEnts,
            FindByClass = function(class)
                local found = {}
                for _, ent in ipairs(clientEnts()) do if ent:GetClass() == class then table.insert(found, ent) end end
                return found
            end
        }
        env.dlights = {}
        env.DynamicLight = function(index) env.dlights[index] = env.dlights[index] or {} return env.dlights[index] end

        local target
        env.modulation = { 1, 1, 1 }
        env.render = {
            PushRenderTarget = function(rt) target = rt end,
            Clear = function(r, g, b, a) assert(target) target.cleared = { r, g, b, a } end,
            PopRenderTarget = function() target = nil end,
            SetColorModulation = function(r, g, b) env.modulation = { r, g, b } end,
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
