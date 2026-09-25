# KSLBestDungeon

A World of Warcraft (retail) companion for [KeystoneLoot](https://www.curseforge.com/wow/addons/keystoneloot)
that ranks Mythic+ dungeons by how many of your KeystoneLoot favorites drop there,
so you know which key to push or which dungeon to ask for.

It has no window of its own: it adds a **Best Dungeons** tab to KeystoneLoot.

## Features

- **Ranked dungeon list** built from your KeystoneLoot favorites, weighted by
  tier (Best in Slot, Must have, Nice to have, Catalyst, Transmog).
- **Follows KeystoneLoot** — the selected character, spec and item level are
  picked up live, and item tooltips show the item level chosen there.
- **Current season automatically** — dungeon names come from the game, not a
  hardcoded list.
- **Share to chat** — post the ranking to party, instance, guild, say, yell or a
  Battle.net friend.

## Requirements

[KeystoneLoot](https://www.curseforge.com/wow/addons/keystoneloot) must be
installed and enabled.

## Installation

1. Download or clone this repository.
2. Place the folder in your WoW AddOns directory so the path looks like:

   ```
   World of Warcraft/_retail_/Interface/AddOns/KSLBestDungeon/KSLBestDungeon.toc
   ```

   The folder **must** be named `KSLBestDungeon` to match the `.toc` file.
3. Restart WoW, or type `/reload` if the client is already running.

## Usage

Type `/kslbd` to open KeystoneLoot on the Best Dungeons tab, or open
KeystoneLoot as usual (`/ksl`) and click the tab.

## License

MIT — see [LICENSE](LICENSE).
