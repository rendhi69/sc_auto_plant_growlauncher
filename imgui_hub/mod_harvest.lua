-- ============================================================================
-- BOREN HUB IMGUI - MODUL AUTO HARVEST PRO (ENGINE + UI)
-- File: imgui_hub/mod_harvest.lua
-- Repo Harvest: https://github.com/rendhi69/sc_harvest_growlauncher.git
-- Fitur:
--   1. Multi-World Farm List (WORLD:DOOR:ITEM_ID) + Item ID (auto pair Block/Seed)
--   2. Multi-World Save List (WORLD:DOOR:TYPE:LIMIT) - opsi simpan GABUNG, BLOCK saja, atau SEED saja
--      + limit per world custom (10k, 20k, dll.) + posisi drop rapi
--   3. Default Drop Threshold = 200 block
--   4. Multi-World Save Event / Mooncake List (WORLD:DOOR:LIMIT) dengan limit total item
--   5. Custom List ID Item Event (default Mooncake: 1058,1094,1096,1098,1828)
--   6. Auto Magni (1252) & Fuel Pack (1746) terintegrasi + Fuel Guard anti-rugi
--   7. Gear Equip List ID (DCS 6840, Harvester 1966/1830, dll.) dari Gear World
--   8. Ignore Gems (ID 112) via onSendPacketRaw
--   9. Mode 3-Zigzag Serpentine & 1-by-1
--  10. Opsional Take Floating setelah pohon habis
-- ============================================================================

local HV = {
    id      = "harvest",
    label   = "Harvest",
    VERSION = "1.2.0",
    META    = {
        type    = "boren_gl_feature",
        id      = "harvest",
        label   = "Harvest",
        order   = 15,
        enabled = true,
    },
}

HV.CFG = {
    default_item_id    = 4584,          -- Block genap / Seed ganjil (auto pair)
    drop_threshold     = 200,           -- Default 200 block (permintaan user)
    default_save_limit = 20000,         -- Default limit save world
    default_ev_limit   = 10000,         -- Default limit event world
    ignore_gems        = true,          -- Blokir collect Gems (ID 112)
    harvest_mode       = "3zigzag",     -- "3zigzag" | "1by1"
    harvest_delay      = 180,
    step_delay         = 110,
    warp_delay         = 4500,
    use_modfly         = true,
    loop_enabled       = false,
    auto_collect       = true,
    collect_range      = 4,
    take_block         = true,          -- Opsi ambil block hasil panen sesuai ID
    take_seed          = true,          -- Opsi ambil seed hasil panen sesuai ID,
    event_ids_raw      = "1058,1094,1096,1098,1828", -- Mooncakes default
    event_threshold    = 150,
    gear_world         = "",            -- 1 world khusus Magni / Fuel Pack / Gear
    auto_magni_fuel    = false,         -- Auto ambil Magni (1252) & Fuel Pack (1746)
    fuel_target_amt    = 100,
    stop_if_no_fuel    = true,          -- Proteksi: stop aman jika Fuel Pack habis di tas & Gear World
    gear_equip_ids     = "6840, 1966",  -- List ID alat/gear to equip (DCS, Harvester, dll.)
    use_dcs_harvester  = false,          -- Default OFF: Gunakan DCS & Harvester (Hand/Back)
    take_floating      = true,          -- Sapu sisa block/seed/event setelah tree habis
}

HV.STATE = {
    enabled          = false,
    running          = false,
    status_text      = "Idle",
    rows             = {},              -- { { name="W", door="D", item_id=4584, status="Ready" }, ... }
    selected_idx     = 0,
    save_rows        = {},              -- { { name="W", door="D", save_type="ALL"|"BLOCK"|"SEED", limit=20000, count=0, status="Ready" }, ... }
    selected_save    = 0,
    event_rows       = {},              -- { { name="W", door="D", limit=10000, count=0, status="Ready" }, ... }
    selected_ev      = 0,
    anti_take        = false,
    is_dropping      = false,
    pending_drop_id  = 0,
    pending_drop_amt = 0,
    drop_confirmed   = false,
    need_fuel        = false,
    total_harvested  = 0,
    total_dropped    = 0,
    logs             = {},
    inv_preview      = { block = 0, seed = 0, ev = 0, fuel = 0 },
}

local HUB_REF = nil
local activeSub = "farms"

-- UI Buffers
local addFarmWorldBuf = ""
local addFarmItemBuf  = "4584"

local addSaveWorldBuf = ""
local addSaveTypeBuf  = "ALL"           -- "ALL" | "BLOCK" | "SEED"
local addSaveLimitBuf = "20000"

local addEventWorldBuf = ""
local addEventLimitBuf = "10000"

local uiNotice    = ""
local CACHED_PATH = nil

-- ============================================================================
-- 1. ITEM IDs & SAFE HELPERS
-- ============================================================================
local ITEM = {
    PUNCH     = 18,
    GEMS      = 112,
    MAGNI     = 1252,
    DCS       = 6840,
    HARVESTER = 1830,
    SORROWS   = 1966,
    FUEL_PACK = 1746,
}

local LOCK_OR_DOOR_IDS = {
    [6] = true, [12] = true, [30] = true, [60] = true, [202] = true, [204] = true,
    [206] = true, [224] = true, [226] = true, [242] = true, [544] = true, [546] = true,
    [1796] = true, [2810] = true, [4428] = true, [4802] = true, [4994] = true, [7188] = true,
}

local function trimStr(s)
    return tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function cleanWorldName(s)
    return trimStr(s):gsub("[^%w_]", ""):upper()
end

local function normalizeHarvestPair(itemID)
    local id = tonumber(itemID) or 4584
    if id <= 0 then id = 4584 end
    if id % 2 == 1 then return id - 1, id end
    return id, id + 1
end

local function addLog(msg)
    local clean = tostring(msg or ""):gsub("`[0-9a-zA-Z!]", "")
    local ts = ""
    if os and os.date then
        local okD, d = pcall(os.date, "[%H:%M:%S] ")
        if okD and d then ts = d end
    end
    local entry = ts .. "[HARVEST] " .. clean
    table.insert(HV.STATE.logs, 1, entry)
    if #HV.STATE.logs > 60 then table.remove(HV.STATE.logs) end
    if HUB_REF and HUB_REF.addLog then HUB_REF.addLog(entry) end
end

local function safeSleep(ms)
    local d = tonumber(ms) or 100
    if Sleep then pcall(Sleep, d)
    elseif sleep then pcall(sleep, d) end
end

local function runAsync(fn)
    if runCoroutine then pcall(runCoroutine, fn)
    else coroutine.resume(coroutine.create(fn)) end
end

-- ============================================================================
-- 2. PERSISTENCE (SAVE / LOAD KONFIGURASI & WORLD LISTS)
-- ============================================================================
local function isSystemWindows()
    if package and package.config and package.config:sub(1, 1) == "\\" then return true end
    if os and type(os.getenv) == "function" then
        local ok, env = pcall(os.getenv, "OS")
        if ok and env and tostring(env):lower():find("windows", 1, true) then return true end
    end
    return false
end

local function splitColons(str)
    local parts = {}
    for seg in (tostring(str or "") .. ":"):gmatch("([^:]*):") do
        table.insert(parts, trimStr(seg))
    end
    if #parts > 0 and parts[#parts] == "" then
        table.remove(parts)
    end
    return parts
end

local function getStorageCandidates()
    local fn = "boren_hub_harvest_data.txt"
    if isSystemWindows() then
        return { fn }
    end
    return {
        "/storage/emulated/0/Download/" .. fn,
        "/sdcard/Download/" .. fn,
        "/storage/emulated/0/Android/media/launcher.powerkuy.growlauncher/ScriptLua/" .. fn,
        "/storage/emulated/0/Android/data/launcher.powerkuy.growlauncher/files/ScriptLua/" .. fn,
        fn,
    }
end

local function readStorageContent()
    local candidates = getStorageCandidates()
    -- 1. Baca via readFile native GrowLauncher jika tersedia
    if readFile then
        for _, path in ipairs(candidates) do
            local ok, txt = pcall(readFile, path)
            if ok and type(txt) == "string" and (txt:find("ROW=", 1, true) or #txt > 10) then
                return txt
            end
        end
    end
    -- 2. Baca via io.open
    if io and io.open then
        for _, path in ipairs(candidates) do
            local ok, f = pcall(io.open, path, "r")
            if ok and f then
                local txt = nil
                pcall(function() txt = f:read("*a"); f:close() end)
                if txt and type(txt) == "string" and (txt:find("ROW=", 1, true) or #txt > 10) then
                    return txt
                end
            end
        end
    end
    -- 3. Fallback: baca file apa pun yang berhasil terbuka dan tidak kosong
    if io and io.open then
        for _, path in ipairs(candidates) do
            local ok, f = pcall(io.open, path, "r")
            if ok and f then
                local txt = nil
                pcall(function() txt = f:read("*a"); f:close() end)
                if txt and type(txt) == "string" and txt ~= "" then
                    return txt
                end
            end
        end
    end
    return nil
end

local function writeStorageContent(content)
    local candidates = getStorageCandidates()
    local wroteAny = false

    -- 1. Tulis via native writeFile jika tersedia di engine
    if writeFile then
        for _, path in ipairs(candidates) do
            local ok = pcall(writeFile, path, content)
            if ok then wroteAny = true end
        end
    end
    if writeToLocal then
        pcall(writeToLocal, "boren_hub_harvest_data.txt", content)
        wroteAny = true
    end

    -- 2. Tulis via io.open ke seluruh direktori yang dapat diakses (Download HP, media, local)
    if io and io.open then
        for _, path in ipairs(candidates) do
            local ok, f = pcall(io.open, path, "w")
            if ok and f then
                pcall(function()
                    f:write(content .. "\n")
                    f:close()
                end)
                wroteAny = true
            end
        end
    end
    return wroteAny
end

local function getDataPath()
    local candidates = getStorageCandidates()
    for _, path in ipairs(candidates) do
        local ok, f = pcall(io.open, path, "r")
        if ok and f then f:close(); return path end
    end
    for _, path in ipairs(candidates) do
        local ok, f = pcall(io.open, path, "a")
        if ok and f then f:close(); return path end
    end
    return "boren_hub_harvest_data.txt"
end

local function parseWorldDoor(raw)
    local s = trimStr(raw):gsub("|", ":")
    if s == "" or s:sub(1, 1) == "#" then return nil end
    local parts = splitColons(s)
    local w = cleanWorldName(parts[1] or "")
    if w == "" then return nil end
    local door = cleanWorldName(parts[2] or "")
    return { name = w, door = door }
end

local function parseWorldList(raw)
    local list = {}
    for tok in tostring(raw or ""):gmatch("[^,\r\n;]+") do
        local p = parseWorldDoor(tok)
        if p then table.insert(list, p) end
    end
    return list
end

local function parseFarmRow(raw)
    local s = trimStr(raw):gsub("|", ":")
    if s == "" or s:sub(1, 1) == "#" then return nil end
    local parts = splitColons(s)
    local w = cleanWorldName(parts[1] or "")
    if w == "" then return nil end
    local door = cleanWorldName(parts[2] or "")
    local iid = math.floor(tonumber(parts[3]) or tonumber(HV.CFG.default_item_id) or 4584)
    if iid <= 0 then iid = 4584 end
    return { name = w, door = door, item_id = iid, status = "Ready" }
end

local function parseSaveRow(raw)
    local s = trimStr(raw):gsub("|", ":")
    if s == "" or s:sub(1, 1) == "#" then return nil end
    local parts = splitColons(s)
    local w = cleanWorldName(parts[1] or "")
    if w == "" then return nil end
    local door = cleanWorldName(parts[2] or "")
    local stype = (parts[3] or "ALL"):upper()
    if stype ~= "BLOCK" and stype ~= "SEED" and stype ~= "ALL" then
        local n = tonumber(stype)
        if n then
            local lim = math.floor(n)
            return { name = w, door = door, save_type = "ALL", limit = lim, count = 0, status = "Ready" }
        end
        stype = "ALL"
    end
    local lim = tonumber(parts[4]) or tonumber(HV.CFG.default_save_limit) or 20000
    local cur = tonumber(parts[5]) or 0
    return { name = w, door = door, save_type = stype, limit = math.max(0, math.floor(lim)), count = cur, status = "Ready" }
end

local function parseEventRow(raw)
    local s = trimStr(raw):gsub("|", ":")
    if s == "" or s:sub(1, 1) == "#" then return nil end
    local parts = splitColons(s)
    local w = cleanWorldName(parts[1] or "")
    if w == "" then return nil end
    local door = cleanWorldName(parts[2] or "")
    local lim = tonumber(parts[3]) or tonumber(HV.CFG.default_ev_limit) or 10000
    local cur = tonumber(parts[4]) or 0
    return { name = w, door = door, limit = math.max(0, math.floor(lim)), count = cur, status = "Ready" }
end

local function parseEventIDs()
    local map, list = {}, {}
    for tok in tostring(HV.CFG.event_ids_raw or ""):gmatch("[^,%s;|]+") do
        local id = math.floor(tonumber(tok) or 0)
        if id > 0 and not map[id] then map[id] = true; table.insert(list, id) end
    end
    return list, map
end

local function parseEquipIDs(raw)
    local list = {}
    for tok in tostring(raw or ""):gmatch("[^,%s;|]+") do
        local id = math.floor(tonumber(tok) or 0)
        if id > 0 then table.insert(list, id) end
    end
    return list
end

function HV.saveData()
    local c = HV.CFG
    local lines = {
        "DEFID="    .. tostring(c.default_item_id),
        "DROPTH="   .. tostring(c.drop_threshold or 200),
        "SAVELIM="  .. tostring(c.default_save_limit or 20000),
        "EVLIM="    .. tostring(c.default_ev_limit or 10000),
        "IGEMS="    .. (c.ignore_gems and "1" or "0"),
        "MODE="     .. tostring(c.harvest_mode),
        "HDELAY="   .. tostring(c.harvest_delay),
        "SDELAY="   .. tostring(c.step_delay),
        "MODFLY="   .. (c.use_modfly and "1" or "0"),
        "LOOP="     .. (c.loop_enabled and "1" or "0"),
        "ACOL="     .. (c.auto_collect and "1" or "0"),
        "EVIDS="    .. tostring(c.event_ids_raw or ""),
        "EVTH="     .. tostring(c.event_threshold),
        "GEARW="    .. tostring(c.gear_world or ""),
        "AMAGFUEL=" .. (c.auto_magni_fuel and "1" or "0"),
        "USEDCS="   .. (c.use_dcs_harvester and "1" or "0"),
        "GEAREQUIP=".. tostring(c.gear_equip_ids or ""),
        "FUELAMT="  .. tostring(c.fuel_target_amt),
        "STPFUEL="  .. (c.stop_if_no_fuel and "1" or "0"),
        "FLOAT="    .. (c.take_floating and "1" or "0"),
        "TAKEBLOCK=".. (c.take_block ~= false and "1" or "0"),
        "TAKESEED=" .. (c.take_seed ~= false and "1" or "0"),
    }
    for _, r in ipairs(HV.STATE.rows) do
        table.insert(lines, string.format("ROW=%s:%s:%d|%s", r.name, r.door or "", r.item_id or c.default_item_id, r.status or "Ready"))
    end
    for _, r in ipairs(HV.STATE.save_rows) do
        table.insert(lines, string.format("SAVEROW=%s:%s:%s:%d:%d|%s", r.name, r.door or "", r.save_type or "ALL", r.limit or 20000, r.count or 0, r.status or "Ready"))
    end
    for _, r in ipairs(HV.STATE.event_rows) do
        table.insert(lines, string.format("EVROW=%s:%s:%d:%d|%s", r.name, r.door or "", r.limit or 10000, r.count or 0, r.status or "Ready"))
    end

    local textContent = table.concat(lines, "\n")
    writeStorageContent(textContent)
end

function HV.loadData()
    local txt = readStorageContent()
    if not txt or txt == "" then return end
    local c = HV.CFG

    local loadedRows, loadedSaveRows, loadedEventRows = {}, {}, {}
    local legacySaveStr, legacyEventStr = "", ""

    for line in txt:gmatch("[^\r\n]+") do
        local k, v = line:match("^([A-Z]+)=(.*)$")
        if k == "DEFID" then c.default_item_id = tonumber(v) or 4584
        elseif k == "DROPTH" then c.drop_threshold = tonumber(v) or 200
        elseif k == "SAVELIM" then c.default_save_limit = tonumber(v) or 20000
        elseif k == "EVLIM" then c.default_ev_limit = tonumber(v) or 10000
        elseif k == "IGEMS" then c.ignore_gems = (v ~= "0")
        elseif k == "MODE" and (v == "3zigzag" or v == "1by1") then c.harvest_mode = v
        elseif k == "HDELAY" then c.harvest_delay = tonumber(v) or 180
        elseif k == "SDELAY" then c.step_delay = tonumber(v) or 110
        elseif k == "MODFLY" then c.use_modfly = (v ~= "0")
        elseif k == "LOOP" then c.loop_enabled = (v == "1")
        elseif k == "ACOL" then c.auto_collect = (v ~= "0")
        elseif k == "EVIDS" then c.event_ids_raw = trimStr(v)
        elseif k == "EVTH" then c.event_threshold = tonumber(v) or 150
        elseif k == "GEARW" then c.gear_world = trimStr(v)
        elseif k == "AMAGFUEL" then c.auto_magni_fuel = (v == "1")
        elseif k == "USEDCS" then c.use_dcs_harvester = (v == "1")
        elseif k == "GEAREQUIP" then c.gear_equip_ids = trimStr(v)
        elseif k == "FUELAMT" then c.fuel_target_amt = tonumber(v) or 100
        elseif k == "STPFUEL" then c.stop_if_no_fuel = (v ~= "0")
        elseif k == "FLOAT" then c.take_floating = (v ~= "0")
        elseif k == "TAKEBLOCK" then c.take_block = (v ~= "0")
        elseif k == "TAKESEED"  then c.take_seed  = (v ~= "0")
        elseif k == "MAGNI" or k == "FUEL" then if v == "1" then c.auto_magni_fuel = true end
        elseif k == "SAVEW" then legacySaveStr = trimStr(v)
        elseif k == "EVW" then legacyEventStr = trimStr(v)
        elseif k == "ROW" then
            local wd, st = v:match("^(.-)|(.*)$")
            local p = parseFarmRow(wd or v)
            if p then p.status = (st and st ~= "") and st or "Ready"; table.insert(loadedRows, p) end
        elseif k == "SAVEROW" then
            local wd, st = v:match("^(.-)|(.*)$")
            local p = parseSaveRow(wd or v)
            if p then p.status = (st and st ~= "") and st or "Ready"; table.insert(loadedSaveRows, p) end
        elseif k == "EVROW" then
            local wd, st = v:match("^(.-)|(.*)$")
            local p = parseEventRow(wd or v)
            if p then p.status = (st and st ~= "") and st or "Ready"; table.insert(loadedEventRows, p) end
        end
    end

    -- Migrasi format legacy ke list tables bila sebelumnya berupa string
    if #loadedSaveRows == 0 and legacySaveStr ~= "" then
        for _, sw in ipairs(parseWorldList(legacySaveStr)) do
            table.insert(loadedSaveRows, { name = sw.name, door = sw.door or "", save_type = "ALL", limit = c.default_save_limit, count = 0, status = "Ready" })
        end
    end
    if #loadedEventRows == 0 and legacyEventStr ~= "" then
        for _, ew in ipairs(parseWorldList(legacyEventStr)) do
            table.insert(loadedEventRows, { name = ew.name, door = ew.door or "", limit = c.default_ev_limit, count = 0, status = "Ready" })
        end
    end

    -- Update state hanya jika hasil load berisi data atau memory kosong
    if #loadedRows > 0 or #HV.STATE.rows == 0 then
        HV.STATE.rows = loadedRows
    end
    if #loadedSaveRows > 0 or #HV.STATE.save_rows == 0 then
        HV.STATE.save_rows = loadedSaveRows
    end
    if #loadedEventRows > 0 or #HV.STATE.event_rows == 0 then
        HV.STATE.event_rows = loadedEventRows
    end

    addFarmItemBuf   = tostring(c.default_item_id)
    addSaveLimitBuf  = tostring(c.default_save_limit)
    addEventLimitBuf = tostring(c.default_ev_limit)
end

-- ============================================================================
-- 3. GAME API, CONN GUARD, MOVEMENT & OBJECT HELPERS
-- ============================================================================
local function getLocalSafe()
    if not getLocal then return nil end
    local ok, p = pcall(getLocal)
    return (ok and p) and p or nil
end

local function getPlayerPos()
    local p = getLocalSafe()
    if not p then return 0, 0 end
    local px = p.posX or (p.pos and p.pos.x) or 0
    local py = p.posY or (p.pos and p.pos.y) or 0
    return math.floor((px + 10) / 32), math.floor((py + 10) / 32)
end

local function getCurrentWorldSafe()
    local fns = { getCurrentWorldName, GetWorldName, getWorld, getCurrentWorld, GetWorld }
    for _, fn in ipairs(fns) do
        if type(fn) == "function" then
            local ok, res = pcall(fn)
            if ok and res ~= nil then
                if type(res) == "string" then
                    local nm = cleanWorldName(res)
                    if nm ~= "" then return nm end
                elseif type(res) == "table" or type(res) == "userdata" then
                    local okN, nm = pcall(function() return res.name or res.worldName end)
                    if okN and type(nm) == "string" then
                        local c = cleanWorldName(nm)
                        if c ~= "" then return c end
                    end
                end
            end
        end
    end
    return "EXIT"
end

local function getInvCount(itemID)
    if not itemID or itemID <= 0 then return 0 end
    local total = 0
    if getInventory then
        local ok, inv = pcall(getInventory)
        if ok and type(inv) == "table" then
            for _, it in ipairs(inv) do
                local id = it.id or it.itemid or it.itemID
                local c  = it.count or it.amount or it.itemCount or 0
                if id and tonumber(id) == itemID then total = total + (tonumber(c) or 0) end
            end
            return total
        end
    end
    if findItem then
        local ok, c = pcall(findItem, itemID)
        if ok and tonumber(c) then return math.floor(tonumber(c)) end
    end
    return 0
end

local function setCollectCheats(enable)
    local v = enable == true
    if cheat and cheat.collect then pcall(cheat.collect, v) end
    if setCheat then pcall(setCheat, "collect", v) end
    if autoCollect then pcall(autoCollect, v) end
    if bot then
        pcall(function()
            if bot.auto_collect ~= nil then bot.auto_collect = v end
            if bot.collect ~= nil then bot.collect = v end
            if bot.anti_collect ~= nil then bot.anti_collect = not v end
        end)
    end
    if editToggle then
        pcall(editToggle, "Auto Collect", v)
        pcall(editToggle, "Anti Collect", not v)
    end
end

local function setConnWarping(isWarping)
    if HUB_REF and HUB_REF.conn and HUB_REF.conn.STATE then
        HUB_REF.conn.STATE.warping = (isWarping == true)
        if isWarping and HUB_REF.conn.touchActivity then pcall(HUB_REF.conn.touchActivity) end
    end
end

local function getTileSafe(x, y)
    if not getTile and not getTiles then return nil end
    if getTile then
        local ok, t = pcall(getTile, x, y)
        if ok and t then return t end
    end
    if getTiles then
        local ok, tiles = pcall(getTiles)
        if ok and type(tiles) == "table" then
            local idx = (y * 100) + x + 1
            if tiles[idx] then return tiles[idx] end
        end
    end
    return nil
end

local function forEachWorldObject(callback)
    local getFn = getObjectList or getObjects or getWorldObjects
    if not getFn then return end
    local ok, objs = pcall(getFn)
    if not ok or type(objs) ~= "table" then return end
    local container = objs
    pcall(function()
        if type(objs) == "table" and objs.objects then container = objs.objects end
    end)

    for _, o in pairs(container) do
        if type(o) == "table" or type(o) == "userdata" then
            local itemID = tonumber(o.itemid or o.itemId or o.itemID or o.item_id)
            local objUID = tonumber(o.id or o.oid or o.uid or o.objID)
            local amt    = tonumber(o.count or o.amount or 1) or 1
            local ox     = (o.pos and tonumber(o.pos.x)) or tonumber(o.posX or o.x) or 0
            local oy     = (o.pos and tonumber(o.pos.y)) or tonumber(o.posY or o.y) or 0
            if itemID and objUID then
                callback(itemID, objUID, amt, ox, oy)
            end
        end
    end
end

local function countDroppedObjectsInWorld(allowedSet)
    local total = 0
    forEachWorldObject(function(oid, _, amt)
        if (not allowedSet) or allowedSet[oid] then total = total + amt end
    end)
    return total
end

local function isTileBlocked(x, y)
    local t = getTileSafe(x, y)
    if not t then return true end
    local fg = tonumber(t.fg) or 0
    if fg > 0 and LOCK_OR_DOOR_IDS[fg] then return true end
    return false
end

local function moveSafeTo(tx, ty, exact)
    if not HV.STATE.running then return false end
    tx = math.max(0, math.min(99, math.floor(tx or 0)))
    ty = math.max(0, math.min(53, math.floor(ty or 0)))

    local curPx, curPy = getPlayerPos()
    if exact then
        if curPx == tx and curPy == ty then return true end
    else
        if curPx and curPy and math.abs(curPx - tx) <= 1 and math.abs(curPy - ty) <= 1 then
            return true
        end
    end

    local sx, sy = tx, ty
    if not exact then
        local t = getTileSafe(tx, ty)
        if t and t.collidable then
            local tUp = getTileSafe(tx, ty - 1)
            if tUp and not tUp.collidable then sx, sy = tx, ty - 1 end
        end
    end

    local pFn = FindPath or findPath
    if not pFn then return false end
    if HV.CFG.use_modfly and editToggle then
        pcall(editToggle, "ModFly", true)
        pcall(editToggle, "Anti Lava", true)
        pcall(editToggle, "No Lava", true)
    end

    local startPx, startPy = getPlayerPos()
    local totalDist = math.max(math.abs((startPx or 0) - sx), math.abs((startPy or 0) - sy))

    if totalDist <= 3 then
        pcall(pFn, sx, sy)
        local maxWait = math.max(160, (tonumber(HV.CFG.step_delay) or 110) * 3)
        local waited = 0
        while waited < maxWait and HV.STATE.running do
            local px, py = getPlayerPos()
            if exact then
                if px == sx and py == sy then
                    safeSleep(HV.CFG.step_delay or 40)
                    return true
                end
            else
                if px and py and math.abs(px - sx) <= 1 and math.abs(py - sy) <= 1 then
                    safeSleep(HV.CFG.step_delay or 40)
                    return true
                end
            end
            safeSleep(25)
            waited = waited + 25
        end
        local fx, fy = getPlayerPos()
        if exact then
            return (fx == sx and fy == sy)
        else
            return (fx and fy and math.abs(fx - sx) <= 1 and math.abs(fy - sy) <= 1)
        end
    end

    pcall(pFn, sx, sy)
    local maxWaitFar = math.max(2500, math.min(15000, totalDist * 180))
    local waitedFar = 0
    local lastPx, lastPy = startPx, startPy
    local stuckTicks = 0

    while waitedFar < maxWaitFar and HV.STATE.running do
        safeSleep(60)
        waitedFar = waitedFar + 60
        local nx, ny = getPlayerPos()
        if nx and ny then
            if exact then
                if nx == sx and ny == sy then
                    safeSleep(HV.CFG.step_delay or 50)
                    return true
                end
            else
                if math.abs(nx - sx) <= 1 and math.abs(ny - sy) <= 1 then
                    safeSleep(HV.CFG.step_delay or 50)
                    return true
                end
            end
            if nx == lastPx and ny == lastPy then
                stuckTicks = stuckTicks + 1
                if stuckTicks >= 10 then
                    pcall(pFn, sx, sy)
                    stuckTicks = 0
                end
            else
                stuckTicks = 0
                lastPx, lastPy = nx, ny
            end
        end
    end
    local fx, fy = getPlayerPos()
    if exact then
        return (fx == sx and fy == sy)
    else
        return (fx and fy and math.abs(fx - sx) <= 1 and math.abs(fy - sy) <= 1)
    end
end

local function warpToWorldInner(wName, doorID)
    doorID = doorID or ""
    if wName == "" then return false end
    unreachableMap = {}
    if getCurrentWorldSafe() == wName and doorID == "" then return true end
    if HUB_REF and HUB_REF.conn and HUB_REF.conn.isPlayerOnline and (not HUB_REF.conn.isPlayerOnline()) and (not HUB_REF.conn.isReconnecting()) then
        local okOn = HUB_REF.conn.ensureOnline({ world = "", isRunning = function() HV.handleSendPacket = onSendPacketHook
return HV.STATE.running end })
        if not okOn then return false end
    end
    local joinStr = (doorID ~= "") and (wName .. "|" .. doorID) or wName
    for _ = 1, 3 do
        if not HV.STATE.running then return false end
        if sendPacket then pcall(sendPacket, 3, "action|join_request\nname|" .. joinStr .. "\ninvitedWorld|0\n")
        elseif growtopia and growtopia.warpTo then pcall(growtopia.warpTo, joinStr) end
        local w, lim = 0, math.max(4000, tonumber(HV.CFG.warp_delay) or 4500)
        while w < lim and HV.STATE.running do
            safeSleep(250); w = w + 250
            if getCurrentWorldSafe() == wName then safeSleep(600); return true end
        end
    end
    return getCurrentWorldSafe() == wName
end

local function warpToWorld(wName, doorID)
    setConnWarping(true)
    local ok = warpToWorldInner(wName, doorID)
    setConnWarping(false)
    return ok
end

local function ensureHVOnline(row, resumeCollect)
    local conn = HUB_REF and HUB_REF.conn
    if not conn or not conn.ensureOnline then return true end
    local tw = row and row.name or ""
    local td = row and row.door or ""
    if not conn.needsReconnect(tw) then return true end
    HV.STATE.status_text = "RECONNECTING..."
    if row then row.status = "Reconnecting..." end
    local okOn = conn.ensureOnline({
        world     = tw,
        door      = td,
        isRunning = function() return HV.STATE.running end,
        onResume  = function() setCollectCheats(resumeCollect == true) end,
        warpFn    = function(w, d) return warpToWorld(w, d) end,
    })
    return okOn == true
end

local function punchTile(tx, ty)
    if not sendPacketRaw then return false end
    if HUB_REF and HUB_REF.conn and HUB_REF.conn.STATE and HUB_REF.conn.STATE.reconnecting then return false end
    local p = getLocalSafe()
    local px = (p and (p.posX or (p.pos and p.pos.x))) or (tx * 32)
    local py = (p and (p.posY or (p.pos and p.pos.y))) or (ty * 32)
    return pcall(sendPacketRaw, false, {
        type = 3, value = ITEM.PUNCH, px = tx, py = ty, x = px, y = py,
        state = (px > tx * 32) and 48 or 32,
    })
end

local function collectNearbyAllowed(allowedSet, radiusTiles)
    if not HV.CFG.auto_collect then return end
    local px, py = getPlayerPos()
    local rad = radiusTiles or (tonumber(HV.CFG.collect_range) or 4)
    forEachWorldObject(function(oid, uid, _, ox, oy)
        if HV.CFG.ignore_gems and oid == ITEM.GEMS then return end
        if (not allowedSet) or allowedSet[oid] then
            local otx = math.floor((ox + 10) / 32)
            local oty = math.floor((oy + 10) / 32)
            if math.abs(otx - px) <= rad and math.abs(oty - py) <= rad then
                if sendPacketRaw then
                    pcall(sendPacketRaw, false, { type = 11, value = uid, x = ox, y = oy })
                end
                if collectObject then pcall(collectObject, uid)
                elseif CollectObject then pcall(CollectObject, uid) end
            end
        end
    end)
end

-- ============================================================================
-- 4. DROP ENGINE (RAPI, SKIP LOCK/DOOR, PINDAH TILE & CEK LIMIT)
-- ============================================================================
local function parseDropDialogPacket(dlgText, fallbackID, dropAmt)
    local embedLines = {}
    local dName = dlgText:match("end_dialog|([^|\r\n]+)") or "drop_item"
    for k, v in dlgText:gmatch("embed_data|([^|\r\n]+)|([^\r\n|]*)") do
        table.insert(embedLines, k .. "|" .. v)
    end
    local countField = dlgText:match("add_text_input|([^|\r\n]+)|") or "count"
    local out = { "action|dialog_return", "dialog_name|" .. dName }
    for _, l in ipairs(embedLines) do table.insert(out, l) end
    if not dlgText:find("itemID|", 1, true) then
        table.insert(out, "itemID|" .. tostring(fallbackID) .. "|")
    end
    table.insert(out, countField .. "|" .. tostring(dropAmt))
    return table.concat(out, "\n") .. "\n"
end

local function onVariantHook(var)
    if not HV.STATE.running or HV.STATE.pending_drop_id <= 0 then return end
    if var and var[0] == "OnDialogRequest" and type(var[1]) == "string" then
        local text = var[1]
        if text:find("drop", 1, true) or text:find("Drop", 1, true) then
            local pkt = parseDropDialogPacket(text, HV.STATE.pending_drop_id, HV.STATE.pending_drop_amt)
            if sendPacket then
                pcall(sendPacket, 2, pkt)
                HV.STATE.drop_confirmed = true
            end
        end
    end
end

local function onSendPacketRawHook(raw)
    if not HV.STATE.running then return end
    -- Blokir packet pickup (11) selama bot sedang drop agar tidak mengambil kembali item yang di-drop
    if (HV.STATE.is_dropping or HV.STATE.anti_take) and raw and raw.type == 11 then
        return true
    end
    if raw and raw.type == 10 and raw.value then
        if raw.value == ITEM.SORROWS or raw.value == ITEM.HARVESTER then
            if not HV.STATE.need_fuel then addLog("`2[Harvester] Berhasil equip Harvester!") end
        end
    end
    if HV.CFG.ignore_gems and raw and raw.type == 11 and raw.value then
        local targetUID = raw.value
        local isGems = false
        forEachWorldObject(function(oid, uid)
            if uid == targetUID and oid == ITEM.GEMS then isGems = true end
        end)
        if isGems then return true end
    end
end

-- ============================================================================
-- NATIVE CLIENT DIALOG & KEYBOARD INPUT BRIDGE
-- ============================================================================
local activeNativeDialogs = {}

local function sanitizeDialogVal(s)
    return tostring(s or ""):gsub("[\r\n|]+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end

local function showClientDialog(dText)
    if not dText or dText == "" then return false end
    if growtopia and type(growtopia.sendDialog) == "function" then
        local ok = pcall(growtopia.sendDialog, dText)
        if ok then return true end
    end
    if sendVariant then
        local ok0 = pcall(sendVariant, { v0 = "OnDialogRequest", v1 = dText })
        if ok0 then return true end
        local ok1 = pcall(sendVariant, { v1 = "OnDialogRequest", v2 = dText })
        if ok1 then return true end
        local okNum = pcall(sendVariant, { [0] = "OnDialogRequest", [1] = dText })
        if okNum then return true end
    end
    if sendVariantList then
        local okList = pcall(sendVariantList, { [0] = "OnDialogRequest", [1] = dText })
        if okList then return true end
    end
    if sendDialog then
        pcall(sendDialog, dText)
        return true
    end
    return false
end

local function openNativeInputDialog(dialogId, title, fields, submitLabel, onSubmit)
    activeNativeDialogs[dialogId] = onSubmit
    local lines = {
        "set_default_color|`o",
        "add_label_with_icon|big|`cBOREN HARVEST - " .. sanitizeDialogVal(title) .. "|left|3802|",
        "add_spacer|small|",
    }
    for _, f in ipairs(fields or {}) do
        local fid = tostring(f.id or "f")
        local flb = sanitizeDialogVal(f.label or fid)
        local fdv = sanitizeDialogVal(f.default or "")
        local fln = tonumber(f.maxLen) or 48
        lines[#lines + 1] = string.format("add_text_input|%s|%s:|%s|%d|", fid, flb, fdv, fln)
    end
    lines[#lines + 1] = "add_spacer|small|"
    lines[#lines + 1] = "add_smalltext|`7Ketik dengan keyboard HP Anda lalu tekan tombol di bawah.|"
    lines[#lines + 1] = "end_dialog|" .. dialogId .. "|Batal|" .. sanitizeDialogVal(submitLabel or "Masukkan ke Form") .. "|"
    local dText = table.concat(lines, "\n")
    showClientDialog(dText)
end

local function onSendPacketHook(p1, p2)
    local packet = (type(p2) == "string") and p2 or ((type(p1) == "string") and p1 or nil)
    if not packet then return false end
    if packet:find("action|dialog_return", 1, true) then
        local dlgName = packet:match("dialog_name|([^\r\n|]+)")
        if dlgName then
            local cb = activeNativeDialogs[dlgName] or (_G.__BOREN_ACTIVE_NATIVE_DIALOGS and _G.__BOREN_ACTIVE_NATIVE_DIALOGS[dlgName])
            if cb then
                activeNativeDialogs[dlgName] = nil
                if _G.__BOREN_ACTIVE_NATIVE_DIALOGS then _G.__BOREN_ACTIVE_NATIVE_DIALOGS[dlgName] = nil end
                local fields = {}
                for line in packet:gmatch("[^\r\n]+") do
                    local k, v = line:match("^([^|]+)|(.*)$")
                    if k and k ~= "" then
                        k = k:gsub("^%s+", ""):gsub("%s+$", "")
                        v = tostring(v or ""):gsub("|$", ""):gsub("^%s+", ""):gsub("%s+$", "")
                        fields[k] = v
                    end
                end
                local btn = tostring(fields.buttonClicked or ""):lower()
                if btn ~= "batal" and btn ~= "cancel" and btn ~= "close" then
                    pcall(cb, fields)
                end
                if HV and HV.STATE and HV.STATE._saved_ui_state ~= nil then
                    HV.STATE.show_ui = HV.STATE._saved_ui_state
                    HV.STATE._saved_ui_state = nil
                elseif HV and HV.STATE and HV.STATE.show_ui ~= nil then
                    HV.STATE.show_ui = true
                end
                return true
            end
        end
    end
    return false
end

-- Registrasi Global & Engine Hooks
if AddHook then
    pcall(AddHook, "OnSendPacketRaw", "boren_hv_raw_hook", onSendPacketRawHook)
    pcall(AddHook, "OnVariantList", "boren_hv_var_hook", onVariantHook)
    pcall(AddHook, "OnSendPacket", "boren_hv_send_hook", onSendPacketHook)
elseif addHook then
    pcall(addHook, onSendPacketRawHook, "onsendpacketraw")
    pcall(addHook, "onSendPacketRaw", "boren_hv_raw_hook", onSendPacketRawHook)
    pcall(addHook, "OnSendPacketRaw", "boren_hv_raw_hook", onSendPacketRawHook)
    pcall(addHook, onVariantHook, "onvariantlist")
    pcall(addHook, "onVariantList", "boren_hv_var_hook", onVariantHook)
    pcall(addHook, "OnVariantList", "boren_hv_var_hook", onVariantHook)
    pcall(addHook, onSendPacketHook, "onsendpacket")
    pcall(addHook, "onSendPacket", "boren_hv_send_hook", onSendPacketHook)
    pcall(addHook, "OnSendPacket", "boren_hv_send_hook", onSendPacketHook)
end
onSendPacketRaw = onSendPacketRawHook
OnSendPacketRaw = onSendPacketRawHook
onSendPacket = onSendPacketHook
OnSendPacket = onSendPacketHook
if applyHook then pcall(applyHook) end
if ApplyHook then pcall(ApplyHook) end

-- ============================================================================
-- 4. DROP ENGINE (DROP SEBELAH DOOR, DARI KANAN KE KIRI, ZIGZAG TINGKAT KE ATAS/BAWAH)
-- ============================================================================
local function countDroppedOnTile(tx, ty)
    local total = 0
    forEachWorldObject(function(oid, uid, amt, ox, oy)
        local otx = math.floor(((ox or 0) + 10) / 32)
        local oty = math.floor(((oy or 0) + 10) / 32)
        if otx == tx and oty == ty then
            total = total + (tonumber(amt) or 1)
        end
    end)
    return total
end

local function isTileCleanForDrop(tx, ty, doorX, doorY)
    if tx < 2 or tx > 97 or ty < 1 or ty > 53 then return false end
    if tx == doorX and ty == doorY then return false end
    if isTileBlocked(tx, ty) then return false end
    local t = getTileSafe(tx, ty)
    if t and t.collidable then return false end
    return true
end

local function isTileCleanForStand(tx, ty, doorX, doorY)
    if tx < 2 or tx > 98 or ty < 1 or ty > 53 then return false end
    if tx == doorX and ty == doorY then return false end
    if isTileBlocked(tx, ty) then return false end
    local t = getTileSafe(tx, ty)
    if t and t.collidable then return false end
    return true
end

local function faceLeft(standX, standY)
    if sendPacketRaw then
        pcall(sendPacketRaw, false, {
            type  = 0,
            pos   = { x = standX * 32, y = standY * 32 },
            x     = standX * 32,
            y     = standY * 32,
            state = 48 -- 48 = Flipped / Menghadap ke kiri
        })
    end
end

local function moveToStand(standX, standY)
    if not HV.STATE.running then return false end
    standX = math.max(2, math.min(98, math.floor(standX or 0)))
    standY = math.max(1, math.min(53, math.floor(standY or 0)))

    if editToggle then
        pcall(editToggle, "ModFly", true)
        pcall(editToggle, "Anti Lava", true)
        pcall(editToggle, "No Lava", true)
    end

    local curPx, curPy = getPlayerPos()
    if curPx == standX and curPy == standY then
        faceLeft(standX, standY)
        return true
    end

    local pFn = FindPath or findPath
    if pFn then
        pcall(pFn, standX, standY)
        local waited = 0
        while waited < 1800 and HV.STATE.running do
            safeSleep(50)
            waited = waited + 50
            local px, py = getPlayerPos()
            if px == standX and py == standY then
                faceLeft(standX, standY)
                safeSleep(40)
                return true
            end
        end
    end

    moveSafeTo(standX, standY, true)
    faceLeft(standX, standY)
    safeSleep(50)
    local fx, fy = getPlayerPos()
    return (fx == standX and fy == standY) or (fx and fy and math.abs(fx - standX) <= 1 and math.abs(fy - standY) <= 1)
end

local function executeDropBatch(itemID, batch)
    if not HV.STATE.running then return false, 0 end
    local cur = getInvCount(itemID)
    if cur <= 0 then return true, 0 end
    batch = math.min(batch, math.min(200, cur))

    HV.STATE.is_dropping = true
    HV.STATE.anti_take = true
    HV.STATE.drop_confirmed = false
    HV.STATE.pending_drop_id = itemID
    HV.STATE.pending_drop_amt = batch

    -- Matikan auto-collect & aktifkan anti-collect cheat
    setCollectCheats(false)
    safeSleep(50)

    -- Metode 1: Standard action|drop (memicu OnDialogRequest di server)
    if sendPacket then
        pcall(sendPacket, 2, "action|drop\n|itemID|" .. tostring(itemID))
        safeSleep(140)
    end

    -- Metode 2: C++ engine direct drop confirmation
    if growtopia and growtopia.confirmDropItem then
        pcall(growtopia.confirmDropItem, itemID, batch)
        safeSleep(140)
    end

    -- Metode 3: Standard packet drop_item / drop dialog return
    if sendPacket then
        pcall(sendPacket, 2, string.format("action|dialog_return\ndialog_name|drop_item\nitemID|%d|\ncount|%d\n", itemID, batch))
        safeSleep(100)
        pcall(sendPacket, 2, string.format("action|dialog_return\ndialog_name|drop\nitemID|%d|\ncount|%d\n", itemID, batch))
        safeSleep(100)
    end

    local waited = 0
    while waited < 850 and HV.STATE.running do
        safeSleep(50)
        waited = waited + 50
        if getInvCount(itemID) < cur or HV.STATE.drop_confirmed then
            break
        end
    end

    HV.STATE.pending_drop_id = 0
    HV.STATE.pending_drop_amt = 0
    HV.STATE.is_dropping = false
    HV.STATE.anti_take = false

    local after = getInvCount(itemID)
    if after < cur then
        local delta = cur - after
        return true, delta
    end
    return false, 0
end

local function dropOntoTileFromRight(dropX, dropY, itemID, maxCanDrop)
    local standX = dropX + 1
    local standY = dropY

    local existingOnTile = countDroppedOnTile(dropX, dropY)
    if existingOnTile >= 4000 then
        return false, 0, true
    end

    if not moveToStand(standX, standY) then
        return false, 0, false
    end
    faceLeft(standX, standY)

    local droppedOnTile = 0
    local failCount = 0

    while HV.STATE.running and failCount < 2 do
        local curInv = getInvCount(itemID)
        if curInv <= 0 then
            return true, droppedOnTile, false
        end

        local tileSpace = 4000 - (existingOnTile + droppedOnTile)
        if tileSpace <= 0 then
            return true, droppedOnTile, true
        end

        local batch = math.min(200, math.min(curInv, tileSpace))
        if maxCanDrop and maxCanDrop > 0 then
            local remainQuota = maxCanDrop - droppedOnTile
            if remainQuota <= 0 then
                return true, droppedOnTile, false
            end
            batch = math.min(batch, remainQuota)
        end

        HV.STATE.status_text = string.format("Drop %d ke (%d,%d)...", batch, dropX, dropY)
        faceLeft(standX, standY)
        local ok, delta = executeDropBatch(itemID, batch)
        if ok and delta > 0 then
            droppedOnTile = droppedOnTile + delta
            HV.STATE.total_dropped = HV.STATE.total_dropped + delta
            failCount = 0
            safeSleep(150)
            if (existingOnTile + droppedOnTile) >= 4000 then
                return true, droppedOnTile, true
            end
        else
            failCount = failCount + 1
            safeSleep(150)
        end
    end

    local tileFull = (failCount >= 2) or ((existingOnTile + droppedOnTile) >= 4000)
    return (droppedOnTile > 0), droppedOnTile, tileFull
end

local function dropItemAllInCurrentWorld(itemID, label, maxQuota)
    local cur = getInvCount(itemID)
    if cur <= 0 then return true, 0 end

    if editToggle then
        pcall(editToggle, "ModFly", true)
        pcall(editToggle, "Anti Lava", true)
        pcall(editToggle, "No Lava", true)
    end
    setCollectCheats(false)

    local px, py = getPlayerPos()
    local doorX, doorY = px or 2, py or 2
    for dy = -2, 2 do
        for dx = -2, 2 do
            local t = getTileSafe(px + dx, py + dy)
            if t and (tonumber(t.fg) == 6 or tonumber(t.fg) == 8) then
                doorX, doorY = px + dx, py + dy
                break
            end
        end
    end

    -- 1. Baris utama sejajar pintu (y = doorY)
    -- 2. Jika penuh naik satu tingkat lagi (doorY - 1, doorY - 2, ...)
    -- 3. Jika atas habis, ke bawahnya (doorY + 1, doorY + 2, ...)
    local candidateRows = { doorY }
    for y = doorY - 1, 1, -1 do
        table.insert(candidateRows, y)
    end
    for y = doorY + 1, 53 do
        table.insert(candidateRows, y)
    end

    local totalDropped = 0

    for _, rowY in ipairs(candidateRows) do
        if getInvCount(itemID) <= 0 or not HV.STATE.running then break end
        if maxQuota and maxQuota > 0 and totalDropped >= maxQuota then break end

        -- Sesuai gambar: Drop di sebelah door (area kosong) dari kanan tile target ke kiri
        local startX = math.max(2, doorX + 1)
        for dropX = startX, 97 do
            if getInvCount(itemID) <= 0 or not HV.STATE.running then break end
            if maxQuota and maxQuota > 0 and totalDropped >= maxQuota then break end

            local standX = dropX + 1
            if standX <= 98 and isTileCleanForDrop(dropX, rowY, doorX, doorY) and isTileCleanForStand(standX, rowY, doorX, doorY) then
                local quotaLeft = (maxQuota and maxQuota > 0) and (maxQuota - totalDropped) or nil
                local ok, droppedAmt, tileFull = dropOntoTileFromRight(dropX, rowY, itemID, quotaLeft)
                if droppedAmt > 0 then
                    totalDropped = totalDropped + droppedAmt
                end
            end
        end
    end

    HV.STATE.is_dropping = false
    HV.STATE.anti_take = false
    local remaining = getInvCount(itemID)
    return (remaining == 0), totalDropped
end

local function dropToSaveWorlds(blockID, seedID, returnFarm)
    local bCnt = getInvCount(blockID)
    local sCnt = getInvCount(seedID)
    if bCnt <= 0 and sCnt <= 0 then return true end

    local rows = HV.STATE.save_rows
    if #rows == 0 then
        addLog("`4[Save World] Daftar Save World kosong! Tambahkan di tab Save World.")
        return false
    end

    local itemsToDrop = {}
    if bCnt > 0 then table.insert(itemsToDrop, { id = blockID, name = "Block", isBlock = true }) end
    if sCnt > 0 then table.insert(itemsToDrop, { id = seedID, name = "Seed", isBlock = false }) end

    for _, itm in ipairs(itemsToDrop) do
        local curAmt = getInvCount(itm.id)
        while curAmt > 0 and HV.STATE.running do
            local targetRow = nil
            for _, r in ipairs(rows) do
                if r.status ~= "Full" and r.status ~= "Inaccessible" then
                    local t = (r.save_type or "ALL"):upper()
                    if itm.isBlock and (t == "ALL" or t == "BLOCK") then
                        targetRow = r; break
                    elseif (not itm.isBlock) and (t == "ALL" or t == "SEED") then
                        targetRow = r; break
                    end
                end
            end

            if not targetRow then
                addLog(string.format("`4[Save World] Semua world untuk %s sudah penuh / tidak tersedia!", itm.name))
                break
            end

            HV.STATE.status_text = "Drop " .. itm.name .. " -> " .. targetRow.name
            if warpToWorld(targetRow.name, targetRow.door) then
                setCollectCheats(false)
                safeSleep(350)

                local filterSet = {}
                local t = (targetRow.save_type or "ALL"):upper()
                if t == "BLOCK" then filterSet[blockID] = true
                elseif t == "SEED" then filterSet[seedID] = true
                else filterSet[blockID] = true; filterSet[seedID] = true end

                local lim = math.max(0, math.floor(tonumber(targetRow.limit) or 0))
                local curInWorld = countDroppedObjectsInWorld(filterSet)
                targetRow.count = curInWorld

                if lim > 0 and curInWorld >= lim then
                    addLog(string.format("`e[Save World] %s capai limit (%d/%d) -> lanjut next world!", targetRow.name, curInWorld, lim))
                    targetRow.status = "Full"
                    HV.saveData()
                else
                    local quotaLeft = (lim > 0) and math.max(0, lim - curInWorld) or nil
                    local okD = dropItemAllInCurrentWorld(itm.id, itm.name, quotaLeft)
                    local afterInWorld = countDroppedObjectsInWorld(filterSet)
                    targetRow.count = afterInWorld
                    if lim > 0 and afterInWorld >= lim then
                        targetRow.status = "Full"
                    end
                    HV.saveData()
                    if not okD then
                        targetRow.status = "Full"
                        HV.saveData()
                    end
                end
            else
                addLog("`4[Save World] Gagal warp ke " .. targetRow.name)
                targetRow.status = "Inaccessible"
                HV.saveData()
            end
            curAmt = getInvCount(itm.id)
        end
    end

    if returnFarm and HV.STATE.running then
        warpToWorld(returnFarm.name, returnFarm.door)
        setCollectCheats(true)
    end
    return (getInvCount(blockID) == 0 and getInvCount(seedID) == 0)
end

local function dropToEventWorlds(returnFarm)
    local evList, evMap = parseEventIDs()
    local toDrop = {}
    for _, id in ipairs(evList) do
        if getInvCount(id) > 0 then table.insert(toDrop, id) end
    end
    if #toDrop == 0 then return true end

    local rows = HV.STATE.event_rows
    if #rows == 0 then
        addLog("`e[Event World] World Event belum diatur (opsional) — melewati drop event.")
        return true
    end

    for _, itmID in ipairs(toDrop) do
        local curAmt = getInvCount(itmID)
        while curAmt > 0 and HV.STATE.running do
            local targetRow = nil
            for _, r in ipairs(rows) do
                if r.status ~= "Full" and r.status ~= "Inaccessible" then
                    targetRow = r; break
                end
            end

            if not targetRow then
                addLog("`e[Event World] Semua World Event penuh / tidak tersedia — drop event dilewati.")
                return true
            end

            HV.STATE.status_text = "Drop Event -> " .. targetRow.name
            if warpToWorld(targetRow.name, targetRow.door) then
                setCollectCheats(false)
                safeSleep(350)

                local lim = math.max(0, math.floor(tonumber(targetRow.limit) or 0))
                local curInWorld = countDroppedObjectsInWorld(evMap)
                targetRow.count = curInWorld

                if lim > 0 and curInWorld >= lim then
                    addLog(string.format("`e[Event World] %s capai limit total (%d/%d) -> pindah world event!", targetRow.name, curInWorld, lim))
                    targetRow.status = "Full"
                    HV.saveData()
                else
                    local quotaLeft = (lim > 0) and math.max(0, lim - curInWorld) or nil
                    local okD = dropItemAllInCurrentWorld(itmID, "Item " .. itmID, quotaLeft)
                    local afterInWorld = countDroppedObjectsInWorld(evMap)
                    targetRow.count = afterInWorld
                    if lim > 0 and afterInWorld >= lim then
                        targetRow.status = "Full"
                    end
                    HV.saveData()
                    if not okD then
                        targetRow.status = "Full"
                        HV.saveData()
                    end
                end
            else
                addLog("`4[Event World] Gagal warp ke " .. targetRow.name)
                targetRow.status = "Inaccessible"
                HV.saveData()
            end
            curAmt = getInvCount(itmID)
        end
    end

    if returnFarm and HV.STATE.running then
        warpToWorld(returnFarm.name, returnFarm.door)
        setCollectCheats(true)
    end
    return true
end

-- ============================================================================
-- 5. GEAR WORLD (MAGNI + FUEL TERPADU & LIST ID EQUIP ALAT)
-- ============================================================================
local function equipItem(itemID)
    if not sendPacketRaw or getInvCount(itemID) <= 0 then return false end
    return pcall(sendPacketRaw, false, { type = 10, value = itemID })
end

local function ensureGearAndFuel(returnFarm)
    local c = HV.CFG
    local needed = {}

    -- 1. Magni & Fuel Pack dijadikan satu
    if c.auto_magni_fuel then
        if getInvCount(ITEM.MAGNI) <= 0 then
            table.insert(needed, { id = ITEM.MAGNI, amt = 1, equip = true, name = "Magnifying Glass" })
        end
        local fuelCount = getInvCount(ITEM.FUEL_PACK)
        if HV.STATE.need_fuel and fuelCount > 0 then
            equipItem(ITEM.FUEL_PACK)
            HV.STATE.need_fuel = false
            safeSleep(250)
            fuelCount = getInvCount(ITEM.FUEL_PACK)
        end
        local targetFuel = math.max(1, math.min(200, tonumber(c.fuel_target_amt) or 100))
        if fuelCount < targetFuel or HV.STATE.need_fuel then
            table.insert(needed, { id = ITEM.FUEL_PACK, amt = targetFuel, equip = false, name = "Fuel Pack" })
        end
    end

    -- 2. Daftar ID Alat untuk Di-equip (DCS, Harvester, dll.) HANYA jika toggle Gunakan DCS aktif!
    local equipIDs = c.use_dcs_harvester and parseEquipIDs(c.gear_equip_ids) or {}
    for _, eqID in ipairs(equipIDs) do
        if getInvCount(eqID) <= 0 then
            table.insert(needed, { id = eqID, amt = 1, equip = true, name = "Gear " .. tostring(eqID) })
        end
    end

    -- Jika semua perlengkapan sudah ada di tas
    if #needed == 0 then
        if c.auto_magni_fuel and getInvCount(ITEM.MAGNI) > 0 then equipItem(ITEM.MAGNI); safeSleep(100) end
        if c.use_dcs_harvester then
            for _, eqID in ipairs(equipIDs) do if getInvCount(eqID) > 0 then equipItem(eqID); safeSleep(100) end end
        end
        return true
    end

    local gw = parseWorldDoor(c.gear_world)
    if not gw or trimStr(c.gear_world or "") == "" then
        -- Gear World opsional! Equip perlengkapan yang ada di tas bila tersedia
        if c.auto_magni_fuel and getInvCount(ITEM.MAGNI) > 0 then equipItem(ITEM.MAGNI); safeSleep(100) end
        if getInvCount(ITEM.FUEL_PACK) > 0 and HV.STATE.need_fuel then equipItem(ITEM.FUEL_PACK); HV.STATE.need_fuel = false; safeSleep(100) end
        if c.use_dcs_harvester then
            for _, eqID in ipairs(equipIDs) do if getInvCount(eqID) > 0 then equipItem(eqID); safeSleep(100) end end
        end
        return true
    end

    HV.STATE.status_text = "Gear World: " .. gw.name
    addLog("[Gear] Ambil perlengkapan / fuel di " .. gw.name)
    if not warpToWorld(gw.name, gw.door) then
        addLog("`e[Gear] Gagal warp ke Gear World " .. gw.name .. " — melanjutkan harvest (Gear World opsional).")
        return true
    end

    setCollectCheats(true)
    safeSleep(450)
    for _, req in ipairs(needed) do
        if not HV.STATE.running then return false end
        forEachWorldObject(function(oid, uid, _, ox, oy)
            if not HV.STATE.running then return end
            if oid == req.id and getInvCount(req.id) < req.amt then
                if moveSafeTo(math.floor((ox + 10) / 32), math.floor((oy + 10) / 32)) then
                    if sendPacketRaw then pcall(sendPacketRaw, false, { type = 11, value = uid, x = ox, y = oy }) end
                    safeSleep(220)
                end
            end
        end)
        if req.equip and getInvCount(req.id) > 0 then
            equipItem(req.id); safeSleep(180)
            addLog("`2[Gear] Equip " .. req.name)
        elseif req.id == ITEM.FUEL_PACK and getInvCount(ITEM.FUEL_PACK) > 0 then
            addLog("`2[Gear] Fuel Pack terambil: " .. getInvCount(ITEM.FUEL_PACK))
            if HV.STATE.need_fuel then equipItem(ITEM.FUEL_PACK); HV.STATE.need_fuel = false; safeSleep(200) end
        end
    end

    if c.auto_magni_fuel and c.stop_if_no_fuel and getInvCount(ITEM.FUEL_PACK) <= 0 and (gw and trimStr(c.gear_world or "") ~= "") then
        addLog("`4[Fuel Guard] Stok Fuel Pack habis di tas & Gear World — bot berhenti aman!")
        HV.STATE.status_text = "No Fuel Pack"
        return false
    end

    if returnFarm and HV.STATE.running then
        warpToWorld(returnFarm.name, returnFarm.door)
        setCollectCheats(true)
    end
    return true
end

-- ============================================================================
-- 6. HARVEST ENGINE (3-ZIGZAG / 1BY1 + TAKE FLOATING + AUTO DROP)
-- ============================================================================
local function isTileTreeReady(t)
    if not t then return false end
    if t.readyharvest == true or t.readyharvest == 1 or t.readyharvest == "true" then return true end
    if t.ready_to_harvest == true or t.ready_to_harvest == 1 then return true end
    if t.canHarvest and type(t.canHarvest) == "function" then
        local okH, resH = pcall(t.canHarvest, t)
        if okH and resH == true then return true end
    end
    if tonumber(t.progress) and tonumber(t.progress) >= 1.0 then return true end
    if t.extra and type(t.extra) == "table" then
        if tonumber(t.extra.growth) == 0 and (tonumber(t.extra.fruitcount) or 0) > 0 then
            return true
        end
    end
    return false
end

local function isReadyTree(tx, ty, seedID, blockID)
    local t = getTileSafe(tx, ty)
    if not t then return false end
    local fg = tonumber(t.fg) or 0
    if fg <= 0 then return false end

    -- Cocokkan fg dengan seedID atau blockID bila disediakan
    local matchesID = false
    if seedID and seedID > 0 and fg == seedID then matchesID = true end
    if (not matchesID) and blockID and blockID > 0 and fg == blockID then matchesID = true end

    -- Jika ID diberikan dan tidak cocok dengan fg, bukan pohon target
    if (seedID and seedID > 0) and not matchesID then return false end

    return isTileTreeReady(t)
end

-- Validasi pukulan pohon: memastikan pohon benar-benar telah dipanen (hancur)
local function harvestTreeTile(tx, ty, seedID, blockID, hDelay)
    for attempt = 1, 4 do
        if not HV.STATE.running then return false end
        punchTile(tx, ty)
        safeSleep(hDelay)

        -- Validasi: cek apakah pohon di tile (tx, ty) sudah pecah/habis
        if not isReadyTree(tx, ty, seedID, blockID) then
            HV.STATE.total_harvested = HV.STATE.total_harvested + 1
            return true
        end
        safeSleep(50)
    end
    if not isReadyTree(tx, ty, seedID, blockID) then
        HV.STATE.total_harvested = HV.STATE.total_harvested + 1
        return true
    end
    return false
end

local function updateInvPreview(blockID, seedID, eventList)
    HV.STATE.inv_preview.block = getInvCount(blockID)
    HV.STATE.inv_preview.seed  = getInvCount(seedID)
    HV.STATE.inv_preview.fuel  = getInvCount(ITEM.FUEL_PACK)
    local evSum = 0
    for _, eid in ipairs(eventList or {}) do evSum = evSum + getInvCount(eid) end
    HV.STATE.inv_preview.ev = evSum
end

local function checkAndDropIfFull(row, blockID, seedID, eventList, forceDrop)
    updateInvPreview(blockID, seedID, eventList)
    local c = HV.CFG
    local th  = math.max(20, math.min(200, tonumber(c.drop_threshold) or 200))
    local eth = math.max(10, math.min(200, tonumber(c.event_threshold) or 150))

    -- 1. Cek Fuel Pack proaktif jika memakai harvester & fuel
    if (not forceDrop) and c.auto_magni_fuel and (HV.STATE.need_fuel or getInvCount(ITEM.FUEL_PACK) <= 0) then
        if not ensureGearAndFuel(row) then return false end
    end

    -- 2. Drop Item Event bila ada di tas
    local needEventDrop = false
    for _, eid in ipairs(eventList) do
        local cnt = getInvCount(eid)
        if (forceDrop and cnt > 0) or cnt >= eth then needEventDrop = true; break end
    end
    if needEventDrop and #HV.STATE.event_rows > 0 then
        if not dropToEventWorlds(forceDrop and nil or row) then return false end
    end

    -- 3. Drop Block & Seed
    local bCnt, sCnt = getInvCount(blockID), getInvCount(seedID)
    if (forceDrop and (bCnt > 0 or sCnt > 0)) or bCnt >= th or sCnt >= th then
        if not dropToSaveWorlds(blockID, seedID, forceDrop and nil or row) then return false end
    end

    updateInvPreview(blockID, seedID, eventList)
    return true
end

local function sweepFloatingObjects(row, blockID, seedID, allowedSet, eventList)
    if not HV.CFG.take_floating then return true end
    HV.STATE.status_text = row.name .. " Take Floating..."
    addLog("[Floating] Sapu sisa drop block/seed/event di " .. row.name)
    setCollectCheats(true)

    local pass = 0
    while pass < 6 and HV.STATE.running do
        pass = pass + 1
        if not ensureHVOnline(row, true) then return false end
        local targets = {}
        forEachWorldObject(function(oid, uid, _, ox, oy)
            if HV.CFG.ignore_gems and oid == ITEM.GEMS then return end
            if allowedSet[oid] then
                table.insert(targets, { oid = oid, uid = uid, ox = ox, oy = oy, tx = math.floor((ox + 10) / 32), ty = math.floor((oy + 10) / 32) })
            end
        end)
        if #targets == 0 then break end
        for _, obj in ipairs(targets) do
            if not HV.STATE.running then return false end
            if not ensureHVOnline(row, true) then return false end
            if not checkAndDropIfFull(row, blockID, seedID, eventList, false) then return false end
            if moveSafeTo(obj.tx, obj.ty) then
                if sendPacketRaw then pcall(sendPacketRaw, false, { type = 11, value = obj.uid, x = obj.ox, y = obj.oy }) end
                collectNearbyAllowed(allowedSet, 3)
                safeSleep(120)
            end
        end
    end
    return true
end

local function processFarmWorld(row)
    local blockID, seedID = normalizeHarvestPair(row.item_id or HV.CFG.default_item_id)
    if blockID <= 0 then row.status = "Invalid ID"; HV.saveData(); return false end

    local eventList, eventMap = parseEventIDs()
    local allowedSet = {}
    if HV.CFG.take_block ~= false then allowedSet[blockID] = true end
    if HV.CFG.take_seed ~= false then allowedSet[seedID] = true end
    for id in pairs(eventMap) do allowedSet[id] = true end

    if not ensureGearAndFuel(nil) then return false end

    row.status = "Warping..."
    HV.STATE.status_text = "Warp: " .. row.name
    if not warpToWorld(row.name, row.door) then
        row.status = "Inaccessible"; HV.saveData(); return false
    end
    setCollectCheats(true)
    safeSleep(500)

    -- Auto-Detect: Cek apakah ada pohon yang cocok di world. Bila 0, scan otomatis pohon matang di world!
    local initialReady = 0
    for testY = 1, 53 do
        for testX = 2, 97 do
            if isReadyTree(testX, testY, seedID, blockID) then
                initialReady = initialReady + 1
                if initialReady >= 1 then break end
            end
        end
        if initialReady >= 1 then break end
    end

    if initialReady == 0 then
        local detectedCounts = {}
        for scY = 1, 53 do
            for scX = 2, 97 do
                local t = getTileSafe(scX, scY)
                if t and isTileTreeReady(t) then
                    local fg = tonumber(t.fg) or 0
                    if fg > 0 then
                        detectedCounts[fg] = (detectedCounts[fg] or 0) + 1
                    end
                end
            end
        end

        local bestFg, bestCnt = nil, 0
        for fg, cnt in pairs(detectedCounts) do
            if cnt > bestCnt then bestFg = fg; bestCnt = cnt end
        end

        if bestFg and bestCnt > 0 then
            blockID, seedID = normalizeHarvestPair(bestFg)
            row.item_id = blockID
            if HV.CFG.take_block ~= false then allowedSet[blockID] = true end
            if HV.CFG.take_seed ~= false then allowedSet[seedID] = true end
            HV.saveData()
            addLog(string.format("`a[Auto-Detect] Menemukan %d pohon matang di %s -> ID Block: %d, Seed: %d", bestCnt, row.name, blockID, seedID))
        end
    end

    local hDelay = math.max(90, tonumber(HV.CFG.harvest_delay) or 180)
    local isZigzag = (HV.CFG.harvest_mode == "3zigzag")

    -- 1. Scan semua baris di world yang memiliki pohon matang, urutkan dari PALING ATAS (ty = 1..53)
    local treeRows = {}
    for testY = 1, 53 do
        local hasTree = false
        for testX = 2, 97 do
            if isReadyTree(testX, testY, seedID, blockID) then
                hasTree = true
                break
            end
        end
        if hasTree then
            table.insert(treeRows, testY)
        end
    end

    -- 2. Mulai panen dari baris PALING ATAS, dari posisi PALING KIRI
    local rowCount = 0
    for _, ty in ipairs(treeRows) do
        if not HV.STATE.running then return false end
        rowCount = rowCount + 1
        local l2r = (rowCount % 2 == 1) -- Baris pertama (paling atas) selalu l2r = true (KIRI ke KANAN)
        local startX = l2r and 2 or 97
        local endX   = l2r and 97 or 2
        local stepX  = l2r and 1 or -1

        local py = ty + 1 -- Lantai tempat pohon berpijak

        if not ensureHVOnline(row, true) then return false end
        if isZigzag then
            local x = startX
            while (l2r and x <= endX) or ((not l2r) and x >= endX) do
                if not HV.STATE.running then return false end
                if not ensureHVOnline(row, true) then return false end

                local t1 = isReadyTree(x, ty, seedID, blockID)
                local t2 = isReadyTree(x + stepX, ty, seedID, blockID)
                local t3 = isReadyTree(x + (stepX * 2), ty, seedID, blockID)

                if t1 or t2 or t3 then
                    if not checkAndDropIfFull(row, blockID, seedID, eventList, false) then return false end
                    local standY = py
                    local tFloor = getTileSafe(x, py)
                    if tFloor and tFloor.collidable then standY = ty end
                    moveSafeTo(x, standY)
                    collectNearbyAllowed(allowedSet, 4)

                    -- Validasi pukulan pohon matang
                    if t1 then harvestTreeTile(x, ty, seedID, blockID, hDelay) end
                    if t2 then harvestTreeTile(x + stepX, ty, seedID, blockID, hDelay) end
                    if t3 then harvestTreeTile(x + (stepX * 2), ty, seedID, blockID, hDelay) end

                    collectNearbyAllowed(allowedSet, 4)
                    x = x + (stepX * 3)
                else
                    x = x + stepX
                end
            end
        else
            for x = startX, endX, stepX do
                if not HV.STATE.running then return false end
                if not ensureHVOnline(row, true) then return false end
                if isReadyTree(x, ty, seedID, blockID) then
                    if not checkAndDropIfFull(row, blockID, seedID, eventList, false) then return false end
                    local standY = py
                    local tFloor = getTileSafe(x, py)
                    if tFloor and tFloor.collidable then standY = ty end
                    moveSafeTo(x, standY)
                    collectNearbyAllowed(allowedSet, 4)

                    -- Validasi pukulan pohon matang
                    harvestTreeTile(x, ty, seedID, blockID, hDelay)

                    collectNearbyAllowed(allowedSet, 4)
                end
            end
        end
    end

    -- Sapu sisa floating block / seed / event jika opsi take_floating aktif
    sweepFloatingObjects(row, blockID, seedID, allowedSet, eventList)

    -- Force drop semua hasil yang tersisa di tas sebelum pindah farm
    checkAndDropIfFull(row, blockID, seedID, eventList, true)

    row.status = "Done"
    HV.saveData()
    addLog(string.format("`2World %s SELESAI dipanen!", row.name))
    return true
end

local function harvestLoopRunner()
    HV.STATE.running = true
    HV.STATE.enabled = true
    addLog("`2Auto Harvest dimulai...")

    while HV.STATE.running do
        local allDone = true
        for i, row in ipairs(HV.STATE.rows) do
            if not HV.STATE.running then break end
            if row.status ~= "Done" and row.status ~= "Inaccessible" and row.status ~= "Invalid ID" then
                allDone = false
                HV.STATE.selected_idx = i
                local ok = processFarmWorld(row)
                if not ok and not HV.STATE.running then break end
                safeSleep(1000)
            end
        end

        if not HV.STATE.running then break end
        if allDone then
            if HV.CFG.loop_enabled and #HV.STATE.rows > 0 then
                addLog("`eSemua farm selesai, looping antrean diulang!")
                for _, r in ipairs(HV.STATE.rows) do
                    if r.status == "Done" then r.status = "Ready" end
                end
                HV.saveData()
                safeSleep(2000)
            else
                addLog("`2Semua antrean Farm Harvest telah selesai!")
                HV.STATE.status_text = "Done All"
                break
            end
        end
    end

    HV.STATE.running = false
    HV.STATE.enabled = false
    setCollectCheats(false)
    HV.STATE.status_text = "Idle"
    HV.saveData()
    addLog("`eAuto Harvest berhenti.")
end

function HV.start()
    if HV.STATE.running then return false end
    if #HV.STATE.rows == 0 then
        addLog("`4Daftar Farm kosong! Tambahkan world di tab Farm List.")
        return false
    end
    runAsync(harvestLoopRunner)
    return true
end

function HV.stop()
    if not HV.STATE.running then
        HV.STATE.enabled = false
        return false
    end
    HV.STATE.running = false
    HV.STATE.enabled = false
    setCollectCheats(false)
    HV.STATE.status_text = "Stopping..."
    addLog("Menghentikan bot...")
    return true
end

function HV.init(hub)
    HUB_REF = hub
    HV.loadData()
end

-- ============================================================================
-- 7. UI RENDERER (TERINTEGRASI DENGAN UI_KIT BOREN STORE HUB)
-- ============================================================================
local function uiKit()
    return HUB_REF and HUB_REF.ui_kit or nil
end

local function autoBtn(lbl)
    local ok, r = pcall(ImGui.Button, lbl)
    return ok and (r == true)
end

local function uiGap(px)
    local k = uiKit()
    if k and k.gap then k.gap(px); return end
    if ImGui and ImGui.Spacing then pcall(ImGui.Spacing) end
end

local function uiSection(title, skipTopSep)
    local k = uiKit()
    if k and k.section then k.section(title, skipTopSep); return end
    if not skipTopSep then ImGui.Separator() end
    if title and title ~= "" then ImGui.Text(title) end
end

local function uiSectionWithKetik(title, btnId, onKetikClick, skipTopSep)
    uiSection(title, skipTopSep)
end

local function uiOpenDialog(id, title, fields, submitLbl, onSubmit)
    activeNativeDialogs[id] = onSubmit
    _G.__BOREN_ACTIVE_NATIVE_DIALOGS = _G.__BOREN_ACTIVE_NATIVE_DIALOGS or {}
    _G.__BOREN_ACTIVE_NATIVE_DIALOGS[id] = onSubmit

    local k = uiKit()
    if k and k.openInputDialog then
        k.openInputDialog(id, title, fields, submitLbl, onSubmit)
        return
    end
    openNativeInputDialog(id, title, fields, submitLbl, onSubmit)
end

local function uiEnableBtn(isOn, id)
    local k = uiKit()
    if k and k.enableBtn then return k.enableBtn(isOn, id) end
    return autoBtn((isOn and "ON##" or "OFF##") .. tostring(id))
end

local function uiToggleBtn(isOn, id, onLbl, offLbl)
    local k = uiKit()
    if k and k.toggleBtn then return k.toggleBtn(isOn, id, onLbl, offLbl) end
    return autoBtn(" " .. (isOn and (onLbl or "ON") or (offLbl or "OFF")) .. " ##" .. tostring(id))
end

local function uiTabBtn(label, isActive)
    local k = uiKit()
    if k and k.tabBtn then return k.tabBtn(label, isActive) end
    return autoBtn(isActive and ("[ " .. label .. " ]") or label)
end

local function uiNote(msg)
    if not msg or msg == "" then return end
    local k = uiKit()
    if k and k.coloredText and k.getPal then
        k.coloredText(k.getPal().textPurple, "Info: " .. tostring(msg))
    else
        ImGui.Text("Info: " .. tostring(msg))
    end
end

local function uiActionBar(id, w, buttons)
    local k = uiKit()
    if k and k.renderActionBar then return k.renderActionBar(id, w, buttons) end
    local hit = nil
    for i, b in ipairs(buttons) do
        if i > 1 then ImGui.SameLine() end
        if autoBtn(b.label) then hit = i end
    end
    return hit
end

local formRevision = 1

local function cleanInputStr(v)
    return tostring(v or ""):gsub("%z.*", "")
end

local function cleanDialogField(v)
    local s = tostring(v or ""):gsub("%z.*", "")
    s = s:gsub("[\r\n|]+$", ""):gsub("^[\r\n|]+", "")
    return s:gsub("^%s+", ""):gsub("%s+$", "")
end

local lastDialogOpenAt = 0
local function safeInput(id, val, maxL, onKetikFn)
    local s = cleanInputStr(val)
    local uniqueId = tostring(id) .. "_" .. tostring(formRevision)
    local ok, r1, r2 = pcall(ImGui.InputText, uniqueId, s, maxL or 256)
    local changed = false
    local newVal = s

    if ok then
        if type(r1) == "boolean" and type(r2) == "string" then
            if r1 == true then
                changed = true
                newVal = cleanInputStr(r2)
            end
        elseif type(r1) == "string" and type(r2) == "boolean" then
            if r2 == true then
                changed = true
                newVal = cleanInputStr(r1)
            end
        end
    end

    -- Otomatis panggil Native Keyboard Dialog saat kolom form diketuk / disentuh
    if onKetikFn and ImGui then
        local clicked = false
        if ImGui.IsItemClicked then
            local okC, clk = pcall(ImGui.IsItemClicked, 0)
            if okC and clk then clicked = true end
        end
        if not clicked and ImGui.IsItemActivated then
            local okA, act = pcall(ImGui.IsItemActivated)
            if okA and act then clicked = true end
        end
        if clicked then
            local now = os.clock and os.clock() or os.time()
            if (now - lastDialogOpenAt) >= 0.8 then
                lastDialogOpenAt = now
                pcall(onKetikFn)
            end
        end
    end

    return changed, newVal
end

local function readClipLines()
    local k = uiKit()
    if k and k.readClipboardLines then return k.readClipboardLines() end
    local clip = ""
    if ImGui and ImGui.GetClipboardText then
        local ok, c = pcall(ImGui.GetClipboardText)
        if ok and type(c) == "string" then clip = c end
    end
    local out = {}
    for line in clip:gmatch("[^\r\n]+") do
        local s = trimStr(line); if s ~= "" then out[#out + 1] = s end
    end
    return out
end

local function availX()
    if ImGui and ImGui.GetContentRegionAvail then
        local ok, av = pcall(ImGui.GetContentRegionAvail)
        if ok and av then
            if type(av) == "number" and av > 40 then return av end
            local okX, x = pcall(function() return av.x end)
            if okX and type(x) == "number" and x > 40 then return x end
        end
    end
    return 480
end

-- ----------------------------------------------------------------------------
-- SUB-TAB 1: FARM LIST
-- ----------------------------------------------------------------------------
local function renderFarmsSub()
    local c, st = HV.CFG, HV.STATE
    local w = availX()

    uiSection("Kontrol Auto Harvest", true)
    ImGui.Text("Status Bot  :"); ImGui.SameLine()
    if uiEnableBtn(st.enabled, "hv_en") then
        if st.enabled then HV.stop() else HV.start() end
    end
    ImGui.SameLine(); ImGui.Text("    Loop  :"); ImGui.SameLine()
    if uiToggleBtn(c.loop_enabled, "hv_lp") then
        c.loop_enabled = not c.loop_enabled; HV.saveData()
    end
    ImGui.SameLine()
    if autoBtn(" Reset ##hv_rst") then
        for _, r in ipairs(st.rows) do r.status = "Ready" end
        HV.saveData(); uiNotice = "Semua status farm di-reset ke Ready."
    end
    ImGui.SameLine()
    if autoBtn(" Clear ##hv_clr") then
        st.rows = {}; st.selected_idx = 0; HV.saveData(); uiNotice = "Daftar farm dikosongkan."
    end

    uiGap(3)
    ImGui.Text("Take Block :"); ImGui.SameLine()
    if uiToggleBtn(c.take_block ~= false, "hv_tb_main") then
        c.take_block = not (c.take_block ~= false); HV.saveData()
    end
    ImGui.SameLine(); ImGui.Text("   Take Seed :"); ImGui.SameLine()
    if uiToggleBtn(c.take_seed ~= false, "hv_ts_main") then
        c.take_seed = not (c.take_seed ~= false); HV.saveData()
    end

    uiGap(3)
    ImGui.Text(string.format("Status: %s   |   Farm: %d   |   Tree: %d   |   Drop: %d",
        tostring(st.status_text), #st.rows, st.total_harvested, st.total_dropped))
    uiNote(uiNotice)

    uiSection("Daftar World Farm (" .. tostring(#st.rows) .. ")")

    if ImGui.BeginTable("BorenHarvestTable", 4) then
        ImGui.TableSetupColumn("World")
        ImGui.TableSetupColumn("Door ID")
        ImGui.TableSetupColumn("Block/Seed ID")
        ImGui.TableSetupColumn("Status")
        ImGui.TableHeadersRow()

        if #st.rows == 0 then
            ImGui.TableNextRow()
            ImGui.TableSetColumnIndex(0); ImGui.Text("(Kosong)")
            ImGui.TableSetColumnIndex(1); ImGui.Text("-")
            ImGui.TableSetColumnIndex(2); ImGui.Text(tostring(c.default_item_id))
            ImGui.TableSetColumnIndex(3); ImGui.Text("Tambah di bawah")
        else
            for i, r in ipairs(st.rows) do
                local bID, sID = normalizeHarvestPair(r.item_id)
                ImGui.TableNextRow()
                ImGui.TableSetColumnIndex(0)
                local sel = (st.selected_idx == i)
                if autoBtn((sel and "> " or "") .. tostring(r.name) .. "##hvr" .. tostring(i)) then
                    st.selected_idx = sel and 0 or i
                end
                ImGui.TableSetColumnIndex(1); ImGui.Text((r.door and r.door ~= "") and r.door or "-")
                ImGui.TableSetColumnIndex(2); ImGui.Text(string.format("%d / %d", bID, sID))
                ImGui.TableSetColumnIndex(3); ImGui.Text(tostring(r.status or "Ready"))
            end
        end
        ImGui.EndTable()
    end

    local function ketikFarmForm()
        local wPre = cleanDialogField(addFarmWorldBuf)
        local iPre = cleanDialogField(addFarmItemBuf ~= "" and addFarmItemBuf or (c.default_item_id and tostring(c.default_item_id) or "4584"))
        uiOpenDialog("boren_hv_fform", "Input Form Farm", {
            { id = "f_world", label = "World Farm (Nama atau Nama:DoorID)", default = wPre, maxLen = 64 },
            { id = "f_item",  label = "Item ID (Block atau Seed)", default = iPre, maxLen = 16 },
        }, "Masukkan ke Form", function(vals)
            local rawW = vals.f_world or vals["f_world"] or ""
            if rawW == "" then
                for k, v in pairs(vals) do
                    if tostring(k):lower():find("world") then rawW = v; break end
                end
            end
            local rawI = vals.f_item or vals["f_item"] or ""
            if rawI == "" then
                for k, v in pairs(vals) do
                    if tostring(k):lower():find("item") then rawI = v; break end
                end
            end
            local wn = cleanDialogField(rawW):upper()
            local iidStr = cleanDialogField(rawI):gsub("[^0-9]", "")
            if wn ~= "" then
                addFarmWorldBuf = wn
            end
            if iidStr ~= "" then
                addFarmItemBuf = iidStr
                local n = tonumber(iidStr)
                if n and n > 0 then
                    c.default_item_id = math.floor(n)
                    HV.saveData()
                end
            end
            formRevision = formRevision + 1
            uiNotice = "Form World Farm terisi: " .. tostring(addFarmWorldBuf)
        end)
    end

    uiSectionWithKetik("Tambah World Farm Baru", "hv_ktk_w", ketikFarmForm)

    if ImGui.BeginTable("BorenHarvestAddW", 2) then
        ImGui.TableSetupColumn("World:DoorID")
        ImGui.TableSetupColumn("Item ID (Block/Seed)")
        ImGui.TableHeadersRow()
        ImGui.TableNextRow()
        ImGui.TableSetColumnIndex(0)
        ImGui.PushItemWidth(math.max(120, math.floor(w * 0.56)))
        local chW, nvW = safeInput("##hv_add_w", addFarmWorldBuf, 256, ketikFarmForm)
        ImGui.PopItemWidth()
        if chW then addFarmWorldBuf = nvW end

        ImGui.TableSetColumnIndex(1)
        ImGui.PushItemWidth(math.max(80, math.floor(w * 0.34)))
        local chI, nvI = safeInput("##hv_add_item", addFarmItemBuf, 64, ketikFarmForm)
        ImGui.PopItemWidth()
        if chI then
            addFarmItemBuf = nvI:gsub("[^0-9]", "")
            local n = tonumber(addFarmItemBuf)
            if n and n > 0 then c.default_item_id = math.floor(n); HV.saveData() end
        end
        ImGui.EndTable()
    end
    uiGap(4)

    local act = uiActionBar("BorenHarvestActs", w, {
        { label = "+ Tambah##hv_add", style = "accent" },
        { label = "World Ini##hv_cur" },
        { label = "Paste List##hv_pst" },
        { label = "Copy List##hv_cpy" },
        { label = "Hapus##hv_del",    style = "muted" },
    })

    if act == 1 then
        local rawW = trimStr(addFarmWorldBuf)
        if rawW == "" then
            uiNotice = "Isi World:DoorID dulu!"
        else
            local norm = rawW:gsub("|", ":")
            local colons = 0
            for _ in norm:gmatch(":") do colons = colons + 1 end
            local p = nil
            if colons >= 2 then
                p = parseFarmRow(norm)
            else
                local wPart, dPart = norm:match("^([^:]+):(.*)$")
                local wName = trimStr(wPart or norm):upper()
                local dId   = trimStr(dPart or ""):upper()
                local iid   = math.floor(tonumber(addFarmItemBuf) or tonumber(c.default_item_id) or 4584)
                if iid <= 0 then iid = 4584 end
                if wName ~= "" then p = { name = wName, door = dId, item_id = iid, status = "Ready" } end
            end
            if p then
                table.insert(st.rows, p); addFarmWorldBuf = ""; HV.saveData()
                uiNotice = "Tersimpan: " .. p.name .. " (ID " .. tostring(p.item_id) .. ")"
            end
        end

    elseif act == 2 then
        local curW = getCurrentWorldSafe()
        if curW ~= "" and curW ~= "EXIT" then
            addFarmWorldBuf = curW .. ":"
            formRevision = formRevision + 1
            uiNotice = "Terisi " .. curW .. ": (masukkan Door ID jika ada, lalu klik + Tambah)"
        else uiNotice = "Masuk ke world dulu!" end

    elseif act == 3 then
        local added = 0
        for _, line in ipairs(readClipLines()) do
            local p = parseFarmRow(line)
            if p then table.insert(st.rows, p); added = added + 1 end
        end
        if added > 0 then HV.saveData() end
        uiNotice = "Paste berhasil: +" .. tostring(added) .. " world."

    elseif act == 4 then
        if ImGui and ImGui.SetClipboardText then
            local out = {}
            for _, r in ipairs(st.rows) do
                table.insert(out, string.format("%s:%s:%d", r.name, r.door or "", r.item_id or c.default_item_id))
            end
            pcall(ImGui.SetClipboardText, table.concat(out, "\n"))
            uiNotice = "Disalin " .. tostring(#out) .. " world ke clipboard."
        end

    elseif act == 5 then
        if st.selected_idx > 0 and st.rows[st.selected_idx] then
            table.remove(st.rows, st.selected_idx); st.selected_idx = 0; HV.saveData()
            uiNotice = "World terpilih dihapus."
        else
            uiNotice = "Pilih baris world di tabel dulu!"
        end
    end
end

-- ----------------------------------------------------------------------------
-- SUB-TAB 2: SAVE WORLD (LIST TABEL BLOCK & SEED + LIMIT CUSTOM)
-- ----------------------------------------------------------------------------
local function renderSaveSub()
    local c, st = HV.CFG, HV.STATE
    local w = availX()

    uiSection("Daftar Save World Block & Seed (" .. tostring(#st.save_rows) .. ")", true)
    uiNote(uiNotice)

    if ImGui.BeginTable("BorenHarvestSaveTbl", 5) then
        ImGui.TableSetupColumn("World")
        ImGui.TableSetupColumn("Door")
        ImGui.TableSetupColumn("Tipe")
        ImGui.TableSetupColumn("Limit (Isi)")
        ImGui.TableSetupColumn("Status")
        ImGui.TableHeadersRow()

        if #st.save_rows == 0 then
            ImGui.TableNextRow()
            ImGui.TableSetColumnIndex(0); ImGui.Text("(Kosong)")
            ImGui.TableSetColumnIndex(1); ImGui.Text("-")
            ImGui.TableSetColumnIndex(2); ImGui.Text("ALL")
            ImGui.TableSetColumnIndex(3); ImGui.Text("20.000")
            ImGui.TableSetColumnIndex(4); ImGui.Text("Tambah di bawah")
        else
            for i, r in ipairs(st.save_rows) do
                ImGui.TableNextRow()
                ImGui.TableSetColumnIndex(0)
                local sel = (st.selected_save == i)
                if autoBtn((sel and "> " or "") .. tostring(r.name) .. "##hvsr" .. tostring(i)) then
                    st.selected_save = sel and 0 or i
                end
                ImGui.TableSetColumnIndex(1); ImGui.Text((r.door and r.door ~= "") and r.door or "-")
                ImGui.TableSetColumnIndex(2); ImGui.Text(tostring(r.save_type or "ALL"))
                local limStr = (r.limit == 0) and "Unli" or string.format("%d (%d)", r.limit, r.count or 0)
                ImGui.TableSetColumnIndex(3); ImGui.Text(limStr)
                ImGui.TableSetColumnIndex(4); ImGui.Text(tostring(r.status or "Ready"))
            end
        end
        ImGui.EndTable()
    end

    local function ketikSaveForm()
        local wPre = cleanDialogField(addSaveWorldBuf)
        local lPre = cleanDialogField(addSaveLimitBuf ~= "" and addSaveLimitBuf or "0")
        uiOpenDialog("boren_hv_sform", "Input Form Save World", {
            { id = "f_world", label = "Save World (Nama atau Nama:DoorID)", default = wPre, maxLen = 64 },
            { id = "f_lim",   label = "Limit per World (0 = Unlimited)", default = lPre, maxLen = 16 },
        }, "Masukkan ke Form", function(vals)
            local wn = cleanDialogField(vals.f_world or vals["f_world"]):upper()
            local limStr = cleanDialogField(vals.f_lim or vals["f_lim"]):gsub("[^0-9]", "")
            if wn ~= "" then addSaveWorldBuf = wn end
            if limStr ~= "" then addSaveLimitBuf = limStr else addSaveLimitBuf = "0" end
            formRevision = formRevision + 1
            uiNotice = "Form Save World terisi: " .. tostring(addSaveWorldBuf)
        end)
    end

    uiSectionWithKetik("Tambah Save World Baru", "hv_ktk_sw", ketikSaveForm)

    if ImGui.BeginTable("BorenHarvestAddSwTbl", 2) then
        ImGui.TableSetupColumn("World:DoorID")
        ImGui.TableSetupColumn("Pilihan Tipe Simpan")
        ImGui.TableHeadersRow()
        ImGui.TableNextRow()
        ImGui.TableSetColumnIndex(0)
        ImGui.PushItemWidth(math.max(120, math.floor(w * 0.48)))
        local chW, nvW = safeInput("##hv_add_sw", addSaveWorldBuf, 256, ketikSaveForm)
        ImGui.PopItemWidth()
        if chW then addSaveWorldBuf = nvW end

        ImGui.TableSetColumnIndex(1)
        if autoBtn((addSaveTypeBuf == "ALL" and "[ Gabung ]" or "Gabung") .. "##sw_t_all") then addSaveTypeBuf = "ALL" end
        ImGui.SameLine()
        if autoBtn((addSaveTypeBuf == "BLOCK" and "[ Block ]" or "Block") .. "##sw_t_blk") then addSaveTypeBuf = "BLOCK" end
        ImGui.SameLine()
        if autoBtn((addSaveTypeBuf == "SEED" and "[ Seed ]" or "Seed") .. "##sw_t_sd") then addSaveTypeBuf = "SEED" end
        ImGui.EndTable()
    end

    uiGap(2)
    ImGui.Text("Limit per World (0 = Unlimited):")
    ImGui.SameLine()
    ImGui.PushItemWidth(math.max(80, math.floor(w * 0.28)))
    local chLim, nvLim = safeInput("##hv_sw_lim_in", addSaveLimitBuf, 16, ketikSaveForm)
    ImGui.PopItemWidth()
    if chLim then addSaveLimitBuf = nvLim:gsub("[^0-9]", "") end
    ImGui.SameLine()
    local isUnliSw = (addSaveLimitBuf == "0" or addSaveLimitBuf == "")
    if autoBtn(isUnliSw and "[ Unlimited ]##sw_unl" or "Unlimited##sw_unl") then
        addSaveLimitBuf = "0"
    end

    uiGap(4)
    local act = uiActionBar("BorenHarvestSaveActs", w, {
        { label = "+ Tambah##sw_add", style = "accent" },
        { label = "World Ini##sw_cur" },
        { label = "Paste List##sw_pst" },
        { label = "Reset Penuh##sw_rst_all" },
        { label = "Hapus##sw_del",    style = "muted" },
    })

    if act == 1 then
        local rawW = trimStr(addSaveWorldBuf)
        if rawW == "" then
            uiNotice = "Isi World Save dulu!"
        else
            local norm = rawW:gsub("|", ":")
            local colons = 0
            for _ in norm:gmatch(":") do colons = colons + 1 end
            if colons >= 2 then
                p = parseSaveRow(norm)
            else
                local wPart, dPart = norm:match("^([^:]+):(.*)$")
                local wName = trimStr(wPart or norm):upper()
                local dId   = trimStr(dPart or ""):upper()
                local lim   = math.floor(tonumber(addSaveLimitBuf) or 20000)
                if lim < 0 then lim = 0 end
                if wName ~= "" then p = { name = wName, door = dId, save_type = addSaveTypeBuf, limit = lim, count = 0, status = "Ready" } end
            end
        end
        if p then
            table.insert(st.save_rows, p); addSaveWorldBuf = ""; HV.saveData()
            uiNotice = "Tersimpan Save: " .. p.name .. " (" .. p.save_type .. " - " .. p.limit .. ")"
        else uiNotice = "Isi World:DoorID dulu!" end

    elseif act == 2 then
        local curW = getCurrentWorldSafe()
        if curW ~= "" and curW ~= "EXIT" then
            addSaveWorldBuf = curW .. ":"
            uiNotice = "Terisi " .. curW .. ": (masukkan Door ID jika ada, lalu klik + Tambah)"
        else uiNotice = "Masuk ke world dulu!" end

    elseif act == 3 then
        local added = 0
        local defLim = math.floor(tonumber(addSaveLimitBuf) or 20000)
        for _, line in ipairs(readClipLines()) do
            local p = parseSaveRow(line)
            if not p then
                local p2 = parseWorldDoor(line)
                if p2 then p = { name = p2.name, door = p2.door, save_type = addSaveTypeBuf, limit = defLim, count = 0, status = "Ready" } end
            end
            if p then table.insert(st.save_rows, p); added = added + 1 end
        end
        if added > 0 then HV.saveData() end
        uiNotice = "Paste berhasil: +" .. tostring(added) .. " save world."

    elseif act == 4 then
        for _, r in ipairs(st.save_rows) do r.status = "Ready" end
        HV.saveData(); uiNotice = "Status semua save world di-reset ke Ready."

    elseif act == 5 then
        if st.selected_save > 0 and st.save_rows[st.selected_save] then
            table.remove(st.save_rows, st.selected_save); st.selected_save = 0; HV.saveData()
            uiNotice = "Save world terpilih dihapus."
        else uiNotice = "Pilih baris save world di tabel dulu!" end
    end

    uiGap(4)
    uiSection("Pengaturan Drop Tas (Default: 200 Block)")
    ImGui.Text("Drop saat tas penuh    : >= " .. tostring(c.drop_threshold or 200) .. " block")
    ImGui.SameLine()
    if autoBtn(" -20 ##hv_dt1") then c.drop_threshold = math.max(20, (c.drop_threshold or 200) - 20); HV.saveData() end
    ImGui.SameLine()
    if autoBtn(" +20 ##hv_dt2") then c.drop_threshold = math.min(200, (c.drop_threshold or 200) + 20); HV.saveData() end
    ImGui.SameLine()
    if autoBtn(" Default 200 ##hv_dt_def") then c.drop_threshold = 200; HV.saveData() end
end

-- ----------------------------------------------------------------------------
-- SUB-TAB 3: EVENT SAVE (LIST TABEL EVENT + LIMIT TOTAL)
-- ----------------------------------------------------------------------------
local function renderEventSub()
    local c, st = HV.CFG, HV.STATE
    local w = availX()

    uiSection("Daftar World Save Event & Mooncake (" .. tostring(#st.event_rows) .. ")", true)
    uiNote(uiNotice)

    if ImGui.BeginTable("BorenHarvestEventTbl", 4) then
        ImGui.TableSetupColumn("World")
        ImGui.TableSetupColumn("Door")
        ImGui.TableSetupColumn("Limit Total (Isi)")
        ImGui.TableSetupColumn("Status")
        ImGui.TableHeadersRow()

        if #st.event_rows == 0 then
            ImGui.TableNextRow()
            ImGui.TableSetColumnIndex(0); ImGui.Text("(Kosong)")
            ImGui.TableSetColumnIndex(1); ImGui.Text("-")
            ImGui.TableSetColumnIndex(2); ImGui.Text("10.000")
            ImGui.TableSetColumnIndex(3); ImGui.Text("Tambah di bawah")
        else
            for i, r in ipairs(st.event_rows) do
                ImGui.TableNextRow()
                ImGui.TableSetColumnIndex(0)
                local sel = (st.selected_ev == i)
                if autoBtn((sel and "> " or "") .. tostring(r.name) .. "##hver" .. tostring(i)) then
                    st.selected_ev = sel and 0 or i
                end
                ImGui.TableSetColumnIndex(1); ImGui.Text((r.door and r.door ~= "") and r.door or "-")
                local limStr = (r.limit == 0) and "Unli" or string.format("%d (%d)", r.limit, r.count or 0)
                ImGui.TableSetColumnIndex(2); ImGui.Text(limStr)
                ImGui.TableSetColumnIndex(3); ImGui.Text(tostring(r.status or "Ready"))
            end
        end
        ImGui.EndTable()
    end

    local function ketikEventForm()
        local wPre = cleanDialogField(addEventWorldBuf)
        local lPre = cleanDialogField(addEventLimitBuf ~= "" and addEventLimitBuf or "0")
        uiOpenDialog("boren_hv_eform", "Input Form Event World", {
            { id = "f_world", label = "World Event (Nama atau Nama:DoorID)", default = wPre, maxLen = 64 },
            { id = "f_lim",   label = "Limit Total Item (0 = Unlimited)", default = lPre, maxLen = 16 },
        }, "Masukkan ke Form", function(vals)
            local wn = cleanDialogField(vals.f_world or vals["f_world"]):upper()
            local limStr = cleanDialogField(vals.f_lim or vals["f_lim"]):gsub("[^0-9]", "")
            if wn ~= "" then addEventWorldBuf = wn end
            if limStr ~= "" then addEventLimitBuf = limStr else addEventLimitBuf = "0" end
            formRevision = formRevision + 1
            uiNotice = "Form Event World terisi: " .. tostring(addEventWorldBuf)
        end)
    end

    uiSectionWithKetik("Tambah Event World Baru", "hv_ktk_ew", ketikEventForm)

    if ImGui.BeginTable("BorenHarvestAddEwTbl", 2) then
        ImGui.TableSetupColumn("World:DoorID")
        ImGui.TableSetupColumn("Limit Total Item")
        ImGui.TableHeadersRow()
        ImGui.TableNextRow()
        ImGui.TableSetColumnIndex(0)
        ImGui.PushItemWidth(math.max(120, math.floor(w * 0.52)))
        local chW, nvW = safeInput("##hv_add_ew", addEventWorldBuf, 256, ketikEventForm)
        ImGui.PopItemWidth()
        if chW then addEventWorldBuf = nvW end

        ImGui.TableSetColumnIndex(1)
        ImGui.PushItemWidth(math.max(70, math.floor(w * 0.24)))
        local chLim, nvLim = safeInput("##hv_ew_lim_in", addEventLimitBuf, 16, ketikEventForm)
        ImGui.PopItemWidth()
        if chLim then addEventLimitBuf = nvLim:gsub("[^0-9]", "") end
        ImGui.EndTable()
    end

    uiGap(2)
    ImGui.Text("Limit per World (0 = Unlimited):")
    ImGui.SameLine()
    local isUnliEv = (addEventLimitBuf == "0" or addEventLimitBuf == "")
    if autoBtn(isUnliEv and "[ Unlimited ]##ew_unl" or "Unlimited##ew_unl") then
        addEventLimitBuf = "0"
    end

    uiGap(4)
    local act = uiActionBar("BorenHarvestEventActs", w, {
        { label = "+ Tambah##ew_add", style = "accent" },
        { label = "World Ini##ew_cur" },
        { label = "Paste List##ew_pst" },
        { label = "Reset Penuh##ew_rst_all" },
        { label = "Hapus##ew_del",    style = "muted" },
    })

    if act == 1 then
        local rawW = trimStr(addEventWorldBuf)
        if rawW == "" then
            uiNotice = "Isi World Event dulu!"
        else
            local norm = rawW:gsub("|", ":")
            local colons = 0
            for _ in norm:gmatch(":") do colons = colons + 1 end
            if colons >= 2 then
                p = parseEventRow(norm)
            else
                local wPart, dPart = norm:match("^([^:]+):(.*)$")
                local wName = trimStr(wPart or norm):upper()
                local dId   = trimStr(dPart or ""):upper()
                local lim   = math.floor(tonumber(addEventLimitBuf) or 10000)
                if lim < 0 then lim = 0 end
                if wName ~= "" then p = { name = wName, door = dId, limit = lim, count = 0, status = "Ready" } end
            end
        end
        if p then
            table.insert(st.event_rows, p); addEventWorldBuf = ""; HV.saveData()
            uiNotice = "Tersimpan Event: " .. p.name .. " (Limit " .. p.limit .. ")"
        else uiNotice = "Isi World:DoorID dulu!" end

    elseif act == 2 then
        local curW = getCurrentWorldSafe()
        if curW ~= "" and curW ~= "EXIT" then
            addEventWorldBuf = curW .. ":"
            uiNotice = "Terisi " .. curW .. ": (masukkan Door ID jika ada, lalu klik + Tambah)"
        else uiNotice = "Masuk ke world dulu!" end

    elseif act == 3 then
        local added = 0
        local defLim = math.floor(tonumber(addEventLimitBuf) or 10000)
        for _, line in ipairs(readClipLines()) do
            local p = parseEventRow(line)
            if not p then
                local p2 = parseWorldDoor(line)
                if p2 then p = { name = p2.name, door = p2.door, limit = defLim, count = 0, status = "Ready" } end
            end
            if p then table.insert(st.event_rows, p); added = added + 1 end
        end
        if added > 0 then HV.saveData() end
        uiNotice = "Paste berhasil: +" .. tostring(added) .. " event world."

    elseif act == 4 then
        for _, r in ipairs(st.event_rows) do r.status = "Ready" end
        HV.saveData(); uiNotice = "Status semua world event di-reset ke Ready."

    elseif act == 5 then
        if st.selected_ev > 0 and st.event_rows[st.selected_ev] then
            table.remove(st.event_rows, st.selected_ev); st.selected_ev = 0; HV.saveData()
            uiNotice = "Event world terpilih dihapus."
        else uiNotice = "Pilih baris event world di tabel dulu!" end
    end

    uiGap(4)
    local function ketikEventIdsDialog()
        local cur = cleanDialogField(c.event_ids_raw or "")
        uiOpenDialog("boren_hv_eids", "Input ID Item Event", {
            { id = "f_eids", label = "Daftar ID Item Event (pisah koma)", default = cur, maxLen = 256 },
        }, "Simpan ID Event", function(vals)
            local raw = cleanDialogField(vals.f_eids or vals["f_eids"])
            if raw ~= "" then
                c.event_ids_raw = raw
                formRevision = formRevision + 1
                HV.saveData()
                uiNotice = "ID Event diperbarui: " .. c.event_ids_raw
            end
        end)
    end

    uiSection("Daftar ID Item Event (Disimpan ke World Event)")
    ImGui.PushItemWidth(math.max(160, math.floor(w * 0.96)))
    local chEI, vEI = safeInput("##hv_ei", c.event_ids_raw, 512, ketikEventIdsDialog)
    ImGui.PopItemWidth()
    if chEI then c.event_ids_raw = vEI; HV.saveData() end

    uiGap(2)
    ImGui.Text("Preset :")
    ImGui.SameLine()
    if autoBtn(" Mooncake (1058,1094,1096,1098,1828) ##hv_pmc") then
        c.event_ids_raw = "1058,1094,1096,1098,1828"
        HV.saveData(); uiNotice = "Preset Mooncake diterapkan."
    end
    ImGui.SameLine()
    if autoBtn(" Kosongkan ID ##hv_ceid") then
        c.event_ids_raw = ""; HV.saveData(); uiNotice = "List ID event dikosongkan."
    end

    uiGap(3)
    ImGui.Text("Drop Event saat tas    : >= " .. tostring(c.event_threshold) .. " item")
    ImGui.SameLine()
    if autoBtn(" -20 ##hv_et1") then c.event_threshold = math.max(10, c.event_threshold - 20); HV.saveData() end
    ImGui.SameLine()
    if autoBtn(" +20 ##hv_et2") then c.event_threshold = math.min(200, c.event_threshold + 20); HV.saveData() end
end

-- ----------------------------------------------------------------------------
-- SUB-TAB 4: GEAR & FUEL (TERPADU + LIST ID EQUIP ALAT)
-- ----------------------------------------------------------------------------
local function renderGearSub()
    local c = HV.CFG
    local w = availX()

    uiSection("Gudang Alat & Fuel (Gear World)", true)
    uiNote(uiNotice)

    local function ketikGearWorldDialog()
        local cur = cleanDialogField(c.gear_world or "")
        uiOpenDialog("boren_hv_gw", "Input World Ambil Gear", {
            { id = "gw", label = "Gear World (WORLD:DOOR)", default = cur, maxLen = 64 },
        }, "Simpan Gear World", function(v)
            local raw = cleanDialogField(v.gw or v["gw"]):upper()
            if raw ~= "" then
                c.gear_world = raw
                formRevision = formRevision + 1
                HV.saveData()
                uiNotice = "Gear World berhasil disimpan: " .. c.gear_world
            end
        end)
    end

    uiSectionWithKetik("World Penyimpanan Alat & Fuel (WORLD:DOOR)", "hv_ktk_gw", ketikGearWorldDialog)

    ImGui.PushItemWidth(math.max(160, math.floor(w * 0.72)))
    local chGW, vGW = safeInput("##hv_gw", c.gear_world, 128, ketikGearWorldDialog)
    ImGui.PopItemWidth()
    if chGW then c.gear_world = vGW; HV.saveData() end
    ImGui.SameLine()
    if autoBtn(" World Ini ##hv_gwc") then
        local cw = getCurrentWorldSafe()
        if cw ~= "" and cw ~= "EXIT" then
            c.gear_world = cw .. ":"
            HV.saveData(); uiNotice = "Terisi " .. cw .. ": (masukkan Door ID jika ada)"
        else uiNotice = "Masuk ke world dulu!" end
    end

    uiGap(4)
    uiSection("Auto Restock Magni & Fuel Pack")

    ImGui.Text("Ambil Magni (1252) & Fuel Pack (1746) :"); ImGui.SameLine()
    if uiToggleBtn(c.auto_magni_fuel, "hv_amf") then
        c.auto_magni_fuel = not c.auto_magni_fuel; HV.saveData()
    end

    if c.auto_magni_fuel then
        uiGap(2)
        ImGui.Text("Target Stok Fuel Pack di Tas          : " .. tostring(c.fuel_target_amt) .. " pack")
        ImGui.SameLine()
        if autoBtn(" -25 ##hv_fa1") then c.fuel_target_amt = math.max(25, c.fuel_target_amt - 25); HV.saveData() end
        ImGui.SameLine()
        if autoBtn(" +25 ##hv_fa2") then c.fuel_target_amt = math.min(200, c.fuel_target_amt + 25); HV.saveData() end

        uiGap(2)
        ImGui.Text("Fuel Guard: Stop Bot jika Fuel Habis  :"); ImGui.SameLine()
        if uiToggleBtn(c.stop_if_no_fuel, "hv_stpf") then
            c.stop_if_no_fuel = not c.stop_if_no_fuel; HV.saveData()
        end
    end

    uiGap(4)
    uiSection("Equip DCS & Harvester (Hand / Back)")
    ImGui.Text("Gunakan DCS & Harvester :"); ImGui.SameLine()
    if uiToggleBtn(c.use_dcs_harvester, "hv_use_dcs") then
        c.use_dcs_harvester = not c.use_dcs_harvester
        HV.saveData()
    end

    if c.use_dcs_harvester then
        uiGap(2)
        ImGui.Text("List ID Item Equip (DCS, Harvester, dll. pisah koma):")
        local function ketikGearEquipDialog()
            local cur = cleanDialogField(c.gear_equip_ids or "")
            uiOpenDialog("boren_hv_geq", "Input List ID Equip", {
                { id = "eq", label = "List ID Equip Alat (pisah koma)", default = cur, maxLen = 128 },
            }, "Simpan ID Equip", function(v)
                local raw = cleanDialogField(v.eq or v["eq"])
                if raw ~= "" then
                    c.gear_equip_ids = raw
                    formRevision = formRevision + 1
                    HV.saveData()
                    uiNotice = "Equip IDs berhasil disimpan: " .. c.gear_equip_ids
                end
            end)
        end

        ImGui.PushItemWidth(math.max(160, math.floor(w * 0.96)))
        local chEq, vEq = safeInput("##hv_eq_ids", c.gear_equip_ids, 256, ketikGearEquipDialog)
        ImGui.PopItemWidth()
        if chEq then c.gear_equip_ids = vEq; HV.saveData() end

        uiGap(2)
        ImGui.Text("Preset Cepat :")
        ImGui.SameLine()
        if autoBtn(" DCS + Sorrows (6840, 1966) ##eq_p1") then
            c.gear_equip_ids = "6840, 1966"; HV.saveData(); uiNotice = "Preset DCS + Sorrows diterapkan."
        end
        ImGui.SameLine()
        if autoBtn(" DCS + Normal (6840, 1830) ##eq_p2") then
            c.gear_equip_ids = "6840, 1830"; HV.saveData(); uiNotice = "Preset DCS + Normal diterapkan."
        end
        ImGui.SameLine()
        if autoBtn(" Sorrows Saja (1966) ##eq_p3") then
            c.gear_equip_ids = "1966"; HV.saveData(); uiNotice = "Preset Sorrows saja diterapkan."
        end
    end
end

-- ----------------------------------------------------------------------------
-- SUB-TAB 5: SETTINGS
-- ----------------------------------------------------------------------------
local function renderSettingsSub()
    local c = HV.CFG

    uiSection("Pengaturan Navigasi & Collect", true)

    ImGui.Text("Ignore Gems (ID 112)       :"); ImGui.SameLine()
    if uiToggleBtn(c.ignore_gems, "hv_ig") then c.ignore_gems = not c.ignore_gems; HV.saveData() end

    uiGap(2)
    ImGui.Text("Auto Collect Block/Seed    :"); ImGui.SameLine()
    if uiToggleBtn(c.auto_collect, "hv_ac") then c.auto_collect = not c.auto_collect; HV.saveData() end

    uiGap(2)
    ImGui.Text("Take Floating (Sapu Sisa)  :"); ImGui.SameLine()
    if uiToggleBtn(c.take_floating, "hv_tf") then c.take_floating = not c.take_floating; HV.saveData() end

    uiGap(2)
    ImGui.Text("Take Block Sesuai ID       :"); ImGui.SameLine()
    if uiToggleBtn(c.take_block ~= false, "hv_tb") then c.take_block = not (c.take_block ~= false); HV.saveData() end

    uiGap(2)
    ImGui.Text("Take Seed Sesuai ID        :"); ImGui.SameLine()
    if uiToggleBtn(c.take_seed ~= false, "hv_ts") then c.take_seed = not (c.take_seed ~= false); HV.saveData() end

    uiGap(2)
    ImGui.Text("Mode Traversal             :"); ImGui.SameLine()
    if uiToggleBtn(c.harvest_mode == "3zigzag", "hv_md", "3-ZIGZAG", "1-BY-1") then
        c.harvest_mode = (c.harvest_mode == "3zigzag") and "1by1" or "3zigzag"; HV.saveData()
    end

    uiGap(2)
    ImGui.Text("ModFly (Tembus Rintangan)  :"); ImGui.SameLine()
    if uiToggleBtn(c.use_modfly, "hv_mf") then c.use_modfly = not c.use_modfly; HV.saveData() end

    uiGap(4)
    uiSection("Pacing Delay Riil (Milidetik)")

    ImGui.Text("Delay Harvest              : " .. tostring(c.harvest_delay) .. " ms")
    ImGui.SameLine()
    if autoBtn(" -20 ##hv_hd1") then c.harvest_delay = math.max(90, c.harvest_delay - 20); HV.saveData() end
    ImGui.SameLine()
    if autoBtn(" +20 ##hv_hd2") then c.harvest_delay = math.min(500, c.harvest_delay + 20); HV.saveData() end

    uiGap(2)
    ImGui.Text("Delay Langkah Bot          : " .. tostring(c.step_delay) .. " ms")
    ImGui.SameLine()
    if autoBtn(" -20 ##hv_sd1") then c.step_delay = math.max(50, c.step_delay - 20); HV.saveData() end
    ImGui.SameLine()
    if autoBtn(" +20 ##hv_sd2") then c.step_delay = math.min(400, c.step_delay + 20); HV.saveData() end
end

-- ----------------------------------------------------------------------------
-- SUB-TAB 6: LOGS
-- ----------------------------------------------------------------------------
local function renderLogsSub()
    local st = HV.STATE
    local w = availX()

    uiSection("Live Preview Tas & Log Panen", true)
    ImGui.Text(string.format("Tas Saat Ini -> Block: %d | Seed: %d | Event: %d | Fuel: %d",
        st.inv_preview.block, st.inv_preview.seed, st.inv_preview.ev, st.inv_preview.fuel))

    uiGap(3)
    if autoBtn(" Bersihkan Log ##hv_clg") then st.logs = {} end
    ImGui.Separator()

    for i = 1, math.min(14, #st.logs) do
        if ImGui.TextWrapped then ImGui.TextWrapped(st.logs[i]) else ImGui.Text(st.logs[i]) end
    end
end

function HV.render(hub)
    HUB_REF = hub or HUB_REF
    if not HV.STATE.loaded then
        HV.STATE.loaded = true
        pcall(HV.loadData)
    end
    local w = availX()
    local tabs = {
        { "farms", "Farm List" },
        { "save",  "Save World" },
        { "event", "Event Save" },
        { "gear",  "Gear & Fuel" },
        { "set",   "Settings" },
        { "logs",  "Logs" },
    }
    for i, tb in ipairs(tabs) do
        if i > 1 then ImGui.SameLine() end
        if uiTabBtn(tb[2], activeSub == tb[1]) then activeSub = tb[1] end
    end
    ImGui.Separator()
    if activeSub == "farms" then renderFarmsSub()
    elseif activeSub == "save" then renderSaveSub()
    elseif activeSub == "event" then renderEventSub()
    elseif activeSub == "gear" then renderGearSub()
    elseif activeSub == "set" then renderSettingsSub()
    else renderLogsSub() end
end

return HV
