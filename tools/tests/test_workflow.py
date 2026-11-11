import datetime
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parent.parent.parent
sys.path[:0] = [str(ROOT / "tools"), str(ROOT / ".claude" / "hooks")]

import check  # noqa: E402
import guard  # noqa: E402
import hook_report  # noqa: E402
import issue  # noqa: E402
from secret_screen import find_secrets  # noqa: E402
from sim_lint import find_violations, lint_simulation  # noqa: E402


class SimLint(unittest.TestCase):
    def test_catches_nondeterminism(self):
        cases = {
            "var r := randi()": "randomness",
            "var t := Time.get_ticks_msec()": "wall clock",
            "await process_frame": "async timing",
            "var a := Area2D.new()": "physics or navigation",
            "var n := $Unit": "scene tree",
            "func step(delta: int) -> void:": "engine delta",
            "var speed: float = 1": "floating point",
            "var speed := 1.5": "floating point",
            "var v := Vector2(1, 2)": "floating point",
            "var r := sqrt(16)": "floating point",
            "var n := RandomNumberGenerator.new()": "randomness",
        }
        for code, rule in cases.items():
            self.assertEqual(find_violations(code), [(1, rule)], code)

    def test_allows_integer_code(self):
        for code in ["var cell := Vector2i(1, 2)", "var rent := 3 * floor_index / 2", 'var name := "v1.5"']:
            self.assertEqual(find_violations(code), [], code)

    def test_ignores_comments(self):
        self.assertEqual(find_violations("var tick := 0  # never randf()\n## no await"), [])

    def test_lint_fails_on_a_planted_float(self):
        with tempfile.TemporaryDirectory() as folder:
            sim = Path(folder) / "scripts" / "sim" / "nested"
            sim.mkdir(parents=True)
            (sim / "bad.gd").write_text("var share := 0.5\n", encoding="utf-8")
            self.assertEqual(
                lint_simulation(folder), ["bad.gd:1: floating point is not allowed in the simulation"]
            )

    def test_current_simulation_is_clean(self):
        self.assertEqual(lint_simulation(ROOT), [])


class StateMachine(unittest.TestCase):
    def test_diagram_edges(self):
        edges = [
            ("start", "ready", "in-progress"), ("start", "backlog", "in-progress"),
            ("ask", "backlog", "blocked"), ("ask", "ready", "blocked"),
            ("ask", "in-progress", "blocked"), ("handoff", "in-progress", "review"),
            ("ready", "backlog", "ready"), ("ready", "blocked", "ready"),
            ("ready", "review", "ready"), ("backlog", "blocked", "backlog"),
            ("close", "review", "done"), ("wontfix", "in-progress", "wontfix"),
            ("finish", "review", "done"),
        ]
        for command, old, new in edges:
            self.assertEqual(issue.next_state(command, old), new)

    def test_agent_cannot_finish_or_skip_review(self):
        for command, old in [
            ("close", "in-progress"), ("start", "review"), ("handoff", "ready"), ("start", "done"),
            ("finish", "in-progress"), ("finish", "ready"), ("finish", "blocked"),
        ]:
            with self.assertRaises(issue.MoveError):
                issue.next_state(command, old)

    def test_only_finish_reaches_done_and_no_agent_move_reaches_ready(self):
        for command, moves in issue.AGENT_MOVES.items():
            self.assertNotIn("ready", moves.values())
            self.assertEqual("done" in moves.values(), command == "finish")

    def test_finish_needs_evidence_and_never_takes_a_playtest(self):
        self.assertEqual(issue.finish_parts(["type::chore"], "12 tests pass"), ("12", "tests pass"))
        for labels, extra in [(["type::chore"], None), (["type::chore"], "12"), (["type::chore"], "x y")]:
            with self.assertRaises(issue.MoveError):
                issue.finish_parts(labels, extra)
        with self.assertRaises(issue.MoveError):
            issue.finish_parts(["type::playtest"], "12 tests pass")

    def test_citation_needs_the_exact_issue(self):
        self.assertTrue(issue.cites(10, "Add it, refs #10"))
        self.assertFalse(issue.cites(10, "Add it, refs #101"))

    def test_gameplay_issue_needs_the_expert_review_before_ready(self):
        review = issue.GAMEPLAY_REVIEW + " matches the reference"
        self.assertTrue(issue.gameplay_problem(["type::feature", "gameplay"], []))
        self.assertTrue(issue.gameplay_problem(["gameplay"], ["looks fine", "Gameplay review: no bold"]))
        self.assertEqual(issue.gameplay_problem(["gameplay"], ["hello", review]), "")
        self.assertEqual(issue.gameplay_problem(["type::chore"], []), "", "not a gameplay issue")

    def test_at_most_one_status_label(self):
        self.assertEqual(issue.status_of(["type::bug", "status::ready"]), "ready")
        self.assertEqual(issue.status_of(["type::feature"]), "backlog", "a new issue")
        with self.assertRaises(issue.MoveError):
            issue.status_of(["status::ready", "status::done"])

    def test_new_issue_gets_a_label_without_removing_one(self):
        with mock.patch.object(issue, "gh") as gh:
            issue.set_status(5, "backlog", "in-progress", ["type::feature"])
            gh.assert_called_once_with("issue", "edit", "5", "--add-label", "status::in-progress")
            gh.reset_mock()
            issue.set_status(5, "ready", "in-progress", ["status::ready"])
            self.assertIn("--remove-label", gh.call_args.args)


class Merge(unittest.TestCase):
    GREEN = {
        "state": "OPEN", "isDraft": False, "baseRefName": "main", "mergeable": "MERGEABLE",
        "title": "feat: x, refs #3", "body": "",
        "statusCheckRollup": [{"name": "tests", "conclusion": "SUCCESS"},
                              {"name": "lint", "conclusion": "SKIPPED"}],
    }

    def problems(self, has_main=True, **changes):
        return issue.merge_problems({**self.GREEN, **changes}, has_main)

    def test_green_pr_merges(self):
        self.assertEqual(self.problems(), [])
        docs_only = [{"path": "docs/rules.md"}, {"path": ".claude/agents/x.md"}, {"path": "README.md"}]
        self.assertEqual(self.problems(statusCheckRollup=[], files=docs_only), [], "CI skips docs")

    def test_refuses_unready_prs(self):
        cases = {
            "pending CI": {"statusCheckRollup": [{"name": "tests", "status": "IN_PROGRESS"}]},
            "failed CI": {"statusCheckRollup": [{"name": "tests", "conclusion": "FAILURE"}]},
            "no CI": {"statusCheckRollup": [], "files": [{"path": "scripts/main.gd"}]},
            "no CI, mixed": {"statusCheckRollup": [], "files": [{"path": "docs/a.md"}, {"path": "x.py"}]},
            "conflicts": {"mergeable": "CONFLICTING"},
            "draft": {"isDraft": True},
            "closed": {"state": "MERGED"},
            "other base": {"baseRefName": "topic"},
            "no issue": {"title": "feat: x"},
        }
        for name, change in cases.items():
            self.assertTrue(self.problems(**change), name)
        self.assertTrue(self.problems(has_main=False), "behind main")


class Guard(unittest.TestCase):
    def rule(self, command):
        result = guard.evaluate("Bash", {"command": command})
        return result[0] if result else None

    def test_blocks(self):
        cases = {
            "git commit --no-verify -m x": "no-verify",
            "git push --force origin topic": "force-push",
            "git push origin main": "push-main",
            "gh pr merge 3": "pr-merge",
            "gh issue close 3": "raw-issue-close",
            "gh issue edit 3 --add-label status::done": "raw-status-label",
            "gh api repos/x/y": "raw-api",
            "python tools/issue.py close 3": "owner-move",
            "git config core.hooksPath .": "hooks-path",
            "git config --unset core.hooksPath": "hooks-path",
            "git config unset core.hooksPath; git status": "hooks-path",
            "git -c core.hooksPath=x commit": "hooks-path",
            "git push origin HEAD:main; gh pr view": "push-main",
            "cd x && git reset --hard": "history-rewrite",
            'gh pr create --title "x" --body "fixes #3"': "pr-closing-keyword",
            '"$G" --headless --path . --script t.gd': "unbounded-script",
        }
        for command, rule in cases.items():
            self.assertEqual(self.rule(command), rule, command)

    def test_private_port_is_off_limits(self):
        folder = "Tower " + "Game"
        denied = [
            ("Read", {"file_path": "D:\\Claude\\" + folder + "\\port\\a.cpp"}),
            ("Grep", {"pattern": "x", "path": "D:/Claude/" + folder + "/analysis"}),
            ("Glob", {"pattern": "**/*", "path": "D:\\Claude\\" + folder + "\\original"}),
            ("Bash", {"command": "cat '/d/Claude/" + folder + "/port/main.cpp'"}),
            ("PowerShell", {"command": "Get-Content 'D:\\Claude\\" + folder + "\\analysis\\a.md'"}),
        ]
        for tool, tool_input in denied:
            self.assertEqual(guard.evaluate(tool, tool_input)[:2], ("private-port", "deny"), tool)
        allowed = [
            ("Read", {"file_path": "D:\\Claude\\" + folder + "\\references\\faq.txt"}),
            ("Read", {"file_path": "D:\\Claude\\TowerGame\\port\\notes.md"}),
            ("Bash", {"command": "ls scripts"}),
        ]
        for tool, tool_input in allowed:
            self.assertIsNone(guard.evaluate(tool, tool_input), tool_input)

    def test_allows_normal_work(self):
        for command in [
            "git status", "git push origin topic", "python tools/issue.py start 3",
            'python tools/issue.py finish 3 12 "tests pass"',
            'git commit -m "docs: explain gh pr merge rule"', "gh issue view 3",
            'timeout 60 "$G" --headless --script t.gd > out.txt',
            "git config core.hooksPath", "git config --show-origin --get-all core.hooksPath; git status",
            "git add x; git config --get core.hooksPath",
            "git push -u origin HEAD; gh pr create --base main",
        ]:
            self.assertIsNone(self.rule(command), command)

    def test_new_script_is_checked_once(self):
        with tempfile.TemporaryDirectory() as folder:
            original = guard.CHECKED_SCRIPTS
            guard.CHECKED_SCRIPTS = Path(folder) / "checked.txt"
            self.addCleanup(setattr, guard, "CHECKED_SCRIPTS", original)
            script = str(Path(folder) / "new.gd")
            self.assertEqual(guard.evaluate("Write", {"file_path": script})[0], "script-logic")
            self.assertIsNone(guard.evaluate("Write", {"file_path": script}), "second attempt")
            other = str(Path(folder) / "notes.md")
            self.assertIsNone(guard.evaluate("Write", {"file_path": other}), "not a script")
            existing = Path(folder) / "old.gd"
            existing.write_text("", encoding="utf-8")
            self.assertIsNone(guard.evaluate("Write", {"file_path": str(existing)}), "already exists")

    def test_enforcement_files_ask_for_owner(self):
        for path in [".claude/settings.json", ".claude/hooks/guard.py", "hooks/pre-push", "tools/issue.py"]:
            self.assertEqual(guard.evaluate("Edit", {"file_path": str(ROOT / path)})[1], "ask", path)
        self.assertIsNone(guard.evaluate("Edit", {"file_path": str(ROOT / "scripts/main.gd")}))

    def test_real_hook_protocol(self):
        event = json.dumps({"tool_name": "Bash", "tool_input": {"command": "git push origin main"}})
        hooks_dir = str(ROOT / ".claude/hooks")
        with tempfile.TemporaryDirectory() as folder:
            log_path = Path(folder) / "log.jsonl"
            program = (
                f"import sys; sys.path.insert(0, {hooks_dir!r}); import guard, pathlib; "
                f"guard.LOG_FILE = pathlib.Path({str(log_path)!r}); guard.main()"
            )
            result = subprocess.run(
                [sys.executable, "-c", program], input=event, capture_output=True, text=True,
            )
            output = json.loads(result.stdout)["hookSpecificOutput"]
            self.assertEqual(output["permissionDecision"], "ask")
            self.assertEqual(json.loads(log_path.read_text())["rule"], "push-main")
        broken = subprocess.run(
            [sys.executable, str(ROOT / ".claude/hooks/guard.py")],
            input="not json", capture_output=True, text=True,
        )
        self.assertEqual(broken.returncode, 2, "broken input must fail closed")

    def test_every_rule_is_documented(self):
        documented = (ROOT / "docs/hooks.md").read_text(encoding="utf-8")
        rules = [rule[0] for rule in guard.COMMAND_RULES + guard.RAW_RULES]
        rules += ["protected-file", "script-logic", "private-port"]
        for rule in rules:
            self.assertIn(f"`{rule}`", documented)


class CommitMessage(unittest.TestCase):
    def problems(self, message):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "msg"
            path.write_text(message, encoding="utf-8")
            with mock.patch.object(check, "git", return_value=""):
                return check.commit_message(path)

    def test_rules(self):
        self.assertEqual(self.problems("Add selection, refs #4\n"), [])
        self.assertEqual(self.problems("chore: set up\n"), [])
        self.assertEqual(self.problems("ci: add workflow\n"), [])
        self.assertEqual(self.problems("chore(bootstrap): set up\n"), [])
        self.assertTrue(self.problems("Add selection\n"))
        self.assertTrue(self.problems("Add selection, fixes #4\n"))
        self.assertTrue(self.problems("chore: tidy\n\nCloses #4\n"))


class SecretScreen(unittest.TestCase):
    def test_finds_credentials(self):
        self.assertIn("github-token", find_secrets("ghp_" + "a" * 30))
        self.assertIn("url-login", find_secrets("http://admin:" + "hunter2@192.168.1.5/"))
        self.assertIn("assigned-secret", find_secrets("pass" + "word = correcthorse"))

    def test_ignores_ordinary_code(self):
        self.assertEqual(find_secrets("var token_count := 3\nfunc move(unit): pass\n"), [])


class HookReview(unittest.TestCase):
    def test_due_after_two_weeks(self):
        last = hook_report.last_review()
        self.assertTrue(hook_report.review_status(last + datetime.timedelta(days=14)))

    def test_review_clears_firings_from_its_own_day(self):
        last = hook_report.last_review()
        midnight = datetime.datetime.combine(last, datetime.time())
        with tempfile.TemporaryDirectory() as folder:
            log = Path(folder) / "log.jsonl"
            with mock.patch.object(hook_report, "LOG_FILE", log):
                for day, due in ((0, False), (1, True)):
                    moment = (midnight + datetime.timedelta(days=day, hours=1)).timestamp()
                    entry = json.dumps({"time": int(moment), "rule": "x"}) + "\n"
                    log.write_text(entry * hook_report.MAX_FIRINGS, encoding="utf-8")
                    self.assertEqual(bool(hook_report.review_status(last)), due, day)


class HooksActive(unittest.TestCase):
    """Uses real throwaway repos. Git exports GIT_DIR into hooks, which would aim these
    commands at this repo, so every GIT_ variable is cleared first."""

    def git(self, *args, cwd):
        subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True)

    def setUp(self):
        clean = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
        patcher = mock.patch.dict(os.environ, clean, clear=True)
        patcher.start()
        self.addCleanup(patcher.stop)
        folder = tempfile.TemporaryDirectory(ignore_cleanup_errors=True)
        self.addCleanup(folder.cleanup)
        self.main = Path(folder.name).resolve() / "main"
        self.worktree = self.main.parent / "worktree"
        self.main.mkdir()
        self.git("init", "-q", cwd=self.main)
        self.git("config", "extensions.worktreeConfig", "true", cwd=self.main)
        self.git(
            "-c", "user.name=t", "-c", "user.email=t@example.com",
            "commit", "-q", "--allow-empty", "-m", "x", cwd=self.main,
        )
        self.git("worktree", "add", "-q", str(self.worktree), cwd=self.main)

    def set_path(self, value, cwd):
        self.git("config", "--worktree", "core.hooksPath", value, cwd=cwd)

    def test_unset_is_inactive(self):
        self.assertFalse(check.hooks_active(self.main))
        self.assertFalse(check.hooks_active(self.worktree))

    def test_relative_path(self):
        self.set_path("hooks", self.main)
        self.assertTrue(check.hooks_active(self.main))
        self.set_path("hooks", self.worktree)
        self.assertTrue(check.hooks_active(self.worktree))

    def test_worktree_naming_the_main_checkout_folder(self):
        self.set_path(str(self.main / "hooks"), self.worktree)
        self.assertTrue(check.hooks_active(self.worktree))

    def test_other_folders_are_inactive(self):
        for value in (str(self.main.parent / "hooks"), "other", ".git/hooks"):
            self.set_path(value, self.worktree)
            self.assertFalse(check.hooks_active(self.worktree), value)


if __name__ == "__main__":
    unittest.main()
