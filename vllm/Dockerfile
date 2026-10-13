# vllm-openai with the vllm[audio] extras, which the upstream image omits.
# Without them every audio request fails with "Invalid or unsupported audio file".
#
# Packages are listed explicitly rather than as vllm[audio] so pip never re-resolves
# vllm itself (nightly builds aren't on PyPI). The list covers both decoders:
# av/soundfile (vLLM >= 0.11) and librosa (older tags that setup.sh may pick).
# Everything already installed is pinned as a constraint so torch/numpy stay put.
ARG VLLM_IMAGE_TAG=cu130-nightly
FROM vllm/vllm-openai:${VLLM_IMAGE_TAG}

RUN pip freeze | grep '==' > /tmp/constraints.txt \
 && pip install --no-cache-dir -c /tmp/constraints.txt \
        av scipy soundfile librosa "mistral_common[audio]" \
 && rm /tmp/constraints.txt
