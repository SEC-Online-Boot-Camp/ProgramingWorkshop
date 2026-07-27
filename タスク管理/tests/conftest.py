"""
テスト用の共通設定（pytest fixture）

このファイルはpytestが自動的に読み込み、
各テストファイルで使用できるfixtureを提供します。
"""

import importlib
import os
import sqlite3
import sys
import types
from datetime import datetime, timezone

import pytest

ROOT = os.path.dirname(os.path.dirname(__file__))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)
try:
    app_mod = importlib.import_module("app")
except Exception:
    app_mod = None
taskmanager_mod = types.ModuleType("TaskManager")
taskmanager_mod.app = app_mod
sys.modules["TaskManager"] = taskmanager_mod


@pytest.fixture
def client(tmp_path, monkeypatch):
    from app import create_app

    # テスト用DBを新規作成（毎回初期化）
    test_db = tmp_path / "test_task.db"
    test_db_str = str(test_db)

    # DBを新規作成し、テーブルを作成
    conn = sqlite3.connect(test_db_str)
    conn.execute(
        """
        CREATE TABLE tasks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            created_at TEXT NOT NULL,
            task TEXT,
            status TEXT,
            assigned TEXT,
            priority TEXT,
            due_date TEXT,
            description TEXT
        )
        """
    )

    # テスト用タスクを1件追加
    now = datetime.now(timezone.utc).isoformat()
    conn.execute(
        """
        INSERT INTO tasks (
            created_at, task, status, assigned, priority, due_date, description
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
        """,
        (
            now,
            "テストタスク",
            "未着手",
            "テスト担当者",
            "高",
            "2025-12-31",
            "テスト用の説明",
        ),
    )
    conn.commit()
    conn.close()

    # 環境変数でテスト用DBを指定（create_appの前に設定）
    monkeypatch.setenv("TEST_DB_PATH", test_db_str)

    # create_appを呼び出してFlaskアプリを作成
    app = create_app()
    app.config["TESTING"] = True
    with app.test_client() as client:
        yield client
