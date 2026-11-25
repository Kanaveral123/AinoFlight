"""Create RPM variants from the game's original Vorbis motor loop.

Only the Vorbis identification sample-rate field and its enclosing Ogg page's
CRC change. The compressed audio packets remain byte-for-byte original. This
is ordinary playback-rate reinterpretation, giving both pitch and RPM change
without adding a decoder/encoder dependency or replacing an original asset.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parents[1]


def ogg_crc(data: bytes) -> int:
    crc = 0
    for byte in data:
        crc ^= byte << 24
        for _ in range(8):
            crc = ((crc << 1) ^ (0x04C11DB7 if crc & 0x80000000 else 0)) & 0xFFFFFFFF
    return crc


def pages(data: bytes):
    offset = 0
    while offset < len(data):
        if data[offset:offset + 4] != b'OggS':
            raise ValueError(f'Not an Ogg page at {offset}')
        segments = data[offset + 26]
        header_end = offset + 27 + segments
        end = header_end + sum(data[offset + 27:header_end])
        if end > len(data):
            raise ValueError('Truncated Ogg page')
        yield offset, header_end, end
        offset = end


def change_rate(original: bytes, ratio: float) -> tuple[bytes, int, int]:
    result = bytearray(original)
    changed_span = None
    before_rate = after_rate = 0
    for start, body, end in pages(original):
        # Vorbis identification packet is the first packet on its own BOS page.
        if original[body:body + 7] == b'\x01vorbis':
            before_rate = struct.unpack_from('<I', original, body + 12)[0]
            after_rate = round(before_rate * ratio)
            struct.pack_into('<I', result, body + 12, after_rate)
            result[start + 22:start + 26] = b'\0' * 4
            struct.pack_into('<I', result, start + 22, ogg_crc(result[start:end]))
            changed_span = (start, body, end)
            break
    if changed_span is None:
        raise ValueError('No Vorbis identification packet')
    allowed = set(range(changed_span[0] + 22, changed_span[0] + 26))
    allowed.update(range(changed_span[1] + 12, changed_span[1] + 16))
    assert len(original) == len(result)
    assert all(a == b or i in allowed for i, (a, b) in enumerate(zip(original, result)))
    for start, _, end in pages(result):
        page = bytearray(result[start:end])
        expected = struct.unpack_from('<I', page, 22)[0]
        page[22:26] = b'\0' * 4
        assert ogg_crc(page) == expected
    return bytes(result), before_rate, after_rate


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--game', type=Path, default=ROOT.parent / 'game',
                        help='game folder holding the original wav/ (default: ../game)')
    parser.add_argument('--output', type=Path, default=ROOT / 'assets/wav')
    args = parser.parse_args()
    original_path = args.game / 'wav' / 'ANB_airplane_motor_LOOP.ogg'
    original = original_path.read_bytes()
    source_hash = hashlib.sha256(original).hexdigest()
    args.output.mkdir(parents=True, exist_ok=True)
    report = {'source': 'wav/' + original_path.name, 'source_sha256': source_hash,
              'method': 'Vorbis playback-rate reinterpretation; audio packets unchanged',
              'variants': []}
    for name, ratio in [('FL_engine_low', 0.72), ('FL_engine_high', 1.32)]:
        data, before, after = change_rate(original, ratio)
        target = args.output / (name + '.ogg')
        target.write_bytes(data)
        report['variants'].append({'name': name, 'ratio': ratio,
                                   'original_rate_hz': before, 'rate_hz': after,
                                   'bytes': len(data), 'all_page_crcs_valid': True,
                                   'audio_packets_unchanged': True,
                                   'sha256': hashlib.sha256(data).hexdigest()})
    assert hashlib.sha256(original_path.read_bytes()).hexdigest() == source_hash
    out = ROOT / 'build/audio-assets.json'
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(report, indent=2), encoding='utf8')
    print(json.dumps({'assets': [v['name'] for v in report['variants']],
                      'original_unchanged': True, 'report': 'build/' + out.name}))


if __name__ == '__main__':
    main()
