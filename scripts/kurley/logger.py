"""Stdout protocol consumed by Swift PythonRunner streaming mode.
PROGRESS i/n filename, DONE, ERROR x — see Audio/PythonRunner.swift onLine.
"""


def log(msg: str) -> None:
    print(msg, flush=True)


def log_progress(idx: int, total: int, name: str) -> None:
    log(f"PROGRESS: {idx}/{total} {name}")


def log_error(msg: str) -> None:
    log(f"ERROR: {msg}")


def log_done() -> None:
    log("DONE")
