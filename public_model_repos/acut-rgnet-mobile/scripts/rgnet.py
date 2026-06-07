"""
RGNet-style composition-aware aesthetics model.

Based on:
- Composition-Aware Image Aesthetics Assessment (WACV 2020)

Faithful parts:
- fully convolutional encoder produces a spatial feature map
- each spatial location is treated as a local region node
- graph edges are built from region feature similarity
- graph reasoning is applied before final aesthetics regression

Approximated parts:
- uses an EfficientNetV2B0 feature backbone for repo practicality
- uses dense cosine-similarity graph construction with softmax normalization
- uses lightweight residual graph-convolution blocks instead of the paper's exact engineering details

Expected inputs:
- batch of RGB images with shape [B, H, W, 3] scaled to [0, 1]

Expected outputs:
- scalar AADB-style aesthetics score in [0, 1]
"""

from __future__ import annotations

import sys

import tensorflow as tf


def _build_backbone(input_shape: tuple[int, int, int], weights: str | None = "imagenet") -> tf.keras.Model:
    if weights is None:
        return tf.keras.applications.EfficientNetV2B0(
            include_top=False,
            weights=None,
            input_shape=input_shape,
        )

    try:
        return tf.keras.applications.EfficientNetV2B0(
            include_top=False,
            weights=weights,
            input_shape=input_shape,
        )
    except Exception as exc:
        print(f"EfficientNetV2B0 {weights} weights unavailable, falling back to random init: {exc}", file=sys.stderr)
        return tf.keras.applications.EfficientNetV2B0(
            include_top=False,
            weights=None,
            input_shape=input_shape,
        )


@tf.keras.utils.register_keras_serializable(package="photo_score_project")
class RegionGraphBuilder(tf.keras.layers.Layer):
    def __init__(self, temperature: float = 0.25, **kwargs):
        super().__init__(**kwargs)
        self.temperature = temperature

    def call(self, node_features: tf.Tensor) -> tf.Tensor:
        node_features = tf.cast(node_features, tf.float32)
        normalized = tf.math.l2_normalize(node_features, axis=-1)
        similarity = tf.matmul(normalized, normalized, transpose_b=True)
        num_nodes = tf.shape(similarity)[-1]
        eye = tf.eye(num_nodes, batch_shape=[tf.shape(similarity)[0]], dtype=similarity.dtype)
        adjacency = tf.nn.softmax(similarity / self.temperature, axis=-1)
        adjacency = adjacency + eye
        degree = tf.reduce_sum(adjacency, axis=-1, keepdims=True)
        return adjacency / tf.maximum(degree, 1e-6)

    def get_config(self):
        return {**super().get_config(), "temperature": self.temperature}


@tf.keras.utils.register_keras_serializable(package="photo_score_project")
class GraphConvolution(tf.keras.layers.Layer):
    def __init__(self, units: int, activation: str = "relu", dropout: float = 0.0, **kwargs):
        super().__init__(**kwargs)
        self.units = units
        self.activation = tf.keras.activations.get(activation)
        self.dropout = dropout
        self.proj = tf.keras.layers.Dense(units, use_bias=False)
        self.norm = tf.keras.layers.LayerNormalization(epsilon=1e-6)
        self.drop = tf.keras.layers.Dropout(dropout)

    def build(self, input_shape):
        node_shape, _ = input_shape
        self.proj.build(node_shape)
        self.norm.build((node_shape[0], node_shape[1], self.units))
        super().build(input_shape)

    def call(self, inputs: tuple[tf.Tensor, tf.Tensor], training: bool = False) -> tf.Tensor:
        node_features, adjacency = inputs
        compute_dtype = tf.as_dtype(self.compute_dtype or tf.keras.backend.floatx())
        node_features = tf.cast(node_features, compute_dtype)
        adjacency = tf.cast(adjacency, compute_dtype)
        residual = node_features
        x = tf.matmul(adjacency, node_features)
        x = self.proj(x)
        x = self.activation(x)
        x = self.drop(x, training=training)
        if residual.shape[-1] == self.units:
            x = x + tf.cast(residual, x.dtype)
        return self.norm(x)

    def get_config(self):
        return {
            **super().get_config(),
            "units": self.units,
            "activation": tf.keras.activations.serialize(self.activation),
            "dropout": self.dropout,
        }


@tf.keras.utils.register_keras_serializable(package="photo_score_project")
class RegionWeightedPooling(tf.keras.layers.Layer):
    def call(self, inputs: tuple[tf.Tensor, tf.Tensor]) -> tf.Tensor:
        node_context, attention = inputs
        return tf.reduce_sum(node_context * attention, axis=1)

    def get_config(self):
        return super().get_config()


def build_rgnet_model(
    input_shape: tuple[int, int, int] = (256, 256, 3),
    backbone_weights: str | None = "imagenet",
) -> tf.keras.Model:
    base = _build_backbone(input_shape=input_shape, weights=backbone_weights)

    inputs = tf.keras.Input(shape=input_shape)
    feature_map = base(inputs, training=False)
    feature_map = tf.keras.layers.Conv2D(256, 1, padding="same", activation="relu", name="region_proj")(feature_map)
    node_features = tf.keras.layers.Reshape((-1, 256), name="region_nodes")(feature_map)

    adjacency = RegionGraphBuilder(name="region_graph")(node_features)
    x = GraphConvolution(256, dropout=0.1, name="gcn_block_1")((node_features, adjacency))
    x = GraphConvolution(256, dropout=0.1, name="gcn_block_2")((x, adjacency))

    node_context = tf.keras.layers.Concatenate(name="region_context")([node_features, x])
    attention = tf.keras.layers.Dense(1, activation="tanh", name="region_attention_logits")(node_context)
    attention = tf.keras.layers.Softmax(axis=1, name="region_attention")(attention)
    pooled = RegionWeightedPooling(name="region_weighted_pool")([node_context, attention])

    global_context = tf.keras.layers.GlobalAveragePooling2D(name="global_pool")(feature_map)
    fused = tf.keras.layers.Concatenate(name="composition_fusion")([pooled, global_context])
    fused = tf.keras.layers.Dropout(0.3)(fused)
    fused = tf.keras.layers.Dense(256, activation="relu", name="head_dense")(fused)
    output = tf.keras.layers.Dense(1, activation="sigmoid", dtype="float32", name="score")(fused)

    return tf.keras.Model(inputs, output, name="rgnet_practical")
