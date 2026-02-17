"""
演習01: メッセージ一覧取得（Read）のテスト
"""


def test_01_Read_01(client):
    """GET /messages でメッセージ一覧ページが正常に表示されること"""
    response = client.get("/messages")
    assert response.status_code == 200
    assert "メッセージ一覧" in response.data.decode("utf-8")
