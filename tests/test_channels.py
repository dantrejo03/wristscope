from wristscope.channels import CHANNELS, FUNDAMENTAL_CHANNELS, Source, channels_for


def test_channel_ids_are_unique():
    assert len(CHANNELS) == len(FUNDAMENTAL_CHANNELS)


def test_channel_counts_per_source():
    assert len(channels_for(Source.ACCELEROMETER)) == 3
    assert len(channels_for(Source.GYRO)) == 3
    # quaternion 4 + rotation rate 3 + user accel 3 + gravity 3 + magnetic field 3 + heading 1
    assert len(channels_for(Source.DEVICE_MOTION)) == 17


def test_channel_ids_start_with_their_source():
    for channel in FUNDAMENTAL_CHANNELS:
        assert channel.id.startswith(channel.source.value + ".")
