--==============================================================--
-- CAFEÍNA • BOT READER
-- INTERFACE BASE — V0
--
-- ESTA VERSÃO É SOMENTE A INTERFACE.
-- Nenhuma função do menu antigo foi reutilizada.
--
-- Botões preparados para receber funções posteriormente:
-- • LEITURA DE BOTS
-- • BAIXAR ARQUIVO
--
-- Recursos da interface:
-- • Janela independente
-- • Minimizar
-- • Fechar
-- • Botão flutuante azul-escuro
-- • Botão flutuante pode ser movido livremente
-- • Janela pode ser arrastada
-- • Compatível com mouse e toque
--==============================================================--

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()

--==============================================================--
-- CORES
--==============================================================--

local COLORS = {
    Background = Color3.fromRGB(12, 12, 16),
    Panel = Color3.fromRGB(20, 20, 25),
    Panel2 = Color3.fromRGB(28, 28, 35),
    Stroke = Color3.fromRGB(55, 55, 65),

    Text = Color3.fromRGB(245, 245, 248),
    SubText = Color3.fromRGB(160, 160, 172),

    Red = Color3.fromRGB(235, 38, 52),
    RedDark = Color3.fromRGB(115, 20, 30),

    -- Botão flutuante de minimizar
    BlueDark = Color3.fromRGB(20, 55, 105),
    BlueStroke = Color3.fromRGB(45, 105, 180),
}

--==============================================================--
-- HELPERS
--==============================================================--

local function Create(className, properties)
    local object = Instance.new(className)

    for property, value in pairs(properties or {}) do
        object[property] = value
    end

    return object
end

local function AddCorner(parent, radius)
    return Create("UICorner", {
        CornerRadius = UDim.new(0, radius or 10),
        Parent = parent,
    })
end

local function AddStroke(parent, color, thickness)
    return Create("UIStroke", {
        Color = color or COLORS.Stroke,
        Thickness = thickness or 1,
        Parent = parent,
    })
end

--==============================================================--
-- GUI
--==============================================================--

local GUI_NAME = "CafeinaBotReader_NewInterface"

-- Remove SOMENTE uma instância desta nova interface.
-- Nenhuma interface antiga é procurada ou alterada.
pcall(function()
    local old = CoreGui:FindFirstChild(GUI_NAME)
    if old then
        old:Destroy()
    end
end)

local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local Gui = Create("ScreenGui", {
    Name = GUI_NAME,
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})

local parented = false

pcall(function()
    if typeof(gethui) == "function" then
        local holder = gethui()
        if holder then
            Gui.Parent = holder
            parented = true
        end
    end
end)

if not parented then
    pcall(function()
        Gui.Parent = CoreGui
        parented = true
    end)
end

if not parented then
    Gui.Parent = PlayerGui
end

--==============================================================--
-- JANELA PRINCIPAL
--==============================================================--

local Main = Create("Frame", {
    Name = "Main",
    Size = UDim2.fromScale(0.78, 0.62),
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),

    BackgroundColor3 = COLORS.Background,
    BorderSizePixel = 0,

    Parent = Gui,
})

AddCorner(Main, 15)
AddStroke(Main, COLORS.Stroke, 1)

--==============================================================--
-- CABEÇALHO
--==============================================================--

local Header = Create("Frame", {
    Name = "Header",

    Size = UDim2.new(1, 0, 0, 62),

    BackgroundColor3 = COLORS.Panel,
    BorderSizePixel = 0,

    Parent = Main,
})

AddCorner(Header, 15)

Create("TextLabel", {
    Name = "Title",

    Position = UDim2.fromOffset(16, 8),
    Size = UDim2.new(1, -105, 0, 25),

    BackgroundTransparency = 1,

    Text = "CAFÉÍNA • BOT READER",
    TextColor3 = COLORS.Text,

    Font = Enum.Font.GothamBold,
    TextSize = 17,

    TextXAlignment = Enum.TextXAlignment.Left,

    Parent = Header,
})

Create("TextLabel", {
    Name = "Subtitle",

    Position = UDim2.fromOffset(16, 34),
    Size = UDim2.new(1, -105, 0, 17),

    BackgroundTransparency = 1,

    Text = "INTERFACE NOVA • V0",

    TextColor3 = COLORS.SubText,

    Font = Enum.Font.Gotham,
    TextSize = 10,

    TextXAlignment = Enum.TextXAlignment.Left,

    Parent = Header,
})

local MinimizeButton = Create("TextButton", {
    Name = "Minimize",

    Position = UDim2.new(1, -78, 0, 13),
    Size = UDim2.fromOffset(30, 30),

    BackgroundColor3 = COLORS.Panel2,
    BorderSizePixel = 0,

    Text = "—",
    TextColor3 = COLORS.Text,

    Font = Enum.Font.GothamBold,
    TextSize = 17,

    Parent = Header,
})

AddCorner(MinimizeButton, 8)

local CloseButton = Create("TextButton", {
    Name = "Close",

    Position = UDim2.new(1, -42, 0, 13),
    Size = UDim2.fromOffset(30, 30),

    BackgroundColor3 = COLORS.RedDark,
    BorderSizePixel = 0,

    Text = "×",
    TextColor3 = COLORS.Text,

    Font = Enum.Font.GothamBold,
    TextSize = 19,

    Parent = Header,
})

AddCorner(CloseButton, 8)

--==============================================================--
-- STATUS
--==============================================================--

local Status = Create("Frame", {
    Name = "Status",

    Position = UDim2.new(0, 10, 0, 72),
    Size = UDim2.new(1, -20, 0, 62),

    BackgroundColor3 = COLORS.Panel,
    BorderSizePixel = 0,

    Parent = Main,
})

AddCorner(Status, 10)

local StatusDot = Create("Frame", {
    Size = UDim2.fromOffset(10, 10),
    Position = UDim2.fromOffset(12, 13),

    BackgroundColor3 = Color3.fromRGB(65, 210, 118),
    BorderSizePixel = 0,

    Parent = Status,
})

AddCorner(StatusDot, 99)

Create("TextLabel", {
    Name = "StatusText",

    Position = UDim2.fromOffset(30, 7),
    Size = UDim2.new(1, -40, 0, 22),

    BackgroundTransparency = 1,

    Text = "Interface pronta",
    TextColor3 = COLORS.Text,

    Font = Enum.Font.GothamBold,
    TextSize = 11,

    TextXAlignment = Enum.TextXAlignment.Left,

    Parent = Status,
})

Create("TextLabel", {
    Name = "StatusDetail",

    Position = UDim2.fromOffset(12, 32),
    Size = UDim2.new(1, -24, 0, 18),

    BackgroundTransparency = 1,

    Text = "Nenhuma leitura executada",

    TextColor3 = COLORS.SubText,

    Font = Enum.Font.Gotham,
    TextSize = 9,

    TextXAlignment = Enum.TextXAlignment.Left,

    Parent = Status,
})

--==============================================================--
-- CORPO
--==============================================================--

local Sidebar = Create("Frame", {
    Name = "Sidebar",

    Position = UDim2.new(0, 10, 0, 144),
    Size = UDim2.new(0.31, -15, 1, -154),

    BackgroundColor3 = COLORS.Panel,
    BorderSizePixel = 0,

    Parent = Main,
})

AddCorner(Sidebar, 10)

local Content = Create("Frame", {
    Name = "Content",

    Position = UDim2.new(0.31, 5, 0, 144),
    Size = UDim2.new(0.69, -15, 1, -154),

    BackgroundColor3 = COLORS.Panel,
    BorderSizePixel = 0,

    Parent = Main,
})

AddCorner(Content, 10)

--==============================================================--
-- BOTÕES NOVOS
--==============================================================--

local ReadBotsButton = Create("TextButton", {
    Name = "ReadBots",

    Position = UDim2.fromOffset(8, 8),
    Size = UDim2.new(1, -16, 0, 46),

    BackgroundColor3 = COLORS.Red,
    BorderSizePixel = 0,

    Text = "LEITURA DE BOTS",

    TextColor3 = COLORS.Text,

    Font = Enum.Font.GothamBold,
    TextSize = 11,

    Parent = Sidebar,
})

AddCorner(ReadBotsButton, 9)

local DownloadButton = Create("TextButton", {
    Name = "Download",

    Position = UDim2.fromOffset(8, 62),
    Size = UDim2.new(1, -16, 0, 46),

    BackgroundColor3 = COLORS.RedDark,
    BorderSizePixel = 0,

    Text = "BAIXAR ARQUIVO",

    TextColor3 = COLORS.Text,

    Font = Enum.Font.GothamBold,
    TextSize = 10,

    Parent = Sidebar,
})

AddCorner(DownloadButton, 9)

--==============================================================--
-- ÁREA DE VISUALIZAÇÃO
--==============================================================--

Create("TextLabel", {
    Name = "ContentTitle",

    Position = UDim2.fromOffset(12, 10),
    Size = UDim2.new(1, -24, 0, 24),

    BackgroundTransparency = 1,

    Text = "LEITURA DE BOTS",

    TextColor3 = COLORS.Text,

    Font = Enum.Font.GothamBold,
    TextSize = 13,

    TextXAlignment = Enum.TextXAlignment.Left,

    Parent = Content,
})

local Viewer = Create("TextBox", {
    Name = "Viewer",

    Position = UDim2.fromOffset(10, 40),
    Size = UDim2.new(1, -20, 1, -50),

    BackgroundColor3 = COLORS.Background,
    BorderSizePixel = 0,

    Text = "Interface criada do zero.\n\nA função de leitura de bots será adicionada na próxima etapa.",

    TextColor3 = COLORS.SubText,

    Font = Enum.Font.Code,
    TextSize = 10,

    TextWrapped = false,
    MultiLine = true,

    ClearTextOnFocus = false,
    TextEditable = false,

    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top,

    Parent = Content,
})

AddCorner(Viewer, 8)

--==============================================================--
-- BOTÃO FLUTUANTE
--==============================================================--

local FloatingButton = Create("TextButton", {
    Name = "FloatingMinimize",

    Size = UDim2.fromOffset(58, 58),

    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.88, 0.15),

    BackgroundColor3 = COLORS.BlueDark,
    BorderSizePixel = 0,

    Text = "C",
    TextColor3 = COLORS.Text,

    Font = Enum.Font.GothamBlack,
    TextSize = 20,

    Parent = Gui,
})

AddCorner(FloatingButton, 99)
AddStroke(FloatingButton, COLORS.BlueStroke, 2)

FloatingButton.Visible = false

--==============================================================--
-- ARRASTAR
--==============================================================--

local function MakeDraggable(target, handle)
    local dragging = false
    local dragStart = nil
    local startPosition = nil

    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseButton1 then

            dragging = true
            dragStart = input.Position
            startPosition = target.Position
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if not dragging then
            return
        end

        if input.UserInputType ~= Enum.UserInputType.Touch
            and input.UserInputType ~= Enum.UserInputType.MouseMovement then
            return
        end

        if not dragStart or not startPosition then
            return
        end

        local delta = input.Position - dragStart

        target.Position = UDim2.new(
            startPosition.X.Scale,
            startPosition.X.Offset + delta.X,

            startPosition.Y.Scale,
            startPosition.Y.Offset + delta.Y
        )
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseButton1 then

            dragging = false
        end
    end)
end

MakeDraggable(Main, Header)
MakeDraggable(FloatingButton, FloatingButton)

--==============================================================--
-- EVENTOS DA INTERFACE
--==============================================================--

MinimizeButton.Activated:Connect(function()
    Main.Visible = false
    FloatingButton.Visible = true
end)

FloatingButton.Activated:Connect(function()
    FloatingButton.Visible = false
    Main.Visible = true
end)

CloseButton.Activated:Connect(function()
    Gui:Destroy()
end)

--==============================================================--
-- BOTÕES DE FUNÇÃO
--==============================================================--

-- IMPORTANTE:
-- Estes dois botões estão propositalmente SEM lógica de leitura.
-- As funções serão adicionadas individualmente nas próximas versões.

ReadBotsButton.Activated:Connect(function()
    Viewer.Text =
        "LEITURA DE BOTS\n\n" ..
        "Botão preparado.\n" ..
        "A função de leitura será adicionada separadamente."
end)

DownloadButton.Activated:Connect(function()
    Viewer.Text =
        "BAIXAR ARQUIVO\n\n" ..
        "Botão preparado.\n" ..
        "A função de geração/download será adicionada separadamente."
end)

print("[CAFEINA BOT READER] Interface nova V0 carregada.")
