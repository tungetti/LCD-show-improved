if [ -f "$HOME/.profile" ]; then
    . "$HOME/.profile"
fi

if [ -z "${SSH_CONNECTION:-}" ] && [ -z "${DISPLAY:-}" ] && [ "$(tty 2>/dev/null)" = "/dev/tty1" ]; then
    export FRAMEBUFFER=/dev/fb1
    startx 2> "$HOME/.xorg-lcd.log"
fi
