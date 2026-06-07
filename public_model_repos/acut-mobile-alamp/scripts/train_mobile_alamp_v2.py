# 모바일 A-LAMP v2 모델을 학습하거나 스모크 검증한다.
from __future__ import annotations

import argparse
import csv
import json
import logging
import math
import os
import sys
from pathlib import Path
from typing import Any

import numpy as np
import tensorflow as tf
from PIL import Image

from src.models.mobile_alamp_v2 import build_mobile_alamp_v2_model


DEFAULT_TRAIN_PATCH_JSONL = (
    "outputs/alamp_paper_mpnet_patch_selector_v4_20260512/subsets/"
    "train_patch_boxes_4096_v4.jsonl"
)
DEFAULT_VAL_PATCH_JSONL = (
    "outputs/alamp_paper_mpnet_patch_selector_v4_20260512/subsets/"
    "val_patch_boxes_4096_v4.jsonl"
)
DEFAULT_OUTPUT_DIR = "outputs/mobile_alamp_v2_4096_smoke"
PREPROCESSING_MODE = "mobilenetv3_include_preprocessing_float_pixels_0_255"


def _load_jsonl_records(path: Path, max_samples: int | None = None) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    with path.open("r", encoding="utf-8") as handle:
        for line in handle:
            records.append(json.loads(line))
            if max_samples is not None and len(records) >= max_samples:
                break
    return records


def _record_image_path(record: dict[str, Any]) -> Path | None:
    value = record.get("resolved_image_path") or record.get("image_path")
    if not value:
        return None
    path = Path(str(value))
    return path if path.exists() else None


def _label_from_score(record: dict[str, Any], label_threshold: float) -> np.ndarray:
    score = float(record.get("mean_score", 0.0))
    label = 1.0 if score > label_threshold else 0.0
    return np.asarray([label], dtype=np.float32)


def _label_summary(records: list[dict[str, Any]], label_threshold: float) -> dict[str, Any]:
    labels = [
        float(_label_from_score(record, label_threshold)[0])
        for record in records
    ]
    positives = int(sum(1 for value in labels if value == 1.0))
    negatives = int(sum(1 for value in labels if value == 0.0))
    return {
        "total": len(labels),
        "positive": positives,
        "negative": negatives,
        "label_threshold": float(label_threshold),
    }


def _class_weights_from_summary(
    label_summary: dict[str, Any],
    mode: str,
) -> dict[int, float] | None:
    if mode == "none":
        return None
    negative_count = int(label_summary["negative"])
    positive_count = int(label_summary["positive"])
    total = int(label_summary["total"])
    if negative_count == 0 or positive_count == 0:
        logging.warning("Class weighting disabled because one class has zero samples.")
        return None
    return {
        0: total / (2.0 * negative_count),
        1: total / (2.0 * positive_count),
    }


def _load_full_image(path: Path, image_size: int) -> np.ndarray:
    with Image.open(path) as image:
        image = image.convert("RGB").resize((image_size, image_size), Image.BILINEAR)
        return np.asarray(image, dtype=np.float32)


def _load_patch_crops(
    record: dict[str, Any],
    image_path: Path,
    patch_size: int,
    patch_count: int,
) -> np.ndarray | None:
    try:
        with Image.open(image_path) as image:
            image = image.convert("RGB")
            width, height = image.size
            boxes = record.get("boxes_abs_xyxy")
            if not boxes:
                norm_boxes = record.get("boxes_norm_xyxy", [])
                boxes = [
                    [box[0] * width, box[1] * height, box[2] * width, box[3] * height]
                    for box in norm_boxes
                ]
            if len(boxes) < patch_count:
                return None

            crops = []
            for index in range(patch_count):
                box = boxes[index]
                crop = image.crop((int(box[0]), int(box[1]), int(box[2]), int(box[3])))
                crop = crop.resize((patch_size, patch_size), Image.BILINEAR)
                crops.append(np.asarray(crop, dtype=np.float32))
        return np.asarray(crops, dtype=np.float32)
    except Exception as exc:
        logging.warning("Skipping image %s because crop loading failed: %s", image_path, exc)
        return None


def _iter_loaded_examples(
    records: list[dict[str, Any]],
    image_size: int,
    patch_size: int,
    patch_count: int,
    label_threshold: float,
):
    skipped = 0
    for record in records:
        image_path = _record_image_path(record)
        if image_path is None:
            skipped += 1
            continue

        patches = _load_patch_crops(
            record,
            image_path=image_path,
            patch_size=patch_size,
            patch_count=patch_count,
        )
        if patches is None:
            skipped += 1
            continue

        full_image = _load_full_image(image_path, image_size=image_size)
        yield {
            "patches": patches.astype(np.float32),
            "full_image": full_image.astype(np.float32),
        }, _label_from_score(record, label_threshold), str(image_path)

    if skipped:
        logging.info("Skipped %s unusable records while loading examples.", skipped)


def _make_dataset(
    records: list[dict[str, Any]],
    image_size: int,
    patch_size: int,
    patch_count: int,
    batch_size: int,
    label_threshold: float,
    training: bool,
) -> tf.data.Dataset:
    def generator():
        for inputs, label, _image_path in _iter_loaded_examples(
            records,
            image_size=image_size,
            patch_size=patch_size,
            patch_count=patch_count,
            label_threshold=label_threshold,
        ):
            yield inputs, label

    dataset = tf.data.Dataset.from_generator(
        generator,
        output_signature=(
            {
                "patches": tf.TensorSpec(
                    shape=(patch_count, patch_size, patch_size, 3),
                    dtype=tf.float32,
                ),
                "full_image": tf.TensorSpec(
                    shape=(image_size, image_size, 3),
                    dtype=tf.float32,
                ),
            },
            tf.TensorSpec(shape=(1,), dtype=tf.float32),
        ),
    )
    if training:
        dataset = dataset.shuffle(
            min(len(records), 256),
            seed=123,
            reshuffle_each_iteration=True,
        )
    return dataset.batch(batch_size).prefetch(tf.data.AUTOTUNE)


def _history_rows(history: tf.keras.callbacks.History) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    metric_names = list(history.history.keys())
    if not metric_names:
        return rows
    for index in range(len(history.history[metric_names[0]])):
        row = {"epoch": index + 1}
        for metric_name in metric_names:
            row[metric_name] = float(history.history[metric_name][index])
        rows.append(row)
    return rows


def _final_metrics(history: tf.keras.callbacks.History) -> dict[str, float]:
    metrics: dict[str, float] = {}
    for key, values in history.history.items():
        if values:
            metrics[key] = float(values[-1])
    return metrics


def _write_training_log(path: Path, rows: list[dict[str, Any]]) -> None:
    if not rows:
        path.write_text("", encoding="utf-8")
        return
    fieldnames = list(rows[0].keys())
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def _binary_roc_auc(y_true: np.ndarray, y_pred: np.ndarray) -> float | None:
    labels = y_true.astype(np.int32)
    positive_count = int(np.sum(labels == 1))
    negative_count = int(np.sum(labels == 0))
    if positive_count == 0 or negative_count == 0:
        return None

    order = np.argsort(y_pred)
    ranks = np.empty(len(y_pred), dtype=np.float64)
    sorted_scores = y_pred[order]
    start = 0
    while start < len(sorted_scores):
        stop = start + 1
        while stop < len(sorted_scores) and sorted_scores[stop] == sorted_scores[start]:
            stop += 1
        average_rank = (start + 1 + stop) / 2.0
        ranks[order[start:stop]] = average_rank
        start = stop

    positive_rank_sum = float(np.sum(ranks[labels == 1]))
    auc = (
        positive_rank_sum - positive_count * (positive_count + 1) / 2.0
    ) / (positive_count * negative_count)
    return float(auc)


def _average_precision(y_true: np.ndarray, y_pred: np.ndarray) -> tuple[float | None, str | None]:
    try:
        from sklearn.metrics import average_precision_score
    except Exception as exc:
        return None, str(exc)
    return float(average_precision_score(y_true, y_pred)), None


def _prediction_summary(y_true: np.ndarray, y_pred: np.ndarray) -> dict[str, Any]:
    if len(y_pred) == 0:
        return {"sample_count": 0}

    pred_positive = y_pred >= 0.5
    true_positive = y_true >= 0.5
    tn = int(np.sum(~pred_positive & ~true_positive))
    fp = int(np.sum(pred_positive & ~true_positive))
    fn = int(np.sum(~pred_positive & true_positive))
    tp = int(np.sum(pred_positive & true_positive))
    average_precision, average_precision_error = _average_precision(y_true, y_pred)
    return {
        "sample_count": int(len(y_pred)),
        "pred_min": float(np.min(y_pred)),
        "pred_max": float(np.max(y_pred)),
        "pred_mean": float(np.mean(y_pred)),
        "pred_std": float(np.std(y_pred)),
        "positive_prediction_ratio_at_0_5": float(np.mean(pred_positive)),
        "confusion_matrix_at_0_5": {
            "tn": tn,
            "fp": fp,
            "fn": fn,
            "tp": tp,
        },
        "roc_auc": _binary_roc_auc(y_true, y_pred),
        "average_precision": average_precision,
        "average_precision_error": average_precision_error,
    }


def _write_validation_predictions(
    model: tf.keras.Model,
    records: list[dict[str, Any]],
    out_dir: Path,
    image_size: int,
    patch_size: int,
    patch_count: int,
    batch_size: int,
    label_threshold: float,
) -> dict[str, Any]:
    image_paths: list[str] = []
    labels: list[float] = []
    predictions: list[float] = []
    batch_patches: list[np.ndarray] = []
    batch_full_images: list[np.ndarray] = []
    batch_labels: list[float] = []
    batch_paths: list[str] = []

    def flush_batch() -> None:
        if not batch_patches:
            return
        batch_inputs = {
            "patches": np.asarray(batch_patches, dtype=np.float32),
            "full_image": np.asarray(batch_full_images, dtype=np.float32),
        }
        batch_predictions = model.predict(batch_inputs, verbose=0).reshape(-1)
        predictions.extend(float(value) for value in batch_predictions)
        labels.extend(batch_labels)
        image_paths.extend(batch_paths)
        batch_patches.clear()
        batch_full_images.clear()
        batch_labels.clear()
        batch_paths.clear()

    for inputs, label, image_path in _iter_loaded_examples(
        records,
        image_size=image_size,
        patch_size=patch_size,
        patch_count=patch_count,
        label_threshold=label_threshold,
    ):
        batch_patches.append(inputs["patches"])
        batch_full_images.append(inputs["full_image"])
        batch_labels.append(float(label[0]))
        batch_paths.append(image_path)
        if len(batch_patches) >= batch_size:
            flush_batch()
    flush_batch()

    prediction_csv = out_dir / "val_predictions.csv"
    with prediction_csv.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=["image_path", "y_true", "y_pred"])
        writer.writeheader()
        for image_path, label, prediction in zip(image_paths, labels, predictions):
            writer.writerow(
                {
                    "image_path": image_path,
                    "y_true": label,
                    "y_pred": prediction,
                }
            )

    summary = _prediction_summary(
        np.asarray(labels, dtype=np.float32),
        np.asarray(predictions, dtype=np.float32),
    )
    summary["val_predictions_csv"] = str(prediction_csv)
    prediction_summary_path = out_dir / "prediction_summary.json"
    prediction_summary_path.write_text(
        json.dumps(summary, indent=2, sort_keys=True),
        encoding="utf-8",
    )
    summary["prediction_summary_json"] = str(prediction_summary_path)
    return summary


def _write_report(out_dir: Path, summary: dict[str, Any]) -> None:
    lines = [
        "# Mobile A-LAMP v2 Smoke Report",
        "",
        "This is an A-LAMP-inspired and RGNet-inspired mobile branch, not an official A-LAMP reproduction.",
        "",
        "## Command",
        "",
        "```bash",
        summary["command"],
        "```",
        "",
        "## Inputs",
        "",
        f"- train patch JSONL: `{summary['train_patch_jsonl']}`",
        f"- val patch JSONL: `{summary['val_patch_jsonl']}`",
        f"- image size: `{summary['image_size']}`",
        f"- patch size/count: `{summary['patch_size']}` / `{summary['patch_count']}`",
        f"- preprocessing mode: `{summary['preprocessing_mode']}`",
        "",
        "## Dataset",
        "",
        "```json",
        json.dumps(summary["dataset"], indent=2, sort_keys=True),
        "```",
        "",
        "## Model",
        "",
        "```json",
        json.dumps(summary["model"], indent=2, sort_keys=True),
        "```",
        "",
        "## Class Weights",
        "",
        "```json",
        json.dumps(summary["class_weight"], indent=2, sort_keys=True),
        "```",
        "",
        "## Final Metrics",
        "",
        "```json",
        json.dumps(summary["final_metrics"], indent=2, sort_keys=True),
        "```",
        "",
        "## Prediction Diagnostics",
        "",
        "```json",
        json.dumps(summary["prediction_summary"], indent=2, sort_keys=True),
        "```",
        "",
        "## Notes",
        "",
        "- Full 4096 training was not run by this smoke.",
        "- TFLite export was not implemented in this step.",
    ]
    (out_dir / "report.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def _command_for_summary() -> str:
    command = " ".join([sys.executable, *sys.argv])
    pythonpath = os.environ.get("PYTHONPATH")
    if pythonpath:
        return f"PYTHONPATH={pythonpath} {command}"
    return command


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--train_patch_jsonl", default=DEFAULT_TRAIN_PATCH_JSONL)
    parser.add_argument("--val_patch_jsonl", default=DEFAULT_VAL_PATCH_JSONL)
    parser.add_argument("--out_dir", default=DEFAULT_OUTPUT_DIR)
    parser.add_argument("--image_size", type=int, default=384)
    parser.add_argument("--patch_size", type=int, default=224)
    parser.add_argument("--patch_count", type=int, default=5)
    parser.add_argument("--batch_size", type=int, default=4)
    parser.add_argument("--epochs", type=int, default=5)
    parser.add_argument("--max_train_samples", type=int)
    parser.add_argument("--max_val_samples", type=int)
    parser.add_argument("--learning_rate", type=float, default=1.0e-4)
    parser.add_argument("--label_threshold", type=float, default=5.0)
    parser.add_argument("--backbone", default="mobilenetv3small", choices=["mobilenetv3small"])
    parser.add_argument("--backbone_weights", default="imagenet")
    parser.add_argument("--freeze_backbone", action=argparse.BooleanOptionalAction, default=True)
    parser.add_argument("--feature_dim", type=int, default=256)
    parser.add_argument("--attention_dim", type=int, default=128)
    parser.add_argument("--class_weight", default="auto", choices=["none", "auto"])
    parser.add_argument("--save_model", action="store_true")
    parser.add_argument("--smoke", action="store_true")
    return parser.parse_args()


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s:%(message)s")
    args = _parse_args()

    train_patch_jsonl = Path(args.train_patch_jsonl)
    val_patch_jsonl = Path(args.val_patch_jsonl)
    if not train_patch_jsonl.is_file():
        raise FileNotFoundError(f"Missing train patch JSONL: {train_patch_jsonl}")
    if not val_patch_jsonl.is_file():
        raise FileNotFoundError(f"Missing val patch JSONL: {val_patch_jsonl}")

    if args.smoke:
        args.max_train_samples = args.max_train_samples or 128
        args.max_val_samples = args.max_val_samples or 64
        args.epochs = min(args.epochs, 1)

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    for gpu in tf.config.list_physical_devices("GPU"):
        try:
            tf.config.experimental.set_memory_growth(gpu, True)
        except Exception:
            pass

    train_records = _load_jsonl_records(train_patch_jsonl, args.max_train_samples)
    val_records = _load_jsonl_records(val_patch_jsonl, args.max_val_samples)
    train_labels = _label_summary(train_records, args.label_threshold)
    val_labels = _label_summary(val_records, args.label_threshold)
    class_weight = _class_weights_from_summary(train_labels, args.class_weight)
    class_weight_summary = {
        "mode": args.class_weight,
        "weights": (
            {str(key): float(value) for key, value in class_weight.items()}
            if class_weight is not None
            else None
        ),
        "applied": class_weight is not None,
    }

    logging.info("Train samples loaded: %s", len(train_records))
    logging.info("Val samples loaded: %s", len(val_records))
    logging.info("Train label distribution: %s", train_labels)
    logging.info("Val label distribution: %s", val_labels)
    logging.info("Class weight: %s", class_weight_summary)
    logging.info("Preprocessing mode: %s", PREPROCESSING_MODE)

    train_dataset = _make_dataset(
        train_records,
        image_size=args.image_size,
        patch_size=args.patch_size,
        patch_count=args.patch_count,
        batch_size=args.batch_size,
        label_threshold=args.label_threshold,
        training=True,
    )
    val_dataset = _make_dataset(
        val_records,
        image_size=args.image_size,
        patch_size=args.patch_size,
        patch_count=args.patch_count,
        batch_size=args.batch_size,
        label_threshold=args.label_threshold,
        training=False,
    )

    model = build_mobile_alamp_v2_model(
        image_size=args.image_size,
        patch_size=args.patch_size,
        patch_count=args.patch_count,
        backbone=args.backbone,
        backbone_weights=args.backbone_weights,
        freeze_backbone=args.freeze_backbone,
        feature_dim=args.feature_dim,
        attention_dim=args.attention_dim,
    )
    model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=args.learning_rate),
        loss="binary_crossentropy",
        metrics=["accuracy", tf.keras.metrics.AUC(name="auc")],
    )

    input_shapes = {
        item.name.split(":")[0]: [int(dim) if dim is not None else None for dim in item.shape]
        for item in model.inputs
    }
    model_summary = {
        "name": model.name,
        "backbone": args.backbone,
        "backbone_weights": args.backbone_weights,
        "freeze_backbone": bool(args.freeze_backbone),
        "feature_dim": int(args.feature_dim),
        "attention_dim": int(args.attention_dim),
        "input_shapes": input_shapes,
        "output_shape": [int(dim) if dim is not None else None for dim in model.output.shape],
        "parameter_count": int(model.count_params()),
    }
    logging.info("Model input shapes: %s", input_shapes)
    logging.info("Model parameter count: %s", model_summary["parameter_count"])

    steps_per_epoch = math.ceil(len(train_records) / args.batch_size)
    validation_steps = math.ceil(len(val_records) / args.batch_size)
    callbacks: list[tf.keras.callbacks.Callback] = []
    best_model_path = out_dir / "best_val_auc_model.keras"
    if args.save_model:
        callbacks.append(
            tf.keras.callbacks.ModelCheckpoint(
                best_model_path,
                monitor="val_auc",
                mode="max",
                save_best_only=True,
                verbose=1,
            )
        )

    history = model.fit(
        train_dataset,
        validation_data=val_dataset,
        epochs=args.epochs,
        steps_per_epoch=steps_per_epoch,
        validation_steps=validation_steps,
        callbacks=callbacks,
        class_weight=class_weight,
        verbose=2,
    )
    rows = _history_rows(history)
    final_metrics = _final_metrics(history)
    logging.info("Final metrics: %s", final_metrics)

    _write_training_log(out_dir / "training_log.csv", rows)

    if args.save_model:
        model.save(out_dir / "final_model.keras")

    prediction_summary = _write_validation_predictions(
        model=model,
        records=val_records,
        out_dir=out_dir,
        image_size=args.image_size,
        patch_size=args.patch_size,
        patch_count=args.patch_count,
        batch_size=args.batch_size,
        label_threshold=args.label_threshold,
    )

    summary = {
        "status": "smoke_completed" if args.smoke else "training_completed",
        "paper_reproduction_claim": "A-LAMP-inspired approximation, not official reproduction",
        "command": _command_for_summary(),
        "train_patch_jsonl": str(train_patch_jsonl),
        "val_patch_jsonl": str(val_patch_jsonl),
        "out_dir": str(out_dir),
        "image_size": int(args.image_size),
        "patch_size": int(args.patch_size),
        "patch_count": int(args.patch_count),
        "batch_size": int(args.batch_size),
        "epochs": int(args.epochs),
        "steps_per_epoch": int(steps_per_epoch),
        "validation_steps": int(validation_steps),
        "learning_rate": float(args.learning_rate),
        "backbone": args.backbone,
        "backbone_weights": args.backbone_weights,
        "freeze_backbone": bool(args.freeze_backbone),
        "feature_dim": int(args.feature_dim),
        "attention_dim": int(args.attention_dim),
        "preprocessing_mode": PREPROCESSING_MODE,
        "class_weight": class_weight_summary,
        "smoke": bool(args.smoke),
        "save_model": bool(args.save_model),
        "dataset": {
            "train_requested_records": len(train_records),
            "val_requested_records": len(val_records),
            "train_label_distribution": train_labels,
            "val_label_distribution": val_labels,
        },
        "model": model_summary,
        "final_metrics": final_metrics,
        "prediction_summary": prediction_summary,
        "artifacts": {
            "training_log": str(out_dir / "training_log.csv"),
            "summary_json": str(out_dir / "summary.json"),
            "report_md": str(out_dir / "report.md"),
            "final_model": str(out_dir / "final_model.keras") if args.save_model else None,
            "best_val_auc_model": str(best_model_path) if args.save_model else None,
            "val_predictions": str(out_dir / "val_predictions.csv"),
            "prediction_summary": str(out_dir / "prediction_summary.json"),
        },
    }
    (out_dir / "summary.json").write_text(
        json.dumps(summary, indent=2, sort_keys=True),
        encoding="utf-8",
    )
    _write_report(out_dir, summary)
    print(f"Wrote Mobile A-LAMP v2 artifacts to {out_dir}")


if __name__ == "__main__":
    main()
