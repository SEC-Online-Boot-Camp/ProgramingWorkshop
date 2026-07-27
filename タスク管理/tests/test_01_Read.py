"""
演習01: タスク一覧取得（Read）のテスト
"""


def test_01_Read_01(client):
    """GET /tasks でタスク一覧ページが正常に表示されること"""
    response = client.get("/tasks")

    assert response.status_code == 200
    assert "タスク一覧" in response.data.decode("utf-8")
