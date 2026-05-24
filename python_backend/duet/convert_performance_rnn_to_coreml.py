from __future__ import annotations

import argparse
import tempfile
from pathlib import Path

import numpy as np


def _load_generator_bundle_bytes(bundle_path: Path) -> tuple[bytes, bytes]:
    # Keep this script Magenta-free: parse .mag directly via note-seq protobuf.
    from note_seq.protobuf import generator_pb2  # type: ignore[import-not-found]
    import tensorflow.compat.v1 as tf  # type: ignore[import-not-found]

    bundle = generator_pb2.GeneratorBundle()
    with tf.gfile.Open(str(bundle_path), "rb") as f:
        bundle.ParseFromString(f.read())

    if len(bundle.checkpoint_file) != 1:
        raise ValueError(f"Expected exactly 1 checkpoint_file entry, got {len(bundle.checkpoint_file)}")
    if not bundle.metagraph_file:
        raise ValueError("Bundle is missing metagraph_file")

    return bundle.checkpoint_file[0], bundle.metagraph_file


def _read_checkpoint_tensors(checkpoint_path: Path) -> dict[str, np.ndarray]:
    import tensorflow.compat.v1 as tf  # type: ignore[import-not-found]

    reader = tf.train.NewCheckpointReader(str(checkpoint_path))
    var_map = reader.get_variable_to_shape_map()
    out: dict[str, np.ndarray] = {}
    for name in var_map.keys():
        out[name] = reader.get_tensor(name)
    return out


def _reorder_basic_lstm_to_keras_gate_order(weights: np.ndarray) -> np.ndarray:
    """
    TF BasicLSTMCell gate order: i, j, f, o
    Keras LSTM gate order:      i, f, c, o  (c == j)
    """
    i, j, f, o = np.split(weights, 4, axis=-1)
    return np.concatenate([i, f, j, o], axis=-1)


def _convert_basic_lstm_weights_to_keras(
    *,
    kernel_full: np.ndarray,
    bias_full: np.ndarray,
    input_dim: int,
    hidden_dim: int,
    forget_bias: float = 1.0,
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    # kernel_full shape: [input_dim + hidden_dim, 4 * hidden_dim]
    kernel_in = kernel_full[:input_dim, :]
    kernel_rec = kernel_full[input_dim:, :]

    kernel_in = _reorder_basic_lstm_to_keras_gate_order(kernel_in)
    kernel_rec = _reorder_basic_lstm_to_keras_gate_order(kernel_rec)
    bias = _reorder_basic_lstm_to_keras_gate_order(bias_full)

    # BasicLSTMCell adds forget_bias at runtime to the forget gate pre-activation.
    # In Keras, we bake that into the forget-gate bias chunk.
    bias = bias.copy()
    bias[hidden_dim : 2 * hidden_dim] += float(forget_bias)

    return kernel_in.astype(np.float32), kernel_rec.astype(np.float32), bias.astype(np.float32)


def _build_keras_step_model(
    *,
    num_classes: int,
    hidden_dim: int,
    num_layers: int,
) :
    import tensorflow as tf  # type: ignore[import-not-found]

    x = tf.keras.Input(shape=(1, num_classes), batch_size=1, name="x")  # [1, 1, 388]
    temperature = tf.keras.Input(shape=(1,), batch_size=1, name="temperature")  # [1, 1]

    # State inputs in TF collection order: c0, h0, c1, h1, c2, h2
    state_ins: list[tf.Tensor] = []
    for layer_idx in range(num_layers):
        state_ins.append(tf.keras.Input(shape=(hidden_dim,), batch_size=1, name=f"c{layer_idx}"))
        state_ins.append(tf.keras.Input(shape=(hidden_dim,), batch_size=1, name=f"h{layer_idx}"))

    y = x
    next_states: list[tf.Tensor] = []
    for layer_idx in range(num_layers):
        lstm = tf.keras.layers.LSTM(
            hidden_dim,
            return_sequences=True,
            return_state=True,
            activation="tanh",
            recurrent_activation="sigmoid",
            unit_forget_bias=False,
            name=f"lstm{layer_idx}",
        )

        c_in = state_ins[layer_idx * 2 + 0]
        h_in = state_ins[layer_idx * 2 + 1]

        y, h_out, c_out = lstm(y, initial_state=[h_in, c_in])
        # Output in TF flattened order (c, h).
        next_states.extend([c_out, h_out])

    logits = tf.keras.layers.Dense(num_classes, use_bias=True, name="fully_connected")(y)
    # Broadcast temperature to [1, 1, 1] so it divides logits [1, 1, C].
    t = tf.keras.layers.Lambda(lambda v: tf.reshape(v, (1, 1, 1)), name="temperature_broadcast")(temperature)
    scaled_logits = tf.keras.layers.Lambda(lambda xs: xs[0] / xs[1], name="scale_logits")([logits, t])
    softmax = tf.keras.layers.Softmax(axis=-1, name="softmax")(scaled_logits)

    outputs = [softmax, *next_states]
    return tf.keras.Model(inputs=[x, temperature, *state_ins], outputs=outputs, name="AIDuetPerformanceRNNStep")


def _apply_weights(
    model,
    *,
    ckpt_tensors: dict[str, np.ndarray],
    num_classes: int,
    hidden_dim: int,
    num_layers: int,
) -> None:
    # LSTM layers
    for layer_idx in range(num_layers):
        kernel_name = f"rnn/multi_rnn_cell/cell_{layer_idx}/basic_lstm_cell/kernel"
        bias_name = f"rnn/multi_rnn_cell/cell_{layer_idx}/basic_lstm_cell/bias"
        kernel_full = ckpt_tensors[kernel_name]
        bias_full = ckpt_tensors[bias_name]

        if layer_idx == 0:
            input_dim = num_classes
        else:
            input_dim = hidden_dim

        k_in, k_rec, b = _convert_basic_lstm_weights_to_keras(
            kernel_full=kernel_full,
            bias_full=bias_full,
            input_dim=input_dim,
            hidden_dim=hidden_dim,
            forget_bias=1.0,
        )

        lstm_layer = model.get_layer(f"lstm{layer_idx}")
        lstm_layer.set_weights([k_in, k_rec, b])

    # FC
    fc_w = ckpt_tensors["fully_connected/weights"].astype(np.float32)  # [512, 388]
    fc_b = ckpt_tensors["fully_connected/biases"].astype(np.float32)  # [388]
    model.get_layer("fully_connected").set_weights([fc_w, fc_b])


def _sanity_check_against_tf_metagraph(
    *,
    metagraph_path: Path,
    checkpoint_path: Path,
    keras_model,
    num_classes: int,
    hidden_dim: int,
    num_layers: int,
) -> None:
    import tensorflow.compat.v1 as tf  # type: ignore[import-not-found]

    graph = tf.Graph()
    with graph.as_default():
        saver = tf.train.import_meta_graph(str(metagraph_path), clear_devices=True)
        inputs_t = graph.get_collection("inputs")[0]
        temperature_t = graph.get_collection("temperature")[0]
        softmax_t = graph.get_collection("softmax")[0]
        initial_state_ts = graph.get_collection("initial_state")
        final_state_ts = graph.get_collection("final_state")

        if len(initial_state_ts) != num_layers * 2 or len(final_state_ts) != num_layers * 2:
            raise ValueError("Unexpected state tensor count in metagraph.")

        with tf.Session(graph=graph) as sess:
            saver.restore(sess, str(checkpoint_path))

            # Single step, one-hot index=0, temperature=1.0
            x = np.zeros((1, 1, num_classes), dtype=np.float32)
            x[0, 0, 0] = 1.0
            init = [np.zeros((1, hidden_dim), dtype=np.float32) for _ in range(num_layers * 2)]

            feed = {inputs_t: x, temperature_t: 1.0}
            for t, v in zip(initial_state_ts, init):
                feed[t] = v

            softmax_tf, final_state_tf = sess.run([softmax_t, final_state_ts], feed_dict=feed)

    # Keras step model output is [softmax, c0, h0, ...]
    temperature_in = np.array([[1.0]], dtype=np.float32)
    keras_inputs = [x, temperature_in, *init]
    keras_out = keras_model(keras_inputs, training=False)
    softmax_keras = keras_out[0].numpy()
    states_keras = [t.numpy() for t in keras_out[1:]]

    if not np.allclose(softmax_tf, softmax_keras, atol=1e-4):
        max_abs = float(np.max(np.abs(softmax_tf - softmax_keras)))
        raise AssertionError(f"Sanity check failed: softmax mismatch (max_abs={max_abs})")

    for idx, (a, b) in enumerate(zip(final_state_tf, states_keras)):
        if not np.allclose(a, b, atol=1e-4):
            max_abs = float(np.max(np.abs(a - b)))
            raise AssertionError(f"Sanity check failed: state[{idx}] mismatch (max_abs={max_abs})")


def _convert_to_coreml(
    *,
    keras_model,
    out_path: Path,
    num_layers: int,
) -> None:
    import coremltools as ct  # type: ignore[import-not-found]

    inputs = [
        ct.TensorType(name="x", shape=(1, 1, 388), dtype=np.float32),
        ct.TensorType(name="temperature", shape=(1, 1), dtype=np.float32),
    ]
    for layer_idx in range(num_layers):
        inputs.append(ct.TensorType(name=f"c{layer_idx}", shape=(1, 512), dtype=np.float32))
        inputs.append(ct.TensorType(name=f"h{layer_idx}", shape=(1, 512), dtype=np.float32))

    mlmodel = ct.convert(
        keras_model,
        source="tensorflow",
        inputs=inputs,
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.macOS12,
        compute_precision=ct.precision.FLOAT32,
    )

    # Rename outputs to stable names (otherwise coremltools defaults to Identity/Identity_1/...).
    # This must use rename_feature() so the ML Program stays consistent with spec.
    spec = mlmodel.get_spec()
    output_names = [o.name for o in spec.description.output]
    expected = 1 + num_layers * 2
    if len(output_names) != expected:
        raise ValueError(f"Unexpected CoreML output count: got {len(output_names)}, expected {expected}")

    ct.utils.rename_feature(spec, output_names[0], "softmax")
    for layer_idx in range(num_layers):
        ct.utils.rename_feature(spec, output_names[layer_idx * 2 + 1], f"c{layer_idx}_out")
        ct.utils.rename_feature(spec, output_names[layer_idx * 2 + 2], f"h{layer_idx}_out")

    # Persist into a non-temp package.
    mlmodel_final = ct.models.MLModel(spec, weights_dir=mlmodel.weights_dir)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    mlmodel_final.save(str(out_path))


def main() -> int:
    parser = argparse.ArgumentParser(description="Convert A.I. Duet Performance RNN .mag bundle to CoreML .mlpackage")
    parser.add_argument(
        "--bundle",
        type=Path,
        default=Path(__file__).parent / "models" / "performance_with_dynamics.mag",
        help="Path to performance_with_dynamics.mag",
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=Path(__file__).parent / "models" / "AIDuetPerformanceRNN.mlpackage",
        help="Output CoreML .mlpackage path",
    )
    parser.add_argument(
        "--sanity-check",
        action="store_true",
        help="Run a TF metagraph vs Keras equivalence check before CoreML conversion.",
    )

    args = parser.parse_args()
    bundle_path: Path = args.bundle
    out_path: Path = args.out

    if not bundle_path.exists():
        raise FileNotFoundError(bundle_path)

    checkpoint_bytes, metagraph_bytes = _load_generator_bundle_bytes(bundle_path)

    # Model constants for performance_with_dynamics:
    num_classes = 388
    hidden_dim = 512
    num_layers = 3

    with tempfile.TemporaryDirectory() as td:
        tmp_dir = Path(td)
        ckpt_path = tmp_dir / "checkpoint"
        meta_path = tmp_dir / "model.meta"
        ckpt_path.write_bytes(checkpoint_bytes)
        meta_path.write_bytes(metagraph_bytes)

        ckpt_tensors = _read_checkpoint_tensors(ckpt_path)

        keras_model = _build_keras_step_model(num_classes=num_classes, hidden_dim=hidden_dim, num_layers=num_layers)
        _apply_weights(
            keras_model,
            ckpt_tensors=ckpt_tensors,
            num_classes=num_classes,
            hidden_dim=hidden_dim,
            num_layers=num_layers,
        )

        if args.sanity_check:
            _sanity_check_against_tf_metagraph(
                metagraph_path=meta_path,
                checkpoint_path=ckpt_path,
                keras_model=keras_model,
                num_classes=num_classes,
                hidden_dim=hidden_dim,
                num_layers=num_layers,
            )

        _convert_to_coreml(keras_model=keras_model, out_path=out_path, num_layers=num_layers)

    print(f"Wrote: {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

