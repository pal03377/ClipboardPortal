"""Admin statistics based on user registration or last clipboard receipt."""

import json
import os
from pathlib import Path
import time


def collect_user_stats(data_dir, now=None):
    if now is None:
        now = time.time()
    periods = (3, 7, 30, 365)
    stats = {"Users": 0}
    stats.update({f"Active {days}d": 0 for days in periods})
    for metadata in Path(data_dir).glob("*.meta"):
        try:
            modified = metadata.stat().st_mtime
        except FileNotFoundError:
            continue  # A user may have been removed while collecting statistics.
        stats["Users"] += 1
        # Metadata is created at registration and updated on clipboard receipt.
        for days in periods:
            if modified >= now - days * 86400:
                stats[f"Active {days}d"] += 1
    return stats


if __name__ == "__main__":
    print(json.dumps(collect_user_stats(os.environ.get("DATA_DIR", "data"))))
