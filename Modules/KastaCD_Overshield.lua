-- =============================================================
-- KastaCD_Overshield.lua
-- Ported from Derangement's Shield Meters (originally a standalone
-- Mists of Pandaria addon, interface 50420 - see
-- DerangementShieldMeters.lua/.toc in this same folder for the
-- original reference source).
--
-- Blizzard's default absorb/shield overlay (the bar shown for things
-- like Power Word: Shield, Ice Barrier, etc.) is clipped to the unit's
-- health bar width - once a unit is at full HP, any remaining shield
-- amount beyond max HP ("overshield") becomes invisible even though
-- it's still absorbing damage. This hooks the same four Blizzard
-- functions the original addon did to re-anchor/resize that overlay so
-- it always reflects the FULL absorb amount, on both compact frames
-- (party/raid) and standalone frames (player/target/focus/pet).
--
-- Unlike the original, this is toggleable (Misc > Overshield Display)
-- - every hook below checks IsOvershieldEnabled() first and does
-- nothing when disabled, leaving Blizzard's own already-applied
-- (vanilla) behavior untouched. hooksecurefunc hooks themselves can't
-- be uninstalled once registered, so "disabled" means "installed but
-- inert", not "not hooked".
-- Depends on: KastaCD_DB.lua (KastaCDDB must exist)
-- =============================================================

local ABSORB_GLOW_ALPHA  = 0.6
local ABSORB_GLOW_OFFSET = -5

-- -------------------------------------------------------------
-- DB accessor with lazy defaults - same pattern as GetIntDB/GetCCDB/
-- GetAnnounceDB elsewhere in this addon. On by default (the user asked
-- for shields to just always be visible, not an opt-in they'd have to
-- remember to enable).
-- -------------------------------------------------------------
function GetOvershieldDB()
    if type(KastaCDDB) ~= "table" then
        return { enabled = true, alwaysShowGlow = false }
    end
    if type(KastaCDDB.overshield) ~= "table" then
        KastaCDDB.overshield = {}
    end
    local db = KastaCDDB.overshield
    if db.enabled == nil then db.enabled = true end
    if db.alwaysShowGlow == nil then db.alwaysShowGlow = false end
    return db
end

-- RE-ENABLED (2026-07-08): was force-disabled while chasing a taint
-- report that turned out to be caused by a Zygor Guides conflict, not
-- this module. The genuine tileSize-nil crash fix (guards further below)
-- stays regardless.
local function IsOvershieldEnabled()
    return GetOvershieldDB().enabled == true
end

-- -------------------------------------------------------------
-- Standalone frames (player/target/focus/pet/party-in-frame-mode) -
-- frame.totalAbsorbBar / frame.totalAbsorbBarOverlay / frame.healthbar
-- (lowercase b), matching Blizzard's UnitFrame.lua naming.
-- -------------------------------------------------------------
hooksecurefunc("UnitFrame_Update",
	function(frame)
		if not IsOvershieldEnabled() then return end
		local absorbBar = frame.totalAbsorbBar
		if not absorbBar then return end

		local absorbOverlay = frame.totalAbsorbBarOverlay
		if not absorbOverlay then return end

		-- Deliberately NOT calling absorbOverlay:SetParent(...) here -
		-- confirmed live that reparenting a Blizzard-owned frame from here
		-- taints it (and, once tainted, ANY later unrelated protected
		-- action - e.g. clicking a toy - can get blocked and blamed on
		-- KastaCD for the rest of the session, not just while in combat).
		-- SetPoint anchors visually to any frame regardless of literal
		-- parent-child relationship, so this overlay never actually needed
		-- to be reparented onto the health bar to begin with - only
		-- ClearAllPoints (routine, not a taint risk) is needed here;
		-- positioning itself happens in the heal-prediction hook below.
		absorbOverlay:ClearAllPoints()

		local absorbGlow = frame.overAbsorbGlow
		if absorbGlow then
			absorbGlow:ClearAllPoints()
			absorbGlow:SetPoint("TOPLEFT", absorbOverlay, "TOPLEFT", ABSORB_GLOW_OFFSET, 0)
			absorbGlow:SetPoint("BOTTOMLEFT", absorbOverlay, "BOTTOMLEFT", ABSORB_GLOW_OFFSET, 0)
			absorbGlow:SetAlpha(ABSORB_GLOW_ALPHA)
		end
	end
)

-- -------------------------------------------------------------
-- Compact frames (party/raid) - frame.totalAbsorb / frame.totalAbsorbOverlay
-- / frame.healthBar (uppercase B), matching Blizzard's
-- CompactUnitFrame.lua naming - deliberately different casing from the
-- standalone-frame hook above, this isn't a typo.
-- -------------------------------------------------------------
hooksecurefunc("CompactUnitFrame_UpdateAll",
	function(frame)
		if not IsOvershieldEnabled() then return end
		local absorbBar = frame.totalAbsorb
		if not absorbBar then return end

		local absorbOverlay = frame.totalAbsorbOverlay
		if not absorbOverlay then return end

		-- See the matching comment in UnitFrame_Update above - no
		-- SetParent, confirmed live to taint the frame and later block
		-- unrelated protected actions for the rest of the session.
		absorbOverlay:ClearAllPoints()

		local absorbGlow = frame.overAbsorbGlow
		if absorbGlow then
			absorbGlow:ClearAllPoints()
			absorbGlow:SetPoint("TOPLEFT", absorbOverlay, "TOPLEFT", ABSORB_GLOW_OFFSET, 0)
			absorbGlow:SetPoint("BOTTOMLEFT", absorbOverlay, "BOTTOMLEFT", ABSORB_GLOW_OFFSET, 0)
			absorbGlow:SetAlpha(ABSORB_GLOW_ALPHA)
		end
	end
)

-- -------------------------------------------------------------
-- Standalone frames: the actual overshield sizing/positioning, driven
-- by UnitGetTotalAbsorbs (the unit's REAL total absorb amount,
-- uncapped by max HP - this is what makes the "beyond full HP" portion
-- visible at all).
-- -------------------------------------------------------------
hooksecurefunc("UnitFrameHealPredictionBars_Update",
	function(frame)
		if not IsOvershieldEnabled() then return end
		local absorbBar = frame.totalAbsorbBar
		if not absorbBar then return end

		local absorbOverlay = frame.totalAbsorbBarOverlay
		if not absorbOverlay then return end

		local _, maxHealth = frame.healthbar:GetMinMaxValues()
		if maxHealth <= 0 then return end

		local totalAbsorb = UnitGetTotalAbsorbs(frame.unit) or 0
		if totalAbsorb > maxHealth then
			totalAbsorb = maxHealth
		end

		if totalAbsorb > 0 then
			if absorbBar:IsShown() then
				absorbOverlay:SetPoint("TOPRIGHT", absorbBar, "TOPRIGHT", 0, 0)
				absorbOverlay:SetPoint("BOTTOMRIGHT", absorbBar, "BOTTOMRIGHT", 0, 0)
			else
				absorbOverlay:SetPoint("TOPRIGHT", frame.healthbar, "TOPRIGHT", 0, 0)
				absorbOverlay:SetPoint("BOTTOMRIGHT", frame.healthbar, "BOTTOMRIGHT", 0, 0)
			end

			-- tileSize isn't a stock Texture property - it's only ever set
			-- by Blizzard's own FrameXML template for this exact overlay,
			-- which some dynamically-generated compact frames apparently
			-- don't carry (confirmed live: a Lua error here, absorbOverlay.
			-- tileSize nil, while a raid profile was being applied). Bail
			-- rather than error - this frame just keeps Blizzard's default
			-- (clipped-at-max-hp) shield display for this update instead.
			if not absorbOverlay.tileSize then return end

			local totalWidth, totalHeight = frame.healthbar:GetSize()
			local barSize = totalAbsorb / maxHealth * totalWidth

			absorbOverlay:SetWidth(barSize)
			absorbOverlay:SetTexCoord(0, barSize / absorbOverlay.tileSize, 0, totalHeight / absorbOverlay.tileSize)
			absorbOverlay:Show()

			if GetOvershieldDB().alwaysShowGlow and frame.overAbsorbGlow then
				frame.overAbsorbGlow:Show()
			end
		end
	end
)

-- -------------------------------------------------------------
-- Compact frames: same as above but for party/raid frames, using
-- UnitGetTotalAbsorbs(frame.displayedUnit) since compact frames track
-- displayedUnit separately from unit (e.g. raid pets/vehicle swaps).
-- -------------------------------------------------------------
hooksecurefunc("CompactUnitFrame_UpdateHealPrediction",
	function(frame)
		if not IsOvershieldEnabled() then return end
		local absorbBar = frame.totalAbsorb
		if not absorbBar then return end

		local absorbOverlay = frame.totalAbsorbOverlay
		if not absorbOverlay then return end

		local _, maxHealth = frame.healthBar:GetMinMaxValues()
		if maxHealth <= 0 then return end

		local totalAbsorb = UnitGetTotalAbsorbs(frame.displayedUnit) or 0
		if totalAbsorb > maxHealth then
			totalAbsorb = maxHealth
		end

		if totalAbsorb > 0 then
			if absorbBar:IsShown() then
				absorbOverlay:SetPoint("TOPRIGHT", absorbBar, "TOPRIGHT", 0, 0)
				absorbOverlay:SetPoint("BOTTOMRIGHT", absorbBar, "BOTTOMRIGHT", 0, 0)
			else
				absorbOverlay:SetPoint("TOPRIGHT", frame.healthBar, "TOPRIGHT", 0, 0)
				absorbOverlay:SetPoint("BOTTOMRIGHT", frame.healthBar, "BOTTOMRIGHT", 0, 0)
			end

			-- See the matching guard in UnitFrameHealPredictionBars_Update
			-- above - tileSize is missing on some dynamically-generated
			-- compact frames and this crashed live.
			if not absorbOverlay.tileSize then return end

			local totalWidth, totalHeight = frame.healthBar:GetSize()
			local barSize = totalAbsorb / maxHealth * totalWidth

			absorbOverlay:SetWidth(barSize)
			absorbOverlay:SetTexCoord(0, barSize / absorbOverlay.tileSize, 0, totalHeight / absorbOverlay.tileSize)
			absorbOverlay:Show()

			if GetOvershieldDB().alwaysShowGlow and frame.overAbsorbGlow then
				frame.overAbsorbGlow:Show()
			end
		end
	end
)
