
# INTRODUCTION
<img src ="./SavedGamesDCS/Mods/Services/Webhooker/theme/WebhookerLogo.png" alt="Webhooker logo" width = 100 align = "right"/>
Webhooker enables DCS multiplayer servers to make web request triggered from the mission scripting environment. The original use case is posting messages to Discord. 
<br/>
<br/>
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

## Configuring templates
Configuring message templates on the server and adding strings to substitute can be acheived through the Webhooker special options menu in DCS. Further documentation can be found [here](/Docs/ServerConfigWalkthrough.md).

## Mission Scripting

### Include method stubs (recommended)
The server side code injects the necessary scripts to queue requests into the mission at runtime, however to ensure your mission runs without errors in other servers or in single player, it is recommended to include `.\MissionScripts\Webhooker_mission.lua` in your missions that use Webhooker with the following mission trigger:

Trigger type | Trigger action | Action parameter
-------------|----------------|------------------
MISSION START| DO SCRIPT FILE | 'Webhooker_mission.lua'

### Commands

For full details on Webhooker scripting commands see this [page](/Docs/MissionScriptingCommands.md).

To send one of your configured requests from mission scripts, call `Webhooker.send` passing the template name and the positional arguments for the template.

The positional arguments can be pre-configured strings, playe names or pre-defined functions, produced respectively by calls to `Webhooker.string`, `Webhooker.player`, and `Webhooker.func`.

For example:

```
Webhooker.send("MyVictoryMessage",Webhooker.string("Red"),Webhooker.player("User123"))
```
# DEPENDENCIES

Webhooker depends upon:
 * [luasec](https://github.com/brunoos/luasec), and its dependency [openssl](https://github.com/openssl/openssl).
 * [LuaWorker](https://github.com/HappyGnome/LuaWorker)

 The required compiled binaries and lua modules are included (subject to applicable licenses).

 Sketch notes for developers (re)building these dependencies can be found [here](Docs/Dependencies.md).
