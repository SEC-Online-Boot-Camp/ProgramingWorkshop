"""
演習02: タスク作成（Create）のテスト
学習ポイント: 入力値のチェック（バリデーション）
"""


def test_02_Create_01(client):
    """POST /tasks/create でタスク名が空の場合は400エラーになること"""
    response = client.post(
        "/tasks/create",
        data={"task": ""},
    )

    assert response.status_code == 400


def test_02_Create_02(client):
    """POST /tasks/create で無効な状態を指定した場合は400エラーになること"""
    response = client.post(
        "/tasks/create",
        data={
            "task": "テストタスク",
            "status": "無効な状態",
        },
    )

    assert response.status_code == 400
