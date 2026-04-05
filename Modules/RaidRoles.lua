-- RaidRoles.lua - Role assignment for RaidSlave (local-only, no addon comms)
-- Ported from TacticaRaidRoles.lua by Doite

------------------------------------------------------------
-- SavedVariables guard
------------------------------------------------------------
local function EnsureDB()
  if not RaidSlaveDB then
    RaidSlaveDB = {
      version = 1,
      Settings = {},
      Healers = {},
      DPS = {},
      Tanks = {},
      wasInRaid = false,
    }
  end
  if not RaidSlaveDB.Healers then RaidSlaveDB.Healers = {} end
  if not RaidSlaveDB.DPS    then RaidSlaveDB.DPS    = {} end
  if not RaidSlaveDB.Tanks  then RaidSlaveDB.Tanks  = {} end
  if RaidSlaveDB.MasterLooter == nil then RaidSlaveDB.MasterLooter = "" end
  if RaidSlaveDB.wasInRaid == nil then RaidSlaveDB.wasInRaid = false end
end

-- Tell Raid Builder to refresh (safe if RB not loaded)
local function NotifyBuilder()
  if RaidSlaveRaidBuilder and RaidSlaveRaidBuilder.NotifyRoleAssignmentChanged then
    RaidSlaveRaidBuilder.NotifyRoleAssignmentChanged()
  elseif RaidSlaveRaidBuilder and RaidSlaveRaidBuilder.RefreshPreview then
    RaidSlaveRaidBuilder.RefreshPreview()
  end
end

------------------------------------------------------------
-- pfUI + SuperWoW detection
------------------------------------------------------------
local RS_hasPfUI = false
local RS_hasSuperWoW = false
local RS_SuperWoWVersion = nil

local function RS_DetectPfUI()
  RS_hasPfUI = false
  if type(IsAddOnLoaded) == "function" then
    local ok = IsAddOnLoaded("pfUI")
    if ok == 1 or ok == true then RS_hasPfUI = true end
  end
  return RS_hasPfUI
end

local function RS_DetectSuperWoW()
  RS_hasSuperWoW = false
  RS_SuperWoWVersion = nil
  if type(SUPERWOW_VERSION) == "string" and SUPERWOW_VERSION ~= "" then
    RS_hasSuperWoW = true
    RS_SuperWoWVersion = SUPERWOW_VERSION
  elseif type(SpellInfo) == "function" or type(SetAutoloot) == "function" or (type(superwow_active) ~= "nil") then
    RS_hasSuperWoW = true
    RS_SuperWoWVersion = "legacy/unknown"
  end
  return RS_hasSuperWoW, RS_SuperWoWVersion
end

SLASH_RSPFUI1 = "/rs_pfui"
SlashCmdList["RSPFUI"] = function()
  RS_DetectPfUI()
  RS_DetectSuperWoW()
  local f = (DEFAULT_CHAT_FRAME or ChatFrame1)
  local pf = RS_hasPfUI and "|cff33ff99LOADED|r" or "|cffff5555NOT loaded|r"
  local sw = RS_hasSuperWoW and ("|cff33ff99present|r" .. (RS_SuperWoWVersion and (" (v" .. RS_SuperWoWVersion .. ")") or "")) or "|cffff5555not detected|r"
  f:AddMessage("|cffff6600RaidSlave:|r pfUI: " .. pf .. ",  SuperWoW: " .. sw)
end

SLASH_RSPFUITANKS1 = "/rs_pfuitanks"
SlashCmdList["RSPFUITANKS"] = function(msg)
  local f = DEFAULT_CHAT_FRAME or ChatFrame1
  local function trim(s) return (string.gsub(s or "", "^%s*(.-)%s*$", "%1")) end
  if not (pfUI and pfUI.uf and pfUI.uf.raid) then
    f:AddMessage("|cffff6600RaidSlave:|r pfUI not loaded or raid frames missing.")
    return
  end
  pfUI.uf.raid.tankrole = pfUI.uf.raid.tankrole or {}
  local t = pfUI.uf.raid.tankrole
  local who = trim(msg)
  if who ~= "" then
    f:AddMessage("|cffff6600RaidSlave:|r pfUI " .. who .. " tank? " .. tostring(t[who] and true or false)
      .. "  |  RaidSlaveDB " .. who .. " tank? " .. tostring(RaidSlaveDB and RaidSlaveDB.Tanks and RaidSlaveDB.Tanks[who] and true or false))
    return
  end
  local c = 0
  for n in pairs(t) do c = c + 1; f:AddMessage("pfUI tank: " .. n) end
  if c == 0 then f:AddMessage("|cffff6600RaidSlave:|r pfUI: none") end
end

-- Find pfUI's external Tank menu key by button text
local External_Tank_Key = nil
local function DetectExternalTankMenuKey()
  External_Tank_Key = nil
  if not UnitPopupButtons then return end
  for k, info in pairs(UnitPopupButtons) do
    if type(k) == "string" and info and info.text == "Toggle as Tank" and k ~= "RAIDSLAVE_TOGGLE_TANK" then
      External_Tank_Key = k; break
    end
  end
end

------------------------------------------------------------
-- pfUI bridge (drive pfUI.uf.raid.tankrole)
------------------------------------------------------------
local function Pfui_IsReady()
  return RS_hasPfUI and pfUI and pfUI.uf and pfUI.uf.raid
end

local function Pfui_GetTankTable()
  if not Pfui_IsReady() then return nil end
  pfUI.uf.raid.tankrole = pfUI.uf.raid.tankrole or {}
  return pfUI.uf.raid.tankrole
end

local function Pfui_RefreshRaid()
  if pfUI and pfUI.uf and pfUI.uf.raid and pfUI.uf.raid.Show then
    pfUI.uf.raid:Show()
  end
end

local function trim(s) return (string.gsub(s or "", "^%s*(.-)%s*$", "%1")) end
local function lower(s) return string.lower(s or "") end

local function Pfui_RemoveAllKeysFor(name)
  local t = Pfui_GetTankTable(); if not t then return end
  local tgt = lower(trim(name or ""))
  for k in pairs(t) do
    if lower(trim(k)) == tgt then t[k] = nil end
  end
end

local function Pfui_SetTank(name, enabled)
  if not name or name == "" then return end
  local t = Pfui_GetTankTable(); if not t then return end
  Pfui_RemoveAllKeysFor(name)
  if enabled then t[name] = true end
  Pfui_RefreshRaid()
end

local function Pfui_ReapplyAllTanks()
  local t = Pfui_GetTankTable(); if not t then return end
  for k in pairs(t) do t[k] = nil end
  for name, v in pairs(RaidSlaveDB.Tanks) do if v then t[name] = true end end
  Pfui_RefreshRaid()
end

------------------------------------------------------------
-- Menu keys & layout offsets
------------------------------------------------------------
local BUTTON_KEY_HEALER = "RAIDSLAVE_TOGGLE_HEALER"
local BUTTON_KEY_DPS    = "RAIDSLAVE_TOGGLE_DPS"
local BUTTON_KEY_TANK   = "RAIDSLAVE_TOGGLE_TANK"
local BUTTON_KEY_ML     = "RAIDSLAVE_PRESET_ML"
local IsSelfRaidLeader
local ML_TAG_OFFSET_AFTER_CLASS = -10

local OFFSET_BEFORE_NAME_DEFAULT = 2
local OFFSET_BEFORE_NAME_PFUI    = 1
local OFFSET_BEFORE_NAME_ACTIVE  = 1

------------------------------------------------------------
-- Raid role helpers (exclusive)
------------------------------------------------------------
local function ClearAllRolesFor(name)
  if not name or name == "" then return end
  RaidSlaveDB.Healers[name] = nil
  RaidSlaveDB.DPS[name] = nil
  RaidSlaveDB.Tanks[name] = nil
end

local function GetCurrentRole(name)
  if not name or name == "" then return nil end
  if RaidSlaveDB.Tanks[name]  then return "T" end
  if RaidSlaveDB.Healers[name] then return "H" end
  if RaidSlaveDB.DPS[name]    then return "D" end
  return nil
end

local function SetMasterLooterPreset(nameOrEmpty)
  RaidSlaveDB.MasterLooter = nameOrEmpty or ""
end

local function CurrentRaidLeaderName()
  local n = GetNumRaidMembers and GetNumRaidMembers() or 0
  for i = 1, n do
    local nm, rank = GetRaidRosterInfo(i)
    if rank == 2 then return nm end
  end
  return UnitName and UnitName("player") or nil
end

local function ApplyPresetMasterLooterNow(nameOrEmpty)
  if not (UnitInRaid("player") and IsSelfRaidLeader()) then return end
  local method = GetLootMethod and GetLootMethod() or nil
  if method ~= "master" then return end
  local target = nameOrEmpty
  if not target or target == "" then target = CurrentRaidLeaderName() end
  if target and target ~= "" then
    SetLootMethod("master", target)
  end
end

function RaidSlaveRaidRoles_GetPresetMasterLooter()
  EnsureDB()
  return RaidSlaveDB.MasterLooter or ""
end

function RaidSlaveRaidRoles_SetPresetMasterLooter(nameOrEmpty)
  EnsureDB()
  if not UnitInRaid("player") then return false, "not in raid" end
  if not IsSelfRaidLeader() then return false, "only raid leader can set preset ML" end

  local name = nameOrEmpty or ""
  if name ~= "" then
    local found = false
    local n = GetNumRaidMembers and GetNumRaidMembers() or 0
    for i = 1, n do
      local r = GetRaidRosterInfo(i)
      if r == name then found = true; break end
    end
    if not found then return false, "player not found in raid" end
  end

  SetMasterLooterPreset(name)
  ApplyPresetMasterLooterNow(name)
  if name ~= "" then
    local me = UnitName and UnitName("player") or ""
    local whisperOn = (RaidSlaveDB and RaidSlaveDB.Settings and RaidSlaveDB.Settings.RoleWhisperEnabled ~= false)
    if whisperOn and me ~= "" and name ~= me and UnitInRaid("player") and IsSelfRaidLeader() then
      SendChatMessage("[RaidSlave]: You have been selected as preset masterlooter. If masterloot is turned on, you will automatically receive the role.", "WHISPER", nil, name)
    end
  end
  if type(RaidSlave_DecorateRaidRoster) == "function" then RaidSlave_DecorateRaidRoster() end
  if type(RaidSlave_DecoratePartyFrames) == "function" then RaidSlave_DecoratePartyFrames() end
  NotifyBuilder()
  return true
end

local function FindUnitByName(name)
  if not name or name == "" then return nil end
  local me = UnitName and UnitName("player")
  if me == name then return "player" end
  local rn = (GetNumRaidMembers and GetNumRaidMembers()) or 0
  if rn > 0 then
    for i = 1, rn do
      local u = "raid" .. i
      if UnitExists and UnitExists(u) then
        local nm = UnitName(u)
        if nm == name then return u end
      end
    end
  end
  local pn = (GetNumPartyMembers and GetNumPartyMembers()) or 0
  if pn > 0 then
    for i = 1, pn do
      local u = "party" .. i
      if UnitExists and UnitExists(u) then
        local nm = UnitName(u)
        if nm == name then return u end
      end
    end
  end
  return nil
end

local function IsUnitOnlineByName(name)
  local u = FindUnitByName(name)
  if not u then return false end
  if UnitIsConnected then return UnitIsConnected(u) and true or false end
  return true
end

local suppressPfuiWrite = false

local function SetExclusiveRole(name, role)
  if not name or name == "" then return nil, nil end
  local current = GetCurrentRole(name)
  if current == role then
    ClearAllRolesFor(name)
    if role == "T" and not suppressPfuiWrite then Pfui_SetTank(name, false) end
    NotifyBuilder()
    return nil, (role == "H" and "not marked as Healer")
             or (role == "D" and "not marked as DPS")
             or (role == "T" and "not marked as Tank")
  else
    ClearAllRolesFor(name)
    if role == "H" then
      RaidSlaveDB.Healers[name] = true
      if not suppressPfuiWrite then Pfui_SetTank(name, false) end
    elseif role == "D" then
      RaidSlaveDB.DPS[name] = true
      if not suppressPfuiWrite then Pfui_SetTank(name, false) end
    elseif role == "T" then
      RaidSlaveDB.Tanks[name] = true
      if not suppressPfuiWrite then Pfui_SetTank(name, true) end
    else
      return nil, nil
    end
    NotifyBuilder()
    return role, (role == "H" and "marked as Healer")
               or (role == "D" and "marked as DPS")
               or (role == "T" and "marked as Tank")
  end
end

------------------------------------------------------------
-- Raid officer checks
------------------------------------------------------------
local function IsLeaderOrAssistByName(name)
  if not name or name == "" then return false end
  local n = GetNumRaidMembers and GetNumRaidMembers() or 0
  for i = 1, n do
    local rname, rank = GetRaidRosterInfo(i)
    if rname and rname == name then
      return (rank and rank >= 1) and true or false
    end
  end
  return false
end

local function IsSelfLeaderOrAssist()
  if not UnitInRaid("player") then return false end
  local me = UnitName and UnitName("player") or nil
  return IsLeaderOrAssistByName(me)
end

IsSelfRaidLeader = function()
  return (IsRaidLeader and IsRaidLeader() == 1) or false
end

------------------------------------------------------------
-- Context menu & click hook
------------------------------------------------------------
local menuInjected = false
local function AddMenuButton()
  if menuInjected then return end
  if not UnitPopupButtons or not UnitPopupMenus then return end
  if not UnitPopupMenus["RAID"] and not UnitPopupMenus["PARTY"] then return end

  if not UnitPopupButtons[BUTTON_KEY_HEALER] then
    UnitPopupButtons[BUTTON_KEY_HEALER] = { text = "Toggle as Healer", dist = 0 }
  end
  if not UnitPopupButtons[BUTTON_KEY_DPS] then
    UnitPopupButtons[BUTTON_KEY_DPS] = { text = "Toggle as DPS", dist = 0 }
  end
  if not UnitPopupButtons[BUTTON_KEY_TANK] then
    UnitPopupButtons[BUTTON_KEY_TANK] = { text = "Toggle as Tank", dist = 0 }
  end
  if not UnitPopupButtons[BUTTON_KEY_ML] then
    UnitPopupButtons[BUTTON_KEY_ML] = { text = "Preset Masterlooter", dist = 0 }
  end

  local hideOurTank = (RS_hasPfUI and RS_hasSuperWoW)

  local function ensureItem(menu, key, insertIndex)
    if not menu then return end
    local exists = false
    local n = table.getn(menu)
    for i = 1, n do if menu[i] == key then exists = true; break end end
    if not exists then table.insert(menu, insertIndex or 3, key) end
  end

  do
    local menu = UnitPopupMenus["RAID"]
    ensureItem(menu, BUTTON_KEY_HEALER, 3)
    ensureItem(menu, BUTTON_KEY_DPS,    4)
    if not hideOurTank then ensureItem(menu, BUTTON_KEY_TANK, 5) end
    ensureItem(menu, BUTTON_KEY_ML,     6)
  end

  do
    local menu = UnitPopupMenus["PARTY"]
    ensureItem(menu, BUTTON_KEY_HEALER, 3)
    ensureItem(menu, BUTTON_KEY_DPS,    4)
    if not hideOurTank then ensureItem(menu, BUTTON_KEY_TANK, 5) end
    ensureItem(menu, BUTTON_KEY_ML,     6)
  end

  do
    local menu = UnitPopupMenus["PLAYER"]
    ensureItem(menu, BUTTON_KEY_HEALER, 3)
    ensureItem(menu, BUTTON_KEY_DPS,    4)
    ensureItem(menu, BUTTON_KEY_TANK,   5)
    ensureItem(menu, BUTTON_KEY_ML,     6)
  end

  menuInjected = true
end

local hookInstalled = false
local function HandleMenuClick()
  if not this or not this.value then return end
  EnsureDB()
  local inRaid  = UnitInRaid and UnitInRaid("player")
  local inParty = (GetNumPartyMembers and (GetNumPartyMembers() or 0) > 0) and true or false
  if (not inRaid) and (not inParty) then return end

  local dropdownFrame = getglobal(UIDROPDOWNMENU_INIT_MENU or "")
  if not dropdownFrame then return end

  local name = dropdownFrame.name
  if (not name or name == "") and dropdownFrame.unit then name = UnitName(dropdownFrame.unit) end
  if not name or name == "" then return end

  local key = this.value
  local roleWanted = nil
  local isExternalPfuiTank = false

  if key == BUTTON_KEY_HEALER then roleWanted = "H"
  elseif key == BUTTON_KEY_DPS  then roleWanted = "D"
  elseif key == BUTTON_KEY_TANK then roleWanted = "T"
  elseif key == BUTTON_KEY_ML then
    if not UnitInRaid("player") then return end
    if not IsSelfRaidLeader() then
      (DEFAULT_CHAT_FRAME or ChatFrame1):AddMessage("|cffff5555RaidSlave:|r Only raid leader can preset master looter.")
      return
    end
    local current = RaidSlaveDB.MasterLooter or ""
    local nextName = (current == name) and "" or name
    RaidSlaveRaidRoles_SetPresetMasterLooter(nextName)
    if type(RaidSlave_DecorateRaidRoster) == "function" then RaidSlave_DecorateRaidRoster() end
    NotifyBuilder()
    local msg = (nextName ~= "") and (nextName .. " preset as ML.") or "Preset ML cleared."
    ;(DEFAULT_CHAT_FRAME or ChatFrame1):AddMessage("|cffff6600RaidSlave:|r " .. msg)
    return
  elseif RS_hasPfUI and External_Tank_Key and key == External_Tank_Key then
    roleWanted = "T"; isExternalPfuiTank = true
  else
    local info = UnitPopupButtons and UnitPopupButtons[key]
    if RS_hasPfUI and info and info.text == "Toggle as Tank" then
      roleWanted = "T"; isExternalPfuiTank = true
    end
  end
  if not roleWanted then return end

  if isExternalPfuiTank then suppressPfuiWrite = true end
  local newRole, msg = SetExclusiveRole(name, roleWanted)
  suppressPfuiWrite = false

  if msg then
    if type(RaidSlave_DecorateRaidRoster) == "function" then RaidSlave_DecorateRaidRoster() end
    if type(RaidSlave_DecoratePartyFrames) == "function" then RaidSlave_DecoratePartyFrames() end
    ;(DEFAULT_CHAT_FRAME or ChatFrame1):AddMessage(string.format("|cffff6600RaidSlave:|r %s is now %s.", name, msg))

    -- whisper (leader/assist only)
    if not (RaidSlaveDB and RaidSlaveDB.Settings) then RaidSlaveDB = RaidSlaveDB or {}; RaidSlaveDB.Settings = RaidSlaveDB.Settings or {} end
    if RaidSlaveDB.Settings.RoleWhisperEnabled ~= false then
      local me = UnitName and UnitName("player") or nil
      if me and me ~= name and IsUnitOnlineByName(name) then
        local inRaidNow = UnitInRaid and UnitInRaid("player")
        local canWhisper = false
        if inRaidNow then
          canWhisper = IsSelfLeaderOrAssist() and true or false
        else
          canWhisper = (IsPartyLeader and IsPartyLeader()) and true or false
        end

        if canWhisper then
          local w
          if newRole == "H" then
            w = "[RaidSlave]: You are marked as 'H' (Healer) on the raid roster."
          elseif newRole == "T" then
            w = "[RaidSlave]: You are marked as 'T' (Tank) on the raid roster."
          elseif newRole == "D" then
            w = "[RaidSlave]: You are marked as 'D' (DPS) on the raid roster."
          else
            w = "[RaidSlave]: You are no longer marked on the raid roster."
          end
          if SendChatMessage then
            SendChatMessage(w, "WHISPER", nil, name)
          end
        end
      end
    end
  end
end

local function InstallClickHook()
  if hookInstalled then return end
  if type(hooksecurefunc) == "function" then
    hooksecurefunc("UnitPopup_OnClick", HandleMenuClick)
  else
    local orig = UnitPopup_OnClick
    UnitPopup_OnClick = function() HandleMenuClick(); if orig then orig() end end
  end
  hookInstalled = true
end

------------------------------------------------------------
-- Roster decoration
------------------------------------------------------------
local function BuildRoleTag(name)
  if not name or name == "" then return "" end
  if RaidSlaveDB.Healers[name] then return "H" end
  if RaidSlaveDB.DPS[name]    then return "D" end
  if RaidSlaveDB.Tanks[name]  then return "T" end
  return ""
end

------------------------------------------------------------
-- Party frame decoration (T/H/D)
------------------------------------------------------------
local function GetPartyNameFS(i)
  return getglobal("PartyMemberFrame" .. i .. "Name")
end

local function GetOrCreatePartyTag(frame)
  if not frame then return nil end
  if not frame.RSPartyRoleTag then
    local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.RSPartyRoleTag = fs
    frame.RSPartyRoleTag:SetTextColor(1, 1, 0)
    frame.RSPartyRoleTag:SetJustifyH("RIGHT")
    local fpath, fsize = frame.RSPartyRoleTag:GetFont()
    if fpath and fsize then frame.RSPartyRoleTag:SetFont(fpath, math.max(8, fsize - 2)) end
  end
  return frame.RSPartyRoleTag
end

local function GetOrCreatePlayerTag()
  if not PlayerFrame then return nil end
  if not PlayerFrame.RSPlayerRoleTag then
    local fs = PlayerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    PlayerFrame.RSPlayerRoleTag = fs
    PlayerFrame.RSPlayerRoleTag:SetTextColor(1, 1, 0)
    PlayerFrame.RSPlayerRoleTag:SetJustifyH("RIGHT")
    local fpath, fsize = fs:GetFont()
    if fpath and fsize then fs:SetFont(fpath, math.max(8, fsize - 2)) end
  end
  return PlayerFrame.RSPlayerRoleTag
end

local function GetOrCreateTag(btn)
  if not btn.RSRoleTag then
    local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.RSRoleTag = fs
    btn.RSRoleTag:SetTextColor(1, 1, 0)
    btn.RSRoleTag:SetJustifyH("RIGHT")
    local fpath, fsize = btn.RSRoleTag:GetFont()
    if fpath and fsize then btn.RSRoleTag:SetFont(fpath, math.max(8, fsize - 2)) end
  end
  return btn.RSRoleTag
end

local function GetOrCreateMLTag(btn)
  if not btn.RSMLTag then
    local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.RSMLTag = fs
    btn.RSMLTag:SetTextColor(1, 0.82, 0)
    btn.RSMLTag:SetJustifyH("LEFT")
    local fpath, fsize = btn.RSMLTag:GetFont()
    if fpath and fsize then btn.RSMLTag:SetFont(fpath, math.max(8, fsize - 2)) end
  end
  return btn.RSMLTag
end

local function GetListNameFS(i) return getglobal("RaidGroupButton" .. i .. "Name") end
local function GetListClassFS(i) return getglobal("RaidGroupButton" .. i .. "Class") end

local function GetGridNameFS(btn, name)
  local base = btn:GetName()
  if base then
    local fs = getglobal(base .. "Name")
    if fs and fs.GetText then return fs end
  end
  if btn.GetFontString then
    local fs2 = btn:GetFontString()
    if fs2 and fs2.GetText then return fs2 end
  end
  if btn.GetRegions and name and name ~= "" then
    local regs = { btn:GetRegions() }
    local m = table.getn(regs)
    for i = 1, m do
      local r = regs[i]
      if r and r.GetObjectType and r:GetObjectType() == "FontString" and r.GetText then
        if r:GetText() == name then return r end
      end
    end
  end
  return nil
end

local function GetGridClassFS(btn)
  local base = btn and btn:GetName()
  if base then
    local fs = getglobal(base .. "Class")
    if fs and fs.GetText then return fs end
  end
  return nil
end

local function Decorate_ListButtons()
  local any = false
  for i = 1, 40 do
    local btn = getglobal("RaidGroupButton" .. i)
    if btn and btn:IsShown() then
      any = true
      local name = nil
      if GetRaidRosterInfo then name = GetRaidRosterInfo(i) end
      if (not name or name == "") and btn.unit then name = UnitName(btn.unit) end
      if (not name or name == "") and btn.name then name = btn.name end

      local nameFS = GetListNameFS(i)
      local classFS = GetListClassFS(i)
      local tagFS = GetOrCreateTag(btn)
      local mlFS = GetOrCreateMLTag(btn)
      tagFS:ClearAllPoints()
      mlFS:ClearAllPoints()
      if nameFS and nameFS:IsShown() then
        tagFS:SetPoint("RIGHT", nameFS, "LEFT", OFFSET_BEFORE_NAME_ACTIVE, 0)
        local tag = BuildRoleTag(name)
        if tag ~= "" then tagFS:SetText(tag); tagFS:Show() else tagFS:SetText(""); tagFS:Hide() end
        local anchorFS = classFS and classFS:IsShown() and classFS or nameFS
        mlFS:SetPoint("LEFT", anchorFS, "RIGHT", ML_TAG_OFFSET_AFTER_CLASS, 0)
        if name and RaidSlaveDB.MasterLooter and name == RaidSlaveDB.MasterLooter then
          mlFS:SetText("ML"); mlFS:Show()
        else
          mlFS:SetText(""); mlFS:Hide()
        end
      else
        tagFS:SetText(""); tagFS:Hide()
        mlFS:SetText(""); mlFS:Hide()
      end
    end
  end
  return any
end

local function Decorate_GroupGrid()
  local any = false
  for g = 1, 8 do
    for s = 1, 5 do
      local btn = getglobal("RaidGroup" .. g .. "Slot" .. s)
      if btn and btn:IsShown() then
        any = true
        local name = btn.name
        if (not name or name == "") and btn.unit then name = UnitName(btn.unit) end

        local nameFS = GetGridNameFS(btn, name)
        local classFS = GetGridClassFS(btn)
        local tagFS = GetOrCreateTag(btn)
        local mlFS = GetOrCreateMLTag(btn)
        tagFS:ClearAllPoints()
        mlFS:ClearAllPoints()
        if nameFS then
          tagFS:SetPoint("RIGHT", nameFS, "LEFT", OFFSET_BEFORE_NAME_ACTIVE, 0)
          local tag = BuildRoleTag(name)
          if tag ~= "" then tagFS:SetText(tag); tagFS:Show() else tagFS:SetText(""); tagFS:Hide() end
          local anchorFS = classFS and classFS:IsShown() and classFS or nameFS
          mlFS:SetPoint("LEFT", anchorFS, "RIGHT", ML_TAG_OFFSET_AFTER_CLASS, 0)
          if name and RaidSlaveDB.MasterLooter and name == RaidSlaveDB.MasterLooter then
            mlFS:SetText("ML"); mlFS:Show()
          else
            mlFS:SetText(""); mlFS:Hide()
          end
        else
          tagFS:SetText(""); tagFS:Hide()
          mlFS:SetText(""); mlFS:Hide()
        end
      end
    end
  end
  return any
end

function RaidSlave_DecorateRaidRoster()
  EnsureDB()
  local ok = Decorate_ListButtons()
  if not ok then Decorate_GroupGrid() end
end

function RaidSlave_DecoratePartyFrames()
  EnsureDB()
  local pn = (GetNumPartyMembers and GetNumPartyMembers()) or 0
  for i = 1, 4 do
    local frame = getglobal("PartyMemberFrame" .. i)
    if frame then
      local tag = GetOrCreatePartyTag(frame)
      if tag then
        tag:ClearAllPoints()
        local nameFS = GetPartyNameFS(i)
        if nameFS and i <= pn then
          local name = UnitName("party" .. i)
          local roleTag = BuildRoleTag(name)
          if roleTag ~= "" then
            tag:SetPoint("RIGHT", nameFS, "LEFT", -2, 0)
            tag:SetText(roleTag)
            tag:Show()
          else
            tag:SetText(""); tag:Hide()
          end
        else
          tag:SetText(""); tag:Hide()
        end
      end
    end
  end
end

function RaidSlave_DecoratePlayerFrame()
  EnsureDB()
  local tag = GetOrCreatePlayerTag()
  if not tag then return end
  tag:ClearAllPoints()
  local inParty = (GetNumPartyMembers and (GetNumPartyMembers() or 0) > 0)
  local inRaid = UnitInRaid and UnitInRaid("player")
  if inParty and not inRaid then
    local me = UnitName and UnitName("player")
    local roleTag = BuildRoleTag(me)
    if roleTag ~= "" then
      local nameFS = PlayerName or getglobal("PlayerName")
      if nameFS then
        tag:SetPoint("RIGHT", nameFS, "LEFT", -2, 0)
        tag:SetText(roleTag)
        tag:Show()
        return
      end
    end
  end
  tag:SetText(""); tag:Hide()
end

local function InstallRosterHooks()
  if type(hooksecurefunc) == "function" and type(RaidFrame_Update) == "function" then
    hooksecurefunc("RaidFrame_Update", function() RaidSlave_DecorateRaidRoster() end)
  elseif type(RaidFrame_Update) == "function" then
    local o = RaidFrame_Update; RaidFrame_Update = function() if o then o() end; RaidSlave_DecorateRaidRoster() end
  end
  if type(hooksecurefunc) == "function" and type(RaidGroupFrame_Update) == "function" then
    hooksecurefunc("RaidGroupFrame_Update", function() RaidSlave_DecorateRaidRoster() end)
  elseif type(RaidGroupFrame_Update) == "function" then
    local o2 = RaidGroupFrame_Update; RaidGroupFrame_Update = function() if o2 then o2() end; RaidSlave_DecorateRaidRoster() end
  end
end

local function InstallPartyHooks()
  if type(PartyMemberFrame_UpdateMember) == "function" then
    if type(hooksecurefunc) == "function" then
      hooksecurefunc("PartyMemberFrame_UpdateMember", function()
        if type(RaidSlave_DecoratePartyFrames) == "function" then RaidSlave_DecoratePartyFrames() end
        if type(RaidSlave_DecoratePlayerFrame) == "function" then RaidSlave_DecoratePlayerFrame() end
      end)
    else
      local o = PartyMemberFrame_UpdateMember
      PartyMemberFrame_UpdateMember = function(...)
        if o then o(unpack(arg)) end
        if type(RaidSlave_DecoratePartyFrames) == "function" then RaidSlave_DecoratePartyFrames() end
        if type(RaidSlave_DecoratePlayerFrame) == "function" then RaidSlave_DecoratePlayerFrame() end
      end
    end
  end

  if type(PartyMemberFrame_Update) == "function" then
    if type(hooksecurefunc) == "function" then
      hooksecurefunc("PartyMemberFrame_Update", function()
        if type(RaidSlave_DecoratePartyFrames) == "function" then RaidSlave_DecoratePartyFrames() end
        if type(RaidSlave_DecoratePlayerFrame) == "function" then RaidSlave_DecoratePlayerFrame() end
      end)
    else
      local o2 = PartyMemberFrame_Update
      PartyMemberFrame_Update = function(...)
        if o2 then o2(unpack(arg)) end
        if type(RaidSlave_DecoratePartyFrames) == "function" then RaidSlave_DecoratePartyFrames() end
        if type(RaidSlave_DecoratePlayerFrame) == "function" then RaidSlave_DecoratePlayerFrame() end
      end
    end
  end

  if type(PlayerFrame_Update) == "function" then
    if type(hooksecurefunc) == "function" then
      hooksecurefunc("PlayerFrame_Update", function()
        if type(RaidSlave_DecoratePlayerFrame) == "function" then RaidSlave_DecoratePlayerFrame() end
      end)
    else
      local op = PlayerFrame_Update
      PlayerFrame_Update = function(...)
        if op then op(unpack(arg)) end
        if type(RaidSlave_DecoratePlayerFrame) == "function" then RaidSlave_DecoratePlayerFrame() end
      end
    end
  end
end

InstallRosterHooks()

------------------------------------------------------------
-- Manual push & clear-all (exported)
------------------------------------------------------------
function RaidSlaveRaidRoles_PushRoles(silent)
  -- No network sync in RaidSlave - just refresh visuals
  EnsureDB()
  if not silent and (DEFAULT_CHAT_FRAME or ChatFrame1) then
    (DEFAULT_CHAT_FRAME or ChatFrame1):AddMessage("|cffff6600RaidSlave:|r Roles are local-only (no network sync).")
  end
  RaidSlave_DecorateRaidRoster()
end

local function WipeRoles(reason)
  EnsureDB()
  RaidSlaveDB.Healers = {}
  RaidSlaveDB.DPS = {}
  RaidSlaveDB.Tanks = {}
  RaidSlaveDB.MasterLooter = ""
  Pfui_ReapplyAllTanks()
  if type(RaidSlave_DecorateRaidRoster) == "function" then RaidSlave_DecorateRaidRoster() end
  if (DEFAULT_CHAT_FRAME or ChatFrame1) then
    (DEFAULT_CHAT_FRAME or ChatFrame1):AddMessage("|cffff6600RaidSlave:|r Role tags cleared" .. (reason and (" (" .. reason .. ")") or "") .. ".")
  end
end

function RaidSlaveRaidRoles_ClearAllRoles(silent)
  EnsureDB()
  WipeRoles("manual clear")
end

SLASH_RSPUSH1 = "/rs_pushroles"
SLASH_RSPUSH2 = "/rspush"
SlashCmdList["RSPUSH"] = function() RaidSlaveRaidRoles_PushRoles(false) end

SLASH_RSCLEAR1 = "/rs_clearroles"
SLASH_RSCLEAR2 = "/rsclear"
SlashCmdList["RSCLEAR"] = function() RaidSlaveRaidRoles_ClearAllRoles(false) end

------------------------------------------------------------
-- SELF menu visibility
------------------------------------------------------------
local UpdateSelfMenuVisibility
local InstallShowMenuHook
local showMenuHookInstalled = false

local function MenuHasKey(menu, key)
  if not menu then return false end
  for i = 1, table.getn(menu) do
    if menu[i] == key then return true end
  end
  return false
end

local function MenuRemoveKey(menu, key)
  if not menu then return end
  local i = 1
  while i <= table.getn(menu) do
    if menu[i] == key then
      table.remove(menu, i)
    else
      i = i + 1
    end
  end
end

local function MenuEnsureKey(menu, key, insertIndex)
  if not menu then return end
  if not MenuHasKey(menu, key) then
    table.insert(menu, insertIndex or 3, key)
  end
end

UpdateSelfMenuVisibility = function()
  if not UnitPopupMenus then return end
  local menu = UnitPopupMenus["SELF"]
  if not menu then return end
  local inRaid  = UnitInRaid and UnitInRaid("player")
  local inParty = (GetNumPartyMembers and (GetNumPartyMembers() or 0) > 0) and true or false
  if inParty and not inRaid then
    MenuEnsureKey(menu, BUTTON_KEY_HEALER, 3)
    MenuEnsureKey(menu, BUTTON_KEY_DPS,    4)
    MenuEnsureKey(menu, BUTTON_KEY_TANK,   5)
  else
    MenuRemoveKey(menu, BUTTON_KEY_HEALER)
    MenuRemoveKey(menu, BUTTON_KEY_DPS)
    MenuRemoveKey(menu, BUTTON_KEY_TANK)
  end
end

InstallShowMenuHook = function()
  if showMenuHookInstalled then return end
  showMenuHookInstalled = true
  local orig = UnitPopup_ShowMenu
  UnitPopup_ShowMenu = function(...)
    UpdateSelfMenuVisibility()
    if orig then
      return orig(unpack(arg))
    end
  end
end

------------------------------------------------------------
-- Init & Events
------------------------------------------------------------
local function AddMenuAndHooks()
  EnsureDB()
  RS_DetectPfUI()
  RS_DetectSuperWoW()
  DetectExternalTankMenuKey()
  OFFSET_BEFORE_NAME_ACTIVE = RS_hasPfUI and OFFSET_BEFORE_NAME_PFUI or OFFSET_BEFORE_NAME_DEFAULT
  AddMenuButton()
  InstallClickHook()
  InstallPartyHooks()
  UpdateSelfMenuVisibility()
  InstallShowMenuHook()
  RaidSlave_DecorateRaidRoster()
  Pfui_ReapplyAllTanks()
end

local selfWasInRaid = false

local f = CreateFrame("Frame")
f:RegisterEvent("VARIABLES_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("RAID_ROSTER_UPDATE")
f:RegisterEvent("PARTY_MEMBERS_CHANGED")
f:RegisterEvent("PARTY_LEADER_CHANGED")

f:SetScript("OnEvent", function()
  if event == "PARTY_MEMBERS_CHANGED" or event == "PARTY_LEADER_CHANGED" then
    EnsureDB()
    UpdateSelfMenuVisibility()

    local inRaidNow = UnitInRaid and UnitInRaid("player")
    if not inRaidNow then
      local pn = (GetNumPartyMembers and (GetNumPartyMembers() or 0)) or 0
      local inPartyNow = (pn > 0) and true or false

      if not inPartyNow then
        WipeRoles("left party")
      else
        local present = {}
        local me = UnitName and UnitName("player")
        if me and me ~= "" then present[me] = true end
        for i = 1, pn do
          local u = "party" .. i
          if UnitExists and UnitExists(u) then
            local nm = UnitName(u)
            if nm and nm ~= "" then present[nm] = true end
          end
        end

        for n in pairs(RaidSlaveDB.Healers) do if not present[n] then RaidSlaveDB.Healers[n] = nil end end
        for n in pairs(RaidSlaveDB.DPS)     do if not present[n] then RaidSlaveDB.DPS[n]     = nil end end
        for n in pairs(RaidSlaveDB.Tanks)   do if not present[n] then RaidSlaveDB.Tanks[n]   = nil end end
        if RaidSlaveDB.MasterLooter and RaidSlaveDB.MasterLooter ~= "" and not present[RaidSlaveDB.MasterLooter] then
          RaidSlaveDB.MasterLooter = ""
        end

        Pfui_ReapplyAllTanks()
        if type(RaidSlave_DecoratePartyFrames) == "function" then RaidSlave_DecoratePartyFrames() end
        if type(RaidSlave_DecoratePlayerFrame) == "function" then RaidSlave_DecoratePlayerFrame() end
      end
    end
    NotifyBuilder()
    return
  end

  if event == "RAID_ROSTER_UPDATE" then
    local inRaid = UnitInRaid("player")
    if (not inRaid) and selfWasInRaid then
      WipeRoles("left raid")
    end
    selfWasInRaid = inRaid and true or false

  elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_LOGIN" or event == "VARIABLES_LOADED" then
    AddMenuAndHooks()
    selfWasInRaid = UnitInRaid("player") and true or false
  end
end)
