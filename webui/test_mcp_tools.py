import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import app  # noqa: E402


def test_guided_wizard_tools_are_registered():
    """v3.11.0 的一键向导必须出现在 MCP 工具表里，否则 AI 客户端用不上旗舰功能。"""
    registered = {}

    class FakeServer:
        def tool(self):
            def deco(fn):
                registered[fn.__name__] = fn
                return fn

            return deco

    app._register_mcp_tools(FakeServer())
    guided = sorted(k for k in registered if k.startswith("guided"))
    assert guided == ["guided_apply", "guided_export", "guided_plan", "guided_rerun"], guided


def test_guided_plan_tool_returns_a_plan():
    registered = {}

    class FakeServer:
        def tool(self):
            def deco(fn):
                registered[fn.__name__] = fn
                return fn

            return deco

    app._register_mcp_tools(FakeServer())
    result = registered["guided_plan"](skip_clean_scan=True)
    assert result.get("ok") is True, result
    assert len(result.get("steps") or []) > 0, result
    assert result.get("profile"), result


def test_guided_apply_tool_dry_run_is_side_effect_free():
    registered = {}

    class FakeServer:
        def tool(self):
            def deco(fn):
                registered[fn.__name__] = fn
                return fn

            return deco

    app._register_mcp_tools(FakeServer())
    result = registered["guided_apply"](dry_run=True, skip_clean_scan=True)
    assert result.get("dryRun") is True, result
    assert len(result.get("results") or []) > 0, result
