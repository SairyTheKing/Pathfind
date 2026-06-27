--[[
    Pathfind Library - Debug Visualization
    
    Draws waypoints, path lines, and debug text for development.
    Only active when debug mode is enabled.
    
    @author Pathfind Contributors
    @version 1.2.0
    @license MIT
]]

local Debug = {}
Debug.__index = Debug

local DEBUG_PREFIX = "PathfindDebug_"

export type Debug = typeof(setmetatable({} :: {
    _enabled: boolean,
    _folder: Folder?,
    _waypoints: { Part },
    _labels: { BillboardGui },
    _lines: { Part },
}, Debug))

function Debug.new(): Debug
    local self = setmetatable({}, Debug)
    self._enabled = false
    self._folder = nil
    self._waypoints = {}
    self._labels = {}
    self._lines = {}
    return self
end

function Debug:SetEnabled(enabled: boolean)
    self._enabled = enabled
    if not enabled then
        self:Clear()
    end
end

function Debug:_ensureFolder(): Folder
    if self._folder and self._folder.Parent then
        return self._folder
    end
    
    self._folder = Instance.new("Folder")
    self._folder.Name = DEBUG_PREFIX .. tostring(game:GetService("HttpService"):GenerateGUID(false))
    self._folder.Parent = workspace
    return self._folder
end

function Debug:_createWaypointMarker(position: Vector3, color: Color3, label: string?): Part
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

function Debug:_createLine(from: Vector3, to: Vector3, color: Color3): Part
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

function Debug:DrawWaypoints(
    waypoints: { { position: Vector3, action: Enum.PathWaypointAction? } },
    color: Color3,
    lineColor: Color3?
)
    if not self._enabled then return end
    
    local lineCol = lineColor or Color3.new(1, 1, 0) -- Yellow default
    
    for i, wp in waypoints do
        local wpColor = color
        if wp.action == Enum.PathWaypointAction.Jump then
            wpColor = Color3.new(0, 1, 0) -- Green for jump waypoints
        end
        
        self:_createWaypointMarker(wp.position, wpColor, tostring(i))
        
        -- Draw line between consecutive waypoints
        if i > 1 and lineColor ~= false then
            local prevPos = waypoints[i - 1].position
            self:_createLine(prevPos, wp.position, lineCol)
        end
    end
end

function Debug:DrawCurrentWaypoint(position: Vector3, color: Color3)
    if not self._enabled then return end
    self:_createWaypointMarker(position, color or Color3.new(0, 1, 1), "►")
end

function Debug:DrawBlocked(position: Vector3)
    if not self._enabled then return end
    self:_createWaypointMarker(position, Color3.new(1, 0, 0), "✕")
end

function Debug:Log(message: string, level: string?)
    if not self._enabled then return end
    
    local prefix = "[Pathfind"
    if level then
        prefix ..= ":" .. level
    end
    prefix ..= "]"
    
    print(prefix, message)
end

function Debug:Clear()
    -- Clear waypoint markers
    for _, wp in self._waypoints do
        if wp and wp.Parent then
            wp:Destroy()
        end
    end
    table.clear(self._waypoints)
    
    -- Clear labels
    for _, label in self._labels do
        if label and label.Parent then
            label:Destroy()
        end
    end
    table.clear(self._labels)
    
    -- Clear lines
    for _, line in self._lines do
        if line and line.Parent then
            line:Destroy()
        end
    end
    table.clear(self._lines)
end

function Debug:Destroy()
    self:Clear()
    if self._folder and self._folder.Parent then
        self._folder:Destroy()
    end
end

return Debug
