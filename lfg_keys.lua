local AddonName, KSLBestDungeon = ...;
local Addon = KSLBestDungeon;

--[[ KSLBestDungeon -- group keys beside Blizzard's Create Group form (V1.6)

    A friend's request (2026-10-10): a leader listing the group's key has to
    hunt for it in the Create Group form's dungeon dropdown, which opens on
    the LEADER's own key. This panel sits beside that form and lists every key
    we know -- yours always, your groupmates' when their addons share them
    (the LibKeystone answers collected in KSLBestDungeon.lua) -- and clicking
    one sets the form to that dungeon.

    How the form is set: LFGListEntryCreation_Select, the same function the
    form's own dropdown and its own-keystone prefill call. That makes the
    selection a value WE wrote; listing is C_LFGList.CreateListing, flagged
    HasRestrictions, which could have refused it. It does not: confirmed in
    game with /kslbd lfgtest (2026-10-10), for your own key and for one you do
    not hold. Blizzard's own rule still applies: an account without the
    authenticator can only list a key it holds (LFGList.lua,
    mythicPlusDisableActivity) -- the form says so itself.

    The title: addons CANNOT write it (securityDisableSetText on the box), and
    the game fills it (C_LFGList.SetEntryTitle) with YOUR key's level only.
    For another player's key the panel focuses the box and says what to type.

    Keys arrive by challenge-mode map ID; the form wants a group-finder
    activity. Both carry the instance map ID (GetMapUIInfo's 6th return,
    GroupFinderActivityInfo.mapID), which is how one is turned into the other.
]]

local L = Addon.L;
local ROW_HEIGHT = 22;
local PANEL_WIDTH = 220;

-- [instance mapID] = { activityID, groupID } for this season's M+ activities.
local function MythicPlusActivities()
    local byMap = {};
    local ids = C_LFGList.GetAvailableActivities(GROUP_FINDER_CATEGORY_ID_DUNGEONS) or {};
    for _, id in ipairs(ids) do
        local info = C_LFGList.GetActivityInfoTable(id);
        if info and info.isMythicPlusActivity and info.mapID then
            byMap[info.mapID] = { activityID = id, groupID = info.groupFinderActivityGroupID };
        end
    end
    return byMap;
end

-- Every key we know: { name, classFile, challengeMapID, level, dungeon, own }.
-- Yours first, then the group's by name.
local function KnownKeys()
    local keys = {};
    local myMap, myLevel = Addon:GetOwnKeystone();
    if myMap and myLevel then
        local _, classFile = UnitClass("player");
        keys[#keys + 1] = { name = UnitName("player"), classFile = classFile, mapID = myMap, level = myLevel, own = true };
    end
    local others = {};
    for name, k in pairs(Addon:GetGroupKeys()) do
        local _, classFile = UnitClass(name);
        others[#others + 1] = { name = name, classFile = k.classFile or classFile, mapID = k.mapID, level = k.level };
    end
    table.sort(others, function(a, b) return a.name < b.name; end);
    for _, k in ipairs(others) do keys[#keys + 1] = k; end
    for _, k in ipairs(keys) do
        k.dungeon = C_ChallengeMode.GetMapUIInfo(k.mapID) or ("Dungeon " .. k.mapID);
    end
    return keys;
end

local panel;

-- ------------------------------------------------------------------
-- Playstyle (user request 2026-10-10). The form refuses to list without one
-- ("Select Playstyle (required)"), so the panel fills it from a remembered
-- choice, Relaxed by default. Set through the function Blizzard's own
-- dropdown calls (LFGListEntryCreation_OnPlayStyleSelectedInternal) -- the
-- value lands in the listing data like the dungeon does, which lists fine
-- from an addon (unlike the title box, which is locked).
-- ------------------------------------------------------------------
local PLAYSTYLE_OFF = 0;
local function SavedPlaystyle()
    local s = Addon:GetSetting("lfgPlaystyle");
    if s == nil then s = Enum.LFGEntryGeneralPlaystyle.FunRelaxed; end   -- saves from before V1.6
    return s;
end

-- `force`: the player just chose it in our dropdown, so it replaces whatever
-- the form has. Otherwise only an EMPTY playstyle is filled, never one the
-- player picked in Blizzard's own dropdown.
local function ApplyPlaystyle(form, force)
    if not form or LFGListEntryCreation_IsEditMode(form) then return; end
    local style = SavedPlaystyle();
    if style == PLAYSTYLE_OFF then return; end
    ---@diagnostic disable-next-line: undefined-field
    local current = form.generalPlaystyle;
    if not force and current and current ~= Enum.LFGEntryGeneralPlaystyle.None then return; end
    LFGListEntryCreation_OnPlayStyleSelectedInternal(form, style);
    if form.PlayStyleDropdown and form.PlayStyleDropdown.GenerateMenu then
        pcall(form.PlayStyleDropdown.GenerateMenu, form.PlayStyleDropdown);   -- refresh its label
    end
end

-- Set Blizzard's form to a key's dungeon (the title is the player's; see below).
local function ChooseKey(form, key)
    local _, _, _, _, _, instanceMapID = C_ChallengeMode.GetMapUIInfo(key.mapID);
    local act = instanceMapID and MythicPlusActivities()[instanceMapID];
    if not act then
        print("|cff9d5db8KSLBestDungeon|r: " .. key.dungeon .. " is not listable as a Mythic+ dungeon right now.");
        return;
    end
    local info = C_LFGList.GetActivityInfoTable(act.activityID);
    -- selectedFilters is Blizzard's runtime field on the form; nil is fine.
    ---@diagnostic disable-next-line: undefined-field
    LFGListEntryCreation_Select(form, form.selectedFilters, info and info.categoryID, act.groupID, act.activityID);

    -- The title CANNOT be set by an addon: Blizzard declares the box with
    -- securityDisableSetText="true" (LFGList.xml, LFGListCreationName), so
    -- SetText from addon code is silently ignored -- found 2026-10-10 after
    -- two attempts showed a blank title. The game fills it itself
    -- (C_LFGList.SetEntryTitle) with YOUR key's level only. So for anyone
    -- else's key: put the cursor in the box, if the game allows that, and
    -- tell the player what to type.
    panel.hintActivity = act.activityID;
    if key.own then
        panel.hint:SetText("");
    else
        panel.hint:SetText(("Type |cffffffff+%d|r as the title"):format(key.level));
        if form.Name and form.Name.SetFocus then pcall(form.Name.SetFocus, form.Name); end
    end
    panel:SetHeight(panel.listHeight + (panel.hint:GetText() ~= "" and 18 or 0));
end


-- Where the panel docks: to the right of the Group Finder window, or, when
-- Raider.IO's profile panel is showing there (it docks on that same edge,
-- user screenshot 2026-10-10), to the right of THAT. Not the left: Blizzard
-- opens the Group Finder against the left of the screen and does not keep a
-- moved position, so a left-hand panel was off screen for most players.
-- Anchored live to whichever edge, so Raider.IO's changing height and width
-- carry it along.
local RIO_PANEL = "RaiderIO_ProfileTooltip";
local function Dock()
    if not panel then return; end
    local rio = _G[RIO_PANEL];
    local onRio = rio and rio:IsShown();
    if panel._dockedOnRio == onRio and panel:GetNumPoints() > 0 then return; end
    panel._dockedOnRio = onRio;
    panel:ClearAllPoints();
    if onRio then
        panel:SetPoint("TOPLEFT", rio, "TOPRIGHT", 4, 0);
    else
        panel:SetPoint("TOPLEFT", PVEFrame, "TOPRIGHT", 4, -24);
    end
end

local function Refresh()
    local form = LFGListFrame and LFGListFrame.EntryCreation;
    if not (panel and form and form:IsVisible()) then return; end
    -- Dungeons only, and not while editing a live listing: its dungeon is
    -- locked then (the form disables its own dropdowns too).
    ---@diagnostic disable-next-line: undefined-field
    local category = form.selectedCategory;
    if category ~= GROUP_FINDER_CATEGORY_ID_DUNGEONS or LFGListEntryCreation_IsEditMode(form) then
        panel:Hide();
        return;
    end
    -- Re-docked every pass (once a second while the form is up): Raider.IO's
    -- panel can appear or go after ours is placed, and is not ours to hook.
    Dock();
    local keys = KnownKeys();
    if #keys == 0 then panel:Hide(); return; end

    for i, key in ipairs(keys) do
        local row = panel.rows[i];
        if not row then
            row = CreateFrame("Button", nil, panel);
            row:SetSize(PANEL_WIDTH - 16, ROW_HEIGHT);
            row:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -60 - (i - 1) * ROW_HEIGHT);
            row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD");
            row.level = row:CreateFontString(nil, "OVERLAY", "GameFontNormal");
            row.level:SetPoint("RIGHT", row, "RIGHT", -2, 0);
            row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
            row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -1);
            row.name:SetPoint("RIGHT", row.level, "LEFT", -4, 0);
            row.name:SetJustifyH("LEFT");
            row.dungeon = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall");
            row.dungeon:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 2, 1);
            row.dungeon:SetPoint("RIGHT", row.level, "LEFT", -4, 0);
            row.dungeon:SetJustifyH("LEFT");
            row:SetScript("OnClick", function(self) ChooseKey(form, self.key); end);
            row:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
                GameTooltip:AddLine(self.key.dungeon .. " +" .. self.key.level, 1, 1, 1);
                GameTooltip:AddLine(self.key.own and L["Your keystone"] or (self.key.name .. L["'s keystone"]), 0.6, 0.6, 0.6);
                GameTooltip:AddLine(L["Click to list this key."], 0.31, 0.88, 0.36);
                GameTooltip:Show();
            end);
            row:SetScript("OnLeave", GameTooltip_Hide);
            panel.rows[i] = row;
        end
        row.key = key;
        -- UnitClass can answer secret on 12.1; a secret cannot index a table.
        local classFile = key.classFile;
        if classFile and issecretvalue and issecretvalue(classFile) then classFile = nil; end
        local color = classFile and RAID_CLASS_COLORS[classFile];
        row.name:SetText(key.own and (key.name .. " " .. L["(you)"]) or key.name);
        if color then row.name:SetTextColor(color.r, color.g, color.b); else row.name:SetTextColor(1, 1, 1); end
        row.dungeon:SetText(key.dungeon);
        row.level:SetText("+" .. key.level);
        row:Show();
    end
    for i = #keys + 1, #panel.rows do panel.rows[i]:Hide(); end
    -- The title reminder belongs to the dungeon it was given for; picked
    -- something else from Blizzard's dropdown since, it goes.
    ---@diagnostic disable-next-line: undefined-field
    if panel.hintActivity and form.selectedActivity ~= panel.hintActivity then
        panel.hintActivity = nil;
        panel.hint:SetText("");
    end
    panel.listHeight = 68 + #keys * ROW_HEIGHT;
    panel:SetHeight(panel.listHeight + (panel.hint:GetText() ~= "" and 18 or 0));
    panel:Show();
end

local function CreatePanel()
    local form = LFGListFrame and LFGListFrame.EntryCreation;
    if panel or not form then return; end
    -- A child of the form, so it shows and hides with it; docked outside the
    -- Group Finder window by Dock() above.
    panel = CreateFrame("Frame", "KSLBestDungeonGroupKeys", form, "BackdropTemplate");
    panel:SetWidth(PANEL_WIDTH);
    Dock();
    panel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    });
    panel:SetBackdropColor(0.05, 0.05, 0.07, 0.92);
    panel:SetBackdropBorderColor(0.62, 0.36, 0.72, 0.9);
    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal");
    panel.title:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -8);
    panel.title:SetText("|cff9d5db8" .. L["Group Keys"] .. "|r");

    -- Playstyle: Blizzard's own modern dropdown template, with the same four
    -- choices its form offers plus "Don't set". The choice is remembered and
    -- is what gets filled in each time the form opens.
    local styleLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall");
    styleLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -30);
    styleLabel:SetText(L["Playstyle"]);
    local style = CreateFrame("DropdownButton", nil, panel, "WowStyle1DropdownTemplate");
    style:SetPoint("LEFT", styleLabel, "RIGHT", 8, 0);
    style:SetPoint("RIGHT", panel, "RIGHT", -10, 0);
    local G = Enum.LFGEntryGeneralPlaystyle;
    style:SetupMenu(function(_, root)
        local function IsSelected(v) return SavedPlaystyle() == v; end
        local function SetSelected(v)
            Addon:SetSetting("lfgPlaystyle", v);
            ApplyPlaystyle(form, true);
        end
        -- Blizzard's names for them. Its GetGeneralPlaystyleString is LOCAL to
        -- LFGList.lua (calling it was a nil-call error, 2026-10-10); these are
        -- the global strings it returns, so they localise the same way.
        local names = {
            [G.Learning] = GROUP_FINDER_GENERAL_PLAYSTYLE1 or "Learning",
            [G.FunRelaxed] = GROUP_FINDER_GENERAL_PLAYSTYLE2 or "Relaxed",
            [G.FunSerious] = GROUP_FINDER_GENERAL_PLAYSTYLE3 or "Competitive",
            [G.Expert] = GROUP_FINDER_GENERAL_PLAYSTYLE4 or "Carry Offered",
        };
        for _, v in ipairs({ G.Learning, G.FunRelaxed, G.FunSerious, G.Expert }) do
            root:CreateRadio(names[v], IsSelected, SetSelected, v);
        end
        root:CreateRadio(L["Don't set"], IsSelected, SetSelected, PLAYSTYLE_OFF);
    end);
    panel.style = style;
    panel.rows = {};
    -- "Type +N as the title": the one thing the panel cannot do for you.
    panel.hint = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    panel.hint:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 10, 8);
    panel.hint:SetPoint("RIGHT", panel, "RIGHT", -10, 0);
    panel.hint:SetJustifyH("LEFT");
    panel.hint:SetText("");
    panel.listHeight = 68;

    -- Ask the group as the form opens, and redraw once a second while it is
    -- up, so an answer arriving late shows. Cheap: a handful of rows.
    panel:SetScript("OnShow", function() Addon:RequestGroupKeys(); end);
    local elapsed = 0;
    form:HookScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt;
        if elapsed < 1 then return; end
        elapsed = 0;
        Refresh();
    end);
    form:HookScript("OnShow", function()
        Addon:RequestGroupKeys();
        Refresh();
        -- Blizzard may clear the playstyle as it sets the form up, so fill it
        -- now and again on the next frame (an empty one only, each time).
        ApplyPlaystyle(form);
        C_Timer.After(0, function() ApplyPlaystyle(form); end);
    end);
    hooksecurefunc("LFGListEntryCreation_Select", function(f) if f == form then Refresh(); end end);
    Refresh();
end

-- The Group Finder is load-on-demand.
do
    local f = CreateFrame("Frame");
    f:RegisterEvent("ADDON_LOADED");
    f:SetScript("OnEvent", function(self, _, name)
        if name == "Blizzard_GroupFinder" or (LFGListFrame and LFGListFrame.EntryCreation) then
            CreatePanel();
            if panel then self:UnregisterAllEvents(); end
        end
    end);
    if LFGListFrame and LFGListFrame.EntryCreation then CreatePanel(); end
end

