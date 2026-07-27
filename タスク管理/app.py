"""
タスク管理アプリケーション

このファイルはFlaskを使ったWebアプリケーションのメインファイルです。
タスクの一覧表示、作成、編集、削除の機能を提供します。
"""

import os
import sqlite3
from datetime import datetime, timezone

from flask import Flask, abort, redirect, render_template, request

# ファイルのあるディレクトリを取得
BASE_DIR = os.path.dirname(__file__)

# データベースファイルのパス（テスト時はTEST_DB_PATHを優先）
DB_PATH = os.environ.get("TEST_DB_PATH") or os.path.join(BASE_DIR, "task_manager.db")

# タスクの状態として許可される値
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
    db_path = os.environ.get("TEST_DB_PATH") or os.path.join(
        BASE_DIR, "task_manager.db"
    )
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
        """トップページ（タスク一覧にリダイレクト）"""
        return redirect("/tasks")

    # ==========================================================================
    # 演習01: タスク一覧取得（Read）
    # --------------------------------------------------------------------------
    # 学習ポイント: ルーティングの設定
    # - @app.get("/01_ToDo") に正しいURLパスを設定してください
    # - ヒント: タスク一覧のURLは "/tasks" です
    # ==========================================================================
    # TODO: 正しいURLパスを設定してください
    @app.get("/01_ToDo")
    def task_list():
        """タスク一覧取得"""

        rows = query_db("SELECT * FROM tasks")

        # テンプレートに渡すためのリストを作成
        tasks = []
        for row in rows:
            task = {
                "id": row["id"],
                "created_at": format_date(row["created_at"]),
                "task": row["task"],
                "status": row["status"],
                "assigned": row["assigned"] or "",
                "priority": row["priority"] or "中",
                "due_date": row["due_date"] or "",
                "description": row["description"] or "",
            }
            tasks.append(task)

        return render_template("tasks.html", tasks=tasks)

    # ===== タスク作成フォームを表示 =====
    @app.get("/tasks/new")
    def new_task_form():
        """新規タスク作成フォームを表示する"""
        return render_template("form.html")

    # ==========================================================================
    # 演習02: タスク作成（Create）
    # --------------------------------------------------------------------------
    # 学習ポイント: 入力値のチェック（バリデーション）
    # - タスク名が空の場合は 400 エラーを返す
    # - 状態が許可された値でない場合は 400 エラーを返す
    # - ヒント: abort(400, "エラーメッセージ") でエラーを返せます
    # ==========================================================================
    @app.post("/tasks/create")
    def create_task():
        """タスク作成"""

        # タスク名を取得
        task_name = request.form.get("task")

        # TODO: タスク名が空の場合は 400 エラーを返してください
        # ヒント: if not task_name: で空かどうか判定できます

        # 状態を取得（デフォルトは「未着手」）
        status = request.form.get("status") or "未着手"

        # TODO: 状態が ALLOWED_STATUS に含まれていない場合は 400 エラーを返してください
        # ヒント: if status not in ALLOWED_STATUS: で判定できます

        # その他のフィールド
        assigned = request.form.get("assigned") or ""
        priority = request.form.get("priority") or "中"
        due_date = request.form.get("due_date") or ""
        description = request.form.get("description") or ""
        created_at = datetime.now(timezone.utc).isoformat()

        # データベースに保存
        query_db(
            """
            INSERT INTO tasks (
                created_at,
                task,
                status,
                assigned,
                priority,
                due_date,
                description
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (
                created_at,
                task_name,
                status,
                assigned,
                priority,
                due_date,
                description,
            ),
            commit=True,
        )

        return redirect("/tasks")

    # ==========================================================================
    # 演習03: タスク削除（Delete）
    # --------------------------------------------------------------------------
    # 学習ポイント: SQLの書き方（DELETE文）
    # - DELETE FROM テーブル名 WHERE 条件
    # - ヒント: task_id を使って特定のタスクを削除します
    # ==========================================================================
    @app.post("/tasks/delete/<int:task_id>")
    def delete_task(task_id):
        """タスク削除"""

        # データベースからタスクを削除
        affected_rows = query_db(
            # TODO: DELETE文を書いてください
            "???",
            (task_id,),
            commit=True,
        )

        # タスクが存在しなかった場合は404エラー
        if affected_rows == 0:
            abort(404, "タスクが見つかりません")

        return redirect("/tasks")

    # ==========================================================================
    # 演習04: タスク更新（Update）
    # --------------------------------------------------------------------------
    # 学習ポイント: 演習01〜03の組み合わせ
    # - ルーティング: 正しいURLパスを設定
    # - バリデーション: 状態のチェック
    # - SQL: UPDATE文の作成
    # ==========================================================================

    # ===== タスク編集フォーム =====
    @app.get("/tasks/edit/<int:task_id>")
    def edit_task_form(task_id):
        """タスク編集"""
        # ToDo: 指定されたIDのタスクを取得
        rows = query_db(
            "???",
            (task_id,),
        )
        # ToDo: タスクが存在しない場合は404エラー
        # ヒント: if not rows: で判定できます

        row = rows[0]
        # テンプレートに渡すタスク情報
        task_item = {
            "id": row["id"],
            "task": row["task"],
            "assigned": row["assigned"] or "",
            "status": row["status"],
            "priority": row["priority"] or "中",
            "due_date": row["due_date"] or "",
            "description": row["description"] or "",
        }

        return render_template(
            "form.html",
            form_action=f"/tasks/update/{task_id}",
            task_item=task_item,
        )

    # TODO: 正しいURLパスを設定してください（例: "/tasks/update/<int:task_id>"）
    @app.post("/04_ToDo")
    def update_task(task_id):
        """タスク更新"""
        # 更新するフィールドと値を収集
        fields = []
        values = []

        # タスク名
        task_name = request.form.get("task")
        if task_name is not None:
            fields.append("task = ?")
            values.append(task_name)

        # 状態
        status = request.form.get("status")
        if status is not None:
            # TODO: 状態が ALLOWED_STATUS に含まれていない場合は 400 エラーを返してください

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
        values.append(task_id)
        # TODO: UPDATE文を書いてください
        sql = f"???"
        affected_rows = query_db(sql, tuple(values), commit=True)

        # ToDo: タスクが存在しなかった場合は404エラー
        # ヒント: affected_rows を使って判定できます

        return redirect("/tasks")

    return app


# このファイルを直接実行した場合の処理
if __name__ == "__main__":
    app = create_app()
    app.run(debug=True)
