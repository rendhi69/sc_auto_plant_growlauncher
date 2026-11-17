-- ============================================================================
-- LOADER BOREN HUB IMGUI (MODULAR AUTO-FETCH & LOAD DARI GITHUB)
-- File: loader_hub_imgui.lua
-- ============================================================================
-- Skrip ringan ini HANYA bertugas memuat (load) modul-modul terpisah dari
-- GitHub (tidak menumpuk full code dalam satu file).
-- Setiap modul (tema, engine plant, tab UI, shell hub) terpisah rapi di folder
-- imgui_hub/ pada repository GitHub.
-- ============================================================================

local BASE_RAW_URL = "https://raw.githubusercontent.com/rendhi69/sc_auto_plant_growlauncher/main/"
local CACHE_TAG = tostring(math.floor((os and os.time and os.time()) or (os and os.clock and os.clock() * 1000) or math.random(100000, 999999)))

local function logMsg(msg)
    if LogToConsole then pcall(LogToConsole, "`e[Boren Hub Loader] `w" .. tostring(msg)) end
end

local function notifyMsg(msg)
    if sendNotification then pcall(sendNotification, tostring(msg))
    elseif growtopia and growtopia.notify then pcall(growtopia.notify, tostring(msg)) end
end

-- Fungsi pemuat modul dinamis (Online GitHub + Fallback Lokal)
local function loadRemoteModule(relPath)
    local url = BASE_RAW_URL .. relPath .. "?v=" .. CACHE_TAG
    local code = nil

    if fetch then
        local okF, res = pcall(fetch, url)
        if okF and type(res) == "string" and res ~= "" and not res:match("^404") and not res:match("^<!DOCTYPE") then
            code = res
        end
    end

    if not code or code == "" then
        local localRoots = {
            "/storage/emulated/0/Android/media/launcher.powerkuy.growlauncher/ScriptLua/",
            "/storage/emulated/0/Android/data/launcher.powerkuy.growlauncher/files/ScriptLua/",
            "/storage/emulated/0/Download/",
            "d:/rotasi 2026/SC LAMA OLD JUTUN/sc growlauncher/script/",
            "script/",
            "",
        }
        for _, root in ipairs(localRoots) do
            local okO, f = pcall(io.open, root .. relPath, "r")
            if okO and f then
                local txt = f:read("*a")
                f:close()
                if txt and txt ~= "" then
                    code = txt
                    break
                end
            end
        end
    end

    if not code or code == "" then
        return nil, "Gagal mengunduh / menemukan modul: " .. relPath
    end

    local loaderFn = loadstring or load
    local chunk, compileErr = loaderFn(code, "@" .. relPath)
    if not chunk then
        return nil, "Error kompilasi " .. relPath .. ": " .. tostring(compileErr)
    end

    local okRun, modOrErr = pcall(chunk)
    if not okRun then
        return nil, "Error runtime " .. relPath .. ": " .. tostring(modOrErr)
    end

    return modOrErr, nil
end

-- ============================================================================
-- BOOTSTRAP MODULAR HUB
-- ============================================================================
logMsg("Memuat modul Boren Hub ImGui dari GitHub...")
notifyMsg("Memuat Boren Hub ImGui...")

local HUB = {
    loadModule = loadRemoteModule,
    tabs       = {},
    logs       = {},
}

function HUB.addLog(line)
    table.insert(HUB.logs, 1, tostring(line or ""))
    if #HUB.logs > 80 then
        table.remove(HUB.logs)
    end
end

local function requireHubMod(relPath)
    local mod, err = loadRemoteModule(relPath)
    if not mod then
        logMsg("`4" .. tostring(err))
        notifyMsg(tostring(err))
        return nil
    end
    return mod
end

-- 1. Muat Tema & Widget ImGui
HUB.widgets = requireHubMod("imgui_hub/theme_widgets.lua")
if not HUB.widgets then return end

-- 2. Muat Engine Auto Plant (terpisah dari UI)
HUB.plant = requireHubMod("imgui_hub/plant_engine.lua")
if not HUB.plant then return end
HUB.plant.init(HUB)

-- 3. Muat Tab UI Plant & daftarkan ke Sidebar Hub
local tabPlant = requireHubMod("imgui_hub/tab_plant.lua")
if not tabPlant then return end
table.insert(HUB.tabs, tabPlant)

-- 4. Muat Shell Utama Hub (Sidebar + Window + Hook ImGui)
HUB.shell = requireHubMod("imgui_hub/hub_shell.lua")
if not HUB.shell then return end
HUB.shell.init(HUB)

logMsg("`2Boren Hub ImGui berhasil dimuat! (Ketik /hub di chat untuk buka/tutup)")
notifyMsg("Boren Hub ImGui Siap! (Ketik /hub)")
