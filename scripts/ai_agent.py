# ai_agent.py  一次性修复版
from config import API_KEY, BASE_URL, MODEL
from openai import OpenAI
from openai.types.chat import ChatCompletionToolMessageParam
import json, re
from typing import Any

client = OpenAI(api_key=API_KEY, base_url=BASE_URL)

# ---------- 1. 全局去重表 ----------
_executed = set()

# ---------- 2. 折叠 STACK_TEXT 到最近 5 行 ----------
def _collapse_stack(text: str) -> str:
    return re.sub(
        r"(?s)(STACK_TEXT:.*?)(?=^\s*$|\Z)",
        lambda m: "\n".join(m.group(1).splitlines()[:7]) + "\n  ...<折叠>...\n",
        text,
        flags=re.MULTILINE
    )

# ---------- 3. 去重执行 ----------
def _send_command_dedup(session: Any, cmd: str) -> str:
    # 用命令主干做 key，防止 .symfix; .reload 重复
    key = re.sub(r'\s+', ' ', cmd.split(';')[0].strip().lower())
    if key in _executed:
        return f"[已执行过，跳过: {cmd}]"
    _executed.add(key)
    # 符号下载超时放大
    timeout = 120.0 if key == '.reload' else 30.0
    raw = session.send_command(cmd, timeout=timeout)
    # 统一折叠
    return _collapse_stack(raw)

def ai_sampling_loop_with_session(session: Any) -> str:
    tools = [{
        "type": "function",
        "function": {
            "name": "run_windbg_command",
            "description": "向 WinDbg 发送任意命令并返回输出",
            "parameters": {
                "type": "object",
                "properties": {"command": {"type": "string"}},
                "required": ["command"]
            }
        }
    }]

    init_output = session.send_command("!analyze -v", timeout=60.0)
    init_output = _collapse_stack(init_output)

    # 若符号错误，先修复再重跑
    if "WRONG_SYMBOLS" in init_output:
        session.send_command(".symfix", timeout=30.0)
        session.send_command(".reload", timeout=120.0)
        init_output = session.send_command("!analyze -v", timeout=60.0)
        init_output = _collapse_stack(init_output)

    messages = [
        {"role": "system", "content": (
            "你是 WinDbg 专家。每轮先用一句中文说明“下一步打算查什么”，再调用工具；"
            "直到确定蓝屏根因，最后必须输出中文报告并以“【结论】”开头。"
        )},
        {"role": "user", "content": "请开始分析"},
        {"role": "assistant", "tool_calls": [{
            "id": "init_call",
            "type": "function",
            "function": {"name": "run_windbg_command", "arguments": json.dumps({"command": "!analyze -v"})}
        }]},
        {"role": "tool", "tool_call_id": "init_call",
         "content": json.dumps({"status": "success", "output": init_output}, ensure_ascii=False)}
    ]

    while True:
        resp = client.chat.completions.create(model=MODEL, messages=messages, tools=tools, tool_choice="auto")
        assistant_msg = resp.choices[0].message

        if assistant_msg.content and "【结论】" in assistant_msg.content:
            return "\033[92m" + assistant_msg.content + "\033[0m"

        if not assistant_msg.tool_calls:
            return assistant_msg.content or "无内容返回"

        messages.append({
            "role": assistant_msg.role,
            "content": assistant_msg.content or "",
            "tool_calls": [
                {"id": tc.id, "type": tc.type,
                 "function": {"name": tc.function.name, "arguments": tc.function.arguments}}
                for tc in assistant_msg.tool_calls
            ]
        })
        for tc in assistant_msg.tool_calls:
            cmd = json.loads(tc.function.arguments)["command"]
            output = _send_command_dedup(session, cmd)
            messages.append(ChatCompletionToolMessageParam(
                tool_call_id=tc.id,
                role="tool",
                content=json.dumps({"status": "success", "output": output}, ensure_ascii=False)
            ))