-- JarStick: gamepad action bars, camera and cursor glue for WoW 12.1
-- Left stick moves, right stick looks. Dpad + face buttons are 8 action slots.
-- L2 flips to bar 2, R2 to bar 3. L1/R1 tab friend/enemy. L3 jumps.
-- R3 held + L3 toggles mouse mode (R1 left click, L1 right click). Select + right stick zooms. Start = Esc.

local ADDON, ns = ...

JarStickDB = JarStickDB or {}         -- account: named profiles
JarStickCharDB = JarStickCharDB or {} -- this character: live settings + last profile name

local defaults = {
    invertX = false,
    invertY = false,
    cameraSpeed = 1.0,
    turnAlways = true,      -- so the reticle aims where the character faces
    interactInCombat = false,
    reticle = true,
    reticleScale = 1.5,
    objectIcon = true,      -- blizzards marker on the soft interact object
    partyHealth = "both",   -- special layer party colors: border, fill, both, off
    zoomSpeed = 1.0,
    zoomFlip = false,
    rightStick = 2,         -- index into GamePadMappedState.sticks
    device = "",            -- "" auto, "combined", or a device name for GamePadSingleActiveID
    mouseStick = "R3",      -- which stick click toggles mouse mode, the other one jumps
    panels = { L = false, R = false }, -- spare bar grids open?
    panelSide = "L",        -- grid cursor
    panelIdx = 1,
    actionCam = false,
    actionCamMode = "basic",
    configScale = 1.25,     -- couch sized options window
    scale = 1.0,
    locked = true,
    mirror = true,          -- right cluster follows the left one
    hideBlizzard = true,
    showGlyphs = true,
    left = {},              -- x/y from screen center, filled on first run
    right = {},
    -- l2/r2: page shown while held. b1-b5: page per bonusbar state
    pages = { l2 = 6, r2 = 5, b1 = 7, b2 = 8, b3 = 9, b4 = 10, b5 = 11 },
    -- hold select: the 8 buttons open panels (right stick still zooms)
    -- L2+R2 + dpad: raid target icon index (1 star .. 8 skull)
    marks = { PADDUP = 7, PADDRIGHT = 8, PADDLEFT = 2, PADDDOWN = 3 }, -- cross, skull, circle, diamond
    selectMenu = {
        PADDUP = "TOGGLECHARACTER0", PADDRIGHT = "TOGGLEPROFESSIONBOOK",
        PADDLEFT = "TOGGLESPELLBOOK", PADDDOWN = "TOGGLETALENTS",
        PAD4 = "TOGGLEWORLDMAP", PAD3 = "OPENALLBAGS", PAD2 = "TOGGLEGROUPFINDER", PAD1 = "TOGGLECOLLECTIONS",
    },
}

-- panels the select menu can open, blizzard binding command + short label
ns.PANELS = {
    { cmd = "TOGGLECHARACTER0", name = "Character" },
    { cmd = "TOGGLESPELLBOOK", name = "Spellbook" },
    { cmd = "TOGGLETALENTS", name = "Talents" },
    { cmd = "TOGGLEPROFESSIONBOOK", name = "Professions" },
    { cmd = "TOGGLEACHIEVEMENT", name = "Achievements" },
    { cmd = "TOGGLEQUESTLOG", name = "Quest log" },
    { cmd = "TOGGLEGUILDTAB", name = "Guild" },
    { cmd = "TOGGLEGROUPFINDER", name = "Group finder" },
    { cmd = "TOGGLECOLLECTIONS", name = "Collections" },
    { cmd = "TOGGLEENCOUNTERJOURNAL", name = "Adventure guide" },
    { cmd = "TOGGLEWORLDMAP", name = "Map" },
    { cmd = "OPENALLBAGS", name = "Bags" },
    { cmd = "TOGGLESOCIAL", name = "Friends" },
    { cmd = "TOGGLEHOUSINGDASHBOARD", name = "Housing" },
    { cmd = "TOGGLEGAMEMENU", name = "Game menu" },
    { cmd = "", name = "Nothing" },
}

local function PanelName(cmd)
    for _, p in ipairs(ns.PANELS) do
        if p.cmd == cmd then return p.name end
    end
    return cmd
end
ns.PanelName = PanelName

-- L2 + R2 together is a fixed layer nothing else can page over
local SPECIAL = {
    -- dpad: raid markers here, the party targets live on the R1 hold layer
    PADDUP = { cmd = "TARGETPARTYMEMBER1", label = "Party 2", unit = "party1", mark = 1 },
    PADDRIGHT = { cmd = "TARGETPARTYMEMBER2", label = "Party 3", unit = "party2", mark = 2 },
    PADDLEFT = { cmd = "TARGETPARTYMEMBER3", label = "Party 4", unit = "party3", mark = 3 },
    PADDDOWN = { cmd = "TARGETPARTYMEMBER4", label = "Party 5", unit = "party4", mark = 4 },
    PAD3 = { cmd = "TARGETSELF", label = "Self" },
    PAD4 = { cmd = "VEHICLEEXIT", label = "Leave" },
    PAD1 = { cmd = "EXTRAACTIONBUTTON1", label = "Extra" },
    PAD2 = { click = "JarStickMount", label = "Mount" },
}
local SPECIAL_MODS = { ["CTRL-SHIFT-"] = true, ["ALT-CTRL-SHIFT-"] = true }
-- the random favorite spell cant be /cast by name, SummonByID(0) is blizzards own route
local MOUNT_MACRO = "/dismount [mounted]\n/stopmacro [mounted]\n/run C_MountJournal.SummonByID(0)"

-- action pages and which blizzard bar they are
ns.PAGES = {
    { page = 1,  name = "Action Bar 1",      slots = "1-12" },
    { page = 2,  name = "Page 2",            slots = "13-24" },
    { page = 3,  name = "Action Bar 4",      slots = "25-36" },
    { page = 4,  name = "Action Bar 5",      slots = "37-48" },
    { page = 5,  name = "Action Bar 3",      slots = "49-60" },
    { page = 6,  name = "Action Bar 2",      slots = "61-72" },
    { page = 7,  name = "Bonus page 7",      slots = "73-84" },
    { page = 8,  name = "Bonus page 8",      slots = "85-96" },
    { page = 9,  name = "Bonus page 9",      slots = "97-108" },
    { page = 10, name = "Bonus page 10",     slots = "109-120" },
    { page = 11, name = "Skyriding page 11", slots = "121-132" },
    { page = 12, name = "Possess page 12",   slots = "133-144" },
    { page = 13, name = "Action Bar 6",      slots = "145-156" },
    { page = 14, name = "Action Bar 7",      slots = "157-168" },
    { page = 15, name = "Action Bar 8",      slots = "169-180" },
}

local SIZE, GAP = 45, 4

-- slot within the page, in diagram order. dx/dy place the diamond (x in half steps)
-- 9 and 10 are the bumpers: tab targeting normally, slots 9/10 while L2 or R2 is held
local BUTTONS = {
    { key = "PADDUP",    cluster = "left",  dx = 0,  dy = 1 },
    { key = "PADDLEFT",  cluster = "left",  dx = -1, dy = 0 },
    { key = "PADDRIGHT", cluster = "left",  dx = 1,  dy = 0 },
    { key = "PADDDOWN",  cluster = "left",  dx = 0,  dy = -1 },
    { key = "PAD4",      cluster = "right", dx = 0,  dy = 1 },  -- Y / triangle
    { key = "PAD3",      cluster = "right", dx = -1, dy = 0 }, -- X / square
    { key = "PAD2",      cluster = "right", dx = 1,  dy = 0 },  -- B / circle
    { key = "PAD1",      cluster = "right", dx = 0,  dy = -1 }, -- A / cross
    -- { key = "PADLSHOULDER", cluster = "left",  dx = -2, dy = 1, target = "TARGETNEARESTFRIEND", color = { 0.2, 1, 0.2 }, panel = "L" },
    -- { key = "PADRSHOULDER", cluster = "right", dx = 2,  dy = 1, target = "TARGETNEARESTENEMY", color = { 1, 0.2, 0.2 }, panel = "R" },
    { key = "PADLSHOULDER", cluster = "left",  dx = -2, dy = 1, target = "TARGETNEARESTENEMY", color = { 1, 0.2, 0.2 }, panel = "L" },
    { key = "PADRSHOULDER", cluster = "right", dx = 2,  dy = 1, target = "TARGETNEARESTFRIEND", color = { 0.2, 1, 0.2 }, panel = "R" },
}
local NUM_BUTTONS = #BUTTONS

-- spare bars as 3x4 grids above the bumper boxes, toggled with L2+R2+L1 / R1
local PANELS = { L = { page = 3, anchor = 9 }, R = { page = 4, anchor = 10 } }
local PCOLS, PROWS = 4, 3

-- which page a modifier prefix pages to, nil for none / the special layer
local function PageMod(mod)
    local shift, ctrl = mod:find("SHIFT"), mod:find("CTRL")
    if shift and ctrl then return nil end
    if shift then return "l2" end
    if ctrl then return "r2" end
end

-- every modifier combo gets bound so a held L2/R2/R3 never swallows a press
local MODS = { "", "SHIFT-", "CTRL-", "ALT-", "CTRL-SHIFT-", "ALT-SHIFT-", "ALT-CTRL-", "ALT-CTRL-SHIFT-" }

-- cvars we own while loaded
local PAD_CVARS = {
    GamePadEmulateShift = "PADLTRIGGER",      -- L2
    GamePadEmulateCtrl = "PADRTRIGGER",       -- R2
    -- R1 doubles as alt: tap = target friend, hold = party layer on the dpad
    GamePadEmulateAlt = "PADRSHOULDER",
    GamePadEmulateEsc = "NONE",               -- start is bound to TOGGLEGAMEMENU instead, emulation never fired
    GamePadCursorLeftClick = "PADRSHOULDER",  -- R1 left clicks in mouse mode
    GamePadCursorRightClick = "PADLSHOULDER", -- L1 right clicks
    GamePadCursorAutoDisableSticks = 0,       -- keep moving while in mouse mode
    GamePadCursorAutoDisableJump = 0,
    GamePadCursorAutoEnable = 0,              -- only R3+L3 brings the cursor up, not every window
    GamePadCursorCentering = 0,
    SoftTargetInteract = 3,                   -- always pick the npc/object in front
    SoftTargetInteractArc = 1,                -- front arc, not dead center only
    SoftTargetIconInteract = 1,
}

local db
local clusters = {}
local buttons = {}
local driver, bindOwner, zoomer, UIHider
local hiddenBars = false

local HideBlizzardBars, ApplyBindings, ApplyLayout, ApplyAll

-- queue secure stuff til combat ends
local pendingSafe = {}
local function RunWhenSafe(key, fn)
    if InCombatLockdown() then
        pendingSafe[key] = fn
    else
        pendingSafe[key] = nil
        fn()
    end
end

local function FlushSafeQueue()
    for key, fn in pairs(pendingSafe) do
        pendingSafe[key] = nil
        fn()
    end
end

local function Print(msg)
    print("|cff66ccffJarStick|r: " .. msg)
end

-- debug lines also go to the saved vars so they can be read after a /reload
local function Log(msg)
    Print(msg)
    local log = JarStickDB.debugLog
    if not log then
        log = {}
        JarStickDB.debugLog = log
    end
    log[#log + 1] = date("%H:%M:%S ") .. msg
    while #log > 80 do
        table.remove(log, 1)
    end
end
ns.Log = Log

local function PageName(page)
    for _, p in ipairs(ns.PAGES) do
        if p.page == page then return p.name end
    end
    return "Page " .. tostring(page)
end

-- cvars ---------------------------------------------------------------------

-- blizzards hand icon over the object it thinks you are facing, handy for aiming
local function ApplyObjectIcon()
    C_CVar.SetCVar("SoftTargetIconGameObject", db.objectIcon and "1" or "0")
end

-- negative speed flips the axis
local function ApplyCamera()
    local s = db.cameraSpeed
    C_CVar.SetCVar("GamePadCameraYawSpeed", tostring(db.invertX and -s or s))
    C_CVar.SetCVar("GamePadCameraPitchSpeed", tostring(db.invertY and -s or s))
    if db.turnAlways then
        -- camera locked: char faces the camera, stick back = backpedal.
        -- face-movement has to be off or the two fight and you flip forward again
        C_CVar.SetCVar("GamePadTurnWithCamera", "2")
        C_CVar.SetCVar("GamePadFaceMovementMaxAngle", "180")
    else
        C_CVar.SetCVar("GamePadTurnWithCamera", C_CVar.GetCVarDefault("GamePadTurnWithCamera"))
        C_CVar.SetCVar("GamePadFaceMovementMaxAngle", C_CVar.GetCVarDefault("GamePadFaceMovementMaxAngle"))
    end
end

-- blizzards action cam presets, same as /console actioncam basic|full|off
local function ApplyActionCam(fromLogin)
    if not ConsoleExec then
        Print("ConsoleExec is gone, set action cam with /console actioncam basic")
        return
    end
    if db.actionCam then
        ConsoleExec("actioncam " .. (db.actionCamMode or "basic"))
    elseif not fromLogin then
        ConsoleExec("actioncam off")
    end
end

local function ApplyPadCVars()
    if not C_GamePad.IsEnabled() then
        C_CVar.SetCVar("GamePadEnable", "1")
        Print("gamepad input enabled, /js for options")
    end
    for cvar, value in pairs(PAD_CVARS) do
        C_CVar.SetCVar(cvar, tostring(value))
    end
    ApplyCamera()
    ApplyObjectIcon()
end

local function ResetPadCVars()
    local list = { "GamePadCameraYawSpeed", "GamePadCameraPitchSpeed", "GamePadTurnWithCamera",
        "GamePadFaceMovementMaxAngle", "GamePadSingleActiveID", "SoftTargetIconGameObject" }
    for cvar in pairs(PAD_CVARS) do
        table.insert(list, cvar)
    end
    for _, cvar in ipairs(list) do
        C_CVar.SetCVar(cvar, C_CVar.GetCVarDefault(cvar))
    end
    Print("gamepad cvars back to Blizzard defaults, disable the addon to keep them")
end

-- blizzards own "Lock Action Bars", it keeps LOCK_ACTIONBAR in sync off the cvar
local function GetLockActionBars()
    return C_CVar.GetCVarBool("lockActionBars")
end

local function SetLockActionBars(on)
    C_CVar.SetCVar("lockActionBars", on and "1" or "0")
end

-- xbox pads seen through directinput put the triggers on a stick axis
local function GetForceXInput()
    return C_CVar.GetCVarBool("GamePadForceXInput")
end

local function SetForceXInput(on)
    C_CVar.SetCVar("GamePadForceXInput", on and "1" or "0")
    Print("XInput " .. (on and "forced" or "not forced") .. ", /reload or replug the pad")
end

-- real devices, the combined one left out. generic = blizzard has no map for it
local function DeviceList()
    local list = {}
    local combined = C_GamePad.GetCombinedDeviceID()
    for _, id in ipairs(C_GamePad.GetAllDeviceIDs()) do
        if id ~= combined then
            local st = C_GamePad.GetDeviceMappedState(id)
            if st then
                list[#list + 1] = { id = id, name = st.name or ("Device " .. id), generic = (st.labelStyle == "Generic") }
            end
        end
    end
    return list
end

-- a pad on a dongle can show up twice (xinput + directinput). combined input then
-- doubles every press and puts the triggers on a stick axis, so pick one device
local lastPick
local function ApplyDevice()
    local list = DeviceList()
    local id, why = 0, nil
    if db.device == "combined" then
        why = "all controllers combined"
    elseif db.device ~= "" then
        for _, e in ipairs(list) do
            if e.name == db.device then id = e.id end
        end
        why = id > 0 and ("using " .. db.device) or ("'" .. db.device .. "' not connected, using combined input")
    elseif #list >= 2 then
        local pick, n = nil, 0
        for _, e in ipairs(list) do
            if not e.generic then
                n = n + 1
                pick = e
            end
        end
        if n == 1 then
            id = pick.id
            local others = {}
            for _, e in ipairs(list) do
                if e.id ~= id then others[#others + 1] = e.name end
            end
            why = "using " .. pick.name .. " only, ignoring " .. table.concat(others, ", ") .. " (same pad seen twice)"
        end
    end
    C_CVar.SetCVar("GamePadSingleActiveID", tostring(id))
    if why and why ~= lastPick then
        lastPick = why
        Print(why)
    end
end

-- /js pad: what the pad is and what each control sends, for sorting out bad axis maps
local function PadReport()
    -- also kept in the saved vars so it can be read after a /reload
    local report = {}
    JarStickDB.padReport = report
    local function Say(s)
        Print(s)
        report[#report + 1] = s
    end
    local ids = C_GamePad.GetAllDeviceIDs()
    Say(#ids .. " device(s), active id " .. tostring(C_GamePad.GetActiveDeviceID()))
    for _, id in ipairs(ids) do
        local st = C_GamePad.GetDeviceMappedState(id)
        local raw = C_GamePad.GetDeviceRawState(id)
        Say(string.format("  #%d %s  labels=%s  buttons=%d axes=%d sticks=%d  raw=%s (%d axes, %d buttons)",
            id, st and st.name or "?", st and tostring(st.labelStyle) or "?",
            st and st.buttonCount or 0, st and st.axisCount or 0, st and st.stickCount or 0,
            raw and raw.name or "?", raw and raw.rawAxisCount or 0, raw and raw.rawButtonCount or 0))
    end
    local cv = {}
    for _, name in ipairs({ "GamePadSingleActiveID", "GamePadTurnWithCamera", "GamePadFaceMovementMaxAngle",
        "GamePadFaceMovementMaxAngleCombat", "GamePadAnalogMovement", "GamePadForceXInput", "GamePadEmulateShift", "GamePadEmulateCtrl", "GamePadEmulateAlt", "GamePadEmulateTapWindowMs" }) do
        cv[#cv + 1] = name:gsub("^GamePad", "") .. "=" .. tostring(C_CVar.GetCVar(name))
    end
    Say("cvars: " .. table.concat(cv, " "))
    Say(string.format("softinteract: %s  PAD3 -> %s  PADFORWARD -> %s  SoftTargetInteract=%s arc=%s",
        (ns.HasSoftInteract and ns.HasSoftInteract()) and "yes" or "none", tostring(GetBindingAction("PAD3", true)),
        tostring(GetBindingAction("PADFORWARD", true)), tostring(C_CVar.GetCVar("SoftTargetInteract")),
        tostring(C_CVar.GetCVar("SoftTargetInteractArc"))))
    Say("group=" .. tostring(IsInGroup()) .. "  ALT-PADDUP -> " .. tostring(GetBindingAction("ALT-PADDUP", true)))
    Say("now hold R1, then press L2, then R2, then move the right stick. watching for 5 seconds")
    local seen, t = {}, 0
    local f = CreateFrame("Frame")
    f:SetScript("OnUpdate", function(self, elapsed)
        t = t + elapsed
        local st = C_GamePad.GetDeviceMappedState()
        for i, v in ipairs(st and st.axes or {}) do
            if math.abs(v) > 0.5 and not seen["a" .. i] then
                seen["a" .. i] = true
                Say(string.format("  axis %d (%s) = %.2f", i, tostring(C_GamePad.AxisIndexToConfigName(i - 1)), v))
            end
        end
        for i, s in ipairs(st and st.sticks or {}) do
            if (s.len or 0) > 0.5 and not seen["s" .. i] then
                seen["s" .. i] = true
                Say(string.format("  stick %d (%s) x=%.2f y=%.2f", i, tostring(C_GamePad.StickIndexToConfigName(i - 1)), s.x, s.y))
            end
        end
        for i, down in ipairs(st and st.buttons or {}) do
            if down and not seen["b" .. i] then
                seen["b" .. i] = true
                Say(string.format("  button %d (%s)", i, tostring(C_GamePad.ButtonIndexToBinding(i - 1))))
            end
        end
        -- which modifiers the game thinks are held
        for _, m in ipairs({ { "alt", IsAltKeyDown }, { "shift", IsShiftKeyDown }, { "ctrl", IsControlKeyDown } }) do
            if m[2]() and not seen[m[1]] then
                seen[m[1]] = true
                Say("  modifier held: " .. m[1])
            end
        end
        if t > 5 then
            self:SetScript("OnUpdate", nil)
            Say("pad report done")
        end
    end)
end

-- mouse mode ----------------------------------------------------------------

-- only R3+L3, /js mouse, or a panel opened from the select menu may turn the cursor on.
-- blizzard's game menu and loot window call SetGamePadCursorControl(true) themselves,
-- so veto anything we didnt ask for
local wantCursor = false

local function SetMouseMode(on)
    if on and CanGamePadControlCursor and not CanGamePadControlCursor() then return end
    wantCursor = on
    SetGamePadCursorControl(on)
end

local function ToggleMouseMode()
    SetMouseMode(not IsGamePadCursorControlEnabled())
end

hooksecurefunc("SetGamePadCursorControl", function(enable)
    if enable and not wantCursor then
        if ns.debug then Print("blizzard turned the cursor on, turning it back off") end
        SetGamePadCursorControl(false)
    elseif not enable and wantCursor then
        SetGamePadCursorControl(true)
    end
end)

local function UpdateModeLabel()
    local text = IsGamePadCursorControlEnabled() and "MOUSE" or ""
    for _, c in pairs(clusters) do
        c.mode:SetText(text)
    end
end

-- select + right stick zoom --------------------------------------------------

local function ZoomOnUpdate(self, elapsed)
    local state = C_GamePad.GetDeviceMappedState()
    local stick = state and state.sticks and state.sticks[db.rightStick]
    if not stick then return end
    local y = stick.y or 0
    if db.zoomFlip then y = -y end
    local step = math.abs(y) * db.zoomSpeed * elapsed * 15
    if y > 0.15 then
        CameraZoomIn(step)
    elseif y < -0.15 then
        CameraZoomOut(step)
    end
end

-- freeze the camera while select is held, the stick is a zoom wheel now
local function StartZoom()
    if zoomer:IsShown() then return end
    C_CVar.SetCVar("GamePadCameraYawSpeed", "0")
    C_CVar.SetCVar("GamePadCameraPitchSpeed", "0")
    zoomer:Show()
end

local function StopZoom()
    if not zoomer:IsShown() then return end
    zoomer:Hide()
    ApplyCamera()
end

-- buttons -------------------------------------------------------------------

-- blizz UpdateHotkeys looks for ACTIONBUTTON0, put the pad glyph there instead
local function UpdateGlyph(button)
    local hk = button.HotKey
    if not hk then return end
    local text = db.showGlyphs and GetBindingText(button.padKey, 1) or ""
    if button.side then
        -- the marker overlay carries the glyph while its up, dont show it twice
        button.side.glyph:SetText(text)
        if button.side:IsShown() then text = "" end
    end
    if text == "" then
        hk:SetText("")
        hk:Hide()
        return
    end
    hk:ClearAllPoints()
    hk:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
    hk:SetSize(button:GetWidth(), 16)
    hk:SetText(text)
    hk:Show()
end

local function RefreshGlyphs()
    for _, b in ipairs(buttons) do
        UpdateGlyph(b)
    end
end

-- only name the page when a trigger put us there
local overlay, selectHeld = nil, false
local function SetPageLabel(state)
    local page = tonumber(state)
    local p = db.pages
    local text = ""
    local paged = page and (page == p.l2 or page == p.r2)
    if overlay then
        text = overlay
    elseif paged then
        text = PageName(page):upper()
    end
    for _, c in pairs(clusters) do
        c.page:SetText(text)
    end
    -- bumper boxes: target markers normally, action slots 9/10 while paged
    for _, b in ipairs(buttons) do
        if b.side then
            b.side:SetShown(overlay ~= nil or not paged)
            UpdateGlyph(b)
        end
    end
end

local function OverlayLabel(key)
    if overlay == "SPECIAL" then
        local sp = SPECIAL[key]
        if sp and sp.mark then return "" end -- drawn as a texture instead
        return sp and sp.label or ""
    end
    if overlay == "PARTY" then
        local sp = SPECIAL[key]
        if sp and sp.unit then return sp.label end
        return ""
    end
    local name = PanelName(db.selectMenu[key] or "")
    return name ~= "Nothing" and name or ""
end

-- party health borders on the special layer. health is secret in combat, so the
-- curve does the thresholds engine side and we just pipe the color into a statusbar
local hpCurve
local function HealthCurve()
    if hpCurve then return hpCurve end
    local black, red = CreateColor(0, 0, 0, 1), CreateColor(1, 0.1, 0.1, 1)
    local yellow, green = CreateColor(1, 0.85, 0.1, 1), CreateColor(0.1, 1, 0.1, 1)
    hpCurve = C_CurveUtil.CreateColorCurve()
    -- tight point pairs = hard steps
    hpCurve:AddPoint(0, black)
    hpCurve:AddPoint(0.005, red)
    hpCurve:AddPoint(0.245, red)
    hpCurve:AddPoint(0.25, yellow)
    hpCurve:AddPoint(0.595, yellow)
    hpCurve:AddPoint(0.6, green)
    hpCurve:AddPoint(1, green)
    return hpCurve
end

-- dispellable debuff -> border color. aura data is secret while restricted
-- (combat, encounters, M+, pvp), only readable outside that
local DISPEL = {
    Magic = { 0.2, 0.6, 1 },
    Curse = { 0.6, 0.2, 1 },
    Poison = { 0.55, 0.35, 0.15 },
    Disease = { 0.55, 0.35, 0.15 },
}

local function DispelColor(unit)
    if C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() then return end
    local aura = C_UnitAuras.GetAuraDataByIndex(unit, 1, "HARMFUL|RAID_PLAYER_DISPELLABLE")
    if not aura or issecretvalue(aura.dispelName) then return end
    return DISPEL[aura.dispelName]
end

local function UpdatePartyHealth()
    local on = overlay == "PARTY"
    for _, b in ipairs(buttons) do
        local sp = b.hp and SPECIAL[b.padKey]
        if sp then
            local style = db.partyHealth or "both"
            if on and UnitExists(sp.unit) and style ~= "off" then
                local color = UnitHealthPercent(sp.unit, true, HealthCurve())
                if ns.debug and not b.hp:IsShown() then
                    ns.Log(string.format("party %s %s: color=%s", b.padKey, sp.unit, type(color)))
                end
                local dispel = DispelColor(sp.unit)
                if dispel then
                    b.hp:SetStatusBarColor(unpack(dispel))
                else
                    b.hp:SetStatusBarColor(color:GetRGB())
                end
                b.hpFill:SetStatusBarColor(color:GetRGB())
                b.hp:SetShown(dispel ~= nil or style == "border" or style == "both")
                b.hpFill:SetShown(style == "fill" or style == "both")
            else
                b.hp:Hide()
                b.hpFill:Hide()
            end
        end
    end
end

-- both triggers, or select, held: dim the icons and show what each button does instead
local function UpdateOverlay()
    local shift, ctrl, alt = IsShiftKeyDown(), IsControlKeyDown(), IsAltKeyDown()
    local want = (shift and ctrl) and "SPECIAL"
        or (alt and not shift and not ctrl) and "PARTY"
        or (selectHeld and "MENU") or nil
    if want == overlay then return end
    if ns.debug then
        ns.Log(string.format("overlay %s -> %s  shift=%s ctrl=%s alt=%s  group=%s  ALT-PADDUP -> %s",
            tostring(overlay), tostring(want), tostring(shift), tostring(ctrl), tostring(alt),
            tostring(IsInGroup()), tostring(GetBindingAction("ALT-PADDUP", true))))
    end
    overlay = want
    for _, b in ipairs(buttons) do
        local text = overlay and OverlayLabel(b.padKey) or ""
        b.special:SetText(text)
        b.special:SetShown(overlay ~= nil)
        -- party layer only dims the dpad it uses
        local dim = overlay and (overlay ~= "PARTY" or text ~= "")
        if b.icon then b.icon:SetAlpha(dim and 0.3 or 1) end
        if b.mark then
            local n = overlay == "SPECIAL" and db.marks[b.padKey]
            if n then b.mark:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. n) end
            b.mark:SetShown(n and true or false)
            -- hide the ability under the marker so it reads clean
            if n and b.icon then b.icon:SetAlpha(0) end
        end
        -- bumper boxes: up arrow while the special layer is held, they open the grids
        if b.side then
            if overlay == "SPECIAL" then
                -- Misc_ArrowLup, the red up arrow spell icon
                b.side.icon:SetTexture(450907)
                b.side.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                b.side.icon:SetVertexColor(1, 1, 1)
            elseif overlay == "PARTY" and b.padKey == "PADLSHOULDER" then
                -- Misc_ArrowDown: L1 targets yourself while R1 is held
                b.side.icon:SetTexture(450905)
                b.side.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                b.side.icon:SetVertexColor(1, 1, 1)
            else
                b.side.icon:SetTexture("Interface\\Cursor\\Crosshairs")
                b.side.icon:SetTexCoord(0, 1, 0, 1)
                b.side.icon:SetVertexColor(unpack(b.sideColor))
            end
        end
    end
    UpdatePartyHealth()
    SetPageLabel(driver and driver:GetAttribute("state-page"))
end

-- offsets from screen center in the clusters own scale, same trick as JarsUnitFrames
local function SavePos(c, key)
    local s = c:GetScale()
    local cx, cy = c:GetCenter()
    local ux, uy = UIParent:GetCenter()
    db[key] = { x = cx - ux / s, y = cy - uy / s }
end

local function MirrorFrom(key)
    local other = key == "left" and "right" or "left"
    db[other] = { x = -db[key].x, y = db[key].y }
end

local function DefaultPositions()
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    db.left = { x = -(w / 2 - 190), y = -(h / 2 - 230) }
    db.right = { x = w / 2 - 190, y = -(h / 2 - 230) }
end

local function CreateCluster(key, name)
    local f = CreateFrame("Frame", "JarStick" .. name, UIParent)
    f:SetSize(SIZE * 3 + GAP * 2, SIZE * 3 + GAP * 2)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if not db.locked then self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePos(self, key)
        if db.mirror then MirrorFrom(key) end
        ApplyLayout()
        if ns.RefreshConfig then ns.RefreshConfig() end
    end)

    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(0, 0.6, 1, 0.25)
    f.bg:Hide()

    f.page = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.page:SetPoint("BOTTOM", f, "TOP", 0, 2)

    f.mode = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.mode:SetPoint("TOP", f, "BOTTOM", 0, -2)
    f.mode:SetTextColor(0.2, 1, 0.2)
    return f
end

local function CreateButton(i, def)
    local parent = clusters[def.cluster]
    local b = CreateFrame("CheckButton", "JarStickButton" .. i, parent, "ActionBarButtonTemplate")
    b:SetSize(SIZE, SIZE)
    b:SetPoint("CENTER", parent, "CENTER", def.dx * (SIZE + GAP) / 2, def.dy * (SIZE + GAP))
    b.padKey = def.key
    b:SetAttribute("action", i)
    if b.UpdateHotkeys then
        hooksecurefunc(b, "UpdateHotkeys", UpdateGlyph)
    end
    UpdateGlyph(b)
    b.special = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.special:SetPoint("CENTER")
    b.special:SetWidth(SIZE - 2)
    b.special:SetWordWrap(true)
    b.special:Hide()

    -- dpad buttons: health colored border behind them for the special layer
    if SPECIAL[def.key] and SPECIAL[def.key].unit then
        local hp = CreateFrame("StatusBar", nil, parent)
        hp:SetPoint("TOPLEFT", b, "TOPLEFT", -4, 4)
        hp:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 4, -4)
        hp:SetFrameLevel(math.max(b:GetFrameLevel() - 1, 0))
        hp:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        hp:SetMinMaxValues(0, 1)
        hp:SetValue(1)
        hp:Hide()
        b.hp = hp

        -- fill: tinted wash over the dimmed icon, under the label
        local fill = CreateFrame("StatusBar", nil, b)
        fill:SetAllPoints()
        fill:SetFrameLevel(b:GetFrameLevel() + 2)
        fill:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        fill:SetMinMaxValues(0, 1)
        fill:SetValue(1)
        fill:SetAlpha(0.55)
        fill:Hide()
        b.hpFill = fill
        -- label lives on a frame above the wash so it stays readable
        local top = CreateFrame("Frame", nil, b)
        top:SetAllPoints()
        top:SetFrameLevel(b:GetFrameLevel() + 3)
        b.special:SetParent(top)
        -- raid marker shown big on the slot while L2+R2 are held
        b.mark = top:CreateTexture(nil, "OVERLAY")
        b.mark:SetPoint("CENTER")
        b.mark:SetSize(SIZE - 8, SIZE - 8)
        b.mark:Hide()
    end

    -- bumpers: a colored target marker sits over the slot until a page swap frees it
    if def.target then
        local s = CreateFrame("Frame", nil, b)
        s:SetAllPoints()
        s:SetFrameLevel(b:GetFrameLevel() + 5)
        s.bg = s:CreateTexture(nil, "BACKGROUND")
        s.bg:SetAllPoints()
        s.bg:SetColorTexture(0.05, 0.05, 0.05, 0.9)
        s.icon = s:CreateTexture(nil, "ARTWORK")
        s.icon:SetPoint("CENTER")
        s.icon:SetSize(SIZE - 10, SIZE - 10)
        s.icon:SetTexture("Interface\\Cursor\\Crosshairs")
        s.icon:SetVertexColor(unpack(def.color))
        s.glyph = s:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
        s.glyph:SetPoint("TOPRIGHT", s, "TOPRIGHT", 0, 0)
        s.glyph:SetSize(SIZE, 16)
        b.side = s
        b.sideColor = def.color
        UpdateGlyph(b)
    end
    return b
end

-- a 3x4 grid of one spare bar, parented to the cluster so it follows scale and position
local function CreatePanel(side, def)
    local anchorBtn = buttons[def.anchor]
    local f = CreateFrame("Frame", "JarStickPanel" .. side, anchorBtn:GetParent())
    f:SetSize(PCOLS * SIZE + (PCOLS - 1) * GAP, PROWS * SIZE + (PROWS - 1) * GAP)
    if side == "L" then
        f:SetPoint("BOTTOMRIGHT", anchorBtn, "TOPRIGHT", 0, GAP * 2)
    else
        f:SetPoint("BOTTOMLEFT", anchorBtn, "TOPLEFT", 0, GAP * 2)
    end
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetPoint("TOPLEFT", -4, 4)
    f.bg:SetPoint("BOTTOMRIGHT", 4, -4)
    f.bg:SetColorTexture(0, 0, 0, 0.5)
    f.buttons = {}
    for i = 1, PCOLS * PROWS do
        local b = CreateFrame("CheckButton", "JarStickPanel" .. side .. i, f, "ActionBarButtonTemplate")
        b:SetSize(SIZE, SIZE)
        local row, col = math.floor((i - 1) / PCOLS), (i - 1) % PCOLS
        b:SetPoint("TOPLEFT", f, "TOPLEFT", col * (SIZE + GAP), -row * (SIZE + GAP))
        b:SetAttribute("action", (def.page - 1) * 12 + i)
        f.buttons[i] = b
    end
    -- open state is remembered, the secure toggle in Interact.lua does the show/hide
    f:HookScript("OnShow", function()
        db.panels[side] = true
        if ns.PanelChanged then ns.PanelChanged() end
    end)
    f:HookScript("OnHide", function()
        db.panels[side] = false
        if ns.PanelChanged then ns.PanelChanged() end
    end)
    f:SetShown(db.panels[side] and true or false)
    return f
end

-- paging --------------------------------------------------------------------

local function PageDriver()
    local p = db.pages
    -- both triggers = special layer, dont page, fall through to the normal chain
    return "[mod:shift,nomod:ctrl] " .. p.l2 .. "; [mod:ctrl,nomod:shift] " .. p.r2 .. "; " ..
        "[overridebar][vehicleui][possessbar][shapeshift] possess; " ..
        "[bonusbar:5] " .. (p.b5 == 11 and "dragon" or p.b5) .. "; " ..
        "[bonusbar:4] " .. p.b4 .. "; [bonusbar:3] " .. p.b3 .. "; " ..
        "[bonusbar:2] " .. p.b2 .. "; [bonusbar:1] " .. p.b1 .. "; 1"
end

-- page swaps run in the restricted env so L2/R2 work in combat
local function CreateDriver()
    driver = CreateFrame("Frame", "JarStickDriver", UIParent, "SecureHandlerStateTemplate")
    for i = 1, NUM_BUTTONS do
        driver:SetFrameRef("button" .. i, buttons[i])
    end
    driver:SetAttribute("nbuttons", NUM_BUTTONS)
    driver:SetAttribute("_onstate-page", [[
        local page = newstate
        if page == "possess" or page == "dragon" then
            if HasVehicleActionBar() then
                page = GetVehicleBarIndex()
            elseif HasOverrideActionBar() then
                page = GetOverrideBarIndex()
            elseif HasTempShapeshiftActionBar() then
                page = GetTempShapeshiftBarIndex()
            elseif HasBonusActionBar() then
                page = GetBonusBarIndex()
            else
                page = 12
            end
        end
        page = tonumber(page) or 1
        for i = 1, self:GetAttribute("nbuttons") do
            local button = self:GetFrameRef("button" .. i)
            if button then
                button:SetAttribute("action", (page - 1) * 12 + i)
            end
        end
    ]])
    driver:HookScript("OnAttributeChanged", function(_, name, value)
        if name == "state-page" then SetPageLabel(value) end
    end)
    RegisterStateDriver(driver, "page", PageDriver())
end

local function RefreshPageDriver()
    RunWhenSafe("pagedriver", function()
        if not driver then return end
        UnregisterStateDriver(driver, "page")
        RegisterStateDriver(driver, "page", PageDriver())
    end)
end

-- invisible buttons the pad bindings click into
local function CreateHelperButton(name, down, up)
    local b = CreateFrame("Button", name, UIParent)
    b:SetSize(1, 1)
    b:SetPoint("TOPLEFT")
    b:SetAlpha(0)
    b:EnableMouse(false)
    b:RegisterForClicks("AnyDown", "AnyUp")
    b:SetScript("OnClick", function(_, _, isDown)
        if isDown then
            down()
        elseif up then
            up()
        end
    end)
    return b
end

-- all non-priority, the interact/menu handler in Interact.lua sits on top with priority ones
ApplyBindings = function()
    RunWhenSafe("bindings", function()
        ClearOverrideBindings(bindOwner)
        local mouseKey = db.mouseStick == "L3" and "PADLSTICK" or "PADRSTICK"
        local jumpKey = db.mouseStick == "L3" and "PADRSTICK" or "PADLSTICK"
        for _, mod in ipairs(MODS) do
            for i, def in ipairs(BUTTONS) do
                local sp = SPECIAL_MODS[mod] and SPECIAL[def.key]
                local party = mod == "ALT-"
                if party and def.key == "PADLSHOULDER" then
                    -- R1 held + L1 = target self
                    SetOverrideBinding(bindOwner, false, mod .. def.key, "TARGETSELF")
                elseif party and SPECIAL[def.key] and SPECIAL[def.key].unit then
                    -- R1 held: dpad picks party members, same as the L2+R2 layer
                    SetOverrideBinding(bindOwner, false, mod .. def.key, SPECIAL[def.key].cmd)
                elseif def.panel and SPECIAL_MODS[mod] then
                    -- L2+R2+bumper toggles that sides spare bar grid
                    SetOverrideBindingClick(bindOwner, false, mod .. def.key, "JarStickPanelToggle" .. def.panel, "LeftButton")
                elseif def.target and not PageMod(mod) then
                    -- bumpers tab target unless a page is held
                    SetOverrideBinding(bindOwner, false, mod .. def.key, def.target)
                elseif sp and sp.mark then
                    -- L2+R2 + dpad: toggle a raid marker on the target
                    SetOverrideBindingClick(bindOwner, false, mod .. def.key, "JarStickMark" .. sp.mark, "LeftButton")
                elseif sp and sp.click then
                    SetOverrideBindingClick(bindOwner, false, mod .. def.key, sp.click, "LeftButton")
                elseif sp then
                    SetOverrideBinding(bindOwner, false, mod .. def.key, sp.cmd)
                else
                    SetOverrideBindingClick(bindOwner, false, mod .. def.key, "JarStickButton" .. i, "LeftButton")
                end
            end
            -- same command the Escape key runs
            SetOverrideBinding(bindOwner, false, mod .. "PADFORWARD", "TOGGLEGAMEMENU")
            SetOverrideBindingClick(bindOwner, false, mod .. "PADBACK", "JarStickSelect", "LeftButton")
            SetOverrideBindingClick(bindOwner, false, mod .. mouseKey, "JarStickMouseToggle", "LeftButton")
            SetOverrideBinding(bindOwner, false, mod .. jumpKey, "JUMP")
        end
    end)
end

ApplyLayout = function()
    RunWhenSafe("layout", function()
        -- first run, or the old corner-anchored format
        if not db.left.x or db.left.point or not db.right.x or db.right.point then
            DefaultPositions()
        end
        for key, c in pairs(clusters) do
            local pos = db[key]
            c:SetScale(db.scale)
            c:ClearAllPoints()
            c:SetPoint("CENTER", UIParent, "CENTER", pos.x, pos.y)
        end
    end)
end

local function ResetPositions()
    DefaultPositions()
    ApplyLayout()
end

local function ApplyLock()
    for _, c in pairs(clusters) do
        c:EnableMouse(not db.locked)
        c.bg:SetShown(not db.locked)
    end
end

-- hide blizzard bars 1-3, Bartender4 HideBlizzard style. one way per session
local function PurgeKey(t, k)
    t[k] = nil
    local c = 42
    repeat
        if t[c] == nil then
            t[c] = nil
        end
        c = c + 1
    until issecurevariable(t, k)
end

local function HideBarFrame(frame, clearEvents)
    if not frame then return end
    if clearEvents then
        frame:UnregisterAllEvents()
    end
    if frame.system then
        PurgeKey(frame, "isShownExternal")
    end
    if frame.HideBase then
        frame:HideBase()
    else
        frame:Hide()
    end
    frame:SetParent(UIHider)
end

local function HideBarButton(button)
    if not button then return end
    button:Hide()
    button:UnregisterAllEvents()
    button:SetAttribute("statehidden", true)
    button.bar = nil
end

HideBlizzardBars = function()
    if hiddenBars or not db.hideBlizzard then return end
    RunWhenSafe("hidebars", function()
        if hiddenBars then return end
        hiddenBars = true
        UIHider = CreateFrame("Frame")
        UIHider:Hide()

        HideBarFrame(MainMenuBar, false)   -- <= 11.2.5
        HideBarFrame(MainActionBar, false) -- >= 12.0
        for i = 1, 12 do
            HideBarButton(_G["ActionButton" .. i])
        end
        if MainMenuBar then
            MainMenuBar:UnregisterEvent("PLAYER_REGEN_ENABLED")
            MainMenuBar:UnregisterEvent("PLAYER_REGEN_DISABLED")
            MainMenuBar:UnregisterEvent("ACTIONBAR_SHOWGRID")
            MainMenuBar:UnregisterEvent("ACTIONBAR_HIDEGRID")
        end

        HideBarFrame(MultiBarBottomLeft, true)
        HideBarFrame(MultiBarBottomRight, true)
        for i = 1, 12 do
            HideBarButton(_G["MultiBarBottomLeftButton" .. i])
            HideBarButton(_G["MultiBarBottomRightButton" .. i])
        end
    end)
end

local function ToggleHideBlizzard()
    if db.hideBlizzard then
        HideBlizzardBars()
    elseif hiddenBars then
        Print("Blizzard bars come back after a /reload")
    end
end

ApplyAll = function()
    ApplyCamera()
    ApplyActionCam()
    ApplyLayout()
    ApplyLock()
    ApplyBindings()
    RefreshGlyphs()
    RefreshPageDriver()
    ToggleHideBlizzard()
    if ns.ApplyInteract then ns.ApplyInteract() end
    if ns.ApplySelectMenu then ns.ApplySelectMenu() end
    if ns.UpdateReticle then ns.UpdateReticle() end
end

-- profiles ------------------------------------------------------------------
-- live settings are per character, named profiles are account wide copies

local function CopyTable(src)
    local t = {}
    for k, v in pairs(src) do
        t[k] = type(v) == "table" and CopyTable(v) or v
    end
    return t
end

local function MergeDefaults(t)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            t[k] = t[k] or {}
            for k2, v2 in pairs(v) do
                if t[k][k2] == nil then t[k][k2] = v2 end
            end
        elseif t[k] == nil then
            t[k] = v
        end
    end
end

-- back to a clean slate: blizzard cvars, then JarStick defaults on top
local function ResetAll()
    ResetPadCVars()
    wipe(db)
    MergeDefaults(db)
    JarStickCharDB.profile = nil
    ApplyPadCVars()
    ApplyDevice()
    ApplyAll()
    Print("everything reset to JarStick defaults")
    if ns.RefreshConfig then ns.RefreshConfig() end
end

local function ProfileNames()
    local names = {}
    for name in pairs(JarStickDB.profiles) do
        names[#names + 1] = name
    end
    table.sort(names)
    return names
end

local function SaveProfile(name)
    name = strtrim(name or "")
    if name == "" then
        Print("give the profile a name")
        return false
    end
    JarStickDB.profiles[name] = CopyTable(db)
    JarStickCharDB.profile = name
    Print("profile '" .. name .. "' saved")
    if ns.RefreshConfig then ns.RefreshConfig() end
    return true
end

local function LoadProfile(name)
    name = strtrim(name or "")
    local src = JarStickDB.profiles[name]
    if not src then
        Print("no profile called '" .. name .. "'")
        return false
    end
    -- same table, Interact.lua and Config.lua hold a ref to it
    wipe(db)
    for k, v in pairs(CopyTable(src)) do
        db[k] = v
    end
    MergeDefaults(db)
    JarStickCharDB.profile = name
    ApplyAll()
    Print("profile '" .. name .. "' loaded")
    if ns.RefreshConfig then ns.RefreshConfig() end
    return true
end

local function DeleteProfile(name)
    name = strtrim(name or "")
    if not JarStickDB.profiles[name] then
        Print("no profile called '" .. name .. "'")
        return false
    end
    JarStickDB.profiles[name] = nil
    if JarStickCharDB.profile == name then
        JarStickCharDB.profile = nil
    end
    Print("profile '" .. name .. "' deleted")
    if ns.RefreshConfig then ns.RefreshConfig() end
    return true
end

-- setup ---------------------------------------------------------------------

local function ApplyMarks()
    RunWhenSafe("marks", function()
        for key, sp in pairs(SPECIAL) do
            local m = sp.mark and _G["JarStickMark" .. sp.mark]
            if m then m:SetAttribute("macrotext", "/tm " .. (db.marks[key] or 8)) end
        end
    end)
end

-- select held: zoom on the stick, panel shortcuts on the buttons (Interact.lua binds them)
local function OnSelectDown()
    selectHeld = true
    UpdateOverlay()
    if ns.SelectLayer then ns.SelectLayer(true) end
    StartZoom()
end

local function OnSelectUp()
    selectHeld = false
    UpdateOverlay()
    if ns.SelectLayer then ns.SelectLayer(false) end
    StopZoom()
end

-- a panel opened while select is held gets the cursor, closing it takes it away again
local cursorPanel
local function PanelShown(frame)
    if not selectHeld or not frame or frame == cursorPanel then return end
    cursorPanel = frame
    if not frame.jarstickHooked then
        frame.jarstickHooked = true
        frame:HookScript("OnHide", function(self)
            if cursorPanel == self then
                cursorPanel = nil
                SetMouseMode(false)
            end
        end)
    end
    SetMouseMode(true)
end

local function HookPanels()
    hooksecurefunc("ShowUIPanel", PanelShown)
    -- bags and the game menu dont go through the panel manager
    for _, name in ipairs({ "ContainerFrameCombinedBags", "ContainerFrame1", "GameMenuFrame" }) do
        local f = _G[name]
        if f then
            f:HookScript("OnShow", PanelShown)
        end
    end
end

local function Init()
    clusters.left = CreateCluster("left", "Left")
    clusters.right = CreateCluster("right", "Right")
    for i, def in ipairs(BUTTONS) do
        buttons[i] = CreateButton(i, def)
    end
    ns.panels = {}
    for side, def in pairs(PANELS) do
        ns.panels[side] = CreatePanel(side, def)
    end

    bindOwner = CreateFrame("Frame", "JarStickBindings", UIParent)

    -- special layer B: favorite mount, or dismount
    local mount = CreateFrame("Button", "JarStickMount", UIParent, "SecureActionButtonTemplate")
    mount:SetAttribute("type", "macro")
    mount:SetAttribute("macrotext", MOUNT_MACRO)
    mount:RegisterForClicks("AnyDown")

    -- raid markers for the special layer dpad, /tm toggles it on the target
    for key, sp in pairs(SPECIAL) do
        if sp.mark then
            local m = CreateFrame("Button", "JarStickMark" .. sp.mark, UIParent, "SecureActionButtonTemplate")
            m:SetAttribute("type", "macro")
            m:RegisterForClicks("AnyDown")
            m.padKey = key
        end
    end
    ApplyMarks()

    CreateHelperButton("JarStickSelect", OnSelectDown, OnSelectUp)
    CreateHelperButton("JarStickMouseToggle", ToggleMouseMode)
    zoomer = CreateFrame("Frame")
    zoomer:Hide()
    zoomer:SetScript("OnUpdate", ZoomOnUpdate)

    CreateDriver()
    ApplyLayout()
    ApplyLock()
    ApplyBindings()
    HookPanels()
    C_Timer.NewTicker(0.25, function()
        UpdateModeLabel()
        UpdateOverlay()
    end)
    -- live while the layer is held
    C_Timer.NewTicker(0.1, function()
        if overlay == "PARTY" then UpdatePartyHealth() end
    end)
    if ns.InitInteract then
        local fn = ns.InitInteract
        ns.InitInteract = nil
        fn()
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("GAME_PAD_CONNECTED")
events:RegisterEvent("GAME_PAD_DISCONNECTED")
events:RegisterEvent("MODIFIER_STATE_CHANGED")
events:RegisterEvent("CVAR_UPDATE")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("LFG_UPDATE")
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        JarStickDB.profiles = JarStickDB.profiles or {}
        JarStickCharDB.settings = JarStickCharDB.settings or {}
        db = JarStickCharDB.settings
        -- first versions kept settings account wide, carry them over once
        if next(db) == nil then
            for k, v in pairs(JarStickDB) do
                if k ~= "profiles" then db[k] = v end
            end
        end
        for k in pairs(JarStickDB) do
            if k ~= "profiles" and k ~= "padReport" and k ~= "debugLog" then JarStickDB[k] = nil end
        end
        MergeDefaults(db)
        -- map and quest log open the same window, first builds had both
        if db.selectMenu.PAD2 == "TOGGLEQUESTLOG" and db.selectMenu.PAD4 == "TOGGLEWORLDMAP" then
            db.selectMenu.PAD2 = "TOGGLEGROUPFINDER"
        end
        ns.db = db
        RunWhenSafe("init", Init)
    elseif event == "PLAYER_LOGIN" then
        ApplyPadCVars()
        ApplyDevice()
        ApplyActionCam(true)
        HideBlizzardBars()
    elseif event == "CVAR_UPDATE" then
        -- something else changed one of our pad cvars (queueing for a dungeon reset the
        -- alt emulation on Jar's client), say who and put it back
        local want = PAD_CVARS[arg1]
        if db and want ~= nil and tostring(C_CVar.GetCVar(arg1)) ~= tostring(want) then
            Log(arg1 .. " changed to " .. tostring(C_CVar.GetCVar(arg1)) .. ", setting it back to " .. tostring(want))
            C_Timer.After(0, function() C_CVar.SetCVar(arg1, tostring(want)) end)
        end
    elseif event == "PLAYER_ENTERING_WORLD" or event == "GROUP_ROSTER_UPDATE" or event == "LFG_UPDATE" then
        -- belt and braces: re-assert the cvars we own
        if db then
            for cvar, value in pairs(PAD_CVARS) do
                if tostring(C_CVar.GetCVar(cvar)) ~= tostring(value) then
                    if ns.debug then Log(event .. ": " .. cvar .. " was " .. tostring(C_CVar.GetCVar(cvar))) end
                    C_CVar.SetCVar(cvar, tostring(value))
                end
            end
        end
    elseif event == "MODIFIER_STATE_CHANGED" then
        if #buttons > 0 then UpdateOverlay() end
    elseif event == "GAME_PAD_CONNECTED" or event == "GAME_PAD_DISCONNECTED" then
        -- ids can shuffle on a replug, give the list a second to settle
        C_Timer.After(1, ApplyDevice)
    elseif event == "PLAYER_REGEN_ENABLED" then
        FlushSafeQueue()
    end
end)

-- for Interact.lua and Config.lua
ns.RunWhenSafe = RunWhenSafe
ns.ApplyCamera = ApplyCamera
ns.ApplyActionCam = ApplyActionCam
ns.ApplyObjectIcon = ApplyObjectIcon
ns.ApplyBindings = ApplyBindings
ns.ApplyMarks = ApplyMarks
ns.ApplyLayout = ApplyLayout
ns.MirrorFrom = MirrorFrom
ns.ResetPositions = ResetPositions
ns.ApplyLock = ApplyLock
ns.RefreshGlyphs = RefreshGlyphs
ns.RefreshPageDriver = RefreshPageDriver
ns.PageName = PageName
ns.ToggleHideBlizzard = ToggleHideBlizzard
ns.ResetPadCVars = ResetPadCVars
ns.ToggleMouseMode = ToggleMouseMode
ns.GetLockActionBars = GetLockActionBars
ns.SetLockActionBars = SetLockActionBars
ns.GetForceXInput = GetForceXInput
ns.SetForceXInput = SetForceXInput
ns.DeviceList = DeviceList
ns.ApplyDevice = ApplyDevice
ns.PadReport = PadReport
ns.ResetAll = ResetAll
ns.ProfileNames = ProfileNames
ns.SaveProfile = SaveProfile
ns.LoadProfile = LoadProfile
ns.DeleteProfile = DeleteProfile
ns.CurrentProfile = function() return JarStickCharDB.profile end
ns.Print = Print

SLASH_JARSTICK1 = "/jarstick"
SLASH_JARSTICK2 = "/jstick"
SLASH_JARSTICK3 = "/js"
SlashCmdList.JARSTICK = function(msg)
    local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    if cmd == "lock" or cmd == "unlock" then
        db.locked = (cmd == "lock")
        ApplyLock()
        Print(db.locked and "clusters locked" or "clusters unlocked, drag them with the mouse")
    elseif cmd == "mouse" then
        ToggleMouseMode()
    elseif cmd == "reset" then
        ResetPadCVars()
    elseif cmd == "resetall" then
        ResetAll()
    elseif cmd == "pad" then
        PadReport()
    elseif cmd == "debug" then
        ns.debug = not ns.debug
        JarStickDB.debugLog = {}
        Print("debug " .. (ns.debug and "on: prints interact/menu state changes, saved on /reload" or "off"))
    elseif cmd == "ui" then
        if ns.UIReport then ns.UIReport() end
    elseif cmd == "save" then
        SaveProfile(rest)
    elseif cmd == "load" then
        LoadProfile(rest)
    elseif cmd == "delete" then
        DeleteProfile(rest)
    elseif cmd == "list" then
        local names = ProfileNames()
        Print(#names > 0 and ("profiles: " .. table.concat(names, ", ")) or "no saved profiles")
    else
        JarStick_ToggleConfig()
    end
end
