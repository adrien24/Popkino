#!/bin/bash
# FORK: chemins Popkino (binaire interne conservé)
chmod +x /usr/bin/popkino
chmod +x /opt/popkino/plezy
chmod +x /opt/popkino/lib/crashpad_handler

if command -v gtk-update-icon-cache &> /dev/null; then
    gtk-update-icon-cache -f -t /usr/share/icons/hicolor || true
fi

if command -v update-desktop-database &> /dev/null; then
    update-desktop-database /usr/share/applications || true
fi
