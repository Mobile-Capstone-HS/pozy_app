from __future__ import annotations

import argparse
import csv
import json
from collections import Counter
from pathlib import Path
from typing import Any

from src.acut_contact_sheet import generate_contact_sheet_for_candidate


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Generate MUSIQ-inspired multi-scale A-cut contact sheets without external APIs.",
    )
    parser.add_argument("--input-topk", required=True, help="Top-k CSV or JSON file.")
    parser.add_argument("--output-dir", default="outputs/acut_contact_sheets")
    parser.add_argument("--top-k", type=int, default=5)
    parser.add_argument("--jpeg-quality", type=int, default=85)
    parser.add_argument("--max-sheet-long-side", type=int, default=1600)
    args = parser.parse_args()

    candidates = load_candidates(Path(args.input_topk))
    candidates = sort_and_limit_candidates(candidates, args.top_k)

    summary: dict[str, Any] = {
        "candidates_processed": len(candidates),
        "sheets_generated": 0,
        "missing_image_paths": 0,
        "missing_images": [],
        "errors": [],
        "missing_metadata_types": Counter(),
        "fallback_counts_by_type": Counter(),
        "outputs": [],
    }

    for index, candidate in enumerate(candidates, start=1):
        if not any(candidate.get(key) for key in ("image_path", "path", "file_path")):
            summary["missing_image_paths"] += 1
            summary["errors"].append({"index": index, "error": "missing_image_path"})
            continue

        try:
            metadata = generate_contact_sheet_for_candidate(
                candidate,
                args.output_dir,
                jpeg_quality=args.jpeg_quality,
                max_sheet_long_side=args.max_sheet_long_side,
            )
        except FileNotFoundError as exc:
            summary["missing_images"].append(str(exc))
            summary["errors"].append({"index": index, "error": f"missing_image: {exc}"})
            continue
        except Exception as exc:  # Keep one bad candidate from stopping a batch.
            summary["errors"].append({"index": index, "error": str(exc)})
            continue

        summary["sheets_generated"] += 1
        summary["outputs"].append(
            {
                "candidate_id": metadata["candidate_id"],
                "contact_sheet_path": metadata["contact_sheet_path"],
                "metadata_path": str(Path(metadata["contact_sheet_path"]).with_suffix(".json")),
            }
        )
        summary["missing_metadata_types"].update(metadata.get("metadata_missing", []))
        for source in metadata.get("crop_source", {}).values():
            if isinstance(source, str) and source.startswith("fallback_"):
                summary["fallback_counts_by_type"].update([source])

    printable = {
        **summary,
        "missing_metadata_types": dict(summary["missing_metadata_types"]),
        "fallback_counts_by_type": dict(summary["fallback_counts_by_type"]),
    }
    print(json.dumps(printable, ensure_ascii=False, indent=2))
    return 0 if summary["errors"] == [] else 1


def load_candidates(path: Path) -> list[dict[str, Any]]:
    suffix = path.suffix.lower()
    if suffix == ".csv":
        with path.open("r", encoding="utf-8-sig", newline="") as handle:
            return [dict(row) for row in csv.DictReader(handle)]

    with path.open("r", encoding="utf-8") as handle:
        raw = json.load(handle)
    rows = _extract_rows(raw)
    if not isinstance(rows, list):
        raise ValueError("JSON input must be a list or contain a candidates/items/results/rankedItems list")
    return [row for row in rows if isinstance(row, dict)]


def sort_and_limit_candidates(candidates: list[dict[str, Any]], top_k: int) -> list[dict[str, Any]]:
    def rank_value(row: dict[str, Any]) -> tuple[int, int]:
        raw = row.get("rank", row.get("primary_rank"))
        try:
            return (0, int(raw))
        except (TypeError, ValueError):
            return (1, 1 << 30)

    selected = sorted(candidates, key=rank_value)
    if top_k > 0:
        return selected[:top_k]
    return selected


def _extract_rows(raw: Any) -> Any:
    if isinstance(raw, list):
        return raw
    if isinstance(raw, dict):
        for key in ("candidates", "items", "results", "rankedItems", "ranked_items", "topk", "top_k"):
            value = raw.get(key)
            if isinstance(value, list):
                return value
    return raw


if __name__ == "__main__":
    raise SystemExit(main())
