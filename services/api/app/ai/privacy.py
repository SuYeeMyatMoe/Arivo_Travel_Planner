"""PrivacyGateway: every model call passes through here.

INPUT → PII classifier → mask (<PERSON_1>, <PASSPORT_1>, …) → policy check → [model] → output validation → rehydrate.
The token map is encrypted at rest (Fernet) and never sent to a model provider. Payment card numbers are refused
outright: they must never reach a prompt, a log or the database (PSP tokenisation handles cards).
"""

from __future__ import annotations

import base64
import hashlib
import json
import re
from dataclasses import dataclass, field

from cryptography.fernet import Fernet

# Order matters: more specific patterns first. Each pattern yields spans that get a typed token.
PATTERNS: list[tuple[str, re.Pattern[str]]] = [
    ("EMAIL", re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b")),
    ("CARD", re.compile(r"\b(?:\d[ -]?){13,19}\b")),
    ("PASSPORT", re.compile(r"\b(?:passport(?:\s*(?:no\.?|number|#))?\s*[:#]?\s*)([A-Z]{1,2}\d{6,8})\b", re.I)),
    # phones: international (+CC …), local with separators, or bare local numbers starting with 0 (e.g. 0123456789)
    ("PHONE", re.compile(r"(?<![\w<])(?:\+\d{1,3}[\s-]?\(?\d{1,4}\)?[\s-]?\d{3,4}[\s-]?\d{3,4}|\(?0\d{1,3}\)?[\s-]\d{3,4}[\s-]?\d{3,4}|0\d{8,11})(?!\w)")),
    ("BOOKING", re.compile(r"\b(?:booking|reservation|confirmation|pnr|ref(?:erence)?)(?:\s*(?:no\.?|number|code|#))?\s*[:#]?\s*([A-Z0-9]{5,10})\b", re.I)),
    ("ADDRESS", re.compile(r"\b\d{1,5}(?:-\d{1,4}){0,3}\s+[A-Z][a-z]+(?:\s[A-Z][a-z]+)*\s(?:Street|St|Road|Rd|Avenue|Ave|Jalan|Lorong|Chome|Dori)\b")),
    ("PERSON", re.compile(r"\b(?i:my name is|i am|i'm|this is|traveller|traveler|passenger|guest|mr\.?|ms\.?|mrs\.?)\s+([A-Z][a-z]+(?:\s[A-Z][a-z]+){0,2})\b")),
]


def _luhn(digits: str) -> bool:
    d = [int(c) for c in digits][::-1]
    total = sum(d[0::2]) + sum(sum(divmod(2 * x, 10)) for x in d[1::2])
    return total % 10 == 0


class PolicyViolation(Exception):
    pass


@dataclass
class Masked:
    text: str
    tokens: dict[str, str] = field(default_factory=dict)  # token → original (kept server-side only)

    def rehydrate(self, text: str) -> str:
        for tok, original in self.tokens.items():
            text = text.replace(tok, original)
        return text


class PrivacyGateway:
    def __init__(self, key_material: str):
        self._fernet = Fernet(base64.urlsafe_b64encode(hashlib.sha256(key_material.encode()).digest()))

    def mask(self, text: str, known: dict[str, str] | None = None) -> Masked:
        """Replace PII spans with typed tokens. `known` = {label: value} from structured data (e.g. booking refs)."""
        counters: dict[str, int] = {}
        tokens: dict[str, str] = {}
        reverse: dict[str, str] = {}

        def token_for(kind: str, value: str) -> str:
            if value in reverse:
                return reverse[value]
            counters[kind] = counters.get(kind, 0) + 1
            tok = f"<{kind}_{counters[kind]}>"
            tokens[tok] = value
            reverse[value] = tok
            return tok

        out = text
        for label, value in (known or {}).items():
            if value and value in out:
                out = out.replace(value, token_for(label.upper(), value))
        for kind, pat in PATTERNS:
            def repl(m: re.Match[str], kind: str = kind) -> str:
                value = m.group(1) if m.groups() and m.group(1) else m.group(0)
                if kind == "CARD":
                    digits = re.sub(r"\D", "", value)
                    if not (13 <= len(digits) <= 19 and _luhn(digits)):
                        return m.group(0)
                    raise PolicyViolation("Card numbers are never sent to AI. Use the secure payment sheet instead.")
                if kind == "PHONE" and len(re.sub(r"\D", "", value)) < 8:
                    return m.group(0)
                return m.group(0).replace(value, token_for(kind, value))
            out = pat.sub(repl, out)
        return Masked(text=out, tokens=tokens)

    def seal(self, masked: Masked) -> bytes:
        """Encrypt a token map for storage (e.g. alongside an agent conversation). Never logged, never sent to models."""
        return self._fernet.encrypt(json.dumps(masked.tokens).encode())

    def unseal(self, blob: bytes) -> dict[str, str]:
        return json.loads(self._fernet.decrypt(blob))

    @staticmethod
    def untrusted(label: str, content: str, limit: int = 6000) -> str:
        """Wrap retrieved web/review/social text so the model treats it as data. Instruction-like text inside stays inert."""
        clean = content.replace("<untrusted", "&lt;untrusted").replace("</untrusted", "&lt;/untrusted")[:limit]
        return f'<untrusted source="{label}">\n{clean}\n</untrusted>'
