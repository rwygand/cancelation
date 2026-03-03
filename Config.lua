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

    -- Input area
    local inputLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    inputLabel:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -16)
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

    -- Scroll frame for the buff list
    local scrollFrame = CreateFrame("ScrollFrame", "CancelationScrollFrame", panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", listHeader, "BOTTOMLEFT", 0, -8)
    scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -30, 16)

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

        local removeBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        removeBtn:SetSize(70, 22)
        removeBtn:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        removeBtn:SetText("Remove")
        row.removeBtn = removeBtn

        return row
    end

    local function RefreshList()
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
