import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import numpy as np

import generate_vieneu_assets as spike


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
            self.assertEqual(spike.vietnamese_amount_words(amount), expected)

    def test_inventory_counts_and_unique_ids(self):
        word = spike.word_inventory()
        chunk = spike.chunk_inventory()
        self.assertEqual(len(word), 21)
        self.assertEqual(len(chunk), 1103)
        ids = [item.asset_id for item in word + chunk]
        self.assertEqual(len(ids), len(set(ids)))

    def test_forced_chunk_is_used_for_middle_short_group(self):
        self.assertEqual(
            spike.amount_chunk_asset_ids(1_005_000),
            [
                "chunk/leading/001",
                "chunk/unit/triệu",
                "chunk/forced/005",
                "chunk/unit/nghìn",
                "chunk/unit/đồng",
            ],
        )

    def test_word_tokens_cover_amount(self):
        inventory = {item.asset_id for item in spike.word_inventory()}
        for amount in spike.LISTENING_AMOUNTS:
            self.assertTrue(set(spike.amount_word_asset_ids(amount)).issubset(inventory))


class WavCompositionTest(unittest.TestCase):
    def _guarded(self, value=100, content_frames=12_000):
        content = np.full(content_frames, value, dtype=np.float32) / 32768.0
        guarded = spike.add_boundary_silence(content, spike.PACKAGE_SAMPLE_RATE)
        return np.round(guarded * 32768).astype(np.int16)

    def test_composes_pcm16_assets_with_gap(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            assets = root / "word" / "wav24"
            assets.mkdir(parents=True)
            for asset_id, value in [("word/token/một", 100), ("word/token/đồng", 200)]:
                spike.write_pcm16(
                    assets / f"{spike.safe_name(asset_id)}.wav",
                    spike.PACKAGE_SAMPLE_RATE,
                    self._guarded(value=value),
                )
            metrics = spike.compose(
                ["word/token/một", "word/token/đồng"],
                "word",
                root / "combined.wav",
                root,
            )
            per_asset = 12_000 + 2 * round(
                spike.PACKAGE_SAMPLE_RATE * spike.COMPOSE_BOUNDARY_SILENCE_MS / 1000
            )
            expected_frames = 2 * per_asset + round(
                spike.PACKAGE_SAMPLE_RATE * spike.JOIN_GAP_MS / 1000
            )
            rate, samples = spike.read_pcm16(root / "combined.wav")
            self.assertEqual(rate, spike.PACKAGE_SAMPLE_RATE)
            self.assertEqual(len(samples), expected_frames)
            self.assertEqual(metrics["token_count"], 2)
            edge_frames = round(
                spike.PACKAGE_SAMPLE_RATE * spike.COMPOSE_BOUNDARY_SILENCE_MS / 1000
            )
            self.assertFalse(np.any(samples[:edge_frames]))
            self.assertFalse(np.any(samples[-edge_frames:]))

    def test_stored_asset_requires_full_zero_boundary_guard(self):
        spec = spike.AssetSpec("word/token/một", "một", "word", "token")
        valid = self._guarded()
        self.assertEqual(
            spike.validate_stored_asset(spec, valid, spike.PACKAGE_SAMPLE_RATE), []
        )
        valid[0] = 1
        self.assertIn(
            "missing_boundary_guard",
            spike.validate_stored_asset(spec, valid, spike.PACKAGE_SAMPLE_RATE),
        )

    def test_stored_asset_uses_asymmetric_corpus_guards(self):
        content_frames = 12_000
        samples = self._guarded(content_frames=content_frames)
        leading_frames = round(
            spike.PACKAGE_SAMPLE_RATE * spike.ASSET_LEADING_SILENCE_MS / 1000
        )
        trailing_frames = round(
            spike.PACKAGE_SAMPLE_RATE * spike.ASSET_TRAILING_SILENCE_MS / 1000
        )

        self.assertEqual(len(samples), leading_frames + content_frames + trailing_frames)
        self.assertFalse(np.any(samples[:leading_frames]))
        self.assertFalse(np.any(samples[-trailing_frames:]))
        self.assertTrue(np.all(samples[leading_frames:-trailing_frames] == 100))

    def test_migrates_legacy_guards_without_changing_speech(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "corpus-v3"
            destination = root / "corpus-v4"
            spec = spike.AssetSpec("word/token/một", "một", "word", "token")
            content = np.full(12_000, 123, dtype=np.int16)
            for format_name, rate in [
                ("wav48", spike.SAMPLE_RATE),
                ("wav24", spike.PACKAGE_SAMPLE_RATE),
            ]:
                legacy = spike.add_boundary_silence(
                    content.astype(np.float32) / 32768.0,
                    rate,
                    leading_ms=120,
                    trailing_ms=120,
                )
                spike.write_pcm16(
                    source / "word" / format_name / "word__token__một.wav",
                    rate,
                    np.round(legacy * 32768).astype(np.int16),
                )
            source_hashes = {
                f"{path.parent.name}/{path.name}": spike.sha256(path)
                for path in (source / "word").glob("wav*/*.wav")
            }

            spike.migrate_corpus_assets([spec], source, destination, 120, 120)

            for format_name, rate in [
                ("wav48", spike.SAMPLE_RATE),
                ("wav24", spike.PACKAGE_SAMPLE_RATE),
            ]:
                path = destination / "word" / format_name / "word__token__một.wav"
                actual_rate, migrated = spike.read_pcm16(path)
                self.assertEqual(actual_rate, rate)
                migrated_content = spike.remove_stored_boundary_silence(migrated, rate)
                np.testing.assert_array_equal(migrated_content, content)
            self.assertEqual(
                source_hashes,
                {
                    f"{path.parent.name}/{path.name}": spike.sha256(path)
                    for path in (source / "word").glob("wav*/*.wav")
                },
            )

    def test_listening_pack_fails_closed_on_invalid_asset(self):
        with tempfile.TemporaryDirectory() as temp:
            corpus = Path(temp) / "corpus"
            specs = [
                spike.AssetSpec("word/token/một", "một", "word", "token"),
                spike.AssetSpec("word/token/đồng", "đồng", "word", "token"),
                spike.AssetSpec("chunk/leading/001", "một", "chunk", "leading-group"),
                spike.AssetSpec("chunk/unit/đồng", "đồng", "chunk", "scale-unit"),
            ]
            for spec in specs:
                path = corpus / spec.scheme / "wav24" / f"{spike.safe_name(spec.asset_id)}.wav"
                spike.write_pcm16(path, spike.PACKAGE_SAMPLE_RATE, self._guarded())
            bad_path = corpus / "word" / "wav24" / "word__token__đồng.wav"
            spike.write_pcm16(
                bad_path,
                spike.PACKAGE_SAMPLE_RATE,
                np.full(12_000, 100, dtype=np.int16),
            )

            with patch.object(spike, "LISTENING_AMOUNTS", [1]):
                with self.assertRaisesRegex(ValueError, "listening pack blocked by QC"):
                    spike.create_listening_pack(corpus, Path(temp) / "listening")

    def test_generation_seed_is_stable_per_attempt(self):
        self.assertEqual(
            spike.generation_seed("chunk/leading/001", 1),
            spike.generation_seed("chunk/leading/001", 1),
        )
        self.assertNotEqual(
            spike.generation_seed("chunk/leading/001", 1),
            spike.generation_seed("chunk/leading/001", 2),
        )

    def test_quality_summary_reports_long_assets(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            spec = spike.AssetSpec("word/token/một", "một", "word", "token")
            spike.write_pcm16(
                root / "word" / "wav24" / "word__token__một.wav",
                spike.PACKAGE_SAMPLE_RATE,
                np.concatenate(
                    [
                        np.zeros(
                            round(
                                spike.PACKAGE_SAMPLE_RATE
                                * spike.ASSET_LEADING_SILENCE_MS
                                / 1000
                            ),
                            dtype=np.int16,
                        ),
                        np.full(spike.PACKAGE_SAMPLE_RATE * 4, 100, dtype=np.int16),
                        np.zeros(
                            round(
                                spike.PACKAGE_SAMPLE_RATE
                                * spike.ASSET_TRAILING_SILENCE_MS
                                / 1000
                            ),
                            dtype=np.int16,
                        ),
                    ]
                ),
            )

            summary = spike.quality_summary([spec], root)

            self.assertEqual(summary["word"]["outlierCount"], 1)
            self.assertEqual(summary["word"]["outliers"][0]["assetId"], spec.asset_id)


if __name__ == "__main__":
    unittest.main()
