#!/usr/bin/env python3
"""Compare ResolutionLab exports and inspect SDR PNG files without contacting the phone."""

import argparse
import hashlib
import json
import struct
import zlib
from datetime import datetime
from pathlib import Path


class EvidenceError(ValueError):
    """An input cannot be used as comparable evidence."""


FORMAT = "resolutionlab.display-report"
SCOPE = "UIKit da cena do processo"
REPORT_LIMIT = 128 * 1024
IMAGE_LIMIT = 64 * 1024 * 1024
ENVIRONMENT = ("machine", "osVersion", "build", "orientation", "appVersion", "sourceRevision")
GEOMETRY = ("bounds", "nativeBounds", "currentMode", "availableModes", "scale", "nativeScale",
            "fixedCoordinateSpace", "sceneBounds")
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def _read(path, limit):
    if not path.is_file():
        raise EvidenceError(f"Arquivo regular esperado em {path.name}.")
    with path.open("rb") as file:
        data = file.read(limit + 1)
    if len(data) > limit:
        raise EvidenceError(f"{path.name} excede o limite de {limit} bytes.")
    return data


def _unique_keys(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise EvidenceError(f"Chave JSON duplicada: {key}.")
        result[key] = value
    return result


def _invalid_number(value):
    raise EvidenceError(f"Número inválido em JSON: {value}.")


def read_report(path):
    data = _read(path, REPORT_LIMIT)
    try:
        report = json.loads(data, object_pairs_hook=_unique_keys, parse_constant=_invalid_number)
    except (UnicodeError, ValueError, RecursionError) as error:
        raise EvidenceError(f"JSON inválido em {path.name}: {error}") from error
    return report, {"file": path.name, "sha256": hashlib.sha256(data).hexdigest()}


def _size(value, field):
    if not isinstance(value, dict):
        raise EvidenceError(f"Dimensões ausentes ou inválidas em {field}.")
    for axis in ("width", "height"):
        number = value.get(axis)
        if type(number) not in (int, float) or not 0 < number <= 65_536:
            raise EvidenceError(f"Dimensão inválida em {field}.{axis}.")
    return {"width": value["width"], "height": value["height"]}


def _envelope(report):
    if (
        not isinstance(report, dict)
        or report.get("format") != FORMAT
        or type(report.get("schema")) is not int
        or report["schema"] != 1
        or report.get("status") != "READ_ONLY"
        or report.get("measurementScope") != SCOPE
    ):
        raise EvidenceError("O arquivo precisa ser uma exportação ResolutionLab de leitura, esquema 1.")


def _capture(sample, phase):
    if not isinstance(sample, dict) or sample.get("phase") != phase or sample.get("historical") is not None:
        raise EvidenceError(f"Coleta ao vivo esperada na etapa {phase}.")

    environment = {key: sample.get(key) for key in ENVIRONMENT}
    if any(not isinstance(value, str) or not value.strip() for value in environment.values()):
        raise EvidenceError("Identificação, build, orientação e versão do app são necessárias para comparar.")
    if environment["orientation"] not in {"portrait", "landscape"}:
        raise EvidenceError("Orientação inválida.")
    try:
        timestamp = datetime.fromisoformat(sample["capturedAt"])
    except (KeyError, TypeError, ValueError) as error:
        raise EvidenceError("O horário da captura é inválido.") from error
    if timestamp.utcoffset() is None:
        raise EvidenceError("O horário da coleta precisa incluir um fuso.")

    geometry = sample.get("geometry")
    if not isinstance(geometry, dict):
        raise EvidenceError("Geometria da coleta ausente.")
    measured = {key: _size(geometry.get(key), key) for key in ("bounds", "nativeBounds")}
    for key in ("currentMode", "fixedCoordinateSpace", "sceneBounds"):
        value = geometry.get(key)
        measured[key] = None if value is None else _size(value, key)

    modes = geometry.get("availableModes")
    if not isinstance(modes, list) or len(modes) > 64:
        raise EvidenceError("Lista de modos inválida.")
    unique = {tuple(_size(mode, "availableModes").values()) for mode in modes}
    measured["availableModes"] = [dict(width=width, height=height) for width, height in sorted(unique)] or None
    for key in ("scale", "nativeScale"):
        number = geometry.get(key)
        if type(number) not in (int, float) or not 0 < number <= 16:
            raise EvidenceError(f"Escala inválida em {key}.")
        measured[key] = number

    return timestamp, environment, measured


def _comparison(before, after):
    if before is None or after is None:
        return "unavailable"
    return "equal" if before == after else "different"


def compare_reports(before, after):
    """Check device context and separate geometry measurements from boot claims."""
    _envelope(before)
    _envelope(after)
    if before.get("latest") is not None:
        raise EvidenceError("O primeiro arquivo deve conter somente a referência da coleta.")
    reference = before.get("reference")
    latest = after.get("latest")
    paired = latest is not None
    if paired and reference != after.get("reference"):
        raise EvidenceError("A referência embutida no segundo arquivo difere da primeira coleta.")

    time_a, environment, geometry_a = _capture(reference, "beforeRestart")
    time_b, other, geometry_b = _capture(
        latest if paired else after.get("reference"),
        "afterReportedRestart" if paired else "beforeRestart",
    )
    differences = [name for name in ENVIRONMENT if environment[name] != other[name]]
    if differences:
        raise EvidenceError("Ambientes diferentes em " + ", ".join(differences) + ".")
    if time_b <= time_a:
        raise EvidenceError("A segunda coleta precisa ser posterior à primeira.")

    return {
        "schema": 1,
        "measurementScope": SCOPE,
        "environment": environment,
        "pairing": {
            "kind": "embedded_reference" if paired else "independent_exports",
            "restartEvidence": "operator_reported" if paired else "not_recorded",
            "beforeCapturedAt": time_a.isoformat(),
            "afterCapturedAt": time_b.isoformat(),
            "wallClockIntervalSeconds": (time_b - time_a).total_seconds(),
        },
        "geometry": {
            name: {
                "before": geometry_a[name],
                "after": geometry_b[name],
                "comparison": _comparison(geometry_a[name], geometry_b[name]),
            }
            for name in GEOMETRY
        },
        "globalCanvasEvidence": "unverified",
    }


def png_dimensions(data):
    """Read PNG raster size and validate the chunk structure and CRCs."""
    if not data.startswith(PNG_SIGNATURE):
        raise EvidenceError("A captura precisa estar em PNG (captura SDR).")
    offset = len(PNG_SIGNATURE)
    view = memoryview(data)
    width = height = 0
    image_data = False
    while offset + 12 <= len(data):
        size, kind = struct.unpack_from(">I4s", view, offset)
        end = offset + 8 + size
        if end + 4 > len(data):
            raise EvidenceError("Chunk PNG truncado.")
        crc, = struct.unpack_from(">I", view, end)
        if zlib.crc32(view[offset + 4:end]) != crc:
            raise EvidenceError("CRC inválido em chunk PNG.")
        if offset == len(PNG_SIGNATURE) and kind != b"IHDR":
            raise EvidenceError("O primeiro chunk PNG precisa ser IHDR.")
        if kind == b"IHDR":
            if size != 13 or width:
                raise EvidenceError("Cabeçalho IHDR inválido no PNG.")
            width, height = struct.unpack_from(">II", view, offset + 8)
            if not (0 < width < 2**31 and 0 < height < 2**31):
                raise EvidenceError("Dimensões inválidas no PNG.")
        elif kind == b"IDAT":
            image_data |= size > 0
        elif kind == b"IEND":
            if size != 0 or not image_data or end + 4 != len(data):
                raise EvidenceError("Fim inválido ou dados de imagem ausentes no PNG.")
            return width, height
        offset = end + 4
    raise EvidenceError("PNG incompleto.")


def inspect_png(path):
    data = _read(path, IMAGE_LIMIT)
    width, height = png_dimensions(data)
    return {"file": path.name, "format": "PNG", "width": width, "height": height,
            "sha256": hashlib.sha256(data).hexdigest(), "scope": "encoded_image_raster"}


def measure_pair(before, after, images):
    report_a, file_a = read_report(before)
    report_b, file_b = read_report(after)
    result = compare_reports(report_a, report_b)
    result["reportFiles"] = {"before": file_a, "after": file_b}
    result["screenshots"] = {}
    for surface, paths in images.items():
        first, second = (inspect_png(path) for path in paths)
        shape_a = first["width"], first["height"]
        shape_b = second["width"], second["height"]
        result["screenshots"][surface] = {
            "before": first, "after": second, "source": "operator_named",
            "sizeComparison": _comparison(shape_a, shape_b),
        }
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    compare = commands.add_parser("compare", help="Comparar dois relatórios ResolutionLab.")
    compare.add_argument("before", type=Path)
    compare.add_argument("after", type=Path)
    for surface in ("home", "settings", "app"):
        compare.add_argument(f"--{surface}", type=Path, nargs=2, metavar=("ANTES", "DEPOIS"))
    image = commands.add_parser("png", help="Conferir dimensões e SHA-256 de um PNG.")
    image.add_argument("path", type=Path)
    args = parser.parse_args()
    try:
        if args.command == "png":
            result = inspect_png(args.path)
        else:
            images = {surface: args.__dict__[surface] for surface in ("home", "settings", "app")
                      if args.__dict__[surface] is not None}
            result = measure_pair(args.before, args.after, images)
    except (EvidenceError, OSError) as error:
        parser.exit(2, f"{error}\n")
    print(json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False))


if __name__ == "__main__":
    main()
