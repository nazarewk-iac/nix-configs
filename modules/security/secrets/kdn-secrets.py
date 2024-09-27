import dataclasses
import re
from pathlib import Path

import fire

pattern: str = ""
placeholder_pattern = re.compile(pattern)

common_kwargs = dict(
    output="/dev/stdout"
)


@dataclasses.dataclass
class Program:
    @staticmethod
    def _line_handler(line, out):
        start = 0
        end = len(line)
        matches = list(placeholder_pattern.finditer(line))
        for match in matches:
            out.write(line[start:match.start()])
            path = match["path"]
            out.write(Path(path).read_text())
            start = match.end()
        out.write(line[start:end])

    def render_file(self, input="/dev/stdin", **kwargs):
        kwargs = common_kwargs | kwargs
        with (
            Path(input).open("r") as inp,
            Path(kwargs["output"]).open("w") as out,
        ):
            for line in inp:
                self._line_handler(line, out)

    def render_string(self, input: str, **kwargs):
        kwargs = common_kwargs | kwargs
        with (Path(kwargs["output"]).open("w") as out):
            for line in input.splitlines(keepends=True):
                self._line_handler(line, out)


if __name__ == "__main__":
    fire.Fire(Program())
