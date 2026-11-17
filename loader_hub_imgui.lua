-- ============================================================================
-- LOADER BOREN STORE IMGUI - ALL-IN-ONE MODULAR (AUTO-FETCH, LOAD & HOT-RELOAD)
-- File: loader_hub_imgui.lua
-- ============================================================================
-- Ringan & 100% modular: memuat (load) tiap fitur dari file terpisah di GitHub
-- (Dashboard, Plant, Dirt Farm, Build Soil, Buy Pack + DebugPack DB) dan
-- mendukung Hot-Reload (Refresh Update) langsung dari Dashboard tanpa tutup GL!
-- ============================================================================

local BASE_RAW_URL = "https://raw.githubusercontent.com/rendhi69/sc_auto_plant_growlauncher/main/"
local reloadSeq = 0
local CACHE_TAG = ""

local function makeFreshTag()
    reloadSeq = reloadSeq + 1
    local t = nil
    if getTime then
        local okT, ms = pcall(getTime)
        if okT and tonumber(ms) then t = math.floor(tonumber(ms)) end
    end
    if not t and os and os.time then
        local okO, ot = pcall(os.time)
        if okO and tonumber(ot) then t = math.floor(tonumber(ot)) end
    end
    if not t and os and os.clock then
        local okC, oc = pcall(os.clock)
        if okC and tonumber(oc) then t = math.floor(tonumber(oc) * 1000) end
    end
    if not t then
        t = math.random(100000, 999999)
    end
    CACHE_TAG = tostring(t) .. "_" .. tostring(reloadSeq)
    return CACHE_TAG
end
makeFreshTag()

local function logMsg(msg)
    if LogToConsole then pcall(LogToConsole, "`e[BOREN STORE] `w" .. tostring(msg)) end
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
    BASE_RAW_URL    = BASE_RAW_URL,
    loadModule      = loadRemoteModule,
    fetchRawUrl     = fetchRawUrl,
    refreshCacheTag = makeFreshTag,
    reloading       = false,
    reload_seq      = 0,
    reload_status   = "Siap",
    tabs            = {},
    logs            = {},
    LINKS = {
        discord       = "https://discord.gg/2pGMQgeNue",
        github_repo   = "https://github.com/rendhi69/sc_auto_plant_growlauncher",
        raw_loader    = BASE_RAW_URL .. "loader_hub_imgui.lua",
        raw_debugpack = "https://raw.githubusercontent.com/rendhi69/data-_id_item/main/debugpack.txt",
    },
}

function HUB.addLog(line)
    table.insert(HUB.logs, 1, tostring(line or ""))
    if #HUB.logs > 80 then table.remove(HUB.logs) end
end

local function stopAllModules()
    for _, key in ipairs({ "plant", "dirt_farm", "build_soil", "buy_pack" }) do
        local m = HUB[key]
        if m and type(m.stop) == "function" then
            pcall(m.stop)
        end
    end
end

local function requireHubMod(stepLabel, relPath, optional)
    logMsg(stepLabel .. " memuat " .. relPath .. "...")
    local mod, err = loadRemoteModule(relPath)
    if not mod then
        logMsg("`4" .. tostring(err))
        if not optional then notifyMsg(tostring(err)) end
        return nil, err
    end
    return mod, nil
end

local function loadAllModulesSync(isReload)
    local mods = {
        { key = "plant",      step = "[1/5]", path = "imgui_hub/plant_engine.lua",     opt = false },
        { key = "dirt_farm",  step = "[2/5]", path = "imgui_hub/mod_dirt_farm.lua",    opt = true  },
        { key = "build_soil", step = "[3/5]", path = "imgui_hub/mod_soil_builder.lua", opt = true  },
        { key = "buy_pack",   step = "[4/5]", path = "imgui_hub/mod_buy_pack.lua",     opt = true  },
        { key = "ui",         step = "[5/5]", path = "imgui_hub/tab_plant.lua",        opt = false },
    }
    local loadedCnt, failCnt = 0, 0
    for _, item in ipairs(mods) do
        HUB.reload_status = (isReload and "Updating " or "Loading ") .. item.step .. "..."
        local mod = requireHubMod(item.step, item.path, item.opt)
        if mod then
            HUB[item.key] = mod
            if type(mod.init) == "function" then
                pcall(mod.init, HUB)
            end
            loadedCnt = loadedCnt + 1
        else
            failCnt = failCnt + 1
            if not item.opt then
                return false, loadedCnt, failCnt
            end
        end
    end
    return true, loadedCnt, failCnt
end

-- Hot-Reload semua modul langsung dari GitHub tanpa menutup Growlauncher!
function HUB.reloadAll(onDone)
    if HUB.reloading then return false end
    HUB.reloading = true
    HUB.reload_status = "Menghentikan bot & mengambil update..."

    local function runner()
        local ok, err = xpcall(function()
            stopAllModules()
            makeFreshTag()
            HUB.reload_seq = (tonumber(HUB.reload_seq) or 0) + 1
            HUB.addLog("[Refresh #" .. tostring(HUB.reload_seq) .. "] Mengambil update terbaru dari GitHub...")
            local okLoad, okCnt, failCnt = loadAllModulesSync(true)
            if okLoad then
                HUB.reload_status = string.format("Update OK #%d (%d modul)", HUB.reload_seq, okCnt)
                HUB.addLog("[Refresh OK] " .. tostring(okCnt) .. " modul dimuat ulang (gagal: " .. tostring(failCnt) .. ").")
                logMsg("`2Hot-Reload berhasil (#" .. tostring(HUB.reload_seq) .. ")!")
            else
                HUB.reload_status = "Update gagal! Cek koneksi."
                HUB.addLog("[Refresh GAGAL] Periksa koneksi internet / GitHub.")
            end
        end, function(e) return tostring(e) end)
        if not ok then
            HUB.reload_status = "Err: " .. tostring(err)
            HUB.addLog("[Refresh Error] " .. tostring(err))
        end
        HUB.reloading = false
        if type(onDone) == "function" then pcall(onDone, HUB.reload_status) end
    end

    if runCoroutine then
        pcall(runCoroutine, runner)
    else
        coroutine.resume(coroutine.create(runner))
    end
    return true
end

-- Boot awal saat loader dijalankan
local okBoot = loadAllModulesSync(false)
if okBoot then
    HUB.reload_status = "Siap (Terbaru)"
    logMsg("`2BOREN STORE siap digunakan! (/hub)")
    notifyMsg("BOREN STORE Siap! (/hub)")
end
