---
type: Task
description: Measure the power draw of host `brys` with a Zigbee metering plug reported into Home Assistant on `briv`, and record idle and LLM-load wattage.
status: open
authored_by: agent
timestamp: 2026-10-11T11:05:00+02:00
---

# Measure `brys` power draw over Zigbee

## Context

- `brys` is the heavy local-LLM box (many cores, a Radeon Pro W6600, `performance` CPU
  governor). Its power draw is unknown. The thermal and clock behaviour of the W6600 hangs
  (`docs/tasks/2026-10/w6600-amdgpu-hang/`) make the power budget worth measuring.
- `briv` runs Home Assistant with the ZHA integration and a ZBT-1 Zigbee coordinator
  (`kdn.services.home-assistant.zha` in `hosts/briv/default.nix`).
- A Zigbee metering smart plug (for example a Sonoff S31 Lite ZB or equivalent with an
  energy-sensor entity) pairs into ZHA and reports W and kWh with no extra gateway.

## Goal

Get a continuous power reading for `brys` from a Zigbee metering plug, visible in the Home
Assistant energy dashboard on `briv`, and record the numbers in this task.

## Steps

1. Buy or locate one Zigbee metering plug.
2. Pair it with the ZBT-1 coordinator through ZHA.
3. Socket `brys` through the plug.
4. Add the sensor to the HA energy dashboard, per-device.
5. Record: idle watts, watts during a Qwen decode run, and watts during a full CPU build.

## Acceptance test

1. The plug reports live power in HA for at least 24 hours without dropping off the mesh.
2. `definition.md` (or a sibling `done.md`) carries the three measured numbers.

## Risks and open questions

- The plug's rated current must cover `brys` peak draw (PSU is far above typical draw, but
  check the inrush and the sustained amperage).
- ZHA on `briv`: confirm the coordinator reaches the desk where `brys` sits, or add a router.

## Related docs

- `hosts/briv/default.nix` — the HA + ZHA wiring.
- `modules/den/aspects/service-home-assistant.nix` — the ZHA aspect.
