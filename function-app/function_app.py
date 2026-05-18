import datetime
import json
import logging
import os
import re
from typing import Any

import azure.functions as func
import requests
from azure.storage.blob import AppendBlobClient
from azure.storage.queue import QueueClient

app = func.FunctionApp(http_auth_level=func.AuthLevel.FUNCTION)

GRAPH_SCOPE = "https://graph.microsoft.com/.default"
GRAPH_BASE = "https://graph.microsoft.com/beta"
GRAPH_RESOURCE_REGEX = re.compile(
    r"onlineMeetings(?:\('([^']+)'\)|/([^/]+))/transcripts(?:\('([^']+)'\)|/([^/?]+))"
)


def _required_env(name: str) -> str:
    value = os.getenv(name, "").strip()
    if not value:
        raise ValueError(f"Missing required environment variable: {name}")
    return value


def _get_graph_token() -> str:
    tenant_id = _required_env("GRAPH_TENANT_ID")
    client_id = _required_env("GRAPH_CLIENT_ID")
    client_secret = _required_env("GRAPH_CLIENT_SECRET")

    token_url = f"https://login.microsoftonline.com/{tenant_id}/oauth2/v2.0/token"
    response = requests.post(
        token_url,
        data={
            "client_id": client_id,
            "client_secret": client_secret,
            "scope": GRAPH_SCOPE,
            "grant_type": "client_credentials",
        },
        timeout=30,
    )
    response.raise_for_status()
    return response.json()["access_token"]


def _extract_ids(resource: str) -> tuple[str, str]:
    match = GRAPH_RESOURCE_REGEX.search(resource)
    if not match:
        raise ValueError(f"Unable to parse meeting/transcript IDs from resource: {resource}")

    meeting_id = match.group(1) or match.group(2)
    transcript_id = match.group(3) or match.group(4)

    if not meeting_id or not transcript_id:
        raise ValueError(f"Missing parsed meeting/transcript IDs for resource: {resource}")

    return meeting_id, transcript_id


def _graph_get(url: str, token: str) -> dict[str, Any]:
    response = requests.get(url, headers={"Authorization": f"Bearer {token}"}, timeout=30)
    response.raise_for_status()
    return response.json()


def _graph_get_text(url: str, token: str) -> str:
    response = requests.get(url, headers={"Authorization": f"Bearer {token}"}, timeout=30)
    response.raise_for_status()
    return response.text


def _queue_client() -> QueueClient:
    return QueueClient.from_connection_string(
        conn_str=_required_env("AzureWebJobsStorage"),
        queue_name=os.getenv("TRANSCRIPT_QUEUE_NAME", "transcript-ingestion"),
    )


def _fetch_transcript(notification: dict[str, Any], token: str) -> dict[str, Any]:
    resource = notification.get("resource", "").strip()
    if not resource:
        raise ValueError("Notification is missing 'resource'.")

    meeting_id, transcript_id = _extract_ids(resource)
    metadata_url = f"{GRAPH_BASE}{resource if resource.startswith('/') else f'/{resource}'}"
    content_url = f"{metadata_url}/content"

    metadata = _graph_get(metadata_url, token)
    content = _graph_get_text(content_url, token)

    return {
        "meeting_id": meeting_id,
        "transcript_id": transcript_id,
        "resource": resource,
        "metadata": metadata,
        "content": content,
        "received_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    }


def _analyze_transcript(content: str, metadata: dict[str, Any]) -> str:
    endpoint = _required_env("AZURE_OPENAI_ENDPOINT").rstrip("/")
    deployment = _required_env("AZURE_OPENAI_DEPLOYMENT")
    api_key = _required_env("AZURE_OPENAI_API_KEY")

    prompt = (
        "Analyze the Microsoft Teams transcript and return markdown with:\n"
        "1) Summary\n2) Key decisions\n3) Action items (owner, task, due date if present)\n"
        "4) Risks/blockers\n5) Sentiment (brief)\n"
        "Keep output concise and factual."
    )

    body = {
        "messages": [
            {"role": "system", "content": "You analyze meeting transcripts for operational follow-up."},
            {"role": "user", "content": f"Metadata:\n{json.dumps(metadata, default=str)}\n\nTranscript:\n{content}"},
            {"role": "user", "content": prompt},
        ],
        "temperature": 0.2,
        "max_tokens": 1200,
    }

    url = f"{endpoint}/openai/deployments/{deployment}/chat/completions?api-version=2024-10-21"
    response = requests.post(url, headers={"api-key": api_key, "Content-Type": "application/json"}, json=body, timeout=60)
    response.raise_for_status()
    data = response.json()
    return data["choices"][0]["message"]["content"].strip()


def _append_analysis(markdown_section: str) -> None:
    connection_string = _required_env("AzureWebJobsStorage")
    container_name = os.getenv("ANALYSIS_BLOB_CONTAINER", "analysis-docs")
    blob_name = os.getenv("ANALYSIS_BLOB_NAME", "teams-transcript-analysis.md")

    append_client = AppendBlobClient.from_connection_string(
        conn_str=connection_string,
        container_name=container_name,
        blob_name=blob_name,
    )

    if not append_client.exists():
        append_client.create_append_blob()

    append_client.append_block(markdown_section.encode("utf-8"))


def _upsert_subscription(token: str) -> dict[str, Any]:
    subscription_id = os.getenv("GRAPH_SUBSCRIPTION_ID", "").strip()
    notification_url = _required_env("GRAPH_NOTIFICATION_URL")
    resource = os.getenv("GRAPH_SUBSCRIPTION_RESOURCE", "/communications/onlineMeetings/getAllTranscripts")
    client_state = _required_env("GRAPH_SUBSCRIPTION_CLIENT_STATE")
    expires_at = (datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(hours=48)).strftime("%Y-%m-%dT%H:%M:%SZ")

    headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}

    if subscription_id:
        renew_url = f"{GRAPH_BASE}/subscriptions/{subscription_id}"
        patch = requests.patch(renew_url, headers=headers, json={"expirationDateTime": expires_at}, timeout=30)
        if patch.ok:
            return patch.json()
        logging.warning("Failed to renew configured subscription '%s'; creating a new one.", subscription_id)

    create_url = f"{GRAPH_BASE}/subscriptions"
    payload = {
        "changeType": "created",
        "notificationUrl": notification_url,
        "resource": resource,
        "expirationDateTime": expires_at,
        "clientState": client_state,
    }
    response = requests.post(create_url, headers=headers, json=payload, timeout=30)
    response.raise_for_status()
    return response.json()


@app.function_name(name="GraphNotifications")
@app.route(route="graph/notifications", methods=["GET", "POST"], auth_level=func.AuthLevel.FUNCTION)
def graph_notifications(req: func.HttpRequest) -> func.HttpResponse:
    validation_token = req.params.get("validationToken")
    if validation_token:
        return func.HttpResponse(validation_token, status_code=200, mimetype="text/plain")

    try:
        body = req.get_json()
    except ValueError:
        return func.HttpResponse("Invalid JSON payload", status_code=400)

    notifications = body.get("value", [])
    if not notifications:
        return func.HttpResponse(status_code=202)

    client_state = os.getenv("GRAPH_SUBSCRIPTION_CLIENT_STATE", "")
    queue_client = _queue_client()
    queue_client.create_queue()
    token = _get_graph_token()

    for notification in notifications:
        incoming_state = notification.get("clientState", "")
        if client_state and incoming_state != client_state:
            logging.warning("Discarding notification with invalid clientState.")
            continue

        try:
            transcript_payload = _fetch_transcript(notification, token)
            queue_client.send_message(json.dumps(transcript_payload))
        except Exception as exc:  # noqa: BLE001
            logging.exception("Failed to process transcript notification: %s", exc)

    return func.HttpResponse(status_code=202)


@app.function_name(name="AnalyzeTranscript")
@app.queue_trigger(arg_name="msg", queue_name="%TRANSCRIPT_QUEUE_NAME%", connection="AzureWebJobsStorage")
def analyze_transcript(msg: func.QueueMessage) -> None:
    payload = json.loads(msg.get_body().decode("utf-8"))
    metadata = payload.get("metadata", {})
    transcript = payload.get("content", "")

    if not transcript.strip():
        logging.warning("Queue message missing transcript content; skipping.")
        return

    analysis = _analyze_transcript(transcript, metadata)
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M:%SZ")
    section = (
        f"\n\n## Meeting Transcript Analysis ({stamp})\n"
        f"- Meeting ID: `{payload.get('meeting_id', 'unknown')}`\n"
        f"- Transcript ID: `{payload.get('transcript_id', 'unknown')}`\n\n"
        f"{analysis}\n"
    )
    _append_analysis(section)


@app.function_name(name="RenewGraphSubscription")
@app.timer_trigger(schedule="0 0 */12 * * *", arg_name="timer", run_on_startup=False, use_monitor=True)
def renew_graph_subscription(timer: func.TimerRequest) -> None:
    if timer.past_due:
        logging.warning("Subscription renewal timer is running late.")

    token = _get_graph_token()
    subscription = _upsert_subscription(token)
    logging.info("Graph subscription ensured. ID=%s Expires=%s", subscription.get("id"), subscription.get("expirationDateTime"))
