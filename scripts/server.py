from fastmcp import FastMCP
from queue import Queue, Empty
import subprocess
import threading
import time
from ai_report import generate_report
import os

mcp = FastMCP("WinDbg MCP Server")
# CDB_PATH = r"C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\cdb.exe"
# 放在文件头部，CDB_PATH 下方
CDB_PATH = r"WinDbg\cdb.exe"
SYMBOL_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'symbols')
os.makedirs(SYMBOL_DIR, exist_ok=True)   # 自动创建

class CdbSession:
    def _read_output(self):
        for line in self.proc.stdout:
            self.output_queue.put(line)

    def send_command(self, cmd: str, timeout: float = 30.0) -> str:
        print(f"--> SEND: {cmd!r}")
        self.proc.stdin.write(cmd + '\n')
        self.proc.stdin.flush()

        lines = []
        start = time.time()

        while True:
            try:
                line = self.output_queue.get(timeout=1.0)
                lines.append(line)
                print(f"    LINE: {line.rstrip()!r}")

                if 'Followup:' in line:
                    break
                if time.time() - start > timeout:
                    lines.append('[Timeout]\n')
                    break
            except Empty:
                continue

        raw = ''.join(lines)
        print(f"<-- RECV: {raw!r}")
        return raw

    def shutdown(self):
        # 静默退出，不打印卸载日志
        self.proc.stdin.write('q\n')
        self.proc.stdin.flush()
        time.sleep(1)  # 给 1 秒退出
        self.proc.terminate()
        self.proc.wait()

    def __init__(self, dump_path: str):
        self.proc = subprocess.Popen(
            [CDB_PATH, '-z', dump_path],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1
        )
        assert self.proc.stdin is not None
        assert self.proc.stdout is not None

        self.output_queue = Queue()
        self._reader_thread = threading.Thread(target=self._read_output, daemon=True)
        self._reader_thread.start()

        time.sleep(1)
        # # 只设路径，不等提示符
        # self.proc.stdin.write('.symfix\n')
        # self.proc.stdin.flush()
        # time.sleep(2)  # 给 2 秒生效
        # # 直接返回，不等 kd>
        # 只设本地缓存，不等提示符
        self.proc.stdin.write(f'.sympath cache*{SYMBOL_DIR}\n')
        self.proc.stdin.flush()
        time.sleep(2)        # 给 2 秒生效
        # 不再发 .reload /f，让 !analyze -v 自己按需拉符号

# ---------- 全局会话 ----------
SESSION = None

# ---------- MCP 工具 ----------
@mcp.tool()
def init_dump_session(dump_path: str):
    global SESSION
    if SESSION:
        return {"status": "error", "message": "Session already started"}
    try:
        SESSION = CdbSession(dump_path)
        return {"status": "success", "message": f"Session started for {dump_path}"}
    except Exception as e:
        return {"status": "error", "message": str(e)}

@mcp.tool()
def run_windbg_command(command: str):
    global SESSION
    if not SESSION:
        return {"status": "error", "message": "No session"}
    try:
        output = SESSION.send_command(command)
        return {"status": "success", "command": command, "output": output[:5000]}
    except Exception as e:
        return {"status": "error", "message": str(e)}

@mcp.tool()
def shutdown_session():
    global SESSION
    if SESSION:
        SESSION.shutdown()
        SESSION = None
        return {"status": "success", "message": "Session closed"}
    return {"status": "error", "message": "No session running"}

@mcp.tool()
def generate_ai_report() -> dict:
    global SESSION
    if not SESSION:
        return {"status": "error", "message": "No session"}
    try:
        analyze = SESSION.send_command("!analyze -v")
        kv = SESSION.send_command("kv")
        lm = SESSION.send_command("lm")
        report = generate_report(analyze, kv, lm)
        return {"status": "success", "report": report}
    except Exception as e:
        return {"status": "error", "message": str(e)}