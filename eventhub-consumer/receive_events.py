"""
Azure Event Hub Consumer - Read APIM log events from Event Hub.

Uses DefaultAzureCredential (supports Azure CLI, Managed Identity, etc.)
to authenticate against the Event Hub namespace.

Usage:
    python receive_events.py
"""

import json
import signal
import sys
from azure.eventhub import EventHubConsumerClient
from azure.identity import AzureCliCredential

# ── Configuration ───────────────────────────────────────────────────────────
EVENTHUB_NAMESPACE = "myapilogger-hub.servicebus.windows.net"
EVENTHUB_NAME = "apim-logs"
CONSUMER_GROUP = "$Default"
# ────────────────────────────────────────────────────────────────────────────

shutdown = False


def on_event(partition_context, event):
    """Callback invoked for each received event."""
    partition_id = partition_context.partition_id
    offset = event.offset
    seq = event.sequence_number
    enqueued = event.enqueued_time

    body = event.body_as_str(encoding="UTF-8")

    print(f"\n{'='*60}")
    print(f"Partition : {partition_id}")
    print(f"Sequence  : {seq}")
    print(f"Offset    : {offset}")
    print(f"Enqueued  : {enqueued}")
    print(f"{'─'*60}")

    # Try to pretty-print JSON; fall back to raw text
    try:
        parsed = json.loads(body)
        print(json.dumps(parsed, indent=2))
    except (json.JSONDecodeError, TypeError):
        print(body)

    print(f"{'='*60}")

    # Update checkpoint so we don't re-read the same events on restart
    partition_context.update_checkpoint(event)


def on_error(partition_context, error):
    """Callback for errors during receive."""
    pid = partition_context.partition_id if partition_context else "N/A"
    print(f"[ERROR] Partition {pid}: {error}", file=sys.stderr)


def on_partition_initialize(partition_context):
    print(f"[INFO] Partition {partition_context.partition_id} initialized")


def on_partition_close(partition_context, reason):
    print(f"[INFO] Partition {partition_context.partition_id} closed: {reason}")


def main():
    credential = AzureCliCredential()

    client = EventHubConsumerClient(
        fully_qualified_namespace=EVENTHUB_NAMESPACE,
        eventhub_name=EVENTHUB_NAME,
        consumer_group=CONSUMER_GROUP,
        credential=credential,
    )

    def handle_signal(sig, frame):
        global shutdown
        print("\n[INFO] Shutting down...")
        shutdown = True

    signal.signal(signal.SIGINT, handle_signal)

    print(f"Listening on {EVENTHUB_NAMESPACE}/{EVENTHUB_NAME} ...")
    print("Press Ctrl+C to stop.\n")

    with client:
        client.receive(
            on_event=on_event,
            on_error=on_error,
            on_partition_initialize=on_partition_initialize,
            on_partition_close=on_partition_close,
            starting_position="-1",  # from beginning of stream
        )


if __name__ == "__main__":
    main()
