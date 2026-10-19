local RAW = "https://raw.githubusercontent.com/new-qwertyui/Bloxstrap/main/"
local API = "https://api.github.com/repos/new-qwertyui/Bloxstrap/contents/"
local hidegui = getgenv().hideui or false

local cloneref = cloneref or function(...)
    return ...
end

local HttpService = cloneref(game:GetService("HttpService"))

local function noCache(url)
    local separator = string.find(url, "?", 1, true) and "&" or "?"
    return url .. separator .. "_cb=" .. HttpService:GenerateGUID(false)
end

local function mkdir(path)
    if makefolder and not isfolder(path) then
        pcall(makefolder, path)
    end
end

mkdir("Bloxstrap")
mkdir("Bloxstrap/Main")
mkdir("Bloxstrap/Main/Functions")
mkdir("Bloxstrap/Main/Configs")
mkdir("Bloxstrap/Main/Fonts")
mkdir("Bloxstrap/Images")

local function installMissing()
    if not isfile("Bloxstrap/Main/Functions/GuiLibrary.lua") then
        local list = HttpService:JSONDecode(
            game:HttpGet(noCache(API .. "Main/Functions"), true)
        )

        for _, v in ipairs(list) do
            if v.name and v.name:find("%.lua$") then
                writefile(
                    "Bloxstrap/Main/Functions/" .. v.name,
                    "return loadstring(game:HttpGet('" .. RAW .. "Main/Functions/" .. v.name .. "?_cb=' .. game:GetService('HttpService'):GenerateGUID(false), true))()"
                )
            end
        end
    end

    if not isfile("Bloxstrap/Main/Configs/Default.json") then
        writefile("Bloxstrap/Main/Configs/Default.json", "{}")
    end
end

installMissing()

local source = game:HttpGet(
    noCache(RAW .. "Main/Bloxstrap.lua"),
    true
)

-- Patch 1: GUIScaler corrige o alvo: UIScale vai em GuiObjects, nao em ScreenGui.
local scaleStartMarker = "local funnycon\nlocal guisets = {}"
local scaleEndMarker = "local touchuuval = 1.2"
local scaleStartPos = string.find(source, scaleStartMarker, 1, true)
local scaleEndPos = scaleStartPos and string.find(source, scaleEndMarker, scaleStartPos, true)
if not scaleStartPos or not scaleEndPos then
    error("GUIScaler block not found. Bloxstrap was probably updated.")
end

local scalePatched = [==[
local funnycon
local guisets = {}
local excludedNames = {
    TouchGui = true, TouchControlFrame = true, DynamicThumbstick = true,
    ThumbstickFrame = true, JumpButton = true, BloxstrapCrosshair = true,
    PerfectUIManager_UI = true, PerfectUIManager_Shield = true, Bloxstrap = true
}
local function isExcluded(obj)
    local current = obj
    while current and current ~= lplr.PlayerGui do
        if excludedNames[current.Name] then return true end
        current = current.Parent
    end
    local name = string.lower(obj.Name)
    return string.find(name, "thumbstick", 1, true) ~= nil
        or string.find(name, "jumpbutton", 1, true) ~= nil
        or string.find(name, "touchcontrol", 1, true) ~= nil
end

-- Target clickable controls themselves, not their full-screen/container parents.
-- UIScale then shrinks each button around its own center instead of pulling an
-- entire layout toward a ScreenGui corner.
local function getTargets()
    local targets, seen = {}, {}
    for _, obj in ipairs(lplr.PlayerGui:GetDescendants()) do
        if (obj:IsA("ImageButton") or obj:IsA("TextButton"))
            and not isExcluded(obj) and not seen[obj] then
            seen[obj] = true
            table.insert(targets, obj)
        end
    end
    return targets
end

local function scaleTarget(obj)
    if not obj or not obj.Parent or isExcluded(obj) then return end
    for _, entry in ipairs(guisets) do
        if entry.target == obj then return end
    end
    local oldui = obj:FindFirstChildWhichIsA("UIScale")
    if oldui then
        table.insert(guisets, {target = obj, oldscale = oldui.Scale, scaler = oldui})
        oldui.Scale = math.min(oldui.Scale, 0.7)
    else
        local uiscale = Instance.new("UIScale")
        uiscale.Name = "__BloxstrapButtonScale"
        uiscale.Scale = 0.7
        uiscale.Parent = obj
        table.insert(guisets, {target = obj, oldscale = 9e9, scaler = uiscale})
    end
end

local function applyToCurrentTargets()
    for _, obj in ipairs(getTargets()) do scaleTarget(obj) end
end

local guiscale = Appearance:AddToggle({
    Name = "GUIScaler",
    Description = "Decrease button scales without moving their centers",
    Default = Bloxstrap.Config.GUIScale,
    Callback = function(call)
        Bloxstrap.UpdateConfig("GUIScale", call)
        if call then
            if funnycon then pcall(function() funnycon:Disconnect() end) end
            table.clear(guisets)
            applyToCurrentTargets()
            funnycon = lplr.PlayerGui.DescendantAdded:Connect(function(obj)
                if (obj:IsA("ImageButton") or obj:IsA("TextButton")) and not isExcluded(obj) then
                    task.defer(function()
                        if obj.Parent and not isExcluded(obj) then scaleTarget(obj) end
                    end)
                end
            end)
        else
            pcall(function() if funnycon then funnycon:Disconnect(); funnycon = nil end end)
            for _, v in ipairs(guisets) do
                if v.oldscale == 9e9 then
                    if v.scaler and v.scaler.Parent then v.scaler:Destroy() end
                elseif v.scaler and v.scaler.Parent then
                    v.scaler.Scale = v.oldscale
                end
            end
            table.clear(guisets)
        end
    end
})

]==]

source = string.sub(source, 1, scaleStartPos - 1)
    .. scalePatched
    .. string.sub(source, scaleEndPos)

local chunk, err = loadstring(
    source,
    "Bloxstrap Smooth GUI Scale + Tiny Dot Crosshair"
)

if not chunk then
    error(err)
end

local Bloxstrap = chunk()

Bloxstrap.start()
Bloxstrap.Visible(not hidegui)
