import pytest

from wristscope.core.channels import Source
from wristscope.core.samples import Sample


def test_partial_sample_is_allowed():
    sample = Sample(Source.DEVICE_MOTION, 1.0, {"motion.gravity.z": -1.0})
    assert sample.values == {"motion.gravity.z": -1.0}


def test_rejects_channel_from_another_source():
    with pytest.raises(ValueError):
        Sample(Source.GYRO, 1.0, {"accel.x": 0.1})


def test_rejects_unknown_channel():
    with pytest.raises(ValueError):
        Sample(Source.GYRO, 1.0, {"gyro.w": 0.1})
