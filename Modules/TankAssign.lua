-- TankAssign.lua - Tank mark assignment for RaidSlave
-- Merged from TankHelper, upgraded to 8 tanks, integrated movable button
-- Turtle WoW (1.12 client)

RaidSlaveTankAssign = {}

local MAX_TANKS = 8

local defaults = {
  tanks = {},
  customText = "",
  button = { x = 0, y = 0, locked = false },
}

local MARK_ATLAS = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"
local MARKS = {
  { idx = 8, name = "Skull",    texCoords = { 0.75, 1,    0.25, 0.5  } },
  { idx = 7, name = "Cross",    texCoords = { 0.5,  0.75, 0.25, 0.5  } },
  { idx = 6, name = "Square",   texCoords = { 0.25, 0.5,  0.25, 0.5  } },
  { idx = 5, name = "Moon",     texCoords = { 0,    0.25, 0.25, 0.5  } },
  { idx = 4, name = "Triangle", texCoords = { 0.75, 1,    0,    0.25 } },
  { idx = 3, name = "Diamond",  texCoords = { 0.5,  0.75, 0,    0.25 } },
  { idx = 2, name = "Circle",   texCoords = { 0.25, 0.5,  0,    0.25 } },
  { idx = 1, name = "Star",     texCoords = { 0,    0.25, 0,    0.25 } },
}

-- ============================================================
-- Helpers
-- ============================================================
local function Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cffff6600[RaidSlave Tank]|r " .. msg)
end

local function InitDB()
  RaidSlaveDB = RaidSlaveDB or {}
  if not RaidSlaveDB.TankAssign then RaidSlaveDB.TankAssign = {} end
  local TA = RaidSlaveDB.TankAssign
  if not TA.tanks then TA.tanks = {} end
  if not TA.customText then TA.customText = "" end
  if not TA.button then TA.button = { x = 0, y = 0, locked = false } end
  for i = 1, MAX_TANKS do
    if not TA.tanks[i] then
      TA.tanks[i] = { name = "", marks = {} }
    end
    if not TA.tanks[i].marks then
      TA.tanks[i].marks = {}
    end
  end
end

local function GetDB()
  return RaidSlaveDB.TankAssign
end

-- Tank detection via RaidSlave roles
local function ScanRaidTanks()
  local found = {}
  if RaidSlaveDB and RaidSlaveDB.Tanks then
    for name, flagged in pairs(RaidSlaveDB.Tanks) do
      if flagged then
        table.insert(found, name)
      end
    end
  end
  if table.getn(found) == 0 then
    Print("No tanks found. Flag players as Tank first (right-click in raid roster).")
  end
  return found
end

-- Build output lines
local function BuildAssignmentLines()
  local db = GetDB()
  local lines = {}
  table.insert(lines, "== Tank Assignment ==")

  for i = 1, MAX_TANKS do
    local tank = db.tanks[i]
    if tank and tank.name and tank.name ~= "" then
      local markStrs = {}
      for _, m in ipairs(MARKS) do
        if tank.marks[m.idx] then
          table.insert(markStrs, m.name)
        end
      end
      if table.getn(markStrs) > 0 then
        local markLine = ""
        for mi, ms in ipairs(markStrs) do
          if mi > 1 then markLine = markLine .. ", " end
          markLine = markLine .. ms
        end
        table.insert(lines, tank.name .. "  >>  " .. markLine)
      end
    end
  end

  -- Custom text
  local ct = db.customText or ""
  if ct ~= "" then
    local start = 1
    while start <= string.len(ct) do
      local nl = string.find(ct, "\n", start, true)
      local line
      if nl then
        line = string.sub(ct, start, nl - 1)
        start = nl + 1
      else
        line = string.sub(ct, start)
        start = string.len(ct) + 1
      end
      if line ~= "" then
        table.insert(lines, line)
      end
    end
  end

  return lines
end

local function SendAssignment(chatType)
  local lines = BuildAssignmentLines()
  if table.getn(lines) <= 1 then
    Print("Nothing to send. Assign marks to tanks first.")
    return
  end
  for _, line in ipairs(lines) do
    SendChatMessage(line, chatType)
  end
  Print("Assignment sent to |cfffff000" .. chatType .. "|r")
end

-- ============================================================
-- Config Panel
-- ============================================================
local cfgW = 470
local cfgH = 490  -- taller for 8 rows
local configPanel = CreateFrame("Frame", "RaidSlaveTankConfig", UIParent)
configPanel:SetWidth(cfgW)
configPanel:SetHeight(cfgH)
configPanel:SetPoint("CENTER", UIParent, "CENTER", 0, 30)
configPanel:SetBackdrop({
  bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
  edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
  tile = true, tileSize = 32, edgeSize = 32,
  insets = { left = 11, right = 12, top = 12, bottom = 11 }
})
configPanel:SetBackdropColor(0, 0, 0, 0.95)
configPanel:SetMovable(true)
configPanel:EnableMouse(true)
configPanel:RegisterForDrag("LeftButton")
configPanel:SetScript("OnDragStart", function() configPanel:StartMoving() end)
configPanel:SetScript("OnDragStop", function() configPanel:StopMovingOrSizing() end)
configPanel:SetFrameStrata("DIALOG")
configPanel:Hide()
table.insert(UISpecialFrames, "RaidSlaveTankConfig")

-- Title
local cfgTitleBg = configPanel:CreateTexture(nil, "ARTWORK")
cfgTitleBg:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
cfgTitleBg:SetWidth(280)
cfgTitleBg:SetHeight(64)
cfgTitleBg:SetPoint("TOP", configPanel, "TOP", 0, 12)

local cfgTitle = configPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
cfgTitle:SetPoint("TOP", configPanel, "TOP", 0, 2)
cfgTitle:SetText("|cffff6600RaidSlave|r - Tank Assignment")

-- Close button
local cfgClose = CreateFrame("Button", "RaidSlaveTankConfigClose", configPanel, "UIPanelCloseButton")
cfgClose:SetPoint("TOPRIGHT", configPanel, "TOPRIGHT", -5, -5)

-- Scan button
local scanBtn = CreateFrame("Button", "RaidSlaveTankScanBtn", configPanel, "UIPanelButtonTemplate")
scanBtn:SetWidth(120)
scanBtn:SetHeight(22)
scanBtn:SetPoint("TOPLEFT", configPanel, "TOPLEFT", 20, -30)
scanBtn:SetText("Scan Raid")

-- Clear all button
local clearBtn = CreateFrame("Button", "RaidSlaveTankClearBtn", configPanel, "UIPanelButtonTemplate")
clearBtn:SetWidth(80)
clearBtn:SetHeight(22)
clearBtn:SetPoint("TOPRIGHT", configPanel, "TOPRIGHT", -20, -30)
clearBtn:SetText("Clear All")

-- Column headers
local headerName = configPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
headerName:SetPoint("TOPLEFT", configPanel, "TOPLEFT", 22, -56)
headerName:SetText("|cffFFD100Tank Name|r")

local headerMarks = configPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
headerMarks:SetPoint("TOPLEFT", configPanel, "TOPLEFT", 150, -56)
headerMarks:SetText("|cffFFD100Marks|r")

-- ============================================================
-- Tank Rows
-- ============================================================
local tankRows = {}
local ROW_START_Y = -72
local ROW_HEIGHT = 30
local NAME_WIDTH = 118
local MARK_SIZE = 24
local MARK_GAP = 3

local function CreateMarkButton(parentRow, rowIdx, markIdx, xOff, yOff)
  local markDef = MARKS[markIdx]
  local btnName = "RaidSlaveTankMark" .. rowIdx .. "_" .. markIdx
  local markBtn = CreateFrame("Button", btnName, configPanel)
  markBtn:SetWidth(MARK_SIZE)
  markBtn:SetHeight(MARK_SIZE)
  markBtn:SetPoint("TOPLEFT", configPanel, "TOPLEFT", xOff, yOff - 1)

  markBtn.rsRow = rowIdx
  markBtn.rsMark = markDef.idx
  markBtn.rsMarkName = markDef.name

  local iconTex = markBtn:CreateTexture(nil, "ARTWORK")
  iconTex:SetTexture(MARK_ATLAS)
  local tc = markDef.texCoords
  iconTex:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
  iconTex:SetAllPoints(markBtn)
  iconTex:SetAlpha(0.35)
  markBtn.rsIcon = iconTex

  local hlTex = markBtn:CreateTexture(nil, "OVERLAY")
  hlTex:SetTexture("Interface\\Buttons\\CheckButtonHilight")
  hlTex:SetBlendMode("ADD")
  hlTex:SetAllPoints(markBtn)
  hlTex:Hide()
  markBtn.rsHl = hlTex

  markBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")

  markBtn:SetScript("OnClick", function()
    local db = GetDB()
    local r = this.rsRow
    local m = this.rsMark
    local tank = db.tanks[r]
    if tank.marks[m] then
      tank.marks[m] = nil
      this.rsIcon:SetAlpha(0.35)
      this.rsHl:Hide()
    else
      tank.marks[m] = true
      this.rsIcon:SetAlpha(1.0)
      this.rsHl:Show()
    end
  end)

  markBtn:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_TOP")
    GameTooltip:AddLine(this.rsMarkName)
    GameTooltip:Show()
  end)
  markBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

  return markBtn, iconTex, hlTex
end

local function CreateTankRow(rowIdx)
  local yOff = ROW_START_Y - (rowIdx - 1) * ROW_HEIGHT
  local rowData = { markBtns = {}, markHighlights = {} }

  local rowNum = configPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  rowNum:SetPoint("TOPLEFT", configPanel, "TOPLEFT", 15, yOff - 4)
  rowNum:SetText("|cff888888" .. rowIdx .. "|r")

  local nameBox = CreateFrame("EditBox", "RaidSlaveTankName" .. rowIdx, configPanel, "InputBoxTemplate")
  nameBox:SetWidth(NAME_WIDTH)
  nameBox:SetHeight(20)
  nameBox:SetPoint("TOPLEFT", configPanel, "TOPLEFT", 28, yOff)
  nameBox:SetAutoFocus(false)
  nameBox:SetMaxLetters(20)
  nameBox:SetFontObject(GameFontHighlightSmall)
  nameBox.rsRow = rowIdx

  nameBox:SetScript("OnEnterPressed", function()
    GetDB().tanks[this.rsRow].name = this:GetText()
    this:ClearFocus()
  end)
  nameBox:SetScript("OnEscapePressed", function() this:ClearFocus() end)
  nameBox:SetScript("OnEditFocusLost", function()
    GetDB().tanks[this.rsRow].name = this:GetText()
  end)

  rowData.nameBox = nameBox

  for mi = 1, 8 do
    local xOff = 150 + (mi - 1) * (MARK_SIZE + MARK_GAP)
    local btn, iconTex, hlTex = CreateMarkButton(rowData, rowIdx, mi, xOff, yOff)
    rowData.markBtns[mi] = btn
    rowData.markHighlights[mi] = { icon = iconTex, highlight = hlTex }
  end

  return rowData
end

for row = 1, MAX_TANKS do
  tankRows[row] = CreateTankRow(row)
end

-- ============================================================
-- Custom Text Area
-- ============================================================
local customLabel = configPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
local customY = ROW_START_Y - MAX_TANKS * ROW_HEIGHT - 8
customLabel:SetPoint("TOPLEFT", configPanel, "TOPLEFT", 22, customY)
customLabel:SetText("|cffFFD100Custom lines (polymorph, etc):|r")

local customScroll = CreateFrame("ScrollFrame", "RaidSlaveTankCustomScroll", configPanel, "UIPanelScrollFrameTemplate")
customScroll:SetPoint("TOPLEFT", configPanel, "TOPLEFT", 18, customY - 16)
customScroll:SetWidth(cfgW - 60)
customScroll:SetHeight(60)

local customBg = configPanel:CreateTexture(nil, "BACKGROUND")
customBg:SetTexture(0, 0, 0, 0.4)
customBg:SetPoint("TOPLEFT", customScroll, "TOPLEFT", -2, 2)
customBg:SetPoint("BOTTOMRIGHT", customScroll, "BOTTOMRIGHT", 2, -2)

local customBox = CreateFrame("EditBox", "RaidSlaveTankCustomBox", customScroll)
customBox:SetMultiLine(true)
customBox:SetAutoFocus(false)
customBox:SetFontObject(GameFontHighlightSmall)
customBox:SetWidth(cfgW - 70)
customBox:SetTextColor(1, 1, 1)
customBox:EnableMouse(true)
customBox:SetScript("OnEscapePressed", function() customBox:ClearFocus() end)
customBox:SetScript("OnEditFocusLost", function()
  GetDB().customText = customBox:GetText()
end)
customScroll:SetScrollChild(customBox)

local hintLabel = configPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
hintLabel:SetPoint("TOPLEFT", customScroll, "BOTTOMLEFT", 0, -3)
hintLabel:SetText("|cff888888Tip: marks are sent as text names (Skull, Cross, Moon...)|r")

-- ============================================================
-- Output Buttons
-- ============================================================
local btnY = -cfgH + 46

local function SaveAllState()
  local db = GetDB()
  db.customText = customBox:GetText()
  for i = 1, MAX_TANKS do
    db.tanks[i].name = tankRows[i].nameBox:GetText()
  end
end

local function MakeOutputBtn(label, chatType, xOff)
  local btn = CreateFrame("Button", "RaidSlaveTankOut_" .. chatType, configPanel, "UIPanelButtonTemplate")
  btn:SetWidth(75)
  btn:SetHeight(22)
  btn:SetPoint("TOPLEFT", configPanel, "TOPLEFT", xOff, btnY)
  btn:SetText(label)
  btn:SetScript("OnClick", function()
    SaveAllState()
    SendAssignment(chatType)
  end)
  return btn
end

local sendLabel = configPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
sendLabel:SetPoint("TOPLEFT", configPanel, "TOPLEFT", 22, btnY + 16)
sendLabel:SetText("|cffFFD100Send to:|r")

MakeOutputBtn("Raid", "RAID", 22)
MakeOutputBtn("RW", "RAID_WARNING", 102)
MakeOutputBtn("Party", "PARTY", 182)
MakeOutputBtn("Yell", "YELL", 262)
MakeOutputBtn("Say", "SAY", 342)

-- ============================================================
-- Refresh UI from DB
-- ============================================================
local function RefreshConfig()
  local db = GetDB()
  for i = 1, MAX_TANKS do
    local tank = db.tanks[i]
    tankRows[i].nameBox:SetText(tank.name or "")
    for mi = 1, 8 do
      local data = tankRows[i].markHighlights[mi]
      local markIdx = MARKS[mi].idx
      if tank.marks[markIdx] then
        data.icon:SetAlpha(1.0)
        data.highlight:Show()
      else
        data.icon:SetAlpha(0.35)
        data.highlight:Hide()
      end
    end
  end
  customBox:SetText(db.customText or "")
end

-- ============================================================
-- Scan & Clear handlers
-- ============================================================
scanBtn:SetScript("OnClick", function()
  local tanks = ScanRaidTanks()
  if table.getn(tanks) == 0 then return end
  local db = GetDB()
  local slot = 1
  for _, tName in ipairs(tanks) do
    while slot <= MAX_TANKS and db.tanks[slot].name ~= "" do
      slot = slot + 1
    end
    if slot > MAX_TANKS then break end
    db.tanks[slot].name = tName
    slot = slot + 1
  end
  RefreshConfig()
  Print("Found |cfffff000" .. table.getn(tanks) .. "|r tank(s).")
end)

clearBtn:SetScript("OnClick", function()
  local db = GetDB()
  for i = 1, MAX_TANKS do
    db.tanks[i] = { name = "", marks = {} }
  end
  db.customText = ""
  RefreshConfig()
  Print("All assignments cleared.")
end)

configPanel:SetScript("OnShow", function() RefreshConfig() end)

function RaidSlaveTankAssign.ToggleConfig()
  if configPanel:IsShown() then
    configPanel:Hide()
  else
    configPanel:Show()
  end
end

-- ============================================================
-- Movable Button (anywhere on screen)
-- Left-click: dropdown to pick send channel
-- Right-click: open config panel
-- ============================================================
local moveBtn = CreateFrame("Button", "RaidSlaveTankButton", UIParent)
moveBtn:SetWidth(36)
moveBtn:SetHeight(36)
moveBtn:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
moveBtn:SetFrameStrata("HIGH")
moveBtn:SetMovable(true)
moveBtn:SetClampedToScreen(true)
moveBtn:EnableMouse(true)
moveBtn:RegisterForDrag("LeftButton")
moveBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

-- Icon
local btnIcon = moveBtn:CreateTexture(nil, "ARTWORK")
btnIcon:SetTexture("Interface\\Icons\\Ability_Defend")
btnIcon:SetAllPoints(moveBtn)

-- Border
local btnBorder = moveBtn:CreateTexture(nil, "OVERLAY")
btnBorder:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
btnBorder:SetWidth(56)
btnBorder:SetHeight(56)
btnBorder:SetPoint("TOPLEFT", moveBtn, "TOPLEFT", -10, 10)

moveBtn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

-- Dropdown menu for left-click
local sendMenu = CreateFrame("Frame", "RaidSlaveTankSendMenu", UIParent, "UIDropDownMenuTemplate")
sendMenu.displayMode = "MENU"
sendMenu.initialize = function()
  local channels = {
    { text = "Send to Raid",    chat = "RAID" },
    { text = "Send to RW",      chat = "RAID_WARNING" },
    { text = "Send to Party",   chat = "PARTY" },
    { text = "Send to Yell",    chat = "YELL" },
    { text = "Send to Say",     chat = "SAY" },
  }
  for _, ch in ipairs(channels) do
    UIDropDownMenu_AddButton({
      text = ch.text,
      notCheckable = 1,
      func = function()
        SaveAllState()
        SendAssignment(ch.chat)
      end
    })
  end
  UIDropDownMenu_AddButton({
    text = "Cancel",
    notCheckable = 1,
    func = function() end
  })
end

-- Drag behavior
local isDragging = false
moveBtn:SetScript("OnDragStart", function()
  local db = GetDB()
  if db.button.locked then return end
  isDragging = true
  moveBtn:StartMoving()
end)
moveBtn:SetScript("OnDragStop", function()
  isDragging = false
  moveBtn:StopMovingOrSizing()
  -- Save position
  local db = GetDB()
  local point, _, relPoint, x, y = moveBtn:GetPoint(1)
  db.button.x = x or 0
  db.button.y = y or 0
end)

-- Click: left = send menu, right = config
moveBtn:SetScript("OnClick", function()
  if arg1 == "LeftButton" then
    ToggleDropDownMenu(1, nil, sendMenu, "RaidSlaveTankButton", 0, 0)
  elseif arg1 == "RightButton" then
    RaidSlaveTankAssign.ToggleConfig()
  end
end)

-- Tooltip
moveBtn:SetScript("OnEnter", function()
  GameTooltip:SetOwner(moveBtn, "ANCHOR_LEFT")
  GameTooltip:AddLine("|cffff6600RaidSlave|r - Tank Assignment")
  GameTooltip:AddLine("Left-click: Send assignments", 0.7, 0.7, 0.7)
  GameTooltip:AddLine("Right-click: Open config", 0.7, 0.7, 0.7)
  GameTooltip:AddLine("Drag: Move button", 0.7, 0.7, 0.7)
  local db = GetDB()
  if db and db.button and db.button.locked then
    GameTooltip:AddLine("|cffff5555(Locked - unlock in /rs options)|r", 0.7, 0.7, 0.7)
  end
  GameTooltip:Show()
end)
moveBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- ============================================================
-- Position restore on load
-- ============================================================
local function RestoreButtonPosition()
  local db = GetDB()
  if db.button and (db.button.x ~= 0 or db.button.y ~= 0) then
    moveBtn:ClearAllPoints()
    moveBtn:SetPoint("CENTER", UIParent, "CENTER", db.button.x, db.button.y)
  end
end

-- ============================================================
-- Events
-- ============================================================
local eventFrame = CreateFrame("Frame", "RaidSlaveTankEventFrame", UIParent)
eventFrame:Hide()
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function()
  if event == "ADDON_LOADED" and arg1 == "RaidSlave" then
    InitDB()
    RestoreButtonPosition()
  end
end)
