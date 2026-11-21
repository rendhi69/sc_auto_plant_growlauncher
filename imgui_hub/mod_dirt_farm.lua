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
    META  = {
        type    = "boren_gl_feature",
        id      = "dirt_farm",
        label   = "Dirt Farm",
        order   = 20,
        enabled = true,
    },
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
    WRENCH        = 32,
    WOOD_PLATFORM = 102,
    SMALL_LOCK    = 202,
    BIG_LOCK      = 204,
    HUGE_LOCK     = 206,
    JAMMER        = 226,
    WORLD_LOCK    = 242,
    AIR_VENT      = 2810,
}

local DOOR_ID_PRESETS = {
    { id = 12,   name = "Door" },
    { id = 30,   name = "Dungeon Door" },
    { id = 544,  name = "Orange Portal" },
    { id = 224,  name = "House Entrance" },
    { id = 2810, name = "Air Vent" },
}

local BLOCKER_PRESETS = {
    { id = 2810, name = "Air Vent" },
    { id = 12,   name = "Door" },
    { id = 30,   name = "Dungeon Door" },
    { id = 60,   name = "Portcullis" },
    { id = 224,  name = "House Entrance" },
    { id = 858,  name = "Screen Door" },
    { id = 544,  name = "Orange Portal" },
}

local PLATFORM_PRESETS = {
    { id = 102,  name = "Wooden Platform" },
    { id = 998,  name = "Fire Escape" },
    { id = 1324, name = "Rock Platform" },
    { id = 1616, name = "Staging Platform" },
    { id = 3572, name = "Cave Platform" },
    { id = 4546, name = "Hover Platform" },
    { id = 8676, name = "Bamboo Platform" },
}

local PLATFORM_NAME_MAP = {
    [102]  = "Wooden Platform",
    [998]  = "Fire Escape",
    [1324] = "Rock Platform",
    [1616] = "Staging Platform",
    [3572] = "Cave Platform",
    [4546] = "Hover Platform",
    [8676] = "Bamboo Platform",
}

local DOOR_NAME_MAP = {
    [12]   = "Door",
    [30]   = "Dungeon Door",
    [60]   = "Portcullis",
    [224]  = "House Entrance",
    [544]  = "Orange Portal",
    [546]  = "Blue Portal",
    [858]  = "Screen Door",
    [2810] = "Air Vent",
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
    storage_raw         = "",
    save_world          = "",     -- World penyimpanan sisa Dirt Block & Dirt Seed (kosong = biarkan di Dirt Farm)
    loop_enabled        = false,
    -- Find World
    find_world_mode     = false,
    find_name_len       = 7,
    find_use_num        = false,
    find_target_cnt     = 1,
    -- Security: Lock, Jammer, Door ID & Penghalang (Blocker) — Default SEMUA ON (Add World & Find World)
    auto_lock_wl        = true,
    wl_public           = true,
    auto_place_sl       = true,
    auto_place_jammer   = true,
    use_id_door         = true,
    id_door_itemid      = 12,     -- Default Door (12)
    door_id             = "DF123",
    door_label          = "BOREN STORE",
    use_blocker_door    = true,
    blocker_door_itemid = 2810,   -- Default Air Vent (2810)
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
    trash_list_raw    = "14,4,5,10,11", -- Default: Cave BG (14), Lava (4), Lava Seed (5), Rock (10), Rock Seed (11) — TANPA Cave BG Seed (15)!
    save_seed_list_raw = "3,2",         -- Default: Dirt Seed (3), Dirt (2)
    -- Delays & Cheats
    punch_delay       = 160,
    place_delay       = 160,
    step_delay        = 120,
    warp_delay        = 3500,
    use_modfly        = true,
    ignore_lock       = false,
}

local DEFAULT_TRASH_RAW = "14,4,5,10,11"
local TRASH_ITEM_NAME_MAP = {
    [2]  = "Dirt",
    [3]  = "Dirt Seed",
    [4]  = "Lava",
    [5]  = "Lava Seed",
    [10] = "Rock",
    [11] = "Rock Seed",
    [14] = "Cave Background",
    [15] = "Cave Background Seed",
}

DF.STATE = {
    enabled            = false,
    running            = false,
    finding_one        = false,
    in_storage         = false,
    anti_take_active   = false,
    pending_drop_id    = 0,
    pending_drop_amt   = 0,
    drop_confirmed     = false,
    checking_door_edit = false,
    door_edit_seen     = false,
    door_edit_id       = "",
    door_edit_locked   = false,
    checking_wl_edit   = false,
    wl_edit_seen       = false,
    wl_edit_is_public  = false,
    wl_edit_return_pkt = "",
    world_enter_public = nil,   -- nil=belum diketahui, true=world masuk [OPEN]/Public, false=world masuk Private
    status_text        = "Idle",
    rows               = {},   -- { { name="W", door="D", status="Ready" }, ... }
    selected_idx       = 0,
    selected_st        = 0,
    selected_sw        = 0,
    selected_ssid      = 0,
    selected_tr        = 0,
    found_count        = 0,
    df_stash_spots     = {},   -- Petak drop sementara Dirt/Seed di DF agar tidak langsung terhisap balik saat break
    logs               = {},
}

local HUB_REF = nil
local activeSub = "worlds" -- "worlds" | "find" | "storage" | "settings" | "logs"
local addWorldBuf = ""
local addDoorBuf = ""
local addStorageBuf = ""
local addStorageDoorBuf = ""
local addSaveBuf = ""
local addSaveDoorBuf = ""
local addSaveSeedItemBuf = ""
local addTrashBuf = ""
local uiNotice = ""
local CACHED_PATH = nil
local breakCollectCounter = 0
local activeTargetWorld = ""

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
local function safeInputText(id, curVal, maxLen, onDoubleTapFn)
    local s = cleanInputStr(curVal)
    local uniqueId = tostring(id) .. "_" .. tostring(formRevision)
    local ok, r1, r2 = pcall(ImGui.InputText, uniqueId, s, maxLen or 256)
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
    local tapFn = (type(onDoubleTapFn) == "function") and onDoubleTapFn or nil
    if tapFn and ImGui then
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
                pcall(tapFn)
            end
        end
    end

    return changed, newVal
end

local function saveDataDebounced()
    local k = HUB_REF and HUB_REF.ui_kit
    if k and k.scheduleSave then
        k.scheduleSave("df_cfg", DF.saveData, 0.55)
    else
        DF.saveData()
    end
end

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

local function getSaveWorldList()
    local list = {}
    local raw = trimStr(DF.CFG.save_world)
    if raw == "" then return list end
    for tok in raw:gmatch("[^,\r\n;]+") do
        local p = parseWorldLine(tok)
        if p then table.insert(list, { name = p.name, door = p.door }) end
    end
    return list
end

local function setSaveWorldList(list)
    local out = {}
    for _, sw in ipairs(list or {}) do
        if sw and sw.name and sw.name ~= "" then
            table.insert(out, sw.door ~= "" and (sw.name .. ":" .. sw.door) or sw.name)
        end
    end
    DF.CFG.save_world = table.concat(out, ",")
    DF.saveData()
end

local DEFAULT_SAVE_SEED_RAW = "3,2"

local function getSaveSeedList()
    local list, seen = {}, {}
    local raw = trimStr(DF.CFG.save_seed_list_raw)
    if raw == "" then raw = DEFAULT_SAVE_SEED_RAW end
    for tok in raw:gmatch("[^,%s;|\r\n]+") do
        local n = math.floor(tonumber(tok) or 0)
        if n > 0 and not seen[n] then
            seen[n] = true
            table.insert(list, n)
        end
    end
    return list
end

local function setSaveSeedList(list)
    local out, seen = {}, {}
    for _, id in ipairs(list or {}) do
        local n = math.floor(tonumber(id) or 0)
        if n > 0 and not seen[n] then
            seen[n] = true
            table.insert(out, tostring(n))
        end
    end
    DF.CFG.save_seed_list_raw = table.concat(out, ",")
    DF.saveData()
end

local function getTrashList()
    local list, seen = {}, {}
    local raw = trimStr(DF.CFG.trash_list_raw)
    if raw == "" then return list end
    for tok in raw:gmatch("[^,%s;|\r\n]+") do
        local n = math.floor(tonumber(tok) or 0)
        if n > 0 and not seen[n] then
            seen[n] = true
            table.insert(list, n)
        end
    end
    return list
end

local function setTrashList(list)
    local out, seen = {}, {}
    for _, id in ipairs(list or {}) do
        local n = math.floor(tonumber(id) or 0)
        if n > 0 and not seen[n] then
            seen[n] = true
            table.insert(out, tostring(n))
        end
    end
    DF.CFG.trash_list_raw = table.concat(out, ",")
    DF.saveData()
end

function DF.saveData()
    local lines = {
        "CFGVER=4",
        "STORAGE=" .. tostring(DF.CFG.storage_raw or ""),
        "SAVEW=" .. tostring(DF.CFG.save_world or ""),
        "SAVESIDELIST=" .. tostring(DF.CFG.save_seed_list_raw or DEFAULT_SAVE_SEED_RAW),
        "TRASHLIST=" .. tostring(DF.CFG.trash_list_raw or ""),
        "LOOP=" .. (DF.CFG.loop_enabled and "1" or "0"),
        "FINDMODE=" .. (DF.CFG.find_world_mode and "1" or "0"),
        "FINDLEN=" .. tostring(tonumber(DF.CFG.find_name_len) or 7),
        "FINDNUM=" .. (DF.CFG.find_use_num and "1" or "0"),
        "FINDTGT=" .. tostring(tonumber(DF.CFG.find_target_cnt) or 1),
        "AUTOWL=" .. (DF.CFG.auto_lock_wl and "1" or "0"),
        "WLPUB=" .. (DF.CFG.wl_public and "1" or "0"),
        "AUTOSL=" .. (DF.CFG.auto_place_sl and "1" or "0"),
        "AUTOJAM=" .. (DF.CFG.auto_place_jammer and "1" or "0"),
        "USEIDDOOR=" .. (DF.CFG.use_id_door and "1" or "0"),
        "IDDOORITEM=" .. tostring(tonumber(DF.CFG.id_door_itemid) or 12),
        "DOORID=" .. tostring(DF.CFG.door_id or "DF123"),
        "DOORLBL=" .. tostring(DF.CFG.door_label or "BOREN STORE"),
        "USEBLK=" .. (DF.CFG.use_blocker_door and "1" or "0"),
        "BLKITEM=" .. tostring(tonumber(DF.CFG.blocker_door_itemid) or 2810),
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
        "IGNORELOCK=" .. (DF.CFG.ignore_lock and "1" or "0"),
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
    local sawTrashList = false
    local sawSaveSeedList = false
    for line in txt:gmatch("[^\r\n]+") do
        local k, v = line:match("^([A-Z0-9]+)=(.*)$")
        if k == "CFGVER" then cfgVer = tonumber(v) or 0
        elseif k == "STORAGE" then DF.CFG.storage_raw = trimStr(v)
        elseif k == "SAVEW" then DF.CFG.save_world = trimStr(v)
        elseif k == "SAVESIDELIST" then DF.CFG.save_seed_list_raw = trimStr(v); sawSaveSeedList = true
        elseif k == "TRASHLIST" then DF.CFG.trash_list_raw = trimStr(v); sawTrashList = true
        elseif k == "LOOP" then DF.CFG.loop_enabled = (v == "1")
        elseif k == "FINDMODE" then DF.CFG.find_world_mode = (v == "1")
        elseif k == "FINDLEN" then DF.CFG.find_name_len = math.max(4, math.min(14, tonumber(v) or 7))
        elseif k == "FINDNUM" then DF.CFG.find_use_num = (v == "1")
        elseif k == "FINDTGT" then DF.CFG.find_target_cnt = math.max(1, tonumber(v) or 1)
        elseif k == "AUTOWL" then DF.CFG.auto_lock_wl = (v ~= "0")
        elseif k == "WLPUB" then DF.CFG.wl_public = (v ~= "0")
        elseif k == "AUTOSL" then DF.CFG.auto_place_sl = (v == "1")
        elseif k == "AUTOJAM" then DF.CFG.auto_place_jammer = (v == "1")
        elseif k == "USEIDDOOR" then DF.CFG.use_id_door = (v == "1")
        elseif k == "IDDOORITEM" then DF.CFG.id_door_itemid = math.max(1, tonumber(v) or 12)
        elseif k == "DOORID" then DF.CFG.door_id = trimStr(v)
        elseif k == "DOORLBL" then DF.CFG.door_label = trimStr(v)
        elseif k == "USEBLK" then DF.CFG.use_blocker_door = (v == "1")
        elseif k == "BLKITEM" then DF.CFG.blocker_door_itemid = math.max(1, tonumber(v) or 2810)
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
        elseif k == "IGNORELOCK" then DF.CFG.ignore_lock = (v == "1")
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
    if cfgVer < 3 then
        DF.CFG.auto_lock_wl      = true
        DF.CFG.auto_place_sl     = true
        DF.CFG.auto_place_jammer = true
        DF.CFG.use_blocker_door  = true
        DF.CFG.use_id_door       = true
    end
    if (cfgVer < 4) or (not sawTrashList) then
        DF.CFG.trash_list_raw = DEFAULT_TRASH_RAW
        DF.saveData()
    elseif cfgVer < 3 then
        DF.saveData()
    end
    if not sawSaveSeedList or DF.CFG.save_seed_list_raw == "" then
        DF.CFG.save_seed_list_raw = DEFAULT_SAVE_SEED_RAW
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

local function cleanWorldName(s)
    local out = tostring(s or ""):gsub("%z", ""):gsub("`.", ""):gsub("^%s+", ""):gsub("%s+$", ""):upper()
    return out
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

local function setAutoCollectActive(enabled)
    if not editToggle then return end
    if enabled then
        pcall(editToggle, "Anti Collect", false)
        pcall(editToggle, "Anti-Collect", false)
        pcall(editToggle, "Auto Collect", true)
        pcall(editToggle, "AutoCollect", true)
    else
        pcall(editToggle, "Auto Collect", false)
        pcall(editToggle, "AutoCollect", false)
        pcall(editToggle, "Anti Collect", true)
        pcall(editToggle, "Anti-Collect", true)
    end
end

local function applyCheats()
    if not editToggle then return end
    if DF.CFG.use_modfly then pcall(editToggle, "ModFly", true) end
    pcall(editToggle, "Anti Lava", true)
    pcall(editToggle, "No Lava", true)
    if DF.STATE.in_storage or DF.STATE.anti_take_active then
        return
    end
    setAutoCollectActive(DF.CFG.auto_collect == true)
end

local function findMainDoor()
    if getTiles then
        local ok, tiles = pcall(getTiles)
        if ok and tiles then
            for _, t in pairs(tiles) do
                if t and tonumber(t.fg) == ITEM.MAIN_DOOR then
                    local tx, ty = tonumber(t.x), tonumber(t.y)
                    if tx and ty then return tx, ty end
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

local activeTargetDoor = ""

local function setConnWarping(flag)
    if HUB_REF and HUB_REF.conn and HUB_REF.conn.setWarping then
        pcall(HUB_REF.conn.setWarping, flag == true)
    end
end

local function warpToWorldInner(wName, doorID)
    wName = cleanWorldName(wName)
    doorID = cleanWorldName(doorID)
    if wName == "" then return false end
    if getCurrentWorldSafe() == wName and doorID == "" then applyCheats(); return true end

    if HUB_REF and HUB_REF.conn and HUB_REF.conn.isPlayerOnline and (not HUB_REF.conn.isPlayerOnline()) and (not HUB_REF.conn.isReconnecting()) then
        local okOn = HUB_REF.conn.ensureOnline({
            world = "",
            isRunning = isActive,
            onResume = applyCheats,
        })
        if not okOn then return false end
    end

    local joinStr = (doorID ~= "") and (wName .. "|" .. doorID) or wName
    DF.STATE.world_enter_public = nil
    for _ = 1, 3 do
        if not isActive() then return false end
        if sendPacket then
            pcall(sendPacket, 3, "action|join_request\nname|" .. joinStr .. "\ninvitedWorld|0\n")
        elseif growtopia and growtopia.warpTo then
            pcall(growtopia.warpTo, joinStr)
        end
        local w, lim = 0, math.max(4500, tonumber(DF.CFG.warp_delay) or 4500)
        while w < lim and isActive() do
            safeSleep(250); w = w + 250
            if getCurrentWorldSafe() == wName then
                safeSleep(650); applyCheats(); return true
            end
        end
    end
    local finalW = getCurrentWorldSafe()
    if finalW == wName then applyCheats(); return true end
    addLog(string.format("[Warp Info] Target: %s | World aktif: %s", wName, finalW ~= "" and finalW or "EXIT"))
    return false
end

local function warpToWorld(wName, doorID)
    setConnWarping(true)
    local ok = warpToWorldInner(wName, doorID)
    setConnWarping(false)
    return ok
end

-- Cek koneksi saat Dirt Farm berjalan: bila DC -> freeze total, fokus reconnect, lalu masuk ulang & lanjutkan!
local function ensureDFOnline(expectedWorld, expectedDoor)
    local conn = HUB_REF and HUB_REF.conn
    if not conn or not conn.ensureOnline then return true end
    local tw = cleanWorldName(expectedWorld or activeTargetWorld)
    local td = cleanWorldName(expectedDoor or activeTargetDoor)
    if not conn.needsReconnect(tw) then return true end
    DF.STATE.status_text = "RECONNECTING..."
    local okOn, didRec = conn.ensureOnline({
        world     = tw,
        door      = td,
        isRunning = isActive,
        onResume  = function()
            if not DF.STATE.in_storage then
                DF.STATE.anti_take_active = false
                applyCheats()
            end
        end,
        warpFn    = function(w, d) return warpToWorld(w, d) end,
    })
    if okOn and didRec and (not DF.STATE.in_storage) then
        DF.STATE.anti_take_active = false
        setAutoCollectActive(DF.CFG.auto_collect == true)
    end
    return okOn == true
end

local function rawAction(tx, ty, val)
    if not sendPacketRaw then return false end
    -- GUARD KERAS: Jangan pernah mengirim paket break/place saat Reconnect, masih di storage, atau salah world!
    if HUB_REF and HUB_REF.conn and HUB_REF.conn.STATE and HUB_REF.conn.STATE.reconnecting then return false end
    if DF.STATE.in_storage then return false end
    if activeTargetWorld ~= "" and getCurrentWorldSafe() ~= activeTargetWorld then return false end
    local p = getLocalSafe()
    local px = (p and (p.posX or (p.pos and p.pos.x))) or (tx * 32)
    local py = (p and (p.posY or (p.pos and p.pos.y))) or (ty * 32)
    return pcall(sendPacketRaw, false, {
        type = 3, value = val, px = tx, py = ty, x = px, y = py,
        state = (px > tx * 32) and 48 or 32,
    })
end

local dropExcessItemAtStorage -- forward declaration untuk stash overflow Dirt/Seed saat break

-- Tarik (vacuum) item/seed/gems di sekitar karakter dengan packet type=11 TANPA teleport ke objek!
local function collectNearbyFloating(centerX, centerY, customRadius, quickMode, forceCollect)
    if DF.STATE.anti_take_active or DF.STATE.in_storage then return 0 end
    if (not DF.CFG.auto_collect) and (not forceCollect) then return 0 end
    if not sendPacketRaw then return 0 end
    local px, py = getPlayerPos()
    local refX = px or centerX
    local refY = py or centerY
    if not refX or not refY then return 0 end
    local radius = math.max(2, tonumber(customRadius) or tonumber(DF.CFG.collect_range) or 3)
    local collected = 0
    local stashMap = DF.STATE.df_stash_spots or {}

    forEachWorldObject(function(itemid, uid, amt, oxPx, oyPx)
        if not DF.STATE.running then return end
        if itemid == ITEM.LAVA then return end
        local ox = math.floor((oxPx + 10) / 32)
        local oy = math.floor((oyPx + 10) / 32)
        if (not forceCollect) and stashMap[ox .. "," .. oy] then return end
        local distP = math.max(math.abs(ox - refX), math.abs(oy - refY))
        local distC = (centerX and centerY) and math.max(math.abs(ox - centerX), math.abs(oy - centerY)) or distP
        if (distP <= radius or distC <= radius) and (itemid == 112 or getInvCount(itemid) < 200) then
            -- Langsung kirim packet type=11 untuk menarik item dari tempat berdiri (JANGAN moveSafeTo/teleport!)
            pcall(sendPacketRaw, false, { type = 11, value = uid, x = oxPx, y = oyPx })
            if not quickMode then safeSleep(15) end
            collected = collected + 1
        end
    end)
    return collected
end

local function checkAutoTrash()
    local thresh = math.max(50, tonumber(DF.CFG.trash_thresh) or 180)
    -- Saat build_upper_dirt ON: bila Dirt Block / Dirt Seed penuh di tas (>= thresh), drop dulu di atas DF
    -- (bukan di-trash!) agar bisa dipungut lagi saat tahap pasang Dirt atas!
    if DF.CFG.build_upper_dirt and dropExcessItemAtStorage then
        local dCnt = getInvCount(ITEM.DIRT)
        local sCnt = getInvCount(ITEM.DIRT_SEED)
        if dCnt >= thresh or sCnt >= thresh then
            local retX, retY = getPlayerPos()
            if dCnt >= thresh then
                dropExcessItemAtStorage(ITEM.DIRT, 20, "Dirt Block (Stash DF)")
                local dx, dy = getPlayerPos()
                if dx and dy then
                    for ox = math.max(0, dx - 1), math.min(99, dx + 1) do
                        DF.STATE.df_stash_spots[ox .. "," .. dy] = true
                    end
                end
            end
            if sCnt >= thresh then
                dropExcessItemAtStorage(ITEM.DIRT_SEED, 20, "Dirt Seed (Stash DF)")
                local sx, sy = getPlayerPos()
                if sx and sy then
                    for ox = math.max(0, sx - 1), math.min(99, sx + 1) do
                        DF.STATE.df_stash_spots[ox .. "," .. sy] = true
                    end
                end
            end
            if retX and retY and isTileSafeToStand(retX, retY) then
                moveSafeTo(retX, retY)
            end
            DF.STATE.anti_take_active = false
            setAutoCollectActive(DF.CFG.auto_collect == true)
        end
    end

    if not DF.CFG.auto_trash or not sendPacket then return end
    local junks = getTrashList()
    if #junks == 0 then return end
    for _, jid in ipairs(junks) do
        -- Lindungi Dirt Block (2) & Dirt Seed (3) bila Build Dirt Atas ON (harus di-stash di DF, bukan di-trash)
        if not (DF.CFG.build_upper_dirt and (jid == ITEM.DIRT or jid == ITEM.DIRT_SEED)) then
            local cnt = getInvCount(jid)
            if cnt >= thresh then
                pcall(sendPacket, 2, "action|trash\n|itemID|" .. tostring(jid) .. "\n")
                safeSleep(280)
                pcall(sendPacket, 2, "action|dialog_return\ndialog_name|trash_item\nitemID|" .. tostring(jid) .. "|\ncount|" .. tostring(cnt) .. "\n")
                safeSleep(300)
            end
        end
    end
end

-- ============================================================================
-- 3. BREAK ENGINE (FG + CAVE BACKGROUND LAG-GUARD + MODE 3 TILE BREAK)
-- ============================================================================
local function isProtectedDoorArea(tx, ty, doorX, doorY)
    if DF.CFG.use_id_door and tx == 0 and ty == 0 then return true end
    if not doorX or not doorY then return false end
    if (tx == doorX and (ty == doorY or ty == doorY + 1 or ty == doorY - 1))
       or (tx == doorX + 1 and ty == doorY)
       or (tx == doorX - 1 and (ty == doorY or ty == doorY - 1)) then
        local t = getTileSafe(tx, ty)
        local fg = tonumber(t and t.fg) or 0
        if (tx == doorX and (ty == doorY or ty == doorY + 1)) or LOCK_IDS[fg] or fg == ITEM.JAMMER then
            return true
        end
        if DF.CFG.use_blocker_door and tx == doorX - 1 and ty == doorY and (fg == tonumber(DF.CFG.blocker_door_itemid) or DOOR_NAME_MAP[fg]) then
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
    for round = 1, 7 do
        if not isActive() then return false end
        if not ensureDFOnline(activeTargetWorld, activeTargetDoor) then return false end
        local t = getTileSafe(tx, ty)
        if not t then return false end

        local curId = isFgLayer and (tonumber(t.fg) or 0) or (tonumber(t.bg) or 0)
        if curId == 0 then return true end
        if isFgLayer and (not isTileClearableByBot(t)) then return true end

        -- Pastikan tidak berdiri TEPAT di atas tile target & berada dalam jangkauan <= 2 tile
        local px, py = getPlayerPos()
        if (not px) or (px == tx and py == ty) or math.abs(px - tx) > 2 or math.abs(py - ty) > 2 or (not isTileSafeToStand(px, py)) then
            moveAdjacentSafe(tx, ty, prefDir)
            safeSleep(60)
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

        local waitWin = (round == 1) and 220 or ((round == 2) and 300 or ((round == 3) and 380 or 450))
        if awaitTileLayerCleared(tx, ty, isFgLayer, waitWin) then
            return true
        end

        -- Jika lag/rubberband di ronde >= 2, re-posisi agar tidak memukul angin / out-of-range
        if round >= 2 then
            local altDir = (round % 2 == 0) and prefDir or (-(prefDir or 1))
            moveAdjacentSafe(tx, ty, altDir)
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
        collectNearbyFloating(tx, ty, DF.CFG.collect_range, true, false)
    end
    return fgDone and bgDone
end

-- Tunggu sinkronisasi server bahwa block/seed benar-benar sudah ter-put di tile target
local function awaitTilePlaced(tx, ty, itemID, maxWaitMs)
    local t = getTileSafe(tx, ty)
    if t and tonumber(t.fg) == itemID then return true end
    local waited = 0
    local lim = maxWaitMs or 220
    while isActive() and waited < lim do
        safeSleep(30); waited = waited + 30
        t = getTileSafe(tx, ty)
        if t and tonumber(t.fg) == itemID then return true end
    end
    return false
end

local function placeTileAt(tx, ty, itemID, prefDir)
    if tx < 0 or tx > 99 or ty < 0 or ty > 53 then return false end
    local t = getTileSafe(tx, ty)
    if not t then return false end
    if tonumber(t.fg) == itemID then return true end
    if getInvCount(itemID) <= 0 then return false end

    local pDelay = math.max(80, tonumber(DF.CFG.place_delay) or 160)
    local isSeed = (itemID == ITEM.DIRT_SEED or itemID == ITEM.CAVE_BG_SEED or itemID == ITEM.LAVA_SEED or itemID == ITEM.ROCK_SEED)

    for attempt = 1, 8 do
        if not isActive() then return false end
        if not ensureDFOnline(activeTargetWorld, activeTargetDoor) then return false end
        t = getTileSafe(tx, ty)
        if t and tonumber(t.fg) == itemID then return true end
        if getInvCount(itemID) <= 0 then return false end

        local px, py = getPlayerPos()
        local outOfRange = (not px) or math.abs(px - tx) > 2 or math.abs(py - ty) > 2
        local onTarget = (px == tx and py == ty)
        if outOfRange or ((not isSeed) and onTarget) or attempt >= 3 then
            local altDir = (attempt % 2 == 1) and prefDir or (-(prefDir or 1))
            moveAdjacentSafe(tx, ty, altDir)
            if attempt >= 3 then safeSleep(80) end
        end
        rawAction(tx, ty, itemID)
        safeSleep(pDelay)
        local waitWin = (attempt == 1) and 140 or ((attempt <= 3) and 220 or 320)
        if awaitTilePlaced(tx, ty, itemID, waitWin) then
            return true
        end
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
        safeSleep(45)
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
                    if (not DF.CFG.ignore_lock) and LOCK_IDS[fg] then
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
                    if (not DF.CFG.ignore_lock) and LOCK_IDS[fg] then
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
    if DF.CFG.ignore_lock then return end
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

-- ============================================================================
-- 4B. VALIDASI ALAT STORAGE (MASING-MASING 1) & DROP KELEBIHAN BACKPACK
-- ============================================================================
local function getRequiredDFKit()
    local kit = {}
    if DF.CFG.ignore_lock then
        -- Mode Ignore Lock: world sudah di-lock orang lain, bot tidak butuh alat lock/security
        return kit
    end
    local byId = {}
    local function addNeed(id, want, label)
        id = math.floor(tonumber(id) or 0)
        if id <= 0 then return end
        if byId[id] then
            byId[id].want = byId[id].want + want
        else
            local entry = { id = id, want = want, label = label }
            byId[id] = entry
            kit[#kit + 1] = entry
        end
    end
    if DF.CFG.auto_lock_wl then
        addNeed(ITEM.WORLD_LOCK, 1, "WL")
    end
    if DF.CFG.auto_place_jammer then
        addNeed(ITEM.JAMMER, 1, "Jammer")
    end
    if DF.CFG.auto_place_sl then
        addNeed(ITEM.SMALL_LOCK, 1, "SL")
    end
    if DF.CFG.use_blocker_door then
        local blkID = math.max(1, tonumber(DF.CFG.blocker_door_itemid) or 2810)
        addNeed(blkID, 1, "Blocker#" .. tostring(blkID))
    end
    if DF.CFG.use_id_door then
        local dID = math.max(1, tonumber(DF.CFG.id_door_itemid) or 12)
        addNeed(dID, 1, "Door#" .. tostring(dID))
    end
    return kit
end

local function inspectKitBackpack(kit)
    local missing, excess, summary = {}, {}, {}
    for _, it in ipairs(kit) do
        local cnt = getInvCount(it.id)
        summary[#summary + 1] = string.format("%s=%d/%d", it.label, cnt, it.want)
        if cnt < it.want then
            missing[#missing + 1] = it
        elseif cnt > it.want then
            excess[#excess + 1] = { id = it.id, want = it.want, have = cnt, label = it.label }
        end
    end
    return missing, excess, table.concat(summary, ", ")
end

-- Cari petak aman di area paling atas world storage (Y=1..2, gaya Lucifer)
local function findTopStorageDropTile(preferX)
    local baseX = math.max(2, math.min(97, math.floor(tonumber(preferX) or 50)))
    local function isFreeAir(tx, ty)
        if tx < 1 or tx > 98 or ty < 1 or ty > 5 then return false end
        if not isTileSafeToStand(tx, ty) then return false end
        local t = getTileSafe(tx, ty)
        if not t then return true end
        local fg = tonumber(t.fg) or 0
        return (fg == 0 or t.collidable ~= true)
    end
    for _, ty in ipairs({ 1, 2, 3 }) do
        for dx = 0, 48 do
            for _, sign in ipairs({ 1, -1 }) do
                if dx > 0 or sign == 1 then
                    local tx = baseX + (dx * sign)
                    if tx >= 2 and tx <= 97 and isFreeAir(tx, ty) and (isFreeAir(tx + 1, ty) or isFreeAir(tx - 1, ty)) then
                        return tx, ty
                    end
                end
            end
        end
    end
    return baseX, 1
end

local function moveToTopStorageDropArea(shiftOffset)
    if editToggle then pcall(editToggle, "ModFly", true) end
    local px, py = getPlayerPos()
    local prefX = (px and px >= 2 and px <= 97) and px or 50
    if shiftOffset and shiftOffset ~= 0 then
        prefX = math.max(2, math.min(97, prefX + shiftOffset))
    end
    if (not shiftOffset or shiftOffset == 0) and py and py >= 1 and py <= 2 then
        return px, py
    end
    local dx, dy = findTopStorageDropTile(prefX)
    DF.STATE.status_text = string.format("Terbang Drop Atas (%d,%d)...", dx, dy)
    moveSafeTo(dx, dy)
    safeSleep(220)
    return dx, dy
end

local function waitInvDropTo(itemID, targetMax, maxWaitMs)
    local waited = 0
    local lim = maxWaitMs or 1000
    while waited < lim and isActive() do
        safeSleep(80)
        waited = waited + 80
        if getInvCount(itemID) <= targetMax then
            return true
        end
    end
    return (getInvCount(itemID) <= targetMax)
end

-- Parse field OnDialogRequest asli Growtopia (support dialog_name "drop" & "drop_item", embed_data dinamis, & text input dinamis)
local function buildDropDialogReturn(dlgText, fallbackItemID, dropAmt)
    local dName = "drop_item"
    local embedLines = {}
    local hasItemEmbed = false
    local countField = "count"
    local foundInput = false

    if type(dlgText) == "string" and dlgText ~= "" then
        for line in dlgText:gmatch("[^\r\n]+") do
            local parts = {}
            for part in (line .. "|"):gmatch("([^|]*)|") do
                parts[#parts + 1] = part
            end
            local cmd = parts[1]
            if cmd == "end_dialog" and parts[2] and parts[2] ~= "" then
                dName = trimStr(parts[2])
            elseif cmd == "embed_data" and parts[2] and parts[2] ~= "" then
                local ek = trimStr(parts[2])
                local ev = trimStr(parts[3] or "")
                if ek:lower() == "itemid" or ek:lower() == "item_id" then hasItemEmbed = true end
                embedLines[#embedLines + 1] = ek .. "|" .. ev .. "|"
            elseif cmd == "add_text_input" and parts[2] and parts[2] ~= "" and (not foundInput) then
                countField = trimStr(parts[2])
                foundInput = true
            end
        end
    end

    local lines = {
        "action|dialog_return",
        "dialog_name|" .. dName,
    }
    for _, el in ipairs(embedLines) do
        lines[#lines + 1] = el
    end
    if not hasItemEmbed then
        lines[#lines + 1] = "itemID|" .. tostring(fallbackItemID) .. "|"
    end
    lines[#lines + 1] = countField .. "|" .. tostring(dropAmt)
    return table.concat(lines, "\n") .. "\n"
end

-- Drop kelebihan item di area paling atas Storage/DF (Y=1..2, gaya Lucifer) hingga tersisa TEPAT keepAmt
dropExcessItemAtStorage = function(itemID, keepAmt, label)
    itemID = math.floor(tonumber(itemID) or 0)
    keepAmt = math.max(0, math.floor(tonumber(keepAmt) or 1))
    if itemID <= 0 then return true end

    local cur = getInvCount(itemID)
    if cur <= keepAmt then return true end

    DF.STATE.anti_take_active = true
    setAutoCollectActive(false)
    if editToggle then pcall(editToggle, "ModFly", true) end
    safeSleep(180)

    -- Terbang ke baris paling atas storage (Y=1..2) SEBELUM mulai drop!
    moveToTopStorageDropArea(0)

    for attempt = 1, 3 do
        if not isActive() then return false end
        cur = getInvCount(itemID)
        if cur <= keepAmt then return true end
        local excess = cur - keepAmt

        -- Bila tile atas penuh pada percobaan ulang, geser menyamping tetap di baris atas (Y=1..2)
        if attempt > 1 then
            local shift = (attempt == 2) and 2 or -2
            moveToTopStorageDropArea(shift)
        end

        DF.STATE.pending_drop_id  = itemID
        DF.STATE.pending_drop_amt = excess
        DF.STATE.drop_confirmed   = false
        DF.STATE.status_text = string.format("Drop Atas %s (%d)...", tostring(label or itemID), excess)
        addLog(string.format("[Storage Drop Atas #%d] %s (ID %d): drop %d (tas %d -> target %d)",
            attempt, tostring(label or itemID), itemID, excess, cur, keepAmt))

        local okDropped = false

        -- Metode 1: API Native GrowLauncher confirmDropItem (TANPA elseif agar selalu jatuh ke fallback bila gagal!)
        if growtopia and growtopia.confirmDropItem then
            pcall(growtopia.confirmDropItem, itemID, excess)
            okDropped = waitInvDropTo(itemID, keepAmt, 950)
        end

        -- Metode 2: Packet standar action|drop -> ditangkap OnDialogRequest oleh DF.handleVariant!
        if (not okDropped) and isActive() and sendPacket then
            DF.STATE.drop_confirmed = false
            pcall(sendPacket, 2, "action|drop\n|itemID|" .. tostring(itemID))
            okDropped = waitInvDropTo(itemID, keepAmt, 1000)
        end

        -- Metode 3: API Native growtopia.dropItem (memicu OnDialogRequest -> DF.handleVariant)
        if (not okDropped) and isActive() and growtopia and growtopia.dropItem then
            DF.STATE.drop_confirmed = false
            pcall(growtopia.dropItem, itemID)
            okDropped = waitInvDropTo(itemID, keepAmt, 900)
        end

        -- Metode 4: Direct dialog_return untuk KEDUA nama dialog Growtopia ("drop_item" & "drop")
        if (not okDropped) and isActive() and sendPacket then
            for _, dlgName in ipairs({ "drop_item", "drop" }) do
                if not isActive() then break end
                local remNow = getInvCount(itemID) - keepAmt
                if remNow <= 0 then okDropped = true; break end
                pcall(sendPacket, 2, string.format(
                    "action|dialog_return\ndialog_name|%s\nitemID|%d|\ncount|%d\n",
                    dlgName, itemID, remNow
                ))
                if waitInvDropTo(itemID, keepAmt, 750) then
                    okDropped = true
                    break
                end
            end
        end

        DF.STATE.pending_drop_id  = 0
        DF.STATE.pending_drop_amt = 0
        if okDropped or getInvCount(itemID) <= keepAmt then
            addLog(string.format("[Storage Drop OK] %s tersisa %d di tas.", tostring(label or itemID), getInvCount(itemID)))
            return true
        end
        safeSleep(250)
    end

    return (getInvCount(itemID) <= keepAmt)
end

-- Ambil alat yang kurang di Storage, drop SEMUA kelebihan hingga masing-masing 1,
-- dan validasi 100% lengkap sebelum boleh find world / masuk DF / break dirt!
local function prepareAndValidateDFKit()
    local kit = getRequiredDFKit()
    if #kit == 0 then return true end

    local missing, excess, summary = inspectKitBackpack(kit)
    if #missing == 0 and #excess == 0 then
        addLog("[DF Kit] Validasi OK (" .. summary .. "). Lanjut!")
        return true
    end

    local storages = getStorageList()
    if #storages == 0 then
        if #missing > 0 then
            local mNames = {}
            for _, it in ipairs(missing) do mNames[#mNames + 1] = it.label end
            addLog("[DF Kit] Alat kurang (" .. table.concat(mNames, ", ") .. ") & Storage belum diisi!")
            DF.STATE.status_text = "Alat Kurang!"
            return false
        end
        addLog("[DF Kit] Semua alat ada (" .. summary .. "), Storage kosong untuk drop kelebihan.")
        return true
    end

    -- KUNCI in_storage = true selama di storage -> rawAction() 100% memblokir break dirt!
    DF.STATE.in_storage = true
    activeTargetWorld = ""
    DF.STATE.status_text = "Ambil Alat Storage..."

    local enteredAnyStorage = false
    for _, st in ipairs(storages) do
        if not isActive() then
            DF.STATE.in_storage = false
            return false
        end
        missing, excess = inspectKitBackpack(kit)
        if #missing == 0 and #excess == 0 then break end

        addLog(string.format("[DF Storage] Masuk storage %s untuk ambil & rapikan alat...", st.name))
        if warpToWorld(st.name, st.door) then
            enteredAnyStorage = true
            safeSleep(650)

            -- FASE A: Ambil hanya item yang masih kurang (< want)
            missing = inspectKitBackpack(kit)
            if #missing > 0 then
                DF.STATE.anti_take_active = false
                if editToggle then
                    pcall(editToggle, "Anti Collect", false)
                    pcall(editToggle, "Auto Collect", true)
                end
                safeSleep(150)

                for _, it in ipairs(missing) do
                    if not isActive() then break end
                    if getInvCount(it.id) < it.want then
                        DF.STATE.status_text = "Ambil " .. it.label .. "..."
                        local grabbed = false
                        forEachWorldObject(function(oid, uid, amt, rx, ry)
                            if grabbed or (not isActive()) or getInvCount(it.id) >= it.want then return end
                            if oid == it.id then
                                moveSafeTo(math.floor((rx + 10) / 32), math.floor((ry + 10) / 32))
                                if sendPacketRaw then
                                    pcall(sendPacketRaw, false, { type = 11, value = uid, x = rx, y = ry })
                                end
                                -- Tunggu sync tas hingga terdeteksi masuk (maks 1.6 detik)
                                local sw = 0
                                while sw < 1600 and isActive() do
                                    safeSleep(150); sw = sw + 150
                                    if getInvCount(it.id) >= it.want then grabbed = true; break end
                                end
                            end
                        end)
                    end
                end
            end

            -- FASE B: AKTIFKAN ANTI-TAKE & DROP SEMUA KELEBIHAN ALAT DI STORAGE (sisakan masing-masing 1!)
            DF.STATE.anti_take_active = true
            if editToggle then
                pcall(editToggle, "Auto Collect", false)
                pcall(editToggle, "Anti Collect", true)
            end
            safeSleep(350)

            for pass = 1, 2 do
                local _, curExcess = inspectKitBackpack(kit)
                if #curExcess == 0 then break end
                for _, ex in ipairs(curExcess) do
                    if not isActive() then break end
                    dropExcessItemAtStorage(ex.id, ex.want, ex.label)
                end
                safeSleep(350)
            end

            missing, excess = inspectKitBackpack(kit)
            if #missing == 0 and #excess == 0 then break end
        end
    end

    -- FASE C: VALIDASI KETAT SEBELUM BOLEH KELUAR STORAGE / FIND WORLD / BREAK DIRT!
    safeSleep(350)
    missing, excess, summary = inspectKitBackpack(kit)
    DF.STATE.in_storage = false

    if #missing > 0 then
        local mNames = {}
        for _, it in ipairs(missing) do mNames[#mNames + 1] = string.format("%s(%d/%d)", it.label, getInvCount(it.id), it.want) end
        addLog("[DF Kit GAGAL] Alat belum lengkap di storage: " .. table.concat(mNames, ", ") .. " — tidak jadi lanjut!")
        DF.STATE.status_text = "Alat Kurang"
        DF.STATE.anti_take_active = false
        return false
    end

    if #excess > 0 then
        local eNames = {}
        for _, ex in ipairs(excess) do eNames[#eNames + 1] = string.format("%s(%d>%d)", ex.label, ex.have, ex.want) end
        addLog("[DF Kit GAGAL] Gagal drop kelebihan di storage: " .. table.concat(eNames, ", ") .. " — cek posisi drop storage!")
        DF.STATE.status_text = "Drop Kelebihan Gagal"
        DF.STATE.anti_take_active = false
        return false
    end

    -- Pertahankan anti_take_active = true sampai bot benar-benar warp keluar dari storage!
    if not enteredAnyStorage then DF.STATE.anti_take_active = false end
    addLog("`2[DF Kit OK] Validasi lengkap & kelebihan sudah di-drop (" .. summary .. "). Siap jalan!")
    return true
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
            DF.STATE.in_storage = false
            DF.STATE.anti_take_active = false
            activeTargetWorld = cleanWorldName(cand)
            setAutoCollectActive(DF.CFG.auto_collect == true)
            safeSleep(700)
            local okFree, reason, dx, dy = isCurrentWorldFreeForDF()
            if okFree then
                addLog("`2[Find World] Ketemu world kosong: " .. cand .. "!")
                if not DF.CFG.ignore_lock then
                    autoSetupLockAndJammer(dx, dy)
                end
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
            if #getStorageList() > 0 then
                if not prepareAndValidateDFKit() then
                    uiNotice = "Alat storage belum lengkap / gagal drop kelebihan!"
                    DF.STATE.status_text = "Kit Belum Siap"
                    return
                end
            end
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
        DF.STATE.in_storage = false
        DF.STATE.anti_take_active = false
        activeTargetWorld = ""
        DF.STATE.finding_one = false
    end
    if runCoroutine then pcall(runCoroutine, runner)
    else coroutine.resume(coroutine.create(runner)) end
end

-- ============================================================================
-- 5. RESTOCK STORAGE, AUTO FARM DIRT & MAIN DIRT FARM PIPELINE
-- ============================================================================
local function restockItem(farmRow, itemID, wantAmt, exactCap)
    local minHave = exactCap and exactCap or 5
    if getInvCount(itemID) >= minHave and ((not exactCap) or getInvCount(itemID) <= exactCap) then
        return true
    end
    local storages = getStorageList()
    if #storages == 0 then
        addLog("[DF] Stok item ID " .. tostring(itemID) .. " habis & Storage kosong!")
        return false
    end

    local prevTarget = activeTargetWorld
    DF.STATE.in_storage = true
    activeTargetWorld = ""

    local gotItem = false
    for _, st in ipairs(storages) do
        if not DF.STATE.running then break end
        if warpToWorld(st.name, st.door) then
            safeSleep(650)
            if getInvCount(itemID) < (exactCap or wantAmt or 1) then
                DF.STATE.anti_take_active = false
                if editToggle then
                    pcall(editToggle, "Anti Collect", false)
                    pcall(editToggle, "Auto Collect", true)
                end
                forEachWorldObject(function(oid, uid, amt, rx, ry)
                    if not DF.STATE.running or getInvCount(itemID) >= (exactCap or wantAmt or 120) then return end
                    if oid == itemID then
                        moveSafeTo(math.floor((rx + 10) / 32), math.floor((ry + 10) / 32))
                        if sendPacketRaw then
                            pcall(sendPacketRaw, false, { type = 11, value = uid, x = rx, y = ry })
                        end
                        local sw = 0
                        while sw < 1400 and DF.STATE.running do
                            safeSleep(150); sw = sw + 150
                            if getInvCount(itemID) >= (exactCap or 1) then break end
                        end
                    end
                end)
            end

            -- Bila butuh jumlah pas (misal exactCap = 1 untuk alat), drop kelebihannya SEBELUM keluar storage!
            if exactCap and getInvCount(itemID) > exactCap then
                dropExcessItemAtStorage(itemID, exactCap, "Item#" .. tostring(itemID))
            end

            if getInvCount(itemID) >= 1 and ((not exactCap) or getInvCount(itemID) <= exactCap) then
                gotItem = true
                break
            end
        end
    end

    DF.STATE.in_storage = false
    if gotItem then
        local okBack = warpToWorld(farmRow.name, farmRow.door)
        DF.STATE.anti_take_active = false
        if okBack then
            activeTargetWorld = cleanWorldName(farmRow.name)
            setAutoCollectActive(DF.CFG.auto_collect == true)
            return true
        end
    end

    -- Pastikan TIDAK pernah diam di storage sambil mengembalikan kontrol ke break loop!
    DF.STATE.anti_take_active = false
    setAutoCollectActive(DF.CFG.auto_collect == true)
    activeTargetWorld = prevTarget
    return false
end

-- Pungut stok item tertentu (misal Dirt Block ID 2 atau Dirt Seed ID 3) yang ter-drop di dalam world DF saat ini
local function collectFloatingItemInDF(targetID, stopAtAmt)
    local lim = stopAtAmt or 185
    if getInvCount(targetID) >= lim then return getInvCount(targetID), true end

    DF.STATE.anti_take_active = false
    setAutoCollectActive(true)

    local targets = {}
    forEachWorldObject(function(oid, uid, amt, rx, ry)
        if oid == targetID then
            targets[#targets + 1] = { uid = uid, amt = amt, rx = rx, ry = ry, tx = math.floor((rx + 10) / 32), ty = math.floor((ry + 10) / 32) }
        end
    end)
    if #targets == 0 then
        return getInvCount(targetID), false
    end

    local foundAny = false
    for _, obj in ipairs(targets) do
        if not DF.STATE.running then break end
        if getInvCount(targetID) >= lim then break end
        foundAny = true
        local px, py = getPlayerPos()
        if (not px) or math.max(math.abs(obj.tx - px), math.abs(obj.ty - py)) > 2 then
            if isTileSafeToStand(obj.tx, obj.ty) then
                moveSafeTo(obj.tx, obj.ty)
            else
                moveAdjacentSafe(obj.tx, obj.ty, 1)
            end
        end
        if sendPacketRaw then
            pcall(sendPacketRaw, false, { type = 11, value = obj.uid, x = obj.rx, y = obj.ry })
        end
        safeSleep(140)
    end
    safeSleep(180)
    return getInvCount(targetID), foundAny
end

-- Simpan sisa Dirt Block (2) & Dirt Seed (3) ke daftar Storage Seed / Save World bila diisi; bila kosong biarkan di Dirt Farm!
-- Simpan sisa item Save Seed (Dirt Seed 3, Dirt 2, dll) ke daftar Storage Seed / Save World bila diisi; bila kosong biarkan di Dirt Farm!
local function saveLeftoverDirtToSaveWorld(farmRow)
    local allSaves = getSaveWorldList()
    local saveList = {}
    local farmName = cleanWorldName(farmRow.name)
    for _, sw in ipairs(allSaves) do
        if sw and sw.name ~= "" and cleanWorldName(sw.name) ~= farmName then
            table.insert(saveList, sw)
        end
    end
    if #saveList == 0 then
        addLog("[DF] Storage Seed / Save World kosong — sisa item Save Seed dibiarkan di Dirt Farm.")
        return true
    end

    local saveItems = getSaveSeedList()
    if #saveItems == 0 then saveItems = { 3, 2 } end

    DF.STATE.df_stash_spots = {}
    farmRow.status = "Save Sisa Dirt..."
    local saveIdx = 1

    for trip = 1, 6 do
        if not DF.STATE.running then return false end
        if saveIdx > #saveList then break end

        -- 1. Pastikan sedang di world DF untuk menyapu item Save Seed di lantai/atas DF
        if getCurrentWorldSafe() ~= farmName then
            if not warpToWorld(farmRow.name, farmRow.door) then break end
            DF.STATE.in_storage = false
            DF.STATE.anti_take_active = false
            setAutoCollectActive(true)
            safeSleep(450)
        end

        for _, itmId in ipairs(saveItems) do
            collectFloatingItemInDF(itmId, 195)
        end

        -- Cek apakah masih ada sisa floating di DF yang tidak muat 1 tas
        local saveItemSet = {}
        for _, itmId in ipairs(saveItems) do saveItemSet[itmId] = true end
        local moreFloatingInDF = false
        forEachWorldObject(function(oid)
            if saveItemSet[oid] then moreFloatingInDF = true end
        end)

        local totalToSave = 0
        for _, itmId in ipairs(saveItems) do
            totalToSave = totalToSave + getInvCount(itmId)
        end
        if totalToSave <= 0 then
            break
        end

        -- 2. Warp ke Save World di daftar (otomatis pindah ke world berikut bila gagal masuk / penuh)
        local droppedAll = false
        while saveIdx <= #saveList and DF.STATE.running do
            local target = saveList[saveIdx]
            DF.STATE.status_text = "Save -> " .. target.name
            addLog(string.format("[DF Save #%d] Menyimpan sisa item ke %s (total %d item di tas)...", trip, target.name, totalToSave))
            DF.STATE.in_storage = true
            activeTargetWorld = ""
            if warpToWorld(target.name, target.door) then
                safeSleep(600)
                for _, itmId in ipairs(saveItems) do
                    if getInvCount(itmId) > 0 then
                        dropExcessItemAtStorage(itmId, 0, "Sisa " .. resolveDoorItemName(itmId))
                    end
                end
                DF.STATE.in_storage = false
                local remCnt = 0
                for _, itmId in ipairs(saveItems) do
                    remCnt = remCnt + getInvCount(itmId)
                end
                if remCnt <= 0 then
                    droppedAll = true
                    break
                else
                    addLog("[DF Save] " .. target.name .. " penuh/gagal drop penuh — coba Save World berikutnya...")
                    saveIdx = saveIdx + 1
                end
            else
                DF.STATE.in_storage = false
                addLog("[DF Save] Gagal masuk " .. target.name .. " — coba Save World berikutnya...")
                saveIdx = saveIdx + 1
            end
        end

        if not droppedAll then
            addLog("[DF Save] Semua Storage Seed gagal dimasuki/penuh, sisa item dibiarkan.")
            break
        end
        if not moreFloatingInDF then
            break
        end
    end

    DF.STATE.in_storage = false
    DF.STATE.anti_take_active = false
    setAutoCollectActive(DF.CFG.auto_collect == true)
    addLog("[DF Save] Sisa item Save Seed selesai disimpan ke Storage Seed!")
    return true
end

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

    -- 2. Bila Dirt Seed di tas 0, pungut dulu Dirt Seed yang ter-drop di world DF!
    if getInvCount(ITEM.DIRT_SEED) <= 0 then
        collectFloatingItemInDF(ITEM.DIRT_SEED, 180)
    end

    -- 3. Tanam sampai 40 Dirt Seed di Y=23 bila punya seed
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

local function resolveDoorItemName(id)
    id = tonumber(id) or 0
    if id <= 0 then return "None" end
    if TRASH_ITEM_NAME_MAP[id] then return TRASH_ITEM_NAME_MAP[id] end
    if DOOR_NAME_MAP[id] then return DOOR_NAME_MAP[id] end
    if PLATFORM_NAME_MAP[id] then return PLATFORM_NAME_MAP[id] end
    if HUB_REF and HUB_REF.item_db and type(HUB_REF.item_db.resolveName) == "function" then
        local nm = HUB_REF.item_db.resolveName(id)
        if nm and nm ~= "" then return nm end
    end
    if getItemInfoByID then
        local ok, info = pcall(getItemInfoByID, id)
        if ok and info and type(info.name) == "string" and info.name ~= "" then return info.name end
    end
    return "Item #" .. tostring(id)
end

-- Periksa apakah cluster lock & Door ID di world saat ini sudah terpasang di posisi yang benar
local function inspectWorldSecurityState(doorX, doorY)
    local blkID = math.max(1, tonumber(DF.CFG.blocker_door_itemid) or 2810)
    local dItem = math.max(1, tonumber(DF.CFG.id_door_itemid) or 12)
    local st = {
        hasBlk = true, hasJam = true, hasWL = true, hasSL = true, hasDoor = true,
        clusterComplete = true,
    }
    if doorX and doorY then
        if DF.CFG.use_blocker_door and doorX - 1 >= 0 then
            local fg = tonumber((getTileSafe(doorX - 1, doorY) or {}).fg) or 0
            st.hasBlk = (fg == blkID or DOOR_NAME_MAP[fg] ~= nil)
        end
        if DF.CFG.auto_place_jammer and doorX - 1 >= 0 and doorY - 1 >= 0 then
            local fg = tonumber((getTileSafe(doorX - 1, doorY - 1) or {}).fg) or 0
            st.hasJam = (fg == ITEM.JAMMER)
        end
        if DF.CFG.auto_lock_wl and doorX + 1 <= 99 then
            local fg = tonumber((getTileSafe(doorX + 1, doorY) or {}).fg) or 0
            st.hasWL = (fg == ITEM.WORLD_LOCK)
        end
        if DF.CFG.auto_place_sl and doorY - 1 >= 0 then
            local fg = tonumber((getTileSafe(doorX, doorY - 1) or {}).fg) or 0
            st.hasSL = (fg == ITEM.SMALL_LOCK)
        end
    end
    if DF.CFG.use_id_door then
        local fg0 = tonumber((getTileSafe(0, 0) or {}).fg) or 0
        st.hasDoor = (fg0 == dItem or DOOR_NAME_MAP[fg0] ~= nil)
    end
    st.clusterComplete = st.hasBlk and st.hasJam and st.hasWL and st.hasSL
    return st
end

-- Stage 0: Smart Skip Lock (jika posisi lock sudah benar -> skip buat ulang lock, cukup cek Door ID!)
local function setupWorldSecurity(row, doorX, doorY)
    if not doorX or not doorY then return true end
    if DF.CFG.ignore_lock then
        addLog("[DF] Ignore Lock AKTIF: Melewati setup security & lock, langsung proses pembuatan Dirt Farm!")
        return true
    end
    local needAny = DF.CFG.use_blocker_door or DF.CFG.auto_place_jammer or DF.CFG.auto_lock_wl or DF.CFG.auto_place_sl or DF.CFG.use_id_door
    if not needAny then return true end

    local blkID = math.max(1, tonumber(DF.CFG.blocker_door_itemid) or 2810)
    local sec = inspectWorldSecurityState(doorX, doorY)

    local function isKeptClusterTile(tx, ty)
        if tx == doorX and (ty == doorY or ty == doorY + 1) then return true end -- White Door & Bedrock
        local t = getTileSafe(tx, ty)
        local fg = tonumber(t and t.fg) or 0
        if tx == doorX - 1 and ty == doorY and (fg == blkID or DOOR_NAME_MAP[fg]) then return true end
        if tx == doorX - 1 and ty == doorY - 1 and fg == ITEM.JAMMER then return true end
        if tx == doorX + 1 and ty == doorY and fg == ITEM.WORLD_LOCK then return true end
        if tx == doorX and ty == doorY - 1 and fg == ITEM.SMALL_LOCK then return true end
        return false
    end

    local function ensureAndPlace(tx, ty, itemID, prefDir, label, acceptAnyDoor)
        if tx < 0 or tx > 99 or ty < 0 or ty > 53 then return false, false end
        if getCurrentWorldSafe() ~= cleanWorldName(row.name) then
            if not warpToWorld(row.name, row.door) then return false, false end
            safeSleep(450)
        end
        local t = getTileSafe(tx, ty)
        local curFg = tonumber(t and t.fg) or 0
        if curFg == itemID or (acceptAnyDoor and DOOR_NAME_MAP[curFg]) then
            return true, true -- alreadyPresent = true
        end
        if getInvCount(itemID) <= 0 then
            if not restockItem(row, itemID, 1, 1) then
                addLog("[Lock/Door] Stok " .. label .. " (ID " .. tostring(itemID) .. ") habis!")
                return false, false
            end
            if getCurrentWorldSafe() ~= cleanWorldName(row.name) then return false, false end
            t = getTileSafe(tx, ty)
            curFg = tonumber(t and t.fg) or 0
            if curFg == itemID or (acceptAnyDoor and DOOR_NAME_MAP[curFg]) then
                return true, true
            end
        end
        if t and ((curFg ~= 0 and isTileClearableByBot(t)) or (tonumber(t.bg) or 0) ~= 0) then
            breakTileCompletely(tx, ty, curFg ~= 0, (tonumber(t.bg) or 0) ~= 0, prefDir, true)
        end
        local okP = placeTileAt(tx, ty, itemID, prefDir)
        if okP then addLog(string.format("[Lock/Door] %s (ID %d) terpasang di (%d,%d)", label, itemID, tx, ty)) end
        return okP, false
    end

    -- Cek bit flag Growtopia TILE_FLAG_PUBLIC (0x80 = 128) langsung dari tile di memori (0 paket, 0 wrench!)
    local function isTilePublicFlag(t)
        if not t then return false, false end
        if type(t.isPublic) == "boolean" then
            return t.isPublic, true
        end
        local fl = tonumber(t.flags)
        if fl == nil then fl = tonumber(t.flag) end
        if fl ~= nil then
            return (math.floor(fl / 128) % 2 == 1), true
        end
        return false, false
    end

    local wlNewlyPlaced = false

    if sec.clusterComplete then
        addLog("[Lock/Door] Posisi lock sudah benar — skip buat ulang lock, lanjut cek Door ID.")
    else
        row.status = "Setup Lock/Door"
        DF.STATE.status_text = row.name .. " Setup Lock"

        -- 0A. Break Dirt & Cave BG Moat HANYA jika Small Lock belum terpasang (agar tidak merusak/mengulang lock yg sudah jadi!)
        if DF.CFG.auto_place_sl and (not sec.hasSL) then
            DF.STATE.status_text = row.name .. " Break Moat"
            addLog(string.format("[Lock/Door] Break dirt & Cave BG area Moat sekitar Main Door (%d,%d)...", doorX, doorY))
            for pass = 1, 2 do
                local brokeAny = false
                for my = doorY - 2, doorY + 2 do
                    for mx = doorX - 2, doorX + 2 do
                        if not DF.STATE.running then return end
                        local isOuterRing    = (math.abs(mx - doorX) == 2 or math.abs(my - doorY) == 2)
                        local isLeftBedrock  = (mx == doorX - 1 and my == doorY + 1)
                        local isRightAboveWL = (mx == doorX + 1 and my == doorY - 1)
                        local isRightBelowWL = (mx == doorX + 1 and my == doorY + 1)
                        if (isOuterRing or isLeftBedrock or isRightAboveWL or isRightBelowWL)
                            and mx >= 0 and mx <= 99 and my >= 0 and my <= 53
                            and (not isKeptClusterTile(mx, my))
                        then
                            local t = getTileSafe(mx, my)
                            local fg = tonumber(t and t.fg) or 0
                            local bg = tonumber(t and t.bg) or 0
                            local needFg = (fg ~= 0 and isTileClearableByBot(t))
                            local needBg = (bg ~= 0)
                            if needFg or needBg then
                                brokeAny = true
                                local prefDir = (mx <= doorX) and -1 or 1
                                breakTileCompletely(mx, my, needFg, needBg, prefDir, true)
                            end
                        end
                    end
                end
                if not brokeAny then break end
                safeSleep(120)
            end
        end

        -- 0B. Bersihkan FG & Cave BG HANYA pada slot cluster yang belum terisi item target
        local clusterSlots = {
            { x = doorX - 1, y = doorY,     id = blkID,           dir = -1, enabled = DF.CFG.use_blocker_door and (not sec.hasBlk) },
            { x = doorX - 1, y = doorY - 1, id = ITEM.JAMMER,     dir = -1, enabled = DF.CFG.auto_place_jammer and (not sec.hasJam) },
            { x = doorX + 1, y = doorY,     id = ITEM.WORLD_LOCK, dir =  1, enabled = DF.CFG.auto_lock_wl and (not sec.hasWL) },
            { x = doorX,     y = doorY - 1, id = ITEM.SMALL_LOCK, dir =  1, enabled = DF.CFG.auto_place_sl and (not sec.hasSL) },
        }
        for _, sl in ipairs(clusterSlots) do
            if sl.enabled and sl.x >= 0 and sl.x <= 99 and sl.y >= 0 and sl.y <= 53 then
                local t = getTileSafe(sl.x, sl.y)
                if t and tonumber(t.fg) ~= sl.id then
                    local needFg = ((tonumber(t.fg) or 0) ~= 0 and isTileClearableByBot(t))
                    local needBg = ((tonumber(t.bg) or 0) ~= 0)
                    if needFg or needBg then
                        breakTileCompletely(sl.x, sl.y, needFg, needBg, sl.dir, true)
                    end
                end
            end
        end

        DF.STATE.status_text = row.name .. " Lock/Door"

        -- 1. Penghalang Kiri (Blocker) di (doorX - 1, doorY) — hanya jika belum terpasang
        if DF.CFG.use_blocker_door and (not sec.hasBlk) and doorX - 1 >= 0 then
            ensureAndPlace(doorX - 1, doorY, blkID, -1, "Penghalang " .. resolveDoorItemName(blkID), true)
        end

        -- 2. Signal Jammer (226) di (doorX - 1, doorY - 1) — hanya jika belum terpasang
        if DF.CFG.auto_place_jammer and (not sec.hasJam) and doorX - 1 >= 0 and doorY - 1 >= 0 then
            local okJam, alreadyJam = ensureAndPlace(doorX - 1, doorY - 1, ITEM.JAMMER, -1, "Signal Jammer", false)
            if okJam and (not alreadyJam) then
                safeSleep(250)
                rawAction(doorX - 1, doorY - 1, ITEM.PUNCH)
                safeSleep(250)
            end
        end

        -- 3. World Lock (242) di (doorX + 1, doorY)
        if DF.CFG.auto_lock_wl and (not sec.hasWL) and doorX + 1 <= 99 then
            local okWL, alreadyWL = ensureAndPlace(doorX + 1, doorY, ITEM.WORLD_LOCK, 1, "World Lock", false)
            if okWL and (not alreadyWL) then
                wlNewlyPlaced = true
                DF.STATE.world_enter_public = false
            end
        end

        -- 4. Small Lock (202) di atas White Door (doorX, doorY - 1) — hanya 2-Step Apply jika baru dipasang!
        if DF.CFG.auto_place_sl and (not sec.hasSL) and doorY - 1 >= 0 then
            if doorY - 2 >= 0 then
                local tTop = getTileSafe(doorX, doorY - 2)
                if tTop and ((tonumber(tTop.fg) or 0) ~= 0 or (tonumber(tTop.bg) or 0) ~= 0) then
                    breakTileCompletely(doorX, doorY - 2, true, true, 1, true)
                end
            end
            local okSL, alreadySL = ensureAndPlace(doorX, doorY - 1, ITEM.SMALL_LOCK, 1, "Small Lock", false)
            if okSL and (not alreadySL) and sendPacket then
                local standY = math.max(0, doorY - 2)
                moveSafeTo(doorX, standY)
                safeSleep(220)

                -- Step 1: Simpan Private (0) + Ignore Empty Air (1) terlebih dahulu!
                rawAction(doorX, doorY - 1, ITEM.WRENCH)
                safeSleep(380)
                pcall(sendPacket, 2, string.format(
                    "action|dialog_return\ndialog_name|lock_edit\ntilex|%d|\ntiley|%d|\ncheckbox_public|0\ncheckbox_ignore|1\ncheckbox_ignore_air|1\n",
                    doorX, doorY - 1
                ))
                safeSleep(480)

                -- Step 2: Wrench lagi & tekan Re-apply Lock (recalcLock) dengan Ignore Empty Air = ON!
                rawAction(doorX, doorY - 1, ITEM.WRENCH)
                safeSleep(380)
                pcall(sendPacket, 2, string.format(
                    "action|dialog_return\ndialog_name|lock_edit\ntilex|%d|\ntiley|%d|\nbuttonClicked|recalcLock\ncheckbox_public|0\ncheckbox_ignore|1\ncheckbox_ignore_air|1\n",
                    doorX, doorY - 1
                ))
                safeSleep(550)
                addLog("[Lock/Door] Small Lock (202) Private + Ignore Air + Re-apply Lock selesai rapi!")
            end
        end
    end

    -- 4.5. PASTIKAN WORLD LOCK (242) = "Allow anyone to Build and Break" (0 WRENCH JIKA SUDAH PUBLIC!)
    -- Lapis 1: Cek bit flag tile WL (flags bit 0x80 = 128) langsung dari memori (0 wrench!)
    -- Lapis 2: Cek status world saat masuk (OnConsoleMessage [OPEN] / open to the public -> 0 wrench!)
    -- Lapis 3: Hanya wrench & set dinamis jika WL baru dipasang ATAU memang terdeteksi masih Private!
    if DF.CFG.auto_lock_wl and DF.CFG.wl_public and doorX + 1 <= 99 and sendPacket then
        local wlX, wlY = doorX + 1, doorY
        local tWL = getTileSafe(wlX, wlY)
        if tWL and tonumber(tWL.fg) == ITEM.WORLD_LOCK then
            local flagPub, hasFlag = isTilePublicFlag(tWL)
            local msgPub = DF.STATE.world_enter_public

            if (not wlNewlyPlaced) and (flagPub or msgPub == true) then
                addLog("[Lock/Door] World Lock (242) sudah Public (status world/flag 0x80) — skip 0 wrench!")
            else
                if wlNewlyPlaced then safeSleep(500) end
                local appliedWL = false
                for attempt = 1, 3 do
                    if not DF.STATE.running then break end
                    -- Cek cepat via tile flag sebelum wrench ulang
                    local fNow, hasFNow = isTilePublicFlag(getTileSafe(wlX, wlY))
                    if appliedWL and hasFNow and fNow then
                        DF.STATE.world_enter_public = true
                        addLog("[Lock/Door] World Lock (242) terverifikasi Public via tile flag (0x80)!")
                        break
                    end

                    moveAdjacentSafe(wlX, wlY, 1)
                    safeSleep(220)

                    DF.STATE.checking_wl_edit   = true
                    DF.STATE.wl_edit_seen       = false
                    DF.STATE.wl_edit_is_public  = false
                    DF.STATE.wl_edit_return_pkt = ""

                    rawAction(wlX, wlY, ITEM.WRENCH)
                    local w = 0
                    while w < 1300 and isActive() and (not DF.STATE.wl_edit_seen) do
                        safeSleep(75); w = w + 75
                    end
                    DF.STATE.checking_wl_edit = false

                    if DF.STATE.wl_edit_seen then
                        if DF.STATE.wl_edit_is_public then
                            DF.STATE.world_enter_public = true
                            addLog(appliedWL
                                and "[Lock/Door] World Lock (242) terverifikasi: Allow anyone to Build & Break = ON!"
                                or  "[Lock/Door] World Lock (242) sudah Allow anyone to Build & Break.")
                            break
                        else
                            local retPkt = DF.STATE.wl_edit_return_pkt
                            if retPkt == "" then
                                retPkt = string.format(
                                    "action|dialog_return\ndialog_name|lock_edit\ntilex|%d|\ntiley|%d|\ncheckbox_public|1\ncheckbox_disable_music|0\ntempo|100\ncheckbox_disable_music_render|0\ncheckbox_set_as_home_world|0\nminimum_entry_level|1\n",
                                    wlX, wlY
                                )
                            end
                            pcall(sendPacket, 2, retPkt)
                            appliedWL = true
                            -- Tunggu sinkronisasi tile flag 0x80 (bila langsung ON, selesai tanpa wrench kedua!)
                            local sw = 0
                            while sw < 900 and isActive() do
                                safeSleep(90); sw = sw + 90
                                local fp2, hf2 = isTilePublicFlag(getTileSafe(wlX, wlY))
                                if hf2 and fp2 then
                                    DF.STATE.world_enter_public = true
                                    addLog("[Lock/Door] World Lock (242) diset Allow anyone to Build & Break = ON!")
                                    break
                                end
                            end
                            if DF.STATE.world_enter_public == true then break end
                        end
                    else
                        -- Fallback bila APK tidak meneruskan OnDialogRequest lock_edit ke Lua
                        pcall(sendPacket, 2, string.format(
                            "action|dialog_return\ndialog_name|lock_edit\ntilex|%d|\ntiley|%d|\ncheckbox_public|1\ncheckbox_disable_music|0\ntempo|100\ncheckbox_disable_music_render|0\ncheckbox_set_as_home_world|0\nminimum_entry_level|1\n",
                            wlX, wlY
                        ))
                        safeSleep(550)
                        addLog("[Lock/Door] World Lock (242) diset Allow anyone to Build & Break (fallback).")
                        break
                    end
                end
            end
        end
    end

    -- 5. CEK / PASANG DOOR ID di (0, 0)
    -- Lapis 1: Jika Door sudah ada di (0,0) & bot masuk langsung ke (0,0) dengan row.door == targetID -> SKIP wrench!
    -- Lapis 2: Jika Door sudah ada di (0,0) -> Wrench 1x baca dialog door_edit; kalau ID sudah benar & locked -> SKIP edit!
    if DF.CFG.use_id_door then
        local dItem = math.max(1, tonumber(DF.CFG.id_door_itemid) or 12)
        local targetID = trimStr(DF.CFG.door_id or "DF123"):upper()
        local targetLbl = trimStr(DF.CFG.door_label or "BOREN STORE")

        local okDoor, alreadyDoor = ensureAndPlace(0, 0, dItem, 1, "Door ID " .. resolveDoorItemName(dItem), true)
        if okDoor and targetID ~= "" and sendPacket then
            local needEditDoor = true
            if alreadyDoor then
                local px, py = getPlayerPos()
                if cleanWorldName(row.door) == targetID and px and py and px <= 1 and py <= 1 then
                    needEditDoor = false
                    addLog("[Lock/Door] Door ID (0,0) sudah valid (" .. targetID .. ") — skip edit.")
                else
                    -- Baca dialog door_edit 1x secara senyap lewat DF.handleVariant
                    DF.STATE.checking_door_edit = true
                    DF.STATE.door_edit_seen = false
                    DF.STATE.door_edit_id = ""
                    DF.STATE.door_edit_locked = false
                    moveSafeTo(1, 0)
                    safeSleep(180)
                    rawAction(0, 0, ITEM.WRENCH)
                    local w = 0
                    while w < 900 and isActive() and (not DF.STATE.door_edit_seen) do
                        safeSleep(75); w = w + 75
                    end
                    DF.STATE.checking_door_edit = false
                    if DF.STATE.door_edit_seen and cleanWorldName(DF.STATE.door_edit_id) == targetID and DF.STATE.door_edit_locked then
                        needEditDoor = false
                        if cleanWorldName(row.door) ~= targetID then
                            row.door = targetID
                            DF.saveData()
                        end
                        addLog("[Lock/Door] Cek Door ID (0,0) OK (" .. targetID .. ") — tidak perlu edit ulang.")
                    end
                end
            end

            if needEditDoor then
                safeSleep(180)
                moveSafeTo(1, 0)
                if not DF.STATE.door_edit_seen then
                    rawAction(0, 0, ITEM.WRENCH)
                    safeSleep(380)
                end
                pcall(sendPacket, 2, string.format(
                    "action|dialog_return\ndialog_name|door_edit\ntilex|0|\ntiley|0|\ndoor_name|%s\ndoor_target|\ndoor_id|%s\ncheckbox_locked|1\n",
                    targetLbl, targetID
                ))
                safeSleep(450)
                row.door = targetID
                DF.saveData()
                addLog("[Lock/Door] Door ID (0,0) diset -> ID=" .. targetID .. " | Label=" .. targetLbl)
            end
        end
    end
    return true
end

local function processDirtFarmWorld(row, skipPreKitCheck)
    -- 0A. Mode Find World: WAJIB siapkan & validasi alat di Storage SEBELUM cari world random!
    --     Mode Add World sendiri: masuk world target dulu -> jika posisi lock sudah lengkap, hemat trip Storage!
    if (not skipPreKitCheck) and DF.CFG.find_world_mode and (not DF.CFG.ignore_lock) then
        if not prepareAndValidateDFKit() then
            row.status = "Alat Kurang"
            DF.saveData()
            return false
        end
    end

    local targetName = cleanWorldName(row.name)
    row.status = "Warping..."
    DF.STATE.status_text = "Warp: " .. row.name
    if not warpToWorld(row.name, row.door) then
        DF.STATE.anti_take_active = false
        activeTargetWorld = ""
        row.status = "Inaccessible"
        DF.saveData()
        return false
    end
    DF.STATE.anti_take_active = false
    DF.STATE.in_storage = false
    DF.STATE.df_stash_spots = {}
    activeTargetWorld = targetName
    activeTargetDoor  = cleanWorldName(row.door)
    setAutoCollectActive(DF.CFG.auto_collect == true)
    safeSleep(550)

    local doorX, doorY = findMainDoor()
    if not doorX or not doorY then
        local wDoor = 0
        while wDoor < 3000 and isActive() do
            safeSleep(250); wDoor = wDoor + 250
            doorX, doorY = findMainDoor()
            if doorX and doorY then break end
        end
    end
    if not doorX or not doorY then
        addLog("[DF] Main Door tidak terdeteksi di world " .. row.name .. " (sinkronisasi lambat / world tidak valid).")
        row.status = "No Main Door"
        DF.saveData()
        return false
    end
    local minX, maxX = getDFRowBounds()
    local sideCols = getSideColumns()

    -- 0B. SETUP SECURITY (Penghalang, Jammer, WL, SL, Door ID) bila diaktifkan
    setupWorldSecurity(row, doorX, doorY)

    -- GUARD KERAS: Pastikan bot BENAR-BENAR berada di world DF target (BUKAN di storage!)
    -- sebelum boleh mengirim 1 pun packet break dirt!
    if getCurrentWorldSafe() ~= targetName then
        if not warpToWorld(row.name, row.door) then
            addLog("[DF Guard] Gagal kembali ke " .. row.name .. " — batal break dirt agar tidak merusak storage!")
            activeTargetWorld = ""
            row.status = "Retry Warp"
            DF.saveData()
            return false
        end
        DF.STATE.anti_take_active = false
        DF.STATE.in_storage = false
        activeTargetWorld = targetName
        safeSleep(550)
        doorX, doorY = findMainDoor()
    end

    -- Pastikan Auto Collect BENAR-BENAR ON & Anti Collect OFF tepat sebelum mulai break dirt!
    DF.STATE.anti_take_active = false
    DF.STATE.in_storage = false
    setAutoCollectActive(DF.CFG.auto_collect == true)

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

    local function isSecurityMoatZone(tx, ty)
        if (not DF.CFG.auto_place_sl) or (not doorX) or (not doorY) then return false end
        return (math.abs(tx - doorX) <= 2 and math.abs(ty - doorY) <= 2)
    end

    local function ensureDirtStock(contextLabel)
        if getInvCount(ITEM.DIRT) > 0 then return true end
        -- PRIORITAS 1: Pungut SEMUA Dirt Block yang ter-drop di world DF dulu sebelum tanam seed!
        DF.STATE.df_stash_spots = {}
        DF.STATE.status_text = row.name .. " Ambil Dirt DF..."
        collectFloatingItemInDF(ITEM.DIRT, 185)
        if getInvCount(ITEM.DIRT) > 0 then return true end
        -- PRIORITAS 2: Hanya tanam Dirt Seed bila Dirt Block di tas & world DF sudah benar-benar 0!
        if farmDirtOnce(doorX, doorY, minX, maxX) and getInvCount(ITEM.DIRT) > 0 then
            return true
        end
        addLog("[DF] Dirt (2) & Dirt Seed (3) habis saat " .. tostring(contextLabel or "build"))
        return false
    end

    -- 4. BANGUN LANTAI DIRT ATAS (Y = 2, 4, ..., 22) POLA 3-ZIGZAG + VERIFIKASI PUT ANTI-LAG
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
                if not ensureDFOnline(row.name, row.door) then return false end
                local xs = goingRight and { standX - 1, standX, standX + 1 } or { standX + 1, standX, standX - 1 }

                local function collectMissingInChunk()
                    local m = {}
                    for _, bx in ipairs(xs) do
                        if bx >= minX and bx <= maxX and (not isProtectedDoorArea(bx, py, doorX, doorY)) and (not isSecurityMoatZone(bx, py)) then
                            local t = getTileSafe(bx, py)
                            if t and (tonumber(t.fg) or 0) == 0 then table.insert(m, bx) end
                        end
                    end
                    return m
                end

                local miss = collectMissingInChunk()
                if #miss > 0 then
                    -- Verifikasi tiap 3-tile chunk hingga benar-benar ter-put di server (maks 4 ronde bila lag/rubberband)
                    for vRound = 1, 4 do
                        if not DF.STATE.running then break end
                        if not ensureDirtStock("build baris atas Y=" .. py) then
                            outOfDirt = true
                            break
                        end
                        local px, pyNow = getPlayerPos()
                        if vRound > 1 or (not px) or math.abs(px - standX) > 1 or pyNow ~= standY then
                            moveSafeTo(standX, standY)
                            if vRound > 1 then safeSleep(80) end
                        end
                        for _, bx in ipairs(miss) do
                            if not DF.STATE.running then break end
                            local tNow = getTileSafe(bx, py)
                            if tNow and (tonumber(tNow.fg) or 0) == 0 then
                                if getInvCount(ITEM.DIRT) <= 0 then
                                    if not ensureDirtStock("build baris atas Y=" .. py) then
                                        outOfDirt = true
                                        break
                                    end
                                    moveSafeTo(standX, standY)
                                end
                                rawAction(bx, py, ITEM.DIRT)
                                safeSleep(pDelay)
                            end
                        end
                        if outOfDirt or (not DF.STATE.running) then break end
                        -- Tunggu konfirmasi server singkat lalu cek ulang apakah masih ada yang bolong akibat lag!
                        safeSleep((vRound == 1) and 90 or 160)
                        miss = collectMissingInChunk()
                        if #miss == 0 then break end
                    end
                    if outOfDirt then break end
                end
                standX = standX + step
            end
            if outOfDirt then break end
            goingRight = not goingRight
        end
    end

    -- 5. PASANG PLATFORM (ID CONFIGURABLE) DI SISI TANGGA X=1 & X=98
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

    -- 5.5. VALIDASI MENYELURUH BENTUK WORLD & SEMUA PUT/BREAK (AUTO-REPAIR SISA LAG!)
    local remainingIssues = 0
    if DF.STATE.running then
        local platID = tonumber(DF.CFG.platform_id) or 102
        local outOfDirtVal = false
        local outOfPlatVal = false

        local function scanWorldDefects()
            local d = { sides = {}, rows = {}, lavaRock = {}, lowerHoles = {}, upperDirt = {}, platforms = {} }

            -- A. Audit Break Sisi Pinggir
            if DF.CFG.clear_side and #sideCols > 0 then
                for _, sx in ipairs(sideCols) do
                    for sy = 24, 53 do
                        local need, nFg, nBg = isOddTileClearNeeded(sx, sy, doorX, doorY)
                        if need then
                            d.sides[#d.sides + 1] = { x = sx, y = sy, fg = nFg, bg = nBg }
                        end
                    end
                end
            end

            -- B. Audit Break Lorong Baris Ganjil (FG + Cave BG)
            if DF.CFG.clear_rows then
                for sy = 25, 53, 2 do
                    for sx = minX, maxX do
                        local need, nFg, nBg = isOddTileClearNeeded(sx, sy, doorX, doorY)
                        if need then
                            d.rows[#d.rows + 1] = { x = sx, y = sy, fg = nFg, bg = nBg }
                        end
                    end
                end
            end

            -- C. Audit Platform Bawah (Y=24..52 genap): sisa Lava/Rock & lubang floor di luar Moat Lock
            if DF.CFG.break_lava or DF.CFG.break_rock then
                for py = 24, 52, 2 do
                    for px = minX, maxX do
                        if (not isProtectedDoorArea(px, py, doorX, doorY)) and (not isSecurityMoatZone(px, py)) then
                            local t = getTileSafe(px, py)
                            local fg = tonumber(t and t.fg) or 0
                            if (DF.CFG.break_lava and fg == ITEM.LAVA) or (DF.CFG.break_rock and fg == ITEM.ROCK) then
                                d.lavaRock[#d.lavaRock + 1] = { x = px, y = py }
                            elseif fg == 0 and DF.CFG.build_upper_dirt then
                                d.lowerHoles[#d.lowerHoles + 1] = { x = px, y = py }
                            end
                        end
                    end
                end
            end

            -- D. Audit Put Lantai Dirt Atas (Y=2..22 genap)
            if DF.CFG.build_upper_dirt then
                for py = 2, 22, 2 do
                    for px = minX, maxX do
                        if (not isProtectedDoorArea(px, py, doorX, doorY)) and (not isSecurityMoatZone(px, py)) then
                            local t = getTileSafe(px, py)
                            if t and (tonumber(t.fg) or 0) == 0 then
                                d.upperDirt[#d.upperDirt + 1] = { x = px, y = py }
                            end
                        end
                    end
                end
            end

            -- E. Audit Put Platform Sisi Tangga (X=1 & X=98, Y=2..52 genap)
            if DF.CFG.place_platform then
                for _, px in ipairs({ 1, 98 }) do
                    for py = 2, 52, 2 do
                        local t = getTileSafe(px, py)
                        if t and tonumber(t.fg) ~= platID and (tonumber(t.fg) or 0) == 0 then
                            d.platforms[#d.platforms + 1] = { x = px, y = py }
                        end
                    end
                end
            end

            d.total = #d.sides + #d.rows + #d.lavaRock + #d.lowerHoles + #d.upperDirt + #d.platforms
            return d
        end

        for vPass = 1, 6 do
            if not DF.STATE.running then return false end
            if not ensureDFOnline(row.name, row.door) then return false end

            local d = scanWorldDefects()
            remainingIssues = d.total
            if d.total == 0 then
                addLog(string.format("[DF Validasi OK] Pass #%d: Bentuk world & semua put/break 100%% sempurna!", vPass))
                break
            end

            row.status = string.format("Validasi #%d (%d)", vPass, d.total)
            DF.STATE.status_text = string.format("%s Fix #%d (%d)", row.name, vPass, d.total)
            addLog(string.format(
                "[DF Validasi #%d] Ditemukan %d sisa lag (Sisi=%d, Lorong=%d, Lava/Rock=%d, LubangBawah=%d, DirtAtas=%d, Plat=%d) — memperbaiki...",
                vPass, d.total, #d.sides, #d.rows, #d.lavaRock, #d.lowerHoles, #d.upperDirt, #d.platforms
            ))

            local repairedAny = false

            -- 1. Repair Break Sisi Pinggir
            for _, item in ipairs(d.sides) do
                if not DF.STATE.running then return false end
                if breakTileCompletely(item.x, item.y, item.fg, item.bg, (item.x < 50) and 1 or -1, false) then
                    repairedAny = true
                end
                checkAutoTrash()
            end

            -- 2. Repair Break Lorong Ganjil
            for _, item in ipairs(d.rows) do
                if not DF.STATE.running then return false end
                if breakTileCompletely(item.x, item.y, item.fg, item.bg, -1, false) then
                    repairedAny = true
                end
                checkAutoTrash()
            end

            -- 3. Repair Lava / Rock Platform Bawah + Tambal Dirt
            for _, item in ipairs(d.lavaRock) do
                if not DF.STATE.running then return false end
                if breakTileCompletely(item.x, item.y, true, false, -1, false) then
                    repairedAny = true
                    if (not outOfDirtVal) and ensureDirtStock("tambal lava/rock") then
                        placeTileAt(item.x, item.y, ITEM.DIRT, -1)
                    end
                end
            end

            -- 4. Repair Lubang Floor Bawah (Y=24..52 genap)
            if not outOfDirtVal then
                for _, item in ipairs(d.lowerHoles) do
                    if not DF.STATE.running then return false end
                    if not ensureDirtStock("validasi floor bawah") then
                        outOfDirtVal = true
                        break
                    end
                    if placeTileAt(item.x, item.y, ITEM.DIRT, -1) then
                        repairedAny = true
                    end
                end
            end

            -- 5. Repair Put Lantai Dirt Atas (Y=2..22 genap)
            if not outOfDirtVal then
                for _, item in ipairs(d.upperDirt) do
                    if not DF.STATE.running then return false end
                    if not ensureDirtStock("validasi dirt atas") then
                        outOfDirtVal = true
                        break
                    end
                    if placeTileAt(item.x, item.y, ITEM.DIRT, -1) then
                        repairedAny = true
                    end
                end
            end

            -- 6. Repair Put Platform Sisi Tangga
            if not outOfPlatVal then
                for _, item in ipairs(d.platforms) do
                    if not DF.STATE.running then return false end
                    if getInvCount(platID) <= 0 then
                        if not restockItem(row, platID, 120) then
                            outOfPlatVal = true
                            break
                        end
                    end
                    if placeTileAt(item.x, item.y, platID, (item.x < 50) and 1 or -1) then
                        repairedAny = true
                    end
                end
            end

            safeSleep(180)
            if not repairedAny then
                -- Cek ulang 1x untuk angka sisa akurat bila memang bahan habis / petak terkunci
                remainingIssues = scanWorldDefects().total
                break
            end
        end
    end

    -- 6. SIMPAN SISA DIRT BLOCK & DIRT SEED KE SAVE WORLD (Bila kosong -> biarkan di Dirt Farm!)
    if DF.STATE.running then
        saveLeftoverDirtToSaveWorld(row)
    end

    activeTargetWorld = ""
    if remainingIssues == 0 then
        row.status = "Done"
        DF.saveData()
        addLog("[Selesai] Dirt Farm " .. row.name .. " tuntas & tervalidasi 100%!")
    else
        row.status = "Sisa (" .. tostring(remainingIssues) .. ")"
        DF.saveData()
        addLog(string.format("[Peringatan] Dirt Farm %s masih ada %d tile belum rapi (cek bahan/lock)!", row.name, remainingIssues))
    end
    return (remainingIssues == 0)
end

local function mainLoop()
    DF.STATE.running = true
    DF.STATE.in_storage = false
    DF.STATE.anti_take_active = false
    activeTargetWorld = ""
    applyCheats()
    addLog("Auto Dirt Farm dimulai.")

    if DF.CFG.find_world_mode then
        local targetCnt = math.max(1, tonumber(DF.CFG.find_target_cnt) or 1)
        DF.STATE.found_count = 0
        local rowAttempts = {}

        while DF.STATE.running do
            -- 1. Cari apakah masih ada world di list yang belum 'Done' dan bukan 'Inaccessible'
            local pendingRow = nil
            for _, r in ipairs(DF.STATE.rows) do
                if r.status ~= "Done" and r.status ~= "Inaccessible" then
                    pendingRow = r
                    break
                end
            end

            if pendingRow then
                local rKey = pendingRow.name
                rowAttempts[rKey] = (rowAttempts[rKey] or 0) + 1
                addLog(string.format("[DF Queue] Menyelesaikan world di list: %s (Percobaan #%d | Status: %s)...", pendingRow.name, rowAttempts[rKey], tostring(pendingRow.status)))
                
                local okDone = processDirtFarmWorld(pendingRow, false)
                safeSleep(450)

                if pendingRow.status == "Done" then
                    rowAttempts[rKey] = nil
                else
                    -- Jika world belum selesai karena kehabisan bahan / alat di storage
                    if pendingRow.status == "Alat Kurang" or pendingRow.status == "No Plat" or pendingRow.status == "Drop Kelebihan Gagal" then
                        addLog(string.format("[DF] Berhenti: World %s belum selesai karena '%s'. Lengkapi bahan di storage terlebih dahulu!", pendingRow.name, tostring(pendingRow.status)))
                        break
                    end
                    -- Jika sudah 3x gagal tanpa progress, hentikan agar tidak loop terus menerus
                    if (rowAttempts[rKey] or 0) >= 3 then
                        addLog(string.format("[DF] World %s masih berstatus '%s' setelah 3x percobaan. Proses dihentikan untuk dicek manual!", pendingRow.name, tostring(pendingRow.status)))
                        break
                    end
                    addLog(string.format("[DF Queue] World %s masih berstatus '%s'. Mengulang penyelesaian world ini hingga Done...", pendingRow.name, tostring(pendingRow.status)))
                    safeSleep(1000)
                end
            else
                -- 2. SEMUA world yang ada di list sudah berstatus "Done" (atau Inaccessible).
                -- Cek apakah target find world sudah tercapai
                if DF.STATE.found_count >= targetCnt then
                    addLog(string.format("`2[DF Selesai] Semua world di list sudah Done & target find world (%d/%d) sudah tercapai!", DF.STATE.found_count, targetCnt))
                    break
                end

                addLog(string.format("[DF Queue] Semua world di list sudah Done. Mencari world kosong baru (#%d/%d)...", DF.STATE.found_count + 1, targetCnt))
                
                -- Validasi alat storage sebelum find world (hanya jika ignore_lock tidak aktif)
                if not DF.CFG.ignore_lock then
                    if not prepareAndValidateDFKit() then
                        addLog("[DF] Berhenti: alat di storage belum lengkap atau kelebihan belum ter-drop.")
                        break
                    end
                end

                local foundRow = findOneFreeWorld()
                if not foundRow then
                    addLog("[DF] Tidak berhasil menemukan world kosong baru. Proses dihentikan.")
                    break
                end

                -- foundRow otomatis masuk ke DF.STATE.rows dengan status = 'Ready'
                -- Iterasi while berikutnya akan langsung memproses foundRow sampai 'Done'
                -- sebelum mencari world berikutnya!
                safeSleep(500)
            end
        end
    else
        while DF.STATE.running do
            for _, row in ipairs(DF.STATE.rows) do
                if not DF.STATE.running then break end
                if row.status ~= "Done" and row.status ~= "Inaccessible" then
                    processDirtFarmWorld(row, false)
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

    DF.STATE.in_storage = false
    DF.STATE.anti_take_active = false
    DF.STATE.pending_drop_id = 0
    DF.STATE.pending_drop_amt = 0
    activeTargetWorld = ""
    DF.STATE.running = false
    DF.STATE.enabled = false
    DF.STATE.status_text = "Idle"
    addLog("Auto Dirt Farm berhenti.")
end

function DF.start()
    if DF.STATE.running then return end
    if HUB_REF and HUB_REF.conn and HUB_REF.conn.clearFatal then pcall(HUB_REF.conn.clearFatal) end
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
            DF.STATE.in_storage = false
            DF.STATE.anti_take_active = false
            DF.STATE.pending_drop_id = 0
            DF.STATE.pending_drop_amt = 0
            activeTargetWorld = ""
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
    DF.STATE.in_storage = false
    DF.STATE.anti_take_active = false
    DF.STATE.pending_drop_id = 0
    DF.STATE.pending_drop_amt = 0
    DF.STATE.checking_door_edit = false
    DF.STATE.checking_wl_edit = false
    activeTargetWorld = ""
    DF.STATE.enabled = false
    DF.STATE.status_text = "Stopped"
end

-- Parse dialog lock_edit asli Growtopia V5.x secara dinamis untuk World Lock:
-- Mendeteksi status "Allow anyone to Build and Break" (checkbox_public / allow_build) & membangun paket dialog_return presisi!
local function parseWLPublicDialog(payload)
    local dName = "lock_edit"
    local lines = { "action|dialog_return" }
    local embedLines = {}
    local fieldLines = {}
    local isPublic = false
    local sawPublicField = false

    for line in tostring(payload or ""):gmatch("[^\r\n]+") do
        local parts = {}
        for part in (line .. "|"):gmatch("([^|]*)|") do
            parts[#parts + 1] = part
        end
        local cmd = parts[1]
        if cmd == "end_dialog" and parts[2] and parts[2] ~= "" then
            dName = trimStr(parts[2])
        elseif cmd == "embed_data" and parts[2] and parts[2] ~= "" then
            embedLines[#embedLines + 1] = trimStr(parts[2]) .. "|" .. trimStr(parts[3] or "") .. "|"
        elseif cmd == "add_checkbox" and parts[2] and parts[2] ~= "" then
            local k = trimStr(parts[2])
            local lbl = trimStr(parts[3] or ""):lower()
            local curV = trimStr(parts[4] or "0")
            local kl = k:lower()
            local isPubBox = (kl == "checkbox_public" or kl:find("public", 1, true)
                or kl:find("allow_build", 1, true)
                or lbl:find("allow anyone", 1, true)
                or lbl:find("build and break", 1, true))
            if isPubBox then
                sawPublicField = true
                if curV == "1" then isPublic = true end
                fieldLines[#fieldLines + 1] = k .. "|1"
            else
                fieldLines[#fieldLines + 1] = k .. "|" .. (curV ~= "" and curV or "0")
            end
        elseif cmd == "add_text_input" and parts[2] and parts[2] ~= "" then
            local k = trimStr(parts[2])
            local curV = trimStr(parts[4] or "")
            fieldLines[#fieldLines + 1] = k .. "|" .. curV
        end
    end

    lines[#lines + 1] = "dialog_name|" .. dName
    for _, el in ipairs(embedLines) do lines[#lines + 1] = el end
    for _, fl in ipairs(fieldLines) do lines[#lines + 1] = fl end
    if not sawPublicField then
        lines[#lines + 1] = "checkbox_public|1"
    end
    return isPublic, table.concat(lines, "\n") .. "\n"
end

-- Auto-confirm dialog drop / drop_item + cek senyap dialog door_edit & lock_edit + baca status world OnConsoleMessage!
-- Mendukung format VariantList v0/v1 maupun v1/v2 serta dialog Growtopia V5.x!
function DF.handleVariant(var)
    if not isActive() then return false end
    if type(var) ~= "table" and type(var) ~= "userdata" then return false end

    local v0, v1, v2 = nil, nil, nil
    pcall(function() v0 = var.v0 or var[0] end)
    pcall(function() v1 = var.v1 or var[1] end)
    pcall(function() v2 = var.v2 or var[2] end)

    local s0, s1 = tostring(v0 or ""), tostring(v1 or "")

    -- 0. Pantau pesan masuk world (OnConsoleMessage) untuk tahu otomatis apakah WL sudah Public [OPEN] (0 wrench!)
    if s0 == "OnConsoleMessage" or s1 == "OnConsoleMessage" then
        local msg = (s0 == "OnConsoleMessage") and tostring(v1 or "") or tostring(v2 or "")
        local clean = msg:gsub("`.", ""):lower()
        if clean:find("world locked by", 1, true) or clean:find("open to the public", 1, true) or clean:find("[open]", 1, true) then
            if clean:find("[open]", 1, true) or clean:find("open to the public", 1, true) or clean:find("allow anyone", 1, true) then
                DF.STATE.world_enter_public = true
            elseif clean:find("world locked by", 1, true) then
                DF.STATE.world_enter_public = false
            end
        end
        return false -- Jangan blokir tampilan console normal!
    end

    local wantDrop = (DF.STATE.pending_drop_id > 0)
    local wantDoor = (DF.STATE.checking_door_edit == true)
    local wantWL   = (DF.STATE.checking_wl_edit == true)
    if (not wantDrop) and (not wantDoor) and (not wantWL) then return false end

    local fn, payload = "", ""
    if s0 == "OnDialogRequest" then
        fn = "OnDialogRequest"
        payload = tostring(v1 or "")
    elseif s1 == "OnDialogRequest" then
        fn = "OnDialogRequest"
        payload = tostring(v2 or "")
    end
    if fn ~= "OnDialogRequest" or payload == "" then return false end

    local low = payload:lower()
    local endDlg = (payload:match("end_dialog|([^|\r\n]+)") or ""):lower()

    -- A. Cek senyap dialog lock_edit World Lock ("Allow anyone to Build and Break")
    if wantWL and (endDlg == "lock_edit" or low:find("checkbox_public", 1, true) or low:find("allow anyone", 1, true)) then
        local isPub, retPkt = parseWLPublicDialog(payload)
        DF.STATE.wl_edit_is_public  = isPub
        DF.STATE.wl_edit_return_pkt = retPkt
        DF.STATE.wl_edit_seen       = true
        return true
    end

    -- B. Cek senyap dialog door_edit (baca door_id & checkbox_locked tanpa menampilkan popup ke layar!)
    if wantDoor and (endDlg == "door_edit" or low:find("add_text_input|door_id|", 1, true)) then
        local dId = ""
        local dLocked = false
        for line in payload:gmatch("[^\r\n]+") do
            local parts = {}
            for part in (line .. "|"):gmatch("([^|]*)|") do
                parts[#parts + 1] = part
            end
            if parts[1] == "add_text_input" and parts[2] == "door_id" then
                dId = trimStr(parts[4] or "")
            elseif parts[1] == "add_checkbox" and parts[2] == "checkbox_locked" then
                dLocked = (trimStr(parts[4] or "") == "1")
            end
        end
        DF.STATE.door_edit_id = dId
        DF.STATE.door_edit_locked = dLocked
        DF.STATE.door_edit_seen = true
        return true
    end

    -- C. Auto-confirm dialog drop / drop_item
    if wantDrop and (endDlg == "drop" or endDlg == "drop_item" or endDlg:find("drop", 1, true)
        or low:find("how many to drop", 1, true) or low:find("drop_item", 1, true))
    then
        if not DF.STATE.drop_confirmed then
            DF.STATE.drop_confirmed = true
            if sendPacket then
                local pktStr = buildDropDialogReturn(payload, DF.STATE.pending_drop_id, DF.STATE.pending_drop_amt)
                pcall(sendPacket, 2, pktStr)
            end
        end
        return true
    end
    return false
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
-- 6. UI RENDERER (List World | Find World | Lock & Door | Storage | Settings | Logs)
-- ============================================================================
local function autoBtn(label)
    local ok, res = pcall(ImGui.Button, label)
    return ok and (res == true)
end

local function uiKit()
    return HUB_REF and HUB_REF.ui_kit or nil
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
    local k = uiKit()
    if k and k.sectionWithKetik and k.openInputDialog then
        k.sectionWithKetik(title, btnId, onKetikClick, skipTopSep)
        return
    end
    uiSection(title, skipTopSep)
end

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
    _G.__BOREN_ACTIVE_NATIVE_DIALOGS = _G.__BOREN_ACTIVE_NATIVE_DIALOGS or {}
    _G.__BOREN_ACTIVE_NATIVE_DIALOGS[dialogId] = onSubmit

    local lines = {
        "set_default_color|`o",
        "add_label_with_icon|big|`cBOREN DIRT FARM - " .. sanitizeDialogVal(title) .. "|left|3802|",
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
                return true
            end
        end
    end
    return false
end

function DF.handleSendPacket(p1, p2)
    return onSendPacketHook(p1, p2)
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

local function uiReadClipLines()
    local k = uiKit()
    if k and k.readClipboardLines then return k.readClipboardLines() end
    local clip = ""
    if ImGui and ImGui.GetClipboardText then
        local ok, c = pcall(ImGui.GetClipboardText)
        if ok and type(c) == "string" then clip = c end
    end
    local lines = {}
    for line in clip:gmatch("[^\r\n]+") do
        local s = trimStr(line)
        if s ~= "" then lines[#lines + 1] = s end
    end
    return lines
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
    uiSection("Kontrol Dirt Farm", true)
    ImGui.Text("Status Bot  :"); ImGui.SameLine()
    if uiEnableBtn(DF.STATE.enabled, "df_en") then
        if DF.STATE.enabled then DF.stop() else DF.start() end
    end
    ImGui.SameLine(); ImGui.Text("    Loop  :"); ImGui.SameLine()
    if uiToggleBtn(DF.CFG.loop_enabled, "df_lp") then
        DF.CFG.loop_enabled = not DF.CFG.loop_enabled; DF.saveData()
    end
    ImGui.SameLine()
    if autoBtn(" Remove Inaccessible ##df") then
        local kept, rem = {}, 0
        for _, r in ipairs(DF.STATE.rows) do
            if tostring(r.status):lower():find("inaccessible", 1, true) then rem = rem + 1
            else table.insert(kept, r) end
        end
        DF.STATE.rows = kept; DF.STATE.selected_idx = 0; DF.saveData()
        uiNotice = "Dihapus " .. tostring(rem) .. " world inaccessible."
    end
    ImGui.SameLine()
    if autoBtn(" Reset ##df_rst") then
        for _, r in ipairs(DF.STATE.rows) do r.status = "Ready" end
        DF.saveData(); uiNotice = "Status di-reset ke Ready."
    end

    uiGap(4)
    local modeLabel = DF.CFG.find_world_mode and "Find World" or "Manual List"
    local brkLabel  = DF.CFG.break_3_mode and "3-Tile" or "1-Tile"
    local bgLabel   = DF.CFG.break_cave_bg and "BG:ON" or "BG:OFF"
    ImGui.Text(string.format("Status: %s   |   Mode: %s   |   %s   |   %s",
        tostring(DF.STATE.status_text), modeLabel, brkLabel, bgLabel))
    uiNote(uiNotice)

    uiSection("Daftar World DF (" .. tostring(#DF.STATE.rows) .. ")")

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

        local function ketikFarmForm()
        local wPre = cleanDialogField(addWorldBuf)
        local dPre = cleanDialogField(addDoorBuf)
        uiOpenDialog("boren_in_df_w", "Input Form World Dirt Farm", {
            { id = "f_world", label = "Nama World", default = wPre, maxLen = 32 },
            { id = "f_door",  label = "Door ID",    default = dPre,  maxLen = 32 },
        }, "Masukkan ke Form", function(vals)
            local wn = cleanDialogField(vals.f_world or vals["f_world"]):upper()
            local dn = cleanDialogField(vals.f_door or vals["f_door"]):upper()
            if wn ~= "" then
                addWorldBuf = wn
            end
            if dn ~= "" then
                addDoorBuf = dn
            end
            formRevision = formRevision + 1
            uiNotice = "Form DF terisi: " .. tostring(addWorldBuf) .. (addDoorBuf ~= "" and (":" .. addDoorBuf) or "")
        end)
    end
    uiSectionWithKetik("Tambah World DF Baru", "df_ktk_w", ketikFarmForm)
    if ImGui.BeginTable("BorenDFAddW", 2) then
        ImGui.TableSetupColumn("World Name")
        ImGui.TableSetupColumn("Door ID")
        ImGui.TableHeadersRow()
        ImGui.TableNextRow()
        ImGui.TableSetColumnIndex(0)
        ImGui.PushItemWidth(math.max(110, math.floor(w * 0.46)))
        local chW, nvW = safeInputText("##df_add_w", addWorldBuf, 256, ketikFarmForm)
        ImGui.PopItemWidth()
        if chW then addWorldBuf = nvW end

        ImGui.TableSetColumnIndex(1)
        ImGui.PushItemWidth(math.max(90, math.floor(w * 0.44)))
        local chD, nvD = safeInputText("##df_add_d", addDoorBuf, 128, ketikFarmForm)
        ImGui.PopItemWidth()
        if chD then addDoorBuf = nvD end
        ImGui.EndTable()
    end
    uiGap(4)

    local act = uiActionBar("BorenDFActs", w, {
        { label = "+ Tambah##df_add", style = "accent" },
        { label = "World Ini##df_cur" },
        { label = "Paste##df_pst" },
        { label = "Hapus##df_del",    style = "muted" },
    })

    if act == 1 then
        local wStr = trimStr(addWorldBuf)
        local dStr = trimStr(addDoorBuf)
        local comb = (wStr:find(":", 1, true) or wStr:find("|", 1, true) or dStr == "") and wStr or (wStr .. ":" .. dStr)
        local p = parseWorldLine(comb)
        if p then
            table.insert(DF.STATE.rows, p); addWorldBuf = ""; addDoorBuf = ""
            formRevision = formRevision + 1
            DF.saveData()
            addLogUI("World DF ditambah: " .. p.name)
            uiNotice = "Tersimpan: " .. p.name
        else uiNotice = "Isi World Name dulu!" end

    elseif act == 2 then
        local curW = getCurrentWorldSafe()
        if curW ~= "" and curW ~= "EXIT" then
            addWorldBuf = curW
            formRevision = formRevision + 1
            uiNotice = "Terisi " .. curW .. " (isi Door ID jika ada lalu klik + Tambah)"
        else uiNotice = "Masuk ke world dulu!" end

    elseif act == 3 then
        local lines = uiReadClipLines()
        if #lines == 0 then
            uiNotice = "Clipboard kosong!"
        elseif #lines == 1 then
            local norm = lines[1]:gsub("|", ":")
            local wP, dP = norm:match("^([^:]+):(.*)$")
            if wP then
                addWorldBuf = trimStr(wP); addDoorBuf = trimStr(dP or "")
            else
                addWorldBuf = lines[1]; addDoorBuf = ""
            end
            uiNotice = "Paste ke form (" .. addWorldBuf .. "). Klik + Tambah."
        else
            local n = 0
            for _, ln in ipairs(lines) do
                local p = parseWorldLine(ln)
                if p then table.insert(DF.STATE.rows, p); n = n + 1 end
            end
            if n > 0 then DF.saveData(); uiNotice = "Smart Paste: +" .. tostring(n) .. " world (tersimpan)!"
            else uiNotice = "Format clipboard tidak valid." end
        end

    elseif act == 4 then
        local idx = DF.STATE.selected_idx
        if idx < 1 or idx > #DF.STATE.rows then idx = #DF.STATE.rows end
        if idx >= 1 and idx <= #DF.STATE.rows then
            local rem = table.remove(DF.STATE.rows, idx)
            DF.STATE.selected_idx = 0; DF.saveData()
            uiNotice = "Dihapus: " .. tostring(rem and rem.name or "")
        end
    end
end

local numBufs = {}

local function renderNumInput(id, curVal, minV, maxV, step, unit, onChange)
    local key = tostring(id)
    if numBufs[key] == nil then numBufs[key] = tostring(curVal) end
    ImGui.PushItemWidth(95)
    local ch, nv = safeInputText("##" .. key, numBufs[key], 64)
    ImGui.PopItemWidth()
    if ch then
        local digits = nv:gsub("[^0-9]", "")
        numBufs[key] = digits
        local n = tonumber(digits)
        if n then
            onChange(math.max(minV, math.min(maxV, math.floor(n))))
        end
    end
    if unit and unit ~= "" then
        ImGui.SameLine(); ImGui.Text(unit)
    end
    if step and step > 0 then
        ImGui.SameLine()
        if autoBtn(" - ##m_" .. key) then
            local nv2 = math.max(minV, (tonumber(curVal) or minV) - step)
            numBufs[key] = tostring(nv2)
            onChange(nv2)
        end
        ImGui.SameLine()
        if autoBtn(" + ##p_" .. key) then
            local nv2 = math.min(maxV, (tonumber(curVal) or minV) + step)
            numBufs[key] = tostring(nv2)
            onChange(nv2)
        end
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
    uiSection("Auto Find World Kosong (Bebas Lock & Player)", true)
    uiNote(uiNotice)

    if ImGui.BeginTable("BorenDFFindOpts", 2) then
        renderOptRow("Auto Find saat Start", function()
            if uiToggleBtn(DF.CFG.find_world_mode, "dffm") then
                DF.CFG.find_world_mode = not DF.CFG.find_world_mode; DF.saveData()
            end
        end)
        renderOptRow("Panjang Nama World", function()
            renderNumInput("df_flen", DF.CFG.find_name_len, 4, 14, 1, "huruf", function(v)
                DF.CFG.find_name_len = v; DF.saveData()
            end)
        end)
        renderOptRow("Campur Angka (0-9)", function()
            if uiToggleBtn(DF.CFG.find_use_num, "dffn") then
                DF.CFG.find_use_num = not DF.CFG.find_use_num; DF.saveData()
            end
        end)
        renderOptRow("Target Jumlah World", function()
            renderNumInput("df_ftgt", DF.CFG.find_target_cnt, 1, 50, 1, "world", function(v)
                DF.CFG.find_target_cnt = v; DF.saveData()
            end)
        end)
        renderOptRow("Auto World Lock (242)", function()
            if uiToggleBtn(DF.CFG.auto_lock_wl, "dfwl") then
                DF.CFG.auto_lock_wl = not DF.CFG.auto_lock_wl; DF.saveData()
            end
        end)
        renderOptRow("Auto Jammer (226)", function()
            if uiToggleBtn(DF.CFG.auto_place_jammer, "dfjm") then
                DF.CFG.auto_place_jammer = not DF.CFG.auto_place_jammer; DF.saveData()
            end
        end)
        ImGui.EndTable()
    end

    uiSection("Aksi Pencarian")
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
    uiGap(4)
    ImGui.Text("Total ditemukan sesi ini: " .. tostring(DF.STATE.found_count) .. "   |   Status: " .. tostring(DF.STATE.status_text))
end

local function renderStorageSub()
    local w = availX()
    local storages = getStorageList()
    uiSection("Storage Platform / Tool (" .. tostring(#storages) .. ")", true)
    uiNote(uiNotice)

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

        local function ketikStorageForm()
        local wPre = cleanDialogField(addStorageBuf)
        local dPre = cleanDialogField(addStorageDoorBuf)
        uiOpenDialog("boren_in_df_st", "Input Form Storage Dirt Farm", {
            { id = "f_world", label = "World Storage", default = wPre, maxLen = 32 },
            { id = "f_door",  label = "Door ID",       default = dPre, maxLen = 32 },
        }, "Masukkan ke Form", function(vals)
            local wn = cleanDialogField(vals.f_world or vals["f_world"]):upper()
            local dn = cleanDialogField(vals.f_door or vals["f_door"]):upper()
            if wn ~= "" then
                addStorageBuf = wn
            end
            if dn ~= "" then
                addStorageDoorBuf = dn
            end
            formRevision = formRevision + 1
            uiNotice = "Form Storage terisi: " .. tostring(addStorageBuf) .. (addStorageDoorBuf ~= "" and (":" .. addStorageDoorBuf) or "")
        end)
    end
    uiSectionWithKetik("Tambah Storage Baru", "df_ktk_st", ketikStorageForm)
    if ImGui.BeginTable("BorenDFAddSt", 2) then
        ImGui.TableSetupColumn("World Storage")
        ImGui.TableSetupColumn("Door ID")
        ImGui.TableHeadersRow()
        ImGui.TableNextRow()
        ImGui.TableSetColumnIndex(0)
        ImGui.PushItemWidth(math.max(110, math.floor(w * 0.46)))
        local chSt, nvSt = safeInputText("##df_add_st", addStorageBuf, 256, ketikStorageForm)
        ImGui.PopItemWidth()
        if chSt then addStorageBuf = nvSt end

        ImGui.TableSetColumnIndex(1)
        ImGui.PushItemWidth(math.max(90, math.floor(w * 0.44)))
        local chStD, nvStD = safeInputText("##df_add_std", addStorageDoorBuf, 128, ketikStorageForm)
        ImGui.PopItemWidth()
        if chStD then addStorageDoorBuf = nvStD end
        ImGui.EndTable()
    end
    uiGap(4)

    local actSt = uiActionBar("BorenDFStActs", w, {
        { label = "+ Tambah##dfst_add", style = "accent" },
        { label = "World Ini##dfst_cur" },
        { label = "Paste##dfst_pst" },
        { label = "Hapus##dfst_del",    style = "muted" },
    })

    if actSt == 1 then
        local wStr = trimStr(addStorageBuf)
        local dStr = trimStr(addStorageDoorBuf)
        local comb = (wStr:find(":", 1, true) or wStr:find("|", 1, true) or dStr == "") and wStr or (wStr .. ":" .. dStr)
        local p = parseWorldLine(comb)
        if p then
            table.insert(storages, { name = p.name, door = p.door })
            setStorageList(storages); addStorageBuf = ""; addStorageDoorBuf = ""
            formRevision = formRevision + 1
            uiNotice = "Tersimpan storage: " .. p.name
        else uiNotice = "Isi World Storage dulu!" end
    elseif actSt == 2 then
        local curW = getCurrentWorldSafe()
        if curW ~= "" and curW ~= "EXIT" then
            addStorageBuf = curW
            formRevision = formRevision + 1
            uiNotice = "Terisi " .. curW .. " (isi Door ID jika ada lalu klik + Tambah)"
        else uiNotice = "Masuk ke world dulu!" end
    elseif actSt == 3 then
        local lines = uiReadClipLines()
        if #lines == 0 then
            uiNotice = "Clipboard kosong!"
        elseif #lines == 1 then
            local norm = lines[1]:gsub("|", ":")
            local wP, dP = norm:match("^([^:]+):(.*)$")
            if wP then addStorageBuf = trimStr(wP); addStorageDoorBuf = trimStr(dP or "")
            else addStorageBuf = lines[1]; addStorageDoorBuf = "" end
            uiNotice = "Paste ke form storage. Klik + Tambah."
        else
            local n = 0
            for _, ln in ipairs(lines) do
                local p = parseWorldLine(ln)
                if p then table.insert(storages, { name = p.name, door = p.door }); n = n + 1 end
            end
            if n > 0 then setStorageList(storages); uiNotice = "Smart Paste: +" .. tostring(n) .. " storage (tersimpan)!"
            else uiNotice = "Format clipboard tidak valid." end
        end
    elseif actSt == 4 then
        local idx = DF.STATE.selected_st
        if idx < 1 or idx > #storages then idx = #storages end
        if idx >= 1 and idx <= #storages then
            table.remove(storages, idx); DF.STATE.selected_st = 0; setStorageList(storages); uiNotice = "Storage dihapus."
        end
    end

    -- PEMISAH JELAS ANTARA WORLD TOOLS & STORAGE SEED / SISA DIRT
    uiGap(16)
    if ImGui and ImGui.Separator then ImGui.Separator() end
    uiGap(8)

    local saveWorlds = getSaveWorldList()
    uiSection("Storage Seed & Sisa Dirt (" .. tostring(#saveWorlds) .. ")  [Kosong = Biarkan di DF]", true)

    if ImGui.BeginTable("BorenDFSaveTable", 2) then
        ImGui.TableSetupColumn("Save World")
        ImGui.TableSetupColumn("Door ID")
        ImGui.TableHeadersRow()
        if #saveWorlds == 0 then
            ImGui.TableNextRow()
            ImGui.TableSetColumnIndex(0); ImGui.Text("(Kosong - Sisa dibiarkan di DF)")
            ImGui.TableSetColumnIndex(1); ImGui.Text("-")
        else
            for i, sw in ipairs(saveWorlds) do
                ImGui.TableNextRow()
                ImGui.TableSetColumnIndex(0)
                local sel = (DF.STATE.selected_sw == i)
                if autoBtn((sel and "> " or "") .. sw.name .. "##dfsw" .. tostring(i)) then
                    DF.STATE.selected_sw = sel and 0 or i
                end
                ImGui.TableSetColumnIndex(1); ImGui.Text(sw.door ~= "" and sw.door or "-")
            end
        end
        ImGui.EndTable()
    end

    local function ketikSaveSeedForm()
        local wPre = cleanDialogField(addSaveBuf)
        local dPre = cleanDialogField(addSaveDoorBuf)
        uiOpenDialog("boren_in_df_sw", "Input Form Storage Seed / Save World", {
            { id = "f_world", label = "Save World", default = wPre, maxLen = 32 },
            { id = "f_door",  label = "Door ID",    default = dPre, maxLen = 32 },
        }, "Masukkan ke Form", function(vals)
            local wn = cleanDialogField(vals.f_world or vals["f_world"]):upper()
            local dn = cleanDialogField(vals.f_door or vals["f_door"]):upper()
            if wn ~= "" then
                addSaveBuf = wn
            end
            if dn ~= "" then
                addSaveDoorBuf = dn
            end
            formRevision = formRevision + 1
            uiNotice = "Form Save World terisi: " .. tostring(addSaveBuf) .. (addSaveDoorBuf ~= "" and (":" .. addSaveDoorBuf) or "")
        end)
    end
    uiSectionWithKetik("Tambah Storage Seed / Save World", "df_ktk_sw", ketikSaveSeedForm)
    if ImGui.BeginTable("BorenDFAddSw", 2) then
        ImGui.TableSetupColumn("Save World")
        ImGui.TableSetupColumn("Door ID")
        ImGui.TableHeadersRow()
        ImGui.TableNextRow()
        ImGui.TableSetColumnIndex(0)
        ImGui.PushItemWidth(math.max(110, math.floor(w * 0.46)))
        local chSw, nvSw = safeInputText("##df_add_sw", addSaveBuf, 256, ketikSaveSeedForm)
        ImGui.PopItemWidth()
        if chSw then addSaveBuf = nvSw end

        ImGui.TableSetColumnIndex(1)
        ImGui.PushItemWidth(math.max(90, math.floor(w * 0.44)))
        local chSwD, nvSwD = safeInputText("##df_add_swd", addSaveDoorBuf, 128, ketikSaveSeedForm)
        ImGui.PopItemWidth()
        if chSwD then addSaveDoorBuf = nvSwD end
        ImGui.EndTable()
    end
    uiGap(4)

    local actSw = uiActionBar("BorenDFSaveWActs", w, {
        { label = "+ Tambah##dfsw_add", style = "accent" },
        { label = "World Ini##dfsw_cur" },
        { label = "Paste##dfsw_pst" },
        { label = "Hapus##dfsw_del",    style = "muted" },
    })

    if actSw == 1 then
        local wStr = trimStr(addSaveBuf)
        local dStr = trimStr(addSaveDoorBuf)
        local comb = (wStr:find(":", 1, true) or wStr:find("|", 1, true) or dStr == "") and wStr or (wStr .. ":" .. dStr)
        local p = parseWorldLine(comb)
        if p then
            table.insert(saveWorlds, { name = p.name, door = p.door })
            setSaveWorldList(saveWorlds); addSaveBuf = ""; addSaveDoorBuf = ""
            formRevision = formRevision + 1
            uiNotice = "Tersimpan storage seed: " .. p.name
        else uiNotice = "Isi Save World dulu!" end
    elseif actSw == 2 then
        local curW = getCurrentWorldSafe()
        if curW ~= "" and curW ~= "EXIT" then
            addSaveBuf = curW
            formRevision = formRevision + 1
            uiNotice = "Terisi " .. curW .. " (isi Door ID jika ada lalu klik + Tambah)"
        else uiNotice = "Masuk ke world dulu!" end
    elseif actSw == 3 then
        local lines = uiReadClipLines()
        if #lines == 0 then
            uiNotice = "Clipboard kosong!"
        elseif #lines == 1 then
            local norm = lines[1]:gsub("|", ":")
            local wP, dP = norm:match("^([^:]+):(.*)$")
            if wP then addSaveBuf = trimStr(wP); addSaveDoorBuf = trimStr(dP or "")
            else addSaveBuf = lines[1]; addSaveDoorBuf = "" end
            formRevision = formRevision + 1
            uiNotice = "Paste ke form storage seed. Klik + Tambah."
        else
            local n = 0
            for _, ln in ipairs(lines) do
                local p = parseWorldLine(ln)
                if p then table.insert(saveWorlds, { name = p.name, door = p.door }); n = n + 1 end
            end
            if n > 0 then
                setSaveWorldList(saveWorlds)
                formRevision = formRevision + 1
                uiNotice = "Smart Paste: +" .. tostring(n) .. " storage seed (tersimpan)!"
            else uiNotice = "Format clipboard tidak valid." end
        end
    elseif actSw == 4 then
        local idx = DF.STATE.selected_sw
        if idx < 1 or idx > #saveWorlds then idx = #saveWorlds end
        if idx >= 1 and idx <= #saveWorlds then
            table.remove(saveWorlds, idx); DF.STATE.selected_sw = 0; setSaveWorldList(saveWorlds)
            formRevision = formRevision + 1
            uiNotice = (#saveWorlds == 0) and "Storage seed kosong (sisa dibiarkan di DF)." or "Storage seed dihapus."
        end
    end

    -- PEMISAH & LIST ITEM SAVE WORLD SEED (Seperti Trash List tapi untuk drop ke Save World)
    uiGap(16)
    if ImGui and ImGui.Separator then ImGui.Separator() end
    uiGap(8)

    local saveSeedList = getSaveSeedList()
    local function ketikSaveSeedItemForm()
        local idPre = cleanDialogField(addSaveSeedItemBuf)
        uiOpenDialog("boren_in_df_ssid", "Input Item ID Save World Seed", {
            { id = "f_sid", label = "Item ID (pisahkan koma jika banyak)", default = idPre, maxLen = 64 },
        }, "Masukkan ke Form", function(vals)
            local raw = cleanDialogField(vals.f_sid or vals["f_sid"])
            if raw ~= "" then
                addSaveSeedItemBuf = raw
            end
            formRevision = formRevision + 1
            uiNotice = "Form Item ID Save terisi: " .. tostring(addSaveSeedItemBuf)
        end)
    end

    uiSectionWithKetik("List Item Save World Seed (" .. tostring(#saveSeedList) .. " item)  [Default: Dirt Seed 3, Dirt 2]", "df_ktk_ssid", ketikSaveSeedItemForm)

    if ImGui.BeginTable("BorenDFSaveSeedTable", 2) then
        ImGui.TableSetupColumn("Item ID")
        ImGui.TableSetupColumn("Nama Item")
        ImGui.TableHeadersRow()
        if #saveSeedList == 0 then
            ImGui.TableNextRow()
            ImGui.TableSetColumnIndex(0); ImGui.Text("(Kosong)")
            ImGui.TableSetColumnIndex(1); ImGui.Text("Tidak ada item yang di-save ke world seed")
        else
            for i, sid in ipairs(saveSeedList) do
                ImGui.TableNextRow()
                ImGui.TableSetColumnIndex(0)
                local sel = (DF.STATE.selected_ssid == i)
                if autoBtn((sel and "> " or "") .. tostring(sid) .. "##dfssid" .. tostring(i)) then
                    DF.STATE.selected_ssid = sel and 0 or i
                end
                ImGui.TableSetColumnIndex(1)
                ImGui.Text(resolveDoorItemName(sid))
            end
        end
        ImGui.EndTable()
    end

    uiGap(4)
    ImGui.PushItemWidth(math.max(140, math.floor(w * 0.48)))
    local chSsid, nvSsid = safeInputText("##df_add_ssid", addSaveSeedItemBuf, 64, ketikSaveSeedItemForm)
    ImGui.PopItemWidth()
    if chSsid then addSaveSeedItemBuf = nvSsid end
    ImGui.SameLine()
    ImGui.Text("ID Item (cth: 3 atau 3,2)")
    uiGap(4)

    local actSsid = uiActionBar("BorenDFSaveSeedActs", w, {
        { label = "+ Tambah ID##dfssid_add", style = "accent" },
        { label = "Hapus##dfssid_del",       style = "muted" },
        { label = "Reset Default##dfssid_rst" },
    })
    if actSsid == 1 then
        local raw = trimStr(addSaveSeedItemBuf)
        local added = 0
        for tok in raw:gmatch("[^,%s;|\r\n]+") do
            local n = math.floor(tonumber(tok) or 0)
            if n > 0 then
                local exists = false
                for _, ex in ipairs(saveSeedList) do
                    if ex == n then exists = true; break end
                end
                if not exists then
                    table.insert(saveSeedList, n)
                    added = added + 1
                end
            end
        end
        if added > 0 then
            setSaveSeedList(saveSeedList)
            addSaveSeedItemBuf = ""
            formRevision = formRevision + 1
            uiNotice = "Save Seed List: +" .. tostring(added) .. " item tersimpan!"
        else
            uiNotice = "Masukkan angka Item ID dulu (cth: 3 atau 2)."
        end
    elseif actSsid == 2 then
        local idx = DF.STATE.selected_ssid
        if idx < 1 or idx > #saveSeedList then idx = #saveSeedList end
        if idx >= 1 and idx <= #saveSeedList then
            local rem = table.remove(saveSeedList, idx)
            DF.STATE.selected_ssid = 0
            setSaveSeedList(saveSeedList)
            formRevision = formRevision + 1
            uiNotice = "Dihapus dari Save Seed List: ID " .. tostring(rem)
        end
    elseif actSsid == 3 then
        DF.CFG.save_seed_list_raw = DEFAULT_SAVE_SEED_RAW
        DF.STATE.selected_ssid = 0
        DF.saveData()
        formRevision = formRevision + 1
        uiNotice = "Save Seed List di-reset ke default (3,2 - Dirt Seed & Dirt)."
    end
end
local function cyclePreset(presets, curId, delta)
    local curIdx = 1
    for i, p in ipairs(presets) do
        if p.id == tonumber(curId) then curIdx = i; break end
    end
    local nextIdx = curIdx + delta
    if nextIdx < 1 then nextIdx = #presets
    elseif nextIdx > #presets then nextIdx = 1 end
    return presets[nextIdx].id
end

local function renderSettingsSub()
    uiSection("Pengaturan Dirt Farm (Break & Build)", true)

    if ImGui.BeginTable("BorenDFSetOpts", 2) then
        renderOptRow("Break 3 Tile", function()
            if uiToggleBtn(DF.CFG.break_3_mode, "dfb3", "ON (3-Tile)", "OFF (1-Tile)") then
                DF.CFG.break_3_mode = not DF.CFG.break_3_mode; DF.saveData()
            end
        end)
        renderOptRow("Break Cave BG (14)", function()
            if uiToggleBtn(DF.CFG.break_cave_bg, "dfbg") then
                DF.CFG.break_cave_bg = not DF.CFG.break_cave_bg; DF.saveData()
            end
        end)
        renderOptRow("Break Lava & Tambal", function()
            if uiToggleBtn(DF.CFG.break_lava, "dflv") then
                DF.CFG.break_lava = not DF.CFG.break_lava; DF.saveData()
            end
        end)
        renderOptRow("Break Rock Platform", function()
            if uiToggleBtn(DF.CFG.break_rock, "dfrk") then
                DF.CFG.break_rock = not DF.CFG.break_rock; DF.saveData()
            end
        end)
        renderOptRow("Clear Sisi Pinggir", function()
            if uiToggleBtn(DF.CFG.clear_side, "dfc1") then
                DF.CFG.clear_side = not DF.CFG.clear_side; DF.saveData()
            end
        end)
        renderOptRow("Clear Lorong Baris", function()
            if uiToggleBtn(DF.CFG.clear_rows, "dfc2") then
                DF.CFG.clear_rows = not DF.CFG.clear_rows; DF.saveData()
            end
        end)
        renderOptRow("Bangun Dirt Atas", function()
            if uiToggleBtn(DF.CFG.build_upper_dirt, "dfud") then
                DF.CFG.build_upper_dirt = not DF.CFG.build_upper_dirt; DF.saveData()
            end
        end)
        renderOptRow("Auto Farm Dirt", function()
            if uiToggleBtn(DF.CFG.auto_farm_dirt, "dfaf") then
                DF.CFG.auto_farm_dirt = not DF.CFG.auto_farm_dirt; DF.saveData()
            end
        end)
        renderOptRow("Pasang Platform", function()
            if uiToggleBtn(DF.CFG.place_platform, "dfc3") then
                DF.CFG.place_platform = not DF.CFG.place_platform; DF.saveData()
            end
            if not DF.CFG.place_platform then
                ImGui.SameLine()
                ImGui.Text("  (OFF = pakai Dirt biasa)")
            end
        end)
        if DF.CFG.place_platform then
            renderOptRow("ID Platform", function()
                renderNumInput("df_plat_id", DF.CFG.platform_id, 1, 20000, 0, "", function(v)
                    DF.CFG.platform_id = v; saveDataDebounced()
                end)
                ImGui.SameLine()
                if autoBtn(" < ##dfp_1") then
                    local nid = cyclePreset(PLATFORM_PRESETS, DF.CFG.platform_id, -1)
                    DF.CFG.platform_id = nid; numBufs["df_plat_id"] = tostring(nid); DF.saveData()
                end
                ImGui.SameLine()
                if autoBtn(" > ##dfp_2") then
                    local nid = cyclePreset(PLATFORM_PRESETS, DF.CFG.platform_id, 1)
                    DF.CFG.platform_id = nid; numBufs["df_plat_id"] = tostring(nid); DF.saveData()
                end
                ImGui.SameLine()
                ImGui.Text(resolveDoorItemName(DF.CFG.platform_id))
            end)
        end
        renderOptRow("Auto Collect Drops", function()
            if uiToggleBtn(DF.CFG.auto_collect, "dfac") then
                DF.CFG.auto_collect = not DF.CFG.auto_collect; DF.saveData()
            end
        end)
        renderOptRow("Auto Trash Sampah", function()
            if uiToggleBtn(DF.CFG.auto_trash, "dfc4") then
                DF.CFG.auto_trash = not DF.CFG.auto_trash; DF.saveData()
            end
        end)
        renderOptRow("ModFly", function()
            if uiToggleBtn(DF.CFG.use_modfly, "dfc5") then
                DF.CFG.use_modfly = not DF.CFG.use_modfly; DF.saveData()
            end
        end)
        renderOptRow("Punch Delay", function()
            renderNumInput("df_punchd", DF.CFG.punch_delay, 60, 500, 20, "ms", function(v)
                DF.CFG.punch_delay = v; saveDataDebounced()
            end)
        end)
        renderOptRow("Place Delay", function()
            renderNumInput("df_placed", DF.CFG.place_delay, 60, 500, 20, "ms", function(v)
                DF.CFG.place_delay = v; saveDataDebounced()
            end)
        end)
        renderOptRow("Step Delay", function()
            renderNumInput("df_stepd", DF.CFG.step_delay, 40, 400, 10, "ms", function(v)
                DF.CFG.step_delay = v; saveDataDebounced()
            end)
        end)
        ImGui.EndTable()
    end

    -- TRASH LIST KUSTOM (Default: 14, 4, 5, 10, 11 — TANPA Cave BG Seed 15!)
    uiGap(10)
    local trashList = getTrashList()
    uiSectionWithKetik("Trash List (" .. tostring(#trashList) .. " item)  [Cave BG Seed 15 aman!]", "df_ktk_tr", function()
        uiOpenDialog("boren_in_df_tr", "Tambah Item ID ke Trash List", {
            { id = "f_tid", label = "Item ID (pisahkan koma jika banyak)", default = addTrashBuf, maxLen = 64 },
        }, "Tambah", function(vals)
            local raw = trimStr(vals.f_tid or "")
            local cur = getTrashList()
            local added = 0
            for tok in raw:gmatch("[^,%s;|\r\n]+") do
                local n = math.floor(tonumber(tok) or 0)
                if n > 0 then table.insert(cur, n); added = added + 1 end
            end
            if added > 0 then
                setTrashList(cur); addTrashBuf = ""
                uiNotice = "Trash List: +" .. tostring(added) .. " item ditambahkan."
            end
        end)
    end)
    uiNote(uiNotice)

    if ImGui.BeginTable("BorenDFTrashTable", 2) then
        ImGui.TableSetupColumn("Item ID")
        ImGui.TableSetupColumn("Nama Item")
        ImGui.TableHeadersRow()
        if #trashList == 0 then
            ImGui.TableNextRow()
            ImGui.TableSetColumnIndex(0); ImGui.Text("(Kosong)")
            ImGui.TableSetColumnIndex(1); ImGui.Text("Tidak ada item yang di-trash")
        else
            for i, tid in ipairs(trashList) do
                ImGui.TableNextRow()
                ImGui.TableSetColumnIndex(0)
                local sel = (DF.STATE.selected_tr == i)
                if autoBtn((sel and "> " or "") .. tostring(tid) .. "##dftr" .. tostring(i)) then
                    DF.STATE.selected_tr = sel and 0 or i
                end
                ImGui.TableSetColumnIndex(1)
                ImGui.Text(resolveDoorItemName(tid))
            end
        end
        ImGui.EndTable()
    end

    uiGap(4)
    local w = availX()
    ImGui.PushItemWidth(math.max(140, math.floor(w * 0.48)))
    local chTr, nvTr = safeInputText("##df_add_tr", addTrashBuf, 64)
    ImGui.PopItemWidth()
    if chTr then addTrashBuf = nvTr end
    ImGui.SameLine()
    ImGui.Text("ID Item (cth: 14 atau 4,5)")
    uiGap(4)

    local actTr = uiActionBar("BorenDFTrActs", w, {
        { label = "+ Tambah ID##dftr_add", style = "accent" },
        { label = "Hapus##dftr_del",       style = "muted" },
        { label = "Reset Default##dftr_rst" },
    })
    if actTr == 1 then
        local raw = trimStr(addTrashBuf)
        local added = 0
        for tok in raw:gmatch("[^,%s;|\r\n]+") do
            local n = math.floor(tonumber(tok) or 0)
            if n > 0 then table.insert(trashList, n); added = added + 1 end
        end
        if added > 0 then
            setTrashList(trashList); addTrashBuf = ""
            uiNotice = "Trash List: +" .. tostring(added) .. " item tersimpan!"
        else
            uiNotice = "Masukkan angka Item ID dulu (cth: 14)."
        end
    elseif actTr == 2 then
        local idx = DF.STATE.selected_tr
        if idx < 1 or idx > #trashList then idx = #trashList end
        if idx >= 1 and idx <= #trashList then
            local rem = table.remove(trashList, idx)
            DF.STATE.selected_tr = 0
            setTrashList(trashList)
            uiNotice = "Dihapus dari Trash List: ID " .. tostring(rem)
        end
    elseif actTr == 3 then
        DF.CFG.trash_list_raw = DEFAULT_TRASH_RAW
        DF.STATE.selected_tr = 0
        DF.saveData()
        uiNotice = "Trash List di-reset ke default (14,4,5,10,11 — Cave BG Seed 15 aman)."
    end
end

local function renderLockDoorSub()
    uiSectionWithKetik("Pengaturan Lock, Door ID (0,0) & Penghalang Kiri", "df_ktk_ld", function()
        uiOpenDialog("boren_in_df_ld", "Setting Door ID & Penghalang", {
            { id = "f_did",  label = "Item ID Door",       default = tostring(DF.CFG.id_door_itemid),      maxLen = 10 },
            { id = "f_txt",  label = "Teks Door ID",       default = tostring(DF.CFG.door_id),             maxLen = 24 },
            { id = "f_lbl",  label = "Label Door",         default = tostring(DF.CFG.door_label),          maxLen = 32 },
            { id = "f_bid",  label = "Item ID Penghalang", default = tostring(DF.CFG.blocker_door_itemid), maxLen = 10 },
        }, "Simpan", function(vals)
            local did = math.floor(tonumber(vals.f_did) or DF.CFG.id_door_itemid)
            local bid = math.floor(tonumber(vals.f_bid) or DF.CFG.blocker_door_itemid)
            if did > 0 then DF.CFG.id_door_itemid = did; numBufs["df_id_door"] = tostring(did) end
            if bid > 0 then DF.CFG.blocker_door_itemid = bid; numBufs["df_blk_id"] = tostring(bid) end
            DF.CFG.door_id = trimStr(vals.f_txt or DF.CFG.door_id)
            DF.CFG.door_label = trimStr(vals.f_lbl or DF.CFG.door_label)
            DF.saveData()
            uiNotice = "Tersimpan Door ID & Penghalang!"
        end)
    end, true)
    uiNote(uiNotice)

    if ImGui.BeginTable("BorenDFLockOpts", 2) then
        renderOptRow("Ignore Lock (Bukan Owner)", function()
            if uiToggleBtn(DF.CFG.ignore_lock, "dfl_ign_lock") then
                DF.CFG.ignore_lock = not DF.CFG.ignore_lock; DF.saveData()
            end
            ImGui.SameLine(); ImGui.TextDisabled("(Langsung buat DF tanpa setup lock/door)")
        end)
        renderOptRow("World Lock (242)", function()
            if uiToggleBtn(DF.CFG.auto_lock_wl, "dfl_wl") then
                DF.CFG.auto_lock_wl = not DF.CFG.auto_lock_wl; DF.saveData()
            end
            ImGui.SameLine(); ImGui.Text("  Allow Build:"); ImGui.SameLine()
            if uiToggleBtn(DF.CFG.wl_public, "dfl_wp") then
                DF.CFG.wl_public = not DF.CFG.wl_public; DF.saveData()
            end
        end)
        renderOptRow("Small Lock (202)", function()
            if uiToggleBtn(DF.CFG.auto_place_sl, "dfl_sl") then
                DF.CFG.auto_place_sl = not DF.CFG.auto_place_sl; DF.saveData()
            end
        end)
        renderOptRow("Signal Jammer (226)", function()
            if uiToggleBtn(DF.CFG.auto_place_jammer, "dfl_jm") then
                DF.CFG.auto_place_jammer = not DF.CFG.auto_place_jammer; DF.saveData()
            end
        end)

        renderOptRow("Pasang Door ID (0,0)", function()
            if uiToggleBtn(DF.CFG.use_id_door, "dfl_ud") then
                DF.CFG.use_id_door = not DF.CFG.use_id_door; DF.saveData()
            end
        end)
        renderOptRow("Jenis / ID Door", function()
            renderNumInput("df_id_door", DF.CFG.id_door_itemid, 1, 20000, 0, "", function(v)
                DF.CFG.id_door_itemid = v; DF.saveData()
            end)
            ImGui.SameLine()
            if autoBtn(" < ##dfl_dp1") then
                local nid = cyclePreset(DOOR_ID_PRESETS, DF.CFG.id_door_itemid, -1)
                DF.CFG.id_door_itemid = nid; numBufs["df_id_door"] = tostring(nid); DF.saveData()
            end
            ImGui.SameLine()
            if autoBtn(" > ##dfl_dp2") then
                local nid = cyclePreset(DOOR_ID_PRESETS, DF.CFG.id_door_itemid, 1)
                DF.CFG.id_door_itemid = nid; numBufs["df_id_door"] = tostring(nid); DF.saveData()
            end
            ImGui.SameLine()
            ImGui.Text(resolveDoorItemName(DF.CFG.id_door_itemid))
        end)
        renderOptRow("Teks Door ID", function()
            ImGui.PushItemWidth(150)
            local ch, nv = safeInputText("##df_door_id", DF.CFG.door_id, 64)
            ImGui.PopItemWidth()
            if ch then DF.CFG.door_id = nv; DF.saveData() end
        end)
        renderOptRow("Label Door", function()
            ImGui.PushItemWidth(150)
            local ch, nv = safeInputText("##df_door_lbl", DF.CFG.door_label, 64)
            ImGui.PopItemWidth()
            if ch then DF.CFG.door_label = nv; DF.saveData() end
        end)

        renderOptRow("Pasang Penghalang", function()
            if uiToggleBtn(DF.CFG.use_blocker_door, "dfl_ub") then
                DF.CFG.use_blocker_door = not DF.CFG.use_blocker_door; DF.saveData()
            end
        end)
        renderOptRow("Jenis / ID Penghalang", function()
            renderNumInput("df_blk_id", DF.CFG.blocker_door_itemid, 1, 20000, 0, "", function(v)
                DF.CFG.blocker_door_itemid = v; DF.saveData()
            end)
            ImGui.SameLine()
            if autoBtn(" < ##dfl_bp1") then
                local nid = cyclePreset(BLOCKER_PRESETS, DF.CFG.blocker_door_itemid, -1)
                DF.CFG.blocker_door_itemid = nid; numBufs["df_blk_id"] = tostring(nid); DF.saveData()
            end
            ImGui.SameLine()
            if autoBtn(" > ##dfl_bp2") then
                local nid = cyclePreset(BLOCKER_PRESETS, DF.CFG.blocker_door_itemid, 1)
                DF.CFG.blocker_door_itemid = nid; numBufs["df_blk_id"] = tostring(nid); DF.saveData()
            end
            ImGui.SameLine()
            ImGui.Text(resolveDoorItemName(DF.CFG.blocker_door_itemid))
        end)
        ImGui.EndTable()
    end

    uiGap(6)
    ImGui.Separator()
    uiGap(4)
    ImGui.TextWrapped("Preset Door: Door (12), Dungeon (30), Portal (544), House (224), Air Vent (2810). Preset Penghalang: Air Vent (2810), Door (12), Dungeon (30), Portcullis (60), House (224), Screen (858), Portal (544). Bisa ketik ID custom langsung di kotak.")
end

local function renderLogsSub()
    uiGap(3)
    if autoBtn(" Clear Logs ##df") then DF.STATE.logs = {} end
    uiGap(4)
    ImGui.Separator()
    uiGap(4)
    if #DF.STATE.logs == 0 then ImGui.Text("Belum ada log Dirt Farm.")
    else
        for i = 1, math.min(20, #DF.STATE.logs) do ImGui.TextWrapped(tostring(DF.STATE.logs[i])) end
    end
end

function DF.render(hub)
    if uiTabBtn("List World", activeSub == "worlds") then activeSub = "worlds" end
    ImGui.SameLine()
    if uiTabBtn("Find World", activeSub == "find") then activeSub = "find" end
    ImGui.SameLine()
    if uiTabBtn("Lock & Door", activeSub == "lockdoor") then activeSub = "lockdoor" end
    ImGui.SameLine()
    if uiTabBtn("Storage", activeSub == "storage") then activeSub = "storage" end
    ImGui.SameLine()
    if uiTabBtn("Settings", activeSub == "settings") then activeSub = "settings" end
    ImGui.SameLine()
    if uiTabBtn("Logs", activeSub == "logs") then activeSub = "logs" end
    uiGap(4)
    ImGui.Separator()

    if activeSub == "worlds" then renderWorldsSub()
    elseif activeSub == "find" then renderFindWorldSub()
    elseif activeSub == "lockdoor" then renderLockDoorSub()
    elseif activeSub == "storage" then renderStorageSub()
    elseif activeSub == "settings" then renderSettingsSub()
    else renderLogsSub() end
end

function DF.init(hub)
    HUB_REF = hub
    DF.loadData()
end

if AddHook then
    pcall(AddHook, "OnSendPacket", "boren_df_dlg_hook", onSendPacketHook)
elseif addHook then
    local function hookDispatch(p1, p2)
        return onSendPacketHook(p1, p2)
    end
    pcall(addHook, hookDispatch, "onsendpacket")
    pcall(addHook, hookDispatch, "on_sendpacket")
    pcall(addHook, "onsendpacket", hookDispatch)
    pcall(addHook, "on_sendpacket", hookDispatch)
end

return DF
