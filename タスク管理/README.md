# タスク管理

タスクを登録・一覧表示・編集・削除できる、タスク管理アプリを作る演習です。
Python（Flask）とSQLiteを使います。

アプリを作る前に、ワークシートで要件定義と設計を考えます。
そのあと、受講者は`app.py`の「TODO」を埋めて、アプリを完成させます。
テストを実行すると、TODOを正しく埋められたかを確かめられます。

## フォルダの中身

| もの | 内容 |
|---|---|
| `ワークシート_要件定義_問題.pdf`・`ワークシート_設計_問題.pdf` | 受講者に配るワークシート |
| `ワークシート_要件定義_正解.pdf`・`ワークシート_設計_正解.pdf` | ワークシートの解答例（講師用） |
| `app.py` | 受講者が編集するファイル（TODOあり） |
| `app_complete.py` | 完成版（講師用・答え合わせ用） |
| `task_manager.db` | 最初のデータが入ったデータベース |
| `create_db.py` | `task_manager.db`を作り直すスクリプト |
| `templates/`・`static/` | 画面のHTML・CSS |
| `tests/` | 確認用のテスト（CRUDの機能ごとに4つ） |

## 準備（初回だけ）

Python 3.12が必要です。このフォルダで、必要なパッケージ（Flask・pytest）を入れます。

```powershell
py -3.12 -m pip install -r requirements.txt
```

ほかの演習とパッケージを分けたいときは、先に仮想環境を作って有効にしてから、上のコマンドを実行します（任意）。

```powershell
py -3.12 -m venv .venv
.venv\Scripts\Activate.ps1
```

## 起動

このフォルダで次を実行し、ブラウザで`http://127.0.0.1:5000`を開きます。止めるときは、ターミナルで`Ctrl+C`を押します。

```powershell
py -3.12 app.py
```

完成版を動かして見せるときは、`app.py`の代わりに`app_complete.py`を実行します。

```powershell
py -3.12 app_complete.py
```

どちらも同じ`task_manager.db`を読み書きします。

## テストで確かめる

```powershell
py -3.12 -m pytest -q
```

テストは`app.py`を確かめます。機能ごとに分かれているので、1つずつ確かめることもできます。

```powershell
py -3.12 -m pytest -q tests/test_01_Read.py     # 一覧表示
py -3.12 -m pytest -q tests/test_02_Create.py   # 登録
py -3.12 -m pytest -q tests/test_03_Delete.py   # 削除
py -3.12 -m pytest -q tests/test_04_Update.py   # 編集
```

テストは、毎回作り直す一時的なデータベースを使うので、`task_manager.db`の中身は変わりません。

## データを最初の状態に戻す

画面から登録・削除したデータを、最初の状態に戻します（`task_manager.db`を作り直します）。

```powershell
py -3.12 create_db.py -f
```
