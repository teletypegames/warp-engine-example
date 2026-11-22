# WarpEngine example stack

A whole studio on one machine, with [WarpEngine](https://git.teletypegames.org/engines/warp_engine) at its heart: the catalog app, a Gitea
forge and Woodpecker CI, wired together. `bin/setup` brings the catalog up, and the engine
starts and wires the git server and the CI itself (its *local components*, through the Docker
socket) — no install wizard, no OAuth app to click together, no passwords to choose — so the
first game you push builds and lands in the catalog.

| Service | Role | Where |
| --- | --- | --- |
| `app` | Rails host with the `warp_engine` gem, ActiveAdmin + Devise for the admin | `http://localhost:8080` |
| `mysql` | Catalog database | internal |
| `warp-example-gitea` | Git forge, started by the engine | `http://localhost:3000` |
| `warp-example-woodpecker` + agent | CI wired to gitea, pipelines served by the engine, started by the engine | `http://localhost:8000` |

What you need: Docker with Compose, git and curl. The app container gets the Docker socket, so
the engine can start the two on the stack network (`warp-example`).

## Quickstart

```sh
git clone https://git.teletypegames.org/engines/warp-engine-example.git
cd warp-engine-example
bin/setup
```

The first run takes a few minutes: the app container bundles, runs
`rails g warp_engine:install` and `rails db:prepare` (which seeds the empty
database), installs the web runtimes, and the script then

runs `bin/rails "warp_engine:local:enable[woodpecker]"` in the app: the engine

1. starts Gitea, creates its administrator (`warp-admin`, a generated password), the `games`
   organisation, its own API token and a push user;
2. registers Woodpecker on Gitea (an OAuth app), starts it, signs in once — no browser —, takes
   an API token and stores the `gitea_token` secret the pipelines tag with;
3. from then on creates repositories there and serves the pipelines to that Woodpecker.

The script prints the Gitea sign-in and, when git has a credential helper, stores it there for
`localhost:3000`. Run it again any time; what is set up stays (a newer engine replaces the
containers whose settings changed). `bin/setup --no-ci` brings up only the catalog and the admin
(the same as `cp .env.example .env && docker compose up -d --build`). Woodpecker's web UI signs
in through Gitea with the same administrator.

- `http://localhost:8080/` — the catalog page: a plain list and a page per game,
  `host_app/app/views/catalog`, there to be replaced by your own site
- `http://localhost:8080/admin` — the admin, `admin@example.org` / `warpengine`
  (`docker compose exec -e ADMIN_EMAIL=you@example.org -e ADMIN_PASSWORD=secret123 app bin/rails db:seed`
  adds one of your own)
- `http://localhost:8080/api/software` — the catalog
- `http://localhost:8080/file/starhop/1.0.0/html/index.html` — a web build
- `http://localhost:8080/api/builds` — the platform build matrix
- `http://localhost:8080/api/docs` — apipie API docs
- `http://localhost:8090/` — the shelves over plain HTTP (`C64`, `PLUS4`, `APPS`),
  for WE64 on a C64; `ftp://localhost:2121/` — the same over FTP, for WEDOS

The ports live in `.env` (`APP_PORT`, `GITEA_PORT`, `WOODPECKER_PORT`, `SHELF_HTTP_PORT`,
`SHELF_FTP_PORT`). The git server and the CI are the engine's containers, not compose services:

```sh
docker compose exec app bin/rails warp_engine:local:status
docker compose exec app bin/rails "warp_engine:local:credentials[gitea]"
docker compose exec -e PURGE=1 app bin/rails "warp_engine:local:remove[gitea]"   # with their data
docker compose down -v                                                            # then the rest
```

## Your first game

With the [WarpEngine Toolbox](https://marketplace.visualstudio.com/items?itemName=TeletypeGames.warpengine-toolbox)
in VS Code: *WarpEngine: Set Host…* → `http://localhost:8080`, *WarpEngine: Sign
In* (approve the code on the admin's *Tool Sign In* page), then *WarpEngine: New
Game*. The engine creates the repository in the `games` organisation, enables it
in Woodpecker with its own CI token, and the toolbox pushes the template. The
pipeline the engine serves builds it, tags `v1.0.0`, and the tag pipeline
publishes the release.

Without the toolbox the same works through the Admin API
(`POST /api/admin/v1/softwares/scaffold`) and a plain `git push` of a repository
holding the one-line marker:

```yaml
# .woodpecker.yaml
platform: phaser
```

The builder images, the project templates and the web shells come from
`git.teletypegames.org` — public, no login needed; `WARP_REGISTRY` and
`WARP_TOOLING_HOST` point the example at your own copies. The images are
built for amd64; on an arm64 machine Docker runs them emulated, slower.

The example pins the images to a dated tag (`WARP_IMAGES`), so a new builder
on our side never changes a pipeline that already works for you; move to a
newer set when you are ready:

| Engine | Images (`git.teletypegames.org/build/…`) | Tag |
| --- | --- | --- |
| 4.3.0– | the same set, and `electron-builder` for the `electron` platform | `2026.11.18` |
| 4.1.6–4.2.x | the same set, with the `tic80pro` that has `tic80-export` and its own native players | `2026.11.17.3` |
| 4.1.5 | the same set, with the `dos-builder` that fills in a missing `dos` block from the name | `2026.11.17.2` |
| 4.1.2–4.1.4 | `godot-builder` (Godot 4.7.1), `phaser-builder`, `love-builder`, `bevy-builder`, `ebitengine-builder`, `c64-builder`, `plus4-builder`, `dos-builder`, `tic80pro`, `commodore-player` | `2026.11.17` |
| 4.1.2– | `ci-tools` (version, tag, upload, publish steps) | `@sha256:8bb7d771…` |

The project templates and demos (`platform_tooling`, `ref: master`) and the web
shells follow their `master` branch: they only matter when a new game starts.

## Stores for your devices

One command points every store at this catalog, for the devices on your local network:

```sh
bin/stores                                  # your machine's address, found by itself
bin/stores 192.168.1.20 --name "My Studio"  # or name it (--id, --logo too)
```

It writes your address into `.env` (`SHELF_HTTP_URL`, `SHELF_FTP_URL`, `SHELF_FTP_ADDRESS`),
restarts the catalog and the shelves, copies the newest Batocera and RetroArch store engines,
WE64 (C64) and WEDOS (DOS) from teletypegames.org into your catalog (released, so they update
themselves from there), names the two store engines after your store, and builds WE64 and
WEDOS with their settings:

| Device | What to do |
| --- | --- |
| Batocera | `curl -fsSL http://ADDRESS:8080/api/stores/batocera/install.sh \| sh` on the box |
| RetroArch | `curl -fsSL http://ADDRESS:8080/api/stores/retroarch/install.sh \| sh` |
| C64 | `http://ADDRESS:8080/stores/c64/<id>.d64`: WE64 and its `WE64.CFG` on one disk image, for the Ultimate's SD card or VICE |
| DOS | `http://ADDRESS:8080/stores/dos/we-dos.zip`: WEDOS with its `WEDOS.CFG`; unpack and run `WEDOS.EXE` |
| Desktop | the WarpEngine Desktop takes `http://ADDRESS:8080` on its first run |

It prints these lines with your address at the end. Run it again whenever your address changes.
The generated files live in `host_app/public/stores/` (not in git). The disk image is written by
`host_app/lib/studio/d64.rb`, no VICE needed.

## The engine version

The host takes the `warp_engine` gem from the TTG gem registry
(`https://git.teletypegames.org/api/packages/engines/rubygems`); `WARP_ENGINE_VERSION`
in `.env` sets the requirement (default `~> 5.1`). To run the stack against an
engine checkout instead — while working on the engine itself:

```sh
WARP_ENGINE_SOURCE=../warp_engine docker compose -f docker-compose.yml -f compose.engine.yml up -d --build
```

## More

The engine README covers the rest: stores for your catalog
(the store engines), publishing a release by hand, shelves, Sync, the
Admin API. Inside this stack run the generators and rake tasks with
`docker compose exec app bin/rails …`.

## License

MIT, see `LICENSE`.
