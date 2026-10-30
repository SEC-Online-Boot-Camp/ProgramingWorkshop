# 環境構築（Elixirアプリ）

Elixir（Phoenix）で作ったアプリを動かすための準備です。対象は次の2つです。

- [データベースの仕組み](../データベースの仕組み/README.md)
- [暗号解読ミッション](../暗号解読ミッション/README.md)

どちらも、Erlang・Elixir・Python 3.12を使います。1台のPCで一度準備すれば、2つのアプリで共通に使えます。
アプリの使い方は、それぞれのフォルダのREADMEを見てください。

Windowsで、PowerShellを使う前提で書いています。管理者権限は不要です（標準ユーザーで実行します）。

## 必要なもの

| もの | バージョン | 用途 |
|---|---|---|
| Erlang/OTP | 27以上 | Elixirを動かす土台 |
| Elixir | 1.17以上 | アプリ本体 |
| Python | 3.12 | 受講者が書いたコード・SQLの実行（SQLはPython標準の`sqlite3`を使う） |

Node.jsは不要です（画面のCSS・JSは、ビルド済みのものをリポジトリに入れてあります）。

## 1. scoopを入れる

[scoop](https://scoop.sh/)は、Windows用のパッケージ管理ツールです。ユーザーのフォルダ（`~\scoop`）にインストールするので、管理者権限は要りません。
すでに入っている場合（`scoop --version`で確かめられます）は、この手順は飛ばします。

[公式サイト](https://scoop.sh/)に書かれている、公式のインストール方法です。

```powershell
# 自分のユーザーだけ、署名付き・ローカルのスクリプトの実行を許可する（設定の変更）
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# scoopのインストーラーをダウンロードして実行する（https://get.scoop.sh の公式スクリプト）
Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
```

- 1行目は、PowerShellの実行ポリシーを、今のユーザーについてだけ変更します。元に戻すときは`Set-ExecutionPolicy -ExecutionPolicy Undefined -Scope CurrentUser`です。
- 2行目は、インターネットから取得したスクリプトをそのまま実行します。会社のPCなどで、ダウンロードしたスクリプトの実行が制限されている場合は、PCの管理者に相談してください。
- scoopと、scoopで入れたものを消すときは`scoop uninstall scoop`です。

## 2. Erlang・Elixir・Pythonを入れる

```powershell
# Python 3.12は「versions」バケット（追加の一覧）にあり、バケットの追加にgitが必要
scoop install git
scoop bucket add versions

scoop install erlang elixir python312
```

入ったかを確かめます（どれも表示するだけで、何も変更しません）。

```powershell
elixir --version     # 「Elixir 1.17」以上と「Erlang/OTP 27」以上が表示される
python312 --version  # Python 3.12.x
```

コマンドが見つからないときは、PowerShellを開き直してください（scoopが追加したPATHが反映されます）。

### Pythonについて

アプリは、次の順にPythonを探します。

1. `~\sobc-venv\Scripts\python.exe`（研修用PCで、あらかじめ用意された仮想環境）
2. `python312`（scoopのpython312が作るコマンド）
3. `python3`、`python`

研修用PCで1が用意されている場合は、`python312`を入れなくても動きます。
`python`・`python3`だけだと、Windowsストアの案内用のダミー（実際には動かない）が見つかることがあるので、`python312`を入れるのがおすすめです。

## 3. Elixirのツールを入れる

Elixirのパッケージ管理（Hex）とビルドツール（rebar3）を、ユーザーのフォルダに入れます。

```powershell
mix local.hex --force
mix local.rebar --force
```

## 4. アプリごとの準備

アプリのフォルダで、一度だけ`mix setup`を実行します。依存パッケージの取得と、CSS・JSのビルドを行います。

```powershell
cd データベースの仕組み
mix setup

cd ..\暗号解読ミッション\App
mix setup
```

`mix setup`は、インターネットから次のものを取得します。

- 依存パッケージ（[hex.pm](https://hex.pm/)）
- CSS・JSのビルドツール（tailwind・esbuild。GitHubとnpmのサイトから、それぞれの実行ファイルを取得）

## 5. 動作確認

アプリのフォルダの`start_server.bat`をダブルクリックするか、アプリのフォルダで`mix phx.server`を実行します。
ブラウザで`http://localhost:4000`を開いて、画面が出れば準備完了です。止めるときは、ターミナルで`Ctrl+C`を2回押します。

## うまくいかないとき

### `mix setup`で、tailwind・esbuildのダウンロードに失敗する

CSS・JSはビルド済みのものをリポジトリに入れてあるので、ビルドツールが無くてもアプリは動きます。
依存パッケージだけを取得して、起動してください。

```powershell
mix deps.get
mix phx.server
```

アプリの画面（`assets/`・`lib/`）を変更したときだけ、ビルドツールが必要になります。

### Pythonを起動できない（データベースの仕組み）

データベースの仕組みのフォルダで、診断スクリプトを実行します。読み取りと、Pythonの起動確認だけを行い、設定やファイルは変更しません。

```powershell
mix run --no-start scripts/diagnose_python.exs
```

最後の「== まとめ ==」から下に、どのPythonが見つかり、どこで失敗したかが表示されます。
