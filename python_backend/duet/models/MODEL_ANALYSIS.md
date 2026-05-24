# A.I. Duet — Magenta Performance RNN (`performance_with_dynamics.mag`) Model Analysis

This document records what’s inside `performance_with_dynamics.mag`, how to run the original TensorFlow graph, and the exact event/token encoding used by Performance RNN.

> Scope: This is analysis for the **Performance RNN with dynamics** bundle shipped at `python_backend/duet/models/performance_with_dynamics.mag`.

## 1) `.mag` file structure (GeneratorBundle)

The `.mag` bundle is a serialized protobuf message:

- Type: `note_seq.protobuf.generator_pb2.GeneratorBundle`
- Fields (present in this bundle):
  - `generator_details` (contains `id` and `description`)
  - `bundle_details` (contains `description`)
  - `checkpoint_file` (`repeated bytes`, here **one entry**)
  - `metagraph_file` (`bytes`)

For this file:

- `generator_details.id` = `performance_with_dynamics`
- `checkpoint_file` entries = `1`
  - entry `0` size ≈ `24,972,721` bytes (TensorFlow checkpoint, single-file format)
- `metagraph_file` size ≈ `82,924` bytes (TensorFlow `MetaGraphDef`)

## 2) TensorFlow checkpoint variables (weights)

The checkpoint contains exactly **8** variables:

- `rnn/multi_rnn_cell/cell_0/basic_lstm_cell/kernel` shape `[900, 2048]`
- `rnn/multi_rnn_cell/cell_0/basic_lstm_cell/bias` shape `[2048]`
- `rnn/multi_rnn_cell/cell_1/basic_lstm_cell/kernel` shape `[1024, 2048]`
- `rnn/multi_rnn_cell/cell_1/basic_lstm_cell/bias` shape `[2048]`
- `rnn/multi_rnn_cell/cell_2/basic_lstm_cell/kernel` shape `[1024, 2048]`
- `rnn/multi_rnn_cell/cell_2/basic_lstm_cell/bias` shape `[2048]`
- `fully_connected/weights` shape `[512, 388]`
- `fully_connected/biases` shape `[388]`

From these shapes we can infer:

- number of classes (`num_classes`) = `388`
- LSTM hidden size = `512`
- number of LSTM layers = `3`
- layer-0 input size = `388` (one-hot event vector)
- layer-1/2 input size = `512` (previous layer output)

## 3) TensorFlow metagraph I/O (original inference interface)

The `metagraph_file` is a TF1-style `MetaGraphDef`. Importing it creates a graph exposing collections:

- **Input tensors**
  - `inputs`: `Placeholder:0`, `float32`, shape **`[1, T, 388]`**
    - Meaning: one-hot encoded performance event sequence, batch size fixed to `1`.
  - `temperature`: `Placeholder_1:0`, `float32`, scalar
    - Meaning: softmax temperature. The graph outputs `softmax(logits / temperature)`.

- **State tensors**
  - `initial_state`: 6 tensors, each `float32` shape `[1, 512]`
    - These are zero-state tensors created by `cell.zero_state(...)`.
    - TensorFlow allows feeding them in `feed_dict` even though they are not placeholders.
    - Order is the flattened `MultiRNNCell` state: **`[c0, h0, c1, h1, c2, h2]`**.
  - `final_state`: 6 tensors, each `float32` shape `[1, 512]`
    - Same ordering as `initial_state`: **`[c0, h0, c1, h1, c2, h2]`**.

- **Output tensors**
  - `softmax`: `Reshape_1:0`, `float32`, shape **`[1, T, 388]`**
    - Meaning: per-step probability distribution over the 388 event classes.

### Notes on gate ordering (important for weight portability)

This model uses TensorFlow’s `BasicLSTMCell`, whose gate split order is:

`i, j, f, o`  (input gate, new input, forget gate, output gate)

The forget bias (`forget_bias = 1.0`) is added **at runtime** to the **`f`** gate pre-activation.

## 4) Performance RNN event encoding (388-class token space)

The 388-class vocabulary matches `note_seq.performance_encoder_decoder.PerformanceOneHotEncoding(num_velocity_bins=32)`, with:

- pitch range: `0..127` (MIDI standard)
- time-shift range: `1..100` steps
- velocity bins: `1..32` bins

Event types (`note_seq.performance_lib.PerformanceEvent`):

- `NOTE_ON` (type = 1): value = MIDI pitch
- `NOTE_OFF` (type = 2): value = MIDI pitch
- `TIME_SHIFT` (type = 3): value = number of steps to advance (>= 1 for this one-hot encoding)
- `VELOCITY` (type = 4): value = velocity bin (1..32)

### 4.1 Integer token ID layout (index → event)

Token IDs are assigned by concatenating ranges in this order:

1) `NOTE_ON` pitch `0..127` → indices **`0..127`**
2) `NOTE_OFF` pitch `0..127` → indices **`128..255`**
3) `TIME_SHIFT` steps `1..100` → indices **`256..355`**
4) `VELOCITY` bin `1..32` → indices **`356..387`**

Formulas:

- `NOTE_ON(p)` → `p`
- `NOTE_OFF(p)` → `128 + p`
- `TIME_SHIFT(s)` → `256 + (s - 1)`
- `VELOCITY(vbin)` → `356 + (vbin - 1)`

### 4.2 Token → event (inverse mapping)

- `0..127` → `NOTE_ON(pitch=index)`
- `128..255` → `NOTE_OFF(pitch=index-128)`
- `256..355` → `TIME_SHIFT(steps=(index-256)+1)`
- `356..387` → `VELOCITY(bin=(index-356)+1)`

### 4.3 How MIDI notes become events

At a high level:

1. Start from a `NoteSequence` (notes with `pitch/start_time/end_time/velocity`).
2. Quantize in **absolute time** to `steps_per_second = 100`.
3. Convert quantized notes into a `note_seq.performance_lib.Performance`, producing an event stream that interleaves:
   - `TIME_SHIFT` events to move forward in time (1..100 per event; longer gaps are represented by repeated time-shifts)
   - `VELOCITY` changes (binned into 32 bins)
   - `NOTE_ON` / `NOTE_OFF` events
4. Convert each `PerformanceEvent` to an integer ID using the table above.
5. Convert integer IDs to one-hot vectors of length 388 for the RNN input.

## 5) Planned CoreML interface (what we will export)

CoreML will receive a **single-step** interface to support streaming generation:

- Inputs (all `float32`)
  - `x`: `[1, 1, 388]` one-hot for the current event (single timestep)
  - `temperature`: scalar (or `[1]`) temperature for softmax
  - `c0, h0, c1, h1, c2, h2`: each `[1, 512]` initial states
- Outputs (all `float32`)
  - `softmax`: `[1, 1, 388]` next-event distribution for this step
  - `c0_out, h0_out, c1_out, h1_out, c2_out, h2_out`: each `[1, 512]`

This makes it easy to:

- “Prime” the model by iterating over an input event sequence and carrying state.
- Continue generation autoregressively by sampling next tokens from `softmax`.

## 6) Conversion attempts (log)

### Attempt 1 (2026-05-24)

1) Tried installing `magenta==2.1.4` with pinned deps on Python 3.10 → dependency resolution conflict (`numpy==1.21.6` not viable on py310, and conflicts with TF pins).
2) Result: **failed** (pip resolution impossible).
3) Next step: avoid Magenta runtime dependency; parse `.mag` via `note_seq.protobuf.generator_pb2` and restore TF checkpoint/metagraph directly.

### Attempt 2 (2026-05-24)

1) Built an equivalent `tf.keras` **single-step** model (3×512 LSTM + `Dense(388)`), loaded weights from the `.mag` checkpoint, and converted using `coremltools` as an `mlprogram` with `FLOAT32` precision.
2) Result: **success** — produced `python_backend/duet/models/AIDuetPerformanceRNN.mlpackage`, loadable with `coremltools.models.MLModel(...)`, and validated numerically against the original TF metagraph with `atol=1e-4` (see `python_backend/duet/validate.py`).
3) Next step: integrate this step-model into the app/runtime sampling loop (autoregressive decoding from `softmax` + event decoding back to MIDI/NoteSequence).
