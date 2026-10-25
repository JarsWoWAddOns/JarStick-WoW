-- JarStick options window: tabs, couch sized fonts, same palette as the other Jars addons

local ADDON, ns = ...

local PALETTE = {
    bg = { 0.10, 0.10, 0.12, 0.95 },
    header = { 0.15, 0.15, 0.18, 1 },
    tab = { 0.14, 0.14, 0.17, 1 },
    accent = { 1.0, 0.55, 0.0, 1 },
    text = { 0.95, 0.95, 0.95, 1 },
    textDim = { 0.70, 0.70, 0.70, 1 },
    border = { 0.20, 0.20, 0.22, 1 },
    track = { 0.25, 0.25, 0.28, 1 },
}
local BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
}

local W, PAD = 470, 14
local TABS = { "Controls", "Layout", "Bars", "Menus", "Profiles" }

local frame
local pages = {}
local widgets = {}
local P -- page currently being filled

local function RefreshAll()
    for _, w in ipairs(widgets) do
        w:Refresh()
    end
end

local function PageOptions(pages)
    local list = {}
    for _, p in ipairs(ns.PAGES) do
        if not pages or pages[p.page] then
            list[#list + 1] = { value = p.page, text = p.name .. "  (slots " .. p.slots .. ")" }
        end
    end
    return list
end

-- the real bars, no stance/vehicle pages
local BAR_PAGES = { [1] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true, [13] = true, [14] = true, [15] = true }

-- widgets -------------------------------------------------------------------

local function NextY(gap)
    P.y = P.y - gap
    return P.y
end

local function AddHeader(text)
    NextY(28)
    local hdr = P.content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    hdr:SetPoint("TOPLEFT", PAD, P.y)
    hdr:SetTextColor(unpack(PALETTE.accent))
    hdr:SetText(text:upper())
    local line = P.content:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("LEFT", hdr, "RIGHT", 10, 0)
    line:SetPoint("RIGHT", P.content, "RIGHT", -PAD, 0)
    line:SetColorTexture(PALETTE.accent[1], PALETTE.accent[2], PALETTE.accent[3], 0.3)
    NextY(14)
end

-- wrapped text, advances by its real height so nothing overlaps
local function AddNote(text)
    NextY(4)
    local fs = P.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("TOPLEFT", PAD + 4, P.y)
    fs:SetWidth(W - PAD * 2 - 8)
    fs:SetJustifyH("LEFT")
    fs:SetTextColor(unpack(PALETTE.textDim))
    fs:SetText(text)
    NextY(math.max(fs:GetStringHeight(), 16) + 10)
end

local function SmallButton(parent, text, width)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(width or 26, 26)
    b:SetBackdrop(BACKDROP)
    b:SetBackdropColor(unpack(PALETTE.tab))
    b:SetBackdropBorderColor(unpack(PALETTE.border))
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    b.text:SetPoint("CENTER")
    b.text:SetText(text)
    b:SetScript("OnEnter", function(self) self:SetBackdropColor(0.20, 0.20, 0.24, 1) end)
    b:SetScript("OnLeave", function(self) self:SetBackdropColor(unpack(PALETTE.tab)) end)
    return b
end

local function AddButton(text, onClick)
    NextY(34)
    local b = SmallButton(P.content, text, 300)
    b:SetPoint("TOPLEFT", PAD + 2, P.y)
    b:SetScript("OnClick", onClick)
    NextY(4)
    return b
end

-- acc is { get = fn, set = fn }, one table so it survives being a middle argument
local function AddCheck(text, acc)
    NextY(32)
    local b = CreateFrame("Button", nil, P.content)
    b:SetSize(W - PAD * 2, 26)
    b:SetPoint("TOPLEFT", PAD, P.y)
    b.border = b:CreateTexture(nil, "BACKGROUND")
    b.border:SetSize(24, 24)
    b.border:SetPoint("LEFT", 1, 0)
    b.border:SetColorTexture(unpack(PALETTE.border))
    b.box = b:CreateTexture(nil, "ARTWORK")
    b.box:SetPoint("TOPLEFT", b.border, 1, -1)
    b.box:SetPoint("BOTTOMRIGHT", b.border, -1, 1)
    b.box:SetColorTexture(unpack(PALETTE.tab))
    b.check = b:CreateTexture(nil, "OVERLAY")
    b.check:SetPoint("TOPLEFT", b.border, 6, -6)
    b.check:SetPoint("BOTTOMRIGHT", b.border, -6, 6)
    b.check:SetColorTexture(unpack(PALETTE.accent))
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    b.text:SetPoint("LEFT", b.border, "RIGHT", 10, 0)
    b.text:SetPoint("RIGHT", b, "RIGHT", 0, 0)
    b.text:SetJustifyH("LEFT")
    b.text:SetText(text)
    b.Refresh = function(self)
        self.check:SetShown(acc.get() and true or false)
    end
    b:SetScript("OnClick", function()
        acc.set(not acc.get())
        RefreshAll()
    end)
    b:SetScript("OnEnter", function(self) self.box:SetColorTexture(0.20, 0.20, 0.24, 1) end)
    b:SetScript("OnLeave", function(self) self.box:SetColorTexture(unpack(PALETTE.tab)) end)
    table.insert(widgets, b)
    return b
end

-- label + typed value on one row, -/slider/+ on the next
local function AddSlider(label, acc, minV, maxV, step, decimals, enabledFn)
    local w = {}
    NextY(26)
    w.label = P.content:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    w.label:SetPoint("TOPLEFT", PAD + 2, P.y)
    w.label:SetText(label)

    w.box = CreateFrame("EditBox", nil, P.content, "InputBoxTemplate")
    w.box:SetSize(72, 24)
    w.box:SetPoint("TOPRIGHT", P.content, "TOPRIGHT", -PAD - 4, P.y + 4)
    w.box:SetAutoFocus(false)
    w.box:SetJustifyH("RIGHT")
    w.box:SetFontObject("GameFontHighlightLarge")
    NextY(30)

    w.minus = SmallButton(P.content, "-")
    w.minus:SetPoint("TOPLEFT", PAD + 2, P.y)
    w.plus = SmallButton(P.content, "+")
    w.plus:SetPoint("TOPRIGHT", P.content, "TOPRIGHT", -PAD - 4, P.y)

    local s = CreateFrame("Slider", nil, P.content)
    w.slider = s
    s:SetPoint("LEFT", w.minus, "RIGHT", 12, 0)
    s:SetPoint("RIGHT", w.plus, "LEFT", -12, 0)
    s:SetHeight(26)
    s:SetOrientation("HORIZONTAL")
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)
    local track = s:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    track:SetHeight(5)
    track:SetColorTexture(unpack(PALETTE.track))
    s:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
    local thumb = s:GetThumbTexture()
    thumb:SetSize(12, 24)
    thumb:SetVertexColor(unpack(PALETTE.accent))
    NextY(32)

    local fmt = "%." .. decimals .. "f"
    local function Commit(v)
        v = math.floor(v / step + 0.5) * step
        v = math.max(minV, math.min(maxV, v))
        acc.set(v)
        RefreshAll()
    end
    w.Refresh = function(self)
        local v = acc.get()
        s:SetValue(v)
        self.box:SetText(string.format(fmt, v))
        self.box:SetCursorPosition(0)
        local on = not enabledFn or enabledFn()
        if on then s:Enable() else s:Disable() end
        self.box:SetEnabled(on)
        self.minus:SetEnabled(on)
        self.plus:SetEnabled(on)
        local a = on and 1 or 0.4
        self.label:SetAlpha(a)
        s:SetAlpha(a)
        self.box:SetAlpha(a)
        self.minus:SetAlpha(a)
        self.plus:SetAlpha(a)
    end
    s:SetScript("OnValueChanged", function(_, v, user)
        if user then Commit(v) end
    end)
    w.box:SetScript("OnEnterPressed", function(self)
        local v = tonumber(self:GetText())
        if v then Commit(v) else w:Refresh() end
        self:ClearFocus()
    end)
    w.box:SetScript("OnEscapePressed", function(self)
        w:Refresh()
        self:ClearFocus()
    end)
    w.minus:SetScript("OnClick", function() Commit(acc.get() - step) end)
    w.plus:SetScript("OnClick", function() Commit(acc.get() + step) end)
    table.insert(widgets, w)
    return w
end

-- options is a list, or a function returning one for lists that change
local function AddDropdown(label, acc, options, enabledFn)
    NextY(26)
    local lbl = P.content:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    lbl:SetPoint("TOPLEFT", PAD + 2, P.y)
    lbl:SetText(label)
    NextY(30)
    local dd = CreateFrame("DropdownButton", nil, P.content, "WowStyle1DropdownTemplate")
    dd:SetPoint("TOPLEFT", PAD + 2, P.y)
    dd:SetWidth(W - PAD * 2 - 4)
    dd:SetHeight(28)
    local function Options()
        return type(options) == "function" and options() or options
    end
    local function Text()
        for _, o in ipairs(Options()) do
            if o.value == acc.get() then return o.text end
        end
        return tostring(acc.get())
    end
    dd:SetDefaultText(Text())
    dd:SetupMenu(function(_, root)
        for _, o in ipairs(Options()) do
            root:CreateRadio(o.text,
                function() return acc.get() == o.value end,
                function()
                    acc.set(o.value)
                    RefreshAll()
                end)
        end
    end)
    dd.Refresh = function(self)
        self:SetDefaultText(Text())
        if self.GenerateMenu then self:GenerateMenu() end
        local on = not enabledFn or enabledFn()
        self:SetEnabled(on)
        self:SetAlpha(on and 1 or 0.4)
        lbl:SetAlpha(on and 1 or 0.4)
    end
    NextY(10)
    table.insert(widgets, dd)
    return dd
end

-- window --------------------------------------------------------------------

local function ShowTab(index)
    for i, page in ipairs(pages) do
        page.scroll:SetShown(i == index)
        local on = i == index
        page.tab:SetBackdropColor(on and PALETTE.accent[1] * 0.35 or PALETTE.tab[1], on and PALETTE.accent[2] * 0.35 or PALETTE.tab[2], on and 0.05 or PALETTE.tab[3], 1)
        page.tab:SetBackdropBorderColor(on and PALETTE.accent[1] or PALETTE.border[1], on and PALETTE.accent[2] or PALETTE.border[2], on and PALETTE.accent[3] or PALETTE.border[3], 1)
        page.tab.text:SetTextColor(unpack(on and PALETTE.text or PALETTE.textDim))
    end
end

local function NewPage(index, name)
    local page = {}
    page.tab = SmallButton(frame, name, 0)
    page.tab:SetHeight(30)
    page.tab:SetPoint("TOPLEFT", frame, "TOPLEFT", 12 + (index - 1) * 108, -42)
    page.tab:SetWidth(104)
    page.tab:SetScript("OnLeave", nil)
    page.tab:SetScript("OnEnter", nil)
    page.tab:SetScript("OnClick", function() ShowTab(index) end)

    page.scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    page.scroll:SetPoint("TOPLEFT", 12, -78)
    page.scroll:SetPoint("BOTTOMRIGHT", -30, 12)
    page.content = CreateFrame("Frame", nil, page.scroll)
    page.content:SetWidth(W)
    page.scroll:SetScrollChild(page.content)
    page.y = 0
    pages[index] = page
    return page
end

local function Build()
    local db = ns.db
    frame = CreateFrame("Frame", "JarStick_ConfigFrame", UIParent, "BackdropTemplate")
    frame:SetSize(560, 660)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetBackdrop(BACKDROP)
    frame:SetBackdropColor(unpack(PALETTE.bg))
    frame:SetBackdropBorderColor(unpack(PALETTE.border))
    table.insert(UISpecialFrames, "JarStick_ConfigFrame")

    local titleBar = frame:CreateTexture(nil, "OVERLAY")
    titleBar:SetPoint("TOPLEFT", 1, -1)
    titleBar:SetPoint("TOPRIGHT", -1, -1)
    titleBar:SetHeight(34)
    titleBar:SetColorTexture(unpack(PALETTE.header))
    local accent = frame:CreateTexture(nil, "OVERLAY")
    accent:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT")
    accent:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT")
    accent:SetHeight(2)
    accent:SetColorTexture(unpack(PALETTE.accent))
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    title:SetPoint("LEFT", titleBar, "LEFT", 14, 0)
    title:SetText("JarStick")
    title:SetTextColor(unpack(PALETTE.text))

    local closeBtn = CreateFrame("Button", nil, frame)
    closeBtn:SetSize(26, 26)
    closeBtn:SetPoint("TOPRIGHT", -5, -5)
    local closeBg = closeBtn:CreateTexture(nil, "BACKGROUND")
    closeBg:SetAllPoints()
    closeBg:SetColorTexture(0.05, 0.05, 0.05, 0.8)
    local closeText = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    closeText:SetPoint("CENTER", 0, 1)
    closeText:SetText("\195\151")
    closeText:SetTextColor(unpack(PALETTE.textDim))
    closeBtn:SetScript("OnEnter", function() closeText:SetTextColor(unpack(PALETTE.accent)) end)
    closeBtn:SetScript("OnLeave", function() closeText:SetTextColor(unpack(PALETTE.textDim)) end)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)

    for i, name in ipairs(TABS) do
        NewPage(i, name)
    end

    local function Key(key, after)
        return {
            get = function() return db[key] end,
            set = function(v)
                db[key] = v
                if after then after() end
            end,
        }
    end

    local function Pos(side, axis)
        return {
            get = function() return db[side][axis] or 0 end,
            set = function(v)
                db[side][axis] = v
                if db.mirror then ns.MirrorFrom(side) end
                ns.ApplyLayout()
            end,
        }
    end

    local function Page(key)
        return {
            get = function() return db.pages[key] end,
            set = function(v)
                db.pages[key] = v
                ns.RefreshPageDriver()
            end,
        }
    end

    local function SelectKey(key)
        return {
            get = function() return db.selectMenu[key] or "" end,
            set = function(v)
                db.selectMenu[key] = v
                ns.ApplySelectMenu()
            end,
        }
    end

    local halfW = math.floor(UIParent:GetWidth() / 2)
    local halfH = math.floor(UIParent:GetHeight() / 2)

    -- controls ---------------------------------------------------------
    P = pages[1]
    AddHeader("Sticks")
    AddDropdown("Mouse mode button (the other stick click jumps)", Key("mouseStick", ns.ApplyBindings), {
        { value = "R3", text = "R3 toggles mouse mode, L3 jumps" },
        { value = "L3", text = "L3 toggles mouse mode, R3 jumps" },
    })
    AddNote("In mouse mode the right stick moves the cursor, R1 left clicks and L1 right clicks.")

    AddHeader("Camera")
    AddCheck("Invert camera X", Key("invertX", ns.ApplyCamera))
    AddCheck("Invert camera Y", Key("invertY", ns.ApplyCamera))
    AddCheck("Camera-locked movement (stick back = backpedal)", Key("turnAlways", ns.ApplyCamera))
    AddNote("Off = Blizzard default: out of combat pulling back turns you around and runs forward.")
    AddSlider("Camera speed", Key("cameraSpeed", ns.ApplyCamera), 0.25, 3, 0.05, 2)
    AddCheck("Action cam", Key("actionCam", ns.ApplyActionCam))
    AddDropdown("Action cam mode", Key("actionCamMode", function()
        if db.actionCam then ns.ApplyActionCam() end
    end), {
        { value = "basic", text = "Basic" },
        { value = "full", text = "Full" },
    }, function() return db.actionCam end)
    AddNote("Same as /console actioncam basic or full. Applied on login while checked, off again when unchecked.")

    AddHeader("Select + right stick zoom")
    AddSlider("Zoom speed", Key("zoomSpeed"), 0.25, 3, 0.05, 2)
    AddCheck("Flip zoom direction", Key("zoomFlip"))

    AddHeader("Interact")
    AddCheck("Center crosshair (the X prompt under it stays either way)", Key("reticle", ns.UpdateReticle))
    AddSlider("Crosshair and prompt size", Key("reticleScale", ns.UpdateReticle), 0.5, 3, 0.1, 1)
    AddCheck("X interacts in combat too", Key("interactInCombat", ns.ApplyInteract))
    AddCheck("Blizzard's hand marker on the object you are facing", Key("objectIcon", ns.ApplyObjectIcon))
    AddNote("X uses the NPC or object in front of you. With a gossip, quest or loot window open the pad goes into menu mode: a legend shows what X / A / B / Y do and the d-pad moves the cursor.")

    AddHeader("Controller")
    AddDropdown("Use controller", Key("device", ns.ApplyDevice), function()
        local list = {
            { value = "", text = "Auto: one recognized pad, ignore a generic twin of it" },
            { value = "combined", text = "All controllers combined (Blizzard default)" },
        }
        for _, e in ipairs(ns.DeviceList()) do
            list[#list + 1] = { value = e.name, text = e.name .. (e.generic and "  (generic map)" or "") }
        end
        return list
    end)
    AddCheck("Force XInput driver (then /reload)", { get = ns.GetForceXInput, set = ns.SetForceXInput })
    AddButton("Print pad report to chat (/js pad)", ns.PadReport)
    AddNote("A pad on a wireless dongle can show up twice (XInput + DirectInput). Combined input then doubles every press and puts the triggers on a stick axis.")
    NextY(10)
    P.content:SetHeight(-P.y)

    -- layout -----------------------------------------------------------
    P = pages[2]
    AddHeader("Clusters")
    AddCheck("Lock clusters (unlock to drag them with the mouse)", Key("locked", ns.ApplyLock))
    AddCheck("Mirror the right cluster to the left one", Key("mirror", function()
        if db.mirror then
            ns.MirrorFrom("left")
            ns.ApplyLayout()
        end
    end))
    AddCheck("Show pad glyphs on the buttons", Key("showGlyphs", ns.RefreshGlyphs))
    AddSlider("Scale", Key("scale", ns.ApplyLayout), 0.5, 2, 0.05, 2)
    AddSlider("Left cluster X (from screen center)", Pos("left", "x"), -halfW, halfW, 1, 0)
    AddSlider("Left cluster Y (from screen center)", Pos("left", "y"), -halfH, halfH, 1, 0)
    AddSlider("Right cluster X", Pos("right", "x"), -halfW, halfW, 1, 0, function() return not db.mirror end)
    AddSlider("Right cluster Y", Pos("right", "y"), -halfH, halfH, 1, 0, function() return not db.mirror end)
    AddButton("Reset positions", function()
        ns.ResetPositions()
        RefreshAll()
    end)

    AddHeader("This window")
    AddSlider("Options window scale", Key("configScale", function() frame:SetScale(db.configScale) end), 0.8, 2, 0.05, 2)
    NextY(10)
    P.content:SetHeight(-P.y)

    -- bars -------------------------------------------------------------
    P = pages[3]
    AddHeader("Bars")
    AddCheck("Lock action bars (Blizzard setting, hold the pickup key to drag off a diamond)",
        { get = ns.GetLockActionBars, set = ns.SetLockActionBars })
    AddCheck("Hide Blizzard bars 1-3 (showing them again needs /reload)", Key("hideBlizzard", ns.ToggleHideBlizzard))
    AddNote("Binding: drag spells, items and macros from the spellbook or bags onto the diamonds. Hold L2 or R2 (or keyboard Shift / Ctrl) while dropping to fill the pages below. The L1 / R1 boxes tab target (L1 enemy, R1 friend) and become slots 9 and 10 of the page while L2 or R2 is held.")

    AddHeader("Party layer (hold R1)")
    AddNote("Tap R1 to tab through friends. Hold R1 and the d-pad targets party members 2 to 5, L1 targets yourself.")
    AddDropdown("Party health colors on the d-pad", Key("partyHealth"), {
        { value = "both", text = "Border and fill" },
        { value = "fill", text = "Fill only" },
        { value = "border", text = "Border only" },
        { value = "off", text = "Off" },
    })
    AddNote("Green 60%+, yellow 25-59%, red under 25%, black when dead. Border turns blue / purple / brown for a dispellable magic / curse / poison debuff when Blizzard lets addons read auras. Live while R1 is held.")

    AddHeader("Paging")
    local barPages = PageOptions(BAR_PAGES)
    local allPages = PageOptions()
    AddDropdown("L2 held shows", Page("l2"), barPages)
    AddDropdown("R2 held shows", Page("r2"), barPages)
    AddDropdown("Bonus bar 1 (cat form, stealth)", Page("b1"), allPages)
    AddDropdown("Bonus bar 2 (tree of life)", Page("b2"), allPages)
    AddDropdown("Bonus bar 3 (bear form)", Page("b3"), allPages)
    AddDropdown("Bonus bar 4 (moonkin)", Page("b4"), allPages)
    AddDropdown("Bonus bar 5 (skyriding)", Page("b5"), allPages)
    AddNote("Vehicles, possession and override bars always take over the diamonds, same as the stock bar.")
    NextY(10)
    P.content:SetHeight(-P.y)

    -- menus ------------------------------------------------------------
    P = pages[4]
    AddHeader("Select menu (hold Select)")
    AddNote("While Select is held the right stick still zooms and the eight buttons open these panels. A panel opened this way turns the cursor on, closing it turns it off. Map and Quest log are the same window.")
    local panels = {}
    for _, p in ipairs(ns.PANELS) do
        panels[#panels + 1] = { value = p.cmd, text = p.name }
    end
    AddDropdown("Select + d-pad up", SelectKey("PADDUP"), panels)
    AddDropdown("Select + d-pad right", SelectKey("PADDRIGHT"), panels)
    AddDropdown("Select + d-pad left", SelectKey("PADDLEFT"), panels)
    AddDropdown("Select + d-pad down", SelectKey("PADDDOWN"), panels)
    AddDropdown("Select + Y", SelectKey("PAD4"), panels)
    AddDropdown("Select + X", SelectKey("PAD3"), panels)
    AddDropdown("Select + B", SelectKey("PAD2"), panels)
    AddDropdown("Select + A", SelectKey("PAD1"), panels)

    AddHeader("Special layer (hold L2 + R2)")
    AddNote("Fixed, nothing can page over it: the d-pad toggles a raid marker on your target, X targets yourself, Y leaves the vehicle, A presses the extra action button, B summons a favorite mount or dismounts.")
    local marks = {}
    local names = { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull" }
    for i, n in ipairs(names) do
        marks[#marks + 1] = { value = i, text = "|TInterface\TargetingFrame\UI-RaidTargetingIcon_" .. i .. ":18|t  " .. n }
    end
    local function Mark(key)
        return {
            get = function() return db.marks[key] end,
            set = function(v)
                db.marks[key] = v
                ns.ApplyMarks()
            end,
        }
    end
    AddDropdown("L2 + R2 + d-pad up", Mark("PADDUP"), marks)
    AddDropdown("L2 + R2 + d-pad right", Mark("PADDRIGHT"), marks)
    AddDropdown("L2 + R2 + d-pad left", Mark("PADDLEFT"), marks)
    AddDropdown("L2 + R2 + d-pad down", Mark("PADDDOWN"), marks)

    AddHeader("Spare bar grids (L2 + R2 + L1 or R1)")
    AddNote("L2 + R2 + L1 opens a 3x4 grid of Action Bar 4 above the L1 box, L2 + R2 + R1 does the same with Action Bar 5 above R1. They stay open until toggled again, across reloads. While a grid is open the plain d-pad walks it and X uses the picked slot; L2 or R2 held still pages the d-pad as usual. Drag anything onto the grids like a normal bar.")
    NextY(10)
    P.content:SetHeight(-P.y)

    -- profiles ---------------------------------------------------------
    P = pages[5]
    AddHeader("Profiles")
    NextY(24)
    local profLabel = P.content:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    profLabel:SetPoint("TOPLEFT", PAD + 2, P.y)

    NextY(34)
    local nameBox = CreateFrame("EditBox", nil, P.content, "InputBoxTemplate")
    nameBox:SetSize(W - PAD * 2 - 110, 26)
    nameBox:SetPoint("TOPLEFT", PAD + 8, P.y)
    nameBox:SetAutoFocus(false)
    nameBox:SetFontObject("GameFontHighlightLarge")
    local saveBtn = SmallButton(P.content, "Save", 96)
    saveBtn:SetPoint("TOPRIGHT", P.content, "TOPRIGHT", -PAD - 4, P.y)
    saveBtn:SetScript("OnClick", function()
        ns.SaveProfile(nameBox:GetText())
        nameBox:ClearFocus()
    end)
    nameBox:SetScript("OnEnterPressed", function(self)
        ns.SaveProfile(self:GetText())
        self:ClearFocus()
    end)
    nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    NextY(36)
    local loadDD = CreateFrame("DropdownButton", nil, P.content, "WowStyle1DropdownTemplate")
    loadDD:SetPoint("TOPLEFT", PAD + 2, P.y)
    loadDD:SetSize(W - PAD * 2 - 110, 28)
    loadDD:SetDefaultText("Load a profile...")
    loadDD:SetupMenu(function(_, root)
        local names = ns.ProfileNames()
        if #names == 0 then
            root:CreateTitle("No saved profiles")
            return
        end
        for _, name in ipairs(names) do
            root:CreateButton(name, function() ns.LoadProfile(name) end)
        end
    end)
    local delBtn = SmallButton(P.content, "Delete", 96)
    delBtn:SetPoint("TOPRIGHT", P.content, "TOPRIGHT", -PAD - 4, P.y)
    delBtn:SetScript("OnClick", function()
        ns.DeleteProfile(nameBox:GetText())
    end)
    NextY(30)

    table.insert(widgets, {
        Refresh = function()
            local cur = ns.CurrentProfile()
            profLabel:SetText(cur and ("Profile: " .. cur) or "Profile: none (settings live on this character)")
            if not nameBox:HasFocus() then nameBox:SetText(cur or "") end
        end,
    })
    AddNote("Settings save per character. Save them as a named profile to reuse on other characters.")

    AddHeader("Commands")
    AddNote("/js, /jstick or /jarstick opens this window.\n/js lock | unlock | mouse | pad | ui | debug | reset | resetall\n/js save <name> | load <name> | delete <name> | list")

    AddHeader("Reset")
    AddButton("Reset EVERYTHING to JarStick defaults", ns.ResetAll)
    AddNote("Blizzard gamepad cvars back to stock, then JarStick's own settings and cvars re-applied fresh. Positions, paging, camera, all of it. Profiles are kept.")
    AddButton("Reset gamepad cvars to Blizzard defaults only", ns.ResetPadCVars)
    NextY(10)
    P.content:SetHeight(-P.y)

    ShowTab(1)
end

function JarStick_ToggleConfig()
    if frame and frame:IsShown() then
        frame:Hide()
    else
        JarStick_OpenConfig()
    end
end

-- entry point for JarsAddonConfig
function JarStick_OpenConfig()
    if not frame then Build() end
    frame:SetScale(ns.db.configScale or 1)
    RefreshAll()
    frame:Show()
end

ns.RefreshConfig = function()
    if frame and frame:IsShown() then RefreshAll() end
end
