# Lock the session with hyprlock unless it is already locked.
pidof hyprlock >/dev/null || exec hyprlock
