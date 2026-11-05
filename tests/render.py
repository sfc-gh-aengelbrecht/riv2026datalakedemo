#!/usr/bin/env python3
"""Render repo SQL with renamed objects.

Prefix mode (E2E test next to a working install):
  python3 tests/render.py <prefix> <user_prefix> <out_dir>
  e.g. python3 tests/render.py RIVTEST rivtest /tmp/rivtest_sql
  Every account-level object name becomes <prefix>_*; the shared AWS role is kept.

Config mode (per-user install, used by skills/riv-lakehouse-demo):
  python3 tests/render.py --config <config.json> <out_dir>
  config keys: user_prefix, warehouse, s3t_cat_int, s3t_db, glue_cat_int, glue_db,
               ext_vol, snow_db, role_arn, bucket
  Also replaces the shared role ARN and the shared external volume bucket.

The demo role RIV_DEMO_RL is kept in both modes.
"""
import json
import pathlib
import re
import sys

PROD = {
    "warehouse": "RIV_DEMO_WH",
    "s3t_cat_int": "RIV_DEMO_S3T_CAT_INT",
    "s3t_db": "RIV_DEMO_S3T_DB",
    "glue_cat_int": "RIV_DEMO_2026_GLUE_CAT_INT",
    "glue_db": "RIV2026DATALAKEDEMO",
    "ext_vol": "RIV_DEMO_2026_SNOW_EXT_VOL",
    "snow_db": "RIV2026DL_SNOW",
}
PROD_ROLE_ARN = "arn:aws:iam::484577546576:role/riv-demo-2026-shared-role"
PROD_BUCKET = "riv-demo-2026-snow-w2"

IDENT = re.compile(r"[A-Z][A-Z0-9_]*")
LOWER = re.compile(r"[a-z][a-z0-9_]*")
BUCKET = re.compile(r"[a-z0-9][a-z0-9-]{1,61}[a-z0-9]")
ROLE_ARN = re.compile(r"arn:aws:iam::\d{12}:role/[A-Za-z0-9+=,.@_-]+")


def usage():
    sys.exit(__doc__)


args = sys.argv[1:]
literal = {}  # exact string replacements (AWS identifiers)
if args[:1] == ["--config"]:
    if len(args) != 3:
        usage()
    cfg = json.loads(pathlib.Path(args[1]).read_text())
    out = pathlib.Path(args[2])
    missing = [k for k in [*PROD, "user_prefix", "role_arn", "bucket"] if k not in cfg]
    if missing:
        sys.exit(f"config missing keys: {', '.join(missing)}")
    for key in PROD:
        if not IDENT.fullmatch(cfg[key]):
            sys.exit(f"{key} must be UPPER_SNAKE: {cfg[key]}")
    if not LOWER.fullmatch(cfg["user_prefix"]):
        sys.exit("user_prefix must be lower_snake")
    if not BUCKET.fullmatch(cfg["bucket"]):
        sys.exit(f"invalid bucket name: {cfg['bucket']}")
    if not ROLE_ARN.fullmatch(cfg["role_arn"]):
        sys.exit(f"invalid role ARN: {cfg['role_arn']}")
    renames = {PROD[k]: cfg[k] for k in PROD}
    user_prefix = cfg["user_prefix"]
    literal = {PROD_ROLE_ARN: cfg["role_arn"], PROD_BUCKET: cfg["bucket"]}
else:
    if len(args) != 3:
        usage()
    prefix, user_prefix, out = args[0], args[1], pathlib.Path(args[2])
    if not IDENT.fullmatch(prefix) or not LOWER.fullmatch(user_prefix):
        sys.exit("prefix must be UPPER_SNAKE, user_prefix lower_snake")
    suffix = {"warehouse": "WH", "s3t_cat_int": "S3T_CAT_INT", "s3t_db": "S3T_DB",
              "glue_cat_int": "GLUE_CAT_INT", "glue_db": "GLUE_DB",
              "ext_vol": "SNOW_EXT_VOL", "snow_db": "SNOW_DB"}
    renames = {PROD[k]: f"{prefix}_{suffix[k]}" for k in PROD}

pattern = re.compile(r"\b(" + "|".join(map(re.escape, renames)) + r")\b")

root = pathlib.Path(__file__).resolve().parent.parent
for src in sorted((root / "sql").rglob("*.sql")):
    text = src.read_text()
    for old, new in literal.items():
        text = text.replace(old, new)
    text = pattern.sub(lambda m: renames[m.group(1)], text)
    text = text.replace("__user_prefix__", user_prefix)
    dst = out / src.relative_to(root / "sql")
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_text(text)
    print(dst)
