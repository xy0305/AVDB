#!/usr/bin/env python3
"""Source-level checks for default-landscape 115 playback (v14)."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"


def read(name: str) -> str:
    return (SRC / name).read_text(encoding="utf-8")


def test_player_defaults_to_landscape():
    player = read("AVDB115PlayerViewController.m")
    playback = read("AVDB115Playback.m")
    header = read("AVDB115Playback.h")
    assert "AVDB115Playback.h" in player
    assert "supportedInterfaceOrientations" in player
    assert "preferredInterfaceOrientationForPresentation" in player
    assert "playerWillAppearInView" in player
    assert "playerWillDisappearFromView" in player
    assert "UIInterfaceOrientationMaskLandscape" in playback
    assert "requestGeometryUpdateWithPreferences" in playback
    assert "UIWindowSceneGeometryPreferencesIOS" in playback
    assert "setNeedsUpdateOfSupportedInterfaceOrientations" in playback
    assert "playerOrientationMask" in header


def test_chrome_hidden_during_playback_and_restored():
    playback = read("AVDB115Playback.m")
    detail = read("AVDB115DetailActions.m")
    assert "setPlaybackChromeHidden:hidden" in playback
    assert "setFloatingButtonHidden:hidden" in playback
    assert "setSuppressed:hidden" in playback
    assert "playerWillDisappearFromView" in playback
    assert "setChromeHidden:YES" in playback
    assert "setChromeHidden:NO" in playback
    assert "playbackChromeHidden" in detail
    # Early-out keeps the v6 chips hidden while the player is up.
    assert "if (self.playbackChromeHidden)" in detail


def test_app_delegate_hook_only_while_player_presented():
    tweak = read("Tweak.m")
    assert "application:supportedInterfaceOrientationsForWindow:" in tweak
    assert "isPlayerPresented" in tweak
    assert "AVDB115OrigAppOrient" in tweak
    # Pass-through when the plugin player is not up (do not force official players).
    assert "if (AVDB115OrigAppOrient) return AVDB115OrigAppOrient" in tweak.replace("\n", " ")


def test_push_path_not_regressed():
    intercept = read("AVDB115HttpIntercept.m")
    harvest = read("AVDB115FileCacheHarvest.m")
    detail = read("AVDB115DetailActions.m")
    tweak = read("Tweak.m")
    assert "[AVDB115HttpIntercept install]" in tweak
    assert "getMovieMagnets(" not in intercept
    # Diagnostic dialog and harvest remain.
    assert "diagnosticLine" in detail and "不会请求带签名的磁力接口" in detail
    assert "harvest" in harvest.lower()
    # Tweak still installs intercept before/with detail actions.
    assert tweak.find("[AVDB115HttpIntercept install]") < tweak.find("[AVDB115DetailActions install]")


def main():
    tests = [
        test_player_defaults_to_landscape,
        test_chrome_hidden_during_playback_and_restored,
        test_app_delegate_hook_only_while_player_presented,
        test_push_path_not_regressed,
    ]
    for fn in tests:
        fn()
        print(f"PASS {fn.__name__}")
    print("PASS: default landscape 115 player (source policy)")


if __name__ == "__main__":
    main()
