from config import API_KEY, BASE_URL, MODEL
from openai import OpenAI
from openai.types.chat import ChatCompletionToolMessageParam
import json
from typing import Any

client = OpenAI(api_key=API_KEY, base_url=BASE_URL)

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
    messages = [
        {"role": "system", "content": (
            "你是 WinDbg 专家。可根据 dump 信息随时调用工具补充数据，"
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
        resp = client.chat.completions.create(
            model=MODEL,
            messages=messages,
            tools=tools,
            tool_choice="auto"          # ① 不强制
        )
        assistant_msg = resp.choices[0].message

        # ② AI 主动说停 → 立即返回
        if assistant_msg.content and "【结论】" in assistant_msg.content:
            return assistant_msg.content

        # ③ 无工具调用也停（兜底）
        if not assistant_msg.tool_calls:
            return assistant_msg.content or "无内容返回"

        # ④ 继续执行工具调用
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
            output = session.send_command(cmd, timeout=30.0)
            messages.append(ChatCompletionToolMessageParam(
                tool_call_id=tc.id,
                role="tool",
                content=json.dumps({"status": "success", "output": output}, ensure_ascii=False)
        ))