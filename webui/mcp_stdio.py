"""
MCP stdio 模式入口 — 供 CodeBuddy / Claude Desktop / Cline 等以子进程方式调用。

与 app.py 的 SSE 模式（常驻 127.0.0.1:5001）的区别：
  - SSE  : 需先启动 WebUI，客户端连 http://127.0.0.1:5001/sse
  - stdio: 客户端自行启动本脚本作为子进程，通过 stdin/stdout 通信，无需常驻端口

两者复用同一套工具定义（webui/app.py 中 _register_mcp_tools 注册）。

CodeBuddy 配置示例（Settings -> MCP -> Add MCP）：
{
  "mcpServers": {
    "pc-optimizer": {
      "type": "stdio",
      "command": "python",
      "args": ["d:\\\\workspace\\\\PC-Optimizer-7thGen\\\\webui\\\\mcp_stdio.py"],
      "description": "PC-Optimizer 系统优化工具集"
    }
  }
}
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import app  # noqa: E402


def main():
    if not app.MCP_AVAILABLE or app.mcp is None:
        sys.stderr.write(
            "[MCP] mcp 库未安装或版本不兼容。请执行: pip install \"mcp<2\"\n"
            "      注意 mcp 2.x 把 FastMCP 改名为 MCPServer，与本项目不兼容。\n"
        )
        sys.exit(1)
    # stdio 传输：通过标准输入输出与客户端通信
    app.mcp.run(transport="stdio")


if __name__ == "__main__":
    main()
