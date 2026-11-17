-- ============================================================================
-- BOREN HUB IMGUI - TAB PLANT UI MODULE (STACK-SAFE & 1:1 LAYOUT REFERENSI)
-- File: imgui_hub/tab_plant.lua
-- ============================================================================

local TabPlant = {
    id    = "plant",
    label = "Plant",
}

local addInputBuf = ""

local function notify(msg)
    if sendNotification then
        pcall(sendNotification, msg)
    end
end

function TabPlant.render(HUB)
    local W = HUB.widgets
    local E = HUB.plant
    if not W or not E then
        ImGui.Text("Modul Plant belum siap.")
        return
    end

    local pal = W.getColors()
    local availW, availH = W.getAvailSize()

    -- ========================================================================
    -- BARIS 1: Enable [Toggle]  |  Loop [Toggle]
    -- ========================================================================
    ImGui.Text("Enable")
    ImGui.SameLine()
    local chEn, newEn = W.toggleSwitch("plant_enable", E.STATE.enabled)
    if chEn then
        if newEn then E.start() else E.stop() end
    end

    ImGui.SameLine()
    W.textColored(pal.textMuted, "   |   ")
    ImGui.SameLine()
    ImGui.Text("Loop")
    ImGui.SameLine()
    local chLp, newLp = W.toggleSwitch("plant_loop", E.CFG.loop_enabled)
    if chLp then
        E.CFG.loop_enabled = newLp
        E.saveData()
    end

    -- ========================================================================
    -- BARIS 2: [ Seed Storage [Required] ]  [ Remove Inaccessible ]
    -- ========================================================================
    local btnRemW = 148
    local storInputW = math.max(120, availW - btnRemW - 10)
    local pushedW1 = ImGui.PushItemWidth and pcall(ImGui.PushItemWidth, storInputW)
    local chStor, newStor = W.inputTextHint("##plant_storage", "Seed Storage [Required]", E.CFG.storage_raw, 256)
    if pushedW1 and ImGui.PopItemWidth then pcall(ImGui.PopItemWidth) end
    if chStor then
        E.CFG.storage_raw = newStor
        E.saveData()
    end

    ImGui.SameLine()
    if W.button("Remove Inaccessible", btnRemW, 0) then
        local removed = E.removeInaccessible()
        notify("Dihapus " .. tostring(removed) .. " world inaccessible.")
    end

    -- ========================================================================
    -- BAGIAN TENGAH: TABEL 5 KOLOM DI DALAM CHILD SCROLLABLE (STACK-SAFE)
    -- ========================================================================
    local tableH = math.max(110, availH - 96)
    local childSize = W.vec2(0, tableH)
    local okChild, childOpen = false, false
    if ImGui.BeginChild then
        if childSize then
            okChild, childOpen = pcall(ImGui.BeginChild, "##plant_tbl_scroll", childSize, true)
        else
            okChild, childOpen = pcall(ImGui.BeginChild, "##plant_tbl_scroll")
        end
    end

    if okChild then
        if childOpen then
            if ImGui.BeginTable then
                local okTbl, tblOpen = pcall(ImGui.BeginTable, "##plant_world_table", 5, W.getTableFlags())
                if not okTbl then
                    okTbl, tblOpen = pcall(ImGui.BeginTable, "##plant_world_table", 5)
                end
                if okTbl and tblOpen then
                    pcall(function()
                        ImGui.TableSetupColumn("Name")
                        ImGui.TableSetupColumn("Door ID")
                        ImGui.TableSetupColumn("Seed ID")
                        ImGui.TableSetupColumn("Splice ID")
                        ImGui.TableSetupColumn("Status")
                        ImGui.TableHeadersRow()

                        for i, row in ipairs(E.STATE.rows) do
                            ImGui.TableNextRow()

                            ImGui.TableSetColumnIndex(0)
                            local isSel = (E.STATE.selected_idx == i)
                            local rowLabel = tostring(row.name or "") .. "##row_" .. tostring(i)
                            if ImGui.Selectable then
                                local okS, clicked = pcall(ImGui.Selectable, rowLabel, isSel)
                                if okS and clicked then
                                    E.STATE.selected_idx = isSel and 0 or i
                                end
                            else
                                ImGui.Text(tostring(row.name or ""))
                            end

                            ImGui.TableSetColumnIndex(1)
                            ImGui.Text(row.door ~= "" and tostring(row.door) or "-")

                            ImGui.TableSetColumnIndex(2)
                            ImGui.Text(tostring(tonumber(row.seed_id) or 0))

                            ImGui.TableSetColumnIndex(3)
                            local sp = tonumber(row.splice_id) or 0
                            ImGui.Text(sp > 0 and tostring(sp) or "-")

                            ImGui.TableSetColumnIndex(4)
                            W.textColored(W.statusColor(row.status), tostring(row.status or "Ready"))
                        end
                    end)
                    -- WAJIB selalu dipanggil jika BeginTable mengembalikan true
                    ImGui.EndTable()
                end
            else
                -- Fallback sederhana jika versi GL tidak memiliki BeginTable
                for i, row in ipairs(E.STATE.rows) do
                    ImGui.Text(string.format("%d. %s | %s | %d | %d | %s",
                        i, tostring(row.name), tostring(row.door),
                        tonumber(row.seed_id) or 0, tonumber(row.splice_id) or 0, tostring(row.status)))
                end
            end
        end
        -- WAJIB selalu dipanggil setiap kali BeginChild dipanggil (meskipun childOpen == false!)
        ImGui.EndChild()
    end

    -- ========================================================================
    -- BARIS BAWAH: [ Name:ID:SeedID:SpliceID ] [ + ] [ - ] [ Import ] [ Export ] [ Reset Status ]
    -- ========================================================================
    local fixedBtnsW = 26 + 26 + 56 + 56 + 92 + 36
    local addInputW = math.max(100, availW - fixedBtnsW)
    local pushedW2 = ImGui.PushItemWidth and pcall(ImGui.PushItemWidth, addInputW)
    local chAdd, newAdd = W.inputTextHint("##plant_add_line", "Name:ID:SeedID:SpliceID", addInputBuf, 256)
    if pushedW2 and ImGui.PopItemWidth then pcall(ImGui.PopItemWidth) end
    if chAdd then
        addInputBuf = newAdd
    end

    ImGui.SameLine()
    if W.button("+##plant_add", 26, 0) then
        local parsed = E.parseRowLine(addInputBuf)
        if parsed then
            table.insert(E.STATE.rows, parsed)
            addInputBuf = ""
            E.saveData()
            E.addLog("[+] Ditambahkan: " .. E.formatRowLine(parsed))
        else
            notify("Format salah! Gunakan Name:ID:SeedID:SpliceID")
        end
    end

    ImGui.SameLine()
    if W.button("-##plant_del", 26, 0) then
        local idx = E.STATE.selected_idx
        if idx < 1 or idx > #E.STATE.rows then idx = #E.STATE.rows end
        if idx >= 1 and idx <= #E.STATE.rows then
            local rem = table.remove(E.STATE.rows, idx)
            E.STATE.selected_idx = 0
            E.saveData()
            E.addLog("[-] Dihapus: " .. tostring(rem and rem.name or ""))
        end
    end

    ImGui.SameLine()
    if W.button("Import", 56, 0) then
        local clip = ""
        if ImGui.GetClipboardText then
            local okC, resC = pcall(ImGui.GetClipboardText)
            if okC and type(resC) == "string" then clip = resC end
        end
        if clip == "" then
            notify("Clipboard kosong! Salin daftar Name:ID:SeedID:SpliceID dulu.")
        else
            local added = 0
            for line in clip:gmatch("[^\r\n]+") do
                local parsed = E.parseRowLine(line)
                if parsed then
                    table.insert(E.STATE.rows, parsed)
                    added = added + 1
                end
            end
            if added > 0 then
                E.saveData()
                E.addLog(string.format("[Import] Berhasil mengimpor %d baris dari clipboard.", added))
                notify("Berhasil import " .. tostring(added) .. " world!")
            else
                notify("Tidak ada baris valid di clipboard.")
            end
        end
    end

    ImGui.SameLine()
    if W.button("Export", 56, 0) then
        local out = {}
        for _, row in ipairs(E.STATE.rows) do
            table.insert(out, E.formatRowLine(row))
        end
        if ImGui.SetClipboardText then
            pcall(ImGui.SetClipboardText, table.concat(out, "\n"))
            E.addLog(string.format("[Export] %d baris disalin ke clipboard.", #out))
            notify("Exported " .. tostring(#out) .. " world ke clipboard!")
        end
    end

    ImGui.SameLine()
    if W.button("Reset Status", 92, 0) then
        E.resetAllStatus()
        notify("Semua status di-reset ke Ready.")
    end
end

return TabPlant
