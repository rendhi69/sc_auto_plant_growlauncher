-- ============================================================================
-- LOADER BOREN STORE - AUTO DIRT FARM (CONSOLE IMGUI)
-- File: loader_dirt_farm.lua
-- ============================================================================
-- Memuat antarmuka Console ImGui khusus Auto Dirt Farm.
-- 100% Berbasis antarmuka Console ImGui Modern (Bukan Menu Native Lama).
-- Dilengkapi auto-fetch dari GitHub, cache-busting, dan fallback file lokal.
-- ============================================================================

local BASE_URL = "https://raw.githubusercontent.com/rendhi69/sc_auto_plant_growlauncher/main/"
local BOOT_PATH = "imgui_hub/boot.lua"
local TARGET_FEATURE = "dirt_farm"

-- Set target fitur awal & mode fokus console
_G.__BOREN_INITIAL_FEATURE = TARGET_FEATURE
_G.__BOREN_SINGLE_FEATURE = "dirt_farm"

local function makeTag()
    if getTime then
        local ok, ms = pcall(getTime)
        if ok and tonumber(ms) then return tostring(math.floor(tonumber(ms))) end
    end
    if os and os.time then
        local ok, t = pcall(os.time)
        if ok and tonumber(t) then return tostring(math.floor(tonumber(t))) end
    end
    if os and os.clock then
        local ok, c = pcall(os.clock)
        if ok and tonumber(c) then return tostring(math.floor(tonumber(c) * 1000)) end
    end
    return tostring(math.random(100000, 999999))
end

local function logMsg(msg)
    if LogToConsole then pcall(LogToConsole, "`e[BOREN DIRT FARM] `w" .. tostring(msg)) end
end

local function notifyUser(msg)
    if sendNotification then pcall(sendNotification, tostring(msg))
    elseif growtopia and growtopia.notify then pcall(growtopia.notify, tostring(msg)) end
end

logMsg("`9Menghubungkan ke GitHub dan memuat Console AUTO DIRT FARM...")
notifyUser("Memuat Console AUTO DIRT FARM...")

local code = nil
if fetch then
    local fetchUrl = BASE_URL .. BOOT_PATH .. "?v=" .. makeTag()
    local okF, res = pcall(fetch, fetchUrl)
    if okF and type(res) == "string" and res ~= "" and not res:match("^404") and not res:match("^<!DOCTYPE") then
        code = res
    end
end

if not code or code == "" then
    local localRoots = {
        "/storage/emulated/0/Android/media/launcher.powerkuy.growlauncher/ScriptLua/",
        "/storage/emulated/0/Android/data/launcher.powerkuy.growlauncher/files/ScriptLua/",
        "/storage/emulated/0/Download/",
        "script/",
        "",
    }
    for _, root in ipairs(localRoots) do
        local okO, f = pcall(io.open, root .. BOOT_PATH, "r")
        if okO and f then
            local txt = f:read("*a")
            f:close()
            if txt and txt ~= "" then code = txt; break end
        end
    end
end

if not code or code == "" then
    logMsg("`4Gagal memuat Console AUTO DIRT FARM! Periksa koneksi internet / file lokal.")
    notifyUser("Gagal memuat Console!")
    return
end

local loaderFn = loadstring or load
local chunk, err = loaderFn(code)
if not chunk then
    logMsg("`4Error kompilasi boot console: " .. tostring(err))
    notifyUser("Error kompilasi console!")
    return
end

local okRun, boot = pcall(chunk)
if not okRun or type(boot) ~= "table" or type(boot.start) ~= "function" then
    logMsg("`4Error inisialisasi boot: " .. tostring(boot))
    notifyUser("Error inisialisasi console!")
    return
end

boot.start(BASE_URL, TARGET_FEATURE)
logMsg("`2Console AUTO DIRT FARM Siap Digunakan!")
notifyUser("Console AUTO DIRT FARM Siap!")
