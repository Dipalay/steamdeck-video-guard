#!/bin/bash
echo "Stopping and disabling Steam Deck Video Guard..."
systemctl --user disable --now deck-video-guard.service 2>/dev/null || true
rm -f ~/.config/systemd/user/deck-video-guard.service
rm -f ~/.local/bin/deck-video-guard.py
systemctl --user daemon-reload
echo "✅ Steam Deck Video Guard has been completely removed."
