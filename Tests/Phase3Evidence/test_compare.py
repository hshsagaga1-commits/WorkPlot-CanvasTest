import copy
import json
import struct
import sys
import tempfile
import unittest
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))
import phase3_compare


def capture(second, phase="beforeRestart"):
    return {
        "phase": phase,
        "capturedAt": f"2026-01-01T12:00:{second:02d}.123Z",
        "machine": "iPhoneFixture1,1",
        "osVersion": "27.0",
        "build": "Fixture-Build",
        "orientation": "portrait",
        "appVersion": "0.1.0",
        "sourceRevision": "fixture",
        "geometry": {
            "bounds": {"width": 10, "height": 20},
            "nativeBounds": {"width": 20, "height": 40},
            "currentMode": {"width": 20, "height": 40},
            "availableModes": [{"width": 20, "height": 40}],
            "scale": 2,
            "nativeScale": 2,
        },
    }


def report(reference, latest=None):
    result = {
        "format": "resolutionlab.display-report",
        "schema": 1,
        "status": "READ_ONLY",
        "measurementScope": "UIKit da cena do processo",
        "reference": reference,
    }
    if latest is not None:
        result["latest"] = latest
    return result


def png_bytes(width, height):
    def chunk(kind, payload):
        return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", zlib.crc32(kind + payload))

    rows = (b"\0" + bytes(width)) * height
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 0, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(rows))
        + chunk(b"IEND", b"")
    )


class CompareTests(unittest.TestCase):
    def setUp(self):
        self.before = capture(1)
        self.after = capture(2, "afterReportedRestart")

    def test_pair_requires_same_reference_and_marks_operator_restart(self):
        result = phase3_compare.compare_reports(report(self.before), report(copy.deepcopy(self.before), self.after))
        self.assertEqual(result["pairing"]["kind"], "embedded_reference")
        self.assertEqual(result["pairing"]["restartEvidence"], "operator_reported")
        self.assertEqual(result["geometry"]["currentMode"]["comparison"], "equal")
        self.assertEqual(result["globalCanvasEvidence"], "unverified")
        alternate = copy.deepcopy(self.before)
        alternate["geometry"]["scale"] = 3
        with self.assertRaises(phase3_compare.EvidenceError):
            phase3_compare.compare_reports(report(self.before), report(alternate, self.after))

    def test_independent_export_reports_logical_only_change_without_declaring_reboot(self):
        after = capture(2)
        after["geometry"]["bounds"] = {"width": 8, "height": 16}
        result = phase3_compare.compare_reports(report(self.before), report(after))
        self.assertEqual(result["pairing"]["kind"], "independent_exports")
        self.assertEqual(result["pairing"]["restartEvidence"], "not_recorded")
        self.assertEqual(result["geometry"]["bounds"]["comparison"], "different")
        self.assertEqual(result["geometry"]["currentMode"]["comparison"], "equal")
        self.assertEqual(result["globalCanvasEvidence"], "unverified")

    def test_missing_mode_is_indeterminate_instead_of_unchanged(self):
        del self.after["geometry"]["currentMode"]
        result = phase3_compare.compare_reports(report(self.before), report(self.before, self.after))
        self.assertEqual(result["geometry"]["currentMode"]["comparison"], "unavailable")
        self.assertEqual(result["geometry"]["nativeBounds"]["comparison"], "equal")

    def test_mismatched_environment_is_rejected(self):
        for key, value in (("orientation", "landscape"), ("build", "Other-Build"), ("sourceRevision", "other")):
            with self.subTest(key=key):
                other = capture(2)
                other[key] = value
                with self.assertRaises(phase3_compare.EvidenceError):
                    phase3_compare.compare_reports(report(self.before), report(other))

    def test_historical_and_duplicate_samples_are_rejected(self):
        for other in (self.before, capture(2, "historical")):
            with self.subTest(other=other["phase"]):
                with self.assertRaises(phase3_compare.EvidenceError):
                    phase3_compare.compare_reports(report(self.before), report(other))

    def test_boolean_or_nonfinite_dimensions_are_rejected(self):
        for width in (True, 0, float("nan"), float("inf")):
            with self.subTest(width=width):
                other = capture(2)
                other["geometry"]["bounds"]["width"] = width
                with self.assertRaises(phase3_compare.EvidenceError):
                    phase3_compare.compare_reports(report(self.before), report(other))

    def test_wrong_schema_and_scope_are_rejected(self):
        for key, value in (("schema", True), ("measurementScope", "other"), ("status", "WRITE_VERIFIED")):
            with self.subTest(key=key):
                malformed = {**report(self.before), key: value}
                with self.assertRaises(phase3_compare.EvidenceError):
                    phase3_compare.compare_reports(malformed, report(capture(2)))

    def test_image_cannot_certify_global_layout(self):
        with tempfile.TemporaryDirectory() as root:
            root = Path(root)
            prior = root / "before"
            posterior = root / "after"
            snapshot = root / "home-before.png"
            changed = root / "home-after.png"
            prior.write_text(json.dumps(report(self.before)))
            posterior.write_text(json.dumps(report(self.after | {"phase": "beforeRestart"})))
            snapshot.write_bytes(png_bytes(10, 20))
            changed.write_bytes(png_bytes(20, 40))
            result = phase3_compare.measure_pair(prior, posterior, {"home": (snapshot, changed)})
            image = result["screenshots"]["home"]
            self.assertEqual(image["sizeComparison"], "different")
            self.assertEqual(image["before"]["width"], 10)
            self.assertEqual(image["source"], "operator_named")
            self.assertEqual(result["globalCanvasEvidence"], "unverified")

    def test_png_checks_structure_sizes_and_crc(self):
        valid = png_bytes(10, 20)
        self.assertEqual(phase3_compare.png_dimensions(valid), (10, 20))
        corrupt = bytearray(valid)
        corrupt[29] ^= 1
        for damaged in (valid[:33], valid[:-1], bytes(corrupt), b"not png"):
            with self.subTest(size=len(damaged)):
                with self.assertRaises(phase3_compare.EvidenceError):
                    phase3_compare.png_dimensions(damaged)

    def test_duplicate_json_keys_are_rejected(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / "before"
            path.write_text('{"schema": 1, "schema": 2}')
            with self.assertRaises(phase3_compare.EvidenceError):
                phase3_compare.read_report(path)


if __name__ == "__main__":
    unittest.main()
