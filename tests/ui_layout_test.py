"""Guard iOS portrait UI spacing and menu sizing in the source patches.

These checks catch parameter mistakes. They do not replace rendering or real-device
checks. For automated screenshot geometry use tools/headless/run.py on Windows.
"""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
CONFIG = (ROOT / 'src/portrait_config.lua').read_text(encoding='utf-8')


def ui_value(name):
    m = re.search(r'\b' + re.escape(name) + r'\s*=\s*([0-9.]+)\s*,', CONFIG)
    assert m, f'missing layout option {name}'
    return float(m.group(1))


def check_action_row():
    offset = ui_value('action_row_offset_ios')
    assert 1.2 <= offset <= 1.8, 'iOS action row offset beyond intended range'
    for target in ('portrait', 'portrait-mobile'):
        patch = (ROOT / f'patches/{target}/globals.lua.patch').read_text(encoding='utf-8')
        assert "love.system.getOS() == 'iOS'" in patch
        assert 'PORTRAIT_CONFIG.action_row_offset_ios' in patch
        assert 'swipe_only and 0.02' in patch
        assert 'or 0.45' in patch, 'non-iOS position must remain unchanged'


def check_run_setup():
    scale = ui_value('run_setup_tab_scale')
    assert 1 < scale <= 1.08, 'three-tab bar may exceed phone width'
    assert 0.5 < ui_value('run_setup_tab_text_scale') <= 0.56
    assert 5.0 < ui_value('run_setup_play_minw') <= 5.5
    assert 0.8 < ui_value('run_setup_play_minh') <= 1.1
    assert ui_value('run_setup_back_desc_scale') > 0.72
    for target in ('portrait', 'portrait-mobile'):
        patch = (ROOT / f'patches/{target}/functions/UI_definitions.lua.patch').read_text(encoding='utf-8')
        for marker in ('run_setup_tab_scale', 'run_setup_tab_text_scale',
                       'run_setup_font_scale', 'run_setup_play_minw', 'run_setup_minh'):
            assert marker in patch, f'{target}: {marker} missing'
    # Conservative estimate from the supplied 706px-wide menu screenshot.
    screen_width, panel_width = 706, 618
    assert (screen_width - panel_width*scale)/2 >= 18, 'menu may hit screen edge'


if __name__ == '__main__':
    check_action_row()
    check_run_setup()
    print('UI layout regression checks passed')
