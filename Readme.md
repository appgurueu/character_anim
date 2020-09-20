# Player Animations (`player_animations`)

Adds player animations. Resembles [`playeranim`](https://github.com/minetest-mods/playeranim) and [`headanim`](https://github.com/LoneWolfHT/headanim).

## About

Requires the [`binarystream`](https://luarocks.org/modules/Tarik02/binarystream)

## About

Depends on [`modlib`](https://github.com/appgurueu/modlib). Code written by Lars Mueller aka LMD or appguru(eu) and licensed under the MIT license.

## Links

* [GitHub](https://github.com/appgurueu/player_animations) - sources, issue tracking, contributing
* [Discord](https://discordapp.com/invite/ysP74by) - discussion, chatting
* [Minetest Forum](https://forum.minetest.net/viewtopic.php?f=9&t=24945) - (more organized) discussion <!-- TODO -->
* [ContentDB](https://content.minetest.net/packages/LMD/player_animations) - releases (cloning from GitHub is recommended)

# Features

* Animates head, right arm & body
* Advantages over `playeranim`:
  * Extracts exact animations and bone positions from glTF models
  * Only sets relevant bone positions for Minetest 5.3.0 and higher
* Advantages over `headanim`:
  * Provides compatibility for Minetest 5.1.1 (actually 5.2.0) and lower
  * Head angles are clamped, head can tilt sideways
  * Animates right arm & body as well

# Instructions

0. If you want to use a custom model, install [`binarystream`](https://luarocks.org/modules/Tarik02/binarystream) from LuaRocks:
   1. `sudo luarocks install binarystream` on many UNIX-systems
   2. Add `player_animations` to `secure.trusted_mods` (or disable mod security)
   3. <!-- TODO -->
1. Install `player_animations` like any other mod
2. **Players have to use `/ca minetest` if they are using Minetest 5.2 for animations to work**. This is due to engine limitations.