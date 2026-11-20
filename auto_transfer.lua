-- ============================================================================
-- AUTO TRANSFER PRO - BOREN STORE (GROWLAUNCHER STANDALONE)
-- File: auto_transfer.lua
-- Fitur:
--   1. Mode Move (Enable ON, Vend OFF, Restock OFF) -> Pindah item dari Multi Input ke Multi Output World
--   2. Mode Auto Vend (Enable ON, Auto Vend ON) -> Deteksi vend di Multi Input, cek harga, beli & drop di Multi Output
--   3. Mode Restock (Enable ON, Restock ON) -> Ambil item dari Multi Input World lalu restock vend di Multi Output World (hingga 5.000 / 5k item)
--   4. Multi-World Queue: Mendukung beberapa world dipisah koma (WORLD1|DOOR, WORLD2|DOOR) dengan queue manager & status antrian.
--   5. Toggle Per Item: ON = X WL / 1 item (<= item_buy_price WL), OFF = X items / 1 WL (>= item_buy_price)
--   6. Toggle Vertical: Scan & Drop urut vertikal (kolom atas-bawah) vs horizontal (baris kiri-kanan)
--   7. Proteksi Anti-Scam: Verifikasi kesesuaian item ID dan harga vending machine
--   8. Dual UI Interface: Standalone Dear ImGui window + Native Growlauncher 5-Tab Menu (/transfer)
-- ============================================================================

local TF = {}

TF.CFG = {
    -- Master Switch & Mode Toggles (Sesuai Gambar)
    enabled          = false,       -- Master switch (START / STOP)
    auto_vend        = false,       -- Auto Vend (Beli dari vend toko di input world)
    restock          = false,       -- Restock (Isi vend toko di output world hingga 5k)
    per_item         = false,       -- Per Item (ON = X WL/item, OFF = X item/1 WL)
    vertical         = false,       -- Vertical Traversal (ON = kolom, OFF = baris)

    -- Form Nilai Item (Sesuai Gambar)
    item_id          = 4584,        -- Item ID target (contoh: 4584 Pepper Tree Block)
    item_price       = 0,           -- Item Price (referensi harga jual)
    item_buy_price   = 200,         -- Item Buy Price (batas harga beli)

    -- World Input/Output (Mendukung Multi-World dipisah koma: WORLD1:DOOR, WORLD2:DOOR)
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

    -- Multi-World Queues
    input_queue      = {},          -- { { name="W", door="D", raw="W|D", status="Ready"|"Active"|"Done" }, ... }
    output_queue     = {},          -- { { name="W", door="D", raw="W|D", status="Ready"|"Active"|"Done" }, ... }
    input_idx        = 1,
    output_idx       = 1,
    show_input_queue = false,
    show_output_queue= false,

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

    -- Dialog Hook Capture
    last_dlg_text    = "",
    pending_vend_x   = -1,
    pending_vend_y   = -1,
}

local CACHED_PATH = nil

-- ============================================================================
-- 1. UTILITY & STRING HELPERS
-- ============================================================================
local function trimStr(s)
    return tostring(s or ""):match("^%s*(.-)%s*$") or ""
end

local function cleanWorldName(s)
    local c = trimStr(s):upper():gsub("[^A-Z0-9_]", "")
    return c
end

local function parseWorldEntry(raw)
    local s = trimStr(raw):gsub("|", ":")
    if s == "" or s:sub(1, 1) == "#" then return nil end
    local parts = {}
    for tok in s:gmatch("[^:]+") do
        table.insert(parts, trimStr(tok))
    end
    local w = cleanWorldName(parts[1] or "")
    if w == "" then return nil end
    local d = cleanWorldName(parts[2] or "")
    return {
        name   = w,
        door   = d,
        raw    = (d ~= "" and (w .. "|" .. d) or w),
        status = "Ready",
    }
end

local function parseWorldList(raw)
    local list = {}
    for tok in tostring(raw or ""):gmatch("[^,\r\n;]+") do
        local p = parseWorldEntry(tok)
        if p then table.insert(list, p) end
    end
    return list
end

local function formatWorldList(list)
    local parts = {}
    for _, item in ipairs(list or {}) do
        if type(item) == "table" and item.raw and item.raw ~= "" then
            table.insert(parts, item.raw)
        end
    end
    return table.concat(parts, ", ")
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
    if LogToConsole then pcall(LogToConsole, "`9[TRANSFER] `0" .. clean) end
end

local function safeSleep(ms)
    local d = tonumber(ms) or 100
    if Sleep then pcall(Sleep, d)
    elseif sleep then pcall(sleep, d) end
end

local function runAsync(fn)
    if run_coroutine then
        pcall(run_coroutine, fn)
    elseif runThread then
        pcall(runThread, fn)
    elseif task and task.spawn then
        pcall(task.spawn, fn)
    else
        local co = coroutine.create(fn)
        coroutine.resume(co)
    end
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

    -- Sync UI Buffers & Queues
    local st = TF.STATE
    st.input_w_buf    = c.input_world_raw
    st.output_w_buf   = c.output_world_raw
    st.input_queue    = parseWorldList(c.input_world_raw)
    st.output_queue   = parseWorldList(c.output_world_raw)
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
                    return tonumber(it.count or it.amount) or 0
                end
            end
        end
    end
    if inventory and inventory.getItemCount then
        local ok, cnt = pcall(inventory.getItemCount, itemID)
        if ok and tonumber(cnt) then return tonumber(cnt) end
    end
    if GetInventory then
        local ok, inv = pcall(GetInventory)
        if ok and type(inv) == "table" then
            for _, it in ipairs(inv) do
                if (it.id == itemID or it.item_id == itemID) then
                    return tonumber(it.count or it.amount) or 0
                end
            end
        end
    end
    return 0
end

local function getLocalPos()
    if GetLocal then
        local ok, me = pcall(GetLocal)
        if ok and me and me.pos_x and me.pos_y then
            return math.floor(me.pos_x / 32), math.floor(me.pos_y / 32)
        end
    end
    if getLocal then
        local ok, me = pcall(getLocal)
        if ok and me and me.posX and me.posY then
            return math.floor(me.posX / 32), math.floor(me.posY / 32)
        end
    end
    return 0, 0
end

local function getCurrentWorld()
    if GetWorld then
        local ok, w = pcall(GetWorld)
        if ok and w and w.name then return cleanWorldName(w.name) end
    end
    if getWorld then
        local ok, w = pcall(getWorld)
        if ok and w and w.name then return cleanWorldName(w.name) end
    end
    return ""
end

local function findPathSafe(tx, ty)
    if not TF.STATE.running then return false end
    if findPath then pcall(findPath, tx, ty)
    elseif FindPath then pcall(FindPath, tx, ty) end
    safeSleep(TF.CFG.step_delay or 110)
    return true
end

local function warpTo(worldRaw)
    local w, d = parseWorldDoor(worldRaw)
    if w == "" then return false end

    local cur = getCurrentWorld()
    if cur == w and d == "" then return true end

    local target = (d ~= "") and (w .. "|" .. d) or w
    addLog("Warp ke " .. target .. "...")
    TF.STATE.status_text = "Warping ke " .. target .. "..."

    if warp then pcall(warp, target)
    elseif Warp then pcall(Warp, target)
    elseif SendPacket then pcall(SendPacket, 3, "action|join_request\nname|" .. target .. "\ninvitedWorld|0")
    elseif sendPacket then pcall(sendPacket, 3, "action|join_request\nname|" .. target .. "\ninvitedWorld|0") end

    local startWait = os.time and os.time() or 0
    local timeout = (TF.CFG.warp_delay or 4500) / 1000 + 4
    while TF.STATE.running do
        safeSleep(500)
        local nw = getCurrentWorld()
        if nw == w then
            safeSleep(1000)
            return true
        end
        local now = os.time and os.time() or 0
        if (now - startWait) > timeout then
            addLog("`4Warp timeout ke " .. target)
            return false
        end
    end
    return false
end

-- ============================================================================
-- 4. DROP & COLLECT ENGINE
-- ============================================================================
local function collectFloatingItem(itemID, range)
    if not TF.STATE.running then return 0 end
    itemID = tonumber(itemID) or 0
    range = range or 2
    local px, py = getLocalPos()

    local objs = nil
    if getObjects then pcall(function() objs = getObjects() end) end
    if (not objs) and GetObjects then pcall(function() objs = GetObjects() end) end
    if type(objs) ~= "table" then return 0 end

    local collected = 0
    for _, o in pairs(objs) do
        if not TF.STATE.running then break end
        if type(o) == "table" then
            local oid = tonumber(o.id or o.item_id or o.itemID) or 0
            if oid == itemID or itemID == 0 then
                local ox = tonumber(o.pos_x or o.x) or 0
                local oy = tonumber(o.pos_y or o.y) or 0
                if ox > 100 then ox = math.floor(ox / 32) end
                if oy > 100 then oy = math.floor(oy / 32) end

                if math.abs(ox - px) <= range and math.abs(oy - py) <= range then
                    local uid = tonumber(o.uid or o.object_id or o.id) or 0
                    if collectObject then pcall(collectObject, uid)
                    elseif CollectObject then pcall(CollectObject, uid) end
                    collected = collected + 1
                    safeSleep(60)
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

local function isVendingMachine(itemID)
    itemID = tonumber(itemID) or 0
    return (itemID == 2978 or itemID == 3234 or itemID == 8898)
end

local function findVendingTiles(vertical)
    local tiles = getTilesList()
    local vends = {}
    for _, t in ipairs(tiles) do
        if type(t) == "table" then
            local fg = tonumber(t.fg or t.foreground) or 0
            if isVendingMachine(fg) then
                table.insert(vends, { x = t.x, y = t.y, fg = fg })
            end
        end
    end
    if vertical then
        table.sort(vends, function(a, b)
            if a.x == b.x then return a.y < b.y end
            return a.x < b.x
        end)
    else
        table.sort(vends, function(a, b)
            if a.y == b.y then return a.x < b.x end
            return a.y < b.y
        end)
    end
    return vends
end

local function wrenchTile(x, y)
    if not TF.STATE.running then return false end
    if wrench then pcall(wrench, x, y)
    elseif Wrench then pcall(Wrench, x, y)
    elseif sendPacketRaw then
        pcall(sendPacketRaw, false, { type = 7, value = 18, px = x * 32, py = y * 32, x = x * 32, y = y * 32 })
    end
    return true
end

local function punchTileWithItem(x, y, itemID)
    if not TF.STATE.running then return false end
    if punch then pcall(punch, x, y, itemID)
    elseif Punch then pcall(Punch, x, y)
    elseif placeTile then pcall(placeTile, x, y, itemID)
    elseif PlaceTile then pcall(PlaceTile, x, y, itemID) end
    return true
end

-- ============================================================================
-- 6. CORE LOGIC RUNNER (MULTI-WORLD & 3 MODES)
-- ============================================================================

-- MODE 1: PURE MOVE BLOCK / SEED (Multi-World Input -> Multi-World Output)
local function runMoveBlockEngine()
    local inQ  = TF.STATE.input_queue
    local outQ = TF.STATE.output_queue
    local targetID = TF.CFG.item_id

    addLog(string.format("`2[MODE 1] Move Item Multi-World: %d Input World -> %d Output World", #inQ, #outQ))

    while TF.STATE.running and TF.STATE.input_idx <= #inQ and TF.STATE.output_idx <= #outQ do
        local curIn  = inQ[TF.STATE.input_idx]
        local curOut = outQ[TF.STATE.output_idx]
        curIn.status  = "Active"
        curOut.status = "Active"

        -- 1. Pergi ke Input World aktif
        if not warpTo(curIn.raw) then
            addLog(string.format("`4Gagal masuk Input World: %s, coba lagi...", curIn.raw))
            safeSleep(2000)
        else
            TF.STATE.status_text = string.format("[%d/%d] Scan item di %s...", TF.STATE.input_idx, #inQ, curIn.name)
            safeSleep(800)

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

                            TF.STATE.status_text = string.format("[%d/%d] Ambil item (%d,%d) di %s...", TF.STATE.input_idx, #inQ, ox, oy, curIn.name)
                            findPathSafe(ox, oy)
                            collectFloatingItem(targetID, 3)
                            safeSleep(150)
                            if getInvCount(targetID) >= 200 then break end
                        end
                    end
                end
            end

            myBag = getInvCount(targetID)

            -- Jika tidak ada floating item lagi di Input World ini dan tas kosong
            if myBag <= 0 and not foundAny then
                addLog(string.format("`e[Multi World] Input World '%s' telah KOSONG!", curIn.name))
                curIn.status = "Done"
                TF.STATE.input_idx = TF.STATE.input_idx + 1
                if TF.STATE.input_idx <= #inQ then
                    addLog(string.format("`3[Multi World] Pindah ke Input World berikutnya (%d/%d): %s", TF.STATE.input_idx, #inQ, inQ[TF.STATE.input_idx].name))
                end
            end

            -- 2. Jika tas berisi item, bawa ke Output World aktif
            if myBag > 0 then
                TF.STATE.status_text = string.format("[%d/%d] Bawa %d item ke Output: %s...", TF.STATE.output_idx, #outQ, myBag, curOut.name)
                if warpTo(curOut.raw) then
                    safeSleep(800)
                    local curX, curY = getLocalPos()
                    local dropX = (curX <= 3) and (curX + 3) or curX
                    local dropY = curY
                    findPathSafe(dropX, dropY)
                    safeSleep(200)

                    TF.STATE.status_text = "Dropping item di " .. curOut.name .. "..."
                    local okDrop = dropItemSafe(targetID, TF.CFG.drop_batch or 200)
                    safeSleep(300)

                    if not okDrop and getInvCount(targetID) > 0 then
                        addLog(string.format("`e[Multi World] Output World '%s' gagal drop (Penuh/Batas). Pindah ke Output World berikutnya!", curOut.name))
                        curOut.status = "Done/Full"
                        TF.STATE.output_idx = TF.STATE.output_idx + 1
                        if TF.STATE.output_idx <= #outQ then
                            addLog(string.format("`3[Multi World] Pindah ke Output World (%d/%d): %s", TF.STATE.output_idx, #outQ, outQ[TF.STATE.output_idx].name))
                        end
                    end
                end
            end
        end
        safeSleep(500)
    end

    if TF.STATE.input_idx > #inQ then
        addLog("`2[Multi World] Semua Input World telah selesai dipindahkan (Semua Kosong)!")
        TF.STATE.status_text = "Semua Input World Selesai"
    elseif TF.STATE.output_idx > #outQ then
        addLog("`2[Multi World] Semua Output World telah terisi (Semua Selesai/Penuh)!")
        TF.STATE.status_text = "Semua Output World Selesai"
    end
end

-- MODE 2: AUTO VEND (BUY & DROP DENGAN MULTI-WORLD)
local function runAutoVendBuyEngine()
    local inQ  = TF.STATE.input_queue
    local outQ = TF.STATE.output_queue
    local targetID = TF.CFG.item_id
    local maxBuyPrice = TF.CFG.item_buy_price
    local isPerItem = TF.CFG.per_item

    addLog(string.format("`2[MODE 2] Auto Vend Buy Multi-World: %d Input World -> %d Output World", #inQ, #outQ))

    while TF.STATE.running and TF.STATE.input_idx <= #inQ and TF.STATE.output_idx <= #outQ do
        if TF.CFG.max_wl_budget > 0 and TF.STATE.total_wl_spent >= TF.CFG.max_wl_budget then
            addLog("`eBatas budget WL telah tercapai (" .. TF.STATE.total_wl_spent .. " WL). Berhenti.")
            break
        end
        if TF.CFG.max_buy_quota > 0 and TF.STATE.total_bought >= TF.CFG.max_buy_quota then
            addLog("`eBatas kuota pembelian tercapai (" .. TF.STATE.total_bought .. " item). Berhenti.")
            break
        end

        local curIn  = inQ[TF.STATE.input_idx]
        local curOut = outQ[TF.STATE.output_idx]
        curIn.status  = "Active"
        curOut.status = "Active"

        if not warpTo(curIn.raw) then
            safeSleep(2000)
        else
            TF.STATE.status_text = string.format("[%d/%d] Memindai Vend di %s...", TF.STATE.input_idx, #inQ, curIn.name)
            safeSleep(800)
            local vends = findVendingTiles(TF.CFG.vertical)
            local boughtInRound = 0

            for _, v in ipairs(vends) do
                if not TF.STATE.running then break end
                local key = v.x .. "," .. v.y
                if not TF.STATE.empty_vends[key] and not TF.STATE.scam_vends[key] then
                    TF.STATE.status_text = string.format("[%d/%d] Cek vend (%d,%d) di %s...", TF.STATE.input_idx, #inQ, v.x, v.y, curIn.name)
                    findPathSafe(v.x, v.y - 1)
                    safeSleep(TF.CFG.step_delay or 110)

                    TF.STATE.last_dlg_text = ""
                    TF.STATE.pending_vend_x = v.x
                    TF.STATE.pending_vend_y = v.y
                    wrenchTile(v.x, v.y)
                    safeSleep(TF.CFG.vend_delay or 250)

                    local dlg = TF.STATE.last_dlg_text
                    if dlg ~= "" then
                        local foundID = tonumber(dlg:match("embed_data|item_id|(%d+)") or dlg:match("embed_data|itemID|(%d+)"))
                        if foundID and foundID ~= targetID then
                            addLog(string.format("`4[ANTI-SCAM] Vend (%d,%d) menjual item ID %d (Bukan target %d)! Dilewati.", v.x, v.y, foundID, targetID))
                            TF.STATE.scam_vends[key] = true
                        else
                            local stock = tonumber(dlg:match("embed_data|stock|(%d+)") or dlg:match("embed_data|count|(%d+)")) or 0
                            if stock <= 0 then
                                TF.STATE.empty_vends[key] = true
                            else
                                local vPrice = tonumber(dlg:match("embed_data|price|(%d+)")) or 0
                                local vCount = tonumber(dlg:match("embed_data|count|(%d+)") or dlg:match("embed_data|item_count|(%d+)")) or 1

                                local priceOk = false
                                if isPerItem then
                                    if vPrice > 0 and vPrice <= maxBuyPrice then priceOk = true end
                                else
                                    if vCount >= maxBuyPrice then priceOk = true end
                                end

                                if priceOk then
                                    addLog(string.format("Membeli item ID %d di vend (%d,%d) %s...", targetID, v.x, v.y, curIn.name))
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
                        if warpTo(curOut.raw) then
                            safeSleep(800)
                            local curX, curY = getLocalPos()
                            findPathSafe(curX + 3, curY)
                            local okDrop = dropItemSafe(targetID, 200)
                            safeSleep(300)
                            if not okDrop and getInvCount(targetID) > 0 then
                                addLog(string.format("`e[Multi World] Output World '%s' penuh, pindah ke output berikutnya!", curOut.name))
                                curOut.status = "Done/Full"
                                TF.STATE.output_idx = TF.STATE.output_idx + 1
                                if TF.STATE.output_idx <= #outQ then
                                    curOut = outQ[TF.STATE.output_idx]
                                end
                            end
                            warpTo(curIn.raw)
                            safeSleep(800)
                        end
                    end
                end
            end

            if boughtInRound == 0 then
                addLog(string.format("`e[Multi World] Tidak ada lagi vend yang memenuhi kriteria di %s.", curIn.name))
                curIn.status = "Done"
                TF.STATE.input_idx = TF.STATE.input_idx + 1
                TF.STATE.empty_vends = {}
                TF.STATE.scam_vends  = {}
                if TF.STATE.input_idx <= #inQ then
                    addLog(string.format("`3[Multi World] Beralih ke Input World (%d/%d): %s", TF.STATE.input_idx, #inQ, inQ[TF.STATE.input_idx].name))
                end
            end
        end
        safeSleep(500)
    end

    local sisa = getInvCount(targetID)
    if sisa > 0 and TF.STATE.output_idx <= #outQ then
        local curOut = outQ[TF.STATE.output_idx]
        if warpTo(curOut.raw) then
            safeSleep(800)
            local curX, curY = getLocalPos()
            findPathSafe(curX + 3, curY)
            dropItemSafe(targetID, sisa)
            safeSleep(300)
        end
    end
end

-- MODE 3: AUTO RESTOCK VEND (MULTI-WORLD INPUT STORAGE -> MULTI-WORLD OUTPUT VEND 5K FULL)
local function runRestockEngine()
    local inQ  = TF.STATE.input_queue
    local outQ = TF.STATE.output_queue
    local targetID = TF.CFG.item_id
    local maxCap = TF.CFG.vend_max_cap or 5000

    addLog(string.format("`2[MODE 3] Auto Restock Multi-World: %d Input Storage -> %d Output Toko (Target Max: 5.000 / 5k per vend)", #inQ, #outQ))

    while TF.STATE.running and TF.STATE.input_idx <= #inQ and TF.STATE.output_idx <= #outQ do
        local curIn  = inQ[TF.STATE.input_idx]
        local curOut = outQ[TF.STATE.output_idx]
        curIn.status  = "Active"
        curOut.status = "Active"

        -- 1. Ambil stok dari curIn jika tas kurang dari 100
        local myBag = getInvCount(targetID)
        if myBag < 100 then
            TF.STATE.status_text = string.format("[%d/%d] Ambil stok di %s...", TF.STATE.input_idx, #inQ, curIn.name)
            if not warpTo(curIn.raw) then
                safeSleep(2000)
            else
                safeSleep(800)
                collectFloatingItem(targetID, 4)
                safeSleep(300)
                myBag = getInvCount(targetID)
                if myBag <= 0 then
                    addLog(string.format("`e[Multi World] Stok di Input World '%s' telah HABIS!", curIn.name))
                    curIn.status = "Done/Empty"
                    TF.STATE.input_idx = TF.STATE.input_idx + 1
                    if TF.STATE.input_idx <= #inQ then
                        addLog(string.format("`3[Multi World] Pindah ambil stok di Input World (%d/%d): %s", TF.STATE.input_idx, #inQ, inQ[TF.STATE.input_idx].name))
                    else
                        addLog("`4[Multi World] Semua Input World kehabisan stok! Selesai.")
                        break
                    end
                end
            end
        end

        -- 2. Restock di curOut jika memiliki stok di tas
        myBag = getInvCount(targetID)
        if myBag > 0 then
            TF.STATE.status_text = string.format("[%d/%d] Isi Vend di %s...", TF.STATE.output_idx, #outQ, curOut.name)
            if not warpTo(curOut.raw) then
                safeSleep(2000)
            else
                safeSleep(800)
                local vends = findVendingTiles(TF.CFG.vertical)
                local restockedInRound = 0

                for _, v in ipairs(vends) do
                    if not TF.STATE.running then break end
                    local key = v.x .. "," .. v.y
                    if not TF.STATE.full_vends[key] then
                        myBag = getInvCount(targetID)
                        if myBag <= 0 then break end

                        TF.STATE.status_text = string.format("[%d/%d] Restock vend (%d,%d) di %s...", TF.STATE.output_idx, #outQ, v.x, v.y, curOut.name)
                        findPathSafe(v.x, v.y - 1)
                        safeSleep(TF.CFG.step_delay or 110)

                        local before = getInvCount(targetID)
                        punchTileWithItem(v.x, v.y, targetID)
                        safeSleep(TF.CFG.vend_delay or 250)

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
                            addLog(string.format("Restock +%d item ke vend (%d,%d) di %s. Total: %d", stocked, v.x, v.y, curOut.name, TF.STATE.total_restocked))
                        else
                            TF.STATE.full_vends[key] = true
                            addLog(string.format("Vend (%d,%d) di %s terdeteksi PENUH (5k limit). Menandai FULL.", v.x, v.y, curOut.name))
                        end
                    end
                end

                if restockedInRound == 0 and myBag > 0 then
                    addLog(string.format("`2[Multi World] Semua vend di '%s' telah PENUH 5.000 (5k)!", curOut.name))
                    curOut.status = "Done (5k Full)"
                    TF.STATE.output_idx = TF.STATE.output_idx + 1
                    TF.STATE.full_vends = {}
                    if TF.STATE.output_idx <= #outQ then
                        addLog(string.format("`3[Multi World] Beralih mengisi Output World berikutnya (%d/%d): %s", TF.STATE.output_idx, #outQ, outQ[TF.STATE.output_idx].name))
                    end
                end
            end
        end
        safeSleep(500)
    end

    if TF.STATE.output_idx > #outQ then
        addLog("`2[Multi World] Semua Output World telah terisi PENUH 5.000 (5k) item!")
        TF.STATE.status_text = "Semua Vend Toko Selesai (5k Full)"
    end
end

local function mainTransferLoop()
    TF.STATE.running = true
    TF.STATE.enabled = true
    TF.STATE.status_text = "Running..."
    TF.STATE.full_vends  = {}
    TF.STATE.empty_vends = {}
    TF.STATE.scam_vends  = {}

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
    local inQ  = parseWorldList(TF.CFG.input_world_raw)
    local outQ = parseWorldList(TF.CFG.output_world_raw)

    if #inQ == 0 then
        addLog("`4Input World [Required] belum diisi!")
        return false
    end
    if #outQ == 0 then
        addLog("`4Output World [Required] belum diisi!")
        return false
    end

    for _, w in ipairs(inQ) do w.status = "Ready" end
    for _, w in ipairs(outQ) do w.status = "Ready" end
    TF.STATE.input_queue  = inQ
    TF.STATE.output_queue = outQ
    TF.STATE.input_idx    = 1
    TF.STATE.output_idx   = 1

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

-- ============================================================================
-- 7. IMGUI UI RENDERER (STANDALONE WINDOW)
-- ============================================================================
local function autoBtn(lbl)
    local ok, r = pcall(ImGui.Button, lbl)
    return ok and (r == true)
end

local function uiGap(px)
    if ImGui and ImGui.Spacing then pcall(ImGui.Spacing) end
end

local function renderMainPanel()
    local c = TF.CFG
    local st = TF.STATE

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
        if c.auto_vend then c.restock = false end
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

    local availW = 500
    if ImGui and ImGui.GetContentRegionAvail then
        local okA, av = pcall(ImGui.GetContentRegionAvail)
        local ax = (type(av) == "number" and av) or (av and av.x) or 500
        if type(ax) == "number" and ax > 50 then availW = ax end
    end

    if availW >= 470 then
        ImGui.SameLine()
    end

    local chPI, vPI = ImGui.Checkbox("Per Item##tf_pi", c.per_item)
    if chPI then c.per_item = vPI; TF.saveData() end
    ImGui.SameLine()

    local chVT, vVT = ImGui.Checkbox("Vertical##tf_vt", c.vertical)
    if chVT then c.vertical = vVT; TF.saveData() end

    uiGap(8)
    ImGui.Separator()
    uiGap(6)

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

    -- Item ID
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

    -- Item Price
    ImGui.Text("Item Price:")
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

    -- Item Buy Price
    ImGui.Text("Item Buy Price:")
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

    -- INPUT WORLD (MULTI-WORLD)
    ImGui.Text("Input World [Required] (Bisa multi world dipisah koma):")
    ImGui.PushItemWidth(260)
    local chIW, vIW = ImGui.InputText("##tf_iw", st.input_w_buf, 1024)
    ImGui.PopItemWidth()
    if chIW then
        st.input_w_buf = vIW
        c.input_world_raw = trimStr(vIW)
        st.input_queue = parseWorldList(c.input_world_raw)
        TF.saveData()
    end
    ImGui.SameLine()
    if autoBtn("+ World Saat Ini##tf_cur_in") then
        local cw = getCurrentWorld()
        if cw ~= "" and cw ~= "EXIT" then
            if c.input_world_raw == "" then c.input_world_raw = cw
            else c.input_world_raw = c.input_world_raw .. ", " .. cw end
            st.input_w_buf = c.input_world_raw
            st.input_queue = parseWorldList(c.input_world_raw)
            TF.saveData()
        end
    end
    local availIW = 500
    if ImGui and ImGui.GetContentRegionAvail then
        local okA, av = pcall(ImGui.GetContentRegionAvail)
        local ax = (type(av) == "number" and av) or (av and av.x) or 500
        if type(ax) == "number" and ax > 50 then availIW = ax end
    end
    if availIW >= 460 then ImGui.SameLine() end
    local inCount = #st.input_queue
    if autoBtn(st.show_input_queue and "▲ Tutup Antrian##tf_inq_btn" or ("▼ Antrian (" .. inCount .. ")##tf_inq_btn")) then
        st.show_input_queue = not st.show_input_queue
    end

    if st.show_input_queue then
        ImGui.TextColored(0.4, 0.8, 1.0, 1.0, string.format("--- Daftar Antrian Input World (%d World) ---", inCount))
        if inCount == 0 then
            ImGui.Text("Belum ada Input World. Masukkan nama world di atas (pisahkan koma).")
        else
            for i, w in ipairs(st.input_queue) do
                local badge = (w.status == "Active") and "[PROSES]" or (w.status:match("^Done") and "[SELESAI]" or "[ANTRI]")
                ImGui.Text(string.format(" %d. %s  %s", i, w.raw, badge))
                ImGui.SameLine()
                if autoBtn("Hapus##del_in_" .. i) then
                    table.remove(st.input_queue, i)
                    c.input_world_raw = formatWorldList(st.input_queue)
                    st.input_w_buf = c.input_world_raw
                    TF.saveData()
                    break
                end
            end
            if autoBtn("↺ Reset Status Antrian Input##reset_in_status") then
                for _, w in ipairs(st.input_queue) do w.status = "Ready" end
                st.input_idx = 1
            end
        end
        uiGap(4)
    end

    uiGap(6)

    -- OUTPUT WORLD (MULTI-WORLD)
    ImGui.Text("Output World [Required] (Bisa multi world dipisah koma):")
    ImGui.PushItemWidth(260)
    local chOW, vOW = ImGui.InputText("##tf_ow", st.output_w_buf, 1024)
    ImGui.PopItemWidth()
    if chOW then
        st.output_w_buf = vOW
        c.output_world_raw = trimStr(vOW)
        st.output_queue = parseWorldList(c.output_world_raw)
        TF.saveData()
    end
    ImGui.SameLine()
    if autoBtn("+ World Saat Ini##tf_cur_out") then
        local cw = getCurrentWorld()
        if cw ~= "" and cw ~= "EXIT" then
            if c.output_world_raw == "" then c.output_world_raw = cw
            else c.output_world_raw = c.output_world_raw .. ", " .. cw end
            st.output_w_buf = c.output_world_raw
            st.output_queue = parseWorldList(c.output_world_raw)
            TF.saveData()
        end
    end
    ImGui.SameLine()
    local outCount = #st.output_queue
    if autoBtn(st.show_output_queue and "▲ Tutup Antrian##tf_outq_btn" or ("▼ Antrian (" .. outCount .. ")##tf_outq_btn")) then
        st.show_output_queue = not st.show_output_queue
    end

    if st.show_output_queue then
        ImGui.TextColored(0.4, 0.8, 1.0, 1.0, string.format("--- Daftar Antrian Output World (%d World) ---", outCount))
        if outCount == 0 then
            ImGui.Text("Belum ada Output World. Masukkan nama world di atas (pisahkan koma).")
        else
            for i, w in ipairs(st.output_queue) do
                local badge = (w.status == "Active") and "[PROSES]" or (w.status:match("^Done") and "[SELESAI]" or "[ANTRI]")
                ImGui.Text(string.format(" %d. %s  %s", i, w.raw, badge))
                ImGui.SameLine()
                if autoBtn("Hapus##del_out_" .. i) then
                    table.remove(st.output_queue, i)
                    c.output_world_raw = formatWorldList(st.output_queue)
                    st.output_w_buf = c.output_world_raw
                    TF.saveData()
                    break
                end
            end
            if autoBtn("↺ Reset Status Antrian Output##reset_out_status") then
                for _, w in ipairs(st.output_queue) do w.status = "Ready" end
                st.output_idx = 1
            end
        end
        uiGap(4)
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

    uiGap(4)
    ImGui.Text(string.format("Statistik -> Moved: %d | Bought: %d (%d WL) | Restocked: %d (Max Cap: 5k)",
        st.total_moved, st.total_bought, st.total_wl_spent, st.total_restocked))
end

local function renderAdvancedPanel()
    local c = TF.CFG
    local st = TF.STATE

    ImGui.Text("Pengaturan Lanjutan & Batas Pengaman:")
    uiGap(4)

    ImGui.Text("Maksimal Kuota Pembelian (0 = Tanpa Batas):")
    ImGui.PushItemWidth(140)
    local chMQ, vMQ = ImGui.InputText("##tf_mq", st.max_quota_buf, 10)
    ImGui.PopItemWidth()
    if chMQ then
        st.max_quota_buf = vMQ
        local n = tonumber(vMQ)
        if n and n >= 0 then c.max_buy_quota = math.floor(n); TF.saveData() end
    end

    ImGui.Text("Maksimal Budget WL yang Dibelanjakan (0 = Tanpa Batas):")
    ImGui.PushItemWidth(140)
    local chMB, vMB = ImGui.InputText("##tf_mb", st.max_budget_buf, 10)
    ImGui.PopItemWidth()
    if chMB then
        st.max_budget_buf = vMB
        local n = tonumber(vMB)
        if n and n >= 0 then c.max_wl_budget = math.floor(n); TF.saveData() end
    end

    uiGap(6)
    ImGui.Separator()
    uiGap(4)

    ImGui.Text("Kapasitas Maksimal Vending Machine: " .. tostring(c.vend_max_cap) .. " item (5k)")
    ImGui.Text("Ukuran Batch Drop per Petak: " .. tostring(c.drop_batch) .. " item")

    local chMF, vMF = ImGui.Checkbox("Gunakan ModFly Saat Berpindah##tf_mf", c.use_modfly)
    if chMF then c.use_modfly = vMF; TF.saveData() end

    local chAC, vAC = ImGui.Checkbox("Auto Collect Floating Item##tf_ac", c.auto_collect)
    if chAC then c.auto_collect = vAC; TF.saveData() end
end

local function renderLogsPanel()
    ImGui.Text("Log Aktivitas Transfer:")
    uiGap(2)
    if autoBtn("Bersihkan Log##tf_clr_log") then
        TF.STATE.logs = {}
    end
    uiGap(4)
    if #TF.STATE.logs == 0 then
        ImGui.Text("Belum ada log.")
    else
        for i, l in ipairs(TF.STATE.logs) do
            ImGui.Text(l)
            if i >= 35 then break end
        end
    end
end

local function drawMainWindow()
    if not ImGui then return end

    local winFlags = 2048 -- ImGuiWindowFlags_HorizontalScrollbar (geser kanan kiri)
    if ImGui.WindowFlags and ImGui.WindowFlags.HorizontalScrollbar then
        winFlags = tonumber(ImGui.WindowFlags.HorizontalScrollbar) or 2048
    end

    local pCnt = 0
    local vCnt = 0
    if ImGui.PushStyleColor and ImGui.Col then
        local C = ImGui.Col
        local function pc(k, col)
            local idx = tonumber(C[k]) or C[k]
            if idx and pcall(ImGui.PushStyleColor, idx, col) then pCnt = pCnt + 1 end
        end
        pc("ScrollbarBg", 0xFF140A28)
        pc("ScrollbarGrab", 0xFFE04000)
        pc("ScrollbarGrabHovered", 0xFFFF6020)
        pc("ScrollbarGrabActive", 0xFFFF3080)
    end
    if ImGui.PushStyleVar and ImGui.StyleVar then
        local V = ImGui.StyleVar
        local function pv(k, val)
            local idx = tonumber(V[k]) or V[k]
            if idx and pcall(ImGui.PushStyleVar, idx, val) then vCnt = vCnt + 1 end
        end
        pv("ScrollbarRounding", 6.0)
        pv("ScrollbarSize", 14.0)
    end

    local okCall, res = pcall(ImGui.Begin, "Boren Transfer Pro - Multi World", true, winFlags)
    if not okCall or res == nil then
        okCall, res = pcall(ImGui.Begin, "Boren Transfer Pro - Multi World", winFlags)
    end
    if not okCall or res == nil then
        okCall, res = pcall(ImGui.Begin, "Boren Transfer Pro - Multi World", true)
    end
    if not okCall or res == nil then
        okCall, res = pcall(ImGui.Begin, "Boren Transfer Pro - Multi World")
    end

    if okCall and res then
        local sub = TF.STATE.active_sub or "main"
        if autoBtn(sub == "main" and "[ Panel Utama ]##sub_main" or "Panel Utama##sub_main") then
            TF.STATE.active_sub = "main"
        end
        ImGui.SameLine()
        if autoBtn(sub == "adv" and "[ Pengaturan Lanjut ]##sub_adv" or "Pengaturan Lanjut##sub_adv") then
            TF.STATE.active_sub = "adv"
        end
        ImGui.SameLine()
        if autoBtn(sub == "logs" and "[ Log Bot ]##sub_logs" or "Log Bot##sub_logs") then
            TF.STATE.active_sub = "logs"
        end

        uiGap(6)
        ImGui.Separator()
        uiGap(6)

        if sub == "main" then
            renderMainPanel()
        elseif sub == "adv" then
            renderAdvancedPanel()
        elseif sub == "logs" then
            renderLogsPanel()
        end

        pcall(ImGui.End)
    end

    if vCnt > 0 and ImGui.PopStyleVar then pcall(ImGui.PopStyleVar, vCnt) end
    if pCnt > 0 and ImGui.PopStyleColor then pcall(ImGui.PopStyleColor, pCnt) end
end

-- ============================================================================
-- 8. NATIVE GROWLAUNCHER 5-TAB MENU INTEGRATION
-- ============================================================================
local function setupNativeMenu()
    if not interface or not interface.add_tab then return end

    interface.add_tab("Transfer: Mode", function(ui)
        ui:addLabel("=== AUTO TRANSFER PRO (BOREN STORE) ===")
        ui:addLabel("Mode Operasi:")
        ui:addToggle("Enable (START / STOP)", TF.CFG.enabled, "tf_toggle_en", false)
        ui:addToggle("Auto Vend (Beli dari Toko)", TF.CFG.auto_vend, "tf_toggle_av", false)
        ui:addToggle("Restock (Isi Vend sampai 5k Full)", TF.CFG.restock, "tf_toggle_rs", false)
        ui:addToggle("Per Item (ON = X WL/item, OFF = Rate)", TF.CFG.per_item, "tf_toggle_pi", false)
        ui:addToggle("Vertical Traversal (Kolom Atas-Bawah)", TF.CFG.vertical, "tf_toggle_vt", false)
    end)

    interface.add_tab("Transfer: Target", function(ui)
        ui:addLabel("=== PENGATURAN TARGET ITEM ===")
        ui:addInputInt("Item ID", 1, 999999, TF.CFG.item_id or 4584, "tf_input_item_id")
        ui:addInputInt("Item Price (Referensi)", 0, 99999, TF.CFG.item_price or 0, "tf_input_price")
        ui:addInputInt("Item Buy Price (Batas)", 1, 99999, TF.CFG.item_buy_price or 200, "tf_input_buy_price")
    end)

    interface.add_tab("Transfer: Worlds", function(ui)
        ui:addLabel("=== DAFTAR MULTI-WORLD ===")
        ui:addInputText("Input World (Pisahkan Koma)", TF.CFG.input_world_raw or "", "tf_in_world")
        ui:addInputText("Output World (Pisahkan Koma)", TF.CFG.output_world_raw or "", "tf_out_world")
        ui:addLabel(string.format("Antrian Saat Ini -> Input: %d World | Output: %d World", #TF.STATE.input_queue, #TF.STATE.output_queue))
    end)

    interface.add_tab("Transfer: Budget", function(ui)
        ui:addLabel("=== PENGATURAN BUDGET & LIMIT ===")
        ui:addInputInt("Maksimal Kuota Beli (0 = Unlimit)", 0, 999999, TF.CFG.max_buy_quota or 0, "tf_max_quota")
        ui:addInputInt("Maksimal Budget WL (0 = Unlimit)", 0, 999999, TF.CFG.max_wl_budget or 0, "tf_max_budget")
    end)

    interface.add_tab("Transfer: Log", function(ui)
        ui:addLabel("=== STATUS & LOG AKTIVITAS ===")
        ui:addLabel("Status: " .. tostring(TF.STATE.status_text))
        ui:addLabel(string.format("Moved: %d | Bought: %d | Restocked: %d (5k)", TF.STATE.total_moved, TF.STATE.total_bought, TF.STATE.total_restocked))
    end)
end

-- ============================================================================
-- 9. HOOK PACKET / DIALOG CAPTURE
-- ============================================================================
local function hookDialogReturn(vtype, packet)
    if vtype == 2 and type(packet) == "string" then
        if packet:find("action|dialog_return") or packet:find("dialog_name|vending") then
            TF.STATE.last_dlg_text = packet
        end
    end
end

if AddHook then
    pcall(AddHook, "OnSendPacket", "boren_tf_dlg_hook", hookDialogReturn)
elseif addHook then
    pcall(addHook, "OnSendPacket", "boren_tf_dlg_hook", hookDialogReturn)
end

-- ============================================================================
-- 10. BOOTSTRAP INITIALIZATION
-- ============================================================================
TF.loadData()
setupNativeMenu()

if imgui and imgui.render then
    pcall(imgui.render, drawMainWindow)
end

if LogToConsole then
    pcall(LogToConsole, "`2[Boren Store] `0Auto Transfer Pro (Multi-World) Berhasil Dimuat! Ketik /transfer untuk buka menu.")
end

return TF
