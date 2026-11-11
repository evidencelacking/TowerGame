"""Finds likely credentials. Used by the pre-commit check."""
import re

PATTERNS = {
    "private-key": r"-----BEGIN [A-Z ]*PRIVATE KEY-----",
    "github-token": r"\b(ghp|gho|ghs|ghu)_[A-Za-z0-9]{20,}|\bgithub_pat_[A-Za-z0-9_]{20,}",
    "api-key": r"\bsk-[A-Za-z0-9_-]{20,}",
    "aws-key": r"\bAKIA[0-9A-Z]{16}\b",
    "assigned-secret": r"(?i)\b(password|passwd|secret|api[_-]?key|token)\b\s*[:=]\s*['\"]?[^\s'\"]{8,}",
    "url-login": r"[a-z][a-z0-9+.-]*://[^\s/:@]+:[^\s/:@]+@",
}
COMPILED = {name: re.compile(pattern) for name, pattern in PATTERNS.items()}


def find_secrets(text):
    """Returns the names of the rules that matched, without the matched text."""
    return sorted(name for name, pattern in COMPILED.items() if pattern.search(text))
