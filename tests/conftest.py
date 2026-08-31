"""Test fixtures for the skill workbench proxy.

``handler.py`` reads six environment variables and constructs two boto3 clients at
module scope, so both have to be in place *before* the import below — which is why the
environment is set here at import time rather than in a fixture.

That import-time coupling is worth keeping in mind rather than designing around: it is
what makes a missing environment variable fail the Lambda cold start loudly instead of
failing the first request that happens to need it.
"""

import os
import sys
from pathlib import Path

import pytest

HANDLER_DIR = Path(__file__).resolve().parent.parent / "lambda" / "proxy"
sys.path.insert(0, str(HANDLER_DIR))

# Values a test can assert against, not realistic ones. The region is required because
# boto3.client() raises NoRegionError without one, even though no call is ever made.
os.environ.setdefault("AWS_DEFAULT_REGION", "us-east-1")
os.environ.setdefault("BUCKET_NAME", "test-skill-bucket")
os.environ.setdefault("KMS_KEY_ARN", "arn:aws:kms:us-east-1:111122223333:key/test")
os.environ.setdefault(
    "HARNESS_ARN",
    "arn:aws:bedrock-agentcore:us-east-1:111122223333:harness/demo_skill_workbench",
)
os.environ.setdefault("USERS_PREFIX", "users")
os.environ.setdefault("SHARED_PREFIX", "shared")
os.environ.setdefault("DEFAULT_MODEL_ID", "us.anthropic.claude-sonnet-4-6")
os.environ.setdefault(
    "ALLOWED_MODEL_IDS",
    "us.anthropic.claude-sonnet-4-6,us.anthropic.claude-haiku-4-5",
)

import handler as handler_module  # noqa: E402

CALLER_UUID = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"


class FakeIdentity:
    def __init__(self, cognito_identity_id):
        self.cognito_identity_id = cognito_identity_id


class FakeContext:
    """Stands in for the Lambda context object.

    Two groups of attributes, and the distinction is worth keeping:

    ``identity`` is the only one ``handler.py`` itself reads. It stays minimal so that a
    change in how identity is resolved fails here rather than passing against a permissive
    mock.

    The other four are required by Powertools, not by this function. ``handler`` carries
    ``@logger.inject_lambda_context``, which calls ``build_lambda_context_model`` on the
    way in, and that reads exactly ``function_name``, ``memory_limit_in_mb``,
    ``invoked_function_arn`` and ``aws_request_id`` — omitting any one of them fails the
    decorator with an AttributeError before the handler body runs, which looks like a
    handler bug and is not one. Powertools documents the same minimum:
    https://docs.aws.amazon.com/powertools/python/latest/core/logger/#inject-lambda-context

    Values are chosen to be assertable rather than realistic, except memory and the name,
    which mirror what proxy.tf actually configures.
    """

    def __init__(self, cognito_identity_id=f"us-east-1:{CALLER_UUID}"):
        self.aws_request_id = "test-request-id"
        self.identity = FakeIdentity(cognito_identity_id) if cognito_identity_id else None

        self.function_name = "test-skill-workbench-proxy"
        self.memory_limit_in_mb = 512
        self.invoked_function_arn = (
            "arn:aws:lambda:us-east-1:111122223333:function:test-skill-workbench-proxy"
        )


@pytest.fixture
def handler():
    return handler_module


@pytest.fixture
def context():
    """An authenticated caller, region-qualified as Lambda supplies it."""
    return FakeContext()


@pytest.fixture
def anonymous_context():
    """A caller with no Cognito identity, as an IAM-signed invocation would be."""
    return FakeContext(cognito_identity_id=None)


@pytest.fixture
def s3_spy(monkeypatch):
    """Replaces the S3 client and records put_object calls, so no bucket is needed."""
    calls = []

    class FakeS3:
        def put_object(self, **kwargs):
            calls.append(kwargs)
            return {}

    monkeypatch.setattr(handler_module, "s3", FakeS3())
    return calls


@pytest.fixture(autouse=True)
def no_real_aws_calls(monkeypatch):
    """Fail loudly if a test reaches an AWS endpoint.

    Added after a test that stubbed only the AgentCore client made a real ListObjectsV2
    call, because the code path it exercised had grown an S3 dependency. It failed on a
    malformed credential rather than on the assertion, which is luck: with valid
    credentials in the environment it would have passed while talking to production.
    """

    def refuse(self, operation_name, *args, **kwargs):
        raise AssertionError(
            f"test attempted a real AWS call: {operation_name}. "
            "Stub the client it uses — see the s3_get_spy, skill_dirs and agentcore_spy fixtures."
        )

    monkeypatch.setattr("botocore.client.BaseClient._make_api_call", refuse)


@pytest.fixture
def skill_dirs(monkeypatch):
    """Stubs S3 so the invoke path can enumerate skill directories.

    Returns CommonPrefixes, as a Delimiter="/" listing does, because that is what the
    handler must read: each s3.uri names one skill *directory*, so it has to discover the
    directories rather than hand over the prefix that contains them.
    """
    listings = {
        f"users/{CALLER_UUID}/": ["my-first-skill/", "terraform-review/"],
        "shared/": ["skill-authoring/", "terraform-review/"],
    }

    class FakePaginator:
        def paginate(self, **kwargs):
            children = listings.get(kwargs["Prefix"], [])
            assert kwargs.get("Delimiter") == "/", (
                "enumeration must use Delimiter='/' so S3 names the directories rather "
                "than returning every object under them"
            )
            return [{"CommonPrefixes": [{"Prefix": kwargs["Prefix"] + c} for c in children]}]

    class FakeS3:
        def get_paginator(self, name):
            assert name == "list_objects_v2"
            return FakePaginator()

    monkeypatch.setattr(handler_module, "s3", FakeS3())
    return listings


@pytest.fixture
def s3_get_spy(monkeypatch):
    """Replaces the S3 client for the read path, recording get_object calls."""
    calls = []

    class Body:
        def read(self):
            return b"file body"

    class FakeS3:
        class exceptions:
            class NoSuchKey(Exception):
                pass

        def get_object(self, **kwargs):
            calls.append(kwargs)
            return {"Body": Body()}

    monkeypatch.setattr(handler_module, "s3", FakeS3())
    return calls


@pytest.fixture
def agentcore_spy(monkeypatch):
    """Replaces the AgentCore client, recording calls and **validating them**.

    The validation is the point. An earlier version of this fixture accepted any keyword
    arguments, so the whole suite passed against a handler that called `invoke_harness`
    with four wrong parameters — `harnessId` instead of `harnessArn`, a `payload` blob
    instead of `messages`, a model string instead of a structure, and a response read as
    a body rather than an event stream. Asserting on what we *send* proves nothing about
    whether the call is *valid*.

    So the params go through botocore's own ParamValidator against the real service
    model. That needs no credentials and makes no network call — the model ships with
    botocore — and it turns these into contract tests.
    """
    import boto3
    from botocore.validate import ParamValidator

    model = (
        boto3.client("bedrock-agentcore", region_name="us-east-1")
        .meta.service_model.operation_model("InvokeHarness")
        .input_shape
    )
    validator = ParamValidator()
    calls = []

    class ValidatingAgentCore:
        def invoke_harness(self, **kwargs):
            report = validator.validate(kwargs, model)
            if report.has_errors():
                raise AssertionError(
                    "invoke_harness called with parameters the service model rejects:\n"
                    + report.generate_report()
                )
            calls.append(kwargs)
            return {"stream": list(STREAM_EVENTS)}

    monkeypatch.setattr(handler_module, "agentcore", ValidatingAgentCore())
    return calls


# A minimal but realistic InvokeHarness event stream: one text delta, a tool use, a stop
# reason and usage metadata. Shapes taken from the service model's output shape.
STREAM_EVENTS = [
    {"messageStart": {"role": "assistant"}},
    {"contentBlockStart": {"contentBlockIndex": 0, "start": {"toolUse": {"toolUseId": "t1", "name": "file_operations"}}}},
    {"contentBlockDelta": {"contentBlockIndex": 0, "delta": {"text": "Hello"}}},
    {"contentBlockDelta": {"contentBlockIndex": 0, "delta": {"text": " world"}}},
    {"contentBlockStop": {"contentBlockIndex": 0}},
    {"messageStop": {"stopReason": "end_turn"}},
    {"metadata": {"usage": {"inputTokens": 10, "outputTokens": 2, "totalTokens": 12}, "metrics": {"latencyMs": 500}}},
]


VALID_SKILL = """---
name: terraform-review
description: Reviews Terraform for the conventions in this repository.
---

Read the plan before the code.
"""
