# ai_agent.py  第3轮-无新信息兜底版
from config import API_KEY, BASE_URL, MODEL
from openai import OpenAI
from openai.types.chat import ChatCompletionToolMessageParam
import json, re, hashlib
from typing import Any

client = OpenAI(api_key=API_KEY, base_url=BASE_URL)

# ---------- 0. 全局去重表 ----------
_executed = set()

# ---------- 0.1 兜底逻辑 ----------
_prev_output_hash = None
_no_new_info_count = 0
MAX_NO_NEW_INFO = 3          # 连续3轮无新信息就兜底

# ---------- 1. 重型命令池 ----------
HEAVY_CMDS = {".bugreport", "!devnode", "!drvobj", "!poaction", "!vm"}

# ---------- 2. 称重函数 ----------
def _dump_level(session: Any) -> str:
    raw = session.send_command("vertarget", timeout=10.0)
    return "full" if raw.count("\n") > 200 else "triage"

# ---------- 3. 折叠 STACK_TEXT ----------
def _collapse_stack(text: str) -> str:
    return re.sub(
        r"(?s)(STACK_TEXT:.*?)(?=^\s*$|\Z)",
        lambda m: "\n".join(m.group(1).splitlines()[:7]) + "\n  ...<折叠>...\n",
        text,
        flags=re.MULTILINE
    )

# ---------- 4. 去重 + 动态过滤 ----------
def _send_command_dedup(session: Any, cmd: str) -> str:
    key = re.sub(r'\s+', ' ', cmd.split(';')[0].strip().lower())
    if key in _executed:
        return f"[已执行过，跳过: {cmd}]"
    _executed.add(key)

    if not hasattr(session, "_dump_level"):
        session._dump_level = _dump_level(session)
    if session._dump_level == "triage" and key in HEAVY_CMDS:
        return f"[当前为内核小转储，命令 '{cmd}' 不可用]"

    timeout = 120.0 if key == ".reload" else 30.0
    raw = session.send_command(cmd, timeout=timeout)
    return _collapse_stack(raw)

# ---------- 5. 主循环 ----------
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

    global _prev_output_hash, _no_new_info_count

    while True:
        resp = client.chat.completions.create(model=MODEL, messages=messages, tools=tools, tool_choice="auto")
        assistant_msg = resp.choices[0].message

        # 如果 AI 已输出结论，直接返回
        if assistant_msg.content and "【结论】" in assistant_msg.content:
            return "\033[92m" + assistant_msg.content + "\033[0m"

        # 无工具调用 → 强制兜底结论
        if not assistant_msg.tool_calls:
            messages.append({
                "role": "user",
                "content": "请基于以上所有信息，立即生成中文蓝屏分析报告，以“【结论】”开头。"
            })
            resp = client.chat.completions.create(model=MODEL, messages=messages, tools=tools, tool_choice="none")
            return "\033[92m" + (resp.choices[0].message.content or "无内容返回") + "\033[0m"

        # 正常工具调用流程
        messages.append({
            "role": assistant_msg.role,
            "content": assistant_msg.content or "",
            "tool_calls": [
                {"id": tc.id, "type": tc.type,
                 "function": {"name": tc.function.name, "arguments": tc.function.arguments}}
                for tc in assistant_msg.tool_calls
            ]
        })

        # 收集本轮全部输出，用于去重判断
        round_outputs = []
        for tc in assistant_msg.tool_calls:
            cmd = json.loads(tc.function.arguments)["command"]
            output = _send_command_dedup(session, cmd)
            round_outputs.append(output)
            messages.append(ChatCompletionToolMessageParam(
                tool_call_id=tc.id,
                role="tool",
                content=json.dumps({"status": "success", "output": output}, ensure_ascii=False)
            ))

        # 无新信息兜底判断
        round_hash = hashlib.md5("".join(round_outputs).encode()).hexdigest()
        if round_hash == _prev_output_hash:
            _no_new_info_count += 1
            if _no_new_info_count >= MAX_NO_NEW_INFO:
                messages.append({
                    "role": "user",
                    "content": "连续多轮未获取新信息，请基于已有信息立即生成中文蓝屏分析报告，以“【结论】”开头。"
                })
                resp = client.chat.completions.create(model=MODEL, messages=messages, tools=tools, tool_choice="none")
                return "\033[92m" + (resp.choices[0].message.content or "无内容返回") + "\033[0m"
        else:
            _no_new_info_count = 0
        _prev_output_hash = round_hash