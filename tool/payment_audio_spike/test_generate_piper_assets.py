import tempfile
import unittest
from pathlib import Path

import numpy as np

import generate_piper_assets as generator


class AmountGrammarTest(unittest.TestCase):
    def test_matches_payment_edge_cases(self):
        cases = {
            150_000: "một trăm năm mươi nghìn",
            1_250_000: "một triệu hai trăm năm mươi nghìn",
            1_005_000: "một triệu không trăm lẻ năm nghìn",
            21_000_005: "hai mươi mốt triệu không trăm lẻ năm",
            999_999_999: (
                "chín trăm chín mươi chín triệu chín trăm chín mươi chín nghìn "
                "chín trăm chín mươi chín"
            ),
        }
        for amount, expected in cases.items():
            self.assertEqual(generator.vietnamese_amount_words(amount), expected)

    def test_inventory_is_exact_and_unique(self):
        assets = generator.chunk_inventory()
        ids = [asset.asset_id for asset in assets]
        self.assertEqual(len(assets), 1_103)
        self.assertEqual(len(ids), len(set(ids)))
        self.assertEqual(ids[0], "chunk/leading/000")
        self.assertEqual(ids[-1], "chunk/unit/đồng")

    def test_forced_chunk_is_used_for_middle_short_group(self):
        self.assertEqual(
            generator.amount_chunk_asset_ids(1_005_000),
            [
                "chunk/leading/001",
                "chunk/unit/triệu",
                "chunk/forced/005",
                "chunk/unit/nghìn",
                "chunk/unit/đồng",
            ],
        )

    def test_rejects_out_of_range_amounts(self):
        for amount in [0, -1, generator.SUPPORTED_AMOUNT_MAX + 1]:
            with self.assertRaises(ValueError):
                generator.amount_chunk_asset_ids(amount)


class WavPolicyTest(unittest.TestCase):
    def _guarded(self, value: int = 100, content_frames: int = 12_000):
        content = np.full(content_frames, value, dtype=np.float32) / 32768.0
        guarded = generator.add_boundary_silence(
            content, generator.PACKAGE_SAMPLE_RATE
        )
        return np.round(guarded * 32768).astype(np.int16)

    def test_stored_asset_uses_asymmetric_guards(self):
        content_frames = 12_000
        samples = self._guarded(content_frames=content_frames)
        leading = round(
            generator.PACKAGE_SAMPLE_RATE
            * generator.ASSET_LEADING_SILENCE_MS
            / 1000
        )
        trailing = round(
            generator.PACKAGE_SAMPLE_RATE
            * generator.ASSET_TRAILING_SILENCE_MS
            / 1000
        )
        self.assertEqual(len(samples), leading + content_frames + trailing)
        self.assertFalse(np.any(samples[:leading]))
        self.assertFalse(np.any(samples[-trailing:]))
        self.assertTrue(np.all(samples[leading:-trailing] == 100))

    def test_validator_fails_on_corrupt_guard(self):
        spec = generator.AssetSpec(
            "chunk/leading/001", "một", "leading-group"
        )
        samples = self._guarded()
        self.assertEqual(
            generator.validate_stored_asset(
                spec, samples, generator.PACKAGE_SAMPLE_RATE
            ),
            [],
        )
        samples[0] = 1
        self.assertIn(
            "missing_boundary_guard",
            generator.validate_stored_asset(
                spec, samples, generator.PACKAGE_SAMPLE_RATE
            ),
        )

    def test_pcm16_round_trip(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "sample.wav"
            expected = self._guarded()
            generator.write_pcm16(path, generator.PACKAGE_SAMPLE_RATE, expected)
            rate, actual = generator.read_pcm16(path)
            self.assertEqual(rate, generator.PACKAGE_SAMPLE_RATE)
            np.testing.assert_array_equal(actual, expected)

    def test_model_checksums_are_production_pins(self):
        self.assertEqual(len(generator.MODEL_SHA256), 64)
        self.assertEqual(len(generator.CONFIG_SHA256), 64)
        self.assertEqual(generator.PIPER_TTS_VERSION, "1.4.2")
        self.assertEqual(
            generator.package_version("piper-tts"), generator.PIPER_TTS_VERSION
        )
        self.assertEqual(generator.SPEED, 0.90)
        self.assertEqual(generator.OUTPUT_GAIN_DB, -1.5)


if __name__ == "__main__":
    unittest.main()
