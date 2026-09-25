local AddonName, KSLBestDungeon = ...;
local Addon = KSLBestDungeon;

-- Constants (matching KeystoneLoot)
local TIER_NICE = 1;
local TIER_MUST = 2;
local TIER_BIS = 3;
local TIER_TRANSMOG = 4;
local TIER_CATALYST = 5;

local TIER_NAME = {
    [TIER_NICE] = "Nice to have",
    [TIER_MUST] = "Must have",
    [TIER_BIS] = "Best in Slot",
    [TIER_TRANSMOG] = "Transmog",
    [TIER_CATALYST] = "Catalyst",
};

local TIER_COLOR = {
    [TIER_BIS] = "|cff00ff00",
    [TIER_MUST] = "|cffffff00",
    [TIER_NICE] = "|cff00ffff",
    [TIER_TRANSMOG] = "|cff808080",
    [TIER_CATALYST] = "|cffa335ee",
};

-- StaticPopup for whisper target
StaticPopupDialogs["KSLBESTDUNGEON_WHISPER_TARGET"] = {
    text = "Enter character name to whisper:",
    button1 = ACCEPT,
    button2 = CANCEL,
    hasEditBox = 1,
    maxLetters = 12,
    editBoxWidth = 200,
    -- 12.x dialogs expose their edit box through GetEditBox(); the old dialog.editBox
    -- field no longer exists.
    OnAccept = function(self)
        local editBox = self.GetEditBox and self:GetEditBox() or self.editBox;
        local target = editBox and strtrim(editBox:GetText());
        if (target and target ~= "") then
            Addon:SendRankedDungeonsToChat("WHISPER", target);
        end
    end,
    OnShow = function(self)
        local editBox = self.GetEditBox and self:GetEditBox() or self.editBox;
        if (editBox) then editBox:SetFocus(); end
    end,
    OnHide = function(self)
        ChatEdit_FocusActiveWindow();
        local editBox = self.GetEditBox and self:GetEditBox() or self.editBox;
        if (editBox) then editBox:SetText(""); end
    end,
    EditBoxOnEnterPressed = function(self)
        local target = strtrim(self:GetText());
        if (target and target ~= "") then
            Addon:SendRankedDungeonsToChat("WHISPER", target);
        end
        self:GetParent():Hide();
    end,
    EditBoxOnEscapePressed = function(self)
        self:GetParent():Hide();
    end,
    timeout = 0,
    exclusive = 1,
    whileDead = 1,
    hideOnEscape = 1,
};

-- ============================================================
-- Share (send the ranking to chat)
-- ============================================================

-- Chat rejects anything longer than this.
local MAX_CHAT_LENGTH = 255;

-- Readable names for the Share menu and the "Sent to ..." confirmation.
local CHANNEL_LABEL = {
    PARTY = "Party",
    INSTANCE_CHAT = "Instance",
    GUILD = "Guild",
    SAY = "Say",
    YELL = "Yell",
    WHISPER = "Whisper",
    BN_WHISPER = "Battle.net friend",
};

-- Send ranked dungeons to chat channel
function Addon:SendRankedDungeonsToChat(channel, whisperTarget)
    local ranked = Addon:GetRankedDungeons();
    if (#ranked == 0) then
        print("|cff9d5db8KSLBestDungeon|r: No dungeons to send");
        return;
    end

    -- Add dungeons in rank order until the next one would push the message past the
    -- chat limit, rather than letting the whole message be rejected.
    local message = "KSL Best Dungeons: ";
    for i, dungeonData in ipairs(ranked) do
        local part = string.format("%s%d.[%s]", (i > 1) and ", " or "", i, dungeonData.dungeon.name);
        if (#message + #part > MAX_CHAT_LENGTH) then break; end
        message = message .. part;
    end

    local SendChat = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage;
    local label = CHANNEL_LABEL[channel] or channel;

    if (channel == "WHISPER" and whisperTarget) then
        SendChat(message, "WHISPER", nil, whisperTarget);
    elseif (channel == "BN_WHISPER" and whisperTarget) then
        -- whisperTarget is the bnetAccountID (presenceID)
        BNSendWhisper(whisperTarget, message);
        print("|cff9d5db8KSLBestDungeon|r: Sent to " .. label);
    else
        SendChat(message, channel);
        print("|cff9d5db8KSLBestDungeon|r: Sent to " .. label);
    end
end

-- Only channels you can post to right now are enabled; the rest are listed greyed out
-- with the reason, so it is clear why they cannot be picked.
local function GenerateShareMenu(dropdown, rootDescription)
    local channels = {
        { value = "PARTY", available = IsInGroup(LE_PARTY_CATEGORY_HOME), reason = "not in a party" },
        { value = "INSTANCE_CHAT", available = IsInGroup(LE_PARTY_CATEGORY_INSTANCE), reason = "not in an instance group" },
        { value = "GUILD", available = IsInGuild(), reason = "not in a guild" },
        { value = "SAY", available = true },
        { value = "YELL", available = true },
    };
    for _, channel in ipairs(channels) do
        local text = CHANNEL_LABEL[channel.value];
        if (not channel.available) then
            text = text .. " |cff808080(" .. channel.reason .. ")|r";
        end
        rootDescription:CreateButton(text, function()
            Addon:SendRankedDungeonsToChat(channel.value);
        end):SetEnabled(channel.available);
    end

    rootDescription:CreateDivider();

    rootDescription:CreateButton("Whisper a character...", function()
        StaticPopup_Show("KSLBESTDUNGEON_WHISPER_TARGET");
    end);

    -- Battle.net Whisper - submenu with friends list (rebuilt each time the menu opens)
    local bnetWhisper = rootDescription:CreateButton("Battle.net friend");
    bnetWhisper:SetScrollMode(300);
    local numTotal = BNGetNumFriends();
    if (numTotal == 0) then
        bnetWhisper:CreateButton("|cff808080No Battle.net friends|r", function() end):SetEnabled(false);
    else
        for i = 1, numTotal do
            local accountInfo = C_BattleNet.GetFriendAccountInfo(i);
            if (accountInfo and accountInfo.bnetAccountID and accountInfo.gameAccountInfo) then
                local gameAccountInfo = accountInfo.gameAccountInfo;
                local characterName = "";
                if (gameAccountInfo.characterName and gameAccountInfo.characterName ~= "") then
                    characterName = " (" .. gameAccountInfo.characterName .. ")";
                end
                local isOnline = gameAccountInfo.isOnline;
                local text = accountInfo.battleTag .. characterName;
                if (not isOnline) then
                    text = "|cff808080" .. text .. " (Offline)|r";
                end
                bnetWhisper:CreateButton(text, function()
                    if (isOnline) then
                        Addon:SendRankedDungeonsToChat("BN_WHISPER", accountInfo.bnetAccountID);
                    end
                end):SetEnabled(isOnline);
            end
        end
    end
end

-- ============================================================
-- Toolbar
--
-- Everything that used to hide in an unlabelled settings dropdown, laid out as visible
-- controls with tooltips. Two rows above the list:
--   1. what is being ranked (character, specs)          [Defaults] [Share]
--   2. Sort [..]  [x] All specs  [x] Weight by tier  Min items [..]
-- The toolbar is a child of the rankings frame, so TabSystem shows and hides it with
-- our tab; never Show()/Hide() it by hand.
-- ============================================================
KSLBestDungeonRankingsFrameMixin = {};

local SORT_OPTIONS = {
    { value = "score", text = "Score" },
    { value = "count", text = "Favorites" },
    { value = "bis", text = "BiS items" },
    { value = "name", text = "Name" },
};

local function AddTooltip(frame, title, body)
    frame:HookScript("OnEnter", function(owner)
        GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM");
        GameTooltip:SetText(title, 1, 1, 1);
        GameTooltip:AddLine(body, nil, nil, nil, true);
        GameTooltip:Show();
    end);
    frame:HookScript("OnLeave", function()
        GameTooltip:Hide();
    end);
end

local function CreateLabel(parent, text)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    label:SetText(text);
    return label;
end

local function CreateCheckbox(parent, text)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate");
    check:SetSize(24, 24);
    if (not check.Text) then
        check.Text = check:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
        check.Text:SetPoint("LEFT", check, "RIGHT", 2, 0);
    end
    check.Text:SetFontObject("GameFontNormalSmall");
    check.Text:SetText(text);
    return check;
end

-- Built from Init() on the rankings frame (self).
function KSLBestDungeonRankingsFrameMixin:CreateToolbar()
    local frame = self;

    -- 60px down: the rankings frame covers the whole KSL window, and the top 60px
    -- are KSL's title bar and header dropdowns.
    local toolbar = CreateFrame("Frame", nil, self);
    toolbar:SetPoint("TOPLEFT", 10, -64);
    toolbar:SetPoint("TOPRIGHT", -12, -64);
    toolbar:SetHeight(52);
    self.Toolbar = toolbar;

    -- Row 1, right: Share, then Defaults to its left
    local share = CreateFrame("DropdownButton", nil, toolbar, "WowStyle1DropdownTemplate");
    share:SetPoint("TOPRIGHT", 0, 0);
    share:SetWidth(80);
    share:SetDefaultText("Share");
    share:SetupMenu(GenerateShareMenu);
    AddTooltip(share, "Share", "Post this ranking to chat: party, instance, guild, say, yell, or a whisper.");
    toolbar.Share = share;

    local defaults = CreateFrame("Button", nil, toolbar, "UIPanelButtonTemplate");
    defaults:SetSize(72, 22);
    defaults:SetPoint("RIGHT", share, "LEFT", -6, 0);
    defaults:SetText("Defaults");
    defaults:SetScript("OnClick", function()
        Addon:ResetSettings();
        frame:Refresh();
    end);
    AddTooltip(defaults, "Defaults", "Put sorting and filtering back to how they started.");
    toolbar.Defaults = defaults;

    -- Row 1, left: what the list is ranking. A frame rather than a bare FontString so
    -- it can carry a tooltip.
    local context = CreateFrame("Frame", nil, toolbar);
    context:SetPoint("LEFT", toolbar, "TOPLEFT", 0, -12);
    context:SetPoint("RIGHT", defaults, "LEFT", -8, 0);
    context:SetHeight(20);
    context:EnableMouse(true);
    context.Text = context:CreateFontString(nil, "OVERLAY", "GameFontHighlight");
    context.Text:SetAllPoints();
    context.Text:SetJustifyH("LEFT");
    context.Text:SetWordWrap(false);
    AddTooltip(context, "What is ranked",
        "Dungeons are ranked by the favorites of the character selected in KeystoneLoot "
        .. "(the character icon at the top).\n\n"
        .. "With \"All specs\" ticked, favorites from every spec count. Untick it to rank "
        .. "only for the spec picked in KeystoneLoot's class menu.");
    toolbar.Context = context;

    -- Row 2: Sort
    local sortLabel = CreateLabel(toolbar, "Sort:");
    sortLabel:SetPoint("LEFT", toolbar, "TOPLEFT", 0, -40);

    local sort = CreateFrame("DropdownButton", nil, toolbar, "WowStyle1DropdownTemplate");
    sort:SetPoint("LEFT", sortLabel, "RIGHT", 6, 0);
    sort:SetWidth(100);
    sort:SetupMenu(function(dropdown, rootDescription)
        for _, option in ipairs(SORT_OPTIONS) do
            rootDescription:CreateRadio(option.text,
                function() return Addon:GetSetting("sortBy") == option.value; end,
                function() Addon:SetSetting("sortBy", option.value); frame:Refresh(); end);
        end
    end);
    AddTooltip(sort, "Sort",
        "Score: favorites weighted by tier (see \"Weight by tier\").\n"
        .. "Favorites: how many favorited items drop there.\n"
        .. "BiS items: how many Best in Slot items drop there.\n"
        .. "Name: alphabetical.");
    toolbar.Sort = sort;

    -- Row 2: All specs
    local allSpecs = CreateCheckbox(toolbar, "All specs");
    allSpecs:SetPoint("LEFT", sort, "RIGHT", 10, 0);
    allSpecs:SetScript("OnClick", function(check)
        Addon:SetSetting("showAllSpecs", check:GetChecked() and true or false);
        frame:Refresh();
    end);
    AddTooltip(allSpecs, "All specs",
        "Count favorites from every spec of this character.\n\n"
        .. "Untick to rank only for the spec picked in KeystoneLoot's class menu.");
    toolbar.AllSpecs = allSpecs;

    -- Row 2: Weight by tier
    local weight = CreateCheckbox(toolbar, "Weight by tier");
    weight:SetPoint("LEFT", allSpecs.Text, "RIGHT", 8, 0);
    weight:SetScript("OnClick", function(check)
        Addon:SetSetting("weightByTier", check:GetChecked() and true or false);
        frame:Refresh();
    end);
    AddTooltip(weight, "Weight by tier",
        "Make better favorites count for more in the score:\n"
        .. "Best in Slot 100, Must have 50, Nice to have 10, Catalyst 5, Transmog 1.\n\n"
        .. "Untick to count every favorite as 1.");
    toolbar.Weight = weight;

    -- Row 2: Min items
    local minLabel = CreateLabel(toolbar, "Min items:");
    minLabel:SetPoint("LEFT", weight.Text, "RIGHT", 10, 0);

    local minFavs = CreateFrame("DropdownButton", nil, toolbar, "WowStyle1DropdownTemplate");
    minFavs:SetPoint("LEFT", minLabel, "RIGHT", 6, 0);
    minFavs:SetWidth(52);
    minFavs:SetupMenu(function(dropdown, rootDescription)
        for i = 1, 10 do
            rootDescription:CreateRadio(tostring(i),
                function() return Addon:GetSetting("minFavorites") == i; end,
                function() Addon:SetSetting("minFavorites", i); frame:Refresh(); end);
        end
    end);
    AddTooltip(minFavs, "Min items", "Hide dungeons with fewer favorites than this.");
    toolbar.MinFavorites = minFavs;
end

-- Bring the toolbar in line with the current settings and KSL selection. Called from
-- every Refresh(), which also covers Defaults and character/spec changes in KSL.
function KSLBestDungeonRankingsFrameMixin:UpdateToolbar()
    local toolbar = self.Toolbar;
    if (not toolbar) then return; end

    toolbar.AllSpecs:SetChecked(Addon:GetSetting("showAllSpecs"));
    toolbar.Weight:SetChecked(Addon:GetSetting("weightByTier"));
    -- Regenerating updates the dropdown text to the selected radio.
    toolbar.Sort:GenerateMenu();
    toolbar.MinFavorites:GenerateMenu();

    local characterKey, _, specId = Addon:GetRankingContext();
    if (not characterKey) then
        toolbar.Context.Text:SetText("|cff808080No character selected in KeystoneLoot|r");
        return;
    end

    -- KSL's key is "Realm-Name-ClassId" (Character:GetKey). Parsed from the right,
    -- because realm names can contain hyphens (Azjol-Nerub) and character names
    -- cannot. The class comes from the key rather than classId above: it is the
    -- class of the character selected in KSL, which need not be the one logged in.
    local _, name, keyClassId = characterKey:match("^(.*)%-(.-)%-(%d+)$");
    name = name or characterKey;
    local classFile = keyClassId and select(2, GetClassInfo(tonumber(keyClassId)));
    local classColor = classFile and C_ClassColor.GetClassColor(classFile);
    if (classColor) then
        name = classColor:WrapTextInColorCode(name);
    end

    local specText;
    if (Addon:GetSetting("showAllSpecs")) then
        specText = "all specs";
    else
        local _, specName = GetSpecializationInfoByID(specId or 0);
        specText = (specName or "current spec") .. " only";
    end

    toolbar.Context.Text:SetText("Ranking " .. name .. "  |cff808080·|r  " .. specText);
end

-- Get Battle.net account ID by BattleTag from friends list (kept for backward compatibility)
function Addon:GetBNetAccountIDByBattleTag(battleTag)
    local numTotal = BNGetNumFriends();
    for i = 1, numTotal do
        local accountInfo = C_BattleNet.GetFriendAccountInfo(i);
        if (accountInfo and accountInfo.battleTag == battleTag) then
            return accountInfo.bnetAccountID;
        end
    end
    return nil;
end

-- ============================================================
-- Rankings Frame Methods
-- ============================================================

function KSLBestDungeonRankingsFrameMixin:Init()
    -- Subscribe to KeystoneLoot's public API. KSL's internal DB observers are not
    -- reachable from here (see the item level note above), KeystoneLootAPI is.
    local API = _G.KeystoneLootAPI;
    if (API and API.RegisterCallback) then
        API:RegisterCallback(API.Event.FAVORITES_CHANGED, function() self:OnFavoritesChanged(); end, self);
    end

    -- The mixin is copied onto a plain CreateFrame() frame rather than applied from an
    -- XML template, so OnShow/OnHide are not wired up for us - do it by hand.
    self:SetScript("OnShow", self.OnShow);
    self:SetScript("OnHide", self.OnHide);

    self:CreateToolbar();

    self.lastFavoritesHash = nil;
    self:StartPolling();
    self:Refresh();
end

-- Polling fallback: catches everything the API does not fire for, such as the
-- character/spec filter changing in KSL.
function KSLBestDungeonRankingsFrameMixin:StartPolling()
    if (self.pollTimer) then return; end

    self.pollTimer = C_Timer.NewTicker(1.0, function()
        if (not self:IsShown()) then return; end

        if (self:GetFavoritesHash() ~= self.lastFavoritesHash) then
            self:Refresh();
        end
    end);
end

function KSLBestDungeonRankingsFrameMixin:OnFavoritesChanged()
    if (not self:IsShown()) then return; end
    self:Refresh();
end

-- Fallback when KSL's Dungeons tab has not laid itself out yet: its default width,
-- and roughly its height for a season of eight dungeons.
local DEFAULT_WIDTH, DEFAULT_HEIGHT = 500, 524;

-- Match the Dungeons tab's size, then size the window to us. KSL's SetTab does the
-- latter too (RefreshSize), but that can run before or after this OnShow depending
-- on the path, so do it here as well rather than rely on the order.
function KSLBestDungeonRankingsFrameMixin:SyncSizeToKSL()
    local KSLFrame = self:GetParent();
    local reference = KSLFrame and KSLFrame.DungeonsFrame;
    local width, height = 0, 0;
    if (reference) then
        width, height = reference:GetSize();
    end
    if (width < 100 or height < 200) then
        width, height = DEFAULT_WIDTH, DEFAULT_HEIGHT;
    end
    self:SetSize(width, height);

    if (self:IsShown() and KSLFrame) then
        KSLFrame:SetSize(width, height);
    end
end

function KSLBestDungeonRankingsFrameMixin:OnShow()
    self:SyncSizeToKSL();
    -- OnHide cancels the ticker, so it has to be recreated every time our tab is selected.
    self:StartPolling();
    self:Refresh();
end

function KSLBestDungeonRankingsFrameMixin:OnHide()
    if (self.pollTimer) then
        self.pollTimer:Cancel();
        self.pollTimer = nil;
    end
end

function KSLBestDungeonRankingsFrameMixin:GetFavoritesHash()
    if (not KeystoneLootDB or not KeystoneLootCharDB) then return nil; end

    -- The selected character and class/spec filter are part of the hash: changing spec
    -- leaves the favorites tables untouched, so without this the list would keep showing
    -- the previous spec's ranking until a /reload.
    local stateKey = Addon.GetFilterStateKey and Addon:GetFilterStateKey() or "";

    local characterKey = KeystoneLootCharDB.ui and KeystoneLootCharDB.ui.selectedCharacterKey;
    if (not characterKey) then return stateKey .. "|nochar"; end

    local favorites = KeystoneLootDB.favorites and KeystoneLootDB.favorites[characterKey];
    if (not favorites) then return stateKey .. "|empty"; end

    -- Create a simple hash from the favorites data
    local hashParts = {};
    for sourceId, sourceData in pairs(favorites) do
        if (type(sourceId) == "number" and sourceId > 0 and sourceId < 1000) then
            for specId, specData in pairs(sourceData) do
                for itemId, itemInfo in pairs(specData) do
                    table.insert(hashParts, string.format("%d:%d:%d:%d", sourceId, specId, itemId, itemInfo.tier or 0));
                end
            end
        end
    end
    table.sort(hashParts);
    return stateKey .. "|" .. table.concat(hashParts, ",");
end

-- Show a status message instead of the list.
-- Reuses a single FontString: FontStrings are regions, not children, so they are not
-- picked up by the container:GetChildren() cleanup in Refresh().
function KSLBestDungeonRankingsFrameMixin:ShowMessage(text, r, g, b)
    local container = self.ScrollFrame.Container;

    if (not self.MessageText) then
        self.MessageText = container:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge");
        self.MessageText:SetPoint("TOP", 0, -120);
    end

    self.MessageText:SetText(text);
    self.MessageText:SetTextColor(r, g, b);
    self.MessageText:Show();
end

function KSLBestDungeonRankingsFrameMixin:HideMessage()
    if (self.MessageText) then
        self.MessageText:Hide();
    end
end

function KSLBestDungeonRankingsFrameMixin:Refresh()
    local container = self.ScrollFrame.Container;

    -- Record the state this rebuild reflects, including the early-return paths below, so
    -- the poll ticker only fires again once something actually changed.
    self.lastFavoritesHash = self:GetFavoritesHash();

    -- Release all existing children
    local children = { container:GetChildren() };
    for _, child in ipairs(children) do
        child:Hide();
        child:SetParent(nil);
    end

    self:HideMessage();
    self:UpdateToolbar();

    -- Check KeystoneLoot
    if (not KeystoneLootDB or not KeystoneLootCharDB) then
        self:ShowMessage("|cffff0000KeystoneLoot not loaded|r\n\nEnable KeystoneLoot addon to use KSLBestDungeon", 1, 0.3, 0.3);
        return;
    end

    -- Check character
    local characterKey = KeystoneLootCharDB.ui and KeystoneLootCharDB.ui.selectedCharacterKey;
    local info = characterKey and { strsplit("-", characterKey) };
    if (not info or #info < 2) then
        self:ShowMessage("|cffffcc00No character selected|r\n\nOpen KeystoneLoot (/ksl) and select a character", 1, 0.8, 0);
        return;
    end

    -- Get ranked dungeons
    local ranked = Addon:GetRankedDungeons();

    if (#ranked == 0) then
        self:ShowMessage("|cff00ffffNo favorites found|r\n\nAdd favorites in KeystoneLoot for this character/spec", 0, 1, 1);
        return;
    end

    -- Create entry for each dungeon
    local yOffset = 0;
    for rank, dungeonData in ipairs(ranked) do
        local frame = CreateFrame("Frame", nil, container, "KSLBestDungeonEntryTemplate");
        frame:SetPoint("TOPLEFT", 0, -yOffset);
        frame:SetPoint("TOPRIGHT", 0, -yOffset);
        -- Passed explicitly: the icons wrap to the row width, and the row's anchors
        -- may not have resolved to a size yet.
        frame:Init(rank, dungeonData, container:GetWidth());
        frame:Show();
        yOffset = yOffset + frame:GetHeight() + 4;
    end

    container:SetHeight(math.max(yOffset, self.ScrollFrame:GetHeight()));
end

-- ============================================================
-- Item level correctness
--
-- KeystoneLoot's Upgrade module (which scales an item to the ilvl picked in KSL's
-- dropdown) lives on KSL's addon-private table. That table is NOT a global -- KSL
-- only exposes _G.KeystoneLootAPI -- so we cannot call Upgrade:BuildItemLink() and
-- any link we build ourselves shows the item at its base ilvl.
--
-- Instead we render item icons with KSL's own global button template,
-- KeystoneLootLootIconButtonTemplate. Its OnEnter/OnClick close over KSL's private
-- Upgrade module, so tooltips, quality colouring and chat links are built inside KSL
-- and always match the dropdown. Do not hand-roll item links here.
-- ============================================================
local KSL_ICON_BUTTON_TEMPLATE = "KeystoneLootLootIconButtonTemplate";

-- ============================================================
-- Entry Template Mixin
-- ============================================================
KSLBestDungeonEntryMixin = {};

-- Row layout. The text column has a fixed width and truncates with "..." (the full
-- dungeon name is in the row tooltip); the icons take the rest of the row and wrap
-- onto further lines, so every favorite is visible at any window width.
local TEXT_LEFT = 50;
local TEXT_WIDTH = 140;
local ICONS_LEFT = TEXT_LEFT + TEXT_WIDTH + 8;
local ICONS_RIGHT_MARGIN = 8;
local ROW_PADDING = 8;
local MIN_ROW_HEIGHT = 70;
local ICON_SIZE = 34; -- KeystoneLootLootIconButtonTemplate is 34x34
local ICON_SPACING = 2;
local ICON_LINE_SPACING = 4;

local function CreateColumnText(parent, font, y)
    local text = parent:CreateFontString(nil, "OVERLAY", font);
    text:SetPoint("TOPLEFT", TEXT_LEFT, y);
    text:SetWidth(TEXT_WIDTH);
    text:SetJustifyH("LEFT");
    text:SetWordWrap(false);
    return text;
end

function KSLBestDungeonEntryMixin:OnLoad()
    -- Top-aligned rather than centred, so it stays beside the name when the icons
    -- wrap and the row grows.
    self.RankText = self:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge");
    self.RankText:SetPoint("TOPLEFT", 10, -26);
    self.RankText:SetTextColor(1, 0.82, 0);

    self.NameText = CreateColumnText(self, "GameFontNormal", -ROW_PADDING);

    self.ScoreText = CreateColumnText(self, "GameFontNormalSmall", -26);
    self.ScoreText:SetTextColor(0.8, 0.8, 0.8);

    self.TierText = CreateColumnText(self, "GameFontNormalSmall", -42);
    self.TierText:SetTextColor(0.7, 0.7, 0.7);

    self.IconContainer = CreateFrame("Frame", nil, self);
    self.IconContainer:SetPoint("TOPLEFT", ICONS_LEFT, -ROW_PADDING);
    self.IconContainer:SetPoint("TOPRIGHT", -ICONS_RIGHT_MARGIN, -ROW_PADDING);
    self.IconContainer:SetHeight(ICON_SIZE);

    self.iconFrames = {};

    self:SetScript("OnEnter", function(self)
        if (self.dungeonData and #self.dungeonData.items > 0) then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
            GameTooltip:AddLine(self.dungeonData.dungeon.name, 1, 1, 1);
            GameTooltip:AddLine(" ");
            -- Names only. Hover an icon for the full tooltip at the selected item level.
            for _, item in ipairs(self.dungeonData.items) do
                local name = C_Item.GetItemInfo(item.itemId);
                local tierName = TIER_NAME[item.tier] or "Unknown";
                local tierColor = TIER_COLOR[item.tier] or "|cffffffff";
                GameTooltip:AddDoubleLine(name or ("Item " .. item.itemId), tierColor .. tierName .. "|r");
            end
            GameTooltip:Show();
        end
    end);

    self:SetScript("OnLeave", function(self)
        GameTooltip:Hide();
    end);
end

function KSLBestDungeonEntryMixin:Init(rank, dungeonData, rowWidth)
    self.dungeonData = dungeonData;

    self.RankText:SetText("#" .. rank);
    self.NameText:SetText(dungeonData.dungeon.name);

    local scoreText = string.format("Score: %.0f  |  Items: %d", dungeonData.stats.score, dungeonData.stats.totalItems);
    self.ScoreText:SetText(scoreText);

    local tierParts = {};
    if (dungeonData.stats.bisCount > 0) then
        table.insert(tierParts, string.format("%s%d BiS|r", TIER_COLOR[TIER_BIS], dungeonData.stats.bisCount));
    end
    if (dungeonData.stats.mustCount > 0) then
        table.insert(tierParts, string.format("%s%d Must|r", TIER_COLOR[TIER_MUST], dungeonData.stats.mustCount));
    end
    if (dungeonData.stats.niceCount > 0) then
        table.insert(tierParts, string.format("%s%d Nice|r", TIER_COLOR[TIER_NICE], dungeonData.stats.niceCount));
    end
    if (dungeonData.stats.catalystCount > 0) then
        table.insert(tierParts, string.format("%s%d Cata|r", TIER_COLOR[TIER_CATALYST], dungeonData.stats.catalystCount));
    end
    if (dungeonData.stats.transmogCount > 0) then
        table.insert(tierParts, string.format("%s%d TMog|r", TIER_COLOR[TIER_TRANSMOG], dungeonData.stats.transmogCount));
    end
    self.TierText:SetText(table.concat(tierParts, "   "));

    -- Item icons, wrapped onto as many lines as they need.
    local container = self.IconContainer;
    local iconsWidth = (rowWidth or 0) - ICONS_LEFT - ICONS_RIGHT_MARGIN;
    local perLine = math.max(1, math.floor((iconsWidth + ICON_SPACING) / (ICON_SIZE + ICON_SPACING)));

    for _, iconFrame in ipairs(self.iconFrames) do
        iconFrame:Hide();
        iconFrame:SetParent(nil);
    end
    self.iconFrames = {};

    for i, item in ipairs(dungeonData.items) do
        local column = (i - 1) % perLine;
        local line = math.floor((i - 1) / perLine);

        -- KSL's own button: it sets the icon and builds the tooltip/chat link through
        -- KSL's Upgrade module, so the item level always matches KSL's dropdown.
        local iconFrame = CreateFrame("Button", nil, container, KSL_ICON_BUTTON_TEMPLATE);
        iconFrame:SetPoint("TOPLEFT", column * (ICON_SIZE + ICON_SPACING), -line * (ICON_SIZE + ICON_LINE_SPACING));
        iconFrame:Init({ itemId = item.itemId });

        -- KSL's Init() desaturates/dims icons that don't match its stat highlighting
        -- filter. Everything in this list is already a favorite, so show them all fully.
        iconFrame.Content.Icon:SetDesaturated(false);
        iconFrame:SetAlpha(1);

        -- KSL marks the tier with a corner icon, but only for the spec currently
        -- filtered in KSL. This list can span specs (showAllSpecs), so keep our own
        -- tier-coloured border, which reflects the tier the item was favorited at.
        iconFrame.Content.IconBorder:Hide();
        iconFrame.TierBorder = iconFrame:CreateTexture(nil, "OVERLAY");
        iconFrame.TierBorder:SetAllPoints();
        local tier = item.tier;
        if (tier == TIER_BIS) then
            iconFrame.TierBorder:SetAtlas("loottoast-itemborder-legendary");
        elseif (tier == TIER_MUST) then
            iconFrame.TierBorder:SetAtlas("loottoast-itemborder-epic");
        elseif (tier == TIER_NICE) then
            iconFrame.TierBorder:SetAtlas("loottoast-itemborder-rare");
        else
            iconFrame.TierBorder:SetAtlas("loottoast-itemborder-uncommon");
        end

        iconFrame:Show();
        table.insert(self.iconFrames, iconFrame);
    end

    local lines = math.max(1, math.ceil(#dungeonData.items / perLine));
    local iconsHeight = lines * ICON_SIZE + (lines - 1) * ICON_LINE_SPACING;
    container:SetHeight(iconsHeight);
    self:SetHeight(math.max(MIN_ROW_HEIGHT, iconsHeight + ROW_PADDING * 2));
end
