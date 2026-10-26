# On-device debugging with LiveContainer + StikDebug

> **Workflow subject to the policy:** read
> [`../references/BEST-PRACTICES.md`](../references/BEST-PRACTICES.md) before
> debugging. Use the cheapest layer that answers the question, and do not
> confuse structural validation with runtime.

Operational guide for debugging Swift/UIKit apps on-device using LiveContainer
and StikDebug. StikDebug is installed externally; the builder only instruments
the IPA. This workflow was validated during Chip8Emu development.

> Official LiveContainer: <https://github.com/LiveContainer/LiveContainer>.
> This repository is independent and is not affiliated with, endorsed by or
> sponsored by LiveContainer; that project's license and security guidance apply
> to its software.

## Principle: layered debugging

Use the cheapest layer that answers the question:

1. **Visual trace inside the app** — UI events, callbacks, files, state and
   rendering. It is the first choice for interface bugs.
2. **Attach/script in StikDebug** — confirms PID, attach, threads, registers and
   debugserver capabilities.
3. **Persistent low-level session** — keeps `debugserver` attached while the app
   runs and captures stops, registers and event breakpoints.

The StikDebug console mostly shows the script/debugserver. The app's `print` and
`NSLog` output does not appear automatically on that screen; use the visual
trace or an appropriate syslog.

## Generating a debug IPA

```sh
# Pure Swift/UIKit
sh /var/minis/skills/forge-on-glass/scripts/build-pure-ui.sh \
  MeuApp com.example.meuapp main.swift Views.swift --debug

# Third-party project inside LiveContainer
python3 /var/minis/skills/forge-on-glass/scripts/port-third-party.py \
  /tmp/projeto MeuApp com.example.meuapp \
  --debug --stikdebug-bundle-id com.kdt.livecontainer.A4658DGR7V

# Validate before installing
python3 /var/minis/skills/forge-on-glass/scripts/check-debug-ipa.py \
  /var/minis/workspace/MeuApp.ipa
```

For the normal signed debug path, run:

```sh
# The normal signed debug path preserves get-task-allow. For an explicitly
# unsigned guest, pass --unsigned and validate only after the host re-signs it.
sh scripts/build-pure-ui.sh App com.example.app main.swift --debug
python3 scripts/check-debug-ipa.py /var/minis/workspace/App.ipa
```

Use `--unsigned` only when the next component explicitly re-signs the guest.

- `assets/DebugSupport.swift`;
- `get-task-allow=true`;
- `LSApplicationQueriesSchemes=stikdebug`;
- blue overlay `DBG • tap: StikDebug`;
- PID, bundle ID and `LC_HOME_PATH` detection;
- `stikdebug://enable-jit` URL with the current PID.

Post-processing re-signing must preserve `get-task-allow`. The installer may
remove it; always validate the IPA that will be installed.

## Bundle IDs in LiveContainer

There are two different IDs:

```text
guest app:     com.minis.chip8emu.debug
host:          com.kdt.livecontainer.A4658DGR7V
```

`--stikdebug-bundle-id` is the ID used to return to the host. Without it,
StikDebug may try to return to the guest bundle and show `Failed to return`.
That does not prove an attach failure. Use the real ID shown by
LiveContainer/StikDebug.

## Layer 1 — visual trace

To investigate a UI flow, add a temporary panel that logs synchronously:

```text
main: viewDidLoad
main: Load ROM handler
main: creating picker
picker: viewDidLoad
picker: ROMs=25
picker: tapped INVADERS
picker: delegate didPick called
main: load INVADERS, url=true
main: ROM loaded INVADERS
main: displayLink added
frame: ok lit=119
```

This quickly answers whether the tap arrived, whether the delegate was called,
whether the file exists, whether the state changed and whether the image was
created. For rendering, also log `UIImage=nil`, `lit=0` and `lit=N` along the
framebuffer → Bitmap → CGImage → UIImage → UIImageView path.

Do not put the first diagnostic in `DispatchQueue.main.async`: if the screen is
never created, the block may never run.

## Layer 2 — attach in StikDebug

The DBG overlay opens StikDebug with the PID. A diagnostic attach script should
log:

```text
vAttach
qSupported
qfThreadInfo
qC
register_packet_length
register_packet_prefix
D
```

`D = OK` means the session was ended by the script. A finite script is useful
to confirm attach, but it is not continuous monitoring.

`universal.js` **is not a generic log capturer**. It implements the `BRK`-based
JIT protocol; in an ordinary app it may sit at `Handling signal 1` or wait
indefinitely. Use it only when the process actually uses the compatible JIT
protocol.

## Layer 3 — persistent session

For continuous monitoring, the script must keep the session open:

```text
vAttach
qSupported/qfThreadInfo/qC
c
log stop/signal
read qC, thread and g
c
...
```

The `debug stop/continue #1` line means the script is blocked at `c`, waiting
for a stop. By itself, it means neither a crash nor a detach. If the app
generates no signals, the counter does not advance.

To get useful events, add instrumentation breakpoints at the points of interest:
tap, callback, selection, loading and rendering. They should only be armed after
the user taps DBG; before that the app must run normally without `SIGTRAP`. The
expected behavior is:

```text
#1 attach/initial state
#2 Load ROM tap
#3 ROM selected
#4 ROM loaded
```

When ending the session in StikDebug, wait for the `D`/detach and return to
LiveContainer manually if the automatic return fails.

## On-device procedure

1. Install the IPA by the method that preserves `get-task-allow`.
2. Open the app through LiveContainer.
3. Confirm that the DBG overlay appears inside the app.
4. For a UI bug, reproduce it first with the visual trace.
5. For attach, tap DBG and keep LocalDevVPN/tunnel active.
6. In StikDebug, confirm the request and watch the PID.
7. For a persistent session, keep the script screen open.
8. Generate the instrumented events and check the counter advancing.
9. The PID changes on every launch; never reuse an old PID.

## Quick interpretation

| Message | Meaning |
|---|---|
| `attach_response = T...` | debugserver responded to the attach |
| `qSupported = ...` | available capabilities |
| `qfThreadInfo = m...` | threads returned |
| `qC = QC...` | current thread |
| `register_packet_length = 0` | `g` returned no packet in that state; not standalone proof of failure |
| `detach = OK` | session ended |
| `Handling signal 1` | universal.js waiting for/processing a signal |
| `debug stop/continue #1` | persistent session waiting for a stop |
| `frame: ok lit=N` | framebuffer has pixels and the image was created |
| `UIImage=nil` | conversion to UIImage failed |

## Limitations

- Attach and the console exist only on the device; iSH does not simulate the
  session.
- `get-task-allow` may be removed by the installer.
- StikJIT/helper is not bundled: StikDebug is external, and guest app extensions
  are not supported by LiveContainer.
- Automatic return to the host is a convenience; if it fails, open LiveContainer
  manually. That does not necessarily invalidate the attach.
- Do not save pairing files, tokens or credentials in sources/reports.

References: [StikDebug](https://github.com/StikDebug/StikDebug),
[LiveContainer](https://github.com/LiveContainer/LiveContainer) and
`assets/DebugSupport.swift`.
