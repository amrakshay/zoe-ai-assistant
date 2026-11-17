"""Read-only: print uuid/parent/type/timestamp/text for one session transcript. usage: uv run q7_dump_chain.py <session_id>"""
import json, sys
from pathlib import Path
p = next((Path.home() / ".claude" / "projects").glob(f"*/{sys.argv[1]}.jsonl"))
for ln in p.read_text().splitlines():
    e = json.loads(ln)
    if not e.get("uuid"):
        continue
    c = (e.get("message") or {}).get("content")
    t = c if isinstance(c, str) else " ".join(x.get("text", "")[:40] for x in (c or []) if isinstance(x, dict))
    print(e["uuid"][:8], "<-", str(e.get("parentUuid"))[:8], e.get("type"), e.get("timestamp", "")[11:23],
          "entrypoint=" + str(e.get("entrypoint")), repr(t[:50]))
