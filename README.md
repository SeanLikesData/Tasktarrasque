# Tasktarrasque

Tasktarrasque is a local macOS menu bar todo list application built with SwiftUI.

It is styled after Notebloat: a compact glassy menu bar popover with local JSON saving and no Dock icon.

## Features

- macOS menu bar application with no Dock icon.
- One week visible at a time.
- Monday-first day tabs.
- Each day has its own task list.
- Each day tab shows a completion score such as `3/5`.
- Old weeks remain saved and can be selected from the week picker.
- A weekly template editor pre-creates recurring tasks for new weeks.
- Template edits affect new weeks only.
- A `This Week` panel holds unscheduled tasks.
- `This Week` tasks can be moved into any day.
- `This Week` tasks can be pushed into next week.
- Each week has a `Big Three` section for three important weekly tasks.
- Local JSON storage only.

## Appearance and behavior

Tasktarrasque is a dark glass HUD popover. It always uses a dark appearance because the frosted background and control colors are tuned for a dark surface.

By default the popover closes when you click another application. Turn on **Keep popover pinned above other windows** in Settings to make it stay open and float above other windows. Either way, clicking the menu bar icon toggles the popover open and closed.

## Build and run

From this repository root:

```sh
./build.sh
open build/Tasktarrasque.app
```

The build script compiles the Swift sources directly with `swiftc` and assembles a proper `.app` bundle. The bundle sets `LSUIElement=true`, so the application runs as a menu bar accessory.

To quit the application, press **Command-Q**.

## Tests

The model logic has a standalone test suite, also compiled directly with `swiftc`:

```sh
./run-tests.sh
```

It exits non-zero if any test fails.

## Distribution note

`build.sh` ad-hoc signs the bundle and the application is not sandboxed. That is fine for personal local use. Distributing it to other machines would require a real signing identity and, ideally, the App Sandbox.

## Data storage

Tasktarrasque stores data locally:

```text
~/Library/Application Support/Tasktarrasque/weeks.json
```

There is no server, account system, analytics system, or cloud synchronization.
