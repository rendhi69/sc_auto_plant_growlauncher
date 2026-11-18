-- ============================================================================
-- BOREN STORE IMGUI - GLOBAL CONNECTION GUARD & AUTO-RECONNECT MANAGER
-- File: imgui_hub/conn_guard.lua
-- ============================================================================
-- Satu pengawas koneksi terpusat untuk SEMUA fitur (Plant, Dirt Farm,
-- Build Soil, Buy Pack):
--   1. Deteksi DC akurat (bedakan warp sengaja vs disconnect asli / kicked EXIT).
--   2. Freeze semua aksi bot saat DC (tidak spam packet / false Done / Inaccessible).
--   3. Fokus reconnect (Auto Reconnect GL + growtopia.enter() backoff aman).
--   4. Stop otomatis pada pesan fatal (banned / suspended / maintenance).
--   5. Validasi online stabil 2.5 detik -> re-apply cheats -> warp balik & resume!
-- ============================================================================

local CONN = {}

CONN.CFG = {
    enabled = true, -- Default ON untuk semua fitur BOREN STORE
}

CONN.STATE = {
    reconnecting   = false,
    is_warping     = false,
    dc_flag        = false,
    dc_reason      = "",
    fatal_stop     = false,
    fatal_reason   = "",
    status_text    = "Online",
    started_ms     = 0,
    attempts       = 0,
    total_reconn   = 0,
}

local HUB_REF = nil
local CACHED_CFG_PATH = nil

-- ============================================================================
-- 1. SAFE HELPERS & PERSISTENCE
-- ============================================================================
local function nowMs()
    if getTime then
        local ok, ms = pcall(getTime)
        if ok and tonumber(ms) then return math.floor(tonumber(ms)) end
    end
    if os and os.clock then
        local ok, c = pcall(os.clock)
        if ok and tonumber(c) then return math.floor(tonumber(c) * 1000) end
    end
    return 0
end

local function safeSleep(ms)
    ms = tonumber(ms) or 50
    if ms < 10 then ms = 10 end
    local fn = sleep or CSleep
    if fn then pcall(fn, ms) end
end

local function stripColors(s)
    return (tostring(s or ""):gsub("`.", ""):gsub("%z", ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function cleanWorld(s)
    return stripColors(s):upper()
end

local function logConn(msg)
    local line = "[Reconnect] " .. stripColors(msg)
    if HUB_REF and HUB_REF.addLog then pcall(HUB_REF.addLog, line) end
    if LogToConsole then pcall(LogToConsole, "`e[BOREN CONN] `w" .. tostring(msg)) end
end

local function getCfgPath()
    if CACHED_CFG_PATH then return CACHED_CFG_PATH end
    if package and package.config and package.config:sub(1, 1) == "\\" then
        CACHED_CFG_PATH = "boren_hub_conn_cfg.txt"
        return CACHED_CFG_PATH
    end
    local dirs = {
        "/storage/emulated/0/Android/media/launcher.powerkuy.growlauncher/ScriptLua/",
        "/storage/emulated/0/Android/data/launcher.powerkuy.growlauncher/files/ScriptLua/",
        "/storage/emulated/0/Download/",
    }
    for _, d in ipairs(dirs) do
        local p = d .. "boren_hub_conn_cfg.txt"
        local okR, fR = pcall(io.open, p, "r")
        if okR and fR then fR:close(); CACHED_CFG_PATH = p; return p end
        local okW, fW = pcall(io.open, p, "a")
        if okW and fW then fW:close(); CACHED_CFG_PATH = p; return p end
    end
    CACHED_CFG_PATH = "boren_hub_conn_cfg.txt"
    return CACHED_CFG_PATH
end

function CONN.saveConfig()
    local ok, f = pcall(io.open, getCfgPath(), "w")
    if ok and f then
        f:write("AUTORECONN=" .. (CONN.CFG.enabled and "1" or "0") .. "\n")
        f:close()
    end
end

function CONN.loadConfig()
    local ok, f = pcall(io.open, getCfgPath(), "r")
    if not ok or not f then return end
    local txt = f:read("*a"); f:close()
    if type(txt) ~= "string" then return end
    local v = txt:match("AUTORECONN=([01])")
    if v ~= nil then CONN.CFG.enabled = (v == "1") end
end

-- ============================================================================
-- 2. GAME CONNECTION PROBES
-- ============================================================================
function CONN.getCurrentWorld()
    local fns = { getCurrentWorldName, GetWorldName, getWorld, getCurrentWorld, GetWorld }
    for _, fn in ipairs(fns) do
        if type(fn) == "function" then
            local ok, res = pcall(fn)
            if ok and res ~= nil then
                if type(res) == "string" then
                    local nm = cleanWorld(res)
                    if nm ~= "" then return nm end
                elseif type(res) == "table" or type(res) == "userdata" then
                    local okN, nm = pcall(function() return res.name or res.worldName end)
                    if okN and type(nm) == "string" then
                        local c = cleanWorld(nm)
                        if c ~= "" then return c end
                    end
                end
            end
        end
    end
    return ""
end

function CONN.isPlayerOnline()
    local hasLocal = false
    if getLocal then
        local okL, me = pcall(getLocal)
        if okL and me ~= nil then hasLocal = true end
    else
        hasLocal = true
    end
    if not hasLocal then return false end
    local w = CONN.getCurrentWorld()
    return (w ~= "")
end

function CONN.setWarping(flag)
    CONN.STATE.is_warping = (flag == true)
end

function CONN.isReconnecting()
    return CONN.STATE.reconnecting == true
end

function CONN.clearFatal()
    CONN.STATE.fatal_stop = false
    CONN.STATE.fatal_reason = ""
    CONN.STATE.dc_flag = false
    CONN.STATE.dc_reason = ""
end

local function enableNativeAutoReconnect()
    if not editToggle then return end
    pcall(editToggle, "Auto Reconnect", true)
    pcall(editToggle, "AutoReconnect", true)
    pcall(editToggle, "Reconnect", true)
end

-- Cek apakah koneksi sedang terputus / terlempar ke EXIT secara tidak terduga
function CONN.needsReconnect(expectedWorld)
    if CONN.STATE.fatal_stop then return false end
    if CONN.STATE.is_warping then return false end
    if CONN.STATE.dc_flag then return true end
    if not CONN.isPlayerOnline() then return true end
    local exp = cleanWorld(expectedWorld)
    if exp ~= "" then
        local curW = CONN.getCurrentWorld()
        if curW == "" or curW == "EXIT" then
            return true
        end
    end
    return false
end

-- ============================================================================
-- 3. VARIANT LISTENER (DETEKSI PESAN DC / RECONNECT / FATAL BAN)
-- ============================================================================
function CONN.handleVariant(var)
    if type(var) ~= "table" and type(var) ~= "userdata" then return false end
    local v0, v1, v2 = nil, nil, nil
    pcall(function() v0 = var.v0 or var[0] end)
    pcall(function() v1 = var.v1 or var[1] end)
    pcall(function() v2 = var.v2 or var[2] end)

    local fn, payload = "", ""
    local s0, s1 = tostring(v0 or ""), tostring(v1 or "")
    if s0 == "OnConsoleMessage" or s0 == "OnTextOverlay" or s0 == "OnAddNotification" or s0 == "OnReconnect" then
        fn = s0; payload = tostring(v1 or "")
    elseif s1 == "OnConsoleMessage" or s1 == "OnTextOverlay" or s1 == "OnAddNotification" or s1 == "OnReconnect" then
        fn = s1; payload = tostring(v2 or "")
    end
    if fn == "" then return false end

    if fn == "OnReconnect" then
        CONN.STATE.dc_flag = true
        CONN.STATE.dc_reason = "Server OnReconnect"
        return false
    end

    local msg = stripColors(payload)
    if msg == "" then return false end
    local low = msg:lower()

    -- 1. Pesan fatal: JANGAN loop reconnect (hentikan semua bot demi keamanan akun)
    if low:find("suspended", 1, true)
        or low:find("account has been banned", 1, true)
        or low:find("permanently banned", 1, true)
        or low:find("under maintenance", 1, true)
        or low:find("server maintenance", 1, true)
        or low:find("update your game", 1, true)
        or low:find("update required", 1, true)
        or low:find("logged on from another", 1, true)
    then
        CONN.STATE.fatal_stop = true
        CONN.STATE.fatal_reason = msg
        CONN.STATE.reconnecting = false
        CONN.STATE.status_text = "STOP: " .. msg:sub(1, 36)
        logConn("`4[FATAL] `w" .. msg .. " -> Menghentikan semua bot otomatis.")
        if HUB_REF and type(HUB_REF.stopAll) == "function" then
            pcall(HUB_REF.stopAll)
        end
        return false
    end

    -- 2. Sinyal disconnect / koneksi terputus
    if low:find("disconnected", 1, true)
        or low:find("connection lost", 1, true)
        or low:find("lost connection", 1, true)
        or low:find("connection timed out", 1, true)
        or low:find("server overloaded", 1, true)
        or low:find("reconnecting", 1, true)
        or low:find("trying to connect", 1, true)
        or low:find("unable to connect", 1, true)
    then
        CONN.STATE.dc_flag = true
        CONN.STATE.dc_reason = msg
        return false
    end

    -- 3. Sinyal sudah kembali online normal
    if low:find("where would you like to go", 1, true) then
        if CONN.isPlayerOnline() then
            CONN.STATE.dc_flag = false
        end
    end
    return false
end

-- ============================================================================
-- 4. FREEZE SEMUA SC -> FOKUS RECONNECT -> VALIDASI ONLINE -> RESUME WORLD
-- ============================================================================
local function defaultWarp(worldName, doorID)
    local w = cleanWorld(worldName)
    local d = cleanWorld(doorID)
    if w == "" then return false end
    local joinStr = (d ~= "") and (w .. "|" .. d) or w
    for _ = 1, 3 do
        if sendPacket then
            pcall(sendPacket, 3, "action|join_request\nname|" .. joinStr .. "\ninvitedWorld|0\n")
        elseif growtopia and growtopia.warpTo then
            pcall(growtopia.warpTo, joinStr)
        end
        local el = 0
        while el < 6000 do
            safeSleep(250); el = el + 250
            if CONN.getCurrentWorld() == w then
                safeSleep(650)
                return true
            end
        end
        safeSleep(1500)
    end
    return (CONN.getCurrentWorld() == w)
end

-- Mengembalikan (okOnline: boolean, didReconnect: boolean)
-- opts = {
--   world     = "WORLDNAME",       -- world target untuk balik setelah online (opsional)
--   door      = "DOORID",          -- door ID (opsional)
--   isRunning = function() ... end,-- fungsi cek apakah bot pemanggil masih berjalan
--   onResume  = function() ... end,-- callback re-apply cheats/toggle setelah online
--   warpFn    = function(w, d) end,-- fungsi warp kustom milik modul (opsional)
-- }
function CONN.ensureOnline(opts)
    opts = opts or {}
    local targetW = cleanWorld(opts.world)
    local targetD = cleanWorld(opts.door)
    local function running()
        if type(opts.isRunning) == "function" then
            local ok, r = pcall(opts.isRunning)
            return ok and (r == true)
        end
        return true
    end

    if CONN.STATE.fatal_stop then
        return false, false
    end

    -- Fast-path 0ms saat koneksi sehat
    if not CONN.needsReconnect(targetW) then
        return true, false
    end

    -- Debounce singkat 1.5 detik (kecuali dc_flag sudah pasti dari server) agar tidak false-trigger saat micro-lag
    if not CONN.STATE.dc_flag then
        local db = 0
        while db < 1500 and running() and (not CONN.STATE.fatal_stop) do
            safeSleep(250); db = db + 250
            if not CONN.needsReconnect(targetW) then
                return true, false
            end
        end
    end

    if CONN.STATE.fatal_stop or (not running()) then
        return false, false
    end

    if not CONN.CFG.enabled then
        logConn("Disconnect terdeteksi (Auto Reconnect OFF) -> Bot dihentikan.")
        CONN.STATE.status_text = "Disconnected"
        return false, false
    end

    -- MASUK MODE FREEZE & FOKUS RECONNECT!
    CONN.STATE.reconnecting = true
    CONN.STATE.started_ms   = nowMs()
    CONN.STATE.attempts     = 0
    CONN.STATE.status_text  = "RECONNECTING..."

    local reason = (CONN.STATE.dc_reason ~= "") and CONN.STATE.dc_reason or "Terputus / keluar ke EXIT"
    logConn("`6Disconnect terdeteksi (" .. reason .. ")! Semua SC dijeda & fokus reconnect...")
    enableNativeAutoReconnect()

    local stableMs = 0
    local nextEnterMs = 0
    local backoffSteps = { 5000, 8000, 12000 }
    local loopElapsed = 0

    while running() and (not CONN.STATE.fatal_stop) do
        local onlineNow = CONN.isPlayerOnline() and (not CONN.STATE.dc_flag)
        if onlineNow then
            stableMs = stableMs + 300
            CONN.STATE.status_text = string.format("Online, verifikasi (%.1fs)...", stableMs / 1000.0)
            -- Pastikan stabil minimal 2.4 detik sebelum resume!
            if stableMs >= 2400 then
                break
            end
        else
            stableMs = 0
            local sec = math.floor(loopElapsed / 1000)
            CONN.STATE.status_text = string.format("RECONNECTING... (%ds)", sec)

            -- Nudge reconnect dengan backoff aman (5s -> 8s -> 12s) agar tidak spam login
            if loopElapsed >= nextEnterMs then
                CONN.STATE.attempts = CONN.STATE.attempts + 1
                enableNativeAutoReconnect()
                if (not CONN.isPlayerOnline()) and growtopia and growtopia.enter then
                    pcall(growtopia.enter)
                end
                -- Clear dc_flag setelah 1 percobaan agar bisa mendeteksi saat akun benar-benar kembali online
                if CONN.isPlayerOnline() then
                    CONN.STATE.dc_flag = false
                end
                local stepIdx = math.min(#backoffSteps, CONN.STATE.attempts)
                nextEnterMs = loopElapsed + backoffSteps[stepIdx]
            end
        end

        safeSleep(300)
        loopElapsed = loopElapsed + 300
    end

    if CONN.STATE.fatal_stop or (not running()) then
        CONN.STATE.reconnecting = false
        CONN.STATE.status_text = CONN.STATE.fatal_stop and ("STOP: " .. CONN.STATE.fatal_reason:sub(1, 30)) or "Idle"
        return false, false
    end

    -- KEMBALI ONLINE! Lepas freeze, re-apply cheats, dan warp balik ke world target!
    CONN.STATE.dc_flag      = false
    CONN.STATE.dc_reason    = ""
    CONN.STATE.reconnecting = false
    CONN.STATE.total_reconn = CONN.STATE.total_reconn + 1
    CONN.STATE.status_text  = "Online (Resuming...)"
    logConn("`2Kembali ONLINE! `wMemulihkan toggle & melanjutkan pekerjaan...")

    if type(opts.onResume) == "function" then
        pcall(opts.onResume)
    end

    if targetW ~= "" and CONN.getCurrentWorld() ~= targetW then
        CONN.STATE.is_warping = true
        local okW = false
        if type(opts.warpFn) == "function" then
            local okCall, wRes = pcall(opts.warpFn, targetW, targetD)
            okW = okCall and (wRes == true)
        else
            okW = defaultWarp(targetW, targetD)
        end
        CONN.STATE.is_warping = false

        if not okW then
            CONN.STATE.status_text = "Online"
            logConn("`6Gagal langsung masuk ulang ke " .. targetW .. ", akan dicoba ulang oleh modul.")
            return false, true
        end
        safeSleep(600)
        if type(opts.onResume) == "function" then
            pcall(opts.onResume)
        end
    end

    CONN.STATE.status_text = "Online"
    return true, true
end

function CONN.init(hub)
    HUB_REF = hub
    CONN.loadConfig()
    if CONN.CFG.enabled then
        enableNativeAutoReconnect()
    end
end

return CONN
