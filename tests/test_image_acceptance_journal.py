"""Exercise the actual embedded release gate without running its PC1 main."""

import ast
import json
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/accept-pc1-image.sh"


def embedded_gate():
    source = SCRIPT.read_text(encoding="utf-8").split("<<'PY'\n", 1)[1].rsplit("\nPY", 1)[0]
    tree = ast.parse(source, filename=str(SCRIPT))
    selected = [node for node in tree.body if isinstance(node, ast.FunctionDef)
                and node.name in ("command", "journal_messages")]
    if len(selected) != 2:
        raise AssertionError("embedded journal functions missing")
    namespace = {"subprocess": subprocess, "json": json}
    exec(compile(ast.Module(body=selected, type_ignores=[]), str(SCRIPT), "exec"), namespace)
    return namespace, tree


class ImageAcceptanceJournalTests(unittest.TestCase):
    def setUp(self):
        self.gate, self.tree = embedded_gate()

    def query(self, result):
        with patch.object(subprocess, "run", return_value=result) as run:
            messages = self.gate["journal_messages"](["--grep=avc:.*denied"])
        self.assertEqual(run.call_args.args[0], ["journalctl", "-b", "--no-pager",
                         "--all", "-o", "json", "--grep=avc:.*denied"])
        return messages

    def test_successful_no_match_is_accepted(self):
        self.assertEqual(self.query(subprocess.CompletedProcess([], 1, "", "")), [])

    def test_empty_success_is_accepted(self):
        self.assertEqual(self.query(subprocess.CompletedProcess([], 0, "", "")), [])

    def test_query_error_cannot_become_no_matches(self):
        for code in (1, 2, 127):
            with self.subTest(code=code), self.assertRaisesRegex(ValueError, "boot journal query failed"):
                self.query(subprocess.CompletedProcess([], code, "", "Failed to open journal"))

    def test_missing_executable_and_timeout_fail_closed(self):
        for error in (FileNotFoundError("journalctl missing"),
                      subprocess.TimeoutExpired(["journalctl"], 20)):
            with self.subTest(error=type(error).__name__), patch.object(subprocess, "run", side_effect=error):
                with self.assertRaisesRegex(ValueError, "boot journal query failed"):
                    self.gate["journal_messages"](["COREDUMP_EXE=/usr/bin/gamescope"])

    def test_matching_avc_and_core_evidence_is_preserved(self):
        messages = ["avc: denied { open } permissive=0", "Process 1468 (gamescope-wl) dumped core"]
        output = "\n".join(json.dumps({"MESSAGE": message}) for message in messages)
        self.assertEqual(self.query(subprocess.CompletedProcess([], 0, output, "")), messages)

    def test_journal_binary_message_is_decoded(self):
        output = json.dumps({"MESSAGE": list(b"gamescope segfault")})
        self.assertEqual(self.query(subprocess.CompletedProcess([], 0, output, "")), ["gamescope segfault"])

    def test_malformed_evidence_is_rejected(self):
        for output in ("not json", "[]", '{"MESSAGE":17}', '{"MESSAGE":[999]}'):
            with self.subTest(output=output), self.assertRaises((ValueError, AttributeError, TypeError)):
                self.query(subprocess.CompletedProcess([], 0, output, ""))

    def test_full_expected_sha_matches_only_valid_baked_prefix(self):
        main = next(node for node in self.tree.body if isinstance(node, ast.FunctionDef) and node.name == "main")
        calls = [node for node in ast.walk(main) if isinstance(node, ast.Call)
                 and isinstance(node.func, ast.Name) and node.func.id == "check"
                 and node.args and isinstance(node.args[0], ast.Constant)
                 and node.args[0].value == "baked expected source commit"]
        self.assertEqual(len(calls), 1)
        expression = compile(ast.Expression(calls[0].args[1]), str(SCRIPT), "eval")
        expected = "70faf40b94991afd88b3574ffe803cb5e5b85bb2"
        for baked, valid in ((expected, True), (expected[:7], True),
                             (expected[:6], False), ("0" * 7, False),
                             (expected + "0", False), ("70faf4G", False), ("", False)):
            with self.subTest(baked=baked):
                self.assertEqual(eval(expression, {"expected_commit": expected, "actual_commit": baked}), valid)


if __name__ == "__main__":
    unittest.main()
