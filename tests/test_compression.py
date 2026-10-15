"""Custom quality must affect real encoders without changing default profiles."""

import concurrent.futures
import copy
import hashlib
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))
import compression_profiles as compression
import convert


class CompressionPolicyTests(unittest.TestCase):
    def test_invalid_values_cannot_reach_encoder_options(self):
        for quality in (0, 101, -1, True, False, 50.5, "50", float("nan"), float("inf")):
            for function, target in (
                (compression.image_options, "jpg"),
                (compression.audio_options, "mp3"),
                (compression.video_options, "mp4"),
            ):
                with self.subTest(quality=quality, function=function.__name__):
                    with self.assertRaises(ValueError):
                        function(target, quality)

    def test_all_audio_ladders_are_monotonic_and_reach_their_endpoints(self):
        for target, rates in compression.AUDIO_KBPS.items():
            values = [compression.audio_bitrate(target, quality) for quality in range(1, 101)]
            self.assertEqual(values, sorted(values))
            self.assertEqual((values[0], values[-1]), (rates[0], rates[-1]))
            self.assertEqual(set(values), set(rates))
            for quality in (1, 35, 75, 100):
                options = compression.audio_options(target, quality)
                self.assertIn(f"{rates[((quality - 1) * (len(rates) - 1) + 49) // 99]}k", options)
                self.assertNotIn("-q:a", options)

    def test_quality_100_does_not_change_webp_to_lossless(self):
        self.assertEqual(compression.image_options("jpg", 1), ["-quality", "1"])
        self.assertEqual(compression.image_options("avif", 100), ["-quality", "100"])
        self.assertEqual(
            compression.image_options("webp", 100),
            ["-quality", "100", "-define", "webp:lossless=false"],
        )

    def test_video_controls_follow_encoder_direction_and_preserve_muxer(self):
        expected = {
            "mp4": ("-crf", "36", "16"),
            "webm": ("-crf", "48", "20"),
            "ogv": ("-q:v", "2", "10"),
            "wmv": ("-b:v", "500k", "8000k"),
            "mpg": ("-q:v", "15", "2"),
        }
        for target, (key, low, high) in expected.items():
            for quality, value in ((1, low), (100, high)):
                options = compression.video_options(target, quality)
                self.assertEqual(options[options.index(key) + 1], value)
        original = [
            "-map",
            "0:v:0",
            "-map",
            "0:a:0?",
            "-crf",
            "20",
            "-c:v",
            "libx264",
            "-b:a",
            "192k",
            "-f",
            "mp4",
        ]
        revised = compression.override_options(original, compression.video_options("mp4", 1))
        self.assertEqual(revised.count("-map"), 2)
        self.assertEqual(revised.count("-crf"), 1)
        self.assertEqual(revised.count("-b:a"), 1)
        self.assertEqual(revised[revised.index("-f") + 1], "mp4")
        self.assertEqual(original[original.index("-crf") + 1], "20")

    def test_unsupported_and_lossless_targets_keep_their_profile(self):
        for category, targets in (
            ("image", ("png", "tiff", "bmp", "ico", "icns")),
            ("audio", ("wav", "flac", "aiff", "alac", "ape", "wv")),
            ("video", ("gif", "mxf")),
            ("document", ("docx", "epub")),
            ("config", ("json", "yaml")),
            ("geo", ("gpkg", "shp")),
        ):
            for target in targets:
                self.assertFalse(compression.supported(category, target))
                self.assertIn("does not apply", compression.note(category, target, 20))
        for target in compression.IMAGE_TARGETS:
            self.assertEqual(compression.image_options(target, None), [])
        for target in compression.AUDIO_KBPS:
            self.assertIsNone(compression.audio_options(target, None))
        for target in compression.VIDEO_TARGETS:
            self.assertEqual(compression.video_options(target, None), [])
        self.assertIsNone(compression.note("audio", "mp3", None))

    def test_metadata_rejects_nonfinite_negative_and_malformed_values(self):
        for bad in ("nan", "inf", "-inf", 0, -2, None, "N/A", [], True, False, 1e100):
            result = compression.media_metadata(
                {
                    "format": {"duration": bad},
                    "streams": [{"codec_type": "audio", "duration": "4.25", "channels": 2}],
                }
            )
            self.assertEqual(result["duration"], 4.25)
            self.assertEqual(result["channels"], 2)
        self.assertEqual(
            compression.media_metadata({"format": {"duration": "nan"}, "streams": []}), {}
        )
        result = compression.media_metadata(
            {
                "format": {"duration": "8"},
                "streams": [
                    {
                        "codec_type": "video",
                        "width": 900,
                        "height": 900,
                        "disposition": {"attached_pic": 1},
                    },
                    {"codec_type": "video", "width": 320, "height": 240},
                    {"codec_type": "audio", "channels": 2},
                ],
            }
        )
        self.assertEqual(result, {"duration": 8.0, "width": 320, "height": 240, "channels": 2})
        self.assertEqual(
            compression.media_metadata(
                {
                    "streams": [
                        {"codec_type": "video", "width": True, "height": -2},
                        {"codec_type": "audio", "channels": 10**20},
                    ]
                }
            ),
            {},
        )

    def test_default_encoder_profiles_are_unchanged(self):
        audio_before = copy.deepcopy(convert.AUDIO)
        with tempfile.TemporaryDirectory(prefix="ultraconvert-quality-default-") as temporary:
            stage = Path(temporary)
            for target in convert.AUDIO:
                commands = []
                with patch.object(
                    convert, "probe", return_value={"streams": [{"codec_type": "audio"}]}
                ):
                    convert.media_convert(
                        stage / "input.wav",
                        stage / ("output." + target),
                        target,
                        stage,
                        commands.append,
                    )
                output_options = commands[0][commands[0].index("-vn") + 1 : -1]
                self.assertEqual(output_options, audio_before[target])
            for target, expected in (
                ("mp4", ("-crf", "20")),
                ("webm", ("-crf", "30")),
                ("ogv", ("-q:v", "7")),
                ("wmv", ("-b:v", "4M")),
                ("mpg", ("-q:v", "3")),
            ):
                commands = []
                with patch.object(
                    convert, "probe", return_value={"streams": [{"codec_type": "video"}]}
                ):
                    convert.media_convert(
                        stage / "input.mp4",
                        stage / ("output." + target),
                        target,
                        stage,
                        commands.append,
                    )
                key, value = expected
                self.assertEqual(commands[0][commands[0].index(key) + 1], value)
        self.assertEqual(convert.AUDIO, audio_before)


class RealCompressionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="ultraconvert-quality-real-")
        cls.work = Path(cls.temporary.name).resolve()
        cls.image = cls.work / "detailed.png"
        cls.audio = cls.work / "noise.wav"
        cls.video = cls.work / "motion.mp4"
        convert.CANCEL.clear()
        # Detailed, deterministic public synthetic image, rather than relying
        # on a photograph or a blank image with unrepresentative compression.
        convert.run(
            [
                "ffmpeg",
                "-v",
                "error",
                "-f",
                "lavfi",
                "-i",
                "testsrc2=size=512x384:rate=1",
                "-frames:v",
                "1",
                cls.image,
            ]
        )
        convert.run(
            [
                "ffmpeg",
                "-v",
                "error",
                "-f",
                "lavfi",
                "-i",
                "anoisesrc=color=pink:sample_rate=48000:duration=3:seed=42",
                "-ac",
                "2",
                cls.audio,
            ]
        )
        convert.run(
            [
                "ffmpeg",
                "-v",
                "error",
                "-f",
                "lavfi",
                "-i",
                "testsrc2=size=320x240:rate=25:duration=2",
                "-f",
                "lavfi",
                "-i",
                "sine=frequency=440:sample_rate=48000:duration=2",
                "-c:v",
                "libx264",
                "-c:a",
                "aac",
                "-ac",
                "2",
                "-shortest",
                cls.video,
            ]
        )
        cls.originals = {
            path: hashlib.sha256(path.read_bytes()).hexdigest()
            for path in (cls.image, cls.audio, cls.video)
        }
        cls.infos = {path: convert.inspect(path) for path in cls.originals}
        for info in cls.infos.values():
            if info["error"]:
                raise AssertionError(info["error"])

    @classmethod
    def tearDownClass(cls):
        for path, digest in cls.originals.items():
            if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
                raise AssertionError("Quality conversion changed an original")
        cls.temporary.cleanup()

    def encode(self, source, target, quality):
        destination = Path(tempfile.mkdtemp(prefix="output-", dir=self.work))
        result = convert.convert_one(self.infos[source], target, destination, 0, quality=quality)
        self.assertTrue(result["success"], result["error"])
        self.assertEqual(result["quality"], quality)
        self.assertEqual(
            result["quality_applied"], compression.supported(self.infos[source]["category"], target)
        )
        output = next(Path(result["output"]).glob("*." + target))
        self.assertGreater(output.stat().st_size, 0)
        detected = convert.inspect(output)
        self.assertIsNone(detected["error"], detected["error"])
        return output, result, detected

    def test_inspection_exposes_existing_probe_metadata(self):
        image, audio, video = (self.infos[path] for path in (self.image, self.audio, self.video))
        self.assertEqual((image["width"], image["height"]), (512, 384))
        self.assertEqual((video["width"], video["height"]), (320, 240))
        self.assertAlmostEqual(audio["duration"], 3.0, delta=0.1)
        self.assertAlmostEqual(video["duration"], 2.0, delta=0.1)
        for source in self.originals:
            self.assertEqual(self.infos[source]["size_bytes"], source.stat().st_size)

    def test_real_image_quality_changes_output_without_resizing(self):
        for target in ("jpg", "jpeg", "webp", "avif", "heic"):
            with self.subTest(target=target):
                low, _, low_info = self.encode(self.image, target, 10)
                high, _, high_info = self.encode(self.image, target, 95)
                self.assertGreater(high.stat().st_size, low.stat().st_size)
                for info in (low_info, high_info):
                    self.assertEqual((info["width"], info["height"]), (512, 384))

    def test_real_audio_quality_changes_each_encoder_bitrate(self):
        for target in compression.AUDIO_KBPS:
            with self.subTest(target=target):
                low, low_result, _ = self.encode(self.audio, target, 1)
                high, high_result, _ = self.encode(self.audio, target, 100)
                self.assertGreater(high.stat().st_size, low.stat().st_size)
                for result, quality in ((low_result, 1), (high_result, 100)):
                    command = result["commands"][0]["command"]
                    self.assertEqual(
                        command[command.index("-b:a") + 1],
                        f"{compression.audio_bitrate(target, quality)}k",
                    )

    def test_low_sample_rate_mono_voice_uses_real_quality_at_both_endpoints(self):
        source = self.work / "voice-8khz.wav"
        convert.run(
            [
                "ffmpeg",
                "-v",
                "error",
                "-f",
                "lavfi",
                "-i",
                "anoisesrc=color=pink:sample_rate=8000:duration=2:seed=42",
                source,
            ]
        )
        original = hashlib.sha256(source.read_bytes()).hexdigest()
        self.infos[source] = convert.inspect(source)
        for target in compression.AUDIO_KBPS:
            with self.subTest(target=target):
                low, _, _ = self.encode(source, target, 1)
                high, _, _ = self.encode(source, target, 100)
                self.assertGreater(high.stat().st_size, low.stat().st_size)
                for output in (low, high):
                    audio = next(
                        stream
                        for stream in convert.probe(output)["streams"]
                        if stream["codec_type"] == "audio"
                    )
                    self.assertEqual((audio["sample_rate"], audio["channels"]), ("48000", 1))
        self.assertEqual(hashlib.sha256(source.read_bytes()).hexdigest(), original)

    def test_tiny_audio_retains_actual_duration_and_size_without_estimate_claims(self):
        source = self.work / "tiny.wav"
        convert.run(
            [
                "ffmpeg",
                "-v",
                "error",
                "-f",
                "lavfi",
                "-i",
                "sine=frequency=440:sample_rate=48000:duration=0.01",
                source,
            ]
        )
        original = source.read_bytes()
        self.infos[source] = convert.inspect(source)
        self.assertAlmostEqual(self.infos[source]["duration"], 0.01, delta=0.001)
        for target in ("mp3", "aac", "opus"):
            output, _, info = self.encode(source, target, 50)
            self.assertGreater(info["duration"], 0)
            self.assertEqual(info["size_bytes"], output.stat().st_size)
            self.assertNotIn("estimated_size", info)
        self.assertEqual(source.read_bytes(), original)

    def test_real_video_quality_changes_all_supported_encoder_families(self):
        for target in ("mp4", "webm", "ogv", "wmv", "mpg"):
            with self.subTest(target=target):
                low, _, low_info = self.encode(self.video, target, 1)
                high, _, high_info = self.encode(self.video, target, 100)
                self.assertGreater(high.stat().st_size, low.stat().st_size)
                for info in (low_info, high_info):
                    self.assertEqual((info["width"], info["height"]), (320, 240))

    def test_custom_video_quality_keeps_every_other_container_readable(self):
        for target in (
            "mov",
            "mkv",
            "avi",
            "m4v",
            "3gp",
            "flv",
            "ts",
            "mts",
            "m2ts",
            "mpeg",
            "vob",
        ):
            with self.subTest(target=target):
                _, result, info = self.encode(self.video, target, 42)
                self.assertTrue(result["quality_applied"])
                self.assertEqual((info["width"], info["height"]), (320, 240))

    def test_parallel_quality_jobs_do_not_leak_into_each_other_or_defaults(self):
        original_profile = copy.deepcopy(convert.AUDIO["mp3"])
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            outputs = list(
                pool.map(lambda quality: self.encode(self.audio, "mp3", quality), (1, 100))
            )
        self.assertLess(outputs[0][0].stat().st_size, outputs[1][0].stat().st_size)
        self.assertEqual(convert.AUDIO["mp3"], original_profile)
        destination = Path(tempfile.mkdtemp(prefix="default-", dir=self.work))
        result = convert.convert_one(self.infos[self.audio], "mp3", destination, 0)
        self.assertTrue(result["success"], result["error"])
        self.assertNotIn("quality", result)
        command = result["commands"][0]["command"]
        self.assertEqual(command[command.index("-q:a") + 1], "2")
        self.assertNotIn("-b:a", command)

    def test_quality_on_lossless_output_is_explicitly_ignored(self):
        _, result, _ = self.encode(self.audio, "flac", 1)
        self.assertIn("does not apply", result["notes"][-1])
        self.assertNotIn("-b:a", result["commands"][0]["command"])

    def test_skip_same_does_not_reencode_a_lossy_file_to_change_quality(self):
        output, _, info = self.encode(self.audio, "mp3", 50)
        original = output.read_bytes()
        with patch.object(
            convert, "media_convert", side_effect=AssertionError("Must not re-encode")
        ):
            result = convert.convert_one(info, "mp3", output.parent, 1, skip_same=True, quality=100)
        self.assertTrue(result["success"] and result["skipped"])
        self.assertFalse(result["quality_applied"])
        self.assertIsNone(result["output"])
        self.assertIn("without re-encoding", result["notes"][0])
        self.assertEqual(output.read_bytes(), original)

    def test_quality_does_not_bypass_source_change_protection(self):
        source = self.work / "changed-source.wav"
        source.write_bytes(self.audio.read_bytes())
        info = convert.inspect(source)
        with source.open("ab") as changed:
            changed.write(b"changed")
        with patch.object(
            convert, "media_convert", side_effect=AssertionError("Must not encode changed source")
        ):
            result = convert.convert_one(info, "mp3", self.work, 0, quality=80)
        self.assertFalse(result["success"])
        self.assertIn("changed after recognition", result["error"])
        self.assertIsNone(result["output"])

    def test_cli_category_settings_override_global_using_source_category(self):
        destination = Path(tempfile.mkdtemp(prefix="cli-", dir=self.work))
        plan = destination / "plan.json"
        plan.write_text(json.dumps({"audio": "mp3", "image": "jpg", "video": "mp3"}))
        process = subprocess.run(
            [
                sys.executable,
                str(ROOT / "src/convert.py"),
                "--output",
                str(destination),
                "--plan",
                str(plan),
                "--quality",
                "50",
                "--quality-image",
                "12",
                "--quality-audio",
                "24",
                "--quality-video",
                "92",
                "--jobs",
                "3",
                "--",
                str(self.image),
                str(self.audio),
                str(self.video),
            ],
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(process.returncode, 0, process.stderr)
        report = json.loads(process.stdout.splitlines()[-1])
        self.assertEqual((report["success"], report["failed"]), (3, 0))
        expected = {"image": 12, "audio": 24, "video": 92}
        self.assertEqual(
            {result["category"]: result["quality"] for result in report["results"]}, expected
        )
        self.assertTrue(all(result["quality_applied"] for result in report["results"]))

    def test_cli_invalid_quality_rejected_before_creating_any_output(self):
        destination = self.work / "must-not-exist"
        for flag in ("--quality", "--quality-image", "--quality-audio", "--quality-video"):
            for quality in ("0", "101", "1.5", "-1"):
                process = subprocess.run(
                    [
                        sys.executable,
                        str(ROOT / "src/convert.py"),
                        "--output",
                        str(destination),
                        "--to",
                        "mp3",
                        flag,
                        quality,
                        "--",
                        str(self.audio),
                    ],
                    text=True,
                    capture_output=True,
                    check=False,
                )
                self.assertEqual(process.returncode, 2)
                self.assertFalse(destination.exists())

    def test_cli_global_quality_is_fallback_and_unsupported_targets_are_explicit(self):
        destination = Path(tempfile.mkdtemp(prefix="fallback-", dir=self.work))
        config = destination / "example.json"
        config.write_text('{"keep":true}')
        plan = destination / "plan.json"
        plan.write_text(json.dumps({"audio": "mp3", "image": "jpg", "config": "yaml"}))
        process = subprocess.run(
            [
                sys.executable,
                str(ROOT / "src/convert.py"),
                "--output",
                str(destination),
                "--plan",
                str(plan),
                "--quality",
                "60",
                "--quality-image",
                "15",
                "--",
                str(self.image),
                str(self.audio),
                str(config),
            ],
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(process.returncode, 0, process.stderr)
        results = {
            result["category"]: result
            for result in json.loads(process.stdout.splitlines()[-1])["results"]
        }
        self.assertEqual(
            {category: result["quality"] for category, result in results.items()},
            {"image": 15, "audio": 60, "config": 60},
        )
        self.assertTrue(results["image"]["quality_applied"] and results["audio"]["quality_applied"])
        self.assertFalse(results["config"]["quality_applied"])
        self.assertIn("does not apply", results["config"]["notes"][-1])
        self.assertEqual(config.read_text(), '{"keep":true}')


if __name__ == "__main__":
    unittest.main()
