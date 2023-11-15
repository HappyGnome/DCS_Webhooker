
# INTRODUCTION

Webhooker enables DCS multiplayer servers to make web request triggered from the mission scripting environment. The original use case is posting messages to Discord.

Due to limitations of communicating between DCS scripting environments, all API requests are generated from template messages and formatted with substituted strings including player names, or predefined strings. While this limits the flexibility of messages, it has the following benefits:

* Templates can only be configured at the server level and webhook urls are kept on the server.
* Missions can be run single player or on other servers without accidentally triggering your webhooks.
* No changes are required to the mission scripting environment security settings.

# INSTALLATION

Copy the contents of the `SavedGamesDCS` folder into your DCS saved games folder on the server. If done correctly then, for example:

File | Contained in (system dependent)
----|-----
`Webhooker.lua` |`C:\Users\<username>\SavedGames\DCS\Scripts\Hooks`
`init.lua` | `C:\Users\<username>\SavedGames\DCS\Mods\Services\Webhooker`

# Basic Usage

## Configure templates
Configuring message templates on the server and adding strings to substitute can be acheived through the Webhooker special options menu in DCS.

## Mission Scripting

### Include method stubs (recommended)
The server side code injects the necessary scripts to queue requests into the mission at runtime, however to ensure your mission runs without errors in other servers or in single player, it is recommended to include `.\MissionScripts\Webhooker_mission.lua` in your missions that use Webhooker with the following mission trigger:

Trigger type | Trigger action | Action parameter
-------------|----------------|------------------
MISSION START| DO SCRIPT FILE | 'Webhooker_mission.lua'

### Send configured webhook from script
#### Commands
There are only a few key commands to know in mission scripting:
* `Webhooker.send` - format and send a template message
* `Webhooker.func` - create a positional template parameter in `Webhooker.send` (or `Webhooker.func`) by calling a function defined in the messageTemplates folder.
* `Webhooker.player` - convert a player name to a positional template parameter in `Webhooker.send` (or `Webhooker.func`)
* `Webhooker.string` - specify one of the configured strings at positional template parameter in `Webhooker.send` (or `Webhooker.func`)

*Section incomplete - examples needed*

#### Formatting functions
By default `Webhooker.func` includes options:
Name      | Description             | Example                 | Converts to
-----     |-------------            |----------               |-------------
int       | Format integer          | `Webhooker.func("int",7)` | "7"
list      | Concatenate parameters  | `Webhooker.func("list",Webhooker.string(", "),Webhooker.func("int",1), Webhooker.func("int",2))` | "1, 2"
datetime  | Format date time        | `Webhooker.func("datetime")` | "31/01/2023"

# DEPENDENCIES

Webhooker depends upon:
 * [luasec](https://github.com/brunoos/luasec), and its dependency [openssl](https://github.com/openssl/openssl).
 * [LuaWorker](https://github.com/HappyGnome/LuaWorker)

 The required compiled binaries and lua modules are included (subject to applicable licenses).

 Sketch notes for developers (re)building these dependencies can be found [here](Docs/Dependencies.md).
