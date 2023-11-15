# Dependency compilation

This page is incomplete and provided for for future reference (but hopefully not of concern for users).

These are sketch notes on how some of the dependencies of Webhooker were compiled.

## Building lua.lib
Compiled Lua plugin modules need to be dynamically linked against lua when they are loaded by DCS. To generate the header 

* Build [lua](https://www.lua.org/versions.html) v5.1.5 
* Output .dll/.lib pair for dynamic linking 
* Target Windows 10 SDK x64

## Building ssl.dll
The included ssl.dll binary was created as follows

* Build OpenSSL (v3.1.2) into a static library (targeting Windows 10 SDK x64)
* Build luasec (v1.3.2), linking against openssl libraries statically, and lua.lib (targeting Windows 10 SDK x64)
* Link against Lua 5.1.5 compiled above

## Building LuaWorker.dll
The included LuaWorker.dll binary was created as follows

* Build [LuaWorker](https://github.com/HappyGnome/LuaWorker) v1.0 
* Visual Studio 2022
* Build tools ('Platform Toolset') v143
* C++ 17 standard
* Target x64 Windows
* Link against Lua 5.1.5 compiled above