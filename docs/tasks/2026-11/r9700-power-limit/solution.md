---
type: Solution
description: The R9700 is capped at 210 W, its hardware floor — the lowest reachable value, measured against three engine profiles and two workloads, with the cap applied at boot and on resume by a systemd oneshot.
task: definition.md
authored_by: agent
timestamp: 2026-11-20T07:40:00+01:00
---

# Cap the R9700 board power at its 210 W floor

Measured 2026-11-20 on brys, one card, one engine at a time.

## The reference: full power (300 W, the factory value)

| profile     | engine configuration        | decode t/s | long prefill t/s (37k prompt) | board power |
| ----------- | --------------------------- | ---------: | ----------------------------: | ----------: |
| `max`       | UD-IQ4_XS on the whole card |   **85.0** |                    **1660.2** |     259.7 W |
| `omni-fast` | IQ2_XS + 21.5 GB reserve    |   **75.5** |                    **1406.7** |     241.3 W |
| `omni-max`  | UD-IQ4_XS + 21.5 GB reserve |   **44.6** |                    **1038.8** |     192.9 W |

Every percentage below is against that profile's own 300 W row. Decode is the median of three runs
of 768 streamed tokens with the first 64 skipped; long prefill is a ~37k-token prompt that starts
with a random nonce so the prefix cache cannot answer it.

## The curves

`max` — the whole-card profile is the only one the cap actually binds:

| cap W | decode t/s |   vs 300 W | long prefill t/s |   vs 300 W | board power | junction |
| ----: | ---------: | ---------: | ---------------: | ---------: | ----------: | -------: |
|   300 |       85.0 |          — |           1660.2 |          — |     259.7 W |     56 C |
|   275 |       85.8 |     +0.9 % |           1643.3 |     −1.0 % |     259.6 W |     60 C |
|   250 |       80.2 |     −5.6 % |           1637.1 |     −1.4 % |     237.9 W |     59 C |
|   225 |       82.3 |     −3.2 % |           1615.7 |     −2.7 % |     219.5 W |     60 C |
|   210 |       77.0 | **−9.4 %** |           1607.4 | **−3.2 %** | **203.6 W** |     62 C |

`omni-fast` — the resting profile; the cap costs almost nothing:

| cap W | decode t/s |   vs 300 W | long prefill t/s |   vs 300 W | board power | junction |
| ----: | ---------: | ---------: | ---------------: | ---------: | ----------: | -------: |
|   300 |       75.5 |          — |           1406.7 |          — |     241.3 W |     63 C |
|   275 |       76.8 |     +1.7 % |           1411.0 |     +0.3 % |     241.6 W |     62 C |
|   250 |       76.7 |     +1.6 % |           1395.6 |     −0.8 % |     232.5 W |     61 C |
|   225 |       75.5 |      0.0 % |           1375.3 |     −2.2 % |     213.7 W |     61 C |
|   210 |       74.3 | **−1.6 %** |           1368.3 | **−2.7 %** | **202.7 W** |     62 C |

`omni-max` — already below the cap at full power, so the cap is a no-op:

| cap W | decode t/s |   vs 300 W | long prefill t/s |   vs 300 W | board power | junction |
| ----: | ---------: | ---------: | ---------------: | ---------: | ----------: | -------: |
|   300 |       44.6 |          — |           1038.8 |          — |     192.9 W |     64 C |
|   275 |       45.9 |     +2.9 % |           1047.9 |     +0.9 % |     193.7 W |     65 C |
|   250 |       46.1 |     +3.4 % |           1046.5 |     +0.7 % |     195.5 W |     65 C |
|   225 |       43.4 |     −2.7 % |           1040.6 |     +0.2 % |     196.7 W |     65 C |
|   210 |       45.4 | **+1.8 %** |           1034.2 | **−0.4 %** | **193.5 W** |     66 C |

Read the curves, not the rows: **decode is flat until the cap actually binds, and long prefill
barely moves at all.** Prefill is a memory-bound stream (the 37k prompt runs at 1.0–1.7k t/s on
all three profiles) and the SMU can keep the memory controllers fed below 210 W. Decode only loses
when the whole-card profile is forced under roughly 250 W, and even then it loses 3–9 %, which is
the same order as the run-to-run spread (±2–3 t/s).

`omni-max` is worth a note: with a 21.5 GB reserve the expert cache is small, so the card sits at
~193 W at full power. Capping it changes nothing. The profile is the power lever there, not the cap.

## Below the floor: refused, all the way down

`power1_cap_min` is **210000000 µW**. The SMU caches its range once at init and rejects anything
outside it with `EINVAL` before the value reaches the hardware; the card keeps its previous value.

| asked | card reports | result                                                                       |
| ----: | -----------: | ---------------------------------------------------------------------------- |
| 209 W |            — | refused (predicted by the range check; 200 W and below were probed directly) |
| 200 W |        210 W | **refused**: `tee: power1_cap: Invalid argument`                             |
| 175 W |        210 W | refused, same error                                                          |
| 150 W |        210 W | refused, same error                                                          |
| 100 W |        210 W | refused, same error                                                          |
|  50 W |        210 W | refused, same error                                                          |

So 100 W and 50 W are not a stability question — the write never lands. Reports of 200–220 W on
other R9700s match what this card allows at the bottom; anything lower needs a modified `pp_table`,
which is out of scope (`hardware.amdgpu.overdrive` raises the ceiling, never lowers the floor).

## What was chosen, and why

**210 W — the floor.** Against the target of ≤10 % decode loss and ≤20 % for comparison:

- `max`: −9.4 % decode, −3.2 % prefill, 56 W less board power (−22 %).
- `omni-fast`: −1.6 % decode, −2.7 % prefill, 39 W less (−16 %).
- `omni-max`: unchanged, and it never reached the cap anyway.

No reachable cap costs 20 %: the floor is the limit, so the comparison column is empty by
construction. `225 W` looks marginally better for `max` in this sample (82.3 vs 77.0 t/s) but that
is inside the ±2–3 t/s spread and it costs 16 W more.

Stability at 210 W, sustained: 8 consecutive 512-token generations in the earlier run and 15 grid
points across three profiles — no failed request, no GPU reset, no ring timeout in `dmesg`, junction
56–66 °C. The card is power-throttled, not thermally throttled.

## Implementation

`hosts-den/brys/gpu-power.nix`:

- `r9700-power-cap.service` (oneshot, `WantedBy=multi-user.target`) writes `power1_cap` to
  `power1_cap_min` — it clamps to whatever the kernel advertises, so a different VBIOS gets a legal
  value instead of an error — then **reads it back** and fails loudly if the value did not stick.
- `r9700-power-cap-resume.service` re-applies it on resume: the cap is not persisted by the driver.
- The script targets the R9700 only (`PCI_ID=1002:7551`); the Radeon 550 sits in the same chassis
  and a board-power cap written to it would be meaningless.
- The unit waits up to 30 s for the hwmon attributes instead of depending on `systemd-udev-settle`.

Verify with `systemctl status r9700-power-cap` (it prints the applied value and the card's range) and
`cat /sys/class/drm/card1/device/hwmon/hwmon2/power1_cap`.

## Reproducing

```sh
hack/r9700-power.sh --host brys show                    # cap, range, live power, temps
hack/probe-power-grid.py                                # the three tables above, ~25 min
hack/probe-power-cap.py                                 # the floor probe: 200/175/150/100/50 W
```

## Caveats

- The numbers are medians of three runs; the run-to-run spread is ±2–3 t/s on decode, which is the
  same size as the difference between adjacent caps above 225 W. Do not read single runs.
- Caps were measured descending inside a profile, so a later row is a slightly warmer card. Junction
  temperatures stayed 56–66 °C, well below throttling, so this does not change the shape.
- `power1_average` is the SMU's input-power estimate, not a wall meter; it under-reports idle and
  cannot show transients.
