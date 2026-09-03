# C3 forensic work

The current blocker is a deterministic SG_IO residual of 78 bytes on vendor command C3 image reads. The historical forensic source in `tools/c3-forensic-reference.c` is preserved as a development reference, not as a supported end-user tool.

Before promoting any workaround, prove whether bytes beyond `len - resid` were actually written by the device. The goal is to distinguish a true short transfer from unreliable residual accounting.
