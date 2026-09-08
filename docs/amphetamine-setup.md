# Amphetamine setup and rollback

Agent Helper uses Amphetamine's supported AppleScript interface. It does not call `sudo`, edit power-management settings, or install its own privileged helper.

## Required setup

1. Install Amphetamine from the Mac App Store.
2. In Amphetamine's session preferences, allow display sleep so the screen can turn off.
3. Enable Closed-Display Mode by turning off “Allow system sleep when display is closed.” Acknowledge Amphetamine's warning and choose not to show it again so later AppleScript calls do not block.
4. Configure Amphetamine to end its session when battery falls to 30% or lower.
5. On Apple silicon, install Power Protect only through Amphetamine's own prompt. It should create:
   - `~/Library/Application Scripts/com.if.Amphetamine/powerProtect.scpt`
   - `/private/etc/sudoers.d/amphetamine_powerProtect`

Run the non-lid automation check:

```sh
sh scripts/verify_amphetamine.sh
```

## Physical closed-lid check

Keep the Mac on a hard, ventilated surface and out of any bag. Prepare a counter:

```sh
sh scripts/closed_lid_canary.sh prepare
```

Close the lid for at least two minutes, reopen it, and verify:

```sh
sh scripts/closed_lid_canary.sh preflight
# Only continue if the separate preflight reports PASS.
# Close the lid for at least two minutes, then reopen it.
sh scripts/closed_lid_canary.sh verify
```

The counter runs in an owned detached tmux session, not as a child of the launching command. The separate preflight proves it survives after `prepare` exits. The verifier then requires at least 120 seconds of wall time and 90 active counter ticks. A sleeping Mac advances wall time but not the counter, so sleep cannot produce a false pass.

## Rollback and emergency cleanup

End the test and restore normal sleep behavior at any time:

```sh
sh scripts/closed_lid_canary.sh cleanup
osascript -e 'tell application "Amphetamine" to if (session is active) then end session'
```

To uninstall Power Protect, use Amphetamine’s menu: **Feedback & Support → Uninstall Scripts…**. Do not delete or broaden its sudoers entry manually. Amphetamine itself can then be removed normally from Applications if Agent Helper is no longer wanted.
