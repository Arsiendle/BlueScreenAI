from config import API_KEY, BASE_URL, MODEL
from openai import OpenAI
import json

client = OpenAI(api_key=API_KEY, base_url=BASE_URL)

def generate_report(analyze_output: str, kv_output: str, lm_output: str) -> str:
    prompt = f"""
你是 Windows 蓝屏分析专家，请根据以下 WinDbg 输出，生成一份**中文蓝屏分析报告**，包含：
1. 蓝屏代码和含义
2. 崩溃原因简述
3. 可能的责任模块
4. 用户处理建议

---  
!analyze -v 输出：
{analyze_output}

kv 输出：
{kv_output}

lm 输出：
{lm_output}
---  
请用中文、简洁、专业地输出报告。
"""
    response = client.chat.completions.create(
        model=MODEL,
        messages=[{"role": "user", "content": prompt}]
    )
    return response.choices[0].message.content or "无内容返回"