#!/usr/bin/env python3
# gen_model.py OUT.onnx: writes tile_sigmoid.onnx, the prodsim "model": one
# Sigmoid node, float32 input "x" of shape [n] -> output "y" of shape [n].
# Encodes the ONNX protobuf by hand, so it needs no onnx package.
import sys


def varint(n):
    out = b""
    while True:
        b = n & 0x7F
        n >>= 7
        if n:
            out += bytes([b | 0x80])
        else:
            return out + bytes([b])


def field(num, wire, payload):
    return varint(num << 3 | wire) + payload


def vint(num, n):
    return field(num, 0, varint(n))


def ld(num, data):  # length-delimited: bytes, string, sub-message
    if isinstance(data, str):
        data = data.encode()
    return field(num, 2, varint(len(data)) + data)


def value_info(name):
    dim = ld(1, ld(2, "n"))                 # TensorShapeProto.dim { dim_param: "n" }
    tensor = vint(1, 1) + ld(2, dim)        # elem_type FLOAT, shape
    return ld(1, name) + ld(2, ld(1, tensor))  # name, type { tensor_type }


node = ld(1, "x") + ld(2, "y") + ld(3, "sigmoid") + ld(4, "Sigmoid")
graph = ld(1, node) + ld(2, "prodsim_tiles") + ld(11, value_info("x")) + ld(12, value_info("y"))
model = (
    vint(1, 8)                                # ir_version
    + ld(2, "prodsim gen_model.py")           # producer_name
    + ld(7, graph)
    + ld(8, ld(1, "") + vint(2, 13))          # opset_import { domain "", version 13 }
)

with open(sys.argv[1], "wb") as f:
    f.write(model)
