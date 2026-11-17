-- ============================================================================
-- BOREN HUB IMGUI - MODUL AUTO DIRT FARM LENGKAP (ENGINE + UI)
-- File: imgui_hub/mod_dirt_farm.lua
-- Fitur Lengkap:
--   1. Find World Otomatis (random nama, cek bebas lock & player, auto WL & Jammer aktif)
--   2. Mode Break 3 Tile Vertikal (baris tengah 27,33,39,45,51 -> break y-2,y,y+2)
--      + opsi Mode 1 Tile + Lag Guard (awaitTileLayerCleared)
--   3. Break Cave Background (t.bg == 14 / t.bg ~= 0) hingga tuntas (4 hit + wait sync)
--   4. Clear Sisi Pinggir dinamis (0,99 atau 0,1,98,99 jika Platform ON) + Sweeper sisa lag
--   5. Clear Lava & tambal Dirt + Bangun Lantai Dirt Atas (Y=2..22) 3-Zigzag + Auto Farm Dirt
--   6. Pasang Platform Sisi (102) + Auto Collect + Auto Trash + Restock Storage + Auto Save
-- ============================================================================

local DF = {
    id    = "dirt_farm",
    label = "Dirt Farm",
}

local ITEM = {
    DIRT          = 2,
    DIRT_SEED     = 3,
    LAVA          = 4,
    LAVA_SEED     = 5,
    MAIN_DOOR     = 6,
    BEDROCK       = 8,
    ROCK          = 10,
    ROCK_SEED     = 11,
    DOOR          = 12,
    CAVE_BG       = 14,
    CAVE_BG_SEED  = 15,
    PUNCH         = 18,
    WOOD_PLATFORM = 102,
    SMALL_LOCK    = 202,
    BIG_LOCK      = 204,
    HUGE_LOCK     = 206,
    JAMMER        = 226,
    WORLD_LOCK    = 242,
}

local LOCK_IDS = {
    [202] = true, [204] = true, [206] = true, [242] = true,
    [1796] = true, [2950] = true, [4994] = true, [5814] = true,
    [7188] = true, [9640] = true, [10410] = true,
}

local KNOWN_BREAK_HITS = {
    [2]  = 3, -- Dirt
    [14] = 4, -- Cave Background (4 punch!)
    [4]  = 4, -- Lava
    [10] = 6, -- Rock
}

DF.CFG = {
    storage_raw       = "",
    loop_enabled      = false,
    -- Find World
    find_world_mode   = false,
    find_name_len     = 7,
    find_use_num      = false,
    find_target_cnt   = 1,
    auto_lock_wl      = true,
    auto_place_jammer = false,
    -- Break & Build Options
    break_3_mode      = true,   -- Mode Break 3 Tile (y-2, y, y+2 sekaligus)
    break_cave_bg     = true,   -- WAJIB hancurkan Cave Background (t.bg ~= 0)
    break_lava        = true,   -- Bersihkan Lava di platform & ganti Dirt
    break_rock        = false,  -- Opsional bersihkan Rock di baris platform genap
    clear_side        = true,   -- Bersihkan sisi pinggir
    clear_rows        = true,   -- Bersihkan lorong ganjil Y=25..53
    build_upper_dirt  = true,   -- Bangun lantai Dirt atas Y=2..22 (3-zigzag)
    auto_farm_dirt    = true,   -- Tanam & panen Dirt Seed di Y=23 bila Dirt habis saat build atas
    place_platform    = false,  -- Default OFF: Pasang Wooden Platform (102) di X=1 & X=98
    platform_id       = 102,
    auto_collect      = true,
    collect_range     = 3,
    auto_trash        = true,
    trash_thresh      = 180,
    -- Delays & Cheats
    punch_delay       = 160,
    place_delay       = 160,
    step_delay        = 120,
    warp_delay        = 3500,
    use_modfly        = true,
}

DF.STATE = {
    enabled      = false,
    running      = false,
    finding_one  = false,
    status_text  = "Idle",
    rows         = {},   -- { { name="W", door="D", status="Ready" }, ... }
    selected_idx = 0,
    selected_st  = 0,
    found_count  = 0,
    logs         = {},
}

local HUB_REF = nil
local activeSub = "worlds" -- "worlds" | "find" | "storage" | "settings" | "logs"
local addWorldBuf = ""
local addStorageBuf = ""
local uiNotice = ""
local CACHED_PATH = nil
local breakCollectCounter = 0

-- ============================================================================
-- 1. SAFE HELPERS & PERSISTENCE
-- ============================================================================
local function trimStr(s)
    local out = tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")
    return out
end

local function isSystemWindows()
    if package and package.config and package.config:sub(1, 1) == "\\" then return true end
    if os and type(os.getenv) == "function" then
        local ok, env = pcall(os.getenv, "OS")
        if ok and env and tostring(env):lower():find("windows", 1, true) then return true end
    end
    return false
end

local function getDataPath()
    if CACHED_PATH then return CACHED_PATH end
    if isSystemWindows() then
        CACHED_PATH = "boren_hub_df_data.txt"
        return CACHED_PATH
    end
    local dirs = {
        "/storage/emulated/0/Android/media/launcher.powerkuy.growlauncher/ScriptLua/",
        "/storage/emulated/0/Android/data/launcher.powerkuy.growlauncher/files/ScriptLua/",
        "/storage/emulated/0/Download/",
    }
    for _, d in ipairs(dirs) do
        local p = d .. "boren_hub_df_data.txt"
        local okR, fR = pcall(io.open, p, "r")
        if okR and fR then fR:close(); CACHED_PATH = p; return p end
        local okW, fW = pcall(io.open, p, "a")
        if okW and fW then fW:close(); CACHED_PATH = p; return p end
    end
    CACHED_PATH = "boren_hub_df_data.txt"
    return CACHED_PATH
end

local function addLogUI(msg)
    local clean = tostring(msg or ""):gsub("`.", "")
    local ts = ""
    if os and type(os.date) == "function" then
        local okD, d = pcall(os.date, "%H:%M:%S")
        if okD and d then ts = "[" .. d .. "] " end
    end
    local entry = ts .. "[DF] " .. clean
    table.insert(DF.STATE.logs, 1, entry)
    if #DF.STATE.logs > 60 then table.remove(DF.STATE.logs) end
    if HUB_REF and HUB_REF.addLog then HUB_REF.addLog(entry) end
end

local function addLog(msg)
    addLogUI(msg)
    if LogToConsole then pcall(LogToConsole, "`e[Boren DF] `w" .. tostring(msg or "")) end
end

local function safeSleep(ms)
    ms = tonumber(ms) or 50
    if ms < 10 then ms = 10 end
    local fn = CSleep or sleep
    if fn then pcall(fn, ms) end
end

local function isActive()
    return (DF.STATE.running == true) or (DF.STATE.finding_one == true)
end

local function parseWorldLine(raw)
    local s = trimStr(raw)
    if s == "" or s:sub(1, 1) == "#" then return nil end
    s = s:gsub("|", ":")
    local w, d = s:match("^([^:]+):(.*)$")
    if w then
        w = trimStr(w):upper()
        d = trimStr(d):upper()
        if w == "" then return nil end
        return { name = w, door = d, status = "Ready" }
    end
    return { name = s:upper(), door = "", status = "Ready" }
end

local function getStorageList()
    local list = {}
    local raw = trimStr(DF.CFG.storage_raw)
    if raw == "" then return list end
    for tok in raw:gmatch("[^,\r\n;]+") do
        local p = parseWorldLine(tok)
        if p then table.insert(list, { name = p.name, door = p.door }) end
    end
    return list
end

local function setStorageList(list)
    local out = {}
    for _, st in ipairs(list or {}) do
        if st and st.name and st.name ~= "" then
            table.insert(out, st.door ~= "" and (st.name .. ":" .. st.door) or st.name)
        end
    end
    DF.CFG.storage_raw = table.concat(out, ",")
    DF.saveData()
end

function DF.saveData()
    local lines = {
        "CFGVER=2",
        "STORAGE=" .. tostring(DF.CFG.storage_raw or ""),
        "LOOP=" .. (DF.CFG.loop_enabled and "1" or "0"),
        "FINDMODE=" .. (DF.CFG.find_world_mode and "1" or "0"),
        "FINDLEN=" .. tostring(tonumber(DF.CFG.find_name_len) or 7),
        "FINDNUM=" .. (DF.CFG.find_use_num and "1" or "0"),
        "FINDTGT=" .. tostring(tonumber(DF.CFG.find_target_cnt) or 1),
        "AUTOWL=" .. (DF.CFG.auto_lock_wl and "1" or "0"),
        "AUTOJAM=" .. (DF.CFG.auto_place_jammer and "1" or "0"),
        "BRK3=" .. (DF.CFG.break_3_mode and "1" or "0"),
        "BRKBG=" .. (DF.CFG.break_cave_bg and "1" or "0"),
        "BRKLAVA=" .. (DF.CFG.break_lava and "1" or "0"),
        "BRKROCK=" .. (DF.CFG.break_rock and "1" or "0"),
        "CSIDE=" .. (DF.CFG.clear_side and "1" or "0"),
        "CROWS=" .. (DF.CFG.clear_rows and "1" or "0"),
        "UPDIRT=" .. (DF.CFG.build_upper_dirt and "1" or "0"),
        "AFDIRT=" .. (DF.CFG.auto_farm_dirt and "1" or "0"),
        "PPLAT=" .. (DF.CFG.place_platform and "1" or "0"),
        "PLAT=" .. tostring(tonumber(DF.CFG.platform_id) or 102),
        "ACOL=" .. (DF.CFG.auto_collect and "1" or "0"),
        "TRASH=" .. (DF.CFG.auto_trash and "1" or "0"),
        "PUNCHD=" .. tostring(tonumber(DF.CFG.punch_delay) or 160),
        "PLACED=" .. tostring(tonumber(DF.CFG.place_delay) or 160),
        "STEPD=" .. tostring(tonumber(DF.CFG.step_delay) or 120),
        "MODFLY=" .. (DF.CFG.use_modfly and "1" or "0"),
    }
    for _, r in ipairs(DF.STATE.rows) do
        table.insert(lines, "ROW=" .. r.name .. ":" .. tostring(r.door or "") .. "|" .. tostring(r.status or "Ready"))
    end
    local ok, f = pcall(io.open, getDataPath(), "w")
    if ok and f then f:write(table.concat(lines, "\n")); f:close() end
end

function DF.loadData()
    local ok, f = pcall(io.open, getDataPath(), "r")
    if not ok or not f then return end
    local txt = f:read("*a"); f:close()
    if not txt or txt == "" then return end
    DF.STATE.rows = {}
    local cfgVer = 0
    for line in txt:gmatch("[^\r\n]+") do
        local k, v = line:match("^([A-Z0-9]+)=(.*)$")
        if k == "CFGVER" then cfgVer = tonumber(v) or 0
        elseif k == "STORAGE" then DF.CFG.storage_raw = trimStr(v)
        elseif k == "LOOP" then DF.CFG.loop_enabled = (v == "1")
        elseif k == "FINDMODE" then DF.CFG.find_world_mode = (v == "1")
        elseif k == "FINDLEN" then DF.CFG.find_name_len = math.max(4, math.min(14, tonumber(v) or 7))
        elseif k == "FINDNUM" then DF.CFG.find_use_num = (v == "1")
        elseif k == "FINDTGT" then DF.CFG.find_target_cnt = math.max(1, tonumber(v) or 1)
        elseif k == "AUTOWL" then DF.CFG.auto_lock_wl = (v ~= "0")
        elseif k == "AUTOJAM" then DF.CFG.auto_place_jammer = (v == "1")
        elseif k == "BRK3" then DF.CFG.break_3_mode = (v ~= "0")
        elseif k == "BRKBG" then DF.CFG.break_cave_bg = (v ~= "0")
        elseif k == "BRKLAVA" then DF.CFG.break_lava = (v ~= "0")
        elseif k == "BRKROCK" then DF.CFG.break_rock = (v == "1")
        elseif k == "CSIDE" then DF.CFG.clear_side = (v ~= "0")
        elseif k == "CROWS" then DF.CFG.clear_rows = (v ~= "0")
        elseif k == "UPDIRT" then DF.CFG.build_upper_dirt = (v ~= "0")
        elseif k == "AFDIRT" then DF.CFG.auto_farm_dirt = (v ~= "0")
        elseif k == "PPLAT" then DF.CFG.place_platform = (v == "1")
        elseif k == "PLAT" then DF.CFG.platform_id = tonumber(v) or 102
        elseif k == "ACOL" then DF.CFG.auto_collect = (v ~= "0")
        elseif k == "TRASH" then DF.CFG.auto_trash = (v ~= "0")
        elseif k == "PUNCHD" then DF.CFG.punch_delay = tonumber(v) or 160
        elseif k == "PLACED" then DF.CFG.place_delay = tonumber(v) or 160
        elseif k == "STEPD" then DF.CFG.step_delay = tonumber(v) or 120
        elseif k == "MODFLY" then DF.CFG.use_modfly = (v ~= "0")
        elseif k == "ROW" then
            local wd, st = v:match("^(.-)|(.*)$")
            local p = parseWorldLine(wd or v)
            if p then
                p.status = (st and st ~= "") and st or "Ready"
                table.insert(DF.STATE.rows, p)
            end
        end
    end
    if cfgVer < 2 then
        DF.CFG.place_platform = false
    end
end

-- ============================================================================
-- 2. ROBUST GROWLAUNCHER STATE, INVENTORY, OBJECTS & SAFE MOVEMENT
-- ============================================================================
local function getLocalSafe()
    if not getLocal then return nil end
    local ok, p = pcall(getLocal)
    return (ok and p) and p or nil
end

local function getPlayerPos()
    local p = getLocalSafe()
    if p then
        local px = p.posX or (p.pos and p.pos.x)
        local py = p.posY or (p.pos and p.pos.y)
        if px and py then
            return math.floor((px + 10) / 32), math.floor((py + 15) / 32)
        end
    end
    return nil, nil
end

local function getCurrentWorldSafe()
    local fn = getCurrentWorldName or getWorld or getCurrentWorld
    if not fn then return "" end
    local ok, res = pcall(fn)
    if ok and type(res) == "string" then return res:upper() end
    if ok and type(res) == "table" and res.name then return tostring(res.name):upper() end
    return ""
end

local function getTileSafe(tx, ty)
    if not getTile or tx < 0 or tx > 99 or ty < 0 or ty > 59 then return nil end
    local ok, t = pcall(getTile, tx, ty)
    return (ok and t) and t or nil
end

-- Robust Inventory Reader (mendukung C++ checkInventoryCount, table, .items, & Sol2 userdata)
local function readInvItemFields(it)
    local t = type(it)
    if t ~= "table" and t ~= "userdata" then return nil, nil end
    local id, amt = nil, nil
    pcall(function() id = tonumber(it.id or it.itemid or it.itemID or it.item_id) end)
    pcall(function() amt = tonumber(it.amount or it.count or it.cnt) end)
    return id, amt
end

local function forEachInvItem(fn)
    if not getInventory then return 0 end
    local ok, inv = pcall(getInventory)
    if not ok or inv == nil then return 0 end
    local t = type(inv)
    if t ~= "table" and t ~= "userdata" then return 0 end
    local container = inv
    pcall(function()
        if inv.items ~= nil and (type(inv.items) == "table" or type(inv.items) == "userdata") then
            container = inv.items
        end
    end)

    local seen = 0
    pcall(function()
        for _, it in pairs(container) do
            local id, amt = readInvItemFields(it)
            if id and id > 0 then seen = seen + 1; fn(id, amt or 0) end
        end
    end)
    if seen == 0 then
        local okLen, n = pcall(function() return #container end)
        if not okLen or not n or n <= 0 then pcall(function() n = container:size() end) end
        local maxI = (n and tonumber(n) and tonumber(n) > 0) and tonumber(n) or 400
        local misses = 0
        for i = 0, maxI do
            local okI, it = pcall(function() return container[i] end)
            local id, amt = nil, nil
            if okI then id, amt = readInvItemFields(it) end
            if id and id > 0 then
                misses = 0; seen = seen + 1; fn(id, amt or 0)
            else
                misses = misses + 1
                if misses >= 50 and i > 5 then break end
            end
        end
    end
    return seen
end

local function getInvCount(itemID)
    local targetID = tonumber(itemID) or 0
    if targetID <= 0 then return 0 end
    if growtopia and growtopia.checkInventoryCount then
        local ok, cnt = pcall(growtopia.checkInventoryCount, targetID)
        if ok and tonumber(cnt) and tonumber(cnt) > 0 then return tonumber(cnt) end
    end
    local total = 0
    forEachInvItem(function(id, amt)
        if id == targetID and amt > 0 then total = total + amt end
    end)
    if total > 0 then return total end
    if growtopia and growtopia.checkInventory then
        local ok, has = pcall(growtopia.checkInventory, targetID)
        if ok and has == true then return 1 end
    end
    return 0
end

-- Robust World Objects Reader (mendukung table, .objects, & Sol2 userdata)
local function forEachWorldObject(fn)
    local getFn = getObjectList or getObjects or getWorldObjects
    if not getFn then return 0 end
    local ok, objs = pcall(getFn)
    if not ok or not objs then return 0 end
    local container = objs
    pcall(function()
        if type(objs) == "table" and objs.objects then container = objs.objects end
    end)

    local seen = 0
    local function processObj(obj)
        if not obj then return end
        local itemid, uid, amt, px, py = nil, nil, nil, nil, nil
        pcall(function() itemid = tonumber(obj.itemid or obj.itemId or obj.item_id) end)
        pcall(function() uid = tonumber(obj.id or obj.oid or obj.netid) end)
        pcall(function() amt = tonumber(obj.amount or obj.count) or 1 end)
        pcall(function()
            if obj.pos then
                px = tonumber(obj.pos.x or obj.pos[1])
                py = tonumber(obj.pos.y or obj.pos[2])
            end
        end)
        if not px then pcall(function() px = tonumber(obj.x or obj.posX) end) end
        if not py then pcall(function() py = tonumber(obj.y or obj.posY) end) end
        if itemid and itemid > 0 and uid and px and py then
            seen = seen + 1
            fn(itemid, uid, amt, px, py, obj)
        end
    end

    pcall(function()
        for _, obj in pairs(container) do processObj(obj) end
    end)
    if seen == 0 then
        local okLen, n = pcall(function() return #container end)
        if not okLen or not n or n <= 0 then pcall(function() n = container:size() end) end
        local maxI = (n and tonumber(n) and tonumber(n) > 0) and tonumber(n) or 1000
        local misses = 0
        for i = 0, maxI do
            local okI, obj = pcall(function() return container[i] end)
            if okI and obj then
                local prev = seen
                processObj(obj)
                if seen > prev then misses = 0 else misses = misses + 1 end
                if misses >= 50 and i > 10 then break end
            else
                misses = misses + 1
                if misses >= 50 and i > 10 then break end
            end
        end
    end
    return seen
end

local function applyCheats()
    if not editToggle then return end
    if DF.CFG.use_modfly then pcall(editToggle, "ModFly", true) end
    pcall(editToggle, "Anti Lava", true)
    pcall(editToggle, "No Lava", true)
    if DF.CFG.auto_collect then
        pcall(editToggle, "Anti Collect", false)
        pcall(editToggle, "Auto Collect", true)
    end
end

local function findMainDoor()
    if getTiles then
        local ok, tiles = pcall(getTiles)
        if ok and tiles then
            for _, t in pairs(tiles) do
                if t and tonumber(t.fg) == ITEM.MAIN_DOOR then
                    return tonumber(t.x), tonumber(t.y)
                end
            end
        end
    end
    for y = 0, 53 do
        for x = 0, 99 do
            local t = getTileSafe(x, y)
            if t and tonumber(t.fg) == ITEM.MAIN_DOOR then
                return x, y
            end
        end
    end
    return nil, nil
end

local function isTileSafeToStand(tx, ty)
    if tx < 0 or tx > 99 or ty < 0 or ty > 53 then return false end
    local t = getTileSafe(tx, ty)
    if not t then return false end
    local fg = tonumber(t.fg) or 0
    if fg == ITEM.LAVA then return false end
    local passable = (fg == 0 or fg == ITEM.MAIN_DOOR or fg == ITEM.DOOR
        or fg == ITEM.WOOD_PLATFORM or fg == (tonumber(DF.CFG.platform_id) or 102)
        or fg == ITEM.DIRT_SEED or fg == ITEM.CAVE_BG_SEED or fg == ITEM.LAVA_SEED or fg == ITEM.ROCK_SEED)
    if not passable then
        if t.collidable == true or fg == ITEM.DIRT or fg == ITEM.ROCK or fg == ITEM.BEDROCK
           or LOCK_IDS[fg] or fg == ITEM.JAMMER then
            return false
        end
    end
    if ty < 53 then
        local below = getTileSafe(tx, ty + 1)
        if below and tonumber(below.fg) == ITEM.LAVA then return false end
    end
    return true
end

-- Exact-arrival moveSafeTo dengan hop chunked 5-tile (anti stuck di tengah dirt padat & akurat untuk 3-Tile Break!)
local function moveSafeTo(tx, ty)
    if not isActive() then return false end
    tx = math.max(0, math.min(99, math.floor(tx or 0)))
    ty = math.max(0, math.min(53, math.floor(ty or 0)))
    local px, py = getPlayerPos()
    if px == tx and py == ty then return true end
    local pFn = FindPath or findPath
    if not pFn then return false end
    if DF.CFG.use_modfly and editToggle then pcall(editToggle, "ModFly", true) end

    local CHUNK_LIMIT = 5
    local function nearestFree(cx, cy)
        for r = 0, 3 do
            for oy = -r, r do
                for ox = -r, r do
                    if math.max(math.abs(ox), math.abs(oy)) == r and isTileSafeToStand(cx + ox, cy + oy) then
                        return cx + ox, cy + oy
                    end
                end
            end
        end
        return nil, nil
    end

    local stuck = 0
    local walkDelay = math.max(40, tonumber(DF.CFG.step_delay) or 120)
    for _ = 1, 45 do
        if not isActive() then return false end
        local curX, curY = getPlayerPos()
        if not curX or not curY then
            stuck = stuck + 1
            if stuck >= 3 then break end
            safeSleep(100)
        else
            if curX == tx and curY == ty then return true end
            local dx, dy = tx - curX, ty - curY
            local dist = math.max(math.abs(dx), math.abs(dy))
            if dist == 0 then return true end

            local stepX, stepY = tx, ty
            local direct = (dist <= CHUNK_LIMIT) or (stuck >= 1)
            if not direct then
                local ratio = CHUNK_LIMIT / dist
                local ix = math.max(0, math.min(99, math.floor(curX + (dx * ratio) + 0.5)))
                local iy = math.max(0, math.min(53, math.floor(curY + (dy * ratio) + 0.5)))
                stepX, stepY = nearestFree(ix, iy)
                if not stepX then stepX, stepY, direct = tx, ty, true end
            end

            pcall(pFn, stepX, stepY)
            local stepDist = math.max(math.abs(curX - stepX), math.abs(curY - stepY))
            local waited, maxWait = 0, math.max(120, math.min(1600, stepDist * 70))
            while waited < maxWait and isActive() do
                local nx, ny = getPlayerPos()
                if nx == stepX and ny == stepY then break end
                if (not direct) and nx and ny and math.abs(nx - stepX) <= 1 and math.abs(ny - stepY) <= 1 then break end
                safeSleep(25); waited = waited + 25
            end

            local npx, npy = getPlayerPos()
            if npx == tx and npy == ty then
                safeSleep(math.floor(walkDelay * 0.6))
                return true
            end
            if npx == curX and npy == curY then
                stuck = stuck + 1
                if direct and stuck >= 2 then break end
            else
                stuck = 0
                if direct and npx and npy and math.abs(npx - tx) <= 1 and math.abs(npy - ty) <= 1 and (npx ~= curX or npy ~= curY) then
                    -- Coba 1x lagi exact jika target sendiri bisa diinjak
                    if isTileSafeToStand(tx, ty) then
                        pcall(pFn, tx, ty)
                        safeSleep(math.min(180, walkDelay))
                    end
                    break
                end
            end
            safeSleep(walkDelay)
        end
    end

    local fx, fy = getPlayerPos()
    return (fx ~= nil and fy ~= nil and math.abs(fx - tx) <= 1 and math.abs(fy - ty) <= 1)
end

local function moveAdjacentSafe(tx, ty, prefDir)
    local dir = prefDir or -1
    local cands = {
        { tx + dir, ty },
        { tx - dir, ty },
        { tx, ty - 1 },
        { tx, ty + 1 },
        { tx + dir, ty - 1 },
        { tx - dir, ty - 1 },
        { tx + dir, ty + 1 },
        { tx - dir, ty + 1 },
        { tx + (dir * 2), ty },
        { tx - (dir * 2), ty },
    }
    for _, c in ipairs(cands) do
        if isTileSafeToStand(c[1], c[2]) then
            local px, py = getPlayerPos()
            if px == c[1] and py == c[2] then return true end
            if moveSafeTo(c[1], c[2]) then return true end
        end
    end
    -- Fallback neighbor non-solid walau lava check ketat
    for _, c in ipairs(cands) do
        local cx, cy = c[1], c[2]
        if cx >= 0 and cx <= 99 and cy >= 0 and cy <= 53 then
            local t = getTileSafe(cx, cy)
            local fg = tonumber(t and t.fg) or 0
            if t and (not t.collidable) and fg ~= ITEM.LAVA and fg ~= ITEM.ROCK and fg ~= ITEM.DIRT and fg ~= ITEM.BEDROCK then
                if moveSafeTo(cx, cy) then return true end
            end
        end
    end
    return false
end

local function warpToWorld(wName, doorID)
    wName = trimStr(wName):upper()
    doorID = trimStr(doorID):upper()
    if wName == "" then return false end
    if getCurrentWorldSafe() == wName and doorID == "" then applyCheats(); return true end
    local joinStr = (doorID ~= "") and (wName .. "|" .. doorID) or wName
    for _ = 1, 2 do
        if not isActive() then return false end
        if sendPacket then
            pcall(sendPacket, 3, "action|join_request\nname|" .. joinStr .. "\ninvitedWorld|0\n")
        elseif growtopia and growtopia.warpTo then
            pcall(growtopia.warpTo, joinStr)
        end
        local w, lim = 0, math.max(2200, tonumber(DF.CFG.warp_delay) or 3500)
        while w < lim and isActive() do
            safeSleep(250); w = w + 250
            if getCurrentWorldSafe() == wName then
                safeSleep(650); applyCheats(); return true
            end
        end
    end
    return getCurrentWorldSafe() == wName
end

local function rawAction(tx, ty, val)
    if not sendPacketRaw then return false end
    local p = getLocalSafe()
    local px = (p and (p.posX or (p.pos and p.pos.x))) or (tx * 32)
    local py = (p and (p.posY or (p.pos and p.pos.y))) or (ty * 32)
    return pcall(sendPacketRaw, false, {
        type = 3, value = val, px = tx, py = ty, x = px, y = py,
        state = (px > tx * 32) and 48 or 32,
    })
end

local function collectNearbyFloating(centerX, centerY, customRadius, quickMode, forceCollect)
    if (not DF.CFG.auto_collect) and (not forceCollect) then return 0 end
    local px, py = getPlayerPos()
    local refX = centerX or px
    local refY = centerY or py
    if not refX or not refY then return 0 end
    local radius = customRadius or tonumber(DF.CFG.collect_range) or 3
    local collected = 0

    forEachWorldObject(function(itemid, uid, amt, oxPx, oyPx)
        if not DF.STATE.running then return end
        if itemid == ITEM.LAVA then return end
        local ox = math.floor((oxPx + 10) / 32)
        local oy = math.floor((oyPx + 10) / 32)
        local dist = math.max(math.abs(ox - refX), math.abs(oy - refY))
        if dist <= radius and getInvCount(itemid) < 200 then
            local cpx, cpy = getPlayerPos()
            local pDist = (cpx and cpy) and math.max(math.abs(ox - cpx), math.abs(oy - cpy)) or 99
            local needWalk = ((not quickMode) and pDist > 1) or (pDist > 2)
            if needWalk and isTileSafeToStand(ox, oy) then
                moveSafeTo(ox, oy)
            end
            if sendPacketRaw then
                pcall(sendPacketRaw, false, { type = 11, value = uid, x = oxPx, y = oyPx })
            end
            if not quickMode then safeSleep(20) end
            collected = collected + 1
        end
    end)
    return collected
end

local function checkAutoTrash()
    if not DF.CFG.auto_trash or not sendPacket then return end
    local thresh = math.max(50, tonumber(DF.CFG.trash_thresh) or 180)
    local junks = { ITEM.CAVE_BG, ITEM.CAVE_BG_SEED, ITEM.LAVA, ITEM.LAVA_SEED, ITEM.ROCK, ITEM.ROCK_SEED }
    if not DF.CFG.build_upper_dirt then
        table.insert(junks, ITEM.DIRT)
        table.insert(junks, ITEM.DIRT_SEED)
    end
    for _, jid in ipairs(junks) do
        local cnt = getInvCount(jid)
        if cnt >= thresh then
            pcall(sendPacket, 2, "action|trash\n|itemID|" .. tostring(jid) .. "\n")
            safeSleep(280)
            pcall(sendPacket, 2, "action|dialog_return\ndialog_name|trash_item\nitemID|" .. tostring(jid) .. "|\ncount|" .. tostring(cnt) .. "\n")
            safeSleep(300)
        end
    end
end

-- ============================================================================
-- 3. BREAK ENGINE (FG + CAVE BACKGROUND LAG-GUARD + MODE 3 TILE BREAK)
-- ============================================================================
local function isProtectedDoorArea(tx, ty, doorX, doorY)
    if not doorX or not doorY then return false end
    if (tx == doorX and (ty == doorY or ty == doorY + 1 or ty == doorY - 1))
       or (tx == doorX + 1 and ty == doorY)
       or (tx == doorX - 1 and (ty == doorY or ty == doorY - 1)) then
        local t = getTileSafe(tx, ty)
        local fg = tonumber(t and t.fg) or 0
        if (tx == doorX and (ty == doorY or ty == doorY + 1)) or LOCK_IDS[fg] or fg == ITEM.JAMMER then
            return true
        end
        if tx == doorX and ty == doorY - 1 then return true end
    end
    return false
end

local function isTileClearableByBot(t)
    if not t then return false end
    local fg = tonumber(t.fg) or 0
    if fg == ITEM.BEDROCK or fg == ITEM.MAIN_DOOR or fg == ITEM.JAMMER or LOCK_IDS[fg] then
        return false
    end
    return true
end

local function getSideColumns()
    if not DF.CFG.clear_side then return {} end
    if not DF.CFG.place_platform then return { 0, 99 } end
    return { 1, 0, 98, 99 }
end

local function getDFRowBounds()
    if DF.CFG.place_platform then return 2, 97 end
    return 1, 98
end

local function isEdgePlatformTile(tx, ty)
    if not DF.CFG.place_platform then return false end
    if (tx == 1 or tx == 98) and (ty % 2 == 0) and ty >= 2 and ty <= 52 then
        local t = getTileSafe(tx, ty)
        if t and tonumber(t.fg) == (tonumber(DF.CFG.platform_id) or 102) then
            return true
        end
    end
    return false
end

local function isOddTileClearNeeded(tx, ty, doorX, doorY)
    if tx < 0 or tx > 99 or ty < 0 or ty > 53 then return false, false, false end
    if isProtectedDoorArea(tx, ty, doorX, doorY) then return false, false, false end
    if isEdgePlatformTile(tx, ty) then return false, false, false end
    local t = getTileSafe(tx, ty)
    if not t or not isTileClearableByBot(t) then return false, false, false end
    local fg = tonumber(t.fg) or 0
    local bg = tonumber(t.bg) or 0
    local needFg = (fg ~= 0)
    local needBg = (DF.CFG.break_cave_bg == true) and (bg ~= 0)
    return (needFg or needBg), needFg, needBg
end

local function estimateTileBreakHits(itemID)
    itemID = tonumber(itemID) or 0
    if KNOWN_BREAK_HITS[itemID] then return KNOWN_BREAK_HITS[itemID] end
    if getItemInfoByID then
        local ok, info = pcall(getItemInfoByID, itemID)
        local bh = ok and info and tonumber(info.breakHits) or 0
        if bh > 0 then
            local norm = (bh >= 12) and math.ceil(bh / 6) or math.ceil(bh)
            return math.max(2, math.min(10, norm))
        end
    end
    return 4
end

-- Tunggu sinkronisasi server bahwa layer FG / BG sudah menjadi 0
local function awaitTileLayerCleared(tx, ty, isFgLayer, maxWaitMs)
    local function checkCleared()
        local t = getTileSafe(tx, ty)
        if not t then return false, true end
        if isFgLayer then
            local fg = tonumber(t.fg) or 0
            return (fg == 0 or fg == ITEM.BEDROCK or fg == ITEM.MAIN_DOOR), false
        end
        return ((tonumber(t.bg) or 0) == 0), false
    end

    local cleared, failed = checkCleared()
    if failed then return false end
    if cleared then return true end

    local waited = 0
    while isActive() and waited < maxWaitMs do
        safeSleep(25); waited = waited + 25
        cleared, failed = checkCleared()
        if failed then return false end
        if cleared then return true end
    end
    return false
end

local function breakTileLayerWithLagGuard(tx, ty, isFgLayer, prefDir)
    local pDelay = math.max(80, tonumber(DF.CFG.punch_delay) or 160)
    for round = 1, 5 do
        if not isActive() then return false end
        local t = getTileSafe(tx, ty)
        if not t then return false end

        local curId = isFgLayer and (tonumber(t.fg) or 0) or (tonumber(t.bg) or 0)
        if curId == 0 then return true end
        if isFgLayer and (not isTileClearableByBot(t)) then return true end

        -- Pastikan tidak berdiri TEPAT di atas tile target & berada dalam jangkauan <= 2 tile
        local px, py = getPlayerPos()
        if (not px) or (px == tx and py == ty) or math.abs(px - tx) > 2 or math.abs(py - ty) > 2 or (not isTileSafeToStand(px, py)) then
            moveAdjacentSafe(tx, ty, prefDir)
        end

        local baseHits = estimateTileBreakHits(curId)
        local burst = (round == 1) and baseHits or math.min(3, math.max(1, math.ceil(baseHits / 2)))
        for _ = 1, burst do
            if not isActive() then return false end
            local ts = getTileSafe(tx, ty)
            if not ts then break end
            local stepId = isFgLayer and (tonumber(ts.fg) or 0) or (tonumber(ts.bg) or 0)
            if stepId == 0 or (isFgLayer and (not isTileClearableByBot(ts))) then return true end
            rawAction(tx, ty, ITEM.PUNCH)
            safeSleep(pDelay)
        end

        local waitWin = (round == 1) and 220 or ((round == 2) and 280 or 360)
        if awaitTileLayerCleared(tx, ty, isFgLayer, waitWin) then
            return true
        end

        -- Jika lag/rubberband di ronde >= 3, re-posisi sejenak
        if round >= 3 then
            moveAdjacentSafe(tx, ty, prefDir)
            safeSleep(120)
        end
    end

    local tEnd = getTileSafe(tx, ty)
    if not tEnd then return false end
    return isFgLayer and ((tonumber(tEnd.fg) or 0) == 0) or ((not isFgLayer) and ((tonumber(tEnd.bg) or 0) == 0))
end

-- Hancurkan FG + Cave Background (t.bg ~= 0) hingga bersih total!
local function breakTileCompletely(tx, ty, breakFg, breakBg, prefDir, skipCollect)
    if not isActive() then return false end
    if tx < 0 or tx > 99 or ty < 0 or ty > 53 then return false end
    local t = getTileSafe(tx, ty)
    if not t then return false end
    if not isTileClearableByBot(t) then return true end

    local fgDone = true
    if breakFg and (tonumber(t.fg) or 0) ~= 0 then
        fgDone = breakTileLayerWithLagGuard(tx, ty, true, prefDir)
    end

    local bgDone = true
    if breakBg and isActive() then
        local tBg = getTileSafe(tx, ty)
        if tBg and (tonumber(tBg.bg) or 0) ~= 0 then
            -- Bila FG masih tersisa akibat lag, habiskan FG dulu sebelum BG
            if (tonumber(tBg.fg) or 0) ~= 0 and isTileClearableByBot(tBg) then
                if breakFg then
                    fgDone = breakTileLayerWithLagGuard(tx, ty, true, prefDir)
                    tBg = getTileSafe(tx, ty)
                else
                    bgDone = false
                end
            end
            if tBg and (tonumber(tBg.fg) or 0) == 0 and (tonumber(tBg.bg) or 0) ~= 0 then
                bgDone = breakTileLayerWithLagGuard(tx, ty, false, prefDir)
            elseif tBg and (tonumber(tBg.fg) or 0) ~= 0 and (tonumber(tBg.bg) or 0) ~= 0 then
                bgDone = false
            end
        end
    end

    if DF.CFG.auto_collect and (not skipCollect) and DF.STATE.running then
        breakCollectCounter = breakCollectCounter + 1
        if (breakCollectCounter % 2) == 0 then
            collectNearbyFloating(tx, ty, DF.CFG.collect_range, true, false)
        end
    end
    return fgDone and bgDone
end

local function placeTileAt(tx, ty, itemID, prefDir)
    if tx < 0 or tx > 99 or ty < 0 or ty > 53 then return false end
    local t = getTileSafe(tx, ty)
    if not t then return false end
    if tonumber(t.fg) == itemID then return true end
    if getInvCount(itemID) <= 0 then return false end

    local pDelay = math.max(80, tonumber(DF.CFG.place_delay) or 160)
    local isSeed = (itemID == ITEM.DIRT_SEED or itemID == ITEM.CAVE_BG_SEED or itemID == ITEM.LAVA_SEED or itemID == ITEM.ROCK_SEED)

    for _ = 1, 8 do
        if not isActive() then return false end
        t = getTileSafe(tx, ty)
        if t and tonumber(t.fg) == itemID then return true end
        local px, py = getPlayerPos()
        local outOfRange = (not px) or math.abs(px - tx) > 2 or math.abs(py - ty) > 2
        local onTarget = (px == tx and py == ty)
        if outOfRange or ((not isSeed) and onTarget) then
            moveAdjacentSafe(tx, ty, prefDir)
        end
        rawAction(tx, ty, itemID)
        safeSleep(pDelay)
    end
    t = getTileSafe(tx, ty)
    return (t ~= nil and tonumber(t.fg) == itemID)
end

local function sanitizeLavaUnderFoot(x, y, doorX, doorY, dirX)
    if y >= 53 then return end
    local belowY = y + 1
    local checkXs = { x }
    local standX = x + (dirX or -1)
    if standX >= 0 and standX <= 99 then table.insert(checkXs, standX) end
    for _, cx in ipairs(checkXs) do
        if not isProtectedDoorArea(cx, belowY, doorX, doorY) then
            local belowTile = getTileSafe(cx, belowY)
            if belowTile and tonumber(belowTile.fg) == ITEM.LAVA then
                breakTileCompletely(cx, belowY, true, false, dirX, true)
                if belowY % 2 == 0 and getInvCount(ITEM.DIRT) > 0 then
                    placeTileAt(cx, belowY, ITEM.DIRT, dirX)
                end
            end
        end
    end
end

-- Mode Break 3 Tile Vertikal: Berdiri tetap di (standX, centerY) & break (centerY, centerY-2, centerY+2) + Lava!
local function standAndBreak3AtCol(doorX, doorY, x, centerY, safeStandDir)
    local standX = math.max(0, math.min(99, x + safeStandDir))

    -- Pastikan posisi berdiri (standX, centerY) bersih & aman dari Lava di bawah kaki
    local needS, nFgS, nBgS = isOddTileClearNeeded(standX, centerY, doorX, doorY)
    if needS then
        breakTileCompletely(standX, centerY, nFgS, nBgS, safeStandDir, true)
    end
    sanitizeLavaUnderFoot(x, centerY, doorX, doorY, safeStandDir)

    local px, py = getPlayerPos()
    if (not px) or py ~= centerY or math.abs(px - x) > 2 or (px == x and py == centerY) or (not isTileSafeToStand(px, py)) then
        if isTileSafeToStand(standX, centerY) then
            moveSafeTo(standX, centerY)
        else
            moveAdjacentSafe(x, centerY, safeStandDir)
        end
    end

    local targets = { centerY, centerY - 2, centerY + 2 }
    for _ = 1, 2 do
        local anyRem = false
        for _, ty in ipairs(targets) do
            if not DF.STATE.running then return false end
            local need, nFg, nBg = isOddTileClearNeeded(x, ty, doorX, doorY)
            if need then
                anyRem = true
                local cpx, cpy = getPlayerPos()
                if (not cpx) or math.abs(cpx - x) > 2 or math.abs(cpy - ty) > 2 then
                    if isTileSafeToStand(standX, centerY) then moveSafeTo(standX, centerY) end
                end
                breakTileCompletely(x, ty, nFg, nBg, safeStandDir, true)
            end
        end

        if DF.CFG.break_lava then
            for _, ly in ipairs({ centerY - 1, centerY + 1 }) do
                if ly >= 24 and ly <= 52 and (not isProtectedDoorArea(x, ly, doorX, doorY)) then
                    local tL = getTileSafe(x, ly)
                    if tL and tonumber(tL.fg) == ITEM.LAVA then
                        anyRem = true
                        breakTileCompletely(x, ly, true, false, safeStandDir, true)
                        if getInvCount(ITEM.DIRT) > 0 then
                            placeTileAt(x, ly, ITEM.DIRT, safeStandDir)
                        end
                    end
                end
            end
        end

        if not anyRem then break end
    end

    if DF.CFG.auto_collect then
        collectNearbyFloating(x, centerY, DF.CFG.collect_range, true, false)
    end
    checkAutoTrash()
    return true
end

-- ============================================================================
-- 4. FIND WORLD ENGINE (AUTO CARI WORLD KOSONG BEBAS LOCK & PLAYER + AUTO WL/JAMMER)
-- ============================================================================
local function generateRandomWorldName(length, useNumbers)
    local chars = useNumbers and "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789" or "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    local res = {}
    for i = 1, length do
        local idx = math.random(1, #chars)
        res[i] = chars:sub(idx, idx)
    end
    return table.concat(res)
end

local function isCurrentWorldFreeForDF()
    -- 1. Scan cepat via getTiles() (fallback ke getTileSafe) untuk cek Lock orang lain
    local scanned = false
    if getTiles then
        local okT, tiles = pcall(getTiles)
        if okT and tiles then
            scanned = true
            for _, t in pairs(tiles) do
                if t then
                    local fg = tonumber(t.fg) or 0
                    if LOCK_IDS[fg] then
                        return false, "Sudah di-lock (ID " .. tostring(fg) .. ")"
                    end
                end
            end
        end
    end
    if not scanned then
        for y = 0, 53 do
            for x = 0, 99 do
                local t = getTileSafe(x, y)
                if t then
                    local fg = tonumber(t.fg) or 0
                    if LOCK_IDS[fg] then
                        return false, "Sudah di-lock (ID " .. tostring(fg) .. ")"
                    end
                end
            end
        end
    end

    -- 2. Cek apakah ada player lain di dalam world
    if getPlayerList and getLocal then
        local okPl, players = pcall(getPlayerList)
        local me = getLocalSafe()
        local myNet = me and (me.netID or me.netid)
        if okPl and type(players) == "table" and myNet then
            for _, pl in pairs(players) do
                local pNet = pl and (pl.netID or pl.netid)
                if pNet and pNet ~= myNet then
                    return false, "Ada player lain (" .. tostring(pl.name or "?") .. ")"
                end
            end
        end
    end

    -- 3. Pastikan Main Door (ID 6) ada (menjamin tile world sudah termuat)
    local dx, dy = findMainDoor()
    if not dx or not dy then
        return false, "Main Door tidak ditemukan"
    end

    return true, "World kosong siap dipakai!", dx, dy
end

local function autoSetupLockAndJammer(doorX, doorY)
    if not doorX or not doorY then return end

    if DF.CFG.auto_lock_wl and getInvCount(ITEM.WORLD_LOCK) > 0 then
        local lockX = (doorX + 1 <= 99) and (doorX + 1) or doorX
        local lockY = (doorX + 1 <= 99) and doorY or math.max(0, doorY - 1)
        local tL = getTileSafe(lockX, lockY)
        if tL and (tonumber(tL.fg) or 0) ~= 0 and (tonumber(tL.fg) or 0) ~= ITEM.WORLD_LOCK then
            breakTileCompletely(lockX, lockY, true, false, 1, true)
        end
        if placeTileAt(lockX, lockY, ITEM.WORLD_LOCK, 1) then
            addLog("[Find World] World Lock (242) terpasang di (" .. lockX .. "," .. lockY .. ")!")
        end
    end

    if DF.CFG.auto_place_jammer and getInvCount(ITEM.JAMMER) > 0 then
        local jamX = (doorX - 1 >= 0) and (doorX - 1) or (doorX + 1)
        local jamY = math.max(0, doorY - 1)
        local tJ = getTileSafe(jamX, jamY)
        if tJ and (tonumber(tJ.fg) or 0) ~= 0 and (tonumber(tJ.fg) or 0) ~= ITEM.JAMMER then
            breakTileCompletely(jamX, jamY, true, false, -1, true)
        end
        if placeTileAt(jamX, jamY, ITEM.JAMMER, -1) then
            safeSleep(250)
            rawAction(jamX, jamY, ITEM.PUNCH) -- Punch 1x agar Signal Jammer aktif!
            safeSleep(250)
            addLog("[Find World] Signal Jammer (226) terpasang & diaktifkan!")
        end
    end
end

local function findOneFreeWorld()
    local len = math.max(4, math.min(14, tonumber(DF.CFG.find_name_len) or 7))
    local useNum = (DF.CFG.find_use_num == true)

    for attempt = 1, 25 do
        if not isActive() then return nil end
        local cand = generateRandomWorldName(len, useNum)
        DF.STATE.status_text = string.format("Find #%d: %s", attempt, cand)
        addLog(string.format("[Find World #%d] Mengecek %s...", attempt, cand))

        if warpToWorld(cand, "") then
            safeSleep(700)
            local okFree, reason, dx, dy = isCurrentWorldFreeForDF()
            if okFree then
                addLog("`2[Find World] Ketemu world kosong: " .. cand .. "!")
                autoSetupLockAndJammer(dx, dy)
                local targetRow = nil
                for _, r in ipairs(DF.STATE.rows) do
                    if r.name == cand then targetRow = r; r.status = "Ready"; break end
                end
                if not targetRow then
                    targetRow = { name = cand, door = "", status = "Ready" }
                    table.insert(DF.STATE.rows, targetRow)
                end
                DF.saveData()
                DF.STATE.found_count = DF.STATE.found_count + 1
                return targetRow
            else
                addLog("[Find World] Skip " .. cand .. ": " .. tostring(reason))
            end
        end
        safeSleep(550)
    end
    addLog("[Find World] Belum ketemu world kosong setelah 25 percobaan.")
    return nil
end

function DF.findSingleWorldNow()
    if DF.STATE.running or DF.STATE.finding_one then return end
    DF.STATE.finding_one = true
    local function runner()
        local ok, err = xpcall(function()
            local row = findOneFreeWorld()
            if row then
                uiNotice = "Ketemu world kosong: " .. row.name
                DF.STATE.status_text = "Found: " .. row.name
            else
                uiNotice = "Belum ketemu world kosong."
                DF.STATE.status_text = "Idle"
            end
        end, function(e) return tostring(e) end)
        if not ok then addLog("`4[Find Err] `w" .. tostring(err)) end
        DF.STATE.finding_one = false
    end
    if runCoroutine then pcall(runCoroutine, runner)
    else coroutine.resume(coroutine.create(runner)) end
end

-- ============================================================================
-- 5. RESTOCK STORAGE, AUTO FARM DIRT & MAIN DIRT FARM PIPELINE
-- ============================================================================
local function restockItem(farmRow, itemID, wantAmt)
    if getInvCount(itemID) >= 5 then return true end
    local storages = getStorageList()
    if #storages == 0 then
        addLog("[DF] Stok item ID " .. tostring(itemID) .. " habis & Storage kosong!")
        return false
    end
    for _, st in ipairs(storages) do
        if not DF.STATE.running then return false end
        if warpToWorld(st.name, st.door) then
            safeSleep(650)
            if editToggle then
                pcall(editToggle, "Anti Collect", false)
                pcall(editToggle, "Auto Collect", true)
            end
            forEachWorldObject(function(oid, uid, amt, rx, ry)
                if not DF.STATE.running or getInvCount(itemID) >= (wantAmt or 120) then return end
                if oid == itemID then
                    moveSafeTo(math.floor((rx + 10) / 32), math.floor((ry + 10) / 32))
                    if sendPacketRaw then
                        pcall(sendPacketRaw, false, { type = 11, value = uid, x = rx, y = ry })
                    end
                    safeSleep(180)
                end
            end)
            if getInvCount(itemID) >= 1 then
                return warpToWorld(farmRow.name, farmRow.door)
            end
        end
    end
    return false
end

-- Auto Plant & Harvest Dirt Seed di baris Y=23 saat Dirt Block habis ketika membangun lantai atas
local function farmDirtOnce(doorX, doorY, minX, maxX)
    if not DF.CFG.auto_farm_dirt then return false end
    local farmY = 23

    -- 1. Harvest pohon Dirt matang yang sudah ada di Y=23
    local harvested = false
    for x = minX, maxX do
        if not DF.STATE.running then return false end
        local t = getTileSafe(x, farmY)
        if t and tonumber(t.fg) == ITEM.DIRT_SEED and t.readyharvest then
            breakTileCompletely(x, farmY, true, false, -1, true)
            moveSafeTo(x, farmY)
            collectNearbyFloating(x, farmY, 3, false, true)
            harvested = true
            if getInvCount(ITEM.DIRT) >= 180 then return true end
        end
    end
    if harvested and getInvCount(ITEM.DIRT) > 0 then return true end

    -- 2. Tanam sampai 40 Dirt Seed di Y=23 bila punya seed
    local planted = 0
    if getInvCount(ITEM.DIRT_SEED) > 0 then
        for x = minX, maxX do
            if not DF.STATE.running or planted >= 40 or getInvCount(ITEM.DIRT_SEED) <= 0 then break end
            if not isProtectedDoorArea(x, farmY, doorX, doorY) then
                local t = getTileSafe(x, farmY)
                local b = getTileSafe(x, farmY + 1)
                if t and tonumber(t.fg) == 0 and b and tonumber(b.fg) ~= 0 then
                    if placeTileAt(x, farmY, ITEM.DIRT_SEED, -1) then
                        planted = planted + 1
                    end
                end
            end
        end
    end

    -- 3. Cek apakah ada pohon Dirt di Y=23 yang sedang tumbuh; tunggu sampai matang lalu panen
    local hasTree = false
    for x = minX, maxX do
        local t = getTileSafe(x, farmY)
        if t and tonumber(t.fg) == ITEM.DIRT_SEED then hasTree = true; break end
    end
    if not hasTree then return false end

    DF.STATE.status_text = "Tunggu Dirt Tree..."
    for _ = 1, 40 do
        if not DF.STATE.running then return false end
        local anyReady = false
        for x = minX, maxX do
            local t = getTileSafe(x, farmY)
            if t and tonumber(t.fg) == ITEM.DIRT_SEED and t.readyharvest then anyReady = true; break end
        end
        if anyReady then break end
        safeSleep(1000)
    end

    for x = minX, maxX do
        if not DF.STATE.running then return false end
        local t = getTileSafe(x, farmY)
        if t and tonumber(t.fg) == ITEM.DIRT_SEED and t.readyharvest then
            breakTileCompletely(x, farmY, true, false, -1, true)
            moveSafeTo(x, farmY)
            collectNearbyFloating(x, farmY, 3, false, true)
            if getInvCount(ITEM.DIRT) >= 185 then break end
        end
    end
    return getInvCount(ITEM.DIRT) > 0
end

local function processDirtFarmWorld(row)
    row.status = "Warping..."
    DF.STATE.status_text = "Warp: " .. row.name
    if not warpToWorld(row.name, row.door) then
        row.status = "Inaccessible"
        DF.saveData()
        return false
    end
    safeSleep(550)

    local doorX, doorY = findMainDoor()
    local minX, maxX = getDFRowBounds()
    local sideCols = getSideColumns()

    -- 1. CLEAR SISI PINGGIR (0,99 atau 1,0,98,99 jika Platform ON | Y=24..53, FG + Cave BG!)
    if DF.CFG.clear_side and #sideCols > 0 then
        row.status = "Clear Sides..."
        DF.STATE.status_text = row.name .. " Clear Sisi"
        for _, sx in ipairs(sideCols) do
            local prefDir = (sx < 50) and 1 or -1
            for sy = 24, 53 do
                if not DF.STATE.running then return false end
                local need, nFg, nBg = isOddTileClearNeeded(sx, sy, doorX, doorY)
                if need then
                    breakTileCompletely(sx, sy, nFg, nBg, prefDir, false)
                    checkAutoTrash()
                end
            end
        end
    end

    -- 2. CLEAR LORONG BARIS GANJIL (MODE 3 TILE BREAK ATAU 1 TILE BREAK + CAVE BG!)
    if DF.CFG.clear_rows then
        local goingRight = true
        if DF.CFG.break_3_mode then
            local centerRows = { 27, 33, 39, 45, 51 }
            for _, centerY in ipairs(centerRows) do
                if not DF.STATE.running then return false end
                row.status = string.format("3-Break Y=%d,%d,%d", centerY - 2, centerY, centerY + 2)
                DF.STATE.status_text = row.name .. " " .. row.status
                local x1 = goingRight and minX or maxX
                local x2 = goingRight and maxX or minX
                local step = goingRight and 1 or -1
                local safeStandDir = -step
                for x = x1, x2, step do
                    if not DF.STATE.running then return false end
                    local anyNeed = false
                    for _, ty in ipairs({ centerY, centerY - 2, centerY + 2 }) do
                        if isOddTileClearNeeded(x, ty, doorX, doorY) then anyNeed = true; break end
                    end
                    if (not anyNeed) and DF.CFG.break_lava then
                        for _, ly in ipairs({ centerY - 1, centerY + 1 }) do
                            if ly >= 24 and ly <= 52 and (not isProtectedDoorArea(x, ly, doorX, doorY)) then
                                local tL = getTileSafe(x, ly)
                                if tL and tonumber(tL.fg) == ITEM.LAVA then anyNeed = true; break end
                            end
                        end
                    end
                    if anyNeed then
                        standAndBreak3AtCol(doorX, doorY, x, centerY, safeStandDir)
                    end
                end
                goingRight = not goingRight
            end
        else
            for sy = 25, 53, 2 do
                if not DF.STATE.running then return false end
                row.status = "Clear Y=" .. tostring(sy)
                DF.STATE.status_text = row.name .. " Clear Y=" .. tostring(sy)
                local x1 = goingRight and minX or maxX
                local x2 = goingRight and maxX or minX
                local step = goingRight and 1 or -1
                for sx = x1, x2, step do
                    if not DF.STATE.running then return false end
                    local need, nFg, nBg = isOddTileClearNeeded(sx, sy, doorX, doorY)
                    if need then
                        sanitizeLavaUnderFoot(sx, sy, doorX, doorY, -step)
                        breakTileCompletely(sx, sy, nFg, nBg, -step, false)
                        checkAutoTrash()
                    end
                end
                goingRight = not goingRight
            end
        end

        -- SWEEPER SISA LAG (bersihkan sisa FG atau Cave BG yang terlewat di pinggir & lorong ganjil)
        for pass = 1, 3 do
            if not DF.STATE.running then return false end
            local leftCnt = 0
            for _, sx in ipairs(sideCols) do
                for sy = 24, 53 do
                    if not DF.STATE.running then return false end
                    local need, nFg, nBg = isOddTileClearNeeded(sx, sy, doorX, doorY)
                    if need then
                        leftCnt = leftCnt + 1
                        breakTileCompletely(sx, sy, nFg, nBg, (sx < 50) and 1 or -1, false)
                    end
                end
            end
            for sy = 25, 53, 2 do
                for sx = minX, maxX do
                    if not DF.STATE.running then return false end
                    local need, nFg, nBg = isOddTileClearNeeded(sx, sy, doorX, doorY)
                    if need then
                        leftCnt = leftCnt + 1
                        breakTileCompletely(sx, sy, nFg, nBg, -1, false)
                    end
                end
            end
            if leftCnt == 0 then break end
            safeSleep(120)
        end
    end

    -- 3. BERSIHKAN LAVA / ROCK DI PLATFORM BAWAH (Y=24..52 genap) & TAMBAL DIRT
    if DF.CFG.break_lava or DF.CFG.break_rock then
        for py = 24, 52, 2 do
            if not DF.STATE.running then return false end
            for px = minX, maxX do
                if not DF.STATE.running then return false end
                if not isProtectedDoorArea(px, py, doorX, doorY) then
                    local t = getTileSafe(px, py)
                    local fg = tonumber(t and t.fg) or 0
                    if (DF.CFG.break_lava and fg == ITEM.LAVA) or (DF.CFG.break_rock and fg == ITEM.ROCK) then
                        breakTileCompletely(px, py, true, false, -1, false)
                        if getInvCount(ITEM.DIRT) > 0 then
                            placeTileAt(px, py, ITEM.DIRT, -1)
                        end
                    end
                end
            end
        end
    end

    -- 4. BANGUN LANTAI DIRT ATAS (Y = 2, 4, ..., 22) POLA 3-ZIGZAG + AUTO FARM DIRT BILA HABIS
    if DF.CFG.build_upper_dirt then
        local pDelay = math.max(80, tonumber(DF.CFG.place_delay) or 160)
        local goingRight = true
        for py = 2, 22, 2 do
            if not DF.STATE.running then return false end
            row.status = "Build Dirt Y=" .. tostring(py)
            DF.STATE.status_text = row.name .. " Dirt Y=" .. tostring(py)
            local standY = math.max(0, py - 1)
            local standX = goingRight and (minX + 1) or (maxX - 1)
            local step = goingRight and 3 or -3
            local outOfDirt = false
            while (goingRight and standX <= maxX) or ((not goingRight) and standX >= minX) do
                if not DF.STATE.running then return false end
                local xs = goingRight and { standX - 1, standX, standX + 1 } or { standX + 1, standX, standX - 1 }
                local miss = {}
                for _, bx in ipairs(xs) do
                    if bx >= minX and bx <= maxX and (not isProtectedDoorArea(bx, py, doorX, doorY)) then
                        local t = getTileSafe(bx, py)
                        if t and (tonumber(t.fg) or 0) == 0 then table.insert(miss, bx) end
                    end
                end
                if #miss > 0 then
                    if getInvCount(ITEM.DIRT) <= 0 then
                        if not farmDirtOnce(doorX, doorY, minX, maxX) then
                            addLog("[DF] Dirt (2) & Dirt Seed (3) habis saat build baris atas Y=" .. py)
                            outOfDirt = true
                            break
                        end
                    end
                    if moveSafeTo(standX, standY) then
                        for _, bx in ipairs(miss) do
                            if not DF.STATE.running or getInvCount(ITEM.DIRT) <= 0 then break end
                            rawAction(bx, py, ITEM.DIRT)
                            safeSleep(pDelay)
                        end
                    end
                end
                standX = standX + step
            end
            if outOfDirt then break end
            goingRight = not goingRight
        end
    end

    -- 5. PASANG WOODEN PLATFORM (ID 102) DI SISI TANGGA X=1 & X=98
    if DF.CFG.place_platform then
        local platID = tonumber(DF.CFG.platform_id) or 102
        row.status = "Place Plat..."
        DF.STATE.status_text = row.name .. " Platform"
        for _, px in ipairs({ 1, 98 }) do
            for py = 2, 52, 2 do
                if not DF.STATE.running then return false end
                local t = getTileSafe(px, py)
                if t and (tonumber(t.fg) or 0) == 0 then
                    if getInvCount(platID) <= 0 then
                        if not restockItem(row, platID, 120) then
                            row.status = "No Plat"
                            DF.saveData()
                            return false
                        end
                    end
                    placeTileAt(px, py, platID, (px < 50) and 1 or -1)
                end
            end
        end
    end

    row.status = "Done"
    DF.saveData()
    addLog("[Selesai] Dirt Farm " .. row.name .. " tuntas!")
    return true
end

local function mainLoop()
    DF.STATE.running = true
    applyCheats()
    addLog("Auto Dirt Farm dimulai.")

    if DF.CFG.find_world_mode then
        -- 1. Selesaikan dulu world pending yang sudah ada di List World
        for _, row in ipairs(DF.STATE.rows) do
            if not DF.STATE.running then break end
            if row.status ~= "Done" and row.status ~= "Inaccessible" then
                processDirtFarmWorld(row)
                safeSleep(450)
            end
        end
        -- 2. Cari world random kosong sebanyak find_target_cnt
        local targetCnt = math.max(1, tonumber(DF.CFG.find_target_cnt) or 1)
        for _ = 1, targetCnt do
            if not DF.STATE.running then break end
            local foundRow = findOneFreeWorld()
            if foundRow and DF.STATE.running then
                processDirtFarmWorld(foundRow)
                safeSleep(500)
            end
        end
    else
        while DF.STATE.running do
            for _, row in ipairs(DF.STATE.rows) do
                if not DF.STATE.running then break end
                if row.status ~= "Done" and row.status ~= "Inaccessible" then
                    processDirtFarmWorld(row)
                    safeSleep(400)
                end
            end
            if not DF.STATE.running then break end
            if DF.CFG.loop_enabled and #DF.STATE.rows > 0 then
                for _, r in ipairs(DF.STATE.rows) do
                    if r.status ~= "Inaccessible" then r.status = "Ready" end
                end
                DF.saveData()
                safeSleep(2500)
            else
                break
            end
        end
    end

    DF.STATE.running = false
    DF.STATE.enabled = false
    DF.STATE.status_text = "Idle"
    addLog("Auto Dirt Farm berhenti.")
end

function DF.start()
    if DF.STATE.running then return end
    if (not DF.CFG.find_world_mode) and #DF.STATE.rows == 0 then
        addLogUI("List world kosong! Tambah world atau aktifkan Find World.")
        DF.STATE.status_text = "List Kosong"
        DF.STATE.enabled = false
        return
    end
    DF.STATE.enabled = true
    local function safeRunner()
        local ok, err = xpcall(mainLoop, function(e)
            return tostring(e) .. "\n" .. (debug and debug.traceback and debug.traceback() or "")
        end)
        if not ok then
            addLog("`4[DF Crash] `w" .. tostring(err))
            DF.STATE.running = false
            DF.STATE.enabled = false
            DF.STATE.status_text = "Error"
        end
    end
    if runCoroutine then pcall(runCoroutine, safeRunner)
    else coroutine.resume(coroutine.create(safeRunner)) end
end

function DF.stop()
    DF.STATE.running = false
    DF.STATE.finding_one = false
    DF.STATE.enabled = false
    DF.STATE.status_text = "Stopped"
end

-- Expose helpers for unit testing / diagnostics
DF._test = {
    breakTileCompletely = breakTileCompletely,
    standAndBreak3AtCol = standAndBreak3AtCol,
    isOddTileClearNeeded = isOddTileClearNeeded,
    isCurrentWorldFreeForDF = isCurrentWorldFreeForDF,
    getSideColumns = getSideColumns,
    getDFRowBounds = getDFRowBounds,
    getInvCount = getInvCount,
}

-- ============================================================================
-- 6. UI RENDERER (List World | Find World | List Storage | Settings | Logs)
-- ============================================================================
local function autoBtn(label)
    local ok, res = pcall(ImGui.Button, label)
    return ok and (res == true)
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

local function renderWorldsSub()
    local w = availX()
    ImGui.Text("Enable:"); ImGui.SameLine()
    if autoBtn(DF.STATE.enabled and "  ON  ##df_en" or "  OFF  ##df_en") then
        if DF.STATE.enabled then DF.stop() else DF.start() end
    end
    ImGui.SameLine(); ImGui.Text(" | Loop:"); ImGui.SameLine()
    if autoBtn(DF.CFG.loop_enabled and "  ON  ##df_lp" or "  OFF  ##df_lp") then
        DF.CFG.loop_enabled = not DF.CFG.loop_enabled; DF.saveData()
    end
    ImGui.SameLine()
    if autoBtn("Remove Inaccessible##df") then
        local kept, rem = {}, 0
        for _, r in ipairs(DF.STATE.rows) do
            if tostring(r.status):lower():find("inaccessible", 1, true) then rem = rem + 1
            else table.insert(kept, r) end
        end
        DF.STATE.rows = kept; DF.STATE.selected_idx = 0; DF.saveData()
        uiNotice = "Dihapus " .. tostring(rem) .. " world inaccessible."
    end

    local modeLabel = DF.CFG.find_world_mode and "Find World" or "Manual List"
    local brkLabel  = DF.CFG.break_3_mode and "3-Tile" or "1-Tile"
    local bgLabel   = DF.CFG.break_cave_bg and "BG:ON" or "BG:OFF"
    ImGui.Text(string.format("Status: %s | Mode: %s | %s | %s",
        tostring(DF.STATE.status_text), modeLabel, brkLabel, bgLabel))
    if uiNotice ~= "" then ImGui.Text("Info: " .. uiNotice) end

    ImGui.Separator()

    if ImGui.BeginTable("BorenDFTable", 3) then
        ImGui.TableSetupColumn("World Name")
        ImGui.TableSetupColumn("Door ID")
        ImGui.TableSetupColumn("Status")
        ImGui.TableHeadersRow()

        if #DF.STATE.rows == 0 then
            ImGui.TableNextRow()
            ImGui.TableSetColumnIndex(0); ImGui.Text("(Kosong)")
            ImGui.TableSetColumnIndex(1); ImGui.Text("-")
            ImGui.TableSetColumnIndex(2); ImGui.Text("Tambah / Find World")
        else
            for i, r in ipairs(DF.STATE.rows) do
                ImGui.TableNextRow()
                ImGui.TableSetColumnIndex(0)
                local sel = (DF.STATE.selected_idx == i)
                if autoBtn((sel and "> " or "") .. tostring(r.name) .. "##dfr" .. tostring(i)) then
                    DF.STATE.selected_idx = sel and 0 or i
                end
                ImGui.TableSetColumnIndex(1); ImGui.Text(r.door ~= "" and r.door or "-")
                ImGui.TableSetColumnIndex(2); ImGui.Text(tostring(r.status or "Ready"))
            end
        end
        ImGui.EndTable()
    end

    ImGui.Separator()
    ImGui.Text("Tambah World DF (Format WORLD:DOORID):")
    ImGui.PushItemWidth(math.max(160, w - 12))
    local ch, nv = ImGui.InputText("##df_add_w", tostring(addWorldBuf or ""), 256)
    ImGui.PopItemWidth()
    if ch and type(nv) == "string" then addWorldBuf = nv end

    if autoBtn(" + Add World ##df") then
        local p = parseWorldLine(addWorldBuf)
        if p then
            table.insert(DF.STATE.rows, p); addWorldBuf = ""; DF.saveData()
            addLogUI("World DF ditambah: " .. p.name)
            uiNotice = "Ditambahkan: " .. p.name
        else uiNotice = "Format: WORLD:DOORID" end
    end
    ImGui.SameLine()
    if autoBtn(" + World Ini ##df") then
        local curW = getCurrentWorldSafe()
        if curW ~= "" and curW ~= "EXIT" then addWorldBuf = curW .. ":"; uiNotice = "Terisi " .. curW
        else uiNotice = "Masuk ke world dulu!" end
    end
    ImGui.SameLine()
    if autoBtn(" - Hapus ##df") then
        local idx = DF.STATE.selected_idx
        if idx < 1 or idx > #DF.STATE.rows then idx = #DF.STATE.rows end
        if idx >= 1 and idx <= #DF.STATE.rows then
            local rem = table.remove(DF.STATE.rows, idx)
            DF.STATE.selected_idx = 0; DF.saveData()
            uiNotice = "Dihapus: " .. tostring(rem and rem.name or "")
        end
    end
    ImGui.SameLine()
    if autoBtn(" Save ##df") then DF.saveData(); uiNotice = "Tersimpan " .. tostring(#DF.STATE.rows) .. " world!" end

    if autoBtn(" Import ##df") then
        local clip = ""
        if ImGui.GetClipboardText then local ok, c = pcall(ImGui.GetClipboardText); if ok and type(c) == "string" then clip = c end end
        local n = 0
        for line in clip:gmatch("[^\r\n]+") do
            local p = parseWorldLine(line)
            if p then table.insert(DF.STATE.rows, p); n = n + 1 end
        end
        if n > 0 then DF.saveData(); uiNotice = "Import " .. tostring(n) .. " world!" else uiNotice = "Clipboard kosong." end
    end
    ImGui.SameLine()
    if autoBtn(" Export ##df") then
        local out = {}
        for _, r in ipairs(DF.STATE.rows) do table.insert(out, r.door ~= "" and (r.name .. ":" .. r.door) or r.name) end
        if ImGui.SetClipboardText then pcall(ImGui.SetClipboardText, table.concat(out, "\n")); uiNotice = "Export " .. tostring(#out) .. " world!" end
    end
    ImGui.SameLine()
    if autoBtn(" Reset Status ##df") then
        for _, r in ipairs(DF.STATE.rows) do r.status = "Ready" end
        DF.saveData(); uiNotice = "Status di-reset ke Ready."
    end
end

local function renderOptRow(label, controlFn)
    ImGui.TableNextRow()
    ImGui.TableSetColumnIndex(0)
    ImGui.Text(label)
    ImGui.TableSetColumnIndex(1)
    ImGui.Text(":")
    ImGui.SameLine()
    controlFn()
end

local function renderFindWorldSub()
    ImGui.Text("Auto Find World Kosong (Bebas Lock & Player)")
    if uiNotice ~= "" then ImGui.Text("Info: " .. uiNotice) end
    ImGui.Separator()

    if ImGui.BeginTable("BorenDFFindOpts", 2) then
        renderOptRow("Auto Find saat Start", function()
            if autoBtn(DF.CFG.find_world_mode and "  ON  ##dffm" or "  OFF  ##dffm") then
                DF.CFG.find_world_mode = not DF.CFG.find_world_mode; DF.saveData()
            end
        end)
        renderOptRow("Panjang Nama World", function()
            ImGui.Text(tostring(DF.CFG.find_name_len) .. " huruf"); ImGui.SameLine()
            if autoBtn(" -1 ##dfln1") then DF.CFG.find_name_len = math.max(4, (tonumber(DF.CFG.find_name_len) or 7) - 1); DF.saveData() end
            ImGui.SameLine()
            if autoBtn(" +1 ##dfln2") then DF.CFG.find_name_len = math.min(14, (tonumber(DF.CFG.find_name_len) or 7) + 1); DF.saveData() end
        end)
        renderOptRow("Campur Angka (0-9)", function()
            if autoBtn(DF.CFG.find_use_num and "  ON  ##dffn" or "  OFF  ##dffn") then
                DF.CFG.find_use_num = not DF.CFG.find_use_num; DF.saveData()
            end
        end)
        renderOptRow("Target Jumlah World", function()
            ImGui.Text(tostring(DF.CFG.find_target_cnt)); ImGui.SameLine()
            if autoBtn(" -1 ##dftg1") then DF.CFG.find_target_cnt = math.max(1, (tonumber(DF.CFG.find_target_cnt) or 1) - 1); DF.saveData() end
            ImGui.SameLine()
            if autoBtn(" +1 ##dftg2") then DF.CFG.find_target_cnt = math.min(50, (tonumber(DF.CFG.find_target_cnt) or 1) + 1); DF.saveData() end
        end)
        renderOptRow("Auto World Lock (242)", function()
            if autoBtn(DF.CFG.auto_lock_wl and "  ON  ##dfwl" or "  OFF  ##dfwl") then
                DF.CFG.auto_lock_wl = not DF.CFG.auto_lock_wl; DF.saveData()
            end
        end)
        renderOptRow("Auto Jammer (226)", function()
            if autoBtn(DF.CFG.auto_place_jammer and "  ON  ##dfjm" or "  OFF  ##dfjm") then
                DF.CFG.auto_place_jammer = not DF.CFG.auto_place_jammer; DF.saveData()
            end
        end)
        ImGui.EndTable()
    end

    ImGui.Separator()
    if autoBtn(DF.STATE.finding_one and " Sedang Mencari... ##dff1" or " Cari 1 World Kosong Sekarang ##dff1") then
        if not DF.STATE.finding_one then
            uiNotice = "Mencari world kosong..."
            DF.findSingleWorldNow()
        end
    end
    ImGui.SameLine()
    if autoBtn(" Stop Find ##dffs") then
        DF.STATE.finding_one = false
        uiNotice = "Pencarian dihentikan."
    end
    ImGui.Text("Total ditemukan sesi ini: " .. tostring(DF.STATE.found_count) .. " | Status: " .. tostring(DF.STATE.status_text))
end

local function renderStorageSub()
    local w = availX()
    local storages = getStorageList()
    ImGui.Text("Storage Platform / Tool (" .. tostring(#storages) .. "):")
    if uiNotice ~= "" then ImGui.Text("Info: " .. uiNotice) end

    if ImGui.BeginTable("BorenDFStorTable", 2) then
        ImGui.TableSetupColumn("Storage World")
        ImGui.TableSetupColumn("Door ID")
        ImGui.TableHeadersRow()
        if #storages == 0 then
            ImGui.TableNextRow()
            ImGui.TableSetColumnIndex(0); ImGui.Text("(Kosong)")
            ImGui.TableSetColumnIndex(1); ImGui.Text("-")
        else
            for i, st in ipairs(storages) do
                ImGui.TableNextRow()
                ImGui.TableSetColumnIndex(0)
                local sel = (DF.STATE.selected_st == i)
                if autoBtn((sel and "> " or "") .. st.name .. "##dfst" .. tostring(i)) then
                    DF.STATE.selected_st = sel and 0 or i
                end
                ImGui.TableSetColumnIndex(1); ImGui.Text(st.door ~= "" and st.door or "-")
            end
        end
        ImGui.EndTable()
    end

    ImGui.Separator()
    ImGui.Text("Tambah Storage (WORLD:DOORID):")
    ImGui.PushItemWidth(math.max(160, w - 12))
    local ch, nv = ImGui.InputText("##df_add_st", tostring(addStorageBuf or ""), 256)
    ImGui.PopItemWidth()
    if ch and type(nv) == "string" then addStorageBuf = nv end

    if autoBtn(" + Add Storage ##df") then
        local p = parseWorldLine(addStorageBuf)
        if p then
            table.insert(storages, { name = p.name, door = p.door })
            setStorageList(storages); addStorageBuf = ""; uiNotice = "Storage ditambah: " .. p.name
        else uiNotice = "Format: WORLD:DOORID" end
    end
    ImGui.SameLine()
    if autoBtn(" - Hapus ##dfst") then
        local idx = DF.STATE.selected_st
        if idx < 1 or idx > #storages then idx = #storages end
        if idx >= 1 and idx <= #storages then
            table.remove(storages, idx); DF.STATE.selected_st = 0; setStorageList(storages); uiNotice = "Storage dihapus."
        end
    end
end

local function renderSettingsSub()
    ImGui.Text("Pengaturan Dirt Farm (Break & Build)")
    ImGui.Separator()

    if ImGui.BeginTable("BorenDFSetOpts", 2) then
        renderOptRow("Break 3 Tile", function()
            if autoBtn(DF.CFG.break_3_mode and "  ON (3-Tile)  ##dfb3" or "  OFF (1-Tile)  ##dfb3") then
                DF.CFG.break_3_mode = not DF.CFG.break_3_mode; DF.saveData()
            end
        end)
        renderOptRow("Break Cave BG (14)", function()
            if autoBtn(DF.CFG.break_cave_bg and "  ON  ##dfbg" or "  OFF  ##dfbg") then
                DF.CFG.break_cave_bg = not DF.CFG.break_cave_bg; DF.saveData()
            end
        end)
        renderOptRow("Break Lava & Tambal", function()
            if autoBtn(DF.CFG.break_lava and "  ON  ##dflv" or "  OFF  ##dflv") then
                DF.CFG.break_lava = not DF.CFG.break_lava; DF.saveData()
            end
        end)
        renderOptRow("Break Rock Platform", function()
            if autoBtn(DF.CFG.break_rock and "  ON  ##dfrk" or "  OFF  ##dfrk") then
                DF.CFG.break_rock = not DF.CFG.break_rock; DF.saveData()
            end
        end)
        renderOptRow("Clear Sisi Pinggir", function()
            if autoBtn(DF.CFG.clear_side and "  ON  ##dfc1" or "  OFF  ##dfc1") then
                DF.CFG.clear_side = not DF.CFG.clear_side; DF.saveData()
            end
        end)
        renderOptRow("Clear Lorong Baris", function()
            if autoBtn(DF.CFG.clear_rows and "  ON  ##dfc2" or "  OFF  ##dfc2") then
                DF.CFG.clear_rows = not DF.CFG.clear_rows; DF.saveData()
            end
        end)
        renderOptRow("Bangun Dirt Atas", function()
            if autoBtn(DF.CFG.build_upper_dirt and "  ON  ##dfud" or "  OFF  ##dfud") then
                DF.CFG.build_upper_dirt = not DF.CFG.build_upper_dirt; DF.saveData()
            end
        end)
        renderOptRow("Auto Farm Dirt", function()
            if autoBtn(DF.CFG.auto_farm_dirt and "  ON  ##dfaf" or "  OFF  ##dfaf") then
                DF.CFG.auto_farm_dirt = not DF.CFG.auto_farm_dirt; DF.saveData()
            end
        end)
        renderOptRow("Pasang Platform (102)", function()
            if autoBtn(DF.CFG.place_platform and "  ON  ##dfc3" or "  OFF  ##dfc3") then
                DF.CFG.place_platform = not DF.CFG.place_platform; DF.saveData()
            end
        end)
        renderOptRow("Auto Collect Drops", function()
            if autoBtn(DF.CFG.auto_collect and "  ON  ##dfac" or "  OFF  ##dfac") then
                DF.CFG.auto_collect = not DF.CFG.auto_collect; DF.saveData()
            end
        end)
        renderOptRow("Auto Trash Sampah", function()
            if autoBtn(DF.CFG.auto_trash and "  ON  ##dfc4" or "  OFF  ##dfc4") then
                DF.CFG.auto_trash = not DF.CFG.auto_trash; DF.saveData()
            end
        end)
        renderOptRow("ModFly", function()
            if autoBtn(DF.CFG.use_modfly and "  ON  ##dfc5" or "  OFF  ##dfc5") then
                DF.CFG.use_modfly = not DF.CFG.use_modfly; DF.saveData()
            end
        end)
        renderOptRow("Punch Delay", function()
            ImGui.Text(tostring(DF.CFG.punch_delay) .. " ms"); ImGui.SameLine()
            if autoBtn(" -20 ##dfp1") then DF.CFG.punch_delay = math.max(80, (tonumber(DF.CFG.punch_delay) or 160) - 20); DF.saveData() end
            ImGui.SameLine()
            if autoBtn(" +20 ##dfp2") then DF.CFG.punch_delay = math.min(400, (tonumber(DF.CFG.punch_delay) or 160) + 20); DF.saveData() end
        end)
        renderOptRow("Place Delay", function()
            ImGui.Text(tostring(DF.CFG.place_delay) .. " ms"); ImGui.SameLine()
            if autoBtn(" -20 ##dfl1") then DF.CFG.place_delay = math.max(80, (tonumber(DF.CFG.place_delay) or 160) - 20); DF.saveData() end
            ImGui.SameLine()
            if autoBtn(" +20 ##dfl2") then DF.CFG.place_delay = math.min(400, (tonumber(DF.CFG.place_delay) or 160) + 20); DF.saveData() end
        end)
        ImGui.EndTable()
    end
end

local function renderLogsSub()
    if autoBtn(" Clear Logs ##df") then DF.STATE.logs = {} end
    ImGui.Separator()
    if #DF.STATE.logs == 0 then ImGui.Text("Belum ada log Dirt Farm.")
    else
        for i = 1, math.min(20, #DF.STATE.logs) do ImGui.TextWrapped(tostring(DF.STATE.logs[i])) end
    end
end

function DF.render(hub)
    if autoBtn(activeSub == "worlds" and "[ List World ]" or "List World") then activeSub = "worlds" end
    ImGui.SameLine()
    if autoBtn(activeSub == "find" and "[ Find World ]" or "Find World") then activeSub = "find" end
    ImGui.SameLine()
    if autoBtn(activeSub == "storage" and "[ List Storage ]" or "List Storage") then activeSub = "storage" end
    ImGui.SameLine()
    if autoBtn(activeSub == "settings" and "[ Settings ]" or "Settings") then activeSub = "settings" end
    ImGui.SameLine()
    if autoBtn(activeSub == "logs" and "[ Logs ]" or "Logs") then activeSub = "logs" end
    ImGui.Separator()

    if activeSub == "worlds" then renderWorldsSub()
    elseif activeSub == "find" then renderFindWorldSub()
    elseif activeSub == "storage" then renderStorageSub()
    elseif activeSub == "settings" then renderSettingsSub()
    else renderLogsSub() end
end

function DF.init(hub)
    HUB_REF = hub
    DF.loadData()
end

return DF
