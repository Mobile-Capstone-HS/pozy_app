# 모바일 A-LAMP v2 모델 구성을 정의한다.
from __future__ import annotations

import math

import tensorflow as tf


@tf.keras.utils.register_keras_serializable(package="MobileALAMPV2")
class MergePatchBatch(tf.keras.layers.Layer):
    def call(self, inputs: tf.Tensor) -> tf.Tensor:
        shape = tf.shape(inputs)
        return tf.reshape(inputs, (shape[0] * shape[1], shape[2], shape[3], shape[4]))

    def compute_output_shape(self, input_shape):
        return (None, input_shape[2], input_shape[3], input_shape[4])


@tf.keras.utils.register_keras_serializable(package="MobileALAMPV2")
class RestorePatchBatch(tf.keras.layers.Layer):
    def __init__(self, patch_count: int, **kwargs):
        super().__init__(**kwargs)
        self.patch_count = int(patch_count)

    def call(self, inputs: tf.Tensor) -> tf.Tensor:
        shape = tf.shape(inputs)
        batch_size = shape[0] // self.patch_count
        return tf.reshape(inputs, (batch_size, self.patch_count, shape[1]))

    def compute_output_shape(self, input_shape):
        return (None, self.patch_count, input_shape[-1])

    def get_config(self):
        config = super().get_config()
        config.update({"patch_count": self.patch_count})
        return config


def _normalise_backbone_weights(backbone_weights: str | None) -> str | None:
    if backbone_weights is None:
        return None
    if str(backbone_weights).lower() in {"none", "null", ""}:
        return None
    return str(backbone_weights)


def _build_mobilenetv3small(
    input_shape: tuple[int, int, int],
    backbone_weights: str | None,
    freeze_backbone: bool,
    name: str,
) -> tf.keras.Model:
    backbone = tf.keras.applications.MobileNetV3Small(
        input_shape=input_shape,
        alpha=1.0,
        minimalistic=False,
        include_top=False,
        weights=_normalise_backbone_weights(backbone_weights),
        include_preprocessing=True,
        name=name,
    )
    backbone.trainable = not freeze_backbone
    return backbone


def _region_layout_branch(
    full_image: tf.Tensor,
    backbone: tf.keras.Model,
    image_size: int,
    feature_dim: int,
    attention_dim: int,
) -> tf.Tensor:
    if image_size < 32:
        raise ValueError("image_size must be at least 32 for MobileNetV3Small.")

    x = backbone(full_image)
    x = tf.keras.layers.Conv2D(
        feature_dim,
        kernel_size=1,
        padding="same",
        activation="relu",
        name="layout_channel_projection",
    )(x)
    tokens = tf.keras.layers.Reshape(
        (-1, feature_dim),
        name="region_tokens",
    )(x)

    query = tf.keras.layers.Dense(attention_dim, use_bias=False, name="region_q")(tokens)
    key = tf.keras.layers.Dense(attention_dim, use_bias=False, name="region_k")(tokens)
    value = tf.keras.layers.Dense(attention_dim, use_bias=False, name="region_v")(tokens)

    attention_logits = tf.keras.layers.Dot(
        axes=(2, 2),
        name="region_attention_logits",
    )([query, key])
    scaled_logits = tf.keras.layers.Rescaling(
        1.0 / math.sqrt(float(attention_dim)),
        name="region_attention_scale",
    )(attention_logits)
    attention = tf.keras.layers.Softmax(axis=-1, name="region_attention")(scaled_logits)
    region_context = tf.keras.layers.Dot(
        axes=(2, 1),
        name="region_context",
    )([attention, value])
    layout_feature = tf.keras.layers.GlobalAveragePooling1D(
        name="layout_feature_pool",
    )(region_context)
    return tf.keras.layers.Dense(
        feature_dim,
        activation="relu",
        name="layout_feature",
    )(layout_feature)


def build_mobile_alamp_v2_model(
    image_size: int = 384,
    patch_size: int = 224,
    patch_count: int = 5,
    backbone: str = "mobilenetv3small",
    backbone_weights: str | None = "imagenet",
    freeze_backbone: bool = True,
    feature_dim: int = 256,
    attention_dim: int = 128,
    dropout_rate: float = 0.25,
) -> tf.keras.Model:
    if backbone.lower() != "mobilenetv3small":
        raise ValueError("Only backbone='mobilenetv3small' is supported.")

    patches = tf.keras.Input(
        shape=(patch_count, patch_size, patch_size, 3),
        name="patches",
    )
    full_image = tf.keras.Input(
        shape=(image_size, image_size, 3),
        name="full_image",
    )

    patch_backbone = _build_mobilenetv3small(
        input_shape=(patch_size, patch_size, 3),
        backbone_weights=backbone_weights,
        freeze_backbone=freeze_backbone,
        name="patch_mobilenetv3small",
    )
    layout_backbone = _build_mobilenetv3small(
        input_shape=(image_size, image_size, 3),
        backbone_weights=backbone_weights,
        freeze_backbone=freeze_backbone,
        name="layout_mobilenetv3small",
    )

    merged_patches = MergePatchBatch(name="merge_patch_batch")(patches)
    patch_map = patch_backbone(merged_patches)
    patch_vector = tf.keras.layers.GlobalAveragePooling2D(name="patch_gap")(patch_map)
    patch_vector = tf.keras.layers.Dense(
        feature_dim,
        activation="relu",
        name="patch_feature_projection",
    )(patch_vector)
    patch_tokens = RestorePatchBatch(
        patch_count=patch_count,
        name="restore_patch_batch",
    )(patch_vector)
    patch_feature = tf.keras.layers.GlobalAveragePooling1D(
        name="patch_mean_pool",
    )(patch_tokens)

    layout_feature = _region_layout_branch(
        full_image=full_image,
        backbone=layout_backbone,
        image_size=image_size,
        feature_dim=feature_dim,
        attention_dim=attention_dim,
    )

    fused = tf.keras.layers.Concatenate(name="patch_layout_concat")(
        [patch_feature, layout_feature]
    )
    fused = tf.keras.layers.Dense(128, activation="relu", name="fusion_dense")(fused)
    fused = tf.keras.layers.Dropout(dropout_rate, name="fusion_dropout")(fused)
    score = tf.keras.layers.Dense(1, activation="sigmoid", name="score")(fused)

    return tf.keras.Model(
        inputs={"patches": patches, "full_image": full_image},
        outputs=score,
        name="mobile_alamp_v2",
    )


__all__ = ["build_mobile_alamp_v2_model"]
