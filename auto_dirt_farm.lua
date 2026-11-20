---@diagnostic disable: undefined-global, lowercase-global
-- ============================================================================
-- AUTO DIRT FARM BY BOREN STORE - GROWLAUNCHER
-- Terintegrasi Penuh ke Menu Native Growlauncher (Kategori: "Boren Store")
-- ============================================================================

-- 1. SAFE PREFERENCES & JSON INITIALIZATION
local ok_pref, PreferencesMod = pcall(require, "Preferences")
if not (ok_pref and PreferencesMod) then
    ok_pref, PreferencesMod = pcall(require, "preferences")
end
if not (ok_pref and PreferencesMod) and Preferences then
    ok_pref = true
    PreferencesMod = Preferences
end
local ok_json, JsonMod = pcall(require, "json")

local saved = nil
if ok_pref and PreferencesMod and PreferencesMod.new then
    local ok_inst, inst = pcall(function()
        local p = PreferencesMod:new("boren_df_v3.json")
        if p and p.load then pcall(p.load, p) end
        return p
    end)
    if ok_inst and inst then
        saved = inst
    end
end

local function loadPref(key, default)
    if saved and saved.get then
        local ok, val = pcall(function() return saved:get(key, default) end)
        if ok and val ~= nil then
            return val
        end
    end
    return default
end

local function setPref(key, val)
    if not saved or not saved.set then return end
    pcall(function()
        saved:set(key, val)
        if saved.save then saved:save() end
    end)
end

local function savePrefs(cfg_table)
    if not saved or not saved.set or not saved.save then return end
    pcall(function()
        for k, v in pairs(cfg_table) do
            local vt = type(v)
            if vt == "string" or vt == "number" or vt == "boolean" then
                saved:set(k, v)
            end
        end
        -- Simpan daftar world sebagai string sederhana agar aman di Preferences Android
        local wParts = {}
        if type(cfg_table.world_list) == "table" then
            for _, entry in ipairs(cfg_table.world_list) do
                if type(entry) == "table" and entry.name and entry.name ~= "" then
                    local flag = entry.done and "1" or "0"
                    table.insert(wParts, tostring(entry.name) .. "|" .. tostring(entry.door or "") .. "|" .. flag)
                end
            end
        end
        saved:set("world_list_str", table.concat(wParts, ";"))

        -- Simpan daftar storage tool
        local tParts = {}
        if type(cfg_table.storage_tool_list) == "table" then
            for _, entry in ipairs(cfg_table.storage_tool_list) do
                if type(entry) == "table" and entry.name and entry.name ~= "" then
                    table.insert(tParts, tostring(entry.name) .. "|" .. tostring(entry.door or ""))
                end
            end
        end
        saved:set("storage_tool_list_str", table.concat(tParts, ";"))

        -- Simpan daftar storage seed
        local sParts = {}
        if type(cfg_table.storage_seed_list) == "table" then
            for _, entry in ipairs(cfg_table.storage_seed_list) do
                if type(entry) == "table" and entry.name and entry.name ~= "" then
                    table.insert(sParts, tostring(entry.name) .. "|" .. tostring(entry.door or ""))
                end
            end
        end
        saved:set("storage_seed_list_str", table.concat(sParts, ";"))
        saved:save()
    end)
end

-- Pure Lua JSON string escaper & encoder (fallback if json module is unavailable)
local function escapeJsonStr(s)
    s = tostring(s or "")
    s = s:gsub("\\", "\\\\")
    s = s:gsub('"', '\\"')
    s = s:gsub("\n", "\\n")
    s = s:gsub("\r", "\\r")
    s = s:gsub("\t", "\\t")
    return '"' .. s .. '"'
end

local function encodeJsonValue(v)
    local t = type(v)
    if t == "string" then
        return escapeJsonStr(v)
    elseif t == "number" or t == "boolean" then
        return tostring(v)
    elseif t == "table" then
        local isArr = (#v > 0) or (next(v) == nil)
        if isArr then
            local parts = {}
            for i = 1, #v do
                parts[i] = encodeJsonValue(v[i])
            end
            return "[" .. table.concat(parts, ",") .. "]"
        else
            local parts = {}
            for k, val in pairs(v) do
                table.insert(parts, escapeJsonStr(k) .. ":" .. encodeJsonValue(val))
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
    end
    return "null"
end

local function jsonEncode(val)
    return encodeJsonValue(val)
end

-- 2. PURE LUA ITEM ID CONSTANTS & DOOR CATEGORIES
-- STANDAR DATABASE RESMI GROWTOPIA / LUCIFER (100% PERSIS items.dat)
local ITEM = {
    BLANK          = 0,
    DIRT           = 2,
    DIRT_SEED      = 3,
    CAVE_DIRT      = 14,
    CAVE_SEED      = 15,
    LAVA           = 4,
    LAVA_SEED      = 5,
    MAIN_DOOR      = 6,
    WHITE_DOOR     = 6,
    BEDROCK        = 8,
    ROCK           = 10,
    ROCK_SEED      = 11,
    DOOR           = 12,
    WOODEN_DOOR    = 12,
    CAVE_BG        = 14,
    PUNCH          = 18,
    DUNGEON_DOOR   = 30,   -- Standar Lucifer: ID 30 (Dungeon Door)
    WRENCH         = 32,
    PORTCULLIS     = 60,   -- Standar Lucifer: ID 60 (Portcullis)
    WOOD_PLATFORM  = 102,  -- Standar Lucifer: ID 102 (Wooden Platform)
    SMALL_LOCK     = 202,
    BIG_LOCK       = 204,
    HUGE_LOCK      = 206,
    HOUSE_ENTRANCE = 224,  -- Standar Lucifer: ID 224 (House Entrance)
    JAMMER         = 226,
    WORLD_LOCK     = 242,
    PORTAL         = 544,  -- Standar Lucifer: ID 544 (Orange Portal)
    PORTAL_BLUE    = 546,  -- Standar Lucifer: ID 546 (Blue Portal)
    WATER          = 822,  -- Standar Lucifer: ID 822 (Water Bucket)
    SCREEN_DOOR    = 858,  -- Standar Lucifer: ID 858 (Screen Door)
    DIAMOND_LOCK   = 1796,
    AIR_VENT       = 2810, -- Standar Lucifer: ID 2810 (Air Vent)
    CAVE_BLAST     = 3562, -- Standar Lucifer: ID 3562 (Cave Blast)
}

local ITEM_NAME_CACHE = {
    [0]    = "Blank",
    [2]    = "Dirt",
    [3]    = "Dirt Seed",
    [4]    = "Lava",
    [5]    = "Lava Seed",
    [6]    = "Main Door",
    [8]    = "Bedrock",
    [10]   = "Rock",
    [11]   = "Rock Seed",
    [12]   = "Door",
    [13]   = "Door Seed",
    [14]   = "Cave Background",
    [15]   = "Cave Background Seed",
    [18]   = "Fist",
    [30]   = "Dungeon Door",
    [31]   = "Dungeon Door Seed",
    [32]   = "Wrench",
    [60]   = "Portcullis",
    [61]   = "Portcullis Seed",
    [102]  = "Wooden Platform",
    [103]  = "Wooden Platform Seed",
    [202]  = "Small Lock",
    [204]  = "Big Lock",
    [206]  = "Huge Lock",
    [224]  = "House Entrance",
    [225]  = "House Entrance Seed",
    [226]  = "Signal Jammer",
    [242]  = "World Lock",
    [544]  = "Orange Portal",
    [546]  = "Blue Portal",
    [822]  = "Water Bucket",
    [858]  = "Screen Door",
    [859]  = "Screen Door Seed",
    [1796] = "Diamond Lock",
    [2810] = "Air Vent",
    [2811] = "Air Vent Seed",
    [3562] = "Cave Blast",
}

local DOOR_ID_PRESETS = {
    { id = 12,   name = "Door (12)" },
    { id = 30,   name = "Dungeon Door (30)" },
    { id = 544,  name = "Orange Portal (544)" },
    { id = 224,  name = "House Entrance (224)" },
    { id = 2810, name = "Air Vent (2810)" },
}

local BLOCKER_DOOR_PRESETS = {
    { id = 2810, name = "Air Vent (2810)" },
    { id = 12,   name = "Door (12)" },
    { id = 30,   name = "Dungeon Door (30)" },
    { id = 60,   name = "Portcullis (60)" },
    { id = 224,  name = "House Entrance (224)" },
    { id = 858,  name = "Screen Door (858)" },
    { id = 544,  name = "Orange Portal (544)" },
}

local KNOWN_ID_DOOR_IDS = {
    [12] = true, [30] = true, [544] = true, [546] = true, [224] = true, [2810] = true,
}

local KNOWN_BLOCKER_IDS = {
    [2810] = true, [12] = true, [30] = true, [60] = true, [224] = true, [858] = true, [544] = true, [546] = true,
}

local OTHER_LOCKS = {
    [202] = true, [204] = true, [206] = true, [242] = true,
    [1796] = true, [2950] = true, [4994] = true, [5814] = true,
    [7188] = true, [10410] = true
}

local function resolveItemName(id)
    id = tonumber(id) or 0
    if id <= 0 then return "None" end
    -- 1. Cek native GrowLauncher engine (langsung baca items.dat aktif persis Lucifer)
    if getItemInfoByID then
        local ok, info = pcall(getItemInfoByID, id)
        if ok and info and type(info.name) == "string" and info.name ~= "" and not info.name:find("Unknown") then
            return info.name
        end
    end
    if growtopia and growtopia.getItemName then
        local ok, n = pcall(growtopia.getItemName, id)
        if ok and n and n ~= "" and not tostring(n):find("Unknown") then
            return tostring(n)
        end
    end
    if getItemName then
        local ok, n = pcall(getItemName, id)
        if ok and n and n ~= "" and not n:find("Unknown") then
            return n
        end
    end
    -- 2. Fallback: Standar Cache Lucifer
    if ITEM_NAME_CACHE[id] then
        return ITEM_NAME_CACHE[id]
    end
    return "Item #" .. tostring(id)
end

local function isDoorOrEntranceItem(id, name)
    if KNOWN_BLOCKER_IDS[id] or KNOWN_ID_DOOR_IDS[id] then
        return true
    end
    local lower = tostring(name or ""):lower()
    if lower:find("door") or lower:find("entrance") or lower:find("portal") or lower:find("portcullis") or lower:find("gate") then
        return true
    end
    return false
end

-- 3. CONFIGURATION & RUNTIME STATE
local function parseWorldEntryToken(rawToken, defaultDoor)
    local clean = tostring(rawToken or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if clean == "" or clean:sub(1, 1) == "#" then return nil end

    -- Dukung format: WORLD:ID, WORLD|ID, plus opsional status |1 / |0 / |DONE / |ANTRI / :DONE
    local body = clean
    local isDone = false
    local statusTag = nil

    local b1, tag1 = clean:match("^(.-)[|:](DONE)$")
    if not b1 then b1, tag1 = clean:match("^(.-)[|:](done)$") end
    if not b1 then b1, tag1 = clean:match("^(.-)[|:](PROSES)$") end
    if not b1 then b1, tag1 = clean:match("^(.-)[|:](ANTRI)$") end
    if not b1 then b1, tag1 = clean:match("^(.-)|([01])$") end
    if b1 and tag1 then
        body = b1
        statusTag = tag1:upper()
        isDone = (statusTag == "DONE" or statusTag == "1")
    end

    local wName, dId = body:match("^([^|:]+)[|:](.*)$")
    if not wName then
        wName = body
        dId = defaultDoor or ""
    end
    wName = wName:upper():gsub("%s+", "")
    dId = (dId or ""):gsub("%s+", "")
    if wName == "" then return nil end

    return {
        name = wName,
        door = dId,
        done = isDone,
        status = isDone and "DONE" or "ANTRI",
    }
end

local function parseSavedWorldList()
    local list = {}
    local rawStr = loadPref("world_list_str", "")
    if type(rawStr) == "string" and rawStr ~= "" then
        for token in rawStr:gmatch("[^;\r\n]+") do
            local entry = parseWorldEntryToken(token, "")
            if entry then
                table.insert(list, entry)
            end
        end
    end
    return list
end

local function parseSavedStorageList(prefKey, fallbackWorld, fallbackDoor)
    local list = {}
    local rawStr = loadPref(prefKey, "")
    if type(rawStr) == "string" and rawStr ~= "" then
        for token in rawStr:gmatch("[^;\r\n]+") do
            local clean = token:gsub("^%s+", ""):gsub("%s+$", "")
            if clean ~= "" then
                local wName, dId = clean:match("^([^|:]+)[|:](.*)$")
                if not wName then
                    wName = clean
                    dId = ""
                end
                wName = wName:upper():gsub("%s+", "")
                dId = (dId or ""):gsub("%s+", "")
                if wName ~= "" and wName ~= "EXIT" and wName ~= "0" then
                    table.insert(list, { name = wName, door = dId })
                end
            end
        end
    end
    if #list == 0 and fallbackWorld and fallbackWorld ~= "" and fallbackWorld ~= "EXIT" and fallbackWorld ~= "0" then
        table.insert(list, { name = fallbackWorld:upper():gsub("%s+", ""), door = (fallbackDoor or ""):gsub("%s+", "") })
    end
    return list
end

local CFG = {
    -- World Selection Mode ("manual" or "random")
    world_mode          = loadPref("world_mode", "manual"),
    random_length       = tonumber(loadPref("random_length", 6)) or 6,
    random_use_numbers  = loadPref("random_use_numbers", false),
    random_target_count = tonumber(loadPref("random_target_count", 5)) or 5,
    world_folder_mode   = tostring(loadPref("world_folder_mode", "download") or "download"),
    world_custom_folder = tostring(loadPref("world_custom_folder", "") or ""),
    world_file_name     = tostring(loadPref("world_file_name", "boren_df_worlds.txt") or "boren_df_worlds.txt"),
    world_list          = parseSavedWorldList(),
    manual_world_text   = tostring(loadPref("manual_world_text", "") or ""),
    manual_door_text    = tostring(loadPref("manual_door_text", "") or ""),

    -- Storage Worlds
    storage_pack_world  = tostring(loadPref("storage_pack_world", "") or ""),
    storage_pack_door   = tostring(loadPref("storage_pack_door", "") or ""),
    storage_tool_list   = parseSavedStorageList("storage_tool_list_str", tostring(loadPref("storage_pack_world", "") or ""), tostring(loadPref("storage_pack_door", "") or "")),

    storage_seed_world  = tostring(loadPref("storage_seed_world", "") or ""),
    storage_seed_door   = tostring(loadPref("storage_seed_door", "") or ""),
    storage_seed_list   = parseSavedStorageList("storage_seed_list_str", tostring(loadPref("storage_seed_world", "") or ""), tostring(loadPref("storage_seed_door", "") or "")),
    save_seed_threshold = tonumber(loadPref("save_seed_threshold", 180)) or 180,

    -- Security & Door Placement Options (Exact Gambar 2 Layout)
    ignore_lock         = loadPref("ignore_lock", false),
    use_wl              = loadPref("use_wl", true),
    wl_public           = loadPref("wl_public", true),       -- WL set PUBLIC = ON (1)
    use_sl              = loadPref("use_sl", true),
    sl_ignore_air       = loadPref("sl_ignore_air", true),   -- SL Ignore Empty Air = ON (1)
    sl_public           = loadPref("sl_public", false),      -- SL Public = OFF (0 / Private)
    use_jammer          = loadPref("use_jammer", true),

    -- Separate Door for ID & Door Penghalang (Blocker/Entrance)
    use_id_door         = loadPref("use_id_door", true),
    id_door_itemid      = tonumber(loadPref("id_door_itemid", 12)) or 12,
    door_id             = tostring(loadPref("door_id", "DF123") or "DF123"),
    door_label          = tostring(loadPref("door_label", "BOREN STORE") or "BOREN STORE"),

    use_blocker_door    = loadPref("use_blocker_door", true),
    blocker_door_itemid = tonumber(loadPref("blocker_door_itemid", 2810)) or 2810,
    delay_tele_door     = tonumber(loadPref("delay_tele_door", 1500)) or 1500,

    -- Seed Saving Options
    save_dirt_seed      = loadPref("save_dirt_seed", true),
    save_cave_seed      = loadPref("save_cave_seed", true),
    save_lava_seed      = loadPref("save_lava_seed", true),
    save_rock_seed      = loadPref("save_rock_seed", true),
    save_lava_block     = loadPref("save_lava_block", false),
    use_custom_save     = loadPref("use_custom_save", false),
    custom_save_itemid  = tonumber(loadPref("custom_save_itemid", 3)) or 3,

    -- DF Construction & Safety Options
    auto_collect        = loadPref("auto_collect", true),
    collect_range       = tonumber(loadPref("collect_range", 3)) or 3,
    use_anti_lava       = loadPref("use_anti_lava", true),
    use_modfly          = loadPref("use_modfly", true),
    auto_reconnect      = loadPref("auto_reconnect", true),
    clear_sides         = loadPref("clear_sides", true),
    break_3_mode        = loadPref("break_3_mode", false),
    break_cave_bg       = loadPref("break_cave_bg", true),
    break_lava          = loadPref("break_lava", true),
    break_rock          = loadPref("break_rock", false),
    build_upper         = loadPref("build_upper", true),
    auto_farm_dirt      = loadPref("auto_farm_dirt", true),
    max_plant_dirt      = tonumber(loadPref("max_plant_dirt", 50)) or 50,
    auto_trash_junk     = loadPref("auto_trash_junk", true),
    trash_threshold     = tonumber(loadPref("trash_threshold", 150)) or 150,
    trash_list_str      = tostring(loadPref("trash_list_str", "4,14,10") or "4,14,10"),
    trash_picker_itemid = tonumber(loadPref("trash_picker_itemid", 4)) or 4,

    -- Platform di jalur naik-turun pinggir (x = 1 atau x = 98)
    use_platform        = loadPref("use_platform", false),
    platform_itemid     = tonumber(loadPref("platform_itemid", 102)) or 102,
    plat_left           = loadPref("plat_left", true),
    plat_right          = loadPref("plat_right", false),

    -- Delays (ms)
    delay_break         = tonumber(loadPref("delay_break", 150)) or 150,
    delay_place         = tonumber(loadPref("delay_place", 150)) or 150,
    delay_walk          = tonumber(loadPref("delay_walk", 160)) or 160,
    delay_warp          = tonumber(loadPref("delay_warp", 4500)) or 4500,
    delay_clear_sides   = tonumber(loadPref("delay_clear_sides", 120)) or 120,
}

if type(CFG.world_list) ~= "table" then
    CFG.world_list = {}
end

local STATE = {
    running            = false,
    paused             = false,
    status_text        = "Siap dijalankan",
    current_world      = "-",
    current_step       = "Idle",
    worlds_completed   = 0,
    logs               = {},
    buf_world_name     = tostring(CFG.manual_world_text or ""),
    buf_world_door     = tostring(CFG.manual_door_text or ""),
    cached_inv         = {},
    cached_doors       = {},
    suppress_dialog         = false,
    last_dialog_text        = "",
    last_dialog_name        = "",
    last_dialog_seq         = 0,
    runtime_hooks_installed = false,
    saving_storage          = false,
    anti_take_active        = false,
    df_dropped_spots        = {},
    error_logs              = {},
    error_count             = 0,
    show_mini_console       = false,
    console_errors_only     = false,
    active_world            = "",
    active_door             = "",
    reconnecting            = false,
    reconnected_restart     = false,
    resume_world_override   = nil,
    resume_door_override    = nil,
    random_done_count       = 0,
}

local refreshNativeDisplayLists -- forward declaration
local updatePowerStatusList     -- forward declaration
local updateWorldDisplayList    -- forward declaration
local updateToolStorageDisplayList -- forward declaration
local updateSeedStorageDisplayList -- forward declaration
local updateFileInfoDisplayList -- forward declaration
local ensureOnlineInWorld       -- forward declaration
local openFileBrowserManagerDialog -- forward declaration
local openPasteWorldListDialog     -- forward declaration
local openCopyAllWorldsDialog      -- forward declaration
local openUnifiedToolManager       -- forward declaration
local openEditToolEntryDialog      -- forward declaration
local openUnifiedSeedManager       -- forward declaration
local openEditSeedEntryDialog      -- forward declaration
local parseAndValidateWorldBatch   -- forward declaration
local parseStorageBatchFromString  -- forward declaration

local function isErrorMessage(msg)
    local low = tostring(msg or ""):lower()
    return low:find("error", 1, true) ~= nil
        or low:find("gagal", 1, true) ~= nil
        or low:find("warn", 1, true) ~= nil
        or low:find("disconnect", 1, true) ~= nil
        or low:find("terputus", 1, true) ~= nil
        or low:find("kurang", 1, true) ~= nil
        or low:find("ui err", 1, true) ~= nil
end

local function addLog(msg)
    local timestamp = os.date("%H:%M:%S")
    local textStr = tostring(msg)
    local entry = string.format("[%s] %s", timestamp, textStr)
    table.insert(STATE.logs, 1, entry)
    if #STATE.logs > 60 then
        table.remove(STATE.logs)
    end
    if isErrorMessage(textStr) then
        STATE.error_count = (STATE.error_count or 0) + 1
        table.insert(STATE.error_logs, 1, entry)
        if #STATE.error_logs > 40 then
            table.remove(STATE.error_logs)
        end
    end
    if LogToConsole then
        pcall(LogToConsole, "`9[Boren Store DF] `0" .. textStr)
    end
end

local function setStatus(step, detail)
    STATE.current_step = step or STATE.current_step
    if detail then
        STATE.status_text = detail
        addLog(step .. " -> " .. detail)
    else
        STATE.status_text = step
        addLog(step)
    end
    if updatePowerStatusList then
        pcall(updatePowerStatusList)
    end
end

local function persistConfig()
    savePrefs(CFG)
end

local function formatWorldListAsText(separatorChar)
    local sep = separatorChar or ":"
    local lines = {}
    for _, entry in ipairs(CFG.world_list) do
        if entry and entry.name and entry.name ~= "" then
            local base = (entry.door and entry.door ~= "") and (entry.name .. sep .. entry.door) or entry.name
            if entry.done then
                base = base .. "|DONE"
            end
            table.insert(lines, base)
        end
    end
    return table.concat(lines, "\n")
end

-- Parse & add one or more world entries from text (supports "WORLD1:DOOR1", "WORLD1|DOOR1", comma/semicolon/newline separated)
local function addManualWorldsFromString(rawWorldStr, defaultDoorStr, clearExisting, keepRandomMode)
    local s = tostring(rawWorldStr or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local defDoor = tostring(defaultDoorStr or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if s == "" then
        if clearExisting then CFG.world_list = {} end
        return 0
    end

    if clearExisting then
        CFG.world_list = {}
    end

    local addedCount = 0
    for token in s:gmatch("[^,;\r\n]+") do
        local parsed = parseWorldEntryToken(token, defDoor)
        if parsed then
            local found = false
            for _, existing in ipairs(CFG.world_list) do
                if existing.name == parsed.name then
                    existing.door = parsed.door
                    existing.done = parsed.done
                    existing.status = parsed.status
                    found = true
                    break
                end
            end
            if not found then
                table.insert(CFG.world_list, parsed)
            end
            addedCount = addedCount + 1
        end
    end

    if addedCount > 0 then
        if not keepRandomMode then
            CFG.world_mode = "manual"
        end
        persistConfig()
    end
    return addedCount
end

local function getWorldEntryStatusTag(entry)
    if entry and entry.done then return "DONE" end
    if STATE.running and entry and (STATE.active_world == entry.name or entry.status == "PROSES") then
        return "PROSES"
    end
    return "ANTRI"
end

local function buildWorldDisplayRows()
    local wList = {}
    for i, entry in ipairs(CFG.world_list) do
        local st = getWorldEntryStatusTag(entry)
        local dInfo = (entry.door and entry.door ~= "") and ("Door: " .. entry.door) or "White Door"
        table.insert(wList, { string.format("%d. %s [%s]", i, entry.name, st), dInfo })
    end
    if #wList == 0 then
        table.insert(wList, { "List world masih kosong", "Ketik Nama World lalu klik + Tambah" })
    end
    return wList
end

updateWorldDisplayList = function()
    if not editValue then return end
    pcall(editValue, "df_world_display_list", jsonEncode(buildWorldDisplayRows()))
end

local function buildToolStorageDisplayRows()
    local tList = {}
    for i, entry in ipairs(CFG.storage_tool_list or {}) do
        local dInfo = (entry.door and entry.door ~= "") and ("Door: " .. entry.door) or "White Door"
        table.insert(tList, { string.format("%d. %s", i, entry.name), dInfo })
    end
    if #tList == 0 then
        table.insert(tList, { "Gudang Alat masih kosong", "Ketik Nama World lalu klik + Tambah" })
    end
    return tList
end

updateToolStorageDisplayList = function()
    if not editValue then return end
    pcall(editValue, "df_tool_storage_list", jsonEncode(buildToolStorageDisplayRows()))
end

local function buildSeedStorageDisplayRows()
    local sList = {}
    for i, entry in ipairs(CFG.storage_seed_list or {}) do
        local dInfo = (entry.door and entry.door ~= "") and ("Door: " .. entry.door) or "White Door"
        table.insert(sList, { string.format("%d. %s", i, entry.name), dInfo })
    end
    if #sList == 0 then
        table.insert(sList, { "Gudang Seed masih kosong", "Ketik Nama World lalu klik + Tambah" })
    end
    return sList
end

updateSeedStorageDisplayList = function()
    if not editValue then return end
    pcall(editValue, "df_seed_storage_list", jsonEncode(buildSeedStorageDisplayRows()))
end

parseStorageBatchFromString = function(rawText)
    local list = {}
    if type(rawText) ~= "string" or rawText == "" then return list end
    local cleaned = rawText:gsub("[\"\'%[%]%(%)]", " "):gsub("\t", " ")
    for part in cleaned:gmatch("[^\r\n;,]+") do
        local trimmed = part:gsub("^%s+", ""):gsub("%s+$", "")
        if trimmed ~= "" then
            local normToken = trimmed:gsub("%s*[:|]%s*", ":")
            local parsed = parseWorldEntryToken(normToken, "")
            if parsed and parsed.name and parsed.name ~= "" and parsed.name ~= "EXIT" and parsed.name ~= "0" then
                local validName = parsed.name:match("^([%w_]+)$")
                if validName and #validName >= 1 and #validName <= 24 then
                    local dId = parsed.door and parsed.door:match("([%w_]+)") or ""
                    table.insert(list, { name = validName:upper(), door = dId })
                end
            end
        end
    end
    return list
end

local function isWorldInQueue(worldName)
    local wTarget = tostring(worldName or ""):upper():gsub("%s+", "")
    if wTarget == "" or type(CFG.world_list) ~= "table" then return false end
    for _, e in ipairs(CFG.world_list) do
        if type(e) == "table" and tostring(e.name or ""):upper():gsub("%s+", "") == wTarget then
            return true
        end
    end
    return false
end

-- Parsing & validasi cerdas untuk Quick Paste & File Import
-- Mampu menangani koma ngaco, spasi acak, tanda kutip, format WORLD:ID maupun WORLD|ID, dsb.
parseAndValidateWorldBatch = function(rawText, replaceMode)
    if type(rawText) ~= "string" or rawText == "" then
        return 0, 0, 0, "Teks kosong! Silakan tempel daftar world terlebih dahulu."
    end

    -- 1. Bersihkan tanda kutip, kurung siku, dan tab yang sering ikut saat copas
    local cleaned = rawText:gsub("[\"\'%[%]%(%)]", " "):gsub("\t", " ")

    -- 2. Pecah string berdasarkan newline, koma, atau titik-koma (termasuk koma berturut-turut ,,)
    local tokens = {}
    for part in cleaned:gmatch("[^\r\n;,]+") do
        local trimmed = part:gsub("^%s+", ""):gsub("%s+$", "")
        if trimmed ~= "" then
            table.insert(tokens, trimmed)
        end
    end

    if #tokens == 0 then
        return 0, 0, 0, "Tidak ada data world yang valid ditemukan."
    end

    local candidateList = {}
    local seenInBatch = {}
    local duplicateCount = 0
    local ignoredCount = 0

    for _, token in ipairs(tokens) do
        -- Bersihkan spasi di sekitar delimiter : atau |
        -- Contoh: "WORLD1  :  DOOR1" -> "WORLD1:DOOR1"
        local normToken = token:gsub("%s*[:|]%s*", ":")

        -- Parse menggunakan parseWorldEntryToken
        local parsed = parseWorldEntryToken(normToken, "")
        if parsed and parsed.name and parsed.name ~= "" then
            local wName = parsed.name
            -- Validasi karakter & panjang nama world Growtopia:
            -- Hanya huruf A-Z, angka 0-9, atau underscore _; panjang 1-24 karakter
            local validName = wName:match("^([%w_]+)$")
            if validName and #validName >= 1 and #validName <= 24 then
                parsed.name = validName:upper()
                -- Validasi Door ID (jika ada, bersihkan karakter aneh)
                if parsed.door and parsed.door ~= "" then
                    parsed.door = parsed.door:match("([%w_]+)") or ""
                end

                if seenInBatch[parsed.name] then
                    duplicateCount = duplicateCount + 1
                else
                    seenInBatch[parsed.name] = true
                    table.insert(candidateList, parsed)
                end
            else
                ignoredCount = ignoredCount + 1
            end
        else
            ignoredCount = ignoredCount + 1
        end
    end

    if #candidateList == 0 then
        return 0, duplicateCount, ignoredCount, "Tidak ada world valid yang dapat ditambahkan."
    end

    local addedCount = 0
    if replaceMode then
        CFG.world_list = {}
        for _, entry in ipairs(candidateList) do
            table.insert(CFG.world_list, entry)
            addedCount = addedCount + 1
        end
    else
        for _, entry in ipairs(candidateList) do
            if not isWorldInQueue(entry.name) then
                table.insert(CFG.world_list, entry)
                addedCount = addedCount + 1
            else
                duplicateCount = duplicateCount + 1
            end
        end
    end

    if addedCount > 0 then
        CFG.world_mode = "manual"
    end

    persistConfig()
    if updateWorldDisplayList then pcall(updateWorldDisplayList) end
    if updateFileInfoDisplayList then pcall(updateFileInfoDisplayList) end

    local summaryMsg = string.format("Berhasil input %d world! (Duplikat: %d | Dilewati: %d | Total Antrean: %d)",
        addedCount, duplicateCount, ignoredCount, #CFG.world_list)
    return addedCount, duplicateCount, ignoredCount, summaryMsg
end

local FOLDER_PRESET_DEFS = {
    { id = "download",   label = "Download",   desc = "Folder Download HP",       full = "/storage/emulated/0/Download/" },
    { id = "documents",  label = "Documents",  desc = "Folder Documents HP",      full = "/storage/emulated/0/Documents/" },
    { id = "script_gl",  label = "Script GL",  desc = "Folder Script GL (Media)", full = "/storage/emulated/0/Android/media/launcher.powerkuy.growlauncher/ScriptLua/" },
    { id = "script_gl6", label = "GL Files",   desc = "Folder Script GL (Files)", full = "/storage/emulated/0/Android/data/launcher.powerkuy.growlauncher/files/ScriptLua/" },
    { id = "internal",   label = "Internal SD",desc = "Root Memori Internal HP",  full = "/storage/emulated/0/" },
    { id = "custom",     label = "Custom",     desc = "Custom Folder Path",       full = "" }
}

local function getFolderPresetInfo(modeId)
    modeId = tostring(modeId or "download")
    for _, p in ipairs(FOLDER_PRESET_DEFS) do
        if p.id == modeId then return p end
    end
    return FOLDER_PRESET_DEFS[1]
end

local function isSystemWindows()
    return (package.config and package.config:sub(1, 1) == "\\")
end

-- Resolve path file .txt menjadi full absolute path di Folder Download HP / PC (Paten)
local function resolveWorldFilePath(rawFileName, optFolderMode, optCustomDir)
    local fn = tostring(rawFileName or CFG.world_file_name or "boren_df_worlds.txt"):gsub("^%s+", ""):gsub("%s+$", "")
    if fn == "" then fn = "boren_df_worlds.txt" end
    if not fn:lower():match("%.txt$") then fn = fn .. ".txt" end

    -- Jika sudah merupakan full path (/ atau path absolut)
    if fn:sub(1, 1) == "/" or fn:match("^%a:[/\\]") then
        local dir = fn:match("^(.*[/\\])") or ""
        local nameOnly = fn:sub(#dir + 1)
        return fn, dir, nameOnly
    end

    local dir = ""
    if isSystemWindows() then
        if (optFolderMode == "custom" or CFG.world_folder_mode == "custom") and (optCustomDir or CFG.world_custom_folder or "") ~= "" then
            dir = tostring(optCustomDir or CFG.world_custom_folder)
        else
            local userProfile = os.getenv("USERPROFILE")
            if userProfile and userProfile ~= "" then
                local winDl = userProfile:gsub("\\", "/") .. "/Downloads/"
                local okD, fhD = pcall(io.open, winDl .. "test_exist.tmp", "w")
                if okD and fhD then
                    fhD:close()
                    pcall(os.remove, winDl .. "test_exist.tmp")
                    dir = winDl
                else
                    dir = ""
                end
            else
                dir = ""
            end
        end
    else
        if (optFolderMode == "custom" or CFG.world_folder_mode == "custom") and (optCustomDir or CFG.world_custom_folder or "") ~= "" then
            dir = tostring(optCustomDir or CFG.world_custom_folder)
        else
            -- Folder paten HP: Download
            dir = "/storage/emulated/0/Download/"
        end
    end

    if dir ~= "" and not (dir:sub(-1) == "/" or dir:sub(-1) == "\\") then
        dir = dir .. "/"
    end

    return dir .. fn, dir, fn
end

-- Cek apakah file benar-benar ada di storage HP/PC beserta info jumlah baris/world
local function checkWorldFileStatus(fullPath)
    if not io or not io.open then
        return false, "I/O module tidak aktif", 0
    end
    local okF, fh = pcall(io.open, fullPath, "r")
    if not okF or not fh then
        return false, "File belum ada", 0
    end
    local worldCnt = 0
    for line in fh:lines() do
        local cl = line:gsub("%s+", "")
        if cl ~= "" and not cl:match("^#") and not cl:match("^//") then
            worldCnt = worldCnt + 1
        end
    end
    fh:close()
    return true, string.format("Ada (%d world)", worldCnt), worldCnt
end

updateFileInfoDisplayList = function()
    if not editValue then return end
    local fullPath, dir, fn = resolveWorldFilePath()
    local okF, statusMsg = checkWorldFileStatus(fullPath)
    local dirDisplay = (dir ~= "") and dir or "(Folder Download / Game)"
    local rows = {
        { "📁 Folder HP (Paten)", dirDisplay },
        { "📄 File Backup", fn },
        { "🔍 Status File", okF and ("`2[ADA] `w" .. statusMsg) or ("`4[BELUM DISIMPAN] `oKlik 'Simpan ke Download'") },
        { "Path Lengkap", fullPath }
    }
    pcall(editValue, "df_file_info_list", jsonEncode(rows))
end

local function recordFileInHistory(fileName)
    if not fileName or fileName == "" then return end
    local cur = tostring(loadPref("file_history_str", "") or "")
    local list = {}
    local seen = { [fileName] = true }
    table.insert(list, fileName)
    for name in cur:gmatch("[^;\r\n]+") do
        local c = name:gsub("^%s+", ""):gsub("%s+$", "")
        if c ~= "" and not seen[c] then
            seen[c] = true
            table.insert(list, c)
            if #list >= 12 then break end
        end
    end
    setPref("file_history_str", table.concat(list, ";"))
end

local function parseSavedFileHistory()
    local hist = tostring(loadPref("file_history_str", "") or "")
    local list = {}
    for h in hist:gmatch("[^;\r\n]+") do
        local hc = h:gsub("^%s+", ""):gsub("%s+$", "")
        if hc ~= "" then table.insert(list, hc) end
    end
    return list
end

-- Scan file .txt yang ada di folder HP (via popen atau history fallback)
local function scanFolderTxtFiles(dirPath)
    local files = {}
    local seen = {}
    local targetDir = dirPath or ""

    if io and io.popen and targetDir ~= "" then
        local cmd = isSystemWindows()
            and ('dir /b /a-d "' .. targetDir:gsub("/", "\\") .. '\\*.txt" 2>nul')
            or ('ls -1 "' .. targetDir .. '" 2>/dev/null')
        local okP, pipe = pcall(io.popen, cmd)
        if okP and pipe then
            for line in pipe:lines() do
                local clean = line:gsub("[\r\n]", ""):gsub("^%s+", ""):gsub("%s+$", "")
                if clean:lower():match("%.txt$") and not seen[clean] then
                    seen[clean] = true
                    local okF, msg, cnt = checkWorldFileStatus(targetDir .. clean)
                    table.insert(files, { name = clean, path = targetDir .. clean, count = cnt, info = msg, exists = okF })
                end
            end
            pipe:close()
        end
    end

    local checkCandidates = { CFG.world_file_name or "boren_df_worlds.txt" }
    for _, h in ipairs(parseSavedFileHistory()) do
        table.insert(checkCandidates, h)
    end

    for _, fn in ipairs(checkCandidates) do
        if not fn:lower():match("%.txt$") then fn = fn .. ".txt" end
        if not seen[fn] then
            local testP = (targetDir ~= "") and (targetDir .. fn) or fn
            local okF, msg, cnt = checkWorldFileStatus(testP)
            if okF then
                seen[fn] = true
                table.insert(files, { name = fn, path = testP, count = cnt, info = msg, exists = true })
            end
        end
    end

    return files, targetDir
end

local function saveWorldListToStorage(showDialogPopup)
    persistConfig()
    local exportTxt = formatWorldListAsText(":")
    local fullPath, dir, fName = resolveWorldFilePath()
    recordFileInHistory(fName)

    local savedFile = false
    if io and io.open then
        local okF, fh = pcall(io.open, fullPath, "w")
        if okF and fh then
            pcall(function()
                fh:write(exportTxt .. (exportTxt ~= "" and "\n" or ""))
                fh:close()
            end)
            savedFile = true
        end
    end
    if writeToLocal then
        pcall(writeToLocal, fullPath, exportTxt)
        pcall(writeToLocal, fName, exportTxt)
    end

    local summary = string.format("Tersimpan %d world ke %s & Preferences.", #CFG.world_list, savedFile and fullPath or fName)
    addLog(summary)
    if sendNotification then pcall(sendNotification, summary) end
    if showDialogPopup and sendDialog then
        pcall(sendDialog, {
            title = "Save List World (" .. tostring(#CFG.world_list) .. ")",
            alias = "boren_df_save_worlds",
            message = summary .. "\n\nPath File HP:\n" .. fullPath .. "\n\nIsi (world:id):\n" .. (exportTxt ~= "" and exportTxt or "(kosong)"),
            confirm = "OK"
        })
    end
    if updateFileInfoDisplayList then pcall(updateFileInfoDisplayList) end
    return true, summary
end

local function loadWorldListFromStorage(replaceExisting)
    local fullPath, dir, fName = resolveWorldFilePath()
    recordFileInHistory(fName)

    local rawData = ""
    local sourceLabel = "Preferences"
    if io and io.open then
        local okF, fh = pcall(io.open, fullPath, "r")
        if okF and fh then
            local okR, content = pcall(function()
                local txt = fh:read("*a")
                fh:close()
                return txt
            end)
            if okR and type(content) == "string" and content:gsub("%s+", "") ~= "" then
                rawData = content
                sourceLabel = fullPath
            end
        end
    end

    if rawData == "" and io and io.open and dir ~= "" then
        local okFb, fhFb = pcall(io.open, fName, "r")
        if okFb and fhFb then
            pcall(function()
                rawData = fhFb:read("*a")
                fhFb:close()
            end)
            if rawData ~= "" then sourceLabel = fName end
        end
    end

    if rawData == "" then
        if saved and saved.load then pcall(saved.load, saved) end
        rawData = tostring(loadPref("world_list_str", "") or "")
    end

    if rawData:gsub("%s+", "") == "" then
        local emptyMsg = "Data Save World belum ada di:\n" .. fullPath .. "\nmaupun di Preferences!"
        if sendNotification then pcall(sendNotification, emptyMsg) end
        if updateFileInfoDisplayList then updateFileInfoDisplayList() end
        return 0, emptyMsg
    end

    local count, dups, ignored, summary = parseAndValidateWorldBatch(rawData, replaceExisting ~= false)
    local doneCnt, antriCnt = 0, 0
    for _, e in ipairs(CFG.world_list) do
        if e.done then doneCnt = doneCnt + 1 else antriCnt = antriCnt + 1 end
    end
    local msg = string.format("Load %d world dari %s (DONE: %d, ANTRI: %d).", count, sourceLabel, doneCnt, antriCnt)
    addLog(msg)
    if sendNotification then pcall(sendNotification, msg) end
    if updateFileInfoDisplayList then updateFileInfoDisplayList() end
    return count, msg
end

-- ============================================================================
-- 4. SAFE HELPER WRAPPERS FOR GROWLAUNCHER API
-- ============================================================================

local function safeSleep(ms)
    if CSleep then
        CSleep(ms)
    elseif sleep then
        sleep(ms)
    end
end

local function waitIfPaused()
    while STATE.running and STATE.paused do
        safeSleep(300)
    end
    if STATE.reconnected_restart then
        return false
    end
    return STATE.running
end

local function getWorldNameSafe()
    if not getCurrentWorldName then return "EXIT" end
    local ok, name = pcall(getCurrentWorldName)
    if ok and type(name) == "string" and name ~= "" then
        return name:upper()
    end
    return "EXIT"
end

local function getPlayerTilePos()
    if not getLocal then return nil, nil end
    local ok, p = pcall(getLocal)
    if not ok or not p then return nil, nil end
    local px = p.posX or (p.pos and p.pos.x)
    local py = p.posY or (p.pos and p.pos.y)
    if not px or not py then return nil, nil end
    return math.floor((px + 10) / 32), math.floor((py + 15) / 32)
end

-- ===================== ROBUST INVENTORY & WORLD OBJECT ENGINE =====================
-- Sesuai dokumentasi resmi GrowLauncher (docs/namespaces/growtopia.md, docs/structs/game-objects.md):
-- 1. InventoryItem memiliki { id, amount }
-- 2. getInventory() mengembalikan InventoryItem[] (dapat berupa table maupun Sol2 userdata container)
-- 3. growtopia.checkInventory(itemid) -> boolean (Cek native C++ apakah player memiliki item)
-- 4. growtopia.checkInventoryCount(itemid) -> number (Hitung total item via C++ memory)
-- 5. getObjectList() / getObjects() -> WorldObject[] ({ id, itemid, amount, pos={x, y} })

local function readInvItemFields(it)
    local t = type(it)
    if t ~= "table" and t ~= "userdata" then return nil, nil end
    local id, amt = nil, nil
    pcall(function() id = tonumber(it.id or it.itemid or it.itemID or it.item_id) end)
    pcall(function() amt = tonumber(it.amount or it.count or it.cnt) end)
    return id, amt
end

local function getRawInventory()
    if not getInventory then return nil end
    local ok, inv = pcall(getInventory)
    if not ok or inv == nil then return nil end
    local t = type(inv)
    if t ~= "table" and t ~= "userdata" then return nil end
    local items = nil
    pcall(function() items = inv.items end)
    if items ~= nil and (type(items) == "table" or type(items) == "userdata") then return items end
    return inv
end

local function forEachInvItem(fn)
    local inv = getRawInventory()
    if not inv then return 0 end
    local seen = 0
    pcall(function()
        for _, it in pairs(inv) do
            local id, amt = readInvItemFields(it)
            if id and id > 0 then
                seen = seen + 1
                fn(id, amt or 0)
            end
        end
    end)
    if seen == 0 then
        local okLen, n = pcall(function() return #inv end)
        if not okLen or not n or n <= 0 then pcall(function() n = inv:size() end) end
        local maxI = (n and tonumber(n) and tonumber(n) > 0) and tonumber(n) or 400
        local misses = 0
        for i = 0, maxI do
            local okI, it = pcall(function() return inv[i] end)
            local id, amt = nil, nil
            if okI then id, amt = readInvItemFields(it) end
            if id and id > 0 then
                misses = 0
                seen = seen + 1
                fn(id, amt or 0)
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

    -- A. C++ native GrowLauncher count (paling cepat & akurat jika sinkron)
    local nativeCnt = 0
    if growtopia and growtopia.checkInventoryCount then
        local ok, cnt = pcall(growtopia.checkInventoryCount, targetID)
        if ok and tonumber(cnt) and tonumber(cnt) > 0 then
            return tonumber(cnt)
        end
    end

    -- B. Scan memori tas (mendukung Lua table, nested .items, dan Sol2 userdata vector)
    local total = 0
    forEachInvItem(function(id, amt)
        if id == targetID and amt > 0 then total = total + amt end
    end)
    if total > 0 then return total end

    -- C. Fallback otoritatif C++ boolean dari GrowLauncher (docs/namespaces/growtopia.md)
    -- Jika checkInventoryCount mengembalikan 0 karena lag sync packet, checkInventory() tetap true jika item ada di tas!
    if growtopia and growtopia.checkInventory then
        local ok, has = pcall(growtopia.checkInventory, targetID)
        if ok and has == true then
            return 1
        end
    end

    return 0
end

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
        for _, obj in pairs(container) do
            processObj(obj)
        end
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

local function findWorldObjectsByItemID(targetID)
    targetID = tonumber(targetID) or 0
    if targetID <= 0 then return {} end
    local list = {}
    forEachWorldObject(function(itemid, uid, amt, px, py, obj)
        if itemid == targetID then
            table.insert(list, {
                itemid = itemid,
                id     = uid,
                amount = amt,
                x      = px,
                y      = py,
                tileX  = math.floor((px + 10) / 32),
                tileY  = math.floor((py + 10) / 32),
                raw    = obj,
            })
        end
    end)
    return list
end

local function logInventoryDiagnostic(idList, tag)
    local invType = "nil"
    if getInventory then
        local ok, inv = pcall(getInventory)
        invType = ok and type(inv) or ("err:" .. tostring(inv))
    end
    local slots = forEachInvItem(function() end)
    local parts = {}
    for _, id in ipairs(idList or {}) do
        id = tonumber(id) or 0
        if id > 0 then
            local nat = "-"
            if growtopia and growtopia.checkInventoryCount then
                local ok, c = pcall(growtopia.checkInventoryCount, id)
                nat = ok and tostring(c) or "err"
            end
            local hasBool = false
            if growtopia and growtopia.checkInventory then
                local ok, h = pcall(growtopia.checkInventory, id)
                hasBool = ok and h
            end
            local sc = 0
            forEachInvItem(function(i, a) if i == id then sc = sc + a end end)
            table.insert(parts, string.format("#%d[nat:%s,has:%s,scan:%d]", id, nat, tostring(hasBool), sc))
        end
    end
    addLog(string.format("`o[BP Diag%s] invType=%s slots=%d | %s",
        tag and (" " .. tag) or "", invType, slots, table.concat(parts, ", ")))
end

local function getWorldObjectsSafe()
    local list = {}
    forEachWorldObject(function(itemid, uid, amt, px, py, obj)
        table.insert(list, obj)
    end)
    return list
end

local function refreshInventorySnapshot()
    local list = {}
    local doors = {}
    do
        local invItems = {}
        forEachInvItem(function(iid, iamt) table.insert(invItems, { id = iid, amount = iamt }) end)
        do
            for _, item in ipairs(invItems) do
                if item and item.id and item.id > 0 and (item.amount or 0) > 0 then
                    local nm = resolveItemName(item.id)
                    local entry = {
                        id     = item.id,
                        amount = item.amount or 0,
                        name   = nm,
                        isDoor = isDoorOrEntranceItem(item.id, nm),
                    }
                    table.insert(list, entry)
                    if entry.isDoor then
                        table.insert(doors, entry)
                    end
                end
            end
        end
    end
    table.sort(list, function(a, b)
        if a.isDoor ~= b.isDoor then
            return a.isDoor
        end
        return a.id < b.id
    end)
    table.sort(doors, function(a, b) return a.id < b.id end)
    STATE.cached_inv = list
    STATE.cached_doors = doors
    if refreshNativeDisplayLists then
        pcall(refreshNativeDisplayLists)
    end
end

local function findMainDoor()
    if getTiles then
        local ok, tiles = pcall(getTiles)
        if ok and tiles then
            for _, t in pairs(tiles) do
                if t and t.fg == ITEM.MAIN_DOOR then
                    return t.x, t.y
                end
            end
        end
    end
    for y = 0, 59 do
        for x = 0, 99 do
            local ok, t = pcall(getTile, x, y)
            if ok and t and t.fg == ITEM.MAIN_DOOR then
                return x, y
            end
        end
    end
    return nil, nil
end

local function isOnMainDoor()
    local px, py = getPlayerTilePos()
    local dx, dy = findMainDoor()
    if px and dx and px == dx and py == dy then
        return true
    end
    return false
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

local function applyCheatToggles()
    if not editToggle then return end
    if CFG.use_modfly then
        pcall(editToggle, "ModFly", true)
    end
    if CFG.use_anti_lava then
        pcall(editToggle, "Anti Lava", true)
        pcall(editToggle, "No Lava", true)
    end
    if CFG.auto_reconnect then
        pcall(editToggle, "Auto Reconnect", true)
        pcall(editToggle, "AutoReconnect", true)
        pcall(editToggle, "Reconnect", true)
    end
    if CFG.auto_collect and not STATE.saving_storage then
        setAutoCollectActive(true)
    elseif STATE.saving_storage then
        setAutoCollectActive(false)
    end
end

-- ============================================================================
-- 5. SAFE MOVEMENT, ANTI-LAVA COLLISION & AUTO COLLECT FLOATING ITEMS
-- ============================================================================

local function isProtectedEnclosure(tx, ty, doorX, doorY)
    if CFG.use_id_door and tx == 0 and ty == 0 then
        return true
    end
    if not doorX or not doorY then return false end
    -- Standar Murni Auto Dirt Farm:
    -- White Door (dx, dy) & Bedrock bawah White Door (dx, dy+1)
    -- Small Lock di atas White Door (dx, dy-1)
    -- Signal Jammer di kiri SL (dx-1, dy-1)
    -- Penghalang Kiri di kiri White Door (dx-1, dy)
    -- World Lock di kanan White Door (dx+1, dy)
    -- Toleransi kompatibilitas: (dx-2, dy)
    if (tx == doorX and ty == doorY)
        or (tx == doorX and ty == doorY + 1)
        or (tx == doorX and ty == doorY - 1)
        or (tx == doorX - 1 and ty == doorY)
        or (tx == doorX - 1 and ty == doorY - 1)
        or (tx == doorX + 1 and ty == doorY)
        or (tx == doorX - 2 and ty == doorY) then
        return true
    end
    return false
end

local function isInSecurityMoat(tx, ty, doorX, doorY)
    if CFG.use_id_door and tx == 0 and ty == 0 then
        return true
    end
    if not doorX or not doorY then return false end
    if (tx >= doorX - 2 and tx <= doorX + 2) and (ty >= doorY - 2 and ty <= doorY + 2) then
        return true
    end
    return false
end

local function isTileSafeToStand(tx, ty)
    if tx < 0 or tx > 99 or ty < 0 or ty > 53 then
        return false
    end
    local ok, t = pcall(getTile, tx, ty)
    if not ok or not t then return false end

    local fg = t.fg or 0
    if fg == ITEM.LAVA then
        return false
    end
    if fg ~= 0
       and fg ~= ITEM.MAIN_DOOR
       and fg ~= ITEM.DOOR
       and fg ~= ITEM.DUNGEON_DOOR
       and fg ~= ITEM.PORTAL
       and fg ~= ITEM.AIR_VENT
       and fg ~= ITEM.HOUSE_ENTRANCE
       and fg ~= ITEM.SCREEN_DOOR
       and fg ~= ITEM.PORTCULLIS
       and fg ~= ITEM.WOOD_PLATFORM
       and fg ~= CFG.id_door_itemid
       and fg ~= CFG.blocker_door_itemid
       and fg ~= CFG.platform_itemid
       and fg ~= ITEM.DIRT_SEED
       and fg ~= ITEM.CAVE_SEED
       and fg ~= ITEM.LAVA_SEED
       and fg ~= ITEM.ROCK_SEED then
        if t.collidable or fg == ITEM.DIRT or fg == ITEM.ROCK or fg == ITEM.BEDROCK or OTHER_LOCKS[fg] or fg == ITEM.JAMMER then
            return false
        end
    end

    if CFG.use_anti_lava and ty < 53 then
        local okB, below = pcall(getTile, tx, ty + 1)
        if okB and below and below.fg == ITEM.LAVA then
            return false
        end
    end

    return true
end

local function moveSafeTo(tx, ty)
    tx = math.max(0, math.min(99, tx))
    ty = math.max(0, math.min(53, ty))
    local px, py = getPlayerTilePos()
    if px == tx and py == ty then
        return true
    end
    local pFn = FindPath or findPath
    if not pFn then return false end

    local CHUNK_LIMIT = 5 -- Hop pendek (5 block) agar gerakan natural & aman saat lag

    -- Waypoint wajib tile yang bisa diinjak; titik garis lurus sering jatuh di dirt/rock padat
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
    while STATE.running do
        local curX, curY = getPlayerTilePos()
        if not curX or not curY then
            stuck = stuck + 1
            if stuck >= 3 then break end
            safeSleep(100)
        else
            if curX == tx and curY == ty then return true end

            local dx = tx - curX
            local dy = ty - curY
            local dist = math.max(math.abs(dx), math.abs(dy))
            if dist == 0 then return true end

            local stepX, stepY = tx, ty
            local direct = (dist <= CHUNK_LIMIT) or stuck >= 1
            if not direct then
                local ratio = CHUNK_LIMIT / dist
                local ix = math.max(0, math.min(99, math.floor(curX + (dx * ratio) + 0.5)))
                local iy = math.max(0, math.min(53, math.floor(curY + (dy * ratio) + 0.5)))
                stepX, stepY = nearestFree(ix, iy)
                if not stepX then stepX, stepY, direct = tx, ty, true end
            end

            local stepDist = math.max(math.abs(curX - stepX), math.abs(curY - stepY))
            local walkDelay = math.max(50, tonumber(CFG.delay_walk) or 160)
            -- TELEPORT per hop dengan jeda SEBELUM teleport mengikuti slider "Delay Jalan" (jitter ±20%)
            safeSleep(math.floor(walkDelay * (0.8 + math.random() * 0.4)))
            if not STATE.running then break end
            pcall(pFn, stepX, stepY)
            -- Tunggu pergerakan segmen hop dengan polling ramah CPU
            local waited = 0
            local maxWait = math.max(120, math.min(1500, stepDist * 60))
            while waited < maxWait and STATE.running do
                local nx, ny = getPlayerTilePos()
                if nx and ny and math.abs(nx - stepX) <= 1 and math.abs(ny - stepY) <= 1 then
                    break
                end
                safeSleep(25)
                waited = waited + 25
            end

            local npx, npy = getPlayerTilePos()
            if npx == tx and npy == ty then safeSleep(math.floor(walkDelay * 0.8)); return true end
            if npx == curX and npy == curY then
                stuck = stuck + 1 -- tidak bergerak: coba langsung ke target, lalu menyerah
                if direct and stuck >= 2 then break end
            else
                stuck = 0
                if direct and npx and npy and math.abs(npx - tx) <= 1 and math.abs(npy - ty) <= 1 then
                    safeSleep(math.floor(walkDelay * 0.8))
                    break
                end
            end
            -- Jeda SETELAH tiap teleport mengikuti slider "Delay Jalan" (walkDelay * 1.5, jitter ±20%)
            safeSleep(math.floor(walkDelay * 1.5 * (0.8 + math.random() * 0.4)))
        end
    end

    local finalX, finalY = getPlayerTilePos()
    if finalX and finalY then
        return (math.abs(finalX - tx) <= 1 and math.abs(finalY - ty) <= 1)
    end
    return false
end

local function moveAdjacentSafe(targetX, targetY, preferredDirX)
    local dir = preferredDirX or -1
    local candidates = {
        { targetX + dir, targetY },
        { targetX - dir, targetY },
        { targetX,       targetY - 1 },
        { targetX,       targetY + 1 },
        { targetX + dir, targetY - 1 },
        { targetX - dir, targetY - 1 },
        { targetX + dir, targetY + 1 },
        { targetX - dir, targetY + 1 },
        { targetX + (dir * 2), targetY },
        { targetX - (dir * 2), targetY },
    }
    for _, cand in ipairs(candidates) do
        local cx, cy = cand[1], cand[2]
        if isTileSafeToStand(cx, cy) then
            local px, py = getPlayerTilePos()
            if px == cx and py == cy then
                return true
            end
            if moveSafeTo(cx, cy) then
                return true
            end
        end
    end
    -- Fallback non-collidable neighbor even if lava check was strict (e.g. while clearing lava around rock)
    for _, cand in ipairs(candidates) do
        local cx, cy = cand[1], cand[2]
        if cx >= 0 and cx <= 99 and cy >= 0 and cy <= 53 then
            local okT, tileInfo = pcall(getTile, cx, cy)
            if okT and tileInfo and (not tileInfo.collidable) and tileInfo.fg ~= ITEM.LAVA and tileInfo.fg ~= ITEM.ROCK and tileInfo.fg ~= ITEM.DIRT and tileInfo.fg ~= ITEM.BEDROCK then
                if moveSafeTo(cx, cy) then
                    return true
                end
            end
        end
    end
    return false
end

local function sendRawAction(tx, ty, value)
    local ok, p = pcall(getLocal)
    if not ok or not p then return false end
    local px = p.posX or (p.pos and p.pos.x) or (tx * 32)
    local py = p.posY or (p.pos and p.pos.y) or (ty * 32)
    local state = (px > (tx * 32)) and 48 or 32

    sendPacketRaw(false, {
        type   = 3,
        value  = value,
        px     = tx,
        py     = ty,
        x      = px,
        y      = py,
        state  = state,
    })
    return true
end

local function getWorldObjectsSafe()
    local fn = getObjectList or getObjects
    if not fn then return nil end
    local ok, objs = pcall(fn)
    if ok and type(objs) == "table" then
        return objs
    end
    return nil
end

local function collectNearbyFloating(centerX, centerY, customRadius, quickMode, forceCollect)
    if ((not CFG.auto_collect) and (not forceCollect)) or STATE.saving_storage then return 0 end
    local objs = getWorldObjectsSafe()
    if not objs then return 0 end

    local px, py = getPlayerTilePos()
    local refX = centerX or px
    local refY = centerY or py
    if not refX or not refY then return 0 end

    -- Selalu hormati penuh CFG.collect_range (jangan dipangkas ke 2 tile saat quickMode)
    local radius = customRadius or CFG.collect_range or 3
    local collected = 0

    for _, obj in pairs(objs) do
        if not STATE.running then break end
        if obj and obj.pos and obj.id then
            local ox = math.floor((obj.pos.x + 10) / 32)
            local oy = math.floor((obj.pos.y + 10) / 32)
            local itemid = obj.itemid or 0
            local dist = math.max(math.abs(ox - refX), math.abs(oy - refY))

            local spotKey = tostring(ox) .. "," .. tostring(oy)
            if dist <= radius and itemid ~= ITEM.LAVA and (not STATE.df_dropped_spots[spotKey]) then
                local curAmt = getInvCount(itemid)
                if curAmt < 200 then
                    local curPx, curPy = getPlayerTilePos()
                    local pDist = (curPx and curPy) and math.max(math.abs(ox - curPx), math.abs(oy - curPy)) or 99
                    -- Server Growtopia menolak pickup bila terlalu jauh (> 1 tile bila tidak quick, atau > 2 tile saat quick); hampiri dulu agar item di dalam area collect_range benar-benar terambil!
                    local needWalk = (not quickMode and pDist > 1) or (pDist > 2)
                    if needWalk and isTileSafeToStand(ox, oy) then
                        moveSafeTo(ox, oy)
                    end
                    -- Sesuai docs structs/game-objects.md: paket type 11 mengirim koord objek (obj.pos.x, obj.pos.y)
                    pcall(sendPacketRaw, false, {
                        type  = 11,
                        value = obj.id,
                        x     = obj.pos.x,
                        y     = obj.pos.y,
                    })
                    if not quickMode then
                        safeSleep(20)
                    end
                    collected = collected + 1
                end
            end
        end
    end
    return collected
end

-- Estimate realistic punch count for an item ID so lag won't cause 45x punch spam
local KNOWN_BREAK_HITS = {
    [ITEM.DIRT]    = 3,
    [ITEM.CAVE_BG] = 4, -- Cave Background membutuhkan 4 punch (sama seperti Lava), bukan 3
    [ITEM.LAVA]    = 4,
    [ITEM.ROCK]    = 6,
}

local function estimateTileBreakHits(itemID)
    if not itemID or itemID <= 0 then return 3 end
    if KNOWN_BREAK_HITS[itemID] then
        return KNOWN_BREAK_HITS[itemID]
    end
    local info = nil
    if getItemInfoByID then
        local ok, res = pcall(getItemInfoByID, itemID)
        if ok and res then info = res end
    elseif itemInfoManager and itemInfoManager.getItemInfoByID then
        local ok, res = pcall(itemInfoManager.getItemInfoByID, itemID)
        if ok and res then info = res end
    end
    local bh = info and tonumber(info.breakHits) or 0
    if bh > 0 then
        -- Growtopia items.dat often stores breakHits * 6 (e.g. 18 = 3 hits, 36 = 6 hits)
        local normalized = (bh >= 12) and math.ceil(bh / 6) or math.ceil(bh)
        if normalized < 2 then normalized = 2 end
        if normalized > 10 then normalized = 10 end
        return normalized
    end
    return 4
end

-- Helper: Wait up to maxWaitMs for server to confirm the current FG/BG layer cleared
local function awaitTileLayerCleared(tx, ty, isFgLayer, maxWaitMs)
    local function isCleared()
        local ok, t = pcall(getTile, tx, ty)
        if not ok or not t then return false, true end
        if isFgLayer then
            return (t.fg == 0 or t.fg == ITEM.BEDROCK or t.fg == ITEM.MAIN_DOOR), false
        end
        return (t.bg == 0), false
    end

    local cleared, failed = isCleared()
    if failed then return false end
    if cleared then return true end

    local waited = 0
    while STATE.running and waited < maxWaitMs do
        safeSleep(25)
        waited = waited + 25
        cleared, failed = isCleared()
        if failed then return false end
        if cleared then return true end
    end
    return false
end

local function breakTileLayerWithLagGuard(tx, ty, isFgLayer, preferredDirX)
    local maxRounds = 5
    for round = 1, maxRounds do
        if not waitIfPaused() then return false end
        local ok, t = pcall(getTile, tx, ty)
        if not ok or not t then return false end

        local curId = isFgLayer and t.fg or t.bg
        if curId == 0 then return true end
        if isFgLayer and (curId == ITEM.BEDROCK or curId == ITEM.MAIN_DOOR) then
            return true
        end

        local px, py = getPlayerTilePos()
        -- Jangan pindah posisi bila sudah berada di jangkauan punch aman (<= 2 tile) agar Break 3 Tile tidak lompat-lompat!
        if (not px) or (px == tx and py == ty) or (math.abs(px - tx) > 2) or (math.abs(py - ty) > 2) or (not isTileSafeToStand(px, py)) then
            local jumpDist = (px and py) and math.max(math.abs(px - tx), math.abs(py - ty)) or 5
            moveAdjacentSafe(tx, ty, preferredDirX)
            if jumpDist >= 4 then
                safeSleep(50) -- Hanya jeda ringan bila habis lompat jauh, langkah antar tile tetap mulus
            end
        end

        local prevProgress = tonumber(t.progress) or 0
        local baseHits = estimateTileBreakHits(curId)
        local burstCount = (round == 1) and baseHits or math.min(3, math.max(1, math.ceil(baseHits / 2)))

        for _ = 1, burstCount do
            if not waitIfPaused() then return false end
            local okStep, tStep = pcall(getTile, tx, ty)
            if not okStep or not tStep then break end
            local stepId = isFgLayer and tStep.fg or tStep.bg
            if stepId == 0 or (isFgLayer and (stepId == ITEM.BEDROCK or stepId == ITEM.MAIN_DOOR)) then
                return true
            end
            sendRawAction(tx, ty, ITEM.PUNCH)
            safeSleep(CFG.delay_break)
        end

        -- Polling ultra-cepat setiap 25ms agar langsung pindah tanpa jeda terasa, tetap aman anti-spam saat lag
        local waitWindow = (round == 1) and 220 or ((round == 2) and 280 or 360)
        if awaitTileLayerCleared(tx, ty, isFgLayer, waitWindow) then
            return true
        end

        -- Still intact: bila disconnect saat sedang break, tunggu online kembali lalu lanjutkan tile ini
        local wNow = getWorldNameSafe()
        if wNow == "" or wNow == "EXIT" then
            if ensureOnlineInWorld and ensureOnlineInWorld(STATE.active_world, STATE.active_door) then
                -- Reconnect berhasil, lanjut putaran berikutnya tanpa membuang tile
            else
                return false
            end
        end
        local okAfter, tAfter = pcall(getTile, tx, ty)
        local afterProgress = (okAfter and tAfter and tonumber(tAfter.progress)) or 0
        if round >= 2 and afterProgress <= prevProgress then
            -- Jika progress macet 0 di putaran >= 3 (indikasi rubberband server), re-sinkronkan posisi di koridor sebelum pukul ulang
            if round >= 3 and py and math.abs(py - ty) <= 2 then
                local stepAlt = (tx > 1) and (tx - 1) or (tx + 1)
                if isTileSafeToStand(stepAlt, py) and (stepAlt ~= tx or py ~= ty) then
                    moveSafeTo(stepAlt, py)
                else
                    moveAdjacentSafe(tx, ty, preferredDirX)
                end
            end
            safeSleep(140)
        end
    end

    local okEnd, tEnd = pcall(getTile, tx, ty)
    if not okEnd or not tEnd then return false end
    return isFgLayer and (tEnd.fg == 0) or (not isFgLayer and tEnd.bg == 0)
end

local breakCollectCounter = 0

local function breakTileCompletely(tx, ty, breakFg, breakBg, preferredDirX, skipCollect)
    if tx < 0 or tx > 99 or ty < 0 or ty > 59 then return false end
    local ok, t = pcall(getTile, tx, ty)
    if not ok or not t then return false end
    if t.fg == ITEM.BEDROCK or t.fg == ITEM.MAIN_DOOR then
        return true
    end

    local fgDone = true
    if breakFg and t.fg ~= 0 then
        fgDone = breakTileLayerWithLagGuard(tx, ty, true, preferredDirX)
    end

    local bgDone = true
    if breakBg and STATE.running then
        local okBg, tBg = pcall(getTile, tx, ty)
        if okBg and tBg and tBg.bg ~= 0 then
            if tBg.fg ~= 0 and tBg.fg ~= ITEM.BEDROCK and tBg.fg ~= ITEM.MAIN_DOOR then
                if breakFg then
                    fgDone = breakTileLayerWithLagGuard(tx, ty, true, preferredDirX)
                    okBg, tBg = pcall(getTile, tx, ty)
                else
                    bgDone = false
                end
            end
            if okBg and tBg and tBg.fg == 0 and tBg.bg ~= 0 then
                bgDone = breakTileLayerWithLagGuard(tx, ty, false, preferredDirX)
            elseif okBg and tBg and tBg.fg ~= 0 and tBg.bg ~= 0 then
                bgDone = false
            end
        end
    end

    if CFG.auto_collect and (not skipCollect) then
        breakCollectCounter = breakCollectCounter + 1
        if (breakCollectCounter % 2) == 0 then
            collectNearbyFloating(tx, ty, CFG.collect_range, true)
        end
    end

    return fgDone and bgDone
end

local function placeTileAt(tx, ty, itemID, isBackground, preferredDirX)
    if tx < 0 or tx > 99 or ty < 0 or ty > 59 then return false end
    local ok, t = pcall(getTile, tx, ty)
    if not ok or not t then return false end

    if not isBackground and t.fg == itemID then
        return true
    end
    if isBackground and t.bg == itemID then
        return true
    end
    if getInvCount(itemID) <= 0 then
        return false
    end

    local isSeed = (itemID == ITEM.DIRT_SEED or itemID == ITEM.CAVE_SEED or itemID == ITEM.LAVA_SEED or itemID == ITEM.ROCK_SEED)

    local maxAttempts = 10
    local attempts = 0
    while STATE.running and attempts < maxAttempts do
        if not waitIfPaused() then return false end
        ok, t = pcall(getTile, tx, ty)
        if not ok or not t then break end
        if (not isBackground and t.fg == itemID) or (isBackground and t.bg == itemID) then
            return true
        end

        local px, py = getPlayerTilePos()
        local outOfRange = (not px) or (math.abs(px - tx) > 2) or (math.abs(py - ty) > 2)
        local standingOnTarget = (px == tx and py == ty)

        if (not isSeed) and (outOfRange or standingOnTarget) then
            moveAdjacentSafe(tx, ty, preferredDirX)
        elseif outOfRange then
            moveAdjacentSafe(tx, ty, preferredDirX)
        end

        sendRawAction(tx, ty, itemID)
        safeSleep(CFG.delay_place)
        attempts = attempts + 1
    end

    ok, t = pcall(getTile, tx, ty)
    return ok and t and ((not isBackground and t.fg == itemID) or (isBackground and t.bg == itemID))
end

-- Strict Validated Placement for Security Items (WL, SL, Jammer, Door ID, Blocker Doors)
local function placeAndValidateSecurityTile(tx, ty, itemID, itemLabel, standX, standY)
    if tx < 0 or tx > 99 or ty < 0 or ty > 59 then return false end
    local ok, t = pcall(getTile, tx, ty)
    if ok and t and t.fg == itemID then
        addLog(string.format("Validasi OK: %s sudah terpasang di (%d, %d)", itemLabel, tx, ty))
        return true
    end

    if getInvCount(itemID) <= 0 then
        addLog(string.format("Gagal Pasang %s: Stok di tas 0!", itemLabel))
        return false
    end

    for attempt = 1, 12 do
        if not waitIfPaused() then return false end
        ok, t = pcall(getTile, tx, ty)
        if ok and t and t.fg == itemID then
            addLog(string.format("Validasi Pasang OK: %s berhasil dipasang di (%d, %d) [Cek #%d]", itemLabel, tx, ty, attempt))
            return true
        end

        -- Jika masih ada block lain yang menghalangi di (tx, ty), hancurkan dulu sampai bersih
        if ok and t and t.fg ~= 0 and t.fg ~= itemID and t.fg ~= ITEM.BEDROCK and t.fg ~= ITEM.MAIN_DOOR then
            breakTileCompletely(tx, ty, true, false, 1)
            safeSleep(150)
        end

        if standX and standY and isTileSafeToStand(standX, standY) then
            moveSafeTo(standX, standY)
        else
            moveAdjacentSafe(tx, ty, 1)
        end

        local px, py = getPlayerTilePos()
        if px == tx and py == ty then
            moveAdjacentSafe(tx, ty, 1)
        end

        sendRawAction(tx, ty, itemID)
        safeSleep(CFG.delay_place + 180)

        ok, t = pcall(getTile, tx, ty)
        if ok and t and t.fg == itemID then
            addLog(string.format("Validasi Pasang OK: %s berhasil dipasang di (%d, %d)", itemLabel, tx, ty))
            return true
        end
    end

    ok, t = pcall(getTile, tx, ty)
    local success = (ok and t and t.fg == itemID)
    if not success then
        addLog(string.format("PERINGATAN: Gagal validasi pasang %s di (%d, %d)!", itemLabel, tx, ty))
    end
    return success
end

-- ============================================================================
-- 6. NETWORK WARP, TRASH, DROP & VALIDATED WRENCH DIALOG EDITING
-- ============================================================================

local function warpTo(worldName, doorID)
    if not worldName or worldName == "" then return false end
    worldName = worldName:upper():gsub("%s+", "")
    doorID = (doorID or ""):gsub("%s+", "")

    local targetStr = (doorID ~= "") and (worldName .. "|" .. doorID) or worldName
    setStatus("Warping", "Menuju world " .. targetStr)

    local tries = 0
    while STATE.running and tries < 5 do
        if not waitIfPaused() then return false end
        local cur = getWorldNameSafe()
        if cur ~= worldName then
            sendPacket(3, "action|join_request\nname|" .. targetStr .. "\ninvitedWorld|0\n")
            safeSleep(CFG.delay_warp)
        else
            if doorID ~= "" and isOnMainDoor() then
                sendPacket(3, "action|join_request\nname|" .. worldName .. "|" .. doorID .. "\ninvitedWorld|0\n")
                safeSleep(2500)
            end
            if getWorldNameSafe() == worldName then
                STATE.current_world = worldName
                applyCheatToggles()
                return true
            end
        end
        tries = tries + 1
    end

    STATE.current_world = getWorldNameSafe()
    applyCheatToggles()
    return STATE.current_world == worldName
end

local function isPlayerOnlineInWorld()
    local curW = getWorldNameSafe()
    if curW == "" or curW == "EXIT" then
        return false, curW
    end
    if getLocal then
        local okP, p = pcall(getLocal)
        if not okP or not p then
            return false, curW
        end
    end
    return true, curW
end

-- Saat Disconnect / terlempar ke EXIT, tunggu hingga online kembali lalu lanjut ke world DF target
ensureOnlineInWorld = function(expectedWorld, expectedDoor)
    local targetW = tostring(expectedWorld or STATE.active_world or ""):upper()
    local targetD = tostring(expectedDoor or STATE.active_door or "")
    local online, curW = isPlayerOnlineInWorld()
    if online and (targetW == "" or curW == targetW) then
        return true
    end

    if (not online) and (not CFG.auto_reconnect) then
        addLog("Disconnect terdeteksi (Auto Reconnect OFF) -> Bot dihentikan.")
        return false
    end

    local wasDisconnected = not online
    STATE.reconnecting = true
    if wasDisconnected then
        setStatus("Menunggu Online", "Disconnect terdeteksi! Auto Reconnect aktif, menunggu online lalu run ulang DF...")
    end
    applyCheatToggles()

    local ticks = 0
    while STATE.running do
        if not waitIfPaused() then
            STATE.reconnecting = false
            return false
        end
        safeSleep(2000)
        ticks = ticks + 1

        local nowOnline, nowW = isPlayerOnlineInWorld()
        if nowOnline then
            if targetW ~= "" and nowW ~= targetW then
                setStatus("Auto Reconnect", "Kembali online! Masuk lagi ke " .. targetW .. " & mengulang scan DF...")
                if warpTo(targetW, targetD) then
                    safeSleep(900)
                    STATE.reconnecting = false
                    applyCheatToggles()
                    if wasDisconnected then
                        STATE.reconnected_restart = true
                        STATE.resume_world_override = targetW
                        STATE.resume_door_override = targetD
                        return false
                    end
                    return true
                end
            else
                safeSleep(600)
                STATE.reconnecting = false
                STATE.current_world = nowW
                applyCheatToggles()
                addLog("Kembali Online di " .. nowW .. "!")
                if wasDisconnected then
                    STATE.reconnected_restart = true
                    STATE.resume_world_override = (targetW ~= "") and targetW or nowW
                    STATE.resume_door_override = targetD
                    return false
                end
                return true
            end
        elseif targetW ~= "" and getLocal then
            local okP, p = pcall(getLocal)
            if okP and p and (ticks % 3 == 0) then
                -- Coba join balik jika sudah login di Title Screen (EXIT)
                local targetStr = (targetD ~= "") and (targetW .. "|" .. targetD) or targetW
                pcall(sendPacket, 3, "action|join_request\nname|" .. targetStr .. "\ninvitedWorld|0\n")
            end
        end
    end

    STATE.reconnecting = false
    return false
end

local function trashItem(itemID, count)
    if count <= 0 then return end
    STATE.suppress_dialog = true
    sendPacket(2, "action|trash\n|itemID|" .. tostring(itemID))
    safeSleep(350)
    sendPacket(2, string.format(
        "action|dialog_return\ndialog_name|trash_item\nitemID|%d|\ncount|%d\n",
        itemID, count
    ))
    safeSleep(450)
    STATE.suppress_dialog = false
end

-- Forward declarations for World List editing helpers
local updateTrashDisplayList
local getConfiguredTrashItemList
local setTrashListFromTable
local openWorldListManagerDialog
local openEditWorldEntryDialog
local openTrashListManagerDialog
local openEditTrashEntryDialog

-- Edit & Hapus item pada CFG.world_list berdasarkan nomor urut (1..N)
local function editWorldEntryAt(idx, rawName, rawDoor)
    idx = math.floor(tonumber(idx) or 0)
    if idx < 1 or idx > #CFG.world_list then
        return false, "Nomor world tidak valid!"
    end
    local cleanName = tostring(rawName or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local cleanDoor = tostring(rawDoor or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if cleanName == "" then
        return false, "Nama world tidak boleh kosong!"
    end
    if cleanName:find("|", 1, true) then
        local wPart, dPart = cleanName:match("^([^|]+)|(.*)$")
        if wPart then
            cleanName = wPart:gsub("^%s+", ""):gsub("%s+$", "")
            if cleanDoor == "" then
                cleanDoor = (dPart or ""):gsub("^%s+", ""):gsub("%s+$", "")
            end
        end
    end
    cleanName = cleanName:upper()
    CFG.world_list[idx].name = cleanName
    CFG.world_list[idx].door = cleanDoor
    persistConfig()
    if updateWorldDisplayList then updateWorldDisplayList() end
    return true, string.format("World #%d diubah -> %s%s", idx, cleanName, (cleanDoor ~= "" and (" | " .. cleanDoor) or ""))
end

local function deleteWorldEntryAt(idx)
    idx = math.floor(tonumber(idx) or 0)
    if idx < 1 or idx > #CFG.world_list then
        return false, "Nomor world tidak valid!"
    end
    local removed = table.remove(CFG.world_list, idx)
    persistConfig()
    if updateWorldDisplayList then updateWorldDisplayList() end
    return true, "World #" .. tostring(idx) .. " (" .. tostring(removed and removed.name or "") .. ") dihapus!"
end

-- Parse Growtopia OnDialogRequest fields dynamically (inputs, checkboxes, embed_data, buttons)
local function parseDialogFields(dlgText)
    local meta = {
        dialog_name = "",
        embeds = {},
        embed_order = {},
        inputs = {},
        input_order = {},
        checkboxes = {},
        checkbox_labels = {},
        checkbox_order = {},
        buttons = {},
    }
    if type(dlgText) ~= "string" or dlgText == "" then
        return meta
    end
    for line in dlgText:gmatch("[^\r\n]+") do
        local parts = {}
        for part in (line .. "|"):gmatch("([^|]*)|") do
            table.insert(parts, part)
        end
        local cmd = parts[1]
        if cmd == "end_dialog" and parts[2] and parts[2] ~= "" then
            meta.dialog_name = parts[2]
        elseif cmd == "embed_data" and parts[2] and parts[2] ~= "" then
            local k = parts[2]
            if meta.embeds[k] == nil then
                table.insert(meta.embed_order, k)
            end
            meta.embeds[k] = parts[3] or ""
        elseif cmd == "add_text_input" and parts[2] and parts[2] ~= "" then
            local k = parts[2]
            if meta.inputs[k] == nil then
                table.insert(meta.input_order, k)
            end
            meta.inputs[k] = parts[4] or ""
        elseif cmd == "add_checkbox" and parts[2] and parts[2] ~= "" then
            local k = parts[2]
            if meta.checkboxes[k] == nil then
                table.insert(meta.checkbox_order, k)
            end
            meta.checkbox_labels[k] = parts[3] or ""
            meta.checkboxes[k] = parts[4] or "0"
        elseif (cmd == "add_button" or cmd == "add_button_with_icon") and parts[2] and parts[2] ~= "" then
            meta.buttons[parts[2]] = parts[3] or parts[2]
        end
    end
    return meta
end

local function buildDialogReturn(dlgText, fallbackName, fallbackX, fallbackY, inputOverrides, checkOverrides, buttonClicked)
    local meta = parseDialogFields(dlgText)
    local dName = (meta.dialog_name ~= "" and meta.dialog_name) or fallbackName
    local tx = tonumber(meta.embeds.tilex) or fallbackX
    local ty = tonumber(meta.embeds.tiley) or fallbackY

    local lines = {
        "action|dialog_return",
        "dialog_name|" .. tostring(dName),
    }
    if tx ~= nil then table.insert(lines, "tilex|" .. tostring(tx) .. "|") end
    if ty ~= nil then table.insert(lines, "tiley|" .. tostring(ty) .. "|") end
    local emitted = {}
    for _, ek in ipairs(meta.embed_order or {}) do
        if ek ~= "tilex" and ek ~= "tiley" then
            table.insert(lines, tostring(ek) .. "|" .. tostring(meta.embeds[ek] or "") .. "|")
            emitted[ek] = true
        end
    end
    if buttonClicked and buttonClicked ~= "" then
        table.insert(lines, "buttonClicked|" .. tostring(buttonClicked))
    end

    for _, k in ipairs(meta.input_order) do
        local v = (inputOverrides and inputOverrides[k] ~= nil) and inputOverrides[k] or meta.inputs[k]
        table.insert(lines, tostring(k) .. "|" .. tostring(v or ""))
        emitted[k] = true
    end
    if inputOverrides then
        for k, v in pairs(inputOverrides) do
            if not emitted[k] then
                table.insert(lines, tostring(k) .. "|" .. tostring(v))
                emitted[k] = true
            end
        end
    end

    for _, k in ipairs(meta.checkbox_order) do
        local v = (checkOverrides and checkOverrides[k] ~= nil) and checkOverrides[k] or meta.checkboxes[k]
        table.insert(lines, tostring(k) .. "|" .. tostring(v or "0"))
        emitted[k] = true
    end
    if checkOverrides then
        for k, v in pairs(checkOverrides) do
            if not emitted[k] then
                table.insert(lines, tostring(k) .. "|" .. tostring(v))
                emitted[k] = true
            end
        end
    end

    return table.concat(lines, "\n") .. "\n"
end

local function parseDialogReturnFields(pkt)
    local fields = {}
    if type(pkt) ~= "string" then return fields end
    for line in pkt:gmatch("[^\r\n]+") do
        local k, v = line:match("^([^|]+)|(.*)$")
        if k and k ~= "" then
            v = (v or ""):gsub("|$", "")
            fields[k] = v
        end
    end
    return fields
end

local function safeSendRawDialog(dText)
    if not dText or dText == "" then return false end
    if growtopia and type(growtopia.sendDialog) == "function" then
        local ok = pcall(growtopia.sendDialog, dText)
        if ok then return true end
    end
    if sendVariant then
        local ok = pcall(sendVariant, { v1 = "OnDialogRequest", v2 = dText })
        if ok then return true end
    end
    if sendDialog then
        pcall(sendDialog, dText)
        return true
    end
    return false
end

openEditWorldEntryDialog = function(idx)
    local entry = CFG.world_list[idx]
    if not entry then return end
    local dLines = {
        "set_default_color|`o",
        "add_quick_exit|",
        string.format("add_label_with_icon|big|`wEdit World DF #%d``|left|2|", idx),
        "add_spacer|small|",
        string.format("add_text_input|edit_w_name|Nama World|%s|24|", tostring(entry.name or "")),
        string.format("add_text_input|edit_w_door|Door ID (Kosong = White Door)|%s|32|", tostring(entry.door or "")),
        "add_spacer|small|",
        "add_button|save_w_edit|`2Simpan Perubahan|noflags|0|0|",
        "add_button|del_w_edit|`4Hapus World Ini|noflags|0|0|",
        string.format("end_dialog|boren_world_edit_%d|Batal||", idx),
    }
    safeSendRawDialog(table.concat(dLines, "\n"))
end

openWorldListManagerDialog = function(fmt)
    fmt = fmt or "colon"

    local copyLines = {}
    for _, e in ipairs(CFG.world_list) do
        local door = e.door or ""
        if fmt == "colon" then
            table.insert(copyLines, (door ~= "") and (e.name .. ":" .. door) or e.name)
        elseif fmt == "pipe" then
            table.insert(copyLines, (door ~= "") and (e.name .. "|" .. door) or e.name)
        else
            table.insert(copyLines, e.name)
        end
    end
    local rawCopy = table.concat(copyLines, "\n")
    local rawBoxText = table.concat(copyLines, ", ")
    if ImGui and ImGui.SetClipboardText and rawCopy ~= "" then
        pcall(ImGui.SetClipboardText, rawCopy)
    end

    local dLines = {
        "set_default_color|`o",
        "add_quick_exit|",
        string.format("add_label_with_icon|big|`wKelola, Salin & Tempel World DF (%d)``|left|2|", #CFG.world_list),
        "add_textbox|`oDi sini Anda bisa salin antrean, tempel banyak world baru, dan edit/hapus world.|left|",
        "add_spacer|small|",

        -- Bagian 1: Salin Semua World
        "add_textbox|`2[1. Salin Semua World DF ke Clipboard]|left|",
        string.format("add_text_input|boren_wcopy_box|Salin Antrean|%s|9999|", rawBoxText),
        "add_button|boren_btn_wfmt_colon|Format Titik Dua (:)|noflags|0|0|",
        "add_button|boren_btn_wfmt_pipe|Format Garis (|)|noflags|0|0|",
        "add_button|boren_btn_wfmt_name|Hanya Nama World|noflags|0|0|",
        "add_spacer|small|",

        -- Bagian 2: Tempel Banyak / Tambah World
        "add_textbox|`2[2. Tempel / Tambah World ke Antrean]|left|",
        "add_textbox|`eTempel 1 atau banyak world (Format: WORLD:ID / WORLD|ID / WORLD). Bebas koma, spasi, enter.|left|",
        "add_text_input|boren_wpaste_raw|Tempel World di sini:||9999|",
        "add_checkbox|boren_wpaste_replace|Ganti semua antrean (Replace)|0|",
        "add_button|boren_submit_wpaste|`2+ Tempel / Tambah ke Antrean|noflags|0|0|",
        "add_spacer|small|",

        -- Bagian 3: Daftar World & Aksi Edit/Hapus
        string.format("add_textbox|`2[3. Daftar Antrean Saat Ini (%d World)]|left|", #CFG.world_list)
    }

    if #CFG.world_list == 0 then
        table.insert(dLines, "add_textbox|`4(Antrean World DF masih kosong. Silakan tempel di atas!)|left|")
    else
        for i, e in ipairs(CFG.world_list) do
            local tag = getWorldEntryStatusTag(e)
            local st = (tag == "DONE") and "`2[DONE]" or ((tag == "PROSES") and "`6[PROSES]" or "`9[ANTRI]")
            local d = (e.door and e.door ~= "") and e.door or "-"
            table.insert(dLines, string.format("add_textbox|`w%d. `9%s `o[Door: %s] %s|left|", i, e.name, d, st))
            table.insert(dLines, string.format("add_button|boren_wedit_%d|Edit|noflags|0|0|", i))
            table.insert(dLines, string.format("add_button|boren_whapus_%d|Hapus|noflags|0|0|", i))
            table.insert(dLines, "add_spacer|small|")
        end
    end

    table.insert(dLines, "end_dialog|boren_world_mgr|Tutup||")
    return safeSendRawDialog(table.concat(dLines, "\n"))
end

openUnifiedToolManager = function(fmt)
    fmt = fmt or "colon"
    local copyLines = {}
    for _, s in ipairs(CFG.storage_tool_list or {}) do
        local d = (s.door and s.door ~= "") and s.door or ""
        if fmt == "colon" then
            table.insert(copyLines, d ~= "" and (s.name .. ":" .. d) or s.name)
        elseif fmt == "pipe" then
            table.insert(copyLines, d ~= "" and (s.name .. "|" .. d) or s.name)
        else
            table.insert(copyLines, s.name)
        end
    end
    local rawBoxText = table.concat(copyLines, ", ")

    local d = {
        "set_default_color|`o",
        "add_quick_exit|",
        string.format("add_label_with_icon|big|`2Kelola Gudang Alat (%d)``|left|242|", #(CFG.storage_tool_list or {})),
        "add_textbox|`oGudang restock World Lock, Small Lock, Jammer, Wooden Door, dan Blocker.|left|",
        "add_spacer|small|",
        "add_textbox|`2[1. Salin Daftar Gudang Alat]|left|",
        string.format("add_text_input|boren_tlcopy_box|Salin Gudang Alat|%s|9999|", rawBoxText),
        "add_button|boren_btn_tlfmt_colon|Format Titik Dua (:)|noflags|0|0|",
        "add_button|boren_btn_tlfmt_pipe|Format Garis (|)|noflags|0|0|",
        "add_button|boren_btn_tlfmt_name|Hanya Nama World|noflags|0|0|",
        "add_spacer|small|",
        "add_textbox|`2[2. Tempel / Tambah Gudang Alat]|left|",
        "add_textbox|`eFormat: WORLD:DOOR atau WORLD|DOOR atau WORLD. Bebas koma/enter.|left|",
        "add_text_input|boren_tlpaste_raw|Tempel Gudang di sini:||9999|",
        "add_checkbox|boren_tlpaste_replace|Ganti seluruh daftar (Replace)|0|",
        "add_button|boren_submit_tlpaste|`2+ Tempel / Tambah ke Gudang Alat|noflags|0|0|",
        "add_spacer|small|",
        string.format("add_textbox|`2[3. Daftar Gudang Alat Saat Ini (%d World)]|left|", #(CFG.storage_tool_list or {}))
    }

    if #(CFG.storage_tool_list or {}) == 0 then
        table.insert(d, "add_textbox|`4(Gudang Alat masih kosong. Silakan tempel di atas!)|left|")
    else
        for i, e in ipairs(CFG.storage_tool_list) do
            local doorStr = (e.door and e.door ~= "") and e.door or "-"
            table.insert(d, string.format("add_textbox|`w%d. `9%s `o[Door: %s]|left|", i, e.name, doorStr))
            table.insert(d, string.format("add_button|boren_tledit_%d|Edit|noflags|0|0|", i))
            table.insert(d, string.format("add_button|boren_tlhapus_%d|Hapus|noflags|0|0|", i))
            table.insert(d, "add_spacer|small|")
        end
    end

    table.insert(d, "end_dialog|boren_df_tool_mgr|Tutup||")
    return safeSendRawDialog(table.concat(d, "\n"))
end

openEditToolEntryDialog = function(idx)
    local entry = (CFG.storage_tool_list or {})[idx]
    if not entry then return end
    local d = {
        "set_default_color|`o",
        "add_quick_exit|",
        string.format("add_label_with_icon|big|`wEdit Gudang Alat #%d: %s``|left|242|", idx, entry.name),
        "add_spacer|small|",
        string.format("add_text_input|edit_tl_name|Nama World:|%s|32|", entry.name),
        string.format("add_text_input|edit_tl_door|Door ID:|%s|32|", entry.door or ""),
        "add_spacer|small|",
        "add_button|save_tl_edit|`2Simpan Perubahan|noflags|0|0|",
        "add_button|del_tl_edit|`4Hapus Gudang Ini|noflags|0|0|",
        string.format("end_dialog|boren_df_tool_edit_%d|Batal||", idx),
    }
    safeSendRawDialog(table.concat(d, "\n"))
end

openUnifiedSeedManager = function(fmt)
    fmt = fmt or "colon"
    local copyLines = {}
    for _, s in ipairs(CFG.storage_seed_list or {}) do
        local d = (s.door and s.door ~= "") and s.door or ""
        if fmt == "colon" then
            table.insert(copyLines, d ~= "" and (s.name .. ":" .. d) or s.name)
        elseif fmt == "pipe" then
            table.insert(copyLines, d ~= "" and (s.name .. "|" .. d) or s.name)
        else
            table.insert(copyLines, s.name)
        end
    end
    local rawBoxText = table.concat(copyLines, ", ")

    local d = {
        "set_default_color|`o",
        "add_quick_exit|",
        string.format("add_label_with_icon|big|`2Kelola Gudang Seed (%d)``|left|3|", #(CFG.storage_seed_list or {})),
        "add_textbox|`oGudang simpan Dirt Seed, Cave Seed, Lava Seed, Rock Seed, dsb.|left|",
        "add_spacer|small|",
        "add_textbox|`2[1. Salin Daftar Gudang Seed]|left|",
        string.format("add_text_input|boren_sdcopy_box|Salin Gudang Seed|%s|9999|", rawBoxText),
        "add_button|boren_btn_sdfmt_colon|Format Titik Dua (:)|noflags|0|0|",
        "add_button|boren_btn_sdfmt_pipe|Format Garis (|)|noflags|0|0|",
        "add_button|boren_btn_sdfmt_name|Hanya Nama World|noflags|0|0|",
        "add_spacer|small|",
        "add_textbox|`2[2. Tempel / Tambah Gudang Seed]|left|",
        "add_textbox|`eFormat: WORLD:DOOR atau WORLD|DOOR atau WORLD. Bebas koma/enter.|left|",
        "add_text_input|boren_sdpaste_raw|Tempel Gudang di sini:||9999|",
        "add_checkbox|boren_sdpaste_replace|Ganti seluruh daftar (Replace)|0|",
        "add_button|boren_submit_sdpaste|`2+ Tempel / Tambah ke Gudang Seed|noflags|0|0|",
        "add_spacer|small|",
        string.format("add_textbox|`2[3. Daftar Gudang Seed Saat Ini (%d World)]|left|", #(CFG.storage_seed_list or {}))
    }

    if #(CFG.storage_seed_list or {}) == 0 then
        table.insert(d, "add_textbox|`4(Gudang Seed masih kosong. Silakan tempel di atas!)|left|")
    else
        for i, e in ipairs(CFG.storage_seed_list) do
            local doorStr = (e.door and e.door ~= "") and e.door or "-"
            table.insert(d, string.format("add_textbox|`w%d. `9%s `o[Door: %s]|left|", i, e.name, doorStr))
            table.insert(d, string.format("add_button|boren_sdedit_%d|Edit|noflags|0|0|", i))
            table.insert(d, string.format("add_button|boren_sdhapus_%d|Hapus|noflags|0|0|", i))
            table.insert(d, "add_spacer|small|")
        end
    end

    table.insert(d, "end_dialog|boren_df_seed_mgr|Tutup||")
    return safeSendRawDialog(table.concat(d, "\n"))
end

openEditSeedEntryDialog = function(idx)
    local entry = (CFG.storage_seed_list or {})[idx]
    if not entry then return end
    local d = {
        "set_default_color|`o",
        "add_quick_exit|",
        string.format("add_label_with_icon|big|`wEdit Gudang Seed #%d: %s``|left|3|", idx, entry.name),
        "add_spacer|small|",
        string.format("add_text_input|edit_sd_name|Nama World:|%s|32|", entry.name),
        string.format("add_text_input|edit_sd_door|Door ID:|%s|32|", entry.door or ""),
        "add_spacer|small|",
        "add_button|save_sd_edit|`2Simpan Perubahan|noflags|0|0|",
        "add_button|del_sd_edit|`4Hapus Gudang Ini|noflags|0|0|",
        string.format("end_dialog|boren_df_seed_edit_%d|Batal||", idx),
    }
    safeSendRawDialog(table.concat(d, "\n"))
end

openEditTrashEntryDialog = function(idx)
    local list = getConfiguredTrashItemList()
    local curId = list[idx]
    if not curId then return end
    local dLines = {
        "set_default_color|`o",
        string.format("add_label_with_icon|big|`wEdit Item Trash #%d``|left|%d|", idx, curId),
        string.format("add_textbox|`oItem saat ini: `w%s (ID: %d)|left|", resolveItemName(curId), curId),
        "add_spacer|small|",
        string.format("add_text_input|edit_trash_id|Item ID Baru|%d|12|", curId),
        "add_spacer|small|",
        "add_button|save_t_edit|`2Simpan Perubahan|noflags|0|0|",
        "add_button|del_t_edit|`4Hapus Item Ini|noflags|0|0|",
        string.format("end_dialog|boren_trash_edit_%d|Batal||", idx),
    }
    safeSendRawDialog(table.concat(dLines, "\n"))
end

openTrashListManagerDialog = function()
    local list = getConfiguredTrashItemList()
    local thresh = math.max(10, tonumber(CFG.trash_threshold) or 150)
    local dLines = {
        "set_default_color|`o",
        string.format("add_label_with_icon|big|`wList Auto-Trash (%d)``|left|18|", #list),
        string.format("add_textbox|`oAuto-Trash aktif saat jumlah >= `2%d`o. Tekan `9Edit`o atau `4Hapus`o di tiap item.|left|", thresh),
    }
    if #list == 0 then
        table.insert(dLines, "add_spacer|small|")
        table.insert(dLines, "add_textbox|`4List Trash masih kosong. Tambah ID item lewat kolom di bawah!|left|")
    else
        for i, id in ipairs(list) do
            table.insert(dLines, "add_spacer|small|")
            table.insert(dLines, string.format("add_textbox|`w%d. %s `o(ID: `2%d`o | BP: %d)|left|", i, resolveItemName(id), id, getInvCount(id)))
            table.insert(dLines, string.format("add_button|boren_tedit_%d|`9Edit #%d|noflags|0|0|", i, i))
            table.insert(dLines, string.format("add_button|boren_thapus_%d|`4Hapus #%d|noflags|0|0|", i, i))
        end
    end
    table.insert(dLines, "add_spacer|small|")
    table.insert(dLines, "add_text_input|boren_new_trash_id|Tambah Item ID Baru||12|")
    table.insert(dLines, "add_button|boren_tadd|`2+ Tambah ke Trash|noflags|0|0|")
    table.insert(dLines, "add_button|boren_treset|`6Reset Default (Lava, Cave, Rock)|noflags|0|0|")
    table.insert(dLines, "end_dialog|boren_trash_mgr|Tutup||")
    return safeSendRawDialog(table.concat(dLines, "\n"))
end

openPasteWorldListDialog = function()
    local dLines = {
        "set_default_color|`o",
        "add_label_with_icon|big|`wInput Banyak World (Quick Paste)``|left|1240|",
        "add_textbox|`oFormat: `2WORLD:ID `oatau `2WORLD|ID `oatau `2WORLD|left|",
        "add_textbox|`9Contoh: `wDF1:DOOR1, DF2:DOOR2, DF3|left|",
        "add_textbox|`7(Pemisah bisa koma `,`, titik koma `;`, spasi, atau ganti baris/enter)|left|",
        "add_spacer|small|",
        "add_text_input|boren_paste_raw|Tempel List World di sini:||9999|",
        "add_spacer|small|",
        "add_checkbox|boren_paste_replace|Ganti semua antrean yang ada saat ini (Replace)|0|",
        "add_spacer|small|",
        "add_button|boren_submit_paste|`2[+ Masukkan ke Antrean]|noflags|0|0|",
        "add_button|boren_cancel_paste|`4[Batal]|noflags|0|0|",
        "end_dialog|boren_paste_mgr|||",
    }
    local d = table.concat(dLines, "\n")
    if sendVariant then
        pcall(sendVariant, { v0 = "OnDialogRequest", v1 = d })
        return true
    elseif growtopia and growtopia.sendDialog then
        pcall(growtopia.sendDialog, d)
        return true
    end
    return false
end

openCopyAllWorldsDialog = function(fmt)
    fmt = fmt or "colon"
    local lines = {}
    for _, entry in ipairs(CFG.world_list) do
        if entry and entry.name and entry.name ~= "" then
            local d = (entry.door and entry.door ~= "") and entry.door or ""
            if fmt == "pipe" then
                table.insert(lines, (d ~= "") and (entry.name .. "|" .. d) or entry.name)
            elseif fmt == "name_only" then
                table.insert(lines, entry.name)
            else -- colon default
                table.insert(lines, (d ~= "") and (entry.name .. ":" .. d) or entry.name)
            end
        end
    end
    local fullText = table.concat(lines, "\n")
    local count = #CFG.world_list

    -- Coba copy otomatis ke clipboard jika ImGui tersedia
    if ImGui and ImGui.SetClipboardText and fullText ~= "" then
        pcall(ImGui.SetClipboardText, fullText)
    end

    local dLines = {
        "set_default_color|`o",
        string.format("add_label_with_icon|big|`wDaftar Semua Farm World (%d World)``|left|1240|", count),
        "add_textbox|`oDi bawah ini seluruh daftar world farm saat ini.|left|",
        "add_textbox|`2Cara Salin di HP: `oTekan & tahan teks di kotak bawah -> `2Select All `o-> `2Copy|left|",
        "add_spacer|small|",
        string.format("add_text_input|boren_copy_field|Daftar World|%s|9999|", fullText),
        "add_spacer|small|",
        "add_textbox|`wGanti Format Tampilan / Salin:|left|",
        "add_button|boren_btn_fmt_colon|`9[Format WORLD:DOOR]|noflags|0|0|",
        "add_button|boren_btn_fmt_pipe|`9[Format WORLD|DOOR]|noflags|0|0|",
        "add_button|boren_btn_fmt_name|`9[Hanya Nama World]|noflags|0|0|",
        "add_spacer|small|",
        "add_button|boren_btn_copy_close|`2[Selesai / Tutup]|noflags|0|0|",
        "end_dialog|boren_copy_mgr|||",
    }
    local d = table.concat(dLines, "\n")
    if sendVariant then
        pcall(sendVariant, { v0 = "OnDialogRequest", v1 = d })
        return true
    elseif growtopia and growtopia.sendDialog then
        pcall(growtopia.sendDialog, d)
        return true
    end
    return false
end

openFileBrowserManagerDialog = function()
    local curW = getWorldNameSafe()
    if curW == "" or curW == "EXIT" then
        if sendNotification then pcall(sendNotification, "Silakan masuk ke world mana saja terlebih dahulu untuk membuka File Manager!") end
        return false
    end
    local fullPath, dir, currentFn = resolveWorldFilePath()
    local files, targetDir = scanFolderTxtFiles(dir)
    local pInfo = getFolderPresetInfo(CFG.world_folder_mode)
    local okF, statusMsg = checkWorldFileStatus(fullPath)

    local dLines = {
        "set_default_color|`o",
        "add_label_with_icon|big|`wFile & Folder Manager DF``|left|1240|",
        string.format("add_textbox|`oFolder HP: `2%s `o(`w%s`o)|left|", (targetDir ~= "" and targetDir or "(Folder Game/Current)"), pInfo.label),
        string.format("add_textbox|`oFile Aktif: `2%s `o| Status: %s|left|", currentFn, okF and ("`2" .. statusMsg) or ("`4" .. statusMsg)),
        string.format("add_textbox|`9Path: `o%s|left|", fullPath),
        "add_spacer|small|",
        "add_textbox|`wPilih Preset Folder HP:|left|",
        "add_button|boren_fdir_download|`9[1. Download]|noflags|0|0|",
        "add_button|boren_fdir_documents|`9[2. Documents]|noflags|0|0|",
        "add_button|boren_fdir_scriptgl|`9[3. Script GL]|noflags|0|0|",
        "add_button|boren_fdir_internal|`9[4. Internal SD]|noflags|0|0|",
        "add_button|boren_fdir_custom|`9[5. Custom]|noflags|0|0|",
        "add_spacer|small|",
    }

    if #files == 0 then
        table.insert(dLines, "add_textbox|`4Tidak ada file .txt terdeteksi di folder ini.|left|")
        table.insert(dLines, "add_textbox|`oKetik nama file baru di bawah lalu klik Simpan File.|left|")
    else
        table.insert(dLines, string.format("add_textbox|`wFile .txt Ditemukan (%d file di folder ini):|left|", #files))
        for i, fInfo in ipairs(files) do
            local isCur = (fInfo.name == currentFn)
            local icon = isCur and "`2▶ " or "`w"
            table.insert(dLines, "add_spacer|small|")
            table.insert(dLines, string.format("add_textbox|%s%d. %s `o(%s)|left|", icon, i, fInfo.name, fInfo.info or ""))
            table.insert(dLines, string.format("add_button|boren_fpick_%d|`2Pilih & Load #%d|noflags|0|0|", i, i))
        end
    end

    table.insert(dLines, "add_spacer|small|")
    table.insert(dLines, string.format("add_text_input|boren_input_fname|Nama File (.txt)|%s|32|", currentFn))
    if CFG.world_folder_mode == "custom" then
        table.insert(dLines, string.format("add_text_input|boren_input_fdir|Custom Path Folder|%s|80|", CFG.world_custom_folder or ""))
    end
    table.insert(dLines, "add_spacer|small|")
    table.insert(dLines, "add_button|boren_fbtn_save|`2Simpan ke File Ini|noflags|0|0|")
    table.insert(dLines, "add_button|boren_fbtn_load|`9Load dari File Ini|noflags|0|0|")
    table.insert(dLines, "add_button|boren_fbtn_rescan|`6Scan Ulang Folder|noflags|0|0|")
    table.insert(dLines, "end_dialog|boren_file_mgr|Tutup||")

    return safeSendRawDialog(table.concat(dLines, "\n"))
end

local function openMiniConsoleDialog(errorsOnly)
    local onlyErr = (errorsOnly == true)
    local srcList = onlyErr and STATE.error_logs or STATE.logs
    local modeLabel = onlyErr and "Hanya Error/Warn" or "Semua Log"

    if growtopia and growtopia.sendDialog and getWorldNameSafe() ~= "EXIT" then
        local dLines = {
            "set_default_color|`o",
            string.format("add_label_with_icon|big|`wBoren Mini Console (%s)``|left|32|", modeLabel),
            string.format("add_textbox|`oStatus: `2%s `o| World: `w%s `o| Error: `4%d|left|", tostring(STATE.current_step), tostring(STATE.current_world), tonumber(STATE.error_count) or 0),
            "add_spacer|small|",
        }
        if #srcList == 0 then
            table.insert(dLines, string.format("add_textbox|`2Belum ada catatan pada mode %s.|left|", modeLabel))
        else
            local maxShow = math.min(14, #srcList)
            for i = 1, maxShow do
                local lineTxt = tostring(srcList[i]):gsub("|", "/")
                local col = isErrorMessage(lineTxt) and "`4" or "`o"
                table.insert(dLines, string.format("add_textbox|%s%s|left|", col, lineTxt))
            end
        end
        table.insert(dLines, "add_spacer|small|")
        table.insert(dLines, "add_button|console_all|`2Semua Log|noflags|0|0|")
        table.insert(dLines, "add_button|console_err|`4Error Saja|noflags|0|0|")
        table.insert(dLines, "add_button|console_clear|`9Clear Log|noflags|0|0|")
        table.insert(dLines, "end_dialog|boren_mini_console|Tutup||")
        pcall(growtopia.sendDialog, table.concat(dLines, "\n"))
        return true
    elseif sendDialog then
        local lines = {
            string.format("Status: %s | World: %s | Total Error: %d", tostring(STATE.current_step), tostring(STATE.current_world), tonumber(STATE.error_count) or 0),
            "------------------------------------"
        }
        if #srcList == 0 then
            table.insert(lines, "(Belum ada catatan)")
        else
            for i = 1, math.min(12, #srcList) do
                table.insert(lines, tostring(srcList[i]))
            end
        end
        pcall(sendDialog, {
            title = "Mini Console (" .. modeLabel .. ")",
            alias = "boren_mini_console_dlg",
            message = table.concat(lines, "\n"),
            confirm = "OK"
        })
        return true
    end
    return false
end

local function onVariantDialogHook(var, pkt)
    if not var then return end
    local ok, shouldBlock = pcall(function()
        local v1 = var.v1
        if v1 == "OnDialogRequest" then
            local raw = tostring(var.v2 or "")
            local dName = raw:match("end_dialog|([^|\n]+)") or ""
            STATE.last_dialog_text = raw
            STATE.last_dialog_name = dName
            STATE.last_dialog_seq = (STATE.last_dialog_seq or 0) + 1
            if STATE.suppress_dialog then
                return true
            end
        end
        return false
    end)
    if ok and shouldBlock then
        return true
    end
end

local function onSendPacketDialogHook(ptype, pkt)
    if type(pkt) ~= "string" then return end
    local ok, shouldBlock = pcall(function()
        if not pkt:find("action|dialog_return", 1, true) then
            return false
        end
        local fields = parseDialogReturnFields(pkt)
        local dName = fields.dialog_name or ""

        if dName == "boren_world_mgr" or dName == "boren_paste_mgr" or dName == "boren_copy_mgr" then
            local btn = fields.buttonClicked or ""
            local delIdx = btn:match("^boren_whapus_(%d+)$")
            local editIdx = btn:match("^boren_wedit_(%d+)$")

            if btn == "boren_btn_wfmt_colon" or btn == "boren_btn_fmt_colon" then
                openWorldListManagerDialog("colon")
                return true
            elseif btn == "boren_btn_wfmt_pipe" or btn == "boren_btn_fmt_pipe" then
                openWorldListManagerDialog("pipe")
                return true
            elseif btn == "boren_btn_wfmt_name" or btn == "boren_btn_fmt_name" then
                openWorldListManagerDialog("name_only")
                return true
            elseif btn == "boren_submit_wpaste" or btn == "boren_submit_paste" then
                local raw = pkt:match("boren_wpaste_raw|(.-)\nboren_wpaste_replace|")
                    or pkt:match("boren_paste_raw|(.-)\nboren_paste_replace|")
                    or pkt:match("boren_wpaste_raw|(.-)\nbuttonClicked|")
                    or pkt:match("boren_paste_raw|(.-)\nbuttonClicked|")
                    or fields.boren_wpaste_raw or fields.boren_paste_raw or ""
                local isReplace = (fields.boren_wpaste_replace == "1" or fields.boren_paste_replace == "1")
                local added, dups, ign, msg = parseAndValidateWorldBatch(raw, isReplace)
                if updateWorldDisplayList then updateWorldDisplayList() end
                if sendNotification then pcall(sendNotification, msg) end
                openWorldListManagerDialog()
                return true
            elseif delIdx then
                local okDel, msg = deleteWorldEntryAt(tonumber(delIdx))
                if updateWorldDisplayList then updateWorldDisplayList() end
                if sendNotification then pcall(sendNotification, msg) end
                openWorldListManagerDialog()
                return true
            elseif editIdx then
                openEditWorldEntryDialog(tonumber(editIdx))
                return true
            elseif btn == "boren_wadd" then
                local added = addManualWorldsFromString(fields.boren_new_w or "", fields.boren_new_d or "", false)
                if updateWorldDisplayList then updateWorldDisplayList() end
                if added > 0 then
                    if sendNotification then pcall(sendNotification, string.format("%d World ditambahkan! (Total: %d)", added, #CFG.world_list)) end
                else
                    if sendNotification then pcall(sendNotification, "Isi kolom Tambah World Baru terlebih dulu!") end
                end
                openWorldListManagerDialog()
                return true
            end
            return true
        end

        local editTargetIdx = dName:match("^boren_world_edit_(%d+)$")
        if editTargetIdx then
            local idx = tonumber(editTargetIdx)
            local btn = fields.buttonClicked or ""
            if btn == "del_w_edit" then
                local _, msg = deleteWorldEntryAt(idx)
                if sendNotification then pcall(sendNotification, msg) end
            elseif btn == "save_w_edit" or fields.edit_w_name then
                local _, msg = editWorldEntryAt(idx, fields.edit_w_name or "", fields.edit_w_door or "")
                if sendNotification then pcall(sendNotification, msg) end
            end
            openWorldListManagerDialog()
            return true
        end

        if dName == "boren_trash_mgr" then
            local btn = fields.buttonClicked or ""
            local delIdx = btn:match("^boren_thapus_(%d+)$")
            local editIdx = btn:match("^boren_tedit_(%d+)$")
            local list = getConfiguredTrashItemList()
            if delIdx then
                local idx = tonumber(delIdx)
                if idx and idx >= 1 and idx <= #list then
                    local removedId = table.remove(list, idx)
                    setTrashListFromTable(list)
                    persistConfig()
                    if updateTrashDisplayList then pcall(updateTrashDisplayList) end
                    if sendNotification then pcall(sendNotification, "Dihapus dari Trash: " .. resolveItemName(removedId)) end
                end
                openTrashListManagerDialog()
            elseif editIdx then
                openEditTrashEntryDialog(tonumber(editIdx))
            elseif btn == "boren_treset" then
                CFG.trash_list_str = "4,14,10"
                persistConfig()
                if updateTrashDisplayList then pcall(updateTrashDisplayList) end
                if sendNotification then pcall(sendNotification, "List Trash direset ke default!") end
                openTrashListManagerDialog()
            elseif btn == "boren_tadd" or (fields.boren_new_trash_id and fields.boren_new_trash_id ~= "") then
                local newId = math.floor(tonumber(fields.boren_new_trash_id) or 0)
                if newId > 0 then
                    local exists = false
                    for _, v in ipairs(list) do if v == newId then exists = true; break end end
                    if not exists then table.insert(list, newId) end
                    setTrashListFromTable(list)
                    persistConfig()
                    if updateTrashDisplayList then pcall(updateTrashDisplayList) end
                    if sendNotification then pcall(sendNotification, "Ditambah ke Trash: " .. resolveItemName(newId)) end
                elseif sendNotification then
                    pcall(sendNotification, "Isi Item ID yang valid (angka > 0)!")
                end
                openTrashListManagerDialog()
            end
            return true
        end

        local editTrashIdx = dName:match("^boren_trash_edit_(%d+)$")
        if editTrashIdx then
            local idx = tonumber(editTrashIdx)
            local btn = fields.buttonClicked or ""
            local list = getConfiguredTrashItemList()
            if idx and idx >= 1 and idx <= #list then
                if btn == "del_t_edit" then
                    local removedId = table.remove(list, idx)
                    setTrashListFromTable(list)
                    persistConfig()
                    if updateTrashDisplayList then pcall(updateTrashDisplayList) end
                    if sendNotification then pcall(sendNotification, "Dihapus dari Trash: " .. resolveItemName(removedId)) end
                elseif btn == "save_t_edit" or fields.edit_trash_id then
                    local newId = math.floor(tonumber(fields.edit_trash_id) or 0)
                    if newId > 0 then
                        list[idx] = newId
                        setTrashListFromTable(list)
                        persistConfig()
                        if updateTrashDisplayList then pcall(updateTrashDisplayList) end
                        if sendNotification then pcall(sendNotification, "Item Trash #" .. tostring(idx) .. " -> " .. resolveItemName(newId)) end
                    end
                end
            end
            openTrashListManagerDialog()
            return true
        end

        if dName == "boren_df_tool_mgr" then
            local btn = fields.buttonClicked or ""
            local delIdx = btn:match("^boren_tlhapus_(%d+)$")
            local editIdx = btn:match("^boren_tledit_(%d+)$")

            if btn == "boren_btn_tlfmt_colon" then
                openUnifiedToolManager("colon")
                return true
            elseif btn == "boren_btn_tlfmt_pipe" then
                openUnifiedToolManager("pipe")
                return true
            elseif btn == "boren_btn_tlfmt_name" then
                openUnifiedToolManager("name_only")
                return true
            elseif btn == "boren_submit_tlpaste" then
                local raw = pkt:match("boren_tlpaste_raw|(.-)\nboren_tlpaste_replace|")
                    or pkt:match("boren_tlpaste_raw|(.-)\nbuttonClicked|")
                    or fields.boren_tlpaste_raw or ""
                local isReplace = (fields.boren_tlpaste_replace == "1")
                local parsed = parseStorageBatchFromString(raw)
                if isReplace then
                    CFG.storage_tool_list = {}
                end
                local added = 0
                for _, item in ipairs(parsed) do
                    local exists = false
                    for _, ex in ipairs(CFG.storage_tool_list) do
                        if ex.name == item.name then exists = true; break end
                    end
                    if not exists then
                        table.insert(CFG.storage_tool_list, { name = item.name, door = item.door })
                        added = added + 1
                    end
                end
                if #CFG.storage_tool_list > 0 then
                    CFG.storage_pack_world = CFG.storage_tool_list[1].name
                    CFG.storage_pack_door = CFG.storage_tool_list[1].door or ""
                else
                    CFG.storage_pack_world = ""
                    CFG.storage_pack_door = ""
                end
                persistConfig()
                if updateToolStorageDisplayList then pcall(updateToolStorageDisplayList) end
                if sendNotification then pcall(sendNotification, string.format("%d Gudang Alat dimasukkan! (Total: %d)", added, #CFG.storage_tool_list)) end
                openUnifiedToolManager()
                return true
            elseif delIdx then
                local idx = tonumber(delIdx)
                if idx and CFG.storage_tool_list[idx] then
                    local removed = table.remove(CFG.storage_tool_list, idx)
                    if #CFG.storage_tool_list > 0 then
                        CFG.storage_pack_world = CFG.storage_tool_list[1].name
                        CFG.storage_pack_door = CFG.storage_tool_list[1].door or ""
                    else
                        CFG.storage_pack_world = ""
                        CFG.storage_pack_door = ""
                    end
                    persistConfig()
                    if updateToolStorageDisplayList then pcall(updateToolStorageDisplayList) end
                    if sendNotification then pcall(sendNotification, "Gudang Alat #" .. idx .. " (" .. tostring(removed.name) .. ") dihapus!") end
                end
                openUnifiedToolManager()
                return true
            elseif editIdx then
                openEditToolEntryDialog(tonumber(editIdx))
                return true
            end
            return true
        end

        local editToolTargetIdx = dName:match("^boren_df_tool_edit_(%d+)$")
        if editToolTargetIdx then
            local idx = tonumber(editToolTargetIdx)
            local btn = fields.buttonClicked or ""
            if idx and CFG.storage_tool_list[idx] then
                if btn == "del_tl_edit" then
                    table.remove(CFG.storage_tool_list, idx)
                    if #CFG.storage_tool_list > 0 then
                        CFG.storage_pack_world = CFG.storage_tool_list[1].name
                        CFG.storage_pack_door = CFG.storage_tool_list[1].door or ""
                    else
                        CFG.storage_pack_world = ""
                        CFG.storage_pack_door = ""
                    end
                    persistConfig()
                    if updateToolStorageDisplayList then pcall(updateToolStorageDisplayList) end
                    if sendNotification then pcall(sendNotification, "Gudang Alat #" .. idx .. " dihapus!") end
                elseif btn == "save_tl_edit" or fields.edit_tl_name then
                    local newName = tostring(fields.edit_tl_name or ""):gsub("^%s+", ""):gsub("%s+$", ""):upper()
                    local newDoor = tostring(fields.edit_tl_door or ""):gsub("^%s+", ""):gsub("%s+$", "")
                    if newName ~= "" then
                        CFG.storage_tool_list[idx].name = newName
                        CFG.storage_tool_list[idx].door = newDoor
                        if idx == 1 then
                            CFG.storage_pack_world = newName
                            CFG.storage_pack_door = newDoor
                        end
                        persistConfig()
                        if updateToolStorageDisplayList then pcall(updateToolStorageDisplayList) end
                        if sendNotification then pcall(sendNotification, "Gudang Alat #" .. idx .. " diubah -> " .. newName) end
                    end
                end
            end
            openUnifiedToolManager()
            return true
        end

        if dName == "boren_df_seed_mgr" then
            local btn = fields.buttonClicked or ""
            local delIdx = btn:match("^boren_sdhapus_(%d+)$")
            local editIdx = btn:match("^boren_sdedit_(%d+)$")

            if btn == "boren_btn_sdfmt_colon" then
                openUnifiedSeedManager("colon")
                return true
            elseif btn == "boren_btn_sdfmt_pipe" then
                openUnifiedSeedManager("pipe")
                return true
            elseif btn == "boren_btn_sdfmt_name" then
                openUnifiedSeedManager("name_only")
                return true
            elseif btn == "boren_submit_sdpaste" then
                local raw = pkt:match("boren_sdpaste_raw|(.-)\nboren_sdpaste_replace|")
                    or pkt:match("boren_sdpaste_raw|(.-)\nbuttonClicked|")
                    or fields.boren_sdpaste_raw or ""
                local isReplace = (fields.boren_sdpaste_replace == "1")
                local parsed = parseStorageBatchFromString(raw)
                if isReplace then
                    CFG.storage_seed_list = {}
                end
                local added = 0
                for _, item in ipairs(parsed) do
                    local exists = false
                    for _, ex in ipairs(CFG.storage_seed_list) do
                        if ex.name == item.name then exists = true; break end
                    end
                    if not exists then
                        table.insert(CFG.storage_seed_list, { name = item.name, door = item.door })
                        added = added + 1
                    end
                end
                if #CFG.storage_seed_list > 0 then
                    CFG.storage_seed_world = CFG.storage_seed_list[1].name
                    CFG.storage_seed_door = CFG.storage_seed_list[1].door or ""
                else
                    CFG.storage_seed_world = ""
                    CFG.storage_seed_door = ""
                end
                persistConfig()
                if updateSeedStorageDisplayList then pcall(updateSeedStorageDisplayList) end
                if sendNotification then pcall(sendNotification, string.format("%d Gudang Seed dimasukkan! (Total: %d)", added, #CFG.storage_seed_list)) end
                openUnifiedSeedManager()
                return true
            elseif delIdx then
                local idx = tonumber(delIdx)
                if idx and CFG.storage_seed_list[idx] then
                    local removed = table.remove(CFG.storage_seed_list, idx)
                    if #CFG.storage_seed_list > 0 then
                        CFG.storage_seed_world = CFG.storage_seed_list[1].name
                        CFG.storage_seed_door = CFG.storage_seed_list[1].door or ""
                    else
                        CFG.storage_seed_world = ""
                        CFG.storage_seed_door = ""
                    end
                    persistConfig()
                    if updateSeedStorageDisplayList then pcall(updateSeedStorageDisplayList) end
                    if sendNotification then pcall(sendNotification, "Gudang Seed #" .. idx .. " (" .. tostring(removed.name) .. ") dihapus!") end
                end
                openUnifiedSeedManager()
                return true
            elseif editIdx then
                openEditSeedEntryDialog(tonumber(editIdx))
                return true
            end
            return true
        end

        local editSeedTargetIdx = dName:match("^boren_df_seed_edit_(%d+)$")
        if editSeedTargetIdx then
            local idx = tonumber(editSeedTargetIdx)
            local btn = fields.buttonClicked or ""
            if idx and CFG.storage_seed_list[idx] then
                if btn == "del_sd_edit" then
                    table.remove(CFG.storage_seed_list, idx)
                    if #CFG.storage_seed_list > 0 then
                        CFG.storage_seed_world = CFG.storage_seed_list[1].name
                        CFG.storage_seed_door = CFG.storage_seed_list[1].door or ""
                    else
                        CFG.storage_seed_world = ""
                        CFG.storage_seed_door = ""
                    end
                    persistConfig()
                    if updateSeedStorageDisplayList then pcall(updateSeedStorageDisplayList) end
                    if sendNotification then pcall(sendNotification, "Gudang Seed #" .. idx .. " dihapus!") end
                elseif btn == "save_sd_edit" or fields.edit_sd_name then
                    local newName = tostring(fields.edit_sd_name or ""):gsub("^%s+", ""):gsub("%s+$", ""):upper()
                    local newDoor = tostring(fields.edit_sd_door or ""):gsub("^%s+", ""):gsub("%s+$", "")
                    if newName ~= "" then
                        CFG.storage_seed_list[idx].name = newName
                        CFG.storage_seed_list[idx].door = newDoor
                        if idx == 1 then
                            CFG.storage_seed_world = newName
                            CFG.storage_seed_door = newDoor
                        end
                        persistConfig()
                        if updateSeedStorageDisplayList then pcall(updateSeedStorageDisplayList) end
                        if sendNotification then pcall(sendNotification, "Gudang Seed #" .. idx .. " diubah -> " .. newName) end
                    end
                end
            end
            openUnifiedSeedManager()
            return true
        end

        if dName == "boren_mini_console" then
            local btn = fields.buttonClicked or ""
            if btn == "console_all" then
                STATE.console_errors_only = false
                openMiniConsoleDialog(false)
            elseif btn == "console_err" then
                STATE.console_errors_only = true
                openMiniConsoleDialog(true)
            elseif btn == "console_clear" then
                STATE.logs = {}
                STATE.error_logs = {}
                STATE.error_count = 0
                openMiniConsoleDialog(STATE.console_errors_only)
            end
            return true
        end

        if dName == "boren_paste_mgr" then
            local btn = fields.buttonClicked or ""
            if btn == "boren_submit_paste" then
                local raw = pkt:match("boren_paste_raw|(.-)\nboren_paste_replace|")
                    or pkt:match("boren_paste_raw|(.-)\nbuttonClicked|")
                    or fields.boren_paste_raw
                    or ""
                local isReplace = (fields.boren_paste_replace == "1") or (pkt:find("boren_paste_replace|1", 1, true) ~= nil)
                local added, dups, ignored, summary = parseAndValidateWorldBatch(raw, isReplace)
                addLog("[Quick Paste] " .. summary)
                if sendNotification then pcall(sendNotification, summary) end
                if sendDialog then
                    pcall(sendDialog, {
                        title = "Hasil Input World (" .. tostring(added) .. " Ditambahkan)",
                        alias = "boren_paste_result",
                        message = summary,
                        confirm = "OK"
                    })
                end
            end
            return true
        end

        if dName == "boren_copy_mgr" then
            local btn = fields.buttonClicked or ""
            if btn == "boren_btn_fmt_colon" then
                openCopyAllWorldsDialog("colon")
            elseif btn == "boren_btn_fmt_pipe" then
                openCopyAllWorldsDialog("pipe")
            elseif btn == "boren_btn_fmt_name" then
                openCopyAllWorldsDialog("name_only")
            end
            return true
        end

        if dName == "boren_file_mgr" then
            local btn = fields.buttonClicked or ""
            local pickIdx = btn:match("^boren_fpick_(%d+)$")
            local dirPreset = btn:match("^boren_fdir_(.+)$")

            if dirPreset then
                CFG.world_folder_mode = dirPreset
                persistConfig()
                if updateFileInfoDisplayList then pcall(updateFileInfoDisplayList) end
                if sendNotification then pcall(sendNotification, "Folder diubah -> " .. getFolderPresetInfo(dirPreset).label) end
                openFileBrowserManagerDialog()
            elseif pickIdx then
                local idx = tonumber(pickIdx)
                local fullPath, dir = resolveWorldFilePath()
                local files = scanFolderTxtFiles(dir)
                if idx and files[idx] then
                    CFG.world_file_name = files[idx].name
                    persistConfig()
                    loadWorldListFromStorage(true)
                    if updateWorldDisplayList then pcall(updateWorldDisplayList) end
                    if updateFileInfoDisplayList then pcall(updateFileInfoDisplayList) end
                    if sendNotification then pcall(sendNotification, "File dimuat: " .. files[idx].name) end
                end
                openFileBrowserManagerDialog()
            elseif btn == "boren_fbtn_save" then
                local newFname = fields.boren_input_fname or ""
                if newFname ~= "" then
                    CFG.world_file_name = newFname:gsub("^%s+", ""):gsub("%s+$", "")
                end
                if fields.boren_input_fdir and fields.boren_input_fdir ~= "" then
                    CFG.world_custom_folder = fields.boren_input_fdir:gsub("^%s+", ""):gsub("%s+$", "")
                end
                saveWorldListToStorage(false)
                if updateFileInfoDisplayList then pcall(updateFileInfoDisplayList) end
                openFileBrowserManagerDialog()
            elseif btn == "boren_fbtn_load" then
                local newFname = fields.boren_input_fname or ""
                if newFname ~= "" then
                    CFG.world_file_name = newFname:gsub("^%s+", ""):gsub("%s+$", "")
                end
                if fields.boren_input_fdir and fields.boren_input_fdir ~= "" then
                    CFG.world_custom_folder = fields.boren_input_fdir:gsub("^%s+", ""):gsub("%s+$", "")
                end
                persistConfig()
                loadWorldListFromStorage(true)
                if updateWorldDisplayList then pcall(updateWorldDisplayList) end
                if updateFileInfoDisplayList then updateFileInfoDisplayList() end
                openFileBrowserManagerDialog()
            elseif btn == "boren_fbtn_rescan" then
                if fields.boren_input_fname and fields.boren_input_fname ~= "" then
                    CFG.world_file_name = fields.boren_input_fname:gsub("^%s+", ""):gsub("%s+$", "")
                end
                if fields.boren_input_fdir and fields.boren_input_fdir ~= "" then
                    CFG.world_custom_folder = fields.boren_input_fdir:gsub("^%s+", ""):gsub("%s+$", "")
                end
                persistConfig()
                if updateFileInfoDisplayList then pcall(updateFileInfoDisplayList) end
                openFileBrowserManagerDialog()
            end
            return true
        end

        return false
    end)
    if ok and shouldBlock then
        return true
    end
end

local function onSendPacketRawCollectHook(pkt)
    if type(pkt) ~= "table" then return false end
    local pktType = tonumber(pkt.type)
    if pktType == 11 then
        if STATE.anti_take_active then
            return true -- Blokir paket collect (Packet 11) agar item/seed/block yang di-drop tidak tersedot kembali!
        end
    end
    return false
end

local function ensureRuntimeHooks()
    if STATE.runtime_hooks_installed then return end
    STATE.runtime_hooks_installed = true
    onVariant = onVariantDialogHook
    OnVariant = onVariantDialogHook
    onSendPacket = onSendPacketDialogHook
    OnSendPacket = onSendPacketDialogHook
    onSendPacketRaw = onSendPacketRawCollectHook
    OnSendPacketRaw = onSendPacketRawCollectHook
    if addHook then
        pcall(addHook, onVariantDialogHook, "onvariant")
        pcall(addHook, onSendPacketDialogHook, "onsendpacket")
        pcall(addHook, onSendPacketRawCollectHook, "onsendpacketraw")
    end
    if applyHook then
        pcall(applyHook)
    end
end

-- Drop item dengan validasi Backpack (cek stok BP sebelum & sesudah drop + support dialog drop & confirmDropItem)
local function waitInvDecrease(itemID, beforeCnt, maxWaitMs)
    local waited = 0
    while waited < maxWaitMs do
        safeSleep(40)
        waited = waited + 40
        local cur = getInvCount(itemID)
        if cur < beforeCnt then
            return beforeCnt - cur, cur
        end
    end
    local finalCnt = getInvCount(itemID)
    return math.max(0, beforeCnt - finalCnt), finalCnt
end

-- Drop item mengutamakan API bawaan GrowLauncher (growtopia.confirmDropItem) agar seminim mungkin memicu dialog ganda, dengan fallback packet standar
local function dropItemSafe(itemID, count)
    local beforeCnt = getInvCount(itemID)
    if beforeCnt <= 0 or count <= 0 then
        return false, 0, beforeCnt
    end
    local wantDrop = math.min(count, beforeCnt)

    ensureRuntimeHooks()
    local prevAntiTake = STATE.anti_take_active
    STATE.anti_take_active = true
    setAutoCollectActive(false)

    if growtopia and growtopia.confirmDropItem then
        pcall(growtopia.confirmDropItem, itemID, wantDrop)
        local droppedNative, afterNative = waitInvDecrease(itemID, beforeCnt, 1400)
        if droppedNative > 0 then
            STATE.anti_take_active = prevAntiTake
            return true, droppedNative, afterNative
        end
    end
    if growtopia and growtopia.dropItem and wantDrop == 1 then
        pcall(growtopia.dropItem, itemID)
        local droppedOne, afterOne = waitInvDecrease(itemID, beforeCnt, 900)
        if droppedOne > 0 then
            STATE.anti_take_active = prevAntiTake
            return true, droppedOne, afterOne
        end
    end

    local prevSuppress = STATE.suppress_dialog
    STATE.suppress_dialog = true

    local prevSeq = STATE.last_dialog_seq or 0
    sendPacket(2, "action|drop\n|itemID|" .. tostring(itemID))
    safeSleep(180)

    local dropped = 0
    local afterCnt = beforeCnt
    if STATE.runtime_hooks_installed and (STATE.last_dialog_seq or 0) > prevSeq then
        local raw = STATE.last_dialog_text or ""
        local dName = STATE.last_dialog_name or ""
        if dName == "drop" or dName == "drop_item" or raw:find("drop", 1, true) then
            local pktStr = buildDialogReturn(raw, "drop_item", nil, nil, { count = tostring(wantDrop) }, nil, nil)
            sendPacket(2, pktStr)
            dropped, afterCnt = waitInvDecrease(itemID, beforeCnt, 800)
        end
    end

    if dropped <= 0 then
        for _, dlgName in ipairs({ "drop_item", "drop" }) do
            sendPacket(2, string.format(
                "action|dialog_return\ndialog_name|%s\nitemID|%d|\ncount|%d\n",
                dlgName, itemID, wantDrop
            ))
            dropped, afterCnt = waitInvDecrease(itemID, beforeCnt, 700)
            if dropped > 0 then break end
        end
    end

    STATE.suppress_dialog = prevSuppress
    STATE.anti_take_active = prevAntiTake
    return (dropped > 0), dropped, afterCnt
end

-- Wrench tile dan tunggu OnDialogRequest asli dari server lewat hook onvariant
local function wrenchAndAwaitDialog(tx, ty, expectedDialogName, standX, standY)
    ensureRuntimeHooks()
    if standX and standY and isTileSafeToStand(standX, standY) then
        moveSafeTo(standX, standY)
    else
        moveAdjacentSafe(tx, ty, 1)
    end
    local prevSeq = STATE.last_dialog_seq or 0
    sendRawAction(tx, ty, ITEM.WRENCH)

    local waited = 0
    while waited < 1600 do
        safeSleep(40)
        waited = waited + 40
        if (STATE.last_dialog_seq or 0) > prevSeq then
            local raw = STATE.last_dialog_text or ""
            local dName = STATE.last_dialog_name or ""
            if (not expectedDialogName) or dName == expectedDialogName or raw:find(expectedDialogName, 1, true) then
                return true, raw
            end
        end
    end
    return false, ""
end

-- Validated Edit Door ID & Label (tunggu OnDialogRequest, kirim dialog_return exact fields, lalu verifikasi)
local function validateAndEditDoorTile(tx, ty, doorID, doorLabel, standX, standY)
    local targetID = tostring(doorID or "DF123")
    local targetLabel = tostring(doorLabel or "BOREN STORE")
    STATE.suppress_dialog = true

    local validated = false
    for attempt = 1, 3 do
        if not waitIfPaused() then break end
        local ok, t = pcall(getTile, tx, ty)
        if not ok or not t or t.fg == 0 then
            break
        end

        local gotDlg, dlgText = wrenchAndAwaitDialog(tx, ty, "door_edit", standX, standY)
        if gotDlg then
            local meta = parseDialogFields(dlgText)
            local lockedLabel = (meta.checkbox_labels.checkbox_locked or ""):lower()
            -- Di Growtopia: "Is open to public" -> 1 agar Player + Door ID bisa masuk; jika label server "Locked/Private" -> 0
            local openBit = (lockedLabel:find("open", 1, true) or lockedLabel:find("public", 1, true) or lockedLabel == "") and "1" or "0"
            local pktStr = buildDialogReturn(
                dlgText,
                "door_edit",
                tx, ty,
                { door_name = targetLabel, door_target = "", door_id = targetID },
                { checkbox_locked = openBit },
                nil
            )
            sendPacket(2, pktStr)
            safeSleep(550)

            local gotV, verifyText = wrenchAndAwaitDialog(tx, ty, "door_edit", standX, standY)
            local okV, tV = pcall(getTile, tx, ty)
            local vMeta = gotV and parseDialogFields(verifyText) or nil
            if (okV and tV and tV.extra and tV.extra.label == targetLabel) or
               (vMeta and vMeta.inputs.door_name == targetLabel and vMeta.inputs.door_id == targetID) then
                validated = true
                break
            end
        else
            -- Fallback bila server/APK tidak memicu onVariant OnDialogRequest
            sendPacket(2, string.format(
                "action|dialog_return\ndialog_name|door_edit\ntilex|%d|\ntiley|%d|\ndoor_name|%s\ndoor_target|\ndoor_id|%s\ncheckbox_locked|1\n",
                tx, ty, targetLabel, targetID
            ))
            safeSleep(600)
            local okV, tV = pcall(getTile, tx, ty)
            if okV and tV and tV.extra and tV.extra.label == targetLabel then
                validated = true
                break
            end
        end
    end

    STATE.suppress_dialog = false
    addLog(string.format("Validasi Door ID (%d, %d) -> ID='%s' Label='%s' [%s]", tx, ty, targetID, targetLabel, validated and "OK" or "WARN"))
    return validated
end

-- Validated Edit World Lock (WL): Set Public = ON (checkbox_public = 1) & verify
local function validateAndEditWorldLock(tx, ty, isPublic, standX, standY)
    local pubBit = isPublic and "1" or "0"
    STATE.suppress_dialog = true

    local validated = false
    for attempt = 1, 4 do
        if not waitIfPaused() then break end
        local ok, t = pcall(getTile, tx, ty)
        if not ok or not t or t.fg ~= ITEM.WORLD_LOCK then
            break
        end

        local gotDlg, dlgText = wrenchAndAwaitDialog(tx, ty, "lock_edit", standX, standY)
        if gotDlg then
            local meta = parseDialogFields(dlgText)
            if meta.checkboxes.checkbox_public == pubBit then
                validated = true
                break
            end
            local pktStr = buildDialogReturn(
                dlgText,
                "lock_edit",
                tx, ty,
                nil,
                { checkbox_public = pubBit },
                nil
            )
            sendPacket(2, pktStr)
            safeSleep(550)

            local gotVerify, verifyText = wrenchAndAwaitDialog(tx, ty, "lock_edit", standX, standY)
            local vMeta = gotVerify and parseDialogFields(verifyText) or nil
            if vMeta and vMeta.checkboxes.checkbox_public == pubBit then
                validated = true
                break
            end
        else
            sendPacket(2, string.format(
                "action|dialog_return\ndialog_name|lock_edit\ntilex|%d|\ntiley|%d|\ncheckbox_public|%s\ncheckbox_disable_music|0\ntempo|100\ncheckbox_disable_music_render|0\ncheckbox_set_as_home_world|0\nminimum_entry_level|1\n",
                tx, ty, pubBit
            ))
            safeSleep(600)
            if attempt >= 2 then
                validated = true
                break
            end
        end
    end

    STATE.suppress_dialog = false
    addLog(string.format("Validasi WL (%d, %d) -> Public=%s [%s]", tx, ty, tostring(isPublic), validated and "OK" or "WARN"))
    return validated
end

-- Validated Edit Small Lock (SL): Set Public = OFF (0), Ignore Empty Air = ON (1), AND Apply Lock (recalcLock)
local function validateAndApplySmallLock(tx, ty, ignoreAir, isPublic, standX, standY)
    local pubBit = isPublic and "1" or "0"
    local ignBit = ignoreAir and "1" or "0"
    STATE.suppress_dialog = true

    local validated = false
    for attempt = 1, 4 do
        if not waitIfPaused() then break end
        local ok, t = pcall(getTile, tx, ty)
        if not ok or not t or t.fg ~= ITEM.SMALL_LOCK then
            break
        end

        local gotDlg, dlgText = wrenchAndAwaitDialog(tx, ty, "lock_edit", standX, standY)
        if gotDlg then
            -- Step 1: Simpan checkbox_public & checkbox_ignore terlebih dulu
            local step1Pkt = buildDialogReturn(
                dlgText,
                "lock_edit",
                tx, ty,
                nil,
                { checkbox_public = pubBit, checkbox_ignore = ignBit },
                nil
            )
            sendPacket(2, step1Pkt)
            safeSleep(450)

            -- Step 2: Wrench lagi, lalu trigger tombol Re-apply Lock (recalcLock) dengan checkbox tetap aktif
            local gotDlg2, dlgText2 = wrenchAndAwaitDialog(tx, ty, "lock_edit", standX, standY)
            local dlgForRecalc = gotDlg2 and dlgText2 or dlgText
            local meta2 = parseDialogFields(dlgForRecalc)
            local recalcBtn = "recalcLock"
            if not meta2.buttons[recalcBtn] then
                for bName, _ in pairs(meta2.buttons) do
                    if bName:lower():find("recalc", 1, true) then
                        recalcBtn = bName
                        break
                    end
                end
            end
            local step2Pkt = buildDialogReturn(
                dlgForRecalc,
                "lock_edit",
                tx, ty,
                nil,
                { checkbox_public = pubBit, checkbox_ignore = ignBit },
                recalcBtn
            )
            sendPacket(2, step2Pkt)
            safeSleep(550)

            -- Step 3: Verifikasi hasil checkbox tersimpan benar
            local gotVerify, verifyText = wrenchAndAwaitDialog(tx, ty, "lock_edit", standX, standY)
            local vMeta = gotVerify and parseDialogFields(verifyText) or nil
            if vMeta and vMeta.checkboxes.checkbox_ignore == ignBit and vMeta.checkboxes.checkbox_public == pubBit then
                validated = true
                break
            end
        else
            -- Fallback bila OnDialogRequest tidak tertangkap hook
            sendPacket(2, string.format(
                "action|dialog_return\ndialog_name|lock_edit\ntilex|%d|\ntiley|%d|\ncheckbox_public|%s\ncheckbox_ignore|%s\n",
                tx, ty, pubBit, ignBit
            ))
            safeSleep(450)
            sendPacket(2, string.format(
                "action|dialog_return\ndialog_name|lock_edit\ntilex|%d|\ntiley|%d|\nbuttonClicked|recalcLock\ncheckbox_public|%s\ncheckbox_ignore|%s\n",
                tx, ty, pubBit, ignBit
            ))
            safeSleep(600)
            if attempt >= 2 then
                validated = true
                break
            end
        end
    end

    STATE.suppress_dialog = false
    addLog(string.format("Validasi SL (%d, %d) -> IgnoreAir=%s, Public=%s + Apply Lock [%s]", tx, ty, tostring(ignoreAir), tostring(isPublic), validated and "OK" or "WARN"))
    return validated
end

-- ============================================================================
-- 7. INSPECT EXISTING WORLD SECURITY & STORAGE MANAGEMENT
-- ============================================================================

-- Inspect whether the current world ALREADY has WL, SL, Jammer, Door ID, and Blocker Doors installed
local function inspectWorldSecurityState(doorX, doorY)
    local info = {
        has_wl            = false,
        has_sl            = false,
        has_jammer        = false,
        has_id_door       = false,
        has_blocker       = false,
        has_left_blocker  = false,
        has_left_dirt     = false,
        all_ready         = false,
        wl_x              = nil,
        wl_y              = nil,
        sl_x              = nil,
        sl_y              = nil,
        jammer_x          = nil,
        jammer_y          = nil,
        blocker_x         = nil,
        blocker_y         = nil,
    }
    if not doorX or not doorY then return info end

    -- 1. Check World Lock:
    -- Standar Asli Dirt Farm: (doorX + 1, doorY) [kanan White Door]
    -- Fallback toleransi: (doorX - 2, doorY)
    for _, offset in ipairs({ { 1, 0 }, { -2, 0 } }) do
        local checkX = doorX + offset[1]
        local checkY = doorY + offset[2]
        if checkX >= 0 and checkX <= 99 and checkY >= 0 and checkY <= 59 then
            local ok, t = pcall(getTile, checkX, checkY)
            if ok and t and (t.fg == ITEM.WORLD_LOCK or OTHER_LOCKS[t.fg]) then
                info.has_wl = true
                info.wl_x = checkX
                info.wl_y = checkY
                break
            end
        end
    end
    -- Fallback: Scan jika ada lock di sekitar radius 3 dari White Door
    if not info.has_wl then
        for dy = -2, 2 do
            for dx = -3, 3 do
                local cx, cy = doorX + dx, doorY + dy
                if cx >= 0 and cx <= 99 and cy >= 0 and cy <= 59 then
                    local ok, t = pcall(getTile, cx, cy)
                    if ok and t and (t.fg == ITEM.WORLD_LOCK or (OTHER_LOCKS[t.fg] and t.fg ~= ITEM.SMALL_LOCK)) then
                        info.has_wl = true
                        info.wl_x = cx
                        info.wl_y = cy
                        break
                    end
                end
            end
            if info.has_wl then break end
        end
    end

    -- 2. Check Signal Jammer:
    -- Standar Asli Dirt Farm: (doorX - 1, doorY - 1) [kiri-atas White Door]
    for _, offset in ipairs({ { -1, -1 }, { -1, 0 } }) do
        local checkX = doorX + offset[1]
        local checkY = doorY + offset[2]
        if checkX >= 0 and checkX <= 99 and checkY >= 0 and checkY <= 59 then
            local ok, t = pcall(getTile, checkX, checkY)
            if ok and t and (t.fg == ITEM.JAMMER or t.fg == 226) then
                info.has_jammer = true
                info.jammer_x = checkX
                info.jammer_y = checkY
                break
            end
        end
    end

    -- 3. Check Small Lock:
    -- Standar Asli Dirt Farm: (doorX, doorY - 1) [tepat di atas White Door]
    for _, offset in ipairs({ { 0, -1 }, { -1, -1 } }) do
        local checkX = doorX + offset[1]
        local checkY = doorY + offset[2]
        if checkX >= 0 and checkX <= 99 and checkY >= 0 and checkY <= 59 then
            local ok, t = pcall(getTile, checkX, checkY)
            if ok and t and (t.fg == ITEM.SMALL_LOCK or OTHER_LOCKS[t.fg]) then
                info.has_sl = true
                info.sl_x = checkX
                info.sl_y = checkY
                break
            end
        end
    end

    -- 4. Check Penghalang (Blocker):
    -- Standar Asli Dirt Farm: (doorX - 1, doorY) [kiri White Door]
    for _, offset in ipairs({ { -1, 0 }, { 0, -1 } }) do
        local checkX = doorX + offset[1]
        local checkY = doorY + offset[2]
        if checkX >= 0 and checkX <= 99 and checkY >= 0 and checkY <= 59 then
            local ok, t = pcall(getTile, checkX, checkY)
            if ok and t and (t.fg == CFG.blocker_door_itemid or (KNOWN_BLOCKER_IDS and KNOWN_BLOCKER_IDS[t.fg]) or isDoorOrEntranceItem(t.fg)) then
                info.has_blocker = true
                info.has_left_blocker = true
                info.blocker_x = checkX
                info.blocker_y = checkY
                break
            end
        end
    end

    -- 5. Check Door ID di (0, 0):
    do
        local ok, t = pcall(getTile, 0, 0)
        if ok and t and (t.fg == CFG.id_door_itemid or (KNOWN_ID_DOOR_IDS and KNOWN_ID_DOOR_IDS[t.fg]) or isDoorOrEntranceItem(t.fg)) then
            info.has_id_door = true
        end
    end

    local wlOk  = (not CFG.use_wl) or info.has_wl
    local slOk  = (not CFG.use_sl) or info.has_sl
    local jamOk = (not CFG.use_jammer) or info.has_jammer
    local idOk  = (not CFG.use_id_door) or info.has_id_door
    local blkOk = (not CFG.use_blocker_door) or info.has_blocker or info.has_left_blocker

    info.all_ready = (wlOk and slOk and jamOk and idOk and blkOk)
    return info
end

local function countDroppedAtTile(tx, ty)
    local objs = getWorldObjectsSafe()
    if not objs then return 0 end
    local total = 0
    for _, obj in pairs(objs) do
        if obj and obj.pos then
            local ox = math.floor((obj.pos.x + 10) / 32)
            local oy = math.floor((obj.pos.y + 10) / 32)
            if ox == tx and oy == ty then
                total = total + (obj.amount or 1)
            end
        end
    end
    return total
end

local function getConfiguredSaveItemList()
    local list = {}
    local seen = {}
    local function addUnique(id)
        if id and id > 0 and not seen[id] then
            seen[id] = true
            table.insert(list, id)
        end
    end
    if CFG.save_dirt_seed then addUnique(ITEM.DIRT_SEED) end
    if CFG.save_cave_seed then addUnique(ITEM.CAVE_SEED) end
    if CFG.save_lava_seed then addUnique(ITEM.LAVA_SEED) end
    if CFG.save_rock_seed then addUnique(ITEM.ROCK_SEED) end
    if CFG.save_lava_block then addUnique(ITEM.LAVA) end
    if CFG.use_custom_save and CFG.custom_save_itemid and CFG.custom_save_itemid > 0 then
        addUnique(CFG.custom_save_itemid)
    end
    return list
end

getConfiguredTrashItemList = function()
    local list = {}
    local seen = {}
    for tok in tostring(CFG.trash_list_str or "4,14,10"):gmatch("%d+") do
        local id = tonumber(tok)
        if id and id > 0 and not seen[id] then
            seen[id] = true
            table.insert(list, math.floor(id))
        end
    end
    return list
end

setTrashListFromTable = function(list)
    local parts = {}
    for _, id in ipairs(list) do
        table.insert(parts, tostring(id))
    end
    CFG.trash_list_str = table.concat(parts, ",")
end

local function isDropTileOpen(tx, ty)
    if tx < 1 or tx > 98 or ty < 0 or ty > 53 then return false end
    local ok, t = pcall(getTile, tx, ty)
    if not ok or not t then return true end
    return (not t.collidable) and t.fg ~= ITEM.BEDROCK and t.fg ~= ITEM.MAIN_DOOR and (not OTHER_LOCKS[t.fg])
end

local function countStacksAtTile(tx, ty)
    local objs = getWorldObjectsSafe()
    if not objs then return 0 end
    local stacks = 0
    for _, obj in pairs(objs) do
        if obj and obj.pos then
            local ox = math.floor((obj.pos.x + 10) / 32)
            local oy = math.floor((obj.pos.y + 10) / 32)
            if ox == tx and oy == ty then
                stacks = stacks + 1
            end
        end
    end
    return stacks
end

local function dropItemsAtOpenSpots(itemsToSave, anchorX, anchorY, minOffset, maxOffset, forceAll, isLocalDF)
    ensureRuntimeHooks()
    local prevAntiTake = STATE.anti_take_active
    STATE.anti_take_active = true
    setAutoCollectActive(false)

    -- Scan spot drop dari TERJAUH ke TERDEKAT (mundur menuju anchor) agar karakter tidak menginjak hasil drop
    local candidateSpots = {}
    for offset = maxOffset, minOffset, -1 do
        local dx = math.min(98, anchorX + offset)
        table.insert(candidateSpots, { dropX = dx, standX = dx - 1, faceState = 32 })
    end
    for offset = maxOffset, minOffset, -1 do
        local dx = math.max(1, anchorX - offset)
        table.insert(candidateSpots, { dropX = dx, standX = dx + 1, faceState = 48 })
    end

    local droppedTiles = {}
    for _, itemID in ipairs(itemsToSave) do
        local beforeBP = getInvCount(itemID)
        local remaining = 0
        if isLocalDF then
            if beforeBP >= 200 then
                remaining = beforeBP
            end
        else
            remaining = beforeBP
            if itemID == ITEM.DIRT_SEED and not forceAll and beforeBP > 60 then
                remaining = beforeBP - 50
            end
        end

        if remaining > 0 then
            local failedTries = 0
            local totalDroppedItem = 0
            for _, spot in ipairs(candidateSpots) do
                if remaining <= 0 or failedTries >= 4 then break end
                local standKey = tostring(spot.standX) .. "," .. tostring(anchorY)
                if (not droppedTiles[standKey]) and isDropTileOpen(spot.dropX, anchorY) and isTileSafeToStand(spot.standX, anchorY)
                   and countDroppedAtTile(spot.dropX, anchorY) < 180 and countStacksAtTile(spot.dropX, anchorY) < 18 then
                    setAutoCollectActive(false)
                    if moveSafeTo(spot.standX, anchorY) then
                        safeSleep(220)
                        local okP, p = pcall(getLocal)
                        local px = (okP and p and (p.posX or (p.pos and p.pos.x))) or (spot.standX * 32)
                        local py = (okP and p and (p.posY or (p.pos and p.pos.y))) or (anchorY * 32)
                        sendPacketRaw(false, {
                            type  = 0,
                            state = spot.faceState,
                            x     = px,
                            y     = py
                        })
                        safeSleep(160)

                        local okDrop, droppedNow, afterBP = dropItemSafe(itemID, remaining)
                        if okDrop and droppedNow > 0 then
                            remaining = remaining - droppedNow
                            totalDroppedItem = totalDroppedItem + droppedNow
                            local dropKey = tostring(spot.dropX) .. "," .. tostring(anchorY)
                            droppedTiles[dropKey] = true
                            if isLocalDF then
                                STATE.df_dropped_spots[dropKey] = true
                            end
                            addLog(string.format("%s OK: Drop %d %s (Sisa BP: %d) di (%d, %d)", isLocalDF and "Drop DF (BP 200)" or "Validasi BP", droppedNow, resolveItemName(itemID), afterBP, spot.dropX, anchorY))
                        else
                            failedTries = failedTries + 1
                            addLog(string.format("Drop %s di (%d, %d) belum mengurangi BP (Stok BP: %d), pindah spot...", resolveItemName(itemID), spot.dropX, anchorY, afterBP))
                        end
                    end
                end
            end

            if totalDroppedItem == 0 then
                local warnMsg = string.format("Gagal save %s! Stok BP masih %d (cek akses lock/spot kosong).", resolveItemName(itemID), getInvCount(itemID))
                addLog(warnMsg)
                if sendNotification then pcall(sendNotification, warnMsg) end
            end
        end
    end

    if isTileSafeToStand(anchorX, anchorY) then
        moveSafeTo(anchorX, anchorY)
        safeSleep(150)
    end
    STATE.anti_take_active = prevAntiTake
end

local function hasAnyDroppedBackupInDF()
    if next(STATE.df_dropped_spots) == nil then return false end
    local objs = getWorldObjectsSafe()
    if not objs then return false end
    for _, obj in pairs(objs) do
        if obj and obj.pos then
            local ox = math.floor((obj.pos.x + 10) / 32)
            local oy = math.floor((obj.pos.y + 10) / 32)
            if STATE.df_dropped_spots[tostring(ox) .. "," .. tostring(oy)] then
                return true
            end
        end
    end
    return false
end

local function collectBackupDropsFromDF(filterItemID)
    if next(STATE.df_dropped_spots) == nil then return 0 end
    local objs = getWorldObjectsSafe()
    if not objs then return 0 end

    local spotsList = {}
    for spotKey, _ in pairs(STATE.df_dropped_spots) do
        local sx, sy = spotKey:match("^([^,]+),([^,]+)$")
        if sx and sy then
            table.insert(spotsList, { x = tonumber(sx), y = tonumber(sy), key = spotKey })
        end
    end

    local collectedAny = 0
    for _, spot in ipairs(spotsList) do
        local matchedHere = false
        local stillHasOther = false
        for _, obj in pairs(objs) do
            if obj and obj.pos and obj.id then
                local ox = math.floor((obj.pos.x + 10) / 32)
                local oy = math.floor((obj.pos.y + 10) / 32)
                if ox == spot.x and oy == spot.y then
                    if (not filterItemID or obj.itemid == filterItemID) and getInvCount(obj.itemid) < 200 then
                        matchedHere = true
                    else
                        stillHasOther = true
                    end
                end
            end
        end
        if matchedHere then
            -- Buka sementara spotKey agar collectNearbyFloating mau mengambil cadangan dari DF
            STATE.df_dropped_spots[spot.key] = nil
            moveSafeTo(spot.x, spot.y)
            safeSleep(120)
            local objsNow = getWorldObjectsSafe() or {}
            local okP, p = pcall(getLocal)
            local charX = (okP and p and p.posX) or (spot.x * 32)
            local charY = (okP and p and p.posY) or (spot.y * 32)
            for _, obj in pairs(objsNow) do
                if obj and obj.pos and obj.id then
                    local ox = math.floor((obj.pos.x + 10) / 32)
                    local oy = math.floor((obj.pos.y + 10) / 32)
                    if ox == spot.x and oy == spot.y and (not filterItemID or obj.itemid == filterItemID) and getInvCount(obj.itemid) < 200 then
                        pcall(sendPacketRaw, false, {
                            type  = 11,
                            value = obj.id,
                            x     = charX,
                            y     = charY,
                        })
                        collectedAny = collectedAny + 1
                        safeSleep(45)
                    end
                end
            end
            if stillHasOther then
                STATE.df_dropped_spots[spot.key] = true
            end
        end
    end
    return collectedAny
end

local function saveSeedsToStorage(returnWorld, returnDoor, forceAll)
    local itemsToSave = getConfiguredSaveItemList()

    local storSeedList = {}
    if type(CFG.storage_seed_list) == "table" and #CFG.storage_seed_list > 0 then
        for _, s in ipairs(CFG.storage_seed_list) do
            if s and s.name and s.name ~= "" then
                table.insert(storSeedList, s)
            end
        end
    end
    if #storSeedList == 0 and CFG.storage_seed_world ~= "" then
        table.insert(storSeedList, { name = CFG.storage_seed_world, door = CFG.storage_seed_door or "" })
    end
    local hasStorageWorld = (#storSeedList > 0)

    -- Poin 1:
    -- - Saat DF masih diproses (forceAll = false):
    --   * Cave Seed, Lava Seed, Rock Seed, Lava Block, dll langsung di-save ke Storage Seed sejak awal saat >= threshold.
    --   * Khusus Dirt Seed & Dirt Block TIDAK dibawa ke Storage dulu — bila BP penuh (>= 200), di-drop di world DF dulu agar nanti diambil buat plant/place sampai DF selesai!
    -- - Setelah semua DF selesai (forceAll = true): seluruh sisa seed termasuk Dirt Seed ikut di-save ke Storage Seed.
    local storageBatch = {}
    local dfBackupBatch = {}
    local dirtInBackup = false

    for _, id in ipairs(itemsToSave) do
        local cnt = getInvCount(id)
        if id == ITEM.DIRT_SEED and (not forceAll) then
            if cnt >= 200 then
                table.insert(dfBackupBatch, id)
            end
        else
            if hasStorageWorld then
                if (forceAll and cnt > 0) or (cnt >= CFG.save_seed_threshold) then
                    table.insert(storageBatch, id)
                end
            elseif cnt >= 200 then
                table.insert(dfBackupBatch, id)
                if id == ITEM.DIRT then dirtInBackup = true end
            end
        end
    end

    if (not forceAll) and (not dirtInBackup) and getInvCount(ITEM.DIRT) >= 200 then
        table.insert(dfBackupBatch, ITEM.DIRT)
    end

    if #storageBatch == 0 and #dfBackupBatch == 0 then
        return true
    end

    STATE.saving_storage = true
    setAutoCollectActive(false)

    -- 1. Drop cadangan Dirt Seed (atau item saat Storage kosong) di world DF dulu
    if #dfBackupBatch > 0 then
        local statusTxt = hasStorageWorld
            and "Dirt Seed penuh (200) -> Drop di DF dulu sampai selesai DF"
            or "Storage Seed kosong -> Drop item 200 di DF (Collect OFF)"
        setStatus("Drop Cadangan DF", statusTxt)
        local doorX, doorY = findMainDoor()
        if not doorX or not doorY then
            doorX, doorY = getPlayerTilePos()
        end
        if not doorX then doorX, doorY = 50, 23 end
        dropItemsAtOpenSpots(dfBackupBatch, doorX, doorY, 3, 12, false, true)
    end

    -- 2. Simpan item non-DirtSeed (atau semua item saat forceAll=true) ke World Storage Seed (multi-world support)
    if #storageBatch > 0 and hasStorageWorld then
        local function restoreAndReturn()
            if returnWorld and returnWorld ~= "" and getWorldNameSafe() ~= returnWorld then
                setStatus("Kembali ke DF", "Menuju " .. returnWorld)
                warpTo(returnWorld, returnDoor or "")
                safeSleep(1000)
            end
            STATE.saving_storage = false
            setAutoCollectActive(CFG.auto_collect)
        end

        local allDropped = false
        for sIdx, stor in ipairs(storSeedList) do
            local sWorld = stor.name:upper()
            local sDoor = stor.door or ""
            setStatus("Save Seed/Block", string.format("Storage Seed %d/%d: %s", sIdx, #storSeedList, sWorld))

            if getWorldNameSafe() ~= sWorld then
                if not warpTo(sWorld, sDoor) then
                    addLog("Gagal warp ke Storage Seed: " .. sWorld)
                else
                    safeSleep(1000)
                end
            end

            if getWorldNameSafe() == sWorld then
                setAutoCollectActive(false)
                local startX, startY = getPlayerTilePos()
                if not startX then startX, startY = 10, 23 end
                dropItemsAtOpenSpots(storageBatch, startX, startY, 1, 8, forceAll, false)

                -- Cek sisa item yang belum ter-drop
                local remainingBatch = {}
                for _, id in ipairs(storageBatch) do
                    local cnt = getInvCount(id)
                    if (forceAll and cnt > 0) or (cnt >= CFG.save_seed_threshold) then
                        table.insert(remainingBatch, id)
                    end
                end

                if #remainingBatch == 0 then
                    allDropped = true
                    break
                else
                    storageBatch = remainingBatch
                    addLog(string.format("Storage Seed %s mungkin penuh, lanjut ke gudang berikutnya jika ada.", sWorld))
                end
            end
        end

        restoreAndReturn()
        return allDropped
    end

    STATE.saving_storage = false
    setAutoCollectActive(CFG.auto_collect)
    return true
end

-- Uji Coba Drop manual langsung dari Menu 3. Storage (Auto Collect OFF + Anti Collect ON + Validasi BP)
local function testDropCustomSaveItem()
    local targetID = (CFG.custom_save_itemid and CFG.custom_save_itemid > 0) and CFG.custom_save_itemid or ITEM.DIRT_SEED
    local itemName = resolveItemName(targetID)
    local beforeBP = getInvCount(targetID)
    if beforeBP <= 0 then
        local msg = string.format("Stok %s (ID %d) di Backpack kosong (0)!", itemName, targetID)
        addLog("Coba Drop -> " .. msg)
        if sendNotification then pcall(sendNotification, msg) end
        return false
    end

    local function execDrop()
        STATE.saving_storage = true
        local prevAntiTake = STATE.anti_take_active
        STATE.anti_take_active = true
        setAutoCollectActive(false)
        safeSleep(150)

        local okDrop, dropped, afterBP = dropItemSafe(targetID, beforeBP)
        safeSleep(300)

        -- Jangan nyalakan Auto Collect langsung di tempat drop supaya hasil tes drop tidak tersedot balik
        STATE.saving_storage = false
        STATE.anti_take_active = prevAntiTake

        if okDrop and dropped > 0 then
            local msg = string.format("Berhasil Drop %dx %s! (BP: %d -> %d) [Collect OFF]", dropped, itemName, beforeBP, afterBP)
            addLog("Coba Drop OK -> " .. msg)
            if sendNotification then pcall(sendNotification, msg) end
        else
            setAutoCollectActive(CFG.auto_collect)
            local msg = string.format("Gagal Drop %s! (Stok BP tetap %d)", itemName, afterBP)
            addLog("Coba Drop GAGAL -> " .. msg)
            if sendNotification then pcall(sendNotification, msg) end
        end
    end

    if runCoroutine then
        pcall(runCoroutine, execDrop)
    else
        execDrop()
    end
    return true
end

local function checkTrashAndSeeds(currentWorld, currentDoor)
    if CFG.auto_trash_junk then
        local junkItems = getConfiguredTrashItemList()
        local thresh = math.max(10, tonumber(CFG.trash_threshold) or 150)
        for _, jid in ipairs(junkItems) do
            local cnt = getInvCount(jid)
            if cnt >= thresh then
                addLog(string.format("Auto-Trash %s (%d >= %d)", resolveItemName(jid), cnt, thresh))
                trashItem(jid, cnt)
            end
        end
    end
    saveSeedsToStorage(currentWorld, currentDoor, false)
end

-- Helper: Bangun pesan Request alat/door yang kurang secara spesifik & kirim notifikasi
local function notifyToolRequest(title, message)
    setStatus(title, message)
    if sendNotification then
        pcall(sendNotification, message)
    end
    if growtopia and growtopia.notify then
        pcall(growtopia.notify, message)
    end
    if sendDialog then
        pcall(sendDialog, { title = title, alias = "boren_df_req", message = message, confirm = "OK" })
    end
end

-- Only require tools that are NOT yet placed in the current world
local function ensureToolsFromStorage(existingSec, returnWorld, returnDoor)
    if CFG.ignore_lock then return true end
    -- Auto-fallback Door ID & Blocker jika belum diset atau jika tas memiliki Wooden Door (12) / alternatif valid
    if CFG.use_id_door and not (existingSec and existingSec.has_id_door) then
        local did = tonumber(CFG.id_door_itemid) or 0
        if did <= 0 or getInvCount(did) <= 0 then
            for _, altID in ipairs({ ITEM.DOOR, 30, 544, 224, 2810 }) do
                if altID ~= did and getInvCount(altID) > 0 then
                    addLog(string.format("`2[Auto-Pilih Door ID] `wMenemukan %s (#%d) di tas, dijadikan Door ID!", resolveItemName(altID), altID))
                    CFG.id_door_itemid = altID
                    did = altID
                    persistConfig()
                    break
                end
            end
        end
        if did <= 0 then CFG.id_door_itemid = ITEM.WOODEN_DOOR end
        if tostring(CFG.door_id or ""):gsub("%s+", "") == "" then
            CFG.door_id = "DF123"
        end
    end

    if CFG.use_blocker_door and not (existingSec and existingSec.has_left_blocker) then
        local bid = tonumber(CFG.blocker_door_itemid) or 0
        if bid <= 0 or getInvCount(bid) <= 0 then
            for _, altID in ipairs({ ITEM.AIR_VENT, ITEM.DOOR, 30, 60, 224, 858, 544 }) do
                if altID ~= bid and getInvCount(altID) > 0 then
                    addLog(string.format("`2[Auto-Pilih Blocker] `wMenemukan %s (#%d) di tas, dijadikan Penghalang!", resolveItemName(altID), altID))
                    CFG.blocker_door_itemid = altID
                    bid = altID
                    persistConfig()
                    break
                end
            end
        end
        if bid <= 0 then CFG.blocker_door_itemid = ITEM.WOODEN_DOOR end
    end

    local needed = {}
    local neededOrder = {}
    local neededRoles = {}
    local function addNeed(id, count, roleLabel)
        id = tonumber(id) or 0
        if id <= 0 then return end
        if not needed[id] then
            table.insert(neededOrder, id)
            neededRoles[id] = roleLabel
        else
            neededRoles[id] = neededRoles[id] .. " & " .. roleLabel
        end
        needed[id] = (needed[id] or 0) + count
    end

    if CFG.use_wl and not (existingSec and existingSec.has_wl) then
        addNeed(ITEM.WORLD_LOCK, 1, "WL")
    end
    if CFG.use_sl and not (existingSec and existingSec.has_sl) then
        addNeed(ITEM.SMALL_LOCK, 1, "SL")
    end
    if CFG.use_jammer and not (existingSec and existingSec.has_jammer) then
        addNeed(ITEM.JAMMER, 1, "Jammer")
    end
    if CFG.use_id_door and not (existingSec and existingSec.has_id_door) then
        addNeed(CFG.id_door_itemid, 1, "Door ID")
    end
    if CFG.use_blocker_door and not (existingSec and existingSec.has_left_blocker) then
        addNeed(CFG.blocker_door_itemid, 1, "Penghalang Kiri")
    end

    local function collectMissingText()
        local missingParts = {}
        local needDoorPickHint = false
        for _, needID in ipairs(neededOrder) do
            local reqAmt = needed[needID]
            local curAmt = getInvCount(needID)
            if curAmt < reqAmt then
                local diff = reqAmt - curAmt
                local role = neededRoles[needID] or ""
                table.insert(missingParts, string.format("%s (%s) x%d", role, resolveItemName(needID), diff))
                if role:find("Door") then
                    needDoorPickHint = true
                end
            end
        end
        return missingParts, needDoorPickHint
    end

    local missingBefore, doorHintBefore = collectMissingText()
    if #missingBefore == 0 then
        return true
    end

    local missingStr = table.concat(missingBefore, ", ")
    addLog("Request Alat dibutuhkan: " .. missingStr)
    logInventoryDiagnostic(neededOrder, "Lock")

    local storList = {}
    if type(CFG.storage_tool_list) == "table" and #CFG.storage_tool_list > 0 then
        for _, s in ipairs(CFG.storage_tool_list) do
            if s and s.name and s.name ~= "" then
                table.insert(storList, s)
            end
        end
    end
    if #storList == 0 and CFG.storage_pack_world ~= "" then
        table.insert(storList, { name = CFG.storage_pack_world, door = CFG.storage_pack_door or "" })
    end

    if #storList == 0 then
        local hint = doorHintBefore and " Atau silakan pilih Door ID / Door Penghalang lain di menu Lock & Door." or ""
        notifyToolRequest(
            "Request Alat Kurang",
            "Request: Kurang " .. missingStr .. "! Siapkan di tas atau isi World Storage Alat." .. hint
        )
        return false
    end

    -- Matikan Auto Collect & nyalakan Anti Collect SEBELUM warp ke Storage Alat agar warpTo() tidak menyalakan Auto Collect di dalam Storage!
    STATE.saving_storage = true
    setAutoCollectActive(false)

    local function dropAllToolExcessInStorage()
        local hasExcess = false
        for _, needID in ipairs(neededOrder) do
            if getInvCount(needID) > needed[needID] then
                hasExcess = true
                break
            end
        end
        if not hasExcess then return end

        local doorX, doorY = findMainDoor()
        local curPx, curPy = getPlayerTilePos()
        local anchorX = doorX or curPx or 50
        local anchorY = doorY or curPy or 23

        local prevAntiTake = STATE.anti_take_active
        STATE.anti_take_active = true
        setAutoCollectActive(false)

        local candidateSpots = {}
        for offset = 12, 1, -1 do
            local dxR = math.min(98, anchorX + offset)
            local sxR = dxR - 1
            if sxR >= 1 then
                table.insert(candidateSpots, { dropX = dxR, standX = sxR, faceState = 32 })
            end
        end
        for offset = 12, 1, -1 do
            local dxL = math.max(1, anchorX - offset)
            local sxL = dxL + 1
            if sxL <= 98 then
                table.insert(candidateSpots, { dropX = dxL, standX = sxL, faceState = 48 })
            end
        end

        local usedDropTiles = {}
        for _, needID in ipairs(neededOrder) do
            local reqAmt = needed[needID]
            local curAmt = getInvCount(needID)
            if curAmt > reqAmt then
                for _, spot in ipairs(candidateSpots) do
                    local nowAmt = getInvCount(needID)
                    local excess = nowAmt - reqAmt
                    if excess <= 0 then break end
                    local dKey = tostring(spot.dropX) .. "," .. tostring(anchorY)
                    if (not usedDropTiles[dKey]) and isDropTileOpen(spot.dropX, anchorY) and isTileSafeToStand(spot.standX, anchorY)
                       and countStacksAtTile(spot.dropX, anchorY) < 18 then
                        setAutoCollectActive(false)
                        moveSafeTo(spot.standX, anchorY)
                        safeSleep(220)
                        local apx, apy = getPlayerTilePos()
                        if apx ~= spot.standX or apy ~= anchorY then
                            if FindPath then pcall(FindPath, spot.standX, anchorY) end
                            safeSleep(200)
                            apx, apy = getPlayerTilePos()
                        end
                        if apx == spot.standX and apy == anchorY then
                            local okP, p = pcall(getLocal)
                            local cpx = (okP and p and (p.posX or (p.pos and p.pos.x))) or (spot.standX * 32)
                            local cpy = (okP and p and (p.posY or (p.pos and p.pos.y))) or (anchorY * 32)
                            sendPacketRaw(false, { type = 0, state = spot.faceState, x = cpx, y = cpy })
                            safeSleep(160)
                            local okDrop, droppedNow, afterBP = dropItemSafe(needID, excess)
                            if okDrop and droppedNow > 0 then
                                usedDropTiles[dKey] = true
                                addLog(string.format("Drop sisa %s x%d di (%d,%d) [berdiri %d] -> BP pas: %d/%d", resolveItemName(needID), droppedNow, spot.dropX, anchorY, spot.standX, afterBP, reqAmt))
                            end
                            safeSleep(180)
                        end
                    end
                end

                -- Fallback darurat bila semua spot samping terhalang
                local remExcess = getInvCount(needID) - reqAmt
                if remExcess > 0 then
                    setAutoCollectActive(false)
                    dropItemSafe(needID, remExcess)
                    safeSleep(180)
                end
            end
        end
        STATE.anti_take_active = prevAntiTake
    end

    local toolSatisfied = false
    local lastMissingAfter = {}
    local lastDoorHintAfter = nil

    for sIdx, stor in ipairs(storList) do
        local sWorld = stor.name:upper()
        local sDoor = stor.door or ""
        setStatus("Ambil Alat", string.format("Gudang Alat %d/%d: %s (%s)", sIdx, #storList, sWorld, missingStr))
        if not warpTo(sWorld, sDoor) then
            addLog("Gagal warp ke Storage Alat: " .. sWorld)
        else
            setAutoCollectActive(false)
            safeSleep(1100)

            -- Tunggu hingga world objects tersinkronisasi dari server (maks 2.5 detik)
            local waited = 0
            while waited < 2500 do
                safeSleep(300)
                waited = waited + 300
                if forEachWorldObject(function() end) > 0 then break end
            end
            safeSleep(200)

            -- Tahap 1: Ambil seluruh alat yang kurang via findWorldObjectsByItemID (mendukung table & userdata)
            for _, needID in ipairs(neededOrder) do
                local reqAmt = needed[needID]
                if getInvCount(needID) < reqAmt then
                    local foundObjs = findWorldObjectsByItemID(needID)
                    -- Jika Door/Blocker spesifik tidak ada di lantai storage, cari pintu alternatif di lantai storage!
                    if #foundObjs == 0 and (needID == CFG.blocker_door_itemid or needID == CFG.id_door_itemid) then
                        for _, altID in ipairs({ ITEM.AIR_VENT, ITEM.DOOR, 30, 60, 224, 858, 544 }) do
                            local altObjs = findWorldObjectsByItemID(altID)
                            if #altObjs > 0 then
                                foundObjs = altObjs
                                if needID == CFG.blocker_door_itemid then CFG.blocker_door_itemid = altID end
                                if needID == CFG.id_door_itemid then CFG.id_door_itemid = altID end
                                persistConfig()
                                break
                            end
                        end
                    end

                    for _, obj in ipairs(foundObjs) do
                        addLog(string.format("Mengambil %s di (%d, %d) [UID: %d, Butuh %dx]", resolveItemName(obj.itemid), obj.tileX, obj.tileY, obj.id, reqAmt))
                        moveSafeTo(obj.tileX, obj.tileY)
                        safeSleep(250)
                        -- Matikan Anti Collect sebelum kirim packet 11 agar objek berhasil masuk ke tas!
                        if editToggle then
                            pcall(editToggle, "Anti Collect", false)
                            pcall(editToggle, "Anti-Collect", false)
                        end
                        STATE.anti_take_active = false
                        pcall(sendPacketRaw, false, {
                            type  = 11,
                            value = obj.id,
                            x     = obj.x,
                            y     = obj.y,
                        })
                        safeSleep(350)
                        if getInvCount(needID) >= reqAmt then
                            break
                        end
                    end
                end
            end

            -- Tahap 2: Drop SEMUA kelebihan alat sekaligus di spot terbuka
            dropAllToolExcessInStorage()

            local missingAfter, doorHintAfter = collectMissingText()
            lastMissingAfter = missingAfter
            lastDoorHintAfter = doorHintAfter
            if #missingAfter == 0 then
                toolSatisfied = true
                break
            else
                missingStr = table.concat(missingAfter, ", ")
                addLog(string.format("Alat masih kurang di gudang %s: %s -> Cek gudang alat berikutnya jika ada.", sWorld, missingStr))
            end
        end
    end

    if not toolSatisfied then
        local afterStr = table.concat(lastMissingAfter, ", ")
        local hint = lastDoorHintAfter and " Silakan pilih item Door ID / Penghalang yang ada di tas." or ""
        STATE.saving_storage = false
        setAutoCollectActive(CFG.auto_collect)
        notifyToolRequest(
            "Request Stok Alat",
            "Request: Kurang " .. afterStr .. " di Storage Alat!" .. hint
        )
        return false
    end

    if returnWorld and returnWorld ~= "" then
        warpTo(returnWorld, returnDoor or "")
        safeSleep(1000)
    end
    -- Pulihkan Auto Collect HANYA SETELAH keluar dari Storage Alat agar sisa alat tidak terhisap kembali
    STATE.saving_storage = false
    setAutoCollectActive(CFG.auto_collect)
    return true
end

-- ============================================================================
-- 8. WORLD SELECTION (MANUAL LIST, AUTO-ADD INPUT, OR RANDOM WORLD FINDER)
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

local function isCurrentWorldUsableForRandom()
    local ok, tiles = pcall(getTiles)
    if not ok or not tiles then return false, "Tile belum termuat" end

    for _, t in pairs(tiles) do
        if t and OTHER_LOCKS[t.fg] then
            return false, "Sudah ada Lock (" .. resolveItemName(t.fg) .. ")"
        end
    end

    local okPl, players = pcall(getPlayerList)
    local okLoc, myLocal = pcall(getLocal)
    if okPl and players and okLoc and myLocal then
        for _, p in pairs(players) do
            if p and p.netID ~= myLocal.netID then
                return false, "Ada player lain (" .. tostring(p.name) .. ")"
            end
        end
    end

    local dx, dy = findMainDoor()
    if not dx or not dy then
        return false, "Main Door tidak ditemukan"
    end

    return true, "World kosong & siap dibuat DF"
end

local function readGLString(alias, fallback)
    if getValue then
        for _, vtype in ipairs({ 2, 5 }) do
            local ok, val = pcall(getValue, vtype, alias)
            if ok and type(val) == "string" and val ~= "" then
                return val
            end
        end
    end
    return fallback
end

local function readGLBool(alias, fallback)
    if getValue then
        local ok, val = pcall(getValue, 0, alias)
        if ok and type(val) == "boolean" then
            return val
        end
    end
    return fallback
end

local function cleanItemName(name)
    if type(name) ~= "string" then return "" end
    -- Hapus kode warna Growtopia seperti `w, `o, `0-9, `b, `p, dsb.
    return name:gsub("`.", ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function lookupItemIDByName(name)
    local clean = cleanItemName(name)
    if clean == "" then return nil end

    -- 1. Ekstrak nomor langsung jika string mengandung format ID misal: "Air Vent (2810)" atau "Door #12"
    local embeddedId = clean:match("%((%d+)%)") or clean:match("#(%d+)")
    if embeddedId and tonumber(embeddedId) and tonumber(embeddedId) > 0 then
        return tonumber(embeddedId)
    end

    -- 2. Cek cache nama lokal & presets pintu DF
    local cleanLow = clean:lower()
    for id, n in pairs(ITEM_NAME_CACHE) do
        if n and cleanItemName(n):lower() == cleanLow then
            return id
        end
    end
    for _, def in ipairs(BLOCKER_DOOR_PRESETS) do
        if def.name and cleanItemName(def.name):lower():find(cleanLow, 1, true) then
            return def.id
        end
    end
    for _, def in ipairs(ID_DOOR_PRESETS) do
        if def.name and cleanItemName(def.name):lower():find(cleanLow, 1, true) then
            return def.id
        end
    end

    -- 3. API C++ Resmi GrowLauncher: getItemInfoByName
    if getItemInfoByName then
        local ok, info = pcall(getItemInfoByName, clean)
        if ok and info and tonumber(info.id) and tonumber(info.id) > 0 then
            return tonumber(info.id)
        end
    end

    -- 4. API C++ Resmi GrowLauncher: itemInfoManager.getItemInfoByName
    if itemInfoManager and itemInfoManager.getItemInfoByName then
        local ok, info = pcall(itemInfoManager.getItemInfoByName, clean)
        if ok and info and tonumber(info.id) and tonumber(info.id) > 0 then
            return tonumber(info.id)
        end
    end

    -- 5. Fallback findItemID
    if findItemID then
        local ok, id = pcall(findItemID, clean)
        if ok and tonumber(id) and tonumber(id) > 0 then
            return tonumber(id)
        end
    end

    -- 6. Fallback growtopia.getItemID
    if growtopia and growtopia.getItemID then
        local ok, id = pcall(growtopia.getItemID, clean)
        if ok and tonumber(id) and tonumber(id) > 0 then
            return tonumber(id)
        end
    end

    return nil
end

local function resolvePickedItemID(value)
    if not value or value == "" then return nil end
    local vType = type(value)
    if vType == "table" or vType == "userdata" then
        local ok, v = pcall(function()
            return value.id or value.itemID or value.itemid or value.item_id or value.value or value.item or value.name
        end)
        if ok and v ~= nil then value = v end
    end
    local num = tonumber(value)
    if num and num > 0 then
        return math.floor(num)
    end
    if type(value) == "string" and value ~= "" then
        local clean = cleanItemName(value)
        local sNum = tonumber(clean)
        if sNum and sNum > 0 then
            return math.floor(sNum)
        end
        local leadNum = clean:match("^(%d+)")
        if leadNum and tonumber(leadNum) and tonumber(leadNum) > 0 then
            return math.floor(tonumber(leadNum))
        end
        local embedNum = clean:match("%((%d+)%)") or clean:match("#(%d+)") or clean:match("(%d+)")
        if embedNum and tonumber(embedNum) and tonumber(embedNum) > 0 then
            return math.floor(tonumber(embedNum))
        end
        local lookedUp = lookupItemIDByName(clean)
        if lookedUp and lookedUp > 0 then
            return lookedUp
        end
    end
    return nil
end

local function readGLItemOrInt(alias, fallback)
    if getValue then
        for _, t in ipairs({ 1, 5, 2 }) do
            local ok, val = pcall(getValue, t, alias)
            if ok and val ~= nil and tostring(val) ~= "" and tostring(val) ~= "0" then
                local res = resolvePickedItemID(val)
                if res and res > 0 then return res end
            end
        end
        local ok0, val0 = pcall(getValue, alias)
        if ok0 and val0 ~= nil and tostring(val0) ~= "" and tostring(val0) ~= "0" then
            local res = resolvePickedItemID(val0)
            if res and res > 0 then return res end
        end
    end
    return fallback
end

local function syncInputsFromGL()
    local wIn = readGLString("df_manual_world_input", "")
    if wIn ~= "" then
        STATE.buf_world_name = wIn:upper()
        CFG.manual_world_text = STATE.buf_world_name
    end
    local dIn = readGLString("df_manual_door_input", "")
    if dIn ~= "" then
        STATE.buf_world_door = dIn
        CFG.manual_door_text = dIn
    end
    local packW = readGLString("df_pack_w", "")
    if packW ~= "" then CFG.storage_pack_world = packW:upper() end
    local packD = readGLString("df_pack_d", "")
    if packD ~= "" then CFG.storage_pack_door = packD end
    local seedW = readGLString("df_seed_w", "")
    if seedW ~= "" then CFG.storage_seed_world = seedW:upper() end
    local seedD = readGLString("df_seed_d", "")
    if seedD ~= "" then CFG.storage_seed_door = seedD end
    local dId = readGLString("df_door_id", "")
    if dId ~= "" then CFG.door_id = dId end
    local dLbl = readGLString("df_door_label", "")
    if dLbl ~= "" then CFG.door_label = dLbl end

    -- Sinkronisasi Item Door ID & Penghalang
    local dItemId = readGLItemOrInt("df_input_id_door", nil) or readGLItemOrInt("df_pick_id_door", nil)
    if dItemId and dItemId > 0 then CFG.id_door_itemid = dItemId end

    local bItemId = readGLItemOrInt("df_input_blocker", nil) or readGLItemOrInt("df_pick_blocker", nil)
    if bItemId and bItemId > 0 then CFG.blocker_door_itemid = bItemId end
    CFG.world_mode = readGLBool("df_world_random", CFG.world_mode == "random") and "random" or "manual"
    local rTgt = tonumber(readGLString("df_random_target", ""))
    if rTgt and rTgt >= 1 then CFG.random_target_count = math.floor(rTgt) end
    local wFile = readGLString("df_world_file", "")
    if wFile ~= "" then CFG.world_file_name = wFile end
end

local function acquireTargetWorld()
    syncInputsFromGL()

    -- Setelah Auto Reconnect dari disconnect, langsung masuk ulang world terakhir agar proses DF dijalankan ulang dari awal
    if STATE.resume_world_override and STATE.resume_world_override ~= "" then
        local rw = STATE.resume_world_override
        local rd = STATE.resume_door_override or ""
        STATE.resume_world_override = nil
        STATE.resume_door_override = nil
        STATE.active_world = rw
        STATE.active_door = rd
        local mIdx = nil
        for idx, entry in ipairs(CFG.world_list) do
            if entry.name == rw and (not entry.done) then
                mIdx = idx
                break
            end
        end
        if getWorldNameSafe() ~= rw then
            warpTo(rw, rd)
            safeSleep(800)
        end
        return rw, rd, mIdx
    end

    if CFG.world_mode == "manual" then
        local hasPending = false
        for _, entry in ipairs(CFG.world_list) do
            if not entry.done then
                hasPending = true
                break
            end
        end

        -- Jika list world masih kosong total, otomatis ambil dari input manual atau world saat ini
        if #CFG.world_list == 0 and STATE.buf_world_name ~= "" then
            addManualWorldsFromString(STATE.buf_world_name, STATE.buf_world_door, false)
            hasPending = (#CFG.world_list > 0)
        end
        if not hasPending and #CFG.world_list == 0 then
            local curW = getWorldNameSafe()
            if curW ~= "" and curW ~= "EXIT" and curW ~= "START" then
                addLog("List world kosong, otomatis memakai world saat ini: " .. curW)
                addManualWorldsFromString(curW, STATE.buf_world_door, false)
            end
        end

        for idx, entry in ipairs(CFG.world_list) do
            if not entry.done then
                STATE.active_world = entry.name
                STATE.active_door = entry.door or ""
                setStatus("Masuk World", "Menuju " .. entry.name)
                if not warpTo(entry.name, entry.door) then
                    if not ensureOnlineInWorld(entry.name, entry.door) then
                        return nil, nil, nil
                    end
                end
                safeSleep(1000)
                return entry.name, entry.door, idx
            end
        end

        STATE.active_world = ""
        STATE.active_door = ""
        local msg = (#CFG.world_list == 0)
            and "List world kosong! Isi Nama World atau nyalakan Mode Random."
            or "Semua world di list sudah selesai! Tambah world baru atau Reset."
        setStatus("Info World", msg)
        if sendNotification then pcall(sendNotification, msg) end
        return nil, nil, nil
    else
        -- VALIDASI UTAMA: Jika ada world di list yang belum DONE atau masih ANTRI,
        -- bot HARUS menyelesaikan world tersebut terlebih dahulu sebelum diizinkan mencari world secara random!
        for idx, entry in ipairs(CFG.world_list) do
            if not entry.done and entry.status ~= "DONE" then
                entry.status = "PROSES"
                STATE.active_world = entry.name
                STATE.active_door = entry.door or ""
                if updateWorldDisplayList then pcall(updateWorldDisplayList) end
                local isRand = false
                pcall(function() isRand = (entry.from_random == true) end)
                local srcTag = isRand and "Random Sebelumnya" or "Antrean List"
                setStatus("Lanjut Antrean World", string.format("%s (%s - Selesaikan antrean)", entry.name, srcTag))
                addLog(string.format("[Validasi Antrean] Menyelesaikan %s dari list terlebih dahulu sebelum mencari random baru", entry.name))
                if not warpTo(entry.name, entry.door) then
                    if not ensureOnlineInWorld(entry.name, entry.door) then
                        return nil, nil, nil
                    end
                end
                safeSleep(1000)
                return entry.name, entry.door, idx
            end
        end

        local targetCount = math.max(1, math.floor(tonumber(CFG.random_target_count) or 5))
        if (STATE.random_done_count or 0) >= targetCount then
            local doneMsg = string.format("Target Find Random selesai (%d/%d world DONE)!", STATE.random_done_count, targetCount)
            STATE.active_world = ""
            STATE.active_door = ""
            setStatus("Target Random Selesai", doneMsg)
            addLog(doneMsg)
            if sendNotification then pcall(sendNotification, doneMsg) end
            return nil, nil, nil
        end

        local attempt = 0
        while STATE.running and attempt < 30 do
            if not waitIfPaused() then return nil, nil, nil end
            attempt = attempt + 1
            local candidate = generateRandomWorldName(CFG.random_length, CFG.random_use_numbers)
            setStatus("Find Random World", string.format("Cek #%d: %s (Target %d/%d)", attempt, candidate, (STATE.random_done_count or 0) + 1, targetCount))
            if warpTo(candidate, "") then
                safeSleep(1200)
                local usable, reason = isCurrentWorldUsableForRandom()
                if usable then
                    addLog("Ditemukan World: " .. candidate .. " (" .. reason .. ") -> Disimpan ke List!")
                    local newDoor = (CFG.use_id_door and CFG.door_id ~= "") and CFG.door_id or ""
                    local listIdx = nil
                    for idx, existing in ipairs(CFG.world_list) do
                        if existing.name == candidate then
                            existing.door = newDoor
                            existing.done = false
                            existing.status = "PROSES"
                            existing.from_random = true
                            listIdx = idx
                            break
                        end
                    end
                    if not listIdx then
                        table.insert(CFG.world_list, {
                            name = candidate,
                            door = newDoor,
                            done = false,
                            status = "PROSES",
                            from_random = true,
                        })
                        listIdx = #CFG.world_list
                    end
                    persistConfig()
                    if updateWorldDisplayList then pcall(updateWorldDisplayList) end
                    return candidate, newDoor, listIdx
                else
                    addLog("Skip " .. candidate .. ": " .. reason)
                end
            end
        end
        setStatus("Gagal Find World", "Tidak menemukan world kosong setelah 30 percobaan.")
        return nil, nil, nil
    end
end

-- ============================================================================
-- 9. DIRT FARM CONSTRUCTION STAGES (GAMBAR 2 + VALIDATION + AUTO-RESUME)
-- ============================================================================

local function checkAndConfigureDoorID()
    local targetID = tostring(CFG.door_id or "DF"):gsub("%s+", "")
    local targetLabel = tostring(CFG.door_label or targetID)
    if targetID == "" then return "" end

    local teleWait = math.max(300, tonumber(CFG.delay_tele_door) or 1500)
    setStatus("Jeda Tele Door (0,0)", string.format("Jeda %d ms sebelum cek Door ID di (0,0)...", teleWait))
    safeSleep(teleWait)
    if CFG.use_modfly and editToggle then pcall(editToggle, "ModFly", true) end
    safeSleep(150)
    moveSafeTo(1, 0)

    local ok0, t0 = pcall(getTile, 0, 0)
    local needPlace = (not ok0) or (not t0) or (t0.fg == 0) or (t0.fg ~= CFG.id_door_itemid and not isDoorOrEntranceItem(t0.fg))

    if needPlace then
        setStatus("Pasang Door ID (0,0)", "Menaruh Door di (0, 0)")
        breakTileCompletely(0, 0, true, false, 1)
        placeAndValidateSecurityTile(0, 0, CFG.id_door_itemid, "Door ID (0,0)", 1, 0)
        safeSleep(300)
        validateAndEditDoorTile(0, 0, targetID, targetLabel, 1, 0)
        return targetID
    end

    local idAlreadyMatching = false
    if t0 and t0.extra then
        if t0.extra.target == targetID or (t0.extra.label and t0.extra.label == targetLabel) then
            idAlreadyMatching = true
        end
    end

    if idAlreadyMatching then
        addLog(string.format("`2[Door ID Validasi] `wDoor ID di (0,0) sudah terpasang & sesuai (ID='%s').", targetID))
    else
        addLog(string.format("`e[Door ID Update] `oDoor ID di (0,0) belum sesuai. Mengatur ulang ke '%s'...", targetID))
        validateAndEditDoorTile(0, 0, targetID, targetLabel, 1, 0)
    end

    return targetID
end

-- Stage A: Setup Locks, Jammer, Door ID & Blocker Doors (Standar Murni Auto Dirt Farm)
-- VALIDASI: Jika sudah terpasang, otomatis skip pembuatan ulang & langsung lanjut proses DF!
local function setupWorldLocks(doorX, doorY, existingSec)
    if CFG.ignore_lock then
        addLog("`2[Ignore Lock] `wMelewati setup lock/security, langsung mulai proses DF...")
        return ""
    end
    local sec = existingSec or inspectWorldSecurityState(doorX, doorY)
    
    local locksAlreadyPlaced = sec.all_ready or (sec.has_wl and sec.has_sl and sec.has_jammer and (sec.has_blocker or sec.has_left_blocker))
    if locksAlreadyPlaced then
        addLog("`2[Lock Validasi] `wKunci world DF sudah terpasang lengkap (WL, Jammer, SL, Penghalang ada). Melewati pembuatan ulang.")
        if sendNotification then pcall(sendNotification, "Lock & Jammer sudah ada! Lanjut DF...") end
        
        -- 1. Re-apply Small Lock jika ada
        if CFG.use_sl and sec.has_sl then
            local slX = sec.sl_x or doorX
            local slY = sec.sl_y or (doorY - 1)
            setStatus("Re-apply Small Lock", "Re-apply SL yang sudah ada...")
            validateAndApplySmallLock(slX, slY, CFG.sl_ignore_air, CFG.sl_public, doorX, math.max(0, doorY - 2))
            safeSleep(200)
        end

        -- 2. Pastikan WL public
        if CFG.use_wl and sec.has_wl and CFG.wl_public then
            local wlX = sec.wl_x or (doorX + 1)
            local wlY = sec.wl_y or doorY
            validateAndEditWorldLock(wlX, wlY, true, doorX + 2, doorY)
            safeSleep(200)
        end

        -- 3. Cek Door ID di (0, 0)
        local activeDoorID = ""
        if CFG.use_id_door then
            activeDoorID = checkAndConfigureDoorID()
        end

        return activeDoorID
    end

    -- JIKA BELUM TERPASANG LENGKAP: Pasang formasi standar asli Dirt Farm
    setStatus("Setup Lock & Moat", string.format("Break dirt sekitar Main Door (%d, %d) sesuai standar asli Dirt Farm", doorX, doorY))

    -- Helper internal: hanya break jika bukan Bedrock, Main Door, atau Lock/Blocker yang sudah terpasang
    local function isKeptSecurityTile(tx, ty)
        if tx == doorX and ty == doorY then return true end
        if tx == doorX and ty == doorY + 1 then return true end
        if sec.has_sl and tx == doorX and ty == doorY - 1 then return true end
        if sec.has_wl and tx == doorX + 1 and ty == doorY then return true end
        if sec.has_jammer and tx == doorX - 1 and ty == doorY - 1 then return true end
        if (sec.has_blocker or sec.has_left_blocker) and tx == doorX - 1 and ty == doorY then return true end
        return false
    end

    -- 0A. Break RING LUAR (Moat 1-tile Empty Air: fg=0 & bg=0) mengelilingi cluster Lock (termasuk kanan-atas & kanan-bawah WL)
    for my = doorY - 2, doorY + 2 do
        for mx = doorX - 2, doorX + 2 do
            local isOuterRing = (math.abs(mx - doorX) == 2 or math.abs(my - doorY) == 2)
            local isLeftBedrock = (mx == doorX - 1 and my == doorY + 1)
            local isRightAboveWL = (mx == doorX + 1 and my == doorY - 1)
            local isRightBelowWL = (mx == doorX + 1 and my == doorY + 1)
            if (isOuterRing or isLeftBedrock or isRightAboveWL or isRightBelowWL) and mx >= 0 and mx <= 99 and my >= 0 and my <= 59 then
                if not isKeptSecurityTile(mx, my) then
                    local prefDir = (mx <= doorX) and -1 or 1
                    breakTileCompletely(mx, my, true, true, prefDir)
                end
            end
        end
    end

    -- 0B. Bersihkan slot cluster Dirt Farm yang BELUM terisi item yang sesuai:
    -- Penghalang Kiri di (doorX - 1, doorY)
    if CFG.use_blocker_door and not (sec.has_blocker or sec.has_left_blocker) and doorX - 1 >= 0 then
        breakTileCompletely(doorX - 1, doorY, true, true, -1)
    end
    -- Signal Jammer di (doorX - 1, doorY - 1)
    if not sec.has_jammer and doorX - 1 >= 0 and doorY - 1 >= 0 then
        breakTileCompletely(doorX - 1, doorY - 1, true, true, -1)
    end
    -- World Lock di (doorX + 1, doorY)
    if not sec.has_wl and doorX + 1 <= 99 then
        breakTileCompletely(doorX + 1, doorY, true, true, 1)
    end
    -- Small Lock di (doorX, doorY - 1)
    if not sec.has_sl and doorY - 1 >= 0 then
        breakTileCompletely(doorX, doorY - 1, true, true, 1)
    end
    -- Slot di atas SL: (doorX, doorY - 2) dikosongkan agar SL apply bersih
    if doorY - 2 >= 0 then
        breakTileCompletely(doorX, doorY - 2, true, true, 1)
    end

    -- ==================== FORMULA RESMI AUTO DIRT FARM ====================
    -- 1. Pasang & Validasi Penghalang Kiri di (doorX - 1, doorY)
    if CFG.use_blocker_door and doorX - 1 >= 0 then
        if not (sec.has_blocker or sec.has_left_blocker) then
            setStatus("Pasang Penghalang Kiri", string.format("Menaruh %s di kiri White Door (%d, %d)", resolveItemName(CFG.blocker_door_itemid), doorX - 1, doorY))
            placeAndValidateSecurityTile(doorX - 1, doorY, CFG.blocker_door_itemid, "Penghalang Kiri", doorX - 2, doorY)
            safeSleep(200)
        end
    end

    -- 2. Pasang & Validasi Signal Jammer di (doorX - 1, doorY - 1) + punch 1x agar aktif
    if CFG.use_jammer and doorX - 1 >= 0 and doorY - 1 >= 0 then
        if not sec.has_jammer then
            setStatus("Pasang Jammer", string.format("Menaruh Signal Jammer di (%d, %d)", doorX - 1, doorY - 1))
            local jamPlaced = placeAndValidateSecurityTile(doorX - 1, doorY - 1, ITEM.JAMMER, "Signal Jammer", doorX - 1, math.max(0, doorY - 2))
            if jamPlaced then
                safeSleep(300)
                sendRawAction(doorX - 1, doorY - 1, ITEM.PUNCH)
                safeSleep(350)
                addLog(string.format("`2[Jammer OK] `wSignal Jammer aktif di (%d, %d)", doorX - 1, doorY - 1))
            end
        else
            addLog("Signal Jammer sudah terpasang di world ini.")
        end
    end

    -- 3. Pasang & Validasi World Lock di (doorX + 1, doorY) [kanan White Door] + Set Public
    if CFG.use_wl and doorX + 1 <= 99 then
        if not sec.has_wl then
            setStatus("Pasang WL", string.format("Menaruh & Set Public WL di (%d, %d)", doorX + 1, doorY))
            placeAndValidateSecurityTile(doorX + 1, doorY, ITEM.WORLD_LOCK, "World Lock (WL)", doorX + 2, doorY)
            safeSleep(200)
        end
        validateAndEditWorldLock(doorX + 1, doorY, CFG.wl_public, doorX + 2, doorY)
        safeSleep(200)
    end

    -- 4. Pasang & Apply Small Lock (Private) di atas White Door (doorX, doorY - 1)
    if CFG.use_sl and doorY - 1 >= 0 then
        if doorY - 2 >= 0 then
            breakTileCompletely(doorX, doorY - 2, true, true, 1)
        end
        if not sec.has_sl then
            setStatus("Pasang Small Lock (Private)", string.format("Menaruh SL di atas White Door (%d, %d)", doorX, doorY - 1))
            placeAndValidateSecurityTile(doorX, doorY - 1, ITEM.SMALL_LOCK, "Small Lock (SL)", doorX, math.max(0, doorY - 2))
            safeSleep(200)
        end
        setStatus("Apply Small Lock", "Set Private + Ignore Empty Air + Re-apply Lock")
        validateAndApplySmallLock(doorX, doorY - 1, CFG.sl_ignore_air, CFG.sl_public, doorX, math.max(0, doorY - 2))
        safeSleep(200)
    end

    -- 5. Pasang Door ID di (0, 0)
    local activeDoorID = ""
    if CFG.use_id_door then
        activeDoorID = checkAndConfigureDoorID()
    end

    return activeDoorID
end

-- Helper: Amankan Lava di bawah kaki target & tile tempat berdiri (x + dirX, y + 1) sebelum melangkah/break
local function sanitizeLavaUnderFoot(x, y, doorX, doorY, dirX)
    if y >= 53 then return end
    local belowY = y + 1
    local checkXs = { x }
    local standX = x + (dirX or -1)
    if standX >= 0 and standX <= 99 then
        table.insert(checkXs, standX)
    end
    for _, cx in ipairs(checkXs) do
        if not isProtectedEnclosure(cx, belowY, doorX, doorY) then
            local ok, belowTile = pcall(getTile, cx, belowY)
            if ok and belowTile and belowTile.fg == ITEM.LAVA then
                breakTileCompletely(cx, belowY, true, false, dirX)
                if belowY % 2 == 0 and (not isInSecurityMoat(cx, belowY, doorX, doorY)) and getInvCount(ITEM.DIRT) > 0 then
                    placeTileAt(cx, belowY, ITEM.DIRT, false, dirX)
                end
            end
        end
    end
end

-- Helper: Tentukan start/end/step zig-zag secara seragam agar tidak duplikasi
local function zigZagRange(goingRight, minV, maxV, stepAbs)
    local s = stepAbs or 1
    if goingRight then
        return minV, maxV, s
    end
    return maxV, minV, -s
end

local function isEdgePlatformTile(tx, ty, doorX, doorY)
    if not CFG.use_platform then return false end
    if ty < 2 or ty > 52 or (ty % 2 ~= 0) then return false end
    if (not CFG.build_upper) and ty < 24 then return false end
    if isInSecurityMoat(tx, ty, doorX, doorY) then return false end
    return (CFG.plat_left and tx == 1) or (CFG.plat_right and tx == 98)
end

-- Helper: Kolom pinggir yang dibersihkan & batas X baris DF berdasarkan setting Platform
-- Jika use_platform == false: kiri 1 baris (x = 0) & kanan 1 baris (x = 99), baris DF penuh x = 1..98
-- Jika use_platform == true: sisi yang dipasang platform butuh 2 baris (kiri: 1,0 | kanan: 98,99)
local function getSideColumns()
    if not CFG.clear_sides then return {} end
    if not CFG.use_platform then
        return { 0, 99 }
    end
    local cols = {}
    if CFG.plat_left then
        table.insert(cols, 1)
        table.insert(cols, 0)
    else
        table.insert(cols, 0)
    end
    if CFG.plat_right then
        table.insert(cols, 98)
        table.insert(cols, 99)
    else
        table.insert(cols, 99)
    end
    return cols
end

local function getDFRowBounds()
    if not CFG.use_platform then
        return 1, 98
    end
    local minX = CFG.plat_left and 2 or 1
    local maxX = CFG.plat_right and 97 or 98
    return minX, maxX
end

-- Helper: Cek apakah foreground/tile aman untuk dibersihkan bot (bukan Bedrock, Main Door, Lock, atau Jammer)
local function isTileClearableByBot(t)
    if not t then return false end
    return t.fg ~= ITEM.BEDROCK and t.fg ~= ITEM.MAIN_DOOR and (not OTHER_LOCKS[t.fg]) and t.fg ~= ITEM.JAMMER
end

-- Helper: Cek apakah 1 tile pada baris ganjil perlu di-break
local function isOddTileClearNeeded(tx, ty, doorX, doorY)
    if isProtectedEnclosure(tx, ty, doorX, doorY) then return false end
    if isEdgePlatformTile(tx, ty, doorX, doorY) then return false end
    local ok, t = pcall(getTile, tx, ty)
    if not ok or not t or not isTileClearableByBot(t) then return false end
    local needFg = (t.fg ~= 0)
    local needBg = CFG.break_cave_bg and (t.bg ~= 0)
    return needFg or needBg, needFg, needBg
end

-- Helper: Cek cepat apakah seluruh desain clear DF (baris ganjil 25..53 & pinggir) sudah bersih agar tidak maksa break lagi
local function isDFOddClearAlreadyDone(doorX, doorY)
    local sideCols = getSideColumns()
    for _, colX in ipairs(sideCols) do
        for y = 24, 53 do
            if (not isProtectedEnclosure(colX, y, doorX, doorY)) and (not isEdgePlatformTile(colX, y, doorX, doorY)) then
                local ok, t = pcall(getTile, colX, y)
                if ok and isTileClearableByBot(t) and (t.fg ~= 0 or (CFG.break_cave_bg and t.bg ~= 0)) then
                    return false
                end
            end
        end
    end
    local rowMinX, rowMaxX = getDFRowBounds()
    for y = 25, 53, 2 do
        for x = rowMinX, rowMaxX do
            if isOddTileClearNeeded(x, y, doorX, doorY) then
                return false
            end
        end
    end
    return true
end

-- Helper: Berdiri tetap di baris tengah centerY & hancurkan sampai 3 tile vertikal (y, y-2, y+2) + Lava di y-1/y+1 tanpa lompat
local function standAndBreak3AtCol(worldName, activeDoorID, doorX, doorY, x, centerY, safeStandDir)
    local standX = math.max(0, math.min(99, x + safeStandDir))
    -- Pastikan tempat berdiri (standX, centerY) & tile di bawahnya aman dari Lava/Dirt sebelum melangkah ke standX
    if (not isProtectedEnclosure(standX, centerY, doorX, doorY)) and isOddTileClearNeeded(standX, centerY, doorX, doorY) then
        local needS, nFgS, nBgS = isOddTileClearNeeded(standX, centerY, doorX, doorY)
        if needS then
            breakTileCompletely(standX, centerY, nFgS, nBgS, safeStandDir, true)
        end
    end
    sanitizeLavaUnderFoot(x, centerY, doorX, doorY, safeStandDir)

    local px, py = getPlayerTilePos()
    if (not px) or py ~= centerY or math.abs(px - x) > 2 or (px == x and py == centerY) or (not isTileSafeToStand(px, py)) then
        if isTileSafeToStand(standX, centerY) then
            moveSafeTo(standX, centerY)
        else
            moveAdjacentSafe(x, centerY, safeStandDir)
        end
    end

    local targets = { centerY, centerY - 2, centerY + 2 }
    for _ = 1, 2 do
        local anyRemaining = false
        for _, ty in ipairs(targets) do
            local need, nFg, nBg = isOddTileClearNeeded(x, ty, doorX, doorY)
            if need then
                anyRemaining = true
                local cpx, cpy = getPlayerTilePos()
                if (not cpx) or math.abs(cpx - x) > 2 or math.abs(cpy - ty) > 2 then
                    if isTileSafeToStand(standX, centerY) then
                        moveSafeTo(standX, centerY)
                    end
                end
                breakTileCompletely(x, ty, nFg, nBg, safeStandDir, true)
            end
        end
        -- Bersihkan juga Lava pada baris genap bersebelahan (y - 1 dan y + 1) selagi karakter tepat berada di sebelah kolom x
        if CFG.break_lava then
            for _, lavaY in ipairs({ centerY - 1, centerY + 1 }) do
                if lavaY >= 24 and lavaY <= 52 and (not isProtectedEnclosure(x, lavaY, doorX, doorY)) then
                    local okL, tL = pcall(getTile, x, lavaY)
                    if okL and tL and tL.fg == ITEM.LAVA then
                        anyRemaining = true
                        breakTileCompletely(x, lavaY, true, false, safeStandDir, true)
                        if (not isInSecurityMoat(x, lavaY, doorX, doorY)) and getInvCount(ITEM.DIRT) > 0 then
                            placeTileAt(x, lavaY, ITEM.DIRT, false, safeStandDir)
                        end
                    end
                end
            end
        end
        if not anyRemaining then break end
    end

    if CFG.auto_collect then
        collectNearbyFloating(x, centerY, CFG.collect_range, true)
    end
    checkTrashAndSeeds(worldName, activeDoorID)
end

-- Helper: Deteksi & bersihkan ulang tile yang tertinggal saat break akibat lag (0 ms bila sudah bersih, max 4 pass + fallback langsung per-tile)
local function sweepRemainingBreakTiles(worldName, activeDoorID, doorX, doorY, checkEvenPlatRockLava, forceDirectMode)
    local rowMinX, rowMaxX = getDFRowBounds()
    local sideCols = getSideColumns()
    for pass = 1, 4 do
        if pass > 1 then
            safeSleep(100)
        end
        local totalLeftover = 0
        local sideLeftover = {}
        for _, colX in ipairs(sideCols) do
            for y = 24, 53 do
                if (not isProtectedEnclosure(colX, y, doorX, doorY)) and (not isEdgePlatformTile(colX, y, doorX, doorY)) then
                    local ok, t = pcall(getTile, colX, y)
                    if ok and isTileClearableByBot(t) then
                        local needFg = (t.fg ~= 0)
                        local needBg = CFG.break_cave_bg and (t.bg ~= 0)
                        if needFg or needBg then
                            table.insert(sideLeftover, { x = colX, y = y, fg = needFg, bg = needBg, dir = (colX < 50) and 1 or -1 })
                            totalLeftover = totalLeftover + 1
                        end
                    end
                end
            end
        end

        local oddLeftoverFlat = {}
        local oddGroups3 = {}
        if CFG.break_3_mode and pass == 1 and (not forceDirectMode) then
            local goingRightSweep = true
            local centerRows = { 27, 33, 39, 45, 51 }
            for _, centerY in ipairs(centerRows) do
                local startX, endX, stepX = zigZagRange(goingRightSweep, rowMinX, rowMaxX, 1)
                local safeStandDir = -stepX
                for x = startX, endX, stepX do
                    local colMiss = 0
                    for _, ty in ipairs({ centerY, centerY - 2, centerY + 2 }) do
                        if isOddTileClearNeeded(x, ty, doorX, doorY) then
                            colMiss = colMiss + 1
                        end
                    end
                    if colMiss > 0 then
                        table.insert(oddGroups3, { x = x, centerY = centerY, dir = safeStandDir })
                        totalLeftover = totalLeftover + colMiss
                    end
                end
                goingRightSweep = not goingRightSweep
            end
        else
            -- Pass >= 2 (atau mode 1-tile): hampiri langsung setiap sisa tile yang bandel agar pasti tuntas meski jalur centerY terhalang
            for y = 25, 53, 2 do
                for x = rowMinX, rowMaxX do
                    local need, needFg, needBg = isOddTileClearNeeded(x, y, doorX, doorY)
                    if need then
                        table.insert(oddLeftoverFlat, { x = x, y = y, fg = needFg, bg = needBg, dir = -1 })
                        totalLeftover = totalLeftover + 1
                    end
                end
            end
        end

        local evenLeftover = {}
        if checkEvenPlatRockLava and (CFG.break_lava or CFG.break_rock) then
            for y = 24, 52, 2 do
                for x = rowMinX, rowMaxX do
                    if not isInSecurityMoat(x, y, doorX, doorY) then
                        local ok, t = pcall(getTile, x, y)
                        if ok and isTileClearableByBot(t) then
                            if (t.fg == ITEM.LAVA and CFG.break_lava) or (t.fg == ITEM.ROCK and CFG.break_rock) then
                                table.insert(evenLeftover, { x = x, y = y, fg = true, bg = false, dir = -1 })
                                totalLeftover = totalLeftover + 1
                            end
                        end
                    end
                end
            end
        end

        if totalLeftover == 0 then
            if pass > 1 then
                addLog("Deteksi Lag Break OK: Semua tile tertinggal sudah bersih (0 tersisa)!")
            end
            return true
        end

        setStatus("Deteksi Lag Break", string.format("Sweep #%d: %d tile tertinggal di %s, lanjut break...", pass, totalLeftover, worldName))
        for _, grp in ipairs(oddGroups3) do
            if not waitIfPaused() then return false end
            if not ensureOnlineInWorld(worldName, activeDoorID) then return false end
            standAndBreak3AtCol(worldName, activeDoorID, doorX, doorY, grp.x, grp.centerY, grp.dir)
        end
        for _, cellList in ipairs({ sideLeftover, oddLeftoverFlat, evenLeftover }) do
            for _, cell in ipairs(cellList) do
                if not waitIfPaused() then return false end
                if not ensureOnlineInWorld(worldName, activeDoorID) then return false end
                if cell.y >= 25 then
                    sanitizeLavaUnderFoot(cell.x, cell.y, doorX, doorY, cell.dir)
                end
                moveAdjacentSafe(cell.x, cell.y, cell.dir)
                breakTileCompletely(cell.x, cell.y, cell.fg, cell.bg, cell.dir)
                checkTrashAndSeeds(worldName, activeDoorID)
            end
        end
    end
    return true
end

-- Stage B: Clear Side Columns (x = 0,99 bila platform false; 2 kolom bila platform aktif) and Alternating Rows (Mode 1 Tile / Mode 3 Tile)
local function clearWorldDirtFarm(worldName, activeDoorID, doorX, doorY)
    if isDFOddClearAlreadyDone(doorX, doorY) then
        -- Desain DF clear sudah terbentuk (seperti Gambar 2): tidak perlu buang waktu clear sisa Rock di platform, langsung lanjut Plant/Harvest & Place DF!
        addLog("Desain DF sudah terbentuk! Skip clear sisa Rock & langsung lanjut place DF...")
        return true
    end

    local rowMinX, rowMaxX = getDFRowBounds()
    local sideCols = getSideColumns()

    do
        if #sideCols > 0 then
            -- Bersihkan kolom pinggir dengan jeda antar kolom & per-tile agar tidak kena rate-limit/ercon.
            local prevColX = nil
            local sideBrokenCount = 0
            local sideDelay = math.max(0, tonumber(CFG.delay_clear_sides) or 120)
            for _, colX in ipairs(sideCols) do
                if not ensureOnlineInWorld(worldName, activeDoorID) then return false end
                if prevColX ~= nil then
                    if (prevColX <= 1 and colX >= 98) or (prevColX >= 98 and colX <= 1) then
                        safeSleep(math.max(650, sideDelay * 4))
                    else
                        safeSleep(math.max(400, sideDelay * 2))
                    end
                end
                prevColX = colX
                setStatus("Clear Pinggir", string.format("Membersihkan kolom pinggir x = %d", colX))
                for y = 24, 53 do
                    if not waitIfPaused() then return false end
                    if (not isProtectedEnclosure(colX, y, doorX, doorY)) and (not isEdgePlatformTile(colX, y, doorX, doorY)) then
                        local ok, t = pcall(getTile, colX, y)
                        if ok and t and t.fg ~= ITEM.BEDROCK and t.fg ~= ITEM.MAIN_DOOR then
                            local hasFg = (t.fg ~= 0)
                            local hasBg = CFG.break_cave_bg and (t.bg ~= 0)
                            if hasFg or hasBg then
                                local prefDir = (colX < 50) and 1 or -1
                                if breakTileCompletely(colX, y, hasFg, hasBg, prefDir) then
                                    sideBrokenCount = sideBrokenCount + 1
                                    if sideDelay > 0 then safeSleep(sideDelay) end
                                    if sideBrokenCount % 8 == 0 then safeSleep(200) end
                                end
                                checkTrashAndSeeds(worldName, activeDoorID)
                            end
                        end
                    end
                end
            end
        end

        local goingRight = true
        if CFG.break_3_mode then
            -- Mode Break 3 Tile (Gambar 1): jalan di baris tengah {27, 33, 39, 45, 51}, break y-2, y, dan y+2 sekaligus!
            local centerRows = { 27, 33, 39, 45, 51 }
            for _, centerY in ipairs(centerRows) do
                if not ensureOnlineInWorld(worldName, activeDoorID) then return false end
                local dxNow, dyNow = findMainDoor()
                if dxNow and dyNow then doorX, doorY = dxNow, dyNow end

                local startX, endX, stepX = zigZagRange(goingRight, rowMinX, rowMaxX, 1)
                local safeStandDir = -stepX

                setStatus("Break 3 Tile", string.format("World: %s | Baris Y = %d,%d,%d", worldName, centerY - 2, centerY, centerY + 2))
                for x = startX, endX, stepX do
                    if not waitIfPaused() then return false end
                    local anyNeed = false
                    for _, ty in ipairs({ centerY, centerY - 2, centerY + 2 }) do
                        if isOddTileClearNeeded(x, ty, doorX, doorY) then
                            anyNeed = true
                            break
                        end
                    end
                    if (not anyNeed) and CFG.break_lava then
                        for _, ly in ipairs({ centerY - 1, centerY + 1 }) do
                            if ly >= 24 and ly <= 52 and (not isProtectedEnclosure(x, ly, doorX, doorY)) then
                                local okL, tL = pcall(getTile, x, ly)
                                if okL and tL and tL.fg == ITEM.LAVA then
                                    anyNeed = true
                                    break
                                end
                            end
                        end
                    end
                    if anyNeed then
                        standAndBreak3AtCol(worldName, activeDoorID, doorX, doorY, x, centerY, safeStandDir)
                    end
                end
                goingRight = not goingRight
            end
        else
            -- Mode Break 1 Tile: break 1 baris ganjil per jalan
            for y = 25, 53, 2 do
                if not ensureOnlineInWorld(worldName, activeDoorID) then return false end
                local dxNow, dyNow = findMainDoor()
                if dxNow and dyNow then doorX, doorY = dxNow, dyNow end

                local startX, endX, stepX = zigZagRange(goingRight, rowMinX, rowMaxX, 1)
                local safeStandDir = -stepX

                setStatus("Break Baris Kosong", string.format("World: %s | Baris Y = %d", worldName, y))
                for x = startX, endX, stepX do
                    if not waitIfPaused() then return false end
                    local need, nFg, nBg = isOddTileClearNeeded(x, y, doorX, doorY)
                    if need then
                        sanitizeLavaUnderFoot(x, y, doorX, doorY, safeStandDir)
                        breakTileCompletely(x, y, nFg, nBg, safeStandDir)
                        checkTrashAndSeeds(worldName, activeDoorID)
                    end
                end
                goingRight = not goingRight
            end
        end
    end

    -- Deteksi cepat apakah masih ada tile pinggir/baris ganjil yang tertinggal karena lag saat break
    if not sweepRemainingBreakTiles(worldName, activeDoorID, doorX, doorY, false) then
        return false
    end

    -- Baris Platform Genap Bawah (24..52): HANYA break Lava (jika aktif) & Rock (jika df_break_rock aktif); put dilakukan batch 3 tile di buildUpperPlatforms
    if CFG.break_lava or CFG.break_rock then
        local goingRightPlat = true
        for y = 24, 52, 2 do
            if not ensureOnlineInWorld(worldName, activeDoorID) then return false end
            local dxNow, dyNow = findMainDoor()
            if dxNow and dyNow then doorX, doorY = dxNow, dyNow end

            local rowHasBreakTarget = false
            for x = rowMinX, rowMaxX do
                if not isInSecurityMoat(x, y, doorX, doorY) then
                    local ok, t = pcall(getTile, x, y)
                    if ok and isTileClearableByBot(t) and ((t.fg == ITEM.LAVA and CFG.break_lava) or (t.fg == ITEM.ROCK and CFG.break_rock)) then
                        rowHasBreakTarget = true
                        break
                    end
                end
            end

            if rowHasBreakTarget then
                local startX, endX, stepX = zigZagRange(goingRightPlat, rowMinX, rowMaxX, 1)
                local safeStandDir = -stepX
                setStatus("Rapikan Baris Platform", string.format("World: %s | Baris Y = %d", worldName, y))
                for x = startX, endX, stepX do
                    if not waitIfPaused() then return false end
                    if not isInSecurityMoat(x, y, doorX, doorY) then
                        local ok, t = pcall(getTile, x, y)
                        if ok and isTileClearableByBot(t) then
                            if (t.fg == ITEM.LAVA and CFG.break_lava) or (t.fg == ITEM.ROCK and CFG.break_rock) then
                                breakTileCompletely(x, y, true, false, safeStandDir)
                            end
                        end
                    end
                end
            end
            goingRightPlat = not goingRightPlat
        end
    end

    -- Validasi akhir break DF (termasuk baris genap Lava/Rock yg mungkin terlewat akibat lag)
    if not sweepRemainingBreakTiles(worldName, activeDoorID, doorX, doorY, true) then
        return false
    end

    return true
end

-- Helper: Hitung berapa tile platform yang masih kosong (sesuai area build, exclude Security Moat)
local function countMissingDirtPlatforms(doorX, doorY)
    local rowMinX, rowMaxX = getDFRowBounds()
    local missing = 0
    for y = 24, 52, 2 do
        for x = rowMinX, rowMaxX do
            if not isInSecurityMoat(x, y, doorX, doorY) then
                local ok, t = pcall(getTile, x, y)
                if ok and t and t.fg == 0 then
                    missing = missing + 1
                end
            end
        end
    end
    if CFG.build_upper then
        for y = 2, 22, 2 do
            for x = rowMinX, rowMaxX do
                if not isInSecurityMoat(x, y, doorX, doorY) then
                    local ok, t = pcall(getTile, x, y)
                    if ok and t and t.fg == 0 then
                        missing = missing + 1
                    end
                end
            end
        end
    end
    return missing
end

-- Harvest 1 pohon Dirt matang dengan validasi fg == 0 (tahan lag) lalu wajib take hasil dropnya
local function harvestDirtTreeAt(tx, ty)
    for round = 1, 3 do
        if not waitIfPaused() then return false end
        local ok, t = pcall(getTile, tx, ty)
        if not ok or not t or t.fg ~= ITEM.DIRT_SEED then
            break
        end
        local px, py = getPlayerTilePos()
        if (not px) or math.abs(px - tx) > 2 or math.abs(py - ty) > 2 then
            moveSafeTo(tx, ty)
        end
        for _ = 1, 2 do
            if not waitIfPaused() then return false end
            local okStep, tStep = pcall(getTile, tx, ty)
            if not okStep or not tStep or tStep.fg ~= ITEM.DIRT_SEED then
                break
            end
            sendRawAction(tx, ty, ITEM.PUNCH)
            safeSleep(CFG.delay_break)
        end
        if awaitTileLayerCleared(tx, ty, true, 220) then
            break
        end
    end
    -- Beri jeda singkat untuk paket WorldObject drop server lalu wajib hampiri & take
    moveSafeTo(tx, ty)
    safeSleep(60)
    collectNearbyFloating(tx, ty, math.max(3, CFG.collect_range or 3), false, true)
    local okEnd, tEnd = pcall(getTile, tx, ty)
    return (not okEnd) or (not tEnd) or (tEnd.fg ~= ITEM.DIRT_SEED)
end

-- Stage C: Auto Plant & Harvest Dirt Seeds (Harvest Take) untuk mengumpulkan Dirt Block bahan bentuk DF
local function farmDirtUntilEnough(worldName, activeDoorID, doorX, doorY)
    if not CFG.auto_farm_dirt then return true end

    local farmRowY = 23
    local rowMinX, rowMaxX = getDFRowBounds()
    while STATE.running do
        if not waitIfPaused() then return false end
        if not ensureOnlineInWorld(worldName, activeDoorID) then return false end
        local missing = countMissingDirtPlatforms(doorX, doorY)
        if getInvCount(ITEM.DIRT) < math.min(160, missing) then
            collectBackupDropsFromDF(ITEM.DIRT)
        end
        local currentDirt = getInvCount(ITEM.DIRT)
        if missing <= 0 or currentDirt >= math.min(160, missing) then
            return true
        end

        -- Pastikan lantai row 24 tempat tanam terisi blok padat jika masih punya Dirt (jangan timpa Rock)
        for x = rowMinX, rowMaxX do
            if not isInSecurityMoat(x, farmRowY + 1, doorX, doorY) then
                local okF, tf = pcall(getTile, x, farmRowY + 1)
                if okF and tf and tf.fg == 0 and getInvCount(ITEM.DIRT) > 0 then
                    placeTileAt(x, farmRowY + 1, ITEM.DIRT, false, -1)
                end
            end
        end

        -- 1. Harvest & Take semua pohon Dirt matang (2 pass agar yg miss karena lag ikut kepanen)
        local harvestedAny = false
        for hPass = 1, 2 do
            local missedTree = false
            for x = rowMinX, rowMaxX do
                if not waitIfPaused() then return false end
                if not isProtectedEnclosure(x, farmRowY, doorX, doorY) then
                    local okT, t = pcall(getTile, x, farmRowY)
                    if okT and t and t.fg == ITEM.DIRT_SEED and t.readyharvest then
                        setStatus("Harvest & Take", string.format("Panen & ambil Dirt Tree di (%d, %d)", x, farmRowY))
                        if not harvestDirtTreeAt(x, farmRowY) then
                            missedTree = true
                        end
                        harvestedAny = true
                        if getInvCount(ITEM.DIRT) >= 185 then
                            break
                        end
                    end
                end
            end
            if (not missedTree) or getInvCount(ITEM.DIRT) >= 185 then
                break
            end
        end
        if harvestedAny then
            for sx = 10, 90, 8 do
                if getInvCount(ITEM.DIRT) >= 190 then break end
                collectNearbyFloating(sx, farmRowY, 5, true, true)
            end
            -- Poin 2: Begitu dapat Dirt dari harvest, langsung kembali untuk place di atas (kalau masih kurang baru tanam lagi!)
            if getInvCount(ITEM.DIRT) > 0 then
                return true
            end
        end

        -- 2. Jika Dirt Seed di BP habis, ambil dulu cadangan Dirt Seed yg sempat di-drop di DF saat tahap break
        if getInvCount(ITEM.DIRT_SEED) <= 0 then
            collectBackupDropsFromDF(ITEM.DIRT_SEED)
        end

        -- Hitung pohon yg sudah tertanam di row 23 saat ini
        local currentTrees = 0
        for x = rowMinX, rowMaxX do
            local okC, tc = pcall(getTile, x, farmRowY)
            if okC and tc and tc.fg == ITEM.DIRT_SEED then
                currentTrees = currentTrees + 1
            end
        end

        -- 3. Poin 2: Tanam secukupnya saja sesuai setting Max Tanam (misal 50), tidak melebihi kebutuhan sisa tile
        local maxBatch = math.max(1, math.min(rowMaxX - rowMinX + 1, tonumber(CFG.max_plant_dirt) or 50))
        local targetTrees = math.min(maxBatch, missing)
        if getInvCount(ITEM.DIRT_SEED) > 0 and currentTrees < targetTrees then
            setStatus("Plant Dirt Seed", string.format("Tanam secukupnya (%d/%d pohon | sisa place %d)", currentTrees, targetTrees, missing))
            for pPass = 1, 2 do
                local plantMissed = 0
                for x = rowMinX, rowMaxX do
                    if not waitIfPaused() then return false end
                    if currentTrees >= targetTrees or getInvCount(ITEM.DIRT_SEED) <= 0 then break end
                    if not isProtectedEnclosure(x, farmRowY, doorX, doorY) then
                        local okT, t = pcall(getTile, x, farmRowY)
                        local okFloor, floorT = pcall(getTile, x, farmRowY + 1)
                        local solidFloor = okFloor and floorT and floorT.fg ~= 0 and (floorT.fg == ITEM.DIRT or floorT.fg == ITEM.ROCK or floorT.collidable)
                        if okT and t and t.fg == 0 and solidFloor then
                            if placeTileAt(x, farmRowY, ITEM.DIRT_SEED, false, -1) then
                                currentTrees = currentTrees + 1
                            else
                                plantMissed = plantMissed + 1
                            end
                        end
                    end
                end
                if plantMissed == 0 or currentTrees >= targetTrees or getInvCount(ITEM.DIRT_SEED) <= 0 then
                    break
                end
            end
        end

        -- Hitung ulang pohon yg sedang tumbuh & cek apakah ada yg sudah matang
        local treeCount = 0
        local readyNow = false
        for x = rowMinX, rowMaxX do
            local okT, t = pcall(getTile, x, farmRowY)
            if okT and t and t.fg == ITEM.DIRT_SEED then
                treeCount = treeCount + 1
                if t.readyharvest then readyNow = true end
            end
        end

        if treeCount == 0 and getInvCount(ITEM.DIRT_SEED) == 0 and getInvCount(ITEM.DIRT) == 0 then
            addLog("Stok Dirt Block & Dirt Seed habis, lanjut ke validasi DF.")
            return true
        end

        -- Poin 2: Selama tree belum ready, bot waiting sampai bisa di-harvest!
        if (not readyNow) and treeCount > 0 then
            setStatus("Tunggu Pohon Tumbuh", string.format("Waiting %d Dirt Tree siap harvest...", treeCount))
            while STATE.running do
                if not waitIfPaused() then return false end
                if not ensureOnlineInWorld(worldName, activeDoorID) then return false end
                local foundReady = false
                local stillTrees = 0
                for x = rowMinX, rowMaxX do
                    local okR, tr = pcall(getTile, x, farmRowY)
                    if okR and tr and tr.fg == ITEM.DIRT_SEED then
                        stillTrees = stillTrees + 1
                        if tr.readyharvest then
                            foundReady = true
                            break
                        end
                    end
                end
                if foundReady or stillTrees == 0 then break end
                safeSleep(1500)
            end
        end
    end
    return true
end

-- Cari posisi berdiri di koridor ATAS (y - 1) atau BAWAH (y + 1) baris platform target, jangan di baris y itu sendiri
local function moveToStandAboveOrBelow(cx, targetY)
    local candidates = {}
    local rowOffsets = {}
    if targetY - 1 >= 1 then table.insert(rowOffsets, -1) end
    if targetY + 1 <= 53 then table.insert(rowOffsets, 1) end

    for _, dy in ipairs(rowOffsets) do
        local sy = targetY + dy
        for _, sx in ipairs({ cx, cx - 1, cx + 1, cx - 2, cx + 2 }) do
            if sx >= 1 and sx <= 98 and isTileSafeToStand(sx, sy) then
                table.insert(candidates, { x = sx, y = sy })
            end
        end
    end

    for _, pos in ipairs(candidates) do
        if moveSafeTo(pos.x, pos.y) then
            return pos.x, pos.y
        end
    end
    return nil, nil
end

-- Put sampai 3 tile platform horizontal sekaligus dari 1 posisi (atas/bawah), cek jarak & lag lalu ulangi yg masih bolong
local function placePlatformBatch3(rowY, standX, standY, missingXs)
    local pending = {}
    for _, x in ipairs(missingXs) do
        table.insert(pending, x)
    end

    for attempt = 1, 3 do
        if #pending == 0 then return true, 0 end
        local px, py = getPlayerTilePos()
        if px ~= standX or py ~= standY then
            moveSafeTo(standX, standY)
        end

        for _, tx in ipairs(pending) do
            if not waitIfPaused() then return false, #pending end
            if getInvCount(ITEM.DIRT) <= 0 then break end
            local cpx, cpy = getPlayerTilePos()
            if (not cpx) or cpy == rowY or math.abs(cpx - tx) > 2 or math.abs(cpy - rowY) > 2 then
                if isTileSafeToStand(tx, standY) then
                    moveSafeTo(tx, standY)
                else
                    local altX, altY = moveToStandAboveOrBelow(tx, rowY)
                    if altX and altY then standX, standY = altX, altY end
                end
            end
            sendRawAction(tx, rowY, ITEM.DIRT)
            safeSleep(CFG.delay_place)
        end

        local stillMissing = {}
        for waitMs = 25, 250, 25 do
            stillMissing = {}
            for _, tx in ipairs(pending) do
                local ok, t = pcall(getTile, tx, rowY)
                if ok and t and t.fg == 0 then
                    table.insert(stillMissing, tx)
                end
            end
            if #stillMissing == 0 then
                return true, 0
            end
            safeSleep(25)
        end

        stillMissing = {}
        for _, tx in ipairs(pending) do
            local ok, t = pcall(getTile, tx, rowY)
            if ok and t and t.fg == 0 then
                table.insert(stillMissing, tx)
            end
        end
        pending = stillMissing
        if #pending == 0 then
            return true, 0
        end
        if getInvCount(ITEM.DIRT) <= 0 then
            break
        end
        if attempt < 3 then
            addLog(string.format("Put lag di Y=%d (%d tile belum masuk), ulangi cepat...", rowY, #pending))
        end
    end

    return (#pending == 0), #pending
end

-- Stage D: Susun Platform Dirt Atas (y = 22..2), Perbaiki Bawah (y = 24..52), Put 3 Tile dari Atas/Bawah & Validasi Ulang
local function buildUpperPlatforms(worldName, activeDoorID, doorX, doorY)
    local rowsToBuild = {}
    for y = 24, 52, 2 do
        table.insert(rowsToBuild, y)
    end
    if CFG.build_upper then
        for y = 22, 2, -2 do
            table.insert(rowsToBuild, y)
        end
    end

    local rowMinX, rowMaxX = getDFRowBounds()

    for pass = 1, 6 do
        rowMinX, rowMaxX = getDFRowBounds()
        for rowIdx, y in ipairs(rowsToBuild) do
            if not ensureOnlineInWorld(worldName, activeDoorID) then return false end
            local dxNow, dyNow = findMainDoor()
            if dxNow and dyNow then doorX, doorY = dxNow, dyNow end

            -- Cek dulu apakah baris y masih ada yang kosong (jangan ganggu Rock yang sudah jadi bagian platform)
            local rowNeedsWork = false
            for x = rowMinX, rowMaxX do
                if not isInSecurityMoat(x, y, doorX, doorY) then
                    local ok, t = pcall(getTile, x, y)
                    if ok and t and t.fg == 0 then
                        rowNeedsWork = true
                        break
                    end
                end
            end

            if rowNeedsWork then
                setStatus(
                    pass == 1 and "Put 3-Tile Platform" or "Validasi & Tambal Bolong",
                    string.format("Pass %d | Baris Y = %d", pass, y)
                )
                local centers = {}
                local pos = rowMinX
                while pos <= rowMaxX do
                    table.insert(centers, math.min(rowMaxX, pos + 1))
                    pos = pos + 3
                end
                local cStart, cEnd, cStep = zigZagRange(rowIdx % 2 == 1, 1, #centers, 1)

                for ci = cStart, cEnd, cStep do
                    local cx = centers[ci]
                    if not waitIfPaused() then return false end
                    local missingXs = {}
                    for _, tx in ipairs({ cx - 1, cx, cx + 1 }) do
                        if tx >= rowMinX and tx <= rowMaxX and not isInSecurityMoat(tx, y, doorX, doorY) then
                            local ok, t = pcall(getTile, tx, y)
                            if ok and t and t.fg == 0 then
                                table.insert(missingXs, tx)
                            end
                        end
                    end

                    if #missingXs > 0 then
                        if getInvCount(ITEM.DIRT) < #missingXs then
                            collectBackupDropsFromDF(ITEM.DIRT)
                        end
                        if getInvCount(ITEM.DIRT) < #missingXs and CFG.auto_farm_dirt then
                            farmDirtUntilEnough(worldName, activeDoorID, doorX, doorY)
                        end
                        if getInvCount(ITEM.DIRT) > 0 then
                            local standX, standY = moveToStandAboveOrBelow(cx, y)
                            if standX and standY then
                                local okPlace = placePlatformBatch3(y, standX, standY, missingXs)
                                if not okPlace and not STATE.running then return false end
                            else
                                -- Fallback darurat bila kedua koridor atas & bawah terhalang total
                                for _, tx in ipairs(missingXs) do
                                    if getInvCount(ITEM.DIRT) <= 0 then break end
                                    placeTileAt(tx, y, ITEM.DIRT, false, -1)
                                end
                            end
                        end
                    end
                end
            end
        end

        local holesRemaining = 0
        for _, y in ipairs(rowsToBuild) do
            for x = rowMinX, rowMaxX do
                if not isInSecurityMoat(x, y, doorX, doorY) then
                    local ok, t = pcall(getTile, x, y)
                    if ok and t and t.fg == 0 then
                        holesRemaining = holesRemaining + 1
                    end
                end
            end
        end

        if holesRemaining == 0 then
            addLog("Validasi Platform DF OK: Semua baris DF rapat (0 bolong)!")
            break
        else
            addLog(string.format("Validasi Platform Pass %d: Terdeteksi %d tile masih bolong, lanjut tambal...", pass, holesRemaining))
            local hasTrees23 = false
            for x = rowMinX, rowMaxX do
                local okT, tr = pcall(getTile, x, 23)
                if okT and tr and tr.fg == ITEM.DIRT_SEED then
                    hasTrees23 = true
                    break
                end
            end
            if getInvCount(ITEM.DIRT) <= 0 and ((not CFG.auto_farm_dirt) or (getInvCount(ITEM.DIRT_SEED) <= 0 and not hasTrees23)) then
                break
            end
        end
    end

    -- Poin 6: Pasang Platform di jalur naik-turun pinggir (x = 1 dan/atau x = 98) di setiap lantai DF
    if CFG.use_platform and (CFG.plat_left or CFG.plat_right) then
        local platID = (CFG.platform_itemid and CFG.platform_itemid > 0) and CFG.platform_itemid or ITEM.WOOD_PLATFORM
        local edgeCols = {}
        if CFG.plat_left then table.insert(edgeCols, 1) end
        if CFG.plat_right then table.insert(edgeCols, 98) end

        for _, ex in ipairs(edgeCols) do
            if getInvCount(platID) <= 0 then
                addLog(string.format("Stok Platform (%s) habis di BP, skip sisa pemasangan pinggir.", resolveItemName(platID)))
                break
            end
            setStatus("Pasang Platform Pinggir", string.format("Memasang %s di kolom x = %d", resolveItemName(platID), ex))
            for y = 2, 52, 2 do
                if not waitIfPaused() then return false end
                if getInvCount(platID) <= 0 then break end
                if (CFG.build_upper or y >= 24) and (not isInSecurityMoat(ex, y, doorX, doorY)) then
                    local okT, t = pcall(getTile, ex, y)
                    if okT and t and t.fg ~= platID then
                        if t.fg ~= 0 and isTileClearableByBot(t) then
                            breakTileCompletely(ex, y, true, false, (ex == 1) and 1 or -1)
                        end
                        local okNow, tNow = pcall(getTile, ex, y)
                        if okNow and tNow and tNow.fg == 0 then
                            placeTileAt(ex, y, platID, false, (ex == 1) and 1 or -1)
                        end
                    end
                end
            end
        end
    end

    -- Bersihkan sisa pohon panen terakhir di row 23 jika ada yg sudah matang
    for x = rowMinX, rowMaxX do
        if not isProtectedEnclosure(x, 23, doorX, doorY) then
            local ok, t = pcall(getTile, x, 23)
            if ok and t and t.fg == ITEM.DIRT_SEED and t.readyharvest then
                harvestDirtTreeAt(x, 23)
            end
        end
    end

    return true
end

-- Poin 4: Deteksi block penghalang / troll yang merusak simetri garis DF (area atas, baris ganjil, line genap DF, & sekitar White Door/WL)
local function findLineObstructions(doorX, doorY)
    local rowMinX, rowMaxX = getDFRowBounds()
    local obs = {}
    local seen = {}
    local function addObs(tx, ty)
        local key = tostring(tx) .. "," .. tostring(ty)
        if seen[key] then return end
        seen[key] = true
        table.insert(obs, { x = tx, y = ty, dir = (tx < 50) and 1 or -1 })
    end

    -- 1. Cek baris ganjil atas & bawah (y = 1..53, step 2) dari block troll yg dipasang orang
    local minOddY = CFG.build_upper and 1 or 25
    for y = minOddY, 53, 2 do
        for x = rowMinX, rowMaxX do
            if not isProtectedEnclosure(x, y, doorX, doorY) then
                local ok, t = pcall(getTile, x, y)
                if ok and t and t.fg ~= 0 and isTileClearableByBot(t) then
                    if not (y == 23 and t.fg == ITEM.DIRT_SEED) then
                        addObs(x, y)
                    end
                end
            end
        end
    end

    -- 2. Cek garis platform genap DF (y = 2..52, step 2): tidak boleh ada block asing selain Dirt / Rock / Platform
    local minEvenY = CFG.build_upper and 2 or 24
    for y = minEvenY, 52, 2 do
        for x = rowMinX, rowMaxX do
            if not isInSecurityMoat(x, y, doorX, doorY) then
                local ok, t = pcall(getTile, x, y)
                if ok and t and t.fg ~= 0 and isTileClearableByBot(t) then
                    local isValidPlat = (t.fg == ITEM.DIRT)
                        or (t.fg == ITEM.ROCK and not CFG.break_rock)
                        or (CFG.use_platform and t.fg == CFG.platform_itemid)
                    if not isValidPlat then
                        addObs(x, y)
                    end
                end
            end
        end
    end

    -- 3. Cek area sekitar White Door, SL & WL (troll block di atas SL/WL yang menghalangi)
    if doorX and doorY then
        for my = math.max(0, doorY - 2), math.min(53, doorY + 2) do
            for mx = math.max(0, doorX - 2), math.min(99, doorX + 2) do
                if not isProtectedEnclosure(mx, my, doorX, doorY) then
                    local ok, t = pcall(getTile, mx, my)
                    if ok and t and t.fg ~= 0 and isTileClearableByBot(t) then
                        addObs(mx, my)
                    end
                end
            end
        end
    end

    return obs
end

local function sweepLineObstructions(worldName, activeDoorID, doorX, doorY)
    local obs = findLineObstructions(doorX, doorY)
    if #obs == 0 then return true end
    setStatus("Bersihkan Penghalang DF", string.format("Deteksi %d block penghalang simetri DF!", #obs))
    for _, cell in ipairs(obs) do
        if not waitIfPaused() then return false end
        if not ensureOnlineInWorld(worldName, activeDoorID) then return false end
        moveAdjacentSafe(cell.x, cell.y, cell.dir)
        breakTileCompletely(cell.x, cell.y, true, false, cell.dir)
        checkTrashAndSeeds(worldName, activeDoorID)
    end
    return true
end

-- Inspeksi seluruh layout DF (sisa clear break + penghalang simetri DF + platform DF yang bolong)
local function inspectFullDFLayout(doorX, doorY)
    local breakLeft = 0
    local sideCols = getSideColumns()
    for _, colX in ipairs(sideCols) do
        for y = 24, 53 do
            if (not isProtectedEnclosure(colX, y, doorX, doorY)) and (not isEdgePlatformTile(colX, y, doorX, doorY)) then
                local ok, t = pcall(getTile, colX, y)
                if ok and isTileClearableByBot(t) and (t.fg ~= 0 or (CFG.break_cave_bg and t.bg ~= 0)) then
                    breakLeft = breakLeft + 1
                end
            end
        end
    end
    local rowMinX, rowMaxX = getDFRowBounds()
    for y = 25, 53, 2 do
        for x = rowMinX, rowMaxX do
            if isOddTileClearNeeded(x, y, doorX, doorY) then
                breakLeft = breakLeft + 1
            end
        end
    end
    if CFG.break_lava or CFG.break_rock then
        for y = 24, 52, 2 do
            for x = rowMinX, rowMaxX do
                if not isInSecurityMoat(x, y, doorX, doorY) then
                    local ok, t = pcall(getTile, x, y)
                    if ok and isTileClearableByBot(t) and ((t.fg == ITEM.LAVA and CFG.break_lava) or (t.fg == ITEM.ROCK and CFG.break_rock)) then
                        breakLeft = breakLeft + 1
                    end
                end
            end
        end
    end

    local obsList = findLineObstructions(doorX, doorY)
    breakLeft = breakLeft + #obsList

    local platHoles = countMissingDirtPlatforms(doorX, doorY)
    return breakLeft, platHoles
end

-- Stage E: Deteksi penuh apakah layout DF sudah lengkap (clear bersih + bebas block penghalang + semua platform ter-put)
local function validateAndRepairFullDFLayout(worldName, activeDoorID, doorX, doorY)
    for cycle = 1, 3 do
        local breakLeft, platHoles = inspectFullDFLayout(doorX, doorY)
        if breakLeft == 0 and platHoles == 0 then
            addLog("Deteksi Layout DF OK: Semua break bersih (0 sisa) & semua line DF simetris (0 bolong)!")
            return true
        end

        addLog(string.format("Deteksi Layout DF #%d: Sisa/Penghalang=%d tile | Platform Bolong=%d tile -> Perbaiki otomatis...", cycle, breakLeft, platHoles))
        setStatus("Deteksi Layout DF", string.format("Cycle %d | Break/Penghalang: %d | Tambal DF: %d", cycle, breakLeft, platHoles))

        if breakLeft > 0 then
            if not sweepRemainingBreakTiles(worldName, activeDoorID, doorX, doorY, (CFG.break_lava or CFG.break_rock), true) then
                return false
            end
            if not sweepLineObstructions(worldName, activeDoorID, doorX, doorY) then
                return false
            end
        end
        if platHoles > 0 then
            if not buildUpperPlatforms(worldName, activeDoorID, doorX, doorY) then
                return false
            end
        end
    end
    return true
end

-- ============================================================================
-- 10. MAIN COROUTINE ORCHESTRATOR
-- ============================================================================

local function processSingleWorld()
    -- 1. Masuk ke World Target dulu untuk mengecek apakah Lock/Jammer sudah terpasang!
    local worldName, worldDoor, manualIdx = acquireTargetWorld()
    if not worldName then
        return false
    end

    STATE.current_world = worldName
    STATE.active_world = worldName
    STATE.active_door = worldDoor or ""
    STATE.df_dropped_spots = {}
    if manualIdx and CFG.world_list[manualIdx] then
        CFG.world_list[manualIdx].done = false
        CFG.world_list[manualIdx].status = "PROSES"
        if updateWorldDisplayList then pcall(updateWorldDisplayList) end
    end
    applyCheatToggles()
    safeSleep(800)

    local doorX, doorY = findMainDoor()
    if not doorX or not doorY then
        setStatus("Error Main Door", "Main Door tidak ditemukan di world " .. worldName)
        return false
    end

    -- 2. Cek apakah di world ini sudah terpasang WL, SL, Jammer, Door ID & Penghalang
    local secState = inspectWorldSecurityState(doorX, doorY)
    local activeDoorID = worldDoor or ""

    local locksAlreadyPlaced = secState.all_ready or (secState.has_wl and secState.has_sl and secState.has_jammer and (secState.has_blocker or secState.has_left_blocker))

    if CFG.ignore_lock then
        setStatus("Ignore Lock DF", "Ignore Lock AKTIF di " .. worldName .. "! Langsung lanjut DF...")
        addLog("`2[Ignore Lock] `wWorld " .. worldName .. " mode Ignore Lock aktif (Bukan Owner). Langsung melanjutkan proses DF tanpa lock/storage!")
        activeDoorID = worldDoor or ""
    elseif locksAlreadyPlaced then
        setStatus("Auto-Resume DF", "Lock, Jammer & Door sudah terpasang di " .. worldName .. "! Langsung lanjut DF...")
        addLog("`2[Auto-Resume DF] `wWorld " .. worldName .. " sudah terpasang lock lengkap! Melanjutkan proses DF tanpa ke Storage Alat...")
        if CFG.use_id_door and activeDoorID == "" then
            activeDoorID = CFG.door_id
        end
        if CFG.use_id_door and not secState.has_id_door then
            activeDoorID = checkAndConfigureDoorID()
        end
    else
        -- Ambil alat yang kurang saja dari Storage Alat, lalu kembali ke world DF
        if not ensureToolsFromStorage(secState, worldName, worldDoor) then
            return false
        end
        doorX, doorY = findMainDoor()
        if not doorX or not doorY then
            return false
        end
        activeDoorID = setupWorldLocks(doorX, doorY, secState)
        if activeDoorID == "" then
            activeDoorID = worldDoor or ""
        end
    end
    if manualIdx and CFG.world_list[manualIdx] and activeDoorID ~= "" and CFG.world_list[manualIdx].door ~= activeDoorID then
        CFG.world_list[manualIdx].door = activeDoorID
        persistConfig()
        if updateWorldDisplayList then pcall(updateWorldDisplayList) end
    end

    -- 3. Cek penuh apakah layout DF sudah lengkap (Lock lengkap + break bersih + 0 platform bolong); jika belum, clear, build & repair!
    local initBreakLeft, initPlatHoles = inspectFullDFLayout(doorX, doorY)
    if secState.all_ready and initBreakLeft == 0 and initPlatHoles == 0 then
        addLog("Cek Status World: " .. worldName .. " sudah selesai penuh (0 bolong, 0 sisa) -> Status DONE!")
    else
        if not clearWorldDirtFarm(worldName, activeDoorID, doorX, doorY) then
            return false
        end
        if not buildUpperPlatforms(worldName, activeDoorID, doorX, doorY) then
            return false
        end
        if not validateAndRepairFullDFLayout(worldName, activeDoorID, doorX, doorY) then
            return false
        end
    end

    -- 5. Setelah DF terbentuk semua & ter-place: ambil cadangan seed di DF (bila ada) lalu simpan ke World Storage Seed!
    if CFG.storage_seed_world ~= "" or (#(CFG.storage_seed_list or {}) > 0) then
        for _ = 1, 4 do
            collectBackupDropsFromDF(nil)
            saveSeedsToStorage(worldName, activeDoorID, true)
            if not hasAnyDroppedBackupInDF() then
                break
            end
        end
    else
        saveSeedsToStorage(worldName, activeDoorID, true)
    end

    if STATE.reconnected_restart then
        return false
    end

    local wasRandom = (CFG.world_mode == "random")
    if manualIdx and CFG.world_list[manualIdx] then
        CFG.world_list[manualIdx].done = true
        CFG.world_list[manualIdx].status = "DONE"
        if CFG.world_list[manualIdx].from_random then
            wasRandom = true
        end
        persistConfig()
    end
    if wasRandom then
        STATE.random_done_count = (STATE.random_done_count or 0) + 1
    end

    STATE.worlds_completed = STATE.worlds_completed + 1
    STATE.active_world = ""
    STATE.active_door = ""
    if updateWorldDisplayList then pcall(updateWorldDisplayList) end
    setStatus("World Selesai!", string.format("DF %s selesai! (Total: %d)", worldName, STATE.worlds_completed))
    if sendNotification then
        pcall(sendNotification, "DF Selesai: " .. worldName)
    end
    return true
end

local function startAutoDF()
    if STATE.running then return end
    ensureRuntimeHooks()
    STATE.running = true
    STATE.paused  = false
    STATE.random_done_count = 0
    if editToggle then pcall(editToggle, "df_run_power", true) end
    if updatePowerStatusList then pcall(updatePowerStatusList) end

    local okCoro, errCoro = pcall(runCoroutine, function()
        syncInputsFromGL()
        setStatus("Bot Berjalan", "Auto Dirt Farm by Boren Store aktif...")
        logInventoryDiagnostic({ ITEM.WORLD_LOCK, ITEM.SMALL_LOCK, ITEM.JAMMER, CFG.id_door_itemid, CFG.blocker_door_itemid }, "Start")
        applyCheatToggles()

        while STATE.running do
            local ok, res = pcall(processSingleWorld)
            if ok and res then
                STATE.reconnected_restart = false
                STATE.resume_world_override = nil
                STATE.resume_door_override = nil
            elseif (not ok) or (not res) then
                if STATE.running and STATE.reconnected_restart then
                    STATE.reconnected_restart = false
                    setStatus("Auto-Restart DF", "Kembali online! Menjalankan ulang scan DF dari awal...")
                    addLog("Auto Reconnect OK -> Run ulang DF otomatis agar tidak ada tile tertinggal!")
                    safeSleep(900)
                else
                    local onlineNow = isPlayerOnlineInWorld()
                    if STATE.running and CFG.auto_reconnect and ((not onlineNow) or STATE.reconnecting) then
                        ensureOnlineInWorld(STATE.active_world, STATE.active_door)
                        if STATE.reconnected_restart then
                            STATE.reconnected_restart = false
                            setStatus("Auto-Restart DF", "Kembali online! Menjalankan ulang scan DF dari awal...")
                            addLog("Auto Reconnect OK -> Run ulang DF otomatis agar tidak ada tile tertinggal!")
                            safeSleep(900)
                        else
                            STATE.running = false
                            break
                        end
                    else
                        if not ok then
                            setStatus("Error", tostring(res))
                        end
                        STATE.running = false
                        break
                    end
                end
            end
            safeSleep(1200)
        end

        STATE.running = false
        STATE.paused  = false
        STATE.reconnecting = false
        if editToggle then pcall(editToggle, "df_run_power", false) end
        setStatus("Berhenti", "Auto Dirt Farm berhenti.")
        if updatePowerStatusList then pcall(updatePowerStatusList) end
    end)

    if not okCoro then
        STATE.running = false
        STATE.paused  = false
        if editToggle then pcall(editToggle, "df_run_power", false) end
        setStatus("Error Coroutine", tostring(errCoro))
        if updatePowerStatusList then pcall(updatePowerStatusList) end
        if sendNotification then pcall(sendNotification, "Gagal mulai bot: " .. tostring(errCoro)) end
    end
end

-- ============================================================================
-- 11. NATIVE GROWLAUNCHER MENU ("Boren Store")
-- ============================================================================

updateTrashDisplayList = function()
    if not editValue then return end
    local tList = {}
    local items = getConfiguredTrashItemList()
    local thresh = math.max(10, tonumber(CFG.trash_threshold) or 150)
    for _, id in ipairs(items) do
        table.insert(tList, {
            string.format("%s (ID: %d)", resolveItemName(id), id),
            string.format("BP: %d | Auto-Trash >= %d", getInvCount(id), thresh)
        })
    end
    if #tList == 0 then
        table.insert(tList, { "List Trash kosong", "Pick item lalu klik + Tambah" })
    end
    pcall(editValue, "df_trash_display_list", jsonEncode(tList))
end

local function updateBagDisplayList()
    if not editValue then return end
    local bList = {}
    for _, it in ipairs(STATE.cached_inv) do
        local tag = it.isDoor and " [DOOR]" or ""
        table.insert(bList, {
            string.format("%s (ID: %d)%s", it.name, it.id, tag),
            string.format("Jumlah: %d", it.amount)
        })
    end
    if #bList == 0 then
        table.insert(bList, { "Belum ada data tas", "Klik 'Refresh Status, Log & Tas' saat di world" })
    end
    pcall(editValue, "df_bag_display_list", jsonEncode(bList))
end

local function updateLogDisplayList()
    if not editValue then return end
    local lList = {
        { "Status: " .. tostring(STATE.current_step), tostring(STATE.status_text) },
        { "World: " .. tostring(STATE.current_world), "DF Selesai: " .. tostring(STATE.worlds_completed) },
    }
    for i = 1, math.min(10, #STATE.logs) do
        table.insert(lList, { "Log #" .. tostring(i), tostring(STATE.logs[i]) })
    end
    pcall(editValue, "df_log_display_list", jsonEncode(lList))
end

updatePowerStatusList = function()
    if not editValue then return end
    local row1Title = "STATUS: BERHENTI (OFF)"
    local row1Sub = "Tekan 'START AUTO DF' untuk mulai"
    if STATE.reconnecting then
        row1Title = "STATUS: MENUNGGU ONLINE"
        row1Sub = "Terputus, otomatis lanjut saat online"
    elseif STATE.running and STATE.paused then
        row1Title = "STATUS: DIJEDA (PAUSE)"
        row1Sub = "World: " .. tostring(STATE.current_world)
    elseif STATE.running then
        row1Title = "STATUS: SEDANG JALAN (ON)"
        row1Sub = "Tekan 'STOP AUTO DF' untuk berhenti"
    end
    pcall(editValue, "df_power_status_list", jsonEncode({
        { row1Title, row1Sub },
        { "World: " .. tostring(STATE.current_world), "Selesai: " .. tostring(STATE.worlds_completed) .. " | Err: " .. tostring(STATE.error_count) }
    }))
end

refreshNativeDisplayLists = function()
    updatePowerStatusList()
    updateWorldDisplayList()
    updateToolStorageDisplayList()
    updateSeedStorageDisplayList()
    updateFileInfoDisplayList()
    updateBagDisplayList()
    updateLogDisplayList()
end

-- Helper UI Builder: memakai UserInterface.new() bawaan Growlauncher agar skema JSON 100% sesuai APK
local function createNativeUI(subName, iconName)
    if UserInterface and UserInterface.new then
        return UserInterface.new(subName, iconName)
    end
    local ui = { sub_name = subName, icon = iconName, menu = {} }
    function ui:addLabelApp(text, icon)
        table.insert(self.menu, { type = "labelapp", text = text, icon = icon or "" })
        return self
    end
    function ui:addLabel(text)
        table.insert(self.menu, { type = "label", text = text })
        return self
    end
    function ui:addDivider()
        table.insert(self.menu, { type = "divider" })
        return self
    end
    function ui:addToggle(text, default, alias, autosave)
        table.insert(self.menu, { type = "toggle", text = text, default = default == true, alias = alias, autosave = autosave == true })
        return self
    end
    function ui:addToggleButton(text, default, alias)
        table.insert(self.menu, { type = "toggle_button", text = text, default = default == true, alias = alias })
        return self
    end
    function ui:addButton(text, alias)
        table.insert(self.menu, { type = "button", text = text, alias = alias })
        return self
    end
    function ui:addInputString(text, default, label, placeholder, icon, alias)
        table.insert(self.menu, { type = "input_string", text = text, default = default or "", label = label or "Text", placeholder = placeholder or "", icon = icon or "", alias = alias })
        return self
    end
    function ui:addInputInt(text, default, label, placeholder, icon, alias)
        table.insert(self.menu, { type = "input_int", text = text, default = tostring(default or "0"), label = label or "Value", placeholder = placeholder or "0", icon = icon or "", alias = alias })
        return self
    end
    function ui:addSlider(text, minVal, maxVal, defaultVal, stepVal, useDot, alias)
        table.insert(self.menu, { type = "slider", text = text, min = minVal, max = maxVal, default = defaultVal, step = stepVal, use_dot = useDot == true, alias = alias })
        return self
    end
    function ui:addTooltip(text, supportText, icon, background)
        table.insert(self.menu, { type = "tooltip", text = text, support_text = supportText or "", icon = icon or "Info", background = background == true })
        return self
    end
    function ui:addItemPicker(text, item, default, alias)
        table.insert(self.menu, { type = "item_picker", text = text, item = item or "Blank", default = tostring(default or "0"), alias = alias })
        return self
    end
    function ui:addDisplayList(text, default, alias)
        table.insert(self.menu, { type = "display_list", text = text, default = default or "Default", alias = alias })
        return self
    end
    function ui:addExpandableToggle(text, default, alias, alwaysExpand, background)
        local obj = {
            type = "expandable_toggle",
            text = text,
            default = default == true,
            alias = alias,
            always_expand = alwaysExpand == true,
            background = background == true,
            list_child = {},
        }
        table.insert(self.menu, obj)
        return obj
    end
    function ui:addChildButton(parentList, text, alias)
        if type(parentList) == "table" then
            table.insert(parentList, { type = "button", text = text, alias = alias })
        end
        return self
    end
    function ui:addChildToggle(parentList, text, default, alias, autosave, background)
        if type(parentList) == "table" then
            table.insert(parentList, { type = "toggle", text = text, default = default == true, alias = alias, autosave = autosave == true, background = background == true })
        end
        return self
    end
    function ui:generateJSON()
        return jsonEncode({ sub_name = self.sub_name, icon = self.icon, menu = self.menu })
    end
    return ui
end

local function registerNativeBorenStoreUI()
    if not addCategory or not addIntoModule then return end

    -- Sub-Menu 1: Start & World
    local uiWorld = createNativeUI("1. Start & World", "PlayArrow")
    uiWorld:addLabelApp("Boren Store - Auto DF", "Storefront")
    if uiWorld.addExpandableToggle and uiWorld.addChildButton and uiWorld.addChildToggle then
        local runCard = uiWorld:addExpandableToggle("▶ START AUTO DF", false, "df_run_power", false, true)
        uiWorld:addChildButton(runCard.list_child, "■ STOP AUTO DF", "df_btn_stop_df")
        uiWorld:addChildToggle(runCard.list_child, "Pause Bot", false, "df_pause_toggle")
    else
        uiWorld:addToggleButton("▶ START / ■ STOP AUTO DF", false, "df_run_power")
        uiWorld:addButton("■ STOP AUTO DF", "df_btn_stop_df")
        uiWorld:addToggle("Pause Bot", false, "df_pause_toggle", false)
    end
    uiWorld:addDisplayList("Status Bot", "Default", "df_power_status_list")
    uiWorld:addDivider()
    uiWorld:addLabel("Daftar World:")
    uiWorld:addInputString("Nama World", CFG.manual_world_text, "World", "WORLD1", "Public", "df_manual_world_input")
    uiWorld:addInputString("Door ID (Opsional)", CFG.manual_door_text, "Door ID", "Kosong = White Door", "DoorFront", "df_manual_door_input")
    uiWorld:addButton("+ Tambah World ke Antrean", "df_btn_add_world")
    uiWorld:addButton("+ Pakai World Sekarang", "df_btn_add_cur_world")
    uiWorld:addButton("📋 Kelola / Edit, Salin & Tempel World", "df_btn_view_worlds")
    uiWorld:addButton("🗑️ Kosongkan Semua World", "df_btn_clear_worlds")
    uiWorld:addDivider()
    uiWorld:addLabel("Cadangan File (Folder Download HP):")
    uiWorld:addDisplayList("Status File Download", "Default", "df_file_info_list")
    uiWorld:addButton("📥 Simpan Antrean ke Download", "df_btn_save_worlds")
    uiWorld:addButton("📤 Muat Antrean dari Download", "df_btn_load_worlds")
    uiWorld:addDisplayList("List World DF", "Default", "df_world_display_list")
    uiWorld:addDivider()
    uiWorld:addLabel("Random World:")
    uiWorld:addToggle("Mode Random World", CFG.world_mode == "random", "df_world_random", true)
    if uiWorld.addInputInt then
        uiWorld:addInputInt("Jumlah World Random", tostring(CFG.random_target_count), "Target", "5", "FormatListNumbered", "df_random_target")
    else
        uiWorld:addInputString("Jumlah World Random", tostring(CFG.random_target_count), "Target", "5", "FormatListNumbered", "df_random_target")
    end
    uiWorld:addSlider("Panjang Nama", 4, 10, CFG.random_length, 1, false, "df_random_len")
    uiWorld:addToggle("Campur Angka", CFG.random_use_numbers, "df_random_num", true)

    -- Sub-Menu 2: Lock & Door
    local idDoorName = ITEM_NAME_CACHE[CFG.id_door_itemid] or ("Item #" .. tostring(CFG.id_door_itemid))
    local blkDoorName = ITEM_NAME_CACHE[CFG.blocker_door_itemid] or resolveItemName(CFG.blocker_door_itemid)
    local uiLock = createNativeUI("2. Lock & Door", "Lock")
    uiLock:addLabelApp("Lock & Door", "Lock")
    uiLock:addTooltip("Posisi Lock", "WL kanan (Public), SL atas (Private), Jammer kiri-atas, Penghalang kiri, Door ID di (0,0).", "Verified", false)
    uiLock:addToggle("Ignore Lock (Bukan Owner)", CFG.ignore_lock, "df_ignore_lock", true)
    uiLock:addToggle("World Lock (WL)", CFG.use_wl, "df_use_wl", true)
    uiLock:addToggle("WL Public", CFG.wl_public, "df_wl_public", true)
    uiLock:addDivider()
    uiLock:addToggle("Small Lock (SL)", CFG.use_sl, "df_use_sl", true)
    uiLock:addToggle("SL Ignore Air & Apply", CFG.sl_ignore_air, "df_sl_ignore", true)
    uiLock:addToggle("SL Public (OFF = Private)", CFG.sl_public, "df_sl_public", true)
    uiLock:addDivider()
    uiLock:addToggle("Signal Jammer", CFG.use_jammer, "df_use_jammer", true)
    uiLock:addDivider()
    uiLock:addToggle("Door ID di (0,0)", CFG.use_id_door, "df_use_id_door", true)
    uiLock:addItemPicker("Item Door ID", idDoorName, tostring(CFG.id_door_itemid), "df_pick_id_door")
    uiLock:addInputInt("ID Door (Manual)", tostring(CFG.id_door_itemid), "ID Item", "Contoh: 12 (Main Door) / 102 (Door)", "Tag", "df_input_id_door")
    uiLock:addInputString("ID Door", CFG.door_id, "ID Door", "DF123", "DoorFront", "df_door_id")
    uiLock:addInputString("Label Door", CFG.door_label, "Label", "BOREN STORE", "Label", "df_door_label")
    uiLock:addSlider("Jeda Tele (0,0) (ms)", 300, 4000, CFG.delay_tele_door, 100, false, "df_delay_tele_door")
    uiLock:addDivider()
    uiLock:addToggle("Penghalang Kiri", CFG.use_blocker_door, "df_use_blocker", true)
    uiLock:addItemPicker("Item Penghalang", blkDoorName, tostring(CFG.blocker_door_itemid), "df_pick_blocker")
    uiLock:addInputInt("ID Penghalang (Manual)", tostring(CFG.blocker_door_itemid), "ID Item", "Contoh: 2810 (Air Vent) / 12 (Door)", "Tag", "df_input_blocker")

    -- Sub-Menu 3: Storage
    local uiStorage = createNativeUI("3. Storage", "Inventory")
    uiStorage:addLabelApp("Storage Alat & Seed", "Inventory")
    uiStorage:addLabel("Ambil Alat (Lock/Door/Jammer):")
    uiStorage:addInputString("World Storage Alat", CFG.storage_pack_world, "World", "WORLDALAT", "Inventory", "df_pack_w")
    uiStorage:addInputString("Door Storage Alat", CFG.storage_pack_door, "Door", "DOOR123", "DoorFront", "df_pack_d")
    uiStorage:addButton("➕ Tambah Gudang Alat", "df_btn_add_tool_direct")
    uiStorage:addButton("📋 Kelola Gudang Alat", "df_btn_manage_tools")
    uiStorage:addButton("🗑️ Kosongkan Gudang Alat", "df_btn_clear_tool_direct")
    uiStorage:addDisplayList("Daftar Gudang Alat", "Default", "df_tool_storage_list")
    uiStorage:addDivider()
    uiStorage:addLabel("Simpan Seed:")
    uiStorage:addInputString("World Storage Seed", CFG.storage_seed_world, "World", "Kosong = drop di DF", "Grass", "df_seed_w")
    uiStorage:addInputString("Door Storage Seed", CFG.storage_seed_door, "Door", "SEED123", "DoorFront", "df_seed_d")
    uiStorage:addButton("➕ Tambah Gudang Seed", "df_btn_add_seed_direct")
    uiStorage:addButton("📋 Kelola Gudang Seed", "df_btn_manage_seeds")
    uiStorage:addButton("🗑️ Kosongkan Gudang Seed", "df_btn_clear_seed_direct")
    uiStorage:addDisplayList("Daftar Gudang Seed", "Default", "df_seed_storage_list")
    uiStorage:addSlider("Simpan Saat >=", 50, 195, CFG.save_seed_threshold, 5, false, "df_seed_thresh")
    uiStorage:addTooltip("Info Seed", "Cave/Lava/Rock langsung disimpan. Dirt Seed disimpan setelah DF selesai.", "Info", false)
    uiStorage:addToggle("Dirt Seed (Setelah DF)", CFG.save_dirt_seed, "df_save_dirt", true)
    uiStorage:addToggle("Cave Seed", CFG.save_cave_seed, "df_save_cave", true)
    uiStorage:addToggle("Lava Seed", CFG.save_lava_seed, "df_save_lava", true)
    uiStorage:addToggle("Rock Seed", CFG.save_rock_seed, "df_save_rock", true)
    uiStorage:addToggle("Lava Block", CFG.save_lava_block, "df_save_lava_block", true)
    uiStorage:addDivider()
    uiStorage:addLabel("Custom Save & Tes Drop:")
    uiStorage:addToggle("Simpan Item Pilihan", CFG.use_custom_save, "df_use_custom_save", true)
    uiStorage:addItemPicker("Pilih Item", ITEM_NAME_CACHE[CFG.custom_save_itemid] or resolveItemName(CFG.custom_save_itemid), tostring(CFG.custom_save_itemid), "df_pick_save_item")
    uiStorage:addButton("Tes Drop Item", "df_btn_test_drop")

    -- Sub-Menu 4: Pengaturan
    local uiSetting = createNativeUI("4. Pengaturan", "Build")
    uiSetting:addLabelApp("Pengaturan DF", "Build")
    uiSetting:addLabel("Umum:")
    uiSetting:addToggle("Auto Collect", CFG.auto_collect, "df_auto_collect", true)
    uiSetting:addSlider("Jarak Collect (Tile)", 1, 6, CFG.collect_range, 1, false, "df_collect_range")
    uiSetting:addToggle("Auto Reconnect", CFG.auto_reconnect, "df_auto_reconnect", true)
    uiSetting:addToggle("Anti-Lava", CFG.use_anti_lava, "df_anti_lava", true)
    uiSetting:addToggle("ModFly Otomatis", CFG.use_modfly, "df_modfly", true)
    uiSetting:addDivider()
    uiSetting:addLabel("Break & Tanam DF:")
    uiSetting:addToggle("Break 3 Baris (Cepat)", CFG.break_3_mode, "df_break_3_mode", true)
    uiSetting:addToggle("Clear Pinggir", CFG.clear_sides, "df_clear_sides", true)
    uiSetting:addSlider("Jeda Pinggir (ms)", 0, 500, CFG.delay_clear_sides, 20, false, "df_delay_sides")
    uiSetting:addToggle("Break Cave BG", CFG.break_cave_bg, "df_break_cave", true)
    uiSetting:addToggle("Break Lava", CFG.break_lava, "df_break_lava", true)
    uiSetting:addToggle("Break Rock", CFG.break_rock, "df_break_rock", true)
    uiSetting:addToggle("Susun Dirt Atas (y=2-22)", CFG.build_upper, "df_build_upper", true)
    uiSetting:addToggle("Auto Tanam Dirt", CFG.auto_farm_dirt, "df_auto_farm", true)
    uiSetting:addSlider("Max Tanam Dirt Seed", 10, 98, CFG.max_plant_dirt, 2, false, "df_max_plant_dirt")
    uiSetting:addDivider()
    uiSetting:addLabel("Platform Pinggir:")
    uiSetting:addToggle("Pakai Platform", CFG.use_platform, "df_use_platform", true)
    uiSetting:addItemPicker("Item Platform", ITEM_NAME_CACHE[CFG.platform_itemid] or resolveItemName(CFG.platform_itemid), tostring(CFG.platform_itemid), "df_pick_platform")
    uiSetting:addToggle("Pasang Kiri (x=1)", CFG.plat_left, "df_plat_left", true)
    uiSetting:addToggle("Pasang Kanan (x=98)", CFG.plat_right, "df_plat_right", true)
    uiSetting:addDivider()
    uiSetting:addLabel("Auto-Trash:")
    uiSetting:addToggle("Aktifkan Auto-Trash", CFG.auto_trash_junk, "df_auto_trash", true)
    uiSetting:addSlider("Trash Saat >=", 10, 200, CFG.trash_threshold, 10, false, "df_trash_thresh")
    uiSetting:addItemPicker("Pilih Item Trash", ITEM_NAME_CACHE[CFG.trash_picker_itemid] or resolveItemName(CFG.trash_picker_itemid), tostring(CFG.trash_picker_itemid), "df_pick_trash_item")
    uiSetting:addButton("+ Tambah Trash", "df_btn_add_trash")
    uiSetting:addButton("- Hapus Trash", "df_btn_rem_trash")
    uiSetting:addButton("Kelola / Edit List Trash", "df_btn_view_trash")
    uiSetting:addButton("Reset Default Trash", "df_btn_reset_trash")
    uiSetting:addDisplayList("List Auto-Trash", "[]", "df_trash_display_list")
    uiSetting:addDivider()
    uiSetting:addLabel("Delay:")
    uiSetting:addSlider("Delay Break (ms)", 80, 400, CFG.delay_break, 10, false, "df_delay_break")
    uiSetting:addSlider("Delay Place (ms)", 80, 400, CFG.delay_place, 10, false, "df_delay_place")
    uiSetting:addSlider("Delay Jalan (ms)", 80, 500, CFG.delay_walk, 10, false, "df_delay_walk")
    uiSetting:addSlider("Delay Warp (ms)", 3000, 8000, CFG.delay_warp, 250, false, "df_delay_warp")

    -- Sub-Menu 5: Console & Tas
    local uiBackpack = createNativeUI("5. Console & Tas", "Terminal")
    uiBackpack:addLabelApp("Console & Backpack", "Terminal")
    uiBackpack:addToggle("Mini Console", false, "df_mini_console", false)
    uiBackpack:addToggle("Hanya Error", false, "df_console_err_only", false)
    uiBackpack:addButton("Buka Log", "df_btn_open_console")
    uiBackpack:addButton("Bersihkan Log", "df_btn_clear_console")
    uiBackpack:addDivider()
    uiBackpack:addButton("Refresh Tas", "df_btn_refresh_bag")
    uiBackpack:addDisplayList("Isi Backpack", "Default", "df_bag_display_list")

    pcall(addCategory, "Boren Store", "Storefront")
    pcall(addIntoModule, uiWorld:generateJSON(), "Boren Store")
    pcall(addIntoModule, uiLock:generateJSON(), "Boren Store")
    pcall(addIntoModule, uiStorage:generateJSON(), "Boren Store")
    pcall(addIntoModule, uiSetting:generateJSON(), "Boren Store")
    pcall(addIntoModule, uiBackpack:generateJSON(), "Boren Store")
end

-- Handle events from Native Growlauncher Menu ("Boren Store")
local lastAliasEventTime = {}

local function toBoolVal(v)
    return (v == true or v == 1 or v == "true" or v == "1")
end

local function handleUIValue(vtype, name, value)
    -- Shift argumen jika GrowLauncher memanggil onValue(alias, value) atau alias ada di vtype
    if type(vtype) == "string" and (name == nil or type(name) ~= "string" or (type(name) == "string" and vtype:sub(1, 3) == "df_")) then
        value = name
        name = vtype
        vtype = 0
    end
    name = tostring(name or "")
    if name == "" then return end

    local now = os.clock()
    local isButton = (name:sub(1, 7) == "df_btn_")
    if isButton then
        if lastAliasEventTime[name] and (now - lastAliasEventTime[name]) < 0.25 then
            return
        end
        lastAliasEventTime[name] = now
    else
        local evKey = name .. "=" .. tostring(value)
        if lastAliasEventTime[evKey] and (now - lastAliasEventTime[evKey]) < 0.08 then
            return
        end
        lastAliasEventTime[evKey] = now
    end

    if name == "df_pause_toggle" then
        STATE.paused = toBoolVal(value)
        setStatus(STATE.paused and "Paused" or "Resumed", STATE.paused and "Bot dijeda" or "Bot lanjut")
    elseif name == "df_run_power" then
        local wantRun = toBoolVal(value)
        if wantRun and not STATE.running then
            startAutoDF()
        elseif not wantRun and STATE.running then
            STATE.running = false
            STATE.paused = false
            STATE.reconnecting = false
            setStatus("Stopping", "Menghentikan bot...")
            updatePowerStatusList()
        end
        return
    elseif name == "df_btn_stop_df" then
        STATE.running = false
        STATE.paused = false
        STATE.reconnecting = false
        if editToggle then pcall(editToggle, "df_run_power", false) end
        setStatus("Stopping", "Bot dihentikan via tombol STOP.")
        updatePowerStatusList()
        if sendNotification then pcall(sendNotification, "Auto DF dihentikan!") end
        return
    elseif name == "df_manual_world_input" then
        CFG.manual_world_text = tostring(value or ""):upper()
        STATE.buf_world_name = CFG.manual_world_text
    elseif name == "df_manual_door_input" then
        CFG.manual_door_text = tostring(value or "")
        STATE.buf_world_door = CFG.manual_door_text
    elseif name == "df_btn_add_world" then
        local wIn = readGLString("df_manual_world_input", "")
        if wIn ~= "" then
            STATE.buf_world_name = wIn:upper()
            CFG.manual_world_text = STATE.buf_world_name
        end
        local dIn = readGLString("df_manual_door_input", "")
        if dIn ~= "" then
            STATE.buf_world_door = dIn
            CFG.manual_door_text = dIn
        end
        local targetW = (STATE.buf_world_name ~= "" and STATE.buf_world_name) or CFG.manual_world_text
        local targetD = (STATE.buf_world_door ~= "" and STATE.buf_world_door) or CFG.manual_door_text
        local count = addManualWorldsFromString(targetW, targetD, false)
        persistConfig()
        updateWorldDisplayList()
        if count > 0 then
            if sendNotification then pcall(sendNotification, string.format("%d World ditambahkan! (Total: %d)", count, #CFG.world_list)) end
        else
            if sendNotification then pcall(sendNotification, "Isi Nama World dulu di atas!") end
        end
    elseif name == "df_btn_add_cur_world" then
        local curW = getWorldNameSafe()
        if curW ~= "" and curW ~= "EXIT" then
            STATE.buf_world_name = curW
            CFG.manual_world_text = curW
            addManualWorldsFromString(curW, STATE.buf_world_door, false)
            persistConfig()
            updateWorldDisplayList()
            if sendNotification then pcall(sendNotification, string.format("World ditambahkan: %s (Total: %d)", curW, #CFG.world_list)) end
        else
            if sendNotification then pcall(sendNotification, "Anda belum masuk ke dalam world!") end
        end
    elseif name == "df_btn_clear_worlds" then
        CFG.world_list = {}
        CFG.manual_world_text = ""
        STATE.buf_world_name = ""
        persistConfig()
        updateWorldDisplayList()
        if sendNotification then pcall(sendNotification, "List world dikosongkan!") end
    elseif name == "df_btn_view_worlds" or name == "df_btn_paste_worlds" or name == "df_btn_copy_all_worlds" then
        ensureRuntimeHooks()
        updateWorldDisplayList()
        openWorldListManagerDialog()
    elseif name == "df_world_file" then
        local f = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if f ~= "" then
            CFG.world_file_name = f
            if updateFileInfoDisplayList then updateFileInfoDisplayList() end
        end
    elseif name == "df_btn_browse_files" then
        ensureRuntimeHooks()
        if updateFileInfoDisplayList then updateFileInfoDisplayList() end
        local curW = getWorldNameSafe()
        local opened = false
        if curW ~= "" and curW ~= "EXIT" then
            opened = openFileBrowserManagerDialog()
        end
        if not opened then
            local fullP, dir, fn = resolveWorldFilePath()
            local ok, statusMsg = checkWorldFileStatus(fullP)
            if sendNotification then pcall(sendNotification, "Path File HP:\n" .. fullP .. "\n(" .. statusMsg .. ")") end
        end
    elseif name == "df_btn_save_worlds" then
        local fIn = readGLString("df_world_file", "")
        if fIn ~= "" then CFG.world_file_name = fIn:gsub("^%s+", ""):gsub("%s+$", "") end
        saveWorldListToStorage(true)
        if updateFileInfoDisplayList then updateFileInfoDisplayList() end
    elseif name == "df_btn_load_worlds" then
        local fIn = readGLString("df_world_file", "")
        if fIn ~= "" then CFG.world_file_name = fIn:gsub("^%s+", ""):gsub("%s+$", "") end
        loadWorldListFromStorage(true)
        if updateWorldDisplayList then updateWorldDisplayList() end
        if updateFileInfoDisplayList then updateFileInfoDisplayList() end
    elseif name == "df_world_random" then
        CFG.world_mode = toBoolVal(value) and "random" or "manual"
    elseif name == "df_random_target" then
        local n = math.floor(tonumber(value) or 5)
        CFG.random_target_count = math.max(1, n)
    elseif name == "df_random_len" then
        CFG.random_length = tonumber(value) or 6
    elseif name == "df_random_num" then
        CFG.random_use_numbers = toBoolVal(value)
    elseif name == "df_ignore_lock" then
        CFG.ignore_lock = toBoolVal(value)
        persistConfig()
    elseif name == "df_use_wl" then
        CFG.use_wl = toBoolVal(value)
    elseif name == "df_wl_public" then
        CFG.wl_public = toBoolVal(value)
    elseif name == "df_use_sl" then
        CFG.use_sl = toBoolVal(value)
    elseif name == "df_sl_ignore" then
        CFG.sl_ignore_air = toBoolVal(value)
    elseif name == "df_sl_public" then
        CFG.sl_public = toBoolVal(value)
    elseif name == "df_use_jammer" then
        CFG.use_jammer = toBoolVal(value)
    elseif name == "df_use_id_door" then
        CFG.use_id_door = toBoolVal(value)
        persistConfig()
    elseif name == "df_pick_id_door" then
        if not value or value == "" or value == 0 or value == "0" then return end
        local num = resolvePickedItemID(value)
        if num and num > 0 and CFG.id_door_itemid ~= num then
            CFG.id_door_itemid = num
            persistConfig()
            if editValue then pcall(editValue, "df_input_id_door", tostring(num)) end
            if sendNotification then pcall(sendNotification, "Door ID: " .. resolveItemName(num) .. " (ID: " .. num .. ")") end
        end
    elseif name == "df_input_id_door" then
        local num = tonumber(value)
        if num and num > 0 and CFG.id_door_itemid ~= math.floor(num) then
            CFG.id_door_itemid = math.floor(num)
            persistConfig()
            if sendNotification then pcall(sendNotification, "Door ID (Manual): " .. resolveItemName(CFG.id_door_itemid) .. " (ID: " .. CFG.id_door_itemid .. ")") end
        end
    elseif name == "df_door_id" then
        CFG.door_id = tostring(value or "DF123")
        persistConfig()
    elseif name == "df_door_label" then
        CFG.door_label = tostring(value or "BOREN STORE")
        persistConfig()
    elseif name == "df_use_blocker" then
        CFG.use_blocker_door = toBoolVal(value)
        persistConfig()
    elseif name == "df_pick_blocker" then
        if not value or value == "" or value == 0 or value == "0" then return end
        local num = resolvePickedItemID(value)
        if num and num > 0 and CFG.blocker_door_itemid ~= num then
            CFG.blocker_door_itemid = num
            persistConfig()
            if editValue then pcall(editValue, "df_input_blocker", tostring(num)) end
            if sendNotification then pcall(sendNotification, "Penghalang Kiri: " .. resolveItemName(num) .. " (ID: " .. num .. ")") end
        end
    elseif name == "df_input_blocker" then
        local num = tonumber(value)
        if num and num > 0 and CFG.blocker_door_itemid ~= math.floor(num) then
            CFG.blocker_door_itemid = math.floor(num)
            persistConfig()
            if sendNotification then pcall(sendNotification, "Penghalang (Manual): " .. resolveItemName(CFG.blocker_door_itemid) .. " (ID: " .. CFG.blocker_door_itemid .. ")") end
        end
    elseif name == "df_delay_tele_door" then
        CFG.delay_tele_door = math.max(300, tonumber(value) or 1500)
        persistConfig()
    elseif name == "df_pack_w" then
        CFG.storage_pack_world = tostring(value or ""):upper()
        persistConfig()
    elseif name == "df_pack_d" then
        CFG.storage_pack_door = tostring(value or "")
        persistConfig()
    elseif name == "df_btn_add_tool_direct" then
        local tWorld = tostring(CFG.storage_pack_world or ""):gsub("^%s+", ""):gsub("%s+$", "")
        local tDoor = tostring(CFG.storage_pack_door or ""):gsub("^%s+", ""):gsub("%s+$", "")
        local parsed = parseStorageBatchFromString(tWorld)
        if #parsed == 0 and tWorld ~= "" and tWorld ~= "EXIT" and tWorld ~= "0" then
            table.insert(parsed, { name = tWorld:upper(), door = tDoor })
        end
        local added = 0
        for _, it in ipairs(parsed) do
            local d = (it.door and it.door ~= "") and it.door or tDoor
            local exists = false
            for _, ex in ipairs(CFG.storage_tool_list or {}) do
                if ex.name == it.name then exists = true; break end
            end
            if not exists then
                table.insert(CFG.storage_tool_list, { name = it.name, door = d })
                added = added + 1
            end
        end
        if added > 0 then
            CFG.storage_pack_world = CFG.storage_tool_list[1].name
            CFG.storage_pack_door = CFG.storage_tool_list[1].door or ""
            persistConfig()
            if updateToolStorageDisplayList then pcall(updateToolStorageDisplayList) end
            if sendNotification then pcall(sendNotification, string.format("%d Gudang Alat ditambahkan! (Total: %d)", added, #(CFG.storage_tool_list or {}))) end
        else
            if sendNotification then pcall(sendNotification, "Isi Nama World Storage Alat terlebih dulu!") end
        end
    elseif name == "df_btn_manage_tools" or name == "df_tool_storage_list" then
        openUnifiedToolManager()
    elseif name == "df_btn_clear_tool_direct" then
        CFG.storage_tool_list = {}
        CFG.storage_pack_world = ""
        CFG.storage_pack_door = ""
        persistConfig()
        if updateToolStorageDisplayList then pcall(updateToolStorageDisplayList) end
        if sendNotification then pcall(sendNotification, "Daftar Gudang Alat dikosongkan!") end
    elseif name == "df_seed_w" then
        CFG.storage_seed_world = tostring(value or ""):upper()
        persistConfig()
    elseif name == "df_seed_d" then
        CFG.storage_seed_door = tostring(value or "")
        persistConfig()
    elseif name == "df_btn_add_seed_direct" then
        local sWorld = tostring(CFG.storage_seed_world or ""):gsub("^%s+", ""):gsub("%s+$", "")
        local sDoor = tostring(CFG.storage_seed_door or ""):gsub("^%s+", ""):gsub("%s+$", "")
        local parsed = parseStorageBatchFromString(sWorld)
        if #parsed == 0 and sWorld ~= "" and sWorld ~= "EXIT" and sWorld ~= "0" then
            table.insert(parsed, { name = sWorld:upper(), door = sDoor })
        end
        local added = 0
        for _, it in ipairs(parsed) do
            local d = (it.door and it.door ~= "") and it.door or sDoor
            local exists = false
            for _, ex in ipairs(CFG.storage_seed_list or {}) do
                if ex.name == it.name then exists = true; break end
            end
            if not exists then
                table.insert(CFG.storage_seed_list, { name = it.name, door = d })
                added = added + 1
            end
        end
        if added > 0 then
            CFG.storage_seed_world = CFG.storage_seed_list[1].name
            CFG.storage_seed_door = CFG.storage_seed_list[1].door or ""
            persistConfig()
            if updateSeedStorageDisplayList then pcall(updateSeedStorageDisplayList) end
            if sendNotification then pcall(sendNotification, string.format("%d Gudang Seed ditambahkan! (Total: %d)", added, #(CFG.storage_seed_list or {}))) end
        else
            if sendNotification then pcall(sendNotification, "Isi Nama World Storage Seed terlebih dulu!") end
        end
    elseif name == "df_btn_manage_seeds" or name == "df_seed_storage_list" then
        openUnifiedSeedManager()
    elseif name == "df_btn_clear_seed_direct" then
        CFG.storage_seed_list = {}
        CFG.storage_seed_world = ""
        CFG.storage_seed_door = ""
        persistConfig()
        if updateSeedStorageDisplayList then pcall(updateSeedStorageDisplayList) end
        if sendNotification then pcall(sendNotification, "Daftar Gudang Seed dikosongkan!") end
    elseif name == "df_seed_thresh" then
        CFG.save_seed_threshold = tonumber(value) or 180
        persistConfig()
    elseif name == "df_save_dirt" then
        CFG.save_dirt_seed = toBoolVal(value)
        persistConfig()
    elseif name == "df_save_cave" then
        CFG.save_cave_seed = toBoolVal(value)
        persistConfig()
    elseif name == "df_save_lava" then
        CFG.save_lava_seed = toBoolVal(value)
        persistConfig()
    elseif name == "df_save_rock" then
        CFG.save_rock_seed = toBoolVal(value)
        persistConfig()
    elseif name == "df_save_lava_block" then
        CFG.save_lava_block = toBoolVal(value)
        persistConfig()
    elseif name == "df_use_custom_save" then
        CFG.use_custom_save = toBoolVal(value)
        persistConfig()
    elseif name == "df_pick_save_item" then
        if not value or value == "" or value == 0 or value == "0" then return end
        local num = resolvePickedItemID(value)
        if num and num > 0 and CFG.custom_save_itemid ~= num then
            CFG.custom_save_itemid = num
            CFG.use_custom_save = true
            persistConfig()
            if editToggle then pcall(editToggle, "df_use_custom_save", true) end
            if sendNotification then pcall(sendNotification, string.format("Item Save: %s (BP: %d)", resolveItemName(num), getInvCount(num))) end
        end
    elseif name == "df_btn_test_drop" then
        testDropCustomSaveItem()
    elseif name == "df_auto_collect" then
        CFG.auto_collect = toBoolVal(value)
    elseif name == "df_collect_range" then
        CFG.collect_range = tonumber(value) or 3
    elseif name == "df_auto_reconnect" then
        CFG.auto_reconnect = toBoolVal(value)
    elseif name == "df_anti_lava" then
        CFG.use_anti_lava = toBoolVal(value)
    elseif name == "df_modfly" then
        CFG.use_modfly = toBoolVal(value)
    elseif name == "df_clear_sides" then
        CFG.clear_sides = toBoolVal(value)
    elseif name == "df_delay_sides" then
        CFG.delay_clear_sides = math.max(0, tonumber(value) or 120)
    elseif name == "df_break_3_mode" then
        CFG.break_3_mode = toBoolVal(value)
    elseif name == "df_break_cave" then
        CFG.break_cave_bg = toBoolVal(value)
    elseif name == "df_break_lava" then
        CFG.break_lava = toBoolVal(value)
    elseif name == "df_break_rock" then
        CFG.break_rock = toBoolVal(value)
    elseif name == "df_build_upper" then
        CFG.build_upper = toBoolVal(value)
    elseif name == "df_auto_farm" then
        CFG.auto_farm_dirt = toBoolVal(value)
    elseif name == "df_max_plant_dirt" then
        CFG.max_plant_dirt = math.max(1, math.min(98, math.floor(tonumber(value) or 50)))
    elseif name == "df_use_platform" then
        CFG.use_platform = toBoolVal(value)
        persistConfig()
    elseif name == "df_pick_platform" then
        if not value or value == "" or value == 0 or value == "0" then return end
        local num = resolvePickedItemID(value)
        if num and num > 0 and CFG.platform_itemid ~= num then
            CFG.platform_itemid = num
            persistConfig()
            if sendNotification then pcall(sendNotification, "Platform: " .. resolveItemName(num)) end
        end
    elseif name == "df_plat_left" then
        CFG.plat_left = toBoolVal(value)
        persistConfig()
    elseif name == "df_plat_right" then
        CFG.plat_right = toBoolVal(value)
        persistConfig()
    elseif name == "df_auto_trash" then
        CFG.auto_trash_junk = toBoolVal(value)
        persistConfig()
    elseif name == "df_trash_thresh" then
        CFG.trash_threshold = math.max(10, math.min(200, math.floor(tonumber(value) or 150)))
        persistConfig()
    elseif name == "df_pick_trash_item" then
        if not value or value == "" or value == 0 or value == "0" then return end
        local num = resolvePickedItemID(value)
        if num and num > 0 and CFG.trash_picker_itemid ~= num then
            CFG.trash_picker_itemid = num
            persistConfig()
            if sendNotification then pcall(sendNotification, "Item Trash dipilih: " .. resolveItemName(num)) end
        end
    elseif name == "df_btn_add_trash" then
        local list = getConfiguredTrashItemList()
        local id = tonumber(CFG.trash_picker_itemid) or 0
        if id > 0 then
            local exists = false
            for _, v in ipairs(list) do if v == id then exists = true; break end end
            if not exists then table.insert(list, math.floor(id)) end
            setTrashListFromTable(list)
            if updateTrashDisplayList then pcall(updateTrashDisplayList) end
            if sendNotification then pcall(sendNotification, "Ditambah ke List Trash: " .. resolveItemName(id)) end
        end
    elseif name == "df_btn_rem_trash" then
        local list = getConfiguredTrashItemList()
        local id = tonumber(CFG.trash_picker_itemid) or 0
        local nextList = {}
        for _, v in ipairs(list) do if v ~= id then table.insert(nextList, v) end end
        setTrashListFromTable(nextList)
        if updateTrashDisplayList then pcall(updateTrashDisplayList) end
        if sendNotification then pcall(sendNotification, "Dihapus dari List Trash: " .. resolveItemName(id)) end
    elseif name == "df_btn_reset_trash" then
        CFG.trash_list_str = "4,14,10"
        if updateTrashDisplayList then pcall(updateTrashDisplayList) end
        if sendNotification then pcall(sendNotification, "List Trash direset ke default (Lava, Cave, Rock)!") end
    elseif name == "df_btn_view_trash" then
        ensureRuntimeHooks()
        if not openTrashListManagerDialog() then
            if sendNotification then pcall(sendNotification, "Masuk ke world dulu untuk membuka List Trash!") end
        end
    elseif name == "df_delay_break" then
        CFG.delay_break = tonumber(value) or 180
        persistConfig()
    elseif name == "df_delay_place" then
        CFG.delay_place = tonumber(value) or 160
        persistConfig()
    elseif name == "df_delay_walk" then
        CFG.delay_walk = tonumber(value) or 250
        persistConfig()
    elseif name == "df_delay_warp" then
        CFG.delay_warp = tonumber(value) or 4500
        persistConfig()
    elseif name == "df_mini_console" then
        STATE.show_mini_console = toBoolVal(value)
    elseif name == "df_console_err_only" then
        STATE.console_errors_only = toBoolVal(value)
    elseif name == "df_btn_open_console" then
        ensureRuntimeHooks()
        openMiniConsoleDialog(STATE.console_errors_only)
    elseif name == "df_btn_clear_console" then
        STATE.logs = {}
        STATE.error_logs = {}
        STATE.error_count = 0
        if sendNotification then pcall(sendNotification, "Log & Error dibersihkan!") end
    elseif name == "df_btn_refresh_bag" then
        refreshInventorySnapshot()
        updateBagDisplayList()
        updateLogDisplayList()
        updatePowerStatusList()
        if sendNotification then pcall(sendNotification, "Isi backpack diperbarui!") end
    end

    if name:sub(1, 3) == "df_" then
        persistConfig()
    end
end

function OnValue(vtype, name, value)
    local ok, err = pcall(handleUIValue, vtype, name, value)
    if not ok then
        addLog("[Boren DF UI Err] " .. tostring(err))
    end
end

-- Alias camelCase & PascalCase untuk OnValue
onValue = OnValue

-- Mini Console ImGui (hanya muncul bila toggle 'Tampilkan Mini Console' dinyalakan)
function onDrawImGui()
    if (not STATE.show_mini_console) or (not ImGui) then
        return
    end
    pcall(function()
        if ImGui.SetNextWindowSize and ImVec2 then
            local cond = (ImGui.Cond and ImGui.Cond.FirstUseEver) or 4
            ImGui.SetNextWindowSize(ImVec2(380, 260), cond)
        end
        local openWin = ImGui.Begin("Boren DF - Mini Console (Cek Error)")
        if openWin then
            local statusCol = STATE.reconnecting and "[WAIT ONLINE] " or (STATE.running and "[AKTIF] " or "[STOP] ")
            ImGui.Text(string.format("%sStep: %s | World: %s", statusCol, tostring(STATE.current_step), tostring(STATE.current_world)))
            ImGui.Text(string.format("DF Selesai: %d | Total Error/Warn: %d", tonumber(STATE.worlds_completed) or 0, tonumber(STATE.error_count) or 0))
            if ImGui.Button(STATE.console_errors_only and "Mode: Error Saja" or "Mode: Semua Log") then
                STATE.console_errors_only = not STATE.console_errors_only
                if editToggle then pcall(editToggle, "df_console_err_only", STATE.console_errors_only) end
            end
            if ImGui.SameLine then ImGui.SameLine() end
            if ImGui.Button("Clear") then
                STATE.logs = {}
                STATE.error_logs = {}
                STATE.error_count = 0
            end
            if ImGui.SameLine then ImGui.SameLine() end
            if ImGui.Button("Tutup") then
                STATE.show_mini_console = false
                if editToggle then pcall(editToggle, "df_mini_console", false) end
            end
            if ImGui.Separator then ImGui.Separator() end
            local list = STATE.console_errors_only and STATE.error_logs or STATE.logs
            if #list == 0 then
                ImGui.TextWrapped(STATE.console_errors_only and "Tidak ada error tercatat." or "Belum ada log aktivitas.")
            else
                for i = 1, math.min(12, #list) do
                    ImGui.TextWrapped(tostring(list[i]))
                end
            end
        end
        ImGui.End()
    end)
end
OnDrawImGui = onDrawImGui

-- Registrasi UI "Boren Store" saat script di-load
registerNativeBorenStoreUI()
updatePowerStatusList()
updateTrashDisplayList()
updateToolStorageDisplayList()
updateSeedStorageDisplayList()

-- Daftarkan setOnValue untuk semua alias UI agar tombol/input merespons di semua versi Growlauncher
local ALL_UI_ALIASES = {
    "df_run_power", "df_btn_stop_df", "df_pause_toggle",
    "df_manual_world_input", "df_manual_door_input",
    "df_btn_add_world", "df_btn_add_cur_world", "df_btn_paste_worlds", "df_btn_copy_all_worlds", "df_btn_clear_worlds", "df_btn_view_worlds",
    "df_world_file", "df_btn_browse_files", "df_file_info_list", "df_btn_save_worlds", "df_btn_load_worlds",
    "df_world_random", "df_random_target", "df_random_len", "df_random_num",
    "df_ignore_lock", "df_use_wl", "df_wl_public",
    "df_use_sl", "df_sl_ignore", "df_sl_public",
    "df_use_jammer", "df_use_id_door", "df_pick_id_door", "df_input_id_door", "df_door_id", "df_door_label", "df_delay_tele_door",
    "df_use_blocker", "df_pick_blocker", "df_input_blocker",
    "df_pack_w", "df_pack_d", "df_btn_add_tool_direct", "df_btn_manage_tools", "df_btn_clear_tool_direct", "df_tool_storage_list",
    "df_seed_w", "df_seed_d", "df_btn_add_seed_direct", "df_btn_manage_seeds", "df_btn_clear_seed_direct", "df_seed_storage_list", "df_seed_thresh",
    "df_save_dirt", "df_save_cave", "df_save_lava", "df_save_rock", "df_save_lava_block",
    "df_use_custom_save", "df_pick_save_item", "df_btn_test_drop",
    "df_auto_collect", "df_collect_range", "df_auto_reconnect", "df_anti_lava", "df_modfly",
    "df_clear_sides", "df_delay_sides", "df_break_3_mode", "df_break_cave", "df_break_lava", "df_break_rock",
    "df_build_upper", "df_auto_farm", "df_max_plant_dirt",
    "df_use_platform", "df_pick_platform", "df_plat_left", "df_plat_right",
    "df_auto_trash", "df_trash_thresh", "df_pick_trash_item", "df_btn_add_trash", "df_btn_rem_trash", "df_btn_view_trash", "df_btn_reset_trash",
    "df_delay_break", "df_delay_place", "df_delay_walk", "df_delay_warp",
    "df_mini_console", "df_console_err_only", "df_btn_open_console", "df_btn_clear_console",
    "df_btn_refresh_bag",
}

if setOnValue then
    for _, aliasName in ipairs(ALL_UI_ALIASES) do
        pcall(setOnValue, aliasName, function(a1, a2, a3)
            if a2 == aliasName then
                OnValue(a1, a2, a3)
            elseif a1 == aliasName then
                OnValue(0, a1, a2)
            else
                OnValue(0, aliasName, a1)
            end
        end)
    end
end

-- Daftarkan hook onvalue (sesuai docs/hooks/index.md: addHook lalu applyHook)
if addHook then
    pcall(addHook, onValue, "onvalue")
end
if applyHook then
    pcall(applyHook)
end

if sendNotification then
    pcall(sendNotification, "Boren Store Auto DF siap!")
end

_G.findWorldObjectsByItemID = findWorldObjectsByItemID
_G.getInvCount = getInvCount
_G.ITEM = ITEM
_G.resolveItemName = resolveItemName
_G.lookupItemIDByName = lookupItemIDByName
_G.inspectWorldSecurityState = inspectWorldSecurityState
_G.setupWorldLocks = setupWorldLocks
_G.isProtectedEnclosure = isProtectedEnclosure
_G.isInSecurityMoat = isInSecurityMoat
_G.acquireTargetWorld = acquireTargetWorld
_G.openUnifiedToolManager = openUnifiedToolManager
_G.openUnifiedSeedManager = openUnifiedSeedManager
_G.parseStorageBatchFromString = parseStorageBatchFromString
_G.ensureToolsFromStorage = ensureToolsFromStorage
_G.saveSeedsToStorage = saveSeedsToStorage
_G.updateToolStorageDisplayList = updateToolStorageDisplayList
_G.updateSeedStorageDisplayList = updateSeedStorageDisplayList
_G.onSendPacketDialogHook = onSendPacketDialogHook

_G.CFG = CFG
_G.STATE = STATE
