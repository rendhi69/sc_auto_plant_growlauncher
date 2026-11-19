-- ============================================================================
-- BOREN HUB IMGUI - MODUL AUTO TRANSFER PRO (MOVE, AUTO VEND & RESTOCK)
-- File: imgui_hub/mod_transfer.lua
-- Fitur:
--   1. Mode Move (Enable ON, Vend OFF, Restock OFF) -> Pindah item dari Input ke Output World
--   2. Mode Auto Vend (Enable ON, Auto Vend ON) -> Deteksi vend, cek harga, beli & drop
--   3. Mode Restock (Enable ON, Restock ON) -> Ambil item dari Input World lalu restock vend di Output World (hingga 5.000 / 5k item)
--   4. Opsi Per Item (ON = X WL per item, OFF = X item per 1 WL)
--   5. Opsi Vertical (ON = pola kolom vertikal atas-bawah, OFF = pola horizontal kiri-kanan)
--   6. Anti-Scam & Validasi ID Ketat sebelum Buy
--   7. Format Input & Output World: WORLD atau WORLD:DOOR
--   8. Kuota & Budget Limit (Max item / Max WL)
-- ============================================================================

local TF = {
    id      = "transfer",
    label   = "Transfer",
    VERSION = "1.0.0",
    META    = {
        type    = "boren_gl_feature",
        id      = "transfer",
        label   = "Transfer",
        order   = 18,
        enabled = true,
    },
}

TF.CFG = {
    -- Top Checkboxes (Sesuai Gambar)
    enabled          = false,       -- Master switch
    auto_vend        = false,       -- Auto Buy dari Vend
    restock          = false,       -- Auto Restock ke Vend
    per_item         = false,       -- false = X item / 1 WL, true = X WL / item
    vertical         = false,       -- false = Horizontal row-first, true = Vertical col-first

    -- Form Nilai Item (Sesuai Gambar)
    item_id          = 4584,        -- Item ID target (contoh: 4584 Pepper Tree Block)
    item_price       = 0,           -- Item Price (referensi harga jual)
    item_buy_price   = 200,         -- Item Buy Price (batas harga beli)

    -- World Input/Output (Sesuai Gambar, support WORLD:DOOR)
    input_world_raw  = "",          -- Input World [Required]
    output_world_raw = "",          -- Output World [Required]

    -- Fitur Tambahan & Keamanan
    vend_max_cap     = 5000,        -- Kapasitas maksimal vend Growtopia = 5.000 (5k) item
    max_buy_quota    = 0,           -- Batas maksimal item yang dibeli (0 = unlimited)
    max_wl_budget    = 0,           -- Batas maksimal WL yang boleh dihabiskan (0 = unlimited)
    drop_batch       = 200,         -- Jumlah item per drop di output world
    step_delay       = 110,         -- ms delay langkah
    warp_delay       = 4500,        -- ms delay warp antar world
    vend_delay       = 250,         -- ms delay interaksi vend
    use_modfly       = true,        -- ModFly saat bergerak
    auto_collect     = true,        -- Auto collect item target
}

TF.STATE = {
    enabled          = false,
    running          = false,
    status_text      = "Idle",
    current_task     = "Standby",
    total_moved      = 0,
    total_bought     = 0,
    total_restocked  = 0,
    total_wl_spent   = 0,
    logs             = {},

    -- Cache Vend yang sudah full / kosong di world aktif
    full_vends       = {},          -- map [ "x,y" ] = true (sudah 5k)
    empty_vends      = {},          -- map [ "x,y" ] = true (stok habis)
    scam_vends       = {},          -- map [ "x,y" ] = true (harga/id tidak sesuai)

    -- Buffer UI
    active_sub       = "main",      -- "main" | "adv" | "logs"
    input_w_buf      = "",
    output_w_buf     = "",
    item_id_buf      = "4584",
    item_price_buf   = "0",
    buy_price_buf    = "200",
    max_quota_buf    = "0",
    max_budget_buf   = "0",

    -- Dialog Hook State
    pending_vend_x   = -1,
    pending_vend_y   = -1,
    last_dlg_text    = "",
    last_dlg_time    = 0,
}

local HUB_REF = nil
local CACHED_PATH = nil

-- Item Constants
local ITEM = {
    WL     = 242,
    DL     = 1796,
    BGL    = 7188,
    VEND   = 2978,
    DVEND  = 3234,
    CYVEND = 8898,
}

local VEND_FG_SET = {
    [2978] = true,
    [3234] = true,
    [8898] = true,
}

-- ============================================================================
-- 1. UTILITY & SAFE PATH DISCOVERY (ZERO HARDCODED PATHS)
-- ============================================================================
local function trimStr(s)
    return tostring(s or ""):match("^%s*(.-)%s*$") or ""
end

local function cleanWorldName(w)
    local s = trimStr(w):upper()
    return s:gsub("[^A-Z0-9_]", "")
end

local function parseWorldDoor(raw)
    local s = trimStr(raw):gsub("|", ":")
    if s == "" then return "", "" end
    local parts = {}
    for tok in s:gmatch("[^:]+") do
        table.insert(parts, trimStr(tok))
    end
    local w = cleanWorldName(parts[1] or "")
    local d = cleanWorldName(parts[2] or "")
    return w, d
end

local function getSafeStoragePath()
    if CACHED_PATH then return CACHED_PATH end
    local candidates = {
        "/storage/emulated/0/Android/media/launcher.powerkuy.growlauncher/ScriptLua/",
        "/storage/emulated/0/Android/data/launcher.powerkuy.growlauncher/files/ScriptLua/",
        "/storage/emulated/0/Download/",
        "script/",
        "",
    }
    for _, dir in ipairs(candidates) do
        local test = dir .. ".boren_tf_test"
        local ok, f = pcall(io.open, test, "w")
        if ok and f then
            f:write("ok")
            f:close()
            pcall(os.remove, test)
            CACHED_PATH = dir .. "boren_transfer_cfg.txt"
            return CACHED_PATH
        end
    end
    CACHED_PATH = "boren_transfer_cfg.txt"
    return CACHED_PATH
end

local function addLog(msg)
    local clean = tostring(msg or ""):gsub("`[0-9a-zA-Z!]", "")
    local ts = ""
    if os and os.date then
        local okD, d = pcall(os.date, "[%H:%M:%S] ")
        if okD and d then ts = d end
    end
    local entry = ts .. "[TRANSFER] " .. clean
    table.insert(TF.STATE.logs, 1, entry)
    if #TF.STATE.logs > 70 then table.remove(TF.STATE.logs) end
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
-- 2. PERSISTENCE (SAVE / LOAD DATA)
-- ============================================================================
function TF.saveData()
    local c = TF.CFG
    local lines = {
        "ENABLE="      .. (c.enabled and "1" or "0"),
        "AUTOVEND="    .. (c.auto_vend and "1" or "0"),
        "RESTOCK="     .. (c.restock and "1" or "0"),
        "PERITEM="     .. (c.per_item and "1" or "0"),
        "VERTICAL="    .. (c.vertical and "1" or "0"),
        "ITEMID="      .. tostring(c.item_id or 4584),
        "PRICE="       .. tostring(c.item_price or 0),
        "BUYPRICE="    .. tostring(c.item_buy_price or 200),
        "INPUTW="      .. tostring(c.input_world_raw or ""),
        "OUTPUTW="     .. tostring(c.output_world_raw or ""),
        "MAXCAP="      .. tostring(c.vend_max_cap or 5000),
        "MAXQUOTA="    .. tostring(c.max_buy_quota or 0),
        "MAXBUDGET="   .. tostring(c.max_wl_budget or 0),
        "DROPBATCH="   .. tostring(c.drop_batch or 200),
        "STEPDELAY="   .. tostring(c.step_delay or 110),
        "WARPDELAY="   .. tostring(c.warp_delay or 4500),
        "MODFLY="      .. (c.use_modfly and "1" or "0"),
        "ACOLLECT="    .. (c.auto_collect and "1" or "0"),
    }
    local ok, f = pcall(io.open, getSafeStoragePath(), "w")
    if ok and f then f:write(table.concat(lines, "\n")); f:close() end
end

function TF.loadData()
    local ok, f = pcall(io.open, getSafeStoragePath(), "r")
    if not ok or not f then return end
    local txt = f:read("*a"); f:close()
    if not txt or txt == "" then return end
    local c = TF.CFG
    for line in txt:gmatch("[^\r\n]+") do
        local k, v = line:match("^([A-Z]+)=(.*)$")
        if k == "ENABLE" then c.enabled = (v == "1")
        elseif k == "AUTOVEND" then c.auto_vend = (v == "1")
        elseif k == "RESTOCK" then c.restock = (v == "1")
        elseif k == "PERITEM" then c.per_item = (v == "1")
        elseif k == "VERTICAL" then c.vertical = (v == "1")
        elseif k == "ITEMID" then c.item_id = tonumber(v) or 4584
        elseif k == "PRICE" then c.item_price = tonumber(v) or 0
        elseif k == "BUYPRICE" then c.item_buy_price = tonumber(v) or 200
        elseif k == "INPUTW" then c.input_world_raw = trimStr(v)
        elseif k == "OUTPUTW" then c.output_world_raw = trimStr(v)
        elseif k == "MAXCAP" then c.vend_max_cap = tonumber(v) or 5000
        elseif k == "MAXQUOTA" then c.max_buy_quota = tonumber(v) or 0
        elseif k == "MAXBUDGET" then c.max_wl_budget = tonumber(v) or 0
        elseif k == "DROPBATCH" then c.drop_batch = tonumber(v) or 200
        elseif k == "STEPDELAY" then c.step_delay = tonumber(v) or 110
        elseif k == "WARPDELAY" then c.warp_delay = tonumber(v) or 4500
        elseif k == "MODFLY" then c.use_modfly = (v ~= "0")
        elseif k == "ACOLLECT" then c.auto_collect = (v ~= "0")
        end
    end

    -- Sync UI Buffers
    local st = TF.STATE
    st.input_w_buf    = c.input_world_raw
    st.output_w_buf   = c.output_world_raw
    st.item_id_buf    = tostring(c.item_id)
    st.item_price_buf = tostring(c.item_price)
    st.buy_price_buf  = tostring(c.item_buy_price)
    st.max_quota_buf  = tostring(c.max_buy_quota)
    st.max_budget_buf = tostring(c.max_wl_budget)
end

-- ============================================================================
-- 3. INVENTORY & GAME STATE HELPERS
-- ============================================================================
local function getInvCount(itemID)
    itemID = tonumber(itemID) or 0
    if itemID <= 0 then return 0 end
    if getInventory then
        local ok, inv = pcall(getInventory)
        if ok and type(inv) == "table" then
            for _, it in ipairs(inv) do
                if (it.id == itemID or it.item_id == itemID) then
                    return tonumber(it.amount or it.count) or 0
                end
            end
            for _, it in pairs(inv) do
                if type(it) == "table" and (it.id == itemID or it.item_id == itemID) then
                    return tonumber(it.amount or it.count) or 0
                end
            end
        end
    end
    if GetInventory then
        local ok, inv = pcall(GetInventory)
        if ok and type(inv) == "table" then
            for _, it in pairs(inv) do
                if type(it) == "table" and (it.id == itemID or it.item_id == itemID) then
                    return tonumber(it.amount or it.count) or 0
                end
            end
        end
    end
    return 0
end

local function getTotalWLs()
    local wls = getInvCount(ITEM.WL)
    local dls = getInvCount(ITEM.DL)
    local bgls = getInvCount(ITEM.BGL)
    return wls + (dls * 100) + (bgls * 10000)
end

local function getCurrentWorld()
    if getCurrentWorldName then
        local ok, w = pcall(getCurrentWorldName)
        if ok and type(w) == "string" and w ~= "" then return w:upper() end
    end
    if GetWorld then
        local ok, w = pcall(GetWorld)
        if ok and type(w) == "table" and w.name then return tostring(w.name):upper() end
    end
    return ""
end

local function getLocalPos()
    if getLocal then
        local ok, pl = pcall(getLocal)
        if ok and type(pl) == "table" then
            local x = tonumber(pl.pos_x or pl.x) or 0
            local y = tonumber(pl.pos_y or pl.y) or 0
            if x > 100 then x = math.floor(x / 32) end
            if y > 100 then y = math.floor(y / 32) end
            return x, y
        end
    end
    if GetLocal then
        local ok, pl = pcall(GetLocal)
        if ok and type(pl) == "table" then
            local x = tonumber(pl.pos_x or pl.x or pl.tileX) or 0
            local y = tonumber(pl.pos_y or pl.y or pl.tileY) or 0
            if x > 100 then x = math.floor(x / 32) end
            if y > 100 then y = math.floor(y / 32) end
            return x, y
        end
    end
    return 0, 0
end

local function findPathSafe(tx, ty)
    if not TF.STATE.running then return false end
    tx, ty = math.floor(tx), math.floor(ty)
    if tx < 0 then tx = 0 elseif tx > 99 then tx = 99 end
    if ty < 0 then ty = 0 elseif ty > 59 then ty = 59 end

    if TF.CFG.use_modfly and setModFly then pcall(setModFly, true) end

    if findPath then
        local ok = pcall(findPath, tx, ty)
        if ok then safeSleep(TF.CFG.step_delay or 110); return true end
    end
    if FindPath then
        local ok = pcall(FindPath, tx, ty)
        if ok then safeSleep(TF.CFG.step_delay or 110); return true end
    end
    return false
end

local function enterDoor(doorID)
    doorID = cleanWorldName(doorID)
    if doorID == "" then return true end
    safeSleep(150)
    if sendPacket then
        pcall(sendPacket, 2, "action|enter_door\ndoor_id|" .. doorID)
    end
    safeSleep(300)
    return true
end

local function warpTo(worldRaw)
    local wName, doorID = parseWorldDoor(worldRaw)
    if wName == "" then return false end
    if getCurrentWorld() == wName then
        if doorID ~= "" then enterDoor(doorID) end
        return true
    end

    addLog("Warp ke " .. wName .. (doorID ~= "" and (":" .. doorID) or "") .. "...")
    TF.STATE.status_text = "Warping " .. wName .. "..."

    for attempt = 1, 5 do
        if not TF.STATE.running then return false end
        if sendPacket then
            pcall(sendPacket, 3, "action|join_request\nname|" .. wName .. "\ninvitedWorld|0")
        elseif warp then
            pcall(warp, wName)
        end

        local waited = 0
        local targetWait = TF.CFG.warp_delay or 4500
        while waited < targetWait do
            if not TF.STATE.running then return false end
            safeSleep(200)
            waited = waited + 200
            if getCurrentWorld() == wName then
                safeSleep(800)
                if doorID ~= "" then enterDoor(doorID) end
                return true
            end
        end
    end
    return false
end

-- ============================================================================
-- 4. DROP & COLLECT ENGINE
-- ============================================================================
local function collectFloatingItem(targetID, maxRange)
    if not TF.STATE.running then return 0 end
    targetID = tonumber(targetID) or 0
    maxRange = tonumber(maxRange) or 3
    local collected = 0

    local objs = nil
    if getObjects then
        local ok, r = pcall(getObjects)
        if ok and type(r) == "table" then objs = r end
    end
    if (not objs) and GetObjects then
        local ok, r = pcall(GetObjects)
        if ok and type(r) == "table" then objs = r end
    end
    if type(objs) ~= "table" then return 0 end

    local myX, myY = getLocalPos()
    for _, o in pairs(objs) do
        if not TF.STATE.running then break end
        if type(o) == "table" then
            local oid = tonumber(o.id or o.item_id or o.itemID) or 0
            if targetID <= 0 or oid == targetID then
                local ox = tonumber(o.pos_x or o.x) or 0
                local oy = tonumber(o.pos_y or o.y) or 0
                if ox > 100 then ox = math.floor(ox / 32) end
                if oy > 100 then oy = math.floor(oy / 32) end

                if math.abs(ox - myX) <= maxRange and math.abs(oy - myY) <= maxRange then
                    if sendPacketRaw then
                        pcall(sendPacketRaw, {
                            type  = 11,
                            value = tonumber(o.uid or o.obj_id or o.oid) or 0,
                            x     = ox * 32,
                            y     = oy * 32,
                        })
                        collected = collected + 1
                    end
                end
            end
        end
    end
    return collected
end

local function dropItemSafe(itemID, amount)
    if not TF.STATE.running then return false end
    itemID = tonumber(itemID) or 0
    amount = tonumber(amount) or 0
    if itemID <= 0 or amount <= 0 then return false end

    local initial = getInvCount(itemID)
    if initial <= 0 then return false end
    local dropAmt = math.min(amount, math.min(200, initial))

    -- Metode 1: growtopia.confirmDropItem
    if growtopia and growtopia.confirmDropItem then
        pcall(growtopia.confirmDropItem, itemID, dropAmt)
        safeSleep(300)
    end
    -- Metode 2: Standard packet drop
    if sendPacket then
        pcall(sendPacket, 2, string.format("action|dialog_return\ndialog_name|drop_item\nitemID|%d|\ncount|%d\n", itemID, dropAmt))
        safeSleep(200)
        pcall(sendPacket, 2, string.format("action|dialog_return\ndialog_name|drop\nitemID|%d|\ncount|%d\n", itemID, dropAmt))
    end
    safeSleep(300)

    local after = getInvCount(itemID)
    if after < initial then
        local delta = initial - after
        TF.STATE.total_moved = TF.STATE.total_moved + delta
        addLog(string.format("Drop %d item (ID %d). Total moved: %d", delta, itemID, TF.STATE.total_moved))
        return true
    end
    return false
end

-- ============================================================================
-- 5. VEND INTERACTION ENGINE (BUY & RESTOCK)
-- ============================================================================
local function getTilesList()
    local list = {}
    if getTiles then
        local ok, r = pcall(getTiles)
        if ok and type(r) == "table" then list = r end
    end
    if (#list == 0) and GetTiles then
        local ok, r = pcall(GetTiles)
        if ok and type(r) == "table" then list = r end
    end
    return list
end

-- Cari semua vending machine di world aktif, urutkan sesuai toggle Vertical/Horizontal
local function findVendingTiles(isVertical)
    local vends = {}
    local tiles = getTilesList()
    for _, t in pairs(tiles) do
        if type(t) == "table" then
            local fg = tonumber(t.fg or t.foreground) or 0
            if VEND_FG_SET[fg] then
                local tx = tonumber(t.x or t.pos_x) or 0
                local ty = tonumber(t.y or t.pos_y) or 0
                table.insert(vends, { x = tx, y = ty, fg = fg })
            end
        end
    end

    if isVertical then
        -- Vertical: urut kolom demi kolom (atas ke bawah, lalu kolom sebelah)
        table.sort(vends, function(a, b)
            if a.x ~= b.x then return a.x < b.x end
            return a.y < b.y
        end)
    else
        -- Horizontal: urut baris demi baris (kiri ke kanan, lalu baris bawah)
        table.sort(vends, function(a, b)
            if a.y ~= b.y then return a.y < b.y end
            return a.x < b.x
        end)
    end
    return vends
end

local function wrenchTile(tx, ty)
    if not TF.STATE.running then return false end
    tx, ty = math.floor(tx), math.floor(ty)
    if wrench then
        pcall(wrench, tx, ty)
        return true
    end
    if sendPacketRaw then
        -- Send wrench / tool packet (type 3, value 32)
        pcall(sendPacketRaw, {
            type  = 3,
            value = 32,
            px    = tx,
            py    = ty,
            x     = tx * 32,
            y     = ty * 32,
        })
        return true
    end
    return false
end

local function punchTileWithItem(tx, ty, itemID)
    if not TF.STATE.running then return false end
    tx, ty = math.floor(tx), math.floor(ty)
    -- Di Growtopia, memukul vend sambil memegang item akan otomatis merestock vend tsb
    if sendPacketRaw then
        pcall(sendPacketRaw, {
            type  = 3,
            value = tonumber(itemID) or 18,
            px    = tx,
            py    = ty,
            x     = tx * 32,
            y     = ty * 32,
        })
        return true
    end
    return false
end

-- Hook Variant untuk menangkap OnDialogRequest dari Vending Machine
function TF.handleVariant(var)
    if not TF.STATE.running then return false end
    if type(var) ~= "table" then return false end
    local fn = tostring(var[0] or "")
    if fn ~= "OnDialogRequest" then return false end

    local payload = tostring(var[1] or "")
    if payload:find("vending", 1, true) or payload:find("vend", 1, true) then
        TF.STATE.last_dlg_text = payload
        TF.STATE.last_dlg_time = os and os.time and os.time() or 0
    end
    return false
end

-- ============================================================================
-- 6. CORE LOGIC RUNNER (3 MODES)
-- ============================================================================

-- MODE 1: PURE MOVE BLOCK / SEED (Input -> Output)
local function runMoveBlockEngine()
    addLog("`2[MODE 1] Move Item dimulai: " .. TF.CFG.input_world_raw .. " -> " .. TF.CFG.output_world_raw)
    local targetID = TF.CFG.item_id

    while TF.STATE.running do
        -- 1. Pergi ke Input World
        if not warpTo(TF.CFG.input_world_raw) then
            addLog("`4Gagal masuk Input World, coba lagi...")
            safeSleep(2000)
        else
            TF.STATE.status_text = "Scanning item di Input World..."
            safeSleep(800)

            -- Scan & ambil item target
            local objs = nil
            if getObjects then pcall(function() objs = getObjects() end) end
            if (not objs) and GetObjects then pcall(function() objs = GetObjects() end) end

            local foundAny = false
            local myBag = getInvCount(targetID)

            if type(objs) == "table" and myBag < 200 then
                for _, o in pairs(objs) do
                    if not TF.STATE.running then break end
                    if type(o) == "table" then
                        local oid = tonumber(o.id or o.item_id or o.itemID) or 0
                        if oid == targetID then
                            foundAny = true
                            local ox = tonumber(o.pos_x or o.x) or 0
                            local oy = tonumber(o.pos_y or o.y) or 0
                            if ox > 100 then ox = math.floor(ox / 32) end
                            if oy > 100 then oy = math.floor(oy / 32) end

                            TF.STATE.status_text = string.format("Mengambil item (%d,%d)...", ox, oy)
                            findPathSafe(ox, oy)
                            collectFloatingItem(targetID, 3)
                            safeSleep(150)
                            if getInvCount(targetID) >= 200 then break end
                        end
                    end
                end
            end

            myBag = getInvCount(targetID)
            if myBag <= 0 and not foundAny then
                addLog("`eSemua item target di Input World telah habis diambil!")
                TF.STATE.status_text = "Input World Kosong"
                break
            end

            -- 2. Jika tas berisi item, bawa ke Output World
            if myBag > 0 then
                TF.STATE.status_text = "Membawa " .. myBag .. " item ke Output World..."
                if warpTo(TF.CFG.output_world_raw) then
                    safeSleep(800)
                    -- Cari petak aman untuk drop (skip door spawn x=2)
                    local curX, curY = getLocalPos()
                    local dropX = (curX <= 3) and (curX + 3) or curX
                    local dropY = curY
                    findPathSafe(dropX, dropY)
                    safeSleep(200)

                    TF.STATE.status_text = "Dropping item..."
                    dropItemSafe(targetID, TF.CFG.drop_batch or 200)
                    safeSleep(300)
                end
            end
        end
        safeSleep(500)
    end
end

-- MODE 2: AUTO VEND (BUY & DROP)
local function runAutoVendBuyEngine()
    addLog("`2[MODE 2] Auto Vend Buy dimulai di " .. TF.CFG.input_world_raw)
    local targetID = TF.CFG.item_id
    local maxBuyPrice = TF.CFG.item_buy_price
    local isPerItem = TF.CFG.per_item

    while TF.STATE.running do
        -- Cek budget limit
        if TF.CFG.max_wl_budget > 0 and TF.STATE.total_wl_spent >= TF.CFG.max_wl_budget then
            addLog("`eBatas budget WL telah tercapai (" .. TF.STATE.total_wl_spent .. " WL). Berhenti.")
            break
        end
        if TF.CFG.max_buy_quota > 0 and TF.STATE.total_bought >= TF.CFG.max_buy_quota then
            addLog("`eBatas kuota pembelian tercapai (" .. TF.STATE.total_bought .. " item). Berhenti.")
            break
        end

        if not warpTo(TF.CFG.input_world_raw) then
            safeSleep(2000)
        else
            TF.STATE.status_text = "Memindai Vending Machine..."
            safeSleep(800)
            local vends = findVendingTiles(TF.CFG.vertical)
            local boughtInRound = 0

            for _, v in ipairs(vends) do
                if not TF.STATE.running then break end
                local key = v.x .. "," .. v.y
                if not TF.STATE.empty_vends[key] and not TF.STATE.scam_vends[key] then
                    -- Dekati vend
                    TF.STATE.status_text = string.format("Cek vend (%d,%d)...", v.x, v.y)
                    findPathSafe(v.x, v.y - 1)
                    safeSleep(TF.CFG.step_delay or 110)

                    -- Buka dialog vend
                    TF.STATE.last_dlg_text = ""
                    TF.STATE.pending_vend_x = v.x
                    TF.STATE.pending_vend_y = v.y
                    wrenchTile(v.x, v.y)
                    safeSleep(TF.CFG.vend_delay or 250)

                    -- Validasi teks dialog
                    local dlg = TF.STATE.last_dlg_text
                    if dlg ~= "" then
                        -- 1. Anti-scam: Cek apakah item_id cocok
                        local foundID = tonumber(dlg:match("embed_data|item_id|(%d+)") or dlg:match("embed_data|itemID|(%d+)"))
                        if foundID and foundID ~= targetID then
                            addLog(string.format("`4[ANTI-SCAM] Vend (%d,%d) menjual item ID %d (Bukan target %d)! Dilewati.", v.x, v.y, foundID, targetID))
                            TF.STATE.scam_vends[key] = true
                        else
                            -- 2. Cek stok
                            local stock = tonumber(dlg:match("embed_data|stock|(%d+)") or dlg:match("embed_data|count|(%d+)")) or 0
                            if stock <= 0 then
                                TF.STATE.empty_vends[key] = true
                            else
                                -- 3. Cek harga
                                local vPrice = tonumber(dlg:match("embed_data|price|(%d+)")) or 0
                                local vCount = tonumber(dlg:match("embed_data|count|(%d+)") or dlg:match("embed_data|item_count|(%d+)")) or 1

                                local priceOk = false
                                if isPerItem then
                                    -- Per item: harga harus <= maxBuyPrice WL
                                    if vPrice > 0 and vPrice <= maxBuyPrice then priceOk = true end
                                else
                                    -- X items / 1 WL: jumlah item per 1 WL harus >= maxBuyPrice
                                    if vCount >= maxBuyPrice then priceOk = true end
                                end

                                if priceOk then
                                    -- Beli dari vend
                                    addLog(string.format("Membeli item ID %d di vend (%d,%d)...", targetID, v.x, v.y))
                                    if sendPacket then
                                        pcall(sendPacket, 2, "action|dialog_return\ndialog_name|vending\nbuttonClicked|buy")
                                        safeSleep(300)
                                        pcall(sendPacket, 2, "action|dialog_return\ndialog_name|vend_buy\nbuttonClicked|buy")
                                        safeSleep(300)
                                        pcall(sendPacket, 2, "action|dialog_return\ndialog_name|vend_buy_check\nbuttonClicked|yes")
                                    end
                                    boughtInRound = boughtInRound + 1
                                    TF.STATE.total_bought = TF.STATE.total_bought + vCount
                                    TF.STATE.total_wl_spent = TF.STATE.total_wl_spent + math.max(1, vPrice)
                                else
                                    addLog(string.format("`6Harga vend (%d,%d) tidak sesuai budget. Dilewati.", v.x, v.y))
                                    TF.STATE.scam_vends[key] = true
                                end
                            end
                        end
                    end

                    -- Jika tas penuh, pergi ke Output World untuk drop
                    if getInvCount(targetID) >= 200 then
                        if warpTo(TF.CFG.output_world_raw) then
                            safeSleep(800)
                            local curX, curY = getLocalPos()
                            findPathSafe(curX + 3, curY)
                            dropItemSafe(targetID, 200)
                            safeSleep(300)
                            warpTo(TF.CFG.input_world_raw)
                            safeSleep(800)
                        end
                    end
                end
            end

            if boughtInRound == 0 then
                addLog("`eTidak ada lagi vend yang memenuhi kriteria harga/stok.")
                TF.STATE.status_text = "Semua Vend Selesai"
                break
            end
        end
        safeSleep(500)
    end
end

-- MODE 3: AUTO RESTOCK VEND (Input Storage -> Output Vend 5k Full)
local function runRestockEngine()
    addLog("`2[MODE 3] Auto Restock dimulai ke " .. TF.CFG.output_world_raw .. " (Target Max: 5.000 / 5k per vend)")
    local targetID = TF.CFG.item_id
    local maxCap = TF.CFG.vend_max_cap or 5000

    while TF.STATE.running do
        -- 1. Ambil item dari Input World jika tas kosong
        local myBag = getInvCount(targetID)
        if myBag < 100 then
            TF.STATE.status_text = "Mengambil stok di Input World..."
            if not warpTo(TF.CFG.input_world_raw) then
                safeSleep(2000)
            else
                safeSleep(800)
                collectFloatingItem(targetID, 4)
                safeSleep(300)
                myBag = getInvCount(targetID)
                if myBag <= 0 then
                    addLog("`eStok item di Input World telah habis!")
                    TF.STATE.status_text = "Stok Habis"
                    break
                end
            end
        end

        -- 2. Pergi ke Output World untuk mengisi vending machine
        if not warpTo(TF.CFG.output_world_raw) then
            safeSleep(2000)
        else
            TF.STATE.status_text = "Memindai Vending Machine toko..."
            safeSleep(800)
            local vends = findVendingTiles(TF.CFG.vertical)
            local restockedInRound = 0

            for _, v in ipairs(vends) do
                if not TF.STATE.running then break end
                local key = v.x .. "," .. v.y
                if not TF.STATE.full_vends[key] then
                    myBag = getInvCount(targetID)
                    if myBag <= 0 then break end -- Kembali ambil stok

                    TF.STATE.status_text = string.format("Restock vend (%d,%d)...", v.x, v.y)
                    findPathSafe(v.x, v.y - 1)
                    safeSleep(TF.CFG.step_delay or 110)

                    -- Pukul vend sambil memegang item untuk memasukkan stok
                    local before = getInvCount(targetID)
                    punchTileWithItem(v.x, v.y, targetID)
                    safeSleep(TF.CFG.vend_delay or 250)

                    -- Coba juga opsi dialog restock jika punch biasa tidak berkurang
                    local after = getInvCount(targetID)
                    if after == before then
                        wrenchTile(v.x, v.y)
                        safeSleep(200)
                        if sendPacket then
                            pcall(sendPacket, 2, "action|dialog_return\ndialog_name|vend_edit\nbuttonClicked|addstock")
                            pcall(sendPacket, 2, "action|dialog_return\ndialog_name|vending\nbuttonClicked|addstock")
                        end
                        safeSleep(250)
                        after = getInvCount(targetID)
                    end

                    if after < before then
                        local stocked = before - after
                        TF.STATE.total_restocked = TF.STATE.total_restocked + stocked
                        restockedInRound = restockedInRound + 1
                        addLog(string.format("Restock +%d item ke vend (%d,%d). Total: %d", stocked, v.x, v.y, TF.STATE.total_restocked))
                    else
                        -- Jika tas tidak berkurang sama sekali, vend kemungkinan besar sudah FULL 5k
                        TF.STATE.full_vends[key] = true
                        addLog(string.format("Vend (%d,%d) terdeteksi PENUH (5k limit). Menandai FULL.", v.x, v.y))
                    end
                end
            end

            if restockedInRound == 0 and myBag > 0 then
                addLog("`2Semua vending machine di Output World telah terisi PENUH (5.000 / 5k item)!")
                TF.STATE.status_text = "Semua Vend Full 5k"
                break
            end
        end
        safeSleep(500)
    end
end

local function mainTransferLoop()
    TF.STATE.running = true
    TF.STATE.enabled = true
    TF.STATE.status_text = "Running..."
    TF.STATE.full_vends  = {}
    TF.STATE.empty_vends = {}
    TF.STATE.scam_vends  = {}

    -- Tentukan mode berdasarkan kombinasi checkbox
    if TF.CFG.auto_vend then
        runAutoVendBuyEngine()
    elseif TF.CFG.restock then
        runRestockEngine()
    else
        runMoveBlockEngine()
    end

    TF.STATE.running = false
    TF.STATE.enabled = false
    TF.STATE.status_text = "Idle"
    TF.saveData()
    addLog("Transfer Bot selesai / berhenti.")
end

function TF.start()
    if TF.STATE.running then return false end
    if trimStr(TF.CFG.input_world_raw) == "" then
        addLog("`4Input World [Required] belum diisi!")
        return false
    end
    if trimStr(TF.CFG.output_world_raw) == "" then
        addLog("`4Output World [Required] belum diisi!")
        return false
    end
    TF.saveData()
    runAsync(mainTransferLoop)
    return true
end

function TF.stop()
    if not TF.STATE.running then
        TF.STATE.enabled = false
        return false
    end
    TF.STATE.running = false
    TF.STATE.enabled = false
    TF.STATE.status_text = "Stopping..."
    addLog("Menghentikan bot transfer...")
    return true
end

function TF.init(hub)
    HUB_REF = hub
    TF.loadData()
end

-- ============================================================================
-- 7. IMGUI UI RENDERER (IDENTIK DENGAN GAMBAR & STANDAR BOREN STORE)
-- ============================================================================
local function autoBtn(lbl)
    local ok, r = pcall(ImGui.Button, lbl)
    return ok and (r == true)
end

local function uiKit()
    return HUB_REF and HUB_REF.ui_kit or nil
end

local function uiGap(px)
    local k = uiKit()
    if k and k.gap then k.gap(px); return end
    if ImGui and ImGui.Spacing then pcall(ImGui.Spacing) end
end

local function uiSection(title, skipTop)
    local k = uiKit()
    if k and k.section then k.section(title, skipTop); return end
    if not skipTop then ImGui.Separator() end
    if title and title ~= "" then ImGui.Text(title) end
end

local function renderMainPanel()
    local c = TF.CFG
    local st = TF.STATE

    -- BARIS TOP CHECKBOXES (PERSIS GAMBAR)
    -- [ ] Enable   [ ] Auto Vend   [ ] Restock   [ ] Per Item   [ ] Vertical
    ImGui.Text("Pengaturan Mode:")
    uiGap(2)

    local chEn, vEn = ImGui.Checkbox("Enable##tf_en", c.enabled)
    if chEn then
        c.enabled = vEn
        if c.enabled then TF.start() else TF.stop() end
        TF.saveData()
    end
    ImGui.SameLine()

    local chAV, vAV = ImGui.Checkbox("Auto Vend##tf_av", c.auto_vend)
    if chAV then
        c.auto_vend = vAV
        if c.auto_vend then c.restock = false end -- Mutually exclusive
        TF.saveData()
    end
    ImGui.SameLine()

    local chRS, vRS = ImGui.Checkbox("Restock##tf_rs", c.restock)
    if chRS then
        c.restock = vRS
        if c.restock then c.auto_vend = false end
        TF.saveData()
    end
    ImGui.SameLine()

    local chPI, vPI = ImGui.Checkbox("Per Item##tf_pi", c.per_item)
    if chPI then c.per_item = vPI; TF.saveData() end
    ImGui.SameLine()

    local chVT, vVT = ImGui.Checkbox("Vertical##tf_vt", c.vertical)
    if chVT then c.vertical = vVT; TF.saveData() end

    uiGap(8)
    ImGui.Separator()
    uiGap(6)

    -- PENJELASAN MODE AKTIF
    local modeDesc = "Move Block/Seed (Input -> Output)"
    if c.auto_vend then
        modeDesc = "Auto Vend Buy (Beli dari Toko -> Drop di Output)"
    elseif c.restock then
        modeDesc = "Auto Restock (Input Storage -> Isi Vend 5k Toko)"
    end
    ImGui.Text("Mode Aktif: " .. modeDesc)
    ImGui.Text(string.format("Pola: %s   |   Hitungan: %s",
        c.vertical and "Vertical (Kolom Atas-Bawah)" or "Horizontal (Baris Kiri-Kanan)",
        c.per_item and "Per Item (X WL per 1 item)" or "Rate (X item per 1 WL)"))

    uiGap(8)
    ImGui.Separator()
    uiGap(6)

    -- FORM ANGKA DENGAN TOMBOL [-] [+] (PERSIS GAMBAR)

    -- 1. Item ID
    ImGui.Text("Item ID:")
    ImGui.PushItemWidth(140)
    local chIID, vIID = ImGui.InputText("##tf_iid", st.item_id_buf, 10)
    ImGui.PopItemWidth()
    if chIID then
        st.item_id_buf = vIID
        local n = tonumber(vIID)
        if n and n > 0 then c.item_id = math.floor(n); TF.saveData() end
    end
    ImGui.SameLine()
    if autoBtn(" - ##tf_iid_dec") then
        c.item_id = math.max(1, c.item_id - 1)
        st.item_id_buf = tostring(c.item_id)
        TF.saveData()
    end
    ImGui.SameLine()
    if autoBtn(" + ##tf_iid_inc") then
        c.item_id = c.item_id + 1
        st.item_id_buf = tostring(c.item_id)
        TF.saveData()
    end

    uiGap(4)

    -- 2. Item Price
    ImGui.Text("Item Price (Referensi):")
    ImGui.PushItemWidth(140)
    local chIP, vIP = ImGui.InputText("##tf_ip", st.item_price_buf, 10)
    ImGui.PopItemWidth()
    if chIP then
        st.item_price_buf = vIP
        local n = tonumber(vIP)
        if n and n >= 0 then c.item_price = math.floor(n); TF.saveData() end
    end
    ImGui.SameLine()
    if autoBtn(" - ##tf_ip_dec") then
        c.item_price = math.max(0, c.item_price - 1)
        st.item_price_buf = tostring(c.item_price)
        TF.saveData()
    end
    ImGui.SameLine()
    if autoBtn(" + ##tf_ip_inc") then
        c.item_price = c.item_price + 1
        st.item_price_buf = tostring(c.item_price)
        TF.saveData()
    end

    uiGap(4)

    -- 3. Item Buy Price
    ImGui.Text(c.per_item and "Item Buy Price (Max WL/item):" or "Item Buy Price (Min item/WL):")
    ImGui.PushItemWidth(140)
    local chIBP, vIBP = ImGui.InputText("##tf_ibp", st.buy_price_buf, 10)
    ImGui.PopItemWidth()
    if chIBP then
        st.buy_price_buf = vIBP
        local n = tonumber(vIBP)
        if n and n >= 0 then c.item_buy_price = math.floor(n); TF.saveData() end
    end
    ImGui.SameLine()
    if autoBtn(" - ##tf_ibp_dec") then
        c.item_buy_price = math.max(1, c.item_buy_price - (c.per_item and 1 or 10))
        st.buy_price_buf = tostring(c.item_buy_price)
        TF.saveData()
    end
    ImGui.SameLine()
    if autoBtn(" + ##tf_ibp_inc") then
        c.item_buy_price = c.item_buy_price + (c.per_item and 1 or 10)
        st.buy_price_buf = tostring(c.item_buy_price)
        TF.saveData()
    end

    uiGap(8)
    ImGui.Separator()
    uiGap(6)

    -- INPUT WORLD & OUTPUT WORLD (PERSIS GAMBAR)
    ImGui.Text("Input World [Required]:")
    ImGui.PushItemWidth(260)
    local chIW, vIW = ImGui.InputText("##tf_iw", st.input_w_buf, 30)
    ImGui.PopItemWidth()
    if chIW then
        st.input_w_buf = vIW
        c.input_world_raw = trimStr(vIW)
        TF.saveData()
    end
    ImGui.SameLine()
    if autoBtn("World Saat Ini##tf_cur_in") then
        local cw = getCurrentWorld()
        if cw ~= "" and cw ~= "EXIT" then
            c.input_world_raw = cw
            st.input_w_buf = cw
            TF.saveData()
        end
    end

    uiGap(4)

    ImGui.Text("Output World [Required]:")
    ImGui.PushItemWidth(260)
    local chOW, vOW = ImGui.InputText("##tf_ow", st.output_w_buf, 30)
    ImGui.PopItemWidth()
    if chOW then
        st.output_w_buf = vOW
        c.output_world_raw = trimStr(vOW)
        TF.saveData()
    end
    ImGui.SameLine()
    if autoBtn("World Saat Ini##tf_cur_out") then
        local cw = getCurrentWorld()
        if cw ~= "" and cw ~= "EXIT" then
            c.output_world_raw = cw
            st.output_w_buf = cw
            TF.saveData()
        end
    end

    uiGap(10)
    ImGui.Separator()
    uiGap(6)

    -- TOMBOL UTAMA START / STOP
    if st.running then
        if autoBtn(" ■ STOP BOT TRANSFER ##tf_stop") then
            TF.stop()
        end
    else
        if autoBtn(" ▶ START BOT TRANSFER ##tf_start") then
            TF.start()
        end
    end
    ImGui.SameLine()
    ImGui.Text("Status: " .. tostring(st.status_text))

    -- STATISTIK REAL-TIME
    uiGap(4)
    ImGui.Text(string.format("Statistik -> Moved: %d | Bought: %d (%d WL) | Restocked: %d (Max Cap: 5k)",
        st.total_moved, st.total_bought, st.total_wl_spent, st.total_restocked))
end

local function renderAdvPanel()
    local c = TF.CFG
    local st = TF.STATE

    uiSection("Pengaturan Lanjutan & Batas Keamanan", true)

    ImGui.Text("Target Batas Beli (Max Buy Quota, 0 = Tanpa Batas):")
    ImGui.PushItemWidth(140)
    local chQ, vQ = ImGui.InputText("##tf_quota", st.max_quota_buf, 10)
    ImGui.PopItemWidth()
    if chQ then
        st.max_quota_buf = vQ
        local n = tonumber(vQ)
        if n and n >= 0 then c.max_buy_quota = math.floor(n); TF.saveData() end
    end

    uiGap(4)
    ImGui.Text("Batas Maksimal Pengeluaran WL (Budget, 0 = Bebas):")
    ImGui.PushItemWidth(140)
    local chB, vB = ImGui.InputText("##tf_budget", st.max_budget_buf, 10)
    ImGui.PopItemWidth()
    if chB then
        st.max_budget_buf = vB
        local n = tonumber(vB)
        if n and n >= 0 then c.max_wl_budget = math.floor(n); TF.saveData() end
    end

    uiGap(4)
    ImGui.Text("Kapasitas Maksimal Vending Machine: " .. tostring(c.vend_max_cap) .. " item (5k)")
    ImGui.Text("Ukuran Batch Drop per Petak: " .. tostring(c.drop_batch) .. " item")

    uiGap(6)
    ImGui.Separator()
    uiGap(6)

    local chMF, vMF = ImGui.Checkbox("Gunakan ModFly saat Bergerak##tf_mf", c.use_modfly)
    if chMF then c.use_modfly = vMF; TF.saveData() end

    local chAC, vAC = ImGui.Checkbox("Auto Collect Item Target##tf_ac", c.auto_collect)
    if chAC then c.auto_collect = vAC; TF.saveData() end

    uiGap(4)
    ImGui.Text("Delay Langkah Bot : " .. tostring(c.step_delay) .. " ms")
    ImGui.SameLine()
    if autoBtn(" -20 ##tf_sd1") then c.step_delay = math.max(60, c.step_delay - 20); TF.saveData() end
    ImGui.SameLine()
    if autoBtn(" +20 ##tf_sd2") then c.step_delay = math.min(300, c.step_delay + 20); TF.saveData() end

    uiGap(2)
    ImGui.Text("Delay Warp World  : " .. tostring(c.warp_delay) .. " ms")
    ImGui.SameLine()
    if autoBtn(" -500 ##tf_wd1") then c.warp_delay = math.max(1500, c.warp_delay - 500); TF.saveData() end
    ImGui.SameLine()
    if autoBtn(" +500 ##tf_wd2") then c.warp_delay = math.min(10000, c.warp_delay + 500); TF.saveData() end
end

local function renderLogsPanel()
    local st = TF.STATE
    uiSection("Live Log Transfer", true)
    if autoBtn(" Bersihkan Log ##tf_clg") then st.logs = {} end
    ImGui.Separator()

    for i = 1, math.min(16, #st.logs) do
        if ImGui.TextWrapped then ImGui.TextWrapped(st.logs[i]) else ImGui.Text(st.logs[i]) end
    end
end

function TF.render(hub)
    HUB_REF = hub or HUB_REF
    local tabs = {
        { "main", "Transfer Panel" },
        { "adv",  "Advance & Budget" },
        { "logs", "Logs" },
    }
    for i, tb in ipairs(tabs) do
        if i > 1 then ImGui.SameLine() end
        local active = (TF.STATE.active_sub == tb[1])
        if autoBtn((active and "[ " or "  ") .. tb[2] .. (active and " ]" or "  ") .. "##tf_tab_" .. tb[1]) then
            TF.STATE.active_sub = tb[1]
        end
    end
    ImGui.Separator()

    if TF.STATE.active_sub == "main" then
        renderMainPanel()
    elseif TF.STATE.active_sub == "adv" then
        renderAdvPanel()
    else
        renderLogsPanel()
    end
end

return TF
