import argparse
import os
import sqlite3
from datetime import datetime, timedelta, timezone

BASE_DIR = os.path.dirname(__file__)
DB_PATH = os.path.join(BASE_DIR, "task_manager.db")


def make_db(path):
    if os.path.exists(path):
        print("seed DB already exists:", path)
        return
    conn = sqlite3.connect(path)
    cur = conn.cursor()
    cur.execute(
        """
        CREATE TABLE tasks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            created_at TEXT NOT NULL,
            task TEXT,
            status TEXT,
            assigned TEXT,
            priority TEXT,
            due_date TEXT,
            description TEXT
        )
        """
    )
    now = datetime.now(timezone.utc)
    samples = [
        {
            "task": "月次業務報告書の作成",
            "assigned": "佐藤",
            "status": "進行中",
            "priority": "高",
            "due_in_days": 3,
            "description": "1月分の売上・課題・来月の予定をまとめる。上長レビューあり。",
        },
        {
            "task": "顧客Aへの見積書作成",
            "assigned": "鈴木",
            "status": "未着手",
            "priority": "高",
            "due_in_days": 5,
            "description": "新規案件の仕様をもとに見積を作成、納期とコストを確認する。",
        },
        {
            "task": "ウェブサイトのテスト実施",
            "assigned": "田中",
            "status": "進行中",
            "priority": "中",
            "due_in_days": 7,
            "description": "リニューアル後の表示・リンク・フォーム動作をブラウザで検証。",
        },
        {
            "task": "社内研修資料の準備",
            "assigned": "高橋",
            "status": "未着手",
            "priority": "中",
            "due_in_days": 10,
            "description": "新入社員向けのセキュリティ研修のスライド作成。",
        },
        {
            "task": "在庫システムのデータ同期確認",
            "assigned": "伊藤",
            "status": "完了",
            "priority": "低",
            "due_in_days": 0,
            "description": "昨夜のバッチ処理結果を確認し、差分がないかチェック済み。",
        },
        {
            "task": "広告文のA/Bテスト準備",
            "assigned": "山田",
            "status": "進行中",
            "priority": "中",
            "due_in_days": 4,
            "description": "クリエイティブ案を2案用意し、配信グループを設定する。",
        },
        {
            "task": "顧客Bとの打ち合わせ調整",
            "assigned": None,
            "status": "未着手",
            "priority": "高",
            "due_in_days": 2,
            "description": "日程候補をメールで提示し、アジェンダを確定する。",
        },
        {
            "task": "請求書データの入力",
            "assigned": "中村",
            "status": "完了",
            "priority": "低",
            "due_in_days": -1,
            "description": "先週分の請求書を会計システムへ登録済み。",
        },
        {
            "task": "バックアップ運用の見直し",
            "assigned": "小林",
            "status": "進行中",
            "priority": "高",
            "due_in_days": 14,
            "description": "取得頻度と保管ポリシーの改定案を作成する。",
        },
        {
            "task": "顧客C向け納品物の最終チェック",
            "assigned": "加藤",
            "status": "未着手",
            "priority": "高",
            "due_in_days": 1,
            "description": "納品前に動作確認とドキュメントの整合性チェックを実施する。",
        },
    ]

    for idx, s in enumerate(samples, start=1):
        created = (now - timedelta(days=idx)).isoformat()
        due = (now + timedelta(days=s.get("due_in_days", 0))).date().isoformat()
        cur.execute(
            """
            INSERT INTO tasks (
                created_at,
                task,
                status,
                assigned,
                priority,
                due_date,
                description)
            VALUES (?,?,?,?,?,?,?)
            """,
            (
                created,
                s["task"],
                s["status"],
                s.get("assigned"),
                s["priority"],
                due,
                s["description"],
            ),
        )

    conn.commit()
    conn.close()
    print("created seed DB:", path)


def main():
    p = argparse.ArgumentParser()
    p.add_argument(
        "--force", "-f", action="store_true", help="Recreate seed DB even if it exists"
    )
    args = p.parse_args()
    if args.force and os.path.exists(DB_PATH):
        os.remove(DB_PATH)
    make_db(DB_PATH)


if __name__ == "__main__":
    main()
