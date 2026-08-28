--// CAFÉÍNA • BOT READER
--// Interface criada em Luau para Roblox

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

--==================================================
-- CONFIGURAÇÕES
--==================================================

local COLORS = {
    Background = Color3.fromRGB(10, 9, 13),
    Panel = Color3.fromRGB(22, 21, 27),
    Panel2 = Color3.fromRGB(25, 24, 30),

    White = Color3.fromRGB(245, 245, 248),
    Gray = Color3.fromRGB(165, 163, 173),

    Red = Color3.fromRGB(242, 29, 48),
    DarkRed = Color3.fromRGB(128, 18, 31),

    Blue = Color3.fromRGB(18, 38, 75),
    BlueHover = Color3.fromRGB(24, 52, 98),

    Green = Color3.fromRGB(50, 220, 125),
}

--==================================================
-- SCREEN GUI
--==================================================

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "CafeinaBotReader"
ScreenGui.ResetOnSpawn = false
ScreenGui.IgnoreGuiInset = true
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = PlayerGui

--==================================================
-- FUNÇÕES AUXILIARES
--==================================================

local function Corner(parent, radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius)
    corner.Parent = parent
    return corner
end

local function Stroke(parent, color, thickness, transparency)
    local stroke = Instance.new("UIStroke")
    stroke.Color = color
    stroke.Thickness = thickness or 1
    stroke.Transparency = transparency or 0
    stroke.Parent = parent
    return stroke
end

local function CreateText(parent, text, size, font, color)
    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextSize = size
    label.Font = font
    label.TextColor3 = color
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = parent
    return label
end

--==================================================
-- JANELA PRINCIPAL
--==================================================

local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
MainFrame.Position = UDim2.fromScale(0.5, 0.5)
MainFrame.Size = UDim2.fromScale(0.92, 0.90)
MainFrame.BackgroundColor3 = COLORS.Background
MainFrame.BorderSizePixel = 0
MainFrame.Parent = ScreenGui

Corner(MainFrame, 28)
Stroke(MainFrame, Color3.fromRGB(48, 47, 55), 2, 0)

--==================================================
-- HEADER
--==================================================

local Header = Instance.new("Frame")
Header.Name = "Header"
Header.Size = UDim2.new(1, 0, 0.24, 0)
Header.BackgroundColor3 = COLORS.Panel
Header.BorderSizePixel = 0
Header.Parent = MainFrame

Corner(Header, 28)

local Title = CreateText(
    Header,
    "CAFÉÍNA • BOT READER",
    30,
    Enum.Font.GothamBold,
    COLORS.White
)

Title.Position = UDim2.new(0, 42, 0, 30)
Title.Size = UDim2.new(0.65, 0, 0, 40)

local Subtitle = CreateText(
    Header,
    "INTERFACE NOVA • V0",
    19,
    Enum.Font.Gotham,
    COLORS.Gray
)

Subtitle.Position = UDim2.new(0, 42, 0, 75)
Subtitle.Size = UDim2.new(0.65, 0, 0, 30)

--==================================================
-- BOTÃO MINIMIZAR
--==================================================

local MinimizeButton = Instance.new("TextButton")
MinimizeButton.Name = "MinimizeButton"
MinimizeButton.AnchorPoint = Vector2.new(1, 0)
MinimizeButton.Position = UDim2.new(1, -145, 0, 40)
MinimizeButton.Size = UDim2.new(0, 90, 0, 90)
MinimizeButton.BackgroundColor3 = Color3.fromRGB(28, 27, 34)
MinimizeButton.Text = "—"
MinimizeButton.TextColor3 = COLORS.White
MinimizeButton.TextSize = 38
MinimizeButton.Font = Enum.Font.GothamBold
MinimizeButton.AutoButtonColor = false
MinimizeButton.Parent = Header

Corner(MinimizeButton, 24)

--==================================================
-- BOTÃO FECHAR
--==================================================

local CloseButton = Instance.new("TextButton")
CloseButton.Name = "CloseButton"
CloseButton.AnchorPoint = Vector2.new(1, 0)
CloseButton.Position = UDim2.new(1, -40, 0, 40)
CloseButton.Size = UDim2.new(0, 90, 0, 90)
CloseButton.BackgroundColor3 = COLORS.DarkRed
CloseButton.Text = "×"
CloseButton.TextColor3 = COLORS.White
CloseButton.TextSize = 38
CloseButton.Font = Enum.Font.GothamBold
CloseButton.AutoButtonColor = false
CloseButton.Parent = Header

Corner(CloseButton, 24)

--==================================================
-- STATUS
--==================================================

local StatusFrame = Instance.new("Frame")
StatusFrame.Name = "StatusFrame"
StatusFrame.Position = UDim2.new(0, 28, 0.27, 0)
StatusFrame.Size = UDim2.new(1, -56, 0.25, 0)
StatusFrame.BackgroundColor3 = COLORS.Panel
StatusFrame.BorderSizePixel = 0
StatusFrame.Parent = MainFrame

Corner(StatusFrame, 24)

local StatusDot = Instance.new("Frame")
StatusDot.Name = "StatusDot"
StatusDot.Position = UDim2.new(0, 32, 0, 32)
StatusDot.Size = UDim2.new(0, 30, 0, 30)
StatusDot.BackgroundColor3 = COLORS.Green
StatusDot.BorderSizePixel = 0
StatusDot.Parent = StatusFrame

Corner(StatusDot, 50)

local StatusTitle = CreateText(
    StatusFrame,
    "Interface pronta",
    25,
    Enum.Font.GothamBold,
    COLORS.White
)

StatusTitle.Position = UDim2.new(0, 75, 0, 25)
StatusTitle.Size = UDim2.new(0.7, 0, 0, 40)

local StatusText = CreateText(
    StatusFrame,
    "Nenhuma leitura executada",
    18,
    Enum.Font.Gotham,
    COLORS.Gray
)

StatusText.Position = UDim2.new(0, 32, 0, 75)
StatusText.Size = UDim2.new(0.8, 0, 0, 30)

--==================================================
-- ÁREA DE CONTEÚDO
--==================================================

local ContentFrame = Instance.new("Frame")
ContentFrame.Name = "ContentFrame"
ContentFrame.Position = UDim2.new(0, 28, 0.55, 0)
ContentFrame.Size = UDim2.new(1, -56, 0.40, 0)
ContentFrame.BackgroundTransparency = 1
ContentFrame.Parent = MainFrame

--==================================================
-- PAINEL DOS BOTÕES
--==================================================

local ButtonFrame = Instance.new("Frame")
ButtonFrame.Name = "ButtonFrame"
ButtonFrame.Size = UDim2.new(0.31, 0, 1, 0)
ButtonFrame.BackgroundColor3 = COLORS.Panel
ButtonFrame.BorderSizePixel = 0
ButtonFrame.Parent = ContentFrame

Corner(ButtonFrame, 24)

local ButtonPadding = Instance.new("UIPadding")
ButtonPadding.PaddingTop = UDim.new(0, 20)
ButtonPadding.PaddingBottom = UDim.new(0, 20)
ButtonPadding.PaddingLeft = UDim.new(0, 20)
ButtonPadding.PaddingRight = UDim.new(0, 20)
ButtonPadding.Parent = ButtonFrame

local ButtonLayout = Instance.new("UIListLayout")
ButtonLayout.FillDirection = Enum.FillDirection.Vertical
ButtonLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
ButtonLayout.VerticalAlignment = Enum.VerticalAlignment.Center
ButtonLayout.Padding = UDim.new(0, 18)
ButtonLayout.Parent = ButtonFrame

--==================================================
-- BOTÃO LEITURA DE BOTS
--==================================================

local BotsButton = Instance.new("TextButton")
BotsButton.Name = "BotsButton"
BotsButton.Size = UDim2.new(1, 0, 0, 110)
BotsButton.BackgroundColor3 = COLORS.Red
BotsButton.Text = "LEITURA DE BOTS"
BotsButton.TextColor3 = COLORS.White
BotsButton.TextSize = 22
BotsButton.Font = Enum.Font.GothamBold
BotsButton.AutoButtonColor = false
BotsButton.Parent = ButtonFrame

Corner(BotsButton, 22)

--==================================================
-- BOTÃO BAIXAR ARQUIVO
--==================================================

local DownloadButton = Instance.new("TextButton")
DownloadButton.Name = "DownloadButton"
DownloadButton.Size = UDim2.new(1, 0, 0, 110)
DownloadButton.BackgroundColor3 = COLORS.DarkRed
DownloadButton.Text = "BAIXAR ARQUIVO"
DownloadButton.TextColor3 = COLORS.White
DownloadButton.TextSize = 22
DownloadButton.Font = Enum.Font.GothamBold
DownloadButton.AutoButtonColor = false
DownloadButton.Parent = ButtonFrame

Corner(DownloadButton, 22)

--==================================================
-- PAINEL DE INFORMAÇÕES
--==================================================

local InfoFrame = Instance.new("Frame")
InfoFrame.Name = "InfoFrame"
InfoFrame.Position = UDim2.new(0.33, 0, 0, 0)
InfoFrame.Size = UDim2.new(0.67, 0, 1, 0)
InfoFrame.BackgroundColor3 = COLORS.Panel
InfoFrame.BorderSizePixel = 0
InfoFrame.Parent = ContentFrame

Corner(InfoFrame, 24)

local InfoTitle = CreateText(
    InfoFrame,
    "LEITURA DE BOTS",
    25,
    Enum.Font.GothamBold,
    COLORS.White
)

InfoTitle.Position = UDim2.new(0, 30, 0, 30)
InfoTitle.Size = UDim2.new(1, -60, 0, 40)

local InfoBox = Instance.new("Frame")
InfoBox.Position = UDim2.new(0, 25, 0.34, 0)
InfoBox.Size = UDim2.new(1, -50, 0.55, 0)
InfoBox.BackgroundColor3 = Color3.fromRGB(10, 9, 13)
InfoBox.BorderSizePixel = 0
InfoBox.Parent = InfoFrame

Corner(InfoBox, 20)

local InfoText = CreateText(
    InfoBox,
    "BAIXAR ARQUIVO\n\nBotão preparado.\nA função de geração/download será adicionada separadamente.",
    18,
    Enum.Font.Code,
    COLORS.Gray
)

InfoText.Position = UDim2.new(0, 15, 0, 10)
InfoText.Size = UDim2.new(1, -30, 1, -20)
InfoText.TextWrapped = true
InfoText.TextYAlignment = Enum.TextYAlignment.Top

--==================================================
-- BOTÃO FLUTUANTE
--==================================================

local FloatingButton = Instance.new("TextButton")
FloatingButton.Name = "FloatingButton"
FloatingButton.AnchorPoint = Vector2.new(0.5, 0.5)
FloatingButton.Position = UDim2.fromScale(0.85, 0.80)
FloatingButton.Size = UDim2.new(0, 75, 0, 75)
FloatingButton.BackgroundColor3 = COLORS.Blue
FloatingButton.Text = "☰"
FloatingButton.TextColor3 = COLORS.White
FloatingButton.TextSize = 30
FloatingButton.Font = Enum.Font.GothamBold
FloatingButton.AutoButtonColor = false
FloatingButton.Visible = false
FloatingButton.ZIndex = 100
FloatingButton.Parent = ScreenGui

Corner(FloatingButton, 22)
Stroke(FloatingButton, Color3.fromRGB(45, 70, 120), 2, 0.2)

--==================================================
-- EFEITO DOS BOTÕES
--==================================================

local function ButtonHover(button, normalColor, hoverColor)
    button.MouseEnter:Connect(function()
        TweenService:Create(
            button,
            TweenInfo.new(0.15),
            {BackgroundColor3 = hoverColor}
        ):Play()
    end)

    button.MouseLeave:Connect(function()
        TweenService:Create(
            button,
            TweenInfo.new(0.15),
            {BackgroundColor3 = normalColor}
        ):Play()
    end)
end

ButtonHover(
    BotsButton,
    COLORS.Red,
    Color3.fromRGB(255, 45, 62)
)

ButtonHover(
    DownloadButton,
    COLORS.DarkRed,
    Color3.fromRGB(155, 22, 38)
)

ButtonHover(
    MinimizeButton,
    Color3.fromRGB(28, 27, 34),
    Color3.fromRGB(38, 37, 45)
)

ButtonHover(
    CloseButton,
    COLORS.DarkRed,
    Color3.fromRGB(155, 22, 38)
)

ButtonHover(
    FloatingButton,
    COLORS.Blue,
    COLORS.BlueHover
)

--==================================================
-- MINIMIZAR
--==================================================

local function Minimize()
    MainFrame.Visible = false
    FloatingButton.Visible = true

    FloatingButton.Size = UDim2.new(0, 0, 0, 0)

    TweenService:Create(
        FloatingButton,
        TweenInfo.new(
            0.25,
            Enum.EasingStyle.Back,
            Enum.EasingDirection.Out
        ),
        {
            Size = UDim2.new(0, 75, 0, 75)
        }
    ):Play()
end

MinimizeButton.MouseButton1Click:Connect(Minimize)

--==================================================
-- ABRIR NOVAMENTE
--==================================================

FloatingButton.MouseButton1Click:Connect(function()

    FloatingButton.Visible = false
    MainFrame.Visible = true

    MainFrame.Size = UDim2.fromScale(0.85, 0.83)

    TweenService:Create(
        MainFrame,
        TweenInfo.new(
            0.25,
            Enum.EasingStyle.Back,
            Enum.EasingDirection.Out
        ),
        {
            Size = UDim2.fromScale(0.92, 0.90)
        }
    ):Play()

end)

--==================================================
-- BOTÃO FECHAR
--==================================================

CloseButton.MouseButton1Click:Connect(function()

    local tween = TweenService:Create(
        MainFrame,
        TweenInfo.new(0.2),
        {
            Size = UDim2.fromScale(0, 0),
            BackgroundTransparency = 1
        }
    )

    tween:Play()

    tween.Completed:Connect(function()
        ScreenGui:Destroy()
    end)

end)

--==================================================
-- BOTÃO LEITURA DE BOTS
--==================================================

BotsButton.MouseButton1Click:Connect(function()

    StatusTitle.Text = "Leitura iniciada"
    StatusText.Text = "Processando informações..."

    task.wait(1)

    StatusTitle.Text = "Interface pronta"
    StatusText.Text = "Leitura executada."

end)

--==================================================
-- BOTÃO DOWNLOAD
--==================================================

DownloadButton.MouseButton1Click:Connect(function()

    StatusTitle.Text = "Download"
    StatusText.Text = "Função de download ainda não configurada."

end)

--==================================================
-- ARRASTAR BOTÃO FLUTUANTE
--==================================================

local dragging = false
local dragStart
local startPosition

FloatingButton.InputBegan:Connect(function(input)

    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then

        dragging = true
        dragStart = input.Position
        startPosition = FloatingButton.Position

        input.Changed:Connect(function()

            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end

        end)
    end

end)

UserInputService.InputChanged:Connect(function(input)

    if not dragging then
        return
    end

    if input.UserInputType ~= Enum.UserInputType.MouseMovement
        and input.UserInputType ~= Enum.UserInputType.Touch then
        return
    end

    local delta = input.Position - dragStart

    local newX = startPosition.X.Offset + delta.X
    local newY = startPosition.Y.Offset + delta.Y

    FloatingButton.Position = UDim2.new(
        startPosition.X.Scale,
        newX,
        startPosition.Y.Scale,
        newY
    )

end)
