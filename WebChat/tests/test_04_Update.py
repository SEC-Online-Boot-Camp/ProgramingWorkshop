"""
演習04: タスク更新（Update）のテスト
学習ポイント: 演習01〜03の組み合わせ（ルーティング + バリデーション + SQL）
"""

import os
import sqlite3


def test_04_Update_01(client):
    """GET /messages/edit/<id> で編集フォームが表示されること"""
    response = client.get("/messages/edit/1")
    assert response.status_code == 200
    html = response.data.decode("utf-8")
    assert "form" in html.lower()


def test_04_Update_02(client):
    """POST /messages/update/<id> でタスクの状態を更新できること"""
    response = client.post(
        "/messages/update/1",
        data={"status": "進行中"},
        follow_redirects=False,
    )
    # リダイレクトされること
    assert response.status_code == 302
    # DBが更新されていること
    db_path = os.environ["TEST_DB_PATH"]
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("SELECT status FROM messages WHERE id = ?", (1,))
    row = cursor.fetchone()
    conn.close()
    assert row is not None
    assert row[0] == "進行中"


def test_04_Update_03(client):
    """POST /messages/update/<id> で無効な状態を指定した場合は400エラーになること"""
    response = client.post(
        "/messages/update/1",
        data={"status": "無効な状態"},
    )
    assert response.status_code == 400


def test_04_Update_04(client):
    """GET /messages/edit/<id> で存在しないIDを指定した場合は404エラーになること"""
    response = client.get("/messages/edit/9999")
    assert response.status_code == 404
