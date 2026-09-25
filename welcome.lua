--[[ KSLBestDungeon -- welcome / release notes

    The first-run greeting and the "what changed" note after an update. One
    frame serves both: they differ only in their heading and body, and both are
    "say this once, then never again".

    Ported from Avatar Continued's welcome.lua, itself ported from SquizzFrames
    and Squizzumables. The details those learned the hard way come with it: the
    scrolling body, the three-way first-run/update/nothing decision, the
    seen-version key on the SavedVariable root, and the shared queue that stops
    notes from several addons drawing on top of each other.

    WHY THE NOTES ARE DUPLICATED HERE rather than read from changelog.txt: an
    addon cannot read its own text files at runtime, so anything shown in game
    has to live in Lua. This is a HIGHLIGHT list, not a changelog. Keep it to
    what a player would notice.
]]

local AddonName = ...;
local Addon = _G.KSLBestDungeon;
if (not Addon) then return; end

-- Highlights per version, newest first, keyed by the .toc Version string.
-- ADD AN ENTRY AS PART OF RELEASING -- see CLAUDE.md's Releasing section.
-- A version with no entry still shows the update note, just without bullets.
local RELEASE_NOTES = {
    ["1.4"] = {
        "The Best Dungeons tab has a toolbar: Sort, All specs, Weight by tier and Min items are right there instead of hidden in an unlabelled menu. Hover any of them for what it does.",
        "The top line says whose favorites are being ranked, and for which specs.",
        "Share posts the ranking to chat. Channels you cannot use right now are greyed out with the reason, and you can whisper any character by name.",
        "An item favorited on several specs now counts once, at its best tier, instead of once per spec.",
        "Catalyst favorites now count as much as Best in Slot, since they become set pieces. Dungeons with them will move up the list.",
        "A score key along the bottom shows what each tier is worth, and hovering a dungeon shows how its score was worked out.",
        "Tiers use KeystoneLoot's own tier icons everywhere, and each item's icon shows the tier you favorited it at.",
        "The ranking follows KeystoneLoot's Slot menu: pick Trinket there to find the best dungeon for your trinkets.",
        "An empty list now says why -- a filter hiding everything, or no favorites yet -- with a button to fix it.",
        "Defaults puts the options back without reloading your interface.",
        "Fixed alts being ranked for your logged-in character's spec -- a Paladin alt showed as Beast Mastery -- when \"All specs\" is off.",
        "Fixed the KeystoneLoot window getting shorter every time you opened the Best Dungeons tab, and the list's scrollbar sitting outside the window.",
        "Every favorite is shown now: icons wrap onto a second line instead of running off the edge.",
        "/rl now reloads your interface, the same as /reload. It is only claimed if no other addon already provides it.",
        "Supports patch 12.1.5 as well as 12.1.0.",
        "This window is new: a short note about what changed, once per update. Type /kslbd notes to see it again.",
    },
};

local function CurrentVersion()
    return (C_AddOns and C_AddOns.GetAddOnMetadata
        and C_AddOns.GetAddOnMetadata(AddonName, "Version")) or "?";
end

-- KSLBestDungeon's purple, as used in the chat prefix.
local ACCENT = { 0.62, 0.36, 0.72 };

local frame;

-- Whether KSLBestDungeonDB existed before this session, which is what tells a
-- new install from an upgrade out of a version that predates this file.
--
-- It has to be taken at our ADDON_LOADED. Before that the SavedVariables have
-- not been loaded, so it always reads nil. After it, GetSettings() creates the
-- table the first time the rankings refresh at PLAYER_LOGIN -- before the
-- delayed CheckVersion below runs -- so it always reads as existing.
local hadSavedVariables = false;

-- ONE UPDATE NOTE AT A TIME, across all of the Squizz addons.
--
-- SquizzFrames, Squizzumables, SquizzTalents, Avatar Continued and this addon
-- each carry a copy of this window, and the copies are identical: same size,
-- same spot, same DIALOG strata, same frame level. Frames that tie on strata
-- and level have no defined draw order, so when two of them updated at the same
-- login their notes drew through each other and flickered as the order flipped.
--
-- The queue lives in _G and is created by whichever addon loads first. Notes
-- that come due at login wait behind one already on screen and appear when it
-- closes; notes opened by hand (/kslbd notes) show straight away, on top.
--
-- KEEP THIS BLOCK IDENTICAL IN ALL OF THE ADDONS. They share the table, so its
-- shape is an interface between them.
local NotesQueue = _G.SquizzNotesQueue or { pending = {} };
_G.SquizzNotesQueue = NotesQueue;

local function PresentNotes(f, queued)
    local active = NotesQueue.active;
    if queued and active and active ~= f and active:IsShown() then
        for _, waiting in ipairs(NotesQueue.pending) do
            if waiting == f then return; end
        end
        table.insert(NotesQueue.pending, f);
        return;
    end
    NotesQueue.active = f;
    f:Show();
    f:Raise();
end

local function OnNotesHidden(f)
    if NotesQueue.active ~= f then return; end
    NotesQueue.active = nil;
    local nextFrame = table.remove(NotesQueue.pending, 1);
    if nextFrame then
        PresentNotes(nextFrame, false);
    end
end

-- Narrower than the frame by the scroll bar's gutter, so a long note is not
-- drawn underneath it.
local BODY_WIDTH = 404;

local function BuildFrame()
    if (frame) then return frame; end

    frame = CreateFrame("Frame", "KSLBestDungeonWelcome", UIParent, "BackdropTemplate");
    frame:SetSize(460, 320);
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 60);
    frame:SetFrameStrata("DIALOG");
    frame:SetMovable(true);
    frame:EnableMouse(true);
    frame:RegisterForDrag("LeftButton");
    frame:SetScript("OnDragStart", frame.StartMoving);
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing);
    frame:SetBackdrop({
        bgFile   = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeSize = 1,
    });
    frame:SetBackdropColor(0.05, 0.05, 0.06, 0.97);
    frame:SetBackdropBorderColor(0.3, 0.3, 0.35, 1);
    frame:Hide();

    -- Escape closes it, like any other dialog.
    table.insert(UISpecialFrames, "KSLBestDungeonWelcome");

    -- Clicking a notes window brings it in front of any other one, and closing
    -- it lets the next queued note through (see NotesQueue).
    frame:SetToplevel(true);
    frame:HookScript("OnHide", OnNotesHidden);

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge");
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -16);
    title:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3], 1);
    frame.title = title;

    -- THE NOTES SCROLL, and that is not optional: a fixed-height FontString
    -- silently relies on every release having few enough bullets to fit, and
    -- the text simply draws outside its parent when one does not. Bounded
    -- between the title and the buttons rather than sized to the text, so the
    -- frame stays put and the buttons stay reachable.
    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate");
    scroll:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12);
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -26, 52);
    frame.scroll = scroll;

    local content = CreateFrame("Frame", nil, scroll);
    content:SetSize(BODY_WIDTH, 1);
    scroll:SetScrollChild(content);
    frame.content = content;

    local body = content:CreateFontString(nil, "OVERLAY", "GameFontNormal");
    body:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0);
    body:SetWidth(BODY_WIDTH);
    body:SetJustifyH("LEFT");
    body:SetJustifyV("TOP");
    body:SetSpacing(4);
    body:SetTextColor(0.85, 0.85, 0.85, 1);
    frame.body = body;

    local openButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate");
    openButton:SetSize(150, 24);
    openButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 18, 16);
    openButton:SetText("Open Best Dungeons");
    openButton:SetScript("OnClick", function()
        frame:Hide();
        Addon:OpenBestDungeonsTab();
    end);

    local closeButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate");
    closeButton:SetSize(90, 24);
    closeButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -18, 16);
    closeButton:SetText("Close");
    closeButton:SetScript("OnClick", function() frame:Hide(); end);

    return frame;
end

-- queued: true for the automatic login note, which waits its turn behind
-- another addon's note; false/nil when opened by hand.
local function Show(titleText, bodyText, queued)
    local f = BuildFrame();
    f.title:SetText(titleText);
    f.body:SetText(bodyText);

    -- Size the scroll child to the text, AFTER SetText so the height is the
    -- wrapped height rather than the pre-layout one. Without this the child
    -- keeps its placeholder height of 1, the scroll frame decides there is
    -- nothing to scroll, and the overflow bug comes straight back.
    f.content:SetHeight(math.max(1, f.body:GetStringHeight() + 4));

    -- Back to the top: the frame is reused, so re-opening it through
    -- /kslbd notes would otherwise restore wherever the last read was left.
    f.scroll:SetVerticalScroll(0);

    PresentNotes(f, queued);
end

-- The greeting for someone who has never run the addon.
local function ShowFirstRun(queued)
    Show("Welcome to KSLBestDungeon",
        "KSLBestDungeon ranks this season's Mythic+ dungeons by how many of your "
     .. "KeystoneLoot favorites drop there, so you know which key is worth running.\n\n"
     .. "It adds a Best Dungeons tab to the KeystoneLoot window. Type /kslbd to go "
     .. "straight to it.\n\n"
     .. "- Favorite items in KeystoneLoot as usual. Setting them to Best in Slot or "
     .. "Must have makes them count for more.\n"
     .. "- The toolbar along the top of the tab sorts and filters the list. Hover any "
     .. "option to see what it does.\n"
     .. "- Share posts the ranking to your group, guild or a friend.", queued);
end

-- The note after updating.
local function ShowUpdated(version, queued)
    local notes = RELEASE_NOTES[version];
    local body = "KSLBestDungeon has been updated to " .. version .. ".\n\n";
    if (notes) then
        for _, line in ipairs(notes) do
            body = body .. "- " .. line .. "\n";
        end
        body = body .. "\nThe full changelog is in changelog.txt in the addon folder.";
    else
        body = body .. "See changelog.txt in the addon folder for what changed.";
    end
    Show("KSLBestDungeon updated", body, queued);
end

-- Decide which, if either, to show. lastSeenVersion sits on the
-- KSLBestDungeonDB root, beside settings, so Defaults (which only replaces
-- .settings) never re-greets anyone. /kslbd reset wipes the whole table, so it
-- does re-greet -- which fits a full reset.
local function CheckVersion()
    if (not KSLBestDungeonDB) then
        KSLBestDungeonDB = {};
    end
    local version = CurrentVersion();
    local seen = KSLBestDungeonDB.lastSeenVersion;

    if (seen == nil) then
        -- No record at all: either a genuinely new install, or an upgrade from
        -- a version that predates this file. hadSavedVariables tells them apart.
        if (hadSavedVariables) then
            ShowUpdated(version, true);
        else
            ShowFirstRun(true);
        end
    elseif (seen ~= version) then
        ShowUpdated(version, true);
    end

    KSLBestDungeonDB.lastSeenVersion = version;
end

local loader = CreateFrame("Frame");
loader:RegisterEvent("ADDON_LOADED");
loader:RegisterEvent("PLAYER_LOGIN");
loader:SetScript("OnEvent", function(self, event, arg1)
    if (event == "ADDON_LOADED") then
        if (arg1 == AddonName) then
            hadSavedVariables = (KSLBestDungeonDB ~= nil);
            self:UnregisterEvent("ADDON_LOADED");
        end
    else
        -- On a delay so it does not land in the middle of the loading screen.
        C_Timer.After(4, CheckVersion);
    end
end);

-- /kslbd notes re-opens the current release notes on demand.
function Addon:ShowReleaseNotes()
    ShowUpdated(CurrentVersion());
end

function Addon:ShowWelcome()
    ShowFirstRun();
end
