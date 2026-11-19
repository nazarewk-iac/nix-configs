# LLM tuning shared by the main brys profile and the `llms` appliance entry.
#
# Two consumers, two different goals, one file:
#
#   * the main profile (hosts-den/brys/default.nix) — a desktop that also serves the fleet,
#     so a model must yield to the user;
#   * the `llms` entry (hosts-den/brys/llm-appliance.nix) — a dedicated appliance that may
#     reserve the machine for throughput.
#
# Only the settings that are correct on **both** live here. Anything that trades
# responsiveness for throughput belongs in the appliance's own block, because that is
# the whole reason the appliance exists.
#
# ## Why not `isolcpus` here
#
# The appliance reserves cores with `isolcpus/nohz_full/rcu_nocbs`. On a desktop that is
# disqualifying: those flags remove cores from the scheduler, so every ordinary task is
# confined to what is left. That tuning stays in the appliance entry.
#
# ## What is genuinely shared, and why
#
# * **ZFS ARC cap.** The model GGUFs live on ZFS. Without the cap the ARC grows to about
#   half of RAM and evicts the mmap'd weights, which are then re-read from disk. Measured
#   on the main profile before the cap: 0.18 tok/s prefill, 6.3M major faults, 271 GB
#   read. With it, the weights stay resident. A desktop wants its page cache too, so this
#   helps both consumers for the same reason.
# * **`transparent_hugepage=madvise`.** Keeps THP available where a program asks for it
#   without the latency spikes of `always`. Good for a 95 GiB `mmap` and neutral for a
#   desktop.
# * **`numa_balancing=disable`.** One socket, so balancing only adds migration work.
# * **The performance governor on the appliance, a soft default here.** CPU-only MoE decode
#   is memory-bandwidth bound, and the default `powersave` governor ramps cores unevenly:
#   measured 6.25 tok/s / 1.06 s TTFT on `performance` against 3.27 tok/s / 47 s TTFT on
#   `powersave`. A desktop does not want the heat, so it keeps the choice as a default it
#   can override.
{ lib, ... }:
{
  # The ARC cap. 8 GiB is a measured value, not a guess: it must be small enough that the
  # model's page cache survives, and large enough that ordinary file I/O is still cached.
  # `madvise` rather than `always` keeps THP available to a 95 GiB mmap without the
  # `always` stalls, and one socket needs no NUMA balancing.
  boot.kernelParams = [
    "zfs.zfs_arc_max=8589934592"
    "transparent_hugepage=madvise"
    "numa_balancing=disable"
  ];

  # A soft default: the appliance overrides it with `mkForce`.
  powerManagement.cpuFreqGovernor = lib.mkDefault "performance";

  boot.kernel.sysctl = {
    "vm.compaction_proactiveness" = 0;
    "fs.file-max" = 1048576;
    # A model load is one huge allocation burst (about 95 GiB of anon at its peak) taken while the
    # pack is being read into page cache. The defaults (min_free 66 MiB, scale 0.1 %) wake kswapd
    # late, so the burst can consume free memory before reclaim starts: measured 2026-11-19, every
    # failing load ended at RSS 88-98 GiB with `free` at 0.
    #
    # Honest limit: these two do **not** make a load fit. With them the failing load still reached
    # 93 GiB and still died; only a reboot (a fresh page cache and ARC) made the same profile load
    # and serve. They stay because a floor of 2 GiB free plus earlier reclaim is cheaper for the
    # burst than a free-fall to zero, and they cost nothing at steady state, where a served model
    # holds its pages and nothing is reclaimed.
    "vm.min_free_kbytes" = 2097152;
    "vm.watermark_scale_factor" = 200;
  };
}
