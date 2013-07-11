local E, L, V, P, G = unpack(select(2, ...)); --Inport: Engine, Locales, PrivateDB, ProfileDB, GlobalDB
local NP = E:NewModule('NamePlates', 'AceHook-3.0', 'AceEvent-3.0', 'AceTimer-3.0')
local LSM = LibStub("LibSharedMedia-3.0")


--TODO:
--[[
	- Performance Tweaks
	- Cleanup Auras Code
	- Raid Icon aura check appears faulty
	- Assure all variables are voided out on nameplate hide
	- Rewrite configuration GUI
	- Add health text
	- Add health threshold coloring via glow texture.
]]

local numChildren = -1
local twipe = table.wipe
local band = bit.band

NP.NumTargetAuraChecks = -1
NP.NumMouseoverAuraChecks = -1
NP.NumTransparentPlates = 0
NP.CreatedPlates = {};
NP.Healers = {};

NP.ByRaidIcon = {}			-- Raid Icon to GUID 		-- ex.  ByRaidIcon["SKULL"] = GUID
NP.ByName = {}				-- Name to GUID (PVP)
NP.AuraList = {}	-- Two Dimensional
NP.AuraSpellID = {}
NP.AuraExpiration = {}
NP.AuraStacks = {}
NP.AuraCaster = {}
NP.AuraDuration = {}
NP.AuraTexture = {}
NP.AuraType = {}
NP.AuraTarget = {}
NP.CachedAuraDurations = {}
NP.AurasCache = {}

NP.HealerSpecs = {
	[L['Restoration']] = true,
	[L['Holy']] = true,
	[L['Discipline']] = true,
	[L['Mistweaver']] = true,
}

NP.RaidTargetReference = {
	["STAR"] = 0x00000001,
	["CIRCLE"] = 0x00000002,
	["DIAMOND"] = 0x00000004,
	["TRIANGLE"] = 0x00000008,
	["MOON"] = 0x00000010,
	["SQUARE"] = 0x00000020,
	["CROSS"] = 0x00000040,
	["SKULL"] = 0x00000080,
}

NP.RaidIconCoordinate = {
	[0]		= { [0]		= "STAR", [0.25]	= "MOON", },
	[0.25]	= { [0]		= "CIRCLE", [0.25]	= "SQUARE",	},
	[0.5]	= { [0]		= "DIAMOND", [0.25]	= "CROSS", },
	[0.75]	= { [0]		= "TRIANGLE", [0.25]	= "SKULL", }, 
}

NP.MAX_DISPLAYABLE_DEBUFFS = 4;
NP.MAX_SMALLNP_DISPLAYABLE_DEBUFFS = 2;

local AURA_UPDATE_INTERVAL = 0.1
local AURA_TYPE_BUFF = 1
local AURA_TYPE_DEBUFF = 6
local AURA_TARGET_HOSTILE = 1
local AURA_TARGET_FRIENDLY = 2
local AuraList, AuraGUID = {}, {}
local AURA_TYPE = {
	["Buff"] = 1,
	["Curse"] = 2,
	["Disease"] = 3,
	["Magic"] = 4,
	["Poison"] = 5,
	["Debuff"] = 6,
}
local RaidIconIndex = {
	"STAR",
	"CIRCLE",
	"DIAMOND",
	"TRIANGLE",
	"MOON",
	"SQUARE",
	"CROSS",
	"SKULL",
}
local TimeColors = {
	[0] = '|cffeeeeee',
	[1] = '|cffeeeeee',
	[2] = '|cffeeeeee',
	[3] = '|cffFFEE00',
	[4] = '|cfffe0000',
}

function NP:OnUpdate(elapsed)
	local count = WorldFrame:GetNumChildren()
	if(count ~= numChildren) then
		numChildren = count
		NP:ScanFrames(WorldFrame:GetChildren())
	end

	for blizzPlate, plate in pairs(NP.CreatedPlates) do
		if blizzPlate:IsShown() then
			plate:SetPoint("CENTER", WorldFrame, "BOTTOMLEFT", blizzPlate:GetCenter())
			plate:Show()
		else
			plate:Hide()
		end
	end

	if(self.elapsed and self.elapsed > 0.2) then
		NP.NumTransparentPlates = 0
		NP:ForEachPlate('SetAlpha')
		NP:ForEachPlate('SetUnitInfo')
		NP:ForEachPlate('ColorizeAndScale')
		NP:ForEachPlate('SetLevel')
		NP:ForEachPlate('CheckFilter')

		self.elapsed = 0
	else
		self.elapsed = (self.elapsed or 0) + elapsed
	end	
end

function NP:CheckFilter()
	local myPlate = NP.CreatedPlates[self]
	local name = self.name:GetText()
	if NP.Healers[name] then
		myPlate.healerIcon:Show()
	else
		myPlate.healerIcon:Hide()
	end
end

function NP:CheckBGHealers()
	local name, _, talentSpec
	for i = 1, GetNumBattlefieldScores() do
		name, _, _, _, _, _, _, _, _, _, _, _, _, _, _, talentSpec = GetBattlefieldScore(i);
		if name then
			name = name:match("(.+)%-.+") or name
			if name and self.HealerSpecs[talentSpec] then
				self.Healers[name] = talentSpec
			elseif name and self.Healers[name] then
				self.Healers[name] = nil;
			end
		end
	end
end

function NP:CheckArenaHealers()
	local numOpps = GetNumArenaOpponentSpecs()
	if not (numOpps > 1) then return end
	
	for i=1, 5 do
		local name = UnitName(format('arena%d', i))
		if name and name ~= UNKNOWN then
			local s = GetArenaOpponentSpec(i)
			local _, talentSpec = nil, UNKNOWN
			if s and s > 0 then
				_, talentSpec = GetSpecializationInfoByID(s)
			end
			
			if talentSpec and talentSpec ~= UNKNOWN and self.HealerSpecs[talentSpec] then
				self.Healers[name] = talentSpec
			end
		end
	end
end

function NP:SetLevel()
	local region = select(4, self:GetRegions())
	if region and region:GetObjectType() == 'FontString' then
		self.level = region
	end

	local myPlate = NP.CreatedPlates[self]

	if self.level:IsShown() then
		if NP.db.level.enable then
			local level, elite, boss, mylevel = self.level:GetObjectType() == 'FontString' and tonumber(self.level:GetText()) or nil, self.eliteIcon:IsShown(), self.bossIcon:IsShown(), UnitLevel("player")
			if boss then
				myPlate.level:SetText("??")
				myPlate.level:SetTextColor(0.8, 0.05, 0)
				myPlate.level:Show()
			elseif level then
				myPlate.level:SetText(level..(elite and "+" or ""))
				myPlate.level:SetTextColor(self.level:GetTextColor())
				myPlate.level:Show()
			end
		else
			myPlate.level:Hide()
			myPlate.level:SetText(nil)
		end
	elseif self.bossIcon:IsShown() and NP.db.level.enable and myPlate.level:GetText() ~= '??' then
		myPlate.level:SetText("??")
		myPlate.level:SetTextColor(0.8, 0.05, 0)
		myPlate.level:Show()
	end
end

function NP:GetReaction(frame)
	local r, g, b = NP:RoundColors(frame.healthBar:GetStatusBarColor())

	for class, _ in pairs(RAID_CLASS_COLORS) do
		local bb = b
		if class == 'MONK' then
			bb = bb - 0.01
		end
		
		if RAID_CLASS_COLORS[class].r == r and RAID_CLASS_COLORS[class].g == g and RAID_CLASS_COLORS[class].b == bb then
			return class
		end
	end

	if (r + b + b) == 1.59 then
		return 'TAPPED_NPC'
	elseif g + b == 0 then
		return 'HOSTILE_NPC'
	elseif r + b == 0 then
		return 'FRIENDLY_NPC'
	elseif r + g > 1.95 then
		return 'NEUTRAL_NPC'
	elseif r + g == 0 then
		return 'FRIENDLY_PLAYER'
	else
		return 'HOSTILE_PLAYER'
	end
end

function NP:GetThreatReaction(frame)
	if frame.threat:IsShown() then
		local r, g, b = frame.threat:GetVertexColor()
		if g + b == 0 then
			return 'FULL_THREAT'
		else
			if self.threatReaction == 'FULL_THREAT' then
				return 'GAINING_THREAT'
			else
				return 'LOSING_THREAT'
			end
		end
	else
		return 'NO_THREAT'
	end
end

local color, scale
function NP:ColorizeAndScale()
	local myPlate = NP.CreatedPlates[self]
	local unitType = NP:GetReaction(self)
	local scale = 1

	self.unitType = unitType
	if RAID_CLASS_COLORS[unitType] then
		color = RAID_CLASS_COLORS[unitType]
	elseif unitType == "TAPPED_NPC" then
		color = NP.db.reactions.tapped
	elseif unitType == "HOSTILE_NPC" then
		local classRole = E.Role
		local threatReaction = NP:GetThreatReaction(self)
		if threatReaction == 'FULL_THREAT' then
			if classRole == 'Tank' then
				color = NP.db.threat.goodColor
				scale = NP.db.threat.goodScale
			else
				color = NP.db.threat.badColor
				scale = NP.db.threat.badScale
			end
		elseif threatReaction == 'GAINING_THREAT' then
			if classRole == 'Tank' then
				color = NP.db.threat.goodTransitionColor
			else
				color = NP.db.threat.badTransitionColor
			end
		elseif threatReaction == 'LOSING_THREAT' then
			if classRole == 'Tank' then
				color = NP.db.threat.badTransitionColor
			else
				color = NP.db.threat.goodTransitionColor
			end
		elseif InCombatLockdown() then
			if classRole == 'Tank' then
				color = NP.db.threat.badColor
				scale = NP.db.threat.badScale
			else
				color = NP.db.threat.goodColor
				scale = NP.db.threat.goodScale
			end
		else
			color = NP.db.reactions.enemy
		end

		self.threatReaction = threatReaction
	elseif unitType == "NEUTRAL_NPC" then
		color = NP.db.reactions.neutral
	elseif unitType == "FRIENDLY_NPC" then
		color = NP.db.reactions.friendlyNPC
	elseif unitType == "FRIENDLY_PLAYER" then
		color = NP.db.reactions.friendlyPlayer
	else
		color = NP.db.reactions.enemy
	end

	myPlate.healthBar:SetStatusBarColor(color.r, color.g, color.b)
	if myPlate.healthBar:GetWidth() ~= (NP.db.healthBar.width * scale) then
		myPlate.healthBar:SetSize(NP.db.healthBar.width * scale, NP.db.healthBar.height * scale)
		self.castBar.icon:Size(NP.db.castBar.height + (NP.db.healthBar.height * scale) + 5)
	end
end

function NP:SetAlpha()
	local myPlate = NP.CreatedPlates[self]
	if self:GetAlpha() < 1 then
		myPlate:SetAlpha(NP.db.nonTargetAlpha)
		NP.NumTransparentPlates = NP.NumTransparentPlates + 1
	else
		myPlate:SetAlpha(1)
	end
end

function NP:SetUnitInfo()
	local myPlate = NP.CreatedPlates[self]

	if self:GetAlpha() == 1 and UnitExists("target") and UnitName("target") == self.name:GetText() and NP.NumTransparentPlates > 0 then
		self.guid = UnitGUID("target")
		self.unit = "target"
		myPlate:SetFrameLevel(2)
		myPlate.overlay:Hide()

		if NP.NumTargetAuraChecks > -1 then
			NP:UpdateAurasByUnitID('target')
			NP.NumTargetAuraChecks = NP.NumTargetAuraChecks + 1
			
			if NP.NumTargetAuraChecks > 1 then
				NP.NumTargetAuraChecks = -1
			end
		end
	elseif self.highlight:IsShown() and UnitExists("mouseover") and UnitName("mouseover") == self.name:GetText() then
		self.guid = UnitGUID("mouseover")
		self.unit = "mouseover"
		myPlate:SetFrameLevel(1)
		myPlate.overlay:Show()

		if NP.NumMouseoverAuraChecks > -1 then
			NP:UpdateAurasByUnitID('mouseover')
			NP.NumMouseoverAuraChecks = NP.NumMouseoverAuraChecks + 1

			if NP.NumMouseoverAuraChecks > 1 then
				NP.NumMouseoverAuraChecks = -1
			end
		end		
	else
		self.unit = nil
		myPlate:SetFrameLevel(0)
		myPlate.overlay:Hide()
	end	
end

function NP:PLAYER_ENTERING_WORLD()
	twipe(self.Healers)
	local inInstance, instanceType = IsInInstance()
	if inInstance and instanceType == 'pvp' and self.db.raidHealIcon.markHealers then
		self.CheckHealerTimer = self:ScheduleRepeatingTimer("CheckBGHealers", 3)
		self:CheckBGHealers()
	elseif inInstance and instanceType == 'arena' and self.db.raidHealIcon.markHealers then
		self:RegisterEvent('UNIT_NAME_UPDATE', 'CheckArenaHealers')
		self:RegisterEvent("ARENA_OPPONENT_UPDATE", 'CheckArenaHealers');
		self:CheckArenaHealers()	
	else
		self:UnregisterEvent('UNIT_NAME_UPDATE')
		self:UnregisterEvent("ARENA_OPPONENT_UPDATE")
		if self.CheckHealerTimer then
			self:CancelTimer(self.CheckHealerTimer)
			self.CheckHealerTimer = nil;
		end
	end
end


function NP:PLAYER_TARGET_CHANGED()
	if UnitExists('target') then
		NP.NumTargetAuraChecks = 0
	end
end

function NP:UPDATE_MOUSEOVER_UNIT()
	if UnitExists('mouseover') then
		NP.NumMouseoverAuraChecks = 0
	end
end

function NP:Initialize()
	self.db = E.db["nameplate"]
	if E.private["nameplate"].enable ~= true then return end
	E.NamePlates = NP

	self.PlateParent = CreateFrame("Frame", nil, WorldFrame)
	self.PlateParent:SetFrameStrata("BACKGROUND")
	self.PlateParent:SetFrameLevel(0)	
	WorldFrame:HookScript('OnUpdate', NP.OnUpdate)
	self:RegisterEvent("PLAYER_ENTERING_WORLD")
	self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	self:RegisterEvent("UNIT_AURA")
	self:RegisterEvent("PLAYER_TARGET_CHANGED")
	self:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
end

function NP:UpdateAllPlates()
	if E.private["nameplate"].enable ~= true then return end
	NP:ForEachPlate("UpdateSettings")
end

function NP:ForEachPlate(functionToRun, ...)
	for blizzPlate, _ in pairs(self.CreatedPlates) do
		if blizzPlate and blizzPlate:IsShown() then
			self[functionToRun](blizzPlate, ...)
		end
	end
end

function NP:RoundColors(r, g, b)	
	return floor(r*100+.5)/100, floor(g*100+.5)/100, floor(b*100+.5)/100
end

function NP:OnShow()
	local objectType
	for object in pairs(self.queue) do		
		objectType = object:GetObjectType()  
		if objectType == "Texture" then
			object.OldTexture = object:GetTexture()
			object:SetTexture("")
			object:SetTexCoord(0, 0, 0, 0)
		elseif objectType == 'FontString' then
			object:SetWidth(0.001)
		elseif objectType == 'StatusBar' then
			object:SetStatusBarTexture("")
		else
			object:Hide()
		end
	end
	
	NP.HealthBar_OnValueChanged(self.healthBar, self.healthBar:GetValue())

	--Check to see if its possible to update auras via raid icon or class color when a plate is shown.
	if self.raidIcon:IsShown() then
		NP:CheckRaidIcon(self)
		NP:UpdateAuras(self)
	end
end

function NP:OnHide()
	local myPlate = NP.CreatedPlates[self]
	self.threatReaction = nil
	self.unitType = nil
	self.guid = nil
	self.unit = nil
	self.raidIconType = nil
	myPlate.lowHealth:Hide()

	if self.AuraWidget then
		for index = 1, NP.MAX_DISPLAYABLE_DEBUFFS do 
			NP.PolledHideIn(self.AuraWidget.AuraIconFrames[index], 0)
		end		
	end
end

function NP:HealthBar_OnValueChanged(value)
	local myPlate = NP.CreatedPlates[self:GetParent():GetParent()]
	local minValue, maxValue = self:GetMinMaxValues()
	myPlate.healthBar:SetMinMaxValues(minValue, maxValue)
	myPlate.healthBar:SetValue(value)

	--Health Text
	if NP.db.healthBar.text.enable and value and maxValue and maxValue > 1 and self:GetScale() == 1 then
		myPlate.healthBar.text:Show()
		myPlate.healthBar.text:SetText(E:GetFormattedText(NP.db.healthBar.text.format, value, maxValue))
	elseif myPlate.healthBar.text:IsShown() then
		myPlate.healthBar.text:Hide()
	end

	--Health Threshold
	local percentValue = (value/maxValue)
	if percentValue < NP.db.healthBar.lowThreshold then
		myPlate.lowHealth:Show()
		if percentValue < (NP.db.healthBar.lowThreshold / 2) then
			myPlate.lowHealth:SetBackdropBorderColor(1, 0, 0, 0.9)
		else
			myPlate.lowHealth:SetBackdropBorderColor(1, 1, 0, 0.9)
		end
	else
		myPlate.lowHealth:Hide()
	end
end

local green =  {r = 0, g = 1, b = 0}
function NP:CastBar_OnValueChanged(value)
	local myPlate = NP.CreatedPlates[self:GetParent():GetParent()]
	local min, max = self:GetMinMaxValues()
	myPlate.castBar:SetMinMaxValues(min, max)
	myPlate.castBar:SetValue(value)
	myPlate.castBar.time:SetFormattedText("%.1f ", value)

	local color
	if(self.shield:IsShown()) then
		color = NP.db.castBar.noInterrupt
	else
		--Color the castbar green slightly before it ends cast.
		if value > 0 and (value/max) >= 0.98 then
			color = green
		else
			color = NP.db.castBar.color
		end
	end			

	myPlate.castBar:SetStatusBarColor(color.r, color.g, color.b)
end

function NP:CastBar_OnShow()
	local myPlate = NP.CreatedPlates[self:GetParent():GetParent()]
	myPlate.castBar:Show()
end

function NP:CastBar_OnHide()
	local myPlate = NP.CreatedPlates[self:GetParent():GetParent()]
	myPlate.castBar:Hide()
end

function NP:UpdateSettings()
	local myPlate = NP.CreatedPlates[self]
	local font = LSM:Fetch("font", NP.db.font)
	local fontSize, fontOutline = NP.db.fontSize, NP.db.fontOutline

	--Name
	self.name:FontTemplate(font, fontSize, fontOutline)
	self.name:ClearAllPoints()
	self.name:SetPoint(E.InversePoints[NP.db.name.attachTo], myPlate.healthBar, NP.db.name.attachTo, NP.db.name.xOffset, NP.db.name.yOffset)
	self.name:SetJustifyH(NP.db.name.justifyH)
	self.name:SetWidth(NP.db.name.width)
	self.name:SetHeight(NP.db.fontSize)

	--Level
	myPlate.level:FontTemplate(font, fontSize, fontOutline)
	myPlate.level:ClearAllPoints()
	myPlate.level:SetPoint(E.InversePoints[NP.db.level.attachTo], myPlate.healthBar, NP.db.level.attachTo, NP.db.level.xOffset, NP.db.level.yOffset)
	myPlate.level:SetJustifyH(NP.db.level.justifyH)

	--HealthBar
	myPlate.healthBar:SetSize(NP.db.healthBar.width, NP.db.healthBar.height)
	myPlate.healthBar:SetStatusBarTexture(E.media.normTex)

	myPlate.healthBar.text:FontTemplate(font, fontSize, fontOutline)
	myPlate.healthBar.text:ClearAllPoints()
	myPlate.healthBar.text:SetPoint(E.InversePoints[NP.db.healthBar.text.attachTo], myPlate.healthBar, NP.db.healthBar.text.attachTo, NP.db.healthBar.text.xOffset, NP.db.healthBar.text.yOffset)
	myPlate.healthBar.text:SetJustifyH(NP.db.healthBar.text.justifyH)

	--CastBar
	myPlate.castBar:SetSize(NP.db.healthBar.width, NP.db.castBar.height)
	myPlate.castBar:SetStatusBarTexture(E.media.normTex)
	
	myPlate.castBar.time:ClearAllPoints()
	myPlate.castBar.time:SetPoint(E.InversePoints[NP.db.castBar.time.attachTo], myPlate.castBar, NP.db.castBar.time.attachTo, NP.db.castBar.time.xOffset, NP.db.castBar.time.yOffset)
	myPlate.castBar.time:SetJustifyH(NP.db.castBar.time.justifyH)	
	myPlate.castBar.time:FontTemplate(font, fontSize, fontOutline)
	
	self.castBar.name:ClearAllPoints()
	self.castBar.name:SetPoint(E.InversePoints[NP.db.castBar.name.attachTo], myPlate.castBar, NP.db.castBar.name.attachTo, NP.db.castBar.name.xOffset, NP.db.castBar.name.yOffset)
	self.castBar.name:SetJustifyH(NP.db.castBar.name.justifyH)		
	self.castBar.name:FontTemplate(font, fontSize, fontOutline)
	self.castBar.name:SetWidth(NP.db.castBar.name.width)
	self.castBar.name:SetHeight(NP.db.fontSize)

	self.castBar.icon:Size(NP.db.castBar.height + NP.db.healthBar.height + 5)	

	--Raid Icon
	self.raidIcon:ClearAllPoints()
	self.raidIcon:SetPoint(E.InversePoints[NP.db.raidHealIcon.attachTo], myPlate.healthBar, NP.db.raidHealIcon.attachTo, NP.db.raidHealIcon.xOffset, NP.db.raidHealIcon.yOffset)	
	self.raidIcon:SetSize(NP.db.raidHealIcon.size, NP.db.raidHealIcon.size)

	--Healer Icon
	myPlate.healerIcon:ClearAllPoints()
	myPlate.healerIcon:SetPoint(E.InversePoints[NP.db.raidHealIcon.attachTo], myPlate.healthBar, NP.db.raidHealIcon.attachTo, NP.db.raidHealIcon.xOffset, NP.db.raidHealIcon.yOffset)
	myPlate.healerIcon:SetSize(NP.db.raidHealIcon.size, NP.db.raidHealIcon.size)

	--Auras
	for index = 1, #self.AuraWidget.AuraIconFrames do 
		if self.AuraWidget.AuraIconFrames and self.AuraWidget.AuraIconFrames[index] then
			local auraFont = LSM:Fetch("font", NP.db.auras.font)
			self.AuraWidget.AuraIconFrames[index].TimeLeft:FontTemplate(auraFont, NP.db.auras.fontSize, NP.db.auras.fontOutline)
			self.AuraWidget.AuraIconFrames[index].Stacks:FontTemplate(auraFont, NP.db.auras.fontSize, NP.db.auras.fontOutline)
			self.AuraWidget.AuraIconFrames[index]:SetSize(NP.db.auras.width, NP.db.auras.height)

			if NP.db.auras.stretchTexture then
				self.AuraWidget.AuraIconFrames[index].Icon:SetTexCoord(.07, 0.93, .23, 0.77)
			else
				self.AuraWidget.AuraIconFrames[index].Icon:SetTexCoord(.07, .93, .07, .93)
			end
		end
	end	
end

function NP:CreatePlate(frame)
	frame.barFrame, frame.nameFrame = frame:GetChildren()
	frame.healthBar, frame.castBar = frame.barFrame:GetChildren()
	frame.threat, frame.border, frame.highlight, frame.level, frame.bossIcon, frame.raidIcon, frame.eliteIcon = frame.barFrame:GetRegions()
	frame.name = frame.nameFrame:GetRegions()
	frame.healthBar.texture = frame.healthBar:GetRegions()
	frame.castBar.texture, frame.castBar.border, frame.castBar.shield, frame.castBar.icon, frame.castBar.name, frame.castBar.shadow = frame.castBar:GetRegions()

	local myPlate = CreateFrame("Frame", nil, self.PlateParent)
	myPlate:SetSize(frame:GetSize())

	--HealthBar
	myPlate.healthBar = CreateFrame("StatusBar", nil, myPlate)
	myPlate.healthBar:SetPoint('BOTTOM', myPlate, 'BOTTOM', 0, 5)
	myPlate.healthBar:SetFrameStrata("BACKGROUND")
	myPlate.healthBar:SetFrameLevel(0)
	NP:CreateBackdrop(myPlate.healthBar)

	myPlate.healthBar.text = myPlate.healthBar:CreateFontString(nil, 'OVERLAY')

	--CastBar
	myPlate.castBar = CreateFrame("StatusBar", nil, myPlate)
	myPlate.castBar:SetPoint('TOPLEFT', myPlate.healthBar, 'BOTTOMLEFT', 0, -5)	
	myPlate.castBar:SetPoint('TOPRIGHT', myPlate.healthBar, 'BOTTOMRIGHT', 0, -5)	
	myPlate.castBar:SetFrameStrata("BACKGROUND")
	myPlate.castBar:SetFrameLevel(0)
	NP:CreateBackdrop(myPlate.castBar)
	myPlate.castBar.time = myPlate.castBar:CreateFontString(nil, 'OVERLAY')
	frame.castBar.name:SetParent(myPlate.castBar)
	frame.castBar.icon:SetParent(myPlate.castBar)
	frame.castBar.icon:SetTexCoord(.07, .93, .07, .93)
	frame.castBar.icon:SetDrawLayer("OVERLAY")
	frame.castBar.icon:ClearAllPoints()
	frame.castBar.icon:SetPoint("TOPLEFT", myPlate.healthBar, "TOPRIGHT", 5, 0)
	NP:CreateBackdrop(myPlate.castBar, frame.castBar.icon)

	--Name
	frame.name:SetParent(myPlate)

	--Level
	myPlate.level = myPlate:CreateFontString(nil, 'OVERLAY')

	--Raid Icon
	frame.raidIcon:SetParent(myPlate)

	--Healer Icon
	myPlate.healerIcon = myPlate:CreateTexture(nil, 'ARTWORK')
	myPlate.healerIcon:SetSize(frame.raidIcon:GetSize())
	myPlate.healerIcon:SetTexture([[Interface\AddOns\ElvUI\media\textures\healer.tga]])
	myPlate.healerIcon:Hide()

	--Overlay
	myPlate.overlay = myPlate:CreateTexture(nil, 'OVERLAY')
	myPlate.overlay:SetAllPoints(myPlate.healthBar)
	myPlate.overlay:SetTexture(1, 1, 1, 0.3)
	myPlate.overlay:Hide()

	--Auras
	local auraHeader = CreateFrame("Frame", nil, myPlate)
	auraHeader:SetHeight(32); auraHeader:Show()
	auraHeader:SetPoint('BOTTOMRIGHT', myPlate.healthBar, 'TOPRIGHT', 0, 10)
	auraHeader:SetPoint('BOTTOMLEFT', myPlate.healthBar, 'TOPLEFT', 0, 10)
	
	auraHeader.PollFunction = NP.UpdateAuraTime
	auraHeader.AuraIconFrames = {}
	for index = 1, NP.MAX_DISPLAYABLE_DEBUFFS do 
		auraHeader.AuraIconFrames[index] = NP:CreateAuraIcon(auraHeader, myPlate);  
	end

	auraHeader.AuraIconFrames[1]:SetPoint("LEFT", auraHeader, -1, 0)
	for index = 2, NP.MAX_DISPLAYABLE_DEBUFFS do 
		auraHeader.AuraIconFrames[index]:SetPoint("LEFT", auraHeader.AuraIconFrames[index-1], "RIGHT", 1, 0) 
	end

	frame.AuraWidget = auraHeader	
	
	--Low-Health Indicator
	myPlate.lowHealth = CreateFrame("Frame", nil, myPlate)
	myPlate.lowHealth:SetFrameLevel(0)
	myPlate.lowHealth:SetOutside(myPlate.healthBar, 3, 3)
	myPlate.lowHealth:SetBackdrop( { 
		edgeFile = LSM:Fetch("border", "ElvUI GlowBorder"), edgeSize = 3,
		insets = {left = 5, right = 5, top = 5, bottom = 5},
	})
	myPlate.lowHealth:SetBackdropColor(0, 0, 0, 0)
	myPlate.lowHealth:SetBackdropBorderColor(1, 1, 0, 0.9)
	myPlate.lowHealth:SetScale(E.PixelMode and 1.5 or 2)
	myPlate.lowHealth:Hide()
	
	--Script Handlers
	frame:HookScript("OnShow", NP.OnShow)
	frame:HookScript("OnHide", NP.OnHide)
	frame.healthBar:HookScript("OnValueChanged", NP.HealthBar_OnValueChanged)
	frame.castBar:HookScript("OnShow", NP.CastBar_OnShow)
	frame.castBar:HookScript("OnHide", NP.CastBar_OnHide)
	frame.castBar:HookScript("OnValueChanged", NP.CastBar_OnValueChanged)
	
	--Hide Elements
	NP:QueueObject(frame, frame.healthBar)
	NP:QueueObject(frame, frame.castBar)
	NP:QueueObject(frame, frame.level)
	NP:QueueObject(frame, frame.threat)
	NP:QueueObject(frame, frame.border)
	NP:QueueObject(frame, frame.castBar.shield)
	NP:QueueObject(frame, frame.castBar.border)
	NP:QueueObject(frame, frame.castBar.shadow)
	NP:QueueObject(frame, frame.bossIcon)
	NP:QueueObject(frame, frame.eliteIcon)

	self.CreatedPlates[frame] = myPlate
	NP.UpdateSettings(frame)
	NP.OnShow(frame)

	if not frame.castBar:IsShown() then
		myPlate.castBar:Hide()
	else
		NP.CastBar_OnShow(frame.castBar)
	end
end

function NP:QueueObject(frame, object)
	frame.queue = frame.queue or {}
	frame.queue[object] = true

	if object.OldTexture then
		object:SetTexture(object.OldTexture)
	end
end

function NP:ScanFrames(...)
	for index = 1, select('#', ...) do
		local frame = select(index, ...)
		local name = frame:GetName()
		
		if(not NP.CreatedPlates[frame] and (name and name:find("NamePlate%d"))) then
			NP:CreatePlate(frame)
		end
	end
end

function NP:CreateBackdrop(parent, point)
	point = point or parent
	local noscalemult = E.mult * UIParent:GetScale()
	
	if point.bordertop then return end

	point.backdrop = parent:CreateTexture(nil, "BORDER")
	point.backdrop:SetDrawLayer("BORDER", -4)
	point.backdrop:SetAllPoints(point)
	point.backdrop:SetTexture(unpack(E["media"].backdropfadecolor))		
	
	if E.PixelMode then 
		point.bordertop = parent:CreateTexture(nil, "BORDER")
		point.bordertop:SetPoint("TOPLEFT", point, "TOPLEFT", -noscalemult, noscalemult)
		point.bordertop:SetPoint("TOPRIGHT", point, "TOPRIGHT", noscalemult, noscalemult)
		point.bordertop:SetHeight(noscalemult)
		point.bordertop:SetTexture(unpack(E["media"].bordercolor))	
		point.bordertop:SetDrawLayer("BORDER", 1)
		
		point.borderbottom = parent:CreateTexture(nil, "BORDER")
		point.borderbottom:SetPoint("BOTTOMLEFT", point, "BOTTOMLEFT", -noscalemult, -noscalemult)
		point.borderbottom:SetPoint("BOTTOMRIGHT", point, "BOTTOMRIGHT", noscalemult, -noscalemult)
		point.borderbottom:SetHeight(noscalemult)
		point.borderbottom:SetTexture(unpack(E["media"].bordercolor))	
		point.borderbottom:SetDrawLayer("BORDER", 1)
		
		point.borderleft = parent:CreateTexture(nil, "BORDER")
		point.borderleft:SetPoint("TOPLEFT", point, "TOPLEFT", -noscalemult, noscalemult)
		point.borderleft:SetPoint("BOTTOMLEFT", point, "BOTTOMLEFT", noscalemult, -noscalemult)
		point.borderleft:SetWidth(noscalemult)
		point.borderleft:SetTexture(unpack(E["media"].bordercolor))	
		point.borderleft:SetDrawLayer("BORDER", 1)
		
		point.borderright = parent:CreateTexture(nil, "BORDER")
		point.borderright:SetPoint("TOPRIGHT", point, "TOPRIGHT", noscalemult, noscalemult)
		point.borderright:SetPoint("BOTTOMRIGHT", point, "BOTTOMRIGHT", -noscalemult, -noscalemult)
		point.borderright:SetWidth(noscalemult)
		point.borderright:SetTexture(unpack(E["media"].bordercolor))	
		point.borderright:SetDrawLayer("BORDER", 1)			
	else
		point.bordertop = parent:CreateTexture(nil, "ARTWORK")
		point.bordertop:SetPoint("TOPLEFT", point, "TOPLEFT", -noscalemult*2, noscalemult*2)
		point.bordertop:SetPoint("TOPRIGHT", point, "TOPRIGHT", noscalemult*2, noscalemult*2)
		point.bordertop:SetHeight(noscalemult)
		point.bordertop:SetTexture(unpack(E.media.bordercolor))	
		point.bordertop:SetDrawLayer("ARTWORK", -6)
		
		point.bordertop.backdrop = parent:CreateTexture(nil, "ARTWORK")
		point.bordertop.backdrop:SetPoint("TOPLEFT", point.bordertop, "TOPLEFT", -noscalemult, noscalemult)
		point.bordertop.backdrop:SetPoint("TOPRIGHT", point.bordertop, "TOPRIGHT", noscalemult, noscalemult)
		point.bordertop.backdrop:SetHeight(noscalemult * 3)
		point.bordertop.backdrop:SetTexture(0, 0, 0)	
		point.bordertop.backdrop:SetDrawLayer("ARTWORK", -7) 

		point.borderbottom = parent:CreateTexture(nil, "ARTWORK")
		point.borderbottom:SetPoint("BOTTOMLEFT", point, "BOTTOMLEFT", -noscalemult*2, -noscalemult*2)
		point.borderbottom:SetPoint("BOTTOMRIGHT", point, "BOTTOMRIGHT", noscalemult*2, -noscalemult*2)
		point.borderbottom:SetHeight(noscalemult)
		point.borderbottom:SetTexture(unpack(E.media.bordercolor))	
		point.borderbottom:SetDrawLayer("ARTWORK", -6)

		point.borderbottom.backdrop = parent:CreateTexture(nil, "ARTWORK")
		point.borderbottom.backdrop:SetPoint("BOTTOMLEFT", point.borderbottom, "BOTTOMLEFT", -noscalemult, -noscalemult)
		point.borderbottom.backdrop:SetPoint("BOTTOMRIGHT", point.borderbottom, "BOTTOMRIGHT", noscalemult, -noscalemult)
		point.borderbottom.backdrop:SetHeight(noscalemult * 3)
		point.borderbottom.backdrop:SetTexture(0, 0, 0)	
		point.borderbottom.backdrop:SetDrawLayer("ARTWORK", -7)			
		
		point.borderleft = parent:CreateTexture(nil, "ARTWORK")
		point.borderleft:SetPoint("TOPLEFT", point, "TOPLEFT", -noscalemult*2, noscalemult*2)
		point.borderleft:SetPoint("BOTTOMLEFT", point, "BOTTOMLEFT", noscalemult*2, -noscalemult*2)
		point.borderleft:SetWidth(noscalemult)
		point.borderleft:SetTexture(unpack(E.media.bordercolor))	
		point.borderleft:SetDrawLayer("ARTWORK", -6)

		point.borderleft.backdrop = parent:CreateTexture(nil, "ARTWORK")
		point.borderleft.backdrop:SetPoint("TOPLEFT", point.borderleft, "TOPLEFT", -noscalemult, noscalemult)
		point.borderleft.backdrop:SetPoint("BOTTOMLEFT", point.borderleft, "BOTTOMLEFT", -noscalemult, -noscalemult)
		point.borderleft.backdrop:SetWidth(noscalemult * 3)
		point.borderleft.backdrop:SetTexture(0, 0, 0)	
		point.borderleft.backdrop:SetDrawLayer("ARTWORK", -7)					
		
		point.borderright = parent:CreateTexture(nil, "ARTWORK")
		point.borderright:SetPoint("TOPRIGHT", point, "TOPRIGHT", noscalemult*2, noscalemult*2)
		point.borderright:SetPoint("BOTTOMRIGHT", point, "BOTTOMRIGHT", -noscalemult*2, -noscalemult*2)
		point.borderright:SetWidth(noscalemult)
		point.borderright:SetTexture(unpack(E.media.bordercolor))	
		point.borderright:SetDrawLayer("ARTWORK", -6)	

		point.borderright.backdrop = parent:CreateTexture(nil, "ARTWORK")
		point.borderright.backdrop:SetPoint("TOPRIGHT", point.borderright, "TOPRIGHT", noscalemult, noscalemult)
		point.borderright.backdrop:SetPoint("BOTTOMRIGHT", point.borderright, "BOTTOMRIGHT", noscalemult, -noscalemult)
		point.borderright.backdrop:SetWidth(noscalemult * 3)
		point.borderright.backdrop:SetTexture(0, 0, 0)	
		point.borderright.backdrop:SetDrawLayer("ARTWORK", -7)
	end
end

---------------------------------------------
--Auras
---------------------------------------------
do
	local PolledHideIn
	local Framelist = {}
	local Watcherframe = CreateFrame("Frame")
	local WatcherframeActive = false
	local select = select
	local timeToUpdate = 0
	
	local function CheckFramelist(self)
		local curTime = GetTime()
		if curTime < timeToUpdate then return end
		local framecount = 0
		timeToUpdate = curTime + AURA_UPDATE_INTERVAL

		for frame, expiration in pairs(Framelist) do
			if expiration < curTime then 
				frame:Hide(); 
				Framelist[frame] = nil
			else 
				if frame.Poll then 
					frame.Poll(NP, frame, expiration) 
				end
				framecount = framecount + 1 
			end
		end

		if framecount == 0 then 
			Watcherframe:SetScript("OnUpdate", nil); 
			WatcherframeActive = false 
		end
	end
	
	function PolledHideIn(frame, expiration)
		if expiration == 0 then 
			frame:Hide()
			Framelist[frame] = nil
		else
			Framelist[frame] = expiration
			frame:Show()
			
			if not WatcherframeActive then 
				Watcherframe:SetScript("OnUpdate", CheckFramelist)
				WatcherframeActive = true
			end
		end
	end
	
	NP.PolledHideIn = PolledHideIn
end

function NP:GetSpellDuration(spellID)
	if spellID then return NP.CachedAuraDurations[spellID] end
end

function NP:SetSpellDuration(spellID, duration)
	if spellID then NP.CachedAuraDurations[spellID] = duration end
end

function NP:CreateAuraIcon(frame, parent)
	local noscalemult = E.mult * UIParent:GetScale()
	local button = CreateFrame("Frame",nil,frame)
	button:SetWidth(NP.db.auras.width)
	button:SetHeight(NP.db.auras.height)
	button:SetScript('OnHide', function()
		if parent.guid then
			NP:UpdateIconGrid(parent, parent.guid)
		end
	end)
	
	if E.PixelMode then
		button.bord = button:CreateTexture(nil, "BACKGROUND")
		button.bord:SetDrawLayer('BACKGROUND', 2)
		button.bord:SetTexture(unpack(E["media"].bordercolor))
		button.bord:SetPoint("TOPLEFT",button,"TOPLEFT", noscalemult,-noscalemult)
		button.bord:SetPoint("BOTTOMRIGHT",button,"BOTTOMRIGHT",-noscalemult,noscalemult)
		
		button.Icon = button:CreateTexture(nil, "BORDER")
		button.Icon:SetPoint("TOPLEFT",button,"TOPLEFT", noscalemult*2,-noscalemult*2)
		button.Icon:SetPoint("BOTTOMRIGHT",button,"BOTTOMRIGHT",-noscalemult*2,noscalemult*2)

		if NP.db.auras.stretchTexture then
			button.Icon:SetTexCoord(.07, 0.93, .23, 0.77)
		else
			button.Icon:SetTexCoord(.07, .93, .07, .93)
		end			
	else
		button.bg = button:CreateTexture(nil, "BACKGROUND")
		button.bg:SetTexture(0, 0, 0, 1)
		button.bg:SetAllPoints(button)
		
		button.bord = button:CreateTexture(nil, "BACKGROUND")
		button.bord:SetDrawLayer('BACKGROUND', 2)
		button.bord:SetTexture(unpack(E["media"].bordercolor))
		button.bord:SetPoint("TOPLEFT",button,"TOPLEFT", noscalemult,-noscalemult)
		button.bord:SetPoint("BOTTOMRIGHT",button,"BOTTOMRIGHT",-noscalemult,noscalemult)
		
		button.bg2 = button:CreateTexture(nil, "BACKGROUND")
		button.bg2:SetDrawLayer('BACKGROUND', 3)
		button.bg2:SetTexture(0, 0, 0, 1)
		button.bg2:SetPoint("TOPLEFT",button,"TOPLEFT", noscalemult*2,-noscalemult*2)
		button.bg2:SetPoint("BOTTOMRIGHT",button,"BOTTOMRIGHT",-noscalemult*2,noscalemult*2)	

		button.Icon = button:CreateTexture(nil, "BORDER")
		button.Icon:SetPoint("TOPLEFT",button,"TOPLEFT", noscalemult*3,-noscalemult*3)
		button.Icon:SetPoint("BOTTOMRIGHT",button,"BOTTOMRIGHT",-noscalemult*3,noscalemult*3)
		if NP.db.auras.stretchTexture then
			button.Icon:SetTexCoord(.07, 0.93, .23, 0.77)
		else
			button.Icon:SetTexCoord(.07, .93, .07, .93)
		end			
	end
	
	button.TimeLeft = button:CreateFontString(nil, 'OVERLAY')
	button.TimeLeft:Point('TOPLEFT', 2, 2)
	button.TimeLeft:SetJustifyH('CENTER')	
	
	button.Stacks = button:CreateFontString(nil,"OVERLAY")
	button.Stacks:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 2, -2)

	button.Poll = frame.PollFunction
	button:Hide() 
	
	return button
end

function NP:UpdateAuraTime(frame, expiration)
	local timeleft = expiration-GetTime()
	local timervalue, formatid = E:GetTimeInfo(timeleft, 4)
	local format = E.TimeFormats[3][2]
	if timervalue < 4 then
		format = E.TimeFormats[4][2]
	end
	frame.TimeLeft:SetFormattedText(("%s%s|r"):format(TimeColors[formatid], format), timervalue)	
end

function NP:ClearAuraContext(frame)
	AuraList[frame] = nil
end

function NP:RemoveAuraInstance(guid, spellID)
	if guid and spellID and NP.AuraList[guid] then
		local instanceID = tostring(guid)..tostring(spellID)..(tostring(caster or "UNKNOWN_CASTER"))
		local auraID = spellID..(tostring(caster or "UNKNOWN_CASTER"))
		if NP.AuraList[guid][auraID] then
			NP.AuraSpellID[instanceID] = nil
			NP.AuraExpiration[instanceID] = nil
			NP.AuraStacks[instanceID] = nil
			NP.AuraCaster[instanceID] = nil
			NP.AuraDuration[instanceID] = nil
			NP.AuraTexture[instanceID] = nil
			NP.AuraType[instanceID] = nil
			NP.AuraTarget[instanceID] = nil
			NP.AuraList[guid][auraID] = nil
		end
	end
end

function NP:GetAuraList(guid)
	if guid and self.AuraList[guid] then return self.AuraList[guid] end
end

function NP:GetAuraInstance(guid, auraID)
	if guid and auraID then
		local instanceID = guid..auraID
		return self.AuraSpellID[instanceID], self.AuraExpiration[instanceID], self.AuraStacks[instanceID], self.AuraCaster[instanceID], self.AuraDuration[instanceID], self.AuraTexture[instanceID], self.AuraType[instanceID], self.AuraTarget[instanceID]
	end
end

function NP:SetAuraInstance(guid, spellID, expiration, stacks, caster, duration, texture, auratype, auratarget)
	local filter = false
	if (self.db.auras.enable and caster == UnitGUID('player')) then
		filter = true;
	end
	
	local trackFilter = E.global['unitframe']['aurafilters'][self.db.auras.additionalFilter]
	if self.db.auras.additionalFilter and #self.db.auras.additionalFilter > 1 and trackFilter then
		local name = GetSpellInfo(spellID)
		local spellList = trackFilter.spells
		local type = trackFilter.type
		if type == 'Blacklist' then
			if spellList[name] and spellList[name].enable then
				filter = false;
			end
		else
			if spellList[name] and spellList[name].enable then
				filter = true;
			end
		end
	end
	
	if E.global.unitframe.InvalidSpells[spellID] then
		filter = false;
	end

	if filter ~= true then
		return;
	end

	if guid and spellID and caster and texture then
		local auraID = spellID..(tostring(caster or "UNKNOWN_CASTER"))
		local instanceID = guid..auraID
		NP.AuraList[guid] = NP.AuraList[guid] or {}
		NP.AuraList[guid][auraID] = instanceID
		NP.AuraSpellID[instanceID] = spellID
		NP.AuraExpiration[instanceID] = expiration
		NP.AuraStacks[instanceID] = stacks
		NP.AuraCaster[instanceID] = caster
		NP.AuraDuration[instanceID] = duration
		NP.AuraTexture[instanceID] = texture
		NP.AuraType[instanceID] = auratype
		NP.AuraTarget[instanceID] = auratarget
	end
end

function NP:UNIT_AURA(event, unit)
	if unit == "target" then
		self:UpdateAurasByUnitID("target")
	elseif unit == "focus" then
		self:UpdateAurasByUnitID("focus")
	end
end

function NP:COMBAT_LOG_EVENT_UNFILTERED(_, _, event, ...)
	local _, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName, destFlags, destRaidFlags, spellID, spellName, _, auraType, stackCount  = ...

	if event == "SPELL_AURA_APPLIED" or event == "SPELL_AURA_REFRESH" or event == "SPELL_AURA_APPLIED_DOSE" or event == "SPELL_AURA_REMOVED_DOSE" or event == "SPELL_AURA_BROKEN" or event == "SPELL_AURA_BROKEN_SPELL" or event == "SPELL_AURA_REMOVED" then	
		if event == "SPELL_AURA_APPLIED" or event == "SPELL_AURA_REFRESH" then
			local duration = NP:GetSpellDuration(spellID)
			local texture = GetSpellTexture(spellID)
			NP:SetAuraInstance(destGUID, spellID, GetTime() + (duration or 0), 1, sourceGUID, duration, texture, AURA_TYPE_DEBUFF, AURA_TARGET_HOSTILE)
		elseif event == "SPELL_AURA_APPLIED_DOSE" or event == "SPELL_AURA_REMOVED_DOSE" then
			local duration = NP:GetSpellDuration(spellID)
			local texture = GetSpellTexture(spellID)
			NP:SetAuraInstance(destGUID, spellID, GetTime() + (duration or 0), stackCount, sourceGUID, duration, texture, AURA_TYPE_DEBUFF, AURA_TARGET_HOSTILE)
		elseif event == "SPELL_AURA_BROKEN" or event == "SPELL_AURA_BROKEN_SPELL" or event == "SPELL_AURA_REMOVED" then
			NP:RemoveAuraInstance(destGUID, spellID)
		end	

		local name, raidIcon
		-- Cache Unit Name for alternative lookup strategy
		if band(destFlags, COMBATLOG_OBJECT_CONTROL_PLAYER) > 0 and destName then 
			local rawName = strsplit("-", destName)			-- Strip server name from players
			NP.ByName[rawName] = destGUID
			name = rawName
		end

		-- Cache Raid Icon Data for alternative lookup strategy
		for iconName, bitmask in pairs(NP.RaidTargetReference) do
			if band(destRaidFlags, bitmask) > 0  then
				NP.ByRaidIcon[iconName] = destGUID
				raidIcon = iconName
				break
			end
		end

		local frame = self:SearchForFrame(destGUID, raidIcon, name)
		if frame then
			NP:UpdateAuras(frame)
		end
	end	
end

function NP:WipeAuraList(guid)
	if guid and self.AuraList[guid] then
		local unitAuraList = self.AuraList[guid]
		for auraID, instanceID in pairs(unitAuraList) do
			self.AuraSpellID[instanceID] = nil
			self.AuraExpiration[instanceID] = nil
			self.AuraStacks[instanceID] = nil
			self.AuraCaster[instanceID] = nil
			self.AuraDuration[instanceID] = nil
			self.AuraTexture[instanceID] = nil
			self.AuraType[instanceID] = nil
			self.AuraTarget[instanceID] = nil
			unitAuraList[auraID] = nil
		end
	end
end

function NP:UpdateAurasByUnitID(unit)
	local guid = UnitGUID(unit)
	self:WipeAuraList(guid)

	if NP.db.auras.filterType == 'DEBUFFS' then
		local index = 1
		local name, _, texture, count, _, duration, expirationTime, unitCaster, _, _, spellID, _, isBossDebuff = UnitDebuff(unit, index)
		while name do
			NP:SetSpellDuration(spellID, duration)
			NP:SetAuraInstance(guid, spellID, expirationTime, count, UnitGUID(unitCaster or ""), duration, texture, AURA_TYPE[dispelType or "Debuff"], unitType)
			index = index + 1
			name , _, texture, count, _, duration, expirationTime, unitCaster, _, _, spellID, _, isBossDebuff = UnitDebuff(unit, index)
		end	
	else
		local index = 1
		local name, _, texture, count, _, duration, expirationTime, unitCaster, _, _, spellID = UnitBuff(unit, index);
		while name do
			NP:SetSpellDuration(spellID, duration)
			NP:SetAuraInstance(guid, spellID, expirationTime, count, UnitGUID(unitCaster or ""), duration, texture, AURA_TYPE[dispelType or "Buff"], unitType)
			index = index + 1
			name, _, texture, count, _, duration, expirationTime, unitCaster, _, _, spellID = UnitBuff(unit, index);
		end		
	end
	
	local raidIcon, name
	if UnitPlayerControlled(unit) then name = UnitName(unit) end
	raidIcon = RaidIconIndex[GetRaidTargetIndex(unit) or ""]
	if raidIcon then self.ByRaidIcon[raidIcon] = guid end
	
	local frame = self:SearchForFrame(guid, raidIcon, name)
	if frame then
		NP:UpdateAuras(frame)
	end
end

function NP:UpdateIcon(frame, texture, expiration, stacks)
	if frame and texture and expiration then
		-- Icon
		frame.Icon:SetTexture(texture)
		
		-- Stacks
		if stacks > 1 then 
			frame.Stacks:SetText(stacks)
		else 
			frame.Stacks:SetText("") 
		end
		
		-- Expiration
		frame:Show()
		NP.PolledHideIn(frame, expiration)
	else 
		NP.PolledHideIn(frame, 0)
	end
end

function NP:UpdateIconGrid(frame, guid)
	local widget = frame.AuraWidget 
	local AuraIconFrames = widget.AuraIconFrames
	local AurasOnUnit = self:GetAuraList(guid)
	local AuraSlotIndex = 1
	local instanceid

	self.AurasCache = wipe(self.AurasCache)
	local aurasCount = 0
	
	-- Cache displayable debuffs
	if AurasOnUnit then
		widget:Show()
		for instanceid in pairs(AurasOnUnit) do
			local aura = {}
			aura.spellID, aura.expiration, aura.stacks, aura.caster, aura.duration, aura.texture, aura.type, aura.target = self:GetAuraInstance(guid, instanceid)
			if tonumber(aura.spellID) then
				aura.name = GetSpellInfo(tonumber(aura.spellID))
				aura.unit = frame.unit
				-- Get Order/Priority
				if aura.expiration > GetTime() then
					aurasCount = aurasCount + 1
					self.AurasCache[aurasCount] = aura
				end
			end
		end
	end
	
	-- Display Auras
	if aurasCount > 0 then 
		for index = 1,  #self.AurasCache do
			local cachedaura = self.AurasCache[index]
			if cachedaura.spellID and cachedaura.expiration then 
				self:UpdateIcon(AuraIconFrames[AuraSlotIndex], cachedaura.texture, cachedaura.expiration, cachedaura.stacks) 
				AuraSlotIndex = AuraSlotIndex + 1
			end
			if AuraSlotIndex > ((frame.isSmallNP and NP.db.smallPlates) and NP.MAX_SMALLNP_DISPLAYABLE_DEBUFFS or NP.MAX_DISPLAYABLE_DEBUFFS) then break end
		end
	end
	
	-- Clear Extra Slots
	if AuraIconFrames[AuraSlotIndex] then
		NP.PolledHideIn(AuraIconFrames[AuraSlotIndex], 0)
	end

	self.AurasCache = wipe(self.AurasCache)
end

function NP:UpdateAuras(frame)
	-- Check for ID
	local guid = frame.guid

	if not guid then
		-- Attempt to ID widget via Name or Raid Icon
		if RAID_CLASS_COLORS[frame.unitType] then 
			guid = NP.ByName[frame.name:GetText()]
		elseif frame.raidIcon:IsShown() then 
			guid = NP.ByRaidIcon[frame.raidIconType] 
		end
		
		if guid then
			frame.guid = guid
		else
			frame.AuraWidget:Hide()
			return
		end
	end
	
	self:UpdateIconGrid(frame, guid)
end

function NP:UpdateAuraByLookup(guid)
 	if guid == UnitGUID("target") then
		NP:UpdateAurasByUnitID("target")
	elseif guid == UnitGUID("mouseover") then
		NP:UpdateAurasByUnitID("mouseover")
	end
end

function NP:CheckRaidIcon(frame)
	if frame.raidIcon:IsShown() then
		local ux, uy = frame.raidIcon:GetTexCoord()
		frame.raidIconType = NP.RaidIconCoordinate[ux][uy]	
	else
		frame.raidIconType = nil;
	end
end

function NP:SearchNameplateByGUID(guid)
	for frame, _ in pairs(NP.CreatedPlates) do
		if frame and frame:IsShown() and frame.guid == guid then
			return frame
		end
	end
end

function NP:SearchNameplateByName(sourceName)
	if not sourceName then return; end
	local SearchFor = strsplit("-", sourceName)
	for frame, _ in pairs(NP.CreatedPlates) do
		if frame and frame:IsShown() and frame.name:GetText() == SearchFor and RAID_CLASS_COLORS[frame.unitType] then
			return frame
		end
	end
end

function NP:SearchNameplateByIconName(raidIcon)
	for frame, _ in pairs(NP.CreatedPlates) do
		NP:CheckRaidIcon(frame)
		if frame and frame:IsShown() and frame.raidIcon:IsShown() and (frame.raidIconType == raidIcon) then
			return frame
		end
	end		
end

function NP:SearchForFrame(guid, raidIcon, name)
	local frame

	if guid then frame = self:SearchNameplateByGUID(guid) end
	if (not frame) and name then frame = self:SearchNameplateByName(name) end
	if (not frame) and raidIcon then frame = self:SearchNameplateByIconName(raidIcon) end
	
	return frame
end


E:RegisterModule(NP:GetName())