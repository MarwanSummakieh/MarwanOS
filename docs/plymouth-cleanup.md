Plymouth cleanup after display recovery
======================================

Candidate6's offline installer and installed-system boot worked, but its full
boot journal contained an enforcing AVC during link-scrub cleanup. A kernel-only
journal query missed the audit transport, so it cannot establish a clean AVC gate.

The original event was audit(1791326751.233:400), plymouthd PID1635 requesting
dac_override. A private VM reproduction under the actual plymouthd_t domain,
with SELinux still Enforcing, supplied syscall/path evidence:

    openat("/dev/tty1", flags=0x902) = -EACCES
    tty owner=player(1000), group=tty(5), mode=0600

The daemon had already deactivated and released DRM so greetd could restart.
Normal quit then switched through the detailed text theme and reopened the
terminal that the player's session now owned. That access needed a permission
the Plymouth domain correctly lacked.

The final post-session cleanup uses `plymouth quit --retain-splash`. The daemon
still exits, but the already frozen splash does not switch to the detailed theme
and reopen tty1. Early cleanup before restarting the session is unchanged. A
failed final quit reports an error and nonzero status while the existing EXIT
trap keeps greetd restored. Terminal ownership/mode and SELinux policy are unchanged.

Native comparison on candidate6 used a new disposable overlay over the preserved
installed VM. Each trial started the daemon while tty1 was root-owned, deactivated
it, restarted greetd, and waited for tty1 to become player-owned/0600. Normal quit
reproduced the denied reopen; retained quit exited without a new enforcing AVC.
Both left no daemon, and retained cleanup left greetd active, the image-owned
readiness check passing, SELinux Enforcing and zero failed system units.

`tests/test_link_scrub_cleanup.py` executes the recovery script with a terminal
ownership lifecycle fixture, demonstrates that the previous cleanup fails, and
checks that cleanup failure cannot be reported as successful reaping or remove
the restored session. It complements the actual SELinux VM trial; it does not
emulate SELinux. Final immutable media still requires a fresh installation and
full-journal AVC check after this source change is baked into the image.
