local addonName, ns = ...

-- Saved variable defaults
local defaults = { buffs = {}, defaultInterval = 1.0 }

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

function ns.GetEffectiveInterval(entry)
    return entry and entry.interval or CancelationDB.defaultInterval or 1.0
end

-- Runtime tracking of per-buff last-cancel times (keyed by spellId or lowercase name)
local lastCancel = {}

local function GetCancelKey(entry)
    return entry.id or (entry.name and entry.name:lower())
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
    -- Check immediately in case the player already has this buff
    if ns.CheckNow then
        C_Timer.After(0, ns.CheckNow)
    end
    return true
end

-- Batch import: entries is a list of { id = number|nil, name = string|nil }
-- Returns added, skipped counts. Single rebuild/refresh/check at the end.
function ns.ImportBuffs(entries)
    local added, skipped = 0, 0
    for _, entry in ipairs(entries) do
        local id, name = entry.id, entry.name
        local isDuplicate = false
        if id and idLookup[id] then
            isDuplicate = true
        elseif name and nameLookup[name:lower()] then
            isDuplicate = true
        end
        if isDuplicate then
            print("|cff00ccffCancelation:|r Import skipped (already exists): " .. (name or ("Spell #" .. (id or "?"))))
            skipped = skipped + 1
        else
            table.insert(CancelationDB.buffs, { id = id, name = name })
            added = added + 1
        end
    end
    if added > 0 then
        ns.RebuildLookups()
        if ns.RefreshConfig then
            ns.RefreshConfig()
        end
        if ns.CheckNow then
            C_Timer.After(0, ns.CheckNow)
        end
    end
    return added, skipped
end

function ns.RemoveBuff(index)
    local entry = CancelationDB.buffs[index]
    if not entry then return end
    local key = GetCancelKey(entry)
    if key then lastCancel[key] = nil end
    local name = entry.name or ("Spell #" .. entry.id)
    table.remove(CancelationDB.buffs, index)
    ns.RebuildLookups()
    print("|cff00ccffCancelation:|r Removed " .. name .. " from the cancel list.")
    if ns.RefreshConfig then
        ns.RefreshConfig()
    end
end

local inCombat = false
local ScheduleRetry -- forward declaration

-- Inner scan function, separated so pcall can catch taint errors
local function ScanAndCancelAuras()
    local now = GetTime()
    local needsRebuild = false
    local canceledAny = true
    local passes = 0
    while canceledAny and passes < 5 do
        canceledAny = false
        passes = passes + 1
        for i = 1, 40 do
            local auraData = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
            if not auraData then break end

            local shouldCancel = false
            local buffIdx

            if auraData.spellId and auraData.spellId ~= 0 and idLookup[auraData.spellId] then
                shouldCancel = true
                buffIdx = idLookup[auraData.spellId]
            else
                local lowerName = auraData.name and auraData.name ~= "" and auraData.name:lower()
                if lowerName and nameLookup[lowerName] then
                    shouldCancel = true
                    buffIdx = nameLookup[lowerName]
                    -- Resolve the spell ID if we only had the name (deferred rebuild after loop)
                    if buffIdx and CancelationDB.buffs[buffIdx] and not CancelationDB.buffs[buffIdx].id then
                        CancelationDB.buffs[buffIdx].id = auraData.spellId
                        needsRebuild = true
                    end
                end
            end

            if shouldCancel and buffIdx then
                local entry = CancelationDB.buffs[buffIdx]
                local key = GetCancelKey(entry)
                local interval = ns.GetEffectiveInterval(entry)
                -- Only cancel if enough time has passed since last cancel of this buff
                if key and (not lastCancel[key] or (now - lastCancel[key]) >= interval) then
                    CancelUnitBuff("player", i, "HELPFUL")
                    lastCancel[key] = now
                    canceledAny = true
                    break
                else
                    -- Interval not yet elapsed; schedule a retry for when it is
                    local remaining = interval - (now - (lastCancel[key] or now))
                    ScheduleRetry(remaining)
                end
            end
        end
    end

    if needsRebuild then
        ns.RebuildLookups()
        if ns.RefreshConfig then
            ns.RefreshConfig()
        end
    end
end

local function CheckAndCancelBuffs()
    if InCombatLockdown() then return end
    if #CancelationDB.buffs == 0 then return end
    -- pcall catches taint errors when combat starts between the
    -- InCombatLockdown check and the aura data access
    local ok, err = pcall(ScanAndCancelAuras)
    if not ok and err and not err:match("tainted") then
        geterrorhandler()(err)
    end
end

ns.CheckNow = CheckAndCancelBuffs

-- Schedule a one-shot retry when a buff was skipped due to interval
local retryPending = false
function ScheduleRetry(delay)
    if retryPending then return end
    retryPending = true
    C_Timer.After(delay, function()
        retryPending = false
        if not InCombatLockdown() then
            CheckAndCancelBuffs()
        end
    end)
end

-- Throttled check - coalesces rapid UNIT_AURA events
local COALESCE_WINDOW = 0.1
local lastCheck = 0
local checkPending = false
local function ScheduleCheck()
    if inCombat then return end
    if checkPending then return end
    checkPending = true
    local delay = math.max(COALESCE_WINDOW - (GetTime() - lastCheck), 0)
    C_Timer.After(delay, function()
        checkPending = false
        if InCombatLockdown() then return end
        lastCheck = GetTime()
        CheckAndCancelBuffs()
    end)
end

-- Main event frame
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterUnitEvent("UNIT_AURA", "player")
frame:RegisterEvent("PLAYER_REGEN_DISABLED") -- enter combat
frame:RegisterEvent("PLAYER_REGEN_ENABLED")  -- leave combat

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        CancelationDB = CancelationDB or CopyTable(defaults)
        CancelationDB.buffs = CancelationDB.buffs or {}
        CancelationDB.defaultInterval = CancelationDB.defaultInterval or defaults.defaultInterval
        ns.RebuildLookups()

        -- Initial check once saved variables are ready
        C_Timer.After(1, function()
            lastCheck = GetTime()
            CheckAndCancelBuffs()
        end)

        -- Initialize the config panel after saved variables are ready
        if ns.InitConfig then
            ns.InitConfig()
        end

        print("|cff00ccffCancelation|r loaded. Type |cff00ff00/cancel|r for help.")
    elseif event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
        checkPending = false
        retryPending = false
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
        ScheduleCheck()
    elseif event == "UNIT_AURA" then
        ScheduleCheck()
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
