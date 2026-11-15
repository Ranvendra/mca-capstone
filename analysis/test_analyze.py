"""Unit tests for M5 trace discovery, validation and reference metrics."""
from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from analysis import analyze


class M5AnalysisTests(unittest.TestCase):
    def test_only_seven_declared_m5_traces_are_selected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in (*analyze.M5_TRACE_NAMES, "sample"):
                (root / f"{name}.trace").write_text("0 00000000\n", encoding="ascii")
            selected = analyze.discover_m5_traces(root)
            self.assertEqual([path.stem for path in selected], list(analyze.M5_TRACE_NAMES))
            self.assertNotIn("sample", [path.stem for path in selected])

    def test_missing_required_m5_trace_fails_loudly(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(FileNotFoundError, "Missing required M5 trace"):
                analyze.discover_m5_traces(Path(directory))

    def test_reference_model_hit_miss_and_amat(self):
        # Two words in one 16-byte block: first misses, second hits.
        rows, summary = analyze.simulate([(0, 0x00), (0, 0x04)], 1024, 16, 4)
        self.assertEqual([row["hit"] for row in rows], [0, 1])
        self.assertEqual([row["latency_cycles"] for row in rows], [22, 1])
        self.assertEqual(summary["miss_penalty_cycles"], 21)
        self.assertAlmostEqual(summary["measured_amat_cycles"], 11.5)
        self.assertAlmostEqual(summary["formula_amat_cycles"], 11.5)
        self.assertAlmostEqual(summary["amat_difference_cycles"], 0.0)

    def test_invalid_cache_geometry_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "at least two blocks"):
            analyze.validate_config(16, 16, 4)

    def test_invalid_memory_latency_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "MEM_LATENCY"):
            analyze.validate_config(1024, 16, 0)

    def test_empty_trace_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "empty trace"):
            analyze.simulate([], 1024, 16, 4)


if __name__ == "__main__":
    unittest.main()
