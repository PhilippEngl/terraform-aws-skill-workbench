"""Proxy between browser credentials and the harness API for the skill workbench.

Two entry paths, selected by the ``action`` field: ``save_skill`` and ``invoke``.
Both live here rather than in the browser because both carry a privilege the browser
must not hold.

The security posture is *construct, never forward*. AWS states the harness does not
validate, sanitise or inspect skill content or source, and ``additionalParams``
passes through unchanged — LiteLLM's ``aws_bedrock_runtime_endpoint`` will redirect a
SigV4-signed request to an arbitrary endpoint, and ``aws_role_name`` will attempt
role assumption. So this function:

* builds the ``skills`` array itself from the caller's Cognito sub plus ``shared/``,
  and discards any client-supplied ``skills``
* accepts a model *name* from a fixed enum and builds the model config itself,
  discarding any client-supplied ``model`` or ``additionalParams``
* validates YAML frontmatter before ``PutObject``, because a malformed ``SKILL.md``
  fails the whole invocation rather than being skipped

The caller's identity comes from the Lambda request context, never from the payload.
"""

import os
import re
import uuid

import boto3
from botocore.exceptions import ParamValidationError
from aws_lambda_powertools import Logger
from aws_lambda_powertools.utilities.typing import LambdaContext

logger = Logger()

s3 = boto3.client("s3")
agentcore = boto3.client("bedrock-agentcore")

BUCKET_NAME = os.environ["BUCKET_NAME"]
KMS_KEY_ARN = os.environ["KMS_KEY_ARN"]
HARNESS_ARN = os.environ["HARNESS_ARN"]
USERS_PREFIX = os.environ.get("USERS_PREFIX", "users")
SHARED_PREFIX = os.environ.get("SHARED_PREFIX", "shared")
DEFAULT_MODEL_ID = os.environ["DEFAULT_MODEL_ID"]
ALLOWED_MODEL_IDS = [m for m in os.environ["ALLOWED_MODEL_IDS"].split(",") if m]
SKILL_NAME_PATTERN = re.compile(r"^[a-z0-9][a-z0-9-]{0,63}$")
RELATIVE_PATH_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._/-]{0,255}$")

MAX_SKILL_BYTES = 256 * 1024

# Mirrors the service constraint on InvokeHarness runtimeSessionId: min 33, max 100,
# pattern [a-zA-Z0-9][a-zA-Z0-9-_]*. Enforced here so a client-supplied ID is refused
# with a message rather than raising ParamValidationError inside botocore.
SESSION_ID_PATTERN = re.compile(r"^[a-zA-Z0-9][a-zA-Z0-9-_]{32,99}$")


class RejectedError(Exception):
    """Caller error. Surfaced to the browser verbatim; never wraps an AWS error."""

@logger.inject_lambda_context(log_event=True)
def handler(event, context: LambdaContext):
    action = (event or {}).get("action")
    try:
        caller_sub = _caller_sub(event, context)

        if action == "save_skill":
            return _ok(_save_skill(event, caller_sub))
        if action == "list_skills":
            return _ok(_list_skills(caller_sub))
        if action == "read_file":
            return _ok(_read_file(event, caller_sub))
        if action == "invoke":
            return _ok(_invoke(event, caller_sub))

        raise RejectedError(f"Unknown action: {action!r}")
    except RejectedError as exc:
        logger.warning("Rejected %s: %s", action, exc)
        return {"ok": False, "error": str(exc)}
    except ParamValidationError as exc:
        logger.error("Parameter validation failed in action %s: %s", action, exc)
        return {"ok": False, "error": f"Client SDK rejected the call: {exc}"}
    except Exception:
        # Deliberately opaque. The browser gets a correlation ID; the detail stays in
        # CloudWatch, where an S3 key or an ARN is not a disclosure.
        logger.exception("Unhandled error in action %s", action)
        return {
            "ok": False,
            "error": "Internal error",
            "request_id": getattr(context, "aws_request_id", None),
        }


# --- Identity -----------------------------------------------------------------


def _caller_sub(event, context):
    """The Cognito identity of the caller, taken from the request context only.

    The browser invokes this function directly with credentials from the identity
    pool, so Lambda populates ``identity.cognito_identity_id``. A sub in the payload
    is ignored — trusting one would let any authenticated user read and write any
    other user's skills.
    """
    identity = getattr(context, "identity", None)
    identity_id = getattr(identity, "cognito_identity_id", None) if identity else None

    if not identity_id:
        raise RejectedError("Unauthenticated: no Cognito identity on the request")

    return identity_id.split(":")[-1]


# --- Skill authoring ----------------------------------------------------------


def _save_skill(event, caller_sub):
    skill_name = event.get("skill_name")
    if not skill_name or not SKILL_NAME_PATTERN.match(str(skill_name)):
        raise RejectedError(
            "skill_name must be kebab-case, start alphanumeric, 64 characters maximum"
        )

    relative_path = event.get("path", "SKILL.md")
    if not RELATIVE_PATH_PATTERN.match(str(relative_path)) or ".." in relative_path:
        raise RejectedError("path contains characters that are not allowed")

    content = event.get("content")
    if not isinstance(content, str):
        raise RejectedError("content must be a string")

    encoded = content.encode("utf-8")
    if len(encoded) > MAX_SKILL_BYTES:
        raise RejectedError(f"content exceeds {MAX_SKILL_BYTES} bytes")

    # Only SKILL.md carries frontmatter. references/ and scripts/ are opaque.
    if relative_path == "SKILL.md":
        _validate_frontmatter(content, skill_name)

    key = f"{USERS_PREFIX}/{caller_sub}/{skill_name}/{relative_path}"

    s3.put_object(
        Bucket=BUCKET_NAME,
        Key=key,
        Body=encoded,
        ContentType="text/markdown; charset=utf-8",
        ServerSideEncryption="aws:kms",
        SSEKMSKeyId=KMS_KEY_ARN,
    )

    logger.info("Saved %s (%d bytes)", key, len(encoded))

    return {"key": key, "bytes": len(encoded), "requires_session_refresh": True}


def _validate_frontmatter(content, skill_name):
    """Reject a SKILL.md the harness would choke on.

    This is the whole reason writes are mediated. A malformed skill fails the entire
    invocation rather than being skipped, so an unvalidated write leaves an agent
    broken with an error that does not name the cause.

    Parsed by hand rather than with PyYAML: the two required keys are simple scalars,
    and a stdlib-only handler needs no dependency layer.
    """
    lines = content.split("\n")

    if not lines or lines[0].strip() != "---":
        raise RejectedError("SKILL.md must open with a --- frontmatter delimiter")

    try:
        end = next(i for i, line in enumerate(lines[1:], start=1) if line.strip() == "---")
    except StopIteration:
        raise RejectedError("Frontmatter is never closed by a second ---")

    fields = {}
    for line in lines[1:end]:
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if "\t" in line:
            raise RejectedError("Frontmatter contains a tab character, which is not valid YAML")
        if ":" not in line:
            raise RejectedError(f"Frontmatter line is not a key: value pair: {line.strip()!r}")
        key, _, value = line.partition(":")
        fields[key.strip()] = value.strip().strip("\"'")

    for required in ("name", "description"):
        if not fields.get(required):
            raise RejectedError(f"Frontmatter is missing a non-empty {required}")

    if fields["name"] != skill_name:
        raise RejectedError(
            f"Frontmatter name {fields['name']!r} does not match the directory {skill_name!r}"
        )

    if len(lines) <= end + 1 or not "\n".join(lines[end + 1 :]).strip():
        raise RejectedError("SKILL.md has frontmatter but no body")

    return fields


def _list_skills(caller_sub):
    prefix = f"{USERS_PREFIX}/{caller_sub}/"
    paginator = s3.get_paginator("list_objects_v2")

    keys = [
        obj["Key"]
        for page in paginator.paginate(Bucket=BUCKET_NAME, Prefix=prefix)
        for obj in page.get("Contents", [])
    ]

    return {"prefix": prefix, "keys": sorted(keys)}


def _read_file(event, caller_sub):
    """Return one of the caller's own skill files.

    Mediated for the same reason writes are, though the reason is different. Scoping the
    browser's own S3 access per user means an IAM condition on
    ``${cognito-identity.amazonaws.com:sub}``, and that variable expands to the
    *region-qualified* identity ID — ``<region>:<uuid>`` — while a usable key segment
    and a usable ``actorId`` both want the bare UUID. Reconciling those in IAM is not
    possible, because a policy cannot strip the region.

    Deriving the key here from the request context sidesteps it: the browser holds only
    ``lambda:InvokeFunction`` and needs no bucket, prefix or KMS grant at all.
    """
    skill_name = event.get("skill_name")
    if not skill_name or not SKILL_NAME_PATTERN.match(str(skill_name)):
        raise RejectedError("skill_name must be kebab-case, start alphanumeric, 64 characters maximum")

    relative_path = event.get("path", "SKILL.md")
    if not RELATIVE_PATH_PATTERN.match(str(relative_path)) or ".." in relative_path:
        raise RejectedError("path contains characters that are not allowed")

    key = f"{USERS_PREFIX}/{caller_sub}/{skill_name}/{relative_path}"

    try:
        body = s3.get_object(Bucket=BUCKET_NAME, Key=key)["Body"].read()
    except s3.exceptions.NoSuchKey:
        raise RejectedError(f"No such file: {skill_name}/{relative_path}")

    return {"key": key, "content": body.decode("utf-8")}


# --- Invocation ---------------------------------------------------------------


def _skill_directories(prefix):
    """The immediate child directories of ``prefix``, each one a skill.

    Uses Delimiter="/" so S3 returns CommonPrefixes — one round trip that names the
    directories, rather than listing every object and deriving them. A skill carrying
    references/ and scripts/ would otherwise be walked in full to learn its own name.

    Returns prefixes with their trailing slash intact, because that is what the service
    expects an s3.uri to end with.
    """
    paginator = s3.get_paginator("list_objects_v2")
    return [
        common["Prefix"]
        for page in paginator.paginate(Bucket=BUCKET_NAME, Prefix=prefix, Delimiter="/")
        for common in page.get("CommonPrefixes", [])
    ]


def _invoke(event, caller_sub):
    prompt = event.get("prompt")
    if not isinstance(prompt, str) or not prompt.strip():
        raise RejectedError("prompt must be a non-empty string")

    model_id = event.get("model_id") or DEFAULT_MODEL_ID
    if model_id not in ALLOWED_MODEL_IDS:
        raise RejectedError(f"model_id must be one of: {', '.join(ALLOWED_MODEL_IDS)}")

    skills = [
        {"s3": {"uri": f"s3://{BUCKET_NAME}/{prefix}"}}
        for prefix in _skill_directories(f"{USERS_PREFIX}/{caller_sub}/")
        + _skill_directories(f"{SHARED_PREFIX}/")
    ]

    session_id = event.get("session_id") or str(uuid.uuid4())
    if not SESSION_ID_PATTERN.match(str(session_id)):
        raise RejectedError(
            "session_id must be 33 to 100 characters of letters, digits, dash or "
            "underscore, starting alphanumeric"
        )

    logger.info(
        "Invoking harness %s for actor %s in session %s with model %s",
        HARNESS_ARN,
        caller_sub,
        session_id,
        model_id,
    )

    request = {
        "harnessArn": HARNESS_ARN,
        "runtimeSessionId": session_id,
        "actorId": caller_sub,
        "model": {"bedrockModelConfig": {"modelId": model_id}},
        "messages": [{"role": "user", "content": [{"text": prompt}]}],
    }
    
    if skills:
        request["skills"] = skills


    response = agentcore.invoke_harness(**request)

    return {
        "session_id": session_id,
        "model_id": model_id,
        "skill_sources": [s["s3"]["uri"] for s in skills],
        **_read_stream(response),
    }


def _read_stream(response):
    """Accumulate the assistant's text from the InvokeHarness event stream.

    The response is an event stream rather than a body, so there is nothing to read
    until it is iterated. Only text deltas are accumulated; tool use and reasoning
    blocks are counted so the caller can tell a silent turn from an inactive one, which
    matters here because a mismatched `allowed_tools` leaves the model with no tools and
    no error.

    Both in-band exception events are raised rather than returned. They arrive as
    ordinary stream members, so ignoring them would surface a service-side validation
    failure as an empty but successful reply.
    """
    chunks = []
    tool_uses = []
    stop_reason = None
    usage = None

    for event in response["stream"]:
        if "contentBlockDelta" in event:
            delta = event["contentBlockDelta"].get("delta", {})
            if "text" in delta:
                chunks.append(delta["text"])
        elif "contentBlockStart" in event:
            start = event["contentBlockStart"].get("start", {})
            if "toolUse" in start:
                tool_uses.append(start["toolUse"].get("name"))
        elif "messageStop" in event:
            stop_reason = event["messageStop"].get("stopReason")
        elif "metadata" in event:
            usage = event["metadata"].get("usage")
        elif "validationException" in event:
            raise RejectedError(event["validationException"].get("message", "Validation failed"))
        elif "internalServerException" in event:
            raise RuntimeError(event["internalServerException"].get("message", "Internal error"))
        elif "runtimeClientError" in event:
            raise RuntimeError(event["runtimeClientError"].get("message", "Runtime client error"))

    return {
        "response": "".join(chunks),
        "tool_uses": tool_uses,
        "stop_reason": stop_reason,
        "usage": usage,
    }


def _ok(body):
    return {"ok": True, **body}
