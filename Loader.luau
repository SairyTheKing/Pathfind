--[[
    Pathfind Library - Executor Loader
    
    Single-file version for use with Roblox executors.
    
    Usage:
        local Pathfind = loadstring(game:HttpGet("https://raw.githubusercontent.com/SairyTheKing/Pathfind/master/Loader.luau"))()
    
    Or for HTTP-disabled executors, copy-paste this entire file.
    
    @author Pathfind Contributors
    @version 1.0.0
    @license MIT
]]

-- =========================================================================
-- Types (inline)
-- =========================================================================

--[[
    PathfindConfig fields:
    agentRadius, agentHeight, agentCanJump, agentCanClimb, agentCanSlide,
    moveSpeed, turnSpeed, reachDistance, jumpPower,
    repathInterval, repathThreshold, maxPathAttempts, timeout, waypointTimeout,
    antiStuckEnabled, stuckThreshold, stuckRecoveryAttempts, stuckMoveDelta,
    losCheckEnabled, losRaycastParams,
    debug, debugColor, debugBlockedColor, debugLineColor
]]

-- =========================================================================
-- Event Module
-- =========================================================================

local Event = {}
Event.__index = Event

function Event.new()
    local self = setmetatable({}, Event)
    self._bindable = Instance.new("BindableEvent")
    self._connections = {}
    return self
end

function Event:Fire(...)
    self._bindable:Fire(...)
end

function Event:Connect(callback)
    local connection = self._bindable.Event:Connect(callback)
    table.insert(self._connections, connection)
    return connection
end

function Event:Once(callback)
    local connection
    connection = self._bindable.Event:Connect(function(...)
        callback(...)
        if connection.Connected then
            connection:Disconnect()
        end
    end)
    table.insert(self._connections, connection)
    return connection
end

function Event:Wait()
    return self._bindable.Event:Wait()
end

function Event:DisconnectAll()
    for _, conn in self._connections do
        if conn.Connected then
            conn:Disconnect()
        end
    end
    table.clear(self._connections)
end

function Event:Destroy()
    self:DisconnectAll()
    self._bindable:Destroy()
end

-- =========================================================================
-- Debug Module
-- =========================================================================

local Debug = {}
Debug.__index = Debug
local DEBUG_PREFIX = "PathfindDebug_"

function Debug.new()
    local self = setmetatable({}, Debug)
    self._enabled = false
    self._folder = nil
    self._waypoints = {}
    self._labels = {}
    self._lines = {}
    return self
end

function Debug:SetEnabled(enabled)
    self._enabled = enabled
    if not enabled then
        self:Clear()
    end
end

function Debug:_ensureFolder()
    if self._folder and self._folder.Parent then
        return self._folder
    end
    self._folder = Instance.new("Folder")
    self._folder.Name = DEBUG_PREFIX .. tostring(game:GetService("HttpService"):GenerateGUID(false))
    self._folder.Parent = workspace
    return self._folder
end

function Debug:_createWaypointMarker(position, color, label)
    local folder = self:_ensureFolder()
    local part = Instance.new("Part")
    part.Size = Vector3.new(0.5, 0.5, 0.5)
    part.Position = position
    part.Anchored = true
    part.CanCollide = false
    part.CanTouch = false
    part.CanQuery = false
    part.Material = Enum.Material.Neon
    part.Color = color
    part.Shape = Enum.PartType.Ball
    part.Parent = folder
    table.insert(self._waypoints, part)

    if label then
        local billboard = Instance.new("BillboardGui")
        billboard.Size = UDim2.new(0, 50, 0, 30)
        billboard.StudsOffset = Vector3.new(0, 1.5, 0)
        billboard.AlwaysOnTop = true
        billboard.Parent = part
        local textLabel = Instance.new("TextLabel")
        textLabel.Size = UDim2.new(1, 0, 1, 0)
        textLabel.BackgroundTransparency = 0.5
        textLabel.BackgroundColor3 = Color3.new(0, 0, 0)
        textLabel.TextColor3 = Color3.new(1, 1, 1)
        textLabel.TextScaled = true
        textLabel.Font = Enum.Font.RobotoMono
        textLabel.Text = label
        textLabel.Parent = billboard
        table.insert(self._labels, billboard)
    end
    return part
end

function Debug:_createLine(from, to, color)
    local folder = self:_ensureFolder()
    local direction = to - from
    local length = direction.Magnitude
    local midpoint = from + direction / 2
    local part = Instance.new("Part")
    part.Size = Vector3.new(0.1, 0.1, length)
    part.CFrame = CFrame.lookAt(midpoint, to)
    part.Anchored = true
    part.CanCollide = false
    part.CanTouch = false
    part.CanQuery = false
    part.Material = Enum.Material.Neon
    part.Color = color
    part.Transparency = 0.3
    part.Parent = folder
    table.insert(self._lines, part)
    return part
end

function Debug:DrawWaypoints(waypoints, color, lineColor)
    if not self._enabled then return end
    local lineCol = lineColor or Color3.new(1, 1, 0)
    for i, wp in waypoints do
        local wpColor = wp.action == Enum.PathWaypointAction.Jump and Color3.new(0, 1, 0) or color
        self:_createWaypointMarker(wp.position, wpColor, tostring(i))
        if i > 1 then
            self:_createLine(waypoints[i - 1].position, wp.position, lineCol)
        end
    end
end

function Debug:DrawCurrentWaypoint(position, color)
    if not self._enabled then return end
    self:_createWaypointMarker(position, color or Color3.new(0, 1, 1), "►")
end

function Debug:Log(message, level)
    if not self._enabled then return end
    local prefix = "[Pathfind" .. (level and (":" .. level) or "") .. "]"
    print(prefix, message)
end

function Debug:Clear()
    for _, wp in self._waypoints do
        if wp and wp.Parent then wp:Destroy() end
    end
    table.clear(self._waypoints)
    for _, label in self._labels do
        if label and label.Parent then label:Destroy() end
    end
    table.clear(self._labels)
    for _, line in self._lines do
        if line and line.Parent then line:Destroy() end
    end
    table.clear(self._lines)
end

function Debug:Destroy()
    self:Clear()
    if self._folder and self._folder.Parent then self._folder:Destroy() end
end

-- =========================================================================
-- AntiStuck Module
-- =========================================================================

local AntiStuck = {}
AntiStuck.__index = AntiStuck

function AntiStuck.new(config)
    local self = setmetatable({}, AntiStuck)
    config = config or {}
    self._enabled = config.enabled ~= false
    self._lastPosition = nil
    self._lastMoveTime = os.clock()
    self._recoveryAttempts = 0
    self._maxRecoveryAttempts = config.maxRecoveryAttempts or 3
    self._stuckThreshold = config.threshold or 2
    self._stuckMoveDelta = config.moveDelta or 0.5
    self._onStuck = config.onStuck
    self._onRecoveryFailed = config.onRecoveryFailed
    self._active = false
    return self
end

function AntiStuck:SetEnabled(enabled)
    self._enabled = enabled
    if not enabled then self:Reset() end
end

function AntiStuck:Start()
    self._active = true
    self._lastPosition = nil
    self._lastMoveTime = os.clock()
    self._recoveryAttempts = 0
end

function AntiStuck:Stop()
    self._active = false
    self:Reset()
end

function AntiStuck:Reset()
    self._lastPosition = nil
    self._lastMoveTime = os.clock()
    self._recoveryAttempts = 0
end

function AntiStuck:UpdatePosition(position)
    if not self._active then return end
    local now = os.clock()
    if self._lastPosition then
        local delta = (position - self._lastPosition).Magnitude
        if delta >= self._stuckMoveDelta then
            self._lastMoveTime = now
            self._recoveryAttempts = 0
        end
    end
    self._lastPosition = position
end

function AntiStuck:IsStuck()
    if not self._enabled or not self._active then return false end
    return (os.clock() - self._lastMoveTime) >= self._stuckThreshold
end

function AntiStuck:AttemptRecovery()
    if not self._active then return nil end
    self._recoveryAttempts += 1
    if self._recoveryAttempts > self._maxRecoveryAttempts then
        if self._onRecoveryFailed then
            self._onRecoveryFailed("Max recovery attempts exceeded")
        end
        return nil
    end
    if self._onStuck then self._onStuck(self._recoveryAttempts) end
    if self._recoveryAttempts == 1 then return "jump"
    elseif self._recoveryAttempts == 2 then return "repath"
    else return "adjust" end
end

function AntiStuck:GetAdjustmentDirection()
    local angle = math.random() * math.pi * 2
    return Vector3.new(math.cos(angle), 0, math.sin(angle)) * 2
end

-- =========================================================================
-- PathManager Module
-- =========================================================================

local PathManager = {}
PathManager.__index = PathManager

function PathManager.new(config)
    local self = setmetatable({}, PathManager)
    config = config or {}
    self._pathfindingService = game:GetService("PathfindingService")
    self._lastComputeTime = 0
    self._computeThrottle = 0.1
    self._currentPath = nil
    self._currentGoal = nil
    self._repathInterval = config.repathInterval or 0.5
    self._repathThreshold = config.repathThreshold or 4
    self._maxPathAttempts = config.maxPathAttempts or 3
    self._pathAttempts = 0
    self._onBlocked = function() end

    self._agentParams = {}
    if config.agentRadius then self._agentParams.AgentRadius = config.agentRadius end
    if config.agentHeight then self._agentParams.AgentHeight = config.agentHeight end
    if config.agentCanJump ~= nil then self._agentParams.AgentCanJump = config.agentCanJump end
    if config.agentCanClimb ~= nil then self._agentParams.AgentCanClimb = config.agentCanClimb end
    if config.agentCanSlide ~= nil then self._agentParams.AgentCanSlide = config.agentCanSlide end
    return self
end

function PathManager:_isThrottled()
    return (os.clock() - self._lastComputeTime) < self._computeThrottle
end

function PathManager:ComputePath(startPos, goalPos)
    if self:_isThrottled() then return nil end
    self._lastComputeTime = os.clock()
    self._currentGoal = goalPos

    local result = { waypoints = {}, status = Enum.PathStatus.NoPath, rawPath = nil }

    local ok, path = pcall(function()
        return self._pathfindingService:CreatePath(self._agentParams)
    end)
    if not ok or not path then return result end

    local computeOk, computeResult = pcall(function()
        path:ComputeAsync(startPos, goalPos)
        return path.Status
    end)
    if not computeOk or computeResult ~= Enum.PathStatus.Success then
        result.status = computeResult or Enum.PathStatus.NoPath
        return result
    end

    for i, wp in path:GetWaypoints() do
        table.insert(result.waypoints, { position = wp.Position, action = wp.Action, index = i })
    end
    result.status = Enum.PathStatus.Success
    result.rawPath = path
    self._currentPath = result
    self._pathAttempts = 0
    self:_connectBlockedEvent(path)
    return result
end

function PathManager:ShouldRepathForMovingTarget(currentPos, targetPos)
    if not self._currentGoal then return true end
    if (targetPos - self._currentGoal).Magnitude >= self._repathThreshold then return true end
    if (os.clock() - self._lastComputeTime) >= self._repathInterval then return true end
    return false
end

function PathManager:IncrementAttempts()
    self._pathAttempts += 1
    return self._pathAttempts
end

function PathManager:HasExceededMaxAttempts()
    return self._pathAttempts >= self._maxPathAttempts
end

function PathManager:_connectBlockedEvent(path)
    if self._currentPath and self._currentPath.blockedConnection then
        self._currentPath.blockedConnection:Disconnect()
    end
    if path and path.Blocked then
        local conn = path.Blocked:Connect(function(waypointIndex)
            self._onBlocked(waypointIndex)
        end)
        if self._currentPath then self._currentPath.blockedConnection = conn end
    end
end

function PathManager:SetBlockedCallback(callback)
    self._onBlocked = callback
end

function PathManager:GetCurrentGoal()
    return self._currentGoal
end

function PathManager:Clear()
    if self._currentPath and self._currentPath.blockedConnection then
        self._currentPath.blockedConnection:Disconnect()
    end
    self._currentPath = nil
    self._currentGoal = nil
    self._pathAttempts = 0
end

-- =========================================================================
-- MovementEngine Module
-- =========================================================================

local MovementEngine = {}
MovementEngine.__index = MovementEngine

function MovementEngine.new(config)
    local self = setmetatable({}, MovementEngine)
    config = config or {}
    self._turnSpeed = config.turnSpeed or 12
    self._reachDistance = config.reachDistance or 2
    self._moveSpeed = config.moveSpeed
    self._jumpPower = config.jumpPower
    self._losCheckEnabled = config.losCheckEnabled ~= false
    self._losRaycastParams = config.losRaycastParams
    self._character = nil
    self._humanoid = nil
    self._rootPart = nil
    self._connection = nil
    self._onReachWaypoint = nil
    self._onPathCompleted = nil
    self._state = {
        currentWaypointIndex = 1,
        isMoving = false,
        isPaused = false,
        lastPosition = nil,
        targetPosition = nil,
        waypoints = {},
    }
    return self
end

function MovementEngine:SetCharacter(character)
    self._character = character
    if character then
        self._humanoid = character:FindFirstChildOfClass("Humanoid")
        self._rootPart = character:FindFirstChild("HumanoidRootPart")
    else
        self._humanoid = nil
        self._rootPart = nil
    end
end

function MovementEngine:GetHumanoid() return self._humanoid end
function MovementEngine:GetRootPart() return self._rootPart end
function MovementEngine:GetState() return self._state end

function MovementEngine:OnReachWaypoint(callback)
    self._onReachWaypoint = callback
end

function MovementEngine:OnPathCompleted(callback)
    self._onPathCompleted = callback
end

function MovementEngine:_refreshReferences()
    if not self._character or not self._character.Parent then
        self:SetCharacter(nil)
        return false
    end
    self._humanoid = self._character:FindFirstChildOfClass("Humanoid")
    self._rootPart = self._character:FindFirstChild("HumanoidRootPart")
    return self._humanoid ~= nil and self._rootPart ~= nil
end

function MovementEngine:_isCharacterValid()
    if not self:_refreshReferences() then return false end
    return self._humanoid ~= nil and self._humanoid.Health > 0
        and self._rootPart ~= nil and self._rootPart.Parent ~= nil
end

function MovementEngine:_getCharacterPosition()
    if self:_refreshReferences() and self._rootPart then
        return self._rootPart.Position
    end
    return nil
end

function MovementEngine:_turnToFace(targetPos, dt)
    if not self._rootPart or not self._rootPart.Parent then return end
    local currentPos = self._rootPart.Position
    local direction = (targetPos - currentPos) * Vector3.new(1, 0, 1)
    if direction.Magnitude < 0.01 then return end
    local targetCF = CFrame.lookAt(currentPos, currentPos + direction)
    local alpha = math.min(1, self._turnSpeed * dt)
    self._rootPart.CFrame = self._rootPart.CFrame:Lerp(targetCF, alpha)
end

function MovementEngine:_checkLineOfSight(from, to)
    if not self._losCheckEnabled then return false end
    local excludeList = {}
    if self._character then table.insert(excludeList, self._character) end
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.FilterDescendantsInstances = excludeList
    rayParams.RespectCanCollide = true
    return workspace:Raycast(from, to - from, rayParams) == nil
end

function MovementEngine:StartMoving(waypoints, targetPosition)
    if not self:_isCharacterValid() then return end
    if self._moveSpeed then self._humanoid.WalkSpeed = self._moveSpeed end
    if self._jumpPower then self._humanoid.JumpPower = self._jumpPower end

    self._state.waypoints = waypoints
    self._state.currentWaypointIndex = 1
    self._state.isMoving = true
    self._state.isPaused = false
    self._state.targetPosition = targetPosition
    self._state.lastPosition = self._rootPart.Position
    self:_startMovementLoop()
end

function MovementEngine:_startMovementLoop()
    if self._connection then self._connection:Disconnect() end
    self._activeMoveToIndex = 0

    self._connection = game:GetService("RunService").Heartbeat:Connect(function(dt)
        if not self._state.isMoving or self._state.isPaused then return end
        if not self:_isCharacterValid() then
            self:Stop()
            if self._onPathCompleted then self._onPathCompleted(false) end
            return
        end

        local currentPos = self._rootPart.Position
        self._state.lastPosition = currentPos
        local waypointIndex = self._state.currentWaypointIndex
        local waypoints = self._state.waypoints

        if waypointIndex > #waypoints then
            self:Stop()
            if self._onPathCompleted then self._onPathCompleted(true) end
            return
        end

        local currentWaypoint = waypoints[waypointIndex]
        local dist = (currentPos - currentWaypoint.position).Magnitude

        if dist <= self._reachDistance then
            if self._onReachWaypoint then
                self._onReachWaypoint(waypointIndex, currentWaypoint)
            end
            self._state.currentWaypointIndex = waypointIndex + 1
            self._activeMoveToIndex = 0

            -- LOS skip
            if self._losCheckEnabled and self._state.targetPosition then
                local idx = self._state.currentWaypointIndex
                for i = idx, math.min(idx + 3, #self._state.waypoints) do
                    local wp = self._state.waypoints[i]
                    if wp.action == Enum.PathWaypointAction.Jump then break end
                    if self:_checkLineOfSight(currentPos, wp.position) then
                        self._state.currentWaypointIndex = i + 1
                    else break end
                end
            end
        else
            if self._activeMoveToIndex ~= waypointIndex then
                self._activeMoveToIndex = waypointIndex
                if currentWaypoint.action == Enum.PathWaypointAction.Jump and self._humanoid then
                    self._humanoid.Jump = true
                end
                self:_turnToFace(currentWaypoint.position, dt)
                if self._humanoid then self._humanoid:MoveTo(currentWaypoint.position) end
            else
                self:_turnToFace(currentWaypoint.position, dt)
            end
        end
    end)
end

function MovementEngine:Stop()
    self._state.isMoving = false
    self._state.isPaused = false
    if self._connection then self._connection:Disconnect() self._connection = nil end
    if self._humanoid and self._humanoid.Parent and self._rootPart then
        self._humanoid:MoveTo(self._rootPart.Position)
    end
end

function MovementEngine:Pause() self._state.isPaused = true end
function MovementEngine:Resume() self._state.isPaused = false end
function MovementEngine:IsMoving() return self._state.isMoving and not self._state.isPaused end

function MovementEngine:GetProgress()
    if #self._state.waypoints == 0 then return 0 end
    return self._state.currentWaypointIndex / #self._state.waypoints
end

function MovementEngine:Destroy()
    self:Stop()
    self:SetCharacter(nil)
end

-- =========================================================================
-- Pathfind Core Module
-- =========================================================================

local Pathfind = {}
Pathfind.__index = Pathfind

local DEFAULT_CONFIG = {
    agentRadius = nil, agentHeight = nil,
    agentCanJump = true, agentCanClimb = false, agentCanSlide = false,
    moveSpeed = nil, turnSpeed = 12, reachDistance = 2, jumpPower = nil,
    repathInterval = 0.5, repathThreshold = 4, maxPathAttempts = 3,
    timeout = nil, waypointTimeout = 4,
    antiStuckEnabled = true, stuckThreshold = 2, stuckRecoveryAttempts = 3, stuckMoveDelta = 0.5,
    losCheckEnabled = true, losRaycastParams = nil,
    debug = false, debugColor = Color3.new(0, 1, 1),
    debugBlockedColor = Color3.new(1, 0, 0), debugLineColor = Color3.new(1, 1, 0),
}

function Pathfind.new(character, config)
    local self = setmetatable({}, Pathfind)
    self._config = {}
    for key, value in DEFAULT_CONFIG do
        self._config[key] = config and config[key] or value
    end

    self._character = character
    self._status = "idle"
    self._isPaused = false
    self._timeoutThread = nil
    self._repathThread = nil
    self._alive = true
    self._currentTarget = nil

    -- Events
    self.Completed = Event.new()
    self.Blocked = Event.new()
    self.Repath = Event.new()
    self.Stuck = Event.new()
    self.Failed = Event.new()
    self.Paused = Event.new()
    self.Resumed = Event.new()
    self.Started = Event.new()
    self.Waypoint = Event.new()

    -- Subsystems
    self._debug = Debug.new()
    self._debug:SetEnabled(self._config.debug or false)

    self._pathManager = PathManager.new({
        agentRadius = self._config.agentRadius,
        agentHeight = self._config.agentHeight,
        agentCanJump = self._config.agentCanJump,
        agentCanClimb = self._config.agentCanClimb,
        agentCanSlide = self._config.agentCanSlide,
        repathInterval = self._config.repathInterval,
        repathThreshold = self._config.repathThreshold,
        maxPathAttempts = self._config.maxPathAttempts,
    })

    self._movementEngine = MovementEngine.new({
        turnSpeed = self._config.turnSpeed,
        reachDistance = self._config.reachDistance,
        moveSpeed = self._config.moveSpeed,
        jumpPower = self._config.jumpPower,
        losCheckEnabled = self._config.losCheckEnabled,
        losRaycastParams = self._config.losRaycastParams,
    })

    self._antiStuck = AntiStuck.new({
        enabled = self._config.antiStuckEnabled,
        threshold = self._config.stuckThreshold,
        moveDelta = self._config.stuckMoveDelta,
        maxRecoveryAttempts = self._config.stuckRecoveryAttempts,
        onStuck = function(attempt)
            self.Stuck:Fire(attempt)
            self._debug:Log("Stuck detected (attempt " .. attempt .. ")", "WARN")
        end,
        onRecoveryFailed = function(reason)
            self:_fail("Anti-stuck recovery failed: " .. reason)
        end,
    })

    self._movementEngine:OnReachWaypoint(function(index, waypoint)
        self:_onWaypointReached(index, waypoint)
    end)
    self._movementEngine:OnPathCompleted(function(success)
        self:_onPathFinished(success)
    end)
    self._pathManager:SetBlockedCallback(function(waypointIndex)
        self._debug:Log("Path blocked at waypoint " .. waypointIndex, "WARN")
        self.Blocked:Fire(waypointIndex)
    end)

    if character then self:_setupCharacterWatch() end
    return self
end

-- =========================================================================
-- Character Watch
-- =========================================================================

function Pathfind:_setupCharacterWatch()
    if not self._character then return end
    self._character.Destroying:Connect(function()
        if self._status == "moving" then self:Stop() end
        self._movementEngine:SetCharacter(nil)
    end)
end

function Pathfind:SetCharacter(character)
    self._character = character
    self._movementEngine:SetCharacter(character)
    if character then self:_setupCharacterWatch() end
end

-- =========================================================================
-- Public Navigation API
-- =========================================================================

function Pathfind:GoTo(target, timeout)
    if not self._alive then return self end
    if self._status == "moving" then self:Stop() end

    local targetPos = self:_resolveTargetPosition(target)
    if not targetPos then self:_fail("Invalid target") return self end
    if not self._movementEngine:_isCharacterValid() then
        self:_fail("Character is invalid") return self
    end

    self._currentTarget = target
    self.Started:Fire(target)
    self:_computeAndMove(targetPos, target, timeout or self._config.timeout)
    return self
end

function Pathfind:Follow(target, repathInterval)
    if not self._alive then return self end
    if self._status == "moving" then self:Stop() end
    if not target or not target.Parent then self:_fail("Invalid follow target") return self end
    if not self._movementEngine:_isCharacterValid() then self:_fail("Character is invalid") return self end

    local interval = repathInterval or self._config.repathInterval or 0.5
    self._currentTarget = target
    self.Started:Fire(target)

    task.spawn(function()
        while self._alive and target and target.Parent do
            if self._isPaused then task.wait(0.1) continue end
            local targetPos = self:_resolveTargetPosition(target)
            if not targetPos then self:_fail("Follow target lost") break end

            local currentPos = self._movementEngine:_getCharacterPosition()
            if currentPos and self._pathManager:ShouldRepathForMovingTarget(currentPos, targetPos) then
                self.Repath:Fire(self._pathManager._pathAttempts)
                self:_computeAndMove(targetPos, target, nil)
            end
            task.wait(interval)
        end
        if self._alive then
            self.Completed:Fire(false, "Follow loop ended")
            self._status = "idle"
        end
    end)
    return self
end

function Pathfind:PreviewPath(target)
    if not self._alive then return nil end
    local targetPos = self:_resolveTargetPosition(target)
    if not targetPos then return nil end
    local startPos = self._movementEngine:_getCharacterPosition()
    if not startPos then return nil end

    local path = self._pathManager:ComputePath(startPos, targetPos)
    if not path or path.status ~= Enum.PathStatus.Success then
        return { waypoints = {}, distance = 0, success = false }
    end
    local totalDistance = 0
    for i = 2, #path.waypoints do
        totalDistance += (path.waypoints[i].position - path.waypoints[i - 1].position).Magnitude
    end
    return { waypoints = path.waypoints, distance = totalDistance, success = true }
end

-- =========================================================================
-- Public Control API
-- =========================================================================

function Pathfind:Stop()
    if not self._alive then return end
    self._status = "idle"
    self._isPaused = false
    self._currentTarget = nil
    self._movementEngine:Stop()
    self._pathManager:Clear()
    self._antiStuck:Stop()
    self:_cancelThreads()
    self._debug:Clear()
end

function Pathfind:CancelGoTo()
    if not self._alive then return end
    self._status = "idle"
    self._currentTarget = nil
    self._movementEngine:Stop()
    self._pathManager:Clear()
    self._antiStuck:Stop()
    self:_cancelThreads()
    self._debug:Clear()
end

function Pathfind:Pause()
    if not self._alive or self._status ~= "moving" then return end
    self._isPaused = true
    self._movementEngine:Pause()
    self.Paused:Fire()
end

function Pathfind:Resume()
    if not self._alive or not self._isPaused then return end
    self._isPaused = false
    self._movementEngine:Resume()
    self.Resumed:Fire()
end

-- =========================================================================
-- Public Query API
-- =========================================================================

function Pathfind:IsMoving() return self._movementEngine:IsMoving() end
function Pathfind:GetStatus() return self._status end
function Pathfind:GetProgress() return self._movementEngine:GetProgress() end
function Pathfind:GetTarget() return self._pathManager:GetCurrentGoal() end
function Pathfind:IsPaused() return self._isPaused end
function Pathfind:IsAlive() return self._alive end
function Pathfind:GetCharacter() return self._character end

function Pathfind:GetWaypoints()
    local state = self._movementEngine:GetState()
    return #state.waypoints > 0 and state.waypoints or nil
end

function Pathfind:GetPathInfo()
    local state = self._movementEngine:GetState()
    local goal = self._pathManager:GetCurrentGoal()
    local currentPos = self._movementEngine:_getCharacterPosition()
    local distToTarget = nil
    if currentPos and goal then distToTarget = (currentPos - goal).Magnitude end
    return {
        status = self._status, target = goal, progress = self:GetProgress(),
        currentWaypoint = state.currentWaypointIndex, totalWaypoints = #state.waypoints,
        distanceToTarget = distToTarget, pathAttempts = self._pathManager._pathAttempts,
        isPaused = self._isPaused,
    }
end

-- =========================================================================
-- Configuration
-- =========================================================================

function Pathfind:SetConfig(key, value)
    self._config[key] = value
    if key == "debug" then self._debug:SetEnabled(value)
    elseif key == "antiStuckEnabled" then self._antiStuck:SetEnabled(value) end
end

function Pathfind:GetConfig(key) return self._config[key] end

function Pathfind:EnableDebug(enabled)
    self._config.debug = enabled
    self._debug:SetEnabled(enabled)
end

-- =========================================================================
-- Internal: Path Computation
-- =========================================================================

function Pathfind:_computeAndMove(targetPos, originalTarget, timeout)
    if not self._alive then return end
    self._status = "computing"
    local startPos = self._movementEngine:_getCharacterPosition()
    if not startPos then self:_fail("Cannot get character position") return end

    local path = self._pathManager:ComputePath(startPos, targetPos)
    if not path or path.status ~= Enum.PathStatus.Success then
        self._pathManager:IncrementAttempts()
        if self._pathManager:HasExceededMaxAttempts() then
            self:_fail("No path found after " .. tostring(self._config.maxPathAttempts) .. " attempts")
            return
        end
        task.delay(0.3, function()
            if self._alive and self._status == "computing" then
                self:_computeAndMove(targetPos, originalTarget, timeout)
            end
        end)
        return
    end

    if #path.waypoints < 2 then self:_fail("Path too short") return end
    table.remove(path.waypoints, 1)

    if self._config.debug then
        self._debug:Clear()
        self._debug:DrawWaypoints(path.waypoints, self._config.debugColor, self._config.debugLineColor)
    end

    self._status = "moving"
    self._antiStuck:Start()
    self._movementEngine:StartMoving(path.waypoints, targetPos)

    if timeout and timeout > 0 then self:_startTimeout(timeout) end
    self:_startRepathChecker(originalTarget)
end

function Pathfind:_startTimeout(seconds)
    self:_cancelThread("timeout")
    self._timeoutThread = task.delay(seconds, function()
        if self._alive and self._status == "moving" then self:_fail("Timeout") end
    end)
end

function Pathfind:_startRepathChecker(originalTarget)
    self:_cancelThread("repath")
    self._repathThread = task.spawn(function()
        while self._alive and self._status == "moving" do
            task.wait(self._config.repathInterval or 0.5)
            if not self._alive or self._status ~= "moving" or self._isPaused then break end

            local currentPos = self._movementEngine:_getCharacterPosition()
            if not currentPos then continue end

            if originalTarget and typeof(originalTarget) == "Instance" then
                local targetPos = self:_resolveTargetPosition(originalTarget)
                if targetPos and self._pathManager:ShouldRepathForMovingTarget(currentPos, targetPos) then
                    self.Repath:Fire(self._pathManager._pathAttempts)
                    self:_computeAndMove(targetPos, originalTarget, nil)
                    return
                end
            end

            self._antiStuck:UpdatePosition(currentPos)
            if self._antiStuck:IsStuck() then
                local strategy = self._antiStuck:AttemptRecovery()
                if strategy == "jump" then
                    local h = self._movementEngine:GetHumanoid()
                    if h then h.Jump = true end
                elseif strategy == "repath" then
                    local goal = self._pathManager:GetCurrentGoal()
                    if goal then
                        self.Repath:Fire(self._pathManager._pathAttempts)
                        self:_computeAndMove(goal, originalTarget, nil)
                        return
                    end
                elseif strategy == "adjust" then
                    local root = self._movementEngine:GetRootPart()
                    local h = self._movementEngine:GetHumanoid()
                    if root and h then
                        h:MoveTo(root.Position + self._antiStuck:GetAdjustmentDirection())
                    end
                end
            end
        end
    end)
end

function Pathfind:_cancelThreads(threadType)
    if threadType == "timeout" or not threadType then
        if self._timeoutThread then task.cancel(self._timeoutThread) self._timeoutThread = nil end
    end
    if threadType == "repath" or not threadType then
        if self._repathThread then task.cancel(self._repathThread) self._repathThread = nil end
    end
end

-- =========================================================================
-- Internal: Callbacks
-- =========================================================================

function Pathfind:_onWaypointReached(index, waypoint)
    self._debug:Log("Waypoint " .. index .. " reached")
    self._antiStuck:Reset()
    self.Waypoint:Fire(index, waypoint)
    if self._config.debug then
        self._debug:DrawCurrentWaypoint(waypoint.position, self._config.debugColor)
    end
end

function Pathfind:_onPathFinished(success)
    self._antiStuck:Stop()
    self:_cancelThreads()
    self.Completed:Fire(success)
    self._status = "idle"
end

function Pathfind:_fail(reason)
    self._debug:Log("Failed: " .. reason, "ERROR")
    self._status = "failed"
    self._antiStuck:Stop()
    self:_cancelThreads()
    self._movementEngine:Stop()
    self._pathManager:Clear()
    self.Failed:Fire(reason)
    self._status = "idle"
end

function Pathfind:_resolveTargetPosition(target)
    if typeof(target) == "Vector3" then return target end
    if typeof(target) == "Instance" then
        if target:IsA("BasePart") then return target.Position
        elseif target:IsA("Model") then
            local primaryPart = target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart")
            if primaryPart then return primaryPart.Position end
        elseif target:IsA("Attachment") then return target.WorldPosition end
        local part = target:FindFirstChildWhichIsA("BasePart")
        if part then return part.Position end
    end
    return nil
end

-- =========================================================================
-- Cleanup
-- =========================================================================

function Pathfind:Destroy()
    if not self._alive then return end
    self._alive = false
    self:Stop()
    self.Completed:Destroy()
    self.Blocked:Destroy()
    self.Repath:Destroy()
    self.Stuck:Destroy()
    self.Failed:Destroy()
    self.Paused:Destroy()
    self.Resumed:Destroy()
    self.Started:Destroy()
    self.Waypoint:Destroy()
    self._debug:Destroy()
    self._movementEngine:Destroy()
    self._debug = nil
    self._movementEngine = nil
    self._pathManager = nil
    self._antiStuck = nil
    self._character = nil
end

return Pathfind
