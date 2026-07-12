-- KastaCD_ModelWidget.lua - custom AceGUI widget showing a live 3D model
-- preview of an NPC by creature displayID, plus its name/ID as text to
-- the model's right. Used next to KastaPlates' dungeon/NPC pickers.
-- Model and info text live in one widget/frame with plain SetPoint
-- anchors, since two separate AceConfig entries relying on Flow layout
-- didn't reliably stay on the same row.
-- Registered as its own widget type ("KastaCDModel") to avoid colliding
-- with another addon's AceGUI version. Wired up via
-- `type = "input", dialogControl = "KastaCDModel"`; SetLabel carries the
-- info text and SetText carries the stringified displayID.
-- A newly-added .toc entry needs a full client relaunch, not just /reload.

local Type, Version = "KastaCDModel", 2
local AceGUI = LibStub and LibStub("AceGUI-3.0", true)
if not AceGUI then return end

local MODEL_SIZE = 260

local methods = {
    ["OnAcquire"] = function(self)
        self:SetWidth(500)
        self:SetHeight(MODEL_SIZE)
        self.model:ClearModel()
        self.info:SetText("")
    end,

    ["OnRelease"] = function(self)
        self.model:ClearModel()
        self.info:SetText("")
    end,

    ["OnWidthSet"] = function(self, width)
        -- Info text wraps to whatever's left after the fixed-size model.
        self.info:SetWidth(math.max(width - MODEL_SIZE - 20, 50))
    end,

    ["SetLabel"] = function(self, text)
        self.info:SetText(text or "")
    end,

    ["SetText"] = function(self, text)
        local displayID = tonumber(text)
        if displayID then
            self.model:SetDisplayInfo(displayID)
            self.model:Show()
        else
            self.model:ClearModel()
            self.model:Hide()
        end
    end,

    ["SetDisabled"] = function(self, disabled) end,
}

local function Constructor()
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(500, MODEL_SIZE)

    local model = CreateFrame("PlayerModel", nil, frame)
    model:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    model:SetSize(MODEL_SIZE, MODEL_SIZE)
    model:Hide()

    local info = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    info:SetPoint("TOPLEFT", model, "TOPRIGHT", 20, -10)
    info:SetJustifyH("LEFT")
    info:SetJustifyV("TOP")
    info:SetWidth(220)

    local widget = {
        frame = frame,
        model = model,
        info  = info,
        type  = Type,
    }
    for method, func in pairs(methods) do
        widget[method] = func
    end

    return AceGUI:RegisterAsWidget(widget)
end

AceGUI:RegisterWidgetType(Type, Constructor, Version)
