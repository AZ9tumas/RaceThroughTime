--[[
	TradeService
	Handles player-to-player pet trading on the server.
	
	Trade Flow:
	1. Player1 requests trade with Player2 via RequestTrade
	2. Player2 accepts via AcceptTradeRequest (trade session begins)
	3. Both players can offer pets via OfferItem / remove via RemoveItem
	4. Player locks in via LockIn (cannot modify offers after)
	5. After BOTH lock in, each player must Accept to finalize
	6. Trade completes when both accept - pets are exchanged
	
	Either player can cancel at any time via CancelTrade.
	
	Trade Request Rules:
	- A player can only have ONE outgoing trade request at a time
	- Sending a new request cancels any previous outgoing request
	- A player cannot request/accept if they have an ongoing trade
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)

-- Type definitions
export type TradeOffer = {
	PetIndex: number,  -- Index in player's PetInventory
	PetData: any,      -- Copy of pet data for display
}

export type TradeSession = {
	Player1: Player,
	Player2: Player,
	Player1Offers: { TradeOffer },
	Player2Offers: { TradeOffer },
	Player1LockedIn: boolean,
	Player2LockedIn: boolean,
	Player1Accepted: boolean,
	Player2Accepted: boolean,
	CreatedAt: number,
}

export type TradeRequest = {
	FromPlayer: Player,
	ToPlayer: Player,
	CreatedAt: number,
}

local TradeService = Knit.CreateService({
	Name = "TradeService",
	Client = {
		-- Signals sent to clients
		TradeRequestReceived = Knit.CreateSignal(),    -- (fromPlayer: Player)
		TradeRequestCancelled = Knit.CreateSignal(),   -- (fromPlayer: Player)
		TradeStarted = Knit.CreateSignal(),            -- (otherPlayer: Player)
		TradeEnded = Knit.CreateSignal(),              -- (reason: string)
		TradeOfferUpdated = Knit.CreateSignal(),       -- (myOffers: {TradeOffer}, theirOffers: {TradeOffer})
		TradeLockedIn = Knit.CreateSignal(),           -- (playerWhoLocked: Player)
		TradeAccepted = Knit.CreateSignal(),           -- (playerWhoAccepted: Player)
		TradeCompleted = Knit.CreateSignal(),          -- (receivedPets: {any})
	},
})

-- Private state
-- Active trade requests: [fromPlayer.UserId] = TradeRequest
local OutgoingRequests: { [number]: TradeRequest } = {}

-- Incoming requests per player: [toPlayer.UserId] = { [fromPlayer.UserId] = TradeRequest }
local IncomingRequests: { [number]: { [number]: TradeRequest } } = {}

-- Active trade sessions: [player.UserId] = TradeSession (both players point to same session)
local ActiveTrades: { [number]: TradeSession } = {}

-- Player trading preferences: [player.UserId] = boolean (true = enabled, false = disabled)
local PlayerTradingEnabled: { [number]: boolean } = {}

-- Helper function for logging
local function Log(message: string)
	--print(string.format("[TradeService]: %s", message))
end

-- Check if a player has trading enabled
local function IsTradingEnabledForPlayer(player: Player): boolean
	local DataService = Knit.GetService("DataService")
	local meta = DataService:Get(player, "Meta")
	
	-- Default to true if not set
	if meta and meta.Settings and meta.Settings.TradingEnabled ~= nil then
		return meta.Settings.TradingEnabled
	end
	return true
end

-- Check if a player is currently in an active trade
local function IsInTrade(player: Player): boolean
	return ActiveTrades[player.UserId] ~= nil
end

-- Get the trade session for a player
local function GetTradeSession(player: Player): TradeSession?
	return ActiveTrades[player.UserId]
end

-- Check if player is Player1 or Player2 in the trade session
local function IsPlayer1(session: TradeSession, player: Player): boolean
	return session.Player1 == player
end

-- Deep copy a table (handles nested tables)
local function DeepCopy(original: any): any
	if type(original) ~= "table" then
		return original
	end
	
	local copy = {}
	for key, value in pairs(original) do
		copy[key] = DeepCopy(value)
	end
	return copy
end

-- Copy pet data for trading (creates a deep copy with updated timestamp)
local function CopyPetDataForTrade(petData: any): any
	local copy = DeepCopy(petData)
	copy.ObtainedAt = os.time()
	copy.Locked = false -- Pets received via trade are always unlocked
	return copy
end

-- Reset acceptance state when offers change
local function ResetAcceptance(session: TradeSession)
	session.Player1Accepted = false
	session.Player2Accepted = false
end

-- Cancel a specific outgoing request
local function CancelOutgoingRequest(fromPlayer: Player)
	local request = OutgoingRequests[fromPlayer.UserId]
	if not request then return end
	
	-- Remove from target's incoming list
	local targetId = request.ToPlayer.UserId
	if IncomingRequests[targetId] then
		IncomingRequests[targetId][fromPlayer.UserId] = nil
	end
	
	-- Notify the target that request was cancelled
	if request.ToPlayer:IsDescendantOf(Players) then
		TradeService.Client.TradeRequestCancelled:Fire(request.ToPlayer, fromPlayer)
	end
	
	-- Remove outgoing request
	OutgoingRequests[fromPlayer.UserId] = nil
	
	Log(string.format("%s cancelled trade request to %s", fromPlayer.Name, request.ToPlayer.Name))
end

-- Cancel all incoming requests to a player
local function CancelAllIncomingRequests(player: Player)
	local incoming = IncomingRequests[player.UserId]
	if not incoming then return end
	
	for fromUserId, request in pairs(incoming) do
		-- Remove from sender's outgoing
		OutgoingRequests[fromUserId] = nil
		
		-- Notify sender that their request was cancelled
		if request.FromPlayer:IsDescendantOf(Players) then
			TradeService.Client.TradeRequestCancelled:Fire(request.FromPlayer, player)
		end
	end
	
	IncomingRequests[player.UserId] = {}
end

-- End a trade session
local function EndTradeSession(session: TradeSession, reason: string)
	if not session then return end
	
	local player1 = session.Player1
	local player2 = session.Player2
	
	-- Remove from active trades
	if player1 then
		ActiveTrades[player1.UserId] = nil
	end
	if player2 then
		ActiveTrades[player2.UserId] = nil
	end
	
	-- Notify both players
	if player1 and player1:IsDescendantOf(Players) then
		TradeService.Client.TradeEnded:Fire(player1, reason)
	end
	if player2 and player2:IsDescendantOf(Players) then
		TradeService.Client.TradeEnded:Fire(player2, reason)
	end
	
	Log(string.format("Trade ended between %s and %s: %s", 
		player1 and player1.Name or "?", 
		player2 and player2.Name or "?", 
		reason))
end

-- Get pet data by index from player's inventory
local function GetPetData(player: Player, petIndex: number): any?
	local DataService = Knit.GetService("DataService")
	local inventory = DataService:Get(player, "Inventory")
	if not inventory or not inventory.PetInventory then
		return nil
	end
	return inventory.PetInventory[petIndex]
end

-- Check if a pet is already offered in a trade
local function IsPetOffered(offers: { TradeOffer }, petIndex: number): boolean
	for _, offer in ipairs(offers) do
		if offer.PetIndex == petIndex then
			return true
		end
	end
	return false
end

-- Notify both players of updated offers
local function NotifyOffersUpdated(session: TradeSession)
	local player1 = session.Player1
	local player2 = session.Player2
	
	if player1 and player1:IsDescendantOf(Players) then
		TradeService.Client.TradeOfferUpdated:Fire(player1, session.Player1Offers, session.Player2Offers)
	end
	if player2 and player2:IsDescendantOf(Players) then
		TradeService.Client.TradeOfferUpdated:Fire(player2, session.Player2Offers, session.Player1Offers)
	end
end

-- Verify that all offered pets still exist in player's inventory
local function ValidateOffers(player: Player, offers: { TradeOffer }): boolean
	local DataService = Knit.GetService("DataService")
	local inventory = DataService:Get(player, "Inventory")
	if not inventory or not inventory.PetInventory then
		return false
	end
	
	for _, offer in ipairs(offers) do
		local pet = inventory.PetInventory[offer.PetIndex]
		if not pet then
			return false
		end
	end
	return true
end

-- Complete the trade - transfer pets between players
local function CompleteTrade(session: TradeSession)
	local DataService = Knit.GetService("DataService")
	local PetService = Knit.GetService("PetService")
	local NotificationService = Knit.GetService("NotificationService")
	
	local player1 = session.Player1
	local player2 = session.Player2
	
	-- Final validation
	if not ValidateOffers(player1, session.Player1Offers) then
		EndTradeSession(session, "Trade failed: Player 1's offered pets no longer available")
		return false
	end
	if not ValidateOffers(player2, session.Player2Offers) then
		EndTradeSession(session, "Trade failed: Player 2's offered pets no longer available")
		return false
	end
	
	-- Collect indices to remove (sorted descending to avoid index shifting issues)
	local player1PetIndicesToRemove = {}
	local player2PetIndicesToRemove = {}
	
	for _, offer in ipairs(session.Player1Offers) do
		table.insert(player1PetIndicesToRemove, offer.PetIndex)
	end
	for _, offer in ipairs(session.Player2Offers) do
		table.insert(player2PetIndicesToRemove, offer.PetIndex)
	end
	
	table.sort(player1PetIndicesToRemove, function(a, b) return a > b end)
	table.sort(player2PetIndicesToRemove, function(a, b) return a > b end)
	
	-- Collect pet data to transfer before removing
	local petsForPlayer1 = {} -- Pets going to Player1 (from Player2)
	local petsForPlayer2 = {} -- Pets going to Player2 (from Player1)
	
	for _, offer in ipairs(session.Player2Offers) do
		local petData = GetPetData(player2, offer.PetIndex)
		if petData then
			table.insert(petsForPlayer1, CopyPetDataForTrade(petData))
		end
	end
	
	for _, offer in ipairs(session.Player1Offers) do
		local petData = GetPetData(player1, offer.PetIndex)
		if petData then
			table.insert(petsForPlayer2, CopyPetDataForTrade(petData))
		end
	end
	
	-- Unequip pets that are being traded
	for _, index in ipairs(player1PetIndicesToRemove) do
		PetService:UnequipPetByIndex(player1, index)
	end
	for _, index in ipairs(player2PetIndicesToRemove) do
		PetService:UnequipPetByIndex(player2, index)
	end
	
	-- Remove traded pets from inventories (descending order)
	DataService:Update(player1, "Inventory", function(inventory)
		for _, index in ipairs(player1PetIndicesToRemove) do
			if inventory.PetInventory[index] then
				table.remove(inventory.PetInventory, index)
			end
		end
		-- Add received pets
		for _, petData in ipairs(petsForPlayer1) do
			table.insert(inventory.PetInventory, petData)
		end
		return inventory
	end)
	
	DataService:Update(player2, "Inventory", function(inventory)
		for _, index in ipairs(player2PetIndicesToRemove) do
			if inventory.PetInventory[index] then
				table.remove(inventory.PetInventory, index)
			end
		end
		-- Add received pets
		for _, petData in ipairs(petsForPlayer2) do
			table.insert(inventory.PetInventory, petData)
		end
		return inventory
	end)
	
	-- Reinitialize pet IDs for both players
	PetService:InitializePets(player1)
	PetService:InitializePets(player2)
	
	-- Send updated data to clients
	DataService:FireDataReady(player1)
	DataService:FireDataReady(player2)
	
	-- Notify clients of completion
	if player1:IsDescendantOf(Players) then
		TradeService.Client.TradeCompleted:Fire(player1, petsForPlayer1)
		NotificationService:SendNotification(player1, "Trade completed successfully!", NotificationService.Category.Success)
	end
	if player2:IsDescendantOf(Players) then
		TradeService.Client.TradeCompleted:Fire(player2, petsForPlayer2)
		NotificationService:SendNotification(player2, "Trade completed successfully!", NotificationService.Category.Success)
	end
	
	Log(string.format("Trade completed: %s received %d pets, %s received %d pets",
		player1.Name, #petsForPlayer1, player2.Name, #petsForPlayer2))
	
	-- Clean up trade session
	ActiveTrades[player1.UserId] = nil
	ActiveTrades[player2.UserId] = nil
	
	return true
end

--[[
	Request a trade with another player.
	Cancels any existing outgoing request from this player.
	
	@param player Player - The player initiating the trade request
	@param targetPlayer Player - The player to trade with
	@return (boolean, string?) - Success status and error message if failed
]]
function TradeService:RequestTrade(player: Player, targetPlayer: Player): (boolean, string?)
	local NotificationService = Knit.GetService("NotificationService")
	
	-- Validate players
	if not player or not targetPlayer then
		return false, "Invalid players"
	end
	
	if player == targetPlayer then
		return false, "Cannot trade with yourself"
	end
	
	if not targetPlayer:IsDescendantOf(Players) then
		return false, "Target player is not in the game"
	end
	
	-- Check if the requesting player has trading enabled
	if not IsTradingEnabledForPlayer(player) then
		return false, "Trading is disabled, change this in settings"
	end
	
	-- Check if the target player has trading enabled
	if not IsTradingEnabledForPlayer(targetPlayer) then
		return false, "That player has disabled trading"
	end
	
	-- Check if either player is already in a trade
	if IsInTrade(player) then
		return false, "You are already in a trade"
	end
	
	if IsInTrade(targetPlayer) then
		return false, "Target player is already in a trade"
	end
	
	-- Cancel any existing outgoing request from this player
	CancelOutgoingRequest(player)
	
	-- Create new trade request
	local request: TradeRequest = {
		FromPlayer = player,
		ToPlayer = targetPlayer,
		CreatedAt = os.time(),
	}
	
	-- Store the request
	OutgoingRequests[player.UserId] = request
	
	if not IncomingRequests[targetPlayer.UserId] then
		IncomingRequests[targetPlayer.UserId] = {}
	end
	IncomingRequests[targetPlayer.UserId][player.UserId] = request
	
	-- Notify target player
	TradeService.Client.TradeRequestReceived:Fire(targetPlayer, player)
	
	-- Send notifications (server handles all notifications)
	NotificationService:SendNotification(player, string.format("Trade request sent to %s", targetPlayer.Name), NotificationService.Category.Success)
	
	Log(string.format("%s requested trade with %s", player.Name, targetPlayer.Name))
	
	return true, nil
end

--[[
	Accept a trade request from another player.
	This starts the actual trade session.
	
	@param player Player - The player accepting the request
	@param fromPlayer Player - The player who sent the request
	@return (boolean, string?) - Success status and error message if failed
]]
function TradeService:AcceptTradeRequest(player: Player, fromPlayer: Player): (boolean, string?)
	-- Validate players
	if not player or not fromPlayer then
		return false, "Invalid players"
	end
	
	if not fromPlayer:IsDescendantOf(Players) then
		return false, "Requesting player is no longer in the game"
	end
	
	-- Check if either player is already in a trade
	if IsInTrade(player) then
		return false, "You are already in a trade"
	end
	
	if IsInTrade(fromPlayer) then
		return false, "Other player is already in a trade"
	end
	
	-- Verify the request exists
	local incoming = IncomingRequests[player.UserId]
	if not incoming or not incoming[fromPlayer.UserId] then
		return false, "No trade request from this player"
	end
	
	-- Cancel all pending requests for both players (they're starting a trade)
	CancelOutgoingRequest(player)
	CancelOutgoingRequest(fromPlayer)
	CancelAllIncomingRequests(player)
	CancelAllIncomingRequests(fromPlayer)
	
	-- Create trade session
	local session: TradeSession = {
		Player1 = fromPlayer,  -- Original requester
		Player2 = player,      -- Accepter
		Player1Offers = {},
		Player2Offers = {},
		Player1LockedIn = false,
		Player2LockedIn = false,
		Player1Accepted = false,
		Player2Accepted = false,
		CreatedAt = os.time(),
	}
	
	-- Store session for both players
	ActiveTrades[player.UserId] = session
	ActiveTrades[fromPlayer.UserId] = session
	
	-- Notify both players that trade started
	TradeService.Client.TradeStarted:Fire(player, fromPlayer)
	TradeService.Client.TradeStarted:Fire(fromPlayer, player)
	
	Log(string.format("Trade started between %s and %s", fromPlayer.Name, player.Name))
	
	return true, nil
end

--[[
	Decline a trade request from another player.
	
	@param player Player - The player declining the request
	@param fromPlayer Player - The player who sent the request
	@return (boolean, string?) - Success status and error message if failed
]]
function TradeService:DeclineTradeRequest(player: Player, fromPlayer: Player): (boolean, string?)
	if not player or not fromPlayer then
		return false, "Invalid players"
	end
	
	local incoming = IncomingRequests[player.UserId]
	if not incoming or not incoming[fromPlayer.UserId] then
		return false, "No trade request from this player"
	end
	
	-- Remove the request
	incoming[fromPlayer.UserId] = nil
	OutgoingRequests[fromPlayer.UserId] = nil
	
	-- Notify the sender that their request was declined
	if fromPlayer:IsDescendantOf(Players) then
		TradeService.Client.TradeRequestCancelled:Fire(fromPlayer, player)
	end
	
	Log(string.format("%s declined trade request from %s", player.Name, fromPlayer.Name))
	
	return true, nil
end

--[[
	Offer a pet in the current trade.
	
	@param player Player - The player offering the pet
	@param petIndex number - The index of the pet in the player's inventory
	@return (boolean, string?) - Success status and error message if failed
]]
function TradeService:OfferItem(player: Player, petIndex: number): (boolean, string?)
	local session = GetTradeSession(player)
	if not session then
		return false, "You are not in a trade"
	end
	
	local isP1 = IsPlayer1(session, player)
	local offers = session.Player1Offers
	if not isP1 then offers = session.Player2Offers end

	local lockedIn = session.Player1LockedIn
	if not isP1 then lockedIn = session.Player2LockedIn end
	
	-- Check if player is locked in
	if lockedIn then
		return false, "You have already locked in and cannot modify offers"
	end
	
	-- Check if pet is already offered
	if IsPetOffered(offers, petIndex) then
		return false, "This pet is already offered"
	end
	
	-- Validate pet exists
	local petData = GetPetData(player, petIndex)
	if not petData then
		return false, "Pet not found in your inventory"
	end
	
	-- Check if pet is locked
	if petData.Locked == true then
		return false, "This pet is locked and cannot be traded"
	end
	
	-- Add to offers
	local offer: TradeOffer = {
		PetIndex = petIndex,
		PetData = petData,
	}
	table.insert(offers, offer)
	
	-- Reset acceptance since offers changed
	ResetAcceptance(session)
	
	-- Notify both players
	NotifyOffersUpdated(session)
	
	Log(string.format("%s offered pet #%d in trade", player.Name, petIndex))
	
	return true, nil
end

--[[
	Remove a pet from the current trade offer.
	
	@param player Player - The player removing the pet
	@param petIndex number - The index of the pet to remove
	@return (boolean, string?) - Success status and error message if failed
]]
function TradeService:RemoveItem(player: Player, petIndex: number): (boolean, string?)
	local session = GetTradeSession(player)
	if not session then
		return false, "You are not in a trade"
	end
	
	local isP1 = IsPlayer1(session, player)
	local offers = session.Player1Offers
	if not isP1 then offers = session.Player2Offers end
	local lockedIn = session.Player1LockedIn
	if not isP1 then lockedIn = session.Player2LockedIn end
	
	-- Check if player is locked in
	if lockedIn then
		return false, "You have already locked in and cannot modify offers"
	end
	
	-- Find and remove the offer
	local foundIndex = nil
	for i, offer in ipairs(offers) do
		if offer.PetIndex == petIndex then
			foundIndex = i
			break
		end
	end
	
	if not foundIndex then
		return false, "Pet is not in your offer"
	end
	
	table.remove(offers, foundIndex)
	
	-- Reset acceptance since offers changed
	ResetAcceptance(session)
	
	-- Notify both players
	NotifyOffersUpdated(session)
	
	Log(string.format("%s removed pet #%d from trade", player.Name, petIndex))
	
	return true, nil
end

--[[
	Lock in the current trade offer.
	After locking in, player cannot add or remove items.
	
	@param player Player - The player locking in
	@return (boolean, string?) - Success status and error message if failed
]]
function TradeService:LockIn(player: Player): (boolean, string?)
	local session = GetTradeSession(player)
	if not session then
		return false, "You are not in a trade"
	end
	
	local isP1 = IsPlayer1(session, player)
	local alreadyLockedIn = session.Player1LockedIn
	if not isP1 then alreadyLockedIn = session.Player2LockedIn end
	
	if alreadyLockedIn then
		return false, "You have already locked in"
	end
	
	-- Lock in
	if isP1 then
		session.Player1LockedIn = true
	else
		session.Player2LockedIn = true
	end
	
	-- Notify both players
	local otherPlayer = isP1 and session.Player2 or session.Player1
	TradeService.Client.TradeLockedIn:Fire(player, player)
	if otherPlayer and otherPlayer:IsDescendantOf(Players) then
		TradeService.Client.TradeLockedIn:Fire(otherPlayer, player)
	end
	
	Log(string.format("%s locked in their trade offer", player.Name))
	
	return true, nil
end

--[[
	Accept the trade (after both players have locked in).
	Trade completes when both players accept.
	
	@param player Player - The player accepting
	@return (boolean, string?) - Success status and error message if failed
]]
function TradeService:AcceptTrade(player: Player): (boolean, string?)
	local session = GetTradeSession(player)
	warn(session)
	if not session then
		warn("Not in trade")
		return false, "You are not in a trade"
	end
	
	-- Both players must be locked in before accepting
	if not session.Player1LockedIn or not session.Player2LockedIn then
		warn("Both players must lock in")
		return false, "Both players must lock in before accepting"
	end
	
	local isP1 = IsPlayer1(session, player)
	local alreadyAccepted = session.Player1Accepted
	if not isP1 then alreadyAccepted = session.Player2Accepted end
	
	if alreadyAccepted then
		warn("You have already accepted")
		return false, "You have already accepted"
	end
	
	-- Set acceptance
	if isP1 then
		session.Player1Accepted = true
	else
		session.Player2Accepted = true
	end
	
	-- Notify both players of acceptance
	local otherPlayer = isP1 and session.Player2 or session.Player1
	TradeService.Client.TradeAccepted:Fire(player, player)
	if otherPlayer and otherPlayer:IsDescendantOf(Players) then
		TradeService.Client.TradeAccepted:Fire(otherPlayer, player)
	end
	
	Log(string.format("%s accepted the trade", player.Name))
	
	-- Check if both have accepted
	if session.Player1Accepted and session.Player2Accepted then
		-- Check inventory space before completing trade
		local DataService = Knit.GetService("DataService")
		local NotificationService = Knit.GetService("NotificationService")
		local MonetizationService = Knit.GetService("MonetizationService")
		local Stats = require(ReplicatedStorage.Modules.Stats)
		
		local player1Inventory = DataService:Get(session.Player1, "Inventory")
		local player2Inventory = DataService:Get(session.Player2, "Inventory")
		
		local player1CurrentPets = player1Inventory and player1Inventory.PetInventory and #player1Inventory.PetInventory or 0
		local player2CurrentPets = player2Inventory and player2Inventory.PetInventory and #player2Inventory.PetInventory or 0
		
		-- Calculate max inventory for each player based on gamepass
		local player1MaxInventory = Stats.MaxPetInventory
		if MonetizationService:HasGamePass(session.Player1, "ExtraSlots") then
			player1MaxInventory = player1MaxInventory + Stats.ExtraSlotsBonus
		end
		local player2MaxInventory = Stats.MaxPetInventory
		if MonetizationService:HasGamePass(session.Player2, "ExtraSlots") then
			player2MaxInventory = player2MaxInventory + Stats.ExtraSlotsBonus
		end
		
		-- Calculate net change: pets received - pets given
		local player1NetChange = #session.Player2Offers - #session.Player1Offers
		local player2NetChange = #session.Player1Offers - #session.Player2Offers
		
		local player1FinalCount = player1CurrentPets + player1NetChange
		local player2FinalCount = player2CurrentPets + player2NetChange
		
		if player1FinalCount > player1MaxInventory then
			NotificationService:SendNotification(session.Player1, string.format("Trade cancelled: You would exceed max inventory (%d/%d pets).", player1FinalCount, player1MaxInventory), NotificationService.Category.Error)
			NotificationService:SendNotification(session.Player2, string.format("Trade cancelled: %s would exceed max inventory.", session.Player1.Name), NotificationService.Category.Error)
			EndTradeSession(session, "Trade cancelled: Player 1 would exceed max inventory")
			return false, "Trade would exceed inventory limit"
		end
		
		if player2FinalCount > player2MaxInventory then
			NotificationService:SendNotification(session.Player2, string.format("Trade cancelled: You would exceed max inventory (%d/%d pets).", player2FinalCount, player2MaxInventory), NotificationService.Category.Error)
			NotificationService:SendNotification(session.Player1, string.format("Trade cancelled: %s would exceed max inventory.", session.Player2.Name), NotificationService.Category.Error)
			EndTradeSession(session, "Trade cancelled: Player 2 would exceed max inventory")
			return false, "Trade would exceed inventory limit"
		end
		
		CompleteTrade(session)
	end
	
	return true, nil
end

--[[
	Decline the trade after locking in (cancels the entire trade).
	
	@param player Player - The player declining
	@return (boolean, string?) - Success status and error message if failed
]]
function TradeService:DeclineTrade(player: Player): (boolean, string?)
	local session = GetTradeSession(player)
	if not session then
		return false, "You are not in a trade"
	end
	
	EndTradeSession(session, string.format("%s declined the trade", player.Name))
	
	return true, nil
end

--[[
	Cancel the current trade session.
	
	@param player Player - The player cancelling
	@return (boolean, string?) - Success status and error message if failed
]]
function TradeService:CancelTrade(player: Player): (boolean, string?)
	local session = GetTradeSession(player)
	if not session then
		return false, "You are not in a trade"
	end
	
	EndTradeSession(session, string.format("%s cancelled the trade", player.Name))
	
	return true, nil
end

--[[
	Get the current trade state for a player.
	Used by clients to sync UI state.
	
	@param player Player - The player requesting state
	@return table? - The trade state or nil if not in trade
]]
function TradeService:GetTradeState(player: Player): any?
	local session = GetTradeSession(player)
	if not session then
		return nil
	end
	
	local isP1 = IsPlayer1(session, player)
	local otherPlayer = isP1 and session.Player2 or session.Player1
	
	return {
		OtherPlayer = otherPlayer,
		MyOffers = isP1 and session.Player1Offers or session.Player2Offers,
		TheirOffers = isP1 and session.Player2Offers or session.Player1Offers,
		ILockedIn = isP1 and session.Player1LockedIn or session.Player2LockedIn,
		TheyLockedIn = isP1 and session.Player2LockedIn or session.Player1LockedIn,
		IAccepted = isP1 and session.Player1Accepted or session.Player2Accepted,
		TheyAccepted = isP1 and session.Player2Accepted or session.Player1Accepted,
	}
end

--[[
	Get pending incoming trade requests for a player.
	
	@param player Player - The player requesting their pending requests
	@return { Player } - Array of players who have sent trade requests
]]
function TradeService:GetPendingRequests(player: Player): { Player }
	local incoming = IncomingRequests[player.UserId]
	if not incoming then
		return {}
	end
	
	local requests = {}
	for _, request in pairs(incoming) do
		if request.FromPlayer:IsDescendantOf(Players) then
			table.insert(requests, request.FromPlayer)
		end
	end
	
	return requests
end

-- Client methods (called by client)
function TradeService.Client:RequestTrade(player: Player, targetPlayer: Player): (boolean, string?)
	local stats, msg = TradeService:RequestTrade(player, targetPlayer)
	local NotificationService = Knit.GetService("NotificationService")

	if msg then
		NotificationService:SendNotification(player, msg, NotificationService.Category[stats and "Success" or "Error"])
	end
end

function TradeService.Client:AcceptTradeRequest(player: Player, fromPlayer: Player): (boolean, string?)
	return TradeService:AcceptTradeRequest(player, fromPlayer)
end

function TradeService.Client:DeclineTradeRequest(player: Player, fromPlayer: Player): (boolean, string?)
	return TradeService:DeclineTradeRequest(player, fromPlayer)
end

function TradeService.Client:OfferItem(player: Player, petIndex: number): (boolean, string?)
	local success, response = TradeService:OfferItem(player, petIndex)
	warn(response)
	return TradeService:OfferItem(player, petIndex)
end

function TradeService.Client:RemoveItem(player: Player, petIndex: number): (boolean, string?)
	return TradeService:RemoveItem(player, petIndex)
end

function TradeService.Client:LockIn(player: Player): (boolean, string?)
	return TradeService:LockIn(player)
end

function TradeService.Client:AcceptTrade(player: Player): (boolean, string?)
	local status, msg = TradeService:AcceptTrade(player)
	warn(status, msg)

	return status, msg
end

function TradeService.Client:DeclineTrade(player: Player): (boolean, string?)
	return TradeService:DeclineTrade(player)
end

function TradeService.Client:CancelTrade(player: Player): (boolean, string?)
	return TradeService:CancelTrade(player)
end

function TradeService.Client:GetTradeState(player: Player): any?
	return TradeService:GetTradeState(player)
end

function TradeService.Client:GetPendingRequests(player: Player): { Player }
	return TradeService:GetPendingRequests(player)
end

function TradeService.Client:SetTradingEnabled(player: Player, enabled: boolean)
	return TradeService:SetTradingEnabled(player, enabled)
end

function TradeService.Client:IsInTrade(player: Player): boolean
	return IsInTrade(player)
end

--[[
	Set whether trading is enabled for a player.
	
	@param player Player - The player setting their preference
	@param enabled boolean - Whether trading should be enabled
]]
function TradeService:SetTradingEnabled(player: Player, enabled: boolean)
	local DataService = Knit.GetService("DataService")
	DataService:Update(player, "Meta", function(meta)
		meta = meta or {}
		if not meta.Settings then
			meta.Settings = {}
		end
		meta.Settings.TradingEnabled = enabled
		return meta
	end)
	
	Log(string.format("%s set trading enabled: %s", player.Name, tostring(enabled)))
end

-- Clean up when player leaves
local function OnPlayerRemoving(player: Player)
	-- Cancel any outgoing requests
	CancelOutgoingRequest(player)
	
	-- Cancel all incoming requests
	CancelAllIncomingRequests(player)
	IncomingRequests[player.UserId] = nil
	
	-- Clean up trading preference
	PlayerTradingEnabled[player.UserId] = nil
	
	-- End any active trade
	local session = GetTradeSession(player)
	if session then
		EndTradeSession(session, string.format("%s left the game", player.Name))
	end
end

-- Knit lifecycle
function TradeService:KnitInit()
	Players.PlayerRemoving:Connect(OnPlayerRemoving)
	Log("TradeService initialized")
end

function TradeService:KnitStart()
	Log("TradeService started")
end

return TradeService
