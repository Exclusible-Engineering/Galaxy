# Galaxy

A small lightweight framework that lets you grab any module from anywhere with `shared("Name")`.

## Features

- Grab any module by name with `shared("Name")`.
- Server and client code is detected and started for you.
- Modules load only when first used, then get cached.

## Installation

Add this to your `wally.toml` and run `wally install`:

```toml
[dependencies]
Galaxy = "artisticvampyre/galaxy@1.1.0"
```

## Getting Started

### 1. Start Galaxy

From a server `Script` and a client `LocalScript`, tell Galaxy where to look for your code:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Galaxy = require(ReplicatedStorage.Packages.Galaxy)

Galaxy.Launch({
    -- Where your reusable modules live
    Modules = { ReplicatedStorage.Packages, ReplicatedStorage.Shared },
    -- Where your systems live
    Systems = { script:WaitForChild("systems") },
})
```

### 2. Make a system

A system is just a module whose name ends in `Service` (server) or `Controller` (client). Galaxy runs the right ones automatically and calls `onInit` then `onStart`.

```lua
-- MainService.luau
local log = shared("log")

local MainService = {}

function MainService:onInit()
    log.info("MainService initialized")
end

function MainService:onStart()
    log.info("MainService started")
end

return MainService
```

### 3. Use other modules

Call `shared("Name")` to get any module or system by its name:

```lua
local MainService = shared("MainService")
local log = shared("log")
```

### Tip: autocomplete for `shared(...)`

Because `shared(...)` takes a string, the editor doesn't know the type by itself. Add a `--@module` annotation above the line so the language server treats it as that module and gives you autocomplete:

```lua
local MainService = shared("MainService") --@module MainService
```

## How It Works

### Modules and systems

- **Modules** are any `ModuleScript`. They load the first time you ask for them with `shared(...)`.
- **Systems** are modules named `...Service` or `...Controller`. Galaxy starts them for you when the game launches.

### Server vs. client

Galaxy looks at where the code is running and picks the right systems:

- On the server it runs anything named `Service`.
- On the client it runs anything named `Controller`.

So you can keep both in the same folder and each side only runs its own.

### When things start

When you call `Galaxy.Launch`:

1. `onInit` is called on every system, one at a time. Use it for setup.
2. `onStart` is called on every system after all setup is done. Use it for your main logic.

### Loading extra folders into a system

If a system needs helper modules from nearby folders, list them in `DirectoriesToLoad` and Galaxy attaches them for you:

```lua
local MyService = { DirectoriesToLoad = { "components", "data" } }

function MyService:onInit()
    -- self.SomeComponent is now available
end

return MyService
```

## When Something Goes Wrong

- If a module fails to load, Galaxy warns you and keeps going, so one mistake doesn't break everything.
- If a module takes too long to load (over 3 seconds), Galaxy tells you which one.
- If two modules depend on each other in a loop, Galaxy warns you and names them.

## Reference

- `Galaxy.Launch({ Modules = {...}, Systems = {...} })` starts the framework.
- `shared("Name")` returns a module or system by name. Works anywhere after `Launch`.
- `Galaxy._VERSION` is the version string.
- On a system, `onInit(self)` runs first for setup, `onStart(self)` runs after for main logic.

## Project Layout

```
src/
  init.luau            the framework
  CycleMetatable.luau  cyclic dependency helper
  wally.toml           package info
test/
  server/  client/  shared/   example game using Galaxy
```

## Development

Install tools with [Aftman](https://github.com/LPGhatguy/aftman), then run the test place:

```sh
aftman install
rojo serve test.project.json
```

## License

MIT. See [LICENSE](LICENSE).
