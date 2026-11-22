-- ============================================================================
-- LOADER BOREN STORE - AUTO PLANT & SPLICE (NATIVE UI GROWLAUNCHER)
-- File: loader_plant_native.lua
-- ============================================================================
-- Memuat antarmuka Native Menu bawaan Growlauncher (Tab 'Boren Plant').
-- Menempel di sidebar / drawer menu Growlauncher.
-- Dilengkapi auto-fetch GitHub, cache-busting, dan fallback file lokal.
-- ============================================================================

local BASE_URL = "https://raw.githubusercontent.com/rendhi69/sc_auto_plant_growlauncher/main/"
local TARGET_FILE = "sc_plant_native/auto_plant.lua"
local FALLBACK_FILE = "auto_plant.lua"

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
    if LogToConsole then pcall(LogToConsole, "`e[BOREN PLANT NATIVE] `w" .. tostring(msg)) end
end

local function notifyUser(msg)
    if sendNotification then pcall(sendNotification, tostring(msg))
    elseif growtopia and growtopia.notify then pcall(growtopia.notify, tostring(msg)) end
end

logMsg("`9Menghubungkan ke GitHub dan memuat Script AUTO PLANT (NATIVE UI)...")
notifyUser("Memuat AUTO PLANT (NATIVE UI)...")

local code = nil
if fetch then
    local urls = {
        BASE_URL .. TARGET_FILE .. "?v=" .. makeTag(),
        BASE_URL .. FALLBACK_FILE .. "?v=" .. makeTag()
    }
    for _, u in ipairs(urls) do
        local okF, res = pcall(fetch, u)
        if okF and type(res) == "string" and res ~= "" and not res:match("^404") and not res:match("^<!DOCTYPE") then
            code = res
            break
        end
    end
end

if not code or code == "" then
    local localRoots = {
        "/storage/emulated/0/Android/media/launcher.powerkuy.growlauncher/ScriptLua/",
        "/storage/emulated/0/Android/data/launcher.powerkuy.growlauncher/files/ScriptLua/",
        "/storage/emulated/0/Download/",
        "script/script done dont edit/sc_plant_native/",
        "script/script done dont edit/sc plant/",
        "script/",
        "",
    }
    for _, root in ipairs(localRoots) do
        for _, fname in ipairs({ TARGET_FILE, FALLBACK_FILE, "auto_plant.lua" }) do
            local okO, f = pcall(io.open, root .. fname, "r")
            if okO and f then
                local txt = f:read("*a")
                f:close()
                if txt and txt ~= "" then code = txt; break end
            end
        end
        if code and code ~= "" then break end
    end
end

if not code or code == "" then
    logMsg("`4Gagal memuat Script AUTO PLANT NATIVE! Periksa koneksi internet / file lokal.")
    notifyUser("Gagal memuat Script Native!")
    return
end

local loaderFn = loadstring or load
local chunk, err = loaderFn(code)
if not chunk then
    logMsg("`4Error kompilasi script: " .. tostring(err))
    notifyUser("Error kompilasi script native!")
    return
end

local okRun, ret = pcall(chunk)
if not okRun then
    logMsg("`4Error menjalankan script: " .. tostring(ret))
    notifyUser("Error eksekusi script native!")
    return
end

logMsg("`2Menu Boren Plant (NATIVE UI) Berhasil Dimuat ke Growlauncher!")
notifyUser("Boren Plant (Native) Siap!")
