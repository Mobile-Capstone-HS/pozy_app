import os
import csv
import argparse
from typing import List, Tuple

import numpy as np
import tensorflow as tf
from PIL import Image


def preprocess_image(img_path: str, input_size: Tuple[int, int]) -> np.ndarray:
    """Load image, resize, normalize to [-1, 1], and add batch dim."""
    img = Image.open(img_path).convert("RGB")
    img = img.resize(input_size)
    x = np.array(img, dtype=np.float32)
    x = (x / 127.5) - 1.0
    x = np.expand_dims(x, axis=0)  # [1, H, W, 3]
    return x


def mean_score_from_distribution(p: np.ndarray) -> float:
    """Convert 10-bin score distribution to mean score in [1, 10]."""
    scores = np.arange(1, 11, dtype=np.float32)
    return float((p[0] * scores).sum())


def collect_images(folder: str) -> List[str]:
    exts = {".jpg", ".jpeg", ".png", ".JPG", ".JPEG", ".PNG"}
    files = []
    for name in os.listdir(folder):
        path = os.path.join(folder, name)
        if os.path.isfile(path) and os.path.splitext(name)[1] in exts:
            files.append(path)
    files.sort()
    return files


def load_tflite_interpreter(model_path: str) -> Tuple[tf.lite.Interpreter, dict, dict]:
    interpreter = tf.lite.Interpreter(model_path=model_path)
    interpreter.allocate_tensors()
    input_details = interpreter.get_input_details()[0]
    output_details = interpreter.get_output_details()[0]
    return interpreter, input_details, output_details


def infer_distribution(
    interpreter: tf.lite.Interpreter,
    input_details: dict,
    output_details: dict,
    x: np.ndarray,
) -> np.ndarray:
    x = x.astype(input_details["dtype"])
    interpreter.set_tensor(input_details["index"], x)
    interpreter.invoke()
    y = interpreter.get_tensor(output_details["index"])
    return y


def score_images(
    model_path: str,
    image_folder: str,
    top_percent: float,
    output_csv: str,
) -> None:
    image_paths = collect_images(image_folder)
    if not image_paths:
        raise RuntimeError(f"No images found in folder: {image_folder}")

    interpreter, input_details, output_details = load_tflite_interpreter(model_path)

    input_shape = input_details["shape"]
    if len(input_shape) != 4:
        raise RuntimeError(f"Unexpected input shape: {input_shape}")

    input_h, input_w = int(input_shape[1]), int(input_shape[2])
    print(f"Model input size: {input_w}x{input_h}")
    print(f"Found {len(image_paths)} images")

    results = []
    for i, img_path in enumerate(image_paths, start=1):
        try:
            x = preprocess_image(img_path, (input_w, input_h))
            p = infer_distribution(interpreter, input_details, output_details, x)
            mean = mean_score_from_distribution(p)

            results.append({
                "filename": os.path.basename(img_path),
                "filepath": img_path,
                "mean_score": mean,
                "dist_1": float(p[0][0]),
                "dist_2": float(p[0][1]),
                "dist_3": float(p[0][2]),
                "dist_4": float(p[0][3]),
                "dist_5": float(p[0][4]),
                "dist_6": float(p[0][5]),
                "dist_7": float(p[0][6]),
                "dist_8": float(p[0][7]),
                "dist_9": float(p[0][8]),
                "dist_10": float(p[0][9]),
            })

            if i % 20 == 0 or i == len(image_paths):
                print(f"Scored {i}/{len(image_paths)}")

        except Exception as e:
            print(f"[WARN] Failed on {img_path}: {e}")

    if not results:
        raise RuntimeError("No images were successfully scored.")

    # Sort descending by score
    results.sort(key=lambda x: x["mean_score"], reverse=True)

    # Select top k
    k = max(1, int(np.ceil(len(results) * top_percent)))
    for idx, row in enumerate(results):
        row["rank"] = idx + 1
        row["is_a_cut"] = 1 if idx < k else 0

    # Save CSV
    fieldnames = [
        "rank",
        "is_a_cut",
        "filename",
        "filepath",
        "mean_score",
        "dist_1", "dist_2", "dist_3", "dist_4", "dist_5",
        "dist_6", "dist_7", "dist_8", "dist_9", "dist_10",
    ]

    with open(output_csv, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(results)

    print(f"\nSaved CSV: {output_csv}")
    print(f"A-cut count: {k}/{len(results)} ({top_percent*100:.1f}%)")

    print("\nTop 10 results:")
    for row in results[:10]:
        print(
            f"#{row['rank']:>3} | "
            f"{row['filename']:<25} | "
            f"score={row['mean_score']:.4f} | "
            f"A-cut={row['is_a_cut']}"
        )


def main():
    parser = argparse.ArgumentParser(description="Score all images in a folder with NIMA TFLite model.")
    parser.add_argument(
        "--model",
        type=str,
        default=os.path.expanduser("~/nima_project/out/nima_aesthetic_fp16_flex.tflite"),
        help="Path to TFLite model"
    )
    parser.add_argument(
        "--input_dir",
        type=str,
        required=True,
        help="Folder containing images to score"
    )
    parser.add_argument(
        "--top_percent",
        type=float,
        default=0.2,
        help="Top fraction to mark as A-cut (e.g. 0.2 = top 20%%)"
    )
    parser.add_argument(
        "--output_csv",
        type=str,
        default="scores.csv",
        help="Output CSV path"
    )

    args = parser.parse_args()

    if not (0 < args.top_percent <= 1.0):
        raise ValueError("--top_percent must be in (0, 1].")

    score_images(
        model_path=args.model,
        image_folder=args.input_dir,
        top_percent=args.top_percent,
        output_csv=args.output_csv,
    )


if __name__ == "__main__":
    main()
