-- ============================================================================
-- LOADER BOREN STORE - AUTO PLANT & SPLICE (FULL IN-GAME DIALOG)
-- File: loader_plant_dialog.lua
-- Repo: https://github.com/rendhi69/sc_auto_plant_growlauncher
-- ============================================================================
-- 100% In-Game Growtopia Dialog murni (OnDialogRequest / action|dialog_return).
-- ONLINE-FIRST: Selalu mengambil pembaruan skrip langsung dari GitHub raw resmi.
-- Jika offline atau fetch gagal, otomatis fallback memuat file lokal perangkat.
-- Dilengkapi Fast Interceptor agar /plant & /p tidak pernah 'Unknown command'.
-- ============================================================================

local GITHUB_URL = "https://raw.githubusercontent.com/rendhi69/sc_auto_plant_growlauncher/main/sc_plant_dialog/auto_plant.lua"
local GITHUB_ROOT_URL = "https://raw.githubusercontent.com/rendhi69/sc_auto_plant_growlauncher/main/auto_plant.lua"

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
        current_dir = src:sub(2):match("^(.*[/\\])") or ""
    end
end

local LOCAL_PATHS = {
    current_dir .. "auto_plant.lua",
    current_dir .. "../sc_plant_dialog/auto_plant.lua",
    "script/sc_plant_dialog/auto_plant.lua",
    "sc_plant_dialog/auto_plant.lua",
    "auto_plant.lua",
    "/storage/emulated/0/Android/media/launcher.powerkuy.growlauncher/ScriptLua/sc_plant_dialog/auto_plant.lua",
    "/storage/emulated/0/Android/media/launcher.powerkuy.growlauncher/ScriptLua/auto_plant.lua",
    "/storage/emulated/0/Android/data/launcher.powerkuy.growlauncher/files/ScriptLua/sc_plant_dialog/auto_plant.lua",
    "/storage/emulated/0/Android/data/launcher.powerkuy.growlauncher/files/ScriptLua/auto_plant.lua",
    "/storage/emulated/0/Download/sc_plant_dialog/auto_plant.lua",
    "/storage/emulated/0/Download/auto_plant.lua",
}

-- ============================================================================
-- 1. PRIORITAS UTAMA: ONLINE-FIRST (SELALU UNDUH TERBARU DARI GITHUB RAW)
-- ============================================================================
logMsg("`9Menghubungkan ke GitHub untuk mengunduh Auto Plant Dialog terbaru...")
local fetcher = fetch or (http and http.get) or (client and client.fetch) or (growtopia and growtopia.fetch)
local content = nil

if fetcher then
    local fetchUrl = GITHUB_URL .. "?t=" .. makeAntiCacheTag()
    local okFetch, res = pcall(fetcher, fetchUrl)
    if okFetch and res then
        if type(res) == "string" and #res > 500 then
            content = res
        elseif type(res) == "table" and res.body and #res.body > 500 then
            content = res.body
        end
    end

    -- Jika URL subfolder gagal, coba URL root repo
    if not content or #content < 500 then
        local fetchUrlRoot = GITHUB_ROOT_URL .. "?t=" .. makeAntiCacheTag()
        local okF2, res2 = pcall(fetcher, fetchUrlRoot)
        if okF2 and res2 then
            if type(res2) == "string" and #res2 > 500 then
                content = res2
            elseif type(res2) == "table" and res2.body and #res2.body > 500 then
                content = res2.body
            end
        end
    end
end

if content and #content > 500 then
    logMsg("`2Berhasil mengunduh versi terbaru langsung dari GitHub!")

    -- Simpan otomatis ke file lokal perangkat agar file lokal selalu terbarui
    for _, p in ipairs(LOCAL_PATHS) do
        if p and p ~= "" then
            local okW, fW = pcall(io.open, p, "w")
            if okW and fW then
                pcall(function() fW:write(content) end)
                pcall(function() fW:close() end)
                break
            end
        end
    end

    local loaderFn = loadstring or load
    local chunk, err = loaderFn(content)
    if chunk then
        local okRun, rErr = pcall(chunk)
        if okRun then
            logMsg("`2Auto Plant In-Game Dialog Berhasil Aktif!")
            notifyUser("Boren Auto Plant Siap! Ketik /plant di chat game.")
            return
        else
            logMsg("`4Error runtime GitHub script: " .. tostring(rErr))
        end
    else
        logMsg("`4Error kompilasi GitHub script: " .. tostring(err))
    end
end

-- ============================================================================
-- 2. CADANGAN: JIKA GITHUB GAGAL / OFFLINE, FALLBACK KE FILE LOKAL
-- ============================================================================
logMsg("`6Koneksi GitHub tidak tersedia, memuat cadangan file lokal...")
for _, p in ipairs(LOCAL_PATHS) do
    if p and p ~= "" then
        local okOpen, f = pcall(io.open, p, "r")
        if okOpen and f then
            local txt = f:read("*a")
            f:close()
            if txt and #txt > 100 then
                logMsg("Memuat skrip cadangan lokal: " .. tostring(p))
                local loaderFn = loadstring or load
                local chunk, err = loaderFn(txt)
                if chunk then
                    local okRun, rErr = pcall(chunk)
                    if okRun then
                        logMsg("`2Auto Plant Cadangan Lokal Berhasil Aktif!")
                        notifyUser("Boren Auto Plant Siap! Ketik /plant di chat game.")
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

logMsg("`4Gagal memuat skrip dari GitHub maupun penyimpanan lokal!")
notifyUser("Gagal memuat Auto Plant Dialog!")
