# Overview

Conpositor has a decent amount of moving parts. This document is here to help contributors get a general idea of where to find things.

## General structure

Conpositor at its highest level is split into 3 main systems:

- The compositor
- The lua backend
- Lua IPC Calling

There are many parts of Conpositor where I use a "dirty" pattern, this allows me to for example only mark a client frame as dirty when its active status changes. This will then cause the layout to be marked dirty, fixing layout automatically. It may be slightly worse on space and speed, however it removes a lot of inconsistency ive ran into with previous implementations of the project.

## The lua backend

Conpositor has a wrapper around zlua to ensure consistent bindings, LuaContext.zig implements all of the binding.

### Lua Objects

Objects in lua are created using [type_gen.lua](conpositor/lua/type_gen.lua) the _GenerateType function is called by Conpositor to convert tables to a proper function table. Instances are manually hashed, this allows for client references in lua to be created and destroyed without the zig instance being destroyed.

### Ownership model

Things owned by Conpositor should be freed by Conpositor, things owned by lua should implement a free in __gc. Types should not have instances owned by one or the other.