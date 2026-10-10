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

    The title: the game builds it (C_LFGList.SetEntryTitle) when the dungeon
    changes and it carries YOUR key's level. If it starts with "+<level>" the
    level is swapped for the chosen key's; otherwise it is left alone.

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
local fakeKeys;   -- set only by the solo test command at the bottom of this file
local function KnownKeys()
    local keys = {};
    local myMap, myLevel = Addon:GetOwnKeystone();
    if myMap and myLevel then
        local _, classFile = UnitClass("player");
        keys[#keys + 1] = { name = UnitName("player"), classFile = classFile, mapID = myMap, level = myLevel, own = true };
    end
    local others = {};
    for name, k in pairs(fakeKeys or Addon:GetGroupKeys()) do
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

-- Set Blizzard's form to a key's dungeon, and its title to that key's level.
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

    -- The title. The game writes "+<level>" only for a key YOU hold; for any
    -- other it writes no level, and it may write after this returns -- only
    -- your own key's level ever showed (user report 2026-10-10). So set it
    -- now and again a moment later: swap a leading "+N", fill an empty title,
    -- or put the level in front of whatever else is there.
    local function ApplyTitle()
        local box = form.Name;
        if not (box and box:IsVisible()) then return; end
        local level = "+" .. key.level;
        local title = box:GetText() or "";
        if title:match("^%+%d+") then
            title = title:gsub("^%+%d+", level, 1);
        elseif strtrim(title) == "" then
            title = level;
        else
            title = level .. " " .. title;
        end
        box:SetText(title);
    end
    ApplyTitle();
    C_Timer.After(0.1, ApplyTitle);
end

local panel;

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
            row:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -28 - (i - 1) * ROW_HEIGHT);
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
    panel:SetHeight(36 + #keys * ROW_HEIGHT);
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
    panel.rows = {};

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

-- ===================================================================
-- TEMPORARY -- REMOVE BEFORE TAGGING V1.6 (user request 2026-10-10:
-- "a test command I can use solo ... that will not be released").
-- /kslbd groupkeystest  : fill the panel with three made-up groupmates
--                         holding random current dungeons, to check the
--                         look and the clicks without a group.
-- /kslbd groupkeystest off : back to the real group's keys.
-- ===================================================================
function Addon:GroupKeysTest(off)
    if off then
        fakeKeys = nil;
        print("|cff9d5db8KSLBestDungeon|r: group keys test off.");
    else
        local maps = C_ChallengeMode.GetMapTable() or {};
        local classes = { "WARRIOR", "PRIEST", "MAGE", "DRUID", "HUNTER" };
        fakeKeys = {};
        for i, name in ipairs({ "Testtank", "Testheals", "Testdps" }) do
            local mapID = maps[((i * 3) % math.max(#maps, 1)) + 1];
            if mapID then
                fakeKeys[name] = { mapID = mapID, level = 8 + i * 2, classFile = classes[i] };
            end
        end
        print("|cff9d5db8KSLBestDungeon|r: group keys test on -- open Group Finder > Dungeons > Start a Group.");
    end
    Refresh();
end
-- ======================= END TEMPORARY ============================
