#!/usr/bin/env python3
"""Validate the native toast JSON built by game_pad_bridge_main.c.

Reconstructs the payload exactly as game_bridge_notify_native_with_icon()
does (macro literals + the four %s substitutions + the notify serial), then
parses it with a real JSON parser and checks the fields the console needs.
Exits non-zero on the first problem.
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, "payload", "game_pad_bridge_main.c")
DEFINES = ("GAME_BRIDGE_ICON_FILE", "POORDS4_DATA_DIR")
MACROS = ("POORDS4_NOTIFY_TEMPLATE_HEAD", "POORDS4_NOTIFY_TEMPLATE_MID",
          "POORDS4_NOTIFY_TEMPLATE_SUB", "POORDS4_NOTIFY_TEMPLATE_BODY",
          "POORDS4_NOTIFY_TEMPLATE_END")


def fail(message):
    print(f"FAIL: {message}")
    sys.exit(1)


def read_source():
    with open(SOURCE, "r", encoding="utf-8") as handle:
        return handle.read()


def define_body(text, name):
    match = re.search(r"#define\s+" + name + r"\s+(.*)", text)
    if not match:
        fail(f"missing #define {name}")
    return match.group(1).strip()


def decode(literal):
    raw = literal[1:-1]
    return raw.replace('\\\\', '\\').replace('\\"', '"')


def expand(text, value):
    for _ in range(8):
        replaced = value
        for name in DEFINES:
            replaced = replaced.replace(name, define_body(text, name))
        if replaced == value:
            break
        value = replaced
    literals = re.findall(r'"(?:[^"\\]|\\.)*"', value)
    if not literals:
        fail(f"no string literal in {value!r}")
    return "".join(decode(literal) for literal in literals)


def macro_text(text, name):
    match = re.search(r"#define\s+" + name + r"\s+(.*?)(?=\n\S|\Z)", text,
                      re.S)
    if not match:
        fail(f"missing macro {name}")
    return match.group(1).replace("\\\n", "\n")


def build_payload(text, icon, body):
    # Mirrors the snprintf() in game_bridge_notify_native_with_icon(): the
    # macros are separated by the four %s placeholders (icon, body, icon,
    # body) and the template itself ends with the %u serial.
    template = ""
    for name in MACROS:
        if template:
            template += "%s"
        template += expand(text, macro_text(text, name))
    values = [icon, body, icon, body]
    parts = template.split("%s")
    if len(parts) != len(values) + 1:
        fail(f"template has {len(parts) - 1} %s placeholders, expected 4")
    out = ""
    for index, part in enumerate(parts):
        out += part
        if index < len(values):
            out += values[index]
    return out.replace("%u", "900001")


def check(text):
    icon = expand(text, macro_text(text, "POORDS4_NOTIFY_ICON_URL"))
    if not icon.startswith('{"type":"Url"'):
        fail(f"unexpected icon spec {icon!r}")
    for body in ("3 controller active", "PoorDS4: reset requested"):
        payload = build_payload(text, icon, body)
        try:
            parsed = json.loads(payload)
        except json.JSONDecodeError as error:
            fail(f"payload is not valid JSON ({error}); payload={payload}")
        view = parsed.get("rawData", {}).get("viewData", {})
        preview = (parsed.get("rawData", {}).get("platformViews", {})
                   .get("previewDisabled", {}).get("viewData", {}))
        checks = [
            (view.get("icon", {}).get("type") == "Url",
             "rawData.viewData.icon is not the Url icon"),
            (view.get("message", {}).get("body") == body,
             "rawData.viewData.message.body does not carry the message"),
            (view.get("subMessage", {}).get("body") == "PoorDS4",
             "rawData.viewData.subMessage.body is not PoorDS4"),
            (preview.get("icon", {}).get("type") == "Url",
             "platformViews.previewDisabled.viewData.icon is not the Url icon"),
            (preview.get("message", {}).get("body") == body,
             "platformViews.previewDisabled.viewData.message.body is wrong"),
            (parsed.get("createdDateTime") is not None,
             "createdDateTime is missing"),
            (parsed.get("localNotificationId") == "900001",
             "localNotificationId is missing"),
        ]
        for ok, message in checks:
            if not ok:
                fail(message)
        print(f"ok: {len(payload)} bytes, body={body!r}")


def main():
    text = read_source()
    check(text)
    print("notification payloads are valid")


if __name__ == "__main__":
    main()
