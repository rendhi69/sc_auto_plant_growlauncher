-- ============================================================================
-- LOADER BOREN STORE IMGUI (PERMANENT THIN LOADER - ZERO PATH MAINTENANCE)
-- File: loader_hub_imgui.lua
-- ============================================================================
-- Loader tipis ini TIDAK PERLU diubah lagi saat ada fitur baru di GitHub!
-- Seluruh daftar fitur, validasi modul GL (META), dan Hot-Reload dikelola
-- otomatis dari pusat: imgui_hub/boot.lua + imgui_hub/manifest.lua.
-- ============================================================================

local BASE_RAW_URL = "https://raw.githubusercontent.com/rendhi69/sc_auto_plant_growlauncher/main/"
local BOOT_PATH    = "imgui_hub/boot.lua"

local function makeTag()
    if getTime then
        local ok, ms = pcall(getTime)
        if ok and tonumber(ms) then return tostring(math.floor(tonumber(ms))) end
    end
    if os and os.time then
        local ok, t = pcall(os.time)
        if ok and tonumber(t) then return tostring(math.floor(tonumber(t))) end
    end
    return tostring(math.random(100000, 999999))
end

local function logMsg(msg)
    if LogToConsole then pcall(LogToConsole, "`e[BOREN STORE] `w" .. tostring(msg)) end
end

local function notifyMsg(msg)
    if sendNotification then pcall(sendNotification, tostring(msg))
    elseif growtopia and growtopia.notify then pcall(growtopia.notify, tostring(msg)) end
end

local code = nil
if fetch then
    local okF, res = pcall(fetch, BASE_RAW_URL .. BOOT_PATH .. "?v=" .. makeTag())
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
    logMsg("`4Gagal memuat BOREN STORE boot.lua! Cek koneksi internet.")
    notifyMsg("Gagal memuat BOREN STORE! Cek koneksi.")
    return
end

local loaderFn = loadstring or load
local chunk, err = loaderFn(code)
if not chunk then
    logMsg("`4Error kompilasi boot.lua: " .. tostring(err))
    return
end

local okRun, boot = pcall(chunk)
if not okRun or type(boot) ~= "table" or type(boot.start) ~= "function" then
    logMsg("`4Error menjalankan boot.lua: " .. tostring(boot))
    return
end

boot.start(BASE_RAW_URL)
