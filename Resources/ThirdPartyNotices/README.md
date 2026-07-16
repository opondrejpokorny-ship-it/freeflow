# Third-Party Notices

FreeFlow bundles selected open-source runtime components so local transcription works without a separate package-manager installation.

## whisper.cpp

- Version: `1.9.1`
- Commit: `f049fff95a089aa9969deb009cdd4892b3e74916`
- Source: `https://github.com/ggml-org/whisper.cpp`
- License: MIT (`whisper.cpp-LICENSE.txt`)

The bundled executable is built from the pinned commit with shared libraries disabled, native CPU-specific optimizations disabled, and the Metal shader library embedded.
