local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local Knit = require(ReplicatedStorage.Packages.Knit)

local SoundController = Knit.CreateController({
	Name = "SoundController",
})

local BackgroundMusic: Sound? = nil
local SoundsFolder: Folder? = nil

local Settings = {
	MusicEnabled = true,
	SFXEnabled = true,
}

local BACKGROUND_MUSIC_VOLUME = 0.3
local SFX_VOLUME = 0.5

local function GetSoundsFolder(): Folder?
	if SoundsFolder then
		return SoundsFolder
	end
	
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if assets then
		SoundsFolder = assets:FindFirstChild("Sounds")
	end
	
	return SoundsFolder
end

local function FindSound(soundName: string): Sound?
	local sound = SoundService:FindFirstChild(soundName)
	if sound and sound:IsA("Sound") then
		return sound
	end
	
	local sounds = GetSoundsFolder()
	if sounds then
		sound = sounds:FindFirstChild(soundName)
		if sound and sound:IsA("Sound") then
			return sound
		end
	end
	
	return nil
end

function SoundController:SetMusicEnabled(enabled: boolean)
	Settings.MusicEnabled = enabled
	if BackgroundMusic then
		if enabled then
			BackgroundMusic.Volume = BACKGROUND_MUSIC_VOLUME
			if not BackgroundMusic.Playing then
				BackgroundMusic:Play()
			end
		else
			BackgroundMusic.Volume = 0
		end
	end
end

function SoundController:SetSFXEnabled(enabled: boolean)
	Settings.SFXEnabled = enabled
end

function SoundController:IsMusicEnabled(): boolean
	return Settings.MusicEnabled
end

function SoundController:IsSFXEnabled(): boolean
	return Settings.SFXEnabled
end

function SoundController:PlaySFX(soundName: string, volume: number?)
	if not Settings.SFXEnabled then
		return
	end
	
	local sound = FindSound(soundName)
	if not sound then
		return
	end
	
	local soundClone = sound:Clone()
	soundClone.Volume = volume or SFX_VOLUME
	soundClone.Parent = SoundService
	soundClone:Play()
	
	Debris:AddItem(soundClone, soundClone.TimeLength + 0.5)
end

function SoundController:PlayStarCollect()
	self:PlaySFX("StarCollect")
end

local function StartBackgroundMusic()
	local sound = FindSound("Background")
	if not sound then
		return
	end
	
	BackgroundMusic = sound:Clone()
	BackgroundMusic.Name = "BackgroundMusic"
	BackgroundMusic.Looped = true
	BackgroundMusic.Volume = Settings.MusicEnabled and BACKGROUND_MUSIC_VOLUME or 0
	BackgroundMusic.Parent = SoundService
	BackgroundMusic:Play()
end

function SoundController:KnitInit()
	GetSoundsFolder()
end

function SoundController:KnitStart()
	local SettingsController = Knit.GetController("SettingsController")
	
	Settings.MusicEnabled = SettingsController:GetSetting("Music") ~= false
	Settings.SFXEnabled = SettingsController:GetSetting("SFX") ~= false
	
	StartBackgroundMusic()
end

return SoundController
