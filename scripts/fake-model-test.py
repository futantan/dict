#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Self-test of scripts/fake-model.py's answering mode: starts it on a free port, sends the
# request shapes ChatCompletionsModel sends, and checks the stream it gets back.
# Standard library only. Run by `make test-mock`.

import importlib.util
import json
import pathlib
import sys
import threading
import unittest
import urllib.error
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


def body(text, response_format=None):
    user = f"<source_text_0a1b2c3d>\n{text}\n</source_text_0a1b2c3d>\n\nDo the task."
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


if __name__ == "__main__":
    unittest.main(verbosity=2)
