"""Exercise the extracted iOS IPA layout without redistributing game files.

Run from the repository root:
    python tests/ipa_input_test.py
"""

import os
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
sys.path.insert(0, os.path.join(ROOT, "tools"))

import build  # noqa: E402
import patches  # noqa: E402


def put(path, content=""):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as stream:
        stream.write(content)


def test_ios_ipa_layout():
    with tempfile.TemporaryDirectory() as root:
        game = os.path.join(root, "Payload", "Balatro.app", "game")
        put(os.path.join(game, "main.lua"), "-- test fixture\n")
        put(os.path.join(game, "version.jkr"),
            "1.0.1o-FULL [M]\n1.0.1o\nPROD_mobile\n")
        os.makedirs(os.path.join(game, "resources"))
        os.makedirs(os.path.join(game, "localization"))

        found = build._find_extracted_game_code_folder(root)
        assert found == game, (found, game)
        assert build._find_extracted_source_folder(root, "resources", found) == os.path.join(game, "resources")
        assert build._find_extracted_source_folder(root, "localization", found) == os.path.join(game, "localization")

        files = patches.read_game(found)
        assert patches.game_version(files) == "1.0.1o"
        assert patches.game_target(files) == "mobile"


def test_balatro_plus_variant_adapter():
    game = {
        "version.jkr": b"1.0.1o-FULL [M]\\n1.0.1o\\nPROD_mobile\\n",
        "functions/UI_definitions.lua": (
            b"local loc_options = localize(_suit, 'collabs')\\n"
            b"['The Witcher'] = {}\\n"
            b"['Critical Role'] = {}\\n"
            b"['Dave the Diver'] = {}\\n"
        ),
        "globals.lua": b"mobile globals",
    }
    assert patches._is_balatro_plus_mobile(game)

    original = """    self.F_HIDE_BETA_LANGS = nil
    self.F_TOUCH_MOUSE = nil
    self.F_HIDE_LOADING_BAR = nil

    if love.system.getOS() == 'iOS' or love.system.getOS() == 'Android' then
        self.F_SAVE_TIMER = 10
        self.F_DISCORD = nil
        self.F_ENGLISH_ONLY = false
        self.F_CRASH_REPORTS = false
        self.F_SOUND_THREAD = false
        self.F_QUIT_BUTTON = false
        self.F_MOBILE = true
        self.F_LINKTREE = true
        self.F_HIDE_LOADING_BAR = true
        self.F_VIDEO_SETTINGS = false
    end

    if love.system.getPlatform and love.system.getPlatform() == 'tvos' then
        self.F_CONTROLLER_REQUIRED = true
    end
"""
    adapted = patches._adapt_balatro_plus_mobile_globals(original.encode()).decode()
    assert "self.F_TOUCH_MOUSE" not in adapted
    assert "self.F_HIDE_LOADING_BAR" not in adapted
    assert "self.F_VERTICAL_SETTINGS = false" in adapted
    assert "self.F_VERTICAL_SETTINGS = true" in adapted
    assert "self.F_MOBILE_UI = true" in adapted
    assert "self.F_EXTERNAL_LINKS = false" in adapted
    assert "self.F_HAPTIC = true" in adapted
    assert "self.F_SAVE_TIMER = 5" in adapted
    assert "self.F_QUIT_BUTTON = false" in adapted
    assert "self.F_CONTROLLER_REQUIRED = true" in adapted

    non_mobile = dict(game)
    non_mobile["version.jkr"] = b"1.0.1o-FULL\\n1.0.1o\\nPROD_PC_Console"
    assert not patches._is_balatro_plus_mobile(non_mobile)


def test_desktop_and_android_layouts():
    with tempfile.TemporaryDirectory() as root:
        put(os.path.join(root, "main.lua"), "-- desktop fixture\n")
        put(os.path.join(root, "version.jkr"), "1.0.1o-FULL\n1.0.1o\nPROD_PC_Console\n")
        os.makedirs(os.path.join(root, "resources"))
        assert build._find_extracted_game_code_folder(root) == root
        assert build._find_extracted_source_folder(root, "resources", root) == os.path.join(root, "resources")

    with tempfile.TemporaryDirectory() as root:
        assets = os.path.join(root, "assets")
        put(os.path.join(assets, "main.lua"), "-- android fixture\n")
        put(os.path.join(assets, "version.jkr"), "1.0.1o-FULL [M]\n1.0.1o\nPROD_mobile\n")
        os.makedirs(os.path.join(assets, "resources"))
        assert build._find_extracted_game_code_folder(root) == assets
        assert build._find_extracted_source_folder(root, "resources", assets) == os.path.join(assets, "resources")


if __name__ == "__main__":
    test_ios_ipa_layout()
    test_balatro_plus_variant_adapter()
    test_desktop_and_android_layouts()
    print("all IPA input and Balatro+ adapter tests passed")
