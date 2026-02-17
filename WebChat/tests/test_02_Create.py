"""
演習02: メッセージ作成（Create）のテスト
学習ポイント: 入力値のチェック（バリデーション）
"""


def test_02_Create_01(client):
    """POST /messages/create でmessageが空の場合は400エラーになること"""
    response = client.post(
        "/messages/create",
        data={"message": ""},
    )
    assert response.status_code == 400


def test_02_Create_02(client):
    """POST /messages/create で無効な状態を指定した場合は400エラーになること"""
    response = client.post(
        "/messages/create",
        data={
            "message": "テストメッセージ",
            "status": "無効な状態",
        },
    )
    assert response.status_code == 400
