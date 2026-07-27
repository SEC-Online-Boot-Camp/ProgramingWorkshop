@echo off
REM ============================================
REM Next.js 開発環境ワンボタン起動バッチ
REM - すでに起動していればブラウザだけ開く
REM - 未起動なら npm install → npm run dev → ブラウザ
REM ============================================

REM このバッチが置かれているディレクトリに移動
cd /d "%~dp0"

set PORT=3000
set URL=http://localhost:%PORT%

echo --------------------------------------------
echo Next.js 開発サーバー起動チェック中...
echo (ポート %PORT% を使用中か確認します)
echo --------------------------------------------

REM すでに何か(=たぶんNext.js dev)が PORT をLISTENしてるか調べる
REM ※ netstat は管理者権限なしでもOK
for /f "tokens=1,2,3,4,5" %%a in ('netstat -ano ^| findstr /R /C:":%PORT% " ^| findstr LISTENING') do (
    set SERVER_RUNNING=1
)

REM 環境変数 SERVER_RUNNING が 1 なら既に稼働中とみなす
if defined SERVER_RUNNING (
    echo --------------------------------------------
    echo 既にサーバーは動いているようです。新しく起動しません。
    echo ブラウザを開きます → %URL%
    echo --------------------------------------------
    start "" "%URL%"
    goto :END
)

echo --------------------------------------------
echo サーバーはまだ動いていません。起動準備をします。
echo --------------------------------------------

REM 依存パッケージが無い場合は install してあげる
if not exist node_modules (
    echo node_modules が見つかりません。npm install を実行します...
    call npm install
    if errorlevel 1 (
        echo [エラー] npm install に失敗しました。
        echo Node.js / npm がインストールされているか確認してください。
        pause
        goto :END
    )
)

echo --------------------------------------------
echo 開発サーバーを起動します: npm run dev
echo 別ウィンドウが開きます。この黒い画面はすぐ閉じます。
echo サーバーを止めたいときは、開いたウィンドウを閉じてください。
echo --------------------------------------------

REM 別のコマンドプロンプトを立ち上げて npm run dev を実行
REM /k なのでそのウィンドウは開いたまま(ログが見える)
start "Next.js Dev Server" cmd /k "npm run dev"

REM サーバー起動直後はまだ立ち上がっていないことがあるので、ちょっと待つ
REM (約2秒弱: 2回分のping応答待ち)
ping 127.0.0.1 -n 3 >nul

echo ブラウザを開きます → %URL%
start "" "%URL%"

:END
echo --------------------------------------------
echo 完了しました 🎉
echo --------------------------------------------
exit
