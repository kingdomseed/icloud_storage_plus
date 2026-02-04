#!/usr/bin/env python3
from __future__ import annotations

import re
from pathlib import Path


def main() -> None:
    """
    Fixes relative links in DeepWiki-exported markdown when stored under
    `docs/deepwiki/`.

    The exporter generates links as if the markdown lives at the repo root
    (e.g. `(README.md)`, `(ios/Classes/...)`). When placed under `docs/`,
    those links break on GitHub. This script updates only the "Relevant source
    files" `<details>` block at the top of each page.
    """

    deepwiki_dir = Path("docs/deepwiki")
    if not deepwiki_dir.is_dir():
        raise SystemExit(
            "Expected 'docs/deepwiki/' to exist. "
            "Run deepwiki-export and move the output to docs/deepwiki first.",
        )

    link_re = re.compile(r"^(\s*-\s*\[[^\]]+\]\()([^)]+)(\)\s*)$")

    for path in sorted(deepwiki_dir.glob("*.md")):
        # Skip our manually-maintained landing page.
        if path.name == "README.md":
            continue

        text = path.read_text(encoding="utf-8")
        lines = text.splitlines(keepends=True)

        in_details = False
        changed = False
        out: list[str] = []

        for line in lines:
            if line.strip() == "<details>":
                in_details = True
                out.append(line)
                continue
            if line.strip() == "</details>":
                in_details = False
                out.append(line)
                continue

            if in_details:
                match = link_re.match(line)
                if match:
                    prefix, target, suffix = match.groups()
                    new_target = target

                    # Migrate legacy doc links into docs/notes.
                    if target == "doc/download-flow.md":
                        new_target = "../notes/download_flow.md"
                    elif target.startswith(("http://", "https://", "#", "../", "./")):
                        new_target = target
                    else:
                        new_target = f"../../{target}"

                    if new_target != target:
                        line = f"{prefix}{new_target}{suffix}"
                        changed = True

            out.append(line)

        if changed:
            path.write_text("".join(out), encoding="utf-8")


if __name__ == "__main__":
    main()

