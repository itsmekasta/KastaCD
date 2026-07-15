-- KastaCD_Leaderboard.lua - personal Mythic+ best-time tracker,
-- deliberately not synced between players. Records your own best
-- completion per dungeon, viewable via /kcdboard.
-- Time from GetCompletionInfo() is in milliseconds. Legion 7.3.5
-- predates the BfA rating system, so only the first four return values
-- (mapID, level, time, onTime) are read.

function GetLeaderboardDB()
    KastaCDDB = KastaCDDB or {}
    local db = KastaCDDB.leaderboard
    if not db then
        db = {}
        KastaCDDB.leaderboard = db
    end
    if db.enabled == nil then db.enabled = true end
    if type(db.best) ~= "table" then db.best = {} end   -- [mapID] = { name, time, level, onTime, date }
    return db
end

local function FormatTime(msTime)
    local totalSeconds = math.floor((msTime or 0) / 1000)
    if SecondsToTime then return SecondsToTime(totalSeconds) end
    return string.format("%d:%02d", math.floor(totalSeconds / 60), totalSeconds % 60)
end

local function RecordCompletion()
    local db = GetLeaderboardDB()
    if not db.enabled then return end

    local mapID, level, timeMs, onTime = C_ChallengeMode.GetCompletionInfo()
    if not mapID or not timeMs then return end

    -- GetMapUIInfo is a post-Legion rename/expansion of this API - 7.3.5
    -- only has GetMapInfo(mapID), returning name as its first value.
    local mapName = type(C_ChallengeMode.GetMapInfo) == "function" and C_ChallengeMode.GetMapInfo(mapID) or nil
    local existing = db.best[mapID]

    if not existing or timeMs < existing.time then
        db.best[mapID] = {
            name   = mapName or ("Map " .. tostring(mapID)),
            time   = timeMs,
            level  = level,
            onTime = onTime and true or false,
            date   = date("%Y-%m-%d"),
        }
        print(string.format("|cff44ff44KastaCD:|r New personal best for %s +%s - %s%s",
            mapName or ("Map " .. tostring(mapID)), tostring(level or "?"), FormatTime(timeMs),
            onTime and " |cff44ff44(Timed)|r" or " |cffff4444(Depleted)|r"))
    end
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("CHALLENGE_MODE_COMPLETED")
watcher:SetScript("OnEvent", RecordCompletion)

-- /kcdboard - prints your best time per dungeon. reset wipes recorded data.
SLASH_KASTACDBOARD1 = "/kcdboard"
SlashCmdList["KASTACDBOARD"] = function(msg)
    local db = GetLeaderboardDB()

    if msg and msg:match("^%s*reset%s*$") then
        wipe(db.best)
        print("|cff44ff44KastaCD:|r Personal leaderboard reset.")
        return
    end

    local rows = {}
    for _, entry in pairs(db.best) do
        table.insert(rows, entry)
    end
    table.sort(rows, function(a, b) return (a.name or "") < (b.name or "") end)

    print("|cff44ff44KastaCD Personal Best Times:|r")
    if #rows == 0 then
        print("  No completed Mythic+ runs recorded yet.")
        return
    end
    for _, entry in ipairs(rows) do
        print(string.format("  %s: +%s - %s %s (%s)",
            entry.name, tostring(entry.level or "?"), FormatTime(entry.time),
            entry.onTime and "|cff44ff44(Timed)|r" or "|cffff4444(Depleted)|r",
            entry.date or "?"))
    end
end
