local addonName, ns = ...

-- Saved variable defaults
local defaults = { buffs = {} }

-- Lookup tables for fast aura matching
local idLookup = {}
local nameLookup = {}

function ns.RebuildLookups()
    wipe(idLookup)
    wipe(nameLookup)
    for i, entry in ipairs(CancelationDB.buffs) do
        if entry.id then
            idLookup[entry.id] = i
        end
        if entry.name then
            nameLookup[entry.name:lower()] = i
        end
    end
end

function ns.AddBuff(input)
    local spellId = tonumber(input)
    local name, id

    if spellId then
        id = spellId
        local spellInfo = C_Spell.GetSpellInfo(spellId)
        name = spellInfo and spellInfo.name or ("Spell #" .. spellId)
    else
        name = input:trim()
        id = nil
    end

    if id and idLookup[id] then
        print("|cff00ccffCancelation:|r " .. name .. " is already in the list.")
        return false
    end
    if name and nameLookup[name:lower()] then
        print("|cff00ccffCancelation:|r " .. name .. " is already in the list.")
        return false
    end

    table.insert(CancelationDB.buffs, { id = id, name = name })
    ns.RebuildLookups()
    print("|cff00ccffCancelation:|r Added " .. name .. (id and (" (ID: " .. id .. ")") or "") .. " to the cancel list.")

    if ns.RefreshConfig then
        ns.RefreshConfig()
    end
    return true
end

function ns.RemoveBuff(index)
    local entry = CancelationDB.buffs[index]
    if not entry then return end
    local name = entry.name or ("Spell #" .. entry.id)
    table.remove(CancelationDB.buffs, index)
    ns.RebuildLookups()
    print("|cff00ccffCancelation:|r Removed " .. name .. " from the cancel list.")
    if ns.RefreshConfig then
        ns.RefreshConfig()
    end
end

local function CheckAndCancelBuffs()
    if #CancelationDB.buffs == 0 then return end

    for i = 1, 40 do
        local auraData = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        if not auraData then break end

        local shouldCancel = false

        if auraData.spellId and idLookup[auraData.spellId] then
            shouldCancel = true
        elseif auraData.name and nameLookup[auraData.name:lower()] then
            shouldCancel = true
            -- Resolve the spell ID if we only had the name
            local idx = nameLookup[auraData.name:lower()]
            if idx and CancelationDB.buffs[idx] and not CancelationDB.buffs[idx].id then
                CancelationDB.buffs[idx].id = auraData.spellId
                ns.RebuildLookups()
                if ns.RefreshConfig then
                    ns.RefreshConfig()
                end
            end
        end

        if shouldCancel then
            CancelUnitBuff("player", i, "HELPFUL")
            -- Indices shift after canceling, so restart the scan
            return CheckAndCancelBuffs()
        end
    end
end

-- Throttled check to batch rapid UNIT_AURA events
local checkPending = false
local function ScheduleCheck()
    if checkPending then return end
    checkPending = true
    C_Timer.After(0.1, function()
        checkPending = false
        CheckAndCancelBuffs()
    end)
end

-- Main event frame
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("UNIT_AURA")

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        CancelationDB = CancelationDB or CopyTable(defaults)
        CancelationDB.buffs = CancelationDB.buffs or {}
        ns.RebuildLookups()

        -- Periodic safety-net check every 2 seconds
        C_Timer.NewTicker(2, CheckAndCancelBuffs)

        -- Initialize the config panel after saved variables are ready
        if ns.InitConfig then
            ns.InitConfig()
        end

        print("|cff00ccffCancelation|r loaded. Type |cff00ff00/cancel|r for help.")
    elseif event == "UNIT_AURA" then
        local unit = ...
        if unit == "player" then
            ScheduleCheck()
        end
    end
end)

-- Slash commands
SLASH_CANCELATION1 = "/cancel"
SLASH_CANCELATION2 = "/cancelation"

SlashCmdList["CANCELATION"] = function(msg)
    msg = msg and msg:trim() or ""

    if msg == "" then
        print("|cff00ccffCancelation|r commands:")
        print("  |cff00ff00/cancel [name or spell ID]|r - Add a buff to the cancel list")
        print("  |cff00ff00/cancel remove [index]|r - Remove a buff by its list index")
        print("  |cff00ff00/cancel list|r - Show all buffs being canceled")
        print("  |cff00ff00/cancel config|r - Open the settings panel")
        return
    end

    if msg == "config" or msg == "options" or msg == "settings" then
        if ns.settingsCategory then
            Settings.OpenToCategory(ns.settingsCategory:GetID())
        end
        return
    end

    if msg == "list" then
        if #CancelationDB.buffs == 0 then
            print("|cff00ccffCancelation:|r No buffs in the cancel list.")
            return
        end
        print("|cff00ccffCancelation:|r Buffs being canceled:")
        for i, entry in ipairs(CancelationDB.buffs) do
            local idStr = entry.id and (" (ID: " .. entry.id .. ")") or " (ID: unknown)"
            print("  " .. i .. ". " .. (entry.name or "Unknown") .. idStr)
        end
        return
    end

    local removeIndex = msg:match("^remove%s+(%d+)$")
    if removeIndex then
        removeIndex = tonumber(removeIndex)
        if removeIndex and CancelationDB.buffs[removeIndex] then
            ns.RemoveBuff(removeIndex)
        else
            print("|cff00ccffCancelation:|r Invalid index. Use |cff00ff00/cancel list|r to see indices.")
        end
        return
    end

    ns.AddBuff(msg)
end
