--[[
    Pathfind Library - Movement Engine
    
    Handles smooth waypoint following, line-of-sight optimization,
    automatic jump handling, and natural movement.
    
    Never changes WalkSpeed or JumpPower unless explicitly configured.
    Uses lookahead for smooth cornering.
    
    @author SairyTheKing
    @version 1.3.0
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
    _smoothMovement: boolean,
    _smoothSegments: number,
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
    smoothMovement: boolean?,
    smoothSegments: number?,
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
    self._smoothMovement = config.smoothMovement ~= false
    self._smoothSegments = config.smoothSegments or 4
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

function MovementEngine:_catmullRom(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: number): Vector3
    local t2 = t * t
    local t3 = t2 * t
    return 0.5 * ((2 * p1) +
        (-p0 + p2) * t +
        (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 +
        (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
end

function MovementEngine:_generateSmoothWaypoints(waypoints: { WaypointData }): { WaypointData }
    if #waypoints < 3 then return waypoints end
    
    local smooth = {}
    local segs = self._smoothSegments or 4
    
    table.insert(smooth, waypoints[1])
    
    for i = 2, #waypoints do
        local p0 = waypoints[math.max(1, i - 2)].position
        local p1 = waypoints[math.max(1, i - 1)].position
        local p2 = waypoints[i].position
        local p3 = waypoints[math.min(#waypoints, i + 1)].position
        
        -- Skip interpolation for jump waypoints — keep them sharp
        if waypoints[i].action == Enum.PathWaypointAction.Jump
            or waypoints[i - 1].action == Enum.PathWaypointAction.Jump then
            table.insert(smooth, waypoints[i])
        else
            for s = 1, segs do
                local t = s / segs
                local pos = self:_catmullRom(p0, p1, p2, p3, t)
                table.insert(smooth, {
                    position = pos,
                    action = Enum.PathWaypointAction.Walk,
                    index = #smooth + 1,
                })
            end
        end
    end
    
    return #smooth > 0 and smooth or waypoints
end

function MovementEngine:_getLookaheadPosition(currentIndex: number): Vector3?
    local waypoints = self._state.waypoints
    local targetIndex = math.min(currentIndex + self._lookAhead, #waypoints)
    
    -- Find a good lookahead target, skipping jump waypoints for smooth turning
    for i = currentIndex, targetIndex do
        local wp = waypoints[i]
        if wp and wp.action == Enum.PathWaypointAction.Jump then
            return wp.position
        end
    end
    
    if targetIndex <= #waypoints then
        return waypoints[targetIndex].position
    end
    return waypoints[currentIndex].position
end

function MovementEngine:_turnToFace(targetPos: Vector3, dt: number)
    if not self._rootPart or not self._rootPart.Parent then return end
    
    local rp = self._rootPart.Position
    local dx = targetPos.X - rp.X
    local dz = targetPos.Z - rp.Z
    if dx * dx + dz * dz < 0.0001 then return end -- skip sqrt
    
    local targetCF = CFrame.lookAt(rp, rp + Vector3.new(dx, 0, dz))
    local alpha = self._turnSpeed * dt
    if alpha >= 1 then
        self._rootPart.CFrame = targetCF
    else
        self._rootPart.CFrame = self._rootPart.CFrame:Lerp(targetCF, alpha)
    end
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
    
    -- Apply Catmull-Rom smoothing when enabled
    local finalWaypoints = self._smoothMovement and self:_generateSmoothWaypoints(waypoints) or waypoints
    self._state.waypoints = finalWaypoints
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
        local wpsLen = #waypoints
        
        if waypointIndex > wpsLen then
            self:Stop()
            if self._onPathCompleted then
                self._onPathCompleted(true)
            end
            return
        end
        
        local currentWaypoint = waypoints[waypointIndex]
        local wpPos = currentWaypoint.position
        local dx = currentPos.X - wpPos.X
        local dy = currentPos.Y - wpPos.Y
        local dz = currentPos.Z - wpPos.Z
        local distSq = dx * dx + dy * dy + dz * dz
        local reachSq = self._reachDistance * self._reachDistance
        
        if distSq <= reachSq then
            if self._onReachWaypoint then
                self._onReachWaypoint(waypointIndex, currentWaypoint)
            end
            self._state.currentWaypointIndex = waypointIndex + 1
            self._activeMoveToIndex = 0
            -- Skip LOS for short paths (< 5 waypoints)
            if self._losCheckEnabled and self._state.targetPosition and wpsLen >= 5 then
                self:_trySkipWaypoints(currentPos)
            end
        else
            local lookTarget = self:_getLookaheadPosition(waypointIndex)
            if not lookTarget then lookTarget = wpPos end
            
            if self._activeMoveToIndex ~= waypointIndex then
                self._activeMoveToIndex = waypointIndex
                
                if currentWaypoint.action == Enum.PathWaypointAction.Jump and self._humanoid then
                    self._humanoid.Jump = true
                end
                
                self:_turnToFace(lookTarget, dt)
                
                if self._humanoid then
                    self._humanoid:MoveTo(wpPos)
                end
            else
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
