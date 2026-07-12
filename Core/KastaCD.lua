-- KastaCD.lua - entry point (loaded first). Everything else lives in
-- the split files below. Do not add spell data, tracking, UI, or event code here.

KASTACD_VERSION = "1.7.4"
KASTACD_NAME    = "KastaCD"

-- Welcome message printed once on login
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function(self)
    print("Thanks for using |cffff7f00[KastaCD - Party Cooldown Tracker v1.7.4] |cffffffff|Hurl:https://github.com/itsmekasta/KastaCD|h[https://github.com/itsmekasta/KastaCD]|h|r")
    self:UnregisterAllEvents()
end)


