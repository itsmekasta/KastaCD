-- KastaCD_DebuffExtender.lua - extends Blizzard's CompactUnitFrame
-- debuff row from 3 to 12 icons (two stacked rows of 6) on party frames,
-- reusing native CompactDebuffTemplate buttons.
-- Depends on: KastaCD_DB.lua (KastaCDDB must exist)
--
-- RUNTIME DISABLED: writing to f.maxDebuffs/f.debuffFrames on a real
-- CompactRaidFrame taints it even as a plain field write - Blizzard's
-- protected raid-frame layout code later reads that data and gets
-- blocked from calling ClearAllPoints(). Needs a different design (an
-- addon-owned overlay, never touching frame.debuffFrames) before re-enabling.
local KCD_DEBUFF_EXTENDER_RUNTIME_DISABLED = true

function GetDebuffExtenderDB()
    KastaCDDB = KastaCDDB or {}
    local db = KastaCDDB.debuffExtender
    if not db then
        db = {}
        KastaCDDB.debuffExtender = db
    end
    if db.enabled == nil then db.enabled = false end
    return db
end

-- Reposition a single extra debuff icon (i = 4..12) relative to the
-- native row. Icons 4-6 extend the first row to the left of icon 1;
-- icons 7-12 stack a second row above icons 4-9.
local function RepositionDebuffIcon(f, i)
    local debuffFrames = f.debuffFrames
    if not debuffFrames or not debuffFrames[1] or not debuffFrames[i] then return end

    local size = debuffFrames[1]:GetWidth()
    local btn  = debuffFrames[i]

    btn:SetSize(size, size)
    btn:ClearAllPoints()

    if i > 6 then
        btn:SetPoint("BOTTOMRIGHT", debuffFrames[i - 3], "TOPRIGHT", 0, 0)
    else
        btn:SetPoint("TOPRIGHT", debuffFrames[1], "TOPRIGHT", -(size * (i - 3)), 0)
    end
end

-- Create one extra native debuff button (CompactDebuffTemplate) and
-- register it into the frame's own debuffFrames table so Blizzard's
-- CompactUnitFrame_UpdateDebuffs populates/updates it exactly like
-- icons 1-3.
local function CreateExtraDebuffButton(f, i)
    local btn = CreateFrame("Button", nil, UIParent, "CompactDebuffTemplate")
    btn.baseSize = 22
    if f.buffFrames and f.buffFrames[1] then
        btn:SetSize(f.buffFrames[1]:GetSize())
    end
    btn:SetFrameStrata(f:GetFrameStrata() or "MEDIUM")
    btn:SetFrameLevel((f:GetFrameLevel() or 0) + 10)
    f.debuffFrames[i] = btn
    return btn
end

local function ExtendDebuffRow(f)
    for i = 4, 12 do
        RepositionDebuffIcon(f, i)
    end
end

local function ApplyExtendedDebuffs(f)
    if KCD_DEBUFF_EXTENDER_RUNTIME_DISABLED then return end
    local db = GetDebuffExtenderDB()
    if not db.enabled then return end
    if not (f and f.unit and f.unit:match("^party%d$")) then return end
    if not f.debuffFrames then return end

    if f.maxDebuffs ~= 12 then
        f.maxDebuffs = 12
    end

    if not f.debuffFrames[4] then
        for i = 4, 12 do
            CreateExtraDebuffButton(f, i)
        end
        if not f.kcdDebuffHideHooked then
            f:HookScript("OnHide", function()
                for i = 4, 12 do
                    if f.debuffFrames[i] then
                        f.debuffFrames[i]:Hide()
                    end
                end
            end)
            f.kcdDebuffHideHooked = true
        end
    end

    ExtendDebuffRow(f)
end

hooksecurefunc("CompactUnitFrame_UpdateDebuffs", function(f)
    ApplyExtendedDebuffs(f)
end)

-- Re-apply immediately on toggle/roster change.
function RefreshDebuffExtender()
    if KCD_DEBUFF_EXTENDER_RUNTIME_DISABLED then return end
    local db = GetDebuffExtenderDB()
    if not db.enabled then return end

    local candidates = {}
    for i = 1, 5 do
        candidates[#candidates+1] = _G["CompactPartyFrameMember"..i]
        candidates[#candidates+1] = _G["CompactRaidFrame"..i]
    end
    if CompactRaidFrameContainer and CompactRaidFrameContainer.flowFrames then
        for _, f in ipairs(CompactRaidFrameContainer.flowFrames) do
            candidates[#candidates+1] = f
        end
    end

    for _, f in ipairs(candidates) do
        if f and f.unit and f.unit:match("^party%d$") then
            ApplyExtendedDebuffs(f)
        end
    end
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("GROUP_ROSTER_UPDATE")
watcher:RegisterEvent("RAID_ROSTER_UPDATE")
watcher:SetScript("OnEvent", function()
    RefreshDebuffExtender()
end)
