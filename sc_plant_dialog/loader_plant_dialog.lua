-- ============================================================================
-- LOADER BOREN STORE - AUTO PLANT & SPLICE (FULL IN-GAME DIALOG)
-- File: loader_plant_dialog.lua
-- Repo: https://github.com/rendhi69/sc_auto_plant_growlauncher
-- ============================================================================
-- 100% In-Game Growtopia Dialog murni (OnDialogRequest / action|dialog_return).
-- 0% ImGui, 0% Native GL Drawer. Ringan, anti-crash, dan responsif.
-- OFFLINE-FIRST: Cek file lokal di perangkat (PC & Android), jika tidak ada
-- otomatis fetch rilis terbaru langsung dari GitHub raw repo sc_auto_plant_growlauncher.
-- ============================================================================

local GITHUB_URL = "https://raw.githubusercontent.com/rendhi69/sc_auto_plant_growlauncher/main/sc_plant_dialog/auto_plant.lua"

local function logMsg(msg)
    if LogToConsole then pcall(LogToConsole, "`5[BOREN DIALOG] `w" .. tostring(msg)) end
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
-- 1. PRIORITAS UTAMA: OFFLINE-FIRST (CEK FILE LOKAL ANDROID & PC)
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

for _, p in ipairs(LOCAL_PATHS) do
    if p and p ~= "" then
        local okOpen, f = pcall(io.open, p, "r")
        if okOpen and f then
            local txt = f:read("*a")
            f:close()
            if txt and #txt > 100 then
                logMsg("Memuat skrip lokal: " .. tostring(p))
                local loaderFn = loadstring or load
                local chunk, err = loaderFn(txt)
                if chunk then
                    local okRun, rErr = pcall(chunk)
                    if okRun then
                        logMsg("`2Auto Plant In-Game Dialog Berhasil Aktif!")
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

-- ============================================================================
-- 2. CADANGAN: JIKA LOKAL TIDAK ADA, AMBIL DARI GITHUB RAW RESMI
-- ============================================================================
logMsg("`9File lokal tidak ditemukan, mengunduh dari GitHub raw...")
notifyUser("Mengunduh Auto Plant Dialog dari GitHub...")

local fetchUrl = GITHUB_URL .. "?t=" .. makeAntiCacheTag()
local fetcher = fetch or (http and http.get) or (client and client.fetch) or (growtopia and growtopia.fetch)

if not fetcher then
    logMsg("`4Gagal: Fungsi fetch/HTTP tidak didukung di Growlauncher ini.")
    notifyUser("Gagal fetch HTTP. Silakan letakkan file auto_plant.lua secara lokal!")
    return
end

local okFetch, res = pcall(fetcher, fetchUrl)
local content = nil
if okFetch and res then
    if type(res) == "string" then
        content = res
    elseif type(res) == "table" and res.body then
        content = res.body
    end
end

if not content or #content < 200 then
    logMsg("`4Gagal mengunduh skrip dari GitHub atau respon kosong.")
    notifyUser("Gagal mengunduh Auto Plant Dialog dari GitHub!")
    return
end

local loaderFn = loadstring or load
local chunk, err = loaderFn(content)
if not chunk then
    logMsg("`4Error kompilasi dari GitHub: " .. tostring(err))
    return
end

local okRun, rErr = pcall(chunk)
if okRun then
    logMsg("`2Auto Plant In-Game Dialog Berhasil Diunduh & Aktif!")
    notifyUser("Boren Auto Plant Siap! Ketik /plant di chat game.")
else
    logMsg("`4Error runtime saat eksekusi: " .. tostring(rErr))
end
