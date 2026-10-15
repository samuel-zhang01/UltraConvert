"""Optional lossy encoding profiles. Omitted quality keeps existing defaults.

The slider is an integer from 1 (smaller) to 100 (higher quality), not a
percentage of the original file's size. Profiles use the encoders' native
quality or target-bitrate controls; a result is never promised a fixed size.
"""

import math

IMAGE_TARGETS = frozenset({"jpg", "jpeg", "webp", "avif", "heic"})
AUDIO_KBPS = {
    "mp3": (64, 96, 128, 160, 192, 256, 320),
    "aac": (48, 64, 96, 128, 160, 192, 256, 320),
    "m4a": (48, 64, 96, 128, 160, 192, 256, 320),
    "wma": (48, 64, 96, 128, 160, 192, 256, 320),
    "opus": (24, 32, 48, 64, 96, 128, 160, 192, 256),
    "ogg": (64, 80, 96, 112, 128, 160, 192),
}
H264_TARGETS = frozenset({"mp4", "mov", "mkv", "avi", "m4v", "3gp", "flv", "ts", "mts", "m2ts"})
VIDEO_TARGETS = H264_TARGETS | {"webm", "ogv", "wmv", "mpg", "mpeg", "vob"}


def validate_quality(value):
    if value is not None and (type(value) is not int or not 1 <= value <= 100):
        raise ValueError("Quality must be a whole number from 1 to 100")
    return value


def supported(category, target):
    if category == "image":
        return target in IMAGE_TARGETS
    if category == "audio":
        return target in AUDIO_KBPS
    if category == "video":
        return target in VIDEO_TARGETS or target in AUDIO_KBPS
    return False


def scale(quality, low, high):
    """Integer interpolation, rounded consistently without floating point.

    For descending scales, round the positive distance first. Swift clients
    can mirror this exact formula; endpoints are always inclusive.
    """
    validate_quality(quality)
    if quality is None:
        raise ValueError("A quality value is required")
    distance = ((quality - 1) * abs(high - low) + 49) // 99
    return low + distance if high >= low else low - distance


def audio_bitrate(target, quality):
    validate_quality(quality)
    values = AUDIO_KBPS.get(target)
    if values is None or quality is None:
        return None
    return values[scale(quality, 0, len(values) - 1)]


def image_options(target, quality):
    validate_quality(quality)
    if quality is None or target not in IMAGE_TARGETS:
        return []
    options = ["-quality", str(quality)]
    if target == "webp":
        # ImageMagick otherwise changes quality=100 into lossless mode.
        options += ["-define", "webp:lossless=false"]
    return options


def audio_options(target, quality):
    """Return a complete custom audio profile or None for the existing profile."""
    bitrate = audio_bitrate(target, quality)
    if bitrate is None:
        return None
    codec = {"mp3": "libmp3lame", "opus": "libopus", "ogg": "libvorbis", "wma": "wmav2"}.get(
        target, "aac"
    )
    # A fixed supported rate avoids silent bitrate caps on 8/16 kHz voice notes.
    # Channel count is preserved; resampling cannot restore missing detail.
    options = ["-c:a", codec, "-b:a", f"{bitrate}k", "-ar", "48000"]
    if target == "aac":
        options += ["-f", "adts"]
    elif target == "m4a":
        options += ["-f", "ipod"]
    elif target == "wma":
        options += ["-f", "asf"]
    return options


def video_options(target, quality):
    """Overrides for the existing video profile; GIF/MXF stay fixed profiles."""
    validate_quality(quality)
    if quality is None or target not in VIDEO_TARGETS:
        return []
    if target in H264_TARGETS:
        return [
            "-crf",
            str(scale(quality, 36, 16)),
            "-b:a",
            f"{audio_bitrate('aac', quality)}k",
            "-ar",
            "48000",
        ]
    if target == "webm":
        return [
            "-crf",
            str(scale(quality, 48, 20)),
            "-b:v",
            "0",
            "-b:a",
            f"{audio_bitrate('opus', quality)}k",
            "-ar",
            "48000",
        ]
    if target == "ogv":
        return [
            "-q:v",
            str(scale(quality, 2, 10)),
            "-b:a",
            f"{audio_bitrate('ogg', quality)}k",
            "-ar",
            "48000",
        ]
    if target == "wmv":
        return [
            "-b:v",
            f"{scale(quality, 500, 8000)}k",
            "-b:a",
            f"{audio_bitrate('wma', quality)}k",
            "-ar",
            "48000",
        ]
    rates = (64, 96, 128, 160, 192, 256, 320, 384)
    return [
        "-q:v",
        str(scale(quality, 15, 2)),
        "-b:a",
        f"{rates[scale(quality, 0, len(rates) - 1)]}k",
    ]


def override_options(options, overrides):
    """Replace named output controls, retaining profile-specific muxer flags."""
    if not overrides:
        return options
    keys = set(overrides[::2])
    result = []
    for key, value in zip(options[::2], options[1::2], strict=True):
        if key not in keys:
            result.extend((key, value))
    return result + overrides


def note(category, target, quality):
    validate_quality(quality)
    if quality is None:
        return None
    if not supported(category, target):
        return f"Custom quality does not apply to {target.upper()}; its standard profile is used."
    if target in AUDIO_KBPS and category in ("audio", "video"):
        return f"Custom quality {quality}/100 uses a {audio_bitrate(target, quality)} kbps target audio bitrate at 48 kHz with the original channel count. Actual size varies with content and container overhead. Higher quality cannot restore source detail."
    if category == "video":
        return f"Custom quality {quality}/100 uses the codec's video quality and audio bitrate controls. Audio uses 48 kHz. Output size depends on the content; higher quality cannot restore source detail."
    return f"Custom quality {quality}/100 uses the codec's quality controls. Output size depends on the content; 100 does not restore source detail or guarantee lossless output."


def media_metadata(media):
    """Use the existing guarded FFprobe result; never launch a second probe."""
    result = {}
    streams = media.get("streams", [])
    durations = [
        media.get("format", {}).get("duration"),
        *(stream.get("duration") for stream in streams),
    ]
    for raw in durations:
        if type(raw) not in (str, int, float):
            continue
        try:
            duration = float(raw)
            if math.isfinite(duration) and 0 < duration <= 1e12:
                result["duration"] = duration
                break
        except ValueError, TypeError, OverflowError:
            continue
    for stream in streams:
        if stream.get("codec_type") == "video" and not stream.get("disposition", {}).get(
            "attached_pic"
        ):
            for key in ("width", "height"):
                value = stream.get(key)
                if type(value) is int and 0 < value <= 1_000_000:
                    result[key] = value
            break
    for stream in streams:
        if stream.get("codec_type") == "audio":
            channels = stream.get("channels")
            if type(channels) is int and 0 < channels <= 1024:
                result["channels"] = channels
            break
    return result
