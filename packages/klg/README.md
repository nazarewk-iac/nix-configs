# klg

An opinionated utility for working with https://klog.jotaen.net/ time-tracking

## Commands overview

### `klg stop [args...]`

just forwards to `klog stop`

### `klg resume [args...]`

issues a `klog start` using the last closed range's summary, errors out on finding open range.

### `klg fmt [file]`

format a `*.klg` file in opinionated way, see [`tests/test_format.py`](tests/test_format.py) for details.

### `klg report --report=NAME`

generate a CSV (and xlsx if `libreoffice` is available) report for a selected period (current month by default) using
`reports.NAME` configuration in `~/.config/klg/config.toml`:

```toml
[reports.default]
resource = "John Doe"
tags = ["#emp1", "emp2"]

[[reports.default.fields]]
field = "Rate Multiplier"
mappings = [
    { tag = '#emergency', value = "1.5" },
    { tag = "", value = "1.0" }
]

[[reports.default.fields]]
field = "Employer"
mappings = [
    # don't track which employer is time off for
    { tag = '#off', value = "-" },
    { tag = '#emp1', value = "Employer 1" },
    { tag = '#emp2', value = "Employer 2" },
    # fallback value
    { tag = "", value = "myself" },
]

[[reports.default.fields]]
field = "Project"
mappings = [
    { tag = '#emp1="Project X"', value = "Project X" },
    { tag = '#emp1="Project Y"', value = "Project Y" },
    { tag = '#emp2="Project A"', value = "Project A" },
    { tag = '#emp2="Project B"', value = "Project B" },
    # don't track which project is time off for
    { tag = '#off', value = "-" },
    { tag = '#emp1', value = "miscleanous work" },
    { tag = '#emp2', value = "-" },
]

```