from server import CdbSession
from ai_agent import ai_sampling_loop_with_session

def main():
    dump_path = input("📁 拖入 dump 文件：").strip().strip('"')
    session = CdbSession(dump_path)
    print("🧠 AI 正在主动采样，请稍候...")
    report = ai_sampling_loop_with_session(session)
    print("\n📄 AI 主动分析报告：\n")
    print(report)
    input("\n按回车退出...")
    session.shutdown()

if __name__ == "__main__":
    main()