"""Tests for the skill workbench proxy."""

import pytest

from conftest import CALLER_UUID, VALID_SKILL


# --- Identity is never taken from the payload ---------------------------------


class TestCallerIdentity:
    def test_region_qualified_id_reduces_to_the_uuid(self, handler, context):
        # The key segment must match ${cognito-identity.amazonaws.com:sub}, which is the
        # bare UUID, not the "region:uuid" form Lambda supplies.
        assert handler._caller_sub({}, context) == CALLER_UUID

    def test_missing_identity_is_rejected(self, handler, anonymous_context):
        with pytest.raises(handler.RejectedError, match="Unauthenticated"):
            handler._caller_sub({}, anonymous_context)

    def test_payload_sub_cannot_supply_identity(self, handler, anonymous_context):
        # The whole tenancy boundary rests on this: a payload sub must not be a fallback.
        event = {"sub": "victim-uuid", "caller_sub": "victim-uuid", "actorId": "victim-uuid"}
        with pytest.raises(handler.RejectedError, match="Unauthenticated"):
            handler._caller_sub(event, anonymous_context)

    def test_payload_sub_does_not_override_the_context(self, handler, context):
        event = {"sub": "victim-uuid"}
        assert handler._caller_sub(event, context) == CALLER_UUID


# --- Frontmatter validation ---------------------------------------------------
# A malformed SKILL.md fails the entire invocation rather than being skipped, so these
# rejections are the reason writes are mediated at all.


class TestFrontmatterValidation:
    def test_valid_frontmatter_returns_its_fields(self, handler):
        fields = handler._validate_frontmatter(VALID_SKILL, "terraform-review")
        assert fields["name"] == "terraform-review"
        assert fields["description"].startswith("Reviews Terraform")

    def test_quoted_values_are_unquoted(self, handler):
        content = '---\nname: "my-skill"\ndescription: \'Quoted.\'\n---\n\nBody.\n'
        fields = handler._validate_frontmatter(content, "my-skill")
        assert fields["name"] == "my-skill"
        assert fields["description"] == "Quoted."

    def test_comments_and_blank_lines_are_skipped(self, handler):
        content = "---\n# a comment\n\nname: my-skill\ndescription: Fine.\n---\n\nBody.\n"
        assert handler._validate_frontmatter(content, "my-skill")["name"] == "my-skill"

    def test_missing_opening_delimiter_is_rejected(self, handler):
        with pytest.raises(handler.RejectedError, match="must open with"):
            handler._validate_frontmatter("name: my-skill\n\nBody.\n", "my-skill")

    def test_unclosed_frontmatter_is_rejected(self, handler):
        with pytest.raises(handler.RejectedError, match="never closed"):
            handler._validate_frontmatter("---\nname: my-skill\n\nBody.\n", "my-skill")

    def test_tab_character_is_rejected(self, handler):
        # Tabs are invalid YAML indentation and the failure downstream is obscure.
        content = "---\nname:\tmy-skill\ndescription: Fine.\n---\n\nBody.\n"
        with pytest.raises(handler.RejectedError, match="tab character"):
            handler._validate_frontmatter(content, "my-skill")

    def test_line_without_a_colon_is_rejected(self, handler):
        content = "---\nname: my-skill\ndescription: Fine.\nstray line\n---\n\nBody.\n"
        with pytest.raises(handler.RejectedError, match="not a key: value pair"):
            handler._validate_frontmatter(content, "my-skill")

    @pytest.mark.parametrize("field", ["name", "description"])
    def test_missing_required_field_is_rejected(self, handler, field):
        fields = {"name": "my-skill", "description": "Fine."}
        del fields[field]
        body = "".join(f"{k}: {v}\n" for k, v in fields.items())
        with pytest.raises(handler.RejectedError, match=f"missing a non-empty {field}"):
            handler._validate_frontmatter(f"---\n{body}---\n\nBody.\n", "my-skill")

    @pytest.mark.parametrize("field", ["name", "description"])
    def test_empty_required_field_is_rejected(self, handler, field):
        fields = {"name": "my-skill", "description": "Fine."}
        fields[field] = ""
        body = "".join(f"{k}: {v}\n" for k, v in fields.items())
        with pytest.raises(handler.RejectedError, match=f"missing a non-empty {field}"):
            handler._validate_frontmatter(f"---\n{body}---\n\nBody.\n", "my-skill")

    def test_name_must_match_the_directory(self, handler):
        # The harness addresses a skill by directory; a mismatch loads under a name the
        # author did not intend, which is confusing rather than harmless.
        with pytest.raises(handler.RejectedError, match="does not match the directory"):
            handler._validate_frontmatter(VALID_SKILL, "some-other-name")

    def test_frontmatter_without_a_body_is_rejected(self, handler):
        content = "---\nname: my-skill\ndescription: Fine.\n---\n\n   \n"
        with pytest.raises(handler.RejectedError, match="no body"):
            handler._validate_frontmatter(content, "my-skill")


# --- Write path ---------------------------------------------------------------


class TestSaveSkill:
    @pytest.mark.parametrize(
        "skill_name",
        [
            "../escape",
            "Upper-Case",
            "-leading-dash",
            "has space",
            "has_underscore",
            "a" * 65,
            "",
            None,
        ],
    )
    def test_illegal_skill_names_are_rejected(self, handler, context, s3_spy, skill_name):
        event = {"skill_name": skill_name, "content": VALID_SKILL}
        with pytest.raises(handler.RejectedError, match="skill_name must be"):
            handler._save_skill(event, CALLER_UUID)
        assert s3_spy == [], "nothing may be written when the name is rejected"

    @pytest.mark.parametrize("path", ["../../etc/passwd", "references/../../escape", "/absolute"])
    def test_path_traversal_is_rejected(self, handler, s3_spy, path):
        event = {"skill_name": "my-skill", "path": path, "content": "body"}
        with pytest.raises(handler.RejectedError, match="path contains"):
            handler._save_skill(event, CALLER_UUID)
        assert s3_spy == []

    def test_non_string_content_is_rejected(self, handler, s3_spy):
        event = {"skill_name": "my-skill", "content": {"not": "a string"}}
        with pytest.raises(handler.RejectedError, match="content must be a string"):
            handler._save_skill(event, CALLER_UUID)
        assert s3_spy == []

    def test_oversized_content_is_rejected(self, handler, s3_spy):
        event = {"skill_name": "my-skill", "content": "x" * (handler.MAX_SKILL_BYTES + 1)}
        with pytest.raises(handler.RejectedError, match="exceeds"):
            handler._save_skill(event, CALLER_UUID)
        assert s3_spy == []

    def test_key_is_scoped_to_the_caller(self, handler, s3_spy):
        event = {"skill_name": "terraform-review", "content": VALID_SKILL}
        result = handler._save_skill(event, CALLER_UUID)

        expected = f"users/{CALLER_UUID}/terraform-review/SKILL.md"
        assert result["key"] == expected
        assert s3_spy[0]["Key"] == expected

    def test_write_is_encrypted_with_the_stack_key(self, handler, s3_spy):
        handler._save_skill({"skill_name": "terraform-review", "content": VALID_SKILL}, CALLER_UUID)
        assert s3_spy[0]["ServerSideEncryption"] == "aws:kms"
        assert s3_spy[0]["SSEKMSKeyId"] == handler.KMS_KEY_ARN

    def test_save_reports_that_a_refresh_is_needed(self, handler, s3_spy):
        # Skills are fetched once per session, so a save is not live. Reporting otherwise
        # is the server-side half of the frontend's "unsaved changes" indicator.
        result = handler._save_skill(
            {"skill_name": "terraform-review", "content": VALID_SKILL}, CALLER_UUID
        )
        assert result["requires_session_refresh"] is True

    def test_supporting_files_skip_frontmatter_validation(self, handler, s3_spy):
        # references/ and scripts/ are opaque; only SKILL.md carries frontmatter.
        event = {
            "skill_name": "skill-authoring",
            "path": "references/frontmatter.md",
            "content": "No frontmatter here, and that is fine.",
        }
        result = handler._save_skill(event, CALLER_UUID)
        assert result["key"].endswith("skill-authoring/references/frontmatter.md")


# --- Read path: mediated for the same reason, different cause --------------------


class TestReadFile:
    def test_key_is_derived_from_the_request_context(self, handler, s3_get_spy):
        result = handler._read_file({"skill_name": "terraform-review"}, CALLER_UUID)
        assert result["key"] == f"users/{CALLER_UUID}/terraform-review/SKILL.md"
        assert result["content"] == "file body"

    def test_caller_cannot_read_another_prefix(self, handler, s3_get_spy):
        # The only identity input is caller_sub, which comes from the Lambda context.
        # A skill_name cannot escape the prefix because traversal is rejected outright.
        for attempt in ("../../victim", "..", "../other-user"):
            with pytest.raises(handler.RejectedError):
                handler._read_file({"skill_name": attempt}, CALLER_UUID)
        assert s3_get_spy == []

    def test_path_traversal_in_path_is_rejected(self, handler, s3_get_spy):
        with pytest.raises(handler.RejectedError, match="path contains"):
            handler._read_file(
                {"skill_name": "my-skill", "path": "../../../etc/passwd"}, CALLER_UUID
            )
        assert s3_get_spy == []

    def test_supporting_files_are_readable(self, handler, s3_get_spy):
        result = handler._read_file(
            {"skill_name": "skill-authoring", "path": "references/frontmatter.md"}, CALLER_UUID
        )
        assert result["key"].endswith("skill-authoring/references/frontmatter.md")


# --- Invoke path: construct, never forward -----------------------------------


class TestInvoke:
    def test_empty_prompt_is_rejected(self, handler, agentcore_spy, skill_dirs):
        with pytest.raises(handler.RejectedError, match="prompt must be"):
            handler._invoke({"prompt": "   "}, CALLER_UUID)
        assert agentcore_spy == []

    def test_unlisted_model_is_rejected_rather_than_defaulted(self, handler, agentcore_spy, skill_dirs):
        # Rejected, so a stale picker is visible instead of silently substituting a model.
        with pytest.raises(handler.RejectedError, match="model_id must be one of"):
            handler._invoke({"prompt": "hi", "model_id": "anthropic.claude-opus-4"}, CALLER_UUID)
        assert agentcore_spy == []

    def test_absent_model_falls_back_to_the_default(self, handler, agentcore_spy, skill_dirs):
        result = handler._invoke({"prompt": "hi"}, CALLER_UUID)
        assert result["model_id"] == handler.DEFAULT_MODEL_ID
        # A structure, not a string: modelId nests under bedrockModelConfig.
        assert agentcore_spy[0]["model"] == {
            "bedrockModelConfig": {"modelId": handler.DEFAULT_MODEL_ID}
        }

    def test_prompt_is_sent_as_a_converse_style_message(self, handler, agentcore_spy, skill_dirs):
        # There is no `payload` parameter on InvokeHarness; `messages` is required.
        handler._invoke({"prompt": "review my terraform"}, CALLER_UUID)
        assert agentcore_spy[0]["messages"] == [
            {"role": "user", "content": [{"text": "review my terraform"}]}
        ]

    def test_harness_is_addressed_by_arn(self, handler, agentcore_spy, skill_dirs):
        handler._invoke({"prompt": "hi"}, CALLER_UUID)
        assert agentcore_spy[0]["harnessArn"] == handler.HARNESS_ARN
        assert "harnessId" not in agentcore_spy[0]

    def test_text_deltas_are_accumulated_from_the_event_stream(self, handler, agentcore_spy, skill_dirs):
        # The response is an event stream, so there is nothing to read until iterated.
        result = handler._invoke({"prompt": "hi"}, CALLER_UUID)
        assert result["response"] == "Hello world"
        assert result["stop_reason"] == "end_turn"
        assert result["usage"]["totalTokens"] == 12

    def test_tool_uses_are_reported(self, handler, agentcore_spy, skill_dirs):
        # A mismatched allowed_tools leaves the model with no tools and no error, so the
        # only way to notice is that nothing was ever called.
        result = handler._invoke({"prompt": "hi"}, CALLER_UUID)
        assert result["tool_uses"] == ["file_operations"]

    def test_validation_exception_in_the_stream_is_surfaced(self, handler, skill_dirs, monkeypatch):
        # In-band exceptions arrive as ordinary stream members. Ignoring them would turn
        # a service-side validation failure into an empty but successful reply.
        class FailingStream:
            def invoke_harness(self, **kwargs):
                return {"stream": [{"validationException": {"message": "bad skill uri", "reason": "FieldValidationFailed"}}]}

        monkeypatch.setattr(handler, "agentcore", FailingStream())
        with pytest.raises(handler.RejectedError, match="bad skill uri"):
            handler._invoke({"prompt": "hi"}, CALLER_UUID)

    def test_client_supplied_skills_are_discarded(self, handler, agentcore_spy, skill_dirs):
        # AWS does not validate skill source, so a forwarded skills array would let a
        # caller point the harness at any S3 prefix or Git repo the role can read.
        event = {
            "prompt": "hi",
            "skills": [{"s3": {"uri": "s3://attacker-bucket/evil/"}}],
        }
        handler._invoke(event, CALLER_UUID)

        uris = [s["s3"]["uri"] for s in agentcore_spy[0]["skills"]]
        assert not any("attacker-bucket" in u for u in uris)

    def test_one_entry_per_skill_directory(self, handler, agentcore_spy, skill_dirs):
        # s3.uri names "the skill directory", so passing the prefix that *contains* the
        # skill directories finds no SKILL.md. Both prefixes are enumerated and the
        # caller's own skills come first.
        handler._invoke({"prompt": "hi"}, CALLER_UUID)

        assert [s["s3"]["uri"] for s in agentcore_spy[0]["skills"]] == [
            f"s3://{handler.BUCKET_NAME}/users/{CALLER_UUID}/my-first-skill/",
            f"s3://{handler.BUCKET_NAME}/users/{CALLER_UUID}/terraform-review/",
            f"s3://{handler.BUCKET_NAME}/shared/skill-authoring/",
            f"s3://{handler.BUCKET_NAME}/shared/terraform-review/",
        ]

    def test_every_skill_entry_sets_exactly_one_source(self, handler, agentcore_spy, skill_dirs):
        # The skill element is a union in the service model, so combining sources in one
        # entry is invalid even though a dict makes it easy to express.
        handler._invoke({"prompt": "hi"}, CALLER_UUID)
        for entry in agentcore_spy[0]["skills"]:
            assert list(entry) == ["s3"]

    def test_uris_keep_their_trailing_slash(self, handler, agentcore_spy, skill_dirs):
        handler._invoke({"prompt": "hi"}, CALLER_UUID)
        assert all(s["s3"]["uri"].endswith("/") for s in agentcore_spy[0]["skills"])

    def test_skills_is_omitted_when_the_caller_has_none(self, handler, agentcore_spy, monkeypatch):
        # An empty list positively asserts "no skills" and would override whatever the
        # harness itself declares, so absence is the correct signal.
        class EmptyS3:
            def get_paginator(self, name):
                class P:
                    def paginate(self, **kwargs):
                        return [{}]
                return P()

        monkeypatch.setattr(handler, "s3", EmptyS3())
        handler._invoke({"prompt": "hi"}, CALLER_UUID)
        assert "skills" not in agentcore_spy[0]

    def test_client_supplied_additional_params_are_discarded(self, handler, agentcore_spy, skill_dirs):
        # additionalParams passes through the harness unchanged, and LiteLLM's
        # aws_bedrock_runtime_endpoint would redirect a SigV4-signed request.
        event = {
            "prompt": "hi",
            "additionalParams": {"aws_bedrock_runtime_endpoint": "https://attacker.example"},
            "model": {"bedrockModelConfig": {"modelId": "anything"}},
        }
        handler._invoke(event, CALLER_UUID)

        sent = agentcore_spy[0]
        assert "additionalParams" not in sent
        assert sent["model"] == {"bedrockModelConfig": {"modelId": handler.DEFAULT_MODEL_ID}}

    def test_actor_id_is_the_caller_so_memory_is_per_user(self, handler, agentcore_spy, skill_dirs):
        handler._invoke({"prompt": "hi"}, CALLER_UUID)
        assert agentcore_spy[0]["actorId"] == CALLER_UUID

    def test_supplied_session_id_is_reused(self, handler, agentcore_spy, skill_dirs):
        # 36 characters, as the browser mints. The service floor is 33.
        session = "aaaaaaaa-1111-2222-3333-bbbbbbbbbbbb"
        result = handler._invoke({"prompt": "hi", "session_id": session}, CALLER_UUID)
        assert result["session_id"] == session
        assert agentcore_spy[0]["runtimeSessionId"] == session

    @pytest.mark.parametrize(
        "session_id",
        ["too-short", "-leading-dash" + "x" * 25, "has space" + "x" * 25, "x" * 101, "has/slash" + "x" * 25],
    )
    def test_illegal_session_id_is_rejected_with_a_message(self, handler, agentcore_spy, skill_dirs, session_id):
        # Without this the service constraint surfaces as ParamValidationError inside
        # botocore, which this handler reports as an opaque "Internal error".
        with pytest.raises(handler.RejectedError, match="session_id must be"):
            handler._invoke({"prompt": "hi", "session_id": session_id}, CALLER_UUID)
        assert agentcore_spy == []

    def test_absent_session_id_is_minted(self, handler, agentcore_spy, skill_dirs):
        # The browser drops the ID to reload edited skills, so minting must be automatic,
        # and a uuid4 string is 36 characters so it always clears the 33-character floor.
        result = handler._invoke({"prompt": "hi"}, CALLER_UUID)
        assert len(result["session_id"]) >= 33
        assert result["session_id"] == agentcore_spy[0]["runtimeSessionId"]


# --- Dispatch and error surface ----------------------------------------------


class TestHandlerDispatch:
    def test_unknown_action_is_rejected_by_name(self, handler, context):
        result = handler.handler({"action": "delete_everything"}, context)
        assert result["ok"] is False
        assert "Unknown action" in result["error"]

    def test_unauthenticated_call_never_reaches_an_action(self, handler, anonymous_context, s3_spy):
        result = handler.handler(
            {"action": "save_skill", "skill_name": "my-skill", "content": VALID_SKILL},
            anonymous_context,
        )
        assert result["ok"] is False
        assert s3_spy == []

    def test_unexpected_error_is_opaque_but_correlatable(self, handler, context, monkeypatch):
        # An S3 key or ARN in a browser-visible error is a disclosure; the request ID is
        # how the detail is still findable in CloudWatch.
        class ExplodingS3:
            def put_object(self, **kwargs):
                raise RuntimeError("bucket test-skill-bucket is on fire")

        monkeypatch.setattr(handler, "s3", ExplodingS3())

        result = handler.handler(
            {"action": "save_skill", "skill_name": "terraform-review", "content": VALID_SKILL},
            context,
        )
        assert result == {
            "ok": False,
            "error": "Internal error",
            "request_id": "test-request-id",
        }

    def test_successful_dispatch_is_wrapped_in_ok(self, handler, context, s3_spy):
        result = handler.handler(
            {"action": "save_skill", "skill_name": "terraform-review", "content": VALID_SKILL},
            context,
        )
        assert result["ok"] is True
        assert result["key"].startswith(f"users/{CALLER_UUID}/")
