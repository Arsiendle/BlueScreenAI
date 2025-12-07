from config import API_KEY, BASE_URL, MODEL
from openai import OpenAI
import json, re

client = OpenAI(api_key=API_KEY, base_url=BASE_URL)

def generate_report(analyze_output: str, kv_output: str, lm_output: str) -> str:
    # 从lm输出提取第三方驱动（不依赖符号）
    drivers = []
    for line in lm_output.splitlines():
        # 匹配：start end module timestamp path
        m = re.match(r'^[a-f0-9`]{16}\s+[a-f0-9`]{16}\s+(\w+)\s+([a-f0-9`]{8})\s+(.+)', line, re.IGNORECASE)
        if m:
            mod, timestamp, path = m.groups()
            mod_lower = mod.lower()
            # 排除系统模块
            if mod_lower not in {'nt', 'hal', 'kd', 'pci', 'tcpip', 'ntfs', 'wdf01000', 'verifier', 'ntkrnlmp', 'wdi', 'pdc'} and \
               not mod_lower.startswith('wdf') and not path.startswith('C:\\Windows\\System32\\DriverStore\\FileRepository\\'):
                drivers.append(f"{mod} (时间戳: {timestamp}, 路径: {path.strip()})")
    
    driver_section = "\n".join(drivers[:10]) if drivers else "未加载明显的第三方驱动"
    
    prompt = f"""你是Windows蓝屏分析专家。根据以下信息生成**精确到驱动**的报告。

**BugCheck分析**：
{analyze_output}

**调用栈**：
{kv_output}

**第三方驱动列表**：
{driver_section}

**必须遵守的规则**：
1. 从驱动列表中**明确选出最可疑的1-3个驱动**，不能泛泛而谈
2. 提供**具体的驱动更新/卸载命令**，如：`pnputil /delete-driver oemxxx.inf /uninstall`
3. 报告包含"【责任模块】"和"【立即操作】"章节
4. 优先级：显卡 > 网卡/声卡 > 存储 > 安全软件 > 其他

请用中文输出报告。"""

    response = client.chat.completions.create(
        model=MODEL,
        messages=[{"role": "user", "content": prompt}]
    )
    return response.choices[0].message.content or "无内容返回"