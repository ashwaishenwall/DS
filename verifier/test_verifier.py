def test_marker_is_unique():
    import uuid
    marker = f"FYND_VERIFIER_MARKER-{uuid.uuid4().hex}"
    assert marker.startswith("FYND_VERIFIER_MARKER-")
    assert len(marker.split("-", 1)[1]) == 32
