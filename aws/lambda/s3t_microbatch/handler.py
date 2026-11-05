"""Micro-batch replay of S3 Tables rawdata.new_activity into rivdemo_ingest.activity.

One invocation loops through new_activity in rowid order, appending `batch_size`
rows per Iceberg commit and sleeping `wait_seconds` between batches. Each batch is
stamped with the run's date/timestamp, a global batch_seq and the run's run_id.
The loop exits cleanly when the SSM stop flag is "true", when the Lambda is close
to its timeout, or when the last source rowid has been written.

Event (all optional):
  {"batch_size": 50, "wait_seconds": 10, "start_rowid": 1, "max_batches": 40}
  {"single": true}   -> write exactly one batch and return
"""

import json
import logging
import os
import time
from datetime import datetime, timezone
from decimal import Decimal

import boto3
import pyarrow as pa
import pyarrow.compute as pc
from pyiceberg.catalog import load_catalog
from pyiceberg.expressions import And, GreaterThanOrEqual, LessThan

log = logging.getLogger()
log.setLevel(logging.INFO)

REGION = os.environ.get("REGION", "us-west-2")
TABLE_BUCKET_ARN = os.environ["TABLE_BUCKET_ARN"]
SRC = os.environ.get("SRC", "rawdata.new_activity")
TGT = os.environ.get("TGT", "rivdemo_ingest.activity")
BATCH_SIZE = int(os.environ.get("BATCH_SIZE", "50"))
WAIT_SECONDS = float(os.environ.get("WAIT_SECONDS", "10"))
STOP_PARAM = os.environ.get("STOP_PARAM", "/riv-demo/s3t-microbatch/stop")
TIMEOUT_GUARD_MS = 30_000

ssm = boto3.client("ssm", region_name=REGION)


def _catalog():
    return load_catalog(
        "s3tables",
        **{
            "type": "rest",
            "uri": f"https://s3tables.{REGION}.amazonaws.com/iceberg",
            "warehouse": TABLE_BUCKET_ARN,
            "rest.sigv4-enabled": "true",
            "rest.signing-name": "s3tables",
            "rest.signing-region": REGION,
        },
    )


def _stop_requested():
    value = ssm.get_parameter(Name=STOP_PARAM)["Parameter"]["Value"]
    return value.strip().lower() == "true"


def _set_stop(value):
    ssm.put_parameter(Name=STOP_PARAM, Value=value, Type="String", Overwrite=True)


def _max_int(table, column):
    col = table.scan(selected_fields=(column,)).to_arrow().column(column)
    value = pc.max(col).as_py() if len(col) else None
    return int(value) if value is not None else 0


def _utc_now():
    # Iceberg "timestamp" (no zone) == Snowflake TIMESTAMP_NTZ; store UTC wall time.
    return datetime.now(timezone.utc).replace(tzinfo=None)


def _build_batch(src_rows, tgt_schema, run_ts, batch_seq, run_id):
    n = src_rows.num_rows
    generated = {
        "period_ending_date": pa.array([run_ts.date()] * n, pa.date32()),
        "insert_timestamp": pa.array([run_ts] * n, pa.timestamp("us")),
        "batch_seq": pa.array([Decimal(batch_seq)] * n, pa.decimal128(38, 0)),
        "run_id": pa.array([run_id] * n, pa.timestamp("us")),
    }
    arrays = []
    for field in tgt_schema:
        col = generated[field.name] if field.name in generated else src_rows.column(field.name)
        arrays.append(col.cast(field.type))
    return pa.Table.from_arrays(arrays, schema=tgt_schema)


def handler(event, context):
    event = event or {}
    if isinstance(event.get("body"), str):  # tolerate API-style payloads
        event = json.loads(event["body"] or "{}")

    batch_size = int(event.get("batch_size", BATCH_SIZE))
    wait_seconds = float(event.get("wait_seconds", WAIT_SECONDS))
    single = bool(event.get("single", False))
    max_batches = int(event.get("max_batches", 1 if single else 10**9))
    pos = int(event.get("start_rowid", 1))

    _set_stop("false")
    run_id = _utc_now()

    catalog = _catalog()
    src = catalog.load_table(SRC)
    tgt = catalog.load_table(TGT)
    tgt_schema = tgt.schema().as_arrow()

    last_src_rowid = _max_int(src, "rowid")
    seq = _max_int(tgt, "batch_seq")

    summary = {
        "run_id": run_id.isoformat(),
        "batch_size": batch_size,
        "start_rowid": pos,
        "batches_written": 0,
        "rows_written": 0,
    }
    log.info(json.dumps({"event": "run_start", **summary, "last_src_rowid": last_src_rowid, "prior_batch_seq": seq}))

    status = "complete"
    while True:
        if pos > last_src_rowid:
            status = "complete"
            break
        if summary["batches_written"] >= max_batches:
            status = "max_batches_reached"
            break
        if _stop_requested():
            status = "stopped"
            break
        if context is not None and context.get_remaining_time_in_millis() < TIMEOUT_GUARD_MS:
            status = "timeout_guard"
            break

        run_ts = _utc_now()
        row_filter = And(
            GreaterThanOrEqual("rowid", Decimal(pos)),
            LessThan("rowid", Decimal(pos + batch_size)),
        )
        rows = src.scan(row_filter=row_filter).to_arrow().sort_by("rowid")

        seq += 1
        batch = _build_batch(rows, tgt_schema, run_ts, seq, run_id)
        tgt.append(batch)

        rowid_from, rowid_to = pos, min(pos + batch_size - 1, last_src_rowid)
        summary["batches_written"] += 1
        summary["rows_written"] += batch.num_rows
        log.info(json.dumps({
            "event": "batch_committed",
            "run_id": run_id.isoformat(),
            "batch_seq": seq,
            "rows": batch.num_rows,
            "rowid_from": rowid_from,
            "rowid_to": rowid_to,
            "insert_timestamp": run_ts.isoformat(),
            "snapshot_id": tgt.current_snapshot().snapshot_id,
        }))
        pos += batch_size

        if pos > last_src_rowid or summary["batches_written"] >= max_batches:
            continue
        time.sleep(wait_seconds)

    summary.update({"status": status, "next_rowid": pos, "last_batch_seq": seq})
    log.info(json.dumps({"event": "run_end", **summary}))
    return summary
