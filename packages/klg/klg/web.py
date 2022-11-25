import pprint

import anyio
from nicegui import ui

from .klog import Klog


async def run(port: int = 8082):
    async def reload():
        result = klog.read()
        output.set_content("\n".join([
            "```",
            pprint.pformat(result),
            "```",
        ]))

    klog = Klog()
    ui.button('reload', on_click=reload)
    output = ui.markdown()
    ui.run(port=port)


if __name__ in ("__main__", "__mp_main__"):
    anyio.run(run)
