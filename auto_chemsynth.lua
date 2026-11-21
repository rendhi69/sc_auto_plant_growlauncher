-- ============================================================================
-- BOREN STORE - AUTO CHEMSYNTH SOLVER (GROWLAUNCHER)
-- Repo: https://github.com/rendhi69/sc_chemsynth_growlauncher-.git
-- ============================================================================

local CS = {
    VERSION = "1.0.0",
    CFG = {
        auto_loop    = true,
        auto_start   = true,   -- Auto wrench Processor untuk mulai
        auto_dialog  = true,   -- Auto konfirmasi dialog Processor jika muncul
        action_delay = 280,    -- Delay antar pemakaian tool (ms)
        sync_timeout = 950,    -- Maks tunggu update tank dari server (ms)
        beam_width   = 70,     -- Lebar Beam Search (ringan untuk Android)
        max_depth    = 12,     -- Kedalaman maksimum Beam Search
        use_solvent  = true,   -- Izinkan Solvent saat solver deterministik buntu
        -- Mapping field Tile.extra untuk membaca current & target color ("auto" = deteksi otomatis)
        cur_field    = "auto",
        tgt_field    = "auto",
    },
    STATE = {
        running      = false,
        status       = "Idle",
        proc_x       = nil,
        proc_y       = nil,
        cur          = {},     -- [1..10] warna saat ini (1..5)
        tgt          = {},     -- [1..10] warna target (1..5)
        solved_count = 0,
        step_count   = 0,
        last_move    = "-",
        logs         = {},
        show_ui      = true,
        inv          = { r = 0, y = 0, g = 0, b = 0, p = 0, cat = 0, str = 0, rep = 0, cen = 0, sol = 0 },
    },
}

-- ============================================================================
-- 1. ITEM IDs & COLOR MAPPING
-- ============================================================================
local function resolveItemID(name, fallback)
    if findItemID then
        local ok, id = pcall(findItemID, name)
        if ok and tonumber(id) and tonumber(id) > 0 then return math.floor(tonumber(id)) end
    end
    if growtopia and growtopia.getItemID then
        local ok, id = pcall(growtopia.getItemID, name)
        if ok and tonumber(id) and tonumber(id) > 0 then return math.floor(tonumber(id)) end
    end
    return fallback
end

local ITEM = {
    WRENCH     = 32,
    PROCESSOR  = resolveItemID("Chemsynth Processor", 4430),
    TANK       = resolveItemID("Chemsynth Tank", 4432),
    CENTRIFUGE = resolveItemID("Chemsynth Centrifuge", 4434),
    REPLICATOR = resolveItemID("Chemsynth Replicator", 4436),
    CATALYST   = resolveItemID("Chemsynth Catalyst", 4438),
    SOLVENT    = resolveItemID("Chemsynth Solvent", 4440),
    STIRRER    = resolveItemID("Chemsynth Stirrer", 4442),
    -- 5 Chemical sesuai urutan spektrum Catalyst: Red -> Yellow -> Green -> Blue -> Pink -> Red
    CHEM_R     = resolveItemID("Chemical R", 916),
    CHEM_Y     = resolveItemID("Chemical Y", 924),
    CHEM_G     = resolveItemID("Chemical G", 914),
    CHEM_B     = resolveItemID("Chemical B", 920),
    CHEM_P     = resolveItemID("Chemical P", 918),
}

-- Index warna 1..5 (urutan spektrum Catalyst)
local COLOR_NAME = { [1] = "R", [2] = "Y", [3] = "G", [4] = "B", [5] = "P" }
local COLOR_FULL = { [1] = "Red", [2] = "Yellow", [3] = "Green", [4] = "Blue", [5] = "Pink" }
local COLOR_CHEM_ID = {
    [1] = ITEM.CHEM_R,
    [2] = ITEM.CHEM_Y,
    [3] = ITEM.CHEM_G,
    [4] = ITEM.CHEM_B,
    [5] = ITEM.CHEM_P,
}
local CHEM_ID_TO_COLOR = {
    [ITEM.CHEM_R] = 1,
    [ITEM.CHEM_Y] = 2,
    [ITEM.CHEM_G] = 3,
    [ITEM.CHEM_B] = 4,
    [ITEM.CHEM_P] = 5,
}
local TOOL_NAME = {
    catalyst   = "Catalyst",
    stirrer    = "Stirrer",
    replicator = "Replicator",
    centrifuge = "Centrifuge",
    solvent    = "Solvent",
}
local TOOL_ID = {
    catalyst   = ITEM.CATALYST,
    stirrer    = ITEM.STIRRER,
    replicator = ITEM.REPLICATOR,
    centrifuge = ITEM.CENTRIFUGE,
    solvent    = ITEM.SOLVENT,
}

-- ============================================================================
-- 2. SAFE HELPERS (GROWLAUNCHER API)
-- ============================================================================
local function addLog(msg)
    local clean = tostring(msg or ""):gsub("`.", "")
    local ts = ""
    if os and os.date then
        local ok, d = pcall(os.date, "%H:%M:%S")
        if ok and d then ts = "[" .. d .. "] " end
    end
    table.insert(CS.STATE.logs, 1, ts .. clean)
    if #CS.STATE.logs > 40 then table.remove(CS.STATE.logs) end
    if LogToConsole then pcall(LogToConsole, "`e[Boren Chem] `w" .. tostring(msg or "")) end
end

local function safeSleep(ms)
    ms = math.max(10, tonumber(ms) or 50)
    local fn = sleep or CSleep
    if fn then pcall(fn, ms) end
end

local function getTileSafe(x, y)
    if not getTile or x < 0 or x > 99 or y < 0 or y > 53 then return nil end
    local ok, t = pcall(getTile, x, y)
    return (ok and t) and t or nil
end

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

local function getInvCount(id)
    id = tonumber(id) or 0
    if id <= 0 then return 0 end
    if growtopia and growtopia.checkInventoryCount then
        local ok, cnt = pcall(growtopia.checkInventoryCount, id)
        if ok and tonumber(cnt) then return math.floor(tonumber(cnt)) end
    end
    if getInventory then
        local ok, inv = pcall(getInventory)
        if ok and inv then
            local total = 0
            pcall(function()
                for _, it in pairs(inv) do
                    local iid = tonumber(it.id or it.itemid or it.itemID)
                    local amt = tonumber(it.amount or it.count) or 0
                    if iid == id then total = total + amt end
                end
            end)
            return total
        end
    end
    return 0
end

local function moveNear(tx, ty)
    local px, py = getPlayerPos()
    if math.abs(px - tx) <= 2 and math.abs(py - ty) <= 2 then return true end
    local pFn = FindPath or findPath
    if not pFn then return false end
    -- Berdiri tepat di atas/samping tank agar aman dalam jangkauan 2 tile
    local cands = { { tx, ty }, { tx, ty - 1 }, { tx, ty + 1 }, { tx - 1, ty }, { tx + 1, ty } }
    for _, c in ipairs(cands) do
        local cx, cy = math.max(0, math.min(99, c[1])), math.max(0, math.min(53, c[2]))
        local t = getTileSafe(cx, cy)
        if t and not t.collidable then
            pcall(pFn, cx, cy)
            local waited, lastX, lastY, stuck = 0, px, py, 0
            while waited < 2500 and CS.STATE.running do
                safeSleep(50); waited = waited + 50
                local nx, ny = getPlayerPos()
                if math.abs(nx - tx) <= 2 and math.abs(ny - ty) <= 2 then return true end
                if nx == lastX and ny == lastY then
                    stuck = stuck + 1
                    if stuck >= 6 then break end
                else
                    stuck = 0; lastX, lastY = nx, ny
                end
            end
        end
    end
    local fx, fy = getPlayerPos()
    return math.abs(fx - tx) <= 2 and math.abs(fy - ty) <= 2
end

local function useItemOnTile(tx, ty, itemID)
    if not sendPacketRaw then return false end
    local p = getLocalSafe()
    local px = (p and (p.posX or (p.pos and p.pos.x))) or (tx * 32)
    local py = (p and (p.posY or (p.pos and p.pos.y))) or (ty * 32)
    return pcall(sendPacketRaw, false, {
        type  = 3,
        value = itemID,
        px    = tx,
        py    = ty,
        x     = px,
        y     = py,
        state = (px > tx * 32) and 48 or 32,
    })
end

-- ============================================================================
-- 3. PEMBACAAN DATA CHEMSYNTH PROCESSOR & 10 TANK
-- ============================================================================
local function normalizeColor(v)
    v = tonumber(v)
    if not v or v <= 0 then return 0 end
    if CHEM_ID_TO_COLOR[v] then return CHEM_ID_TO_COLOR[v] end
    if v >= 1 and v <= 5 then return math.floor(v) end
    return 0
end

local function readFieldSafe(tbl, key)
    if not tbl or not key then return nil end
    local ok, val = pcall(function() return tbl[key] end)
    return ok and val or nil
end

-- Baca (curColor, tgtColor) dari sebuah Tile Chemsynth Tank
local function readTankColors(t)
    if not t then return 0, 0 end
    local ex = readFieldSafe(t, "extra")
    if not ex then return 0, 0 end

    -- Mode manual jika user menentukan field spesifik
    if CS.CFG.cur_field ~= "auto" and CS.CFG.tgt_field ~= "auto" then
        return normalizeColor(readFieldSafe(ex, CS.CFG.cur_field)),
               normalizeColor(readFieldSafe(ex, CS.CFG.tgt_field))
    end

    -- Auto-deteksi pasangan field umum di berbagai versi Growlauncher
    local pairsToCheck = {
        { "current_chem", "target_chem" },
        { "current",      "target"      },
        { "chem",         "target"      },
        { "alttype",      "volume"      },
        { "color",        "volume"      },
        { "volume",       "color"       },
        { "flag",         "alttype"     },
        { "lastupdate",   "lastupdate2" },
        { "growth",       "fruitcount"  },
        { "vend_item",    "vend_price"  },
    }
    for _, p in ipairs(pairsToCheck) do
        local c = normalizeColor(readFieldSafe(ex, p[1]))
        local g = normalizeColor(readFieldSafe(ex, p[2]))
        if c >= 1 and c <= 5 and g >= 1 and g <= 5 then
            return c, g
        end
    end
    return 0, 0
end

-- Scan world untuk menemukan Chemsynth Processor + 10 Chemsynth Tank di kanannya
local function findChemsynthSetup()
    for y = 0, 53 do
        for x = 0, 89 do
            local t = getTileSafe(x, y)
            if t and tonumber(t.fg) == ITEM.PROCESSOR then
                local okAll = true
                for i = 1, 10 do
                    local tk = getTileSafe(x + i, y)
                    if not tk or tonumber(tk.fg) ~= ITEM.TANK then
                        okAll = false; break
                    end
                end
                if okAll then
                    CS.STATE.proc_x, CS.STATE.proc_y = x, y
                    return true, x, y
                end
            end
        end
    end
    CS.STATE.proc_x, CS.STATE.proc_y = nil, nil
    return false, nil, nil
end

local function readAllTanks()
    if not CS.STATE.proc_x or not CS.STATE.proc_y then return false, nil, nil end
    local cur, tgt = {}, {}
    local activeCount = 0
    for i = 1, 10 do
        local t = getTileSafe(CS.STATE.proc_x + i, CS.STATE.proc_y)
        local c, g = readTankColors(t)
        cur[i], tgt[i] = c, g
        if c >= 1 and g >= 1 then activeCount = activeCount + 1 end
    end
    CS.STATE.cur, CS.STATE.tgt = cur, tgt
    return (activeCount == 10), cur, tgt
end

-- Tombol Diagnostik: Dump semua field Tile.extra 10 tank agar 100% pasti kalau format GL berbeda
local function dumpTankExtraDebug()
    local ok, px, py = findChemsynthSetup()
    if not ok then
        addLog("`4[Dump] Processor (ID " .. ITEM.PROCESSOR .. ") + 10 Tank (ID " .. ITEM.TANK .. ") tidak ditemukan!")
        return
    end
    addLog(string.format("`2[Dump] Setup ditemukan di (%d,%d). Inspect 3 tank pertama:", px, py))
    local fields = {
        "type", "current_chem", "target_chem", "alttype", "color", "volume",
        "flag", "growth", "fruitcount", "lastupdate", "lastupdate2",
        "vend_item", "vend_price", "dshelf1", "dshelf2", "label"
    }
    for i = 1, 3 do
        local t = getTileSafe(px + i, py)
        local ex = t and readFieldSafe(t, "extra")
        local parts = { string.format("T%d(%d,%d) fg=%s fl=%s", i, px + i, py, tostring(t and t.fg), tostring(t and t.flag)) }
        if ex then
            for _, f in ipairs(fields) do
                local v = readFieldSafe(ex, f)
                if v ~= nil and v ~= 0 and v ~= "" then
                    table.insert(parts, f .. "=" .. tostring(v))
                end
            end
        else
            table.insert(parts, "extra=nil")
        end
        addLog(table.concat(parts, " | "))
    end
    local active, cur, tgt = readAllTanks()
    if active then
        local sc, st = {}, {}
        for i = 1, 10 do sc[i] = COLOR_NAME[cur[i]] or "?"; st[i] = COLOR_NAME[tgt[i]] or "?" end
        addLog("`2[Dump] Auto-read OK! Cur=" .. table.concat(sc) .. " Tgt=" .. table.concat(st))
    else
        addLog("`e[Dump] Auto-read belum cocok (belum aktif atau nama field extra beda). Kirim log di atas!")
    end
end

-- ============================================================================
-- 4. SIMULATOR 4 TOOL DETERMINISTIK + BEAM SEARCH SOLVER
-- ============================================================================
local function copyState(s)
    return { s[1], s[2], s[3], s[4], s[5], s[6], s[7], s[8], s[9], s[10] }
end

local function stateKey(s)
    return string.char(
        48 + s[1], 48 + s[2], 48 + s[3], 48 + s[4], 48 + s[5],
        48 + s[6], 48 + s[7], 48 + s[8], 48 + s[9], 48 + s[10]
    )
end

local function statesEqual(a, b)
    for i = 1, 10 do if a[i] ~= b[i] then return false end end
    return true
end

-- 1) Catalyst: warna tank i + semua tetangga bersebelahan warna sama naik 1 spektrum (1->2->3->4->5->1)
local function applyCatalyst(s, idx)
    local ns = copyState(s)
    local c = ns[idx]
    local nc = (c % 5) + 1
    ns[idx] = nc
    local l = idx - 1
    while l >= 1 and ns[l] == c do ns[l] = nc; l = l - 1 end
    local r = idx + 1
    while r <= 10 and ns[r] == c do ns[r] = nc; r = r + 1 end
    return ns
end

-- 2) Stirrer: tukar tank i-1 dan i+1 tanpa mengubah tank i
local function applyStirrer(s, idx)
    if idx < 2 or idx > 9 or s[idx - 1] == s[idx + 1] then return nil end
    local ns = copyState(s)
    ns[idx - 1], ns[idx + 1] = ns[idx + 1], ns[idx - 1]
    return ns
end

-- 3) Replicator: duplikasi tank i dan geser kanan (tank 10 hilang)
local function applyReplicator(s, idx)
    if idx < 1 or idx > 9 then return nil end
    local ns = copyState(s)
    for k = 10, idx + 1, -1 do ns[k] = ns[k - 1] end
    if statesEqual(ns, s) then return nil end
    return ns
end

-- 4) Centrifuge: rotasi simetris di sekitar tank i sebanyak min(i-1, 10-i)
local function applyCentrifuge(s, idx)
    local span = math.min(idx - 1, 10 - idx)
    if span <= 1 then return nil end -- span==1 identik dengan Stirrer
    local ns = copyState(s)
    local changed = false
    for d = 1, span do
        if ns[idx - d] ~= ns[idx + d] then
            ns[idx - d], ns[idx + d] = ns[idx + d], ns[idx - d]
            changed = true
        end
    end
    return changed and ns or nil
end

local function scoreState(s, tgt)
    local exact = 0
    local distPen = 0
    local cntS = { 0, 0, 0, 0, 0 }
    local cntT = { 0, 0, 0, 0, 0 }
    for i = 1, 10 do
        local si, ti = s[i], tgt[i]
        cntS[si] = cntS[si] + 1
        cntT[ti] = cntT[ti] + 1
        if si == ti then
            exact = exact + 1
        else
            local diff = (ti - si) % 5
            distPen = distPen + diff
        end
    end
    local freqMatch = 0
    for c = 1, 5 do
        freqMatch = freqMatch + math.min(cntS[c], cntT[c])
    end
    -- Bonus blok berurutan yang sudah benar dari kiri atau kanan
    local runBonus = 0
    for i = 1, 10 do if s[i] == tgt[i] then runBonus = runBonus + 2 else break end end
    for i = 10, 1, -1 do if s[i] == tgt[i] then runBonus = runBonus + 2 else break end end
    return exact * 20 + freqMatch * 4 + runBonus - distPen
end

-- Kembalikan: solved (bool), plan (list of { tool, idx }), bestFirstMove
local function solveChemsynth(startState, targetState, availTools, availChems)
    if statesEqual(startState, targetState) then return true, {}, nil end
    local targetKey = stateKey(targetState)
    local visited = { [stateKey(startState)] = true }
    local beam = { { s = copyState(startState), path = {}, score = scoreState(startState, targetState) } }
    local bestNode = beam[1]
    local startScore = bestNode.score

    local hasCat  = availTools.catalyst
    local hasStir = availTools.stirrer
    local hasRep  = availTools.replicator
    local hasCent = availTools.centrifuge
    local beamW   = math.max(20, math.min(150, tonumber(CS.CFG.beam_width) or 70))
    local maxD    = math.max(4, math.min(18, tonumber(CS.CFG.max_depth) or 12))

    for _ = 1, maxD do
        local nextBeam = {}
        for _, node in ipairs(beam) do
            local st = node.s

            local function pushCandidate(ns, toolName, idx)
                if not ns then return false end
                local k = stateKey(ns)
                if visited[k] then return false end
                visited[k] = true
                local np = {}
                for j = 1, #node.path do np[j] = node.path[j] end
                np[#np + 1] = { tool = toolName, idx = idx }
                if k == targetKey then
                    bestNode = { s = ns, path = np, score = 999999 }
                    return true
                end
                local sc = scoreState(ns, targetState)
                local cand = { s = ns, path = np, score = sc }
                nextBeam[#nextBeam + 1] = cand
                if sc > bestNode.score then bestNode = cand end
                return false
            end

            -- 1) Catalyst (cukup 1 posisi perwakilan per grup warna bersebelahan)
            if hasCat then
                for i = 1, 10 do
                    if (i == 1 or st[i] ~= st[i - 1]) and availChems[st[i]] then
                        if pushCandidate(applyCatalyst(st, i), "catalyst", i) then
                            return true, bestNode.path, bestNode.path[1]
                        end
                    end
                end
            end
            -- 2) Stirrer
            if hasStir then
                for i = 2, 9 do
                    if availChems[st[i]] then
                        if pushCandidate(applyStirrer(st, i), "stirrer", i) then
                            return true, bestNode.path, bestNode.path[1]
                        end
                    end
                end
            end
            -- 3) Replicator
            if hasRep then
                for i = 1, 9 do
                    if availChems[st[i]] then
                        if pushCandidate(applyReplicator(st, i), "replicator", i) then
                            return true, bestNode.path, bestNode.path[1]
                        end
                    end
                end
            end
            -- 4) Centrifuge
            if hasCent then
                for i = 3, 8 do
                    if availChems[st[i]] then
                        if pushCandidate(applyCentrifuge(st, i), "centrifuge", i) then
                            return true, bestNode.path, bestNode.path[1]
                        end
                    end
                end
            end
        end

        if #nextBeam == 0 then break end
        table.sort(nextBeam, function(a, b) return a.score > b.score end)
        beam = {}
        local lim = math.min(#nextBeam, beamW)
        for i = 1, lim do beam[i] = nextBeam[i] end
    end

    if bestNode.score > startScore and bestNode.path[1] then
        return false, bestNode.path, bestNode.path[1]
    end
    return false, nil, nil
end

-- ============================================================================
-- 5. ENGINE EKSEKUSI & AUTO DIALOG HOOK
-- ============================================================================
local function checkStartStock()
    for c = 1, 5 do
        local cnt = getInvCount(COLOR_CHEM_ID[c])
        if cnt < 5 then
            return false, string.format("Chemical %s kurang (%d/5)", COLOR_FULL[c], cnt)
        end
    end
    local anyTool = false
    for _, id in pairs(TOOL_ID) do
        if getInvCount(id) > 0 then anyTool = true; break end
    end
    if not anyTool then return false, "Tidak ada Chemsynth Tool di inventory!" end
    return true, "OK"
end

local function refreshInvCache()
    CS.STATE.inv.r   = getInvCount(ITEM.CHEM_R)
    CS.STATE.inv.y   = getInvCount(ITEM.CHEM_Y)
    CS.STATE.inv.g   = getInvCount(ITEM.CHEM_G)
    CS.STATE.inv.b   = getInvCount(ITEM.CHEM_B)
    CS.STATE.inv.p   = getInvCount(ITEM.CHEM_P)
    CS.STATE.inv.cat = getInvCount(ITEM.CATALYST)
    CS.STATE.inv.str = getInvCount(ITEM.STIRRER)
    CS.STATE.inv.rep = getInvCount(ITEM.REPLICATOR)
    CS.STATE.inv.cen = getInvCount(ITEM.CENTRIFUGE)
    CS.STATE.inv.sol = getInvCount(ITEM.SOLVENT)
end

local function getAvailableStock()
    refreshInvCache()
    local inv = CS.STATE.inv
    local tools = {
        catalyst   = inv.cat > 0,
        stirrer    = inv.str > 0,
        replicator = inv.rep > 0,
        centrifuge = inv.cen > 0,
        solvent    = inv.sol > 0,
    }
    local chems = {
        [1] = inv.r > 0,
        [2] = inv.y > 0,
        [3] = inv.g > 0,
        [4] = inv.b > 0,
        [5] = inv.p > 0,
    }
    return tools, chems
end

local function startSynthesis()
    if not CS.STATE.proc_x then return false end
    CS.STATE.status = "Wrench Processor..."
    if not moveNear(CS.STATE.proc_x, CS.STATE.proc_y) then
        addLog("`4Gagal menjangkau Chemsynth Processor!")
        return false
    end
    useItemOnTile(CS.STATE.proc_x, CS.STATE.proc_y, ITEM.WRENCH)
    local waited = 0
    while waited < 2500 and CS.STATE.running do
        safeSleep(150); waited = waited + 150
        local active = readAllTanks()
        if active then return true end
    end
    return readAllTanks()
end

local function executeMove(move)
    local tx = CS.STATE.proc_x + move.idx
    local ty = CS.STATE.proc_y
    local toolID = TOOL_ID[move.tool]
    if not toolID then return false end

    local _, curBefore = readAllTanks()
    local keyBefore = curBefore and stateKey(curBefore) or ""

    CS.STATE.last_move = string.format("%s -> T%d", TOOL_NAME[move.tool] or move.tool, move.idx)
    CS.STATE.status = CS.STATE.last_move

    if not moveNear(tx, ty) then
        addLog("`4Gagal mendekati Tank #" .. tostring(move.idx))
        return false
    end

    useItemOnTile(tx, ty, toolID)
    CS.STATE.step_count = CS.STATE.step_count + 1
    safeSleep(math.max(120, tonumber(CS.CFG.action_delay) or 280))

    -- Tunggu sinkronisasi warna dari server agar tidak desync
    local waited, lim = 0, math.max(300, tonumber(CS.CFG.sync_timeout) or 950)
    while waited < lim and CS.STATE.running do
        local active, curNow, tgtNow = readAllTanks()
        if not active then return true end -- Sudah selesai & reset oleh server
        if statesEqual(curNow, tgtNow) then return true end
        if stateKey(curNow) ~= keyBefore then return true end
        safeSleep(60); waited = waited + 60
    end
    return true
end

local function mainLoop()
    CS.STATE.running = true
    CS.STATE.status = "Scanning..."
    addLog("Auto Chemsynth dimulai.")

    local found, px, py = findChemsynthSetup()
    if not found then
        addLog("`4Setup Processor + 10 Tank tidak ditemukan di world ini!")
        CS.STATE.running = false
        CS.STATE.status = "No Setup"
        return
    end
    addLog(string.format("`2Setup aktif di Processor (%d,%d), Tank X=%d..%d", px, py, px + 1, px + 10))

    while CS.STATE.running do
        local active, cur, tgt = readAllTanks()
        if not active then
            if CS.CFG.auto_start then
                local okStock, reason = checkStartStock()
                if not okStock then
                    addLog("`4Stop: " .. reason)
                    CS.STATE.status = reason
                    break
                end
                if not startSynthesis() then
                    addLog("`eProcessor di-wrench tapi tank belum terbaca. Coba klik 'Dump Tile Extra' saat aktif.")
                    CS.STATE.status = "Tank Unreadable"
                    break
                end
                active, cur, tgt = readAllTanks()
            else
                CS.STATE.status = "Menunggu aktif..."
                safeSleep(400)
            end
        end

        if active and cur and tgt then
            if statesEqual(cur, tgt) then
                CS.STATE.solved_count = CS.STATE.solved_count + 1
                addLog("`2Synthesis #" .. CS.STATE.solved_count .. " selesai!")
                CS.STATE.status = "Done #" .. CS.STATE.solved_count
                safeSleep(1200)
                if not CS.CFG.auto_loop then break end
            else
                local tools, chems = getAvailableStock()
                local solved, plan, firstMove = solveChemsynth(cur, tgt, tools, chems)
                if firstMove then
                    if solved then
                        addLog(string.format("`2Solusi ditemukan (%d langkah) -> %s T%d", #plan, TOOL_NAME[firstMove.tool], firstMove.idx))
                    end
                    executeMove(firstMove)
                elseif CS.CFG.use_solvent and tools.solvent then
                    -- Pilih tank pertama yang belum cocok dan chemical-nya tersedia untuk Solvent
                    local sIdx = nil
                    for i = 1, 10 do
                        if cur[i] ~= tgt[i] and chems[cur[i]] then sIdx = i; break end
                    end
                    if sIdx then
                        addLog("`eSolusi deterministik buntu -> pakai Solvent di Tank #" .. sIdx)
                        executeMove({ tool = "solvent", idx = sIdx })
                    else
                        addLog("`4Stop: Chemical untuk Solvent habis!")
                        CS.STATE.status = "No Chem"
                        break
                    end
                else
                    addLog("`4Stop: Tidak ada langkah valid (cek stok tool/chemical).")
                    CS.STATE.status = "Stuck/No Stock"
                    break
                end
            end
        end
    end

    CS.STATE.running = false
    if CS.STATE.status == "Scanning..." then CS.STATE.status = "Idle" end
    addLog("Auto Chemsynth berhenti.")
end

function CS.start()
    if CS.STATE.running then return end
    local function runner()
        local ok, err = xpcall(mainLoop, function(e)
            return tostring(e) .. "\n" .. (debug and debug.traceback and debug.traceback() or "")
        end)
        if not ok then
            addLog("`4[Crash] " .. tostring(err))
            CS.STATE.running = false
            CS.STATE.status = "Error"
        end
    end
    if runCoroutine then pcall(runCoroutine, runner)
    else coroutine.resume(coroutine.create(runner)) end
end

function CS.stop()
    CS.STATE.running = false
    CS.STATE.status = "Stopped"
end

-- Auto-konfirmasi dialog Chemsynth Processor jika server memunculkan dialog konfirmasi
local function onVariantHook(var)
    if not CS.STATE.running or not CS.CFG.auto_dialog then return false end
    if var and var.v1 == "OnDialogRequest" and type(var.v2) == "string" then
        local dlg = var.v2
        if dlg:lower():find("chemsynth", 1, true) then
            local dlgName = dlg:match("end_dialog|([^|]+)|") or "chemsynth_processor"
            local btn = dlg:match("add_button|([^|]+)|[^|]*[Ss]tart") or dlg:match("add_button|([^|]+)|[^|]*[Bb]egin")
            if btn and sendPacket then
                pcall(sendPacket, 2, "action|dialog_return\ndialog_name|" .. dlgName .. "\nbuttonClicked|" .. btn .. "\n")
                return true
            end
        end
    end
    return false
end

local function runAsync(fn)
    if runCoroutine then pcall(runCoroutine, fn)
    else coroutine.resume(coroutine.create(fn)) end
end

local function doScanNow()
    refreshInvCache()
    local ok, px, py = findChemsynthSetup()
    if ok then
        readAllTanks()
        addLog(string.format("Setup ditemukan di (%d,%d)", px, py))
    else
        addLog("Setup tidak ditemukan di world ini.")
    end
end

-- ============================================================================
-- 6. COMPACT IMGUI + NATIVE GROWLAUNCHER MENU
-- ============================================================================
local function formatColors(arr)
    if not arr or #arr < 10 then return "- - - - - - - - - -" end
    local out = {}
    for i = 1, 10 do out[i] = COLOR_NAME[arr[i]] or "." end
    return table.concat(out, " ")
end

local function safeCheckbox(label, curVal)
    local ok, r1, r2 = pcall(ImGui.Checkbox, label, curVal)
    if not ok then return false, curVal end
    if type(r1) == "boolean" and type(r2) == "boolean" then
        return r1, r2
    elseif type(r1) == "boolean" and r1 ~= curVal then
        return true, r1
    end
    return false, curVal
end

function onDrawImGui()
    if (not ImGui) or (not CS.STATE.show_ui) then return end
    pcall(function()
        if ImGui.SetNextWindowSize and ImVec2 then
            local cond = (ImGui.Cond and ImGui.Cond.FirstUseEver) or 4
            ImGui.SetNextWindowSize(ImVec2(370, 340), cond)
        end
        local opened = ImGui.Begin("BOREN CHEMSYNTH v" .. CS.VERSION)
        if opened then
            local inv = CS.STATE.inv
            ImGui.Text(string.format("Status: %s | Solved: %d | Steps: %d", CS.STATE.status, CS.STATE.solved_count, CS.STATE.step_count))
            if CS.STATE.proc_x then
                ImGui.Text(string.format("Processor: (%d,%d) | Last: %s", CS.STATE.proc_x, CS.STATE.proc_y, CS.STATE.last_move))
            else
                ImGui.Text("Processor: Belum discan")
            end

            if ImGui.Separator then ImGui.Separator() end
            ImGui.Text("Cur: " .. formatColors(CS.STATE.cur))
            ImGui.Text("Tgt: " .. formatColors(CS.STATE.tgt))
            ImGui.Text(string.format("Chem R:%d Y:%d G:%d B:%d P:%d", inv.r, inv.y, inv.g, inv.b, inv.p))
            ImGui.Text(string.format("Tool Cat:%d Str:%d Rep:%d Cen:%d Sol:%d", inv.cat, inv.str, inv.rep, inv.cen, inv.sol))

            if ImGui.Separator then ImGui.Separator() end
            if not CS.STATE.running then
                if ImGui.Button("START") then CS.start() end
            else
                if ImGui.Button("STOP") then CS.stop() end
            end
            if ImGui.SameLine then ImGui.SameLine() end
            if ImGui.Button("Scan") then runAsync(doScanNow) end
            if ImGui.SameLine then ImGui.SameLine() end
            if ImGui.Button("Dump Tile Extra") then runAsync(dumpTankExtraDebug) end

            if ImGui.Separator then ImGui.Separator() end
            local chL, vL = safeCheckbox("Auto Loop", CS.CFG.auto_loop)
            if chL then CS.CFG.auto_loop = vL end
            if ImGui.SameLine then ImGui.SameLine() end
            local chS, vS = safeCheckbox("Auto Wrench", CS.CFG.auto_start)
            if chS then CS.CFG.auto_start = vS end
            if ImGui.SameLine then ImGui.SameLine() end
            local chSol, vSol = safeCheckbox("Solvent", CS.CFG.use_solvent)
            if chSol then CS.CFG.use_solvent = vSol end

            ImGui.Text("Delay: " .. tostring(CS.CFG.action_delay) .. " ms")
            if ImGui.SameLine then ImGui.SameLine() end
            if ImGui.Button("-50##dl") then CS.CFG.action_delay = math.max(150, CS.CFG.action_delay - 50) end
            if ImGui.SameLine then ImGui.SameLine() end
            if ImGui.Button("+50##dl") then CS.CFG.action_delay = math.min(1000, CS.CFG.action_delay + 50) end

            if ImGui.Separator then ImGui.Separator() end
            for i = 1, math.min(6, #CS.STATE.logs) do
                if ImGui.TextWrapped then ImGui.TextWrapped(tostring(CS.STATE.logs[i]))
                else ImGui.Text(tostring(CS.STATE.logs[i])) end
            end
        end
        ImGui.End()
    end)
end
OnDrawImGui = onDrawImGui

-- Menu Native Growlauncher (ikon & skema persis seperti Auto Soil/Plant yang terbukti muncul)
local function registerNativeMenu()
    if not addIntoModule then return false end
    local js = nil
    if UserInterface and UserInterface.new then
        local okU, ui = pcall(UserInterface.new, "Auto Chemsynth", "PlayArrow")
        if okU and ui and ui.generateJSON then
            ui:addLabelApp("Boren Store - Auto Chemsynth v" .. CS.VERSION, "Storefront")
            ui:addButton("START CHEMSYNTH", "cs_btn_start")
            ui:addButton("STOP CHEMSYNTH", "cs_btn_stop")
            ui:addButton("Scan Setup", "cs_btn_scan")
            ui:addButton("Dump Tile Extra", "cs_btn_dump")
            ui:addToggle("Tampilkan Panel ImGui", CS.STATE.show_ui, "cs_show_ui", false)
            ui:addToggle("Auto Loop", CS.CFG.auto_loop, "cs_auto_loop", false)
            ui:addToggle("Auto Wrench Processor", CS.CFG.auto_start, "cs_auto_start", false)
            ui:addToggle("Pakai Solvent saat Buntu", CS.CFG.use_solvent, "cs_use_solvent", false)
            ui:addSlider("Delay Tool (ms)", 150, 1000, CS.CFG.action_delay, 50, false, "cs_delay")
            local okJ, out = pcall(function() return ui:generateJSON() end)
            if okJ and type(out) == "string" and out ~= "" then js = out end
        end
    end
    if not js then
        js = '{"sub_name":"Auto Chemsynth","icon":"PlayArrow","menu":[' ..
            '{"type":"labelapp","text":"Boren Store - Auto Chemsynth","icon":"Storefront"},' ..
            '{"type":"button","text":"START CHEMSYNTH","alias":"cs_btn_start"},' ..
            '{"type":"button","text":"STOP CHEMSYNTH","alias":"cs_btn_stop"},' ..
            '{"type":"button","text":"Scan Setup","alias":"cs_btn_scan"},' ..
            '{"type":"button","text":"Dump Tile Extra","alias":"cs_btn_dump"},' ..
            '{"type":"toggle","text":"Tampilkan Panel ImGui","default":true,"alias":"cs_show_ui"},' ..
            '{"type":"toggle","text":"Auto Loop","default":true,"alias":"cs_auto_loop"},' ..
            '{"type":"toggle","text":"Auto Wrench Processor","default":true,"alias":"cs_auto_start"},' ..
            '{"type":"toggle","text":"Pakai Solvent saat Buntu","default":true,"alias":"cs_use_solvent"}' ..
            ']}'
    end
    if addCategory then pcall(addCategory, "Boren Chem", "Storefront") end
    local okAdd = pcall(addIntoModule, js, "Boren Chem")
    return okAdd
end

local function handleVal(name, val)
    if name == "cs_btn_start" then CS.start()
    elseif name == "cs_btn_stop" then CS.stop()
    elseif name == "cs_btn_scan" then runAsync(doScanNow)
    elseif name == "cs_btn_dump" then runAsync(dumpTankExtraDebug)
    elseif name == "cs_show_ui" then CS.STATE.show_ui = (val == true)
    elseif name == "cs_auto_loop" then CS.CFG.auto_loop = (val == true)
    elseif name == "cs_auto_start" then CS.CFG.auto_start = (val == true)
    elseif name == "cs_use_solvent" then CS.CFG.use_solvent = (val == true)
    elseif name == "cs_delay" and tonumber(val) then CS.CFG.action_delay = math.floor(tonumber(val)) end
end

function OnValue(a1, a2, a3)
    if type(a2) == "string" then handleVal(a2, a3)
    elseif type(a1) == "string" then handleVal(a1, a2) end
end
onValue   = OnValue
onVariant = onVariantHook
OnVariant = onVariantHook

if addHook then
    pcall(addHook, onVariantHook, "onvariant")
    pcall(addHook, onValue, "onvalue")
end

local okMenu = registerNativeMenu()
if setOnValue then
    for _, al in ipairs({ "cs_btn_start", "cs_btn_stop", "cs_btn_scan", "cs_btn_dump", "cs_show_ui", "cs_auto_loop", "cs_auto_start", "cs_use_solvent", "cs_delay" }) do
        pcall(setOnValue, al, function(a1, a2, a3)
            if a2 == al then handleVal(al, a3)
            elseif a1 == al then handleVal(al, a2)
            else handleVal(al, a1) end
        end)
    end
end
if applyHook then pcall(applyHook) end

pcall(refreshInvCache)
addLog(string.format("`2Boren Chemsynth v%s aktif! [Menu:%s ImGui:%s]", CS.VERSION, okMenu and "OK" or "NO", ImGui and "OK" or "NO"))
return CS
