from fastmcp import FastMCP
from queue import Queue, Empty
import subprocess
import threading
import time
import re
from ai_report import generate_report
import os

mcp = FastMCP("WinDbg MCP Server")
CDB_PATH = r"C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\cdb.exe"
# 国内镜像符号服务器
SYMPATH = rf'srv*{os.path.join(os.path.dirname(__file__), "symcache")}*https://mirrors.tuna.tsinghua.edu.cn/windows/msdl/download/symbols'

class CdbSession:
    def _read_output(self):
        for line in self.proc.stdout:
            self.output_queue.put(line)

    def send_command(self, cmd: str, timeout: float = 30.0) -> str:
        print(f"--> SEND: {cmd!r}")
        self.proc.stdin.write(cmd + '\n')
        self.proc.stdin.flush()

        lines, start, kd_seen, last_read = [], time.time(), False, time.time()
        while True:
            try:
                line = self.output_queue.get(timeout=1.0)
                lines.append(line)
                print(f"    LINE: {line.rstrip()!r}")
                last_read = time.time()

                # 见到第一个 kd> 才标记
                if re.match(r'^\d+\s*:\s*kd>\s*$', line.strip()):
                    kd_seen = True

            except Empty:
                # 1. 见过 kd> 后 1 秒静默 → 正常结束，不标 Timeout
                if kd_seen and time.time() - last_read > 1.0:
                    break
                # 2. 真正超时 → 标 Timeout
                if time.time() - start > timeout:
                    lines.append('[Timeout]\n')
                    break
                # ✅ 正常结束（静默）→ 不追加 Timeout
                break
                # 3. 否则继续等

        raw = ''.join(lines)
        print(f"<-- RECV: {raw!r}")
        return raw

    def shutdown(self):
        self.proc.stdin.write('q\n')
        self.proc.stdin.flush()
        time.sleep(1)
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
        self.proc.stdin.write(f'.sympath {SYMPATH}\n')
        self.proc.stdin.flush()
        time.sleep(2)

SESSION = None

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