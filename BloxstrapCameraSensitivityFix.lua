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

-- Patch 0: robust Camera Sensitivity.
-- Rebinds every CameraInput module and reapplies after PlayerScripts/camera changes.
local cameraStartMarker = "pcall(function()\nlocal camerascript"
local cameraEndMarker = "\nlocal funnycon"
local cameraStartPos = string.find(source, cameraStartMarker, 1, true)
local cameraEndPos = cameraStartPos and string.find(source, cameraEndMarker, cameraStartPos, true)

if not cameraStartPos or not cameraEndPos then
    error("Camera Sensitivity block not found. Bloxstrap was probably updated.")
end

local cameraPatched = [=[
local __BloxstrapSensitivityState = getgenv().__BloxstrapCameraSensitivityFix
if type(__BloxstrapSensitivityState) ~= "table" then
    __BloxstrapSensitivityState = {
        value = tonumber(Bloxstrap.Config.CameraSensitivity) or 1,
        modules = setmetatable({}, {__mode = "k"}),
        running = false
    }
    getgenv().__BloxstrapCameraSensitivityFix = __BloxstrapSensitivityState
end

__BloxstrapSensitivityState.value = tonumber(Bloxstrap.Config.CameraSensitivity)
    or __BloxstrapSensitivityState.value or 1

local function __applyBloxstrapCameraSensitivity()
    local playerScripts = lplr:FindFirstChild("PlayerScripts")
    if not playerScripts then return end

    for _, cameraInputModule in ipairs(playerScripts:GetDescendants()) do
        if cameraInputModule:IsA("ModuleScript") and cameraInputModule.Name == "CameraInput" then
            local ok, cameraInput = pcall(require, cameraInputModule)
            if ok and type(cameraInput) == "table" and type(cameraInput.getRotation) == "function" then
                local entry = __BloxstrapSensitivityState.modules[cameraInputModule]
                if not entry then
                    entry = {}
                    __BloxstrapSensitivityState.modules[cameraInputModule] = entry
                end

                if cameraInput.getRotation ~= entry.wrapper then
                    -- If Roblox/Evade replaced the function, use the new original.
                    entry.original = cameraInput.getRotation
                    local original = entry.original
                    local state = __BloxstrapSensitivityState

                    entry.wrapper = function(...)
                        local packed = table.pack(original(...))
                        if typeof(packed[1]) == "Vector2" then
                            packed[1] = packed[1] * (tonumber(state.value) or 1)
                        end
                        return table.unpack(packed, 1, packed.n)
                    end

                    cameraInput.getRotation = entry.wrapper
                end
            end
        end
    end
end

local function __scheduleBloxstrapCameraSensitivity()
    task.defer(function()
        task.wait()
        pcall(__applyBloxstrapCameraSensitivity)
    end)
end

local camsensitivity = Appearance:AddSlider({
    Name = "Camera Sensitivity",
    Min = 1,
    Max = 7,
    Increase = 0.1,
    Default = tonumber(Bloxstrap.Config.CameraSensitivity) or 1,
    Callback = function(val)
        local number = tonumber(val) or 1
        __BloxstrapSensitivityState.value = number
        Bloxstrap.UpdateConfig("CameraSensitivity", number)
        pcall(function()
            Bloxstrap.SaveConfig()
        end)
        __scheduleBloxstrapCameraSensitivity()
    end
})

-- Apply saved value immediately; don't wait for the user to move the slider.
pcall(__applyBloxstrapCameraSensitivity)

local __playerScripts = lplr:FindFirstChild("PlayerScripts")
if __playerScripts then
    __playerScripts.DescendantAdded:Connect(function(obj)
        if obj:IsA("ModuleScript") and obj.Name == "CameraInput" then
            __scheduleBloxstrapCameraSensitivity()
        end
    end)
end

lplr.CharacterAdded:Connect(__scheduleBloxstrapCameraSensitivity)

if not __BloxstrapSensitivityState.running then
    __BloxstrapSensitivityState.running = true
    task.spawn(function()
        while task.wait(0.75) do
            if not lplr.Parent then break end
            pcall(__applyBloxstrapCameraSensitivity)
        end
        __BloxstrapSensitivityState.running = false
    end)
end
]=]

source = string.sub(source, 1, cameraStartPos - 1)
    .. cameraPatched
    .. string.sub(source, cameraEndPos)

-- Patch 1: GUIScaler continua abaixo de 0.50, mas com passos menores depois disso.
local scaleStartMarker = "local funnycon\nlocal guisets = {}"
local scaleEndMarker = "local touchuuval = 1.2"

local scaleStartPos = string.find(source, scaleStartMarker, 1, true)
local scaleEndPos = scaleStartPos and string.find(source, scaleEndMarker, scaleStartPos, true)

if not scaleStartPos or not scaleEndPos then
    error("GUIScaler block not found. Bloxstrap was probably updated.")
end

local scalePatched = [=[
local funnycon

local MIN_SCALE = tonumber(getgenv().BloxstrapMinScale) or 0.01
if MIN_SCALE < 0 then
    MIN_SCALE = 0.01
end

local function nextScale(current)
    current = tonumber(current) or 1

    -- Mantem o comportamento conhecido nas duas primeiras reducoes:
    -- 1.00 -> 0.75 -> 0.50
    -- Depois desce mais suave, parecido com o video:
    -- 0.50 -> 0.40 -> 0.30 -> 0.20 -> 0.10 -> 0.05 -> 0.01
    if current > 0.75 then
        return 0.75
    elseif current > 0.50 then
        return 0.50
    elseif current > 0.40 then
        return 0.40
    elseif current > 0.30 then
        return 0.30
    elseif current > 0.20 then
        return 0.20
    elseif current > 0.10 then
        return 0.10
    elseif current > 0.05 then
        return 0.05
    end

    return MIN_SCALE
end

local function scalePlayerGui(v)
    if not v or v.Name == "TouchGui" then
        return
    end

    local oldui = v:FindFirstChildWhichIsA("UIScale", true)

    if oldui then
        oldui.Scale = nextScale(oldui.Scale)
    else
        local uiscale = Instance.new("UIScale")
        uiscale.Name = "__BloxstrapUnlimitedScale"
        uiscale.Scale = 0.75
        uiscale.Parent = v
    end
end

local function disconnectScaler()
    pcall(function()
        if funnycon then
            funnycon:Disconnect()
            funnycon = nil
        end
    end)
end

local function applyScalePass()
    for _, v in ipairs(lplr.PlayerGui:GetChildren()) do
        scalePlayerGui(v)
    end
end

local guiscale = Appearance:AddToggle({
    Name = "GUIScaler",
    Description = "1.00 -> 0.75 -> 0.50 -> 0.40 -> 0.30 -> 0.20 -> 0.10...",
    Default = Bloxstrap.Config.GUIScale,
    Callback = function(call)
        Bloxstrap.UpdateConfig("GUIScale", call)

        if call then
            disconnectScaler()
            applyScalePass()

            funnycon = lplr.PlayerGui.ChildAdded:Connect(function(v)
                task.defer(function()
                    scalePlayerGui(v)
                end)
            end)
        else
            -- Nao restaura: ligar de novo aplica o proximo passo.
            disconnectScaler()
        end
    end
})

]=]

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
