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

-- KeystoneLoot's own tier icons (its Favorites.TIER_TEXTURE, which is on KSL's private
-- table, so the paths are repeated here). Tiers are shown ONLY with these, everywhere:
-- the corner of each item icon, the row summary, the score key and the tooltips. One
-- visual language, and the same one players already know from KeystoneLoot.
local TIER_TEXTURE = {
    [TIER_NICE] = "Interface\\AddOns\\KeystoneLoot\\assets\\tier_nice",
    [TIER_MUST] = "Interface\\AddOns\\KeystoneLoot\\assets\\tier_must",
    [TIER_BIS] = "Interface\\AddOns\\KeystoneLoot\\assets\\tier_bis",
    [TIER_TRANSMOG] = "Interface\\AddOns\\KeystoneLoot\\assets\\tier_transmog",
    [TIER_CATALYST] = "Interface\\AddOns\\KeystoneLoot\\assets\\tier_catalyst",
};

-- Display order: by score weight, highest first. Differs from KeystoneLoot's own
-- TIER_ORDER (which puts Catalyst after Nice) because Catalyst weighs the same as
-- BiS here, and the score key should read from most to least valuable.
local TIER_ORDER = { TIER_BIS, TIER_CATALYST, TIER_MUST, TIER_NICE, TIER_TRANSMOG };

local TIER_SHORT_NAME = {
    [TIER_NICE] = "Nice",
    [TIER_MUST] = "Must",
    [TIER_BIS] = "BiS",
    [TIER_TRANSMOG] = "Transmog",
    [TIER_CATALYST] = "Catalyst",
};

-- Inline tier icon for FontStrings and tooltips.
local function TierIcon(tier, size)
    local texture = TIER_TEXTURE[tier];
    if (not texture) then return ""; end
    size = size or 14;
    return string.format("|T%s:%d:%d|t", texture, size, size);
end

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
        .. "only for the spec picked in KeystoneLoot's class menu.\n\n"
        .. "It also follows KeystoneLoot's Slot menu: pick Trinket there to rank dungeons "
        .. "by your trinket favorites only. Favorites or All slots ranks every slot.");
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
        .. "Best in Slot 100, Catalyst 100, Must have 50, Nice to have 10, Transmog 1.\n\n"
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

-- ============================================================
-- Score key
--
-- A strip along the bottom of the list saying what the score is made of, in the same
-- tier icons the rows and item icons use. Built from Init(); the scroll frame stops
-- 26px above the inset's bottom to leave room for it.
-- ============================================================
function KSLBestDungeonRankingsFrameMixin:CreateScoreKey()
    local key = CreateFrame("Frame", nil, self);
    key:SetPoint("BOTTOMLEFT", self.Inset, "BOTTOMLEFT", 6, 4);
    key:SetPoint("BOTTOMRIGHT", self.Inset, "BOTTOMRIGHT", -6, 4);
    key:SetHeight(20);
    key:EnableMouse(true);

    local divider = key:CreateTexture(nil, "ARTWORK");
    divider:SetColorTexture(1, 1, 1, 0.1);
    divider:SetPoint("TOPLEFT", 0, 1);
    divider:SetPoint("TOPRIGHT", 0, 1);
    divider:SetHeight(1);

    key.Text = key:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
    key.Text:SetPoint("LEFT", 2, -1);
    key.Text:SetPoint("RIGHT", -2, -1);
    key.Text:SetJustifyH("LEFT");
    key.Text:SetWordWrap(false);

    AddTooltip(key, "Score",
        "Each dungeon's score adds up its favorites, weighted by the tier you gave them "
        .. "in KeystoneLoot, so one Best in Slot item outranks several Nice to have ones.\n\n"
        .. "Untick \"Weight by tier\" to count every favorite as 1.\n\n"
        .. "Hover a dungeon to see how its score was worked out.");
    self.ScoreKey = key;
end

function KSLBestDungeonRankingsFrameMixin:UpdateScoreKey()
    local key = self.ScoreKey;
    if (not key) then return; end

    local weighted = Addon:GetSetting("weightByTier");
    local parts = {};
    for _, tier in ipairs(TIER_ORDER) do
        if (weighted) then
            table.insert(parts, string.format("%s %s %d", TierIcon(tier), TIER_SHORT_NAME[tier],
                Addon:GetTierWeight(tier, true)));
        else
            table.insert(parts, TierIcon(tier) .. " " .. TIER_SHORT_NAME[tier]);
        end
    end

    local prefix = weighted and "|cffffd100Score:|r  " or "|cffffd100Score:|r every favorite = 1  ";
    key.Text:SetText(prefix .. table.concat(parts, "   "));
end

-- Bring the toolbar in line with the current settings and KSL selection. Called from
-- every Refresh(), which also covers Defaults and character/spec changes in KSL.
function KSLBestDungeonRankingsFrameMixin:UpdateToolbar()
    self:UpdateScoreKey();

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

    local text = "Ranking " .. name .. "  |cff808080·|r  " .. specText;
    local slotLabel = Addon:GetSlotFilterLabel();
    if (slotLabel) then
        text = text .. "  |cff808080·|r  " .. slotLabel;
    end
    toolbar.Context.Text:SetText(text);
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
    self:CreateScoreKey();

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

-- Show a status message instead of the list: a title, an explanation and, when there
-- is one obvious fix, a button that does it.
--
-- Parented to the rankings frame, NOT the scroll container: Refresh() detaches every
-- child of the container, and would take the message with it. Centred on the inset so
-- it sits in the middle of the empty list at any window size.
function KSLBestDungeonRankingsFrameMixin:ShowMessage(title, body, buttonText, onClick)
    local message = self.Message;
    if (not message) then
        message = CreateFrame("Frame", nil, self);
        message:SetPoint("CENTER", self.Inset, "CENTER", 0, 10);
        message:SetSize(360, 160);

        message.Title = message:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge");
        message.Title:SetPoint("TOP", 0, 0);
        message.Title:SetWidth(360);

        message.Body = message:CreateFontString(nil, "OVERLAY", "GameFontHighlight");
        message.Body:SetPoint("TOP", message.Title, "BOTTOM", 0, -10);
        message.Body:SetWidth(340);
        message.Body:SetSpacing(3);

        message.Button = CreateFrame("Button", nil, message, "UIPanelButtonTemplate");
        message.Button:SetHeight(24);
        message.Button:SetPoint("TOP", message.Body, "BOTTOM", 0, -14);
        message.Button:SetScript("OnClick", function(button)
            if (button.onClick) then button.onClick(); end
        end);

        self.Message = message;
    end

    message.Title:SetText(title);
    message.Body:SetText(body or "");
    if (buttonText) then
        message.Button:SetText(buttonText);
        message.Button:SetWidth(math.max(120, message.Button:GetTextWidth() + 30));
        message.Button.onClick = onClick;
        message.Button:Show();
    else
        message.Button.onClick = nil;
        message.Button:Hide();
    end
    message:Show();
end

function KSLBestDungeonRankingsFrameMixin:HideMessage()
    if (self.Message) then
        self.Message:Hide();
    end
end

-- Explain an empty list, most specific cause first, each with the fix as a button.
function KSLBestDungeonRankingsFrameMixin:ShowEmptyReason(candidates)
    local frame = self;

    -- Favorites exist but Min items hides every dungeon.
    if (candidates > 0) then
        local minFavorites = Addon:GetSetting("minFavorites");
        self:ShowMessage("Every dungeon is hidden by Min items",
            string.format("%d %s favorites, but none has at least %d. Lower Min items in the "
                .. "toolbar, or show them all.",
                candidates, (candidates == 1) and "dungeon has" or "dungeons have", minFavorites),
            "Show all dungeons",
            function()
                Addon:SetSetting("minFavorites", 1);
                frame:Refresh();
            end);
        return;
    end

    -- KSL's Slot filter excludes every favorite. No button: KSL's filter state is only
    -- read here, never written (see GetSlotFilter in the core file).
    if (Addon:IsSlotFilterActive() and Addon:HasAnyDungeonFavorites()) then
        local slotLabel = Addon:GetSlotFilterLabel();
        self:ShowMessage(slotLabel and string.format("No favorites in %s", slotLabel)
                or "No favorites match the Slot filter",
            "This list follows the Slot menu at the top of KeystoneLoot. Pick Favorites or "
            .. "All slots there to rank every slot.");
        return;
    end

    -- This spec has none, but other specs do.
    if (not Addon:GetSetting("showAllSpecs") and Addon:HasAnyDungeonFavorites()) then
        local _, _, specId = Addon:GetRankingContext();
        local _, specName = GetSpecializationInfoByID(specId or 0);
        self:ShowMessage(string.format("No favorites for %s", specName or "this spec"),
            "This character has dungeon favorites on its other specs. \"All specs\" is off, "
            .. "so only this spec's favorites are ranked.",
            "Show all specs",
            function()
                Addon:SetSetting("showAllSpecs", true);
                frame:Refresh();
            end);
        return;
    end

    -- Nothing favorited yet.
    local KSLFrame = self:GetParent();
    local dungeonsTabId = KSLFrame and KSLFrame.dungeonsTabId;
    self:ShowMessage("No dungeon favorites yet",
        "In KeystoneLoot's Dungeons tab, click an item and pick a tier: Best in Slot, "
        .. "Catalyst, Must have, Nice to have or Transmog. This tab then ranks the dungeons "
        .. "by what they drop for you.",
        dungeonsTabId and "Go to Dungeons" or nil,
        function()
            KSLFrame:SetTab(dungeonsTabId);
        end);
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
    container:SetHeight(1);

    self:HideMessage();
    self:UpdateToolbar();

    -- Check KeystoneLoot
    if (not KeystoneLootDB or not KeystoneLootCharDB) then
        self:ShowMessage("KeystoneLoot isn't loaded",
            "Best Dungeons ranks your KeystoneLoot favorites. Enable KeystoneLoot in the "
            .. "AddOns list and reload.");
        return;
    end

    -- Check character
    local characterKey = KeystoneLootCharDB.ui and KeystoneLootCharDB.ui.selectedCharacterKey;
    local info = characterKey and { strsplit("-", characterKey) };
    if (not info or #info < 2) then
        self:ShowMessage("No character selected",
            "Pick a character with the character icon at the top right of KeystoneLoot.");
        return;
    end

    -- Get ranked dungeons
    local ranked, candidates = Addon:GetRankedDungeons();

    if (#ranked == 0) then
        self:ShowEmptyReason(candidates or 0);
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

-- Stands in for KSL's UpdateFavoriteIcon on our icon buttons (see Entry Init).
local function ShowFavoritedTier(button)
    local icon = button.Content and button.Content.FavoriteIcon;
    if (not icon) then return; end

    local texture = TIER_TEXTURE[button.favoritedTier];
    if (texture) then
        icon:SetTexture(texture);
        icon:SetDesaturated(false);
        icon:Show();
    else
        icon:Hide();
    end
end

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

    self:SetScript("OnEnter", function(row)
        local data = row.dungeonData;
        if (not data or #data.items == 0) then return; end

        GameTooltip:SetOwner(row, "ANCHOR_RIGHT");
        GameTooltip:AddLine(data.dungeon.name, 1, 1, 1);

        -- The score's working, so the number on the row means something.
        local weighted = Addon:GetSetting("weightByTier");
        local counts = data.tiers or {};
        GameTooltip:AddLine(" ");
        GameTooltip:AddLine(weighted and "Score, weighted by tier:" or "Score, every favorite counting 1:", 1, 0.82, 0);
        for _, tier in ipairs(TIER_ORDER) do
            local count = counts[tier] or 0;
            if (count > 0) then
                local weight = Addon:GetTierWeight(tier, weighted);
                GameTooltip:AddDoubleLine(
                    string.format("%s %d %s", TierIcon(tier), count, TIER_NAME[tier]),
                    string.format("x %d = %d", weight, count * weight),
                    0.9, 0.9, 0.9, 0.9, 0.9, 0.9);
            end
        end
        -- Tiers KeystoneLoot added after this was written still count, at 1 each.
        local unknown = 0;
        for tier, count in pairs(counts) do
            if (not TIER_TEXTURE[tier]) then unknown = unknown + count; end
        end
        if (unknown > 0) then
            GameTooltip:AddDoubleLine(string.format("%d other", unknown), string.format("x 1 = %d", unknown),
                0.9, 0.9, 0.9, 0.9, 0.9, 0.9);
        end
        GameTooltip:AddDoubleLine("Score", string.format("%.0f", data.stats.score), 1, 1, 1, 1, 1, 1);

        -- Names only. Hover an icon for the full tooltip at the selected item level.
        GameTooltip:AddLine(" ");
        for _, item in ipairs(data.items) do
            local name = C_Item.GetItemInfo(item.itemId);
            GameTooltip:AddDoubleLine(TierIcon(item.tier) .. " " .. (name or ("Item " .. item.itemId)),
                TIER_NAME[item.tier] or "Other", 1, 1, 1, 0.7, 0.7, 0.7);
        end
        GameTooltip:Show();
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

    -- "[icon] 5 BiS  [icon] 3 Must", best tier first, in KeystoneLoot's tier icons.
    local tierParts = {};
    local counts = dungeonData.tiers or {};
    for _, tier in ipairs(TIER_ORDER) do
        local count = counts[tier] or 0;
        if (count > 0) then
            table.insert(tierParts, string.format("%s%d %s", TierIcon(tier, 12), count, TIER_SHORT_NAME[tier]));
        end
    end
    self.TierText:SetText(table.concat(tierParts, "  "));

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

        -- KSL's corner tier icon shows the tier for the spec currently filtered in
        -- KSL, and KSL redraws it on every hover (OnEnter/OnLeave call
        -- UpdateFavoriteIcon). This list can span specs (All specs), so replace the
        -- method on this button instance to always show the tier the item was
        -- favorited at -- the tier its score counted.
        --
        -- This used to hide KSL's quality border and add a tier-coloured one from the
        -- loottoast-itemborder-* atlases instead. Those atlases do not draw on 12.x, so
        -- icons showed no border at all; KSL's own quality border stays now.
        iconFrame.favoritedTier = item.tier;
        iconFrame.UpdateFavoriteIcon = ShowFavoritedTier;
        iconFrame:UpdateFavoriteIcon();

        iconFrame:Show();
        table.insert(self.iconFrames, iconFrame);
    end

    local lines = math.max(1, math.ceil(#dungeonData.items / perLine));
    local iconsHeight = lines * ICON_SIZE + (lines - 1) * ICON_LINE_SPACING;
    container:SetHeight(iconsHeight);
    self:SetHeight(math.max(MIN_ROW_HEIGHT, iconsHeight + ROW_PADDING * 2));
end
