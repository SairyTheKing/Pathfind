--[[
    Pathfind Library - Path Manager
    
    Handles path computation, recalculation, and validation.
    Wraps PathfindingService with smart caching and throttling.
    
    @author SairyTheKing
    @version 1.2.0
    @license MIT
]]

local PathManager = {}
PathManager.__index = PathManager

export type WaypointData = {
    position: Vector3,
    action: Enum.PathWaypointAction,
    index: number,
}

export type ComputedPath = {
    waypoints: { WaypointData },
    status: Enum.PathStatus,
    rawPath: any?,
    blockedConnection: RBXScriptConnection?,
}

export type PathManager = typeof(setmetatable({} :: {
    _pathfindingService: PathfindingService,
    _agentParams: { [string]: any },
    _lastComputeTime: number,
    _computeThrottle: number,
    _currentPath: ComputedPath?,
    _currentGoal: Vector3?,
    _repathInterval: number,
    _repathThreshold: number,
    _maxPathAttempts: number,
    _pathAttempts: number,
}, PathManager))

function PathManager.new(config: {
    agentRadius: number?,
    agentHeight: number?,
    agentCanJump: boolean?,
    agentCanClimb: boolean?,
    agentCanSlide: boolean?,
    repathInterval: number?,
    repathThreshold: number?,
    maxPathAttempts: number?,
}?): PathManager
    local self = setmetatable({}, PathManager)
    
    config = config or {}
    
    self._pathfindingService = game:GetService("PathfindingService")
    self._lastComputeTime = 0
    self._computeThrottle = 0.1 -- Minimum seconds between computations
    self._currentPath = nil
    self._currentGoal = nil
    self._repathInterval = config.repathInterval or 0.5
    self._repathThreshold = config.repathThreshold or 4
    self._maxPathAttempts = config.maxPathAttempts or 3
    self._pathAttempts = 0
    self._onBlocked = function() end -- Default no-op
    
    -- Build agent parameters
    self._agentParams = {}
    if config.agentRadius then
        self._agentParams.AgentRadius = config.agentRadius
    end
    if config.agentHeight then
        self._agentParams.AgentHeight = config.agentHeight
    end
    if config.agentCanJump ~= nil then
        self._agentParams.AgentCanJump = config.agentCanJump
    end
    if config.agentCanClimb ~= nil then
        self._agentParams.AgentCanClimb = config.agentCanClimb
    end
    if config.agentCanSlide ~= nil then
        self._agentParams.AgentCanSlide = config.agentCanSlide
    end
    
    return self
end

function PathManager:_isThrottled(): boolean
    return (os.clock() - self._lastComputeTime) < self._computeThrottle
end

function PathManager:ComputePath(startPos: Vector3, goalPos: Vector3): ComputedPath?
    if self:_isThrottled() then
        return nil
    end
    
    self._lastComputeTime = os.clock()
    self._currentGoal = goalPos
    
    local result: ComputedPath = {
        waypoints = {},
        status = Enum.PathStatus.NoPath,
        rawPath = nil,
    }
    
    local ok, path = pcall(function()
        return self._pathfindingService:CreatePath(self._agentParams)
    end)
    
    if not ok or not path then
        result.status = Enum.PathStatus.NoPath
        return result
    end
    
    -- Compute the path
    local computeOk, computeResult = pcall(function()
        path:ComputeAsync(startPos, goalPos)
        return path.Status
    end)
    
    if not computeOk or computeResult ~= Enum.PathStatus.Success then
        result.status = computeResult or Enum.PathStatus.NoPath
        return result
    end
    
    -- Extract waypoints
    local rawWaypoints = path:GetWaypoints()
    for i, wp in rawWaypoints do
        table.insert(result.waypoints, {
            position = wp.Position,
            action = wp.Action,
            index = i,
        })
    end
    
    result.status = Enum.PathStatus.Success
    result.rawPath = path
    self._currentPath = result
    self._pathAttempts = 0
    
    -- Connect to Blocked event on the raw path
    self:_connectBlockedEvent(path)
    
    return result
end

function PathManager:ShouldRepath(currentPos: Vector3): boolean
    if not self._currentGoal then
        return false
    end
    
    -- Time-based repath
    local elapsed = os.clock() - self._lastComputeTime
    if elapsed < self._repathInterval then
        return false
    end
    
    -- Distance-based repath
    local distToGoal = (currentPos - self._currentGoal).Magnitude
    if distToGoal > self._repathThreshold then
        return true
    end
    
    return false
end

function PathManager:ShouldRepathForMovingTarget(
    currentPos: Vector3,
    targetPos: Vector3
): boolean
    if not self._currentGoal then
        return true
    end
    
    -- Check if target moved significantly from last computed goal
    local targetDelta = (targetPos - self._currentGoal).Magnitude
    if targetDelta >= self._repathThreshold then
        return true
    end
    
    -- Time-based repath check
    local elapsed = os.clock() - self._lastComputeTime
    if elapsed >= self._repathInterval then
        return true
    end
    
    return false
end

function PathManager:IncrementAttempts(): number
    self._pathAttempts += 1
    return self._pathAttempts
end

function PathManager:ResetAttempts()
    self._pathAttempts = 0
end

function PathManager:HasExceededMaxAttempts(): boolean
    return self._pathAttempts >= self._maxPathAttempts
end

function PathManager:CheckOcclusion(startIndex: number): boolean
    if not self._currentPath or not self._currentPath.rawPath then
        return false
    end
    
    local ok, isOccluded = pcall(function()
        return self._currentPath.rawPath:CheckOcclusionAsync(startIndex)
    end)
    
    if not ok then
        return false
    end
    
    return isOccluded
end

function PathManager:_connectBlockedEvent(path: any)
    -- Disconnect previous blocked event if any
    if self._currentPath and self._currentPath.blockedConnection then
        self._currentPath.blockedConnection:Disconnect()
    end
    
    -- Connect to the Path.Blocked event
    if path and path.Blocked then
        local conn = path.Blocked:Connect(function(waypointIndex: number)
            self._onBlocked(waypointIndex)
        end)
        if self._currentPath then
            self._currentPath.blockedConnection = conn
        end
    end
end

function PathManager:SetBlockedCallback(callback: (waypointIndex: number) -> ())
    self._onBlocked = callback
end

function PathManager:GetCurrentGoal(): Vector3?
    return self._currentGoal
end

function PathManager:Clear()
    -- Disconnect any blocked event before clearing
    if self._currentPath and self._currentPath.blockedConnection then
        self._currentPath.blockedConnection:Disconnect()
    end
    
    self._currentPath = nil
    self._currentGoal = nil
    self._pathAttempts = 0
end

return PathManager
