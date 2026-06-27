--[[
    Pathfind Library - Movement Engine
    
    Handles smooth waypoint following, line-of-sight optimization,
    automatic jump handling, and natural movement.
    
    @author Pathfind Contributors
    @version 1.0.0
    @license MIT
]]

local MovementEngine = {}
MovementEngine.__index = MovementEngine

export type WaypointData = {
    position: Vector3,
    action: Enum.PathWaypointAction,
    index: number,
}

export type MovementState = {
    currentWaypointIndex: number,
    isMoving: boolean,
    isPaused: boolean,
    lastPosition: Vector3?,
    targetPosition: Vector3?,
    waypoints: { WaypointData },
}

export type MovementEngine = typeof(setmetatable({} :: {
    _character: Model?,
    _humanoid: Humanoid?,
    _rootPart: BasePart?,
    _turnSpeed: number,
    _reachDistance: number,
    _moveSpeed: number?,
    _jumpPower: number?,
    _losCheckEnabled: boolean,
    _losRaycastParams: RaycastParams?,
    _state: MovementState,
    _connection: RBXScriptConnection?,
    _onReachWaypoint: ((index: number, waypoint: WaypointData) -> ())?,
    _onPathCompleted: ((success: boolean) -> ())?,
}, MovementEngine))

function MovementEngine.new(config: {
    turnSpeed: number?,
    reachDistance: number?,
    moveSpeed: number?,
    jumpPower: number?,
    losCheckEnabled: boolean?,
    losRaycastParams: RaycastParams?,
}?): MovementEngine
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

function MovementEngine:SetCharacter(character: Model?)
    self._character = character
    if character then
        self._humanoid = character:FindFirstChildOfClass("Humanoid")
        self._rootPart = character:FindFirstChild("HumanoidRootPart")
    else
        self._humanoid = nil
        self._rootPart = nil
    end
end

function MovementEngine:GetCharacter(): Model?
    return self._character
end

function MovementEngine:GetHumanoid(): Humanoid?
    return self._humanoid
end

function MovementEngine:GetRootPart(): BasePart?
    return self._rootPart
end

function MovementEngine:OnReachWaypoint(callback: (index: number, waypoint: WaypointData) -> ())
    self._onReachWaypoint = callback
end

function MovementEngine:OnPathCompleted(callback: (success: boolean) -> ())
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

function MovementEngine:_isCharacterValid(): boolean
    if not self:_refreshReferences() then
        return false
    end
    
    return self._humanoid ~= nil
        and self._humanoid.Health > 0
        and self._rootPart ~= nil
        and self._rootPart.Parent ~= nil
end

function MovementEngine:_applyMoveSpeed()
    if self._humanoid and self._moveSpeed then
        self._humanoid.WalkSpeed = self._moveSpeed
    end
end

function MovementEngine:_applyJumpPower()
    if self._humanoid and self._jumpPower then
        self._humanoid.JumpPower = self._jumpPower
    end
end

function MovementEngine:_getCharacterPosition(): Vector3?
    if self:_refreshReferences() and self._rootPart then
        return self._rootPart.Position
    end
    return nil
end

function MovementEngine:_getTargetPosition(waypoint: WaypointData): Vector3
    -- For movement, always target the position (we handle jumping separately)
    return waypoint.position
end

function MovementEngine:_shouldJump(waypoint: WaypointData): boolean
    return waypoint.action == Enum.PathWaypointAction.Jump
end

function MovementEngine:_checkLineOfSight(from: Vector3, to: Vector3): boolean
    if not self._losCheckEnabled then
        return false -- If LOS disabled, always use path following
    end
    
    local params = self._losRaycastParams
    if not params then
        params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.RespectCanCollide = true
    end
    
    -- Exclude character from raycast
    local excludeList = {}
    if self._character then
        table.insert(excludeList, self._character)
    end
    
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.FilterDescendantsInstances = excludeList
    rayParams.RespectCanCollide = true
    
    local direction = to - from
    local result = workspace:Raycast(from, direction, rayParams)
    
    -- If nothing was hit, target is in line of sight
    return result == nil
end

function MovementEngine:_canSkipWaypoint(fromPos: Vector3, waypoint: WaypointData, goalPos: Vector3): boolean
    -- Only skip non-jump waypoints that have clear line of sight
    if waypoint.action == Enum.PathWaypointAction.Jump then
        return false
    end
    
    return self:_checkLineOfSight(fromPos, waypoint.position)
end

function MovementEngine:_turnToFace(targetPos: Vector3, dt: number)
    if not self._rootPart or not self._rootPart.Parent then return end
    
    local currentPos = self._rootPart.Position
    local direction = (targetPos - currentPos) * Vector3.new(1, 0, 1) -- Flatten to horizontal
    
    if direction.Magnitude < 0.01 then return end
    
    local targetCF = CFrame.lookAt(currentPos, currentPos + direction)
    local currentCF = self._rootPart.CFrame
    
    -- Smooth rotation using actual delta time
    local alpha = math.min(1, self._turnSpeed * dt)
    self._rootPart.CFrame = currentCF:Lerp(targetCF, alpha)
end

function MovementEngine:StartMoving(waypoints: { WaypointData }, targetPosition: Vector3)
    if not self:_isCharacterValid() then return end
    
    self:_applyMoveSpeed()
    self:_applyJumpPower()
    
    self._state.waypoints = waypoints
    self._state.currentWaypointIndex = 1
    self._state.isMoving = true
    self._state.isPaused = false
    self._state.targetPosition = targetPosition
    self._state.lastPosition = self._rootPart.Position
    
    -- Start the movement loop
    self:_startMovementLoop()
end

function MovementEngine:_startMovementLoop()
    if self._connection then
        self._connection:Disconnect()
    end
    
    -- Track which waypoint we've issued MoveTo for to avoid restarting every frame
    (self :: any)._activeMoveToIndex = 0
    
    self._connection = game:GetService("RunService").Heartbeat:Connect(function(dt: number)
        if not self._state.isMoving or self._state.isPaused then
            return
        end
        
        if not self:_isCharacterValid() then
            self:Stop()
            if self._onPathCompleted then
                self._onPathCompleted(false)
            end
            return
        end
        
        local currentPos = self._rootPart.Position
        self._state.lastPosition = currentPos
        
        local waypointIndex = self._state.currentWaypointIndex
        local waypoints = self._state.waypoints
        
        if waypointIndex > #waypoints then
            -- Reached the end of the path
            self:Stop()
            if self._onPathCompleted then
                self._onPathCompleted(true)
            end
            return
        end
        
        local currentWaypoint = waypoints[waypointIndex]
        local waypointPos = currentWaypoint.position
        
        -- Check if we've reached this waypoint
        local distToWaypoint = (currentPos - waypointPos).Magnitude
        
        if distToWaypoint <= self._reachDistance then
            -- Reached waypoint
            if self._onReachWaypoint then
                self._onReachWaypoint(waypointIndex, currentWaypoint)
            end
            
            -- Move to next waypoint
            self._state.currentWaypointIndex = waypointIndex + 1
            self._activeMoveToIndex = 0 -- Reset so next waypoint issues a new MoveTo
            
            -- Check for line-of-sight optimization on next waypoints
            if self._losCheckEnabled and self._state.targetPosition then
                self:_trySkipWaypoints(currentPos)
            end
        else
            -- Only issue MoveTo once per waypoint to avoid jitter
            if self._activeMoveToIndex ~= waypointIndex then
                self._activeMoveToIndex = waypointIndex
                
                -- Handle jumping
                if self:_shouldJump(currentWaypoint) and self._humanoid then
                    self._humanoid.Jump = true
                end
                
                -- Turn to face waypoint
                self:_turnToFace(waypointPos, dt)
                
                -- Issue single MoveTo call
                if self._humanoid then
                    self._humanoid:MoveTo(waypointPos)
                end
            else
                -- Continue smooth turning towards the waypoint
                self:_turnToFace(waypointPos, dt)
            end
        end
    end)
end

function MovementEngine:_trySkipWaypoints(currentPos: Vector3)
    local startIndex = self._state.currentWaypointIndex
    local targetPos = self._state.targetPosition
    
    -- Try to skip ahead by checking line of sight to further waypoints
    for i = startIndex, math.min(startIndex + 3, #self._state.waypoints) do
        local wp = self._state.waypoints[i]
        if wp.action == Enum.PathWaypointAction.Jump then
            break -- Don't skip jump waypoints
        end
        
        if targetPos and self:_canSkipWaypoints(currentPos, wp, targetPos) then
            -- Check if we can see past this waypoint to the target or next few
            self._state.currentWaypointIndex = i + 1
        else
            break
        end
    end
end

function MovementEngine:Stop()
    self._state.isMoving = false
    self._state.isPaused = false
    
    if self._connection then
        self._connection:Disconnect()
        self._connection = nil
    end
    
    if self._humanoid and self._humanoid.Parent then
        self._humanoid:MoveTo(self._rootPart.Position)
    end
end

function MovementEngine:Pause()
    self._state.isPaused = true
end

function MovementEngine:Resume()
    self._state.isPaused = false
end

function MovementEngine:IsMoving(): boolean
    return self._state.isMoving and not self._state.isPaused
end

function MovementEngine:GetState(): MovementState
    return self._state
end

function MovementEngine:GetProgress(): number
    if #self._state.waypoints == 0 then return 0 end
    return self._state.currentWaypointIndex / #self._state.waypoints
end

function MovementEngine:Destroy()
    self:Stop()
    self:SetCharacter(nil)
end

return MovementEngine
