import re
import sys
from pathlib import Path
import dataclasses


net = Path("/run/secrets/networking")
anon = net / "anonymization"


@dataclasses.dataclass
class Replacement:
    pattern: str
    replacement: str

    def __post_init__(self):
        self.re = re.compile(self.pattern)

    def replace(self, txt):
        return self.re.sub(self.replacement, txt)


replacements = []
for entry in sorted(anon.iterdir()):
    kwargs = {file.name: file.read_text() for file in entry.iterdir()}
    replacements.append(Replacement(**kwargs))

for line in sys.stdin:
    for r in replacements:
        line = r.replace(line)
    sys.stdout.write(line)
