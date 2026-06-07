# RGNet 논문 지향 v1 AADB 회귀 실험을 학습한다.
from __future__ import annotations

import argparse
import inspect
import json
from io import BytesIO
from datetime import datetime
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd
import tensorflow as tf
import yaml

from src.models.rgnet_paper_v1 import (
    MODEL_VARIANT,
    build_rgnet_paper_v1_model,
    get_rgnet_paper_v1_custom_objects,
)


DEFAULT_OUTPUT_DIR = "outputs/rgnet_paper_v1_aadb_regression_20260509/full_train"
PREPROCESS_BACKENDS = ("tf", "pil_bilinear")
ADJACENCY_TYPES = ("semantic", "hybrid_spatial")
CONTEXT_MODULE_TYPES = ("parallel_aspp", "cascaded_denseaspp")


def _read_yaml(path: str | None) -> dict[str, Any]:
    if not path:
        return {}
    with Path(path).open("r", encoding="utf-8") as handle:
        loaded = yaml.safe_load(handle) or {}
    if not isinstance(loaded, dict):
        raise ValueError(f"Expected mapping config in {path}")
    return loaded


def _cfg(config: dict[str, Any], section: str, key: str, default: Any) -> Any:
    value = config.get(section, {})
    if isinstance(value, dict) and key in value:
        return value[key]
    return default


def _resolve(value: Any, config: dict[str, Any], section: str, key: str, default: Any) -> Any:
    return value if value is not None else _cfg(config, section, key, default)


def _normalize_weights(value: str | None) -> str | None:
    if value is None:
        return None
    if str(value).lower() in {"none", "null", "false", "random"}:
        return None
    return str(value)


def _normalize_preprocess_backend(value: str | None) -> str:
    backend = "tf" if value is None else str(value).lower()
    if backend not in PREPROCESS_BACKENDS:
        raise ValueError(f"Unsupported preprocess_backend: {value}. Expected one of {PREPROCESS_BACKENDS}")
    return backend


def _normalize_adjacency_type(value: str | None) -> str:
    adjacency_type = "semantic" if value is None else str(value).lower()
    if adjacency_type not in ADJACENCY_TYPES:
        raise ValueError(f"Unsupported adjacency_type: {value}. Expected one of {ADJACENCY_TYPES}")
    return adjacency_type


def _normalize_context_module_type(value: str | None) -> str:
    context_module_type = "parallel_aspp" if value is None else str(value).lower()
    if context_module_type not in CONTEXT_MODULE_TYPES:
        raise ValueError(f"Unsupported context_module_type: {value}. Expected one of {CONTEXT_MODULE_TYPES}")
    return context_module_type


def _parse_int_tuple(value: str | list[int] | tuple[int, ...] | None, default: tuple[int, ...]) -> tuple[int, ...]:
    if value is None:
        return default
    if isinstance(value, str):
        return tuple(int(part.strip()) for part in value.split(",") if part.strip())
    return tuple(int(part) for part in value)


def _parse_bool(value: Any, default: bool) -> bool:
    if value is None:
        return bool(default)
    if isinstance(value, bool):
        return value
    normalized = str(value).strip().lower()
    if normalized in {"1", "true", "yes", "y", "on"}:
        return True
    if normalized in {"0", "false", "no", "n", "off"}:
        return False
    raise ValueError(f"Expected boolean value, got: {value}")


def _polynomial_learning_rate(initial_lr: float, epoch: int, max_epochs: int, power: float) -> float:
    if max_epochs <= 0:
        return float(initial_lr)
    progress = min(max(float(epoch) / float(max_epochs), 0.0), 1.0)
    return float(initial_lr) * float((1.0 - progress) ** float(power))


def _build_adam_optimizer(learning_rate: float, weight_decay: float) -> tuple[tf.keras.optimizers.Optimizer, str]:
    if float(weight_decay) <= 0.0:
        return tf.keras.optimizers.Adam(learning_rate=learning_rate), "none"
    if "weight_decay" in inspect.signature(tf.keras.optimizers.Adam).parameters:
        return (
            tf.keras.optimizers.Adam(learning_rate=learning_rate, weight_decay=float(weight_decay)),
            "optimizer_weight_decay",
        )
    return tf.keras.optimizers.Adam(learning_rate=learning_rate), "not_applied_adam_weight_decay_unsupported"


def _setup_tensorflow(seed: int) -> dict[str, object]:
    tf.keras.mixed_precision.set_global_policy("float32")
    tf.keras.utils.set_random_seed(seed)
    gpus = tf.config.list_physical_devices("GPU")
    for gpu in gpus:
        try:
            tf.config.experimental.set_memory_growth(gpu, True)
        except Exception as exc:
            print("memory growth setup failed:", exc)
    return {
        "visible_gpus": [str(gpu) for gpu in gpus],
        "mixed_precision_policy": str(tf.keras.mixed_precision.global_policy()),
        "tensorflow_version": tf.__version__,
    }


def _load_frame(csv_path: str, image_col: str, target_col: str, max_samples: int | None) -> pd.DataFrame:
    frame = pd.read_csv(csv_path)
    required = {image_col, target_col}
    missing = sorted(required - set(frame.columns))
    if missing:
        raise ValueError(f"{csv_path} missing required columns: {missing}")
    frame = frame.dropna(subset=[image_col, target_col]).reset_index(drop=True)
    if max_samples is not None:
        frame = frame.head(int(max_samples)).reset_index(drop=True)
    if frame.empty:
        raise ValueError(f"{csv_path} produced an empty frame")
    return frame


def _decode_image_pil_bilinear(contents: tf.Tensor, image_size: int) -> np.ndarray:
    from PIL import Image

    with Image.open(BytesIO(contents.numpy())) as image:
        image = image.convert("RGB").resize((image_size, image_size), Image.BILINEAR)
        return np.asarray(image, dtype=np.float32) / 255.0


def _decode_image(
    path: tf.Tensor,
    image_size: int,
    training: bool,
    preprocess_backend: str,
    random_horizontal_flip: bool,
    random_scale_crop: bool,
    scale_min: float,
    scale_max: float,
    crop_size: int,
) -> tf.Tensor:
    image = tf.io.read_file(path)
    if preprocess_backend == "tf":
        image = tf.image.decode_jpeg(image, channels=3)
        image = tf.image.convert_image_dtype(image, tf.float32)
    elif preprocess_backend == "pil_bilinear":
        image = tf.py_function(
            lambda contents: _decode_image_pil_bilinear(contents, image_size),
            [image],
            Tout=tf.float32,
        )
        image.set_shape([image_size, image_size, 3])
    else:
        raise ValueError(f"Unsupported preprocess_backend: {preprocess_backend}")

    if training and random_scale_crop:
        scale = tf.random.uniform([], float(scale_min), float(scale_max), dtype=tf.float32)
        scaled_size = tf.cast(tf.round(tf.cast(crop_size, tf.float32) * scale), tf.int32)
        scaled_size = tf.maximum(scaled_size, int(crop_size))
        image = tf.image.resize(image, [scaled_size, scaled_size])
        image = tf.image.random_crop(image, [int(crop_size), int(crop_size), 3])
        image.set_shape([int(crop_size), int(crop_size), 3])
        if int(crop_size) != int(image_size):
            image = tf.image.resize(image, [image_size, image_size])
    else:
        image = tf.image.resize(image, [image_size, image_size])

    if training and random_horizontal_flip:
        image = tf.image.random_flip_left_right(image)
    return image


def _make_dataset(
    frame: pd.DataFrame,
    image_col: str,
    target_col: str,
    image_size: int,
    batch_size: int,
    training: bool,
    shuffle: bool,
    preprocess_backend: str,
    random_horizontal_flip: bool,
    random_scale_crop: bool,
    scale_min: float,
    scale_max: float,
    crop_size: int,
) -> tf.data.Dataset:
    paths = frame[image_col].astype(str).to_numpy()
    targets = frame[target_col].astype("float32").to_numpy().reshape(-1, 1)
    dataset = tf.data.Dataset.from_tensor_slices((paths, targets))
    if training and shuffle:
        dataset = dataset.shuffle(min(len(frame), 10000), reshuffle_each_iteration=True)

    def _map(path: tf.Tensor, target: tf.Tensor) -> tuple[tf.Tensor, tf.Tensor]:
        image = _decode_image(
            path,
            image_size=image_size,
            training=training,
            preprocess_backend=preprocess_backend,
            random_horizontal_flip=random_horizontal_flip,
            random_scale_crop=random_scale_crop,
            scale_min=scale_min,
            scale_max=scale_max,
            crop_size=crop_size,
        )
        return image, target

    return dataset.map(_map, num_parallel_calls=tf.data.AUTOTUNE).batch(batch_size).prefetch(tf.data.AUTOTUNE)


def _float_history(history: dict[str, list[float]]) -> dict[str, list[float]]:
    return {key: [float(value) for value in values] for key, values in history.items()}


def _count_trainable_params(model: tf.keras.Model) -> int:
    return int(sum(np.prod(variable.shape) for variable in model.trainable_weights))


def _row_sum_stats(adjacency: tf.Tensor) -> dict[str, float]:
    row_sums = tf.reduce_sum(tf.cast(adjacency, tf.float32), axis=-1)
    return {
        "row_sum_min": float(tf.reduce_min(row_sums).numpy()),
        "row_sum_max": float(tf.reduce_max(row_sums).numpy()),
    }


def _collect_adjacency_diagnostic(model: tf.keras.Model, sample_images: tf.Tensor) -> dict[str, object]:
    layer = None
    for layer_name in ("hybrid_spatial_adjacency", "region_similarity_adjacency"):
        try:
            layer = model.get_layer(layer_name)
            break
        except ValueError:
            continue
    if layer is None:
        return {"available": False, "reason": "adjacency layer not found"}

    diagnostic: dict[str, object] = {
        "available": True,
        "layer_name": layer.name,
    }
    try:
        diagnostic_model = tf.keras.Model(model.input, [layer.input, layer.output])
        node_features, adjacency = diagnostic_model(sample_images[:1], training=False)
        diagnostic["final_adjacency"] = _row_sum_stats(adjacency)
        semantic_layer = getattr(layer, "semantic_adjacency", None)
        if semantic_layer is not None:
            diagnostic["semantic_adjacency"] = _row_sum_stats(semantic_layer(node_features))
        else:
            diagnostic["semantic_adjacency"] = _row_sum_stats(adjacency)
        spatial_adjacency = getattr(layer, "_spatial_adjacency", None)
        if spatial_adjacency is not None:
            diagnostic["spatial_adjacency"] = _row_sum_stats(spatial_adjacency)
    except Exception as exc:
        diagnostic = {
            **diagnostic,
            "available": False,
            "reason": str(exc),
        }
    return diagnostic


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Train the isolated RGNet-paper-v1 AADB regression model.")
    parser.add_argument("--config")
    parser.add_argument("--train_csv")
    parser.add_argument("--val_csv")
    parser.add_argument("--image_col")
    parser.add_argument("--target_col")
    parser.add_argument("--image_size", type=int)
    parser.add_argument("--batch_size", type=int)
    parser.add_argument("--epochs", type=int)
    parser.add_argument("--learning_rate", type=float)
    parser.add_argument("--patience", type=int)
    parser.add_argument("--early_stopping_patience", type=int)
    parser.add_argument("--out_dir")
    parser.add_argument("--backbone_weights")
    parser.add_argument("--region_dim", type=int)
    parser.add_argument("--graph_units", type=int)
    parser.add_argument("--graph_blocks", type=int)
    parser.add_argument("--graph_temperature", type=float)
    parser.add_argument("--graph_dropout", type=float)
    parser.add_argument("--head_dropout", type=float)
    parser.add_argument("--dilation_rates")
    parser.add_argument("--aggregation")
    parser.add_argument("--lse_r", type=float)
    parser.add_argument("--adjacency_type", choices=ADJACENCY_TYPES)
    parser.add_argument("--spatial_alpha", type=float)
    parser.add_argument("--spatial_sigma", type=float)
    parser.add_argument("--context_module_type", choices=CONTEXT_MODULE_TYPES)
    parser.add_argument("--denseaspp_rates")
    parser.add_argument("--denseaspp_growth_rate", type=int)
    parser.add_argument("--use_context_batchnorm")
    parser.add_argument("--paper_recipe")
    parser.add_argument("--random_horizontal_flip")
    parser.add_argument("--random_scale_crop")
    parser.add_argument("--scale_min", type=float)
    parser.add_argument("--scale_max", type=float)
    parser.add_argument("--crop_size", type=int)
    parser.add_argument("--lr_schedule", choices=("constant", "polynomial"))
    parser.add_argument("--poly_power", type=float)
    parser.add_argument("--weight_decay", type=float)
    parser.add_argument("--disable_early_stopping")
    parser.add_argument("--preprocess_backend", choices=PREPROCESS_BACKENDS)
    parser.add_argument("--max_train_samples", type=int)
    parser.add_argument("--max_val_samples", type=int)
    parser.add_argument("--seed", type=int)
    parser.add_argument("--no_verify_save_load", dest="verify_save_load", action="store_false", default=None)
    parser.add_argument("--verify_save_load", dest="verify_save_load", action="store_true")
    parser.add_argument("--allow_cpu_full", action="store_true")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    config = _read_yaml(args.config)

    train_csv = _resolve(args.train_csv, config, "data", "train_csv", "data/processed/aadb/train.csv")
    val_csv = _resolve(args.val_csv, config, "data", "val_csv", "data/processed/aadb/val.csv")
    image_col = _resolve(args.image_col, config, "data", "image_col", "image_path")
    target_col = _resolve(args.target_col, config, "data", "target_col", "score")
    image_size = int(_resolve(args.image_size, config, "model", "image_size", 256))
    batch_size = int(_resolve(args.batch_size, config, "training", "batch_size", 8))
    epochs = int(_resolve(args.epochs, config, "training", "epochs", 20))
    learning_rate = float(_resolve(args.learning_rate, config, "training", "learning_rate", 1e-4))
    patience_arg = args.early_stopping_patience if args.early_stopping_patience is not None else args.patience
    patience = int(_resolve(patience_arg, config, "training", "early_stopping_patience", _cfg(config, "training", "patience", 3)))
    out_dir = Path(_resolve(args.out_dir, config, "experiment", "train_output_dir", DEFAULT_OUTPUT_DIR))
    backbone_weights = _normalize_weights(_resolve(args.backbone_weights, config, "model", "backbone_weights", "imagenet"))
    region_dim = int(_resolve(args.region_dim, config, "model", "region_dim", 256))
    graph_units = int(_resolve(args.graph_units, config, "model", "graph_units", 256))
    graph_blocks = int(_resolve(args.graph_blocks, config, "model", "graph_blocks", 3))
    graph_temperature = float(_resolve(args.graph_temperature, config, "model", "graph_temperature", 0.25))
    graph_dropout = float(_resolve(args.graph_dropout, config, "model", "graph_dropout", 0.1))
    head_dropout = float(_resolve(args.head_dropout, config, "model", "head_dropout", 0.3))
    dilation_rates = _parse_int_tuple(_resolve(args.dilation_rates, config, "model", "dilation_rates", None), (1, 3, 6, 12, 18))
    aggregation = str(_resolve(args.aggregation, config, "model", "aggregation", "lse")).lower()
    lse_r = float(_resolve(args.lse_r, config, "model", "lse_r", 4.0))
    adjacency_type = _normalize_adjacency_type(_resolve(args.adjacency_type, config, "model", "adjacency_type", "semantic"))
    spatial_alpha = float(_resolve(args.spatial_alpha, config, "model", "spatial_alpha", 0.0))
    spatial_sigma = float(_resolve(args.spatial_sigma, config, "model", "spatial_sigma", 0.25))
    context_module_type = _normalize_context_module_type(
        _resolve(args.context_module_type, config, "model", "context_module_type", "parallel_aspp")
    )
    denseaspp_rates = _parse_int_tuple(
        _resolve(args.denseaspp_rates, config, "model", "denseaspp_rates", None),
        (3, 6, 12, 18),
    )
    denseaspp_growth_rate = int(_resolve(args.denseaspp_growth_rate, config, "model", "denseaspp_growth_rate", 64))
    use_context_batchnorm = _parse_bool(
        _resolve(args.use_context_batchnorm, config, "model", "use_context_batchnorm", True),
        True,
    )
    paper_recipe = _parse_bool(_resolve(args.paper_recipe, config, "training", "paper_recipe", False), False)
    random_horizontal_flip = _parse_bool(
        _resolve(args.random_horizontal_flip, config, "training", "random_horizontal_flip", True),
        True,
    )
    random_scale_crop = _parse_bool(
        _resolve(args.random_scale_crop, config, "training", "random_scale_crop", False),
        False,
    )
    scale_min = float(_resolve(args.scale_min, config, "training", "scale_min", 1.05))
    scale_max = float(_resolve(args.scale_max, config, "training", "scale_max", 1.25))
    crop_size = int(_resolve(args.crop_size, config, "training", "crop_size", image_size))
    lr_schedule = str(_resolve(args.lr_schedule, config, "training", "lr_schedule", "constant")).lower()
    if lr_schedule not in {"constant", "polynomial"}:
        raise ValueError(f"Unsupported lr_schedule: {lr_schedule}")
    poly_power = float(_resolve(args.poly_power, config, "training", "poly_power", 0.9))
    weight_decay = float(_resolve(args.weight_decay, config, "training", "weight_decay", 0.0))
    disable_early_stopping = _parse_bool(
        _resolve(args.disable_early_stopping, config, "training", "disable_early_stopping", False),
        False,
    )
    if scale_min <= 0.0 or scale_max <= 0.0 or scale_min > scale_max:
        raise ValueError(f"Invalid scale range: scale_min={scale_min}, scale_max={scale_max}")
    preprocess_backend = _normalize_preprocess_backend(
        _resolve(args.preprocess_backend, config, "data", "preprocess_backend", "tf")
    )
    max_train_samples = _resolve(args.max_train_samples, config, "training", "max_train_samples", None)
    max_val_samples = _resolve(args.max_val_samples, config, "training", "max_val_samples", None)
    seed = int(_resolve(args.seed, config, "training", "seed", 42))
    verify_save_load = bool(_resolve(args.verify_save_load, config, "training", "verify_save_load", True))

    out_dir.mkdir(parents=True, exist_ok=True)
    tf_info = _setup_tensorflow(seed)

    train_frame = _load_frame(str(train_csv), image_col, target_col, max_train_samples)
    val_frame = _load_frame(str(val_csv), image_col, target_col, max_val_samples)
    print(f"preprocess_backend: {preprocess_backend}")
    if not tf_info["visible_gpus"] and len(train_frame) > 1000 and epochs > 3 and not args.allow_cpu_full:
        raise RuntimeError(
            "GPU is not visible for a long/full run. Re-run with GPU access or pass --allow_cpu_full explicitly."
        )

    train_ds = _make_dataset(
        train_frame,
        image_col,
        target_col,
        image_size,
        batch_size,
        training=True,
        shuffle=True,
        preprocess_backend=preprocess_backend,
        random_horizontal_flip=random_horizontal_flip,
        random_scale_crop=random_scale_crop,
        scale_min=scale_min,
        scale_max=scale_max,
        crop_size=crop_size,
    )
    val_ds = _make_dataset(
        val_frame,
        image_col,
        target_col,
        image_size,
        batch_size,
        training=False,
        shuffle=False,
        preprocess_backend=preprocess_backend,
        random_horizontal_flip=False,
        random_scale_crop=False,
        scale_min=scale_min,
        scale_max=scale_max,
        crop_size=crop_size,
    )

    model = build_rgnet_paper_v1_model(
        input_shape=(image_size, image_size, 3),
        backbone_weights=backbone_weights,
        region_dim=region_dim,
        graph_units=graph_units,
        graph_blocks=graph_blocks,
        graph_temperature=graph_temperature,
        graph_dropout=graph_dropout,
        head_dropout=head_dropout,
        dilation_rates=dilation_rates,
        aggregation=aggregation,
        lse_r=lse_r,
        adjacency_type=adjacency_type,
        spatial_alpha=spatial_alpha,
        spatial_sigma=spatial_sigma,
        context_module_type=context_module_type,
        denseaspp_rates=denseaspp_rates,
        denseaspp_growth_rate=denseaspp_growth_rate,
        use_context_batchnorm=use_context_batchnorm,
    )
    model_metadata = dict(getattr(model, "_rgnet_paper_v1_config", {}))
    parameter_count = int(model.count_params())
    trainable_parameter_count = _count_trainable_params(model)
    print(f"adjacency_type: {adjacency_type}")
    print(f"spatial_alpha: {spatial_alpha}")
    print(f"spatial_sigma: {spatial_sigma}")
    print(f"context_module_type: {context_module_type}")
    print(f"denseaspp_rates: {denseaspp_rates}")
    print(f"denseaspp_growth_rate: {denseaspp_growth_rate}")
    print(f"use_context_batchnorm: {use_context_batchnorm}")
    print(f"context_channels: {model_metadata.get('context_channels')}")
    print(f"feature_map_node_count: {model_metadata.get('feature_map_node_count')}")
    print(f"model parameters: total={parameter_count}, trainable={trainable_parameter_count}")
    optimizer, weight_decay_implementation = _build_adam_optimizer(learning_rate, weight_decay)
    print(f"paper_recipe: {paper_recipe}")
    print(f"random_horizontal_flip: {random_horizontal_flip}")
    print(f"random_scale_crop: {random_scale_crop}")
    print(f"scale_min: {scale_min}")
    print(f"scale_max: {scale_max}")
    print(f"crop_size: {crop_size}")
    print(f"lr_schedule: {lr_schedule}")
    print(f"poly_power: {poly_power}")
    print(f"weight_decay: {weight_decay}")
    print(f"weight_decay_implementation: {weight_decay_implementation}")
    print(f"early_stopping_enabled: {not disable_early_stopping}")
    print(f"early_stopping_patience: {patience}")
    model.compile(
        optimizer=optimizer,
        loss="mse",
        metrics=[tf.keras.metrics.MeanAbsoluteError(name="mae")],
    )

    sample_images, _ = next(iter(train_ds.take(1)))
    forward_sample = model(sample_images, training=False)
    forward_check = {
        "input_shape": [int(dim) for dim in sample_images.shape],
        "output_shape": [int(dim) for dim in forward_sample.shape],
        "prediction_min": float(tf.reduce_min(forward_sample).numpy()),
        "prediction_max": float(tf.reduce_max(forward_sample).numpy()),
        "all_finite": bool(np.isfinite(forward_sample.numpy()).all()),
        "in_unit_range": bool((forward_sample.numpy() >= 0.0).all() and (forward_sample.numpy() <= 1.0).all()),
    }
    adjacency_diagnostic = _collect_adjacency_diagnostic(model, sample_images)

    callbacks: list[tf.keras.callbacks.Callback] = []
    if lr_schedule == "polynomial":
        callbacks.append(
            tf.keras.callbacks.LearningRateScheduler(
                lambda epoch, _lr: _polynomial_learning_rate(learning_rate, epoch, epochs, poly_power),
                verbose=0,
            )
        )
    callbacks.extend(
        [
        tf.keras.callbacks.ModelCheckpoint(
            str(out_dir / "best.weights.h5"),
            save_best_only=True,
            save_weights_only=True,
            monitor="val_loss",
            mode="min",
        ),
        tf.keras.callbacks.CSVLogger(str(out_dir / "training_history.csv")),
        ]
    )
    if not disable_early_stopping:
        callbacks.append(
            tf.keras.callbacks.EarlyStopping(
                monitor="val_loss",
                patience=patience,
                restore_best_weights=True,
            )
        )

    history_obj = model.fit(
        train_ds,
        validation_data=val_ds,
        epochs=epochs,
        callbacks=callbacks,
        verbose=2,
    )
    history = _float_history(history_obj.history)
    epochs_completed = int(len(history.get("loss", [])))
    if lr_schedule == "polynomial":
        per_epoch_learning_rates = [
            _polynomial_learning_rate(learning_rate, epoch, epochs, poly_power)
            for epoch in range(epochs_completed)
        ]
    else:
        per_epoch_learning_rates = [float(learning_rate) for _ in range(epochs_completed)]

    final_model_path = out_dir / "final_model.keras"
    trained_sample = model(sample_images, training=False)
    model.save(str(final_model_path))

    save_load_check: dict[str, object] | None = None
    if verify_save_load:
        loaded = tf.keras.models.load_model(
            str(final_model_path),
            compile=False,
            safe_mode=False,
            custom_objects=get_rgnet_paper_v1_custom_objects(),
        )
        loaded_sample = loaded(sample_images, training=False)
        max_abs_diff = tf.reduce_max(tf.abs(tf.cast(trained_sample, tf.float32) - tf.cast(loaded_sample, tf.float32)))
        save_load_check = {
            "loaded_model_name": loaded.name,
            "loaded_output_shape": [int(dim) for dim in loaded_sample.shape],
            "max_abs_diff_vs_trained_forward_sample": float(max_abs_diff.numpy()),
        }

    val_losses = history.get("val_loss", [])
    best_epoch = int(np.argmin(val_losses) + 1) if val_losses else None
    best_val_loss = float(min(val_losses)) if val_losses else None
    best_val_mae = None
    if best_epoch is not None and history.get("val_mae"):
        best_val_mae = float(history["val_mae"][best_epoch - 1])
    context_note = (
        "cascaded DenseASPP"
        if context_module_type == "cascaded_denseaspp"
        else "parallel ASPP approximation"
    )

    summary = {
        "created_at_local": datetime.now().astimezone().isoformat(),
        "model_variant": MODEL_VARIANT,
        "official_reproduction": False,
        "paper_comparability_note": (
            f"Uses DenseNet121, {context_note}, spatial region nodes, cosine adjacency, "
            "residual graph convolution, region-level scores, and configurable aggregation. "
            "This is not the official paper implementation."
        ),
        "train_csv": str(train_csv),
        "val_csv": str(val_csv),
        "image_col": image_col,
        "target_col": target_col,
        "train_samples": int(len(train_frame)),
        "val_samples": int(len(val_frame)),
        "image_size": image_size,
        "preprocess_backend": preprocess_backend,
        "preprocessing": {
            "backend": preprocess_backend,
            "normalization": "float32_rgb_0_1",
            "resize": "tf.image.resize" if preprocess_backend == "tf" else "PIL.Image.BILINEAR",
        },
        "augmentation": {
            "random_horizontal_flip": random_horizontal_flip,
            "random_scale_crop": random_scale_crop,
            "scale_min": scale_min,
            "scale_max": scale_max,
            "crop_size": crop_size,
            "training_only": True,
        },
        "paper_recipe": paper_recipe,
        "batch_size": batch_size,
        "epochs_requested": epochs,
        "epochs_completed": epochs_completed,
        "learning_rate": learning_rate,
        "initial_learning_rate": learning_rate,
        "lr_schedule": lr_schedule,
        "poly_power": poly_power,
        "per_epoch_learning_rates": per_epoch_learning_rates,
        "weight_decay": weight_decay,
        "weight_decay_implementation": weight_decay_implementation,
        "early_stopping": {
            "enabled": not disable_early_stopping,
            "monitor": "val_loss",
            "patience": patience,
            "restore_best_weights": not disable_early_stopping,
        },
        "model": {
            "backbone": "DenseNet121",
            "backbone_weights_requested": backbone_weights,
            "context_module": (
                "cascaded DenseASPP"
                if context_module_type == "cascaded_denseaspp"
                else "parallel ASPP approximation"
            ),
            "context_module_type": context_module_type,
            "dilation_rates": list(dilation_rates),
            "denseaspp_rates": list(denseaspp_rates),
            "denseaspp_growth_rate": denseaspp_growth_rate,
            "use_context_batchnorm": use_context_batchnorm,
            "context_channels": model_metadata.get("context_channels"),
            "region_dim": region_dim,
            "graph_units": graph_units,
            "graph_blocks": graph_blocks,
            "graph_temperature": graph_temperature,
            "graph_dropout": graph_dropout,
            "head_dropout": head_dropout,
            "adjacency": (
                "hybrid semantic cosine softmax plus spatial Gaussian prior"
                if adjacency_type == "hybrid_spatial"
                else "cosine similarity, softmax-normalized"
            ),
            "adjacency_type": adjacency_type,
            "spatial_alpha": spatial_alpha,
            "spatial_sigma": spatial_sigma,
            "feature_map_height": model_metadata.get("feature_map_height"),
            "feature_map_width": model_metadata.get("feature_map_width"),
            "feature_map_node_count": model_metadata.get("feature_map_node_count"),
            "graph_convolution": "residual graph convolution",
            "region_score_head": "per-node sigmoid scalar score",
            "aggregation": aggregation,
            "lse_r": lse_r,
            "aggregation_formula": "(1 / r) * log(mean(exp(r * region_scores))) for aggregation=lse",
            "output_activation": "region sigmoid before aggregation",
            "parameter_count": parameter_count,
            "trainable_parameter_count": trainable_parameter_count,
        },
        "adjacency_diagnostic": adjacency_diagnostic,
        "tensorflow": tf_info,
        "forward_check": forward_check,
        "save_load_check": save_load_check,
        "outputs": {
            "final_model": str(final_model_path),
            "best_weights": str(out_dir / "best.weights.h5"),
            "training_history_csv": str(out_dir / "training_history.csv"),
            "train_summary_json": str(out_dir / "train_summary.json"),
        },
        "best_epoch": best_epoch,
        "best_val_loss": best_val_loss,
        "best_val_mae": best_val_mae,
        "history": history,
    }
    (out_dir / "train_summary.json").write_text(json.dumps(summary, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps(summary, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
