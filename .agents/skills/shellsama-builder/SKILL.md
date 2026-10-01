---
name: shellsama-builder
description: Builds, tests, and verifies shellsama — the Samarinda Desktop Shell providing docks, panels, taskbars, application launchers, and system indicators built on Floria Toolkit.
version: 1.0.0
triggers:
  - build shellsama
  - compile shellsama
  - test shellsama
  - test shellsama xephyr
  - run shellsama
  - samarinda shell
---

# `shellsama` — Samarinda Desktop Shell Build & Development Skill

Orchestrates the build pipeline, unit tests, and nested Xephyr execution for **shellsama**, the official Desktop Shell for the Samarinda Desktop Environment powered by **Floria Toolkit** and **Florialib**.

> [!NOTE]
> Window management and compositing are handled by the companion project **`../wmsama`**. `shellsama` focuses purely on user-facing desktop shell surfaces: panels, docks, taskbars, app launchers, system tray, and status popovers.

---

## 1. Prerequisites & Dependencies

- **Free Pascal Compiler (`fpc` >= 3.2.0)**
- **PasBuild (`pasbuild` >= 1.9.0)**: Reads `project.xml`.
- **Florialib (`florialib:0.0.1-SNAPSHOT`)**: Core vector graphics (AggPas), image processing, and XCB bindings.
- **Floria Toolkit (`floria-toolkit`)**: Dotted-namespace UI widgets (`Ft.Widget.*`), theming (`Ft.Theme`), vector icons (`Ft.Icons`), and dialogs.
- **Xephyr (`/usr/bin/Xephyr`)**: Nested X server for visual development alongside `wmsama`.

---

## 2. Build & Test Commands

| Action | Command | Description |
| :--- | :--- | :--- |
| **Compile Executable** | `./build.sh` or `pasbuild compile` | Compiles `shellsama` binary to `target/shellsama` |
| **Run Unit Tests** | `./build.sh test` or `pasbuild test` | Compiles and executes test suite `TestRunner` |
| **Clean Artifacts** | `./build.sh clean` or `pasbuild clean` | Cleans `target/` build directory |

---

## 3. Nested Testing with Xephyr (Alongside `wmsama`)

Test the complete Samarinda Desktop Environment by launching both `wmsama` (WM) and `shellsama` (Desktop Shell) inside Xephyr:

```bash
# 1. Start Xephyr on virtual display :2
Xephyr -br -ac -noreset -screen 1280x720x24 -resizeable :2 &
XEPHYR_PID=$!

# 2. Start wmsama Window Manager / Compositor
DISPLAY=:2 ../wmsama/target/wmsama &
WM_PID=$!

# 3. Start shellsama Desktop Shell (Panel, Dock, Taskbar)
DISPLAY=:2 ./target/shellsama &
SHELL_PID=$!

# 4. Launch test client applications
DISPLAY=:2 ../floria-toolkit/target/example_c_button_icons &
DISPLAY=:2 ../floria-toolkit/target/example_c_file_dialog &

# 5. Clean teardown when finished
kill -9 $SHELL_PID $WM_PID $XEPHYR_PID 2>/dev/null || true
wait $XEPHYR_PID 2>/dev/null || true
```

---

## 4. `shellsama` Architecture & Components

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    shellsama (Samarinda Desktop Shell)                  │
├─────────────────────────────────────────────────────────────────────────┤
│  Top / Bottom Dock Panel (ShellSama.Panel)                              │
│  - EWMH Dock window (_NET_WM_WINDOW_TYPE_DOCK)                          │
│  - Reserves screen geometry via _NET_WM_STRUT_PARTIAL                   │
│  - Frosted glass backdrop blur with Amamizu Liquid Glass theme          │
├─────────────────────────────────────────────────────────────────────────┤
│  Application Launcher / Start Menu (ShellSama.Launcher)                 │
│  - Popover modal dialog with search bar (TFtEntry)                      │
│  - Application grid with vector SVG icons (TFtButton, Ft.Icons)         │
│  - Parses /usr/share/applications/*.desktop entries                     │
├─────────────────────────────────────────────────────────────────────────┤
│  Taskbar / Window Switcher (ShellSama.Taskbar)                          │
│  - Synchronizes with _NET_CLIENT_LIST from wmsama                       │
│  - Displays active windows with icons, titles, and minimize/focus click │
├─────────────────────────────────────────────────────────────────────────┤
│  Status & Control Center (ShellSama.Status)                             │
│  - Clock & calendar indicator                                           │
│  - Network, volume, and power indicators                                │
│  - Quick toggle switches for Dark Mode / Liquid Glass (TFtSwitch)       │
└─────────────────────────────────────────────────────────────────────────┘
```
