-- ============================================================================
-- LOADER AUTO PLANT & SPLICE - BOREN STORE (AUTO-FETCH DARI GITHUB)
-- ============================================================================
-- Skrip ini otomatis mengambil dan menjalankan auto_plant.lua versi
-- terbaru dari GitHub repository: https://github.com/rendhi69/sc_auto_plant_growlauncher
-- Setiap kali ada update di GitHub, bot otomatis memakai kode terbaru tanpa perlu
-- mengganti atau copy-paste file manual lagi di Growlauncher!
-- ============================================================================

local RAW_URL = "https://raw.githubusercontent.com/rendhi69/sc_auto_plant_growlauncher/main/auto_plant.lua"

-- Parameter unik (?v=timestamp) untuk bypass CDN cache Fastly GitHub (selalu fresh)
local fetchUrl = RAW_URL .. "?v=" .. tostring(os.time())

local function notifyUser(msg)
    if sendNotification then
        pcall(sendNotification, msg)
    elseif growtopia and growtopia.notify then
        pcall(growtopia.notify, msg)
    end
end

LogToConsole("`9[Boren Store Loader] `0Menghubungkan ke GitHub (Auto Plant & Splice)...")
notifyUser("Menghubungkan ke GitHub...")

local content, err = nil, nil
if fetch then
    local okFetch, res, fetchErr = pcall(fetch, fetchUrl)
    if okFetch and res and res ~= "" then
        content = res
    else
        err = fetchErr or "Respons kosong"
    end
end

-- Fallback jika koneksi offline atau fetch tidak tersedia di versi GL tertentu
if not content or content == "" then
    LogToConsole("`e[Boren Store Loader] `0Fetch GitHub gagal (" .. tostring(err or "koneksi offline") .. "). Mencoba memuat file lokal...")
    local candidatePaths = {
        "/storage/emulated/0/Android/media/launcher.powerkuy.growlauncher/ScriptLua/auto_plant.lua",
        "/storage/emulated/0/Android/media/launcher.powerkuy.growlauncher/ScriptLua/script code/auto_plant.lua",
        "/storage/emulated/0/Android/data/launcher.powerkuy.growlauncher/files/ScriptLua/auto_plant.lua",
        "/storage/emulated/0/Download/auto_plant.lua",
        "d:/rotasi 2026/SC LAMA OLD JUTUN/sc growlauncher/script/script code/auto_plant.lua",
        "script/script code/auto_plant.lua",
        "auto_plant.lua"
    }
    for _, p in ipairs(candidatePaths) do
        local okF, fh = pcall(io.open, p, "r")
        if okF and fh then
            local fileCode = fh:read("*all")
            fh:close()
            if fileCode and fileCode ~= "" then
                content = fileCode
                LogToConsole("`2[Boren Store Loader] `0Berhasil fallback memuat dari: " .. p)
                break
            end
        end
    end
end

if not content or content == "" then
    LogToConsole("`4[Loader Error] `0Gagal memuat auto_plant.lua dari GitHub maupun penyimpanan lokal!")
    notifyUser("Gagal: Auto Plant tidak dapat dimuat!")
    return
end

local chunk, loadErr = load(content)
if not chunk then
    LogToConsole("`4[Loader Syntax Error] `0Gagal mem-parsing skrip: " .. tostring(loadErr))
    notifyUser("Syntax error pada skrip Auto Plant!")
    return
end

LogToConsole("`2[Boren Store Loader] `0Skrip Auto Plant & Splice berhasil dimuat!")
notifyUser("Auto Plant berhasil dimuat!")

-- Eksekusi skrip utama
chunk()
