-- ============================================================================
-- LOADER BOREN STORE - AUTO DIRT FARM
-- File: loader_dirt_farm.lua
-- ============================================================================
-- Memuat script Auto Dirt Farm standalone (/df).
-- Dilengkapi auto-fetch dari GitHub, cache-busting, dan fallback file lokal.
-- ============================================================================

local RAW_URL = "https://raw.githubusercontent.com/rendhi69/sc_auto_df_growlauncher/main/auto_dirt_farm.lua"

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

logMsg("`9Menghubungkan ke GitHub dan memuat AUTO DIRT FARM...")
notifyUser("Memuat AUTO DIRT FARM...")

local content = nil
if fetch then
    local fetchUrl = RAW_URL .. "?v=" .. makeTag()
    local okF, res = pcall(fetch, fetchUrl)
    if okF and type(res) == "string" and res ~= "" and not res:match("^404") and not res:match("^<!DOCTYPE") then
        content = res
    end
end

if not content or content == "" then
    local candidatePaths = {
        "/storage/emulated/0/Android/media/launcher.powerkuy.growlauncher/ScriptLua/auto_dirt_farm.lua",
        "/storage/emulated/0/Android/data/launcher.powerkuy.growlauncher/files/ScriptLua/auto_dirt_farm.lua",
        "/storage/emulated/0/Download/auto_dirt_farm.lua",
        "script/script code/auto_dirt_farm.lua",
        "script/auto_dirt_farm.lua",
        "auto_dirt_farm.lua",
    }
    for _, p in ipairs(candidatePaths) do
        local okF, fh = pcall(io.open, p, "r")
        if okF and fh then
            local text = fh:read("*a")
            fh:close()
            if text and text ~= "" then
                content = text
                logMsg("`2File lokal berhasil dimuat dari: " .. p)
                break
            end
        end
    end
end

if not content or content == "" then
    local errMsg = "Gagal memuat auto_dirt_farm.lua! (Koneksi offline dan file lokal tidak ditemukan)."
    logMsg("`4" .. errMsg)
    notifyUser(errMsg)
    return
end

local loaderFn = loadstring or load
local chunk, loadErr = loaderFn(content)
if not chunk then
    local errMsg = "Error kompilasi script: " .. tostring(loadErr)
    logMsg("`4" .. errMsg)
    notifyUser(errMsg)
    return
end

local okExec, runErr = pcall(chunk)
if okExec then
    logMsg("`2AUTO DIRT FARM berhasil dimuat dan siap digunakan!")
    notifyUser("AUTO DIRT FARM Siap!")
else
    local errMsg = "Error runtime: " .. tostring(runErr)
    logMsg("`4" .. errMsg)
    notifyUser(errMsg)
end
