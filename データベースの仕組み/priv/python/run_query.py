"""読み取り専用のデータベースで、1文のSELECTだけを実行し、結果を1行のJSONで標準出力に書き出す。

使い方: python run_query.py <データベースファイル> <入力JSONファイル>

入力JSON:
    {"sql": "SELECT文（1文だけ）", "params": ["? に値として渡す値", ...]}

出力JSON:
    {"columns": [...], "rows": [...], "truncated": true | false, "error": "メッセージ" | null}

「考えてみよう」のSQLインジェクションの体験用。受講者が入力した文字列が、そのままSQLの
一部になる（危険な作りの）場合があるので、次の守りを重ねている。

  * データベースを読み取り専用で開く（mode=ro）、PRAGMA query_only = ON
  * 実行できる操作をSELECT（と、その中で読む表・関数）だけに限る（オーソライザ）
  * sqlite3 の execute は1文しか実行できない（複数の文はエラーになる）
  * 実行は3秒で打ち切る、結果は200行まで
  * 外部への通信はしない
"""

import json
import sqlite3
import sys
import time
from pathlib import Path

MAX_ROWS = 200
TIME_LIMIT_SEC = 3.0

# SELECT の実行に必要な操作だけを許す。ほかの操作（INSERT・UPDATE・DELETE・DROP・ATTACH・PRAGMA など）は拒否する
ALLOWED_ACTIONS = {
    sqlite3.SQLITE_SELECT,
    sqlite3.SQLITE_READ,
    sqlite3.SQLITE_FUNCTION,
    getattr(sqlite3, "SQLITE_RECURSIVE", None),
}


def authorizer(action, *_args):
    return sqlite3.SQLITE_OK if action in ALLOWED_ACTIONS else sqlite3.SQLITE_DENY


def fail(message):
    return {"columns": [], "rows": [], "truncated": False, "error": message}


def run(db_path, request):
    uri = Path(db_path).resolve().as_uri() + "?mode=ro"
    conn = sqlite3.connect(uri, uri=True)
    try:
        conn.execute("PRAGMA query_only = ON")
        conn.set_authorizer(authorizer)
        deadline = time.monotonic() + TIME_LIMIT_SEC
        conn.set_progress_handler(lambda: 1 if time.monotonic() > deadline else 0, 10_000)

        try:
            cur = conn.execute(request["sql"], request.get("params", []))
            rows = cur.fetchmany(MAX_ROWS + 1)
            return {
                "columns": [d[0] for d in cur.description] if cur.description else [],
                "rows": [list(r) for r in rows[:MAX_ROWS]],
                "truncated": len(rows) > MAX_ROWS,
                "error": None,
            }
        except sqlite3.Error as e:
            message = str(e)
            if message == "interrupted":
                message = f"interrupted（{TIME_LIMIT_SEC:g}秒以内に終わらなかったため中断しました）"
            return fail(message)
    finally:
        conn.close()


def main():
    db_path, input_path = sys.argv[1], sys.argv[2]
    with open(input_path, encoding="utf-8") as f:
        request = json.load(f)

    print(json.dumps(run(db_path, request), ensure_ascii=False, default=str))


if __name__ == "__main__":
    main()
