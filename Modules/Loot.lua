-- Loot.lua - Boss loot mode helper for RaidSlave
-- Ported from TacticaLoot.lua by Doite (stripped addon comms, simplified boss detection)

-------------------------------------------------
-- Compat shims
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

local function tlen(t)
  if table and table.getn then return table.getn(t) end
  local n = 0; for _ in pairs(t) do n = n + 1 end; return n
end

local function InRaid()
  return UnitInRaid and UnitInRaid("player")
end

local function IsRL()
  return (IsRaidLeader and IsRaidLeader() == 1) or false
end

local function EnsureLootDefaults()
  RaidSlaveDB = RaidSlaveDB or {}
  RaidSlaveDB.Settings = RaidSlaveDB.Settings or {}
  RaidSlaveDB.Settings.Loot = RaidSlaveDB.Settings.Loot or {}
  if RaidSlaveDB.Settings.Loot.AutoMasterLoot == nil then
    RaidSlaveDB.Settings.Loot.AutoMasterLoot = true
  end
  if RaidSlaveDB.Settings.Loot.AutoGroupPopup == nil then
    RaidSlaveDB.Settings.Loot.AutoGroupPopup = true
  end
  if RaidSlaveDB.Settings.LootPromptDefault == nil then
    RaidSlaveDB.Settings.LootPromptDefault = "group"
  end
  if RaidSlaveDB.LootSkip == nil then
    RaidSlaveDB.LootSkip = { active = false, leader = "" }
  end
end

-------------------------------------------------
-- Boss detection (simplified: worldboss only)
-------------------------------------------------
local function IsBossTarget()
  if not UnitExists("target") then return false end
  if UnitClassification and UnitClassification("target") == "worldboss" then
    return true
  end
  return false
end

-------------------------------------------------
-- Raid leader / master looter helpers
-------------------------------------------------
local function GetRaidLeaderName()
  if not InRaid() then return nil end
  for i = 1, GetNumRaidMembers() do
    local name, rank = GetRaidRosterInfo(i)
    if rank == 2 then return name end
  end
  return nil
end

local function GetMasterLooterName()
  local method, mlPartyID, mlRaidID = GetLootMethod()
  if method ~= "master" then return nil end
  if InRaid() and mlRaidID then
    local name = GetRaidRosterInfo(mlRaidID)
    return name
  elseif not InRaid() and mlPartyID then
    local unit = (mlPartyID == 0) and "player" or ("party" .. mlPartyID)
    return UnitName(unit)
  end
  return nil
end

local function GetPresetMasterLooter()
  if type(RaidSlaveRaidRoles_GetPresetMasterLooter) == "function" then
    local n = RaidSlaveRaidRoles_GetPresetMasterLooter()
    if n and n ~= "" then return n end
  end
  return nil
end

local function NormalizeName(n)
  if not n then return nil end
  local base = string.match(n, "^([^%-]+)")
  return string.lower(base or n)
end

local function IsSelfMasterLooter()
  local my = UnitName("player")
  local ml = GetMasterLooterName()
  return (NormalizeName(my) and NormalizeName(ml) and NormalizeName(my) == NormalizeName(ml)) or false
end

local function CountRemainingLootSlots()
  local n = GetNumLootItems and GetNumLootItems() or 0
  if n <= 0 then return 0 end
  local remaining = 0
  for i = 1, n do
    if LootSlotHasItem and LootSlotHasItem(i) then
      remaining = remaining + 1
    end
  end
  return remaining
end

local function ApplyPresetIfMasterLoot()
  if not (InRaid() and IsRL()) then return end
  local preset = GetPresetMasterLooter()
  if not preset or preset == "" then return end
  local method = GetLootMethod and GetLootMethod()
  if method ~= "master" then return end
  local current = GetMasterLooterName()
  if NormalizeName(current) == NormalizeName(preset) then return end
  SetLootMethod("master", preset)
end

-------------------------------------------------
-- Raid-scoped "don't ask again"
-------------------------------------------------
local function LootSkip_IsActiveForCurrentRaid()
  if not (RaidSlaveDB and RaidSlaveDB.LootSkip and RaidSlaveDB.LootSkip.active) then return false end
  if not InRaid() then return false end
  local leader = GetRaidLeaderName()
  return (leader and RaidSlaveDB.LootSkip.leader == leader) or false
end

local function LootSkip_ActivateForCurrentRaid()
  if not InRaid() then return end
  local leader = GetRaidLeaderName()
  if not leader then return end
  RaidSlaveDB.LootSkip.active = true
  RaidSlaveDB.LootSkip.leader = leader
end

local function LootSkip_Clear()
  if not RaidSlaveDB then return end
  RaidSlaveDB.LootSkip = { active = false, leader = "" }
end

-------------------------------------------------
-- Popup UI
-------------------------------------------------
local LootFrame, LootDropdown, LootMLDropdown, DontAskCB
local SelectedMethod = "group"
local SelectedPresetML = ""
local LOOT_METHODS = {
  { text = "Group Loot",        value = "group" },
  { text = "Round Robin",       value = "roundrobin" },
  { text = "Free-For-All",      value = "freeforall" },
  { text = "Need Before Greed", value = "needbeforegreed" },
  { text = "Master Looter",     value = "master" },
}

local function GetRaidLeaderNameForLabel()
  if not InRaid() then return "raidlead" end
  for i = 1, (GetNumRaidMembers() or 0) do
    local n, rank = GetRaidRosterInfo(i)
    if rank == 2 then return n or "raidlead" end
  end
  return "raidlead"
end

local function RaidMembersChronological()
  local t = {}
  if not InRaid() then return t end
  local leader = GetRaidLeaderNameForLabel()
  for i = 1, (GetNumRaidMembers() or 0) do
    local n = GetRaidRosterInfo(i)
    if n and n ~= "" and n ~= leader then table.insert(t, n) end
  end
  return t
end

local function SetDropdownEnabled(dd, enabled)
  if not dd then return end
  if dd.EnableMouse then dd:EnableMouse(enabled and true or false) end
  dd:SetAlpha(enabled and 1.0 or 0.55)
  local btn = dd.GetName and getglobal(dd:GetName() .. "Button") or nil
  if btn then
    if enabled and btn.Enable then btn:Enable()
    elseif (not enabled) and btn.Disable then btn:Disable() end
  end
end

local function InitPresetMLDropdown(dd)
  UIDropDownMenu_Initialize(dd, function()
    local info = {
      text = "None/" .. (GetRaidLeaderNameForLabel() or "raidlead"),
      func = function()
        SelectedPresetML = ""
        UIDropDownMenu_SetText("None/" .. (GetRaidLeaderNameForLabel() or "raidlead"), dd)
        if InRaid() and IsRL() and type(RaidSlaveRaidRoles_SetPresetMasterLooter) == "function" then
          RaidSlaveRaidRoles_SetPresetMasterLooter("")
        end
      end
    }
    UIDropDownMenu_AddButton(info)
    local names = RaidMembersChronological()
    for i = 1, tlen(names) do
      local nm = names[i]
      UIDropDownMenu_AddButton({
        text = nm,
        func = function()
          SelectedPresetML = nm
          UIDropDownMenu_SetText(nm, dd)
          if InRaid() and IsRL() and type(RaidSlaveRaidRoles_SetPresetMasterLooter) == "function" then
            RaidSlaveRaidRoles_SetPresetMasterLooter(nm)
          end
        end
      })
    end
  end)
end

local function CreateLootPopup()
  if LootFrame then return end

  local f = CreateFrame("Frame", "RaidSlaveLootPopup", UIParent)
  f:SetWidth(235); f:SetHeight(190)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  f:SetBackdrop({
    bgFile  = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 }
  })
  f:SetFrameStrata("DIALOG")
  f:Hide()

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOP", f, "TOP", 0, -12)
  title:SetText("Switch Loot Method")

  local label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  label:SetPoint("TOP", f, "TOP", 0, -30)
  label:SetText("Do you want to switch to:")

  local dd = CreateFrame("Frame", "RaidSlaveLootDropdown", f, "UIDropDownMenuTemplate")
  dd:SetPoint("TOP", f, "TOP", 15, -45)
  dd:SetWidth(200)
  LootDropdown = dd

  UIDropDownMenu_Initialize(dd, function()
    for i = 1, tlen(LOOT_METHODS) do
      local opt = LOOT_METHODS[i]
      local info = {
        text = opt.text,
        func = function()
          SelectedMethod = opt.value
          UIDropDownMenu_SetText(opt.text, dd)
        end
      }
      UIDropDownMenu_AddButton(info)
    end
  end)

  local mlLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  mlLabel:SetPoint("TOP", f, "TOP", 0, -75)
  mlLabel:SetText("Preset Masterlooter:")

  local mlDD = CreateFrame("Frame", "RaidSlaveLootMLDropdown", f, "UIDropDownMenuTemplate")
  mlDD:SetPoint("TOP", f, "TOP", 15, -90)
  mlDD:SetWidth(200)
  LootMLDropdown = mlDD
  InitPresetMLDropdown(mlDD)

  local cb = CreateFrame("CheckButton", "RaidSlaveLootDontAskCB", f, "UICheckButtonTemplate")
  cb:SetWidth(24); cb:SetHeight(24)
  cb:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 35, 40)
  local cbText = getglobal("RaidSlaveLootDontAskCBText")
  if cbText then cbText:SetText("Don't ask again this raid") end
  DontAskCB = cb

  local yes = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  yes:SetWidth(100); yes:SetHeight(24)
  yes:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 16)
  yes:SetText("Yes - Change")
  yes:SetScript("OnClick", function()
    if not (InRaid() and IsRL()) then
      local cf = DEFAULT_CHAT_FRAME or ChatFrame1
      cf:AddMessage("|cffff5555RaidSlave:|r Only the raid leader can change loot method.")
      f:Hide()
      return
    end
    local method = SelectedMethod or "group"
    if method == "master" then
      local ml = GetPresetMasterLooter() or UnitName("player")
      SetLootMethod("master", ml)
    else
      SetLootMethod(method)
    end
    if DontAskCB and DontAskCB:GetChecked() then
      LootSkip_ActivateForCurrentRaid()
    end
    f:Hide()
  end)

  local keep = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  keep:SetWidth(100); keep:SetHeight(24)
  keep:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 16)
  keep:SetText("No - Keep")
  local fs = keep:GetFontString()
  if fs and fs.SetTextColor then fs:SetTextColor(0.2, 1.0, 0.2) end
  keep:SetNormalTexture("Interface\\Buttons\\UI-Panel-Button-Up")
  local nt = keep:GetNormalTexture(); if nt then nt:SetVertexColor(0.2, 0.8, 0.2) end
  keep:SetPushedTexture("Interface\\Buttons\\UI-Panel-Button-Down")
  local pt = keep:GetPushedTexture(); if pt then pt:SetVertexColor(0.2, 0.8, 0.2) end
  keep:SetHighlightTexture("Interface\\Buttons\\UI-Panel-Button-Highlight")
  local ht = keep:GetHighlightTexture(); if ht then ht:SetBlendMode("ADD"); ht:SetVertexColor(0.2, 1.0, 0.2) end
  keep:SetScript("OnClick", function()
    if DontAskCB and DontAskCB:GetChecked() then
      LootSkip_ActivateForCurrentRaid()
    end
    f:Hide()
  end)

  LootFrame = f
end

function RaidSlaveLoot_ShowPopup()
  EnsureLootDefaults()
  CreateLootPopup()
  local def = (RaidSlaveDB and RaidSlaveDB.Settings and RaidSlaveDB.Settings.LootPromptDefault) or "group"
  SelectedMethod = def
  local shown = "Group Loot"
  for i = 1, tlen(LOOT_METHODS) do
    if LOOT_METHODS[i].value == def then shown = LOOT_METHODS[i].text end
  end
  if LootDropdown then UIDropDownMenu_SetText(shown, LootDropdown) end
  if LootMLDropdown then
    InitPresetMLDropdown(LootMLDropdown)
    SelectedPresetML = (GetPresetMasterLooter() or "")
    UIDropDownMenu_SetText((SelectedPresetML ~= "" and SelectedPresetML) or ("None/" .. (GetRaidLeaderNameForLabel() or "raidlead")), LootMLDropdown)
    SetDropdownEnabled(LootMLDropdown, InRaid() and IsRL())
  end
  LootFrame:Show()
end

-------------------------------------------------
-- Events & flow (simplified - no multi-mob tracking)
-------------------------------------------------
local TL_AwaitingLoot   = false
local TL_SawLootWindow  = false
local TL_SlotsRemaining = nil
local TL_WasInRaid      = false
local TL_AlreadyOnMsgShown = false
local TL_LastBossName   = nil

-- Called when boss is targeted (from PLAYER_TARGET_CHANGED)
function RaidSlaveLoot_OnBossTargeted(raidName, bossName)
  EnsureLootDefaults()
  if not (InRaid() and IsRL()) then return end
  if not (RaidSlaveDB.Settings and RaidSlaveDB.Settings.Loot and RaidSlaveDB.Settings.Loot.AutoMasterLoot) then return end
  if not IsBossTarget() then return end

  local method = GetLootMethod and GetLootMethod()
  if method ~= "master" then
    TL_AlreadyOnMsgShown = false
  end
  if method == "master" then
    if not TL_AlreadyOnMsgShown then
      local cf = DEFAULT_CHAT_FRAME or ChatFrame1
      cf:AddMessage("|cffff6600RaidSlave:|r Masterloot is already on.")
      TL_AlreadyOnMsgShown = true
    end
    return
  end
  local ml = GetPresetMasterLooter() or UnitName("player")
  SetLootMethod("master", ml)
  TL_AlreadyOnMsgShown = false
  local cf = DEFAULT_CHAT_FRAME or ChatFrame1
  cf:AddMessage("|cffff6600RaidSlave:|r Enabled Masterloot.")
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("RAID_ROSTER_UPDATE")
f:RegisterEvent("PLAYER_TARGET_CHANGED")
f:RegisterEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH")
f:RegisterEvent("LOOT_OPENED")
f:RegisterEvent("LOOT_SLOT_CLEARED")
f:RegisterEvent("LOOT_CLOSED")
f:RegisterEvent("PARTY_LOOT_METHOD_CHANGED")

f:SetScript("OnEvent", function()
  EnsureLootDefaults()

  if event == "PLAYER_ENTERING_WORLD" then
    TL_WasInRaid = InRaid() and true or false
    if not TL_WasInRaid then
      TL_AwaitingLoot = false
      TL_SawLootWindow = false
      TL_SlotsRemaining = nil
    end

  elseif event == "RAID_ROSTER_UPDATE" then
    local now = InRaid() and true or false
    if TL_WasInRaid and not now then
      LootSkip_Clear()
      TL_AwaitingLoot = false
      TL_SawLootWindow = false
      TL_SlotsRemaining = nil
    elseif now then
      local leader = GetRaidLeaderName()
      if RaidSlaveDB.LootSkip.active and leader and leader ~= RaidSlaveDB.LootSkip.leader then
        LootSkip_Clear()
      end
    end
    TL_WasInRaid = now

  elseif event == "PLAYER_TARGET_CHANGED" then
    -- Track boss targeting for auto-ML and loot flow
    if IsBossTarget() then
      TL_LastBossName = UnitName("target")
      -- Auto-ML
      if RaidSlaveDB.Settings and RaidSlaveDB.Settings.Loot and RaidSlaveDB.Settings.Loot.AutoMasterLoot then
        RaidSlaveLoot_OnBossTargeted(nil, TL_LastBossName)
      end
    end

  elseif event == "CHAT_MSG_COMBAT_HOSTILE_DEATH" then
    local dead = string.match(arg1 or "", "^(.+) dies%.$")
    if dead and TL_LastBossName and string.lower(dead) == string.lower(TL_LastBossName) then
      TL_AwaitingLoot = true
      TL_SlotsRemaining = nil
      TL_SawLootWindow = false
    end

  elseif event == "LOOT_OPENED" then
    if not TL_AwaitingLoot then return end
    TL_SawLootWindow = true
    TL_SlotsRemaining = CountRemainingLootSlots()

  elseif event == "LOOT_SLOT_CLEARED" then
    if TL_SlotsRemaining and TL_SlotsRemaining > 0 then
      TL_SlotsRemaining = TL_SlotsRemaining - 1
    end

  elseif event == "LOOT_CLOSED" then
    if not TL_AwaitingLoot then return end
    if not InRaid() then return end
    if not (RaidSlaveDB.Settings and RaidSlaveDB.Settings.Loot and RaidSlaveDB.Settings.Loot.AutoGroupPopup) then return end
    if LootSkip_IsActiveForCurrentRaid() then return end
    if not IsRL() then return end

    local method = GetLootMethod and GetLootMethod()
    if method ~= "master" then return end
    if not IsSelfMasterLooter() then return end
    if not TL_SawLootWindow then return end

    TL_SlotsRemaining = CountRemainingLootSlots()
    if (TL_SlotsRemaining or 0) == 0 then
      TL_AwaitingLoot = false
      RaidSlaveLoot_ShowPopup()
    end

  elseif event == "PARTY_LOOT_METHOD_CHANGED" then
    ApplyPresetIfMasterLoot()
  end
end)
