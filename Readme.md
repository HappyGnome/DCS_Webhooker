
# INTRODUCTION

The aim of DCS_DiscordLink is to allow DCS (servers) to post messages to Discord from the mission environment.
This project is in the prototyping stage. Final capabilities TBC.

# INSTALLATION

## Server

### Saved games
Copy the contents of the `SavedGamesDCS` folder into your DCS saved games folder. If done correctly then E.g. `.\SavedGamesDCS\Scripts\Hooks\DCS_DiscordLink.lua` will be copied to `C:\Users\<username>\SavedGames\DCS\Scripts\Hooks\DCS_DiscordLink.lua` (system dependent).

### Environment variables
Discord webhook URLs may need to be added to the environment on the server. Details TBC.

## Mission Scripts
`.\MissionScripts` contains scripts that can be included in mission files to add logging from the mission environment.

# DEPENDENCIES

DCS_DiscordLink depends upon [luasec](https://github.com/brunoos/luasec), and its dependency [openssl](https://github.com/openssl/openssl).

## Building ssl.dll
The included ssl.dll binary was created as follows
* Build [lua](https://www.lua.org/versions.html) (v5.1.5) as a .dll/.lib pair for dynamic linking (targeting Windows x64)
  - N.B. the .lib needs to be compatible with lua.dll included with DCS
* Build OpenSSL (v3.1.2) into a static library (targeting Windows x64)
* Build luasec (v1.3.2), linking against openssl libraries statically, and lua.lib (targeting Windows x64)