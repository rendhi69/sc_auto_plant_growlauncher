-- ============================================================================
-- BOREN STORE - REMOTE BOOTLOADER & DYNAMIC FEATURE REGISTRY (3-LAYER VALIDATION)
-- File: imgui_hub/boot.lua
-- ============================================================================
-- Semua manajemen modul, validasi fitur GL (META.type == "boren_gl_feature"
-- + render()), dan Hot-Reload dikelola terpusat di sini sehingga file loader
-- tipis di HP user (loader_hub_imgui.lua) TIDAK PERNAH perlu diubah lagi saat
-- menambah fitur baru!
-- ============================================================================

local BOOT = {}

local DEFAULT_BASE_URL = "https://raw.githubusercontent.com/rendhi69/sc_auto_plant_growlauncher/main/"
local FEATURE_TYPE_TAG = "boren_gl_feature"

local LOCAL_FALLBACK_ROOTS = {
    "/storage/emulated/0/Android/media/launcher.powerkuy.growlauncher/ScriptLua/",
    "/storage/emulated/0/Android/data/launcher.powerkuy.growlauncher/files/ScriptLua/",
    "/storage/emulated/0/Download/",
    "script/",
    "",
}

local function logMsg(msg)
    if LogToConsole then pcall(LogToConsole, "`e[BOREN STORE] `w" .. tostring(msg)) end
end

local function notifyMsg(msg)
    if sendNotification then pcall(sendNotification, tostring(msg))
    elseif growtopia and growtopia.notify then pcall(growtopia.notify, tostring(msg)) end
end

-- Lapis 3: Validasi runtime bahwa modul benar-benar fitur GL BOREN STORE yang valid
local function validateGLFeature(mod, entry)
    if type(mod) ~= "table" then
        return false, "Return modul bukan table"
    end
    local meta = mod.META
    if type(meta) ~= "table" then
        return false, "Tidak memiliki META (bukan modul fitur GL)"
    end
    if meta.type ~= FEATURE_TYPE_TAG then
        return false, "META.type tidak cocok (" .. tostring(meta.type) .. ")"
    end
    if meta.enabled == false then
        return false, "Fitur dinonaktifkan (enabled=false)"
    end
    if type(mod.render) ~= "function" then
        return false, "Tidak memiliki fungsi render(hub)"
    end
    local id = tostring(meta.id or mod.id or (entry and entry.id) or "")
    local label = tostring(meta.label or mod.label or (entry and entry.label) or id)
    local order = tonumber(meta.order or (entry and entry.order)) or 100
    if id == "" then
        return false, "META.id kosong"
    end
    return true, { id = id, label = label, order = order }
end

function BOOT.start(baseRawUrl)
    local BASE_RAW_URL = (type(baseRawUrl) == "string" and baseRawUrl ~= "") and baseRawUrl or DEFAULT_BASE_URL
    if BASE_RAW_URL:sub(-1) ~= "/" then BASE_RAW_URL = BASE_RAW_URL .. "/" end

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
        if not t then t = math.random(100000, 999999) end
        CACHE_TAG = tostring(t) .. "_" .. tostring(reloadSeq)
        return CACHE_TAG
    end
    makeFreshTag()

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
            for _, root in ipairs(LOCAL_FALLBACK_ROOTS) do
                local okO, f = pcall(io.open, root .. relPath, "r")
                if okO and f then
                    local txt = f:read("*a")
                    f:close()
                    if txt and txt ~= "" then code = txt; break end
                end
            end
        end
        if not code or code == "" then
            return nil, "Gagal memuat modul: " .. tostring(relPath)
        end
        local loaderFn = loadstring or load
        local chunk, compileErr = loaderFn(code)
        if not chunk then
            return nil, "Error kompilasi " .. tostring(relPath) .. ": " .. tostring(compileErr)
        end
        local okRun, modOrErr = pcall(chunk)
        if not okRun then
            return nil, "Error runtime " .. tostring(relPath) .. ": " .. tostring(modOrErr)
        end
        return modOrErr, nil
    end

    local HUB = {
        BASE_RAW_URL    = BASE_RAW_URL,
        loadModule      = loadRemoteModule,
        fetchRawUrl     = fetchRawUrl,
        refreshCacheTag = makeFreshTag,
        validateFeature = validateGLFeature,
        reloading       = false,
        reload_seq      = 0,
        reload_status   = "Siap",
        features        = {}, -- Daftar fitur dinamis tervalidasi: { { id, label, order, path, mod }, ... }
        tabs            = {},
        logs            = {},
        LINKS = {
            discord       = "https://discord.gg/2pGMQgeNue",
            github_repo   = "https://github.com/rendhi69/sc_auto_plant_growlauncher",
            raw_loader    = BASE_RAW_URL .. "loader_hub_imgui.lua",
            raw_debugpack = "https://raw.githubusercontent.com/rendhi69/data-_id_item/main/debugpack.txt",
            raw_item_db   = "https://raw.githubusercontent.com/rendhi69/data-_id_item/main/item_database.txt",
        },
    }

    function HUB.addLog(line)
        table.insert(HUB.logs, 1, tostring(line or ""))
        if #HUB.logs > 80 then table.remove(HUB.logs) end
    end

    local function stopAllModules()
        if HUB.plant and type(HUB.plant.stop) == "function" then pcall(HUB.plant.stop) end
        for _, feat in ipairs(HUB.features or {}) do
            local m = feat.mod or HUB[feat.id]
            if m and type(m.stop) == "function" then pcall(m.stop) end
        end
    end

    local function getFallbackManifest()
        return {
            schema = "boren_gl_manifest_v1",
            core = {
                { key = "plant", path = "imgui_hub/plant_engine.lua", required = true },
                { key = "ui",    path = "imgui_hub/tab_plant.lua",    required = true },
            },
            features = {
                { id = "dirt_farm",   label = "Dirt Farm",   order = 20, path = "imgui_hub/mod_dirt_farm.lua" },
                { id = "build_soil",  label = "Build Soil",  order = 30, path = "imgui_hub/mod_soil_builder.lua" },
                { id = "buy_pack",    label = "Buy Pack",    order = 40, path = "imgui_hub/mod_buy_pack.lua" },
                { id = "database_id", label = "Database ID", order = 50, path = "imgui_hub/mod_database_id.lua" },
            },
        }
    end

    local function loadAllFromManifest(isReload)
        HUB.reload_status = isReload and "Membaca manifest terbaru..." or "Membaca manifest..."
        local manifest, mErr = loadRemoteModule("imgui_hub/manifest.lua")
        if type(manifest) ~= "table" or type(manifest.core) ~= "table" then
            logMsg("`6Manifest remote gagal (" .. tostring(mErr) .. "), pakai fallback default.")
            manifest = getFallbackManifest()
        end

        local featList = type(manifest.features) == "table" and manifest.features or {}
        local totalSteps = #manifest.core + #featList
        local stepIdx = 0
        local loadedCnt, failCnt, skipCnt = 0, 0, 0

        -- 1. Muat core engine (plant_engine.lua dulu, ui nanti setelah fitur terdaftar)
        local uiEntry = nil
        for _, c in ipairs(manifest.core) do
            if c.key == "ui" then
                uiEntry = c
            else
                stepIdx = stepIdx + 1
                HUB.reload_status = string.format("%s [%d/%d]...", isReload and "Updating" or "Loading", stepIdx, totalSteps)
                local mod, err = loadRemoteModule(c.path)
                if mod then
                    HUB[c.key] = mod
                    if type(mod.init) == "function" then pcall(mod.init, HUB) end
                    loadedCnt = loadedCnt + 1
                else
                    failCnt = failCnt + 1
                    logMsg("`4" .. tostring(err))
                    if c.required then return false, loadedCnt, failCnt end
                end
            end
        end

        -- 2. Muat & validasi semua fitur dinamis dari manifest (Lapis 1 + 2 + 3!)
        local newFeatures = {}
        for _, entry in ipairs(featList) do
            stepIdx = stepIdx + 1
            HUB.reload_status = string.format("%s [%d/%d]...", isReload and "Updating" or "Loading", stepIdx, totalSteps)
            local mod, err = loadRemoteModule(entry.path)
            if mod then
                local okVal, infoOrReason = validateGLFeature(mod, entry)
                if okVal then
                    HUB[infoOrReason.id] = mod
                    if type(mod.init) == "function" then pcall(mod.init, HUB) end
                    table.insert(newFeatures, {
                        id    = infoOrReason.id,
                        label = infoOrReason.label,
                        order = infoOrReason.order,
                        path  = entry.path,
                        mod   = mod,
                    })
                    loadedCnt = loadedCnt + 1
                else
                    skipCnt = skipCnt + 1
                    local warn = "[Skip Non-GL] " .. tostring(entry.path) .. ": " .. tostring(infoOrReason)
                    logMsg("`6" .. warn)
                    HUB.addLog(warn)
                end
            else
                failCnt = failCnt + 1
                logMsg("`4" .. tostring(err))
                HUB.addLog("[Load Gagal] " .. tostring(err))
            end
        end

        table.sort(newFeatures, function(a, b)
            if a.order ~= b.order then return a.order < b.order end
            return a.label < b.label
        end)
        HUB.features = newFeatures

        -- 3. Muat UI Utama terakhir agar sidebar langsung menampilkan semua fitur baru
        if uiEntry then
            stepIdx = stepIdx + 1
            HUB.reload_status = string.format("%s [%d/%d]...", isReload and "Updating" or "Loading", stepIdx, totalSteps)
            local uiMod, uiErr = loadRemoteModule(uiEntry.path)
            if uiMod then
                HUB.ui = uiMod
                if type(uiMod.init) == "function" then pcall(uiMod.init, HUB) end
                loadedCnt = loadedCnt + 1
            else
                failCnt = failCnt + 1
                logMsg("`4" .. tostring(uiErr))
                notifyMsg(tostring(uiErr))
                return false, loadedCnt, failCnt
            end
        end

        return true, loadedCnt, failCnt, skipCnt
    end

    -- Hot-Reload dinamis: re-fetch manifest.lua + seluruh fitur baru tanpa perlu update loader!
    function HUB.reloadAll(onDone)
        if HUB.reloading then return false end
        HUB.reloading = true
        HUB.reload_status = "Mengambil update & fitur baru..."

        local function runner()
            local ok, err = xpcall(function()
                stopAllModules()
                makeFreshTag()
                HUB.reload_seq = (tonumber(HUB.reload_seq) or 0) + 1
                HUB.addLog("[Refresh #" .. tostring(HUB.reload_seq) .. "] Memuat ulang manifest & semua modul...")
                local okLoad, okCnt, failCnt = loadAllFromManifest(true)
                if okLoad then
                    HUB.reload_status = string.format("Update OK #%d (%d modul)", HUB.reload_seq, okCnt)
                    HUB.addLog("[Refresh OK] " .. tostring(okCnt) .. " modul aktif (gagal: " .. tostring(failCnt) .. ").")
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

    -- Boot awal
    local okBoot, okCnt = loadAllFromManifest(false)
    if okBoot then
        HUB.reload_status = "Siap (" .. tostring(okCnt) .. " modul)"
        logMsg("`2BOREN STORE siap (" .. tostring(okCnt) .. " modul)! (/hub)")
        notifyMsg("BOREN STORE Siap! (/hub)")
    end
    return HUB
end

return BOOT
