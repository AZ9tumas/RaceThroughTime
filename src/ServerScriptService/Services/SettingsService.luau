local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)

local SettingsService = Knit.CreateService({
	Name = "SettingsService",
	Client = {},
})

local VALID_SETTINGS = {
	Music = "boolean",
	SFX = "boolean",
	HidePets = "boolean",
	TradingEnabled = "boolean",
}

function SettingsService.Client:UpdateSetting(player, settingKey: string, value: any): (boolean, string?)
	if not VALID_SETTINGS[settingKey] then
		return false, "Invalid setting key"
	end
	local expectedType = VALID_SETTINGS[settingKey]
	if typeof(value) ~= expectedType then
		return false, "Invalid value type"
	end
	local DataService = Knit.GetService("DataService")
	DataService:Update(player, "Meta", function(meta)
		meta = meta or {}
		if not meta.Settings then
			meta.Settings = {}
		end
		meta.Settings[settingKey] = value
		return meta
	end)
	
	-- Fire data ready to update client
	DataService:FireDataReady(player)
	
	return true, nil
end

function SettingsService.Client:GetSettings(player): { [string]: any }?
	local DataService = Knit.GetService("DataService")
	local meta = DataService:Get(player, "Meta")
	if meta and meta.Settings then
		return meta.Settings
	end
	return nil
end

function SettingsService:KnitInit()
end

function SettingsService:KnitStart()
end

return SettingsService
