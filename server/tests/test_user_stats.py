import os
from pathlib import Path
import tempfile
import unittest

from app.user_stats import collect_user_stats


class UserStatsTests(unittest.TestCase):
    def test_empty_directory(self):
        with tempfile.TemporaryDirectory() as data_dir:
            self.assertEqual(collect_user_stats(data_dir), {
                "Users": 0,
                "Active 3d": 0,
                "Active 7d": 0,
                "Active 30d": 0,
                "Active 365d": 0,
            })

    def test_activity_windows_include_exact_boundary(self):
        now = 1800000000
        with tempfile.TemporaryDirectory() as data_dir:
            for index, days in enumerate((0, 3, 7, 30, 365, 366)):
                metadata = Path(data_dir) / f"{index:08d}.meta"
                metadata.touch()
                modified = now - days * 86400
                os.utime(metadata, (modified, modified))
            # Other per-user files must not be counted as additional users.
            (Path(data_dir) / "00000000").touch()
            (Path(data_dir) / "00000000.publickey").touch()
            self.assertEqual(collect_user_stats(data_dir, now=now), {
                "Users": 6,
                "Active 3d": 2,
                "Active 7d": 3,
                "Active 30d": 4,
                "Active 365d": 5,
            })
