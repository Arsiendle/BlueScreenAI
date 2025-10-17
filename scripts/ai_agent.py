from config import API_KEY, BASE_URL, MODEL
from openai import OpenAI
from mcp.server.fastmcp import FastMCP
from server import SESSION
import json
import re
from typing import Any

mcp = FastMCP("AI BlueScreen Agent")
client = OpenAI(api_key=API_KEY, base_url=BASE_URL)

# ---------- 工具 ----------
def get_blue_screen_summary(session: Any) -> dict:
    if not session:
        return {"status": "error", "message": "No session"}
    out = session.send_command("!analyze -v", timeout=30.0)

    # ✅ 提炼关键字段
    bug = re.search(r'BUGCHECK_CODE:\s+([a-fA-F0-9]+)', out)
    prob = re.search(r'IMAGE_NAME:\s+(\S+)', out)
    err = re.search(r'ERROR_CODE:.*(0x[0-9a-fA-F]+)', out)
    disk = re.search(r'DISK_HARDWARE_ERROR:.*(There was error with disk hardware)', out)

    return {
        "status": "success",
        "bugcheck_code": bug.group(1) if bug else None,
        "probably_caused": prob.group(1).strip() if prob else None,
        "error_code": err.group(1) if err else None,
        "disk_error": disk.group(1) if disk else None,
        "raw": out[:2000],
    }

def get_call_stack(session: Any) -> dict:
    if not session:
        return {"status": "error", "message": "No session"}
    out = session.send_command("kv", timeout=10.0)
    return {"status": "success", "stack": "\n".join(out.splitlines()[:20])}

def get_module_by_address(session: Any, address: str) -> dict:
    if not session:
        return {"status": "error", "message": "No session"}
    out = session.send_command(f"lm a {address}", timeout=10.0)
    m = re.search(r"([a-fA-F0-9`]+)\s+([a-fA-F0-9`]+)\s+(\S+)", out)
    if m:
        start, end, name = m.groups()
        detail = session.send_command(f"!lmi {name}", timeout=10.0)
        path = re.search(r"Image path:\s+(.+?)\r", detail)
        ver = re.search(r"Image version:\s+(.+?)\r", detail)
        ts = re.search(r"Date stamp:\s+(.+?)\r", detail)
        return {
            "status": "success",
            "name": name,
            "start": start,
            "end": end,
            "image_path": path.group(1) if path else None,
            "image_version": ver.group(1) if ver else None,
            "time_stamp": ts.group(1) if ts else None,
            "detail": detail[:800],
        }
    return {"status": "error", "message": "Module not found"}

# ---------- AI 采样 ----------
def ai_sampling_loop_with_session(session: Any) -> str:
    from openai.types.chat import (ChatCompletionSystemMessageParam,
                                   ChatCompletionUserMessageParam,
                                   ChatCompletionToolMessageParam)

    summary = get_blue_screen_summary(session)

    messages = [
        ChatCompletionSystemMessageParam(
            role="system", content="你是 Windows 蓝屏根因分析专家。请根据以下信息输出一份**中文**蓝屏分析报告，包含：错误代码、责任模块、错误含义、用户处理建议。"
        ),
        ChatCompletionUserMessageParam(
            role="user", content=json.dumps(summary, ensure_ascii=False)
        ),
    ]

    resp = client.chat.completions.create(
        model=MODEL,
        messages=messages,
        tools=[],
        tool_choice="none"
    )

    return resp.choices[0].message.content or "无内容返回"