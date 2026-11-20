"""The session options that keep the gate in front of everything (#14). CI has no Claude login, so this pins
the configuration; the live check that a settings allow rule can't skip the hook is in the acceptance run (#22)."""
from zoe_core.brain import Brain
from zoe_core.policy import ENABLED_BUILTINS


async def _send(*a, **k):
    pass


def test_catch_all_hook_blocks_on_failure():
    o = Brain(_send).options()
    matchers = o.hooks["PreToolUse"]
    assert len(matchers) == 1
    m = matchers[0]
    assert m.matcher is None                      # every tool, not a name pattern
    assert getattr(m, "on_failure", None) == "block"
    assert m.hooks[0].__self__.__class__.__name__ == "Gate"


def test_no_permission_mode_that_skips_hooks():
    o = Brain(_send).options()
    assert o.permission_mode in (None, "default")


def test_only_gated_builtins_are_loaded():
    o = Brain(_send).options()
    assert set(o.tools) == set(ENABLED_BUILTINS)
    assert o.can_use_tool is not None             # catch-all that denies
