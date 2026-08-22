-- Shirobana special-unit gameplay
-- UNIT_SHIROBANA is created by this script and cannot be trained normally.

local SHIROBANA_CIVILIZATION = "CIVILIZATION_SHIROBANA";
local SHIROBANA_UNIT = "UNIT_SHIROBANA";
local SHIROBANA_UNIT_HASH = GameInfo.Units[SHIROBANA_UNIT].Hash;

local SHIROBANA_ERA_PROGRESS_PROPERTY = "SHIROBANA_ERA_COMBAT_STEPS";
local SHIROBANA_ERA_COMBAT_AMOUNT = 15;

local ERA_ORDER = {
	"ERA_ANCIENT",
	"ERA_CLASSICAL",
	"ERA_MEDIEVAL",
	"ERA_RENAISSANCE",
	"ERA_INDUSTRIAL",
	"ERA_MODERN",
	"ERA_ATOMIC",
	"ERA_INFORMATION",
	"ERA_FUTURE"
};

local ERA_INDEX_BY_TYPE = {};
for eraIndex, eraType in ipairs(ERA_ORDER) do
	ERA_INDEX_BY_TYPE[eraType] = eraIndex;
end

local ERA_COMBAT_MODIFIERS = {
	ERA_CLASSICAL = "SHIROBANA_ERA_CLASSICAL_COMBAT",
	ERA_MEDIEVAL = "SHIROBANA_ERA_MEDIEVAL_COMBAT",
	ERA_RENAISSANCE = "SHIROBANA_ERA_RENAISSANCE_COMBAT",
	ERA_INDUSTRIAL = "SHIROBANA_ERA_INDUSTRIAL_COMBAT",
	ERA_MODERN = "SHIROBANA_ERA_MODERN_COMBAT",
	ERA_ATOMIC = "SHIROBANA_ERA_ATOMIC_COMBAT",
	ERA_INFORMATION = "SHIROBANA_ERA_INFORMATION_COMBAT",
	ERA_FUTURE = "SHIROBANA_ERA_FUTURE_COMBAT"
};

local SHIROBANA_UNIT_ID_PROPERTY = "SHIROBANA_UNIT_ID";
local SHIROBANA_RESPAWN_PROPERTY = "SHIROBANA_RESPAWN_PENDING";
local SPAWN_IN_PROGRESS = {};

local function IsShirobana(playerID)
	local playerConfig = PlayerConfigurations[playerID];
	return playerConfig ~= nil and playerConfig:GetCivilizationTypeName() == SHIROBANA_CIVILIZATION;
end

local function GetCapital(playerID)
	local player = Players[playerID];
	if player == nil then
		return nil;
	end

	local cities = player:GetCities();
	if cities == nil then
		return nil;
	end

	local capital = cities:GetCapitalCity();
	if capital ~= nil then
		return capital;
	end

	-- Fallback for rulesets where GetCapitalCity is not ready on the first turn.
	for _, city in cities:Members() do
		if city:IsCapital() then
			return city;
		end
	end

	return nil;
end

local function FindShirobanaUnit(playerID)
	local player = Players[playerID];
	if player == nil then
		return nil, 0;
	end

	local foundUnit = nil;
	local unitCount = 0;
	for _, unit in player:GetUnits():Members() do
		if unit:GetTypeHash() == SHIROBANA_UNIT_HASH then
			if foundUnit == nil then
				foundUnit = unit;
			end
			unitCount = unitCount + 1;
		end
	end

	return foundUnit, unitCount;
end

local function RememberUnit(playerID, unit)
	if unit ~= nil then
		Players[playerID]:SetProperty(SHIROBANA_UNIT_ID_PROPERTY, unit:GetID());
	end
end

local function SpawnShirobana(playerID, isRespawn, spawnX, spawnY)
	if SPAWN_IN_PROGRESS[playerID] then
		return nil;
	end

	if spawnX == nil or spawnY == nil then
		local capital = GetCapital(playerID);
		if capital == nil then
			return nil;
		end
		spawnX = capital:GetX();
		spawnY = capital:GetY();
	end

	SPAWN_IN_PROGRESS[playerID] = true;
	local unit = UnitManager.InitUnit(playerID, SHIROBANA_UNIT, spawnX, spawnY);
	if unit == nil and UnitManager.InitUnitValidAdjacentHex ~= nil then
		UnitManager.InitUnitValidAdjacentHex(playerID, SHIROBANA_UNIT, spawnX, spawnY, 1);
		unit = FindShirobanaUnit(playerID);
	end
	SPAWN_IN_PROGRESS[playerID] = nil;

	if unit ~= nil then
		local player = Players[playerID];
		RememberUnit(playerID, unit);
		if isRespawn then
			unit:SetDamage(unit:GetMaxDamage() - 1);
			player:SetProperty(SHIROBANA_RESPAWN_PROPERTY, 0);
		end
		print("[Shirobana] Spawned UNIT_SHIROBANA for player " .. tostring(playerID) .. " at " .. tostring(spawnX) .. "," .. tostring(spawnY) .. (isRespawn and " (respawn)" or " (initial)"));
	end

	return unit;
end

local function EnsureShirobanaUnit(playerID, forceRespawn, spawnX, spawnY)
	if not IsShirobana(playerID) or SPAWN_IN_PROGRESS[playerID] then
		return nil;
	end

	local player = Players[playerID];
	local existingUnit = FindShirobanaUnit(playerID);
	if existingUnit ~= nil then
		RememberUnit(playerID, existingUnit);
		return existingUnit;
	end

	-- CanTrain=False prevents normal creation. This guard is the only creation path.
	-- A pending flag makes a delayed retry after a death remain a 1 HP respawn.
	local isRespawn = forceRespawn or player:GetProperty(SHIROBANA_RESPAWN_PROPERTY) == 1;
	local unit = SpawnShirobana(playerID, isRespawn, spawnX, spawnY);
	if unit == nil and isRespawn then
		player:SetProperty(SHIROBANA_RESPAWN_PROPERTY, 1);
	end

	return unit;
end

local function MarkUnitKilled(playerID, killedUnitID)
	if not IsShirobana(playerID) then
		return;
	end

	local player = Players[playerID];
	local trackedUnitID = player:GetProperty(SHIROBANA_UNIT_ID_PROPERTY);
	if trackedUnitID == nil then
		local currentUnit = FindShirobanaUnit(playerID);
		if currentUnit ~= nil then
			trackedUnitID = currentUnit:GetID();
			player:SetProperty(SHIROBANA_UNIT_ID_PROPERTY, trackedUnitID);
		end
	end

	if trackedUnitID ~= nil and killedUnitID ~= nil and tonumber(trackedUnitID) ~= tonumber(killedUnitID) then
		return;
	end

	player:SetProperty(SHIROBANA_RESPAWN_PROPERTY, 1);
	EnsureShirobanaUnit(playerID, true);
end

local function OnUnitRemovedFromMap(playerID, unitID)
	if not IsShirobana(playerID) then
		return;
	end

	local player = Players[playerID];
	local trackedUnitID = player:GetProperty(SHIROBANA_UNIT_ID_PROPERTY);
	if trackedUnitID ~= nil and unitID ~= nil and tonumber(trackedUnitID) == tonumber(unitID) then
		MarkUnitKilled(playerID, unitID);
	end
end

-- Gameplay event form: killedPlayerID, killedUnitID, killerPlayerID, killerUnitID.
-- Some UI contexts pass a unit object instead, so accept that form as well.
local function OnUnitKilledInCombat(killedPlayerID, killedUnitID)
	if type(killedPlayerID) == "number" then
		MarkUnitKilled(killedPlayerID, killedUnitID);
		return;
	end

	local killedUnit = killedPlayerID;
	if killedUnit ~= nil and killedUnit.GetOwner ~= nil then
		MarkUnitKilled(killedUnit:GetOwner(), killedUnit:GetID());
	end
end

local function GetCurrentEraType(player)
	if player == nil then
		return nil;
	end

	local eraValue = nil;
	if player.GetEra ~= nil then
		eraValue = player:GetEra();
	end

	if eraValue == nil and player.GetEras ~= nil then
		local eras = player:GetEras();
		if eras ~= nil and eras.GetEra ~= nil then
			eraValue = eras:GetEra();
		end
	end

	if eraValue == nil and player.GetCulture ~= nil then
		local culture = player:GetCulture();
		if culture ~= nil then
			if culture.GetEra ~= nil then
				eraValue = culture:GetEra();
			elseif culture.GetCurrentEra ~= nil then
				eraValue = culture:GetCurrentEra();
			end
		end
	end

	if type(eraValue) == "string" then
		return eraValue;
	end

	if type(eraValue) ~= "number" or GameInfo.Eras == nil then
		return nil;
	end

	-- GameInfo row indexing differs between gameplay builds. Prefer the
	-- explicit Index column and then fall back to the normal row lookup.
	for eraInfo in GameInfo.Eras() do
		if eraInfo.Index == eraValue then
			return eraInfo.EraType;
		end
	end

	local eraInfo = GameInfo.Eras[eraValue];
	if eraInfo == nil then
		eraInfo = GameInfo.Eras[eraValue + 1];
	end
	return eraInfo ~= nil and eraInfo.EraType or nil;
end

local function GetCurrentEraStep(player)
	local eraType = GetCurrentEraType(player);
	local eraStep = ERA_INDEX_BY_TYPE[eraType];
	if eraStep == nil then
		if eraType ~= nil then
			print("[Shirobana] Warning: unsupported era " .. tostring(eraType));
		end
		return nil, eraType;
	end

	return eraStep - 1, eraType;
end

local function ApplyMissingEraCombat(playerID)
	if not IsShirobana(playerID) then
		return;
	end

	local player = Players[playerID];
	if player == nil then
		return;
	end

	local currentStep, eraType = GetCurrentEraStep(player);
	if currentStep == nil then
		return;
	end

	local appliedStep = tonumber(player:GetProperty(SHIROBANA_ERA_PROGRESS_PROPERTY)) or 0;
	if currentStep <= appliedStep then
		return;
	end

	local addedSteps = 0;
	for step = appliedStep + 1, currentStep do
		local eraName = ERA_ORDER[step + 1];
		local modifierID = ERA_COMBAT_MODIFIERS[eraName];
		if modifierID == nil then
			print("[Shirobana] Warning: no combat modifier for era " .. tostring(eraName));
			break;
		end

		-- Each era has a distinct modifier/ability chain, so every attach is
		-- an independent +15 base-combat-strength contribution.
		player:AttachModifierByID(modifierID);
		appliedStep = step;
		addedSteps = addedSteps + 1;
	end

	player:SetProperty(SHIROBANA_ERA_PROGRESS_PROPERTY, appliedStep);
	if addedSteps > 0 then
		print("[Shirobana] Applied " .. tostring(addedSteps) .. " era combat increase(s) for player " .. tostring(playerID) .. "; current era " .. tostring(eraType) .. ", total base combat +" .. tostring(appliedStep * SHIROBANA_ERA_COMBAT_AMOUNT));
	end
end

local function OnCityAddedToMap(playerID, cityID, cityX, cityY)
	if not IsShirobana(playerID) then
		return;
	end

	local existingUnit = FindShirobanaUnit(playerID);
	if existingUnit ~= nil then
		RememberUnit(playerID, existingUnit);
		return;
	end

	-- The first city is the capital. Prefer the city object when it is already
	-- available; the event coordinates are the early-game fallback when the
	-- player city collection has not finished initializing yet.
	local city = nil;
	if CityManager ~= nil and CityManager.GetCity ~= nil then
		city = CityManager.GetCity(playerID, cityID);
	end
	if city ~= nil and city.IsCapital ~= nil and not city:IsCapital() then
		return;
	end

	EnsureShirobanaUnit(playerID, false, cityX, cityY);
end

local function OnPlayerTurnActivated(playerID)
	if IsShirobana(playerID) then
		EnsureShirobanaUnit(playerID, false);
		-- Also repairs saves or contexts where PlayerEraChanged was missed.
		ApplyMissingEraCombat(playerID);
	end
end

local function OnPlayerEraChanged(playerID)
	-- Read the era back from the player instead of trusting the event payload;
	-- this keeps the same path safe across gameplay event signatures.
	ApplyMissingEraCombat(playerID);
end

local function OnTurnBegin()
	if PlayerManager == nil or PlayerManager.GetAliveIDs == nil then
		return;
	end

	for _, playerID in ipairs(PlayerManager.GetAliveIDs()) do
		if IsShirobana(playerID) then
			EnsureShirobanaUnit(playerID, false);
			ApplyMissingEraCombat(playerID);
		end
	end
end

Events.PlayerTurnActivated.Add(OnPlayerTurnActivated);
if Events.PlayerEraChanged ~= nil then
	Events.PlayerEraChanged.Add(OnPlayerEraChanged);
end
if Events.CityAddedToMap ~= nil then
	Events.CityAddedToMap.Add(OnCityAddedToMap);
end
if Events.TurnBegin ~= nil then
	Events.TurnBegin.Add(OnTurnBegin);
end

-- This event is available in current Civ6 gameplay contexts. The guard keeps
-- the script loadable in older rule-set builds that expose it only to UI Lua.
if Events.UnitKilledInCombat ~= nil then
	Events.UnitKilledInCombat.Add(OnUnitKilledInCombat);
end

-- This catches removals that bypass the combat event. The tracked unit ID
-- prevents ordinary map removals from creating a replacement.
if Events.UnitRemovedFromMap ~= nil then
	Events.UnitRemovedFromMap.Add(OnUnitRemovedFromMap);
end
