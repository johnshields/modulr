"""Shared Essentia audio loading, decoded once and reused across detectors."""


def load_essentia(path, sample_rate=44100):
    """Mono buffer via Essentia MonoLoader, with Essentia logging silenced."""
    import essentia
    essentia.log.infoActive = False
    essentia.log.warningActive = False
    import essentia.standard as es
    return es.MonoLoader(filename=path, sampleRate=sample_rate)()
