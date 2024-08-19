import re
import sys
from pathlib import Path
import dataclasses


net = Path("/run/configs/networking")
anon = net / "anonymization"


@dataclasses.dataclass
class Replacement:
    pattern: str
    replacement: str

    def __post_init__(self):
        self.re = re.compile(self.pattern)

    def replace_count(self, txt):
        return self.re.subn(self.replacement, txt)


replacements = []
for entry in sorted(anon.iterdir()):
    kwargs = {file.name: file.read_text() for file in entry.iterdir()}
    replacements.append(Replacement(**kwargs))

replacement_count = 0
for line in sys.stdin:
    for r in replacements:
        line, count = r.replace_count(line)
        replacement_count += count
    sys.stdout.write(line)

sys.stderr.write(f"replaced {replacement_count} matches")
