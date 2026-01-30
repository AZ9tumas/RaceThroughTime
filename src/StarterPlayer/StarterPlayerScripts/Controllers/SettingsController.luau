-- this is about the settings ui on the client

local PlayerGui : PlayerGui
local SettingsUI : ScreenGui = PlayerGui:WaitForChild("SettingsUI")
local mainFrame = SettingsUI:WaitForChild("MainFrame")
local closeButton: TextButton = mainFrame:WaitForChild("Header"):WaitForChild("TextButton")

local contentFrame: Frame = mainFrame:WaitForChild("Frame")

-- all of these are enable/disable buttons
-- hide other players' pets
local hidePets: TextButton = contentFrame:WaitForChild("Hide Pets"):WaitForChild("TextButton")
-- turn off main music (background music)
local musicVolume: TextButton = contentFrame:WaitForChild("Music Volume"):WaitForChild("TextButton")

-- turn off sound effects
local soundEffects: TextButton = contentFrame:WaitForChild("Sound Effects"):WaitForChild("TextButton")

-- no incoming trade requests
local tradingEnabled: TextButton = contentFrame:WaitForChild("Trading"):WaitForChild("TextButton")

--[[
    TODO :
    - implement the actual functionality of these buttons
    - save the data so that players do not have to constantly re-enable/disable these settings
]]