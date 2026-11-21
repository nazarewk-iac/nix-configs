# The media bench
#
# One Makefile per capture. Every stage is a file target, so `make` resumes after a failure and
# re-runs only what changed — which is what a two-hour tape needs.
#
# Stages that need a GPU model go through `admit`, never straight to a server: the placement tree
# decides whether the card can take it, and a `wait` verdict means the step waits rather than fails.
#
#   make -f hack/media/Makefile cut denoise encode SRC=/data/vhs/tape-07.mkv OUT=/data/vhs/tape-07
#
# The bench never deletes the source. Masters stay where they are produced; `proxies` is the only
# target meant to be copied to a weaker client.

SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c

SRC ?=
OUT ?= $(if $(SRC),$(basename $(SRC)).work,)
FFMPEG ?= ffmpeg
FFPROBE ?= ffprobe
ADMIT ?= kdn-inference-helpers admit
NTFY ?= $(HOME)/.config/ntfy/topic

ifeq ($(strip $(SRC)),)
$(error set SRC=<capture file>)
endif
ifeq ($(strip $(OUT)),)
$(error set OUT=<work directory>)
endif

PROBE := $(OUT)/probe.json
CUT := $(OUT)/cut.mkv
DEINT := $(OUT)/deinterlaced.mkv
VDN := $(OUT)/video-denoised.mkv
WAV := $(OUT)/audio.wav
ACLEAN := $(OUT)/audio-clean.wav
MASTER := $(OUT)/master.mkv
PROXY := $(OUT)/proxy.mp4

.PHONY: all clean notify probe-print cut deint denoise audio master proxy encode
all: $(MASTER) $(PROXY)

# Named aliases: a person types `make cut`, not `make /data/tape.work/cut.mkv`.
cut: $(CUT)
deint: $(DEINT)
denoise: $(VDN)
audio: $(ACLEAN)
master: $(MASTER)
proxy: $(PROXY)
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
# alone and flagged, which is the "broken recording" tag.
$(CUT): $(SRC) $(PROBE) | $(OUT)
	@python3 hack/media/cut.py --src "$(SRC)" --probe "$(PROBE)" --out "$(basename $(CUT)).tmp.mkv" --ffmpeg "$(FFMPEG)"
	mv "$(basename $(CUT)).tmp.mkv" "$(CUT)"

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

# DeepFilterNet if it is installed; the copy otherwise, so the chain never breaks on a missing tool.
$(ACLEAN): $(WAV)
	@if [ ! -s "$<" ]; then : > "$@"; exit 0; fi
	@if command -v deepFilter >/dev/null 2>&1; then \
	  deepFilter --input "$<" --output "$(OUT)/audio-clean" && \
	  mv "$(OUT)/audio-clean/"*.wav "$(basename $@).tmp$(suffix $@)"; \
	else \
	  echo "deepFilter not installed; keeping the source audio" >&2; \
	  cp "$<" "$(basename $@).tmp$(suffix $@)"; \
	fi
	mv "$(basename $@).tmp$(suffix $@)" "$@"

# ---------------------------------------------------------------- master
# SVT-AV1 at CRF 28, 10-bit: the archive format. `make vmaf` gates it.
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

# A small proxy for the client side: 720p, fast to copy to a laptop.
$(PROXY): $(MASTER)
	$(FFMPEG) -hide_banner -loglevel error -y -i "$<" -vf "scale=-2:720" \
	  -c:v libx264 -preset veryfast -crf 23 -c:a aac -b:a 96k "$(basename $@).tmp$(suffix $@)"
	mv "$(basename $@).tmp$(suffix $@)" "$@"

# ---------------------------------------------------------------- gates
# VMAF of the master against the denoised source. Below the floor the encode is rejected.
VMAF_FLOOR ?= 93
vmaf: $(MASTER)
	@python3 hack/media/vmaf.py --reference "$(VDN)" --distorted "$(MASTER)" --floor $(VMAF_FLOOR) --ffmpeg "$(FFMPEG)"

notify:
	@if [ -r "$(NTFY)" ]; then \
	  curl -fsS -m 10 -H "Title: media bench" -d "$$(basename $(OUT)) finished" "https://ntfy.sh/$$(cat $(NTFY))" >/dev/null && \
	  echo "notified"; \
	else \
	  echo "no ntfy topic at $(NTFY); skipping" >&2; \
	fi

clean:
	rm -rf "$(OUT)"
