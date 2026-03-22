local addonName, ns = ...

function ns.InitConfig()
    local panel = CreateFrame("Frame", "CancelationConfigPanel")
    panel:Hide()

    -- Title
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Cancelation")

    local desc = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    desc:SetText("Manage the list of buffs to automatically cancel.")

    -- Global interval setting
    local intervalLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    intervalLabel:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -16)
    intervalLabel:SetText("Default check interval (seconds):")

    local intervalBox = CreateFrame("EditBox", "CancelationIntervalBox", panel, "InputBoxTemplate")
    intervalBox:SetSize(60, 20)
    intervalBox:SetPoint("LEFT", intervalLabel, "RIGHT", 8, 0)
    intervalBox:SetAutoFocus(false)
    intervalBox:SetText(tostring(CancelationDB.defaultInterval or 1.0))

    intervalBox:SetScript("OnEnterPressed", function(self)
        local val = tonumber(self:GetText())
        if val and val >= 0.1 then
            CancelationDB.defaultInterval = val
            self:SetText(tostring(val))
        else
            self:SetText(tostring(CancelationDB.defaultInterval or 1.0))
        end
        self:ClearFocus()
    end)

    intervalBox:SetScript("OnEscapePressed", function(self)
        self:SetText(tostring(CancelationDB.defaultInterval or 1.0))
        self:ClearFocus()
    end)

    local intervalHint = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    intervalHint:SetPoint("TOPLEFT", intervalLabel, "BOTTOMLEFT", 0, -4)
    intervalHint:SetText("How often to check for unwanted buffs. Per-buff overrides can be set below (blank = use default).")

    -- Input area
    local inputLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    inputLabel:SetPoint("TOPLEFT", intervalHint, "BOTTOMLEFT", 0, -16)
    inputLabel:SetText("Add buff (name or spell ID):")

    local inputBox = CreateFrame("EditBox", "CancelationInputBox", panel, "InputBoxTemplate")
    inputBox:SetSize(250, 20)
    inputBox:SetPoint("TOPLEFT", inputLabel, "BOTTOMLEFT", 6, -4)
    inputBox:SetAutoFocus(false)

    local addBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    addBtn:SetSize(80, 22)
    addBtn:SetPoint("LEFT", inputBox, "RIGHT", 8, 0)
    addBtn:SetText("Add")

    -- List header
    local listHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    listHeader:SetPoint("TOPLEFT", inputBox, "BOTTOMLEFT", -6, -20)
    listHeader:SetText("Unwanted Buffs:")

    -- Import/Export section (anchored to bottom of panel, built first so scroll frame can reference it)
    local separator = panel:CreateTexture(nil, "ARTWORK")
    separator:SetHeight(1)
    separator:SetColorTexture(0.5, 0.5, 0.5, 0.5)
    separator:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 8, 80)
    separator:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -8, 80)

    -- Export row
    local exportLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    exportLabel:SetPoint("TOPLEFT", separator, "BOTTOMLEFT", 0, -8)
    exportLabel:SetText("Export:")

    local exportBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    exportBox:SetHeight(20)
    exportBox:SetPoint("LEFT", exportLabel, "RIGHT", 8, 0)
    exportBox:SetPoint("RIGHT", panel, "RIGHT", -96, 0)
    exportBox:SetAutoFocus(false)

    local exportBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    exportBtn:SetSize(80, 22)
    exportBtn:SetPoint("LEFT", exportBox, "RIGHT", 8, 0)
    exportBtn:SetText("Export")

    exportBtn:SetScript("OnClick", function()
        local parts = {}
        for _, entry in ipairs(CancelationDB.buffs) do
            local id = entry.id and tostring(entry.id) or ""
            local name = entry.name or ""
            table.insert(parts, id .. "," .. name)
        end
        exportBox:SetText(table.concat(parts, ";"))
        exportBox:HighlightText()
        exportBox:SetFocus()
    end)

    exportBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    -- Import row
    local importLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    importLabel:SetPoint("TOPLEFT", exportLabel, "BOTTOMLEFT", 0, -12)
    importLabel:SetText("Import:")

    local importBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    importBox:SetHeight(20)
    importBox:SetPoint("LEFT", importLabel, "RIGHT", 8, 0)
    importBox:SetPoint("RIGHT", panel, "RIGHT", -96, 0)
    importBox:SetAutoFocus(false)

    local importBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    importBtn:SetSize(80, 22)
    importBtn:SetPoint("LEFT", importBox, "RIGHT", 8, 0)
    importBtn:SetText("Import")

    local function DoImport(text)
        if not text or text:trim() == "" then return end
        local entries = {}
        local malformed = 0
        for part in text:gmatch("[^;]+") do
            part = part:trim()
            if part ~= "" then
                local idStr, name = part:match("^(%d*),(.+)$")
                if name then
                    name = name:trim()
                    local id = tonumber(idStr)
                    table.insert(entries, { id = id, name = (name ~= "") and name or nil })
                else
                    malformed = malformed + 1
                end
            end
        end
        local added, skipped = ns.ImportBuffs(entries)
        local msg = "|cff00ccffCancelation:|r Import complete: " .. added .. " added, " .. skipped .. " skipped"
        if malformed > 0 then
            msg = msg .. ", " .. malformed .. " malformed"
        end
        print(msg .. ".")
        importBox:SetText("")
        importBox:ClearFocus()
    end

    importBtn:SetScript("OnClick", function()
        DoImport(importBox:GetText())
    end)

    importBox:SetScript("OnEnterPressed", function(self)
        DoImport(self:GetText())
    end)

    importBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    -- Scroll frame for the buff list (bottom anchored above the import/export section)
    local scrollFrame = CreateFrame("ScrollFrame", "CancelationScrollFrame", panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", listHeader, "BOTTOMLEFT", 0, -8)
    scrollFrame:SetPoint("BOTTOMRIGHT", separator, "TOPRIGHT", -30, 8)

    local scrollChild = CreateFrame("Frame", "CancelationScrollChild")
    scrollFrame:SetScrollChild(scrollChild)
    scrollChild:SetWidth(1)

    scrollFrame:SetScript("OnSizeChanged", function(self, width)
        scrollChild:SetWidth(width)
    end)

    -- Empty state text
    local emptyText = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    emptyText:SetPoint("TOP", 0, -20)
    emptyText:SetText("No buffs in the cancel list.\nUse the input above or /cancel [name/ID] to add buffs.")
    emptyText:Hide()

    -- Row pool
    local rows = {}

    local function CreateRow(parent, index)
        local row = CreateFrame("Frame", nil, parent)
        row:SetHeight(28)

        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(1, 1, 1, 0)
        row.bg = bg

        local indexText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        indexText:SetPoint("LEFT", 4, 0)
        indexText:SetWidth(24)
        indexText:SetJustifyH("RIGHT")
        row.indexText = indexText

        local nameText = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        nameText:SetPoint("LEFT", indexText, "RIGHT", 8, 0)
        nameText:SetWidth(200)
        nameText:SetJustifyH("LEFT")
        row.nameText = nameText

        local idText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        idText:SetPoint("LEFT", nameText, "RIGHT", 8, 0)
        idText:SetWidth(120)
        idText:SetJustifyH("LEFT")
        row.idText = idText

        local rowIntervalLabel = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        rowIntervalLabel:SetPoint("LEFT", idText, "RIGHT", 12, 0)
        rowIntervalLabel:SetText("Interval:")
        row.intervalLabel = rowIntervalLabel

        local rowIntervalBox = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
        rowIntervalBox:SetSize(50, 20)
        rowIntervalBox:SetPoint("LEFT", rowIntervalLabel, "RIGHT", 4, 0)
        rowIntervalBox:SetAutoFocus(false)
        row.intervalBox = rowIntervalBox

        local removeBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        removeBtn:SetSize(70, 22)
        removeBtn:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        removeBtn:SetText("Remove")
        row.removeBtn = removeBtn

        return row
    end

    local function RefreshList()
        intervalBox:SetText(tostring(CancelationDB.defaultInterval or 1.0))
        for _, row in ipairs(rows) do
            row:Hide()
        end

        if not CancelationDB or not CancelationDB.buffs or #CancelationDB.buffs == 0 then
            emptyText:Show()
            scrollChild:SetHeight(60)
            return
        end

        emptyText:Hide()

        local yOffset = 0
        for i, entry in ipairs(CancelationDB.buffs) do
            if not rows[i] then
                rows[i] = CreateRow(scrollChild, i)
            end
            local row = rows[i]

            row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset)
            row:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
            row.bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.05 or 0)
            row.indexText:SetText(i .. ".")
            row.nameText:SetText(entry.name or "Unknown")
            row.idText:SetText(entry.id and ("ID: " .. entry.id) or "ID: unknown")

            row.removeBtn:SetScript("OnClick", function()
                ns.RemoveBuff(i)
            end)

            local entryInterval = entry.interval
            row.intervalBox:SetText(entryInterval and tostring(entryInterval) or "")
            row.intervalBox:SetScript("OnEnterPressed", function(self)
                local val = tonumber(self:GetText())
                if val and val >= 0.1 then
                    CancelationDB.buffs[i].interval = val
                elseif self:GetText():trim() == "" then
                    CancelationDB.buffs[i].interval = nil
                    self:SetText("")
                else
                    self:SetText(entryInterval and tostring(entryInterval) or "")
                end
                self:ClearFocus()
            end)
            row.intervalBox:SetScript("OnEscapePressed", function(self)
                self:SetText(entryInterval and tostring(entryInterval) or "")
                self:ClearFocus()
            end)

            row:Show()
            yOffset = yOffset + 28
        end

        scrollChild:SetHeight(math.max(1, yOffset))
    end

    ns.RefreshConfig = RefreshList

    -- Input handlers
    addBtn:SetScript("OnClick", function()
        local text = inputBox:GetText():trim()
        if text ~= "" then
            ns.AddBuff(text)
            inputBox:SetText("")
            inputBox:ClearFocus()
        end
    end)

    inputBox:SetScript("OnEnterPressed", function(self)
        local text = self:GetText():trim()
        if text ~= "" then
            ns.AddBuff(text)
            self:SetText("")
        end
        self:ClearFocus()
    end)

    inputBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    panel:SetScript("OnShow", RefreshList)

    -- Register with the modern Settings API
    local category = Settings.RegisterCanvasLayoutCategory(panel, "Cancelation")
    ns.settingsCategory = category
    Settings.RegisterAddOnCategory(category)

    RefreshList()
end
