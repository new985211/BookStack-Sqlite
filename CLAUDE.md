# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

BookStack (by TruthHun) is a **Go** web application for building and sharing documentation/wiki sites. It is a rewrite/fork of [MinDoc](https://github.com/lifei6671/mindoc) and powers [bookstack.cn](https://www.bookstack.cn). Despite the name, it is **not** the PHP/Laravel BookStack project — do not look for Laravel conventions.

It ships a companion WeChat mini-program API ("BookChat") alongside the server-rendered web UI.

## Tech stack

- **Go 1.13+** — module `github.com/TruthHun/BookStack`
- **Beego v1.12** — MVC framework: `beego/orm` for DB, `beego.Router` for routing, Go `html/template` for views (`views/`)
- **MySQL** — driver `go-sql-driver/mysql`; tables are auto-created. All tables use a configurable prefix, default `md_` (`conf/enumerate.go` → `GetDatabasePrefix()`)
- **Markdown** — blackfriday v2, with Chrome headless (or `puppeteer`, see `package.json`) for rendering in the editor
- **Search** — Elasticsearch (`models/elasticsearch.go`) + [gse](https://github.com/go-ego/gse) Chinese word segmentation (`dictionary/`)
- **File storage** — local or Aliyun OSS (`models/store/`)
- **Ebook export** — Calibre via `github.com/TruthHun/converter`

## Commands

There is no Makefile. `build.sh` is the canonical build entry point.

```bash
# Build (cross-compiles macOS/linux-amd64/windows/linux-arm64, then packages .deb for amd64 + arm64)
bash build.sh <version>       # e.g. bash build.sh 2.0 → output/<version>/

# Local dev build / run
go build -o BookStack
./BookStack                  # serves on port 8181 (see conf/app.conf)

# CLI subcommands (database must be reachable)
./BookStack install          # create tables + seed admin user (admin / admin888)
./BookStack migrate          # run versioned migrations (commands/migrate/)
./BookStack version          # print version
./BookStack service install|remove|restart   # install/remove/restart as a system service

# Tests — only one test file exists in the whole repo
go test ./utils/html2md/
go test ./...
```

The build injects `utils.Version`, `utils.GitHash`, `utils.BuildAt` via `-ldflags` (see `build.sh`), which are printed at startup by `utils.PrintInfo()`.

## Architecture

Standard Beego MVC layout; the request flow is `main.go` → `routers/` → `controllers/` → `models/` → `views/`.

- **`main.go`** — entry point. Wraps the app in `kardianos/service` so the same binary runs as a foreground process or a system service. Calls `commands.RegisterCommand()` and `utils.InitVirtualRoot()` (creates the `virtualroot/` upload dir).
- **`commands/`** — startup wiring, not HTTP logic:
  - `command.go` — registers DB (`RegisterDataBase`), all ORM models (`RegisterModel`), logger, and template funcs. Any new model **must** be added to `RegisterModel()` here to be picked up by the ORM.
  - `install.go` — `install` subcommand: `orm.RunSyncdb` auto-creates tables, seeds options + `admin` user.
  - `migrate/` — versioned schema migrations, registered in `RegisterMigration()`.
  - `daemon/` — `service install/remove/restart` handling.
- **`routers/`** — all routing lives here, never in controllers:
  - `web.go` — web UI routes (large, one `beego.Router(pattern, &Ctrl{}, "method:Action")` per line).
  - `bookchat.go` — BookChat API routes under the configurable `apiPrefix` (default `/bookchat/api/v1/...`).
  - `filter.go` — `beego.InsertFilter` auth gates: `/manager*`, `/setting*`, `/book*`, `/api*` require a login session.
- **`controllers/`** — web controllers (`BaseController` provides shared helpers); `controllers/api/` is the BookChat JSON API.
- **`models/`** — Beego ORM models (one struct per file, `orm:` tags, `TableName()` method). Also contains non-model logic (Elasticsearch client, ebook generation, version control).
- **`utils/`** — helpers: JWT/auth, HTML→Markdown (`html2md/`), pagination (`pager.go`), password, LDAP, WeChat, sitemap, etc.
- **`conf/`** — `app.conf.example` (main config), `oss.conf.example`, `oauth.conf.example`, and `enumerate.go` (constants + role/prefix helpers).
- **`oauth/`** — third-party login providers (GitHub/Gitee/QQ/WeChat).
- **`views/`** — Go templates, grouped by feature (`book/`, `document/`, `manager/`, `account/`, ...); `views/template.html` is the shared layout.
- **`scripts/`** — `bookstack.service` (systemd unit) and `offline-install.sh` (offline `.deb` installer for Kylin V10 / Ubuntu 20.04).

## Configuration

- Config file is `conf/app.conf`. It is **not** committed (`.gitignore` ignores `*.conf`); on first run `commands.ResolveCommand` copies `conf/app.conf.example` → `conf/app.conf` automatically.
- Key settings: `httpport` (default 8181), `runmode` (`dev`/`prod`), MySQL connection (`db_host`/`db_port`/`db_username`/`db_password`/`db_database`), `store_type` (`local`/`oss`), `apiPrefix`.
- Sessions are file-backed under `store/session`.
- `oss.conf` and `oauth.conf` are `include`d into `app.conf` — do not modify the `include` lines.

## Conventions and gotchas

- **Routing uses Beego's `method:Action` string** (e.g. `"get:Index"`, `"*:Login"`), not annotations. Add a route in `routers/`, then implement the matching method on the controller.
- **ORM model registration is manual** — forgetting to add a new struct to `commands.RegisterModel()` means the table won't be created by `install` or used by `orm`.
- **Database schema changes** should go through `commands/migrate/` (versioned) rather than relying on `RunSyncdb`, which only handles new installs.
- Default admin credentials are `admin` / `admin888`, set in `commands/install.go`.
- `package.json` exists only to pull in `puppeteer` for headless Chrome rendering; it is not a JS build system.
- Comments throughout the codebase (including config and CLI output) are in Chinese.
