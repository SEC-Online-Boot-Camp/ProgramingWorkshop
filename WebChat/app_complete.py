"""
メッセージ管理アプリケーション

このファイルはFlaskを使ったWebアプリケーションのメインファイルです。
メッセージの一覧表示、作成、編集、削除の機能を提供します。
"""

import os
import sqlite3
from datetime import datetime, timezone

from flask import Flask, abort, redirect, render_template, request

from create_db import make_db


def _ensure_db(db_path):
    """メッセージテーブルが無ければ作成する"""
    # make_db はDBファイルが無ければ作成するが、既存ファイルの空状態は考慮しないため
    connection = sqlite3.connect(db_path)
    connection.execute(
        """
        CREATE TABLE IF NOT EXISTS messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            created_at TEXT NOT NULL,
            message TEXT,
            status TEXT,
            assigned TEXT,
            priority TEXT,
            due_date TEXT,
            description TEXT
        )
        """
    )
    connection.commit()
    connection.close()


# ファイルのあるディレクトリを取得
BASE_DIR = os.path.dirname(__file__)

# データベースファイルのパス（テスト時はTEST_DB_PATHを優先）
DB_PATH = os.environ.get("TEST_DB_PATH") or os.path.join(BASE_DIR, "webchat.db")

# メッセージの状態として許可される値
ALLOWED_STATUS = ("未着手", "進行中", "保留", "完了")


def query_db(sql, params=(), commit=False):
    """
    データベースに対してSQLを実行する

    引数:
        sql: 実行するSQL文
        params: SQLのパラメータ（?に入る値）
        commit: Trueの場合、変更を保存する（INSERT, UPDATE, DELETE用）

    戻り値:
        commit=False: 取得した行のリスト
        commit=True: 変更された行数
    """
    # 実行時に TEST_DB_PATH を確認（テスト環境対応）
    db_path = os.environ.get("TEST_DB_PATH") or os.path.join(BASE_DIR, "webchat.db")

    # DBが存在しない場合はシードDBを生成しておく
    if not os.path.exists(db_path):
        make_db(db_path)
    # DBファイルが存在しても messages テーブルが無いケースに備えて作成
    _ensure_db(db_path)
    connection = sqlite3.connect(db_path)
    connection.row_factory = sqlite3.Row  # 結果を辞書形式で取得できるようにする
    cursor = connection.cursor()
    cursor.execute(sql, params)

    if commit:
        # INSERT, UPDATE, DELETEの場合
        connection.commit()
        affected_rows = cursor.rowcount
        connection.close()
        return affected_rows

    # SELECTの場合
    rows = cursor.fetchall()
    connection.close()
    return rows


def format_date(date_string):
    """
    日付文字列をYYYY-MM-DD形式に変換する

    引数:
        date_string: ISO形式の日付文字列

    戻り値:
        YYYY-MM-DD形式の文字列、または変換できない場合は元の文字列
    """
    if not date_string:
        return ""
    try:
        dt = datetime.fromisoformat(date_string)
        return dt.date().isoformat()
    except (ValueError, TypeError):
        return date_string


def create_app():
    """Flaskアプリケーションを作成する"""
    app = Flask(
        __name__,
        template_folder=os.path.join(BASE_DIR, "templates"),
        static_folder=os.path.join(BASE_DIR, "static"),
    )

    # ===== トップページ =====
    @app.get("/")
    def index():
        """トップページ（メッセージ一覧にリダイレクト）"""
        return redirect("/messages")

    # ==========================================================================
    # 演習01: メッセージ一覧取得（Read）
    # --------------------------------------------------------------------------
    # 学習ポイント: ルーティングの設定
    # - @app.get("/01_ToDo") に正しいURLパスを設定してください
    # - ヒント: メッセージ一覧のURLは "/messages" です
    # ==========================================================================
    # TODO: 正しいURLパスを設定してください
    @app.get("/messages")
    def message_list():
        """メッセージ一覧取得"""

        rows = query_db("SELECT * FROM messages ORDER BY id ASC")

        # テンプレートに渡すためのリストを作成
        messages = []
        for row in rows:
            message = {
                "id": row["id"],
                "created_at": format_date(row["created_at"]),
                "message": row["message"],
                "status": row["status"],
                "assigned": row["assigned"] or "",
                "priority": row["priority"] or "中",
                "due_date": row["due_date"] or "",
                "description": row["description"] or "",
            }
            messages.append(message)

        return render_template("messages.html", messages=messages)

    # ===== タスク作成フォームを表示 =====
    @app.get("/messages/new")
    def new_message_form():
        """新規メッセージ作成フォームを表示する"""
        return render_template("form.html")

    # ==========================================================================
    # 演習02: メッセージ作成（Create）
    # --------------------------------------------------------------------------
    # 学習ポイント: 入力値のチェック（バリデーション）
    # - message が空の場合は 400 エラーを返す
    # - 状態が許可された値でない場合は 400 エラーを返す
    # - ヒント: abort(400, "エラーメッセージ") でエラーを返せます
    # ==========================================================================
    @app.post("/messages/create")
    def create_message():
        """メッセージ作成"""

        # メッセージ本文を取得
        message = request.form.get("message")

        # TODO: message が空の場合は 400 エラーを返してください
        # ヒント: if not message: で空かどうか判定できます
        if not message:
            abort(400, "messageは必須です")

        # 状態を取得（デフォルトは「未着手」）
        status = request.form.get("status") or "未着手"

        # TODO: 状態が ALLOWED_STATUS に含まれていない場合は 400 エラーを返してください
        # ヒント: if status not in ALLOWED_STATUS: で判定できます
        if status not in ALLOWED_STATUS:
            abort(400, "無効な状態です")

        # その他のフィールド
        assigned = request.form.get("assigned") or ""
        priority = request.form.get("priority") or "中"
        due_date = request.form.get("due_date") or ""
        description = request.form.get("description") or ""
        created_at = datetime.now(timezone.utc).isoformat()

        # データベースに保存
        query_db(
            """
            INSERT INTO messages (
                created_at,
                message,
                status,
                assigned,
                priority,
                due_date,
                description
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (
                created_at,
                message,
                status,
                assigned,
                priority,
                due_date,
                description,
            ),
            commit=True,
        )

        return redirect("/messages")

    # ==========================================================================
    # 演習03: メッセージ削除（Delete）
    # --------------------------------------------------------------------------
    # 学習ポイント: SQLの書き方（DELETE文）
    # - DELETE FROM テーブル名 WHERE 条件
    # - ヒント: message_id を使って特定のメッセージを削除します
    # ==========================================================================
    @app.post("/messages/delete/<int:message_id>")
    def delete_message(message_id):
        """メッセージ削除"""

        # データベースからタスクを削除
        affected_rows = query_db(
            # TODO: DELETE文を書いてください
            "DELETE FROM messages WHERE id = ?",
            (message_id,),
            commit=True,
        )

        # メッセージが存在しなかった場合は404エラー
        if affected_rows == 0:
            abort(404, "メッセージが見つかりません")

        return redirect("/messages")

    # ==========================================================================
    # 演習04: メッセージ更新（Update）
    # --------------------------------------------------------------------------
    # 学習ポイント: 演習01〜03の組み合わせ
    # - ルーティング: 正しいURLパスを設定
    # - バリデーション: 状態のチェック
    # - SQL: UPDATE文の作成
    # ==========================================================================

    # ===== メッセージ編集フォーム =====
    @app.get("/messages/edit/<int:message_id>")
    def edit_message_form(message_id):
        """メッセージ編集"""
        # ToDo: 指定されたIDのメッセージを取得
        rows = query_db(
            "SELECT * FROM messages WHERE id = ?",
            (message_id,),
        )
        # ToDo: メッセージが存在しない場合は404エラー
        # ヒント: if not rows: で判定できます
        if not rows:
            abort(404, "メッセージが見つかりません")

        row = rows[0]
        # テンプレートに渡すメッセージ情報
        message_item = {
            "id": row["id"],
            "message": row["message"],
            "assigned": row["assigned"] or "",
            "status": row["status"],
            "priority": row["priority"] or "中",
            "due_date": row["due_date"] or "",
            "description": row["description"] or "",
        }

        return render_template(
            "form.html",
            form_action=f"/messages/update/{message_id}",
            message_item=message_item,
        )

    # ===== メッセージ更新を実行 =====
    # TODO: 正しいURLパスを設定してください（例: "/messages/update/<int:message_id>"）
    @app.post("/messages/update/<int:message_id>")
    def update_message(message_id):
        """メッセージ更新"""
        # 更新するフィールドと値を収集
        fields = []
        values = []

        # メッセージ本文
        message = request.form.get("message")
        if message is not None:
            fields.append("message = ?")
            values.append(message)

        # 状態
        status = request.form.get("status")
        if status is not None:
            # TODO: 状態が ALLOWED_STATUS に含まれていない場合は 400 エラーを返してください
            if status not in ALLOWED_STATUS:
                abort(400, "無効な状態です")
            fields.append("status = ?")
            values.append(status)

        # 担当者
        assigned = request.form.get("assigned")
        if assigned is not None:
            fields.append("assigned = ?")
            values.append(assigned)

        # 優先度
        priority = request.form.get("priority")
        if priority is not None:
            fields.append("priority = ?")
            values.append(priority)

        # 期限
        due_date = request.form.get("due_date")
        if due_date is not None:
            fields.append("due_date = ?")
            values.append(due_date)

        # 詳細
        description = request.form.get("description")
        if description is not None:
            fields.append("description = ?")
            values.append(description)

        # 更新するフィールドがない場合はエラー
        if not fields:
            abort(400, "更新するフィールドがありません")

        # SQLを組み立てて実行
        values.append(message_id)
        # TODO: UPDATE文を書いてください
        sql = f"UPDATE messages SET {', '.join(fields)} WHERE id = ?"
        affected_rows = query_db(sql, tuple(values), commit=True)

        # ToDo: メッセージが存在しなかった場合は404エラー
        # ヒント: affected_rows を使って判定できます
        if affected_rows == 0:
            abort(404, "メッセージが見つかりません")

        return redirect("/messages")

    return app


# このファイルを直接実行した場合の処理
if __name__ == "__main__":
    app = create_app()
    app.run(debug=True)
