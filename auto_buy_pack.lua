--[[
    Auto Buy By Boren - Auto Buy Pack & Anti-Retake World Drop (GrowLauncher Android/PC)
    Fitur:
    1. Pencarian pack langsung dari List Debug (tanpa buka/render Shop).
       Nama pack, nama debug (Pack ID), harga gems, dan seluruh ID item isi pack otomatis terisi.
    2. Mendukung Price (harga 1 pack) & How Many (target pack, 0 = sampai gems habis).
    3. Auto Buy langsung via packet (action|buy\nitem|<debug_name>\n) di World Save + Drop Anti-Take.
]]

-- ============================================================================
-- 1. SAFE HELPERS & JSON / PREFERENCES
-- ============================================================================
local function loadPrefsObj()
    if Preferences and Preferences.new then
        local ok, p = pcall(function() return Preferences:new("boren_buy_pack.json") end)
        if ok and p then return p end
    end
    local okReq, PrefMod = pcall(require, "Preferences")
    if okReq and PrefMod and PrefMod.new then
        local ok, p = pcall(function() return PrefMod:new("boren_buy_pack.json") end)
        if ok and p then return p end
    end
    return nil
end

local PREF_STORE = loadPrefsObj()

local function loadPref(key, defaultVal)
    if PREF_STORE and PREF_STORE.get then
        local ok, val = pcall(function() return PREF_STORE:get(key, defaultVal) end)
        if ok and val ~= nil then return val end
    end
    return defaultVal
end

local function savePrefs(cfg)
    if not (PREF_STORE and PREF_STORE.set) then return end
    for k, v in pairs(cfg) do
        local tv = type(v)
        if tv == "string" or tv == "number" or tv == "boolean" then
            pcall(function() PREF_STORE:set(k, v) end)
        end
    end
    if PREF_STORE.save then
        pcall(function() PREF_STORE:save() end)
    end
end

local function escapeJsonStr(s)
    s = tostring(s or "")
    s = s:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t")
    return '"' .. s .. '"'
end

local function encodeJsonValue(v)
    local tv = type(v)
    if tv == "nil" then return "null"
    elseif tv == "boolean" then return v and "true" or "false"
    elseif tv == "number" then return tostring(v)
    elseif tv == "string" then return escapeJsonStr(v)
    elseif tv == "table" then
        local isArr = true
        local maxIdx = 0
        for k, _ in pairs(v) do
            if type(k) ~= "number" or k < 1 or math.floor(k) ~= k then
                isArr = false
                break
            end
            if k > maxIdx then maxIdx = k end
        end
        if isArr then
            local parts = {}
            for i = 1, maxIdx do
                table.insert(parts, encodeJsonValue(v[i]))
            end
            return "[" .. table.concat(parts, ",") .. "]"
        else
            local parts = {}
            for k, val in pairs(v) do
                table.insert(parts, escapeJsonStr(k) .. ":" .. encodeJsonValue(val))
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
    end
    return "null"
end

-- ============================================================================
-- 2. EMBEDDED DEBUG PACK DATABASE (SESUAI debugpack & RUNTIME STATE
-- ============================================================================
local EMBEDDED_DEBUG_PACKS = [=[
Upgrade Backpack:upgrade_backpack::
Clothes Pack:clothes_pack:50:234,210,1846,342,11202,214,138,354,2938,144,272,208,90,38,66,238,122,36,34,44,48,76,140,10034,694,142,236,270,130,40,68,42,374,372,3578,370
Rare Clothes Pack:rare_clothes:500:11204,600,1762,1028,1146,292,1708,5016,576,1736,348,1652,1650,294,3052,1330,890,1124,312,3530,1140,156,2882,258,452,9356,154,1478,1142,1120,150,2934,80,2928,1524,796,1126,152,1954,2576,2958,158,136,496,1848,896,1476,4954,1864,6674,296,290,310,1862,6796,4964,4968,2700,1316,1516,1854,1856,446,3590,1312,1688,1314,3466,594,1858,8884,1502,268,794,1342,488,798,1590,724,352,3048,1026,1860,1032,1838,1718,1850,316,1690,492,894,6788,1116,304,1332,302,86,3164,2578,1022,2960,88,1800,3056,3060,3934,2954,132,852,266,494,1504,74,50,134,98,448,3932,96,148,788,232,288,4966,70,2718,1844,1722,84,212,1122,92,1720,124,46,72,356,146,754,662,94,78,82,1716,250
Infernal Shades:infernal_shades:25000:12474
Tidal Shades:tidal_shades:25000:12476
Verdant Shades:verdant_shades:25000:12478
Transmutabooth:transmutation_device:25000:9170
Contact Lens Pack:contact_lenses:15000:6768,6760,6762,6764,6766
Eye Drop Pack:eye_drops:30000:5468,5466,5464,5462,5460,5458
Turtle Hat:nyan_hat:25000:574
Tiny Horsie:tiny_horsie:25000:592
Pleiadian Star Ship:star_ship:25000:760
Dragon Hand:dragon_hand:50000:900
Little Red Corvette:corvette:25000:766
Stick Horse:stick_horse:25000:1012
Ambulance:ambulance:25000:1272
Riding Raptor:raptor:25000:1320
Mid-Pacific Owl:owl:30000:1540
Unicorn Garland:unicorn:50000:1648
StarBoard:starboard:30000:1740
Growley Motorcycle:motorcycle:50000:1950
Monkey On Your Back:monkey_on_back:50000:2900
Carrot Sword:carrot_sword:15000:2908
Red Bicycle:red_bicycle:30000:2974
Fire Truck:fire_truck:50000:3068
Pet Slime:pet_slime:100000:3166
Dabstep Low Top Sneakers:dabstep_shoes:30000:6790
World Lock:world_lock:2000:242
World Lock Pack:world_lock_10_pack:20000:242
Advertisers Pack:anzu_pack1:10000:10874,10872,10870,10876
Small Lock:small_lock:50:202
Big Lock:big_lock:200:204
Huge Lock:huge_lock:500:206
Door And Sign Hello Pack:door_pack:12:12,20
Door Mover:door_mover:5000:1404
Vending Machine:vending_machine:8000:2978
DigiVendMachine:digi_vend:12000:9268
Vending Hub - Checkout Counter:checkout_counter:50000:9270
Change of Address:change_addr:20000:2580
Signal Jammer:signal_jammer:2000:226
Punch Jammer:punch_jammer:15000:1276
Zombie Jammer:zombie_jammer:15000:1278
Imperial Starship Blast:starship_blast:10000:6420
SurgWorld Blast:surg_blast:10000:8556
Bountiful Blast:bountiful_blast:5000:8738
Thermonuclear Blast:thermo_blast:15000:1402
Antigravity Generator:antigravity_generator:450000:4992
Building Blocks Machine:building_blocks_machine:8000:8196
Builder's Lock:builders_lock:50000:4994
Weather Machine - Sunny:weather_sunny:1000:932
Weather Machine - Night:weather_night:10000:934
Weather Machine - Arid:weather_arid:10000:946
Weather Machine - Rainy City:weather_rainy:10000:984
Weather Machine - Warp Speed:weather_warp:10000:1750
Mars Blast:mars_blast:15000:1136
Undersea Blast:undersea_blast:15000:1532
Cave Blast:cave_blast:30000:3562
Weather Machine - Stuff:weather_stuff:50000:3832
Weather Machine - Jungle:weather_jungle:20000:4776
Weather Machine - Background:weather_backgd:150000:5000
Weather Machine - Digital Rain:digital_rain_weather:30000:6854
Treasure Blast:treasure_blast:10000:7588
Infinity Weather Machine:infinity_weather_machine:50000:10058
Small Seed Pack:5seed:100:5706
Small Seed Pack Collection:ssp_10_pack:1000:5706
Rare Seed Pack:rare_seed:1000:2293,2295,2297,2299,2301,2305,2629,2309,2311,2313,2315,2317,2321,2323,2325,2327,2329,2333,2335,2337,2339,2341,2319,2331,2343,4697,2447,2519,2629,2727,231,487,483,2019,427,1757,2009,281,781,329,459,1041,421,2787,2789,1043,2797,181,613,65,4983,283,553,425,4635,987,627,2017,989,61,4639,973,3523,331,265,859,433,253,339,1105,439,4567,333,677,5673,1427,5603,183,10533,5731,7223,10833,6035,6813,1113,1047,653,2811,4703,1429,847,665,485,1613,833,2025,1775,3931,429,3831,423,437,1773,4767,1299,361,667,2815,3473,301,4637,5683,2709,415,955,461,861,9389,5467,2791,2815,1803,419,2027,685,555,741,10531,5729,7221,10831,6033,6811,621,6401,1107,359,3471,855,309,1685,1449,1309,441,1111,221,1431,3065,9307,1257,1501,1109,4641,3587,1103,417,743,431,3823,2949,1131,3825,727,5379,729,187,787,5459,3423,3261,3521,5461,3721,327,247,63,3479,445,4783,299,863,8935,1451,261,1871,1499,455,9391,683,1159,551,1745,411,3005,557,687,4799,559,4643,3899,1605,9309,567,565,1155,3827,1327,1767,993,1157,563,4721,115,1423,10515,1329,6545,287,669,777,5463,1655,1599,561,4585,3413,4745,1771,2011,1161,1729,3757,3753,321,3265,3263,623,775,6397,129,4667,759,3767,1529,6543,4707,3835,1435,651,8929,569,527,3287,1595,6063,2795,1003,1731,4943,4963,597,4669,1531,1523,625,4297,599,657,571,873,3755,2969,1725,4603,1447,3267,5375,1683
5-pack of Grow Spray Fertilizer:grow_spray:200:228
Deluxe Grow Spray:deluxe_grow_spray:900:1778
Bountiful Seed Pack:bountiful_seed_pack:1000:8970
Basic Splicing Kit:basic_splice:200:101,21,1139,381,17,57,13,3567,11
Surgery Starter Pack:surg_starter_pack:5000:1248,1246,1244,1242,8558,1256,1240
Surgical Kit:surgical_kit:12000:9310,4316,4310,1270,1258,1268,1260,4308,4318,4312,4314,1264,1266,1263,4296
Surgical Tools Value Pack:surg_value_pack:45000:9310,4316,4310,1270,1258,1268,1260,4308,4318,4312,4314,1264,1266,1263,4296
Galactic Goodies:star_supplies:15000:6526,6532,6534,6536,6416,6524,6530,6518,6540,6528,6522,6538,6520
Fishin' Pack:fishin_pack:10000:2912,3044,3004,3002,2914,5524,5522
Fish Trainin' Pack:fish_training_pack:10000:5536,5532,5530
Fish Flakes:fish_flakes:7500:5536
Fish Medicine:fish_medicine:1500:5532
Fish Reviver:fish_reviver:5000:5534
Crime Wave:crime_wave:5000:2293,2295,2297,2299,2301,2305,2629,2309,2311,2313,2315,2317,2321,2323,2325,2327,2329,2333,2335,2337,2339,2341,2319,2331,2343,4697,2447,2519,2629,2727
Silkworm:silkworn:7000:3316
Geiger Counter:geiger:25000:2204
Zombie Defense Pack:zombie_pack:10000:764,768,784,782,786,774,788,790
B.O.O. Training Pack:boo_pack:10000:3710,3716,3714,3720
EctoJuicer:ectojuicer:30000:6096
Ghost Hunter's Pack:ghost_hunting:10000:13820
Chemsynth Pack:chemsynth:10000:4442,4434,4440,4438,4436,4432,4430
Racing Action Pack:race_pack:3500:486,484,482,410,430,428,496,356,488,490,494,492
Composer's Pack:music_pack:5000:418,416,414,426,424,422,420,412
Education Pack:school_pack:5000:678,672,670,676,658,654,650,652,674,8872,8870,8876,8874
Dungeon Pack:dungeon_pack:10000:692,696,694,690,688,686,684,682,680
Fantasy Pack:fantasy_pack:5000:583,596,598,606,608,604,594,600
Vegas Pack:vegas_pack:20000:798,796,794,758,756,754,456,752,1582,740,1922,1920,1924,1918,1916,743,747,749,744
Farm Pack:farm_pack:15000:898,896,894,892,13732,890,886,888,884,880,872,866
Mad Science Kit:science_pack:5000:918,920,924,914,916,930,904,12494,770,772,912,928
City Pack:city_pack:8000:1008,1002,988,1006,1004,998,996,990,992,986,994
Wild West Pack:west_pack:8000:1016,1020,1048,1046,1044,1042,1040,1038,1032,1034,1036,1028,1026,1024,1030,1022
Astro Pack:astro_pack:5000:1152,1154,1130,1128,1160,1162,1164,1146,1144,1142,1140,1148
Prehistoric Pack:prehistoric_pack:5000:1328,1324,1322,1326,1342,1340,1332,1334,1338,1330,1336
Shop Pack:shop_pack:10000:1420,1434,1446,1430,1432,1428,1426,1422,1436
Home Pack:home_pack:50000:1474,1476,1478,1454,1472,1450,1480,1448,1482
Cinema Pack:cinema_pack:6000:1596,1608,1606,1604,1600,1598,1594,1590,1592,1588
Adventure Pack:adventure_pack:20000:4780,1704,1692,1698,1696,1702,1694,4706,4704,1706,1684,1682
Rockin' Pack:rockin_pack:9999:1726,1730,1728,1724,1720,1722,1732,1718,1714,1712,1710
Game Pack:game_pack:50000:1658,1656,1622,1618,1616,1660
Superhero Pack:superhero:10000:6684,7148,2196,2200,2202,2198,2194,6694,2162,2164,2160,2158,6696,6686,2126,2128,2124,2122,6692,6682,2102,2104,2100,2098,2114,2116,2112,2110,6690,6680,2174,2176,2172,2170,2078,2080,2076,2074,6688,6678,2138,2140,2136,2134,2186,2188,2184,2182,2150,2152,2148,2146,2208
Fashion Pack:fashion_pack:5000:11800,11206,10080,2672,2684,2660,2648,2708,2646
Sportsball Pack:sportsball_pack:20000:13600,6676,6670,2906,2888,2884,2880,6672,2882,2878,2890,2886,6668,2894,2892,2898,2896,6674,2904,2902
Firefighter Pack:firefighter:10000:3072,3066,3052,3060,3056,3048
Steampack:steampack:20000:3292,3280,3284,3282,3270,3260
Painter's Pack:paintbrush:30000:3494,3492,3480,3484,3486,3488,3482,3478,3490
Paleontologist's Kit:paleo_kit:20000:3938,4128,3934,3932,4132
CyBlocks Starter Pack:robot_starter_pack:5000:5668,5680,5676,5672,5678,5674
CyBlocks Command Pack:robot_command_pack:2000:5704,5702,5698,5700,5696,5694,5690,5692,5688,5686,5682,5684,5680,5678,5676,5672,5674
CyBot Pack:robot_pack:15000:5670,5710,5708
Gangland Style:gang_pack:5000:478,480,472,470,476,474,468,466,464,462
]=]

local PACK_CATALOG = {}
local PACK_BY_CODE = {}

local function trimStr(s)
    return tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function sanitizeDialogText(s)
    return trimStr(tostring(s or ""):gsub("`.", "")):gsub("[|\r\n]+", " ")
end

local function loadPacksIntoCatalog(rawText)
    for line in tostring(rawText or ""):gmatch("[^\r\n]+") do
        local ln = trimStr(line)
        if ln ~= "" and ln:sub(1, 2) ~= "--" and ln ~= "]]" and (not ln:find("^packs%s*=")) then
            local name, code, priceStr, idsStr = ln:match("^([^:]+):([^:]*):([^:]*):(.*)$")
            name = trimStr(name)
            code = trimStr(code)
            if name ~= "" and code ~= "" then
                local cleanIds = {}
                for tok in tostring(idsStr or ""):gmatch("[^,%s;]+") do
                    local n = tonumber(tok)
                    if n and n > 0 then
                        table.insert(cleanIds, tostring(math.floor(n)))
                    end
                end
                local entry = {
                    title = name,
                    code = code,
                    price = tonumber(priceStr) or 0,
                    ids = table.concat(cleanIds, ","),
                }
                local key = code:lower()
                local existingIdx = PACK_BY_CODE[key]
                if existingIdx then
                    PACK_CATALOG[existingIdx] = entry
                else
                    table.insert(PACK_CATALOG, entry)
                    PACK_BY_CODE[key] = #PACK_CATALOG
                end
            end
        end
    end
end

loadPacksIntoCatalog(EMBEDDED_DEBUG_PACKS)

if io and io.open then
    for _, path in ipairs({ "debugpack.txt", "ScriptLua/debugpack.txt" }) do
        local f = io.open(path, "r")
        if f then
            local content = f:read("*a")
            f:close()
            loadPacksIntoCatalog(content)
            break
        end
    end
end

local CFG = {
    pack_name           = tostring(loadPref("pack_name", "world_lock") or "world_lock"),
    pack_item_ids_text  = tostring(loadPref("pack_item_ids_text", "242") or "242"),
    pack_price          = tonumber(loadPref("pack_price", 2000)) or 2000,
    target_packs        = tonumber(loadPref("target_packs", 0)) or 0,

    drop_world          = tostring(loadPref("drop_world", "") or ""),
    drop_door           = tostring(loadPref("drop_door", "") or ""),

    drop_anchor_x       = tonumber(loadPref("drop_anchor_x", 0)) or 0,
    drop_anchor_y       = tonumber(loadPref("drop_anchor_y", 0)) or 0,
    drop_threshold      = tonumber(loadPref("drop_threshold", 200)) or 200,
    max_stacks_per_tile = tonumber(loadPref("max_stacks_per_tile", 18)) or 18,

    use_gl_drop         = (loadPref("use_gl_drop", true) ~= false),
    anti_retake         = (loadPref("anti_retake", true) ~= false),
    auto_learn_items    = (loadPref("auto_learn_items", true) ~= false),
    shop_search         = tostring(loadPref("shop_search", "") or ""),

    delay_buy           = tonumber(loadPref("delay_buy", 1000)) or 1000,
    delay_drop          = tonumber(loadPref("delay_drop", 350)) or 350,
    delay_warp          = tonumber(loadPref("delay_warp", 4500)) or 4500,
}

local STATE = {
    running              = false,
    step                 = "SIAP",
    detail               = string.format("Database %d pack siap! Cari nama pack, isi World Save & START.", #PACK_CATALOG),
    packs_bought         = 0,
    items_dropped        = 0,
    full_drop_tiles      = {},
    backpack_full_flag   = false,
    no_gems_flag         = false,
    unknown_pack_flag    = false,
    pending_drop_id      = nil,
    pending_drop_amt     = nil,
    hooks_installed      = false,
    saved_ac_toggle      = nil,
    saved_anti_toggle    = nil,
    last_dialog_items    = {},
    dialog_page          = 1,
    anti_take_active     = false,
    last_store_msg       = "",
    buy_server_confirmed = false,
    in_coroutine         = false,
    ignore_power_event   = false,
    user_edited_price    = false,
    user_set_target      = false,
    last_seen_search_gl  = nil,
    buying_now           = false,
    suppress_store_until = 0,
    logged_store_block   = false,
}

local function notifyUser(msg)
    msg = tostring(msg or "")
    if growtopia and growtopia.notify then
        pcall(growtopia.notify, msg)
    elseif sendNotification then
        pcall(sendNotification, msg)
    end
end

local function logMsg(msg)
    msg = "[Auto Buy By Boren] " .. tostring(msg or "")
    if LogToConsole then
        pcall(LogToConsole, msg)
    elseif log then
        pcall(log, msg)
    end
end

local function safeSleep(ms)
    local waitMs = math.max(0, tonumber(ms) or 0)
    if waitMs == 0 then return end
    if STATE.in_coroutine and CSleep then
        pcall(CSleep, waitMs)
    elseif sleep then
        pcall(sleep, waitMs)
    elseif CSleep then
        pcall(CSleep, waitMs)
    end
end

local function runInCoroutineSafe(fn)
    local wrapped = function()
        STATE.in_coroutine = true
        local ok, err = pcall(fn)
        STATE.in_coroutine = false
        if not ok then
            logMsg("Coroutine Error: " .. tostring(err))
        end
    end
    if runCoroutine then
        local okC, errC = pcall(runCoroutine, wrapped)
        if not okC then
            STATE.in_coroutine = false
            logMsg("Gagal runCoroutine: " .. tostring(errC))
            wrapped()
        end
    else
        wrapped()
    end
end

local updateStatusList

local function setStatus(step, detail)
    STATE.step = tostring(step or "Berjalan")
    STATE.detail = tostring(detail or "")
    logMsg(STATE.step .. " - " .. STATE.detail)
    if updateStatusList then
        pcall(updateStatusList)
    end
end

updateStatusList = function()
    if not editValue then return end
    local gemStr = "-"
    if getGems then
        local okG, g = pcall(getGems)
        if okG and g then gemStr = tostring(g) end
    end
    local runLabel = STATE.running and ("BERJALAN: " .. STATE.step) or ("BERHENTI (" .. STATE.step .. ")")
    local targetTxt = (CFG.target_packs > 0) and (tostring(STATE.packs_bought) .. "/" .. tostring(CFG.target_packs)) or (tostring(STATE.packs_bought) .. " (Habis)")
    local rows = {
        { runLabel, STATE.detail },
        { "How Many: " .. targetTxt .. " | Price: " .. tostring(CFG.pack_price), "Gems: " .. gemStr .. " | Drop: " .. tostring(STATE.items_dropped) },
    }
    pcall(editValue, "bp_status_list", encodeJsonValue(rows))
end

-- ============================================================================
-- 3. PARSERS & WORLD / INVENTORY HELPERS
-- ============================================================================
local function parseWorldAndDoor(rawWorld, rawDoor)
    local w = trimStr(rawWorld)
    local d = trimStr(rawDoor)
    if w:find("|", 1, true) then
        local wn, wd = w:match("^([^|]+)|(.*)$")
        w = trimStr(wn)
        if trimStr(wd) ~= "" then d = trimStr(wd) end
    elseif w:find(":", 1, true) then
        local wn, wd = w:match("^([^:]+):(.*)$")
        w = trimStr(wn)
        if trimStr(wd) ~= "" then d = trimStr(wd) end
    end
    return w:upper(), d
end

local function parsePackItemIDs(rawText)
    local ids = {}
    local seen = {}
    for token in tostring(rawText or ""):gmatch("[^,\r\n;%s]+") do
        local subId = tonumber(token)
        if subId and subId > 0 then
            subId = math.floor(subId)
            if not seen[subId] then
                seen[subId] = true
                table.insert(ids, subId)
            end
        elseif trimStr(token):lower() ~= "nul" and trimStr(token):lower() ~= "null" then
            if findItemID then
                local ok, id = pcall(findItemID, trimStr(token))
                if ok and tonumber(id) and tonumber(id) > 0 then
                    local fid = math.floor(tonumber(id))
                    if not seen[fid] then
                        seen[fid] = true
                        table.insert(ids, fid)
                    end
                end
            end
        end
    end
    return ids
end

local function getItemNameSafe(itemID)
    if getItemInfoByID then
        local ok, info = pcall(getItemInfoByID, itemID)
        if ok and info and info.name and info.name ~= "" then
            return tostring(info.name)
        end
    end
    if growtopia and growtopia.getItemName then
        local ok, nm = pcall(growtopia.getItemName, itemID)
        if ok and nm and nm ~= "" then
            return tostring(nm)
        end
    end
    return "ID " .. tostring(itemID)
end

local function getCurrentWorldSafe()
    if getCurrentWorldName then
        local ok, w = pcall(getCurrentWorldName)
        if ok and type(w) == "string" and w ~= "" then return w:upper() end
    end
    if getWorld then
        local ok, w = pcall(getWorld)
        if ok and w and w.name then return tostring(w.name):upper() end
    end
    return ""
end

local function isOnlineInWorld()
    if getLocal then
        local ok, p = pcall(getLocal)
        if not ok or not p then return false end
    end
    local w = getCurrentWorldSafe()
    return (w ~= "" and w ~= "EXIT")
end

local function getPlayerTilePos()
    if not getLocal then return nil, nil end
    local ok, p = pcall(getLocal)
    if not ok or not p then return nil, nil end
    local px = p.posX or (p.pos and p.pos.x)
    local py = p.posY or (p.pos and p.pos.y)
    if not px or not py then return nil, nil end
    return math.floor((px + 10) / 32), math.floor((py + 10) / 32)
end

local function snapshotInventory()
    local snap = {}
    if getInventory then
        local ok, inv = pcall(getInventory)
        if ok and type(inv) == "table" then
            for _, item in pairs(inv) do
                local id = tonumber(item.id or item.itemID or item.itemid)
                local amt = tonumber(item.amount or item.count) or 0
                if id and id > 0 and id ~= 112 and amt > 0 then
                    snap[id] = (snap[id] or 0) + amt
                end
            end
        end
    end
    return snap
end

local function getInvCount(itemID)
    if growtopia and growtopia.checkInventoryCount then
        local ok, cnt = pcall(growtopia.checkInventoryCount, itemID)
        if ok and type(cnt) == "number" then
            return cnt
        end
    end
    if getInventory then
        local ok, inv = pcall(getInventory)
        if ok and type(inv) == "table" then
            for _, item in pairs(inv) do
                if (item.id or item.itemID or item.itemid) == itemID then
                    return tonumber(item.amount or item.count) or 0
                end
            end
        end
    end
    return 0
end

local function hasAnyTrackedItem(itemIDs)
    if getInventory then
        local snap = snapshotInventory()
        for _, id in ipairs(itemIDs) do
            if (snap[id] or 0) > 0 then return true end
        end
        return false
    end
    for _, id in ipairs(itemIDs) do
        if getInvCount(id) > 0 then return true end
    end
    return false
end

local function hasReachedDropThreshold(itemIDs)
    local thresh = math.max(1, math.min(200, tonumber(CFG.drop_threshold) or 200))
    if getInventory then
        local snap = snapshotInventory()
        for _, id in ipairs(itemIDs) do
            if (snap[id] or 0) >= thresh then return true, id end
        end
        return false, nil
    end
    for _, id in ipairs(itemIDs) do
        if getInvCount(id) >= thresh then return true, id end
    end
    return false, nil
end

local function readGLRawString(alias)
    if getValue then
        local sawEmpty = false
        for _, vt in ipairs({ 2, 5, 1 }) do
            local ok, v = pcall(getValue, vt, alias)
            if ok and v ~= nil then
                local s = trimStr(tostring(v))
                if s ~= "" then return s end
                sawEmpty = true
            end
        end
        if sawEmpty then return "" end
    end
    return nil
end

local function readGLString(alias, fallback)
    local s = readGLRawString(alias)
    if s ~= nil and s ~= "" then return s end
    return fallback
end

local function readGLInt(alias)
    if getValue then
        for _, vt in ipairs({ 1, 2, 5 }) do
            local ok, v = pcall(getValue, vt, alias)
            if ok and v ~= nil then
                local cleaned = trimStr(tostring(v)):gsub("[,%s]", "")
                local n = tonumber(cleaned)
                if n then return math.floor(n) end
            end
        end
    end
    return nil
end

local function readGLBool(alias, fallback)
    if getValue then
        local ok, v = pcall(getValue, 0, alias)
        if ok and type(v) == "boolean" then return v end
    end
    return fallback
end

local function syncInputsFromGL()
    local pName = readGLString("bp_pack_name", "")
    if pName ~= "" then CFG.pack_name = trimStr(pName) end

    local iIds = readGLString("bp_item_ids", "")
    if iIds ~= "" then CFG.pack_item_ids_text = trimStr(iIds) end

    local pPrice = readGLInt("bp_pack_price")
    if pPrice and (pPrice > 0 or not STATE.user_edited_price) and pPrice >= 0 then
        CFG.pack_price = pPrice
    end

    local tPacks = readGLInt("bp_target_packs")
    if tPacks and (tPacks > 0 or not STATE.user_set_target) and tPacks >= 0 then
        CFG.target_packs = tPacks
    end

    local dWorld = readGLString("bp_drop_world", "")
    if dWorld ~= "" then CFG.drop_world = trimStr(dWorld):upper() end

    local dDoor = readGLString("bp_drop_door", "")
    if dDoor ~= "" then CFG.drop_door = trimStr(dDoor) end

    local dThresh = readGLInt("bp_drop_thresh")
    if dThresh and dThresh >= 1 then CFG.drop_threshold = math.min(200, dThresh) end

    CFG.use_gl_drop = readGLBool("bp_use_gl_drop", CFG.use_gl_drop)
    CFG.anti_retake = readGLBool("bp_anti_retake", CFG.anti_retake)
    CFG.auto_learn_items = readGLBool("bp_auto_learn", CFG.auto_learn_items)
end

local function learnNewPackItems(beforeInv, itemIDs)
    if not beforeInv then return false end
    local afterInv = snapshotInventory()
    local seen = {}
    for _, id in ipairs(itemIDs) do
        seen[id] = true
    end
    local addedAny = false
    for id, afterAmt in pairs(afterInv) do
        local prevAmt = beforeInv[id] or 0
        if afterAmt > prevAmt and (not seen[id]) then
            seen[id] = true
            table.insert(itemIDs, id)
            addedAny = true
            logMsg(string.format("Auto-Deteksi Isi Pack: +%s (ID %d)", getItemNameSafe(id), id))
        end
    end
    if addedAny then
        local strs = {}
        for _, id in ipairs(itemIDs) do
            table.insert(strs, tostring(id))
        end
        CFG.pack_item_ids_text = table.concat(strs, ", ")
        if editValue then pcall(editValue, "bp_item_ids", CFG.pack_item_ids_text) end
        savePrefs(CFG)
    end
    return addedAny
end

-- ============================================================================
-- 4. SEARCH & SELECT PACK DARI DEBUG LIST (TANPA RENDER SHOP)
-- ============================================================================
local function scorePackMatch(entry, q, words, isNumericQ)
    local titleL = entry.title:lower()
    local codeL = entry.code:lower()
    if q == "" then return 100 end

    -- 1. Cocok persis (exact match)
    if codeL == q or titleL == q then return 1000 end
    -- 2. Diawali query (prefix match)
    if titleL:sub(1, #q) == q or codeL:sub(1, #q) == q then return 800 end
    -- 3. Awal kata cocok (word boundary match)
    if (" " .. titleL):find(" " .. q, 1, true) or ("_" .. codeL):find("_" .. q, 1, true) then
        return 600
    end
    -- 4. Substring di judul atau kode debug
    if titleL:find(q, 1, true) or codeL:find(q, 1, true) then
        return 450
    end
    -- 5. Multi-kata (semua kata ada di judul atau kode debug, tidak tembus ke ratusan ID acak)
    if #words > 1 then
        local textHay = titleL .. " " .. codeL
        local allOk = true
        for _, w in ipairs(words) do
            if not textHay:find(w, 1, true) then
                allOk = false
                break
            end
        end
        if allOk then return 350 end
    end
    -- 6. Khusus query angka murni: cocokkan persis per token ID item (mis. "242", "5706")
    if isNumericQ then
        local idsHay = "," .. tostring(entry.ids or "") .. ","
        if idsHay:find("," .. q .. ",", 1, true) then
            return 200
        end
    end
    return nil
end

local function buildFilteredPackList(queryStr)
    local q = trimStr(queryStr):lower()
    local words = {}
    if q ~= "" then
        for w in q:gmatch("%S+") do
            table.insert(words, w)
        end
    end
    local isNumericQ = (q ~= "" and q:match("^%d+$") ~= nil)

    local scored = {}
    for origIdx, item in ipairs(PACK_CATALOG) do
        local sc = scorePackMatch(item, q, words, isNumericQ)
        if sc then
            table.insert(scored, { item = item, score = sc, origIdx = origIdx })
        end
    end

    if q ~= "" then
        table.sort(scored, function(a, b)
            if a.score ~= b.score then return a.score > b.score end
            if #a.item.title ~= #b.item.title then return #a.item.title < #b.item.title end
            return a.origIdx < b.origIdx
        end)
    end

    local list = {}
    for _, s in ipairs(scored) do
        table.insert(list, s.item)
    end
    return list
end

local function updatePackResultsList()
    if not editValue then return end
    local q = trimStr(CFG.shop_search)
    local items = buildFilteredPackList(q)
    local rows = {}
    if q == "" then
        table.insert(rows, { string.format("Ketik nama di 'Cari Pack' (%d pack siap)", #PACK_CATALOG), "Atau pilih langsung dari kategori 'Pilih Pack' di bawah" })
        local limit = math.min(10, #items)
        for i = 1, limit do
            local it = items[i]
            local priceTxt = (tonumber(it.price) or 0) > 0 and (tostring(it.price) .. "g") or "Store"
            table.insert(rows, { string.format("%d. %s", i, sanitizeDialogText(it.title)), sanitizeDialogText(it.code) .. " | " .. priceTxt })
        end
    else
        local limit = math.min(25, #items)
        for i = 1, limit do
            local it = items[i]
            local priceTxt = (tonumber(it.price) or 0) > 0 and (tostring(it.price) .. " Gems") or "Store"
            table.insert(rows, { string.format("%d. %s", i, sanitizeDialogText(it.title)), "Kode: " .. sanitizeDialogText(it.code) .. " | " .. priceTxt })
        end
        if #rows == 0 then
            table.insert(rows, { "Tidak ada pack cocok: " .. q, "Coba kata lain mis: seed / surg / lock" })
        end
    end
    pcall(editValue, "bp_shop_results_list", encodeJsonValue(rows))
    return items
end

local function applySelectedPack(entry)
    if not entry then return end
    CFG.pack_name = entry.code
    if (tonumber(entry.price) or 0) > 0 then
        CFG.pack_price = math.floor(tonumber(entry.price))
        STATE.user_edited_price = false
        if editValue then pcall(editValue, "bp_pack_price", tostring(CFG.pack_price)) end
    end

    CFG.pack_item_ids_text = trimStr(entry.ids or "")
    CFG.auto_learn_items = true
    if editToggle then pcall(editToggle, "bp_auto_learn", true) end

    if editValue then
        pcall(editValue, "bp_pack_name", CFG.pack_name)
        pcall(editValue, "bp_item_ids", CFG.pack_item_ids_text)
    end
    savePrefs(CFG)

    local idInfo = (CFG.pack_item_ids_text ~= "") and "ID Otomatis Siap" or "Auto-Deteksi Saat Beli"
    local infoMsg = string.format("Dipilih: %s (%s) | %d Gems | %s",
        entry.title, entry.code, tonumber(entry.price) or 0, idInfo)
    setStatus("Pack Siap", infoMsg)
    notifyUser(infoMsg)
end

local function findBestPackMatch(rawInput)
    local q = trimStr(rawInput):lower()
    if q == "" then return nil end

    local idxNum = tonumber(q)
    if idxNum and idxNum >= 1 and math.floor(idxNum) == idxNum then
        local curFiltered = buildFilteredPackList(CFG.shop_search)
        if curFiltered[idxNum] then return curFiltered[idxNum] end
    end

    for _, it in ipairs(PACK_CATALOG) do
        if it.code:lower() == q then return it end
    end
    for _, it in ipairs(PACK_CATALOG) do
        if it.title:lower() == q then return it end
    end
    local filtered = buildFilteredPackList(rawInput)
    return filtered[1]
end

local function openPackPickerDialog(queryStr, pageOverride)
    if queryStr ~= nil then
        CFG.shop_search = trimStr(queryStr)
        savePrefs(CFG)
    end
    local items = buildFilteredPackList(CFG.shop_search)
    STATE.last_dialog_items = items

    local perPage = 15
    local totalPages = math.max(1, math.ceil(#items / perPage))
    local page = tonumber(pageOverride) or 1
    if page < 1 then page = 1 end
    if page > totalPages then page = totalPages end
    STATE.dialog_page = page

    if growtopia and growtopia.sendDialog then
        local lines = {
            "set_default_color|`o",
            "add_label_with_icon|big|`wAuto Buy By Boren - Cari Pack``|left|112|",
            string.format("add_textbox|`oList Debug: `2%d`o pack | Ditemukan: `2%d`o | Hal `w%d/%d`o.|left|", #PACK_CATALOG, #items, page, totalPages),
            "add_spacer|small|",
            string.format("add_text_input|shop_q|Cari Nama Pack:|%s|32|", sanitizeDialogText(CFG.shop_search or "")),
            "add_button|shop_search|`2Cari|noflags|0|0|",
            "add_button|shop_clear_q|`9Tampilkan Semua|noflags|0|0|",
            "add_spacer|small|",
        }
        if #items == 0 then
            table.insert(lines, "add_textbox|`4Tidak ada pack cocok dengan kata pencarianmu.|left|")
        else
            local startIdx = (page - 1) * perPage + 1
            local endIdx = math.min(#items, startIdx + perPage - 1)
            for i = startIdx, endIdx do
                local it = items[i]
                local priceTxt = (tonumber(it.price) or 0) > 0 and (tostring(it.price) .. " Gems") or "Gratis/Store"
                table.insert(lines, string.format("add_button|shop_pick_%d|`w%s (`5%s`w) [`2%s`w]|noflags|0|0|", i, sanitizeDialogText(it.title), priceTxt, sanitizeDialogText(it.code)))
            end
            if totalPages > 1 then
                if page > 1 then
                    table.insert(lines, "add_button|shop_page_prev|`6<< Sebelumnya|noflags|0|0|")
                end
                if page < totalPages then
                    table.insert(lines, "add_button|shop_page_next|`6Berikutnya >>|noflags|0|0|")
                end
            end
        end
        table.insert(lines, "end_dialog|boren_shop_browser|Tutup||")
        pcall(growtopia.sendDialog, table.concat(lines, "\n"))
        return true
    end
    return false
end

-- ============================================================================
-- 5. ANTI-RETAKE COLLECT GUARD & WARP
-- ============================================================================
local function applyDropCollectGuard(droppingNow)
    if not CFG.anti_retake then
        STATE.anti_take_active = false
        return
    end
    STATE.anti_take_active = (droppingNow == true)
    if droppingNow then
        if STATE.saved_ac_toggle == nil then
            STATE.saved_ac_toggle = readGLBool("Auto Collect", false)
            STATE.saved_anti_toggle = readGLBool("Anti Collect", false)
        end
        if editToggle then
            pcall(editToggle, "Auto Collect", false)
            pcall(editToggle, "Anti Collect", true)
            pcall(editToggle, "AutoCollect", false)
            pcall(editToggle, "AntiCollect", true)
        elseif editValue then
            pcall(editValue, "Auto Collect", false)
            pcall(editValue, "Anti Collect", true)
        end
    else
        if editToggle then
            if STATE.saved_ac_toggle ~= nil then
                pcall(editToggle, "Auto Collect", STATE.saved_ac_toggle)
            end
            if STATE.saved_anti_toggle ~= nil then
                pcall(editToggle, "Anti Collect", STATE.saved_anti_toggle)
            end
        end
    end
end

local function warpToWorld(worldName, doorID, forceRewarp)
    worldName = trimStr(worldName):upper()
    doorID = trimStr(doorID)
    if worldName == "" then return false end

    local curW = getCurrentWorldSafe()
    local alreadyHere = (curW == worldName)
    local targetStr = (doorID ~= "") and (worldName .. "|" .. doorID) or worldName
    if alreadyHere and doorID == "" and (not forceRewarp) then
        return true
    end

    local startX, startY = getPlayerTilePos()
    setStatus("Warp World", (doorID ~= "") and ("Menuju " .. worldName .. ":" .. doorID) or ("Menuju " .. worldName))
    if sendPacket then
        pcall(sendPacket, 3, "action|join_request\nname|" .. targetStr .. "\ninvitedWorld|0\n")
    elseif growtopia and growtopia.warpTo then
        pcall(growtopia.warpTo, worldName)
    end

    local maxWait = math.max(2500, tonumber(CFG.delay_warp) or 4500)
    local elapsed = 0
    while STATE.running and elapsed < maxWait do
        safeSleep(250)
        elapsed = elapsed + 250
        if getCurrentWorldSafe() == worldName then
            if (not alreadyHere) or doorID == "" then
                safeSleep(650)
                return true
            end
            local npx, npy = getPlayerTilePos()
            if (startX and npx and (npx ~= startX or npy ~= startY)) or elapsed >= 1000 then
                safeSleep(450)
                return true
            end
        end
    end
    return (getCurrentWorldSafe() == worldName)
end

-- ============================================================================
-- 6. HOOKS (BUY CONFIRMATION / DROP DIALOG / ANTI-TAKE TYPE 11)
-- ============================================================================
local function extractVariantString(val)
    if val == nil then return "" end
    local tv = type(val)
    if tv == "string" or tv == "number" or tv == "boolean" then
        return tostring(val)
    end
    local res = nil
    pcall(function()
        if val.getString then
            res = val:getString()
        elseif val.str then
            res = val.str
        elseif val.text then
            res = val.text
        end
    end)
    if res ~= nil then return tostring(res) end
    local okStr, s = pcall(tostring, val)
    return okStr and s or ""
end

local function extractVariantFields(var)
    if var == nil then return "", "" end
    local raw1, raw2, raw3
    pcall(function() raw1 = var.v1 end)
    pcall(function() raw2 = var.v2 end)
    pcall(function() raw3 = var.v3 end)
    if raw1 == nil then
        pcall(function() raw1 = var[1] or var[0] end)
    end
    if raw2 == nil then
        pcall(function()
            if var[0] ~= nil and var[1] ~= nil then
                raw2 = var[1]
            else
                raw2 = var[2]
            end
        end)
    end
    if raw1 == nil then
        pcall(function()
            if var.get then
                raw1 = var:get(0)
                raw2 = var:get(1)
                raw3 = var:get(2)
            end
        end)
    end
    return extractVariantString(raw1), extractVariantString(raw2), extractVariantString(raw3)
end

local function getClockSec()
    if os and os.clock then
        local ok, c = pcall(os.clock)
        if ok and type(c) == "number" then return c end
    end
    return 0
end

local function shouldSuppressStoreUI()
    if STATE.running then return true end
    local now = getClockSec()
    return now > 0 and STATE.suppress_store_until > now
end

local function onVariantHook(var, pkt)
    if var == nil then return false end
    local v1, v2, v3 = extractVariantFields(var)
    if v1 == "" then return false end
    local v1Low = v1:lower()
    local payload = (v2 ~= "" and v2) or (v3 ~= "" and v3) or ""
    local low = payload:lower()

    if v1Low == "onstorerequest" then
        if shouldSuppressStoreUI() then
            if not STATE.logged_store_block then
                STATE.logged_store_block = true
                logMsg("Tampilan Shop (OnStoreRequest) diblokir agar beli pack tetap di background.")
            end
            return true
        end
    elseif v1Low == "onstorepurchaseresult" then
        local cleanMsg = trimStr(payload:gsub("`.", ""))
        if cleanMsg ~= "" then
            STATE.last_store_msg = cleanMsg
            logMsg("Hasil Beli Store: " .. cleanMsg)
        end
        if low:find("not enough gems") or low:find("don't have enough gems") or low:find("insufficient gems") then
            STATE.no_gems_flag = true
        elseif low:find("backpack is full") or low:find("inventory is full") or low:find("can't carry") then
            STATE.backpack_full_flag = true
        elseif low:find("unknown item") or low:find("cannot purchase") or low:find("not available") then
            STATE.unknown_pack_flag = true
        elseif low:find("purchased") or low:find("bought") or low:find("success") then
            STATE.buy_server_confirmed = true
        end
        if shouldSuppressStoreUI() then
            return true
        end
    elseif v1Low == "onconsolemessage" or v1Low == "ontextoverlay" then
        local cleanMsg = trimStr(payload:gsub("`.", ""))
        if STATE.running and cleanMsg ~= "" and (low:find("gem") or low:find("buy") or low:find("pack") or low:find("store") or low:find("wait") or low:find("full") or low:find("unknown") or low:find("bought") or low:find("purchased")) then
            STATE.last_store_msg = cleanMsg
            logMsg("Server: " .. cleanMsg)
        end
        if low:find("not enough gems") or low:find("don't have enough gems") or low:find("insufficient gems") then
            STATE.no_gems_flag = true
        elseif low:find("backpack is full") or low:find("inventory is full") or low:find("can't carry any more") then
            STATE.backpack_full_flag = true
        elseif low:find("unknown item") or low:find("cannot purchase") or low:find("not available") then
            STATE.unknown_pack_flag = true
        elseif low:find("bought") or low:find("purchased") then
            STATE.buy_server_confirmed = true
        end
    elseif v1Low == "ondialogrequest" then
        if STATE.running and STATE.pending_drop_id and (low:find("drop") or low:find("how many")) then
            local dropAmt = tonumber(STATE.pending_drop_amt) or 1
            local idStr = tostring(STATE.pending_drop_id)
            local dialogName = payload:match("end_dialog|([^|\n]+)") or "drop_item"
            if dialogName:lower():find("drop") then
                if sendPacket then
                    pcall(sendPacket, 2, string.format("action|dialog_return\ndialog_name|%s\nitemID|%s|\ncount|%d\n", dialogName, idStr, dropAmt))
                end
                return true
            end
        elseif shouldSuppressStoreUI() and (not low:find("boren_shop_browser")) and (low:find("store") or low:find("purchase") or low:find("confirm") or low:find("buy") or (STATE.buying_now and (low:find("spend") or low:find("pack")))) then
            local dialogName = payload:match("end_dialog|([^|\r\n]+)")
            if dialogName and trimStr(dialogName) ~= "" and sendPacket then
                local btnName = payload:match("add_button|([^|\r\n]+)|")
                local extraBtn = (btnName and trimStr(btnName) ~= "" and btnName ~= "cancel" and btnName ~= "back")
                    and ("buttonClicked|" .. trimStr(btnName) .. "\n") or ""
                pcall(sendPacket, 2, "action|dialog_return\ndialog_name|" .. trimStr(dialogName) .. "\n" .. extraBtn)
                logMsg("Konfirmasi beli otomatis: " .. trimStr(dialogName))
            end
            return true
        end
    end
    return false
end

local function onSendPacketHook(ptype, pktStr)
    if type(pktStr) ~= "string" then return false end

    if pktStr:find("dialog_name|boren_shop_browser", 1, true) then
        local btn = pktStr:match("buttonClicked|([^\n|\r]+)") or ""
        local qIn = pktStr:match("shop_q|([^\n|\r]*)")
        if btn == "shop_clear_q" then
            CFG.shop_search = ""
            if editValue then pcall(editValue, "bp_shop_search", "") end
            savePrefs(CFG)
            updatePackResultsList()
            openPackPickerDialog("", 1)
        elseif btn == "shop_page_prev" then
            openPackPickerDialog(CFG.shop_search, (STATE.dialog_page or 1) - 1)
        elseif btn == "shop_page_next" then
            openPackPickerDialog(CFG.shop_search, (STATE.dialog_page or 1) + 1)
        elseif btn:sub(1, 10) == "shop_pick_" then
            local pidx = tonumber(btn:sub(11))
            local picked = pidx and STATE.last_dialog_items[pidx]
            if picked then
                applySelectedPack(picked)
            end
        elseif btn == "shop_search" or qIn ~= nil then
            CFG.shop_search = trimStr(qIn or CFG.shop_search)
            if editValue then pcall(editValue, "bp_shop_search", CFG.shop_search) end
            savePrefs(CFG)
            updatePackResultsList()
            openPackPickerDialog(CFG.shop_search, 1)
        end
        return true
    end
    return false
end

local function onSendPacketRawHook(pkt)
    if STATE.anti_take_active and type(pkt) == "table" and tonumber(pkt.type) == 11 then
        return true
    end
    return false
end

local function ensureHooks()
    if STATE.hooks_installed then return end
    STATE.hooks_installed = true
    if addHook then
        pcall(addHook, onVariantHook, "onvariant")
        pcall(addHook, onSendPacketHook, "onsendpacket")
        pcall(addHook, onSendPacketRawHook, "onsendpacketraw")
    end
    if applyHook then
        pcall(applyHook)
    end
end

-- ============================================================================
-- 7. WORLD DROP ENGINE (ANTI-RETAKE + GL CONFIRM DROP)
-- ============================================================================
local function isTilePassable(tx, ty)
    if tx < 1 or tx > 98 or ty < 1 or ty > 53 then return false end
    if not getTile then return true end
    local ok, t = pcall(getTile, tx, ty)
    if not ok or not t then return true end
    if t.collidable then return false end
    local fg = tonumber(t.fg) or 0
    if fg == 4 or fg == 8 or fg == 2 or fg == 10 or fg == 242 or fg == 202 then
        return false
    end
    return true
end

local function isDropTileUsable(tx, ty)
    if not isTilePassable(tx, ty) then return false end
    local key = tostring(tx) .. "," .. tostring(ty)
    if STATE.full_drop_tiles[key] then return false end

    local fn = getObjectList or getObjects
    if fn then
        local ok, objs = pcall(fn)
        if ok and type(objs) == "table" then
            local stackCount = 0
            local totalQty = 0
            for _, obj in pairs(objs) do
                if obj and obj.pos then
                    local ox = math.floor((obj.pos.x + 10) / 32)
                    local oy = math.floor((obj.pos.y + 10) / 32)
                    if ox == tx and oy == ty then
                        stackCount = stackCount + 1
                        totalQty = totalQty + (tonumber(obj.amount) or 1)
                    end
                end
            end
            if stackCount >= (tonumber(CFG.max_stacks_per_tile) or 18) or totalQty >= 3600 then
                STATE.full_drop_tiles[key] = true
                return false
            end
        end
    end
    return true
end

local function moveToDropStand(standX, standY, dropX)
    if FindPath then
        local okChk, blocked = pcall(FindPath, standX, standY, true)
        if okChk and blocked == true then return false end
        local okMove = pcall(FindPath, standX, standY)
        if not okMove then return false end
        safeSleep(160)
    end

    local px, py = getPlayerTilePos()
    if px and py and (px ~= standX or py ~= standY) then
        return false
    end

    if sendPacketRaw then
        local faceLeft = (dropX < standX)
        pcall(sendPacketRaw, false, {
            type  = 0,
            state = faceLeft and 48 or 32,
            x     = standX * 32,
            y     = standY * 32,
        })
        safeSleep(70)
    end
    return true
end

local function hasFloorObjectsAt(tx, ty)
    local fn = getObjectList or getObjects
    if not fn then return false end
    local ok, objs = pcall(fn)
    if ok and type(objs) == "table" then
        for _, obj in pairs(objs) do
            if obj and obj.pos then
                local ox = math.floor((obj.pos.x + 10) / 32)
                local oy = math.floor((obj.pos.y + 10) / 32)
                if ox == tx and oy == ty then
                    return true
                end
            end
        end
    end
    return false
end

local function hasCleanHorizontalPath(fromX, toX, ty)
    if not fromX then return true end
    local step = (toX >= fromX) and 1 or -1
    for sx = fromX, toX, step do
        if hasFloorObjectsAt(sx, ty) then
            return false
        end
    end
    return true
end

local function findAntiRetakeDropSlot(anchorX, anchorY)
    local px, py = getPlayerTilePos()
    local offsetsY = { 0, -1, 1, -2, 2 }
    for _, requireCleanFloor in ipairs({ true, false }) do
        if (not requireCleanFloor) and px and py and px >= 1 and px <= 97 and (not hasFloorObjectsAt(px, py)) and isDropTileUsable(px + 1, py) then
            return px + 1, py, px
        end
        for _, dy in ipairs(offsetsY) do
            local ty = anchorY + dy
            if ty >= 2 and ty <= 53 then
                if requireCleanFloor and px and py == ty and px >= 1 and px <= 97 and (not hasFloorObjectsAt(px, ty)) then
                    local dxRight = px + 1
                    if isDropTileUsable(dxRight, ty) and (not hasFloorObjectsAt(dxRight, ty)) then
                        return dxRight, ty, px
                    end
                end
                for dx = 0, -24, -1 do
                    local dropX = anchorX + dx
                    local standX = dropX - 1
                    if dropX >= 2 and dropX <= 98 and standX >= 1 and isTilePassable(standX, ty) and isDropTileUsable(dropX, ty) then
                        local pathOk = (not requireCleanFloor) or ((not hasFloorObjectsAt(standX, ty)) and (not hasFloorObjectsAt(dropX, ty)) and ((py ~= ty) or hasCleanHorizontalPath(px, standX, ty)))
                        if pathOk then
                            return dropX, ty, standX
                        end
                    end
                end
                for dx = 1, 16 do
                    local dropX = anchorX + dx
                    local standX = dropX + 1
                    if dropX >= 1 and dropX <= 97 and standX <= 98 and isTilePassable(standX, ty) and isDropTileUsable(dropX, ty) then
                        local pathOk = (not requireCleanFloor) or ((not hasFloorObjectsAt(standX, ty)) and (not hasFloorObjectsAt(dropX, ty)) and ((py ~= ty) or hasCleanHorizontalPath(px, standX, ty)))
                        if pathOk then
                            return dropX, ty, standX
                        end
                    end
                end
            end
        end
    end
    return nil, nil, nil
end

local function dropSingleItemAntiRetake(itemID, anchorX, anchorY)
    local amt = getInvCount(itemID)
    if amt <= 0 then return true end

    local attempts = 0
    while STATE.running and amt > 0 and attempts < 8 do
        attempts = attempts + 1
        local dropX, dropY, standX = findAntiRetakeDropSlot(anchorX, anchorY)
        if not dropX then
            setStatus("World Drop Penuh", "Tidak ditemukan tile kosong di world drop!")
            return false
        end

        if not moveToDropStand(standX, dropY, dropX) then
            STATE.full_drop_tiles[tostring(dropX) .. "," .. tostring(dropY)] = true
        else
            local beforeAmt = getInvCount(itemID)
            local dropAmt = math.min(200, beforeAmt)
            STATE.pending_drop_id = itemID
            STATE.pending_drop_amt = dropAmt

            local usedConfirmDrop = false
            if CFG.use_gl_drop and growtopia and growtopia.confirmDropItem then
                pcall(growtopia.confirmDropItem, itemID, dropAmt)
                usedConfirmDrop = true
            elseif sendPacket then
                pcall(sendPacket, 2, string.format("action|drop\n|itemID|%d\n", itemID))
            end

            local waited = 0
            local afterAmt = beforeAmt
            while STATE.running and waited < 1400 do
                safeSleep(60)
                waited = waited + 60
                afterAmt = getInvCount(itemID)
                if afterAmt < beforeAmt then break end
            end

            if afterAmt >= beforeAmt and usedConfirmDrop and sendPacket and STATE.running then
                pcall(sendPacket, 2, string.format("action|drop\n|itemID|%d\n", itemID))
                waited = 0
                while STATE.running and waited < 1200 do
                    safeSleep(60)
                    waited = waited + 60
                    afterAmt = getInvCount(itemID)
                    if afterAmt < beforeAmt then break end
                end
            end

            STATE.pending_drop_id = nil
            STATE.pending_drop_amt = nil

            if afterAmt < beforeAmt then
                STATE.items_dropped = STATE.items_dropped + (beforeAmt - afterAmt)
                safeSleep(CFG.delay_drop)
                amt = afterAmt
            else
                STATE.full_drop_tiles[tostring(dropX) .. "," .. tostring(dropY)] = true
                amt = afterAmt
            end
        end
    end

    return (getInvCount(itemID) <= 0)
end

local function dropPackItemsToWorld(itemIDs)
    if not hasAnyTrackedItem(itemIDs) then
        return true
    end

    local dropW, dropD = parseWorldAndDoor(CFG.drop_world, CFG.drop_door)
    if dropW == "" then
        setStatus("Error Drop", "World Save belum diisi!")
        notifyUser("Isi World Save dulu!")
        return false
    end

    applyDropCollectGuard(true)

    if getCurrentWorldSafe() ~= dropW then
        if not warpToWorld(dropW, dropD) then
            setStatus("Gagal Warp Drop", "Gagal masuk ke world save " .. dropW)
            return false
        end
    end

    applyDropCollectGuard(true)
    safeSleep(250)

    local px, py = getPlayerTilePos()
    local anchorX = (tonumber(CFG.drop_anchor_x) or 0) > 0 and math.floor(CFG.drop_anchor_x) or (px or 50)
    local anchorY = (tonumber(CFG.drop_anchor_y) or 0) > 0 and math.floor(CFG.drop_anchor_y) or (py or 23)

    if getInventory then
        local snap = snapshotInventory()
        for _, itemID in ipairs(itemIDs) do
            if not STATE.running then break end
            if (snap[itemID] or 0) > 0 then
                setStatus("Drop Pack", string.format("Drop %s x%d di %s (Anti-Retake)", getItemNameSafe(itemID), snap[itemID], dropW))
                if not dropSingleItemAntiRetake(itemID, anchorX, anchorY) then
                    return false
                end
            end
        end
    else
        for _, itemID in ipairs(itemIDs) do
            if not STATE.running then break end
            local cnt = getInvCount(itemID)
            if cnt > 0 then
                setStatus("Drop Pack", string.format("Drop %s x%d di %s (Anti-Retake)", getItemNameSafe(itemID), cnt, dropW))
                if not dropSingleItemAntiRetake(itemID, anchorX, anchorY) then
                    return false
                end
            end
        end
    end

    local fpx, fpy = getPlayerTilePos()
    if fpx and fpy then
        local stepAwayX = (fpx <= anchorX) and (fpx - 1) or (fpx + 1)
        if stepAwayX >= 1 and stepAwayX <= 98 and isTilePassable(stepAwayX, fpy) and (not hasFloorObjectsAt(stepAwayX, fpy)) then
            if FindPath then pcall(FindPath, stepAwayX, fpy) end
            safeSleep(120)
        end
    end

    return true
end

-- ============================================================================
-- 8. MAIN DIRECT BUY PACK & DROP LOOP (TANPA RENDER SHOP)
-- ============================================================================
local function runBuyPackLoop()
    syncInputsFromGL()
    ensureHooks()

    local packCode = trimStr(CFG.pack_name)
    if packCode == "" and trimStr(CFG.shop_search) ~= "" then
        packCode = trimStr(CFG.shop_search)
    end
    if packCode == "" then
        setStatus("Error Input", "Cari & pilih pack dulu!")
        notifyUser("Cari & pilih pack dulu!")
        return
    end

    -- Auto-cocokkan ke database debugpack (isi nama debug, harga & seluruh ID item otomatis!)
    local matched = findBestPackMatch(packCode)
    if matched and (packCode:find("%s") ~= nil or tonumber(packCode) ~= nil or matched.code:lower() == packCode:lower() or matched.title:lower() == packCode:lower()) then
        packCode = matched.code
        CFG.pack_name = matched.code
        if editValue then pcall(editValue, "bp_pack_name", packCode) end
        if (not STATE.user_edited_price) and (tonumber(matched.price) or 0) > 0 and (CFG.pack_price == 2000 or CFG.pack_price == 0 or packCode ~= "world_lock") then
            CFG.pack_price = math.floor(tonumber(matched.price))
            if editValue then pcall(editValue, "bp_pack_price", tostring(CFG.pack_price)) end
        end
        if trimStr(CFG.pack_item_ids_text) == "" and trimStr(matched.ids or "") ~= "" then
            CFG.pack_item_ids_text = trimStr(matched.ids)
            if editValue then pcall(editValue, "bp_item_ids", CFG.pack_item_ids_text) end
        end
    end

    local itemIDs = parsePackItemIDs(CFG.pack_item_ids_text)
    if #itemIDs == 0 then
        CFG.auto_learn_items = true
    end

    local dropW, dropD = parseWorldAndDoor(CFG.drop_world, CFG.drop_door)
    if dropW == "" then
        setStatus("Error Input", "World Save belum diisi!")
        notifyUser("Isi World Save dulu!")
        return
    end

    STATE.packs_bought         = 0
    STATE.items_dropped        = 0
    STATE.full_drop_tiles      = {}
    STATE.backpack_full_flag   = false
    STATE.no_gems_flag         = false
    STATE.unknown_pack_flag    = false
    STATE.buy_server_confirmed = false
    STATE.last_store_msg       = ""
    STATE.buying_now           = false
    STATE.logged_store_block   = false

    local targetLabel = (CFG.target_packs > 0) and (tostring(CFG.target_packs) .. " pack") or "Sampai Habis"
    logMsg(string.format("Mulai Direct Buy: pack=%s | price=%d | jumlah=%s | world=%s", packCode, CFG.pack_price, targetLabel, dropW))
    setStatus("Masuk World Save", (dropD ~= "") and ("Warp ke " .. dropW .. ":" .. dropD) or ("Warp ke " .. dropW))

    if getCurrentWorldSafe() ~= dropW or dropD ~= "" then
        if not warpToWorld(dropW, dropD, true) then
            setStatus("Gagal Warp Save", "Gagal masuk ke World Save " .. dropW)
            return
        end
    end

    applyDropCollectGuard(true)

    local reachedPre = hasReachedDropThreshold(itemIDs)
    if reachedPre then
        if not dropPackItemsToWorld(itemIDs) then
            return
        end
    end

    local lastBeforeInv = nil
    local consecutiveBuyFails = 0
    while STATE.running do
        if not isOnlineInWorld() then
            setStatus("Menunggu Online", "Koneksi terputus, menunggu kembali online...")
            safeSleep(1500)
        else
            local curW = getCurrentWorldSafe()
            if curW ~= dropW then
                if not warpToWorld(dropW, dropD, true) then
                    safeSleep(1000)
                end
                applyDropCollectGuard(true)
            elseif CFG.target_packs > 0 and STATE.packs_bought >= CFG.target_packs then
                setStatus("Target Tercapai", string.format("Sudah beli %d/%d pack.", STATE.packs_bought, CFG.target_packs))
                break
            elseif CFG.pack_price > 0 and getGems and (function()
                local okG, curGems = pcall(getGems)
                if okG and type(curGems) == "number" and curGems < CFG.pack_price then
                    setStatus("Gems Habis", string.format("Sisa gems (%d) < harga pack (%d).", curGems, CFG.pack_price))
                    return true
                end
                return false
            end)() then
                break
            elseif STATE.no_gems_flag then
                setStatus("Gems Habis", "Server melaporkan gems tidak cukup.")
                break
            elseif STATE.unknown_pack_flag then
                setStatus("Pack Tidak Valid", "Kode debug '" .. packCode .. "' ditolak server!")
                notifyUser("Kode pack ditolak server: " .. packCode)
                break
            else
                local needDrop, fullId = hasReachedDropThreshold(itemIDs)
                if STATE.backpack_full_flag or needDrop then
                    STATE.backpack_full_flag = false
                    setStatus("Drop Item", fullId and (getItemNameSafe(fullId) .. " mencapai batas drop, drop di " .. dropW) or "Tas penuh, drop di " .. dropW)
                    if not dropPackItemsToWorld(itemIDs) then
                        break
                    end
                else
                    applyDropCollectGuard(true)
                    local targetDisp = (CFG.target_packs > 0) and tostring(CFG.target_packs) or "Habis"
                    setStatus("Membeli Pack", string.format("Beli '%s' #%d/%s (%d Gems) di %s", packCode, STATE.packs_bought + 1, targetDisp, CFG.pack_price, dropW))

                    local beforeInv = snapshotInventory()
                    local beforeGems = nil
                    if getGems then
                        local okBg, bg = pcall(getGems)
                        if okBg and type(bg) == "number" then beforeGems = bg end
                    end
                    lastBeforeInv = beforeInv
                    STATE.last_store_msg = ""
                    STATE.buy_server_confirmed = false
                    STATE.buying_now = true
                    STATE.suppress_store_until = getClockSec() + 3.0

                    -- Beli langsung via package tanpa render shop
                    if sendPacket then
                        pcall(sendPacket, 2, "action|buy\nitem|" .. packCode .. "\n")
                    end

                    local buyVerified = false
                    local waitBuy = 0
                    local minDelay = math.max(500, tonumber(CFG.delay_buy) or 1000)
                    while STATE.running and waitBuy < math.max(minDelay, 1300) do
                        safeSleep(100)
                        waitBuy = waitBuy + 100
                        if STATE.no_gems_flag or STATE.unknown_pack_flag or STATE.backpack_full_flag then
                            break
                        end
                        local gotNew = learnNewPackItems(beforeInv, itemIDs)
                        local curG = nil
                        if getGems then
                            local okCg, cg = pcall(getGems)
                            if okCg and type(cg) == "number" then curG = cg end
                        end
                        local invGained = gotNew
                        if not invGained then
                            local nowInv = snapshotInventory()
                            for id, nAmt in pairs(nowInv) do
                                if nAmt > (beforeInv[id] or 0) then
                                    invGained = true
                                    break
                                end
                            end
                        end
                        if (beforeGems and curG and curG < beforeGems) or invGained or STATE.buy_server_confirmed then
                            buyVerified = true
                            if waitBuy >= minDelay then
                                break
                            end
                        end
                    end

                    if buyVerified then
                        consecutiveBuyFails = 0
                        STATE.packs_bought = STATE.packs_bought + 1
                        updateStatusList()
                    elseif STATE.no_gems_flag or STATE.unknown_pack_flag or STATE.backpack_full_flag then
                        -- Ditangani iterasi berikutnya
                    else
                        consecutiveBuyFails = consecutiveBuyFails + 1
                        logMsg(string.format("Pembelian #%d belum terkonfirmasi (%d/4). Msg: %s", consecutiveBuyFails, 4, tostring(STATE.last_store_msg)))
                        if consecutiveBuyFails >= 4 then
                            local errTxt = (STATE.last_store_msg ~= "") and STATE.last_store_msg or ("Store tidak merespon kode '" .. packCode .. "'")
                            setStatus("Gagal Beli Pack", errTxt)
                            notifyUser("Gagal beli pack: " .. errTxt)
                            break
                        else
                            safeSleep(600)
                        end
                    end
                    STATE.buying_now = false
                end
            end
        end
    end

    if STATE.running and STATE.packs_bought > 0 then
        safeSleep(650)
        if lastBeforeInv then
            learnNewPackItems(lastBeforeInv, itemIDs)
        end
    end

    if STATE.running and hasAnyTrackedItem(itemIDs) then
        setStatus("Drop Akhir", "Drop semua sisa hasil beli ke " .. dropW)
        dropPackItemsToWorld(itemIDs)
    end

    applyDropCollectGuard(false)
    if STATE.running then
        notifyUser(string.format("Auto Buy selesai! Dibeli: %d pack | Dropped: %d item", STATE.packs_bought, STATE.items_dropped))
    end
end

local function setPowerToggleSilent(val)
    if not editToggle then return end
    STATE.ignore_power_event = true
    pcall(editToggle, "bp_run_power", val == true)
    STATE.ignore_power_event = false
end

local function startBuyPack()
    if STATE.running then return end
    ensureHooks()
    STATE.running = true
    updateStatusList()

    local function runner()
        local ok, err = pcall(runBuyPackLoop)
        if not ok then
            setStatus("Error", tostring(err))
            notifyUser("Error Buy Pack: " .. tostring(err))
        end
        STATE.running = false
        applyDropCollectGuard(false)
        setPowerToggleSilent(false)
        updateStatusList()
    end

    runInCoroutineSafe(runner)
end

local function stopBuyPack()
    STATE.running = false
    applyDropCollectGuard(false)
    setPowerToggleSilent(false)
    setStatus("Berhenti", "Dihentikan oleh user.")
end

-- ============================================================================
-- 9. SIMPLE GROWLAUNCHER NATIVE UI & EVENT HANDLER
-- ============================================================================
local function classifyPackBucket(entry)
    local hay = (tostring(entry.title or "") .. " " .. tostring(entry.code or "")):lower()
    if hay:find("lock") or hay:find("door") or hay:find("vend") or hay:find("jammer")
        or hay:find("upgrade_backpack") or hay:find("clothes") or hay:find("checkout")
        or hay:find("change_addr") or hay:find("antigravity") or hay:find("building_blocks")
        or hay:find("advertiser") then
        return 1
    elseif hay:find("seed") or hay:find("spray") or hay:find("splice") or hay:find("farm")
        or hay:find("weather") or hay:find("blast") then
        return 2
    elseif hay:find("surg") or hay:find("fish") or hay:find("crime") or hay:find("silkwor")
        or hay:find("geiger") or hay:find("zombie") or hay:find("boo_pack") or hay:find("ecto")
        or hay:find("ghost") or hay:find("chem") or hay:find("science") then
        return 3
    end
    return 4
end

local function buildUI()
    if not (UserInterface and UserInterface.new and addIntoModule) then
        return
    end
    if addCategory then
        pcall(addCategory, "Auto Buy By Boren", "ShoppingCart")
    end

    -- Tab 1: Buy Pack + List Pack Menyatu di UI GL Asli (Tanpa Console ImGui Terpisah!)
    local uiBuy = UserInterface.new("1. Buy Pack", "ShoppingCart")
    uiBuy:addLabelApp("Auto Buy By Boren", "ShoppingCart")
    uiBuy:addToggleButton("START / STOP Buy Pack", false, "bp_run_power")
    uiBuy:addDisplayList("Status Bot (Console)", "[]", "bp_status_list")
    uiBuy:addDivider()
    uiBuy:addInputString("Cari Pack (Ketik Nama)", CFG.shop_search, "Cari", "Ketik nama mis: Small Seed / Surg / Blast", "Search", "bp_shop_search")
    uiBuy:addButton("Cari Spesifik di List GL", "bp_btn_filter_list")
    uiBuy:addButton("Pilih Hasil Pencarian (Popup Klik)", "bp_btn_open_search_popup")
    uiBuy:addDisplayList("Hasil Pencarian Spesifik (Tampilan Teks)", "[]", "bp_shop_results_list")

    if uiBuy.addDialog and uiBuy.addChildButton then
        local bucketDefs = {
            { title = "Pilih Pack: Locks, Basics & Baju", sub = "World Lock, Small Lock, Vend, Jammer, Baju, Upgrade" },
            { title = "Pilih Pack: Seeds, Farm, Weather & Blast", sub = "SSP, Rare Seed, Spray, Splice, Weather, Blast" },
            { title = "Pilih Pack: Profesi (Surg, Fish, Ghost, Crime)", sub = "Surgical Kit, Fishing, Ghost, Crime, Geiger, Science" },
            { title = "Pilih Pack: Theme Packs & Aksesoris", sub = "Astro, Vegas, Superhero, Shades, Vehicles, dll" },
        }
        local buckets = { {}, {}, {}, {} }
        for idx, entry in ipairs(PACK_CATALOG) do
            local b = classifyPackBucket(entry)
            table.insert(buckets[b], { idx = idx, entry = entry })
        end
        for b = 1, 4 do
            if #buckets[b] > 0 then
                local dlg = uiBuy:addDialog(bucketDefs[b].title, string.format("%s (%d pack)", bucketDefs[b].sub, #buckets[b]), {})
                if dlg and dlg.menu then
                    for _, itemRef in ipairs(buckets[b]) do
                        local it = itemRef.entry
                        local pTxt = (tonumber(it.price) or 0) > 0 and (tostring(it.price) .. "g") or "Store"
                        local btnLabel = string.format("%s (%s) [%s]", it.title, pTxt, it.code)
                        uiBuy:addChildButton(dlg.menu, btnLabel, "bp_dp_" .. tostring(itemRef.idx))
                    end
                end
            end
        end
    end

    uiBuy:addDivider()
    uiBuy:addInputString("Nama Pack Terpilih (Debug / Nama)", CFG.pack_name, "Pack", "Otomatis terisi tanpa perlu isi ID", "ShoppingBag", "bp_pack_name")
    uiBuy:addInputInt("Price (Harga 1 Pack)", tostring(CFG.pack_price), "Price", "100", "Diamond", "bp_pack_price")
    uiBuy:addInputInt("Jumlah Pack yg Dibeli (0 = Sampai Habis)", tostring(CFG.target_packs), "Jumlah Pack", "200 (0 = Sampai Habis)", "Flag", "bp_target_packs")
    if uiBuy.addExpandableToggle and uiBuy.addChildInputString and uiBuy.addChildToggle then
        local advIds = uiBuy:addExpandableToggle("Pengaturan ID Item (Otomatis dari Debug List)", false, "bp_adv_ids", false, true)
        uiBuy:addChildToggle(advIds.list_child, "Auto-Deteksi ID Tambahan saat Beli", CFG.auto_learn_items, "bp_auto_learn")
        uiBuy:addChildInputString(advIds.list_child, "ID Item Pack (Terisi Otomatis)", CFG.pack_item_ids_text, "ID List", "Otomatis dari list debug", "FormatListNumbered", "bp_item_ids")
    else
        uiBuy:addInputString("ID Item Pack (Terisi Otomatis)", CFG.pack_item_ids_text, "ID List", "Otomatis dari list debug", "FormatListNumbered", "bp_item_ids")
        uiBuy:addToggle("Auto-Deteksi ID Tambahan saat Beli", CFG.auto_learn_items, "bp_auto_learn", true)
    end

    -- Tab 2: World Save & Drop Settings
    local uiDrop = UserInterface.new("2. World Save", "Inventory")
    uiDrop:addLabelApp("Auto Buy By Boren - World Save", "Inventory")
    uiDrop:addInputString("World Save / Drop", CFG.drop_world, "World Save", "NAMAWORLD atau WORLD|DOOR", "Public", "bp_drop_world")
    uiDrop:addInputString("Door ID Save (Opsional)", CFG.drop_door, "Door ID", "Kosongkan jika tanpa ID", "DoorFront", "bp_drop_door")
    uiDrop:addInputInt("Auto-Drop Per (Max 200, Sisa tetap Drop)", tostring(CFG.drop_threshold), "Batas", "200", "Layers", "bp_drop_thresh")
    uiDrop:addDivider()
    uiDrop:addToggle("Pakai Drop GL (Tanpa Popup Allow)", CFG.use_gl_drop, "bp_use_gl_drop", true)
    uiDrop:addToggle("Anti-Take Item Saat Drop (Blok Collect & Hindari Item)", CFG.anti_retake, "bp_anti_retake", true)
    uiDrop:addButton("Set Titik Awal Drop di Posisi Saya", "bp_btn_set_drop_pos")
    uiDrop:addButton("Reset Titik Drop ke Otomatis (0,0)", "bp_btn_reset_drop_pos")
    uiDrop:addSlider("Max Stack Per Tile", 5, 19, CFG.max_stacks_per_tile, 1, false, "bp_max_stacks")
    uiDrop:addSlider("Delay Buy (ms)", 500, 3000, CFG.delay_buy, 100, false, "bp_delay_buy")
    uiDrop:addSlider("Delay Drop (ms)", 200, 1500, CFG.delay_drop, 50, false, "bp_delay_drop")
    uiDrop:addSlider("Delay Warp (ms)", 3000, 8000, CFG.delay_warp, 250, false, "bp_delay_warp")

    pcall(addIntoModule, uiBuy:generateJSON(), "Auto Buy By Boren")
    pcall(addIntoModule, uiDrop:generateJSON(), "Auto Buy By Boren")
    updateStatusList()
    updatePackResultsList()
    if runCoroutine then
        runInCoroutineSafe(function()
            safeSleep(450)
            updateStatusList()
            updatePackResultsList()
        end)
    end
end

local lastBtnTime = {}

local function applySearchQuery(newQuery, notifyIfMultiple)
    CFG.shop_search = trimStr(newQuery)
    STATE.last_seen_search_gl = readGLRawString("bp_shop_search")
    local found = updatePackResultsList() or buildFilteredPackList(CFG.shop_search)
    local qL = CFG.shop_search:lower()
    if qL ~= "" and (#found == 1 or (found[1] and (found[1].code:lower() == qL or found[1].title:lower() == qL))) then
        applySelectedPack(found[1])
    elseif notifyIfMultiple then
        notifyUser(string.format("Ditemukan %d pack untuk '%s'!", #found, CFG.shop_search))
    end
end

local function resolveLatestSearchQuery()
    local qRaw = readGLRawString("bp_shop_search")
    if qRaw ~= nil and qRaw ~= STATE.last_seen_search_gl then
        STATE.last_seen_search_gl = qRaw
        return qRaw
    end
    return CFG.shop_search
end

function OnValue(vtype, name, value)
    if type(name) ~= "string" then return end

    if name:sub(1, 7) == "bp_btn_" then
        local now = os and os.clock and os.clock() or 0
        if lastBtnTime[name] and (now - lastBtnTime[name]) < 0.25 then return end
        lastBtnTime[name] = now
    end

    if name == "bp_run_power" then
        if STATE.ignore_power_event then return end
        local wantOn = (value == true or value == 1 or value == "true" or value == "1")
        if wantOn == STATE.running then return end
        if wantOn then
            startBuyPack()
        else
            stopBuyPack()
        end
    elseif name:sub(1, 6) == "bp_dp_" then
        local idx = tonumber(name:sub(7))
        if idx and PACK_CATALOG[idx] then
            applySelectedPack(PACK_CATALOG[idx])
        end
    elseif name == "bp_shop_search" then
        applySearchQuery(value, false)
    elseif name == "bp_btn_filter_list" then
        ensureHooks()
        applySearchQuery(resolveLatestSearchQuery(), true)
    elseif name == "bp_btn_open_search_popup" then
        ensureHooks()
        CFG.shop_search = trimStr(resolveLatestSearchQuery())
        updatePackResultsList()
        openPackPickerDialog(CFG.shop_search, 1)
    elseif name == "bp_pack_name" then
        local newInput = trimStr(value)
        local changed = (newInput:lower() ~= trimStr(CFG.pack_name):lower())
        if changed then
            STATE.user_edited_price = false
        end
        CFG.pack_name = newInput
        if changed and newInput ~= "" then
            local exact = findBestPackMatch(newInput)
            if exact and (exact.code:lower() == newInput:lower() or exact.title:lower() == newInput:lower() or tonumber(newInput) ~= nil) then
                applySelectedPack(exact)
            end
        end
    elseif name == "bp_auto_learn" then
        CFG.auto_learn_items = (value == true or value == 1 or value == "true" or value == "1")
    elseif name == "bp_item_ids" then
        CFG.pack_item_ids_text = trimStr(value)
    elseif name == "bp_pack_price" then
        local n = tonumber((tostring(value):gsub("[,%s]", "")))
        if n and n >= 0 then
            CFG.pack_price = math.floor(n)
            STATE.user_edited_price = true
        end
        updateStatusList()
    elseif name == "bp_target_packs" then
        local n = tonumber((tostring(value):gsub("[,%s]", "")))
        if n and n >= 0 then
            CFG.target_packs = math.floor(n)
            STATE.user_set_target = (CFG.target_packs > 0)
        end
        updateStatusList()
    elseif name == "bp_drop_world" then
        CFG.drop_world = trimStr(value):upper()
    elseif name == "bp_drop_door" then
        CFG.drop_door = trimStr(value)
    elseif name == "bp_drop_thresh" then
        local n = tonumber(value)
        if n and n >= 1 then CFG.drop_threshold = math.min(200, math.floor(n)) end
    elseif name == "bp_use_gl_drop" then
        CFG.use_gl_drop = (value == true or value == 1 or value == "true" or value == "1")
    elseif name == "bp_anti_retake" then
        CFG.anti_retake = (value == true or value == 1 or value == "true" or value == "1")
    elseif name == "bp_btn_set_drop_pos" then
        local px, py = getPlayerTilePos()
        if px and py then
            CFG.drop_anchor_x = px
            CFG.drop_anchor_y = py
            notifyUser(string.format("Titik awal drop diset ke (%d, %d)", px, py))
        else
            notifyUser("Masuk ke world dulu untuk set posisi drop!")
        end
    elseif name == "bp_btn_reset_drop_pos" then
        CFG.drop_anchor_x = 0
        CFG.drop_anchor_y = 0
        notifyUser("Titik awal drop direset ke otomatis (0,0)")
    elseif name == "bp_max_stacks" then
        local n = tonumber(value)
        if n then CFG.max_stacks_per_tile = math.max(5, math.min(19, math.floor(n))) end
    elseif name == "bp_delay_buy" then
        local n = tonumber(value)
        if n then CFG.delay_buy = math.max(500, math.floor(n)) end
    elseif name == "bp_delay_drop" then
        local n = tonumber(value)
        if n then CFG.delay_drop = math.max(200, math.floor(n)) end
    elseif name == "bp_delay_warp" then
        local n = tonumber(value)
        if n then CFG.delay_warp = math.max(2500, math.floor(n)) end
    end

    savePrefs(CFG)
end

if addHook then
    pcall(addHook, onVariantHook, "onvariant")
    pcall(addHook, onSendPacketHook, "onsendpacket")
    pcall(addHook, onSendPacketRawHook, "onsendpacketraw")
    STATE.hooks_installed = true
end

if applyHook then
    pcall(applyHook)
end

pcall(buildUI)
