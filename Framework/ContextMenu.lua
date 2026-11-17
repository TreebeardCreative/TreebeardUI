local _, private = ...
if private.__TBUISkip or private.__TreebeardUISkip then return end
local TBU = (private.__TBUIRuntime or private.__TreebeardUIRuntime) or private
local Styles = TBU.WindowStyles

local ContextMenu = {}
TBU.ContextMenu = ContextMenu

-- A consumer provides labels and actions; the menu owns only presentation.
function ContextMenu:Create(owner)
    local menu = TBU:CreateBackdropFrame("Frame", UIParent)
    menu.storageOwner = owner
    menu:SetFrameStrata("TOOLTIP")
    menu:SetClampedToScreen(true)
    menu:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8", edgeFile="Interface\\Buttons\\WHITE8X8",
        edgeSize=1, insets={left=0,right=0,top=0,bottom=0}})
    local function repaint(target)
        local style = Styles:GetForFrame(target)
        target:SetBackdropColor(unpack(Styles:GetControlInputCanvasColor(style)))
        target:SetBackdropBorderColor(unpack(Styles:GetControlBorderColor(style)))
    end
    Styles:RegisterVisual(menu, repaint)
    repaint(menu)
    menu:Hide()
    menu.buttons = {}
    menu.title = menu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    menu.title:SetJustifyH("LEFT")
    menu.title:SetJustifyV("MIDDLE")
    menu.title:Hide()
    menu:SetScript("OnUpdate", function(self)
        if self.justOpened then self.justOpened = false; return end
        local down = IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")
        if down and not self.wasDown and not self:IsMouseOver() then self:Hide() end
        self.wasDown = down
    end)
    function menu:Open(anchor, title, entries)
        -- Keep the original Open(anchor, entries) signature valid for consumers.
        if type(title) == "table" and entries == nil then
            entries = title
            title = nil
        end
        self:Hide()
        for _, button in ipairs(self.buttons) do button:Hide() end
        local height, padding, buttonGap = 23, 8, 4
        local count = 0
        local widestContent, widestButton = 0, 0
        local buttonWidths = {}
        local hasTitle = type(title) == "string" and title ~= ""
        if hasTitle then
            self.title:SetText(title)
            self.title:SetTextColor(unpack(Styles:GetTextColor("primary", self.title)))
            self.title:Show()
            widestContent = math.ceil(self.title:GetStringWidth() or 0)
        else
            self.title:SetText("")
            self.title:Hide()
        end
        for _, entry in ipairs(entries or {}) do
            if type(entry.label) == "string" and type(entry.action) == "function" then
                count = count + 1
                local button = self.buttons[count]
                if not button then
                    button = Styles:CreateButton(self, "", 1, function(b)
                        local action = b.action
                        self:Hide()
                        if action then action() end
                    end)
                    self.buttons[count] = button
                end
                button.action = entry.action
                button.label:SetText(entry.label)
                local contentWidth = math.ceil(button.label:GetStringWidth() or 0) + 16
                buttonWidths[count] = contentWidth
                widestButton = math.max(widestButton, contentWidth)
                widestContent = math.max(widestContent, contentWidth)
                button:ClearAllPoints()
                button:Show()
            end
        end
        if count == 0 or not anchor then return false end
        local minWidth = 150
        local maxWidth = math.max(minWidth, (UIParent:GetWidth() or 1280) - padding * 2)
        local width = math.min(maxWidth, math.max(minWidth, widestContent + padding * 2))
        local maxButtonWidth = math.max(1, math.min(maxWidth - padding * 2, widestButton))
        local titleHeight = hasTitle and 16 or 0
        local titleGap = hasTitle and 6 or 0
        local buttonTop = padding + titleHeight + titleGap
        if hasTitle then
            self.title:ClearAllPoints()
            self.title:SetPoint("TOPLEFT", self, "TOPLEFT", padding, -padding)
            self.title:SetWidth(width - padding * 2)
        end
        for index = 1, count do
            local button = self.buttons[index]
            button:SetWidth(math.min(maxButtonWidth, buttonWidths[index] or maxButtonWidth))
            button:ClearAllPoints()
            button:SetPoint("TOP", self, "TOP", 0,
                -buttonTop - (index - 1) * (height + buttonGap))
        end
        local contentHeight = titleHeight + titleGap + count * height
            + math.max(0, count - 1) * buttonGap
        self:SetSize(width, padding * 2 + contentHeight)
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, 0)
        self.wasDown = true
        self.justOpened = true
        self:Show()
        return true
    end
    return menu
end
