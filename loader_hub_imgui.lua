-- ============================================================================
-- LOADER BOREN HUB IMGUI (MODULAR AUTO-FETCH & LOAD DARI GITHUB)
-- File: loader_hub_imgui.lua
-- ============================================================================
-- Ringan & modular: hanya melakukan fetch + load modul Engine dan modul UI
-- secara terpisah dari GitHub (tanpa full code di satu file).
-- ============================================================================

local BASE_RAW_URL = "https://raw.githubusercontent.com/rendhi69/sc_auto_plant_growlauncher/main/"
local CACHE_TAG = tostring(math.floor((os and os.time and os.time()) or (os and os.clock and os.clock() * 1000) or math.random(100000, 999999)))

local function logMsg(msg)
    if LogToConsole then pcall(LogToConsole, "`e[Boren Hub] `w" .. tostring(msg)) end
end

local function notifyMsg(msg)
    if sendNotification then pcall(sendNotification, tostring(msg))
    elseif growtopia and growtopia.notify then pcall(growtopia.notify, tostring(msg)) end
end

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
        return nil, "Gagal memuat modul: " .. relPath
    end

    local loaderFn = loadstring or load
    local chunk, compileErr = loaderFn(code)
    if not chunk then
        return nil, "Error kompilasi " .. relPath .. ": " .. tostring(compileErr)
    end

    local okRun, modOrErr = pcall(chunk)
    if not okRun then
        return nil, "Error runtime " .. relPath .. ": " .. tostring(modOrErr)
    end

    return modOrErr, nil
end

local HUB = {
    loadModule = loadRemoteModule,
    tabs       = {},
    logs       = {},
}

function HUB.addLog(line)
    table.insert(HUB.logs, 1, tostring(line or ""))
    if #HUB.logs > 60 then table.remove(HUB.logs) end
end

local function requireHubMod(stepLabel, relPath)
    logMsg(stepLabel .. " memuat " .. relPath .. "...")
    local mod, err = loadRemoteModule(relPath)
    if not mod then
        logMsg("`4" .. tostring(err))
        notifyMsg(tostring(err))
        return nil
    end
    return mod
end

-- [1/2] Muat Modul Engine Auto Plant
HUB.plant = requireHubMod("[1/2]", "imgui_hub/plant_engine.lua")
if not HUB.plant then return end
HUB.plant.init(HUB)

-- [2/2] Muat Modul UI ImGui (Plant / Settings / Logs)
HUB.ui = requireHubMod("[2/2]", "imgui_hub/tab_plant.lua")
if not HUB.ui then return end
HUB.ui.init(HUB)

logMsg("`2Boren Hub ImGui siap! (Ketik /hub di chat untuk buka/tutup)")
notifyMsg("Boren Hub ImGui Siap! (/hub)")
