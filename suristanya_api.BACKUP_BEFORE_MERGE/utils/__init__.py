"""
Package init. Runs BEFORE utils.model_loader imports.

Patches numpy's pickle reconstructors so pickles created on NumPy 2.x
(references to BitGenerator *classes*) can be loaded on NumPy 1.x
(references expected as *strings*).

This must run before any pickle.load() of the fusion model.
"""
import numpy.random._pickle as _nprp

# Save originals
_ORIG_RANDOMSTATE_CTOR = _nprp.__randomstate_ctor
_ORIG_BIT_GENERATOR_CTOR = _nprp.__bit_generator_ctor
_ORIG_GENERATOR_CTOR = _nprp.__generator_ctor


def _coerce(arg):
    """Convert BitGenerator class -> its string name. Leave strings alone."""
    if isinstance(arg, type):
        return arg.__name__
    return arg


def _wrap(orig):
    def patched(*args, **kwargs):
        args = tuple(_coerce(a) for a in args)
        return orig(*args, **kwargs)
    patched.__wrapped__ = orig
    return patched


_nprp.__randomstate_ctor = _wrap(_ORIG_RANDOMSTATE_CTOR)
_nprp.__bit_generator_ctor = _wrap(_ORIG_BIT_GENERATOR_CTOR)
_nprp.__generator_ctor = _wrap(_ORIG_GENERATOR_CTOR)