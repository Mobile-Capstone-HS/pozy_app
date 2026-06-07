from __future__ import annotations

import math
from pathlib import Path
import argparse

import tensorflow as tf

from src.datasets.ava_distribution_dataset import load_ava_distribution_frame, make_ava_distribution_dataset
from src.models.nima_distribution import build_nima_distribution_model, emd_loss, mean_score_mae

_CHECKPOINT_ARTIFACT_NAMES = ("best.weights.h5", "final_model.keras", "saved_model")

gpus = tf.config.list_physical_devices("GPU")
print("Visible GPUs:", gpus)

for gpu in gpus:
    try:
        tf.config.experimental.set_memory_growth(gpu, True)
    except Exception as exc:
        print("memory growth setup failed:", exc)

if gpus:
    tf.keras.mixed_precision.set_global_policy("mixed_float16")
    print("mixed precision enabled")


def _assert_no_existing_checkpoint_artifacts(out_dir: Path) -> None:
    existing = [str(out_dir / name) for name in _CHECKPOINT_ARTIFACT_NAMES if (out_dir / name).exists()]
    if existing:
        raise FileExistsError(
            "Refusing to overwrite existing NIMA checkpoint artifacts. Use a new fixed-preprocessing output "
            f"directory instead. Existing artifacts: {existing}"
        )


def main() -> None:
    parser = argparse.ArgumentParser(description="Train a paper-faithful NIMA distribution model on AVA-style CSVs.")
    parser.add_argument("--train_csv", required=True)
    parser.add_argument("--val_csv", required=True)
    parser.add_argument("--image_size", type=int, default=224)
    parser.add_argument("--batch_size", type=int, default=32)
    parser.add_argument("--epochs", type=int, default=10)
    parser.add_argument("--learning_rate", type=float, default=1e-4)
    parser.add_argument(
        "--backbone_weights",
        default="imagenet",
        help="EfficientNetV2B0 weights argument. Use an explicit ImageNet .h5 path if the Keras alias tries to download.",
    )
    parser.add_argument("--steps_per_epoch", type=int)
    parser.add_argument("--validation_steps", type=int)
    parser.add_argument("--out_dir", required=True)
    args = parser.parse_args()

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    _assert_no_existing_checkpoint_artifacts(out_dir)

    train_frame = load_ava_distribution_frame(args.train_csv)
    val_frame = load_ava_distribution_frame(args.val_csv)
    print(f"[NIMA] Valid train rows: {len(train_frame)}")
    print(f"[NIMA] Valid val rows: {len(val_frame)}")

    train_ds = make_ava_distribution_dataset(
        frame=train_frame,
        image_size=(args.image_size, args.image_size),
        batch_size=args.batch_size,
        training=True,
        repeat=True,
        drop_remainder=True,
    )
    val_ds = make_ava_distribution_dataset(
        frame=val_frame,
        image_size=(args.image_size, args.image_size),
        batch_size=args.batch_size,
        training=False,
        shuffle=False,
        repeat=False,
        drop_remainder=False,
    )

    effective_train_steps = args.steps_per_epoch or max(1, len(train_frame) // args.batch_size)
    effective_val_steps = args.validation_steps or max(1, math.ceil(len(val_frame) / args.batch_size))
    print(f"[NIMA] steps_per_epoch={effective_train_steps} validation_steps={effective_val_steps}")
    print(f"[NIMA] train element_spec={train_ds.element_spec}")
    print(f"[NIMA] val element_spec={val_ds.element_spec}")

    sample_images, sample_targets = next(iter(train_ds.take(1)))
    print(f"[NIMA] sample train batch image shape={sample_images.shape} dtype={sample_images.dtype}")
    print(f"[NIMA] sample train batch target shape={sample_targets.shape} dtype={sample_targets.dtype}")

    backbone_weights = None if args.backbone_weights.lower() == "none" else args.backbone_weights
    model = build_nima_distribution_model(
        input_shape=(args.image_size, args.image_size, 3),
        backbone_weights=backbone_weights,
    )
    model.compile(
        optimizer=tf.keras.optimizers.Adam(args.learning_rate),
        loss=emd_loss,
        metrics=[mean_score_mae, tf.keras.metrics.KLDivergence(name="kl_divergence")],
    )

    callbacks = [
        tf.keras.callbacks.ModelCheckpoint(
            str(out_dir / "best.weights.h5"),
            save_best_only=True,
            save_weights_only=True,
            monitor="val_loss",
            mode="min",
        ),
        tf.keras.callbacks.EarlyStopping(monitor="val_loss", patience=3, restore_best_weights=True),
    ]

    model.fit(
        train_ds,
        validation_data=val_ds,
        epochs=args.epochs,
        steps_per_epoch=effective_train_steps,
        validation_steps=effective_val_steps,
        callbacks=callbacks,
    )
    model.save(out_dir / "final_model.keras")
    model.export(out_dir / "saved_model")
    print("Saved:", out_dir / "final_model.keras")
    print("Exported:", out_dir / "saved_model")


if __name__ == "__main__":
    main()
