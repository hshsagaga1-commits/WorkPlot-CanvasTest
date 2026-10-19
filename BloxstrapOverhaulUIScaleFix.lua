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


source = string.sub(source, 1, scaleStartPos - 1)
    .. scalePatched
    .. string.sub(source, scaleEndPos)

-- Patch 2: Crosshair mobile-safe.
-- Usa imagem customizada se funcionar; sem imagem usa um ponto branco minúsculo.
local crossStartMarker = "local chosenimage = ''"
local crossEndMarker = "Appearance:AddSection('Customizations')"

local crossStartPos = string.find(source, crossStartMarker, 1, true)
local crossEndPos = crossStartPos and string.find(source, crossEndMarker, crossStartPos, true)

if not crossStartPos or not crossEndPos then
    error("Crosshair block not found. Bloxstrap was probably updated.")
end

local crossPatched = [=[
local chosenimage = ''
local crosshairRoot
local crosshairImage
local fallbackDot

local guiParent = game:GetService("CoreGui")
pcall(function()
    if gethui then
        guiParent = gethui()
    end
end)

pcall(function()
    local old = guiParent:FindFirstChild("BloxstrapCrosshair")
    if old then
        old:Destroy()
    end
end)

local screengui = Instance.new("ScreenGui")
screengui.Name = "BloxstrapCrosshair"
screengui.IgnoreGuiInset = true
screengui.ResetOnSpawn = false
screengui.DisplayOrder = 999999
screengui.Enabled = false
screengui.Parent = guiParent

local function makeCircle(frame)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(1, 0)
    corner.Parent = frame
end

local function ensureCrosshair()
    if crosshairRoot and crosshairRoot.Parent then
        return
    end

    crosshairRoot = Instance.new("Frame")
    crosshairRoot.Name = "CrosshairRoot"
    crosshairRoot.AnchorPoint = Vector2.new(0.5, 0.5)
    crosshairRoot.Position = UDim2.new(0.5, 0, 0.5, 0)
    crosshairRoot.Size = UDim2.new(0, 8, 0, 8)
    crosshairRoot.BackgroundTransparency = 1
    crosshairRoot.ZIndex = 100
    crosshairRoot.Parent = screengui

    crosshairImage = Instance.new("ImageLabel")
    crosshairImage.Name = "CustomImage"
    crosshairImage.AnchorPoint = Vector2.new(0.5, 0.5)
    crosshairImage.Position = UDim2.fromScale(0.5, 0.5)
    crosshairImage.Size = UDim2.new(0, 8, 0, 8)
    crosshairImage.BackgroundTransparency = 1
    crosshairImage.ZIndex = 102
    crosshairImage.Parent = crosshairRoot

    fallbackDot = Instance.new("Frame")
    fallbackDot.Name = "Dot"
    fallbackDot.AnchorPoint = Vector2.new(0.5, 0.5)
    fallbackDot.Position = UDim2.fromScale(0.5, 0.5)
    fallbackDot.Size = UDim2.new(0, 2, 0, 2)
    fallbackDot.BorderSizePixel = 0
    fallbackDot.BackgroundColor3 = Color3.new(1, 1, 1)
    fallbackDot.ZIndex = 101
    fallbackDot.Parent = crosshairRoot
    makeCircle(fallbackDot)
end

local function refreshCrosshairVisual()
    ensureCrosshair()

    local hasImage = type(chosenimage) == "string" and chosenimage ~= ""
    crosshairImage.Image = hasImage and chosenimage or ""
    crosshairImage.Visible = hasImage
    fallbackDot.Visible = not hasImage
end

local function tryLoadCrosshairAsset(path)
    if type(path) ~= "string" or path == "" then
        return ""
    end

    local assetFn = getcustomasset or getsynasset
    if not assetFn then
        return ""
    end

    local ok, asset = pcall(assetFn, path)
    if ok and type(asset) == "string" then
        return asset
    end

    return ""
end

pcall(function()
    if Bloxstrap.Config.CrosshairImage and Bloxstrap.Config.CrosshairImage ~= "" then
        chosenimage = tryLoadCrosshairAsset(Bloxstrap.Config.CrosshairImage)
    end
end)

refreshCrosshairVisual()

local crosshair = Appearance:AddToggle({
    Name = "Crosshair",
    Description = "Tiny centered dot, mobile-safe",
    Default = Bloxstrap.Config.Crosshair,
    Callback = function(call)
        Bloxstrap.UpdateConfig("Crosshair", call)
        refreshCrosshairVisual()
        screengui.Enabled = call and true or false
    end
})

local imageOptions = {}
pcall(function()
    if listfiles then
        imageOptions = listfiles("Bloxstrap/Images")
    end
end)

Appearance:AddDropdown({
    Name = "Image",
    Options = imageOptions,
    Default = Bloxstrap.Config.CrosshairImage,
    Callback = function(val)
        Bloxstrap.UpdateConfig("CrosshairImage", val)
        chosenimage = tryLoadCrosshairAsset(val)
        refreshCrosshairVisual()
    end
})

]=]

source = string.sub(source, 1, crossStartPos - 1)
    .. crossPatched
    .. string.sub(source, crossEndPos)

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
