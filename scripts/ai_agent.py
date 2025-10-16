from config import API_KEY, BASE_URL, MODEL
from openai import OpenAI
from mcp.server.fastmcp import FastMCP
from server import SESSION
import json
import re
from typing import Any, List

mcp = FastMCP("AI BlueScreen Agent")
client = OpenAI(api_key=API_KEY, base_url=BASE_URL)

# ---------- 工具 ----------
@mcp.tool()
def get_blue_screen_summary(session: Any) -> dict:
    if not session: return {"status": "error", "message": "No session"}
    out = session.send_command("!analyze -v")
    bug = re.search(r"BugCheck\s+([A-F0-9]+)", out)
    prob = re.search(r"Probably caused by\s+:\s+(.+?)\r", out)
    return {"status": "success", "bugcheck_code": bug.group(1) if bug else None,
            "probably_caused": prob.group(1).strip() if prob else None, "raw": out[:2000]}

@mcp.tool()
def get_call_stack(session: Any) -> dict:
    if not session: return {"status": "error", "message": "No session"}
    out = session.send_command("kv")
    return {"status": "success", "stack": "\n".join(out.splitlines()[:20])}

@mcp.tool()
def get_module_by_address(session: Any, address: str) -> dict:
    if not session: return {"status": "error", "message": "No session"}
    out = session.send_command(f"lm a {address}")
    m = re.search(r"([a-fA-F0-9`]+)\s+([a-fA-F0-9`]+)\s+(\S+)", out)
    if m:
        start, end, name = m.groups()
        detail = session.send_command(f"!lmi {name}")
        path = re.search(r"Image path:\s+(.+?)\r", detail)
        ver = re.search(r"Image version:\s+(.+?)\r", detail)
        ts = re.search(r"Date stamp:\s+(.+?)\r", detail)
        return {"status": "success", "name": name, "start": start, "end": end,
                "image_path": path.group(1) if path else None,
                "image_version": ver.group(1) if ver else None,
                "time_stamp": ts.group(1) if ts else None, "detail": detail[:800]}
    return {"status": "error", "message": "Module not found"}

# ---------- AI 采样 ----------
def ai_sampling_loop_with_session(session: Any) -> str:
    from openai.types.chat import (ChatCompletionSystemMessageParam,
                                   ChatCompletionUserMessageParam,
                                   ChatCompletionToolMessageParam)

    messages: List[Any] = [
        ChatCompletionSystemMessageParam(
            role="system", content="你是 Windows 蓝屏根因分析专家。请按需调用工具，用最少命令确定根本原因并输出中文报告。"
        ),
        ChatCompletionUserMessageParam(
            role="user", content=str(get_blue_screen_summary(session)))
    ]

    resp = client.chat.completions.create(
        model=MODEL, messages=messages,
        tools=[{"type": "function", "function": {
            "name": "get_call_stack", "description": "获取调用栈",
            "parameters": {"type": "object", "properties": {}, "required": []}
        }}, {"type": "function", "function": {
            "name": "get_module_by_address", "description": "根据地址查模块",
            "parameters": {"type": "object", "properties": {"address": {"type": "string"}}, "required": ["address"]}
        }}], tool_choice="auto"
    )

    if resp.choices[0].message.tool_calls:
        messages.append(resp.choices[0].message)
        for call in resp.choices[0].message.tool_calls:
            if call.function.name == "get_call_stack":
                stack = get_call_stack(session)
                messages.append(ChatCompletionToolMessageParam(tool_call_id=call.id, role="tool",
                                                               content=json.dumps(stack, ensure_ascii=False)))
                for line in stack["stack"].splitlines():
                    m = re.search(r"([a-fA-F0-9`]+)\s+.*\+0x[0-9a-f]+", line)
                    if m:
                        mod = get_module_by_address(session, m.group(1))
                        messages.append(ChatCompletionToolMessageParam(tool_call_id="addr_auto", role="tool",
                                                                       content=json.dumps(mod, ensure_ascii=False)))
                        break
            elif call.function.name == "get_module_by_address":
                args = json.loads(call.function.arguments)
                mod = get_module_by_address(session, args["address"])
                messages.append(ChatCompletionToolMessageParam(tool_call_id=call.id, role="tool",
                                                               content=json.dumps(mod, ensure_ascii=False)))
    messages.append(ChatCompletionUserMessageParam(
        role="user", content="请根据以上所有信息，输出中文蓝屏分析报告（不超过 300 字），必须包含：模块名、版本、路径、时间戳、建议。"))
    final = client.chat.completions.create(model=MODEL, messages=messages)
    return final.choices[0].message.content or "无内容返回"