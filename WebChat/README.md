WebChat workshop starter

Quick start (for students):

- Open the `WebChat` folder in VSCode.
- Create and activate a virtualenv (optional):

```powershell
py -3.12 -m venv .venv
& .venv\Scripts\Activate.ps1
```

- Install dependencies:

```powershell
py -3.12 -m pip install -r requirements.txt
```

- Regenerate seed DB (optional, instructor already provided one):

```powershell
py -3.12 create_seed_db.py -f
```

- Run tests:

```powershell
py -3.12 -m pytest -q
```

- During the lesson, edit the TODOs in `app.py` to make tests pass.
