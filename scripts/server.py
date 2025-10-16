from fastmcp import FastMCP
import subprocess
import threading
import time
from queue import Queue, Empty
from ai_report import generate_report

mcp = FastMCP("WinDbg MCP Server")
CDB_PATH = r"C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\cdb.exe"
# CDB_PATH = r"WinDbg\cdb.exe"

class CdbSession:
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
        self.send_command('.symfix')
        self.send_command('.reload')

    def _read_output(self):
        for line in self.proc.stdout:
            self.output_queue.put(line)

    def send_command(self, cmd: str, timeout: float = 5.0) -> str:
        self.proc.stdin.write(cmd + '\n')
        self.proc.stdin.flush()

        lines = []
        start = time.time()
        while True:
            try:
                line = self.output_queue.get(timeout=0.5)
                lines.append(line)
                if line.strip().endswith('kd>'):
                    break
                if time.time() - start > timeout:
                    lines.append('[Timeout]\n')
                    break
            except Empty:
                break
        return ''.join(lines)

    def shutdown(self):
        self.send_command('q')
        self.proc.terminate()
        self.proc.wait()

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