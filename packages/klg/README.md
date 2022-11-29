# klg

An opinionated utility for working with https://klog.jotaen.net/ time-tracking

## Reporting configuration

example `~/.config/klg/config.toml`:

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
    { tag = '#emp1', value = "Employer 1" },
    { tag = '#emp2', value = "Employer 2" },
    # don't track which employer is time off for
    { tag = '#off', value = "-" },
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