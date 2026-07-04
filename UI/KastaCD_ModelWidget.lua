-- =============================================================
-- KastaCD_ModelWidget.lua
-- A minimal custom AceGUI widget that shows a live 3D model preview of
-- an NPC by creature displayID (Model:SetDisplayInfo), plus its name/NPC
-- ID as text to the model's right - used next to the KastaPlates
-- dungeon/NPC pickers so choosing a name out of a dropdown isn't a total
-- guess at what the enemy actually looks like.
--
-- Both the model AND the info text live inside this ONE widget/frame,
-- positioned with plain SetPoint anchors under this file's own control,
-- rather than as two separate AceConfig option entries relying on
-- AceGUI's Flow layout to land them side by side - that was tried first
-- and didn't reliably keep them on the same row next to each other.
--
-- Registered under a brand-new, KastaCD-only widget type name
-- ("KastaCDModel") rather than any existing AceGUI type, so there's no
-- possibility of colliding with another addon's own bundled copy of a
-- shared library winning LibStub's version race (the same class of
-- problem that broke two earlier attempts at patching AceGUI/AceConfig's
-- own stock files this session).
--
-- Wired up via `type = "input", dialogControl = "KastaCDModel"` in the
-- options table (dialogControl is an existing, stock AceConfig field).
-- AceConfigDialog's FeedOptions calls SetLabel(name) and
-- SetText(get-result) for type="input" controls - this widget repurposes
-- SetLabel to carry the info text (the option's `name` field) and
-- SetText to carry the stringified displayID (the option's `get` field),
-- so one options-table entry drives both halves of this one widget.
--
-- IMPORTANT: this is a brand-new file added to the .toc - per the
-- KastaPlates dungeon-dropdown investigation earlier this session, a
-- newly-added .toc entry needs a full client relaunch (not just
-- /reload) to actually be picked up the first time.
-- =============================================================

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
        -- Info text wraps to whatever's left of the row after the fixed-
        -- size model, instead of a hardcoded guess.
        self.info:SetWidth(math.max(width - MODEL_SIZE - 20, 50))
    end,

    -- Real content setters - see file header comment on why SetLabel/
    -- SetText carry the info text/displayID instead of a plain label and
    -- editable value (this widget has neither).
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
