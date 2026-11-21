---
type: Task
description: Follow-up research — what actually goes wrong when ripping VHS, and what analysing surveillance-style video would require.
status: open
authored_by: agent
timestamp: 2026-11-21T17:00:00+01:00
---

# Video analysis: ripping VHS, and watching streams

Research only. Nothing here is implemented; the point is to know what the bench must survive and
what a second class of work would need.

## Part 1 — what goes wrong when ripping VHS

Sources: Canadian Conservation Institute Technical Bulletin 31, IASA TC-06, the AV Artifact Atlas,
and the TBC literature. Ordered by how much they hurt an archive.

| defect                   | what it looks like                                                | cause                                                                             | our answer                                                                                                           |
| ------------------------ | ----------------------------------------------------------------- | --------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| **Time base error**      | wavy verticals, rolling, tearing, capture card giving up mid-tape | motor speed, tape stretch, head rotation                                          | **hardware**: a TBC in the VCR or a frame store. No software fix; without one the capture is unusable                |
| **Audio drift**          | audio slides out of sync over minutes                             | dropped frames without matching audio frames; unstable clocks                     | TBC plus a capture device that never drops; check by measuring drift at the end of a tape                            |
| **Tracking error**       | bands of noise, rolling lines, full "snow"                        | heads not following the recorded tracks, usually a different VCR than recorded it | adjust tracking per tape before capture; a second VCR if it will not settle                                          |
| **Dropouts**             | white/black streaks, flashes, brief audio loss                    | dust, wrinkles, lost oxide — permanent                                            | tape cleaning reduces the debris kind; **the bench should count them, not hide them**                                |
| **Head switching noise** | a distorted strip at the bottom of the frame                      | the head off/on interval, present on every VHS                                    | crop or mask the bottom lines; it is part of the signal                                                              |
| **Head clog / low RF**   | no image or very poor image                                       | dirty heads, misalignment                                                         | clean the heads; no software remedy                                                                                  |
| **Skew / stiction**      | image tearing, audible glitches, tape squeal                      | binder hydrolysis (sticky-shed), stretched tape                                   | treat the tape (bake), or the capture destroys it                                                                    |
| **Macrovision**          | pulsing brightness, AGC pumping on some cards                     | copy protection in the vertical blanking                                          | a TBC that ignores it; **removal is a legal question, not a technical one** — record the decision before touching it |
| **Interlacing**          | comb teeth on motion                                              | 50/60 fields per second                                                           | `bwdif` in the bench                                                                                                 |
| **Softness**             | no fine detail                                                    | VHS cannot record the higher frequencies                                          | nothing to fix; **do not upscale for archive**                                                                       |

### What this means for the bench

- **The bench cannot rescue a bad capture.** TBC, tracking and cleaning happen before the file
  exists. The bench's job is to _detect and report_, not to repair: black spans, frozen spans,
  dropouts, and a transcript.
- **Dropouts are a countable signal.** A `dropout` stage (frame-level difference or a black/white
  streak detector) would tell the operator which tapes to re-capture, which is worth more than any
  filter.
- **Audio drift is checkable.** Compare a marker at the start and the end of a tape (a spoken
  word at both ends) and measure the offset; the transcript already gives us the text.
- **Do not upscale for archive.** The source is 576 lines and soft; an upscale invents detail. A
  separate, tagged derivative after human review is the only acceptable form.
- **The paused/stuck player wart** is a freeze detector, already added: a frozen span over 10 s is
  `stuck`, and a capture that is stuck for a third of its length is `suspect`.

## Part 2 — surveillance-style streams

Three use cases, in increasing difficulty. All of them are **detect-then-describe**, not
"watch everything": a cheap detector finds the candidate moment, a vision model describes it, and a
person or a rule decides.

### A. Find when an event happened (shed panel torn off, window broken, car scratched)

Batch, retrospective, no deadline.

1. **Cheap pass**: frame differencing and motion-energy over a downscaled stream finds the
   _intervals_ with change; `scdet`/`freezedetect` narrow them; a long still period followed by a
   burst is the signature.
2. **Describe pass**: the reviewer (`qwen2.5-vl-7b`) gets 6-12 frames around each candidate and
   answers a fixed question — "what changed between these frames, and is a person present?".
3. **Search**: the description is embedded and indexed, so "when was the shed damaged" is a
   retrieval query over descriptions, not a re-scan of the video.

Cost: the cheap pass is CPU-bound and can run on any host; the describe pass is ~2 s per candidate
on the reviewer, which fits the `small` tier.

### B. Baby sleep: patterns and "key moments" for a night

Batch over one night's footage (8-10 h), low frame rate.

1. **Pose and motion** at 1 frame every few seconds: is the baby moving, is a parent present.
2. **Audio events**: crying onset/offset, duration, count — cheap, and the most useful signal.
3. **Key moments**: clip the 30 s around each cry onset, each position change, each adult entry.
4. **Summary**: an LLM writes the night's narrative from the event list, not from frames.

The hard part is **not** the model: it is the privacy and the storage. A night at 1 fps is ~30 k
frames; keep the event list and the clips, delete the rest.

### C. Real-time elderly safety (tripped, crying, not moving for minutes unless in bed)

**This is the one that must not be built casually.** It is a safety system with a false-negative
cost measured in hours, and the hardware/legal constraints dominate.

- **Latency budget**: detection in seconds, not minutes. That rules out the batch VLM pattern; it
  needs a small, always-on model (pose + fall classifier) on a local device, with the VLM only for
  confirming a candidate.
- **False negatives are the design target**, not accuracy: "not moving for N minutes while not in
  bed" is a rule, and a rule needs a _reliable_ bed/room segmentation — which is the hard part.
- **Privacy**: the camera feed of a person's home is the most sensitive data in this fleet. It
  stays on the device, only events leave, and the person must be able to see and delete everything.
- **Failure modes**: the system must announce its own blindness (camera offline, model stuck) rather
  than be silently confident.
- **Not a substitute for a person.** A rule that calls for help must have a human escalation path
  and a way to silence it.

### What all three share

| layer      | choice                                | why                                   |
| ---------- | ------------------------------------- | ------------------------------------- |
| detector   | classical (frame diff, `scdet`, pose) | cheap, explainable, runs anywhere     |
| describer  | `qwen2.5-vl-7b` (reviewer)            | already co-resident, 40 t/s           |
| index      | embeddings over descriptions          | "when did X happen" becomes retrieval |
| escalation | a rule + a human                      | never a model alone for safety        |

## Follow-ups this creates

1. **Bench**: a `dropout` counter and an audio-drift check (Part 1), on top of the freeze detector.
2. **Capture rig**: TBC decision, tracking procedure per tape, cleaning — hardware, not code.
3. **Monitoring PoC**: start with A (retrospective event search), because it needs no real-time
   guarantee and no privacy decision beyond "the footage is ours".
4. **Do not start C** until A works and the privacy design is written down.
