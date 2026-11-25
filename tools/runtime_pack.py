"""Remove only the executable-key XOR layer from an SSU PCK.

The installed Anemoi runtime expects scn_data_exe_angou_mod == 0. All
scene sizes, LZSS data, package tables and embedded sources remain intact.
No game/runtime files are changed unless explicitly supplied as output.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib
import json
from pathlib import Path
import struct

C = importlib.import_module('siglus_ssu.const')
PCK = importlib.import_module('siglus_ssu.pck')
COMMON = importlib.import_module('siglus_ssu.common')
NATIVE = importlib.import_module('siglus_ssu.native_ops')


def convert(input_path: Path, output_path: Path, angou_path: Path | None = None) -> dict:
    original = input_path.read_bytes()
    if not PCK.looks_like_pck(original):
        raise ValueError('Input is not a recognized Siglus PCK')
    header = COMMON.parse_i32_header(original, C.PACK_HDR_FIELDS, C.PACK_HDR_SIZE)
    names, encoded = PCK._read_pck_scene_lists(original, header)
    if len(names) != header['scn_data_cnt'] or len(encoded) != len(names):
        raise ValueError('Scene table is incomplete')
    indices = COMMON.read_struct_list(
        original, header['scn_data_index_list_ofs'], header['scn_data_index_cnt'],
        COMMON.I32_PAIR_STRUCT,
    )
    if len(indices) != len(names):
        raise ValueError('Scene data index is incomplete')
    key = b''
    if header['scn_data_exe_angou_mod']:
        if angou_path and angou_path.is_file():
            key = COMMON.angou_to_exe_el(COMMON.read_angou_first_line(str(angou_path)))
        else:
            key = PCK._resolve_pck_scene_exe_el(
                original, input_pck=str(input_path), hdr=header,
                scn_data=encoded, trace_key=False,
            )
        if len(key) != 16:
            raise ValueError('No valid executable XOR key source; use --angou PATH')
    result = bytearray(original)
    verified = []
    output_header = dict(header)
    output_header['scn_data_exe_angou_mod'] = 0
    data_base = header['scn_data_list_ofs']
    ranges = []
    for name, scene, (offset, size) in zip(names, encoded, indices):
        absolute = data_base + offset
        if offset < 0 or size < 0 or absolute + size > len(original):
            raise ValueError(f'Invalid scene span: {name}')
        before = PCK._decode_scene_blob(scene, header, key, require_exe=True)
        if not before or not COMMON.looks_like_siglus_dat(before):
            raise ValueError(f'Input scene does not decode: {name}')
        changed = bytearray(scene)
        if key:
            NATIVE.xor_cycle_inplace(changed, key, 0)
        after = PCK._decode_scene_blob(bytes(changed), output_header, require_exe=True)
        if before != after:
            raise ValueError(f'Decoded scene changed: {name}')
        result[absolute:absolute + size] = changed
        ranges.append((absolute, absolute + size))
        verified.append({'scene': name, 'dat_sha256': hashlib.sha256(before).hexdigest(),
                         'encoded_size': size, 'decoded_size': len(before)})
    flag_offset = C.PACK_HDR_FIELDS.index('scn_data_exe_angou_mod') * 4
    struct.pack_into('<i', result, flag_offset, 0)
    # Every byte outside the scene payloads and this one header integer must
    # remain untouched, including all include/route tables and OS chunks.
    ranges.append((flag_offset, flag_offset + 4))
    cursor = 0
    for start, end in sorted(ranges):
        if result[cursor:start] != original[cursor:start]:
            raise AssertionError('Unrelated package data was changed')
        cursor = max(cursor, end)
    if result[cursor:] != original[cursor:]:
        raise AssertionError('Package tail was changed')
    if len(result) != len(original):
        raise AssertionError('Package length was changed')
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(result)
    report = {
        'input': input_path.name, 'output': output_path.name,
        'input_sha256': hashlib.sha256(original).hexdigest(),
        'output_sha256': hashlib.sha256(result).hexdigest(),
        'bytes': len(result), 'input_exe_xor_flag': header['scn_data_exe_angou_mod'],
        'output_exe_xor_flag': 0, 'scene_count': len(verified),
        'all_decoded_scenes_identical': True, 'all_other_package_bytes_identical': True,
        'scenes': verified,
    }
    output_path.with_suffix('.verification.json').write_text(
        json.dumps(report, ensure_ascii=False, indent=2), encoding='utf8',
    )
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('input', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--angou', type=Path,
                        default=Path(__file__).resolve().parents[1] / 'scene' / '暗号.dat')
    args = parser.parse_args()
    report = convert(args.input, args.output, args.angou)
    print(json.dumps({k: v for k, v in report.items() if k != 'scenes'}, ensure_ascii=False))


if __name__ == '__main__':
    main()
