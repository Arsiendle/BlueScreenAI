import os
from dotenv import load_dotenv

load_dotenv()  # 自动加载 .env（若存在）

API_KEY     = os.getenv("API_KEY", "")        # 必填
BASE_URL    = os.getenv("BASE_URL", "https://api.deepseek.com/v1")
MODEL       = os.getenv("MODEL", "deepseek-chat")

if not API_KEY:
    raise RuntimeError(
        "【缺少 API_KEY】请在当前目录新建 .env 文件，或执行：\n"
        "Linux/Mac: export API_KEY=sk-xxx\n"
        "Windows:   set API_KEY=sk-xxx"
    )