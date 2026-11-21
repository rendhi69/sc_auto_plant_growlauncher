-- ============================================================================
-- LOADER BOREN STORE - DASHBOARD UTAMA (IMGUI HUB)
-- File: loader_hub_imgui.lua
-- ============================================================================
-- Memuat seluruh Dashboard Boren Store ImGui Hub (Kompatibilitas Loader Lama).
-- Dilengkapi auto-fetch dari GitHub, cache-busting, dan fallback file lokal.
-- ============================================================================

local BASE_URL = "https://raw.githubusercontent.com/rendhi69/sc_auto_plant_growlauncher/main/"
local BOOT_PATH = "imgui_hub/boot.lua"

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
    if LogToConsole then pcall(LogToConsole, "`e[BOREN DASHBOARD] `w" .. tostring(msg)) end
end

local function notifyUser(msg)
    if sendNotification then pcall(sendNotification, tostring(msg))
    elseif growtopia and growtopia.notify then pcall(growtopia.notify, tostring(msg)) end
end

logMsg("`9Menghubungkan ke GitHub dan memuat Dashboard...")
notifyUser("Memuat Dashboard Boren Store...")

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
    logMsg("`4Gagal memuat Dashboard! Periksa koneksi internet / file lokal.")
    notifyUser("Gagal memuat Dashboard!")
    return
end

local loaderFn = loadstring or load
local chunk, err = loaderFn(code)
if not chunk then
    logMsg("`4Error kompilasi core dashboard: " .. tostring(err))
    notifyUser("Error kompilasi dashboard!")
    return
end

local okRun, boot = pcall(chunk)
if not okRun or type(boot) ~= "table" or type(boot.start) ~= "function" then
    logMsg("`4Error inisialisasi boot: " .. tostring(boot))
    notifyUser("Error inisialisasi dashboard!")
    return
end

boot.start(BASE_URL)
logMsg("`2Dashboard Boren Store ImGui Hub Siap Digunakan!")
notifyUser("Dashboard Siap!")
