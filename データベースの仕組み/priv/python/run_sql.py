"""受講者が書いたSQLをSQLiteで実行し、結果を1行のJSONで標準出力に書き出す。

使い方: python run_sql.py <データベースファイル> <入力JSONファイル>

入力JSON:
    {"sql": "受講者のSQL（複数文可）", "extras": ["アプリ側で使う確認用のSELECT", ...],
     "track": ["1文ごとに調べる確認用のSELECT", ...]}

出力JSON:
    {"results": [...], "error": {...} | null, "extras": [...], "tracked": [true | false, ...]}

受講者のSQLは1文ずつ実行し、エラーが出た文で止める。extras は受講者のSQLの
あとに必ず実行し、テーブルの表示や課題の達成判定に使う。
track は受講者のSQLを1文実行するたびに調べ、行が返ったことが一度でもあれば true にする
（「INSERTしてすぐDELETEした」ように、最後の状態からは分からない途中の状態を知るため）。
"""

import json
import re
import sqlite3
import sys
import time

MAX_ROWS = 200
TIME_LIMIT_SEC = 3.0


def is_blank(stmt):
    """コメントと空白しかない文かどうか。"""
    body = re.sub(r"/\*.*?\*/", "", stmt, flags=re.S)
    body = re.sub(r"--[^\n]*", "", body)
    return body.strip() in ("", ";")


def split_statements(sql):
    """セミコロンで文を区切る。文字列やコメントの中のセミコロンでは区切らない。"""
    stmts, start = [], 0
    for i, ch in enumerate(sql):
        if ch == ";" and sqlite3.complete_statement(sql[start : i + 1]):
            stmts.append(sql[start : i + 1])
            start = i + 1
    stmts.append(sql[start:])
    return [s.strip() for s in stmts if not is_blank(s)]


def label(stmt):
    """結果の見出しに使う文。先頭のコメント行は除く。"""
    lines = stmt.splitlines()
    while lines and lines[0].strip().startswith("--"):
        lines.pop(0)
    return "\n".join(lines).strip()


def execute(conn, stmt):
    cur = conn.execute(stmt)
    if cur.description:
        rows = cur.fetchmany(MAX_ROWS + 1)
        return {
            "type": "rows",
            "columns": [d[0] for d in cur.description],
            "rows": [list(r) for r in rows[:MAX_ROWS]],
            "truncated": len(rows) > MAX_ROWS,
        }
    return {"type": "change", "count": cur.rowcount}


def main():
    db_path, input_path = sys.argv[1], sys.argv[2]
    with open(input_path, encoding="utf-8") as f:
        request = json.load(f)

    # isolation_level=None で1文ごとに確定させる（実行のたびに別プロセスなので、
    # 確定しないまま終わると変更が消えてしまう）
    conn = sqlite3.connect(db_path, isolation_level=None)
    deadline = time.monotonic() + TIME_LIMIT_SEC
    conn.set_progress_handler(lambda: 1 if time.monotonic() > deadline else 0, 10_000)

    track = request.get("track", [])
    tracked = [False] * len(track)

    def update_tracked():
        for i, query in enumerate(track):
            if tracked[i]:
                continue
            try:
                tracked[i] = conn.execute(query).fetchone() is not None
            except sqlite3.Error:
                pass

    results, error = [], None
    for stmt in split_statements(request.get("sql", "")):
        try:
            results.append({"sql": label(stmt), **execute(conn, stmt)})
            update_tracked()
        except sqlite3.Error as e:
            message = str(e)
            if message == "interrupted":
                message = f"interrupted（{TIME_LIMIT_SEC:g}秒以内に終わらなかったため中断しました）"
            error = {"sql": label(stmt), "message": message}
            break

    extras = []
    for stmt in request.get("extras", []):
        try:
            extras.append(execute(conn, stmt))
        except sqlite3.Error:
            extras.append(None)

    conn.close()
    print(
        json.dumps(
            {"results": results, "error": error, "extras": extras, "tracked": tracked},
            ensure_ascii=False,
            default=str,
        )
    )


if __name__ == "__main__":
    main()
