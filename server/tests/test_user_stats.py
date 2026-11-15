import os
from pathlib import Path
import tempfile
import unittest

from app.user_stats import collect_user_stats


class UserStatsTests(unittest.TestCase):
    def test_empty_directory(self):
        with tempfile.TemporaryDirectory() as data_dir:
            self.assertEqual(collect_user_stats(data_dir), {
                "Number of users": 0,
                "Number of active users last 3d": 0,
                "Number of active users last 7d": 0,
                "Number of active users last 30d": 0,
                "Number of active users last 265d": 0,
            })

    def test_activity_windows_include_exact_boundary(self):
        now = 1800000000
        with tempfile.TemporaryDirectory() as data_dir:
            for index, days in enumerate((0, 3, 7, 30, 265, 266)):
                metadata = Path(data_dir) / f"{index:08d}.meta"
                metadata.touch()
                modified = now - days * 86400
                os.utime(metadata, (modified, modified))
            # Other per-user files must not be counted as additional users.
            (Path(data_dir) / "00000000").touch()
            (Path(data_dir) / "00000000.publickey").touch()
            self.assertEqual(collect_user_stats(data_dir, now=now), {
                "Number of users": 6,
                "Number of active users last 3d": 2,
                "Number of active users last 7d": 3,
                "Number of active users last 30d": 4,
                "Number of active users last 265d": 5,
            })
