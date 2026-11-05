#!/usr/bin/env bash
# Builds the riv-demo-pyiceberg Lambda layer (Python 3.12, arm64): pyiceberg + pyarrow.
# The AWS SDK for pandas layer can't be used: its pyarrow is built without S3
# support (pyarrow._s3fs), which pyiceberg's writer imports. boto3/botocore come
# from the Lambda runtime and are removed to save space.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
BUILD="$HERE/build/layer"
OUT="$HERE/build/pyiceberg-layer.zip"
PYICEBERG_VERSION="${PYICEBERG_VERSION:-0.11.1}"
PYARROW_VERSION="${PYARROW_VERSION:-20.0.0}"

rm -rf "$BUILD" "$OUT"
mkdir -p "$BUILD/python"

python3 -m pip install \
  --quiet \
  --platform manylinux2014_aarch64 \
  --implementation cp \
  --python-version 3.12 \
  --only-binary=:all: \
  --target "$BUILD/python" \
  "pyiceberg==${PYICEBERG_VERSION}" "pyarrow==${PYARROW_VERSION}"

cd "$BUILD/python"
for pkg in boto3 botocore s3transfer jmespath; do
  rm -rf "$pkg" "$pkg"-*.dist-info
done
# pyarrow ships headers, static libs and tests that Lambda never loads.
rm -rf pyarrow/include pyarrow/tests pyarrow/src
# Arrow Flight is optional and nothing else links it; dropping it keeps the zip
# under Lambda's 50 MB direct-upload limit. (libarrow_substrait must stay: libarrow_python links it.)
rm -f pyarrow/libarrow_flight.so* pyarrow/_flight*.so pyarrow/flight.py
find pyarrow -name "*.pxd" -delete -o -name "*.pyx" -delete -o -name "*.a" -delete
find . -type d -name "__pycache__" -prune -exec rm -rf {} +
find . -type d -name "tests" -prune -exec rm -rf {} +

cd "$BUILD"
zip -qr9 "$OUT" python
echo "Layer zip: $OUT ($(du -h "$OUT" | cut -f1) zipped, $(du -sh "$BUILD/python" | cut -f1) unzipped)"
