--[[
	TradeController
	Client-side controller for handling pet trading.
	
	Provides a simplified API for UI to interact with the trading system:
	- Request/accept/decline trades
	- Offer/remove items during trade
	- Lock in and accept/decline final trade
	- Callbacks/signals for UI to react to trade events
	
	USAGE EXAMPLES:
	
	-- From UI script:
	local TradeController = Knit.GetController("TradeController")
	
	-- Request a trade with another player
	TradeController:RequestTrade(otherPlayer)
	
	-- Accept an incoming trade request
	TradeController:AcceptRequest(fromPlayer)
	
	-- Offer a pet (by inventory index)
	TradeController:OfferPet(petIndex)
	
	-- Lock in your offer
	TradeController:LockIn()
	
	-- Accept final trade (after both locked in)
	TradeController:Accept()
	
	-- Connect to trade events
	TradeController.OnTradeStarted:Connect(function(otherPlayer)
		-- Show trade UI
	end)
	
	TradeController.OnTradeEnded:Connect(function(reason)
		-- Hide trade UI
	end)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Signal = require(ReplicatedStorage.Packages.Signal)

local TradeController = Knit.CreateController({
	Name = "TradeController",
})

-- Public signals for UI to connect to
TradeController.OnTradeRequestReceived = Signal.new()   -- (fromPlayer: Player)
TradeController.OnTradeRequestCancelled = Signal.new()  -- (fromPlayer: Player)
TradeController.OnTradeStarted = Signal.new()           -- (otherPlayer: Player)
TradeController.OnTradeEnded = Signal.new()             -- (reason: string)
TradeController.OnOffersUpdated = Signal.new()          -- (myOffers: {}, theirOffers: {})
TradeController.OnPlayerLockedIn = Signal.new()         -- (player: Player, isMe: boolean)
TradeController.OnPlayerAccepted = Signal.new()         -- (player: Player, isMe: boolean)
TradeController.OnTradeCompleted = Signal.new()         -- (receivedPets: {})

-- Private state
local Player = Players.LocalPlayer
local TradeService = nil
local TradingEnabled = true -- Whether trading is enabled for this player

-- Current trade state (synced with server)
local CurrentTradeState = nil
local PendingRequests = {} -- { Player }

-- Helper for notifications
local function ShowNotification(message: string, category: string?)
	local NotificationController = Knit.GetController("NotificationController")
	if NotificationController then
		local cat = NotificationController.Category[category or "Default"] or NotificationController.Category.Default
		NotificationController:ShowNotification(message, cat)
	end
end

--[[
	Set whether trading is enabled for this player.
	
	@param enabled boolean - Whether trading should be enabled
]]
function TradeController:SetTradingEnabled(enabled: boolean)
	TradingEnabled = enabled
	
	-- Notify server of trading preference change
	if TradeService then
		TradeService:SetTradingEnabled(enabled)
	end
end

--[[
	Check if trading is enabled for this player.
	
	@return boolean
]]
function TradeController:IsTradingEnabled(): boolean
	return TradingEnabled
end

--[[
	Request a trade with another player.
	
	@param targetPlayer Player - The player to trade with
	@return boolean - Whether the request was sent successfully
]]
function TradeController:RequestTrade(targetPlayer: Player): boolean
	if not TradeService then
		ShowNotification("Trading is not available", "Error")
		return false
	end
	
	local success, errorMsg = TradeService:RequestTrade(targetPlayer)
	
	if success then
		ShowNotification(string.format("Trade request sent to %s", targetPlayer.Name), "Success")
	else
		ShowNotification(errorMsg or "Failed to send trade request", "Error")
	end
	
	return success
end

--[[
	Accept an incoming trade request.
	
	@param fromPlayer Player - The player who sent the request
	@return boolean - Whether the trade was accepted successfully
]]
function TradeController:AcceptRequest(fromPlayer: Player): boolean
	if not TradeService then
		ShowNotification("Trading is not available", "Error")
		return false
	end
	
	local success, errorMsg = TradeService:AcceptTradeRequest(fromPlayer)
	
	if not success then
		ShowNotification(errorMsg or "Failed to accept trade request", "Error")
	end
	
	return success
end

--[[
	Decline an incoming trade request.
	
	@param fromPlayer Player - The player who sent the request
	@return boolean - Whether the request was declined successfully
]]
function TradeController:DeclineRequest(fromPlayer: Player): boolean
	if not TradeService then
		return false
	end
	
	local success, _ = TradeService:DeclineTradeRequest(fromPlayer)
	
	-- Remove from pending requests
	for i, player in ipairs(PendingRequests) do
		if player == fromPlayer then
			table.remove(PendingRequests, i)
			break
		end
	end
	
	return success
end

--[[
	Offer a pet in the current trade.
	
	@param petIndex number - The index of the pet in inventory
	@return boolean - Whether the pet was offered successfully
]]
function TradeController:OfferPet(petIndex: number): boolean
	if not TradeService then
		ShowNotification("Trading is not available", "Error")
		return false
	end
	
	local success, errorMsg = TradeService:OfferItem(petIndex)
	
	if not success then
		ShowNotification(errorMsg or "Failed to offer pet", "Error")
	end
	
	return success
end

--[[
	Remove a pet from the current trade offer.
	
	@param petIndex number - The index of the pet to remove
	@return boolean - Whether the pet was removed successfully
]]
function TradeController:RemovePet(petIndex: number): boolean
	if not TradeService then
		return false
	end
	
	local success, errorMsg = TradeService:RemoveItem(petIndex)
	
	if not success then
		ShowNotification(errorMsg or "Failed to remove pet", "Error")
	end
	
	return success
end

--[[
	Lock in the current trade offer.
	After locking in, you cannot add or remove items.
	
	@return boolean - Whether lock in was successful
]]
function TradeController:LockIn(): boolean
	if not TradeService then
		ShowNotification("Trading is not available", "Error")
		return false
	end
	
	local success, errorMsg = TradeService:LockIn()
	
	if success then
		ShowNotification("You have locked in your offer", "Success")
	else
		ShowNotification(errorMsg or "Failed to lock in", "Error")
	end
	
	return success
end

--[[
	Accept the trade (after both players locked in).
	
	@return boolean - Whether acceptance was successful
]]
function TradeController:Accept(): boolean
	if not TradeService then
		ShowNotification("Trading is not available", "Error")
		return false
	end
	
	local success, errorMsg = TradeService:AcceptTrade()
	
	if not success then
		ShowNotification(errorMsg or "Failed to accept trade", "Error")
	end
	
	return success
end

--[[
	Decline the trade after locking in (cancels entire trade).
	
	@return boolean - Whether decline was successful
]]
function TradeController:Decline(): boolean
	if not TradeService then
		return false
	end
	
	local success, _ = TradeService:DeclineTrade()
	return success
end

--[[
	Cancel the current trade.
	
	@return boolean - Whether cancellation was successful
]]
function TradeController:Cancel(): boolean
	if not TradeService then
		return false
	end
	
	local success, _ = TradeService:CancelTrade()
	return success
end

--[[
	Get the current trade state.
	
	@return table? - The current trade state or nil if not in trade
	{
		OtherPlayer: Player,
		MyOffers: { {PetIndex: number, PetData: any} },
		TheirOffers: { {PetIndex: number, PetData: any} },
		ILockedIn: boolean,
		TheyLockedIn: boolean,
		IAccepted: boolean,
		TheyAccepted: boolean,
	}
]]
function TradeController:GetTradeState(): any?
	return CurrentTradeState
end

--[[
	Check if currently in a trade.
	
	@return boolean
]]
function TradeController:IsInTrade(): boolean
	return CurrentTradeState ~= nil
end

--[[
	Get pending incoming trade requests.
	
	@return { Player }
]]
function TradeController:GetPendingRequests(): { Player }
	return PendingRequests
end

--[[
	Refresh trade state from server.
	Called automatically, but can be called manually if needed.
]]
function TradeController:RefreshState()
	if not TradeService then return end
	
	CurrentTradeState = TradeService:GetTradeState()
	PendingRequests = TradeService:GetPendingRequests()
end

-- Handle server events
local function OnTradeRequestReceived(fromPlayer: Player)
	-- Add to pending requests
	local found = false
	for _, player in ipairs(PendingRequests) do
		if player == fromPlayer then
			found = true
			break
		end
	end
	if not found then
		table.insert(PendingRequests, fromPlayer)
	end
	
	ShowNotification(string.format("%s wants to trade with you!", fromPlayer.Name), "Alert")
	TradeController.OnTradeRequestReceived:Fire(fromPlayer)
end

local function OnTradeRequestCancelled(fromPlayer: Player)
	-- Remove from pending requests
	for i, player in ipairs(PendingRequests) do
		if player == fromPlayer then
			table.remove(PendingRequests, i)
			break
		end
	end
	
	TradeController.OnTradeRequestCancelled:Fire(fromPlayer)
end

local function OnTradeStarted(otherPlayer: Player)
	-- Refresh state
	if TradeService then
		CurrentTradeState = TradeService:GetTradeState()
	end
	
	-- Clear pending requests since we're now in a trade
	PendingRequests = {}
	
	-- Disable frames during trade (no exceptions)
	local UIFramesController = Knit.GetController("UIFramesController")
	if UIFramesController then
		UIFramesController:DisableFrames(true)
	end
	
	ShowNotification(string.format("Trade started with %s", otherPlayer.Name), "Success")
	TradeController.OnTradeStarted:Fire(otherPlayer)
end

local function OnTradeEnded(reason: string)
	CurrentTradeState = nil
	
	-- Re-enable frames when trade ends
	local UIFramesController = Knit.GetController("UIFramesController")
	if UIFramesController then
		UIFramesController:DisableFrames(false)
	end
	
	TradeController.OnTradeEnded:Fire(reason)
end

local function OnTradeOfferUpdated(myOffers: any, theirOffers: any)
	if CurrentTradeState then
		CurrentTradeState.MyOffers = myOffers
		CurrentTradeState.TheirOffers = theirOffers
		-- Reset acceptance when offers change
		CurrentTradeState.IAccepted = false
		CurrentTradeState.TheyAccepted = false
	end
	
	TradeController.OnOffersUpdated:Fire(myOffers, theirOffers)
end

local function OnTradeLockedIn(playerWhoLocked: Player)
	local isMe = playerWhoLocked == Player
	
	if CurrentTradeState then
		if isMe then
			CurrentTradeState.ILockedIn = true
		else
			CurrentTradeState.TheyLockedIn = true
		end
	end
	
	if not isMe then
		ShowNotification(string.format("%s has locked in", playerWhoLocked.Name), "Alert")
	end
	
	TradeController.OnPlayerLockedIn:Fire(playerWhoLocked, isMe)
end

local function OnTradeAccepted(playerWhoAccepted: Player)
	local isMe = playerWhoAccepted == Player
	
	if CurrentTradeState then
		if isMe then
			CurrentTradeState.IAccepted = true
		else
			CurrentTradeState.TheyAccepted = true
		end
	end
	
	if not isMe then
		ShowNotification(string.format("%s has accepted the trade", playerWhoAccepted.Name), "Alert")
	end
	
	TradeController.OnPlayerAccepted:Fire(playerWhoAccepted, isMe)
end

local function OnTradeCompleted(receivedPets: any)
	CurrentTradeState = nil
	
	-- Re-enable frames when trade completes
	local UIFramesController = Knit.GetController("UIFramesController")
	if UIFramesController then
		UIFramesController:DisableFrames(false)
	end
	
	local petCount = receivedPets and #receivedPets or 0
	if petCount > 0 then
		ShowNotification(string.format("Trade complete! You received %d pet(s)", petCount), "Success")
	else
		ShowNotification("Trade complete!", "Success")
	end
	
	TradeController.OnTradeCompleted:Fire(receivedPets)
end

-- Knit lifecycle
function TradeController:KnitInit()
	-- Initialize state
	CurrentTradeState = nil
	PendingRequests = {}
end

function TradeController:KnitStart()
	-- Get TradeService
	TradeService = Knit.GetService("TradeService")
	
	-- Connect to server signals
	TradeService.TradeRequestReceived:Connect(OnTradeRequestReceived)
	TradeService.TradeRequestCancelled:Connect(OnTradeRequestCancelled)
	TradeService.TradeStarted:Connect(OnTradeStarted)
	TradeService.TradeEnded:Connect(OnTradeEnded)
	TradeService.TradeOfferUpdated:Connect(OnTradeOfferUpdated)
	TradeService.TradeLockedIn:Connect(OnTradeLockedIn)
	TradeService.TradeAccepted:Connect(OnTradeAccepted)
	TradeService.TradeCompleted:Connect(OnTradeCompleted)
	
	-- Initial state refresh
	self:RefreshState()
end

return TradeController
