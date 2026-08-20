#!/usr/bin/env python3
"""CI guardrail (T126): flags AppLogger calls that look like they might log
sensitive data unfiltered.

This is a cheap heuristic, not a full audit — it exists so a future PR that
reintroduces a leak like the ones found in the 2026-08-19/20 security audits
(a raw GPS coordinate, an unsanitized exception carrying the Gemini API key
via a failed HTTP request URL) fails CI automatically instead of only being
caught by chance during a manual review. False positives are expected and
acceptable: fix the wording so the check stops flagging it (e.g. wrap a raw
exception in sanitizeError(), or don't interpolate the value directly), or
adjust the patterns below if a match is genuinely not sensitive.

See AGENTS.md's "Never log secrets" rule.
"""
import re
import sys
from pathlib import Path

# Words that, if interpolated into an AppLogger call, suggest the raw value
# of something sensitive is being logged directly (as opposed to e.g. a
# boolean "was this resolved" flag, or a category tag).
SUSPICIOUS_KEYWORDS = re.compile(
    r"(latitude|longitude|password|apikey|api_key|secret|token|coordinate)",
    re.IGNORECASE,
)

# Common names for a caught exception/error object — logging one of these
# directly (unless via sanitizeError()) risks leaking anything the
# exception's toString() happens to include, e.g. a failed HTTP request URL
# containing an API key in its query string.
RAW_EXCEPTION_VAR = re.compile(
    r"\$\{?\s*(e|err|error|exception|ttsError|fallbackError|analysisError|nanoError)\b",
)


def find_calls(text: str):
    """Yield (line_no, call_text) for each AppLogger.<method>(...) call,
    using simple paren-depth matching (good enough for this codebase's
    call shapes; not a full Dart parser)."""
    for m in re.finditer(r"AppLogger\.\w+\(", text):
        start = m.end() - 1  # index of the opening '('
        depth = 0
        i = start
        while i < len(text):
            if text[i] == "(":
                depth += 1
            elif text[i] == ")":
                depth -= 1
                if depth == 0:
                    break
            i += 1
        call_text = text[m.start(): i + 1]
        line_no = text.count("\n", 0, m.start()) + 1
        yield line_no, call_text


SUPPRESSION_MARKER = "log-hygiene-ok"


def check_file(path: Path):
    lines = path.read_text().splitlines(keepends=True)
    text = "".join(lines)
    issues = []
    for line_no, call in find_calls(text):
        end_line_no = line_no + call.count("\n")
        # Suppression: `// log-hygiene-ok: <reason>` anywhere on the call's
        # lines, or the line right before it — for a deliberate, reviewed
        # case where a match is a genuine false positive (e.g. logging
        # only whether a value is null, not the value itself).
        context = "".join(lines[max(0, line_no - 5):end_line_no])
        if SUPPRESSION_MARKER in context:
            continue
        if SUSPICIOUS_KEYWORDS.search(call):
            issues.append((line_no, "logs a suspiciously-named value directly", call))
        if RAW_EXCEPTION_VAR.search(call) and "sanitizeError" not in call:
            issues.append((line_no, "logs a raw exception without sanitizeError()", call))
    return issues


def main() -> int:
    root = Path("lib")
    any_issues = False
    for path in sorted(root.rglob("*.dart")):
        for line_no, reason, call in check_file(path):
            any_issues = True
            print(f"{path}:{line_no}: {reason}")
            print(f"    {' '.join(call.split())}")
    if any_issues:
        print()
        print("Log hygiene check found possible issues above (see AGENTS.md's "
              '"Never log secrets" rule). If a match is a false positive, fix '
              "the wording so it's no longer flagged, or adjust the patterns "
              "in scripts/check_log_hygiene.py.")
        return 1
    print("Log hygiene check: no issues found.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
