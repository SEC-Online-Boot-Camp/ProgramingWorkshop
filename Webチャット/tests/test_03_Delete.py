"""
演習03: タスク削除（Delete）のテスト
学習ポイント: SQLの書き方（DELETE文）
"""

import os
import sqlite3


def test_03_Delete_01(client):
    """POST /messages/delete/<id> で削除後にリダイレクトされること"""
    response = client.post("/messages/delete/1", follow_redirects=False)
    assert response.status_code == 302
    assert "/messages" in response.location


def test_03_Delete_02(client):
    """POST /messages/delete/<id> でDBからタスクが削除されること"""
    db_path = os.environ["TEST_DB_PATH"]
    # 削除前にタスクが存在することを確認
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("SELECT COUNT(*) FROM messages WHERE id = ?", (1,))
    count_before = cursor.fetchone()[0]
    conn.close()
    assert count_before == 1
    # 削除リクエスト
    client.post("/messages/delete/1")
    # DBから削除されていること
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("SELECT COUNT(*) FROM messages WHERE id = ?", (1,))
    count_after = cursor.fetchone()[0]
    conn.close()
    assert count_after == 0


def test_03_Delete_03(client):
    """POST /messages/delete/<id> で存在しないIDを指定した場合は404エラーになること"""
    response = client.post("/messages/delete/9999")
    assert response.status_code == 404
