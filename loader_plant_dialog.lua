-- ============================================================================
-- LOADER BOREN STORE - AUTO PLANT & SPLICE (FULL IN-GAME DIALOG)
-- File: loader_plant_dialog.lua
-- Repo: https://github.com/rendhi69/sc_auto_plant_growlauncher
-- ============================================================================
-- 100% In-Game Growtopia Dialog murni (OnDialogRequest / action|dialog_return).
-- ONLINE-FIRST: Selalu mengambil pembaruan skrip langsung dari GitHub / CDN resmi.
-- Dilengkapi multi-fallback (jsDelivr CDN + GitHub raw) bebas blokir ISP.
-- Jika offline atau fetch gagal, otomatis fallback memuat file lokal perangkat.
-- Dilengkapi Fast Interceptor agar /plant & /p tidak pernah 'Unknown command'.
-- ============================================================================

local function logMsg(msg)
    if LogToConsole then pcall(LogToConsole, "`5[BOREN LOADER] `w" .. tostring(msg)) end
end

local function notifyUser(msg)
    if sendNotification then pcall(sendNotification, tostring(msg))
    elseif growtopia and growtopia.notify then pcall(growtopia.notify, tostring(msg)) end
end

local function makeAntiCacheTag()
    local t = ""
    if getTime then
        local ok, ms = pcall(getTime)
        if ok and tonumber(ms) then t = tostring(math.floor(tonumber(ms))) end
    end
    if t == "" and os and os.time then
        local ok, s = pcall(os.time)
        if ok and tonumber(s) then t = tostring(math.floor(tonumber(s))) end
    end
    if t == "" then
        t = tostring(math.random(100000, 999999))
    end
    return t
end

-- ============================================================================
-- FAST CHAT INTERCEPTOR DI TINGKAT LOADER (/plant, /p, /boren, /menu)
-- Mencegah munculnya 'Unknown command' di chat game sejak detik pertama
-- ============================================================================
local function loaderFastPacketHook(arg1, arg2)
    local pStr = nil
    local pType = nil
    if type(arg1) == "string" then
        pStr = arg1
        pType = (type(arg2) == "number") and arg2 or nil
    elseif type(arg2) == "string" then
        pStr = arg2
        pType = (type(arg1) == "number") and arg1 or nil
    elseif type(arg1) == "table" then
        pStr = arg1.str or arg1.packet or arg1.text or arg1.data or arg1[2] or arg1[1]
        pType = tonumber(arg1.type)
    elseif type(arg2) == "table" then
        pStr = arg2.str or arg2.packet or arg2.text or arg2.data or arg2[2] or arg2[1]
        pType = tonumber(arg2.type)
    end

    if not pStr or type(pStr) ~= "string" then return false end

    -- Intersepsi Chat Command /plant, /p, /boren, /menu
    local lowerP = pStr:lower()
    if lowerP:find("/plant", 1, true) or lowerP:find("/p", 1, true) or lowerP:find("/boren", 1, true) or lowerP:find("/menu", 1, true) then
        if lowerP:find("action|input", 1, true) or lowerP:find("text|/", 1, true) or lowerP:find("action|chat", 1, true) or lowerP:sub(1, 1) == "/" then
            local cmd = lowerP:match("|text|(/[a-z0-9_]+)") or lowerP:match("text|(/[a-z0-9_]+)") or lowerP:match("(/[a-z0-9_]+)")
            if cmd == "/plant" or cmd == "/p" or cmd == "/menu" or cmd == "/boren" or cmd == "/dialog" then
                local openFn = _G.showPlantMainDialog or showPlantMainDialog
                if openFn then
                    pcall(openFn)
                    logMsg("`2Menu Dialog dibuka via chat: `e" .. tostring(cmd))
                else
                    notifyUser("Auto Plant sedang dimuat... ketik /plant lagi sebentar!")
                end
                return true -- SELALU BLOKIR agar tidak muncul Unknown command di server!
            end
        end
    end

    -- Intersepsi Dialog Return
    if pStr:find("action|dialog_return", 1, true) then
        local handler = _G.handleDialogReturn or handleDialogReturn
        if handler and handler(pStr) then
            return true
        end
    end

    return false
end

-- Pasang Fast Hook ke semua varian hook engine Growlauncher
local hookFuncs = { addHook, AddHook, hook, Hook }
for _, h in ipairs(hookFuncs) do
    if type(h) == "function" then
        pcall(h, loaderFastPacketHook, "onsendpacket")
        pcall(h, loaderFastPacketHook, "onSendPacket")
        pcall(h, loaderFastPacketHook, "OnSendPacket")
        pcall(h, "onsendpacket", loaderFastPacketHook)
        pcall(h, "onSendPacket", loaderFastPacketHook)
        pcall(h, "OnSendPacket", loaderFastPacketHook)
        pcall(h, "onsendpacket", "boren_loader_hook", loaderFastPacketHook)
        pcall(h, "onSendPacket", "boren_loader_hook", loaderFastPacketHook)
        pcall(h, "OnSendPacket", "boren_loader_hook", loaderFastPacketHook)
    end
end
if AddHookCallback then
    pcall(AddHookCallback, loaderFastPacketHook, "onsendpacket")
    pcall(AddHookCallback, loaderFastPacketHook, "onSendPacket")
    pcall(AddHookCallback, "onsendpacket", loaderFastPacketHook)
    pcall(AddHookCallback, "onSendPacket", loaderFastPacketHook)
end
onSendPacket = loaderFastPacketHook
OnSendPacket = loaderFastPacketHook
_G.onSendPacket = loaderFastPacketHook
_G.OnSendPacket = loaderFastPacketHook
if applyHook then pcall(applyHook) end
if ApplyHook then pcall(ApplyHook) end

-- ============================================================================
-- DAFTAR JALUR LOKAL PERANGKAT (PC & ANDROID)
-- ============================================================================
local current_dir = ""
if debug and debug.getinfo then
    local src = debug.getinfo(1, "S").source
    if src and src:sub(1, 1) == "@" then
        current_dir = src:sub(2):match([=[^(.*[/\])]=]) or ""
    end
end

local LOCAL_PATHS = {
    current_dir .. "auto_plant.lua",
    current_dir .. "../dialog/plant/auto_plant.lua",
    current_dir .. "../sc_plant_dialog/auto_plant.lua",
    "script/dialog/plant/auto_plant.lua",
    "script/sc_plant_dialog/auto_plant.lua",
    "sc_plant_dialog/auto_plant.lua",
    "auto_plant.lua",
    "/storage/emulated/0/Android/media/launcher.powerkuy.growlauncher/ScriptLua/sc_plant_dialog/auto_plant.lua",
    "/storage/emulated/0/Android/media/launcher.powerkuy.growlauncher/ScriptLua/dialog/plant/auto_plant.lua",
    "/storage/emulated/0/Android/media/launcher.powerkuy.growlauncher/ScriptLua/auto_plant.lua",
    "/storage/emulated/0/Android/data/launcher.powerkuy.growlauncher/files/ScriptLua/sc_plant_dialog/auto_plant.lua",
    "/storage/emulated/0/Android/data/launcher.powerkuy.growlauncher/files/ScriptLua/dialog/plant/auto_plant.lua",
    "/storage/emulated/0/Android/data/launcher.powerkuy.growlauncher/files/ScriptLua/auto_plant.lua",
    "/storage/emulated/0/Download/sc_plant_dialog/auto_plant.lua",
    "/storage/emulated/0/Download/dialog/plant/auto_plant.lua",
    "/storage/emulated/0/Download/auto_plant.lua",
}

-- ============================================================================
-- 1. PRIORITAS UTAMA: ONLINE-FIRST (CDN & GITHUB RAW RESMI)
-- ============================================================================
local ONLINE_URLS = {
    -- 1. jsDelivr CDN (Sangat cepat di Asia Tenggara & bebas blokir ISP Indonesia)
    "https://cdn.jsdelivr.net/gh/rendhi69/sc_auto_plant_growlauncher@main/auto_plant.lua",
    "https://cdn.jsdelivr.net/gh/rendhi69/sc_auto_plant_growlauncher@main/sc_plant_dialog/auto_plant.lua",
    -- 2. GitHub Raw Canonical (Format resmi dokumentasi Growlauncher)
    "https://raw.githubusercontent.com/rendhi69/sc_auto_plant_growlauncher/refs/heads/main/auto_plant.lua",
    "https://raw.githubusercontent.com/rendhi69/sc_auto_plant_growlauncher/refs/heads/main/sc_plant_dialog/auto_plant.lua",
    -- 3. GitHub Raw Standard
    "https://raw.githubusercontent.com/rendhi69/sc_auto_plant_growlauncher/main/auto_plant.lua"
}

logMsg("`9Menghubungkan ke server untuk mengunduh Auto Plant Dialog terbaru (v2.3)...")
local fetcher = fetch or (http and http.get) or (client and client.fetch) or (growtopia and growtopia.fetch)
local content = nil
local fetchedSource = ""

if fetcher then
    for _, u in ipairs(ONLINE_URLS) do
        -- Coba URL bersih terlebih dahulu (tanpa query string agar libcurl/fetch tidak error)
        local okFetch, res = pcall(fetcher, u)
        if okFetch and res then
            if type(res) == "string" and #res > 500 then
                content = res
                fetchedSource = u
                break
            elseif type(res) == "table" and res.body and #res.body > 500 then
                content = res.body
                fetchedSource = u
                break
            end
        end

        -- Coba varian anti-cache jika URL bersih gagal
        local tag = makeAntiCacheTag()
        local okF2, res2 = pcall(fetcher, u .. "?t=" .. tag)
        if okF2 and res2 then
            if type(res2) == "string" and #res2 > 500 then
                content = res2
                fetchedSource = u
                break
            elseif type(res2) == "table" and res2.body and #res2.body > 500 then
                content = res2.body
                fetchedSource = u
                break
            end
        end
    end
end

if content and #content > 500 then
    logMsg("`2Berhasil mengunduh Auto Plant terbaru (" .. tostring(#content) .. " bytes)!")

    -- Simpan otomatis ke file lokal perangkat agar cache selalu sinkron dengan server
    for _, p in ipairs(LOCAL_PATHS) do
        if p and p ~= "" then
            local okW, fW = pcall(io.open, p, "w")
            if okW and fW then
                pcall(function() fW:write(content) end)
                pcall(function() fW:close() end)
            end
        end
    end

    local loaderFn = loadstring or load
    local chunk, err = loaderFn(content)
    if chunk then
        local okRun, rErr = pcall(chunk)
        if okRun then
            logMsg("`2[ONLINE] Auto Plant v2.3 In-Game Dialog Berhasil Aktif!")
            notifyUser("`2[ONLINE] Auto Plant v2.3 Siap! Ketik /plant.")
            return
        else
            logMsg("`4Error runtime GitHub script: " .. tostring(rErr))
        end
    else
        logMsg("`4Error kompilasi GitHub script: " .. tostring(err))
    end
end

-- ============================================================================
-- 2. CADANGAN: JIKA SERVER ONLINE GAGAL / OFFLINE, FALLBACK KE FILE LOKAL
-- ============================================================================
logMsg("`4[PERINGATAN] Server online tidak merespon! Memuat cadangan file lokal...")
for _, p in ipairs(LOCAL_PATHS) do
    if p and p ~= "" then
        local okOpen, f = pcall(io.open, p, "r")
        if okOpen and f then
            local txt = f:read("*a")
            f:close()
            if txt and #txt > 100 then
                logMsg("`6Memuat skrip cadangan lokal: " .. tostring(p))
                local loaderFn = loadstring or load
                local chunk, err = loaderFn(txt)
                if chunk then
                    local okRun, rErr = pcall(chunk)
                    if okRun then
                        logMsg("`3[LOKAL] Auto Plant Cadangan Lokal Berhasil Aktif!")
                        notifyUser("`4[LOKAL] File lokal dimuat (Bukan online terbaru)!")
                        return
                    else
                        logMsg("`4Error runtime lokal: " .. tostring(rErr))
                    end
                else
                    logMsg("`4Error kompilasi lokal: " .. tostring(err))
                end
            end
        end
    end
end

logMsg("`4Gagal memuat skrip dari server online maupun penyimpanan lokal!")
notifyUser("`4Gagal memuat Auto Plant Dialog!")
