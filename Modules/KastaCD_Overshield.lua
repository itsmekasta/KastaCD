-- KastaCD_Overshield.lua - ported from Derangement's Shield Meters.
-- Blizzard's absorb overlay is clipped to the health bar width, so any
-- shield beyond max HP ("overshield") becomes invisible even while
-- still absorbing. Hooks the same four Blizzard functions the original
-- addon did to re-anchor/resize the overlay to the full absorb amount,
-- on both compact and standalone frames. Toggleable (Misc > Overshield
-- Display) - hooks can't be uninstalled, so "disabled" means inert, not
-- unhooked.
-- Depends on: KastaCD_DB.lua (KastaCDDB must exist)

local ABSORB_GLOW_ALPHA  = 0.6
local ABSORB_GLOW_OFFSET = -5

-- DB accessor with lazy defaults, on by default.
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

local function IsOvershieldEnabled()
    return GetOvershieldDB().enabled == true
end

-- Standalone frames (player/target/focus/pet) - frame.totalAbsorbBar /
-- totalAbsorbBarOverlay / healthbar (lowercase b), Blizzard's UnitFrame.lua naming.
hooksecurefunc("UnitFrame_Update",
	function(frame)
		if not IsOvershieldEnabled() then return end
		local absorbBar = frame.totalAbsorbBar
		if not absorbBar then return end

		local absorbOverlay = frame.totalAbsorbBarOverlay
		if not absorbOverlay then return end

		-- Not SetParent - reparenting a Blizzard-owned frame taints it.
		-- SetPoint anchors visually regardless of literal parentage.
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

-- Compact frames (party/raid) - frame.totalAbsorb / totalAbsorbOverlay /
-- healthBar (uppercase B), Blizzard's CompactUnitFrame.lua naming.
hooksecurefunc("CompactUnitFrame_UpdateAll",
	function(frame)
		if not IsOvershieldEnabled() then return end
		local absorbBar = frame.totalAbsorb
		if not absorbBar then return end

		local absorbOverlay = frame.totalAbsorbOverlay
		if not absorbOverlay then return end

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

-- Standalone frames: overshield sizing/positioning, driven by
-- UnitGetTotalAbsorbs (real total absorb, uncapped by max HP).
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

			-- tileSize isn't a stock Texture property - some dynamically
			-- generated compact frames don't carry it. Bail rather than error.
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

-- Compact frames: same as above, using frame.displayedUnit since compact
-- frames track it separately from unit (raid pets/vehicle swaps).
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
