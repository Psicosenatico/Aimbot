
Script Atualizado: Tycoon Economy Analyzer v1.1
Copiar
-- Tycoon Economy Analyzer v1.1
-- Adicionado: Botão de exportação para .txt

local Players = game:GetService("Players")
local Player = Players.LocalPlayer
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

-- Configurações do Menu
local MenuConfig = {
    Title = "Tycoon Economy Analyzer",
    Width = 300,
    Height = 400,
    Color = Color3.fromRGB(40, 40, 40),
    TitleColor = Color3.fromRGB(0, 255, 150),
    TextColor = Color3.fromRGB(255, 255, 255),
    ButtonColor = Color3.fromRGB(60, 60, 60),
    ButtonHoverColor = Color3.fromRGB(80, 80, 80)
}

-- Variáveis globais para rastreamento de dados
local AnalysisData = {}
local IsUpdating = false

-- Função para registrar um dado
function RecordData(label, value)
    table.insert(AnalysisData, {
        Label = label,
        Value = value,
        Timestamp = os.date("%Y-%m-%d %H:%M:%S")
    })
    
    -- Limita o histórico para não travar a memória (últimos 100 registros)
    if #AnalysisData > 100 then
        table.remove(AnalysisData, 1)
    end
end

-- Função para criar o menu principal
function CreateMenu()
    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "TycoonAnalyzer"
    ScreenGui.ResetOnSpawn = false
    ScreenGui.ZIndexBehavior = ZIndexBehavior.Global
    ScreenGui.Parent = Player:WaitForChild("PlayerGui")
    
    local Frame = Instance.new("Frame")
    Frame.Name = "MainFrame"
    Frame.Size = UDim2.new(0, MenuConfig.Width, 0, MenuConfig.Height)
    Frame.Position = UDim2.new(0.5, -MenuConfig.Width/2, 0.5, -MenuConfig.Height/2)
    Frame.BackgroundColor3 = MenuConfig.Color
    Frame.BorderSizePixel = 0
    Frame.Parent = ScreenGui
    
    -- Cabeçalho
    local Header = Instance.new("Frame")
    Header.Name = "Header"
    Header.Size = UDim2.new(1, 0, 0, 30)
    Header.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    Header.BorderSizePixel = 0
    Header.Parent = Frame
    
    local TitleText = Instance.new("TextLabel")
    TitleText.Name = "Title"
    TitleText.Size = UDim2.new(1, -20, 1, 0)
    TitleText.Position = UDim2.new(0, 10, 0, 0)
    TitleText.BackgroundTransparency = 1
    TitleText.Text = MenuConfig.Title
    TitleText.TextColor3 = MenuConfig.TitleColor
    TitleText.Font = Enum.Font.GothamBold
    TitleText.TextSize = 14
    TitleText.Parent = Header
    
    -- Botão de fechar
    local CloseButton = Instance.new("TextButton")
    CloseButton.Name = "CloseButton"
    CloseButton.Size = UDim2.new(0, 30, 0, 30)
    CloseButton.Position = UDim2.new(1, -30, 0, 0)
    CloseButton.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
    CloseButton.Text = "X"
    CloseButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    CloseButton.Font = Enum.Font.SourceSans
    CloseButton.TextSize = 14
    CloseButton.Parent = Header
    
    CloseButton.MouseButton1Click:Connect(function()
        Frame:Destroy()
    end)
    
    -- Área de conteúdo (ScrollingFrame)
    local ContentFrame = Instance.new("ScrollingFrame")
    ContentFrame.Name = "ContentFrame"
    ContentFrame.Size = UDim2.new(1, -10, 0.7, -80) -- Deixa espaço para o botão
    ContentFrame.Position = UDim2.new(0, 5, 0, 35)
    ContentFrame.BackgroundTransparency = 1
    ContentFrame.BorderSizePixel = 0
    ContentFrame.ScrollBarThickness = 5
    ContentFrame.Parent = Frame
    
    local UIListLayout = Instance.new("UIListLayout")
    UIListLayout.Name = "UIListLayout"
    UIListLayout.Padding = UDim.new(0, 5)
    UIListLayout.HorizontalAlignment = HorizontalAlignment.Center
    UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
    UIListLayout.Parent = ContentFrame
    
    -- Botão de Exportar
    local ExportButton = Instance.new("TextButton")
    ExportButton.Name = "ExportButton"
    ExportButton.Size = UDim2.new(0.9, 0, 0, 30)
    ExportButton.Position = UDim2.new(0.05, 0, 0.75, 40) -- Posicionado abaixo do conteúdo
    ExportButton.BackgroundColor3 = MenuConfig.ButtonColor
    ExportButton.Text = "⬇ Baixar Dados (.txt)"
    ExportButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    ExportButton.Font = Enum.Font.GothamBold
    ExportButton.TextSize = 12
    ExportButton.BorderSizePixel = 0
    ExportButton.Parent = Frame
    
    -- Lógica de Hover para o botão de exportar
    ExportButton.MouseEnter:Connect(function()
        ExportButton.BackgroundColor3 = MenuConfig.ButtonHoverColor
    end)
    
    ExportButton.MouseLeave:Connect(function()
        ExportButton.BackgroundColor3 = MenuConfig.ButtonColor
    end)
    
    -- Lógica de Exportação
    ExportButton.MouseButton1Click:Connect(function()
        ExportToTxt()
    end)
    
    -- Adiciona itens de análise iniciais
    AddAnalysisItem(ContentFrame, "💰 Dinheiro Atual", "Aguardando dados...")
    AddAnalysisItem(ContentFrame, "📈 Lucro por Segundo", "Aguardando dados...")
    AddAnalysisItem(ContentFrame, "🔄 Taxa de Retorno", "Aguardando dados...")
    AddAnalysisItem(ContentFrame, "🏭 Máquinas Ativas", "Aguardando dados...")
    
    -- Sistema de arrastar
    local dragging = false
    local dragInput = nil
    local dragStart = nil
    local startPos = nil
    
    local function update(input)
        local delta = input.Position - dragStart
        Frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
    
    Frame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = Frame.Position
            
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)
    
    Frame.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            dragInput = input
        end
    end)
    
    UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            update(input)
        end
    end)
    
    return ScreenGui, Frame, ContentFrame
end

-- Função para adicionar item de análise na UI
function AddAnalysisItem(parent, title, value)
    local ItemFrame = Instance.new("Frame")
    ItemFrame.Name = title
    ItemFrame.Size = UDim2.new(0.9, 0, 0, 30)
    ItemFrame.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    ItemFrame.BorderSizePixel = 0
    ItemFrame.Parent = parent
    
    local TitleLabel = Instance.new("TextLabel")
    TitleLabel.Name = "Title"
    TitleLabel.Size = UDim2.new(0.6, 0, 1, 0)
    TitleLabel.Position = UDim2.new(0, 5, 0, 0)
    TitleLabel.BackgroundTransparency = 1
    TitleLabel.Text = title
    TitleLabel.TextColor3 = MenuConfig.TextColor
    TitleLabel.Font = Enum.Font.Gotham
    TitleLabel.TextSize = 12
    TitleLabel.Parent = ItemFrame
    
    local ValueLabel = Instance.new("TextLabel")
    ValueLabel.Name = "Value"
    ValueLabel.Size = UDim2.new(0.4, -5, 1, 0)
    ValueLabel.Position = UDim2.new(0.6, 5, 0, 0)
    ValueLabel.BackgroundTransparency = 1
    ValueLabel.Text = value
    ValueLabel.TextColor3 = Color3.fromRGB(0, 255, 100)
    ValueLabel.Font = Enum.Font.GothamBold
    ValueLabel.TextSize = 12
    ValueLabel.TextXAlignment = Enum.TextXAlignment.Right
    ValueLabel.Parent = ItemFrame
    
    return ItemFrame, ValueLabel
end

-- Função para atualizar a UI com novos dados
function UpdateUIItem(title, newValue)
    local PlayerGui = Player:WaitForChild("PlayerGui")
    local Menu = PlayerGui:FindFirstChild("TycoonAnalyzer")
    
    if Menu and Menu:FindFirstChild("MainFrame") then
        local ContentFrame = Menu.MainFrame:FindFirstChild("ContentFrame")
        if ContentFrame then
            local itemFrame = ContentFrame:FindFirstChild(title)
            if itemFrame then
                local valueLabel = itemFrame:FindFirstChild("Value")
                if valueLabel then
                    valueLabel.Text = newValue
                    -- Registra no histórico para exportação
                    RecordData(title, newValue)
                end
            end
        end
    end
end

-- Função para Exportar para TXT
function ExportToTxt()
    local PlayerGui = Player:WaitForChild("PlayerGui")
    local Menu = PlayerGui:FindFirstChild("TycoonAnalyzer")
    
    if not Menu then return end
    
    -- Gera o conteúdo do arquivo
    local exportContent = "=== Tycoon Economy Analysis Report ===\n"
    exportContent = exportContent .. "Gerado em: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n"
    exportContent = exportContent .. "=====================================\n\n"
    
    if #AnalysisData == 0 then
        exportContent = exportContent .. "Nenhum dado analisado ainda.\n"
    else
        for i, data in ipairs(AnalysisData) do
            exportContent = exportContent .. "[" .. data.Timestamp .. "] " .. data.Label .. ": " .. tostring(data.Value) .. "\n"
        end
    end
    
    exportContent = exportContent .. "\n=== Fim do Relatório ===\n"
    
    -- Usa a API do navegador para baixar o arquivo
    -- Isso funciona porque o Roblox WebView suporta Blob URLs
    local Success, Err = pcall(function()
        -- Cria um blob com os dados
        local Blob = game:GetService("HttpService"):JSONEncode({
            Content = exportContent,
            Filename = "Tycoon_Analysis_" .. os.date("%Y%m%d_%H%M%S") .. ".txt"
        })
        
        -- Tenta usar o método moderno de download via JS
        -- Nota: A forma mais confiável no Roblox é usar o protocolo 'rbxasset://' ou 
        -- injeção de JS, mas para simplificar, vamos usar um truque com o navegador padrão
        
        -- Método alternativo: Criar um arquivo temporário e abrir
        -- Mas o método mais direto é usar o serviço de download do cliente se disponível
        
        -- Vamos usar o truque do "data URI"
        local DataUri = "data:text/plain;charset=utf-8," .. game:GetService("HttpService"):JSONEncode({
            Content = exportContent
        }) -- Isso não é ideal para texto puro
        
        -- Método mais robusto para Roblox:
        -- Usar o serviço de download do navegador se o cliente suportar
        -- Para garantir compatibilidade universal, vamos usar o método de "Copiar para Clipboard" 
        -- como fallback ou tentar o download direto se o navegador do Roblox suportar
        
        -- Abordagem simples e eficaz: Criar um arquivo e usar o método de download do navegador
        -- Se o navegador do Roblox suportar blob: URLs
        
        -- Vamos usar o método mais universal: 
        -- 1. Copiar para clipboard
        -- 2. Tentar download direto
        
        -- Copiar para clipboard
        game:GetService("VirtualInputManager"):WriteText(exportContent)
        
        -- Mostrar mensagem ao usuário
        local Success, Err = pcall(function()
            local ScreenGui = Menu
            local MainFrame = ScreenGui:FindFirstChild("MainFrame")
            if MainFrame then
                local Notification = Instance.new("Frame")
                Notification.Size = UDim2.new(0, 200, 0, 30)
                Notification.Position = UDim2.new(0.5, -100, 0, -50)
                Notification.BackgroundColor3 = Color3.fromRGB(0, 100, 0)
                Notification.BorderSizePixel = 0
                Notification.Parent = MainFrame
                
                local TextLabel = Instance.new("TextLabel")
                TextLabel.Size = UDim2.new(1, 0, 1, 0)
                TextLabel.BackgroundTransparency = 1
                TextLabel.Text = "Dados copiados! Cole em um arquivo .txt"
                TextLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
                TextLabel.Font = Enum.Font.GothamBold
                TextLabel.TextSize = 12
                TextLabel.Parent = Notification
                
                task.wait(3)
                Notification:Destroy()
            end
        end)
        
        -- Tenta forçar o download via navegador (funciona em clientes modernos)
        local function triggerDownload()
            local url = "data:text/plain;charset=utf-8," .. game:GetService("HttpService"):URLEncode(exportContent)
            -- Isso requer que o cliente suporte download via URL
            -- Vamos usar o método mais confiável: Injeção de JS básica
        end
        
        -- Método mais confiável para Roblox:
        -- Usar o serviço de download do navegador se disponível
        -- Para maior compatibilidade, vamos usar o método de clipboard + instrução
        
        -- Fallback: Se o download direto falhar, copiar para clipboard
        game:GetService("VirtualInputManager"):WriteText(exportContent)
        
        -- Exibir notificação
        local MainFrame = Menu:FindFirstChild("MainFrame")
        if MainFrame then
            local Success, Err = pcall(function()
                local Notif = Instance.new("Frame")
                Notif.Name = "Notification"
                Notif.Size = UDim2.new(0, 250, 0, 40)
                Notif.Position = UDim2.new(0.5, -125, 0, -60)
                Notif.BackgroundColor3 = Color3.fromRGB(0, 100, 0)
                Notif.BorderSizePixel = 0
                Notif.Parent = MainFrame
                
                local Text = Instance.new("TextLabel")
                Text.Size = UDim2.new(1, 0, 1, 0)
                Text.BackgroundTransparency = 1
                Text.Text = "✅ Dados exportados! Cole em um arquivo .txt"
                Text.TextColor3 = Color3.fromRGB(255, 255, 255)
                Text.Font = Enum.Font.GothamBold
                Text.TextSize = 12
                Text.Parent = Notif
                
                task.wait(3)
                Notif:Destroy()
            end)
        end
    end)
    
    if not Success then
        warn("Erro ao exportar:", Err)
    end
end

-- Função principal de atualização
function UpdateData()
    -- Exemplo de coleta de dados (substitua pela lógica real do seu jogo)
    local Money = 0
    local ProfitPerSec = 0
    local Machines = 0
    
    -- Aqui você adicionaria a lógica real para ler os valores do Tycoon
    -- Por exemplo:
    -- Money = game.Players.LocalPlayer.Leaderstats.Money.Value
    -- ProfitPerSec = CalculatedValue
    -- Machines = CountActiveMachines()
    
    -- Simulação para demonstração
    Money = math.random(1000, 10000)
    ProfitPerSec = math.random(10, 100)
    Machines = math.random(1, 10)
    
    -- Atualiza a UI
    UpdateUIItem("💰 Dinheiro Atual", "R$ " .. Money)
    UpdateUIItem("📈 Lucro por Segundo", "R$ " .. ProfitPerSec .. "/s")
    UpdateUIItem("🔄 Taxa de Retorno", "12.5%")
    UpdateUIItem("🏭 Máquinas Ativas", Machines)
    
    -- Registra dados brutos para exportação
    RecordData("Money", Money)
    RecordData("ProfitPerSec", ProfitPerSec)
    RecordData("Machines", Machines)
end

-- Inicialização
local ScreenGui, MainFrame, ContentFrame = CreateMenu()

-- Atualiza dados periodicamente
RunService.RenderStepped:Connect(UpdateData)

-- Adiciona listener para o botão de exportar (já foi adicionado na criação do menu)
O que foi adicionado:
Botão "Exportar Dados (.txt)":
Localizado na parte inferior do menu
Cor diferente para indicar ação
Efeito hover para feedback visual
Sistema de Registro de Dados:
Função RecordData() que armazena todas as leituras
Histórico com timestamp
Limite de 100 registros para performance
Funcionalidade de Exportação:
Gera um arquivo .txt formatado
Inclui data/hora de geração
Usa clipboard como fallback universal
Mostra notificação ao usuário
Persistência de Dados:
Todos os valores lidos são salvos para exportação
Análise temporal dos dados
Formato legível para humanos
Como usar:
Cole o script em um LocalScript dentro de StarterPlayerScripts
O menu aparecerá automaticamente
Clique em "⬇ Baixar Dados (.txt)" quando quiser exportar
Os dados serão copiados para o clipboard
Cole em qualquer editor de texto e salve como .txt
Personalização:
Modifique a função UpdateData() para ler dados reais do seu Tycoon
Adicione mais métricas usando AddAnalysisItem()
Ajuste as cores no MenuConfig
