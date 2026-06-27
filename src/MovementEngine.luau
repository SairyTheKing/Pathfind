--[[
    Pathfind Library - Movement Engine
    
    Handles smooth waypoint following, line-of-sight optimization,
    automatic jump handling, and natural movement.
    
    Never changes WalkSpeed or JumpPower unless explicitly configured.
    Uses lookahead for smooth cornering.
    
    @author Pathfind Contributors
    @version 1.1.0
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
    _lookAhead: number,
    _losCheckEnabled: boolean,
    _losRaycastParams: RaycastParams?,
    _state: MovementState,
    _connection: RBXScriptConnection?,
    _onReachWaypoint: ((index: number, waypoint: WaypointData) -> ())?,
    _onPathCompleted: ((success: boolean) -> ())?,
    _activeMoveToIndex: number,
    _losRaycastCache: RaycastParams?,
}, MovementEngine))

function MovementEngine.new(config: {
    turnSpeed: number?,
    reachDistance: number?,
    moveSpeed: number?,
    jumpPower: number?,
    lookAhead: number?,
    losCheckEnabled: boolean?,
    losRaycastParams: RaycastParams?,
}?): MovementEngine
    local self = setmetatable({}, MovementEngine)
    
    config = config or {}
    self._turnSpeed = config.turnSpeed or 16
    self._reachDistance = config.reachDistance or 2.5
    self._moveSpeed = config.moveSpeed
    self._jumpPower = config.jumpPower
    self._lookAhead = config.lookAhead or 1
    self._losCheckEnabled = config.losCheckEnabled ~= false
    self._losRaycastParams = config.losRaycastParams
    self._character = nil
    self._humanoid = nil
    self._rootPart = nil
    self._connection = nil
    self._onReachWaypoint = nil
    self._onPathCompleted = nil
    self._activeMoveToIndex = 0
    self._losRaycastCache = nil
    
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
    self._losRaycastCache = nil
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

function MovementEngine:_getCharacterPosition(): Vector3?
    if self._rootPart and self._rootPart.Parent then
        return self._rootPart.Position
    end
    if self:_refreshReferences() and self._rootPart then
        return self._rootPart.Position
    end
    return nil
end

function MovementEngine:_getLookaheadPosition(currentIndex: number): Vector3?
    local waypoints = self._state.waypoints
    local targetIndex = math.min(currentIndex + self._lookAhead, #waypoints)
    
    -- Find a good lookahead target, skipping jump waypoints for smooth turning
    for i = currentIndex, targetIndex do
        local wp = waypoints[i]
        if wp and wp.action == Enum.PathWaypointAction.Jump then
            -- If we hit a jump waypoint, aim at it directly
            return wp.position
        end
    end
    
    -- Use the lookahead waypoint position
    if targetIndex <= #waypoints then
        return waypoints[targetIndex].position
    end
    return waypoints[currentIndex].position
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

function MovementEngine:_getRaycastParams(): RaycastParams
    if self._losRaycastCache then
        return self._losRaycastCache
    end
    
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.RespectCanCollide = true
    
    if self._character then
        params.FilterDescendantsInstances = { self._character }
    end
    
    self._losRaycastCache = params
    return params
end

function MovementEngine:_checkLineOfSight(from: Vector3, to: Vector3): boolean
    if not self._losCheckEnabled then
        return false
    end
    
    if self._losRaycastParams then
        local result = workspace:Raycast(from, to - from, self._losRaycastParams)
        return result == nil
    end
    
    local params = self:_getRaycastParams()
    local direction = to - from
    local result = workspace:Raycast(from, direction, params)
    
    return result == nil
end

function MovementEngine:_trySkipWaypoints(currentPos: Vector3)
    local startIndex = self._state.currentWaypointIndex
    local targetPos = self._state.targetPosition
    local maxSkip = math.min(startIndex + 3, #self._state.waypoints)
    
    for i = startIndex, maxSkip do
        local wp = self._state.waypoints[i]
        if not wp then break end
        
        if wp.action == Enum.PathWaypointAction.Jump then
            break
        end
        
        if targetPos and self:_checkLineOfSight(currentPos, wp.position) then
            self._state.currentWaypointIndex = i + 1
        else
            break
        end
    end
end

function MovementEngine:StartMoving(waypoints: { WaypointData }, targetPosition: Vector3)
    if not self:_isCharacterValid() then return end
    
    -- Only override speed/power if explicitly configured
    if self._moveSpeed and self._humanoid then
        self._humanoid.WalkSpeed = self._moveSpeed
    end
    if self._jumpPower and self._humanoid then
        self._humanoid.JumpPower = self._jumpPower
    end
    
    self._state.waypoints = waypoints
    self._state.currentWaypointIndex = 1
    self._state.isMoving = true
    self._state.isPaused = false
    self._state.targetPosition = targetPosition
    self._state.lastPosition = self._rootPart.Position
    self._activeMoveToIndex = 0
    
    -- Invalidate LOS cache
    self._losRaycastCache = nil
    
    self:_startMovementLoop()
end

function MovementEngine:_startMovementLoop()
    if self._connection then
        self._connection:Disconnect()
    end
    
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
        
        -- Check if we've completed the entire path
        if waypointIndex > #waypoints then
            self:Stop()
            if self._onPathCompleted then
                self._onPathCompleted(true)
            end
            return
        end
        
        local currentWaypoint = waypoints[waypointIndex]
        local waypointPos = currentWaypoint.position
        local distToWaypoint = (currentPos - waypointPos).Magnitude
        
        if distToWaypoint <= self._reachDistance then
            -- Reached waypoint
            if self._onReachWaypoint then
                self._onReachWaypoint(waypointIndex, currentWaypoint)
            end
            
            -- Advance to next waypoint
            self._state.currentWaypointIndex = waypointIndex + 1
            self._activeMoveToIndex = 0
            
            -- LOS skip optimization
            if self._losCheckEnabled and self._state.targetPosition then
                self:_trySkipWaypoints(currentPos)
            end
        else
            -- Get the lookahead target for smooth turning
            local lookTarget = self:_getLookaheadPosition(waypointIndex)
            if not lookTarget then lookTarget = waypointPos end
            
            -- Only issue MoveTo once per waypoint to avoid jitter
            if self._activeMoveToIndex ~= waypointIndex then
                self._activeMoveToIndex = waypointIndex
                
                -- Handle jumping
                if currentWaypoint.action == Enum.PathWaypointAction.Jump and self._humanoid then
                    self._humanoid.Jump = true
                end
                
                -- Turn toward lookahead target for smoother cornering
                self:_turnToFace(lookTarget, dt)
                
                -- Issue single MoveTo call
                if self._humanoid then
                    self._humanoid:MoveTo(waypointPos)
                end
            else
                -- Continue smooth turning
                self:_turnToFace(lookTarget, dt)
            end
        end
    end)
end

function MovementEngine:Stop()
    self._state.isMoving = false
    self._state.isPaused = false
    
    if self._connection then
        self._connection:Disconnect()
        self._connection = nil
    end
    
    if self._humanoid and self._humanoid.Parent and self._rootPart then
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
