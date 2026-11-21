# The media bench
#
# One Makefile per capture. Every stage is a file target, so `make` resumes after a failure and
# re-runs only what changed — which is what a two-hour tape needs.
#
# Stages that need a GPU model go through `admit`, never straight to a server: the placement tree
# decides whether the card can take it, and a `wait` verdict means the step waits rather than fails.
#
#   make -f hack/media/Makefile cut freeze transcribe encode report \
#     SRC=/data/vhs/tape-07.mkv OUT=/data/vhs/tape-07
#
# Two rules govern the picture, and both are checked rather than promised:
#
#   1. Archiving never upscales. No stage that feeds `master` may carry a `scale` filter that adds
#      pixels, and the master is the capture's own resolution or smaller. `report` fails when the
#      master is larger than the source. The one upscale in this file is `enhance`, which is not
#      the archive: it is off `all`, off `master`'s dependency tree, tagged in its filename and in
#      its metadata, and refuses to run when the source is already at its target height.
#   2. A frozen picture is reported, never silently archived. `freeze` classifies every held span:
#      longer than `STUCK_SECONDS` (10) is a paused or stuck player and the operator must check the
#      tape, anything shorter is a still shot. `report` lists both classes and flags a capture that
#      is stuck for more than a third of its content.
#
# The bench never deletes the source. Masters stay where they are produced; `proxy.mp4` is the only
# target meant to be copied to a weaker client.

SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c

SRC ?=
OUT ?= $(if $(SRC),$(basename $(SRC)).work,)
FFMPEG ?= ffmpeg
FFPROBE ?= ffprobe
ADMIT ?= kdn-inference-helpers admit
NTFY ?= $(HOME)/.config/ntfy/topic
WHISPER ?= whisper-cli
WHISPER_MODEL ?= /var/lib/kdn/llms/models/whisper/ggml-base.en.bin
WHISPER_LANG ?= auto
# freeze: a span of no change longer than this is a stuck player, not a still shot.
STUCK_SECONDS ?= 10
FREEZE_NOISE ?= 0.003
FREEZE_MIN ?= 2
# enhance: the target height of the optional, tagged upscale. It is not the archive.
ENHANCE_HEIGHT ?= 1080

ifeq ($(strip $(SRC)),)
$(error set SRC=<capture file>)
endif
ifeq ($(strip $(OUT)),)
$(error set OUT=<work directory>)
endif

PROBE := $(OUT)/probe.json
CUT := $(OUT)/cut.mkv
CUT_JSON := $(OUT)/cut.json
FROZEN := $(OUT)/frozen.json
DEINT := $(OUT)/deinterlaced.mkv
VDN := $(OUT)/video-denoised.mkv
WAV := $(OUT)/audio.wav
ACLEAN := $(OUT)/audio-clean.wav
TRANSCRIPT := $(OUT)/transcript.txt
MASTER := $(OUT)/master.mkv
PROXY := $(OUT)/proxy.mp4
REPORT := $(OUT)/report.json
ENHANCED := $(OUT)/enhanced.review-required.mkv

.PHONY: all clean notify probe-print cut deint denoise audio transcribe freeze master proxy \
	enhance report encode
all: $(MASTER) $(PROXY) $(REPORT)

# Named aliases: a person types `make cut`, not `make /data/tape.work/cut.mkv`.
cut: $(CUT)
deint: $(DEINT)
denoise: $(VDN)
audio: $(ACLEAN)
transcribe: $(TRANSCRIPT)
freeze: $(FROZEN)
master: $(MASTER)
proxy: $(PROXY)
enhance: $(ENHANCED)
report: $(REPORT)
encode: $(MASTER) $(PROXY)

# ---------------------------------------------------------------- inspection
$(OUT):
	mkdir -p $@

$(PROBE): $(SRC) | $(OUT)
	$(FFPROBE) -v error -print_format json -show_format -show_streams "$<" > "$(basename $@).tmp$(suffix $@)"
	mv "$(basename $@).tmp$(suffix $@)" "$@"

probe-print: $(PROBE)
	@python3 -c 'import json,sys; d=json.load(open("$(PROBE)")); f=d["format"]; print(f"{f[\"duration\"]}s, {f[\"size\"]} bytes")'

# ---------------------------------------------------------------- cut to content
# A VHS capture starts and ends with black or snow. `blackdetect` finds the ends; the cut keeps the
# span between the first and the last non-black second. A capture that is black throughout is left
# alone and flagged, which is the "broken recording" tag. The marker goes beside `cut.mkv`, not
# beside the temporary name the cut is written under.
$(CUT) $(CUT_JSON) &: $(SRC) $(PROBE) | $(OUT)
	@python3 hack/media/cut.py --src "$(SRC)" --probe "$(PROBE)" --out "$(basename $(CUT)).tmp.mkv" \
	  --marker "$(CUT).broken.json" --info "$(CUT_JSON)" --ffmpeg "$(FFMPEG)"
	mv "$(basename $(CUT)).tmp.mkv" "$(CUT)"

# ---------------------------------------------------------------- freeze
# A held picture is either a still shot in the content or a paused/stuck player, and `freezedetect`
# cannot tell them apart: the duration is the only difference. The span is classified, never cut —
# a tape that paused for a minute is still the tape. `freeze.py` scans the cut and not the source,
# because the black preamble is a static picture too and would be reported as stuck.
$(FROZEN): $(CUT)
	@python3 hack/media/freeze.py --src "$<" --out "$(basename $@).tmp.json" \
	  --noise $(FREEZE_NOISE) --min $(FREEZE_MIN) --stuck $(STUCK_SECONDS) \
	  --ffmpeg "$(FFMPEG)" --ffprobe "$(FFPROBE)"
	mv "$(basename $@).tmp.json" "$@"

# ---------------------------------------------------------------- picture
$(DEINT): $(CUT)
	$(FFMPEG) -hide_banner -loglevel error -y -i "$<" -vf "bwdif=mode=send_field:parity=auto:deint=all" \
	  -c:v ffv1 -level 3 -c:a copy "$(basename $@).tmp$(suffix $@)"
	mv "$(basename $@).tmp$(suffix $@)" "$@"

$(VDN): $(DEINT)
	$(FFMPEG) -hide_banner -loglevel error -y -i "$<" -vf "hqdn3d=4:3:6:4.5" -c:v ffv1 -level 3 -c:a copy "$(basename $@).tmp$(suffix $@)"
	mv "$(basename $@).tmp$(suffix $@)" "$@"

# ---------------------------------------------------------------- sound
# A capture can be silent, or be a tape with a dead audio track: an empty WAV then stands for "no
# audio", and the master step omits the stream instead of failing.
$(WAV): $(CUT)
	@if $(FFPROBE) -v error -select_streams a -show_entries stream=index -of csv=p=0 "$<" | grep -q .; then \
	  $(FFMPEG) -hide_banner -loglevel error -y -i "$<" -vn -c:a pcm_s16le -ar 48000 "$(basename $@).tmp$(suffix $@)" && \
	  mv "$(basename $@).tmp$(suffix $@)" "$@"; \
	else \
	  echo "no audio stream in $<; the master will be video only" >&2; \
	  : > "$@"; \
	fi

# Tape hiss is broadband and sits above speech: a high-pass, a spectral gate and a gentle low-pass
# remove most of it without the artefacts a neural denoiser leaves on music. `deepFilter` is used
# when its CLI is installed, because it is better on speech and worse on music.
$(ACLEAN): $(WAV)
	@if [ ! -s "$<" ]; then : > "$@"; exit 0; fi
	@if command -v deepFilter >/dev/null 2>&1; then \
	  deepFilter --input "$<" --output "$(OUT)/audio-clean" && \
	  mv "$(OUT)/audio-clean/"*.wav "$(basename $@).tmp$(suffix $@)"; \
	else \
	  $(FFMPEG) -hide_banner -loglevel error -y -i "$<" \
	    -af "highpass=f=70,afftdn=nf=-25:tn=1,lowpass=f=12000" \
	    -c:a pcm_s16le "$(basename $@).tmp$(suffix $@)"; \
	fi
	mv "$(basename $@).tmp$(suffix $@)" "$@"

# Speech to text: the archive index, and "is this tape worth keeping" without watching it.
$(TRANSCRIPT): $(ACLEAN)
	@if [ ! -s "$<" ]; then echo "no audio to transcribe" >&2; : > "$@"; exit 0; fi
	@if [ ! -r "$(WHISPER_MODEL)" ]; then \
	  echo "no whisper model at $(WHISPER_MODEL); skipping the transcript" >&2; : > "$@"; exit 0; \
	fi
	$(WHISPER) -m "$(WHISPER_MODEL)" -f "$<" -l $(WHISPER_LANG) -otxt \
	  -of "$(basename $@).tmp" -np >/dev/null 2>&1
	mv "$(basename $@).tmp.txt" "$@"

# ---------------------------------------------------------------- master
# SVT-AV1 at CRF 28, 10-bit: the archive format. `make vmaf` gates it.
#
# RULE: the master is never upscaled. There is no `scale` filter here, and none may be added: the
# master keeps the capture's own resolution, because the pixels a VHS tape holds are the most the
# archive can ever contain and a bigger frame only invents the rest. `report` fails when the master
# comes out larger than the source. A viewer that wants more lines from 576 may have the tagged
# `enhance` derivative, which is not the archive and says so in its name and its metadata.
$(MASTER): $(VDN) $(ACLEAN)
	@if [ -s "$(ACLEAN)" ]; then \
	  $(FFMPEG) -hide_banner -loglevel error -y -i "$(VDN)" -i "$(ACLEAN)" \
	    -map 0:v:0 -map 1:a:0 -c:v libsvtav1 -preset 6 -crf 28 -pix_fmt yuv420p10le \
	    -c:a libopus -b:a 128k -metadata title="$(notdir $(OUT))" "$(basename $@).tmp$(suffix $@)"; \
	else \
	  $(FFMPEG) -hide_banner -loglevel error -y -i "$(VDN)" \
	    -map 0:v:0 -c:v libsvtav1 -preset 6 -crf 28 -pix_fmt yuv420p10le \
	    -metadata title="$(notdir $(OUT))" "$(basename $@).tmp$(suffix $@)"; \
	fi
	mv "$(basename $@).tmp$(suffix $@)" "$@"

# A small proxy for the client side: at most 720 lines, 8-bit, fast to copy to a laptop. A PAL
# capture is already 576 lines, so the cap keeps the proxy below the master instead of upscaling
# it, and the 8-bit format is what consumer players decode.
$(PROXY): $(MASTER)
	$(FFMPEG) -hide_banner -loglevel error -y -i "$<" -vf "scale=-2:'min(720,ih)'" \
	  -c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p -c:a aac -b:a 96k "$(basename $@).tmp$(suffix $@)"
	mv "$(basename $@).tmp$(suffix $@)" "$@"

# ---------------------------------------------------------------- enhance (not the archive)
# The optional upscale, for a person who wants to look at a 576-line tape on a 1080-line screen.
# Three things keep it out of the archive:
#
#   * it is off `all` and nothing depends on it, so no ordinary run produces it;
#   * the filename says `review-required` and the metadata says the same, so a copy that escapes
#     the work directory cannot pass for the master. The key is `COMMENT`, not `comment`: Matroska
#     keeps the uppercase spelling and silently drops the lowercase one, which is how a warning tag
#     disappears without a message;
#   * it refuses when the master already has `ENHANCE_HEIGHT` lines or more: an upscale of an
#     upscale is pixels without detail, and this stage exists to be reviewed, not to be trusted.
#
# Deleting `enhanced.review-required.mkv` loses nothing: the master is the record, and this file is
# reproducible from it at any time.
#
# The guard is a phony prerequisite, so it runs every time `enhance` is asked for — even when a
# derivative from an earlier run is still on disk. A refusal that only fires on the first run is not
# a refusal.
.PHONY: enhance-guard
enhance-guard: $(MASTER)
	@h=$$($(FFPROBE) -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$(MASTER)"); \
	if [ "$${h:-0}" -ge $(ENHANCE_HEIGHT) ]; then \
	  echo "enhance: refused: the master is $$h lines, at or above ENHANCE_HEIGHT=$(ENHANCE_HEIGHT)." >&2; \
	  echo "enhance: an upscale adds pixels, not detail; the archive stays at $$h." >&2; \
	  exit 1; \
	fi

$(ENHANCED): $(MASTER) enhance-guard
	@h=$$($(FFPROBE) -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$(MASTER)"); \
	echo "enhance: $$h -> $(ENHANCE_HEIGHT) lines, derived and tagged; NOT part of the archive" >&2
	$(FFMPEG) -hide_banner -loglevel error -y -i "$<" \
	  -vf "scale=-2:$(ENHANCE_HEIGHT):flags=lanczos,unsharp=5:5:0.4:5:5:0.0" \
	  -c:v libx264 -preset medium -crf 18 -pix_fmt yuv420p -c:a copy \
	  -metadata title="$(notdir $(OUT)) (derived upscale, human review required)" \
	  -metadata COMMENT="derived upscale, human review required" \
	  "$(basename $@).tmp$(suffix $@)"
	mv "$(basename $@).tmp$(suffix $@)" "$@"

# ---------------------------------------------------------------- report
# The archive report: what the tape is, what was cut, what was frozen and how long, where the
# transcript is, and how big the products came out. Two rules are checked here, so the run cannot
# quietly break either one: the master must not be larger than the source, and a capture that is
# stuck for more than a third of its content is flagged `suspect`.
$(REPORT): $(MASTER) $(PROXY) $(TRANSCRIPT) $(FROZEN) $(CUT_JSON) $(PROBE)
	@python3 hack/media/report.py --out "$(basename $@).tmp.json" --probe "$(PROBE)" \
	  --cut-json "$(CUT_JSON)" --frozen-json "$(FROZEN)" --transcript "$(TRANSCRIPT)" \
	  --master "$(MASTER)" --proxy "$(PROXY)" --ffprobe "$(FFPROBE)"
	mv "$(basename $@).tmp.json" "$@"

# ---------------------------------------------------------------- gates
# VMAF of the master against the denoised source. Below the floor the encode is rejected.
VMAF_FLOOR ?= 93
vmaf: $(MASTER)
	@python3 hack/media/vmaf.py --reference "$(VDN)" --distorted "$(MASTER)" --floor $(VMAF_FLOOR) --ffmpeg "$(FFMPEG)"

notify:
	@echo "notification is a placeholder: no backend is wired (ntfy was a far-future idea)" >&2

# The intermediates are the reason a two-hour tape needs 42 GiB while it runs. `clean` drops them and
# keeps everything the archive is made of: the master, the proxy, the report and the transcript, plus
# the two small JSON files the report reads. The source is never touched. A later `make` rebuilds
# what it needs from `cut.mkv` and re-encodes the master, so `clean` belongs at the end of a capture,
# not in the middle of one.
clean:
	rm -f "$(DEINT)" "$(VDN)" "$(WAV)" "$(ACLEAN)" "$(basename $(DEINT)).tmp.mkv" \
	  "$(basename $(VDN)).tmp.mkv" "$(basename $(WAV)).tmp.wav" "$(basename $(ACLEAN)).tmp.wav"
	@echo "clean: intermediates removed; $(MASTER), $(PROXY), $(REPORT) kept" >&2
