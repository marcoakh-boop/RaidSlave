-- RaidSlave.lua - Raid leader toolkit for Turtle WoW (1.12 client)
-- Merged from Tactica (by Doite) + TankHelper, stripped of boss tactics & addon comms
-- Author: Marco

-------------------------------------------------
-- LUA 5.0 COMPAT
-------------------------------------------------
do
  if not string.gmatch and string.gfind then
    string.gmatch = function(s, p) return string.gfind(s, p) end
  end
  if not string.match then
    string.match = function(s, p, init)
      local _, _, cap1 = string.find(s, p, init)
      return cap1
    end
  end
end

if not UIDropDownMenu_CreateInfo then
  UIDropDownMenu_CreateInfo = function() return {} end
end

local function tlen(t)
  if table and table.getn then return table.getn(t) end
  local n = 0; for _ in pairs(t) do n = n + 1 end; return n
end

-------------------------------------------------
-- DELAYED EXECUTION HELPER
-------------------------------------------------
local _laterQueue = {}
local _laterFrame = CreateFrame("Frame")
_laterFrame:Hide()
_laterFrame:SetScript("OnUpdate", function()
  for i = tlen(_laterQueue), 1, -1 do
    local job = _laterQueue[i]
    local dt = (arg1 and tonumber(arg1)) or 0.02
    job.t = job.t - dt
    if job.t <= 0 then
      table.remove(_laterQueue, i)
      local ok, err = pcall(job.f)
    end
  end
  if tlen(_laterQueue) == 0 then _laterFrame:Hide() end
end)

local function RunLater(delay, fn)
  table.insert(_laterQueue, { t = math.max(0.01, delay or 0.01), f = fn })
  _laterFrame:Show()
end

-------------------------------------------------
-- GLOBAL TABLE
-------------------------------------------------
RaidSlave = {
  Version = "1.0.0",
  exportFrame = nil,
  exportEditBox = nil,
  optionsFrame = nil,
}

local RS_TITLE_COLOR = "|cffff6600"

-------------------------------------------------
-- SAVEDVARIABLES INIT
-------------------------------------------------
local function InitializeSavedVariables()
  if not RaidSlaveDB then
    RaidSlaveDB = {
      version = 1,
      Healers = {},
      DPS = {},
      Tanks = {},
      MasterLooter = "",
      Settings = {
        RoleWhisperEnabled = true,
        Loot = {
          AutoMasterLoot = true,
          AutoGroupPopup = true,
        },
        ExportFormat = "name_class_role",
        ExportIncludeLabels = true,
      },
    }
  else
    RaidSlaveDB.Settings = RaidSlaveDB.Settings or {}
    RaidSlaveDB.Healers = RaidSlaveDB.Healers or {}
    RaidSlaveDB.DPS = RaidSlaveDB.DPS or {}
    RaidSlaveDB.Tanks = RaidSlaveDB.Tanks or {}
    if RaidSlaveDB.MasterLooter == nil then RaidSlaveDB.MasterLooter = "" end
  end

  local S = RaidSlaveDB.Settings
  if S.RoleWhisperEnabled == nil then S.RoleWhisperEnabled = true end
  S.Loot = S.Loot or {}
  if S.Loot.AutoMasterLoot == nil then S.Loot.AutoMasterLoot = true end
  if S.Loot.AutoGroupPopup == nil then S.Loot.AutoGroupPopup = true end
end

-------------------------------------------------
-- EXPORT HELPERS
-------------------------------------------------
local RaidSlaveExportFormatOptions = {
  { value = "name",            text = "Only Name",           header = "Player Name" },
  { value = "name_class",      text = "Name & Class",        header = "Player Name\tClass" },
  { value = "name_role",       text = "Name & Role",         header = "Player Name\tRole" },
  { value = "name_class_role", text = "Name, Class & Role",  header = "Player Name\tClass\tRole" },
}

local function GetExportFormatOption(value)
  for _, opt in ipairs(RaidSlaveExportFormatOptions) do
    if opt.value == value then return opt end
  end
  return RaidSlaveExportFormatOptions[4]
end

local function GetExportFormat()
  RaidSlaveDB = RaidSlaveDB or {}
  RaidSlaveDB.Settings = RaidSlaveDB.Settings or {}
  local opt = GetExportFormatOption(RaidSlaveDB.Settings.ExportFormat)
  RaidSlaveDB.Settings.ExportFormat = opt.value
  return opt
end

local RaidSlaveExportLabelOptions = {
  { value = false, text = "No labels" },
  { value = true,  text = "Include labels" },
}

local function GetExportIncludeLabels()
  RaidSlaveDB = RaidSlaveDB or {}
  RaidSlaveDB.Settings = RaidSlaveDB.Settings or {}
  if RaidSlaveDB.Settings.ExportIncludeLabels == nil then
    RaidSlaveDB.Settings.ExportIncludeLabels = true
  end
  return (RaidSlaveDB.Settings.ExportIncludeLabels == true)
end

local function GetExportLabelText(includeLabels)
  if includeLabels then return "Include labels" end
  return "No labels"
end

-------------------------------------------------
-- PRINT HELPERS
-------------------------------------------------
function RaidSlave:PrintMessage(msg)
  DEFAULT_CHAT_FRAME:AddMessage(RS_TITLE_COLOR .. "RaidSlave:|r " .. msg)
end

function RaidSlave:PrintError(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cffff0000RaidSlave Error:|r " .. msg)
end

-------------------------------------------------
-- ROLE SUMMARY (post to raid)
-------------------------------------------------
function RaidSlave:PostRoleSummary()
  if not (UnitInRaid and UnitInRaid("player")) then
    self:PrintError("You must be in a raid.")
    return
  end

  local total = (GetNumRaidMembers and GetNumRaidMembers()) or 0
  local tanks, healers = {}, {}
  local T = (RaidSlaveDB and RaidSlaveDB.Tanks)   or {}
  local H = (RaidSlaveDB and RaidSlaveDB.Healers) or {}

  for i = 1, total do
    local name = GetRaidRosterInfo(i)
    if name and name ~= "" then
      if T[name] then
        table.insert(tanks, name)
      elseif H[name] then
        table.insert(healers, name)
      end
    end
  end

  table.sort(tanks,   function(a, b) return string.lower(a) < string.lower(b) end)
  table.sort(healers, function(a, b) return string.lower(a) < string.lower(b) end)

  local function postNames(label, list)
    local cnt  = (table.getn and table.getn(list)) or 0
    local base = string.format("[RaidSlave]: %s - [%d]: ", label, cnt)
    local cur  = base
    local n    = (table.getn and table.getn(list)) or 0

    for idx = 1, n do
      local piece = (idx > 1 and ", " or "") .. list[idx]
      if string.len(cur) + string.len(piece) > 230 then
        SendChatMessage(cur, "RAID")
        cur = "    " .. list[idx]
      else
        cur = cur .. piece
      end
    end
    SendChatMessage(cur, "RAID")
  end

  postNames("Tanks",   tanks)
  postNames("Healers", healers)

  local nT = (table.getn and table.getn(tanks))   or 0
  local nH = (table.getn and table.getn(healers)) or 0
  local dpsTotal = total - nT - nH
  if dpsTotal < 0 then dpsTotal = 0 end
  SendChatMessage(string.format("[RaidSlave]: DPS - [%d]: The rest of the raid.", dpsTotal), "RAID")
end

-------------------------------------------------
-- EXPORT ROSTER UI
-------------------------------------------------
function RaidSlave:ShowExportRolesFrame()
  if not (UnitInRaid and UnitInRaid("player")) then
    self:PrintError("You must be in a raid.")
    return
  end

  local function FillExportData()
    local formatOpt = GetExportFormat()
    local includeLabels = GetExportIncludeLabels()
    local tsvLines = {}
    if includeLabels then
      table.insert(tsvLines, formatOpt.header)
    end
    local total = (GetNumRaidMembers and GetNumRaidMembers()) or 0
    local T = (RaidSlaveDB and RaidSlaveDB.Tanks)   or {}
    local H = (RaidSlaveDB and RaidSlaveDB.Healers) or {}
    local D = (RaidSlaveDB and RaidSlaveDB.DPS)     or {}

    local raidData = {}
    for i = 1, total do
      local name, _, _, _, class = GetRaidRosterInfo(i)
      if name and name ~= "" then
        local role = "DPS"
        if T[name] then role = "Tank"
        elseif H[name] then role = "Healer"
        end
        table.insert(raidData, { name = name, class = class or "Unknown", role = role })
      end
    end

    table.sort(raidData, function(a, b)
      local roleOrder = { Tank = 1, Healer = 2, DPS = 3 }
      local aOrder = roleOrder[a.role] or 4
      local bOrder = roleOrder[b.role] or 4
      if aOrder ~= bOrder then return aOrder < bOrder end
      return string.lower(a.name) < string.lower(b.name)
    end)

    for _, entry in ipairs(raidData) do
      local row
      if formatOpt.value == "name" then
        row = entry.name
      elseif formatOpt.value == "name_class" then
        row = string.format("%s\t%s", entry.name, entry.class)
      elseif formatOpt.value == "name_role" then
        row = string.format("%s\t%s", entry.name, entry.role)
      else
        row = string.format("%s\t%s\t%s", entry.name, entry.class, entry.role)
      end
      table.insert(tsvLines, row)
    end

    local tsvText = table.concat(tsvLines, "\n")
    self.exportEditBox:SetText(tsvText)
    self.exportEditBox:HighlightText()
    self.exportEditBox:SetFocus()
  end

  if not self.exportFrame then
    local f = CreateFrame("Frame", "RaidSlaveExportFrame", UIParent)
    f:SetWidth(450); f:SetHeight(400)
    f:SetPoint("CENTER", UIParent, "CENTER")
    f:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold",
      tile = true, tileSize = 32, edgeSize = 32,
      insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    f:SetBackdropColor(0, 0, 0, 1)
    f:EnableMouse(true); f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() this:StartMoving() end)
    f:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -20)
    title:SetJustifyH("LEFT")
    title:SetText(RS_TITLE_COLOR .. "RaidSlave|r - Export Raid Roster")

    local instructions = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    instructions:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -45)
    instructions:SetJustifyH("LEFT")
    instructions:SetText("Select all (Ctrl+A) and copy (Ctrl+C) to clipboard:")

    local scrollFrame = CreateFrame("ScrollFrame", "RaidSlaveExportScrollFrame", f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -70)
    scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -35, 50)

    local bg = CreateFrame("Frame", nil, f)
    bg:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", -5, 5)
    bg:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", 5, -5)
    bg:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 16,
      insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    bg:SetBackdropColor(0, 0, 0, 0.5)

    local editBox = CreateFrame("EditBox", "RaidSlaveExportEditBox", scrollFrame)
    editBox:SetMultiLine(true); editBox:SetAutoFocus(false)
    editBox:SetFontObject("ChatFontNormal")
    editBox:SetWidth(380); editBox:SetHeight(1000); editBox:SetMaxLetters(0)
    editBox:SetScript("OnEscapePressed", function() f:Hide() end)
    scrollFrame:SetScrollChild(editBox)

    local closeButton = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -10)

    -- Output format dropdown
    local outputLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    outputLabel:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 20, 23)
    outputLabel:SetText("Output:")

    local outputDrop = CreateFrame("Frame", "RaidSlaveExportOutputDropdown", f, "UIDropDownMenuTemplate")
    outputDrop:SetPoint("LEFT", outputLabel, "RIGHT", -10, 0)
    UIDropDownMenu_SetWidth(145, outputDrop)

    UIDropDownMenu_Initialize(outputDrop, function()
      for _, opt in ipairs(RaidSlaveExportFormatOptions) do
        UIDropDownMenu_AddButton({
          text = opt.text,
          value = opt.value,
          checked = (GetExportFormat().value == opt.value),
          func = function()
            local picked = this and this.value or opt.value
            local selectedOpt = GetExportFormatOption(picked)
            RaidSlaveDB.Settings.ExportFormat = selectedOpt.value
            UIDropDownMenu_SetText(selectedOpt.text, outputDrop)
            FillExportData()
            CloseDropDownMenus()
          end
        })
      end
    end)

    -- Labels dropdown
    local labelsLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    labelsLabel:SetPoint("LEFT", outputDrop, "RIGHT", -2, 0)
    labelsLabel:SetText("Label:")

    local labelsDrop = CreateFrame("Frame", "RaidSlaveExportLabelsDropdown", f, "UIDropDownMenuTemplate")
    labelsDrop:SetPoint("LEFT", labelsLabel, "RIGHT", -10, 0)
    UIDropDownMenu_SetWidth(120, labelsDrop)

    UIDropDownMenu_Initialize(labelsDrop, function()
      for _, opt in ipairs(RaidSlaveExportLabelOptions) do
        UIDropDownMenu_AddButton({
          text = opt.text,
          value = opt.value,
          checked = (GetExportIncludeLabels() == opt.value),
          func = function()
            local picked = this and this.value
            if picked == nil then picked = opt.value end
            RaidSlaveDB.Settings.ExportIncludeLabels = (picked == true)
            UIDropDownMenu_SetText(GetExportLabelText(RaidSlaveDB.Settings.ExportIncludeLabels), labelsDrop)
            FillExportData()
            CloseDropDownMenus()
          end
        })
      end
    end)

    self.exportFrame = f
    self.exportEditBox = editBox
    self.exportOutputDropdown = outputDrop
    self.exportLabelsDropdown = labelsDrop
  end

  UIDropDownMenu_SetText(GetExportFormat().text, self.exportOutputDropdown)
  UIDropDownMenu_SetText(GetExportLabelText(GetExportIncludeLabels()), self.exportLabelsDropdown)
  FillExportData()
  self.exportFrame:Show()
  self:PrintMessage("Raid roster exported. Press Ctrl+A then Ctrl+C to copy.")
end

-------------------------------------------------
-- OPTIONS UI
-------------------------------------------------
function RaidSlave:ShowOptionsFrame()
  if self.optionsFrame then
    self.optionsFrame:Show()
    if self.RefreshOptionsFrame then self:RefreshOptionsFrame() end
    return
  end

  local f = CreateFrame("Frame", "RaidSlaveOptionsFrame", UIParent)
  f:SetWidth(260); f:SetHeight(130)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  f:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 16, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 }
  })
  f:SetBackdropColor(0, 0, 0, 1)
  f:SetBackdropBorderColor(1, 1, 1, 1)
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true); f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function() this:StartMoving() end)
  f:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOP", f, "TOP", 0, -12)
  title:SetText(RS_TITLE_COLOR .. "RaidSlave Options|r")

  local function mkcb(name, y, text)
    local cb = CreateFrame("CheckButton", name, f, "UICheckButtonTemplate")
    cb:SetWidth(24); cb:SetHeight(24)
    cb:SetPoint("TOPLEFT", f, "TOPLEFT", 12, y)
    local label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    label:SetText(text)
    return cb
  end

  f.cbAutoML      = mkcb("RSOptAutoML",      -28, "Auto Master Loot on boss (RL)")
  f.cbAutoGroup   = mkcb("RSOptAutoGroup",    -48, "Loot popup after boss (RL)")
  f.cbRoleWhisper = mkcb("RSOptRoleWhisper",  -68, "Whisper role confirmations")

  f.cbAutoML:SetScript("OnClick", function()
    if not (RaidSlaveDB and RaidSlaveDB.Settings) then return end
    RaidSlaveDB.Settings.Loot = RaidSlaveDB.Settings.Loot or {}
    RaidSlaveDB.Settings.Loot.AutoMasterLoot = this:GetChecked() and true or false
    RaidSlave:PrintMessage(RaidSlaveDB.Settings.Loot.AutoMasterLoot and "Auto Master Loot is |cff00ff00ON|r." or "Auto Master Loot is |cffff5555OFF|r.")
  end)

  f.cbAutoGroup:SetScript("OnClick", function()
    if not (RaidSlaveDB and RaidSlaveDB.Settings) then return end
    RaidSlaveDB.Settings.Loot = RaidSlaveDB.Settings.Loot or {}
    RaidSlaveDB.Settings.Loot.AutoGroupPopup = this:GetChecked() and true or false
    RaidSlave:PrintMessage(RaidSlaveDB.Settings.Loot.AutoGroupPopup and "Group Loot popup is |cff00ff00ON|r." or "Group Loot popup is |cffff5555OFF|r.")
  end)

  f.cbRoleWhisper:SetScript("OnClick", function()
    if not (RaidSlaveDB and RaidSlaveDB.Settings) then return end
    RaidSlaveDB.Settings.RoleWhisperEnabled = this:GetChecked() and true or false
    RaidSlave:PrintMessage(RaidSlaveDB.Settings.RoleWhisperEnabled and "Role-whisper is |cff00ff00ON|r." or "Role-whisper is |cffff5555OFF|r.")
  end)

  -- Initial sync
  local S = RaidSlaveDB.Settings
  local L = S.Loot or {}
  if f.cbAutoML      then f.cbAutoML:SetChecked(L.AutoMasterLoot and true or false) end
  if f.cbAutoGroup   then f.cbAutoGroup:SetChecked(L.AutoGroupPopup and true or false) end
  if f.cbRoleWhisper then f.cbRoleWhisper:SetChecked(S.RoleWhisperEnabled and true or false) end

  local close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  close:SetWidth(70); close:SetHeight(20)
  close:SetPoint("BOTTOM", f, "BOTTOM", 0, 12)
  close:SetText("Close")
  close:SetScript("OnClick", function() f:Hide() end)

  f:SetScript("OnShow", function()
    if RaidSlave.RefreshOptionsFrame then RaidSlave:RefreshOptionsFrame() end
  end)

  self.optionsFrame = f
  f:Show()
end

function RaidSlave:RefreshOptionsFrame()
  local f = self.optionsFrame
  if not f then return end
  local S = RaidSlaveDB and RaidSlaveDB.Settings or nil
  local L = S and S.Loot or nil
  if f.cbAutoML      then f.cbAutoML:SetChecked(L and L.AutoMasterLoot and true or false) end
  if f.cbAutoGroup   then f.cbAutoGroup:SetChecked(L and L.AutoGroupPopup and true or false) end
  if f.cbRoleWhisper then f.cbRoleWhisper:SetChecked(S and S.RoleWhisperEnabled and true or false) end
end

-------------------------------------------------
-- SLASH COMMANDS
-------------------------------------------------
function RaidSlave:CommandHandler(msg)
  local args = {}
  if msg and msg ~= "" then
    for arg in string.gmatch(msg, "([^,]+)") do
      local trimmed = string.gsub(arg, "^%s*(.-)%s*$", "%1")
      table.insert(args, trimmed)
    end
  end
  local command = string.lower(args[1] or "")

  if command == "" or command == "help" then
    self:PrintHelp()

  elseif command == "build" then
    if RaidSlaveRaidBuilder and RaidSlaveRaidBuilder.Open then
      RaidSlaveRaidBuilder.Open()
    else
      self:PrintError("Raid Builder module not loaded.")
    end

  elseif command == "lfm" then
    if RaidSlaveRaidBuilder and RaidSlaveRaidBuilder.AnnounceOnce then
      RaidSlaveRaidBuilder.AnnounceOnce()
    end

  elseif command == "autoinvite" then
    if RaidSlaveInvite and RaidSlaveInvite.Open then
      RaidSlaveInvite.Open()
    else
      self:PrintError("Auto-Invite module not loaded.")
    end

  elseif command == "comp" or command == "composition" then
    if RaidSlaveComposition and RaidSlaveComposition.Open then
      RaidSlaveComposition:Open()
    else
      self:PrintError("Composition module not loaded.")
    end

  elseif command == "tank" or command == "tanks" then
    if RaidSlaveTankAssign and RaidSlaveTankAssign.ToggleConfig then
      RaidSlaveTankAssign.ToggleConfig()
    else
      self:PrintError("Tank Assign module not loaded.")
    end

  elseif command == "roles" or command == "role" then
    self:PostRoleSummary()

  elseif command == "export" or command == "exportroles" then
    self:ShowExportRolesFrame()

  elseif command == "rolewhisper" then
    if not RaidSlaveDB or not RaidSlaveDB.Settings then return end
    RaidSlaveDB.Settings.RoleWhisperEnabled = not RaidSlaveDB.Settings.RoleWhisperEnabled
    if RaidSlaveDB.Settings.RoleWhisperEnabled then
      self:PrintMessage("Role-whisper is |cff00ff00ON|r.")
    else
      self:PrintMessage("Role-whisper is |cffff5555OFF|r.")
    end

  elseif command == "clearroles" then
    if RaidSlaveRaidRoles_ClearAllRoles then
      RaidSlaveRaidRoles_ClearAllRoles(false)
    else
      self:PrintError("Raid roles module not loaded.")
    end

  elseif command == "options" or command == "config" then
    self:ShowOptionsFrame()

  elseif command == "loot" then
    if RaidSlaveLoot_ShowPopup then
      RaidSlaveLoot_ShowPopup()
    else
      self:PrintError("Loot module not loaded.")
    end

  else
    self:PrintError("Unknown command. Use /rs help")
  end
end

function RaidSlave:PrintHelp()
  self:PrintMessage("RaidSlave Commands:")
  self:PrintMessage("  |cffffff78/rs build|r - open Raid Builder")
  self:PrintMessage("  |cffffff78/rs lfm|r - announce Raid Builder msg")
  self:PrintMessage("  |cffffff78/rs autoinvite|r - open Auto Invite")
  self:PrintMessage("  |cffffff78/rs comp|r - open Composition tool")
  self:PrintMessage("  |cffffff78/rs tank|r - open Tank Assignment")
  self:PrintMessage("  |cffffff00/rs roles|r - post Tanks/Healers/DPS to raid")
  self:PrintMessage("  |cffffff00/rs export|r - export roster as CSV")
  self:PrintMessage("  |cffffff00/rs rolewhisper|r - toggle role whisper")
  self:PrintMessage("  |cffffff00/rs clearroles|r - clear all role assignments")
  self:PrintMessage("  |cffffff00/rs options|r - options panel")
  self:PrintMessage("  |cffffff00/rs loot|r - show loot method dialog")
end

-------------------------------------------------
-- SLASH REGISTRATION
-------------------------------------------------
SLASH_RAIDSLAVE1 = "/raidslave"
SLASH_RAIDSLAVE2 = "/rs"
SlashCmdList["RAIDSLAVE"] = function(msg)
  RaidSlave:CommandHandler(msg)
end

-------------------------------------------------
-- EVENT HANDLING
-------------------------------------------------
local rsEventFrame = CreateFrame("Frame")
rsEventFrame:RegisterEvent("ADDON_LOADED")

rsEventFrame:SetScript("OnEvent", function()
  if event == "ADDON_LOADED" and arg1 == "RaidSlave" then
    InitializeSavedVariables()
    RunLater(1, function()
      local cf = DEFAULT_CHAT_FRAME or ChatFrame1
      cf:AddMessage(RS_TITLE_COLOR .. "RaidSlave|r loaded. Use |cffffff00/rs|r for commands.")
    end)
  end
end)
