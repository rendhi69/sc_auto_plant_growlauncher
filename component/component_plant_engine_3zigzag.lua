-- ============================================================================
-- COMPONENT: REUSABLE PLANT & SPLICE ENGINE (3 PETAK ZIGZAG & 1BY1)
-- ============================================================================
-- File: component_plant_engine_3zigzag.lua
-- Lokasi: script/component/component_plant_engine_3zigzag.lua
--
-- KEGUNAAN:
--   Komponen serbaguna (plug-and-play) untuk menanam bibit (Planting) dan
--   mengawinkan bibit (Splicing) secara otomatis dengan pola 3-Petak Zigzag
--   Gaya Lucifer (Kiri, Tengah, Kanan per langkah 3 petak) maupun 1-by-1
--   tanpa perlu menulis ulang deteksi platform, splice retry, dan row sweeper.
--
-- FITUR LENGKAP:
--   1. Mode 3 Petak Zigzag (Gaya Lucifer):
--      Bot melangkah per 3 petak (X = 1, 4, 7, ... 97) dan menanam 3 petak
--      sekaligus (X - 1, X, X + 1) di jangkauan tangannya, dengan penanganan
--      otomatis untuk sisa petak di ujung (X = 98 dan 99).
--   2. Mode Splice Cerdas (Kawin 2 Seed):
--      Mendukung penanaman Seed 1 lalu ditimpa Seed 2 dengan sistem verifikasi
--      multi-retry hingga pohon baru berhasil terbentuk (anti bibit miss/drop).
--   3. Deteksi Platform & Pijakan Otomatis:
--      Mendeteksi baris tanaman yang valid (memiliki pijakan di Y + 1) dan
--      menghindari tile pintu, jammer, serta lock.
--   4. Row Sweeper Anti-Miss:
--      Pembersihan otomatis di akhir setiap baris untuk menambal petak yang
--      terlewat akibat lag atau latency tinggi server Growtopia.
--   5. Restock Callback Support:
--      Memanggil callback saat stok seed di tas habis, lalu otomatis kembali
--      ke koordinat terakhir untuk melanjutkan penanaman.
-- ============================================================================

local BOREN_PLANT_ENGINE = {}
BOREN_PLANT_ENGINE.__index = BOREN_PLANT_ENGINE

-- ============================================================================
-- HELPER INTERNAL (SAFE CLIENT ABSTRACTION)
-- ============================================================================
local function safeSleep(ms)
    ms = math.max(10, tonumber(ms) or 50)
    if sleep then pcall(sleep, ms)
    elseif Sleep then pcall(Sleep, ms)
    end
end

local function getPlayerPos()
    if getLocal then
        local ok, p = pcall(getLocal)
        if ok and p then
            local px = (p.posX or (p.pos and p.pos.x))
            local py = (p.posY or (p.pos and p.pos.y))
            if px and py then
                return math.floor((px + 10) / 32), math.floor((py + 15) / 32)
            end
        end
    end
    if getBotPos then
        local ok, bx, by = pcall(getBotPos)
        if ok and bx and by then return bx, by end
    end
    return nil, nil
end

local function getTileSafe(tx, ty)
    if getTile then
        local ok, t = pcall(getTile, tx, ty)
        if ok and t then return t end
    end
    return nil
end

local function getInvCount(itemID)
    itemID = tonumber(itemID) or 0
    if itemID <= 0 then return 0 end
    if getInventory then
        local ok, inv = pcall(getInventory)
        if ok and type(inv) == "table" then
            for _, it in pairs(inv) do
                local id = it.id or it.itemid or it.itemId
                if id == itemID then
                    return tonumber(it.count or it.amount or 0) or 0
                end
            end
        end
    end
    if findItem then
        local ok, c = pcall(findItem, itemID)
        if ok and tonumber(c) then return tonumber(c) end
    end
    return 0
end

local function sendPlantPacket(tx, ty, itemID)
    itemID = tonumber(itemID) or 0
    if itemID <= 0 then return false end

    -- Jalur 1: sendPacketRaw (Packet 3)
    if sendPacketRaw then
        local px, py = getPlayerPos()
        local rawX = (px and px * 32) or (tx * 32)
        local rawY = (py and py * 32) or (ty * 32)
        local state = (rawX > (tx * 32)) and 48 or 32
        local ok = pcall(sendPacketRaw, false, {
            type  = 3,
            value = itemID,
            px    = tx,
            py    = ty,
            x     = rawX,
            y     = rawY,
            state = state
        })
        if ok then return true end
    end

    -- Jalur 2: place native
    if place then
        local ok = pcall(place, itemID, tx, ty)
        if ok then return true end
    end
    if placeTileAt then
        local ok = pcall(placeTileAt, tx, ty, itemID, false)
        if ok then return true end
    end

    return false
end

local function isTreeTile(t)
    if not t then return false end
    if t.readyharvest == true or t.ready_to_harvest == true then return true end
    if t.canHarvest and type(t.canHarvest) == "function" then
        local okH, resH = pcall(t.canHarvest, t)
        if okH and resH == true then return true end
    end
    if t.extra and type(t.extra) == "table" then
        local fruits = tonumber(t.extra.fruitcount) or 0
        if fruits > 0 then return true end
    end
    return false
end

-- ============================================================================
-- KONSTRUKTOR
-- ============================================================================
-- Parameter opts:
--   seed_1_id       : ID Seed utama (default: 3 / Dirt Seed)
--   seed_2_id       : ID Seed kedua untuk Splice (default: 15 / Rock Seed)
--   splice_mode     : boolean (true = kawin 2 seed, false = tanam 1 seed biasa)
--   mode            : "3zigzag" (default gaya Lucifer) atau "1by1"
--   plant_delay     : Delay packet tanam (ms, default: 80)
--   splice_delay    : Delay antar seed 1 dan seed 2 (ms, default: 200)
--   step_delay      : Delay per langkah bot (ms, default: 90)
--   min_seed_bp     : Batas minimal seed di tas untuk memicu restock (default: 3)
--   enable_sweeper  : boolean (default: true, row sweeper anti miss)
-- ============================================================================
function BOREN_PLANT_ENGINE.new(opts)
    opts = opts or {}
    local self = setmetatable({}, BOREN_PLANT_ENGINE)

    self.seed_1_id      = tonumber(opts.seed_1_id) or 3
    self.seed_2_id      = tonumber(opts.seed_2_id) or 15
    self.splice_mode    = (opts.splice_mode == true)
    self.mode           = opts.mode or "3zigzag"
    self.plant_delay    = tonumber(opts.plant_delay) or 180
    self.splice_delay   = tonumber(opts.splice_delay) or 180
    self.step_delay     = tonumber(opts.step_delay) or 90
    self.min_seed_bp    = tonumber(opts.min_seed_bp) or 3
    self.enable_sweeper = (opts.enable_sweeper ~= false)

    -- State internal
    self.running        = true
    self.paused         = false
    self.planted_count  = 0
    self.fresh_seeds    = {} -- Cache timestamp seed yang baru ditanam

    return self
end

-- ============================================================================
-- 1. DETEKSI STATUS TILE TANAM & SPLICE
-- ============================================================================
function BOREN_PLANT_ENGINE:isFreshlyPlanted(tx, ty)
    local key = tx .. "_" .. ty
    local t = self.fresh_seeds[key]
    if t and (os.time() - t) <= 25 then
        return true
    end
    return false
end

function BOREN_PLANT_ENGINE:getTilePlantStatus(tx, ty)
    if tx < 0 or tx > 99 or ty < 0 or ty > 53 then return "INVALID" end

    local tAt = getTileSafe(tx, ty)
    if not tAt then return "INVALID" end

    -- Jangan tanam di tile yang terhalang bedrock, door, lock, jammer
    local fg = tonumber(tAt.fg) or 0
    if fg == 6 or fg == 8 or fg == 242 or fg == 226 or fg == 5638 or fg == 4994 then
        return "INVALID"
    end

    -- Harus ada pijakan di bawahnya (ty + 1)
    local tBelow = getTileSafe(tx, ty + 1)
    if not tBelow or (tonumber(tBelow.fg) or 0) == 0 then
        return "INVALID"
    end

    local s1 = self.seed_1_id
    local s2 = self.seed_2_id
    local isSplice = (self.splice_mode and s2 > 0 and s1 > 0 and s1 ~= s2)

    -- 1. Mode Single Seed Biasa
    if not isSplice then
        if fg == 0 then
            return "EMPTY"
        elseif fg == s1 or isTreeTile(tAt) then
            return "DONE"
        else
            return "INVALID"
        end
    end

    -- 2. Mode Splice (Kawin 2 Seed)
    if fg == 0 then
        return "EMPTY"
    end

    if fg == s1 then
        if isTreeTile(tAt) then
            return "DONE" -- Sudah jadi pohon berbuah
        else
            return "NEEDS_SPLICE_2" -- Butuh ditimpa Seed 2 (baik baru ditanam atau sisa di world)
        end
    end

    if fg == s2 then
        if isTreeTile(tAt) then
            return "DONE"
        else
            return "NEEDS_SPLICE_1" -- Butuh ditimpa Seed 1
        end
    end

    -- Jika fg bukan 0, bukan s1, bukan s2 -> Berarti sudah sukses tersplice jadi pohon baru!
    return "DONE"
end

function BOREN_PLANT_ENGINE:isTilePlantable(tx, ty)
    local st = self:getTilePlantStatus(tx, ty)
    return (st == "EMPTY" or st == "NEEDS_SPLICE_2" or st == "NEEDS_SPLICE_1")
end

-- ============================================================================
-- 2. PERGERAKAN AMAN (SAFE NAVIGATION)
-- ============================================================================
function BOREN_PLANT_ENGINE:moveTo(tx, ty)
    tx = math.max(0, math.min(99, math.floor(tx or 0)))
    ty = math.max(0, math.min(53, math.floor(ty or 0)))

    local px, py = getPlayerPos()
    if px == tx and py == ty then return true end

    local pFn = findPath or FindPath
    if pFn then
        pcall(pFn, tx, ty)
        safeSleep(self.step_delay)
        return true
    end
    return false
end

-- ============================================================================
-- 3. LOGIKA EKSEKUSI TANAM & SPLICE DENGAN MULTI-RETRY
-- ============================================================================
function BOREN_PLANT_ENGINE:punchTile(tx, ty)
    if not sendPacketRaw then return false end
    local px, py = getPlayerPos()
    local state = (px > tx) and 48 or 32
    local rawPx = px * 32
    local rawPy = py * 32
    return pcall(sendPacketRaw, false, {
        type  = 3,
        value = 18,
        px    = tx,
        py    = ty,
        x     = rawPx,
        y     = rawPy,
        state = state,
    })
end

function BOREN_PLANT_ENGINE:clearFailedSplice(tx, ty)
    for _ = 1, 4 do
        if not self.running then break end
        self:punchTile(tx, ty)
        safeSleep(150)
        local t = getTileSafe(tx, ty)
        local fgNow = tonumber(t and t.fg) or 0
        if fgNow == 0 then return true end
        if fgNow ~= self.seed_1_id and fgNow ~= self.seed_2_id then return true end
    end
    return false
end

function BOREN_PLANT_ENGINE:plantAndSpliceTile(tx, ty)
    local st = self:getTilePlantStatus(tx, ty)
    if st == "DONE" or st == "INVALID" then return true end

    local s1 = self.seed_1_id
    local s2 = self.seed_2_id
    local isSplice = (self.splice_mode and s2 > 0 and s1 > 0 and s1 ~= s2)

    local delayPlant  = tonumber(self.plant_delay) or 180
    local delaySplice = tonumber(self.splice_delay) or 180

    -- A. Mode Single Seed
    if not isSplice then
        if st == "EMPTY" then
            sendPlantPacket(tx, ty, s1)
            safeSleep(delayPlant)
            self.planted_count = self.planted_count + 1
        end
        return true
    end

    -- B. Mode Splice (Kawin 2 Seed dengan Multi-Retry & Recovery)
    local maxSpliceAttempts = 3
    for attempt = 1, maxSpliceAttempts do
        local curSt = self:getTilePlantStatus(tx, ty)
        if curSt == "DONE" then
            self.planted_count = self.planted_count + 1
            return true
        end

        if curSt == "EMPTY" then
            sendPlantPacket(tx, ty, s1)
            safeSleep(delaySplice)
            sendPlantPacket(tx, ty, s2)
            safeSleep(delayPlant)
        elseif curSt == "NEEDS_SPLICE_2" then
            sendPlantPacket(tx, ty, s2)
            safeSleep(delayPlant)
        elseif curSt == "NEEDS_SPLICE_1" then
            sendPlantPacket(tx, ty, s1)
            safeSleep(delayPlant)
        end

        -- Verifikasi hasil splice
        for _ = 1, 3 do
            safeSleep(50)
            local tCheck = getTileSafe(tx, ty)
            local fgNow = tonumber(tCheck and tCheck.fg) or 0
            if fgNow ~= 0 and fgNow ~= s1 and fgNow ~= s2 then
                self.planted_count = self.planted_count + 1
                return true
            end
        end
        safeSleep(80)
    end

    -- Auto-Recovery untuk un-spliced sprouted plant
    local lastSt = self:getTilePlantStatus(tx, ty)
    if lastSt == "NEEDS_SPLICE_2" or lastSt == "NEEDS_SPLICE_1" then
        local cleared = self:clearFailedSplice(tx, ty)
        if cleared then
            safeSleep(100)
            sendPlantPacket(tx, ty, s1)
            safeSleep(delaySplice)
            sendPlantPacket(tx, ty, s2)
            safeSleep(delayPlant)
            self.planted_count = self.planted_count + 1
            return true
        end
    end

    return true
end

function BOREN_PLANT_ENGINE:plantSection(spotList, plantY)
    if not spotList or #spotList == 0 then return true end

    local s1 = self.seed_1_id
    local s2 = self.seed_2_id
    local isSplice = (self.splice_mode and s2 > 0 and s1 > 0 and s1 ~= s2)
    local delayPlant  = tonumber(self.plant_delay) or 180
    local delaySplice = tonumber(self.splice_delay) or 180

    -- A. Mode Single Seed
    if not isSplice then
        for _, sx in ipairs(spotList) do
            if not self.running then break end
            while self.paused do safeSleep(300) if not self.running then break end end
            if self:getTilePlantStatus(sx, plantY) == "EMPTY" then
                sendPlantPacket(sx, plantY, s1)
                safeSleep(delayPlant)
                self.planted_count = self.planted_count + 1
            end
        end

        for _ = 1, 2 do
            local needRetry = false
            for _, sx in ipairs(spotList) do
                if self:getTilePlantStatus(sx, plantY) == "EMPTY" then
                    needRetry = true
                    sendPlantPacket(sx, plantY, s1)
                    safeSleep(delayPlant)
                end
            end
            if not needRetry then break end
        end
        return true
    end

    -- B. Mode Batch Section Splice (3-Petak Sekaligus)
    -- Tahap 1: Pasang Seed 1 pada semua petak EMPTY
    local plantedS1 = {}
    for _, sx in ipairs(spotList) do
        if not self.running then break end
        while self.paused do safeSleep(300) if not self.running then break end end
        local st = self:getTilePlantStatus(sx, plantY)
        if st == "EMPTY" then
            sendPlantPacket(sx, plantY, s1)
            plantedS1[sx] = true
            safeSleep(delayPlant)
        end
    end

    -- Tahap 2: Cooldown Server Growtopia (> 200ms)
    safeSleep(delaySplice)

    -- Tahap 3: Pasang Seed 2 untuk menimpa Seed 1
    for _, sx in ipairs(spotList) do
        if not self.running then break end
        while self.paused do safeSleep(300) if not self.running then break end end
        local st = self:getTilePlantStatus(sx, plantY)
        if plantedS1[sx] or st == "NEEDS_SPLICE_2" or st == "EMPTY" then
            sendPlantPacket(sx, plantY, s2)
            safeSleep(delayPlant)
        elseif st == "NEEDS_SPLICE_1" then
            sendPlantPacket(sx, plantY, s1)
            safeSleep(delayPlant)
        end
    end

    -- Tahap 4: In-Place Verification & Retry Sebelum Melangkah
    safeSleep(140)
    for retry = 1, 3 do
        if not self.running then break end
        local allDone = true
        for _, sx in ipairs(spotList) do
            local st = self:getTilePlantStatus(sx, plantY)
            if st == "NEEDS_SPLICE_2" then
                allDone = false
                sendPlantPacket(sx, plantY, s2)
                safeSleep(delayPlant)
            elseif st == "NEEDS_SPLICE_1" then
                allDone = false
                sendPlantPacket(sx, plantY, s1)
                safeSleep(delayPlant)
            elseif st == "EMPTY" then
                allDone = false
                sendPlantPacket(sx, plantY, s1)
                safeSleep(delaySplice)
                sendPlantPacket(sx, plantY, s2)
                safeSleep(delayPlant)
            end
        end
        if allDone then break end
        safeSleep(120)
    end

    -- Tahap 5: Auto-Recovery untuk semak gagal splice (Punch & Replant)
    for _, sx in ipairs(spotList) do
        if not self.running then break end
        local st = self:getTilePlantStatus(sx, plantY)
        if st == "NEEDS_SPLICE_2" or st == "NEEDS_SPLICE_1" then
            local cleared = self:clearFailedSplice(sx, plantY)
            if cleared then
                safeSleep(100)
                sendPlantPacket(sx, plantY, s1)
                safeSleep(delaySplice)
                sendPlantPacket(sx, plantY, s2)
                safeSleep(delayPlant)
                self.planted_count = self.planted_count + 1
            end
        end
    end

    return true
end

-- ============================================================================
-- 4. CEK STOK SEED DI TAS
-- ============================================================================
function BOREN_PLANT_ENGINE:hasEnoughSeedInBackpack()
    local s1Count = getInvCount(self.seed_1_id)
    if not self.splice_mode then
        return s1Count >= self.min_seed_bp
    else
        local s2Count = getInvCount(self.seed_2_id)
        return (s1Count >= self.min_seed_bp) and (s2Count >= self.min_seed_bp)
    end
end

-- ============================================================================
-- 5. EKSEKUSI PENANAMAN 1 BARIS (3-ZIGZAG ATAU 1BY1)
-- ============================================================================
function BOREN_PLANT_ENGINE:plantRow(plantY, restockCb, goingRight)
    if goingRight == nil then goingRight = true end
    self.current_dir = goingRight

    if self.mode == "3zigzag" then
        if goingRight then
            -- =================================================================
            -- POLA 3 PETAK ZIGZAG: KIRI KE KANAN (X = 1 s/d 97, lalu 98 & 99)
            -- =================================================================
            self:moveTo(0, plantY)
            local standX = 1
            while standX <= 97 do
                if not self.running then break end
                while self.paused do safeSleep(300) if not self.running then break end end

                local sLeft   = standX - 1
                local sCenter = standX
                local sRight  = standX + 1

                local needPlant = (sLeft >= 0 and self:isTilePlantable(sLeft, plantY))
                               or self:isTilePlantable(sCenter, plantY)
                               or (sRight <= 99 and self:isTilePlantable(sRight, plantY))

                if needPlant then
                    -- Cek stok sebelum mendekati
                    if not self:hasEnoughSeedInBackpack() then
                        if restockCb then
                            local ok = restockCb(self.seed_1_id, self.seed_2_id, standX, plantY)
                            if not ok then return false, "RESTOCK_FAILED" end
                        else
                            return false, "NO_STOCK"
                        end
                    end

                    self:moveTo(standX, plantY)

                    local sectionSpots = {}
                    if sLeft >= 0 then table.insert(sectionSpots, sLeft) end
                    table.insert(sectionSpots, sCenter)
                    if sRight <= 99 then table.insert(sectionSpots, sRight) end

                    self:plantSection(sectionSpots, plantY)
                end

                standX = standX + 3
            end

            -- Tangani ujung kanan platform (petak 98 dan 99)
            if self:isTilePlantable(98, plantY) or self:isTilePlantable(99, plantY) then
                if not self:hasEnoughSeedInBackpack() then
                    if restockCb then
                        local ok = restockCb(self.seed_1_id, self.seed_2_id, 98, plantY)
                        if not ok then return false, "RESTOCK_FAILED" end
                    else
                        return false, "NO_STOCK"
                    end
                end
                self:moveTo(98, plantY)
                self:plantSection({ 98, 99 }, plantY)
            else
                self:moveTo(98, plantY)
            end

        else
            -- =================================================================
            -- POLA 3 PETAK ZIGZAG: KANAN KE KIRI (98 & 99 dulu, lalu X = 97 s/d 1)
            -- =================================================================
            self:moveTo(98, plantY)
            if self:isTilePlantable(99, plantY) or self:isTilePlantable(98, plantY) then
                if not self:hasEnoughSeedInBackpack() then
                    if restockCb then
                        local ok = restockCb(self.seed_1_id, self.seed_2_id, 98, plantY)
                        if not ok then return false, "RESTOCK_FAILED" end
                    else
                        return false, "NO_STOCK"
                    end
                end
                self:moveTo(98, plantY)
                self:plantSection({ 99, 98 }, plantY)
            end

            local standX = 97
            while standX >= 1 do
                if not self.running then break end
                while self.paused do safeSleep(300) if not self.running then break end end

                local sRight  = standX + 1
                local sCenter = standX
                local sLeft   = standX - 1

                local needPlant = (sRight <= 99 and self:isTilePlantable(sRight, plantY))
                               or self:isTilePlantable(sCenter, plantY)
                               or (sLeft >= 0 and self:isTilePlantable(sLeft, plantY))

                if needPlant then
                    if not self:hasEnoughSeedInBackpack() then
                        if restockCb then
                            local ok = restockCb(self.seed_1_id, self.seed_2_id, standX, plantY)
                            if not ok then return false, "RESTOCK_FAILED" end
                        else
                            return false, "NO_STOCK"
                        end
                    end

                    self:moveTo(standX, plantY)

                    local sectionSpots = {}
                    if sRight <= 99 then table.insert(sectionSpots, sRight) end
                    table.insert(sectionSpots, sCenter)
                    if sLeft >= 0 then table.insert(sectionSpots, sLeft) end

                    self:plantSection(sectionSpots, plantY)
                end

                standX = standX - 3
            end

            if self:isTilePlantable(0, plantY) then
                if not self:hasEnoughSeedInBackpack() then
                    if restockCb then
                        local ok = restockCb(self.seed_1_id, self.seed_2_id, 0, plantY)
                        if not ok then return false, "RESTOCK_FAILED" end
                    else
                        return false, "NO_STOCK"
                    end
                end
                self:moveTo(0, plantY)
                self:plantSection({ 0 }, plantY)
            else
                self:moveTo(0, plantY)
            end
        end

    else
        -- =====================================================================
        -- POLA 1-BY-1 (Satu per satu petak sesuai arah gerak)
        -- =====================================================================
        if goingRight then
            self:moveTo(0, plantY)
            for curX = 0, 99 do
                if not self.running then break end
                while self.paused do safeSleep(300) if not self.running then break end end

                if self:isTilePlantable(curX, plantY) then
                    if not self:hasEnoughSeedInBackpack() then
                        if restockCb then
                            local ok = restockCb(self.seed_1_id, self.seed_2_id, curX, plantY)
                            if not ok then return false, "RESTOCK_FAILED" end
                        else
                            return false, "NO_STOCK"
                        end
                    end
                    self:moveTo(curX, plantY)
                    self:plantSection({ curX }, plantY)
                end
            end
            self:moveTo(98, plantY)
        else
            self:moveTo(98, plantY)
            for curX = 99, 0, -1 do
                if not self.running then break end
                while self.paused do safeSleep(300) if not self.running then break end end

                if self:isTilePlantable(curX, plantY) then
                    if not self:hasEnoughSeedInBackpack() then
                        if restockCb then
                            local ok = restockCb(self.seed_1_id, self.seed_2_id, curX, plantY)
                            if not ok then return false, "RESTOCK_FAILED" end
                        else
                            return false, "NO_STOCK"
                        end
                    end
                    self:moveTo(curX, plantY)
                    self:plantSection({ curX }, plantY)
                end
            end
            self:moveTo(0, plantY)
        end
    end

    -- =========================================================================
    -- ROW SWEEPER: Tambal otomatis petak yang terlewat di baris ini
    -- =========================================================================
    if self.enable_sweeper then
        local missedSpots = {}
        if goingRight then
            for x = 0, 99 do
                if self:isTilePlantable(x, plantY) then table.insert(missedSpots, x) end
            end
        else
            for x = 99, 0, -1 do
                if self:isTilePlantable(x, plantY) then table.insert(missedSpots, x) end
            end
        end

        if #missedSpots > 0 then
            for _, mx in ipairs(missedSpots) do
                if not self.running then break end
                if self:isTilePlantable(mx, plantY) then
                    if not self:hasEnoughSeedInBackpack() then
                        if restockCb then
                            local ok = restockCb(self.seed_1_id, self.seed_2_id, mx, plantY)
                            if not ok then return false, "RESTOCK_FAILED" end
                        else
                            return false, "NO_STOCK"
                        end
                    end
                    self:moveTo(mx, plantY)
                    self:plantSection({ mx }, plantY)
                end
            end
        end
    end

    return true
end

-- ============================================================================
-- 6. DETEKSI & HITUNG SELURUH BARIS PLATFORM DI WORLD
-- ============================================================================
function BOREN_PLANT_ENGINE:hasPlantableSpotsInRow(plantY)
    if plantY < 0 or plantY > 53 then return false end
    for x = 0, 99 do
        if self:isTilePlantable(x, plantY) then
            return true
        end
    end
    return false
end

function BOREN_PLANT_ENGINE:detectRows()
    local rows = {}
    for y = 0, 53 do
        if self:hasPlantableSpotsInRow(y) then
            table.insert(rows, y)
        end
    end
    return rows
end

function BOREN_PLANT_ENGINE:countPlantableSpots()
    local total = 0
    for y = 0, 53 do
        for x = 0, 99 do
            if self:isTilePlantable(x, y) then
                total = total + 1
            end
        end
    end
    return total
end

function BOREN_PLANT_ENGINE:start()
    self.running = true
    self.paused = false
end

function BOREN_PLANT_ENGINE:stop()
    self.running = false
end

function BOREN_PLANT_ENGINE:pause(p)
    if p == nil then p = true end
    self.paused = p
end

-- ============================================================================
-- 7. EKSEKUSI TANAM SELURUH WORLD (DARI BARIS ATAS KE BAWAH)
-- ============================================================================
function BOREN_PLANT_ENGINE:plantWorld(restockCb, progressCb)
    self.running = true
    self.paused  = false
    self.planted_count = 0

    local rows = self:detectRows()
    if #rows == 0 then
        self.running = false
        return true, 0 -- World sudah penuh ter-plant
    end

    for idx, y in ipairs(rows) do
        if not self.running then break end

        -- Arah dinamis berdasarkan posisi bot saat ini (hemat jalan & anti bolak-balik)
        local curPx = getPlayerTilePos()
        local goingRight = true
        if curPx and curPx >= 50 then
            goingRight = false
        else
            goingRight = true
        end

        local ok, err = self:plantRow(y, restockCb, goingRight)
        if not ok then
            self.running = false
            return false, err
        end

        if progressCb then
            pcall(progressCb, y, idx, #rows, self.planted_count, goingRight)
        end
    end

    self.running = false
    return true, self.planted_count
end

-- ============================================================================
-- 8. UI ATTACHMENT HELPER (GROWLAUNCHER)
-- ============================================================================
function BOREN_PLANT_ENGINE:attachToUI(uiTab, prefix)
    if not uiTab then return end
    prefix = prefix or "pe_"

    uiTab:addLabel("Pengaturan Pola Tanam & Bibit:")
    uiTab:addToggle("Pola Tanam 3 Petak Sekaligus (Gaya Lucifer)", self.mode == "3zigzag", prefix .. "mode_3zigzag", true)
    uiTab:addToggle("Aktifkan Splice (Kawin 2 Seed)", self.splice_mode, prefix .. "splice_mode", true)
    uiTab:addInputInt("ID Seed 1 (Utama)", tostring(self.seed_1_id), "Seed ID 1", "Contoh: 3 (Dirt) / 4585 (Pepper)", "Tag", prefix .. "seed_1_id")
    uiTab:addInputInt("ID Seed 2 (Splice)", tostring(self.seed_2_id), "Seed ID 2", "Contoh: 15 (Cave)", "Tag", prefix .. "seed_2_id")
    uiTab:addInputInt("Delay Tanam (ms)", tostring(self.plant_delay), "Delay", "Contoh: 80", "Clock", prefix .. "plant_delay")
    uiTab:addInputInt("Delay Splice (ms)", tostring(self.splice_delay), "Delay", "Contoh: 200", "Clock", prefix .. "splice_delay")
end

function BOREN_PLANT_ENGINE:handleUIValue(name, val, prefix)
    prefix = prefix or "pe_"
    if name == prefix .. "mode_3zigzag" then
        self.mode = (val == true or val == 1) and "3zigzag" or "1by1"
        return true
    elseif name == prefix .. "splice_mode" then
        self.splice_mode = (val == true or val == 1)
        return true
    elseif name == prefix .. "seed_1_id" then
        local num = tonumber(val)
        if num and num > 0 then self.seed_1_id = math.floor(num) end
        return true
    elseif name == prefix .. "seed_2_id" then
        local num = tonumber(val)
        if num and num > 0 then self.seed_2_id = math.floor(num) end
        return true
    elseif name == prefix .. "plant_delay" then
        local num = tonumber(val)
        if num and num >= 10 then self.plant_delay = math.floor(num) end
        return true
    elseif name == prefix .. "splice_delay" then
        local num = tonumber(val)
        if num and num >= 50 then self.splice_delay = math.floor(num) end
        return true
    end
    return false
end

-- Daftarkan ke Global agar bisa dipanggil langsung
_G.BOREN_PLANT_ENGINE = BOREN_PLANT_ENGINE
return BOREN_PLANT_ENGINE
