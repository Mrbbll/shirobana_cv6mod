-- Shirobana special-unit gameplay
-- UNIT_SHIROBANA is created by this script and cannot be trained normally.

local SHIROBANA_CIVILIZATION = "CIVILIZATION_SHIROBANA";
local SHIROBANA_UNIT = "UNIT_SHIROBANA";
local SHIROBANA_UNIT_HASH = GameInfo.Units[SHIROBANA_UNIT].Hash;

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
		return nil;
	end

	for _, unit in player:GetUnits():Members() do
		if unit:GetTypeHash() == SHIROBANA_UNIT_HASH then
			return unit;
		end
	end

	return nil;
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

	local trackedUnitID = Players[playerID]:GetProperty(SHIROBANA_UNIT_ID_PROPERTY);
	if trackedUnitID ~= nil and unitID ~= nil and tonumber(trackedUnitID) == tonumber(unitID) then
		MarkUnitKilled(playerID, unitID);
	end
end

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

local function OnCityAddedToMap(playerID, cityID, cityX, cityY)
	if not IsShirobana(playerID) then
		return;
	end

	local existingUnit = FindShirobanaUnit(playerID);
	if existingUnit ~= nil then
		RememberUnit(playerID, existingUnit);
		return;
	end

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
	end
end

local function OnTurnBegin()
	if PlayerManager == nil or PlayerManager.GetAliveIDs == nil then
		return;
	end

	for _, playerID in ipairs(PlayerManager.GetAliveIDs()) do
		if IsShirobana(playerID) then
			EnsureShirobanaUnit(playerID, false);
		end
	end
end

Events.PlayerTurnActivated.Add(OnPlayerTurnActivated);
if Events.CityAddedToMap ~= nil then
	Events.CityAddedToMap.Add(OnCityAddedToMap);
end
if Events.TurnBegin ~= nil then
	Events.TurnBegin.Add(OnTurnBegin);
end
if Events.UnitKilledInCombat ~= nil then
	Events.UnitKilledInCombat.Add(OnUnitKilledInCombat);
end
if Events.UnitRemovedFromMap ~= nil then
	Events.UnitRemovedFromMap.Add(OnUnitRemovedFromMap);
end
