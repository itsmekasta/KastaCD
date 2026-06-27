-- =============================================================
-- KastaCD.lua  –  Entry point (loaded first by KastaCD.toc)
-- Everything else lives in the split files below this one.
-- DO NOT add spell data, tracking, UI, or event code here.
-- =============================================================

KASTACD_VERSION = "1.2"
KASTACD_NAME    = "KastaCD"

-- Welcome message printed once on login
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function(self)
    print("Thanks for using |cffff7f00[KastaCD - Party Cooldown Tracker v1.2] |cffffffff|Hurl:https://github.com/itsmekasta/KastaCD|h[https://github.com/itsmekasta/KastaCD]|h|r")
    self:UnregisterAllEvents()
end)
