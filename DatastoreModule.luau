local Version = script.Version.Value
-- 0 = Testing
-- 1 = Official

local Blacklist = {
	--'derkywerp', -- Derky
}

local ReplicatedStorage = game:GetService('ReplicatedStorage')
local DatastoreService = game:GetService('DataStoreService')
local Players = game:GetService('Players')
local TweenService = game:GetService('TweenService')

local CashTweenInfo = TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local GameDatastore = DatastoreService:GetDataStore('v' .. Version)
local CashDatastore = DatastoreService:GetOrderedDataStore('v' .. Version .. '_Cash')

local DataStructure = require(script.DataStructure).Structure
local Trove = require(ReplicatedStorage.Packages.Trove)

local Datastore = {}
local PlayerTroves = {}
local IsShuttingDown = false

function Datastore:InitializePlayer(Player)
	Datastore:_StartRecursiveInitialization(DataStructure, 'Data', nil, Player)
	print('Successfully Initialized: ' .. Player.Name .. ' (' .. Player.UserId .. ')')
end

function Datastore:LoadData(Player)
	local Success, ErrorMsg, Data
	local Attempts = 0
	repeat
		Success, ErrorMsg = pcall(function()
			Data = GameDatastore:GetAsync(Player.UserId)
		end)
		Attempts += 1
	until Attempts >= 10 or Success

	if Success and Attempts < 10 then
		if Data then
			Datastore:_UnpackData(Player, Data, Player.Data)
			print('Data successfully loaded for: ' .. Player.Name .. ' (' .. Player.UserId .. ')')
		else
			print('No data found for: ' .. Player.Name .. ' (' .. Player.UserId .. ')')
		end
	else
		warn(ErrorMsg)
	end
end

function Datastore:SaveData(Player)
	local DataTable = Datastore:_PackFolder(Player.Data)

	local Success, ErrorMsg
	local Attempts = 0
	repeat
		Success, ErrorMsg = pcall(function()
			GameDatastore:SetAsync(Player.UserId, DataTable)
		end)
		Attempts += 1
	until Attempts >= 10 or Success

	if Success and Attempts < 10 then
		print('Data successfully saved for: ' .. Player.Name .. ' (' .. Player.UserId .. ')')
	else
		warn(ErrorMsg)
	end

	local Success2, ErrorMsg2
	local Attempts2 = 0
	repeat
		Success2, ErrorMsg2 = pcall(function()
			CashDatastore:SetAsync(Player.UserId, math.min(math.floor(DataTable['Cash']), 2^53))
		end)
		Attempts2 += 1
	until Attempts2 >= 10 or Success2
end

function Datastore:_StartRecursiveInitialization(ChildrenData, FolderName, ParentFolder, Player)
	local Folder = Instance.new('Folder')

	local IsSaveChildren = string.sub(FolderName, 1, 1) == '_'
	
	Folder.Name = IsSaveChildren and string.sub(FolderName, 2) or FolderName
	Folder:SetAttribute('SaveChildren', IsSaveChildren)

	if ParentFolder then
		Folder.Parent = ParentFolder
	else
		Folder.Parent = Player
	end

	for Name, Value in pairs(ChildrenData) do
		local DataInstance
		local ValueType = type(Value)

		if ValueType == 'table' then
			DataInstance = Datastore:_StartRecursiveInitialization(Value, Name, Folder, Player)
		elseif ValueType == 'number' then
			DataInstance = Instance.new('NumberValue', Folder)
		elseif ValueType == 'boolean' then
			DataInstance = Instance.new('BoolValue', Folder)
		elseif ValueType == 'string' then
			DataInstance = Instance.new('StringValue', Folder)
		else
			warn('Invalid type for: ' .. Name)
			continue
		end

		if ValueType ~= 'table' then
			DataInstance.Value = Value
			DataInstance.Name = Name
		end
	end

	return Folder
end

function Datastore:_PackFolder(Folder)
	local Result = {}

	for _, DataInstance in pairs(Folder:GetChildren()) do
		local InstanceName = DataInstance.Name
		
		if DataInstance:GetAttribute('SaveChildren') == true then
			InstanceName = '_' .. InstanceName
		end

		if DataInstance:IsA('Folder') then
			Result[InstanceName] = Datastore:_PackFolder(DataInstance)
		else
			Result[InstanceName] = DataInstance.Value
		end
	end

	return Result
end

function Datastore:_UnpackData(Player, DataTable, ParentFolder)
	for Name, Value in pairs(DataTable) do
		
		local FolderName = string.sub(Name, 1, 1) == '_' and string.sub(Name, 2) or Name

		local DataInstance = ParentFolder:FindFirstChild(FolderName)

		if DataInstance then
			if DataInstance:IsA('Folder') then
				Datastore:_UnpackData(Player, Value, DataInstance)
			else
				DataInstance.Value = Value
			end
		else
			local ValueType = type(Value)

			if ValueType == 'number' then
				DataInstance = Instance.new('NumberValue', ParentFolder)
			elseif ValueType == 'boolean' then
				DataInstance = Instance.new('BoolValue', ParentFolder)
			elseif ValueType == 'string' then
				DataInstance = Instance.new('StringValue', ParentFolder)
			elseif ValueType == 'table' then
				local SubFolder = Instance.new('Folder', ParentFolder)
				SubFolder.Name = FolderName
				SubFolder:SetAttribute('SaveChildren', true)
				Datastore:_UnpackData(Player, Value, SubFolder)
				continue
			else
				warn('Invalid type for: ' .. Name)
				continue
			end

			DataInstance.Name = FolderName
			DataInstance.Value = Value
		end
	end
end

function Datastore:_PlayerAdded(Player)
	local PlayerTrove = Trove.new()
	PlayerTroves[Player] = PlayerTrove

	Player:SetAttribute('DataLoaded', false)
	Datastore:InitializePlayer(Player)
	Datastore:LoadData(Player)

	local LeaderstatsFolder = PlayerTrove:Add(Instance.new('Folder'))
	LeaderstatsFolder.Name = 'leaderstats'
	LeaderstatsFolder.Parent = Player

	local CashLeaderstats = Instance.new('NumberValue', LeaderstatsFolder)
	CashLeaderstats.Name = 'Cash'
	CashLeaderstats.Value = Player.Data.Cash.Value
	PlayerTrove:Connect(Player.Data.Cash.Changed, function(NewValue)
		local CashTween = TweenService:Create(CashLeaderstats, CashTweenInfo, {Value = NewValue})
		CashTween:Play()
	end)

	Player:SetAttribute('DataLoaded', true)
	Player:SetAttribute('HoldingBrainrot', 'Nothing')

	while Player.Parent do
		task.wait(60)
		if not table.find(Blacklist, Player.UserId) and not Player:GetAttribute('DataSavedForLeave') then
			Datastore:SaveData(Player)
		end
	end
end

function Datastore:_PlayerRemoving(Player)
	if IsShuttingDown then return end

	Datastore:SaveData(Player)
	Player:SetAttribute('DataSavedForLeave', true)

	local PlayerTrove = PlayerTroves[Player]
	if PlayerTrove then
		PlayerTrove:Destroy()
		PlayerTroves[Player] = nil
	end
end

function Datastore:SaveAllData()
	IsShuttingDown = true

	local SaveThreads = {}

	for _, Player in ipairs(Players:GetPlayers()) do
		local Thread = task.spawn(function()
			if not Player:GetAttribute('DataSavedForLeave') then
				Datastore:SaveData(Player)
			end
		end)
		table.insert(SaveThreads, Thread)
	end

	for _, Thread in ipairs(SaveThreads) do
		task.wait()
		while coroutine.status(Thread) ~= 'dead' do
			task.wait()
		end
	end
end

function Datastore:Start()
	Players.PlayerAdded:Connect(function(Player) Datastore:_PlayerAdded(Player) end)
	Players.PlayerRemoving:Connect(function(Player) Datastore:_PlayerRemoving(Player) end)
end

return Datastore
