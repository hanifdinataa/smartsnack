
from pathlib import Path
import tensorflow as tf

keras_path = Path(r"c:\Hanif-Dinata\SEMESTER6\TA\ANDROID\MODEL\artifacts_v3\smartsnack_model_for_convert.keras")
out_path = Path(r"c:\Hanif-Dinata\SEMESTER6\TA\ANDROID\MODEL\artifacts_v3\smartsnack_model.tflite")
quantize = True

m = tf.keras.models.load_model(str(keras_path), compile=False)

# Try A: keras model
err = []
buf = None
try:
    c = tf.lite.TFLiteConverter.from_keras_model(m)
    if quantize:
        c.optimizations = [tf.lite.Optimize.DEFAULT]
        c.target_spec.supported_types = [tf.float16]
    c.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS, tf.lite.OpsSet.SELECT_TF_OPS]
    c._experimental_lower_tensor_list_ops = False
    buf = c.convert()
    print("OK A")
except Exception as e:
    err.append("A=" + str(e))

# Try B: concrete function
if buf is None:
    try:
        @tf.function(input_signature=[tf.TensorSpec([None, m.input_shape[1], m.input_shape[2], m.input_shape[3]], tf.float32)])
        def serve(x):
            return m(x, training=False)
        concrete = serve.get_concrete_function()
        c = tf.lite.TFLiteConverter.from_concrete_functions([concrete], m)
        if quantize:
            c.optimizations = [tf.lite.Optimize.DEFAULT]
            c.target_spec.supported_types = [tf.float16]
        c.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS, tf.lite.OpsSet.SELECT_TF_OPS]
        c._experimental_lower_tensor_list_ops = False
        buf = c.convert()
        print("OK B")
    except Exception as e:
        err.append("B=" + str(e))

if buf is None:
    raise RuntimeError("ALL_FAILED: " + " | ".join(err))

out_path.write_bytes(buf)
print("OK FINAL", out_path, len(buf))
