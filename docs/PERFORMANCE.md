# Performance and high-CPU investigation

Omanome treats performance evidence as an ownership question first. A process
is an Omanome process only when it carries `OMANOME_OWNER=io.omanome.shell` or
matches the registry's exact PID, start-time, and executable identity. A
process named `lua`, `quickshell`, or anything else is not attributed by name.

## Safe commands

```sh
omanome processes --json
omanome benchmark --json
omanome profiler [--json] [--interval 1]
omanome watchdog --watch --json
omanome performance check --json
```

`processes` is an on-demand owner-only snapshot. `benchmark` is a deterministic
config projection/JSON round-trip benchmark; its result is not a frame-rate,
idle-CPU, or whole-system certification. `profiler` watches the same owner-only
snapshot at a bounded interval. `watchdog` is notify-only: it observes only Omanome-owned
processes, requires sustained CPU/memory pressure, and reports without sending
signals or terminating anything. `performance check` is a source-level safety
gate for loops, polling, Lua execution, process ownership, and config writes.

The runtime performance budget also bounds the universal Device Graph's live
battery-source inventory at 16 real UPower sources. Missing power backends stay
unknown or unavailable; a battery row is never synthesized to fill the budget.

The JSON reports keep these quantities separate:

- `ownerCpuPercent`: measured CPU for processes proven to be Omanome-owned;
- `systemCpuPercent`: whole-host sample, not attributed to Omanome;
- `helperCpuPercent`: the subset of proven Omanome-owned helper processes;
- `quickshellCpuPercent` and `companionCpuPercent`: `null` unless the host
  exposes an explicit Omanome-owned identity for those components.

## Runtime policy

The service uses one owner-marked process lane per command family, a registry
with PID/start-time identity, bounded timeout and restart backoff, and crash-loop
suppression. Expensive refreshes are event-driven or slow fallback timers;
clipboard/config writes are debounced; search input is debounced; live preview
delegates are destroyed when the panel Loader becomes inactive. OSK repeat is
stopped on release. Optional effects are budgeted by the performance mode and
fail closed when a capability is not present.

Modes are `automatic`, `quality`, `balanced`, `performance`, and
`battery-saver`. Automatic mode uses only available power, thermal, fullscreen,
and backend GPU signals. Schema-2 configurations that still contain
`performance.qualityPreset` migrate that value to `performance.mode`.

## Investigating a foreign high-CPU process

If an unowned process is hot, record its executable, command line, parent PID,
parent command line, start time, and owning package/service. Compare that
evidence with the Omanome owner snapshot. Do not infer ownership from a short
name and do not use a broadcast action such as `pkill lua`; Omanome's watchdog
has no termination path for exactly this reason.

If an incident is outside Omanome's ownership boundary, the correct Omanome
result is an attribution report and a regression guard, not killing the foreign
process or claiming that Omanome fixed it. Runtime measurements should report
the exact command, sample interval, host conditions, and whether the value was
measured or unavailable.
