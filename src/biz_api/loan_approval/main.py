
import os
import sys
import asyncio
import logging
from logging_config import configure_logging
from mcp_tools import mcp

logger = logging.getLogger(__name__)

if __name__ == "__main__":
    # Windows ProactorEventLoop raises WinError 10054 on connection teardown.
    # SelectorEventLoop handles it cleanly.
    if sys.platform == "win32":
        asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())

    configure_logging()
    profile = os.environ.get("PROFILE", "prod")
    
    port = 8070 if profile == "dev" else 8080
    logger.info(f"Starting loan approval MCP server with profile: {profile}, port: {port}")
    mcp.run(transport="http", port=port, host="0.0.0.0")
