#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Self-test of scripts/fake-model.py's answering mode: starts it on a free port, sends the
# request shapes ChatCompletionsModel sends, and checks the stream it gets back; then
# signs in with ChatGPT and streams from the plan's Responses API as the app does.
# Standard library only. Run by `make test-mock`.

import base64
import hashlib
import importlib.util
import json
import pathlib
import sys
import threading
import unittest
import urllib.error
import urllib.parse
import urllib.request

sys.dont_write_bytecode = True  # importing fake-model.py must not leave scripts/__pycache__
HERE = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("fake_model", HERE / "fake-model.py")
fake_model = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fake_model)
fake_model.Handler.log = lambda self, line: None

PROOFREAD_SCHEMA = {
    "type": "json_schema",
    "json_schema": {"name": "proofread", "strict": True, "schema": {"type": "object"}},
}


CARD_SCHEMA = {
    "type": "json_schema",
    "json_schema": {"name": "card", "strict": True, "schema": {"type": "object"}},
}
CARD_KEYS = ["status", "lemma", "phonetic", "partOfSpeech", "definition", "contextTranslation",
             "otherSenses", "examples", "collocations", "level"]


def card_body(term, context=""):
    """A card request as PromptBuilder.card sends it: the JSON object in the source block."""
    return body(json.dumps({"term": term, "context": context}, ensure_ascii=False), CARD_SCHEMA)


TRANSLATE_OUT_TASK = ("Translate the source block into English as the writer's own message. "
                      "Output only the translation.")


def body(text, response_format=None, task="Do the task."):
    user = f"<source_text_0a1b2c3d>\n{text}\n</source_text_0a1b2c3d>\n\n{task}"
    request = {
        "model": "mock",
        "messages": [{"role": "system", "content": "sys"}, {"role": "user", "content": user}],
        "stream": True,
        "stream_options": {"include_usage": True},
        "max_tokens": 256,
        "reasoning_effort": "none",
    }
    if response_format:
        request["response_format"] = response_format
    return request


class AnsweringModeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = fake_model.make_server(0)
        cls.port = cls.server.server_address[1]
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()

    def post(self, path, payload):
        request = urllib.request.Request(
            f"http://127.0.0.1:{self.port}{path}",
            data=json.dumps(payload).encode(),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(request, timeout=10) as response:
            return response.status, response.headers["Content-Type"], response.read().decode()

    def stream(self, payload):
        status, content_type, raw = self.post("/v1/chat/completions", payload)
        self.assertEqual(status, 200)
        self.assertEqual(content_type, "text/event-stream")
        events = [block for block in raw.split("\n\n") if block]
        for event in events:
            self.assertTrue(event.startswith("data: "), event)
        self.assertEqual(events[-1], "data: [DONE]")
        chunks = [json.loads(event[len("data: "):]) for event in events[:-1]]
        deltas = [c for c in chunks if c.get("choices")]
        self.assertGreater(len(deltas), 1, "the reply comes in several deltas")
        text = "".join(c["choices"][0]["delta"].get("content", "") for c in deltas)
        self.assertEqual(deltas[-1]["choices"][0]["finish_reason"], "stop")
        self.assertIn("usage", chunks[-1])
        self.assertEqual(chunks[-1]["choices"], [])
        return text

    def test_proofreading_answers_the_edit_list(self):
        text = self.stream(
            body("Their going to the park tomorow, I think it will be fun.", PROOFREAD_SCHEMA))
        edits = json.loads(text)["edits"]
        self.assertEqual(
            [(e["wrong"], e["right"]) for e in edits],
            [("Their", "They're"), ("tomorow,", "tomorrow.")])

    def test_proofreading_unknown_text_answers_no_edits(self):
        self.assertEqual(json.loads(self.stream(body("Fine as is.", PROOFREAD_SCHEMA))),
                         {"edits": []})

    def test_card_from_the_table_comes_in_schema_order(self):
        text = self.stream(card_body("ran", "She ran a small bakery for ten years."))
        card = json.loads(text)
        self.assertEqual(list(card), CARD_KEYS)
        self.assertEqual(card["lemma"], "run")
        self.assertEqual(card["definition"], fake_model.MARK + "经营；管理")

    def test_card_term_matches_lowercased(self):
        self.assertEqual(json.loads(self.stream(card_body("Fine")))["lemma"], "fine")

    def test_card_not_a_term_has_no_definition(self):
        card = json.loads(self.stream(card_body("asdfgh")))
        self.assertEqual(card["status"], "not_a_term")
        self.assertEqual(card["definition"], "")

    def test_card_fallback_fills_in_the_term(self):
        card = json.loads(self.stream(card_body('say "cheese"', "Everyone, say \"cheese\"!")))
        self.assertEqual(list(card), CARD_KEYS)
        self.assertEqual(card["lemma"], 'say "cheese"')
        self.assertTrue(card["definition"].startswith(fake_model.MARK))
        self.assertIn('say "cheese"', card["examples"][0]["sentence"])
        self.assertNotEqual(card["contextTranslation"], "")

    def test_card_fallback_without_context_has_no_context_translation(self):
        self.assertEqual(json.loads(self.stream(card_body("petrichor")))["contextTranslation"], "")

    def test_translation_from_the_table_is_marked(self):
        text = self.stream(body("five dozen liquor jugs"))
        self.assertTrue(text.startswith(fake_model.MARK), text)
        self.assertIn("五打酒壶", text)

    def test_translation_fallback_echoes_the_source(self):
        self.assertEqual(self.stream(body("an unknown sentence")),
                         fake_model.MARK + "an unknown sentence")

    def test_translate_out_from_the_table_is_marked(self):
        text = self.stream(body("我们明天下午三点开会。", task=TRANSLATE_OUT_TASK))
        self.assertEqual(text, fake_model.MARK + "We have a meeting at three tomorrow afternoon.")

    def test_translate_out_fallback_echoes_the_source(self):
        self.assertEqual(self.stream(body("一句没有的话", task=TRANSLATE_OUT_TASK)),
                         fake_model.MARK + "一句没有的话")

    def test_back_translation_of_a_translate_out_result(self):
        forward = self.stream(body("不好意思，路上堵车，我要晚到十分钟", task=TRANSLATE_OUT_TASK))
        # The app back-translates the result as the mock gave it, MARK included.
        back = self.stream(body(forward))
        self.assertEqual(back, fake_model.MARK + "抱歉，我堵在路上了，会晚到十分钟。")

    def test_every_translate_out_has_its_back_translation(self):
        table = json.loads(fake_model.REPLIES.read_text(encoding="utf-8"))
        self.assertGreaterEqual(len(table["translateOuts"]), 3)
        for source, result in table["translateOuts"].items():
            self.assertIn(result, table["translations"], source)

    def test_without_include_usage_there_is_no_usage_chunk(self):
        payload = body("five dozen liquor jugs")
        del payload["stream_options"]
        _, _, raw = self.post("/v1/chat/completions", payload)
        self.assertNotIn('"usage"', raw)

    def test_unknown_path_is_not_found(self):
        with self.assertRaises(urllib.error.HTTPError) as caught:
            self.post("/unknown", {})
        self.assertEqual(caught.exception.code, 404)

    def get(self, path):
        url = f"http://127.0.0.1:{self.port}{path}"
        with urllib.request.urlopen(url, timeout=10) as response:
            self.assertEqual(response.status, 200)
            self.assertEqual(response.headers["Content-Type"], "application/json")
            return json.loads(response.read())

    def test_models_lists_the_mock_in_the_openai_shape(self):
        listing = self.get("/v1/models")
        self.assertEqual(listing["object"], "list")
        self.assertEqual([model["id"] for model in listing["data"]], ["mock"])

    def test_tags_lists_the_mock_in_the_ollama_shape(self):
        self.assertEqual([model["name"] for model in self.get("/api/tags")["models"]], ["mock"])

    def test_unknown_get_is_not_found(self):
        with self.assertRaises(urllib.error.HTTPError) as caught:
            self.get("/v1/chat/completions")
        self.assertEqual(caught.exception.code, 404)
        self.assertIn("message", json.loads(caught.exception.read())["error"])


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


class ChatGPTPlanTests(unittest.TestCase):
    """Sign in with ChatGPT and the plan's Responses API as ChatGPTSignIn and ResponsesModel
    use them."""

    @classmethod
    def setUpClass(cls):
        cls.server = fake_model.make_server(0)
        cls.port = cls.server.server_address[1]
        cls.base = f"http://127.0.0.1:{cls.port}"
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()

    def request(self, method, path, data=None, headers=None):
        request = urllib.request.Request(self.base + path, data=data, headers=headers or {},
                                         method=method)
        opener = urllib.request.build_opener(NoRedirect)
        try:
            with opener.open(request, timeout=10) as response:
                return response.status, dict(response.headers), response.read().decode()
        except urllib.error.HTTPError as error:
            return error.code, dict(error.headers), error.read().decode()

    def authorize(self, client="dynamic_agent_client", verifier="v" * 43, **overrides):
        challenge = fake_model.b64url(hashlib.sha256(verifier.encode()).digest())
        params = {
            "response_type": "code", "client_id": client, "agent_name_hint": "Dict",
            "ext_agent_host_id": "urn:uuid:test", "scope": fake_model.SCOPES,
            "redirect_uri": "http://127.0.0.1:1455/auth/callback",
            "resource": self.base + "/chatgpt/v1", "state": "st", "nonce": "no",
            "code_challenge": challenge, "code_challenge_method": "S256",
        }
        params.update(overrides)
        return self.request(
            "GET", "/auth/api/accounts/authorize?" + urllib.parse.urlencode(params))

    def token(self, fields):
        return self.request(
            "POST", "/auth/api/accounts/oauth/token",
            urllib.parse.urlencode(fields).encode(),
            {"Content-Type": "application/x-www-form-urlencoded"})

    def sign_in(self, verifier="v" * 43):
        status, headers, _ = self.authorize(verifier=verifier)
        self.assertEqual(status, 302)
        location = urllib.parse.urlsplit(headers["Location"])
        self.assertEqual(f"{location.scheme}://{location.netloc}{location.path}",
                         "http://127.0.0.1:1455/auth/callback")
        query = urllib.parse.parse_qs(location.query)
        self.assertEqual(query["state"], ["st"])
        self.assertEqual(query["client_id"], [fake_model.MOCK_CLIENT])
        status, _, raw = self.token({
            "grant_type": "authorization_code", "client_id": fake_model.MOCK_CLIENT,
            "code": query["code"][0], "code_verifier": verifier,
            "redirect_uri": "http://127.0.0.1:1455/auth/callback",
            "resource": self.base + "/chatgpt/v1"})
        self.assertEqual(status, 200, raw)
        return json.loads(raw)

    def responses(self, token, payload):
        return self.request(
            "POST", "/chatgpt/v1/responses", json.dumps(payload).encode(),
            {"Content-Type": "application/json", "Authorization": f"Bearer {token}"})

    def test_sign_in_issues_tokens_and_a_checked_id_token(self):
        tokens = self.sign_in()
        self.assertIn(fake_model.PLAN_SCOPE, tokens["scope"].split())
        payload = tokens["id_token"].split(".")[1]
        claims = json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))
        self.assertEqual(claims["iss"], self.base + "/auth")
        self.assertEqual(claims["aud"], fake_model.MOCK_CLIENT)
        self.assertEqual(claims["nonce"], "no")

    def test_a_later_sign_in_gets_no_new_client_id(self):
        status, headers, _ = self.authorize(client=fake_model.MOCK_CLIENT, agent_name_hint="")
        self.assertEqual(status, 302)
        self.assertNotIn("client_id", urllib.parse.parse_qs(urllib.parse.urlsplit(
            headers["Location"]).query))

    def test_authorize_refuses_localhost_and_missing_hints(self):
        self.assertEqual(
            self.authorize(redirect_uri="http://localhost:1455/auth/callback")[0], 400)
        self.assertEqual(self.authorize(agent_name_hint="")[0], 400)
        self.assertEqual(self.authorize(ext_agent_host_id="")[0], 400)

    def test_a_wrong_verifier_is_invalid_grant(self):
        status, headers, _ = self.authorize(verifier="a" * 43)
        code = urllib.parse.parse_qs(urllib.parse.urlsplit(headers["Location"]).query)["code"][0]
        status, _, raw = self.token({
            "grant_type": "authorization_code", "client_id": fake_model.MOCK_CLIENT,
            "code": code, "code_verifier": "b" * 43,
            "redirect_uri": "http://127.0.0.1:1455/auth/callback", "resource": "r"})
        self.assertEqual((status, json.loads(raw)["error"]), (400, "invalid_grant"))

    def test_refresh_rotates_and_a_spent_token_is_refused(self):
        tokens = self.sign_in()
        refresh = {"grant_type": "refresh_token", "client_id": fake_model.MOCK_CLIENT,
                   "refresh_token": tokens["refresh_token"], "resource": "r"}
        status, _, raw = self.token(refresh)
        self.assertEqual(status, 200)
        self.assertNotEqual(json.loads(raw)["refresh_token"], tokens["refresh_token"])
        self.assertEqual(self.token(refresh)[0], 400)

    def test_models_in_the_plan_shape_need_a_token(self):
        tokens = self.sign_in()
        status, _, raw = self.request(
            "GET", "/chatgpt/v1/models",
            headers={"Authorization": f"Bearer {tokens['access_token']}"})
        self.assertEqual(status, 200)
        self.assertEqual([m["visibility"] for m in json.loads(raw)["models"]], ["list", "hide"])
        self.assertEqual(self.request("GET", "/chatgpt/v1/models")[0], 401)

    def test_responses_streams_the_translation(self):
        tokens = self.sign_in()
        user = "<source_text_0a1b2c3d>\nfive dozen liquor jugs\n</source_text_0a1b2c3d>\n\nDo."
        status, headers, raw = self.responses(tokens["access_token"], {
            "model": "mock", "instructions": "sys", "input": [{"role": "user", "content": user}],
            "store": False, "stream": True, "reasoning": {"effort": "none"}})
        self.assertEqual(status, 200)
        self.assertEqual(headers["Content-Type"], "text/event-stream")
        events = [json.loads(block.split("data: ", 1)[1]) for block in raw.split("\n\n") if block]
        self.assertEqual(events[-1]["type"], "response.completed")
        text = "".join(e["delta"] for e in events if e["type"] == "response.output_text.delta")
        self.assertIn("五打酒壶", text)

    def test_responses_rejects_what_the_plan_rejects(self):
        token = self.sign_in()["access_token"]
        good = {"model": "mock", "input": [{"role": "user", "content": "u"}], "store": False,
                "stream": True}
        for change, param in [({"store": True}, "store"), ({"stream": False}, "stream"),
                              ({"max_output_tokens": 9}, "max_output_tokens"),
                              ({"temperature": 0}, "temperature"),
                              ({"input": [{"role": "system", "content": "s"}]}, "input.role")]:
            status, _, raw = self.responses(token, {**good, **change})
            self.assertEqual(status, 400, param)
            error = json.loads(raw)["error"]
            self.assertEqual(error["code"], "subscription_sharing_unsupported_capability")
            self.assertEqual(error["param"], param)
        status, _, raw = self.responses(token, {**good, "model": "mock-limit"})
        self.assertEqual(status, 429)
        self.assertEqual(json.loads(raw)["error"]["code"],
                         "subscription_sharing_usage_limit_exceeded")
        self.assertEqual(self.responses("forged", good)[0], 401)


if __name__ == "__main__":
    unittest.main(verbosity=2)
