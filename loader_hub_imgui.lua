-- ============================================================================
-- LOADER BOREN HUB IMGUI - ALL-IN-ONE MODULAR (AUTO-FETCH & LOAD DARI GITHUB)
-- File: loader_hub_imgui.lua
-- ============================================================================
-- Ringan & 100% modular: hanya memuat (load) tiap fitur dari file terpisah di
-- GitHub (Plant, Dirt Farm, Build Soil, Buy Pack + DebugPack DB).
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

local function fetchRawUrl(fullUrl)
    if not fetch then return nil end
    local sep = fullUrl:find("?", 1, true) and "&" or "?"
    local okF, res = pcall(fetch, fullUrl .. sep .. "v=" .. CACHE_TAG)
    if okF and type(res) == "string" and res ~= "" and not res:match("^404") and not res:match("^<!DOCTYPE") then
        return res
    end
    return nil
end

local function loadRemoteModule(relPath)
    local code = fetchRawUrl(BASE_RAW_URL .. relPath)

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
    loadModule  = loadRemoteModule,
    fetchRawUrl = fetchRawUrl,
    tabs        = {},
    logs        = {},
}

function HUB.addLog(line)
    table.insert(HUB.logs, 1, tostring(line or ""))
    if #HUB.logs > 80 then table.remove(HUB.logs) end
end

local function requireHubMod(stepLabel, relPath, optional)
    logMsg(stepLabel .. " memuat " .. relPath .. "...")
    local mod, err = loadRemoteModule(relPath)
    if not mod then
        logMsg("`4" .. tostring(err))
        if not optional then notifyMsg(tostring(err)) end
        return nil
    end
    return mod
end

-- [1/5] Modul Engine Auto Plant
HUB.plant = requireHubMod("[1/5]", "imgui_hub/plant_engine.lua", false)
if not HUB.plant then return end
HUB.plant.init(HUB)

-- [2/5] Modul Auto Dirt Farm (Engine + UI)
HUB.dirt_farm = requireHubMod("[2/5]", "imgui_hub/mod_dirt_farm.lua", true)
if HUB.dirt_farm and HUB.dirt_farm.init then HUB.dirt_farm.init(HUB) end

-- [3/5] Modul Auto Build Soil (Engine + UI)
HUB.build_soil = requireHubMod("[3/5]", "imgui_hub/mod_soil_builder.lua", true)
if HUB.build_soil and HUB.build_soil.init then HUB.build_soil.init(HUB) end

-- [4/5] Modul Auto Buy Pack (Engine + UI + DebugPack GitHub DB)
HUB.buy_pack = requireHubMod("[4/5]", "imgui_hub/mod_buy_pack.lua", true)
if HUB.buy_pack and HUB.buy_pack.init then HUB.buy_pack.init(HUB) end

-- [5/5] Modul Shell Hub + Sidebar + UI Plant + Hooks
HUB.ui = requireHubMod("[5/5]", "imgui_hub/tab_plant.lua", false)
if not HUB.ui then return end
HUB.ui.init(HUB)

logMsg("`2Boren Hub (Plant, Dirt Farm, Build Soil, Buy Pack) siap! (/hub)")
notifyMsg("Boren Hub All-in-One Siap! (/hub)")
