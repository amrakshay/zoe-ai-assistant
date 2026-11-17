"""Shared helpers for the F01 spike. Run every script through ./cleanenv.sh so no
CLAUDE_*/ANTHROPIC_* variables leak in from the Claude desktop host."""
import json
import os
import pathlib
import statistics
import time

HERE = pathlib.Path(__file__).resolve().parent
OUT = HERE / "out"
OUT.mkdir(exist_ok=True)
MODEL = "claude-haiku-5-5"


def now() -> float:
    return time.perf_counter()


def dump(name: str, obj) -> pathlib.Path:
    p = OUT / name
    p.write_text(json.dumps(obj, indent=2, default=str))
    return p


def summary(xs):
    xs = [x for x in xs if x is not None]
    if not xs:
        return {"n": 0}
    return {
        "n": len(xs),
        "median_s": round(statistics.median(xs), 3),
        "min_s": round(min(xs), 3),
        "max_s": round(max(xs), 3),
        "runs_s": [round(x, 3) for x in xs],
    }


def assert_no_api_key():
    assert "ANTHROPIC_API_KEY" not in os.environ, "ANTHROPIC_API_KEY must be unset"
    leaked = [k for k in os.environ if k.startswith(("CLAUDE", "ANTHROPIC"))]
    assert not leaked, f"run via ./cleanenv.sh; leaked vars: {leaked}"
